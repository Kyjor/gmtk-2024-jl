module DevilTearsEffectModule
    using JulGame
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    """
    Normal consumption: +1 to all stats
    """
    function gain_devil_tears_stats!(user)
        user.maxHealth += 1
        user.attack += 1
        user.defense += 1
        user.maxShield += 1
    end

    """
    Execute devil tears effect - two modes:
    1. Normal consumption: +1 to all stats
    2. Boss defeat consumption: lose 33% max health, gain +3 to all stats except HP
    """
    function execute_devil_tears_effect(battle_potion_manager, slot_index::Int, is_boss_defeat::Bool = false)
        @debug("Executing devil tears effect - boss defeat: $is_boss_defeat")
        
        user = battle_potion_manager.user
        
        if is_boss_defeat
            # Boss defeat mode: lose 33% max health, gain +3 to all stats except HP
            health_loss = floor(Int, user.maxHealth * 0.33)
            user.maxHealth = max(1, user.maxHealth - health_loss)  # Ensure at least 1 HP
            user.health = min(user.health, user.maxHealth)  # Clamp current health to new max
            
            # Gain +3 to all stats except HP
            user.attack += 3
            user.defense += 3
            user.maxShield += 3
            
            @debug("Devil tears boss effect: Lost $health_loss max health, gained +3 to attack/defense/shield")
        else
            gain_devil_tears_stats!(user)
            
            @debug("Devil tears normal effect: Gained +1 to all stats")
        end
        
        # Remove potion from inventory
        deleteat!(battle_potion_manager.user.potions, slot_index)
        
        @debug("Devil tears effect executed successfully")
    end

    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end

    # Export functions
    export execute_devil_tears_effect, gain_devil_tears_stats!

end 
