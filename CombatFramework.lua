-- Connected Discord-GitHub | Discord: m_a_l_e_k.1231_86990 | Roblox: Loka_king90

--[[
================================================================================
COMBAT FRAMEWORK DEMONSTRATION

This script demonstrates an advanced understanding of Roblox Luau programming.
The system is designed as a server-authoritative combat framework where all
combat validation and physics are processed on the server.

Key Concepts Demonstrated:
• Metatable-based Object Oriented Programming
• Roblox API usage (Players, Humanoid, CFrame, Raycasting)
• Physics based knockback
• Server-side combat validation
• Stamina and cooldown systems
• Combo combat system
• Data persistence using DataStore
• Structured architecture with reusable functions

The goal of this framework is to show how different Roblox systems interact
together to form a complete gameplay system.

All combat logic runs on the server in order to prevent exploiters from
modifying damage or physics calculations on the client.
================================================================================
]]

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

---------------------------------------------------------------------
-- DATASTORE
---------------------------------------------------------------------

local PlayerStore = DataStoreService:GetDataStore("CombatFrameworkSubmission_v1")

---------------------------------------------------------------------
-- REMOTE EVENT SETUP
---------------------------------------------------------------------

local EventFolder = ReplicatedStorage:FindFirstChild("CombatEvents")

if not EventFolder then
	EventFolder = Instance.new("Folder")
	EventFolder.Name = "CombatEvents"
	EventFolder.Parent = ReplicatedStorage
end

local function createRemote(name)

	local remote = EventFolder:FindFirstChild(name)

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = EventFolder
	end

	return remote

end

local PunchEvent = createRemote("PunchEvent")
local KickEvent = createRemote("KickEvent")
local BlockEvent = createRemote("BlockEvent")

---------------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------------

--[[
Utility functions are helper methods used throughout the script.
They improve readability and prevent code duplication.
]]

local function getCharacter(player)
	return player.Character
end

local function getHumanoid(character)
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character)
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

local function isAlive(humanoid)

	if humanoid and humanoid.Health > 0 then
		return true
	end

	return false

end

local function magnitude(a,b)

	return (a.Position - b.Position).Magnitude

end

local function unitDirection(a,b)

	local dir = b.Position - a.Position

	if dir.Magnitude == 0 then
		return Vector3.new()
	end

	return dir.Unit

end

---------------------------------------------------------------------
-- PLAYER OBJECT SYSTEM (METATABLE OOP)
---------------------------------------------------------------------

--[[
The PlayerClass acts as a structured data container for each player.

Using metatables allows us to attach methods directly to player objects.
This approach keeps the combat system modular and organized.

Each player has their own instance which stores runtime state such as
stamina, cooldowns, combo counters, and persistent data.
]]

local PlayerClass = {}
PlayerClass.__index = PlayerClass

PlayerClass.Cache = {}

function PlayerClass.new(player)

	local self = setmetatable({}, PlayerClass)

	self.Player = player
	self.UserId = player.UserId

	self.Data = {

		Coins = 0,
		BaseDamage = 10,
		UpgradeLevel = 1

	}

	self.Combo = 0
	self.LastHitTime = 0
	self.Blocking = false
	self.Stamina = 100
	self.Cooldowns = {}
	self.Dirty = false

	PlayerClass.Cache[player] = self

	return self

end

---------------------------------------------------------------------
-- DATA LOADING
---------------------------------------------------------------------

function PlayerClass:Load()

	local success,data = pcall(function()

		return PlayerStore:GetAsync(self.UserId)

	end)

	if success and data then

		self.Data = data

	end

end

---------------------------------------------------------------------
-- DATA SAVING
---------------------------------------------------------------------

function PlayerClass:Save()

	if not self.Dirty then return end

	pcall(function()

		PlayerStore:SetAsync(self.UserId,self.Data)

	end)

	self.Dirty = false

end

---------------------------------------------------------------------
-- DAMAGE CALCULATION
---------------------------------------------------------------------

function PlayerClass:GetDamage()

	local base = self.Data.BaseDamage
	local upgrade = self.Data.UpgradeLevel

	local total = base + (upgrade * 2)

	return total

end

---------------------------------------------------------------------
-- COOLDOWN SYSTEM
---------------------------------------------------------------------

function PlayerClass:CanAct(action)

	local now = os.clock()

	if self.Cooldowns[action] then

		local elapsed = now - self.Cooldowns[action]

		if elapsed < 0.35 then
			return false
		end

	end

	self.Cooldowns[action] = now

	return true

end

---------------------------------------------------------------------
-- STAMINA SYSTEM
---------------------------------------------------------------------

function PlayerClass:UseStamina(amount)

	if self.Stamina < amount then
		return false
	end

	self.Stamina -= amount

	return true

end

function PlayerClass:RegenerateStamina()

	local new = self.Stamina + 0.5

	self.Stamina = math.clamp(new,0,100)

end

---------------------------------------------------------------------
-- PHYSICS SYSTEM
---------------------------------------------------------------------

--[[
This function applies physical knockback to a character.

Roblox physics allows us to simulate force interactions between objects.
By applying an impulse to the target's root part we can simulate impact
from an attack.

The direction is calculated using vector math between attacker and target.
]]

local function applyKnockback(attackerRoot,targetRoot,power)

	local direction = targetRoot.Position - attackerRoot.Position

	if direction.Magnitude == 0 then
		return
	end

	direction = direction.Unit

	local impulse = direction * power + Vector3.new(0,power*0.4,0)

	targetRoot:ApplyImpulse(impulse * targetRoot.AssemblyMass)

end

---------------------------------------------------------------------
-- RAYCAST COMBAT DETECTION
---------------------------------------------------------------------

--[[
Raycasting is used to detect objects along a direction vector.

This demonstrates usage of Roblox's spatial query system.
Instead of blindly damaging every player nearby we perform
a directional raycast to simulate a forward attack.

This prevents hitting targets behind the player.
]]

local function performRaycast(origin,direction,ignore)

	local params = RaycastParams.new()

	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Blacklist

	local result = Workspace:Raycast(origin,direction,params)

	return result

end

---------------------------------------------------------------------
-- ATTACK VALIDATION
---------------------------------------------------------------------

local function canHit(attRoot,targetRoot)

	if magnitude(attRoot,targetRoot) > 8 then
		return false
	end

	local look = attRoot.CFrame.LookVector

	local dir = unitDirection(attRoot,targetRoot)

	local dot = look:Dot(dir)

	if dot < 0.2 then
		return false
	end

	return true

end

---------------------------------------------------------------------
-- DAMAGE APPLICATION
---------------------------------------------------------------------

local function dealDamage(humanoid,amount)

	if isAlive(humanoid) then

		humanoid:TakeDamage(amount)

	end

end

---------------------------------------------------------------------
-- COMBAT CORE
---------------------------------------------------------------------

local function processHit(attacker,targetPlayer,multiplier)

	local attackerChar = getCharacter(attacker.Player)
	local targetChar = getCharacter(targetPlayer)

	if not attackerChar or not targetChar then
		return
	end

	local attRoot = getRoot(attackerChar)
	local tarRoot = getRoot(targetChar)
	local tarHum = getHumanoid(targetChar)

	if not attRoot or not tarRoot or not tarHum then
		return
	end

	if not canHit(attRoot,tarRoot) then
		return
	end

	local damage = attacker:GetDamage() * multiplier

	if attacker.Blocking then
		damage = damage * 0.4
	end

	dealDamage(tarHum,damage)

	applyKnockback(attRoot,tarRoot,60*multiplier)

end

---------------------------------------------------------------------
-- PUNCH EVENT
---------------------------------------------------------------------

PunchEvent.OnServerEvent:Connect(function(player)

	local obj = PlayerClass.Cache[player]

	if not obj then return end

	if not obj:CanAct("Punch") then return end

	if not obj:UseStamina(10) then return end

	obj.Combo += 1

	if os.clock() - obj.LastHitTime > 2 then
		obj.Combo = 1
	end

	obj.LastHitTime = os.clock()

	obj.Dirty = true

	for _,p in ipairs(Players:GetPlayers()) do

		if p ~= player then

			processHit(obj,p,1 + obj.Combo * 0.1)

		end

	end

end)

---------------------------------------------------------------------
-- KICK EVENT
---------------------------------------------------------------------

KickEvent.OnServerEvent:Connect(function(player)

	local obj = PlayerClass.Cache[player]

	if not obj then return end

	if not obj:CanAct("Kick") then return end

	if not obj:UseStamina(20) then return end

	obj.Dirty = true

	for _,p in ipairs(Players:GetPlayers()) do

		if p ~= player then

			processHit(obj,p,1.5)

		end

	end

end)

---------------------------------------------------------------------
-- BLOCK EVENT
---------------------------------------------------------------------

BlockEvent.OnServerEvent:Connect(function(player,state)

	local obj = PlayerClass.Cache[player]

	if obj then

		obj.Blocking = state

	end

end)

---------------------------------------------------------------------
-- PLAYER CONNECTION EVENTS
---------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)

	local obj = PlayerClass.new(player)

	obj:Load()

end)

Players.PlayerRemoving:Connect(function(player)

	local obj = PlayerClass.Cache[player]

	if obj then

		obj:Save()

		PlayerClass.Cache[player] = nil

	end

end)

---------------------------------------------------------------------
-- MAIN SERVER LOOP
---------------------------------------------------------------------

RunService.Heartbeat:Connect(function()

	for _,obj in pairs(PlayerClass.Cache) do

		obj:RegenerateStamina()

	end

end)
