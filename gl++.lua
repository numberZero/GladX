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

local typemap = {
	GLenum = "GLenum",
	GLbitfield = "GLbitfield",
	GLboolean = "GLboolean",
	GLsync = "GLsync",
	GLhandleARB = "GLhandle",
	GLDEBUGPROC = "GLDEBUGPROC",
	GLVULKANPROCNV = "GLVULKANPROCNV",
	GLint64 = "std::int64_t",
	GLuint64 = "std::uint64_t",
	GLintptr = "std::intptr_t",
	GLsizeiptr = "__ssize_t",
	GLvdpauSurfaceNV = "std::intptr_t",

	GLchar = "char",
	GLbyte = "signed char",
	GLubyte = "unsigned char",
	GLshort = "short",
	GLushort = "unsigned short",
	GLint = "int",
	GLuint = "unsigned",
	GLfloat = "float",
	GLdouble = "double",
	GLclampf = "float",
	GLclampd = "double",
	GLsizei = "int",
}

local function parse_param(xml)
	assert(xml.tag == "param" or xml.tag == "proto")
	local ptype = ""
	local name
	local underlying
	for _, part in ipairs(xml) do
		if type(part) == "string" then
			ptype = ptype .. part
		elseif part.tag == "ptype" then
			assert(#part == 1)
			underlying = typemap[part[1]]
			assert(type(underlying) == "string")
			if xml.attr.group then
				----------------------------------------
				if xml.attr.group == "sync" then
					xml.attr.group = "GLsync"
				end
				----------------------------------------
				ptype = ptype .. xml.attr.group
			else
				ptype = ptype .. underlying
			end
		elseif part.tag == "name" then
			assert(#part == 1)
			name = part[1]
			assert(type(name) == "string")
			break
		end
	end
	return {
		name = name:trim(),
		type = ptype:trim(),
		underlying = underlying,
		group = xml.attr.group,
	}
end

local function add_command(commands, xml, list)
	assert(xml.tag == "command")
	local rtype
	local cname
	local params = {}
	for _, entry in ipairs(xml) do
		if entry.tag == "proto" then
			local proto = parse_param(entry)
			cname = proto.name
			rtype = proto.type
			if not list[cname] then
				return
			end
		elseif entry.tag == "param" then
			local param = parse_param(entry)
			params[#params + 1] = param
		end
	end
	commands[cname] = {
		name = cname,
		rtype = rtype,
		params = params,
		len = xml.attr.len,
		xml = xml,
	}
end

local function parse_commands()
	local commands = {}
	for _, section in ipairs(spec) do
		if section.tag == "commands" then
			for _, entry in ipairs(section) do
				if entry.tag == "command" then
					add_command(commands, entry, feature.commands)
				end
			end
			break
		end
	end
	return commands
end

local function parse_types(commands, groups)
	local typedefs = {}
	for _, command in pairs(commands) do
		for _, param in ipairs(command.params) do
			local group = param.group
			if group and not groups[group] then
				typedefs[group] = param.underlying
			end
		end
	end
	return typedefs;
end

for key, _ in pairs(feature.enums) do
	feature.enums[key] = {
		name = key,
		groups = {},
	}
end
feature.groups = parse_groups(feature.enums)
feature.enums = parse_enums(feature.enums, feature.groups)
feature.commands = parse_commands()
feature.typedefs = parse_types(feature.commands, feature.groups)

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

local function generate(feature)
	local f = io.open("gl++/gl.hxx", "w")
	f:write("// OpenGL: ", feature.api, " ", feature.version, "\n")
	f:write("// Header generated by GladX\n")
	f:write("\n")
	f:write("#pragma once\n")
	f:write("#include \"types.hxx\"\n")
	f:write("#include \"bitset.hxx\"\n")
	f:write("#define __gl_h_\n")
	f:write("#define ", feature.name, " 1\n")

	local order = {}
	for key, _ in pairs(feature.typedefs) do
		order[#order + 1] = key
	end
	table.sort(order)
	f:write("\n// Typedefs\n")
	for _, tname in ipairs(order) do
		f:write("\ntypedef ", feature.typedefs[tname], " ", tname, ";")
	end

	order = {}
	for key, _ in pairs(feature.groups) do
		order[#order + 1] = key
	end
	table.sort(order)
	f:write("\n// Enumerations\n")
	for _, gname in ipairs(order) do
		local group = feature.groups[gname]
		if next(group.enums) and group.type ~= "bitmask" and gname ~= "SpecialNumbers" then
			f:write("\nenum class ", gname, ": unsigned {\n")
			local list = {}
			for ename, _ in pairs(group.enums) do
				list[#list + 1] = ename
			end
			table.sort(list)
			for _, ename in ipairs(list) do
				f:write("\t", neat_const_name(ename), " = ", feature.enums[ename].value, ", // ", ename, "\n")
			end
			f:write("};\n")
		end
	end
	f:write("\n// Bit sets\n")
	for _, gname in ipairs(order) do
		local group = feature.groups[gname]
		if next(group.enums) and group.type == "bitmask" then
			local t = "Bitset<" .. gname .. ", unsigned>"
			f:write("\nstruct ", gname, ": ", t, " {\n")
			for ename, _ in pairs(group.enums) do
				local enum = feature.enums[ename]
				f:write("\t", t, " ", neat_const_name(ename), " = atom(", enum.value, "); // ", ename, "\n")
			end
			f:write("};\n")
		end
	end
	order = {}
	for key, _ in pairs(feature.commands) do
		order[#order + 1] = key
	end
	table.sort(order)
	f:write("\n// Commands\n")
	for _, cname in ipairs(order) do
		local command = feature.commands[cname]
		local cname = command.name --:sub(3)
		f:write("\n", command.rtype, " ", cname, "(\n\t")
		for i, param in ipairs(command.params) do
			if i ~= 1 then
				f:write(",\n\t")
			end
			f:write(param.type, " ", param.name)
		end
		f:write("\n);\n")
	end
	f:close()
end

for _, v in ipairs({...}) do
	if v == "--list-apis" then
		list_apis()
	end
	if v == "--list-gl33" then
		list_contents(feature)
	end
	if v == "--gen-gl33" then
		generate(feature)
	end
end
