--bypass
repeat task.wait() until game:IsLoaded()

local function isAdonisAC(tab) 
    return rawget(tab,"Detected") and typeof(rawget(tab,"Detected"))=="function" and rawget(tab,"RLocked") 
end

for _,v in next,getgc(true) do 
    if typeof(v)=="table" and isAdonisAC(v) then 
        for i,f in next,v do 
            if rawequal(i,"Detected") then 
                local old 
                old=hookfunction(f,function(action,info,crash)
                    if rawequal(action,"_") and rawequal(info,"_") and rawequal(crash,false) then 
                        return old(action,info,crash) 
                    end 
                    return task.wait(9e9) 
                end) 
                warn("bypassed") 
                break 
            end 
        end 
    end 
end

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local RepStorage  = game:GetService("ReplicatedStorage")
local Workspace   = game:GetService("Workspace")
local Debris      = game:GetService("Debris")
local UIS         = game:GetService("UserInputService")
local CoreGui     = game:GetService("CoreGui")
local Light       = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local Events    = RepStorage:WaitForChild("Events")
local GN_S      = Events:WaitForChild("GNX_S")
local GN_R      = Events:WaitForChild("GNX_R")
local ZF_H      = Events:WaitForChild("ZFKLF__H")

local BlackList, WhiteList = {}, {}
local function IsBlack(n) return BlackList[n] == true end
local function IsWhite(n) return WhiteList[n] == true end

local Config = {
    -- Ragebot
    Enabled         = false,
    AutoReload      = true,
    DownCheck       = false,
    TargetMode      = "Near",
    BlackPriority   = true,
    FriendlyFire    = true,

    -- 缓存
    CacheThreshold  = 0.75,
    CacheLookCos    = 0.95,

    -- 弹道扫描参数
    PathOriginR     = 18.5,
    PathTargetR     = 23.5,
    PathScans       = 24,
    PathScanRate    = 14,
    PathMaxDist     = 820,

    -- 4 Scanners（Legacy 备份）
    OriginShift        = false,
    OriginShiftRange   = 6.0,
    OriginShiftScans   = 24,
    TargetShift        = false,
    TargetShiftRange   = 7.5,
    TargetShiftScans   = 24,
    CrossShift         = false,
    Wallbang           = false,
    WallbangRange      = 7.0,

    -- Visuals
    HitSound        = "None",
    TracerEnabled   = false,
    HitLogEnabled   = false,
    HitLogMax       = 8,
    HitLogLifetime  = 5,

    -- ESP
    ESP_Enabled     = true,
    ESP_OnlyListed  = false,
    ESP_TeamCheck   = true,
    ESP_Box         = true,
    ESP_Health      = true,
    ESP_HealthText  = true,
    ESP_Name        = true,
    ESP_Distance    = true,
    ESP_Weapon      = true,
    ESP_Chams       = false,
    ESP_ChamsAlpha  = 0.6,
    ESP_MaxDist     = 1500,
    ESP_BlackColor  = Color3.fromRGB(255, 70, 70),
    ESP_WhiteColor  = Color3.fromRGB(70, 255, 120),
    ESP_NormalColor = Color3.fromRGB(180, 220, 255),
    ESP_FontSize    = 9,
    ESP_BoxThick    = 1,
}

local HitSounds = {
    ["Skeet"]     = "rbxassetid://5633695679",
    ["Neverlose"] = "rbxassetid://8726881116",
    ["Gamesense"] = "rbxassetid://4817809188",
}

local Last_Shot = 0

local function GetFireInterval(tool)
    if not tool then return 0.3 end
    local name = tool.Name
    if name == "Beretta" or name == "Tec-9" or name == "TEC-9" or name == "TEC 9" then
        return 0.05
    end
    return 0.3
end

local ClanControllerShared
local function SameTeam(player)
    if not player then return false end
    if not ClanControllerShared then
        pcall(function()
            local PS = LocalPlayer:FindFirstChild("PlayerScripts")
            local CC = PS and PS:FindFirstChild("ClanController")
            if CC and type(getsenv) == "function" then
                local Env = getsenv(CC)
                ClanControllerShared = Env and Env.shared
            end
        end)
    end
    local TeamCache = ClanControllerShared and ClanControllerShared.cachedTeamModels
    return (TeamCache and TeamCache[player.UserId]) and true or false
end

local FriendCache = setmetatable({}, { __mode = "k" })
local function IsFriend(player)
    if not player then return false end
    local c = FriendCache[player]
    local now = tick()
    if c and (now - c.t) < 3 then return c.v end
    local ok, v = pcall(function() return LocalPlayer:IsFriendsWith(player.UserId) end)
    v = ok and v == true
    FriendCache[player] = { t = now, v = v }
    return v
end

local function IsFriendly(player)
    if not player then return true end
    if player == LocalPlayer then return true end
    if IsWhite(player.Name) then return true end
    if not Config.FriendlyFire then return false end
    if SameTeam(player) then return true end
    if IsFriend(player) then return true end
    return false
end

local PHI = 0.6180339887

local function BuildOrthoBasis(dir)
    local u = dir.Unit
    local arb = math.abs(u.X) < 0.9 and Vector3.new(1,0,0) or Vector3.new(0,1,0)
    local t1 = u:Cross(arb).Unit
    local t2 = u:Cross(t1).Unit
    return t1, t2
end

local function FibonacciHemisphere(center, poleDir, radius, count)
    local pts = { center }
    if count <= 0 or radius <= 0 then return pts end
    local u = poleDir.Unit
    local t1, t2 = BuildOrthoBasis(u)
    for i = 0, count - 1 do
        local phi   = i * PHI * 2 * math.pi
        local cosT  = 1 - (i + 0.5) / count
        local sinT  = math.sqrt(math.max(0, 1 - cosT * cosT))
        local r     = radius * (math.random() ^ (1/3))
        local dir   = t1 * (sinT * math.cos(phi))
                    + t2 * (sinT * math.sin(phi))
                    + u  * cosT
        pts[#pts + 1] = center + dir * r
    end
    return pts
end

local GOLDEN = math.pi * (3 - math.sqrt(5))
local SEED   = 0

local function Sphere(center, radius, count)
    local pts = { center }
    if radius <= 0 or count <= 0 then return pts end
    for i = 1, count do
        local y     = 1 - (i / count) * 2
        local r     = math.sqrt(math.max(0, 1 - y * y))
        local theta = GOLDEN * i + SEED
        pts[i + 1]  = center + Vector3.new(math.cos(theta) * r, y, math.sin(theta) * r) * radius
    end
    return pts
end

local IGNORE_BUF = {}
local RAY_PARAMS = RaycastParams.new()
RAY_PARAMS.FilterType   = Enum.RaycastFilterType.Exclude
RAY_PARAMS.IgnoreWater  = true

local function BuildRayFilter(targetChar)
    local n = 0
    IGNORE_BUF = {}
    local char = LocalPlayer.Character
    if char        then n = n + 1; IGNORE_BUF[n] = char        end
    if Camera      then n = n + 1; IGNORE_BUF[n] = Camera      end
    if targetChar  then n = n + 1; IGNORE_BUF[n] = targetChar  end
    RAY_PARAMS.FilterDescendantsInstances = IGNORE_BUF
    return RAY_PARAMS
end

local function RayCheckTol(O, T, params)
    local d = T - O
    local dist = d.Magnitude
    if dist < 0.5 then return false end

    local allow
    if dist < 50 then allow = 20
    elseif dist < 150 then allow = 35
    else allow = 55 end

    local hit = Workspace:Raycast(O, d, params)
    if not hit then return true end
    return (hit.Position - T).Magnitude <= allow
end

local ScanParams = RaycastParams.new()
ScanParams.FilterType = Enum.RaycastFilterType.Exclude
ScanParams.IgnoreWater = true

local ScanFilter = {}
local function BuildParams()
    local n = 0
    local char = LocalPlayer.Character
    if char then n = n + 1; ScanFilter[n] = char end
    local vfx = Workspace:FindFirstChild("VFX")
    if vfx then n = n + 1; ScanFilter[n] = vfx end
    for i = #ScanFilter, n + 1, -1 do ScanFilter[i] = nil end
    ScanParams.FilterDescendantsInstances = ScanFilter
    return ScanParams
end

local function RayVisible(from, to, params)
    local hit = Workspace:Raycast(from, to - from, params)
    return not hit
end

local function RayHitsChar(from, targetPart, params)
    local hit = Workspace:Raycast(from, targetPart.Position - from, params)
    if not hit then return true end
    return hit.Instance and hit.Instance:IsDescendantOf(targetPart.Parent)
end

--===== 5.1 OriginShift =====
local function OriginScan(targetPart, originCF, params, range, scans)
    if not targetPart or not targetPart.Parent then return nil end
    if RayHitsChar(originCF.Position, targetPart, params) then return nil end

    local basePos  = originCF.Position
    local dir      = (targetPart.Position - basePos)
    if dir.Magnitude < 0.01 then return nil end

    local poleDir  = dir.Unit
    local points   = FibonacciHemisphere(basePos, poleDir, range or 6, scans or 24)

    local bestPos, bestDist
    for _, p in ipairs(points) do
        if RayVisible(basePos, p, params) then
            if RayHitsChar(p, targetPart, params) then
                local d = (p - basePos).Magnitude
                if not bestDist or d < bestDist then
                    bestDist = d
                    bestPos  = p
                end
            end
        end
    end
    return bestPos
end

--===== 5.2 TargetShift =====
local function TargetScan(targetPart, originCF, params, range, scans)
    if not targetPart or not targetPart.Parent then return nil end
    if RayHitsChar(originCF.Position, targetPart, params) then return nil end

    local basePos = targetPart.Position
    local poleDir = (originCF.Position - basePos)
    if poleDir.Magnitude < 0.01 then return nil end

    local points  = FibonacciHemisphere(basePos, poleDir, range or 7.5, scans or 24)

    local originPos = originCF.Position
    for _, p in ipairs(points) do
        if RayHitsChar(p, targetPart, params) then
            if RayVisible(originPos, p, params) then
                return p
            end
        end
    end
    return nil
end

--===== 5.3 CrossShift =====
local function CrossScan(targetPart, originCF, params, originRange, targetRange, scans)
    if not targetPart or not targetPart.Parent then return nil end
    if RayHitsChar(originCF.Position, targetPart, params) then return nil end

    local baseOrigin = originCF.Position
    local baseTarget = targetPart.Position

    local originPole = (baseTarget - baseOrigin).Unit
    local targetPole = (baseOrigin - baseTarget).Unit

    local originPts = FibonacciHemisphere(baseOrigin, originPole, originRange or 6, scans or 16)
    local targetPts = FibonacciHemisphere(baseTarget, targetPole, targetRange or 7.5, scans or 16)

    for _, o in ipairs(originPts) do
        if RayVisible(baseOrigin, o, params) then
            for _, t in ipairs(targetPts) do
                if RayHitsChar(t, targetPart, params) and RayVisible(o, t, params) then
                    return o, t
                end
            end
        end
    end
    return nil
end

--===== 5.4 Wallbang (Legacy 相机偏移法) =====
local function WallbangScan(targetPart, originCF, params, range)
    if not targetPart or not targetPart.Parent then return nil end
    if RayHitsChar(originCF.Position, targetPart, params) then return nil end

    local cam = Camera
    if not cam then return nil end

    local camCF       = cam.CFrame
    local camPos      = camCF.Position
    local targetPos   = targetPart.Position
    local targetChar  = targetPart.Parent

    local right   = camCF.RightVector
    local up      = Vector3.new(0, 1, 0)
    local horiz   = Vector3.new(right.X, 0, right.Z)
    if horiz.Magnitude < 0.01 then return nil end
    horiz = horiz.Unit

    local directions = {
        { horiz, range or 6 },
        { -horiz, range or 6 },
        { up, (range or 6) + 1 },
        { -up, (range or 6) + 1 },
    }

    local bestPos, bestDist
    for _, d in ipairs(directions) do
        local dirV = d[1]; local dist = d[2]
        local hit  = Workspace:Raycast(camPos, dirV * dist, params)
        if hit then
            local check = hit.Position - hit.Normal * 0.1
            local delta = check - camPos
            local deltaMag = delta.Magnitude
            if deltaMag > 0.1 then
                local hit2 = Workspace:Raycast(check, targetPos - check, params)
                if (not hit2) or (hit2.Instance and hit2.Instance:IsDescendantOf(targetChar)) then
                    if not bestDist or deltaMag < bestDist then
                        bestDist = deltaMag
                        bestPos  = check
                    end
                end
            end
        end
    end
    return bestPos
end

local function ScanBulletPath(myPos, tPos, targetChar)
    local axis = tPos - myPos
    if axis.Magnitude < 0.01 then return nil, nil end
    axis = axis.Unit

    local params = BuildRayFilter(targetChar)

    if RayCheckTol(myPos, tPos, params) then
        return myPos, tPos
    end

    local originR = Config.PathOriginR
    local targetR = Config.PathTargetR
    local count   = Config.PathScans

    local so = Sphere(myPos, originR, count)
    local st = Sphere(tPos,  targetR, count)

    for i = 1, #so do
        for j = 1, #st do
            if i ~= 1 or j ~= 1 then
                if RayCheckTol(so[i], st[j], params) then
                    return so[i], st[j]
                end
            end
        end
    end

    return nil, nil
end

local HookedFuncs = setmetatable({}, { __mode = "k" })
local NetworkFire

local function TryHookNetworkFunction(fn)
    if HookedFuncs[fn] then return end
    if type(fn) ~= "function" then return end
    local ok, consts = pcall(debug.getconstants, fn)
    if not ok or type(consts) ~= "table" then return end
    if consts[1] ~= "Parent" or consts[2] ~= "CFrame" then return end
    HookedFuncs[fn] = true

    local old = fn
    local new = function(rt, remote, hash, ...)
        NetworkFire = new
        return old(rt, remote, hash, ...)
    end
    pcall(function() debug.setupvalue(fn, 1, new) end)
    if hookfunction then
        local hooked = hookfunction(fn, function(...)
            return old(...)
        end)
        HookedFuncs[fn] = hooked or old
    end
end

local function ScanForNetworkFunction()
    if type(getgc) ~= "function" then return false end
    local found = false
    for _, fn in next, getgc(false) do
        if type(fn) == "function" then
            local info = debug.getinfo(fn)
            if info and info.source and info.source:find("ViewmodelController") then
                local ok, consts = pcall(debug.getconstants, fn)
                if ok and type(consts) == "table" and consts[1] == "Parent" and consts[2] == "CFrame" then
                    TryHookNetworkFunction(fn)
                    found = true
                end
            end
        end
    end
    return found
end

task.spawn(function()
    for _ = 1, 40 do
        if NetworkFire then break end
        ScanForNetworkFunction()
        task.wait(0.25)
    end
end)

local Last_Solution
local Last_Shot_Time = 0

-- ★ 修复 1：SolutionCache 增加 Char 字段
local SolutionCache = {
    Solution = nil,
    MyPos    = nil,
    TPos     = nil,
    Target   = nil,
    Char     = nil,   -- 新增：绑定缓存对应的 Character 实例
    Age      = 0,
    MaxAge   = 20,
}

local function GetLocalRealPosition()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or Vector3.zero
end

local function IsTargetAlive(p)
    if not p or not p.Parent then return false end
    local char = p.Character
    if not char or not char.Parent then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if char:FindFirstChildOfClass("ForceField") then return false end
    return true
end

local function IsLockValid(p)
    if not p or not p.Parent then return false end
    if not IsBlack(p.Name) then return false end
    if IsWhite(p.Name) then return false end
    if IsFriendly(p) then return false end
    if not IsTargetAlive(p) then return false end
    local ph = p.Character:FindFirstChildOfClass("Humanoid")
    if not ph or ph.Health <= (Config.DownCheck and 15 or 0) then return false end
    return true
end

-- ★ 修复 2：ClearSolution 同步清空 Char
local function ClearSolution()
    Last_Solution = nil
    SolutionCache.Solution = nil
    SolutionCache.Target   = nil
    SolutionCache.Char     = nil   -- 新增
end

local function GetTarget()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local mode    = Config.TargetMode
    local isLock  = mode == "Lock"
    local mouse   = UIS:GetMouseLocation()
    local center  = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local myPos   = GetLocalRealPosition()

    local best, bestMetric = nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and not IsWhite(p.Name) then
            if IsFriendly(p) then continue end
            if isLock and not IsBlack(p.Name) then continue end

            local pr = p.Character:FindFirstChild("HumanoidRootPart")
            local ph = p.Character:FindFirstChildOfClass("Humanoid")
            if not pr or not ph then continue end
            if ph.Health <= (Config.DownCheck and 15 or 0) then continue end
            if p.Character:FindFirstChildOfClass("ForceField") then continue end

            local metric
            if mode == "Near" or isLock then
                metric = (myPos - pr.Position).Magnitude
            elseif mode == "Mouse" then
                local sp, on = Camera:WorldToViewportPoint(pr.Position)
                if not on then continue end
                metric = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
            elseif mode == "Centre" then
                local sp, on = Camera:WorldToViewportPoint(pr.Position)
                if not on then continue end
                metric = (center - Vector2.new(sp.X, sp.Y)).Magnitude
            else
                metric = (myPos - pr.Position).Magnitude
            end

            if not isLock and Config.BlackPriority and IsBlack(p.Name) then
                metric = metric * 0.01
            end

            if metric < bestMetric then
                bestMetric = metric
                best = p
            end
        end
    end
    return best
end

-- ★ 修复 3：SolveForTarget 返回值附带 Char
local function SolveForTarget(target)
    if not target or not target.Character then return nil end

    local char = LocalPlayer.Character
    if not char then return nil end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local targetChar = target.Character
    local tRoot      = targetChar:FindFirstChild("HumanoidRootPart")
    if not tRoot then return nil end

    local dist = (myRoot.Position - tRoot.Position).Magnitude
    if dist > Config.PathMaxDist then return nil end

    local partName = dist > 400 and "Torso" or "Head"
    local hitPart  = targetChar:FindFirstChild(partName)
                  or targetChar:FindFirstChild("Head")
                  or targetChar:FindFirstChild("UpperTorso")
                  or tRoot
    if not hitPart then return nil end

    local origin, hitPos = ScanBulletPath(myRoot.Position, tRoot.Position, targetChar)
    if not origin or not hitPos then return nil end

    return {
        Target  = target,
        HitPart = hitPart,
        Origin  = origin,
        Hit     = hitPos,
        Mode    = "Path",
        Char    = targetChar,   -- 新增
    }
end

-- ★ 修复 4：主循环缓存校验加入 Char 一致性
RunService.Heartbeat:Connect(function(dt)
    SEED = SEED + 0.7
    if SEED > math.pi * 2 then SEED = SEED - math.pi * 2 end

    if not Config.Enabled then
        ClearSolution()
        return
    end

    local target = GetTarget()
    if not target then
        ClearSolution()
        return
    end

    local tChar = target.Character
    if not tChar or not tChar.Parent then
        ClearSolution()
        return
    end

    if SolutionCache.Solution and SolutionCache.Target == target
        and SolutionCache.Char == tChar          -- ★ 新增：Character 必须一致
        and SolutionCache.MyPos and SolutionCache.TPos then
        local myPos = GetLocalRealPosition()
        local tRoot = tChar:FindFirstChild("HumanoidRootPart")
        local tPos  = tRoot and tRoot.Position or SolutionCache.TPos
        if (myPos - SolutionCache.MyPos).Magnitude < Config.CacheThreshold
            and (tPos - SolutionCache.TPos).Magnitude < Config.CacheThreshold then
            SolutionCache.Age = SolutionCache.Age + 1
            if SolutionCache.Age < SolutionCache.MaxAge then
                Last_Solution = SolutionCache.Solution
                return
            end
        end
    end

    local sol = SolveForTarget(target)
    if sol then
        Last_Solution = sol
        SolutionCache.Solution = sol
        SolutionCache.Target   = target
        SolutionCache.Char     = tChar           -- ★ 新增：记录 Character
        SolutionCache.MyPos    = GetLocalRealPosition()
        local tRoot = tChar:FindFirstChild("HumanoidRootPart")
        SolutionCache.TPos     = tRoot and tRoot.Position or sol.Hit
        SolutionCache.Age      = 0
    else
        ClearSolution()
    end
end)

-- ★ 修复 5：开火循环加入 Character 一致性 + hitPart 归属校验 + Lock 失败清 LockedTarget
RunService.Heartbeat:Connect(function()
    if not Config.Enabled then return end
    local sol = Last_Solution
    if not sol or not sol.Target or not sol.Target.Character then return end

    -- Lock：严格校验，失败即清 LockedTarget
    if Config.TargetMode == "Lock" then
        if not IsLockValid(sol.Target) then
            LockedTarget = nil                    -- ★ 新增
            ClearSolution()
            return
        end
    else
        if not IsTargetAlive(sol.Target) then
            ClearSolution()                        -- ★ 新增：非 Lock 失效也清缓存
            return
        end
    end

    -- ★ 新增：sol.Char 与当前 targetChar 必须一致
    local targetChar = sol.Target.Character
    if not targetChar or not targetChar.Parent then
        ClearSolution()
        return
    end
    if sol.Char and sol.Char ~= targetChar then
        ClearSolution()
        return
    end

    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool or not tool:FindFirstChild("IsGun") then return end

    local waitTime = GetFireInterval(tool)
    if tick() - Last_Shot < waitTime then return end

    local vals  = tool:FindFirstChild("Values")
    local ammo  = vals and vals:FindFirstChild("SERVER_Ammo")
    if not ammo or ammo.Value <= 0 then return end

    -- ★ 新增：hitPart 必须仍属于当前 targetChar
    local hitPart = sol.HitPart
    if not hitPart or not hitPart.Parent
       or not hitPart:IsDescendantOf(targetChar) then
        hitPart = targetChar:FindFirstChild("Head")
               or targetChar:FindFirstChild("Torso")
               or targetChar:FindFirstChild("HumanoidRootPart")
        if hitPart then
            sol.HitPart = hitPart     -- 就地修正
        end
    end
    if not hitPart then
        ClearSolution()                -- ★ 新增：拿不到部件也清缓存
        return
    end

    local key    = "K" .. math.random(1000, 9999)
    local origin = sol.Origin
    local hitPos = sol.Hit
    local dir    = (hitPos - origin).Unit

    GN_S:FireServer(tick(), key, tool, "FDS9I83", origin, { dir }, false)
    ZF_H:FireServer("🧈", tool, key, 1, hitPart, hitPos, dir)

    if tool:FindFirstChild("Hitmarker") then
        tool.Hitmarker:Fire(hitPart)
    end

    if Config.TracerEnabled then
        task.spawn(function()
            local a0 = Instance.new("Attachment", Workspace.Terrain); a0.Position = origin
            local a1 = Instance.new("Attachment", Workspace.Terrain); a1.Position = origin + dir * 1000
            local beam = Instance.new("Beam", Workspace.Terrain)
            beam.Texture = "rbxassetid://446111271"
            beam.Width0, beam.Width1 = 1, 1
            beam.Color = ColorSequence.new(Color3.fromRGB(255,255,255))
            beam.Transparency = NumberSequence.new(0.3)
            beam.Attachment0, beam.Attachment1 = a0, a1
            beam.FaceCamera, beam.LightEmission = true, 1
            Debris:AddItem(a0, 4); Debris:AddItem(a1, 4); Debris:AddItem(beam, 4)
        end)
    end

    if Config.HitLogEnabled then
        local dmg = 17
        local myPos = GetLocalRealPosition()
        local tRoot = targetChar:FindFirstChild("HumanoidRootPart")
        local dist  = tRoot and math.floor((myPos - tRoot.Position).Magnitude) or 0
        local tag = IsBlack(sol.Target.Name)
            and ' <font color="rgb(255,80,80)">[BLACK]</font>'
            or IsWhite(sol.Target.Name)
            and ' <font color="rgb(80,255,120)">[WHITE]</font>' or ''
        local modeTag = string.format(' <font color="rgb(120,200,255)">[%s]</font>', sol.Mode or "Direct")
        AddLog(string.format(
            '<font color="rgb(200,200,200)">Hit </font>'..
            '<font color="rgb(0,255,0)">%s </font>'..
            '<font color="rgb(255,200,0)">%s </font>'..
            '<font color="rgb(200,200,200)">for %s dmg (%sm)</font>%s%s',
            sol.Target.Name, tool.Name, math.floor(dmg*100)/100, dist, tag, modeTag
        ))
    end

    Last_Shot = tick()
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" and self == ZF_H then
        if Config.HitSound ~= "None" and HitSounds[Config.HitSound] then
            task.spawn(function()
                local s = Instance.new("Sound", Camera)
                s.SoundId = HitSounds[Config.HitSound]
                s.Volume = 1
                s:Play()
                Debris:AddItem(s, 1)
            end)
        end
    end
    return oldNamecall(self, ...)
end)

local reloadConns = {}
local function ClearReloadConns()
    for _, c in ipairs(reloadConns) do c:Disconnect() end
    reloadConns = {}
end

local function SetupTool(tool)
    if not (tool and tool:FindFirstChild("IsGun") and Config.AutoReload) then return end
    local vals = tool:FindFirstChild("Values"); if not vals then return end
    local sa  = vals:FindFirstChild("SERVER_Ammo")
    local ssa = vals:FindFirstChild("SERVER_StoredAmmo")
    local function reload()
        if Config.AutoReload and ssa and ssa.Value ~= 0 then
            GN_R:FireServer(tick(), "KLWE89U0", tool)
        end
    end
    if ssa then table.insert(reloadConns, ssa:GetPropertyChangedSignal("Value"):Connect(reload)) end
    if sa  then table.insert(reloadConns, sa:GetPropertyChangedSignal("Value"):Connect(reload))  end
end   

local function AutoReloadSetup()
    ClearReloadConns()
    if not Config.AutoReload then return end
    if LocalPlayer.Character then
        SetupTool(LocalPlayer.Character:FindFirstChildOfClass("Tool"))
        table.insert(reloadConns, LocalPlayer.Character.ChildAdded:Connect(function(o)
            if o:IsA("Tool") then SetupTool(o) end
        end))
    end
    table.insert(reloadConns, LocalPlayer.CharacterAdded:Connect(function(c)
        repeat task.wait() until c and c.Parent
        ClearReloadConns()
        SetupTool(c:FindFirstChildOfClass("Tool"))
        table.insert(reloadConns, c.ChildAdded:Connect(function(o)
            if o:IsA("Tool") then SetupTool(o) end
        end))
    end))
end
AutoReloadSetup()

local HitLogGui, HitLogContainer, ActiveLogs = nil, nil, {}
local function InitHitLog()
    if HitLogGui then return end
    HitLogGui = Instance.new("ScreenGui")
    HitLogGui.Name = "MergedHitLog"
    HitLogGui.ResetOnSpawn = false
    HitLogGui.IgnoreGuiInset = true
    HitLogGui.Enabled = false
    HitLogGui.Parent = CoreGui
    HitLogContainer = Instance.new("Frame")
    HitLogContainer.Name = "LogContainer"
    HitLogContainer.Position = UDim2.new(0, 20, 0, 70)
    HitLogContainer.Size = UDim2.new(0, 500, 0, 800)
    HitLogContainer.BackgroundTransparency = 1
    HitLogContainer.Parent = HitLogGui
end
InitHitLog()

function AddLog(text)
    if not Config.HitLogEnabled or not HitLogContainer then return end
    if #ActiveLogs >= Config.HitLogMax then
        local oldest = table.remove(ActiveLogs, 1)
        if oldest then oldest:Destroy() end
    end
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 400, 0, 13)
    bg.BackgroundColor3 = Color3.new(0,0,0)
    bg.BackgroundTransparency = 0.5
    bg.Parent = HitLogContainer
    bg.Position = UDim2.new(0, 0, 0, #ActiveLogs*20)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(220,220,220)
    lbl.TextSize = 10
    lbl.Font = Enum.Font.Code
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.RichText = true
    lbl.Parent = bg
    table.insert(ActiveLogs, bg)
    task.delay(Config.HitLogLifetime, function()
        local i = table.find(ActiveLogs, bg)
        if i then table.remove(ActiveLogs, i) end
        if bg then bg:Destroy() end
    end)
end

local ESP = (function()
    local ScreenGui, PlayerList, PlayerCount, ESPObjects = nil, {}, 0, {}
    local PixelFont = Font.new("rbxassetid://12187371840", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    local Scale, RefHeight = 0.8, 658
    local MaxSqDist = (Config.ESP_MaxDist * 3.57) ^ 2
    local CurrentCam = Workspace.CurrentCamera
    local LastCamCF = nil
    local CameraChanged = true

    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "MergedESP"
    ScreenGui.Parent = CoreGui
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true

    local function Create(class, props)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        return o
    end

    local function GetClassColor(name)
        if IsBlack(name) then return Config.ESP_BlackColor end
        if IsWhite(name) then return Config.ESP_WhiteColor end
        return Config.ESP_NormalColor
    end

    local function CreateESP(Player)
        if Player == LocalPlayer or ESPObjects[Player] then return end

        local C = {
            Player = Player, Shown = false,
            Character = Player.Character,
            Highlight = nil,
        }

        ESPObjects[Player] = C
        PlayerCount = PlayerCount + 1
        PlayerList[PlayerCount] = C

        local Anchor = Create("Frame", {
            Parent = ScreenGui,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
        })

        local BoxOutline = Create("Frame", {
            Parent = Anchor, BackgroundTransparency = 1,
            Size = UDim2.new(1,0,1,0),
        })
        local OutlineStroke = Instance.new("UIStroke")
        OutlineStroke.Color = Color3.new(0,0,0)
        OutlineStroke.Thickness = Config.ESP_BoxThick + 1
        OutlineStroke.Parent = BoxOutline

        local BoxMain = Create("Frame", {
            Parent = Anchor, BackgroundTransparency = 1,
            Size = UDim2.new(1,0,1,0),
        })
        local MainStroke = Instance.new("UIStroke")
        MainStroke.Color = Config.ESP_NormalColor
        MainStroke.Thickness = Config.ESP_BoxThick
        MainStroke.Parent = BoxMain

        local NameLabel = Create("TextLabel", {
            Parent = Anchor, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 0, -2),
            Size = UDim2.new(0, 200, 0, 14),
            FontFace = PixelFont, TextSize = Config.ESP_FontSize,
            TextColor3 = Config.ESP_NormalColor,
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
        })

        local DistLabel = Create("TextLabel", {
            Parent = Anchor, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 1, 2),
            Size = UDim2.new(0, 200, 0, 14),
            FontFace = PixelFont, TextSize = Config.ESP_FontSize,
            TextColor3 = Config.ESP_NormalColor,
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
        })

        local WeaponLabel = Create("TextLabel", {
            Parent = Anchor, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 1, 16),
            Size = UDim2.new(0, 200, 0, 12),
            FontFace = PixelFont, TextSize = math.max(7, Config.ESP_FontSize - 1),
            TextColor3 = Color3.fromRGB(255, 200, 100),
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
        })

        local HealthBg = Create("Frame", {
            Parent = Anchor,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(0, -4, 0, 0),
            Size = UDim2.new(0, 2, 1, 0),
            BackgroundColor3 = Color3.fromRGB(30,30,30),
            BorderSizePixel = 0,
        })
        local HealthFill = Create("Frame", {
            Parent = HealthBg,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.fromRGB(60,200,60),
            BorderSizePixel = 0,
        })
        local HealthText = Create("TextLabel", {
            Parent = Anchor, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(0, -8, 0.5, 0),
            Size = UDim2.new(0, 50, 0, 12),
            FontFace = PixelFont, TextSize = math.max(7, Config.ESP_FontSize - 1),
            TextColor3 = Color3.fromRGB(255,255,255),
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Right,
        })

        local Highlight = Instance.new("Highlight")
        Highlight.Name = "MergedHighlight"
        Highlight.FillColor = Color3.fromRGB(0, 150, 255)
        Highlight.FillTransparency = Config.ESP_ChamsAlpha
        Highlight.OutlineColor = Color3.fromRGB(0, 255, 255)
        Highlight.OutlineTransparency = 0
        Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        Highlight.Enabled = false
        Highlight.Parent = CoreGui

        C.Anchor = Anchor
        C.BoxOutline = BoxOutline; C.OutlineStroke = OutlineStroke
        C.BoxMain = BoxMain; C.MainStroke = MainStroke
        C.NameLabel = NameLabel
        C.DistLabel = DistLabel
        C.WeaponLabel = WeaponLabel
        C.HealthBg = HealthBg; C.HealthFill = HealthFill; C.HealthText = HealthText
        C.Highlight = Highlight

        Player.CharacterRemoving:Connect(function()
            C.Character = nil
            if C.Highlight then C.Highlight.Adornee = nil; C.Highlight.Enabled = false end
        end)
        Player.CharacterAdded:Connect(function(ch)
            C.Character = ch
            task.wait(0.15)
            if C.Highlight then C.Highlight.Adornee = ch end
        end)
        if Player.Character then Highlight.Adornee = Player.Character end
    end

    local function RemoveESP(Player)
        local C = ESPObjects[Player]
        if not C then return end
        if C.Anchor then C.Anchor:Destroy() end
        if C.Highlight then C.Highlight:Destroy() end
        ESPObjects[Player] = nil
    end

    local function HideESP(C)
        if not C.Shown then return end
        C.Shown = false
        C.Anchor.Visible = false
        if C.Highlight then C.Highlight.Enabled = false end
    end

    local function ShowESP(C)
        if C.Shown then return end
        C.Shown = true
        C.Anchor.Visible = true
        if C.Highlight and Config.ESP_Chams then C.Highlight.Enabled = true end
    end

    for _, p in ipairs(Players:GetPlayers()) do CreateESP(p) end
    Players.PlayerAdded:Connect(CreateESP)
    Players.PlayerRemoving:Connect(RemoveESP)

    local function Update(C)
        local name = C.Player.Name
        local black, white = IsBlack(name), IsWhite(name)
        if Config.ESP_OnlyListed and not (black or white) then
            HideESP(C); return
        end
        if Config.ESP_TeamCheck and IsFriendly(C.Player) and C.Player ~= LocalPlayer then
            HideESP(C); return
        end

        local char = C.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not root or not hum or hum.Health <= 0 then
            HideESP(C); return
        end

        local sp, on = Camera:WorldToViewportPoint(root.Position)
        if not on or sp.Z <= 0 then HideESP(C); return end

        local myPos = GetLocalRealPosition()
        local dist3 = (myPos - root.Position).Magnitude
        if dist3 > Config.ESP_MaxDist then HideESP(C); return end

        ShowESP(C)

        local classColor = GetClassColor(name)

        local height = 3.5 * (root.Size.Y / sp.Z) * 300
        local width  = height * 0.55
        height = math.clamp(height, 20, 500)
        width  = math.clamp(width, 12, 300)
        C.Anchor.Position = UDim2.fromOffset(sp.X - width/2, sp.Y - height/2)
        C.Anchor.Size     = UDim2.fromOffset(width, height)

        C.MainStroke.Color = classColor
        C.MainStroke.Thickness = Config.ESP_BoxThick
        C.BoxMain.Visible = Config.ESP_Box
        C.BoxOutline.Visible = Config.ESP_Box
        C.OutlineStroke.Thickness = Config.ESP_BoxThick + 1

        C.NameLabel.Visible = Config.ESP_Name
        if Config.ESP_Name then
            C.NameLabel.Text = name
            C.NameLabel.TextColor3 = classColor
            C.NameLabel.TextSize = Config.ESP_FontSize
        end

        C.DistLabel.Visible = Config.ESP_Distance
        if Config.ESP_Distance then
            C.DistLabel.Text = string.format("%dM", math.floor(dist3))
            C.DistLabel.TextColor3 = classColor
            C.DistLabel.TextSize = Config.ESP_FontSize
        end

        C.WeaponLabel.Visible = Config.ESP_Weapon
        if Config.ESP_Weapon then
            local tool = char:FindFirstChildOfClass("Tool")
            C.WeaponLabel.Text = tool and tool.Name or ""
        end

        C.HealthBg.Visible = Config.ESP_Health
        C.HealthFill.Visible = Config.ESP_Health
        C.HealthText.Visible = Config.ESP_HealthText and Config.ESP_Health
        if Config.ESP_Health then
            local pct = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
            C.HealthFill.Size = UDim2.new(1, 0, pct, 0)
            local col = Color3.fromRGB(60,200,60):Lerp(Color3.fromRGB(255,60,60), 1 - pct)
            C.HealthFill.BackgroundColor3 = col
            if Config.ESP_HealthText then
                C.HealthText.Text = tostring(math.floor(hum.Health))
                C.HealthText.TextColor3 = col
            end
        end

        if C.Highlight then
            C.Highlight.Enabled = Config.ESP_Chams
            C.Highlight.FillTransparency = Config.ESP_ChamsAlpha
            if black then
                C.Highlight.FillColor = Config.ESP_BlackColor
                C.Highlight.OutlineColor = Config.ESP_BlackColor
            elseif white then
                C.Highlight.FillColor = Config.ESP_WhiteColor
                C.Highlight.OutlineColor = Config.ESP_WhiteColor
            else
                C.Highlight.FillColor = Color3.fromRGB(0, 150, 255)
                C.Highlight.OutlineColor = Color3.fromRGB(0, 255, 255)
            end
        end
    end

    RunService:BindToRenderStep("MergedESPUpdate", Enum.RenderPriority.Camera.Value + 1, function()
        CurrentCam = Workspace.CurrentCamera
        if CurrentCam ~= Camera then Camera = CurrentCam end
        if not Config.ESP_Enabled then
            for _, C in pairs(ESPObjects) do HideESP(C) end
            return
        end
        for _, C in pairs(ESPObjects) do
            pcall(Update, C)
        end
    end)

    return {
        ClearClassCache = function()
            for _, C in pairs(ESPObjects) do
                if C.Highlight then C.Highlight.Enabled = false end
            end
        end
    }
end)()

local function GetPlayerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(names, p.Name) end
    end
    return names
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "kood",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "kood",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = nil,
        FileName = "kood",
    },
    KeySystem = false,
})

--=== Ragebot Tab ===
local MainTab = Window:CreateTab("Ragebot", 4483362458)

MainTab:CreateToggle({
    Name = "Enable Ragebot",
    CurrentValue = false,
    Flag = "RB_Enabled",
    Callback = function(v) Config.Enabled = v end,
})

MainTab:CreateToggle({
    Name = "Auto Reload",
    CurrentValue = true,
    Flag = "RB_AutoReload",
    Callback = function(v) Config.AutoReload = v; AutoReloadSetup() end,
})

MainTab:CreateToggle({
    Name = "Down Check",
    CurrentValue = false,
    Flag = "RB_DownCheck",
    Callback = function(v) Config.DownCheck = v end,
})

MainTab:CreateToggle({
    Name = "Friendly Fire Check",
    CurrentValue = true,
    Flag = "RB_FF",
    Callback = function(v) Config.FriendlyFire = v end,
})

MainTab:CreateToggle({
    Name = "Blacklist Priority",
    CurrentValue = true,
    Flag = "RB_BlackPriority",
    Callback = function(v) Config.BlackPriority = v end,
})

--=== Path Tracing ===
MainTab:CreateSection("Path Tracing")

MainTab:CreateSlider({
    Name = "Origin Radius",
    Range = {1, 30}, Increment = 0.5,
    CurrentValue = 18.5, Flag = "PT_OriginR",
    Callback = function(v) Config.PathOriginR = v end,
})

MainTab:CreateSlider({
    Name = "Target Radius",
    Range = {1, 30}, Increment = 0.5,
    CurrentValue = 23.5, Flag = "PT_TargetR",
    Callback = function(v) Config.PathTargetR = v end,
})

MainTab:CreateSlider({
    Name = "Scan Count",
    Range = {8, 48}, Increment = 1,
    CurrentValue = 24, Flag = "PT_Scans",
    Callback = function(v) Config.PathScans = v end,
})

MainTab:CreateSlider({
    Name = "Scan Rate (Hz)",
    Range = {4, 60}, Increment = 1,
    CurrentValue = 14, Flag = "PT_ScanRate",
    Callback = function(v) Config.PathScanRate = v end,
})

MainTab:CreateSlider({
    Name = "Max Distance",
    Range = {100, 1500}, Increment = 10,
    CurrentValue = 820, Flag = "PT_MaxDist",
    Callback = function(v) Config.PathMaxDist = v end,
})

--=== Scanners Section (Legacy / 保留备用) ===
MainTab:CreateSection("Scanners (Legacy)")

MainTab:CreateToggle({
    Name = "Origin Shift",
    CurrentValue = false, Flag = "SC_OriginShift",
    Callback = function(v) Config.OriginShift = v end,
})
MainTab:CreateSlider({
    Name = "Origin Range", Range = {1, 12}, Increment = 0.1,
    CurrentValue = 6.0, Flag = "SC_OriginRange",
    Callback = function(v) Config.OriginShiftRange = v end,
})
MainTab:CreateSlider({
    Name = "Origin Scans", Range = {8, 48}, Increment = 1,
    CurrentValue = 24, Flag = "SC_OriginScans",
    Callback = function(v) Config.OriginShiftScans = v end,
})

MainTab:CreateToggle({
    Name = "Target Shift",
    CurrentValue = false, Flag = "SC_TargetShift",
    Callback = function(v) Config.TargetShift = v end,
})
MainTab:CreateSlider({
    Name = "Target Range", Range = {1, 12}, Increment = 0.1,
    CurrentValue = 7.5, Flag = "SC_TargetRange",
    Callback = function(v) Config.TargetShiftRange = v end,
})
MainTab:CreateSlider({
    Name = "Target Scans", Range = {8, 48}, Increment = 1,
    CurrentValue = 24, Flag = "SC_TargetScans",
    Callback = function(v) Config.TargetShiftScans = v end,
})

MainTab:CreateToggle({
    Name = "Cross Shift (组合)",
    CurrentValue = false, Flag = "SC_CrossShift",
    Callback = function(v) Config.CrossShift = v end,
})

MainTab:CreateToggle({
    Name = "Wallbang (Legacy)",
    CurrentValue = false, Flag = "SC_Wallbang",
    Callback = function(v) Config.Wallbang = v end,
})
MainTab:CreateSlider({
    Name = "Wallbang Range", Range = {1, 15}, Increment = 0.1,
    CurrentValue = 7.0, Flag = "SC_WallbangRange",
    Callback = function(v) Config.WallbangRange = v end,
})

--=== Targeting ===
MainTab:CreateSection("Targeting")

MainTab:CreateSlider({
    Name = "Cache Threshold", Range = {0.1, 5}, Increment = 0.01,
    CurrentValue = 0.75, Flag = "RB_CacheThreshold",
    Callback = function(v) Config.CacheThreshold = v end,
})

-- ★ 修复 6：切换 Target Mode 时同步清 LockedTarget
MainTab:CreateDropdown({
    Name = "Target Mode",
    Options = {"Near", "Mouse", "Centre", "Lock"},
    CurrentOption = "Near", Flag = "RB_TargetMode",
    Callback = function(v)
        Config.TargetMode = v
        LockedTarget = nil
        ClearSolution()
    end,
})

MainTab:CreateDropdown({
    Name = "Hit Sound",
    Options = {"None", "Skeet", "Neverlose", "Gamesense"},
    CurrentOption = "None", Flag = "RB_HitSound",
    Callback = function(v) Config.HitSound = v end,
})

MainTab:CreateToggle({
    Name = "Tracer", CurrentValue = false, Flag = "RB_Tracer",
    Callback = function(v) Config.TracerEnabled = v end,
})

MainTab:CreateToggle({
    Name = "Hit Log", CurrentValue = false, Flag = "RB_HitLog",
    Callback = function(v)
        Config.HitLogEnabled = v
        if HitLogGui then HitLogGui.Enabled = v end
    end,
})

--=== Lists Tab ===
local ListTab = Window:CreateTab("Lists", 4483362458)
ListTab:CreateSection("Blacklist / Whitelist")

local BlackDropdown, WhiteDropdown

-- ★ 修复 7：黑名单变更时清 LockedTarget
BlackDropdown = ListTab:CreateDropdown({
    Name = "Blacklist",
    Options = GetPlayerNames(),
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "LB_BlackList",
    Callback = function(sel)
        BlackList = {}
        for _, n in ipairs(sel) do
            BlackList[n] = true
            WhiteList[n] = nil
        end
        if WhiteDropdown then WhiteDropdown:Refresh(GetPlayerNames(), true) end
        LockedTarget = nil
        ClearSolution()
        ESP.ClearClassCache()
    end,
})

-- ★ 修复 8：白名单变更时清 LockedTarget
WhiteDropdown = ListTab:CreateDropdown({
    Name = "Whitelist",
    Options = GetPlayerNames(),
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "LB_WhiteList",
    Callback = function(sel)
        WhiteList = {}
        for _, n in ipairs(sel) do
            WhiteList[n] = true
            BlackList[n] = nil
        end
        if BlackDropdown then BlackDropdown:Refresh(GetPlayerNames(), true) end
        LockedTarget = nil
        ClearSolution()
        ESP.ClearClassCache()
    end,
})

ListTab:CreateButton({
    Name = "Refresh Lists",
    Callback = function()
        if BlackDropdown then BlackDropdown:Refresh(GetPlayerNames(), true) end
        if WhiteDropdown then WhiteDropdown:Refresh(GetPlayerNames(), true) end
    end,
})

ListTab:CreateButton({
    Name = "Clear Lists",
    Callback = function()
        BlackList, WhiteList = {}, {}
        if BlackDropdown then BlackDropdown:Refresh(GetPlayerNames(), true) end
        if WhiteDropdown then WhiteDropdown:Refresh(GetPlayerNames(), true) end
        LockedTarget = nil
        ClearSolution()
        ESP.ClearClassCache()
    end,
})

--=== ESP Tab ===
local EspTab = Window:CreateTab("ESP", 4483362458)
EspTab:CreateSection("Master")

EspTab:CreateToggle({
    Name = "Enable ESP", CurrentValue = true, Flag = "ESP_Enabled",
    Callback = function(v) Config.ESP_Enabled = v end,
})
EspTab:CreateToggle({
    Name = "Only Show List Players", CurrentValue = false, Flag = "ESP_OnlyListed",
    Callback = function(v) Config.ESP_OnlyListed = v end,
})
EspTab:CreateToggle({
    Name = "Team Check", CurrentValue = true, Flag = "ESP_TeamCheck",
    Callback = function(v) Config.ESP_TeamCheck = v end,
})
EspTab:CreateSlider({
    Name = "Max Distance", Range = {100, 5000}, Increment = 10,
    CurrentValue = 1500, Flag = "ESP_MaxDist",
    Callback = function(v) Config.ESP_MaxDist = v end,
})

EspTab:CreateSection("Box & Text")
EspTab:CreateToggle({
    Name = "Box", CurrentValue = true, Flag = "ESP_Box",
    Callback = function(v) Config.ESP_Box = v end,
})
EspTab:CreateSlider({
    Name = "Box Thickness", Range = {1, 5}, Increment = 1,
    CurrentValue = 1, Flag = "ESP_BoxThick",
    Callback = function(v) Config.ESP_BoxThick = v end,
})
EspTab:CreateToggle({
    Name = "Name", CurrentValue = true, Flag = "ESP_Name",
    Callback = function(v) Config.ESP_Name = v end,
})
EspTab:CreateToggle({
    Name = "Distance", CurrentValue = true, Flag = "ESP_Distance",
    Callback = function(v) Config.ESP_Distance = v end,
})
EspTab:CreateToggle({
    Name = "Weapon", CurrentValue = true, Flag = "ESP_Weapon",
    Callback = function(v) Config.ESP_Weapon = v end,
})
EspTab:CreateSlider({
    Name = "Font Size", Range = {7, 14}, Increment = 1,
    CurrentValue = 9, Flag = "ESP_FontSize",
    Callback = function(v) Config.ESP_FontSize = v end,
})

EspTab:CreateSection("Health")
EspTab:CreateToggle({
    Name = "Health Bar", CurrentValue = true, Flag = "ESP_Health",
    Callback = function(v) Config.ESP_Health = v end,
})
EspTab:CreateToggle({
    Name = "Health Text", CurrentValue = true, Flag = "ESP_HealthText",
    Callback = function(v) Config.ESP_HealthText = v end,
})

EspTab:CreateSection("Chams")
EspTab:CreateToggle({
    Name = "Chams Highlight", CurrentValue = false, Flag = "ESP_Chams",
    Callback = function(v) Config.ESP_Chams = v end,
})
EspTab:CreateSlider({
    Name = "Chams Alpha", Range = {0, 1}, Increment = 0.05,
    CurrentValue = 0.6, Flag = "ESP_ChamsAlpha",
    Callback = function(v) Config.ESP_ChamsAlpha = v end,
})

EspTab:CreateSection("Colors")
EspTab:CreateColorPicker({
    Name = "Blacklist Color", Color = Config.ESP_BlackColor, Flag = "ESP_BlackColor",
    Callback = function(c) Config.ESP_BlackColor = c; ESP.ClearClassCache() end,
})
EspTab:CreateColorPicker({
    Name = "Whitelist Color", Color = Config.ESP_WhiteColor, Flag = "ESP_WhiteColor",
    Callback = function(c) Config.ESP_WhiteColor = c; ESP.ClearClassCache() end,
})
EspTab:CreateColorPicker({
    Name = "Normal Color", Color = Config.ESP_NormalColor, Flag = "ESP_NormalColor",
    Callback = function(c) Config.ESP_NormalColor = c; ESP.ClearClassCache() end,
})

Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    if BlackDropdown then BlackDropdown:Refresh(GetPlayerNames(), true) end
    if WhiteDropdown then WhiteDropdown:Refresh(GetPlayerNames(), true) end
end)
Players.PlayerRemoving:Connect(function(p)
    BlackList[p.Name] = nil
    WhiteList[p.Name] = nil
    if LockedTarget == p then
        LockedTarget = nil
        ClearSolution()
    end
    task.wait(0.2)
    if BlackDropdown then BlackDropdown:Refresh(GetPlayerNames(), true) end
    if WhiteDropdown then WhiteDropdown:Refresh(GetPlayerNames(), true) end
end)

_G.MergedRagebot = {
    Config = Config,
    BlackList = BlackList,
    WhiteList = WhiteList,
    Scanners = {
        Origin   = OriginScan,
        Target   = TargetScan,
        Cross    = CrossScan,
        Wallbang = WallbangScan,
        Path     = ScanBulletPath,
    },
    FibonacciHemisphere = FibonacciHemisphere,
    Sphere              = Sphere,
    RayCheckTol         = RayCheckTol,
    GetTarget           = GetTarget,
    SolveForTarget      = SolveForTarget,
    GetFireInterval     = GetFireInterval,
}
return _G.MergedRagebot
