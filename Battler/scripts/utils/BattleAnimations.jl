# Data-driven piece match animations.
#
# Every piece maps to one or more AnimWaves built from shared archetypes:
#   :strike  - arcing slash into the target, full hit juice
#   :guard   - lobbed onto the player, shield pulse
#   :status  - fast bolt, colored affliction flash (no hit-stop; it's not a blow)
#   :restore - soft lob onto the player, heal glow
#   :self_hit- dark bolt back at the player (damage juice comes from take_damage)
#   :buff    - lob onto the player, bright flash
#   :gold    - lob onto the player, gold glint
# Dual-effect pieces (e.g. Spiked Shield) simply compose multiple waves.

const GRID_CENTER = Math.Vector2f(4.0, 4.0)

struct AnimWave
    target::Symbol              # :enemy, :player, :all_enemies
    motion::Symbol              # :arc, :bolt, :lob
    impact::Symbol              # :strike, :guard, :status, :restore, :self_hit, :buff, :gold
    tint::NTuple{4, Int}        # projectile sprite tint
    impact_color::NTuple{4, Int}
end

const ANIM_WHITE = (255, 255, 255, 255)

const PIECE_ANIMATIONS = Dict{String, Vector{AnimWave}}(
    PIECE_SWORD => [AnimWave(:enemy, :arc, :strike, ANIM_WHITE, (255, 210, 180, 255))],
    PIECE_CRIMSONBLADE => [AnimWave(:enemy, :arc, :strike, (255, 140, 140, 255), (220, 80, 200, 255))],
    PIECE_VAMPIRESWORD => [
        AnimWave(:enemy, :arc, :strike, (255, 170, 170, 255), (255, 80, 120, 255)),
        AnimWave(:player, :lob, :restore, (255, 170, 190, 255), (150, 255, 170, 255)),
    ],
    PIECE_SHIELD => [AnimWave(:player, :lob, :guard, ANIM_WHITE, (150, 200, 255, 255))],
    PIECE_REFLECTIVESHIELD => [AnimWave(:player, :lob, :guard, (225, 240, 255, 255), (210, 235, 255, 255))],
    PIECE_SPIKEDSHIELD => [
        AnimWave(:player, :lob, :guard, ANIM_WHITE, (150, 200, 255, 255)),
        AnimWave(:enemy, :arc, :strike, ANIM_WHITE, (255, 210, 180, 255)),
    ],
    PIECE_POTION => [AnimWave(:player, :lob, :restore, ANIM_WHITE, (150, 255, 170, 255))],
    PIECE_BURN => [AnimWave(:enemy, :bolt, :status, (255, 190, 130, 255), (255, 150, 50, 255))],
    PIECE_FREEZE => [AnimWave(:enemy, :bolt, :status, (185, 230, 255, 255), (100, 200, 255, 255))],
    PIECE_POISON => [AnimWave(:enemy, :bolt, :status, (195, 255, 175, 255), (120, 220, 80, 255))],
    PIECE_LIGHTNING => [AnimWave(:enemy, :bolt, :strike, (255, 255, 185, 255), (255, 240, 120, 255))],
    PIECE_GRENADE => [AnimWave(:all_enemies, :lob, :strike, ANIM_WHITE, (255, 180, 100, 255))],
    PIECE_DIE => [AnimWave(:enemy, :arc, :strike, ANIM_WHITE, (255, 230, 180, 255))],
    PIECE_SKULL => [AnimWave(:player, :bolt, :self_hit, (210, 190, 225, 255), (120, 60, 140, 255))],
    PIECE_DODGE => [AnimWave(:player, :lob, :buff, ANIM_WHITE, ANIM_WHITE)],
    PIECE_LUCKY => [AnimWave(:player, :lob, :buff, (255, 235, 160, 255), (255, 215, 0, 255))],
    PIECE_YELLOWGEM => [AnimWave(:player, :lob, :gold, ANIM_WHITE, (255, 215, 0, 255))],
    PIECE_REDGEM => [AnimWave(:player, :lob, :gold, ANIM_WHITE, (255, 215, 0, 255))],
    PIECE_BLUEGEM => [AnimWave(:player, :lob, :gold, ANIM_WHITE, (255, 215, 0, 255))],
    PIECE_GREENGEM => [AnimWave(:player, :lob, :gold, ANIM_WHITE, (255, 215, 0, 255))],
    PIECE_WAND => [AnimWave(:enemy, :arc, :strike, (220, 160, 255, 255), (200, 120, 255, 255))],
)

const PIECE_IMPACT_SFX = Dict{String, Vector{String}}(
    PIECE_GRENADE => ["damageexplosive1", "damageexplosive2"],
)

const PIECE_MATCH_SFX = Dict{String, String}(
    PIECE_SWORD => "piecesword",
    PIECE_CRIMSONBLADE => "piecesword",
    PIECE_VAMPIRESWORD => "piecevampiresword",
    PIECE_SHIELD => "pieceshield",
    PIECE_SPIKEDSHIELD => "pieceshield",
    PIECE_REFLECTIVESHIELD => "piecereflectiveshield",
    PIECE_POTION => "drink",
    PIECE_BURN => "piecefire",
    PIECE_FREEZE => "pieceice",
    PIECE_POISON => "piecepoison",
    PIECE_SKULL => "pieceskull",
    PIECE_DODGE => "piecedodge",
    PIECE_LUCKY => "pieceluck",
    PIECE_WAND => "pieceluck",
    PIECE_BLUEGEM => "piecebluegem",
    PIECE_GREENGEM => "piecegreengem",
    PIECE_REDGEM => "pieceredgem",
    PIECE_YELLOWGEM => "pieceyellowgem",
)

function piece_sprite_name(piece_key::String)::String
    return JulGame.UserGlobals["Module"].get_asset_path("piece", lowercase(replace(piece_key, "PIECE_" => "")))
end

# Per-motion flight parameters; i is the projectile index within the wave.
function wave_motion_params(motion::Symbol, i::Int)
    if motion == :arc
        easings = [ease_out_back, ease_out_expo, ease_out_circ, ease_out_quart]
        return (
            duration = 0.4 + i * 0.05,
            arc = 0.5 + i * 0.2,
            stagger = 0.08,
            start_scale = 0.7 + i * 0.1,
            target_scale = 1.2 + i * 0.05,
            easing = easings[((i - 1) % length(easings)) + 1],
        )
    elseif motion == :bolt
        return (
            duration = 0.26 + i * 0.03,
            arc = 0.15,
            stagger = 0.05,
            start_scale = 0.8,
            target_scale = 1.05,
            easing = ease_out_quad,
        )
    else # :lob
        return (
            duration = 0.55 + i * 0.05,
            arc = 0.9,
            stagger = 0.1,
            start_scale = 1.0,
            target_scale = 1.35,
            easing = ease_out_cubic,
        )
    end
end

mutable struct IntentAnimation
    entity::Any
    start_pos::Any
    target_pos::Any
    mid_pos::Any
    duration::Float64
    elapsed::Float64
    delay::Float64
    impact::Symbol
    impact_color::NTuple{4, Int}
    start_scale::Float64
    target_scale::Float64
    easing_function::Function
    target_entity::Any
    impact_triggered::Bool
    sfx::String
end

function play_sfx(name::String)
    isempty(name) && return
    globals = JulGame.UserGlobals["Module"]
    globals.AudioManagerModule.play_audio_oneshot(
        globals.get_audio_manager(),
        globals.get_asset_path("sfx", name),
        false, 1.0, 0, 1,
    )
end

function play_piece_match_sfx(piece_key::String)
    play_sfx(get(PIECE_MATCH_SFX, piece_key, ""))
end

function play_impact_sfx_once!(this::BattleManager, anim::IntentAnimation)
    isempty(anim.sfx) && return
    name = anim.sfx
    play_sfx(name)
    for a in this.activeAnimations
        if a.sfx == name
            a.sfx = ""
        end
    end
end

"""Average world position of the matched pieces, so the fly-out starts on the match."""
function match_fly_origin(entities, piece_key)::Union{Nothing, Math.Vector2f}
    sx = 0.0
    sy = 0.0
    n = 0
    entities === nothing && return nothing
    for e in entities
        e === nothing && continue
        try
            string(e.name) == string(piece_key) || continue
            sx += Float64(e.transform.position.x)
            sy += Float64(e.transform.position.y)
            n += 1
        catch
        end
    end
    n == 0 && return nothing
    return Math.Vector2f(sx / n, sy / n)
end

function trigger_intent_animation(intent::String, actionCount::Int, origin=nothing)
    @debug "trigger_intent_animation called with intent: $(intent) and actionCount: $(actionCount)"
    global BattleManagerInstance
    this = BattleManagerInstance

    play_piece_match_sfx(intent)

    waves = get(PIECE_ANIMATIONS, intent, nothing)
    if waves === nothing
        apply_single_intent(this, intent, actionCount)
        return
    end

    push!(this.pendingIntents, (intent, actionCount))

    created = 0
    for wave in waves
        created += create_wave_animations(this, intent, wave, actionCount, origin)
    end

    if created == 0
        # No valid targets (e.g. everything already dead): apply immediately so
        # the intent isn't stuck in pendingIntents with no coroutine to flush it.
        apply_single_intent(this, intent, actionCount)
        filter!(x -> x != (intent, actionCount), this.pendingIntents)
        return
    end

    start_animation_coroutine(this)
end

function wave_targets(this::BattleManager, wave::AnimWave)
    if wave.target == :player
        player_entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")
        return player_entity === nothing ? Any[] : Any[player_entity]
    elseif wave.target == :enemy
        enemy_entity = BattleJuiceModule.selected_enemy_entity(this)
        return enemy_entity === nothing ? Any[] : Any[enemy_entity]
    else # :all_enemies
        return Any[e for e in this.enemies if e.scripts[1].health > 0]
    end
end

function spawn_wave_projectile(sprite_name::String, tint::NTuple{4, Int}, index::Int)
    projectile = JulGame.EntityModule.Entity("PieceProjectile_$(index)_$(rand(1000:9999))")
    try
        projectile.sprite = JulGame.SpriteModule.InternalSprite(
            projectile,
            sprite_name,
            Math.Vector4(0, 0, 0, 0),
            false,
            tint,
            false;
            pixelsPerUnit = 150,
            layer = 10,
        )
    catch e
        @error "Error creating projectile sprite $(sprite_name): $(e)"
        projectile.sprite = JulGame.SpriteModule.InternalSprite(
            projectile,
            JulGame.UserGlobals["Module"].get_asset_path("piece", "error"),
            Math.Vector4(0, 0, 0, 0),
            false,
            tint,
            false;
            pixelsPerUnit = 150,
            layer = 10,
        )
    end
    return JulGame.create_entity(projectile)
end

function create_wave_animations(this::BattleManager, piece_key::String, wave::AnimWave, count::Int, origin=nothing)::Int
    sprite_name = piece_sprite_name(piece_key)
    names = get(PIECE_IMPACT_SFX, piece_key, String[])
    sfx = isempty(names) ? "" : rand(names)
    created = 0
    launch = origin === nothing ? GRID_CENTER : origin

    for target in wave_targets(this, wave)
        target_pos = Math.Vector2f(target.transform.position.x, target.transform.position.y)

        for i in 1:count
            params = wave_motion_params(wave.motion, i)

            start_x = launch.x + (i - 1) * 0.15
            start_y = launch.y + (i - 1) * 0.08
            start_pos = Math.Vector2f(start_x, start_y)
            mid_pos = Math.Vector2f(
                (start_pos.x + target_pos.x) / 2,
                (start_pos.y + target_pos.y) / 2 + params.arc,
            )

            projectile = spawn_wave_projectile(sprite_name, wave.tint, i)
            projectile.transform.position = Math.Vector3f(start_x, start_y, 0.0)

            push!(
                this.activeAnimations,
                IntentAnimation(
                    projectile,
                    start_pos,
                    target_pos,
                    mid_pos,
                    params.duration,
                    0.0,
                    (i - 1) * params.stagger,
                    wave.impact,
                    wave.impact_color,
                    params.start_scale,
                    params.target_scale,
                    params.easing,
                    target,
                    false,
                    sfx,
                ),
            )
            created += 1
        end
    end

    return created
end

function bezier_point(start_pos, mid_pos, target_pos, t)
    inv_t = 1.0 - t
    return Math.Vector2f(
        inv_t * inv_t * start_pos.x + 2 * inv_t * t * mid_pos.x + t * t * target_pos.x,
        inv_t * inv_t * start_pos.y + 2 * inv_t * t * mid_pos.y + t * t * target_pos.y,
    )
end

function bezier_tangent(start_pos, mid_pos, target_pos, t)
    dx = 2 * (1 - t) * (mid_pos.x - start_pos.x) + 2 * t * (target_pos.x - mid_pos.x)
    dy = 2 * (1 - t) * (mid_pos.y - start_pos.y) + 2 * t * (target_pos.y - mid_pos.y)
    return atan(dy, dx)
end

function apply_wave_impact!(anim::IntentAnimation)
    target = anim.target_entity
    target === nothing && return

    if anim.impact == :strike
        BattleJuiceModule.sword_impact!(target, GRID_CENTER)
        BattleJuiceModule.clear_brace!(target)
    elseif anim.impact == :guard
        BattleJuiceModule.shield_impact!(target)
    elseif anim.impact == :status
        BattleJuiceModule.status_flash!(target, anim.impact_color)
        BattleJuiceModule.shake!(target; intensity = 0.06, duration = 0.15)
    elseif anim.impact == :restore
        BattleJuiceModule.flash!(target; color = anim.impact_color, duration = 0.3)
        BattleJuiceModule.scale_pulse!(target; intensity = 1.06, duration = 0.2)
    elseif anim.impact == :self_hit
        BattleJuiceModule.flash!(target; color = anim.impact_color, duration = 0.25)
    elseif anim.impact == :buff
        BattleJuiceModule.flash!(target; color = anim.impact_color, duration = 0.3)
        BattleJuiceModule.scale_pulse!(target; intensity = 1.06, duration = 0.2)
    elseif anim.impact == :gold
        BattleJuiceModule.flash!(target; color = anim.impact_color, duration = 0.25)
    end
end

function start_animation_coroutine(this::BattleManager)
    if this.animationCoroutine !== nothing && !istaskdone(this.animationCoroutine.task)
        return
    end
    this.animationCoroutine = JulGame.CoroutineModule.start_coroutine(animation_coroutine, this)
end

function animation_coroutine(this::BattleManager)
    @debug "Animation coroutine started"
    globals = JulGame.UserGlobals["Module"]
    speed_multiplier = globals.get_data_manager().game_speed_multiplier

    while !isempty(this.activeAnimations)
        deltaTime = JulGame.DELTA_TIME * speed_multiplier * BattleJuiceModule.time_scale()
        if deltaTime <= 0.0
            JulGame.CoroutineModule.wait_for_coroutine()
            continue
        end

        completed_animations = Int[]
        current_brace_targets = Any[]

        for (i, anim) in enumerate(this.activeAnimations)
            if anim.elapsed < anim.delay
                anim.elapsed += deltaTime
                continue
            end

            animation_elapsed = anim.elapsed - anim.delay
            progress = min(animation_elapsed / anim.duration, 1.0)
            eased_progress = anim.easing_function(progress)
            current_pos = bezier_point(anim.start_pos, anim.mid_pos, anim.target_pos, eased_progress)

            scale_progress = ease_out_quart(progress)
            current_scale = anim.start_scale + (anim.target_scale - anim.start_scale) * scale_progress

            travel_angle = bezier_tangent(anim.start_pos, anim.mid_pos, anim.target_pos, eased_progress)
            rotation = travel_angle / (2π)
            if anim.impact == :strike && progress > 0.8
                # Fast slash arc in the last 20% so the strike reads as a swing.
                slash_t = (progress - 0.8) / 0.2
                rotation += 0.33 * ease_out_back(slash_t)
            end

            anim.entity.transform.position = Math.Vector3f(current_pos.x, current_pos.y, 0.0)
            anim.entity.transform.scale = Math.Vector3f(current_scale, current_scale, 1.0)
            anim.entity.transform.rotation = Math.Vector3f(0.0, 0.0, rotation)

            if anim.impact == :strike && progress > 0.15 && progress < 1.0 && anim.target_entity !== nothing
                push!(current_brace_targets, (anim.target_entity, progress))
            end

            if anim.impact == :strike && progress > 0.8
                impact_scale = 1.0 + (1.0 - progress) * 0.5
                anim.entity.transform.scale = Math.Vector3f(
                    current_scale * impact_scale,
                    current_scale * impact_scale,
                    1.0,
                )
            end

            anim.elapsed += deltaTime

            if progress >= 1.0
                if !anim.impact_triggered
                    anim.impact_triggered = true
                    apply_wave_impact!(anim)
                    play_impact_sfx_once!(this, anim)
                end
                push!(completed_animations, i)
                JulGame.destroy_entity(MAIN, anim.entity)
            end
        end

        seen = Set{UInt}()
        for (target, progress) in current_brace_targets
            key = BattleJuiceModule.entity_id(target)
            if key in seen
                continue
            end
            push!(seen, key)
            BattleJuiceModule.set_brace!(target, GRID_CENTER; intensity=min(1.0, 0.35 + progress * 0.65))
        end

        for i in reverse(completed_animations)
            deleteat!(this.activeAnimations, i)
        end

        JulGame.CoroutineModule.wait_for_coroutine()
    end

    for enemy in this.enemies
        BattleJuiceModule.clear_brace!(enemy)
    end

    if !isempty(this.pendingIntents)
        Scripts.BattleManagerModule.apply_pending_intents(this)
    end

    this.animationCoroutine = nothing
    @debug "Animation coroutine ended"
end
