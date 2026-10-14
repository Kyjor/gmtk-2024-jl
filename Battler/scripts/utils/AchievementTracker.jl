module AchievementTrackerModule
    using ..Globals
    using ..MetaProgressModule
    using JSON3

    export get_all_achievements, get_achievement, unlock_hint_for_item,
        achievement_progress, on_action!, track_stat!, track_stat_max!, on_run_end!,
        check_achievements!, sync_steam_achievements!

    # Baked at compile time like other game data so built exes don't need the file on disk.
    const ACHIEVEMENTS_JSON_BYTES = read(joinpath(@__DIR__, "..", "..", "assets", "game-data-manager", "json", "Achievements.json"))

    struct Achievement
        key::String
        icon::String                 # "type/slug" resolved via get_asset_path
        en_name::String
        en_desc::String
        jp_name::String
        jp_desc::String
        condition_type::String
        condition_stat::String
        condition_value::Int
        unlocks::Vector{String}      # item keys granted on completion
        steam_api_name::String
    end

    function name(achievement::Achievement)
        lang = lowercase(Globals.get_current_language())
        if lang == "jp" && !isempty(achievement.jp_name)
            return achievement.jp_name
        end
        return achievement.en_name
    end

    function description(achievement::Achievement)
        lang = lowercase(Globals.get_current_language())
        if lang == "jp" && !isempty(achievement.jp_desc)
            return achievement.jp_desc
        end
        return achievement.en_desc
    end

    # Catalog (loaded once) + reverse map: item key -> achievement that unlocks it.
    const _ACHIEVEMENTS = Ref{Union{Vector{Achievement}, Nothing}}(nothing)
    const _UNLOCK_SOURCE = Dict{String, Achievement}()

    function _parse_achievement(entry)::Achievement
        unlocks = String[]
        raw_unlocks = string(get(entry, "Unlocks", ""))
        for key in split(raw_unlocks, ",")
            trimmed = strip(key)
            isempty(trimmed) || push!(unlocks, String(trimmed))
        end
        return Achievement(
            string(entry["Key"]),
            string(get(entry, "Icon", "")),
            string(get(entry, "EN_NAME", "")),
            string(get(entry, "EN_DESC", "")),
            string(get(entry, "JP_NAME", "")),
            string(get(entry, "JP_DESC", "")),
            string(get(entry, "Condition_Type", "stat_threshold")),
            string(get(entry, "Condition_Stat", "")),
            Int(get(entry, "Condition_Value", 1)),
            unlocks,
            string(get(entry, "Steam_API_Name", "")),
        )
    end

    function get_all_achievements()::Vector{Achievement}
        if _ACHIEVEMENTS[] === nothing
            achievements = Achievement[]
            try
                path = joinpath(@__DIR__, "..", "..", "assets", "game-data-manager", "json", "Achievements.json")
                bytes = isfile(path) ? read(path) : ACHIEVEMENTS_JSON_BYTES
                for entry in JSON3.read(String(copy(bytes)))
                    push!(achievements, _parse_achievement(entry))
                end
            catch e
                @error "Failed to load achievements data: $e"
            end
            _ACHIEVEMENTS[] = achievements
            empty!(_UNLOCK_SOURCE)
            for achievement in achievements, item_key in achievement.unlocks
                _UNLOCK_SOURCE[item_key] = achievement
            end
        end
        return _ACHIEVEMENTS[]
    end

    function get_achievement(key::String)::Union{Achievement, Nothing}
        for achievement in get_all_achievements()
            achievement.key == key && return achievement
        end
        return nothing
    end

    """The achievement that unlocks `item_key`, or nothing (locked forever hint)."""
    function unlock_hint_for_item(item_key::String)::Union{Achievement, Nothing}
        get_all_achievements() # ensure reverse map is built
        return get(_UNLOCK_SOURCE, item_key, nothing)
    end

    """Progress toward an achievement in 0.0–1.0 (1.0 when complete)."""
    function achievement_progress(meta, achievement::Achievement)::Float64
        achievement.key in meta.completed_achievements && return 1.0
        achievement.condition_value <= 0 && return 0.0
        current = MetaProgressModule.get_stat(meta, achievement.condition_stat)
        return clamp(current / achievement.condition_value, 0.0, 1.0)
    end

    # ------------------------------------------------------------------
    # Stat recording + achievement evaluation
    # ------------------------------------------------------------------

    # Analytics actions mirrored into always-on local lifetime stats.
    const _ACTION_STAT_MAP = Dict{Symbol, String}(
        :potion_used => "potions_used",
        :enemy_killed => "enemies_killed",
        :gold_spent => "gold_spent",
        :damage_dealt => "total_damage_dealt",
        :turn_taken => "turns_taken",
        :switch_used => "switches_used",
        :reroll_used => "rerolls_used",
    )

    function _meta()
        return Globals.get_meta_progress()
    end

    """Mirror an analytics action into lifetime stats (called from track_action,
    before the analytics opt-in gate, so meta stats are always recorded)."""
    function on_action!(action::Symbol, value::Int = 1)
        meta = _meta()
        if action == :combo_length
            MetaProgressModule.record_stat_max!(meta, "longest_combo", value)
        else
            stat_key = get(_ACTION_STAT_MAP, action, nothing)
            stat_key === nothing && return
            MetaProgressModule.record_stat!(meta, stat_key, value)
        end
        check_achievements!(meta)
    end

    """Directly increment a lifetime stat and evaluate achievements."""
    function track_stat!(stat_key::String, delta::Int = 1; save::Bool = false)
        meta = _meta()
        MetaProgressModule.record_stat!(meta, stat_key, delta)
        changed = check_achievements!(meta)
        if save && !changed
            # check_achievements! already saves on change; persist the stat bump too.
            MetaProgressModule.try_save_profile!(meta)
        end
    end

    """Directly record a high-water-mark stat and evaluate achievements."""
    function track_stat_max!(stat_key::String, value::Int)
        meta = _meta()
        MetaProgressModule.record_stat_max!(meta, stat_key, value)
        check_achievements!(meta)
    end

    """
    Merge run-level results into lifetime stats at run end and persist the profile.
    """
    function on_run_end!(; run_won::Bool = false)
        meta = _meta()
        try
            MetaProgressModule.record_stat!(meta, run_won ? "runs_won" : "runs_lost")

            data_manager = Globals.get_data_manager()
            psm = data_manager.persistent_state_manager
            if psm !== nothing
                MetaProgressModule.record_stat_max!(meta, "floors_reached_best", psm.currentFloor)
                MetaProgressModule.record_stat_max!(meta, "longest_combo", psm.highestComboThisRun)
                MetaProgressModule.record_stat!(meta, "total_play_time_sec", round(Int, psm.runElapsedTime))
            end

            user = data_manager.user_data
            if run_won && user !== nothing && !isempty(user.selectedCharacter)
                MetaProgressModule.record_stat!(meta, "runs_won_$(user.selectedCharacter)")
            end
        catch e
            @error "Failed to merge run-end stats into profile: $e"
        end

        check_achievements!(meta)
        MetaProgressModule.try_save_profile!(meta)
    end

    """
    Evaluate all incomplete achievements against lifetime stats. Grants unlocks,
    notifies Steam, and saves the profile when anything completed.
    Returns true when at least one achievement completed.
    """
    function check_achievements!(meta)::Bool
        changed = false
        for achievement in get_all_achievements()
            achievement.key in meta.completed_achievements && continue
            achievement.condition_type == "stat_threshold" || continue
            if MetaProgressModule.get_stat(meta, achievement.condition_stat) >= achievement.condition_value
                _complete_achievement!(meta, achievement)
                changed = true
            end
        end
        changed && MetaProgressModule.try_save_profile!(meta)
        return changed
    end

    function _complete_achievement!(meta, achievement::Achievement)
        push!(meta.completed_achievements, achievement.key)
        @debug "Achievement completed: $(achievement.key)"
        for item_key in achievement.unlocks
            MetaProgressModule.unlock_item!(meta, item_key)
        end
        _notify_steam_achievement(achievement)
    end

    function _notify_steam_achievement(achievement::Achievement)
        isempty(achievement.steam_api_name) && return
        try
            data_manager = Globals.get_data_manager()
            # Do not force Steam initialization here (see Globals: Steam must load lazily).
            steam = data_manager.steam_data
            steam === nothing && return
            Globals.SteamModule.unlock_achievement(steam, achievement.steam_api_name)
            Globals.SteamModule.store_stats(steam)
        catch e
            @debug "Steam achievement notify failed for $(achievement.key): $e"
        end
    end

    """
    Push already-completed achievements to Steam (stub until ISteamUserStats is wired).
    Safe to call after profile load when Steam becomes available.
    """
    function sync_steam_achievements!(meta)
        for achievement in get_all_achievements()
            achievement.key in meta.completed_achievements || continue
            _notify_steam_achievement(achievement)
        end
        try
            steam = Globals.get_data_manager().steam_data
            steam === nothing && return
            Globals.SteamModule.store_stats(steam)
        catch e
            @debug "Steam stats store failed during achievement sync: $e"
        end
    end
end
