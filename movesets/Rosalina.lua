require "anims/rosalina"

local E_MODEL_TWIRL_EFFECT = smlua_model_util_get_id("spin_attack_geo")

-- Rosalina actions
_G.ACT_JUMP_TWIRL       = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING)
_G.ACT_TWIRL_POUND      = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ATTACKING | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)
_G.ACT_TWIRL_POUND_LAND = allocate_mario_action(ACT_GROUP_STATIONARY | ACT_FLAG_STATIONARY | ACT_FLAG_ATTACKING)

-- Rosalina sounds
local ROSALINA_SOUND_SPIN        = audio_sample_load("z_sfx_rosalina_spinattack.ogg")
local ROSALINA_SOUND_HOMING_SPIN = audio_sample_load("z_sfx_rosalina_homing_spinattack.ogg")

---@param o Object
local function bhv_spin_attack_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE -- Allows you to change the position and angle
end

---@param o Object
local function bhv_spin_attack_loop(o)
    -- Retrieves the Mario state corresponding to its global index
    local m = gMarioStates[network_local_index_from_global(o.globalPlayerIndex)]
    if m == nil or m.marioObj == nil then
        obj_mark_for_deletion(o)
        return
    end

    o.parentObj = m.marioObj                     -- Sets the Mario object as its parent
    cur_obj_set_pos_relative_to_parent(0, 20, 0) -- Makes it move to its parent's position

    o.oFaceAngleYaw = o.oFaceAngleYaw + 0x2000   -- Rotates it

    if m.action ~= ACT_JUMP_TWIRL or o.oTimer > 15 then -- Deletes itself once the action changes
        obj_mark_for_deletion(o)
    end
end

local id_bhvTwirlEffect = hook_behavior(nil, OBJ_LIST_GENACTOR, true, bhv_spin_attack_init, bhv_spin_attack_loop,
    "bhvRosalinaTwirlEffect")

-- Spinable actions, these are actions you can spin out of that don't normally allow a kick/dive
local extraSpinActs = T{
    ACT_LONG_JUMP,
    ACT_BACKFLIP,
}

-- Spin overridable actions, these are overriden instantly
local spinOverrides = T{
    ACT_PUNCHING,
    ACT_MOVE_PUNCHING,
    ACT_JUMP_KICK,
    ACT_DIVE
}

---@param m MarioState
function act_jump_twirl(m)
    local e = gCharacterStates[m.playerIndex].rosalina

    if m.actionTimer >= 15 then
        return set_mario_action(m, ACT_FREEFALL, 0) -- End the action
    end

    if m.input & INPUT_Z_PRESSED ~= 0 and m.vel.y > 0 then
        return set_mario_action(m, ACT_TWIRL_POUND, 0)
    end

    if m.actionTimer == 0 then
        m.marioObj.header.gfx.animInfo.animID = -1
        play_character_sound(m, CHAR_SOUND_HELLO)                    -- Plays the character sound
        audio_sample_play(ROSALINA_SOUND_SPIN, m.pos, 1)             -- Plays the spin sound sample
        m.particleFlags = m.particleFlags | ACTIVE_PARTICLE_SPARKLES -- Spawns sparkle particles

        if e.canSpin then
            m.vel.y = 30 -- Initial upward velocity
            e.canSpin = false

            -- Spawn the spin effect
            if m.playerIndex == 0 then
                spawn_sync_object(id_bhvTwirlEffect, E_MODEL_TWIRL_EFFECT, m.pos.x, m.pos.y, m.pos.z, function(o)
                    o.globalPlayerIndex = m.marioObj.globalPlayerIndex
                end)
            end
        else
            m.vel.y = math.max(m.vel.y, 0)
        end
        m.marioObj.hitboxRadius = 100 -- Damage hitbox
    else
        m.marioObj.hitboxRadius = 37 -- Reset the hitbox after initial hit
    end

    common_air_action_step(m, ACT_FREEFALL_LAND, CHAR_ANIM_BEND_KNESS_RIDING_SHELL, AIR_STEP_NONE)

    m.marioBodyState.handState = MARIO_HAND_PEACE_SIGN -- Hand State

    -- Increments the action timer
    m.actionTimer = m.actionTimer + 1
end

local function rosalina_is_obj_targetable(obj)
    return (obj_is_exclamation_box(obj) or obj_is_bully(obj) or obj_is_attackable(obj)) and obj_is_valid_for_interaction(obj)
end

local rosalinaHomingLists = {
    OBJ_LIST_DEFAULT,
    OBJ_LIST_LEVEL,
    OBJ_LIST_SURFACE,
    OBJ_LIST_PUSHABLE,
    OBJ_LIST_GENACTOR,
    OBJ_LIST_DESTRUCTIVE,
}

--- @param m MarioState
--- @param distmax number
--- @return Object
--- Finds the closest target to MarioState `m` within the `distmax` units
local function rosalina_find_homing_target(m, distmax)
    local target
    local distmin = distmax
    local pos = gVec3fZero()
    vec3f_copy(pos, m.pos)
    for _, objList in pairs(rosalinaHomingLists) do
        local obj = obj_get_first(objList)
        while obj do
            if rosalina_is_obj_targetable(obj) then
                local distToObj = math.sqrt((pos.x - obj.oPosX)^2 + (pos.y - obj.oPosY)^2 + (pos.z - obj.oPosZ)^2) - (m.marioObj.hitboxRadius + obj.hitboxRadius)
                if distToObj < distmin then
                    distmin = distToObj
                    target = obj
                end
            end
            obj = obj_get_next(obj)
        end
    end
    return target
end

---@param m MarioState
function act_twirl_pound(m)
    if m.actionState == 0 then
        m.vel.y = -100 -- Initial downward velocity
        mario_set_forward_vel(m, 0)

        if m.actionTimer == 0 then
            set_mario_animation(m, CHAR_ANIM_START_GROUND_POUND)
            audio_sample_play(ROSALINA_SOUND_HOMING_SPIN, m.pos, 1)
            m.particleFlags = m.particleFlags | ACTIVE_PARTICLE_SPARKLES
        end

        m.marioBodyState.handState = MARIO_HAND_PEACE_SIGN

        m.actionTimer = m.actionTimer + 1
        if m.actionTimer >= (m.marioObj.header.gfx.animInfo.curAnim.loopEnd + 4) then
            play_character_sound(m, CHAR_SOUND_GROUND_POUND_WAH)
            m.marioObj.hitboxRadius = 60
            m.actionState = 1
        end
    else
        local o = rosalina_find_homing_target(m, 700)
        local dist = dist_between_objects(m.marioObj, o)
        local yaw, pitch

        set_mario_animation(m, CHAR_ANIM_TRIPLE_JUMP_LAND)
        set_anim_to_frame(m, 14)

        m.marioBodyState.handState = MARIO_HAND_OPEN

        local stepResult = perform_air_step(m, 0)

        m.vel.y = m.vel.y * 1.15 -- faster fall

        if o ~= nil and dist < 1000 then
            yaw = obj_angle_to_object(m.marioObj, o)
            if o.collisionData then
                pitch = sonic_pitch_to_object(m, o) + degrees_to_sm64(5)
            else
                pitch = sonic_pitch_to_object(m, o) - degrees_to_sm64(3)
            end

            m.forwardVel = math.clamp(80, m.vel.y + 20, 150)

            m.vel.x = math.abs(m.forwardVel) * sins(yaw) * coss(pitch)
            m.vel.z = math.abs(m.forwardVel) * coss(yaw) * coss(pitch)
        end

        if stepResult == AIR_STEP_LANDED then
            if should_get_stuck_in_ground(m) ~= 0 then
                queue_rumble_data_mario(m, 5, 80)
                play_character_sound(m, CHAR_SOUND_OOOF2)
                m.particleFlags = m.particleFlags | PARTICLE_MIST_CIRCLE
                set_mario_action(m, ACT_BUTT_STUCK_IN_GROUND, 0)
            else
                play_mario_heavy_landing_sound(m, SOUND_ACTION_TERRAIN_HEAVY_LANDING)
                if check_fall_damage(m, ACT_HARD_BACKWARD_GROUND_KB) == 0 then
                    m.particleFlags = m.particleFlags | PARTICLE_MIST_CIRCLE | PARTICLE_HORIZONTAL_STAR
                    set_mario_action(m, ACT_TWIRL_POUND_LAND, 0)
                end
            end
            set_camera_shake_from_hit(SHAKE_GROUND_POUND)
        elseif stepResult == AIR_STEP_HIT_WALL then
            mario_set_forward_vel(m, -16)
            if m.vel.y > 0 then m.vel.y = 0 end

            m.particleFlags = m.particleFlags | PARTICLE_VERTICAL_STAR
            set_mario_action(m, ACT_BACKWARD_AIR_KB, 0)
        end
    end
end

---@param m MarioState
function act_twirl_pound_land(m)
    m.actionState = 1

    if m.input & INPUT_UNKNOWN_10 ~= 0 then
        return drop_and_set_mario_action(m, ACT_SHOCKWAVE_BOUNCE, 0);
    end

    if m.input & INPUT_OFF_FLOOR ~= 0 then
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    if m.input & INPUT_ABOVE_SLIDE ~= 0 then
        return set_mario_action(m, ACT_BUTT_SLIDE, 0)
    end

    landing_step(m, CHAR_ANIM_TRIPLE_JUMP_LAND, ACT_TRIPLE_JUMP_LAND_STOP)
end

---@param m MarioState
---@param o Object
---@param intType InteractionType
function rosalina_allow_interact(m, o, intType)
    local e = gCharacterStates[m.playerIndex].rosalina
    if m.action == ACT_JUMP_TWIRL and intType == INTERACT_GRABBABLE and o.oInteractionSubtype & INT_SUBTYPE_NOT_GRABBABLE == 0 then
        local angleTo = mario_obj_angle_to_object(m, o)
        if (o.oInteractionSubtype & INT_SUBTYPE_GRABS_MARIO ~= 0 or obj_has_behavior_id(o, id_bhvBowser) ~= 0) then -- heavy grab objects
            if m.pos.y - m.floorHeight < 100 and abs_angle_diff(m.faceAngle.y, angleTo) < 0x4000 then
                m.action = ACT_MOVE_PUNCHING
                m.actionArg = 1
            end
        elseif not e.orbitObjActive then -- light grab objects
            m.usedObj = o
            e.orbitObjActive = true
            e.orbitObjDist = 160 - m.actionTimer * 2
            e.orbitObjAngle = angleTo

            return false
        end
    end
end

--[[function rosalina_on_interact(m, o, intType, intValue)
    if m.playerIndex ~= 0 then return end

    local e = gCharacterStates[m.playerIndex].rosalina
    e.extraHealth = true
    e.health = 6

    m.hurtCounter = 0
    m.healCounter = 0
end]]--

local function update_rosalina_health(m, e)
    if m.playerIndex ~= 0 then return end

    if m.hurtCounter > 0 then
        m.hurtCounter = 0
        e.health = e.health - 1
        if e.extraHealth and e.health < 4 then
            e.extraHealth = false
        end
    end

    if m.healCounter > 0 then
        m.healCounter = 0
        e.health = e.health + 1
    end

    local maxHealth = e.extraHealth and 6 or 3
    if e.health >= maxHealth then
        e.health = maxHealth
        m.health = 0x880
    elseif e.health == 1 then
        m.health = 0x200
    else
        m.health = e.health > 0 and 0x700 or 0xFF
    end
end

---@param m MarioState
function rosalina_update(m)
    local e = gCharacterStates[m.playerIndex].rosalina

    if m.controller.buttonPressed & B_BUTTON ~= 0 and extraSpinActs[m.action] then
        return set_mario_action(m, ACT_JUMP_TWIRL, 0)
    end

    --if m.action & ACT_FLAG_AIR == 0 and m.playerIndex == 0 then
    --    e.canSpin = true
    --end

    if m.action ~= ACT_JUMP_TWIRL and m.action ~= ACT_TWIRL_POUND and m.marioObj.hitboxRadius ~= 37 then
        m.marioObj.hitboxRadius = 37
    end

    -- make her floatier
    if m.vel.y < 0 and m.action & ACT_FLAG_AIR ~= 0 and m.action ~= ACT_SHOT_FROM_CANNON then
        m.vel.y = m.vel.y + 0.9
    end

    update_rosalina_health(m, e)

    if e.orbitObjActive then
        local o = m.usedObj

        if not o or o.activeFlags == ACTIVE_FLAG_DEACTIVATED then
            e.orbitObjActive = false
            o.oIntangibleTimer = 0

            if m.playerIndex == 0 then m.usedObj = nil end
            return
        end

        e.orbitObjDist = e.orbitObjDist - 6
        if e.orbitObjDist >= 90 then
            e.orbitObjAngle = e.orbitObjAngle + 0x1800
        else
            e.orbitObjAngle = approach_s16_asymptotic(e.orbitObjAngle, m.faceAngle.y, 4)
        end

        o.oPosX = m.pos.x + sins(e.orbitObjAngle) * e.orbitObjDist
        o.oPosZ = m.pos.z + coss(e.orbitObjAngle) * e.orbitObjDist
        o.oPosY = approach_f32_asymptotic(o.oPosY, m.pos.y + 50, 0.25)

        obj_set_vel(o, 0, 0, 0)
        o.oForwardVel = 0
        o.oIntangibleTimer = -1

        if m.playerIndex == 0 and e.orbitObjDist <= 80 then
            e.orbitObjActive = false
            o.oIntangibleTimer = 0

            if m.action & (ACT_FLAG_INVULNERABLE | ACT_FLAG_INTANGIBLE) ~= 0 or m.action & ACT_GROUP_MASK >= ACT_GROUP_SUBMERGED then
                m.usedObj = nil
            else
                o.oIntangibleTimer = 0
                m.interactObj = o
                m.usedObj = o
                if o.oSyncID ~= 0 then network_send_object(o, true) end

                if m.action & ACT_FLAG_AIR == 0 then
                    set_mario_action(m, ACT_HOLD_IDLE, 0)
                    mario_grab_used_object(m)
                else
                    set_mario_action(m, ACT_HOLD_FREEFALL, 0)
                    mario_grab_used_object(m)
                end
            end
        end
    end
end

---@param m MarioState
function rosalina_before_action(m, action)
    if not action then return end

    local e = gCharacterStates[m.playerIndex].rosalina

    if spinOverrides[action] and m.controller.buttonDown & (Z_TRIG | A_BUTTON) == 0 and m.action ~= ACT_STEEP_JUMP then
        return ACT_JUMP_TWIRL
    end

    if action & ACT_FLAG_AIR == 0 and not e.canSpin then
        play_sound_with_freq_scale(SOUND_GENERAL_COIN_SPURT_EU, m.marioObj.header.gfx.cameraToObject, 1.6)
        if m.playerIndex == 0 then
            spawn_sync_object(id_bhvSparkle, E_MODEL_SPARKLES_ANIMATION, m.pos.x, m.pos.y + 200, m.pos.z,
                function(o) obj_scale(o, 0.75) end)
        end
        e.canSpin = true
    end
end

function rosalina_before_phys_step(m)
    local hScale = 1.0

    -- slower ground movement
    if (m.action & ACT_FLAG_MOVING) ~= 0 then
        hScale = hScale * 0.95
    end

    m.vel.x = m.vel.x * hScale
    m.vel.z = m.vel.z * hScale
end

------------------
-- Rosalina HUD --
------------------

local rosalinaVanillaMeter = load_meter("rosalina")
rosalinaVanillaMeter.pie = load_textures("char_select_custom_meter_pie", 1, 8)

local rosalinaCustomMeter = load_meter("rosalina")
rosalinaCustomMeter.pie = load_textures("char-select-ec-rosalina-meter-pie-", 1, 7)

function rosalina_health_meter(localIndex, health, prevX, prevY, prevScaleW, prevScaleH, x, y, scaleW, scaleH)
    local m = gMarioStates[localIndex]
    local p = gPlayerSyncTable[localIndex]
    local prevScaleW = prevScaleW/64
    local prevScaleH = prevScaleH/64
    local scaleW = scaleW/64
    local scaleH = scaleH/64

    local tex = rosalinaVanillaMeter.label.left
    djui_hud_render_texture_interpolated(tex, prevX, prevY, prevScaleW, prevScaleH, x, y, scaleW, scaleH)
    tex = rosalinaVanillaMeter.label.right
    djui_hud_render_texture_interpolated(tex, prevX + 31*prevScaleW, prevY, prevScaleW, prevScaleH, x + 31*scaleW, y, scaleW, scaleH)

    if gCSPlayers[m.playerIndex].movesetToggle then
        local djuiFont = djui_hud_get_font()
        local djuiColor = djui_hud_get_color()
        djui_hud_set_font(FONT_RECOLOR_HUD)

        health = gCharacterStates[m.playerIndex].rosalina.health

        tex = rosalinaCustomMeter.pie[health + 1] ~= nil and rosalinaCustomMeter.pie[health + 1] or rosalinaVanillaMeter.pie[health + 1]
        djui_hud_render_texture_interpolated(tex, prevX + 15*prevScaleW, prevY + 16*scaleH, prevScaleW, prevScaleH, x + 15*scaleW, y + 16*scaleH, scaleW, scaleH)

        djui_hud_set_color(255 * djuiColor.r/255, 255 * djuiColor.g/255, 0, djuiColor.a)
        local healthText = tostring(health)
        local hx = (31 - djui_hud_measure_text(healthText)*0.5)*prevScaleW
        local hy = 21*prevScaleH
        if health > 3 then
            hx = hx - 2
            hy = hy - 2
        end
        djui_hud_print_text_interpolated(healthText, prevX + hx, prevY + hy, prevScaleH*0.75, x + hx, y + hy, prevScaleH*0.75)

        -- Clean up after we're done
        djui_hud_set_font(djuiFont)
        djui_hud_set_color(djuiColor.r, djuiColor.g, djuiColor.b, djuiColor.a)
    else
        health = health >> 8
        if health > 0 then
            tex = rosalinaVanillaMeter.pie[health]
            djui_hud_render_texture_interpolated(tex, prevX + 15*prevScaleW, prevY + 16*scaleH, prevScaleW, prevScaleH, x + 15*scaleW, y + 16*scaleH, scaleW, scaleH)
        end
    end
end

hook_mario_action(ACT_JUMP_TWIRL, act_jump_twirl, INT_KICK)
hook_mario_action(ACT_TWIRL_POUND, act_twirl_pound, INT_GROUND_POUND)
hook_mario_action(ACT_TWIRL_POUND_LAND, act_twirl_pound_land, INT_GROUND_POUND_OR_TWIRL)

return {
    { HOOK_MARIO_UPDATE, rosalina_update },
 -- { HOOK_ON_PVP_ATTACK, rosalina_on_pvp_attack },
    { HOOK_ALLOW_INTERACT, rosalina_allow_interact },
 -- { HOOK_ON_INTERACT, rosalina_on_interact },
    { HOOK_BEFORE_SET_MARIO_ACTION, rosalina_before_action },
    { HOOK_BEFORE_PHYS_STEP, rosalina_before_phys_step },
    meter = rosalina_health_meter
}