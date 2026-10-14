function handle_accept(this, event::randomevent_flipacoin)
    this.eventResolved = true
    
    if rand() * 100 < event.success
        heal_amount = 10
        before = this.user.health
        this.user.health = min(this.user.health + heal_amount, this.user.maxHealth)
        OverworldFeedbackModule.heal!(this.user.health - before)
        push!(this.pages, EventStringsModule.format_string(:coin_toss_win, heal_amount=heal_amount))
    else
        damage = 10
        apply_out_of_combat_damage!(this.user, damage)
        OverworldFeedbackModule.damage!(damage)
        push!(this.pages, EventStringsModule.format_string(:coin_toss_lose, damage=damage))
    end
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end