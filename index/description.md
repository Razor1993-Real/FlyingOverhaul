# Razor1993s Flying Overhaul

**FLY stops opening the town map. You climb onto the bird and fly Kanto yourself — at four and a half times walking speed, as high as you like, until you pick a spot and put down.**

![The bird lifts off in a ring of wind, climbs, and cruises high over Kanto while the compass names Viridian City](https://raw.githubusercontent.com/Razor1993-Real/FlyingOverhaul/main/docs/media/flight.gif)

**Requires the [Dramatic Shape voxel mod](https://github.com/DramaticShape/DramaticShapeVoxelMod).** The flight is a thing you do in a 3D world. Without that mod installed this one steps aside completely and the town map opens exactly as it always did.

## A flight, not a menu

Take-off, cruise and landing are yours to steer. The bird faces the way it is going — those are vanilla's own four sprite frames — and the camera hangs behind and above it and stays there whatever altitude or voxel rung you fly at. You can tip the view up and down while flying, and the bird stays in shot.

## A compass you can navigate by

![The ribbon names Pallet Town and counts the distance down as the bird flies toward it](https://raw.githubusercontent.com/Razor1993-Real/FlyingOverhaul/main/docs/media/compass.gif)

A ribbon across the top names the nearest town in each direction — one per sector, so eleven towns never collapse into eleven overlapping labels. Neighbours fade in and out as you approach, and the one you are heading at tells you how far it is. Names come from the game's own data, so a translation mod moves the compass with it; there is not a single place name in this mod's code.

## Landing rules that mean something

Water and unwalkable ground refuse a landing. So does any map you have not walked yourself — towns *and* routes. The explored region is derived by walking the game's own connection graph out from the towns you have visited, with the ones you have not standing as walls, so FLY can never set you down somewhere you have not earned. Towns you may land in are a filled green pip on the compass; the rest are hollow and say `? NOT EXPLORED`.

## Kanto under the void

The gaps between the loaded maps used to be a transparent hole with the world floating in it. They are now filled with the game's own map of Kanto — the same image the TOWN MAP screen draws, so it matches the art by construction rather than by taste. The town map is a stylised diagram rather than a scale drawing, so the sheet is *warped*: all eleven towns are pinned to their real world positions to under a world pixel and the coastline is stretched between them. It hangs below the ground plane, so wherever a map exists that map's own terrain covers it — nothing is ever drawn over a town or a route.

## Wind

A tornado of dust and leaves at take-off, and again when you come down.

![The bird descends on Viridian City, the wind kicks up dust, and the player is standing on the ground](https://raw.githubusercontent.com/Razor1993-Real/FlyingOverhaul/main/docs/media/landing.gif)

## Options

Seven rows, in the OPTIONS menu and on the mod manager's page — both edit the same stored value.

- **FLY HEIGHT** — 6 / 12 / 24 / 48 cells, default 24
- **FLY SPEED** — 3X / 4.5X / 6X / 9X walking, default 4.5X
- **FLY LOOK** — free camera tilt, default ON
- **FLY VOXEL** — KEEP / OFF / 15 / 35 / 50 / 75, default 50
- **FLY T-SHIFT** — KEEP / OFF / 1 / 2 / 3, default 2
- **FLY V-CURVE** — KEEP / OFF / 1 / 2 / 3, default OFF
- **KANTO MAP** — the underlay, default ON

The three voxel settings are borrowed for the length of a flight and handed straight back; nothing is written to disk to do it. **KEEP** on any of them means the flight leaves that one alone, so a diorama you tuned yourself survives the trip. **FLY VOXEL: OFF** flies over the flat tile world instead, for a machine that would rather not mesh thirty maps at once.

## Known limits

- Requires the Dramatic Shape voxel mod, and does nothing without it.
- One flight is one continuous stretch of world: it cannot cross into a region the loader has not streamed in.
- Between the towns it pins exactly, the underlay is a diagram — its coastline is approximate. Vermilion's bay is corrected by hand; other harbours are not.

## Credits

Built on **DramaticShape**'s voxel mod, which the flight is drawn through. The town map data and the visited-town flag that the compass and the underlay read come from **pret/pokered**, by way of the recompilation's own extractor.

Not an official product. A mod by Razor1993.
