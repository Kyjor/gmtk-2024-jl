function _pick_eligible_treasure(user)
    if length(user.treasures) >= user.max_treasures
        return nothing
    end
    treasure_data = Globals.get_data_manager().treasure_data
    if treasure_data === nothing
        return nothing
    end
    candidates = isa(treasure_data, Dict) ? collect(values(treasure_data)) : treasure_data
    candidates = filter(Globals.item_available_in_game, candidates)
    owned_keys = isempty(user.treasures) ? Set{String}() : Set(t.key for t in user.treasures)
    eligible = filter(t -> !in(t.key, owned_keys), candidates)
    if isempty(eligible)
        return nothing
    end
    weights = [1.0 / max(t.rarity, 0.01) for t in eligible]
    total = sum(weights)
    roll = rand() * total
    acc = 0.0
    for (i, w) in enumerate(weights)
        acc += w
        if roll <= acc
            return eligible[i]
        end
    end
    return eligible[end]
end

function handle_accept(this, event::randomevent_cursedchest)
    this.eventResolved = true
    
    if rand() * 100 < event.success
        # Success: random loot
        loot_type = rand(1:3)
        if loot_type == 1
            gold_amount = rand(15:30)
            this.user.gold += gold_amount
            OverworldFeedbackModule.gold!(gold_amount)
            push!(this.pages, EventStringsModule.format_string(:cursed_chest_gold, gold_amount=gold_amount))
        elseif loot_type == 2
            this.user.attack += 1
            OverworldFeedbackModule.attack!(1)
            push!(this.pages, EventStringsModule.EVENT_STRINGS[:cursed_chest_attack])
        else
            chosen_treasure = _pick_eligible_treasure(this.user)
            if chosen_treasure !== nothing
                push!(this.user.treasures, chosen_treasure)
                OverworldFeedbackModule.treasure!(chosen_treasure)
                push!(this.pages, EventStringsModule.format_string(:cursed_chest_treasure, treasure_name=chosen_treasure.name))
            else
                # No eligible treasure (player owns all available, or at max) — fall back to gold so the loot branch never feels empty
                gold_amount = rand(15:30)
                this.user.gold += gold_amount
                OverworldFeedbackModule.gold!(gold_amount)
                push!(this.pages, EventStringsModule.format_string(:cursed_chest_gold, gold_amount=gold_amount))
            end
        end
    else
        # Failure: curse - lose 5 max HP
        max_hp_loss = 5
        this.user.maxHealth = max(1, this.user.maxHealth - max_hp_loss)
        this.user.health = min(this.user.health, this.user.maxHealth)
        ensure_out_of_combat_survival!(this.user)
        OverworldFeedbackModule.max_hp!(-max_hp_loss)
        push!(this.pages, EventStringsModule.format_string(:cursed_chest_curse, max_hp_loss=max_hp_loss))
    end
    
    this.pageIndex = length(this.pages)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
end
