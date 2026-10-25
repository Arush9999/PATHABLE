# PathAble Architecture

Tagline: **Every path. Every person. Every step.**

PathAble is a Flutter mobile application for crowdsourced pedestrian navigation and infrastructure reporting.

## Goals

- Accessibility-first navigation for pedestrians, wheelchair/mobility users, blind/low-vision users, and cyclists
- Community hazard reports that influence routing
- Clear separation between demonstration data and real-world data
- Replaceable backends for maps, routing, geocoding, and persistence

## Layering

```
lib/
  app/           # App shell, theme, router, configuration, DI providers
  core/          # Cross-cutting utilities (location, errors, format, widgets)
  features/      # UI by screen domain (map, search, navigation, report, …)
  data/          # Models, repositories, local stores, remote services
  routing/       # RoutingService (Valhalla path-only → demo) + scoring
  backend/       # Supabase client wiring
```

UI depends on repositories and services through Riverpod providers. Feature widgets do not import Supabase or Valhalla clients directly.

## State management

- **Riverpod** for dependency injection and async state
- Configuration is provided once at startup via `appConfigurationProvider`
- Hazard access goes through `HazardRepository` (create / update / confirm / nearby)

## Demonstration mode

When `PATHABLE_MODE=demo` or Supabase credentials are missing, the app:

1. Shows a persistent demonstration banner
2. Uses `DemoHazardRepository` (local persistence via SharedPreferences)
3. Labels seeded hazards as fictional
4. Uses MapLibre demotiles unless a MapTiler style is configured

Demonstration mode must never silently pretend a failed production API call succeeded.

## Mapping & directions

- **MapLibre Flutter** renders the map and route polylines
- Style URL from `MAP_STYLE_URL`; geocoding via MapTiler when configured
- Routing: Valhalla (paths and sidewalks; a gap follows the sidewalk beside the road) → labeled demo geometry
- Walk / bike modes; start address or phone location; ETA + distance formatting
- Auth: Supabase email + native Google Sign-In (`AuthService`)

## Backend integrations

| Concern | Interface | Demo | Production |
|--------|-----------|------|------------|
| Hazards | `HazardRepository` | `DemoHazardRepository` | Supabase + PostGIS |
| Photos | Storage uploader | Local path only | `hazard-photos` bucket |
| Routing | `RoutingService` | Demo path router | Valhalla (paths, then sidewalk gap) + hazard scoring |
| Geocoding | `GeocodingService` | Demo destinations | MapTiler (+ favorites merge) |
| Auth | `AuthService` | N/A (local demo) | Email + Google → Supabase |
| Speech | `VoiceService` | Device TTS / STT | Same |
| Profiles | Preferences sync | Local SharedPreferences | `user_preferences` table |

## Offline drafts

Failed production reports enqueue in `PendingReportQueue` and flush on connectivity restore. Drafts are never labeled “submitted” until the server accepts them.

## Security notes

- Only the Supabase **anon** key may ship in the mobile app
- Service-role keys stay on the server
- Row Level Security is required on production tables
- `.env` is gitignored; `.env.example` is the template
