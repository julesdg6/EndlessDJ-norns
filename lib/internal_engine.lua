local InternalEngine = {}

local function call(command, ...)
  local fn = engine and engine[command]
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, ...)
  if not ok then
    print("Endless DJ: engine." .. command .. " failed: " .. tostring(err))
  end
  return ok
end

function InternalEngine.deck_id(deck, deck_a)
  return deck == deck_a and 1 or 2
end

function InternalEngine.set_deck_levels(a, b)
  call("deck_level", 1, a)
  call("deck_level", 2, b)
end

function InternalEngine.all_off()
  call("all_off")
end

function InternalEngine.drum(deck_id, voice, velocity)
  call("n808_hit", deck_id, voice, velocity / 127)
end

function InternalEngine.bass(deck_id, note, velocity, length, accent, slide)
  call(
    "n303_note",
    deck_id,
    note,
    velocity / 127,
    length or 1,
    accent and 1 or 0,
    slide and 1 or 0
  )
end

function InternalEngine.chord(deck_id, note, velocity, length, preset)
  call("nchord_note", deck_id, note, velocity / 127, length or 1, preset or 1)
end

function InternalEngine.mono(deck_id, note, velocity, length)
  call("nmono_note", deck_id, note, velocity / 127, length or 1)
end

function InternalEngine.sampler(deck_id, pad, velocity)
  call("nsampler_hit", deck_id, pad, velocity / 127, 1)
end

function InternalEngine.load_sample(pad, path)
  call("nsampler_load", pad, path)
end

return InternalEngine
