function handle_choice(this, event::randomevent_threedoors, choice::String)
    if choice == "leave"
        Globals.RandomEventsModule.handle_decline(this, event)
        return
    end
    this.eventResolved && return

    door = tryparse(Int, choice)
    (door === nothing || door < 1 || door > 3) && return
    this.doorChosen = door
    this.eventResolved = true

    outcome = this.doorOutcomes[door]
    msg = if outcome == :treasure
        this.user.gold += 50
        OverworldFeedbackModule.gold!(50)
        EventStringsModule.format_string(:three_doors_treasure, gold_amount=50)
    elseif outcome == :pain
        apply_out_of_combat_damage!(this.user, 10)
        OverworldFeedbackModule.damage!(10)
        EventStringsModule.format_string(:three_doors_pain, damage=10)
    else
        EventStringsModule.EVENT_STRINGS[:three_doors_nothing]
    end

    push!(this.pages, msg)
    this.pageIndex = length(this.pages)
    push!(this.viewedPages, this.pageIndex)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
