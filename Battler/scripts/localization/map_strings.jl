# Map Strings Dictionary
# Used in: scripts/MapManager.jl
# Contains all user-facing strings for map navigation and tooltips

module MapStringsModule

const MAP_STRINGS = Dict(
    # Map tooltips
    :map_tooltip_default => "Hover over a location to see what awaits you...",
    
    # Map UI
    :map_regen_button => "Regen Map",
    
    # Reward dialog
    :map_reward_accept => "Accept",
    :map_reward_decline => "Decline",
)

# Helper function to get encounter tooltip text
# This should be generated dynamically based on encounter type
function get_encounter_tooltip_text(encounter_type::String)
    # This is a placeholder - actual implementation should use encounter data
    return "Encounter: $encounter_type"
end

export MAP_STRINGS, get_encounter_tooltip_text

end # module
