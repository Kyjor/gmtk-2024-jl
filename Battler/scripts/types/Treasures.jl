module TreasuresModule
include("../generated-types/TreasuresStructs.jl")


# Apply effects based on treasure types
function apply_turn_end_effect(treasure::String, game_manager, value::Int)
    if treasure == TREASURE_DUMBELLS || treasure == TREASURE_KNEEPADS || treasure == TREASURE_CUTEBANDAGE
        return value + (game_manager.round - 1)
    end
    return value
end

# Called at the start of combat
function apply_combat_start_effect(treasure::String, entity)
    if treasure == TREASURE_BLESSEDAMULET
        # Start with 10 shield points
        entity.shield = clamp(entity.shield + 10, 0, entity.maxShield)
        return true
    elseif treasure == TREASURE_WARRIORHELMET
        # Set first attack flag
        entity.first_attack_bonus = true
        return true
    end
    return false
end

# Called when player makes an attack
function apply_attack_effect(treasure::String, entity, damage::Int, is_critical::Bool=false)
    bonus_damage = 0
    
    if treasure == TREASURE_WARRIORHELMET && is_critical
        # Critical hit bonus damage
        bonus_damage += floor(Int, damage * 0.5) # +50% damage on crits
    end
    
    if treasure == TREASURE_WARRIORHELMET && isdefined(entity, :first_attack_bonus) && entity.first_attack_bonus
        # First attack bonus
        bonus_damage *= 2
        entity.first_attack_bonus = false
    end
    
    if treasure == TREASURE_VAMPIREFANG && rand() < 0.15
        # 15% chance to heal on regular attacks
        entity.health = clamp(entity.health + 1, 0, entity.maxHealth)
    end
    
    return damage + bonus_damage
end

# Called when player defends with shield
function apply_defense_effect(treasure::String, entity, defense::Int)
    if treasure == TREASURE_ANCIENTSHIELD
        # No direct defense bonus from Ancient Shield here
        return defense
    end
    
    return defense
end

# Called when player uses a healing effect
function apply_heal_effect(treasure::String, entity, heal_amount::Int)
    if treasure == TREASURE_BLESSEDAMULET
        # 20% more effective healing
        return floor(Int, heal_amount * 1.2)
    end
    
    return heal_amount
end

# Called when player applies burn effect
function apply_burn_effect(treasure::String, entity, enemy, burn_amount::Int, burn_damage::Int)
    if treasure == TREASURE_ELEMENTALFOCUS
        # Burn lasts longer and deals more damage
        return burn_amount + 2, burn_damage + 1
    elseif treasure == TREASURE_DRAGONSCALE
        # Burn is twice as strong and grants shield
        entity.shield = clamp(entity.shield + 1, 0, entity.maxShield)
        return burn_amount, burn_damage * 2
    end
    
    return burn_amount, burn_damage
end

# Called when player applies freeze effect
function apply_freeze_effect(treasure::String, entity, enemy, freeze_amount::Int, freeze_damage::Int)
    if treasure == TREASURE_ELEMENTALFOCUS
        # Freeze lasts longer and deals more damage
        return freeze_amount + 2, freeze_damage + 1
    elseif treasure == TREASURE_FROSTSHARD
        # Freeze is twice as strong and grants healing
        entity.health = clamp(entity.health + 1, 0, entity.maxHealth)
        return freeze_amount, freeze_damage * 2
    end
    
    return freeze_amount, freeze_damage
end


# Called after successful dodge
function apply_dodge_success(treasure::String, entity, battle_manager)
    if treasure == TREASURE_SHADOWCLOAK
        # Grant an extra move after first successful dodge
        battle_manager.moveCount += 1
        entity.dodge_success_move_bonus = false
        return true
    end
    
    return false
end

# Called when gaining gold
function apply_gold_effect(treasure::String, entity, gold_amount::Int)
    if treasure == TREASURE_ROGUEGLOVES
        # Extra gold from Gold Coin pieces
        return gold_amount + 5
    end
    
    return gold_amount
end

# Called after battle
function apply_post_battle_effect(treasure::String, entity)
    if treasure == TREASURE_ROGUEGLOVES && rand() < 0.1
        # 10% chance to find extra gold after battle
        entity.gold += 10
        return "Found 10 extra gold with Rogue Gloves!"
    end
    
    return ""
end

# Called when using thunder
function apply_thunder_effect(treasure::String, entity, hit_chance::Int, vulnerable_duration::Int)
    if treasure == TREASURE_THUNDERGEM
        # Increased hit chance and vulnerable duration
        return hit_chance + 20, vulnerable_duration + 2
    end
    
    return hit_chance, vulnerable_duration
end

# Called when using vampire sword
function apply_vampire_effect(treasure::String, entity, damage::Int, heal_amount::Int)
    if treasure == TREASURE_VAMPIREFANG
        # Increased damage and healing from vampire sword
        return damage + 1, heal_amount + 2
    end
    
    return damage, heal_amount
end

# Called when checking for critical hits
function apply_critical_hit_effect(treasure::String, entity, crit_occurred::Bool)
    if treasure == TREASURE_LUCKYCHARM && crit_occurred && rand() < 0.1
        # 10% chance for critical hit to trigger twice
        return true
    end
    
    return false
end

# Called when player would die
function apply_death_prevention(treasure::String, entity)
    if treasure == TREASURE_ANCIENTSHIELD &&
       entity.health <= 0 &&
       hasproperty(entity, :ancient_shield_used) &&
       !entity.ancient_shield_used
        # Survive with 10 HP and gain 10 shield.
        # Per-floor semantics are enforced by resetting `ancient_shield_used`
        # when the current floor changes in PersistentStateManager.
        entity.health = min(entity.maxHealth, 10)
        entity.shield = clamp(entity.shield + 10, 0, entity.maxShield)
        entity.ancient_shield_used = true
        return true
    end
    
    return false
end

end # module
