module BattlePotionManagerModule
    using JulGame
    using ..Scripts
    include("utils/PotionsConstants.jl")
    include("potions/PotionEffects.jl")
    using .PotionEffectsModule
    include("potions/BombEffect.jl")
    using .BombEffectModule
    include("potions/EyeDropperEffect.jl")
    using .EyeDropperEffectModule

    mutable struct BattlePotionManager <: Script
        parent # reference to the entity this script is attached to
        
        # User data and managers
        user
        persistentStateManager
        battleManager
        gridController
        inputHandler
        
        
        # Bomb selection state
        isBombSelectionMode::Bool
        bombAreaSize::Int
        bombSlotIndex::Int
        selectedBombCenter
        highlightedCells
        
        # Eye dropper selection state
        isEyeDropperSelectionMode::Bool
        eyeDropperSlotIndex::Int
        
        function BattlePotionManager()
            this = new()
            
            this.isBombSelectionMode = false
            this.bombAreaSize = 3  # 3x3 area for regular bomb
            this.bombSlotIndex = 0
            this.selectedBombCenter = nothing
            this.highlightedCells = []
            
            this.isEyeDropperSelectionMode = false
            this.eyeDropperSlotIndex = 0
            
            return this
        end
    end

    function JulGame.initialize(this::BattlePotionManager)
        @debug("BattlePotionManager.initialize called")
        
        # Get user and managers
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()
        this.persistentStateManager = globals.get_data_manager().persistent_state_manager
        
        # Get other scripts from parent entity
        this.battleManager = this.parent.scripts[4]  # BattleManager is script 4
        this.gridController = this.parent.scripts[3]  # GridController is script 3
        this.inputHandler = this.parent.scripts[2]   # InputHandler is script 2
    end

    function JulGame.update(this::BattlePotionManager, deltaTime)
        # Handle potion usage input only during player turn and not paused
        if this.battleManager.currentState == this.battleManager.battleStates[:playerTurn] && 
           !this.parent.scripts[1].pauseMenu.paused  # GameManager has pauseMenu
            
            handle_potion_input(this)
        end
        
        # Handle bomb selection mode
        if this.isBombSelectionMode
            BombEffectModule.handle_bomb_selection(this)
        end
        
        # Handle eye dropper selection mode
        if this.isEyeDropperSelectionMode
            EyeDropperEffectModule.handle_eyedropper_selection(this)
        end
    end

    function JulGame.on_shutdown(this::BattlePotionManager)
        # Clean up any highlights when shutting down
        BombEffectModule.clear_bomb_highlights(this)
        EyeDropperEffectModule.clear_eyedropper_highlights(this)
    end

    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end

    function handle_potion_input(this::BattlePotionManager)
        # Keyboard input disabled - now handled by PotionDisplayManager with mouse input
        # Keep this function for compatibility but don't handle keyboard input
    end

    """Detonator and Nail are aiming at the board. A potion click would steal that target."""
    function ability_targeting_blocks_potion(this::BattlePotionManager)::Bool
        parent = this.parent
        parent === nothing && return false
        length(parent.scripts) < 17 && return false
        am = parent.scripts[17]
        return am isa Scripts.AbilityManagerModule.AbilityManager &&
            (am.isDetonatorSelectionMode || am.isNailSelectionMode)
    end

    function use_potion(this::BattlePotionManager, slot_index::Int)
        if ability_targeting_blocks_potion(this)
            @debug "Cannot use a potion while an active ability is targeting"
            return
        end
        if slot_index > length(this.user.potions)
            @warn("Tried to use potion from slot $slot_index but only have $(length(this.user.potions)) potions")
            return
        end
        
        potion = this.user.potions[slot_index]
        @debug("Using potion: $(potion.key) from slot $slot_index")
        
        # Use the modular potion effects system
        success = PotionEffectsModule.execute_potion_effect(potion.key, this, slot_index)
        
        if success
            play_potion_drink_sfx()
            Globals.RunRecorderModule.note_potion!(potion.key, "used")
            # Track potion usage in analytics
            try
                globals = JulGame.UserGlobals["Module"]
                Globals.AnalyticsModule.track_action(:potion_used)
            catch e
                @debug "Could not track potion usage: $e"
            end
        else
            @debug("Potion type $(potion.key) not yet implemented")
        end
    end

    const _SHOP_POTION_BATTLE_ONLY_KEYS = Set{String}((
        POTION_BOMB,
        POTION_GIGABOMB,
        POTION_MEGABOMB,
        POTION_EYEDROPPER,
        POTION_BASICBATTERY,
        POTION_ACTIVEBATTERY,
        POTION_DEVILTEARS,
        POTION_ANGELTEARS,
    ))

    """
    Apply a potion from the shared inventory bar while in the upgraded shop scene.
    Battle-only/grid potions show feedback and are not consumed; shop/Dice/etc. defer to ShopManager.use_inventory_potion.
    """
    function use_potion_in_shop(shop_manager, slot_index::Int)
        if shop_manager === nothing
            @warn("use_potion_in_shop: shop_manager is nothing")
            return
        end
        if slot_index < 1 || slot_index > length(shop_manager.user.potions)
            @warn("use_potion_in_shop: invalid slot $slot_index")
            return
        end

        potion = shop_manager.user.potions[slot_index]
        if potion.key ∈ _SHOP_POTION_BATTLE_ONLY_KEYS
            Scripts.ShopManagerModule.show_battle_only_potion_blocked(shop_manager, potion)
            return
        end

        Scripts.ShopManagerModule.use_inventory_potion(shop_manager, slot_index)
    end

    function play_potion_drink_sfx()
        try
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(),
                globals.get_asset_path("sfx", "drink"),
                false, 1.0, 0, 1,
            )
        catch e
            @debug "drink sfx: $e"
        end
    end

    # Export the use_potion function for external access
    export use_potion, use_potion_in_shop, play_potion_drink_sfx, ability_targeting_blocks_potion



end 