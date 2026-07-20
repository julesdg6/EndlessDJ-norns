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

if not source:find("lp2_midi_device", 1, true) then
  fail("Missing lp2_midi_device parameter for second Launchpad")
end
if not source:find("lp2_redraw", 1, true) then
  fail("Missing lp2_redraw function for LP2 display")
end
if not source:find("lp2_connect", 1, true) then
  fail("Missing lp2_connect function")
end
if not source:find("LP2_COLORS", 1, true) then
  fail("Missing LP2_COLORS palette table")
end
if not source:find("lp2_step_note", 1, true) then
  fail("Missing lp2_step_note helper for LP2 step-grid layout")
end
if not source:find("lp2_sysex_tick", 1, true) then
  fail("Missing LP2 programmer-mode keepalive tick")
end
pass("Second Launchpad (LP2) support exists")

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

print("All Endless DJ checks passed")
