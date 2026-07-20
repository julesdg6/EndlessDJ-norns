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
--   T-8 drums  ch9  on t8 midi device  (default device 1 via MX-1)
--   T-8 bass   ch8  on t8 midi device
--   J-6 chords ch6  on j6 midi device  (default device 1 via MX-1)
--   MX-1 Beat FX depth automated via CC during mix transitions

engine.name = "PolyPerc"

-- Virtual grid connection (monome or midigrid virtual device).
-- With the midigrid mod enabled (SYSTEM → MODS → MIDIGRID), two Launchpad
-- Mini MK3 controllers appear as one 16×8 virtual grid.  Physical-device
-- setup, Programmer mode, rotation, RGB conversion, and LED buffering are
-- handled by midigrid; this script uses only the standard grid API.
local g   -- grid object; nil when no grid is connected

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
-- Fields: release in seconds, cutoff in Hz, gain = filter resonance (0-1), pw = pulse width (0-1).
-- Note: PolyPerc uses Env.perc with a fixed default attack; there is no engine.attack command.
local norns_presets = {
  {name="pad",     release=2.0, cutoff=800,  gain=0.5, pw=0.5},
  {name="synth",   release=0.5, cutoff=3000, gain=0.3, pw=0.3},
  {name="pluck",   release=0.3, cutoff=5000, gain=0.2, pw=0.2},
  {name="strings", release=1.5, cutoff=1500, gain=0.4, pw=0.5},
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

-- ──────────────────────────────────────────────
-- Korg NTS-1 (optional melodic voice)
-- ──────────────────────────────────────────────
local nts1_midi_out
local nts1_mdev = 1
local nts1_enabled = false
local nts1_ch = 1
local nts1_variation_amount = 0.35
local nts1_motif_density = 0.65
local nts1_register = 0
local nts1_cc_enabled = true
local nts1_cc_cache = {}
local nts1_cc_last_tick = {}
local nts1_reset_cc_state
local NTS1_LCG_MOD = 4294967296 -- 2^32
local NTS1_OCTAVE_DIVISOR = 97
local NTS1_SECTION_BARS = 16
local NTS1_SECTION_PHASE_DENOM = 15
local NTS1_MIX_OUTGOING_DENSITY = 0.45
local NTS1_MIX_INCOMING_DENSITY = 0.75
local NTS1_RHYTHM_MIN_NOTES = 2
local NTS1_RHYTHM_REDUCE_MUT_MAX = 0.55
local NTS1_RHYTHM_MAX_NOTES = 6
local NTS1_RHYTHM_APPEND_START = 10
local NTS1_RHYTHM_APPEND_STEP = 3
local NTS1_RHYTHM_MAX_OFFSET = 15
local NTS1_MUTATION_SEED_OFFSET = 7
local NTS1_MUTATION_OP_COUNT = 7
local NTS1_MOTIF_INDEX_BASE_OFFSET = 2

-- ──────────────────────────────────────────────
-- Akai MPX8 (optional one-shot / sample layer)
-- ──────────────────────────────────────────────
local mpx8_midi_out
local mpx8_mdev = 1
local mpx8_enabled = false
local mpx8_ch = 10 -- MIDI channel 10 (General MIDI drum channel); matches MPX8 i01 incoming Note On channel
-- Factory Internal Kit i01 pad notes (1-8):
--   1=kick(36)  2=snare(38)  3=closed hat(42)  4=open hat(46)
--   5=low tom(43)  6=mid tom(47)  7=crash(49)  8=ride(51)
-- Endless DJ semantics still map to these pads by index (see params labels).
local mpx8_pads = {36, 38, 42, 46, 43, 47, 49, 51}

local playing = false
local bpm = 128
local ppqn = 4
local tick = 0
local phrase_bars = 128
local step = 1

-- Mixing spans the last 32 bars of the phrase, split into four 8-bar phases:
--   Phase 1 (bars 97-104):  fade kick between decks
--   Phase 2 (bars 105-112): fade bass between decks
--   Phase 3 (bars 113-120): fade other drums between decks
--   Phase 4 (bars 121-128): fade chords/melody between decks
local MIX_START_BAR = 97
local MIX_BARS = 32

local current_bar = 1
local next_bar = nil
local next_step = 1
local mixing = false

local xfade = 0
local manual_xfade = false
local generation = 2

local drum_ch = 9
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
  "DUBSTEP",
  "DEEP",
  "ACID",
  "TRANCE",
  "PROG",
  "JUNGLE",
  "DNB",
  "LIQUID",
  "HARDTECHNO",
  "ELECTRO",
  "JUKE",
  "AFRO",
  "MINIMAL",
  "MELODIC",
  "SPEED",
  "BASSLINE",
  "HARDSTYLE"
}

local roots = {45,47,48,50,52,53,55}

local deck_a = {name="A-001", genre="HOUSE",    active=true,  angle=0, root=45, pc=0, norns_preset=1,
                variation_seed=12345, mpx8_riser_fired=false, mpx8_impact_fired=false, mpx8_drop_accent_fired=false}
local deck_b = {name="B-002", genre="TWO_STEP", active=false, angle=0, root=50, pc=1, norns_preset=2,
                variation_seed=54321, mpx8_riser_fired=false, mpx8_impact_fired=false, mpx8_drop_accent_fired=false}

local notes_off = {}
local notes_pending = {}

local KICK = 36
local SNARE = 38
local CLAP = 50
local TOM = 47
local CHH = 42
local OHH = 46

-- ──────────────────────────────────────────────
-- Virtual 16×8 grid state
-- Left half  (x 1–8):  four-lane drum sequencer
-- Right half (x 9–16): NTS-1 and J-6 trigger lanes + playable keyboard
-- ──────────────────────────────────────────────

-- 4 drum lanes x 16 steps: 1=kick  2=snare  3=open hat  4=closed hat
local drum_steps = {}
for i = 1, 4 do
  drum_steps[i] = {}
  for j = 1, 16 do drum_steps[i][j] = false end
end

-- Right-half trigger patterns (16 steps, toggled via grid pads)
local nts1_steps = {}   -- NTS-1 melody: true = allowed to trigger on this step
local j6_steps   = {}   -- J-6 chord:   true = allowed to trigger on this step
for i = 1, 16 do nts1_steps[i] = false end
for i = 1, 16 do j6_steps[i]   = false end

-- Activity levels for synth rows (set when instrument fires; decayed each tick)
local grid_nts1_level = 0
local grid_j6_level   = 0

-- ──────────────────────────────────────────────
-- Keyboard state (right half, y = 5–8)
-- ──────────────────────────────────────────────
local kb_base    = 48   -- MIDI note at bottom-left of keyboard area (C3)
local kb_octave  = 0    -- additional octave shift (params: grid_kb_octave)
local kb_pressed = {}   -- note → true while pad is held (for note-off cleanup)
local kb_target  = 1    -- 1 = NTS-1  2 = J-6  3 = Norns instrument

-- ──────────────────────────────────────────────
-- Semantic grid brightness levels (0–15)
-- midigrid maps these to device-specific RGB via its selected palette.
-- Use the `endless_dj` palette (SYSTEM → MODS → MIDIGRID → palette) for
-- distinct instrument colours; any standard palette gives usable brightness.
-- ──────────────────────────────────────────────
local LEVEL = {
  OFF      = 0,
  INACTIVE = 1,   -- inactive step
  PLAYHEAD = 3,   -- cursor on an inactive step
  KICK     = 5,   -- kick drum lane
  SNARE    = 6,   -- snare lane
  OHAT     = 7,   -- open hi-hat lane
  CHAT     = 8,   -- closed hi-hat lane
  NTS1     = 9,   -- NTS-1 enabled step
  J6       = 10,  -- J-6 enabled step
  ROOT     = 11,  -- root note (keyboard)
  SCALE    = 12,  -- in-scale note (keyboard)
  CHROMA   = 13,  -- chromatic / out-of-scale note (keyboard)
  PRESSED  = 14,  -- pressed note or active trigger
  HOT      = 15,  -- active step under playhead / bright white
}

-- Forward declarations (tables defined after drum/chord pattern tables below)
local bass_patterns
local chord_allow_house

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
    local pos = ((current_bar - MIX_START_BAR) * 16 + (step - 1)) / (MIX_BARS * 16)
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
  -- Disable variation (Roland J-6 CC 80: 0-63 = off)
  chord_midi_out:cc(80, 0, j6_pc_ch)
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
    norns_preset = math.random(#norns_presets),
    variation_seed = math.random(1, 65535),
    nts1_identity = nil,
    nts1_motif = nil,
    nts1_phrase = nil,
    nts1_motif_turn = 1,
    nts1_motif_mutation_bars = nil,
    -- Per-deck MPX8 one-shot flags (reset each time a new deck is generated)
    mpx8_riser_fired = false,
    mpx8_impact_fired = false,
    mpx8_drop_accent_fired = false,
  }
end

local function current_deck()
  return deck_a.active and deck_a or deck_b
end

local function next_deck()
  return deck_a.active and deck_b or deck_a
end

local function nts1_reset_deck_identities()
  for _, d in ipairs({deck_a, deck_b}) do
    d.nts1_identity = nil
    d.nts1_motif = nil
    d.nts1_phrase = nil
    d.nts1_motif_turn = 1
  end
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

  -- Clear any hanging NTS-1 notes on the configured channel.
  if nts1_midi_out then
    for n=0,127 do
      nts1_midi_out:note_off(n, 0, nts1_ch)
    end
  end

  -- Reset MX-1 Beat FX depth so no effect lingers after stopping.
  send_mx1_cc(mx1_fx_cc, 0)
  nts1_reset_cc_state()

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

local function clear_scheduled_notes_for_device(dev)
  if not dev then return end
  for i=#notes_pending,1,-1 do
    if notes_pending[i].dev == dev then
      table.remove(notes_pending, i)
    end
  end
  for i=#notes_off,1,-1 do
    if notes_off[i].dev == dev then
      table.remove(notes_off, i)
    end
  end
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

-- Convert a MIDI note number to frequency in Hz (A440 tuning; note 69 = 440 Hz).
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
-- key: note letter (A-G), optional accidental (b/#), optional minor suffix (m/M)
-- Returns bpm (number), semitone (0-11 or nil), key_str on success; nil on failure.
local function parse_acapella_filename(filename)
  local bpm_str, key_str = filename:match("^(%d+)_([A-Ga-g][b#]?[mM]?)_")
  if not bpm_str then return nil end
  local bpm_val = tonumber(bpm_str)
  -- Reject implausible BPM values (valid music range: 40–250)
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
  -- Reject paths containing shell-unsafe characters to prevent command injection.
  if dir:find('[\'"`$\\;|&<>]') then return end
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
  -- buffer_read_mono(path, src_start, dst_start, duration, src_ch, buf)
  -- src_start=0: read from file beginning; dst_start=0: write to buffer start;
  -- duration=-1: read entire file; src_ch=1: left/mono channel; buf=buffer index
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
  },
  DEEP = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={7,15}
  },
  ACID = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={3,7,11,15}
  },
  TRANCE = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}
  },
  PROG = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={1,3,5,7,9,11,13,15}
  },
  JUNGLE = {
    kick={1,3,7,11,13},
    snare={5,9,13},
    clap={},
    hats={2,4,6,8,10,12,14,16}
  },
  DNB = {
    kick={1,7,11},
    snare={5,9,13},
    clap={},
    hats={2,4,6,8,10,12,14,16}
  },
  LIQUID = {
    kick={1,7,11},
    snare={5,9,13},
    clap={9},
    hats={3,6,9,12,15}
  },
  HARDTECHNO = {
    kick={1,5,9,13},
    snare={},
    clap={5,13},
    tom={3,7,11,15},
    hats={2,4,6,8,10,12,14,16}
  },
  ELECTRO = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={3,7,10,14}
  },
  JUKE = {
    kick={1,5,7,9,11,13,15},
    snare={5,9,13},
    clap={},
    hats={1,3,5,7,9,11,13,15}
  },
  AFRO = {
    kick={1,5,9,13},
    snare={7,15},
    clap={5,11},
    tom={3,8,12},
    hats={2,4,7,10,12,15}
  },
  MINIMAL = {
    kick={1,9},
    snare={},
    clap={9},
    hats={5,13}
  },
  MELODIC = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={3,7,11,15}
  },
  SPEED = {
    kick={1,5,9,13},
    snare={5,13},
    clap={3,9},
    hats={3,7,10,14}
  },
  BASSLINE = {
    kick={1,5,9,13},
    snare={5,13},
    clap={5,13},
    hats={4,8,12,16}
  },
  HARDSTYLE = {
    kick={1,5,9,13},
    snare={9},
    clap={},
    hats={3,7,11,15}
  }
}

-- ──────────────────────────────────────────────
-- Grid coordinate helpers
-- ──────────────────────────────────────────────

-- Map drum (lane 1-4, step 1-16) → grid (x 1-8, y 1-8).
-- Layout (y=1 = top row):
--   lane 1 kick:       y 1-2,  steps 1-8 → y=1, steps 9-16 → y=2
--   lane 2 snare:      y 3-4
--   lane 3 open hat:   y 5-6
--   lane 4 closed hat: y 7-8
local function drum_to_xy(lane, s)
  local row_offset = s > 8 and 1 or 0
  local y = (lane - 1) * 2 + 1 + row_offset
  local x = s <= 8 and s or (s - 8)
  return x, y
end

-- Map grid (x 1-8, y 1-8) → drum (lane 1-4, step 1-16).
local function xy_to_drum(x, y)
  local lane = math.ceil(y / 2)
  local s = x + ((y - 1) % 2) * 8
  return lane, s
end

-- Map synth (inst 1-2, step 1-16) → grid (x 9-16, y 1-4).
-- inst 1 = NTS-1 (y=1-2), inst 2 = J-6 (y=3-4)
local function synth_to_xy(inst, s)
  local row_offset = s > 8 and 1 or 0
  local y = (inst - 1) * 2 + 1 + row_offset
  local x = 8 + (s <= 8 and s or (s - 8))
  return x, y
end

-- Map grid (x 9-16, y 1-4) → synth (inst 1-2, step 1-16); nil if outside.
local function xy_to_synth(x, y)
  if y < 1 or y > 4 then return nil, nil end
  local inst = math.ceil(y / 2)
  local s = (x - 8) + ((y - 1) % 2) * 8
  if s < 1 or s > 16 then return nil, nil end
  return inst, s
end

-- Map keyboard grid (x 9-16, y 5-8) → MIDI note.
-- y=8 (bottom row) starts at kb_base + kb_octave*12; each row adds 8 semitones.
local function kb_note_for(x, y)
  local row = 8 - y    -- 0=bottom (y=8), 3=top (y=5)
  return kb_base + kb_octave * 12 + row * 8 + (x - 9)
end

-- Returns true when note shares its pitch class with root.
local function is_root_note(note, root)
  return (note - root) % 12 == 0
end

-- Major-scale intervals (semitones above root).
local MAJOR_SCALE_INTERVALS = {0, 2, 4, 5, 7, 9, 11}

-- Returns true when note is in the major scale rooted at root.
local function is_scale_note(note, root)
  local interval = (note - root) % 12
  for _, v in ipairs(MAJOR_SCALE_INTERVALS) do
    if interval == v then return true end
  end
  return false
end

-- ──────────────────────────────────────────────
-- J-6 trigger pattern initialisation
-- ──────────────────────────────────────────────

-- Populate j6_steps with the genre's default chord-trigger steps so the
-- initial grid pattern matches the generative engine's timing rules.
local function j6_init_pattern(genre)
  for i = 1, 16 do j6_steps[i] = false end
  if chord_allow_house and chord_allow_house[genre] then
    j6_steps[1] = true; j6_steps[9] = true
  elseif genre == "TWO_STEP" then
    j6_steps[4] = true; j6_steps[10] = true
  elseif genre == "BREAKS" then
    j6_steps[1] = true; j6_steps[11] = true
  elseif genre == "TECHNO" or genre == "DUBSTEP" then
    j6_steps[1] = true; j6_steps[9] = true
  elseif genre == "TRANCE" or genre == "PROG" or genre == "HARDTECHNO" then
    j6_steps[1] = true
  elseif genre == "JUKE" then
    j6_steps[1] = true; j6_steps[5] = true
    j6_steps[9] = true; j6_steps[13] = true
  elseif genre == "MINIMAL" then
    j6_steps[1] = true
  elseif genre == "SPEED" or genre == "BASSLINE" then
    j6_steps[4] = true; j6_steps[12] = true
  else
    j6_steps[1] = true   -- fallback: trigger at bar start
  end
end

-- Load drum and synth patterns from a genre's defaults.
local function grid_load_pattern(genre)
  local p = drum_patterns[genre] or drum_patterns.HOUSE
  for i = 1, 16 do
    drum_steps[1][i] = hit(p.kick  or {}, i)
    drum_steps[2][i] = hit(p.snare or {}, i)
    drum_steps[3][i] = false                  -- open hat starts empty for editing
    drum_steps[4][i] = hit(p.hats  or {}, i)
  end
  j6_init_pattern(genre)
  -- NTS-1 triggers at bar start by default
  for i = 1, 16 do nts1_steps[i] = false end
  nts1_steps[1] = true
end

-- ──────────────────────────────────────────────
-- Grid drawing
-- ──────────────────────────────────────────────

local function grid_redraw(s)
  if not g then return end
  local deck = current_deck()

  -- Left half: drum sequencer (x=1-8, y=1-8)
  local drum_lane_levels = {LEVEL.KICK, LEVEL.SNARE, LEVEL.OHAT, LEVEL.CHAT}
  for lane = 1, 4 do
    local lane_level = drum_lane_levels[lane]
    for step_i = 1, 16 do
      local x, y = drum_to_xy(lane, step_i)
      local level
      if step_i == s then
        level = drum_steps[lane][step_i] and LEVEL.HOT or LEVEL.PLAYHEAD
      elseif drum_steps[lane][step_i] then
        level = lane_level
      else
        level = LEVEL.INACTIVE
      end
      g:led(x, y, level)
    end
  end

  -- Right half: NTS-1 trigger pattern (x=9-16, y=1-2)
  for step_i = 1, 16 do
    local x, y = synth_to_xy(1, step_i)
    local level
    if step_i == s then
      if nts1_steps[step_i] and grid_nts1_level > 0 then
        level = LEVEL.PRESSED
      elseif nts1_steps[step_i] then
        level = LEVEL.HOT
      else
        level = LEVEL.PLAYHEAD
      end
    elseif nts1_steps[step_i] then
      level = LEVEL.NTS1
    else
      level = LEVEL.INACTIVE
    end
    g:led(x, y, level)
  end

  -- Right half: J-6 trigger pattern (x=9-16, y=3-4)
  for step_i = 1, 16 do
    local x, y = synth_to_xy(2, step_i)
    local level
    if step_i == s then
      if j6_steps[step_i] and grid_j6_level > 0 then
        level = LEVEL.PRESSED
      elseif j6_steps[step_i] then
        level = LEVEL.HOT
      else
        level = LEVEL.PLAYHEAD
      end
    elseif j6_steps[step_i] then
      level = LEVEL.J6
    else
      level = LEVEL.INACTIVE
    end
    g:led(x, y, level)
  end

  -- Right half: chromatic keyboard (x=9-16, y=5-8)
  -- Layout (y=8 bottom): rows cover 8 chromatic notes each; every row adds
  -- 8 semitones so the 32 pads span roughly 2.5 octaves.  Root notes are
  -- highlighted; in-scale and chromatic notes are visually distinct.
  for ky = 5, 8 do
    for kx = 9, 16 do
      local note = kb_note_for(kx, ky)
      local level
      if kb_pressed[note] then
        level = LEVEL.PRESSED
      elseif is_root_note(note, deck.root) then
        level = LEVEL.ROOT
      elseif is_scale_note(note, deck.root) then
        level = LEVEL.SCALE
      else
        level = LEVEL.CHROMA
      end
      g:led(kx, ky, level)
    end
  end

  g:refresh()
end

-- Turn off all grid LEDs.
local function grid_clear()
  if not g then return end
  g:all(LEVEL.OFF)
  g:refresh()
end

-- ──────────────────────────────────────────────
-- Keyboard MIDI output
-- ──────────────────────────────────────────────

local function kb_note_on(note)
  if kb_target == 1 then
    if nts1_enabled and nts1_midi_out then
      nts1_midi_out:note_on(note, 100, nts1_ch)
    end
  elseif kb_target == 2 then
    if chord_midi_out then chord_midi_out:note_on(note, 100, chord_ch) end
  elseif kb_target == 3 then
    engine.hz(note_to_hz(note))
  end
end

local function kb_note_off(note)
  if kb_target == 1 then
    if nts1_midi_out then nts1_midi_out:note_off(note, 0, nts1_ch) end
  elseif kb_target == 2 then
    if chord_midi_out then chord_midi_out:note_off(note, 0, chord_ch) end
  end
  -- PolyPerc (kb_target==3) does not support explicit note-off
end

-- Send note-off for every currently held keyboard note and clear pressed state.
local function kb_all_notes_off()
  for note, _ in pairs(kb_pressed) do
    kb_note_off(note)
  end
  kb_pressed = {}
end

-- ──────────────────────────────────────────────
-- Grid key handler and connection
-- ──────────────────────────────────────────────

local function grid_key(x, y, z)
  if x <= 8 then
    -- Left half: drum sequencer
    if z == 0 then return end
    local lane, s_idx = xy_to_drum(x, y)
    if lane >= 1 and lane <= 4 and s_idx >= 1 and s_idx <= 16 then
      drum_steps[lane][s_idx] = not drum_steps[lane][s_idx]
      grid_redraw(step)
    end
  elseif y <= 4 then
    -- Right half, upper rows: synth trigger lanes
    if z == 0 then return end
    local inst, s_idx = xy_to_synth(x, y)
    if inst == 1 and s_idx then
      nts1_steps[s_idx] = not nts1_steps[s_idx]
      grid_redraw(step)
    elseif inst == 2 and s_idx then
      j6_steps[s_idx] = not j6_steps[s_idx]
      grid_redraw(step)
    end
  else
    -- Right half, lower rows (y=5-8): chromatic keyboard
    local note = kb_note_for(x, y)
    if z > 0 then
      kb_pressed[note] = true
      kb_note_on(note)
    else
      kb_pressed[note] = nil
      kb_note_off(note)
    end
    grid_redraw(step)
  end
end

-- Connect to the virtual grid and set up the key callback.
local function grid_connect()
  g = grid.connect()
  if g then
    g.key = grid_key
    grid_load_pattern(current_deck().genre)
    grid_redraw(step)
  end
end

bass_patterns = {
  HOUSE={0,0,7,0, 0,10,7,0, 0,0,12,10, 7,0,3,0},
  FUNKY={0,7,0,10, 12,10,7,0, 5,0,7,10, 12,0,10,7},
  DIRTY={0,0,0,3, 0,0,7,10, 0,0,12,10, 7,3,0,0},
  TECHNO={0,0,0,0, 7,0,0,0, 0,0,10,0, 7,0,3,0},
  GARAGE4={0,0,7,0, 10,0,7,0, 0,12,0,10, 7,0,3,0},
  TWO_STEP={0,0,0,7, 0,10,0,0, 12,0,0,10, 0,7,3,0},
  BREAKS={0,0,7,0, 0,0,10,0, 12,0,7,0, 3,0,0,10},
  DUBSTEP={0,0,0,0, -12,0,0,0, 0,0,0,-5, -12,0,0,0},
  DEEP={0,0,0,0, 0,0,0,0, 5,0,0,0, 7,0,0,0},
  ACID={0,0,12,0, 5,0,7,10, 0,0,12,0, 5,7,0,0},
  TRANCE={0,0,5,7, 0,10,5,0, 0,0,7,10, 5,0,7,0},
  PROG={0,0,0,0, 7,0,0,0, 0,0,0,0, 5,0,0,0},
  JUNGLE={0,0,0,7, 0,12,0,0, 5,0,0,7, 0,0,12,0},
  DNB={0,0,7,0, 0,0,10,0, 0,7,0,0, 12,0,5,0},
  LIQUID={0,5,0,7, 0,10,0,5, 7,0,12,0, 5,0,7,10},
  HARDTECHNO={0,0,0,0, 0,0,0,0, 7,0,0,0, 0,0,0,0},
  ELECTRO={0,0,7,0, 0,0,5,0, 0,7,0,10, 0,5,0,0},
  JUKE={0,7,0,5, 0,7,10,0, 0,5,0,7, 12,0,7,0},
  AFRO={0,0,5,0, 0,7,0,10, 0,0,5,7, 0,10,0,0},
  MINIMAL={0,0,0,0, 0,0,0,0, 0,0,7,0, 0,0,0,0},
  MELODIC={0,0,5,7, 10,0,7,5, 0,5,0,7, 10,7,5,0},
  SPEED={0,0,7,0, 0,10,0,7, 0,0,12,0, 7,0,5,0},
  BASSLINE={0,7,0,10, 0,12,7,0, 5,0,7,0, 10,0,7,5},
  HARDSTYLE={0,0,0,0, 7,0,0,0, 0,0,0,0, 5,0,7,0}
}

local chord_progs = {
  HOUSE={{0,3,7},{5,8,12},{7,10,14},{3,7,10}},
  FUNKY={{0,4,7},{5,9,12},{7,11,14},{10,14,17}},
  DIRTY={{0,3,7},{3,7,10},{5,8,12},{7,10,14}},
  TECHNO={{0,3,7},{0,3,7},{-2,1,5},{0,3,7}},
  GARAGE4={{0,3,7},{5,8,12},{10,14,17},{7,10,14}},
  TWO_STEP={{0,3,7},{10,14,17},{5,8,12},{7,10,14}},
  BREAKS={{0,3,7},{7,10,14},{5,8,12},{3,7,10}},
  DUBSTEP={{0,3,7},{0,3,7},{-5,-2,2},{-7,-4,0}},
  DEEP={{0,3,7},{5,8,12},{7,10,14},{5,8,12}},
  ACID={{0,3,7},{0,3,7},{5,8,12},{0,3,7}},
  TRANCE={{0,4,7},{5,9,12},{9,12,16},{7,11,14}},
  PROG={{0,3,7},{0,3,7},{7,10,14},{5,8,12}},
  JUNGLE={{0,3,7},{10,13,17},{5,8,12},{7,10,14}},
  DNB={{0,3,7},{3,7,10},{7,10,14},{5,8,12}},
  LIQUID={{0,4,7},{5,9,12},{7,11,14},{3,7,10}},
  HARDTECHNO={{0,3,7},{-5,-2,2},{0,3,7},{0,3,7}},
  ELECTRO={{0,3,7},{5,8,12},{3,7,10},{7,10,14}},
  JUKE={{0,3,7},{0,3,7},{5,8,12},{5,8,12}},
  AFRO={{0,4,7},{5,9,12},{7,11,14},{10,14,17}},
  MINIMAL={{0,3,7},{0,3,7},{0,3,7},{-2,1,5}},
  MELODIC={{0,4,7},{9,12,16},{5,9,12},{7,11,14}},
  SPEED={{0,3,7},{5,8,12},{10,14,17},{7,10,14}},
  BASSLINE={{0,3,7},{7,10,14},{5,8,12},{10,14,17}},
  HARDSTYLE={{0,4,7},{0,4,7},{5,9,12},{7,11,14}}
}

local chord_styles = {
  HOUSE={"block","stab","offbeat"},
  FUNKY={"stab","up","offbeat"},
  DIRTY={"stab","strum","block"},
  TECHNO={"stab"},
  GARAGE4={"offbeat","stab","up"},
  TWO_STEP={"offbeat","updown","stab"},
  BREAKS={"stab","strum"},
  DUBSTEP={"stab","block"},
  DEEP={"block","offbeat"},
  ACID={"stab"},
  TRANCE={"up","updown"},
  PROG={"block","offbeat"},
  JUNGLE={"stab"},
  DNB={"stab","block"},
  LIQUID={"up","strum"},
  HARDTECHNO={"stab"},
  ELECTRO={"offbeat","stab"},
  JUKE={"stab","offbeat"},
  AFRO={"block","up"},
  MINIMAL={"stab"},
  MELODIC={"up","updown"},
  SPEED={"offbeat","stab"},
  BASSLINE={"offbeat","stab","up"},
  HARDSTYLE={"block","stab"}
}

local function choose(t)
  return t[math.random(#t)]
end

-- ──────────────────────────────────────────────
-- NTS-1 motif helpers
-- ──────────────────────────────────────────────

local function nts1_lcg(seed)
  return (math.max(1, seed or 1) * 1103515245 + 12345) % NTS1_LCG_MOD
end

local function nts1_copy_list(t)
  local out = {}
  for i, v in ipairs(t or {}) do out[i] = v end
  return out
end

local function nts1_collect_scale(genre)
  local prog = chord_progs[genre] or chord_progs.HOUSE
  local scale = {}
  local seen = {}
  for _, triad in ipairs(prog) do
    for _, interval in ipairs(triad) do
      local pc = interval % 12
      if not seen[pc] then
        seen[pc] = true
        table.insert(scale, pc)
      end
    end
  end
  table.sort(scale)
  if #scale == 0 then scale = {0, 3, 7} end
  return scale
end

local function nts1_snap_to_pcs(note, root, pcs, min_note, max_note)
  if #pcs == 0 then return clamp(note, min_note, max_note) end
  local best = nil
  local best_dist = 999
  for oct = -2, 2 do
    for _, pc in ipairs(pcs) do
      local cand = root + pc + (12 * oct)
      while cand < min_note do cand = cand + 12 end
      while cand > max_note do cand = cand - 12 end
      local d = math.abs(cand - note)
      if d < best_dist then
        best = cand
        best_dist = d
      end
    end
  end
  return clamp(best or note, min_note, max_note)
end

-- Build a short motif from a deck's genre/root/seed.
-- Every note is quantized to the deck scale so phrases remain harmonically safe.
local function make_nts1_motif(genre, root, variation_seed, min_note, max_note)
  local scale = nts1_collect_scale(genre)
  local seed = math.max(1, variation_seed or 1)
  local motif = {}
  for i = 1, 4 do
    seed = nts1_lcg(seed + i * 17)
    local pc = scale[(seed % #scale) + 1]
    local octave = ((seed // NTS1_OCTAVE_DIVISOR) % 2) + 1
    local note = root + pc + octave * 12
    motif[i] = nts1_snap_to_pcs(note, root, scale, min_note or 48, max_note or 84)
  end
  if #motif > 1 and motif[#motif] == motif[1] then
    motif[#motif] = nts1_snap_to_pcs(motif[#motif] + 2, root, scale, min_note or 48, max_note or 84)
  end
  return motif
end

local function make_nts1_identity(deck)
  local seed = math.max(1, deck.variation_seed or 1)
  local scale = nts1_collect_scale(deck.genre)
  -- reg = register bias (in 3-semitone steps), density = stylistic density scalar,
  -- pattern = bar-relative trigger offsets (0-15 ticks), length = note lengths (ticks).
  local genre_profile = {
    TECHNO={reg=-3,density=0.55,pattern={0,8},length={8,6,8,6}},
    DUBSTEP={reg=-4,density=0.45,pattern={0,10},length={10,6,9,6}},
    TRANCE={reg=2,density=0.82,pattern={0,4,8,12},length={4,4,4,4}},
    LIQUID={reg=1,density=0.72,pattern={0,6,12},length={5,5,6,6}},
    JUNGLE={reg=1,density=0.78,pattern={0,3,7,11,14},length={3,3,4,4}},
    DNB={reg=1,density=0.80,pattern={0,3,7,10,13},length={3,4,3,4}},
    DEEP={reg=-1,density=0.52,pattern={0,8},length={10,8,10,8}},
    MINIMAL={reg=-2,density=0.35,pattern={0},length={12,10,10,12}},
    MELODIC={reg=2,density=0.76,pattern={0,4,9,12},length={4,5,4,6}},
    HARDSTYLE={reg=0,density=0.70,pattern={0,4,8,12},length={4,4,4,4}}
  }
  local prof = genre_profile[deck.genre] or {reg=0,density=0.65}
  -- Register param uses 3-semitone steps (minor-third moves) for noticeable
  -- shifts without forcing abrupt octave jumps.
  local register_min = 48 + (nts1_register + prof.reg) * 3
  local register_max = 76 + (nts1_register + prof.reg) * 3
  local mutation_choices = {4, 8, 16}
  seed = nts1_lcg(seed)
  local mutation_bars = mutation_choices[(seed % #mutation_choices) + 1]
  local pattern_pool = {
    {0, 8},
    {0, 6, 12},
    {0, 4, 8, 12},
    {0, 3, 7, 10, 14}
  }
  local length_pool = {
    {6, 5, 5, 7},
    {4, 4, 6, 6},
    {5, 3, 4, 7}
  }
  local rhythm_seed = nts1_lcg(seed + 29)
  local rhythm_pattern = nts1_copy_list(prof.pattern or pattern_pool[(rhythm_seed % #pattern_pool) + 1])
  local length_seed = nts1_lcg(seed + 37)
  local note_lengths = nts1_copy_list(prof.length or length_pool[(length_seed % #length_pool) + 1])

  local timbre_scenes = {
    {osc_type=0, fx_type=0, cutoff_base=84, cutoff_span=22,
      resonance_base=48, resonance_span=16, shape_base=40, shape_span=26, reverb_base=26, reverb_span=24},
    {osc_type=1, fx_type=1, cutoff_base=70, cutoff_span=30,
      resonance_base=56, resonance_span=20, shape_base=58, shape_span=18, reverb_base=20, reverb_span=18},
    {osc_type=2, fx_type=2, cutoff_base=62, cutoff_span=36,
      resonance_base=62, resonance_span=24, shape_base=52, shape_span=28, reverb_base=14, reverb_span=18}
  }
  seed = nts1_lcg(seed + 41)
  local scene = timbre_scenes[(seed % #timbre_scenes) + 1]

  return {
    root = deck.root,
    scale = scale,
    octave_range = {register_min, register_max},
    base_motif = make_nts1_motif(deck.genre, deck.root, seed, register_min, register_max),
    rhythmic_pattern = rhythm_pattern,
    note_lengths = note_lengths,
    density = clamp(nts1_motif_density * (prof.density or 1), 0.15, 1.0),
    preferred_register = nts1_register + (prof.reg or 0),
    timbre = {
      osc_type = scene.osc_type,
      fx_type = scene.fx_type,
      cutoff_base = scene.cutoff_base,
      cutoff_span = scene.cutoff_span,
      resonance_base = scene.resonance_base,
      resonance_span = scene.resonance_span,
      shape_base = scene.shape_base,
      shape_span = scene.shape_span,
      reverb_base = scene.reverb_base,
      reverb_span = scene.reverb_span
    },
    mutation_bars = mutation_bars,
    variation_seed = seed
  }
end

local NTS1_CC = {
  OSC_TYPE = 14,
  OSC_SHAPE = 19,
  FILTER_CUTOFF = 43,
  FILTER_RESONANCE = 44,
  AMP_ATTACK = 16,
  AMP_RELEASE = 72,
  FX_TYPE = 88,
  FX_DEPTH = 91
}

local function nts1_send_cc(cc, value, force)
  if not nts1_midi_out or not nts1_cc_enabled then return end
  local v = clamp(math.floor(value), 0, 127)
  local prev = nts1_cc_cache[cc]
  local last_tick_sent = nts1_cc_last_tick[cc]
  -- Ignore tiny deltas and rate-limit CC updates per control lane.
  local rate_limited = last_tick_sent and (tick - last_tick_sent) < 2
  if (not force) and ((prev and math.abs(prev - v) < 2) or rate_limited) then return end
  nts1_midi_out:cc(cc, v, nts1_ch)
  nts1_cc_cache[cc] = v
  nts1_cc_last_tick[cc] = tick
end

local function nts1_apply_scene(deck, sec, b, force)
  if not nts1_cc_enabled then return end
  if not deck.nts1_identity then return end
  local timbre = deck.nts1_identity.timbre
  if not timbre then return end
  local sec_phase = (b - 1) % NTS1_SECTION_BARS
  local phase = sec_phase / NTS1_SECTION_PHASE_DENOM
  if sec == "BREAK" then phase = phase * 0.3 end
  if sec == "BUILD" then phase = clamp(phase + 0.35, 0, 1) end
  if sec == "DROP" then phase = 1 end
  local cutoff = timbre.cutoff_base + timbre.cutoff_span * phase
  local resonance = timbre.resonance_base + timbre.resonance_span * phase
  local shape = timbre.shape_base + timbre.shape_span * phase
  local fx_depth = timbre.reverb_base + timbre.reverb_span * phase
  nts1_send_cc(NTS1_CC.OSC_TYPE, timbre.osc_type * 40, force)
  nts1_send_cc(NTS1_CC.FX_TYPE, timbre.fx_type * 40, force)
  nts1_send_cc(NTS1_CC.FILTER_CUTOFF, cutoff, force)
  nts1_send_cc(NTS1_CC.FILTER_RESONANCE, resonance, force)
  nts1_send_cc(NTS1_CC.OSC_SHAPE, shape, force)
  nts1_send_cc(NTS1_CC.FX_DEPTH, fx_depth, force)
  nts1_send_cc(NTS1_CC.AMP_ATTACK, (sec == "INTRO" or sec == "BREAK") and 60 or 28, force)
  nts1_send_cc(NTS1_CC.AMP_RELEASE, (sec == "BREAK" or sec == "MIX") and 86 or 56, force)
end

nts1_reset_cc_state = function()
  nts1_cc_cache = {}
  nts1_cc_last_tick = {}
end

local function nts1_mutate_motif(deck, sec, b)
  if not deck.nts1_identity then return end
  local identity = deck.nts1_identity
  local motif = nts1_copy_list(deck.nts1_motif or identity.base_motif)
  if #motif == 0 then return end

  local mut = clamp(nts1_variation_amount, 0, 1)
  if sec == "BUILD" then mut = clamp(mut + 0.20, 0, 1) end
  if sec == "DROP" then mut = clamp(mut + 0.10, 0, 1) end
  if sec == "BREAK" then mut = clamp(mut - 0.18, 0, 0.5) end
  if mut <= 0.02 then return end

  local seed = nts1_lcg(identity.variation_seed + b * 53)
  local do_mut = ((seed % 1000) / 1000) < mut
  if not do_mut then return end

  local scale = identity.scale
  local prog = chord_progs[deck.genre] or chord_progs.HOUSE
  local triad = prog[(math.floor((b - 1) / 2) % #prog) + 1]
  local chord_pcs = {}
  for _, interval in ipairs(triad) do
    table.insert(chord_pcs, interval % 12)
  end

  seed = nts1_lcg(seed + NTS1_MUTATION_SEED_OFFSET)
  local slot = (seed % #motif) + 1
  local op = (seed % NTS1_MUTATION_OP_COUNT) + 1
  local min_note = identity.octave_range[1]
  local max_note = identity.octave_range[2]

  if op == 1 then
    -- 1) transpose a motif note by a scale step
    motif[slot] = nts1_snap_to_pcs(motif[slot] + ((seed % 2 == 0) and 2 or -2), deck.root, scale, min_note, max_note)
  elseif op == 2 and #motif > 2 then
    -- 2) remove one motif note
    table.remove(motif, slot)
  elseif op == 3 and #motif < 6 then
    -- 3) add one note in register and chord context
    table.insert(motif, slot, nts1_snap_to_pcs(motif[slot] + 12, deck.root, chord_pcs, min_note, max_note))
  elseif op == 4 then
    -- 4) change final note to a nearby chord tone
    local delta4 = (seed % 2 == 0) and 5 or -5
    motif[#motif] = nts1_snap_to_pcs(motif[#motif] + delta4, deck.root, chord_pcs, min_note, max_note)
  elseif op == 5 then
    -- 5) octave-shift one note
    motif[slot] = nts1_snap_to_pcs(motif[slot] + ((seed % 2 == 0) and 12 or -12), deck.root, scale, min_note, max_note)
  elseif op == 6 then
    -- 6) shorten or extend a selected note length
    local len_idx = ((slot - 1) % #identity.note_lengths) + 1
    local t = identity.note_lengths[len_idx]
    identity.note_lengths[len_idx] = clamp(t + ((seed % 2 == 0) and 1 or -1), 2, 12)
  else
    -- 7) increase/reduce rhythmic density (call/response style simplification/extension)
    local rp = identity.rhythmic_pattern
    if #rp == 0 then
      rp[1] = 0
    end
    -- Intentionally mutates the per-deck identity so rhythmic evolution carries
    -- across subsequent phrase boundaries instead of resetting each bar.
    -- At low mutation settings prefer simplification; at higher settings bias
    -- toward extension so BUILD/DROP sections can intensify over time.
    if #rp > NTS1_RHYTHM_MIN_NOTES and mut < NTS1_RHYTHM_REDUCE_MUT_MAX then
      table.remove(rp, #rp)
    elseif #rp < NTS1_RHYTHM_MAX_NOTES then
      local new_offset = (rp[#rp] or NTS1_RHYTHM_APPEND_START) + NTS1_RHYTHM_APPEND_STEP
      table.insert(rp, clamp(new_offset, 0, NTS1_RHYTHM_MAX_OFFSET))
    end
  end
  deck.nts1_motif = motif
end

-- ──────────────────────────────────────────────
-- MPX8 helpers
-- ──────────────────────────────────────────────

-- Send a one-shot trigger to the MPX8 (note_on immediately followed by note_off).
-- The sampler ignores note duration; this purely signals the trigger.
local function mpx8_trigger(pad_idx, vel)
  if not mpx8_midi_out then return end
  local note = mpx8_pads[pad_idx]
  if not note then return end
  mpx8_midi_out:note_on(note, vel, mpx8_ch)
  mpx8_midi_out:note_off(note, 0, mpx8_ch)
end

-- Per-genre kick velocity (default 110). Only genres deviating from the default are listed.
-- Harder/darker styles push higher; broken-beat styles push slightly lower.
local kick_vel = {
  -- original genres
  TECHNO=122, DUBSTEP=120,
  -- new genres
  HARDTECHNO=124, HARDSTYLE=125, DNB=118, JUNGLE=118
}
-- Per-genre snare velocity (default 100). Only genres deviating from the default are listed.
local snare_vel = {
  -- original genres
  DUBSTEP=122, BREAKS=122,
  -- new genres
  DNB=122, JUNGLE=122, HARDTECHNO=122, HARDSTYLE=122
}
-- Per-genre closed hi-hat velocity (default 70). Only genres deviating from the default are listed.
local hat_vel = {
  -- original genres
  TECHNO=88,
  -- new genres
  HARDTECHNO=85, TRANCE=85
}

-- Per-genre bass note trigger probability (default 0.55).
-- Only genres deviating from the default are listed.
local bass_prob = {
  -- original genres
  DUBSTEP=0.90, TECHNO=0.65,
  -- new genres
  DEEP=0.40, MINIMAL=0.35, PROG=0.45,
  ACID=0.75, TRANCE=0.70, DNB=0.85, BASSLINE=0.90, JUKE=0.85
}

-- Per-genre block-chord sustain duration in ticks (default 10).
-- Only genres deviating from the default are listed.
local block_chord_dur = {
  -- original genres
  DUBSTEP=4,
  -- new genres: ambient/melodic styles hold chords longer
  DEEP=14, MINIMAL=14, PROG=12, MELODIC=12, TRANCE=12
}

-- Per-genre bass note octave offset (default 0) and note length in ticks (default 1).
-- Only genres deviating from the default are listed.
local bass_octave = { DUBSTEP=-12, DNB=-12 }  -- sub-bass register
local bass_len    = { DUBSTEP=3 }             -- DUBSTEP uses long, sustained bass notes

-- Genres that share the default house-style chord timing (every 8 steps, at step 1 and 9).
-- Original genres: HOUSE, FUNKY, DIRTY, GARAGE4
-- New genres:      DEEP, ACID, DNB, LIQUID, ELECTRO, AFRO, MELODIC, HARDSTYLE, JUNGLE
chord_allow_house = {
  HOUSE=true, FUNKY=true, DIRTY=true, GARAGE4=true,
  DEEP=true, ACID=true, DNB=true, LIQUID=true,
  ELECTRO=true, AFRO=true, MELODIC=true, HARDSTYLE=true, JUNGLE=true
}

local function play_drums(sec, s, b, mix_fades, deck)
  local gn = deck.genre
  local p = drum_patterns[gn] or drum_patterns.HOUSE
  local d = density_for_section(sec)
  -- Use grid-editable drum_steps for the active deck; genre pattern for incoming deck during mix
  local use_grid = (deck == current_deck())

  local kick_amount  = mix_fades and mix_fades.kick  or 1
  local drums_amount = mix_fades and mix_fades.drums or 1

  local kick_prob = 1.0
  if sec == "INTRO" then kick_prob = 0.75 end
  if sec == "BREAK" then kick_prob = 0.45 end
  kick_prob = kick_prob * kick_amount

  -- Snare and clap always fire when pattern calls for them (base prob 1.0);
  -- scale by drums_amount for a consistent probabilistic fade with kick.
  local snare_prob = 1.0 * drums_amount
  local clap_prob  = 1.0 * drums_amount

  -- Kick
  local kick_hit
  if use_grid then kick_hit = drum_steps[1][s] else kick_hit = hit(p.kick, s) end
  if kick_hit and math.random() < kick_prob then
    t8_note(KICK, kick_vel[gn] or 110, drum_ch, 1)
  end

  -- Snare
  local snare_hit
  if use_grid then
    snare_hit = drum_steps[2][s]
  else
    snare_hit = p.snare and hit(p.snare, s)
  end
  if snare_hit and sec ~= "INTRO" and math.random() < snare_prob then
    t8_note(SNARE, snare_vel[gn] or 100, drum_ch, 1)
  end

  -- Clap (always generative; not on grid)
  if p.clap and hit(p.clap, s) and sec ~= "INTRO" and math.random() < clap_prob then
    if gn ~= "TECHNO" then
      t8_note(CLAP, 110, drum_ch, 1)
    end
  end

  -- Tom (always generative)
  if p.tom and hit(p.tom, s) and math.random() < 0.45 * drums_amount then
    t8_note(TOM, 85, drum_ch, 1)
  end

  -- Closed hi-hat
  local chh_hit
  if use_grid then
    chh_hit = drum_steps[4][s]
  else
    chh_hit = p.hats and hit(p.hats, s)
  end
  if chh_hit and math.random() < (0.45 + d * 0.40) * drums_amount then
    t8_note(CHH, hat_vel[gn] or 70, drum_ch, 1)
  end

  -- Open hi-hat
  if use_grid then
    if drum_steps[3][s] and math.random() < drums_amount then
      t8_note(OHH, 70, drum_ch, 1)
    end
  elseif (s == 7 or s == 15) and sec ~= "INTRO" and math.random() < d * 0.35 * drums_amount then
    t8_note(OHH, 70, drum_ch, 1)
  end

  -- Bar fills (always generative)
  if b % 16 == 0 and s >= 13 and math.random() < drums_amount then
    if s == 13 then t8_note(SNARE, 95, drum_ch, 1) end
    if s == 14 then t8_note(TOM, 90, drum_ch, 1) end
    if s == 15 then t8_note(SNARE, 105, drum_ch, 1) end
    if s == 16 then t8_note(CLAP, 115, drum_ch, 1) end
  end
end

local function play_bass(sec, s, deck, mix_fades)
  if sec == "INTRO" then return end
  if sec == "BREAK" and math.random() < 0.55 then return end
  local bass_amount = mix_fades and mix_fades.bass or 1
  if math.random() >= bass_amount then return end

  local pat = bass_patterns[deck.genre] or bass_patterns.HOUSE
  local degree = pat[((s-1)%16)+1]
  if degree == nil then return end

  local prob = bass_prob[deck.genre] or 0.55

  if degree ~= 0 or math.random() < prob then
    local octave = bass_octave[deck.genre] or 0
    local len    = bass_len[deck.genre]    or 1
    t8_note(deck.root + octave + degree, sec=="DROP" and 112 or 94, bass_ch, len)
  end
end

local function play_chords(sec, s, deck, b, mix_fades)
  if sec == "INTRO" then return end
  local melody_amount = mix_fades and mix_fades.melody or 1
  if math.random() >= melody_amount then return end

  -- Determine whether this step is allowed to trigger.
  -- For the active deck: use the grid-editable j6_steps pattern.
  -- For the incoming deck during mixing: fall back to genre timing rules.
  local allow = false
  if deck == current_deck() then
    allow = j6_steps[s]
  else
    local gn = deck.genre
    if chord_allow_house[gn] then
      allow = (s==1 or s==9)
    elseif gn=="TWO_STEP" then
      allow = (s==4 or s==10)
    elseif gn=="BREAKS" then
      allow = (s==1 or s==11)
    elseif gn=="TECHNO" then
      allow = (s==1 and b%4==1)
    elseif gn=="DUBSTEP" then
      allow = (s==1 or s==9)
    elseif gn=="TRANCE" then
      allow = (s==1 and b%2==1)
    elseif gn=="PROG" or gn=="HARDTECHNO" then
      allow = (s==1 and b%4==1)
    elseif gn=="JUKE" then
      allow = (s==1 or s==5 or s==9 or s==13)
    elseif gn=="MINIMAL" then
      allow = (s==1 and b%8==1)
    elseif gn=="SPEED" or gn=="BASSLINE" then
      allow = (s==4 or s==12)
    end
  end
  if not allow then return end
  if sec == "BREAK" and math.random() < 0.45 then return end

  local gn = deck.genre
  local prog = chord_progs[gn] or chord_progs.HOUSE
  local triad = prog[(math.floor((b-1)/2) % #prog) + 1]
  local base = deck.root + 12
  local notes = {base+triad[1], base+triad[2], base+triad[3]}
  local style = choose(chord_styles[gn] or {"block"})
  local vel = sec=="DROP" and 98 or 78

  if style == "block" then
    local dur = block_chord_dur[gn] or 10
    for _,n in ipairs(notes) do
      chord_note(n, vel, dur)
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
  grid_j6_level = 8
end

local function play_norns_instrument(sec, s, deck, b, mix_fades)
  if not norns_inst_enabled then return end
  if sec == "INTRO" or sec == "BREAK" then return end
  local melody_amount = mix_fades and mix_fades.melody or 1
  if math.random() >= melody_amount then return end
  if s ~= 1 then return end

  local gn = deck.genre
  local preset = norns_presets[deck.norns_preset or norns_preset_idx]
  -- If no preset could be found, no notes are sent.
  if not preset then return end
  local is_pad = (preset.name == "pad" or preset.name == "strings")
  if is_pad and b % 2 ~= 1 then return end

  local ok, err = pcall(function()
    engine.release(preset.release)
    engine.cutoff(preset.cutoff)
    engine.gain(preset.gain)
    engine.pw(preset.pw)
    engine.amp(norns_inst_vol)

    local prog = chord_progs[gn] or chord_progs.HOUSE
    local triad = prog[(math.floor((b - 1) / 2) % #prog) + 1]
    local base = deck.root + 24  -- +24 semitones = two octaves above deck root

    for _, interval in ipairs(triad) do
      engine.hz(note_to_hz(base + interval))
    end
  end)
  if not ok then
    print("Endless DJ: norns instrument error: " .. tostring(err))
    return
  end
end

-- ──────────────────────────────────────────────
-- NTS-1 melodic voice
-- ──────────────────────────────────────────────

-- Play the deck's NTS-1 motif at bar/step boundaries.
-- Each deck keeps a stable motif/rhythm/timbre identity, then applies
-- controlled phrase-boundary mutations so the part evolves without chaos.
-- During mixes, density follows melody-group fade and outgoing/incoming parts
-- are simplified/introduced gradually.
local function play_nts1(sec, s, deck, b, mix_fades)
  if not nts1_enabled then return end
  if not nts1_midi_out then return end

  -- Gate by trigger pattern: active deck uses grid-editable nts1_steps;
  -- incoming deck during mixing uses bar-start rule (step 1 only).
  if deck == current_deck() then
    if not nts1_steps[s] then return end
  else
    if s ~= 1 then return end
  end

  if not deck.nts1_identity then
    deck.nts1_identity = make_nts1_identity(deck)
    deck.nts1_motif = nts1_copy_list(deck.nts1_identity.base_motif)
    deck.nts1_motif_mutation_bars = deck.nts1_identity.mutation_bars
    deck.nts1_motif_turn = 1
    nts1_apply_scene(deck, sec, b, true)
  else
    nts1_apply_scene(deck, sec, b, false)
  end

  if not deck.nts1_motif or #deck.nts1_motif == 0 then return end

  local identity = deck.nts1_identity
  local mut_bars = deck.nts1_motif_mutation_bars or 8
  local phrase_idx = math.floor((b - 1) / mut_bars)
  if deck.nts1_phrase ~= phrase_idx then
    if deck.nts1_phrase == nil then
      deck.nts1_motif = nts1_copy_list(identity.base_motif)
    else
      nts1_mutate_motif(deck, sec, b)
    end
    deck.nts1_phrase = phrase_idx
  end

  local melody_amount = mix_fades and mix_fades.melody or 1
  local sec_density = identity.density
  if sec == "INTRO" then sec_density = sec_density * 0.20 end
  if sec == "GROOVE" then sec_density = sec_density * 0.55 end
  if sec == "MAIN" then sec_density = sec_density * 0.75 end
  if sec == "BREAK" then sec_density = sec_density * 0.15 end
  if sec == "BUILD" then sec_density = sec_density * 0.95 end
  if sec == "DROP" then sec_density = clamp(sec_density * 1.15, 0, 1) end
  -- In MIX: outgoing/current deck is simplified, incoming deck gets stronger.
  if sec == "MIX" then
    sec_density = sec_density * (deck == current_deck() and NTS1_MIX_OUTGOING_DENSITY or NTS1_MIX_INCOMING_DENSITY)
  end
  sec_density = sec_density * melody_amount

  local seed = nts1_lcg((identity.variation_seed or 1) + b * 19)
  if ((seed % 1000) / 1000) > sec_density then return end

  local motif = deck.nts1_motif
  local rhythm = identity.rhythmic_pattern
  if #rhythm == 0 then rhythm = {0} end
  local note_lengths = identity.note_lengths
  local register_bump = 0
  if sec == "BUILD" then register_bump = 12 end
  if sec == "DROP" then register_bump = 7 end
  if sec == "BREAK" then register_bump = -12 end

  local num_triggers = (sec == "MIX" and deck == current_deck()) and 1 or #rhythm
  for i = 1, num_triggers do
    local offset = rhythm[((i - 1) % #rhythm) + 1]
    local motif_idx = ((deck.nts1_motif_turn + i - NTS1_MOTIF_INDEX_BASE_OFFSET) % #motif) + 1
    local note = motif[motif_idx] + register_bump
    note = clamp(note, identity.octave_range[1], identity.octave_range[2] + 12)
    local note_len = note_lengths[((motif_idx - 1) % #note_lengths) + 1] or 6
    local next_offset = nil
    if i < num_triggers then
      next_offset = rhythm[((i) % #rhythm) + 1]
    end
    if next_offset and next_offset > offset then
      note_len = math.min(note_len, math.max(1, next_offset - offset - 1))
    end
    note_len = math.min(note_len, math.max(1, 16 - offset))
    local vel = (sec == "DROP") and 92 or ((sec == "BREAK") and 58 or 80)
    if offset == 0 then
      note_on_to(nts1_midi_out, note, vel, nts1_ch, note_len)
    else
      note_delayed(nts1_midi_out, note, vel, nts1_ch, offset, note_len)
    end
  end

  deck.nts1_motif_turn = ((deck.nts1_motif_turn + #rhythm - 1) % #motif) + 1
  grid_nts1_level = 4
end

-- ──────────────────────────────────────────────
-- MPX8 sample layer
-- ──────────────────────────────────────────────

-- Trigger MPX8 pads at genre- and section-appropriate bar/phrase boundaries.
-- Percussion and fills follow the "other drums" phase (mix_fades.drums).
-- One-shot transition samples (riser, impact, drop accent) fire at most once
-- per deck so they are not duplicated when both virtual decks are playing.
local function play_mpx8(sec, s, deck, b, mix_fades)
  if not mpx8_enabled then return end
  if not mpx8_midi_out then return end
  -- MPX8 is a bar-level device; only act at the start of each bar
  if s ~= 1 then return end

  -- ── One-shot transition samples ────────────────
  -- Riser fires once at the first bar of BUILD
  if sec == "BUILD" and b == 81 and not deck.mpx8_riser_fired then
    deck.mpx8_riser_fired = true
    mpx8_trigger(6, 100)  -- pad 6: riser
  end

  -- Impact and drop accent fire once at the first bar of DROP
  if sec == "DROP" and b == 97 then
    if not deck.mpx8_impact_fired then
      deck.mpx8_impact_fired = true
      mpx8_trigger(5, 110)  -- pad 5: impact
    end
    if not deck.mpx8_drop_accent_fired then
      deck.mpx8_drop_accent_fired = true
      mpx8_trigger(8, 110)  -- pad 8: drop accent
    end
  end

  -- ── Recurring fills, stabs, and accents ────────
  -- These are gated by the "other drums" mix phase during transitions.
  if sec == "INTRO" or sec == "GROOVE" or sec == "BREAK" or sec == "MIX" then return end

  local drums_amount = mix_fades and mix_fades.drums or 1
  if math.random() >= drums_amount then return end

  -- Derive a per-deck accent offset (0-3) from the variation_seed so accents
  -- land on different bar positions for different tracks.
  local accent_offset = (deck.variation_seed or 1) % 4

  -- Pad 1: percussion accent at 4-bar boundaries (offset by deck seed)
  if (b + accent_offset) % 4 == 0 then
    local vel = (sec == "DROP") and 100 or 82
    mpx8_trigger(1, vel)
  end
  -- Pad 2: alternate percussion at 8-bar boundaries in DROP only
  if sec == "DROP" and (b + accent_offset) % 8 == 0 then
    mpx8_trigger(2, 90)
  end

  -- Pad 3: short fill at every 4-bar boundary
  if b % 4 == 0 then
    local vel = (sec == "DROP") and 102 or 85
    mpx8_trigger(3, vel)
  end
  -- Pad 4: long fill at every 8-bar boundary
  if b % 8 == 0 then
    local vel = (sec == "DROP") and 108 or 90
    mpx8_trigger(4, vel)
  end

  -- Pad 7: vocal/FX stab at the start of every 8-bar phrase in MAIN/DROP
  if (sec == "MAIN" or sec == "DROP") and b % 8 == 1 then
    local vel = (sec == "DROP") and 100 or 80
    mpx8_trigger(7, vel)
  end
end

local function play_deck(deck, b, s, mix_fades)
  local sec = section_for_bar(b)
  play_drums(sec, s, b, mix_fades, deck)
  play_bass(sec, s, deck, mix_fades)
  play_chords(sec, s, deck, b, mix_fades)
  play_norns_instrument(sec, s, deck, b, mix_fades)
  play_nts1(sec, s, deck, b, mix_fades)
  play_mpx8(sec, s, deck, b, mix_fades)
end

local function start_mix_if_needed()
  if current_bar == MIX_START_BAR and step == 1 and not mixing then
    mixing = true
    next_bar = 1
    next_step = 1
    j6_program_change(next_deck().pc)
  end
end

local function update_xfade()
  if manual_xfade then return end

  if mixing then
    local pos = ((current_bar - MIX_START_BAR) * 16 + (step - 1)) / (MIX_BARS * 16)
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

  current_bar = MIX_BARS + 1
  step = 1
  next_bar = nil
  next_step = 1
  mixing = false
  -- Do NOT call quiet_notes() here.  Sending 4096 note-off messages (128
  -- notes × 16 channels × 2 MIDI devices) in a tight Lua loop blocks the
  -- metro callback thread, causing several bars of silence followed by a
  -- rapid "catch-up" burst — exactly the symptom reported in issue #24.
  -- Every note_on is already paired with a scheduled note_off in the
  -- notes_off queue (via note_on_to), so no hanging notes can occur.
  -- The MX-1 effect depth is reset to 0 automatically on the next tick by
  -- update_mx1_fx() once mixing is false.
  nts1_reset_cc_state()
  if nts1_enabled and nts1_midi_out then
    local deck = current_deck()
    if deck and not deck.nts1_identity then
      deck.nts1_identity = make_nts1_identity(deck)
      deck.nts1_motif = nts1_copy_list(deck.nts1_identity.base_motif)
      deck.nts1_motif_mutation_bars = deck.nts1_identity.mutation_bars
      deck.nts1_motif_turn = 1
    end
    if deck then
      nts1_apply_scene(deck, section_for_bar(current_bar), current_bar, true)
    end
  end
  grid_load_pattern(current_deck().genre)
  grid_redraw(step)
end

local metro_clock

local function clock_tick()
  if not playing then return end

  service_note_offs()
  service_pending_notes()
  start_mix_if_needed()
  update_xfade()
  update_mx1_fx()
  -- Decay synth activity levels and redraw the grid once for both halves
  grid_nts1_level = math.max(0, grid_nts1_level - 1)
  grid_j6_level   = math.max(0, grid_j6_level   - 1)
  grid_redraw(step)

  -- Wrap musical playback in pcall so any unexpected engine or MIDI error
  -- (e.g. the norns instrument first firing at bar 17 where the GROOVE
  -- section begins) cannot stop the metro clock.
  local play_ok, play_err = pcall(function()
    if mixing then
      -- Position within the 32-bar mix (0.0 = start, 1.0 = end).
      -- The mix is divided into four 8-bar phases, each responsible for
      -- cross-fading one group of components:
      --   Phase 1 (0.00-0.25): kick drum
      --   Phase 2 (0.25-0.50): bass
      --   Phase 3 (0.50-0.75): other drums (snare, hats, clap, tom)
      --   Phase 4 (0.75-1.00): chords / melody
      local pos = ((current_bar - MIX_START_BAR) * 16 + (step - 1)) / (MIX_BARS * 16)
      pos = clamp(pos, 0, 1)

      -- Fade amount for each phase: 1→0 for outgoing, 0→1 for incoming.
      -- Phase index is 0-based so the formula maps: phase 1→0, 2→1, 3→2, 4→3.
      local function phase_out(p) return clamp(1 - (pos - p * 0.25) * 4, 0, 1) end
      local function phase_in(p)  return clamp(    (pos - p * 0.25) * 4, 0, 1) end

      local out_fades = {
        kick   = phase_out(0),
        bass   = phase_out(1),
        drums  = phase_out(2),
        melody = phase_out(3),
      }
      local in_fades = {
        kick   = phase_in(0),
        bass   = phase_in(1),
        drums  = phase_in(2),
        melody = phase_in(3),
      }

      play_deck(current_deck(), current_bar, step, out_fades)
      play_deck(next_deck(), next_bar, next_step, in_fades)
    else
      play_deck(current_deck(), current_bar, step, nil)
    end
  end)
  if not play_ok then
    print("Endless DJ: playback error: " .. tostring(play_err))
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
  -- NTS-1 and MPX8 are optional; connect using their default device slots.
  -- They send no MIDI until enabled in params.
  nts1_midi_out = midi.connect(nts1_mdev)
  mpx8_midi_out = midi.connect(mpx8_mdev)

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

  params:add_separator("grid_sep", "GRID")

  params:add_option("grid_kb_target", "keyboard target", {"nts1","j6","norns"}, kb_target)
  params:set_action("grid_kb_target", function(v)
    kb_all_notes_off()
    kb_target = v
  end)

  params:add_number("grid_kb_octave", "keyboard octave", -2, 4, kb_octave)
  params:set_action("grid_kb_octave", function(v)
    kb_all_notes_off()
    kb_octave = v
    grid_redraw(step)
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

  -- ── Korg NTS-1 ────────────────────────────────
  params:add_separator("nts1_sep", "KORG NTS-1")

  params:add_option("nts1_enabled", "nts1 enabled", {"off","on"}, 1)
  params:set_action("nts1_enabled", function(v)
    nts1_enabled = (v == 2)
    if nts1_midi_out then
      if not nts1_enabled then
        -- Clear any hanging notes when disabled
        for n=0,127 do nts1_midi_out:note_off(n, 0, nts1_ch) end
      else
        nts1_reset_cc_state()
      end
    end
  end)

  params:add_option("nts1_midi_device", "nts1 device", dev_names, nts1_mdev)
  params:set_action("nts1_midi_device", function(v)
    -- Clear hanging notes on old device before switching
    if nts1_midi_out then
      for n=0,127 do nts1_midi_out:note_off(n, 0, nts1_ch) end
    end
    nts1_mdev = v
    nts1_midi_out = midi.connect(nts1_mdev)
    nts1_reset_cc_state()
  end)

  params:add_number("nts1_ch", "nts1 channel", 1, 16, nts1_ch)
  params:set_action("nts1_ch", function(v)
    -- Clear hanging notes on old channel before switching
    if nts1_midi_out then
      for n=0,127 do nts1_midi_out:note_off(n, 0, nts1_ch) end
    end
    nts1_ch = v
    nts1_reset_cc_state()
  end)

  params:add_number("nts1_variation", "nts1 variation", 0, 100, math.floor(nts1_variation_amount * 100))
  params:set_action("nts1_variation", function(v)
    nts1_variation_amount = clamp(v / 100, 0, 1)
  end)

  params:add_number("nts1_motif_density", "nts1 motif density", 10, 100, math.floor(nts1_motif_density * 100))
  params:set_action("nts1_motif_density", function(v)
    nts1_motif_density = clamp(v / 100, 0.1, 1)
    nts1_reset_deck_identities()
  end)

  params:add_number("nts1_register", "nts1 register", -6, 6, nts1_register)
  params:set_action("nts1_register", function(v)
    nts1_register = v
    nts1_reset_deck_identities()
  end)

  params:add_option("nts1_cc_automation", "nts1 cc automation", {"off","on"}, nts1_cc_enabled and 2 or 1)
  params:set_action("nts1_cc_automation", function(v)
    nts1_cc_enabled = (v == 2)
    nts1_reset_cc_state()
  end)

  params:add_trigger("nts1_test", "nts1 test note")
  params:set_action("nts1_test", function()
    if nts1_midi_out then
      note_on_to(nts1_midi_out, 60, 80, nts1_ch, 16)
    end
  end)

  -- ── Akai MPX8 ─────────────────────────────────
  params:add_separator("mpx8_sep", "AKAI MPX8")

  params:add_option("mpx8_enabled", "mpx8 enabled", {"off","on"}, 1)
  params:set_action("mpx8_enabled", function(v)
    mpx8_enabled = (v == 2)
    if not mpx8_enabled and mpx8_midi_out then
      clear_scheduled_notes_for_device(mpx8_midi_out)
      for n=0,127 do mpx8_midi_out:note_off(n, 0, mpx8_ch) end
    end
  end)

  params:add_option("mpx8_midi_device", "mpx8 device", dev_names, mpx8_mdev)
  params:set_action("mpx8_midi_device", function(v)
    if mpx8_midi_out then
      clear_scheduled_notes_for_device(mpx8_midi_out)
      for n=0,127 do mpx8_midi_out:note_off(n, 0, mpx8_ch) end
    end
    mpx8_mdev = v
    mpx8_midi_out = midi.connect(mpx8_mdev)
  end)

  params:add_number("mpx8_ch", "mpx8 channel", 1, 16, mpx8_ch)
  params:set_action("mpx8_ch", function(v)
    if mpx8_midi_out then
      for n=0,127 do mpx8_midi_out:note_off(n, 0, mpx8_ch) end
    end
    mpx8_ch = v
  end)

  -- Configurable note numbers for the 8 pads
  local pad_labels = {
    "mpx8 pad1 perc accent",
    "mpx8 pad2 alt perc",
    "mpx8 pad3 short fill",
    "mpx8 pad4 long fill",
    "mpx8 pad5 impact",
    "mpx8 pad6 riser",
    "mpx8 pad7 vocal stab",
    "mpx8 pad8 drop accent",
  }
  for i = 1, 8 do
    -- Capture loop index in a local so each closure writes the correct pad slot
    -- (Lua closures capture variables by reference; without `pad_i` all eight
    -- closures would share the same `i` after the loop ends.)
    local pad_i = i
    params:add_number("mpx8_pad" .. i, pad_labels[i], 0, 127, mpx8_pads[i])
    params:set_action("mpx8_pad" .. i, function(v) mpx8_pads[pad_i] = v end)
  end

  for i = 1, 8 do
    local pad_i = i
    params:add_trigger("mpx8_test_pad" .. i, "test " .. pad_labels[i])
    params:set_action("mpx8_test_pad" .. i, function()
      if mpx8_enabled and mpx8_midi_out then
        mpx8_trigger(pad_i, 90)
      end
    end)
  end

  params:add_trigger("mpx8_test", "mpx8 test all pads")
  params:set_action("mpx8_test", function()
    if mpx8_enabled and mpx8_midi_out then
      -- Fire each pad in sequence with a 4-tick gap
      for i = 1, 8 do
        note_delayed(mpx8_midi_out, mpx8_pads[i], 90, mpx8_ch, (i - 1) * 4, 1)
      end
    end
  end)

  update_clock()
  grid_connect()
  redraw()
end

function cleanup()
  quiet_notes()
  kb_all_notes_off()
  grid_clear()
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
