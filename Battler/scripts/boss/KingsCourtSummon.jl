# Included into BattleManagerModule — revives a defeated Knight or Priest slot (same entities, no fourth spawn).

"""Revive a downed Knight or Priest in King's Court. `minion_key` is ENEMY_KNIGHT or ENEMY_PRIEST."""
function revive_kings_court_minion!(battle_manager, king_script, minion_key::String)
    if !isdefined(battle_manager, :kingsCourtMode) || !battle_manager.kingsCourtMode
        return
    end
    for enemy_entity in battle_manager.enemies
        es = enemy_entity.scripts[1]
        if es.enemyKey != minion_key
            continue
        end
        if es.health > 0
            return
        end
        es.health = es.maxHealth
        es.shield = 0
        es.hasReportedDefeat = false
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
            @debug "KingsCourtSummon UI reactivate: $(e)"
        end
        try
            Scripts.EnemyModule.set_next_enemy_intent(es)
        catch e
            @debug "KingsCourtSummon set_next_enemy_intent: $(e)"
        end
        DisplayTextModule.display_text(
            "king_summon_text_$(rand(1000:9999))",
            "$(minion_key == ENEMY_KNIGHT ? "Knight" : "Priest") returns!";
            fontSize=32,
            anchor=:center,
            lifetime=2000,
            color=(255, 215, 0, 255)
        )
        @debug "KingsCourtSummon: revived $(minion_key)"
        return
    end
    @warn "KingsCourtSummon: no entity found for $(minion_key)"
end
