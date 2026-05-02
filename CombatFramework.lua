--// =========================================================
--// PURPOSE:
--// Demonstrates advanced Luau systems:
--// OOP, combat validation, physics, state machine,
--// stamina layers, cooldown architecture, hit logic expansion
--// =========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Store = DataStoreService:GetDataStore("CombatFramework_300Plus")

local folder = ReplicatedStorage:FindFirstChild("CombatEvents")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "CombatEvents"
	folder.Parent = ReplicatedStorage
end

local function makeRemote(name)
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	return r
end

local PunchEvent = makeRemote("PunchEvent")
local KickEvent = makeRemote("KickEvent")
local BlockEvent = makeRemote("BlockEvent")

--// =========================================================
--// UTILITY SYSTEM
--// =========================================================

local function getChar(p)
	return p.Character
end

local function getRoot(c)
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum(c)
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function alive(h)
	return h and h.Health > 0
end

local function dist(a,b)
	return (a.Position - b.Position).Magnitude
end

local function clamp01(v)
	if v < 0 then return 0 end
	if v > 1 then return 1 end
	return v
end

local function normalize(v)
	if v.Magnitude == 0 then return Vector3.zero end
	return v.Unit
end

--// =========================================================
--// PLAYER CLASS
--// =========================================================

local PlayerClass = {}
PlayerClass.__index = PlayerClass
PlayerClass.Cache = {}

function PlayerClass.new(player)
	local self = setmetatable({}, PlayerClass)

	self.Player = player
	self.Id = player.UserId

	self.Data = {
		Coins = 0,
		Damage = 10,
		Upgrade = 1
	}

	self.Combo = 0
	self.LastHit = 0
	self.Blocking = false

	self.Stamina = 100
	self.MaxStamina = 100

	self.Sprinting = false
	self.Attacking = false

	self.Cooldowns = {}
	self.State = "Idle"

	self.Dirty = false

	PlayerClass.Cache[player] = self
	return self
end

function PlayerClass:Load()
	local ok, data = pcall(function()
		return Store:GetAsync(self.Id)
	end)

	if ok and data then
		self.Data = data
	end
end

function PlayerClass:Save()
	if not self.Dirty then return end
	pcall(function()
		Store:SetAsync(self.Id, self.Data)
	end)
	self.Dirty = false
end

function PlayerClass:GetDamage()
	return self.Data.Damage + (self.Data.Upgrade * 2)
end

function PlayerClass:CanAct(action)
	local now = os.clock()
	if self.Cooldowns[action] and now - self.Cooldowns[action] < 0.3 then
		return false
	end
	self.Cooldowns[action] = now
	return true
end

function PlayerClass:UseStamina(amount)
	if self.Stamina < amount then return false end
	self.Stamina -= amount
	return true
end

function PlayerClass:Regen()
	if self.State == "Idle" then
		self.Stamina = math.min(self.MaxStamina, self.Stamina + 0.6)
	else
		self.Stamina = math.min(self.MaxStamina, self.Stamina + 0.2)
	end
end

function PlayerClass:SetState(state)
	self.State = state
end

--// =========================================================
--// HIT VALIDATION SYSTEM
--// =========================================================

local function directionCheck(aRoot, tRoot)
	local look = aRoot.CFrame.LookVector
	local dir = normalize(tRoot.Position - aRoot.Position)
	local dot = look:Dot(dir)
	return dot
end

local function canHit(aRoot, tRoot)
	if dist(aRoot,tRoot) > 8 then return false end
	if directionCheck(aRoot,tRoot) < 0.15 then return false end
	return true
end

--// =========================================================
--// PHYSICS SYSTEM
--// =========================================================

local function knockback(aRoot, tRoot, power)
	local dir = normalize(tRoot.Position - aRoot.Position)
	tRoot.AssemblyLinearVelocity =
		dir * power + Vector3.new(0, power * 0.35, 0)
end

--// =========================================================
--// DAMAGE SYSTEM
--// =========================================================

local function applyDamage(hum, dmg)
	if alive(hum) then
		hum:TakeDamage(dmg)
	end
end

--// =========================================================
--// CORE HIT SYSTEM
--// =========================================================

local function hit(attacker, targetPlayer, mult)
	local aChar = getChar(attacker.Player)
	local tChar = getChar(targetPlayer)

	if not aChar or not tChar then return end

	local aRoot = getRoot(aChar)
	local tRoot = getRoot(tChar)
	local tHum = getHum(tChar)

	if not aRoot or not tRoot or not tHum then return end

	if not canHit(aRoot,tRoot) then return end

	local dmg = attacker:GetDamage() * mult

	if attacker.Blocking then
		dmg *= 0.4
	end

	applyDamage(tHum, dmg)
	knockback(aRoot,tRoot,60 * mult)
end

--// =========================================================
--// PUNCH SYSTEM (EXPANDED LOGIC)
--// =========================================================

PunchEvent.OnServerEvent:Connect(function(player)
	local obj = PlayerClass.Cache[player]
	if not obj then return end
	if not obj:CanAct("Punch") then return end
	if not obj:UseStamina(10) then return end

	obj.Attacking = true
	obj:SetState("Attack")

	obj.Combo += 1

	if os.clock() - obj.LastHit > 1.8 then
		obj.Combo = 1
	end

	obj.LastHit = os.clock()
	obj.Dirty = true

	for _,p in pairs(Players:GetPlayers()) do
		if p ~= player then
			hit(obj,p,1 + obj.Combo * 0.12)
		end
	end

	obj.Attacking = false
	obj:SetState("Idle")
end)

--// =========================================================
--// KICK SYSTEM
--// =========================================================

KickEvent.OnServerEvent:Connect(function(player)
	local obj = PlayerClass.Cache[player]
	if not obj then return end
	if not obj:CanAct("Kick") then return end
	if not obj:UseStamina(18) then return end

	obj:SetState("Attack")
	obj.Dirty = true

	for _,p in pairs(Players:GetPlayers()) do
		if p ~= player then
			hit(obj,p,1.6)
		end
	end

	obj:SetState("Idle")
end)

--// =========================================================
--// BLOCK SYSTEM
--// =========================================================

BlockEvent.OnServerEvent:Connect(function(player,state)
	local obj = PlayerClass.Cache[player]
	if obj then
		obj.Blocking = state
		if state then
			obj:SetState("Block")
		else
			obj:SetState("Idle")
		end
	end
end)

--// =========================================================
--// PLAYER SYSTEM
--// =========================================================

Players.PlayerAdded:Connect(function(p)
	local obj = PlayerClass.new(p)
	obj:Load()
end)

Players.PlayerRemoving:Connect(function(p)
	local obj = PlayerClass.Cache[p]
	if obj then
		obj:Save()
		PlayerClass.Cache[p] = nil
	end
end)

--// =========================================================
--// MAIN LOOP (EXPANDED SYSTEMS)
--// =========================================================

task.spawn(function()
	while true do
		task.wait(0.8)

		for _,obj in pairs(PlayerClass.Cache) do
			obj:Regen()

			if obj.Stamina <= 0 then
				obj:SetState("Exhausted")
			end

			obj.Dirty = true
		end
	end
end)

--// ADDITIONAL PROCESS LOOP (STATE MANAGEMENT)
task.spawn(function()
	while true do
		task.wait(1)

		for _,obj in pairs(PlayerClass.Cache) do
			if obj.State == "Exhausted" then
				obj.Stamina += 1
			end

			if obj.Stamina > 30 and obj.State == "Exhausted" then
				obj:SetState("Idle")
			end
		end
	end
end)

--// =========================================================
--// END FRAMEWORK
--// =========================================================
