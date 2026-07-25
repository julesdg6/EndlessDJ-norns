local InternalEngine = {}

InternalEngine.n808 = {
  tone = 0.5,
  decay = 0.5,
  drive = 0.25,
  variation = 0.15,
}

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

function InternalEngine.set_n808(tone, decay, drive, variation)
  call("n808_set", tone, decay, drive, variation)
end

function InternalEngine.set_n808_control(name, value)
  if InternalEngine.n808[name] == nil then return false end
  InternalEngine.n808[name] = value
  InternalEngine.set_n808(
    InternalEngine.n808.tone,
    InternalEngine.n808.decay,
    InternalEngine.n808.drive,
    InternalEngine.n808.variation
  )
  return true
end

function InternalEngine.set_n808_level(voice, level)
  call("n808_level", voice, level)
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

function InternalEngine.set_n303(deck_id, settings)
  call(
    "n303_set",
    deck_id,
    settings.waveform,
    settings.cutoff,
    settings.resonance,
    settings.env_mod,
    settings.decay,
    settings.drive,
    settings.slide_time
  )
end

function InternalEngine.set_n303_control(deck_id, settings, name, value)
  if not settings or settings[name] == nil then return false end
  settings[name] = value
  InternalEngine.set_n303(deck_id, settings)
  return true
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
