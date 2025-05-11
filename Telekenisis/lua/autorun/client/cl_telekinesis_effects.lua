-- Client-side effects for the telekinesis weapon

-- Create a custom light effect when the telekinesis is active
hook.Add("RenderScreenspaceEffects", "TelekinesisScreenEffects", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local weapon = ply:GetActiveWeapon()
    if IsValid(weapon) and weapon:GetClass() == "weapon_telekinesis" then
        -- Enhanced visual effects when using telekinesis
        if ply:KeyDown(IN_ATTACK) then
            -- Add a subtle bloom effect
            local effects = {
                ["$pp_colour_addr"] = 0,
                ["$pp_colour_addg"] = 0.01,
                ["$pp_colour_addb"] = 0.05,
                ["$pp_colour_brightness"] = 0.02,
                ["$pp_colour_contrast"] = 1.05,
                ["$pp_colour_colour"] = 1.2,
                ["$pp_colour_mulr"] = 0,
                ["$pp_colour_mulg"] = 0,
                ["$pp_colour_mulb"] = 0.2
            }
            
            DrawColorModify(effects)
            DrawBloom(0.3, 0.7, 9, 9, 2, 1, 0.1, 0.5, 1)
            
            -- Add motion blur for dramatic effect
            DrawMotionBlur(0.1, 0.4, 0.01)
        end
    end
end)

-- Add particle effects between the player and grabbed object
hook.Add("Think", "TelekinesisParticleEffects", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local weapon = ply:GetActiveWeapon()
    if IsValid(weapon) and weapon:GetClass() == "weapon_telekinesis" and ply:KeyDown(IN_ATTACK) then
        local trace = ply:GetEyeTrace()
        if IsValid(trace.Entity) and not trace.Entity:IsPlayer() and not trace.Entity:IsNPC() then
            -- Enhanced particle effects
            if math.random(1, 8) == 1 then
                local effectdata = EffectData()
                effectdata:SetOrigin(trace.Entity:GetPos())
                effectdata:SetStart(ply:GetShootPos())
                effectdata:SetAttachment(1)
                util.Effect("TeslaZap", effectdata)
                
                -- Add energy rings
                if math.random(1, 3) == 1 then
                    effectdata:SetScale(2)
                    effectdata:SetMagnitude(1)
                    effectdata:SetRadius(2)
                    util.Effect("cball_explode", effectdata)
                end
                
                -- Add subtle energy pulses along the beam
                local dir = (trace.Entity:GetPos() - ply:GetShootPos()):GetNormalized()
                local dist = trace.Entity:GetPos():Distance(ply:GetShootPos())
                local steps = math.min(10, math.floor(dist / 150))
                
                for i = 1, steps do
                    if math.random(1, 3) == 1 then
                        local pos = ply:GetShootPos() + (dir * (dist * (i/steps)))
                        local pulse = EffectData()
                        pulse:SetOrigin(pos)
                        pulse:SetScale(0.5)
                        util.Effect("energysplash", pulse)
                    end
                end
            end
            
            -- Add a glowing outline to the object
            halo.Add({trace.Entity}, Color(0, 150, 255, 255), 2, 2, 2, true, true)
        end
    end
end)

-- Add sound effects for telekinesis
hook.Add("Think", "TelekinesisSoundEffects", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local weapon = ply:GetActiveWeapon()
    if IsValid(weapon) and weapon:GetClass() == "weapon_telekinesis" then
        -- Create environment sound
        if ply:KeyDown(IN_ATTACK) and (not weapon.NextHumSound or weapon.NextHumSound < CurTime()) then
            weapon.NextHumSound = CurTime() + 4
            ply:EmitSound("ambient/energy/force_field_loop1.wav", 40, math.random(90, 110), 0.3)
            
            -- Random energy crackle
            if math.random(1, 5) == 1 then
                ply:EmitSound("ambient/energy/zap" .. math.random(1, 9) .. ".wav", 50, math.random(90, 120), 0.4)
            end
        end
    end
end)
