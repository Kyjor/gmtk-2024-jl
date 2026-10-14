# Advanced AI for Priest enemy (King's Court boss only).
using ..EnemyPatternsModule
using ..Scripts

function _priest_scaled_heal(enemy, target_max_health::Int)::Int
    base = round(Int, enemy.enemyData.average_heal * target_max_health)
    return Scripts.RunScalingModule.scale_heal(
        base,
        string(enemy.enemyKey);
        pattern = string(enemy.enemyData.pattern),
    )
end

function _priest_scaled_shield(enemy)::Int
    return Scripts.RunScalingModule.scale_defense(
        Int(enemy.enemyData.average_defense),
        string(enemy.enemyKey);
        pattern = string(enemy.enemyData.pattern),
    )
end

"""
Priest alternates: shield all allies except self, or heal the King.
Returns: (intent::String, value::Int) or nothing for standard pattern
"""
function priest_ai(enemy, context::EnemyPatternsModule.AIContext)
    if !context.kingsCourtMode
        return nothing
    end

    king = nothing
    knight = nothing
    for ally in context.allEnemies
        if ally.enemyKey == "ENEMY_KING"
            king = ally
        elseif ally.enemyKey == "ENEMY_KNIGHT"
            knight = ally
        end
    end

    if king !== nothing && king.health > 0
        king_hp = king.health / king.maxHealth
        if king_hp < 0.5
            heal_amount = _priest_scaled_heal(enemy, king.maxHealth)
            @debug("Priest AI: Healing King ($(round(Int, king_hp * 100))% HP)")
            return ("HealKing", heal_amount)
        end
    end

    allies_need_shield = false
    if king !== nothing && king.health > 0 && king.shield < 3
        allies_need_shield = true
    end
    if knight !== nothing && knight.health > 0 && knight.shield < 3
        allies_need_shield = true
    end

    shield_amount = _priest_scaled_shield(enemy)
    if allies_need_shield
        @debug("Priest AI: Allies need shield")
        return ("AllyShield", shield_amount)
    end

    if context.turnNumber % 2 == 0
        @debug("Priest AI: Turn $(context.turnNumber), AllyShield")
        return ("AllyShield", shield_amount)
    else
        if king !== nothing && king.health > 0
            heal_amount = _priest_scaled_heal(enemy, king.maxHealth)
            @debug("Priest AI: Turn $(context.turnNumber), HealKing")
            return ("HealKing", heal_amount)
        end
    end

    return nothing
end

function priest_skill(enemy, gridController)
    @debug("Priest using skill - Divine Blessing!")
    battleManager = enemy.battleManager
    for ally_entity in battleManager.enemies
        ally = ally_entity.scripts[1]
        if ally.health > 0 && ally.id != enemy.id
            heal_amount = round(Int, ally.maxHealth * 0.2)
            ally.health = clamp(ally.health + heal_amount, 0, ally.maxHealth)
            shield_amount = 5
            ally.shield = clamp(ally.shield + shield_amount, 0, 999)
            @debug("Priest healed $(ally.enemyKey) for $(heal_amount) and granted $(shield_amount) shield")
        end
    end
    DisplayTextModule.display_text(
        "priest_skill_text",
        "Divine Blessing!";
        fontSize=32,
        anchor=:center,
        lifetime=2000,
        color=(255, 215, 0, 255)
    )
end

EnemyPatternsModule.register_enemy_ai("ENEMY_PRIEST", priest_ai)
EnemyPatternsModule.register_enemy_skill("ENEMY_PRIEST", priest_skill)
