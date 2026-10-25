-- Storage bucket + policies, GeoJSON nearby_hazards, broader RPC grants.

-- ---------------------------------------------------------------------------
-- hazard-photos storage
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

-- ---------------------------------------------------------------------------
-- nearby_hazards returns GeoJSON location for mobile clients
-- ---------------------------------------------------------------------------

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

-- Allow anonymous confirmations to trigger verification recompute.
grant execute on function public.recompute_hazard_verification(uuid)
  to anon, authenticated, service_role;
