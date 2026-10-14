module EnemySpriteAnimationsModule
    using JulGame
    using Random

    export EnemyAnimationSpec, ANIMATABLE_ENEMIES, attach_enemy_animation!

    struct EnemyAnimationSpec
        framePaths::Vector{String}
        minimumFPS::Int
        maximumFPS::Int
    end

    const ANIMATABLE_ENEMIES = Dict{String, EnemyAnimationSpec}(
        "ENEMY_CROW" => EnemyAnimationSpec(
            ["enemy-crow", "enemy-crow1"],
            1,
            1,
        ),
        "ENEMY_SKELEBAT" => EnemyAnimationSpec(
            ["enemy-skelebat", "enemy-skelebat1"],
            1,
            1,
        ),
    )

    function attach_enemy_animation!(
        entity,
        enemyKey::String;
        rng::AbstractRNG = Random.default_rng(),
    )::Bool
        spec = get(ANIMATABLE_ENEMIES, enemyKey, nothing)
        if spec === nothing || entity.sprite === nothing || entity.sprite == C_NULL
            return false
        end
        if entity.animator !== nothing && entity.animator != C_NULL
            @warn "Enemy already has an animator" enemyKey
            return false
        end

        fps = rand(rng, spec.minimumFPS:spec.maximumFPS)
        animation = JulGame.AnimationModule.Animation(
            JulGame.Math.Vector4[],
            fps,
            [JulGame.UserGlobals["Module"].get_asset_path(p) for p in spec.framePaths],
        )
        animator = JulGame.add_animator(
            entity,
            JulGame.AnimatorModule.Animator([animation]),
        )

        startFrame = rand(rng, eachindex(spec.framePaths))
        animator.lastFrame = startFrame
        entity.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path(spec.framePaths[startFrame])
        return true
    end
end
