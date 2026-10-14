"""
Swaps character sprite poses when art exists for the selected character.
Idle keeps the battle default frame; attack/damaged only swap when those assets exist.
"""
module CharacterPoseControllerModule
    using JulGame

    export attach!, detach!, set_pose!, pulse_pose!, update!, ensure_player!, current_pose

    const PLAYER_ENTITY_ID = "95b3f5d9-a580-4a15-b745-9ecf1fc76620"
    const HOLD_ATTACK = 0.48
    const HOLD_DAMAGED = 0.55
    const HOLD_VICTORY = 1.4
    const HOLD_DEFEAT = 2.0

    # Only list poses that have art on disk. Missing keys are ignored.
    # Asset names are bare (e.g. "magician", "magicianattack"); the registry resolves the latest version.
    function get_pose_art(character_key::AbstractString, pose::Symbol)::Union{String, Nothing}
        globals = JulGame.UserGlobals["Module"]
        parts = split(character_key, "_")
        length(parts) < 2 && return nothing
        pose_str = pose === :idle ? "" : lowercase(String(pose))
        name = "$(lowercase(String(parts[2])))$(pose_str)"
        globals.AssetManager.asset_exists("character", name) || return nothing
        return globals.get_asset_path("character", name)
    end

    mutable struct PoseState
        entity::Any
        character_key::String
        pose::Symbol
        hold_remaining::Float64
        last_health::Int
        observer_registered::Bool
        active::Bool
    end

    const STATE = PoseState(nothing, "", :idle, 0.0, -1, false, false)

    function _art(character_key::String, pose::Symbol)
        return get_pose_art(character_key, pose)
    end

    function _has_pose(character_key::String, pose::Symbol)::Bool
        return _art(character_key, pose) !== nothing
    end

    function _apply_image!(path::String)
        spr = STATE.entity === nothing ? nothing : STATE.entity.sprite
        (spr === nothing || spr == C_NULL) && return
        spr.imagePath = path
        try
            parentmodule(@__MODULE__).SpriteShadowEffectModule.refresh!(STATE.entity)
        catch
        end
    end

    function set_pose!(pose::Symbol; hold::Float64 = 0.0)
        STATE.active || return false
        path = _art(STATE.character_key, pose)
        path === nothing && return false
        STATE.pose = pose
        STATE.hold_remaining = hold
        _apply_image!(path)
        return true
    end

    function pulse_pose!(pose::Symbol; hold::Float64 = -1.0)
        default_hold = pose === :attack ? HOLD_ATTACK :
                       pose === :damaged ? HOLD_DAMAGED :
                       pose === :victory ? HOLD_VICTORY :
                       pose === :defeat ? HOLD_DEFEAT : 0.4
        h = hold < 0 ? default_hold : hold
        return set_pose!(pose; hold = h)
    end

    function current_pose()::Symbol
        return STATE.pose
    end

    function _on_event(event, data)
        STATE.active || return
        try
            if event == :damage_dealt
                pulse_pose!(:attack)
            elseif event == :victory
                set_pose!(:victory; hold = HOLD_VICTORY)
            elseif event == :defeat
                set_pose!(:defeat; hold = HOLD_DEFEAT)
            end
        catch e
            @debug "CharacterPoseController event: $e"
        end
    end

    function _ensure_observer!()
        STATE.observer_registered && return
        try
            globals = JulGame.UserGlobals["Module"]
            globals.ObserverModule.add_observer((event, data) -> _on_event(event, data))
            STATE.observer_registered = true
        catch e
            @debug "CharacterPoseController observer: $e"
        end
    end

    function attach!(entity, character_key::AbstractString; combatant = nothing)::Bool
        entity === nothing && return false
        key = uppercase(String(character_key))
        isempty(key) && (key = "CHARACTER_MAGICIAN")
        STATE.entity = entity
        STATE.character_key = key
        STATE.hold_remaining = 0.0
        STATE.active = true
        if combatant !== nothing
            try
                STATE.last_health = Int(combatant.health)
            catch
                STATE.last_health = -1
            end
        else
            STATE.last_health = -1
        end
        _ensure_observer!()
        set_pose!(:idle)
        return _has_pose(key, :idle)
    end

    function detach!()
        STATE.active = false
        STATE.entity = nothing
        STATE.pose = :idle
        STATE.hold_remaining = 0.0
    end

    function ensure_player!(user)::Bool
        user === nothing && return false
        entity = try user.playerEntity catch; nothing end
        if entity === nothing
            try
                entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, PLAYER_ENTITY_ID)
                user.playerEntity = entity
            catch
            end
        end
        entity === nothing && return false
        if STATE.active && STATE.entity === entity
            return true
        end
        key = try String(user.selectedCharacter) catch; "CHARACTER_MAGICIAN" end
        return attach!(entity, key; combatant = user)
    end

    function update!(deltaTime, combatant = nothing)
        STATE.active || return
        dt = Float64(deltaTime)

        if combatant !== nothing
            try
                hp = Int(combatant.health)
                if STATE.last_health >= 0 && hp < STATE.last_health
                    pulse_pose!(:damaged)
                end
                STATE.last_health = hp
            catch
            end
        end

        if STATE.hold_remaining > 0
            STATE.hold_remaining -= dt
            if STATE.hold_remaining <= 0 && STATE.pose != :idle && STATE.pose != :defeat
                set_pose!(:idle)
            end
        end
    end
end
