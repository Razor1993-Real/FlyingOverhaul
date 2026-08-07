-- Kanto under the void.
--
-- Between the maps there is nothing: a transparent hole with the towns and
-- routes floating in it. This lays the game's own Kanto map underneath, so
-- the gaps read as sea and coastline instead of as absence.
--
-- Three problems, and the interesting one is the second:
--
--   WHAT TO DRAW    the engine already ships the picture. field.townMap's
--                   background is a 20x18 grid of 8x8 tiles out of the ROM
--                   -- the very image the town map screen draws. Nothing
--                   needs to be authored, and "matches the art style" is
--                   true by construction rather than by taste.
--
--   WHERE TO PUT IT the town map is NOT a scale drawing. Fitted to the real
--                   connection geometry it puts most towns within a cell or
--                   two, Fuchsia thirteen cells out and Indigo Plateau
--                   twenty-nine. No scale and offset can fix that, because
--                   the error is not linear -- it is a stylised diagram. So
--                   the image is WARPED: every town is an anchor pinned to
--                   its true position and the sheet is stretched between
--                   them. What gets distorted is open sea, where nobody can
--                   tell.
--
--   NOT COVERING    solved by geometry rather than by masking. The sheet
--   ANYTHING        hangs BELOW the ground plane, so wherever a map exists
--                   its terrain occupies those pixels first and the depth
--                   buffer keeps the sheet out. Where no map exists there is
--                   nothing to lose that argument to, and the sheet shows.
--                   No stencil, no cutting the mesh to shape, and it stays
--                   correct as maps stream in and out.

local V = ...

local Underlay = {}

-- The town map is 20x18 tiles of 8, i.e. the Game Boy screen.
Underlay.TEX_W = 160
Underlay.TEX_H = 144

-- Marker placement on that image: TownMapCoordsToOAMCoords puts the 16x16
-- nybble grid two tiles in and one tile down (src/ui/TownMap.lua markerXY),
-- and the marker is 8x8, so its CENTRE -- which is what an anchor means --
-- is another four in and four down.
Underlay.MARK_X = 20
Underlay.MARK_Y = 12

-- Mesh subdivisions across the sheet. Fine enough that the world curve,
-- which the vertex shader applies per vertex, stays smooth across a sheet
-- several thousand pixels wide: a coarse grid facets visibly, and worse, a
-- quad's flat interior can bulge back up through terrain that curved away
-- underneath it.
Underlay.GRID = 64

-- How far under the ground plane it hangs. Enough margin that the curve's
-- per-vertex drop cannot lift a quad's interior through the terrain far from
-- the camera, shallow enough that it is not visible as a step at a map's rim.
Underlay.DEPTH = -20

-- The four Game Boy shades, in the order the sheet uses them (darkest
-- first), as the colours they are drawn in.
--
-- Recoloured rather than shown as-is because the world around it is not grey.
-- Under COLORS: ADVANCED the terrain is fully colourised, and a monochrome
-- sheet next to a green field reads as a missing texture rather than as a
-- map. The shades carry meaning on this particular image -- the mottled
-- light/white tile is sea, flat dark is landmass, flat white is the route
-- grid -- so mapping them is enough; no per-tile work is needed.
Underlay.PALETTE = {
  { 0.09, 0.14, 0.11 },   -- outlines
  { 0.28, 0.46, 0.25 },   -- landmass
  { 0.36, 0.52, 0.64 },   -- open water
  { 0.74, 0.79, 0.70 },   -- coast and routes
}

-- The fifth colour, which the sheet itself does not have: sea foam.
Underlay.FOAM = { 0.47, 0.62, 0.72 }

-- Which of the four shades a red channel value is.
function Underlay.shadeIndex(r)
  return math.min(4, math.max(1, math.floor(r * 3 + 0.5) + 1))
end

-- Foam, or a route line? The lightest shade does double duty on this image:
-- it draws the little wave dashes out at sea AND the route grid on land. At
-- 1:1 that is fine. Stretched forty-five times across Kanto the wave dashes
-- become five-tile blocks, and open sea -- which is most of what the void
-- ever shows -- reads as a chequerboard rather than as water.
--
-- So a light pixel is asked what it is standing in. Mostly water around it
-- means foam, and foam is painted a lighter shade OF the water instead of
-- against it: the pattern survives as a sheen at the scale the sheet is
-- actually seen. A light pixel with land around it is a route and is left
-- alone, so nothing inland changes.
--
-- `shades` is the whole image classified, one entry per pixel, row major
-- and 1-based; 0 means transparent.
function Underlay.isFoam(shades, w, h, x, y)
  if shades[y * w + x + 1] ~= 4 then return false end
  local water, land = 0, 0
  for dy = -1, 1 do
    for dx = -1, 1 do
      local nx, ny = x + dx, y + dy
      if (dx ~= 0 or dy ~= 0)
         and nx >= 0 and nx < w and ny >= 0 and ny < h then
        local s = shades[ny * w + nx + 1]
        if s == 3 then water = water + 1
        elseif s == 1 or s == 2 then land = land + 1 end
      end
    end
  end
  return water > land
end

-- ------- the sheet's own furniture (pure)
--
-- The town map has its legend baked into the picture: a boxed square on
-- every city, small rings on the landmarks, dashes along the sea routes. On
-- a 160x144 screen those are the map's labelling. Stretched forty-five times
-- across Kanto they are black slabs lying on the world, labelling nothing --
-- there is no cursor out here for them to belong to. So they come off.
--
-- Two kinds, told apart by WHERE the black sits rather than by a list of
-- coordinates that a different sheet would invalidate. A city box fills its
-- whole 8x8 tile, so its border runs along the tile's own edge: the tile goes
-- and the terrain around it grows back through. A ring or a dash sits inside
-- its tile, so only those pixels go and the tile keeps what it was drawing --
-- which matters out at sea, where taking the whole tile pulled the pale route
-- colour down into the water in pier-shaped streaks.
function Underlay.glyphMask(shades, w, h)
  local mask = {}
  for ty = 0, h - 8, 8 do
    for tx = 0, w - 8, 8 do
      local black, onRim = {}, false
      for j = 0, 7 do
        for i = 0, 7 do
          local x, y = tx + i, ty + j
          if shades[y * w + x + 1] == 1 then
            black[#black + 1] = y * w + x + 1
            if i == 0 or i == 7 or j == 0 or j == 7 then onRim = true end
          end
        end
      end
      if #black > 0 then
        if onRim then
          for j = 0, 7 do
            for i = 0, 7 do mask[(ty + j) * w + tx + i + 1] = true end
          end
        else
          for _, k in ipairs(black) do mask[k] = true end
        end
      end
    end
  end
  return mask
end

-- Grow the surroundings into the masked pixels, a ring at a time: each pass
-- gives every masked pixel that has a settled neighbour the shade most of
-- those neighbours have, and repeats until nothing is left. Written as a
-- read pass and then a write pass, so a pixel decided this round cannot
-- become the evidence for its neighbour in the same round -- that would let
-- one colour march across the hole instead of the four sides meeting.
function Underlay.dissolve(shades, w, h, mask)
  local left = {}
  for k in pairs(mask) do left[#left + 1] = k; shades[k] = 0 end
  while #left > 0 do
    local paint, again = {}, {}
    for _, k in ipairs(left) do
      local x, y = (k - 1) % w, math.floor((k - 1) / w)
      local best, bestN = nil, 0
      local tally = {}
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = x + d[1], y + d[2]
        if nx >= 0 and nx < w and ny >= 0 and ny < h then
          local s = shades[ny * w + nx + 1]
          if s and s > 0 then
            tally[s] = (tally[s] or 0) + 1
            -- ties go to the darker shade, so land closes a hole before a
            -- route does and a coastline cannot sprout a spur
            if tally[s] > bestN or (tally[s] == bestN and best and s < best) then
              best, bestN = s, tally[s]
            end
          end
        end
      end
      if best then paint[k] = best else again[#again + 1] = k end
    end
    if not next(paint) then break end
    for k, s in pairs(paint) do shades[k] = s end
    left = again
  end
  return shades
end

-- ------- where the diagram and the world disagree (pure)
--
-- Vermilion's harbour opens onto the sea. The town map does not draw that:
-- from the city it is solid land for thirty-two sheet pixels, which the warp
-- stretches to some hundred and seventy tiles, so a player flying over the
-- dock sees the bay end in a green field. The diagram is not wrong for what
-- it is -- a legend at that size cannot afford a bay -- it just does not
-- survive being laid over the real thing.
--
-- Stated as an offset from the town's own marker rather than as an absolute
-- rectangle, so it still means "south of Vermilion" if the sheet's layout
-- ever moves under it.
Underlay.BAYS = {
  { town = "VERMILION_CITY", x0 = -8, y0 = 4, x1 = 7, y1 = 15 },
}

-- An 8x8 tile that is nothing but open sea, to fill a bay with. Taken from
-- the sheet rather than invented: the sea is a dither of two shades, and a
-- flat rectangle of one of them next to it reads as a hole in the pattern.
-- Sampled on the tile grid and re-laid on the tile grid, so the dither runs
-- through the seam unbroken.
function Underlay.seaTile(shades, w, h)
  for ty = 0, h - 8, 8 do
    for tx = 0, w - 8, 8 do
      local water, foam, other = 0, 0, 0
      for j = 0, 7 do
        for i = 0, 7 do
          local s = shades[(ty + j) * w + tx + i + 1]
          if s == 3 then water = water + 1
          elseif s == 4 then foam = foam + 1
          else other = other + 1 end
        end
      end
      if other == 0 and water > 0 and foam > 0 then return tx, ty end
    end
  end
  return nil
end

-- Carve one bay, in the sea's own pattern.
function Underlay.carve(shades, w, h, x0, y0, x1, y1, rx, ry)
  if not rx then return shades end
  for y = math.max(0, y0), math.min(h - 1, y1) do
    for x = math.max(0, x0), math.min(w - 1, x1) do
      shades[y * w + x + 1] = shades[(ry + y % 8) * w + rx + x % 8 + 1]
    end
  end
  return shades
end

-- Every bay the sheet needs, resolved against the town markers.
function Underlay.carveBays(shades, w, h, locs)
  local rx, ry = Underlay.seaTile(shades, w, h)
  for _, bay in ipairs(Underlay.BAYS) do
    local loc = locs and locs[bay.town]
    if loc and loc.x and loc.y then
      local cx = loc.x * 8 + Underlay.MARK_X
      local cy = loc.y * 8 + Underlay.MARK_Y
      Underlay.carve(shades, w, h, cx + bay.x0, cy + bay.y0,
                     cx + bay.x1, cy + bay.y1, rx, ry)
    end
  end
  return shades
end

-- ------- the fit (pure)
--
-- Least squares, one axis at a time: world = a * townmap + b. This alone is
-- the "just scale it" answer, and on its own it is not good enough -- see the
-- header. It is here because the warp below needs something to be a
-- correction TO, and because a global scale is the right thing to fall back
-- on out at the edges where there are no anchors nearby.
--
-- `anchors` is a list of { tx, ty, wx, wz }: a point on the sheet, and where
-- that point really is in the world.
function Underlay.fit(anchors)
  local n = #anchors
  if n < 2 then return 1, 0, 1, 0 end
  local sx, sy, sxx, syy, sxw, syw, swx, swz = 0, 0, 0, 0, 0, 0, 0, 0
  for _, a in ipairs(anchors) do
    sx = sx + a.tx; sy = sy + a.ty
    sxx = sxx + a.tx * a.tx; syy = syy + a.ty * a.ty
    sxw = sxw + a.tx * a.wx; syw = syw + a.ty * a.wz
    swx = swx + a.wx; swz = swz + a.wz
  end
  local dx = n * sxx - sx * sx
  local dy = n * syy - sy * sy
  local ax = dx ~= 0 and (n * sxw - sx * swx) / dx or 1
  local az = dy ~= 0 and (n * syw - sy * swz) / dy or 1
  return ax, (swx - ax * sx) / n, az, (swz - az * sy) / n
end

-- What the fit leaves over at each anchor: the vector that would have to be
-- added to land exactly on the town.
function Underlay.residuals(anchors, ax, bx, az, bz)
  local out = {}
  for i, a in ipairs(anchors) do
    out[i] = { tx = a.tx, ty = a.ty,
               rx = a.wx - (ax * a.tx + bx),
               rz = a.wz - (az * a.ty + bz) }
  end
  return out
end

-- How sharply an anchor's pull falls off with distance. Two is the ordinary
-- inverse-square choice: high enough that a town's correction is spent
-- locally instead of dragging the whole coastline, low enough that the
-- blend between neighbours stays smooth rather than showing each anchor's
-- territory as a facet.
Underlay.FALLOFF = 2

-- Close enough to an anchor to BE it, in sheet pixels. Guards the division
-- and makes the pin exact rather than merely very close.
Underlay.SNAP = 0.5

-- Where a point on the sheet goes in the world.
--
-- The fit, plus an inverse-distance-weighted blend of the residuals
-- (Shepard). At an anchor the weight of that anchor runs away to infinity
-- and the blend becomes its correction alone, so the town lands exactly on
-- its real position -- which is the whole promise of this module. Away from
-- the anchors the corrections fade into each other, and far from all of them
-- the blend flattens out and what is left is the plain fit.
function Underlay.warp(res, ax, bx, az, bz, tx, ty)
  local wx, wz = ax * tx + bx, az * ty + bz
  if #res == 0 then return wx, wz end

  local sw, sx, sz = 0, 0, 0
  for _, r in ipairs(res) do
    local dx, dy = tx - r.tx, ty - r.ty
    local d2 = dx * dx + dy * dy
    if d2 <= Underlay.SNAP * Underlay.SNAP then
      return wx + r.rx, wz + r.rz
    end
    local w = 1 / d2 ^ (Underlay.FALLOFF / 2)
    sw = sw + w
    sx = sx + w * r.rx
    sz = sz + w * r.rz
  end
  return wx + sx / sw, wz + sz / sw
end

-- ------- the anchors
--
-- One per fly town: where its marker sits on the sheet, and where the town
-- really is. The world side comes from Atlas, which already walks the
-- connection graph for the compass -- so the sheet is pinned to the same
-- geometry the renderer draws, not to a table that could drift from it.
function Underlay.anchors(towns, locs)
  local out = {}
  for _, t in ipairs(towns or {}) do
    local loc = locs and locs[t.id]
    if loc and loc.x and loc.y then
      out[#out + 1] = {
        id = t.id,
        tx = loc.x * 8 + Underlay.MARK_X,
        ty = loc.y * 8 + Underlay.MARK_Y,
        wx = t.x, wz = t.z,
      }
    end
  end
  return out
end

-- ------- the picture

local texture = nil
local mesh = nil
local builtFor = nil

function Underlay.invalidate()
  mesh, builtFor = nil, nil
end

function Underlay.forget()
  Underlay.invalidate()
  texture = nil
end

-- Build the sheet once: the 360 tile indices blitted into one image, then
-- recoloured through the palette above.
local function buildTexture()
  if texture ~= nil then return texture or nil end
  texture = false
  local ok = pcall(function()
    local Game = require("src.core.Game")
    local bg = ((Game.data.field or {}).townMap or {}).background
    if not (bg and bg.map and bg.tiles) then return end

    local sheet = love.graphics.newImage(bg.tiles.path)
    local iw, ih = sheet:getDimensions()
    local per = iw / 8
    local quads = {}
    for i = 0, per * (ih / 8) - 1 do
      quads[i] = love.graphics.newQuad((i % per) * 8, math.floor(i / per) * 8,
                                       8, 8, iw, ih)
    end

    local canvas = love.graphics.newCanvas(Underlay.TEX_W, Underlay.TEX_H,
                                           { dpiscale = 1 })
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    -- Everything below the canvas switch, and the reason this sheet was
    -- invisible for a while. push("all") SAVES the state, it does not
    -- neutralise it -- and this runs inside the voxel scene pass, so the
    -- state it saved is a 3D one. The scene shader's position() ignores
    -- transform_projection entirely and returns `vp * model * vertex`, so
    -- the tile blits below were being run through the camera and landing
    -- nowhere near a 160x144 canvas; what little arrived came out at
    -- VertexShade 0, i.e. black. The canvas ended up empty, every fragment
    -- of the sheet failed the alpha test, and the blank was then cached.
    love.graphics.setShader()
    love.graphics.setDepthMode()
    love.graphics.setBlendMode("alpha")
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    for i = 1, #bg.map do
      local q = quads[bg.map[i]]
      if q then
        love.graphics.draw(sheet, q, ((i - 1) % 20) * 8,
                           math.floor((i - 1) / 20) * 8)
      end
    end
    love.graphics.setCanvas()
    love.graphics.pop()

    -- Recolour on the CPU, once. A shader would have to be bound for every
    -- draw of the sheet forever after; this is a few thousand pixels touched
    -- at load and an ordinary texture from then on.
    local data = canvas:newImageData()
    local pal = Underlay.PALETTE
    -- classify first, paint second: the foam rule needs to see a pixel's
    -- neighbours, and mapPixel only ever hands over one pixel at a time
    local w, h = data:getDimensions()
    local shades = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, _, _, a = data:getPixel(x, y)
        shades[y * w + x + 1] = (a < 0.5) and 0 or Underlay.shadeIndex(r)
      end
    end
    -- off with the legend, in with the bay -- both before the foam rule
    -- below is asked anything, since both change what a pixel stands in
    Underlay.dissolve(shades, w, h, Underlay.glyphMask(shades, w, h))
    Underlay.carveBays(shades, w, h,
                       ((Game.data.field or {}).townMap or {}).locations)

    data:mapPixel(function(x, y, _, _, _, a)
      if a < 0.5 then return 0, 0, 0, 0 end
      local c = Underlay.isFoam(shades, w, h, x, y) and Underlay.FOAM
                or pal[shades[y * w + x + 1]]
      return c[1], c[2], c[3], 1
    end)
    texture = love.graphics.newImage(data)
    texture:setFilter("nearest", "nearest")
  end)
  if not ok then texture = false end
  return texture or nil
end

Underlay._buildTexture = buildTexture

-- Build the texture ahead of time, from a caller that is NOT inside a render
-- pass (main.lua's step hook). After the first tick this is a table lookup.
function Underlay.warm() return buildTexture() end

-- ------- the mesh
--
-- A grid over the sheet, each vertex warped into the world. UVs are the
-- grid's own fractions, normalised, the way ChunkMesher's uvRect hands them
-- over. Shade is flat: this is a map, not a lit surface, and a shaded one
-- would read as terrain the player might try to land on.

function Underlay.buildMesh(anchors)
  local DS = V.ds()
  if not DS then return nil end
  local Voxel3D = DS.require("Voxel3D")
  local ax, bx, az, bz = Underlay.fit(anchors)
  local res = Underlay.residuals(anchors, ax, bx, az, bz)

  local n = Underlay.GRID
  local verts, indices = {}, {}
  for gy = 0, n do
    local v = gy / n
    local ty = v * Underlay.TEX_H
    for gx = 0, n do
      local u = gx / n
      local tx = u * Underlay.TEX_W
      local wx, wz = Underlay.warp(res, ax, bx, az, bz, tx, ty)
      verts[#verts + 1] = { wx, Underlay.DEPTH, wz, u, v, 1 }
    end
  end
  local row = n + 1
  for gy = 0, n - 1 do
    for gx = 0, n - 1 do
      local a = gy * row + gx + 1
      local b = a + 1
      local c = a + row
      local d = c + 1
      indices[#indices + 1] = a; indices[#indices + 1] = b
      indices[#indices + 1] = d
      indices[#indices + 1] = a; indices[#indices + 1] = d
      indices[#indices + 1] = c
    end
  end
  return Voxel3D.newMesh(verts, indices)
end

-- Build (or reuse) the sheet for a root map. Cheap to call every frame: it
-- only does work when the world under it has changed.
function Underlay.ensure(rootId, towns, locs)
  if mesh and builtFor == rootId then return mesh end
  local anchors = Underlay.anchors(towns, locs)
  if #anchors < 2 then return nil end
  mesh = Underlay.buildMesh(anchors)
  builtFor = rootId
  return mesh
end

-- Draw it. Must be called INSIDE the voxel scene pass -- Voxel3D.draw is a
-- no-op outside one -- which is why main.lua hangs this off beginScene
-- rather than off the render wrap the tornado uses.
-- How many times the sheet has actually gone down. The screenshot suite
-- asserts on it, because "the option is on" and "a draw happened" are not
-- the same claim and the difference is exactly where this went wrong once.
Underlay.drawn = 0

-- `rawDraw` is Voxel3D.draw as it was BEFORE this mod wrapped it. Handed in
-- rather than looked up, because the caller IS that wrapper: going through
-- the table again would re-enter it and recurse.
function Underlay.draw(rootId, towns, locs, rawDraw)
  local DS = V.ds()
  if not DS then return false end
  local tex = buildTexture()
  if not tex then return false end
  local m = Underlay.ensure(rootId, towns, locs)
  if not m then return false end
  ;(rawDraw or DS.require("Voxel3D").draw)(m, tex, nil)
  Underlay.drawn = Underlay.drawn + 1
  return true
end

-- The mesh's world extent, for a caller that wants to know where the sheet
-- actually ended up rather than where it was meant to.
function Underlay.bounds(anchors)
  local ax, bx, az, bz = Underlay.fit(anchors)
  local res = Underlay.residuals(anchors, ax, bx, az, bz)
  local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
  for _, c in ipairs({ { 0, 0 }, { Underlay.TEX_W, 0 },
                       { 0, Underlay.TEX_H },
                       { Underlay.TEX_W, Underlay.TEX_H } }) do
    local wx, wz = Underlay.warp(res, ax, bx, az, bz, c[1], c[2])
    x0, z0 = math.min(x0, wx), math.min(z0, wz)
    x1, z1 = math.max(x1, wx), math.max(z1, wz)
  end
  return x0, z0, x1, z1
end

-- named for the suite
function Underlay._mesh() return mesh end
function Underlay._texture() return texture or nil end

return Underlay
