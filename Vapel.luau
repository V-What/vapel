local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Theme = {
	Background = Color3.fromRGB(19, 19, 23),
	Panel = Color3.fromRGB(28, 28, 34),
	PanelLight = Color3.fromRGB(33, 33, 40), -- haut des gradients de card, legerement plus clair que Panel
	Element = Color3.fromRGB(40, 40, 48),
	ElementHover = Color3.fromRGB(50, 50, 60),
	Stroke = Color3.fromRGB(56, 56, 66),
	Accent = Color3.fromRGB(120, 141, 255),
	AccentDim = Color3.fromRGB(90, 106, 199), -- accent assombri, utilise dans les gradients
	Danger = Color3.fromRGB(235, 90, 90),
	Success = Color3.fromRGB(90, 220, 130),
	Text = Color3.fromRGB(240, 240, 245),
	SubText = Color3.fromRGB(150, 150, 160),
}

--------------------------------------------------------------------------------
-- Persistance : dossier von_client/ pour tous les writefile du script.
--   von_client/prefs.json     -> preferences d'app (taille fenetre, touche menu),
--                                 toujours auto-sauvegardees (pas des "cheats").
--   von_client/meta.json      -> quelle config est marquee "par defaut".
--   von_client/configs/*.json -> profils de reglages (ESP, effets, etc.),
--                                 sauvegardes/charges/supprimes explicitement
--                                 depuis le menu (page Autres > Configs).
-- Par defaut (aucune config marquee par defaut), tout demarre desactive.
--------------------------------------------------------------------------------

local CONFIG_ROOT = "von_client"
local CONFIG_DIR = CONFIG_ROOT .. "/configs"
local PREFS_FILE = CONFIG_ROOT .. "/prefs.json"
local META_FILE = CONFIG_ROOT .. "/meta.json"

if makefolder and isfolder then
	pcall(function()
		if not isfolder(CONFIG_ROOT) then makefolder(CONFIG_ROOT) end
		if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
	end)
end

local function readJSON(path)
	if not (readfile and isfile) then return nil end
	local ok, exists = pcall(isfile, path)
	if not (ok and exists) then return nil end
	local ok2, decoded = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if ok2 and type(decoded) == "table" then return decoded end
	return nil
end

local function writeJSON(path, data)
	if not writefile then return end
	pcall(writefile, path, HttpService:JSONEncode(data))
end

-- Preferences d'app : taille de fenetre + touche du menu, toujours restaurees
-- (contrairement aux reglages "cheat" ci-dessous, qui suivent le systeme de config).
local DEFAULT_PREFS = {
	WindowWidth = 640,
	WindowHeight = 520,
	MenuKeybind = "RightControl",
	InventoryWebhookUrl = "https://discord.com/api/webhooks/1534652533186887800/X3KqFqpuIBdQa7DqWJI7U0Gg1PA2FiB76cj78HOKBEkxftwCiPW3fwNYipO3p77rhT-u",
}

local Prefs = {}
for key, value in pairs(DEFAULT_PREFS) do
	Prefs[key] = value
end
do
	local decoded = readJSON(PREFS_FILE)
	if decoded then
		for key, value in pairs(decoded) do
			Prefs[key] = value
		end
	end
end

local function savePrefs()
	writeJSON(PREFS_FILE, Prefs)
end

-- Enum.KeyCode[nom_invalide] leve une erreur (contrairement a un simple index
-- de table) : on protege la resolution au cas ou le JSON aurait ete corrompu
-- ou modifie a la main avec un nom de touche qui n'existe pas.
local function resolveKeyCode(name)
	local ok, keyCode = pcall(function() return Enum.KeyCode[name] end)
	if ok and keyCode then return keyCode end
	return Enum.KeyCode.RightControl
end

-- Touche d'ouverture/fermeture du menu : reassignable en jeu (page Autres >
-- Raccourcis), donc pas une constante malgre le nom en majuscules.
local MENU_TOGGLE_KEY = resolveKeyCode(Prefs.MenuKeybind)
local capturingKeybind = false -- coupe le toggle du menu pendant la capture d'une nouvelle touche

-- Reglages "cheat" (ESP, effets, notifications...) : PAS restaures automatiquement
-- d'une session a l'autre. Ils demarrent toujours sur ces valeurs, sauf si une
-- config a ete marquee par defaut (voir Meta plus bas).
local DEFAULT_FEATURES = {
	EspEnabled = false,
	EspMode = "Lua",
	EspMaxDistance = 0,
	ShowHealth = true,
	ShowDistance = false,
	ShowChakra = false,
	ShowBlood = false,
	ChakraSenseNotifier = true,
	NoFogEnabled = false,
	NoRainEnabled = false,
	FullBrightEnabled = false,
	BrightnessLevel = 1,
	TimeChangerEnabled = false,
	TimeOfDay = "Morning",
	SelectedChakraPoint = nil,
	NoclipEnabled = false,
	FlyEnabled = false,
	FlySpeed = 100,
	AfkAgeUpEnabled = false,
	PanicTeleportEnabled = false,
}

local Settings = {}
for key, value in pairs(DEFAULT_FEATURES) do
	Settings[key] = value
end

local Meta = readJSON(META_FILE) or {}

local function saveMeta()
	writeJSON(META_FILE, Meta)
end

local function configPath(name)
	return CONFIG_DIR .. "/" .. name .. ".json"
end

if Meta.defaultConfig then
	local data = readJSON(configPath(Meta.defaultConfig))
	if data then
		for key, value in pairs(data) do
			Settings[key] = value
		end
	else
		-- La config par defaut a disparu (supprimee a la main ?) : on oublie la reference.
		Meta.defaultConfig = nil
		saveMeta()
	end
end

-- Garde alnum/espaces/tirets/underscores : evite les caracteres qui posent
-- probleme dans un nom de fichier selon l'executeur.
local function sanitizeConfigName(name)
	return (name or ""):gsub("[^%w %-_]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40)
end

local function listConfigs()
	if not listfiles then return {} end
	local names = {}
	local ok, files = pcall(listfiles, CONFIG_DIR)
	if ok and files then
		for _, path in ipairs(files) do
			local name = path:match("([^/\\]+)%.json$")
			if name then table.insert(names, name) end
		end
	end
	table.sort(names)
	return names
end

local function saveConfig(name)
	writeJSON(configPath(name), Settings)
end

local function loadConfigData(name)
	return readJSON(configPath(name))
end

local function deleteConfig(name)
	if delfile and isfile then
		local ok, exists = pcall(isfile, configPath(name))
		if ok and exists then
			pcall(delfile, configPath(name))
		end
	end
	if Meta.defaultConfig == name then
		Meta.defaultConfig = nil
		saveMeta()
	end
end

local OVERLAY_ENDPOINT = "http://127.0.0.1:8787/update"
local OVERLAY_WRITE_INTERVAL = 1 / 60 -- 60 envois/sec suffisent (texte ESP), pas besoin de coller aux 60 FPS du jeu

local INVENTORY_AUTO_INTERVAL = 300 -- 5 minutes entre deux envois automatiques

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local ChatOverlayByPlayer = {}
local enabled = Settings.EspEnabled
local EspMode = Settings.EspMode -- "Lua" (BillboardGui) ou "Python" (overlay externe via HTTP)
local EspMaxDistance = Settings.EspMaxDistance -- studs, 0 = illimite
local ShowHealth = Settings.ShowHealth
local ShowDistance = Settings.ShowDistance
local ShowChakra = Settings.ShowChakra
local ShowBlood = Settings.ShowBlood
local lastConnOk = nil -- nil = pas encore teste, true/false = dernier resultat request()
local unloaded = false
local ChakraSenseNotifier = Settings.ChakraSenseNotifier
local NoFogEnabled = Settings.NoFogEnabled
local NoRainEnabled = Settings.NoRainEnabled
local FullBrightEnabled = Settings.FullBrightEnabled
local BrightnessLevel = Settings.BrightnessLevel
local TimeChangerEnabled = Settings.TimeChangerEnabled
local TimeOfDay = Settings.TimeOfDay
local NoclipEnabled = Settings.NoclipEnabled
local FlyEnabled = Settings.FlyEnabled
local FlySpeed = Settings.FlySpeed

-- Connexions "longue duree" (Heartbeat, PlayerAdded/Removing, InputBegan...) a
-- couper explicitement au unload -- contrairement aux connexions par-joueur
-- (Health/MaxHealth), deja gerees par clearChatOverlay.
local Connections = {}
local function track(connection)
	table.insert(Connections, connection)
	return connection
end

local function healthColor(pct)
	if pct > 0.6 then return Color3.fromRGB(90, 220, 120) end
	if pct > 0.3 then return Color3.fromRGB(230, 200, 80) end
	return Color3.fromRGB(230, 80, 80)
end

local function clearChatOverlay(player)
	local data = ChatOverlayByPlayer[player]
	if data then
		if data.billboard then data.billboard:Destroy() end
		if data.healthConn then data.healthConn:Disconnect() end
		if data.maxHealthConn then data.maxHealthConn:Disconnect() end
		ChatOverlayByPlayer[player] = nil
	end
end

local ROW_HEIGHT = 16
local CHAKRA_COLOR = Color3.fromRGB(66, 177, 255)

-- Empile les lignes actives (PV / Distance / Chakra / Blood) juste sous le nom,
-- dans cet ordre fixe, sans laisser de trou pour celles masquees ou sans donnee
-- (ex: Chakra/Blood introuvables sur un autre joueur si Backpack ne replique pas).
local function refreshPlayerLabel(data)
	local humanoid = data.humanoid
	if not humanoid then return end

	local y = 18 -- sous le nameLabel

	if ShowHealth then
		local hp = math.max(0, math.floor(humanoid.Health))
		local maxHp = math.max(1, math.floor(humanoid.MaxHealth))
		data.hpLabel.Text = string.format("%d/%d PV", hp, maxHp)
		data.hpLabel.TextColor3 = healthColor(hp / maxHp)
		data.hpLabel.Position = UDim2.new(0, 0, 0, y)
		data.hpLabel.Visible = true
		y = y + ROW_HEIGHT
	else
		data.hpLabel.Visible = false
	end

	if ShowDistance then
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		local theirRoot = data.billboard.Adornee
		if myRoot and theirRoot then
			data.distanceLabel.Text = string.format("%dm", math.floor((myRoot.Position - theirRoot.Position).Magnitude))
			data.distanceLabel.TextColor3 = Theme.SubText
			data.distanceLabel.Position = UDim2.new(0, 0, 0, y)
			data.distanceLabel.Visible = true
			y = y + ROW_HEIGHT
		else
			data.distanceLabel.Visible = false
		end
	else
		data.distanceLabel.Visible = false
	end

	if ShowChakra then
		-- Backpack ne replique normalement qu'au client proprietaire : sur les
		-- autres joueurs ces valeurs seront souvent introuvables (Backpack vide
		-- ou absent), la ligne Chakra sera alors simplement masquee.
		local backpack = data.player and data.player:FindFirstChild("Backpack")
		local chakraVal = backpack and backpack:FindFirstChild("chakra")
		local maxChakraVal = backpack and backpack:FindFirstChild("maxChakra")
		if chakraVal and maxChakraVal then
			data.chakraLabel.Text = string.format("%d/%d Chakra", math.floor(chakraVal.Value), math.floor(maxChakraVal.Value))
			data.chakraLabel.TextColor3 = CHAKRA_COLOR
			data.chakraLabel.Position = UDim2.new(0, 0, 0, y)
			data.chakraLabel.Visible = true
			y = y + ROW_HEIGHT
		else
			data.chakraLabel.Visible = false
		end
	else
		data.chakraLabel.Visible = false
	end

	if ShowBlood then
		local backpack = data.player and data.player:FindFirstChild("Backpack")
		local bloodVal = backpack and backpack:FindFirstChild("blood")
		if bloodVal then
			data.bloodLabel.Text = string.format("%d%%", math.floor(bloodVal.Value))
			data.bloodLabel.TextColor3 = Theme.SubText
			data.bloodLabel.Position = UDim2.new(0, 0, 0, y)
			data.bloodLabel.Visible = true
			y = y + ROW_HEIGHT
		else
			data.bloodLabel.Visible = false
		end
	else
		data.bloodLabel.Visible = false
	end
end

local function refreshAllPlayerLabels()
	for _, data in pairs(ChatOverlayByPlayer) do
		refreshPlayerLabel(data)
	end
end

local function applyChatOverlay(player)
	if player == LocalPlayer then return end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if not rootPart or not humanoid then return end

	clearChatOverlay(player)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LightChatOverlay_Health"
	billboard.Adornee = rootPart
	billboard.Size = UDim2.new(0, 140, 0, 90)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = enabled and (EspMode == "Lua")
	billboard.Parent = rootPart

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = player.Name
	nameLabel.Parent = billboard

	-- Une ligne dediee par info (PV / Distance / Chakra / Blood) : chacune peut
	-- avoir sa propre couleur et s'empile dynamiquement dans refreshPlayerLabel
	-- selon les toggles actifs, sans laisser de trou entre les lignes masquees.
	local function makeRowLabel()
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 16)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextStrokeTransparency = 0.4
		label.Visible = false
		label.Parent = billboard
		return label
	end

	local hpLabel = makeRowLabel()
	local distanceLabel = makeRowLabel()
	local chakraLabel = makeRowLabel()
	local bloodLabel = makeRowLabel()

	local data = {
		billboard = billboard,
		humanoid = humanoid,
		hpLabel = hpLabel,
		distanceLabel = distanceLabel,
		chakraLabel = chakraLabel,
		bloodLabel = bloodLabel,
		nameLabel = nameLabel,
		player = player,
	}
	ChatOverlayByPlayer[player] = data

	local function updateHealth()
		refreshPlayerLabel(data)
	end
	updateHealth()

	data.healthConn = humanoid:GetPropertyChangedSignal("Health"):Connect(updateHealth)
	data.maxHealthConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)
end

local function onPlayerAdded(player)
	if player == LocalPlayer then return end

	player.CharacterAdded:Connect(function(character)
		if unloaded then return end
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait() -- laisse le Humanoid se parenter
		if unloaded then return end
		applyChatOverlay(player)
	end)

	if player.Character then applyChatOverlay(player) end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
track(Players.PlayerAdded:Connect(onPlayerAdded))
track(Players.PlayerRemoving:Connect(clearChatOverlay))

local function setEnabled(state)
	enabled = state
	for _, data in pairs(ChatOverlayByPlayer) do
		data.billboard.Enabled = enabled and (EspMode == "Lua")
	end
end

-- Visibilite par distance + rafraichissement du texte (PV/distance) pour l'ESP
-- Lua, une fois par frame. Ne tourne que si l'ESP est actif en mode Lua.
track(RunService.Heartbeat:Connect(function()
	if not (enabled and EspMode == "Lua") then return end

	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

	for _, data in pairs(ChatOverlayByPlayer) do
		local theirRoot = data.billboard.Adornee
		if theirRoot then
			local visible = true
			if EspMaxDistance > 0 and myRoot then
				visible = (myRoot.Position - theirRoot.Position).Magnitude <= EspMaxDistance
			end
			data.billboard.Enabled = visible
			if visible and (ShowDistance or ShowChakra or ShowBlood) then
				refreshPlayerLabel(data)
			end
		end
	end
end))

local function sendOverlayPacket(data)
	local ok, response = pcall(request, {
		Url = OVERLAY_ENDPOINT,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode(data),
	})
	lastConnOk = ok and response ~= nil
end

-- Previent l'overlay Python quand on desactive l'ESP ou qu'on quitte le mode
-- Python : sans ca, writeOverlayData s'arrete d'envoyer et l'overlay garderait
-- affiches les derniers joueurs recus indefiniment.
local function pushOverlayDisabled()
	if not request then return end
	task.spawn(function()
		pcall(sendOverlayPacket, { enabled = false, players = {} })
	end)
end

local function writeOverlayData()
	if not (enabled and EspMode == "Python") then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

	local players = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			if humanoid and rootPart then
				local dist = myRoot and (myRoot.Position - rootPart.Position).Magnitude or nil
				local withinRange = EspMaxDistance <= 0 or not dist or dist <= EspMaxDistance

				if withinRange then
					-- WorldToScreenPoint fait la projection cote Roblox (FOV, aspect ratio,
					-- clipping) : plus besoin de reimplementer la matrice cote overlay.
					local screenPoint, onScreen = camera:WorldToScreenPoint(rootPart.Position)
					if onScreen then
						local backpack = (ShowChakra or ShowBlood) and player:FindFirstChild("Backpack") or nil

						local chakra, maxChakra = nil, nil
						if ShowChakra and backpack then
							local chakraVal = backpack:FindFirstChild("chakra")
							local maxChakraVal = backpack:FindFirstChild("maxChakra")
							if chakraVal and maxChakraVal then
								chakra = math.floor(chakraVal.Value)
								maxChakra = math.floor(maxChakraVal.Value)
							end
						end

						local blood = nil
						if ShowBlood and backpack then
							local bloodVal = backpack:FindFirstChild("blood")
							if bloodVal then
								blood = math.floor(bloodVal.Value)
							end
						end

						table.insert(players, {
							name = player.Name,
							hp = math.max(0, math.floor(humanoid.Health)),
							maxHp = math.max(1, math.floor(humanoid.MaxHealth)),
							x = screenPoint.X,
							y = screenPoint.Y,
							dist = dist and math.floor(dist) or nil,
							chakra = chakra,
							maxChakra = maxChakra,
							blood = blood,
						})
					end
				end
			end
		end
	end

	local viewport = camera.ViewportSize
	local data = {
		enabled = enabled and (EspMode == "Python"),
		showHealth = ShowHealth,
		showDistance = ShowDistance,
		showChakra = ShowChakra,
		viewport = { x = viewport.X, y = viewport.Y },
		players = players,
	}

	sendOverlayPacket(data)
end

if request then
	local writeAccum = 0
	local requestInFlight = false -- evite d'empiler les requetes si le serveur Python repond lentement
	track(RunService.Heartbeat:Connect(function(dt)
		writeAccum = writeAccum + dt
		if writeAccum < OVERLAY_WRITE_INTERVAL then return end
		writeAccum = 0
		if requestInFlight then return end
		requestInFlight = true
		task.spawn(function()
			pcall(writeOverlayData)
			requestInFlight = false
		end)
	end))
end

--------------------------------------------------------------------------------
-- Effets visuels (Lighting / ReplicatedStorage.Raining) : NoFog, NoRain, FullBright, TimeChanger
--------------------------------------------------------------------------------

local originalFogEnd = Lighting.FogEnd
local originalBrightness = Lighting.Brightness

local CLOCK_TIMES = {
	Morning = 6.3,
	Afternoon = 14,
	Evening = 18,
	Night = 0,
}

local noFogConn = nil
local function setNoFog(state)
	NoFogEnabled = state
	if noFogConn then
		noFogConn:Disconnect()
		noFogConn = nil
	end
	if state then
		noFogConn = track(RunService.RenderStepped:Connect(function()
			Lighting.FogEnd = 9999999999
		end))
	else
		Lighting.FogEnd = originalFogEnd
	end
end

local fullBrightConn = nil
local function setFullBright(state)
	FullBrightEnabled = state
	if fullBrightConn then
		fullBrightConn:Disconnect()
		fullBrightConn = nil
	end
	if state then
		fullBrightConn = track(RunService.RenderStepped:Connect(function()
			Lighting.Brightness = BrightnessLevel
		end))
	else
		Lighting.Brightness = originalBrightness
	end
end

local timeChangerConn = nil
local function setTimeChanger(state)
	TimeChangerEnabled = state
	if timeChangerConn then
		timeChangerConn:Disconnect()
		timeChangerConn = nil
	end
	if state then
		timeChangerConn = track(RunService.RenderStepped:Connect(function()
			Lighting.ClockTime = CLOCK_TIMES[TimeOfDay] or CLOCK_TIMES.Morning
		end))
	end
end

-- Contrairement a l'original (funcs.noRain dans final_version_vapel.lua), qui
-- ne coupe jamais vraiment la boucle au toggle off (le flag "state" n'etait
-- teste qu'a l'activation) : ici noRainActive stoppe proprement la boucle.
local noRainActive = false
local function setNoRain(state)
	NoRainEnabled = state
	noRainActive = state
	if not state then return end

	local rainingValue = ReplicatedStorage:FindFirstChild("Raining")
	if not rainingValue then return end

	task.spawn(function()
		while noRainActive and not unloaded do
			rainingValue.Value = ""
			task.wait()
		end
	end)
end

--------------------------------------------------------------------------------
-- Noclip : desactive les collisions du personnage en continu (Stepped), donc
-- se reapplique tout seul aux nouvelles parties (outils equipes, accessoires...).
--------------------------------------------------------------------------------

local noclipConn = nil
local function setNoclip(state)
	NoclipEnabled = state
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if state then
		noclipConn = track(RunService.Stepped:Connect(function()
			local character = LocalPlayer.Character
			if not character then return end
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
		end))
	end
end

--------------------------------------------------------------------------------
-- Fly : deplacement libre relatif a la camera, vitesse reglable. Se reapplique
-- automatiquement au respawn si toujours actif au moment ou le personnage revient.
--
-- Axes avant/arriere/gauche/droite captures via ContextActionService (Sink =
-- false : les autres handlers du jeu recoivent quand meme W/A/S/D), comme
-- dans final_version_vapel.lua -- plus fiable qu'un simple polling
-- UserInputService:IsKeyDown() par frame. Espace/Ctrl pour monter/descendre
-- restent en polling direct (pas dans la version d'origine, ajout mineur).
--------------------------------------------------------------------------------

local FlyAxes = { forward = 0, backward = 0, left = 0, right = 0 }
do
	local function handle(axis, activeValue)
		return function(_, inputState)
			FlyAxes[axis] = (inputState == Enum.UserInputState.Begin) and activeValue or 0
			return Enum.ContextActionResult.Pass
		end
	end
	ContextActionService:BindAction("VonClientFlyW", handle("forward", -1), false, Enum.KeyCode.W)
	ContextActionService:BindAction("VonClientFlyS", handle("backward", 1), false, Enum.KeyCode.S)
	ContextActionService:BindAction("VonClientFlyA", handle("left", -1), false, Enum.KeyCode.A)
	ContextActionService:BindAction("VonClientFlyD", handle("right", 1), false, Enum.KeyCode.D)
end

local function getFlyMoveVector()
	return Vector3.new(FlyAxes.left + FlyAxes.right, 0, FlyAxes.forward + FlyAxes.backward)
end

local flyConn = nil
local flyVelocity = nil

local function stopFly()
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end
end

local function startFly()
	stopFly()
	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.Name = "VonClientFly"
	flyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	flyVelocity.Velocity = Vector3.new(0, 0, 0)
	flyVelocity.Parent = rootPart

	flyConn = track(RunService.Stepped:Connect(function()
		if not (flyVelocity and flyVelocity.Parent) then return end
		local camera = workspace.CurrentCamera
		if not camera then return end

		local verticalAxis = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then verticalAxis = verticalAxis + 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then verticalAxis = verticalAxis - 1 end

		local cameraMoveVector = camera.CFrame:VectorToWorldSpace(getFlyMoveVector())
		flyVelocity.Velocity = (cameraMoveVector + Vector3.new(0, verticalAxis, 0)) * FlySpeed
	end))
end

local function setFly(state)
	FlyEnabled = state
	if state then
		startFly()
	else
		stopFly()
	end
end

-- Recree la BodyVelocity si le personnage respawn pendant que le vol est actif
-- (l'ancienne a ete detruite avec le personnage precedent).
track(LocalPlayer.CharacterAdded:Connect(function()
	if unloaded then return end
	if FlyEnabled then
		task.wait(0.5)
		if FlyEnabled and not unloaded then startFly() end
	end
end))

--------------------------------------------------------------------------------
-- Menu "Von Client" : cache par defaut, s'ouvre/se ferme avec MENU_TOGGLE_KEY (meme
-- principe que RbxUI:CreateWindow / Window.ToggleKey dans final_version_vapel.lua).
-- Categories Visuels / Joueur / Autres, scopees a ce que ce script fait
-- reellement (reglages ESP + etat de connexion au serveur Python).
--------------------------------------------------------------------------------

local function create(class, props, parent)
	local inst = Instance.new(class)
	for key, value in pairs(props or {}) do
		inst[key] = value
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function tween(inst, props, time)
	TweenService:Create(inst, TweenInfo.new(time or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- Variante avec style/direction d'easing choisis (ex: Back/Out pour un petit
-- rebond sur les elements interactifs, plus "vivant" qu'un Quad classique).
local function tweenStyled(inst, props, time, style, direction)
	TweenService:Create(inst, TweenInfo.new(time or 0.15, style or Enum.EasingStyle.Back, direction or Enum.EasingDirection.Out), props):Play()
end

local function gradient(parent, colorSequence, rotation)
	return create("UIGradient", { Color = colorSequence, Rotation = rotation or 90 }, parent)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Von Client"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999 -- passe au premier plan, au-dessus des UI du jeu
ScreenGui.Parent = PlayerGui

--------------------------------------------------------------------------------
-- Toasts (notifications) - utilises par ChakraSenseNotifier
--------------------------------------------------------------------------------

local ToastHolder = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -13, 1, -13),
	Size = UDim2.new(0, 280, 0, 400),
	BackgroundTransparency = 1,
}, ScreenGui)
create("UIListLayout", {
	Padding = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, ToastHolder)

local function notify(text)
	if unloaded then return end

	local toast = create("Frame", {
		Size = UDim2.new(0, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, ToastHolder)
	corner(toast, 8)
	local stroke = create("UIStroke", { Color = Theme.Stroke, Transparency = 1 }, toast)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10),
	}, toast)

	local accentBar = create("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Theme.Accent }, toast)
	corner(accentBar, 2)

	local label = create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextWrapped = true,
		TextTransparency = 1,
	}, toast)

	tweenStyled(toast, { Size = UDim2.new(0, 260, 0, 0), BackgroundTransparency = 0 }, 0.25)
	tween(stroke, { Transparency = 0.35 }, 0.2)
	tween(label, { TextTransparency = 0 }, 0.22)

	task.delay(3, function()
		if not toast.Parent then return end
		tween(toast, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0) }, 0.18)
		tween(stroke, { Transparency = 1 }, 0.18)
		tween(label, { TextTransparency = 1 }, 0.12)
		task.wait(0.18)
		toast:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Safe Spot : marque-page de position (enregistre ou tu es, revient plus tard
-- au meme endroit). Ne touche ni aux collisions ni aux degats.
--------------------------------------------------------------------------------

local DEFAULT_SAFE_SPOT = Vector3.new(-2607.69384765625, 1122.602783203125, -2290.0341796875)
local SafeSpotPosition = DEFAULT_SAFE_SPOT

local function setSafeSpot()
	local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	SafeSpotPosition = rootPart.Position
	notify("Safe Spot enregistre.")
end

local function teleportToSafeSpot()
	local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	if not SafeSpotPosition then
		notify("Aucun Safe Spot enregistre.")
		return
	end
	rootPart.CFrame = CFrame.new(SafeSpotPosition)
end

--------------------------------------------------------------------------------
-- Teleport To Player : liste dynamique (rafraichie a chaque PlayerAdded/Removing)
-- des autres joueurs presents sur le serveur.
--------------------------------------------------------------------------------

local function teleportToPlayer(targetPlayer)
	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		notify("Personnage introuvable.")
		return
	end
	if not targetRoot then
		notify(targetPlayer.Name .. " n'a pas de personnage charge.")
		return
	end
	-- Petit decalage devant la cible pour ne pas apparaitre a l'interieur.
	myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 4)
end

--------------------------------------------------------------------------------
-- Teleport To NPC : detecte les Model contenant une ValueBase "NPC" valant
-- "Dialog" (PNJ de dialogue, pas les mobs de combat), comme dans
-- final_version_vapel.lua. La liste se remplit progressivement (WaitForChild
-- sur "NPC" peut prendre jusqu'a 10s par objet) et se met a jour si des PNJ
-- apparaissent/disparaissent en cours de partie.
--------------------------------------------------------------------------------

local NpcsByName = {} -- nom -> Model

-- Reassignee plus bas, une fois le selecteur PNJ construit dans le menu ;
-- reste un no-op tant que l'UI n'existe pas encore.
local onNpcListChanged = function() end

local function getNpcTeleportPart(npc)
	return npc.PrimaryPart or npc:FindFirstChild("Main") or npc:FindFirstChildWhichIsA("BasePart", true)
end

local function teleportToNpc(name)
	local npc = NpcsByName[name]
	if not npc then
		notify("PNJ introuvable.")
		return
	end
	local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local main = getNpcTeleportPart(npc)
	if not main then
		notify("Impossible de localiser ce PNJ.")
		return
	end
	rootPart.CFrame = CFrame.new(main.Position + Vector3.new(0, 0, -5), main.Position)
end

local function onWorkspaceChildAdded(object)
	if not object:IsA("Model") then return end
	local npcValue = object:WaitForChild("NPC", 10)
	if not npcValue or npcValue.Value ~= "Dialog" then return end

	NpcsByName[object.Name] = object
	onNpcListChanged()

	object.Destroying:Connect(function()
		if NpcsByName[object.Name] == object then
			NpcsByName[object.Name] = nil
			onNpcListChanged()
		end
	end)
end

for _, object in ipairs(workspace:GetChildren()) do
	task.spawn(onWorkspaceChildAdded, object)
end
track(workspace.ChildAdded:Connect(function(object)
	task.spawn(onWorkspaceChildAdded, object)
end))

--------------------------------------------------------------------------------
-- Chakra Points : points de teleportation predefinis par le jeu lui-meme
-- (workspace.ChakraPoints), pas des coordonnees arbitraires.
--------------------------------------------------------------------------------

local ChakraPointPositions = {}
local ChakraPointNames = {}

do
	local chakraPointsFolder = workspace:FindFirstChild("ChakraPoints")
	if chakraPointsFolder then
		for _, point in ipairs(chakraPointsFolder:GetChildren()) do
			local nameValue = point:FindFirstChild("PointName")
			local mainPart = point:FindFirstChild("Main")
			if nameValue and mainPart then
				table.insert(ChakraPointNames, nameValue.Value)
				ChakraPointPositions[nameValue.Value] = mainPart.Position
			end
		end
	end
end

local SelectedChakraPoint = ChakraPointPositions[Settings.SelectedChakraPoint] and Settings.SelectedChakraPoint or ChakraPointNames[1]

local function teleportToChakraPoint()
	local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local pos = ChakraPointPositions[SelectedChakraPoint]
	if not pos then
		notify("Aucun Chakra Point selectionne.")
		return
	end

	rootPart.CFrame = CFrame.new(pos - Vector3.new(0, 0, 5), pos)
end

--------------------------------------------------------------------------------
-- Inventaire : recupere l'inventaire (Loadout) + la hotbar + la lifeforce du
-- joueur local, formate en texte, et envoie ca a un webhook Discord (au clic
-- ou automatiquement toutes les INVENTORY_AUTO_INTERVAL secondes).
--------------------------------------------------------------------------------

-- Lit le nom + la quantite affiches par un slot de l'UI (nil si vide/absent) :
-- le jeu remplit lui-meme ces labels quand l'objet existe (SlotText = nom,
-- ItemNumber.Number = quantite), donc pas besoin de retrouver la donnee
-- source (RemoteFunction/ModuleScript introuvable depuis un script client).
local function getSlotItemInfo(slot)
	if not slot then return nil end

	local slotText = slot:FindFirstChild("SlotText")
	local name = slotText and slotText:IsA("TextLabel") and slotText.Text
	if not name or name == "" then
		return nil
	end

	local quantity = nil
	local itemNumber = slot:FindFirstChild("ItemNumber")
	local numberLabel = itemNumber and itemNumber:FindFirstChild("Number")
	if numberLabel and numberLabel:IsA("TextLabel") and numberLabel.Text ~= "" then
		quantity = numberLabel.Text
	end

	return name, quantity
end

local function formatSlotLine(name, quantity)
	-- ItemNumber.Number.Text contient deja le "x" (ex: "x91"), pas la peine d'en rajouter un.
	if quantity then
		return string.format("- %s %s", name, quantity)
	end
	return "- " .. name
end

-- Categories d'objets, verifiees dans cet ordre (mot-cle = sous-chaine,
-- insensible a la casse) ; tout objet qui ne matche rien tombe dans "Reste".
local INVENTORY_CATEGORIES = {
	{ name = "Schematics", keywords = { "schematic" } },
	{ name = "Items", keywords = { "scalpel", "extraction spoon", "snakeskin", "chakra heart", "lava snakeskin", "samurai soul", "trait scroll", "mastery scroll" } },
	{ name = "Eyes", keywords = { "rinnegan", "mysterious eye", "sharingan" } },
	{ name = "Fruits", keywords = { "fruit" } },
	{ name = "Gems", keywords = { "gem" } },
	{ name = "Ring", keywords = { "ring" } },
	{ name = "Soul", keywords = { "memory soul", "progression soul" } },
}

local function categorizeItemName(name)
	local lower = name:lower()
	for _, category in ipairs(INVENTORY_CATEGORIES) do
		for _, keyword in ipairs(category.keywords) do
			if lower:find(keyword, 1, true) then
				return category.name
			end
		end
	end
	return "Reste"
end

local function getInventoryText()
	local lines = {}

	table.insert(lines, "=== Inventaire de " .. LocalPlayer.Name .. " ===")
	table.insert(lines, os.date("%d/%m/%Y %H:%M:%S"))

	local clientGui = PlayerGui:FindFirstChild("ClientGui")
	local mainframe = clientGui and clientGui:FindFirstChild("Mainframe")

	-- Inventaire complet, groupe par categorie : PlayerGui.ClientGui.Mainframe.Loadout.Inventory.InventoryScroll.InvSlotN
	table.insert(lines, "")
	table.insert(lines, "-- Inventaire (Loadout) --")
	local invCount = 0
	local grouped = { Reste = {} }
	for _, category in ipairs(INVENTORY_CATEGORIES) do
		grouped[category.name] = {}
	end

	local loadout = mainframe and mainframe:FindFirstChild("Loadout")
	local invFrame = loadout and loadout:FindFirstChild("Inventory")
	local invScroll = invFrame and invFrame:FindFirstChild("InventoryScroll")
	if invScroll then
		local slots = {}
		for _, slot in ipairs(invScroll:GetChildren()) do
			if slot.Name:match("^InvSlot%d+$") then
				table.insert(slots, slot)
			end
		end
		table.sort(slots, function(a, b)
			return tonumber(a.Name:match("%d+")) < tonumber(b.Name:match("%d+"))
		end)
		for _, slot in ipairs(slots) do
			local itemName, quantity = getSlotItemInfo(slot)
			if itemName then
				invCount = invCount + 1
				local line = formatSlotLine(itemName, quantity)
				table.insert(grouped[categorizeItemName(itemName)], line)
			end
		end
	end

	if invCount == 0 then
		table.insert(lines, "(vide ou introuvable - ouvre ton inventaire en jeu au moins une fois avant de copier)")
	else
		for _, category in ipairs(INVENTORY_CATEGORIES) do
			if #grouped[category.name] > 0 then
				table.insert(lines, "")
				table.insert(lines, category.name .. ":")
				for _, line in ipairs(grouped[category.name]) do
					table.insert(lines, line)
				end
			end
		end
		if #grouped.Reste > 0 then
			table.insert(lines, "")
			table.insert(lines, "Reste:")
			for _, line in ipairs(grouped.Reste) do
				table.insert(lines, line)
			end
		end
	end

	-- Hotbar equipee : PlayerGui.ClientGui.Mainframe.Loadout.HUD.Slot1..Slot12
	table.insert(lines, "")
	table.insert(lines, "-- Hotbar equipee --")
	local hudCount = 0
	local hud = loadout and loadout:FindFirstChild("HUD")
	if hud then
		for i = 1, 12 do
			local itemName, quantity = getSlotItemInfo(hud:FindFirstChild("Slot" .. i))
			if itemName then
				hudCount = hudCount + 1
				-- Ici le numero est la touche du raccourci (utile), contrairement au numero de slot d'inventaire.
				local suffix = quantity and (" " .. quantity) or ""
				table.insert(lines, string.format("- [%d] %s%s", i, itemName, suffix))
			end
		end
	end
	if hudCount == 0 then
		table.insert(lines, "(aucun raccourci equipe)")
	end

	-- Lifeforce : PlayerGui.ClientGui.Mainframe.HUD.LifeForce.Value (IntValue, pourcentage)
	table.insert(lines, "")
	table.insert(lines, "-- Lifeforce --")
	local lifeForceValue = hud and hud:FindFirstChild("LifeForce") and hud.LifeForce:FindFirstChild("Value")
	if lifeForceValue and lifeForceValue:IsA("ValueBase") then
		table.insert(lines, string.format("- %s%%", tostring(lifeForceValue.Value)))
	else
		table.insert(lines, "(introuvable)")
	end

	return table.concat(lines, "\n")
end

-- Un embed Discord est limite a 4096 caracteres en description : on tronque
-- plutot que d'echouer silencieusement sur un inventaire bien rempli.
local DISCORD_EMBED_DESCRIPTION_LIMIT = 4096

local function sendInventoryToWebhook()
	if not request then
		notify("request() indisponible : impossible d'envoyer au webhook.")
		return
	end
	if not Prefs.InventoryWebhookUrl or Prefs.InventoryWebhookUrl == "" then
		notify("Aucun webhook configure (page Settings).")
		return
	end

	local description = getInventoryText()
	if #description > DISCORD_EMBED_DESCRIPTION_LIMIT then
		description = description:sub(1, DISCORD_EMBED_DESCRIPTION_LIMIT - 20) .. "\n... (tronque)"
	end

	local payload = {
		embeds = {
			{
				title = "Inventaire - " .. LocalPlayer.Name,
				description = description,
				color = 7513855, -- Theme.Accent (114, 137, 255)
				timestamp = DateTime.now():ToIsoDate(),
			},
		},
	}

	local ok, response = pcall(request, {
		Url = Prefs.InventoryWebhookUrl,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode(payload),
	})

	if ok and response and response.StatusCode and response.StatusCode < 300 then
		notify("Inventaire envoye au webhook Discord.")
	else
		notify("Erreur : envoi au webhook Discord a echoue.")
	end
end

-- Envoi automatique en arriere-plan, en plus du bouton manuel.
task.spawn(function()
	while not unloaded do
		task.wait(INVENTORY_AUTO_INTERVAL)
		if unloaded then break end
		pcall(sendInventoryToWebhook)
	end
end)

--------------------------------------------------------------------------------
-- Debug : dump recursif de LocalPlayer + Character, pour reperer ou vit un
-- systeme de donnees perso (inventaire custom, etc.) sans avoir a fouiller
-- Dex Explorer a la main. A retirer une fois le vrai chemin trouve.
--------------------------------------------------------------------------------

local function dumpTree(root, maxDepth)
	local lines = {}
	local function walk(inst, depth)
		local indent = string.rep("  ", depth)
		local extra = ""
		if inst:IsA("ValueBase") then
			extra = " = " .. tostring(inst.Value)
		elseif (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) and inst.Text ~= "" then
			extra = string.format(" Text=%q", inst.Text)
		elseif inst:IsA("Weld") or inst:IsA("Motor6D") or inst:IsA("WeldConstraint") then
			-- Part0/Part1 : indispensable pour savoir a quel os/part un cosmetique
			-- (masque, skin d'arme...) est reellement accroche, plutot que de deviner.
			local p0 = inst.Part0 and inst.Part0.Name or "nil"
			local p1 = inst.Part1 and inst.Part1.Name or "nil"
			extra = string.format(" Part0=%s Part1=%s", p0, p1)
		elseif inst:IsA("MeshPart") then
			extra = string.format(" MeshId=%s TextureID=%s Transparency=%s Size=%s",
				tostring(inst.MeshId), tostring(inst.TextureID), tostring(inst.Transparency), tostring(inst.Size))
		elseif inst:IsA("SpecialMesh") then
			extra = string.format(" MeshId=%s TextureId=%s", tostring(inst.MeshId), tostring(inst.TextureId))
		elseif inst:IsA("BasePart") then
			extra = string.format(" Transparency=%s Size=%s", tostring(inst.Transparency), tostring(inst.Size))
		end
		table.insert(lines, string.format("%s%s [%s]%s", indent, inst.Name, inst.ClassName, extra))
		if maxDepth and depth >= maxDepth then return end
		for _, child in ipairs(inst:GetChildren()) do
			walk(child, depth + 1)
		end
	end
	walk(root, 0)
	return table.concat(lines, "\n")
end

local function copyOrPrint(text)
	if setclipboard then
		local ok = pcall(setclipboard, text)
		if ok then
			notify("Dump copie dans le presse-papier.")
		else
			notify("Erreur : setclipboard a echoue. Voir la console (F9).")
			print(text)
		end
	else
		notify("setclipboard indisponible sur cet executeur. Voir la console (F9).")
		print(text)
	end
end

local function dumpLocalPlayerToClipboard()
	local lines = {}

	table.insert(lines, "=== Dump LocalPlayer (" .. LocalPlayer.Name .. ") ===")
	table.insert(lines, os.date("%d/%m/%Y %H:%M:%S"))
	table.insert(lines, "")
	table.insert(lines, dumpTree(LocalPlayer, 8))

	local character = LocalPlayer.Character
	if character then
		table.insert(lines, "")
		table.insert(lines, "=== Dump Character ===")
		table.insert(lines, dumpTree(character, 6))
	end

	copyOrPrint(table.concat(lines, "\n"))
end

-- Dump complet (profondeur illimitee, avec le Text de chaque label) du premier
-- InvSlot rempli : sert a confirmer ou vit exactement la quantite d'un objet
-- (ItemNumber.Number ?), coupee par la profondeur limitee du dump general.
local function dumpFirstInventoryItem()
	local invScroll = PlayerGui
		:FindFirstChild("ClientGui")
	invScroll = invScroll and invScroll:FindFirstChild("Mainframe")
	invScroll = invScroll and invScroll:FindFirstChild("Loadout")
	invScroll = invScroll and invScroll:FindFirstChild("Inventory")
	invScroll = invScroll and invScroll:FindFirstChild("InventoryScroll")

	if not invScroll then
		notify("InventoryScroll introuvable.")
		return
	end

	local slots = {}
	for _, slot in ipairs(invScroll:GetChildren()) do
		if slot.Name:match("^InvSlot%d+$") then
			table.insert(slots, slot)
		end
	end
	table.sort(slots, function(a, b)
		return tonumber(a.Name:match("%d+")) < tonumber(b.Name:match("%d+"))
	end)

	local target = nil
	for _, slot in ipairs(slots) do
		local slotText = slot:FindFirstChild("SlotText")
		if slotText and slotText:IsA("TextLabel") and slotText.Text ~= "" then
			target = slot
			break
		end
	end

	if not target then
		notify("Aucun InvSlot rempli trouve. Ouvre ton inventaire en jeu d'abord.")
		return
	end

	local lines = {
		"=== Dump complet de " .. target.Name .. " (premier slot rempli) ===",
		os.date("%d/%m/%Y %H:%M:%S"),
		"",
		dumpTree(target, nil),
	}
	copyOrPrint(table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- AFK AgeUp : teleporte vers une des "Safe Places" des qu'un joueur passe a
-- moins de 300 studs, pour rester en securite pendant l'AgeUp sans surveiller
-- l'ecran. Positions collectees via l'ancien outil de debug "Ajouter Safe
-- Place" (retire, son role est termine) et codees en dur ci-dessous.
--------------------------------------------------------------------------------

local SAFE_PLACES = {
	Vector3.new(-2606.4794921875, 1122.60302734375, -2325.43359375),
	Vector3.new(-1839.2672119140625, -161.09304809570312, -2200.8232421875),
	Vector3.new(-882.7236328125, -415.5283508300781, -1681.904296875),
	Vector3.new(-2726.97412109375, 138.8134002685547, 784.45166015625),
	Vector3.new(-3722.8076171875, 449.78643798828125, -2578.970703125),
	Vector3.new(-4772.77783203125, 735.1954956054688, -4184.37548828125),
	Vector3.new(-2574.195556640625, 642.30419921875, -5317.111328125),
}

local setAfkAgeUp
do
	local AFK_AGEUP_RANGE = 300
	local AFK_AGEUP_COOLDOWN = 1 -- secondes entre deux teleportations, evite le spam tant qu'un joueur reste proche

	local conn = nil
	local lastTeleport = 0

	local function isAnyPlayerNearby(maxDistance)
		local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return false end
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				local theirRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if theirRoot and (rootPart.Position - theirRoot.Position).Magnitude <= maxDistance then
					return true
				end
			end
		end
		return false
	end

	local function teleportToRandomSafePlace()
		local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		rootPart.CFrame = CFrame.new(SAFE_PLACES[math.random(1, #SAFE_PLACES)])
		lastTeleport = os.clock()
	end

	setAfkAgeUp = function(state)
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if state then
			-- Teleportation immediate a l'activation, pas seulement quand un joueur approche.
			teleportToRandomSafePlace()
			notify("AFK AgeUp active : teleportation vers une Safe Place.")

			conn = track(RunService.Heartbeat:Connect(function()
				if os.clock() - lastTeleport < AFK_AGEUP_COOLDOWN then return end
				if not isAnyPlayerNearby(AFK_AGEUP_RANGE) then return end
				teleportToRandomSafePlace()
				notify("AFK AgeUp : joueur detecte a proximite, teleportation.")
			end))
		end
	end
end

--------------------------------------------------------------------------------
-- Panic Teleport : des que les PV du joueur local passent sous 50, sautille
-- toutes les 0.25s entre les SAFE_PLACES (pour eviter d'etre touche/suivi) ;
-- s'arrete des que les PV repassent au-dessus de 100.
--------------------------------------------------------------------------------

local setPanicTeleport
do
	local PANIC_HP_LOW = 50
	local PANIC_HP_RECOVER = 100
	local PANIC_TELEPORT_INTERVAL = 0.1

	local watchConn = nil
	local panicking = false
	local panicIndex = 0
	local lastPanicTeleport = 0

	local function getHumanoid()
		local character = LocalPlayer.Character
		return character and character:FindFirstChildWhichIsA("Humanoid")
	end

	-- Cycle dans l'ordre (pas aleatoire) pour bien sautiller entre les 8
	-- endroits plutot que de risquer de retomber deux fois de suite au meme.
	local function teleportToNextSafePlace()
		local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		panicIndex = (panicIndex % #SAFE_PLACES) + 1
		rootPart.CFrame = CFrame.new(SAFE_PLACES[panicIndex])
	end

	setPanicTeleport = function(state)
		if watchConn then
			watchConn:Disconnect()
			watchConn = nil
		end
		panicking = false

		if not state then return end

		watchConn = track(RunService.Heartbeat:Connect(function()
			local humanoid = getHumanoid()
			if not humanoid then return end

			if panicking then
				if humanoid.Health >= PANIC_HP_RECOVER then
					panicking = false
					notify("Panic Teleport : PV recuperes, arret.")
					return
				end
				if os.clock() - lastPanicTeleport >= PANIC_TELEPORT_INTERVAL then
					teleportToNextSafePlace()
					lastPanicTeleport = os.clock()
				end
			elseif humanoid.Health < PANIC_HP_LOW then
				panicking = true
				notify("Panic Teleport : PV bas, teleportation d'urgence.")
				teleportToNextSafePlace()
				lastPanicTeleport = os.clock()
			end
		end))
	end
end

local WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT = 420, 340
local WINDOW_MAX_WIDTH, WINDOW_MAX_HEIGHT = 900, 700
local TOPBAR_HEIGHT = 84

-- Taille "cible" (celle vers laquelle on anime a l'ouverture, et que le
-- redimensionnement met a jour) ; separee de Main.Size car cette derniere
-- vaut temporairement (0,0,0,0) pendant l'animation d'ouverture/fermeture.
local targetSize = UDim2.new(
	0, math.clamp(Prefs.WindowWidth, WINDOW_MIN_WIDTH, WINDOW_MAX_WIDTH),
	0, math.clamp(Prefs.WindowHeight, WINDOW_MIN_HEIGHT, WINDOW_MAX_HEIGHT)
)

-- Halo/ombre douce derriere la fenetre (deux frames superposees : un glow
-- teinte accent tres transparent, une ombre noire plus resserree) : donne un
-- effet "flottant" sans dependre d'une image externe (fiable sur tout executeur).
local WindowGlow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Theme.Accent,
	BackgroundTransparency = 0.92,
	ZIndex = 0,
	Visible = false,
}, ScreenGui)
corner(WindowGlow, 24)

local WindowShadow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	ZIndex = 0,
	Visible = false,
}, ScreenGui)
corner(WindowShadow, 14)

local Main = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = targetSize,
	BackgroundColor3 = Theme.Background,
	Visible = false,
	Active = true,
	ZIndex = 1,
}, ScreenGui)
corner(Main, 12)
create("UIStroke", { Color = Theme.Stroke, Transparency = 0.2 }, Main)

-- Ecran de "chargement" joue a chaque ouverture : masque le contenu derriere
-- un voile + 3 points qui pulsent en cascade, puis se dissout pour reveler le
-- menu (deja construit en dessous). Purement cosmetique, ~0.5s.
local LoadingOverlay = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Theme.Background,
	BackgroundTransparency = 0,
	ZIndex = 20,
	Visible = false,
	Active = true, -- bloque les clics vers ce qu'il masque pendant l'animation
}, Main)
corner(LoadingOverlay, 12)

create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.5, -8),
	Size = UDim2.new(0, 200, 0, 24),
	BackgroundTransparency = 1,
	Text = "Von Client",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Theme.Text,
	ZIndex = 21,
}, LoadingOverlay)

local LoadingDots = {}
for i = 1, 3 do
	local dot = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, (i - 2) * 16, 0.5, 14),
		Size = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.7,
		ZIndex = 21,
	}, LoadingOverlay)
	corner(dot, 4)
	table.insert(LoadingDots, dot)
end

local loadingTweens = {}
local function playLoadingIntro()
	for _, t in ipairs(loadingTweens) do t:Cancel() end
	table.clear(loadingTweens)

	LoadingOverlay.Visible = true
	LoadingOverlay.BackgroundTransparency = 0
	for _, dot in ipairs(LoadingDots) do
		dot.BackgroundTransparency = 0.7
		dot.Size = UDim2.new(0, 8, 0, 8)
	end

	for i, dot in ipairs(LoadingDots) do
		local dotTween = TweenService:Create(
			dot,
			TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (i - 1) * 0.15),
			{ BackgroundTransparency = 0, Size = UDim2.new(0, 10, 0, 10) }
		)
		dotTween:Play()
		table.insert(loadingTweens, dotTween)
	end

	task.delay(0.55, function()
		for _, t in ipairs(loadingTweens) do t:Cancel() end
		table.clear(loadingTweens)
		tween(LoadingOverlay, { BackgroundTransparency = 1 }, 0.2)
		task.delay(0.2, function()
			if not Main.Visible then return end -- ferme entre temps : rien a reveler
			LoadingOverlay.Visible = false
		end)
	end)
end

local function syncWindowHalo()
	local pos, size = Main.Position, Main.Size
	WindowGlow.Position = pos
	WindowGlow.Size = UDim2.new(0, size.X.Offset + 50, 0, size.Y.Offset + 50)
	WindowShadow.Position = pos
	WindowShadow.Size = UDim2.new(0, size.X.Offset + 16, 0, size.Y.Offset + 16)
end
syncWindowHalo()
Main:GetPropertyChangedSignal("Position"):Connect(syncWindowHalo)
Main:GetPropertyChangedSignal("Size"):Connect(syncWindowHalo)

-- Animation d'ouverture/fermeture "pro" : leger zoom (96% -> 100%, aucun
-- rebond) + fondu du halo, plutot que l'ancien pop depuis une taille nulle.
local WINDOW_GLOW_TRANSPARENCY = 0.92
local WINDOW_SHADOW_TRANSPARENCY = 0.45
local WINDOW_OPEN_SCALE = 0.96

local function scaledSize(size, factor)
	return UDim2.new(0, size.X.Offset * factor, 0, size.Y.Offset * factor)
end

local function openWindow()
	Main.Visible = true
	WindowGlow.Visible = true
	WindowShadow.Visible = true
	WindowGlow.BackgroundTransparency = 1
	WindowShadow.BackgroundTransparency = 1
	Main.Size = scaledSize(targetSize, WINDOW_OPEN_SCALE)

	tweenStyled(Main, { Size = targetSize }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	tween(WindowGlow, { BackgroundTransparency = WINDOW_GLOW_TRANSPARENCY }, 0.28)
	tween(WindowShadow, { BackgroundTransparency = WINDOW_SHADOW_TRANSPARENCY }, 0.28)
	playLoadingIntro()
end

local function closeWindow()
	local closeTween = TweenService:Create(
		Main,
		TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Size = scaledSize(targetSize, WINDOW_OPEN_SCALE) }
	)
	tween(WindowGlow, { BackgroundTransparency = 1 }, 0.14)
	tween(WindowShadow, { BackgroundTransparency = 1 }, 0.14)
	closeTween.Completed:Connect(function()
		Main.Visible = false
		WindowGlow.Visible = false
		WindowShadow.Visible = false
		LoadingOverlay.Visible = false
		Main.Size = targetSize -- pret pour la prochaine ouverture
	end)
	closeTween:Play()
end

local function toggleWindow()
	if Main.Visible then closeWindow() else openWindow() end
end

--------------------------------------------------------------------------------
-- Splash d'injection : jouee UNE SEULE fois au chargement du script (pas a
-- chaque ouverture du menu) - vraie barre de progression qui se remplit sur
-- ~1.1s, plutot que les points de playLoadingIntro (reserves aux ouvertures
-- manuelles). A la fin, la fenetre se referme : le menu reste cache par
-- defaut comme avant, la splash sert juste a confirmer le chargement.
--------------------------------------------------------------------------------

local InjectionOverlay = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Theme.Background,
	ZIndex = 25,
	Visible = false,
	Active = true,
}, Main)
corner(InjectionOverlay, 12)

local InjectionLogo = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -46),
	Size = UDim2.new(0, 64, 0, 64),
	BackgroundColor3 = Theme.Accent,
	ZIndex = 26,
}, InjectionOverlay)
corner(InjectionLogo, 18)
gradient(InjectionLogo, ColorSequence.new(Theme.Accent, Theme.AccentDim), 45)
create("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "V",
	Font = Enum.Font.GothamBold,
	TextSize = 34,
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 27,
}, InjectionLogo)

create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 8),
	Size = UDim2.new(0, 240, 0, 26),
	BackgroundTransparency = 1,
	Text = "Von Client",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Theme.Text,
	ZIndex = 26,
}, InjectionOverlay)

local ProgressBarBack = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 42),
	Size = UDim2.new(0, 220, 0, 6),
	BackgroundColor3 = Theme.Element,
	ZIndex = 26,
}, InjectionOverlay)
corner(ProgressBarBack, 3)

local ProgressBarFill = create("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Theme.Accent,
	ZIndex = 27,
}, ProgressBarBack)
corner(ProgressBarFill, 3)
gradient(ProgressBarFill, ColorSequence.new(Theme.Accent, Theme.AccentDim), 0)

local ProgressLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 64),
	Size = UDim2.new(0, 220, 0, 16),
	BackgroundTransparency = 1,
	Text = "Chargement... 0%",
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = Theme.SubText,
	ZIndex = 26,
}, InjectionOverlay)

local function playInjectionSplash()
	InjectionOverlay.Visible = true
	InjectionOverlay.BackgroundTransparency = 0
	ProgressBarFill.Size = UDim2.new(0, 0, 1, 0)
	ProgressLabel.Text = "Chargement... 0%"

	Main.Visible = true
	WindowGlow.Visible = true
	WindowShadow.Visible = true
	WindowGlow.BackgroundTransparency = 1
	WindowShadow.BackgroundTransparency = 1
	Main.Size = scaledSize(targetSize, WINDOW_OPEN_SCALE)
	tweenStyled(Main, { Size = targetSize }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	tween(WindowGlow, { BackgroundTransparency = WINDOW_GLOW_TRANSPARENCY }, 0.28)
	tween(WindowShadow, { BackgroundTransparency = WINDOW_SHADOW_TRANSPARENCY }, 0.28)

	local DURATION = 1.1
	local startTime = os.clock()
	task.spawn(function()
		while true do
			local pct = math.clamp((os.clock() - startTime) / DURATION, 0, 1)
			ProgressBarFill.Size = UDim2.new(pct, 0, 1, 0)
			ProgressLabel.Text = string.format("Chargement... %d%%", math.floor(pct * 100))
			if pct >= 1 then break end
			task.wait()
		end
	end)

	task.delay(DURATION + 0.15, function()
		tween(InjectionOverlay, { BackgroundTransparency = 1 }, 0.25)
		task.delay(0.25, function()
			InjectionOverlay.Visible = false
			-- Le menu reste ouvert apres la splash (pas de closeWindow() ici).
		end)
	end)
end

-- Pas de fond visible : juste un Frame transparent qui sert de zone de drag
-- et de conteneur pour le logo/titre/bouton fermer, poses directement sur le
-- fond de Main (plus de "barre noire" separee).
local TopBar = create("Frame", { Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT), BackgroundTransparency = 1 }, Main)

-- Logo : monogramme "V" en attendant un vrai logo (remplace juste ce Frame
-- par une ImageLabel avec Image = "rbxassetid://..." le jour ou tu en as un).
local LOGO_SIZE = 56
local Logo = create("Frame", {
	Position = UDim2.new(0, 14, 0, (TOPBAR_HEIGHT - LOGO_SIZE) / 2),
	Size = UDim2.new(0, LOGO_SIZE, 0, LOGO_SIZE),
	BackgroundColor3 = Theme.Accent,
}, TopBar)
corner(Logo, 15)
gradient(Logo, ColorSequence.new(Theme.Accent, Theme.AccentDim), 45)
create("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.85, Thickness = 1 }, Logo)
create("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "V",
	Font = Enum.Font.GothamBold,
	TextSize = 30,
	TextColor3 = Color3.new(1, 1, 1),
}, Logo)

local titleLeft = 14 + LOGO_SIZE + 12
local titleWidth = 1 -- Scale ; l'offset negatif ci-dessous laisse la place au bouton fermer
local TITLE_HEIGHT, SUBTITLE_HEIGHT, TITLE_GAP = 28, 18, 4
local titleTop = (TOPBAR_HEIGHT - (TITLE_HEIGHT + TITLE_GAP + SUBTITLE_HEIGHT)) / 2

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, titleLeft, 0, titleTop),
	Size = UDim2.new(titleWidth, -(titleLeft + 54), 0, TITLE_HEIGHT),
	Text = "Von Client",
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	TextColor3 = Theme.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TopBar)

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, titleLeft, 0, titleTop + TITLE_HEIGHT + TITLE_GAP),
	Size = UDim2.new(titleWidth, -(titleLeft + 54), 0, SUBTITLE_HEIGHT),
	Text = "Menu de controle",
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	TextColor3 = Theme.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TopBar)

local CloseButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.new(0, 38, 0, 38),
	BackgroundColor3 = Theme.Element,
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Theme.Text,
	AutoButtonColor = false,
}, TopBar)
corner(CloseButton, 10)
CloseButton.MouseButton1Click:Connect(closeWindow)
CloseButton.MouseEnter:Connect(function() tween(CloseButton, { BackgroundColor3 = Theme.Danger }, 0.1) end)
CloseButton.MouseLeave:Connect(function() tween(CloseButton, { BackgroundColor3 = Theme.Element }, 0.1) end)

-- Drag de la fenetre (via la barre de titre)
do
	local dragging, dragStart, startPos
	TopBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = Main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- Redimensionnement (poignee en bas a droite), clampe entre les tailles min/max,
-- sauvegarde dans Settings pour retrouver la meme taille au prochain chargement.
local ResizeHandle = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -3, 1, -3),
	Size = UDim2.new(0, 14, 0, 14),
	BackgroundColor3 = Theme.Stroke,
	BackgroundTransparency = 0.4,
	Active = true,
	ZIndex = 10, -- cree avant Sidebar/PagesHolder : sans ca, ces derniers (meme ZIndex par defaut) le recouvriraient
}, Main)
corner(ResizeHandle, 3)
ResizeHandle.MouseEnter:Connect(function() tween(ResizeHandle, { BackgroundTransparency = 0 }, 0.1) end)
ResizeHandle.MouseLeave:Connect(function() tween(ResizeHandle, { BackgroundTransparency = 0.4 }, 0.1) end)

do
	local resizing, resizeStart, startSize
	ResizeHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeStart = input.Position
			startSize = Main.Size
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
					savePrefs()
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - resizeStart
			local newWidth = math.clamp(startSize.X.Offset + delta.X, WINDOW_MIN_WIDTH, WINDOW_MAX_WIDTH)
			local newHeight = math.clamp(startSize.Y.Offset + delta.Y, WINDOW_MIN_HEIGHT, WINDOW_MAX_HEIGHT)
			targetSize = UDim2.new(0, newWidth, 0, newHeight)
			Main.Size = targetSize
			Prefs.WindowWidth = newWidth
			Prefs.WindowHeight = newHeight
		end
	end)
end

local SIDEBAR_WIDTH = 150

local Sidebar = create("Frame", {
	Position = UDim2.new(0, 0, 0, TOPBAR_HEIGHT),
	Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -TOPBAR_HEIGHT),
	BackgroundColor3 = Theme.Panel,
}, Main)
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, Sidebar)
create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, Sidebar)

local PagesHolder = create("Frame", {
	Position = UDim2.new(0, SIDEBAR_WIDTH, 0, TOPBAR_HEIGHT),
	Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, -TOPBAR_HEIGHT),
	BackgroundTransparency = 1,
}, Main)

local pages, sidebarButtons, currentPage = {}, {}, nil

local function selectPage(name)
	if currentPage then
		local prev = sidebarButtons[currentPage]
		prev.Button.BackgroundColor3 = Theme.Element
		prev.Label.TextColor3 = Theme.SubText
		pages[currentPage].Visible = false
	end

	local current = sidebarButtons[name]
	pages[name].Visible = true
	current.Button.BackgroundColor3 = Theme.ElementHover
	current.Label.TextColor3 = current.AccentColor
	currentPage = name
end

-- Chaque categorie a sa propre barre d'accent (pas juste celle qui est
-- selectionnee) : plus besoin d'un indicateur qui glisse dans un calque a
-- part, donc plus de risque de conflit avec le UIListLayout de Sidebar.
local function createCategory(name, accentColor)
	local Button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Theme.Element,
		Text = "",
		AutoButtonColor = false,
	}, Sidebar)
	corner(Button, 8)

	local AccentBar = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.new(0, 4, 1, -16),
		BackgroundColor3 = accentColor or Theme.Accent,
	}, Button)
	corner(AccentBar, 2)

	local Label = create("TextLabel", {
		Position = UDim2.new(0, 20, 0, 0),
		Size = UDim2.new(1, -26, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Button)

	Button.MouseButton1Click:Connect(function() selectPage(name) end)
	Button.MouseEnter:Connect(function()
		if currentPage ~= name then tween(Button, { BackgroundColor3 = Theme.Stroke }, 0.1) end
	end)
	Button.MouseLeave:Connect(function()
		if currentPage ~= name then tween(Button, { BackgroundColor3 = Theme.Element }, 0.1) end
	end)

	local Page = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Accent,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, PagesHolder)
	create("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, Page)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
	}, Page)

	pages[name] = Page
	sidebarButtons[name] = { Button = Button, Label = Label, AccentColor = accentColor or Theme.Accent }
	return Page
end

-- Card avec liseré d'accent plein-hauteur a gauche (façon callout/alert box
-- moderne) et titre a l'interieur, a droite du lisere. ClipsDescendants fait
-- epouser le lisere au coin arrondi de la card au lieu de deborder en carre.
local function addSection(page, title)
	local Card = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		ClipsDescendants = true,
	}, page)
	corner(Card, 12)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.15 }, Card)

	-- Meme style que l'indicateur de la sidebar (barre fine et pleine, sans degrade).
	local AccentBar = create("Frame", {
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, 3, 1, -12),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, Card)
	corner(AccentBar, 2)

	create("TextLabel", {
		Position = UDim2.new(0, 20, 0, 14),
		Size = UDim2.new(1, -36, 0, 22),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Card)

	local Content = create("Frame", {
		Position = UDim2.new(0, 20, 0, 44),
		Size = UDim2.new(1, -36, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, Card)
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, Content)
	create("UIPadding", { PaddingBottom = UDim.new(0, 18) }, Content)

	return Content
end

local function addToggleRow(content, text, default, onChange)
	local state = default or false

	local Row = create("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -66, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Row)

	local ON_POSITION, OFF_POSITION = UDim2.new(1, -25, 0.5, -11), UDim2.new(0, 3, 0.5, -11)

	local Switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 52, 0, 28),
		BackgroundColor3 = state and Theme.Accent or Theme.Element,
	}, Row)
	corner(Switch, 14)
	-- Fin liseré accent qui s'estompe quand le switch est off, s'illumine quand on.
	local switchGlow = create("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Transparency = state and 0.5 or 1 }, Switch)

	local Knob = create("Frame", {
		Size = UDim2.new(0, 22, 0, 22),
		Position = state and ON_POSITION or OFF_POSITION,
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, Switch)
	corner(Knob, 11)

	local Click = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "" }, Switch)

	local function set(newState)
		state = newState
		tween(Switch, { BackgroundColor3 = state and Theme.Accent or Theme.Element }, 0.15)
		tween(switchGlow, { Transparency = state and 0.5 or 1 }, 0.15)
		tweenStyled(Knob, { Position = state and ON_POSITION or OFF_POSITION }, 0.2)
		if onChange then onChange(state) end
	end
	Click.MouseButton1Click:Connect(function() set(not state) end)

	return { Set = set, Get = function() return state end }
end

local function addDropdownRow(content, text, options, default, onChange)
	local selected = default or options[1]
	local HEADER_HEIGHT, SEARCH_HEIGHT, OPTION_HEIGHT = 40, 36, 34

	local Holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		BackgroundColor3 = Theme.Element,
		ClipsDescendants = true,
	}, content)
	corner(Holder, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Holder)

	local MainButton = create("TextButton", {
		Size = UDim2.new(1, -30, 0, HEADER_HEIGHT),
		BackgroundTransparency = 1,
		Text = text .. ": " .. tostring(selected),
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
	}, Holder)

	local Chevron = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundTransparency = 1,
		Text = "▾",
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.SubText,
	}, Holder)

	-- Barre de recherche : fond Panel (plus sombre que le Holder en Element,
	-- effet "en creux") pour bien la distinguer. Filtre les options en direct.
	local SearchBox = create("TextBox", {
		Position = UDim2.new(0, 8, 0, HEADER_HEIGHT + 4),
		Size = UDim2.new(1, -16, 0, SEARCH_HEIGHT - 8),
		BackgroundColor3 = Theme.Panel,
		Text = "",
		PlaceholderText = "Rechercher...",
		PlaceholderColor3 = Theme.SubText,
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		ClearTextOnFocus = false,
	}, Holder)
	corner(SearchBox, 6)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.3 }, SearchBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, SearchBox)

	local List = create("Frame", {
		Position = UDim2.new(0, 0, 0, HEADER_HEIGHT + SEARCH_HEIGHT),
		Size = UDim2.new(1, 0, 0, #options * OPTION_HEIGHT),
		BackgroundTransparency = 1,
	}, Holder)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, List)

	local optionButtons = {}
	local open = false

	local function visibleOptionCount()
		local count = 0
		for _, btn in ipairs(optionButtons) do
			if btn.Visible then count = count + 1 end
		end
		return count
	end

	local function resizeOpen()
		tween(Holder, { Size = UDim2.new(1, 0, 0, HEADER_HEIGHT + SEARCH_HEIGHT + visibleOptionCount() * OPTION_HEIGHT) }, 0.12)
	end

	local function applyFilter()
		local query = SearchBox.Text:lower()
		for _, btn in ipairs(optionButtons) do
			btn.Visible = query == "" or btn.Text:lower():find(query, 1, true) ~= nil
		end
		if open then resizeOpen() end
	end

	local function close()
		open = false
		tween(Holder, { Size = UDim2.new(1, 0, 0, HEADER_HEIGHT) })
		tween(Chevron, { Rotation = 0 }, 0.15)
		SearchBox.Text = ""
		applyFilter()
	end

	for _, option in ipairs(options) do
		local OptButton = create("TextButton", {
			Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
			BackgroundColor3 = Theme.Stroke,
			BackgroundTransparency = 1,
			Text = tostring(option),
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextColor3 = Theme.SubText,
		}, List)
		table.insert(optionButtons, OptButton)
		OptButton.MouseEnter:Connect(function() tween(OptButton, { BackgroundTransparency = 0.4 }, 0.1) end)
		OptButton.MouseLeave:Connect(function() tween(OptButton, { BackgroundTransparency = 1 }, 0.1) end)
		OptButton.MouseButton1Click:Connect(function()
			selected = option
			MainButton.Text = text .. ": " .. tostring(selected)
			close()
			if onChange then onChange(selected) end
		end)
	end

	SearchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)

	MainButton.MouseEnter:Connect(function() tween(Holder, { BackgroundColor3 = Theme.Stroke }, 0.1) end)
	MainButton.MouseLeave:Connect(function() tween(Holder, { BackgroundColor3 = Theme.Element }, 0.1) end)

	MainButton.MouseButton1Click:Connect(function()
		open = not open
		if open then
			tween(Chevron, { Rotation = 180 }, 0.15)
			resizeOpen()
		else
			close()
		end
	end)

	-- Met a jour la valeur affichee sans passer par un clic (utilise par le
	-- chargement de config) ; declenche quand meme onChange pour appliquer l'effet.
	local function set(newValue)
		selected = newValue
		MainButton.Text = text .. ": " .. tostring(selected)
		if onChange then onChange(selected) end
	end

	return { Get = function() return selected end, Set = set, Instance = Holder }
end

local function addSliderRow(content, text, min, max, default, step, onChange)
	step = step or 1
	local value = default or min

	local Holder = create("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -70, 0, 22),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Holder)

	local decimals = step < 1 and math.max(0, -math.floor(math.log10(step) + 0.0001)) or 0
	local function formatValue(v)
		if v <= 0 and min <= 0 then return "Illimite" end
		return string.format("%." .. decimals .. "f", v)
	end

	local ValueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 80, 0, 22),
		BackgroundTransparency = 1,
		Text = formatValue(value),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, Holder)

	local Bar = create("Frame", {
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Theme.Element,
	}, Holder)
	corner(Bar, 4)

	local function pctFor(v) return (v - min) / (max - min) end

	local Fill = create("Frame", { Size = UDim2.new(pctFor(value), 0, 1, 0), BackgroundColor3 = Theme.Accent }, Bar)
	corner(Fill, 4)
	gradient(Fill, ColorSequence.new(Theme.Accent, Theme.AccentDim), 0)

	-- Curseur rond par-dessus la barre fine : plus lisible/tactile qu'un simple
	-- remplissage, et grossit legerement au survol/drag pour le feedback.
	local Knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(pctFor(value), 0, 0.5, 0),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
	}, Bar)
	corner(Knob, 8)
	create("UIStroke", { Color = Theme.Accent, Thickness = 2 }, Knob)

	local dragging = false

	local function apply(x)
		local p = math.clamp((x - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
		local raw = min + (max - min) * p
		value = math.clamp(math.floor(raw / step + 0.5) * step, min, max)
		local pct = pctFor(value)
		Fill.Size = UDim2.new(pct, 0, 1, 0)
		Knob.Position = UDim2.new(pct, 0, 0.5, 0)
		ValueLabel.Text = formatValue(value)
		if onChange then onChange(value) end
	end

	local function setKnobHover(hovering)
		tweenStyled(Knob, { Size = hovering and UDim2.new(0, 20, 0, 20) or UDim2.new(0, 16, 0, 16) }, 0.15)
	end
	Bar.MouseEnter:Connect(function() setKnobHover(true) end)
	Bar.MouseLeave:Connect(function() if not dragging then setKnobHover(false) end end)

	Bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setKnobHover(true)
			apply(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			setKnobHover(false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			apply(input.Position.X)
		end
	end)

	-- Met a jour la valeur directement (utilise par le chargement de config),
	-- sans passer par une position en pixels ; declenche quand meme onChange.
	local function set(newValue)
		value = math.clamp(newValue, min, max)
		local pct = pctFor(value)
		Fill.Size = UDim2.new(pct, 0, 1, 0)
		Knob.Position = UDim2.new(pct, 0, 0.5, 0)
		ValueLabel.Text = formatValue(value)
		if onChange then onChange(value) end
	end

	return { Get = function() return value end, Set = set }
end

local function addLabelRow(content, text)
	return create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, content)
end

-- Bouton de rebind : au clic, ecoute la prochaine touche clavier pressee et
-- l'assigne. Coupe le toggle du menu (capturingKeybind) pendant la capture
-- pour eviter qu'une touche pressee pour le rebind ne ferme/ouvre le menu en
-- meme temps. Echap annule sans changer.
local function addKeybindRow(content, text, currentKey, onChange)
	local capturing = false

	local Row = create("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -122, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Row)

	local KeyButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 112, 0, 32),
		BackgroundColor3 = Theme.Element,
		Text = currentKey.Name,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Theme.Accent,
		AutoButtonColor = false,
	}, Row)
	corner(KeyButton, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, KeyButton)

	KeyButton.MouseEnter:Connect(function()
		if not capturing then tween(KeyButton, { BackgroundColor3 = Theme.Stroke }, 0.1) end
	end)
	KeyButton.MouseLeave:Connect(function()
		if not capturing then tween(KeyButton, { BackgroundColor3 = Theme.Element }, 0.1) end
	end)

	KeyButton.MouseButton1Click:Connect(function()
		if capturing then return end
		capturing = true
		capturingKeybind = true
		KeyButton.Text = "..."
		tween(KeyButton, { BackgroundColor3 = Theme.Accent, TextColor3 = Color3.new(1, 1, 1) }, 0.1)

		local connection
		connection = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

			connection:Disconnect()
			capturing = false
			capturingKeybind = false
			tween(KeyButton, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.Accent }, 0.1)

			if input.KeyCode == Enum.KeyCode.Escape then
				KeyButton.Text = currentKey.Name
				return
			end

			currentKey = input.KeyCode
			KeyButton.Text = currentKey.Name
			if onChange then onChange(currentKey) end
		end)
	end)

	return { Get = function() return currentKey end }
end

local function addButtonRow(content, text, onClick)
	local Button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Theme.Element,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
	}, content)
	corner(Button, 10)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Button)
	local buttonScale = create("UIScale", { Scale = 1 }, Button) -- petit effet d'appui (scale), independant du pivot du bouton

	local hovering = false
	Button.MouseEnter:Connect(function()
		hovering = true
		tween(Button, { BackgroundColor3 = Theme.Stroke }, 0.1)
	end)
	Button.MouseLeave:Connect(function()
		hovering = false
		tween(Button, { BackgroundColor3 = Theme.Element }, 0.1)
	end)

	Button.MouseButton1Click:Connect(function()
		tween(Button, { BackgroundColor3 = Theme.Accent }, 0.1)
		tween(buttonScale, { Scale = 0.96 }, 0.08)
		task.delay(0.08, function()
			tween(buttonScale, { Scale = 1 }, 0.12)
		end)
		task.delay(0.1, function()
			tween(Button, { BackgroundColor3 = hovering and Theme.Stroke or Theme.Element }, 0.15)
		end)
		if onClick then onClick() end
	end)

	return Button
end

-- Selecteur (dropdown) + bouton "Teleporter" en dessous, dont les options
-- peuvent changer en cours de partie (rebuild complet du dropdown a chaque
-- refresh -- plus simple que d'etendre addDropdownRow pour un changement
-- d'options a chaud). `getOptions` renvoie la liste de noms courante,
-- `onTeleport(name)` est appele au clic sur le bouton.
--
-- Le dropdown est pose directement dans `section` (comme Chakra Point), PAS
-- dans un Frame intermediaire a AutomaticSize : une chaine AutomaticSize sur
-- 3 niveaux (Card > wrapper > dropdown tweene) propage mal le redimensionnement
-- pendant l'animation d'ouverture, ce qui laissait la card a une taille figee
-- (grande par defaut, ne grossissait pas a l'ouverture). LayoutOrder fixe
-- l'ordre visuel puisque le dropdown est detruit/recree a chaque refresh.
local function addTeleportSelector(section, label, buttonText, getOptions, onTeleport)
	local currentRow = nil
	local selected = nil

	local function rebuild()
		if currentRow then
			currentRow:Destroy()
			currentRow = nil
		end

		local options = getOptions()
		if #options == 0 then
			selected = nil
			currentRow = addLabelRow(section, "Aucune cible disponible pour l'instant.")
		else
			if not selected or not table.find(options, selected) then
				selected = options[1]
			end
			currentRow = addDropdownRow(section, label, options, selected, function(v)
				selected = v
			end).Instance
		end
		currentRow.LayoutOrder = 1
	end

	rebuild()

	local teleportButton = addButtonRow(section, buttonText, function()
		if not selected then
			notify("Aucune cible selectionnee.")
			return
		end
		onTeleport(selected)
	end)
	teleportButton.LayoutOrder = 2

	return { Refresh = rebuild }
end

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

local VisualsPage = createCategory("Visuels", Theme.Accent)
local PlayerPage = createCategory("Joueur", Color3.fromRGB(196, 120, 255))
local AutoPage = createCategory("Auto", Color3.fromRGB(255, 175, 70))
local SkinPage = createCategory("Skin", Color3.fromRGB(255, 120, 170))
local SettingsPage = createCategory("Settings", Theme.Success)

--------------------------------------------------------------------------------
------------------------------- VISUALS ----------------------------------------
--------------------------------------------------------------------------------

-- Tout ce bloc est dans un do...end et ecrit directement dans FEATURE_CONTROLS
-- (au lieu de ~18 variables locales separees) : Luau limite une fonction (et
-- le script entier EST une seule fonction) a 200 registres locaux, et on l'a
-- depasse. Les locals ici sont liberes a la fin du bloc ; seule
-- applyFeatureSettings (predeclaree juste en dessous) survit.
local applyFeatureSettings
do
	local FEATURE_CONTROLS = {}

	-- Reglages ESP : active/désactive, mode (Lua ou Python), distance max, affichage PV et distance.
	local EspSection = addSection(VisualsPage, "ESP")

	FEATURE_CONTROLS.EspEnabled = addToggleRow(EspSection, "ESP Actif", enabled, function(state)
		setEnabled(state)
		if not state then pushOverlayDisabled() end
		Settings.EspEnabled = state
	end)

	FEATURE_CONTROLS.EspMode = addDropdownRow(EspSection, "Mode ESP", { "Lua", "Python" }, EspMode, function(mode)
		local wasPython = enabled and EspMode == "Python"
		EspMode = mode
		setEnabled(enabled) -- reapplique la visibilite des billboards selon le nouveau mode
		if wasPython and mode ~= "Python" then pushOverlayDisabled() end
		Settings.EspMode = mode
	end)

	FEATURE_CONTROLS.EspMaxDistance = addSliderRow(EspSection, "Distance Max", 0, 10000, EspMaxDistance, 1, function(v)
		EspMaxDistance = v
		Settings.EspMaxDistance = v
	end)

	FEATURE_CONTROLS.ShowHealth = addToggleRow(EspSection, "Afficher PV", ShowHealth, function(state)
		ShowHealth = state
		refreshAllPlayerLabels()
		Settings.ShowHealth = state
	end)

	FEATURE_CONTROLS.ShowDistance = addToggleRow(EspSection, "Afficher Distance", ShowDistance, function(state)
		ShowDistance = state
		refreshAllPlayerLabels()
		Settings.ShowDistance = state
	end)

	FEATURE_CONTROLS.ShowChakra = addToggleRow(EspSection, "Afficher Chakra", ShowChakra, function(state)
		ShowChakra = state
		refreshAllPlayerLabels()
		Settings.ShowChakra = state
	end)

	FEATURE_CONTROLS.ShowBlood = addToggleRow(EspSection, "Afficher Blood", ShowBlood, function(state)
		ShowBlood = state
		refreshAllPlayerLabels()
		Settings.ShowBlood = state
	end)

	local EnvSection = addSection(VisualsPage, "Environnement")

	FEATURE_CONTROLS.NoFogEnabled = addToggleRow(EnvSection, "No Fog", NoFogEnabled, function(state)
		setNoFog(state)
		Settings.NoFogEnabled = state
	end)
	FEATURE_CONTROLS.NoRainEnabled = addToggleRow(EnvSection, "No Rain", NoRainEnabled, function(state)
		setNoRain(state)
		Settings.NoRainEnabled = state
	end)
	FEATURE_CONTROLS.FullBrightEnabled = addToggleRow(EnvSection, "Full Bright", FullBrightEnabled, function(state)
		setFullBright(state)
		Settings.FullBrightEnabled = state
	end)

	FEATURE_CONTROLS.BrightnessLevel = addSliderRow(EnvSection, "Brightness Level", 1, 10, BrightnessLevel, 0.1, function(v)
		BrightnessLevel = v
		Settings.BrightnessLevel = v
	end)

	FEATURE_CONTROLS.TimeOfDay = addDropdownRow(EnvSection, "Heure", { "Morning", "Afternoon", "Evening", "Night" }, TimeOfDay, function(v)
		TimeOfDay = v
		Settings.TimeOfDay = v
	end)

	FEATURE_CONTROLS.TimeChangerEnabled = addToggleRow(EnvSection, "Time Changer", TimeChangerEnabled, function(state)
		setTimeChanger(state)
		Settings.TimeChangerEnabled = state
	end)

	--------------------------------------------------------------------------------
	------------------------------- PLAYER -----------------------------------------
	--------------------------------------------------------------------------------

	local NotifSection = addSection(PlayerPage, "Notifications")

	FEATURE_CONTROLS.ChakraSenseNotifier = addToggleRow(NotifSection, "Chakra Sense Notifier", ChakraSenseNotifier, function(state)
		ChakraSenseNotifier = state
		Settings.ChakraSenseNotifier = state
	end)

	local MovementSection = addSection(PlayerPage, "Mouvement")

	FEATURE_CONTROLS.NoclipEnabled = addToggleRow(MovementSection, "Noclip", NoclipEnabled, function(state)
		setNoclip(state)
		Settings.NoclipEnabled = state
	end)

	FEATURE_CONTROLS.FlyEnabled = addToggleRow(MovementSection, "Fly", FlyEnabled, function(state)
		setFly(state)
		Settings.FlyEnabled = state
	end)

	FEATURE_CONTROLS.FlySpeed = addSliderRow(MovementSection, "Fly Speed", 10, 500, FlySpeed, 10, function(v)
		FlySpeed = v
		Settings.FlySpeed = v
	end)

	addLabelRow(MovementSection, "Fly : ZQSD/WASD pour se deplacer, Espace pour monter, Ctrl pour descendre.")

	local TeleportPlayerSection = addSection(PlayerPage, "Teleport Joueur")
	local playerTeleportSelector = addTeleportSelector(TeleportPlayerSection, "Joueur", "Teleporter au joueur",
		function()
			local names = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer then
					table.insert(names, player.Name)
				end
			end
			table.sort(names)
			return names
		end,
		function(name)
			local target = Players:FindFirstChild(name)
			if not target then
				notify("Joueur introuvable.")
				return
			end
			teleportToPlayer(target)
		end
	)
	track(Players.PlayerAdded:Connect(playerTeleportSelector.Refresh))
	track(Players.PlayerRemoving:Connect(function()
		task.wait() -- laisse le joueur sortir de Players:GetPlayers() avant de rafraichir
		playerTeleportSelector.Refresh()
	end))

	local TeleportNpcSection = addSection(PlayerPage, "Teleport PNJ")
	local npcTeleportSelector = addTeleportSelector(TeleportNpcSection, "PNJ", "Teleporter au PNJ",
		function()
			local names = {}
			for name in pairs(NpcsByName) do
				table.insert(names, name)
			end
			table.sort(names)
			return names
		end,
		teleportToNpc
	)
	onNpcListChanged = npcTeleportSelector.Refresh

	local SafeSpotSection = addSection(PlayerPage, "Safe Spot")
	addButtonRow(SafeSpotSection, "Definir Safe Spot", setSafeSpot)
	addButtonRow(SafeSpotSection, "Teleporter au Safe Spot", teleportToSafeSpot)

	local ChakraPointsSection = addSection(PlayerPage, "Chakra Points")
	if #ChakraPointNames > 0 then
		FEATURE_CONTROLS.SelectedChakraPoint = addDropdownRow(ChakraPointsSection, "Chakra Point", ChakraPointNames, SelectedChakraPoint, function(v)
			SelectedChakraPoint = v
			Settings.SelectedChakraPoint = v
		end)
		addButtonRow(ChakraPointsSection, "Teleporter", teleportToChakraPoint)
	else
		addLabelRow(ChakraPointsSection, "Aucun ChakraPoints trouve dans workspace.")
	end

	local InventorySection = addSection(PlayerPage, "Inventaire")
	addLabelRow(InventorySection, "Envoie Inventaire (Loadout) + Hotbar + Lifeforce au webhook Discord. Auto toutes les 5 min. Astuce : ouvre ton inventaire en jeu une fois pour que les slots se remplissent.")
	addButtonRow(InventorySection, "Envoyer au webhook Discord", sendInventoryToWebhook)

	local AfkAgeUpSection = addSection(AutoPage, "AFK AgeUp")
	addLabelRow(AfkAgeUpSection, "Teleporte automatiquement vers une Safe Place des qu'un joueur passe a moins de 300 metres (cooldown 1s entre deux teleportations).")
	FEATURE_CONTROLS.AfkAgeUpEnabled = addToggleRow(AfkAgeUpSection, "AFK AgeUp", Settings.AfkAgeUpEnabled, function(state)
		setAfkAgeUp(state)
		Settings.AfkAgeUpEnabled = state
	end)

	local PanicTeleportSection = addSection(AutoPage, "Panic Teleport")
	addLabelRow(PanicTeleportSection, "Des que tes PV passent sous 50, teleportation toutes les 0.1s entre les Safe Places. S'arrete quand tes PV repassent au-dessus de 100.")
	FEATURE_CONTROLS.PanicTeleportEnabled = addToggleRow(PanicTeleportSection, "Panic Teleport", Settings.PanicTeleportEnabled, function(state)
		setPanicTeleport(state)
		Settings.PanicTeleportEnabled = state
	end)

	-- Pousse une config chargee vers l'UI (declenche l'onChange normal de
	-- chaque controle, qui applique l'effet reel) sans dupliquer la logique.
	applyFeatureSettings = function(data)
		data = data or {}
		for key, control in pairs(FEATURE_CONTROLS) do
			if control then
				local value = data[key]
				if value == nil then value = DEFAULT_FEATURES[key] end
				if value ~= nil then control.Set(value) end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Configs : profils de reglages "cheat" nommes, sauvegardes dans
-- von_client/configs/*.json. Rien n'est charge par defaut sauf si une config
-- est marquee comme telle (etoile).
--------------------------------------------------------------------------------

local function addConfigRow(container, name, isDefault, onLoad, onSetDefault, onDelete)
	local Row = create("Frame", { Size = UDim2.new(1, 0, 0, 78), BackgroundColor3 = Theme.Element }, container)
	corner(Row, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Row)

	create("TextLabel", {
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 20),
		BackgroundTransparency = 1,
		Text = isDefault and (name .. "  \226\152\133 par defaut") or name,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = isDefault and Theme.Accent or Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Row)

	local ButtonsHolder = create("Frame", {
		Position = UDim2.new(0, 12, 0, 34),
		Size = UDim2.new(1, -24, 0, 32),
		BackgroundTransparency = 1,
	}, Row)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, ButtonsHolder)

	local function miniButton(text, color)
		local Btn = create("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = color or Theme.Stroke,
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
		}, ButtonsHolder)
		corner(Btn, 6)
		create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, Btn)
		return Btn
	end

	miniButton("Charger", Theme.Accent).MouseButton1Click:Connect(onLoad)
	miniButton(isDefault and "Retirer defaut" or "Def. par defaut").MouseButton1Click:Connect(onSetDefault)
	miniButton("Supprimer", Theme.Danger).MouseButton1Click:Connect(onDelete)
end

do
	local ConfigSection = addSection(SettingsPage, "Configs")
	addLabelRow(ConfigSection, "Par defaut, rien n'est active. Enregistre tes reglages actuels sous un nom, puis marque une config par defaut pour qu'elle se recharge automatiquement au prochain chargement du script.")

	local ConfigNameBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = "",
		PlaceholderText = "Nom de la config...",
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
	}, ConfigSection)
	corner(ConfigNameBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, ConfigNameBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, ConfigNameBox)

	local ConfigListContainer = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, ConfigSection)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ConfigListContainer)

	local function refreshConfigList()
		ConfigListContainer:ClearAllChildren()
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ConfigListContainer)

		local names = listConfigs()
		if #names == 0 then
			addLabelRow(ConfigListContainer, "Aucune config enregistree pour l'instant.")
			return
		end

		for _, name in ipairs(names) do
			addConfigRow(ConfigListContainer, name, Meta.defaultConfig == name,
				function()
					local data = loadConfigData(name)
					if not data then
						notify("Impossible de charger '" .. name .. "'.")
						return
					end
					applyFeatureSettings(data)
					notify("Config '" .. name .. "' chargee.")
				end,
				function()
					Meta.defaultConfig = (Meta.defaultConfig == name) and nil or name
					saveMeta()
					notify(Meta.defaultConfig == name and ("'" .. name .. "' est la config par defaut.") or "Plus de config par defaut.")
					refreshConfigList()
				end,
				function()
					deleteConfig(name)
					notify("Config '" .. name .. "' supprimee.")
					refreshConfigList()
				end
			)
		end
	end

	addButtonRow(ConfigSection, "Enregistrer la config actuelle", function()
		local name = sanitizeConfigName(ConfigNameBox.Text)
		if name == "" then
			notify("Donne un nom a ta config avant d'enregistrer.")
			return
		end
		saveConfig(name)
		notify("Config '" .. name .. "' enregistree.")
		refreshConfigList()
	end)

	refreshConfigList()
end

--------------------------------------------------------------------------------
-- Skin : Recherche (dump exploratoire, colle le resultat pour analyse) +
-- Skin d'arme (equipement reel). D'apres le dump de "Golden Zabunagi" :
-- l'arme portee est un simple MeshPart accroche au perso par un Motor6D
-- (Part0="Main"), avec juste un MeshId/TextureID/Size/Color/Material dessus -
-- pas de systeme d'accessoires/welds complexe comme suppose au debut (c'est
-- d'ailleurs pourquoi le premier essai base sur Humanoid:AddAccessory /
-- MeshPart clone+Weld n'avait rien donne). Reskin = recopier ces proprietes
-- directement sur le MeshPart deja en place, aucun clone/weld necessaire.
--------------------------------------------------------------------------------

do
	local Skin = {}

	-- Workspace/PlayerGui en premier : c'est la que vivent les objets "live"
	-- qui nous interessent (armes portees, UI ouverte). ReplicatedStorage peut
	-- etre enorme (particules, sons, assets...) - le scanner en dernier.
	Skin.SCAN_ROOTS = { workspace, PlayerGui, game:GetService("StarterGui"), game:GetService("ReplicatedFirst"), ReplicatedStorage }
	Skin.SCAN_MAX_MATCHES = 10
	Skin.SCAN_MAX_DEPTH = 10
	-- Budget SEPARE par conteneur (pas partage) : sinon un ReplicatedStorage
	-- enorme epuise tout le budget avant meme d'atteindre Workspace, qui ne
	-- serait alors jamais scanne (bug corrige : c'est ce qui s'est passe ici).
	Skin.SCAN_MAX_VISITED_PER_ROOT = 600000

	-- Cherche (insensible a la casse) tout instance dont le nom contient
	-- `query`, dans les conteneurs listes ci-dessus. S'arrete a
	-- Skin.SCAN_MAX_MATCHES resultats et ne descend pas plus loin que
	-- Skin.SCAN_MAX_DEPTH pour rester lisible/rapide.
	function Skin.findMatches(query)
		local lowerQuery = query:lower()
		local matches = {}
		local stats = {}

		for _, root in ipairs(Skin.SCAN_ROOTS) do
			local visited = 0
			local truncated = false

			local function walk(inst, depth)
				if #matches >= Skin.SCAN_MAX_MATCHES then return end
				if visited >= Skin.SCAN_MAX_VISITED_PER_ROOT then
					truncated = true
					return
				end
				visited = visited + 1
				if inst.Name:lower():find(lowerQuery, 1, true) then
					table.insert(matches, inst)
				end
				if depth >= Skin.SCAN_MAX_DEPTH then return end
				for _, child in ipairs(inst:GetChildren()) do
					if #matches >= Skin.SCAN_MAX_MATCHES then return end
					if visited >= Skin.SCAN_MAX_VISITED_PER_ROOT then
						truncated = true
						return
					end
					walk(child, depth + 1)
				end
			end

			walk(root, 0)
			table.insert(stats, string.format("%s: %d visite(s)%s", root.Name, visited, truncated and " (limite atteinte)" or ""))
			if #matches >= Skin.SCAN_MAX_MATCHES then break end
		end

		return matches, stats
	end

	Skin.SkinSection = addSection(SkinPage, "Scanner (exploration)")
	addLabelRow(Skin.SkinSection, "Cherche un nom (ex: Valentine, Shop, Skin...) dans ReplicatedStorage / PlayerGui / StarterGui / ReplicatedFirst / Workspace, et copie un dump des resultats dans le presse-papier. Colle-le moi pour qu'on trouve la vraie structure des items.")

	Skin.QueryBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = "Valentine",
		PlaceholderText = "Nom a chercher...",
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
	}, Skin.SkinSection)
	corner(Skin.QueryBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Skin.QueryBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, Skin.QueryBox)

	Skin.ScanResultLabel = addLabelRow(Skin.SkinSection, "Aucune recherche effectuee pour l'instant.")

	addButtonRow(Skin.SkinSection, "Chercher et copier le dump", function()
		local query = Skin.QueryBox.Text
		if query == "" then
			notify("Tape un nom a chercher.")
			return
		end

		local matches, stats = Skin.findMatches(query)
		if #matches == 0 then
			Skin.ScanResultLabel.Text = "Aucun resultat pour '" .. query .. "'. (" .. table.concat(stats, " | ") .. ")"
			notify("Aucun resultat. Voir le detail sous la recherche (nb d'instances visitees par conteneur).")
			return
		end

		local lines = {
			"=== Recherche '" .. query .. "' ===",
			os.date("%d/%m/%Y %H:%M:%S"),
			#matches .. " resultat(s)" .. (#matches >= Skin.SCAN_MAX_MATCHES and " (limite atteinte, affine la recherche pour voir le reste)" or ""),
			"Scan : " .. table.concat(stats, " | "),
			"",
		}
		for _, inst in ipairs(matches) do
			table.insert(lines, "--- " .. inst:GetFullName() .. "  [" .. inst.ClassName .. "] ---")
			table.insert(lines, dumpTree(inst, Skin.SCAN_MAX_DEPTH))
			table.insert(lines, "")
		end

		copyOrPrint(table.concat(lines, "\n"))
		Skin.ScanResultLabel.Text = #matches .. " resultat(s) pour '" .. query .. "', dump copie."
	end)

	-- Ne garde que les resultats utilisables comme source de skin : soit un
	-- MeshPart avec un mesh charge (armes recentes, ex. Golden Zabunagi),
	-- soit un Part classique avec un SpecialMesh enfant qui lui donne sa
	-- forme (ancienne methode, ex. Spider Gunbai - ClassName="Part", pas
	-- "MeshPart", donc invisible pour le premier filtre si on s'arrete la).
	function Skin.findMeshMatches(query)
		local matches, stats = Skin.findMatches(query)
		local meshMatches = {}
		for _, inst in ipairs(matches) do
			if inst:IsA("MeshPart") and inst.MeshId ~= "" then
				table.insert(meshMatches, inst)
			elseif inst:IsA("BasePart") and inst:FindFirstChildWhichIsA("SpecialMesh") then
				table.insert(meshMatches, inst)
			end
		end
		return meshMatches, stats
	end

	-- Ton arme equipee = un MeshPart de ton perso qui a un Motor6D enfant
	-- (c'est le joint qui l'accroche a la part "Main"). Generique : marche
	-- pour n'importe quelle arme, pas seulement Golden Zabunagi.
	function Skin.findMyWeaponParts()
		local character = LocalPlayer.Character
		local found = {}
		if not character then return found end
		for _, desc in ipairs(character:GetDescendants()) do
			if desc:IsA("MeshPart") and desc:FindFirstChildWhichIsA("Motor6D") then
				table.insert(found, desc)
			end
		end
		return found
	end

	Skin.WeaponSkinSection = addSection(SkinPage, "Skin d'arme")
	addLabelRow(Skin.WeaponSkinSection, "Ton arme equipee est un simple MeshPart accroche a ton perso par un Motor6D. On recopie juste MeshId/TextureID/Taille/Couleur d'une autre arme trouvee (rack du shop, arme d'un autre joueur...) directement dessus : 100% visuel, rien n'est envoye au serveur. Un respawn ou un changement d'arme remet l'original (a reappliquer).")

	Skin.myWeaponParts = {}
	Skin.myWeaponLabels = {}
	Skin.myWeaponSelector = nil
	Skin.MyWeaponHolder = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, Skin.WeaponSkinSection)
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, Skin.MyWeaponHolder)

	function Skin.refreshMyWeapon()
		Skin.MyWeaponHolder:ClearAllChildren()
		create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, Skin.MyWeaponHolder)

		Skin.myWeaponParts = Skin.findMyWeaponParts()
		if #Skin.myWeaponParts == 0 then
			addLabelRow(Skin.MyWeaponHolder, "Aucune arme detectee sur ton perso (equipe-la en jeu, puis reessaie).")
			Skin.myWeaponSelector = nil
			return
		end

		Skin.myWeaponLabels = {}
		for _, part in ipairs(Skin.myWeaponParts) do
			table.insert(Skin.myWeaponLabels, part.Name)
		end
		Skin.myWeaponSelector = addDropdownRow(Skin.MyWeaponHolder, "Mon arme", Skin.myWeaponLabels, Skin.myWeaponLabels[1], nil)
	end

	addButtonRow(Skin.WeaponSkinSection, "Detecter mon arme", Skin.refreshMyWeapon)
	Skin.refreshMyWeapon()

	Skin.skinScanResults = {}
	Skin.skinResultLabels = {}
	Skin.skinSelector = nil

	Skin.SkinQueryBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = "",
		PlaceholderText = "Nom de l'arme/skin a copier (ex: Golden Zabunagi)...",
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
	}, Skin.WeaponSkinSection)
	corner(Skin.SkinQueryBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Skin.SkinQueryBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, Skin.SkinQueryBox)

	Skin.SkinSearchResultLabel = addLabelRow(Skin.WeaponSkinSection, "Aucune recherche effectuee.")

	Skin.SkinResultHolder = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, Skin.WeaponSkinSection)
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, Skin.SkinResultHolder)

	addButtonRow(Skin.WeaponSkinSection, "Chercher un skin source", function()
		local query = Skin.SkinQueryBox.Text
		if query == "" then
			notify("Tape un nom a chercher.")
			return
		end
		local matches, stats = Skin.findMeshMatches(query)
		Skin.skinScanResults = matches
		Skin.SkinSearchResultLabel.Text = #matches .. " MeshPart trouve(s) pour '" .. query .. "'. (" .. table.concat(stats, " | ") .. ")"

		Skin.SkinResultHolder:ClearAllChildren()
		create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, Skin.SkinResultHolder)

		if #matches == 0 then
			Skin.skinSelector = nil
			addLabelRow(Skin.SkinResultHolder, "Aucun MeshPart trouve avec ce nom.")
			return
		end

		Skin.skinResultLabels = {}
		for _, inst in ipairs(matches) do
			table.insert(Skin.skinResultLabels, inst:GetFullName())
		end
		Skin.skinSelector = addDropdownRow(Skin.SkinResultHolder, "Skin source", Skin.skinResultLabels, Skin.skinResultLabels[1], nil)
	end)

	addButtonRow(Skin.WeaponSkinSection, "Appliquer ce skin sur mon arme", function()
		if not Skin.myWeaponSelector or #Skin.myWeaponParts == 0 then
			notify("Detecte d'abord ton arme.")
			return
		end
		if not Skin.skinSelector or #Skin.skinScanResults == 0 then
			notify("Cherche d'abord un skin source.")
			return
		end

		local myIndex = table.find(Skin.myWeaponLabels, Skin.myWeaponSelector.Get())
		local myPart = myIndex and Skin.myWeaponParts[myIndex]
		local sourceIndex = table.find(Skin.skinResultLabels, Skin.skinSelector.Get())
		local sourcePart = sourceIndex and Skin.skinScanResults[sourceIndex]

		if not (myPart and myPart.Parent) then
			notify("Ton arme n'existe plus (respawn ?), redetecte-la.")
			return
		end
		if not (sourcePart and sourcePart.Parent) then
			notify("Le skin source n'existe plus, refais une recherche.")
			return
		end

		-- On NE TOUCHE PLUS a myPart (Motor6D/hitbox/collision intacts) : trop
		-- risque (a deja provoque un "tp sur l'arme" en cassant l'attache
		-- reelle). A la place : originale rendue invisible, et un clone du
		-- skin (juste le mesh, sans particules/attachments de la source)
		-- colle par-dessus via WeldConstraint, qui la suit partout puisque
		-- myPart continue d'etre anime normalement par son propre Motor6D.
		local OVERLAY_NAME = "VonClientWeaponSkin"
		local existingOverlay = myPart:FindFirstChild(OVERLAY_NAME)
		if existingOverlay then existingOverlay:Destroy() end

		local overlay = sourcePart:Clone()
		for _, child in ipairs(overlay:GetChildren()) do
			-- Garde SpecialMesh/Decal/Texture (donnent sa forme/son skin a un
			-- Part classique, ex. Spider Gunbai) ; vire le reste (Weld,
			-- Motor6D, Attachment, ParticleEmitter, Sound, Script...) qui
			-- referencait le contexte de la source et n'a plus de sens isole.
			if not (child:IsA("SpecialMesh") or child:IsA("Decal") or child:IsA("Texture")) then
				child:Destroy()
			end
		end
		overlay.Name = OVERLAY_NAME
		overlay.Anchored = false
		overlay.CanCollide = false
		pcall(function() overlay.Massless = true end)
		overlay.Transparency = 0
		overlay.CFrame = myPart.CFrame
		overlay.Parent = myPart

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = myPart
		weld.Part1 = overlay
		weld.Parent = overlay

		myPart.Transparency = 1

		notify("Skin colle par-dessus ton arme (originale juste rendue invisible, rien d'autre touche).")
	end)

	addButtonRow(Skin.WeaponSkinSection, "Retirer le skin colle", function()
		if not Skin.myWeaponSelector or #Skin.myWeaponParts == 0 then
			notify("Detecte d'abord ton arme.")
			return
		end
		local myIndex = table.find(Skin.myWeaponLabels, Skin.myWeaponSelector.Get())
		local myPart = myIndex and Skin.myWeaponParts[myIndex]
		if not (myPart and myPart.Parent) then
			notify("Ton arme n'existe plus (respawn ?), redetecte-la.")
			return
		end

		local overlay = myPart:FindFirstChild("VonClientWeaponSkin")
		if overlay then overlay:Destroy() end
		myPart.Transparency = 0
		notify("Skin retire, arme d'origine visible.")
	end)
end

do
	local DebugSection = addSection(SettingsPage, "Debug")
	addLabelRow(DebugSection, "Dump recursif de LocalPlayer + Character (pour reperer un systeme d'inventaire perso).")
	addButtonRow(DebugSection, "Dump LocalPlayer", dumpLocalPlayerToClipboard)
	addLabelRow(DebugSection, "Dump complet (sans limite de profondeur) du premier objet trouve dans l'inventaire - pour verifier ou se trouve la quantite.")
	addButtonRow(DebugSection, "Dump 1er item d'inventaire", dumpFirstInventoryItem)
end

-- StatusLabel doit survivre au-dela de ce bloc (mis a jour par la boucle de
-- statut plus bas), donc predeclare ici et assigne dans le do...end.
local StatusLabel
do
	local ConnSection = addSection(SettingsPage, "Connexion serveur Python")
	addLabelRow(ConnSection, "Endpoint : " .. OVERLAY_ENDPOINT)
	StatusLabel = addLabelRow(ConnSection, "Statut : en attente...")
end

--------------------------------------------------------------------------------
------------------------------- SETTINGS ----------------------------------------
--------------------------------------------------------------------------------

do
	local ShortcutSection = addSection(SettingsPage, "Raccourcis")
	addKeybindRow(ShortcutSection, "Touche menu", MENU_TOGGLE_KEY, function(newKey)
		MENU_TOGGLE_KEY = newKey
		Prefs.MenuKeybind = newKey.Name
		savePrefs()
	end)
end

do
	local WebhookSection = addSection(SettingsPage, "Webhook Discord")
	addLabelRow(WebhookSection, "Utilise pour l'envoi automatique de l'inventaire (page Joueur > Inventaire). Colle un lien de webhook Discord puis enregistre.")

	local WebhookUrlBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = Prefs.InventoryWebhookUrl or "",
		PlaceholderText = "https://discord.com/api/webhooks/...",
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, WebhookSection)
	corner(WebhookUrlBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, WebhookUrlBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, WebhookUrlBox)

	addButtonRow(WebhookSection, "Enregistrer le webhook", function()
		local url = WebhookUrlBox.Text
		if url == "" then
			notify("Le lien webhook ne peut pas etre vide.")
			return
		end
		Prefs.InventoryWebhookUrl = url
		savePrefs()
		notify("Webhook enregistre.")
	end)

	addButtonRow(WebhookSection, "Copier le webhook actuel", function()
		local url = Prefs.InventoryWebhookUrl or ""
		if url == "" then
			notify("Aucun webhook configure.")
			return
		end
		if setclipboard then
			local ok = pcall(setclipboard, url)
			notify(ok and "Webhook copie dans le presse-papier." or "Erreur : setclipboard a echoue.")
		else
			notify("setclipboard indisponible. Webhook affiche en console (F9).")
			print(url)
		end
	end)
end

-- Coupe tout proprement : previent le renderer Python (enabled=false), coupe
-- toutes les connexions longue-duree, detruit les billboards et le menu.
local function unload()
	if unloaded then return end
	unloaded = true

	if request then
		pcall(sendOverlayPacket, { enabled = false, players = {} })
	end

	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end

	for player in pairs(ChatOverlayByPlayer) do
		clearChatOverlay(player)
	end

	ScreenGui:Destroy()
end

local SessionSection = addSection(SettingsPage, "Session")
local UnloadButton = create("TextButton", {
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundColor3 = Theme.Danger,
	Text = "Decharger le script",
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
}, SessionSection)
corner(UnloadButton, 10)
local unloadScale = create("UIScale", { Scale = 1 }, UnloadButton)
UnloadButton.MouseEnter:Connect(function() tween(UnloadButton, { BackgroundColor3 = Color3.fromRGB(250, 110, 110) }, 0.1) end)
UnloadButton.MouseLeave:Connect(function() tween(UnloadButton, { BackgroundColor3 = Theme.Danger }, 0.1) end)
UnloadButton.MouseButton1Click:Connect(function()
	tween(unloadScale, { Scale = 0.96 }, 0.08)
	task.delay(0.08, function() tween(unloadScale, { Scale = 1 }, 0.12) end)
	unload()
end)

-- Alerte si un joueur a le cooldown "Chakra Sense" actif (structure
-- ReplicatedStorage.Cooldowns.<Joueur>.<NomCooldown> propre a ce jeu).
-- Verifie toutes les 15s, seulement quand ChakraSenseNotifier est coche.
task.spawn(function()
	while not unloaded do
		task.wait(15)
		if not (unloaded or not ChakraSenseNotifier) then
			local cooldownsFolder = ReplicatedStorage:FindFirstChild("Cooldowns")
			if cooldownsFolder then
				for _, playerFolder in ipairs(cooldownsFolder:GetChildren()) do
					if playerFolder:FindFirstChild("Chakra Sense") then
						notify(string.format("%s a Chakra Sense actif", playerFolder.Name))
					end
				end
			end
		end
	end
end)

-- Les toggles ne declenchent leur onChange qu'au clic : sans ca, un effet deja
-- actif au demarrage (config par defaut chargee avec NoFog/Fly/etc. a true)
-- s'afficherait allume dans le menu sans que l'effet reel ne soit applique.
setEnabled(enabled)
setNoFog(NoFogEnabled)
setNoRain(NoRainEnabled)
setFullBright(FullBrightEnabled)
setTimeChanger(TimeChangerEnabled)
setNoclip(NoclipEnabled)
setFly(FlyEnabled)

selectPage("Visuels")
playInjectionSplash()

-- Rafraichit le statut de connexion une fois par seconde (pas besoin de plus).
task.spawn(function()
	while not unloaded do
		if lastConnOk == nil then
			StatusLabel.Text = "Statut : en attente..."
			StatusLabel.TextColor3 = Theme.SubText
		elseif lastConnOk then
			StatusLabel.Text = "Statut : connecte"
			StatusLabel.TextColor3 = Theme.Success
		else
			StatusLabel.Text = "Statut : deconnecte (lance light_chat_overlay.py ?)"
			StatusLabel.TextColor3 = Theme.Danger
		end
		task.wait(1)
	end
end)

track(UserInputService.InputBegan:Connect(function(input, gpe)
	if unloaded then return end
	if gpe then return end
	if capturingKeybind then return end
	if input.KeyCode == MENU_TOGGLE_KEY then
		toggleWindow()
	end
end))
