function handle_choice(this, event::randomevent_unmarkedgrave, choice::String)
    @debug "Choice: $choice"
    if choice == "1_1"
        # Search the grave
        this.eventResolved = true
        if length(this.user.potions) >= this.user.max_potions
            push!(this.pages, EventStringsModule.EVENT_STRINGS[:unmarked_grave_no_potion_slot])
        else
            push!(this.pages, this.currentEvent.page_2_1)
            apply_out_of_combat_damage!(this.user, 6)
            potion_count = length(this.user.potions)
            add_potion!(this.user, "RANDOM", 1)
            OverworldFeedbackModule.damage!(6)
            if length(this.user.potions) > potion_count
                OverworldFeedbackModule.potion!(1; key = last(this.user.potions).key)
            end
        end
        this.pageIndex = length(this.pages)
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
    elseif choice == "1_2"
        # Leave the grave
        this.eventResolved = true
        push!(this.pages, this.currentEvent.page_2_2)
        this.pageIndex = length(this.pages)
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
    end
end