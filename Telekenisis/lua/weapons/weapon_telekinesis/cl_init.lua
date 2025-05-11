include("shared.lua")

SWEP.DrawWeaponInfoBox = true
SWEP.BounceWeaponIcon = false

-- Add better textures and effects
SWEP.WepSelectIcon = surface.GetTextureID("vgui/entities/weapon_telekinesis")

function SWEP:Initialize()
    -- Initialize client vars
    self.NextPulseTime = 0
    self.PulseSize = 0
    self.NextGlowTime = 0
end

function SWEP:DrawHUD()
    -- Draw a reticle
    local x, y = ScrW() / 2, ScrH() / 2
    
    -- Dynamic reticle color based on whether something can be grabbed
    local tr = LocalPlayer():GetEyeTrace()
    local canGrab = false
    local color = Color(255, 255, 255, 200)
    
    if IsValid(tr.Entity) and not tr.Entity:IsPlayer() and not tr.Entity:IsNPC() then
        local phys = tr.Entity:GetPhysicsObject()
        if IsValid(phys) then
            canGrab = true
            if phys:GetMass() <= self.MaxWeight then
                color = Color(0, 200, 255, 220) -- Blue for objects we can grab
            else
                color = Color(255, 50, 50, 220) -- Red for too heavy
            end
        end
    end
    
    -- Draw pulse effect when holding attack
    if LocalPlayer():KeyDown(IN_ATTACK) then
        if CurTime() > self.NextPulseTime then
            self.NextPulseTime = CurTime() + 0.02
            self.PulseSize = self.PulseSize + 1
            if self.PulseSize > 20 then
                self.PulseSize = 0
            end
        end
        
        -- Draw expanding circle
        surface.SetDrawColor(color.r, color.g, color.b, math.Clamp(200 - self.PulseSize * 10, 0, 200))
        surface.DrawCircle(x, y, 5 + self.PulseSize, color)
    else
        self.PulseSize = 0
    end
    
    -- Draw the circle
    surface.SetDrawColor(color)
    surface.DrawCircle(x, y, 4, color)
    
    -- Draw the crosshair lines with dynamic size
    local lineLength = canGrab and 8 or 5
    local innerGap = canGrab and 3 or 2
    
    surface.DrawLine(x - lineLength - innerGap, y, x - innerGap, y)
    surface.DrawLine(x + innerGap, y, x + lineLength + innerGap, y)
    surface.DrawLine(x, y - lineLength - innerGap, x, y - innerGap)
    surface.DrawLine(x, y + innerGap, x, y + lineLength + innerGap)
    
    -- If we have a valid entity, show some information
    if canGrab then
        -- Display entity information
        local phys = tr.Entity:GetPhysicsObject()
        if IsValid(phys) then
            local text = "Object: " .. tr.Entity:GetClass()
            local weight = phys:GetMass()
            
            -- Create a background for text
            local bgColor = Color(0, 0, 0, 150)
            local textColor = Color(255, 255, 255, 255)
            
            -- Draw the background
            surface.SetDrawColor(bgColor)
            surface.DrawRect(x + 20, y - 45, 200, 60)
            
            -- Draw text
            draw.SimpleText(text, "Trebuchet24", x + 30, y - 40, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Weight: " .. math.Round(weight) .. " kg", "Trebuchet24", x + 30, y - 20, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            
            -- Color code based on whether it's liftable
            local statusColor = Color(0, 255, 0, 255) -- Green for liftable
            local statusText = "LIFTABLE"
            if weight > self.MaxWeight then
                statusColor = Color(255, 50, 50, 255) -- Red for too heavy
                statusText = "TOO HEAVY"
            end
            
            draw.SimpleText(statusText, "Trebuchet24", x + 30, y, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            
            -- Draw distance bar
            local distance = math.Round(tr.StartPos:Distance(tr.HitPos))
            local maxDist = self.MaxDistance
            local distPercent = math.Clamp(distance / maxDist, 0, 1)
            
            -- Draw distance background
            surface.SetDrawColor(0, 0, 0, 180)
            surface.DrawRect(x - 100, y + 20, 200, 10)
            
            -- Draw distance indicator
            local distColor = Color(0, 255 * (1 - distPercent), 255 * distPercent, 255)
            surface.SetDrawColor(distColor)
            surface.DrawRect(x - 100, y + 20, 200 * distPercent, 10)
            
            -- Draw distance text
            draw.SimpleText(distance .. " units", "Default", x, y + 35, distColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
end

function SWEP:Think()
    -- Add visual effects while using telekinesis
    local ply = LocalPlayer()
    
    if ply:KeyDown(IN_ATTACK) then
        -- Enhanced beam effects
        local tr = ply:GetEyeTrace()
        if IsValid(tr.Entity) and not tr.Entity:IsPlayer() and not tr.Entity:IsNPC() then
            -- Add glow effect to viewmodel hands
            if CurTime() > self.NextGlowTime then
                self.NextGlowTime = CurTime() + 0.1
                
                local dlight = DynamicLight(ply:EntIndex())
                if dlight then
                    dlight.pos = ply:GetShootPos()
                    dlight.r = 0
                    dlight.g = 150
                    dlight.b = 255
                    dlight.brightness = 1
                    dlight.decay = 1000
                    dlight.size = 100
                    dlight.dietime = CurTime() + 0.2
                end
            end
        end
    end
end

function SWEP:CalcViewModelView(vm, oldPos, oldAng, pos, ang)
    -- Make the viewmodel float when using telekinesis
    if LocalPlayer():KeyDown(IN_ATTACK) then
        local bobSpeed = 3
        local bobAmount = 0.5
        
        local bobX = math.sin(CurTime() * bobSpeed) * bobAmount
        local bobY = math.cos(CurTime() * bobSpeed * 0.5) * bobAmount
        local bobZ = math.sin(CurTime() * bobSpeed * 0.7) * bobAmount
        
        pos = pos + Vector(bobX, bobY, bobZ)
        ang:RotateAroundAxis(ang:Right(), bobX * 2)
        ang:RotateAroundAxis(ang:Up(), bobY * 2)
    end
    
    return pos, ang
end

function SWEP:GetViewModelPosition(pos, ang)
    pos = pos + ang:Forward() * 5
    ang:RotateAroundAxis(ang:Right(), 10)
    return pos, ang
end

function SWEP:DrawWorldModel()
    local ply = self:GetOwner()
    
    if IsValid(ply) then
        local boneIndex = ply:LookupBone("ValveBiped.Bip01_R_Hand")
        if boneIndex then
            local pos, ang = ply:GetBonePosition(boneIndex)
            
            pos = pos + ang:Forward() * 4 + ang:Right() * 2 + ang:Up() * -2
            
            ang:RotateAroundAxis(ang:Right(), 180)
            ang:RotateAroundAxis(ang:Forward(), 20)
            ang:RotateAroundAxis(ang:Up(), 0)
            
            self:SetRenderOrigin(pos)
            self:SetRenderAngles(ang)
            
            -- Draw world model with custom effects
            if ply:KeyDown(IN_ATTACK) then
                -- Add a glowing effect
                local dlight = DynamicLight(self:EntIndex())
                if dlight then
                    dlight.pos = pos
                    dlight.r = 0
                    dlight.g = 150
                    dlight.b = 255
                    dlight.brightness = 1
                    dlight.decay = 1000
                    dlight.size = 100
                    dlight.dietime = CurTime() + 0.2
                end
            end
            
            self:DrawModel()
        end
    else
        self:DrawModel()
    end
end
