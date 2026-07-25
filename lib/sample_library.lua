local SampleLibrary = {}

SampleLibrary.factory_risers = {}
SampleLibrary.factory_roles = {}

SampleLibrary.ROLES = {
  "perc_accent", "alt_perc", "short_fill", "long_fill",
  "impact", "riser", "vocal_stab", "drop_accent",
}

local function scan(path)
  local files = {}
  if not util or not util.scandir then return files end
  for _, name in ipairs(util.scandir(path) or {}) do
    if type(name) == "string" and name:lower():match("%.wav$") then
      table.insert(files, path .. name)
    end
  end
  table.sort(files)
  return files
end

function SampleLibrary.scan()
  SampleLibrary.factory_risers =
    scan(_path.code .. "EndlessDJ/samples/factory/risers/")
  SampleLibrary.factory_roles = {}
  local next_slot = 49
  for _, role in ipairs(SampleLibrary.ROLES) do
    if role ~= "riser" then
      local paths = scan(
        _path.code .. "EndlessDJ/samples/factory/oneshots/" .. role .. "/"
      )
      SampleLibrary.factory_roles[role] = {}
      for _, path in ipairs(paths) do
        table.insert(SampleLibrary.factory_roles[role], {
          slot = next_slot,
          path = path,
        })
        next_slot = next_slot + 1
      end
    end
  end
  return SampleLibrary.factory_risers
end

function SampleLibrary.load_factory(internal_engine)
  local files = SampleLibrary.scan()
  for index, path in ipairs(files) do
    local slot = index + 16
    if slot > 48 then break end
    internal_engine.load_sample(slot, path)
  end
  local one_shots = 0
  for _, role in ipairs(SampleLibrary.ROLES) do
    for _, sample in ipairs(SampleLibrary.factory_roles[role] or {}) do
      internal_engine.load_sample(sample.slot, sample.path)
      one_shots = one_shots + 1
    end
  end
  print(
    "Endless DJ: loaded " .. #files .. " factory risers and " ..
    one_shots .. " role one-shots"
  )
  return #files, one_shots
end

function SampleLibrary.riser_for_seed(seed)
  local count = #SampleLibrary.factory_risers
  if count == 0 then return nil end
  return ((math.max(1, seed or 1) - 1) % count) + 17
end

function SampleLibrary.role_for_seed(role, seed)
  if role == "riser" then
    return SampleLibrary.riser_for_seed(seed)
  end
  local choices = SampleLibrary.factory_roles[role] or {}
  if #choices == 0 then return nil end
  local index = ((math.max(1, seed or 1) - 1) % #choices) + 1
  return choices[index].slot
end

return SampleLibrary
