function handle_choice(this, event::randomevent_serenefountain, choice::String)
    if choice == "1_1"
        # Take a bath
        this.eventResolved = true
        push!(this.pages, this.currentEvent.page_2_1)
        this.user.health = min(this.user.health + 15, this.user.maxHealth)
        OverworldFeedbackModule.heal!(15)
        this.pageIndex = length(this.pages)
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
    elseif choice == "1_2"
        # Wash your clothes
        this.eventResolved = true
        push!(this.pages, this.currentEvent.page_2_2)
        this.user.maxHealth = this.user.maxHealth + 5
        OverworldFeedbackModule.max_hp!(5)
        this.pageIndex = length(this.pages)
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
    end
end