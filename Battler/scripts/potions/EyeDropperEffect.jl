module EyeDropperEffectModule
    using JulGame
    include("../utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    """
    Execute the eye dropper potion effect
    This allows the player to select a piece type on the board and clears ALL identical pieces
    """
    function execute_eyedropper_effect(battle_potion_manager, slot_index::Int)
        @debug("Starting eye dropper selection mode")
        
        # Set the battle potion manager into eye dropper selection mode
        battle_potion_manager.isEyeDropperSelectionMode = true
        battle_potion_manager.eyeDropperSlotIndex = slot_index
        
        # Show instruction text
        DisplayTextModule.display_text(
            "eyedropper_instruction",
            "Select a piece type to clear ALL identical pieces ";
            fontSize = 18,
            anchor = :center,
            lifetime = 5000,
            color = (255, 255, 255, 255),
            position = JulGame.Math.Vector2(640, 100)
        )
        
        @debug("Eye dropper selection mode activated")
    end

    """
    Handle eye dropper piece selection logic
    Called from the main potion manager update loop
    """
    function handle_eyedropper_selection(battle_potion_manager)
        # Handle ESC to cancel eye dropper selection
        if JulGame.InputModule.get_button_pressed("ESCAPE")
            cancel_eyedropper_selection(battle_potion_manager)
            return
        end
        
        # Get mouse position and convert to grid coordinates using GridController logic
        mousePos = MAIN.input.mousePositionWorld
        gridPiece = Scripts.GridControllerModule.calculate_grid_piece_at_mouse_position(battle_potion_manager.gridController, mousePos)
        
        # Check if mouse is in grid bounds and hovering over a piece
        if gridPiece !== nothing
            # Update highlight for the currently hovered piece type
            update_eyedropper_highlights(battle_potion_manager, gridPiece.name)
            
            # Handle click to confirm selection
            if JulGame.InputModule.get_mouse_button_pressed(1)
                execute_eyedropper_clear(battle_potion_manager, gridPiece.name)
            end
        else
            # Mouse outside grid or over empty space, clear highlights
            clear_eyedropper_highlights(battle_potion_manager)
        end
    end

    """
    Update highlights for all pieces of the selected type
    """
    function update_eyedropper_highlights(battle_potion_manager, piece_type::String)
        # Clear previous highlights first
        clear_eyedropper_highlights(battle_potion_manager)
        
        # Find all pieces of the same type and highlight them
        for x in 1:battle_potion_manager.gridController.gridWidth
            for y in 1:battle_potion_manager.gridController.gridHeight
                piece = battle_potion_manager.gridController.gridPieces[x, y]
                if piece !== nothing && piece.name == piece_type
                    # Create highlight entity
                    crop = JulGame.Math.Vector4(0, 0, 0, 0)
                    
                    highlight_entity = JulGame.EntityModule.Entity("EyeDropper_Highlight")
                    highlight_entity.sprite = JulGame.SpriteModule.InternalSprite(
                        highlight_entity, 
                        "highlight.png", 
                        crop, 
                        false, 
                        (100, 255, 100, 180),  # Green-tinted highlight for eye dropper
                        false; 
                        pixelsPerUnit = 150, 
                        layer = 4
                    )
                    
                    highlight_entity = JulGame.create_entity(highlight_entity)
                    
                    # Convert grid coordinates to world coordinates for positioning
                    world_x = Scripts.GridControllerModule.calculate_placement_x(battle_potion_manager.gridController, x)
                    world_y = Scripts.GridControllerModule.calculate_placement_y(battle_potion_manager.gridController, y)
                    highlight_entity.transform.position = JulGame.Math.Vector2f(world_x, world_y)
                    highlight_entity.transform.scale = JulGame.Math.Vector2f(battle_potion_manager.gridController.gridCellWidth, battle_potion_manager.gridController.gridCellHeight)
                end
            end
        end
    end

    """
    Clear all eye dropper highlight entities
    """
    function clear_eyedropper_highlights(battle_potion_manager)
        # Remove all eye dropper highlight entities
        for entity in JulGame.SceneModule.get_entities_by_name(MAIN.scene, "EyeDropper_Highlight")
            JulGame.destroy_entity(MAIN, entity)
        end
    end

    """
    Execute the eye dropper clear effect - remove all pieces of the selected type
    """
    function execute_eyedropper_clear(battle_potion_manager, piece_type::String)
        @debug("Executing eye dropper clear for piece type: $piece_type")
        
        # Collect all pieces of the selected type
        pieces_to_clear = []
        for x in 1:battle_potion_manager.gridController.gridWidth
            for y in 1:battle_potion_manager.gridController.gridHeight
                piece = battle_potion_manager.gridController.gridPieces[x, y]
                if piece !== nothing && piece.name == piece_type
                    push!(pieces_to_clear, piece)
                end
            end
        end
        
        if !isempty(pieces_to_clear)
            @debug("Eye dropper will clear $(length(pieces_to_clear)) pieces of type $piece_type")
            
            # Use the grid controller's search_for_matches function to activate the pieces
            # This will handle the match logic and effects properly
            Scripts.GridControllerModule.search_for_matches(battle_potion_manager.gridController, pieces_to_clear, true, false, false, false)
        else
            @debug("No pieces of type $piece_type found on the board")
        end
        
        # Remove the used potion from inventory
        deleteat!(battle_potion_manager.user.potions, battle_potion_manager.eyeDropperSlotIndex)
        
        # End eye dropper selection mode
        cancel_eyedropper_selection(battle_potion_manager)
        
        @debug("Eye dropper effect executed successfully")
    end

    """
    Cancel eye dropper selection mode
    """
    function cancel_eyedropper_selection(battle_potion_manager)
        @debug("Cancelling eye dropper selection")
        battle_potion_manager.isEyeDropperSelectionMode = false
        battle_potion_manager.eyeDropperSlotIndex = 0
        clear_eyedropper_highlights(battle_potion_manager)
    end

    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end

    # Export functions that need to be called from the main potion manager
    export execute_eyedropper_effect, handle_eyedropper_selection, cancel_eyedropper_selection

end 