local identity_engine = dofile("lib/song_identity.lua")
local groove_engine = dofile("lib/groove_engine.lua")
local bass_engine = dofile("lib/bass_engine.lua")

local function fail(message)
  io.stderr:write("FAIL: " .. message .. "\n")
  os.exit(1)
end

local function encode(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
  local result = {}
  for _, key in ipairs(keys) do result[#result + 1] = key .. "=" .. encode(value[key]) end
  return "{" .. table.concat(result, ",") .. "}"
end

local genres = {
  "HOUSE","FUNKY","DIRTY","TECHNO","GARAGE4","TWO_STEP",
  "BREAKS","DUBSTEP","DEEP","ACID","TRANCE","PROG","JUNGLE",
  "DNB","LIQUID","HARDTECHNO","ELECTRO","JUKE","AFRO","MINIMAL",
  "MELODIC","SPEED","BASSLINE","HARDSTYLE",
}

for _, genre in ipairs(genres) do
  local identity = identity_engine.new{seed=12048,deck="A",genre=genre}
  local groove = groove_engine.new(identity)
  local first = bass_engine.new(identity, groove)
  local second = bass_engine.new(identity, groove)
  local valid, reason = bass_engine.validate(first)
  if not valid then fail(genre .. " bass plan is invalid: " .. tostring(reason)) end
  if encode(first) ~= encode(second) then fail(genre .. " bass plan is not deterministic") end
  if first.phrase_bars ~= 4 or #first.bars ~= 4 then fail(genre .. " must use a four-bar phrase") end
end

local two_step_voices = {}
for seed = 1, 512 do
  local identity = identity_engine.new{seed=seed,deck="B",genre="TWO_STEP"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  if plan.voice_family == "303" then fail("2-Step selected a forbidden default 303") end
  two_step_voices[plan.voice_family] = true
end
for _, voice in ipairs({"sub","reese","organ","fm"}) do
  if not two_step_voices[voice] then fail("2-Step never selected " .. voice) end
end

for seed = 1, 64 do
  local identity = identity_engine.new{seed=seed,deck="A",genre="ACID"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  if plan.voice_family ~= "303" then fail("Acid House must select the expressive 303 voice") end
  local expressive = false
  for bar = 1, 4 do
    for _, event in pairs(plan.bars[bar]) do
      expressive = expressive or event.accent or event.slide
    end
  end
  if not expressive then fail("Acid phrase lacks accents and slides") end
end

local distinct = {}
for seed = 1, 96 do
  local identity = identity_engine.new{seed=seed,deck="A",genre="HOUSE"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  distinct[encode(plan)] = true
end
local count = 0
for _ in pairs(distinct) do count = count + 1 end
if count < 40 then fail("different seeds do not create sufficiently distinct bass records") end

io.stdout:write("PASS: deterministic genre-aware bass architecture\n")
