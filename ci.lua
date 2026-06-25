print("Starting quick installation...")

-- 1. Remove os arquivos antigos para não dar conflito
if fs.exists("cloud_user.lua") then
    print("Removing old cloud_user.lua...")
    fs.delete("cloud_user.lua")
end

if fs.exists("cloud.lua") then
    print("Removing old cloud.lua...")
    fs.delete("cloud.lua")
end

-- 2. Cria a pasta de plugins se não existir
if not fs.exists("plugins") then
    fs.makeDir("plugins")
end

if fs.exists("plugins/install.lua") then
    print("Removing old plugins/install.lua...")
    fs.delete("plugins/install.lua")
end

-- 3. Baixa os arquivos certos direto do GitHub
print("Downloading cloud_user.lua...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud_user.lua", "cloud_user.lua")

print("Downloading cloud.lua...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud.lua", "cloud.lua")

print("Downloading installer...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/plugins/install.lua", "plugins/install.lua")

-- 4. Cria o startup.lua apontando para o sistema principal do tablet
print("Configuring auto-boot (startup.lua)...")
local f = fs.open("startup.lua", "w")
f.writeLine('-- Automatic Cloud System Boot')
f.writeLine('shell.run("cloud_user.lua")') -- ◄ Corrigido para iniciar o seu cloud_user
f.close()

-- 5. Finaliza e roda o sistema na hora
print("Installation completed successfully!")
print("Starting cloud...")
shell.run("cloud_user.lua") -- ◄ Corrigido aqui tambémprint("Starting quick installation...")

-- 1. Remove os arquivos antigos para não dar conflito
if fs.exists("cloud_user.lua") then
    print("Removing old cloud_user.lua...")
    fs.delete("cloud_user.lua")
end

if fs.exists("cloud.lua") then
    print("Removing old cloud.lua...")
    fs.delete("cloud.lua")
end

-- 2. Cria a pasta de plugins se não existir
if not fs.exists("plugins") then
    fs.makeDir("plugins")
end

if fs.exists("plugins/install.lua") then
    print("Removing old plugins/install.lua...")
    fs.delete("plugins/install.lua")
end

-- 3. Baixa os arquivos certos direto do GitHub
print("Downloading cloud_user.lua...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud_user.lua", "cloud_user.lua")

print("Downloading cloud.lua...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud.lua", "cloud.lua")

print("Downloading installer...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/plugins/install.lua", "plugins/install.lua")

-- 4. Cria o startup.lua apontando para o sistema principal do tablet
print("Configuring auto-boot (startup.lua)...")
local f = fs.open("startup.lua", "w")
f.writeLine('-- Automatic Cloud System Boot')
f.writeLine('shell.run("cloud_user.lua")') -- ◄ Corrigido para iniciar o seu cloud_user
f.close()

-- 5. Finaliza e roda o sistema na hora
print("Installation completed successfully!")
print("Starting cloud...")
shell.run("cloud.lua") -- ◄ Corrigido aqui também
