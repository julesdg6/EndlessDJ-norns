-- Endless DJ grid diagnostics. Paste this complete file into Maiden.
-- It reports RGB capability and paints levels 0-15 across the first two rows.

local function report(message)
  print("Endless DJ grid: " .. tostring(message))
end

local g = grid and grid.connect and grid.connect()
local diagnostic_midigrid = g and g.vgrid and g or rawget(_G, "midigrid")
local devices = diagnostic_midigrid and diagnostic_midigrid.vgrid
  and diagnostic_midigrid.vgrid.devices

local palette_ok, palette = pcall(include, "EndlessDJ/lib/palettes/endless_dj")
if not palette_ok or type(palette) ~= "table" or #palette ~= 16 then
  report("palette missing or invalid")
else
  report("palette loaded: 16 entries")
end

local attached = 0
local accepted = 0
for index, device in pairs(devices or {}) do
  attached = attached + 1
  local driver = device.name or device.dev or ("device " .. tostring(index))
  if type(device.rgb_lut) == "table" then
    report(driver .. ": RGB supported")
    if palette_ok and type(palette) == "table" and #palette == 16 then
      device.rgb_lut = palette
      device.force_full_refresh = true
      accepted = accepted + 1
    end
  else
    report(driver .. ": NO RGB LUT; install the SysEx RGB driver")
  end
end
report("palette applied to " .. tostring(accepted) .. "/" ..
  tostring(attached) .. " device(s)")

if g then
  g:all(0)
  for level = 0, 15 do
    g:led((level % 8) + 1, math.floor(level / 8) + 1, level)
  end
  g:refresh()
  report("levels 0-15 displayed on rows 1-2")
else
  report("no grid connection; display test skipped")
end

local driver_path =
  "/home/we/dust/code/midigrid/lib/devices/launchpad_mini_mk3.lua"
local driver_file = io.open(driver_path, "rb")
if driver_file then
  local driver_source = driver_file:read("*a")
  driver_file:close()
  report(driver_source:find("SysEx RGB driver", 1, true)
    and "SysEx RGB driver detected"
    or "SysEx RGB driver marker missing; update midigrid")
else
  report("Launchpad Mini MK3 driver file not found")
end
