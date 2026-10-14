function handle_accept(this, event::randomevent_darkdoor)
    this.eventResolved = true
    
    roll = rand() * 100
    if roll < event.success
        # Success (30%): treasure
        treasure_type = rand(1:2)
        if treasure_type == 1
            gold_amount = rand(25:50)
            this.user.gold += gold_amount
            OverworldFeedbackModule.gold!(gold_amount)
            push!(this.pages, EventStringsModule.format_string(:dark_door_treasure_dollars, gold_amount=gold_amount))
        else
            this.user.attack += 2
            OverworldFeedbackModule.attack!(2)
            push!(this.pages, EventStringsModule.EVENT_STRINGS[:dark_door_treasure_attack])
        end
    else
        # Failure (70%): ambush - take damage
        damage = rand(8:15)
        apply_out_of_combat_damage!(this.user, damage)
        OverworldFeedbackModule.damage!(damage)
        push!(this.pages, EventStringsModule.format_string(:dark_door_ambush, damage=damage))
    end
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
