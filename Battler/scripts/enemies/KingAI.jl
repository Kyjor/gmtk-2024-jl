# Advanced AI for King enemy (King's Court boss only).
using ..EnemyPatternsModule
using ..Scripts

"""
King advanced AI logic.
The King summons minions endlessly (up to 2 at a time).
When a minion is missing, he uses the turn to re-summon.
While all minions are up, he will attack or block.

Returns: (intent::String, value::Int) or nothing for standard pattern
"""
function king_ai(enemy, context::EnemyPatternsModule.AIContext)
    if !context.kingsCourtMode
        return nothing
    end

    living_knight = false
    living_priest = false
    king_health_percent = enemy.health / enemy.maxHealth

    for ally in context.allEnemies
        if ally.id == enemy.id || ally.health <= 0
            continue
        end
        if ally.enemyKey == "ENEMY_KNIGHT"
            living_knight = true
        elseif ally.enemyKey == "ENEMY_PRIEST"
            living_priest = true
        end
    end

    if !living_knight || !living_priest
        delay = 0
        try
            delay = Int(context.battleManager.kingsCourtSummonDelay)
        catch
            delay = 0
        end
        if delay > 0
            context.battleManager.kingsCourtSummonDelay = delay - 1
            @debug("King AI: summon delayed ($(delay) remaining), using combat intent")
        else
            @debug("King AI: missing living minion (knight=$(living_knight), priest=$(living_priest)), summoning")
            return ("Skill", 0)
        end
    else
        try
            context.battleManager.kingsCourtSummonDelay = 1
        catch
        end
    end

    pat = string(enemy.enemyData.pattern)
    key = string(enemy.enemyKey)

    if context.player.shield > 10
        defend_amount = Scripts.RunScalingModule.scale_defense(
            Int(enemy.enemyData.average_defense), key; pattern = pat,
        )
        @debug("King AI: Player has high shield, defending")
        return ("Defend", defend_amount)
    end

    player_health_percent = context.player.health / context.player.maxHealth
    if player_health_percent < 0.3
        attack_amount = Scripts.RunScalingModule.scale_attack(
            Int(enemy.enemyData.average_attack), key; pattern = pat,
        )
        @debug("King AI: Player low health, attacking aggressively")
        return ("Attack", attack_amount + 2)
    end

    if king_health_percent < 0.4
        defend_amount = Scripts.RunScalingModule.scale_defense(
            Int(enemy.enemyData.average_defense), key; pattern = pat,
        )
        @debug("King AI: Low health, defending")
        return ("Defend", defend_amount)
    end

    attack_amount = Scripts.RunScalingModule.scale_attack(
        Int(enemy.enemyData.average_attack), key; pattern = pat,
    )
    @debug("King AI: All minions present, attacking")
    return ("Attack", attack_amount)
end

"""
King skill execution - summons a missing minion (revives Knight or Priest slot).
"""
function king_skill(enemy, gridController)
    battleManager = enemy.battleManager
    if battleManager === nothing || !battleManager.kingsCourtMode
        return
    end

    has_knight = false
    has_priest = false
    for ally in battleManager.enemies
        s = ally.scripts[1]
        if s.health > 0 && s.id != enemy.id
            if s.enemyKey == "ENEMY_KNIGHT"
                has_knight = true
            elseif s.enemyKey == "ENEMY_PRIEST"
                has_priest = true
            end
        end
    end

    minion_key = if !has_knight
        "ENEMY_KNIGHT"
    elseif !has_priest
        "ENEMY_PRIEST"
    else
        nothing
    end

    if minion_key !== nothing
        Scripts.BattleManagerModule.revive_kings_court_minion!(battleManager, enemy, minion_key)
        battleManager.kingsCourtSummonDelay = 1
    end
end

EnemyPatternsModule.register_enemy_ai("ENEMY_KING", king_ai)
EnemyPatternsModule.register_enemy_skill("ENEMY_KING", king_skill)
