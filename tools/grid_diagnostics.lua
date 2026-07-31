-- EndlessDJ grid diagnostics
-- Run this snippet in Maiden (the Norns web editor) to test grid connectivity,
-- display all 16 brightness levels across the grid, and report midigrid driver
-- and RGB capability for each attached device.
--
-- Usage:
--   1. Open Maiden (http://<norns-ip>/) in a browser.
--   2. Paste this entire file into the Maiden REPL and press Enter.
--   3. Check the Maiden console output and observe your grid.
--
-- Minimum supported midigrid: commit 2024-03 or later (rgb_lut field present
-- in launchpad_gen3 device objects).
-- Required midigrid settings: active on, grid size 128, rotate second device off.

local function diag_print(msg)
  print("[grid_diag] " .. tostring(msg))
end

-- ── 1. Detect midigrid ───────────────────────────────────────────────────────
local mg = nil
local g = grid.connect and grid.connect()

if g and g.vgrid then
  mg = g
  diag_print("midigrid detected via grid.connect().vgrid")
else
  mg = rawget(_G, "midigrid")
  if mg then
    diag_print("midigrid detected via global _G.midigrid")
  else
    diag_print("WARNING: midigrid not found – install the midigrid mod and enable it")
    diag_print("  SYSTEM -> MODS -> install midigrid (https://github.com/jaggednz/midigrid)")
  end
end

-- ── 2. Report attached devices ───────────────────────────────────────────────
if mg and mg.vgrid and mg.vgrid.devices then
  local count = 0
  for i, device in pairs(mg.vgrid.devices) do
    count = count + 1
    local driver = device.name or device.dev or tostring(device)
    if device.rgb_lut then
      diag_print("device " .. tostring(i) .. ": " .. tostring(driver) .. " – RGB supported (rgb_lut present)")
    else
      diag_print("device " .. tostring(i) .. ": " .. tostring(driver) .. " – NO RGB LUT" ..
        " (upgrade midigrid to the SysEx RGB driver)")
    end
  end
  if count == 0 then
    diag_print("WARNING: midigrid vgrid has no devices – check USB connections and MIDI permissions")
  else
    diag_print(tostring(count) .. " device(s) found")
  end
else
  diag_print("No midigrid virtual grid devices to report")
end

-- ── 3. Load and inject the EndlessDJ palette ─────────────────────────────────
local palette_ok, lut = pcall(include, "EndlessDJ/lib/palettes/endless_dj")
if palette_ok and type(lut) == "table" then
  diag_print("EndlessDJ palette loaded (" .. tostring(#lut) .. " entries)")
  if mg and mg.vgrid and mg.vgrid.devices then
    local accepted = 0
    for _, device in pairs(mg.vgrid.devices) do
      if device.rgb_lut then
        device.rgb_lut = lut
        device.force_full_refresh = true
        accepted = accepted + 1
      end
    end
    diag_print("palette injected into " .. tostring(accepted) .. " device(s)")
  end
else
  diag_print("WARNING: could not load EndlessDJ palette – " .. tostring(lut))
end

-- ── 4. Display all 16 levels on the grid ─────────────────────────────────────
-- Levels 0–15 are painted as two rows of 8: levels 0–7 on row 1, 8–15 on row 2.
-- Any remaining rows are turned off so previously lit pads do not distract.
if g then
  g.all(0)
  for level = 0, 15 do
    local x = (level % 8) + 1
    local y = math.floor(level / 8) + 1
    g.led(x, y, level)
  end
  g.refresh()
  diag_print("Grid painted: row 1 = levels 0-7, row 2 = levels 8-15")
  diag_print("With the EndlessDJ palette the colours should be:")
  diag_print("  level 0 = off,  1 = dim grey,  3 = medium grey,  5 = red (kick)")
  diag_print("  level 6 = yellow (snare),  7 = green (open hat),  8 = blue (closed hat)")
  diag_print("  level 9 = cyan (NTS-1),  10 = violet (J-6)")
  diag_print("  level 11 = amber (root),  12 = lime (scale),  13 = dim purple (chroma)")
  diag_print("  level 14 = warm white (pressed),  15 = bright white (hot)")
else
  diag_print("WARNING: no grid connected – cannot paint level test")
end

-- ── 5. SysEx RGB driver check ─────────────────────────────────────────────────
local driver_path = "/home/we/dust/code/midigrid/lib/devices/launchpad_mini_mk3.lua"
local f = io.open(driver_path, "r")
if f then
  local content = f:read("*a")
  f:close()
  if content:find("SysEx RGB driver", 1, true) then
    diag_print("Launchpad Mini MK3 driver: SysEx RGB driver detected (correct)")
  else
    diag_print("WARNING: Launchpad Mini MK3 driver does NOT contain 'SysEx RGB driver' marker")
    diag_print("  This may be an older driver without full RGB support.")
    diag_print("  Update midigrid: cd /home/we/dust/code/midigrid && git pull")
  end
else
  diag_print("Launchpad Mini MK3 driver not found at " .. driver_path)
  diag_print("  (midigrid may not be installed, or driver path has changed)")
end

diag_print("Diagnostics complete.")
