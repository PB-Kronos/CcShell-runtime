local args = { ... }

-- =====================
-- CONFIG
-- Repo structure:
--   main/pkg/<package>
--   main/pkg/single/<installer>
-- =====================
local REPO = settings.get("repo") or "https://raw.githubusercontent.com/PB-Kronos/CcShell-runtime/main/pkg"
local DB_PATH = settings.get("db_path") or "/var/kpkg/db.json"

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
    local dir = fs.getDir(DB_PATH)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local f = fs.open(DB_PATH, "w")
    f.write(textutils.serialize(db))
    f.close()
end

-- =====================
-- HTTP
-- =====================
local function fetch(url)
    if not http then
        print("HTTP not enabled")
        return nil
    end

    local h = http.get(url)
    if not h then return nil end

    local data = h.readAll()
    h.close()

    return data
end

-- =====================
-- FILE OPS
-- =====================
local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

-- =====================
-- MANIFEST
-- =====================
local function loadManifest(pkg)
    local url = REPO .. "/" .. pkg .. "/manifest.lua"
    local src = fetch(url)
    if not src then return nil end

    local fn, err = load(src)
    if not fn then
        print("Manifest load error: " .. err)
        return nil
    end

    local ok, result = pcall(fn)
    if not ok then
        print("Manifest runtime error: " .. result)
        return nil
    end

    return result
end

-- =====================
-- SINGLE INSTALLERS
-- =====================
local function runSinglePackage(pkg)
    pkg = pkg:gsub("^/", "")

    local function try(url)
        local src = fetch(url)
        if not src then return false end

        print("Running installer: " .. url)

        local fn, err = load(src)
        if not fn then
            print("Installer load error: " .. err)
            return true
        end

        local ok, runtimeErr = pcall(fn)
        if not ok then
            print("Installer runtime error: " .. runtimeErr)
        end

        return true
    end

    -- 1. Exact match: scada/common.lua
    if try(REPO .. "/single/" .. pkg .. ".lua") then
        return true
    end

    -- 2. Folder fallback: scada/common.lua → scada.lua
    local parent = pkg:match("(.+)/[^/]+$")
    if parent then
        if try(REPO .. "/single/" .. parent .. ".lua") then
            return true
        end
    end

    return false
end

-- =====================
-- INSTALL
-- =====================
local function install(pkg, db)
    if not pkg then
        print("Usage: pacman -S <pkg>")
        return
    end

    -- 1. SINGLE INSTALLERS FIRST (highest priority)
    if runSinglePackage(pkg) then
        return
    end

    -- 2. MANIFEST INSTALL
    local manifest = loadManifest(pkg)

    if manifest then
        print("Installing " .. (manifest.name or pkg))

        for _, file in ipairs(manifest.files or {}) do
            local url = REPO .. "/" .. pkg .. "/files/" .. file
            local data = fetch(url)

            if data then
                local path = "/" .. file
                writeFile(path, data)
                print(" + " .. file)
            else
                print(" ! failed: " .. file)
            end
        end

        db[pkg] = {
            version = manifest.version,
            files = manifest.files
        }

        print("Installed " .. pkg)
        return
    end

    print("Package not found: " .. pkg)
end

-- =====================
-- REMOVE
-- =====================
local function remove(pkg, db)
    if not pkg then
        print("Usage: pacman -R <pkg>")
        return
    end

    local entry = db[pkg]

    if not entry then
        print("Package not installed: " .. pkg)
        return
    end

    print("Removing " .. pkg)

    for _, file in ipairs(entry.files or {}) do
        local path = "/" .. file
        if fs.exists(path) then
            fs.delete(path)
            print(" - " .. file)
        end
    end

    db[pkg] = nil
    print("Removed " .. pkg)
end

-- =====================
-- QUERY
-- =====================
local function query(db)
    print("Installed packages:")

    for name, info in pairs(db) do
        print("- " .. name .. " (" .. (info.version or "?") .. ")")
    end
end

-- =====================
-- UPGRADE
-- =====================
local function upgrade(db)
    print("Upgrading system...")

    local list = {}
    for pkg in pairs(db) do
        table.insert(list, pkg)
    end

    for _, pkg in ipairs(list) do
        remove(pkg, db)
        install(pkg, db)
    end

    print("Upgrade complete")
end

-- =====================
-- CLI
-- =====================
local db = loadDB()

local cmd = args[1]
local target = args[2]

if cmd == "-S" then
    install(target, db)

elseif cmd == "-R" then
    remove(target, db)

elseif cmd == "-Syu" then
    upgrade(db)

elseif cmd == "-Q" then
    query(db)

else
    print("pacman usage:")
    print("  pacman -S <pkg>")
    print("  pacman -R <pkg>")
    print("  pacman -Syu")
    print("  pacman -Q")
end

saveDB(db)