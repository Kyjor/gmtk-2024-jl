# Advanced AI for Birdman enemy
using ..EnemyPatternsModule
using ..Scripts

"""Minimum turns between Birdman specials (use on turn N ⇒ next earliest N+3)."""
const BIRDMAN_SKILL_PERIOD = 5

# enemy.id => remaining turns before special is allowed again
const BIRDMAN_SKILL_COOLDOWN = Dict{Any, Int}()

function _birdman_tick_skill_cooldown!(enemy)::Bool
    # Unseen enemies start mid-cooldown so the first special lands on their BIRDMAN_SKILL_PERIOD-th intent.
    cd = get(BIRDMAN_SKILL_COOLDOWN, enemy.id, BIRDMAN_SKILL_PERIOD - 1)
    if cd > 0
        BIRDMAN_SKILL_COOLDOWN[enemy.id] = cd - 1
        return false
    end
    return true
end

function _birdman_start_skill_cooldown!(enemy)
    # After using this turn, block the next (period - 1) decisions.
    BIRDMAN_SKILL_COOLDOWN[enemy.id] = max(0, BIRDMAN_SKILL_PERIOD - 1)
end

"""
Birdman advanced AI logic.
Makes intelligent decisions based on battle state.

Returns: (intent::String, value::Int) or nothing for standard pattern
"""
function birdman_ai(enemy, context::EnemyPatternsModule.AIContext)
    can_skill = _birdman_tick_skill_cooldown!(enemy)
    health_percent = enemy.health / enemy.maxHealth

    # Below 15% health: prioritize healing
    if health_percent < 0.10
        base = round(Int, enemy.enemyData.average_heal * enemy.enemyData.average_health)
        heal_amount = Scripts.RunScalingModule.scale_heal(
            base,
            string(enemy.enemyKey);
            pattern = string(enemy.enemyData.pattern),
        )
        @debug("Birdman AI: Low health ($(health_percent*100)%), choosing to heal")
        return ("Heal", heal_amount)
    end

    # Special at most once every BIRDMAN_SKILL_PERIOD turns
    if can_skill
        @debug("Birdman AI: skill off cooldown, scrambling the board")
        _birdman_start_skill_cooldown!(enemy)
        return ("Skill", 0)
    end

    return nothing
end

"""
Birdman skill execution - scrambles the game board.
"""
function birdman_skill(enemy, gridController)
    @debug("Birdman using skill to scramble the board, then curse the most common pieces")
    _birdman_start_skill_cooldown!(enemy)
    Scripts.GridControllerModule.start_birdman_special!(gridController)
end

EnemyPatternsModule.register_enemy_ai("ENEMY_BIRDMAN", birdman_ai)
EnemyPatternsModule.register_enemy_skill("ENEMY_BIRDMAN", birdman_skill)
