# Shop Strings Dictionary
# Used in: scripts/ShopManager.jl
# Contains all user-facing strings for shop UI, purchase messages, and shop interactions

module ShopStringsModule

const SHOP_STRINGS = Dict(
    # Shop messages
    :shop_inventory_refreshed => "Shop inventory refreshed!",
    :shop_sold_out => "Sold out",
    :shop_select_item_upgrade => "Select an item to upgrade!",
    :shop_inventory_unavailable => "Inventory system not available!",
    :shop_select_item_trash => "Select an item to trash!",
    :shop_not_enough_gold => "Not enough dollars! You need {amount} dollars.",
    :shop_bought_everything => "You bought everything! The shopkeeper is overjoyed!",
    :shop_hamster_welcome => "Chewed goods — half price!",
    
    # Purchase messages
    :shop_purchased_piece => "Purchased {piece_name} for {price} dollars!",
    :shop_purchased_chewed_piece => "Purchased chewed {piece_name} for {price} dollars!",
    :shop_purchased_treasure => "Purchased {treasure_name} treasure for {price} dollars!",
    :shop_purchased_chewed_treasure => "Purchased chewed {treasure_name} for {price} dollars!",
    :shop_purchased_potion => "Potion purchased! You now have {count} potions.",
    :shop_potion_limit => "You can only have 4 potions at a time!",
    
    # Refresh messages
    :shop_refreshed_pieces => "Refreshed piece selection for {cost} dollars!",
    :shop_refreshed_treasures => "Refreshed treasure selection for {cost} dollars!",
    :shop_not_enough_gold_refresh => "Not enough dollars to refresh! You need {cost} dollars.",
    
    # Potion usage messages
    :shop_potion_not_found => "Potion not found!",
    :shop_potion_used_reroll => "Used {potion_name}! Shop inventory rerolled!",
    :shop_potion_used_no_effect => "Used {potion_name}! It has no effect.",
    :shop_potion_used_heal => "Used {potion_name}! Restored {amount} health.",
    :shop_potion_battle_only => "{potion_name} can only be used in battle.",
    :shop_potion_discarded => "Discarded {potion_name}.",
    :shop_potion_sold => "Sold {potion_name} for {price} dollars!",
    
    # Shop UI labels
    :shop_price_sold_out => "Sold out",
    :shop_price_piece_upgrade => "75",
    :shop_price_trash => "50",
    
    # Context menu
    :shop_context_discard => "Discard",
    :shop_context_use => "Use",
    :shop_context_sell => "Sell",
    :shop_context_sell_price => "Sell (\${price})",
    
    # Player stats labels
    :shop_stat_health => "Health: {value}",
    :shop_stat_attack => "Attack: {value}",
    :shop_stat_defense => "Defense: {value}",
    :shop_stat_speed => "Speed: {value}",
    :shop_stat_gold => "Dollars: {value}",
    
    # Shopkeeper messages
    :shopkeeper_not_enough_gold => "Not enough dollars!",
    :shopkeeper_thank_you => "Thank you!",
    :shopkeeper_bought_everything => "You bought everything!",
)

# Helper function to format strings with placeholders
function format_string(key::Symbol; kwargs...)
    str = SHOP_STRINGS[key]
    for (k, v) in kwargs
        str = replace(str, "{$(k)}" => string(v))
    end
    return str
end

export SHOP_STRINGS, format_string

end # module
