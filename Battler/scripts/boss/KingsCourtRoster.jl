# King's Court boss roster detection (Priest + King + Knight at battle start).
module KingsCourtRosterModule

const _KINGS_COURT_KEYS = Set{String}(["ENEMY_PRIEST", "ENEMY_KING", "ENEMY_KNIGHT"])

"""True when this battle was started with exactly the King's Court trio (boss-only advanced AI)."""
function is_kings_court_startup(current_enemies)::Bool
    current_enemies === nothing && return false
    try
        keys = Set{String}(uppercase(strip(string(e.key))) for e in current_enemies)
        return keys == _KINGS_COURT_KEYS
    catch
        return false
    end
end

export is_kings_court_startup

end # module
