# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.0.0

First public release. The mod carried in-development versions up to 2.0.0
before it was published; the count starts here, at the first build anyone
else can install.

### Added

- **Free flight.** The party menu's FLY row no longer opens the town map. The
  player climbs onto the bird, cruises under their own steering at 4.5x
  walking speed, and lands where they choose.
- **A compass ribbon** naming the nearest town in each direction, one per
  sector, fading its neighbours in and out on approach. Towns you have been to
  are a filled green pip; the rest are hollow and say `? NOT EXPLORED`.
- **Landing rules.** Water and unwalkable ground refuse a landing, and so does
  any map you have not walked yourself — towns and routes alike, the explored
  region derived by walking the connection graph from the towns you have
  visited.
- **Kanto under the void.** The gaps between the loaded maps are filled with
  the game's own town map, warped so that all eleven towns sit on their real
  world positions to under a world pixel. It hangs below the ground plane, so
  the depth buffer keeps it out of every map that exists.
- **A wind tornado** at take-off and landing, with dust off the ground and
  leaves in the air.
- **Seven options**, in the OPTIONS menu and on the mod manager's page:
  `FLY HEIGHT`, `FLY SPEED`, `FLY LOOK`, `FLY VOXEL`, `FLY T-SHIFT`,
  `FLY V-CURVE` and `KANTO MAP`.
- **Four directional bird sprites**, so the bird faces the way it is flying.

### Changed

- The voxel mod's `VOXEL`, `T-SHIFT` and `V-CURVE` are borrowed for the length
  of a flight and handed straight back. Nothing is written to disk to do it.
- The world streams several towns wide during a flight rather than the four
  maps walking needs.

### Known

- Requires the Dramatic Shape voxel mod.
- One flight is one continuous stretch of world.
- The underlay is a stylised diagram between the towns it pins; Vermilion's
  bay is corrected by hand, other harbours are not.
