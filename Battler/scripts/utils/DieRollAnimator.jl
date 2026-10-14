"""
Die match presentation: hop + rolling frames, then a landed face with a number.
"""
module DieRollAnimatorModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule

    export play_clusters!, update_animator!, is_blocking, owns, reset_animator!
    export die_roll_range, roll_die_face, is_die_piece

    const ROLL_FRAMES = (
        "pieceanim-dieroll1",
        "pieceanim-dieroll2",
        "pieceanim-dieroll3",
    )
    const LAND_FRAME = "pieceanim-dieroll4"
    const FRAME_INTERVAL = 0.06
    const ROLL_DURATION = 0.72
    const LAND_HOLD = 0.55
    const MAX_DT = 1 / 30
    const HOP_FRAC = 0.45
    const WOBBLE_FRAC = 0.22
    const FACE_FONT = 36
    const RENDER_LIFETIME_MS = 80

    mutable struct DieClip
        entities::Vector{Any}
        face::Int
        lo::Int
        hi::Int
        base_x::Vector{Float64}
        base_y::Vector{Float64}
        base_sx::Vector{Float64}
        base_sy::Vector{Float64}
        base_rot::Vector{Float64}
        elapsed::Float64
        landed::Bool
        result_sfx_played::Bool
    end

    mutable struct DieRollState
        clips::Vector{DieClip}
        cell_h::Float64
        blocking::Bool
        sfx_started::Bool
        on_complete::Union{Nothing, Function}
    end

    const STATE = DieRollState(DieClip[], 1.0, false, false, nothing)

    function is_die_piece(key)::Bool
        k = uppercase(strip(string(key)))
        return k == "PIECE_DIE"
    end

    function die_roll_range(action_count::Int)::Tuple{Int, Int}
        lo = max(1, Int(action_count))
        return lo, lo + 5
    end

    function roll_die_face(action_count::Int)::Int
        lo, hi = die_roll_range(action_count)
        return rand(lo:hi)
    end

    function is_blocking()::Bool
        return STATE.blocking
    end

    function owns(entity)::Bool
        STATE.blocking || return false
        for clip in STATE.clips
            for e in clip.entities
                e === entity && return true
            end
        end
        return false
    end

    function reset_animator!()
        STATE.clips = DieClip[]
        STATE.blocking = false
        STATE.sfx_started = false
        STATE.on_complete = nothing
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
            @debug "die sfx: $e"
        end
    end

    function _snapshot_bases(entities)
        xs = Float64[]
        ys = Float64[]
        sxs = Float64[]
        sys = Float64[]
        rots = Float64[]
        for e in entities
            p = e.transform.position
            s = e.transform.scale
            push!(xs, Float64(p.x))
            push!(ys, Float64(p.y))
            push!(sxs, Float64(s.x))
            push!(sys, Float64(s.y))
            rot = 0.0
            try
                spr = e.sprite
                if spr !== nothing
                    rot = Float64(spr.rotation)
                end
            catch
            end
            push!(rots, rot)
        end
        return xs, ys, sxs, sys, rots
    end

    """
    `clusters` is a vector of NamedTuples: `(entities, face, lo, hi)`.
    """
    function play_clusters!(clusters; cell_h::Float64 = 1.0, on_complete = nothing)
        reset_animator!()
        isempty(clusters) && return
        STATE.cell_h = cell_h
        STATE.on_complete = on_complete
        for cluster in clusters
            ents = [e for e in cluster.entities if e !== nothing]
            isempty(ents) && continue
            xs, ys, sxs, sys, rots = _snapshot_bases(ents)
            push!(STATE.clips, DieClip(
                ents,
                Int(cluster.face),
                Int(cluster.lo),
                Int(cluster.hi),
                xs, ys, sxs, sys, rots,
                0.0,
                false,
                false,
            ))
        end
        isempty(STATE.clips) && return
        STATE.blocking = true
        _sfx("piecedicerollingloop")
        STATE.sfx_started = true
    end

    function _set_frame!(entity, path::String)
        spr = entity.sprite
        spr === nothing && return
        try
            String(spr.imagePath) == path && return
            spr.imagePath = path
        catch e
            @debug "die frame: $e"
        end
    end

    function _pose!(entity, x, y, sx, sy, rot)
        try
            entity.transform.position = Math.Vector2f(x, y)
            entity.transform.scale = Math.Vector2f(sx, sy)
        catch e
            @debug "die pose: $e"
        end
        spr = entity.sprite
        spr === nothing && return
        try
            spr.rotation = rot
        catch
        end
    end

    function _draw_face_number(entity, i::Int, text::String)
        spr = entity.sprite
        parent = spr !== nothing ? spr : entity
        try
            DisplayTextModule.display_text(
                "die_face_$(objectid(entity))_$(i)",
                text;
                parent = parent,
                anchor = :center,
                fontSize = FACE_FONT,
                color = (40, 32, 28, 255),
                layer = 14,
                lifetime = RENDER_LIFETIME_MS,
            )
        catch e
            @debug "die face text: $e"
        end
    end

    function _tick_clip!(clip::DieClip, dt::Float64, cell_h::Float64)
        clip.elapsed += dt
        rolling = clip.elapsed < ROLL_DURATION
        if rolling
            t = clamp(clip.elapsed / ROLL_DURATION, 0.0, 1.0)
            frame_i = mod(floor(Int, clip.elapsed / FRAME_INTERVAL), length(ROLL_FRAMES)) + 1
            for (i, e) in enumerate(clip.entities)
                e === nothing && continue
                phase = (i - 1) * 2.1
                hop = abs(sin(t * 3 * π)) * cell_h * HOP_FRAC
                wobble = sin(clip.elapsed * 16 + phase) * cell_h * WOBBLE_FRAC
                stretch = 1.0 + 0.14 * sin(t * 3 * π)
                squash = 1.0 - 0.12 * sin(t * 3 * π)
                rot = clip.base_rot[i] + sin(clip.elapsed * 20 + phase) * 0.18
                try
                    _set_frame!(e, JulGame.UserGlobals["Module"].get_asset_path(ROLL_FRAMES[frame_i]))
                    _pose!(e, clip.base_x[i] + wobble, clip.base_y[i] - hop, clip.base_sx[i] * squash, clip.base_sy[i] * stretch, rot)
                catch e2
                    @debug "die roll pose: $e2"
                end
            end
            return
        end

        if !clip.landed
            clip.landed = true
        end
        if !clip.result_sfx_played
            _sfx("piecediceresult$(rand(1:3))")
            clip.result_sfx_played = true
        end

        land_t = clamp((clip.elapsed - ROLL_DURATION) / 0.12, 0.0, 1.0)
        squash = 0.78 + 0.22 * land_t
        stretch = 1.18 - 0.18 * land_t
        for (i, e) in enumerate(clip.entities)
            e === nothing && continue
            try
                _set_frame!(e, JulGame.UserGlobals["Module"].get_asset_path(LAND_FRAME))
                _pose!(e, clip.base_x[i], clip.base_y[i], clip.base_sx[i] * stretch, clip.base_sy[i] * squash, clip.base_rot[i])
            catch e2
                @debug "die land pose: $e2"
            end
            _draw_face_number(e, i, string(clip.face))
        end
    end

    function update_animator!(deltaTime::Float64)
        STATE.blocking || return
        sp = 1.0
        try
            sp = clamp(Float64(JulGame.UserGlobals["Module"].get_data_manager().game_speed_multiplier), 0.15, 6.0)
        catch
        end
        dt = min(max(deltaTime, 0.0) * sp, MAX_DT)
        done = true
        for clip in STATE.clips
            try
                _tick_clip!(clip, dt, STATE.cell_h)
            catch e
                @debug "die clip tick: $e"
            end
            if clip.elapsed < ROLL_DURATION + LAND_HOLD
                done = false
            end
        end
        done || return
        cb = STATE.on_complete
        reset_animator!()
        if cb !== nothing
            try
                cb()
            catch e
                @debug "die on_complete: $e"
            end
        end
    end
end
