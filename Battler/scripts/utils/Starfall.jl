"""
StarfallModule

Magician passive: when a combo ends, the combo stars fly into random living enemies
instead of off screen, each dealing STAR_DAMAGE on arrival.
"""
module StarfallModule
    using JulGame

    export dismiss_stars!

    const CHARACTER_KEY = "CHARACTER_MAGICIAN"
    const STAR_DAMAGE = 1
    const SHOOT_SFX_VARIANTS = 5
    const IMPACT_SFX_STEPS = 9
    const IMPACT_SFX_MIN_GAP = 0.07  # seconds; stars land 0.04s apart, so skip some to avoid a wall of noise
    const IMPACT_VOLUME = 0.7

    mutable struct ImpactSfxState
        step::Int
        last_time::Float64
    end
    const IMPACT_SFX = ImpactSfxState(0, 0.0)

    _scripts() = parentmodule(@__MODULE__)

    function _play_sfx(name::String, volume::Float64 = 1.0)
        try
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(),
                globals.get_asset_path("sfx", name),
                false, volume, 0, 1,
            )
        catch e
            @debug "Starfall sfx: $e"
        end
    end

    """Rising-pitch impact ladder (combostardamage1..9), throttled across the volley."""
    function _play_impact_sfx()
        now = time()
        now - IMPACT_SFX.last_time < IMPACT_SFX_MIN_GAP && return
        IMPACT_SFX.last_time = now
        IMPACT_SFX.step = min(IMPACT_SFX.step + 1, IMPACT_SFX_STEPS)
        _play_sfx("combostardamage$(IMPACT_SFX.step)", IMPACT_VOLUME)
    end

    function _battle_manager()
        try
            grid = _scripts().ComboStarsModule.resolve_grid(nothing)
            return grid === nothing ? nothing : grid.battleManager
        catch
            return nothing
        end
    end

    function _active(bm)::Bool
        bm === nothing && return false
        try
            return bm.user.selectedCharacter == CHARACTER_KEY &&
                   bm.currentState != bm.battleStates[:battleEnd]
        catch
            return false
        end
    end

    _alive(enemy)::Bool = enemy.scripts[1].health > 0

    function _screen_center(enemy)
        try
            spr = enemy.sprite
            pos = spr.lastRenderedScreenPosition
            size = spr.lastRenderedScreenSize
            if pos !== nothing && size !== nothing && Float64(size.x) > 0
                return (Float64(pos.x) + Float64(size.x) / 2.0, Float64(pos.y) + Float64(size.y) / 2.0)
            end
        catch
        end
        p = enemy.transform.position
        return _scripts().ComboStarsModule.world_to_screen(Float64(p.x), Float64(p.y))
    end

    function _strike!(bm, enemy)
        _alive(enemy) || return
        bm.currentState == bm.battleStates[:battleEnd] && return
        try
            JulGame.UserGlobals["Module"].AnalyticsModule.track_action(:damage_dealt, STAR_DAMAGE)
        catch e
            @debug "Could not track starfall damage: $e"
        end
        _play_impact_sfx()
        icon = ""
        try
            icon = _scripts().ComboStarsModule.star_chip_art()
        catch
        end
        _scripts().BattleManagerModule.take_damage(
            bm, enemy.scripts[1], STAR_DAMAGE;
            damage_icon = icon,
            damage_source = "combo_star",
        )
    end

    """Pick a living enemy, preferring ones whose health + shield earlier stars have not already covered."""
    function _aim(bm, claimed::Dict{Any, Int})
        alive = [e for e in bm.enemies if _alive(e)]
        isempty(alive) && return nothing
        remaining(e) = e.scripts[1].health + e.scripts[1].shield - get(claimed, e, 0)
        uncovered = filter(e -> remaining(e) > 0, alive)
        enemy = rand(isempty(uncovered) ? alive : uncovered)
        claimed[enemy] = get(claimed, enemy, 0) + STAR_DAMAGE
        x, y = _screen_center(enemy)
        return (x, y, () -> _strike!(bm, enemy))
    end

    """Combo-end dismissal: Magician stars strike enemies, everyone else's fly off screen."""
    function dismiss_stars!()
        stars = _scripts().ComboStarsModule
        bm = _battle_manager()
        _active(bm) || return stars.dismiss!()
        if any(s -> s.phase != :leaving, stars.STATE.stars) && any(_alive, bm.enemies)
            IMPACT_SFX.step = 0
            IMPACT_SFX.last_time = 0.0
            _play_sfx("combostarshoot$(rand(1:SHOOT_SFX_VARIANTS))")
        end
        claimed = Dict{Any, Int}()
        stars.dismiss!(; target_for = (i, star) -> _aim(bm, claimed))
    end
end
