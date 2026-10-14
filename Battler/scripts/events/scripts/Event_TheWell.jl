function handle_accept(this, event::randomevent_thewell)
    this.eventResolved = true
    
    cost = 10
    if this.user.gold < cost
        push!(this.pages, EventStringsModule.format_string(:the_well_insufficient_gold, cost=cost))
        this.pageIndex = length(this.pages)
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
        return
    end
    
    this.user.gold -= cost
    this.user.luck += 100
    OverworldFeedbackModule.gold!(-cost)
    OverworldFeedbackModule.luck!(100)
    
    push!(this.pages, EventStringsModule.format_string(:the_well_success, cost=cost))
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
