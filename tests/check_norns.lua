local function fail(msg)
  io.stderr:write("FAIL: " .. msg .. "\n")
  os.exit(1)
end

local function pass(msg)
  io.stdout:write("PASS: " .. msg .. "\n")
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function find_script()
  local candidates = {
    "EndlessDJ.lua",
    "endless_dj.lua",
    "endlessdj.lua",
    "endless_dj/endless_dj.lua"
  }
  for _, path in ipairs(candidates) do
    if read_file(path) then return path end
  end
  local p = io.popen("find . -type f -name '*.lua' -not -path './tests/*' | head -n 1")
  if not p then return nil end
  local path = p:read("*l")
  p:close()
  if path and path:sub(1,2) == "./" then path = path:sub(3) end
  return path
end

local path = find_script()
if not path then fail("No Norns Lua script found") end
local source = read_file(path)
if not source then fail("Could not read " .. path) end
pass("Found script: " .. path)

if not source:find("Endless DJ v1.124", 1, true) then
  fail("Script version must match PR #124")
end
pass("Script version matches PR #124")

for _, name in ipairs({"init","redraw","key","enc","cleanup"}) do
  if not source:match("function%s+" .. name .. "%s*%(") then
    fail("Missing required entry point: " .. name .. "()")
  end
end
pass("Required Norns entry points exist")

local notes = {KICK=36, SNARE=38, CLAP=50, TOM=47, CHH=42, OHH=46}
for name, note in pairs(notes) do
  if not source:match("local%s+" .. name .. "%s*=%s*" .. note) then
    fail(name .. " must use T-8 MIDI note " .. note)
  end
end
pass("T-8 MIDI map is correct")

for _, genre in ipairs({
  "HOUSE","FUNKY","DIRTY","TECHNO",
  "GARAGE4","TWO_STEP","BREAKS","DUBSTEP",
  "DEEP","ACID","TRANCE","PROG",
  "JUNGLE","DNB","LIQUID","HARDTECHNO",
  "ELECTRO","JUKE","AFRO","MINIMAL",
  "MELODIC","SPEED","BASSLINE","HARDSTYLE"
}) do
  if not source:find('"' .. genre .. '"', 1, true) then
    fail("Missing genre: " .. genre)
  end
end
pass("All required genres exist")

do
  local _, init_start = source:find("function init()", 1, true)
  local init_end = init_start and source:find("\n  midi_out =", init_start, true)
  local startup = init_start and init_end and source:sub(init_start, init_end) or ""
  if not startup:find('deck_a = make_deck("A")', 1, true) or
      not startup:find('deck_b = make_deck("B", deck_a.genre)', 1, true) then
    fail("Both startup decks must use the normal randomized deck generator")
  end
  if not startup:find("deck_a.active = true", 1, true) or
      not startup:find("deck_b.active = false", 1, true) then
    fail("Random startup must leave Deck A active and Deck B queued")
  end
  if not source:find("while genre == excluded_genre", 1, true) then
    fail("Startup deck generation must avoid duplicate opening genres")
  end
end
pass("Startup decks are randomized with distinct genres")

do
  local defaults_at = source:find("params:default()", 1, true)
  local final_param_at = source:find('params:add_trigger("mpx8_test"', 1, true)
  local grid_connect_at = source:find("grid_connect()", final_param_at, true)
  if not defaults_at then
    fail("Startup must restore and apply the last-used pset with params:default()")
  end
  if not final_param_at or defaults_at < final_param_at then
    fail("Last-used pset must be restored after every parameter is registered")
  end
  if not grid_connect_at or defaults_at > grid_connect_at then
    fail("Last-used pset must be restored before startup services are connected")
  end
end
pass("Last-used pset is restored after parameter registration")

do
  local expected_sections = {
    "hardware_connections_sep", "output_routes_sep", "transport", "mixer_sep",
    "n808_sep", "n303_sep", "acid_sep", "nchord_sep", "nmono_sep",
    "norns_inst_sep", "nsampler_sep", "resample_sep", "acapella_sep",
    "mx1", "nts1_sep", "mpx8_sep", "grid_sep",
  }
  local order_cursor = source:find('local section_order = {', 1, true)
  if not order_cursor then fail("Missing explicit PARAMS menu section order") end
  for _, id in ipairs(expected_sections) do
    local found = source:find('"' .. id .. '"', order_cursor, true)
    if not found or found < order_cursor then
      fail("PARAMS menu section is missing or out of order: " .. id)
    end
    order_cursor = found + #id + 2
  end

  local hardware_start = source:find(
    'params:add_separator("hardware_connections_sep"', 1, true
  )
  local routing_start = source:find(
    'params:add_separator("output_routes_sep"', hardware_start, true
  )
  if not hardware_start or not routing_start then
    fail("Missing hardware-connections or output-routing section")
  end
  local hardware = source:sub(hardware_start, routing_start)
  for _, id in ipairs({
    "t8_midi_device", "drum_ch", "bass_ch",
    "j6_midi_device", "chord_ch", "mx1_midi_device", "mx1_ch",
    "nts1_midi_device", "nts1_ch", "mpx8_midi_device", "mpx8_ch",
  }) do
    if not hardware:find('"' .. id .. '"', 1, true) then
      fail("Hardware mapping must be at the top of PARAMS: " .. id)
    end
  end
end
pass("PARAMS menu starts with hardware mapping and follows workflow order")

if not source:find("chord_midi_out", 1, true) then
  fail("J-6 must use a separate MIDI output")
end

if not source:find("j6_midi_device", 1, true) then
  fail("Missing J-6 MIDI device parameter")
end
pass("Separate J-6 MIDI routing exists")

if not source:find("current_bar = MIX_BARS + 1", 1, true) then
  fail("Incoming deck should continue from bar MIX_BARS+1 after the 32-bar mix")
end
pass("32-bar mix handover continues at bar MIX_BARS+1")

-- Calling quiet_notes() inside finish_handover() sends 4096 MIDI note-off
-- messages (128 notes × 16 channels × 2 devices) in a tight Lua loop,
-- blocking the metro callback thread for several seconds.  This is exactly
-- what caused the "quiet for a few bars / catches up" symptom (issue #24).
-- Every note_on is already paired with a scheduled note_off via note_on_to(),
-- so quiet_notes() is not needed here and must not be re-introduced.
do
  local _, fh_start = source:find("local function finish_handover", 1, true)
  if not fh_start then
    fail("finish_handover function not found")
  end
  -- Find the closing 'end' that terminates finish_handover.
  local fh_end = source:find("\nlocal ", fh_start)
  local fh_body = source:sub(fh_start, fh_end)
  -- Strip line comments (--...) before searching for actual function calls.
  local fh_no_comments = fh_body:gsub("%-%-[^\n]*", "")
  if fh_no_comments:find("quiet_notes%s*%(") then
    fail("Regression: finish_handover must not call quiet_notes() -- " ..
         "it floods MIDI with 4096 note-off messages, causing a quiet period at handover (issue #24)")
  end
end
pass("finish_handover does not call quiet_notes()")

if source:match("local%s+CLAP%s*=%s*39") then
  fail("Regression: T-8 clap must be note 50, not 39")
end
pass("No T-8 clap regression")

if not source:find('"Endless"', 1, true) then
  fail("Custom Endless engine must be referenced as engine.name")
end
pass("Custom Endless engine selected")

if source:find('include("EndlessDJ-norns/', 1, true) then
  fail("Norns module includes must use the installed EndlessDJ folder, not the repository name")
end
for _, module in ipairs({"output_router", "internal_engine"}) do
  if not source:find('include("EndlessDJ/lib/' .. module .. '")', 1, true) then
    fail("Missing Norns-safe include path for " .. module)
  end
end
pass("Internal modules use the installed EndlessDJ folder")

do
  local engine_source = read_file("lib/Engine_Endless.sc")
  if not engine_source then
    fail("Missing custom SuperCollider engine")
  end
  if engine_source:find("Crone.output", 1, true) then
    fail("Custom engines must route through their CroneAudioContext, not Crone.output")
  end
  if not engine_source:find("context.out_b", 1, true) then
    fail("Custom engine must route its mixer to context.out_b")
  end
  if not engine_source:find("context.xg", 1, true) then
    fail("Custom engine synths must belong to context.xg")
  end
  if not engine_source:find("server.sync", 1, true) then
    fail("Custom engine must wait for SynthDef uploads before creating mixer nodes")
  end
  for _, command in ipairs({"n808_set", "n808_level"}) do
    if not engine_source:find("addCommand(\\" .. command, 1, true) then
      fail("Custom engine is missing " .. command .. " command")
    end
  end
  if not engine_source:find("openHats", 1, true) then
    fail("n-808 must maintain per-deck open-hat state for choking")
  end
  if not engine_source:find("n303Voices", 1, true) or
      not engine_source:find("n303SlidePending", 1, true) then
    fail("n-303 must maintain a persistent voice and slide state per deck")
  end
  if not engine_source:find("addCommand(\\n303_set", 1, true) then
    fail("Custom engine is missing n303_set command")
  end
  if not engine_source:find('addCommand(\\n303_set, "ifffffff"', 1, true) then
    fail("n303_set must address one deck followed by seven patch controls")
  end
  if not engine_source:find("Limiter.ar", 1, true) then
    fail("n-303 must bound resonant and driven output")
  end
  for command, format in pairs({
    nchord_on="iifi", nchord_off="ii", nchord_all_off="i", nchord_set="iifff"
  }) do
    if not engine_source:find(
        "addCommand(\\" .. command .. ', "' .. format .. '"', 1, true
      ) then
      fail("Custom engine is missing " .. command .. " command or format")
    end
  end
  if not engine_source:find("nchordHeld", 1, true) then
    fail("n-chord must track held notes independently for each deck")
  end
  for command, format in pairs({
    nmono_note="iiff", nmono_on="iif", nmono_off="i",
    nmono_set="iiffffffffff", nmono_model="ii"
  }) do
    if not engine_source:find(
        "addCommand(\\" .. command .. ', "' .. format .. '"', 1, true
      ) then
      fail("Custom engine is missing " .. command .. " command or format")
    end
  end
  if not engine_source:find("nmonoVoices", 1, true) then
    fail("n-mono must allocate one persistent voice per deck")
  end
end
pass("Custom engine uses the supplied Crone audio context")

do
  local engine_source = read_file("lib/Engine_Endless.sc") or ""
  for _, synthdef in ipairs({
    "endlessAutoMeter", "endlessInstrumentMixer", "endlessDelayReturn",
    "endlessReverbReturn", "endlessDeckMixer", "endlessMaster",
  }) do
    if not engine_source:find("SynthDef(\\" .. synthdef, 1, true) then
      fail("Internal mixer is missing " .. synthdef)
    end
  end
  for command, format in pairs({
    mixer_set="iiffffff", fx_return_set="iff", automix_set="ifff",
    master_set="ffff",
  }) do
    if not engine_source:find(
        "addCommand(\\" .. command .. ', "' .. format .. '"', 1, true
      ) then
      fail("Internal mixer is missing " .. command .. " command or format")
    end
  end
  for _, token in ipairs({
    "instrumentBuses", "delayBuses", "reverbBuses", "masterBus",
    "autoControlBuses", "Amplitude.kr", "ReplaceOut.kr",
    "Compander.ar", "Limiter.ar", "FreeVerb2.ar", "CombC.ar",
    "DetectSilence.ar", "Impulse.ar(0)", "doneAction: 1", "wakePart",
  }) do
    if not engine_source:find(token, 1, true) then
      fail("Internal mixer is missing architecture token " .. token)
    end
  end
  if engine_source:find("\\out, deckBuses[deck].index, \\voice", 1, true) or
      engine_source:find("\\out, deckBuses[deck].index, \\buf", 1, true) then
    fail("Internal voices must feed instrument channels before deck buses")
  end
  for _, wake in ipairs({
    "this.wakePart(deck, 0)", "this.wakePart(deck, 1)",
    "this.wakePart(deck, 2)", "this.wakePart(deck, 3)",
    "this.wakePart(deck, 4)",
  }) do
    if not engine_source:find(wake, 1, true) then
      fail("Silent mixer suspension is missing wake path " .. wake)
    end
  end
  local instrument_mixer = engine_source:match(
    "SynthDef%(\\endlessInstrumentMixer,(.-)SynthDef%(\\endlessDelayReturn,"
  ) or ""
  if instrument_mixer:find("DetectSilence", 1, true) or
      instrument_mixer:find("doneAction: 1", 1, true) then
    fail("Stem mixers must remain persistent so the first transient is never lost")
  end
  local wake_harness_source = read_file("lib/norns_harness.lua") or ""
  if not wake_harness_source:find('"20 persistent-mixer first hits"', 1, true) or
      not wake_harness_source:find("first_hit_missing == 0", 1, true) or
      not wake_harness_source:find("peak <= 0.05", 1, true) then
    fail("Full Norns harness must test 20 present first kick transients")
  end
  if engine_source:find("resampleBuffers[slot].zero", 1, true) then
    fail("Resampling must not race asynchronous buffer clearing against recording")
  end
end
for _, param in ipairs({
  "auto_mixer_mode", "auto_mixer_headroom", "auto_mixer_kick_duck",
  "auto_mixer_melody_priority", "auto_mixer_transition",
}) do
  if not source:find('"' .. param .. '"', 1, true) then
    fail("Auto mixer is missing parameter " .. param)
  end
end
for _, token in ipairs({
  "automix_patch_for_genre", "automix=automix_patch_for_genre",
  "mixer_apply_deck(deck_a, 1)", "mixer_apply_deck(deck_b, 2)",
}) do
  if not source:find(token, 1, true) then
    fail("Per-song auto mixer is missing " .. token)
  end
end
for _, part in ipairs({"drums", "bass", "chords", "mono", "samples"}) do
  if not source:find('"' .. part .. '"', 1, true) then
    fail("Internal mixer is missing channel " .. part)
  end
end
if not source:find('"mix_" .. channel_name .. "_" .. name', 1, true) then
  fail("Internal mixer parameter generation is missing")
end
for _, control in ipairs({
  "level", "pan", "filter", "saturation", "delay_send", "reverb_send",
}) do
  if not source:find('{"' .. control .. '"', 1, true) then
    fail("Internal mixer is missing channel control " .. control)
  end
end
for _, param in ipairs({
  "mix_delay_return", "mix_reverb_return", "mix_master_level",
  "mix_master_compression", "mix_master_threshold", "mix_limiter_ceiling",
}) do
  if not source:find('"' .. param .. '"', 1, true) then
    fail("Internal mixer is missing parameter " .. param)
  end
end
do
  local previous_engine = engine
  local mixer_received, returns_received, automix_received, master_received
  local deck_levels = {}
  engine = {
    mixer_set = function(...) mixer_received = {...} end,
    fx_return_set = function(...) returns_received = {...} end,
    automix_set = function(...) automix_received = {...} end,
    deck_level = function(...) deck_levels[#deck_levels + 1] = {...} end,
    master_set = function(...) master_received = {...} end,
  }
  local internal = dofile("lib/internal_engine.lua")
  internal.set_mixer(2, 4, {
    level=0.8, pan=-0.2, filter=0.7, saturation=0.3,
    delay_send=0.4, reverb_send=0.5,
  })
  internal.set_fx_returns(2, 0.6, 0.7)
  internal.set_automix(2, {
    amount=0.65, kick_duck=0.3, melody_priority=0.45,
  })
  internal.set_transition_compensation(0.25)
  internal.set_deck_levels(0.7, 0.7)
  internal.set_master(0.9, 0.88, 0.4, 0.52)
  engine = previous_engine
  if not mixer_received or mixer_received[1] ~= 2 or
      mixer_received[2] ~= 4 or mixer_received[8] ~= 0.5 then
    fail("Mixer wrapper must forward deck, channel, and six controls")
  end
  if not returns_received or returns_received[1] ~= 2 or
      returns_received[3] ~= 0.7 then
    fail("FX return wrapper must forward both return levels")
  end
  if not automix_received or automix_received[1] ~= 2 or
      automix_received[2] ~= 0.65 or automix_received[4] ~= 0.45 then
    fail("Auto mixer wrapper must forward deck and dynamic controls")
  end
  if not deck_levels[1] or deck_levels[1][2] >= 0.7 or
      not deck_levels[2] or deck_levels[2][2] >= 0.7 then
    fail("Transition compensation must reduce overlapping deck levels")
  end
  if not master_received or master_received[3] ~= 0.4 or
      master_received[4] ~= 0.52 then
    fail("Master wrapper must forward compression and limiting controls")
  end
end
pass("Auto mixer, five channels, dual send/returns, and mastering exist")

do
  local engine_source = read_file("lib/Engine_Endless.sc") or ""
  for _, voice in ipairs({
    "Kick", "Snare", "Clap", "Tom", "ClosedHat", "OpenHat",
  }) do
    if not engine_source:find("SynthDef(\\endless808" .. voice, 1, true) then
      fail("n-808 CPU optimization is missing dedicated " .. voice .. " SynthDef")
    end
  end
  if engine_source:find("voiceSignals", 1, true) then
    fail("n-808 must not calculate all six drum voices for every hit")
  end
end
pass("n-808 calculates only the requested drum voice")

do
  local engine_source = read_file("lib/Engine_Endless.sc") or ""
  for _, token in ipairs({
    "nchordSynthDefs = Array.fill(8",
    "SynthDef(nchordSynthDefs[presetIndex]",
    "nchordSynthDefs[nchordPreset[deck] - 1]",
  }) do
    if not engine_source:find(token, 1, true) then
      fail("n-chord CPU optimization is missing " .. token)
    end
  end
  if engine_source:find("presetIndex, signals", 1, true) then
    fail("n-chord must not calculate all eight sound models for every note")
  end
end
pass("n-chord calculates only the selected sound model")

for _, control in ipairs({"tone", "decay", "drive", "variation"}) do
  if not source:find('"n808_" .. name', 1, true) or
      not source:find('{"' .. control .. '", "n-808 ' .. control, 1, true) then
    fail("Missing n-808 " .. control .. " performance parameter")
  end
end
for _, voice in ipairs({"kick", "snare", "clap", "tom", "closed hat", "open hat"}) do
  if not source:find('"' .. voice .. '"', 1, true) then
    fail("Missing n-808 " .. voice .. " level")
  end
end
if not source:find("internal_engine.set_n808_control", 1, true) or
    not source:find("internal_engine.set_n808_level", 1, true) then
  fail("n-808 parameters must be forwarded through the internal engine wrapper")
end
pass("n-808 performance controls and per-voice levels exist")

if not source:find('"n303_waveform"', 1, true) then
  fail("Missing n-303 waveform parameter")
end
for _, control in ipairs({
  "cutoff", "resonance", "env_mod", "decay", "drive", "slide_time"
}) do
  if not source:find('{"' .. control .. '", "n-303 ', 1, true) then
    fail("Missing n-303 " .. control .. " performance parameter")
  end
end
if not source:find("internal_engine.set_n303_control", 1, true) then
  fail("n-303 parameters must be forwarded through the internal engine wrapper")
end
if not source:find("n303_patch_for_genre", 1, true) or
    not source:find("n303 = n303_patch_for_genre", 1, true) then
  fail("Every generated deck must receive a genre-shaped n-303 patch")
end
if not source:find("n303_apply_deck(deck_a, false)", 1, true) or
    not source:find("n303_apply_deck(deck_b, false)", 1, true) then
  fail("Deck A and Deck B n-303 patches must be applied independently")
end
do
  local previous_engine = engine
  local received
  engine = {
    n303_set = function(...)
      received = {...}
    end
  }
  local internal = dofile("lib/internal_engine.lua")
  local patch = {
    waveform=1, cutoff=0.2, resonance=0.3, env_mod=0.4,
    decay=0.5, drive=0.6, slide_time=0.7
  }
  internal.set_n303(2, patch)
  engine = previous_engine
  if not received or received[1] ~= 2 or received[8] ~= patch.slide_time then
    fail("n-303 wrapper must send the target deck and all seven patch controls")
  end
end
pass("n-303 uses independent, genre-shaped per-song patches")

if not source:find("play_norns_instrument", 1, true) then
  fail("Missing play_norns_instrument function")
end
if not source:find("norns_presets", 1, true) then
  fail("Missing norns_presets definitions")
end
if not source:find("internal_engine.chord", 1, true) then
  fail("Norns instrument must target the internal n-chord voice")
end
if not source:find("internal_engine.chord_on", 1, true) or
    not source:find("internal_engine.chord_off", 1, true) then
  fail("Norns grid keyboard must use gated n-chord note on/off commands")
end
if not source:find("nchord_patch_for_genre", 1, true) or
    not source:find("nchord = nchord_patch_for_genre", 1, true) then
  fail("Every generated deck must receive a genre-shaped n-chord patch")
end
if not source:find("nchord_voice_notes", 1, true) then
  fail("n-chord must apply generated inversion and octave spread")
end
for _, param in ipairs({"nchord_preset", "nchord_inversion", "nchord_spread", "nchord_strum"}) do
  if not source:find('"' .. param .. '"', 1, true) then
    fail("Missing n-chord parameter " .. param)
  end
end
for _, control in ipairs({"brightness", "filter_env", "chorus"}) do
  if not source:find('{"' .. control .. '", "n-chord ', 1, true) then
    fail("Missing n-chord parameter nchord_" .. control)
  end
end
if source:find("engine%.attack", 1, true) then
  fail("Regression: unsupported engine.attack call")
end
pass("Generated n-chord poly synth and gated keyboard support exist")

if not source:find("nmono_patch_for_genre", 1, true) or
    not source:find("nmono = nmono_patch_for_genre", 1, true) then
  fail("Every generated deck must receive a genre-shaped n-mono patch")
end
if not source:find("nmono_apply_deck(deck_a, false)", 1, true) or
    not source:find("nmono_apply_deck(deck_b, false)", 1, true) then
  fail("Deck A and Deck B n-mono patches must be applied independently")
end
for _, param in ipairs({"nmono_preset", "nmono_model", "nmono_waveform"}) do
  if not source:find('"' .. param .. '"', 1, true) then
    fail("Missing n-mono parameter " .. param)
  end
end
for _, control in ipairs({
  "sub", "cutoff", "resonance", "attack", "release",
  "glide", "lfo_rate", "lfo_depth", "delay_send"
}) do
  if not source:find('{"' .. control .. '", "n-mono ', 1, true) then
    fail("Missing n-mono control " .. control)
  end
end
for _, token in ipairs({
  "nmono_model_names", "nmono_model_palettes", "nmono_model_for_genre",
  "TWO_STEP={1,2,3,4}", "DUBSTEP={1,2,4,5}",
}) do
  if not source:find(token, 1, true) then
    fail("Missing deterministic genre-shaped n-mono model token " .. token)
  end
end
local engine_source = read_file("lib/Engine_Endless.sc") or ""
for _, token in ipairs({
  "model.clip(0, 5)", "subVoice", "reese", "organ", "fm", "wobble",
  'addCommand(\\nmono_model, "ii"',
}) do
  if not engine_source:find(token, 1, true) then
    fail("Missing interchangeable n-mono model implementation " .. token)
  end
end
local acid_start = engine_source:find("SynthDef(\\endless303", 1, true)
local chord_start = engine_source:find("8.do({ arg presetIndex;", 1, true)
local mono_start = engine_source:find("SynthDef(\\endlessMono", 1, true)
local sampler_start = engine_source:find("SynthDef(\\endlessSampler", 1, true)
if not acid_start or not chord_start or
    engine_source:sub(acid_start, chord_start):find("DetectSilence", 1, true) or
    not mono_start or not sampler_start or
    engine_source:sub(mono_start, sampler_start):find("DetectSilence", 1, true) then
  fail("Persistent n-303 and n-mono voices must not self-pause while idle")
end
local mono_set_pos = engine_source:find("nmonoVoices[deck].set(", 1, true)
local mono_run_pos = engine_source:find("nmonoVoices[deck].run(true);", 1, true)
local acid_set_pos = engine_source:find("n303Voices[deck].set(*controls);", 1, true)
local acid_run_pos = engine_source:find("n303Voices[deck].run(true);", 1, true)
if not mono_set_pos or not mono_run_pos or mono_set_pos > mono_run_pos or
    not acid_set_pos or not acid_run_pos or acid_set_pos > acid_run_pos then
  fail("Persistent synth controls must be applied before dormant nodes resume")
end
pass("Generated persistent n-mono synth and controls exist")

if not source:find('include("EndlessDJ/lib/sample_library")', 1, true) then
  fail("Missing Norns-safe sample library include")
end
if not source:find("sample_library.load_factory", 1, true) or
    not source:find("sample_library.role_for_seed", 1, true) then
  fail("Factory sampler roles must load automatically and vary stably per song")
end
if not source:find('params:add_file("nsampler_pad_"', 1, true) then
  fail("N-SAMPLER must expose persistent user sample assignments")
end
do
  if not engine_source:find('addCommand(\\nsampler_hit, "iiffffffi"', 1, true) then
    fail("N-SAMPLER playback controls/choke command is missing")
  end
  for command, format in pairs({
    nsampler_on="iiffffffi", nsampler_off="ii"
  }) do
    if not engine_source:find(
        "addCommand(\\" .. command .. ', "' .. format .. '"', 1, true
      ) then
      fail("N-SAMPLER is missing gated command " .. command)
    end
  end
  if not engine_source:find("Array.fill(76", 1, true) or
      not engine_source:find("samplerChokes", 1, true) then
    fail("N-SAMPLER must allocate user, riser, role buffers and choke state")
  end
  if not engine_source:find("samplerHeld", 1, true) then
    fail("N-SAMPLER must track gated user pads independently per deck")
  end
end
do
  local p = io.popen("find samples/factory/risers -type f -name '*.wav' | sort")
  if not p then fail("Could not inspect factory risers") end
  local count = 0
  for wav in p:lines() do
    local header = read_file(wav)
    if not header or header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "WAVE" then
      fail("Invalid factory WAV: " .. wav)
    end
    count = count + 1
  end
  p:close()
  if count ~= 32 then fail("Expected 32 factory risers, found " .. count) end
end
do
  local p = io.popen("find samples/factory/oneshots -type f -name '*.wav' | sort")
  if not p then fail("Could not inspect factory role one-shots") end
  local count = 0
  for wav in p:lines() do
    local header = read_file(wav)
    if not header or header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "WAVE" then
      fail("Invalid factory role WAV: " .. wav)
    end
    count = count + 1
  end
  p:close()
  if count ~= 28 then fail("Expected 28 factory role one-shots, found " .. count) end
end
for _, param in ipairs({
  "nsampler_edit_pad", "nsampler_test_pad", "nsampler_release_pad",
}) do
  if not source:find('"' .. param .. '"', 1, true) then
    fail("Missing N-SAMPLER user control " .. param)
  end
end
for _, label in ipairs({
  "level", "pitch", "reverse", "pan", "start",
  "finish", "cutoff", "choke", "gated",
}) do
  if not source:find('{"' .. label .. '"', 1, true) then
    fail("Missing N-SAMPLER per-pad control " .. label)
  end
end
for _, role in ipairs({
  "perc_accent", "alt_perc", "short_fill", "long_fill",
  "impact", "riser", "vocal_stab", "drop_accent",
}) do
  if not source:find('"' .. role .. '"', 1, true) then
    fail("Missing N-SAMPLER factory role " .. role)
  end
end
pass("N-SAMPLER roles, persistent pads, full controls, gating, and variation exist")

do
  if not engine_source:find("SynthDef(\\endlessSamplerLoop", 1, true) then
    fail("Advanced sampler must provide a persistent loop SynthDef")
  end
  for command, format in pairs({
    nsampler_loop_on="iiffffff", nsampler_loop_off="ii"
  }) do
    if not engine_source:find(
        "addCommand(\\" .. command .. ', "' .. format .. '"', 1, true
      ) then
      fail("Advanced sampler is missing " .. command .. " command")
    end
  end
  if not engine_source:find("samplerLoops", 1, true) or
      not engine_source:find("Phasor.ar", 1, true) then
    fail("Advanced sampler must track tempo-synced loop nodes per deck")
  end
end
if not source:find("sampler_advanced_tick", 1, true) or
    not source:find("sampler_stop_all_loops", 1, true) then
  fail("Advanced sampler sequencing and cleanup are missing")
end
for _, control in ipairs({
  "source_bpm", "loop", "slices", "order",
  "slice_reverse", "repeat_amount", "probability", "target",
}) do
  if not source:find('{"' .. control .. '"', 1, true) then
    fail("Missing advanced sampler control " .. control)
  end
end
for _, behavior in ipairs({
  "bpm / settings.source_bpm",
  "settings.slices > 0",
  "settings.order == 2",
  "settings.order == 3",
  "settings.slice_reverse * 100",
  "settings.repeat_amount * 100",
  "settings.probability * 100",
}) do
  if not source:find(behavior, 1, true) then
    fail("Missing advanced sampler behavior: " .. behavior)
  end
end
do
  local previous_engine = engine
  local received
  engine = {
    nsampler_loop_on = function(...)
      received = {...}
    end
  }
  local internal = dofile("lib/internal_engine.lua")
  internal.sampler_loop_on(2, 4, {
    level=0.8, rate=1.25, pan=-0.2, start=0.1, finish=0.9, cutoff=0.7
  })
  engine = previous_engine
  if not received or received[1] ~= 2 or received[2] ~= 4 or
      received[4] ~= 1.25 or received[8] ~= 0.7 then
    fail("Advanced sampler loop wrapper must forward deck, pad, and controls")
  end
end
pass("Tempo-synced loops, 8/16 slicing, rearrangement, reverse, repeat, and probability exist")

do
  if source:find("sampler_repeat_clocks", 1, true) then
    fail("Sampler repeats must not leave Lua clock coroutines behind")
  end
  if not source:find("internal_engine.sampler_repeat", 1, true) or
      not engine_source:find(
        'addCommand(\\nsampler_repeat, "iiffffffif"', 1, true
      ) or
      not engine_source:find("repeatDelay", 1, true) or
      not engine_source:find("DelayN.ar", 1, true) then
    fail("Sampler stutters must be scheduled inside the audio engine")
  end
end
do
  local previous_engine = engine
  local received
  engine = {
    nsampler_repeat = function(...)
      received = {...}
    end
  }
  local internal = dofile("lib/internal_engine.lua")
  internal.sampler_repeat(2, 3, 100, {
    level=0.8, rate=1.2, pan=0.1, start=0.2, finish=0.4,
    cutoff=0.7, choke=2,
  }, 0.09)
  engine = previous_engine
  if not received or received[1] ~= 2 or received[2] ~= 3 or
      received[9] ~= 2 or received[10] ~= 0.09 then
    fail("Sampler repeat wrapper must forward playback and repeat delay")
  end
end
pass("Sampler repeats use engine-side delay without Lua clock cleanup races")

do
  if not engine_source:find("SynthDef(\\endlessSamplerGrain", 1, true) or
      not engine_source:find("GrainBuf.ar", 1, true) then
    fail("Granular sampler must use a dedicated GrainBuf SynthDef")
  end
  for command, format in pairs({
    nsampler_grain_on="iiffffffffi", nsampler_grain_off="i"
  }) do
    if not engine_source:find(
        "addCommand(\\" .. command .. ', "' .. format .. '"', 1, true
      ) then
      fail("Granular sampler is missing " .. command .. " command")
    end
  end
  if not engine_source:find("maxGrains: 24", 1, true) or
      not engine_source:find("samplerGrains = Array.fill(2", 1, true) then
    fail("Granular sampler must enforce one CPU-bounded voice per deck")
  end
end
for _, control in ipairs({
  "granular", "grain_position", "grain_size", "grain_density",
  "grain_rate", "grain_spread", "grain_freeze",
}) do
  if not source:find('{"' .. control .. '"', 1, true) then
    fail("Missing granular sampler control " .. control)
  end
end
if not source:find("granular_patch_for_genre", 1, true) or
    not source:find("ngrain = granular_patch_for_genre", 1, true) then
  fail("Each generated deck must receive a stable genre-shaped granular patch")
end
if not source:find("sampler_grain_settings", 1, true) or
    not source:find("internal_engine.sampler_grain_on", 1, true) or
    not source:find("internal_engine.sampler_grain_off", 1, true) then
  fail("Granular playback and cleanup must flow through the engine wrapper")
end
do
  local previous_engine = engine
  local received
  engine = {
    nsampler_grain_on = function(...)
      received = {...}
    end
  }
  local internal = dofile("lib/internal_engine.lua")
  internal.sampler_grain_on(2, 5, {
    level=0.7, position=0.25, size=0.08, density=18, rate=1.5,
    pan=-0.1, spread=0.8, cutoff=0.6, freeze=true,
  })
  engine = previous_engine
  if not received or received[1] ~= 2 or received[2] ~= 5 or
      received[4] ~= 0.25 or received[6] ~= 18 or
      received[10] ~= 0.6 or received[11] ~= 1 then
    fail("Granular wrapper must forward deck, pad, controls, and freeze")
  end
end
pass("CPU-bounded, genre-shaped Deck A/B granular playback and freeze exist")

do
  for _, synthdef in ipairs({
    "endlessResampleRecord", "endlessResamplePlayer", "endlessResampleLoop",
    "endlessResampleGrain",
  }) do
    if not engine_source:find("SynthDef(\\" .. synthdef, 1, true) then
      fail("Live resampling is missing " .. synthdef)
    end
  end
  for command, format in pairs({
    resample_start="iif", resample_record_stop="i",
    resample_analyze="if",
    resample_play="iiiffff", resample_grain_on="iiffffffffi",
    resample_stop="ii",
  }) do
    if not engine_source:find(
        "addCommand(\\" .. command .. ', "' .. format .. '"', 1, true
      ) then
      fail("Live resampling is missing " .. command .. " command or format")
    end
  end
  for _, token in ipairs({
    "resampleBuffers = Array.fill(2", "server.sampleRate * 32",
    "In.ar(inBus, 2)", "Synth.after(sourceNode", "RecordBuf.ar",
    "captureBuses = Array.fill(3", "endlessCaptureTap",
    'addPoll("resample_record_peak_1"', "PeakFollower.kr",
    "PlayBuf.ar(", "\\out, deckBuses[deck].index", "maxGrains: 16",
    "resampleBuffers.do({ arg buffer; buffer.free; })",
  }) do
    if not engine_source:find(token, 1, true) then
      fail("Live resampling is missing safety token " .. token)
    end
  end
  local deck_mixer = engine_source:match(
    "SynthDef%(\\\\endlessDeckMixer,(.-)SynthDef%(\\\\endlessMaster,"
  ) or ""
  local master_mixer = engine_source:match(
    "SynthDef%(\\\\endlessMaster,(.-)SynthDef%(\\\\endless808Kick,"
  ) or ""
  if deck_mixer:find("DetectSilence", 1, true) or
      master_mixer:find("DetectSilence", 1, true) then
    fail("Persistent deck/master mixers must not suspend during resample gaps")
  end
  local harness_source = read_file("lib/norns_harness.lua") or ""
  for _, token in ipairs({
    "run_norns_test_harness", "run_resample_test_harness",
    'version="v1.124"', 'sample_library=sample_library',
  }) do
    if not source:find(token, 1, true) then
      fail("Norns harness integration is missing " .. token)
    end
  end
  for _, token in ipairs({
    '"quick"', '"full"', '"interactive"',
    "REQUIRED_COMMANDS", "factory risers", "role one-shots",
    "ENDLESS_HARNESS_XRUN_COUNT", "cleanup complete",
    "snapshot_params", "restore_params", "force_internal_routes",
    'safe_engine("all_off")', "xpcall(", "restore_audio",
    "clock.cancel",
  }) do
    if not harness_source:find(token, 1, true) then
      fail("Physical Norns harness is missing " .. token)
    end
  end
  if not harness_source:find("function instance:run(mode)", 1, true)
      or not harness_source:find("function instance:stop()", 1, true)
      or not source:find("physical_harness:run(mode or \"quick\")", 1, true) then
    fail("Norns harness methods must preserve colon-call semantics")
  end
  pass("One-command quick/full/interactive physical Norns harness exists")
end
for _, param in ipairs({
  "resample_source", "resample_slot", "resample_bars",
  "resample_destination", "resample_mode", "resample_level",
  "resample_rate", "resample_slice", "resample_record",
  "resample_play", "resample_stop",
}) do
  if not source:find('"' .. param .. '"', 1, true) then
    fail("Live resampling is missing parameter " .. param)
  end
end
for _, token in ipairs({
  "resample_service()", "resample_state.pending",
  "request.bars * 16", "clip.duration / 32",
  "if not playing then",
}) do
  if not source:find(token, 1, true) then
    fail("Quantized resampling is missing " .. token)
  end
end
do
  local previous_engine = engine
  local start_received, play_received, grain_received, stop_received
  engine = {
    resample_start = function(...) start_received = {...} end,
    resample_play = function(...) play_received = {...} end,
    resample_grain_on = function(...) grain_received = {...} end,
    resample_stop = function(...) stop_received = {...} end,
  }
  local internal = dofile("lib/internal_engine.lua")
  internal.resample_start(3, 2, 40)
  internal.resample_play(2, 1, 2, {
    level=0.7, rate=1.25, start=0.1, finish=0.8,
  })
  internal.resample_grain_on(1, 2, {
    level=0.6, position=0.3, size=0.08, density=10,
    rate=0.75, spread=0.7, cutoff=0.8, finish=0.5, freeze=true,
  })
  internal.resample_stop(2, 1)
  engine = previous_engine
  if not start_received or start_received[1] ~= 3 or
      start_received[2] ~= 2 or start_received[3] ~= 32 then
    fail("Resample recording wrapper must cap captures at 32 seconds")
  end
  if not play_received or play_received[1] ~= 2 or
      play_received[3] ~= 2 or play_received[7] ~= 0.8 then
    fail("Resample player wrapper must forward deck, slot, mode, and range")
  end
  if not grain_received or grain_received[4] ~= 0.3 or
      grain_received[10] ~= 0.5 or grain_received[11] ~= 1 then
    fail("Resample granular wrapper must forward bounded texture controls")
  end
  if not stop_received or stop_received[1] ~= 2 or stop_received[2] ~= 1 then
    fail("Resample stop wrapper must address one slot on one deck")
  end
end
pass("Quantized dual-slot post-FX live resampling and replay exist")

for _, part in ipairs({"drums", "bass", "chords", "mono", "samples"}) do
  if not source:find('{"' .. part .. '", "' .. part .. ' output"}', 1, true) then
    fail("Missing manual output route for " .. part)
  end
end
if not source:find("output_router", 1, true) then
  fail("Missing output router integration")
end
if not source:find("internal_engine.set_deck_levels", 1, true) then
  fail("Internal Deck A/B bus levels must follow the crossfader")
end
do
  local router = dofile("lib/output_router.lua")
  for _, part in ipairs({"drums", "bass", "chords", "mono", "samples"}) do
    if router.get(part) ~= router.EXTERNAL then
      fail(part .. " output must default to external to preserve MIDI behaviour")
    end
    router.set(part, router.BOTH)
    if not router.sends_external(part) or not router.sends_internal(part) then
      fail(part .. " BOTH route must reach external and internal outputs")
    end
  end
end
pass("Manual per-part routes and internal deck crossfade exist")

if not source:find("acapella_files", 1, true) then
  fail("Missing acapella_files variable")
end
if not source:find("parse_acapella_filename", 1, true) then
  fail("Missing parse_acapella_filename function for BPM/key parsing")
end
if not source:find("softcut", 1, true) then
  fail("Missing softcut usage for acapella playback")
end
if not source:find("scan_acapellas", 1, true) then
  fail("Missing scan_acapellas function")
end
pass("Acapella playback support exists")

-- ── Unified grid interface checks ─────────────────────────────────────────
if not source:find("grid.connect", 1, true) then
  fail("Script must use grid.connect() for the single logical grid connection")
end
if source:find("LP_PROGRAMMER_SYSEX", 1, true) then
  fail("Regression: LP_PROGRAMMER_SYSEX must be removed (no Launchpad SysEx in script)")
end
if source:find("midigrid_lib", 1, true) then
  fail("Regression: midigrid_lib must be removed (use grid.connect() instead)")
end
if not source:find("grid_redraw", 1, true) then
  fail("Missing grid_redraw function for unified grid display")
end
if not source:find("nts1_steps", 1, true) then
  fail("Missing nts1_steps for NTS-1 trigger pattern")
end
if not source:find("j6_steps", 1, true) then
  fail("Missing j6_steps for J-6 chord trigger pattern")
end
if not source:find("grid_connect", 1, true) then
  fail("Missing grid_connect function")
end
pass("Unified grid interface (grid.connect, grid_redraw, nts1_steps, j6_steps)")

for _, token in ipairs({
  'g.vgrid and g or rawget(_G, "midigrid")',
  'device.force_full_refresh = true',
  'grid palette unavailable or invalid',
  'has no RGB LUT',
  'grid palette applied to',
  'midigrid is active but no grid devices are attached',
  'midigrid found but its virtual-grid devices are unavailable',
}) do
  if not source:find(token, 1, true) then
    fail("Missing grid palette diagnostic: " .. token)
  end
end
local grid_diagnostics = read_file("tools/grid_diagnostics.lua") or ""
for _, token in ipairs({
  "Endless DJ grid diagnostics", "levels 0-15", "rgb_lut",
  "SysEx RGB driver", "force_full_refresh", "g:refresh()",
}) do
  if not grid_diagnostics:find(token, 1, true) then
    fail("Missing Maiden grid diagnostic behavior: " .. token)
  end
end
pass("Launchpad palette diagnostics and immediate refresh exist")

-- ── Korg NTS-1 checks ─────────────────────────────────────────────────────
if not source:find("nts1_midi_out", 1, true) then
  fail("Missing nts1_midi_out MIDI output for NTS-1")
end
if not source:find("nts1_midi_device", 1, true) then
  fail("Missing nts1_midi_device parameter")
end
if not source:find("play_nts1", 1, true) then
  fail("Missing play_nts1 function")
end
if not source:find("make_nts1_motif", 1, true) then
  fail("Missing make_nts1_motif function")
end
if not source:find("variation_seed", 1, true) then
  fail("Missing variation_seed in deck identity")
end
if not source:find("nts1_variation", 1, true) then
  fail("Missing nts1_variation parameter")
end
if not source:find("nts1_motif_density", 1, true) then
  fail("Missing nts1_motif_density parameter")
end
if not source:find("nts1_register", 1, true) then
  fail("Missing nts1_register parameter")
end
if not source:find("local nts1_register = %-8") then
  fail("Expected NTS-1 default register to be -8 (-24 semitones)")
end
if not source:find('params:add_number%("nts1_register", "nts1 register", %-8, 6, nts1_register%)') then
  fail("Expected NTS-1 register param minimum/default to allow -8")
end
if not source:find("nts1_cc_automation", 1, true) then
  fail("Missing nts1_cc_automation parameter")
end
if not source:find("nts1_midi_out:cc", 1, true) and not source:find("nts1_send_cc", 1, true) then
  fail("Missing NTS-1 CC automation output")
end
-- NTS-1 must not use program_change
do
  local _, pn_start = source:find("local function play_nts1", 1, true)
  if pn_start then
    local pn_end = source:find("\nlocal ", pn_start)
    local pn_body = source:sub(pn_start, pn_end)
    local pn_no_comments = pn_body:gsub("%-%-[^\n]*", "")
    if pn_no_comments:find("program_change") then
      fail("NTS-1 must not use program_change (original NTS-1 does not support it)")
    end
  end
end
pass("NTS-1 support exists (nts1_midi_device, play_nts1, make_nts1_motif)")

-- ── NTS-1 AR loop sync checks ──────────────────────────────────────────────
-- AR loop must only be used when the NTS-1 has received enough MIDI clock
-- to be in sync; the guard state and clock-sending machinery must exist.
if not source:find("nts1_synced", 1, true) then
  fail("Missing nts1_synced flag for AR loop sync guard")
end
if not source:find("nts1_clock_ticks", 1, true) then
  fail("Missing nts1_clock_ticks counter for MIDI clock tracking")
end
if not source:find("nts1_midi_out:clock()", 1, true) then
  fail("NTS-1 must send MIDI clock pulses so the device can sync its AR loop rate")
end
if not source:find("nts1_midi_out:start()", 1, true) then
  fail("NTS-1 must send MIDI Start when playback begins")
end
if not source:find("nts1_midi_out:stop()", 1, true) then
  fail("NTS-1 must send MIDI Stop when playback ends so the AR loop halts cleanly")
end
if not source:find("EG_TYPE", 1, true) then
  fail("Missing EG_TYPE in NTS1_CC for envelope type control (AR loop gating)")
end
if not source:find("EG_AR_LOOP", 1, true) then
  fail("Missing EG_AR_LOOP value in NTS1_CC")
end
-- Verify AR loop is guarded by nts1_synced in nts1_apply_scene
do
  local _, as_start = source:find("local function nts1_apply_scene", 1, true)
  if as_start then
    local as_end = source:find("\nlocal ", as_start)
    local as_body = source:sub(as_start, as_end)
    local as_no_comments = as_body:gsub("%-%-[^\n]*", "")
    if not as_no_comments:find("nts1_synced") then
      fail("nts1_apply_scene must gate AR loop on nts1_synced")
    end
    if not as_no_comments:find("EG_AR_LOOP") then
      fail("nts1_apply_scene must reference EG_AR_LOOP")
    end
  end
end
pass("NTS-1 AR loop is guarded by sync state (nts1_synced, MIDI clock/start/stop)")

-- ── Akai MPX8 checks ──────────────────────────────────────────────────────
if not source:find("mpx8_midi_out", 1, true) then
  fail("Missing mpx8_midi_out MIDI output for MPX8")
end
if not source:find("mpx8_midi_device", 1, true) then
  fail("Missing mpx8_midi_device parameter")
end
if not source:match("local%s+mpx8_ch%s*=%s*10") then
  fail("MPX8 channel default must be 10")
end
if not source:find("play_mpx8", 1, true) then
  fail("Missing play_mpx8 function")
end
if not source:find("mpx8_pads", 1, true) then
  fail("Missing mpx8_pads pad note table")
end
if not source:find("local mpx8_pads = {36, 38, 42, 46, 43, 47, 49, 51}", 1, true) then
  fail("MPX8 default pad map must match factory i01 notes")
end
if not source:find("mpx8_riser_fired", 1, true) then
  fail("Missing mpx8_riser_fired one-shot guard")
end
if not source:find("mpx8_impact_fired", 1, true) then
  fail("Missing mpx8_impact_fired one-shot guard")
end
if not source:find('params:add_trigger("mpx8_test_pad" .. i,', 1, true) then
  fail("Missing per-pad MPX8 test triggers")
end
if not source:find('for i = 1, 8 do', 1, true) then
  fail("Missing 8-pad loop for MPX8 tests")
end
pass("MPX8 support exists (mpx8_midi_device, play_mpx8, mpx8_pads, one-shot guards)")

local function serialize_pattern(pattern)
  local parts = {}
  for i, step in ipairs(pattern) do
    parts[i] = table.concat({
      step.degree or 0,
      step.gate and "1" or "0",
      step.accent and "1" or "0",
      step.slide and "1" or "0",
      step.octave or 0,
      step.length or 0
    }, ":")
  end
  return table.concat(parts, "|")
end

local function pattern_stats(pattern)
  local gate_count, accent_count, slide_count, octave_count = 0, 0, 0, 0
  local longest_gate_run, longest_rest_run = 0, 0
  local gate_run, rest_run = 0, 0
  local unique = {}
  for _, step in ipairs(pattern) do
    unique[(step.degree or 0) + ((step.octave or 0) * 12)] = true
    if step.gate then
      gate_count = gate_count + 1
      gate_run = gate_run + 1
      rest_run = 0
      if gate_run > longest_gate_run then longest_gate_run = gate_run end
      if step.accent then accent_count = accent_count + 1 end
      if step.slide then slide_count = slide_count + 1 end
    else
      rest_run = rest_run + 1
      gate_run = 0
      if rest_run > longest_rest_run then longest_rest_run = rest_run end
    end
    if (step.octave or 0) ~= 0 then octave_count = octave_count + 1 end
  end
  local unique_pitch_count = 0
  for _ in pairs(unique) do unique_pitch_count = unique_pitch_count + 1 end
  return {
    gate_count = gate_count,
    accent_count = accent_count,
    slide_count = slide_count,
    octave_count = octave_count,
    longest_gate_run = longest_gate_run,
    longest_rest_run = longest_rest_run,
    unique_pitch_count = unique_pitch_count
  }
end

local function diff_steps(a, b)
  local changed = 0
  for i = 1, math.min(#a, #b) do
    local sa, sb = a[i], b[i]
    if sa.degree ~= sb.degree or sa.gate ~= sb.gate or sa.accent ~= sb.accent or
        sa.slide ~= sb.slide or sa.octave ~= sb.octave or sa.length ~= sb.length then
      changed = changed + 1
    end
  end
  return changed
end

do
  _G._UNIT_TEST = true
  _G.ENDLESS_DJ_TEST_API = nil
  engine = {}
  audio = {}
  include = function() return {} end
  grid = {
    connect = function()
      return {
        led = function() end,
        all = function() end,
        refresh = function() end
      }
    end
  }
  metro = {
    init = function()
      return {time = 0, event = nil, start = function() end, stop = function() end}
    end
  }
  midi = {
    devices = {},
    connect = function()
      return {
        note_on = function() end,
        note_off = function() end,
        cc = function() end,
        program_change = function() end
      }
    end,
    to_msg = function() return nil end
  }
  params = {set = function() end}
  screen = setmetatable({}, {__index = function() return function() end end})
  softcut = setmetatable({}, {__index = function() return function() end end})

  local chunk, err = loadfile(path)
  if not chunk then fail("Could not load " .. path .. " for acid generator tests: " .. tostring(err)) end
  local ok, load_err = pcall(chunk)
  if not ok then fail("Could not execute " .. path .. " for acid generator tests: " .. tostring(load_err)) end
  local api = _G.ENDLESS_DJ_TEST_API
  if type(api) ~= "table" then fail("Missing ENDLESS_DJ_TEST_API test hooks") end

  local function make_pattern(seed, length, variety)
    local deck = {name = "T-001", genre = "ACID", root = 45}
    local settings = api.acid_settings_for_genre("ACID")
    settings.length = length
    settings.pitch_variety = variety or settings.pitch_variety
    return api.acid_build_pattern(deck, seed, settings)
  end

  local p1 = select(1, make_pattern(123456, 16, 0.35))
  local p2 = select(1, make_pattern(123456, 16, 0.35))
  if serialize_pattern(p1) ~= serialize_pattern(p2) then
    fail("Acid generator must be deterministic for a fixed seed and settings")
  end
  pass("Acid generator is deterministic for a fixed seed")

  for _, length in ipairs({16, 24, 32}) do
    local pattern = select(1, make_pattern(54321 + length, length, 0.5))
    if #pattern ~= length then
      fail("Acid pattern length " .. tostring(length) .. " must generate " .. tostring(length) .. " steps")
    end
  end
  pass("Acid generator supports 16/24/32 step patterns")

  do
    local low = select(1, make_pattern(67890, 16, 0.10))
    local high = select(1, make_pattern(67890, 16, 0.90))
    local low_stats = pattern_stats(low)
    local high_stats = pattern_stats(high)
    if low_stats.unique_pitch_count > high_stats.unique_pitch_count then
      fail("Low pitch variety should not produce more unique pitches than high pitch variety")
    end
  end
  pass("Acid pitch variety changes the generated note pool")

  do
    local settings = api.acid_settings_for_genre("ACID")
    local base, scale = api.acid_build_pattern({name = "T-002", genre = "ACID", root = 45}, 13579, settings)
    local deck = {
      name = "T-002",
      genre = "ACID",
      root = 45,
      acid = {
        seed = 13579,
        variation = 0,
        variation_interval = 8,
        length = settings.length,
        scale = scale,
        base_pattern = api.acid_copy_pattern(base),
        pattern = api.acid_copy_pattern(base),
        last_section = "GROOVE",
        last_bar = 0
      }
    }
    api.acid_refresh_phrase(deck, "DROP", 9)
    local changed = diff_steps(base, deck.acid.pattern)
    if changed < 1 or changed > 6 then
      fail("Acid phrase variation should make a limited number of mutations, got " .. tostring(changed))
    end
  end
  pass("Acid phrase variation keeps the base identity and mutates only a few steps")

  do
    local seen = {}
    local duplicates = 0
    for seed = 1, 1000 do
      local pattern = select(1, make_pattern(seed * 7919, 16, 0.45))
      local stats = pattern_stats(pattern)
      if stats.gate_count == 0 or stats.gate_count == #pattern then
        fail("Acid generator produced an empty or fully gated pattern for seed " .. tostring(seed))
      end
      if stats.longest_gate_run > 6 then
        fail("Acid generator produced an overly long gate run for seed " .. tostring(seed))
      end
      if stats.longest_rest_run > 7 then
        fail("Acid generator produced an overly long rest run for seed " .. tostring(seed))
      end
      local signature = serialize_pattern(pattern)
      if seen[signature] then duplicates = duplicates + 1 end
      seen[signature] = true
    end
    if duplicates > 40 then
      fail("Acid generator duplicate rate is too high across 1000 seeds (" .. tostring(duplicates) .. " duplicates)")
    end
  end
  pass("Acid generator statistics avoid empty, fully gated, and overly repetitive patterns")
end

print("All Endless DJ checks passed")
