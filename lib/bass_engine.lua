-- Deterministic genre-aware bass plans. Bass phrases are generated once per
-- record, then replayed without per-note randomness so their identity survives
-- arrangement changes and DJ transitions.
local M = {}


local VOICES = {
  HOUSE={"organ","analog","sub"}, FUNKY={"organ","analog","fm"},
  DIRTY={"reese","fm","wobble"}, TECHNO={"analog","sub","reese"},
  GARAGE4={"organ","sub","reese"}, TWO_STEP={"sub","reese","organ","fm"},
  BREAKS={"reese","analog","fm"}, DUBSTEP={"sub","reese","wobble"},
  DEEP={"sub","organ","analog"}, ACID={"303"},
  TRANCE={"analog","reese","303"}, PROG={"analog","sub","reese"},
  JUNGLE={"sub","reese"}, DNB={"reese","sub","fm"},
  LIQUID={"sub","reese","organ"}, HARDTECHNO={"reese","analog","303"},
  ELECTRO={"fm","analog","reese"}, JUKE={"sub","fm"},
  AFRO={"sub","organ","analog"}, MINIMAL={"sub","analog"},
  MELODIC={"analog","sub","reese"}, SPEED={"reese","organ","sub"},
  BASSLINE={"organ","reese","wobble","fm"}, HARDSTYLE={"analog","reese"},
}


local MODEL = {analog=0,sub=1,reese=2,organ=3,fm=4,wobble=5}
local VOICE_PROFILES = {
  analog={sub=0.28,cutoff=0.62,resonance=0.24,attack=0.03,release=0.34,
    glide=0.12,lfo_rate=0.16,lfo_depth=0.09,delay_send=0.08},
  sub={sub=0.08,cutoff=0.38,resonance=0.12,attack=0.04,release=0.48,
    glide=0.08,lfo_rate=0.08,lfo_depth=0.03,delay_send=0.01},
  reese={sub=0.12,cutoff=0.46,resonance=0.34,attack=0.02,release=0.48,
    glide=0.18,lfo_rate=0.12,lfo_depth=0.22,delay_send=0.04},
  organ={sub=0.02,cutoff=0.88,resonance=0.08,attack=0.01,release=0.22,
    glide=0.01,lfo_rate=0.06,lfo_depth=0.01,delay_send=0.02},
  fm={sub=0.04,cutoff=0.74,resonance=0.18,attack=0.01,release=0.30,
    glide=0.04,lfo_rate=0.20,lfo_depth=0.58,delay_send=0.04},
  wobble={sub=0.32,cutoff=0.36,resonance=0.58,attack=0.02,release=0.52,
    glide=0.10,lfo_rate=0.42,lfo_depth=0.82,delay_send=0.05},
}
local LOW = {DUBSTEP=-12,JUNGLE=-12,DNB=-12,LIQUID=-12,JUKE=-12,HARDSTYLE=-12}
