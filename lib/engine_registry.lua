-- Single source of truth for all internal engine model families.
-- Provides name→SC integer mappings, equal-loudness gain coefficients
-- (mirroring Engine_Endless.sc modelGain arrays), and UI display names.
-- Every generator, the song identity, the drum engine, and the mixer
-- consumes this module; no subsystem maintains parallel mapping tables.
local M = {}

-- Drum kit: model name → n-808 SC engine integer (0-based, 5 kits)
M.KIT = { ["808"]=0, ["909"]=1, linn=2, industrial=3, hybrid=4 }

-- Chord engine: model name → nchord SC engine integer (0-based, 5 models)
M.CHORD = { analog=0, fm=1, organ=2, pad=3, rave=4 }

-- Mono/bass engine: model name → nmono/nbass SC engine integer (0-based, 6 models)
M.MONO = { analog=0, sub=1, reese=2, organ=3, fm=4, wobble=5 }

-- UI display strings (1-based, matching params:add_option order)
M.KIT_NAMES   = {"808", "909", "LinnDrum", "industrial", "hybrid"}
M.CHORD_NAMES = {"analog", "FM", "organ / piano", "supersaw / pad", "rave / hoover"}
M.MONO_NAMES  = {"analog", "sub", "reese", "organ", "fm", "wobble"}

-- Equal-loudness gain coefficients mirroring Engine_Endless.sc modelGain arrays.
-- Chord:     analog=0.92, fm=0.78, organ=0.48, pad=0.86, rave=0.70
-- Mono/bass: analog=1.15, sub=1.20, reese=1.10, organ=0.58, fm=1.10, wobble=0.95
-- Kit loudness is balanced inside SC per-voice; no additional Lua coefficient needed.
M.CHORD_GAIN = { analog=0.92, fm=0.78, organ=0.48, pad=0.86, rave=0.70 }
M.MONO_GAIN  = { analog=1.15, sub=1.20, reese=1.10, organ=0.58, fm=1.10, wobble=0.95 }
M.KIT_GAIN   = { ["808"]=1.00, ["909"]=1.00, linn=1.00, industrial=1.00, hybrid=1.00 }

-- Return the SC integer for a drum kit name, or nil if not registered.
function M.kit_id(name)   return M.KIT[name]   end
-- Return the SC integer for a chord engine name, or nil if not registered.
function M.chord_id(name) return M.CHORD[name] end
-- Return the SC integer for a mono/bass engine name, or nil if not registered.
function M.mono_id(name)  return M.MONO[name]  end

-- Validate helpers — return true on success, false + reason string on failure.
-- Use these at song-generation time so unsupported engine combinations are
-- caught before any audio graph is created rather than silently falling back.
function M.validate_kit(name)
  if M.KIT[name] then return true end
  return false, "unknown drum kit: " .. tostring(name)
end

function M.validate_chord(name)
  if M.CHORD[name] then return true end
  return false, "unknown chord engine: " .. tostring(name)
end

function M.validate_mono(name)
  if M.MONO[name] then return true end
  return false, "unknown mono/bass engine: " .. tostring(name)
end

return M
