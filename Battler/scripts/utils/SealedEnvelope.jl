module SealedEnvelopeModule
    using JulGame

    # Sealed Envelope treasure: while capturing, match intents are stored instead of resolved.
    # A later activation releases every stored intent at once without spending a move.
    const TREASURE_KEY = "TREASURE_SEALEDENVELOPE"

    const STATE = (
        capturing = Ref(false),
        sealed_this_battle = Ref(false),
        stored = Tuple{String, Int}[],
    )

    const TURN_OVER_STATES = (:playerAction, :enemyTurn, :animatingIntents, :battleEnd)

    is_capturing()::Bool = STATE.capturing[]
    stored_count()::Int = length(STATE.stored)

    # --- Fly-in FX (screen space): captured pieces fly into the envelope icon, which shakes per arrival ---
    const FLY_DURATION = 0.45
    const FLY_STAGGER = 0.08
    const FLY_LIFT = 140.0
    const FLYER_SIZE = 44.0
    const FLYER_END_SCALE = 0.4
    const MAX_FLYERS_PER_INTENT = 5
    const SHAKE_DURATION = 0.25
    const SHAKE_AMPLITUDE = 6.0
    const SHAKE_HZ = 22.0
    const SHAKE_ROTATION = 12.0
    const FX_LAYER = 25
    const FX_LIFETIME_MS = 100

    mutable struct Flyer
        uid::Int
        icon::String
        delay::Float64
        elapsed::Float64
        from_x::Float64
        from_y::Float64
    end

    const FX = (
        flyers = Flyer[],
        next_uid = Ref(1),
        target = Ref((80.0, 640.0)),  # screen centre of the envelope icon, set by the ability display
        shake_left = Ref(0.0),
    )

    """Start of a battle: nothing carries over between fights."""
    function reset!()
        STATE.capturing[] = false
        STATE.sealed_this_battle[] = false
        empty!(STATE.stored)
        empty!(FX.flyers)
        FX.shake_left[] = 0.0
    end

    """
    Called from the match pipeline. Returns true when the intent was stored and must not resolve now.
    `entities` (the matched pieces) only positions the fly-in FX.
    """
    function capture_intents!(intent::AbstractString, count::Integer, entities = nothing)::Bool
        STATE.capturing[] || return false
        key = String(intent)
        # One cumulative entry per intent (first-seen order), released as a single intent.
        i = findfirst(e -> first(e) == key, STATE.stored)
        if i === nothing
            push!(STATE.stored, (key, Int(count)))
        else
            STATE.stored[i] = (key, last(STATE.stored[i]) + Int(count))
        end
        _spawn_flyers!(key, Int(count), entities)
        return true
    end

    """
    The player's turn is over (no moves left / enemy turn starting): stop capturing so the envelope stays
    dormant until released, and drop fly-ins that have not launched yet so none arrive during the next turn.
    """
    function end_turn!()
        STATE.capturing[] = false
        filter!(f -> f.delay <= 0.0, FX.flyers)
        return nothing
    end

    function _screen_size()
        cam = MAIN.scene.camera
        cam === nothing && return (1280.0, 720.0)
        return (Float64(cam.size.x), Float64(cam.size.y))
    end

    function _world_to_screen(wx::Float64, wy::Float64)
        cam = MAIN.scene.camera
        if cam === nothing
            W, H = _screen_size()
            return (W / 2.0, H / 2.0)
        end
        S = Float64(JulGame.pixels_per_world_unit(cam))
        return ((wx - (Float64(cam.position.x) + Float64(cam.offset.x))) * S,
                (wy - (Float64(cam.position.y) + Float64(cam.offset.y))) * S)
    end

    function _screen_origin(intent::String, entities)
        pts = Tuple{Float64, Float64}[]
        if entities !== nothing
            live = [e for e in entities if e !== nothing]
            matching = [e for e in live if string(e.name) == intent]
            for e in (isempty(matching) ? live : matching)
                p = e.transform.position
                push!(pts, _world_to_screen(Float64(p.x) + 0.5, Float64(p.y) + 0.5))
            end
        end
        if isempty(pts)
            W, H = _screen_size()
            return (W / 2.0, H / 2.0)
        end
        return (sum(first, pts) / length(pts), sum(last, pts) / length(pts))
    end

    function _intent_icon(intent::String)::String
        parts = split(intent, "_")
        return JulGame.UserGlobals["Module"].get_asset_path("piece", lowercase(length(parts) > 1 ? parts[2] : parts[1]))
    end

    function _spawn_flyers!(intent::String, count::Int, entities)
        try
            icon = _intent_icon(intent)
            ox, oy = _screen_origin(intent, entities)
            # Queue behind flyers still waiting so every arrival reads as its own shake.
            base_delay = isempty(FX.flyers) ? 0.0 : maximum(f -> f.delay, FX.flyers) + FLY_STAGGER
            for i in 1:clamp(count, 1, MAX_FLYERS_PER_INTENT)
                push!(FX.flyers, Flyer(FX.next_uid[], icon, max(0.0, base_delay) + (i - 1) * FLY_STAGGER, 0.0,
                    ox + (i - 1) * 6.0, oy - (i - 1) * 4.0))
                FX.next_uid[] += 1
            end
        catch e
            @debug "SealedEnvelope flyers: $e"
        end
    end

    """Screen centre of the envelope icon; the flyers home in on it."""
    set_target!(x::Real, y::Real) = (FX.target[] = (Float64(x), Float64(y)); nothing)

    """(x offset, rotation in degrees) to apply to the envelope icon while it shakes."""
    function shake_offset()
        left = FX.shake_left[]
        left <= 0.0 && return (0.0, 0.0)
        k = left / SHAKE_DURATION
        phase = (SHAKE_DURATION - left) * SHAKE_HZ * 2π
        return (SHAKE_AMPLITUDE * k * sin(phase), SHAKE_ROTATION * k * sin(phase + 0.7))
    end

    function _render_flyer(f::Flyer, t::Float64)
        fx, fy = f.from_x, f.from_y
        tx, ty = FX.target[]
        cx, cy = (fx + tx) / 2.0, min(fy, ty) - FLY_LIFT
        e = t * t * t
        inv = 1.0 - e
        x = inv * inv * fx + 2 * inv * e * cx + e * e * tx
        y = inv * inv * fy + 2 * inv * e * cy + e * e * ty
        size = FLYER_SIZE * (1.0 + (FLYER_END_SCALE - 1.0) * e)
        sz = JulGame.Math.Vector2(size, size)
        img = JulGame.ImmediateUIModule.immediate_image(
            "sealed_envelope_flyer_$(f.uid)",
            f.icon;
            anchor = :none,
            position = JulGame.Math.Vector2(x - size / 2.0, y - size / 2.0),
            size = sz,
            rotation = 360.0 * e,
            layer = FX_LAYER,
            lifetime = FX_LIFETIME_MS,
        )
        if img !== nothing
            img.size = sz
            img.originalSize = sz
        end
    end

    """Advance and draw the fly-in FX. Called every frame by the ability display."""
    function update_fx!(dt::Real)
        dt = Float64(dt)
        FX.shake_left[] = max(0.0, FX.shake_left[] - dt)
        isempty(FX.flyers) && return
        keep = Flyer[]
        for f in FX.flyers
            if f.delay > 0.0
                f.delay -= dt
                push!(keep, f)
                continue
            end
            f.elapsed += dt
            t = min(f.elapsed / FLY_DURATION, 1.0)
            if t >= 1.0
                FX.shake_left[] = SHAKE_DURATION
                continue
            end
            try
                _render_flyer(f, t)
            catch e
                @debug "SealedEnvelope flyer render: $e"
            end
            push!(keep, f)
        end
        empty!(FX.flyers)
        append!(FX.flyers, keep)
    end

    function _is_player_turn(bm)::Bool
        bm !== nothing && bm.currentState == bm.battleStates[:playerTurn]
    end

    function can_activate(bm)::Bool
        _is_player_turn(bm) || return false
        # Stored intents can only be released on a later turn.
        is_capturing() && return false
        stored_count() > 0 && return true
        return !STATE.sealed_this_battle[] && bm.moveCount > 0
    end

    """Allow sealing again this battle (Active Battery)."""
    recharge!() = (STATE.sealed_this_battle[] = false; nothing)

    """
    With stored intents: resolve them all now (no animation queue, so battle state and move count are untouched).
    Empty: capture the rest of this turn's matches.
    """
    function activate!(bm)::Bool
        can_activate(bm) || return false
        if stored_count() > 0
            batch = copy(STATE.stored)
            empty!(STATE.stored)
            battle = parentmodule(@__MODULE__).BattleManagerModule
            for (intent, count) in batch
                battle.apply_single_intent(bm, intent, count)
                bm.currentState == bm.battleStates[:battleEnd] && break
            end
            return true
        end
        STATE.capturing[] = true
        STATE.sealed_this_battle[] = true
        return true
    end

    """Safety net for turn-end paths that skip `end_turn!` (polled every frame)."""
    function note_battle_state!(bm)
        is_capturing() || return
        bm === nothing && return
        for s in TURN_OVER_STATES
            if bm.currentState == bm.battleStates[s]
                end_turn!()
                return
            end
        end
    end

    function _intent_name(key::String)::String
        try
            piece_map = JulGame.UserGlobals["Module"].get_piece_data()
            haskey(piece_map, key) && return String(piece_map[key].name)
        catch
        end
        return key
    end

    function tooltip_text(base::AbstractString)::String
        lines = String[String(base)]
        if !isempty(STATE.stored)
            push!(lines, "Stored:")
            for (intent, count) in STATE.stored
                push!(lines, "{icon:$(_intent_icon(intent))} $(_intent_name(intent)) x$(count)")
            end
        elseif is_capturing()
            push!(lines, "Storing this turn's matches.")
        elseif STATE.sealed_this_battle[]
            push!(lines, "Already used this battle.")
        end
        return join(lines, "\n")
    end

    export capture_intents!, activate!, can_activate, note_battle_state!, is_capturing, stored_count, tooltip_text, reset!,
        set_target!, shake_offset, update_fx!, end_turn!
end
