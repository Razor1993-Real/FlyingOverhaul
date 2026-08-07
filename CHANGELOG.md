# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.0.3

The two things the wiki's publishing guide asks for that were missing. Both
ship inside the archive, which is why this is a release and not a quiet
documentation push.

### Added

- **`DIFFERENCES.md`** — what the mod changes from the original game, and
  what it only approximates: the derived explored-region ledger on saves made
  before the mod existed, and the underlay's coastline between the eleven
  towns it pins exactly.
- **Installing** in the README. The instructions went out with the developer
  "Try it" section and nothing replaced them, so the README said what the mod
  does and never how to get it.
- A credits and standing note: whose work this is built on, that nothing
  distributed is ROM-derived, and that this is not an official product.

## 1.0.2

Nothing in `lib/` or `main.lua` has changed since 1.0.0. This release exists
so the manifest and the published tag agree again.

### Changed

- The README opens with the flight itself: four animations — take-off and the
  climb over Kanto, the party menu, the compass counting a town down, and the
  landing. `.modkitignore` keeps them, and the mod-index metadata, out of the
  installable archive.
- The release workflow no longer cuts a version for a documentation change.
  `docs/**` and `index/**` join `**.md` in `paths-ignore`; neither ever
  reaches a player, and 1.0.1 was a release whose archive differed from
  1.0.0's by one paragraph of README.

## 1.0.1

Cut by the release workflow from a README edit. Its archive differs from
1.0.0's only in `README.md`.

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
