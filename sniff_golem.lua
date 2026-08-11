--------------------------------------------------------------------------------
-- Sniffer Wooden Golem - instrumentation complete
--------------------------------------------------------------------------------
-- But : comprendre comment le script de reference survit a "Spire" et "Dragon".
-- A lancer AVANT d'activer l'autre script, puis aller faire le boss avec LUI.
--
-- Etiquettes, toutes horodatees a os.clock() pour pouvoir se correler :
--   POS   position/PV du joueur, 10 Hz, en continu
--   BOSS  animation jouee par le boss (c'est la qu'on repere Spire/Dragon)
--   ME    animation jouee par NOUS (le script de reference joue-t-il un dodge ?)
--   OUT   remote sortant (FireServer / InvokeServer)
--   IN    remote entrant (OnClientEvent)
--   MOVER BodyVelocity/AlignPosition/... ajoute a notre personnage
--   PART  partie apparue dans l'arene (le pic de Spire : sa POSITION permettrait
--         de s'ecarter de la ou il est, au lieu de cycler sur des coins fixes)
--   STATE Anchored / PlatformStand / attributs / Settings.<joueur>
--
-- Chaque brique s'arme dans son propre pcall : si l'executeur ne fournit pas
-- hookmetamethod (par exemple), le reste tourne quand meme. La version
-- precedente plantait en entier sur la premiere API manquante, sans rien dire.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local BOSS_NAME = "Wooden Golem"

-- Arene du Wooden Golem : centre approximatif et rayon, pour ne journaliser que
-- les parties qui apparaissent LA (sinon tout le workspace defile).
local ARENA_CENTER = Vector3.new(-4650, 340, -2930)
local ARENA_RADIUS = 400

local function log(tag, fmt, ...)
	print(string.format("[%8.3f] %-5s %s", os.clock(), tag, string.format(fmt, ...)))
end

--------------------------------------------------------------------------------
-- Relance propre
--------------------------------------------------------------------------------
-- Relancer le script empilerait un hook __namecall de plus et une boucle de
-- position de plus a chaque fois (donc des lignes en double, puis en triple...).
-- On garde donc l'etat dans _G : au demarrage on coupe l'instance precedente.
-- Le hook __namecall, lui, ne se retire pas - il teste GEN pour ne rien
-- journaliser s'il appartient a une generation perimee.
if _G.__VonSniff then
	for _, conn in ipairs(_G.__VonSniff.conns) do pcall(function() conn:Disconnect() end) end
	_G.__VonSniff.gen = _G.__VonSniff.gen + 1
	log("INIT", "instance precedente coupee (generation %d)", _G.__VonSniff.gen)
else
	_G.__VonSniff = { gen = 1, conns = {}, hooked = false }
end

local SNIFF = _G.__VonSniff
SNIFF.conns = {}
local GEN = SNIFF.gen

-- Enregistre une connexion pour qu'une relance puisse la couper.
local function keep(conn)
	table.insert(SNIFF.conns, conn)
	return conn
end

-- Arme une brique et dit si elle a pris. Rien ne doit pouvoir faire tomber
-- l'ensemble du sniffer.
local function arm(name, fn)
	local ok, err = pcall(fn)
	log("INIT", "%-18s %s", name, ok and "ok" or ("ECHEC: " .. tostring(err)))
	return ok
end

log("INIT", "--- demarrage du sniffer %s ---", BOSS_NAME)

--------------------------------------------------------------------------------
-- Mise en forme des arguments de remote
--------------------------------------------------------------------------------

local function describe(value)
	local kind = typeof(value)
	if kind == "Instance" then
		return value.ClassName .. "(" .. value.Name .. ")"
	elseif kind == "Vector3" then
		return string.format("V3(%.1f, %.1f, %.1f)", value.X, value.Y, value.Z)
	elseif kind == "CFrame" then
		local p = value.Position
		return string.format("CF(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
	elseif kind == "table" then
		local parts = {}
		for k, v in pairs(value) do
			table.insert(parts, tostring(k) .. "=" .. tostring(v))
			if #parts >= 6 then table.insert(parts, "...") break end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif kind == "string" then
		return #value > 60 and ('"' .. value:sub(1, 60) .. '..."') or ('"' .. value .. '"')
	end
	return tostring(value)
end

local function describeArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = describe((select(i, ...)))
	end
	return table.concat(parts, ", ")
end

-- Bruit de fond : ces remotes partent en continu et noieraient le reste.
local NOISE = {
	SetRainAbove = true, NearbyFruitsPlease = true, NearbyTrinketsPlease = true,
	GetPlayerList = true, playHitEffect = true, Emit = true, generateDebris = true,
	UpdateChunks = true, Ping = true, Heartbeat = true,
	tweenModelScale = true, playSound = true, playParticle = true,
}

--------------------------------------------------------------------------------
-- Etat partage (le boss suivi, pour que la boucle de position sache son offset)
--------------------------------------------------------------------------------

local S = { boss = nil, bossConn = nil }

local function findBoss()
	local model = workspace:FindFirstChild(BOSS_NAME)
	if model and model:FindFirstChild("Humanoid") and model.Humanoid.Health > 0 then
		return model
	end
	return nil
end

--------------------------------------------------------------------------------
-- Briques
--------------------------------------------------------------------------------

arm("remotes sortants", function()
	local hook = hookmetamethod
	local getMethod = getnamecallmethod
	assert(typeof(hook) == "function", "hookmetamethod indisponible")
	assert(typeof(getMethod) == "function", "getnamecallmethod indisponible")

	assert(not SNIFF.hooked, "hook __namecall deja installe (conserve entre relances)")
	SNIFF.hooked = true

	local old
	old = hook(game, "__namecall", function(self, ...)
		local method = getMethod()
		if method == "FireServer" or method == "InvokeServer" then
			local first = (select(1, ...))
			local quiet = (typeof(first) == "string" and NOISE[first]) or NOISE[self.Name]
			if not quiet then
				-- `...` est mis en forme ICI, pas dans la closure du pcall :
				-- Luau refuse `...` a l'interieur d'une fonction imbriquee
				-- (erreur de compilation, pas d'execution - c'est ce qui rendait
				-- tout le sniffer muet). On passe donc une chaine deja prete.
				local desc = describeArgs(...)
				local remoteName, callMethod = self.Name, method
				-- pcall : une erreur de journalisation ne doit JAMAIS casser un
				-- appel du jeu qui passe par ce hook.
				pcall(function()
					log("OUT", "%s:%s(%s)", remoteName, callMethod, desc)
				end)
			end
		end
		return old(self, ...)
	end)
end)

arm("remotes entrants", function()
	local found = 0
	for _, name in ipairs({ "DataEvent", "CombatEvent", "EffectEvent" }) do
		local remote = ReplicatedStorage:FindFirstChild(name, true)
		if remote and remote:IsA("RemoteEvent") then
			found = found + 1
			keep(remote.OnClientEvent:Connect(function(...)
				local first = (select(1, ...))
				if not (typeof(first) == "string" and NOISE[first]) then
					-- Meme raison que pour les sortants : `...` mis en forme hors
					-- de la closure du pcall (Luau l'interdit a l'interieur).
					local desc = describeArgs(...)
					pcall(function() log("IN", "%s(%s)", name, desc) end)
				end
			end))
		end
	end
	assert(found > 0, "aucun RemoteEvent connu trouve")
end)

arm("notre personnage", function()
	local function watchCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.AnimationPlayed:Connect(function(track)
				local anim = track.Animation
				log("ME", "anim %s", anim and tostring(anim.AnimationId) or "?")
			end)
		end

		-- Un dodge peut passer par un BodyMover ou une contrainte plutot que par
		-- un CFrame pose chaque frame : c'est justement ce qu'on veut savoir.
		character.DescendantAdded:Connect(function(obj)
			if obj:IsA("BodyMover") or obj:IsA("Constraint") then
				log("MOVER", "+ %s (%s) sur %s", obj.ClassName, obj.Name,
					obj.Parent and obj.Parent.Name or "?")
			end
		end)

		-- PBCooldown = Perfect Block reussi, M1XPCD = coup porte : ca dit si la
		-- reference bloque ou attaque, sans avoir a le deduire des animations.
		character.AttributeChanged:Connect(function(attr)
			log("STATE", "attribut %s = %s", attr, tostring(character:GetAttribute(attr)))
		end)
	end

	if LocalPlayer.Character then task.spawn(watchCharacter, LocalPlayer.Character) end
	keep(LocalPlayer.CharacterAdded:Connect(watchCharacter))
end)

arm("Settings joueur", function()
	local settings = ReplicatedStorage:FindFirstChild("Settings")
	local mine = settings and settings:FindFirstChild(LocalPlayer.Name)
	assert(mine, "ReplicatedStorage.Settings." .. LocalPlayer.Name .. " introuvable")
	local n = 0
	for _, value in ipairs(mine:GetChildren()) do
		if value:IsA("ValueBase") then
			n = n + 1
			keep(value.Changed:Connect(function(newValue)
				log("STATE", "Settings.%s = %s", value.Name, tostring(newValue))
			end))
		end
	end
	log("INIT", "  (%d valeurs suivies)", n)
end)

--------------------------------------------------------------------------------
-- Verdict par attaque
--------------------------------------------------------------------------------
-- Sur Spire/Dragon, on ouvre une fenetre de 3,5 s et on resume en UNE ligne :
-- PV perdus, bande de hauteur occupee, et sommet du hazard apparu. C'est
-- exactement ce qu'il faut pour juger un reglage sans redepouiller tout le log.
--
-- Bandes mesurees sur un combat complet :
--   Spire  -> WormBranch (pics de sol) Y 325-341
--   Dragon -> Hitbox a hauteur de vol  Y 372-373
-- D'ou le creneau vise, que ni l'une ni l'autre n'atteint : Y 345-365.
local DODGE_ANIMS = { ["116907126244057"] = "SPIRE", ["120758909308511"] = "DRAGON" }
local SAFE_LOW, SAFE_HIGH = 345, 365

local function reportDodge(kind)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end

	local hpStart = humanoid.Health
	local minY, maxY = math.huge, -math.huge
	local inSafe, total = 0, 0
	local hazardTop = -math.huge

	-- Sommet atteint par les pics apparus pendant la fenetre.
	local conn = workspace.DescendantAdded:Connect(function(obj)
		if obj:IsA("BasePart") and obj.Name == "WormBranch" then
			local ok, pos = pcall(function() return obj.Position end)
			if ok and pos.Y > hazardTop then hazardTop = pos.Y end
		end
	end)

	task.spawn(function()
		local deadline = os.clock() + 3.5
		while os.clock() < deadline do
			local y = root.Position.Y
			minY, maxY = math.min(minY, y), math.max(maxY, y)
			total = total + 1
			if y >= SAFE_LOW and y <= SAFE_HIGH then inSafe = inSafe + 1 end
			task.wait(0.05)
		end
		conn:Disconnect()

		local lost = hpStart - humanoid.Health
		log("VERDICT", "%s : PV %s%d  |  Y %.0f-%.0f  |  creneau sur %d%% du temps  |  sommet hazard %s",
			kind,
			lost > 0 and "-" or "=", math.abs(math.floor(lost)),
			minY, maxY,
			total > 0 and math.floor(inSafe / total * 100) or 0,
			hazardTop > -math.huge and string.format("%.1f", hazardTop) or "aucun")
	end)
end

arm("boss", function()
	local function watchBoss(model)
		if S.boss == model then return end
		if S.bossConn then S.bossConn:Disconnect() end
		S.boss = model
		local humanoid = model:FindFirstChild("Humanoid")
		if humanoid then
			S.bossConn = humanoid.AnimationPlayed:Connect(function(track)
				local anim = track.Animation
				local id = anim and tostring(anim.AnimationId) or "?"
				log("BOSS", "anim %s", id)
				for needle, kind in pairs(DODGE_ANIMS) do
					if string.find(id, needle, 1, true) then
						reportDodge(kind)
						break
					end
				end
			end)
		end
		log("BOSS", "suivi : %s  pv=%d", model:GetFullName(),
			humanoid and math.floor(humanoid.Health) or -1)
	end

	keep(workspace.ChildAdded:Connect(function(child)
		if child.Name == BOSS_NAME then
			task.wait(0.2)
			local m = findBoss()
			if m then watchBoss(m) end
		end
	end))

	local existing = findBoss()
	if existing then watchBoss(existing) else log("INIT", "  (boss absent pour l'instant)") end
end)

arm("parties de l'arene", function()
	keep(workspace.DescendantAdded:Connect(function(obj)
		if not obj:IsA("BasePart") then return end
		local ok, pos = pcall(function() return obj.Position end)
		if not ok then return end
		if (pos - ARENA_CENTER).Magnitude > ARENA_RADIUS then return end
		log("PART", "+ %s (%s) a V3(%.1f, %.1f, %.1f) taille %s",
			obj.Name, obj.ClassName, pos.X, pos.Y, pos.Z, tostring(obj.Size))
	end))
end)

arm("position/PV", function()
	task.spawn(function()
		local lastHp = nil
		while task.wait(0.1) and SNIFF.gen == GEN do
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			if root and humanoid then
				-- offY seul ne suffisait pas : sans la position du boss on ne peut
				-- pas comparer la DISTANCE HORIZONTALE a laquelle chacun plane,
				-- alors que c'est la piste principale pour expliquer pourquoi la
				-- reference ne prend pas les attaques normales du boss.
				local offY, dist = 0, -1
				if S.boss and S.boss.Parent then
					local anchor = S.boss:FindFirstChild("HumanoidRootPart")
					if anchor then
						offY = root.Position.Y - anchor.Position.Y
						local d = root.Position - anchor.Position
						dist = math.sqrt(d.X * d.X + d.Z * d.Z)
					end
				end

				local hp = math.floor(humanoid.Health)
				local marker = ""
				if lastHp and hp < lastHp then
					marker = string.format("   <<< DEGATS -%d", lastHp - hp)
				end
				lastHp = hp

				log("POS", "hp=%d pos=(%.2f, %.2f, %.2f) offY=%.1f distXZ=%.1f anch=%s plat=%s vel=%.1f%s",
					hp, root.Position.X, root.Position.Y, root.Position.Z, offY, dist,
					tostring(root.Anchored), tostring(humanoid.PlatformStand),
					root.AssemblyLinearVelocity.Magnitude, marker)
			end

			if not findBoss() and S.boss then
				S.boss = nil
				if S.bossConn then S.bossConn:Disconnect() S.bossConn = nil end
			end
		end
	end)
end)

log("INIT", "--- arme. Lance ton script de reference, puis fais le %s. ---", BOSS_NAME)
