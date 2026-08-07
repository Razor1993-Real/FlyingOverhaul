-- Where everything is, and where the player has already been.
--
-- Two jobs that share one walk of the map graph:
--
--   THE LAYOUT   every connected outdoor map's rectangle, in the take-off
--                map's own pixel frame -- the same frame the bird's px/py
--                live in, so a town's position is directly comparable with
--                the bird's. Feeds the compass and the point-to-map lookup.
--
--   THE LEDGER   which maps the player has actually been to, which is what
--                decides where the bird may put down.
--
-- The walk itself is the ENGINE'S: OverworldState.computeNeighbors, the same
-- pure function rebuildNeighbors uses, run with a hop count large enough to
-- reach the whole connected component. Composing connection offsets by hand
-- would be a second implementation of the one thing that absolutely must
-- agree with what the renderer draws.
--
-- The two pure walks below (deriveExplored, mapAt) take plain tables instead
-- of the live world, so the suite can check them under luajit with no engine
-- present -- which is where the rules that are easy to get subtly wrong live.

local V = ...

local Atlas = {}

-- Vanilla's NUM_CITY_MAPS: map indices below this are the towns FLY knows
-- (src/world/Map.lua, Map.isFlyTown). Used by the pure walks, which have no
-- Map module to ask.
Atlas.NUM_CITY_MAPS = 11

-- ------- the layout

local cache = nil            -- { root = id, maps = {...}, towns = {...} }

local function isTownDef(def)
  return def ~= nil and def.index ~= nil and def.index < Atlas.NUM_CITY_MAPS
end
Atlas._isTownDef = isTownDef

-- Every connected map's rect in `rootId`'s frame, root included at (0, 0).
--
-- hops is deliberately large rather than the reach being large: with no
-- reachW/reachH, computeNeighbors' inReach answers false and the hop count
-- alone drives the walk, which is the simpler of the two knobs and cannot
-- be tripped up by a map whose body sits oddly relative to the root.
local function buildLayout(rootId)
  local Game = require("src.core.Game")
  local OverworldState = require("src.world.OverworldController")
  local maps = Game.data and Game.data.maps
  local rootDef = maps and maps[rootId]
  if not rootDef then return {} end

  local out = {
    [rootId] = { id = rootId, ox = 0, oy = 0,
                 w = rootDef.width * 32, h = rootDef.height * 32,
                 def = rootDef },
  }
  local ok, list = pcall(OverworldState.computeNeighbors, maps, rootId, 99)
  if ok then
    for _, n in ipairs(list) do
      local def = maps[n.id]
      if def and not out[n.id] then
        out[n.id] = { id = n.id, ox = n.ox, oy = n.oy,
                      w = def.width * 32, h = def.height * 32, def = def }
      end
    end
  end
  return out
end

-- What a place is CALLED, resolved exactly the way the town map resolves it
-- (`entryName`, src/ui/TownMap.lua): the field registry's own entry, falling
-- back to the map id with its underscores opened out.
--
-- Deliberately the only source. The names live in `field.townMap.locations`,
-- which is merged content -- so a translation mod that patches that registry
-- moves the compass and the town map together, and this mod never has to
-- know a single place name. Reading `label` as well as `name` is what keeps
-- the two screens from disagreeing on a dataset that only carries one.
function Atlas.nameOf(loc, mapId)
  local name = type(loc) == "table" and (loc.name or loc.label) or nil
  return name or tostring(mapId):gsub("_", " ")
end

-- The towns among them, with the display name the town map already uses.
local function buildTowns(layout)
  local Game = require("src.core.Game")
  local field = (Game.data and Game.data.field) or {}
  local locs = (field.townMap and field.townMap.locations) or {}
  local visited = (Game.save and Game.save.visited) or {}
  local out, seen = {}, {}
  for _, mapId in ipairs(field.flyOrder or {}) do
    local rect = layout[mapId]
    if rect and not seen[mapId] and isTownDef(rect.def) then
      seen[mapId] = true
      out[#out + 1] = {
        id = mapId,
        name = Atlas.nameOf(locs[mapId], mapId),
        -- the middle of the town, which is what "fly toward it" means
        x = rect.ox + rect.w / 2,
        z = rect.oy + rect.h / 2,
        visited = visited[mapId] and true or false,
      }
    end
  end
  return out
end

-- Build (or reuse) the layout for a root map. Called once per flight: the
-- flight never changes maps, so nothing it depends on can move under it.
function Atlas.open(rootId)
  if cache and cache.root == rootId then return cache end
  local layout = buildLayout(rootId)
  cache = { root = rootId, maps = layout, towns = buildTowns(layout) }
  return cache
end

function Atlas.close()
  cache = nil
end

-- The layout for whichever map is under the player right now, opening it if
-- something else closed it.
--
-- Atlas.open is the flight's entry point and Atlas.close is its exit, which
-- was the whole story while only the compass and the landing read this. The
-- Kanto underlay reads it on every drawn frame, flight or not, and cannot
-- care whose turn it is -- so this asks for the layout by map rather than by
-- occasion, and rebuilds when the player has walked somewhere else.
function Atlas.forMap(mapId)
  if not mapId then return nil end
  if not (cache and cache.root == mapId) then Atlas.open(mapId) end
  return cache
end

function Atlas.towns()
  return (cache and cache.towns) or {}
end

function Atlas.layout()
  return (cache and cache.maps) or {}
end

-- ------- which map is under a point
--
-- Pure over a layout table so the suite can check the boundary cases: the
-- half-open rect (a point on a map's east edge belongs to its neighbour, not
-- to both) and the VOID between two maps that do not actually touch, which
-- must answer nil rather than picking whichever came first.
function Atlas.mapAt(layout, x, z)
  if type(layout) ~= "table" then return nil end
  for id, r in pairs(layout) do
    if x >= r.ox and x < r.ox + r.w and z >= r.oy and z < r.oy + r.h then
      return id
    end
  end
  return nil
end

-- ------- the ledger
--
-- The engine records visits for the ELEVEN TOWNS only -- save.visited is
-- vanilla's wTownVisitedFlag, and OverworldState:setMap sets it behind an
-- explicit isFlyTown gate so the ROUTE_4/ROUTE_10 Pokemon Centers stay out
-- (#788). A route visit is written nowhere in the save at all.
--
-- So the mod keeps its own set, in mod.save (backed by save.modData, so it
-- travels with the save file), fed from map.entered from here on.
--
-- For a save that already has hours on it that set would be empty, and the
-- player would suddenly be unable to land on routes they have walked a dozen
-- times. Hence deriveExplored below, run once.

local LEDGER_KEY = "explored"
local DERIVED_KEY = "exploredDerived"

-- The region a player with these towns has plausibly walked: breadth-first
-- through the connection graph from every visited town, with UNVISITED TOWNS
-- ACTING AS WALLS -- reached, but never walked through.
--
-- The wall is what makes the answer mean something. Without it the walk
-- spills through the whole region and marks Fuchsia's routes explored for a
-- player still on Route 2; with it, everything between the towns you have
-- been to opens and everything past them stays shut, which is what "where
-- have I been" amounts to on a map you cross on foot.
--
-- Pure: `maps` need only carry `connections` and `index`.
function Atlas.deriveExplored(maps, visited, isTown)
  isTown = isTown or isTownDef
  local open, queue = {}, {}
  for id in pairs(visited or {}) do
    if maps[id] then
      open[id] = true
      queue[#queue + 1] = id
    end
  end
  local qi = 1
  while queue[qi] do
    local def = maps[queue[qi]]
    qi = qi + 1
    for _, conn in pairs((def and def.connections) or {}) do
      local id = conn.map
      local dest = maps[id]
      if dest and not open[id]
         -- a town the player has not been to is the edge of what they know
         and not (isTown(dest) and not (visited or {})[id]) then
        open[id] = true
        queue[#queue + 1] = id
      end
    end
  end
  return open
end

local function ledger()
  local mod = V.mod
  if not (mod and mod.save) then return nil end
  local got = mod.save:get(LEDGER_KEY)
  if type(got) ~= "table" then
    got = {}
    mod.save:set(LEDGER_KEY, got)
  end
  return got
end

-- Run the derivation once per save, the first time a flight needs an answer.
function Atlas.ensureLedger()
  local mod = V.mod
  local set = ledger()
  if not set then return {} end
  if mod.save:get(DERIVED_KEY) then return set end

  local ok = pcall(function()
    local Game = require("src.core.Game")
    local derived = Atlas.deriveExplored(Game.data.maps,
                                         Game.save and Game.save.visited or {})
    for id in pairs(derived) do set[id] = true end
  end)
  -- Marked derived either way: a derivation that threw would throw again
  -- every frame, and an empty ledger still fills in from map.entered.
  mod.save:set(DERIVED_KEY, true)
  if not ok then
    mod.log:warn("could not derive the explored region; "
                 .. "it will fill in as you travel")
  end
  return set
end

-- Record a map the player has entered. Called from map.entered, so it
-- catches routes, towns and interiors alike.
function Atlas.markExplored(mapId)
  if type(mapId) ~= "string" then return end
  local set = ledger()
  if set then set[mapId] = true end
end

function Atlas.explored(mapId)
  if not mapId then return false end
  local set = ledger()
  return (set and set[mapId]) and true or false
end

-- named for the suite
function Atlas._ledger() return ledger() end
function Atlas._cache() return cache end

return Atlas
