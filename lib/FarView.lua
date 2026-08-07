-- The view distance the flight needs: several towns at once instead of the
-- screen's own neighbourhood.
--
-- The engine already has the lever. OverworldState:rebuildNeighbors walks
-- the connection graph through OverworldState.computeNeighbors, and that
-- walk keeps going for as long as a map's body overlaps the current map's
-- rect INFLATED BY THE VIEW HALF-EXTENTS (computeNeighbors' inReach):
--
--     if cur.hops + 1 <= hops or inReach(destDef, ox, oy) then
--
-- so a large enough reach makes the hop count irrelevant and the BFS runs
-- out as far as the reach allows. That is why this module does not touch
-- constants.world.neighborHops at all -- inReach alone carries both the
-- insert and the queue, and merged content is not ours to rewrite.
--
-- Reach is fed in the one way rebuildNeighbors will take it: it derives the
-- reach from Game.renderer:worldViewSize(), so the wrap lends the renderer a
-- bigger answer FOR THE DURATION OF THAT ONE CALL and puts the real function
-- back immediately. Nothing else in the frame ever sees the inflated size.
--
-- The voxel meshes follow on their own: VoxelScene.prefetch iterates
-- state.neighbors and ChunkMesher.pump builds them inside the cooperative
-- BuildBudget slice, so the extra world streams in over a few seconds
-- rather than freezing the take-off.

local V = ...
local Flight = V.require("Flight")

local FarView = {}

-- World pixels of reach in each direction. Kanto's maps run a few hundred
-- pixels across, so this covers roughly a dozen of them around the bird --
-- several towns and the routes between them -- without pulling in the whole
-- region and every mesh that would imply.
FarView.REACH = 3500

local installed = false

-- rebuildNeighbors halves the view size and adds 64 to get its reach, so
-- hand it a view of 2*REACH to end up at REACH (the 64 is slack we keep).
local function wideViewSize()
  return FarView.REACH * 2, FarView.REACH * 2
end

function FarView.install()
  if installed then return end
  local OverworldState = require("src.world.OverworldController")
  local inner = OverworldState.rebuildNeighbors

  function OverworldState:rebuildNeighbors()
    if not Flight.active() then return inner(self) end
    local Game = require("src.core.Game")
    local renderer = Game.renderer
    if not (renderer and renderer.worldViewSize) then return inner(self) end

    local realW, realH = renderer:worldViewSize()
    local savedFn = renderer.worldViewSize
    renderer.worldViewSize = wideViewSize
    local ok, err = pcall(inner, self)
    renderer.worldViewSize = savedFn

    -- Record the REAL view size, not the borrowed one. OverworldState:update
    -- re-runs this walk whenever the live view size stops matching
    -- neighborViewW/H; left holding the inflated numbers it would mismatch
    -- every single frame and rebuild the whole neighbourhood at 60Hz.
    self.neighborViewW, self.neighborViewH = realW, realH
    if not ok then error(err, 0) end
  end

  installed = true
end

-- Called on both edges of the flight: the neighbourhood is rebuilt once on
-- take-off (wide) and once on landing (back to the screen's own), and
-- MapLoader.trim inside rebuildNeighbors releases whatever the wide set was
-- holding that the narrow one is not.
function FarView.refresh(ow)
  if not (ow and ow.map) then return end
  pcall(function() ow:rebuildNeighbors() end)
end

return FarView
