--!strict

--[[
	Constructs a new For object which maps keys of a table using a `processor`
	function.

	Optionally, a `destructor` function can be specified for cleaning up output.

	Additionally, a `meta` table/value can optionally be returned to pass data
	created when running the processor to the destructor when the created object
	is cleaned up.
]]

local Package = script.Parent.Parent
local PubTypes = require(Package.PubTypes)
local Types = require(Package.Types)
-- State
local For = require(Package.State.For)
local Computed = require(Package.State.Computed)
-- Logging
local parseError = require(Package.Logging.parseError)
local logError = require(Package.Logging.logError)

local function ForKeys<KI, KO, V, M>(
	scope: {PubTypes.Task},
	inputTable: PubTypes.CanBeState<{[KI]: V}>,
	processor: (PubTypes.Use, KI) -> (KO, M?)
): Types.For<KI, KO, V, V>

	return For(
		scope,
		inputTable,
		function(scope, inputKey, inputValue)
			return Computed(scope, function(scope, use)
				local ok, key, meta = xpcall(processor, parseError, scope, use, use(inputKey))
				if ok then
					return key, meta
				else
					logError("forProcessorError", parseError)
				end
			end), inputValue
		end
	)
end

return ForKeys