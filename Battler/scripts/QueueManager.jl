module QueueManagerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts
    include("utils/Easings.jl")

    # Partial refill (after dequeue-to-grid): cascade + new piece from off-screen left
    const QUEUE_LAYOUT_CASCADE_DELAY = 0.085
    const QUEUE_LAYOUT_DURATION = 0.52
    const QUEUE_OFFSCREEN_LEFT_EXTRA = 34.0
    const QUEUE_DRAG_CLICK_THRESHOLD = 0.15

    mutable struct QueueManager <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        queue_length::Int
        
        queue_pieces
        distance_between_pieces::Float64
        queue_start_x::Float64
        queue_start_y::Float64
        queue_piece_scale::Math.Vector2f

        # Drag and drop functionality
        dragging_piece::Bool
        dragged_piece_entity
        dragged_piece_data
        dragged_piece_index::Int
        original_position::Math.Vector2f
        gridController
        dragging_offset::Math.Vector2f 
        drag_mouse_start::Math.Vector2f
        abilityManager  # Reference to AbilityManager to check if Hocus Pocus is active

        isMouseDown::Bool

        # Animation functionality
        animating_pieces::Vector{Any}  # Array of pieces currently being animated
        animation_speed::Float64      # Speed of the animation
        
        # Return animation for dropped pieces
        returning_piece_entity
        return_start_position::Math.Vector2f
        return_target_position::Math.Vector2f
        return_animation_time::Float64
        return_animation_duration::Float64
        is_returning::Bool

        queue_layout_anim_next_refresh::Bool
        queue_layout_anim_full_refresh::Bool
        queue_layout_busy::Bool
        queue_layout_tweens::Vector{Any}

        function QueueManager()
            this = new() # do not remove this line
            this.distance_between_pieces = 1.05
            this.queue_start_x = -10.35
            this.queue_start_y = -3.1
            this.queue_piece_scale = Math.Vector2f(1.25, 1.25)
            this.queue_length = 7
            this.queue_pieces = []
            # Initialize drag and drop variables
            this.dragging_piece = false
            this.dragged_piece_entity = nothing
            this.dragged_piece_data = nothing
            this.dragged_piece_index = -1
            this.original_position = Math.Vector2f(0, 0)
            this.gridController = nothing
            this.isMouseDown = false
            this.dragging_offset = Math.Vector2f(0, 0)
            this.drag_mouse_start = Math.Vector2f(0, 0)

            # Initialize animation variables
            this.animating_pieces = []
            this.animation_speed = 6.0  # Animation speed (higher = faster)
            
            # Initialize return animation
            this.returning_piece_entity = nothing
            this.return_start_position = Math.Vector2f(0, 0)
            this.return_target_position = Math.Vector2f(0, 0)
            this.return_animation_time = 0.0
            this.return_animation_duration = 0.4  # 400ms for return animation
            this.is_returning = false

            this.queue_layout_anim_next_refresh = false
            this.queue_layout_anim_full_refresh = false
            this.queue_layout_busy = false
            this.queue_layout_tweens = Any[]

            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # This is where you should register collision events or other events
    # Do not remove this function
    function JulGame.initialize(this::QueueManager)
        this.gridController = this.parent.scripts[3]
        this.abilityManager = this.parent.scripts[17]  # AbilityManager is script 19
        @debug("queue manager initialized")
    end

    # This is called every frame
    # Do not remove this function
    function JulGame.update(this::QueueManager, deltaTime)
        update_queue_layout_animations(this, deltaTime)
        # Update animating pieces
        update_animating_pieces(this, deltaTime)
        
        # Update return animation
        update_return_animation(this, deltaTime)

        if JulGame.InputModule.get_mouse_button_pressed(1) || JulGame.InputModule.get_mouse_button(1)
            #@debug "setting mouse down to true"
            this.isMouseDown = true
        end
        if JulGame.InputModule.get_mouse_button_released(1)
            #@debug "setting mouse down to false"
            this.isMouseDown = false
        end
        # Get the battle manager to check the current state
        battleManager = this.parent.scripts[4]
        
        # Only allow dragging during the player's turn
        mousePos = MAIN.input.mousePositionWorld
        if this.dragging_piece && this.dragged_piece_entity === nothing
            this.dragging_piece = false
        end
        if battleManager.currentState == battleManager.battleStates[:playerTurn]
            # Handle dragging of queue pieces (but not if returning or queue layout is animating)
            if this.dragging_piece && this.dragged_piece_entity !== nothing && !this.is_returning
                # Update the position of the dragged piece to follow the mouse
                this.dragged_piece_entity.transform.position = Math.Vector2f(
                    mousePos.x + this.dragging_offset.x,
                    mousePos.y + this.dragging_offset.y
                )
                
                # Check if mouse button is released
                if !this.isMouseDown
                    handle_piece_drop(this)
                end
            elseif !this.dragging_piece && !this.queue_layout_busy && this.isMouseDown && JulGame.InputModule.get_mouse_button(1) && !Scripts.TutorialModule.blocks_side_actions()
                #@debug "checking mouse for queue"
                # Check if we're clicking on a queue piece
                
                # Check all queue piece entities
                for entity in MAIN.scene.entities
                    if occursin("_Queue", entity.name)
                        # Get the entity position (top-left corner)
                        entityPos = entity.transform.position
                        # Get the entity size (assuming 1x1 for queue pieces)
                        entitySize = 1.0
                        # Calculate entity center
                        entityCenterX = entityPos.x + entitySize/2
                        entityCenterY = entityPos.y + entitySize/2
                        # Check if mouse is within reasonable distance of center (half the size)
                        globals = JulGame.UserGlobals["Module"]
                        hocus_pocus_active = globals.UserModule.has_treasure(
                            globals.TreasuresModule.TREASURE_HOCUSPOCUS,
                        )
                        if abs(mousePos.x - entityCenterX) <= entitySize/2 && 
                           abs(mousePos.y - entityCenterY) <= entitySize/2 &&
                           hocus_pocus_active
                            @debug "dragging $(entity.name) with Hocus Pocus active"
                            start_dragging(this, entity)
                            break
                        end
                    end
                end
            end
        elseif this.dragging_piece
            # If we're not in player turn but still dragging, cancel the drag
            cancel_queue_drag!(this)
        end
    end

    # This is called when the script is removed from an entity (scene change, entity deletion)
    # Do not remove this function
    function JulGame.on_shutdown(this::QueueManager)
    end 

    function start_dragging(this, entity)
        @debug "Starting to drag $(entity.name)"
        this.is_returning = false
        this.returning_piece_entity = nothing
        this.dragging_piece = true
        this.dragged_piece_entity = entity
        this.original_position = entity.transform.position
        
        # Calculate the offset between mouse position and entity position
        mousePos = MAIN.input.mousePositionWorld
        this.drag_mouse_start = Math.Vector2f(mousePos.x, mousePos.y)
        this.dragging_offset = Math.Vector2f(
            entity.transform.position.x - mousePos.x,
            entity.transform.position.y - mousePos.y
        )
        
        # Extract the piece name without the _Queue suffix
        piece_name = replace(entity.name, "_Queue" => "")
        
        # Find the piece data and index in the queue
        for (index, piece) in enumerate(this.queue_pieces)
            if piece.key == piece_name
                this.dragged_piece_data = piece
                this.dragged_piece_index = index
                break
            end
        end
        
        # Change the layer to make it appear above other pieces
        if this.dragged_piece_entity.sprite !== nothing
            this.dragged_piece_entity.sprite.layer = 3
        end

        try
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(),
                globals.get_asset_path("sfx", "selectpiece"),
                false, 1.0, 0, 1,
            )
        catch
        end
    end
    
    function cancel_queue_drag!(this)
        if this.dragged_piece_entity !== nothing
            this.dragged_piece_entity.transform.position = this.original_position
            this.dragged_piece_entity.transform.scale = this.queue_piece_scale
            if this.dragged_piece_entity.sprite !== nothing
                this.dragged_piece_entity.sprite.layer = 2
                this.dragged_piece_entity.sprite.rotation = 0.0
            end
        end
        this.dragging_piece = false
        this.is_returning = false
        this.returning_piece_entity = nothing
        this.dragged_piece_entity = nothing
        this.dragged_piece_data = nothing
        this.dragged_piece_index = -1
    end

    function handle_piece_drop(this)
        @debug "Dropping piece"
        mousePos = MAIN.input.mousePositionWorld

        if abs(mousePos.x - this.drag_mouse_start.x) < QUEUE_DRAG_CLICK_THRESHOLD &&
           abs(mousePos.y - this.drag_mouse_start.y) < QUEUE_DRAG_CLICK_THRESHOLD
            cancel_queue_drag!(this)
            return
        end
        
        globals = JulGame.UserGlobals["Module"]
        if !globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_HOCUSPOCUS)
            @debug "Hocus Pocus not owned, cancelling drag"
            # Return piece to queue
            if this.dragged_piece_entity !== nothing
                this.dragged_piece_entity.transform.position = this.original_position
                if this.dragged_piece_entity.sprite !== nothing
                    this.dragged_piece_entity.sprite.layer = 2
                end
            end
            this.dragging_piece = false
            this.dragged_piece_entity = nothing
            this.dragged_piece_data = nothing
            this.dragged_piece_index = -1
            return
        end
        
        # Check if the drop position is within the grid
        if this.gridController.gridStartX <= mousePos.x <= (this.gridController.gridStartX + this.gridController.gridWidth * this.gridController.gridCellWidth) && this.gridController.gridStartY <= mousePos.y <= (this.gridController.gridStartY + this.gridController.gridHeight * this.gridController.gridCellHeight)   
            # Convert to grid coordinates
            gridX = convert(Int64, Scripts.InputHandlerModule.convert_world_position_to_grid_position(this, mousePos).x)
            gridY = convert(Int64, Scripts.InputHandlerModule.convert_world_position_to_grid_position(this, mousePos).y)
            
            # Check bounds
            if gridX >= 1 && gridX <= this.gridController.gridWidth && 
               gridY >= 1 && gridY <= this.gridController.gridHeight
                
                # Place the piece on the grid (handles both empty spaces and replacing existing pieces)
                if this.dragged_piece_data !== nothing
                    # Get the existing piece at the drop location
                    existing_piece = this.gridController.gridPieces[gridX, gridY]
                    
                    if existing_piece !== nothing
                        # Check if the existing piece is nailed - if so, don't allow replacement
                        if Scripts.AbilityManagerModule.is_piece_nailed(existing_piece)
                            @debug "Cannot replace nailed piece with queue piece"
                            # Show feedback that replacement is blocked
                            DisplayTextModule.display_text(
                                "nail_replace_blocked",
                                "Cannot replace nailed pieces!";
                                fontSize = 18,
                                anchor = :center,
                                lifetime = 1500,
                                color = (255, 100, 100, 255)
                            )
                        elseif existing_piece.name == this.dragged_piece_data.key
                            # Replacing a piece with the exact same piece is a no-op:
                            # treat it like a cancelled drop and return it to the queue.
                            @debug "Identical piece at drop target, returning to queue"
                            if this.dragged_piece_entity !== nothing
                                start_return_animation(this, this.dragged_piece_entity, this.original_position)
                            end
                        else
                            # Replace the piece and check for matches
                            replace_grid_piece(this, gridX, gridY)
                        end
                    else
                        # Empty grid space - place the piece directly
                        place_piece_on_empty_grid(this, gridX, gridY)
                    end
                end
            end
        else
            # Return the piece to its original position in the queue with animation
            if this.dragged_piece_entity !== nothing
                start_return_animation(this, this.dragged_piece_entity, this.original_position)
            end
        end
        
        # Reset dragging state (but keep entity for animation)
        this.dragging_piece = false
        # Don't clear dragged_piece_entity yet - let animation complete
        if !this.is_returning
            this.dragged_piece_entity = nothing
            this.dragged_piece_data = nothing
            this.dragged_piece_index = -1
        end
    end
    
    function replace_grid_piece(this, gridX, gridY)
        # Destroy the existing piece at the grid position
        existing_piece = this.gridController.gridPieces[gridX, gridY]
        if existing_piece !== nothing
            JulGame.destroy_entity(MAIN, existing_piece)
        end
        
        # Create a new piece at the grid position with the dragged piece data
        new_piece = Scripts.GridControllerModule.place_item(this.gridController, this.dragged_piece_data, gridX, gridY)
        
        # Remove the dragged piece from the queue and add a new one
        if this.dragged_piece_index > 0
            deleteat!(this.queue_pieces, this.dragged_piece_index)
            
            # Add a new piece to the queue
            globals = JulGame.UserGlobals["Module"]
            persistentStateManager = globals.get_data_manager().persistent_state_manager
            
            pushfirst!(this.queue_pieces, get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager))
        end
        
        # Destroy the dragged queue piece entity
        if this.dragged_piece_entity !== nothing
            JulGame.destroy_entity(MAIN, this.dragged_piece_entity)
        end
        
        # Update the queue display
        update_queue_display(this)
        
        # Track drag usage in analytics
        try
            Globals.AnalyticsModule.track_action(:drag_used)
        catch e
            @debug "Could not track drag usage: $e"
        end
        
        if this.abilityManager !== nothing
            globals = JulGame.UserGlobals["Module"]
            Scripts.AbilityManagerModule.use_ability(this.abilityManager, globals.TreasuresModule.TREASURE_HOCUSPOCUS)
        end
        
        # Check for matches around the new piece
        check_for_matches_around_piece(this, new_piece)
    end
    
    """
    Place a piece on an empty grid space (for Hocus Pocus)
    """
    function place_piece_on_empty_grid(this, gridX, gridY)
        if this.dragged_piece_data === nothing
            return
        end
        
        # Place the piece directly on the grid
        new_piece = Scripts.GridControllerModule.place_item(this.gridController, this.dragged_piece_data, gridX, gridY)
        
        # Remove the dragged piece from the queue and add a new one
        if this.dragged_piece_index > 0
            deleteat!(this.queue_pieces, this.dragged_piece_index)
            
            # Add a new piece to the queue
            globals = JulGame.UserGlobals["Module"]
            persistentStateManager = globals.get_data_manager().persistent_state_manager
            
            pushfirst!(this.queue_pieces, get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager))
        end
        
        # Destroy the dragged queue piece entity
        if this.dragged_piece_entity !== nothing
            JulGame.destroy_entity(MAIN, this.dragged_piece_entity)
        end
        
        # Update the queue display
        update_queue_display(this)
        
        # Track drag usage in analytics
        try
            Globals.AnalyticsModule.track_action(:drag_used)
        catch e
            @debug "Could not track drag usage: $e"
        end
        
        if this.abilityManager !== nothing
            globals = JulGame.UserGlobals["Module"]
            Scripts.AbilityManagerModule.use_ability(this.abilityManager, globals.TreasuresModule.TREASURE_HOCUSPOCUS)
        end
        
        # Check for matches around the new piece
        check_for_matches_around_piece(this, new_piece)
    end
    
    function check_for_matches_around_piece(this, piece)
        # Get the battle manager
        battleManager = this.parent.scripts[4]
        
        # Search for matches
        Scripts.GridControllerModule.search_for_matches(this.gridController, [piece], false, false, false, true)
    end

    function init_grid_and_populate_queue(this, persistentStateManager, gridWidth, gridHeight)
        grid = get_rand_grid_from_seed_and_update_seed_use_count(this, persistentStateManager, gridWidth, gridHeight) 

        refill_queue(this, persistentStateManager)
        this.queue_layout_anim_full_refresh = true
        update_queue_display(this)

        return grid
    end

    function get_rand_grid_from_seed_and_update_seed_use_count(this, persistentStateManager, gridWidth, gridHeight) 
        globals = JulGame.UserGlobals["Module"]
        return globals.PersistentStateManagerModule.get_rand_grid_from_seed_and_update_seed_use_count(persistentStateManager, gridWidth, gridHeight)
    end
    
    function get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager)
        globals = JulGame.UserGlobals["Module"]
        return globals.PersistentStateManagerModule.get_rand_from_seed_and_update_seed_use_count(persistentStateManager)
    end

    function clean_queue_display(this)
        entities_to_destroy = []
        
        # Get list of entities currently being animated to avoid destroying them
        animating_entity_ids = Set()
        for animation_data in this.animating_pieces
            if haskey(animation_data, "entity") && animation_data["entity"] !== nothing
                push!(animating_entity_ids, animation_data["entity"].id)
            end
        end
        queue_layout_entity_ids = Set()
        for tw in this.queue_layout_tweens
            if haskey(tw, "entity") && tw["entity"] !== nothing
                push!(queue_layout_entity_ids, tw["entity"].id)
            end
        end
        
        count = 0
        for entity in MAIN.scene.entities
            # if name contains _Queue and it's not currently animating
            if occursin("_Queue", entity.name) && !(entity.id in animating_entity_ids) && !(entity.id in queue_layout_entity_ids)
                @debug "destroying $(entity.name) in queue display"
                push!(entities_to_destroy, entity)
                count += 1
            end
        end
        @debug "destroyed $count entities in queue display"

        for entity in entities_to_destroy
            JulGame.destroy_entity(MAIN, entity)
        end
    end    

    function refill_queue(this, persistentStateManager)
        number_of_pieces_to_add::Int = this.queue_length - length(this.queue_pieces)
        @debug "adding $(number_of_pieces_to_add) to queue"

        @debug "current queue: $(this.queue_pieces)"
        if number_of_pieces_to_add > 0
            for i = 1:number_of_pieces_to_add
                pushfirst!(this.queue_pieces, get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager))
            end
            @debug "new queue: $(this.queue_pieces)"
        end
    end

    function dequeue_piece_for_grid_and_enqueue_new_piece(this, persistentStateManager)
        @debug "removing last item from queue: $(this.queue_pieces)"
        last_item = pop!(this.queue_pieces)
        @debug "item removed: $(last_item)"
        pushfirst!(this.queue_pieces, get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager))
        @debug "queue after item removed and new item added: $(this.queue_pieces)"

        return last_item
    end

    # New function to dequeue with animation
    function dequeue_piece_for_grid_with_animation(this, persistentStateManager, gridX, gridY, offsetY = 0)
        @debug "dequeuing piece with animation for grid position ($gridX, $gridY)"

        if this.queue_layout_busy
            finish_queue_layout_animations_immediate!(this)
        end
        
        # Get the piece data (last item in queue) but DON'T modify the queue yet
        if isempty(this.queue_pieces)
            # @warn "Queue is empty, cannot dequeue"
            return nothing
        end
        
        piece_data = this.queue_pieces[end]  # Get the last piece without removing it yet
        
        # Find all queue entities
        queue_entities = []
        for entity in MAIN.scene.entities
            if occursin("_Queue", entity.name)
                push!(queue_entities, entity)
            end
        end
        
        # Sort by x position (rightmost first, since we dequeue from the end)
        if !isempty(queue_entities)
            sort!(queue_entities, by = e -> e.transform.position.x, rev = true)
            
            # Find the rightmost queue entity that corresponds to the piece being dequeued
            queue_entity = nothing
            target_piece_key = piece_data.key
            
            # Look for an entity that matches the piece being dequeued and isn't animating
            for entity in queue_entities
                entity_piece_key = replace(entity.name, "_Queue" => "")
                
                # Check if this entity matches our target piece and isn't already animating
                if entity_piece_key == target_piece_key
                    is_already_animating = false
                    for animation_data in this.animating_pieces
                        if haskey(animation_data, "entity") && animation_data["entity"] !== nothing && animation_data["entity"].id == entity.id
                            is_already_animating = true
                            break
                        end
                    end
                    
                    if !is_already_animating
                        queue_entity = entity
                        break
                    end
                end
            end
            
            # If we couldn't find a matching entity, fall back to any available entity
            if queue_entity === nothing
                for entity in queue_entities
                    is_already_animating = false
                    for animation_data in this.animating_pieces
                        if haskey(animation_data, "entity") && animation_data["entity"] !== nothing && animation_data["entity"].id == entity.id
                            is_already_animating = true
                            break
                        end
                    end
                    
                    if !is_already_animating
                        queue_entity = entity
                        @debug "Using fallback entity $(entity.name) for piece $(target_piece_key)"
                        break
                    end
                end
            end
            
            if queue_entity !== nothing
                # NOW we can safely update the queue data since we've identified the entity to animate
                actual_piece_data = pop!(this.queue_pieces)  # Remove the actual piece
                pushfirst!(this.queue_pieces, get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager))  # Add new piece
                
                # Start animation from queue position to grid position
                @debug "starting animation from queue to grid for $(actual_piece_data.key) at $(gridX), $(gridY) with offset $offsetY"
                start_queue_to_grid_animation(this, queue_entity, actual_piece_data, gridX, gridY, offsetY)
                
                # Update queue display immediately to show the change
                #update_queue_display_immediate(this)
            else
                # Fallback: animate from off-screen left when all queue entities are animating
                actual_piece_data = pop!(this.queue_pieces)  # Still need to update queue data
                pushfirst!(this.queue_pieces, get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager))
                start_offscreen_to_grid_animation(this, actual_piece_data, gridX, gridY, offsetY)
                # Still update display even for fallback
                update_queue_display(this)
            end
        else
            # Fallback: animate from off-screen left when no queue entities found
            actual_piece_data = pop!(this.queue_pieces)  # Still need to update queue data
            pushfirst!(this.queue_pieces, get_rand_from_seed_and_update_seed_use_count(this, persistentStateManager))
            start_offscreen_to_grid_animation(this, actual_piece_data, gridX, gridY, offsetY)
            # Still update display even for fallback
            update_queue_display(this)
        end
        
        return piece_data
    end

    function start_queue_to_grid_animation(this, queue_entity, piece_data, gridX, gridY, offsetY)
        @debug "Starting animation from queue to grid for $(piece_data.key)"
        
        world_grid_position = Scripts.PieceModule.convert_grid_position_to_world_position(this, Math.Vector2(gridX, gridY))
        # Calculate target position (top of the grid column with offset)
        target_position = Math.Vector2f(Float64(world_grid_position.x), Float64(world_grid_position.y) + offsetY - 3)
        # @warn "BOUNCE DEBUG start_anim: grid=($gridX,$gridY) world_grid_pos.y=$(world_grid_position.y) inputOffsetY=$offsetY target_pos.y=$(target_position.y)"
        
        # Change the layer to make it appear above other pieces during animation
        if queue_entity.sprite !== nothing
            queue_entity.sprite.layer = 5
        end

        # Queue art renders at a different pixelsPerUnit (125) than grid pieces (150),
        # so scale toward a ppu-compensated target that matches the final grid size
        # exactly — otherwise the size pops when the grid piece replaces the entity.
        start_scale = Math.Vector2f(queue_entity.transform.scale.x, queue_entity.transform.scale.y)
        ppu = queue_entity.sprite !== nothing && queue_entity.sprite.pixelsPerUnit > 0 ? queue_entity.sprite.pixelsPerUnit : 150
        scale_ratio = ppu / 150.0
        target_scale = Math.Vector2f(
            this.gridController.gridCellWidth * scale_ratio,
            this.gridController.gridCellHeight * scale_ratio,
        )
        
        # Create animation data
        animation_data = Dict(
            "entity" => queue_entity,
            "piece_data" => piece_data,
            "start_position" => Math.Vector2f(queue_entity.transform.position.x, queue_entity.transform.position.y),
            "target_position" => target_position,
            "start_scale" => start_scale,
            "target_scale" => target_scale,
            "final_grid_position" => Math.Vector2f(Float64(gridX), Float64(gridY)),
            "elapsed_time" => 0.0,
            "duration" => 0.6,  # Animation duration in seconds
            "is_complete" => false
        )
        
        # Add to animating pieces list
        push!(this.animating_pieces, animation_data)
        
        # Remove the queue entity name from queue display updates
        # (it will be destroyed when animation completes)
    end

    function start_offscreen_to_grid_animation(this, piece_data, gridX, gridY, offsetY)
        @debug "Starting animation from off-screen left to grid for $(piece_data.key)"
        
        world_grid_position = Scripts.PieceModule.convert_grid_position_to_world_position(this, Math.Vector2(gridX, gridY))
        # Calculate target position (top of the grid column with offset)
        target_position = Math.Vector2f(Float64(world_grid_position.x), Float64(world_grid_position.y) + offsetY - 3)
        
        # Start position: off-screen to the left, at the same Y as target
        start_x = this.queue_start_x - 5.0  # Further left than queue
        start_y = target_position.y
        
        # Create a temporary entity for animation (similar to queue pieces)
        crop = Math.Vector4(0, 0, 0, 0)
        temp_entity = JulGame.EntityModule.Entity("$(piece_data.key)_Offscreen")
        try
            temp_entity.sprite = JulGame.SpriteModule.InternalSprite(temp_entity, JulGame.UserGlobals["Module"].get_asset_path("piece", lowercase(split(piece_data.key, "_")[2])), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 150, layer = 5)
        catch e
            @error "Error creating offscreen piece: $(piece_data.key), placing error sprite"
            temp_entity.sprite = JulGame.SpriteModule.InternalSprite(temp_entity, JulGame.UserGlobals["Module"].get_asset_path("piece", "error"), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 8, layer = 5)
        end
        
        temp_entity = JulGame.create_entity(temp_entity)
        temp_entity.transform.position = Math.Vector2f(start_x, start_y)
        temp_entity.transform.scale = Math.Vector2f(this.gridController.gridCellWidth, this.gridController.gridCellHeight)
        
        # Create animation data
        animation_data = Dict(
            "entity" => temp_entity,
            "piece_data" => piece_data,
            "start_position" => Math.Vector2f(start_x, start_y),
            "target_position" => target_position,
            "final_grid_position" => Math.Vector2f(Float64(gridX), Float64(gridY)),
            "elapsed_time" => 0.0,
            "duration" => 0.8,  # Animation duration in seconds (same as queue pieces)
            "is_complete" => false
        )
        
        # Add to animating pieces list
        push!(this.animating_pieces, animation_data)
        
        @debug "Offscreen animation started from ($start_x, $start_y) to ($(target_position.x), $(target_position.y))"
    end

    function update_animating_pieces(this, deltaTime)
        # Update all currently animating pieces
        pieces_to_remove = []
        animations_completed_this_frame = false
        
        for (index, animation_data) in enumerate(this.animating_pieces)
            if animation_data["is_complete"]
                push!(pieces_to_remove, index)
                continue
            end
            
            # Update elapsed time (apply game speed multiplier)
            globals = JulGame.UserGlobals["Module"]
            speed_multiplier = globals.get_data_manager().game_speed_multiplier
            animation_data["elapsed_time"] += deltaTime * speed_multiplier
            
            # Calculate progress (0 to 1)
            progress = min(animation_data["elapsed_time"] / animation_data["duration"], 1.0)
            
            # Apply smooth lerp to position
            current_position = Math.Vector2f(
                JulGame.Math.SmoothLerp(
                    animation_data["start_position"].x, 
                    animation_data["target_position"].x, 
                    progress
                ),
                JulGame.Math.SmoothLerp(
                    animation_data["start_position"].y, 
                    animation_data["target_position"].y, 
                    progress
                )
            )
            
            # Update entity position
            animation_data["entity"].transform.position = current_position

            # Grow toward the grid-piece footprint while traveling
            if haskey(animation_data, "start_scale")
                start_scale = animation_data["start_scale"]
                target_scale = animation_data["target_scale"]
                animation_data["entity"].transform.scale = Math.Vector2f(
                    JulGame.Math.SmoothLerp(start_scale.x, target_scale.x, progress),
                    JulGame.Math.SmoothLerp(start_scale.y, target_scale.y, progress)
                )
            end
            
            # Check if animation is complete
            if progress >= 1.0
                complete_animation_silent(this, animation_data)
                animation_data["is_complete"] = true
                animations_completed_this_frame = true
                push!(pieces_to_remove, index)
            end
        end
        
        # Remove completed animations (in reverse order to maintain indices)
        for index in reverse(pieces_to_remove)
            deleteat!(this.animating_pieces, index)
        end
        
        # Update queue display once at the end if any animations completed
        if animations_completed_this_frame
            @debug "updating queue display from update_animating_pieces"
            update_queue_display_immediate(this)
        end
    end

    function complete_animation_silent(this, animation_data)
        @debug "Completing animation for piece (silent)"
        
        # Get the final position and piece data
        gridX = convert(Int64, animation_data["final_grid_position"].x)
        gridY = convert(Int64, animation_data["final_grid_position"].y)
        piece_data = animation_data["piece_data"]
        final_world_pos = Scripts.PieceModule.convert_grid_position_to_world_position(this, Math.Vector2(gridX, gridY))
        offsetY = animation_data["target_position"].y - final_world_pos.y
        
        # @warn "BOUNCE DEBUG (silent): gridX=$gridX gridY=$gridY target_pos.y=$(animation_data["target_position"].y) final_world_pos.y=$(final_world_pos.y) offsetY=$offsetY"
        
        ent = animation_data["entity"]
        was_queue_piece = ent !== nothing && occursin("_Queue", ent.name)
        # Destroy the animated queue entity
        JulGame.destroy_entity(MAIN, ent)
        if was_queue_piece
            this.queue_layout_anim_next_refresh = true
        end
        
        # Create the actual grid piece at the final position
        new_item = Scripts.GridControllerModule.place_item(this.gridController, piece_data, gridX, gridY, offsetY)
        
        # Add to falling pieces if it's above its final grid position
        if offsetY != 0
            push!(this.gridController.fallingPieces, new_item)
        end
        
        @debug "Animation completed and grid piece created at ($gridX, $gridY) with offset $offsetY"
        
        # Don't update queue display here - it will be done in batch by update_animating_pieces
    end

    function complete_animation(this, animation_data)
        @debug "Completing animation for piece"
        
        # Get the final position and piece data
        gridX = convert(Int64, animation_data["final_grid_position"].x)
        gridY = convert(Int64, animation_data["final_grid_position"].y)
        piece_data = animation_data["piece_data"]
        final_world_pos = Scripts.PieceModule.convert_grid_position_to_world_position(this, Math.Vector2(gridX, gridY))
        offsetY = animation_data["target_position"].y - final_world_pos.y
        
        # @warn "BOUNCE DEBUG: gridX=$gridX gridY=$gridY target_pos.y=$(animation_data["target_position"].y) final_world_pos.y=$(final_world_pos.y) offsetY=$offsetY"
        
        ent = animation_data["entity"]
        was_queue_piece = ent !== nothing && occursin("_Queue", ent.name)
        JulGame.destroy_entity(MAIN, ent)
        if was_queue_piece
            this.queue_layout_anim_next_refresh = true
        end
        
        # Create the actual grid piece at the final position
        new_item = Scripts.GridControllerModule.place_item(this.gridController, piece_data, gridX, gridY, offsetY)
        
        # Add to falling pieces if it's above its final grid position
        if offsetY != 0
            push!(this.gridController.fallingPieces, new_item)
        end
        
        @debug "Animation completed and grid piece created at ($gridX, $gridY) with offset $offsetY"
        
        # Update queue display to fill in the gap left by the completed animation
        @debug "updating queue display from complete_animation"
        update_queue_display_immediate(this)
    end

    function finish_queue_layout_animations_immediate!(this::QueueManager)
        for tw in this.queue_layout_tweens
            ent = tw["entity"]
            if ent !== nothing && ent.transform !== nothing
                ent.transform.position = Math.Vector2f(Float64(tw["tx"]), Float64(tw["ty"]))
            end
        end
        empty!(this.queue_layout_tweens)
        this.queue_layout_busy = false
    end

    function update_queue_layout_animations(this::QueueManager, deltaTime::Float64)
        isempty(this.queue_layout_tweens) && return
        globals = JulGame.UserGlobals["Module"]
        speed_mult = try
            globals.get_data_manager().game_speed_multiplier
        catch
            1.0
        end
        dt = deltaTime * speed_mult
        all_done = true
        for tw in this.queue_layout_tweens
            tw["elapsed"] = Float64(tw["elapsed"]) + dt
            t0 = Float64(tw["delay"])
            dur = Float64(tw["duration"])
            elapsed = Float64(tw["elapsed"])
            ent = tw["entity"]
            sx = Float64(tw["sx"])
            sy = Float64(tw["sy"])
            # Before the tween starts, the engine may leave new entities at (0,0); hold start pose.
            if elapsed < t0
                if ent !== nothing && ent.transform !== nothing
                    ent.transform.position = Math.Vector2f(sx, sy)
                end
                all_done = false
                continue
            end
            u = min((elapsed - t0) / dur, 1.0)
            eased = ease_out_cubic(u)
            tx = Float64(tw["tx"])
            ty = Float64(tw["ty"])
            x = sx + (tx - sx) * eased
            y = sy + (ty - sy) * eased
            if ent !== nothing && ent.transform !== nothing
                ent.transform.position = Math.Vector2f(x, y)
            end
            if u < 1.0
                all_done = false
            end
        end
        if all_done
            for tw in this.queue_layout_tweens
                ent = tw["entity"]
                if ent !== nothing && ent.transform !== nothing
                    ent.transform.position = Math.Vector2f(Float64(tw["tx"]), Float64(tw["ty"]))
                end
            end
            empty!(this.queue_layout_tweens)
            this.queue_layout_busy = false
        end
    end

    """
    After piece(s) leave the queue for the grid we have N existing `_Queue` entities
    and `queue_length` logical pieces.  Shift existing entities right (rightmost starts
    first) and slide (queue_length - N) new pieces in from off-screen left, all with a
    staggered ease-out (cubic, no overshoot).
    """
    function start_queue_layout_animation(this)::Bool
        if !this.queue_layout_anim_next_refresh || this.queue_layout_busy
            return false
        end
        animating_entity_ids = Set()
        for animation_data in this.animating_pieces
            if haskey(animation_data, "entity") && animation_data["entity"] !== nothing
                push!(animating_entity_ids, animation_data["entity"].id)
            end
        end
        queue_entities = []
        for entity in MAIN.scene.entities
            if occursin("_Queue", entity.name) && !(entity.id in animating_entity_ids)
                push!(queue_entities, entity)
            end
        end
        sort!(queue_entities, by = e -> e.transform.position.x)
        n_existing = length(queue_entities)
        if n_existing == 0 || n_existing >= this.queue_length || length(this.queue_pieces) != this.queue_length
            this.queue_layout_anim_next_refresh = false
            return false
        end
        this.queue_layout_anim_next_refresh = false
        n_new = this.queue_length - n_existing
        # Anchor off-screen spawn to the live leftmost piece so we don't rely on a stale constant
        # (avoids pieces briefly appearing at world origin / wrong side before the tween).
        left_ref_x = Float64(queue_entities[1].transform.position.x)
        off_x = left_ref_x - QUEUE_OFFSCREEN_LEFT_EXTRA
        targets_x = [this.queue_start_x + (i - 1) * this.distance_between_pieces for i in 1:this.queue_length]
        ty = this.queue_start_y
        tweens = Any[]
        cascade = QUEUE_LAYOUT_CASCADE_DELAY
        dur = QUEUE_LAYOUT_DURATION
        step = 0
        for j in n_existing:-1:1
            ent = queue_entities[j]
            sx = Float64(ent.transform.position.x)
            sy = Float64(ent.transform.position.y)
            tx = targets_x[n_new + j]
            push!(tweens, Dict{String, Any}(
                "entity" => ent,
                "sx" => sx, "sy" => sy, "tx" => tx, "ty" => ty,
                "delay" => step * cascade, "elapsed" => 0.0, "duration" => dur,
            ))
            step += 1
        end
        for k in n_new:-1:1
            new_piece_data = this.queue_pieces[k]
            new_ent = place_item(this, new_piece_data, off_x, ty)
            if new_ent !== nothing && new_ent.transform !== nothing
                new_ent.transform.position = Math.Vector2f(Float64(off_x), Float64(ty))
            end
            push!(tweens, Dict{String, Any}(
                "entity" => new_ent,
                "sx" => off_x, "sy" => ty, "tx" => targets_x[k], "ty" => ty,
                "delay" => step * cascade, "elapsed" => 0.0, "duration" => dur,
            ))
            step += 1
        end
        this.queue_layout_tweens = tweens
        this.queue_layout_busy = true
        return true
    end

    """
    Full reroll / initial fill: every slot is new. Cascade from the right (slot 7 first);
    all pieces spawn off-screen left and ease into place.
    """
    function start_queue_full_layout_animation(this)::Bool
        if !this.queue_layout_anim_full_refresh || this.queue_layout_busy
            return false
        end
        if length(this.queue_pieces) != this.queue_length
            this.queue_layout_anim_full_refresh = false
            return false
        end
        this.queue_layout_anim_full_refresh = false
        clean_queue_display(this)
        off_x = Float64(this.queue_start_x) - QUEUE_OFFSCREEN_LEFT_EXTRA
        targets_x = [Float64(this.queue_start_x) + (i - 1) * this.distance_between_pieces for i in 1:this.queue_length]
        ty = Float64(this.queue_start_y)
        tweens = Any[]
        cascade = QUEUE_LAYOUT_CASCADE_DELAY
        dur = QUEUE_LAYOUT_DURATION
        step = 0
        for k in this.queue_length:-1:1
            piece = this.queue_pieces[k]
            new_ent = place_item(this, piece, off_x, ty)
            if new_ent !== nothing && new_ent.transform !== nothing
                new_ent.transform.position = Math.Vector2f(off_x, ty)
            end
            push!(tweens, Dict{String, Any}(
                "entity" => new_ent,
                "sx" => off_x, "sy" => ty,
                "tx" => targets_x[k], "ty" => ty,
                "delay" => step * cascade, "elapsed" => 0.0, "duration" => dur,
            ))
            step += 1
        end
        this.queue_layout_tweens = tweens
        this.queue_layout_busy = true
        return true
    end

    function update_queue_display(this)
        if this.queue_layout_busy
            finish_queue_layout_animations_immediate!(this)
        end
        # While queue-to-grid animations are in flight, use the slot-aware version
        # so we leave room for the cascade layout animation when they finish.
        if !isempty(this.animating_pieces)
            update_queue_display_immediate(this)
            return
        end
        if this.queue_layout_anim_full_refresh && length(this.queue_pieces) == this.queue_length
            if start_queue_full_layout_animation(this)
                return
            end
        end
        @debug "updating queue display"
        queue_pos_start_x = this.queue_start_x
        queue_pos_start_y = this.queue_start_y

        clean_queue_display(this)
        x_counter = -2
        for piece in this.queue_pieces
            place_item(this, piece, queue_pos_start_x, queue_pos_start_y)

            queue_pos_start_x += this.distance_between_pieces
        end
        
    end

    function update_queue_display_immediate(this)
        @debug "updating queue display immediately (preserving animations)"
        @debug "updating queue display immediately (preserving animations)"

        if this.queue_layout_busy
            return
        end
        
        # Get count of pieces currently animating
        animating_count = length(this.animating_pieces)

        if this.queue_layout_anim_next_refresh && animating_count == 0
            if start_queue_layout_animation(this)
                return
            end
        end
        
        # Only update the static (non-animating) part of the queue
        queue_pos_start_x = this.queue_start_x
        queue_pos_start_y = this.queue_start_y
        
        # Clean only non-animating queue pieces
        clean_queue_display(this)
        
        # Place new queue pieces, accounting for the pieces that are animating
        # We want to show queue_length - animating_count pieces
        # Ensure we don't attempt to display a negative number of pieces (can happen if
        # animating_count temporarily exceeds queue_length).  Using `max` guarantees the
        # result is never negative while still respecting available queue slots.
        available_slots = max(0, this.queue_length - animating_count)
        display_count = min(length(this.queue_pieces), available_slots)
        
        for i in 1:display_count
            piece = this.queue_pieces[i]
            place_item(this, piece, queue_pos_start_x, queue_pos_start_y)
            queue_pos_start_x += this.distance_between_pieces
        end
        
        @debug "Updated queue display: showing $display_count pieces, $animating_count animating"
    end

    function place_item(this,item, placementX, placementY, offsetY = 0)
        if this.gridController === nothing
            this.gridController = this.parent.scripts[3]
        end
        crop = Math.Vector4(0, 0, 0, 0)

        newItem = JulGame.EntityModule.Entity("$(item.key)_Queue")
        try
            newItem.sprite = JulGame.SpriteModule.InternalSprite(newItem, JulGame.UserGlobals["Module"].get_asset_path("piece", lowercase(split(item.key, "_")[2])), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 125, layer = 2)
        catch e
            @error first(string(e), 1000)
            newItem.sprite = JulGame.SpriteModule.InternalSprite(newItem, JulGame.UserGlobals["Module"].get_asset_path("piece", "error"), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 8, layer = 2)
        end

        newItem = JulGame.create_entity(newItem)
        newItem.transform.position = Math.Vector2f(placementX, placementY + offsetY)
        newItem.transform.scale = this.queue_piece_scale
    
        @debug("Placed $(newItem.name) at $(placementX), $(placementY + offsetY) successfully (Queue)")
        return newItem
    end
    
    function handle_reroll(this, info)
        battleManager = this.parent.scripts[4]
        if battleManager.currentState != battleManager.battleStates[:playerTurn]
            @debug "not player turn, cannot reroll queue"
            return
        end
        if battleManager.moveCount < 1
            @debug "no moves left, cannot reroll queue"
            return
        end
        if this.queue_layout_busy
            finish_queue_layout_animations_immediate!(this)
        end
        this.queue_layout_anim_next_refresh = false
        this.queue_layout_anim_full_refresh = true
        # clear entire queue and then refill it. all of the pieces cleared are discarded
        @debug "rerolling queue"
        items_to_destroy = []
        for entity in MAIN.scene.entities
            if occursin("_Queue", entity.name)
                @debug "destroying $(entity.name) in queue display"
                push!(items_to_destroy, entity)
            end
        end
        for entity in items_to_destroy
            JulGame.destroy_entity(MAIN, entity)
        end
        this.queue_pieces = []
        globals = JulGame.UserGlobals["Module"]
        persistentStateManager = globals.get_data_manager().persistent_state_manager
        
        refill_queue(this, persistentStateManager)
        update_queue_display(this)
        # battleManager.currentState = battleManager.battleStates[:processTurn]
        
        # Track reroll usage in analytics
        try
            Globals.AnalyticsModule.track_action(:reroll_used)
        catch e
            @debug "Could not track reroll usage: $e"
        end
        
        @debug "Queue has been rerolled and updated."
    end
    
    """
    Start return animation for a piece that was dropped outside the board
    """
    function start_return_animation(this, entity, target_position::Math.Vector2f)
        if entity === nothing
            return
        end
        
        this.returning_piece_entity = entity
        this.return_start_position = Math.Vector2f(entity.transform.position.x, entity.transform.position.y)
        this.return_target_position = target_position
        this.return_animation_time = 0.0
        this.is_returning = true
        
        @debug "Starting return animation from ($(this.return_start_position.x), $(this.return_start_position.y)) to ($(target_position.x), $(target_position.y))"
    end
    
    """
    Update return animation
    """
    function update_return_animation(this, deltaTime)
        if !this.is_returning || this.returning_piece_entity === nothing
            return
        end
        
        # Update animation time
        this.return_animation_time += deltaTime
        progress = min(this.return_animation_time / this.return_animation_duration, 1.0)
        
        # Apply easing (ease_out_back for a nice springy feel)
        eased_progress = ease_out_back(progress)
        
        # Interpolate position
        current_x = this.return_start_position.x + (this.return_target_position.x - this.return_start_position.x) * eased_progress
        current_y = this.return_start_position.y + (this.return_target_position.y - this.return_start_position.y) * eased_progress
        
        # Update entity position
        this.returning_piece_entity.transform.position = Math.Vector2f(current_x, current_y)
        
        # Check if animation is complete
        if progress >= 1.0
            # Animation complete - snap to final position and reset
            this.returning_piece_entity.transform.position = this.return_target_position
            
            # Reset layer
            if this.returning_piece_entity.sprite !== nothing
                this.returning_piece_entity.sprite.layer = 2
            end
            
            # Reset scale to normal (in case it was scaled up by hover effects)
            if this.returning_piece_entity.transform !== nothing
                # Get the original scale from queue_piece_scale
                this.returning_piece_entity.transform.scale = this.queue_piece_scale
            end
            
            # Reset rotation (in case it was rotated by hover effects)
            if this.returning_piece_entity.sprite !== nothing
                this.returning_piece_entity.sprite.rotation = 0.0
            end
            
            # Clear return animation state
            this.is_returning = false
            this.returning_piece_entity = nothing
            
            # Now clear the dragged piece data
            this.dragged_piece_entity = nothing
            this.dragged_piece_data = nothing
            this.dragged_piece_index = -1
            
            @debug "Return animation complete"
        end
    end
end
