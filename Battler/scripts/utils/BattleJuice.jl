# Lean immediate-mode battle game-feel primitives (flash, shake, hitstop, death, etc.)
module BattleJuiceModule
using JulGame
include("DisplayText.jl")
using .DisplayTextModule
using ..Scripts
using ..ActionResultDisplayModule
include("Easings.jl")

const PLAYER_ENTITY_ID = "95b3f5d9-a580-4a15-b745-9ecf1fc76620"

mutable struct FlashEffect
    entity::Any
    original_color::NTuple{4, Int}
    flash_color::NTuple{4, Int}
    duration::Float64
    elapsed::Float64
end

mutable struct ShakeEffect
    entity::Any
    original_position::Math.Vector3f
    intensity::Float64
    duration::Float64
    elapsed::Float64
    # Smooth decaying sway (matches UI button hover) instead of random jitter.
    wobble::Bool
end

mutable struct KnockbackEffect
    entity::Any
    original_position::Math.Vector3f
    direction::Math.Vector2f
    distance::Float64
    duration::Float64
    elapsed::Float64
end

mutable struct ScalePulseEffect
    entity::Any
    original_scale::Math.Vector3f
    target_scale::Math.Vector3f
    duration::Float64
    elapsed::Float64
end

mutable struct DodgeEffect
    entity::Any
    original_position::Math.Vector3f
    direction::Float64
    distance::Float64
    out_duration::Float64
    return_duration::Float64
    elapsed::Float64
end

mutable struct BraceEffect
    entity::Any
    original_scale::Math.Vector3f
    original_position::Math.Vector3f
    threat_direction::Math.Vector2f
    intensity::Float64
end

mutable struct DeathEffect
    entity::Any
    style::Symbol
    original_scale::Math.Vector3f
    original_position::Math.Vector3f
    original_color::NTuple{4, Int}
    duration::Float64
    elapsed::Float64
    on_complete::Union{Nothing, Function}
end

mutable struct FloatingNumberEffect
    id::String
    entity::Any
    text::String
    color::NTuple{4, Int}
    start_offset_y::Float64
    duration::Float64
    elapsed::Float64
end

mutable struct ScreenFlashEffect
    color::NTuple{4, Int}
    intensity::Float64
    duration::Float64
    elapsed::Float64
end

mutable struct ReflectShieldEffect
    entity::Any
    duration::Float64
    elapsed::Float64
end

mutable struct ShockBolt
    entity::Any
    life::Float64
end

mutable struct ShockArcEffect
    entity::Any
    duration::Float64
    elapsed::Float64
    cooldown::Float64
    bolts::Vector{ShockBolt}
    original_color::Union{Nothing, NTuple{4, Int}}
end

mutable struct JuiceState
    hitstop_remaining::Float64
    camera_trauma::Float64
    camera_original_pos::Union{Nothing, Math.Vector3f}
    camera_initialized::Bool
    flashes::Vector{FlashEffect}
    shakes::Vector{ShakeEffect}
    knockbacks::Vector{KnockbackEffect}
    scale_pulses::Vector{ScalePulseEffect}
    dodges::Vector{DodgeEffect}
    braces::Dict{UInt, BraceEffect}
    deaths::Vector{DeathEffect}
    floating_numbers::Vector{FloatingNumberEffect}
    screen_flashes::Vector{ScreenFlashEffect}
    reflect_shields::Vector{ReflectShieldEffect}
    shock_arcs::Vector{ShockArcEffect}
    juice_observer_registered::Bool
    slowmo_scale::Float64
end

const JUICE = JuiceState(
    0.0, 0.0, nothing, false,
    FlashEffect[], ShakeEffect[], KnockbackEffect[], ScalePulseEffect[],
    DodgeEffect[], Dict{UInt, BraceEffect}(), DeathEffect[], FloatingNumberEffect[],
    ScreenFlashEffect[], ReflectShieldEffect[], ShockArcEffect[], false, 1.0,
)

const DEATH_STYLES = Dict{String, Symbol}(
    "ENEMY_SLIME" => :pop,
    "ENEMY_SNAKE" => :dissolve,
    "ENEMY_BIRDMAN" => :squash_fade,
    "ENEMY_GHOST" => :dissolve,
    "ENEMY_HAPPYGHOST" => :dissolve,
    "ENEMY_SADGHOST" => :dissolve,
    "ENEMY_SCYTHEGHOST" => :dissolve,
    "ENEMY_CROW" => :pop,
    "ENEMY_CROWMAN" => :squash_fade,
    "ENEMY_KING" => :squash_fade,
    "ENEMY_KNIGHT" => :squash_fade,
    "ENEMY_PRIEST" => :squash_fade,
)

function time_scale()::Float64
    JUICE.hitstop_remaining > 0.0 && return 0.0
    return JUICE.slowmo_scale
end

function scaled_delta(deltaTime::Float64)::Float64
    return deltaTime * time_scale()
end

function hitstop!(seconds::Float64)
    JUICE.hitstop_remaining = max(JUICE.hitstop_remaining, seconds)
end

function set_slowmo!(scale::Float64)
    JUICE.slowmo_scale = clamp(scale, 0.05, 1.0)
end

function entity_id(entity)::UInt
    return objectid(entity)
end

function entity_sprite(entity)
    try
        return entity.sprite
    catch
        return nothing
    end
end

function ensure_camera_original!()
    if !JUICE.camera_initialized
        JUICE.camera_original_pos = MAIN.scene.camera.position
        JUICE.camera_initialized = true
    end
end

function sync_camera_origin!()
    try
        JUICE.camera_original_pos = MAIN.scene.camera.position
        JUICE.camera_initialized = true
    catch
    end
end

function player_entity()
    return JulGame.SceneModule.get_entity_by_id(MAIN.scene, PLAYER_ENTITY_ID)
end

function selected_enemy_entity(battle_manager)
    if battle_manager === nothing || battle_manager.selectedEnemy === nothing
        return nothing
    end
    selected = battle_manager.selectedEnemy
    try
        if isdefined(selected, :parent) && selected.parent !== nothing
            return selected.parent
        end
    catch
    end
    for enemy in battle_manager.enemies
        if enemy.scripts[1] === selected
            return enemy
        end
    end
    return nothing
end

function death_style_for_enemy(enemy_key::String)::Symbol
    return get(DEATH_STYLES, enemy_key, :squash_fade)
end

# Remove an in-flight effect for this entity, returning it so its recorded
# original state can be carried over. Reading the live transform instead would
# capture a mid-effect (already scaled/moved/tinted) value as the new baseline
# and compound it forever.
function take_over_effect!(effects, entity)
    index = findfirst(effect -> effect.entity === entity, effects)
    index === nothing && return nothing
    existing = effects[index]
    deleteat!(effects, index)
    return existing
end

function flash!(
    entity;
    color::NTuple{4, Int} = (255, 200, 200, 255),
    duration::Float64 = 0.22,
)
    entity === nothing && return
    sprite = entity_sprite(entity)
    sprite === nothing && return
    existing = take_over_effect!(JUICE.flashes, entity)
    original_color = existing === nothing ? sprite.color : existing.original_color
    push!(
        JUICE.flashes,
        FlashEffect(entity, original_color, color, duration, 0.0),
    )
end

function shake!(
    entity;
    intensity::Float64 = 0.12,
    duration::Float64 = 0.25,
    wobble::Bool = false,
)
    entity === nothing && return
    try
        existing = take_over_effect!(JUICE.shakes, entity)
        original_position = existing === nothing ? entity.transform.position : existing.original_position
        push!(
            JUICE.shakes,
            ShakeEffect(
                entity,
                original_position,
                intensity,
                duration,
                0.0,
                wobble,
            ),
        )
    catch
    end
end

"""End an entity's shake now and put it back where the shake started."""
function cancel_shake!(entity)
    effect = take_over_effect!(JUICE.shakes, entity)
    effect === nothing && return
    try
        entity.transform.position = effect.original_position
    catch
    end
end

function knockback!(
    entity,
    direction::Math.Vector2f;
    distance::Float64 = 0.18,
    duration::Float64 = 0.14,
)
    entity === nothing && return
    len = sqrt(direction.x^2 + direction.y^2)
    dir = len > 0.001 ? Math.Vector2f(direction.x / len, direction.y / len) : Math.Vector2f(1.0, 0.0)
    try
        existing = take_over_effect!(JUICE.knockbacks, entity)
        original_position = existing === nothing ? entity.transform.position : existing.original_position
        push!(
            JUICE.knockbacks,
            KnockbackEffect(
                entity,
                original_position,
                dir,
                distance,
                duration,
                0.0,
            ),
        )
    catch
    end
end

function scale_pulse!(
    entity;
    intensity::Float64 = 1.08,
    duration::Float64 = 0.2,
)
    entity === nothing && return
    try
        existing = take_over_effect!(JUICE.scale_pulses, entity)
        base = existing === nothing ? entity.transform.scale : existing.original_scale
        # An active brace also owns the scale; its recorded base is the true one.
        brace = get(JUICE.braces, entity_id(entity), nothing)
        if existing === nothing && brace !== nothing
            base = brace.original_scale
        end
        push!(
            JUICE.scale_pulses,
            ScalePulseEffect(
                entity,
                base,
                Math.Vector3f(base.x * intensity, base.y * intensity, base.z),
                duration,
                0.0,
            ),
        )
    catch
    end
end

function camera_shake!(amount::Float64)
    ensure_camera_original!()
    JUICE.camera_trauma = min(1.0, JUICE.camera_trauma + amount)
end

function screen_flash!(
    color::NTuple{4, Int};
    intensity::Float64 = 0.35,
    duration::Float64 = 0.35,
)
    push!(JUICE.screen_flashes, ScreenFlashEffect(color, intensity, duration, 0.0))
end

function damage_number!(
    entity,
    value;
    crit::Bool = false,
    color::Union{Nothing, NTuple{4, Int}} = nothing,
)
    ActionResultDisplayModule.push(entity; kind = :damage, value = value, crit = crit, color = color)
end

function heal_number!(entity, value::Int; icon = nothing)
    ActionResultDisplayModule.push(entity; kind = :heal, value = value, icon = icon)
end

function hit_spark!(entity)
    entity === nothing && return
    push!(
        JUICE.floating_numbers,
        FloatingNumberEffect(
            "juice_hit_$(rand(1000:9999))",
            entity,
            "!",
            (255, 240, 200, 255),
            0.0,
            0.35,
            0.0,
        ),
    )
end

function dodge_step!(entity; direction::Float64 = -1.0)
    entity === nothing && return
    try
        # Brace owns transform.position every frame — clear it or the sidestep is invisible.
        clear_brace!(entity)
        existing = take_over_effect!(JUICE.dodges, entity)
        original_position = existing === nothing ? entity.transform.position : existing.original_position
        push!(
            JUICE.dodges,
            DodgeEffect(
                entity,
                original_position,
                direction,
                1.05,
                0.14,
                0.24,
                0.0,
            ),
        )
        flash!(entity; color = (255, 255, 255, 255), duration = 0.28)
        scale_pulse!(entity; intensity = 1.16, duration = 0.26)
        camera_shake!(0.22)
        play_dodge_sfx()
    catch
    end
end

function set_brace!(
    entity,
    threat_pos::Math.Vector2f;
    intensity::Float64 = 1.0,
)
    entity === nothing && return
    key = entity_id(entity)
    if !haskey(JUICE.braces, key)
        try
            # Take the true baseline from any in-flight effect that owns the
            # transform, so the brace doesn't capture a mid-effect value.
            base_scale = entity.transform.scale
            pulse_index = findfirst(e -> e.entity === entity, JUICE.scale_pulses)
            if pulse_index !== nothing
                base_scale = JUICE.scale_pulses[pulse_index].original_scale
            end
            base_position = entity.transform.position
            for effects in (JUICE.shakes, JUICE.knockbacks)
                index = findfirst(e -> e.entity === entity, effects)
                if index !== nothing
                    base_position = effects[index].original_position
                    break
                end
            end
            JUICE.braces[key] = BraceEffect(
                entity,
                base_scale,
                base_position,
                Math.Vector2f(0.0, 0.0),
                0.0,
            )
        catch
            return
        end
    end
    brace = JUICE.braces[key]
    dx = entity.transform.position.x - threat_pos.x
    dy = entity.transform.position.y - threat_pos.y
    len = sqrt(dx * dx + dy * dy)
    if len > 0.001
        brace.threat_direction = Math.Vector2f(dx / len, dy / len)
    end
    brace.intensity = clamp(intensity, 0.0, 1.0)
end

function clear_brace!(entity)
    entity === nothing && return
    key = entity_id(entity)
    brace = get(JUICE.braces, key, nothing)
    if brace === nothing
        return
    end
    try
        entity.transform.scale = brace.original_scale
        entity.transform.position = brace.original_position
    catch
    end
    delete!(JUICE.braces, key)
end

# Cancel every active effect on the entity, restoring recorded originals so a
# subsequent baseline read (e.g. by play_death!) sees the true resting state.
function cancel_entity_effects!(entity)
    entity === nothing && return
    flash = take_over_effect!(JUICE.flashes, entity)
    if flash !== nothing
        sprite = entity_sprite(entity)
        sprite !== nothing && (sprite.color = flash.original_color)
    end
    try
        moved = take_over_effect!(JUICE.shakes, entity)
        moved === nothing && (moved = take_over_effect!(JUICE.knockbacks, entity))
        moved === nothing && (moved = take_over_effect!(JUICE.dodges, entity))
        moved !== nothing && (entity.transform.position = moved.original_position)
        # Clear any remaining position effects too.
        take_over_effect!(JUICE.shakes, entity)
        take_over_effect!(JUICE.knockbacks, entity)
        take_over_effect!(JUICE.dodges, entity)

        pulse = take_over_effect!(JUICE.scale_pulses, entity)
        pulse !== nothing && (entity.transform.scale = pulse.original_scale)
    catch
    end
    clear_brace!(entity)
end

function play_death!(
    entity;
    style::Symbol = :squash_fade,
    on_complete::Union{Nothing, Function} = nothing,
)
    entity === nothing && return
    for death in JUICE.deaths
        if death.entity === entity
            return
        end
    end
    cancel_entity_effects!(entity)
    try
        sprite = entity_sprite(entity)
        original_color = sprite === nothing ? (255, 255, 255, 255) : sprite.color
        push!(
            JUICE.deaths,
            DeathEffect(
                entity,
                style,
                entity.transform.scale,
                entity.transform.position,
                original_color,
                style == :pop ? 0.55 : 0.75,
                0.0,
                on_complete,
            ),
        )
    catch e
        @debug "play_death! failed: $(e)"
        on_complete !== nothing && on_complete()
    end
end

function enemy_damage_feedback!(entity, damage::Int; crit::Bool = false, icon::String = "", source::String = "")
    flash!(entity; color = (255, 180, 180, 255), duration = crit ? 0.35 : 0.22)
    shake!(entity; intensity = crit ? 0.18 : 0.12)
    if isempty(icon)
        damage_number!(entity, damage; crit = crit)
    else
        ActionResultDisplayModule.push(entity; kind = :damage, value = damage, crit = crit, icon = icon)
    end
    src = isempty(source) ? (ActionResultDisplayModule.SOURCE.active ? ActionResultDisplayModule.SOURCE.piece_key : "hit") : source
    ActionResultDisplayModule.note_move_damage!(entity, damage, src)
end

function player_damage_feedback!(entity, damage::Int; crit::Bool = false)
    flash!(entity; color = (255, 80, 80, 255), duration = 0.3)
    shake!(entity; intensity = 0.15)
    screen_flash!((255, 40, 40, 120); intensity = 0.28, duration = 0.3)
    hitstop!(0.09)
    camera_shake!(0.35)
    damage_number!(entity, damage; crit = crit)
end

function player_hit_impact!(
    entity,
    enemy_pos::Math.Vector3f;
    shake_intensity::Float64 = 0.15,
)
    entity === nothing && return
    flash!(entity; color = (255, 80, 80, 255), duration = 0.28)
    shake!(entity; intensity = shake_intensity, duration = 0.3)
    screen_flash!((255, 40, 40, 120); intensity = 0.28, duration = 0.3)
    hitstop!(0.09)
    camera_shake!(0.35)
    dx = entity.transform.position.x - enemy_pos.x
    dy = entity.transform.position.y - enemy_pos.y
    knockback!(entity, Math.Vector2f(dx, dy); distance = 0.12, duration = 0.12)
end

function sword_impact!(entity, grid_center::Math.Vector2f)
    entity === nothing && return
    flash!(entity; color = (255, 210, 180, 255), duration = 0.18)
    dx = entity.transform.position.x - grid_center.x
    dy = entity.transform.position.y - grid_center.y
    knockback!(entity, Math.Vector2f(dx, dy); distance = 0.1, duration = 0.1)
    shake!(entity; intensity = 0.1, duration = 0.18)
    hitstop!(0.04)
    camera_shake!(0.22)
    hit_spark!(entity)
end

function shield_impact!(entity)
    entity === nothing && return
    flash!(entity; color = (150, 200, 255, 255), duration = 0.28)
    scale_pulse!(entity; intensity = 1.12, duration = 0.25)
end

const REFLECT_SHIELD_SIZE = 1.4
const REFLECT_SHIELD_TINT = (200, 150, 255)
# Above the player, below the reflected projectile (EnemyTurnAnimator PROJECTILE_LAYER = 20).
const REFLECT_SHIELD_LAYER = 19

"""Reflective Shield that pops up where an attack is reflected, then bursts outward."""
function reflect_shield!(center::Math.Vector3f; duration::Float64 = 0.6)
    try
        ent = JulGame.EntityModule.Entity("Reflect_Shield_VFX")
        ent.sprite = JulGame.SpriteModule.InternalSprite(
            ent,
            JulGame.UserGlobals["Module"].get_asset_path("piece", "reflectiveshield"),
            Math.Vector4(0, 0, 0, 0), false, (255, 255, 255, 255), false;
            pixelsPerUnit = 150, layer = REFLECT_SHIELD_LAYER,
        )
        ent = JulGame.create_entity(ent)
        half = REFLECT_SHIELD_SIZE / 2
        ent.transform.scale = Math.Vector2f(REFLECT_SHIELD_SIZE, REFLECT_SHIELD_SIZE)
        ent.transform.position = Math.Vector2f(center.x - half, center.y - half)
        ent.sprite.renderScale = Math.Vector2f(0.3, 0.3)
        push!(JUICE.reflect_shields, ReflectShieldEffect(ent, duration, 0.0))
    catch e
        @debug "reflect shield: $e"
    end
end

const SHOCK_ARC_DURATION = 0.55
const SHOCK_BOLT_LIFE = 0.07
const SHOCK_LAYER = 3
const LIGHTNING_FRAMES = 12

function resolve_juice_entity(target)
    target === nothing && return nothing
    try
        if isdefined(target, :sprite) && target.sprite !== nothing && isdefined(target, :transform)
            return target
        end
    catch
    end
    try
        parent = target.parent
        parent !== nothing && return parent
    catch
    end
    return nothing
end

function shock_orbit_radius(entity)::Float64
    try
        sprite = entity.sprite
        ppu = sprite.pixelsPerUnit > 0 ? Float64(sprite.pixelsPerUnit) : 64.0
        w = Float64(sprite.size.x) * Float64(entity.transform.scale.x) / ppu
        h = Float64(sprite.size.y) * Float64(entity.transform.scale.y) / ppu
        return clamp(max(w, h) * 0.30, 0.55, 1.45)
    catch
        return 1.35
    end
end

function destroy_shock_bolt!(bolt::ShockBolt)
    try
        JulGame.destroy_entity(MAIN, bolt.entity)
    catch
    end
end

function spawn_shock_bolt!(center, radius::Float64)::Union{Nothing, ShockBolt}
    frame = rand(1:LIGHTNING_FRAMES)
    angle = rand() * 2π
    r = radius * (0.72 + rand() * 0.22)
    ent = JulGame.EntityModule.Entity("Shock_Bolt")
    ent.sprite = JulGame.SpriteModule.InternalSprite(
        ent,
        JulGame.UserGlobals["Module"].get_asset_path("fx", "lightning$(frame)"),
        Math.Vector4(0, 0, 0, 0), false, (255, 255, 255, 255), false;
        pixelsPerUnit = 110, layer = SHOCK_LAYER,
        rotation = rad2deg(angle) + (rand() - 0.5) * 24,
    )
    ent = JulGame.create_entity(ent)
    ent.transform.position = Math.Vector2f(center.x + cos(angle) * r, center.y + sin(angle) * r)
    s = 1.15 + rand() * 0.4
    ent.sprite.renderScale = Math.Vector2f(s, s)
    return ShockBolt(ent, SHOCK_BOLT_LIFE)
end

"""Random lightning frames flashing around a target. Plays a random damagelightning clip."""
function shock_arc!(target)
    entity = resolve_juice_entity(target)
    entity === nothing && return
    for effect in JUICE.shock_arcs
        if effect.entity === entity && effect.elapsed < effect.duration
            effect.elapsed = min(effect.elapsed, 0.12)
            return
        end
    end
    color = nothing
    try
        color = entity.sprite.color
    catch
    end
    push!(JUICE.shock_arcs, ShockArcEffect(entity, SHOCK_ARC_DURATION, 0.0, 0.0, ShockBolt[], color))
    play_shock_sfx()
end

function play_shock_sfx()
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", "damagelightning$(rand(1:3))"),
            false, 0.9, 0, 1,
        )
    catch
    end
end

function shock_flash_target!(effect::ShockArcEffect)
    sprite = entity_sprite(effect.entity)
    sprite === nothing && return
    if effect.original_color === nothing
        effect.original_color = sprite.color
    end
    base = effect.original_color
    hot = mod(effect.elapsed, 0.1) < 0.06
    sprite.color = hot ? (255, 245, 40, base[4]) : base
end

"""Color the enemy body should use while a shock burst is playing. Nothing if this entity is not shocking."""
function shock_body_color(entity)
    entity === nothing && return nothing
    for effect in JUICE.shock_arcs
        effect.entity === entity || continue
        effect.elapsed >= effect.duration && continue
        base = effect.original_color === nothing ? (255, 255, 255, 255) : effect.original_color
        hot = mod(effect.elapsed, 0.1) < 0.06
        return hot ? (255, 245, 40, base[4]) : base
    end
    return nothing
end

function restore_shock_flash!(effect::ShockArcEffect)
    effect.original_color === nothing && return
    sprite = entity_sprite(effect.entity)
    sprite !== nothing && (sprite.color = effect.original_color)
    effect.original_color = nothing
end

function update_shock_arcs!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.shock_arcs)
        effect.elapsed += deltaTime
        effect.cooldown -= deltaTime
        alive = ShockBolt[]
        for bolt in effect.bolts
            bolt.life -= deltaTime
            if bolt.life > 0
                push!(alive, bolt)
            else
                destroy_shock_bolt!(bolt)
            end
        end
        effect.bolts = alive
        if effect.elapsed < effect.duration
            try
                shock_flash_target!(effect)
            catch
            end
        else
            restore_shock_flash!(effect)
        end
        if effect.elapsed < effect.duration && effect.cooldown <= 0
            try
                pos = effect.entity.transform.position
                radius = shock_orbit_radius(effect.entity)
                bolt = spawn_shock_bolt!(pos, radius)
                bolt !== nothing && push!(effect.bolts, bolt)
                if rand() < 0.45
                    extra = spawn_shock_bolt!(pos, radius)
                    extra !== nothing && push!(effect.bolts, extra)
                end
            catch
            end
            gap = 0.028 + rand() * 0.05
            rand() < 0.28 && (gap += 0.05)
            effect.cooldown = gap
        end
        if effect.elapsed >= effect.duration && isempty(effect.bolts)
            push!(completed, i)
        end
    end
    for i in reverse(completed)
        restore_shock_flash!(JUICE.shock_arcs[i])
        deleteat!(JUICE.shock_arcs, i)
    end
end

function heal_feedback!(entity, amount::Int; icon = nothing)
    play_heal_sfx(amount)
    flash!(entity; color = (150, 255, 170, 255), duration = 0.3)
    heal_number!(entity, amount; icon = icon)
end

function play_heal_sfx(amount::Int)
    amount <= 0 && return
    name = amount < 5 ? "healsmall" : "healbig"
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", name),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "heal sfx: $e"
    end
end

function play_dodge_sfx()
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", "piecedodge"),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "dodge sfx: $e"
    end
end

function shield_gain_feedback!(entity, amount::Int = 0)
    flash!(entity; color = (120, 180, 255, 255), duration = 0.3)
    scale_pulse!(entity; intensity = 1.1, duration = 0.22)
    amount > 0 && ActionResultDisplayModule.push(entity; kind = :shield, value = amount)
end

function status_arrow_icon(buff::Bool)::String
    try
        return JulGame.UserGlobals["Module"].get_asset_path("status", buff ? "arrowbuff" : "arrowdebuff")
    catch
        return ""
    end
end

function status_glyph(status::Symbol)::String
    try
        globals = JulGame.UserGlobals["Module"]
        status == :shock && return globals.get_asset_path("piece", "lightning")
        return globals.get_asset_path("status", string(status))
    catch
        return ""
    end
end

function status_chip_label(status_type, duration)
    d = try
        Int(duration)
    catch
        0
    end
    t = status_type isa Symbol ? status_type : Symbol(lowercase(string(status_type)))
    buff = t in (:dodge, :reflect, :lucky)
    arrow = status_arrow_icon(buff)
    color = t == :burn ? (255, 150, 50, 255) :
            t == :freeze ? (150, 200, 255, 255) :
            t == :poison ? (200, 100, 255, 255) :
            t == :vulnerable ? (200, 100, 255, 255) :
            t == :shock ? (255, 220, 80, 255) :
            (215, 210, 195, 255)
    # Known statuses are the icon, the arrow, and the stack count.
    if t in (:burn, :freeze, :poison, :vulnerable, :shock, :dodge, :reflect, :lucky)
        return ("$(d)", color, status_glyph(t), arrow)
    end
    return (string(status_type), color, arrow, "")
end

function status_flash!(entity, color::NTuple{4, Int})
    flash!(entity; color = color, duration = 0.35)
end

function victory_screen!()
    screen_flash!((255, 215, 80, 140); intensity = 0.45, duration = 0.55)
end

function defeat_screen!()
    screen_flash!((40, 20, 30, 180); intensity = 0.5, duration = 0.65)
end

function turn_transition_flash!()
    screen_flash!((100, 100, 255, 60); intensity = 0.2, duration = 0.4)
end

function enemy_turn_flash!()
    screen_flash!((200, 100, 100, 80); intensity = 0.15, duration = 0.3)
end

function update_flashes!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.flashes)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        sprite = entity_sprite(effect.entity)
        if sprite !== nothing
            t = sin(progress * π)
            r = Int(round(effect.original_color[1] * (1 - t) + effect.flash_color[1] * t))
            g = Int(round(effect.original_color[2] * (1 - t) + effect.flash_color[2] * t))
            b = Int(round(effect.original_color[3] * (1 - t) + effect.flash_color[3] * t))
            sprite.color = (r, g, b, effect.original_color[4])
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        effect = JUICE.flashes[i]
        sprite = entity_sprite(effect.entity)
        sprite !== nothing && (sprite.color = effect.original_color)
        deleteat!(JUICE.flashes, i)
    end
end

function update_shakes!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.shakes)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        intensity = effect.intensity * (1.0 - progress)
        dx, dy = effect.wobble ?
            (sin(progress * 20.0) * intensity, cos(progress * 17.0) * intensity) :
            ((rand() - 0.5) * 2.0 * intensity, (rand() - 0.5) * 2.0 * intensity)
        try
            effect.entity.transform.position = Math.Vector3f(
                effect.original_position.x + dx,
                effect.original_position.y + dy,
                effect.original_position.z,
            )
        catch
            push!(completed, i)
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        effect = JUICE.shakes[i]
        try
            effect.entity.transform.position = effect.original_position
        catch
        end
        deleteat!(JUICE.shakes, i)
    end
end

function update_knockbacks!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.knockbacks)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        eased = ease_out_cubic(progress)
        offset = effect.distance * (1.0 - eased)
        try
            effect.entity.transform.position = Math.Vector3f(
                effect.original_position.x + effect.direction.x * offset,
                effect.original_position.y + effect.direction.y * offset,
                effect.original_position.z,
            )
        catch
            push!(completed, i)
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        effect = JUICE.knockbacks[i]
        try
            effect.entity.transform.position = effect.original_position
        catch
        end
        deleteat!(JUICE.knockbacks, i)
    end
end

function update_scale_pulses!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.scale_pulses)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        t = sin(progress * π)
        try
            sx = effect.original_scale.x + (effect.target_scale.x - effect.original_scale.x) * t
            sy = effect.original_scale.y + (effect.target_scale.y - effect.original_scale.y) * t
            effect.entity.transform.scale = Math.Vector3f(sx, sy, effect.original_scale.z)
        catch
            push!(completed, i)
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        effect = JUICE.scale_pulses[i]
        try
            effect.entity.transform.scale = effect.original_scale
        catch
        end
        deleteat!(JUICE.scale_pulses, i)
    end
end

function update_dodges!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.dodges)
        effect.elapsed += deltaTime
        total = effect.out_duration + effect.return_duration
        progress = min(effect.elapsed / total, 1.0)
        try
            if effect.elapsed <= effect.out_duration
                t = ease_out_cubic(effect.elapsed / effect.out_duration)
                offset = effect.distance * t * effect.direction
                effect.entity.transform.position = Math.Vector3f(
                    effect.original_position.x + offset,
                    effect.original_position.y,
                    effect.original_position.z,
                )
            else
                t = ease_out_cubic((effect.elapsed - effect.out_duration) / effect.return_duration)
                offset = effect.distance * (1.0 - t) * effect.direction
                effect.entity.transform.position = Math.Vector3f(
                    effect.original_position.x + offset,
                    effect.original_position.y,
                    effect.original_position.z,
                )
            end
        catch
            push!(completed, i)
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        effect = JUICE.dodges[i]
        try
            effect.entity.transform.position = effect.original_position
        catch
        end
        deleteat!(JUICE.dodges, i)
    end
end

function update_reflect_shields!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.reflect_shields)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        r, g, b = REFLECT_SHIELD_TINT
        try
            if progress < 0.3
                # Pop in white-hot, cooling to the mirror tint
                t = progress / 0.3
                s = 0.3 + 0.7 * ease_out_back(t)
                color = (round(Int, 255 + (r - 255) * t), round(Int, 255 + (g - 255) * t), 255, 255)
            else
                # Burst outward while fading
                t = (progress - 0.3) / 0.7
                s = 1.0 + 0.35 * ease_out_cubic(t)
                color = (r, g, b, round(Int, 255 * (1.0 - t * t)))
            end
            effect.entity.sprite.renderScale = Math.Vector2f(s, s)
            effect.entity.sprite.color = color
        catch
            push!(completed, i)
            continue
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        try
            JulGame.destroy_entity(MAIN, JUICE.reflect_shields[i].entity)
        catch
        end
        deleteat!(JUICE.reflect_shields, i)
    end
end

function update_braces!()
    for (_, brace) in JUICE.braces
        # Active dodge/knockback/shake owns position — don't stomp the sidestep.
        if any(e -> e.entity === brace.entity, JUICE.dodges) ||
           any(e -> e.entity === brace.entity, JUICE.knockbacks) ||
           any(e -> e.entity === brace.entity, JUICE.shakes)
            continue
        end
        try
            lean = 0.06 * brace.intensity
            scale = 1.0 - 0.04 * brace.intensity
            brace.entity.transform.scale = Math.Vector3f(
                brace.original_scale.x * scale,
                brace.original_scale.y * scale,
                brace.original_scale.z,
            )
            brace.entity.transform.position = Math.Vector3f(
                brace.original_position.x + brace.threat_direction.x * lean,
                brace.original_position.y + brace.threat_direction.y * lean,
                brace.original_position.z,
            )
        catch
        end
    end
end

function update_deaths!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.deaths)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        sprite = entity_sprite(effect.entity)
        try
            if effect.style == :squash_fade
                if progress < 0.15
                    sprite !== nothing && (sprite.color = (255, 255, 255, 255))
                elseif progress < 0.45
                    t = (progress - 0.15) / 0.3
                    sy = effect.original_scale.y * (1.0 - 0.35 * ease_in_cubic(t))
                    sx = effect.original_scale.x * (1.0 + 0.15 * ease_in_cubic(t))
                    effect.entity.transform.scale = Math.Vector3f(sx, sy, effect.original_scale.z)
                else
                    t = (progress - 0.45) / 0.55
                    sink = 0.35 * ease_in_cubic(t)
                    alpha = Int(round(effect.original_color[4] * (1.0 - t)))
                    effect.entity.transform.position = Math.Vector3f(
                        effect.original_position.x,
                        effect.original_position.y - sink,
                        effect.original_position.z,
                    )
                    sprite !== nothing && (sprite.color = (
                        effect.original_color[1],
                        effect.original_color[2],
                        effect.original_color[3],
                        alpha,
                    ))
                end
            elseif effect.style == :pop
                if progress < 0.35
                    t = progress / 0.35
                    s = 1.0 + 0.35 * ease_out_back(t)
                    effect.entity.transform.scale = Math.Vector3f(
                        effect.original_scale.x * s,
                        effect.original_scale.y * s,
                        effect.original_scale.z,
                    )
                    sprite !== nothing && (sprite.color = (255, 255, 255, 255))
                else
                    t = (progress - 0.35) / 0.65
                    s = (1.35 - 0.85 * ease_in_cubic(t))
                    alpha = Int(round(effect.original_color[4] * (1.0 - t)))
                    effect.entity.transform.scale = Math.Vector3f(
                        effect.original_scale.x * s,
                        effect.original_scale.y * s,
                        effect.original_scale.z,
                    )
                    sprite !== nothing && (sprite.color = (
                        effect.original_color[1],
                        effect.original_color[2],
                        effect.original_color[3],
                        alpha,
                    ))
                end
            else
                flicker = progress < 0.8 ? (rand() > 0.35 ? 1.0 : 0.35) : (1.0 - progress) / 0.2
                alpha = Int(round(effect.original_color[4] * flicker))
                sprite !== nothing && (sprite.color = (
                    effect.original_color[1],
                    effect.original_color[2],
                    effect.original_color[3],
                    alpha,
                ))
            end
        catch
            push!(completed, i)
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        effect = JUICE.deaths[i]
        try
            effect.entity.isActive = false
            effect.entity.transform.scale = effect.original_scale
            effect.entity.transform.position = effect.original_position
            sprite = entity_sprite(effect.entity)
            sprite !== nothing && (sprite.color = effect.original_color)
        catch
        end
        if effect.on_complete !== nothing
            try
                effect.on_complete()
            catch e
                @debug "death on_complete error: $(e)"
            end
        end
        deleteat!(JUICE.deaths, i)
    end
end

function update_floating_numbers!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.floating_numbers)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        alpha = Int(round(effect.color[4] * (1.0 - progress)))
        offset_y = effect.start_offset_y - 28.0 * ease_out_cubic(progress)
        try
            DisplayTextModule.display_text(
                effect.id,
                effect.text;
                fontSize = occursin("heal", effect.id) ? 26 : 24,
                anchor = :center,
                anchorOffset = Math.Vector2(0, Int(round(offset_y))),
                lifetime = 50,
                color = (effect.color[1], effect.color[2], effect.color[3], alpha),
                parent = entity_sprite(effect.entity),
            )
        catch
            push!(completed, i)
        end
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        deleteat!(JUICE.floating_numbers, i)
    end
end

function update_screen_flashes!(deltaTime::Float64)
    completed = Int[]
    for (i, effect) in enumerate(JUICE.screen_flashes)
        effect.elapsed += deltaTime
        progress = min(effect.elapsed / effect.duration, 1.0)
        alpha = Int(floor(effect.color[4] * sin(progress * π) * effect.intensity))
        JulGame.ImmediateUIModule.immediate_rect(
            "juice_screen_flash_$(i)";
            size = Math.Vector2(1920, 1080),
            color = (effect.color[1], effect.color[2], effect.color[3], alpha),
            anchor = :center,
            layer = 999,
        )
        progress >= 1.0 && push!(completed, i)
    end
    for i in reverse(completed)
        deleteat!(JUICE.screen_flashes, i)
    end
end

function update_camera_shake!(deltaTime::Float64)
    ensure_camera_original!()
    original = JUICE.camera_original_pos
    if JUICE.camera_trauma <= 0.0
        if original !== nothing
            MAIN.scene.camera.position = original
        end
        return
    end
    if !Scripts.MainSettingsModule.is_screen_shake_enabled()
        JUICE.camera_trauma = 0.0
        if original !== nothing
            MAIN.scene.camera.position = original
        end
        return
    end
    shake = JUICE.camera_trauma^2
    offset = shake * 0.35
    MAIN.scene.camera.position = Math.Vector3f(
        original.x + (rand() - 0.5) * 2.0 * offset,
        original.y + (rand() - 0.5) * 2.0 * offset,
        original.z,
    )
    JUICE.camera_trauma = max(0.0, JUICE.camera_trauma - deltaTime * 1.8)
end

function update(deltaTime::Float64)
    if JUICE.hitstop_remaining > 0.0
        JUICE.hitstop_remaining = max(0.0, JUICE.hitstop_remaining - deltaTime)
    end

    juice_dt = scaled_delta(deltaTime)
    if juice_dt > 0.0
        update_flashes!(juice_dt)
        update_shakes!(juice_dt)
        update_knockbacks!(juice_dt)
        update_scale_pulses!(juice_dt)
        update_dodges!(juice_dt)
        update_reflect_shields!(juice_dt)
        update_shock_arcs!(juice_dt)
        update_braces!()
        update_deaths!(juice_dt)
        update_floating_numbers!(juice_dt)
        update_screen_flashes!(juice_dt)
        update_camera_shake!(juice_dt)
    end
    ActionResultDisplayModule.update(juice_dt)
end

function on_juice_event(event::Symbol, data::Any)
    try
        if event == :damage_dealt && data isa Dict && haskey(data, :target) && haskey(data, :damage)
            target = data[:target]
            crit = get(data, :is_critical, false)
            enemy_damage_feedback!(target, data[:damage]; crit = crit)
        elseif event == :healing_received && data isa Dict && haskey(data, :amount)
            entity = player_entity()
            entity !== nothing && heal_feedback!(entity, data[:amount]; icon = get(data, :icon, nothing))
        elseif event == :shield_gained && data isa Dict
            entity = player_entity()
            entity !== nothing && shield_gain_feedback!(entity, get(data, :amount, 0))
        elseif event == :status_applied && data isa Dict && haskey(data, :target)
            target = data[:target]
            label, color, icon, badge = status_chip_label(get(data, :status_type, :status), get(data, :duration, 0))
            try
                status_flash!(target, color)
            catch
            end
            ActionResultDisplayModule.push(target; kind = :status, value = label, color = color, icon = icon, badge = badge)
            status_type = get(data, :status_type, :status)
            status_sym = status_type isa Symbol ? status_type : Symbol(lowercase(string(status_type)))
            status_sym == :shock && shock_arc!(target)
            if status_sym != :shock
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
        elseif event == :victory
            victory_screen!()
        elseif event == :defeat
            defeat_screen!()
        end
    catch e
        @debug "BattleJuice event error ($(event)): $(e)"
    end
end

function initialize_juice_observer!()
    if JUICE.juice_observer_registered
        return
    end
    try
        globals = JulGame.UserGlobals["Module"]
        globals.ObserverModule.add_observer((event, data) -> on_juice_event(event, data))
        JUICE.juice_observer_registered = true
    catch e
        @debug "Failed to initialize juice observer: $(e)"
    end
end

function reset!()
    JUICE.hitstop_remaining = 0.0
    JUICE.slowmo_scale = 1.0
    JUICE.camera_trauma = 0.0
    empty!(JUICE.flashes)
    empty!(JUICE.shakes)
    empty!(JUICE.knockbacks)
    empty!(JUICE.scale_pulses)
    empty!(JUICE.dodges)
    empty!(JUICE.reflect_shields)
    for effect in JUICE.shock_arcs
        restore_shock_flash!(effect)
        for bolt in effect.bolts
            destroy_shock_bolt!(bolt)
        end
    end
    empty!(JUICE.shock_arcs)
    empty!(JUICE.braces)
    empty!(JUICE.deaths)
    empty!(JUICE.floating_numbers)
    empty!(JUICE.screen_flashes)
    if JUICE.camera_original_pos !== nothing
        MAIN.scene.camera.position = JUICE.camera_original_pos
    end
    ActionResultDisplayModule.reset!()
end

export time_scale, scaled_delta, hitstop!, set_slowmo!, flash!, shake!, cancel_shake!, knockback!, scale_pulse!
export camera_shake!, screen_flash!, damage_number!, heal_number!, hit_spark!, dodge_step!, reflect_shield!, shock_arc!, shock_body_color
export set_brace!, clear_brace!, play_death!, death_style_for_enemy, selected_enemy_entity
export enemy_damage_feedback!, player_damage_feedback!, player_hit_impact!, sword_impact!
export shield_impact!, heal_feedback!, shield_gain_feedback!, status_flash!, status_arrow_icon
export victory_screen!, defeat_screen!, turn_transition_flash!, enemy_turn_flash!
export update, initialize_juice_observer!, reset!, entity_id, sync_camera_origin!

end # module
