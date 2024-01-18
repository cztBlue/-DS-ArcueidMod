local function createprefabs(customprefabs)
    local prefabs =
    {
        "nightmarefuel",
        "shadowheart",
        "armor_sanity",
        "nightsword",
    }

    for i, v in ipairs(customprefabs) do
        if not table.contains(prefabs, v) then
            table.insert(prefabs, v)
        end
    end
    return prefabs
end

local function createassets(name)
    return
    {
        Asset("ANIM", "anim/".."creature_"..name..".zip"),
        Asset("ANIM", "anim/".."creature_"..name.."_upg_build.zip"),
    }
end

-- local bishopfxassets =
-- {
--     Asset("ANIM", "anim/shadow_bishop_fx.zip"),
-- }

local PHYS_RADIUS =
{
    ["shadow_rook"] = 1.6,
    ["shadow_knight"] = .25,
    ["shadow_bishop"]  = .3,
}

--------------------------------------------------------------------------

local function lootsetfn(lootdropper)
    local loot = {}

    if lootdropper.inst.level >= 2 then
        for i = 1, math.random(2, 3) do
            table.insert(loot, "nightmarefuel")
        end

        if lootdropper.inst.level >= 3 then
            table.insert(loot, "shadowheart")
            table.insert(loot, "nightmarefuel")
            --TODO: replace with shadow equipment drops
            table.insert(loot, "armor_sanity")
            table.insert(loot, "nightsword")
            if IsSpecialEventActive(SPECIAL_EVENTS.WINTERS_FEAST) then
                table.insert(loot, GetRandomBasicWinterOrnament())
            end
        end
    end

    lootdropper:SetLoot(loot)
end

SetSharedLootTable("shadow_chesspiece",
{
    { "nightmarefuel",  1.0 },
    { "nightmarefuel",  0.5 },
})

--------------------------------------------------------------------------

local function retargetfn(inst)
    --retarget nearby players if current target is fleeing or not a player
    local target = inst.components.combat.target
    if target ~= nil then
        local dist = TUNING[string.upper(inst.prefab)].RETARGET_DIST
        if target:HasTag("player") and inst:IsNear(target, dist) or not inst:IsNearPlayer(dist, true) then
            return
        end
        target = nil
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local players = FindPlayersInRange(x, y, z, TUNING.SHADOWCREATURE_TARGET_DIST, true)
    local rangesq = math.huge
    for i, v in ipairs(players) do
        local distsq = v:GetDistanceSqToPoint(x, y, z)
        if distsq < rangesq and inst.components.combat:CanTarget(v) then
            rangesq = distsq
            target = v
        end
    end
    return target, true
end

local function ShareTargetFn(dude)
    return dude:HasTag("shadowchesspiece") and not dude.components.health:IsDead()
end

local function OnAttacked(inst, data)
    inst.components.combat:SetTarget(data.attacker)
    inst.components.combat:ShareTarget(data.attacker, 30, ShareTargetFn, 1)
end

--------------------------------------------------------------------------

local function PushMusic(inst)
    if ThePlayer ~= nil and ThePlayer:IsNear(inst, 30) then
        ThePlayer:PushEvent("triggeredevent", { name = "shadowchess" })
    end
end

local function OnMusicDirty(inst)
    --Dedicated server does not need to trigger music
    if not TheNet:IsDedicated() then
        if inst._music:value() then
            if inst._musictask == nil then
                inst._musictask = inst:DoPeriodicTask(1, PushMusic, 0)
            end
        elseif inst._musictask ~= nil then
            inst._musictask:Cancel()
            inst._musictask = nil
        end
    end
end

local function StartMusic(inst)
    if not (inst._music:value() or inst.components.health:IsDead()) then
        inst._music:set(true)
        OnMusicDirty(inst)
    end
end

local function StopMusic(inst)
    if inst._music:value() then
        inst._music:set(false)
        OnMusicDirty(inst)
    end
end

--------------------------------------------------------------------------

local function OnLevelUp(inst, data)
    if inst.level < 3 and
        data ~= nil and
        data.source ~= nil and
        data.source.prefab ~= inst.prefab and
        -- only level up if the source's level is equal or greater then this inst's level
        -- (test #inst.levelupsource because there may be some queued)
        data.source.level > #inst.levelupsource and
        not table.contains(inst.levelupsource, data.source.prefab) then
        table.insert(inst.levelupsource, data.source.prefab)
    end
end

local function WantsToLevelUp(inst)
    return inst.level < #inst.levelupsource + 1
end

local function nodmglevelingup(inst, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
    return WantsToLevelUp(inst) and amount <= 0 and not ignore_absorb
end

--------------------------------------------------------------------------

local MAX_LEVEL = 3

local function IsMaxLevel(inst)
    return inst.level == MAX_LEVEL
end

local function commonlevelup(inst, overridelevel)
    if inst.components.health:IsDead() then
        return
    end
    local level = math.min(overridelevel or (inst.level + 1), MAX_LEVEL)
    if level ~= inst.level then
        inst.level = level

        local tunings = TUNING[string.upper(inst.prefab)]
        local scale = tunings.LEVELUP_SCALE[level]

        local x, y, z = inst.Transform:GetWorldPosition()
        inst.Transform:SetScale(scale, scale, scale)
        inst.Physics:SetCapsule(PHYS_RADIUS[inst.prefab] * scale, 1)
        inst.Physics:Teleport(x, y, z)

        inst.AnimState:SetMultColour(1, 1, 1, 0.5 + (0.12*(level-1)))

        inst.components.health:SetMaxHealth(tunings.HEALTH[level])

        if level > 1 then
            inst:AddTag("epic")
            inst:AddTag("noepicmusic")
            StartMusic(inst)
            inst.sounds.levelup = "dontstarve/sanity/transform/three"
        else
            inst:RemoveTag("epic")
            inst:RemoveTag("noepicmusic")
            StopMusic(inst)
            inst.sounds.levelup = "dontstarve/sanity/transform/two"
        end

        return level, scale
    end
end

local function knightlevelup(inst, overridelevel)
    local level, scale = commonlevelup(inst, overridelevel)
    if level ~= nil then
        inst.components.locomotor.walkspeed = TUNING.SHADOW_KNIGHT.SPEED[level] / scale

        inst.components.combat:SetDefaultDamage(TUNING.SHADOW_KNIGHT.DAMAGE[level])
        inst.components.combat:SetRange(TUNING.SHADOW_KNIGHT.ATTACK_RANGE * scale, TUNING.SHADOW_KNIGHT.ATTACK_RANGE_LONG * scale)
        inst.components.combat:SetAttackPeriod(TUNING.SHADOW_KNIGHT.ATTACK_PERIOD[level])

        if level > 1 then
            local suffix = tostring(level - 1)
            inst.AnimState:OverrideSymbol("arm",       "creature_shadow_knight_upg_build", "arm"..suffix)
            inst.AnimState:OverrideSymbol("ear",       "creature_shadow_knight_upg_build", "ear"..suffix)
            inst.AnimState:OverrideSymbol("face",      "creature_shadow_knight_upg_build", "face"..suffix)
            inst.AnimState:OverrideSymbol("head",      "creature_shadow_knight_upg_build", "head"..suffix)
            inst.AnimState:OverrideSymbol("leg_low",   "creature_shadow_knight_upg_build", "leg_low"..suffix)
            inst.AnimState:OverrideSymbol("neck",      "creature_shadow_knight_upg_build", "neck"..suffix)
            inst.AnimState:OverrideSymbol("spring",    "creature_shadow_knight_upg_build", "spring"..suffix)
        else
            inst.AnimState:ClearAllOverrideSymbols()
        end

        inst.sounds.attack = "dontstarve/sanity/knight/attack_"..tostring(level)
    end
end

--------------------------------------------------------------------------

local function onsave(inst, data)
    data.level = inst.level > 1 and inst.level or nil
    data.levelupsource = #inst.levelupsource > 0 and inst.levelupsource or nil
end

local function onpreload(inst, data)
    while #inst.levelupsource > 0 do
        table.remove(inst.levelupsource)
    end
    if data ~= nil then
        if data.levelupsource ~= nil then
            for i, v in ipairs(data.levelupsource) do
                table.insert(inst.levelupsource, v)
            end
        end
        if data.level ~= nil then
            inst:LevelUp(data.level)
        end
    end
end

--------------------------------------------------------------------------

local function OnEntityWake(inst)
    if inst._despawntask ~= nil then
        inst._despawntask:Cancel()
        inst._despawntask = nil
    end
end

local function OnDespawn(inst)
    inst._despawntask = nil
    if inst:IsAsleep() and not inst.components.health:IsDead() then
        inst:Remove()
    end
end

local function OnEntitySleep(inst)
    if inst._despawntask ~= nil then
        inst._despawntask:Cancel()
    end
    inst._despawntask = inst:DoTaskInTime(TUNING.SHADOW_CHESSPIECE_DESPAWN_TIME, OnDespawn)
end

--------------------------------------------------------------------------

local function commonfn(name, sixfaced)
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()

    MakeCharacterPhysics(inst, 10, PHYS_RADIUS[name])
    RemovePhysicsColliders(inst)
    inst.Physics:SetCollisionGroup(COLLISION.SANITY)
    --inst.Physics:CollidesWith(COLLISION.SANITY)
    inst.Physics:CollidesWith(COLLISION.WORLD)

    if sixfaced then
        inst.Transform:SetSixFaced()
    else
        inst.Transform:SetFourFaced()
    end

    inst:AddTag("monster")
    inst:AddTag("hostile")
    inst:AddTag("notraptrigger")
    inst:AddTag("shadowchesspiece")
    inst:AddTag("shadow_aligned")

    inst.AnimState:SetBank(name)
    inst.AnimState:SetBuild(name)
    inst.AnimState:PlayAnimation("idle_loop")
    inst.AnimState:SetMultColour(1, 1, 1, .5)
    inst.AnimState:SetFinalOffset(1)
	inst.AnimState:UsePointFiltering(true)

    -- inst._music = net_bool(inst.GUID, "shadowchesspiece._music", "musicdirty")

    -- inst.entity:SetPristine()

    -- if not TheWorld.ismastersim then
    --     inst:ListenForEvent("musicdirty", OnMusicDirty)

    --     return inst
    -- end

    inst:AddComponent("locomotor") -- locomotor must be constructed before the stategraph
	inst.components.locomotor:SetTriggersCreep(false)
    inst.components.locomotor.pathcaps = { ignorecreep = true }

    inst:AddComponent("health")
    inst.components.health.nofadeout = true

    inst:AddComponent("combat")
    inst.components.combat:SetRetargetFunction(3, retargetfn)
    inst.components.health.redirect = nodmglevelingup

    -- inst:AddComponent("explosiveresist")

    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetChanceLootTable("shadow_chesspiece")
    inst.components.lootdropper:SetLootSetupFn(lootsetfn)

    inst:AddComponent("sanityaura")
    inst.components.sanityaura.aura = -TUNING.SANITYAURA_LARGE

    -- inst:AddComponent("epicscare")
    -- inst.components.epicscare:SetRange(TUNING.SHADOW_CHESSPIECE_EPICSCARE_RANGE)

    -- inst:AddComponent("drownable")

    inst:ListenForEvent("attacked", OnAttacked)
    inst:ListenForEvent("death", StopMusic)
    inst:ListenForEvent("levelup", OnLevelUp)

    inst.OnSave = onsave
    inst.OnPreLoad = onpreload

    inst.WantsToLevelUp = WantsToLevelUp

    inst.OnEntityWake = OnEntityWake
    inst.OnEntitySleep = OnEntitySleep

    inst.level = 1
    inst.levelupsource = {}
    inst.sounds =
    {
        --common sounds
        death = "dontstarve/sanity/death_pop",
        levelup = "dontstarve/sanity/transform/two",
    }
    return inst
end



local function knightfn()
    local inst = commonfn("shadow_knight")

    inst.components.locomotor.walkspeed = TUNING.SHADOW_KNIGHT.SPEED[1]
    inst.components.health:SetMaxHealth(TUNING.SHADOW_KNIGHT.HEALTH[1])
    inst.components.combat:SetDefaultDamage(TUNING.SHADOW_KNIGHT.DAMAGE[1])
    inst.components.combat:SetAttackPeriod(TUNING.SHADOW_KNIGHT.ATTACK_PERIOD[1])
    inst.components.combat:SetRange(TUNING.SHADOW_KNIGHT.ATTACK_RANGE, TUNING.SHADOW_KNIGHT.ATTACK_RANGE_LONG)

    inst:SetStateGraph("SGshadow_knight_")
    inst:SetBrain("shadow_knightbrain_")

    --声音先不做
    -- inst.sounds.attack = "dontstarve/sanity/knight/attack_1"
    -- inst.sounds.attack_grunt = "dontstarve/sanity/knight/attack_grunt"
    -- inst.sounds.die = "dontstarve/sanity/knight/die"
    -- inst.sounds.idle = "dontstarve/sanity/knight/idle"
    -- inst.sounds.taunt = "dontstarve/sanity/knight/taunt"
    -- inst.sounds.disappear = "dontstarve/sanity/knight/dissappear"
    -- inst.sounds.hit = "dontstarve/sanity/knight/hit_response"

    inst.LevelUp = knightlevelup

    return inst
end



return Prefab("shadow_knight", knightfn, createassets("shadow_knight"), createprefabs({ --[["shadow_crest"]] }))
    