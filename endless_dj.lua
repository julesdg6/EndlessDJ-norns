-- endless_dj.lua
-- Endless DJ v1.0
-- Turntable-style animated decks + Roland AIRA MX-1 integration
--
-- T-8 drum map used here:
--   kick  36
--   snare 38
--   clap  50
--   tom   47
--   chh   42
--   ohh   46
--
-- MIDI (all routed via Roland AIRA MX-1 as USB hub):
--   T-8 drums  ch10 on t8 midi device  (default device 1 via MX-1)
--   T-8 bass   ch8  on t8 midi device
--   J-6 chords ch6  on j6 midi device  (default device 1 via MX-1)
--   MX-1 Beat FX depth automated via CC during mix transitions

engine.name = "PolyPerc"

-- Optional midigrid support for Launchpad connected as HID
-- Install via: https://github.com/jaggednz/midigrid
local midigrid_lib
local _mg_ok, _mg_err = pcall(function() midigrid_lib = include('midigrid/lib/midigrid') end)
if not _mg_ok and _mg_err then
  print("midigrid not loaded (direct MIDI mode): " .. tostring(_mg_err))
end

local midi_out
local chord_midi_out
local mx1_midi_out

local mdev = 1
local chord_mdev = 1
local mx1_mdev = 1

-- ──────────────────────────────────────────────
-- Norns instrument (PolyPerc SuperCollider engine)
-- ──────────────────────────────────────────────
local norns_inst_enabled = true
local norns_inst_vol = 0.8

-- Presets: pad, synth, pluck, strings.
-- Fields: attack/release in seconds, cutoff in Hz, gain = filter resonance (0-1), pw = pulse width (0-1).
local norns_presets = {
  {name="pad",     attack=0.8,  release=2.0, cutoff=800,  gain=0.5, pw=0.5},
  {name="synth",   attack=0.02, release=0.5, cutoff=3000, gain=0.3, pw=0.3},
  {name="pluck",   attack=0.01, release=0.3, cutoff=5000, gain=0.2, pw=0.2},
  {name="strings", attack=0.4,  release=1.5, cutoff=1500, gain=0.4, pw=0.5},
}
local norns_preset_idx = 1

-- ──────────────────────────────────────────────
-- Acapella playback via softcut
-- ──────────────────────────────────────────────
local acapella_enabled = false
local acapella_vol = 0.7
local acapella_files = {}   -- list of {path, filename, bpm, semitone, key}
local acapella_index = 1
local acapella_loaded = false
local ACAPELLA_VOICE  = 1
local ACAPELLA_BUFFER = 1
local mx1_ch = 1
local mx1_fx_enabled = true
local mx1_fx_cc = 12

local playing = false
local bpm = 128
local ppqn = 4
local tick = 0
local phrase_bars = 128
local step = 1

local current_bar = 1
local next_bar = nil
local next_step = 1
local mixing = false

local xfade = 0
local manual_xfade = false
local generation = 2

local drum_ch = 10
local bass_ch = 8
local chord_ch = 6

local j6_pc_ch = 16
local j6_pc_enabled = true
local j6_pc_min = 0
local j6_pc_max = 63

local genres = {
  "HOUSE",
  "FUNKY",
  "DIRTY",
  "TECHNO",
  "GARAGE4",
  "TWO_STEP",
  "BREAKS",
  "DUBSTEP"
}

local roots = {45,47,48,50,52,53,55}

local deck_a = {name="A-001", genre="HOUSE",     active=true,  angle=0, root=45, pc=0, norns_preset=1}
local deck_b = {name="B-002", genre="TWO_STEP", active=false, angle=0, root=50, pc=1, norns_preset=2}

local notes_off = {}
local notes_pending = {}

local KICK = 36
local SNARE = 38
local CLAP = 50
local TOM = 47
local CHH = 42
local OHH = 46

-- ──────────────────────────────────────────────
-- Launchpad Mini MK3 drum step sequencer
-- ──────────────────────────────────────────────
local lp = nil
local lp_dev = 3
local lp_use_mg = false

-- 4 lanes x 16 steps: 1=kick  2=snare  3=open hat  4=closed hat
local drum_steps = {}
for i = 1, 4 do
  drum_steps[i] = {}
  for j = 1, 16 do drum_steps[i][j] = false end
end

-- Novation colour palette velocities per lane: {active, playhead cursor}
local LP_COLORS = {
  {5,  7},   -- kick:       red
  {13, 14},  -- snare:      yellow
  {21, 23},  -- open hat:   green
  {45, 46},  -- closed hat: blue
}

-- Map Novation palette velocities → midigrid brightness levels
local LP_VEL_TO_MG = {
  [5]=3,  [7]=5,    -- kick
  [13]=8, [14]=10,  -- snare
  [21]=12,[23]=14,  -- open hat
  [45]=6, [46]=9,   -- closed hat
}

-- SysEx to switch Launchpad Mini MK3 into programmer mode
local LP_PROGRAMMER_SYSEX = {0xF0,0x00,0x20,0x29,0x02,0x0D,0x0E,0x01,0xF7}

local MIDI_START = 0xFA
local MIDI_CONTINUE = 0xFB
local MIDI_STOP = 0xFC

local sections = {
  {name="INTRO", first=1, last=16},
  {name="GROOVE", first=17, last=32},
  {name="MAIN", first=33, last=64},
  {name="BREAK", first=65, last=80},
  {name="BUILD", first=81, last=96},
  {name="DROP", first=97, last=120},
  {name="MIX", first=121, last=128},
}

local function clamp(x,a,b)
  return math.max(a, math.min(b,x))
end

local function hit(list, s)
  if not list then return false end
  for _,v in ipairs(list) do
    if v == s then return true end
  end
  return false
end

-- Send a MIDI CC to the Roland AIRA MX-1 (e.g. Beat FX depth).
local function send_mx1_cc(cc_num, val)
  if not mx1_midi_out then return end
  if not mx1_fx_enabled then return end
  mx1_midi_out:cc(cc_num, clamp(math.floor(val), 0, 127), mx1_ch)
end

-- Automate MX-1 Beat FX depth during mix transitions.
-- The effect ramps up from zero to peak at mid-mix then back to zero,
-- adding a natural DJ-style wash over the crossfade window.
local function update_mx1_fx()
  if not mx1_fx_enabled then return end
  if mixing then
    local pos = ((current_bar - 121) * 16 + (step - 1)) / (8 * 16)
    local depth = math.sin(clamp(pos, 0, 1) * math.pi) * 100
    send_mx1_cc(mx1_fx_cc, depth)
  else
    send_mx1_cc(mx1_fx_cc, 0)
  end
end

local function section_for_bar(b)
  for _,s in ipairs(sections) do
    if b >= s.first and b <= s.last then
      return s.name
    end
  end
  return "PLAY"
end

local function random_pc()
  return math.random(j6_pc_min, j6_pc_max)
end

local function j6_program_change(num)
  if not chord_midi_out then return end
  if not j6_pc_enabled then return end
  chord_midi_out:program_change(num, j6_pc_ch)
end

local function make_deck(letter)
  generation = generation + 1
  return {
    name = letter .. "-" .. string.format("%03d", generation),
    genre = genres[math.random(#genres)],
    active = false,
    angle = math.random() * math.pi * 2,
    root = roots[math.random(#roots)],
    pc = random_pc(),
    norns_preset = math.random(#norns_presets)
  }
end

local function current_deck()
  return deck_a.active and deck_a or deck_b
end

local function next_deck()
  return deck_a.active and deck_b or deck_a
end

local function quiet_notes()
  if midi_out then
    for ch=1,16 do
      for n=0,127 do
        midi_out:note_off(n, 0, ch)
      end
    end
  end

  if chord_midi_out then
    for ch=1,16 do
      for n=0,127 do
        chord_midi_out:note_off(n, 0, ch)
      end
    end
  end

  -- Reset MX-1 Beat FX depth so no effect lingers after stopping.
  send_mx1_cc(mx1_fx_cc, 0)

  notes_off = {}
  notes_pending = {}
end

local function apply_transport_message(msg_type)
  if msg_type == "start" or msg_type == "continue" then
    playing = true
    redraw()
    return true
  elseif msg_type == "stop" then
    playing = false
    quiet_notes()
    redraw()
    return true
  end
  return false
end

local function handle_mx1_transport(data)
  local msg = nil
  -- Prefer decoded messages when midi.to_msg is available, otherwise
  -- fall back to raw realtime status bytes below.
  if midi and midi.to_msg and data then
    msg = midi.to_msg(data)
  end

  local transport_type = msg and msg.type or nil

  -- Prefer decoded transport message types when available.
  -- Some devices/firmware revisions may only expose raw realtime status bytes.
  if not transport_type then
    local status = nil
    if type(data) == "table" then
      status = data[1]
    end
    if status == MIDI_START then
      transport_type = "start"
    elseif status == MIDI_CONTINUE then
      transport_type = "continue"
    elseif status == MIDI_STOP then
      transport_type = "stop"
    end
  end

  if transport_type then
    apply_transport_message(transport_type)
  end
end

local function connect_mx1_midi()
  mx1_midi_out = midi.connect(mx1_mdev)
  if mx1_midi_out then
    mx1_midi_out.event = handle_mx1_transport
  else
    print("Endless DJ: failed to connect mx1 midi device " .. tostring(mx1_mdev)
      .. " (check mx1_midi_device parameter and USB connection)")
  end
end

local function note_on_to(dev, note, vel, ch, len_ticks)
  if not dev then return end
  dev:note_on(note, vel, ch)
  table.insert(notes_off, {
    t = tick + (len_ticks or 1),
    n = note,
    ch = ch,
    dev = dev
  })
end

local function note_delayed(dev, note, vel, ch, delay_ticks, len_ticks)
  table.insert(notes_pending, {
    t = tick + delay_ticks,
    n = note,
    v = vel,
    ch = ch,
    len = len_ticks,
    dev = dev
  })
end

local function t8_note(note, vel, ch, len_ticks)
  note_on_to(midi_out, note, vel, ch, len_ticks)
end

local function chord_note(note, vel, len_ticks)
  note_on_to(chord_midi_out, note, vel, chord_ch, len_ticks)
end

local function chord_note_delayed(note, vel, delay_ticks, len_ticks)
  note_delayed(chord_midi_out, note, vel, chord_ch, delay_ticks, len_ticks)
end

local function service_note_offs()
  for i=#notes_off,1,-1 do
    local e = notes_off[i]
    if tick >= e.t then
      if e.dev then
        e.dev:note_off(e.n, 0, e.ch)
      end
      table.remove(notes_off, i)
    end
  end
end

local function service_pending_notes()
  for i=#notes_pending,1,-1 do
    local e = notes_pending[i]
    if tick >= e.t then
      note_on_to(e.dev, e.n, e.v, e.ch, e.len)
      table.remove(notes_pending, i)
    end
  end
end

local function density_for_section(sec)
  if sec == "INTRO" then return 0.40 end
  if sec == "GROOVE" then return 0.60 end
  if sec == "MAIN" then return 0.78 end
  if sec == "BREAK" then return 0.45 end
  if sec == "BUILD" then return 0.75 end
  if sec == "DROP" then return 0.95 end
  if sec == "MIX" then return 0.70 end
  return 0.70
end

-- ──────────────────────────────────────────────
-- Norns instrument helpers
-- ──────────────────────────────────────────────

local function note_to_hz(note)
  return 440 * 2 ^ ((note - 69) / 12)
end

-- ──────────────────────────────────────────────
-- Acapella helpers
-- ──────────────────────────────────────────────

-- Map key-string pitch class → semitone 0-11.
local KEY_SEMITONE = {
  C=0,  ["C#"]=1, Cs=1, Db=1,
  D=2,  ["D#"]=3, Ds=3, Eb=3,
  E=4,
  F=5,  ["F#"]=6, Fs=6, Gb=6,
  G=7,  ["G#"]=8, Gs=8, Ab=8,
  A=9,  ["A#"]=10, As=10, Bb=10,
  B=11
}

-- Parse acapella filename. Expected format: {bpm}_{key}_{description}.{ext}
-- e.g. 128_Am_House_Vocal.mp3  →  bpm=128, semitone=9 (A), key="Am"
-- Returns bpm (number), semitone (0-11 or nil), key_str on success; nil on failure.
local function parse_acapella_filename(filename)
  local bpm_str, key_str = filename:match("^(%d+)_([A-Ga-g][b#]?[mM]?)_")
  if not bpm_str then return nil end
  local bpm_val = tonumber(bpm_str)
  if not bpm_val or bpm_val < 40 or bpm_val > 250 then return nil end
  -- Strip trailing 'm'/'M' to get pitch class then normalise capitalisation.
  local key_base = key_str:gsub("[mM]$", "")
  key_base = key_base:sub(1, 1):upper() .. key_base:sub(2)
  local semitone = KEY_SEMITONE[key_base]
  return bpm_val, semitone, key_str
end

-- Scan ~/dust/audio/endlessdj/ for audio files with BPM/key in the filename.
local function scan_acapellas()
  acapella_files = {}
  if not (_path and _path.audio) then return end
  local dir = _path.audio .. "endlessdj/"
  local exts = {"mp3", "wav", "flac", "aif", "aiff"}
  for _, ext in ipairs(exts) do
    local cmd = 'find "' .. dir .. '" -maxdepth 1 -iname "*.' .. ext .. '" 2>/dev/null'
    local ok, p = pcall(io.popen, cmd)
    if ok and p then
      for line in p:lines() do
        line = line:match("^%s*(.-)%s*$") or ""
        if line ~= "" then
          local fname = line:match("([^/\\]+)$") or ""
          local bpm_val, semitone, key_str = parse_acapella_filename(fname)
          if bpm_val then
            table.insert(acapella_files, {
              path     = line,
              filename = fname,
              bpm      = bpm_val,
              semitone = semitone,
              key      = key_str,
            })
          end
        end
      end
      p:close()
    end
  end
  table.sort(acapella_files, function(a, b) return a.filename < b.filename end)
end

local function setup_softcut()
  audio.level_cut(1.0)
  softcut.reset()
  softcut.buffer(ACAPELLA_VOICE, ACAPELLA_BUFFER)
  softcut.loop(ACAPELLA_VOICE, 0)
  softcut.loop_start(ACAPELLA_VOICE, 0)
  softcut.loop_end(ACAPELLA_VOICE, 300)
  softcut.position(ACAPELLA_VOICE, 0)
  softcut.rate(ACAPELLA_VOICE, 1.0)
  softcut.level(ACAPELLA_VOICE, acapella_vol)
  softcut.fade_time(ACAPELLA_VOICE, 0.01)
  softcut.enable(ACAPELLA_VOICE, 1)
  softcut.play(ACAPELLA_VOICE, 0)
end

local function load_acapella(idx)
  if #acapella_files == 0 then return end
  acapella_index = ((idx - 1) % #acapella_files) + 1
  local ac = acapella_files[acapella_index]
  softcut.play(ACAPELLA_VOICE, 0)
  softcut.buffer_clear()
  softcut.buffer_read_mono(ac.path, 0, 0, -1, 1, ACAPELLA_BUFFER)
  softcut.position(ACAPELLA_VOICE, 0)
  acapella_loaded = true
end

local function start_acapella()
  if not acapella_enabled then return end
  if not acapella_loaded then return end
  if #acapella_files == 0 then return end
  local ac = acapella_files[acapella_index]
  local rate = bpm / ac.bpm
  softcut.rate(ACAPELLA_VOICE, rate)
  softcut.level(ACAPELLA_VOICE, acapella_vol)
  softcut.position(ACAPELLA_VOICE, 0)
  softcut.play(ACAPELLA_VOICE, 1)
end

local function stop_acapella()
  softcut.play(ACAPELLA_VOICE, 0)
end

local drum_patterns = {
  HOUSE = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={3,7,11,15}
  },
  FUNKY = {
    kick={1,5,9,11,13},
    snare={5,13},
    clap={5,13},
    hats={3,4,7,10,11,15}
  },
  DIRTY = {
    kick={1,5,9,13,16},
    snare={5,13},
    clap={5,13},
    hats={3,7,8,11,15}
  },
  TECHNO = {
    kick={1,5,9,13},
    snare={},
    clap={},
    tom={4,8,12,16},
    hats={3,7,11,15}
  },
  GARAGE4 = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={3,4,7,10,12,15}
  },
  TWO_STEP = {
    kick={1,7,11},
    snare={5,13},
    clap={5,13},
    hats={3,4,7,10,12,15}
  },
  BREAKS = {
    kick={1,4,11,15},
    snare={5,13},
    clap={},
    hats={3,6,8,11,14,16}
  },
  DUBSTEP = {
    kick={1,11},
    snare={9},
    clap={9},
    hats={3,7,11,15}
  }
}

-- ──────────────────────────────────────────────
-- Launchpad helper functions
-- ──────────────────────────────────────────────

-- Encode (lane, step) → programmer-mode MIDI note.
-- Physical layout (top row of launchpad = row 8):
--   lane 1 kick      rows 8/7  (steps 1-8 / 9-16)
--   lane 2 snare     rows 6/5
--   lane 3 open hat  rows 4/3
--   lane 4 closed hat rows 2/1
local function lp_note(lane, s)
  local base_row = 8 - (lane - 1) * 2
  local row = (s <= 8) and base_row or (base_row - 1)
  local col = (s <= 8) and s or (s - 8)
  return row * 10 + col
end

-- Decode a programmer-mode MIDI note → (lane, step); nil,nil if outside grid
local function lp_decode(note)
  local row = math.floor(note / 10)
  local col = note % 10
  if row < 1 or row > 8 or col < 1 or col > 8 then return nil, nil end
  for lane = 1, 4 do
    local base_row = 8 - (lane - 1) * 2
    if row == base_row     then return lane, col     end
    if row == base_row - 1 then return lane, col + 8 end
  end
  return nil, nil
end

local function lp_led(note, vel)
  if not lp then return end
  if lp_use_mg then
    local row = math.floor(note / 10)
    local col = note % 10
    local x, y = col, 9 - row
    local z = (vel == 0) and 0 or (LP_VEL_TO_MG[vel] or 1)
    lp:led(x, y, z)
  else
    lp:note_on(note, vel, 1)
  end
end

local function lp_refresh()
  if lp_use_mg and lp then lp:refresh() end
end

-- Redraw the entire grid; s = the step currently being played (1-16)
local function lp_redraw(s)
  if not lp then return end
  for lane = 1, 4 do
    local c = LP_COLORS[lane]
    for i = 1, 16 do
      local n   = lp_note(lane, i)
      local vel
      if i == s then
        vel = c[2]
      elseif drum_steps[lane][i] then
        vel = c[1]
      else
        vel = 0
      end
      lp_led(n, vel)
    end
  end
  lp_refresh()
end

-- Populate drum_steps from a genre's base drum pattern
local function lp_load_pattern(genre)
  local p = drum_patterns[genre] or drum_patterns.HOUSE
  for i = 1, 16 do
    drum_steps[1][i] = hit(p.kick  or {}, i)
    drum_steps[2][i] = hit(p.snare or {}, i)
    drum_steps[3][i] = false                   -- open hat has no base pattern entry; start empty for manual programming
    drum_steps[4][i] = hit(p.hats  or {}, i)
  end
end

-- Turn off all launchpad LEDs
local function lp_clear()
  if not lp then return end
  if lp_use_mg then
    lp:all(0)
    lp:refresh()
  else
    for row = 1, 8 do
      for col = 1, 8 do
        lp:note_on(row * 10 + col, 0, 1)
      end
    end
  end
end

-- Connect to the launchpad; tries midigrid first (for HID-connected devices),
-- then falls back to direct MIDI programmer mode.
local function lp_connect(dev)
  lp_use_mg = false

  if midigrid_lib then
    local mg = midigrid_lib.connect()
    if mg then
      lp = mg
      lp_use_mg = true
      lp_load_pattern(current_deck().genre)
      lp_redraw(step)
      mg.key = function(x, y, z)
        if z > 0 then
          -- Convert midigrid (x,y) to programmer-mode note: row = 9-y, col = x
          local note = (9 - y) * 10 + x
          local lane, s = lp_decode(note)
          if lane then
            drum_steps[lane][s] = not drum_steps[lane][s]
            local brightness = drum_steps[lane][s]
              and (LP_VEL_TO_MG[LP_COLORS[lane][1]] or 1) or 0
            lp:led(x, y, brightness)
            lp:refresh()
          end
        end
      end
      return
    end
  end

  -- Fall back to direct MIDI (programmer mode SysEx + note_on LEDs)
  lp = midi.connect(dev)
  local ok = pcall(function() lp:send(LP_PROGRAMMER_SYSEX) end)
  if not ok then
    print("launchpad: programmer mode SysEx failed on device " .. dev)
  end
  lp_load_pattern(current_deck().genre)
  lp_redraw(step)

  lp.event = function(data)
    local msg = midi.to_msg(data)
    if msg and msg.type == "note_on" and msg.vel > 0 then
      local lane, s = lp_decode(msg.note)
      if lane then
        drum_steps[lane][s] = not drum_steps[lane][s]
        lp_led(lp_note(lane, s),
          drum_steps[lane][s] and LP_COLORS[lane][1] or 0)
      end
    end
  end
end

local bass_patterns = {
  HOUSE={0,0,7,0, 0,10,7,0, 0,0,12,10, 7,0,3,0},
  FUNKY={0,7,0,10, 12,10,7,0, 5,0,7,10, 12,0,10,7},
  DIRTY={0,0,0,3, 0,0,7,10, 0,0,12,10, 7,3,0,0},
  TECHNO={0,0,0,0, 7,0,0,0, 0,0,10,0, 7,0,3,0},
  GARAGE4={0,0,7,0, 10,0,7,0, 0,12,0,10, 7,0,3,0},
  TWO_STEP={0,0,0,7, 0,10,0,0, 12,0,0,10, 0,7,3,0},
  BREAKS={0,0,7,0, 0,0,10,0, 12,0,7,0, 3,0,0,10},
  DUBSTEP={0,0,0,0, -12,0,0,0, 0,0,0,-5, -12,0,0,0}
}

local chord_progs = {
  HOUSE={{0,3,7},{5,8,12},{7,10,14},{3,7,10}},
  FUNKY={{0,4,7},{5,9,12},{7,11,14},{10,14,17}},
  DIRTY={{0,3,7},{3,7,10},{5,8,12},{7,10,14}},
  TECHNO={{0,3,7},{0,3,7},{-2,1,5},{0,3,7}},
  GARAGE4={{0,3,7},{5,8,12},{10,14,17},{7,10,14}},
  TWO_STEP={{0,3,7},{10,14,17},{5,8,12},{7,10,14}},
  BREAKS={{0,3,7},{7,10,14},{5,8,12},{3,7,10}},
  DUBSTEP={{0,3,7},{0,3,7},{-5,-2,2},{-7,-4,0}}
}

local chord_styles = {
  HOUSE={"block","stab","offbeat"},
  FUNKY={"stab","up","offbeat"},
  DIRTY={"stab","strum","block"},
  TECHNO={"stab"},
  GARAGE4={"offbeat","stab","up"},
  TWO_STEP={"offbeat","updown","stab"},
  BREAKS={"stab","strum"},
  DUBSTEP={"stab","block"}
}

local function choose(t)
  return t[math.random(#t)]
end

local function play_drums(sec, s, b, mix_amount, deck)
  local g = deck.genre
  local p = drum_patterns[g] or drum_patterns.HOUSE
  local d = density_for_section(sec)
  -- Use launchpad patterns only for the currently active deck
  local use_lp = lp ~= nil and (deck == current_deck())

  local kick_prob = 1.0
  if sec == "INTRO" then kick_prob = 0.75 end
  if sec == "BREAK" then kick_prob = 0.45 end
  if mix_amount and mix_amount < 0.45 then kick_prob = 0.20 end

  -- Kick
  local kick_hit
  if use_lp then kick_hit = drum_steps[1][s] else kick_hit = hit(p.kick, s) end
  if kick_hit and math.random() < kick_prob then
    local vel = 110
    if g == "TECHNO" then vel = 122 end
    if g == "DUBSTEP" then vel = 120 end
    t8_note(KICK, vel, drum_ch, 1)
  end

  -- Snare
  local snare_hit
  if use_lp then
    snare_hit = drum_steps[2][s]
  else
    snare_hit = p.snare and hit(p.snare, s)
  end
  if snare_hit and sec ~= "INTRO" then
    local vel = 100
    if g == "DUBSTEP" or g == "BREAKS" then vel = 122 end
    t8_note(SNARE, vel, drum_ch, 1)
  end

  -- Clap (always generative; not on launchpad)
  if p.clap and hit(p.clap, s) and sec ~= "INTRO" then
    if g ~= "TECHNO" then
      t8_note(CLAP, 110, drum_ch, 1)
    end
  end

  -- Tom (always generative)
  if p.tom and hit(p.tom, s) and math.random() < 0.45 then
    t8_note(TOM, 85, drum_ch, 1)
  end

  -- Closed hi-hat
  local chh_hit
  if use_lp then
    chh_hit = drum_steps[4][s]
  else
    chh_hit = p.hats and hit(p.hats, s)
  end
  if chh_hit and math.random() < (0.45 + d * 0.40) then
    local vel = 70
    if g == "TECHNO" then vel = 88 end
    t8_note(CHH, vel, drum_ch, 1)
  end

  -- Open hi-hat
  if use_lp then
    if drum_steps[3][s] then
      t8_note(OHH, 70, drum_ch, 1)
    end
  elseif (s == 7 or s == 15) and sec ~= "INTRO" and math.random() < d * 0.35 then
    t8_note(OHH, 70, drum_ch, 1)
  end

  -- Bar fills (always generative)
  if b % 16 == 0 and s >= 13 then
    if s == 13 then t8_note(SNARE, 95, drum_ch, 1) end
    if s == 14 then t8_note(TOM, 90, drum_ch, 1) end
    if s == 15 then t8_note(SNARE, 105, drum_ch, 1) end
    if s == 16 then t8_note(CLAP, 115, drum_ch, 1) end
  end
end

local function play_bass(sec, s, deck, mix_amount)
  if sec == "INTRO" then return end
  if sec == "BREAK" and math.random() < 0.55 then return end
  if mix_amount and mix_amount < 0.62 then return end

  local pat = bass_patterns[deck.genre] or bass_patterns.HOUSE
  local degree = pat[((s-1)%16)+1]
  if degree == nil then return end

  local prob = 0.55
  if deck.genre == "DUBSTEP" then prob = 0.90 end
  if deck.genre == "TECHNO" then prob = 0.65 end

  if degree ~= 0 or math.random() < prob then
    local octave = 0
    local len = 1
    if deck.genre == "DUBSTEP" then
      octave = -12
      len = 3
    end
    t8_note(deck.root + octave + degree, sec=="DROP" and 112 or 94, bass_ch, len)
  end
end

local function play_chords(sec, s, deck, b, mix_amount)
  if sec == "INTRO" then return end
  if mix_amount and mix_amount < 0.50 then return end

  local g = deck.genre
  local allow = false

  if g=="HOUSE" or g=="FUNKY" or g=="DIRTY" or g=="GARAGE4" then
    allow = (s==1 or s==9)
  elseif g=="TWO_STEP" then
    allow = (s==4 or s==10)
  elseif g=="BREAKS" then
    allow = (s==1 or s==11)
  elseif g=="TECHNO" then
    allow = (s==1 and b%4==1)
  elseif g=="DUBSTEP" then
    allow = (s==1 or s==9)
  end

  if not allow then return end
  if sec == "BREAK" and math.random() < 0.45 then return end

  local prog = chord_progs[g] or chord_progs.HOUSE
  local triad = prog[(math.floor((b-1)/2) % #prog) + 1]
  local base = deck.root + 12
  local notes = {base+triad[1], base+triad[2], base+triad[3]}
  local style = choose(chord_styles[g] or {"block"})
  local vel = sec=="DROP" and 98 or 78

  if style == "block" then
    for _,n in ipairs(notes) do
      chord_note(n, vel, g=="DUBSTEP" and 4 or 10)
    end
  elseif style == "up" then
    for i,n in ipairs(notes) do
      chord_note_delayed(n, vel, i-1, 8)
    end
  elseif style == "updown" then
    chord_note_delayed(notes[1], vel, 0, 5)
    chord_note_delayed(notes[2], vel, 1, 5)
    chord_note_delayed(notes[3], vel, 2, 5)
    chord_note_delayed(notes[2], vel, 3, 5)
  elseif style == "strum" then
    for i,n in ipairs(notes) do
      chord_note_delayed(n, vel, i-1, 12)
    end
  elseif style == "stab" then
    for _,n in ipairs(notes) do
      chord_note(n, vel+12, 3)
    end
  elseif style == "offbeat" then
    for _,n in ipairs(notes) do
      chord_note_delayed(n, vel, 2, 4)
    end
  end
end

local function play_norns_instrument(sec, s, deck, b, mix_amount)
  if not norns_inst_enabled then return end
  if sec == "INTRO" or sec == "BREAK" then return end
  if mix_amount and mix_amount < 0.50 then return end
  if s ~= 1 then return end

  local g = deck.genre
  local preset = norns_presets[deck.norns_preset or norns_preset_idx]
  local is_pad = (preset.name == "pad" or preset.name == "strings")
  if is_pad and b % 2 ~= 1 then return end

  engine.attack(preset.attack)
  engine.release(preset.release)
  engine.cutoff(preset.cutoff)
  engine.gain(preset.gain)
  engine.pw(preset.pw)
  engine.amp(norns_inst_vol)

  local prog = chord_progs[g] or chord_progs.HOUSE
  local triad = prog[(math.floor((b - 1) / 2) % #prog) + 1]
  local base = deck.root + 24  -- two octaves above deck root

  for _, interval in ipairs(triad) do
    engine.hz(note_to_hz(base + interval))
  end
end

local function play_deck(deck, b, s, mix_amount)
  local sec = section_for_bar(b)
  play_drums(sec, s, b, mix_amount, deck)
  play_bass(sec, s, deck, mix_amount)
  play_chords(sec, s, deck, b, mix_amount)
  play_norns_instrument(sec, s, deck, b, mix_amount)
end

local function start_mix_if_needed()
  if current_bar == 121 and step == 1 and not mixing then
    mixing = true
    next_bar = 1
    next_step = 1
    j6_program_change(next_deck().pc)
  end
end

local function update_xfade()
  if manual_xfade then return end

  if mixing then
    local pos = ((current_bar - 121) * 16 + (step - 1)) / (8 * 16)
    if deck_a.active then
      xfade = clamp(pos * 100, 0, 100)
    else
      xfade = clamp(100 - pos * 100, 0, 100)
    end
  else
    xfade = deck_a.active and 0 or 100
  end
end

local function finish_handover()
  if deck_a.active then
    deck_a.active = false
    deck_b.active = true
    deck_a = make_deck("A")
  else
    deck_b.active = false
    deck_a.active = true
    deck_b = make_deck("B")
  end

  current_bar = 9
  step = 1
  next_bar = nil
  next_step = 1
  mixing = false
  quiet_notes()
  lp_load_pattern(current_deck().genre)
  lp_redraw(step)
end

local metro_clock

local function clock_tick()
  if not playing then return end

  service_note_offs()
  service_pending_notes()
  start_mix_if_needed()
  update_xfade()
  update_mx1_fx()
  lp_redraw(step)

  if mixing then
    local pos = ((current_bar - 121) * 16 + (step - 1)) / (8 * 16)
    local old_amount = 1 - pos
    local new_amount = pos

    if old_amount > 0.35 then
      play_deck(current_deck(), current_bar, step, nil)
    end

    play_deck(next_deck(), next_bar, next_step, new_amount)
  else
    play_deck(current_deck(), current_bar, step, nil)
  end

  step = step + 1
  if mixing then next_step = next_step + 1 end
  tick = tick + 1

  if step > 16 then
    step = 1
    current_bar = current_bar + 1
  end

  if mixing and next_step > 16 then
    next_step = 1
    next_bar = next_bar + 1
  end

  if current_bar > phrase_bars then
    finish_handover()
  end

  redraw()
end

local function update_clock()
  if metro_clock then metro_clock:stop() end
  metro_clock = metro.init()
  metro_clock.time = 60 / bpm / ppqn
  metro_clock.event = clock_tick
  metro_clock:start()
end

local function chord_test()
  if not chord_midi_out then return end
  j6_program_change(random_pc())
  chord_note(60, 110, 8)
  chord_note_delayed(64, 110, 1, 8)
  chord_note_delayed(67, 110, 2, 8)
end

-- Build a list of MIDI device names for use in option params.
-- Slots 1-8 map directly to midi.connect() device numbers.
local function midi_device_names()
  local names = {}
  for i = 1, 8 do
    local d = midi.devices[i]
    if d and d.name then
      names[i] = d.name
    else
      names[i] = "---"
    end
  end
  return names
end

function init()
  math.randomseed(os.time())

  midi_out = midi.connect(mdev)
  chord_midi_out = midi.connect(chord_mdev)
  connect_mx1_midi()

  scan_acapellas()
  setup_softcut()

  local dev_names = midi_device_names()

  params:add_separator("endless_dj", "ENDLESS DJ")

  params:add_option("t8_midi_device", "t8 device", dev_names, mdev)
  params:set_action("t8_midi_device", function(v)
    mdev = v
    midi_out = midi.connect(mdev)
  end)

  params:add_option("j6_midi_device", "j6 device", dev_names, chord_mdev)
  params:set_action("j6_midi_device", function(v)
    chord_mdev = v
    chord_midi_out = midi.connect(chord_mdev)
  end)

  params:add_separator("mx1", "ROLAND AIRA MX-1")

  params:add_option("mx1_midi_device", "mx1 device", dev_names, mx1_mdev)
  params:set_action("mx1_midi_device", function(v)
    mx1_mdev = v
    connect_mx1_midi()
  end)

  params:add_option("mx1_fx_enabled", "mx1 beat fx", {"off","on"}, 2)
  params:set_action("mx1_fx_enabled", function(v) mx1_fx_enabled = (v == 2) end)

  params:add_number("mx1_ch", "mx1 system channel", 1, 16, mx1_ch)
  params:set_action("mx1_ch", function(v) mx1_ch = v end)

  params:add_number("mx1_fx_cc", "mx1 fx depth cc", 1, 127, mx1_fx_cc)
  params:set_action("mx1_fx_cc", function(v) mx1_fx_cc = v end)

  params:add_separator("transport", "TRANSPORT")

  params:add_number("bpm", "bpm", 60, 180, bpm)
  params:set_action("bpm", function(v)
    bpm = v
    update_clock()
  end)

  params:add_number("drum_ch", "drum channel", 1, 16, drum_ch)
  params:set_action("drum_ch", function(v) drum_ch = v end)

  params:add_number("bass_ch", "bass channel", 1, 16, bass_ch)
  params:set_action("bass_ch", function(v) bass_ch = v end)

  params:add_number("chord_ch", "chord channel", 1, 16, chord_ch)
  params:set_action("chord_ch", function(v) chord_ch = v end)

  params:add_option("j6_pc_enabled", "j6 program change", {"off","on"}, 2)
  params:set_action("j6_pc_enabled", function(v) j6_pc_enabled = (v == 2) end)

  params:add_number("j6_pc_ch", "j6 pc channel", 1, 16, j6_pc_ch)
  params:set_action("j6_pc_ch", function(v) j6_pc_ch = v end)

  params:add_number("j6_pc_min", "j6 pc min", 0, 63, j6_pc_min)
  params:set_action("j6_pc_min", function(v) j6_pc_min = v end)

  params:add_number("j6_pc_max", "j6 pc max", 0, 63, j6_pc_max)
  params:set_action("j6_pc_max", function(v) j6_pc_max = v end)

  params:add_option("manual_xfade", "manual crossfader", {"no","yes"}, 1)
  params:set_action("manual_xfade", function(v) manual_xfade = (v == 2) end)

  params:add_separator("launchpad_sep", "LAUNCHPAD")
  params:add_option("lp_midi_device", "launchpad device", dev_names, lp_dev)
  params:set_action("lp_midi_device", function(v)
    lp_dev = v
    lp_connect(lp_dev)
  end)

  -- ── Norns instrument ──────────────────────────
  params:add_separator("norns_inst_sep", "NORNS INSTRUMENT")

  params:add_option("norns_inst_enabled", "norns inst enabled", {"off","on"}, 2)
  params:set_action("norns_inst_enabled", function(v)
    norns_inst_enabled = (v == 2)
  end)

  local preset_names = {}
  for i, p in ipairs(norns_presets) do preset_names[i] = p.name end
  params:add_option("norns_inst_preset", "norns inst sound", preset_names, norns_preset_idx)
  params:set_action("norns_inst_preset", function(v)
    norns_preset_idx = v
    deck_a.norns_preset = v
    deck_b.norns_preset = v
  end)

  params:add_number("norns_inst_vol", "norns inst vol", 0, 10, math.floor(norns_inst_vol * 10))
  params:set_action("norns_inst_vol", function(v)
    norns_inst_vol = v / 10
  end)

  -- ── Acapella ──────────────────────────────────
  params:add_separator("acapella_sep", "ACAPELLA")

  params:add_option("acapella_enabled", "acapella enabled", {"off","on"}, 1)
  params:set_action("acapella_enabled", function(v)
    acapella_enabled = (v == 2)
    if not acapella_enabled then stop_acapella() end
  end)

  local ac_names = {}
  if #acapella_files > 0 then
    for _, ac in ipairs(acapella_files) do
      table.insert(ac_names, ac.filename)
    end
  else
    ac_names = {"no files in dust/audio/endlessdj/"}
  end
  params:add_option("acapella_file", "acapella file", ac_names, 1)
  params:set_action("acapella_file", function(v)
    if #acapella_files > 0 then
      load_acapella(v)
    end
  end)

  params:add_number("acapella_vol", "acapella vol", 0, 10, math.floor(acapella_vol * 10))
  params:set_action("acapella_vol", function(v)
    acapella_vol = v / 10
    softcut.level(ACAPELLA_VOICE, acapella_vol)
  end)

  update_clock()
  lp_connect(lp_dev)
  redraw()
end

function cleanup()
  quiet_notes()
  lp_clear()
  stop_acapella()
  if metro_clock then metro_clock:stop() end
end

function key(n,z)
  if z == 0 then return end

  if n == 2 then
    playing = not playing
    if not playing then
      quiet_notes()
      stop_acapella()
    else
      start_acapella()
    end
  elseif n == 3 then
    if playing then
      current_bar = 121
      step = 1
      mixing = false
      next_bar = nil
    else
      chord_test()
    end
  end

  redraw()
end

function enc(n,d)
  if n == 2 then
    bpm = clamp(bpm + d, 60, 180)
    params:set("bpm", bpm)
  elseif n == 3 then
    manual_xfade = true
    params:set("manual_xfade", 2)
    xfade = clamp(xfade + d*2, 0, 100)
  end
  redraw()
end

-- small turntable-style deck, inspired by adamstaff/turntable's visual approach:
-- filled platter, moving label/sticker, grooves, and a tonearm whose stylus
-- travels inward across the record.
local function deck_play_progress(deck)
  if deck.active then
    return clamp((current_bar - 1 + (step - 1) / 16) / phrase_bars, 0, 1)
  end

  if mixing and deck == next_deck() and next_bar then
    return clamp((next_bar - 1 + (next_step - 1) / 16) / phrase_bars, 0, 1)
  end

  return 0
end

local function draw_tonearm(cx, cy, r, progress, active, flip)
  local base_x
  local base_y = cy - r - 3

  if flip then
    base_x = cx - r - 6
  else
    base_x = cx + r + 6
  end

  local start_radius = r - 2
  local end_radius = 5
  local current_radius = start_radius - progress * (start_radius - end_radius)

  local arm_angle
  if flip then
    arm_angle = math.pi * 1.25
  else
    arm_angle = math.pi * 1.75
  end

  local tip_x = cx + math.cos(arm_angle) * current_radius
  local tip_y = cy - math.sin(arm_angle) * current_radius

  local arm_vec_x = tip_x - base_x
  local arm_vec_y = tip_y - base_y
  local arm_len = math.sqrt(arm_vec_x * arm_vec_x + arm_vec_y * arm_vec_y)

  if arm_len < 1 then return end

  local arm_norm_x = arm_vec_x / arm_len
  local arm_norm_y = arm_vec_y / arm_len
  local perp_x = -arm_norm_y
  local perp_y = arm_norm_x

  local bend = flip and 3 or -3
  local cp1_x = base_x + arm_vec_x * 0.45 - perp_x * bend
  local cp1_y = base_y + arm_vec_y * 0.45 + perp_y * bend
  local cp2_x = base_x + arm_vec_x * 0.70 + perp_x * bend
  local cp2_y = base_y + arm_vec_y * 0.70 - perp_y * bend

  screen.level(active and 9 or 3)
  screen.circle(base_x, base_y, 4)
  screen.fill()

  screen.level(active and 15 or 5)
  screen.circle(base_x, base_y, 2)
  screen.fill()

  screen.level(active and 15 or 5)
  screen.move(base_x, base_y)
  screen.curve(cp1_x, cp1_y, cp2_x, cp2_y, tip_x, tip_y)
  screen.stroke()

  screen.move(tip_x, tip_y)
  if flip then
    screen.line_rel(-2, -1)
  else
    screen.line_rel(2, -1)
  end
  screen.stroke()
end

local function draw_deck(cx, cy, r, angle, active, label, deck, flip)
  local progress = deck_play_progress(deck)

  screen.aa(1)

  screen.level(active and 4 or 2)
  screen.circle(cx, cy, r + 3)
  screen.fill()

  screen.level(0)
  screen.circle(cx, cy, r)
  screen.fill()

  screen.level(active and 9 or 4)
  screen.circle(cx, cy, r)
  screen.stroke()

  local jitter = 0
  if playing and active then
    jitter = math.sin(angle * 2) * 0.08
  end

  screen.level(active and 4 or 2)
  screen.arc(cx, cy, r - 3, 5.2 + jitter, 5.55 + jitter)
  screen.stroke()
  screen.arc(cx, cy, r - 6, 1.45 + jitter, 1.95 + jitter)
  screen.stroke()

  screen.level(active and 15 or 6)
  screen.circle(cx, cy, 6)
  screen.fill()

  screen.level(0)
  screen.arc(cx, cy, 5, angle - 0.12, angle + 0.12)
  screen.stroke()

  screen.level(0)
  screen.circle(cx, cy, 1)
  screen.fill()

  local sx = cx + math.floor(math.cos(angle) * (r - 2) + 0.5)
  local sy = cy + math.floor(math.sin(angle) * (r - 2) + 0.5)
  screen.level(active and 15 or 5)
  screen.circle(sx, sy, 1.5)
  screen.fill()

  draw_tonearm(cx, cy, r, progress, active, flip)

  screen.aa(0)
  screen.level(10)
  screen.move(cx - 3, cy + r + 8)
  screen.text(label)
end

local function draw_xfader()
  local x0, x1, y = 24, 104, 54

  screen.level(4)
  screen.rect(x0, y, x1-x0, 1)
  screen.fill()

  screen.level(15)
  local x = x0 + math.floor((x1-x0) * xfade / 100)
  screen.rect(x-3, y-4, 6, 8)
  screen.fill()
end

function redraw()
  screen.clear()
  screen.aa(0)

  if playing then
    deck_a.angle = deck_a.angle + (deck_a.active and 0.18 or 0.08)
    deck_b.angle = deck_b.angle + (deck_b.active and 0.18 or 0.08)
  end

  screen.level(15)
  screen.move(1,8)
  screen.text("ENDLESS")
  screen.move(106,8)
  screen.text(bpm)

  draw_deck(34, 28, 14, deck_a.angle, deck_a.active or (mixing and deck_a == next_deck()), "A", deck_a, false)
  draw_deck(94, 28, 14, deck_b.angle, deck_b.active or (mixing and deck_b == next_deck()), "B", deck_b, false)

  draw_xfader()

  screen.level(12)
  screen.move(4,63)

  if playing then
    if mixing then
      screen.text("MIX " .. current_deck().genre .. ">" .. next_deck().genre)
    else
      screen.text(section_for_bar(current_bar) .. " " .. current_bar .. " " .. current_deck().genre)
    end
  else
    screen.text("K2 PLAY  K3 J6 TEST")
  end

  screen.update()
end
