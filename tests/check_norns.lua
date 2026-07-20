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
    "endless_dj.lua",
    "endlessdj.lua",
    "EndlessDJ.lua",
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

if not source:find('"PolyPerc"', 1, true) then
  fail("PolyPerc engine must be referenced as engine.name")
end
pass("PolyPerc engine selected")

if not source:find("play_norns_instrument", 1, true) then
  fail("Missing play_norns_instrument function")
end
if not source:find("norns_presets", 1, true) then
  fail("Missing norns_presets definitions")
end
if not source:find("note_to_hz", 1, true) then
  fail("Missing note_to_hz helper for PolyPerc frequency conversion")
end
if source:find("engine%.attack", 1, true) then
  fail("Regression: engine.attack does not exist in PolyPerc (Env.perc has no attack command)")
end
pass("Norns instrument (PolyPerc) support exists")

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
