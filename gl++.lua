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
		print(prefix .. value)
	end
end

local spec = parse_xml(read_file("gl.xml"))

local apis = {}
for _, entry in ipairs(spec) do
	if entry.tag == "feature" then
		local api = apis[entry.attr.api]
		if not api then
			api = {}
			apis[entry.attr.api] = api
		end
		local feature = {
			api = entry.attr.api,
			version = entry.attr.number,
			name = entry.attr.name,
			xml = entry
		}
		api[#api + 1] = feature
		api[feature.version] = feature
	end
end

for api, features in pairs(apis) do
	table.sort(features, cmp_ver)
	print("API: " .. api)
	local base_feature = {
		types = {},
		enums = {},
		commands = {},
	}
	for _, feature in ipairs(features) do
		print(" - " .. feature.version .. " : " .. feature.name)
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
		print_set(feature.commands, " - - ")
		base_feature = feature
	end
end
