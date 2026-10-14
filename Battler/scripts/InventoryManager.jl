module InventoryManagerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts
    using ..OverworldFeedbackModule
    include("localization/inventory_strings.jl")
    using .InventoryStringsModule

    const WEIGHT_INCREASE_AMOUNT = 5

    InventoryManagerInstance = nothing
    mutable struct InventoryManager <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        
        # User and state management
        user
        persistentStateManager
        
        # UI state
        isInventoryOpen::Bool
        
        # Scrolling
        scrollOffset::Float64
        scrollSpeed::Float64
        maxItems::Int  # Max items visible at once
        itemsPerRow::Int
        
        # Panel dimensions and positioning
        panelWidth::Int
        panelHeight::Int
        panelX::Int
        panelY::Int
        itemSize::Int
        itemSpacing::Int
        
        # Categories
        selectedCategory::String  # "all", "items", "potions", "treasures"
        
        # Special modes
        deletionMode::Bool  # True when in trash deletion mode
        deletionCost::Int   # Cost to delete an item
        upgradeMode::Bool   # True when in upgrade mode
        upgradeCost::Int    # Cost to upgrade an item
        
        # Message system
        messageText::String
        messageTimeout::Float64
        
        # Confirmation dialog state
        confirmationActive::Bool
        confirmationItem
        confirmationDelay::Float64  # Delay to prevent same-frame conflicts
        
        # Tooltip manager
        tooltipManager

        # Bag
        bag

        function InventoryManager()
            this = new() # do not remove this line
            
            # Initialize inventory state
            this.isInventoryOpen = false
            
            # Scrolling settings
            this.scrollOffset = 0.0
            this.scrollSpeed = 300.0
            
            # Panel layout settings
            this.panelWidth = 800
            this.panelHeight = 600
            this.panelX = (1920 - 800) ÷ 2  # Center horizontally
            this.panelY = (1080 - 600) ÷ 2  # Center vertically
            this.itemSize = 80
            this.itemSpacing = 10
            this.itemsPerRow = 8
            this.maxItems = 40  # 5 rows × 8 items
            
            # Default category
            this.selectedCategory = "all"
            
            # Initialize special modes
            this.deletionMode = false
            this.deletionCost = 10  # Default cost to delete an item
            this.upgradeMode = false
            this.upgradeCost = 75  # Default cost to upgrade an item
            
            # Initialize message system
            this.messageText = ""
            this.messageTimeout = 0.0
            
            # Initialize confirmation dialog state
            this.confirmationActive = false
            this.confirmationItem = nothing
            this.confirmationDelay = 0.0

            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    function JulGame.initialize(this::InventoryManager)
        global InventoryManagerInstance = this
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()
        this.persistentStateManager = globals.get_data_manager().persistent_state_manager
        
        # Create and initialize the tooltip manager if not provided
        if !isdefined(this, :tooltipManager) || this.tooltipManager === nothing
            tooltipEntity = JulGame.EntityModule.Entity("InventoryTooltipManager")
            tooltipEntity = JulGame.create_entity(tooltipEntity)
            push!(tooltipEntity.scripts, Scripts.TooltipManagerModule.TooltipManager())
            this.tooltipManager = tooltipEntity.scripts[1]
            
            # Set custom tooltip style
            Scripts.TooltipManagerModule.set_tooltip_style(
                this.tooltipManager,
                hoverDelay = UInt64(120)
            )
        end

        this.bag = JulGame.SceneModule.get_ui_element_by_id("77b0eee2-0df4-4aeb-b443-b52f51850fd2")
        if this.bag !== nothing && length(this.bag.clickEvents) == 0
            inventoryClickEvent = () -> toggle_inventory(this)
            JulGame.UI.add_click_event(this.bag, inventoryClickEvent)
        elseif this.bag === nothing
            this.bag = JulGame.SceneModule.get_ui_element_by_id("9ef533c2-c777-4c18-add7-254654a96c9e")
            if this.bag !== nothing && length(this.bag.clickEvents) == 0
                inventoryClickEvent = () -> toggle_inventory(this)
                JulGame.UI.add_click_event(this.bag, inventoryClickEvent)
            end
        end  
    end

    # This is called every frame
    function JulGame.update(this::InventoryManager, deltaTime)
        # Toggle inventory with I key
        if JulGame.InputModule.get_button_pressed("I")
            toggle_inventory(this)
        end
        
        # Update message timeout
        if this.messageTimeout > 0
            this.messageTimeout -= deltaTime
        end
        
        # Update confirmation delay
        if this.confirmationDelay > 0
            this.confirmationDelay -= deltaTime
        end
        
        # Only update if inventory is open
        if this.isInventoryOpen
            draw_inventory_panel(this, deltaTime)
            
            # Update tooltip manager to check for hovers
            if this.tooltipManager !== nothing
                Scripts.TooltipManagerModule.check_tooltip_hovers(this.tooltipManager)
            end
        end
    end

    # This is called when the script is removed from an entity
    function JulGame.on_shutdown(this::InventoryManager)
        # Clean up any resources if needed
        global InventoryManagerInstance = nothing
    end

    """
    Toggle the inventory panel open/closed
    """
    function toggle_inventory(this::InventoryManager)
        this.isInventoryOpen = !this.isInventoryOpen
        if this.isInventoryOpen
            # Reset scroll when opening
            this.scrollOffset = 0.0
        else
            deregister_old_tooltip_areas(this)
        end
    end

    function toggle_inventory()
        @debug "toggle_inventory"
        if InventoryManagerInstance !== nothing
            @debug "toggle_inventory actually toggling"
            toggle_inventory(InventoryManagerInstance)
        else
            @debug "toggle_inventory is nothing"
        end
    end

    """
    Close the inventory panel
    """
    function close_inventory(this::InventoryManager)
        # Clean up tooltip areas when closing inventory
        deregister_old_tooltip_areas(this)
        this.isInventoryOpen = false
        this.deletionMode = false  # Exit deletion mode when closing
        this.upgradeMode = false   # Exit upgrade mode when closing
        this.confirmationActive = false  # Clear any active confirmation
        this.confirmationItem = nothing
        this.confirmationDelay = 0.0  # Clear confirmation delay
    end

    """
    Open inventory in deletion mode for trash upgrade
    """
    function open_deletion_inventory(this::InventoryManager, cost::Int = 10)
        this.deletionMode = true
        this.deletionCost = cost
        this.upgradeMode = false
        this.isInventoryOpen = true
        this.scrollOffset = 0.0
    end

    """
    Open inventory in upgrade mode for piece upgrade
    """
    function open_upgrade_inventory(this::InventoryManager, cost::Int = 75)
        this.upgradeMode = true
        this.upgradeCost = cost
        this.deletionMode = false
        this.isInventoryOpen = true
        this.scrollOffset = 0.0
        this.selectedCategory = "items"  # Only show items for upgrading
    end

    """
    Draw the main inventory panel and all its contents
    """
    function draw_inventory_panel(this::InventoryManager, deltaTime)
        # Draw background panel
        bg = Scripts.NineSliceUIModule.immediate_panel(
            "inventory_background";
            position = Math.Vector2(this.panelX, this.panelY),
            size = Math.Vector2(this.panelWidth, this.panelHeight),
            layer = 100
        )
        
        # Draw title
        title_text = this.deletionMode ? InventoryStringsModule.format_string(:inventory_title_trash, cost=this.deletionCost) :
                    this.upgradeMode ? InventoryStringsModule.format_string(:inventory_title_upgrade, cost=this.upgradeCost) :
                    InventoryStringsModule.INVENTORY_STRINGS[:inventory_title]
        title_color = this.deletionMode ? (255, 200, 200, 255) :
                     this.upgradeMode ? (200, 255, 200, 255) :
                     (255, 255, 255, 255)
        
        DisplayTextModule.display_text(
            "inventory_title",
            title_text;
            position = Math.Vector2(this.panelX + 20, this.panelY + 20),
            fontSize = 28,
            color = title_color,
            layer = 101
        )
        
        # Draw close button
        close_button = Scripts.NineSliceUIModule.immediate_button(
            "inventory_close",
            () -> close_inventory(this);
            size = Math.Vector2(40, 40),
            text = InventoryStringsModule.INVENTORY_STRINGS[:inventory_close_button],
            fontSize = 20,
            color = (200, 60, 60, 255),
            layer = 101,
            anchor = :topRight,
            anchorOffset = Math.Vector2(-10, 10),
            parent = bg
        )
        
        # Draw category tabs
        draw_category_tabs(this, bg)
        
        # Handle scrolling input
        handle_scrolling_input(this, deltaTime)
        
        # Get filtered items based on selected category
        filtered_items = get_filtered_items(this)
        
        # Draw scroll instructions if there are more items than can fit
        total_rows = ceil(Int, length(filtered_items) / this.itemsPerRow)
        visible_rows = this.maxItems ÷ this.itemsPerRow
        
        if total_rows > visible_rows
            DisplayTextModule.display_text(
                "scroll_instructions",
                InventoryStringsModule.INVENTORY_STRINGS[:inventory_scroll_instructions];
                position = Math.Vector2(this.panelX + 20, this.panelY + this.panelHeight - 30),
                fontSize = 16,
                color = (180, 180, 180, 255),
                layer = 101
            )
        end
        
        # Draw item grid
        draw_item_grid(this, filtered_items)
        
        # Draw message if active
        if this.messageTimeout > 0
            draw_message(this)
        end
        
        # Draw confirmation dialog if active
        if this.confirmationActive
            draw_confirmation_dialog(this)
        end
    end

    """
    Draw category filter tabs
    """
    function draw_category_tabs(this::InventoryManager, bg)
        categories = ["all", "items", "potions", "treasures"]
        tab_width = 120
        tab_height = 35
        
        for (i, category) in enumerate(categories)
            is_selected = (category == this.selectedCategory)
            tab_color = is_selected ? (80, 120, 160, 255) : (60, 60, 70, 200)
            text_color = is_selected ? (255, 255, 255, 255) : (200, 200, 200, 255)
            
            tab_button = Scripts.NineSliceUIModule.immediate_button(
                "tab_$(category)",
                () -> set_category(this, category);
                size = Math.Vector2(tab_width, tab_height),
                text = category == "all" ? InventoryStringsModule.INVENTORY_STRINGS[:inventory_category_all] :
                       category == "items" ? InventoryStringsModule.INVENTORY_STRINGS[:inventory_category_items] :
                       category == "potions" ? InventoryStringsModule.INVENTORY_STRINGS[:inventory_category_potions] :
                       InventoryStringsModule.INVENTORY_STRINGS[:inventory_category_treasures],
                fontSize = 16,
                color = tab_color,
                layer = 101,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(20 + (i-1) * (tab_width + 5), 60),
                parent = bg
            )
        end
    end

    """
    Set the active category filter
    """
    function set_category(this::InventoryManager, category::String)
        # Clean up old tooltip areas for the previous category
        deregister_old_tooltip_areas(this)
        
        this.selectedCategory = category
        this.scrollOffset = 0.0  # Reset scroll when changing categories
    end

    """
    Deregister all tooltip areas for the current category
    """
    function deregister_old_tooltip_areas(this::InventoryManager)
        if this.tooltipManager !== nothing
            # We need to deregister all possible tooltip areas for the current category
            # Since we don't know exactly how many items were visible, we'll clean up
            # more than necessary (this is safe as deregistering non-existent areas is harmless)
            for index in 1:this.maxItems
                tooltip_id = "item_tooltip_$(this.selectedCategory)_$(index)"
                Scripts.TooltipManagerModule.deregister_tooltip_area(this.tooltipManager, tooltip_id)
            end
        end
    end

    """
    Handle keyboard input for scrolling
    """
    function handle_scrolling_input(this::InventoryManager, deltaTime)
        # Handle scrolling with arrow keys
        if JulGame.InputModule.get_button_held_down("Up")
            this.scrollOffset = max(this.scrollOffset - this.scrollSpeed * deltaTime, 0.0)
        elseif JulGame.InputModule.get_button_held_down("Down")
            filtered_items = get_filtered_items(this)
            total_rows = ceil(Int, length(filtered_items) / this.itemsPerRow)
            visible_rows = this.maxItems ÷ this.itemsPerRow
            max_scroll = max(0.0, Float64((total_rows - visible_rows) * (this.itemSize + this.itemSpacing)))
            this.scrollOffset = min(this.scrollOffset + this.scrollSpeed * deltaTime, max_scroll)
        end
    end

    """
    Get items filtered by the selected category
    """
    function get_filtered_items(this::InventoryManager)
        items = []
        
        if this.selectedCategory == "all" || this.selectedCategory == "items"
            for piece in this.user.pieces
               # @debug("Piece: $(piece)")
                push!(items, Dict(
                    "type" => "item",
                    "data" => piece,
                    "name" => piece.name,
                    "icon" => get_piece_icon_path(piece),
                    "description" => get_piece_description(piece, this.user.pieces, this.user)
                ))
            end
        end
        
        if this.selectedCategory == "all" || this.selectedCategory == "potions"
            for potion in this.user.potions
                push!(items, Dict(
                    "type" => "potion",
                    "data" => potion,
                    "name" => potion.name,
                    "icon" => get_potion_icon_path(potion),
                    "description" => get_potion_description(potion)
                ))
            end
        end
        
        if this.selectedCategory == "all" || this.selectedCategory == "treasures"
            for treasure in this.user.treasures
                push!(items, Dict(
                    "type" => "treasure", 
                    "data" => treasure,
                    "name" => treasure.name,
                    "icon" => get_treasure_icon_path(treasure),
                    "description" => get_treasure_description(treasure)
                ))
            end
        end
        
        return items
    end

    """
    Draw the grid of inventory items
    """
    function draw_item_grid(this::InventoryManager, items)
        grid_start_x = this.panelX + 20
        grid_start_y = this.panelY + 110
        
        visible_items = get_visible_items(this, items)
        
        for (index, item) in enumerate(visible_items)
            # Calculate grid position
            col = (index - 1) % this.itemsPerRow
            row = (index - 1) ÷ this.itemsPerRow
            
            item_x = grid_start_x + col * (this.itemSize + this.itemSpacing)
            item_y = grid_start_y + row * (this.itemSize + this.itemSpacing)
            
            # Draw item slot background
            slot_color = item["type"] == "item" ? (60, 80, 100, 180) :
                        item["type"] == "potion" ? (80, 60, 100, 180) :
                        (100, 80, 60, 180)  # treasure
            
            # Fill at 102, frame at 103.
            slot_rect = Scripts.NineSliceUIModule.immediate_panel(
                "item_slot_$(this.selectedCategory)_$(index)";
                position = Math.Vector2(item_x, item_y),
                size = Math.Vector2(this.itemSize, this.itemSize),
                color = slot_color,
                border_color = (120, 120, 140, 255),
                fill_alpha = 255,
                layer = 102
            )
            
            # Draw item icon
            item_button = JulGame.ImmediateUIModule.immediate_button(
                "item_$(this.selectedCategory)_$(index)",
                () -> handle_item_click(this, item);
                position = Math.Vector2(item_x + 4, item_y + 4),
                size = Math.Vector2(this.itemSize - 8, this.itemSize - 8),
                buttonUpPath = item["icon"],
                buttonDownPath = item["icon"],
                layer = 104,
                anchor = :center, 
                parent = slot_rect,
                forceClickCheck = true
            )
            
            # Add hover highlighting
            if item_button.isHovered
                # Draw hover highlight overlay
                highlight_color = this.deletionMode ? (255, 100, 100, 80) :
                                 this.upgradeMode ? (100, 255, 100, 80) :
                                 (100, 200, 255, 80)
                border_color = this.deletionMode ? (255, 150, 150, 255) :
                              this.upgradeMode ? (150, 255, 150, 255) :
                              (150, 220, 255, 255)
                
                JulGame.ImmediateUIModule.immediate_rect(
                    "item_hover_$(this.selectedCategory)_$(index)";
                    position = Math.Vector2(item_x, item_y),
                    size = Math.Vector2(this.itemSize, this.itemSize),
                    color = highlight_color,
                    borderWidth = 2,
                    borderColor = border_color,
                    layer = 105
                )
            end
            
            # Register tooltip for this item
            Scripts.TooltipManagerModule.register_tooltip_area(
                this.tooltipManager,
                "item_tooltip_$(this.selectedCategory)_$(index)",
                item_x,
                item_y,
                this.itemSize,
                this.itemSize,
                "$(item["name"]): $(item["description"])"
            )
        end
    end

    """
    Get the subset of items that should be visible based on scroll offset
    """
    function get_visible_items(this::InventoryManager, items)
        if isempty(items)
            return []
        end
        
        # Calculate which items are visible based on scroll
        items_per_row = this.itemsPerRow
        visible_rows = this.maxItems ÷ items_per_row
        
        # Convert scroll offset to row offset
        item_height_with_spacing = this.itemSize + this.itemSpacing
        scroll_row_offset = floor(Int, this.scrollOffset / item_height_with_spacing)
        
        start_index = scroll_row_offset * items_per_row + 1
        end_index = min(length(items), start_index + this.maxItems - 1)
        
        if start_index > length(items)
            return []
        end
        
        return items[start_index:end_index]
    end

    """
    Handle clicking on an inventory item
    """
    function handle_item_click(this::InventoryManager, item)
        # Don't allow item clicks if confirmation dialog is active
        if this.confirmationActive
            return
        end
        
        @debug("Clicked on item: $(item["name"])")
        
        if this.deletionMode
            handle_deletion_click(this, item)
        elseif this.upgradeMode
            handle_upgrade_click(this, item)
        else
            # Add any normal item interaction logic here
            # For example: use potion, examine item details, etc.
        end
    end

    """
    Handle item deletion when in deletion mode
    """
    function handle_deletion_click(this::InventoryManager, item)
        # Check if player has enough gold
        if this.user.gold < this.deletionCost
            show_deletion_message(this, "Not enough gold! You need $(this.deletionCost) gold to delete items.")
            return
        end

        # Check if the item is a piece
        if item["type"] == "item" && length(this.user.pieces) <= 5
            show_deletion_message(this, "You need at least 6 pieces to delete an item.")
            return
        end
        
        # Set confirmation dialog state with delay to prevent same-frame conflicts
        @debug("Setting confirmation active for item: $(item["name"])")
        this.confirmationActive = true
        this.confirmationItem = item
        this.confirmationDelay = 0.1  # 100ms delay
    end

    """
    Handle item upgrade when in upgrade mode
    """
    function handle_upgrade_click(this::InventoryManager, item)
        # Only allow upgrading pieces (items), not potions or treasures
        if item["type"] != "item"
            show_deletion_message(this, "You can only upgrade items!")
            return
        end
        
        # Check if player has enough gold
        if this.user.gold < this.upgradeCost
            show_deletion_message(this, "Not enough gold! You need $(this.upgradeCost) gold to upgrade items.")
            return
        end
        
        # Set confirmation dialog state with delay to prevent same-frame conflicts
        @debug("Setting confirmation active for item upgrade: $(item["name"])")
        this.confirmationActive = true
        this.confirmationItem = item
        this.confirmationDelay = 0.1  # 100ms delay
    end

    """
    Draw confirmation dialog for item deletion or upgrade
    """
    function draw_confirmation_dialog(this::InventoryManager)
        if !this.confirmationActive || this.confirmationItem === nothing || this.confirmationDelay > 0
            @debug("Confirmation dialog skipped: active=$(this.confirmationActive), item=$(this.confirmationItem !== nothing), delay=$(this.confirmationDelay)")
            return
        end
        
        @debug("Drawing confirmation dialog")
        item = this.confirmationItem
        
        # Determine dialog type based on mode
        is_upgrade = this.upgradeMode
        dialog_color = is_upgrade ? (20, 40, 20, 240) : (40, 20, 20, 240)
        border_color = is_upgrade ? (100, 200, 100, 255) : (200, 100, 100, 255)
        action_text = is_upgrade ? InventoryStringsModule.INVENTORY_STRINGS[:inventory_action_upgrade] : InventoryStringsModule.INVENTORY_STRINGS[:inventory_action_delete]
        cost = is_upgrade ? this.upgradeCost : this.deletionCost
        
        # Create confirmation dialog
        confirmation_bg = Scripts.NineSliceUIModule.immediate_panel(
            "confirmation_bg";
            size = JulGame.Math.Vector2(500, 200),
            anchor = :center,
            layer = 200,
        )
        
        # Confirmation text
        DisplayTextModule.display_text(
            "confirmation_text",
            "$(action_text) $(item["name"]) for $(cost)G?";
            anchor = :center,
            anchorOffset = JulGame.Math.Vector2(0, -40),
            fontSize = 24,
            color = (255, 255, 255, 255),
            layer = 201
        )
        
        # Yes button
        confirm_action = is_upgrade ? () -> confirm_upgrade(this, item) : () -> confirm_deletion(this, item)
        Scripts.NineSliceUIModule.immediate_button(
            "confirmation_yes",
            confirm_action;
            text = InventoryStringsModule.INVENTORY_STRINGS[:inventory_confirm_action],
            fontSize = 20,
            size = JulGame.Math.Vector2(100, 40),
            anchor = :center,
            anchorOffset = JulGame.Math.Vector2(-60, 40),
            layer = 201
        )
        
        # No button
        Scripts.NineSliceUIModule.immediate_button(
            "confirmation_no",
            () -> cancel_confirmation(this);
            text = InventoryStringsModule.INVENTORY_STRINGS[:inventory_cancel_action],
            fontSize = 20,
            size = JulGame.Math.Vector2(100, 40),
            anchor = :center,
            anchorOffset = JulGame.Math.Vector2(60, 40),
            layer = 201
        )
    end

    """
    Confirm item deletion
    """
    function confirm_deletion(this::InventoryManager, item)
        # Deduct gold
        this.user.gold -= this.deletionCost
        OverworldFeedbackModule.gold!(-this.deletionCost)
        
        @debug("Confirming deletion of $(item)")
        # Remove item from appropriate collection
        if item["type"] == "item"
            @debug("Removing piece: $(item["data"].key)")
            # Find and remove the piece
            for (i, piece) in enumerate(this.user.pieces)
                @debug("Checking piece: $(piece)")
                if piece.key == item["data"].key
                    @debug("Removing piece: $(piece.key)")
                    deleteat!(this.user.pieces, i)
                    break
                end
            end
        elseif item["type"] == "potion"
            @debug("Removing potion: $(item["data"].key)")
            # Find and remove the potion
            for (i, potion) in enumerate(this.user.potions)
                if potion.key == item["data"].key
                    @debug("Removing potion: $(potion.key)")
                    deleteat!(this.user.potions, i)
                    break
                end
            end
        elseif item["type"] == "treasure"
            @debug("Removing treasure: $(item["data"].key)")
            # Find and remove the treasure
            for (i, treasure) in enumerate(this.user.treasures)
                if treasure.key == item["data"].key
                    @debug("Removing treasure: $(treasure.key)")
                    deleteat!(this.user.treasures, i)
                    break
                end
            end
        end
        
        # Mark trash-can used (single-use) in persistent state
        if this.persistentStateManager !== nothing
            this.persistentStateManager.playerData["hasUsedTrashCan"] = true
        end
        JulGame.UserGlobals["Module"].RunRecorderModule.record!("shop_trash";
            kind = string(item["type"]), key = string(item["data"].key), price = this.deletionCost)
        show_deletion_message(this, "Deleted $(item["name"]) for $(this.deletionCost)G!")
        
        # Clear confirmation state
        this.confirmationActive = false
        this.confirmationItem = nothing
        this.confirmationDelay = 0.0
        
        # Close inventory after successful deletion
        close_inventory(this)
    end

    """
    Confirm item upgrade
    """
    function confirm_upgrade(this::InventoryManager, item)
        # Deduct gold
        this.user.gold -= this.upgradeCost
        OverworldFeedbackModule.gold!(-this.upgradeCost)
        
        @debug("Confirming upgrade of $(item)")
        
        # Find the piece in the user's collection and increase its rarity
        if item["type"] == "item"
            @debug("Upgrading piece: $(item["data"].key)")
            for i = 1:length(this.user.pieces)
                piece = this.user.pieces[i]
                if piece.key == item["data"].key
                    # Raise board share by WEIGHT_INCREASE_AMOUNT pp of the post-add total.
                    # e.g. 10/100 (10%) + 5pp => 15% of (100 + added weight).
                    globals = JulGame.UserGlobals["Module"]
                    old_share = globals.UserModule.piece_board_share(piece, this.user.pieces)
                    new_share = old_share + WEIGHT_INCREASE_AMOUNT / 100.0
                    others_total = max(0.0, sum(Float64(p.weight) for p in this.user.pieces) - Float64(piece.weight))
                    new_weight = globals.UserModule.rarity_for_share(new_share, others_total)

                    # Struct is immutable, so we need to create a new one.
                    # rarity is stored as a String; getproperty parses it to a number.
                    this.user.pieces[i] = globals.UserModule.with_weight(piece, new_weight)

                    
                    @debug("Upgraded piece $(piece.key) share from $(old_share) to $(new_share) (weight $(piece.weight) -> $(new_weight))")
                    break
                end
            end
        end
        
        # Mark piece-upgrade used (single-use) in persistent state
        if this.persistentStateManager !== nothing
            this.persistentStateManager.playerData["hasPieceUpgrade"] = true
        end
        JulGame.UserGlobals["Module"].RunRecorderModule.record!("shop_upgrade";
            key = string(item["data"].key), price = this.upgradeCost)
        show_deletion_message(this, "Upgraded $(item["name"]) for $(this.upgradeCost)G! Rarity increased.")
        
        # Clear confirmation state
        this.confirmationActive = false
        this.confirmationItem = nothing
        this.confirmationDelay = 0.0
        
        # Close inventory after successful upgrade
        close_inventory(this)
    end

    """
    Cancel item deletion or upgrade
    """
    function cancel_confirmation(this::InventoryManager)
        # Clear confirmation state
        this.confirmationActive = false
        this.confirmationItem = nothing
        this.confirmationDelay = 0.0
    end

    """
    Show deletion status message
    """
    function show_deletion_message(this::InventoryManager, message::String)
        this.messageText = message
        this.messageTimeout = 3.0  # Show message for 3 seconds
        @debug("Deletion message: $(message)")
    end

    """
    Draw message overlay
    """
    function draw_message(this::InventoryManager)
        # Draw message background
        JulGame.ImmediateUIModule.immediate_rect(
            "inventory_message_bg";
            size = JulGame.Math.Vector2(600, 60),
            color = (40, 40, 40, 200),
            anchor = :center,
            anchorOffset = JulGame.Math.Vector2(0, 200),
            borderWidth = 2,
            borderColor = (100, 100, 100, 255),
            layer = 150
        )
        
        # Draw message text
        DisplayTextModule.display_text(
            "inventory_message_text",
            this.messageText;
            anchor = :center,
            anchorOffset = JulGame.Math.Vector2(0, 200),
            fontSize = 20,
            color = (255, 255, 255, 255),
            layer = 151
        )
    end

    # Helper functions for getting item info and icons
    function get_piece_icon_path(piece)
        return JulGame.UserGlobals["Module"].get_asset_path("piece", lowercase(split(piece.key, "_")[2]))
    end

    function get_potion_icon_path(potion)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(potion.key, "_")[2]))
    end

    function get_treasure_icon_path(treasure)
        return JulGame.UserGlobals["Module"].get_asset_path("treasure", lowercase(split(treasure.key, "_")[2]))
    end

    function get_piece_description(piece, all_pieces, user)
        description = ""
        description = piece.description
        if piece.attack > 0
            description *= " Attack: $(piece.attack) + $(user.attack)"
        end
        if piece.defense > 0
            description *= " Defense: $(piece.defense)"
        end
        # Add rarity/weight information (relative to all pieces)
        total_rarity = sum(p.weight for p in all_pieces)
        if total_rarity > 0
            weight_percent = round((piece.weight / total_rarity) * 100, digits=2)
            description *= " | Weight: $(weight_percent)%"
        else
            description *= " | Weight: 0%"
        end
        return description
    end

    function get_potion_description(potion)
        return potion.description
    end

    function get_treasure_description(treasure)
        return treasure.description
    end

    # Export the main functions that might be called from other scripts
    export close_inventory, toggle_inventory, open_deletion_inventory, open_upgrade_inventory
end 