# Strings Index - Master module for all localization strings
# This module provides a centralized way to access all string dictionaries
# Used throughout the game for consistent string management

module StringsIndexModule

# Import all string modules
include("event_strings.jl")
include("shop_strings.jl")
include("battle_strings.jl")
include("ui_strings.jl")
include("map_strings.jl")
include("inventory_strings.jl")

using .EventStringsModule
using .ShopStringsModule
using .BattleStringsModule
using .UIStringsModule
using .MapStringsModule
using .InventoryStringsModule

# Re-export all string dictionaries for convenience
export EventStringsModule, ShopStringsModule, BattleStringsModule, 
       UIStringsModule, MapStringsModule, InventoryStringsModule

# Helper function to get a string from any module
function get_string(module_name::Symbol, key::Symbol, kwargs...)
    if module_name == :event
        return EventStringsModule.format_string(key, kwargs...)
    elseif module_name == :shop
        return ShopStringsModule.format_string(key, kwargs...)
    elseif module_name == :battle
        return BattleStringsModule.format_string(key, kwargs...)
    elseif module_name == :ui
        return UIStringsModule.UI_STRINGS[key]
    elseif module_name == :map
        return MapStringsModule.MAP_STRINGS[key]
    elseif module_name == :inventory
        return InventoryStringsModule.format_string(key, kwargs...)
    else
        error("Unknown string module: $module_name")
    end
end

export get_string

end # module
