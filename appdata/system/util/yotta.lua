--[[pod_format="raw",created="2024-03-16 21:44:35",modified="2024-03-21 13:18:39",revision=216]]
-- yotta: a "package" "manager" for Picotron
--  by ahrotahn <reh@ahrotahn.net>
-- v1.0: initial hideous beautiful version

YF_VER = 1
YF_DIR = "lib"
YF_TRACKFILE = "yottafile.pod"
YF_DEFAULT = YF_DIR.."/" .. YF_TRACKFILE
YF_SYS = "/appdata/system/global_yottafile.pod"

function usage()
	print("usage: yotta [command]")
	print("commands:")
	print(" init - initialize a yottafile for the current directory")
	print(" list - list the current dependencies")
	print("   -v - verbose: list all tracked files under each dependency")
	print(" add [cart] - add a cart ref as dependency (but don't add/remove anything yet)")
	print(" remove [cart] - remove a cart ref as dependency (but don't add/remove anythin yet)")
	print(" apply - make the current directory match a yottafile")
	print("   (this is what actually adds and removes files!)")
	print(" force - this is an apply that will reinstall every dep (for updates?)")
	print(" util install [cart] - globally install utility cart ref")
	print(" util uninstall [cart] - globally uninstall utility cart ref")
	print(" util list - list all tracked util cart refs and their files")
end

function download_bbs_cart(id)
	-- ok, yes, yes zep, i know you said this isn't a public api
	-- but i do so like to live dangerously.
	-- return fetch("http://picotron-dev.local/"..id)
	return fetch("https://www.lexaloffle.com/bbs/get_cart.php?cat=8&lid="..id)
	-- i'm placing it up top in an easy-to-access place in case
	-- it needs to be manually edited by end-users in the future
	-- to comply with some kind of eventual future public api
	-- to get everything running again.
end

function read_yottafile(yfp)
	yfp = yfp or YF_DEFAULT
	local raw = fetch(yfp)
	
	if raw["_yf_version"] == 1 then
		return {
			tags = raw["tags"],
			deps = raw["deps"],
			tracked = raw["tracked"]
		}
	else
		print("ERROR: unknown yottafile version: " .. raw["_yf_version"])
		print("Malformed or future yottafile? Maybe update yotta or pick a real target?")
		exit(1)
	end
end

function write_yottafile(yf, yfp)
	yfp = yfp or YF_DEFAULT
	store(yfp, {
		["_yf_version"] = YF_VER,
		tags = yf["tags"],
		deps = yf["deps"],
		tracked = yf["tracked"]
	})
end

function normalize_cart_ref(ref)
	if ref:sub(1,1) == "#" then
		-- BBS id
		ref = "_bbs_" .. ref:sub(2)
	else
		-- filename
		ref = fullpath(ref):basename()
		if (ref:sub(-4) == ".png") ref = ref:sub(1, -5)
		if (ref:sub(-4) == ".p64") ref = ref:sub(1, -5)
	end
	
	ref = table.concat(split(ref, "-", false), "_")
	ref = table.concat(split(ref, ".", false), "_")
	-- TODO: figure out more bad fs symbols to fix probably lmao

	return ref
end

function install_ref(ref, yfp, dest_dir, owner_ref)
	yfp = yfp or YF_DEFAULT
	owner_ref = owner_ref or ref
	
	local norm_name = normalize_cart_ref(ref)
	dest_dir = dest_dir or "./"..YF_DIR.."/"..norm_name
	local tmp_cart = "/ram/_yotta_temp.p64"

	-- fetch cart data
	if ref:sub(1,1) == "#" then
		-- BBS download
		tmp_cart ..= ".png"
		local data = download_bbs_cart(ref:sub(2))	
			
		if type(data) != "string" or #data <= 0 then
			print("ERROR: could not acquire BBS cart with ID: " .. ref);
			exit(1)
		end
		
		rm(tmp_cart)
		store(tmp_cart, data)
	else
		-- file path
		
		local filename = fullpath(ref)
		if fstat(filename) != "folder" then
			filename = filename..".p64"
			if fstat(filename) != "folder" then
				filename = filename..".png"
				if fstat(filename) != "folder" then
					print("ERROR: could not acquire filesystem cart with path: " .. ref)
					exit(1)
				end
			end
		end

		if (filename:sub(-8) == ".p64.png") tmp_cart ..= ".png"
		cp(filename, tmp_cart)
	end
	
	-- does target have /export
	local exports_dir = tmp_cart .. "/exports"
	if not fstat(exports_dir) then
		print("WARNING: specified ref ("..ref..") has no exports. IGNORING REF!")
		return false
	end
	
	if yfp == YF_SYS then
		-- overlay exports onto root fs
		-- kind of yikes ig
		local result = merge(exports_dir, "")
		foreach(result["files"], function(v) yf_add_track(ref, v, yfp) end)
		foreach(result["dirs"], function(v) yf_add_track(ref, v, yfp) end)
	else
		if fstat(dest_dir) != "folder" then
			mkdir(dest_dir)
			yf_add_track(ref, dest_dir, yfp)
		end
	
		-- extract exports into appropriate CWD locations
		for exp in all(ls(exports_dir)) do
			local full = fullpath(exports_dir.."/"..exp)
			local ext = exp:sub(-4)
			local dest = dest_dir.."/"..full:basename()
			local lua = (ext == ".lua")
		
			if ext == ".gfx" or ext == ".sfx" or ext == ".map" then
				-- allow gfx, sfx, and map exports!
				dest = "./"..ext:sub(-3).."/"..norm_name.."_"..full:basename()
			end
		
			print("copying src:"..exp.." => dst:"..dest)
			cp(full, fullpath(dest))
			yf_add_track(ref, dest, yfp)
		end
	end

	-- clean up...
	rm(tmp_cart)
end

function yf_add_track(ref, file, yfp)
	local yf = read_yottafile(yfp)
	local norm = normalize_cart_ref(ref)
	if type(yf["tracked"][norm]) != "table" then
		yf["tracked"][norm] = {}
	end
	if count(yf["tracked"][norm], file) == 0 then
		add(yf["tracked"][norm], file)
	end
	if type(yf["tracked"]["_refs"]) != "table" then
		yf["tracked"]["_refs"] = {}
	end
	if count(yf["tracked"]["_refs"], ref) == 0 then
		add(yf["tracked"]["_refs"], ref)
	end
	write_yottafile(yf, yfp)
end

function yf_remove_track(ref, file, yfp)
	local yf = read_yottafile(yfp)
	local norm = normalize_cart_ref(ref)
	if type(yf["tracked"][norm]) != "table" then
		return
	end
	while count(yf["tracked"][norm], file) > 0 do
		del(yf["tracked"][norm], file)
	end
	if #yf["tracked"][norm] == 0 then
		deli(yf["tracked"], norm)
		del(yf["tracked"]["_refs"], ref)
	end
	write_yottafile(yf, yfp)
end

function uninstall_ref(ref, yfp)
	yfp = yfp or YF_DEFAULT
	local norm_name = normalize_cart_ref(ref)
	local yf = read_yottafile(yfp)
	
	if type(yf["tracked"][norm_name]) != "table" then
		return
	end
	
	for file in all(yf["tracked"][norm_name]) do
		local type = fstat(fullpath(file))
		if type != "folder" then
			rm(fullpath(file))
			yf_remove_track(ref, file, yfp)
		end
	end
	
	for file in all(yf["tracked"][norm_name]) do
		if type == "folder" then
			if #ls(fullpath(file)) == 0 then
				-- remove folders originally added by this ref that are now empty
				rm(fullpath(file))
			end
			
			yf_remove_track(ref, file, yfp)
		end
	end
end

function merge(src, dst, dir)
	dir = dir or "/"
	
	local dirs = {}
	local files = {}
	
	for entry in all(ls(src..dir)) do
		local type = fstat(src..dir..entry)
		local rpath = dir..entry
		if type == "folder" then
			if fstat(dst..rpath) != "folder" then
				mkdir(dst..rpath)
			end

			local inner = merge(src, dst, dir..entry.."/")
			foreach(inner["dirs"], function(v) add(dirs, v) end)
			foreach(inner["files"], function(v) add(files, v) end)
		elseif type == "file" then
			if (fstat(dst..rpath) == "file") then
				cp(dst..rpath, dst..rpath..".bak")
			end
			
			add(files, dst..rpath)
			cp(src..rpath, dst..rpath)
		end
	end
	
	return {
		dirs = dirs,
		files = files
	}
end

function yf_init(yfp)
	yfp = yfp or YF_DEFAULT
	
	if fstat(yfp) then
		return
	end

	local tags = {
		["created"] = date()
	}
	
	print("initializing yottafile at: " .. fullpath(yfp))
	
	if yfp != YF_SYS and fstat(YF_DIR) != "folder" then
		mkdir(YF_DIR)
	end
	
	write_yottafile({
		["deps"] = {},
		["tags"] = tags,
		["tracked"] = {
			["_refs"] = {}
		}
	}, yfp)
end

function yf_list(verbose, yfp)
	verbose = verbose or false
	yfp = yfp or YF_DEFAULT
	
	local yf = read_yottafile(yfp)
	print("list of current "..(yfp == YF_SYS and "system-level utilities" or "dependencies")..":")
	
	for dep in all(yf["deps"]) do
		local norm = normalize_cart_ref(dep)
		print("  "..dep.." (\""..norm.."\")")
		if verbose or util then
			for file in all(yf["tracked"][norm]) do
				print("    " .. file)
			end
		end
	end
end	

--
-- entry
--

cd(env().path)
local argv = env().argv
if (#argv < 1) then
	usage()
	exit(1)
end

local command = argv[1]

if count({"init", "util", "help"}, command) == 0
and fstat(YF_DEFAULT) != "file" then
	print("ERROR: No yottafile present")
	print("")
	usage()
	exit(1)
end

if command == "init" then
	yf_init()
elseif command == "list" then
	yf_list(argv[2] == "-v")
elseif command == "add" then
	for i = 2, #argv do
		local ref = argv[i]
		print("adding "..ref)

		local yf = read_yottafile()
		add(yf["deps"], ref)
		write_yottafile(yf)
	end
elseif command == "remove" then
	for i = 2, #argv do
		local ref = argv[i]
		print("removing "..ref)
	
		local yf = read_yottafile()
		del(yf["deps"], ref)
		write_yottafile(yf)
	end
elseif command == "apply" or command == "force" then
	local yf = read_yottafile()
	local force = (command == "force")

	for ref in all(yf["tracked"]["_refs"]) do
		if count(yf["deps"], ref) == 0 then
			print("removing dependency: "..ref)
			uninstall_ref(ref)
		end
	end
	
	for ref in all(yf["deps"]) do
		if force or count(yf["tracked"]["_refs"]) == 0 then
			print((force and "updating" or "adding") .. " dependency: "..ref)
			install_ref(ref)
		end
	end
elseif command == "util" then
	yf_init(YF_SYS)
	
	subcommand = argv[2]
	if subcommand == "install" then
		for i = 3, #argv do
			local ref = argv[i]
			print("installing utility: "..ref)

			local yf = read_yottafile(YF_SYS)
			add(yf["deps"], ref)
			write_yottafile(yf, YF_SYS)
		
			install_ref(ref, YF_SYS)
		end
	elseif subcommand == "uninstall" then
		for i = 3, #argv do
			local ref = argv[i]
			print("uninstalling utility: "..ref)
		
			local yf = read_yottafile(YF_SYS)
			del(yf["deps"], ref)
			write_yottafile(yf, YF_SYS)
				
			uninstall_ref(ref, YF_SYS)
		end
	elseif subcommand == "list" then
		yf_list(true, YF_SYS)
	else
		usage()
		exit((subcommand != "help") and 1 or 0)
	end
else
	usage()
	exit((command != "help") and 1 or 0)
end