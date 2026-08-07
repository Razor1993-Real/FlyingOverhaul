-- Driver: photograph a whole flight and assert what it borrowed.
--
--   POKEPORT_DRIVER=mods/FlyingOverhaul/tests/fly_shots.lua \
--   SHOT_DIR=.scratchpad/flyshots POKEPORT_GAME=red lovec.exe .
--
-- Run from the repository root. Writes one PNG per beat and prints a
-- PASS/FAIL line per assertion, so the run is checkable without opening the
-- images -- the images are for the things only an eye can check.
return function(game)
  io.stdout:setvbuf("no")
  local U = dofile("tests/drivers/util.lua")
  local ROOT = os.getenv("SHOT_DIR") or "shots/fly"
  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  local fails, checks = 0, 0
  local function ok(cond, what)
    checks = checks + 1
    if cond then
      print("PASS " .. what)
    else
      fails = fails + 1
      print("FAIL " .. what)
    end
  end
  local function eq(got, want, what)
    ok(got == want, ("%s (got %s, want %s)")
       :format(what, tostring(got), tostring(want)))
  end

  local fly = game.mods.exports["FLYING_OVERHAUL"]
  local dsHandle = game.mods.exports["DRAMATIC_SHAPE"]
  ok(fly ~= nil, "FLYING_OVERHAUL is loaded and exports its handle")
  ok(dsHandle ~= nil, "DRAMATIC_SHAPE is loaded")
  if not (fly and dsHandle) then
    for _, e in ipairs(game.mods.errors or {}) do print("  mod error: " .. e) end
    print(("%d checks, %d failures"):format(checks, fails))
    return love.event.quit()
  end

  local DS = dsHandle.lib
  local V = fly.lib
  local Flight = V.require("Flight")
  local BirdMove = V.require("BirdMove")
  local Atlas = V.require("Atlas")
  local Compass = V.require("Compass")
  local BirdCam = V.require("BirdCam")
  local ChunkMesher = DS.require("ChunkMesher")
  local WorldCurve = DS.require("WorldCurve")
  local Voxel3D = DS.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")
  local ModRuntime = require("src.mods.Runtime")

  do
    local chains = (ModRuntime.hooks and ModRuntime.hooks.chains) or {}
    local names = {}
    for k in pairs(chains) do names[#names + 1] = k end
    table.sort(names)
    print("[fly] hook chains: " .. table.concat(names, ", "))
  end

  local shots = 0
  local function shot(name)
    if U.shot(game, ("%s/%s.png"):format(ROOT, name)) then
      shots = shots + 1
    else
      fails = fails + 1
      print("FAIL screenshot " .. name .. " did not reach disk")
    end
  end
  local function settle(limit)
    for _ = 1, (limit or 1200) do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    U.wait(30)
  end

  -- ------- 1. the party menu's FLY row is rewritten
  --
  -- Asked of the hook chain directly rather than by building a party with a
  -- FLY user and a badge: what is under test is the rewrite, and the
  -- conditions that decide whether the row exists at all are the engine's
  -- and are deliberately untouched.
  do
    local items = {
      { label = "FLY", action = "fly" },
      { label = "STATS", action = "stats" },
    }
    local out = ModRuntime.call("ui.party.submenu",
                                function(_, list) return list end,
                                game, items, nil, {})
    local flyRow = out and out[1]
    ok(type(flyRow) == "table", "the submenu hook returned a list")
    eq(flyRow and flyRow.label, "FLY", "the FLY row keeps its label")
    eq(flyRow and flyRow.action, nil, "the FLY row no longer carries an action")
    ok(flyRow and type(flyRow.onSelect) == "function",
       "the FLY row carries a callback instead -- no town map")
    eq(out and out[2] and out[2].action, "stats",
       "the other rows are left alone")
  end

  -- COLORS: ADVANCED for the whole run. `redpp` is the id, ADVANCED the
  -- label (PaletteFX.MODE_LABELS). It is the richest colourisation the
  -- engine has, and therefore the one that shows up anything of this mod's
  -- that is still drawing in flat Game Boy greys -- the Kanto underlay above
  -- all, which is recoloured by hand and has nothing else to check it.
  do
    local PaletteFX = require("src.render.PaletteFX")
    game.save.options.colors = "redpp"
    PaletteFX.setMode("redpp")
    eq(PaletteFX.modeLabel("redpp"), "ADVANCED", "COLORS is on ADVANCED")
  end

  -- ------- 2. the world before take-off
  U.teleport(game, "PALLET_TOWN", 13, 14, "down")
  local ow = game.overworld
  Pipelines.setLevel("voxel", 3)      -- the player is sitting on "35"
  Pipelines.setLevel("tiltshift", 0)
  WorldCurve.setting:sync(0)
  local wasVoxel = Pipelines.level("voxel")
  local wasTilt = Pipelines.level("tiltshift")
  local wasCurve = WorldCurve.setting:get()
  settle()
  local groundNeighbors = #(ow.neighbors or {})
  shot("01_ground_before")
  ok(not Flight.active(), "no flight before FLY is used")

  -- ------- 3. take off
  ok(fly.begin(), "the flight starts")
  ok(Flight.active(), "the flight is running")
  eq(ow.player.inputLocked, true, "the climb locks the grid walk")

  -- the borrowed settings, in force for the flight
  eq(Pipelines.levelLabel("voxel", Pipelines.level("voxel")), "50",
     "VOXEL is on the 50 rung while flying")
  eq(Pipelines.levelLabel("tiltshift", Pipelines.level("tiltshift")), "2",
     "T-SHIFT is on 2 while flying")
  eq(WorldCurve.level(), 0, "V-CURVE is off while flying -- flat shows more")

  U.wait(30)
  shot("02_climbing")
  ok(Flight.altitude > 0 and Flight.altitude < Flight.CRUISE,
     "the bird is between the ground and cruise mid-climb")

  -- let the climb finish and the wide neighbourhood mesh
  for _ = 1, 300 do
    if Flight.phase == "cruise" then break end
    U.wait(1)
  end
  eq(Flight.phase, "cruise", "the climb reaches cruise")
  ok(math.abs(Flight.altitude - Flight.CRUISE) < 1e-6,
     "cruise sits at the cruise altitude")
  settle()
  shot("03_cruise")

  -- ------- 4. the view distance
  local flyingNeighbors = #(ow.neighbors or {})
  print(("[fly] neighbours: %d on the ground, %d in the air")
        :format(groundNeighbors, flyingNeighbors))
  ok(flyingNeighbors > groundNeighbors,
     "the flight loads more of the world than walking does")

  -- ------- 5. steer: fly north up Route 1 toward Viridian
  local FirstPerson = DS.require("FirstPerson")
  FirstPerson.yaw = math.pi          -- face north (+yaw 0 is south)
  U.wait(10)
  local startY = ow.player.py
  U.hold(game, "up", 240)
  settle()
  local travelled = startY - ow.player.py
  print(("[fly] travelled %d world px north over the hold"):format(travelled))
  ok(travelled > 0, "holding up moves the bird the way the camera looks")

  -- The "3x speed" claim is asserted against the voxel mod's OWN walking
  -- constant rather than against distance covered in N driver frames: the
  -- driver is resumed once per rendered frame, and while thirty-odd maps
  -- are meshing behind the flight a frame is worth a varying number of
  -- fixed logic steps -- so distance-per-frame drifts run to run and would
  -- make this a flaky test of the frame rate rather than a test of the
  -- speed. FreeMove.WALK is what a walking player covers per logic step,
  -- and Flight.SPEED is what BirdMove advances per logic step, so their
  -- ratio IS the promise.
  local FreeMove = DS.require("FreeMove")
  print(("[fly] walk %.2f px/step, flight %.2f px/step")
        :format(FreeMove.WALK, BirdMove.speed()))
  ok(math.abs(BirdMove.speed() - 4.5 * FreeMove.WALK) < 1e-9,
     "the flight advances at exactly 4.5 times the walking speed")
  shot("04_cruise_north")

  -- ------- 5b. the compass, against the real region
  --
  -- The town positions come out of the engine's own connection walk, so this
  -- checks the walk still lays Kanto out the way Kanto is: it would catch a
  -- change in the map data or in computeNeighbors' offset composition, either
  -- of which would silently point the whole ribbon somewhere else.
  do
    local towns = Atlas.towns()
    print(("[fly] atlas knows %d towns"):format(#towns))
    ok(#towns == 11, "all eleven fly towns are placed")

    local by = {}
    for _, t in ipairs(towns) do by[t.id] = t end
    ok(by.PALLET_TOWN ~= nil, "PALLET_TOWN is among them")
    eq(by.VIRIDIAN_CITY and by.VIRIDIAN_CITY.name, "VIRIDIAN CITY",
       "and they carry the town map's own display name")

    -- the layout, sanity-checked against the real geography rather than
    -- against pinned numbers: north is -Z, east is +X
    local pallet = by.PALLET_TOWN
    ok(by.VIRIDIAN_CITY.z < pallet.z, "Viridian is north of Pallet")
    ok(by.PEWTER_CITY.z < by.VIRIDIAN_CITY.z, "Pewter is north of Viridian")
    ok(by.CINNABAR_ISLAND.z > pallet.z, "Cinnabar is south of Pallet")
    ok(by.CERULEAN_CITY.x > pallet.x and by.CERULEAN_CITY.z < pallet.z,
       "Cerulean is north-east of Pallet")
    ok(by.VERMILION_CITY.x > pallet.x, "Vermilion is east of Pallet")
    ok(by.INDIGO_PLATEAU.x < pallet.x and by.INDIGO_PLATEAU.z < pallet.z,
       "Indigo Plateau is north-west of Pallet")

    -- and the ribbon actually picks Viridian out when the bird faces north
    local FirstPerson = DS.require("FirstPerson")
    local p = ow.player
    local markers = Compass.select(towns, p.px + 8, p.py + 8, FirstPerson.yaw)
    local names = {}
    for _, m in ipairs(markers) do
      names[#names + 1] = ("%s(%d)"):format(m.town.id,
                                            math.floor(m.dist / 16))
    end
    print("[fly] ribbon: " .. table.concat(names, " "))
    print(("[fly] compass calls=%d draws=%d skip=%s")
          :format(Compass.calls, Compass.draws, tostring(Compass.lastSkip)))
    ok(Compass.calls > 0, "render.hud reaches the compass")
    ok(Compass.draws > 0, "and the ribbon actually draws")
    ok(#markers > 0, "the ribbon has something on it while flying north")
    ok(#markers <= 8,
       "and never more markers than the arc has sectors -- no pile-up")

    -- an unvisited town is a bare pip until it is the one being flown at
    local unseen = nil
    for _, m in ipairs(markers) do
      if not m.town.visited then unseen = m break end
    end
    if unseen then
      local wasCentred = unseen.centred
      unseen.centred = false
      eq(#Compass.labelFor(unseen), 0,
         "an unvisited town off-centre stays anonymous")
      unseen.centred = true
      eq(Compass.labelFor(unseen)[1], "? NOT EXPLORED",
         "and centred it says why you cannot go there")
      unseen.centred = wasCentred
    else
      print("[fly] note: no unvisited town on the ribbon, label case skipped")
    end

    -- ------- and the same ribbon with names on it
    --
    -- The driver's save has only Pallet visited, so every marker above is a
    -- question mark. Mark a few towns seen and rebuild, which is both the
    -- picture worth looking at and the only check that the NAMED path lays
    -- out without collisions.
    local visited = game.save.visited or {}
    game.save.visited = visited
    local restore = {}
    for _, id in ipairs({ "PEWTER_CITY", "CERULEAN_CITY", "CELADON_CITY",
                          "VIRIDIAN_CITY", "SAFFRON_CITY" }) do
      restore[id] = visited[id]
      visited[id] = true
    end
    Atlas.close()
    Atlas.open(ow.map.id)
    local named = Compass.select(Atlas.towns(), p.px + 8, p.py + 8,
                                 FirstPerson.yaw)
    local shown = {}
    for _, m in ipairs(named) do
      if m.town.visited then
        shown[#shown + 1] = Compass.labelFor(m)[1]
      end
    end
    print("[fly] named ribbon: " .. table.concat(shown, " | "))
    ok(#shown > 0, "visited towns show their names on the ribbon")

    -- The names come through WHOLE, from the field registry. The ribbon used
    -- to trim " CITY" off with a hardcoded English suffix list -- so this
    -- checks the untrimmed name, which is also the check that a translation
    -- mod's names would survive.
    local sawFullName = false
    for _, label in ipairs(shown) do
      if label:find(" CITY", 1, true) or label:find(" TOWN", 1, true) then
        sawFullName = true
      end
    end
    ok(sawFullName, "and they keep the whole name, CITY or TOWN included")
    settle()
    shot("09_compass_named")

    for id, was in pairs(restore) do visited[id] = was end
    Atlas.close()
    Atlas.open(ow.map.id)
  end

  -- ------- 5c. the bird shows all four of its frames
  --
  -- The sheet always had them; the body's heading was pinned to the camera's
  -- yaw, and the camera is boomed along that same yaw, so the bird sat at a
  -- constant 180 degrees from the lens and only ever drew its back.
  --
  -- Checked through the real chain -- Player:pose to VoxelScene's frame
  -- picker -- rather than against the arithmetic, which the logic suite
  -- already covers. Photographed too, because "the bird is facing the wrong
  -- way" is a thing only an eye catches.
  do
    local Player = require("src.world.Player")
    local SR = require("src.render.SpriteRenderer")
    local pl = ow.player
    FirstPerson.yaw = 0                     -- look south, steady
    U.wait(4)

    local function frameNow()
      -- what the 3D pass would draw: the pose's facing rotated into the
      -- camera's own frame, exactly as VoxelScene's viewFacing asks for it
      local _, _, _, facing = Player.pose(pl)
      return FirstPerson.playerFacing(facing, pl.px + 8, pl.py + 8)
    end

    -- UP is forward: FirstPerson.moveVector reads mz as up-minus-down, so
    -- the up button is the one that pushes the bird away from the camera.
    --
    -- The direction is held ACROSS the screenshot rather than released
    -- first. A hovering bird turns back to face the way the player is
    -- looking, which is correct behaviour and takes about a third of a
    -- second -- long enough that a shot taken after the release photographs
    -- the bird already back on its old heading, and the picture disagrees
    -- with the assertion beside it.
    local seen, order = {}, {}
    for _, run in ipairs({ { "up", "forward" }, { "down", "backward" },
                           { "left", "strafe left" }, { "right", "strafe right" } }) do
      local btn, what = run[1], run[2]
      local src = "flyshot"
      game.input:sourcePress(btn, src)
      U.wait(40)
      local f = frameNow()
      order[#order + 1] = ("%s=%s"):format(what, tostring(f))
      if f then seen[f] = true end
      shot("10_facing_" .. what:gsub(" ", "_"))
      game.input:sourceRelease(btn, src)
      U.wait(20)
    end
    print("[fly] bird frames: " .. table.concat(order, "  "))

    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    eq(n, 4, "flying the four ways draws four different sprite frames")
    ok(seen.up and seen.down and seen.left and seen.right,
       "and they are the four the sheet actually holds")

    -- the frame indices those map to are the walker layout's own
    ok(SR.STAND.down ~= SR.STAND.up and SR.STAND.up ~= SR.STAND.left,
       "the three stand frames are distinct rows of the sheet")
  end

  -- a quarter turn: the camera is camera-relative, so the world should be
  -- seen from a different bearing rather than always from the south
  FirstPerson.yaw = math.pi / 2
  U.wait(20)
  settle()
  shot("05_cruise_yawed_east")

  -- ------- 6. the flight does not walk the world
  --
  -- Crossing cells at altitude must not run the landing pipeline: no
  -- encounters, no warps, no step counting. The step counter is the
  -- cheapest honest witness for all three.
  local before = game.save.stepCounter or game.save.steps or 0
  U.hold(game, "down", 90)
  local after = game.save.stepCounter or game.save.steps or 0
  eq(after, before, "flying over cells does not count steps")
  eq(game.stack:top(), ow, "flying over cells does not start a battle")

  -- ------- 7. land
  --
  -- Put the bird over water first and confirm it refuses, then over the
  -- town and confirm it goes down.
  -- re-read ow.player each time: a landing that crosses a seam runs setMap,
  -- and a stale player reference would be poking at the map before it
  local function place(cx, cy)
    local pl = ow.player
    pl.cellX, pl.cellY = cx, cy
    pl.px, pl.py = cx * 16, cy * 16
    BirdMove.drop()
    U.wait(2)
  end
  local p = ow.player

  local waterCell = nil
  for cy = 0, ow.map.def.height * 2 - 1 do
    for cx = 0, ow.map.def.width * 2 - 1 do
      if ow.map:isWaterCell(cx, cy) then waterCell = { cx, cy } break end
    end
    if waterCell then break end
  end
  if waterCell then
    place(waterCell[1], waterCell[2])
    ok(not Flight.canLandAt(ow.map, p.cellX, p.cellY),
       "the sea is refused as a landing spot")
    local landed, why = fly.land()
    ok(not landed, "a landing request over water is refused")
    eq(why, "terrain", "and the refusal is about the ground, not the map")
    ok(Flight.active(), "the flight continues after a refused landing")
  else
    print("[fly] note: no water cell on this map, refusal case skipped")
  end

  -- ------- 7b. you cannot land somewhere you have never been
  --
  -- Self-validating, like the trainer case: the SAME landing is tried over a
  -- map the player has walked and over one they have not. If the explored
  -- one were refused too, the refusal below would be proving nothing.
  do
    Atlas.ensureLedger()
    local here = ow.map.id
    ok(Atlas.explored(here),
       ("the map the flight took off from (%s) counts as explored"):format(here))

    -- A LOADED neighbour the player has not been to. Loaded, because the
    -- terrain question needs a real Map object -- and the bird is clamped to
    -- the loaded neighbourhood anyway, so it could never be anywhere else.
    local unseen, seen = nil, nil
    for _, nb in ipairs(ow.neighbors or {}) do
      local d = nb.map.def
      -- a walkable cell somewhere near the middle, so the refusal under test
      -- is about the ledger and not about landing in a lake
      for _, frac in ipairs({ 0.5, 0.35, 0.65 }) do
        local lx = math.floor(d.width * 2 * frac)
        local ly = math.floor(d.height * 2 * frac)
        if nb.map:isWalkableCell(lx, ly) and not nb.map:isWaterCell(lx, ly) then
          local cand = { nb = nb, wx = nb.ox + lx * 16, wz = nb.oy + ly * 16 }
          if Atlas.explored(nb.map.id) then seen = seen or cand
          else unseen = unseen or cand end
          break
        end
      end
    end

    local function hover(c)
      local pl = ow.player
      pl.px, pl.py = c.wx, c.wz
      pl.cellX, pl.cellY = math.floor(c.wx / 16), math.floor(c.wz / 16)
      BirdMove.drop()
      U.wait(2)
    end

    -- the control: a neighbour the player HAS been to accepts the landing,
    -- which is what makes the refusal below mean something
    if seen then
      hover(seen)
      eq(BirdMove.mapUnder(ow), seen.nb.map.id,
         ("the bird knows it is over %s"):format(seen.nb.map.id))
      local okLand, why = fly.land()
      ok(okLand, ("a landing on %s, which the player has walked, is accepted")
         :format(seen.nb.map.id))
      if okLand then
        for _ = 1, 300 do
          if not Flight.active() then break end
          U.wait(1)
        end
        eq(ow.map.id, seen.nb.map.id,
           "and the crossing is made official -- the player is on that map")
        ok(fly.begin(), "back into the air for the refusal case")
        for _ = 1, 400 do
          if Flight.phase == "cruise" then break end
          U.wait(1)
        end
      else
        print("[fly] refused: " .. tostring(why))
      end
    else
      print("[fly] note: no explored neighbour found, control case skipped")
    end

    if not unseen then
      print("[fly] note: every neighbour is explored, refusal case skipped")
    else
      -- re-resolve against the map the player is on now
      local nb = nil
      for _, cand in ipairs(ow.neighbors or {}) do
        if cand.map.id == unseen.nb.map.id then nb = cand break end
      end
      if not nb then
        print("[fly] note: the unexplored map is no longer a neighbour, skipped")
      else
        local d = nb.map.def
        local lx = math.floor(d.width * 2 * 0.5)
        local ly = math.floor(d.height * 2 * 0.5)
        hover({ wx = nb.ox + lx * 16, wz = nb.oy + ly * 16 })
        eq(BirdMove.mapUnder(ow), nb.map.id,
           ("the bird knows it is over %s"):format(nb.map.id))
        local landed, why = fly.land()
        ok(not landed, "a landing on a map never visited is refused")
        eq(why, "unexplored", "and the refusal says why, not just 'no'")
        ok(Flight.active(), "the flight continues")

        -- the player is told, rather than merely buzzed at
        Compass.say("CAN'T LAND HERE", "NEVER BEEN HERE YET")
        ok(Compass._toast() ~= nil, "the hint is on screen")
        settle()
        shot("08_cannot_land_here")
        Compass.clear()
      end
    end
  end

  -- Home ground: a walkable cell on the map the player is standing on now,
  -- which the control landing above may have changed. Found rather than
  -- hardcoded, so this section does not depend on where the flight ended up.
  local homeCell = nil
  do
    local d = ow.map.def
    for _, frac in ipairs({ 0.5, 0.4, 0.6, 0.3, 0.7 }) do
      local lx = math.floor(d.width * 2 * frac)
      local ly = math.floor(d.height * 2 * frac)
      if ow.map:isWalkableCell(lx, ly) and not ow.map:isWaterCell(lx, ly) then
        homeCell = { lx, ly }
        break
      end
    end
  end
  ok(homeCell ~= nil, "the current map has somewhere to put down")
  place(homeCell[1], homeCell[2])
  ok(Flight.canLandAt(ow.map, p.cellX, p.cellY), "that ground accepts a landing")
  ok(Atlas.explored(BirdMove.mapUnder(ow)),
     "and the map under the bird is one the player has walked")
  shot("06_landing_approach")
  ok(fly.land(), "the landing is accepted")
  eq(Flight.phase, "landing", "the descent has begun")

  for _ = 1, 300 do
    if not Flight.active() then break end
    U.wait(1)
  end
  ok(not Flight.active(), "the flight ends")
  eq(ow.player.inputLocked, false, "the player has the grid walk back")
  eq(Voxel3D.camera, nil, "the placed bird camera is handed back")
  settle()
  shot("07_landed")

  -- ------- 8. the borrowed settings are given back
  eq(Pipelines.level("voxel"), wasVoxel, "VOXEL is back where the player left it")
  eq(Pipelines.level("tiltshift"), wasTilt, "T-SHIFT is back")
  eq(WorldCurve.level(), wasCurve, "V-CURVE is back")
  -- back to the screen's own neighbourhood. Compared against the FLIGHT's
  -- count rather than against the take-off map's: a landing that crossed a
  -- seam ends on a different map, whose own narrow neighbourhood is a
  -- different (small) number.
  local landedNeighbors = #(ow.neighbors or {})
  print(("[fly] neighbours after landing: %d (was %d in the air)")
        :format(landedNeighbors, flyingNeighbors))
  ok(landedNeighbors < flyingNeighbors / 2,
     "the wide neighbourhood is released on landing")

  -- ------- 9. nobody challenges a bird
  --
  -- Trainer sight does not come through the landing pipeline -- update()
  -- checks it directly, off the player's logical cell -- so suppressing it
  -- is its own wrap and deserves its own check.
  --
  -- Self-validating on purpose: the same placement is tested on the GROUND
  -- as well. If the grounded case did not engage, the bird standing there
  -- unchallenged would prove nothing about the wrap and everything about a
  -- badly chosen cell.
  --
  -- The FLYING case runs first and the control LAST, deliberately. A trainer
  -- who sights the player does not merely set a flag: startTrainerApproach
  -- arms the "!" beat whose onDone walks them over and pushes the battle, and
  -- unwinding that from outside is guesswork. Run last, its side effects have
  -- nothing left to pollute -- the driver quits on the next line.
  do
    local DIRVEC = { up = { 0, -1 }, down = { 0, 1 },
                     left = { -1, 0 }, right = { 1, 0 } }
    local found, foundMap = nil, nil
    for _, mapId in ipairs({ "ROUTE_3", "ROUTE_24", "ROUTE_22", "ROUTE_4" }) do
      U.teleport(game, mapId, 5, 5, "down")
      U.wait(5)
      local o = game.overworld
      for _, npc in ipairs(o.npcs or {}) do
        local d = npc.def
        if d and d.trainerClass and DIRVEC[npc.facing]
           and not o:trainerDefeated(npc) then
          local header = game.data:trainerHeader(o.map.def.label, d.index)
          if header and (header.range or 0) > 0 then
            found, foundMap = npc, mapId
            break
          end
        end
      end
      if found then break end
    end

    if not found then
      print("[fly] note: no sighted trainer found, the sight case is skipped")
    else
      local o = game.overworld
      local vec = DIRVEC[found.facing]
      local pl = o.player
      local function stand(cells)
        pl.cellX = found.cellX + vec[1] * cells
        pl.cellY = found.cellY + vec[2] * cells
        pl.px, pl.py = pl.cellX * 16, pl.cellY * 16
        pl.moving = false
      end

      -- the case under test: the same cell, six cells up
      ok(fly.begin(), "a flight starts on the trainer's route")
      for _ = 1, 300 do
        if Flight.phase == "cruise" then break end
        U.wait(1)
      end
      eq(Flight.phase, "cruise", "the test flight reaches cruise")
      stand(1)
      o.engaging = false
      o:checkTrainerSight()
      eq(o.engaging, false,
         "the trainer does not challenge the player flying overhead")
      eq(game.stack:top(), game.overworld,
         "and nothing was pushed over the overworld")

      stand(0)
      if fly.land() then
        for _ = 1, 300 do
          if not Flight.active() then break end
          U.wait(1)
        end
      end
      ok(not Flight.active(), "the test flight is landed again")

      -- the control, last: on the ground, the very same cell must engage --
      -- otherwise the check above proved nothing
      stand(1)
      o.engaging = false
      o:checkTrainerSight()
      ok(o.engaging and true or false,
         ("the same trainer on %s DOES sight the player on the ground")
         :format(foundMap))
    end
  end

  -- ------- 10. the options menu
  --
  -- Asked of the real hook chain, so this covers the rows actually reaching
  -- the OPTIONS menu rather than the table this mod hands over.
  do
    local Options = V.require("Options")
    local base = { { id = "text_speed", label = "TEXT SPEED" } }
    local out = ModRuntime.call("ui.options.rows",
                                function(_, rows) return rows end, game, base)
    ok(type(out) == "table", "the options hook returned a list")

    local mine = {}
    for _, row in ipairs(out or {}) do
      if type(row) == "table" and tostring(row.id):find("FLYING_OVERHAUL", 1, true) then
        mine[#mine + 1] = row
      end
    end
    eq(#mine, 7, "all seven FLY rows reach the OPTIONS menu")
    eq(out[1] and out[1].id, "text_speed", "and the engine's own rows keep their place")

    for _, row in ipairs(mine) do
      ok(type(row.label) == "string" and row.label ~= "",
         ("%s has a label"):format(tostring(row.id)))
      ok(type(row.value(game)) == "string",
         ("%s renders a value"):format(tostring(row.id)))
    end

    -- stepping a row really moves the stored value, not just the display
    local before = Options.speed:get()
    local speedRow = nil
    for _, row in ipairs(mine) do
      if tostring(row.id):find("speed", 1, true) then speedRow = row end
    end
    ok(speedRow ~= nil, "FLY SPEED is one of them")
    if speedRow then
      speedRow.step(game, 1)
      ok(Options.speed:get() ~= before, "stepping it changes the stored value")
      local stored = game.save.options.modOptions
                     and game.save.options.modOptions.FLYING_OVERHAUL
      eq(stored and stored.speed, Options.speed:get(),
         "and it lands in this mod's own options bucket, not another mod's")
      Options.speed:setValue(before, game)
      eq(Options.speed:get(), before, "restored for the rest of the run")
    end
  end

  -- ------- 11. the newer options actually change the flight
  --
  -- One flight per case, each asserting the thing the setting promises
  -- rather than merely that the value stored.
  do
    local Options = V.require("Options")
    local Tornado = V.require("Tornado")
    local Voxel3D = DS.require("Voxel3D")

    -- A clean map to work from. The trainer section above deliberately ends
    -- with one engaged -- that is its control case -- and a flight started
    -- into that state never gets the pad, because engagement gates
    -- handleInput exactly as it gates the grid walk.
    U.teleport(game, "PALLET_TOWN", 13, 14, "down")
    U.wait(5)
    ow = game.overworld
    local homeCell = nil
    do
      local d = ow.map.def
      for _, frac in ipairs({ 0.5, 0.4, 0.6, 0.3, 0.7 }) do
        local lx = math.floor(d.width * 2 * frac)
        local ly = math.floor(d.height * 2 * frac)
        if ow.map:isWalkableCell(lx, ly) and not ow.map:isWaterCell(lx, ly) then
          homeCell = { lx, ly }
          break
        end
      end
    end
    ok(homeCell ~= nil, "somewhere to put down on the options round")
    homeCell = homeCell or { 13, 14 }

    local function flyOnce(after)
      ok(fly.begin(), "took off")
      for _ = 1, 500 do
        if Flight.phase == "cruise" then break end
        U.wait(1)
      end
      after()
      -- put it back down wherever it is standing, or just end the flight
      local pl = ow.player
      pl.cellX, pl.cellY = homeCell[1], homeCell[2]
      pl.px, pl.py = pl.cellX * 16, pl.cellY * 16
      BirdMove.drop()
      U.wait(2)
      local down, why = fly.land()
      ok(down, ("the round landed again (%s)"):format(tostring(why)))
      for _ = 1, 400 do
        if not Flight.active() then break end
        U.wait(1)
      end
      ok(not Flight.active(), "and the flight is over before the next one")
    end

    -- FLY VOXEL: OFF -- the diorama is off for the flight and comes back
    local wasVox = Pipelines.level("voxel")
    Options.voxel:sync("OFF")
    flyOnce(function()
      eq(Pipelines.level("voxel"), 0, "FLY VOXEL OFF flies over the flat world")
      settle()
      shot("11_voxel_off")
    end)
    eq(Pipelines.level("voxel"), wasVox, "and the player's own rung comes back")

    -- FLY VOXEL: 75 -- the rung that used to push the bird out of frame
    Options.voxel:sync("75")
    flyOnce(function()
      eq(Pipelines.levelLabel("voxel", Pipelines.level("voxel")), "75",
         "FLY VOXEL 75 takes the diorama to its lowest rung")
      local rig = BirdCam._rig()
      ok(rig ~= nil, "the bird camera is placed")
      if rig then
        -- the bird, measured against the axis the camera actually looks
        -- along: this is the check the 75 rung used to fail outright
        local ex, ey, ez = rig.eye[1], rig.eye[2], rig.eye[3]
        local fx, fy, fz = rig.focus[1], rig.focus[2], rig.focus[3]
        local pl = ow.player
        local bx, by, bz = pl.px + 8, Flight.altitude, pl.py + 8
        local function ang(ax, ay, az, bx2, by2, bz2)
          local d1 = math.sqrt(ax * ax + ay * ay + az * az)
          local d2 = math.sqrt(bx2 * bx2 + by2 * by2 + bz2 * bz2)
          if d1 < 1e-6 or d2 < 1e-6 then return 0 end
          local dot = (ax * bx2 + ay * by2 + az * bz2) / (d1 * d2)
          return math.acos(math.max(-1, math.min(1, dot)))
        end
        local off = ang(fx - ex, fy - ey, fz - ez, bx - ex, by - ey, bz - ez)
        print(("[fly] bird sits %.1f degrees off the view axis at rung 75")
              :format(math.deg(off)))
        ok(math.deg(off) < 29,
           "and the bird is inside the lens rather than off the top of it")
      end
      settle()
      shot("12_voxel_75")
    end)
    Options.voxel:sync("50")

    -- FLY LOOK -- steering the camera up and down keeps the bird in shot
    ok(Options.look:get() == true, "FLY LOOK is on by default")
    flyOnce(function()
      local FP = DS.require("FirstPerson")
      local seenAngles = {}
      for _, pitch in ipairs({ -math.rad(40), 0, math.rad(60) }) do
        FP.pitch = pitch
        U.wait(6)
        local rig = BirdCam._rig()
        if rig then
          seenAngles[#seenAngles + 1] = rig.eye[2] - rig.focus[2]
        end
      end
      ok(#seenAngles == 3, "the camera rebuilt at each look angle")
      ok(seenAngles[1] ~= seenAngles[3],
         "and looking up and down really moves the eye")
      FP.pitch = 0
      U.wait(6)
      shot("13_look_steered")
    end)

    -- the tornado runs on the climb and the descent, and not between them
    Tornado.reset()
    ok(not Tornado.visible(), "no wind with the flight on the ground")
    ok(fly.begin(), "took off for the wind")
    U.wait(20)
    ok(Tornado.visible(), "the funnel is up during the climb")
    settle()
    shot("14_tornado_takeoff")
    for _ = 1, 500 do
      if Flight.phase == "cruise" then break end
      U.wait(1)
    end
    U.wait(60)
    ok(not Tornado.visible(), "and gone once the bird is cruising")
    local pl = ow.player
    pl.cellX, pl.cellY = homeCell[1], homeCell[2]
    pl.px, pl.py = pl.cellX * 16, pl.cellY * 16
    BirdMove.drop()
    U.wait(2)
    if fly.land() then
      U.wait(20)
      ok(Tornado.visible(), "it comes back for the descent")
      shot("15_tornado_landing")
      for _ = 1, 400 do
        if not Flight.active() then break end
        U.wait(1)
      end
    end
    U.wait(60)
    ok(not Tornado.visible(), "and is gone again once down")
    ok(Voxel3D ~= nil, "the voxel renderer was reachable throughout")
  end

  -- ------- 12. Kanto under the void
  --
  -- The picture is what this is for, so it is photographed with and without.
  -- The assertions cover the two things a screenshot cannot settle: that the
  -- sheet is really built out of the game's own data, and that OFF means
  -- nothing is built rather than something drawn invisibly.
  do
    local Options = V.require("Options")
    local Underlay = V.require("Underlay")

    ok(Options.underlay:get() == true, "KANTO MAP is on by default")

    ok(fly.begin(), "up for a look at the underlay")
    for _ = 1, 500 do
      if Flight.phase == "cruise" then break end
      U.wait(1)
    end
    settle()

    ok(Underlay._texture() ~= nil, "the Kanto sheet was built")
    ok(Underlay._mesh() ~= nil, "and warped into a mesh")
    -- Not the same claim as "the option is on", and the difference is
    -- exactly where this went wrong once: the sheet spent an afternoon
    -- built, warped, projected on screen and never actually drawn.
    ok(Underlay.drawn > 0, "and the draw call actually ran")
    shot("16_underlay_on")

    -- Where the two shots below will be compared: a point the bird is
    -- flying over (a real map, so terrain owns those pixels) and a point
    -- out in the void (no map, so the sheet owns them).
    local onTown = { Voxel3D.project(ow.player.px + 8, Underlay.DEPTH,
                                     ow.player.py + 8) }
    local onVoid = { Voxel3D.project(-900, Underlay.DEPTH, 700) }

    -- the anchors, resolved against the live region rather than a fixture:
    -- every town must sit exactly where the world says it does
    do
      local region = Atlas.forMap(ow.map.id)
      local locs = ((game.data.field or {}).townMap or {}).locations or {}
      local anchors = Underlay.anchors(region and region.towns or {}, locs)
      eq(#anchors, 11, "all eleven towns anchor the sheet")
      local ax, bx, az, bz = Underlay.fit(anchors)
      local res = Underlay.residuals(anchors, ax, bx, az, bz)
      local worst = 0
      for _, a in ipairs(anchors) do
        local wx, wz = Underlay.warp(res, ax, bx, az, bz, a.tx, a.ty)
        worst = math.max(worst, math.abs(wx - a.wx), math.abs(wz - a.wz))
      end
      print(("[fly] underlay worst anchor miss: %.3f world px"):format(worst))
      ok(worst < 1, "and each lands on its real position")
    end

    -- OFF: nothing built, nothing drawn
    Options.underlay:sync(false)
    Underlay.invalidate()
    U.wait(20)
    settle()
    shot("17_underlay_off")
    eq(Underlay._mesh(), nil, "OFF leaves no mesh behind to draw")

    -- THE "covers nothing" CLAIM, put to the two pictures rather than to
    -- the theory behind it. Same camera, sheet on and off: over the map the
    -- frame must be unchanged -- the terrain won the depth test, which is
    -- the entire mechanism -- and out in the void it must have changed,
    -- because that is where the sheet is allowed to speak.
    do
      local function pixelAt(name, p)
        if not p[1] then return nil end
        local f = io.open(("%s/%s.png"):format(ROOT, name), "rb")
        if not f then return nil end
        local bytes = f:read("*a"); f:close()
        local okImg, img = pcall(love.image.newImageData,
                                 love.filesystem.newFileData(bytes, "s.png"))
        if not okImg then return nil end
        local w, h = img:getDimensions()
        local x = math.min(w - 1, math.max(0, math.floor(p[1])))
        local y = math.min(h - 1, math.max(0, math.floor(p[2])))
        return { img:getPixel(x, y) }
      end
      local function same(a, b)
        if not (a and b) then return nil end
        for i = 1, 4 do
          if math.abs((a[i] or 0) - (b[i] or 0)) > 1 / 255 then return false end
        end
        return true
      end
      local townOn = pixelAt("16_underlay_on", onTown)
      local townOff = pixelAt("17_underlay_off", onTown)
      local voidOn = pixelAt("16_underlay_on", onVoid)
      local voidOff = pixelAt("17_underlay_off", onVoid)
      ok(same(townOn, townOff) == true,
         "over the map the sheet changes not one pixel")
      ok(same(voidOn, voidOff) == false,
         "and out in the void it is what fills the hole")
    end

    Options.underlay:sync(true)
    U.wait(20)
    ok(Options.underlay:get() == true, "and it comes back on")

    -- a landing cell on whatever map this round left us on, rather than one
    -- another section computed for a map we may no longer be over
    local pl = ow.player
    local d = ow.map.def
    for _, frac in ipairs({ 0.5, 0.4, 0.6, 0.3, 0.7 }) do
      local lx = math.floor(d.width * 2 * frac)
      local ly = math.floor(d.height * 2 * frac)
      if ow.map:isWalkableCell(lx, ly) and not ow.map:isWaterCell(lx, ly) then
        pl.cellX, pl.cellY = lx, ly
        break
      end
    end
    pl.px, pl.py = pl.cellX * 16, pl.cellY * 16
    BirdMove.drop()
    U.wait(2)
    local down, why = fly.land()
    ok(down, ("and back down (%s)"):format(tostring(why)))
    for _ = 1, 400 do
      if not Flight.active() then break end
      U.wait(1)
    end
  end

  print(("[fly] %d screenshots in %s"):format(shots, ROOT))
  print(("%d checks, %d failures"):format(checks, fails))
  love.event.quit()
end
