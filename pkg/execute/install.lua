local function download(src, dst)
    shell.run("wget https://raw.githubusercontent.com/PB-Kronos/CcShell-runtime/main/" .. src .. " " .. dst)
end

local function install_file(cache_path, target_path, source_path)
    download(source_path, cache_path)
    if not fs.exists(cache_path) then
        error("download failed for " .. source_path, 0)
    end

    if fs.exists(target_path) then
        error("module " .. target_path .. " already exists", 0)
    end

    fs.copy(cache_path, target_path)

    if not fs.exists(target_path) then
        error("install failed, module " .. target_path .. " could not be verified", 0)
    end

    print("Installed:", target_path)
end

local function install()
    install_file("/var/cache/execute.lua", "/bin/execute.lua", "pkg/execute/execute.lua")
    install_file("/var/cache/file.lua", "/bin/file.lua", "pkg/execute/file.lua")
end

if downloader then
    shell.run("wget https://raw.githubusercontent.com/PB-Kronos/CcShell-runtime/main/pkg/execute/execute.lua /home/download/execute.lua")
    shell.run("wget https://raw.githubusercontent.com/PB-Kronos/CcShell-runtime/main/pkg/execute/file.lua /home/download/file.lua")
elseif downloader == false then
    install()
else
    error("download is nil")
end
