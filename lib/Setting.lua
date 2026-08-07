-- One of this mod's own settings: a ladder of values, where it persists, and
-- the row the player cycles it on.
--
-- The voxel mod ships a class that does exactly this, and it cannot be
-- borrowed. Its `modId()` reads ITS namespace's `mod` and falls back to the
-- literal string "DRAMATIC_SHAPE", so a setting built from this mod through
-- the exported namespace would read and write inside the voxel mod's own
-- options bucket -- silently, and only noticed when a player's flight
-- settings started following their diorama settings around. So this is the
-- same shape, bound to this mod.
--
-- Two homes for one value, and they cannot disagree because both read it
-- back out of the same place:
--
--   options:define    a row on this mod's page in the mod manager.
--   ui.options.rows   the same setting on the OPTIONS menu, next to the
--                     display rows the player already goes there for.
--
-- Writing mirrors what the manager's own page does (ManagerState:setOption):
-- the live save's options table, the loader's copy that mod.options:get
-- reads, and then the file.

local V = ...

local Setting = {}
Setting.__index = Setting

local function modId()
  local mod = V.mod
  return (mod and mod.id) or "FLYING_OVERHAUL"
end

-- `values` are what gets stored, `labels` what the row shows for each, and
-- `default` which one a fresh save (or an unreadable stored value) lands on.
--
-- The default is named rather than positional -- the voxel mod's equivalent
-- uses values[1], which quietly ties "the first rung" to "the default" and
-- makes reordering a ladder change behaviour. Here KEEP sits first on three
-- of the five ladders and is emphatically not what they default to.
function Setting.new(key, label, values, labels, default, help)
  local self = setmetatable({
    key = key, label = label, values = values, labels = labels,
    default = default, help = help,
    index = nil,        -- nil = not yet read back from the persisted options
  }, Setting)
  assert(#values == #labels, "a ladder needs one label per value: " .. key)
  assert(self:indexOf(default) ~= nil,
         "the default must be on the ladder: " .. key)
  return self
end

function Setting:indexOf(value)
  for i, v in ipairs(self.values) do
    if v == value then return i end
  end
  return nil
end

function Setting:defaultIndex()
  return self:indexOf(self.default) or 1
end

-- What the player left it at last session. Read lazily rather than at load
-- time: the loader fills modOptions before a mod runs, but reading through
-- the API keeps this honest about where the value lives.
function Setting:read()
  if self.index then return self.index end
  local mod = V.mod
  local value
  if mod and mod.options then
    local ok, got = pcall(mod.options.get, mod.options, self.key)
    if ok then value = got end
  end
  self.index = self:indexOf(value) or self:defaultIndex()
  return self.index
end

function Setting:get()
  return self.values[self:read()]
end

function Setting:label_()
  return self.labels[self:read()]
end

function Setting:setIndex(i, game)
  local n = #self.values
  i = ((i - 1) % n + n) % n + 1
  self.index = i
  local value, id = self.values[i], modId()
  local opts = game and game.save and game.save.options
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[id] = opts.modOptions[id] or {}
    opts.modOptions[id][self.key] = value
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id][self.key] = value
  end
  if game and game.writeOptions then pcall(game.writeOptions, game) end
  return value
end

function Setting:setValue(value, game)
  return self:setIndex(self:indexOf(value) or self:defaultIndex(), game)
end

function Setting:cycle(game, dir)
  return self:setIndex(self:read() + (dir or 1), game)
end

-- Adopt a value set from somewhere else (the mod manager's settings page,
-- which writes and persists on its own). Nothing to store: just move the
-- cached index so the next read agrees with it.
function Setting:sync(value)
  self.index = self:indexOf(value) or self:defaultIndex()
end

-- The descriptor src/ui/OptionRows.lua renders, in the shape the
-- ui.options.rows hook appends.
function Setting:row()
  local self_ = self
  return {
    id = modId() .. ":" .. self.key,
    label = self.label,
    value = function() return self_:label_() end,
    step = function(game, dir)
      self_:cycle(game, dir)
      return true
    end,
  }
end

-- The row the mod manager's own settings page builds for this mod.
function Setting:schema()
  local choices = {}
  for i, v in ipairs(self.values) do
    choices[#choices + 1] = { self.labels[i], v }
  end
  return { key = self.key, type = "choice", label = self.label,
           choices = choices, default = self.default, help = self.help }
end

return Setting
