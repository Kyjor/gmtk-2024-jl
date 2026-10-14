module MetaProgressModule
    using ..Globals
    using JulGame
    using JulGame.SaveSystemModule: SaveStore, write_save, read_save, delete_save,
        SaveNotFound, SaveRestoredFromBackup

    export MetaProgress, load_meta_progress, try_save_profile!,
        record_stat!, record_stat_max!, get_stat,
        is_unlocked, unlock_item!, completion_ratio

    const PROFILE_SLOT = "profile"
    const PROFILE_SCHEMA_VERSION = 1

    # Items every new profile starts with (character starting loadouts + basics).
    const STARTER_PIECES = (
        "PIECE_SWORD", "PIECE_SHIELD", "PIECE_POTION", "PIECE_SKULL",
        "PIECE_DODGE", "PIECE_CRIMSONBLADE", "PIECE_GREENGEM",
        "PIECE_GRENADE", "PIECE_LUCKY",
    )
    const STARTER_TREASURES = ("TREASURE_HOCUSPOCUS", "TREASURE_DETONATOR", "TREASURE_CUTEBANDAGE")
    const STARTER_POTIONS = ("POTION_BOMB", "POTION_BASICBATTERY")

    mutable struct MetaProgress
        schema_version::Int
        unlocked_pieces::Set{String}
        unlocked_treasures::Set{String}
        unlocked_potions::Set{String}
        completed_achievements::Set{String}
        lifetime_stats::Dict{String, Int}
        tutorial_completed::Bool

        function MetaProgress()
            this = new()
            this.schema_version = PROFILE_SCHEMA_VERSION
            this.unlocked_pieces = Set{String}(STARTER_PIECES)
            this.unlocked_treasures = Set{String}(STARTER_TREASURES)
            this.unlocked_potions = Set{String}(STARTER_POTIONS)
            this.completed_achievements = Set{String}()
            this.lifetime_stats = Dict{String, Int}()
            this.tutorial_completed = false
            return this
        end
    end

    # ------------------------------------------------------------------
    # Persistence (profile.json, alongside run.json — same encrypted store)
    # ------------------------------------------------------------------

    function _profile_store()
        # Same directory and secret as SaveManager, but a separate schema version
        # so profile migrations are independent of run-save migrations.
        base = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "", create_dir = true)
        dir = joinpath(base, "saves")
        mkpath(dir)
        return SaveStore(;
            directory = dir,
            secret_key = Globals.SAVE_DATA_SECRET_KEY,
            version = PROFILE_SCHEMA_VERSION,
            max_backups = 2,
        )
    end

    function _serialize_profile(meta::MetaProgress)
        return Dict{String, Any}(
            "schema" => meta.schema_version,
            "unlocked_pieces" => sort!(collect(meta.unlocked_pieces)),
            "unlocked_treasures" => sort!(collect(meta.unlocked_treasures)),
            "unlocked_potions" => sort!(collect(meta.unlocked_potions)),
            "completed_achievements" => sort!(collect(meta.completed_achievements)),
            "lifetime_stats" => Dict{String, Any}(k => v for (k, v) in meta.lifetime_stats),
            "tutorial_completed" => meta.tutorial_completed,
        )
    end

    function _string_set(raw)::Set{String}
        result = Set{String}()
        raw === nothing && return result
        for value in raw
            push!(result, string(value))
        end
        return result
    end

    function _restore_profile!(meta::MetaProgress, payload)
        # Union with starters so new starter items appear for existing profiles.
        union!(meta.unlocked_pieces, _string_set(get(payload, "unlocked_pieces", nothing)))
        union!(meta.unlocked_treasures, _string_set(get(payload, "unlocked_treasures", nothing)))
        union!(meta.unlocked_potions, _string_set(get(payload, "unlocked_potions", nothing)))
        meta.completed_achievements = _string_set(get(payload, "completed_achievements", nothing))
        stats_raw = get(payload, "lifetime_stats", nothing)
        if stats_raw !== nothing
            for (k, v) in pairs(stats_raw)
                meta.lifetime_stats[string(k)] = Int(v)
            end
        end
        meta.tutorial_completed = get(payload, "tutorial_completed", false) === true
    end

    """
    Load the persistent profile from disk, falling back to a fresh default
    profile (starter unlocks only) when no save exists or loading fails.
    """
    function load_meta_progress()::MetaProgress
        meta = MetaProgress()
        try
            status, payload = read_save(_profile_store(), PROFILE_SLOT)
            if status == SaveNotFound || payload === nothing
                @debug "No profile save found, starting fresh"
                return meta
            end
            if status == SaveRestoredFromBackup
                @warn "Profile save restored from backup"
            end
            _restore_profile!(meta, payload)
        catch e
            @error "Failed to load profile save, using defaults: $e"
        end
        return meta
    end

    function try_save_profile!(meta::MetaProgress)::Bool
        try
            return write_save(_profile_store(), PROFILE_SLOT, _serialize_profile(meta))
        catch e
            @error "Failed to save profile: $e"
            return false
        end
    end

    # ------------------------------------------------------------------
    # Lifetime stats
    # ------------------------------------------------------------------

    get_stat(meta::MetaProgress, key::String)::Int = get(meta.lifetime_stats, key, 0)

    """Increment a lifetime stat by `delta`. Does not save — callers batch saves."""
    function record_stat!(meta::MetaProgress, key::String, delta::Int = 1)
        meta.lifetime_stats[key] = get_stat(meta, key) + delta
    end

    """Record a high-water-mark stat (e.g. longest combo, deepest floor)."""
    function record_stat_max!(meta::MetaProgress, key::String, value::Int)
        if value > get_stat(meta, key)
            meta.lifetime_stats[key] = value
        end
    end

    # ------------------------------------------------------------------
    # Unlocks
    # ------------------------------------------------------------------

    function _unlock_set_for_key(meta::MetaProgress, item_key::String)
        startswith(item_key, "PIECE_") && return meta.unlocked_pieces
        startswith(item_key, "TREASURE_") && return meta.unlocked_treasures
        startswith(item_key, "POTION_") && return meta.unlocked_potions
        return nothing
    end

    function is_unlocked(meta::MetaProgress, item_key::String)::Bool
        unlock_set = _unlock_set_for_key(meta, item_key)
        return unlock_set !== nothing && item_key in unlock_set
    end

    """Unlock an item by key (type inferred from PIECE_/TREASURE_/POTION_ prefix).
    Returns true if the item was newly unlocked."""
    function unlock_item!(meta::MetaProgress, item_key::String)::Bool
        unlock_set = _unlock_set_for_key(meta, item_key)
        if unlock_set === nothing
            @warn "Unknown unlock key prefix: $item_key"
            return false
        end
        item_key in unlock_set && return false
        push!(unlock_set, item_key)
        @debug "Necropedia unlock: $item_key"
        return true
    end

    """Return (unlocked, total) for a catalog dict of key => item."""
    function completion_ratio(meta::MetaProgress, catalog)::Tuple{Int, Int}
        total = 0
        unlocked = 0
        for key in keys(catalog)
            total += 1
            if is_unlocked(meta, string(key))
                unlocked += 1
            end
        end
        return (unlocked, total)
    end
end
