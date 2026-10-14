function handle_accept(this, event::randomevent_sacrificethefutureforthepresent)
    this.eventResolved = true
    
    # Full heal, but lose max health
    max_hp_loss = 5
    old_health = this.user.health
    
    # Reduce max health first
    this.user.maxHealth = max(1, this.user.maxHealth - max_hp_loss)
    # Full heal to new max
    this.user.health = this.user.maxHealth
    ensure_out_of_combat_survival!(this.user)

    health_gained = this.user.health - old_health
    OverworldFeedbackModule.max_hp!(-max_hp_loss)
    OverworldFeedbackModule.heal!(health_gained)
    if health_gained > 0
        push!(this.pages, EventStringsModule.format_string(:sacrifice_healed, max_hp_loss=max_hp_loss))
    else
        push!(this.pages, EventStringsModule.format_string(:sacrifice_no_heal, max_hp_loss=max_hp_loss))
    end
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
