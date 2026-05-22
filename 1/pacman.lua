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
    if not h then
        print("Failed to fetch: " .. url)
        return nil
    end

    local data = h.readAll()
    h.close()
    return data
end

-- =====================
-- FILE OPS
-- =====================
local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local f = fs.open(path, "w")
    if not f then
        print("Failed to write: " .. path)
        return false
    end

    f.write(content)
    f.close()
    return true
end

-- =====================
-- MANIFEST
-- =====================
local function loadManifest(pkg)
    local src = fetch(REPO .. "/" .. pkg .. "/manifest.lua")
    if not src then return nil end

    local fn, err = load(src)
    if not fn then
        print("Manifest load error: " .. tostring(err))
        return nil
    end

    return fn()
end

-- =====================
-- INSTALL
-- =====================
local function install(pkg, db)
    if not pkg then
        print("Usage: pacman -S <pkg>")
        return
    end

    local manifest = loadManifest(pkg)
    if not manifest then
        print("Package not found: " .. pkg)
        return
    end

    print("Installing " .. manifest.name)

    for _, file in ipairs(manifest.files or {}) do
        local url = REPO .. "/" .. pkg .. "/files/" .. file
        local data = fetch(url)

        if data then
            local path = "/" .. file
            writeFile(path, data)
            print(" + " .. file)
        else
            print(" ! Failed: " .. file)
        end
    end

    db[pkg] = {
        version = manifest.version,
        files = manifest.files
    }

    print("Installed " .. pkg)
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
-- UPGRADE ALL
-- =====================
local function upgrade(db)
    print("Upgrading system...")

    local list = {}
    for pkg in pairs(db) do
        table.insert(list, pkg)
    end

    for _, pkg in ipairs(list) do
        print("Updating " .. pkg)
        remove(pkg, db)
        install(pkg, db)
    end

    print("Upgrade complete")
end

-- =====================
-- CLI PARSER
-- =====================
local db = loadDB()

local function has(flag)
    for _, v in ipairs(args) do
        if v == flag then return true end
    end
    return false
end

local cmd = args[1]
local target = args[2]

if cmd == "-S" then
    install(target, db)

elseif cmd == "-R" then
    remove(target, db)

elseif has("-Syu") then
    upgrade(db)

elseif has("-Q") then
    query(db)

else
    print("pacman usage:")
    print("  pacman -S <pkg>   Install package")
    print("  pacman -R <pkg>   Remove package")
    print("  pacman -Syu       Upgrade all packages")
    print("  pacman -Q         List installed packages")
end

saveDB(db)