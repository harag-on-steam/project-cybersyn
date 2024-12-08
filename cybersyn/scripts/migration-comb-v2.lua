local OLD_MODE_MAPPING = {
	["/"]  = "<", -- PRIMARY_IO
	["%"]  = ">", -- SECONDARY_IO
	["+"]  = "≤", -- DEPOT
	["-"]  = "≥", -- WAGON
	[">>"] = "≠", -- REFUELER
	-- everything else is mapped to DEFAULT_PRIMARY_IO
}

local DEFAULT_PRIMARY_IO = "<" -- PRIMARY_IO
local DEFAULT_NETWORK = { name = "signal-A", type = "virtual" }
local DEFAULT_SETTINGS = 0 -- allow_list_on, everything else off

local DISABLE_INPUTS = { green = false, red = false }
local ALWAYS_TRUE = {
	compare_type = "or",
	comparator = "=",
	-- no signals, undefined == undefined is true in this context
	first_signal_networks = DISABLE_INPUTS,
	second_signal_networks = DISABLE_INPUTS,
}

---@param constant_combinator LuaEntity?
---@return LogisticFilter[]?
local function get_constant_signals(constant_combinator)
	if not constant_combinator or not constant_combinator.valid then return nil end
	local behavior = constant_combinator.get_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
	local section1 = behavior and behavior.get_section(1)
	return section1 and section1.filters
end

---@param arithmetic_combinator LuaEntity?
---@return ArithmeticCombinatorParameters?
local function get_arithmetic_params(arithmetic_combinator)
	if not arithmetic_combinator or not arithmetic_combinator.valid then return nil end
	local behavior = arithmetic_combinator.get_control_behavior() --[[@as LuaArithmeticCombinatorControlBehavior]]
	return behavior and behavior.parameters
end

---Replaces a v1 arithmetic Cybersyn combinator with a v2 decider Cybersyn combinator.
---All settings and current output signals are copied over and the hidden output combinator is destroyed.
---Does not perform any cleanup in map_data.
---Returns the new combinator entity and the unit_numbers of the old combinator and its hidden output combinator.
---@param v1 LuaEntity
---@return LuaEntity, uint32, uint32?
function replace_with_combinator_v2(v1)
	local surface = v1.surface

	local v1_unit_number = v1.unit_number
	local v1_params = get_arithmetic_params(v1)

	local v1_output = surface.find_entity("cybersyn-combinator-output", v1.position)
	local v1_output_unit_number = v1_output and v1_output.unit_number
	local v1_output_signals = get_constant_signals(v1_output)

	assert(v1_unit_number)
	assert(v1_params)

	local v2 = surface.create_entity {
		name = "cybersyn-combinator-2",
		fast_replace = true,
		spill = false,
		raise_built = false,
		preserve_ghosts_and_corpses = true,
		create_build_effect_smoke = false,
		position = v1.position,
		direction = v1.direction,
		quality = v1.quality,
		force = v1.force, -- required for fast_replace
	}
	assert(v2, "script-based combinator update cannot fail")

	if v1_output then
		v1_output.destroy()
	end

	local cybersyn_settings = {
		compare_type = "or",
		comparator = OLD_MODE_MAPPING[v1_params.operation] or DEFAULT_PRIMARY_IO,
		constant = v1_params.second_constant or DEFAULT_SETTINGS,
		first_signal = v1_params.first_signal or DEFAULT_NETWORK,
		first_signal_networks = DISABLE_INPUTS,
		second_signal_networks = DISABLE_INPUTS,
	}

	local outputs = {}
	if v1_output_signals then
		local i = 1
		for _, filter in pairs(v1_output_signals) do
			local signal = filter.value
			if (signal and filter.min) then
				outputs[i] = {
					copy_count_from_input = false,
					constant = filter.min,
					signal = { name=signal.name, quality=signal.quality, type=signal.type }
				}
				i = i + 1
			end
		end
	end

	local v2_behavior = v2.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]
	v2_behavior.parameters = {
		conditions = {
			cybersyn_settings,
			ALWAYS_TRUE,
		},
		outputs = outputs
	}

	return v2, v1_unit_number, v1_output_unit_number
end
