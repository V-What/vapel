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
print("HALF1 OK")
