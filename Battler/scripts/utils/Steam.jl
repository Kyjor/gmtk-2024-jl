module SteamModule
    using ..Globals
    using SteamWorks

    mutable struct Steam
        # Steamworks
        steam_id::UInt64
        steam_name::String
        steam_avatar::String
        steam_friends

        is_initialized::Bool

        function Steam()
            this = new()

            @debug("Initializing Steam")
            this.is_initialized = false
            init_steam(this)
            if this.is_initialized
                init_steam_friends(this)
            end

            return this
        end
    end

    function init_steam(this::Steam)
        if get(ENV, "TEST_MODE", "false") == "true"
            @debug("Skipping Steam initialization in test mode")
            return
        end
        try
            @debug("Trying to initialize Steamworks")
            if SteamWorks.InitSteamAPI() == -1
                @error("Failed to initialize Steamworks")
                return
            end
            
            this.is_initialized = true
            this.steam_id = SteamWorks.UserId[]
        catch e
            @error("Error initializing Steamworks: $(e)")
        end
    end

    function init_steam_friends(this::Steam)
        if get(ENV, "TEST_MODE", "false") == "true" || !this.is_initialized
            @debug("Skipping Steam friends initialization in test mode")
            return
        end
        try
            @debug("Initializing Steam friends")
            this.steam_friends = SteamWorks.LibSteam.SteamAPI_SteamFriends()
        catch e
            @error("Error initializing Steam friends: $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function get_steam_id(this::Steam)
        if !this.is_initialized
            @debug("Skipping Steam ID initialization")
            return
        end
        try
            @debug("Getting Steam ID")
            return SteamWorks.LibSteam.SteamAPI_SteamUser()
        catch e
            @error("Error getting Steam ID: $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function set_rich_presence(this::Steam, status::String)
        if !this.is_initialized
            @debug("Skipping rich presence initialization")
            return
        end
        try
            @debug("Setting rich presence to: $(status)")
            SteamWorks.LibSteam.SteamAPI_ISteamFriends_SetRichPresence(this.steam_friends, "steam_display", "#Status_$status")
        catch e
            @error("Error setting rich presence: $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function set_rich_presence_with_position(this::Steam, status::String, room::Int, floor::Int)
        if !this.is_initialized
            @debug("Skipping rich presence initialization")
            return
        end
        try
            @debug("Setting rich presence to: $(status) at position $(room) on floor $(floor)")
            # Set the position value
            val = SteamWorks.LibSteam.SteamAPI_ISteamFriends_SetRichPresence(this.steam_friends, "position", string(room))

            # Set the floor value
            val = SteamWorks.LibSteam.SteamAPI_ISteamFriends_SetRichPresence(this.steam_friends, "floor", string(floor))

            # Set the display template that includes position
            val = SteamWorks.LibSteam.SteamAPI_ISteamFriends_SetRichPresence(this.steam_friends, "steam_display", "#Status_$(status)_WithPosition")
        catch e
            @error("Error setting rich presence with position: $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function clear_rich_presence(this::Steam)
        if !this.is_initialized
            @debug("Skipping rich presence initialization")
            return
        end
        try
            @debug("Clearing rich presence")
            SteamWorks.LibSteam.SteamAPI_ISteamFriends_ClearRichPresence(this.steam_friends)
        catch e
            @error("Error clearing rich presence: $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    # ------------------------------------------------------------------
    # Achievements / stats (stubs)
    # ------------------------------------------------------------------
    # TODO: Wire these to the Steamworks ISteamUserStats API once achievements
    # are configured in the Steamworks partner dashboard:
    #   stats = SteamWorks.LibSteam.SteamAPI_SteamUserStats()
    #   SteamAPI_ISteamUserStats_SetAchievement(stats, api_name)
    #   SteamAPI_ISteamUserStats_SetStatInt32(stats, stat_name, value)
    #   SteamAPI_ISteamUserStats_StoreStats(stats)

    """
    Unlock a Steam achievement by its API name (stub).
    """
    function unlock_achievement(this::Steam, api_name::String)
        if !this.is_initialized
            @debug("Skipping Steam achievement unlock (not initialized): $(api_name)")
            return
        end
        try
            @debug("STUB: would unlock Steam achievement $(api_name)")
            # TODO: SteamAPI_ISteamUserStats_SetAchievement + StoreStats
        catch e
            @error("Error unlocking Steam achievement $(api_name): $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    """
    Push a lifetime stat value to Steam (stub).
    """
    function set_stat(this::Steam, stat_name::String, value::Int)
        if !this.is_initialized
            @debug("Skipping Steam stat update (not initialized): $(stat_name)=$(value)")
            return
        end
        try
            @debug("STUB: would set Steam stat $(stat_name) to $(value)")
            # TODO: SteamAPI_ISteamUserStats_SetStatInt32
        catch e
            @error("Error setting Steam stat $(stat_name): $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    """
    Flush pending achievement/stat changes to Steam servers (stub).
    """
    function store_stats(this::Steam)
        if !this.is_initialized
            @debug("Skipping Steam stats store (not initialized)")
            return
        end
        try
            @debug("STUB: would store Steam stats")
            # TODO: SteamAPI_ISteamUserStats_StoreStats
        catch e
            @error("Error storing Steam stats: $(e)")
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end
end 