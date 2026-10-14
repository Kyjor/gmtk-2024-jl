"""
ButtonJuiceModule

Reusable juice for anchored UI buttons, keyed by id (no per-button struct fields needed).
Hover: gentle scale pulse plus a small shake on enter. Click: quick shake + click SFX, then the
button flies off to the right (ease-in) and `on_left` runs once it is offscreen.

Call `update!` every frame after the root's `anchorOffset`/`size` are back at their rest values.
Children anchored to the root follow it. Only `size`/`anchorOffset` are touched, so baked effect
textures are stretched rather than re-baked.
"""
module ButtonJuiceModule
    using JulGame

    export update!, click!, hover_pulse_scale

    const CLICK_SFX = "sfx-clickswoosh"
    const PULSE_SPEED = 5.0             # radians per second
    const PULSE_SCALE = 0.04
    const HOVER_SHAKE_DURATION = 0.25
    const HOVER_SHAKE_AMOUNT = 4.0
    const CLICK_SHAKE_DURATION = 0.15
    const CLICK_SHAKE_AMOUNT = 10.0
    const FLY_DURATION = 0.35
    const FLY_DISTANCE = 2400.0         # clears the right edge of the 1920-wide logical screen

    mutable struct JuiceState
        hovered::Bool
        pulse_time::Float64
        shake_left::Float64             # seconds of shake remaining
        shake_duration::Float64
        shake_amount::Float64
        leave_time::Float64             # < 0 until clicked
        on_left::Union{Function, Nothing}
        last_frame::Int
        last_time::Float64
    end

    JuiceState() = JuiceState(false, 0.0, 0.0, 1.0, 0.0, -1.0, nothing, JulGame.FrameCount, time())

    const STATES = Dict{String, JuiceState}()

    """State for `id`; resets itself when the button hasn't been updated for a few frames (reopened screen / new scene)."""
    function _state(id::String)::JuiceState
        s = get(STATES, id, nothing)
        if s === nothing || JulGame.FrameCount - s.last_frame > 2
            s = JuiceState()
            STATES[id] = s
        end
        s.last_frame = JulGame.FrameCount
        return s
    end

    """Scale multiplier after `t` seconds of hover (also used by board pieces)."""
    hover_pulse_scale(t::Float64)::Float64 = 1.0 + PULSE_SCALE * (1.0 - cos(t * PULSE_SPEED)) / 2.0

    function _start_shake!(s::JuiceState, duration::Float64, amount::Float64)
        s.shake_left = duration
        s.shake_duration = duration
        s.shake_amount = amount
    end

    # 0 = left/top edge, 0.5 = centered, 1 = right/bottom edge.
    function _anchor_factors(anchor)::Tuple{Float64, Float64}
        a = lowercase(string(anchor))
        fx = occursin("right", a) ? 1.0 : occursin("left", a) ? 0.0 : 0.5
        fy = occursin("bottom", a) ? 1.0 : occursin("top", a) ? 0.0 : 0.5
        return (fx, fy)
    end

    function _play_click_sfx()
        try
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path(CLICK_SFX), false, 1.0, 0, 1)
        catch e
            @debug "ButtonJuice sfx: $e"
        end
    end

    """Advance and apply the juice for `id` to `root` (hover state supplied by the caller)."""
    function update!(id::String, root, hovered::Bool)
        s = _state(id)
        now = time()
        dt = clamp(now - s.last_time, 0.0, 0.1)
        s.last_time = now

        rest_offset = root.anchorOffset
        rest_size = root.size
        dx = 0.0
        dy = 0.0
        scale = 1.0

        if s.leave_time >= 0
            s.leave_time += dt
            fly = clamp((s.leave_time - CLICK_SHAKE_DURATION) / FLY_DURATION, 0.0, 1.0)
            dx += FLY_DISTANCE * fly^3
            if fly >= 1.0 && s.on_left !== nothing
                on_left = s.on_left
                s.on_left = nothing
                on_left()
            end
        else
            hovered && !s.hovered && _start_shake!(s, HOVER_SHAKE_DURATION, HOVER_SHAKE_AMOUNT)
            s.pulse_time = hovered ? s.pulse_time + dt : 0.0
            scale = hover_pulse_scale(s.pulse_time)
        end
        s.hovered = hovered

        if s.shake_left > 0
            s.shake_left = max(s.shake_left - dt, 0.0)
            progress = 1.0 - s.shake_left / s.shake_duration
            amount = s.shake_amount * (1.0 - progress)
            dx += sin(progress * 20.0) * amount
            dy += cos(progress * 17.0) * amount
        end

        # Grow around the center regardless of which corner the root is anchored to.
        fx, fy = _anchor_factors(root.anchor.current_state)
        grow_x = rest_size.x * (scale - 1.0)
        grow_y = rest_size.y * (scale - 1.0)
        root.size = Math.Vector2(rest_size.x + grow_x, rest_size.y + grow_y)
        root.anchorOffset = Math.Vector2(
            rest_offset.x + dx + (fx - 0.5) * grow_x,
            rest_offset.y + dy + (fy - 0.5) * grow_y,
        )
    end

    """Shake, play the click SFX and fly off. Returns false if already leaving (ignore repeat clicks)."""
    function click!(id::String; on_left::Union{Function, Nothing} = nothing, sfx::Bool = true)::Bool
        s = _state(id)
        s.leave_time >= 0 && return false
        s.leave_time = 0.0
        s.last_time = time()
        s.on_left = on_left
        _start_shake!(s, CLICK_SHAKE_DURATION, CLICK_SHAKE_AMOUNT)
        sfx && _play_click_sfx()
        return true
    end
end
