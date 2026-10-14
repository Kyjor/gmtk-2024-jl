function handle_accept(this, event::randomevent_restsite)
    this.eventResolved = true
    
    heal_amount = round(Int, this.user.maxHealth * 0.25)
    before = this.user.health
    this.user.health = min(this.user.health + heal_amount, this.user.maxHealth)
    gained = this.user.health - before
    OverworldFeedbackModule.heal!(gained > 0 ? gained : heal_amount)
    Globals.RunRecorderModule.record!("rest"; healed = gained, hp = this.user.health)
    
    push!(this.pages, EventStringsModule.format_string(:rest_site_heal, heal_amount=heal_amount))
    this.pageIndex = length(this.pages)
    
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end