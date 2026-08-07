# Differences from the original game

What this mod changes, in the shape of the engine's own
`docs/known-differences.md`: genuine divergences from vanilla behaviour, and
an honest account of what is approximated rather than reproduced. The base
game's ledger is not this mod's to write in.

## FLY no longer opens the town map

In the original, FLY from the party menu opens the town map and teleports the
player to a chosen visited town. Here the row keeps its label and its
conditions — the same badge and the same move check decide whether it appears
at all — but selecting it starts a flight instead of pushing a screen.

The town map itself is untouched: the TOWN MAP item opens it exactly as
before. What changed is one row's destination, not the screen.

The rewrite is conditional. Without the Dramatic Shape voxel mod loaded, or
on a driver with no depth pass, the row is left exactly as vanilla built it
and the original town map opens.

## Flight is movement, and the world is told it is not walking

The original's FLY is a teleport: one frame you are in Pewter, the next in
Celadon, and nothing between the two ever happens. Here the player really
crosses the ground, which raises a question the original never had to answer.

A bird at altitude is deliberately not a walker. Crossing a cell in flight
rolls no wild encounter, takes no warp, trips no map trigger, counts no step
toward the step counter or egg-equivalent timers, and no trainer's line of
sight reaches it. The logical cell is still tracked underneath, but only so
the landing knows where it is putting the player down.

This is a divergence with no vanilla counterpart to be faithful to: the
original has no state in which the player is over the map without being on
it.

## Landing is refused where the player has not walked

Vanilla's FLY offers only towns whose `wTownVisitedFlag` bit is set, so the
restriction exists in the original — but it covers eleven towns and nothing
else, because eleven towns are the only places it could ever send you.

A free flight can be over anything, so the rule is extended to every map: a
route or a town the player has never walked refuses the landing and says so.
Water and unwalkable ground refuse it too.

**This is the mod's largest approximation.** The game records visits for the
eleven fly towns and for nothing else, so for everywhere else the mod must
work it out rather than look it up. It walks the game's own connection graph
outward from the towns that *are* recorded, treating unvisited towns as
walls, and calls everything reachable that way "explored". On a save made
before the mod was installed this is a reconstruction, not a record: a player
who walked a route and then never reached the town beyond it will find that
route counted as unexplored. From the first flight onward the mod keeps its
own ledger and the guess is not repeated.

## The gaps between maps are filled with a warped town map

The original never draws the space between maps, because it never shows two
maps at once. The voxel mod does, and from the air the gaps are a transparent
hole with the world floating in it.

This mod lays the game's own town map background under that hole. Only the
eleven towns are placed accurately — each is pinned to its true world
position to under a world pixel. **Everything between them is approximate by
construction**: the town map is a stylised diagram, not a scale drawing (a
single scale and offset misplaces Fuchsia by thirteen cells and Indigo
Plateau by twenty-nine), so the sheet is stretched between the anchors and
the coastline lands wherever the stretching puts it.

One correction is applied by hand: Vermilion's harbour opens onto sea that
the diagram does not draw, so a bay is carved south of the town. Other
harbours are not corrected. The sheet hangs below the ground plane, so it can
never cover a map that exists.

## Voxel settings are borrowed for the length of a flight

`VOXEL`, `T-SHIFT` and `V-CURVE` belong to the Dramatic Shape voxel mod and
are the player's own choices. For the duration of a flight this mod
substitutes its own values and puts the player's back on landing. Nothing is
written to disk to do it, so a crash mid-flight cannot leave a borrowed value
behind — the stored settings were never touched.

Each of the three can be set to `KEEP`, which declines the substitution
entirely.

## The world streams wider in the air than on foot

Walking loads the current map and its immediate neighbours. A flight loads
several towns' worth, so that there is something to look at. The consequence
is the one limit worth stating plainly: **one flight is one continuous stretch
of world.** It cannot cross into a region the loader has not streamed in, so
the reachable area is bounded by what is loaded rather than by the map graph.

## Not a divergence: save data

The mod stores its explored-map ledger in its own `modData` under the mod
platform's save model. No vanilla save structure is written to, and disabling
the mod leaves the save as vanilla wrote it.
