# Inventory Strings Dictionary
# Used in: scripts/InventoryManager.jl
# Contains all user-facing strings for inventory UI and item management

module InventoryStringsModule

const INVENTORY_STRINGS = Dict(
    # Inventory titles
    :inventory_title => "Inventory",
    :inventory_title_upgrade => "Select Item to Upgrade (Cost: {cost}G)",
    :inventory_title_trash => "Select Item to Trash (Cost: {cost}G)",
    
    # Inventory UI
    :inventory_close_button => "X",
    :inventory_scroll_instructions => "Use Arrow Keys to Scroll",
    
    # Categories
    :inventory_category_all => "ALL",
    :inventory_category_items => "ITEMS",
    :inventory_category_potions => "POTIONS",
    :inventory_category_treasures => "TREASURES",
    
    # Confirmation dialog
    :inventory_confirm_action => "Yes",
    :inventory_cancel_action => "No",
    :inventory_action_upgrade => "Upgrade",
    :inventory_action_delete => "Delete",
)

# Helper function to format strings with placeholders
function format_string(key::Symbol; kwargs...)
    str = INVENTORY_STRINGS[key]
    for (k, v) in kwargs
        str = replace(str, "{$(k)}" => string(v))
    end
    return str
end

export INVENTORY_STRINGS, format_string

end # module
