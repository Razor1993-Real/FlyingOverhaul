# Razor1993s Flying Overhaul

FLY stops opening the town map. You climb onto the bird and fly Kanto
yourself — at four and a half times walking speed, as high as you like, until
you pick a spot and put down.

![Taking off in a ring of wind, climbing, and cruising over Kanto](https://raw.githubusercontent.com/Razor1993-Real/FlyingOverhaul/main/docs/media/flight.gif)

**Requires the [Dramatic Shape voxel mod](https://github.com/DramaticShape/DramaticShapeVoxelMod).**
The flight is a thing you do in a 3D world. Without that mod installed this
one steps aside completely and the town map opens exactly as it always did.

## What you get

**A flight, not a menu.** Take-off, cruise and landing are yours to steer.
The bird faces the way it is going, the camera hangs behind and above it and
stays there whatever altitude or voxel rung you fly at, and you can tip the
view up and down while the bird stays in frame.

**A compass you can navigate by.** A ribbon across the top names the nearest
town in each direction — one per sector, so eleven towns never turn into
eleven overlapping labels. Neighbours fade in and out as you approach. Towns
you have been to are a filled green pip and you may land there; the rest are
hollow and say `? NOT EXPLORED`.

![The ribbon names Pallet Town and counts the distance down](https://raw.githubusercontent.com/Razor1993-Real/FlyingOverhaul/main/docs/media/compass.gif)

**Landing rules that mean something.** Water and unwalkable ground refuse a
landing. So does any map you have not walked yourself — towns *and* routes.
The explored region is derived by walking the game's own connection graph out
from the towns you have visited, with the ones you have not standing as
walls, so FLY can never put you somewhere you have not earned.

**Kanto under the void.** The gaps between the loaded maps used to be a
transparent hole with the world floating in it. They are now filled with the
game's own map of Kanto — the same image the TOWN MAP screen draws, so it
matches the art by construction. The town map is a stylised diagram rather
than a scale drawing, so the sheet is *warped*: all eleven towns are pinned
to their real world positions to under a world pixel and the coastline is
stretched between them. It hangs below the ground plane, so wherever a map
exists that map's own terrain covers it and nothing is ever drawn over a town
or a route.

**Wind.** A tornado of dust and leaves at take-off and again on landing.

## Options

Seven rows, in the OPTIONS menu and on the mod manager's page. Both edit the
same stored value.

| row | choices | default |
| --- | --- | --- |
| FLY HEIGHT | 6 / 12 / 24 / 48 cells | 24 cells |
| FLY SPEED | 3X / 4.5X / 6X / 9X walking | 4.5X |
| FLY LOOK | ON / OFF | ON |
| FLY VOXEL | KEEP / OFF / 15 / 35 / 50 / 75 | 50 |
| FLY T-SHIFT | KEEP / OFF / 1 / 2 / 3 | 2 |
| FLY V-CURVE | KEEP / OFF / 1 / 2 / 3 | OFF |
| KANTO MAP | ON / OFF | ON |

The last three borrow the voxel mod's own settings for the length of a
flight and hand them straight back — nothing is written to disk to do it.
**KEEP** on any of them means the flight leaves that one alone, so a diorama
you have tuned yourself survives the trip.

## Known limits

- One flight is one continuous stretch of world: it cannot cross into a
  region the loader has not streamed in.
- Between the towns it pins exactly, the underlay is a diagram — its
  coastline is approximate. Vermilion's bay is corrected by hand; other
  harbours are not.
- Requires the Dramatic Shape voxel mod, and does nothing without it.

## Credits

Built on **DramaticShape**'s voxel mod, which the flight is drawn through.
The town map data and `wTownVisitedFlag` that the compass and the underlay
read come from **pret/pokered** by way of the recompilation's own extractor.

Not an official product; a mod by Razor1993.
