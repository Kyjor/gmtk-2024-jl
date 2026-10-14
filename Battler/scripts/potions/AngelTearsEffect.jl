module AngelTearsEffectModule
    using JulGame
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    """
    Normal consumption: +10% max health (current health rises too). Returns the health gained.
    """
    function gain_angel_tears_health!(user)::Int
        health_gain = floor(Int, user.maxHealth * 0.10)
        user.maxHealth += health_gain
        user.health += health_gain
        return health_gain
    end

    """
    Execute angel tears effect - two modes:
    1. Normal consumption: +10% max health
    2. Death prevention: automatically consume to revive with 25% health
    """
    function execute_angel_tears_effect(battle_potion_manager, slot_index::Int, is_death_prevention::Bool = false)
        @debug("Executing angel tears effect - death prevention: $is_death_prevention")
        
        user = battle_potion_manager.user
        
        if is_death_prevention
            # Death prevention mode: revive with 25% health
            new_health = floor(Int, user.maxHealth * 0.25)
            user.health = max(1, new_health)  # Ensure at least 1 HP
            
            @debug("Angel tears death prevention: Revived with $new_health health")
        else
            health_gain = gain_angel_tears_health!(user)
            
            @debug("Angel tears normal effect: Gained $health_gain max health")
        end
        
        # Remove potion from inventory
        deleteat!(battle_potion_manager.user.potions, slot_index)
        
        @debug("Angel tears effect executed successfully")
    end

    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end

    # Export functions
    export execute_angel_tears_effect, gain_angel_tears_health!

end 
