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
  "GARAGE4","TWO_STEP","BREAKS","DUBSTEP"
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
pass("Second Launchpad (LP2) support exists")

print("All Endless DJ checks passed")
