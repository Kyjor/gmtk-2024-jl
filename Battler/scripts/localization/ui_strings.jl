# UI Strings Dictionary
# Used in: scripts/Title.jl, scripts/ConfirmationDialog.jl, scripts/MainSettings.jl
# Contains general UI strings, buttons, and common interface elements

module UIStringsModule

const UI_STRINGS = Dict(
    # Confirmation dialog
    :confirm_button => "Confirm",
    :cancel_button => "Cancel",
    :start_new_run => "Start New Run",
    
    # Title screen confirmation
    :title_new_run_title => "New Run",
    :title_new_run_message => "Starting a new run will erase your current progress.\n\nAre you sure you want to continue?",
    
    # Settings
    :settings_main_menu => "Main Menu",
    :settings_map => "Map",
    :settings_fast_mode => "Fast Mode",
    
    # Release notes
    :release_notes_title => "Release Notes",
    :release_notes_close_hint => "Press F1 to close",
    :release_notes_open_hint => "Press F1 for release notes",
    
    # Acknowledgments / notices
    :ack_early_access_title => "Early Access Notice",
    :ack_early_access_message => "This game is in Early Access. You may encounter bugs, incomplete features, and unexpected issues.\n\nYour feedback is valuable! Please report any problems or suggestions on our Discord community.",
    :ack_early_access_button => "I Understand",
    
    :ack_analytics_title => "Help Us Improve the Game",
    :ack_analytics_message => "We'd love your help! This game can collect anonymous usage data to improve gameplay and fix bugs. No personal information is collected.\n\nWould you like to enable analytics? You can change this later in Settings.",
    :ack_analytics_button_enable => "Enable Analytics",
    :ack_analytics_button_no_thanks => "No Thanks",
    
    :ack_terms_title => "Terms of Service",
    :ack_terms_message => "By playing this game, you agree to our Terms of Service and Privacy Policy.\n\nPlease visit our website for the complete terms.",
    :ack_terms_button => "I Accept",
    
    # Character selection
    :character_select_title => "Select Character:",
    :character_locked => "Locked...",
    :character_stats => "HP {hp}   ATK {atk}   DEF {def}",
    :character_starting_pieces => "Starting pieces:",
    :character_activate_label => "Active:",
    :character_passive_label => "Passive:",
    :character_start_button => "Start",
    :character_back_button => "Back",
    :character_unknown_treasure => "Unknown Treasure",
    :character_no_description => "No description available",
    :character_no_passive => "No passive ability",
    :character_passive_magician => "Starfall: Combo stars strike random enemies for 1 damage each.",
    :character_passive_demolitionist => "Starts every battle with a free Giga Bomb potion.",
    :character_unknown_piece => "Unknown piece",

    # Necropedia
    :necropedia_menu_label => "Necropedia",
    :necropedia_title => "NECROPEDIA",
    :necropedia_back => "Back",
    :necropedia_section_unlocks => "Unlocks",
    :necropedia_section_stats => "Stats",
    :necropedia_section_achievements => "Achievements",
    :necropedia_sub_pieces => "Pieces",
    :necropedia_sub_treasures => "Treasures",
    :necropedia_sub_potions => "Potions",
    :necropedia_locked_name => "???",
    :necropedia_locked_hint => "Complete an achievement to reveal.",
    :necropedia_completed => "Completed",
    :necropedia_unlocks_prefix => "Unlocks:",
    :necropedia_stat_runs_started => "Runs Started",
    :necropedia_stat_runs_won => "Runs Won",
    :necropedia_stat_runs_lost => "Runs Lost",
    :necropedia_stat_enemies => "Enemies Slain",
    :necropedia_stat_combo => "Best Combo",
    :necropedia_stat_floor => "Deepest Floor",
    :necropedia_stat_playtime => "Play Time",
    :necropedia_stat_collection => "Collection",
    :necropedia_stat_damage => "Damage Dealt",
    :necropedia_stat_potions => "Potions Used",
    :necropedia_stat_gold => "Gold Spent",
    :necropedia_scroll_hint => "Up/Down to scroll",
    
    # Current Run Status
    :current_run_continue => "Continue run?",
    :current_run_title => "Current Run:",
    :current_run_game_time => "Game time: {time}",
    :current_run_floor => "Floor {floor}",
    :current_run_room => "Room {room}",
    :current_run_pieces_count => "({count}) Pieces:",
    :current_run_treasures_count => "({count}) Treasures:",
    :current_run_tooltip_attack => "Attack: {value}",
    :current_run_tooltip_defense => "Defense: {value}",
    :current_run_tooltip_weight => "Weight: {percent}%",

    # Current Run Status - Map status
    :current_run_status_traversing => "...Traversing the map...",
    :current_run_status_battling => "...Battling...",
    :current_run_status_random_event => "...Random Event...",
    :current_run_status_resting => "...Resting...",
    :current_run_status_shopping => "...Shopping...",
    
    # Post-run (battle end) screen
    :post_run_victory => "Victory!",
    :post_run_defeat => "Defeat!",
    :post_run_thank_you => "Thank you for playing...",
    :post_run_blurb => "If you enjoyed the game, please give it a Wishlist! Stay tuned as we continue to develop the game! More items, more characters, more floors...",
    :post_run_blurb2 => "Get the latest news and developments in our Discord! Wishlist on Steam!",
    :post_run_highest_combo => "Highest combo: {n}",
    :post_run_exit => "Exit",
    :post_run_wishlist => "Wishlist!",
    :post_run_discord => "Discord",
    :post_run_necro_part => "NECRO",
    :post_run_matcher_part => "MATCHER",

    # Player death / game over
    :game_over_title => "Game Over",
    :game_over_question => "?",
    :game_over_continue => "New run",
    :game_over_exit => "Exit",
)

# Helper function to format strings with placeholders
function format_string(key::Symbol; kwargs...)
    str = UI_STRINGS[key]
    for (k, v) in kwargs
        str = replace(str, "{$(k)}" => string(v))
    end
    return str
end

export UI_STRINGS, format_string

end # module
