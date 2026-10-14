# Battle Strings Dictionary
# Used in: scripts/BattleManager.jl, scripts/ComboResponder.jl, scripts/types/Pieces.jl
# Contains all user-facing strings for battle UI, combat feedback, and battle outcomes

module BattleStringsModule

const BATTLE_STRINGS = Dict(
    # Battle outcome
    :battle_victory => "VICTORY!",
    :battle_defeat => "DEFEAT!",
    
    # Battle buttons
    :battle_button_ok => "OK",
    :battle_button_continue => "Continue",
    :battle_button_quit => "Quit",
    :battle_button_return_to_title => "Title",
    :battle_button_skip => "Skip",
    :battle_button_accept => "Accept",
    :battle_button_decline => "Decline",
    
    # Combat feedback
    :combat_healing_blocked => "HEALING BLOCKED!",
    :combat_first_strike => "FIRST STRIKE!",
    :combat_damage => "-{amount}",
    :combat_critical_damage => "-{amount}!",
    
    # Combo messages
    :combo_active => "COMBO x{length}! ({items} items)",
    :combo_complete => "COMBO COMPLETE!\n{length} matches, {items} items",
    :combo_generic => "{count}x COMBO!",
    :combo_typed => "{count}x {type} COMBO!",
    
    # Ability UI
    :ability_panel_title => "Actions",
    :ability_detonator => "Detonator ({uses})",
    :ability_hocus_pocus => "Hocus Pocus ({uses})",
    :ability_nail => "Nail ({uses})",
    :ability_chessboard => "Chessboard ({uses})",
    :ability_sealed_envelope => "Sealed Envelope ({uses})",
    
    # Victory/Defeat screen
    :battle_reward_title => "Bonus Reward:",
    :battle_gold_reward => "+{amount} Gold",
    
    # Combo messages (from ComboResponder)
    :combo_start => "COMBO x1!",
    
    # Special combat messages
    :angel_tears_activated => "ANGEL TEARS!",
    
    # Battle rewards
    :battle_reward_full_heal_name => "Full Heal",
    :battle_reward_full_heal_description => "Restore all health",

    # Reward choice packages
    :battle_reward_choose => "Choose wisely",
    :battle_reward_owned => "(owned)",
    :battle_reward_new => "(new)",
    :battle_reward_new_badge => "NEW",
    :battle_reward_weight_label => "Weight",
    :battle_reward_weight_change => "{old} -> {new}",
    :battle_reward_weight_unknown => "? -> ?",
    :battle_reward_weight_unknown_up => "? -> more",
    :battle_reward_weight_unknown_down => "? -> less",
    :battle_reward_label_piece => "Piece",
    :battle_reward_label_treasure => "Treasure",
    :battle_reward_label_potion => "Potion",
    :battle_reward_label_dollars => "Dollars",
    :battle_reward_label_health => "Health",
    :battle_reward_label_max_health => "Max Health",
    :battle_reward_label_mystery => "???",
    :battle_reward_heal_amount => "+{amount} HP",
    :battle_reward_heal_full => "Full Heal",
    :battle_reward_max_health_amount => "+{amount} Max HP",
    :battle_reward_mystery_up_title => "Random Weight Upgrade",
    :battle_reward_mystery_up_body => "One of your pieces will take up more of the board.\nThe icon cycles through what you own. Take this and it lands on a piece, then that piece's weight goes up.",
    :battle_reward_mystery_down_title => "Random Weight Downgrade",
    :battle_reward_mystery_down_body => "One of your pieces will take up less of the board.\nThe icon cycles through what you own. Take this and it lands on a piece, then that piece's weight goes down.",
    :battle_reward_weight_up_note => "This raises this piece's share of the board.",
    :battle_reward_weight_down_note => "This lowers this piece's share of the board.",
    :battle_reward_skip_title => "Skip Rewards",
    :battle_reward_skip_message => "You will not receive any unselected rewards.\n\nSkip anyway?",
    :battle_reward_skip_cancel => "Cancel",
    
    # Battle feedback messages
    :feedback_recoil => "RECOIL!",
    :feedback_lifesteal => "LIFESTEAL!",
    :feedback_vulnerable => "VULNERABLE!",
    :feedback_miss => "MISS!",
    :feedback_reflect_ready => "REFLECT READY!",
    :feedback_dodge_ready => "DODGE READY!",
    :feedback_frozen => "FROZEN!",
    :feedback_burning => "BURNING!",
    :feedback_poisoned => "POISONED!",
    :feedback_dodge => "Dodged!",
    :feedback_dodge_failed => "Dodge failed!",
    :feedback_blocked => "Blocked!",
    :feedback_reflected => "REFLECTED!",
    :feedback_gold_collected => "+{amount} GOLD",
    :feedback_shield_gained => "+{amount} SHIELD",
    :feedback_damage => "-{amount}",
    :feedback_critical_damage => "-{amount}!",
    :feedback_heal => "+{amount}",
    :feedback_combo_generic => "{count}x COMBO!",
    :feedback_combo_typed => "{count}x {type} COMBO!",
    
    # Enemy intent tooltips
    :enemy_intent_unknown => "Unknown intent",
    :enemy_intent_attack => "The enemy will attack for {value} damage",
    :enemy_intent_defend => "The enemy will defend and gain {value} shield",
    :enemy_intent_heal => "The enemy will heal for {value} health",
    :enemy_intent_skill => "The enemy will use a skill (value: {value})",
    :enemy_intent_bash => "The enemy will bash for {value} damage and apply Vulnerable",
    :enemy_intent_weaken => "The enemy will apply Weaken ({value} stacks); your attacks deal less damage until your turn ends",
    :enemy_intent_heal_king => "The enemy will heal the King for {value} health",
    :enemy_intent_ally_shield => "The enemy will grant {value} shield to each other living ally",
    :enemy_intent_summon => "The enemy will summon {value} crow(s)",
    :enemy_intent_generic => "The enemy will {intent_type} (value: {value})",
    # Enemy intent tooltip: red header line, then one white line per effect
    :enemy_intent_header => "{name} is using:",
    :enemy_intent_default_name => "Enemy",
    :enemy_intent_line_attack => "Attack for {value} damage",
    :enemy_intent_line_defend => "Gain {value} shield",
    :enemy_intent_line_heal => "Heal for {value} health",
    :enemy_intent_line_skill => "Use a skill (value: {value})",
    :enemy_intent_line_apply => "Apply {value} {status}",
    :enemy_intent_line_weaken_note => "Your attacks deal less damage until your turn ends",
    :enemy_intent_line_heal_king => "Heal the King for {value} health",
    :enemy_intent_line_ally_shield => "Grant {value} shield to each other living ally",
    :enemy_intent_line_summon => "Summon {value} crow(s)",
    :enemy_intent_line_generic => "{intent_type} (value: {value})",
)

# Helper function to format strings with placeholders
function format_string(key::Symbol; kwargs...)
    str = BATTLE_STRINGS[key]
    for (k, v) in kwargs
        str = replace(str, "{$(k)}" => string(v))
    end
    return str
end

export BATTLE_STRINGS, format_string

end # module
