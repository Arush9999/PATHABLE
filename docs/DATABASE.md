# PathAble Database

Supabase PostgreSQL + PostGIS stores community hazard reports.

## Apply migrations

1. Create a Supabase project.
2. Enable the **PostGIS** extension if not already enabled by the migration.
3. Run SQL files in order from `supabase/migrations/`.
4. Optionally load `supabase/seed.sql` (demonstration rows only).
5. Create a Storage bucket `hazard-photos`:
   - Public read optional; authenticated/anon upload with size limit ~5MB
   - Allowed MIME types: `image/jpeg`, `image/png`, `image/webp`

Put only the project URL and **anon** key in the mobile `.env`. Keep the service-role key on the server.

## Core tables

| Table | Purpose |
|-------|---------|
| `hazards` | Reports with PostGIS `geography` point + optional affected geometry |
| `hazard_confirmations` | Independent still-present / resolved / unsure responses |
| `user_preferences` | Optional synced accessibility preferences |
| `saved_destinations` | Optional saved places |
| `report_moderation` | Abuse flags |
| `verification_settings` | Configurable verification thresholds |

Latitude/longitude are not duplicated as scalar columns; use `location`.

## Row Level Security summary

- **hazards:** public select; insert for anon/authenticated with matching `created_by`; update by owner
- **hazard_confirmations:** public select; insert with matching `user_id`
- **user_preferences / saved_destinations:** owner only
- **report_moderation:** insert for reporters; select own flags
- Privileged bulk moderation uses the **service role** on the server only

Reporter email addresses are never stored on hazard rows.

## Nearby query

```sql
select * from public.nearby_hazards(29.54847, -95.58381, 2500);
```

## Verification

`public.recompute_hazard_verification(hazard_id)` updates status/confidence using:

- independent still-present counts
- resolved vote conflicts → `under_review`
- age-based transition to `stale` (longer for high/critical)

Serious hazards are not silently deleted.

## Testing policies

Use the Supabase SQL editor with `anon` / `authenticated` JWT claims, or `supabase test` / pgTAP if available. Confirm:

1. Anonymous can insert a provisional hazard with `created_by` null
2. Anonymous cannot update another user’s hazard
3. Authenticated user cannot insert a confirmation as a different `user_id`
4. Preferences rows are invisible across users
