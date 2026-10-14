# Rest site fire pit: offer money, health or a potion to the flame for a variable reward.
# The reward scales with what the offering is worth; sometimes the flame gives nothing back (unexplained).

const FIRE_DUD_CHANCE = 0.5
const FIRE_LUCK_RANGE = (0.6, 2.0)   # random multiplier on an offering's worth
const FIRE_GOLD_SHARE = 0.5          # share of current dollars offered
const FIRE_HEALTH_SHARE = 0.3        # share of current health offered
const FIRE_HP_WORTH = 6              # dollar worth of one offered health
# Relative chance of each reward among those currently available
const FIRE_TREASURE_CHANCE = 0.03
const FIRE_POTION_CHANCE = 0.22
const FIRE_MAX_HP_CHANCE = 0.2
const FIRE_GOLD_CHANCE = 0.3
const FIRE_HEAL_CHANCE = 0.25
# (chance, minimum rolled value) per reward
const FIRE_REWARDS = (
    treasure = (FIRE_TREASURE_CHANCE, 180),
    potion = (FIRE_POTION_CHANCE, 60),
    max_hp = (FIRE_MAX_HP_CHANCE, 60),
    gold = (FIRE_GOLD_CHANCE, 0),
    heal = (FIRE_HEAL_CHANCE, 0),
)
const FIRE_POTION_CHOICE_PREFIX = "fire_potion_"

"""
Offerings the player can currently make: :gold, :health, :potion.
"""
function fire_offer_kinds(user)::Vector{Symbol}
    kinds = Symbol[]
    user.gold >= 2 && push!(kinds, :gold)
    user.health >= 2 && push!(kinds, :health)
    isempty(user.potions) || push!(kinds, :potion)
    return kinds
end

"""
Choices: "fire_gold", "fire_health", "fire_potion_<slot>".
"""
function handle_choice(this, event::randomevent_restsite, choice::String)
    this.eventResolved && return
    text = offer_to_fire!(this.user, choice)
    text === nothing && return
    this.eventResolved = true
    push!(this.pages, text)
    this.pageIndex = length(this.pages)
    push!(this.viewedPages, this.pageIndex)
    Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "piecefire"), false, 1.0, 0, 1)
end

"""
Take the offering and grant the reward. Returns the event text, or nothing when the choice is not affordable.
"""
function offer_to_fire!(user, choice::String)::Union{Nothing, String}
    offer = _take_fire_offering!(user, choice)
    offer === nothing && return nothing
    kind, worth, text_key = offer
    return EventStringsModule.EVENT_STRINGS[text_key] * "\n\n" * _grant_fire_reward!(user, kind, worth)
end

function _take_fire_offering!(user, choice::String)
    if choice == "fire_gold" && user.gold >= 2
        amount = max(1, floor(Int, user.gold * FIRE_GOLD_SHARE))
        user.gold -= amount
        OverworldFeedbackModule.gold!(-amount)
        return (:gold, Float64(amount), :fire_offer_gold_text)
    elseif choice == "fire_health" && user.health >= 2
        amount = clamp(round(Int, user.health * FIRE_HEALTH_SHARE), 1, user.health - 1)
        apply_out_of_combat_damage!(user, amount)
        OverworldFeedbackModule.damage!(amount)
        return (:health, Float64(amount * FIRE_HP_WORTH), :fire_offer_health_text)
    elseif startswith(choice, FIRE_POTION_CHOICE_PREFIX)
        slot = tryparse(Int, choice[length(FIRE_POTION_CHOICE_PREFIX) + 1:end])
        (slot === nothing || !(1 <= slot <= length(user.potions))) && return nothing
        potion = popat!(user.potions, slot)
        # Rarer potions (lower spawn rarity) are worth up to twice their price
        rarity = clamp(Float64(something(potion.rarity, 1.0)), 0.0, 1.0)
        return (:potion, potion.average_price * (2.0 - rarity), :fire_offer_potion_text)
    end
    return nothing
end

function _grant_fire_reward!(user, offered::Symbol, worth::Float64)::String
    rand() < FIRE_DUD_CHANCE && return EventStringsModule.EVENT_STRINGS[:fire_reward_dud]
    lo, hi = FIRE_LUCK_RANGE
    value = worth * (lo + rand() * (hi - lo))
    kind = _fire_reward_kind(user, offered, value)
    if kind == :treasure
        treasure = TreasureChestModule.pick_reward(user)
        push!(user.treasures, treasure)
        OverworldFeedbackModule.treasure!(treasure)
        return EventStringsModule.format_string(:fire_reward_treasure, name = treasure.en_name)
    elseif kind == :potion
        potion = rand(_fire_potion_pool())
        add_potion!(user, potion.key)
        OverworldFeedbackModule.potion!(1; key = potion.key)
        return EventStringsModule.format_string(:fire_reward_potion, name = potion.en_name)
    elseif kind == :max_hp
        amount = max(1, round(Int, value / 40))
        user.maxHealth += amount
        user.health += amount
        OverworldFeedbackModule.max_hp!(amount)
        return EventStringsModule.format_string(:fire_reward_max_hp, amount = amount)
    elseif kind == :heal
        amount = min(user.maxHealth - user.health, max(1, round(Int, value / 4)))
        user.health += amount
        OverworldFeedbackModule.heal!(amount)
        return EventStringsModule.format_string(:fire_reward_heal, amount = amount)
    end
    amount = max(1, round(Int, value))
    user.gold += amount
    OverworldFeedbackModule.gold!(amount)
    return EventStringsModule.format_string(:fire_reward_gold, amount = amount)
end

"""
Weighted pick among rewards the rolled value reaches and the player can receive; falls back to max health.
"""
function _fire_reward_kind(user, offered::Symbol, value::Float64)::Symbol
    options = [(kind, chance) for (kind, (chance, min_value)) in pairs(FIRE_REWARDS)
               if value >= min_value && _fire_reward_available(user, offered, kind)]
    isempty(options) && return :max_hp
    roll = rand() * sum(last, options)
    for (kind, chance) in options
        roll -= chance
        roll <= 0 && return kind
    end
    return first(last(options))
end

# The flame never hands back the same thing it was given.
function _fire_reward_available(user, offered::Symbol, kind::Symbol)::Bool
    kind == :gold && return offered != :gold
    kind == :heal && return offered != :health && user.health < user.maxHealth
    kind == :potion && return length(user.potions) < user.max_potions && !isempty(_fire_potion_pool())
    kind == :treasure && return TreasureChestModule.pick_reward(user) !== nothing
    return true
end

_fire_potion_pool() = filter(Globals.item_available_in_game, collect(values(Globals.get_potion_data())))
