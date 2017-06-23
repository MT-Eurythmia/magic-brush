minetest.register_privilege("brush", "Allows players to use the brush")

minetest.register_craftitem("brush:brush", {
	inventory_image = "brush_brush.png",
	description = "Magic Brush",
	stack_max = 1,
	range = 15,
	on_place = function(itemstack, placer, pointed_thing)
		if not minetest.check_player_privs(placer, "brush") then
			minetest.chat_send_player(placer:get_player_name(), "Missing privilege: brush")
			return
		end

		if not pointed_thing or pointed_thing.type ~= "node" then
			return
		end

		local player_pos = placer:get_pos()
		if minetest.get_node({x=player_pos.x, y=player_pos.y+1,z=player_pos.z}).name ~= "air" then
			return
		end

		local meta = itemstack:get_meta()
		local radius = meta:get_int("radius")
		if radius == 0 then
			radius = 2
		end
		local height = meta:get_int("height")
		if height == 0 then
			height = 2
		end
		local backward = meta:get_int("backward")
		local replace_air = meta:get_string("replace_air") == "true"
		local replace_air_backward = meta:get_string("replace_air_backward") ~= "false"

		-- Compute the true sphere radius
		-- We use the formula R = a^2 x b / (4 x Ar),
		-- b being the triangle base: 2 x radius + 1,
		-- a being another side of the triangle: sqrt(height^2 + (radius + 1/2)^2)
		-- and Ar being the area of the triangle: height * (radius + 1/2)
		local sphere_radius
		do
			local a = 2 * radius
			local b = math.sqrt(height ^ 2 + (radius - 0.5) ^ 2)
			local area = height * (radius - 0.5)
			sphere_radius = math.floor(a^2 * b / (4 * area))
		end

		-- Compute the sphere center position
		local node_pos = pointed_thing.under
		local dir = {x = 0, y = 0, z = 0}

		local face_pos = minetest.pointed_thing_to_face_pos(placer, pointed_thing)
		for _, d in ipairs({"x", "y", "z"}) do
			if face_pos[d] == node_pos[d] + 0.5 then
				dir[d] = 1
				break
			elseif face_pos[d] == node_pos[d] - 0.5 then
				dir[d] = -1
				break
			end
		end

		local sphere_center = vector.add(node_pos, vector.multiply(dir, -(sphere_radius - height)))

		-- Get the filling node
		local node
		do
			local inventory = placer:get_inventory()
			local item = inventory:get_stack("main", placer:get_wield_index()+1):get_name()
			if minetest.registered_nodes[item] then
				node = item
			else
				node = minetest.get_node(pointed_thing.under).name
			end
		end
		local node_id = minetest.get_content_id(node)
		local air_id = minetest.get_content_id("air")

		-- Fill the area
		local pos1 = vector.subtract(sphere_center, sphere_radius)
		local pos2 = vector.add(sphere_center, sphere_radius)
		local manip = minetest.get_voxel_manip()
		local emerged_pos1, emerged_pos2 = manip:read_from_map(pos1, pos2)
		local area = VoxelArea:new({MinEdge=emerged_pos1, MaxEdge=emerged_pos2})
		local data = manip:get_data()

		local min_radius, max_radius = sphere_radius * (sphere_radius - 1), sphere_radius * (sphere_radius + 1)
		local offset_x, offset_y, offset_z = sphere_center.x - area.MinEdge.x, sphere_center.y - area.MinEdge.y, sphere_center.z - area.MinEdge.z
		local stride_z, stride_y = area.zstride, area.ystride

		local function do_replace(pos, new_y)
			local i = new_y + (pos.x + offset_x)
			for _, k in ipairs({"x", "y", "z"}) do
				if dir[k] == 1 and pos[k] > sphere_radius - height then
					if not replace_air or data[i] == air_id then
						data[i] = node_id
					end
				elseif dir[k] == 1 and pos[k] > sphere_radius - height - backward then
					if not (replace_air_backward or replace_air) or data[i] == air_id then
						data[i] = node_id
					end
				elseif dir[k] == -1 and pos[k] < -(sphere_radius - height) then
					if not replace_air or data[i] == air_id then
						data[i] = node_id
					end
				elseif dir[k] == -1 and pos[k] < -(sphere_radius - height - backward) then
					if not (replace_air_backward or replace_air) or data[i] == air_id then
						data[i] = node_id
					end
				end
			end
		end

		for z = -sphere_radius, sphere_radius do
			-- Offset contributed by z plus 1 to make it 1-indexed
			local new_z = (z + offset_z) * stride_z + 1
			for y = -sphere_radius, sphere_radius do
				local new_y = new_z + (y + offset_y) * stride_y
				for x = -sphere_radius, sphere_radius do
					local squared = x * x + y * y + z * z
					if squared <= max_radius then
						do_replace({x=x,y=y,z=z}, new_y)
					end
				end
			end
		end

		manip:set_data(data)
		manip:write_to_map()
	end,

	on_use = function(itemstack, user, pointed_thing)
		local meta = itemstack:get_meta()
		local radius = meta:get_int("radius")
		if radius == 0 then
			radius = 2
		end
		local height = meta:get_int("height")
		if height == 0 then
			height = 2
		end
		local backward = meta:get_int("backward")
		local replace_air = meta:get_string("replace_air")
		local replace_air_backward = meta:get_string("replace_air_backward")
		if replace_air_backward == "" then
			replace_air_backward = "true"
		end
		minetest.show_formspec(user:get_player_name(), "brush:brush_config",
			"size[5,4]"..
			"field[0.3,0.5;2,1;radius;Radius;"..radius.."]"..
			"field[0.3,1.5;2,1;height;Height;"..height.."]"..
			"field[0.3,2.5;2,1;backward;Backward length;"..backward.."]"..
			"checkbox[2.2,0;replace_air;Replace air only;"..replace_air.."]"..
			"checkbox[2.2,1;replace_air_backward;Replace air only\nwhen going backward;"..replace_air_backward.."]"..
			"button_exit[1.4,3.2;2,1;exit;Proceed]")
	end
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "brush:brush_config" then
		return
	end

	local itemstack = player:get_wielded_item()
	if itemstack:get_name() ~= "brush:brush" then
		minetest.chat_send_player(player:get_player_name(), "You must hold the brush.")
		return
	end

	local meta = itemstack:get_meta()
	if fields.replace_air ~= nil then
		meta:set_string("replace_air", fields.replace_air)
		player:set_wielded_item(itemstack)
		return
	elseif fields.replace_air_backward ~= nil then
		meta:set_string("replace_air_backward", fields.replace_air_backward)
		player:set_wielded_item(itemstack)
		return
	end

	if not fields.exit then
		return
	end
	if not tonumber(fields.radius) or not tonumber(fields.height) or not tonumber(fields.backward) then
		minetest.chat_send_player(player:get_player_name(), "Malformed number.")
		return
	end
	if tonumber(fields.radius) > 30 then
		minetest.chat_send_player(player:get_player_name(), "You cannot set a radius over 30.")
		return
	end

	meta:set_int("radius", fields.radius)
	meta:set_int("height", fields.height)
	meta:set_int("backward", fields.backward)
	player:set_wielded_item(itemstack)
end)
