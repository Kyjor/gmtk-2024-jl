function handle_accept(this, event::randomevent_mousehole)
    this.eventResolved = true
    
    roll = rand() * 100
    if roll < event.success
        # Success (50%): find something good
        reward = rand(1:2)
        if reward == 1
            gold_amount = rand(30:50)
            this.user.gold += gold_amount
            OverworldFeedbackModule.gold!(gold_amount)
            push!(this.pages, EventStringsModule.format_string(:mouse_hole_gold, gold_amount=gold_amount))
        else
            heal_amount = rand(5:10)
            before = this.user.health
            this.user.health = min(this.user.health + heal_amount, this.user.maxHealth)
            OverworldFeedbackModule.heal!(this.user.health - before)
            push!(this.pages, EventStringsModule.format_string(:mouse_hole_heal, heal_amount=heal_amount))
        end
    elseif roll < event.success + event.failure
        # Failure (40%): get hurt
        damage = rand(5:10)
        apply_out_of_combat_damage!(this.user, damage)
        OverworldFeedbackModule.damage!(damage)
        push!(this.pages, EventStringsModule.format_string(:mouse_hole_damage, damage=damage))
    else
        # Special (10%): rare treasure
        this.user.maxHealth += 5
        this.user.health += 5
        OverworldFeedbackModule.max_hp!(5)
        OverworldFeedbackModule.heal!(5)
        push!(this.pages, EventStringsModule.EVENT_STRINGS[:mouse_hole_special])
    end
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
