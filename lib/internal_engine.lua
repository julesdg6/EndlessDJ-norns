local InternalEngine = {}
local transition_compensation = 0

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
  a, b = a or 0, b or 0
  local overlap = math.min(a, b)
  local compensation = 1 - (overlap * transition_compensation)
  call("deck_level", 1, a * compensation)
  call("deck_level", 2, b * compensation)
end

function InternalEngine.set_transition_compensation(amount)
  transition_compensation = math.max(0, math.min(0.5, amount or 0))
end

function InternalEngine.set_automix(deck_id, settings)
  settings = settings or {}
  call(
    "automix_set", deck_id,
    settings.amount or 0,
    settings.kick_duck or 0.3,
    settings.melody_priority or 0.45
  )
end

function InternalEngine.set_mixer(deck_id, part_id, settings)
  settings = settings or {}
  call(
    "mixer_set", deck_id, part_id,
    settings.level or 1,
    settings.pan or 0,
    settings.filter or 1,
    settings.saturation or 0,
    settings.delay_send or 0,
    settings.reverb_send or 0
  )
end

function InternalEngine.set_fx_returns(deck_id, delay_level, reverb_level)
  call("fx_return_set", deck_id, delay_level or 0.7, reverb_level or 0.7)
end

function InternalEngine.set_master(level, ceiling, compression, threshold)
  call(
    "master_set",
    level or 0.9,
    ceiling or 0.9,
    compression or 0.35,
    threshold or 0.55
  )
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

function InternalEngine.set_n808_model(deck_id, model)
  call("n808_model", deck_id, model or 0)
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

function InternalEngine.chord_on(deck_id, note, velocity, preset)
  call("nchord_on", deck_id, note, velocity / 127, preset or 1)
end

function InternalEngine.chord_off(deck_id, note)
  call("nchord_off", deck_id, note)
end

function InternalEngine.chord_all_off(deck_id)
  call("nchord_all_off", deck_id)
end

function InternalEngine.set_nchord(deck_id, settings)
  call("nchord_model", deck_id, settings.model or 0)
  call(
    "nchord_set",
    deck_id,
    settings.preset,
    settings.brightness,
    settings.filter_env,
    settings.chorus
  )
end

function InternalEngine.set_nchord_control(deck_id, settings, name, value)
  if not settings or settings[name] == nil then return false end
  settings[name] = value
  InternalEngine.set_nchord(deck_id, settings)
  return true
end

function InternalEngine.mono(deck_id, note, velocity, length)
  call("nmono_note", deck_id, note, velocity / 127, length or 1)
end

function InternalEngine.mono_on(deck_id, note, velocity)
  call("nmono_on", deck_id, note, velocity / 127)
end

function InternalEngine.mono_off(deck_id)
  call("nmono_off", deck_id)
end

function InternalEngine.set_nmono(deck_id, settings)
  call("nmono_model", deck_id, settings.model or 0)
  call(
    "nmono_set",
    deck_id,
    settings.preset,
    settings.waveform,
    settings.sub,
    settings.cutoff,
    settings.resonance,
    settings.attack,
    settings.release,
    settings.glide,
    settings.lfo_rate,
    settings.lfo_depth,
    settings.delay_send
  )
end

function InternalEngine.set_nmono_control(deck_id, settings, name, value)
  if not settings or settings[name] == nil then return false end
  settings[name] = value
  InternalEngine.set_nmono(deck_id, settings)
  return true
end

function InternalEngine.bass_voice(deck_id, note, velocity, length)
  call("nbass_note", deck_id, note, velocity / 127, length or 1)
end

function InternalEngine.set_nbass(deck_id, settings)
  call("nbass_model", deck_id, settings.model or 0)
  call(
    "nbass_set",
    deck_id,
    settings.preset,
    settings.waveform,
    settings.sub,
    settings.cutoff,
    settings.resonance,
    settings.attack,
    settings.release,
    settings.glide,
    settings.lfo_rate,
    settings.lfo_depth,
    settings.delay_send
  )
end

function InternalEngine.sampler(deck_id, pad, velocity, settings)
  settings = settings or {}
  call(
    "nsampler_hit", deck_id, pad,
    velocity / 127 * (settings.level or 1),
    settings.rate or 1, settings.pan or 0,
    settings.start or 0, settings.finish or 1,
    settings.cutoff or 1, settings.choke or 0
  )
end

function InternalEngine.sampler_repeat(deck_id, pad, velocity, settings, delay)
  settings = settings or {}
  call(
    "nsampler_repeat", deck_id, pad,
    velocity / 127 * (settings.level or 1),
    settings.rate or 1, settings.pan or 0,
    settings.start or 0, settings.finish or 1,
    settings.cutoff or 1, settings.choke or 0,
    delay or 0.08
  )
end

function InternalEngine.sampler_on(deck_id, pad, velocity, settings)
  settings = settings or {}
  call(
    "nsampler_on", deck_id, pad,
    velocity / 127 * (settings.level or 1),
    settings.rate or 1, settings.pan or 0,
    settings.start or 0, settings.finish or 1,
    settings.cutoff or 1, settings.choke or 0
  )
end

function InternalEngine.sampler_off(deck_id, pad)
  call("nsampler_off", deck_id, pad)
end

function InternalEngine.sampler_loop_on(deck_id, pad, settings)
  settings = settings or {}
  call(
    "nsampler_loop_on", deck_id, pad,
    settings.level or 1, settings.rate or 1, settings.pan or 0,
    settings.start or 0, settings.finish or 1, settings.cutoff or 1
  )
end

function InternalEngine.sampler_loop_off(deck_id, pad)
  call("nsampler_loop_off", deck_id, pad)
end

function InternalEngine.sampler_grain_on(deck_id, pad, settings)
  settings = settings or {}
  call(
    "nsampler_grain_on", deck_id, pad,
    settings.level or 0.65,
    settings.position or 0.5,
    settings.size or 0.12,
    settings.density or 12,
    settings.rate or 1,
    settings.pan or 0,
    settings.spread or 0.6,
    settings.cutoff or 1,
    settings.freeze and 1 or 0
  )
end

function InternalEngine.sampler_grain_off(deck_id)
  call("nsampler_grain_off", deck_id)
end

function InternalEngine.resample_start(source, slot, duration)
  call("resample_start", source, slot, math.min(32, duration or 1))
end

function InternalEngine.resample_record_stop(slot)
  call("resample_record_stop", slot)
end

function InternalEngine.resample_play(deck_id, slot, mode, settings)
  settings = settings or {}
  call(
    "resample_play", deck_id, slot, mode or 1,
    settings.level or 0.8, settings.rate or 1,
    settings.start or 0, settings.finish or 1
  )
end

function InternalEngine.resample_grain_on(deck_id, slot, settings)
  settings = settings or {}
  call(
    "resample_grain_on", deck_id, slot,
    settings.level or 0.65, settings.position or 0.5,
    settings.size or 0.12, settings.density or 12,
    settings.rate or 1, settings.spread or 0.6,
    settings.cutoff or 1, settings.finish or 1,
    settings.freeze and 1 or 0
  )
end

function InternalEngine.resample_stop(deck_id, slot)
  call("resample_stop", deck_id, slot)
end

function InternalEngine.load_sample(pad, path)
  call("nsampler_load", pad, path)
end

return InternalEngine
