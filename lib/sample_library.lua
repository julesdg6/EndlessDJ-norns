local SampleLibrary = {}

SampleLibrary.factory_risers = {}

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
  return SampleLibrary.factory_risers
end

function SampleLibrary.load_factory(internal_engine)
  local files = SampleLibrary.scan()
  for index, path in ipairs(files) do
    local slot = index + 16
    if slot > 48 then break end
    internal_engine.load_sample(slot, path)
  end
  print("Endless DJ: loaded " .. #files .. " factory risers")
  return #files
end

function SampleLibrary.riser_for_seed(seed)
  local count = #SampleLibrary.factory_risers
  if count == 0 then return nil end
  return ((math.max(1, seed or 1) - 1) % count) + 17
end

return SampleLibrary
