print("Starting quick installation...")

-- 1. Remove old cloud_user.lua if it exists on the tablet/computer
if fs.exists("cloud_user.lua") then
    print("Removing old cloud_user.lua...")
    fs.delete("cloud_user.lua")
end

-- 2. Create plugins folder first to ensure the path exists
if not fs.exists("plugins") then
    fs.makeDir("plugins")
end

if fs.exists("plugins/install.lua") then
    print("Removing old plugins/install.lua...")
    fs.delete("plugins/install.lua")
end

-- 3. Download cloud.lua and the main plugin installer
print("Downloading clouduser...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud_user.lua", "cloud_user.lua")

print("Downloading cloud.lua...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud.lua", "cloud.lua")

print("Downloading installer...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/plugins/install.lua", "plugins/install.lua")

-- 4. Create or overwrite startup.lua for automatic system boot
print("Configuring auto-boot (startup.lua)...")
local f = fs.open("startup.lua", "w")
f.writeLine('-- Automatic Cloud System Boot')
f.writeLine('shell.run("cloud.lua")')
f.close()

-- 5. Run the system immediately after completion
print("Installation completed successfully!")
print("Starting cloud...")
shell.run("cloud.lua")
