# Event Strings Dictionary
# Used in: scripts/EventManager.jl
# Contains all user-facing strings for random events, event UI, and event outcomes

module EventStringsModule

# Event outcome messages
const EVENT_STRINGS = Dict(
    # Number guess event
    :number_guess_correct => "Correct! You gained 5 max health!",
    :number_guess_incorrect => "Wrong! The number was {number}. You lost 1 max health.",
    
    # Coin flip event
    :coin_flip_win => "It's {result}! You won 10 dollars!",
    :coin_flip_lose => "It's {result}! Better luck next time!",
    
    # Mystery box outcomes
    :mystery_box_dollars => "You found {value} dollars!",
    :mystery_box_attack => "You found a magic scroll! +{value} Attack",
    :mystery_box_defense => "You found a shield charm! +{value} Defense",
    :mystery_box_max_health => "You found a health charm! +{value} Max Health",
    :mystery_box_health => "You found a healing potion! +{value} Health",
    :mystery_box_bad_health => "It was trapped! You lost {value} Health",
    :mystery_box_bad_dollars => "It was trapped! You lost {value} Gold",
    
    # Double or nothing event
    :double_or_nothing_no_gold => "You don't have enough dollars!",
    :double_or_nothing_win => "You doubled your dollars! +5 dollars!",
    :double_or_nothing_lose => "You lost your 5 dollars!",
    
    # Sacrifice health event
    :sacrifice_health_insufficient => "You don't have enough health to sacrifice!",
    :sacrifice_health_success => "You sacrificed 5 health and gained +2 Attack!",
    
    # Health gamble event
    :health_gamble_win => "Lucky! You gained 10 health!",
    :health_gamble_lose => "Unlucky! You lost 5 health!",
    
    # Event UI buttons
    :event_button_yes => "Yes",
    :event_button_no => "No",
    :event_button_continue => "Continue",
    :event_button_exit => "Exit",
    
    # Event decline message
    :event_decline_message => "You decide against it.",
    
    # Event narrative text (default pages)
    :event_mousehole_page1 => "Your body begins to shrink in size as you walk down the dark alley.",
    :event_mousehole_page2 => "There's a hole in the nearby wall...\n\nWill you attempt to enter?",
    :event_restsite_page1 => "You find a comfortable spot to rest and heal.",
    :event_restsite_page2 => "Rest, or offer something to the flame?",
    
    # Event odds display
    :event_odds_success => "{percent}% success",
    :event_odds_special => "{percent}% special",
    :event_odds_failure => "{percent}% failure",
    
    # Typing effect indicator
    :typing_completion_indicator => "▼",
    
    # Deal with the Devil
    :deal_with_devil_success => "The devil accepts your bargain. Your attack doubles! (+{attack_gain} Attack)\n\nYou cannot heal in your next battle.",
    
    # Cursed Chest
    :cursed_chest_gold => "The chest contains {gold_amount} dollars!",
    :cursed_chest_attack => "You find a power gem! +1 Attack",
    :cursed_chest_defense => "You find a protective charm! +1 Defense",
    :cursed_chest_curse => "The chest was cursed! You lose {max_hp_loss} max health.",
    :cursed_chest_treasure => "You find a treasure: {treasure_name}!",
    
    # Dark Door
    :dark_door_treasure_dollars => "Behind the door lies a treasure room! +{gold_amount} dollars!",
    :dark_door_treasure_attack => "You find an ancient weapon! +2 Attack!",
    :dark_door_ambush => "Ambush! Enemies attack from the shadows! -{damage} health!",
    
    # Mouse Hole
    :mouse_hole_gold => "You squeeze through and find {gold_amount} dollars hidden inside!",
    :mouse_hole_heal => "You find a cozy spot and rest. +{heal_amount} health!",
    :mouse_hole_damage => "You get stuck and scrape yourself badly. -{damage} health!",
    :mouse_hole_special => "You discover a magical acorn! +5 max health!",
    
    # Strange Merchant
    :strange_merchant_no_dollars => "You don't have enough dollars! The merchant shoos you away.",
    :strange_merchant_heal => "The potion heals you for {heal_amount} health!",
    :strange_merchant_poison => "It was poison! You take {damage} damage!",
    :strange_merchant_legendary => "It's a legendary elixir! +2 Attack and +2 Defense!",
    
    # The Well
    :the_well_insufficient_dollars => "You need at least {cost} dollars to make a wish.",
    :the_well_success => "You toss {cost} dollars into the well. You feel luckier! 100% Luck to start the next battle.",
    
    # Sacrifice The Future For The Present
    :sacrifice_healed => "You feel invigorated! Fully healed, but your max health is reduced by {max_hp_loss}.",
    :sacrifice_no_heal => "The sacrifice is made. Your max health is reduced by {max_hp_loss}.",
    
    # Coin Toss
    :coin_toss_win => "The coin lands in your favor! You gain {heal_amount} health.",
    :coin_toss_lose => "The coin betrays you! You lose {damage} health.",
    
    # Rest Site
    :rest_site_heal => "You rest and recover {heal_amount} health.",
    :rest_site_rest => "Rest",
    :rest_site_offer => "Offer",

    # Rest Site fire pit
    :fire_offer_gold => "Money",
    :fire_offer_health => "Health",
    :fire_offer_potion => "Potion",
    :fire_offer_back => "Back",
    :fire_offer_gold_text => "You decide to cast away your wealth to the flame.",
    :fire_offer_health_text => "You scorch your remains in the flame.",
    :fire_offer_potion_text => "You drop a full potion bottle into the flame.",
    :fire_reward_dud => "The flame crackles, then settles. You leave with nothing.",
    :fire_reward_gold => "Dollars fly out from the fire. +{amount} dollars.",
    :fire_reward_heal => "Your body recovers some health. +{amount} health.",
    :fire_reward_max_hp => "Your body grows more resilient. +{amount} max health.",
    :fire_reward_potion => "A bottle rolls out from the ashes: {name}.",
    :fire_reward_treasure => "Something valuable shines from the ashes: {name}.",

    # Unmarked Grave
    :unmarked_grave_no_potion_slot => "Your potion pouch is full. You leave the remains untouched.",

    # Three Doors
    :three_doors_leave => "Leave",
    :three_doors_treasure => "A purse of {gold_amount} dollars sits behind the door.",
    :three_doors_pain => "Pain. You take {damage} damage.",
    :three_doors_nothing => "Nothing. The doorway is empty.",

    # Treasure Chest (map treasure node)
    :treasure_chest_intro => "A treasure chest sits alone in the dark, ready to be opened.",
    :treasure_chest_take => "Take",
    :treasure_chest_leave => "Leave",
    :treasure_chest_found => "{treasure_name}: {treasure_desc}",
    :treasure_chest_gold => "You find {gold_amount} dollars inside.",
    :treasure_chest_taken => "You take the {treasure_name}.",
    :treasure_chest_gold_taken => "You take {gold_amount} dollars.",
    :treasure_chest_left => "You close the lid and leave with nothing.",
)

# Helper function to format strings with placeholders
function format_string(key::Symbol; kwargs...)
    str = EVENT_STRINGS[key]
    for (k, v) in kwargs
        str = replace(str, "{$(k)}" => string(v))
    end
    return str
end

export EVENT_STRINGS, format_string

end # module
