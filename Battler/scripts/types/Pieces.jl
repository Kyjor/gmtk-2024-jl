module PiecesModule
include("../generated-types/PiecesStructs.jl")

function apply_intent(piece_key::String, battle_manager, actionValue::Int)
    #@debug "Applying intent: $(piece_key)"

    ref_action_count = Ref(actionValue)
    #@debug "checking if $(piece_key) is a general effect"
    shouldApplyGeneralEffects = _calculate_action_value(ALL_PIECES[piece_key], battle_manager, ref_action_count)
    #@debug "shouldApplyGeneralEffects: $(shouldApplyGeneralEffects)"
    if shouldApplyGeneralEffects === nothing
        #@debug "Applying general effects for $(piece_key)"
        _apply_general_effects(ALL_PIECES[piece_key], battle_manager, ref_action_count)
    end

    apply_special_effects(ALL_PIECES[piece_key], battle_manager, ref_action_count)
    #@debug "Applied intent: $(piece_key)"
end

#region General Effects
function _apply_general_effects(piece, battle_manager, actionValue)
    @debug "Applying general effects error dispatch"
end

function _apply_general_effects(piece::Piece, battle_manager, actionValue::Ref{Int})
    @debug "Applying general effects for $(piece.key)"
    if battle_manager.user.luck > 0 && rand(1:100) < battle_manager.user.luck
        actionValue[] *= 2
        @debug "doubled action value because player is lucky"
    end

    # Resolved once: single-target effects below must never land on a corpse.
    status_target = live_enemy_target(battle_manager)

    if piece.hit_percentage < 100
        # return if the piece misses
        if rand(1:100) > piece.hit_percentage
            @debug "Piece $(piece.key) missed"
            # Emit miss event
            for enemy in battle_manager.enemies
                if enemy.scripts[1] == status_target
                    Globals.ObserverModule.notify(:attack_missed, Dict(:target => enemy))
                    break
                end
            end
            return
        end
    end

    if piece.defense > 0
        shield_amount = piece_shield_amount(piece, battle_manager.user, actionValue[])
        battle_manager.user.shield = clamp(battle_manager.user.shield + shield_amount, 0, battle_manager.user.maxShield)

        # Emit shield gained event
        Globals.ObserverModule.notify(:shield_gained, Dict(:battle_manager => battle_manager, :amount => shield_amount))
    end
    if piece.burn > 0
        burn_amount = piece.burn * actionValue[]
        if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_DRAGONSCALE)
            # Gain 1 shield when burning enemy
            battle_manager.user.shield = clamp(battle_manager.user.shield + 1, 0, battle_manager.user.maxShield)
            @debug "Dragon Scale effect applied, gaining 1 shield"
        end
        if status_target !== nothing
            status_target.burn += burn_amount

            # Emit burn status event
            for enemy in battle_manager.enemies
                if enemy.scripts[1] == status_target
                    Globals.ObserverModule.notify(:status_applied, Dict(:target => enemy, :status_type => :burn, :duration => burn_amount))
                    break
                end
            end
        end
    end
    if piece.freeze > 0
        freeze_amount = piece_freeze_amount(piece, actionValue[])
        if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_FROSTSHARD)
            # Heal 1 HP when freezing enemy
            battle_manager.user.health = clamp(battle_manager.user.health + 1, 0, battle_manager.user.maxHealth)
            @debug "Frost Shard effect applied, doubling freeze and healing 1 HP"

            # Emit healing event
            Globals.ObserverModule.notify(:healing_received, Dict(:battle_manager => battle_manager, :amount => 1))
        end
        if status_target !== nothing
            status_target.freeze = clamp(status_target.freeze + freeze_amount, 0, 5)

            # Emit freeze status event
            for enemy in battle_manager.enemies
                if enemy.scripts[1] == status_target
                    Globals.ObserverModule.notify(:status_applied, Dict(:target => enemy, :status_type => :freeze, :duration => freeze_amount))
                    break
                end
            end
        end
    end
    if piece.vulnerable > 0
        vulnerable_amount = piece.vulnerable * actionValue[]
        # AOE (Mace) writes a stack on every living enemy. Single-target stays on the selected one.
        status_targets = if is_aoe(piece)
            [e.scripts[1] for e in battle_manager.enemies if e.scripts[1].health > 0]
        elseif status_target !== nothing
            [status_target]
        else
            []
        end
        for enemy_script in status_targets
            enemy_script.vulnerable = clamp(enemy_script.vulnerable + vulnerable_amount, 0, 5)
        end
        for enemy in battle_manager.enemies
            enemy.scripts[1] in status_targets || continue
            Globals.ObserverModule.notify(:status_applied, Dict(:target => enemy, :status_type => :vulnerable, :duration => vulnerable_amount))
        end
    end
    if piece.poison > 0
        poison_amount = _calculate_step_amount(piece, piece.poison, battle_manager, actionValue[])
        if status_target !== nothing
            status_target.poison = clamp(status_target.poison + poison_amount, 0, 5)

            # Emit poison status event
            for enemy in battle_manager.enemies
                if enemy.scripts[1] == status_target
                    Globals.ObserverModule.notify(:status_applied, Dict(:target => enemy, :status_type => :poison, :duration => poison_amount))
                    break
                end
            end
        end
    end
    if piece.heal > 0
        # Check if healing is blocked (Deal With The Devil)
        heal_blocked = get(Globals.get_data_manager().persistent_state_manager.playerData, "heal_blocked", false)
        if heal_blocked
            @debug "Healing is blocked by devil's bargain!"
            Globals.ObserverModule.notify(:special_text, Dict(
                :battle_manager => battle_manager,
                :text => "HEALING BLOCKED!",
                :color => (255, 80, 80, 255)
            ))
        else
            heal_amount = piece_heal_amount(piece, actionValue[])
            # Alchemist Belt: 25% chance for random enemy status when using the potion piece (not during UI/tooltip reads).
            if piece.key == PIECE_POTION &&
               Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_ALCHEMISTBELT) &&
               !isempty(battle_manager.enemies) &&
               rand() < 0.25
                enemy_entity = rand(battle_manager.enemies)
                if length(enemy_entity.scripts) >= 1
                    apply_potion_vial_effect(enemy_entity.scripts[1])
                    @debug "Alchemist Belt: random status applied via potion heal"
                end
            end
            battle_manager.user.health = clamp(battle_manager.user.health + heal_amount, 0, battle_manager.user.maxHealth)

            # Emit healing event
            Globals.ObserverModule.notify(:healing_received, Dict(:battle_manager => battle_manager, :amount => heal_amount))
        end
    end
    if piece.attack_self > 0
        self_damage = piece.attack_self * actionValue[]
        try
            root = parentmodule(parentmodule(PiecesModule))
            root.Scripts.BattleManagerModule.take_damage(battle_manager, battle_manager.user, self_damage)
        catch e
            @debug "BattleManager take_damage unavailable for recoil, using raw HP: $(e)"
            battle_manager.user.health = clamp(battle_manager.user.health - self_damage, 0, battle_manager.user.maxHealth)
        end

        # Emit self-damage event with recoil flag
        Globals.ObserverModule.notify(:damage_dealt, Dict(
            :battle_manager => battle_manager,
            :target_type => :player,
            :damage => self_damage,
            :is_critical => false,
            :damage_type => :physical,
            :is_recoil => true
        ))
    end
    if piece.attack > 0
        is_critical = false
        alive_enemies = count(e -> e.scripts[1].health > 0, battle_manager.enemies)
        first_strike = warrior_first_strike(battle_manager.user)
        attack_value = piece_attack_damage(piece, battle_manager.user, actionValue[], alive_enemies)
        @debug "Applying attack of $(attack_value)"

        # Warrior Helmet first attack bonus
        if first_strike
            battle_manager.user.first_attack_bonus = false
            is_critical = true
            @debug "Warrior Helmet effect applied, first attack deals +2 damage"

            # Emit first strike event
            Globals.ObserverModule.notify(:special_text, Dict(
                :battle_manager => battle_manager,
                :text => "FIRST STRIKE!",
                :color => (255, 215, 0, 255)
            ))
        end

        if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_VAMPIREBLOOD)
            # Check if healing is blocked (Deal With The Devil)
            heal_blocked = get(Globals.get_data_manager().persistent_state_manager.playerData, "heal_blocked", false)
            if !heal_blocked
                vampire_heal = floor(Int64, attack_value * 0.5)
                battle_manager.user.health = clamp(battle_manager.user.health + vampire_heal, 0, battle_manager.user.maxHealth)
                @debug "Vampire blood effect applied, healing for $(vampire_heal)"

                # Emit healing event for lifesteal
                Globals.ObserverModule.notify(:healing_received, Dict(:battle_manager => battle_manager, :amount => vampire_heal))
            else
                @debug "Vampire blood lifesteal blocked by devil's bargain!"
            end
        end
        # Track damage dealt in analytics
        try
            Globals.AnalyticsModule.track_action(:damage_dealt, attack_value)
        catch e
            @debug "Could not track damage dealt: $e"
        end

        if is_aoe(piece)
            original_selected = battle_manager.selectedEnemy
            for enemy_entity in battle_manager.enemies
                enemy_script = enemy_entity.scripts[1]
                if enemy_script.health > 0
                    battle_manager.selectedEnemy = enemy_script
                    deal_damage(battle_manager, attack_value, is_critical)
                end
            end
            battle_manager.selectedEnemy = original_selected
        else
            deal_damage(battle_manager, attack_value, is_critical)
        end
    end
end

#endregion General Effecs

function apply_modifications(piece::piece_sword, property::Symbol)
    #@debug "Applying modifications for $(piece.key) and property $(property)"
    value = parse_stat_value(getfield(piece, property))
    data_manager = Globals.get_data_manager()
    if property == :attack
        if data_manager.current_battle_manager !== nothing
            if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_DUMBELLS)
                value += data_manager.current_battle_manager.gameManager.round
                @debug "Dumbells effect applied, increasing attack by $(value)"
            end
        end
    end

    return value
end

function apply_modifications(piece::piece_shield, property::Symbol)
    #@debug "Applying modifications for $(piece.key) and property $(property)"
    value = parse_stat_value(getfield(piece, property))
    data_manager = Globals.get_data_manager()
    if property == :defense
        if data_manager.current_battle_manager !== nothing
            if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_KNEEPADS)
                value += data_manager.current_battle_manager.gameManager.round
                @debug "Kneepads effect applied, increasing defense by $(value)"
            end
        end
    end

    return value
end

function apply_modifications(piece::piece_potion, property::Symbol)
    #@debug "Applying modifications for $(piece.key) and property $(property)"
    value = parse_stat_value(getfield(piece, property))
    data_manager = Globals.get_data_manager()
    if data_manager === nothing
        @warn "Data manager is nothing"
        return value
    end
    if data_manager.current_battle_manager === nothing
        #        @warn "Current battle manager is nothing"
        return value
    end
    if property == :heal
        if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_CUTEBANDAGE)
            value += data_manager.current_battle_manager.gameManager.round
            @debug "Cute bandage effect applied, increasing heal by $(value)"
        end
        # Alchemist Belt vial is applied only when a potion heal resolves in combat (_apply_general_effects),
        # not here — this path runs on every UI read of :heal / {Heal} and must stay side-effect free.
    end

    return value
end

function apply_special_effects(piece, battle_manager, actionValue)
    @debug "Applying special effects error dispatch"
end

function apply_special_effects(piece::piece_wand, battle_manager, actionValue::Ref{Int})
    chance = min(25 * actionValue[], 75)
    rand(1:100) > chance && return
    target = live_enemy_target(battle_manager)
    target === nothing && return

    effect = apply_potion_vial_effect(target)
    for enemy in battle_manager.enemies
        if enemy.scripts[1] == target
            Globals.ObserverModule.notify(:status_applied, Dict(
                :target => enemy,
                :status_type => Symbol(effect),
                :duration => 1,
            ))
            break
        end
    end
end

function apply_special_effects(piece::piece_lucky, battle_manager, actionValue::Ref{Int})
    @debug "applying special effects for lucky piece"
    # base_chance = piece.hit_percentage
    # actions = max(actionValue[] - 3, 0)
    # for x = 0:actions
    #     base_chance += 9
    # end
    # gate = rand() * 100
    # @debug "Gate: $gate , base_chance: $base_chance"
    # if gate < base_chance
    #     battle_manager.user.luck = 10
    #     @debug "User is lucky!"
    # end
    luck_to_add = 5
    actions = max(actionValue[] - 3, 0)
    for x = 0:actions
     luck_to_add += 1
    end
    battle_manager.user.luck += luck_to_add
end

function _calculate_action_value(piece::piece_sword, battle_manager, actionValue::Ref{Int})
    #@debug "Applying sword intent of $(piece.attack * actionValue[])"
    #actionValue[] = piece.attack * actionValue[]
end

function _calculate_action_value(piece::piece_wand, battle_manager, actionValue::Ref{Int})
end

function _calculate_action_value(piece::piece_grenade, battle_manager, actionValue::Ref{Int})
end

function _calculate_action_value(piece::piece_die, battle_manager, actionValue::Ref{Int})
    # Face is rolled during match presentation and passed in as actionValue.
end

function _calculate_action_value(piece::piece_potion, battle_manager, actionValue::Ref{Int})
end

function _calculate_action_value(piece::piece_shield, battle_manager, actionValue::Ref{Int})
end

"""Block from the spreadsheet Defense stat times the action count."""
function shield_block_amount(defense, action_count, user)::Int
    return defense + max(0, action_count - 1) + max(0, user.defense - 1)
end

# function _calculate_action_value(piece::piece_spikedshield, battle_manager, actionValue::Ref{Int})
# end

function _calculate_action_value(piece::piece_reflectiveshield, battle_manager, actionValue::Ref{Int})
    reflect_chance = actionValue[]
    battle_manager.user.reflect_chance = min(reflect_chance, 100)

    # Emit reflect ready event
    Globals.ObserverModule.notify(:ability_activated, Dict(:battle_manager => battle_manager, :ability_type => :reflect_ready))
end

const EMPTY_LOCKET_MAX_DODGE_MOVES_PER_TURN = 1

function empty_locket_dodge_turn(battle_manager)
    Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_EMPTYLOCKET) &&
    battle_manager.firstMatchTypeThisTurn === PIECE_DODGE
end

const DODGE_PER_MATCH = 5
const MAX_DODGE_CHANCE = 100
const SHADOW_CLOAK_DODGE_BONUS = 5

"""
Dodge chance rolled against an enemy attack: Boot stacks plus the flat Shadow Cloak bonus.
Checks ownership directly — `has_treasure` flashes the treasure icon and UI calls this every frame.
"""
function player_dodge_chance(user)::Int
    has_cloak = any(t -> t.key == Globals.TreasuresModule.TREASURE_SHADOWCLOAK, user.treasures)
    bonus = has_cloak ? SHADOW_CLOAK_DODGE_BONUS : 0
    return min(Int(user.dodge_chance) + bonus, MAX_DODGE_CHANCE)
end

const CURSED_MIRROR_REFLECT_BONUS = 3

"""Reflect chance rolled against an enemy attack: Mirror stacks plus the flat Cursed Mirror bonus."""
function player_reflect_chance(user)::Int
    has_mirror = any(t -> t.key == Globals.TreasuresModule.TREASURE_CURSEDMIRROR, user.treasures)
    bonus = has_mirror ? CURSED_MIRROR_REFLECT_BONUS : 0
    return min(Int(user.reflect_chance) + bonus, 100)
end

function _calculate_action_value(piece::piece_dodge, battle_manager, actionValue::Ref{Int})
    dodge_chance = DODGE_PER_MATCH * actionValue[]
    battle_manager.user.dodge_chance = min(battle_manager.user.dodge_chance + dodge_chance, MAX_DODGE_CHANCE)
    # Emit dodge ready event
    Globals.ObserverModule.notify(:ability_activated, Dict(:battle_manager => battle_manager, :ability_type => :dodge_ready))
    # Skip general effects — dodge ignores hit_percentage (accuracy).
    return false
end

function _calculate_action_value(piece::piece_burn, battle_manager, actionValue::Ref{Int})
end

function _calculate_action_value(piece::piece_freeze, battle_manager, actionValue::Ref{Int})
end

function _calculate_action_value(piece::piece_vampiresword, battle_manager, actionValue::Ref{Int})
    # Apply vampire effect to the enemy
    vampire_damage = effective_attack_damage_after_debuffs(
        battle_manager.user,
        attack_damage_with_user_stat(battle_manager.user, piece.attack, actionValue[])
    )
    vampire_heal = floor(Int64, vampire_damage * 0.5)

    deal_damage(battle_manager, vampire_damage, false)
    battle_manager.user.health = clamp(battle_manager.user.health + vampire_heal, 0, battle_manager.user.maxHealth)

    # Emit healing event for lifesteal
    Globals.ObserverModule.notify(:healing_received, Dict(:battle_manager => battle_manager, :amount => vampire_heal, :is_lifesteal => true))

    return false
end

function _calculate_action_value(piece::piece_crimsonblade, battle_manager, actionValue::Ref{Int})
end

function _calculate_step_amount(piece, piece_value, battle_manager, action_count::Int, modifier::Int = 0)
    return piece_value + max(0, action_count - 1) + max(0, modifier - 1)
end

# Lightning piece - shock (and attack, when it has one) hits the selected enemy unless the piece is AOE
function _calculate_action_value(piece, battle_manager, actionValue::Ref{Int})
    # Handle lightning piece specially
    if piece.key == "PIECE_LIGHTNING"
        shock_amount =  _calculate_step_amount(piece, piece.shock, battle_manager, actionValue[])

        if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_THUNDERGEM)
            shock_amount += 1
            @debug "Thunder Gem effect applied, increasing shock duration by 1"
        end

        # Attack is optional. A 0 attack stat must not emit a 0-damage chip.
        attack_value = 0
        if piece.attack > 0
            attack_value = effective_attack_damage_after_debuffs(
                battle_manager.user,
                attack_damage_with_user_stat(battle_manager.user, piece.attack, actionValue[]),
            )
        end

        targets = if is_aoe(piece)
            battle_manager.enemies
        else
            selected = live_enemy_target(battle_manager)
            filter(e -> e.scripts[1] == selected, battle_manager.enemies)
        end
        for enemy_entity in targets
            enemy_script = enemy_entity.scripts[1]
            if enemy_script.health > 0
                if attack_value > 0
                    @debug "Lightning attacking enemy for $(attack_value) damage"

                    try
                        Globals.AnalyticsModule.track_action(:damage_dealt, attack_value)
                    catch e
                        @debug "Could not track damage dealt: $e"
                    end

                    original_selected = battle_manager.selectedEnemy
                    battle_manager.selectedEnemy = enemy_script
                    deal_damage(battle_manager, attack_value, false)
                    battle_manager.selectedEnemy = original_selected
                end

                enemy_script.shock = clamp(enemy_script.shock + shock_amount, 0, 5)

                Globals.ObserverModule.notify(:status_applied, Dict(:target => enemy_entity, :status_type => :shock, :duration => shock_amount))
            end
        end
        
        # Return false to prevent general attack effects from applying
        return false
    end
    
    # Fallback for other pieces — must return nothing so general effects still run
    @warn "No intent applied for piece of type $(typeof(piece))"
    return nothing
end

function _calculate_action_value(piece::piece_poison, battle_manager, actionValue::Ref{Int})
end

const GEM_GOLD = Dict(
    PIECE_YELLOWGEM => 10,
    PIECE_BLUEGEM => 3,
    PIECE_REDGEM => 5,
    PIECE_GREENGEM => 1,
)
const ROGUE_GLOVES_GEM_BONUS = 3

"""Gold from a gem match: base × action count (match 3/4/5 → 1/2/3), plus a flat Rogue Gloves bonus on Yellow."""
function gem_gold(piece_key::String, action_count::Int)::Int
    gold = get(GEM_GOLD, piece_key, 0) * action_count
    if piece_key == PIECE_YELLOWGEM && Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_ROGUEGLOVES)
        gold += ROGUE_GLOVES_GEM_BONUS
    end
    return gold
end

function _calculate_action_value(piece::piece_yellowgem, battle_manager, actionValue::Ref{Int})
    gold_amount = gem_gold(piece.key, actionValue[])
    battle_manager.user.gold += gold_amount

    # Emit gold collection event
    Globals.ObserverModule.notify(:gold_collected, Dict(:battle_manager => battle_manager, :amount => gold_amount))
end

function _calculate_action_value(piece::piece_bluegem, battle_manager, actionValue::Ref{Int})
    gold_amount = gem_gold(piece.key, actionValue[])
    # if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_ROGUEGLOVES)
    #     gold_amount += 3
    #     @debug "Rogue Gloves effect applied, gaining extra gold from gem"
    # end
    battle_manager.user.gold += gold_amount
end

function _calculate_action_value(piece::piece_redgem, battle_manager, actionValue::Ref{Int})
    gold_amount = gem_gold(piece.key, actionValue[])
    # if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_ROGUEGLOVES)
    #     gold_amount += 3
    #     @debug "Rogue Gloves effect applied, gaining extra gold from gem"
    # end
    battle_manager.user.gold += gold_amount
end

function _calculate_action_value(piece::piece_greengem, battle_manager, actionValue::Ref{Int})
    gold_amount = gem_gold(piece.key, actionValue[])
    # if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_ROGUEGLOVES)
    #     gold_amount += 3
    #     @debug "Rogue Gloves effect applied, gaining extra gold from gem"
    # end
    battle_manager.user.gold += gold_amount
end

"""Apply the player's attack stat after the piece/action multiplier."""
function attack_damage_with_user_stat(user, piece_attack::Int, action_count::Int)::Int
    return piece_attack * action_count + max(0, user.attack - 1)
end

#region General effect amounts — side-effect free, shared by `_apply_general_effects` and the swap preview
is_aoe(piece)::Bool = piece.type !== nothing && occursin("AOE", piece.type)

piece_shield_amount(piece, user, action_count::Int)::Int =
    piece.defense > 0 ? shield_block_amount(piece.defense, action_count, user) + max(0, Int(user.defense) - 1) : 0

function piece_freeze_amount(piece, action_count::Int)::Int
    amount = piece.freeze * action_count
    return Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_FROSTSHARD) ? amount * 2 : amount
end

function piece_heal_amount(piece, action_count::Int)::Int
    amount = piece.heal * action_count
    return Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_BLESSEDAMULET) ? floor(Int, amount * 1.2) : amount
end

warrior_first_strike(user)::Bool =
    Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_WARRIORHELMET) && user.first_attack_bonus

"""Damage each target takes from a general attack, before its vulnerable stacks."""
function piece_attack_damage(piece, user, action_count::Int, alive_enemies::Int)::Int
    attack_value = piece.attack * action_count
    if is_aoe(piece) && Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_BOMBCHAMBER) && alive_enemies == 1
        attack_value *= 3
    end
    attack_value += max(0, user.attack - 1)
    warrior_first_strike(user) && (attack_value += 2)
    return effective_attack_damage_after_debuffs(user, attack_value)
end
#endregion

"""
Enemy that should receive a single-target effect, or `nothing` when all are dead.

`selectedEnemy` can still point at a corpse: `refresh_selected_enemy_indicator!` only
runs once `Enemy.update` notices the death, a frame after the kill. Every intent left in
the same batch (e.g. a sword queued behind an AOE grenade) would otherwise resolve onto
the dead enemy and appear to do nothing.
"""
function live_enemy_target(battle_manager)
    selected = battle_manager.selectedEnemy
    if selected !== nothing && selected.health > 0
        return selected
    end
    for enemy_entity in battle_manager.enemies
        enemy_script = enemy_entity.scripts[1]
        if enemy_script.health > 0
            return enemy_script
        end
    end
    return nothing
end

"""Reduce outgoing attack damage from enemy debuffs: Weaken (0.75× per stack, max 5), then Poison (-1 per stack)."""
function effective_attack_damage_after_debuffs(user, attack_value::Int)::Int
    w = clamp(user.weaken, 0, 5)
    damage = w <= 0 ? attack_value : floor(Int, attack_value * (0.75 ^ w))
    return max(0, damage - max(user.poison, 0))
end

"""Matches Combatant.take_damage: each vulnerable stack adds 1 flat damage."""
function damage_after_vulnerable(damage::Int, vulnerable_stacks::Int)::Int
    vulnerable_stacks <= 0 && return damage
    return damage + vulnerable_stacks
end

function deal_damage(battle_manager, damage::Int, is_critical::Bool=false)
    target = live_enemy_target(battle_manager)
    target === nothing && return

    # Find enemy entity for feedback
    enemy_entity = nothing
    for enemy in battle_manager.enemies
        if enemy.scripts[1] == target
            enemy_entity = enemy
            break
        end
    end

    # Mirror Combatant.take_damage() math so feedback reflects actual HP loss.
    effective_damage = damage_after_vulnerable(damage, Int(target.vulnerable))
    target_shield = hasproperty(target, :shield) ? max(0, target.shield) : 0
    health_damage = max(0, effective_damage - target_shield)

    if health_damage > 0
        if effective_damage > 20
            play_piece_damage_sfx("damageheavy")
        else
            play_piece_damage_sfx(rand(("damagenormal1", "damagenormal2", "damagenormal3", "damagenormal4", "damagenormal5", "damagenormal6")))
        end
    end

    # Emit damage dealt event
    if enemy_entity !== nothing
        Globals.ObserverModule.notify(
            :damage_dealt,
            Dict(:target => enemy_entity, :damage => health_damage, :is_critical => is_critical, :damage_type => :physical),
        )
    end

    take_damage(target, damage)
end

function take_damage(target, damage)
    Globals.UserModule.take_damage(target, damage)
    #todo play animation based on type of damage
end

function play_piece_damage_sfx(name::String)
    try
        Globals.AudioManagerModule.play_audio_oneshot(
            Globals.get_audio_manager(),
            Globals.get_asset_path("sfx", name),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "piece damage sfx: $e"
    end
end

# Called when Alchemist Belt procs on a potion heal in combat (`enemy` is the Enemy script, not the Entity).
# Returns the status name so callers (wand) can notify.
function apply_potion_vial_effect(enemy)
    effect = rand(["burn", "freeze", "vulnerable", "poison", "shock"])

    if effect == "burn"
        enemy.burn += 1
        @debug "Alchemist Vial effect applied, increasing burn duration by 1"
    elseif effect == "freeze"
        enemy.freeze = clamp(enemy.freeze + 1, 0, 5)
        @debug "Alchemist Vial effect applied, increasing freeze duration by 1"
    elseif effect == "vulnerable"
        enemy.vulnerable = clamp(enemy.vulnerable + 1, 0, 5)
        @debug "Alchemist Vial effect applied, increasing vulnerable duration by 1"
    elseif effect == "poison"
        enemy.poison = clamp(enemy.poison + 1, 0, 5)
        @debug "Alchemist Vial effect applied, increasing poison duration by 1"
    elseif effect == "shock"
        enemy.shock = clamp(enemy.shock + 1, 0, 5)
        @debug "Alchemist Vial effect applied, increasing shock duration by 1"
    end
    return effect
end
end # module
