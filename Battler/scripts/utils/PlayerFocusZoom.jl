"""
Player-focused camera zoom used by lethal incoming attacks and the death cinematic.
"""
module PlayerFocusZoomModule
    using JulGame
    include("Easings.jl")

    export would_kill_player, begin_focus!, release_focus!, commit_focus!, update!, is_active, reset!

    const ZOOM_MUL = 1.2
    const DURATION_IN = 0.75
    const DURATION_OUT = 0.42
    const SLOWMO = 0.25
    const MUSIC_FADE = 0.9

    mutable struct FocusState
        mode::Symbol
        u::Float64
        out_start_u::Float64
        elapsed::Float64
        player::Any
        rest_zoom::Float64
        rest_x::Float64
        rest_y::Float64
        rest_z::Float64
        captured::Bool
        music_u::Float64
        music_target::Float64
    end

    const STATE = FocusState(:idle, 0.0, 0.0, 0.0, nothing, 1.0, 0.0, 0.0, 0.0, false, 1.0, 1.0)

    function is_active()::Bool
        return STATE.mode != :idle
    end

    function would_kill_player(user, damage)::Bool
        user === nothing && return false
        dmg = try Int(damage) catch; return false end
        dmg <= 0 && return false
        try
            if user.vulnerable > 0
                dmg = floor(Int, dmg * 1.5)
            end
        catch
        end
        remaining = dmg
        try
            shield = Int(user.shield)
            if shield > 0
                remaining = max(0, dmg - shield)
            end
        catch
        end
        hp = try Int(user.health) catch; return false end
        return remaining >= hp
    end

    function reset!()
        if STATE.captured
            try
                cam = MAIN.scene.camera
                cam.zoom = STATE.rest_zoom
                cam.position = Math.Vector3f(STATE.rest_x, STATE.rest_y, STATE.rest_z)
                _sync_juice_camera!()
            catch
            end
        end
        STATE.mode = :idle
        STATE.u = 0.0
        STATE.out_start_u = 0.0
        STATE.elapsed = 0.0
        STATE.player = nothing
        STATE.captured = false
        _set_slowmo!(false)
    end

    function begin_focus!(player)
        player === nothing && return
        if STATE.mode == :in || STATE.mode == :commit || STATE.mode == :hold
            STATE.player = player
            return
        end
        if STATE.mode == :out
            STATE.mode = :in
            STATE.elapsed = STATE.u * DURATION_IN
            STATE.player = player
            _set_slowmo!(true)
            _set_music_target!(0.0)
            return
        end
        try
            cam = MAIN.scene.camera
            STATE.rest_zoom = Float64(cam.zoom)
            STATE.rest_x = Float64(cam.position.x)
            STATE.rest_y = Float64(cam.position.y)
            STATE.rest_z = Float64(cam.position.z)
            STATE.captured = true
        catch
            return
        end
        STATE.player = player
        STATE.mode = :in
        STATE.u = 0.0
        STATE.elapsed = 0.0
        _set_slowmo!(true)
        _set_music_target!(0.0)
    end

    function commit_focus!()
        STATE.mode == :idle && STATE.player === nothing && return
        if STATE.mode == :idle
            return
        end
        if STATE.mode == :out
            STATE.elapsed = STATE.u * DURATION_IN
        end
        STATE.mode = :commit
        _set_slowmo!(false)
        _set_music_target!(0.0)
    end

    function release_focus!()
        (STATE.mode == :idle || STATE.mode == :commit || STATE.mode == :hold) && return
        STATE.out_start_u = max(STATE.u, 0.05)
        STATE.elapsed = 0.0
        STATE.mode = :out
        _set_slowmo!(false)
        _set_music_target!(1.0)
    end

    function _sync_juice_camera!()
        try
            parentmodule(@__MODULE__).BattleManagerModule.BattleJuiceModule.sync_camera_origin!()
        catch
        end
    end

    function _set_slowmo!(on::Bool)
        try
            juice = parentmodule(@__MODULE__).BattleManagerModule.BattleJuiceModule
            juice.set_slowmo!(on ? SLOWMO : 1.0)
        catch
        end
    end

    function _set_music_target!(target::Float64)
        STATE.music_target = clamp(target, 0.0, 1.0)
    end

    function _apply_music!()
        try
            scripts = parentmodule(@__MODULE__)
            full = scripts.DJModule.music_effective_volume_sdl()
            vol = Int(round(full * clamp(STATE.music_u, 0.0, 1.0)))
            scripts.SceneTransitionModule.set_dj_music_volume!(vol)
        catch
        end
    end

    function _tick_music!(dt::Float64)
        STATE.music_u == STATE.music_target && return
        step = dt / MUSIC_FADE
        if STATE.music_u < STATE.music_target
            STATE.music_u = min(STATE.music_target, STATE.music_u + step)
        else
            STATE.music_u = max(STATE.music_target, STATE.music_u - step)
        end
        _apply_music!()
    end

    function _cam_offset(camera)
        try
            return Float64(camera.offset.x), Float64(camera.offset.y)
        catch
            return 0.0, 0.0
        end
    end

    function _place_focus_at!(camera, new_zoom::Float64, focus_x::Float64, focus_y::Float64, screen_x::Float64, screen_y::Float64)
        S = JulGame.SCALE_UNITS * new_zoom
        ox, oy = _cam_offset(camera)
        camera.position = Math.Vector3f(
            focus_x - screen_x / S - ox,
            focus_y - screen_y / S - oy,
            camera.position.z,
        )
        camera.zoom = new_zoom
    end

    function _focus_xy()
        p = STATE.player
        if p !== nothing
            try
                pos = p.transform.position
                return Float64(pos.x), Float64(pos.y)
            catch
            end
        end
        return STATE.rest_x, STATE.rest_y
    end

    function _apply_camera!()
        STATE.captured || return
        fx, fy = _focus_xy()
        cam = MAIN.scene.camera
        ox, oy = _cam_offset(cam)
        S_rest = JulGame.SCALE_UNITS * STATE.rest_zoom
        sx0 = (fx - STATE.rest_x - ox) * S_rest
        sy0 = (fy - STATE.rest_y - oy) * S_rest
        zoom_u = clamp(STATE.u, 0.0, 1.0)
        target_zoom = STATE.rest_zoom * (1.0 + (ZOOM_MUL - 1.0) * zoom_u)
        _place_focus_at!(cam, target_zoom, fx, fy, sx0, sy0)
        _sync_juice_camera!()
    end

    function update!(deltaTime::Float64)
        dt = max(0.0, deltaTime)
        _tick_music!(dt)
        STATE.mode == :idle && return
        if STATE.mode == :in || STATE.mode == :commit
            STATE.elapsed += dt
            STATE.u = ease_in_cubic(clamp(STATE.elapsed / DURATION_IN, 0.0, 1.0))
            if STATE.u >= 1.0 && STATE.mode == :commit
                STATE.u = 1.0
                STATE.mode = :hold
            end
        elseif STATE.mode == :out
            STATE.elapsed += dt
            p = clamp(STATE.elapsed / DURATION_OUT, 0.0, 1.0)
            STATE.u = STATE.out_start_u * (1.0 - ease_out_back(p))
            if p >= 1.0
                reset!()
                return
            end
        end
        _apply_camera!()
    end
end
