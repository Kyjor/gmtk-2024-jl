"""
Player death cinematic: fade to black while zooming, knockback tumble,
heart break, spotlight drop, then Game Over UI.
"""
module PlayerDeathAnimatorModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule
    include("Easings.jl")
    include("../localization/ui_strings.jl")
    using .UIStringsModule

    export play_death!, update_animator!, is_active, owns, reset_animator!

    const T_FADE = 1.15
    const T_IMPACT_SHAKE = 0.45
    const IMPACT_SHAKE_PX = 28.0
    const T_FIRST_LAND = 5.0
    const T_SECOND_LAND = 5.55
    const T_REST = 6.10
    const T_HEART_RISE = 6.90
    const T_HEART_BREAK = 7.00
    const T_HEART_DONE = 7.85
    const T_SPOT_START = 7.95
    const T_SPOT_END = 8.60
    const T_TITLE_START = 8.40
    const T_TITLE_END = 9.10
    const T_OPTIONS_END = 9.55
    const LAND_TIMES = (T_FIRST_LAND, T_SECOND_LAND, T_REST)
    const BLACK_LAYER = 8000
    const SPOT_LAYER = 8010
    const PLAYER_LAYER = 8020
    const HEART_LAYER = 8030
    const UI_LAYER = 8100
    const HEART_IMG = "ui-healthheart"
    const HEART_SRC_W = 108
    const HEART_SRC_H = 95
    const SPOTLIGHT_BOTTOM = "menu-spotlightbottom"
    const SPOTLIGHT_TOP = "menu-spotlighttop"
    const HEART_COLOR = (255, 70, 127, 255)

    mutable struct DeathState
        active::Bool
        elapsed::Float64
        player::Any
        battle_manager::Any
        on_finalize::Union{Nothing, Function}
        on_exit::Union{Nothing, Function}
        cam_zoom::Float64
        cam_x::Float64
        cam_y::Float64
        cam_z::Float64
        cam_captured::Bool
        base_x::Float64
        base_y::Float64
        base_z::Float64
        base_sx::Float64
        base_sy::Float64
        base_sz::Float64
        base_rz::Float64
        color_r::Int
        color_g::Int
        color_b::Int
        color_a::Int
        sprite_layer::Int
        image_path::String
        px::Float64
        py::Float64
        pw::Float64
        ph::Float64
        prz::Float64
        squash::Float64
        fly_x0::Float64
        fly_y0::Float64
        rest_cx::Float64
        rest_cy::Float64
        bounce_stage::Int
        heart_broken::Bool
        beat_commented::Bool
        finalized::Bool
        screen_captured::Bool
        fly_locked::Bool
    end

    const STATE = DeathState(
        false, 0.0, nothing, nothing, nothing, nothing,
        1.0, 0.0, 0.0, 0.0, false,
        0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0,
        255, 255, 255, 255, 0,
        "",
        0.0, 0.0, 160.0, 220.0, 0.0, 1.0,
        0.0, 0.0, 0.0, 0.0,
        0, false, false, false, false, false,
    )

    function is_active()::Bool
        return STATE.active
    end

    function owns(entity)::Bool
        STATE.active || return false
        entity === nothing && return false
        return entity === STATE.player
    end

    function reset_animator!()
        STATE.active = false
        STATE.elapsed = 0.0
        STATE.player = nothing
        STATE.battle_manager = nothing
        STATE.on_finalize = nothing
        STATE.on_exit = nothing
        STATE.bounce_stage = 0
        STATE.heart_broken = false
        STATE.beat_commented = false
        STATE.finalized = false
        STATE.screen_captured = false
        STATE.fly_locked = false
        STATE.image_path = ""
        STATE.prz = 0.0
        STATE.squash = 1.0
        # Reset camera zoom to 1.0
        cam = MAIN.scene.camera
        cam.zoom = 1.0
        parentmodule(@__MODULE__).PlayerFocusZoomModule.reset!()
    end

    function _sfx(name::String)
        try
            g = JulGame.UserGlobals["Module"]
            g.AudioManagerModule.play_audio_oneshot(
                g.get_audio_manager(),
                g.get_asset_path("sfx", name),
                false, 1.0, 0, 1,
            )
        catch e
            @debug "player death sfx: $e"
        end
    end

    function _nineslice()
        try
            return parentmodule(@__MODULE__).NineSliceUIModule
        catch
            return nothing
        end
    end

    function _logical_size()
        try
            s = JulGame.WindowManagerModule.get_logical_size()
            return Float64(s.x), Float64(s.y)
        catch
            return 1920.0, 1080.0
        end
    end

    function _world_to_screen(wx::Float64, wy::Float64)
        cam = MAIN.scene.camera
        scale = JulGame.SCALE_UNITS * Float64(cam.zoom)
        sx = Float64(cam.size.x) / 2 + (wx - Float64(cam.position.x)) * scale
        sy = Float64(cam.size.y) / 2 + (wy - Float64(cam.position.y)) * scale
        return sx, sy
    end

    function _capture_screen_from_world!()
        p = STATE.player
        p === nothing && return
        captured = false
        try
            sp = p.sprite.lastRenderedScreenPosition
            sz = p.sprite.lastRenderedScreenSize
            if sp !== nothing && sz !== nothing && Float64(sz.x) > 4.0
                STATE.px = Float64(sp.x)
                STATE.py = Float64(sp.y)
                STATE.pw = max(8.0, Float64(sz.x))
                STATE.ph = max(8.0, Float64(sz.y))
                captured = true
            end
        catch
        end
        if !captured
            try
                sx, sy = _world_to_screen(STATE.base_x, STATE.base_y)
                cam = MAIN.scene.camera
                scale = JulGame.SCALE_UNITS * Float64(cam.zoom)
                STATE.pw = max(96.0, abs(STATE.base_sx) * scale)
                STATE.ph = max(128.0, abs(STATE.base_sy) * scale)
                STATE.px = sx - STATE.pw * 0.5
                STATE.py = sy - STATE.ph * 0.5
                captured = true
            catch
            end
        end
        captured && (STATE.screen_captured = true)
    end

    function _body_center()
        return STATE.px + STATE.pw * 0.5, STATE.py + STATE.ph * 0.5
    end

    function _stage_rest_center()
        lw, lh = _logical_size()
        cx0, cy0 = STATE.fly_x0, STATE.fly_y0
        half_vis = max(STATE.pw, STATE.ph) * 0.52
        min_cx = half_vis + 80.0
        stage_cx = lw * 0.34
        rest_cx = clamp(cx0 - 110.0, min_cx, max(min_cx, stage_cx))
        rest_cy = lh * 0.55
        return rest_cx, rest_cy
    end

    function _bounce_height(t::Float64)::Float64
        if t < T_FIRST_LAND
            u = t / T_FIRST_LAND
            return 320.0 * 4.0 * u * (1.0 - u)
        elseif t < T_SECOND_LAND
            u = (t - T_FIRST_LAND) / max(T_SECOND_LAND - T_FIRST_LAND, 0.001)
            return 90.0 * 4.0 * u * (1.0 - u)
        elseif t < T_REST
            u = (t - T_SECOND_LAND) / max(T_REST - T_SECOND_LAND, 0.001)
            return 28.0 * 4.0 * u * (1.0 - u)
        end
        return 0.0
    end

    function _land_squash(t::Float64)::Float64
        nearest = 1.0
        for land in LAND_TIMES
            nearest = min(nearest, abs(t - land))
        end
        return 1.0 - 0.28 * exp(-nearest * 28.0)
    end

    function _tick_fly!(t::Float64)
        rest_cx, rest_cy = _stage_rest_center()
        air_u = clamp(t / T_FIRST_LAND, 0.0, 1.0)
        cx = STATE.fly_x0 + (rest_cx - STATE.fly_x0) * ease_out_cubic(air_u)
        cy = rest_cy - _bounce_height(t)
        STATE.px = cx - STATE.pw * 0.5
        STATE.py = cy - STATE.ph * 0.5
        STATE.prz = -90.0 * ease_out_cubic(clamp(t / 0.7, 0.0, 1.0))
        STATE.squash = _land_squash(t)
        STATE.rest_cx = rest_cx
        STATE.rest_cy = rest_cy
        if t >= T_REST
            STATE.rest_cx = cx
            STATE.rest_cy = cy
        end
        while STATE.bounce_stage < length(LAND_TIMES) && t >= LAND_TIMES[STATE.bounce_stage + 1]
            STATE.bounce_stage += 1
            _sfx("thud$(STATE.bounce_stage)")
        end
    end

    function _impact_shake(t::Float64)
        t >= T_IMPACT_SHAKE && return 0.0, 0.0
        amp = IMPACT_SHAKE_PX * (1.0 - t / T_IMPACT_SHAKE)
        return (rand() - 0.5) * 2.0 * amp, (rand() - 0.5) * 2.0 * amp
    end

    function _draw_player_clone!(t::Float64)
        isempty(STATE.image_path) && return
        lw, lh = _logical_size()
        cx, cy = _body_center()
        sx, sy = _impact_shake(t)
        cx += sx
        cy += sy
        w = STATE.pw
        h = STATE.ph * STATE.squash
        img = JulGame.ImmediateUIModule.immediate_image(
            "player_death_body",
            STATE.image_path;
            anchor = :center,
            anchorOffset = Math.Vector2(Int(round(cx - lw * 0.5)), Int(round(cy - lh * 0.5))),
            size = Math.Vector2(Int(round(w)), Int(round(h))),
            color = (STATE.color_r, STATE.color_g, STATE.color_b, 255),
            layer = PLAYER_LAYER,
        )
        try
            img.rotation = STATE.prz
        catch
        end
    end

    function _draw_black!(t::Float64)
        lw, lh = _logical_size()
        a = Int(round(255 * ease_in_out_sine(clamp(t / T_FADE, 0.0, 1.0))))
        a <= 0 && return
        JulGame.ImmediateUIModule.immediate_rect(
            "player_death_black";
            position = Math.Vector2(0, 0),
            size = Math.Vector2(Int(round(lw)) + 8, Int(round(lh)) + 8),
            color = (0, 0, 0, a),
            layer = BLACK_LAYER,
        )
    end

    function _draw_heart!(t::Float64)
        t < T_REST && return
        cx, cy = STATE.rest_cx, STATE.rest_cy
        s = max(56.0, STATE.ph * 0.42)
        if t < T_HEART_BREAK
            rise = clamp((t - T_REST) / max(T_HEART_RISE - T_REST, 0.001), 0.0, 1.0)
            y = cy + 24.0 - 150.0 * ease_out_cubic(rise)
            JulGame.ImmediateUIModule.immediate_image(
                "player_death_heart",
                JulGame.UserGlobals["Module"].get_asset_path(HEART_IMG);
                position = Math.Vector2(Int(round(cx - s * 0.5)), Int(round(y - s * 0.5))),
                size = Math.Vector2(Int(round(s)), Int(round(s))),
                color = HEART_COLOR,
                layer = PLAYER_LAYER - 1,
            )
            return
        end
        if !STATE.heart_broken
            STATE.heart_broken = true
            # SOUND: heart-break sting when an asset exists
        end
        age = max(0.0, t - T_HEART_BREAK)
        fade = clamp(1.0 - age / max(T_HEART_DONE - T_HEART_BREAK, 0.001), 0.0, 1.0)
        a = Int(round(HEART_COLOR[4] * fade))
        a <= 0 && return
        lw, lh = _logical_size()
        y0 = cy + 24.0 - 150.0
        g = 520.0
        half_w = s * 0.5
        half_src = HEART_SRC_W ÷ 2
        dw = Int(round(half_w))
        dh = Int(round(s))
        for (side, id, sx) in ((-1.0, "player_death_shard_l", 0), (1.0, "player_death_shard_r", half_src))
            dx = side * (half_w * 0.5 + 130.0 * age)
            dy = -32.0 * age + 0.5 * g * age * age
            rot = side * (14.0 + 240.0 * age)
            img = JulGame.ImmediateUIModule.immediate_image(
                id,
                JulGame.UserGlobals["Module"].get_asset_path(HEART_IMG);
                anchor = :center,
                anchorOffset = Math.Vector2(Int(round(cx + dx - lw * 0.5)), Int(round(y0 + dy - lh * 0.5))),
                size = Math.Vector2(dw, dh),
                crop = Math.Vector4(sx, 0, half_src, HEART_SRC_H),
                color = (HEART_COLOR[1], HEART_COLOR[2], HEART_COLOR[3], a),
                layer = HEART_LAYER,
            )
            try
                img.rotation = rot
                img.size = Math.Vector2(dw, dh)
                img.originalSize = Math.Vector2(dw, dh)
            catch
            end
        end
    end

    function _draw_spotlight!(t::Float64)
        t < T_SPOT_START && return
        u = clamp((t - T_SPOT_START) / max(T_SPOT_END - T_SPOT_START, 0.001), 0.0, 1.0)
        slide = ease_out_cubic(u)
        lw, lh = _logical_size()
        dest_y = STATE.rest_cy - 40.0
        spot_h = max(838.0, dest_y * 2.0)
        spot_w = 937.0 * (spot_h / 838.0)
        top_h = 367.0 * (spot_h / 838.0)
        top_w = 549.0 * (spot_h / 838.0)
        y = dest_y + (1.0 - slide) * (-(lh + 200.0))
        ox = Int(round(STATE.rest_cx - lw * 0.5))
        oy = Int(round(y - lh * 0.5))
        bottom = JulGame.ImmediateUIModule.immediate_image(
            "player_death_spotlight_bottom",
            JulGame.UserGlobals["Module"].get_asset_path(SPOTLIGHT_BOTTOM);
            anchor = :center,
            anchorOffset = Math.Vector2(ox, oy),
            size = Math.Vector2(Int(round(spot_w)), Int(round(spot_h))),
            color = (255, 255, 255, 255),
            layer = SPOT_LAYER,
        )
        JulGame.ImmediateUIModule.immediate_image(
            "player_death_spotlight_top",
            JulGame.UserGlobals["Module"].get_asset_path(SPOTLIGHT_TOP);
            anchor = :centerTop,
            size = Math.Vector2(Int(round(top_w)), Int(round(top_h))),
            color = (255, 255, 255, 255),
            layer = SPOT_LAYER + 1,
            parent = bottom,
        )
    end

    function _go_title!()
        cb = STATE.on_exit
        if cb !== nothing
            cb()
            return
        end
        try
            bm = STATE.battle_manager
            trans = bm === nothing ? nothing : bm.transitionManager
            parentmodule(@__MODULE__).SceneTransitionModule.transition_to_scene(
                trans,
                "title_scene.json";
                direction = parentmodule(@__MODULE__).SceneTransitionModule.Fade,
            )
        catch e
            @debug "player death exit: $e"
        end
    end

    function _draw_game_over!(t::Float64)
        t < T_TITLE_START && return
        title_u = clamp((t - T_TITLE_START) / max(T_TITLE_END - T_TITLE_START, 0.001), 0.0, 1.0)
        slide = ease_out_back(title_u)
        y_off = Int(round((1.0 - slide) * -420.0))
        ui_x = 430
        settled_y = -80
        DisplayTextModule.display_text(
            "player_death_title",
            UIStringsModule.UI_STRINGS[:game_over_title];
            fontSize = 72,
            color = (255, 230, 210, 255),
            anchor = :center,
            anchorOffset = Math.Vector2(ui_x, settled_y + y_off),
            layer = UI_LAYER,
            applyEffects = false,
        )
        q_a = 0
        opt_a = 0
        clickable = false
        if t >= T_TITLE_END
            fade = clamp((t - T_TITLE_END) / max(T_OPTIONS_END - T_TITLE_END, 0.001), 0.0, 1.0)
            q_a = Int(round(255 * fade))
            opt_a = q_a
            clickable = fade >= 1.0
        end
        q_a > 0 && DisplayTextModule.display_text(
            "player_death_title_q",
            UIStringsModule.UI_STRINGS[:game_over_question];
            fontSize = 72,
            color = (255, 230, 210, q_a),
            anchor = :center,
            anchorOffset = Math.Vector2(ui_x + 210, settled_y),
            layer = UI_LAYER,
            applyEffects = false,
        )
        opt_a <= 0 && return
        ns = _nineslice()
        btn_y = 80
        for (id, label_key, x_off) in (
            ("player_death_continue", :game_over_continue, ui_x - 150),
            ("player_death_exit", :game_over_exit, ui_x + 150),
        )
            click = clickable ? (() -> _go_title!()) : (() -> nothing)
            host = nothing
            if ns !== nothing
                try
                    host = ns.immediate_panel(
                        "$(id)_panel";
                        size = Math.Vector2(280, 90),
                        anchor = :center,
                        anchorOffset = Math.Vector2(x_off, btn_y),
                        layer = UI_LAYER,
                    )
                catch
                end
            end
            if host === nothing
                host = JulGame.ImmediateUIModule.immediate_rect(
                    "$(id)_panel";
                    size = Math.Vector2(280, 90),
                    anchor = :center,
                    anchorOffset = Math.Vector2(x_off, btn_y),
                    color = (20, 18, 22, Int(round(230 * (opt_a / 255)))),
                    layer = UI_LAYER,
                    clickEvent = click,
                )
            else
                try
                    host.clickEvents = Function[click]
                catch
                end
            end
            DisplayTextModule.display_text(
                "$(id)_label",
                UIStringsModule.UI_STRINGS[label_key];
                fontSize = 32,
                color = (245, 240, 230, opt_a),
                anchor = :center,
                anchorOffset = Math.Vector2(x_off, btn_y),
                layer = UI_LAYER + 1,
                clickEvent = click,
                applyEffects = false,
            )
        end
    end

    function play_death!(user, battle_manager; on_finalize = nothing, on_exit = nothing)
        reset_animator!()
        player = nothing
        try
            player = user.playerEntity
        catch
        end
        player === nothing && return
        STATE.active = true
        STATE.elapsed = 0.0
        STATE.player = player
        STATE.battle_manager = battle_manager
        STATE.on_finalize = on_finalize
        STATE.on_exit = on_exit
        _sfx("lethalmovegameover")
        try
            user.healthHeart !== nothing && (user.healthHeart.isActive = false)
        catch
        end
        try
            user.healthHeartBackground !== nothing && (user.healthHeartBackground.isActive = false)
        catch
        end
        try
            user.shieldUI !== nothing && (user.shieldUI.isActive = false)
        catch
        end
        p = player.transform.position
        s = player.transform.scale
        STATE.base_x = Float64(p.x)
        STATE.base_y = Float64(p.y)
        STATE.base_z = hasproperty(p, :z) ? Float64(p.z) : 0.0
        STATE.base_sx = Float64(s.x)
        STATE.base_sy = Float64(s.y)
        STATE.base_sz = hasproperty(s, :z) ? Float64(s.z) : 1.0
        try
            STATE.base_rz = Float64(player.transform.rotation.z)
        catch
            STATE.base_rz = 0.0
        end
        try
            c = player.sprite.color
            STATE.color_r = Int(c[1]); STATE.color_g = Int(c[2]); STATE.color_b = Int(c[3]); STATE.color_a = Int(c[4])
            STATE.sprite_layer = Int(player.sprite.layer)
            STATE.image_path = String(player.sprite.imagePath)
        catch
        end
        try
            cam = MAIN.scene.camera
            STATE.cam_zoom = Float64(cam.zoom)
            STATE.cam_x = Float64(cam.position.x)
            STATE.cam_y = Float64(cam.position.y)
            STATE.cam_z = Float64(cam.position.z)
            STATE.cam_captured = true
        catch
            STATE.cam_captured = false
        end
        try
            parentmodule(@__MODULE__).PlayerFocusZoomModule.begin_focus!(player)
            parentmodule(@__MODULE__).PlayerFocusZoomModule.commit_focus!()
        catch
        end
        _capture_screen_from_world!()
        cx, cy = _body_center()
        STATE.fly_x0 = cx
        STATE.fly_y0 = cy
        STATE.rest_cx = cx
        STATE.rest_cy = cy
    end

    function _maybe_finalize!(t::Float64)
        t < T_REST && return
        STATE.finalized && return
        STATE.finalized = true
        cb = STATE.on_finalize
        cb !== nothing && cb()
        try
            STATE.player !== nothing && (STATE.player.isActive = false)
        catch
        end
    end

    function _lock_fly_origin!()
        cx, cy = _body_center()
        STATE.pw *= 1.2
        STATE.ph *= 1.2
        STATE.px = cx - STATE.pw * 0.5
        STATE.py = cy - STATE.ph * 0.5
        STATE.fly_x0 = cx
        STATE.fly_y0 = cy
        STATE.rest_cx, STATE.rest_cy = _stage_rest_center()
        STATE.fly_locked = true
    end

    function update_animator!(deltaTime::Float64)
        STATE.active || return
        STATE.elapsed += max(0.0, deltaTime)
        t = STATE.elapsed
        if !STATE.fly_locked
            _capture_screen_from_world!()
            if STATE.screen_captured || t > 0.08
                _lock_fly_origin!()
            else
                cx, cy = _body_center()
                STATE.fly_x0 = cx
                STATE.fly_y0 = cy
            end
        end
        STATE.fly_locked && _tick_fly!(t)
        _maybe_finalize!(t)
        _draw_black!(t)
        _draw_spotlight!(t)
        _draw_player_clone!(t)
        _draw_heart!(t)
        _draw_game_over!(t)
    end
end
