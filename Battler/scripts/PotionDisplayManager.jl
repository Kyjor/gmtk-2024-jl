module PotionDisplayManagerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts
    
    mutable struct PotionDisplayManager <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        
        # Manager references
        user
        battlePotionManager
        shopManager  # ShopManager script on shop entity (resolved by type, not scripts[1])
        
        # Slideout UI elements
        potionHolder
        potionSlot1
        potionSlot2
        potionSlot3
        potionSlot4
        
        # Position constants (legacy world-space values, converted to UI screen-space).
        basePosition::Int
        hiddenPosition::Int
        # Current state
        currentPotionCount::Int
        targetPosition::Int
        # Shop potion menu was open last frame; the click that picks/closes it must not reopen it.
        shopMenuWasOpen::Bool
        
        function PotionDisplayManager()
            this = new() # do not remove this line
            
            this.basePosition = 0
            this.hiddenPosition = -525
            this.currentPotionCount = 0
            this.targetPosition = this.hiddenPosition
            this.shopManager = nothing
            this.shopMenuWasOpen = false

            return this # do not remove this line
        end
    end

    """Find shop manager script on an entity (ShopManager or HamsterShopManager)."""
    function _find_shop_manager_on_entity(entity)
        entity === nothing && return nothing
        for s in entity.scripts
            if s isa Scripts.ShopManagerModule.ShopManager ||
               s isa Scripts.HamsterShopManagerModule.HamsterShopManager
                return s
            end
        end
        return nothing
    end

    @inline function _is_shop_scene()::Bool
        return MAIN.scene.name == "upgraded-shop" || MAIN.scene.name == "hamster-shop"
    end

    function JulGame.initialize(this::PotionDisplayManager)
        # start timer 
        timer = time_ns()
        # Get user data
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()

         # Get potion display UI elements
         this.potionHolder = JulGame.SceneModule.get_ui_element_by_id("ui_potion_holder")
         this.potionSlot1 = JulGame.SceneModule.get_ui_element_by_id("ui_potion_slot_1")
         this.potionSlot2 = JulGame.SceneModule.get_ui_element_by_id("ui_potion_slot_2")
         this.potionSlot3 = JulGame.SceneModule.get_ui_element_by_id("ui_potion_slot_3")
         this.potionSlot4 = JulGame.SceneModule.get_ui_element_by_id("ui_potion_slot_4")
        
        # Get BattlePotionManager reference
        if MAIN.scene.name == "battle"
            battleEntity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba")
            this.battlePotionManager = battleEntity.scripts[9]  # BattlePotionManager is script 9
        elseif _is_shop_scene()
            this.shopManager = _find_shop_manager_on_entity(this.parent)
            if this.shopManager === nothing
                shopEnt = JulGame.SceneModule.get_entity_by_id(
                    MAIN.scene,
                    "58ca72a3-0f2d-4b7d-9a7c-8b998e48c615",
                )
                this.shopManager = _find_shop_manager_on_entity(shopEnt)
            end
        elseif MAIN.scene.name == "title_scene"
            set_potion_display(this, false)
            return
        end
        set_potion_display(this, true)
        
        # Initialize display
        update_potion_display(this)
        @debug "PotionDisplayManager initialized in $((time_ns() - timer) / 1e9) seconds"
    end

    function JulGame.update(this::PotionDisplayManager, deltaTime)
        if MAIN.scene.name == "title_scene"
            return
        end
        # Update display if potion count changed
        potionCount = length(this.user.potions)
        if potionCount != this.currentPotionCount
            this.currentPotionCount = potionCount
            update_potion_display(this)
        end
        
        # Shop: click opens Use/Sell/Discard menu on bar (battle uses PotionTooltip context menu on LMB)
        if _is_shop_scene()
            handle_potion_input(this)
            this.shopMenuWasOpen = _shop_menu_open(this)
        end

         # display potion count text
         if potionCount > 0 && this.potionHolder !== nothing
            DisplayTextModule.display_text(
                "potion_count_text",
                "$(potionCount)/4";
                fontSize = 28,
                anchor = :bottomRight,
                anchorOffset = JulGame.Math.Vector2(
                    10,
                    5
                ),
                color = (160, 199, 255, 255),
                parent = this.potionHolder
            )
        end
    end

    function JulGame.on_shutdown(this::PotionDisplayManager)
    end

    function set_potion_display(this::PotionDisplayManager, isActive::Bool)
        if this.potionHolder !== nothing
            this.potionHolder.isActive = isActive
        end
        if this.potionSlot1 !== nothing
            this.potionSlot1.isActive = isActive
        end
        if this.potionSlot2 !== nothing
            this.potionSlot2.isActive = isActive
        end
        if this.potionSlot3 !== nothing
            this.potionSlot3.isActive = isActive
        end
        if this.potionSlot4 !== nothing
            this.potionSlot4.isActive = isActive
        end
    end

    function update_potion_display(this::PotionDisplayManager)
        potionCount = length(this.user.potions)
        
        if this.potionHolder === nothing
            return
        end
        
        # Calculate target position based on potion count
        if potionCount == 0
            this.targetPosition = this.hiddenPosition
        else
            # Linear interpolation between hidden and base position
            # 1 potion: closer to hidden, 4 potions: at base position
            potionHolderPositions = [-390, -270, -135, this.basePosition]
            this.targetPosition = potionHolderPositions[potionCount]
        end
        
        # Update slideout position
        this.potionHolder.anchorOffset = JulGame.Math.Vector2(this.targetPosition, this.potionHolder.anchorOffset.y)
        
        # Update individual potion slots
        update_potion_slots(this)
    end
    
    function update_potion_slots(this::PotionDisplayManager)
        slots = [this.potionSlot1, this.potionSlot2, this.potionSlot3, this.potionSlot4]
        
        # Support up to 4 potions as designed in the UI
        maxPotions = min(4, length(this.user.potions))
        
        for i in 1:4
            slots[i] === nothing && continue
            if i <= maxPotions
                # Show potion
                slots[i].isActive = true
                # Set potion sprite
                potion = this.user.potions[i]
                slots[i].path = get_potion_icon_path(potion.key)
            else
                # Hide unused slots
                slots[i].isActive = false
            end
        end
    end
    
    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end
    
    function handle_potion_input(this::PotionDisplayManager)
        # Check for mouse clicks on potion slots
        if JulGame.InputModule.get_mouse_button_pressed(1)
            check_potion_slot_clicks(this)
        end
    end
    
    function check_potion_slot_clicks(this::PotionDisplayManager)
        slots = [this.potionSlot1, this.potionSlot2, this.potionSlot3, this.potionSlot4]
        maxPotions = min(4, length(this.user.potions))
        
        for i in 1:maxPotions
            slots[i] === nothing && continue
            if slots[i].isActive && slots[i].isHovered
                # Use potion through BattlePotionManager
                @debug "Potion slotttt $(i) clicked"
                use_potion_at_slot(this, i)
                break
            end
        end
    end
    
    function use_potion_at_slot(this::PotionDisplayManager, slotIndex::Int)
        if slotIndex <= length(this.user.potions)
            if MAIN.scene.name == "battle"
                @debug "Potion slot clicked $(slotIndex)"
                if this.battlePotionManager === nothing
                    @warn("PotionDisplayManager: BattlePotionManager missing on battle")
                    return
                end
                # Call the existing potion usage system from BattlePotionManager module
                if Scripts.BattlePotionManagerModule.ability_targeting_blocks_potion(this.battlePotionManager)
                    @debug "Cannot use a potion while an active ability is targeting"
                    return
                end
                Scripts.BattlePotionManagerModule.use_potion(this.battlePotionManager, slotIndex)
                
                # The display will be updated in the next frame when the potion count changes
            elseif _is_shop_scene()
                if this.shopManager === nothing
                    @warn("PotionDisplayManager: ShopManager missing on $(MAIN.scene.name)")
                    return
                end
                (_shop_menu_open(this) || this.shopMenuWasOpen) && return
                if this.shopManager isa Scripts.HamsterShopManagerModule.HamsterShopManager
                    Scripts.HamsterShopManagerModule.open_inventory_potion_context_menu(this.shopManager, slotIndex)
                else
                    Scripts.ShopManagerModule.open_inventory_potion_context_menu(this.shopManager, slotIndex)
                end
            end
        end
    end

    _shop_menu_open(this::PotionDisplayManager)::Bool =
        this.shopManager !== nothing && this.shopManager.contextMenuManager.isOpen
    
end

