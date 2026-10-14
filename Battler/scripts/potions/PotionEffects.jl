module PotionEffectsModule
    using JulGame
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    # Include all individual potion effect files
    include("BombEffect.jl")
    include("EyeDropperEffect.jl")
    include("BasicBatteryEffect.jl")
    include("ActiveBatteryEffect.jl")
    include("DevilTearsEffect.jl")
    include("AngelTearsEffect.jl")
    include("DiceEffect.jl")
    include("HerbalTeaEffect.jl")

    # Export all effect functions
    export execute_potion_effect, get_potion_effect_function, handle_boss_defeat_potions, handle_death_prevention_potions, usable_in, use_outside_battle!

    """
    Main entry point for executing any potion effect
    """
    function execute_potion_effect(potion_key::String, battle_potion_manager, slot_index::Int)
        @debug("Executing potion effect for: $potion_key")
        
        if potion_key == POTION_BOMB
            BombEffectModule.execute_bomb_effect(battle_potion_manager, slot_index, 3)
        elseif potion_key == POTION_GIGABOMB  
            BombEffectModule.execute_bomb_effect(battle_potion_manager, slot_index, 5)
        elseif potion_key == POTION_MEGABOMB
            BombEffectModule.execute_bomb_effect(battle_potion_manager, slot_index, 7)
        elseif potion_key == POTION_EYEDROPPER
            EyeDropperEffectModule.execute_eyedropper_effect(battle_potion_manager, slot_index)
        elseif potion_key == POTION_BASICBATTERY
            BasicBatteryEffectModule.execute_basic_battery_effect(battle_potion_manager, slot_index)
        elseif potion_key == POTION_ACTIVEBATTERY
            ActiveBatteryEffectModule.execute_active_battery_effect(battle_potion_manager, slot_index)
        elseif potion_key == POTION_DEVILTEARS
            # Normal consumption mode
            DevilTearsEffectModule.execute_devil_tears_effect(battle_potion_manager, slot_index, false)
        elseif potion_key == POTION_ANGELTEARS
            # Normal consumption mode
            AngelTearsEffectModule.execute_angel_tears_effect(battle_potion_manager, slot_index, false)
        elseif potion_key == POTION_DICE
            DiceEffectModule.execute_dice_effect(battle_potion_manager, slot_index)
        elseif potion_key == POTION_HERBALTEA
            HerbalTeaEffectModule.execute_herbal_tea_effect(battle_potion_manager, slot_index)
        else
            @warn("Potion effect not implemented for: $potion_key")
            return false
        end
        
        return true
    end

    """
    Handle special potion effects that trigger on boss defeat
    """
    function handle_boss_defeat_potions(battle_potion_manager)
        @debug("Checking for boss defeat potion effects")
        
        # Check if player has Devil Tears in inventory
        for (index, potion) in enumerate(battle_potion_manager.user.potions)
            if potion.key == POTION_DEVILTEARS
                @debug("Found Devil Tears in inventory, consuming for boss defeat effect")
                DevilTearsEffectModule.execute_devil_tears_effect(battle_potion_manager, index, true)
                return true  # Only consume one Devil Tears per boss defeat
            end
        end
        
        return false
    end

    """
    Handle special potion effects that trigger on death prevention
    """
    function handle_death_prevention_potions(battle_potion_manager)
        @debug("Checking for death prevention potion effects")
        
        # Check if player has Angel Tears in inventory
        for (index, potion) in enumerate(battle_potion_manager.user.potions)
            if potion.key == POTION_ANGELTEARS
                @debug("Found Angel Tears in inventory, consuming for death prevention effect")
                AngelTearsEffectModule.execute_angel_tears_effect(battle_potion_manager, index, true)
                return true  # Only consume one Angel Tears per death
            end
        end
        
        return false
    end

    """
    True when `context` ("Combat", "Shop", "Map", "Event") is listed in the potion's Type column.
    """
    usable_in(potion, context::AbstractString)::Bool = any(t -> strip(t) == context, split(potion.type, ","))

    """
    Consume a potion outside combat (map, event).
    """
    function use_outside_battle!(user, slot_index::Int)
        potion = user.potions[slot_index]
        globals = JulGame.UserGlobals["Module"]
        if potion.key == POTION_HERBALTEA
            gained = HerbalTeaEffectModule.drink_herbal_tea!(user)
            Scripts.OverworldFeedbackModule.heal!(gained; icon = HerbalTeaEffectModule.herbal_tea_icon())
        elseif potion.key == POTION_ANGELTEARS
            gained = AngelTearsEffectModule.gain_angel_tears_health!(user)
            Scripts.OverworldFeedbackModule.heal!(gained; icon = globals.get_asset_path("potion", "angeltears"))
        elseif potion.key == POTION_DEVILTEARS
            DevilTearsEffectModule.gain_devil_tears_stats!(user)
        else
            @warn("Out-of-combat potion effect not implemented for: $(potion.key)")
            return
        end
        deleteat!(user.potions, slot_index)
        Scripts.BattlePotionManagerModule.play_potion_drink_sfx()
        globals.RunRecorderModule.note_potion!(potion.key, "used")
        globals.SaveManagerModule.try_save_run!()
    end

end 