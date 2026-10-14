function handle_accept(this, event::randomevent_strangemerchant)
    this.eventResolved = true
    
    cost = 5
    if this.user.gold < cost
        push!(this.pages, EventStringsModule.EVENT_STRINGS[:strange_merchant_no_gold])
        this.pageIndex = length(this.pages)
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
        return
    end
    
    this.user.gold -= cost
    OverworldFeedbackModule.gold!(-cost)
    
    roll = rand() * 100
    if roll < event.success
        # Success (60%): healing potion
        heal_amount = rand(10:20)
        before = this.user.health
        this.user.health = min(this.user.health + heal_amount, this.user.maxHealth)
        OverworldFeedbackModule.heal!(this.user.health - before)
        push!(this.pages, EventStringsModule.format_string(:strange_merchant_heal, heal_amount=heal_amount))
    elseif roll < event.success + event.failure
        # Failure (35%): poison
        damage = rand(5:10)
        apply_out_of_combat_damage!(this.user, damage)
        OverworldFeedbackModule.damage!(damage)
        push!(this.pages, EventStringsModule.format_string(:strange_merchant_poison, damage=damage))
    else
        # Special (5%): super rare effect
        this.user.attack += 2
        this.user.defense += 2
        OverworldFeedbackModule.attack!(2)
        OverworldFeedbackModule.defense!(2)
        push!(this.pages, EventStringsModule.EVENT_STRINGS[:strange_merchant_legendary])
    end
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
