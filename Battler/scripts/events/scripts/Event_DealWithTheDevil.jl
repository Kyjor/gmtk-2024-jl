function handle_accept(this, event::randomevent_dealwiththedevil)
    this.eventResolved = true
    
    # Double base attack
    attack_gain = max(1, this.user.attack)
    this.user.attack += attack_gain
    OverworldFeedbackModule.attack!(attack_gain)
    
    # Block healing for the next battle
    this.persistentStateManager.playerData["heal_blocked"] = true
    
    push!(this.pages, EventStringsModule.format_string(:deal_with_devil_success, attack_gain=attack_gain))
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
