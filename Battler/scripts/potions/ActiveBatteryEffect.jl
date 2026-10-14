module ActiveBatteryEffectModule
    using JulGame
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    """
    Execute active battery effect - recharging all active items
    """
    function execute_active_battery_effect(battle_potion_manager, slot_index::Int)
        @debug("Executing active battery effect - recharging all active items")
        
        # Recharge all active items
        ability_manager = battle_potion_manager.parent.scripts[17]  # AbilityManager is script 17
        Scripts.AbilityManagerModule.recharge_all!(ability_manager)
        
        # Remove potion from inventory
        deleteat!(battle_potion_manager.user.potions, slot_index)
        
        @debug("Active battery effect executed successfully - recharged all active items")
    end

    function get_potion_icon_path(key::String)
        return JulGame.UserGlobals["Module"].get_asset_path("potion", lowercase(split(key, "_")[2]))
    end

    # Export functions
    export execute_active_battery_effect

end 