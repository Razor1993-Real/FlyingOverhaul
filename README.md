# Razor1993s Flying Overhaul — free bird flight

**FLY stops opening the town map: you ride the bird over Kanto yourself and
pick your own place to land.**

For the player who knows the map and wants to *see* it — the one who noticed
that a game which built Kanto in three dimensions still teleports you across
it through a menu.

Companion to the [Dramatic Shape voxel mod](https://github.com/DramaticShape/DramaticShapeVoxelMod),
which it requires: the flight is a thing you do in a 3D world. Without it —
or on a driver with no depth pass — the FLY row is left exactly as vanilla
built it and the town map opens as it always did.


## Playing

| | |
| --- | --- |
| **FLY** (party menu) | climb on and take off. No destination list. |
| **D-pad / left stick** | fly, camera-relative — forward is where you look |
| **Mouse / right stick / drag** | turn the camera, and with it the flight |
| **A** | land — see below |

The climb and the descent are automatic; by default the bird cruises
twenty-four cells up and covers ground at four and a half times walking speed
— both adjustable, see **Settings**. START is deliberately not available in
the air, the same way the vanilla departure locks input.

The bird turns to face where it is actually going: fly away and you see its
back, strafe and you see its side, turn and it leans into the corner. Those
are vanilla's own four sprite frames — `SPRITE_BIRD` is a full six-frame
walker sheet, the same shape the player's is.

A storm turns around the player on the way up and again on the way down —
three layers of it: **dust** torn off the ground and flung outward, the
near-white **funnel** corkscrewing up, and **leaves** tumbling round the
outside. Every particle is drawn as a streak from where it was to where it
is, which is most of what makes it read as moving air rather than as
confetti.

It stands in real world coordinates, placed on screen through the voxel
mod's own projection, so you fly *around* it rather than past a decal, and
the world curve bends it along with the ground it stands on. It is as tall
as the bird is high, so it grows out of the ground on the way up and folds
back into it on the way down.

## The compass

A ribbon across the top of the screen while you fly: north, east, south and
west, and a marker for each town at its own bearing. Fly toward a marker by
putting it in the middle.

It stays quiet on purpose. Eleven towns would stack into an unreadable pile,
so the arc is cut into sectors and **only the nearest town in each one is
shown** — fly past it and the one behind it takes its place. Names appear
where there is room for them, the one you are heading at first, and it tells
you how far that one is in cells.

Names come from the game's own data (`field.townMap.locations`, the same
entries the town map draws), so a translation mod that patches that registry
moves the compass with it. There is not a single place name in this mod's
code. On a window too narrow for a name and its distance the *layout* gives
way — the distance goes first, then the label, leaving a marker that still
points the right way.

Towns you have not been to are a hollow marker rather than a name: there is
something out there, and finding out what is the game.

## Landing

**A** puts the bird down, on two conditions:

- **Ground you could stand on.** Water and the map edge refuse with the usual
  bump.
- **Somewhere you have already been.** Flying somewhere is not the same as
  having gone there, so a route or town you have never walked turns the
  landing down and says so.

You can land anywhere else you like, including a map away from where you took
off — the crossing is made official as you come down, so you really are on
that map when you get there.

The mod keeps its own record of where you have walked (the game itself only
remembers the eleven towns). On an existing save that record is worked out
once, the first time you fly: everything between the towns you have visited
is open, everything past them is not.

## While you are up there

For the length of the flight — and not one frame longer — three of the voxel
mod's settings are borrowed:

| setting | flight value |
| --- | --- |
| VOXEL | `50` |
| T-SHIFT | `2` |
| V-CURVE | `OFF` |

Nothing is written to disk to do it, and your own values come back on
landing. If you change one of them from the mod manager mid-flight, that new
choice is what you get back, not the one from before take-off.

The world is also loaded much wider than walking needs it — several towns
and the routes between them, streaming in under the climb — so a flight
actually has something to look at.

## What the world does not do

A bird six cells up is not walking. Crossing a cell at altitude rolls no
encounter, takes no warp, trips no trigger, counts no step, and no trainer
challenges you from the ground below. The logical cell is still tracked, but
only so the landing knows where it is putting you.

Flying does not change maps either: one flight is one continuous stretch of
world, clamped to what is loaded.

## Kanto under the void

Between the maps there is nothing — a transparent hole with the towns and
routes floating in it. **KANTO MAP** lays the game's own map of Kanto
underneath, so the gaps read as sea and coastline instead of as absence.

Nothing was drawn for this. `field.townMap`'s background is a 20×18 grid of
8×8 tiles out of the ROM — the very image the TOWN MAP screen shows — so it
matches the rest of the art by construction rather than by taste. It is
recoloured on load, once, because the world around it is not grey.

**It is warped, not scaled.** The town map is a stylised diagram, not a scale
drawing: fitted to the real connection geometry it puts most towns within a
cell or two, Fuchsia thirteen cells out and Indigo Plateau twenty-nine. So
every one of the eleven towns is pinned to its true world position as an
anchor and the sheet is stretched between them. What gets distorted is open
sea, where nobody can tell. Each town lands on its real position to under a
world pixel, and the suite checks exactly that.

**It covers nothing, and there is no mask.** The sheet hangs below the ground
plane. Wherever a map exists its terrain occupies those pixels first and the
depth buffer keeps the sheet out; where no map exists there is nothing to
lose that argument to. That stays correct as maps stream in and out, needs no
stencil and no cutting the mesh to shape — and it is asserted on the pictures
themselves: with the sheet on and off, the frame over a map must be identical
and the frame over the void must not be.

**Two things are edited out of the sheet on the way in.** The town map has
its own legend baked into the picture — a boxed square on every city, small
rings on the landmarks, dashes along the sea routes. At 160×144 those are the
map labelling itself; stretched forty-five times they are black slabs lying
on the world, labelling nothing. They are removed by what they look like
rather than by a list of coordinates: a glyph whose black runs along its
tile's edge takes the whole tile and the terrain grows back through it, while
a ring or a dash inside a tile takes only its own pixels so the tile keeps
what it was drawing.

And Vermilion's harbour gets its bay. The diagram draws solid land from the
city out to the south coast, which the warp stretches to some hundred and
seventy tiles — so the dock the player is flying over ended in a green field.
A bay is carved south of the town in the sea's own dither pattern, phase
aligned so the seam does not show. That correction is stated as an offset
from Vermilion's own marker, not as a rectangle on the sheet.

OFF really means off: no mesh is built and no draw is issued.

## Settings

Seven rows, in the OPTIONS menu and on this mod's page in the mod manager.
Both edit the same stored value.

| row | choices | default |
| --- | --- | --- |
| FLY HEIGHT | 6 / 12 / 24 / 48 cells | 24 cells |
| FLY SPEED | 3X / 4.5X / 6X / 9X walking | 4.5X |
| FLY LOOK | ON / OFF | ON |
| FLY VOXEL | KEEP / OFF / 15 / 35 / 50 / 75 | 50 |
| FLY T-SHIFT | KEEP / OFF / 1 / 2 / 3 | 2 |
| FLY V-CURVE | KEEP / OFF / 1 / 2 / 3 | OFF |
| KANTO MAP | ON / OFF | ON |

The defaults are exactly what the mod did before the menu existed.

**FLY LOOK** lets you tip the camera up and down with the mouse or the right
stick, the way the third-person rung does. The bird stays in shot whatever
you do with it — the camera's aim point is solved from the angle it ends up
at, not fixed in advance.

The last three are the voxel mod's settings, borrowed for the length of the
flight. **KEEP** means the flight does not touch that one at all — neither
on the way in nor on the way out. If you have tuned your own diorama and
want to see *that* from the air, KEEP is how you say so.

**FLY VOXEL: OFF** flies over the flat tile world instead of the diorama —
the compass, the landing rules and the wind all still work, the bird just
rides above a 2D map. Useful if you want the flight without the 3D, or on a
machine that would rather not mesh thirty maps of geometry.

Otherwise the camera follows FLY VOXEL: pick 35 and the bird's camera hangs
at 35 too, rather than at a hardcoded angle the mode is no longer drawn for.

**FLY V-CURVE** is off by default, so the world stays flat under you. The
bend does read as a small planet from up here, and that is the curve doing
its job at height — but it also drops everything past the near distance below
the horizon, and what you are usually doing up here is looking at Kanto. Turn
it to 3 if you want the planet back.

## Layout

| file | what it owns |
| --- | --- |
| `main.lua` | the seams: the FLY row, the fixed-step tick, the HUD, and the wraps inside the voxel mod |
| `lib/Flight.lua` | the phase machine and the altitude curve — no engine, no LOVE |
| `lib/BirdMove.lua` | the pad while flying, and the landing verdict |
| `lib/BirdCam.lua` | the boom, through `Voxel3D.camera` |
| `lib/FarView.lua` | the wide neighbourhood |
| `lib/Settings.lua` | borrowing and giving back the three settings |
| `lib/Atlas.lua` | where the towns are, and where the player has been |
| `lib/Compass.lua` | the ribbon, its decluttering, and the message line |
| `lib/Tornado.lua` | the wind at take-off and landing, its dust and its leaves |
| `lib/Underlay.lua` | the Kanto sheet: its texture, its warp and its mesh |
| `lib/Setting.lua` | one ladder setting, bound to this mod |
| `lib/Options.lua` | the seven of them, their schema and their rows |

Everything it touches in the voxel mod goes through that mod's published
`mod.exports.lib` namespace.

### One workaround worth knowing about

The compass takes its screen geometry from the engine's `render.letterbox`
hook rather than from the viewport `render.hud` is handed. That is not a
preference: the voxel mod wraps `Renderer:endFrame` to paint its battle-exit
veil and calls the inner one **without returning its result**
(`lib/BattleExit.lua`), so every `render.hud` subscriber gets `nil` where the
frame's geometry should be while that mod is installed. `render.letterbox`
carries the same numbers from inside the same frame, so nothing has to
re-derive the letterbox arithmetic. The viewport is still preferred whenever
one actually arrives, so this costs nothing once that wrapper is fixed
upstream.

## Tests

```bash
luajit mods/FlyingOverhaul/tests/fly_logic_test.lua
```

The phase machine, the altitude curve, the landing predicate, the boom's
geometry, the by-label rung lookup, the compass bearings and decluttering,
the point-to-map lookup and the explored-region derivation — with no engine
and no LOVE. Including a guard that every label still fits the twenty
characters a Game Boy screen has room for.

```bash
POKEPORT_IMPORT_ROM="$PWD/Pokemon Red.gb" POKEPORT_DRIVER=mods/FlyingOverhaul/tests/fly_shots.lua SHOT_DIR=.scratchpad/flyshots lovec .
```

A whole flight, photographed and asserted: the borrowed settings in force and
handed back, the view distance, the speed against the voxel mod's own walking
constant, that flying counts no steps, that water refuses a landing, that the
compass places all eleven towns where Kanto actually has them, and — each
self-validating against the same case done the other way — that a landing on
a map you have walked is accepted while one on a map you have not is refused,
and that nobody challenges a bird. COLORS is held on ADVANCED for the whole
run, which is also the mode that shows whether the Kanto sheet's recolouring
sits well next to a colourised world.

`POKEPORT_IMPORT_ROM` is not optional in either of these. Without it the
scripted run opens the ROM picker and waits for somebody to choose the file
by hand, which looks exactly like a hang.

```bash
POKEPORT_IMPORT_ROM="$PWD/Pokemon Red.gb" POKEPORT_DRIVER=mods/FlyingOverhaul/tests/fly_partymenu_test.lua lovec .
```

The real path: a PIDGEOT that knows FLY, the THUNDERBADGE, the party menu
opened and the cursor walked onto FLY — and no town map at the end of it.

All three run inside the repository's own `scripts/test.sh` mod-SDK tier.
