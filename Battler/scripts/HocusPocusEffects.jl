module HocusPocusEffectsModule
    using JulGame
    using ..Scripts
    include("utils/Easings.jl")

    mutable struct HocusPocusEffects <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        
        queueManager
        abilityManager
        
        # Track hover state for each queue piece
        hoveredPiece::Any  # Currently hovered piece entity
        previousHoveredPiece::Any
        
        # Animation state for each piece
        pieceStates
        
        # Dancing animation parameters
        danceTime::Float64
        danceSpeed::Float64
        danceAmplitude::Float64
        
        # Hover animation parameters
        hoverScale::Float64
        hoverTransitionTime::Float64
        
        # Drag animation parameters
        dragScale::Float64
        dragShadowOffset::Float64
        
        # Rotation/tilt parameters for dragging
        rotationAmount::Float64
        rotationSpeed::Float64
        manualTiltAmount::Float64
        tiltSpeed::Float64
        movementDelta::Math.Vector2f  # Track movement for rotation
        
        function HocusPocusEffects()
            this = new() # do not remove this line
            
            this.hoveredPiece = nothing
            this.previousHoveredPiece = nothing
            this.pieceStates = Dict()
            
            # Dancing animation
            this.danceTime = 0.0
            this.danceSpeed = 2.0  # Speed of dancing animation
            this.danceAmplitude = 0.15  # How much pieces move up/down
            
            # Hover animation
            this.hoverScale = 1.2  # Scale when hovered
            this.hoverTransitionTime = 0.15  # Time to transition scale
            
            # Drag animation
            this.dragScale = 1.3  # Scale when dragging
            this.dragShadowOffset = 0.2  # Shadow offset when dragging
            
            # Rotation/tilt parameters
            this.rotationAmount = 15.0  # Rotation per unit of movement (degrees per world unit)
            this.rotationSpeed = 20.0  # Speed of rotation lerp
            this.manualTiltAmount = 0.5  # Tilt based on mouse offset (degrees per world unit)
            this.tiltSpeed = 20.0  # Speed of tilt lerp
            this.movementDelta = Math.Vector2f(0, 0)  # Track movement for rotation
            
            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # Do not remove this function
    function JulGame.initialize(this::HocusPocusEffects)
        @debug "HocusPocusEffects: Initializing..."
        # Find QueueManager and AbilityManager by searching through scripts
        for (idx, script) in enumerate(this.parent.scripts)
            if typeof(script) == Scripts.QueueManagerModule.QueueManager
                this.queueManager = script
                @debug "HocusPocusEffects: Found QueueManager at index $idx"
            elseif typeof(script) == Scripts.AbilityManagerModule.AbilityManager
                this.abilityManager = script
                @debug "HocusPocusEffects: Found AbilityManager at index $idx"
            end
        end
        
        if this.queueManager === nothing
            @warn "HocusPocusEffects: Could not find QueueManager"
        end
        if this.abilityManager === nothing
            @warn "HocusPocusEffects: Could not find AbilityManager"
        end
    end

    # This is called every frame
    # Do not remove this function
    function JulGame.update(this::HocusPocusEffects, deltaTime::Float64)
        if this.queueManager === nothing || this.abilityManager === nothing
            # Try to find them again if they're missing
            for (idx, script) in enumerate(this.parent.scripts)
                if this.queueManager === nothing && typeof(script) == Scripts.QueueManagerModule.QueueManager
                    this.queueManager = script
                elseif this.abilityManager === nothing && typeof(script) == Scripts.AbilityManagerModule.AbilityManager
                    this.abilityManager = script
                end
            end
            if this.queueManager === nothing || this.abilityManager === nothing
                return
            end
        end
        
        globals = JulGame.UserGlobals["Module"]
        if !globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_HOCUSPOCUS)
            reset_all_animations(this)
            return
        end
        if this.abilityManager.isDetonatorSelectionMode || this.abilityManager.isNailSelectionMode
            reset_all_animations(this)
            return
        end
        # Match highlight gating: only juice the queue on the player's turn
        battleManager = this.parent.scripts[4]
        if battleManager.currentState != battleManager.battleStates[:playerTurn]
            reset_all_animations(this)
            return
        end
        
        # Update dance time
        this.danceTime += deltaTime * this.danceSpeed
        
        # Find all queue pieces
        queue_pieces = get_queue_pieces(this)
        
        if isempty(queue_pieces)
            return  # No queue pieces to animate
        end
        
        # Update hover detection
        update_hover_detection(this, queue_pieces)
        
        # Update animations for each piece
        for piece in queue_pieces
            update_piece_animations(this, piece, deltaTime)
        end
        
        # Clean up states for pieces that no longer exist
        cleanup_states(this, queue_pieces)
    end
    
    """
    Get all queue piece entities
    """
    function get_queue_pieces(this)
        pieces = []
        for entity in MAIN.scene.entities
            # Include the dragged piece so hover/drag scale state is not deleted
            # mid-click (that recaptured the enlarged scale as the new base).
            if occursin("_Queue", entity.name)
                push!(pieces, entity)
            end
        end
        return pieces
    end
    
    """
    Update hover detection for queue pieces
    """
    function update_hover_detection(this, queue_pieces)
        mousePos = MAIN.input.mousePositionWorld
        this.previousHoveredPiece = this.hoveredPiece
        this.hoveredPiece = nothing
        
        # Check if mouse is over any queue piece (using same logic as QueueManager click detection)
        for piece in queue_pieces
            if piece.sprite === nothing
                continue
            end
            
            # Get piece position and size (same as QueueManager click detection)
            entityPos = piece.transform.position
            entitySize = 1.0  # Same as QueueManager uses
            
            # Calculate entity center (matching QueueManager's calculation)
            entityCenterX = entityPos.x + entitySize/2
            entityCenterY = entityPos.y + entitySize/2
            
            # Make hover area taller to account for dance animation
            # Add dance amplitude to both top and bottom, plus some padding
            baseHoverSize = entitySize / 2  # Base hover size (half size on each side of center)
            hoverHeight = baseHoverSize + (this.danceAmplitude * 2) + 0.2  # Extra padding for safety
            hoverWidth = baseHoverSize
            
            # Check if mouse is within bounds (centered around piece center, like click detection)
            if abs(mousePos.x - entityCenterX) <= hoverWidth && 
               abs(mousePos.y - entityCenterY) <= hoverHeight
                this.hoveredPiece = piece
                break
            end
        end
        
        # Handle hover state changes
        if this.hoveredPiece !== this.previousHoveredPiece
            if this.previousHoveredPiece !== nothing
                on_hover_exit(this, this.previousHoveredPiece)
            end
            if this.hoveredPiece !== nothing
                on_hover_enter(this, this.hoveredPiece)
            end
        end
    end
    
    """
    Initialize state for a piece if it doesn't exist
    """
    function ensure_piece_state(this, piece)
        if !haskey(this.pieceStates, piece)
            base_scale = if this.queueManager !== nothing
                this.queueManager.queue_piece_scale
            else
                Math.Vector2f(piece.transform.scale.x, piece.transform.scale.y)
            end
            this.pieceStates[piece] = Dict(
                "baseScale" => Math.Vector2f(base_scale.x, base_scale.y),
                "targetScale" => 1.0,
                "scaleTime" => 0.0,
                "basePosition" => Math.Vector2f(piece.transform.position.x, piece.transform.position.y),
                "danceOffset" => 0.0,
                "rotation" => 0.0,
                "rotationDelta" => 0.0,  # For smooth rotation lerping
                "tiltX" => 0.0,
                "tiltY" => 0.0,
                "shadowEntity" => nothing,
                "isDragging" => false,
                "lastKnownBaseX" => piece.transform.position.x,
                "lastKnownBaseY" => piece.transform.position.y,
                "lastPosition" => Math.Vector2f(piece.transform.position.x, piece.transform.position.y)
            )
        else
            # Update base position if piece moved externally (queue reordering)
            state = this.pieceStates[piece]
            current_pos = piece.transform.position
            stored_base = state["basePosition"]
            dance_offset = state["danceOffset"]
            
            # Calculate expected position with dance offset
            expected_y = stored_base.y + dance_offset
            expected_x = stored_base.x
            
            # If position differs significantly from expected (accounting for dance),
            # the piece was moved externally (e.g., queue reordering)
            x_diff = abs(current_pos.x - expected_x)
            y_diff = abs(current_pos.y - expected_y)
            
            # If X changed significantly, queue was reordered - update base X
            if x_diff > 0.2
                state["basePosition"] = Math.Vector2f(current_pos.x, stored_base.y)
                state["lastKnownBaseX"] = current_pos.x
            end
            
            # If Y changed significantly beyond dance range, update base Y
            if y_diff > this.danceAmplitude * 1.5
                state["basePosition"] = Math.Vector2f(stored_base.x, current_pos.y - dance_offset)
                state["lastKnownBaseY"] = current_pos.y - dance_offset
            end
        end
        return this.pieceStates[piece]
    end
    
    """
    Update animations for a single piece
    """
    function update_piece_animations(this, piece, deltaTime)
        if piece === nothing || !isdefined(piece, :transform)
            return
        end
        
        state = ensure_piece_state(this, piece)
        
        # Check if this piece is being dragged or returning
        is_dragging = false
        is_returning = false
        if this.queueManager !== nothing
            if isdefined(this.queueManager, :dragged_piece_entity)
                is_dragging = (this.queueManager.dragged_piece_entity === piece)
            end
            if isdefined(this.queueManager, :returning_piece_entity)
                is_returning = (this.queueManager.returning_piece_entity === piece)
            end
        end
        state["isDragging"] = is_dragging
        
        # If returning, reset scale to normal and skip animations
        if is_returning
            # Reset scale to base scale
            piece.transform.scale = state["baseScale"]
            set_render_scale!(piece, 1.0)
            # Reset rotation
            if piece.sprite !== nothing
                piece.sprite.rotation = 0.0
            end
            return
        end
        
        # Update dancing animation (only if not dragging and Hocus Pocus is available)
        if !is_dragging
            update_dance_animation(this, piece, state, deltaTime)
            # Update last position for non-dragging pieces (for when they start dragging)
            state["lastPosition"] = Math.Vector2f(piece.transform.position.x, piece.transform.position.y)
        end
        
        # Update hover scale animation
        update_hover_scale(this, piece, state, deltaTime)
        
        # Update drag effects
        if is_dragging
            update_drag_effects(this, piece, state, deltaTime)
        else
            remove_drag_effects(this, piece, state)
            # Reset movement delta when not dragging
            this.movementDelta = Math.Vector2f(0, 0)
        end
    end
    
    """
    Update dancing animation (bobbing up and down)
    """
    function update_dance_animation(this, piece, state, deltaTime)
        # Use piece index for phase offset (so pieces dance at different times)
        piece_index = get_piece_index(this, piece)
        phase = this.danceTime + (piece_index * 0.5)  # Offset each piece
        
        # Calculate dance offset using sine wave
        new_dance_offset = sin(phase) * this.danceAmplitude
        
        # Get current position
        current_pos = piece.transform.position
        basePos = state["basePosition"]
        
        # Update base position if piece moved significantly (queue manager repositioned it)
        x_diff = abs(current_pos.x - basePos.x)
        y_diff = abs(current_pos.y - (basePos.y + state["danceOffset"]))
        
        if x_diff > 0.1
            # X changed - queue was reordered, update base X
            state["basePosition"] = Math.Vector2f(current_pos.x, basePos.y)
            basePos = state["basePosition"]
        end
        
        if y_diff > this.danceAmplitude * 1.5
            # Y changed beyond dance range - update base Y
            state["basePosition"] = Math.Vector2f(basePos.x, current_pos.y - state["danceOffset"])
            basePos = state["basePosition"]
        end
        
        # Apply new dance offset
        state["danceOffset"] = new_dance_offset
        piece.transform.position = Math.Vector2f(
            basePos.x,
            basePos.y + state["danceOffset"]
        )
        
        # Add slight rotation for more dynamic feel
        state["rotation"] = sin(phase * 0.7) * 5.0  # Max 5 degrees rotation
        if piece.sprite !== nothing
            piece.sprite.rotation = state["rotation"]
        end
    end
    
    """
    Update hover scale animation
    """
    function update_hover_scale(this, piece, state, deltaTime)
        is_hovered = (this.hoveredPiece === piece)
        
        # Determine target scale
        if state["isDragging"]
            target_scale = this.dragScale
        elseif is_hovered
            target_scale = this.hoverScale
        else
            target_scale = 1.0
        end
        
        # Update target if changed
        if state["targetScale"] != target_scale
            state["targetScale"] = target_scale
            state["scaleTime"] = 0.0
        end
        
        # Animate scale
        state["scaleTime"] += deltaTime
        t = min(state["scaleTime"] / this.hoverTransitionTime, 1.0)
        eased_t = ease_out_back(t)  # Using ease_out_back for springy feel
        
        set_render_scale!(piece, 1.0 + (target_scale - 1.0) * eased_t)
    end

    """Hover/drag scale, drawn about the piece's center; transform.scale stays at baseScale."""
    function set_render_scale!(piece, s::Float64)
        piece.sprite === nothing && return
        piece.sprite.renderScale = Math.Vector2f(s, s)
    end
    
    """
    Update drag effects (shadow, scale, rotation, tilt, etc.)
    """
    function update_drag_effects(this, piece, state, deltaTime)
        # Create shadow if it doesn't exist
        if state["shadowEntity"] === nothing
            create_drag_shadow(this, piece, state)
        end
        
        # Increase layer when dragging
        if piece.sprite !== nothing
            piece.sprite.layer = 10  # High layer when dragging
        end
        
        # Update rotation based on movement (FollowRotation from Unity example)
        base_rotation = update_drag_rotation(this, piece, state, deltaTime)
        
        # Update tilt based on mouse offset (CardTilt from Unity example)
        tilt_rotation = update_drag_tilt(this, piece, state, deltaTime)
        
        # Combine base rotation (from movement) with tilt (from mouse offset)
        if piece.sprite !== nothing
            final_rotation = clamp(base_rotation + tilt_rotation, -60.0, 60.0)
            piece.sprite.rotation = final_rotation
        end

        # Update shadow (offset below the piece) after scale/rotation are final for this frame
        shadow = state["shadowEntity"]
        if shadow !== nothing
            shadow_pos = piece.transform.position
            shadow.transform.position = Math.Vector2f(
                shadow_pos.x,
                shadow_pos.y - this.dragShadowOffset
            )
            shadow.transform.scale = piece.transform.scale
            # Make shadow darker and more transparent
            if shadow.sprite !== nothing && piece.sprite !== nothing
                shadow.sprite.color = (0, 0, 0, 100)
                shadow.sprite.renderScale = piece.sprite.renderScale
                shadow.sprite.rotation = piece.sprite.rotation
            end
        end
    end
    
    """
    Update rotation based on movement direction and speed (similar to FollowRotation)
    Returns the calculated rotation value
    """
    function update_drag_rotation(this, piece, state, deltaTime)
        current_pos = Math.Vector2f(piece.transform.position.x, piece.transform.position.y)
        last_pos = state["lastPosition"]
        
        # Calculate movement (per frame)
        movement = Math.Vector2f(current_pos.x - last_pos.x, current_pos.y - last_pos.y)
        
        # Calculate movement speed (magnitude)
        movement_speed = sqrt(movement.x * movement.x + movement.y * movement.y)
        
        # Smooth movement delta (lerp towards current movement)
        # Use movement directly when dragging, smoothed delta otherwise
        this.movementDelta = Math.Vector2f(
            this.movementDelta.x + (movement.x - this.movementDelta.x) * (25.0 * deltaTime),
            this.movementDelta.y + (movement.y - this.movementDelta.y) * (25.0 * deltaTime)
        )
        
        # Calculate rotation based on movement direction and speed
        # X movement rotates around Z axis (like the Unity example)
        # Scale by speed so faster movement = more rotation
        # rotationAmount is the max rotation per unit of movement
        movement_rotation = this.movementDelta.x * this.rotationAmount * min(movement_speed * 2.0, 1.0)
        
        # Smooth rotation delta (lerp towards target rotation)
        state["rotationDelta"] += (movement_rotation - state["rotationDelta"]) * (this.rotationSpeed * deltaTime)
        
        # Clamp rotation to -60 to 60 degrees
        clamped_rotation = clamp(state["rotationDelta"], -60.0, 60.0)
        
        # Update last position
        state["lastPosition"] = current_pos
        
        return clamped_rotation
    end
    
    """
    Update tilt based on mouse offset (similar to CardTilt)
    Returns the tilt rotation value to add to base rotation
    """
    function update_drag_tilt(this, piece, state, deltaTime)
        mousePos = MAIN.input.mousePositionWorld
        piece_pos = piece.transform.position
        
        # Calculate offset from piece center to mouse
        offset = Math.Vector2f(mousePos.x - piece_pos.x, mousePos.y - piece_pos.y)
        
        # Calculate tilt based on offset (inverse Y for natural feel)
        # Offset is in world units, convert to rotation degrees
        target_tilt_x = -offset.y * this.manualTiltAmount
        target_tilt_y = offset.x * this.manualTiltAmount
        
        # Smooth tilt lerping
        current_tilt_x = state["tiltX"]
        current_tilt_y = state["tiltY"]
        
        state["tiltX"] += (target_tilt_x - current_tilt_x) * (this.tiltSpeed * deltaTime)
        state["tiltY"] += (target_tilt_y - current_tilt_y) * (this.tiltSpeed * deltaTime)
        
        # Return tilt rotation (Y offset affects Z rotation in 2D)
        return state["tiltY"]
    end
    
    """
    Remove drag effects
    """
    function remove_drag_effects(this, piece, state)
        # Remove shadow
        if state["shadowEntity"] !== nothing
            JulGame.destroy_entity(MAIN, state["shadowEntity"])
            state["shadowEntity"] = nothing
        end
        
        # Reset layer
        if piece.sprite !== nothing
            piece.sprite.layer = 2  # Back to normal layer
        end
        
        # Smoothly reset rotation and tilt
        state["rotationDelta"] *= 0.9  # Decay rotation
        state["tiltX"] *= 0.9
        state["tiltY"] *= 0.9
        
        # If rotation is very small, snap to zero
        if abs(state["rotationDelta"]) < 0.1
            state["rotationDelta"] = 0.0
            if piece.sprite !== nothing
                piece.sprite.rotation = 0.0
            end
        end
    end
    
    """
    Create drag shadow entity
    """
    function create_drag_shadow(this, piece, state)
        if piece.sprite === nothing
            return
        end
        
        # Create shadow entity (duplicate of piece but darker)
        shadow = JulGame.EntityModule.Entity("$(piece.name)_Shadow")
        crop = Math.Vector4(0, 0, 0, 0)
        
        # Get the same image as the piece
        image_path = piece.sprite.imagePath
        shadow.sprite = JulGame.SpriteModule.InternalSprite(
            shadow,
            image_path,
            crop,
            false,
            (0, 0, 0, 100),  # Dark shadow color
            false;
            pixelsPerUnit = piece.sprite.pixelsPerUnit,
            layer = 1  # Behind the piece
        )
        
        shadow = JulGame.create_entity(shadow)
        shadow.transform.position = piece.transform.position
        shadow.transform.scale = piece.transform.scale
        shadow.sprite.renderScale = piece.sprite.renderScale
        shadow.transform.rotation = piece.transform.rotation
        
        state["shadowEntity"] = shadow
    end
    
    """
    Get piece index in queue (for phase offset in dance animation)
    """
    function get_piece_index(this, piece)
        queue_pieces = get_queue_pieces(this)
        for (index, p) in enumerate(queue_pieces)
            if p === piece
                return index
            end
        end
        return 0
    end
    
    """
    Handle hover enter
    """
    function on_hover_enter(this, piece)
        state = ensure_piece_state(this, piece)
        # Target scale will be updated in update_hover_scale
        # Add a slight punch effect
        if piece.sprite !== nothing
            # Small rotation punch
            original_rotation = piece.sprite.rotation
            piece.sprite.rotation = original_rotation + 10.0
            # Will be smoothed back in update
        end
    end
    
    """
    Handle hover exit
    """
    function on_hover_exit(this, piece)
        state = ensure_piece_state(this, piece)
        # Target scale will be updated in update_hover_scale
    end
    
    """
    Reset all animations
    """
    function reset_all_animations(this)
        for (piece, state) in this.pieceStates
            if piece !== nothing && isdefined(piece, :transform)
                # Reset scale
                piece.transform.scale = state["baseScale"]
                set_render_scale!(piece, 1.0)
                # Reset position
                piece.transform.position = state["basePosition"]
                # Reset rotation
                if piece.sprite !== nothing
                    piece.sprite.rotation = 0.0
                end
                # Remove shadow
                if state["shadowEntity"] !== nothing
                    JulGame.destroy_entity(MAIN, state["shadowEntity"])
                end
            end
        end
        this.pieceStates = Dict()
        this.hoveredPiece = nothing
        this.previousHoveredPiece = nothing
    end
    
    """
    Clean up states for pieces that no longer exist
    """
    function cleanup_states(this, current_pieces)
        pieces_to_remove = []
        for (piece, state) in this.pieceStates
            if !(piece in current_pieces)
                # Clean up shadow if it exists
                if state["shadowEntity"] !== nothing
                    JulGame.destroy_entity(MAIN, state["shadowEntity"])
                end
                push!(pieces_to_remove, piece)
            end
        end
        for piece in pieces_to_remove
            delete!(this.pieceStates, piece)
        end
    end

    export HocusPocusEffects

end # module
