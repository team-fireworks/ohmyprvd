--!strict
--[[
  Copyright (c) Team Fireworks 2024.
  This source code is licensed under the MIT license found in the LICENSE file
  in the root directory of this source tree.
]]

local Log = require("prvdmwrong/log")
local Types = require("prvdmwrong/types")
local expect = Log.expect
local warn = Log.warn

type Lifecycle<Interface = { [any]: any }> = Types.Lifecycle
type Object = { [unknown]: unknown }

local Lifecycles = {}
Lifecycles.methodRegistered = {} :: { [string]: { [{}]: (Object) -> () } }
Lifecycles.methodUnregistered = {} :: { [string]: { [{}]: (Object) -> () } }
Lifecycles.lifecycleMethods = {} :: { [string]: { [Lifecycle]: true } }

--[[
  Registers lifecycle methods for an object.
  @internal
]]
function Lifecycles.registerMethod(object: Object, method: string)
  local methodRegistered = Lifecycles.methodRegistered[method]
  if not methodRegistered then
    return
  end

  for _, handler in pairs(methodRegistered) do
    handler(object)
  end
end

--[[
  Unregister lifecycle methods from an object.
  @internal
]]
function Lifecycles.unregisterMethod(object: Object, method: string)
  if not object or not object[method] then
    return
  end

  local methodUnregistered = Lifecycles.methodUnregistered[method]
  if not methodUnregistered then
    return
  end

  for _, handler in pairs(methodUnregistered) do
    handler(object)
  end
end

--[[
  Registers all lifecycle methods on an object.
  @internal
]]
function Lifecycles.registerAll(object: Object)
  for method, lifecycles in pairs(Lifecycles.lifecycleMethods) do
    if typeof(object[method]) ~= "function" then
      continue
    end
    for lifecycle in pairs(lifecycles) do
      lifecycle:register(object)
    end
  end
end

--[[
  Constructs and returns a lifecycle method.
]]
function Lifecycles.Lifecycle(method: string, fire: (self: Lifecycle, ...unknown) -> ()): Lifecycle
  local self = {} :: Lifecycle
  self.listeners = {}
  self.method = method
  self.fire = fire

  function self:register(object)
    expect(typeof(object[method]) == "function", "cannotRegisterLifecycle", nil, `{method} must be a method`)
    expect(not table.find(self.listeners, object), "cannotRegisterLifecycle", nil, `already registered this lifecycle`)
    Lifecycles.registerMethod(object, method)
    table.insert(self.listeners, object)
  end

  function self:unregister(object)
    local index = table.find(self.listeners, object)
    if table.find(self.listeners, object) then
      table.remove(self.listeners, index)
      Lifecycles.unregisterMethod(object, method)
    end
  end

  local lifecycleMethods = Lifecycles.lifecycleMethods[method]
  if not lifecycleMethods then
    local methods = {}
    Lifecycles.lifecycleMethods[method] = methods
    lifecycleMethods = methods
  end
  lifecycleMethods[self] = true

  table.freeze(self)
  return self
end

--[[
  Called when an object registers a method. Handlers are expected to be
  infallible and non-yielding. The handler receives the implementing object.
]]
function Lifecycles.onLifecycleRegistered(method: string, handler: (Object) -> ())
  local methodRegistered = Lifecycles.methodRegistered[method]
  if not methodRegistered then
    local ref = {}
    Lifecycles.methodRegistered[method] = ref
    methodRegistered = ref
  end
  local identifier = table.freeze {}
  methodRegistered[identifier] = handler
end

--[[
  Called when an object unregister a method. Handlers are expected to be
  infallible and non-yielding. The handler receives the implementing object.
]]
function Lifecycles.onLifecycleUnregistered(method: string, handler: (Object) -> ())
  local methodUnregistered = Lifecycles.methodUnregistered[method]
  if not methodUnregistered then
    local ref = {}
    Lifecycles.methodUnregistered[method] = ref
    methodUnregistered = ref
  end
  local identifier = table.freeze {}
  methodUnregistered[identifier] = handler
end

--[[
  A handler for lifecycle methods that spawns all listeners concurrently.
]]
function Lifecycles.fireConcurrent(self: Lifecycle, ...: unknown)
  for _, listener in ipairs(self.listeners) do
    task.spawn(listener[self.method], listener, ...)
  end
end

--[[
  A handler for lifecycle methods that runs all listeners sequentially.
]]
function Lifecycles.fireSequential(self: Lifecycle, ...: unknown)
  for _, listener in ipairs(self.listeners) do
    listener[self.method](listener, ...)
  end
end

--[[
  @deprecated use either `onLifecycleRegistered` or `Lifecycle` instead
]]
function Lifecycles.onMethodImplemented(method: string, handler: (Object) -> ())
  warn("onMethodImplementedWasDeprecated", method)
  Lifecycles.onLifecycleRegistered(method, handler)
end

table.freeze(Lifecycles)
return Lifecycles
