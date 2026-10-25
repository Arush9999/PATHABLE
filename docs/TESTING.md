# PathAble Testing

## Commands

```bash
flutter analyze
flutter test
```

Ordinary unit tests must not require live Supabase, Valhalla, or API keys.

## Current coverage

- Hazard / GeoPoint model validation (including EWKB / GeoJSON / WKT)
- Demonstration repository seeding and create
- Configuration demo fallback behavior
- Route scoring and hazard-to-route matching
- Report validators + report form widget
- Onboarding, hazard list, accessibility profile widgets
- Pending report queue enqueue / remove

## Recommended next tests

- Confirmation screen with a mock `HazardRepository`
- Photo uploader local-path detection (unit)
- MapTiler geocode JSON parse fixtures
- OSRM / Valhalla polyline decode fixtures
