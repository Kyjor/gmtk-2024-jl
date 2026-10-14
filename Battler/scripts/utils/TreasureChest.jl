module TreasureChestModule
    using JulGame
    using ..OverworldFeedbackModule

    # Treasure node event: a layered chest drops in, bursts open, and the reward flies to the player.
    # Motion is position/size/alpha only (web UIImage ignores rotation and crop).

    # "color" art set, or "" for the chalk set that matches the other event illustrations.
    const ART_SUFFIX = ""

    # Layer rects (x, y, w, h) in the artist's 930x587 canvas, drawn back to front.
    const RECT_INSIDE = (261, 222, 428, 91)
    const RECT_FRONT = (260, 248, 430, 244)
    const RECT_LID = (258, 113, 432, 225)
    const RECT_LOCK = (362, 284, 68, 65)
    const RECT_SPOTLIGHT = (164, -22, 620, 554)
    const RECT_HIT = (258, 113, 432, 379)   # lid + body, for hover/click
    const PIVOT = (474.0, 492.0)        # bottom centre of the chest
    const MOUTH = (474.0, 268.0)        # centre of the open top
    const LOCK_CENTER = (396.0, 316.0)

    const SCALE = 1.1
    const ANCHOR = (960.0, 610.0)       # screen position of PIVOT; the dialog panel starts at y 630
    const PRESENT = (960.0, 300.0)      # screen centre of the floating reward
    const REWARD_SIZE = 170.0
    const FALLBACK_TARGET = (300.0, 820.0)

    const DROP_TIME = 0.4
    const DROP_HEIGHT = 520.0
    const WINDUP_TIME = 0.55
    const LID_RISE = 160.0
    const LID_OPEN_TIME = 0.42
    const LID_SLAM_TIME = 0.16
    const SLAM_DELAY_TAKE = 0.12
    const SLAM_DELAY_LEAVE = 0.3
    const LOCK_FALL_TIME = 0.75
    const LOCK_GRAVITY = 1700.0
    const FLASH_TIME = 0.2
    const REVEAL_TIME = 0.8
    const FLY_TIME = 0.55
    const FLY_LIFT = 260.0
    const SINK_TIME = 0.35
    const MAX_SPARKS = 80

    const LAYER_SPOTLIGHT = -11
    const LAYER_INSIDE = -10
    const LAYER_GLOW = -9
    const LAYER_REWARD_INSIDE = -8
    const LAYER_FRONT = -7
    const LAYER_LID = -6
    const LAYER_GLINT = -5
    const LAYER_LOCK = -4
    const LAYER_SPARKS = -3
    const LAYER_HALO = 23
    const LAYER_FLASH = 24
    const LAYER_REWARD = 25

    const GLOW_COLOR = (255, 214, 120)
    const SPARK_COLORS = ((255, 220, 110), (255, 255, 255), (255, 240, 180))
    const DUST_COLOR = (230, 220, 200)

    mutable struct Spark
        x::Float64
        y::Float64
        vx::Float64
        vy::Float64
        age::Float64
        life::Float64
        size::Float64
        gravity::Float64
        color::NTuple{3, Int}
        frame::Int
    end

    mutable struct TreasureChest
        user
        reward              # treasure struct, or nothing for the gold fallback
        gold::Int
        icon::String
        iconAspect::Float64
        phase::Symbol       # :intro, :closed, :windup, :reveal, :presented, :taking, :leaving, :done
        phaseT::Float64
        t::Float64
        openT::Float64      # time since the lid burst open; < 0 while shut
        impactT::Float64
        impactK::Float64
        slammed::Bool
        lockVx::Float64
        sparkTimer::Float64
        sparks::Vector{Spark}
        hovered::Bool
        hoverK::Float64     # eased 0..1 hover amount
        rewardPos::NTuple{2, Float64}
        target::NTuple{2, Float64}
    end

    function TreasureChest(user)
        globals = JulGame.UserGlobals["Module"]
        reward = pick_reward(user)
        gold = reward === nothing ? _roll_gold() : 0
        icon = reward === nothing ? globals.get_asset_path("ui", "money") : globals.get_asset_path("treasure", _key_name(reward.key))
        return TreasureChest(user, reward, gold, icon, reward === nothing ? 79 / 129 : 1.0,
            :intro, 0.0, 0.0, -1.0, 10.0, 0.0, false, 0.0, 0.0, Spark[], false, 0.0, PRESENT, FALLBACK_TARGET)
    end

    """Prefers unowned treasures; nothing (gold instead) when slots are full or none are available."""
    function pick_reward(user)
        globals = JulGame.UserGlobals["Module"]
        length(user.treasures) >= user.max_treasures && return nothing
        pool = filter(globals.item_available_in_game, collect(values(globals.get_treasure_data())))
        owned_keys = Set(t.key for t in user.treasures)
        unowned = filter(t -> !(t.key in owned_keys), pool)
        pool = isempty(unowned) ? pool : unowned
        return isempty(pool) ? nothing : rand(pool)
    end

    # 25-100, weighted toward the low end.
    _roll_gold() = round(Int, 25 + rand()^2 * 75)

    function _key_name(key)::String
        parts = split(lowercase(String(key)), "_")
        return String(length(parts) >= 2 ? parts[2] : parts[1])
    end

    function _sfx(name::String)
        g = JulGame.UserGlobals["Module"]
        g.AudioManagerModule.play_audio_oneshot(g.get_audio_manager(), g.get_asset_path("sfx", name), false, 1.0, 0, 1)
    end

    _clamp01(x) = clamp(x, 0.0, 1.0)
    _ease_in_quad(x) = x * x
    _ease_out_cubic(x) = 1 - (1 - x)^3
    _ease_out_back(x) = 1 + 2.70158 * (x - 1)^3 + 1.70158 * (x - 1)^2
    _spring(t) = exp(-7t) * cos(22t)
    _alpha(a) = round(Int, clamp(a, 0, 255))

    # ---------- Commands ----------

    function open_chest!(c::TreasureChest)::Bool
        c.phase == :closed || return false
        _set_phase!(c, :windup)
        _sfx("mystery")
        return true
    end

    """Fly the reward to the player's sprite; it is granted on arrival."""
    function take_reward!(c::TreasureChest, player)::Bool
        c.phase == :presented || return false
        c.rewardPos = _presented_pos(c)
        c.target = _sprite_center(player)
        _set_phase!(c, :taking)
        _sfx("swoosh")
        return true
    end

    function leave_reward!(c::TreasureChest)::Bool
        c.phase == :presented || return false
        c.rewardPos = _presented_pos(c)
        _set_phase!(c, :leaving)
        return true
    end

    """Advance and draw. Returns :clicked when the closed chest is clicked, :presented when the reward settles,
    :finished once taken/left, else :none."""
    function update!(c::TreasureChest, dt::Real; zoom::Real = 1.0)::Symbol
        dt = Float64(dt)
        s = SCALE * Float64(zoom)
        c.t += dt
        c.phaseT += dt
        c.impactT += dt
        c.openT >= 0 && (c.openT += dt)
        clicked = _update_hover!(c, dt, s)
        signal = _advance!(c)
        _update_sparks!(c, dt)
        _draw!(c, s)
        return clicked ? :clicked : signal
    end

    # ---------- State ----------

    function _set_phase!(c::TreasureChest, phase::Symbol)
        c.phase = phase
        c.phaseT = 0.0
    end

    function _impact!(c::TreasureChest, k::Float64)
        c.impactK = k
        c.impactT = 0.0
    end

    function _advance!(c::TreasureChest)::Symbol
        if c.phase == :intro && c.phaseT >= DROP_TIME
            _impact!(c, 0.22)
            _sfx("thud2")
            _dust!(c)
            _set_phase!(c, :closed)
        elseif c.phase == :windup && c.phaseT >= WINDUP_TIME
            _burst!(c)
            _set_phase!(c, :reveal)
        elseif c.phase == :reveal && c.phaseT >= REVEAL_TIME
            _sfx("buff")
            _set_phase!(c, :presented)
            return :presented
        elseif c.phase == :taking || c.phase == :leaving
            if !c.slammed && _close_progress(c) >= 1.0
                c.slammed = true
                _impact!(c, 0.14)
                _sfx("thud1")
                _dust!(c)
            end
            if c.phase == :taking && c.phaseT >= FLY_TIME
                _grant!(c)
                _burst_sparks!(c, c.target[1], c.target[2], 14, 250.0, 520.0, false)
                _set_phase!(c, :done)
                return :finished
            elseif c.phase == :leaving && c.slammed
                _set_phase!(c, :done)
                return :finished
            end
        end
        return :none
    end

    function _burst!(c::TreasureChest)
        c.openT = 0.0
        c.lockVx = (rand(Bool) ? 1.0 : -1.0) * (140.0 + 80.0 * rand())
        _impact!(c, -0.16)
        _sfx("pixelblockbreak")
        _sfx("swoosh")
        mx, my = _to_screen(MOUTH, SCALE)
        _burst_sparks!(c, mx, my, 20, 380.0, 820.0, true)
    end

    function _grant!(c::TreasureChest)
        if c.reward === nothing
            c.user.gold += c.gold
            OverworldFeedbackModule.gold!(c.gold)
        else
            push!(c.user.treasures, c.reward)
            OverworldFeedbackModule.treasure!(c.reward)
        end
    end

    function _close_progress(c::TreasureChest)::Float64
        c.phase == :taking && return _clamp01((c.phaseT - SLAM_DELAY_TAKE) / LID_SLAM_TIME)
        c.phase == :leaving && return _clamp01((c.phaseT - SLAM_DELAY_LEAVE) / LID_SLAM_TIME)
        return 0.0
    end

    function _mouse_over(s::Float64)::Bool
        m = JulGame.InputModule.get_mouse_position()
        x, y, w, h = RECT_HIT
        x0, y0 = _to_screen((x, y), s)
        x1, y1 = _to_screen((x + w, y + h), s)
        return x0 <= m.x <= x1 && y0 <= m.y <= y1
    end

    """Track hover on the closed chest; true when it was clicked this frame."""
    function _update_hover!(c::TreasureChest, dt::Float64, s::Float64)::Bool
        was = c.hovered
        c.hovered = c.phase == :closed && _mouse_over(s)
        if c.hovered && !was
            _impact!(c, 0.06)
            _sfx("hovernewgame")
        end
        c.hoverK += ((c.hovered ? 1.0 : 0.0) - c.hoverK) * min(1.0, dt * 12)
        return c.hovered && JulGame.InputModule.get_mouse_button_pressed(1)
    end

    function _sprite_center(entity)::NTuple{2, Float64}
        try
            sprite = entity.sprite
            pos = sprite.lastRenderedScreenPosition
            sz = sprite.lastRenderedScreenSize
            (pos === nothing || sz === nothing) && return FALLBACK_TARGET
            return (Float64(pos.x) + Float64(sz.x) / 2, Float64(pos.y) + Float64(sz.y) / 2)
        catch
            return FALLBACK_TARGET
        end
    end

    # ---------- Sparks ----------

    function _push_spark!(c::TreasureChest, spark::Spark)
        length(c.sparks) < MAX_SPARKS && push!(c.sparks, spark)
    end

    function _spark(x, y, vx, vy, life, size, gravity, color)::Spark
        return Spark(x, y, vx, vy, 0.0, life, size, gravity, color, rand(1:5))
    end

    function _burst_sparks!(c::TreasureChest, x, y, n::Int, vmin::Float64, vmax::Float64, upward::Bool)
        for _ in 1:n
            angle = upward ? -π / 2 + (rand() - 0.5) * π * 0.9 : rand() * 2π
            speed = vmin + (vmax - vmin) * rand()
            _push_spark!(c, _spark(x, y, cos(angle) * speed, sin(angle) * speed, 0.5 + 0.5 * rand(),
                26.0 + 26.0 * rand(), upward ? 1400.0 : 600.0, rand(SPARK_COLORS)))
        end
    end

    function _dust!(c::TreasureChest)
        bx, by = _to_screen(PIVOT, SCALE)
        half = (RECT_FRONT[3] / 2) * SCALE
        for side in (-1.0, 1.0), _ in 1:3
            _push_spark!(c, _spark(bx + side * half, by, side * (150.0 + 150.0 * rand()), -(40.0 + 80.0 * rand()),
                0.4, 20.0 + 10.0 * rand(), 300.0, DUST_COLOR))
        end
    end

    function _ambient_sparks!(c::TreasureChest, dt::Float64)
        c.sparkTimer -= dt
        c.sparkTimer > 0 && return
        if c.phase == :closed || c.phase == :windup
            c.sparkTimer = c.phase == :windup ? 0.04 : c.hovered ? 0.06 : 0.12 + 0.08 * rand()
            angle = rand() * 2π
            speed = 50.0 + 60.0 * rand()
            x, y = _to_screen((LOCK_CENTER[1] + cos(angle) * 14, LOCK_CENTER[2] + sin(angle) * 14), SCALE)
            _push_spark!(c, _spark(x, y, cos(angle) * speed, sin(angle) * speed, 0.7 + 0.4 * rand(),
                14.0 + 10.0 * rand(), -30.0, rand(SPARK_COLORS)))
        elseif c.phase == :reveal || c.phase == :presented
            c.sparkTimer = 0.08
            mx, my = _to_screen(MOUTH, SCALE)
            _push_spark!(c, _spark(mx + (rand() - 0.5) * 300 * SCALE, my, (rand() - 0.5) * 40, -(120.0 + 120.0 * rand()),
                0.8 + 0.4 * rand(), 16.0 + 16.0 * rand(), -40.0, rand(SPARK_COLORS)))
        end
    end

    function _update_sparks!(c::TreasureChest, dt::Float64)
        _ambient_sparks!(c, dt)
        for p in c.sparks
            p.age += dt
            p.vy += p.gravity * dt
            p.vx *= max(0.0, 1.0 - 1.5 * dt)
            p.x += p.vx * dt
            p.y += p.vy * dt
        end
        filter!(p -> p.age < p.life, c.sparks)
    end

    # ---------- Drawing ----------

    _to_screen(p, s; sx = 1.0, sy = 1.0, ox = 0.0, oy = 0.0) =
        (ANCHOR[1] + ox + (p[1] - PIVOT[1]) * s * sx, ANCHOR[2] + oy + (p[2] - PIVOT[2]) * s * sy)

    function _image(id::String, path::String, x, y, w, h, layer::Int; color = (255, 255, 255), alpha = 255)
        sz = JulGame.Math.Vector2(w, h)
        img = JulGame.ImmediateUIModule.immediate_image(
            id,
            path;
            anchor = :none,
            position = JulGame.Math.Vector2(x, y),
            size = sz,
            color = (color[1], color[2], color[3], _alpha(alpha)),
            layer = layer,
        )
        if img !== nothing
            # UIImage renders originalSize, and ImmediateUI only writes size — lock both
            img.size = sz
            img.originalSize = sz
        end
        return img
    end

    _centered(id, path, x, y, w, h, layer; kwargs...) = _image(id, path, x - w / 2, y - h / 2, w, h, layer; kwargs...)

    _art(part::String) = JulGame.UserGlobals["Module"].get_asset_path("eventimg", "treasurechest$(part)$(ART_SUFFIX)")

    """One chest layer, squashed about the chest pivot plus its own bottom centre (psx/psy), offset by dx/dy canvas px."""
    function _draw_part(part::String, rect, layer::Int, s, sx, sy, ox, oy; dx = 0.0, dy = 0.0, psx = 1.0, psy = 1.0, alpha = 255)
        x, y, w, h = rect
        bx, by = _to_screen((x + w / 2 + dx, y + h + dy), s; sx = sx, sy = sy, ox = ox, oy = oy)
        W = w * s * sx * psx
        H = h * s * sy * psy
        _image("treasure_chest_$(part)", _art(part), bx - W / 2, by - H, W, H, layer; alpha = alpha)
    end

    function _body_squash(c::TreasureChest)
        sx, sy, ox = 1.0, 1.0, 0.0
        if c.phase == :closed
            b = sin(c.t * 2.4)
            sy += 0.012 * b
            sx -= 0.008 * b
        elseif c.phase == :windup
            e = _windup_ease(c)
            sy -= 0.1 * e
            sx += 0.07 * e
            ox = sin(c.phaseT * 70) * (2 + 7 * e)
        end
        sp = c.impactK * _spring(c.impactT)
        return (sx + 0.6 * sp, sy - sp, ox)
    end

    _windup_ease(c::TreasureChest) = c.phase == :windup ? _ease_in_quad(_clamp01(c.phaseT / WINDUP_TIME)) : 0.0

    function _lid_lift(c::TreasureChest)::Float64
        (c.openT < 0 || c.phase == :done) && return 0.0
        lift = _ease_out_back(_clamp01(c.openT / LID_OPEN_TIME))
        c.openT > LID_OPEN_TIME && (lift += 0.04 * sin(2.6 * (c.openT - LID_OPEN_TIME)))
        return lift * (1.0 - _ease_in_quad(_close_progress(c)))
    end

    _presented_pos(c::TreasureChest) = (PRESENT[1], PRESENT[2] + 10 * sin(2.2 * c.phaseT))

    """(x, y, width, layer) of the reward this frame, or nothing when hidden."""
    function _reward_state(c::TreasureChest)
        mx, my = _to_screen(MOUTH, SCALE)
        if c.phase == :reveal
            q = _clamp01(c.phaseT / REVEAL_TIME)
            return (mx + (PRESENT[1] - mx) * _ease_out_cubic(q), my + (PRESENT[2] - my) * _ease_out_back(q),
                REWARD_SIZE * (0.25 + 0.75 * _ease_out_back(_clamp01(q * 1.4))), q < 0.15 ? LAYER_REWARD_INSIDE : LAYER_REWARD)
        elseif c.phase == :presented
            x, y = _presented_pos(c)
            return (x, y, REWARD_SIZE * (1 + 0.04 * sin(4.4 * c.phaseT)), LAYER_REWARD)
        elseif c.phase == :taking
            q = _clamp01(c.phaseT / FLY_TIME)
            e = q * q
            inv = 1 - e
            (fx, fy), (tx, ty) = c.rewardPos, c.target
            cx, cy = (fx + tx) / 2, min(fy, ty) - FLY_LIFT
            return (inv^2 * fx + 2 * inv * e * cx + e^2 * tx, inv^2 * fy + 2 * inv * e * cy + e^2 * ty,
                REWARD_SIZE * (1 + 0.2 * sin(π * q) - 0.65 * e), LAYER_REWARD)
        elseif c.phase == :leaving
            q = c.phaseT / SINK_TIME
            q >= 1 && return nothing
            e = _ease_in_quad(q)
            fx, fy = c.rewardPos
            return (fx + (mx - fx) * e, fy + (my - fy) * e, REWARD_SIZE * (1 - 0.75 * e), q > 0.6 ? LAYER_REWARD_INSIDE : LAYER_REWARD)
        end
        return nothing
    end

    function _draw!(c::TreasureChest, s::Float64)
        globals = JulGame.UserGlobals["Module"]
        glow = globals.get_asset_path("eventimg", "treasurechestglow")
        intro = c.phase == :intro ? _clamp01(c.phaseT / DROP_TIME) : 1.0
        opened = c.openT >= 0 && c.phase != :done
        closing = 1.0 - _close_progress(c)

        # Stage light (does not drop with the chest)
        lx, ly, lw, lh = RECT_SPOTLIGHT
        sx0, sy0 = _to_screen((lx, ly), s)
        flare = opened ? 105 * exp(-3 * c.openT) * closing : 0.0
        _image("treasure_spotlight", globals.get_asset_path("menu", "spotlightbottom"), sx0, sy0, lw * s, lh * s, LAYER_SPOTLIGHT;
            color = (255, 240, 200), alpha = (150 + 15 * sin(1.3 * c.t) + flare) * intro)

        sx, sy, ox = _body_squash(c)
        oy = -DROP_HEIGHT * (1 - _ease_in_quad(intro))
        _draw_part("inside", RECT_INSIDE, LAYER_INSIDE, s, sx, sy, ox, oy)

        if opened
            g = _ease_out_back(_clamp01(c.openT / 0.35))
            mx, my = _to_screen(MOUTH, s; sx = sx, sy = sy, ox = ox, oy = oy)
            size = 520 * s * g * (1 + 0.05 * sin(3.1 * c.t))
            _centered("treasure_glow", glow, mx, my, size, size, LAYER_GLOW;
                color = GLOW_COLOR, alpha = (170 + 85 * exp(-4 * c.openT)) * closing)
        end

        _draw_part("front", RECT_FRONT, LAYER_FRONT, s, sx, sy, ox, oy)

        e = _windup_ease(c)
        hk = c.hoverK
        rattle = (c.phase == :windup ? -abs(sin(c.phaseT * 38)) * 8 * e : 0.0) - abs(sin(c.t * 30)) * 3 * hk
        launch = opened ? exp(-9 * c.openT) : 0.0
        _draw_part("lid", RECT_LID, LAYER_LID, s, sx, sy, ox, oy;
            dy = -LID_RISE * _lid_lift(c) + rattle, psx = 1 - 0.08 * launch, psy = 1 + 0.18 * launch)

        if c.openT < 0
            gx, gy = _to_screen(LOCK_CENTER, s; sx = sx, sy = sy, ox = ox, oy = oy)
            pulse = sin(5 * c.t)
            size = 110 * s * (1 + 0.12 * pulse) * (1 + 1.2 * e) * (1 + 0.35 * hk)
            _centered("treasure_glint", glow, gx, gy, size, size, LAYER_GLINT;
                color = GLOW_COLOR, alpha = (110 + 50 * pulse + 120 * e + 70 * hk) * intro)
            _draw_part("lock", RECT_LOCK, LAYER_LOCK, s, sx, sy, ox, oy;
                dx = sin(c.phaseT * 55) * 3 * e + sin(c.t * 48) * 4 * hk, dy = -abs(sin(c.t * 24)) * 3 * hk)
        elseif c.openT < LOCK_FALL_TIME
            t = c.openT
            _draw_part("lock", RECT_LOCK, LAYER_LOCK, s, sx, sy, ox, oy;
                dx = c.lockVx * t, dy = -480 * t + 0.5 * LOCK_GRAVITY * t^2,
                alpha = 255 * (1 - _clamp01((t - 0.35) / 0.4)))
        end

        reward = _reward_state(c)
        if reward !== nothing
            x, y, w, layer = reward
            h = w * c.iconAspect
            if layer == LAYER_REWARD
                _centered("treasure_halo", glow, x, y, w * 2.2, w * 2.2, LAYER_HALO; color = GLOW_COLOR, alpha = 150)
            end
            _centered("treasure_reward", c.icon, x, y, w, h, layer)
        end

        for (i, p) in enumerate(c.sparks)
            q = p.age / p.life
            size = p.size * (1 - 0.6 * q)
            _centered("treasure_spark_$(i)", globals.get_asset_path("fx", "sparkle$(p.frame)"), p.x, p.y, size, size, LAYER_SPARKS;
                color = p.color, alpha = 255 * (1 - q))
        end

        if opened && c.openT < FLASH_TIME
            JulGame.ImmediateUIModule.immediate_rect(
                "treasure_flash";
                anchor = :center,
                size = JulGame.Math.Vector2(1920, 1080),
                color = (255, 255, 255, _alpha(150 * (1 - c.openT / FLASH_TIME))),
                layer = LAYER_FLASH,
            )
        end
    end

    export TreasureChest, update!, open_chest!, take_reward!, leave_reward!, pick_reward
end
