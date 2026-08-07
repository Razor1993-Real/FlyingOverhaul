-- Driver: the real user-facing path, end to end.
--
-- fly_shots.lua asks the ui.party.submenu hook directly, which proves the
-- rewrite but not that the rewrite is what the player actually reaches. This
-- one gives the player a PIDGEOT that knows FLY and the THUNDERBADGE that
-- unlocks it, opens the party menu for real, walks the cursor onto FLY and
-- presses A -- and then asserts what vanilla WOULD have done did not happen:
-- no town map on the stack, and a flight in the air instead.
--
--   POKEPORT_DRIVER=mods/FlyingOverhaul/tests/fly_partymenu_test.lua \
--   POKEPORT_GAME=red lovec.exe .
return function(game)
  io.stdout:setvbuf("no")
  local U = dofile("tests/drivers/util.lua")

  local fails, checks = 0, 0
  local function ok(cond, what)
    checks = checks + 1
    if cond then print("PASS " .. what) else
      fails = fails + 1; print("FAIL " .. what)
    end
  end
  local function eq(got, want, what)
    ok(got == want, ("%s (got %s, want %s)")
       :format(what, tostring(got), tostring(want)))
  end

  local fly = game.mods.exports["FLYING_OVERHAUL"]
  ok(fly ~= nil, "FLYING_OVERHAUL is loaded")
  if not fly then
    print(("%d checks, %d failures"):format(checks, fails))
    return love.event.quit()
  end
  local Flight = fly.lib.require("Flight")
  local Screens = require("src.ui.Screens")

  U.teleport(game, "PALLET_TOWN", 13, 14, "down")
  local ow = game.overworld

  -- a flier, and the badge that lets it be used outside
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(game.data, "PIDGEOT", 40)
  mon.moves = { { id = "FLY", pp = 15 } }
  game.save.party = { mon }
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.THUNDERBADGE = 1
  U.wait(5)

  -- open the party menu the way START > POKEMON does
  Screens.push(game, "PartyMenu")
  U.wait(10)
  local party = game.stack:top()
  ok(party ~= nil and party ~= ow, "the party menu is open")

  -- A on the mon opens its submenu
  U.tap(game, "a")
  U.wait(10)
  ok(party.submenu ~= nil, "the mon's submenu is open")

  local labels = {}
  for i, entry in ipairs(party.subItems or {}) do
    labels[i] = tostring(entry.label)
  end
  print("[party] submenu: " .. table.concat(labels, ", "))

  local flyIndex = nil
  for i, entry in ipairs(party.subItems or {}) do
    if tostring(entry.label):upper() == "FLY" then flyIndex = i break end
  end
  ok(flyIndex ~= nil, "FLY is offered for a PIDGEOT with the THUNDERBADGE")
  if not flyIndex then
    print(("%d checks, %d failures"):format(checks, fails))
    return love.event.quit()
  end

  local flyRow = party.subItems[flyIndex]
  eq(flyRow.action, nil, "the row the player reaches carries no action id")
  ok(type(flyRow.onSelect) == "function", "it carries this mod's callback")

  -- walk the cursor onto FLY and choose it
  while party.subIndex > flyIndex do U.tap(game, "up"); U.wait(3) end
  while party.subIndex < flyIndex do U.tap(game, "down"); U.wait(3) end
  eq(party.subIndex, flyIndex, "the cursor is on FLY")
  U.tap(game, "a")
  U.wait(15)

  -- vanilla would have pushed the town map here
  local top = game.stack:top()
  ok(top == ow, "the overworld is back on top -- no town map was pushed")
  eq(Flight.active(), true, "a flight started instead")
  eq(Flight.phase, "takeoff", "and it is climbing")

  -- and it really is a flight, not a warp: same map, and the bird rises
  eq(ow.map.id, "PALLET_TOWN", "the player is still on the map they left")
  local low = Flight.altitude
  U.wait(40)
  ok(Flight.altitude > low, "the bird is gaining altitude")

  for _ = 1, 300 do
    if Flight.phase == "cruise" then break end
    U.wait(1)
  end
  eq(Flight.phase, "cruise", "the climb reaches free flight")

  print(("%d checks, %d failures"):format(checks, fails))
  love.event.quit()
end
