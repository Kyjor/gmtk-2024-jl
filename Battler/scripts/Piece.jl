module PieceModule
    using JulGame
    using JulGame.SceneManagement.SceneBuilderModule
    using ..Scripts
    using ..PatternKindsModule
    using ..PatternAnimatorModule
    include("utils/FloatingAnimation.jl")
    using .FloatingAnimationModule

    # Easing functions for smooth animations
    function ease_out_bounce(x::Float64) :: Float64
        n1 = 7.5625
        d1 = 2.75
        
        if x < 1 / d1
            return n1 * x ^ 2
        elseif x < 2 / d1
            return n1 * (x - 1.5 / d1) ^ 2 + 0.75
        elseif x < 2.5 / d1
            return n1 * (x - 2.25 / d1) ^ 2 + 0.9375
        else
            return n1 * (x - 2.625 / d1) ^ 2 + 0.984375
        end
    end

    function ease_out_back(x::Float64) :: Float64
        c1 = 1.70158
        c3 = c1 + 1
        
        return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
    end

    mutable struct Piece
        parent
        battleManager
        gridPosition::Math.Vector2
        gameManager
        gridController
        speed::Float64
        pieceData
        
        # Animation properties
        isAnimating::Bool
        animationProgress::Float64
        animationDuration::Float64
        startPosition::Math.Vector2f
        targetPosition::Math.Vector2f
        
        # Idle floating animation
        idleAnimation::FloatingAnimation
        
        # Nail state
        isNailed::Bool

        # Candy Crush–style board modifier (stripe / wrapped / color bomb)
        pattern::PatternKind

        function Piece(gridPosition::Math.Vector2, pieceData)
            this = new()

            this.gridPosition = gridPosition
            this.speed = 5
            this.pieceData = pieceData
            
            # Initialize animation properties
            this.isAnimating = false
            this.animationProgress = 0.0
            this.animationDuration = 0.6  # Fixed duration for consistent bounce
            this.startPosition = Math.Vector2f(0, 0)
            this.targetPosition = Math.Vector2f(0, 0)
            
            # Initialize nail state
            this.isNailed = false
            this.pattern = PATTERN_NONE

            # Initialize very subtle idle floating animation with random variations
            randomOffset = rand() * 2π  # Random phase offset for variety
            this.idleAnimation = FloatingAnimation(
                speed = 0.1 + rand() * 0.1,  # 0.6-0.9 cycles per second
                verticalAmplitude = (0.5 + rand() * 0.5) / 64.0,  # Very subtle 1.5-2.3 pixels
                horizontalAmplitude = (0.5 + rand() * 0.5) / 64.0,  # Even more subtle 1.0-1.5 pixels
                rotationAmplitude = 0.5 + rand() * 0.5,  # Very slight rotation 0.8-1.5 degrees
                horizontalPhaseOffset = randomOffset,
                rotationPhaseOffset = randomOffset + π/4
            )

            return this
        end
    end

    function JulGame.initialize(this::Piece)
        this.gameManager = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba").scripts[1]
        this.gridController = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba").scripts[3]
        this.battleManager = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba").scripts[4]
        this.targetPosition = convert_grid_position_to_world_position(this, this.gridPosition)

        # Initialize the idle floating animation with the piece sprite
        if this.parent !== nothing && this.parent.sprite !== nothing
            # TODO: Maybe add this back in for hints
            #initialize_floating_animation(this.idleAnimation, this.parent.sprite)
        end

        @debug("piece initialized: $(this.pieceData)")
    end

    function start_fall_animation(this, targetPos)
        this.startPosition = Math.Vector2f(this.parent.transform.position.x, this.parent.transform.position.y)
        this.targetPosition = Math.Vector2f(targetPos.x, targetPos.y)
        this.isAnimating = true
        this.animationProgress = 0.0
        # @warn "BOUNCE START: $(this.parent.name) from Y=$(this.startPosition.y) to Y=$(this.targetPosition.y) dist=$(this.targetPosition.y - this.startPosition.y)"
    end

    """Drop an in-flight fall (e.g. one the hover wobble triggered) so a swapped piece can't resume it from its old cell."""
    function stop_fall_animation!(this)
        this.isAnimating = false
        this.animationProgress = 1.0
    end

    function convert_grid_position_to_world_position(this, grid_position)
		# Convert grid indices (1-based) to world coordinates
		# Subtract 1 to convert from 1-based to 0-based, then multiply by cell size and add start position
		worldX = (grid_position.x - 1) * this.gridController.gridCellWidth + this.gridController.gridStartX
		worldY = (grid_position.y - 1) * this.gridController.gridCellHeight + this.gridController.gridStartY
		
		return Math.Vector2f(worldX, worldY)
	end

    function should_start_fall_animation(currentPos, gridPosWorld, settlingTolerance)
        shouldStart = currentPos.y < gridPosWorld.y
        # Only log when there's a significant difference
        if abs(currentPos.y - gridPosWorld.y) > 0.5
            # @warn "BOUNCE CHECK: currentPos.y=$(currentPos.y) gridPosWorld.y=$(gridPosWorld.y) shouldStart=$shouldStart diff=$(gridPosWorld.y - currentPos.y)"
        end
        return shouldStart
    end
    
    function should_settle_animation(yDistance, animationProgress, settlingTolerance)
        # Only settle when animation is complete - don't cut it short based on distance
        # The bounce effect happens in the later part of the animation
        return animationProgress >= 1.0
    end
    
    function settle_piece_position(this::Piece, gridPosWorld)
        # @warn "BOUNCE SETTLE: $(this.parent.name) at Y=$(gridPosWorld.y) progress=$(this.animationProgress)"
        this.animationProgress = 1.0
        this.isAnimating = false
        this.parent.transform.position = Math.Vector2f(gridPosWorld.x, gridPosWorld.y)
        
        # Re-initialize idle animation after falling animation completes
        if this.parent !== nothing && this.parent.sprite !== nothing
            initialize_floating_animation(this.idleAnimation, this.parent.sprite)
        end
    end
    
    function update_fall_animation(this::Piece, deltaTime, gridPosWorld)
        # Apply game speed multiplier to animation
        globals = JulGame.UserGlobals["Module"]
        speed_multiplier = globals.get_data_manager().game_speed_multiplier
        this.animationProgress += (deltaTime * speed_multiplier) / this.animationDuration
        easedProgress = ease_out_bounce(this.animationProgress)
        
        # Interpolate position with easing
        currentX = this.startPosition.x + (gridPosWorld.x - this.startPosition.x) * easedProgress
        currentY = this.startPosition.y + (gridPosWorld.y - this.startPosition.y) * easedProgress
        
        this.parent.transform.position = Math.Vector2f(currentX, currentY)
    end
    
    function ensure_grid_alignment(this::Piece, gridPosWorld)
        if this.parent.transform.position.y != gridPosWorld.y
            diff = abs(this.parent.transform.position.y - gridPosWorld.y)
            if diff > 0.5
                # @warn "BOUNCE SNAP: $(this.parent.name) snapping from Y=$(this.parent.transform.position.y) to Y=$(gridPosWorld.y) diff=$diff"
            end
            this.parent.transform.position = Math.Vector2f(gridPosWorld.x, gridPosWorld.y)
        end
    end

    function JulGame.update(this::Piece, deltaTime)
        if this.battleManager.currentState == this.battleManager.battleStates[:switchingItems]
            return
        end
        if this.gridController !== nothing && hasproperty(this.gridController, :rearranging) && this.gridController.rearranging
            return
        end
        if Scripts.DieRollAnimatorModule.owns(this.parent)
            return
        end

        gridPosWorld = convert_grid_position_to_world_position(this, this.gridPosition)  
        currentPos = this.parent.transform.position
        yDistance = abs(currentPos.y - gridPosWorld.y)
        settlingTolerance = 0.1

        # Check if we need to start a new animation
        if !this.isAnimating && should_start_fall_animation(currentPos, gridPosWorld, settlingTolerance)
            start_fall_animation(this, gridPosWorld)
        elseif !this.isAnimating && yDistance <= settlingTolerance
            # Force snap to exact position
            this.parent.transform.position = Math.Vector2f(gridPosWorld.x, gridPosWorld.y)
        end

        # Process animation
        if this.isAnimating
            currentPos = this.parent.transform.position
            yDistance = abs(currentPos.y - gridPosWorld.y)
            
            if should_settle_animation(yDistance, this.animationProgress, settlingTolerance)
                settle_piece_position(this, gridPosWorld)
            else
                update_fall_animation(this, deltaTime, gridPosWorld)
            end
        else
            # When not falling, ensure alignment (floating animation works on sprite offset)
            ensure_grid_alignment(this, gridPosWorld)
            if is_patterned(this.pattern)
                tick_idle_visual!(this.parent, this.pattern, PatternAnimatorModule.get_animator().idle_time)
            end
        end
    end

    function JulGame.on_shutdown(this::Piece)
    end 
end
