--!strict
--!nolint LocalShadow

--[[
	Constructs a new state object which can listen for updates on another state
	object.
]]

local Package = script.Parent.Parent
local Types = require(Package.Types)
local InternalTypes = require(Package.InternalTypes)
local External = require(Package.External)
local whichLivesLonger = require(Package.Memory.whichLivesLonger)
local logWarn = require(Package.Logging.logWarn)
local logError = require(Package.Logging.logError)

local class = {}
local CLASS_METATABLE = {__index = class}

--[[
	Called when the watched state changes value.
]]
function class:update(): boolean
	local self = self :: InternalTypes.Observer
	for _, callback in pairs(self._changeListeners) do
		External.doTaskImmediate(callback)
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
function class:onChange(
	callback: () -> ()
): () -> ()
	local self = self :: InternalTypes.Observer
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
function class:onBind(
	callback: () -> ()
): () -> ()
	local self = self :: InternalTypes.Observer
	External.doTaskImmediate(callback)
	return self:onChange(callback)
end

function class:destroy()
	local self = self :: InternalTypes.Observer
	if self.scope == nil then
		logError("destroyedTwice", nil, "Observer")
	end
	self.scope = nil
	for dependency in pairs(self.dependencySet) do
		dependency.dependentSet[self] = nil
	end
end

local function Observer(
	scope: Types.Scope<unknown>,
	watchedState: Types.StateObject<unknown>
): Types.Observer
	if watchedState == nil then
		logError("scopeMissing", nil, "Observers", "myScope:Observer(watchedState)")
	end

	local self = setmetatable({
		type = "State",
		kind = "Observer",
		scope = scope,
		dependencySet = {[watchedState] = true},
		dependentSet = {},
		_changeListeners = {}
	}, CLASS_METATABLE)
	local self = (self :: any) :: InternalTypes.Observer
	
	table.insert(scope, self)

	if watchedState.scope == nil then
		logError("useAfterDestroy", nil, `The {watchedState.kind} object`, `the Observer that is watching it`)
	elseif whichLivesLonger(scope, self, watchedState.scope, watchedState) == "a" then
		logWarn("possiblyOutlives", `The {watchedState.kind} object`, `the Observer that is watching it`)
	end

	-- add this object to the watched state's dependent set
	watchedState.dependentSet[self] = true

	return self
end

return Observer