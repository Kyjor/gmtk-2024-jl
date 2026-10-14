module AbilityManagerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts

    mutable struct AbilityManager
        parent::Any # Reference to the entity that this script is attached to
        
        # Ability system
        abilityUsesThisTurn::Dict{String, Int}  # Track ability uses per turn
        maxAbilityUsesPerTurn::Dict{String, Int}  # Max uses per turn for each ability
        
        # Selection states for different abilities
        isDetonatorSelectionMode::Bool
        detonatorSelectedRowCol::Union{Nothing, Tuple{String, Int}}  # ("row"|"column", index)
        
        isHocusPocusMode::Bool
        
        # Nail system
        isNailSelectionMode::Bool
        currentNailedPiece::Union{Nothing, Any}  # Currently nailed piece (only one at a time)

        # Turns left before Chessboard can be used again. 0 means ready.
        chessboardCooldown::Int
        
        # UI references
        battleManager
        gridController
        queueManager
        user

        # Skip rebuilding Hocus empty-cell overlays when the grid layout is unchanged (UInt64(0) = force rebuild).
        hocus_pocus_empty_signature::UInt64
        
        function AbilityManager()
            this = new()
            
            this.abilityUsesThisTurn = Dict{String, Int}()
            this.maxAbilityUsesPerTurn = Dict{String, Int}(
                "TREASURE_DETONATOR" => 1,
                "TREASURE_HOCUSPOCUS" => 1,
                "TREASURE_NAIL" => 1
            )
            
            this.isDetonatorSelectionMode = false
            this.detonatorSelectedRowCol = nothing
            
            this.isHocusPocusMode = false
            
            this.isNailSelectionMode = false
            this.currentNailedPiece = nothing
            this.chessboardCooldown = 0

            this.hocus_pocus_empty_signature = UInt64(0)
            
            return this
        end
    end

    function _hocus_empty_grid_signature(grid)::UInt64
        h = UInt64(1)
        for x in 1:grid.gridWidth
            for y in 1:grid.gridHeight
                if grid.gridPieces[x, y] === nothing
                    h = hash(x, h)
                    h = hash(y, h)
                end
            end
        end
        return h
    end

    function JulGame.initialize(this::AbilityManager)
        # Get references to other managers
        this.battleManager = this.parent.scripts[4]  # BattleManager is script 4
        this.gridController = this.parent.scripts[3]  # GridController is script 3
        this.queueManager = this.parent.scripts[6]   # QueueManager is script 6
        
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()
        sync_hocus_pocus_if_owned(this)
        Scripts.SealedEnvelopeModule.reset!()
    end

    function JulGame.update(this::AbilityManager, deltaTime)
        sync_hocus_pocus_if_owned(this)
        Scripts.SealedEnvelopeModule.note_battle_state!(this.battleManager)
        globals = JulGame.UserGlobals["Module"]
        has_hocus = globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_HOCUSPOCUS)
        # Selection modes must not share the same elseif chain as passive Hocus — nail/detonator must still run.
        if this.isDetonatorSelectionMode
            handle_detonator_selection(this)
        elseif this.isNailSelectionMode
            handle_nail_selection(this)
        end
        if has_hocus && !this.isDetonatorSelectionMode && !this.isNailSelectionMode
            handle_hocus_pocus_mode(this)
        elseif has_hocus
            clear_hocus_pocus_highlights(this)
        end
    end

    function JulGame.on_shutdown(this::AbilityManager)
    end

    """
    Reset ability uses at the start of each turn
    """
    function reset_turn_abilities(this)
        empty!(this.abilityUsesThisTurn)
        this.isDetonatorSelectionMode = false
        this.isNailSelectionMode = false
        this.detonatorSelectedRowCol = nothing
        if this.chessboardCooldown > 0
            this.chessboardCooldown -= 1
        end
        sync_hocus_pocus_if_owned(this)
    end

    """
    Refill every active item (Active Battery). Selection modes are left alone.
    """
    function recharge_all!(this)
        empty!(this.abilityUsesThisTurn)
        this.chessboardCooldown = 0
        Scripts.SealedEnvelopeModule.recharge!()
    end

    """
    Clear hocus state when the treasure is gone. Drag/queue use `has_treasure`; `isHocusPocusMode` is not used to gate other abilities.
    """
    function sync_hocus_pocus_if_owned(this)
        globals = JulGame.UserGlobals["Module"]
        if !globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_HOCUSPOCUS)
            this.isHocusPocusMode = false
            clear_hocus_pocus_highlights(this)
        end
    end

    """
    Check if an ability can be used (has uses remaining and player has the treasure)
    """
    function can_use_ability(this::AbilityManager, treasure)::Bool
        globals = JulGame.UserGlobals["Module"]
        
        # Check if player has the treasure
        if !globals.UserModule.has_treasure(treasure)
            return false
        end
        
        # Special case: Hocus Pocus is always available if owned
        if treasure == globals.TreasuresModule.TREASURE_HOCUSPOCUS
            return true
        end

        if treasure == globals.TreasuresModule.TREASURE_CHESSBOARD
            return this.chessboardCooldown <= 0
        end

        if treasure == globals.TreasuresModule.TREASURE_SEALEDENVELOPE
            return Scripts.SealedEnvelopeModule.can_activate(this.battleManager)
        end
        
        treasure_struct = globals.TreasuresModule.ALL_TREASURES[treasure]
        # Check if ability has uses remaining
        uses_this_turn = get(this.abilityUsesThisTurn, treasure_struct.key, 0)
        max_uses = get(this.maxAbilityUsesPerTurn, treasure_struct.key, 0)
        
        return uses_this_turn < max_uses
    end

    """
    Use an ability (increment use counter)
    """
    function use_ability(this, treasure)
        globals = JulGame.UserGlobals["Module"]
        
        # Special case: Hocus Pocus has unlimited uses, so we don't track usage
        if treasure == globals.TreasuresModule.TREASURE_HOCUSPOCUS
            @debug "Used Hocus Pocus (unlimited uses)"
            return true
        end
        
        if can_use_ability(this, treasure)
            treasure_struct = globals.TreasuresModule.ALL_TREASURES[treasure]
            this.abilityUsesThisTurn[treasure_struct.key] = get(this.abilityUsesThisTurn, treasure_struct.key, 0) + 1
            globals.RunRecorderModule.note_ability!(treasure_struct.key)
            @debug "Used ability $(treasure_struct.key), uses this turn: $(this.abilityUsesThisTurn[treasure_struct.key])"
            return true
        end
        return false
    end

    """
    Activate detonator ability - enter selection mode
    """
    function activate_detonator(this)
        globals = JulGame.UserGlobals["Module"]
        if !can_use_ability(this, globals.TreasuresModule.TREASURE_DETONATOR)
            @debug "Cannot use detonator ability"
            return false
        end
        
        @debug "Activating detonator ability"
        this.isDetonatorSelectionMode = true
        this.detonatorSelectedRowCol = nothing
        
        # Show instruction text
        DisplayTextModule.display_text(
            "detonator_instruction",
            "Select a row or column to destroy ";
            fontSize = 18,
            anchor = :center,
            lifetime = 5000,
            color = (255, 255, 255, 255),
            position = JulGame.Math.Vector2(640, 100)
        )
        
        return true
    end

    """
    Handle detonator selection logic
    """
    function handle_detonator_selection(this)
        # Handle ESC to cancel
        if JulGame.InputModule.get_button_pressed("ESCAPE")
            cancel_detonator_selection(this)
            return
        end
        
        # Get mouse position
        mousePos = MAIN.input.mousePositionWorld
        
        # Check if mouse is in grid bounds
        if mousePos.x >= this.gridController.gridStartX && 
           mousePos.x <= this.gridController.gridStartX + this.gridController.gridWidth * this.gridController.gridCellWidth &&
           mousePos.y >= this.gridController.gridStartY && 
           mousePos.y <= this.gridController.gridStartY + this.gridController.gridHeight * this.gridController.gridCellHeight
            
            # Convert to grid coordinates
            localX = (mousePos.x - this.gridController.gridStartX) / this.gridController.gridCellWidth
            localY = (mousePos.y - this.gridController.gridStartY) / this.gridController.gridCellHeight
            gridX = convert(Int, floor(localX)) + 1
            gridY = convert(Int, floor(localY)) + 1
            
            # Clamp to grid bounds
            gridX = clamp(gridX, 1, this.gridController.gridWidth)
            gridY = clamp(gridY, 1, this.gridController.gridHeight)
            
            # Determine if closer to row or column selection
            # Check distance from edges to determine row vs column selection
            distFromLeft = localX
            distFromRight = this.gridController.gridWidth - localX
            distFromTop = localY
            distFromBottom = this.gridController.gridHeight - localY
            
            # If close to left/right edges, select column; if close to top/bottom, select row
            new_selection = nothing
            if min(distFromLeft, distFromRight) < min(distFromTop, distFromBottom)
                new_selection = ("column", gridX)
            else
                new_selection = ("row", gridY)
            end
            
            # Update selection if changed
            if this.detonatorSelectedRowCol != new_selection
                this.detonatorSelectedRowCol = new_selection
                update_detonator_highlights(this)
            end
            
            # Handle click to confirm
            if JulGame.InputModule.get_mouse_button_pressed(1)
                execute_detonator(this)
            end
        else
            # Mouse outside grid, clear selection
            if this.detonatorSelectedRowCol !== nothing
                this.detonatorSelectedRowCol = nothing
                clear_detonator_highlights(this)
            end
        end
    end

    """
    Update detonator highlights for selected row/column
    """
    function update_detonator_highlights(this)
        clear_detonator_highlights(this)
        
        if this.detonatorSelectedRowCol === nothing
            return
        end
        
        selection_type, index = this.detonatorSelectedRowCol
        
        if selection_type == "row"
            # Highlight entire row
            for x in 1:this.gridController.gridWidth
                create_detonator_highlight(this, x, index)
            end
        elseif selection_type == "column"
            # Highlight entire column
            for y in 1:this.gridController.gridHeight
                create_detonator_highlight(this, index, y)
            end
        end
    end

    """
    Create a single detonator highlight at grid position
    """
    function create_detonator_highlight(this, gridX::Int, gridY::Int)
        crop = JulGame.Math.Vector4(0, 0, 0, 0)
        
        highlight_entity = JulGame.EntityModule.Entity("Detonator_Highlight")
        highlight_entity.sprite = JulGame.SpriteModule.InternalSprite(
            highlight_entity,
            "highlight.png",
            crop,
            false,
            (255, 200, 0, 180),  # Orange highlight for detonator
            false;
            pixelsPerUnit = 150,
            layer = 4
        )
        
        highlight_entity = JulGame.create_entity(highlight_entity)
        
        # Convert grid coordinates to world coordinates
        world_x = Scripts.GridControllerModule.calculate_placement_x(this.gridController, gridX)
        world_y = Scripts.GridControllerModule.calculate_placement_y(this.gridController, gridY)
        highlight_entity.transform.position = JulGame.Math.Vector2f(world_x, world_y)
        highlight_entity.transform.scale = JulGame.Math.Vector2f(this.gridController.gridCellWidth, this.gridController.gridCellHeight)
    end

    """
    Clear all detonator highlight entities
    """
    function clear_detonator_highlights(this)
        Scripts.GridControllerModule.remove_detonator_highlights()
    end

    """
    Execute detonator ability
    """
    function execute_detonator(this)
        globals = JulGame.UserGlobals["Module"]
        if this.detonatorSelectedRowCol === nothing
            return
        end
        
        selection_type, index = this.detonatorSelectedRowCol
        @debug "Executing detonator on $(selection_type) $(index)"
        
        # Collect pieces to destroy
        pieces_to_destroy = []
        
        if selection_type == "row"
            for x in 1:this.gridController.gridWidth
                piece = this.gridController.gridPieces[x, index]
                if piece !== nothing
                    push!(pieces_to_destroy, piece)
                end
            end
        elseif selection_type == "column"
            for y in 1:this.gridController.gridHeight
                piece = this.gridController.gridPieces[index, y]
                if piece !== nothing
                    push!(pieces_to_destroy, piece)
                end
            end
        end
        
        if !isempty(pieces_to_destroy)
            @debug "Detonator destroying $(length(pieces_to_destroy)) pieces"
            # Use the grid controller's search_for_matches to handle the destruction
            Scripts.GridControllerModule.search_for_matches(
                this.gridController,
                pieces_to_destroy,
                true,
                false,
                true,
                false,
            )
        end

        try
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(),
                globals.get_asset_path("sfx", "potionbombhuge"),
                false, 1.0, 0, 1,
            )
        catch e
            @debug "detonator explosion sfx: $e"
        end
        
        # Mark ability as used
        use_ability(this, globals.TreasuresModule.TREASURE_DETONATOR)
        
        # End selection mode
        cancel_detonator_selection(this)
        
        @debug "Detonator ability executed successfully"
    end

    """
    Cancel detonator selection mode
    """
    function cancel_detonator_selection(this)
        @debug "Cancelling detonator selection"
        this.isDetonatorSelectionMode = false
        this.detonatorSelectedRowCol = nothing
        clear_detonator_highlights(this)
    end

    """
    Activate hocus pocus ability - enter drag mode
    """
    function activate_hocus_pocus(this)
        globals = JulGame.UserGlobals["Module"]
        @debug "Hocus pocus is always on when owned"
        if !can_use_ability(this, globals.TreasuresModule.TREASURE_HOCUSPOCUS)
            @debug "Cannot use hocus pocus ability"
            return false
        end
        sync_hocus_pocus_if_owned(this)
        return true
    end

    """A potion (Bomb, Eye Dropper) is waiting for its board target; starting an active would cancel it."""
    function potion_targeting_active(this)::Bool
        bpm = this.battleManager.battlePotionManager
        return bpm !== nothing && (bpm.isBombSelectionMode || bpm.isEyeDropperSelectionMode)
    end

    """
    Unified ability activation function - routes to specific ability handlers
    """
    function activate_ability(this, treasure_key::String)
        Scripts.TutorialModule.blocks_side_actions() && return false
        potion_targeting_active(this) && return false
        globals = JulGame.UserGlobals["Module"]
        
        if treasure_key == globals.TreasuresModule.TREASURE_HOCUSPOCUS
            return activate_hocus_pocus(this)
        elseif treasure_key == globals.TreasuresModule.TREASURE_DETONATOR
            return activate_detonator(this)
        elseif treasure_key == globals.TreasuresModule.TREASURE_NAIL
            return activate_nail(this)
        elseif treasure_key == globals.TreasuresModule.TREASURE_CHESSBOARD
            return activate_chessboard(this)
        elseif treasure_key == globals.TreasuresModule.TREASURE_SEALEDENVELOPE
            used = Scripts.SealedEnvelopeModule.activate!(this.battleManager)
            used && globals.RunRecorderModule.note_ability!(treasure_key)
            return used
        else
            @warn "Unknown ability treasure key: $treasure_key"
            return false
        end
    end
    
    const CHESSBOARD_RECHARGE_TURNS = 2

    """
    Remove every piece on odd squares, or every piece on even squares. Recharges after two turns.
    """
    function activate_chessboard(this)
        globals = JulGame.UserGlobals["Module"]
        if !can_use_ability(this, globals.TreasuresModule.TREASURE_CHESSBOARD)
            @debug "Cannot use chessboard ability"
            return false
        end
        if this.battleManager === nothing ||
           this.battleManager.currentState != this.battleManager.battleStates[:playerTurn]
            return false
        end

        grid = this.gridController
        remove_odd = rand(Bool)
        pieces = Any[]
        for x in 1:grid.gridWidth
            for y in 1:grid.gridHeight
                piece = grid.gridPieces[x, y]
                piece === nothing && continue
                isodd(x + y) == remove_odd || continue
                is_piece_nailed(piece) && continue
                push!(pieces, piece)
            end
        end

        if !isempty(pieces)
            Scripts.GridControllerModule.search_for_matches(
                grid,
                pieces,
                true,
                false,
                true,
                false,
            )
        end

        this.chessboardCooldown = CHESSBOARD_RECHARGE_TURNS
        globals.RunRecorderModule.note_ability!(globals.TreasuresModule.TREASURE_CHESSBOARD)
        @debug "Chessboard removed $(remove_odd ? "odd" : "even") squares ($(length(pieces)) pieces)"
        return true
    end

    """
    Handle hocus pocus mode logic
    """
    function handle_hocus_pocus_mode(this)
        # Only show empty-cell highlights on the player's turn — avoids redraw noise during cascades / AI
        if this.battleManager === nothing ||
           this.battleManager.currentState != this.battleManager.battleStates[:playerTurn]
            clear_hocus_pocus_highlights(this)
            return
        end
        # Drag/drop is handled by QueueManager.handle_piece_drop
        show_hocus_pocus_feedback(this)
    end
    
    """
    Show visual feedback for hocus pocus mode
    """
    function show_hocus_pocus_feedback(this)
        sig = _hocus_empty_grid_signature(this.gridController)
        if sig == this.hocus_pocus_empty_signature
            return
        end
        clear_hocus_pocus_highlights(this)
        for x in 1:this.gridController.gridWidth
            for y in 1:this.gridController.gridHeight
                if this.gridController.gridPieces[x, y] === nothing
                    create_hocus_pocus_highlight(this, x, y)
                end
            end
        end
        this.hocus_pocus_empty_signature = sig
    end
    
    """
    Create highlight for valid hocus pocus drop zone
    """
    function create_hocus_pocus_highlight(this, gridX::Int, gridY::Int)
        crop = JulGame.Math.Vector4(0, 0, 0, 0)
        
        highlight_entity = JulGame.EntityModule.Entity("HocusPocus_Highlight")
        highlight_entity.sprite = JulGame.SpriteModule.InternalSprite(
            highlight_entity,
            "highlight.png",
            crop,
            false,
            (100, 255, 255, 120),  # Cyan highlight for hocus pocus
            false;
            pixelsPerUnit = 150,
            layer = 3
        )
        
        highlight_entity = JulGame.create_entity(highlight_entity)
        
        # Convert grid coordinates to world coordinates
        world_x = Scripts.GridControllerModule.calculate_placement_x(this.gridController, gridX)
        world_y = Scripts.GridControllerModule.calculate_placement_y(this.gridController, gridY)
        highlight_entity.transform.position = JulGame.Math.Vector2f(world_x, world_y)
        highlight_entity.transform.scale = JulGame.Math.Vector2f(this.gridController.gridCellWidth, this.gridController.gridCellHeight)
    end
    
    """
    Clear all hocus pocus highlight entities
    """
    function clear_hocus_pocus_highlights(this)
        Scripts.GridControllerModule.remove_hocus_pocus_highlights()
        this.hocus_pocus_empty_signature = UInt64(0)
    end

    """
    True when nail selection can be opened (spare use, or an active nail to move/remove).
    """
    function can_activate_nail(this)::Bool
        globals = JulGame.UserGlobals["Module"]
        return can_use_ability(this, globals.TreasuresModule.TREASURE_NAIL) ||
               has_active_nail(this)
    end

    function has_active_nail(this)::Bool
        return this.currentNailedPiece !== nothing && is_piece_nailed(this.currentNailedPiece)
    end

    """
    Clear the active nail without placing a new one.
    """
    function clear_current_nail!(this)
        piece = this.currentNailedPiece
        if piece !== nothing &&
           piece.scripts !== nothing &&
           length(piece.scripts) > 0 &&
           hasfield(typeof(piece.scripts[1]), :isNailed)
            piece.scripts[1].isNailed = false
            remove_nail_visual(this, piece)
        elseif piece !== nothing
            remove_nail_visual(this, piece)
        end
        this.currentNailedPiece = nothing
        @debug "Cleared active nail"
    end

    """
    Activate nail ability - enter selection mode
    """
    function activate_nail(this)
        globals = JulGame.UserGlobals["Module"]
        if !can_activate_nail(this)
            @debug "Cannot use nail ability"
            return false
        end
        
        @debug "Activating nail ability"
        this.isNailSelectionMode = true
        
        instruction = has_active_nail(this) ?
            "Select a piece to nail, or click the nailed piece to remove" :
            "Select a piece to nail to the board"
        DisplayTextModule.display_text(
            "nail_instruction",
            instruction;
            fontSize = 24,
            anchor = :centerBottom,
            lifetime = 5000,
            color = (255, 200, 0, 255)
        )
        
        return true
    end

    """
    Handle nail selection logic
    """
    function handle_nail_selection(this)
        # Handle ESC to cancel
        if JulGame.InputModule.get_button_pressed("ESCAPE")
            cancel_nail_selection(this)
            return
        end
        
        # Get mouse position and check for piece selection
        mousePos = MAIN.input.mousePositionWorld
        gridPiece = Scripts.GridControllerModule.calculate_grid_piece_at_mouse_position(this.gridController, mousePos)
        
        # Handle click to select piece
        if JulGame.InputModule.get_mouse_button_pressed(1) && gridPiece !== nothing
            execute_nail(this, gridPiece)
        end
    end

    """
    Execute nail ability on selected piece (or remove if that piece is already nailed).
    """
    function execute_nail(this, target_piece)
        @debug "Executing nail on piece: $(target_piece.name)"
        globals = JulGame.UserGlobals["Module"]

        # Clicking the active nail removes it (free; does not spend a use).
        if this.currentNailedPiece === target_piece && is_piece_nailed(target_piece)
            clear_current_nail!(this)
            cancel_nail_selection(this)
            DisplayTextModule.display_text(
                "nail_removed",
                "NAIL REMOVED";
                fontSize = 24,
                anchor = :center,
                lifetime = 1500,
                color = (255, 200, 0, 255)
            )
            return
        end

        if !can_use_ability(this, globals.TreasuresModule.TREASURE_NAIL)
            @debug "No nail uses remaining; can only remove the active nail"
            DisplayTextModule.display_text(
                "nail_no_uses",
                "No nail uses left — click the nailed piece to remove";
                fontSize = 20,
                anchor = :centerBottom,
                lifetime = 2500,
                color = (255, 200, 0, 255)
            )
            return
        end
        
        # Remove nail from previous piece if it exists
        if this.currentNailedPiece !== nothing
            clear_current_nail!(this)
        end
        
        # Nail the new piece
        target_piece.scripts[1].isNailed = true
        this.currentNailedPiece = target_piece
        add_nail_visual(this, target_piece)
        globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "activetreasurenail"), false, 1.0, 0, 1);

        # Mark ability as used
        use_ability(this, globals.TreasuresModule.TREASURE_NAIL)
        
        # End selection mode
        cancel_nail_selection(this)
        
        # Show success feedback
        DisplayTextModule.display_text(
            "nail_success",
            "NAILED!";
            fontSize = 24,
            anchor = :center,
            lifetime = 1500,
            color = (255, 200, 0, 255)
        )
        
        @debug "Nail ability executed successfully"
    end

    """
    Add visual indicator to nailed piece
    """
    function add_nail_visual(this, piece)
        globals = JulGame.UserGlobals["Module"]
        crop = JulGame.Math.Vector4(0, 0, 0, 0)
        icon_path = globals.get_asset_path("treasure", "nail")

        nail_entity = JulGame.EntityModule.Entity("Nail_Visual_$(piece.id)")
        nail_entity.sprite = JulGame.SpriteModule.InternalSprite(
            nail_entity,
            icon_path,
            crop,
            false,
            (255, 255, 255, 255),
            false;
            pixelsPerUnit = 150,
            layer = 5  # Higher layer to show on top of piece
        )
        
        nail_entity = JulGame.create_entity(nail_entity)
        nail_entity.transform.position = piece.transform.position
        nail_entity.transform.scale = JulGame.Math.Vector2f(
            this.gridController.gridCellWidth * 0.4,
            this.gridController.gridCellHeight * 0.4,
        )
        
        @debug "Added nail visual to piece at $(piece.transform.position)"
    end

    """
    Remove visual indicator from piece
    """
    function remove_nail_visual(this, piece)
        # Find and destroy the nail visual entity
        nail_visual_name = "Nail_Visual_$(piece.id)"
        for entity in MAIN.scene.entities
            if entity.name == nail_visual_name
                JulGame.destroy_entity(MAIN, entity)
                @debug "Removed nail visual from piece"
                break
            end
        end
    end

    """
    Cancel nail selection mode
    """
    function cancel_nail_selection(this)
        @debug "Cancelling nail selection"
        this.isNailSelectionMode = false
    end

    """
    Check if a piece is nailed (helper function for other systems)
    """
    function is_piece_nailed(piece)
        return piece !== nothing && 
               piece.scripts !== nothing && 
               length(piece.scripts) > 0 && 
               hasfield(typeof(piece.scripts[1]), :isNailed) &&
               piece.scripts[1].isNailed
    end

    # Export functions
    export AbilityManager, reset_turn_abilities, can_use_ability, can_activate_nail, activate_ability, activate_detonator, activate_hocus_pocus, activate_nail, activate_chessboard, is_piece_nailed, clear_current_nail!, cancel_nail_selection

end # module
