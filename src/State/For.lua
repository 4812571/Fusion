--!nonstrict

--[[
	The private generic implementation for all public `For` objects.
]]

local Package = script.Parent.Parent
local PubTypes = require(Package.PubTypes)
local Types = require(Package.Types)
-- Logging
local logError = require(Package.Logging.logError)
local logErrorNonFatal = require(Package.Logging.logErrorNonFatal)
local parseError = require(Package.Logging.parseError)
-- State
local peek = require(Package.State.peek)
local isState = require(Package.State.isState)
local Value = require(Package.State.Value)
-- Memory
local doCleanup = require(Package.Memory.doCleanup)

local class = {}

local CLASS_METATABLE = { __index = class }
local WEAK_KEYS_METATABLE = { __mode = "k" }

--[[
	Called when the original table is changed.
]]

function class:update(): boolean
	
	local existingInputTable = self._existingInputTable
	local existingOutputTable = self._existingOutputTable
	local existingProcessors = self._existingProcessors
	local newInputTable = peek(self._inputTable)
	local newOutputTable = self._newOutputTable
	local newProcessors = self._newProcessors
	local remainingPairs = self._remainingPairs

	-- clean out main dependency set
	for dependency in pairs(self.dependencySet) do
		dependency.dependentSet[self] = nil
	end
	table.clear(self.dependencySet)

	if isState(self._inputTable) then
		self._inputTable.dependentSet[self], self.dependencySet[self._inputTable] = true, true
	end

	if newInputTable ~= existingInputTable then
		for key, value in newInputTable do
			if remainingPairs[key] == nil then
				remainingPairs[key] = {[value] = true}
			else
				remainingPairs[key][value] = true
			end
		end

		-- First, try and reuse processors who match both the key and value of a
		-- remaining pair. This can be done with no recomputation.
		-- NOTE: we also reuse processors with nil output keys here, so long as
		-- they match values. This ensures they don't get recomputed either.
		for tryReuseProcessor in existingProcessors do
			local key = peek(tryReuseProcessor.inputPair).key
			local value = peek(tryReuseProcessor.inputPair).value
			if peek(tryReuseProcessor.outputPair).key == nil then
				for key, remainingValues in remainingPairs do
					if remainingValues[value] ~= nil then
						remainingValues[value] = nil
						tryReuseProcessor.inputPair:set({key = key, value = value})
						newProcessors[tryReuseProcessor] = true
						existingProcessors[tryReuseProcessor] = nil
						break
					end
				end
			else
				local remainingValues = remainingPairs[key]
				if remainingValues ~= nil and remainingValues[value] ~= nil then
					remainingValues[value] = nil
					newProcessors[tryReuseProcessor] = true
					existingProcessors[tryReuseProcessor] = nil
				end
			end
			
		end
		-- Next, try and reuse processors who match the key of a remaining pair.
		-- The value will change but the key will stay stable.
		for tryReuseProcessor in existingProcessors do
			local key = peek(tryReuseProcessor.inputPair).key
			local remainingValues = remainingPairs[key]
			if remainingValues ~= nil then
				local value = next(remainingValues)
				if value ~= nil then
					remainingValues[value] = nil
					tryReuseProcessor.inputPair:set({key = key, value = value})
					newProcessors[tryReuseProcessor] = true
					existingProcessors[tryReuseProcessor] = nil
				end
			end
		end
		-- Next, try and reuse processors who match the value of a remaining pair.
		-- The key will change but the value will stay stable.
		for tryReuseProcessor in existingProcessors do
			local value = peek(tryReuseProcessor.inputPair).value
			for key, remainingValues in remainingPairs do
				if remainingValues[value] ~= nil then
					remainingValues[value] = nil
					tryReuseProcessor.inputPair:set({key = key, value = value})
					newProcessors[tryReuseProcessor] = true
					existingProcessors[tryReuseProcessor] = nil
					break
				end
			end
		end
		-- Finally, try and reuse any remaining processors, even if they do not
		-- match a pair. Both key and value will be changed.
		for tryReuseProcessor in existingProcessors do
			for key, remainingValues in remainingPairs do
				local value = next(remainingValues)
				if value ~= nil then
					remainingValues[value] = nil
					tryReuseProcessor.inputPair:set({key = key, value = value})
					newProcessors[tryReuseProcessor] = true
					existingProcessors[tryReuseProcessor] = nil
					break
				end
			end
		end
		-- By this point, we can be in one of three cases:
		-- 1) some existing processors are left over; no remaining pairs (shrunk)
		-- 2) no existing processors are left over; no remaining pairs (same size)
		-- 3) no existing processors are left over; some remaining pairs (grew)
		-- So, existing processors should be destroyed, and remaining pairs should
		-- be created. This accomodates for table growth and shrinking.
		for unusedProcessor in existingProcessors do
			doCleanup(unusedProcessor.cleanupTask)
		end
		
		for key, remainingValues in remainingPairs do
			for value in remainingValues do
				local scope = {}
				local inputPair = Value(scope, {key = key, value = value})
				local processOK, outputPair = xpcall(self._processor, parseError, scope, inputPair)
				if processOK then
					local processor = {
						inputPair = inputPair,
						outputPair = outputPair,
						cleanupTask = scope
					}
					newProcessors[processor] = true
				else
					logErrorNonFatal("forProcessorError", outputPair)
				end
			end
		end
	end

	for processor in newProcessors do
		local pair = processor.outputPair
		pair.dependentSet[self], self.dependencySet[pair] = true, true
		local key, value = peek(pair).key, peek(pair).value
		if value == nil then
			continue
		end
		if key == nil then
			key = #newOutputTable + 1
		end
		if newOutputTable[key] == nil then
			newOutputTable[key] = value
		else
			logErrorNonFatal("forKeyCollision", key)
		end
	end

	self._existingProcessors = newProcessors
	self._existingOutputTable = newOutputTable
	table.clear(existingOutputTable)
	table.clear(existingProcessors)
	table.clear(remainingPairs)
	self._newProcessors = existingProcessors
	self._newOutputTable = existingOutputTable

	return true
end

--[[
	Returns the interior value of this state object.
]]
function class:_peek(): any
	return self._existingOutputTable
end

function class:get()
	logError("stateGetWasRemoved")
end

function class:destroy()
	if self.scope == nil then
		logError("destroyedTwice", nil, "For")
	end
	self.scope = nil
	for dependency in pairs(self.dependencySet) do
		dependency.dependentSet[self] = nil
	end
	for unusedProcessor in self._existingProcessors do
		doCleanup(unusedProcessor.cleanupTask)
	end
end

local function For<KI, VI, KO, VO>(
	scope: PubTypes.Scope<any>,
	inputTable: PubTypes.CanBeState<{ [KI]: VI }>,
	processor: (
		{any},
		PubTypes.StateObject<{key: KI, value: VI}>
	) -> (PubTypes.StateObject<{key: KO?, value: VO}>)
): Types.For<KI, KO, VI, VO>

	local self = setmetatable({
		type = "State",
		kind = "For",
		scope = scope,
		dependencySet = {},
		-- if we held strong references to the dependents, then they wouldn't be
		-- able to get garbage collected when they fall out of scope
		dependentSet = setmetatable({}, WEAK_KEYS_METATABLE),
		_processor = processor,
		_inputTable = inputTable,
		_existingInputTable = nil,
		_existingOutputTable = {},
		_existingProcessors = {},
		_newOutputTable = {},
		_newProcessors = {},
		_remainingPairs = {}
	}, CLASS_METATABLE)

	self:update()
	
	table.insert(scope, self)

	return self
end

return For