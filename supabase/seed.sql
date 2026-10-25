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
