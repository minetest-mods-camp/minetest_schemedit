-- advschem/init.lua

advschem = {}

local path       = minetest.get_worldpath().."/advschem.mt"
advschem.markers = {}

-- [local function] Renumber table
local function renumber(t)
	local res = {}
	for _, i in pairs(t) do
		res[#res + 1] = i
	end
	return res
end

---
--- Formspec API
---

local contexts = {}
local form_data = {}
local tabs = {}
local forms = {}

-- [function] Add form
function advschem.add_form(name, def)
	def.name = name
	forms[name] = def

	if def.tab then
		tabs[#tabs + 1] = name
	end
end

-- [function] Generate tabs
function advschem.generate_tabs(current)
	local retval = "tabheader[0,0;tabs;"
	for _, t in pairs(tabs) do
		local f = forms[t]
		if f.tab ~= false and f.caption then
			retval = retval..f.caption..","

			if type(current) ~= "number" and current == f.name then
				current = _
			end
		end
	end
	retval = retval:sub(1, -2) -- Strip last comma
	retval = retval..";"..current.."]" -- Close tabheader
	return retval
end

-- [function] Handle tabs
function advschem.handle_tabs(pos, name, fields)
	local tab = tonumber(fields.tabs)
	if tab and tabs[tab] and forms[tabs[tab]] then
		advschem.show_formspec(pos, name, forms[tabs[tab]].name)
		return true
	end
end

-- [function] Show formspec
function advschem.show_formspec(pos, player, tab, show, ...)
	if forms[tab] then
		if type(player) == "string" then
			player = minetest.get_player_by_name(player)
		end
		local name = player:get_player_name()

		if show ~= false then
			if not form_data[name] then
				form_data[name] = {}
			end

			local form = forms[tab].get(form_data[name], pos, name, ...)
			if forms[tab].tab then
				form = form..advschem.generate_tabs(tab)
			end

			minetest.show_formspec(name, "advschem:"..tab, form)
			contexts[name] = pos

			-- Update player attribute
			if forms[tab].cache_name ~= false then
				player:set_attribute("advschem:tab", tab)
			end
		else
			minetest.close_formspec(pname, "advschem:"..tab)
		end
	end
end

-- [event] On receive fields
minetest.register_on_player_receive_fields(function(player, formname, fields)
	local formname = formname:split(":")

	if formname[1] == "advschem" and forms[formname[2]] then
		local handle = forms[formname[2]].handle
		local name = player:get_player_name()
		if contexts[name] then
			if not form_data[name] then
				form_data[name] = {}
			end

			if not advschem.handle_tabs(contexts[name], name, fields) and handle then
				handle(form_data[name], contexts[name], name, fields)
			end
		end
	end
end)

-- [event] Transfer probabilities and force place on item placement into node
minetest.register_on_placenode(function(pos, newnode, player, oldnode, itemstack)
	local smeta = itemstack:get_meta():to_table().fields
	local nmeta = minetest.get_meta(pos)
	if smeta.advschem_prob then
		nmeta:set_string("advschem_prob", smeta_advschem_prob)
	end
	if smeta.advschem_force_place then
		nmeta:set_string("advschem_force_place", smeta_advschem_force_place)
	end
end)

-- Helper function. Scans probabilities of all nodes in the given area and returns a prob_list
advschem.scan_metadata = function(pos1, pos2)
	local prob_list = {}

	for x=pos1.x, pos2.x do
	for y=pos1.y, pos2.y do
	for z=pos1.z, pos2.z do
		local scanpos = {x=x, y=y, z=z}
		local node = minetest.get_node_or_nil(scanpos)

		local prob, force_place
		if node == nil or node.name == "advschem:void" then
			prob = 0
			force_place = false
		else
			local meta = minetest.get_meta(scanpos)

			prob = tonumber(meta:get_string("advschem_prob")) or 127
			local fp = meta:get_string("advschem_force_place")
			if fp == "true" then
				force_place = true
			else
				force_place = false
			end
		end

		local ostrpos = minetest.pos_to_string(scanpos)
		prob_list[ostrpos] = {
			pos = scanpos,
			prob = prob,
			force_place = force_place,
		}
	end
	end
	end

	return prob_list
end

-- Sets probability and force_place metadata of an item.
-- Also updates item description.
-- The itemstack is updated in-place.
local function set_item_metadata(itemstack, prob, force_place)
	local smeta = itemstack:get_meta()
	local prob_desc = "\nProbability: "..(prob) or
			smeta:get_string("advschem_prob") or "Not Set"
	-- Update probability
	if prob and prob >= 0 and prob < 127 then
		smeta:set_string("advschem_prob", tostring(prob))
	elseif prob and prob == 127 then
		-- Clear prob metadata for default probability
		prob_desc = ""
		smeta:set_string("advschem_prob", nil)
	else
		prob_desc = "\nProbability: "..(smeta:get_string("advschem_prob") or
				"Not Set")
	end

	-- Update force place if value is not nil
	if force_place then
		smeta:set_string("advschem_force_place", "true")
	end

	-- Update description
	local desc = minetest.registered_items[itemstack:get_name()].description
	local meta_desc = smeta:get_string("description")
	if meta_desc and meta_desc ~= "" then
		desc = meta_desc
	end

	local original_desc = smeta:get_string("original_description")
	if original_desc and original_desc ~= "" then
		desc = original_desc
	else
		smeta:set_string("original_description", desc)
	end

	local force_desc = ""
	if smeta:get_string("advschem_force_place") == "true" then
		force_desc = "\n".."Force Place"
	end

	desc = desc..minetest.colorize("#D79E9E", prob_desc..force_desc)

	smeta:set_string("description", desc)

	return itemstack
end

---
--- Formspec Tabs
---

advschem.add_form("main", {
	tab = true,
	caption = "Main",
	get = function(self, pos, name)
		local meta = minetest.get_meta(pos):to_table().fields
		local strpos = minetest.pos_to_string(pos)

		local border_button
		if meta.schem_border == "true" and advschem.markers[strpos] then
			border_button = "button[3.5,7.5;3,1;border;Hide Border]"
		else
			border_button = "button[3.5,7.5;3,1;border;Show Border]"
		end

		-- TODO: Show information regarding volume, pos1, pos2, etc... in formspec
		return [[
			size[7,8]
			label[0.5,-0.1;Position: ]]..strpos..[[]
			label[3,-0.1;Owner: ]]..name..[[]

			field[0.8,1;5,1;name;Schematic Name:;]]..(meta.schem_name or "")..[[]
			button[5.3,0.69;1.2,1;save_name;Save]
			tooltip[save_name;Save schematic name]
			field_close_on_enter[name;false]

			button[0.5,1.5;6,1;export;Export Schematic]
			label[0.5,2.2;Schematic will be exported as a .mts file and stored in]
			label[0.5,2.45;<minetest dir>/worlds/<worldname>/schems/<name>.mts]

			field[0.8,7;2,1;x;X-Size:;]]..meta.x_size..[[]
			field[2.8,7;2,1;y;Y-Size:;]]..meta.y_size..[[]
			field[4.8,7;2,1;z;Z-Size:;]]..meta.z_size..[[]
			field_close_on_enter[x;false]
			field_close_on_enter[y;false]
			field_close_on_enter[z;false]

			button[0.5,7.5;3,1;save;Save Size]
		]]..
		border_button
	end,
	handle = function(self, pos, name, fields)
		local realmeta = minetest.get_meta(pos)
		local meta = realmeta:to_table().fields
		local strpos = minetest.pos_to_string(pos)

		-- Toggle border
		if fields.border then
			if meta.schem_border == "true" and advschem.markers[strpos] then
				advschem.unmark(pos)
				meta.schem_border = "false"
			else
				advschem.mark(pos)
				meta.schem_border = "true"
			end
		end

		local update_positions = false
		-- Save size vector values
		if (fields.save or fields.key_enter_field == "x" or
				fields.key_enter_field == "y" or fields.key_enter_field == "z")
				and (fields.x and fields.y and fields.z and fields.x ~= ""
				and fields.y ~= "" and fields.z ~= "") then
			local x, y, z = tonumber(fields.x), tonumber(fields.y), tonumber(fields.z)

			if x then
				meta.x_size = math.max(x, 1)
			end
			if y then
				meta.y_size = math.max(y, 1)
			end
			if z then
				meta.z_size = math.max(z, 1)
			end

			-- Set positions to be updated
			update_positions = true
		end

		-- Save schematic name
		if fields.save_name or fields.key_enter_field == "name" and fields.name and
				fields.name ~= "" then
			meta.schem_name = fields.name
		end

		-- Export schematic
		if fields.export and meta.schem_name and meta.schem_name ~= "" then
			local pos1, pos2 = advschem.size(pos)
			local path = minetest.get_worldpath().."/schems/"
			minetest.mkdir(path)

			local plist = advschem.scan_metadata(pos1, pos2)
			local probability_list = {}
			for _, i in pairs(plist) do
				local prob = i.prob
				if i.force_place == true then
					prob = prob + 128
				end

				probability_list[#probability_list + 1] = {
					pos = minetest.string_to_pos(_),
					prob = prob,
				}
			end

			local slist = minetest.deserialize(meta.slices)
			local slice_list = {}
			for _, i in pairs(slist) do
				slice_list[#slice_list + 1] = {
					ypos = pos.y + i.ypos,
					prob = i.prob,
				}
			end

			local filepath = path..meta.schem_name..".mts"
			local res = minetest.create_schematic(pos1, pos2, probability_list, filepath, slice_list)

			if res then
				minetest.chat_send_player(name, minetest.colorize("#00ff00",
						"Exported schematic to "..filepath))
			else
				minetest.chat_send_player(name, minetest.colorize("red",
						"Failed to export schematic to "..filepath))
			end
		end

		-- Save meta before updating visuals
		local inv = realmeta:get_inventory():get_lists()
		realmeta:from_table({fields = meta, inventory = inv})

		-- Update border
		if not fields.border and meta.schem_border == "true" then
			advschem.mark(pos)
		end

		-- Update formspec
		if not fields.quit then
			advschem.show_formspec(pos, minetest.get_player_by_name(name), "main")
		end

		if update_positions then
			local pos1, pos2 = advschem.size(pos)
			pos1, pos2 = advschem.sort_pos(pos1, pos2)
		end
	end,
})

advschem.add_form("prob", {
	tab = true,
	caption = "Probability",
	get = function(self, pos, name)
		local meta = minetest.get_meta(pos)
		local inventory = meta:get_inventory()
		local stack = inventory:get_stack("probability", 1)
		local stringpos = pos.x..","..pos.y..","..pos.z

		local form = [[
			size[8,6]
			list[nodemeta:]]..stringpos..[[;probability;0,0;1,1;]
			label[0,1;Probability is a number between 0 and 127.]
			list[current_player;main;0,1.5;8,4;]
			listring[nodemeta:]]..stringpos..[[;probability]
			listring[current_player;main]
		]]

		if stack:get_name() ~= "" then
			local smeta = stack:get_meta():to_table().fields

			form = form .. [[
				field[1.3,0.4;2,1;probability;Probability:;]]..
						(smeta.advschem_prob or "127").."]" ..
			[[
				field_close_on_enter[probability;false]
				checkbox[3.1,0.1;force_place;Force Place;]]..(smeta.advschem_force_place or "false")..[[]
				button[5,0.1;1.5,1;rst;Reset]
				button[6.5,0.1;1.5,1;save;Save]
			]]
		else
			form = form .. [[
				label[1,0.2;Insert schematc node probability tool into slot.]
			]]
		end

		return form
	end,
	handle = function(self, pos, name, fields)
		local meta = minetest.get_meta(pos)
		local inventory = meta:get_inventory()
		local stack = inventory:get_stack("probability", 1)
		local smeta = stack:get_meta()

		if stack:get_name() ~= "" then
			if fields.rst then
				smeta:set_string("advschem_prob", nil)
				smeta:set_string("advschem_force_place", nil)

				-- Reset description
				local original_desc = smeta:get_string("original_desc")
				if not original_desc or original_desc == "" then
					original_desc = minetest.registered_items[stack:get_name()].description
				end

				smeta:set_string("description", original_desc)
			elseif fields.force_place or fields.save or
					fields.key_enter_field == "probability" then

				local prob = tonumber(fields.probability)
				local force_place

				if fields.force_place ~= nil then
					if fields.force_place == "true" then
						force_place = true
					elseif fields.force_place == "false" then
						force_place = false
					end
				end

				set_item_metadata(stack, prob, force_place)

				advschem.show_formspec(pos, minetest.get_player_by_name(name), "prob")
			end

			-- Update itemstack
			inventory:set_stack("probability", 1, stack)

			-- Refresh formspec on reset or force placement change
			if fields.rst or fields.force_place then
				advschem.show_formspec(pos, minetest.get_player_by_name(name), "prob")
			end
		end
	end,
})

advschem.add_form("slice", {
	caption = "Y-Slice",
	tab = true,
	get = function(self, pos, name, visible_panel)
		local meta = minetest.get_meta(pos):to_table().fields

		self.selected = self.selected or 1
		local selected = tostring(self.selected)
		local slice_list = minetest.deserialize(meta.slices)
		local slices = ""
		for _, i in pairs(slice_list) do
			local insert = "Y = "..tostring(i.ypos).."; Probability = "..tostring(i.prob)
			slices = slices..minetest.formspec_escape(insert)..","
		end
		slices = slices:sub(1, -2) -- Remove final comma

		local form = [[
			size[7,6]
			table[0,0;6.8,4;slices;]]..slices..[[;]]..selected..[[]
		]]

		if self.panel_add or self.panel_edit then
			local ypos_default, prob_default = "", ""
			local done_button = "button[5,5.18;2,1;done_add;Done]"
			if self.panel_edit then
				done_button = "button[5,5.18;2,1;done_edit;Done]"
				ypos_default = slice_list[self.selected].ypos
				prob_default = slice_list[self.selected].prob
			end

			form = form..[[
				field[0.3,5.5;2.5,1;ypos;Y-Position (max ]]..(meta.y_size - 1)..[[):;]]..ypos_default..[[]
				field[2.8,5.5;2.5,1;prob;Probability (0-127):;]]..prob_default..[[]
				field_close_on_enter[ypos;false]
				field_close_on_enter[prob;false]
			]]..done_button
		end

		if not self.panel_edit then
			form = form.."button[0,4;2,1;add;+ Add Slice]"
		end

		if slices ~= "" and self.selected and not self.panel_add then
			if not self.panel_edit then
				form = form..[[
					button[2,4;2,1;remove;- Remove Slice]
					button[4,4;2,1;edit;+/- Edit Slice]
				]]
			else
				form = form..[[
					button[0,4;2,1;remove;- Remove Slice]
					button[2,4;2,1;edit;+/- Edit Slice]
				]]
			end
		end

		return form
	end,
	handle = function(self, pos, name, fields)
		local meta = minetest.get_meta(pos)
		local player = minetest.get_player_by_name(name)

		if fields.slices then
			local slices = fields.slices:split(":")
			self.selected = tonumber(slices[2])
		end

		if fields.add then
			if not self.panel_add then
				self.panel_add = true
				advschem.show_formspec(pos, player, "slice")
			else
				self.panel_add = nil
				advschem.show_formspec(pos, player, "slice")
			end
		end

		local ypos, prob = tonumber(fields.ypos), tonumber(fields.prob)
		if (fields.done_add or fields.done_edit) and fields.ypos and fields.prob and
		fields.ypos ~= "" and fields.prob ~= "" and ypos and prob and
				 ypos <= (meta:get_int("y_size") - 1) and prob >= 0 and prob <= 255 then
			local slice_list = minetest.deserialize(meta:get_string("slices"))
			local index = #slice_list + 1
			if fields.done_edit then
				index = self.selected
			end

			slice_list[index] = {ypos = ypos, prob = prob}

			meta:set_string("slices", minetest.serialize(slice_list))

			-- Update and show formspec
			self.panel_add = nil
			advschem.show_formspec(pos, player, "slice")
		end

		if fields.remove and self.selected then
			local slice_list = minetest.deserialize(meta:get_string("slices"))
			slice_list[self.selected] = nil
			meta:set_string("slices", minetest.serialize(renumber(slice_list)))

			-- Update formspec
			self.selected = 1
			self.panel_edit = nil
			advschem.show_formspec(pos, player, "slice")
		end

		if fields.edit then
			if not self.panel_edit then
				self.panel_edit = true
				advschem.show_formspec(pos, player, "slice")
			else
				self.panel_edit = nil
				advschem.show_formspec(pos, player, "slice")
			end
		end
	end,
})

advschem.add_form("probtool", {
	cache_name = false,
	caption = "Schematic Node Probability Tool",
	get = function(self, pos, name)
		local player = minetest.get_player_by_name(name)
		if not player then
			return
		end
		local probtool = player:get_wielded_item()
		if probtool:get_name() ~= "advschem:probtool" then
			return
		end

		local meta = probtool:get_meta()
		local prob = tonumber(meta:get_string("advschem_prob"))
		local force_place = meta:get_string("advschem_force_place")

		if not prob then
			prob = 127
		end
		if force_place == nil or force_place == "" then
			force_place = "false"
		end
		local form = "size[5,4]"..
			"label[0,0;Schematic Node Probability Tool]"..
			"field[0.75,1;4,1;prob;Probability;"..prob.."]"..
			"button_exit[0.25,3;2,1;cancel;Cancel]"..
			"button_exit[2.75,3;2,1;submit;Okay]"..
			"tooltip[submit;Use the new probability value for this tool]"..
			"field_close_on_enter[prob;false]"
		return form
	end,
	handle = function(self, pos, name, fields)
		if fields.submit then
			local prob = tonumber(fields.prob)
			if prob then
				local player = minetest.get_player_by_name(name)
				if not player then
					return
				end
				local probtool = player:get_wielded_item()
				if probtool:get_name() ~= "advschem:probtool" then
					return
				end

				set_item_metadata(probtool, prob, false)

				player:set_wielded_item(probtool)

				-- TODO: Force place
			end
		end
	end,
})

---
--- API
---

--- Copies and modifies positions `pos1` and `pos2` so that each component of
-- `pos1` is less than or equal to the corresponding component of `pos2`.
-- Returns the new positions.
function advschem.sort_pos(pos1, pos2)
	if not pos1 or not pos2 then
		return
	end

	pos1, pos2 = table.copy(pos1), table.copy(pos2)
	if pos1.x > pos2.x then
		pos2.x, pos1.x = pos1.x, pos2.x
	end
	if pos1.y > pos2.y then
		pos2.y, pos1.y = pos1.y, pos2.y
	end
	if pos1.z > pos2.z then
		pos2.z, pos1.z = pos1.z, pos2.z
	end
	return pos1, pos2
end

-- [function] Prepare size
function advschem.size(pos)
	local pos1   = vector.new(pos)
	local meta   = minetest.get_meta(pos)
	local node   = minetest.get_node(pos)
	local param2 = node.param2
	local size   = {
		x = meta:get_int("x_size"),
		y = math.max(meta:get_int("y_size") - 1, 0),
		z = meta:get_int("z_size"),
	}

	if param2 == 1 then
		local new_pos = vector.add({x = size.z, y = size.y, z = -size.x}, pos)
		pos1.x = pos1.x + 1
		new_pos.z = new_pos.z + 1
		return pos1, new_pos
	elseif param2 == 2 then
		local new_pos = vector.add({x = -size.x, y = size.y, z = -size.z}, pos)
		pos1.z = pos1.z - 1
		new_pos.x = new_pos.x + 1
		return pos1, new_pos
	elseif param2 == 3 then
		local new_pos = vector.add({x = -size.z, y = size.y, z = size.x}, pos)
		pos1.x = pos1.x - 1
		new_pos.z = new_pos.z - 1
		return pos1, new_pos
	else
		local new_pos = vector.add(size, pos)
		pos1.z = pos1.z + 1
		new_pos.x = new_pos.x - 1
		return pos1, new_pos
	end
end

-- [function] Mark region
function advschem.mark(pos)
	advschem.unmark(pos)

	local id = minetest.pos_to_string(pos)
	local owner = minetest.get_meta(pos):get_string("owner")
	local pos1, pos2 = advschem.size(pos)
	pos1, pos2 = advschem.sort_pos(pos1, pos2)

	local thickness = 0.2
	local sizex, sizey, sizez = (1 + pos2.x - pos1.x) / 2, (1 + pos2.y - pos1.y) / 2, (1 + pos2.z - pos1.z) / 2
	local m = {}
	local low = true
	local offset

	-- XY plane markers
	for _, z in ipairs({pos1.z - 0.5, pos2.z + 0.5}) do
		if low then
			offset = -0.01
		else
			offset = 0.01
		end
		local marker = minetest.add_entity({x = pos1.x + sizex - 0.5, y = pos1.y + sizey - 0.5, z = z + offset}, "advschem:display")
		if marker ~= nil then
			marker:set_properties({
				visual_size={x=(sizex+0.01) * 2, y=sizey * 2},
				collisionbox = {-sizex, -sizey, -thickness, sizex, sizey, thickness},
			})
			marker:get_luaentity().id = id
			marker:get_luaentity().owner = owner
			table.insert(m, marker)
		end
		low = false
	end

	low = true
	-- YZ plane markers
	for _, x in ipairs({pos1.x - 0.5, pos2.x + 0.5}) do
		if low then
			offset = -0.01
		else
			offset = 0.01
		end

		local marker = minetest.add_entity({x = x + offset, y = pos1.y + sizey - 0.5, z = pos1.z + sizez - 0.5}, "advschem:display")
		if marker ~= nil then
			marker:set_properties({
				visual_size={x=(sizez+0.01) * 2, y=sizey * 2},
				collisionbox = {-thickness, -sizey, -sizez, thickness, sizey, sizez},
			})
			marker:set_yaw(math.pi / 2)
			marker:get_luaentity().id = id
			marker:get_luaentity().owner = owner
			table.insert(m, marker)
		end
		low = false
	end

	advschem.markers[id] = m
	return true
end

-- [function] Unmark region
function advschem.unmark(pos)
	local id = minetest.pos_to_string(pos)
	if advschem.markers[id] then
		local retval
		for _, entity in ipairs(advschem.markers[id]) do
			entity:remove()
			retval = true
		end
		return retval
	end
end

---
--- Registrations
---

-- [priv] schematic_override
minetest.register_privilege("schematic_override", {
	description = "Allows you to access advschem nodes not owned by you",
	give_to_singleplayer = false,
})

-- [node] Schematic creator
minetest.register_node("advschem:creator", {
	description = "Schematic Creator",
	tiles = {"advschem_creator_top.png", "advschem_creator_bottom.png",
			"advschem_creator_sides.png"},
	groups = { dig_immediate = 3},
	paramtype2 = "facedir",
	is_ground_content = false,

	after_place_node = function(pos, player)
		local name = player:get_player_name()
		local meta = minetest.get_meta(pos)

		meta:set_string("owner", name)
		meta:set_string("infotext", "Schematic Creator\n(owned by "..name..")")
		meta:set_string("prob_list", minetest.serialize({}))
		meta:set_string("slices", minetest.serialize({}))

		local node = minetest.get_node(pos)
		local dir  = minetest.facedir_to_dir(node.param2)

		meta:set_int("x_size", 1)
		meta:set_int("y_size", 1)
		meta:set_int("z_size", 1)

		local inv = meta:get_inventory()
		inv:set_size("probability", 1)

		local pos1, pos2 = advschem.size(pos)

		-- Don't take item from itemstack
		return true
	end,
	can_dig = function(pos, player)
		local name = player:get_player_name()
		local meta = minetest.get_meta(pos)
		if meta:get_string("owner") == name or
				minetest.check_player_privs(player, "schematic_override") == true then
			return true
		end

		return false
	end,
	on_rightclick = function(pos, node, player)
		local meta = minetest.get_meta(pos)
		local name = player:get_player_name()
		if meta:get_string("owner") == name or
				minetest.check_player_privs(player, "schematic_override") == true then
			-- Get player attribute
			local tab = player:get_attribute("advschem:tab")
			if not forms[tab] or not tab then
				tab = "main"
			end

			advschem.show_formspec(pos, player, tab, true)
		end
	end,
	after_destruct = function(pos)
		advschem.unmark(pos)
	end,

	-- Update formspec when items are added to or taken from the probability inventory
	on_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname == "probability" then
			advschem.show_formspec(pos, player, "prob", true)
		end
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname == "probability" then
			local itemstring = stack:get_name()
			if itemstring ~= "advschem:probtool" then
				return 0
			end
		end
		return stack:get_count()
	end,
	on_metadata_inventory_take = function(pos, listname, index, stack, player)
		if listname == "probability" then
			advschem.show_formspec(pos, player, "prob", true)
		end
	end,
})

minetest.register_tool("advschem:probtool", {
	description = "Schematic Node Probability Tool",
	wield_image = "advschem_probtool.png",
	inventory_image = "advschem_probtool.png",
	on_use = function(itemstack, placer, pointed_thing)
		advschem.show_formspec(placer:getpos(), placer, "probtool", true)
	end,
	on_place = function(itemstack, placer, pointed_thing)
		pos = pointed_thing.under
		local nmeta = minetest.get_meta(pos)
		local imeta = itemstack:get_meta()
		local prob = tonumber(imeta:get_string("advschem_prob"))
		local force_place = imeta:get_string("advschem_force_place")

		if not prob or prob == 127 then
			nmeta:set_string("advschem_prob", nil)
		else
			nmeta:set_string("advschem_prob", prob)
		end
		if force_place == "true" then
			nmeta:set_string("advschem_force_place", "true")
		else
			nmeta:set_string("advschem_force_place", nil)
		end
		return itemstack
	end,
})

minetest.register_node("advschem:void", {
	description = "Schematic Void",
	tiles = { "advschem_void.png" },
	drawtype = "nodebox",
	is_ground_content = false,
	paramtype = "light",
	walkable = false,
	sunlight_propagates = true,
	node_box = {
		type = "fixed",
		fixed = {
			{ -4/16, -4/16, -4/16, 4/16, 4/16, 4/16 },
		},
	},
	groups = { dig_immediate = 3},
})

-- [entity] Display
minetest.register_entity("advschem:display", {
	initial_properties = {
		visual = "upright_sprite",
		textures = {"advschem_border.png"},
		visual_size = {x=10, y=10},
		physical = false,
	},
	on_step = function(self, dtime)
		if not self.id then
			self.object:remove()
		elseif not advschem.markers[self.id] then
			self.object:remove()
		end
	end,
	on_punch = function(self, hitter)
		local pos = minetest.string_to_pos(self.id)
		local meta = minetest.get_meta(pos)
		if meta:get_string("owner") == hitter:get_player_name() or
				minetest.check_player_privs(hitter, "schematic_override") == true then
			advschem.unmark(pos)
			meta:set_string("schem_border", "false")
		end
	end,
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
})

-- [chatcommand] Place schematic
minetest.register_chatcommand("placeschem", {
	description = "Place schematic at the position specified or the current "..
			"player position (loaded from "..minetest.get_worldpath().."/schems/)",
	privs = {debug = true},
	params = "[<schematic name>.mts] (<x> <y> <z>)",
	func = function(name, param)
		local schem, p = string.match(param, "^([^ ]+) *(.*)$")
		local pos      = minetest.string_to_pos(p)

		if not pos then
			pos = minetest.get_player_by_name(name):get_pos()
		end

		return true, "Success: "..dump(minetest.place_schematic(pos,
				minetest.get_worldpath().."/schems/"..schem..".mts", "random", nil, false))
	end,
})

