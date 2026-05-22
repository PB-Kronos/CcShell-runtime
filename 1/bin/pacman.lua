-- pacman.lua (simplified package system - no manifests)

local args = { ... }

-- =====================
-- CONFIG
-- =====================
local REPO = "https://raw.githubusercontent.com/PB-Kronos/CcShell-runtime/main/pkg"
local DB_PATH = "/var/kpkg/db.json"

-- =====================
-- DB
-- =====================
local function loadDB()
    if not fs.exists(DB_PATH) then return {} end

    local f = fs.open(DB_PATH, "r")
    local data = f.readAll()
    f.close()

    return textutils.unserialize(data) or {}
end

local function saveDB(db)
    if not fs.exists("/var/kpkg") then
        fs.makeDir("/var/kpkg")
    end

    local f = fs.open(DB_PATH, "w")
    f.write(textutils.serialize(db))
    f.close()
end

-- =====================
-- HTTP
-- =====================
local function fetch(url)
    local h = http.get(url)
    if not h then return nil end

    local data = h.readAll()
    h.close()
    return data
end

-- =====================
-- PATH RESOLUTION
-- =====================

local function tryFetch(path)
    -- raw file fetch helper
    return fetch(REPO .. "/" .. path)
end

local function resolvePackagePath(pkg)
    -- returns possible remote paths in priority order

    return {
        pkg .. "/setup.lua",
        pkg .. ".lua"
    }
end

local function findRemote(pkg)
    local candidates = resolvePackagePath(pkg)

    for _, path in ipairs(candidates) do
        local data = tryFetch(path)
        if data then
            return path, data
        end
    end

    return nil, nil
end

-- =====================
-- INSTALL / RUN LOGIC
-- =====================

local function installOrRun(pkg, db)
    if not pkg then
        print("Usage: pacman -S <pkg>")
        return
    end

    local remotePath, data = findRemote(pkg)

    if not data then
        print("Package not found: " .. pkg)
        return
    end

    print("Found: " .. remotePath)

    -- If it's setup.lua → treat as installer
    if remotePath:match("setup%.lua$") then
        print("Running installer for " .. pkg)

        local fn, err = load(data, "@" .. remotePath, "t", _G)
        if not fn then
            print("Load error: " .. tostring(err))
            return
        end

        local ok, err2 = pcall(fn)
        if not ok then
            print("Install error: " .. tostring(err2))
            return
        end

        db[pkg] = { type = "installer" }
        saveDB(db)

        print("Installed (installer mode): " .. pkg)
        return
    end

    -- Otherwise treat as single-run program
    print("Executing package: " .. pkg)

    local fn, err = load(data, "@" .. remotePath, "t", _G)
    if not fn then
        print("Load error: " .. tostring(err))
        return
    end

    local ok, err2 = pcall(fn)
    if not ok then
        print("Runtime error: " .. tostring(err2))
    end
end

-- =====================
-- REMOVE (local DB only)
-- =====================
local function remove(pkg, db)
    if not db[pkg] then
        print("Package not installed: " .. pkg)
        return
    end

    db[pkg] = nil
    saveDB(db)

    print("Removed: " .. pkg)
end

-- =====================
-- QUERY
-- =====================
local function query(db)
    print("Installed packages:")

    for name, info in pairs(db) do
        print("- " .. name .. " (" .. (info.type or "?") .. ")")
    end
end

-- =====================
-- CLI
-- =====================
local db = loadDB()

local function has(flag)
    for _, v in ipairs(args) do
        if v == flag then return true end
    end
    return false
end

local target = args[2]

if args[1] == "-S" then
    installOrRun(target, db)

elseif has("-R") then
    remove(target, db)

elseif has("-Q") then
    query(db)

else
    print("pacman usage:")
    print("  pacman -S <pkg>")
    print("  pacman -R <pkg>")
    print("  pacman -Q")
ends