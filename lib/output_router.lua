local Router = {}

Router.OFF = 1
Router.EXTERNAL = 2
Router.INTERNAL = 3
Router.BOTH = 4
Router.OPTIONS = {"off", "external", "internal", "both"}

local routes = {
  drums = Router.EXTERNAL,
  bass = Router.EXTERNAL,
  chords = Router.EXTERNAL,
  mono = Router.EXTERNAL,
  samples = Router.EXTERNAL,
}

function Router.set(part, route)
  assert(routes[part], "unknown output part: " .. tostring(part))
  routes[part] = route
end

function Router.get(part)
  return routes[part]
end

function Router.sends_external(part)
  local route = routes[part]
  return route == Router.EXTERNAL or route == Router.BOTH
end

function Router.sends_internal(part)
  local route = routes[part]
  return route == Router.INTERNAL or route == Router.BOTH
end

return Router
