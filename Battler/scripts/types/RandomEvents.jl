module RandomEventsModule
include("../generated-types/RandomEventsStructs.jl")
using ..UserModule: apply_out_of_combat_damage!, ensure_out_of_combat_survival!, add_potion!
using ...OverworldFeedbackModule
using ...TreasureChestModule
include("../events/EventBank.jl")

    function handle_random_event(this, event_key::String)
        _handle_random_event(this, ALL_RANDOMEVENTS[event_key])
    end

    function _handle_random_event(this, event)
        @warn "unhandled random event: $(event.key)"
    end

    function handle_accept(this, currentEvent)
        # Track event won in analytics
        try
            Globals.AnalyticsModule.track_action(:event_won)
        catch e
            @debug "Could not track event won: $e"
        end
        
        # Start artwork zoom + SFX + fade
        this.isZooming = true
        this.zoomT = 0.0
        this.fadeToBlackA = 0
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
    end

    function handle_decline(this, currentEvent)
        # Track event ignored in analytics
        try
            Globals.AnalyticsModule.track_action(:event_ignored)
        catch e
            @debug "Could not track event ignored: $e"
        end
        
        # Flip to a brief decline message before leaving
        this.declineShown = true
        this.declineTimer = 0.0
        this.pageIndex = min(length(this.pages), this.pageIndex + 0) # stay on page for message rendering
    end

    function handle_choice(this, currentEvent, choice)
        @debug "Choice: $choice"
    end
end # module 