#!/usr/bin/lua

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

local function print_set(set, prefix)
	local list = {}
	for key, _ in pairs(set) do
		list[#list + 1] = key
	end
	table.sort(list)
	for _, value in ipairs(list) do
		io.write(prefix, value, "\n")
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
	local enums = feature.enums
	for key, value in pairs(enums) do
		enums[key] = {
			groups = {},
		}
	end
	feature.groups = parse_groups(enums)
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

for _, v in ipairs({...}) do
	if v == "--list-apis" then
		list_apis()
	end
	if v == "--list-gl33" then
		list_contents(apis["gl"]["3.3"])
	end
end
