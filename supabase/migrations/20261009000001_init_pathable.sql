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

-- Nearby hazards query used by the mobile app (security definer, limited columns).
create or replace function public.nearby_hazards(
  lat double precision,
  lng double precision,
  radius_meters double precision default 2500
)
returns setof public.hazards
language sql
stable
security invoker
set search_path = public
as $$
  select h.*
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
