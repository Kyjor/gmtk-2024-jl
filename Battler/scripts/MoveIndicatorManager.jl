module MoveIndicatorManagerModule
    using JulGame
    using ..Scripts

    mutable struct MoveIndicator
        entity::Union{Nothing, Any}
        gridPosition::Math.Vector2f
        isHighlighted::Bool
    end

    mutable struct MoveIndicatorManager
        parent

        indicatorPool::Vector{MoveIndicator}
        activeIndicators::Vector{MoveIndicator}

        availableImage::String
        indicatorScale::Math.Vector2f

        gridController

        availableColor::NTuple{4, Int}
        highlightedColor::NTuple{4, Int}

        function MoveIndicatorManager()
            this = new()

            this.indicatorPool = MoveIndicator[]
            this.activeIndicators = MoveIndicator[]

            # Same square tile asset as detonator / hocus-pocus overlays
            this.availableImage = "highlight.png"
            this.indicatorScale = Math.Vector2f(1.0, 1.0)

            # Solid gray available cells; brighter hover target
            this.availableColor = (120, 120, 120, 255)
            this.highlightedColor = (220, 220, 220, 255)

            return this
        end
    end

    function JulGame.initialize(this::MoveIndicatorManager)
        if this.parent === nothing
            @error "MoveIndicatorManager: parent is not set"
            return
        end

        this.gridController = this.parent.scripts[3]
        if this.gridController === nothing
            @error "MoveIndicatorManager: gridController is nothing"
            return
        end

        this.indicatorScale = Math.Vector2f(
            this.gridController.gridCellWidth,
            this.gridController.gridCellHeight,
        )
    end

    function JulGame.update(this::MoveIndicatorManager, deltaTime)
    end

    function JulGame.on_shutdown(this::MoveIndicatorManager)
        clear_all_indicators(this)
    end

    function show_available_moves(this::MoveIndicatorManager, possibleMoves::Vector{Math.Vector2f})
        if this.gridController === nothing
            @warn "MoveIndicatorManager: gridController is not initialized"
            return this.activeIndicators
        end

        hide_all_indicators(this)

        for gridPos in possibleMoves
            if gridPos.x < 1 || gridPos.x > this.gridController.gridWidth ||
               gridPos.y < 1 || gridPos.y > this.gridController.gridHeight
                continue
            end

            indicator = get_or_create_indicator(this, gridPos)
            if indicator.entity === nothing
                continue
            end

            indicator.isHighlighted = false
            update_indicator_visual(this, indicator, false)
            indicator.entity.isActive = true
            push!(this.activeIndicators, indicator)
        end

        return this.activeIndicators
    end

    function highlight_move(this::MoveIndicatorManager, targetGridPos::Math.Vector2f)
        tx = Int(targetGridPos.x)
        ty = Int(targetGridPos.y)
        for indicator in this.activeIndicators
            shouldHighlight = Int(indicator.gridPosition.x) == tx && Int(indicator.gridPosition.y) == ty
            if indicator.isHighlighted != shouldHighlight
                indicator.isHighlighted = shouldHighlight
                update_indicator_visual(this, indicator, shouldHighlight)
            end
        end
    end

    function clear_highlight(this::MoveIndicatorManager)
        for indicator in this.activeIndicators
            if indicator.isHighlighted
                indicator.isHighlighted = false
                update_indicator_visual(this, indicator, false)
            end
        end
    end

    function hide_all_indicators(this::MoveIndicatorManager)
        for indicator in this.activeIndicators
            if indicator.entity !== nothing
                indicator.entity.isActive = false
            end
            indicator.isHighlighted = false
        end
        append!(this.indicatorPool, this.activeIndicators)
        empty!(this.activeIndicators)
    end

    function clear_all_indicators(this::MoveIndicatorManager)
        hide_all_indicators(this)
        for indicator in this.indicatorPool
            if indicator.entity !== nothing
                JulGame.destroy_entity(MAIN, indicator.entity)
            end
        end
        empty!(this.indicatorPool)
    end

    function is_valid_move_target(this::MoveIndicatorManager, gridPos::Math.Vector2f)::Bool
        tx = Int(gridPos.x)
        ty = Int(gridPos.y)
        for indicator in this.activeIndicators
            if Int(indicator.gridPosition.x) == tx && Int(indicator.gridPosition.y) == ty
                return true
            end
        end
        return false
    end

    function get_or_create_indicator(this::MoveIndicatorManager, gridPos::Math.Vector2f)::MoveIndicator
        if !isempty(this.indicatorPool)
            indicator = pop!(this.indicatorPool)
            indicator.gridPosition = gridPos
            position_indicator(this, indicator)
            return indicator
        end

        entity = create_indicator_entity(this, gridPos)
        return MoveIndicator(entity, gridPos, false)
    end

    function create_indicator_entity(this::MoveIndicatorManager, gridPos::Math.Vector2f)
        if this.gridController === nothing
            return nothing
        end

        gx = Int(gridPos.x)
        gy = Int(gridPos.y)
        world_x = Scripts.GridControllerModule.calculate_placement_x(this.gridController, gx)
        world_y = Scripts.GridControllerModule.calculate_placement_y(this.gridController, gy)

        # Match AbilityManager detonator / hocus highlight creation
        crop = Math.Vector4(0, 0, 0, 0)
        entity = JulGame.EntityModule.Entity("MoveIndicator")
        entity.sprite = JulGame.SpriteModule.InternalSprite(
            entity,
            this.availableImage,
            crop,
            false,
            this.availableColor,
            false;
            pixelsPerUnit = 150,
            # Below board pieces (layer 2): the hover square sits behind the gem.
            layer = 1,
        )
        entity = JulGame.create_entity(entity)
        entity.transform.position = Math.Vector2f(world_x, world_y)
        entity.transform.scale = this.indicatorScale
        entity.isActive = false
        return entity
    end

    function position_indicator(this::MoveIndicatorManager, indicator::MoveIndicator)
        if indicator.entity === nothing || this.gridController === nothing
            return
        end
        gx = Int(indicator.gridPosition.x)
        gy = Int(indicator.gridPosition.y)
        world_x = Scripts.GridControllerModule.calculate_placement_x(this.gridController, gx)
        world_y = Scripts.GridControllerModule.calculate_placement_y(this.gridController, gy)
        indicator.entity.transform.position = Math.Vector2f(world_x, world_y)
        indicator.entity.transform.scale = this.indicatorScale
    end

    function update_indicator_visual(this::MoveIndicatorManager, indicator::MoveIndicator, isHighlighted::Bool)
        if indicator.entity === nothing || indicator.entity.sprite === nothing
            return
        end
        # Color only — never swap imagePath (avoids texture reload stalls)
        indicator.entity.sprite.color = isHighlighted ? this.highlightedColor : this.availableColor
    end
end
