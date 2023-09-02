--!nonstrict

--[[
	Constructs a new state object which can listen for updates on another state
	object.

	FIXME: enabling strict types here causes free types to leak
]]

local Package = script.Parent.Parent
local PubTypes = require(Package.PubTypes)
local Types = require(Package.Types)

type Set<T> = {[T]: any}

local class = {}
local CLASS_METATABLE = {__index = class}

--[[
	Called when the watched state changes value.
]]
function class:update(): boolean
	for _, callback in pairs(self._changeListeners) do
		task.spawn(callback)
	end
	return false
end

--[[
	Adds a change listener. When the watched state changes value, the listener
	will be fired.

	Returns a function which, when called, will disconnect the change listener.
	As long as there is at least one active change listener, this Observer
	will be held in memory, preventing GC, so disconnecting is important.
]]
function class:onChange(callback: () -> ()): () -> ()
	local uniqueIdentifier = {}
	self._changeListeners[uniqueIdentifier] = callback
	return function()
		self._changeListeners[uniqueIdentifier] = nil
	end
end

--[[
	Similar to `class:onChange()`, however it runs the provided callback
	immediately.
]]
function class:onBind(callback: () -> ()): () -> ()
	task.spawn(callback)
	return self:onChange(callback)
end

function class:destroy()
	for dependency in pairs(self.dependencySet) do
		dependency.dependentSet[self] = nil
	end
	table.clear(self)
end

local function Observer(watchedState: PubTypes.Value<any>): Types.Observer
	local self = setmetatable({
		type = "State",
		kind = "Observer",
		dependencySet = {[watchedState] = true},
		dependentSet = {},
		_changeListeners = {}
	}, CLASS_METATABLE)

	-- add this object to the watched state's dependent set
	watchedState.dependentSet[self] = true

	return self
end

return Observer