# Advanced AI for Knight enemy (King's Court boss only — always attack).
using JulGame
using ..EnemyPatternsModule

function knight_ai(enemy, context::EnemyPatternsModule.AIContext)
    if !context.kingsCourtMode
        return nothing
    end
    attack_amount = Scripts.RunScalingModule.scale_attack(
        Int(enemy.enemyData.average_attack),
        string(enemy.enemyKey);
        pattern = string(enemy.enemyData.pattern),
    )
    @debug("Knight AI (King's Court): Attack for $(attack_amount)")
    return ("Attack", attack_amount)
end

function knight_skill(enemy, gridController)
    @debug("Knight using skill - Powerful Charge!")
    DisplayTextModule.display_text(
        "knight_skill_text",
        "Knight charges!";
        fontSize=28,
        anchor=:center,
        lifetime=1500,
        color=(255, 100, 100, 255)
    )
end

EnemyPatternsModule.register_enemy_ai("ENEMY_KNIGHT", knight_ai)
EnemyPatternsModule.register_enemy_skill("ENEMY_KNIGHT", knight_skill)
