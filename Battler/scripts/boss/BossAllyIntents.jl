# Boss-only intents: Priest heals the King or shields other living allies (not the Priest).
module BossAllyIntentsModule
using JulGame

include("../utils/EnemiesConstants.jl")

function apply_heal_king!(bm, heal_amount::Int)
    heal_amount <= 0 && return
    for enemy_entity in bm.enemies
        es = enemy_entity.scripts[1]
        if es.enemyKey == ENEMY_KING && es.health > 0
            es.health = clamp(es.health + heal_amount, 0, es.maxHealth)
            @debug "HealKing: King healed to $(es.health)"
            return
        end
    end
end

function apply_ally_shield_except_actor!(bm, actor_script, shield_amount::Int)
    shield_amount <= 0 && return
    for enemy_entity in bm.enemies
        es = enemy_entity.scripts[1]
        if es === actor_script || es.health <= 0
            continue
        end
        es.shield = clamp(es.shield + shield_amount, 0, 999)
        @debug "AllyShield: $(es.enemyKey) shield=$(es.shield)"
    end
end

export apply_heal_king!, apply_ally_shield_except_actor!

end # module
