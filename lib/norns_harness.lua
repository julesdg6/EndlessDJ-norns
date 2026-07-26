local Harness = {}

local REQUIRED_COMMANDS = {
  "all_off", "automix_set", "deck_level", "fx_return_set", "master_set",
  "mixer_set", "n303_note", "n303_set", "n808_hit", "n808_level",
  "n808_set", "nchord_all_off", "nchord_note", "nchord_off",
  "nchord_on", "nchord_set", "nmono_note", "nmono_off", "nmono_on",
  "nmono_set", "nsampler_grain_off", "nsampler_grain_on",
  "nsampler_hit", "nsampler_load", "nsampler_loop_off",
  "nsampler_loop_on", "nsampler_off", "nsampler_on",
  "nsampler_repeat", "resample_analyze", "resample_grain_on",
  "resample_play", "resample_record_stop", "resample_start", "resample_stop",
}

local ROUTE_PARAMS = {
  "drums_output", "bass_output", "chords_output", "mono_output",
  "samples_output",
}

local function command_available(name)
  return engine and type(engine[name]) == "function"
end

local function command_count()
  local count = 0
  for _ in pairs((engine and engine.commands) or {}) do count = count + 1 end
  return count
end

local function count_role_samples(sample_library)
  local count = 0
  for _, samples in pairs(sample_library.factory_roles or {}) do
    count = count + #samples
  end
  return count
end

local function safe_engine(name, ...)
  local fn = engine and engine[name]
  if type(fn) ~= "function" then
    return false, "missing engine." .. name
  end
  local ok, err = pcall(fn, ...)
  if not ok then return false, tostring(err) end
  return true
end

local function safe_stop(poll_instance)
  if poll_instance and type(poll_instance.stop) == "function" then
    pcall(function() poll_instance:stop() end)
  end
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function Harness.new(options)
  options = options or {}
  local instance = {
    version = options.version or "unknown",
    sample_library = options.sample_library or {},
    restore_audio = options.restore_audio,
    running = false,
    active_clock = nil,
  }

  local function snapshot_params()
    local saved = {}
    if not params or type(params.get) ~= "function" then return saved end
    for _, id in ipairs(ROUTE_PARAMS) do
      local ok, value = pcall(function() return params:get(id) end)
      if ok then saved[id] = value end
    end
    return saved
  end

  local function restore_params(saved)
    if not params or type(params.set) ~= "function" then return end
    for id, value in pairs(saved or {}) do
      pcall(function() params:set(id, value) end)
    end
  end

  local function force_internal_routes()
    if not params or type(params.set) ~= "function" then return end
    for _, id in ipairs(ROUTE_PARAMS) do
      pcall(function() params:set(id, 3) end)
    end
  end

  local function cleanup(active_polls)
    for _, poll_instance in ipairs(active_polls or {}) do
      safe_stop(poll_instance)
    end
    safe_engine("nsampler_grain_off", 1)
    safe_engine("nsampler_grain_off", 2)
    for deck = 1, 2 do
      safe_engine("nmono_off", deck)
      safe_engine("nchord_all_off", deck)
      for slot = 1, 2 do safe_engine("resample_stop", deck, slot) end
    end
    safe_engine("all_off")
  end

  local function run_checks(mode, report, metrics)
    report("INFO", "version " .. instance.version)
    report("INFO", "registered engine commands " .. command_count())

    for _, name in ipairs(REQUIRED_COMMANDS) do
      if command_available(name) then
        report("PASS", "engine." .. name)
      else
        report("FAIL", "missing engine." .. name)
      end
    end

    local risers = #(instance.sample_library.factory_risers or {})
    local roles = count_role_samples(instance.sample_library)
    report(risers == 32 and "PASS" or "FAIL", "factory risers " .. risers .. "/32")
    report(roles == 28 and "PASS" or "FAIL", "role one-shots " .. roles .. "/28")

    safe_engine("deck_level", 1, 1)
    safe_engine("deck_level", 2, mode == "quick" and 0 or 0.65)
    safe_engine("master_set", 0.8, 0.9, 0.35, 0.55)
    safe_engine("fx_return_set", 1, 0.35, 0.35)
    safe_engine("automix_set", 1, 0.5, 0.3, 0.45)
    for part = 1, 5 do
      safe_engine("mixer_set", 1, part, 0.75, 0, 1, 0, 0.08, 0.08)
    end

    report("TEST", "n-808")
    safe_engine("n808_hit", 1, 0, 0.9)
    clock.sleep(0.16)
    safe_engine("n808_hit", 1, 1, 0.8)

    report("TEST", "n-303 accent and slide")
    safe_engine("n303_note", 1, 36, 0.7, 0.25, 1, 0)
    clock.sleep(0.18)
    safe_engine("n303_note", 1, 43, 0.7, 0.25, 0, 1)

    report("TEST", "n-chord gate cleanup")
    for _, note in ipairs({60, 63, 67}) do
      safe_engine("nchord_on", 1, note, 0.45, 1)
    end
    clock.sleep(0.22)
    safe_engine("nchord_all_off", 1)

    report("TEST", "n-mono gate cleanup")
    safe_engine("nmono_on", 1, 67, 0.5)
    clock.sleep(0.2)
    safe_engine("nmono_off", 1)

    if risers > 0 then
      report("TEST", "n-sampler one-shot")
      safe_engine("nsampler_hit", 1, 17, 0.45, 1, 0, 0, 1, 1, 0)
    else
      report("FAIL", "n-sampler smoke test skipped: no factory riser")
    end

    if mode == "quick" then return end

    report("TEST", "Deck B and sampler modes")
    safe_engine("n808_hit", 2, 4, 0.65)
    if risers > 0 then
      safe_engine("nsampler_on", 2, 17, 0.35, 1, 0, 0, 1, 1, 0)
      clock.sleep(0.12)
      safe_engine("nsampler_off", 2, 17)
      safe_engine("nsampler_loop_on", 2, 17, 0.25, 1, 0, 0, 0.0625, 1)
      clock.sleep(0.18)
      safe_engine("nsampler_loop_off", 2, 17)
      safe_engine("nsampler_repeat", 1, 17, 0.3, 1, 0, 0, 0.0625, 1, 0, 0.06)
      safe_engine("nsampler_grain_on", 1, 17, 0.22, 0.5, 0.08, 6, 1, 0, 0.4, 1, 0)
      clock.sleep(0.25)
      safe_engine("nsampler_grain_off", 1)
    end

    report("TEST", "live resampling")
    safe_engine("mixer_set", 1, 1, 1, 0, 1, 0, 0, 0)
    safe_engine("resample_start", 1, 1, 1)
    clock.sleep(0.08)
    safe_engine("n808_hit", 1, 0, 0.9)
    clock.sleep(0.2)
    safe_engine("n808_hit", 1, 1, 0.8)
    clock.sleep(0.25)
    safe_engine("resample_record_stop", 1)
    safe_engine("resample_analyze", 1, 0.0625)
    clock.sleep(2.2)
    safe_engine("resample_play", 1, 1, 1, 0.4, 1, 0, 0.0625)
    clock.sleep(2.2)
    safe_engine("resample_stop", 1, 1)

    local signal_threshold = 0.001
    report(
      metrics.record > signal_threshold and "PASS" or "FAIL",
      "resample record peak " .. string.format("%.4f", metrics.record)
    )
    report(
      metrics.buffer > signal_threshold and "PASS" or "FAIL",
      "resample buffer peak " .. string.format("%.4f", metrics.buffer)
    )
    report(
      metrics.playback > signal_threshold and "PASS" or "FAIL",
      "resample playback peak " .. string.format("%.4f", metrics.playback)
    )

    if mode == "interactive" then
      report("LISTEN", "confirm drums, acid, chord, mono, sampler and replay were audible")
      report("LISTEN", "confirm Deck A/B balance, FX and master level were clean")
    end

    report("INFO", "CPU max avg " .. string.format("%.2f", metrics.cpu_avg))
    report("INFO", "CPU max peak " .. string.format("%.2f", metrics.cpu_peak))
  end

  function instance:run(mode)
    mode = mode or "quick"
    if mode == "resample" then mode = "full" end
    if mode ~= "quick" and mode ~= "full" and mode ~= "interactive" then
      print("ENDLESS HARNESS FAIL: mode must be quick, full or interactive")
      return false
    end
    if self.running then
      print("ENDLESS HARNESS: already running")
      return false
    end

    self.running = true
    local saved_params = snapshot_params()
    local active_polls = {}
    local metrics = {
      cpu_avg=0, cpu_peak=0, record=0, buffer=0, playback=0,
    }
    local failures = 0
    local started_at = os.date("%Y-%m-%d %H:%M:%S")

    local function report(status, message)
      print("ENDLESS HARNESS " .. status .. ": " .. message)
      if status == "FAIL" then failures = failures + 1 end
    end

    local function meter(name, field)
      local ok, poll_instance = pcall(function()
        return poll.set(name, function(value)
          metrics[field] = math.max(metrics[field], value or 0)
        end)
      end)
      if not ok or not poll_instance then
        report("FAIL", "poll " .. name)
        return
      end
      poll_instance.time = 0.2
      poll_instance:start()
      table.insert(active_polls, poll_instance)
    end

    force_internal_routes()
    meter("cpu_avg", "cpu_avg")
    meter("cpu_peak", "cpu_peak")
    if mode ~= "quick" then
      meter("resample_record_peak_1", "record")
      meter("resample_buffer_peak_1", "buffer")
      meter("resample_playback_peak_1", "playback")
    end

    self.active_clock = clock.run(function()
      local ok, err = xpcall(
        function() run_checks(mode, report, metrics) end,
        debug.traceback
      )
      if not ok then report("FAIL", "runtime " .. tostring(err)) end

      cleanup(active_polls)
      restore_params(saved_params)
      if type(self.restore_audio) == "function" then
        local restored, restore_err = pcall(self.restore_audio)
        if not restored then
          report("FAIL", "restore audio " .. tostring(restore_err))
        end
      end
      os.execute(
        "journalctl --since " .. shell_quote(started_at) ..
        " | grep -Eic 'xrun|overrun|underrun' | " ..
        "xargs echo ENDLESS_HARNESS_XRUN_COUNT"
      )

      report("INFO", "cleanup complete")
      if failures == 0 then
        report("PASS", mode .. " mode complete")
      else
        report("FAIL", failures .. " stage(s) failed")
      end
      self.running = false
      self.active_clock = nil
    end)
    return true
  end

  function instance:stop()
    if self.active_clock and clock and type(clock.cancel) == "function" then
      pcall(clock.cancel, self.active_clock)
    end
    cleanup({})
    if type(self.restore_audio) == "function" then
      pcall(self.restore_audio)
    end
    self.running = false
    self.active_clock = nil
  end

  return instance
end

return Harness
