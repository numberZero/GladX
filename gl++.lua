#!/usr/bin/lua

dofile("helpers.lua")

local parse_xml = require("lxp.lom").parse

local function read_file(filename)
	local f = io.open(filename, "r")
	local data = f:read("a")
	f:close()
	return data
end

local function cmp_ver(f1, f2)
	return f1.version < f2.version
end

local function shallow_copy(table)
	local copy = {}
	for key, value in pairs(table) do
		copy[key] = value
	end
	return copy
end

local function print_set(set, prefix, suffix)
	local list = {}
	for key, _ in pairs(set) do
		list[#list + 1] = key
	end
	table.sort(list)
	for _, value in ipairs(list) do
		io.write(prefix, value, suffix)
	end
end

local function print_set_oneline(set, sep)
	local list = {}
	for key, _ in pairs(set) do
		list[#list + 1] = key
	end
	table.sort(list)
	for _, value in ipairs(list) do
		if _ ~= 1 then
			io.write(sep)
		end
		io.write(value)
	end
end

local spec = parse_xml(read_file("gl.xml"))

local apis = {}
for _, section in ipairs(spec) do
	if section.tag == "feature" then
		local api = apis[section.attr.api]
		if not api then
			api = {}
			apis[section.attr.api] = api
		end
		local feature = {
			api = section.attr.api,
			version = section.attr.number,
			name = section.attr.name,
			xml = section
		}
		api[#api + 1] = feature
		api[feature.version] = feature
	end
end

for api, features in pairs(apis) do
	table.sort(features, cmp_ver)
	local base_feature = {
		types = {},
		enums = {},
		commands = {},
	}
	for _, feature in ipairs(features) do
		feature.types = shallow_copy(base_feature.types)
		feature.enums = shallow_copy(base_feature.enums)
		feature.commands = shallow_copy(base_feature.commands)
		for _, section in ipairs(feature.xml) do
			if (section.tag == "require" or section.tag == "remove") and section.attr.profile ~= "compatibility" then
				local val = section.tag == "require" or nil
				for _, entry in ipairs(section) do
					if entry.tag == "type" or entry.tag == "enum" or entry.tag == "command" then
						feature[entry.tag .. "s"][entry.attr.name] = val
					end
				end
			end
		end
		base_feature = feature
	end
end

----------------------------------------
local feature = apis["gl"]["3.3"]
----------------------------------------

local function parse_groups(enums)
	local groups = {}
	for _, section in ipairs(spec) do
		if section.tag == "groups" then
			for _, entry in ipairs(section) do
				if entry.tag == "group" then
					local gname = entry.attr.name
					groups[gname] = {
						name = gname,
						type = entry.attr.type,
						enums = {},
						xml = entry
					}
				end
			end
			break
		end
	end
	for gname, group in pairs(groups) do
		for _, entry in ipairs(group.xml) do
			if entry.tag == "enum" then
				local ename = entry.attr.name
				local enum = enums[ename]
				if enum then
					enum.groups[gname] = true
					group.enums[ename] = true
				end
			end
		end
	end
	return groups
end

local function parse_enums(enums, groups)
	for _, section in ipairs(spec) do
		if section.tag == "enums" then
			local gname = section.attr.group
			local t = section.attr.type or "list"
			local group = gname and groups[gname]
			if gname and not group then
				group = {
					name = gname,
					enums = {},
				}
			end
			if group and t then
				group.type = t
			end
			for _, entry in ipairs(section) do
				if entry.tag == "enum" then
					local ename = entry.attr.name
					local enum = enums[ename]
					if enum then
						enum.value = entry.attr.value
						if group then
							groups[gname] = group
							enum.groups[gname] = true
							group.enums[ename] = true
						end
					end
				end
			end
		end
	end
	return enums
end

local enums = feature.enums
for key, _ in pairs(enums) do
	enums[key] = {
		name = key,
		groups = {},
	}
end
feature.groups = parse_groups(enums)
feature.enums = parse_enums(enums, feature.groups)

-- Output generating functions

local function list_apis()
	for api, features in pairs(apis) do
		print("API: " .. api)
		for _, feature in ipairs(features) do
			print(" - " .. feature.version .. " : " .. feature.name)
		end
	end
end

local function list_contents(feature)
	print("API: " .. feature.api .. " " .. feature.version)
	print("Types:")
	print_set(feature.types, " - ", "\n")
	print("Enumerators:")

	local order = {}
	for key, _ in pairs(enums) do
		order[#order + 1] = key
	end
	table.sort(order)
	for _, key in ipairs(order) do
		io.write(" - ", key, ": ")
		print_set_oneline(enums[key].groups, ", ")
		io.write("\n")
	end

	print("Commands:")
	print_set(feature.commands, " - ", "\n")

	print("Groups:")
	local order = {}
	for key, _ in pairs(feature.groups) do
		order[#order + 1] = key
	end
	table.sort(order)
	for _, key in ipairs(order) do
		local group = feature.groups[key]
		io.write(" - ", key, ": ")
		print_set_oneline(group.enums, ", ")
		io.write("\n")
	end
end

local function neat_const_name(capname)
	local parts = string.split(capname, "_")
	table.remove(parts, 1)
	for i, v in ipairs(parts) do
		local cap = string.sub(v, 1, 1)
		parts[i] = cap .. string.lower(string.sub(v, 2))
	end
	return table.concat(parts)
end

local function generate_header(feature)
	io.write("// OpenGL: ", feature.api, " ", feature.version, "\n")
	io.write("// Header generated by GladX\n")
	io.write("\n")
	io.write("#pragma once\n")
	io.write("#include \"bitset.hxx\"\n")
	io.write("#define __gl_h_\n")
	io.write("#define ", feature.name, " 1\n")

	local order = {}
	for key, _ in pairs(feature.groups) do
		order[#order + 1] = key
	end
	table.sort(order)
	io.write("\n// Enumerations\n")
	for _, gname in ipairs(order) do
		local group = feature.groups[gname]
		if next(group.enums) and group.type ~= "bitmask" then
			io.write("\nenum class ", gname, ": unsigned {\n")
			local list = {}
			for ename, _ in pairs(group.enums) do
				list[#list + 1] = ename
			end
			table.sort(list)
			for _, ename in ipairs(list) do
				io.write("\t", neat_const_name(ename), " = ", feature.enums[ename].value, ", // ", ename, "\n")
			end
			io.write("};\n")
		end
	end
	io.write("\n// Bit sets\n")
	for _, gname in ipairs(order) do
		local group = feature.groups[gname]
		if next(group.enums) and group.type == "bitmask" then
			local t = "Bitset<" .. gname .. ", unsigned>"
			io.write("\nstruct ", gname, ": ", t, " {\n")
			for ename, _ in pairs(group.enums) do
				local enum = feature.enums[ename]
				io.write("\t", t, " ", neat_const_name(ename), " = atom(", enum.value, "); // ", ename, "\n")
			end
			io.write("};\n")
		end
	end
end

for _, v in ipairs({...}) do
	if v == "--list-apis" then
		list_apis()
	end
	if v == "--list-gl33" then
		list_contents(feature)
	end
	if v == "--gen-gl33" then
		generate_header(feature)
	end
end
