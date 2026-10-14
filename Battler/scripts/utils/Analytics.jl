module AnalyticsModule
    using HTTP
    using JSON3
    using Dates
    using ..Globals
    using ..AchievementTrackerModule
    using ..JulGame
    
    const BASE_URL = "https://tqkuynpcwovnfraedsen.supabase.co/rest/v1"
    const ANALYTICS_URL = "$(BASE_URL)/Runs"
    const CRASH_URL = "$(BASE_URL)/Crashes"
    const STARTUPS_URL = "$(BASE_URL)/Startups"
    const ANALYTICS_HEADERS = [
        "apikey" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRxa3V5bnBjd292bmZyYWVkc2VuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDUyNDUzNTEsImV4cCI6MjA2MDgyMTM1MX0.dpmjv5A6Y_ZUnCFII3sgFX_USd4ESaEDHZ6YOhV2XaQ",
        "Authorization" => "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRxa3V5bnBjd292bmZyYWVkc2VuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDUyNDUzNTEsImV4cCI6MjA2MDgyMTM1MX0.dpmjv5A6Y_ZUnCFII3sgFX_USd4ESaEDHZ6YOhV2XaQ",
        "Content-Type" => "application/json",
        "Prefer" => "return=minimal"
    ]

    mutable struct Analytics
        #uuid 4 
        uuid::String
        # Run info
        endDateTime
        startDateTime
        floorsClimbed::Int
        playTimeInSecondsBattle::Int
        character_used::Int
        userIdHashed::String


        # Player info
        current_health::Int
        max_health::Int
        most_damage_dealt::Int
        most_damage_received::Int
        current_gold::Int
        relics_used::String # { cute_bandage: { obtained: "1:reward", uses: 100 }, }

        # actions taken
        potions_used::Int
        rerolls_used::Int
        switches_used::Int
        drags_used::Int
        events_won::Int
        events_ignored::Int
        gold_spent::Int
        enemies_killed::Int
        turns_taken::Int
        longest_combo::Int

        # averages
        average_combo::Int
        average_damage_dealt::Int
        average_damage_received::Int

        # Happenings
        health_lost::Int
        health_gained::Int

        total_damage_dealt::Int
        lowest_health::Int

        # System info
        cpu_name::String
        gpu_name::String
        ram_used::String
        ram_total::String
        os_name::String
        
        user_id_hashed::UInt64
        is_analytics_enabled::Bool

    function Analytics()
        this = new()

        this.cpu_name = String("$(Sys.cpu_info()[1].model)")
        this.gpu_name = "TODO" #Sys.gpu_info()[1].name
        # convert to GB
        this.ram_total = String("$(round(Int, Sys.total_memory() / 1024 / 1024 / 1024)) GB")
        this.ram_used = String("$(round(Int, (Sys.total_memory() - Sys.free_memory()) / 1024 / 1024 / 1024)) GB")
        this.os_name = String(Sys.KERNEL)

        this.user_id_hashed = UInt64(0)

        # Initialize all analytics tracking fields to 0/default values
        this.uuid = ""
        this.endDateTime = ""
        this.startDateTime = ""
        this.floorsClimbed = 0
        this.playTimeInSecondsBattle = 0
        this.character_used = 0
        this.userIdHashed = ""
        this.current_health = 0
        this.max_health = 0
        this.most_damage_dealt = 0
        this.most_damage_received = 0
        this.current_gold = 0
        this.relics_used = "{}"
        this.potions_used = 0
        this.rerolls_used = 0
        this.switches_used = 0
        this.drags_used = 0
        this.events_won = 0
        this.events_ignored = 0
        this.gold_spent = 0
        this.enemies_killed = 0
        this.turns_taken = 0
        this.longest_combo = 0
        this.average_combo = 0
        this.average_damage_dealt = 0
        this.average_damage_received = 0
        this.health_lost = 0
        this.health_gained = 0
        this.total_damage_dealt = 0
        this.lowest_health = 0

        # Load analytics setting from preference file (default to false/disabled)
        this.is_analytics_enabled = false
        analyticsSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "analytics_settings.txt")
        if isfile(analyticsSettingsPath)
            config = Dict{String, Any}()
            open(analyticsSettingsPath, "r") do file
                for line in eachline(file)
                    if contains(line, "=")
                        key, value = split(line, "=")
                        config[key] = value
                    end
                end
            end
            this.is_analytics_enabled = parse(Int, get(config, "AnalyticsEnabled", "0")) == 1
        end
            
        # Allow environment variable override for testing
        if get(ENV, "ANALYTICS_ENABLED", "") == "false"
            this.is_analytics_enabled = false
        elseif get(ENV, "ANALYTICS_ENABLED", "") == "true"
            this.is_analytics_enabled = true
        end
            
        @debug "Analytics initialized with is_analytics_enabled = $(this.is_analytics_enabled)"

        return this
    end
    end

    function reset(this::Analytics)
        # Reset all analytics tracking fields for a new run
        this.floorsClimbed = 0
        this.playTimeInSecondsBattle = 0
        this.character_used = 0
        this.current_health = 0
        this.max_health = 0
        this.most_damage_dealt = 0
        this.most_damage_received = 0
        this.current_gold = 0
        this.relics_used = "{}"
        this.potions_used = 0
        this.rerolls_used = 0
        this.switches_used = 0
        this.drags_used = 0
        this.events_won = 0
        this.events_ignored = 0
        this.gold_spent = 0
        this.enemies_killed = 0
        this.turns_taken = 0
        this.longest_combo = 0
        this.average_combo = 0
        this.average_damage_dealt = 0
        this.average_damage_received = 0
        this.health_lost = 0
        this.health_gained = 0
        this.total_damage_dealt = 0
        this.lowest_health = 0
        this.startDateTime = _analytics_timestamptz_iso(Dates.now(Dates.UTC))
    end
    
    """
    Helper function to safely update analytics fields
    """
    function track_action(action::Symbol, value::Int = 1)
        try
            AchievementTrackerModule.on_action!(action, value)
        catch e
            @debug "Could not mirror action to meta progress ($action): $e"
        end
        Globals.RunRecorderModule.on_action!(action, value)

        try
            data_manager = Globals.get_data_manager()
            if data_manager === nothing
                return
            end
            analytics_data = data_manager.analytics_data
            if analytics_data === nothing || !analytics_data.is_analytics_enabled
                return
            end
            
            if action == :potion_used
                analytics_data.potions_used += value
            elseif action == :reroll_used
                analytics_data.rerolls_used += value
            elseif action == :switch_used
                analytics_data.switches_used += value
            elseif action == :drag_used
                analytics_data.drags_used += value
            elseif action == :enemy_killed
                analytics_data.enemies_killed += value
            elseif action == :turn_taken
                analytics_data.turns_taken += value
            elseif action == :event_won
                analytics_data.events_won += value
            elseif action == :event_ignored
                analytics_data.events_ignored += value
            elseif action == :gold_spent
                analytics_data.gold_spent += value
            elseif action == :damage_dealt
                analytics_data.total_damage_dealt += value
                if value > analytics_data.most_damage_dealt
                    analytics_data.most_damage_dealt = value
                end
            elseif action == :damage_received
                analytics_data.average_damage_received += value
                if value > analytics_data.most_damage_received
                    analytics_data.most_damage_received = value
                end
            elseif action == :combo_length
                if value > analytics_data.longest_combo
                    analytics_data.longest_combo = value
                end
                analytics_data.average_combo += value
            end
        catch e
            @debug "Could not track analytics action $action: $e"
        end
    end
    
    export track_action

    function _analytics_field_or(obj, field::Symbol, default)
        if obj === nothing || !hasproperty(obj, field)
            return default
        end
        try
            value = getproperty(obj, field)
            return value === nothing ? default : value
        catch
            return default
        end
    end

    """Evaluate `f()` for a single analytics payload field; swallow errors and use `default`."""
    function _safe_payload_field(f::Function, default)
        try
            return f()
        catch e
            @debug "analytics payload field failed, using default: $(typeof(e))"
            return default
        end
    end

    function _analytics_timestamptz_iso(dt::DateTime)
        Dates.format(dt, dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"
    end

    """Fire an analytics POST without blocking the caller. Uses Julia `@async` so the request
    runs when the main loop (or other code) calls `yield()` — not JulGame's coroutine system,
    which is frame-sliced for animations and is torn down on every scene change."""
    function _post_async(url::String, body::String, label::String)
        @async begin
            try
                response = HTTP.post(url, ANALYTICS_HEADERS, body)
                if response.status != 201
                    @warn "Failed to send $label: $(response.status) - $(String(response.body))"
                else
                    @debug "$label tracked successfully"
                end
            catch e
                @warn "Failed to send $label: $(e)"
            end
        end
    end

    """Postgres `integer` is int32 (~±2.1e9). Clamp instead of sending oversized values as
    strings — PostgREST still casts numeric strings to integer and rejects them."""
    function _as_int128(x)::Int128
        if x isa Integer
            return Int128(x)
        elseif x isa AbstractFloat
            isfinite(x) || return Int128(0)
            return Int128(round(x))
        elseif x isa AbstractString
            p = tryparse(Int128, strip(x))
            return p === nothing ? Int128(0) : p
        else
            return Int128(0)
        end
    end

    function _postgres_numeric_json(x)::Int
        return Int(clamp(_as_int128(x), Int128(typemin(Int32)), Int128(typemax(Int32))))
    end

    function _character_used_code(sel)::Int
        sel === nothing && return 0
        s = uppercase(string(sel))
        s == "CHARACTER_MAGICIAN" && return 1
        s == "CHARACTER_DEMOLITIONIST" && return 2
        s == "CHARACTER_KNIGHT" && return 3
        return 0
    end


    _outcome_for(run_won) = run_won === true ? "won" : run_won === false ? "died" : "abandoned"

    function track_run_end(this, floors_climbed::Int, max_health::Int; run_won::Union{Nothing,Bool} = nothing,
                           outcome::Union{Nothing,String} = nothing)
        # Check if analytics is enabled in settings
        if !this.is_analytics_enabled
            @debug "Run end tracking skipped: analytics disabled"
            return
        end
        outcome = something(outcome, _outcome_for(run_won))

        try
            # Get additional data from game state
            data_manager = Globals.get_data_manager()
            user_data = _analytics_field_or(data_manager, :user_data, nothing)
            persistent_state = _analytics_field_or(data_manager, :persistent_state_manager, nothing)
            
            longest_combo_reported = _safe_payload_field(
                () -> max(this.longest_combo, _analytics_field_or(persistent_state, :highestComboThisRun, 0)),
                0,
            )

            play_time_seconds = _safe_payload_field(
                () -> round(Int, _analytics_field_or(persistent_state, :runElapsedTime, 0.0)),
                0,
            )

            character_used = _safe_payload_field(
                () -> _character_used_code(_analytics_field_or(user_data, :selectedCharacter, nothing)),
                0,
            )

            relics_json = _safe_payload_field(function ()
                treasures = _analytics_field_or(user_data, :treasures, [])
                if treasures === nothing || isempty(treasures)
                    return "{}"
                end
                relics_dict = Dict{String, Any}()
                for i in eachindex(treasures)
                    isassigned(treasures, i) || continue
                    treasure = treasures[i]
                    treasure_name = _analytics_field_or(treasure, :name, nothing)
                    if treasure_name !== nothing
                        relics_dict[string(treasure_name)] = Dict("obtained" => "run", "uses" => 0)
                    end
                end
                return JSON3.write(relics_dict)
            end, "{}")

            # Build payload one keyed field at a time; each assignment is isolated via _safe_payload_field.
            analytics_payload = Dict{String, Any}()

            analytics_payload["user_id_hash"] = _safe_payload_field(() -> string(this.user_id_hashed), "0")
            analytics_payload["floors_climbed"] = _safe_payload_field(() -> _postgres_numeric_json(floors_climbed), "0")
            analytics_payload["max_health"] = _safe_payload_field(() -> _postgres_numeric_json(max_health), "0")
            analytics_payload["play_time_seconds"] = _safe_payload_field(() -> _postgres_numeric_json(play_time_seconds), "0")
            analytics_payload["character_used"] = character_used
            analytics_payload["current_health"] = _safe_payload_field(
                () -> _postgres_numeric_json(_analytics_field_or(user_data, :health, 0)),
                "0",
            )
            analytics_payload["current_gold"] = _safe_payload_field(
                () -> _postgres_numeric_json(_analytics_field_or(user_data, :gold, 0)),
                "0",
            )
            analytics_payload["final_level"] = _safe_payload_field(
                () -> _postgres_numeric_json(_analytics_field_or(persistent_state, :currentLevel, floors_climbed + 1)),
                string(floors_climbed + 1),
            )
            analytics_payload["relics_used"] = relics_json

            analytics_payload["potions_used"] = _safe_payload_field(() -> _postgres_numeric_json(this.potions_used), "0")
            analytics_payload["rerolls_used"] = _safe_payload_field(() -> _postgres_numeric_json(this.rerolls_used), "0")
            analytics_payload["switches_used"] = _safe_payload_field(() -> _postgres_numeric_json(this.switches_used), "0")
            analytics_payload["drags_used"] = _safe_payload_field(() -> _postgres_numeric_json(this.drags_used), "0")
            analytics_payload["events_won"] = _safe_payload_field(() -> _postgres_numeric_json(this.events_won), "0")
            analytics_payload["events_ignored"] = _safe_payload_field(() -> _postgres_numeric_json(this.events_ignored), "0")
            analytics_payload["gold_spent"] = _safe_payload_field(() -> _postgres_numeric_json(this.gold_spent), "0")
            analytics_payload["enemies_killed"] = _safe_payload_field(() -> _postgres_numeric_json(this.enemies_killed), "0")
            p_turns = _safe_payload_field(() -> this.turns_taken, 0)
            analytics_payload["turns_taken"] = _safe_payload_field(() -> _postgres_numeric_json(p_turns), "0")
            analytics_payload["longest_combo"] = _safe_payload_field(() -> _postgres_numeric_json(longest_combo_reported), "0")
            analytics_payload["most_damage_dealt"] = _safe_payload_field(() -> _postgres_numeric_json(this.most_damage_dealt), "0")
            analytics_payload["most_damage_received"] = _safe_payload_field(() -> _postgres_numeric_json(this.most_damage_received), "0")
            p_total_damage = _safe_payload_field(() -> this.total_damage_dealt, 0)
            analytics_payload["total_damage_dealt"] = _safe_payload_field(() -> _postgres_numeric_json(p_total_damage), "0")
            analytics_payload["lowest_health"] = _safe_payload_field(() -> _postgres_numeric_json(this.lowest_health), "0")
            analytics_payload["health_lost"] = _safe_payload_field(() -> _postgres_numeric_json(this.health_lost), "0")
            analytics_payload["health_gained"] = _safe_payload_field(() -> _postgres_numeric_json(this.health_gained), "0")
            analytics_payload["average_combo"] =
                _safe_payload_field(() -> _postgres_numeric_json(p_turns > 0 ? this.average_combo ÷ p_turns : 0), "0")
            analytics_payload["average_damage_dealt"] =
                _safe_payload_field(() -> _postgres_numeric_json(p_turns > 0 ? p_total_damage ÷ p_turns : 0), "0")
            analytics_payload["average_damage_received"] =
                _safe_payload_field(() -> _postgres_numeric_json(p_turns > 0 ? this.average_damage_received ÷ p_turns : 0), "0")
            end_dt_utc = Dates.now(Dates.UTC)
            end_iso = _analytics_timestamptz_iso(end_dt_utc)
            start_raw = _safe_payload_field(() -> this.startDateTime, "")
            start_iso = if start_raw isa String && !isempty(strip(start_raw))
                strip(start_raw)
            else
                _analytics_timestamptz_iso(end_dt_utc - Dates.Second(max(play_time_seconds, 0)))
            end
            analytics_payload["start_datetime"] = start_iso
            analytics_payload["end_datetime"] = end_iso
            analytics_payload["os_name"] = _safe_payload_field(() -> this.os_name, "")
            analytics_payload["cpu_name"] = _safe_payload_field(() -> this.cpu_name, "")
            if run_won !== nothing
                analytics_payload["run_won"] = run_won
            end
            try
                merge!(analytics_payload, Globals.RunRecorderModule.build_payload(outcome))
            catch e
                @warn "Run recorder payload failed; sending legacy columns only: $(e)"
            end

            body = JSON3.write(analytics_payload)
            _post_async(ANALYTICS_URL, body, "run end ($(outcome), floors=$(floors_climbed), time=$(play_time_seconds)s)")
        catch e
            @warn "Failed to send analytics: $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function _abandoned_relics_json(treasures)::String
        relics = Dict{String, Any}()
        treasures isa AbstractArray || return "{}"
        for i in eachindex(treasures)
            isassigned(treasures, i) || continue
            t = treasures[i]
            t === nothing && continue
            key = ""
            source = "unknown"
            uses = 0
            try
                if t isa AbstractDict
                    haskey(t, "key") && (key = string(t["key"]))
                    haskey(t, "source") && (source = string(t["source"]))
                    haskey(t, "triggers") && (uses = t["triggers"])
                elseif hasproperty(t, :key) && isdefined(t, :key)
                    key = string(getfield(t, :key))
                end
            catch
                continue
            end
            isempty(key) && continue
            relics[key] = Dict("obtained" => source, "uses" => uses)
        end
        return JSON3.write(relics)
    end

    """Copy a payload into JSON-safe containers. Unassigned array slots throw UndefRefError inside JSON3.write."""
    function _json_ready(x, depth::Int = 0)
        depth > 32 && return nothing
        if x isa Number || x isa AbstractString || x isa Bool || x === nothing
            return x
        end
        if x isa AbstractDict
            out = Dict{String, Any}()
            for (k, v) in pairs(x)
                try
                    out[string(k)] = _json_ready(v, depth + 1)
                catch
                end
            end
            return out
        end
        if x isa AbstractArray
            out = Any[]
            for i in eachindex(x)
                isassigned(x, i) || continue
                try
                    push!(out, _json_ready(x[i], depth + 1))
                catch
                end
            end
            return out
        end
        return string(typeof(x))
    end

    """
    Send the run in the on-disk save as `outcome = "abandoned"` (called before a new run replaces it).
    Synchronous with short timeouts so it is not lost if the game quits right after.
    """
    function track_abandoned_run(this)
        (this !== nothing && this.is_analytics_enabled) || return
        try
            raw = Globals.SaveManagerModule.read_saved_run_recorder()
            raw === nothing && return
            payload = Globals.RunRecorderModule.abandoned_payload(raw)
            payload === nothing && return
            loadout = payload["loadout"]
            stats = get(loadout, "stats", Dict{String, Any}())
            stats isa AbstractDict || (stats = Dict{String, Any}())
            node = _postgres_numeric_json(get(loadout, "node", 0))
            elapsed = _postgres_numeric_json(get(loadout, "elapsed", 0))
            end_dt = Dates.now(Dates.UTC)
            item_stats = get(payload, "item_stats", Dict{String, Any}())
            started_raw = item_stats isa AbstractDict ? get(item_stats, "started_at", "") : ""
            started = started_raw === nothing ? "" : string(started_raw)
            payload["user_id_hash"] = isdefined(this, :user_id_hashed) ? string(this.user_id_hashed) : "0"
            payload["floors_climbed"] = max(0, node - 1)
            payload["final_level"] = node
            payload["max_health"] = _postgres_numeric_json(get(stats, "max_health", 0))
            payload["current_health"] = _postgres_numeric_json(get(stats, "health", 0))
            payload["current_gold"] = _postgres_numeric_json(get(stats, "gold", 0))
            payload["character_used"] = _character_used_code(get(loadout, "character", nothing))
            payload["play_time_seconds"] = elapsed
            payload["relics_used"] = _abandoned_relics_json(get(loadout, "treasures", nothing))
            payload["start_datetime"] = isempty(started) ? _analytics_timestamptz_iso(end_dt - Dates.Second(elapsed)) : started
            payload["end_datetime"] = _analytics_timestamptz_iso(end_dt)
            payload["os_name"] = isdefined(this, :os_name) ? this.os_name : ""
            payload["cpu_name"] = isdefined(this, :cpu_name) ? this.cpu_name : ""
            payload["run_won"] = false
            response = HTTP.post(ANALYTICS_URL, ANALYTICS_HEADERS, JSON3.write(_json_ready(payload));
                connect_timeout = 5, readtimeout = 5, retry = false, status_exception = false)
            response.status == 201 || @warn "Failed to send abandoned run: $(response.status) - $(String(response.body))"
        catch e
            @warn "Failed to send abandoned run: $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function track_crash(this::Analytics, error_message::String)
        if !this.is_analytics_enabled
            return
        end

        try
            body = JSON3.write(Dict(
                "error_message" => error_message,
                "os_name" => isdefined(this, :os_name) ? this.os_name : "",
                "cpu_name" => isdefined(this, :cpu_name) ? this.cpu_name : "",
                "gpu_name" => isdefined(this, :gpu_name) ? this.gpu_name : "",
                "ram_used" => isdefined(this, :ram_used) ? this.ram_used : "",
                "ram_total" => isdefined(this, :ram_total) ? this.ram_total : "",
                "user_id_hash" => isdefined(this, :user_id_hashed) ? string(this.user_id_hashed) : "0",
            ))
            response = HTTP.post(CRASH_URL, ANALYTICS_HEADERS, body)

            if response.status != 201
                @warn "Failed to send crash: $(response.status) - $(String(response.body))"
            end
        catch e
            @warn "Failed to send crash: $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function track_startup(this::Analytics)
        if !this.is_analytics_enabled
            @debug "Startup tracking skipped: analytics disabled"
            return
        end

        try
            body = JSON3.write(Dict(
                "user_id_hash" => string(this.user_id_hashed)
            ))
            _post_async(STARTUPS_URL, body, "startup")
        catch e
            @warn "Failed to send startup: $(e)"
        end
    end

    function is_analytics_enabled(this::Analytics)
        if !this.is_analytics_enabled
            return false
        end

        # Get the data manager
        data_manager = Globals.get_data_manager()

        if data_manager === nothing
            return false
        end

        # Get settings from persistent state
        settings = data_manager.persistent_state_manager.settings
        return get(settings, "analytics_enabled", false)
    end

    function Base.setproperty!(this::Analytics, property::Symbol, value)
        if property != :is_analytics_enabled && isdefined(this, :is_analytics_enabled)
            if !this.is_analytics_enabled
                return
            end
        end
        if property == :user_id_hashed
            value = hash(value)
        end
        if property == :is_analytics_enabled && get(ENV, "ANALYTICS_ENABLED", "") != "true"
            # if ccall(:jl_generating_output, Cint, ()) == 0
            #     @info "Analytics disabled because dev mode is enabled"
            #     value = false
            # end
        end
        setfield!(this, property, value)
    end

    export track_run_end, track_startup, track_abandoned_run
end 