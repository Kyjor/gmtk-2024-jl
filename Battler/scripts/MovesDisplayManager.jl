module MovesDisplayManagerModule
    using JulGame
    using JulGame.EffectsModule
    using ..GridControllerModule
    include("utils/Easings.jl")
    include("utils/Constants.jl")

    const MAX_VISIBLE_PIPS = 4
    # ~44px bars at ppu=0 scale to ~0.69 world units; keep a small gap between centers
    const PIP_SPACING = 0.9f0
    const CENTER_X = 4.5f0
    const CENTER_Y = -3.2f0
    const LAYOUT_LERP_SPEED = 18.0
    const SHAKE_INTENSITY = 0.04f0
    const SHAKE_FREQUENCY = 18.0

    const ENTITY_IDS = (
        "ec10dfa5-7fba-4d32-9410-33d3552a1e7e",
        "1622c504-9abe-482f-9783-c7116381d79f",
        "96e883a1-58aa-4fb4-95b8-1ef8c2ed4fae",
    )
    const MOVES_TEXT_ID = "c8eee6e3-022f-435b-bd27-3e9ec9fe2a1a"

    mutable struct MovesDisplayManager <: Script
        parent
        pipEntities::Vector{Any}
        battleManager
        gridController
        movesText

        previousMoveCount::Int
        shakeTime::Float64
        layoutProgress::Float64
        layoutFromCount::Int
        layoutToCount::Int
        basePositions::Vector{Math.Vector2f}
        recoveredDuringResolve::Bool

        function MovesDisplayManager()
            this = new()
            this.pipEntities = Any[]
            this.battleManager = nothing
            this.gridController = nothing
            this.movesText = nothing
            this.previousMoveCount = 3
            this.shakeTime = 0.0
            this.layoutProgress = 1.0
            this.layoutFromCount = 3
            this.layoutToCount = 3
            this.basePositions = Math.Vector2f[]
            this.recoveredDuringResolve = false
            return this
        end
    end

    function _asset(style_n::Int, state::String)::String
        return JulGame.UserGlobals["Module"].get_asset_path("movecounter", "$(style_n)$(state)")
    end

    function _is_resolving(bm)::Bool
        states = bm.battleStates
        return bm.currentState == states[:switchingItems] ||
               bm.currentState == states[:searchingForMatches] ||
               bm.currentState == states[:replaceItems] ||
               bm.currentState == states[:processTurn]
    end

    function _can_act(this::MovesDisplayManager)::Bool
        bm = this.battleManager
        bm === nothing && return false
        bm.currentState != bm.battleStates[:playerTurn] && return false
        gc = this.gridController
        if gc !== nothing
            try
                return are_grid_pieces_reset(gc)
            catch
                return true
            end
        end
        return true
    end

    function _visible_count(move_count::Int)::Int
        return clamp(move_count, 0, MAX_VISIBLE_PIPS)
    end

    function _style_n(move_count::Int)::Int
        move_count <= 0 && return 1
        return move_count >= MAX_VISIBLE_PIPS ? MAX_VISIBLE_PIPS : move_count
    end

    function _centered_xs(count::Int)::Vector{Float32}
        count <= 0 && return Float32[]
        xs = Float32[]
        start_x = CENTER_X - (count - 1) * PIP_SPACING / 2.0f0
        for i in 0:(count - 1)
            push!(xs, start_x + i * PIP_SPACING)
        end
        return xs
    end

    function _ensure_fourth_pip!(this::MovesDisplayManager)
        length(this.pipEntities) >= MAX_VISIBLE_PIPS && return
        template = this.pipEntities[1]
        template === nothing && return
        try
            clone = JulGame.EntityModule.Entity("MovesLeft4")
            clone.transform.position = Math.Vector2f(CENTER_X, CENTER_Y)
            clone.isActive = false
            clone.sprite = JulGame.SpriteModule.InternalSprite(
                clone,
                _asset(4, "active"),
                C_NULL,
                false,
                (255, 255, 255, 255),
                false;
                pixelsPerUnit = 0,
                layer = template.sprite.layer,
            )
            JulGame.Component.initialize(clone.sprite)
            clone = JulGame.create_entity(clone)
            push!(this.pipEntities, clone)
            push!(this.basePositions, Math.Vector2f(CENTER_X, CENTER_Y))
        catch e
            @error "MovesDisplayManager: failed to create 4th pip: $e"
        end
    end

    function _start_layout_anim!(this::MovesDisplayManager, from_count::Int, to_count::Int)
        from_count == to_count && return
        this.layoutFromCount = max(from_count, 1)
        this.layoutToCount = max(to_count, 0)
        this.layoutProgress = 0.0
    end

    function JulGame.initialize(this::MovesDisplayManager)
        this.pipEntities = Any[]
        this.basePositions = Math.Vector2f[]
        for id in ENTITY_IDS
            entity = JulGame.SceneModule.get_entity_by_id(id)
            push!(this.pipEntities, entity)
            if entity !== nothing
                push!(this.basePositions, Math.Vector2f(entity.transform.position.x, entity.transform.position.y))
                entity.sprite.color = (255, 255, 255, 255)
            else
                push!(this.basePositions, Math.Vector2f(CENTER_X, CENTER_Y))
            end
        end
        _ensure_fourth_pip!(this)

        this.battleManager = this.parent.scripts[4]
        this.gridController = this.parent.scripts[3]
        this.movesText = JulGame.SceneModule.get_ui_element_by_id(MOVES_TEXT_ID)
        if this.movesText !== nothing
            JulGame.apply_effects!(this.movesText, BATTLE_NUMBER_TEXT_EFFECTS)
        end
        this.previousMoveCount = this.battleManager.moveCount
        this.layoutFromCount = _visible_count(this.previousMoveCount)
        this.layoutToCount = this.layoutFromCount
        this.layoutProgress = 1.0
        this.recoveredDuringResolve = false
    end

    function JulGame.update(this::MovesDisplayManager, deltaTime)
        bm = this.battleManager
        bm === nothing && return
        isempty(this.pipEntities) && return

        move_count = bm.moveCount
        resolving = _is_resolving(bm)
        can_act = _can_act(this)

        if resolving && move_count > this.previousMoveCount
            this.recoveredDuringResolve = true
        elseif !resolving
            this.recoveredDuringResolve = false
        end

        prev_visible = _visible_count(this.previousMoveCount)
        visible = _visible_count(move_count)
        if visible != prev_visible
            _start_layout_anim!(this, prev_visible, visible)
        end
        this.previousMoveCount = move_count

        this.layoutProgress = min(1.0, this.layoutProgress + deltaTime * LAYOUT_LERP_SPEED)
        ease_t = ease_out_expo(this.layoutProgress)
        from_xs = _centered_xs(max(this.layoutFromCount, 1))
        to_xs = _centered_xs(max(visible, 1))

        this.shakeTime += deltaTime
        style = _style_n(move_count)
        current_pip_index = visible

        for (i, entity) in enumerate(this.pipEntities)
            entity === nothing && continue
            if i > visible
                entity.isActive = false
                continue
            end
            entity.isActive = true

            from_x = i <= length(from_xs) ? from_xs[i] : (isempty(from_xs) ? CENTER_X : from_xs[end])
            to_x = i <= length(to_xs) ? to_xs[i] : CENTER_X
            base_x = from_x + (to_x - from_x) * Float32(ease_t)
            base_y = CENTER_Y
            this.basePositions[i] = Math.Vector2f(base_x, base_y)

            is_current = i == current_pip_index
            state = "active"
            shake_x = 0.0f0
            if resolving && is_current && !this.recoveredDuringResolve
                state = "half"
                shake_x = Float32(sin(this.shakeTime * SHAKE_FREQUENCY * 2π) * SHAKE_INTENSITY)
            elseif can_act && is_current && visible > 0
                state = "highlighted"
            end

            desired_path = _asset(style, state)
            if entity.sprite.imagePath != desired_path
                entity.sprite.imagePath = desired_path
            end
            entity.sprite.color = (255, 255, 255, 255)
            entity.transform.position = Math.Vector2f(base_x + shake_x, base_y)
        end

        if this.movesText !== nothing
            shown = max(0, move_count)
            if shown > MAX_VISIBLE_PIPS
                this.movesText.text = "+$(shown - MAX_VISIBLE_PIPS)"
            elseif shown == 1
                this.movesText.text = "1 move left"
            else
                this.movesText.text = "$(shown) moves left"
            end
        end
    end

    function JulGame.on_shutdown(this::MovesDisplayManager)
    end
end
