-- Shared deterministic generator fixtures. Off-device regression tests and the
-- physical Norns harness consume the same seeds, so a reported record can be
-- reconstructed exactly on either side.
local M = {}

M.genres = {
  "HOUSE", "FUNKY", "DIRTY", "TECHNO", "GARAGE4", "TWO_STEP",
  "BREAKS", "DUBSTEP", "DEEP", "ACID", "TRANCE", "PROG", "JUNGLE",
  "DNB", "LIQUID", "HARDTECHNO", "ELECTRO", "JUKE", "AFRO",
  "MINIMAL", "MELODIC", "SPEED", "BASSLINE", "HARDSTYLE",
}

-- These are the first stable Deck A seeds selecting each archetype. Keep them
-- explicit: changing identity selection must be reviewed as a fixture change.
local archetype_seeds = {6, 8, 1, 4}

M.golden = {}
M.listening = {}

function M.build(song_identity)
  M.golden = {}
  M.listening = {}
  for _, genre in ipairs(M.genres) do
    local archetypes = assert(song_identity.archetypes_for_genre(genre))
    M.golden[genre] = {}
    for index, archetype in ipairs(archetypes) do
      local fixture = {genre=genre, archetype=archetype, seed=archetype_seeds[index], deck="A"}
      M.golden[genre][archetype] = fixture
      M.listening[#M.listening + 1] = fixture
    end
  end
  return M
end

function M.all(song_identity)
  if #M.listening == 0 then M.build(song_identity) end
  return M.listening
end

function M.for_genre(song_identity, genre)
  if not M.golden[genre] then M.build(song_identity) end
  return M.golden[genre]
end

return M
