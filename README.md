# PathAble

**Every path. Every person. Every step.**

PathAble is a crowdsourced pedestrian navigation and infrastructure reporting app for Android and iOS. Community hazard reports influence routing for pedestrians, wheelchair and mobility users, blind and low-vision travelers, and cyclists.

## Status

Working MVP for demo + production configuration:

- Flutter (Material 3) + Riverpod + GoRouter + MapLibre
- Search with settable start (phone location or address)
- Walk / bike directions on paths and sidewalks; a path gap follows the sidewalk beside the road (Valhalla → demo)
- Email + Google accounts when Supabase is configured
- Hazard report (optional photo), confirmations, offline draft retry
- Optional Supabase accounts + accessibility profile sync
- Civic aggregate dashboard
- Supabase/PostGIS SQL (`scripts/apply_all.sql`) including Storage policies

Publish steps: [GO_LIVE.md](docs/GO_LIVE.md). Limits: [KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md).

## Quick start (demonstration mode)

```bash
cp .env.example .env
flutter pub get
flutter run
```

No API keys are required for demonstration mode.

## Documentation

- [Go live (publish checklist)](docs/GO_LIVE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Setup](docs/SETUP.md)
- [Database](docs/DATABASE.md)
- [Testing](docs/TESTING.md)
- [Known Limitations](docs/KNOWN_LIMITATIONS.md)

## Judge demo path (no API keys)

1. Launch the app and complete onboarding.
2. Open **Search destination** and pick a demonstration place.
3. Preview routes and note hazard explanations / accessibility ranking.
4. Switch **Accessibility preferences** (e.g. wheelchair) and re-preview.
5. Open a hazard, confirm it, and submit a new report from **Report**.
6. Open **Settings → Civic infrastructure dashboard** for aggregates.

## Configuration

See [`.env.example`](.env.example). Never commit real credentials. Never embed Supabase service-role keys in the mobile client.

## License / attribution

Map data © OpenStreetMap contributors. Configure a production-capable MapLibre style/tile provider before heavy traffic; do not rely on public OSM tile servers for production load.
