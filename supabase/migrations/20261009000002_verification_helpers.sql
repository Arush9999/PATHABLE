-- Configurable hazard verification helpers (Phase 6 algorithm entry points).

create table if not exists public.verification_settings (
  id int primary key default 1 check (id = 1),
  still_present_to_active int not null default 2,
  resolved_votes_for_review int not null default 2,
  stale_after_days int not null default 14,
  critical_stale_after_days int not null default 30,
  updated_at timestamptz not null default timezone('utc', now())
);

insert into public.verification_settings (id)
values (1)
on conflict (id) do nothing;

alter table public.verification_settings enable row level security;

drop policy if exists verification_settings_read on public.verification_settings;
create policy verification_settings_read
  on public.verification_settings
  for select
  to anon, authenticated
  using (true);

-- Recompute status/confidence from confirmations. Intended for authenticated
-- clients and scheduled jobs. Does not permanently store location histories.
create or replace function public.recompute_hazard_verification(target_hazard uuid)
returns public.hazards
language plpgsql
security definer
set search_path = public
as $$
declare
  settings public.verification_settings%rowtype;
  hazard public.hazards%rowtype;
  still_count int;
  resolved_count int;
  age_days numeric;
  stale_limit int;
begin
  select * into settings from public.verification_settings where id = 1;
  select * into hazard from public.hazards where id = target_hazard for update;
  if not found then
    raise exception 'hazard not found';
  end if;

  select
    count(*) filter (where response = 'still_present'),
    count(*) filter (where response = 'resolved')
  into still_count, resolved_count
  from public.hazard_confirmations
  where hazard_id = target_hazard
    and created_at > timezone('utc', now()) - interval '30 days';

  age_days := extract(epoch from (timezone('utc', now()) - hazard.created_at)) / 86400.0;
  stale_limit := case
    when hazard.severity in ('high', 'critical') then settings.critical_stale_after_days
    else settings.stale_after_days
  end;

  if resolved_count >= settings.resolved_votes_for_review
     and resolved_count > still_count then
    hazard.status := 'under_review';
    hazard.confidence_score := greatest(0, hazard.confidence_score - 0.15);
  elsif still_count >= settings.still_present_to_active then
    hazard.status := 'active';
    hazard.confidence_score := least(1, 0.35 + still_count * 0.12);
    hazard.last_confirmed_at := timezone('utc', now());
  elsif age_days >= stale_limit and hazard.status in ('provisional', 'active') then
    -- Serious unresolved hazards become stale for re-verification, not silently removed.
    hazard.status := 'stale';
  end if;

  hazard.updated_at := timezone('utc', now());

  update public.hazards h
  set
    status = hazard.status,
    confidence_score = hazard.confidence_score,
    last_confirmed_at = hazard.last_confirmed_at,
    updated_at = hazard.updated_at
  where h.id = target_hazard;

  return hazard;
end;
$$;

revoke all on function public.recompute_hazard_verification(uuid) from public;
grant execute on function public.recompute_hazard_verification(uuid)
  to anon, authenticated, service_role;
