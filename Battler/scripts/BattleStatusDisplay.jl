module BattleStatusDisplayModule
using JulGame
include("utils/DisplayText.jl")
using .DisplayTextModule
using ..Scripts

const STATUS_MAPPINGS = Dict(
    "burn"       => (c) -> (val = c.burn,                              buff = false, tooltip = "Burn: Lose HP each turn"),
    "freeze"     => (c) -> (val = c.freeze,                            buff = false, tooltip = "Freeze: Enemies skip their turn; on you, lose a move"),
    "poison"     => (c) -> (val = c.poison,                            buff = false, tooltip = "Poison: Attacks deal 1 less damage per stack"),
    "vulnerable" => (c) -> (val = c.vulnerable,                        buff = false, tooltip = "Vulnerable: Take increased damage"),
    "weaken"     => (c) -> (val = c.weaken,                            buff = false, tooltip = "Weaken: Deal less damage with attacks"),
    "shock"      => (c) -> (val = c.shock,                             buff = false, tooltip = "Shock: Deal damage to other enemies each turn"),
    "dodge"      => (c) -> (val = Float64(shown_dodge_chance(c))/100.0, buff = true,  tooltip = "Dodge: Chance to avoid attacks"),
    "reflect"    => (c) -> (val = Float64(shown_reflect_chance(c))/100.0, buff = true, tooltip = "Reflect: Chance to reflect damage"),
    "lucky"      => (c) -> (val = Float64(c.luck)/100.0,               buff = true,  tooltip = "Lucky: Feeling lucky?"),
)

"""Player dodge includes the Shadow Cloak base; enemies show their raw dodge_chance."""
function shown_dodge_chance(c)::Int
    globals = JulGame.UserGlobals["Module"]
    c === globals.get_user_data() || return Int(c.dodge_chance)
    return globals.PiecesModule.player_dodge_chance(c)
end

"""Player reflect includes the Cursed Mirror base; enemies show their raw reflect_chance."""
function shown_reflect_chance(c)::Int
    globals = JulGame.UserGlobals["Module"]
    c === globals.get_user_data() || return Int(c.reflect_chance)
    return globals.PiecesModule.player_reflect_chance(c)
end

const ATTACK_STATUS_ICON = "piece-sword"
const SHOCK_STATUS_ICON = "piece-lightning"
const BATTLE_GAME_ENTITY_ID = "7a8aa3ba-17c8-4346-a606-361c29fbfeba"

# Rest and hover share a pivot on the player's right (not the feet).
# Packed sits on a tight right-side arc; hover spreads into a column in the gap
# between the player and the board, extra columns growing left over the player.
const PLAYER_ARC_CENTER = Math.Vector2(420.0, -510.0)
const PLAYER_PACKED_CENTER = PLAYER_ARC_CENTER
const PLAYER_ARC_START = Float64(π / 2)          # 6 o'clock
const PLAYER_ARC_SWEEP_MIN = Float64(-π / 5)     # ~36°
const PLAYER_ARC_SWEEP_MAX = Float64(-π / 2)     # 90° to 3 o'clock, not a full wrap
const PLAYER_PACKED_RADIUS_MIN = 28.0
const PLAYER_PACKED_RADIUS_MAX = 42.0
const ICON_SIZE       = 126.0
const PLAYER_FAN_SPACING = ICON_SIZE + 12.0
const PLAYER_FAN_ROWS    = 4  # fits between the treasure bar and the potion bar
const PACKED_SPACING  = ICON_SIZE * 0.5
const HOVER_BUFFER    = 24.0
const ANIMATION_DURATION = 0.3
const MAX_STATUSES_FOR_FULL_ARC = 4

# Enemy compact row still uses a downward-leaning arc under the heart
const ARC_START       = π
const ARC_SPAN_MAX    = -π
const ARC_SPAN_MIN    = -π / 2

# Per-enemy row under health heart (smaller than player HUD but readable)
const ENEMY_ICON_SIZE       = 78.0
const ENEMY_PACKED_SPACING  = ENEMY_ICON_SIZE * 0.48
const ENEMY_ARC_RADIUS_MIN  = 44.0
const ENEMY_ARC_RADIUS_MAX  = 110.0
const ENEMY_HOVER_BUFFER    = 24.0
const ENEMY_BUFF_ICON_W     = 32.0
const ENEMY_BUFF_ICON_H     = 34.0
const ENEMY_TEXT_FONT       = 22

mutable struct BattleStatusDisplay <: Script
    parent # reference to the entity this script is attached to

    # References
    combatant  # The combatant whose statuses to display
    gameManager
    tooltipManager
    arcCenter::Math.Vector2  # Screen-space anchor reference for status layout
    instanceId::String
    status_layout::Symbol  # :player (Game Manager entity) or :enemy_compact (enemy entity)
    registeredStatuses::Set{String}
    statusCards::Dict{String, Any}
    isHovered::Bool
    animationProgress::Float64
    targetProgress::Float64
    animationTime::Float64
    startProgress::Float64

    function BattleStatusDisplay(arcCenter::Math.Vector2 = PLAYER_PACKED_CENTER, instanceId::String = "default", status_layout::Symbol = :player)
        this = new()
        this.combatant = nothing
        this.tooltipManager = nothing
        this.arcCenter = arcCenter
        this.instanceId = instanceId
        this.status_layout = status_layout
        this.registeredStatuses = Set{String}()
        this.statusCards = Dict{String, Any}()
        this.isHovered = false
        this.animationProgress = 0.0
        this.targetProgress = 0.0
        this.animationTime = 0.0
        this.startProgress = 0.0
        return this
    end
end

function JulGame.initialize(this::BattleStatusDisplay)
    @debug("BattleStatusDisplay.initialize called")
    set_references(this)
end

function set_references(this::BattleStatusDisplay)
    if this.status_layout == :enemy_compact
        gameEntity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, BATTLE_GAME_ENTITY_ID)
        if gameEntity === nothing || isempty(gameEntity.scripts)
            @error "BattleStatusDisplay enemy mode: game entity missing"
            return
        end
        this.gameManager = gameEntity.scripts[1]
        this.tooltipManager = this.gameManager.tooltipManager
        this.combatant = this.parent.scripts[1]
    else
        this.gameManager = this.parent.scripts[1]
        this.tooltipManager = this.gameManager.tooltipManager
        this.combatant = this.gameManager.user
    end
end

function set_combatant(this::BattleStatusDisplay, combatant)
    this.combatant = combatant
end

function layout_sizes(this::BattleStatusDisplay)
    if this.status_layout == :enemy_compact
        return (
            icon = ENEMY_ICON_SIZE,
            packed_spacing = ENEMY_PACKED_SPACING,
            hover_buf = ENEMY_HOVER_BUFFER,
            r_min = ENEMY_ARC_RADIUS_MIN,
            r_max = ENEMY_ARC_RADIUS_MAX,
            buff_w = ENEMY_BUFF_ICON_W,
            buff_h = ENEMY_BUFF_ICON_H,
            text_fs = ENEMY_TEXT_FONT,
        )
    end
    return (
        icon = ICON_SIZE,
        packed_spacing = PACKED_SPACING,
        hover_buf = HOVER_BUFFER,
        buff_w = 40.0,
        buff_h = 44.0,
        text_fs = 24,
    )
end

function refresh_enemy_arc_center!(this::BattleStatusDisplay, icon_size::Float64)
    es = this.combatant
    cam = MAIN.scene.camera
    (cam === nothing || es === nothing) && return
    H = Float64(cam.size.y)
    hsl = es.healthHeart
    sx, sy, hw, hh = 0.0, 0.0, 48.0, 48.0
    if hsl !== nothing && hsl.sprite !== nothing &&
       hsl.sprite.lastRenderedScreenPosition !== nothing && hsl.sprite.lastRenderedScreenSize !== nothing
        pos = hsl.sprite.lastRenderedScreenPosition
        sz = hsl.sprite.lastRenderedScreenSize
        sx = Float64(pos.x)
        sy = Float64(pos.y)
        hw = Float64(sz.x)
        hh = Float64(sz.y)
    else
        # Fallback before first draw: same world→screen as world-space UI (top-left origin, y down).
        wx = Float64(es.heartPosition.x)
        wy = Float64(es.heartPosition.y)
        S = JulGame.pixels_per_world_unit(cam)
        sx = (wx - (Float64(cam.position.x) + Float64(cam.offset.x))) * S
        sy = (wy - (Float64(cam.position.y) + Float64(cam.offset.y))) * S
    end
    cx = sx + hw / 2
    cy_bottom = sy + hh + 6.0
    # :bottomLeft UI: position.y = H - icon_h + anchorOffset.y  →  anchorOffset.y = cy_bottom - H + icon_h
    this.arcCenter = Math.Vector2(Float32(cx), Float32(cy_bottom - H + icon_size))
end

function status_ui_hidden(this::BattleStatusDisplay)::Bool
    if this.status_layout == :enemy_compact
        return this.combatant !== nothing && this.combatant.health <= 0
    end
    gm = this.gameManager
    gm === nothing && return false
    bm = try
        gm.battleManager
    catch
        nothing
    end
    bm === nothing && return false
    return bm.isPlayerDead || bm.currentState == bm.battleStates[:battleEnd]
end

function hide_status_ui!(this::BattleStatusDisplay)
    if this.tooltipManager !== nothing
        for key in this.registeredStatuses
            Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(
                this.tooltipManager,
                "$(this.instanceId)_$(key)_status"
            )
        end
    end
    empty!(this.registeredStatuses)

    IUI = JulGame.ImmediateUIModule
    for key in collect(keys(this.statusCards))
        IUI.remove_immediate_component("$(this.instanceId)_$(key)_status")
        IUI.remove_immediate_component("$(this.instanceId)_$(key)_status_buff")
        IUI.remove_immediate_component("$(this.instanceId)_$(key)_status_text")
    end
    empty!(this.statusCards)
    this.isHovered = false
end

function JulGame.update(this::BattleStatusDisplay, deltaTime)
    if status_ui_hidden(this)
        hide_status_ui!(this)
        return
    end
    L = layout_sizes(this)
    if this.status_layout == :enemy_compact
        refresh_enemy_arc_center!(this, L.icon)
    end
    active = active_statuses(this)
    update_hover!(this, length(active), L)
    update_animation(this, deltaTime)
    show_active_statuses(this, active, L)
end

"""Statuses stay in the hovered fan whenever any are active."""
function update_hover!(this::BattleStatusDisplay, n::Int, L)
    this.isHovered = n > 0
end

function update_animation(this::BattleStatusDisplay, deltaTime::Float64)
    new_target = this.isHovered ? 1.0 : 0.0
    if abs(this.targetProgress - new_target) > 0.01
        this.startProgress = this.animationProgress
        this.targetProgress = new_target
        this.animationTime = 0.0
    end

    if abs(this.animationProgress - this.targetProgress) > 0.01
        this.animationTime += deltaTime
        t = min(this.animationTime / ANIMATION_DURATION, 1.0)
        eased = springy_ease(t)
        this.animationProgress = this.startProgress + (this.targetProgress - this.startProgress) * eased
    else
        this.animationProgress = this.targetProgress
    end
end

function springy_ease(t::Float64)::Float64
    if t >= 1.0
        return 1.0
    end
    k = 8.0
    ω = 15.0
    return 1.0 - exp(-k * t) * cos(ω * t)
end

function compute_arc_offset(i::Int, n::Int, arcCenter::Math.Vector2, r_min::Float64, r_max::Float64, span_min::Float64, span_max::Float64, max_full::Int)::Math.Vector2
    scale = n == 1 ? 0.0 : min((n - 1) / (max_full - 1), 1.0)
    radius = r_min + (r_max - r_min) * scale
    span = span_min + (span_max - span_min) * scale
    t = n == 1 ? 0.5 : (i - 1) / (n - 1)
    angle = ARC_START + t * span
    return Math.Vector2(
        arcCenter.x + radius * cos(angle),
        arcCenter.y + radius * sin(angle)
    )
end

function compute_packed_offset(i::Int, n::Int, arcCenter::Math.Vector2, icon_size::Float64, packed_spacing::Float64)::Math.Vector2
    total_width = icon_size + (n - 1) * packed_spacing
    start_x = arcCenter.x - total_width / 2.0
    x = start_x + (i - 1) * packed_spacing
    return Math.Vector2(x, arcCenter.y)
end

function player_arc_radius_and_sweep(n::Int, r_min::Float64, r_max::Float64)
    scale = n == 1 ? 0.0 : min((n - 1) / (MAX_STATUSES_FOR_FULL_ARC - 1), 1.0)
    radius = r_min + (r_max - r_min) * scale
    sweep = PLAYER_ARC_SWEEP_MIN + (PLAYER_ARC_SWEEP_MAX - PLAYER_ARC_SWEEP_MIN) * scale
    return radius, sweep
end

function player_slot_offset(i::Int, n::Int, arcCenter::Math.Vector2, radius::Float64, sweep::Float64)::Math.Vector2
    t = n == 1 ? 0.5 : (i - 1) / (n - 1)
    angle = PLAYER_ARC_START + t * sweep
    return Math.Vector2(
        arcCenter.x + radius * cos(angle),
        arcCenter.y + radius * sin(angle)
    )
end

"""Hovered player slot: bottom-up columns of PLAYER_FAN_ROWS, centered on the pivot."""
function player_fan_offset(i::Int, n::Int)::Math.Vector2
    rows = min(n, PLAYER_FAN_ROWS)
    col, row = divrem(i - 1, PLAYER_FAN_ROWS)
    return Math.Vector2(
        PLAYER_ARC_CENTER.x - col * PLAYER_FAN_SPACING,
        PLAYER_ARC_CENTER.y - (row - (rows - 1) / 2) * PLAYER_FAN_SPACING
    )
end

function status_slot_offsets(this::BattleStatusDisplay, i::Int, n::Int, L)
    if this.status_layout == :player
        packed_r, packed_s = player_arc_radius_and_sweep(n, PLAYER_PACKED_RADIUS_MIN, PLAYER_PACKED_RADIUS_MAX)
        packed = player_slot_offset(i, n, PLAYER_ARC_CENTER, packed_r, packed_s)
        return packed, player_fan_offset(i, n)
    end
    packed = compute_packed_offset(i, n, this.arcCenter, L.icon, L.packed_spacing)
    arc = compute_arc_offset(i, n, this.arcCenter, L.r_min, L.r_max, ARC_SPAN_MIN, ARC_SPAN_MAX, MAX_STATUSES_FOR_FULL_ARC)
    return packed, arc
end

function active_statuses(this::BattleStatusDisplay)
    this.combatant === nothing && return Any[]
    active = Any[(key, s) for (key, value) in STATUS_MAPPINGS for s in [value(this.combatant)] if s.val > 0]
    if this.status_layout == :player && this.combatant.attack > 1
        push!(active, (
            "attack",
            (val = this.combatant.attack, buff = true, tooltip = "Attack: Adds +$(this.combatant.attack) damage to attacks")
        ))
    end
    return active
end

function show_active_statuses(this::BattleStatusDisplay, active, L)
    if this.combatant === nothing || this.tooltipManager === nothing
        return
    end

    globals = JulGame.UserGlobals["Module"]
    active_keys = Set(key for (key, _) in active)

    for key in collect(keys(this.statusCards))
        if key ∉ active_keys
            if key in this.registeredStatuses
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(
                    this.tooltipManager,
                    "$(this.instanceId)_$(key)_status"
                )
                delete!(this.registeredStatuses, key)
            end
            delete!(this.statusCards, key)
        end
    end

    n = length(active)
    in_arc_state = this.animationProgress > 0.5

    for (i, (key, status)) in enumerate(active)
        packed_pos, arc_pos = status_slot_offsets(this, i, n, L)
        offset = Math.Vector2(
            packed_pos.x + (arc_pos.x - packed_pos.x) * this.animationProgress,
            packed_pos.y + (arc_pos.y - packed_pos.y) * this.animationProgress
        )
        iz = round(Int, L.icon)
        card = JulGame.ImmediateUIModule.immediate_image(
            "$(this.instanceId)_$(key)_status",
            status_icon_path(globals, key);
            anchor = :bottomLeft,
            anchorOffset = offset,
            size = Math.Vector2(iz, iz),
            layer = 99,
            color = (255, 255, 255, 255)
        )
        this.statusCards[key] = card

        if in_arc_state
            Scripts.TooltipManagerModule.register_tooltip_item(
                this.tooltipManager,
                card,
                status.tooltip
            )
            if key ∉ this.registeredStatuses
                push!(this.registeredStatuses, key)
            end
        else
            if key in this.registeredStatuses
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(
                    this.tooltipManager,
                    "$(this.instanceId)_$(key)_status"
                )
                delete!(this.registeredStatuses, key)
            end
        end

        icon = status.buff ? "arrowbuff" : "arrowdebuff"
        buff = JulGame.ImmediateUIModule.immediate_image(
            "$(this.instanceId)_$(key)_status_buff",
            globals.get_asset_path("status", icon);
            anchor = :bottomRight,
            anchorOffset = Math.Vector2(-10, 0),
            parent = card,
            size = Math.Vector2(round(Int, L.buff_w), round(Int, L.buff_h)),
            layer = 100,
            color = (255, 255, 255, 255)
        )
        # Both sit on top of the card; leaving them hit-testable would block the
        # card's tooltip wherever they overlap it.
        buff.ignoreInputEvents = true
        is_pct = key == "dodge" || key == "reflect" || key == "lucky"
        label = is_pct ? "$(Int(round(status.val * 100)))%" : "$(status.val)"
        text = DisplayTextModule.display_text(
            "$(this.instanceId)_$(key)_status_text",
            label;
            parent = buff,
            fontSize = L.text_fs,
            anchor = :centerBottom,
            anchorOffset = Math.Vector2(0, 10),
            lifetime = 1500,
            layer = 101,
            color = (255, 255, 0, 255)
        )
        text !== nothing && (text.ignoreInputEvents = true)
    end
end

function status_icon_path(globals, key::String)
    key == "attack" && return globals.get_asset_path(ATTACK_STATUS_ICON)
    key == "shock" && return globals.get_asset_path(SHOCK_STATUS_ICON)
    return globals.get_asset_path("status", key)
end

function JulGame.on_shutdown(this::BattleStatusDisplay)
    hide_status_ui!(this)
end

end
