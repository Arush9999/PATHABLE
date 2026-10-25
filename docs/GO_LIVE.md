# PathAble go-live steps (1–5)

## Step 1 — Supabase backend (required once)

Project URL: `https://foqimgsjyvwunjmhklxt.supabase.co`.

1. Open [Supabase SQL Editor](https://supabase.com/dashboard/project/foqimgsjyvwunjmhklxt/sql/new).
2. Paste and run the entire file: `scripts/apply_all.sql`  
   (includes schema, `nearby_hazards` GeoJSON, verification RPC, **hazard-photos** bucket + policies, demo seed).
3. If you already applied an older SQL dump, also run:  
   `supabase/migrations/20261016000001_storage_geojson_grants.sql`
4. Auth → enable **Email** provider. For fastest demo signup, disable **Confirm email**.
5. Auth → enable **Google** provider. In Google Cloud Console create:
   - OAuth **Web** client (put its client ID in `.env` as `GOOGLE_WEB_CLIENT_ID`)
   - Android client (package `com.pathable.pathable` + your debug SHA-1)
   Paste the Web client ID + secret into Supabase Google provider settings.
   (Android-only — no iOS client needed.)

Verify: Table Editor shows `hazards`; Storage shows bucket `hazard-photos`.

## Step 2 — Maps / geocode / routing

Configure local `.env` (never commit):

- MapTiler streets style + `MAPTILER_API_KEY` + `GEOCODING_URL`
- Valhalla (required for live path/trail/sidewalk directions):
  - Host/desktop: `VALHALLA_URL=http://127.0.0.1:8002`
  - Android emulator: `VALHALLA_URL=http://10.0.2.2:8002`
  - Production: `VALHALLA_URL=https://routing.yourdomain.com`
- Google: `GOOGLE_WEB_CLIENT_ID` (Web client ID only; Android client is for Google Cloud)

Local Valhalla:

```powershell
cd scripts\valhalla
docker compose up -d
```

Directions use Valhalla on paths and sidewalks. If a path ends, the route
follows the sidewalk beside the road until a path resumes. Pedestrian costing
has no `use_roads` field; `walkway_factor` 0.1 and `sidewalk_factor` 0.4 do
this. Bicycle costing sets `use_roads` to 0. OSRM road routing is not used.
Without Valhalla, only labeled demo path geometry is available.

## Step 3 — App hardening (in repo)

Implemented:

- Required accounts when Supabase is configured (email + Google Sign-In)
- Report + confirm require a signed-in user in production
- Optional photo (camera or gallery) upload to Storage on report
- Offline draft queue with connectivity flush (not marked submitted until accepted)
- Confirmations → `hazard_confirmations` + `recompute_hazard_verification`
- MapTiler geocoding, start address / phone location, walk & bike path routes on map

## Step 4 — Release packaging

### Android

```powershell
keytool -genkey -v -keystore android/keystore/pathable-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias pathable
copy android\key.properties.example android\key.properties
# edit passwords in android/key.properties
flutter build appbundle --release
```

Upload `build/app/outputs/bundle/release/app-release.aab` to Google Play Console.  
Privacy policy URL required for store listing. Android-only — skip App Store / iOS.

## Step 5 — QA before publish

```powershell
flutter analyze
flutter test
flutter run
```

Manual checklist:

- [ ] Map shows Riverstone with MapTiler tiles
- [ ] Search returns real places; start address / phone location works
- [ ] Walk & bike routes draw on the map with real times
- [ ] Email and Google sign-in work
- [ ] Report persists in Supabase (with optional photo) while signed in
- [ ] Confirm updates hazard via verification RPC
- [ ] Wheelchair / bike profile changes routing preferences
- [ ] TalkBack labels make sense
- [ ] Location / mic / camera permission prompts are clear
- [ ] Airplane-mode report queues as draft; reconnect flushes it
