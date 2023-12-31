--修改的是一个本地函数，这里没法注入了，所以重写了一份放在这里
local Perishable = Class(function(self, inst)
	self.inst = inst
	self.perishfn = nil
	self.perishtime = nil

	self.frozenfiremult = false

	self.targettime = nil
	self.perishremainingtime = nil
	self.updatetask = nil
	self.dt = nil
	self.onperishreplacement = nil
end)



local function Update(inst, dt)
	if inst.components.perishable then
		local seasonmanager = GetSeasonManager()
		local modifier = 1
		local owner = inst.components.inventoryitem and inst.components.inventoryitem.owner or nil
		if owner then
			if owner:HasTag("fridge") then
				if inst:HasTag("frozen") and not owner:HasTag("nocool") and not owner:HasTag("lowcool") then
					modifier = TUNING.PERISH_COLD_FROZEN_MULT
				else
					modifier = TUNING.PERISH_FRIDGE_MULT
				end
			elseif owner:HasTag("spoiler") and owner:HasTag("poison") then
				modifier = TUNING.PERISH_POISON_MULT
			elseif owner:HasTag("spoiler") then
				modifier = TUNING.PERISH_GROUND_MULT
			end
		else
			modifier = TUNING.PERISH_GROUND_MULT
		end

		--改动了：添加一个特别的冰冻逻辑
		if owner then
			if owner:HasTag("superfridge") then
				modifier = 0
			end
		end
		
		-- Cool off hot foods over time (faster if in a fridge)
		if inst.components.edible and inst.components.edible.temperaturedelta and inst.components.edible.temperaturedelta > 0 then
			if owner and owner:HasTag("fridge") then
				if not owner:HasTag("nocool") then
					inst.components.edible.temperatureduration = inst.components.edible.temperatureduration - 1
				end
			elseif seasonmanager and seasonmanager:GetCurrentTemperature() < TUNING.OVERHEAT_TEMP - 5 then
				inst.components.edible.temperatureduration = inst.components.edible.temperatureduration - .25
			end
			if inst.components.edible.temperatureduration < 0 then inst.components.edible.temperatureduration = 0 end
		end

		local mm = GetWorld().components.moisturemanager
		if mm:IsEntityWet(inst) then
			modifier = modifier * TUNING.PERISH_WET_MULT
		end

		if seasonmanager and seasonmanager:GetCurrentTemperature() < 0 then
			if inst:HasTag("frozen") and not inst.components.perishable.frozenfiremult then
				modifier = TUNING.PERISH_COLD_FROZEN_MULT
			else
				modifier = modifier * TUNING.PERISH_WINTER_MULT
			end
		end

		if inst.components.perishable.frozenfiremult then
			modifier = modifier * TUNING.PERISH_FROZEN_FIRE_MULT
		end

		if seasonmanager and seasonmanager:GetCurrentTemperature() > TUNING.OVERHEAT_TEMP then
			modifier = modifier * TUNING.PERISH_SUMMER_MULT
		end

		local aporkalypse = GetAporkalypse()
		if aporkalypse and aporkalypse:IsActive() then
			modifier = modifier * TUNING.PERISH_APORKALYPSE_MULT
		end

		modifier = modifier * TUNING.PERISH_GLOBAL_MULT
		
		if owner then
			if owner:HasTag("superrotten") then
				modifier = modifier * 20
			end
		end

		local old_val = inst.components.perishable.perishremainingtime
		local delta = dt or (10 + math.random() * FRAMES * 8)
		inst.components.perishable.perishremainingtime = inst.components.perishable.perishremainingtime - delta *
		modifier
		if math.floor(old_val * 100) ~= math.floor(inst.components.perishable.perishremainingtime * 100) then
			inst:PushEvent("perishchange", { percent = inst.components.perishable:GetPercent() })
		end

		--trigger the next callback
		if inst.components.perishable.perishremainingtime <= 0 then
			inst.components.perishable:Perish()
		end
	end
end


function Perishable:IsFresh()
	return self:GetPercent() >= .5
end

function Perishable:IsStale()
	return self:GetPercent() < .5 and self:GetPercent() > .2
end

function Perishable:IsSpoiled()
	return self:GetPercent() <= .2
end

function Perishable:GetAdjective()
	if self.inst.components.edible then
		if self:IsStale() then
			if self.inst:HasTag("frozen") then
				return STRINGS.UI.HUD.STALE_FROZEN
			else
				return STRINGS.UI.HUD.STALE
			end
		elseif self:IsSpoiled() then
			if self.inst:HasTag("frozen") then
				return STRINGS.UI.HUD.STALE_FROZEN
			else
				return STRINGS.UI.HUD.SPOILED
			end
		end
	elseif self.inst.components.eater then
		if self:IsStale() then
			return STRINGS.UI.HUD.HUNGRY
		elseif self:IsSpoiled() then
			return STRINGS.UI.HUD.STARVING
		end
	end
end

function Perishable:Dilute(number, timeleft)
	if self.inst.components.stackable then
		self.perishremainingtime = (self.inst.components.stackable.stacksize * self.perishremainingtime + number * timeleft) /
		(number + self.inst.components.stackable.stacksize)
		self.inst:PushEvent("perishchange", { percent = self:GetPercent() })
	end
end

function Perishable:SetPerishTime(time)
	self.perishtime = time
	self.perishremainingtime = time
end

function Perishable:SetOnPerishFn(fn)
	self.perishfn = fn
end

function Perishable:GetPercent()
	if self.perishremainingtime and self.perishtime and self.perishtime > 0 then
		return math.min(1, self.perishremainingtime / self.perishtime)
	else
		return 0
	end
end

function Perishable:SetPercent(percent)
	if percent < 0 then percent = 0 end
	if percent > 1 then percent = 1 end
	self.perishremainingtime = percent * self.perishtime
	self.inst:PushEvent("perishchange", { percent = self.inst.components.perishable:GetPercent() })
end

function Perishable:ReducePercent(amount)
	local cur = self:GetPercent()
	self:SetPercent(cur - amount)
end

function Perishable:GetDebugString()
	if self.perishremainingtime and self.perishremainingtime > 0 then
		return string.format("%s %2.2fs", self.updatetask and "Perishing" or "Paused", self.perishremainingtime)
	else
		return "perished"
	end
end

function Perishable:LongUpdate(dt)
	if self.updatetask then
		Update(self.inst, dt or 0)
	end
end

function Perishable:StartPerishing()
	if self.updatetask then
		self.updatetask:Cancel()
		self.updatetask = nil
	end

	local dt = 10 +
	math.random() * FRAMES * 8             --math.max( 4, math.min( self.perishtime / 100, 10)) + ( math.random()* FRAMES * 8)

	if dt > 0 then
		self.updatetask = self.inst:DoPeriodicTask(dt, Update, math.random() * 2, dt)
	else
		Update(self.inst, 0)
	end
end

function Perishable:Perish()
	--print ("perish")

	if self.updatetask then
		self.updatetask:Cancel()
		self.updatetask = nil
	end

	self.inst:PushEvent("perished")

	if self.perishfn then
		self.perishfn(self.inst)
	end

	if self.onperishreplacement then
		local goop = SpawnPrefab(self.onperishreplacement)
		if goop then
			local owner = self.inst.components.inventoryitem and self.inst.components.inventoryitem.owner or nil
			local pt = Vector3(self.inst.Transform:GetWorldPosition())
			local holder = owner and (owner.components.inventory or owner.components.container)
			local slot = holder and holder:GetItemSlot(self.inst)
			local floating = false
			if self.inst.components.floatable then
				floating = self.inst.components.floatable.onwater or false
			end
			local shelf = nil

			if self.inst.onshelf then
				shelf = self.inst.onshelf
			end

			local fromInterior = self.inst.interior

			self.inst:Remove()

			if holder then
				holder:GiveItem(goop, slot)
			else
				goop.Transform:SetPosition(pt:Get())

				if fromInterior then
					GetInteriorSpawner():AddPrefabToInterior(goop, fromInterior)
				end

				if floating then
					if goop.components.floatable then
						goop.components.floatable:OnHitWater(true)
					else
						local fx = SpawnPrefab("splash_water_sink")
						fx.Transform:SetPosition(pt:Get())
						goop:Remove()
					end
				end
			end

			if shelf then
				shelf.components.shelfer:AcceptGift(nil, goop)
			end

			if goop.components.stackable and self.inst.components.stackable then
				goop.components.stackable:SetStackSize(self.inst.components.stackable.stacksize)
			end
		end
	end
end

function Perishable:StopPerishing()
	if self.updatetask then
		self.updatetask:Cancel()
		self.updatetask = nil
	end
end

function Perishable:OnSave()
	local data = {}

	data.paused = self.updatetask == nil
	data.time = self.perishremainingtime

	return data
end

function Perishable:OnLoad(data)
	if data and data.time then
		self.perishremainingtime = data.time
		if not data.paused then
			self:StartPerishing()
		end
	end
end

return Perishable
