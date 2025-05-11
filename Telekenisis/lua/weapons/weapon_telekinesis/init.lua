AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function SWEP:Initialize()
    self:SetHoldType("magic")
    self.GrabbedEntity = nil
    self.GrabDistance = 150
    self.LastThinkTime = 0
    self.RotationAxis = Vector(math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(-1, 1)):GetNormalized()
    self.RotationSpeed = math.Rand(0.5, 2)
    self.PushMode = false
    self.PullMode = false
    
    -- Initialize sound cooldown
    self.NextGrabSound = 0
    self.NextReleaseSound = 0
    self.NextThrowSound = 0
    self.NextPushSound = 0
    
    -- Initialize effect timers
    self.NextParticleEffect = 0
    self.NextShockwave = 0
end

function SWEP:PrimaryAttack()
    if SERVER then
        if IsValid(self.GrabbedEntity) then
            -- We're already grabbing something, manipulate it
            self:ManipulateObject()
        else
            -- Try to grab a new object
            self:GrabObject()
        end
    end
end

function SWEP:SecondaryAttack()
    if SERVER then
        -- If we're holding an object and the throw key is pressed
        if IsValid(self.GrabbedEntity) then
            self:ThrowObject()
        else
            -- Wave effect when not holding anything
            self:PushNearbyObjects()
        end
    end
end

function SWEP:Reload()
    if SERVER then
        if self:GetOwner():KeyPressed(IN_RELOAD) then
            self.PushMode = not self.PushMode
            self.PullMode = false
            if self.PushMode then
                self:GetOwner():ChatPrint("Push Mode Activated")
                self:EmitSound("weapons/physcannon/physcannon_charge.wav")
            end
        elseif self:GetOwner():KeyDown(IN_RELOAD) then
            if IsValid(self.GrabbedEntity) then
                if self.PushMode then
                    -- Increase distance
                    self.GrabDistance = math.min(self.GrabDistance + 10, self.MaxDistance)
                elseif self.PullMode then
                    -- Decrease distance
                    self.GrabDistance = math.max(self.GrabDistance - 10, 50)
                end
            end
        elseif self:GetOwner():KeyReleased(IN_RELOAD) and not self.PushMode then
            self.PullMode = not self.PullMode
            if self.PullMode then
                self:GetOwner():ChatPrint("Pull Mode Activated")
                self:EmitSound("weapons/physcannon/physcannon_charge.wav")
            end
        end
    end
end

function SWEP:GrabObject()
    local owner = self:GetOwner()
    local tr = util.TraceLine({
        start = owner:GetShootPos(),
        endpos = owner:GetShootPos() + owner:GetAimVector() * self.MaxDistance,
        filter = owner,
        mask = MASK_SOLID
    })
    
    if not tr.Hit or not IsValid(tr.Entity) then return end
    
    local phys = tr.Entity:GetPhysicsObject()
    if not IsValid(phys) then return end
    
    -- Don't grab players or NPCs
    if tr.Entity:IsPlayer() or tr.Entity:IsNPC() then return end
    
    -- Don't grab items that are too heavy
    if phys:GetMass() > self.MaxWeight then
        owner:ChatPrint("This object is too heavy to move with telekinesis!")
        if CurTime() > self.NextPushSound then
            self:EmitSound("physics/metal/metal_solid_strain" .. math.random(1, 5) .. ".wav")
            self.NextPushSound = CurTime() + 1
        end
        return
    end
    
    self.GrabbedEntity = tr.Entity
    self.GrabDistance = tr.Fraction * self.MaxDistance
    
    -- Apply visual effect
    local effect = EffectData()
    effect:SetOrigin(tr.HitPos)
    effect:SetEntity(tr.Entity)
    util.Effect("manhack_sparks", effect)
    
    -- Add shockwave effect
    local shock = EffectData()
    shock:SetOrigin(tr.HitPos)
    shock:SetScale(10)
    shock:SetMagnitude(5)
    shock:SetRadius(5)
    util.Effect("ThumperDust", shock)
    
    -- Play grab sound
    if CurTime() > self.NextGrabSound then
        self:EmitSound("physics/metal/metal_barrel_impact_hard" .. math.random(1, 7) .. ".wav", 75, math.random(90, 110))
        self:EmitSound("ambient/machines/thumper_startup1.wav", 75, math.random(110, 140))
        self.NextGrabSound = CurTime() + 1
    end
    
    -- Keep track of the entity we're grabbing
    self.GrabbedEntity.OldCollisionGroup = self.GrabbedEntity:GetCollisionGroup()
    self.GrabbedEntity:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
    
    -- Store the time we grabbed it for throw force calculation
    self.GrabTime = CurTime()
    
    -- Create a light for the object
    if not self.GrabbedEntity.TKLight and SERVER then
        self.GrabbedEntity.TKLight = ents.Create("light_dynamic")
        self.GrabbedEntity.TKLight:SetPos(self.GrabbedEntity:GetPos())
        self.GrabbedEntity.TKLight:SetParent(self.GrabbedEntity)
        self.GrabbedEntity.TKLight:SetKeyValue("brightness", "3")
        self.GrabbedEntity.TKLight:SetKeyValue("distance", "150")
        self.GrabbedEntity.TKLight:SetKeyValue("_light", "0 150 255 255")
        self.GrabbedEntity.TKLight:Spawn()
        self.GrabbedEntity.TKLight:Activate()
    end
    
    -- Create trail effect
    if not self.GrabbedEntity.TKTrail and SERVER then
        util.SpriteTrail(self.GrabbedEntity, 0, Color(0, 150, 255, 100), false, 15, 1, 1, 0.1, "trails/laser.vmt")
    end
    
    -- Apply slow rotation
    self.RotationAxis = Vector(math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(-1, 1)):GetNormalized()
    self.RotationSpeed = math.Rand(0.5, 2)
    
    -- Make the object wake up
    phys:Wake()
    
    -- Network to client that we've grabbed an entity
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
end

function SWEP:ManipulateObject()
    if not IsValid(self.GrabbedEntity) then return end
    
    local phys = self.GrabbedEntity:GetPhysicsObject()
    if not IsValid(phys) then return end
    
    local owner = self:GetOwner()
    local target_pos = owner:GetShootPos() + owner:GetAimVector() * self.GrabDistance
    
    -- Calculate the direction and force
    local vecToTarget = target_pos - self.GrabbedEntity:GetPos()
    local distance = vecToTarget:Length()
    
    -- Adjust the force based on distance
    local force_mul = math.Clamp(distance / 100, 0.1, 10)
    
    -- Apply the force
    phys:Wake()
    phys:AddVelocity(vecToTarget:GetNormalized() * self.Force * force_mul - phys:GetVelocity() * 0.8)
    
    -- Apply subtle rotation
    if CurTime() - self.LastThinkTime > 0.1 then
        local ang = Angle(0, 0, 0)
        ang:RotateAroundAxis(self.RotationAxis, self.RotationSpeed)
        phys:AddAngleVelocity(ang:Forward() * self.RotationSpeed - phys:GetAngleVelocity() * 0.3)
        self.LastThinkTime = CurTime()
    end
    
    -- Create a visual effect between player and object
    if CurTime() > self.NextParticleEffect and SERVER then
        self.NextParticleEffect = CurTime() + 0.2
        
        local effectdata = EffectData()
        effectdata:SetOrigin(self.GrabbedEntity:GetPos())
        effectdata:SetStart(owner:GetShootPos())
        effectdata:SetAttachment(1)
        effectdata:SetEntity(self.GrabbedEntity)
        util.Effect("TeslaHitboxes", effectdata)
        
        -- Random energy effects
        if math.random(1, 10) == 1 and CurTime() > self.NextShockwave then
            self.NextShockwave = CurTime() + 1
            local shockData = EffectData()
            shockData:SetOrigin(self.GrabbedEntity:GetPos())
            shockData:SetScale(1)
            shockData:SetMagnitude(2)
            shockData:SetRadius(2)
            util.Effect("cball_bounce", shockData)
            
            -- Play random energy sound
            self:EmitSound("ambient/energy/zap" .. math.random(1, 9) .. ".wav", 60, math.random(90, 120))
        end
    end
end

function SWEP:ReleaseObject()
    if not IsValid(self.GrabbedEntity) then return end
    
    -- Restore original collision group
    if self.GrabbedEntity.OldCollisionGroup then
        self.GrabbedEntity:SetCollisionGroup(self.GrabbedEntity.OldCollisionGroup)
        self.GrabbedEntity.OldCollisionGroup = nil
    end
    
    -- Remove the light
    if IsValid(self.GrabbedEntity.TKLight) then
        self.GrabbedEntity.TKLight:Remove()
        self.GrabbedEntity.TKLight = nil
    end
    
    -- Play release sound
    if CurTime() > self.NextReleaseSound then
        self:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 75, math.random(90, 110))
        self.NextReleaseSound = CurTime() + 1
    end
    
    -- Add some visual effects on release
    local effect = EffectData()
    effect:SetOrigin(self.GrabbedEntity:GetPos())
    effect:SetEntity(self.GrabbedEntity)
    util.Effect("cball_bounce", effect)
    
    self.GrabbedEntity = nil
    
    -- Reset modes
    self.PushMode = false
    self.PullMode = false
    
    -- Network to client
    self:SendWeaponAnim(ACT_VM_SECONDARYATTACK)
end

function SWEP:ThrowObject()
    if not IsValid(self.GrabbedEntity) then return end
    
    local phys = self.GrabbedEntity:GetPhysicsObject()
    if not IsValid(phys) then return end
    
    -- Calculate how long we've been holding the object
    local holdTime = CurTime() - self.GrabTime
    local holdForce = math.Clamp(holdTime, 0.5, 3)
    
    -- Apply a strong force in the direction the player is looking
    phys:ApplyForceCenter(self:GetOwner():GetAimVector() * self.ThrowForceMultiplier * holdForce * phys:GetMass())
    
    -- Play throw sound
    if CurTime() > self.NextThrowSound then
        self:EmitSound("weapons/slam/throw.wav", 75, math.random(90, 110))
        self:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 5) .. ".wav", 75, math.random(70, 90))
        self.NextThrowSound = CurTime() + 1
    end
    
    -- Add dramatic effects
    local effect = EffectData()
    effect:SetOrigin(self.GrabbedEntity:GetPos())
    effect:SetScale(3)
    effect:SetMagnitude(10)
    effect:SetRadius(5)
    util.Effect("ThumperDust", effect)
    
    -- Create shockwave
    local shock = EffectData()
    shock:SetOrigin(self.GrabbedEntity:GetPos())
    shock:SetScale(10)
    shock:SetMagnitude(8)
    shock:SetRadius(8)
    util.Effect("cball_explode", shock)
    
    -- Release after throwing
    self:ReleaseObject()
end

function SWEP:PushNearbyObjects()
    local owner = self:GetOwner()
    
    -- Find all entities in a cone in front of the player
    local entities = ents.FindInCone(owner:GetShootPos(), owner:GetAimVector(), self.MaxDistance/2, math.cos(math.rad(30)))
    
    local pushedAny = false
    
    for _, ent in pairs(entities) do
        if IsValid(ent) and ent:GetPhysicsObject():IsValid() and not ent:IsPlayer() and not ent:IsNPC() then
            local phys = ent:GetPhysicsObject()
            
            -- Make sure it's not too heavy
            if phys:GetMass() <= self.MaxWeight * 1.5 then
                -- Calculate push direction and strength
                local dir = (ent:GetPos() - owner:GetShootPos()):GetNormalized()
                local dist = ent:GetPos():Distance(owner:GetShootPos())
                local forceMult = math.Clamp(1 - dist/(self.MaxDistance/2), 0.1, 1)
                
                -- Apply push force
                phys:ApplyForceCenter(dir * self.PushForce * forceMult * phys:GetMass())
                pushedAny = true
                
                -- Add effect
                local effect = EffectData()
                effect:SetOrigin(ent:GetPos())
                effect:SetScale(2)
                effect:SetMagnitude(1)
                effect:SetRadius(2)
                util.Effect("cball_bounce", effect)
            end
        end
    end
    
    -- Play sound if we pushed something
    if pushedAny and CurTime() > self.NextPushSound then
        self:EmitSound("weapons/physcannon/energy_bounce" .. math.random(1, 2) .. ".wav", 75, math.random(90, 110))
        self:EmitSound("ambient/machines/thumper_hit.wav", 75, math.random(90, 110))
        self.NextPushSound = CurTime() + 1
        
        -- Add dramatic effect in front of player
        local effect = EffectData()
        effect:SetOrigin(owner:GetShootPos() + owner:GetAimVector() * 100)
        effect:SetScale(10)
        effect:SetMagnitude(5)
        effect:SetNormal(owner:GetAimVector())
        util.Effect("ThumperDust", effect)
        
        -- Create shockwave
        local shock = EffectData()
        shock:SetOrigin(owner:GetShootPos() + owner:GetAimVector() * 100)
        shock:SetScale(15)
        shock:SetMagnitude(10)
        shock:SetRadius(10)
        shock:SetNormal(owner:GetAimVector())
        util.Effect("cball_explode", shock)
        
        -- Screen shake
        util.ScreenShake(owner:GetPos(), 5, 5, 0.5, 500)
    end
end

function SWEP:Holster()
    self:ReleaseObject()
    return true
end

function SWEP:OnRemove()
    self:ReleaseObject()
end

function SWEP:OnDrop()
    self:ReleaseObject()
end

function SWEP:Think()
    if SERVER then
        if not self:GetOwner():KeyDown(IN_ATTACK) then
            if IsValid(self.GrabbedEntity) then
                if not self:GetOwner():KeyDown(IN_RELOAD) then
                    self:ReleaseObject()
                end
            end
        end
    end
end
