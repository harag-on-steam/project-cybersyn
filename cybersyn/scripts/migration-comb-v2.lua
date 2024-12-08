local OLD_TO_NEW_MODE_MAPPING = {
	["/"]  = "<", -- PRIMARY_IO
	["%"]  = ">", -- SECONDARY_IO
	["+"]  = "≤", -- DEPOT
	["-"]  = "≥", -- WAGON
	[">>"] = "≠", -- REFUELER
	-- if input value is already mapped
	["<"]  = "<", -- PRIMARY_IO
	[">"]  = ">", -- SECONDARY_IO
	["≤"]  = "≤", -- DEPOT
	["≥"]  = "≥", -- WAGON
	["≠"]  = "≠", -- REFUELER
	-- everything else is mapped to MODE_PRIMARY_IO
}

local NEW_TO_OLD_MODE_MAPPING = {
	["<"]  = "/",  -- PRIMARY_IO
	[">"]  = "%",  -- SECONDARY_IO
	["≤"]  = "+",  -- DEPOT
	["≥"]  = "-",  -- WAGON
	["≠"]  = ">>", -- REFUELER
	-- if input value is already mapped
	["/"]  = "/",  -- PRIMARY_IO
	["%"]  = "%",  -- SECONDARY_IO
	["+"]  = "+",  -- DEPOT
	["-"]  = "-",  -- WAGON
	[">>"] = ">>", -- REFUELER
	-- everything else is mapped to MODE_PRIMARY_IO
}

function map_old_mode_to_new_mode(mode)
	return OLD_TO_NEW_MODE_MAPPING[mode] or MODE_PRIMARY_IO
end

function map_new_mode_to_old_mode(mode)
	return NEW_TO_OLD_MODE_MAPPING[mode] or MODE_PRIMARY_IO
end

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
---Lookup tables in map_data and corresponding station, depot or refueler are updated with the v2 entity.
---@param v1 LuaEntity
---@return LuaEntity comb the new combinator
---@return uint32 comb_type 0: not part of a station, 1: station comb1, 2: station comb2, 3: depot, 4: refueler
---@return Station|Depot|Refueler|nil station the station this combinator is a part of or nil if it is not
function replace_with_combinator_v2(v1)
	local map_data = storage
	local surface = v1.surface

	local v1_unit_number = v1.unit_number
	local v1_params = get_arithmetic_params(v1)

	local v1_output = surface.find_entity("cybersyn-combinator-output", v1.position)
	local v1_output_unit_number = v1_output and v1_output.unit_number
	local v1_output_signals = get_constant_signals(v1_output)

	assert(v1_unit_number, "cybersyn: invalid combinator")
	assert(v1_params, "cybersyn: invalid combinator")

	local comb_type, _, station, stop = comb_to_internal_entity(storage, v1, v1_unit_number)

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
	assert(v2, "cybersyn: combinator update failed")
	local v2_unit_number = v2.unit_number
	assert(v2_unit_number, "cybersyn: combinator update failed")

	if v1_output then
		v1_output.destroy()
	end
	if v1_output_unit_number then
		map_data.to_output[v1_output_unit_number] = nil
	end

	local cybersyn_settings = {
		compare_type = "or",
		comparator = map_old_mode_to_new_mode(v1_params.operation),
		constant = v1_params.second_constant or 0,
		first_signal = v1_params.first_signal or NETWORK_SIGNAL_DEFAULT,
		first_signal_networks = CONDITION_INPUTS_DISABLED,
		second_signal_networks = CONDITION_INPUTS_DISABLED,
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
			CONDITION_ALWAYS_TRUE,
		},
		outputs = outputs
	}

	if map_data.to_comb[v1_unit_number] then
		map_data.to_comb[v2_unit_number] = v2
		map_data.to_comb_params[v2_unit_number] = v2_behavior.get_condition(1)

		map_data.to_comb[v1_unit_number] = nil
		map_data.to_comb_params[v1_unit_number] = nil
	end

	if station then
		map_data.to_stop[v2_unit_number] = stop
		map_data.to_stop[v1_unit_number] = nil

		if comb_type == 1 then     --station comb1
			station.entity_comb1 = v2
		elseif comb_type == 2 then --station comb2
			station.entity_comb2 = v2
		elseif comb_type == 3 then --depot
			station.entity_comb  = v2
		elseif comb_type == 4 then --refueler
			station.entity_comb  = v2
		end
	end

	return v2, comb_type, station
end
