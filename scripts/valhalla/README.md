# Local Valhalla setup (Riverstone / Sugar Land)

Routing tiles are built from the **Houston** OSM extract so Riverstone (Sugar Land, TX 77479) is covered.

## Start / rebuild

```powershell
cd scripts\valhalla
docker compose down
# Optional clean rebuild:
# Remove-Item -Recurse -Force .\valhalla_data\*
docker compose up -d
docker compose logs -f
```

Wait until the service is listening, then check:

```text
http://127.0.0.1:8002/status
```

App `.env`:

```env
VALHALLA_URL=http://127.0.0.1:8002
```

## Costing the app sends

PathAble does not draw an offset line beside a road. Valhalla's own geometry is the route.

Pedestrian requests have no `use_roads` field. `walkway_factor` is 0.1 (footways) and `sidewalk_factor` is 0.4 (sidewalk ways, and roads tagged with a sidewalk). An untagged road stays at factor 1, so a gap follows the sidewalk beside the road and rejoins a footway when one is available. `alley_factor` is 3 so an alley is not that bridge.

Bicycle requests set `use_roads` to 0. Cycleways, paths, and footways stay cheaper than riding in traffic. A road is still allowed when the path ends, until a path is cheaper again.

## Notes

- After changing regions, wipe `valhalla_data` and set `force_rebuild=True` once, then set it back to `False`.
- Android emulator: use `http://10.0.2.2:8002` instead of `127.0.0.1`.
- Physical phone: use your PC’s LAN IP.
