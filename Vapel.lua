--------------------------------------------------------------------------------
-- Limite Luau : 200 registres locaux.
-- Ce fichier entier est compile comme UNE SEULE fonction (le chunk racine),
-- et Luau limite une fonction a 200 registres locaux actifs simultanement.
-- Un local ne libere son registre que quand le bloc lexical (do...end, if,
-- for, function...) qui le contient se termine - donc des dizaines de
-- variables locales "a plat" (jamais imbriquees dans un do...end qui se
-- referme) s'accumulent et finissent par depasser la limite, meme si chacune
-- semble anodine individuellement. Erreur typique a la compilation :
--   Out of local registers when trying to allocate <Nom> : exceeded limit 200
-- Regle a suivre en ajoutant du code ici (variables/UI/sections...) :
--   - Isoler chaque section/feature independante dans son propre do...end
--     des qu'elle a ses propres variables locales (ex: `local XSection = ...`)
--     qui ne sont pas reutilisees ailleurs : ca libere leurs registres des la
--     fin du bloc au lieu de les garder ouverts jusqu'a la fin du fichier.
--   - Preferer ecrire directement dans une table partagee (voir
--     FEATURE_CONTROLS plus bas) plutot que de creer une variable locale par
--     controle UI.
--   - Si l'erreur revient malgre ce wrapping, c'est que le total cumule sur
--     tout le fichier est deja proche de la limite : chercher d'autres blocs
--     "a plat" (grep "^local " et "^\tlocal ") a regrouper dans des do...end,
--     pas seulement le code qu'on vient d'ajouter.
--------------------------------------------------------------------------------

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

-- Valeurs de depart uniquement : Skin.set() (plus bas, juste apres le
-- chargement des Prefs) ecrase ces champs avec le theme choisi et les repeint
-- a chaque changement. Ne pas lire Theme au moment de creer une instance sans
-- passer par Skin.paint, sinon la couleur est figee a la creation et ne suivra
-- plus les changements de theme.
local Theme = {
	Background = Color3.fromRGB(15, 17, 19),
	Panel = Color3.fromRGB(23, 26, 29),
	PanelLight = Color3.fromRGB(29, 33, 38), -- haut des gradients de card, legerement plus clair que Panel
	Element = Color3.fromRGB(29, 33, 38),
	ElementHover = Color3.fromRGB(33, 37, 41),
	Stroke = Color3.fromRGB(38, 42, 47),
	StrokeStrong = Color3.fromRGB(51, 57, 64), -- filet appuye : bordure au survol, contour ouvert
	Accent = Color3.fromRGB(230, 233, 236),
	AccentDim = Color3.fromRGB(185, 190, 196), -- accent assombri, utilise dans les gradients
	OnAccent = Color3.fromRGB(15, 17, 19), -- texte/icone POSE sur un fond Accent
	Danger = Color3.fromRGB(217, 88, 75),
	Warn = Color3.fromRGB(217, 164, 65),
	Success = Color3.fromRGB(76, 175, 109),
	Text = Color3.fromRGB(230, 233, 236),
	SubText = Color3.fromRGB(121, 128, 138),
	SubTextDim = Color3.fromRGB(91, 98, 107), -- texte tertiaire : placeholders, unites
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
	ShowKeybindHud = false,
	MenuTheme = "Graphite",
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

--------------------------------------------------------------------------------
-- Themes de couleur
--------------------------------------------------------------------------------
-- La table Theme (definie plus haut) reste LA table lue partout dans le
-- fichier : changer de theme ecrase ses champs au lieu de remplacer la table,
-- pour que tout le code existant qui fait `Theme.Accent` continue de marcher
-- sans etre touche.
--
-- Mais Roblox COPIE la couleur au moment de la creation de l'instance
-- (`BackgroundColor3 = Theme.Panel` prend la valeur, pas une reference) : muter
-- Theme ne repeint donc rien tout seul. D'ou Skin.paint, par lequel passent
-- toutes les instances du menu : il retient quelle propriete suit quel jeton et
-- les repeint toutes d'un coup au changement de theme.
--
-- Regle de couleur commune aux 6 themes : Success / Warn / Danger ne sont
-- JAMAIS l'accent. Ils veulent toujours dire la meme chose (ca va / attention /
-- probleme), sinon "actif" et "ca va" auraient la meme couleur - c'est pour ca
-- que Jade garde un ambre pour Warn au lieu de recycler son vert.
--
-- Tout est regroupe dans UNE table (etat + fonctions) plutot qu'en locals
-- separes : le fichier entier est une seule fonction Luau limitee a 200
-- registres locaux (voir la note en tete de fichier).
local Skin = {
	current = nil,
	registry = {}, -- { { inst = <Instance>, map = { Propriete = "NomDeJeton" } }, ... }
	byInst = {},   -- inst -> son entree dans registry, pour pouvoir la retrouver
	order = { "Graphite", "Ambre", "Jade", "Indigo", "Rouille", "Papier" },
}

Skin.themes = {
	-- Achromatique : l'accent EST le blanc du texte. La couleur ne sert qu'aux etats.
	Graphite = {
		Background = Color3.fromRGB(15, 17, 19), Panel = Color3.fromRGB(23, 26, 29),
		PanelLight = Color3.fromRGB(29, 33, 38), Element = Color3.fromRGB(29, 33, 38),
		ElementHover = Color3.fromRGB(33, 37, 41), Stroke = Color3.fromRGB(38, 42, 47),
		StrokeStrong = Color3.fromRGB(51, 57, 64), Text = Color3.fromRGB(230, 233, 236),
		SubText = Color3.fromRGB(121, 128, 138), SubTextDim = Color3.fromRGB(91, 98, 107),
		Accent = Color3.fromRGB(230, 233, 236), AccentDim = Color3.fromRGB(185, 190, 196),
		OnAccent = Color3.fromRGB(15, 17, 19), Success = Color3.fromRGB(76, 175, 109),
		Warn = Color3.fromRGB(217, 164, 65), Danger = Color3.fromRGB(217, 88, 75),
	},
	-- Ambre sur graphite froid : couleur d'instrument, lisible sur toute scene.
	Ambre = {
		Background = Color3.fromRGB(20, 22, 26), Panel = Color3.fromRGB(26, 29, 34),
		PanelLight = Color3.fromRGB(32, 36, 41), Element = Color3.fromRGB(32, 36, 41),
		ElementHover = Color3.fromRGB(35, 39, 47), Stroke = Color3.fromRGB(43, 48, 56),
		StrokeStrong = Color3.fromRGB(56, 63, 73), Text = Color3.fromRGB(221, 226, 234),
		SubText = Color3.fromRGB(124, 133, 147), SubTextDim = Color3.fromRGB(93, 101, 114),
		Accent = Color3.fromRGB(232, 163, 61), AccentDim = Color3.fromRGB(184, 128, 45),
		OnAccent = Color3.fromRGB(20, 22, 26), Success = Color3.fromRGB(94, 210, 142),
		Warn = Color3.fromRGB(232, 163, 61), Danger = Color3.fromRGB(224, 104, 92),
	},
	-- Le plus calme : gris violace, vert sourd.
	Jade = {
		Background = Color3.fromRGB(23, 22, 28), Panel = Color3.fromRGB(30, 29, 37),
		PanelLight = Color3.fromRGB(37, 36, 46), Element = Color3.fromRGB(37, 36, 46),
		ElementHover = Color3.fromRGB(42, 41, 51), Stroke = Color3.fromRGB(44, 42, 53),
		StrokeStrong = Color3.fromRGB(59, 57, 71), Text = Color3.fromRGB(237, 234, 242),
		SubText = Color3.fromRGB(139, 135, 160), SubTextDim = Color3.fromRGB(106, 103, 128),
		Accent = Color3.fromRGB(92, 201, 167), AccentDim = Color3.fromRGB(70, 156, 129),
		OnAccent = Color3.fromRGB(15, 38, 32), Success = Color3.fromRGB(92, 201, 167),
		Warn = Color3.fromRGB(224, 177, 94), Danger = Color3.fromRGB(224, 122, 130),
	},
	-- Le plus proche de l'ancien menu, pour qui veut la continuite.
	Indigo = {
		Background = Color3.fromRGB(19, 19, 25), Panel = Color3.fromRGB(27, 27, 35),
		PanelLight = Color3.fromRGB(34, 34, 44), Element = Color3.fromRGB(34, 34, 44),
		ElementHover = Color3.fromRGB(38, 38, 47), Stroke = Color3.fromRGB(43, 43, 55),
		StrokeStrong = Color3.fromRGB(57, 57, 72), Text = Color3.fromRGB(233, 234, 242),
		SubText = Color3.fromRGB(130, 134, 160), SubTextDim = Color3.fromRGB(98, 102, 126),
		Accent = Color3.fromRGB(120, 141, 255), AccentDim = Color3.fromRGB(90, 107, 199),
		OnAccent = Color3.fromRGB(12, 14, 28), Success = Color3.fromRGB(90, 220, 130),
		Warn = Color3.fromRGB(230, 184, 79), Danger = Color3.fromRGB(235, 90, 90),
	},
	-- Le seul aux neutres chauds : des bruns, pas des gris.
	Rouille = {
		Background = Color3.fromRGB(22, 18, 15), Panel = Color3.fromRGB(30, 24, 21),
		PanelLight = Color3.fromRGB(37, 30, 26), Element = Color3.fromRGB(37, 30, 26),
		ElementHover = Color3.fromRGB(41, 32, 25), Stroke = Color3.fromRGB(47, 38, 32),
		StrokeStrong = Color3.fromRGB(63, 52, 44), Text = Color3.fromRGB(239, 231, 223),
		SubText = Color3.fromRGB(154, 139, 126), SubTextDim = Color3.fromRGB(118, 106, 95),
		Accent = Color3.fromRGB(210, 96, 58), AccentDim = Color3.fromRGB(162, 74, 44),
		OnAccent = Color3.fromRGB(24, 15, 10), Success = Color3.fromRGB(120, 179, 107),
		Warn = Color3.fromRGB(217, 164, 65), Danger = Color3.fromRGB(217, 88, 75),
	},
	-- Clair. Attention : eblouit sur une scene de jeu sombre, c'est assume.
	Papier = {
		Background = Color3.fromRGB(237, 238, 241), Panel = Color3.fromRGB(248, 249, 250),
		PanelLight = Color3.fromRGB(255, 255, 255), Element = Color3.fromRGB(255, 255, 255),
		ElementHover = Color3.fromRGB(228, 231, 235), Stroke = Color3.fromRGB(215, 218, 224),
		StrokeStrong = Color3.fromRGB(180, 186, 195), Text = Color3.fromRGB(21, 23, 28),
		SubText = Color3.fromRGB(102, 109, 120), SubTextDim = Color3.fromRGB(148, 154, 163),
		Accent = Color3.fromRGB(184, 65, 43), AccentDim = Color3.fromRGB(142, 49, 33),
		OnAccent = Color3.fromRGB(255, 255, 255), Success = Color3.fromRGB(46, 125, 82),
		Warn = Color3.fromRGB(168, 112, 26), Danger = Color3.fromRGB(184, 65, 43),
	},
}

-- Enregistre `inst` comme suivant le theme et applique les couleurs tout de
-- suite. map : { NomDePropriete = "NomDeJetonDansTheme" }. Renvoie inst pour
-- pouvoir s'ecrire en enveloppe autour de create(...).
--
-- Rappeler paint sur la MEME instance met a jour son mapping au lieu d'ajouter
-- une seconde entree : c'est ce qui permet a un controle de changer de jeton
-- selon son etat (un switch passe de "StrokeStrong" a "Accent" quand on
-- l'active) sans que le registre gonfle ni qu'un changement de theme le
-- repeigne avec son jeton d'origine.
function Skin.paint(inst, map)
	local entry = Skin.byInst[inst]
	if entry then
		for prop, token in pairs(map) do
			entry.map[prop] = token
		end
	else
		entry = { inst = inst, map = map }
		Skin.byInst[inst] = entry
		table.insert(Skin.registry, entry)
	end
	for prop, token in pairs(map) do
		inst[prop] = Theme[token]
	end
	return inst
end

function Skin.set(name)
	local theme = Skin.themes[name]
	if not theme then return end
	Skin.current = name
	for key, color in pairs(theme) do
		Theme[key] = color
	end
	-- Repeint tout le registre. Les instances detruites entre-temps (dropdown
	-- reconstruit par addTeleportSelector, toast expire...) font echouer
	-- l'affectation : on les sort du registre au passage plutot que de le
	-- laisser grossir indefiniment.
	local kept = {}
	for _, entry in ipairs(Skin.registry) do
		local ok = pcall(function()
			for prop, token in pairs(entry.map) do
				entry.inst[prop] = Theme[token]
			end
		end)
		if ok then
			table.insert(kept, entry)
		else
			Skin.byInst[entry.inst] = nil
		end
	end
	Skin.registry = kept
end

Skin.set(Prefs.MenuTheme or "Graphite")

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
	ShowCurrentSkill = false,
	EspScale = "x1",
	ChakraSenseNotifier = true,
	ChakraSenseNotifyInterval = 15,
	SpectatedNotifier = true,
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
	SelectedSellType = "Trinket",
	AutoSpectateOnClick = false,
	InventoryAutoSendEnabled = false,
	InventoryAutoSendInterval = 300,
	BuyQuantity = 1,
	AutoInfuseEnabled = false,
	AutoInfuseInterval = 15,
	AutoEquipWeaponEnabled = false,
	AutoBossEnabled = false,
	AutoBossPauseOnChakraSense = true,
	PanicHealEnabled = true,
	PanicHealThreshold = 30,
	NotifyLootEnabled = false,
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

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local ChatOverlayByPlayer = {}

-- Etat des features ESP/Environnement/Mouvement : regroupe dans UNE table
-- plutot que ~17 locals separes (limite des 200 registres - voir note en
-- tete de fichier). unloaded/lastConnOk restent des locals a part (lifecycle
-- du script, pas des reglages de feature).
local FeatureState = {
	enabled = Settings.EspEnabled,
	EspMode = Settings.EspMode, -- "Lua" (BillboardGui) ou "Python" (overlay externe via HTTP)
	EspMaxDistance = Settings.EspMaxDistance, -- studs, 0 = illimite
	ShowHealth = Settings.ShowHealth,
	ShowDistance = Settings.ShowDistance,
	ShowChakra = Settings.ShowChakra,
	ShowBlood = Settings.ShowBlood,
	ShowCurrentSkill = Settings.ShowCurrentSkill, -- Lua uniquement, pas envoye a l'overlay Python
	EspScale = Settings.EspScale, -- idem, Lua uniquement
	ChakraSenseNotifier = Settings.ChakraSenseNotifier,
	SpectatedNotifier = Settings.SpectatedNotifier,
	NoFogEnabled = Settings.NoFogEnabled,
	NoRainEnabled = Settings.NoRainEnabled,
	FullBrightEnabled = Settings.FullBrightEnabled,
	BrightnessLevel = Settings.BrightnessLevel,
	TimeChangerEnabled = Settings.TimeChangerEnabled,
	TimeOfDay = Settings.TimeOfDay,
	NoclipEnabled = Settings.NoclipEnabled,
	FlyEnabled = Settings.FlyEnabled,
	FlySpeed = Settings.FlySpeed,
}

local lastConnOk = nil -- nil = pas encore teste, true/false = dernier resultat request()
local unloaded = false

-- Connexions "longue duree" (Heartbeat, PlayerAdded/Removing, InputBegan...) a
-- couper explicitement au unload -- contrairement aux connexions par-joueur
-- (Health/MaxHealth), deja gerees par clearChatOverlay.
local Connections = {}
local function track(connection)
	table.insert(Connections, connection)
	return connection
end

-- Signal partage "quelqu'un a Chakra Sense actif la, maintenant" : mis a
-- jour par les deux watchers Chakra Sense (Cooldowns + CurrentSkill, tout en
-- bas du fichier) des qu'ils detectent quelque chose, INDEPENDAMMENT du
-- toggle ChakraSenseNotifier (qui ne controle que les notifs toast) - lu par
-- Auto Boss pour se mettre en pause. Grace period de quelques secondes car
-- CurrentSkill flickere (actif/inactif tres rapidement en usage reel,
-- confirme en live), sinon Auto Boss ferait des allers-retours en rafale.
local ChakraSenseThreat = { lastSeen = -math.huge }
local CHAKRA_SENSE_GRACE_SECONDS = 8
local function isChakraSenseThreatActive()
	return os.clock() - ChakraSenseThreat.lastSeen < CHAKRA_SENSE_GRACE_SECONDS
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
local NAME_HEIGHT = 18
local CHAKRA_COLOR = Color3.fromRGB(66, 177, 255)
local CURRENT_SKILL_COLOR = Color3.fromRGB(255, 165, 0)

-- Multiplicateur de taille de tout l'ESP Lua (billboard, StudsOffset,
-- textes) - PAS applique a l'overlay Python (sendOverlayPacket/
-- writeOverlayData plus bas n'y touchent pas du tout). Rebuild complet des
-- billboards au changement (voir FEATURE_CONTROLS.EspScale) plutot qu'un
-- rescale en place : plus simple et fiable, la creation dans
-- applyChatOverlay lit deja FeatureState.EspScale.
local ESP_SCALE_VALUES = { ["x1"] = 1, ["x1.25"] = 1.25, ["x1.5"] = 1.5, ["x2"] = 2, ["x3"] = 3 }
local ESP_SCALE_OPTIONS = { "x1", "x1.25", "x1.5", "x2", "x3" }
local function getEspScale()
	return ESP_SCALE_VALUES[FeatureState.EspScale] or 1
end

-- Empile les lignes actives (PV / Distance / Chakra / Blood) juste sous le
-- nom, dans cet ordre fixe, sans laisser de trou pour celles masquees ou
-- sans donnee (ex: Chakra/Blood introuvables sur un autre joueur si Backpack
-- ne replique pas). CurrentSkill (orange, ex: "Water Dragon", "Chakra Sense",
-- "Dynamic Entry") passe lui AU-DESSUS du nom quand present, lu directement
-- sur ReplicatedStorage.Settings.<joueur>.CurrentSkill (meme champ que
-- ChakraSenseThreat plus bas dans le fichier).
local function refreshPlayerLabel(data)
	local humanoid = data.humanoid
	if not humanoid then return end

	local scale = getEspScale()
	local rowHeight = ROW_HEIGHT * scale
	local nameHeight = NAME_HEIGHT * scale

	local skillText = ""
	if FeatureState.ShowCurrentSkill and data.player then
		local ok, currentSkill = pcall(function()
			return ReplicatedStorage.Settings[data.player.Name]:FindFirstChild("CurrentSkill")
		end)
		if ok and currentSkill and currentSkill.Value ~= "" then
			skillText = currentSkill.Value
		end
	end

	if skillText ~= "" then
		data.skillLabel.Text = skillText
		data.skillLabel.TextColor3 = CURRENT_SKILL_COLOR
		data.skillLabel.Position = UDim2.new(0, 0, 0, 0)
		data.skillLabel.Visible = true
		data.nameLabel.Position = UDim2.new(0, 0, 0, nameHeight)
	else
		data.skillLabel.Visible = false
		data.nameLabel.Position = UDim2.new(0, 0, 0, 0)
	end

	local y = (skillText ~= "" and nameHeight * 2 or nameHeight) -- sous le nameLabel (et le skillLabel si affiche)

	if FeatureState.ShowHealth then
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

	if FeatureState.ShowDistance then
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		local theirRoot = data.billboard.Adornee
		if myRoot and theirRoot then
			data.distanceLabel.Text = string.format("%dm", math.floor((myRoot.Position - theirRoot.Position).Magnitude))
			data.distanceLabel.TextColor3 = Theme.SubText
			data.distanceLabel.Position = UDim2.new(0, 0, 0, y)
			data.distanceLabel.Visible = true
			y = y + rowHeight
		else
			data.distanceLabel.Visible = false
		end
	else
		data.distanceLabel.Visible = false
	end

	if FeatureState.ShowChakra then
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
			y = y + rowHeight
		else
			data.chakraLabel.Visible = false
		end
	else
		data.chakraLabel.Visible = false
	end

	if FeatureState.ShowBlood then
		local backpack = data.player and data.player:FindFirstChild("Backpack")
		local bloodVal = backpack and backpack:FindFirstChild("blood")
		if bloodVal then
			data.bloodLabel.Text = string.format("%d%%", math.floor(bloodVal.Value))
			data.bloodLabel.TextColor3 = Theme.SubText
			data.bloodLabel.Position = UDim2.new(0, 0, 0, y)
			data.bloodLabel.Visible = true
			y = y + rowHeight
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

	-- Scale lu une fois a la creation : un changement de EspScale pendant que
	-- l'ESP tourne redeclenche applyChatOverlay pour tout le monde (voir
	-- FEATURE_CONTROLS.EspScale), donc pas besoin de recalculer ici a chaque
	-- refresh.
	local scale = getEspScale()
	local nameHeight = NAME_HEIGHT * scale
	local rowHeight = ROW_HEIGHT * scale

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LightChatOverlay_Health"
	billboard.Adornee = rootPart
	billboard.Size = UDim2.new(0, 140 * scale, 0, 90 * scale)
	billboard.StudsOffset = Vector3.new(0, 2.5 * scale, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = FeatureState.enabled and (FeatureState.EspMode == "Lua")
	billboard.Parent = rootPart

	local skillLabel = Instance.new("TextLabel")
	skillLabel.BackgroundTransparency = 1
	skillLabel.Size = UDim2.new(1, 0, 0, nameHeight)
	skillLabel.Font = Enum.Font.GothamBold
	skillLabel.TextSize = 13 * scale
	skillLabel.TextStrokeTransparency = 0.4
	skillLabel.Visible = false
	skillLabel.Parent = billboard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, nameHeight)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13 * scale
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
		label.Size = UDim2.new(1, 0, 0, rowHeight)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13 * scale
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
		skillLabel = skillLabel,
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

-- Vrai <=> ce joueur a deja un overlay VALIDE. Pas seulement "une entree
-- existe" : le billboard est parente au HumanoidRootPart, donc il est detruit
-- avec le personnage (mort, respawn, streaming). L'entree, elle, survit et
-- pointe alors dans le vide - d'ou la verification du parent ET de l'adornee,
-- qui doit etre le HumanoidRootPart COURANT.
local function hasLiveOverlay(player)
	local data = ChatOverlayByPlayer[player]
	if not (data and data.billboard and data.billboard.Parent) then return false end
	local character = player.Character
	return character ~= nil and data.billboard.Adornee == character:FindFirstChild("HumanoidRootPart")
end

local function onPlayerAdded(player)
	if player == LocalPlayer then return end

	track(player.CharacterAdded:Connect(function(character)
		if unloaded then return end
		-- Attendre les DEUX : un HumanoidRootPart present ne garantit pas que le
		-- Humanoid soit deja parente, et applyChatOverlay exige les deux (il
		-- abandonne sinon). L'ancien code n'attendait que le HumanoidRootPart
		-- puis laissait passer une seule frame.
		if not character:WaitForChild("HumanoidRootPart", 15) then return end
		if not character:WaitForChild("Humanoid", 5) then return end
		if unloaded then return end
		applyChatOverlay(player)
	end))

	if player.Character then applyChatOverlay(player) end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
track(Players.PlayerAdded:Connect(onPlayerAdded))
track(Players.PlayerRemoving:Connect(clearChatOverlay))

-- Rattrapage periodique : recree tout overlay manquant.
--
-- Les accroches evenementielles ci-dessus font chacune UNE tentative, et
-- echouent silencieusement si le personnage n'est pas pret au bon moment :
--   - `if player.Character then applyChatOverlay(player) end` s'execute au
--     chargement du script pour les joueurs deja la ; le Character peut exister
--     alors que le HumanoidRootPart n'est pas encore parente - applyChatOverlay
--     abandonne, et plus rien ne relancait.
--   - CharacterAdded abandonne si le personnage n'arrive pas dans le delai.
--   - Un personnage detruit puis restreame (joueur qui s'eloigne puis revient)
--     ne redeclenche pas CharacterAdded : le billboard est parti avec.
-- Constate en jeu : certains joueurs n'apparaissaient jamais dans l'ESP.
-- Plutot que d'essayer d'enumerer toutes les courses possibles, on reconcilie :
-- une passe par seconde, qui ne fait rien tant que tout va bien.
-- Pas de track() ici : il attend une connexion a Disconnect, pas un thread.
-- Le garde `unloaded` suffit a arreter la boucle (meme pattern que les autres
-- boucles de ce fichier, ex: le HUD des keybinds).
task.spawn(function()
	while not unloaded do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and not hasLiveOverlay(player) then
				local character = player.Character
				if character
					and character:FindFirstChild("HumanoidRootPart")
					and character:FindFirstChildWhichIsA("Humanoid")
				then
					applyChatOverlay(player)
				end
			end
		end
	end
end)

local function setEnabled(state)
	FeatureState.enabled = state
	for _, data in pairs(ChatOverlayByPlayer) do
		data.billboard.Enabled = FeatureState.enabled and (FeatureState.EspMode == "Lua")
	end
end

-- Visibilite par distance + rafraichissement du texte (PV/distance) pour l'ESP
-- Lua, une fois par frame. Ne tourne que si l'ESP est actif en mode Lua.
track(RunService.Heartbeat:Connect(function()
	if not (FeatureState.enabled and FeatureState.EspMode == "Lua") then return end

	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

	for _, data in pairs(ChatOverlayByPlayer) do
		local theirRoot = data.billboard.Adornee
		if theirRoot then
			local visible = true
			if FeatureState.EspMaxDistance > 0 and myRoot then
				visible = (myRoot.Position - theirRoot.Position).Magnitude <= FeatureState.EspMaxDistance
			end
			data.billboard.Enabled = visible
			if visible and (FeatureState.ShowDistance or FeatureState.ShowChakra or FeatureState.ShowBlood or FeatureState.ShowCurrentSkill) then
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
	if not (FeatureState.enabled and FeatureState.EspMode == "Python") then return end

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
				local withinRange = FeatureState.EspMaxDistance <= 0 or not dist or dist <= FeatureState.EspMaxDistance

				if withinRange then
					-- WorldToScreenPoint fait la projection cote Roblox (FOV, aspect ratio,
					-- clipping) : plus besoin de reimplementer la matrice cote overlay.
					local screenPoint, onScreen = camera:WorldToScreenPoint(rootPart.Position)
					if onScreen then
						local backpack = (FeatureState.ShowChakra or FeatureState.ShowBlood) and player:FindFirstChild("Backpack") or nil

						local chakra, maxChakra = nil, nil
						if FeatureState.ShowChakra and backpack then
							local chakraVal = backpack:FindFirstChild("chakra")
							local maxChakraVal = backpack:FindFirstChild("maxChakra")
							if chakraVal and maxChakraVal then
								chakra = math.floor(chakraVal.Value)
								maxChakra = math.floor(maxChakraVal.Value)
							end
						end

						local blood = nil
						if FeatureState.ShowBlood and backpack then
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
		enabled = FeatureState.enabled and (FeatureState.EspMode == "Python"),
		showHealth = FeatureState.ShowHealth,
		showDistance = FeatureState.ShowDistance,
		showChakra = FeatureState.ShowChakra,
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
	FeatureState.NoFogEnabled = state
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
	FeatureState.FullBrightEnabled = state
	if fullBrightConn then
		fullBrightConn:Disconnect()
		fullBrightConn = nil
	end
	if state then
		fullBrightConn = track(RunService.RenderStepped:Connect(function()
			Lighting.Brightness = FeatureState.BrightnessLevel
		end))
	else
		Lighting.Brightness = originalBrightness
	end
end

local timeChangerConn = nil
local function setTimeChanger(state)
	FeatureState.TimeChangerEnabled = state
	if timeChangerConn then
		timeChangerConn:Disconnect()
		timeChangerConn = nil
	end
	if state then
		timeChangerConn = track(RunService.RenderStepped:Connect(function()
			Lighting.ClockTime = CLOCK_TIMES[FeatureState.TimeOfDay] or CLOCK_TIMES.Morning
		end))
	end
end

-- Contrairement a l'original (funcs.noRain dans final_version_vapel.lua), qui
-- ne coupe jamais vraiment la boucle au toggle off (le flag "state" n'etait
-- teste qu'a l'activation) : ici noRainActive stoppe proprement la boucle.
local noRainActive = false
local function setNoRain(state)
	FeatureState.NoRainEnabled = state
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
	FeatureState.NoclipEnabled = state
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
		flyVelocity.Velocity = (cameraMoveVector + Vector3.new(0, verticalAxis, 0)) * FeatureState.FlySpeed
	end))
end

local function setFly(state)
	FeatureState.FlyEnabled = state
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
	if FeatureState.FlyEnabled then
		task.wait(0.5)
		if FeatureState.FlyEnabled and not unloaded then startFly() end
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
-- Toasts (notifications) - utilises par FeatureState.ChakraSenseNotifier
-- Chaque toast a une puce coloree (info/succes/erreur) et une barre de
-- progression en bas qui se vide en temps reel, pour visualiser le temps
-- restant avant disparition. Un nombre max de toasts visibles evite
-- l'accumulation sans fin quand une feature notifie en rafale (ex: Panic
-- Teleport, qui peut notifier plusieurs fois par seconde).
--------------------------------------------------------------------------------

-- Regroupees dans une seule table plutot que des locals separes : le fichier
-- entier est une seule fonction Luau (limite de 200 registres locaux), voir
-- la note en tete de fichier.
-- Token (et pas une Color3) : la couleur est lue dans Theme au moment ou le
-- toast est cree, donc elle suit le theme courant (voir Skin en tete de
-- fichier). Un toast dure quelques secondes, pas la peine de le repeindre en
-- cours de route s'il est a l'ecran pile au changement de theme.
local TOAST = {
	Width = 300,
	Kinds = {
		info = { Token = "Accent", Glyph = "●" },
		success = { Token = "Success", Glyph = "✓" },
		error = { Token = "Danger", Glyph = "✕" },
	},
}
local activeToasts = {} -- max 4 toasts visibles simultanement (voir notify)

local ToastHolder = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -13, 1, -13),
	Size = UDim2.new(0, TOAST.Width, 0, 460),
	BackgroundTransparency = 1,
}, ScreenGui)
create("UIListLayout", {
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, ToastHolder)

-- kind : "info" (defaut), "success" ou "error". duration : secondes avant
-- disparition (defaut 3.5).
local function notify(text, kind, duration)
	if unloaded then return end
	duration = duration or 3.5
	local style = TOAST.Kinds[kind] or TOAST.Kinds.info
	local styleColor = Theme[style.Token]

	-- Rafale de notifications : on vire tout de suite les plus anciennes en
	-- trop plutot que de laisser la pile grossir indefiniment.
	while #activeToasts >= 4 do
		local oldest = table.remove(activeToasts, 1)
		if oldest and oldest.Parent then oldest:Destroy() end
	end

	local toast = create("Frame", {
		Size = UDim2.new(0, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, ToastHolder)
	corner(toast, 4)
	local stroke = create("UIStroke", { Color = Theme.Stroke, Transparency = 1 }, toast)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11),
	}, toast)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, toast)

	table.insert(activeToasts, toast)

	local HeaderRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, toast)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, HeaderRow)

	local IconChip = create("Frame", {
		Size = UDim2.new(0, 20, 0, 20),
		BackgroundColor3 = styleColor,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, HeaderRow)
	corner(IconChip, 3)
	local iconStroke = create("UIStroke", { Color = styleColor, Transparency = 1 }, IconChip)
	local glyph = create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = style.Glyph,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = styleColor,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, IconChip)

	local label = create("TextLabel", {
		Size = UDim2.new(0, TOAST.Width - 22 - 20 - 10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		LayoutOrder = 2,
	}, HeaderRow)

	local ProgressTrack = create("Frame", {
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, toast)
	corner(ProgressTrack, 2)
	local ProgressFill = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = styleColor,
		BackgroundTransparency = 1,
	}, ProgressTrack)
	corner(ProgressFill, 2)

	tweenStyled(toast, { Size = UDim2.new(0, TOAST.Width, 0, 0), BackgroundTransparency = 0 }, 0.25)
	tween(stroke, { Transparency = 0.35 }, 0.2)
	tween(iconStroke, { Transparency = 0.4 }, 0.2)
	tween(IconChip, { BackgroundTransparency = 0.85 }, 0.2)
	tween(glyph, { TextTransparency = 0 }, 0.22)
	tween(label, { TextTransparency = 0 }, 0.22)
	tween(ProgressTrack, { BackgroundTransparency = 0 }, 0.2)
	tween(ProgressFill, { BackgroundTransparency = 0.15 }, 0.2)
	-- Linear et duree exacte : la barre reflete le temps restant reel, pas un effet decoratif.
	TweenService:Create(ProgressFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 1, 0) }):Play()

	task.delay(duration, function()
		if not toast.Parent then return end
		local index = table.find(activeToasts, toast)
		if index then table.remove(activeToasts, index) end
		tween(toast, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0) }, 0.18)
		tween(stroke, { Transparency = 1 }, 0.18)
		tween(label, { TextTransparency = 1 }, 0.12)
		tween(glyph, { TextTransparency = 1 }, 0.12)
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
	notify("Safe Spot enregistre.", "success")
end

local function teleportToSafeSpot()
	local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	if not SafeSpotPosition then
		notify("Aucun Safe Spot enregistre.", "error")
		return
	end
	-- Ancrage bref pendant le saut de CFrame : un simple rootPart.CFrame = ...
	-- sur un personnage sous controle physique normal donne un glissement
	-- visible (confirme en jeu, notamment enchaine juste apres l'auto loot).
	-- Ancrer bloque completement la physique le temps du saut.
	local wasAnchored = rootPart.Anchored
	rootPart.Anchored = true
	rootPart.CFrame = CFrame.new(SafeSpotPosition)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	task.wait()
	rootPart.Anchored = wasAnchored
end

--------------------------------------------------------------------------------
-- Teleport To Player : liste dynamique (rafraichie a chaque PlayerAdded/Removing)
-- des autres joueurs presents sur le serveur.
--------------------------------------------------------------------------------

local function teleportToPlayer(targetPlayer)
	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		notify("Personnage introuvable.", "error")
		return
	end
	if not targetRoot then
		notify(targetPlayer.Name .. " n'a pas de personnage charge.", "error")
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
		notify("PNJ introuvable.", "error")
		return
	end
	local rootPart = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local main = getNpcTeleportPart(npc)
	if not main then
		notify("Impossible de localiser ce PNJ.", "error")
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
		notify("Aucun Chakra Point selectionne.", "error")
		return
	end

	rootPart.CFrame = CFrame.new(pos - Vector3.new(0, 0, 5), pos)
end

--------------------------------------------------------------------------------
-- Inventaire : recupere l'inventaire (Loadout) + la hotbar + la lifeforce du
-- joueur local, formate en texte, et envoie ca a un webhook Discord.
-- Automatique uniquement (toggle + intervalle reglables, page Auto), plus de
-- bouton manuel.
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
		notify("request() indisponible : impossible d'envoyer au webhook.", "error")
		return
	end
	if not Prefs.InventoryWebhookUrl or Prefs.InventoryWebhookUrl == "" then
		notify("Aucun webhook configure (page Settings).", "error")
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
		notify("Inventaire envoye au webhook Discord.", "success")
	else
		notify("Erreur : envoi au webhook Discord a echoue.", "error")
	end
end

-- Envoi automatique en arriere-plan (page Auto : toggle + intervalle
-- reglables). Tick chaque seconde plutot que task.wait(intervalle) pour
-- reagir tout de suite si le toggle ou l'intervalle changent en cours de
-- route, sans avoir a attendre la fin du cycle precedent.
task.spawn(function()
	local lastSend = 0
	while not unloaded do
		task.wait(1)
		if unloaded then break end
		if Settings.InventoryAutoSendEnabled and (os.clock() - lastSend) >= Settings.InventoryAutoSendInterval then
			lastSend = os.clock()
			pcall(sendInventoryToWebhook)
		end
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
			notify("Dump copie dans le presse-papier.", "success")
		else
			notify("Erreur : setclipboard a echoue. Voir la console (F9).", "error")
			print(text)
		end
	else
		notify("setclipboard indisponible sur cet executeur. Voir la console (F9).", "error")
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
		notify("InventoryScroll introuvable.", "error")
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
		notify("Aucun InvSlot rempli trouve. Ouvre ton inventaire en jeu d'abord.", "error")
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
			notify("AFK AgeUp active : teleportation vers une Safe Place.", "success")

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
					notify("Panic Teleport : PV recuperes, arret.", "success")
					return
				end
				if os.clock() - lastPanicTeleport >= PANIC_TELEPORT_INTERVAL then
					teleportToNextSafePlace()
					lastPanicTeleport = os.clock()
				end
			elseif humanoid.Health < PANIC_HP_LOW then
				panicking = true
				notify("Panic Teleport : PV bas, teleportation d'urgence.", "error")
				teleportToNextSafePlace()
				lastPanicTeleport = os.clock()
			end
		end))
	end
end

local WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT = 420, 340
local WINDOW_MAX_WIDTH, WINDOW_MAX_HEIGHT = 900, 700

-- Chassis "Compact" : barre de titre fine, onglets en bande horizontale sous
-- la barre de titre (plus de colonne laterale : sa largeur revient au
-- contenu), et barre d'etat en bas. Regroupes dans une table plutot qu'en
-- constantes separees (limite des 200 registres - voir la note en tete de
-- fichier) ; MenuChrome recoit plus bas les instances qu'il faut retrouver
-- depuis ailleurs (recherche, barre d'etat).
local MenuChrome = { TopBar = 44, Tabs = 34, Status = 24, bands = {}, rows = {}, blocks = {}, drops = {} }
local TOPBAR_HEIGHT = MenuChrome.TopBar

-- Taille "cible" (celle vers laquelle on anime a l'ouverture, et que le
-- redimensionnement met a jour) ; separee de Main.Size car cette derniere
-- vaut temporairement (0,0,0,0) pendant l'animation d'ouverture/fermeture.
local targetSize = UDim2.new(
	0, math.clamp(Prefs.WindowWidth, WINDOW_MIN_WIDTH, WINDOW_MAX_WIDTH),
	0, math.clamp(Prefs.WindowHeight, WINDOW_MIN_HEIGHT, WINDOW_MAX_HEIGHT)
)

-- Il y avait ici un halo (Frame teinte accent) + une ombre (Frame noire),
-- tous deux plus grands que la fenetre et poses derriere pour donner un effet
-- "flottant". Retire : Roblox ne sait pas flouter un Frame, donc c'etait deux
-- rectangles nets aux bords francs autour de la fenetre - ca se voyait comme
-- un halo sale plutot que comme une ombre. Le contour de 1 px sur Main suffit
-- a detacher la fenetre du jeu.

local Main = Skin.paint(create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = targetSize,
	Visible = false,
	Active = true,
	ZIndex = 1,
}, ScreenGui), { BackgroundColor3 = "Background" })
corner(Main, 5)
Skin.paint(create("UIStroke", { Transparency = 0 }, Main), { Color = "Stroke" })

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

-- Animation d'ouverture/fermeture : leger zoom (96% -> 100%, aucun rebond),
-- plutot que l'ancien pop depuis une taille nulle.
local WINDOW_OPEN_SCALE = 0.96

local function scaledSize(size, factor)
	return UDim2.new(0, size.X.Offset * factor, 0, size.Y.Offset * factor)
end

local function openWindow()
	Main.Visible = true
	Main.Size = scaledSize(targetSize, WINDOW_OPEN_SCALE)

	tweenStyled(Main, { Size = targetSize }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	playLoadingIntro()
end

local function closeWindow()
	local closeTween = TweenService:Create(
		Main,
		TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Size = scaledSize(targetSize, WINDOW_OPEN_SCALE) }
	)
	closeTween.Completed:Connect(function()
		Main.Visible = false
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
	TextSize = 14,
	TextColor3 = Theme.SubText,
	ZIndex = 26,
}, InjectionOverlay)

local function playInjectionSplash()
	InjectionOverlay.Visible = true
	InjectionOverlay.BackgroundTransparency = 0
	ProgressBarFill.Size = UDim2.new(0, 0, 1, 0)
	ProgressLabel.Text = "Chargement... 0%"

	Main.Visible = true
	Main.Size = scaledSize(targetSize, WINDOW_OPEN_SCALE)
	tweenStyled(Main, { Size = targetSize }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

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

-- Fond de la barre de titre : un ton au-dessus du fond de fenetre, comme la
-- bande d'onglets et la barre d'etat - les trois cadres du chassis se lisent
-- ainsi comme un meme calque autour du contenu.
Skin.paint(TopBar, { BackgroundColor3 = "Panel" })
TopBar.BackgroundTransparency = 0
Skin.paint(create("Frame", { -- filet de separation (pas de UIStroke : il ferait le tour)
	Position = UDim2.new(0, 0, 1, -1),
	Size = UDim2.new(1, 0, 0, 1),
	BorderSizePixel = 0,
}, TopBar), { BackgroundColor3 = "Stroke" })

Skin.paint(create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 10, 0, 0),
	Size = UDim2.new(0, 96, 1, 0),
	Text = "Von Client",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TopBar), { TextColor3 = "Text" })

Skin.paint(create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 106, 0, 0),
	Size = UDim2.new(0, 44, 1, 0),
	Text = "v2.4",
	Font = Enum.Font.Code,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TopBar), { TextColor3 = "SubTextDim" })

-- Recherche : filtre les lignes de la page courante par leur libelle, et
-- masque les sections qui n'ont plus rien a montrer. Le filtrage lui-meme vit
-- dans MenuChrome.applyFilter (defini apres addSection, qui enregistre les
-- lignes au fur et a mesure).
local SearchBar = Skin.paint(create("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -52, 0.5, 0),
	Size = UDim2.new(0, 190, 0, 26),
}, TopBar), { BackgroundColor3 = "Background" })
corner(SearchBar, 3)
Skin.paint(create("UIStroke", { Transparency = 0 }, SearchBar), { Color = "Stroke" })

MenuChrome.Search = Skin.paint(create("TextBox", {
	Size = UDim2.new(1, -18, 1, 0),
	Position = UDim2.new(0, 9, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	PlaceholderText = "Rechercher un reglage",
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
}, SearchBar), { TextColor3 = "Text", PlaceholderColor3 = "SubTextDim" })

local CloseButton = Skin.paint(create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.new(0, 30, 0, 26),
	BackgroundTransparency = 1,
	Text = "✕",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	AutoButtonColor = false,
}, TopBar), { TextColor3 = "SubText", BackgroundColor3 = "ElementHover" })
corner(CloseButton, 3)
CloseButton.MouseButton1Click:Connect(closeWindow)
CloseButton.MouseEnter:Connect(function()
	CloseButton.BackgroundTransparency = 0
	tween(CloseButton, { TextColor3 = Theme.Text }, 0.1)
end)
CloseButton.MouseLeave:Connect(function()
	CloseButton.BackgroundTransparency = 1
	tween(CloseButton, { TextColor3 = Theme.SubText }, 0.1)
end)

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
local ResizeHandle = Skin.paint(create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -4, 1, -4),
	Size = UDim2.new(0, 10, 0, 10),
	BackgroundTransparency = 0.4,
	Active = true,
	ZIndex = 10, -- cree avant TabStrip/PagesHolder : sans ca, ces derniers (meme ZIndex par defaut) le recouvriraient
}, Main), { BackgroundColor3 = "StrokeStrong" })
corner(ResizeHandle, 2)
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

-- Bande d'onglets horizontale (remplace l'ancienne colonne laterale de 150 px,
-- dont la largeur revient maintenant au contenu). L'onglet actif est marque par
-- un trait de 2 px sous le libelle, pas par un fond : moins de bruit visuel a
-- six onglets cote a cote.
local TabStrip = Skin.paint(create("Frame", {
	Position = UDim2.new(0, 0, 0, MenuChrome.TopBar),
	Size = UDim2.new(1, 0, 0, MenuChrome.Tabs),
}, Main), { BackgroundColor3 = "Panel" })
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, TabStrip)
create("UIPadding", { PaddingLeft = UDim.new(0, 8) }, TabStrip)

-- Filet sous la bande d'onglets, pose dans Main et PAS dans TabStrip : ce
-- dernier a un UIListLayout, qui rangerait le filet comme un onglet de plus et
-- casserait la rangee.
Skin.paint(create("Frame", {
	Position = UDim2.new(0, 0, 0, MenuChrome.TopBar + MenuChrome.Tabs - 1),
	Size = UDim2.new(1, 0, 0, 1),
	BorderSizePixel = 0,
	ZIndex = 2,
}, Main), { BackgroundColor3 = "Stroke" })

-- Barre d'etat : ce qu'on veut voir sans ouvrir de page (boss suivi et ses PV,
-- liaison a l'overlay Python, config chargee, touche du menu). Remplie par
-- MenuChrome.setStatus, appelee depuis Auto Boss et le chargement de config.
local StatusBar = Skin.paint(create("Frame", {
	Position = UDim2.new(0, 0, 1, -MenuChrome.Status),
	Size = UDim2.new(1, 0, 0, MenuChrome.Status),
}, Main), { BackgroundColor3 = "Panel" })
Skin.paint(create("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	BorderSizePixel = 0,
}, StatusBar), { BackgroundColor3 = "Stroke" })

MenuChrome.StatusLeft = Skin.paint(create("TextLabel", {
	Position = UDim2.new(0, 10, 0, 0),
	Size = UDim2.new(0.6, -10, 1, 0),
	BackgroundTransparency = 1,
	Text = "BOSS --",
	Font = Enum.Font.Code,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
}, StatusBar), { TextColor3 = "SubText" })

-- Decalee de 20 px de plus vers la gauche que la moitie gauche : la poignee de
-- redimensionnement occupe le coin en bas a droite, juste au-dessus.
MenuChrome.StatusRight = Skin.paint(create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -22, 0, 0),
	Size = UDim2.new(0.4, -22, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.Code,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
}, StatusBar), { TextColor3 = "SubTextDim" })

-- boss/hp peuvent etre nil (aucun boss suivi) : la moitie gauche retombe alors
-- sur "BOSS --". La moitie droite (config + touche menu) ne bouge qu'au
-- chargement d'une config ou au rebind, donc elle est reconstruite ici a chaque
-- appel plutot que d'etre pilotee separement.
function MenuChrome.setStatus(boss, hp, maxHp)
	if boss and hp and maxHp then
		MenuChrome.StatusLeft.Text = string.format("BOSS %s  %d/%d", string.upper(boss), hp, maxHp)
	elseif boss then
		MenuChrome.StatusLeft.Text = "BOSS " .. string.upper(boss)
	else
		MenuChrome.StatusLeft.Text = "BOSS --"
	end
end

function MenuChrome.refreshRight()
	MenuChrome.StatusRight.Text = string.format(
		"CONFIG %s   MENU %s",
		Meta.defaultConfig or "aucune",
		MENU_TOGGLE_KEY and MENU_TOGGLE_KEY.Name or "--"
	)
end

-- Pas de ClipsDescendants ici : les pages sont des ScrollingFrame, qui
-- decoupent deja leur propre contenu. En ajouter un a ce niveau tronquait les
-- listes de selecteurs ouvertes pres du bas de page (voir buildDropList, dont
-- le panneau est desormais parente a Main pour cette raison).
local PagesHolder = create("Frame", {
	Position = UDim2.new(0, 0, 0, MenuChrome.TopBar + MenuChrome.Tabs),
	Size = UDim2.new(1, 0, 1, -(MenuChrome.TopBar + MenuChrome.Tabs + MenuChrome.Status)),
	BackgroundTransparency = 1,
}, Main)

local pages, sidebarButtons, currentPage = {}, {}, nil

local function selectPage(name)
	-- Les panneaux de selecteurs flottent dans PagesHolder, pas dans leur page :
	-- un panneau laisse ouvert resterait visible par-dessus le nouvel onglet.
	if MenuChrome.closeDrops then MenuChrome.closeDrops() end

	if currentPage then
		local prev = sidebarButtons[currentPage]
		prev.Label.TextColor3 = Theme.SubText
		prev.Underline.BackgroundTransparency = 1
		pages[currentPage].Visible = false
	end

	local current = sidebarButtons[name]
	pages[name].Visible = true
	current.Label.TextColor3 = Theme.Accent
	current.Underline.BackgroundColor3 = Theme.Accent
	current.Underline.BackgroundTransparency = 0
	currentPage = name

	-- La page vient de devenir visible : au prochain pas de rendu, Roblox aura
	-- calcule la hauteur de ses cards et MenuChrome.balance pourra les repartir
	-- entre les deux colonnes (voir sa note). Ne fait rien aux appels suivants.
	if MenuChrome.balance then
		task.defer(MenuChrome.balance, pages[name])
	end
	-- La recherche est globale au menu mais s'applique page par page : en
	-- changeant d'onglet, on rejoue le filtre sur la nouvelle page (sinon on
	-- arrive sur une page complete alors que le champ est encore rempli).
	if MenuChrome.applyFilter then MenuChrome.applyFilter() end
end

-- accentColor n'est plus utilise (une couleur par categorie faisait six accents
-- concurrents dans une bande horizontale) : l'onglet actif prend simplement
-- l'accent du theme. Le parametre reste accepte pour ne pas avoir a toucher les
-- six appels createCategory plus bas.
local function createCategory(name, accentColor)
	-- Largeur estimee d'apres le nombre de caracteres (Gotham Medium 14 fait
	-- ~8 px/caractere) : les six onglets doivent tenir cote a cote meme a la
	-- largeur MINIMALE de fenetre (420), sinon les derniers sont coupes.
	-- Total a 8/caractere + 18 de marge : ~388 px, plus les 8 px de retrait a
	-- gauche - ca passe tout juste, ne pas augmenter sans relever WINDOW_MIN_WIDTH.
	local Button = create("TextButton", {
		Size = UDim2.new(0, 8 * #name + 18, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, TabStrip)

	local Label = Skin.paint(create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
	}, Button), { TextColor3 = "SubText" })

	local Underline = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, -10, 0, 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, Button)

	Button.MouseButton1Click:Connect(function() selectPage(name) end)
	Button.MouseEnter:Connect(function()
		if currentPage ~= name then tween(Label, { TextColor3 = Theme.Text }, 0.1) end
	end)
	Button.MouseLeave:Connect(function()
		if currentPage ~= name then tween(Label, { TextColor3 = Theme.SubText }, 0.1) end
	end)

	local Page = Skin.paint(create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, PagesHolder), { ScrollBarImageColor3 = "Stroke" })
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, Page)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	}, Page)

	-- Le panneau d'un selecteur ouvert est positionne une fois, en coordonnees
	-- fenetre : il ne suit pas la page qui defile. Plutot que de le repositionner
	-- a chaque frame, on referme les listes ouvertes des que la page bouge.
	Page:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if MenuChrome.closeDrops then MenuChrome.closeDrops() end
	end)

	pages[name] = Page
	sidebarButtons[name] = { Button = Button, Label = Label, Underline = Underline }
	-- Le contenu s'organise en blocs a deux colonnes (voir addSection) : on suit
	-- ici, PAR PAGE, le bloc en cours de remplissage (une section pleine largeur
	-- le referme). Indexe par l'instance Page parce que c'est ce que addSection
	-- recoit, pas le nom de la categorie.
	MenuChrome.bands[Page] = { block = nil }
	MenuChrome.rows[Page] = {}
	MenuChrome.blocks[Page] = {} -- blocs a deux colonnes, reequilibres au premier affichage
	return Page
end

-- Tooltip generique (survol) : un seul Frame partage plutot qu'un pave de
-- texte fixe sous chaque controle (menu trop charge sinon) - repositionne et
-- rempli au MouseEnter de la cible, cache au MouseLeave. Bascule a gauche du
-- curseur si l'affichage a droite deborderait de l'ecran.
local Tooltip = Skin.paint(create("Frame", {
	Size = UDim2.new(0, 220, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 100,
}, ScreenGui), { BackgroundColor3 = "Panel" })
corner(Tooltip, 4)
Skin.paint(create("UIStroke", { Transparency = 0 }, Tooltip), { Color = "StrokeStrong" })
create("UIPadding", {
	PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9),
	PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
}, Tooltip)
local TooltipLabel = Skin.paint(create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Text = "",
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 101,
}, Tooltip), { TextColor3 = "SubText" })

-- target : n'importe quel GuiObject (Row/Holder/Button retourne par
-- addToggleRow/addDropdownRow/addButtonRow/addSliderRow...).
local function attachTooltip(target, text)
	target.MouseEnter:Connect(function(x, y)
		TooltipLabel.Text = text
		local posX = x + 16
		if posX + 220 > ScreenGui.AbsoluteSize.X then
			posX = x - 220 - 16
		end
		Tooltip.Position = UDim2.new(0, posX, 0, y - 10)
		Tooltip.Visible = true
	end)
	target.MouseLeave:Connect(function()
		Tooltip.Visible = false
	end)
end

-- Card compacte : titre en petites capitales sous un filet, contenu dessous.
-- Le lisere d'accent plein-hauteur a saute - avec deux cards cote a cote il se
-- repetait trop et devenait du bruit.
--
-- Mise en page en DEUX COLONNES : Roblox n'a pas de grille qui accepte des
-- enfants a hauteur automatique (UIGridLayout impose une taille de cellule
-- fixe), donc on empile des "rangees" (bands) dans le UIListLayout vertical de
-- la page, chacune contenant au plus deux cards a 50 %. Une section large
-- (wide=true, ex: Auto Boss) ferme la rangee en cours et prend toute la largeur.
local function addSection(page, title, wide)
	local band = MenuChrome.bands[page]

	local host
	if wide or not band then
		-- Pleine largeur : la card est posee directement dans la page, et le
		-- bloc a deux colonnes en cours est referme pour que le suivant reparte
		-- proprement a gauche.
		if band then band.block = nil end
		host = page
	else
		-- VRAIES colonnes, pas des rangees de deux : chaque colonne est un Frame
		-- qui empile ses cards verticalement. Avec des rangees, une card haute
		-- (celles qui contiennent un selecteur) imposait sa hauteur a sa voisine
		-- et creusait un grand vide sous la plus courte - c'est exactement ce
		-- qu'on voyait sous "Panic Teleport" a cote d'"Auto Infuse". Ici la card
		-- suivante de la colonne remonte se coller a la precedente.
		if not band.block then
			local Block = create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, page)
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				VerticalAlignment = Enum.VerticalAlignment.Top,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, Block)

			band.block = { frame = Block, cols = {}, cards = {} }
			for i = 1, 2 do
				band.block.cols[i] = create("Frame", {
					Size = UDim2.new(0.5, -4, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = i,
				}, Block)
				create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, band.block.cols[i])
			end
			table.insert(MenuChrome.blocks[page], band.block)
		end
		-- Toutes les cards atterrissent d'abord dans la colonne 1 : la
		-- repartition definitive est faite par MenuChrome.balance au premier
		-- affichage de la page, quand les hauteurs reelles sont connues.
		-- Les repartir ici en alternance serait a l'aveugle - c'est ce qui
		-- laissait une colonne courte a cote d'une card haute (Auto Infuse).
		host = band.block.cols[1]
	end

	local Card = Skin.paint(create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, host), { BackgroundColor3 = "Panel" })
	corner(Card, 4)
	Skin.paint(create("UIStroke", { Transparency = 0 }, Card), { Color = "Stroke" })

	if band and band.block and not wide then
		table.insert(band.block.cards, Card)
	end

	local Inner = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, Card)
	create("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder }, Inner)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	}, Inner)

	-- Casse normale en Gotham, pas des capitales en chasse fixe : "ENVOI AUTO
	-- INVENTAIRE" faisait log systeme, et les capitales tiennent mal l'accentuation
	-- francaise. La chasse fixe reste reservee aux valeurs (chiffres, touches).
	local TitleLabel = Skin.paint(create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 19),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
	}, Inner), { TextColor3 = "SubText" })

	Skin.paint(create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		LayoutOrder = 1,
	}, Inner), { BackgroundColor3 = "Stroke" })

	local Content = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, Inner)
	create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, Content)
	create("UIPadding", { PaddingTop = UDim.new(0, 6) }, Content)

	-- Enregistre la card pour la recherche : chaque ligne creee dedans se
	-- declare via MenuChrome.track (appele par les add*Row), et la card se
	-- masque toute seule quand plus aucune de ses lignes ne correspond.
	table.insert(MenuChrome.rows[page], { card = Card, title = string.lower(title), rows = {} })
	MenuChrome.currentSection = MenuChrome.rows[page][#MenuChrome.rows[page]]

	return Content
end

-- Declare une ligne aupres de la recherche. `text` est le libelle affiche :
-- c'est lui qu'on compare a la requete. Appele par chaque add*Row juste apres
-- avoir cree sa ligne, donc rattache a la derniere section ouverte.
function MenuChrome.track(inst, text)
	local section = MenuChrome.currentSection
	if section then
		table.insert(section.rows, { inst = inst, text = string.lower(text or "") })
	end
	return inst
end

-- Filtre la page visible : masque les lignes qui ne correspondent pas, puis
-- les cards devenues vides. Un titre de section qui correspond garde toutes
-- ses lignes (chercher "esp" doit montrer la section ESP entiere).
function MenuChrome.applyFilter()
	if not currentPage then return end
	local query = string.lower(MenuChrome.Search.Text)
	for _, section in ipairs(MenuChrome.rows[pages[currentPage]] or {}) do
		local titleHit = query == "" or string.find(section.title, query, 1, true) ~= nil
		local kept = 0
		for _, row in ipairs(section.rows) do
			local hit = titleHit or string.find(row.text, query, 1, true) ~= nil
			row.inst.Visible = hit
			if hit then kept = kept + 1 end
		end
		-- Recherche vide => on ne masque JAMAIS une card. Sans ce garde-fou,
		-- une section dont le contenu n'est pas indexe (construit avec create()
		-- au lieu d'un add*Row, ex: le bouton Decharger) compte zero ligne et
		-- disparaissait des l'ouverture du menu.
		section.card.Visible = query == "" or titleHit or kept > 0
	end
end

MenuChrome.Search:GetPropertyChangedSignal("Text"):Connect(MenuChrome.applyFilter)

-- Repartit les cards d'une page entre les deux colonnes pour que celles-ci
-- finissent aussi hautes que possible - sinon une card haute (celle qui contient
-- un selecteur, ex: Auto Infuse) fait deborder sa colonne et laisse un grand
-- vide en bas de l'autre.
--
-- Appelee au PREMIER affichage de la page, jamais a la construction : c'est le
-- seul moment ou AbsoluteSize est renseignee, donc le seul moment ou on connait
-- la hauteur reelle des cards. Toutes les combinaisons sont essayees (2^n) pour
-- prendre la meilleure : n depasse rarement 8 par page, et l'ordre de
-- declaration est preserve a l'interieur de chaque colonne (on ne fait que
-- choisir DANS QUELLE colonne va chaque card, pas les reordonner).
function MenuChrome.balance(page, attempt)
	local blocks = MenuChrome.blocks[page]
	if not blocks then return end

	-- AbsoluteSize n'est renseignee qu'une fois la fenetre reellement affichee
	-- et la mise en page calculee. Si on tombe trop tot (menu encore masque par
	-- la splash de chargement), toutes les hauteurs valent 0 : on retente plutot
	-- que de repartir n'importe comment, et on abandonne au bout de ~2 s.
	attempt = (attempt or 0) + 1
	for _, block in ipairs(blocks) do
		for _, card in ipairs(block.cards) do
			if card.AbsoluteSize.Y <= 0 then
				if attempt < 20 then task.delay(0.1, MenuChrome.balance, page, attempt) end
				return
			end
		end
	end

	MenuChrome.blocks[page] = nil -- mesure valide : une seule fois par page

	for _, block in ipairs(blocks) do
		local cards = block.cards
		local count = #cards
		if count >= 2 and count <= 16 then
			local heights = {}
			for i, card in ipairs(cards) do
				heights[i] = card.AbsoluteSize.Y + 8 -- + l'ecart entre deux cards
			end

			local bestMask, bestScore = 0, math.huge
			for mask = 0, (2 ^ count) - 1 do
				local left, right = 0, 0
				for i = 1, count do
					-- bit a 1 => colonne de gauche
					if math.floor(mask / (2 ^ (i - 1))) % 2 == 1 then
						left = left + heights[i]
					else
						right = right + heights[i]
					end
				end
				local score = math.max(left, right)
				if score < bestScore then
					bestMask, bestScore = mask, score
				end
			end

			for i, card in ipairs(cards) do
				local goesLeft = math.floor(bestMask / (2 ^ (i - 1))) % 2 == 1
				card.Parent = block.cols[goesLeft and 1 or 2]
				card.LayoutOrder = i -- conserve l'ordre de declaration dans la colonne
			end
		end
	end
end

-- Hauteur commune a toutes les lignes de reglage : ce qui donne son rythme
-- vertical a la page. 32 px au lieu de 38 - assez pour respirer avec du texte
-- a 14, tout en restant plus dense qu'avant.
local ROW_H = 34

local function addToggleRow(content, text, default, onChange)
	local state = default or false

	local Row = MenuChrome.track(create("Frame", { Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 }, content), text)
	local Label = Skin.paint(create("TextLabel", {
		Size = UDim2.new(1, -46, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Row), { TextColor3 = "Text" })

	local ON_POSITION, OFF_POSITION = UDim2.new(1, -17, 0.5, -7), UDim2.new(0, 3, 0.5, -7)

	local Switch = Skin.paint(create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 36, 0, 20),
	}, Row), { BackgroundColor3 = state and "Accent" or "StrokeStrong" })
	corner(Switch, 10)

	local Knob = Skin.paint(create("Frame", {
		Size = UDim2.new(0, 14, 0, 14),
		Position = state and ON_POSITION or OFF_POSITION,
	}, Switch), { BackgroundColor3 = state and "OnAccent" or "SubText" })
	corner(Knob, 7)

	local Click = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "" }, Switch)

	local function set(newState)
		state = newState
		-- Reecrit l'entree de registre plutot que la couleur seule : sans ca un
		-- changement de theme repeindrait le switch avec le jeton d'origine
		-- (celui capture a la creation) et perdrait l'etat courant.
		Skin.paint(Switch, { BackgroundColor3 = state and "Accent" or "StrokeStrong" })
		Skin.paint(Knob, { BackgroundColor3 = state and "OnAccent" or "SubText" })
		tweenStyled(Knob, { Position = state and ON_POSITION or OFF_POSITION }, 0.2)
		if onChange then onChange(state) end
	end
	Click.MouseButton1Click:Connect(function() set(not state) end)

	-- Row/Label exposes : utilises par KeybindTool pour inserer le petit carre
	-- de rebind a gauche du texte, sans que les toggles sans keybind n'aient a
	-- en payer le cout visuel.
	return { Set = set, Get = function() return state end, Row = Row, Label = Label }
end

-- Metriques communes aux deux selecteurs.
--
-- La liste ne se deplie PAS en place : elle flotte au-dessus du contenu (voir
-- buildDropList). En place, elle faisait grandir sa card, donc sa colonne, donc
-- creusait un grand vide en bas de l'autre colonne des qu'on ouvrait un
-- selecteur - c'est ce qu'on voyait avec "Gemmes" ouvert a cote d'une colonne
-- gauche courte. En flottant, ouvrir un selecteur ne bouge plus rien.
--
-- DROP_H vaut ROW_H : un selecteur occupe exactement la meme hauteur qu'un
-- toggle ou un slider, sinon il casse le rythme vertical de la card.
-- DROP_MAX = 9 : les deux listes a cocher (Boss 8, Gemmes 9) tiennent alors en
-- entier sans avoir a defiler, ce qui est justement le cas ou on veut tout voir.
local DROP_H, OPT_H, DROP_MAX = ROW_H, 29, 9 -- DROP_MAX : options visibles avant defilement
local DROP_BOX = 160 -- largeur de la boite de valeur, a droite
local DROP_SEARCH_FROM = 8 -- a partir de combien d'options on ajoute une recherche
local DROP_SEARCH_H = 28

-- En-tete commun, construit comme les autres lignes : libelle nu a gauche
-- (meme couleur, meme taille qu'un toggle), et une boite compacte a droite
-- avec la valeur et le chevron. Avant, tout l'en-tete etait une grosse boite
-- pleine largeur : le selecteur ressortait comme un corps etranger au milieu
-- de lignes nues. Renvoie Holder, bouton, label de valeur et chevron.
local function buildDropHead(content, text, valueText)
	local Holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, DROP_H),
		BackgroundTransparency = 1,
	}, content)

	local MainButton = create("TextButton", {
		Size = UDim2.new(1, 0, 0, DROP_H),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, Holder)

	Skin.paint(create("TextLabel", {
		Size = UDim2.new(1, -(DROP_BOX + 10), 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, MainButton), { TextColor3 = "Text" })

	local Box = Skin.paint(create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, DROP_BOX, 0, 26),
	}, MainButton), { BackgroundColor3 = "Element" })
	corner(Box, 3)
	Skin.paint(create("UIStroke", { Transparency = 0 }, Box), { Color = "StrokeStrong" })

	local ValueLabel = Skin.paint(create("TextLabel", {
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(1, -26, 1, 0),
		BackgroundTransparency = 1,
		Text = valueText,
		Font = Enum.Font.Code,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Box), { TextColor3 = "Text" })

	local Chevron = Skin.paint(create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1,
		Text = "▾",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	}, Box), { TextColor3 = "SubText" })

	MainButton.MouseEnter:Connect(function() tween(Box, { BackgroundColor3 = Theme.ElementHover }, 0.1) end)
	MainButton.MouseLeave:Connect(function() tween(Box, { BackgroundColor3 = Theme.Element }, 0.1) end)

	return Holder, MainButton, ValueLabel, Chevron
end

-- Option de liste, commune aux deux selecteurs. `label` est deja mis en forme
-- par l'appelant (le multi-select y prefixe sa case "[x] " / "[  ] ").
local function buildDropOption(list, label)
	-- ZIndex explicite (et pas la valeur par defaut) : le ScreenGui est cree par
	-- Instance.new, donc son ZIndexBehavior vaut Global - le rendu suit le
	-- numero de ZIndex a plat sur tout l'arbre, PAS la hierarchie. Sans ca, le
	-- fond du panneau (12) recouvrait ses propres options (1) : la liste
	-- s'ouvrait et restait cliquable, mais paraissait vide.
	local OptButton = Skin.paint(create("TextButton", {
		Size = UDim2.new(1, 0, 0, OPT_H),
		BackgroundTransparency = 1,
		Text = label,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 14,
	}, list), { BackgroundColor3 = "ElementHover", TextColor3 = "SubText" })
	create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, OptButton)
	OptButton.MouseEnter:Connect(function() OptButton.BackgroundTransparency = 0 end)
	OptButton.MouseLeave:Connect(function() OptButton.BackgroundTransparency = 1 end)
	return OptButton
end

-- Panneau de liste FLOTTANT, parente a Main (la fenetre) et PAS a la card ni a
-- PagesHolder : il passe ainsi par-dessus le contenu au lieu de le pousser, et
-- surtout il echappe au ClipsDescendants de la zone de contenu. Parente a
-- PagesHolder, une liste ouverte pres du bas de page etait tout simplement
-- coupee - on ne voyait que les deux premieres options du selecteur "Boss".
-- Main n'a pas de ClipsDescendants : le panneau peut donc deborder de la
-- fenetre si besoin, ce qui vaut mieux que d'etre tronque.
--
-- Position calculee a la main a l'ouverture, en coordonnees Main.
--
-- ZIndex : le ScreenGui vient d'Instance.new, donc son ZIndexBehavior vaut
-- Global - tout est dessine selon le numero de ZIndex a plat sur l'arbre, sans
-- tenir compte de la hierarchie. Un enfant ne passe donc PAS automatiquement
-- au-dessus de son parent : il faut etager explicitement (panneau 12, barre de
-- recherche et liste 13, options 14). Le contenu du menu plafonne a 10
-- (poignee de redimensionnement) et les voiles de chargement commencent a 20,
-- d'ou cette plage.
-- Renvoie { Panel, Scroll, Search, Open, Close, IsOpen }.
--
-- Une barre de recherche apparait a partir de DROP_SEARCH_FROM options : c'est
-- indispensable sur les listes longues (les ~30 objets achetables), ou faire
-- defiler a l'aveugle est penible.
local function buildDropList(holder, optionCount)
	local withSearch = optionCount >= DROP_SEARCH_FROM
	local searchOffset = withSearch and DROP_SEARCH_H or 0

	local Panel = Skin.paint(create("Frame", {
		Visible = false,
		ZIndex = 12,
	}, Main), { BackgroundColor3 = "Element" })
	corner(Panel, 3)
	Skin.paint(create("UIStroke", { Transparency = 0 }, Panel), { Color = "StrokeStrong" })

	local Search
	if withSearch then
		Search = Skin.paint(create("TextBox", {
			Position = UDim2.new(0, 1, 0, 1),
			Size = UDim2.new(1, -2, 0, DROP_SEARCH_H - 2),
			BackgroundTransparency = 1,
			Text = "",
			PlaceholderText = "Rechercher...",
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			ZIndex = 13,
		}, Panel), { TextColor3 = "Text", PlaceholderColor3 = "SubTextDim" })
		create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, Search)
		Skin.paint(create("Frame", {
			Position = UDim2.new(0, 0, 0, DROP_SEARCH_H - 1),
			Size = UDim2.new(1, 0, 0, 1),
			BorderSizePixel = 0,
			ZIndex = 13,
		}, Panel), { BackgroundColor3 = "StrokeStrong" })
	end

	local Scroll = Skin.paint(create("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, searchOffset),
		Size = UDim2.new(1, 0, 1, -searchOffset),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 13,
	}, Panel), { ScrollBarImageColor3 = "StrokeStrong" })
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, Scroll)

	local api = { Panel = Panel, Scroll = Scroll, Search = Search }

	function api.Close()
		Panel.Visible = false
		if Search then Search.Text = "" end
	end

	-- visibleCount : nombre d'options non filtrees, pour que le panneau ne garde
	-- pas une hauteur fixe quand la recherche en masque la moitie.
	function api.Open(visibleCount)
		local rows = math.clamp(visibleCount or optionCount, 1, DROP_MAX)
		local height = searchOffset + rows * OPT_H
		local origin = Main.AbsolutePosition
		local anchor = holder.AbsolutePosition

		-- Sous l'en-tete par defaut ; au-dessus si la liste depasserait le bas de
		-- l'ecran (typiquement un selecteur en bas d'une page bien remplie).
		local top = anchor.Y + DROP_H
		if top + height > ScreenGui.AbsoluteSize.Y - 8 then
			top = anchor.Y - height
		end

		Panel.Position = UDim2.fromOffset(anchor.X - origin.X, top - origin.Y)
		Panel.Size = UDim2.fromOffset(holder.AbsoluteSize.X, height)
		Panel.Visible = true
	end

	function api.IsOpen() return Panel.Visible end

	table.insert(MenuChrome.drops, api)
	return api
end

-- Referme tous les selecteurs ouverts. Appelee au changement d'onglet et avant
-- d'en ouvrir un autre : comme les panneaux flottent hors de leur card, un
-- panneau oublie resterait visible par-dessus une page qui a change.
function MenuChrome.closeDrops(except)
	for _, api in ipairs(MenuChrome.drops) do
		if api ~= except then api.Close() end
	end
end

local function addDropdownRow(content, text, options, default, onChange)
	local selected = default or options[1]

	local Holder, MainButton, ValueLabel, Chevron = buildDropHead(content, text, tostring(selected))
	MenuChrome.track(Holder, text)

	local drop = buildDropList(Holder, #options)
	local buttons = {}

	local function close()
		drop.Close()
		tween(Chevron, { Rotation = 0 }, 0.15)
	end

	-- Compte les options encore visibles apres filtrage, pour redimensionner le
	-- panneau au plus juste.
	local function visibleCount()
		local n = 0
		for _, btn in ipairs(buttons) do
			if btn.Visible then n = n + 1 end
		end
		return n
	end

	local function applyDropFilter()
		local query = drop.Search and string.lower(drop.Search.Text) or ""
		for _, btn in ipairs(buttons) do
			btn.Visible = query == "" or string.find(string.lower(btn.Text), query, 1, true) ~= nil
		end
		if drop.IsOpen() then drop.Open(visibleCount()) end
	end

	for _, option in ipairs(options) do
		local OptButton = buildDropOption(drop.Scroll, tostring(option))
		table.insert(buttons, OptButton)
		if option == selected then Skin.paint(OptButton, { TextColor3 = "Accent" }) end
		OptButton.MouseButton1Click:Connect(function()
			selected = option
			ValueLabel.Text = tostring(selected)
			for _, other in ipairs(buttons) do
				Skin.paint(other, { TextColor3 = other == OptButton and "Accent" or "SubText" })
			end
			close()
			if onChange then onChange(selected) end
		end)
	end

	if drop.Search then
		drop.Search:GetPropertyChangedSignal("Text"):Connect(applyDropFilter)
	end

	MainButton.MouseButton1Click:Connect(function()
		if drop.IsOpen() then
			close()
		else
			MenuChrome.closeDrops(drop)
			applyDropFilter()
			drop.Open(visibleCount())
			tween(Chevron, { Rotation = 180 }, 0.15)
		end
	end)

	-- Met a jour la valeur affichee sans passer par un clic (utilise par le
	-- chargement de config) ; declenche quand meme onChange pour appliquer l'effet.
	local function set(newValue)
		selected = newValue
		ValueLabel.Text = tostring(selected)
		if onChange then onChange(selected) end
	end

	return { Get = function() return selected end, Set = set, Instance = Holder }
end

-- Variante "cases a cocher repliables" de addDropdownRow : ne se ferme pas au
-- clic sur une option (chacune togglee independamment), l'entete affiche le
-- nombre selectionne. selectedSet est une table {option=bool} mutee en place
-- (et servant d'etat initial) ; onChange(option, newState) est appele a
-- chaque clic sur une option.
local function addMultiSelectDropdownRow(content, text, options, selectedSet, onChange)
	local function countSelected()
		local n = 0
		for _, v in pairs(selectedSet) do
			if v then n = n + 1 end
		end
		return n
	end

	-- L'en-tete compte les actifs ("6 / 8") au lieu de nommer une valeur : c'est
	-- l'information utile quand plusieurs sont coches en meme temps.
	local function headText() return countSelected() .. " / " .. #options end

	local Holder, MainButton, ValueLabel, Chevron = buildDropHead(content, text, headText())
	MenuChrome.track(Holder, text)

	local drop = buildDropList(Holder, #options)
	local buttons = {}

	local function optionText(option)
		return (selectedSet[option] and "[x]  " or "[  ]  ") .. tostring(option)
	end

	local function visibleCount()
		local n = 0
		for _, btn in ipairs(buttons) do
			if btn.Visible then n = n + 1 end
		end
		return n
	end

	local function applyDropFilter()
		local query = drop.Search and string.lower(drop.Search.Text) or ""
		for _, btn in ipairs(buttons) do
			btn.Visible = query == "" or string.find(string.lower(btn.Text), query, 1, true) ~= nil
		end
		if drop.IsOpen() then drop.Open(visibleCount()) end
	end

	for _, option in ipairs(options) do
		local OptButton = buildDropOption(drop.Scroll, optionText(option))
		OptButton.Font = Enum.Font.Code
		OptButton.TextSize = 13
		table.insert(buttons, OptButton)
		if selectedSet[option] then Skin.paint(OptButton, { TextColor3 = "Accent" }) end

		-- Ne se ferme PAS au clic : on coche plusieurs entrees d'affilee.
		OptButton.MouseButton1Click:Connect(function()
			local newState = not selectedSet[option]
			selectedSet[option] = newState
			OptButton.Text = optionText(option)
			Skin.paint(OptButton, { TextColor3 = newState and "Accent" or "SubText" })
			ValueLabel.Text = headText()
			if onChange then onChange(option, newState) end
		end)
	end

	if drop.Search then
		drop.Search:GetPropertyChangedSignal("Text"):Connect(applyDropFilter)
	end

	MainButton.MouseButton1Click:Connect(function()
		if drop.IsOpen() then
			drop.Close()
			tween(Chevron, { Rotation = 0 }, 0.15)
		else
			MenuChrome.closeDrops(drop)
			applyDropFilter()
			drop.Open(visibleCount())
			tween(Chevron, { Rotation = 180 }, 0.15)
		end
	end)

	return { Instance = Holder }
end

local function addSliderRow(content, text, min, max, default, step, onChange)
	step = step or 1
	local value = default or min

	-- Tout tient sur UNE ligne (libelle / valeur / piste) au lieu des deux
	-- d'avant : c'est l'autre moitie du gain de densite.
	local Holder = MenuChrome.track(create("Frame", { Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 }, content), text)
	Skin.paint(create("TextLabel", {
		Size = UDim2.new(1, -178, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Holder), { TextColor3 = "Text" })

	local decimals = step < 1 and math.max(0, -math.floor(math.log10(step) + 0.0001)) or 0
	local function formatValue(v)
		if v <= 0 and min <= 0 then return "illimite" end
		return string.format("%." .. decimals .. "f", v)
	end

	-- Chasse fixe : la valeur ne fait pas sauter la piste en changeant de
	-- largeur quand elle passe de 9 a 10.
	local ValueLabel = Skin.paint(create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -110, 0, 0),
		Size = UDim2.new(0, 62, 1, 0),
		BackgroundTransparency = 1,
		Text = formatValue(value),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, Holder), { TextColor3 = "SubText" })

	local Bar = Skin.paint(create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 100, 0, 4),
	}, Holder), { BackgroundColor3 = "StrokeStrong" })
	corner(Bar, 2)

	local function pctFor(v) return (v - min) / (max - min) end

	local Fill = Skin.paint(create("Frame", { Size = UDim2.new(pctFor(value), 0, 1, 0) }, Bar), { BackgroundColor3 = "Accent" })
	corner(Fill, 2)

	-- Curseur : un trait vertical fin plutot qu'une pastille ronde - a cette
	-- taille de piste (3 px) une pastille ferait une grosse bulle posee dessus.
	local Knob = Skin.paint(create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(pctFor(value), 0, 0.5, 0),
		Size = UDim2.new(0, 4, 0, 15),
		ZIndex = 2,
	}, Bar), { BackgroundColor3 = "Accent" })

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
		tweenStyled(Knob, { Size = hovering and UDim2.new(0, 4, 0, 19) or UDim2.new(0, 4, 0, 15) }, 0.15)
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
	return MenuChrome.track(Skin.paint(create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, content), { TextColor3 = "SubText" }), text)
end

-- Comportement de capture partage par addKeybindRow (ligne complete, touche
-- menu) et le petit carre de rebind des toggles (KeybindTool) : au clic sur
-- `button`, ecoute la prochaine touche clavier et l'assigne. Coupe le toggle
-- du menu (capturingKeybind) pendant la capture pour eviter qu'une touche
-- pressee pour le rebind ne ferme/ouvre le menu en meme temps.
-- escapeClears = false (touche menu) : Echap annule, garde l'ancienne touche.
-- escapeClears = true (keybinds de features) : Echap desassigne (comme
-- Retour arriere/Suppr) puisque ces touches supportent l'etat "aucune".
local function attachKeybindCapture(button, currentKey, onChange, escapeClears)
	local capturing = false
	local function labelFor(k) return k and k.Name or "Aucune" end
	button.Text = labelFor(currentKey)

	button.MouseEnter:Connect(function()
		if not capturing then tween(button, { BackgroundColor3 = Theme.ElementHover }, 0.1) end
	end)
	button.MouseLeave:Connect(function()
		if not capturing then tween(button, { BackgroundColor3 = Theme.Element }, 0.1) end
	end)

	-- Pendant l'ecoute, le cadre passe en Warn (ambre dans tous les themes) :
	-- ca dit "le menu attend une touche" sans se confondre avec l'accent, qui
	-- veut deja dire "actif" partout ailleurs.
	button.MouseButton1Click:Connect(function()
		if capturing then return end
		capturing = true
		capturingKeybind = true
		button.Text = "..."
		tween(button, { TextColor3 = Theme.Warn }, 0.1)
		local captureStroke = button:FindFirstChildWhichIsA("UIStroke")
		if captureStroke then captureStroke.Color = Theme.Warn end

		local connection
		connection = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

			connection:Disconnect()
			capturing = false
			capturingKeybind = false
			tween(button, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.Text }, 0.1)
			if captureStroke then captureStroke.Color = Theme.StrokeStrong end

			if input.KeyCode == Enum.KeyCode.Escape and not escapeClears then
				button.Text = labelFor(currentKey)
				return
			end

			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				currentKey = nil
			else
				currentKey = input.KeyCode
			end
			button.Text = labelFor(currentKey)
			if onChange then onChange(currentKey) end
		end)
	end)

	return { Get = function() return currentKey end }
end

local function addKeybindRow(content, text, currentKey, onChange, escapeClears)
	local Row = MenuChrome.track(create("Frame", { Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 }, content), text)
	Skin.paint(create("TextLabel", {
		Size = UDim2.new(1, -104, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Row), { TextColor3 = "Text" })

	local KeyButton = Skin.paint(create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 102, 0, 25),
		Font = Enum.Font.Code,
		TextSize = 13,
		AutoButtonColor = false,
	}, Row), { BackgroundColor3 = "Element", TextColor3 = "Text" })
	corner(KeyButton, 3)
	Skin.paint(create("UIStroke", { Transparency = 0 }, KeyButton), { Color = "StrokeStrong" })

	return attachKeybindCapture(KeyButton, currentKey, onChange, escapeClears or false)
end

--------------------------------------------------------------------------------
-- Keybinds de features : touche configurable par feature (Noclip, Fly, ESP,
-- TP Safe Spot...), en plus du clic dans le menu. Persistees dans Prefs
-- (comme MENU_TOGGLE_KEY) - ce sont des preferences d'input, pas des reglages
-- "cheat" qui suivent le systeme de config. Inclut le HUD "Voir les Keybinds"
-- (page Settings) qui affiche les touches assignees, colorees quand la
-- feature associee est active. KeybindTool regroupe etat + fonctions dans
-- UNE table plutot qu'en locals separes (limite des 200 registres).
--------------------------------------------------------------------------------

local KeybindTool = {}
do
	local function resolveOptionalKeyCode(name)
		if not name or name == "" then return nil end
		local ok, keyCode = pcall(function() return Enum.KeyCode[name] end)
		if ok and keyCode then return keyCode end
		return nil
	end

	-- entries[i] = { id, label, key (KeyCode ou nil), get (function->bool, ou
	-- nil pour une action sans etat), run (function, appelee sur la touche) }
	KeybindTool.entries = {}
	KeybindTool.hudRows = {} -- entry -> TextLabel affiche dans le HUD

	-- Enregistre une entree + persiste au changement. Partage entre bind()
	-- (ligne complete, actions) et bindToggle() (petit carre, toggles).
	local function registerEntry(id, label, getFn, runFn, onKeyChanged)
		local key = resolveOptionalKeyCode(Prefs.FeatureKeybinds and Prefs.FeatureKeybinds[id])
		local entry = { id = id, label = label, key = key, get = getFn, run = runFn }
		table.insert(KeybindTool.entries, entry)

		local function onChange(newKey)
			entry.key = newKey
			Prefs.FeatureKeybinds = Prefs.FeatureKeybinds or {}
			Prefs.FeatureKeybinds[id] = newKey and newKey.Name or nil
			savePrefs()
			KeybindTool.refreshHud()
		end
		onKeyChanged(key, onChange)
	end

	-- Action ponctuelle (ex: teleport) : ligne complete "Touche (Label)".
	-- getFn peut etre nil (pas d'etat actif/inactif - le HUD l'affiche alors
	-- toujours en blanc). Echap desassigne (comme Retour arriere/Suppr).
	function KeybindTool.bind(content, id, label, getFn, runFn)
		registerEntry(id, label, getFn, runFn, function(key, onChange)
			addKeybindRow(content, "Touche (" .. label .. ")", key, onChange, true)
		end)
	end

	-- Toggle FEATURE_CONTROLS (control.Get/control.Set) : la touche inverse
	-- l'etat, exactement comme un clic sur le switch. Pas de ligne separee -
	-- juste un petit carre insere a gauche du texte du toggle (control.Row/
	-- control.Label, exposes par addToggleRow), pour rester compact.
	function KeybindTool.bindToggle(id, label, control)
		registerEntry(id, label, control.Get, function()
			control.Set(not control.Get())
		end, function(key, onChange)
			local SQUARE = 18
			local GAP = 6

			control.Label.Position = UDim2.new(0, SQUARE + GAP, 0, 0)
			control.Label.Size = UDim2.new(1, -38 - SQUARE - GAP, 1, 0)

			local KeySquare = Skin.paint(create("TextButton", {
				Position = UDim2.new(0, 0, 0.5, -SQUARE / 2),
				Size = UDim2.new(0, SQUARE, 0, SQUARE),
				Font = Enum.Font.Code,
				TextSize = 10,
				TextScaled = true,
				TextWrapped = true,
				AutoButtonColor = false,
			}, control.Row), { BackgroundColor3 = "Element", TextColor3 = "SubText" })
			corner(KeySquare, 3)
			Skin.paint(create("UIStroke", { Transparency = 0 }, KeySquare), { Color = "StrokeStrong" })

			attachKeybindCapture(KeySquare, key, onChange, true)
		end)
	end

	track(UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or capturingKeybind or unloaded then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		for _, entry in ipairs(KeybindTool.entries) do
			if entry.key == input.KeyCode then
				entry.run()
			end
		end
	end))

	-- HUD : liste des touches assignees, superposee au jeu (independante de la
	-- fenetre du menu). Ne montre que les entries avec une touche assignee.
	KeybindTool.hudFrame = create("Frame", {
		Position = UDim2.new(0, 16, 0, 60),
		Size = UDim2.new(0, 220, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = Prefs.ShowKeybindHud,
	}, ScreenGui)
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, KeybindTool.hudFrame)

	function KeybindTool.refreshHud()
		KeybindTool.hudFrame:ClearAllChildren()
		create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, KeybindTool.hudFrame)
		KeybindTool.hudRows = {}
		for _, entry in ipairs(KeybindTool.entries) do
			if entry.key then
				KeybindTool.hudRows[entry] = create("TextLabel", {
					Size = UDim2.new(1, 0, 0, 18),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Text = "[" .. entry.key.Name .. "] " .. entry.label,
					Font = Enum.Font.GothamBold,
					TextSize = 14,
					TextColor3 = Color3.new(1, 1, 1),
					TextStrokeTransparency = 0.5,
					TextXAlignment = Enum.TextXAlignment.Left,
				}, KeybindTool.hudFrame)
			end
		end
	end

	task.spawn(function()
		while not unloaded do
			task.wait(0.2)
			if KeybindTool.hudFrame.Visible then
				for entry, row in pairs(KeybindTool.hudRows) do
					local active = entry.get and entry.get()
					row.TextColor3 = active and Theme.Accent or Color3.new(1, 1, 1)
				end
			end
		end
	end)
end

local function addButtonRow(content, text, onClick)
	local Button = Skin.paint(create("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		AutoButtonColor = false,
	}, content), { BackgroundColor3 = "Element", TextColor3 = "Text" })
	corner(Button, 3)
	Skin.paint(create("UIStroke", { Transparency = 0 }, Button), { Color = "Stroke" })
	local buttonScale = create("UIScale", { Scale = 1 }, Button) -- petit effet d'appui (scale), independant du pivot du bouton
	MenuChrome.track(Button, text)

	local hovering = false
	Button.MouseEnter:Connect(function()
		hovering = true
		tween(Button, { BackgroundColor3 = Theme.ElementHover }, 0.1)
	end)
	Button.MouseLeave:Connect(function()
		hovering = false
		tween(Button, { BackgroundColor3 = Theme.Element }, 0.1)
	end)

	Button.MouseButton1Click:Connect(function()
		-- Flash a l'accent puis retour : le seul moment ou un bouton se colore.
		Button.BackgroundColor3 = Theme.Accent
		Button.TextColor3 = Theme.OnAccent
		tween(buttonScale, { Scale = 0.97 }, 0.08)
		task.delay(0.08, function()
			tween(buttonScale, { Scale = 1 }, 0.12)
		end)
		task.delay(0.12, function()
			tween(Button, {
				BackgroundColor3 = hovering and Theme.ElementHover or Theme.Element,
				TextColor3 = Theme.Text,
			}, 0.15)
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
			notify("Aucune cible selectionnee.", "error")
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
local AutresPage = createCategory("Autres", Color3.fromRGB(110, 210, 200))
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

	-- Chaque section vit dans son propre do...end : la variable "XSection"
	-- (et le reste de ses locals) ne sert que le temps de construire cette
	-- section, donc on la laisse sortir de portee tout de suite pour liberer
	-- son registre local plutot que de le garder ouvert jusqu'a la fin du
	-- bloc. Voir la note "Limite Luau : 200 registres locaux" en tete de
	-- fichier avant d'ajouter une nouvelle section ici sans ce wrapping.

	do
		-- Reglages ESP : active/désactive, mode (Lua ou Python), distance max, affichage PV et distance.
		local EspSection = addSection(VisualsPage, "ESP")

		FEATURE_CONTROLS.EspEnabled = addToggleRow(EspSection, "ESP Actif", FeatureState.enabled, function(state)
			setEnabled(state)
			if not state then pushOverlayDisabled() end
			Settings.EspEnabled = state
		end)
		KeybindTool.bindToggle("EspEnabled", "ESP", FEATURE_CONTROLS.EspEnabled)

		FEATURE_CONTROLS.EspMode = addDropdownRow(EspSection, "Mode ESP", { "Lua", "Python" }, FeatureState.EspMode, function(mode)
			local wasPython = FeatureState.enabled and FeatureState.EspMode == "Python"
			FeatureState.EspMode = mode
			setEnabled(FeatureState.enabled) -- reapplique la visibilite des billboards selon le nouveau mode
			if wasPython and mode ~= "Python" then pushOverlayDisabled() end
			Settings.EspMode = mode
		end)

		FEATURE_CONTROLS.EspMaxDistance = addSliderRow(EspSection, "Distance Max", 0, 10000, FeatureState.EspMaxDistance, 1, function(v)
			FeatureState.EspMaxDistance = v
			Settings.EspMaxDistance = v
		end)

		FEATURE_CONTROLS.ShowHealth = addToggleRow(EspSection, "Afficher PV", FeatureState.ShowHealth, function(state)
			FeatureState.ShowHealth = state
			refreshAllPlayerLabels()
			Settings.ShowHealth = state
		end)

		FEATURE_CONTROLS.ShowDistance = addToggleRow(EspSection, "Afficher Distance", FeatureState.ShowDistance, function(state)
			FeatureState.ShowDistance = state
			refreshAllPlayerLabels()
			Settings.ShowDistance = state
		end)

		FEATURE_CONTROLS.ShowChakra = addToggleRow(EspSection, "Afficher Chakra", FeatureState.ShowChakra, function(state)
			FeatureState.ShowChakra = state
			refreshAllPlayerLabels()
			Settings.ShowChakra = state
		end)

		FEATURE_CONTROLS.ShowBlood = addToggleRow(EspSection, "Afficher Blood", FeatureState.ShowBlood, function(state)
			FeatureState.ShowBlood = state
			refreshAllPlayerLabels()
			Settings.ShowBlood = state
		end)

		-- CurrentSkill (orange, au-dessus du nom) et taille de l'ESP : ESP Lua
		-- uniquement, aucun des deux n'est envoye a l'overlay Python
		-- (sendOverlayPacket/writeOverlayData n'y touchent pas).
		FEATURE_CONTROLS.ShowCurrentSkill = addToggleRow(EspSection, "Afficher Current Skill (au-dessus du nom)", FeatureState.ShowCurrentSkill, function(state)
			FeatureState.ShowCurrentSkill = state
			refreshAllPlayerLabels()
			Settings.ShowCurrentSkill = state
		end)

		FEATURE_CONTROLS.EspScale = addDropdownRow(EspSection, "Taille ESP", ESP_SCALE_OPTIONS, FeatureState.EspScale, function(scale)
			FeatureState.EspScale = scale
			Settings.EspScale = scale
			-- Rebuild complet plutot qu'un rescale en place (voir getEspScale) :
			-- applyChatOverlay relit deja FeatureState.EspScale a la creation.
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer and player.Character then
					applyChatOverlay(player)
				end
			end
		end)
	end

	do
		local EnvSection = addSection(VisualsPage, "Environnement")

		FEATURE_CONTROLS.NoFogEnabled = addToggleRow(EnvSection, "No Fog", FeatureState.NoFogEnabled, function(state)
			setNoFog(state)
			Settings.NoFogEnabled = state
		end)
		FEATURE_CONTROLS.NoRainEnabled = addToggleRow(EnvSection, "No Rain", FeatureState.NoRainEnabled, function(state)
			setNoRain(state)
			Settings.NoRainEnabled = state
		end)
		FEATURE_CONTROLS.FullBrightEnabled = addToggleRow(EnvSection, "Full Bright", FeatureState.FullBrightEnabled, function(state)
			setFullBright(state)
			Settings.FullBrightEnabled = state
		end)

		FEATURE_CONTROLS.BrightnessLevel = addSliderRow(EnvSection, "Brightness Level", 1, 10, FeatureState.BrightnessLevel, 0.1, function(v)
			FeatureState.BrightnessLevel = v
			Settings.BrightnessLevel = v
		end)

		FEATURE_CONTROLS.TimeOfDay = addDropdownRow(EnvSection, "Heure", { "Morning", "Afternoon", "Evening", "Night" }, FeatureState.TimeOfDay, function(v)
			FeatureState.TimeOfDay = v
			Settings.TimeOfDay = v
		end)

		FEATURE_CONTROLS.TimeChangerEnabled = addToggleRow(EnvSection, "Time Changer", FeatureState.TimeChangerEnabled, function(state)
			setTimeChanger(state)
			Settings.TimeChangerEnabled = state
		end)
	end

	--------------------------------------------------------------------------------
	------------------------------- PLAYER -----------------------------------------
	--------------------------------------------------------------------------------

	do
		local NotifSection = addSection(PlayerPage, "Notifications")

		FEATURE_CONTROLS.ChakraSenseNotifier = addToggleRow(NotifSection, "Chakra Sense Notifier", FeatureState.ChakraSenseNotifier, function(state)
			FeatureState.ChakraSenseNotifier = state
			Settings.ChakraSenseNotifier = state
		end)
		-- Frequence du poll ReplicatedStorage.Cooldowns (voir tout en bas du
		-- fichier) - remplace le task.wait(15) fixe d'origine.
		FEATURE_CONTROLS.ChakraSenseNotifyInterval = addSliderRow(NotifSection, "Frequence de verification Chakra Sense (secondes)", 1, 30, Settings.ChakraSenseNotifyInterval, 1, function(v)
			Settings.ChakraSenseNotifyInterval = v
		end)
		-- BeingObservedBy : des qu'une valeur de ce nom est ajoutee dans notre
		-- ReplicatedStorage.Settings.<nous>, on notifie - simple ChildAdded,
		-- pas de verification de valeur (demande explicitement ainsi par
		-- l'utilisateur). Confirme en jeu que ce champ apparait aussi bien
		-- pour le spectate que pour Chakra Sense.
		FEATURE_CONTROLS.SpectatedNotifier = addToggleRow(NotifSection, "Alerte si quelqu'un vous observe (spectate/Chakra Sense)", FeatureState.SpectatedNotifier, function(state)
			FeatureState.SpectatedNotifier = state
			Settings.SpectatedNotifier = state
		end)
	end

	do
		local MovementSection = addSection(PlayerPage, "Mouvement")

		FEATURE_CONTROLS.NoclipEnabled = addToggleRow(MovementSection, "Noclip", FeatureState.NoclipEnabled, function(state)
			setNoclip(state)
			Settings.NoclipEnabled = state
		end)
		KeybindTool.bindToggle("NoclipEnabled", "Noclip", FEATURE_CONTROLS.NoclipEnabled)

		FEATURE_CONTROLS.FlyEnabled = addToggleRow(MovementSection, "Fly", FeatureState.FlyEnabled, function(state)
			setFly(state)
			Settings.FlyEnabled = state
		end)
		attachTooltip(FEATURE_CONTROLS.FlyEnabled.Row, "ZQSD/WASD pour se deplacer, Espace pour monter, Ctrl pour descendre.")
		KeybindTool.bindToggle("FlyEnabled", "Fly", FEATURE_CONTROLS.FlyEnabled)

		FEATURE_CONTROLS.FlySpeed = addSliderRow(MovementSection, "Fly Speed", 10, 500, FeatureState.FlySpeed, 10, function(v)
			FeatureState.FlySpeed = v
			Settings.FlySpeed = v
		end)

	end

	do
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
					notify("Joueur introuvable.", "error")
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
	end

	do
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
	end

	do
		local SafeSpotSection = addSection(PlayerPage, "Safe Spot")
		addButtonRow(SafeSpotSection, "Definir Safe Spot", setSafeSpot)
		addButtonRow(SafeSpotSection, "Teleporter au Safe Spot", teleportToSafeSpot)
		-- Action ponctuelle (pas de toggle) : getFn = nil, le HUD l'affiche
		-- toujours en blanc.
		KeybindTool.bind(SafeSpotSection, "TeleportSafeSpot", "TP Safe Spot", nil, teleportToSafeSpot)
	end

	do
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
	end

	do
		local InventorySection = addSection(AutoPage, "Envoi Auto Inventaire")
		FEATURE_CONTROLS.InventoryAutoSendEnabled = addToggleRow(InventorySection, "Envoi Auto", Settings.InventoryAutoSendEnabled, function(state)
			Settings.InventoryAutoSendEnabled = state
		end)
		attachTooltip(FEATURE_CONTROLS.InventoryAutoSendEnabled.Row, "Envoie Inventaire + Hotbar + Lifeforce au webhook Discord a intervalle regulier.")
		FEATURE_CONTROLS.InventoryAutoSendInterval = addSliderRow(InventorySection, "Intervalle (secondes)", 30, 1800, Settings.InventoryAutoSendInterval, 30, function(v)
			Settings.InventoryAutoSendInterval = v
		end)
	end

	do
		local AfkAgeUpSection = addSection(AutoPage, "AFK AgeUp")
		FEATURE_CONTROLS.AfkAgeUpEnabled = addToggleRow(AfkAgeUpSection, "AFK AgeUp", Settings.AfkAgeUpEnabled, function(state)
			setAfkAgeUp(state)
			Settings.AfkAgeUpEnabled = state
		end)
		attachTooltip(FEATURE_CONTROLS.AfkAgeUpEnabled.Row, "Teleporte vers une Safe Place des qu'un joueur passe a moins de 300 metres.")
	end

	do
		local PanicTeleportSection = addSection(AutoPage, "Panic Teleport")
		FEATURE_CONTROLS.PanicTeleportEnabled = addToggleRow(PanicTeleportSection, "Panic Teleport", Settings.PanicTeleportEnabled, function(state)
			setPanicTeleport(state)
			Settings.PanicTeleportEnabled = state
		end)
		attachTooltip(FEATURE_CONTROLS.PanicTeleportEnabled.Row, "Teleporte entre Safe Places si PV < 50, jusqu'a repasser au-dessus de 100.")
	end

	do
		-- Auto Infuse : reproduit la sequence complete capturee dans call.lua -
		-- DataEvent:FireServer("Item", "Selected", gemName) PUIS
		-- DataFunction:InvokeServer("RequestToInfuse", gemName). Le second
		-- appel seul (sans le FireServer prealable) ne faisait rien en jeu -
		-- le serveur a besoin de savoir quel item est "selectionne" avant la
		-- requete d'infusion. La gemme infuse l'arme actuellement equipee (ni
		-- l'un ni l'autre appel ne prend d'arme cible).
		-- GEM_NAMES extrait du dump (data2.lua, table Items, entrees avec
		-- Type = "Gem").
		local GEM_NAMES = {
			"Aqua Gem", "Black Flame Gem", "Flame Gem", "Ground Gem", "Ice Gem",
			"Poison Gem", "Spark Gem", "Spooky Gem", "Wind Gem",
		}

		Settings.AutoInfuseGems = Settings.AutoInfuseGems or {}

		local function findInventoryQuantity(inventory, itemName)
			for _, slot in pairs(inventory) do
				if slot.Item == itemName then
					return slot.Quantity or 0
				end
			end
			return 0
		end

		local function runInfuseCycle()
			local Events = ReplicatedStorage:FindFirstChild("Events")
			local DataFunction = Events and Events:FindFirstChild("DataFunction")
			local DataEvent = Events and Events:FindFirstChild("DataEvent")
			if not DataFunction or not DataEvent then
				notify("ReplicatedStorage.Events introuvable.", "error")
				return
			end

			local ok, playerData = pcall(function()
				return DataFunction:InvokeServer("GetData")
			end)
			if not ok or not playerData or not playerData.Inventory then
				notify("Auto Infuse : impossible de recuperer l'inventaire.", "error")
				return
			end

			for _, gemName in ipairs(GEM_NAMES) do
				if Settings.AutoInfuseGems[gemName] and findInventoryQuantity(playerData.Inventory, gemName) > 0 then
					DataEvent:FireServer("Item", "Selected", gemName)
					task.wait()

					local infuseOk, result = pcall(function()
						return DataFunction:InvokeServer("RequestToInfuse", gemName)
					end)

					if not infuseOk then
						notify("Erreur Auto Infuse (" .. gemName .. ") : " .. tostring(result), "error")
					elseif result == false then
						notify("Infusion refusee par le serveur pour " .. gemName .. ".", "error")
					elseif result == true then
						notify("Infusion reussie : " .. gemName .. ".", "success")
					end

					task.wait(0.3) -- petit delai entre deux infusions
				end
			end
		end

		task.spawn(function()
			while not unloaded do
				task.wait(Settings.AutoInfuseInterval)
				if unloaded then break end
				if Settings.AutoInfuseEnabled then
					pcall(runInfuseCycle)
				end
			end
		end)

		local AutoInfuseSection = addSection(AutoPage, "Auto Infuse")
		FEATURE_CONTROLS.AutoInfuseEnabled = addToggleRow(AutoInfuseSection, "Auto Infuse", Settings.AutoInfuseEnabled, function(state)
			Settings.AutoInfuseEnabled = state
		end)
		attachTooltip(FEATURE_CONTROLS.AutoInfuseEnabled.Row, "Infuse automatiquement les gemmes cochees des que t'en as en inventaire.")
		FEATURE_CONTROLS.AutoInfuseInterval = addSliderRow(AutoInfuseSection, "Intervalle (secondes)", 15, 90, Settings.AutoInfuseInterval, 1, function(v)
			Settings.AutoInfuseInterval = v
		end)
		addMultiSelectDropdownRow(AutoInfuseSection, "Gemmes", GEM_NAMES, Settings.AutoInfuseGems, function(gemName, state)
			Settings.AutoInfuseGems[gemName] = state
		end)
	end

	do
		-- Auto Boss : vole au-dessus du boss (hors de portee de ses attaques
		-- au corps a corps) et spam l'attaque tant qu'il est vivant, boss par
		-- boss via BOSS_CONFIGS plutot qu'un Fly generique (facile a etendre :
		-- ajouter une entree pour un autre boss). Decalage vertical (attach-
		-- Offset, 10 studs) et rotation fixe testes en live via Potassium :
		-- zero degat encaisse sur plusieurs secondes d'attach, PlatformStand
		-- indispensable pour eviter que le Humanoid du jeu se batte contre le
		-- CFrame pose chaque frame (voir M.setAttachedPhysics plus bas).
		-- Sub (jutsu de substitution, voir M.trySubstitute plus bas) declenche
		-- automatiquement des qu'on encaisse des degats, en filet de securite
		-- supplementaire - reduit les degats sans remplacer un bon
		-- positionnement.
		-- performM1/canM1 sont des globals internes a ClientGui.LocalScript
		-- (pas partages avec ce script), recuperes une fois via getsenv.
		-- Le loot n'apparait pas automatiquement dans l'inventaire (verifie :
		-- rien dans u11.Inventory juste apres un kill) - c'est un ramassage
		-- physique au sol (voir rewardsModel/M.collectLoot plus bas).
		-- Etat + fonctions regroupees en deux tables (meme pattern que
		-- Spectate Leaderboard plus haut) : la boucle de position/attaque a
		-- besoin d'etat partage (attache ?, jeton anti-doublon) entre
		-- plusieurs fonctions qui doivent toutes rester actives ensemble.
		-- rewardsModel : Model deja present dans workspace (pas cree par le
		-- boss a sa mort), avec des Part "TrinketSpawn1".."N" invisibles/sans
		-- collision qui accueillent le loot physique au sol une fois le boss
		-- mort - confirme en live via Potassium (workspace.TairockRewards.
		-- TrinketSpawn1..6, Transparency=1, CanCollide=false, vides tant que
		-- le boss est vivant).
		-- Lavarossa (WorldBoss) : meme famille de NPC que Tairock (meme
		-- Script "NPCManager" trouve dans les deux Model) - observe en live
		-- pendant que l'autofarm d'un autre script tournait dessus : hover a
		-- 10-12 studs au-dessus de la HumanoidRootPart, PV du joueur constants
		-- (0 degat) sur tout le combat, HP boss reste bloque a 1 (downed, meme
		-- pattern "attend un finisher" que Tairock) puis le Model disparait de
		-- workspace une fois looté - LavarossaRewards (TrinketSpawn1..7) suit
		-- exactement la meme structure que TairockRewards.
		-- spawnFloor/spawnEvent : contrairement a Tairock (qui respawn seul
		-- avec le temps), Lavarossa est un world boss qui doit etre "reveille"
		-- - confirme dans le dump client (data.lua) : marcher sur le Part
		-- workspace.LavarossaFloor tant que son StringValue enfant "Activated"
		-- vaut "" declenche DataEvent:FireServer("activateLavarossa"). Une
		-- fois active, Activated repasse a autre chose ("ReadyToDeactivate"
		-- observe en live juste apres un kill) le temps d'un cooldown avant de
		-- redevenir "" - voir M.trySpawnBoss plus bas.
		local BOSS_CONFIGS = {
			-- lootWaitPosition : point capture en live, centre entre les 6
			-- TrinketSpawn de TairockRewards (a portee de ramassage de tous),
			-- utilise pour attendre le settle du loot au lieu de spawns[1]
			-- (qui n'est proche que d'UN seul trinket).
			Tairock = {
				attachOffset = Vector3.new(0, 8, 0),
				rewardsModel = "TairockRewards",
				lootWaitPosition = Vector3.new(-120.995849609375, -215.20166015625, -1074.076904296875),
			},
			Lavarossa = {
				attachOffset = Vector3.new(0, 10, 0),
				rewardsModel = "LavarossaRewards",
				spawnFloor = "LavarossaFloor",
				spawnEvent = "activateLavarossa",
				lootWaitPosition = Vector3.new(-500.2711486816406, -312.06591796875, -193.25636291503906),
			},
			-- dodgeAnimationIds/dodgeOffset : contrairement a Tairock/Lavarossa,
			-- Chakra Knight a des attaques qui touchent meme au hover normal
			-- (~10 studs) - confirme en live (Potassium), deux pistes
			-- distinctes :
			--   - 10141233349 : piste secondaire superposee a l'idle de base,
			--     correspond aux moments ou l'autre script monte a ~40 studs.
			--   - 10229183096 : jouee ~0.6s AVANT que le boss (son propre
			--     HumanoidRootPart) ne saute physiquement d'une cinquantaine
			--     de studs (observe : Y -119 -> -64) - deroule un peu comme
			--     un signal d'annonce/windup pour ce saut.
			-- Voir M.attachTo : hover normal tant qu'aucune des deux ne joue,
			-- saute a dodgeOffset des qu'une demarre, redescend a son arret
			-- (Humanoid.AnimationPlayed/AnimationTrack.Stopped) - le CFrame
			-- etant recalcule chaque frame relativement a la position ACTUELLE
			-- du boss, on suit deja son saut physique ; dodgeOffset ajoute
			-- juste la marge verticale supplementaire pendant ces deux pistes.
			["Chakra Knight"] = {
				attachOffset = Vector3.new(0, 10, 0),
				rewardsModel = "ChakraKnightRewards",
				dodgeAnimationIds = { "10141233349", "10229183096" },
				dodgeOffset = Vector3.new(0, 42, 0),
				lootWaitPosition = Vector3.new(2831.0322265625, -123.50000762939453, -1153.224365234375),
			},
			-- Barbarit The Rose : meme mecanique de spawn manuel que Lavarossa
			-- (BarbaritFloor/activateBarbarit, confirme dans data.lua). Combat
			-- observe en live sur ~31s : 0 degat encaisse a un hover de ~9-15
			-- studs, aucun saut/animation speciale detectee (contrairement a
			-- Chakra Knight) - pas besoin de dodgeAnimationIds ici.
			["Barbarit The Rose"] = {
				attachOffset = Vector3.new(0, 12, 0),
				rewardsModel = "BarbaritRewards",
				spawnFloor = "BarbaritFloor",
				spawnEvent = "activateBarbarit",
			},
			-- Hyuga Boss : pas de Grip (CanBeGripped=false, InstantDeath=true
			-- dans GameManager.NPC - confirme en live, meurt directement sans
			-- jamais passer par l'etat "a terre"/PlatformStanding, donc la
			-- logique de Grip partagee ne se declenche jamais pour lui, pas
			-- besoin de cas particulier). Deux esquives distinctes observees
			-- en live (probablement "64 Palms"/"Palm Rotation" cote jeu) :
			-- les deux animations font monter l'autre script a ~30 studs.
			-- Pas de spawnFloor/spawnEvent connu (acces via un portail
			-- physique - Hyuga BossPortal/BossEntrances - pas un remote
			-- d'activation simple comme Lavarossa/Barbarit).
			["Hyuga Boss"] = {
				attachOffset = Vector3.new(0, 9, 0),
				rewardsModel = "Hyuga BossRewards",
				dodgeAnimationIds = { "8580099842", "8699113073" },
				dodgeOffset = Vector3.new(0, 35, 0),
				lootWaitPosition = Vector3.new(-674.881591796875, -359.86474609375, -728.7794189453125),
			},
			-- Manda : meme mecanique de spawn manuel que Lavarossa/Barbarit
			-- (MandaFloor/activateManda, confirme dans data.lua). Meme
			-- famille que Lava Snake (memes animations de base partagees) et
			-- meme trigger d'esquive : rbxassetid://9954909571, correlation
			-- nette et repetee (4x) confirmee en live - hover normal ~5-7
			-- studs, monte a ~53-56 studs pendant cette animation, degats
			-- stoppent pendant la montee. (La toute premiere observation
			-- avait mesure un hover ~1246 studs, mais c'etait avant d'etre
			-- reellement en position de combat - fausse mesure, corrigee ici
			-- avec des donnees prises en plein combat actif.)
			Manda = {
				attachOffset = Vector3.new(0, 12, 0),
				rewardsModel = "MandaRewards",
				spawnFloor = "MandaFloor",
				spawnEvent = "activateManda",
				dodgeAnimationIds = { "9954909571" },
				dodgeOffset = Vector3.new(0, 58, 0),
				lootWaitPosition = Vector3.new(1526.775146484375, -534.0000610351562, 726.8818359375),
			},
			-- Lava Snake : meme famille que Manda (memes animations de base
			-- partagees, confirme en live), mais a echelle normale cette
			-- fois. Trigger de l'esquive clairement identifie en live :
			-- l'animation rbxassetid://9954909571 apparait ~0.15-0.3s avant
			-- chaque montee a ~55-57 studs (degats qui stoppent pendant, et
			-- reprennent des le retour au hover normal ~5-7 studs) -
			-- correlation nette et reproductible (observee 2 fois).
			["Lava Snake"] = {
				attachOffset = Vector3.new(0, 12, 0),
				rewardsModel = "LavaSnakeRewards",
				spawnFloor = "LavaSnakeFloor",
				spawnEvent = "activateLavaSnake",
				dodgeAnimationIds = { "9954909571" },
				dodgeOffset = Vector3.new(0, 60, 0),
				lootWaitPosition = Vector3.new(-604.2379760742188, -548.9771118164062, -1481.6185302734375),
			},
			-- Wooden Golem : toujours present (pas de spawnFloor/spawnEvent -
			-- CustomArena/AlwaysAggro=true dans GameManager.NPC). GripImmunity=true
			-- cote GameManager - voir gripImmune plus bas et son usage dans la
			-- section Grip du main loop.
			--
			-- dodgeCyclePositions : les 4 coins entre lesquels on cycle pendant
			-- "Spire" et "Dragon" (les deux FarRangeAttacks a portee). X/Z releves
			-- au sniffer sur le script de reference.
			--
			-- HAUTEUR = 336.92, celle du script de reference. NE PAS remonter.
			--
			-- Ca a ete essaye a 355, sur un raisonnement pourtant solide : les
			-- pics de sol du Spire ("WormBranch") culminent a 337-341, donc 336.92
			-- est dedans, et 355 tombe dans le creneau libre entre eux et la
			-- hitbox du Dragon (372-373). En jeu, resultat inverse : nettement
			-- PLUS de degats a 355 qu'a 336.92, deux essais de suite.
			--
			-- L'explication la plus probable est que la hauteur ne sert pas a
			-- sortir de la portee du hazard mais a sortir de la zone que le
			-- serveur considere comme touchee - et que les coins a 336.92 sont
			-- justement hors de cette zone, quoi qu'en dise la geometrie des
			-- pics. A ne pas retoucher sans mesure contradictoire.
			["Wooden Golem"] = {
				attachOffset = Vector3.new(0, 9, 0),
				rewardsModel = "WoodenGolemRewards",
				dodgeAnimationIds = { "116907126244057", "120758909308511" },
				dodgeCyclePositions = {
					Vector3.new(-4726.7885, 336.9198, -3006.4700),
					Vector3.new(-4718.8340, 336.9197, -2856.7888),
					Vector3.new(-4505.9922, 336.9198, -3005.4119),
					Vector3.new(-4523.6904, 336.9198, -2861.7544),
				},
				lootWaitPosition = Vector3.new(-4703.2788, 336.9198, -2940.3208),
				gripImmune = true,
			},
		}
		-- Liste ordonnee pour le dropdown de selection (meme pattern que
		-- GEM_NAMES/AutoInfuseGems) - a completer en meme temps que
		-- BOSS_CONFIGS quand un boss est ajoute, pour la rota multi-boss.
		local BOSS_NAMES = { "Tairock", "Lavarossa", "Chakra Knight", "Barbarit The Rose", "Hyuga Boss", "Manda", "Lava Snake", "Wooden Golem" }

		Settings.AutoBossSelected = Settings.AutoBossSelected or {}
		for _, name in ipairs(BOSS_NAMES) do
			if Settings.AutoBossSelected[name] == nil then
				Settings.AutoBossSelected[name] = true
			end
		end

		local GameManager = require(ReplicatedStorage.GameManager)

		-- hudHp/hudHpMax : derniers PV pousses dans le HUD, memorises pour que
		-- M.setHudState puisse reafficher la meme valeur dans la barre d'etat du
		-- menu sans que l'appelant ait a les repasser.
		-- dodgeUntil : instant (os.clock) jusqu'auquel on reste en esquive, arme
		-- au DEBUT de l'animation d'attaque - voir DODGE_WINDOW_SECONDS et
		-- M.isDodging.
		local state = { enabled = false, attached = false, token = 0, healthConn = nil, hud = nil, lastGripAttempt = 0, lastConfig = nil, lastBossName = nil, lootPending = false, chakraSensePaused = false, resumeDeadline = nil, bossPresent = false, lastSpawnAttempt = {}, dodging = false, dodgeActiveCount = 0, dodgeUntil = 0, dodgeAnimConn = nil, gripping = false, deadSince = nil, lowHealthSince = nil, panicPaused = false, hudHp = nil, hudHpMax = nil }

		-- Duree pendant laquelle on reste en esquive, comptee depuis le DEBUT de
		-- l'animation d'attaque (pas depuis sa fin). Les degats arrivent bien
		-- apres que l'animation soit terminee, avec des delais tres reguliers
		-- mesures au sniffer :
		--   Spire  -> le coup tombe a t+1.35, +1.40, +1.40 s
		--   Dragon -> le coup tombe a t+3.87, +3.94 s
		-- Se caler sur la fin de l'animation (+1s) ne couvrait donc pas le
		-- Dragon : on etait deja revenu au contact quand le coup partait.
		-- 4.5s laisse une marge d'une demi-seconde apres le plus tardif observe.
		local DODGE_WINDOW_SECONDS = 4.5
		local M = {}

		function M.getDataEvent()
			return ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("DataEvent")
		end

		-- Anti-brulage Lavarossa : bloque le remote qui inflige les degats de
		-- lave/void progressifs, avant qu'il parte au serveur - actif
		-- uniquement pendant qu'Auto Boss tourne (state.enabled), pas en
		-- permanence. Confirme par decompile (data.lua ~15864 :
		-- DataEvent:FireServer("InflictFire", "extraLavaDamage"), declenche par
		-- le Touched du LocalScript du jeu au contact de Lava/LavarossaVoid) ET
		-- en live (~10 PV/seconde en restant dessus jusqu'a la mort) - bloquer
		-- ce couple action+raison coupe la chaine a la source sans toucher aux
		-- autres InflictFire (torches, ailments de combat). Ne protege PAS les
		-- zones "Void" a mort instantanee (ex: Hyuga) : testees en live sous
		-- toutes les coutures (retrait de part, blocage TakeDamage/KillMe,
		-- attribut FallDamageImmunity, bouclier physique) - rien ne marche,
		-- c'est un vrai Script serveur dont le bytecode n'est jamais envoye au
		-- client (decompile() -> "-- Empty bytecode") : kill entierement
		-- server-authoritative, aucune technique client ne peut le bypasser.
		do
			local DataEvent = M.getDataEvent()
			local oldNamecall
			oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
				if state.enabled and self == DataEvent then
					local method = getnamecallmethod()
					if method == "FireServer" or method == "fireServer" then
						local action, reason = ...
						if action == "InflictFire" and reason == "extraLavaDamage" then
							return
						end
					end
				end
				return oldNamecall(self, ...)
			end)
		end

		-- Notifier le Loot : meme webhook Discord enregistre que l'envoi auto
		-- d'inventaire (Prefs.InventoryWebhookUrl, page Settings) - meme
		-- pattern d'embed que sendInventoryToWebhook plus haut dans le
		-- fichier. Appelee depuis M.collectLoot une fois le ramassage
		-- termine, avec la liste des noms d'items reellement ramasses.
		function M.notifyLootWebhook(bossName, itemNames)
			if not request then return end
			if not Prefs.InventoryWebhookUrl or Prefs.InventoryWebhookUrl == "" then return end
			if #itemNames == 0 then return end

			local description = table.concat(itemNames, "\n")
			if #description > DISCORD_EMBED_DESCRIPTION_LIMIT then
				description = description:sub(1, DISCORD_EMBED_DESCRIPTION_LIMIT - 20) .. "\n... (tronque)"
			end

			local payload = {
				embeds = {
					{
						title = "Loot - " .. tostring(bossName) .. " (" .. LocalPlayer.Name .. ")",
						description = description,
						color = 7513855, -- Theme.Accent (114, 137, 255)
						timestamp = DateTime.now():ToIsoDate(),
					},
				},
			}

			pcall(request, {
				Url = Prefs.InventoryWebhookUrl,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload),
			})
		end

		-- Auto Equip Weapon (migre depuis une section a part - doit demarrer
		-- avec Auto Boss, pas tourner en fond independamment). Deux bugs
		-- trouves en live, dans l'ordre :
		--   1) Le combat ne ratait pas sans equip manuel (performM1 attaque
		--      toujours) mais utilisait CombatType="Fist" (mains nues) au
		--      lieu du CombatType de l'arme (ex: "Greatsword"). Le remote
		--      DataEvent:FireServer("Item", "Selected"/"Unselected", ...)
		--      (sequence exacte capturee d'un vrai clic) ne modifie RIEN
		--      d'observable, ni cote serveur (Settings) ni cote local - donc
		--      insuffisant seul. La vraie mise a jour vit dans une table
		--      d'etat locale (u32 dans le dump) inaccessible via getsenv mais
		--      recuperable comme upvalue de performM1 via debug.getupvalues -
		--      on l'ecrit directement (CombatType/CombatTable/WeaponEquipped/
		--      Selected), confirme persistant en live.
		--   2) ReplicatedStorage.Settings.<joueur>.CurrentWeapon (utilise au
		--      depart comme source du nom d'arme) ne represente PAS l'arme
		--      possedee/preferee du joueur mais l'etat de combat COURANT -
		--      constate en live a "Fist" pile pendant qu'on farmait a mains
		--      nues, donc le lire pour "restaurer l'arme" etait circulaire
		--      (ca ne faisait que reconfirmer Fist). La vraie source stable
		--      est une AUTRE table upvalue de performM1 (u11/donnees
		--      persistantes du joueur, identifiable par ses champs
		--      CurrentWeapon+Loadout) : u11.CurrentWeapon vaut bien "Golden
		--      Zabunagi" en live independamment de l'etat de combat momentane.
		-- Localise les upvalues de performM1 dont on a besoin. Recalcule a
		-- chaque appel (pas de cache) : le personnage/LocalScript peut changer
		-- au respawn, plus sur de ne jamais garder une reference perimee.
		function M.getWeaponUpvalues()
			local _, performM1 = M.getCombatFns()
			if not (performM1 and debug and debug.getupvalues) then return nil end
			local okUp, upvalues = pcall(debug.getupvalues, performM1)
			if not (okUp and upvalues) then return nil end

			local localState, gm, playerData
			for _, v in pairs(upvalues) do
				if typeof(v) == "table" then
					if localState == nil and v.CombatType ~= nil and v.WeaponEquipped ~= nil then
						localState = v
					elseif gm == nil and v.Items and v.getCombatTable then
						gm = v
					elseif playerData == nil and v.CurrentWeapon ~= nil and v.Loadout ~= nil then
						playerData = v
					end
				end
			end
			if not (localState and gm and playerData) then return nil end
			return localState, gm, playerData
		end

		-- Reaffirme uniquement l'etat local (pas de remote ici - trop
		-- couteux/spammy en continu). Confirme en live : apres un forcage
		-- ponctuel, le jeu revalide et reinitialise CombatType/WeaponEquipped
		-- une seule fois dans les ~2s qui suivent (retombe a "Fist"/false) -
		-- mais reaffirmer toutes les 0.1-0.2s empeche durablement ce reset
		-- (teste 6s sans coupure). Meme logique que le PlatformStand
		-- reaffirme chaque frame dans M.attachTo. Appele a chaque tick de la
		-- boucle principale de M.start(), pas juste une fois au demarrage.
		function M.reassertWeapon()
			local localState, gm, playerData = M.getWeaponUpvalues()
			if not (localState and gm and playerData) then return end
			local weaponName = playerData.CurrentWeapon
			if not (weaponName and weaponName ~= "") then return end
			local itemData = gm.Items[weaponName]
			if not (itemData and itemData.CombatType) then return end
			pcall(function()
				localState.CombatType = itemData.CombatType
				localState.CombatTable = gm:getCombatTable(itemData.CombatType)
				localState.WeaponEquipped = true
				localState.Selected = weaponName
			end)
		end

		-- Version "one-shot" appelee au demarrage d'Auto Boss (voir M.start) :
		-- reaffirme une premiere fois + tente le remote (best-effort, garde
		-- au cas ou il ait un effet cote serveur qu'on n'a pas pu observer -
		-- voir les notes plus haut, ce remote seul s'est montre inerte dans
		-- tous nos tests). La reaffirmation continue (M.reassertWeapon,
		-- appelee a chaque tick de boucle) est ce qui fait vraiment tenir
		-- l'etat dans la duree.
		function M.equipCurrentWeapon()
			M.reassertWeapon()
			local _, _, playerData = M.getWeaponUpvalues()
			local weaponName = playerData and playerData.CurrentWeapon
			if not (weaponName and weaponName ~= "") then return end
			local DataEvent = M.getDataEvent()
			if DataEvent then
				pcall(function() DataEvent:FireServer("Item", "Unselected", weaponName) end)
				task.wait(0.1)
				pcall(function() DataEvent:FireServer("Item", "Selected", weaponName) end)
			end
		end

		-- HUD (ScreenGui + panneau) affichant l'etat d'Auto Boss en permanence
		-- pendant qu'il est actif (pas seulement pendant l'attach) - demande
		-- explicitement plutot qu'un simple label dans le menu (souvent ferme
		-- pendant le farm). Memes donnees qu'avant (boss courant, PV, raison
		-- d'arret, phase) mais rangees autrement : la phase monte en haut a
		-- droite parce que c'est ce qu'on lit le plus souvent, le nom du boss et
		-- ses PV tiennent sur une seule ligne, et la barre passe de 22 a 6 px.
		-- 420x126 au lieu de 420x168 : un quart de hauteur en moins sans rien
		-- perdre. Le lisere d'accent vertical a saute : la phase coloree en haut
		-- a droite dit deja ce qu'il disait.
		-- state.hud est une table de labels - voir M.setHudState plus bas
		-- pour les mettre a jour ensemble.
		--
		-- On stocke des NOMS DE JETONS, pas des Color3 : sinon les couleurs
		-- seraient figees au chargement du script et ne suivraient pas les
		-- changements de theme (voir Skin en tete de fichier).
		local STAGE_COLORS = {
			Waiting = "SubText",
			Spawning = "Accent",
			Attacking = "Accent",
			Grip = "Accent",
			Looting = "Success",
			Paused = "Danger",
			Resuming = "Danger",
			Panic = "Danger",
		}

		function M.ensureHud()
			if state.hud then return state.hud end
			local gui = Instance.new("ScreenGui")
			gui.Name = "VonClientAutoBossHud"
			gui.ResetOnSpawn = false
			gui.IgnoreGuiInset = true
			gui.Parent = PlayerGui

			local root = Skin.paint(create("Frame", {
				Size = UDim2.new(0, 420, 0, 126),
				Position = UDim2.new(0.5, -210, 0, 16),
				BackgroundTransparency = 0.05,
				ClipsDescendants = true,
				Active = true,
				Visible = false,
			}, gui), { BackgroundColor3 = "Background" })
			corner(root, 5)
			Skin.paint(create("UIStroke", { Transparency = 0 }, root), { Color = "Stroke" })

			-- Draggable partout sur le panneau, meme mecanique que la fenetre
			-- principale (voir "Drag de la fenetre" plus haut dans le
			-- fichier) - juste ciblee sur root au lieu de Main.
			do
				local dragging, dragStart, startPos
				root.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = true
						dragStart = input.Position
						startPos = root.Position
						input.Changed:Connect(function()
							if input.UserInputState == Enum.UserInputState.End then dragging = false end
						end)
					end
				end)
				UserInputService.InputChanged:Connect(function(input)
					if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						local delta = input.Position - dragStart
						root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
					end
				end)
			end

			-- Bandeau : point d'etat + titre a gauche, phase a droite. Les deux
			-- prennent la couleur de la phase (STAGE_COLORS), c'est le seul
			-- endroit colore du HUD.
			local bandeau = Skin.paint(create("Frame", {
				Size = UDim2.new(1, 0, 0, 32),
			}, root), { BackgroundColor3 = "Panel" })
			Skin.paint(create("Frame", {
				Position = UDim2.new(0, 0, 1, -1),
				Size = UDim2.new(1, 0, 0, 1),
				BorderSizePixel = 0,
			}, bandeau), { BackgroundColor3 = "Stroke" })

			local statusDot = Skin.paint(create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0.5, 0),
				Size = UDim2.new(0, 7, 0, 7),
				BorderSizePixel = 0,
			}, bandeau), { BackgroundColor3 = "SubText" })
			corner(statusDot, 4)

			Skin.paint(create("TextLabel", {
				Position = UDim2.new(0, 24, 0, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = "AUTO BOSS",
				Font = Enum.Font.Code,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, bandeau), { TextColor3 = "SubText" })

			local stageLabel = Skin.paint(create("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.new(0.5, -12, 1, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.Code,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, bandeau), { TextColor3 = "Accent" })

			-- Nom du boss et PV sur la MEME ligne : c'est ce qui fait tomber la
			-- hauteur totale, les deux se lisent d'un seul coup d'oeil.
			local bossLabel = Skin.paint(create("TextLabel", {
				Position = UDim2.new(0, 12, 0, 40),
				Size = UDim2.new(1, -142, 0, 22),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, root), { TextColor3 = "Text" })

			local hpText = Skin.paint(create("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 40),
				Size = UDim2.new(0, 122, 0, 22),
				BackgroundTransparency = 1,
				Text = "-- / --",
				Font = Enum.Font.Code,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, root), { TextColor3 = "Text" })

			-- Barre de vie : 6 px au lieu de 22, le texte est passe au-dessus.
			-- Le remplissage vire Danger sous 25 % (comportement conserve) pour
			-- reperer la fenetre de Grip d'un coup d'oeil.
			local hpBarBack = Skin.paint(create("Frame", {
				Position = UDim2.new(0, 12, 0, 68),
				Size = UDim2.new(1, -24, 0, 6),
			}, root), { BackgroundColor3 = "Stroke" })
			corner(hpBarBack, 3)
			local hpBarFill = Skin.paint(create("Frame", {
				Size = UDim2.new(0, 0, 1, 0),
			}, hpBarBack), { BackgroundColor3 = "Accent" })
			corner(hpBarFill, 3)

			Skin.paint(create("Frame", {
				Position = UDim2.new(0, 12, 0, 88),
				Size = UDim2.new(1, -24, 0, 1),
				BorderSizePixel = 0,
			}, root), { BackgroundColor3 = "Stroke" })

			Skin.paint(create("TextLabel", {
				Position = UDim2.new(0, 12, 0, 95),
				Size = UDim2.new(0, 56, 0, 20),
				BackgroundTransparency = 1,
				Text = "RAISON",
				Font = Enum.Font.Code,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, root), { TextColor3 = "SubTextDim" })

			local reasonLabel = Skin.paint(create("TextLabel", {
				Position = UDim2.new(0, 74, 0, 95),
				Size = UDim2.new(1, -86, 0, 20),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamMedium,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, root), { TextColor3 = "SubText" })

			state.hud = { Root = root, StatusDot = statusDot, HpFill = hpBarFill, HpText = hpText, BossLabel = bossLabel, ReasonLabel = reasonLabel, StageLabel = stageLabel }
			M.setHudState("None", "Not Found Any Boss", "Waiting")
			M.setHudHealth(nil, nil)
			return state.hud
		end

		-- bossText : nom du boss actuel ou "None". reasonText : pourquoi
		-- Auto Boss ne farm pas actuellement (Chakra Sense, boss introuvable,
		-- ...) ou "None" si tout va bien. stageText : phase en cours
		-- (Waiting/Attacking/Grip/Looting/Paused...) - pilote aussi la couleur
		-- du point de statut et du texte de stage (STAGE_COLORS).
		function M.setHudState(bossText, reasonText, stageText)
			local hud = state.hud
			if not hud then return end

			-- Plus de crochets autour des valeurs : le nom du boss est
			-- maintenant le titre de la ligne, pas une donnee entre delimiteurs.
			-- "None" devient un vrai texte d'absence, en gris efface.
			local hasBoss = bossText and bossText ~= "None"
			hud.BossLabel.Text = hasBoss and tostring(bossText) or "Aucun boss"
			Skin.paint(hud.BossLabel, { TextColor3 = hasBoss and "Text" or "SubTextDim" })

			local quiet = (not reasonText) or reasonText == "None"
			hud.ReasonLabel.Text = quiet and "Aucune" or tostring(reasonText)

			hud.StageLabel.Text = string.upper(tostring(stageText))
			local token = STAGE_COLORS[stageText] or "SubText"
			Skin.paint(hud.StageLabel, { TextColor3 = token })
			Skin.paint(hud.StatusDot, { BackgroundColor3 = token })
			-- Une raison presente pendant une phase d'alerte (Paused/Panic) est
			-- la vraie information a lire : elle passe en Danger comme la phase.
			Skin.paint(hud.ReasonLabel, { TextColor3 = (not quiet and token == "Danger") and "Danger" or "SubText" })

			MenuChrome.setStatus(hasBoss and bossText or nil, state.hudHp, state.hudHpMax)
		end

		-- Mise a jour de la barre de vie, appelee a chaque frame depuis le
		-- RenderStep de M.attachTo (voir plus bas) - separee de M.setHudState
		-- (mise a jour cote boucle principale, 0.1s) pour que la barre reste
		-- fluide pendant le combat. current/max nil -> etat vide ("-- / --").
		function M.setHudHealth(current, max)
			local hud = state.hud
			if not hud then return end
			if not (current and max and max > 0) then
				state.hudHp, state.hudHpMax = nil, nil
				hud.HpFill.Size = UDim2.new(0, 0, 1, 0)
				hud.HpText.Text = "-- / --"
				return
			end
			state.hudHp = math.max(0, math.floor(current))
			state.hudHpMax = math.floor(max)
			local pct = math.clamp(current / max, 0, 1)
			tween(hud.HpFill, { Size = UDim2.new(pct, 0, 1, 0) }, 0.15)
			Skin.paint(hud.HpFill, { BackgroundColor3 = pct <= 0.25 and "Danger" or "Accent" })
			hud.HpText.Text = string.format("%d / %d", state.hudHp, state.hudHpMax)
		end

		function M.getCombatFns()
			local clientGui = PlayerGui:FindFirstChild("ClientGui")
			local clientScript = clientGui and clientGui:FindFirstChild("LocalScript")
			if not (clientScript and getsenv) then return nil end
			local ok, env = pcall(getsenv, clientScript)
			if not (ok and env) then return nil end
			return env.canM1, env.performM1
		end

		-- attached=true (accroche) : plus de collisions ET PlatformStand=true
		-- sur NOTRE Humanoid - sans ca, le Humanoid du jeu (Freefall en l'air)
		-- se bat contre le CFrame qu'on pose chaque frame, ce qui donnait le
		-- "ca bouge trop / pas un point fixe" observe en jeu. Confirme en
		-- live via Potassium : avec PlatformStand=true, zero degat encaisse
		-- sur 3s et la seule variation mesuree est le deplacement reel du
		-- boss (pas du jitter).
		function M.setAttachedPhysics(attached)
			local character = LocalPlayer.Character
			if not character then return end
			local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			if humanoid then
				humanoid.PlatformStand = attached
				if not attached then
					-- PlatformStand=false tout seul ne "reveille" pas toujours
					-- la machine a etats du Humanoid (mouvement bloque/glisse
					-- apres l'attach, corrige avant seulement en activant/
					-- desactivant Noclip a la main) - forcer GettingUp remet
					-- une locomotion normale, et on remet la vitesse residuelle
					-- a zero (les teleports CFrame pendant l'attach/le loot
					-- peuvent laisser une vitesse "fantome" que Roblox
					-- reapplique brutalement des que le mouvement normal
					-- reprend, d'ou le glissement/decollage observe).
					pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
					local rootPart = character:FindFirstChild("HumanoidRootPart")
					if rootPart then
						-- Ancrage bref en plus de la vitesse a zero : bloque
						-- completement la physique pendant l'instant ou on
						-- rend la main, pour eviter tout glissement residuel.
						local wasAnchored = rootPart.Anchored
						rootPart.Anchored = true
						rootPart.AssemblyLinearVelocity = Vector3.zero
						rootPart.AssemblyAngularVelocity = Vector3.zero
						task.wait()
						rootPart.Anchored = wasAnchored
					end
				end
			end
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = not attached
				end
			end
		end

		-- Teleport "propre" : ancre la piece le temps du saut de CFrame,
		-- plutot qu'un simple rootPart.CFrame = ... . Confirme en jeu que des
		-- CFrame repetes sur un personnage sous controle physique normal
		-- (CanCollide=true, PlatformStand=false - donc apres detach, pendant
		-- le loot) donnent un glissement visible malgre la vitesse remise a
		-- zero juste apres : ancrer bloque completement la physique le temps
		-- du saut, ce qui l'empeche d'interpoler/lisser le deplacement.
		function M.teleportRootPart(rootPart, position)
			local wasAnchored = rootPart.Anchored
			rootPart.Anchored = true
			rootPart.CFrame = CFrame.new(position)
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			task.wait()
			rootPart.Anchored = wasAnchored
		end

		-- Pas de filtre sur Health > 0 : le boss reste "trouve" tant que le
		-- Model existe encore dans workspace, meme a 0 HP. Avec le filtre
		-- d'avant, on considerait le boss "introuvable" pile a 0 HP et on se
		-- detachait tout de suite - au moment ou il faut justement rester
		-- attache pour le grip. Voir M.start() pour la distinction
		-- attaque (Health > 0) / grip (Health < seuil).
		-- Transition "boss vivant -> boss mort", partagee entre le cas normal
		-- (Model retire de workspace, voir la branche `else` de M.start) et le
		-- cas Health<=0 avec Model encore present (voir plus bas : observe en
		-- live sur Lavarossa grippe en etant enflamme - le statut Brulure
		-- semble retarder la suppression du Model, du coup M.findBoss()
		-- continuait a le "trouver" et le loot ne se declenchait jamais).
		-- Le palier Health=1 pendant l'etat "a terre" (voir bossDowned plus
		-- bas) est deja bien etabli en live sur les 3 boss geres ici - Health
		-- <= 0 ne peut donc arriver qu'apres un Grip reussi, jamais pendant
		-- l'attente du Grip.
		function M.markBossGone()
			if not state.bossPresent then return end
			state.bossPresent = false
			state.deadSince = nil
			state.lowHealthSince = nil
			if state.attached then
				M.detach()
			end
			state.lootPending = true
			M.setHudHealth(nil, nil)
		end

		-- Certains boss ont des variantes de quete (ex: "Barbarit The
		-- Hallowed", "Hallowed Chakra Knight" - voir data2.lua, GameManager.
		-- NPC) qui partagent le meme texte de dialogue que le vrai boss et se
		-- retrouvent nommees PAREIL dans workspace ("Barbarit The Rose"),
		-- mais avec des stats differentes (MaxHealth=900 au lieu de 750 pour
		-- Barbarit) - confirme en live : Auto Boss s'est attache a l'une
		-- d'elles au lieu du vrai world boss. FindFirstChild seul ne peut pas
		-- les distinguer (retourne juste le premier trouve), donc on scanne
		-- TOUS les enfants du meme nom. Le check MaxHealth seul s'est montre
		-- insuffisant en pratique (constate en live : toujours arrive de
		-- prendre la mauvaise instance) - filtre de proximite en plus, pour
		-- les boss avec spawnFloor (Lavarossa/Barbarit) : le vrai world boss
		-- spawne toujours pres du Part d'activation (BarbaritFloor,
		-- LavarossaFloor...) qu'on utilise deja pour le reveiller (voir
		-- M.trySpawnBoss) - pas besoin de capturer une position separee, on
		-- reutilise directement Position de ce meme Part. Tolerance large
		-- (500 studs) car ce Part n'est pas pile au point de spawn exact,
		-- juste dans la meme zone - largement suffisant pour exclure une
		-- variante de quete qui erre ailleurs sur la carte.
		-- Cherche un boss precis par son nom (voir M.findBoss - separee pour
		-- pouvoir prioriser explicitement state.lastBossName avant de scanner
		-- tous les autres boss configures).
		function M.findBossByName(name)
			local config = BOSS_CONFIGS[name]
			if not (config and Settings.AutoBossSelected[name]) then return nil end
			local npcData = GameManager.NPC and GameManager.NPC[name]
			local spawnFloor = config.spawnFloor and workspace:FindFirstChild(config.spawnFloor)
			for _, model in ipairs(workspace:GetChildren()) do
				if model.Name == name then
					local humanoid = model:FindFirstChild("Humanoid")
					local healthOk = humanoid and (not npcData or humanoid.MaxHealth == npcData.MaxHealth)
					local positionOk = true
					if healthOk and spawnFloor then
						local hrp = model:FindFirstChild("HumanoidRootPart")
						positionOk = hrp ~= nil and (hrp.Position - spawnFloor.Position).Magnitude <= (config.spawnRadius or 500)
					end
					if healthOk and positionOk then
						return model, config
					end
				end
			end
			return nil
		end

		-- Cherche UNIQUEMENT le boss deja engage (state.lastBossName), sans
		-- jamais se rabattre sur un autre boss selectionne. Recherche
		-- allegee (nom + Humanoid seulement, pas de re-verification
		-- MaxHealth/position) : son identite a deja ete confirmee au moment
		-- de l'engagement initial (voir M.findBossByName, utilise seulement
		-- pour denicher un NOUVEAU boss). Reconstate en live sur Lavarossa :
		-- le filtre strict (MaxHealth) peut echouer momentanement PENDANT la
		-- sequence de mort du cadavre encore present.
		function M.findCurrentBoss()
			if not (state.lastBossName and Settings.AutoBossSelected[state.lastBossName]) then
				return nil
			end
			local model = workspace:FindFirstChild(state.lastBossName)
			if model and model:FindFirstChild("Humanoid") then
				return model, BOSS_CONFIGS[state.lastBossName]
			end
			return nil
		end

		function M.findBoss()
			-- Tant qu'un boss est deja engage, NE JAMAIS se rabattre sur un
			-- autre boss selectionne, meme si celui-ci vient de disparaitre
			-- (mort) - sinon pairs(BOSS_CONFIGS) peut retourner un AUTRE boss
			-- deja selectionne au meme tick (ex: Tairock qui vient de
			-- respawn, ou Chakra Knight deja present) au lieu de laisser
			-- M.findBoss() renvoyer nil pour ce boss-la, ce qui est
			-- justement le signal dont M.start() a besoin pour declencher
			-- M.markBossGone() et demarrer la phase loot. Constate en live a
			-- plusieurs reprises (Barbarit->Tairock, Lavarossa->Chakra
			-- Knight, Chakra Knight->un autre) : le loot ne se declenchait
			-- jamais car un boss de remplacement etait trouve avant que la
			-- transition de mort du bon boss n'ait eu lieu. state.lastBossName
			-- n'est remis a nil qu'une fois le loot vraiment termine (voir
			-- M.start()) - c'est CA qui rouvre la recherche d'un nouveau
			-- boss, pas juste le fait que l'ancien ait disparu.
			if state.lastBossName then
				return M.findCurrentBoss()
			end

			for name in pairs(BOSS_CONFIGS) do
				local boss, config = M.findBossByName(name)
				if boss then
					return boss, config
				end
			end
			return nil
		end

		-- Pour les boss avec spawnFloor/spawnEvent (voir BOSS_CONFIGS) :
		-- teleporte sur le Part d'activation et declenche le remote tant que
		-- son StringValue "Activated" vaut "" (pret). Cooldown de 5s par boss
		-- entre deux tentatives - le spawn du Model prend quelques secondes et
		-- Activated ne change pas forcement instantanement, pas la peine de
		-- spammer FireServer a chaque tick (0.1s) de la boucle principale.
		-- Retourne true si une tentative vient d'etre faite (le boucle
		-- appelante saute alors le repli "boss introuvable -> Safe Spot").
		function M.trySpawnBoss()
			local now = os.clock()
			for name, config in pairs(BOSS_CONFIGS) do
				if Settings.AutoBossSelected[name] and config.spawnFloor then
					local floor = workspace:FindFirstChild(config.spawnFloor)
					local activated = floor and floor:FindFirstChild("Activated")
					if floor and activated and activated.Value == "" then
						if now - (state.lastSpawnAttempt[name] or 0) >= 5 then
							state.lastSpawnAttempt[name] = now
							local character = LocalPlayer.Character
							local rootPart = character and character:FindFirstChild("HumanoidRootPart")
							if rootPart then
								M.teleportRootPart(rootPart, floor.Position + Vector3.new(0, 5, 0))
							end
							local DataEvent = M.getDataEvent()
							if DataEvent then
								pcall(function() DataEvent:FireServer(config.spawnEvent) end)
							end
						end
						return true
					end
				end
			end
			return false
		end

		-- HumanoidRootPart plutot que Head : reste centre/stable, alors que
		-- Head bouge avec les animations d'attaque du boss - confirme en live
		-- que ca donne un suivi net (Head donnait le "chelou" observe).
		function M.getBossAnchor(boss)
			return boss:FindFirstChild("HumanoidRootPart") or boss.PrimaryPart or boss:FindFirstChild("Head")
		end

		-- GetDescendants et pas GetChildren : la hierarchie n'est pas la meme
		-- partout. Chez la plupart des boss (Manda, Tairock...) les TrinketSpawn
		-- sont des enfants directs du modele de recompenses, mais chez le Wooden
		-- Golem ils sont ranges dans DEUX sous-Model intermediaires. Avec
		-- GetChildren on n'en trouvait aucun, donc M.collectLoot repartait
		-- aussitot (#spawns == 0 -> "done") sans jamais looter, et en silence.
		function M.getTrinketSpawns(rewards)
			local spawns = {}
			for _, part in ipairs(rewards:GetDescendants()) do
				if part:IsA("BasePart") and part.Name:match("^TrinketSpawn") then
					table.insert(spawns, part)
				end
			end
			return spawns
		end

		-- Les vrais items ramassables ne sont PAS des enfants de TrinketSpawnN
		-- (ceux-la ne recoivent qu'un marqueur "Occupied" - piege qui a fait
		-- echouer la premiere version) : ce sont des MeshPart parentes
		-- directement a Workspace, avec un enfant "ObjectValue" qui pointe
		-- vers leur TrinketSpawnN d'origine. On s'en sert pour ne prendre que
		-- le loot de CE rewardsModel (confirme en live via Potassium : items
		-- "Spark Gem"/"Life Up Fruit"/etc, chacun avec Pickupable/Active/ID/
		-- ObjectValue).
		-- IsDescendantOf et pas "Parent == rewards" : meme raison que dans
		-- M.getTrinketSpawns. Le TrinketSpawn vise par l'ObjectValue peut etre
		-- range dans un sous-Model (Wooden Golem), auquel cas son Parent n'est
		-- pas le modele de recompenses mais le sous-Model - la comparaison
		-- directe echouait et aucun item n'etait jamais reconnu.
		-- IsDescendantOf couvre aussi le cas plat des autres boss.
		function M.findRewardItems(rewards)
			local items = {}
			for _, obj in ipairs(workspace:GetChildren()) do
				local link = obj:FindFirstChild("ObjectValue")
				if obj:FindFirstChild("Pickupable") and link and link.Value and link.Value:IsDescendantOf(rewards) then
					table.insert(items, obj)
				end
			end
			return items
		end

		-- Confirmation post-settle (voir M.collectLoot) : apres les 5s
		-- d'attente a lootWaitPosition, verifie qu'au moins un item est bien
		-- visible avant de foncer sur le ramassage - protege contre un spawn
		-- serveur anormalement lent (rare, mais evite de looter dans le vide).
		-- S'arrete aussi immediatement si une menace Chakra Sense apparait.
		function M.waitForLoot(rewards, timeoutSeconds)
			local deadline = os.clock() + timeoutSeconds
			while os.clock() < deadline do
				if Settings.AutoBossPauseOnChakraSense and isChakraSenseThreatActive() then return false end
				if #M.findRewardItems(rewards) > 0 then return true end
				task.wait(0.2)
			end
			return false
		end

		-- Auto loot : le vrai pickup n'est pas un contact physique mais un
		-- clic (mouse.Target sur l'item en jeu), confirme par l'utilisateur
		-- via un dump decompile (Cobalt) : DataEvent:FireServer("PickUp",
		-- ID.Value). mouse.Target est purement une condition d'input cote
		-- client pour declencher l'action ; le serveur ne voit que l'ID
		-- envoye, donc pas besoin de simuler une souris - on lit ID.Value
		-- directement sur l'item (voir M.findRewardItems) et on tire le
		-- remote nous-memes. Garde-fou "ClearedToPickUp" (liste de noms
		-- autorises a looter, anti ninja-loot) pas verifie ici, le serveur
		-- l'appliquera de toute facon.
		-- Retourne "done" (termine, rien de plus a faire - meme si rien
		-- trouve) ou "interrupted" (menace Chakra Sense detectee en cours de
		-- route) : permet a M.start() de savoir s'il faut reessayer plus
		-- tard sans perdre le fil (le loot reste au sol tant qu'il n'est pas
		-- ramasse, donc rappeler cette fonction plus tard reprend
		-- naturellement la ou on s'est arrete).
		function M.collectLoot(config)
			if not (config and config.rewardsModel) then return "done" end
			local rewards = workspace:FindFirstChild(config.rewardsModel)
			if not rewards then
				-- Le nommage de ces modeles est irregulier cote jeu
				-- ("ChakraKnightRewards" sans espace mais "Hyuga BossRewards"
				-- avec) : un nom mal orthographie dans BOSS_CONFIGS rendait la
				-- phase de loot silencieusement inoperante, indiscernable d'un
				-- "il n'y avait rien a ramasser". On le dit maintenant.
				notify("Loot impossible : aucun modele '" .. config.rewardsModel .. "' dans workspace.", "error")
				return "done"
			end

			local character = LocalPlayer.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart then return "done" end

			local DataEvent = M.getDataEvent()
			if not DataEvent then return "done" end

			local spawns = M.getTrinketSpawns(rewards)
			if #spawns == 0 then return "done" end

			local function threatened()
				return Settings.AutoBossPauseOnChakraSense and isChakraSenseThreatActive()
			end

			-- Se teleporter a lootWaitPosition (centre entre tous les
			-- TrinketSpawn, capture en live - repli sur spawns[1] si pas
			-- encore capturee pour ce boss) et attendre 5s SUR PLACE avant de
			-- commencer a looter, plutot que de foncer des le premier trinket
			-- vu : laisse le temps a tous les autres de spawner.
			M.teleportRootPart(rootPart, config.lootWaitPosition or spawns[1].Position)

			local LOOT_SETTLE_SECONDS = 5
			local settleDeadline = os.clock() + LOOT_SETTLE_SECONDS
			while os.clock() < settleDeadline do
				if threatened() then return "interrupted" end
				task.wait(0.2)
			end

			-- Confirme qu'il y a bien quelque chose a looter apres le settle -
			-- 10s max (au lieu de 5s) : un settle qui se termine pile avant
			-- que le premier trinket spawn ne doit pas conclure "rien a
			-- looter" et repartir prematurement, mieux vaut attendre un peu
			-- plus avant d'abandonner.
			if threatened() then return "interrupted" end
			if not M.waitForLoot(rewards, 10) then
				return threatened() and "interrupted" or "done" -- "done" = rien a looter (timeout normal)
			end

			-- Nom des items presents AVANT le ramassage (voir plus bas : sert
			-- a calculer ce qui a vraiment ete ramasse pour la notif Discord,
			-- par difference avec ce qui reste apres - plus fiable que
			-- d'accumuler pendant pickUpAll, qui peut retenter le meme item
			-- deux fois sur le deuxieme passage sans que ca veuille dire
			-- deux ramassages distincts).
			local initialNames = {}
			for _, item in ipairs(M.findRewardItems(rewards)) do
				table.insert(initialNames, item.Name)
			end

			-- Portee courte requise pour que le PickUp soit accepte cote
			-- serveur (confirme en live : ~3 studs marche, ~11-17 studs non,
			-- meme avec un ID valide et Active=true) - il faut se deplacer
			-- SUR chaque item individuellement, pas juste une fois vers
			-- spawns[1] (les items sont disperses sur les differents
			-- TrinketSpawnN, potentiellement loin les uns des autres).
			local function pickUpAll()
				for _, item in ipairs(M.findRewardItems(rewards)) do
					if threatened() then return false end
					local idValue = item:FindFirstChild("ID")
					local activeValue = item:FindFirstChild("Active")
					if idValue and (not activeValue or activeValue.Value ~= false) then
						M.teleportRootPart(rootPart, item.Position)
						task.wait(0.3)
						pcall(function()
							DataEvent:FireServer("PickUp", idValue.Value)
						end)
						task.wait(0.3)
					end
				end
				return true
			end

			if not pickUpAll() then return "interrupted" end

			-- Deuxieme passage pour les items encore la (arrives en retard,
			-- premier essai rate...), puis verification finale.
			task.wait(0.5)
			if threatened() then return "interrupted" end
			if not pickUpAll() then return "interrupted" end

			task.wait(0.3)
			local stillThere = M.findRewardItems(rewards)
			local missed = #stillThere
			if missed > 0 then
				notify(missed .. " loot(s) pas ramasse(s) sur " .. config.rewardsModel .. " (peut-etre pas autorise via ClearedToPickUp).", "error")
			end

			if Settings.NotifyLootEnabled and #initialNames > missed then
				-- Difference multiset (initialNames - stillThere) plutot
				-- qu'une simple soustraction de comptes : gere correctement
				-- les noms d'items dupliques.
				local remaining = {}
				for _, item in ipairs(stillThere) do
					remaining[item.Name] = (remaining[item.Name] or 0) + 1
				end
				local collectedNames = {}
				for _, name in ipairs(initialNames) do
					if remaining[name] and remaining[name] > 0 then
						remaining[name] = remaining[name] - 1
					else
						table.insert(collectedNames, name)
					end
				end
				M.notifyLootWebhook(state.lastBossName or config.rewardsModel, collectedNames)
			end

			return "done"
		end

		-- Sub (jutsu de substitution) : DataEvent:FireServer("Dash", "Sub",
		-- position) confirme dans le dump decompile de ClientGui.LocalScript
		-- (print "SUBBED" juste avant ce FireServer). Cooldown lu depuis
		-- ReplicatedStorage.Settings.<joueur>.SubCooldown (timestamp serveur
		-- du dernier Sub) compare a GameManager.Settings.SubCooldown (duree)
		-- via workspace:GetServerTimeNow(), comme le fait le vrai client -
		-- evite de spammer le remote pour rien pendant le cooldown. Retraite
		-- vers le haut (on est deja cense etre au-dessus du boss) plutot
		-- qu'une direction aleatoire. Reduit les degats au lieu de les
		-- annuler completement, donc ne remplace pas un bon positionnement -
		-- filet de securite en plus, comme demande.
		function M.trySubstitute()
			local DataEvent = M.getDataEvent()
			local character = LocalPlayer.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not (DataEvent and rootPart) then return end

			local cooldownOk, cooldownValue = pcall(function()
				return ReplicatedStorage.Settings[LocalPlayer.Name].SubCooldown.Value
			end)
			if cooldownOk and cooldownValue then
				local elapsed = workspace:GetServerTimeNow() - cooldownValue
				if elapsed < (GameManager.Settings.SubCooldown or 0) then return end
			end

			local escapePosition = (rootPart.CFrame * CFrame.new(0, 15, 0)).Position
			pcall(function()
				DataEvent:FireServer("Dash", "Sub", escapePosition)
			end)
		end

		function M.watchHealth()
			if state.healthConn then
				state.healthConn:Disconnect()
				state.healthConn = nil
			end
			local character = LocalPlayer.Character
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			if not humanoid then return end
			local lastHealth = humanoid.Health
			state.healthConn = track(humanoid.HealthChanged:Connect(function(newHealth)
				if state.enabled and newHealth < lastHealth then
					M.trySubstitute()
				end
				lastHealth = newHealth
			end))
		end

		-- Reaccroche le suivi de vie si le personnage respawn pendant que
		-- Auto Boss est actif (meme principe que le CharacterAdded du Fly
		-- plus haut dans le fichier).
		track(LocalPlayer.CharacterAdded:Connect(function()
			if unloaded then return end
			if state.enabled then
				task.wait(0.5)
				if state.enabled and not unloaded then M.watchHealth() end
			end
		end))

		-- Attach reel sur le HumanoidRootPart du boss, pas un simple
		-- repositionnement au polling toutes les 0.1s (trop lent : le boss
		-- bouge entre deux mises a jour et peut toucher le joueur). Meme
		-- esprit que "Attach To Back" dans old cheat.lua (CFrame relatif a la
		-- cible, pas juste une position neutre).
		-- BindToRenderStep a priorite Last (pas RunService.Stepped) : garantit
		-- qu'on ecrit le CFrame APRES tout autre systeme lie a Stepped/
		-- RenderStepped ce frame-la (le controleur de personnage du jeu
		-- notamment), qui pouvait sinon re-appliquer une rotation juste apres
		-- nous et donner le "en biais" observe en jeu malgre un
		-- CFrame.Angles(-90,0,0) mathematiquement correct (verifie en live :
		-- LookVector imprime = (0,-1,0) exact). On remet aussi les vitesses
		-- lineaire/angulaire residuelles a zero : sans ca l'elan physique
		-- d'avant l'attach peut encore se voir malgre le CFrame force.
		local ATTACH_ROTATION = CFrame.Angles(math.rad(-90), 0, 0)
		local ATTACH_STEP_NAME = "VonClientAutoBossAttach"
		-- Portee de Grip verifiee en live sur Barbarit The Rose : depuis le
		-- hover normal (12 studs), Gripping.Value reste "None" (rejet
		-- silencieux cote serveur) ; a ~0.3 stud, Gripping bascule dessus et
		-- le boss finit par disparaitre. Applique a tous les boss (pas
		-- seulement Barbarit) - sans danger pour ceux ou l'ancien offset
		-- marchait deja (juste un aller-retour de plus, invisible en jeu).
		local GRIP_APPROACH_OFFSET = Vector3.new(0, 3, 0)

		-- Seule source de verite pour "est-on en train d'esquiver ?" : soit une
		-- animation d'esquive joue encore, soit on est dans la marge gardee juste
		-- apres (DODGE_HOLD_SECONDS). Tout le reste du module doit passer par ici
		-- plutot que de lire state.dodging directement, sinon la marge est ignoree.
		function M.isDodging()
			return state.dodgeActiveCount > 0 or os.clock() < state.dodgeUntil
		end

		function M.attachTo(boss, config)
			M.setAttachedPhysics(true)
			state.attached = true
			M.ensureHud()
			state.dodging = false
			state.dodgeActiveCount = 0
			state.dodgeUntil = 0
			state.gripping = false

			-- dodgeAnimationIds (voir BOSS_CONFIGS, ex: Chakra Knight) : bascule
			-- vers dodgeOffset tant qu'AU MOINS UNE de ces AnimationTrack joue
			-- sur le boss, revient a attachOffset quand la derniere s'arrete.
			-- Compteur plutot qu'un simple booleen : gere le cas ou deux
			-- pistes de la liste se chevauchent (l'arret de l'une ne doit pas
			-- annuler le dodge tant que l'autre joue encore). Un seul hook
			-- pour toute la duree de l'attach (pas par frame) - AnimationPlayed
			-- fournit directement l'AnimationTrack, pas besoin de polling.
			if state.dodgeAnimConn then
				state.dodgeAnimConn:Disconnect()
				state.dodgeAnimConn = nil
			end
			if config.dodgeAnimationIds then
				local bossHumanoid = boss:FindFirstChild("Humanoid")
				if bossHumanoid then
					state.dodgeAnimConn = bossHumanoid.AnimationPlayed:Connect(function(animTrack)
						local anim = animTrack.Animation
						local id = anim and tostring(anim.AnimationId)
						if not id then return end
						local matched = false
						for _, dodgeId in ipairs(config.dodgeAnimationIds) do
							if id:find(dodgeId, 1, true) then
								matched = true
								break
							end
						end
						if not matched then return end
						state.dodgeActiveCount = state.dodgeActiveCount + 1
						state.dodging = true
						-- La fenetre part d'ICI, du debut de l'animation : c'est le
						-- seul repere temporel fiable pour les degats (voir
						-- DODGE_WINDOW_SECONDS). Un nouveau declenchement pendant une
						-- esquive en cours repousse l'echeance, jamais ne la raccourcit.
						state.dodgeUntil = math.max(state.dodgeUntil, os.clock() + DODGE_WINDOW_SECONDS)
						-- dodgeCyclePositions (ex: Wooden Golem) : declenche aussi le Sub
						-- (M.trySubstitute, jutsu de substitution - voir plus haut) DES LE
						-- DEBUT du dodge, en plus du cyclage ancre. M.trySubstitute est
						-- deja appele reactivement sur toute perte de PV (M.watchHealth),
						-- mais la, proactif : le Sub est un vrai FireServer reconnu par le
						-- serveur (contrairement a notre CFrame purement client), donc plus
						-- fiable pour mettre a jour la position que le serveur croit etre
						-- la notre au moment ou le danger commence. Cooldown-gate deja
						-- gere en interne par M.trySubstitute, donc sans risque de spam.
						if config.dodgeCyclePositions then
							pcall(M.trySubstitute)
						end
						-- :Once() pas garanti sur tous les executeurs (voir
						-- CLAUDE.md) - Connect + auto-disconnect a la main.
						local stoppedConn
						stoppedConn = animTrack.Stopped:Connect(function()
							state.dodgeActiveCount = math.max(0, state.dodgeActiveCount - 1)
							state.dodging = state.dodgeActiveCount > 0
							-- Rien a faire de plus ici : c'est state.dodgeUntil,
							-- arme au DEBUT de l'animation, qui decide quand on
							-- revient au contact (voir M.isDodging).
							stoppedConn:Disconnect()
						end)
					end)
				end
			end

			RunService:BindToRenderStep(ATTACH_STEP_NAME, Enum.RenderPriority.Last.Value, function()
				local character = LocalPlayer.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local anchor = boss.Parent and M.getBossAnchor(boss)
				if not (rootPart and anchor) then return end

				-- Reaffirme PlatformStand a CHAQUE frame plutot qu'une seule
				-- fois au debut de l'attach : confirme en live que le jeu peut
				-- le repasser a false en cours de route (notre etat retombe
				-- alors en Freefall sans que state.attached ne s'en rende
				-- compte, ce qui semble faire rejeter le Grip cote serveur -
				-- Grip exige probablement de ne pas etre en Freefall).
				local humanoid = character:FindFirstChildWhichIsA("Humanoid")
				if humanoid and not humanoid.PlatformStand then
					humanoid.PlatformStand = true
				end

				-- dodgeCyclePositions (ex: Wooden Golem, Spire/Dragon) : contrairement a
				-- dodgeOffset (relatif au boss), ce sont des positions ABSOLUES fixes de
				-- l'arene. Cycle a 10 Hz (rythme mesure sur le script de reference).
				--
				-- SURTOUT : NE PAS ancrer le rootPart ici. Ca a ete essaye - la
				-- derive hors des 4 coins disparaissait bien - mais le sniffer a
				-- montre que c'etait le remede pire que le mal :
				--   nous, anch=true  -> -22, -29, -21 PV sur trois attaques
				--   reference, anch=false -> 0, 0, -10 PV, memes coins, meme cadence
				-- Un HumanoidRootPart ancre n'est plus simule par la physique, donc
				-- le client cesse de repliquer sa position : le serveur continue de
				-- nous croire la ou on etait avant, pres du boss, en pleine zone
				-- d'effet. Le cyclage devient purement visuel pendant que le serveur
				-- applique les degats sur l'ancienne position. Sans ancrage, la
				-- replication suit et le serveur nous voit vraiment dans le coin.
				-- (Verifie aussi : les degats ne viennent PAS des pics de sol -
				-- aucun WormBranch n'est apparu pendant ces trois attaques.)
				local dodging = M.isDodging()
				local targetPosition
				if dodging and config.dodgeCyclePositions then
					local positions = config.dodgeCyclePositions
					local index = (math.floor(os.clock() * 10) % #positions) + 1
					targetPosition = positions[index]
				else
					local offset = state.gripping and GRIP_APPROACH_OFFSET or (dodging and config.dodgeOffset) or config.attachOffset
					targetPosition = anchor.Position + offset
				end
				if rootPart.Anchored then
					rootPart.Anchored = false
				end
				rootPart.CFrame = CFrame.new(targetPosition) * ATTACH_ROTATION
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
				-- Le panneau (Current Boss/Stop Reason/Stage) est mis a jour
				-- depuis la boucle principale de M.start() (voir M.setHudState),
				-- pas ici : elle a deja acces au nom du boss et a la raison
				-- courante, pas la peine de dupliquer. La barre de vie par
				-- contre est mise a jour ici, a chaque frame, pour rester
				-- fluide pendant le combat (la boucle principale ne tick qu'a
				-- 0.1s).
				local bossHumanoid = boss:FindFirstChild("Humanoid")
				if bossHumanoid then
					M.setHudHealth(bossHumanoid.Health, bossHumanoid.MaxHealth)
				end
			end)
		end

		function M.detach()
			pcall(function() RunService:UnbindFromRenderStep(ATTACH_STEP_NAME) end)
			if state.dodgeAnimConn then
				state.dodgeAnimConn:Disconnect()
				state.dodgeAnimConn = nil
			end
			state.dodging = false
			state.dodgeActiveCount = 0
			-- Au cas ou le detach arrive EN PLEIN dodgeCyclePositions (boss qui
			-- meurt/disparait pendant Spire/Dragon) : le RenderStep qui remettait
			-- Anchored=false vient d'etre coupe, donc le faire ici pour ne pas
			-- laisser le personnage bloque ancre.
			local character = LocalPlayer.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart.Anchored then
				rootPart.Anchored = false
			end
			state.gripping = false
			-- Le panneau reste visible apres un detach (loot/pause en cours,
			-- voir M.stop() pour le seul vrai moment ou il se cache).
			if state.attached then
				M.setAttachedPhysics(false)
				state.attached = false
				-- Reproduit le contournement manuel (activer puis desactiver
				-- le Noclip) qui debloquait le mouvement de facon fiable,
				-- malgre l'ancrage/vitesse-a-zero/GettingUp deja en place -
				-- automatise ici en dernier recours puisque le probleme
				-- persiste malgre ca.
				pcall(setNoclip, true)
				task.wait(0.2)
				pcall(setNoclip, false)
			end
		end

		function M.stop()
			state.enabled = false
			state.token = state.token + 1
			M.detach()
			if state.healthConn then
				state.healthConn:Disconnect()
				state.healthConn = nil
			end
			if state.hud then state.hud.Root.Visible = false end
		end

		function M.start()
			state.token = state.token + 1
			local myToken = state.token
			state.enabled = true
			local canM1, performM1 = M.getCombatFns()
			if not (canM1 and performM1) then
				notify("Impossible de recuperer les fonctions de combat (canM1/performM1). Auto Boss desactive.", "error")
				state.enabled = false
				return
			end
			M.watchHealth()
			M.ensureHud().Root.Visible = true
			M.setHudState("None", "None", "Waiting")
			if Settings.AutoEquipWeaponEnabled then
				M.equipCurrentWeapon()
			end

			task.spawn(function()
				-- Meme logique que l'autre script : verifie que le boss est
				-- bien spawn AVANT de tenter quoi que ce soit. S'il ne l'est
				-- pas (mort, pas encore apparu...), ramasse d'abord le loot
				-- (voir M.collectLoot) si on venait de quitter un boss
				-- attache, PUIS notifie et retp au Safe Spot - notifiedMissing
				-- evite de spammer la notif/le tp a chaque tick tant que le
				-- boss reste absent. L'attach lui-meme est gere par
				-- M.attachTo/M.detach (voir BindToRenderStep au-dessus) ;
				-- cette boucle detecte le boss, tente l'attaque et tente le
				-- Grip une fois sous 50 HP ("finir" le boss a terre - DataEvent
				-- :FireServer("Grip"), touche B, confirme dans le dump
				-- decompile). Le grip ne prend pas de cible en argument (le
				-- serveur la determine tout seul) et la condition exacte cote
				-- client (boss "a terre") n'a pas pu etre verifiee en live,
				-- donc on le retente juste toutes les 0.5s sous le seuil de vie
				-- - le serveur l'ignore silencieusement si ce n'est pas le bon
				-- moment, pas de risque a le retenter plusieurs fois.
				local GRIP_HEALTH_THRESHOLD = 50
				local CHAKRA_SENSE_RESUME_DELAY_SECONDS = 2
				local notifiedMissing = false
				while state.enabled and state.token == myToken and not unloaded do
					-- Pause anti-detection : si quelqu'un a Chakra Sense actif a
					-- proximite (signal partage ChakraSenseThreat, alimente par
					-- les deux watchers Chakra Sense plus bas dans le fichier),
					-- on se detache et on retp au Safe Spot le temps que ca se
					-- calme, SANS toucher a l'etat du boss/du loot dans le monde -
					-- c'est cet etat du jeu lui-meme (boss encore en vie ? loot
					-- encore au sol ?) qui sert de "sauvegarde" de la phase : pas
					-- besoin de variable separee, on reprend naturellement le
					-- combat ou le loot en cours des que la menace disparait.
					if Settings.AutoEquipWeaponEnabled then
						M.reassertWeapon()
					end

					-- Panic Heal : meme esprit que la pause Chakra Sense
					-- (detach + tp Safe Spot), mais declenchee par les PV du
					-- joueur plutot qu'une menace exterieure - priorite sur
					-- tout le reste (une urgence de vie passe avant Chakra
					-- Sense). Reprend tout seul des que les PV repassent
					-- au-dessus du seuil (pas de delai tampon ici,
					-- contrairement a Chakra Sense : la regen est progressive,
					-- pas de risque de clignotement rapide comme un
					-- toggle manuel).
					local myHealthPercent = 100
					pcall(function()
						local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
						if hum and hum.MaxHealth > 0 then
							myHealthPercent = (hum.Health / hum.MaxHealth) * 100
						end
					end)
					local panicActive = Settings.PanicHealEnabled and myHealthPercent <= Settings.PanicHealThreshold

					local threatActive = Settings.AutoBossPauseOnChakraSense and isChakraSenseThreatActive()

					if panicActive then
						state.resumeDeadline = nil
						if state.attached then
							M.detach()
						end
						if not state.panicPaused then
							state.panicPaused = true
							notify(string.format("PV sous %d%% - pause Auto Boss, retour au Safe Spot.", Settings.PanicHealThreshold), "error")
							teleportToSafeSpot()
						end
						M.setHudState(state.lastBossName or "None", string.format("PV bas (%d%%)", math.floor(myHealthPercent)), "Panic")
						task.wait(0.3)
					elseif threatActive then
						-- Se detacher NE veut pas dire que le boss est mort : on
						-- peut tres bien etre en pleine baston quand la menace
						-- apparait. Ne pas forcer lootPending ici - au reveil,
						-- M.findBoss() retrouvera le boss toujours vivant dans le
						-- monde et on reprendra le combat normalement. lootPending
						-- ne doit etre mis a true que quand le boss est reellement
						-- introuvable (voir plus bas), pas juste parce qu'on etait
						-- attache au moment de la pause.
						state.resumeDeadline = nil -- la menace est revenue : on annule tout compte a rebours de reprise en cours
						if state.attached then
							M.detach()
						end
						if not state.chakraSensePaused then
							state.chakraSensePaused = true
							notify("Chakra Sense detecte a proximite - pause Auto Boss, retour au Safe Spot.", "error")
							teleportToSafeSpot()
						end
						M.setHudState(state.lastBossName or "None", "Chakra Sense actif a proximite", "Paused")
						task.wait(0.5)
					elseif state.chakraSensePaused then
						-- Menace disparue, mais delai de securite avant de
						-- vraiment reprendre : si quelqu'un active/desactive
						-- Chakra Sense en rafale, ca absorbe le clignotement au
						-- lieu de rattacher puis se re-detacher en boucle.
						state.resumeDeadline = state.resumeDeadline or (os.clock() + CHAKRA_SENSE_RESUME_DELAY_SECONDS)
						if os.clock() < state.resumeDeadline then
							M.setHudState(state.lastBossName or "None", "Chakra Sense actif a proximite", "Resuming")
							task.wait(0.2)
						else
							state.chakraSensePaused = false
							state.resumeDeadline = nil
							notify("Plus de Chakra Sense detecte - reprise de l'Auto Boss.", "success")
						end
					elseif state.panicPaused then
						if myHealthPercent > Settings.PanicHealThreshold then
							state.panicPaused = false
							notify("PV remontes au-dessus du seuil - reprise de l'Auto Boss.", "success")
						else
							M.setHudState(state.lastBossName or "None", string.format("PV bas (%d%%)", math.floor(myHealthPercent)), "Panic")
							task.wait(0.3)
						end
					else
						-- Le boss actuellement combattu vient d'etre decoche dans
						-- le dropdown de selection (rota multi-boss) : on
						-- l'abandonne tout de suite plutot que de continuer a le
						-- taper. PAS de lootPending ici (il n'est pas mort, on
						-- laisse juste tomber) - sans ce check explicite, tant
						-- qu'un AUTRE boss selectionne est deja present dans le
						-- monde, M.findBoss() le retournerait immediatement et la
						-- condition "if not state.attached" plus bas empecherait
						-- de re-attacher dessus puisqu'on pense deja etre attache
						-- (au mauvais boss) - reste visuellement bloque sur
						-- l'ancien tant qu'aucun tick ne renvoie nil.
						if state.attached and state.lastBossName and not Settings.AutoBossSelected[state.lastBossName] then
							M.detach()
							state.bossPresent = false
							state.lastConfig = nil
							state.lastBossName = nil
						end

						-- Loot laisse en plan par une pause precedente : on finit
						-- ca avant de refaire quoi que ce soit d'autre
						-- (state.lastConfig pointe toujours vers le bon
						-- rewardsModel).
						if state.lootPending and state.lastConfig then
							M.setHudState(state.lastBossName or "None", "None", "Looting")
							local ok, result = pcall(M.collectLoot, state.lastConfig)
							if ok and result == "done" then
								state.lootPending = false
								-- Rouvre la recherche d'un nouveau boss (voir
								-- M.findBoss) - sans ca elle resterait bloquee a
								-- ne chercher QUE ce boss-la pour toujours.
								state.lastConfig = nil
								state.lastBossName = nil
							end
						else
							local boss, config = M.findBoss()

							if boss then
								notifiedMissing = false
								state.bossPresent = true
								if not state.attached then
									M.attachTo(boss, config)
								end
								state.lastConfig = config
								state.lastBossName = boss.Name
								local bossHumanoid = boss:FindFirstChild("Humanoid")
								-- PlatformStanding confirme en live via Potassium
								-- comme le vrai signal "a terre" du boss (Health=1,
								-- GetState()==PlatformStanding). Continuer a taper
								-- une fois le boss a terre semble interferer avec
								-- le Grip / provoquer un contre qui stun le joueur
								-- (observe : Settings.Stunned=true, Settings.
								-- MeleeCooldown=true juste apres des tentatives
								-- ratees) - donc on arrete l'attaque des que le
								-- boss atteint cet etat, et on evite aussi de
								-- retenter le Grip tant qu'on est nous-meme stun.
								local bossDowned = bossHumanoid and bossHumanoid:GetState() == Enum.HumanoidStateType.PlatformStanding

								-- Health<=0 seul ne suffit pas a distinguer "vraiment
								-- mort, Model pas encore retire" de "a terre, Health
								-- au plancher en attendant le Grip" - le plancher
								-- exact varie selon le boss (Lavarossa reste a 1,
								-- mais Tairock a ete observe a 0 en plein downed :
								-- regression constatee en live quand ce cas
								-- declenchait markBossGone AVANT meme la tentative
								-- de Grip). bossDowned (toujours vrai tant que le
								-- Grip n'a pas fini le travail) est un premier signal,
								-- mais insuffisant seul pour Lavarossa : constate en
								-- live que GetState() peut rester PlatformStanding
								-- indefiniment meme apres un Grip reussi (peut-etre
								-- lie au statut Brulure). Le loot deja au sol
								-- (rewardsModel/TrinketSpawn) est un signal direct et
								-- independant du boss - s'il y en a, le kill est
								-- forcement confirme cote serveur, peu importe ce que
								-- rapporte encore GetState().
								local lootAlreadyDropped = false
								if config.rewardsModel then
									local rewards = workspace:FindFirstChild(config.rewardsModel)
									lootAlreadyDropped = rewards ~= nil and #M.findRewardItems(rewards) > 0
								end

								-- Filet de secours : si bossDowned reste coince sur
								-- PlatformStanding ET qu'aucun loot ne se montre
								-- jamais (constate en live sur Lavarossa - reste
								-- bloque a retenter le Grip indefiniment, jamais de
								-- transition vers la phase loot), on abandonne
								-- l'attente au bout de 8s a Health<=0 et on force
								-- quand meme le passage en loot plutot que de
								-- rester coince pour toujours.
								local deadTooLong = false
								if bossHumanoid and bossHumanoid.Health <= 0 then
									state.deadSince = state.deadSince or os.clock()
									deadTooLong = os.clock() - state.deadSince > 8
								else
									state.deadSince = nil
								end

								-- Filet de secours supplementaire (constate en live
								-- sur Manda : le loot ne s'est declenche que bien
								-- apres le kill, Health ne retombant pas de facon
								-- fiable a 0) - si le boss reste bloque a terre
								-- (bossDowned) sous 25 PV pendant plus de 10s sans
								-- jamais finir a 0 proprement, on considere que
								-- c'est fini quand meme. Conditionne a bossDowned
								-- expres : evite de couper un combat encore actif
								-- ou le boss est juste passe sous 25 PV mais se bat
								-- toujours normalement.
								local LOW_HEALTH_THRESHOLD = 25
								local LOW_HEALTH_STUCK_SECONDS = 10
								local stuckLowHealth = false
								if bossHumanoid and bossDowned and bossHumanoid.Health > 0 and bossHumanoid.Health < LOW_HEALTH_THRESHOLD then
									state.lowHealthSince = state.lowHealthSince or os.clock()
									stuckLowHealth = os.clock() - state.lowHealthSince > LOW_HEALTH_STUCK_SECONDS
								else
									state.lowHealthSince = nil
								end

								local trulyDead = bossHumanoid and bossHumanoid.Health <= 0 and (not bossDowned or lootAlreadyDropped or deadTooLong)
								if trulyDead or stuckLowHealth then
									state.deadSince = nil
									state.lowHealthSince = nil
									M.markBossGone()
								else
									local bossAlive = bossHumanoid and bossHumanoid.Health > 0
									M.setHudState(boss.Name, "None", bossDowned and "Grip" or "Attacking")

									-- M.isDodging() : pendant une esquive (voir
									-- dodgeAnimationIds/dodgeOffset dans M.attachTo),
									-- le personnage est deja loin du boss - continuer
									-- a tenter M1 dans le vide ne sert a rien et peut
									-- gener l'esquive elle-meme. Passe par isDodging (et
									-- pas state.dodging) pour couvrir aussi la marge
									-- gardee apres la fin de l'animation.
									if bossAlive and not bossDowned and not M.isDodging() then
										local ok, canAttack = pcall(canM1)
										if ok and canAttack then
											pcall(performM1)
										end
									end

									-- config.gripImmune (ex: Wooden Golem) : GameManager.NPC a
									-- GripImmunity=true + DieAfter=5 pour ce boss - le Grip est
									-- silencieusement rejete par le serveur, inutile de le
									-- tenter (et ca eviterait de se rapprocher pour rien via
									-- GRIP_APPROACH_OFFSET). Il meurt tout seul quelques
									-- secondes apres etre a terre - le fallback deadTooLong
									-- plus bas prend deja le relais.
									if bossHumanoid and bossHumanoid.Health < GRIP_HEALTH_THRESHOLD and bossDowned and not (state.lastConfig and state.lastConfig.gripImmune) then
										local now = os.clock()
										if now - state.lastGripAttempt >= 0.5 then
											-- Meme condition que le vrai bouton Grip du jeu
											-- (dump decompile, touche B) : le client bloque
											-- l'envoi si MeleeCooldown est encore actif, pas
											-- seulement si Stunned. Rate sur Barbarit en live
											-- (MeleeCooldown=true juste apres les derniers M1
											-- avant que le boss tombe) - sans ce check, le
											-- serveur rejette silencieusement chaque tentative.
											local myStunned, myMeleeCooldown = false, false
											pcall(function()
												local mySettings = ReplicatedStorage.Settings[LocalPlayer.Name]
												myStunned = mySettings.Stunned.Value
												myMeleeCooldown = mySettings.MeleeCooldown.Value
											end)
											if not myStunned and not myMeleeCooldown then
												state.lastGripAttempt = now
												-- Rapproche temporairement (GRIP_APPROACH_OFFSET,
												-- voir M.attachTo) le temps de la tentative : le
												-- hover normal est trop loin pour que le serveur
												-- accepte le Grip (confirme en live sur Barbarit -
												-- Gripping.Value reste "None" a 12 studs, bascule
												-- dessus a ~0.3 stud). On laisse le temps au
												-- RenderStep de repositionner avant de tirer, et un
												-- peu apres pour laisser le Grip s'enclencher avant
												-- de remonter.
												state.gripping = true
												task.wait(0.3)
												local DataEvent = M.getDataEvent()
												if DataEvent then
													pcall(function() DataEvent:FireServer("Grip") end)
												end
												task.wait(0.5)
												state.gripping = false
											end
										end
									end
								end
							else
								-- state.bossPresent (pas state.attached) detecte la
								-- transition "boss vivant -> boss disparu" : une
								-- pause Chakra Sense a deja pu nous detacher avant
								-- meme que le boss meure, donc state.attached seul
								-- ne suffit plus a distinguer "boss vient de mourir"
								-- de "boss jamais spawn".
								M.markBossGone()
								if state.lootPending and state.lastConfig then
									M.setHudState(state.lastBossName or "None", "None", "Looting")
									local ok, result = pcall(M.collectLoot, state.lastConfig)
									if ok and result == "done" then
										state.lootPending = false
										-- Rouvre la recherche d'un nouveau boss
										-- (voir M.findBoss).
										state.lastConfig = nil
										state.lastBossName = nil
									end
								end
								-- Avant de conclure "pas spawn" : certains boss (voir
								-- spawnFloor/spawnEvent dans BOSS_CONFIGS, ex:
								-- Lavarossa) ont besoin d'etre reveilles a la main.
								-- M.trySpawnBoss renvoie true tant qu'un de ces boss
								-- est pret a etre active (meme si la tentative
								-- elle-meme est rate-limitee) - dans ce cas on laisse
								-- la boucle reessayer au lieu de repartir au Safe Spot.
								if not state.lootPending then
									local spawning = M.trySpawnBoss()
									if spawning then
										M.setHudState(state.lastBossName or "None", "None", "Spawning")
									else
										M.setHudState("None", "Not Found Any Boss", "Waiting")
										if not notifiedMissing then
											notifiedMissing = true
											notify("Boss introuvable (pas spawn ou deja mort) - retour au Safe Spot.", "error")
											teleportToSafeSpot()
										end
									end
								end
							end
						end
					end

					task.wait(0.1)
				end
				if state.token == myToken then M.stop() end
			end)
		end

		-- Pleine largeur : c'est la card la plus chargee du menu (7 reglages + le
		-- multi-select des boss), elle etoufferait dans une demi-colonne.
		local AutoBossSection = addSection(AutoPage, "Auto Boss", true)
		FEATURE_CONTROLS.AutoBossEnabled = addToggleRow(AutoBossSection, "Auto Boss", Settings.AutoBossEnabled, function(value)
			Settings.AutoBossEnabled = value
			if value then M.start() else M.stop() end
		end)
		attachTooltip(FEATURE_CONTROLS.AutoBossEnabled.Row, "Vole au-dessus du boss, attaque, grip sous 50 PV, ramasse le loot et retourne au Safe Spot automatiquement.")
		FEATURE_CONTROLS.AutoBossPauseOnChakraSense = addToggleRow(AutoBossSection, "Pause si Chakra Sense detecte", Settings.AutoBossPauseOnChakraSense, function(value)
			Settings.AutoBossPauseOnChakraSense = value
		end)
		FEATURE_CONTROLS.PanicHealEnabled = addToggleRow(AutoBossSection, "Panic Heal", Settings.PanicHealEnabled, function(value)
			Settings.PanicHealEnabled = value
		end)
		attachTooltip(FEATURE_CONTROLS.PanicHealEnabled.Row, "Retour au Safe Spot automatique si tes PV passent sous le seuil choisi.")
		FEATURE_CONTROLS.PanicHealThreshold = addSliderRow(AutoBossSection, "Seuil Panic Heal (% PV)", 10, 80, Settings.PanicHealThreshold, 5, function(v)
			Settings.PanicHealThreshold = v
		end)
		FEATURE_CONTROLS.AutoEquipWeaponEnabled = addToggleRow(AutoBossSection, "Auto Equip Weapon", Settings.AutoEquipWeaponEnabled, function(value)
			Settings.AutoEquipWeaponEnabled = value
		end)
		attachTooltip(FEATURE_CONTROLS.AutoEquipWeaponEnabled.Row, "Reequipe ton arme actuelle (CurrentWeapon) au demarrage d'Auto Boss.")
		FEATURE_CONTROLS.NotifyLootEnabled = addToggleRow(AutoBossSection, "Notifier le Loot", Settings.NotifyLootEnabled, function(value)
			Settings.NotifyLootEnabled = value
		end)
		attachTooltip(FEATURE_CONTROLS.NotifyLootEnabled.Row, "Envoie la liste du loot ramasse au webhook Discord enregistre (page Settings).")
		addMultiSelectDropdownRow(AutoBossSection, "Boss", BOSS_NAMES, Settings.AutoBossSelected, function(name, state)
			Settings.AutoBossSelected[name] = state
		end)
	end

	do
		-- Vendre Tout : reproduit le flux reel de vente en masse aux PNJ marchands,
		-- reconstruit depuis un dump client decompile (data.lua ~L5457 et ~L7194,
		-- LocalScript "Potassium's decompiler"). Le vrai client, quand on appuie sur
		-- E pres d'un PNJ puis choisit l'option de vente en masse :
		--   1. Trouve le PNJ via GameManager:findNearbyNPC(HumanoidRootPart.CFrame)
		--      et prend son HumanoidRootPart (sinon .Main, sinon le Model) comme
		--      5e argument ("dialogPart") - PAS le HumanoidRootPart du joueur.
		--   2. Calcule le vrai prix via GameManager:calculateBulk(Inventory, Loadout,
		--      Type, nil) puis GameManager:getModifiedPrice(valeur, relationVillage,
		--      economie, "Sell") - ce n'est pas une valeur libre.
		--   3. Appelle DataFunction:InvokeServer("SellingBulk", prix, Type, nil, dialogPart).
		-- GameManager est un ModuleScript ordinaire sous ReplicatedStorage (require(
		-- ReplicatedStorage.GameManager) dans le dump), donc requerable directement
		-- ici comme le vrai client le fait, plutot que de deviner le calcul de prix.
		-- Locals internes (GameManager, helpers de prix, resolution du PNJ) isoles
		-- dans un do...end imbrique : seuls SELLABLE_ITEM_TYPES et sellAllOfType
		-- doivent survivre pour construire l'UI plus bas, le reste peut liberer
		-- son registre des que la closure sellAllOfType est construite (meme
		-- pattern que setAfkAgeUp/setPanicTeleport plus haut dans le fichier).
		local SELLABLE_ITEM_TYPES = { "Trinket", "Gem" }
		local sellAllOfType

		do
			local GameManager = require(ReplicatedStorage.GameManager)

			local function lookupVillageData(villageData, month, week, village)
				return villageData["Month" .. month]["Week" .. week][village]
			end

			local function getEconomy(villageData, month, week, village)
				if village == "Rogue" then return "Struggling" end
				if village == "Neutral" or not village then return "Average" end
				return lookupVillageData(villageData, month, week, village).Politics.Economy
			end

			local function getVillageRelationship(villageData, month, week, villageA, villageB)
				if not (villageA and villageB) then return nil end
				if villageA == "Rogue" or villageB == "Rogue" then return "War" end
				if villageA == "Neutral" or villageB == "Neutral" then return "Neutral" end
				if villageA == villageB then return "Own" end

				local dataA = lookupVillageData(villageData, month, week, villageA)
				local dataB = lookupVillageData(villageData, month, week, villageB)
				if table.find(dataA.Politics.Alliances, villageB) or table.find(dataB.Politics.Alliances, villageA) then
					return "Allied"
				end
				if table.find(dataA.Politics.Wars, villageB) or table.find(dataB.Politics.Wars, villageA) then
					return "War"
				end
				return "Neutral"
			end

			local function getNpcDialogPart(npc)
				return npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Main") or npc
			end

			-- dialogPart n'est qu'une reference d'Instance passee au serveur (utilisee
			-- pour lire son attribut "Village" et calculer le prix) : rien dans le flux
			-- observe ne l'exige "proche" de toi. On va donc chercher le PNJ "Merchant"
			-- (vendeur de base confirme en jeu) directement par son nom dans workspace,
			-- plutot que de passer par GameManager:findNearbyNPC qui exige d'etre a
			-- portee - ce qui permet de vendre depuis n'importe ou sur la carte.
			local MERCHANT_NPC_NAME = "Merchant"

			local function findMerchantNpc()
				return workspace:FindFirstChild(MERCHANT_NPC_NAME)
			end

			sellAllOfType = function(itemType)
				local DataFunction = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("DataFunction")
				if not DataFunction then
					notify("ReplicatedStorage.Events.DataFunction introuvable.", "error")
					return
				end

				local ok, result = pcall(function()
					local npc = findMerchantNpc()
					if not npc then
						return "no_npc"
					end
					local dialogPart = getNpcDialogPart(npc)

					local playerData = DataFunction:InvokeServer("GetData")
					if not playerData then
						return "no_data"
					end

					local villageData, month, week = DataFunction:InvokeServer("getVillageData")
					local npcVillage = dialogPart:GetAttribute("Village")
					local relationship = getVillageRelationship(villageData, month, week, playerData.Village, npcVillage)
					local economy = getEconomy(villageData, month, week, npcVillage)

					local rawValue = GameManager:calculateBulk(playerData.Inventory, playerData.Loadout, itemType, nil)
					local price = GameManager:getModifiedPrice(rawValue, relationship, economy, "Sell")

					return DataFunction:InvokeServer("SellingBulk", price, itemType, nil, dialogPart)
				end)

				if not ok then
					notify("Erreur lors de la vente de " .. itemType .. " : " .. tostring(result), "error")
				elseif result == "no_npc" then
					notify("PNJ \"" .. MERCHANT_NPC_NAME .. "\" introuvable dans workspace.", "error")
				elseif result == "no_data" then
					notify("Impossible de recuperer tes donnees joueur.", "error")
				elseif result == true then
					notify("Vente reussie : " .. itemType .. ".", "success")
				else
					notify("Vente refusee par le serveur pour : " .. itemType .. ".", "error")
				end
			end
		end

		local SellAllSection = addSection(AutresPage, "Vendre Tout")
		FEATURE_CONTROLS.SelectedSellType = addDropdownRow(SellAllSection, "Type d'objet", SELLABLE_ITEM_TYPES, Settings.SelectedSellType, function(v)
			Settings.SelectedSellType = v
		end)
		attachTooltip(addButtonRow(SellAllSection, "Vendre Tout", function()
			sellAllOfType(Settings.SelectedSellType)
		end), "Vend d'un coup tout ce que tu possedes du type choisi au Merchant, depuis n'importe ou.")
	end

	do
		-- Achat generique : reproduit l'appel "Pay" capture en jeu (call.lua) -
		-- DataFunction:InvokeServer("Pay", price, itemName, quantity, dialogPart).
		-- Contrairement a la vente, pas besoin de GameManager ici : le prix
		-- envoye correspond exactement au champ SalePrice de l'item dans le
		-- dump (verifie sur l'exemple capture - Golden Zabunagi, SalePrice=70,
		-- achete avec price=70). dialogPart reutilise le meme PNJ "Merchant"
		-- que Vendre Tout (rien dans le flux ne l'exige "proche" de toi).
		-- BUYABLE_ITEMS extrait du dump (data2.lua, table Items, entrees avec
		-- Buyabble = true) ; locals internes isoles dans ce do...end.
		local BUYABLE_ITEMS = {
			["Adamantine Staff"] = 1000,
			["Akatsuki Hat"] = 100,
			["Bloody Executioner's Blade"] = 300,
			["Bowl"] = 3,
			["Candy Cane Kusanagi"] = 300,
			["Chakrabone"] = 15,
			["Chef's Kiss"] = 50,
			["Chicken"] = 6,
			["Desolated Key"] = 20,
			["Durana Kage Hat"] = 500,
			["Executioner's Blade"] = 300,
			["Flaming Heart"] = 90,
			["Frozen Executioner's Blade"] = 300,
			["Gingerbread Gunbai"] = 1000,
			["Golden Asumai"] = 40,
			["Golden Halberd"] = 70,
			["Golden Kunai"] = 25,
			["Golden Resanagi"] = 40,
			["Golden Zabunagi"] = 70,
			["Grounds Key"] = 10,
			["Gunbai"] = 1000,
			["Hallowed Kusanagi"] = 300,
			["Jingle Bell Staff"] = 1000,
			["Kusanagi"] = 300,
			["Metallic Bow"] = 250,
			["Nutcracker Raijin"] = 300,
			["Onyx Asumai"] = 70,
			["Onyx Halberd"] = 150,
			["Onyx Kunai"] = 40,
			["Onyx Resanagi"] = 60,
			["Onyx Zabunagi"] = 90,
			["Pumpkin Samehada"] = 800,
			["Raijin Kunai"] = 300,
			["Rain Kage Hat"] = 500,
			["Ramen"] = 10,
			["Red Anbu Mask"] = 100,
			["Ring Schematics"] = 90,
			["Samehada"] = 800,
			["Silver Asumai"] = 25,
			["Silver Halberd"] = 50,
			["Silver Kunai"] = 15,
			["Silver Resanagi"] = 25,
			["Silver Zabunagi"] = 50,
			["Skeletal Adamantine Staff"] = 1000,
			["Snow Kage Hat"] = 500,
			["Snow Key"] = 50,
			["Sorythia Kage Hat"] = 500,
			["Spider Gunbai"] = 1000,
			["Spooky Raijin Kunai"] = 300,
			["Torch"] = 25,
			["Tree Samehada"] = 800,
		}

		local BUYABLE_ITEM_NAMES = {}
		for name in pairs(BUYABLE_ITEMS) do
			table.insert(BUYABLE_ITEM_NAMES, name)
		end
		table.sort(BUYABLE_ITEM_NAMES)

		local function buyItem(itemName, quantity)
			local unitPrice = BUYABLE_ITEMS[itemName]
			if not unitPrice then
				notify("Item inconnu (absent des data) : \"" .. tostring(itemName) .. "\".", "error")
				return
			end

			local DataFunction = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("DataFunction")
			if not DataFunction then
				notify("ReplicatedStorage.Events.DataFunction introuvable.", "error")
				return
			end

			local npc = workspace:FindFirstChild("Merchant")
			if not npc then
				notify("PNJ \"Merchant\" introuvable dans workspace.", "error")
				return
			end
			local dialogPart = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Main") or npc

			local ok, result = pcall(function()
				return DataFunction:InvokeServer("Pay", unitPrice * quantity, itemName, quantity, dialogPart)
			end)

			if not ok then
				notify("Erreur lors de l'achat de " .. itemName .. " : " .. tostring(result), "error")
			elseif result == true then
				notify("Achat reussi : " .. itemName .. " x" .. quantity .. ".", "success")
			else
				notify("Achat refuse par le serveur pour : " .. itemName .. ".", "error")
			end
		end

		local BuySection = addSection(AutresPage, "Acheter")

		local ItemNameBox = Skin.paint(create("TextBox", {
			Size = UDim2.new(1, 0, 0, 30),
			Text = "",
			PlaceholderText = "Nom exact de l'item...",
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			ClearTextOnFocus = false,
		}, BuySection), { BackgroundColor3 = "Element", TextColor3 = "Text", PlaceholderColor3 = "SubTextDim" })
		corner(ItemNameBox, 3)
		Skin.paint(create("UIStroke", { Transparency = 0 }, ItemNameBox), { Color = "Stroke" })
		create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, ItemNameBox)

		addDropdownRow(BuySection, "Choisir dans la liste", BUYABLE_ITEM_NAMES, nil, function(v)
			ItemNameBox.Text = v
		end)

		FEATURE_CONTROLS.BuyQuantity = addSliderRow(BuySection, "Quantite", 1, 99, Settings.BuyQuantity, 1, function(v)
			Settings.BuyQuantity = v
		end)

		attachTooltip(addButtonRow(BuySection, "Acheter", function()
			local name = ItemNameBox.Text
			if name == "" then
				notify("Entre ou choisis un nom d'item.", "error")
				return
			end
			buyItem(name, Settings.BuyQuantity)
		end), "Achete l'item choisi au Merchant, depuis n'importe ou.")
	end

	do
		-- Spectate generique (façon EdgeIY/infiniteyield ";spectate") : AUCUNE
		-- dependance au systeme "observe"/Chakra Sense du jeu - on bascule juste
		-- CurrentCamera.CameraSubject localement, purement cote client, exactement
		-- comme le fait Infinite Yield. Ca evite tout aller-retour serveur et
		-- toute condition de skill/moderateur.
		-- Cible identifiee en cliquant une entree du VRAI leaderboard du jeu
		-- (Mainframe.PlayerList.List, celui du Tab - confirme data.lua ~L7153).
		-- On lit le nom affiche AU MOMENT DU CLIC : pour cliquer un bouton il
		-- faut d'abord le survoler, et le gestionnaire MouseEnter natif du jeu
		-- (connecte des la creation de l'entree, donc avant que notre propre
		-- hook ne la detecte) a deja bascule le texte sur le vrai pseudo Roblox
		-- (RealName) a ce moment-la - on peut alors le faire correspondre
		-- directement a Players:GetPlayers(), sans passer par GetPlayerList.
		-- Etat + fonctions regroupes dans deux tables plutot qu'en locals
		-- separes, pour rester large sur les registres (voir note en tete de
		-- fichier).
		-- listConn / targetConn : connexions qu'on doit pouvoir COUPER nous-memes,
		-- pas seulement au unload - la liste du jeu est reconstruite a chaque
		-- respawn et la cible peut changer de personnage. Les garder ici evite
		-- d'empiler des connexions mortes sur des instances detruites.
		local state = { enabled = false, currentTarget = nil, connected = {}, listConn = nil, targetConn = nil }
		local M = {}

		function M.findPlayerByDisplayText(text)
			for _, player in ipairs(Players:GetPlayers()) do
				if player.Name == text or player.DisplayName == text then
					return player
				end
			end
			return nil
		end

		function M.stopSpectating()
			state.currentTarget = nil
			if state.targetConn then
				state.targetConn:Disconnect()
				state.targetConn = nil
			end
			local character = LocalPlayer.Character
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			if humanoid then
				workspace.CurrentCamera.CameraSubject = humanoid
			end
		end

		function M.spectate(player)
			local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
			if not humanoid then
				notify(player.Name .. " n'a pas de personnage charge.", "error")
				return
			end
			workspace.CurrentCamera.CameraSubject = humanoid
			state.currentTarget = player

			-- La cible va mourir tot ou tard : son Humanoid est alors detruit et
			-- la camera retombe toute seule sur nous, alors que state.currentTarget
			-- continue de la designer. Sans ce reaccrochage, on ne suivait plus
			-- rien ET recliquer sur ce joueur appelait stopSpectating (on croyait
			-- deja le spectate) au lieu de le reprendre.
			if state.targetConn then state.targetConn:Disconnect() end
			state.targetConn = player.CharacterAdded:Connect(function(character)
				if state.currentTarget ~= player then return end
				local newHumanoid = character:WaitForChild("Humanoid", 10)
				if newHumanoid and state.currentTarget == player then
					workspace.CurrentCamera.CameraSubject = newHumanoid
				end
			end)
		end

		function M.getPlayerListFrame()
			local clientGui = PlayerGui:FindFirstChild("ClientGui")
			local mainframe = clientGui and clientGui:FindFirstChild("Mainframe")
			local playerList = mainframe and mainframe:FindFirstChild("PlayerList")
			return playerList and playerList:FindFirstChild("List")
		end

		function M.onEntryClicked(child)
			if not state.enabled then return end
			local nameLabel = child:FindFirstChild("PlayerName")
			if not nameLabel then return end
			local player = M.findPlayerByDisplayText(nameLabel.Text)
			if not player or player == LocalPlayer then return end

			if state.currentTarget == player then
				M.stopSpectating()
			else
				M.spectate(player)
			end
		end

		function M.hookEntry(child)
			if child:IsA("ImageButton") and not state.connected[child] then
				state.connected[child] = true
				track(child.MouseButton1Down:Connect(function()
					M.onEntryClicked(child)
				end))
				track(child.Destroying:Connect(function()
					state.connected[child] = nil
				end))
			end
		end

		function M.hookPlayerList()
			local listFrame = M.getPlayerListFrame()
			if not listFrame then
				task.delay(2, M.hookPlayerList) -- PlayerList pas encore charge, on reessaie
				return
			end
			-- Coupe l'accroche precedente : sur un rebuild du ClientGui elle
			-- pointe vers une List detruite, et sans ca on empilerait une
			-- connexion morte de plus a chaque respawn.
			if state.listConn then state.listConn:Disconnect() end
			state.connected = {}
			for _, child in ipairs(listFrame:GetChildren()) do
				M.hookEntry(child)
			end
			state.listConn = track(listFrame.ChildAdded:Connect(M.hookEntry))
		end
		M.hookPlayerList()

		-- ClientGui a ResetOnSpawn=true (verifie en jeu) : a CHAQUE mort, Roblox
		-- detruit puis recree tout le ScreenGui, donc la List et notre connexion
		-- ChildAdded avec. C'est la cause du "le spectate ne marche plus apres
		-- etre mort" : plus aucune entree n'etait accrochee, cliquer ne faisait
		-- rien. On se raccroche donc a chaque respawn.
		track(LocalPlayer.CharacterAdded:Connect(function()
			if unloaded then return end
			-- Notre propre mort remet la camera sur notre nouveau personnage :
			-- l'ancienne cible n'est plus spectate, il faut oublier l'etat sinon
			-- recliquer dessus la stoppait au lieu de la reprendre.
			M.stopSpectating()
			task.wait(1) -- laisse le jeu reconstruire son ClientGui
			M.hookPlayerList()
		end))

		-- Cible qui quitte le serveur : meme etat fantome que ci-dessus.
		track(Players.PlayerRemoving:Connect(function(player)
			if state.currentTarget == player then
				M.stopSpectating()
			end
		end))

		local SpectateSection = addSection(AutresPage, "Spectate Leaderboard")
		FEATURE_CONTROLS.AutoSpectateOnClick = addToggleRow(SpectateSection, "Spectate au clic (leaderboard)", Settings.AutoSpectateOnClick, function(value)
			state.enabled = value
			Settings.AutoSpectateOnClick = value
			if not value then M.stopSpectating() end
		end)
		attachTooltip(FEATURE_CONTROLS.AutoSpectateOnClick.Row, "Clique un joueur dans le leaderboard (Tab) pour le spectate, reclique pour arreter.")
	end

	do
		-- Reputation de la faction du joueur (playerData.Village), lue via le
		-- meme remote GetData que la vente (voir sellAllOfType plus haut).
		local ReputationSection = addSection(AutresPage, "Reputation")
		local ReputationLabel = addLabelRow(ReputationSection, "Reputation : ...")

		local function refreshReputation()
			local DataFunction = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("DataFunction")
			if not DataFunction then
				ReputationLabel.Text = "Reputation : DataFunction introuvable"
				return
			end
			local ok, playerData = pcall(function()
				return DataFunction:InvokeServer("GetData")
			end)
			local reputation = ok and playerData and playerData.Reputation and playerData.Village
				and playerData.Reputation[playerData.Village]
			ReputationLabel.Text = "Reputation : " .. (reputation ~= nil and tostring(reputation) or "?")
		end

		addButtonRow(ReputationSection, "Actualiser", refreshReputation)
		refreshReputation()
	end

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
	local Row = Skin.paint(create("Frame", { Size = UDim2.new(1, 0, 0, 56) }, container), { BackgroundColor3 = "Element" })
	corner(Row, 3)
	Skin.paint(create("UIStroke", { Transparency = 0 }, Row), { Color = "Stroke" })

	Skin.paint(create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -20, 0, 18),
		BackgroundTransparency = 1,
		Text = isDefault and (name .. "  \226\152\133 par defaut") or name,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Row), { TextColor3 = isDefault and "Accent" or "Text" })

	local ButtonsHolder = create("Frame", {
		Position = UDim2.new(0, 10, 0, 27),
		Size = UDim2.new(1, -20, 0, 23),
		BackgroundTransparency = 1,
	}, Row)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, ButtonsHolder)

	-- Trois niveaux : "filled" pour l'action principale (fond accent, texte
	-- OnAccent), "danger" pour la destructrice (contour et texte rouges, jamais
	-- de rouge plein - ca attirerait l'oeil plus que Charger), nil pour le
	-- neutre (contour gris). La couleur n'apparait que la ou l'action compte.
	local function miniButton(text, kind)
		local Btn = Skin.paint(create("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = kind == "filled" and 0 or 1,
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			AutoButtonColor = false,
		}, ButtonsHolder), {
			BackgroundColor3 = "Accent",
			TextColor3 = kind == "filled" and "OnAccent" or (kind == "danger" and "Danger" or "SubText"),
		})
		corner(Btn, 3)
		if kind ~= "filled" then
			Skin.paint(create("UIStroke", { Transparency = 0 }, Btn), {
				Color = kind == "danger" and "Danger" or "StrokeStrong",
			})
		end
		create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, Btn)
		return Btn
	end

	miniButton("Charger", "filled").MouseButton1Click:Connect(onLoad)
	miniButton(isDefault and "Retirer defaut" or "Def. par defaut").MouseButton1Click:Connect(onSetDefault)
	miniButton("Supprimer", "danger").MouseButton1Click:Connect(onDelete)
end

do
	local ConfigSection = addSection(SettingsPage, "Configs")

	local ConfigNameBox = Skin.paint(create("TextBox", {
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		PlaceholderText = "Nom de la config...",
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		ClearTextOnFocus = false,
	}, ConfigSection), { BackgroundColor3 = "Element", TextColor3 = "Text", PlaceholderColor3 = "SubTextDim" })
	corner(ConfigNameBox, 3)
	Skin.paint(create("UIStroke", { Transparency = 0 }, ConfigNameBox), { Color = "Stroke" })
	create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, ConfigNameBox)
	attachTooltip(ConfigNameBox, "Enregistre tes reglages actuels sous ce nom, marque-en une par defaut pour la recharger au demarrage.")

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
						notify("Impossible de charger '" .. name .. "'.", "error")
						return
					end
					applyFeatureSettings(data)
					notify("Config '" .. name .. "' chargee.", "success")
				end,
				function()
					Meta.defaultConfig = (Meta.defaultConfig == name) and nil or name
					saveMeta()
					notify(Meta.defaultConfig == name and ("'" .. name .. "' est la config par defaut.") or "Plus de config par defaut.")
					refreshConfigList()
					MenuChrome.refreshRight()
				end,
				function()
					deleteConfig(name)
					notify("Config '" .. name .. "' supprimee.", "success")
					refreshConfigList()
					MenuChrome.refreshRight()
				end
			)
		end
	end

	addButtonRow(ConfigSection, "Enregistrer la config actuelle", function()
		local name = sanitizeConfigName(ConfigNameBox.Text)
		if name == "" then
			notify("Donne un nom a ta config avant d'enregistrer.", "error")
			return
		end
		saveConfig(name)
		notify("Config '" .. name .. "' enregistree.", "success")
		refreshConfigList()
	end)

	refreshConfigList()
end

do
	local Section = addSection(SkinPage, "Skin")
	addLabelRow(Section, "En cours de developpement.")
end

do
	local DebugSection = addSection(SettingsPage, "Debug")
	addButtonRow(DebugSection, "Dump LocalPlayer", dumpLocalPlayerToClipboard)
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
	-- Le theme est une preference d'app (comme la taille de fenetre ou la touche
	-- du menu), pas un reglage "cheat" : il vit dans Prefs et se recharge a
	-- chaque session, independamment du systeme de configs.
	local AppearanceSection = addSection(SettingsPage, "Apparence")
	addDropdownRow(AppearanceSection, "Theme", Skin.order, Skin.current, function(name)
		Skin.set(name)
		Prefs.MenuTheme = name
		savePrefs()
	end)
	addLabelRow(AppearanceSection, "Graphite est achromatique : l'accent y est le blanc du texte. Papier est clair, il eblouit sur une scene sombre.")
end

do
	local ShortcutSection = addSection(SettingsPage, "Raccourcis")
	addKeybindRow(ShortcutSection, "Touche menu", MENU_TOGGLE_KEY, function(newKey)
		MENU_TOGGLE_KEY = newKey
		Prefs.MenuKeybind = newKey.Name
		savePrefs()
		MenuChrome.refreshRight()
	end)
end

do
	local KeybindHudSection = addSection(SettingsPage, "HUD Keybinds")
	attachTooltip(addToggleRow(KeybindHudSection, "Voir les Keybinds", Prefs.ShowKeybindHud, function(state)
		Prefs.ShowKeybindHud = state
		savePrefs()
		KeybindTool.hudFrame.Visible = state
	end).Row, "Affiche a l'ecran les touches assignees a chaque feature active.")
end

do
	local WebhookSection = addSection(SettingsPage, "Webhook Discord")

	local WebhookUrlBox = Skin.paint(create("TextBox", {
		Size = UDim2.new(1, 0, 0, 30),
		Text = Prefs.InventoryWebhookUrl or "",
		PlaceholderText = "https://discord.com/api/webhooks/...",
		Font = Enum.Font.Code,
		TextSize = 12,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, WebhookSection), { BackgroundColor3 = "Element", TextColor3 = "Text", PlaceholderColor3 = "SubTextDim" })
	corner(WebhookUrlBox, 3)
	Skin.paint(create("UIStroke", { Transparency = 0 }, WebhookUrlBox), { Color = "Stroke" })
	create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, WebhookUrlBox)
	attachTooltip(WebhookUrlBox, "Utilise par l'envoi auto d'inventaire (page Auto > Envoi Auto Inventaire).")

	addButtonRow(WebhookSection, "Enregistrer le webhook", function()
		local url = WebhookUrlBox.Text
		if url == "" then
			notify("Le lien webhook ne peut pas etre vide.", "error")
			return
		end
		Prefs.InventoryWebhookUrl = url
		savePrefs()
		notify("Webhook enregistre.", "success")
	end)

	addButtonRow(WebhookSection, "Copier le webhook actuel", function()
		local url = Prefs.InventoryWebhookUrl or ""
		if url == "" then
			notify("Aucun webhook configure.", "error")
			return
		end
		if setclipboard then
			local ok = pcall(setclipboard, url)
			if ok then
				notify("Webhook copie dans le presse-papier.", "success")
			else
				notify("Erreur : setclipboard a echoue.", "error")
			end
		else
			notify("setclipboard indisponible. Webhook affiche en console (F9).", "error")
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

-- Section large (3e argument) : le bouton de decharge est la seule action
-- irreversible du menu, il ne partage pas sa rangee avec autre chose.
-- Passe par MenuChrome.track pour etre indexe par la recherche, comme toute
-- ligne construite a la main plutot que par un add*Row.
local SessionSection = addSection(SettingsPage, "Session", true)
local UnloadButton = MenuChrome.track(Skin.paint(create("TextButton", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Text = "Decharger le script",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	AutoButtonColor = false,
}, SessionSection), { BackgroundColor3 = "Danger", TextColor3 = "Danger" }), "Decharger le script")
corner(UnloadButton, 3)
Skin.paint(create("UIStroke", { Transparency = 0 }, UnloadButton), { Color = "Danger" })
local unloadScale = create("UIScale", { Scale = 1 }, UnloadButton)
-- Contour rouge au repos, rouge plein au survol : visible sans hurler dans une
-- page ou tout le reste est neutre.
UnloadButton.MouseEnter:Connect(function()
	UnloadButton.BackgroundTransparency = 0
	tween(UnloadButton, { TextColor3 = Theme.OnAccent }, 0.1)
end)
UnloadButton.MouseLeave:Connect(function()
	UnloadButton.BackgroundTransparency = 1
	tween(UnloadButton, { TextColor3 = Theme.Danger }, 0.1)
end)
UnloadButton.MouseButton1Click:Connect(function()
	tween(unloadScale, { Scale = 0.97 }, 0.08)
	task.delay(0.08, function() tween(unloadScale, { Scale = 1 }, 0.12) end)
	unload()
end)

-- Alerte si un joueur a le cooldown "Chakra Sense" actif (structure
-- ReplicatedStorage.Cooldowns.<Joueur>.<NomCooldown> propre a ce jeu).
-- Frequence reglable (Settings.ChakraSenseNotifyInterval, 1-30s, slider page
-- Joueur > Notifications) au lieu du task.wait(15) fixe d'origine.
-- C'est la SEULE des deux alertes Chakra Sense a notifier via toast
-- (FeatureState.ChakraSenseNotifier) - la version CurrentSkill juste apres
-- ne sert plus qu'a alimenter ChakraSenseThreat en silence, pour Auto Boss
-- et les futures features qui en auront besoin (toggle ou d'office), comme
-- demande explicitement.
task.spawn(function()
	while not unloaded do
		task.wait(Settings.ChakraSenseNotifyInterval or 15)
		if unloaded then break end
		local cooldownsFolder = ReplicatedStorage:FindFirstChild("Cooldowns")
		if cooldownsFolder then
			for _, playerFolder in ipairs(cooldownsFolder:GetChildren()) do
				if playerFolder:FindFirstChild("Chakra Sense") then
					ChakraSenseThreat.lastSeen = os.clock()
					if FeatureState.ChakraSenseNotifier then
						notify(string.format("%s a Chakra Sense actif", playerFolder.Name))
					end
				end
			end
		end
	end
end)

do
	-- Detection Chakra Sense silencieuse, evenementielle : lu via
	-- ReplicatedStorage.Settings.<joueur>.CurrentSkill (reflete le skill
	-- actuellement selectionne/actif). Ne notifie PAS - alimente uniquement
	-- ChakraSenseThreat (utilise par Auto Boss et tout ce qui suivra), donc
	-- independant du toggle ChakraSenseNotifier qui ne concerne que le
	-- poll Cooldowns au-dessus.
	local state = { hookedPlayers = {} }
	local M = {}

	function M.watchCurrentSkill(player)
		if state.hookedPlayers[player] then return end
		state.hookedPlayers[player] = true

		task.spawn(function()
			local settingsFolder = ReplicatedStorage:WaitForChild("Settings", 10)
			local playerSettings = settingsFolder and settingsFolder:WaitForChild(player.Name, 10)
			local currentSkill = playerSettings and playerSettings:WaitForChild("CurrentSkill", 10)
			if not currentSkill then return end

			track(currentSkill.Changed:Connect(function(value)
				if unloaded or value ~= "Chakra Sense" then return end
				ChakraSenseThreat.lastSeen = os.clock()
			end))
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		M.watchCurrentSkill(player)
	end
	track(Players.PlayerAdded:Connect(M.watchCurrentSkill))
end

do
	-- SpectatedNotifier : simple ChildAdded sur notre
	-- ReplicatedStorage.Settings.<NOUS> - des qu'une valeur nommee
	-- "BeingObservedBy" apparait, on notifie, sans verifier son contenu
	-- (demande explicitement ainsi). Confirme en jeu que ce champ apparait
	-- aussi bien pour le spectate que pour Chakra Sense (les deux passent
	-- par le meme remote "observe" cote serveur, voir le dump decompile).
	task.spawn(function()
		local settingsFolder = ReplicatedStorage:WaitForChild("Settings", 10)
		local mySettings = settingsFolder and settingsFolder:WaitForChild(LocalPlayer.Name, 10)
		if not mySettings then return end

		track(mySettings.ChildAdded:Connect(function(child)
			if unloaded or not FeatureState.SpectatedNotifier then return end
			if child.Name == "BeingObservedBy" then
				notify("On vous observe !", "error")
			end
		end))
	end)
end

-- Les toggles ne declenchent leur onChange qu'au clic : sans ca, un effet deja
-- actif au demarrage (config par defaut chargee avec NoFog/Fly/etc. a true)
-- s'afficherait allume dans le menu sans que l'effet reel ne soit applique.
setEnabled(FeatureState.enabled)
setNoFog(FeatureState.NoFogEnabled)
setNoRain(FeatureState.NoRainEnabled)
setFullBright(FeatureState.FullBrightEnabled)
setTimeChanger(FeatureState.TimeChangerEnabled)
setNoclip(FeatureState.NoclipEnabled)
setFly(FeatureState.FlyEnabled)

-- Ferme la derniere section ouverte : les lignes creees APRES ce point le sont
-- dynamiquement (liste de configs reconstruite, dropdown de teleport rafraichi)
-- et ne doivent pas s'accumuler dans l'index de la recherche, qui suppose des
-- lignes stables.
MenuChrome.currentSection = nil

selectPage("Visuels")
MenuChrome.refreshRight() -- remplit la moitie droite de la barre d'etat (config + touche menu)
playInjectionSplash()
KeybindTool.refreshHud() -- construit le HUD une fois tous les KeybindTool.bind faits plus haut

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
