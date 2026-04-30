

--// SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

--// DATASTORE
local DataStore = DataStoreService:GetDataStore("FinalSubmission_FIXED_v2")

--// REMOTES
local folder = ReplicatedStorage:FindFirstChild("CombatEvents") or Instance.new("Folder")
folder.Name = "CombatEvents"
folder.Parent = ReplicatedStorage

local function remote(name)
	local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end

local PunchEvent = remote("PunchEvent")
local KickEvent = remote("KickEvent")
local BlockEvent = remote("BlockEvent")

--// PLAYER SYSTEM
local PlayerClass = {}
PlayerClass.__index = PlayerClass
PlayerClass.Cache = {}

function PlayerClass.new(player)
	local self = setmetatable({}, PlayerClass)

	self.Player = player
	self.UserId = player.UserId

	self.Data = {
		Coins = 0,
		Damage = 10,
		Upgrade = 1
	}

	self.Combo = 0
	self.LastHit = 0
	self.Blocking = false
	self.Stamina = 100
	self.Cooldowns = {}
	self.Dirty = false

	PlayerClass.Cache[player] = self
	return self
end

--// LOAD DATA
function PlayerClass:Load()
	local success, data = pcall(function()
		return DataStore:GetAsync(self.UserId)
	end)

	if success and data then
		self.Data = data
	end
end

--// SAVE DATA (SAFE)
function PlayerClass:Save()
	if not self.Dirty then return end

	pcall(function()
		DataStore:SetAsync(self.UserId, self.Data)
	end)

	self.Dirty = false
end

--// DAMAGE CALC
function PlayerClass:GetDamage()
	return self.Data.Damage + (self.Data.Upgrade * 2)
end

--// COOLDOWN
function PlayerClass:CanAct(action)
	local now = os.clock()
	if self.Cooldowns[action] and now - self.Cooldowns[action] < 0.35 then
		return false
	end
	self.Cooldowns[action] = now
	return true
end

--// STAMINA
function PlayerClass:UseStamina(amount)
	if self.Stamina < amount then return false end
	self.Stamina -= amount
	return true
end

function PlayerClass:Regen()
	self.Stamina = math.min(100, self.Stamina + 0.4)
end

--// HELPERS
local function getChar(p) return p.Character end
local function getRoot(c) return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum(c) return c and c:FindFirstChildOfClass("Humanoid") end

--// VALID TARGET CHECK
local function getTargetData(player)
	local char = player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")

	if not root or not hum or hum.Health <= 0 then
		return
	end

	return char, root, hum
end

--// PHYSICS
local function knockback(attRoot, tarRoot, power)
	local dir = (tarRoot.Position - attRoot.Position)
	if dir.Magnitude == 0 then return end
	dir = dir.Unit

	target.AssemblyLinearVelocity = dir * power + Vector3.new(0, power * 0.4, 0)
end

--// DAMAGE APPLY
local function applyDamage(hum, amount)
	if hum and hum.Health > 0 then
		hum:TakeDamage(amount)
	end
end

--// CORE HIT (FIXED RELIABLE SYSTEM)
local function hit(attacker, targetPlayer, mult)
	local aChar = attacker.Player.Character
	local tChar, tRoot, tHum = getTargetData(targetPlayer)
	if not aChar or not tChar then return end

	local aRoot = aChar:FindFirstChild("HumanoidRootPart")
	if not aRoot or not tRoot or not tHum then return end

	-- distance check
	local dist = (aRoot.Position - tRoot.Position).Magnitude
	if dist > 8 then return end

	-- direction check (TSB style)
	local dir = aRoot.CFrame.LookVector
	local toTarget = (tRoot.Position - aRoot.Position).Unit
	local dot = dir:Dot(toTarget)

	if dot < 0.2 then return end

	local dmg = attacker:GetDamage() * mult

	if attacker.Blocking then
		dmg *= 0.35
	end

	applyDamage(tHum, dmg)
	knockback(aRoot, tRoot, 60 * mult)
end

--// PUNCH
PunchEvent.OnServerEvent:Connect(function(player)
	local obj = PlayerClass.Cache[player]
	if not obj or not obj:CanAct("Punch") then return end
	if not obj:UseStamina(10) then return end

	obj.Combo += 1
	if os.clock() - obj.LastHit > 2 then
		obj.Combo = 1
	end
	obj.LastHit = os.clock()

	obj.Dirty = true

	for _, p in pairs(Players:GetPlayers()) do
		if p ~= player then
			hit(obj, p, 1 + obj.Combo * 0.1)
		end
	end
end)

--// KICK
KickEvent.OnServerEvent:Connect(function(player)
	local obj = PlayerClass.Cache[player]
	if not obj or not obj:CanAct("Kick") then return end
	if not obj:UseStamina(20) then return end

	obj.Dirty = true

	for _, p in pairs(Players:GetPlayers()) do
		if p ~= player then
			hit(obj, p, 1.5)
		end
	end
end)

--// BLOCK
BlockEvent.OnServerEvent:Connect(function(player, state)
	local obj = PlayerClass.Cache[player]
	if obj then
		obj.Blocking = state
	end
end)

--// PLAYER JOIN
Players.PlayerAdded:Connect(function(player)
	local obj = PlayerClass.new(player)
	obj:Load()
end)

--// PLAYER LEAVE
Players.PlayerRemoving:Connect(function(player)
	local obj = PlayerClass.Cache[player]
	if obj then
		obj:Save()
		PlayerClass.Cache[player] = nil
	end
end)

--// SINGLE OPTIMIZED LOOP
while true do
	task.wait(1)

	for _, obj in pairs(PlayerClass.Cache) do
		obj:Regen()
		obj:Save()
	end
end
