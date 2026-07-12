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

if not source:find("current_bar = 9", 1, true) then
  fail("Incoming deck should continue at bar 9 after the 8-bar mix")
end
pass("8-bar mix handover continues at bar 9")

if source:match("local%s+CLAP%s*=%s*39") then
  fail("Regression: T-8 clap must be note 50, not 39")
end
pass("No T-8 clap regression")

print("All Endless DJ checks passed")
