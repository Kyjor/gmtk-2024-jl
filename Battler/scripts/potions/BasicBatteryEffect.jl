module BasicBatteryEffectModule
    using JulGame
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    """
    Execute basic battery effect - gain +3 moves this turn
    """
    function execute_basic_battery_effect(battle_potion_manager, slot_index::Int)
        @debug("Executing basic battery effect - gaining +3 moves this turn")
        
        # Gain +3 moves this turn
        battle_potion_manager.battleManager.moveCount += 3
        
        # Remove potion from inventory
        deleteat!(battle_potion_manager.user.potions, slot_index)
        
        @debug("Basic battery effect executed successfully - gained 3 moves")
    end

    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end

    # Export functions
    export execute_basic_battery_effect

end 