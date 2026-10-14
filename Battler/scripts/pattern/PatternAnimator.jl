"""
Pattern piece VFX: stripe sweeps, wrapped blasts, color-bomb flashes, create pops.
Destroys can wait on `play_events!(...; on_gate=...)`.
"""
module PatternAnimatorModule
    using JulGame
    using ..PatternKindsModule
    using ..PatternVisualsModule
    export PatternAnimProfile, PATTERN_ANIM_PROFILES
    export PatternAnimClip, PatternAnimatorState, PatternVfxSprite
    export play_events!, update_animator!, is_animator_blocking, get_animator, reset_animator!
    export tick_idle_visual!, clear_idle_state!, anim_profile_symbol
    export set_grid_context!, clear_pattern_vfx!

    const VFX_ENTITY_NAME = "Pattern_VFX"

    struct PatternAnimProfile
        create_duration::Float64
        activate_duration::Float64
        clear_duration::Float64
        idle_pulse_speed::Float64
        create_scale::Float64
        tint::NTuple{4, Int}
        sfx::String
    end

    const PATTERN_ANIM_PROFILES = Dict{Symbol, PatternAnimProfile}(
        :stripe_h => PatternAnimProfile(0.28, 0.2, 0.38, 1.6, 1.3, (255, 230, 120, 255), "sfx-firstmatch"),
        :stripe_v => PatternAnimProfile(0.28, 0.2, 0.38, 1.6, 1.3, (120, 220, 255, 255), "sfx-firstmatch"),
        :wrapped => PatternAnimProfile(0.32, 0.22, 0.42, 1.2, 1.4, (255, 160, 90, 255), "sfx-firstmatch"),
        :colorbomb => PatternAnimProfile(0.36, 0.25, 0.48, 1.8, 1.45, (230, 140, 255, 255), "sfx-firstmatch"),
        :combo => PatternAnimProfile(0.34, 0.26, 0.45, 1.4, 1.5, (255, 255, 200, 255), "sfx-firstmatch"),
        :pattern_none => PatternAnimProfile(0.12, 0.1, 0.12, 1.0, 1.0, (255, 255, 255, 255), ""),
    )

    mutable struct PatternVfxSprite
        entity::Any
        elapsed::Float64
        duration::Float64
        delay::Float64
        start_scale::Float64
        end_scale::Float64
        start_alpha::Int
        end_alpha::Int
        base_tint::NTuple{4, Int}
        cell_w::Float64
        cell_h::Float64
        # Optional piece pop (scales an existing board piece, not a VFX entity)
        target_piece::Any
    end

    _set_render_scale!(ent, s) = (ent.sprite.renderScale = Math.Vector2f(s, s))

    mutable struct PatternAnimClip
        event_kind::Symbol
        profile::Symbol
        elapsed::Float64
        duration::Float64
        cell::Union{Nothing, PatternCell}
        cells::Vector{PatternCell}
        gate_released::Bool
        on_gate::Union{Nothing, Function}
        spawned::Bool
    end

    mutable struct PatternAnimatorState
        clips::Vector{PatternAnimClip}
        vfx::Vector{PatternVfxSprite}
        idle_time::Float64
        blocking::Bool
        grid_start_x::Float64
        grid_start_y::Float64
        cell_w::Float64
        cell_h::Float64
        grid_pieces::Any
    end

    function PatternAnimatorState()
        PatternAnimatorState(PatternAnimClip[], PatternVfxSprite[], 0.0, false, 0.0, 0.0, 1.0, 1.0, nothing)
    end

    const GLOBAL_ANIMATOR = Ref{PatternAnimatorState}(PatternAnimatorState())

    function get_animator()::PatternAnimatorState
        return GLOBAL_ANIMATOR[]
    end

    function reset_animator!()
        clear_pattern_vfx!()
        GLOBAL_ANIMATOR[] = PatternAnimatorState()
    end

    function set_grid_context!(; start_x::Float64, start_y::Float64, cell_w::Float64, cell_h::Float64, grid_pieces = nothing)
        st = get_animator()
        st.grid_start_x = start_x
        st.grid_start_y = start_y
        st.cell_w = cell_w
        st.cell_h = cell_h
        st.grid_pieces = grid_pieces
    end

    function _profile(sym::Symbol)::PatternAnimProfile
        return get(PATTERN_ANIM_PROFILES, sym, PATTERN_ANIM_PROFILES[:pattern_none])
    end

    function _duration_for(event_kind::Symbol, profile::Symbol)::Float64
        p = _profile(profile)
        event_kind == :pattern_create && return p.create_duration
        event_kind == :pattern_activate && return p.activate_duration
        event_kind == :pattern_clear_sweep && return p.clear_duration
        event_kind == :pattern_second_blast && return p.clear_duration
        event_kind == :pattern_combo && return p.activate_duration
        return 0.12
    end

    function cell_world(st::PatternAnimatorState, cell::PatternCell)
        x = (cell[1] - 1) * st.cell_w + st.grid_start_x
        y = (cell[2] - 1) * st.cell_h + st.grid_start_y
        return (x, y)
    end

    function _spawn_highlight(st::PatternAnimatorState, cell::PatternCell, tint::NTuple{4, Int},
        duration::Float64, delay::Float64;
        start_scale::Float64 = 0.35, end_scale::Float64 = 1.15,
        start_alpha::Int = 220, end_alpha::Int = 0)

        crop = Math.Vector4(0, 0, 0, 0)
        ent = JulGame.EntityModule.Entity(VFX_ENTITY_NAME)
        ent.sprite = JulGame.SpriteModule.InternalSprite(
            ent, "highlight.png", crop, false, tint, false;
            pixelsPerUnit = 150, layer = 5,
        )
        ent = JulGame.create_entity(ent)
        wx, wy = cell_world(st, cell)
        ent.transform.position = Math.Vector2f(wx, wy)
        ent.transform.scale = Math.Vector2f(st.cell_w, st.cell_h)
        _set_render_scale!(ent, start_scale)
        push!(st.vfx, PatternVfxSprite(
            ent, 0.0, duration, delay, start_scale, end_scale, start_alpha, end_alpha, tint,
            st.cell_w, st.cell_h, nothing,
        ))
        return ent
    end

    function clear_pattern_vfx!()
        st = get_animator()
        for v in st.vfx
            try
                if v.target_piece !== nothing
                    _set_render_scale!(v.target_piece, 1.0)
                end
                if v.entity !== nothing
                    JulGame.destroy_entity(MAIN, v.entity)
                end
            catch
            end
        end
        empty!(st.vfx)
        try
            for entity in JulGame.SceneModule.get_entities_by_name(MAIN.scene, VFX_ENTITY_NAME)
                JulGame.destroy_entity(MAIN, entity)
            end
        catch
        end
    end

    function play_events!(events::Vector{PatternEvent}; on_gate::Union{Nothing, Function} = nothing)
        state = get_animator()
        if isempty(events)
            on_gate !== nothing && on_gate()
            return
        end

        max_dur = 0.0
        for ev in events
            dur = _duration_for(ev.kind, ev.profile)
            max_dur = max(max_dur, dur)
            push!(state.clips, PatternAnimClip(
                ev.kind, ev.profile, 0.0, dur, ev.cell, copy(ev.cells), false, nothing, false,
            ))
            # Match/clear SFX is owned by ComboResponder (combo-tiered). Playing
            # profile SFX here stomped channel 1 with sfx-firstmatch every event.
        end
        if on_gate !== nothing
            push!(state.clips, PatternAnimClip(
                :pattern_gate, :pattern_none, 0.0, max(max_dur, 0.05), nothing, PatternCell[], false, on_gate, true,
            ))
            state.blocking = true
        end
    end

    function _spawn_clip_vfx!(st::PatternAnimatorState, clip::PatternAnimClip)
        clip.spawned = true
        p = _profile(clip.profile)
        tint = p.tint

        if clip.event_kind == :pattern_create
            _spawn_create_vfx!(st, clip, p, tint)
        elseif clip.event_kind == :pattern_clear_sweep || clip.event_kind == :pattern_activate
            if clip.profile == :stripe_h || clip.profile == :stripe_v
                _spawn_stripe_sweep!(st, clip, tint)
            elseif clip.profile == :wrapped || clip.event_kind == :pattern_activate && clip.profile == :wrapped
                _spawn_radial_blast!(st, clip, tint)
            elseif clip.profile == :colorbomb
                _spawn_type_flash!(st, clip, tint)
            else
                _spawn_radial_blast!(st, clip, tint)
            end
        elseif clip.event_kind == :pattern_second_blast
            _spawn_radial_blast!(st, clip, tint; stronger = true)
        elseif clip.event_kind == :pattern_combo
            _spawn_combo_vfx!(st, clip, tint)
        end
    end

    function _spawn_create_vfx!(st::PatternAnimatorState, clip::PatternAnimClip, p::PatternAnimProfile, tint::NTuple{4, Int})
        # Flash matched cells, then pop the anchor.
        origin = clip.cell
        for cell in clip.cells
            dist = origin === nothing ? 0.0 : Float64(abs(cell[1] - origin[1]) + abs(cell[2] - origin[2]))
            delay = min(0.12, dist * 0.03)
            _spawn_highlight(st, cell, tint, clip.duration * 0.7, delay;
                start_scale = 0.9, end_scale = 0.2, start_alpha = 180, end_alpha = 0)
        end
        if origin !== nothing
            _spawn_highlight(st, origin, tint, clip.duration, 0.05;
                start_scale = 0.5, end_scale = 1.35, start_alpha = 255, end_alpha = 40)
            # Scale-pop the actual piece if present
            if st.grid_pieces !== nothing
                try
                    ent = st.grid_pieces[origin[1], origin[2]]
                    if ent !== nothing
                        push!(st.vfx, PatternVfxSprite(
                            nothing, 0.0, clip.duration, 0.0, 1.0, p.create_scale, 255, 255, tint,
                            st.cell_w, st.cell_h, ent,
                        ))
                    end
                catch
                end
            end
        end
    end

    function _spawn_stripe_sweep!(st::PatternAnimatorState, clip::PatternAnimClip, tint::NTuple{4, Int})
        cells = clip.cells
        isempty(cells) && return
        origin = clip.cell
        horizontal = clip.profile == :stripe_h

        # Order cells along the sweep axis away from origin (or left→right / top→bottom).
        sorted = copy(cells)
        if origin !== nothing
            sort!(sorted, by = c -> horizontal ? abs(c[1] - origin[1]) : abs(c[2] - origin[2]))
        else
            sort!(sorted, by = c -> horizontal ? c[1] : c[2])
        end

        n = max(1, length(sorted))
        for (i, cell) in enumerate(sorted)
            delay = ((i - 1) / n) * (clip.duration * 0.65)
            _spawn_highlight(st, cell, tint, clip.duration * 0.45, delay;
                start_scale = 0.4, end_scale = 1.2, start_alpha = 240, end_alpha = 0)
        end
    end

    function _spawn_radial_blast!(st::PatternAnimatorState, clip::PatternAnimClip, tint::NTuple{4, Int}; stronger::Bool = false)
        origin = clip.cell
        cells = clip.cells
        isempty(cells) && return
        ox, oy = origin === nothing ? cells[1] : origin
        for cell in cells
            dist = Float64(max(abs(cell[1] - ox), abs(cell[2] - oy)))  # chebyshev
            delay = dist * (stronger ? 0.06 : 0.05)
            peak = stronger ? 1.45 : 1.25
            _spawn_highlight(st, cell, tint, clip.duration * 0.55, delay;
                start_scale = 0.25, end_scale = peak, start_alpha = 255, end_alpha = 0)
        end
        # Center punch
        _spawn_highlight(st, (ox, oy), (255, 255, 255, 255), clip.duration * 0.35, 0.0;
            start_scale = 0.6, end_scale = stronger ? 1.8 : 1.5, start_alpha = 255, end_alpha = 0)
    end

    function _spawn_type_flash!(st::PatternAnimatorState, clip::PatternAnimClip, tint::NTuple{4, Int})
        cells = clip.cells
        for (i, cell) in enumerate(cells)
            delay = ((i - 1) % 7) * 0.02
            _spawn_highlight(st, cell, tint, clip.duration * 0.5, delay;
                start_scale = 0.7, end_scale = 1.3, start_alpha = 230, end_alpha = 0)
        end
    end

    function _spawn_combo_vfx!(st::PatternAnimatorState, clip::PatternAnimClip, tint::NTuple{4, Int})
        # Big flash on all cells + center burst
        _spawn_type_flash!(st, clip, tint)
        if clip.cell !== nothing
            _spawn_highlight(st, clip.cell, (255, 255, 255, 255), clip.duration, 0.0;
                start_scale = 0.5, end_scale = 1.7, start_alpha = 255, end_alpha = 0)
        end
    end

    function is_animator_blocking()::Bool
        return get_animator().blocking
    end

    function _ease_out_cubic(t::Float64)::Float64
        u = 1.0 - t
        return 1.0 - u * u * u
    end

    function update_animator!(deltaTime::Float64)
        state = get_animator()
        state.idle_time += deltaTime

        speed = 1.0
        try
            speed = JulGame.UserGlobals["Module"].get_data_manager().game_speed_multiplier
        catch
        end
        dt = deltaTime * speed

        # Spawn VFX for new clips
        for clip in state.clips
            if !clip.spawned && clip.event_kind != :pattern_gate
                _spawn_clip_vfx!(state, clip)
            elseif clip.event_kind == :pattern_gate
                clip.spawned = true
            end
        end

        # Update VFX sprites
        keep_vfx = PatternVfxSprite[]
        for v in state.vfx
            if v.delay > 0
                v.delay -= dt
                if v.delay > 0
                    # Keep hidden until delay elapses
                    if v.entity !== nothing
                        try
                            v.entity.sprite.color = (v.base_tint[1], v.base_tint[2], v.base_tint[3], 0)
                        catch
                        end
                    end
                    push!(keep_vfx, v)
                    continue
                end
                v.elapsed = 0.0
            end
            v.elapsed += dt
            t = clamp(v.elapsed / max(0.001, v.duration), 0.0, 1.0)
            eased = _ease_out_cubic(t)
            scale = v.start_scale + (v.end_scale - v.start_scale) * eased
            alpha = round(Int, v.start_alpha + (v.end_alpha - v.start_alpha) * t)

            if v.target_piece !== nothing
                try
                    # Pop then settle back
                    pop_t = t < 0.45 ? (t / 0.45) : (1.0 - (t - 0.45) / 0.55)
                    _set_render_scale!(v.target_piece, 1.0 + (v.end_scale - 1.0) * sin(pop_t * π))
                catch
                end
            end

            if v.entity !== nothing
                try
                    _set_render_scale!(v.entity, scale)
                    v.entity.sprite.color = (
                        v.base_tint[1], v.base_tint[2], v.base_tint[3], clamp(alpha, 0, 255),
                    )
                catch
                end
            end

            if t < 1.0
                push!(keep_vfx, v)
            else
                try
                    if v.target_piece !== nothing
                        _set_render_scale!(v.target_piece, 1.0)
                    end
                    if v.entity !== nothing
                        JulGame.destroy_entity(MAIN, v.entity)
                    end
                catch
                end
            end
        end
        state.vfx = keep_vfx

        # Advance clips / gates
        isempty(state.clips) && (state.blocking = false; return)

        keep = PatternAnimClip[]
        still_blocking = false
        for clip in state.clips
            clip.elapsed += dt
            if clip.elapsed >= clip.duration
                if !clip.gate_released && clip.on_gate !== nothing
                    clip.gate_released = true
                    try
                        clip.on_gate()
                    catch e
                        @debug "pattern anim gate: $e"
                    end
                end
            else
                push!(keep, clip)
                if clip.on_gate !== nothing
                    still_blocking = true
                end
            end
        end
        state.clips = keep
        state.blocking = still_blocking
    end

    function tick_idle_visual!(entity, kind::PatternKind, idle_time::Float64)
        !is_patterned(kind) && return
        entity === nothing && return
        try
            entity.sprite === nothing && return
            p = _profile(anim_profile_symbol(kind))
            pulse = 0.85 + 0.15 * (0.5 + 0.5 * sin(idle_time * p.idle_pulse_speed * 2π))
            base = pattern_tint(kind)
            entity.sprite.color = (
                clamp(round(Int, base[1] * pulse), 0, 255),
                clamp(round(Int, base[2] * pulse), 0, 255),
                clamp(round(Int, base[3] * pulse), 0, 255),
                255,
            )
        catch
        end
    end

    function anim_profile_symbol(kind::PatternKind)::Symbol
        kind == PATTERN_STRIPE_H && return :stripe_h
        kind == PATTERN_STRIPE_V && return :stripe_v
        kind == PATTERN_WRAPPED && return :wrapped
        kind == PATTERN_COLORBOMB && return :colorbomb
        return :pattern_none
    end

    function clear_idle_state!()
        get_animator().idle_time = 0.0
    end
end
