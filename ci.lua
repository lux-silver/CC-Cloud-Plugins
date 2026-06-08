-- Código ideal para o seu script 'ci'
print("Iniciando instalacao rapida...")

-- 1. Cria a pasta plugins primeiro para garantir que o caminho exista
if not fs.exists("plugins") then
    fs.makeDir("plugins")
end

-- 2. Baixa cada arquivo direto no seu lugar certo (sem precisar mover depois)
print("Baixando cloud.lua...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud.lua", "cloud.lua")

print("Baixando cloud_user.lua...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/cloud_user.lua", "cloud_user.lua")

print("Baixando instalador...")
shell.run("wget", "https://raw.githubusercontent.com/lux-silver/CC-Cloud-Plugins/main/plugins/install.lua", "plugins/install.lua")

-- 3. Executa o sistema automaticamente
print("Pronto! Iniciando cloud...")
shell.run("cloud")