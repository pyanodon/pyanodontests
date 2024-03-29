local table = require('__stdlib__/stdlib/utils/table')

local pytest = {}

local start_tech_name = '__START__'
local fuel_fluid = 'fluid'
local fuel_electricity = 'electricity'
local fuel_heat = 'heat'
local crafting_boiler = '__boiler__'
local crafting_generator = '__generator__'
local crafting_reactor = '__reactor__'
local crafting_launch = '__launch__'
local tech_tab = {}
local ignored_crafting = {'py-venting', 'py-runoff', 'py-incineration', 'blackhole-energy', 'compost', crafting_launch, crafting_boiler, crafting_reactor, crafting_generator, 'drilling-fluid'}
local starting_entities = {'crash-site-assembling-machine-1-repaired', 'crash-site-lab-repaired'}
local ignored_entities = {'bioport','requester-tank','provider-tank'}
local ignored_recipes = { 'bioport-hidden-recipe' }
local added_recipes = {}
local custom_recipes = {}
local ignored_techs = {'placeholder'}

local entity_script_unlocks = {}
entity_script_unlocks["bitumen-seep-mk01"] = { "oil-derrick-mk01", "oil-mk01" }
entity_script_unlocks["bitumen-seep-mk02"] = { "oil-derrick-mk02", "oil-mk02" }
entity_script_unlocks["bitumen-seep-mk03"] = { "oil-derrick-mk03", "oil-mk03" }
entity_script_unlocks["bitumen-seep-mk04"] = { "oil-derrick-mk04", "oil-mk04" }
entity_script_unlocks["natural-gas-seep-mk01"] = { "natural-gas-extractor-mk01", "natural-gas-mk01" }
entity_script_unlocks["natural-gas-seep-mk02"] = { "natural-gas-extractor-mk01", "natural-gas-mk01" }
entity_script_unlocks["natural-gas-seep-mk03"] = { "natural-gas-extractor-mk01", "natural-gas-mk01" }
entity_script_unlocks["natural-gas-seep-mk04"] = { "natural-gas-extractor-mk01", "natural-gas-mk01" }
entity_script_unlocks["tar-seep-mk01"] = { "tar-extractor-mk01", "tar-patch" }
entity_script_unlocks["tar-seep-mk02"] = { "tar-extractor-mk02", "tar-patch" }
entity_script_unlocks["tar-seep-mk03"] = { "tar-extractor-mk03", "tar-patch" }
entity_script_unlocks["tar-seep-mk04"] = { "tar-extractor-mk04", "tar-patch" }
entity_script_unlocks["numal-reef-mk01"] = { "numal-reef-mk01" }
entity_script_unlocks["numal-reef-mk02"] = { "numal-reef-mk02" }
entity_script_unlocks["numal-reef-mk03"] = { "numal-reef-mk03" }
entity_script_unlocks["numal-reef-mk04"] = { "numal-reef-mk04" }

local item_script_unlocks = {}
item_script_unlocks["bioport"] = { "guano" }


function pytest.start_log(msg)
	game.write_file('tech_tree_log.txt', msg .. '\n')
end


function pytest.log(msg)
	game.write_file('tech_tree_log.txt', msg .. '\n', true)
end


function pytest.tech(tech)
	if not tech_tab[tech] then
		local t = {}
		t.name = tech
		t.dependents = {}
		t.prerequisites = {}
		t.recipes = {}
		t.unlocked_entities = {}
		t.unlocked_crafting = {}
		t.unlocked_mining = {}
		t.unlocked_items = {}
		t.unlocked_fluids = {}
		t.unlocked_fuels = {}
		t.unlocked_recipes = {}
		t.skipped_recipes = {}
		t.required_science_packs = {}
		t.unlocked_techs = {}
		t.unlocked_lab_slots = {}
		t.unlocked_equipment = {}
		tech_tab[tech] = t
	end
	return tech_tab[tech]
end


function pytest.add_dependent_tech(parent_tech, dependent_tech)
	parent_tech.dependents[dependent_tech.name] = dependent_tech
	dependent_tech.prerequisites[parent_tech.name] = parent_tech
end


function pytest.prepare_tech_data()
	local start_tech = pytest.tech(start_tech_name)

	for _, r in pairs(game.recipe_prototypes) do
		if r.enabled then
			start_tech.recipes[r.name] = true
		end
	end

	for _, tech in pairs(game.technology_prototypes) do
		local t = pytest.tech(tech.name)

		if tech.enabled and not table.any(ignored_techs, function (t) return t == tech.name end) then
			if not tech.prerequisites or table.is_empty(tech.prerequisites) then
				pytest.add_dependent_tech(start_tech, t)
			else
				for pt, _ in pairs(tech.prerequisites) do
					pytest.add_dependent_tech(pytest.tech(pt), t)
				end
			end

			for _, eff in pairs(tech.effects or {}) do
				if eff.type == 'unlock-recipe' then
					t.recipes[eff.recipe] = true
				end
			end
		end
	end
end


function pytest.insert_crafting_details(tab, craft, write_log)
	if not tab then tab = {} end

	local push = true

	for _, cr in pairs(tab) do
		if cr.ingredient_count >= craft.ingredient_count and cr.fluidboxes_in >= craft.fluidboxes_in and cr.fluidboxes_out >= craft.fluidboxes_out then
			push = false
		end
	end

	if push then
		if write_log then
			pytest.log('  - Unlocked crafting: ' .. craft.crafting_category .. ', ingredients: ' .. craft.ingredient_count .. ', fluidboxes in: ' .. craft.fluidboxes_in .. ', fluidboxes out: ' .. craft.fluidboxes_out)
		end

		local key = (craft.ingredient_count or 255) .. '|' .. (craft.fluidboxes_in or 0) .. '|' .. (craft.fluidboxes_out or 0)

		local remove_keys = {}
		for k, cr in pairs(tab) do
			if cr.ingredient_count < craft.ingredient_count and cr.fluidboxes_in < craft.fluidboxes_in and cr.fluidboxes_out < craft.fluidboxes_out then
				remove_keys[k] = true
			end
		end

		for k, _ in pairs(remove_keys) do
			tab[k] = nil
		end

		tab[key] = craft
	end

	return tab
end


function pytest.add_crafting_categories(tech, entity)
	local fb_in = 0
	local fb_out = 0

	for _, fb in pairs(entity.fluidbox_prototypes or {}) do
		if (fb.production_type == "input" or fb.production_type == "input-output")
			and not (entity.fluid_energy_source_prototype and entity.fluid_energy_source_prototype.fluid_box and entity.fluid_energy_source_prototype.fluid_box.index == fb.index)
		then
			fb_in = fb_in + 1
		elseif fb.production_type == "output" then
			fb_out = fb_out + 1
		end
	end

	local categories = entity.crafting_categories or {}
	if entity.type == 'boiler' then
		categories[crafting_boiler] = true
	elseif entity.type == 'generator' then
		categories[crafting_generator] = true
	elseif entity.type == 'reactor' then
		categories[crafting_reactor] = true
	elseif entity.type == 'rocket-silo' and entity.rocket_entity_prototype and entity.rocket_entity_prototype.get_inventory_size(defines.inventory.rocket) then
		categories[crafting_launch] = true
	end

	for c, _ in pairs(categories) do
		local craft = {}
		craft.crafting_category = c
		craft.ingredient_count = entity.ingredient_count or 255
		craft.fluidboxes_in = fb_in
		craft.fluidboxes_out = fb_out
		craft.entity = entity

		tech.unlocked_crafting[c] = pytest.insert_crafting_details(tech.unlocked_crafting[c], craft, true)
	end
end


function pytest.add_resource_categories(tech, entity)
	for r, _ in pairs(entity.resource_categories or {}) do
		if not tech.unlocked_mining[r] then
			pytest.log('  - Unlocked mining: ' .. r)
			tech.unlocked_mining[r] = true

			for _, e in pairs(tech.unlocked_entities) do
				if e.resource_category and e.resource_category == r then
					pytest.add_mining_results(tech, e)
				end
			end
		end
	end
end


function pytest.add_fuel_category(tech, fuel_category)
	if not tech.unlocked_fuels[fuel_category] then
		pytest.log('  - Unlocked fuel: ' .. fuel_category)
		tech.unlocked_fuels[fuel_category] = true
	end
end


function pytest.verify_entity(tech, entity_name, write_errors)
	local entity = game.entity_prototypes[entity_name]
	if table.any(ignored_entities, function (e) return e == entity_name end) then 
		return true
	end

	if entity.burner_prototype and (entity.energy_usage or entity.max_energy_usage) > 0 then
		local found = false
		local str = ''
		for fc, _ in pairs(entity.burner_prototype.fuel_categories) do
			if tech.unlocked_fuels[fc] then
				found = true
			end
			str = (str ~= '' and str .. ', ' or '') .. fc
		end

		if not found then
			if write_errors then
				pytest.log('ERROR: Missing fuel for entity: ' .. entity_name .. ' - fuel categories: ' .. str)
			end

			return false
		end
	end

	if entity.electric_energy_source_prototype and (entity.energy_usage or entity.max_energy_usage) > 0 and not tech.unlocked_fuels[fuel_electricity] then
		if write_errors then
			pytest.log('ERROR: Missing fuel for entity: ' .. entity_name .. ' - fuel category: ' .. fuel_electricity)
		end

		return false
	end

	if entity.heat_energy_source_prototype and (entity.energy_usage or entity.max_energy_usage) > 0 and not tech.unlocked_fuels[fuel_heat] then
		if write_errors then
			pytest.log('ERROR: Missing fuel for entity: ' .. entity_name .. ' - fuel category: ' .. fuel_heat)
		end

		return false
	end

	if entity.fluid_energy_source_prototype and (entity.energy_usage or entity.max_energy_usage) > 0 and not tech.unlocked_fuels[fuel_fluid] then
		if write_errors then
			pytest.log('ERROR: Missing fuel for entity: ' .. entity_name .. ' - fuel category: ' .. fuel_fluid)
		end

		return false
	end

	return true
end


function pytest.add_entity(tech, entity_name)
	local entity = game.entity_prototypes[entity_name]

	if not tech.unlocked_entities[entity_name] then
		pytest.log('  - Unlocked entity: ' .. entity_name)
		tech.unlocked_entities[entity_name] = entity

		pytest.add_crafting_categories(tech, entity)
		pytest.add_resource_categories(tech, entity)
		pytest.add_mining_results(tech, entity)

		for _, s in pairs(entity.result_units or {}) do
			pytest.add_entity(tech, s.unit)
		end

		for _, l in pairs(entity.loot or {}) do
			if l.probability > 0 and l.count_max > 0 then
				pytest.add_item(tech, l.item, ' (loot)')
			end
		end

		if entity.fixed_recipe and not tech.unlocked_recipes[entity.fixed_recipe] then
			added_recipes[entity.fixed_recipe] = true
		end

		for _, item_name in pairs(item_script_unlocks[entity_name] or {}) do
			pytest.add_item(tech, item_name)
		end

		if entity.type == 'offshore-pump' then
			pytest.add_fluid(tech, entity.fluid.name)
		elseif entity.type == 'boiler' then
			local custom_recipe = {}
			custom_recipe.name = crafting_boiler .. entity.name
			custom_recipe.category = crafting_boiler
			custom_recipe.ingredients = {}
			custom_recipe.products = {}

			local input = {}
			local output = {}
			local has_output = false
			local io_fb

			for _, fb in pairs(entity.fluidbox_prototypes) do
				if (fb.production_type == 'input' or fb.production_type == 'input-output') and fb.filter and #fb.pipe_connections > 0 then
					input = { type = 'fluid', name = fb.filter.name, minimum_temperature = fb.minimum_temperature, maximum_temperature = fb.maximum_temperature }
				elseif fb.production_type == 'output' and fb.filter and #fb.pipe_connections > 0 then
					output = { type = 'fluid', name = fb.filter.name, temperature = entity.target_temperature }
					has_output = true
				end

				if fb.production_type == 'input-output' then
					io_fb = fb
				end
			end

			-- Old style boiler
			if not has_output then
				output = { type = 'fluid', name = io_fb.filter.name, temperature = entity.target_temperature }
			end

			local amount = entity.max_energy_usage / (entity.target_temperature - game.fluid_prototypes[input.name].default_temperature) / game.fluid_prototypes[input.name].heat_capacity * 60
			input.amount = amount
			output.amount = amount

			table.insert(custom_recipe.ingredients, input)
			table.insert(custom_recipe.products, output)

			custom_recipes[custom_recipe.name] = custom_recipe
			added_recipes[custom_recipe.name] = true
		elseif entity.type == 'generator' then
			local custom_recipe = {}
			custom_recipe.name = crafting_generator .. entity.name
			custom_recipe.category = crafting_generator
			custom_recipe.ingredients = {}
			custom_recipe.products = {}

			local input = {}

			for _, fb in pairs(entity.fluidbox_prototypes) do
				if (fb.production_type == 'input' or fb.production_type == 'input-output') and fb.filter then
					input = { type = 'fluid', name = fb.filter.name, amount = entity.fluid_usage_per_tick * 60, minimum_temperature = fb.minimum_temperature, maximum_temperature = fb.maximum_temperature }
				end
			end

			local amount = entity.fluid_usage_per_tick * (entity.maximum_temperature - game.fluid_prototypes[input.name].default_temperature) * game.fluid_prototypes[input.name].heat_capacity * 60
			table.insert(custom_recipe.ingredients, input)
			table.insert(custom_recipe.products, { type = fuel_electricity, name = fuel_electricity, amount = amount })

			custom_recipes[custom_recipe.name] = custom_recipe
			added_recipes[custom_recipe.name] = true
		elseif entity.type == 'reactor' then
			local custom_recipe = {}
			custom_recipe.name = crafting_reactor .. entity.name
			custom_recipe.category = crafting_reactor
			custom_recipe.ingredients = {}
			custom_recipe.products = {}

			local amount = entity.max_energy_usage * 60
			table.insert(custom_recipe.products, { type = fuel_heat, name = fuel_heat, amount = amount })

			custom_recipes[custom_recipe.name] = custom_recipe
			added_recipes[custom_recipe.name] = true
		elseif entity.type == 'lab' then
			for _, i in pairs(game.entity_prototypes[entity.name].lab_inputs or {}) do
				if not tech.unlocked_lab_slots[i] then
					pytest.log('  - Unlocked lab input: ' .. i)
					tech.unlocked_lab_slots[i] = true
				end
			end
		end

		if entity.burner_prototype and not table.is_empty(entity.burner_prototype.fuel_categories or {}) then
			for _, i in pairs(tech.unlocked_items) do
				if i.fuel_category and entity.burner_prototype.fuel_categories[i.fuel_category] then
					pytest.add_burnt_result(tech, i)
				end
			end
		end
	end
end


function pytest.add_equipment(tech, equipment_name)
	local equipment = game.equipment_prototypes[equipment_name]

	if not tech.unlocked_equipment[equipment_name] then
		pytest.log('  - Unlocked equipment: ' .. equipment_name)
		tech.unlocked_equipment[equipment_name] = equipment

		if equipment.burner_prototype and not table.is_empty(equipment.burner_prototype.fuel_categories or {}) then
			for _, i in pairs(tech.unlocked_items) do
				if i.fuel_category and equipment.burner_prototype.fuel_categories[i.fuel_category] then
					pytest.add_burnt_result(tech, i)
				end
			end
		end
	end
end


function pytest.add_item(tech, item_name, source, no_log)
	local item = game.item_prototypes[item_name]

	if not tech.unlocked_items[item_name] then
		if not no_log then
			pytest.log('  - Unlocked item: ' .. item_name .. (source or ''))
		end
		tech.unlocked_items[item_name] = item

		if item.place_result then
			pytest.add_entity(tech, item.place_result.name)
		end

		if item.place_as_equipment_result then
			pytest.add_equipment(tech, item.place_as_equipment_result.name)
		end

		for _, entity_name in pairs(entity_script_unlocks[item_name] or {}) do
			pytest.add_entity(tech, entity_name)
		end

		if item.fuel_category and (item.fuel_value or 0) > 0 then
			pytest.add_fuel_category(tech, item.fuel_category)
			pytest.add_burnt_result(tech, item)
		end

		if item.rocket_launch_products and not table.is_empty(item.rocket_launch_products) then
			local custom_recipe = {}
			custom_recipe.name = crafting_launch .. item.name
			custom_recipe.category = crafting_launch
			custom_recipe.ingredients = {{ type = 'item', name = item.name, amount = 1 }}
			custom_recipe.products = table.deep_copy(item.rocket_launch_products)
			custom_recipes[custom_recipe.name] = custom_recipe
			added_recipes[custom_recipe.name] = true
		end
	end
end


function pytest.add_burnt_result(tech, item)
	if item.fuel_category and item.burnt_result and tech.unlocked_fuels[item.fuel_category] then
		local used = false

		for _, e in pairs(tech.unlocked_entities) do
			if e.burner_prototype and e.burner_prototype.fuel_categories[item.fuel_category]
			and e.burner_prototype.fuel_inventory_size > 0 and e.burner_prototype.burnt_inventory_size > 0 then
				used = true
				break
			end
		end

		for _, e in pairs(tech.unlocked_equipment) do
			if e.burner_prototype and e.burner_prototype.fuel_categories[item.fuel_category]
			and e.burner_prototype.fuel_inventory_size > 0 and e.burner_prototype.burnt_inventory_size > 0 then
				used = true
				break
			end
		end

		if used then
			pytest.add_item(tech, item.burnt_result.name, ' (burnt)')
		end
	end
end


function pytest.add_fluid(tech, fluid_name, temperature)
	local fluid = game.fluid_prototypes[fluid_name]

	local new = false
	temperature = temperature or fluid.default_temperature

	if not tech.unlocked_fluids[fluid_name] then
		tech.unlocked_fluids[fluid_name] = {}
		new = true
	end

	if not tech.unlocked_fluids[fluid_name][temperature] then
		pytest.log('  - Unlocked fluid: ' .. fluid_name .. ', temp: ' .. temperature)
		tech.unlocked_fluids[fluid_name][temperature] = true
	end

	if new then
		for _, e in pairs(tech.unlocked_entities) do
			if e.mineable_properties and e.mineable_properties.required_fluid == fluid_name then
				pytest.add_mining_results(tech, e)
			end
		end

		if (fluid.fuel_value or 0) > 0 then
			pytest.add_fuel_category(tech, fuel_fluid)
		end
	end
end


function pytest.add_products(tech, products, source)
	for _, p in pairs(products or {}) do
		if ((p.amount or 0) > 0 or (p.amount_max or 0) > 0) and (not p.probability or p.probability > 0) then
			if p.type == 'item' then
				pytest.add_item(tech, p.name, source)
			elseif p.type == 'fluid' then
				pytest.add_fluid(tech, p.name, p.temperature)
			elseif p.type == fuel_electricity then
				pytest.add_fuel_category(tech, fuel_electricity)
			elseif p.type == fuel_heat then
				pytest.add_fuel_category(tech, fuel_heat)
			end
		end
	end
end


function pytest.add_mining_results(tech, entity)
	if entity.mineable_properties and entity.mineable_properties.minable and entity.mineable_properties.products
	and (not entity.resource_category or tech.unlocked_mining[entity.resource_category])
	and (not entity.mineable_properties.required_fluid or tech.unlocked_fluids[entity.mineable_properties.required_fluid]) then
		pytest.add_products(tech, entity.mineable_properties.products, ' (mining)')
	end
end


function pytest.init_start_tech(tech)
	pytest.log('- AUTOPLACE:')
	for _, e in pairs(game.entity_prototypes) do
		if e.autoplace_specification and e.autoplace_specification.default_enabled then
			pytest.add_entity(tech, e.name)
		end
	end

	pytest.log('- STARTING ASSEMBLERS:')
	for _, e in pairs(starting_entities) do
		if game.entity_prototypes[e] then
			pytest.add_entity(tech, e)
		end
	end

	pytest.log('- CHARACTER:')
	pytest.add_entity(tech, 'character')
end


function pytest.ignore_recipe(recipe)
	local result = table.any(ignored_crafting, function (r) return r == recipe.category end)
		or recipe.name:find('fill%-.*%-barrel') ~= nil or recipe.name:find('empty%-.*%-barrel') ~= nil
		or recipe.name:find('fill%-.*%-canister') ~= nil or recipe.name:find('empty%-.*%-canister') ~= nil

	return result
end


function pytest.process_recipe(tech, recipe, write_errors)
	if table.any(ignored_recipes, function (r) return r == recipe.name end) then
		return true
	end

	local result = true
	local ingredient_count = 0
	local fluidboxes_in = 0
	local fluidboxes_out = 0
	local first = true

	for _, i in pairs(recipe.ingredients or {}) do
		local err = false
		local msg = ''
		ingredient_count = ingredient_count + 1

		if i.type == 'item' then
			if not tech.unlocked_items[i.name] then
				msg = 'ERROR: Missing ingredient for recipe ' .. recipe.name .. ': ' .. i.name
				err = true
			end
		else
			fluidboxes_in = fluidboxes_in + 1
			if not tech.unlocked_fluids[i.name] then
				msg = 'ERROR: Missing ingredient for recipe ' .. recipe.name .. ': ' .. i.name
				err = true
			elseif i.temperature or i.minimum_temperature or i.maximum_temperature then
				local r = false

				for t, _ in pairs(tech.unlocked_fluids[i.name]) do
					if (not i.temperature or i.temperature == t) and (not i.minimum_temperature or i.minimum_temperature <= t) and (not i.maximum_temperature or i.maximum_temperature >= t) then
						r = true
						break
					end
				end

				if not r then
					msg = 'ERROR: Missing ingredient for recipe ' .. recipe.name .. ': ' .. i.name ..
						(i.temperature ~= nil and ' temp: ' .. i.temperature or '') ..
						(i.minimum_temperature ~= nil and ' min temp: ' .. i.minimum_temperature or '') ..
						(i.maximum_temperature ~= nil and ' max temp: ' .. i.maximum_temperature or '')

					err = true
				end
			end
		end

		if err then
			if write_errors then
				if pytest.ignore_recipe(recipe) then
					tech.skipped_recipes[recipe.name] = true
				else
					if first then
						pytest.log('- RECIPE: ' .. recipe.name)
						first = false
					end
					pytest.log(msg)
					result = false
				end
			else
				result = false
			end
		end
	end

	if not tech.skipped_recipes[recipe.name] then
		for _, p in pairs(recipe.products or {}) do
			if p.type == 'fluid' then
				fluidboxes_out = fluidboxes_out + 1
			end
		end

		local craft_found = false

		for _, craft in pairs(tech.unlocked_crafting[recipe.category] or {}) do
			if craft.ingredient_count >= ingredient_count or craft.fluidboxes_in >= fluidboxes_in or craft.fluidboxes_out >= fluidboxes_out then
				craft_found = true
			end
		end

		if not craft_found then
			if write_errors then
				if pytest.ignore_recipe(recipe) then
					tech.skipped_recipes[recipe.name] = true
				else
					if first then
						pytest.log('- RECIPE: ' .. recipe.name)
					end
					pytest.log('ERROR: Missing crafting for recipe ' .. recipe.name .. ': ' .. recipe.category ..
						', ingredient_count ' .. ingredient_count .. ', fluidboxes in ' .. fluidboxes_in .. ', fluidboxes out ' .. fluidboxes_out)
					result = false
				end
			else
				result = false
			end
		end
	end

	if result then
		for _, p in pairs(recipe.products or {}) do
			if ((p.amount or 0) > 0 or (p.amount_max or 0) > 0) and (not p.probability or p.probability > 0)
			and	p.type == 'item' then
				if game.item_prototypes[p.name].place_result then
					result = pytest.verify_entity(tech, game.item_prototypes[p.name].place_result.name, write_errors) and result
				end
				if game.item_prototypes[p.name].place_as_equipment_result then
					result = pytest.verify_equipment(tech, game.item_prototypes[p.name].place_as_equipment_result.name, write_errors) and result
				end
			end
		end
	end

	if result and not tech.skipped_recipes[recipe.name] then
		pytest.log('- RECIPE: ' .. recipe.name)
		pytest.add_products(tech, recipe.products)
		tech.unlocked_recipes[recipe.name] = true
	end

	return result
end


function pytest.verify_equipment(tech, name, write_errors)
	local equipment = game.equipment_prototypes[name]

	if equipment.burner_prototype and equipment.energy_consumption > 0 then
		local found = false
		local str = ''
		for fc, i in pairs(equipment.burner_prototype.fuel_categories or {}) do
			if tech.unlocked_fuel_categories[fc] then
				found = true
			end
			str = (str ~= '' and str .. ', ' or '') .. fc
		end

		if not found then
			if write_errors then
				pytest.log('ERROR: Missing fuel category for equipment ' .. name .. ': ' .. str)
			end
			return false
		end
	end

	return true
end


function pytest.verify_tech(tech)
	local result = true

	if tech.name == start_tech_name then
		pytest.init_start_tech(tech)
	elseif game.technology_prototypes[tech.name] then
		local err = false
		local msg = ''

		for _, i in pairs(game.technology_prototypes[tech.name].research_unit_ingredients or {}) do
			tech.required_science_packs[i.name] = true

			if not tech.unlocked_lab_slots[i.name] then
				msg = 'ERROR: Missing lab slot for tech ' .. tech.name .. ': ' .. i.name
				err = true
			end

			if i.type == 'item' then
				if not tech.unlocked_items[i.name] then
					msg = 'ERROR: Missing research ingredient for tech ' .. tech.name .. ': ' .. i.name
					err = true
				end
			else
				if not tech.unlocked_fluids[i.name] then
					msg = 'ERROR: Missing research ingredient for tech ' .. tech.name .. ': ' .. i.name
					err = true
				elseif i.temperature or i.minimum_temperature or i.maximum_temperature then
					local r = false

					for t, _ in pairs(tech.unlocked_fluids[i.name]) do
						if (not i.temperature or i.temperature == t) and (not i.minimum_temperature or i.minimum_temperature <= t) and (not i.maximum_temperature or i.maximum_temperature >= t) then
							r = true
							break
						end
					end

					if not r then
						msg = 'ERROR: Missing research ingredient for tech ' .. tech.name .. ': ' .. i.name ..
							(i.temperature ~= nil and ' temp: ' .. i.temperature or '') ..
							(i.minimum_temperature ~= nil and ' min temp: ' .. i.minimum_temperature or '') ..
							(i.maximum_temperature ~= nil and ' max temp: ' .. i.maximum_temperature or '')

						err = true
					end
				end
			end

			if err then
				pytest.log(msg)
				result = false
			end
		end

		local parent_science_packs = {}

		for _, pr in pairs(tech.prerequisites) do
			parent_science_packs = table.merge(parent_science_packs, pr.required_science_packs)
		end

		for sc, _ in pairs(parent_science_packs) do
			if not tech.required_science_packs[sc] then
				pytest.log("ERROR: Required science pack " .. sc .. " not inherited from prerequisites: " .. table.concat(table.keys(tech.prerequisites), ', '))
				result = false
			end
		end

		for pt, _ in pairs(tech.prerequisites) do
			if tech.unlocked_techs[pt] then
				pytest.log("ERROR: Redundant prerquisite: " .. pt)
				result = false
			else
				tech.unlocked_techs[pt] = true
			end
		end

		if not result then
			return false
		end
	end

	result = true
	local logged_recipes = {}

	while result do
		--pytest.log('START LOOP')
		result = false
		local remove_recipes = {}
		added_recipes = {}

		for r, _ in pairs(tech.recipes) do
			local recipe = game.recipe_prototypes[r] or custom_recipes[r]
			if tech.unlocked_recipes[r] then
				if pytest.ignore_recipe(recipe) then
					remove_recipes[r] = true
				elseif not logged_recipes[r] then
					logged_recipes[r] = true
					pytest.log("ERROR: Recipe is already unlocked: " .. r)
				end
			else
				--pytest.log('CALL PROCESS_RECIPE ' .. r)
				local res = pytest.process_recipe(tech, recipe, false)
				--pytest.log('CALL PROCESS_RECIPE ' .. r .. ' result: ' .. (res and 'true' or 'false'))
				if res then
					remove_recipes[r] = true
				end
				result = result or res
			end
		end

		for r, _ in pairs(added_recipes) do
			tech.recipes[r] = true
		end

		for r, _ in pairs(remove_recipes) do
			tech.recipes[r] = nil
		end
	end

	result = true

	-- Any leftover recipes have failed. Loop through again to write the errors
	for r, _ in pairs(tech.recipes) do
		local recipe = game.recipe_prototypes[r] or custom_recipes[r]
		result = pytest.process_recipe(tech, recipe, true) and result
	end

	return result
end


function pytest.merge_parents(tech)
	for _, p in pairs(tech.prerequisites) do
		tech.unlocked_entities = table.merge(tech.unlocked_entities, p.unlocked_entities)
		tech.unlocked_mining = table.merge(tech.unlocked_mining, p.unlocked_mining)
		tech.unlocked_fuels = table.merge(tech.unlocked_fuels, p.unlocked_fuels)
		tech.unlocked_items = table.merge(tech.unlocked_items, p.unlocked_items)
		tech.recipes = table.merge(tech.recipes, p.skipped_recipes)
		tech.unlocked_recipes = table.merge(tech.unlocked_recipes, p.unlocked_recipes)
		tech.unlocked_techs = table.merge(tech.unlocked_techs, p.unlocked_techs)
		tech.unlocked_lab_slots = table.merge(tech.unlocked_lab_slots, p.unlocked_lab_slots)
		tech.unlocked_equipment = table.merge(tech.unlocked_equipment, p.unlocked_equipment)

		for c, tab in pairs(p.unlocked_crafting) do
			for _, craft in pairs(tab) do
				tech.unlocked_crafting[c] = pytest.insert_crafting_details(tech.unlocked_crafting[c], craft, false)
			end
		end

		for f, temps in pairs(p.unlocked_fluids) do
			tech.unlocked_fluids[f] = table.merge(tech.unlocked_fluids[f] or {}, temps)
		end

		for _, item in pairs(p.unlocked_items) do
			if item.fuel_category and (item.fuel_value or 0) > 0 then
				pytest.add_burnt_result(tech, item)
			end
		end

		for _, e in pairs(tech.unlocked_entities) do
			if e.mineable_properties and e.mineable_properties.required_fluid then
				pytest.add_mining_results(tech, e)
			end
		end
	end
end


function pytest.verify_tech_tree()
	local q = {}
	q.first = 0
	q.last = 0
	q.data = {}
	q.data[0] = pytest.tech(start_tech_name)

	local valid_techs = {}

	while q.first <= q.last do
		local tech = q.data[q.first]
		q.data[q.first] = nil
		q.first = q.first + 1

		pytest.log('TECHNOLOGY: ' .. tech.name)

		pytest.merge_parents(tech)
		local result = pytest.verify_tech(tech)

		if result then
			valid_techs[tech.name] = true

			for _, dep in pairs(tech.dependents) do
				local push = true

				for p, _ in pairs(dep.prerequisites) do
					if not valid_techs[p] then
						push = false
					end
				end

				if push then
					q.last = q.last + 1
					q.data[q.last] = dep
				end
			end
		end
	end
end


script.on_init(function(event)
	pytest.start_log("TECH TREE CHECK")
	pytest.prepare_tech_data()
	pytest.verify_tech_tree()
end)
