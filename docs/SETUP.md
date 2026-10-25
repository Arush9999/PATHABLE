# PathAble Setup

## Prerequisites

- Flutter **3.29+** (developed with Flutter 3.47.7 / Dart 3.13.5)
- Android Studio / Xcode for device builds
- Optional for production: Supabase project, MapTiler key, Valhalla, Google OAuth client IDs

## Install

```bash
git clone <repo-url>
cd PATHABLE
cp .env.example .env
flutter pub get
```

Ensure Flutter is on your `PATH`, or use a full path such as:

```powershell
C:\Users\<you>\flutter\bin\flutter.bat pub get
```

## Demonstration mode

Leave Supabase empty (or set `PATHABLE_MODE=demo`):

```
PATHABLE_MODE=demo
MAP_STYLE_URL=https://demotiles.maplibre.org/style.json
```

```bash
flutter run
```

You should see a demonstration banner, Riverstone demo area, seeded hazards, search favorites, and local report/confirm.

## Production configuration

Copy `.env.example` → `.env`:

| Variable | Purpose |
|----------|---------|
| `PATHABLE_MODE` | `demo` or `production` |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Public anon key only |
| `MAP_STYLE_URL` | MapLibre style JSON URL (MapTiler recommended) |
| `MAPTILER_API_KEY` | MapTiler key for geocoding |
| `GEOCODING_URL` | Usually `https://api.maptiler.com/geocoding` |
| `VALHALLA_URL` | Required for live path/trail/sidewalk directions |
| `GOOGLE_WEB_CLIENT_ID` | Google OAuth Web client ID (Sign-In + Supabase) |
| `GOOGLE_IOS_CLIENT_ID` | Google OAuth iOS client ID (iOS / macOS) |

Never place a Supabase **service role** key in the mobile app or in git.

Apply backend SQL once — see [GO_LIVE.md](GO_LIVE.md).

## Platform permissions

- **Android:** location, internet, camera, mic, media images in `AndroidManifest.xml`
- **iOS:** location / speech / microphone / camera / photo library strings in `Info.plist`

## Verify

```bash
flutter analyze
flutter test
flutter run
```

## Features included

- Map + hazard markers, search / start address, walk & bike directions on-map
- Accounts (email + Google) required when Supabase is configured
- Hazard report (optional photo), confirmations, offline draft retry
- Directions on paths and sidewalks; a gap follows the sidewalk beside the road until a path resumes
- Civic dashboard (client-side aggregates)
