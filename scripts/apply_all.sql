-- PathAble initial schema
-- Requires PostGIS. Apply with the Supabase SQL editor or CLI.

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enumerations
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.hazard_category as enum (
    'blocked_sidewalk',
    'pothole_or_damaged_pavement',
    'missing_or_damaged_curb_ramp',
    'stairs_or_inaccessible_path',
    'broken_elevator',
    'construction_closure',
    'poor_lighting',
    'excessive_noise',
    'pedestrian_signal_problem',
    'other'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.hazard_severity as enum (
    'low',
    'moderate',
    'high',
    'critical'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.hazard_status as enum (
    'provisional',
    'active',
    'resolved',
    'stale',
    'under_review'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.confirmation_response as enum (
    'still_present',
    'resolved',
    'unable_to_determine'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.evidence_type as enum (
    'visual',
    'traveled_through',
    'other'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.moderation_status as enum (
    'open',
    'dismissed',
    'action_taken'
  );
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.hazards (
  id uuid primary key default gen_random_uuid(),
  category public.hazard_category not null,
  severity public.hazard_severity not null,
  status public.hazard_status not null default 'provisional',
  description text,
  location geography(point, 4326) not null,
  affected_geometry geometry(geometry, 4326),
  confidence_score numeric(4,3) not null default 0.350
    check (confidence_score >= 0 and confidence_score <= 1),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  last_confirmed_at timestamptz,
  expires_at timestamptz,
  resolved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  photo_path text,
  is_demonstration boolean not null default false
);

create index if not exists hazards_location_gix
  on public.hazards using gist (location);

create index if not exists hazards_status_created_idx
  on public.hazards (status, created_at desc);

create index if not exists hazards_category_idx
  on public.hazards (category);

create table if not exists public.hazard_confirmations (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  response public.confirmation_response not null,
  evidence_type public.evidence_type,
  created_at timestamptz not null default timezone('utc', now()),
  -- Server-validated proximity flag; raw continuous location history is not stored.
  was_near_hazard boolean,
  client_distance_meters numeric(10,2)
);

create index if not exists hazard_confirmations_hazard_idx
  on public.hazard_confirmations (hazard_id, created_at desc);

-- Application/server functions enforce the 24-hour reconfirmation window.
-- This index supports efficient lookups for that check.
create index if not exists hazard_confirmations_user_hazard_idx
  on public.hazard_confirmations (hazard_id, user_id, created_at desc)
  where user_id is not null;

create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  profile_json jsonb not null default '{}'::jsonb,
  sync_enabled boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.saved_destinations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  location geography(point, 4326) not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists saved_destinations_user_idx
  on public.saved_destinations (user_id);

create table if not exists public.report_moderation (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  reporter_user_id uuid references auth.users(id) on delete set null,
  reason text not null,
  status public.moderation_status not null default 'open',
  created_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz
);

create index if not exists report_moderation_status_idx
  on public.report_moderation (status, created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers / triggers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists hazards_set_updated_at on public.hazards;
create trigger hazards_set_updated_at
before update on public.hazards
for each row execute function public.set_updated_at();

-- Nearby hazards for the mobile app (GeoJSON location for easy client parse).
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
  is_demonstration boolean
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
    h.is_demonstration
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

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.hazards enable row level security;
alter table public.hazard_confirmations enable row level security;
alter table public.user_preferences enable row level security;
alter table public.saved_destinations enable row level security;
alter table public.report_moderation enable row level security;

-- Hazards: public read of non-private fields; insert for anon/authenticated;
-- update limited to owner or via privileged server functions later.
drop policy if exists hazards_select_public on public.hazards;
create policy hazards_select_public
  on public.hazards
  for select
  to anon, authenticated
  using (true);

drop policy if exists hazards_insert_authenticated_or_anon on public.hazards;
create policy hazards_insert_authenticated_or_anon
  on public.hazards
  for insert
  to anon, authenticated
  with check (
    (created_by is null and auth.uid() is null)
    or created_by = auth.uid()
  );

drop policy if exists hazards_update_owner on public.hazards;
create policy hazards_update_owner
  on public.hazards
  for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

-- Confirmations: anyone can read aggregates indirectly via hazard status;
-- inserts allowed; no public user email exposure (user_id is opaque uuid).
drop policy if exists confirmations_select_public on public.hazard_confirmations;
create policy confirmations_select_public
  on public.hazard_confirmations
  for select
  to anon, authenticated
  using (true);

drop policy if exists confirmations_insert on public.hazard_confirmations;
create policy confirmations_insert
  on public.hazard_confirmations
  for insert
  to anon, authenticated
  with check (
    (user_id is null and auth.uid() is null)
    or user_id = auth.uid()
  );

-- Preferences / destinations: owner only.
drop policy if exists preferences_owner on public.user_preferences;
create policy preferences_owner
  on public.user_preferences
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists destinations_owner on public.saved_destinations;
create policy destinations_owner
  on public.saved_destinations
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Moderation flags: insert for reporters; select/update reserved for service role.
drop policy if exists moderation_insert on public.report_moderation;
create policy moderation_insert
  on public.report_moderation
  for insert
  to anon, authenticated
  with check (
    (reporter_user_id is null and auth.uid() is null)
    or reporter_user_id = auth.uid()
  );

drop policy if exists moderation_select_own on public.report_moderation;
create policy moderation_select_own
  on public.report_moderation
  for select
  to authenticated
  using (reporter_user_id = auth.uid());

-- Storage bucket policies should be configured in the Supabase dashboard:
-- bucket: hazard-photos, max size ~5MB, mime types image/jpeg,image/png,image/webp
comment on table public.hazards is
  'Community pedestrian infrastructure hazard reports. Do not expose reporter emails.';


-- ===== NEXT FILE =====

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

-- ---------------------------------------------------------------------------
-- Storage: hazard-photos bucket + policies
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'hazard-photos',
  'hazard-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists hazard_photos_select on storage.objects;
create policy hazard_photos_select
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'hazard-photos');

drop policy if exists hazard_photos_insert on storage.objects;
create policy hazard_photos_insert
  on storage.objects
  for insert
  to anon, authenticated
  with check (bucket_id = 'hazard-photos');

drop policy if exists hazard_photos_update_own on storage.objects;
create policy hazard_photos_update_own
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'hazard-photos' and (owner = auth.uid() or owner is null))
  with check (bucket_id = 'hazard-photos');


-- ===== NEXT FILE =====

-- Demonstration seed for a configured Supabase project (Riverstone / Sugar Land).
-- These rows are explicitly marked is_demonstration = true.

insert into public.hazards (
  id, category, severity, status, description, location,
  confidence_score, last_confirmed_at, is_demonstration
) values
(
  '11111111-1111-1111-1111-111111111101',
  'blocked_sidewalk',
  'high',
  'active',
  '[DEMO] Construction barriers blocking a sidewalk near University Blvd. Not a verified real-world report.',
  st_setsrid(st_makepoint(-95.58240, 29.54960), 4326)::geography,
  0.820,
  timezone('utc', now()) - interval '1 hour',
  true
),
(
  '11111111-1111-1111-1111-111111111102',
  'stairs_or_inaccessible_path',
  'critical',
  'active',
  '[DEMO] Stair-only connector on a pedestrian path with no ramp.',
  st_setsrid(st_makepoint(-95.58120, 29.55040), 4326)::geography,
  0.900,
  timezone('utc', now()) - interval '3 hours',
  true
),
(
  '11111111-1111-1111-1111-111111111103',
  'missing_or_damaged_curb_ramp',
  'high',
  'provisional',
  '[DEMO] Reported missing curb ramp at a crosswalk in Riverstone. Provisionally reported.',
  st_setsrid(st_makepoint(-95.58510, 29.54720), 4326)::geography,
  0.450,
  null,
  true
),
(
  '11111111-1111-1111-1111-111111111104',
  'broken_elevator',
  'critical',
  'active',
  '[DEMO] Elevator at Demo University Blvd Shops out of service.',
  st_setsrid(st_makepoint(-95.58720, 29.55120), 4326)::geography,
  0.780,
  timezone('utc', now()) - interval '40 minutes',
  true
),
(
  '11111111-1111-1111-1111-111111111105',
  'poor_lighting',
  'moderate',
  'provisional',
  '[DEMO] Poorly lit trail segment after dusk near the park path.',
  st_setsrid(st_makepoint(-95.58180, 29.54650), 4326)::geography,
  0.400,
  null,
  true
),
(
  '11111111-1111-1111-1111-111111111106',
  'blocked_sidewalk',
  'high',
  'active',
  '[DEMO] Community-style report at The Shops at Telfair, 12920 University Blvd. The parking-lot crossing is unclear, and outdoor seating or signage may obstruct the pedestrian path. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.6489237, 29.5955017), 4326)::geography,
  0.720,
  timezone('utc', now()) - interval '6 hours',
  true
),
(
  '11111111-1111-1111-1111-111111111107',
  'pedestrian_signal_problem',
  'critical',
  'active',
  '[DEMO] Community-style report at University Blvd and Commonwealth Blvd. The crosswalk is long and difficult for visually impaired pedestrians. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.6398278, 29.5591462), 4326)::geography,
  0.700,
  timezone('utc', now()) - interval '6 hours',
  true
),
(
  '11111111-1111-1111-1111-111111111108',
  'pedestrian_signal_problem',
  'high',
  'active',
  '[DEMO] Community-style report at University Blvd and New Territory Blvd. The intersection is wide and pedestrian guidance is limited. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.6486578, 29.5940148), 4326)::geography,
  0.660,
  timezone('utc', now()) - interval '6 hours',
  true
),
(
  '11111111-1111-1111-1111-111111111109',
  'stairs_or_inaccessible_path',
  'high',
  'provisional',
  '[DEMO] Community-style report near Telfair Central Park. A trail split is hard to follow and may hide an obstacle. Approximate pin near Telfair Central. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.65320, 29.59240), 4326)::geography,
  0.500,
  null,
  true
),
(
  '11111111-1111-1111-1111-111111111110',
  'stairs_or_inaccessible_path',
  'critical',
  'active',
  '[DEMO] Community-style report for the Telfair Lake trail bridge. Sharp turns, water nearby, and limited tactile guidance. Approximate pin in central Telfair. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.65560, 29.58920), 4326)::geography,
  0.550,
  timezone('utc', now()) - interval '6 hours',
  true
),
(
  '11111111-1111-1111-1111-111111111111',
  'pedestrian_signal_problem',
  'high',
  'active',
  '[DEMO] Community-style report for the Crossing at Telfair near Highway 6. A large parking lot has several vehicle conflict points and weak pedestrian wayfinding. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.64740, 29.60380), 4326)::geography,
  0.640,
  timezone('utc', now()) - interval '6 hours',
  true
),
(
  '11111111-1111-1111-1111-111111111112',
  'blocked_sidewalk',
  'moderate',
  'provisional',
  '[DEMO] Community-style report along University Commons. Driveways cross the sidewalk and pedestrian-vehicle interactions are busy. Approximate pin on University Blvd. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.6190438, 29.5522335), 4326)::geography,
  0.480,
  null,
  true
),
(
  '11111111-1111-1111-1111-111111111113',
  'blocked_sidewalk',
  'critical',
  'provisional',
  '[DEMO] Community-style report for a bus stop on University Blvd. The sidewalk connection is missing and the access path is grass or mud. Approximate stop pin. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.6210913, 29.5539660), 4326)::geography,
  0.500,
  null,
  true
),
(
  '11111111-1111-1111-1111-111111111114',
  'blocked_sidewalk',
  'high',
  'provisional',
  '[DEMO] Community-style report at the Riverstone H-E-B near University Blvd. Shopping carts and parking-lot traffic make the pedestrian path harder to follow. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.5826764, 29.5785263), 4326)::geography,
  0.600,
  null,
  true
),
(
  '11111111-1111-1111-1111-111111111115',
  'other',
  'critical',
  'active',
  '[DEMO] Community-style report at the Sugar Land Costco on Southwest Freeway. The parking lot is very large and wayfinding on foot is difficult. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.6434803, 29.5854859), 4326)::geography,
  0.620,
  timezone('utc', now()) - interval '6 hours',
  true
),
(
  '11111111-1111-1111-1111-111111111116',
  'blocked_sidewalk',
  'high',
  'provisional',
  '[DEMO] Community-style report at Sugar Land Town Square. Sidewalks get crowded and outdoor dining can block the walking path. Not a verified inspection.',
  st_setsrid(st_makepoint(-95.6222566, 29.5958438), 4326)::geography,
  0.580,
  null,
  true
)
on conflict (id) do nothing;

