# Crowman Summon: revive defeated crow slots (same entities, no extra spawn).
# Included into EnemyTurnAnimatorModule.

"""Revive up to `count` dead ENEMY_CROW allies. No-op when none are down. Returns how many revived."""
function apply_crowman_summon!(bm, count::Int = 1)::Int
    count <= 0 && return 0
    revived = 0
    for enemy_entity in bm.enemies
        revived >= count && break
        es = enemy_entity.scripts[1]
        es.enemyKey == "ENEMY_CROW" || continue
        es.health > 0 && continue

        es.health = es.maxHealth
        es.shield = 0
        es.hasReportedDefeat = false
        try
            es.deathStarted = false
        catch
        end
        enemy_entity.isActive = true
        if isdefined(es, :parent) && es.parent !== nothing
            es.parent.isActive = true
            if es.parent.sprite !== nothing && es.enemyBodyAliveColor !== nothing
                es.parent.sprite.color = es.enemyBodyAliveColor
            end
        end
        try
            es.healthHeartBackground.isActive = true
            es.healthHeart.isActive = true
            es.intent.isActive = true
        catch e
            @debug "CrowmanSummon UI reactivate: $(e)"
        end
        try
            Scripts.EnemyModule.set_next_enemy_intent(es)
        catch e
            @debug "CrowmanSummon set_next_enemy_intent: $(e)"
        end
        revived += 1
        @debug "CrowmanSummon: revived crow ($(revived)/$(count))"
    end
    if revived > 0
        DisplayTextModule.display_text(
            "crowman_summon_text_$(rand(1000:9999))",
            revived == 1 ? "A crow returns!" : "$(revived) crows return!";
            fontSize=32,
            anchor=:center,
            lifetime=2000,
            color=(200, 200, 220, 255)
        )
    end
    return revived
end
