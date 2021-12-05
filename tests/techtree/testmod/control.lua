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
local ignored_crafting = {'py-venting', 'py-runoff', 'py-incineration', 'blackhole-energy', 'compost', crafting_launch}
local starting_entities = {'crash-site-assembling-machine-1-repaired', 'crash-site-lab-repaired'}
local added_recipes = {}
local custom_recipes= {}


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

		if tech.enabled then
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

		if entity.fixed_recipe then
			added_recipes[entity.fixed_recipe] = true
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

			for _, fb in pairs(entity.fluidbox_prototypes) do
				if (fb.production_type == 'input' or fb.production_type == 'input-output') and fb.filter then
					input = { type = 'fluid', name = fb.filter.name, minimum_temperature = fb.minimum_temperature, maximum_temperature = fb.maximum_temperature }
				elseif fb.production_type == 'output' and fb.filter then
					output = { type = 'fluid', name = fb.filter.name, temperature = entity.target_temperature }
				end
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
					result = pytest.add_burnt_result(tech, i) and result
				end
			end
		end
	end
end


function pytest.add_item(tech, item_name, source)
	local item = game.item_prototypes[item_name]

	if not tech.unlocked_items[item_name] then
		pytest.log('  - Unlocked item: ' .. item_name .. (source or ''))
		tech.unlocked_items[item_name] = item

		if item.place_result then
			pytest.add_entity(tech, item.place_result.name)
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
		or recipe.name:find('fill%-canister%-') ~= nil or recipe.name:find('empty%-canister%-') ~= nil

	return result
end


function pytest.process_recipe(tech, recipe_name, write_errors)
	local recipe = game.recipe_prototypes[recipe_name] or custom_recipes[recipe_name]

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
		for _, p in pairs(recipe.products) do
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
			and	p.type == 'item' and game.item_prototypes[p.name].place_result then
				result = pytest.verify_entity(tech, game.item_prototypes[p.name].place_result.name, write_errors) and result
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


function pytest.verify_tech(tech)
	pytest.log('TECHNOLOGY: ' .. tech.name)

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
				pytest.log("ERROR: Required science pack not inherited from prerequisites: " .. sc)
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

	while result do
		--pytest.log('START LOOP')
		result = false
		local remove_recipes = {}
		added_recipes = {}

		for r, _ in pairs(tech.recipes) do
			if tech.unlocked_recipes[r] then
				remove_recipes[r] = true
			else
				--pytest.log('CALL PROCESS_RECIPE ' .. r)
				local res = pytest.process_recipe(tech, r, false)
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
		result = pytest.process_recipe(tech, r, true) and result
	end

	return result
end


function pytest.merge_parents(tech)
	for _, p in pairs(tech.prerequisites) do
		tech.unlocked_entities = table.merge(tech.unlocked_entities, p.unlocked_entities)
		tech.unlocked_mining = table.merge(tech.unlocked_mining, p.unlocked_mining)
		tech.unlocked_items = table.merge(tech.unlocked_items, p.unlocked_items)
		tech.unlocked_fuels = table.merge(tech.unlocked_fuels, p.unlocked_fuels)
		tech.recipes = table.merge(tech.recipes, p.skipped_recipes)
		tech.unlocked_recipes = table.merge(tech.unlocked_recipes, p.unlocked_recipes)
		tech.unlocked_techs = table.merge(tech.unlocked_techs, p.unlocked_techs)
		tech.unlocked_lab_slots = table.merge(tech.unlocked_lab_slots, p.unlocked_lab_slots)

		for c, tab in pairs(p.unlocked_crafting) do
			for _, craft in pairs(tab) do
				tech.unlocked_crafting[c] = pytest.insert_crafting_details(tech.unlocked_crafting[c], craft, false)
			end
		end

		for f, temps in pairs(p.unlocked_fluids) do
			tech.unlocked_fluids[f] = table.merge(tech.unlocked_fluids[f] or {}, temps)
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
