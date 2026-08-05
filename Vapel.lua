local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local MENU_TOGGLE_KEY = Enum.KeyCode.RightControl -- ouvre/ferme le menu (comme Window.ToggleKey dans RbxUI)

local Theme = {
	Background = Color3.fromRGB(22, 22, 26),
	Panel = Color3.fromRGB(30, 30, 36),
	Element = Color3.fromRGB(40, 40, 47),
	Stroke = Color3.fromRGB(54, 54, 62),
	Accent = Color3.fromRGB(114, 137, 255),
	Text = Color3.fromRGB(235, 235, 240),
	SubText = Color3.fromRGB(150, 150, 158),
}

local OVERLAY_ENDPOINT = "http://127.0.0.1:8787/update"
local OVERLAY_WRITE_INTERVAL = 1 / 60 -- 60 envois/sec suffisent (texte ESP), pas besoin de coller aux 60 FPS du jeu

local INVENTORY_WEBHOOK_URL = "https://discord.com/api/webhooks/1534652533186887800/X3KqFqpuIBdQa7DqWJI7U0Gg1PA2FiB76cj78HOKBEkxftwCiPW3fwNYipO3p77rhT-u"
local INVENTORY_AUTO_INTERVAL = 300 -- 5 minutes entre deux envois automatiques

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local ChatOverlayByPlayer = {}
local enabled = false
local EspMode = "Lua" -- "Lua" (BillboardGui) ou "Python" (overlay externe via HTTP)
local EspMaxDistance = 0 -- studs, 0 = illimite
local ShowHealth = true
local ShowDistance = false
local ShowChakra = false
local ShowBlood = false
local lastConnOk = nil -- nil = pas encore teste, true/false = dernier resultat request()
local unloaded = false
local ChakraSenseNotifier = true
local NoFogEnabled = false
local NoRainEnabled = false
local FullBrightEnabled = false
local BrightnessLevel = 1
local TimeChangerEnabled = false
local TimeOfDay = "Morning"

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
		y += ROW_HEIGHT
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
			y += ROW_HEIGHT
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
			y += ROW_HEIGHT
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
			y += ROW_HEIGHT
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
		writeAccum += dt
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
-- Menu "VapeL" : cache par defaut, s'ouvre/se ferme avec MENU_TOGGLE_KEY (meme
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

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VapeL"
ScreenGui.ResetOnSpawn = false
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
		Size = UDim2.new(0, 260, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
	}, ToastHolder)
	corner(toast, 8)
	create("UIStroke", { Color = Theme.Stroke }, toast)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, toast)

	local label = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextWrapped = true,
		TextTransparency = 1,
	}, toast)

	tween(toast, { BackgroundTransparency = 0 }, 0.15)
	tween(label, { TextTransparency = 0 }, 0.15)

	task.delay(3, function()
		if not toast.Parent then return end
		tween(toast, { BackgroundTransparency = 1 }, 0.15)
		tween(label, { TextTransparency = 1 }, 0.15)
		task.wait(0.15)
		toast:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Safe Spot : marque-page de position (enregistre ou tu es, revient plus tard
-- au meme endroit). Ne touche ni aux collisions ni aux degats.
--------------------------------------------------------------------------------

local SafeSpotPosition = nil

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

local SelectedChakraPoint = ChakraPointNames[1]

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
	{ name = "Items", keywords = { "scalpel", "extraction spoon", "lava snake skin", "samurai soul", "trait scroll", "mastery scroll" } },
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
				invCount += 1
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
				hudCount += 1
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
		Url = INVENTORY_WEBHOOK_URL,
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

local Main = create("Frame", {
	Size = UDim2.new(0, 460, 0, 320),
	Position = UDim2.new(0.5, -230, 0.5, -160),
	BackgroundColor3 = Theme.Background,
	Visible = false,
	Active = true,
}, ScreenGui)
corner(Main, 10)
create("UIStroke", { Color = Theme.Stroke }, Main)

local TopBar = create("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Theme.Panel }, Main)
corner(TopBar, 10)

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 0),
	Size = UDim2.new(1, -70, 1, 0),
	Text = "VapeL",
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Theme.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TopBar)

local CloseButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.new(0, 30, 0, 30),
	BackgroundColor3 = Theme.Element,
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = Theme.Text,
	AutoButtonColor = false,
}, TopBar)
corner(CloseButton, 6)
CloseButton.MouseButton1Click:Connect(function() Main.Visible = false end)

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

local Sidebar = create("Frame", {
	Position = UDim2.new(0, 0, 0, 42),
	Size = UDim2.new(0, 130, 1, -42),
	BackgroundColor3 = Theme.Panel,
}, Main)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, Sidebar)
create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, Sidebar)

local PagesHolder = create("Frame", {
	Position = UDim2.new(0, 130, 0, 42),
	Size = UDim2.new(1, -130, 1, -42),
	BackgroundTransparency = 1,
}, Main)

local pages, sidebarButtons, currentPage = {}, {}, nil

local function selectPage(name)
	if currentPage then
		pages[currentPage].Visible = false
		sidebarButtons[currentPage].BackgroundColor3 = Theme.Element
		sidebarButtons[currentPage].TextColor3 = Theme.SubText
	end
	pages[name].Visible = true
	sidebarButtons[name].BackgroundColor3 = Theme.Accent
	sidebarButtons[name].TextColor3 = Color3.new(1, 1, 1)
	currentPage = name
end

local function createCategory(name)
	local Button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Theme.Element,
		Text = name,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		AutoButtonColor = false,
	}, Sidebar)
	corner(Button, 6)
	Button.MouseButton1Click:Connect(function() selectPage(name) end)

	local Page = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, PagesHolder)
	create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, Page)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	}, Page)

	pages[name] = Page
	sidebarButtons[name] = Button
	return Page
end

local function addSection(page, title)
	local Card = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
	}, page)
	corner(Card, 8)
	create("UIStroke", { Color = Theme.Stroke }, Card)

	create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Card)

	local Content = create("Frame", {
		Position = UDim2.new(0, 10, 0, 34),
		Size = UDim2.new(1, -20, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, Card)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, Content)
	create("UIPadding", { PaddingBottom = UDim.new(0, 10) }, Content)

	return Content
end

local function addToggleRow(content, text, default, onChange)
	local state = default or false

	local Row = create("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Row)

	local Switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 46, 0, 24),
		BackgroundColor3 = state and Theme.Accent or Theme.Element,
	}, Row)
	corner(Switch, 12)

	local Knob = create("Frame", {
		Size = UDim2.new(0, 18, 0, 18),
		Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, Switch)
	corner(Knob, 9)

	local Click = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "" }, Switch)

	local function set(newState)
		state = newState
		tween(Switch, { BackgroundColor3 = state and Theme.Accent or Theme.Element })
		tween(Knob, { Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) })
		if onChange then onChange(state) end
	end
	Click.MouseButton1Click:Connect(function() set(not state) end)

	return { Set = set, Get = function() return state end }
end

local function addDropdownRow(content, text, options, default, onChange)
	local selected = default or options[1]

	local Holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Element,
		ClipsDescendants = true,
	}, content)
	corner(Holder, 6)

	local MainButton = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Text = text .. ": " .. tostring(selected),
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
	}, Holder)

	local List = create("Frame", {
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, #options * 30),
		BackgroundTransparency = 1,
	}, Holder)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, List)

	local open = false
	local function close()
		open = false
		tween(Holder, { Size = UDim2.new(1, 0, 0, 34) })
	end

	for _, option in ipairs(options) do
		local OptButton = create("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = tostring(option),
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = Theme.SubText,
		}, List)
		OptButton.MouseButton1Click:Connect(function()
			selected = option
			MainButton.Text = text .. ": " .. tostring(selected)
			close()
			if onChange then onChange(selected) end
		end)
	end

	MainButton.MouseButton1Click:Connect(function()
		open = not open
		if open then
			tween(Holder, { Size = UDim2.new(1, 0, 0, 34 + #options * 30) })
		else
			close()
		end
	end)

	return { Get = function() return selected end }
end

local function addSliderRow(content, text, min, max, default, step, onChange)
	step = step or 1
	local value = default or min

	local Holder = create("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -60, 0, 20),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
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
		Size = UDim2.new(0, 70, 0, 20),
		BackgroundTransparency = 1,
		Text = formatValue(value),
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, Holder)

	local Bar = create("Frame", {
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Theme.Element,
	}, Holder)
	corner(Bar, 5)

	local function pctFor(v) return (v - min) / (max - min) end

	local Fill = create("Frame", { Size = UDim2.new(pctFor(value), 0, 1, 0), BackgroundColor3 = Theme.Accent }, Bar)
	corner(Fill, 5)

	local dragging = false
	local function apply(x)
		local p = math.clamp((x - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
		local raw = min + (max - min) * p
		value = math.clamp(math.floor(raw / step + 0.5) * step, min, max)
		Fill.Size = UDim2.new(pctFor(value), 0, 1, 0)
		ValueLabel.Text = formatValue(value)
		if onChange then onChange(value) end
	end

	Bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			apply(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			apply(input.Position.X)
		end
	end)

	return { Get = function() return value end }
end

local function addLabelRow(content, text)
	return create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, content)
end

local function addButtonRow(content, text, onClick)
	local Button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Theme.Element,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
	}, content)
	corner(Button, 6)

	Button.MouseButton1Click:Connect(function()
		tween(Button, { BackgroundColor3 = Theme.Accent }, 0.1)
		task.delay(0.1, function()
			tween(Button, { BackgroundColor3 = Theme.Element }, 0.15)
		end)
		if onClick then onClick() end
	end)

	return Button
end

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

local VisualsPage = createCategory("Visuels")
local PlayerPage = createCategory("Joueur")
local OtherPage = createCategory("Autres")

--------------------------------------------------------------------------------
------------------------------- VISUALS ----------------------------------------
--------------------------------------------------------------------------------


-- Reglages ESP : active/désactive, mode (Lua ou Python), distance max, affichage PV et distance.

local EspSection = addSection(VisualsPage, "ESP")

addToggleRow(EspSection, "ESP Actif", enabled, function(state)
	setEnabled(state)
	if not state then pushOverlayDisabled() end
end)

addDropdownRow(EspSection, "Mode ESP", { "Lua", "Python" }, EspMode, function(mode)
	local wasPython = enabled and EspMode == "Python"
	EspMode = mode
	setEnabled(enabled) -- reapplique la visibilite des billboards selon le nouveau mode
	if wasPython and mode ~= "Python" then pushOverlayDisabled() end
end)

addSliderRow(EspSection, "Distance Max", 0, 10000, EspMaxDistance, 1, function(v)
	EspMaxDistance = v
end)

addToggleRow(EspSection, "Afficher PV", ShowHealth, function(state)
	ShowHealth = state
	refreshAllPlayerLabels()
end)

addToggleRow(EspSection, "Afficher Distance", ShowDistance, function(state)
	ShowDistance = state
	refreshAllPlayerLabels()
end)

addToggleRow(EspSection, "Afficher Chakra", ShowChakra, function(state)
	ShowChakra = state
	refreshAllPlayerLabels()
end)

addToggleRow(EspSection, "Afficher Blood", ShowBlood, function(state)
	ShowBlood = state
	refreshAllPlayerLabels()
end)

local EnvSection = addSection(VisualsPage, "Environnement")

addToggleRow(EnvSection, "No Fog", NoFogEnabled, setNoFog)
addToggleRow(EnvSection, "No Rain", NoRainEnabled, setNoRain)
addToggleRow(EnvSection, "Full Bright", FullBrightEnabled, setFullBright)

addSliderRow(EnvSection, "Brightness Level", 1, 10, BrightnessLevel, 0.1, function(v)
	BrightnessLevel = v
end)

addDropdownRow(EnvSection, "Heure", { "Morning", "Afternoon", "Evening", "Night" }, TimeOfDay, function(v)
	TimeOfDay = v
end)

addToggleRow(EnvSection, "Time Changer", TimeChangerEnabled, setTimeChanger)

--------------------------------------------------------------------------------




--------------------------------------------------------------------------------
------------------------------- PLAYER -----------------------------------------
--------------------------------------------------------------------------------

local NotifSection = addSection(PlayerPage, "Notifications")

addToggleRow(NotifSection, "Chakra Sense Notifier", ChakraSenseNotifier, function(state)
	ChakraSenseNotifier = state
end)

local SafeSpotSection = addSection(PlayerPage, "Safe Spot")
addButtonRow(SafeSpotSection, "Definir Safe Spot", setSafeSpot)
addButtonRow(SafeSpotSection, "Teleporter au Safe Spot", teleportToSafeSpot)

local ChakraPointsSection = addSection(PlayerPage, "Chakra Points")
if #ChakraPointNames > 0 then
	addDropdownRow(ChakraPointsSection, "Chakra Point", ChakraPointNames, SelectedChakraPoint, function(v)
		SelectedChakraPoint = v
	end)
	addButtonRow(ChakraPointsSection, "Teleporter", teleportToChakraPoint)
else
	addLabelRow(ChakraPointsSection, "Aucun ChakraPoints trouve dans workspace.")
end

local InventorySection = addSection(PlayerPage, "Inventaire")
addLabelRow(InventorySection, "Envoie Inventaire (Loadout) + Hotbar + Lifeforce au webhook Discord. Auto toutes les 5 min. Astuce : ouvre ton inventaire en jeu une fois pour que les slots se remplissent.")
addButtonRow(InventorySection, "Envoyer au webhook Discord", sendInventoryToWebhook)

local DebugSection = addSection(OtherPage, "Debug")
addLabelRow(DebugSection, "Dump recursif de LocalPlayer + Character (pour reperer un systeme d'inventaire perso).")
addButtonRow(DebugSection, "Dump LocalPlayer", dumpLocalPlayerToClipboard)
addLabelRow(DebugSection, "Dump complet (sans limite de profondeur) du premier objet trouve dans l'inventaire - pour verifier ou se trouve la quantite.")
addButtonRow(DebugSection, "Dump 1er item d'inventaire", dumpFirstInventoryItem)

local ConnSection = addSection(OtherPage, "Connexion serveur Python")
addLabelRow(ConnSection, "Endpoint : " .. OVERLAY_ENDPOINT)
local StatusLabel = addLabelRow(ConnSection, "Statut : en attente...")

--------------------------------------------------------------------------------
------------------------------- AUTRES -----------------------------------------
--------------------------------------------------------------------------------

local ShortcutSection = addSection(OtherPage, "Raccourcis")
addLabelRow(ShortcutSection, "Touche menu : " .. MENU_TOGGLE_KEY.Name)

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

local SessionSection = addSection(OtherPage, "Session")
local UnloadButton = create("TextButton", {
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = Color3.fromRGB(200, 60, 60),
	Text = "Decharger le script",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
}, SessionSection)
corner(UnloadButton, 6)
UnloadButton.MouseButton1Click:Connect(unload)

-- Alerte si un joueur a le cooldown "Chakra Sense" actif (structure
-- ReplicatedStorage.Cooldowns.<Joueur>.<NomCooldown> propre a ce jeu).
-- Verifie toutes les 15s, seulement quand ChakraSenseNotifier est coche.
task.spawn(function()
	while not unloaded do
		task.wait(15)
		if unloaded or not ChakraSenseNotifier then continue end

		local cooldownsFolder = ReplicatedStorage:FindFirstChild("Cooldowns")
		if not cooldownsFolder then continue end

		for _, playerFolder in ipairs(cooldownsFolder:GetChildren()) do
			if playerFolder:FindFirstChild("Chakra Sense") then
				notify(string.format("%s a Chakra Sense actif", playerFolder.Name))
			end
		end
	end
end)

selectPage("Visuels")

-- Rafraichit le statut de connexion une fois par seconde (pas besoin de plus).
task.spawn(function()
	while not unloaded do
		if lastConnOk == nil then
			StatusLabel.Text = "Statut : en attente..."
			StatusLabel.TextColor3 = Theme.SubText
		elseif lastConnOk then
			StatusLabel.Text = "Statut : connecte"
			StatusLabel.TextColor3 = Color3.fromRGB(90, 220, 120)
		else
			StatusLabel.Text = "Statut : deconnecte (lance light_chat_overlay.py ?)"
			StatusLabel.TextColor3 = Color3.fromRGB(230, 80, 80)
		end
		task.wait(1)
	end
end)

track(UserInputService.InputBegan:Connect(function(input, gpe)
	if unloaded then return end
	if gpe then return end
	if input.KeyCode == MENU_TOGGLE_KEY then
		Main.Visible = not Main.Visible
	end
end))
