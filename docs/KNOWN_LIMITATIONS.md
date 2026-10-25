# Known Limitations

PathAble is an MVP for the Congressional App Challenge.

## Demonstration vs production

- Demo mode uses fictional Riverstone data and may use MapLibre demotiles.
- Demo routes are labeled and are **not** verified real-world routes.
- Absence of hazard reports never proves a path is safe or accessible.

## External services

- Supabase requires project URL + anon key; without them the app stays in demo mode.
- MapTiler powers the map style and worldwide place search when keys are set. Search is not the Google Places index, so some business listings differ, but it is not limited to the United States or Sugar Land.
- Live directions require Valhalla (`VALHALLA_URL`). Pedestrian costing prefers footways (`walkway_factor` 0.1) and uses a sidewalk (`sidewalk_factor` 0.4), including a road that has a sidewalk, only to bridge a gap until a path resumes. Bicycle costing sets `use_roads` to 0 so cycleways and paths win; a road stays legal as that same gap. Roads with no pedestrian access stay excluded. OSRM is not used.
- Without Valhalla, only labeled demo path geometry is used (OSRM road routing is disabled).
- Google Sign-In needs `GOOGLE_WEB_CLIENT_ID` plus Google + Supabase Auth provider setup.
- Store builds need a public HTTPS Valhalla host (not `localhost` / `10.0.2.2`).

## Speech

- Uses `flutter_tts` and `speech_to_text` through `DeviceVoiceService`.
- Voice reporting fills the form for user confirmation before submit.
- Continuous background conversation recording is not supported.

## Offline

- Local draft reports retry when connectivity returns (production mode).
- Full offline navigation / offline map tiles are out of MVP scope.
- Cached hazard lists may be stale when offline.

## Photos

- Optional report photos upload to Supabase Storage bucket `hazard-photos` when the backend is configured.
- Without the bucket/policies applied, photo upload fails and the report may queue as a draft.

## Verification

- Production confirmations insert into `hazard_confirmations` and call `recompute_hazard_verification`.
- Tune `verification_settings` thresholds before treating confidence as production-grade.

## Platform tooling

- Android cmdline-tools / licenses may need `flutter doctor --android-licenses`.
- Windows desktop builds need Visual Studio C++; prefer Android emulator, device, or Chrome for day-to-day runs.
