-- Add or remove a hazard when 25% of people who passed that spot agree.
-- 5 of 20 reports adds it. 5 of 20 "gone" votes removes it. Each person counts once.

alter table public.verification_settings
  add column if not exists passage_agreement_ratio numeric(4,3) not null default 0.250
    check (passage_agreement_ratio > 0 and passage_agreement_ratio <= 1);

update public.verification_settings
set passage_agreement_ratio = 0.250
where id = 1;

alter table public.hazards
  add column if not exists passer_count int not null default 0,
  add column if not exists reporter_count int not null default 0,
  add column if not exists removal_count int not null default 0;

create table if not exists public.hazard_passages (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists hazard_passages_hazard_idx
  on public.hazard_passages (hazard_id, created_at desc);

alter table public.hazard_passages enable row level security;

create or replace function public.recompute_hazard_verification(target_hazard uuid)
returns public.hazards
language plpgsql
security definer
set search_path = public
as $$
declare
  settings public.verification_settings%rowtype;
  hazard public.hazards%rowtype;
  passer_count int;
  reporter_count int;
  removal_count int;
  ratio numeric;
  window_start timestamptz := timezone('utc', now()) - interval '30 days';
begin
  select * into settings from public.verification_settings where id = 1;
  ratio := coalesce(settings.passage_agreement_ratio, 0.250);

  select * into hazard from public.hazards where id = target_hazard for update;
  if not found then
    raise exception 'hazard not found';
  end if;

  if hazard.is_demonstration then
    return hazard;
  end if;

  select count(distinct user_id) into reporter_count
  from (
    select h.created_by as user_id
    from public.hazards h
    where h.id = target_hazard
      and h.created_by is not null
      and h.created_at > window_start
    union
    select c.user_id
    from public.hazard_confirmations c
    where c.hazard_id = target_hazard
      and c.user_id is not null
      and c.response = 'still_present'
      and c.created_at > window_start
  ) reporters;

  select count(distinct user_id) into removal_count
  from public.hazard_confirmations c
  where c.hazard_id = target_hazard
    and c.user_id is not null
    and c.response = 'resolved'
    and c.created_at > window_start;

  select count(distinct user_id) into passer_count
  from (
    select p.user_id
    from public.hazard_passages p
    where p.hazard_id = target_hazard
      and p.created_at > window_start
    union
    select h.created_by
    from public.hazards h
    where h.id = target_hazard
      and h.created_by is not null
      and h.created_at > window_start
    union
    select c.user_id
    from public.hazard_confirmations c
    where c.hazard_id = target_hazard
      and c.user_id is not null
      and c.response in ('still_present', 'resolved')
      and c.created_at > window_start
  ) people;

  hazard.passer_count := passer_count;
  hazard.reporter_count := reporter_count;
  hazard.removal_count := removal_count;
  hazard.updated_at := timezone('utc', now());

  if passer_count = 0 then
    hazard.status := 'provisional';
    hazard.confidence_score := 0;
    hazard.resolved_at := null;
  elsif removal_count::numeric >= passer_count::numeric * ratio then
    hazard.status := 'resolved';
    hazard.confidence_score := least(1, removal_count::numeric / passer_count);
    hazard.resolved_at := coalesce(hazard.resolved_at, timezone('utc', now()));
  elsif reporter_count::numeric >= passer_count::numeric * ratio then
    hazard.status := 'active';
    hazard.confidence_score := least(1, reporter_count::numeric / passer_count);
    hazard.last_confirmed_at := timezone('utc', now());
    hazard.resolved_at := null;
  else
    hazard.status := 'provisional';
    hazard.confidence_score := least(1, reporter_count::numeric / passer_count);
    hazard.resolved_at := null;
  end if;

  update public.hazards h
  set
    status = hazard.status,
    confidence_score = hazard.confidence_score,
    last_confirmed_at = hazard.last_confirmed_at,
    resolved_at = hazard.resolved_at,
    passer_count = hazard.passer_count,
    reporter_count = hazard.reporter_count,
    removal_count = hazard.removal_count,
    updated_at = hazard.updated_at
  where h.id = target_hazard;

  return hazard;
end;
$$;

create or replace function public.record_hazard_passage(target_hazard uuid)
returns public.hazards
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  hazard public.hazards%rowtype;
begin
  if uid is null then
    raise exception 'Sign in required to record a passage';
  end if;

  select * into hazard from public.hazards where id = target_hazard;
  if not found then
    raise exception 'hazard not found';
  end if;

  if hazard.is_demonstration or hazard.status = 'resolved' then
    return hazard;
  end if;

  if not exists (
    select 1
    from public.hazard_passages p
    where p.hazard_id = target_hazard
      and p.user_id = uid
      and p.created_at > timezone('utc', now()) - interval '1 day'
  ) then
    insert into public.hazard_passages (hazard_id, user_id)
    values (target_hazard, uid);
  end if;

  return public.recompute_hazard_verification(target_hazard);
end;
$$;

create or replace function public.hazard_count_creator_passage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.created_by is not null and not new.is_demonstration then
    insert into public.hazard_passages (hazard_id, user_id)
    values (new.id, new.created_by);
    perform public.recompute_hazard_verification(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists hazards_count_creator_passage on public.hazards;
create trigger hazards_count_creator_passage
after insert on public.hazards
for each row execute function public.hazard_count_creator_passage();

revoke all on function public.recompute_hazard_verification(uuid) from public;
grant execute on function public.recompute_hazard_verification(uuid)
  to anon, authenticated, service_role;

revoke all on function public.record_hazard_passage(uuid) from public;
grant execute on function public.record_hazard_passage(uuid)
  to authenticated, service_role;

drop function if exists public.nearby_hazards(double precision, double precision, double precision);

create or replace function public.nearby_hazards(
  lat double precision,
  lng double precision,
  radius_meters double precision default 2500
)
returns table (
  id uuid,
  category public.hazard_category,
  severity public.hazard_severity,
  status public.hazard_status,
  description text,
  location jsonb,
  confidence_score numeric,
  created_at timestamptz,
  updated_at timestamptz,
  last_confirmed_at timestamptz,
  expires_at timestamptz,
  resolved_at timestamptz,
  created_by uuid,
  photo_path text,
  is_demonstration boolean,
  passer_count int,
  reporter_count int,
  removal_count int
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    h.id,
    h.category,
    h.severity,
    h.status,
    h.description,
    st_asgeojson(h.location::geometry)::jsonb as location,
    h.confidence_score,
    h.created_at,
    h.updated_at,
    h.last_confirmed_at,
    h.expires_at,
    h.resolved_at,
    h.created_by,
    h.photo_path,
    h.is_demonstration,
    h.passer_count,
    h.reporter_count,
    h.removal_count
  from public.hazards h
  where st_dwithin(
    h.location,
    st_setsrid(st_makepoint(lng, lat), 4326)::geography,
    radius_meters
  )
  and h.status <> 'resolved'
  order by st_distance(
    h.location,
    st_setsrid(st_makepoint(lng, lat), 4326)::geography
  );
$$;

grant execute on function public.nearby_hazards(double precision, double precision, double precision)
  to anon, authenticated;
