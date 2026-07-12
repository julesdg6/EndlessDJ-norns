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

engine.name = "None"

local midi_out
local chord_midi_out
local mx1_midi_out

local mdev = 1
local chord_mdev = 1
local mx1_mdev = 1
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

local deck_a = {name="A-001", genre="HOUSE", active=true, angle=0, root=45, pc=0}
local deck_b = {name="B-002", genre="TWO_STEP", active=false, angle=0, root=50, pc=1}

local notes_off = {}
local notes_pending = {}

local KICK = 36
local SNARE = 38
local CLAP = 50
local TOM = 47
local CHH = 42
local OHH = 46

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
    pc = random_pc()
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
  local msg
  -- Keep this guard for compatibility with environments where midi.to_msg
  -- may not be present for realtime transport callbacks.
  if midi and midi.to_msg and data then
    msg = midi.to_msg(data)
  end

  -- Prefer decoded transport message types when available.
  -- Some devices/firmware revisions may only expose raw realtime status bytes.
  if msg and msg.type then
    apply_transport_message(msg.type)
  else
    local status = data and data[1]
    if status == MIDI_START then
      apply_transport_message("start")
    elseif status == MIDI_CONTINUE then
      apply_transport_message("continue")
    elseif status == MIDI_STOP then
      apply_transport_message("stop")
    end
  end
end

local function connect_mx1_midi()
  mx1_midi_out = midi.connect(mx1_mdev)
  if mx1_midi_out then
    mx1_midi_out.event = handle_mx1_transport
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

  local kick_prob = 1.0
  if sec == "INTRO" then kick_prob = 0.75 end
  if sec == "BREAK" then kick_prob = 0.45 end
  if mix_amount and mix_amount < 0.45 then kick_prob = 0.20 end

  if hit(p.kick, s) and math.random() < kick_prob then
    local vel = 110
    if g == "TECHNO" then vel = 122 end
    if g == "DUBSTEP" then vel = 120 end
    t8_note(KICK, vel, drum_ch, 1)
  end

  if p.snare and hit(p.snare, s) and sec ~= "INTRO" then
    local vel = 100
    if g == "DUBSTEP" or g == "BREAKS" then vel = 122 end
    t8_note(SNARE, vel, drum_ch, 1)
  end

  if p.clap and hit(p.clap, s) and sec ~= "INTRO" then
    if g ~= "TECHNO" then
      t8_note(CLAP, 110, drum_ch, 1)
    end
  end

  if p.tom and hit(p.tom, s) and math.random() < 0.45 then
    t8_note(TOM, 85, drum_ch, 1)
  end

  if p.hats and hit(p.hats, s) and math.random() < (0.45 + d * 0.40) then
    local vel = 70
    if g == "TECHNO" then vel = 88 end
    t8_note(CHH, vel, drum_ch, 1)
  end

  if (s == 7 or s == 15) and sec ~= "INTRO" and math.random() < d * 0.35 then
    t8_note(OHH, 70, drum_ch, 1)
  end

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

local function play_deck(deck, b, s, mix_amount)
  local sec = section_for_bar(b)
  play_drums(sec, s, b, mix_amount, deck)
  play_bass(sec, s, deck, mix_amount)
  play_chords(sec, s, deck, b, mix_amount)
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
end

local metro_clock

local function clock_tick()
  if not playing then return end

  service_note_offs()
  service_pending_notes()
  start_mix_if_needed()
  update_xfade()
  update_mx1_fx()

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

function init()
  math.randomseed(os.time())

  midi_out = midi.connect(mdev)
  chord_midi_out = midi.connect(chord_mdev)
  connect_mx1_midi()

  params:add_separator("endless_dj", "ENDLESS DJ")

  params:add_number("t8_midi_device", "t8 midi device", 1, 8, mdev)
  params:set_action("t8_midi_device", function(v)
    mdev = v
    midi_out = midi.connect(mdev)
  end)

  params:add_number("j6_midi_device", "j6 midi device", 1, 8, chord_mdev)
  params:set_action("j6_midi_device", function(v)
    chord_mdev = v
    chord_midi_out = midi.connect(chord_mdev)
  end)

  params:add_separator("mx1", "ROLAND AIRA MX-1")

  params:add_number("mx1_midi_device", "mx1 midi device", 1, 8, mx1_mdev)
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

  update_clock()
  redraw()
end

function cleanup()
  quiet_notes()
  if metro_clock then metro_clock:stop() end
end

function key(n,z)
  if z == 0 then return end

  if n == 2 then
    if playing then
      playing = false
      quiet_notes()
    else
      playing = true
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
  draw_deck(94, 28, 14, deck_b.angle, deck_b.active or (mixing and deck_b == next_deck()), "B", deck_b, true)

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
