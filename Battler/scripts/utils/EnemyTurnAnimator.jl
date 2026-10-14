# Enemy Turn Animator - Sequential animation system for enemy actions
# Provides visual feedback when enemies execute their intents

module EnemyTurnAnimatorModule
using JulGame
include("DisplayText.jl")
using .DisplayTextModule
using ...Scripts
using ..BattleJuiceModule
using ..ActionResultDisplayModule
include("../localization/battle_strings.jl")
include("../boss/BossAllyIntents.jl")
using .BossAllyIntentsModule
include("../enemies/CrowmanSummon.jl")
using .BattleStringsModule

# === CONFIGURATION ===
# Timing configuration (all in seconds)
mutable struct AnimationConfig
    wind_up_duration::Float64      # Enemy "charges up" animation
    projectile_duration::Float64   # Projectile travel time
    impact_duration::Float64       # Impact/shake on target
    result_display_duration::Float64  # Show damage numbers etc.
    between_enemies_delay::Float64 # Pause between enemy animations

    function AnimationConfig()
        this = new()
        this.wind_up_duration = 0.25
        this.projectile_duration = 0.3
        this.impact_duration = 0.35
        this.result_display_duration = 0.4
        this.between_enemies_delay = 0.3
        return this
    end
end

# Global config instance
const ANIM_CONFIG = AnimationConfig()

# Intent animation definitions
struct IntentAnimation
    wind_up_color::Tuple{Int,Int,Int,Int}
    wind_up_scale::Float64
    projectile_image::String
    projectile_color::Tuple{Int,Int,Int,Int}
    impact_color::Tuple{Int,Int,Int,Int}
    impact_shake_intensity::Float64
    particle_type::Symbol
    sound_effect::String
end

# Animation definitions for each intent type
const INTENT_ANIMATIONS = Dict{String,IntentAnimation}(
    "ATTACK" => IntentAnimation(
        (255, 100, 100, 255),  # Red wind-up
        1.15,                  # Scale up 15%
        "intent-spikey-sword",
        (255, 50, 50, 255),    # Red projectile
        (255, 0, 0, 255),      # Red impact
        0.15,                  # Shake intensity
        :impact,
        "damagenormal1"
    ),
    "DEFEND" => IntentAnimation(
        (100, 150, 255, 255),  # Blue wind-up
        1.1,
        "intent-shield",
        (100, 150, 255, 255),
        (100, 200, 255, 255),
        0.0,                   # No shake for defend
        :sparkles,
        "pieceshield"
    ),
    "HEAL" => IntentAnimation(
        (100, 255, 100, 255),  # Green wind-up
        1.1,
        "piece-potion",
        (100, 255, 100, 255),
        (150, 255, 150, 255),
        0.0,
        :healing,
        "healsmall"
    ),
    "BURN" => IntentAnimation(
        (255, 150, 50, 255),   # Orange wind-up
        1.12,
        "piece-sword",  # TODO: Fire sprite
        (255, 100, 0, 255),
        (255, 150, 50, 255),
        0.08,
        :fire,
        "piecefire"
    ),
    "FREEZE" => IntentAnimation(
        (100, 200, 255, 255),  # Cyan wind-up
        1.12,
        "piece-shield",  # TODO: Ice sprite
        (150, 220, 255, 255),
        (100, 200, 255, 255),
        0.08,
        :ice,
        "pieceice"
    ),
    "POISON" => IntentAnimation(
        (150, 50, 200, 255),   # Purple wind-up
        1.12,
        "status-poison",
        (100, 200, 50, 255),
        (150, 50, 200, 255),
        0.05,
        :sparkles,
        "unknown1"
    ),
    "SKILL" => IntentAnimation(
        (255, 200, 50, 255),   # Gold wind-up
        1.2,
        "piece-error",
        (255, 215, 0, 255),
        (255, 200, 100, 255),
        0.1,
        :sparkles,
        "thud1"
    ),
    "CURSE" => IntentAnimation(
        (120, 60, 160, 255),
        1.18,
        "piece-skull",
        (180, 100, 220, 255),
        (90, 40, 120, 255),
        0.06,
        :sparkles,
        "unknown1"
    ),
    "TEAMHEAL" => IntentAnimation(
        (100, 255, 100, 255),
        1.1,
        "piece-potion",
        (100, 255, 100, 255),
        (150, 255, 150, 255),
        0.0,
        :healing,
        "healsmall"
    ),
    "BASH" => IntentAnimation(
        (220, 80, 80, 255),
        1.2,
        "intent-spikey-sword",
        (200, 40, 40, 255),
        (180, 30, 30, 255),
        0.2,
        :impact,
        "damageheavy"
    ),
    "WEAKEN" => IntentAnimation(
        (120, 80, 160, 255),
        1.12,
        "intent-spikey-sword",
        (150, 100, 200, 255),
        (120, 70, 150, 255),
        0.06,
        :sparkles,
        "unknown1"
    ),
    "HEALKING" => IntentAnimation(
        (100, 255, 100, 255),
        1.1,
        "piece-potion",
        (100, 255, 100, 255),
        (150, 255, 150, 255),
        0.0,
        :healing,
        "healsmall"
    ),
    "ALLYSHIELD" => IntentAnimation(
        (100, 150, 255, 255),
        1.1,
        "intent-shield",
        (100, 150, 255, 255),
        (100, 200, 255, 255),
        0.0,
        :sparkles,
        "pieceshield"
    ),
    "SUMMON" => IntentAnimation(
        (180, 180, 200, 255),
        1.15,
        "enemy-crow",
        (180, 180, 200, 255),
        (200, 200, 220, 255),
        0.0,
        :sparkles,
        "thud1"
    )
)

# === STATE TRACKING ===
mutable struct EnemyTurnState
    is_animating::Bool
    current_enemy_index::Int
    enemy_queue::Vector{Any}  # Queue of (enemy_entity, enemy_script, intent, value)
    animation_phase::Symbol   # :idle, :wind_up, :projectile, :impact, :reflect_return, :result, :complete
    phase_elapsed::Float64
    projectile_entity::Any    # The acting enemy's intent HUD while it flies
    projectile_origin::Any    # Where the intent HUD launched from
    projectile_rest::Any      # Intent HUD look to restore when it lands
    battle_manager::Any
    on_complete_callback::Union{Function,Nothing}
    impact_original_pos::Any  # Store target position during impact phase
    impact_feedback_applied::Bool
    attack_was_reflected::Bool
    attack_was_dodged::Bool
    attack_was_blocked::Bool
    attack_dodge_failed::Bool
    reflect_from_pos::Any
    reflect_damage::Int
    result_text_shown::Bool
    frozen_effect_applied::Bool

    function EnemyTurnState()
        this = new()
        this.is_animating = false
        this.current_enemy_index = 0
        this.enemy_queue = []
        this.animation_phase = :idle
        this.phase_elapsed = 0.0
        this.projectile_entity = nothing
        this.projectile_origin = nothing
        this.projectile_rest = nothing
        this.battle_manager = nothing
        this.on_complete_callback = nothing
        this.impact_original_pos = nothing
        this.impact_feedback_applied = false
        this.attack_was_reflected = false
        this.attack_was_dodged = false
        this.attack_was_blocked = false
        this.attack_dodge_failed = false
        this.reflect_from_pos = nothing
        this.reflect_damage = 0
        this.result_text_shown = false
        this.frozen_effect_applied = false
        return this
    end
end

const TURN_STATE = EnemyTurnState()

# === PUBLIC API ===

"""
Start the enemy turn animation sequence.
Call this instead of directly processing enemy turns.
"""
function start_enemy_turn_animations(battle_manager, on_complete::Union{Function,Nothing}=nothing)
    TURN_STATE.battle_manager = battle_manager
    TURN_STATE.on_complete_callback = on_complete
    TURN_STATE.enemy_queue = []
    TURN_STATE.current_enemy_index = 0
    TURN_STATE.animation_phase = :idle
    TURN_STATE.phase_elapsed = 0.0

    # Build queue of enemies that will act
    for enemy in battle_manager.enemies
        enemy_script = enemy.scripts[1]
        if enemy_script.health <= 0
            continue
        end

        # Store enemy action in queue
        push!(TURN_STATE.enemy_queue, (
            entity=enemy,
            script=enemy_script,
            intent=uppercase(enemy_script.currentIntent),
            value=enemy_script.intentValue,
            is_frozen=(Int(enemy_script.freeze) > 0)
        ))
    end

    if isempty(TURN_STATE.enemy_queue)
        # No enemies to animate, complete immediately
        if on_complete !== nothing
            on_complete()
        end
        return
    end

    # Start animations
    TURN_STATE.is_animating = true
    TURN_STATE.current_enemy_index = 1
    TURN_STATE.animation_phase = :wind_up
    TURN_STATE.phase_elapsed = 0.0
    TURN_STATE.frozen_effect_applied = false

    @debug "Starting enemy turn animations for $(length(TURN_STATE.enemy_queue)) enemies"
end

"""
Update the animation system. Call this every frame during enemy turn.
Returns true if animations are still running, false when complete.
"""
function update(deltaTime::Float64)::Bool
    if !TURN_STATE.is_animating
        return false
    end

    TURN_STATE.phase_elapsed += deltaTime * BattleJuiceModule.time_scale()

    current_enemy = TURN_STATE.enemy_queue[TURN_STATE.current_enemy_index]

    # Use the queue snapshot: freeze is ticked down mid-animation, so a live
    # check would let a 1-stack freeze skip the first frame then attack.
    if current_enemy.is_frozen
        animate_frozen_enemy(current_enemy, deltaTime)
        return true
    end

    # Get animation config for this intent
    intent = current_enemy.intent
    anim = get(INTENT_ANIMATIONS, intent, INTENT_ANIMATIONS["ATTACK"])

    # Phase state machine
    if TURN_STATE.animation_phase == :wind_up
        animate_wind_up(current_enemy, anim, deltaTime)
    elseif TURN_STATE.animation_phase == :projectile
        animate_projectile(current_enemy, anim, deltaTime)
    elseif TURN_STATE.animation_phase == :impact
        animate_impact(current_enemy, anim, deltaTime)
    elseif TURN_STATE.animation_phase == :reflect_return
        animate_reflect_return(current_enemy, anim, deltaTime)
    elseif TURN_STATE.animation_phase == :result
        animate_result(current_enemy, anim, deltaTime)
    elseif TURN_STATE.animation_phase == :between_enemies
        animate_between_enemies(deltaTime)
    end

    return TURN_STATE.is_animating
end

"""
Check if animations are currently running.
"""
function is_animating()::Bool
    return TURN_STATE.is_animating
end

# === ANIMATION PHASES ===

function animate_wind_up(enemy_data, anim::IntentAnimation, deltaTime::Float64)
    progress = TURN_STATE.phase_elapsed / ANIM_CONFIG.wind_up_duration
    entity = enemy_data.entity

    if progress < 1.0
        try
            # Scale up
            scale_factor = 1.0 + (anim.wind_up_scale - 1.0) * sin(progress * π)
            entity.sprite.renderScale = Math.Vector2f(scale_factor, scale_factor)

            # Color tint - only for self-buffs (DEFEND/HEAL)
            # Don't tint enemy when attacking, only pulse scale
            is_self_buff = enemy_data.intent in ["DEFEND", "HEAL", "TEAMHEAL", "ALLYSHIELD", "SUMMON"]
            if is_self_buff
                tint_amount = sin(progress * π)
                r = Int(round(255 * (1 - tint_amount) + anim.wind_up_color[1] * tint_amount))
                g = Int(round(255 * (1 - tint_amount) + anim.wind_up_color[2] * tint_amount))
                b = Int(round(255 * (1 - tint_amount) + anim.wind_up_color[3] * tint_amount))
                entity.sprite.color = (r, g, b, 255)
            end
        catch e
            @debug "Error in wind_up animation: $(e)"
        end
    else
        try
            # Reset entity appearance
            entity.sprite.renderScale = Math.Vector2f(1, 1)
            entity.sprite.color = (255, 255, 255, 255)
        catch e
            @debug "Error resetting wind_up: $(e)"
        end

        # Move to next phase
        TURN_STATE.animation_phase = :projectile
        TURN_STATE.phase_elapsed = 0.0

        # Create projectile for ALL intents (attacks fly to player, buffs fly to health heart)
        create_projectile(enemy_data)
        fire_feedback!(enemy_data)

        play_intent_sfx(anim, enemy_data.value)
    end
end

function animate_projectile(enemy_data, anim::IntentAnimation, deltaTime::Float64)
    progress = TURN_STATE.phase_elapsed / ANIM_CONFIG.projectile_duration

    if progress < 1.0
        if TURN_STATE.projectile_entity !== nothing
            # Determine target based on intent type
            target_pos = nothing
            is_self_buff = enemy_data.intent in ["DEFEND", "HEAL", "TEAMHEAL", "ALLYSHIELD", "SUMMON"]

            if is_self_buff
                # Fly toward enemy's health heart
                try
                    health_heart = enemy_data.script.healthHeart
                    if health_heart !== nothing
                        target_pos = health_heart.transform.position
                    end
                catch e
                    @debug "Could not get health heart position: $(e)"
                end

                # Fallback to enemy position if health heart not found
                if target_pos === nothing
                    target_pos = enemy_data.entity.transform.position
                end
            elseif enemy_data.intent == "HEALKING"
                bm = TURN_STATE.battle_manager
                for e in bm.enemies
                    s = e.scripts[1]
                    if s.enemyKey == "ENEMY_KING" && s.health > 0
                        try
                            hh = s.healthHeart
                            if hh !== nothing
                                target_pos = hh.transform.position
                            end
                        catch ex
                            @debug "HealKing projectile target: $(ex)"
                        end
                        if target_pos === nothing
                            target_pos = e.transform.position
                        end
                        break
                    end
                end
            elseif enemy_data.intent == "CURSE"
                gc = TURN_STATE.battle_manager.gridController
                if gc !== nothing
                    cx = gc.gridStartX + (gc.gridWidth * gc.gridCellWidth) / 2
                    cy = gc.gridStartY + (gc.gridHeight * gc.gridCellHeight) / 2
                    target_pos = Math.Vector3f(Float32(cx), Float32(cy), 0.0f0)
                end
                if target_pos === nothing
                    player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
                    if player_entity !== nothing
                        target_pos = player_entity.transform.position
                    end
                end
            else
                # Fly toward player for attacks/debuffs
                player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
                if player_entity !== nothing
                    target_pos = player_entity.transform.position
                end
            end

            if target_pos !== nothing
                enemy_pos = enemy_data.entity.transform.position
                origin = TURN_STATE.projectile_origin
                base_scale = TURN_STATE.projectile_rest.scale

                # Eased movement
                eased_progress = ease_out_cubic(progress)
                current_x = origin.x + (target_pos.x - origin.x) * eased_progress
                current_y = origin.y + (target_pos.y - origin.y) * eased_progress

                TURN_STATE.projectile_entity.transform.position = Math.Vector3f(current_x, current_y, 0.0)

                if is_self_buff
                    # Self-buff: Scale UP and FADE OUT as it approaches health heart
                    scale = 1.0 + progress  # Grows to 2x its HUD size
                    alpha = Int(round(255 * (1.0 - progress)))  # Fades from 255 to 0

                    TURN_STATE.projectile_entity.transform.scale = Math.Vector3f(base_scale.x * scale, base_scale.y * scale, 1.0)

                    # Apply fade via sprite color alpha
                    try
                        base_color = anim.projectile_color
                        TURN_STATE.projectile_entity.sprite.color = (base_color[1], base_color[2], base_color[3], alpha)
                    catch e
                        @debug "Could not set projectile alpha: $(e)"
                    end

                    # No rotation for self-buffs, looks cleaner
                else
                    # Attack: Rotate and pulse like before
                    TURN_STATE.projectile_entity.transform.rotation = Math.Vector3f(0, 0, progress * 720)

                    # Scale pulse
                    scale = 1.0 + sin(progress * π * 2) * 0.2
                    TURN_STATE.projectile_entity.transform.scale = Math.Vector3f(base_scale.x * scale, base_scale.y * scale, 1.0)

                    if enemy_data.intent in ["ATTACK", "BASH", "BURN", "FREEZE", "POISON", "WEAKEN"]
                        player_entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")
                        if player_entity !== nothing
                            BattleJuiceModule.set_brace!(
                                player_entity,
                                Math.Vector2f(enemy_pos.x, enemy_pos.y);
                                intensity=min(1.0, 0.35 + eased_progress * 0.65),
                            )
                        end
                    end
                end
            end
        end
    else
        is_self_buff = enemy_data.intent in ["DEFEND", "HEAL", "TEAMHEAL", "ALLYSHIELD", "SUMMON"]

        if is_self_buff
            destroy_projectile()
            apply_enemy_intent_effect(enemy_data)
            _begin_result!()
        elseif is_physical_strike(enemy_data.intent)
            player_entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")
            BattleJuiceModule.clear_brace!(player_entity)
            defense = resolve_player_defense(TURN_STATE.battle_manager, enemy_data)
            if defense == :reflect
                start_reflect_return!(enemy_data)
            else
                destroy_projectile()
                if defense == :dodge
                    _begin_result!()
                elseif defense == :blocked
                    apply_enemy_intent_effect(enemy_data)
                    if player_entity !== nothing
                        BattleJuiceModule.shield_impact!(player_entity)
                    end
                    _begin_result!()
                else
                    TURN_STATE.animation_phase = :impact
                    TURN_STATE.phase_elapsed = 0.0
                    TURN_STATE.impact_feedback_applied = false
                    apply_enemy_intent_effect(enemy_data)
                end
            end
        else
            destroy_projectile()
            player_entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")
            BattleJuiceModule.clear_brace!(player_entity)
            TURN_STATE.animation_phase = :impact
            TURN_STATE.phase_elapsed = 0.0
            TURN_STATE.impact_feedback_applied = false
            apply_enemy_intent_effect(enemy_data)
        end
    end
end

function animate_impact(enemy_data, anim::IntentAnimation, deltaTime::Float64)
    progress = TURN_STATE.phase_elapsed / ANIM_CONFIG.impact_duration

    target_entity = nothing
    if enemy_data.intent in ["ATTACK", "BASH", "BURN", "FREEZE", "POISON", "WEAKEN"]
        target_entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")
    elseif enemy_data.intent == "HEALKING"
        bm = TURN_STATE.battle_manager
        for e in bm.enemies
            s = e.scripts[1]
            if s.enemyKey == "ENEMY_KING" && s.health > 0
                target_entity = e
                break
            end
        end
    end

    if !TURN_STATE.impact_feedback_applied && target_entity !== nothing && anim.impact_shake_intensity > 0
        TURN_STATE.impact_feedback_applied = true
        try
            TURN_STATE.impact_original_pos = target_entity.transform.position
        catch
            TURN_STATE.impact_original_pos = nothing
        end
        BattleJuiceModule.player_hit_impact!(
            target_entity,
            enemy_data.entity.transform.position;
            shake_intensity = anim.impact_shake_intensity,
        )
        BattleJuiceModule.clear_brace!(target_entity)
    end

    if progress >= 1.0
        if target_entity !== nothing
            try
                target_entity.sprite.color = (255, 255, 255, 255)
                if TURN_STATE.impact_original_pos !== nothing
                    target_entity.transform.position = TURN_STATE.impact_original_pos
                end
            catch e
                @debug "Could not reset entity: $(e)"
            end
        end

        TURN_STATE.impact_original_pos = nothing
        _begin_result!()
    end
end

function animate_result(enemy_data, anim::IntentAnimation, deltaTime::Float64)
    progress = TURN_STATE.phase_elapsed / ANIM_CONFIG.result_display_duration

    if !TURN_STATE.result_text_shown
        TURN_STATE.result_text_shown = true
        show_result_text(enemy_data)
    end

    if progress >= 1.0
        # Move to next enemy or complete
        advance_to_next_enemy()
    end
end

function animate_between_enemies(deltaTime::Float64)
    progress = TURN_STATE.phase_elapsed / ANIM_CONFIG.between_enemies_delay

    if progress >= 1.0
        if TURN_STATE.current_enemy_index <= length(TURN_STATE.enemy_queue)
            # Start next enemy's animation
            TURN_STATE.animation_phase = :wind_up
            TURN_STATE.phase_elapsed = 0.0
        else
            # All done
            complete_enemy_turn()
        end
    end
end

function animate_frozen_enemy(enemy_data, deltaTime::Float64)
    progress = TURN_STATE.phase_elapsed / (ANIM_CONFIG.wind_up_duration + ANIM_CONFIG.result_display_duration)
    entity = enemy_data.entity

    if progress < 1.0
        # Frozen shake and blue tint
        shake_intensity = 0.03 * (1.0 - progress)
        shake_x = (rand() - 0.5) * 2.0 * shake_intensity
        shake_y = (rand() - 0.5) * 2.0 * shake_intensity

        entity.sprite.color = (150, 200, 255, 255)

        if !TURN_STATE.frozen_effect_applied
            TURN_STATE.frozen_effect_applied = true
            DisplayTextModule.display_text(
                "frozen_indicator_$(enemy_data.script.id)",
                "FROZEN!";
                fontSize=28,
                anchor=:center,
                anchorOffset=Math.Vector2(0, -150),
                lifetime=1200,
                color=(100, 200, 255, 255)
            )
            apply_frozen_enemy_effect(enemy_data)
        end
    else
        # Reset and advance
        entity.sprite.color = (255, 255, 255, 255)
        advance_to_next_enemy()
    end
end

# === HELPER FUNCTIONS ===

const PROJECTILE_LAYER = 20

"""Fire the enemy's own intent HUD; it stays hidden after landing until `reveal_intent!` on the next player turn."""
function create_projectile(enemy_data)
    TURN_STATE.projectile_entity = nothing
    intent = enemy_data.script.intent
    (intent === nothing || !intent.isActive) && return
    try
        pos = intent.transform.position
        TURN_STATE.projectile_origin = Math.Vector3f(pos.x, pos.y, 0.0)
        TURN_STATE.projectile_rest = (
            scale = intent.transform.scale,
            rotation = intent.transform.rotation,
            color = intent.sprite.color,
            layer = intent.sprite.layer,
        )
        intent.sprite.layer = PROJECTILE_LAYER
        enemy_data.script.intentLaunched = true
        TURN_STATE.projectile_entity = intent
    catch e
        @debug "Error launching intent HUD: $(e)"
    end
end

function destroy_projectile()
    projectile = TURN_STATE.projectile_entity
    projectile === nothing && return
    TURN_STATE.projectile_entity = nothing
    rest = TURN_STATE.projectile_rest
    try
        projectile.isActive = false
        projectile.transform.scale = rest.scale
        projectile.transform.rotation = rest.rotation
        projectile.sprite.color = rest.color
        projectile.sprite.layer = rest.layer
    catch e
        @debug "Error landing intent HUD: $(e)"
    end
end

"""Fade every launched intent HUD back in once the enemy turn is over."""
function reveal_intents!()
    bm = TURN_STATE.battle_manager
    bm === nothing && return
    for enemy in bm.enemies
        Scripts.EnemyModule.reveal_intent!(enemy.scripts[1])
    end
end

"""Attackers lurch as their intent fires: a violent shake and a red tint."""
function fire_feedback!(enemy_data)
    is_physical_strike(enemy_data.intent) || return
    BattleJuiceModule.shake!(enemy_data.entity; intensity = 0.2, duration = 0.35)
    BattleJuiceModule.flash!(enemy_data.entity; color = (255, 60, 60, 255), duration = 0.35)
end

heal_glow!(entity) = BattleJuiceModule.flash!(entity; color = (110, 255, 130, 255), duration = 0.6)

function play_debuff_sfx()
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", "debuff"),
            false, 0.85, 0, 1,
        )
    catch
    end
end

function apply_enemy_intent_effect(enemy_data)
    bm = TURN_STATE.battle_manager
    enemy_script = enemy_data.script
    intent = enemy_data.intent
    value = enemy_data.value

    @debug "Applying effect: $(intent) with value $(value)"

    if intent == "ATTACK"
        apply_connected_attack!(bm, enemy_data)
    elseif intent == "BASH"
        apply_connected_attack!(bm, enemy_data)
        bm.user.vulnerable = clamp(bm.user.vulnerable + 1, 0, 5)
        @debug "Bash applied, player vulnerable is $(bm.user.vulnerable)"
    elseif intent == "WEAKEN"
        bm.user.weaken = clamp(bm.user.weaken + value, 0, 5)
        @debug "Player weaken is $(bm.user.weaken)"
        play_debuff_sfx()
    elseif intent == "DEFEND"
        enemy_script.shield = value
        @debug "Enemy shield is $(enemy_script.shield)"
    elseif intent == "HEAL"
        enemy_script.health = clamp(enemy_script.health + value, 0, enemy_script.maxHealth)
        heal_glow!(enemy_data.entity)
        @debug "Enemy health is $(enemy_script.health) after healing"
    elseif intent == "BURN"
        bm.user.burn = clamp(bm.user.burn + value, 0, 999)
        @debug "Player burn is $(bm.user.burn)"
        play_debuff_sfx()
    elseif intent == "FREEZE"
        bm.user.freeze = clamp(bm.user.freeze + value, 0, 999)
        bm.moveCount = max(bm.moveCount - 1, 1)
        @debug "Player freeze is $(bm.user.freeze)"
        play_debuff_sfx()
    elseif intent == "POISON"
        bm.user.poison = clamp(bm.user.poison + value, 0, 999)
        @debug "Player poison is $(bm.user.poison)"
        play_debuff_sfx()
    elseif intent == "SKILL"
        Scripts.BattleManagerModule.execute_enemy_skill(bm, enemy_script)
    elseif intent == "HEALKING"
        BossAllyIntentsModule.apply_heal_king!(bm, value)
        for e in bm.enemies
            s = e.scripts[1]
            if s.enemyKey == "ENEMY_KING" && s.health > 0
                heal_glow!(e)
                break
            end
        end
    elseif intent == "ALLYSHIELD"
        BossAllyIntentsModule.apply_ally_shield_except_actor!(bm, enemy_script, value)
    elseif intent == "CURSE"
        gc = bm.gridController
        if gc !== nothing
            n = clamp(value, 1, 8)
            Scripts.GridControllerModule.start_curse_skull_cluster_animation(gc, n)
        end
    elseif intent == "TEAMHEAL"
        for enemy in bm.enemies
            es = enemy.scripts[1]
            if es.health > 0
                es.health = clamp(es.health + value, 0, es.maxHealth)
                heal_glow!(enemy)
            end
        end
    elseif intent == "SUMMON"
        apply_crowman_summon!(bm, max(1, Int(value)))
    end
end

function is_physical_strike(intent)::Bool
    return intent == "ATTACK" || intent == "BASH"
end

"""Incoming strike damage after poison reduction and player vulnerable (matches take_damage)."""
function effective_incoming_attack_damage(bm, enemy_data)::Int
    attack_damage = Int(enemy_data.value)
    try
        poison = Int(enemy_data.script.poison)
        if poison > 0
            attack_damage = max(0, attack_damage - min(poison, attack_damage))
        end
    catch
    end
    try
        if Int(bm.user.vulnerable) > 0
            attack_damage = floor(Int64, attack_damage * 1.5)
        end
    catch
    end
    return attack_damage
end

function attack_fully_blocked_by_shield(bm, damage::Int)::Bool
    damage <= 0 && return true
    return Int(bm.user.shield) >= damage
end

function resolve_player_defense(bm, enemy_data)::Symbol
    globals = JulGame.UserGlobals["Module"]
    value = enemy_data.value
    player_entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")
    incoming = effective_incoming_attack_damage(bm, enemy_data)

    # Dodge first — spend the roll even if shield would have fully blocked.
    dodge_chance = incoming > 0 ? globals.PiecesModule.player_dodge_chance(bm.user) : 0
    if dodge_chance > 0
        has_shadow_cloak = globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_SHADOWCLOAK)

        gate = rand() * 100
        if gate < dodge_chance
            @debug "Player dodged the attack! at $(dodge_chance) with gate of $(gate)"

            if player_entity !== nothing
                threat = try
                    enemy_data.entity.transform.position
                catch
                    nothing
                end
                dodge_dir = -1.0
                if threat !== nothing
                    try
                        dodge_dir = player_entity.transform.position.x >= threat.x ? 1.0 : -1.0
                    catch
                    end
                end
                BattleJuiceModule.dodge_step!(player_entity; direction = dodge_dir)
                ActionResultDisplayModule.push(
                    player_entity;
                    kind = :status,
                    value = BattleStringsModule.BATTLE_STRINGS[:feedback_dodge],
                    piece_key = "PIECE_DODGE",
                    color = (255, 220, 100, 255),
                )
                try
                    Globals.ObserverModule.notify(:dodge_success, Dict(:target => player_entity))
                catch
                end
            end

            if has_shadow_cloak && !bm.user.shadowCloakUsed
                bm.user.shadowCloakUsed = true
                bm.moveCount += 1
            end
            TURN_STATE.attack_was_dodged = true
            bm.user.dodge_chance = 0
            Scripts.PlayerFocusZoomModule.release_focus!()
            return :dodge
        else
            @debug "No dodge at $(dodge_chance) with gate of $(gate)"
            TURN_STATE.attack_dodge_failed = true
            if player_entity !== nothing
                ActionResultDisplayModule.push(
                    player_entity;
                    kind = :status,
                    value = BattleStringsModule.BATTLE_STRINGS[:feedback_dodge_failed],
                    piece_key = "PIECE_DODGE",
                    color = (180, 180, 180, 255),
                )
            end
        end
        bm.user.dodge_chance = 0
    end

    if attack_fully_blocked_by_shield(bm, incoming)
        TURN_STATE.attack_was_blocked = true
        Scripts.PlayerFocusZoomModule.release_focus!()
        return :blocked
    end

    reflect_chance = globals.PiecesModule.player_reflect_chance(bm.user)
    if reflect_chance > 0 && rand() * 100 < reflect_chance
        @debug "Player reflected the attack!"
        TURN_STATE.reflect_damage = min(value, 20)
        return :reflect
    end

    return :hit
end

function play_intent_sfx(anim::IntentAnimation, value=0)
    name = anim.sound_effect
    # Player hurt sounds play when the hit lands (take_damage), not at projectile spawn.
    if name == "damagenormal1" || name == "damageheavy" || startswith(name, "damagenormal")
        return
    end
    if name == "healsmall" && try Int(value) catch; 0 end >= 5
        name = "healbig"
    end
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", name),
            false, 0.7, 0, 1,
        )
    catch e
        @debug "Could not play sound: $(e)"
    end
end

function _intent_source_key(intent::String)::String
    intent == "ATTACK" && return "PIECE_SWORD"
    intent == "BASH" && return "PIECE_MACE"
    intent == "WEAKEN" && return "PIECE_SWORD"
    intent == "BURN" && return "PIECE_SWORD"
    intent == "HEAL" && return "PIECE_POTION"
    intent == "TEAMHEAL" && return "PIECE_POTION"
    intent == "HEALKING" && return "PIECE_POTION"
    intent == "DEFEND" && return "PIECE_SHIELD"
    intent == "ALLYSHIELD" && return "PIECE_SHIELD"
    intent == "FREEZE" && return "PIECE_SHIELD"
    intent == "POISON" && return "STATUS_POISON"
    intent == "CURSE" && return "PIECE_SKULL"
    return ""
end

function _begin_result!()
    TURN_STATE.animation_phase = :result
    TURN_STATE.phase_elapsed = 0.0
    TURN_STATE.result_text_shown = false
end

function play_reflect_sfx()
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", "reflect"),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "reflect sfx: $e"
    end
end

"""Shield pops up where the projectile is caught (its center), or on the reflect origin."""
function _spawn_reflect_shield!()
    projectile = TURN_STATE.projectile_entity
    center = TURN_STATE.reflect_from_pos
    if projectile !== nothing
        try
            p = projectile.transform.position
            s = projectile.transform.scale
            center = Math.Vector3f(p.x + s.x / 2, p.y + s.y / 2, 0.0)
        catch
        end
    end
    center === nothing && return
    BattleJuiceModule.reflect_shield!(center)
end

function start_reflect_return!(enemy_data)
    TURN_STATE.attack_was_reflected = true
    TURN_STATE.animation_phase = :reflect_return
    TURN_STATE.phase_elapsed = 0.0
    play_reflect_sfx()
    Scripts.PlayerFocusZoomModule.release_focus!()

    player_entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")
    if player_entity !== nothing
        BattleJuiceModule.flash!(player_entity; color=(255, 255, 255, 255), duration=0.3)
        pos = player_entity.transform.position
        TURN_STATE.reflect_from_pos = Math.Vector3f(pos.x, pos.y, 0.0)
    elseif TURN_STATE.projectile_entity !== nothing
        pos = TURN_STATE.projectile_entity.transform.position
        TURN_STATE.reflect_from_pos = Math.Vector3f(pos.x, pos.y, 0.0)
    end

    if TURN_STATE.projectile_entity !== nothing
        try
            spr = TURN_STATE.projectile_entity.sprite
            spr.isFlipped = !spr.isFlipped
        catch e
            @debug "Could not flip reflected projectile: $(e)"
        end
    end
    _spawn_reflect_shield!()

    DisplayTextModule.display_text(
        "reflect_success",
        "REFLECTED!";
        fontSize=24,
        anchor=:bottomLeft,
        anchorOffset=Math.Vector2(150, -200),
        lifetime=1500,
        color=(200, 150, 255, 255)
    )
end

function animate_reflect_return(enemy_data, anim::IntentAnimation, deltaTime::Float64)
    progress = TURN_STATE.phase_elapsed / ANIM_CONFIG.projectile_duration
    projectile = TURN_STATE.projectile_entity
    enemy_pos = enemy_data.entity.transform.position
    from_pos = TURN_STATE.reflect_from_pos
    if from_pos === nothing
        from_pos = enemy_pos
    end

    if progress < 1.0 && projectile !== nothing
        eased = ease_out_cubic(progress)
        projectile.transform.position = Math.Vector3f(
            from_pos.x + (enemy_pos.x - from_pos.x) * eased,
            from_pos.y + (enemy_pos.y - from_pos.y) * eased,
            0.0,
        )
        projectile.transform.rotation = Math.Vector3f(0, 0, progress * 720)
        scale = 1.0 + sin(progress * π * 2) * 0.2
        base_scale = TURN_STATE.projectile_rest.scale
        projectile.transform.scale = Math.Vector3f(base_scale.x * scale, base_scale.y * scale, 1.0)
        try
            base_color = anim.projectile_color
            projectile.sprite.color = (min(255, base_color[1] + 40), min(255, base_color[2] + 20), 255, 255)
        catch
        end
        return
    end

    destroy_projectile()
    TURN_STATE.reflect_from_pos = nothing
    bm = TURN_STATE.battle_manager
    Scripts.BattleManagerModule.take_damage(bm, enemy_data.script, TURN_STATE.reflect_damage)
    _begin_result!()
end

function apply_connected_attack!(bm, enemy_data)
    globals = JulGame.UserGlobals["Module"]
    value = enemy_data.value

    if bm.user.shield > 0 &&
       globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_SPLINTEREDSHIELD)
        block_damage = 5
        @debug "Splintered Shield effect applied, dealing $(block_damage) damage back to attacker"
        Scripts.BattleManagerModule.take_damage(bm, enemy_data.script, block_damage)
    end

    attack_damage = value
    enemy_script = enemy_data.script
    if enemy_script.poison > 0
        poison_reduction = min(enemy_script.poison, attack_damage)
        attack_damage = max(0, attack_damage - poison_reduction)
        @debug "Poison reduced enemy attack by $(poison_reduction) (poison: $(enemy_script.poison), original: $(value), final: $(attack_damage))"
        if poison_reduction > 0
            DisplayTextModule.display_text(
                "poison_reduction_text",
                "POISON: -$(poison_reduction)";
                fontSize=20,
                anchor=:center,
                anchorOffset=Math.Vector2(0, 50),
                lifetime=1500,
                color=(100, 255, 100, 255)
            )
        end
    end

    Scripts.BattleManagerModule.take_damage(bm, bm.user, attack_damage; skip_battle_damage_feedback=true)
end

function apply_frozen_enemy_effect(enemy_data)
    bm = TURN_STATE.battle_manager
    enemy_script = enemy_data.script

    # Skip action: take freeze damage, tick stacks, roll next intent.
    freeze_damage = floor(Int64, max(0, Int(enemy_script.freeze)) * 2)
    if freeze_damage > 0
        Scripts.BattleManagerModule.take_damage(bm, enemy_script, freeze_damage)
    end

    enemy_script.freeze = max(0, Int(enemy_script.freeze) - 1)
    Scripts.EnemyModule.set_next_enemy_intent(enemy_script)
end

function show_result_text(enemy_data)
    intent = enemy_data.intent
    value = enemy_data.value
    source = _intent_source_key(intent)

    player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")

    if TURN_STATE.attack_was_dodged
        # Chip already pushed in resolve_player_defense.
    elseif TURN_STATE.attack_was_blocked
        player_entity !== nothing && ActionResultDisplayModule.push(
            player_entity;
            kind = :status,
            value = BattleStringsModule.BATTLE_STRINGS[:feedback_blocked],
            piece_key = "PIECE_SHIELD",
            color = (120, 200, 255, 255),
        )
    elseif (intent == "ATTACK" || intent == "BASH") && !TURN_STATE.attack_was_reflected
        player_entity !== nothing && ActionResultDisplayModule.push(player_entity; kind = :damage, value = value, piece_key = source)
    elseif intent == "DEFEND"
        ActionResultDisplayModule.push(enemy_data.entity; kind = :shield, value = value, piece_key = source)
    elseif intent == "HEAL"
        ActionResultDisplayModule.push(enemy_data.entity; kind = :heal, value = value, piece_key = source)
    elseif intent == "HEALKING"
        bm = TURN_STATE.battle_manager
        for e in bm.enemies
            s = e.scripts[1]
            if s.enemyKey == "ENEMY_KING" && s.health > 0
                ActionResultDisplayModule.push(e; kind = :heal, value = value, piece_key = source)
                break
            end
        end
    elseif intent == "ALLYSHIELD"
        player_entity !== nothing && ActionResultDisplayModule.push(player_entity; kind = :shield, value = value, piece_key = source)
    elseif intent == "BURN"
        label, color, icon, badge = BattleJuiceModule.status_chip_label(:burn, value)
        player_entity !== nothing && ActionResultDisplayModule.push(player_entity; kind = :status, value = label, icon = icon, badge = badge, color = color)
    elseif intent == "FREEZE"
        label, color, icon, badge = BattleJuiceModule.status_chip_label(:freeze, value)
        player_entity !== nothing && ActionResultDisplayModule.push(player_entity; kind = :status, value = label, icon = icon, badge = badge, color = color)
    elseif intent == "POISON"
        label, color, icon, badge = BattleJuiceModule.status_chip_label(:poison, value)
        player_entity !== nothing && ActionResultDisplayModule.push(player_entity; kind = :status, value = label, icon = icon, badge = badge, color = color)
    elseif intent == "WEAKEN"
        player_entity !== nothing && ActionResultDisplayModule.push(player_entity; kind = :status, value = "Weak $(value)", piece_key = source, icon = BattleJuiceModule.status_arrow_icon(false), color = (160, 120, 220, 255))
    elseif intent == "CURSE"
        player_entity !== nothing && ActionResultDisplayModule.push(player_entity; kind = :status, value = "Cursed!", piece_key = source, icon = BattleJuiceModule.status_arrow_icon(false), color = (180, 100, 220, 255))
    elseif intent == "TEAMHEAL"
        ActionResultDisplayModule.push(enemy_data.entity; kind = :heal, value = value, piece_key = source)
    elseif intent == "SUMMON"
        ActionResultDisplayModule.push(enemy_data.entity; kind = :status, value = "Summon $(value)", piece_key = source, icon = BattleJuiceModule.status_arrow_icon(true), color = (200, 200, 220, 255))
    end
end

function advance_to_next_enemy()
    bm = TURN_STATE.battle_manager

    # Check if battle ended (player death)
    if bm.currentState == bm.battleStates[:battleEnd]
        complete_enemy_turn()
        return
    end

    # Frozen path already rolled next intent in apply_frozen_enemy_effect.
    current_enemy = TURN_STATE.enemy_queue[TURN_STATE.current_enemy_index]
    if !TURN_STATE.frozen_effect_applied
        Scripts.EnemyModule.set_next_enemy_intent(current_enemy.script)
    end
    if current_enemy.script.vulnerable > 0
        current_enemy.script.vulnerable -= 1
    end
    if current_enemy.script.poison > 0
        current_enemy.script.poison -= 1
    end

    TURN_STATE.current_enemy_index += 1
    TURN_STATE.attack_was_reflected = false
    TURN_STATE.attack_was_dodged = false
    TURN_STATE.attack_was_blocked = false
    TURN_STATE.attack_dodge_failed = false
    TURN_STATE.reflect_from_pos = nothing
    TURN_STATE.reflect_damage = 0
    TURN_STATE.frozen_effect_applied = false

    if TURN_STATE.current_enemy_index > length(TURN_STATE.enemy_queue)
        # All enemies done
        complete_enemy_turn()
    else
        # Pause before next enemy
        TURN_STATE.animation_phase = :between_enemies
        TURN_STATE.phase_elapsed = 0.0
    end
end

function complete_enemy_turn()
    TURN_STATE.is_animating = false
    TURN_STATE.animation_phase = :idle

    destroy_projectile()
    reveal_intents!()

    @debug "Enemy turn animations complete"

    # Call completion callback
    if TURN_STATE.on_complete_callback !== nothing
        TURN_STATE.on_complete_callback()
    end
end

# Easing function
function ease_out_cubic(t::Float64)::Float64
    return 1.0 - (1.0 - t)^3
end

# === CONFIGURATION API ===

function set_animation_speed(multiplier::Float64)
    ANIM_CONFIG.wind_up_duration /= multiplier
    ANIM_CONFIG.projectile_duration /= multiplier
    ANIM_CONFIG.impact_duration /= multiplier
    ANIM_CONFIG.result_display_duration /= multiplier
end

function set_between_enemies_delay(delay::Float64)
    ANIM_CONFIG.between_enemies_delay = delay
end

function set_total_animation_duration(duration::Float64)
    # Distribute duration across phases
    ANIM_CONFIG.wind_up_duration = duration * 0.2
    ANIM_CONFIG.projectile_duration = duration * 0.25
    ANIM_CONFIG.impact_duration = duration * 0.25
    ANIM_CONFIG.result_display_duration = duration * 0.3
end

end # module
