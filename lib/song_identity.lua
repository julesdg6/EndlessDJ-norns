-- Deterministic, deck-independent song identity foundation.
-- Musical generators consume named child streams so adding a new choice to one
-- subsystem cannot perturb unrelated parts of the record.


local M = {}


local profiles = rawget(_G, "genre_profiles")
if not profiles then
  local ok, result = pcall(require, "genre_profiles")
  profiles = ok and result or dofile("lib/genre_profiles.lua")
end


local MODULUS = 2147483647
local MULTIPLIER = 48271


local function hash_text(text, seed)
  local value = math.max(1, math.floor(seed or 1) % MODULUS)
  for index = 1, #text do
    value = (value * 131 + text:byte(index) + index) % MODULUS
  end
  return math.max(1, value)
end


local Rng = {}
Rng.__index = Rng


function Rng:new(seed)
  return setmetatable({state=math.max(1, math.floor(seed or 1) % MODULUS)}, self)
end


function Rng:next()
  self.state = (self.state * MULTIPLIER) % MODULUS
  return self.state
end


function Rng:float()
