module BombEffectModule
    using JulGame
    include("../utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    """
    Execute bomb effect with the specified bomb size
    """
    function execute_bomb_effect(battle_potion_manager, slot_index::Int, bomb_size::Int)
        @debug("Starting bomb selection mode with size $(bomb_size)x$(bomb_size)")
        battle_potion_manager.isBombSelectionMode = true
        battle_potion_manager.bombAreaSize = bomb_size
        battle_potion_manager.bombSlotIndex = slot_index
        battle_potion_manager.selectedBombCenter = nothing
        clear_bomb_highlights(battle_potion_manager)
        
        # Show instruction text
        DisplayTextModule.display_text(
            "bomb_instruction",
            "Select target area for bomb ";
            fontSize = 18,
            anchor = :center,
            lifetime = 3000,
            color = (255, 255, 255, 255),
            position = JulGame.Math.Vector2(640, 100)
        )
    end

    """
    Handle bomb selection logic
    Called from the main potion manager update loop
    """
    function handle_bomb_selection(battle_potion_manager)
        # Handle ESC to cancel bomb selection
        if JulGame.InputModule.get_button_pressed("ESCAPE")
            cancel_bomb_selection(battle_potion_manager)
            return
        end
        
        # Get mouse position and convert to grid coordinates using GridController logic
        mousePos = MAIN.input.mousePositionWorld
        gridPiece = Scripts.GridControllerModule.calculate_grid_piece_at_mouse_position(battle_potion_manager.gridController, mousePos)
        
        # Check if mouse is in grid bounds
        if gridPiece !== nothing
            # Convert world position to grid coordinates
            gridPos = Scripts.GridControllerModule.convert_world_position_to_grid_position(battle_potion_manager.gridController, mousePos)
            center_x = convert(Int, gridPos.x)
            center_y = convert(Int, gridPos.y)
            new_center = (center_x, center_y)
            
            # Update highlights if mouse moved to new position
            if battle_potion_manager.selectedBombCenter != new_center
                battle_potion_manager.selectedBombCenter = new_center
                update_bomb_highlights(battle_potion_manager, center_x, center_y)
            end
            
            # Handle click to confirm bomb placement
            if JulGame.InputModule.get_mouse_button_pressed(1)
                execute_bomb(battle_potion_manager, center_x, center_y)
            end
        else
            # Mouse outside grid, clear highlights
            if battle_potion_manager.selectedBombCenter !== nothing
                battle_potion_manager.selectedBombCenter = nothing
                clear_bomb_highlights(battle_potion_manager)
            end
        end
    end

    """
    Update bomb area highlights
    """
    function update_bomb_highlights(battle_potion_manager, center_x::Int, center_y::Int)
        # Clear previous highlights
        clear_bomb_highlights(battle_potion_manager)
        
        # Calculate bomb area bounds in grid coordinates
        half_size = battle_potion_manager.bombAreaSize ÷ 2
        min_x = max(1, center_x - half_size)
        max_x = min(battle_potion_manager.gridController.gridWidth, center_x + half_size)
        min_y = max(1, center_y - half_size)
        max_y = min(battle_potion_manager.gridController.gridHeight, center_y + half_size)
        
        # Create highlight entities for bomb area
        for x in min_x:max_x
            for y in min_y:max_y
                # Create highlight entity
                crop = JulGame.Math.Vector4(0, 0, 0, 0)
                
                highlight_entity = JulGame.EntityModule.Entity("Bomb_Highlight")
                highlight_entity.sprite = JulGame.SpriteModule.InternalSprite(
                    highlight_entity, 
                    "highlight.png", 
                    crop, 
                    false, 
                    (255, 100, 100, 180),  # Red-tinted highlight for bomb
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
                
                push!(battle_potion_manager.highlightedCells, (x, y))
            end
        end
    end

    """
    Clear all bomb highlight entities
    """
    function clear_bomb_highlights(battle_potion_manager)
        # Remove all bomb highlight entities
        for entity in JulGame.SceneModule.get_entities_by_name(MAIN.scene, "Bomb_Highlight")
            JulGame.destroy_entity(MAIN, entity)
        end
        battle_potion_manager.highlightedCells = []
    end

    """
    Execute the bomb effect at the specified center
    """
    function execute_bomb(battle_potion_manager, center_x::Int, center_y::Int)
        @debug("Executing bomb at center ($center_x, $center_y) with size $(battle_potion_manager.bombAreaSize)x$(battle_potion_manager.bombAreaSize)")
        play_bomb_explosion_sfx(battle_potion_manager.bombAreaSize)
        
        # Calculate bomb area bounds in grid coordinates
        half_size = battle_potion_manager.bombAreaSize ÷ 2
        min_x = max(1, center_x - half_size)
        max_x = min(battle_potion_manager.gridController.gridWidth, center_x + half_size)
        min_y = max(1, center_y - half_size)
        max_y = min(battle_potion_manager.gridController.gridHeight, center_y + half_size)
        
        # Collect all pieces in bomb area
        pieces_to_activate = []
        for x in min_x:max_x
            for y in min_y:max_y
                piece = battle_potion_manager.gridController.gridPieces[x, y]
                if piece !== nothing
                    push!(pieces_to_activate, piece)
                end
            end
        end
        
        if !isempty(pieces_to_activate)
            @debug("Bomb will activate $(length(pieces_to_activate)) pieces")
            Scripts.GridControllerModule.search_for_matches(
                battle_potion_manager.gridController,
                pieces_to_activate,
                true,
                false,
                true,
                false,
            )
        end
        
        # Remove the used potion from inventory
        deleteat!(battle_potion_manager.user.potions, battle_potion_manager.bombSlotIndex)
        
        # End bomb selection mode
        cancel_bomb_selection(battle_potion_manager)
        
        @debug("Bomb executed successfully")
    end

    function play_bomb_explosion_sfx(bomb_size::Int)
        name = if bomb_size <= 3
            "potionbombsmall"
        elseif bomb_size <= 5
            "potionbombmedium"
        else
            "potionbombhuge"
        end
        try
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(),
                globals.get_asset_path("sfx", name),
                false, 1.0, 0, 1,
            )
        catch e
            @debug "bomb explosion sfx: $e"
        end
    end

    """
    Cancel bomb selection mode
    """
    function cancel_bomb_selection(battle_potion_manager)
        @debug("Cancelling bomb selection")
        battle_potion_manager.isBombSelectionMode = false
        battle_potion_manager.bombSlotIndex = 0
        battle_potion_manager.selectedBombCenter = nothing
        clear_bomb_highlights(battle_potion_manager)
    end

    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end

    # Export functions that need to be called from the main potion manager
    export execute_bomb_effect, handle_bomb_selection, cancel_bomb_selection

end 