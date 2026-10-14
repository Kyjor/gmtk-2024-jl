module AbilityDisplayModule
using JulGame
include("utils/DisplayText.jl")
using .DisplayTextModule
using JulGame.EffectsModule
using ..Scripts

mutable struct AbilityDisplay <: Script
    parent # reference to the entity this script is attached to

    # References
    abilityManager
    gameManager
    tooltipManager
    user
    arcCenter::Math.Vector2  # Position where the ability arc is centered (screen coords, bottomLeft anchor)
    instanceId::String  # Unique ID for this instance (for UI element names)
    registeredAbilities::Set{String}
    abilityCards::Dict{String, Any}
    hoverZone::Union{Nothing, Any}
    isHovered::Bool
    animationProgress::Float64
    targetProgress::Float64
    animationTime::Float64
    startProgress::Float64
    
    # Hover scale tracking (similar to MapManager)
    abilityScales::Dict{String, Float64}  # treasure_key -> current scale
    abilityTargetScales::Dict{String, Float64}  # treasure_key -> target scale
    hoveredAbility::Union{Nothing, String}  # Currently hovered ability key
    availabilityFlashPhase::Float64  # Time accumulator for ready-to-use pulse (excludes Hocus Pocus)
    hoverCloseTimer::Float64  # linger before collapsing when hit-test flickers

    function AbilityDisplay(arcCenter::Math.Vector2 = Math.Vector2(100, -550), instanceId::String = "player_abilities")
        this = new()
        this.abilityManager = nothing
        this.gameManager = nothing
        this.tooltipManager = nothing
        this.user = nothing
        this.arcCenter = arcCenter
        this.instanceId = instanceId
        this.registeredAbilities = Set{String}()
        this.abilityCards = Dict{String, Any}()
        this.hoverZone = nothing
        this.isHovered = false
        this.animationProgress = 0.0
        this.targetProgress = 0.0
        this.animationTime = 0.0
        this.startProgress = 0.0
        
        # Initialize hover scale tracking
        this.abilityScales = Dict{String, Float64}()
        this.abilityTargetScales = Dict{String, Float64}()
        this.hoveredAbility = nothing
        this.availabilityFlashPhase = 0.0
        this.hoverCloseTimer = 0.0
        return this
    end
end

function JulGame.initialize(this::AbilityDisplay)
    @debug("AbilityDisplay.initialize called")
    set_references(this)
end

function set_references(this::AbilityDisplay)
    globals = JulGame.UserGlobals["Module"]
    this.gameManager = this.parent.scripts[1]    # GameManager is script 1
    this.tooltipManager = this.gameManager.tooltipManager
    this.abilityManager = this.parent.scripts[17]  # AbilityManager is script 19
    this.user = globals.get_user_data()
    
    # Use fixed position similar to BattleStatusDisplay
    # Position is in screen coordinates with :bottomLeft anchor
    # BattleStatusDisplay uses (250, -350), we'll use (250, 250) for player side
    if this.arcCenter == Math.Vector2(0, 0)
        this.arcCenter = Math.Vector2(100, -550)  # Similar area to status display but on player side
    end
end

function JulGame.update(this::AbilityDisplay, deltaTime)
    this.availabilityFlashPhase += Float64(deltaTime)
    update_animation(this, deltaTime)
    update_ability_scale_animations(this, deltaTime)
    show_active_abilities(this)
    Scripts.SealedEnvelopeModule.update_fx!(deltaTime)
    handle_keyboard_shortcuts(this)
end

"""
Hit-test only marks the topmost UI element hovered. Icons/labels sit above the
invisible fan zone, so we also treat card hover + mouse-in-zone-bounds as open.
"""
function is_ability_fan_hovered(this::AbilityDisplay)::Bool
    if this.hoveredAbility !== nothing
        return true
    end
    if this.hoverZone !== nothing && this.hoverZone.isHovered
        return true
    end
    for card in values(this.abilityCards)
        if card !== nothing && card.isHovered
            return true
        end
    end
    # Covers gaps / READY-USING labels that steal hit-test from the zone
    zone = this.hoverZone
    if zone !== nothing && zone.position !== nothing && zone.size !== nothing
        mx = MAIN.input.mousePosition.x
        my = MAIN.input.mousePosition.y
        px, py = zone.position.x, zone.position.y
        sx, sy = zone.size.x, zone.size.y
        if mx >= px && mx <= px + sx && my >= py && my <= py + sy
            return true
        end
    end
    return false
end

function update_animation(this::AbilityDisplay, deltaTime::Float64)
    # Get number of active abilities
    active_abilities = get_active_ability_list(this)
    n = length(active_abilities)
    
    # If only one ability, skip arc animation - just keep it in packed position
    if n <= 1
        this.animationProgress = 0.0
        this.targetProgress = 0.0
        this.hoverCloseTimer = 0.0
        return
    end
    
    raw_hovered = is_ability_fan_hovered(this)
    if raw_hovered
        this.hoverCloseTimer = HOVER_CLOSE_DELAY
        this.isHovered = true
    else
        this.hoverCloseTimer = max(0.0, this.hoverCloseTimer - deltaTime)
        this.isHovered = this.hoverCloseTimer > 0.0
    end

    # Update target based on hover state
    new_target = this.isHovered ? 1.0 : 0.0
    if abs(this.targetProgress - new_target) > 0.01
        this.startProgress = this.animationProgress
        this.targetProgress = new_target
        this.animationTime = 0.0
    end

    # Update animation progress
    if abs(this.animationProgress - this.targetProgress) > 0.01
        this.animationTime += deltaTime
        t = min(this.animationTime / ANIMATION_DURATION, 1.0)
        eased = springy_ease(t)
        
        this.animationProgress = this.startProgress + (this.targetProgress - this.startProgress) * eased
    else
        this.animationProgress = this.targetProgress
    end
end

function handle_keyboard_shortcuts(this::AbilityDisplay)
    if this.abilityManager === nothing || this.user === nothing
        return
    end
    
    globals = JulGame.UserGlobals["Module"]
    
    # Get active abilities in order
    active_abilities = get_active_ability_list(this)
    
    # Check number keys 1-9 (just use the number as string)
    for i in 1:min(9, length(active_abilities))
        key_name = "$(i)"
        if JulGame.InputModule.get_button_pressed(key_name)
            treasure_key = active_abilities[i]
            globals = JulGame.UserGlobals["Module"]
            if treasure_key == globals.TreasuresModule.TREASURE_HOCUSPOCUS
                continue
            end
            activate_ability_by_key(this, treasure_key)
            break
        end
    end
end

function activate_ability_by_key(this::AbilityDisplay, treasure_key::String)
    if this.abilityManager === nothing
        return
    end
    
    globals = JulGame.UserGlobals["Module"]
    
    is_active = false
    if treasure_key == globals.TreasuresModule.TREASURE_DETONATOR
        is_active = this.abilityManager.isDetonatorSelectionMode
    elseif treasure_key == globals.TreasuresModule.TREASURE_NAIL
        is_active = this.abilityManager.isNailSelectionMode
    end
    
    if is_active
        if treasure_key == globals.TreasuresModule.TREASURE_DETONATOR
            Scripts.AbilityManagerModule.cancel_detonator_selection(this.abilityManager)
        elseif treasure_key == globals.TreasuresModule.TREASURE_NAIL
            Scripts.AbilityManagerModule.cancel_nail_selection(this.abilityManager)
        end
    else
        # Otherwise, activate it
        Scripts.AbilityManagerModule.activate_ability(this.abilityManager, treasure_key)
    end
end

const ARC_RADIUS_MAX  = 190.0
const ARC_RADIUS_MIN  = 95.0
# Hover arc in bottomLeft offset space (+x right, +y down on screen):
# player is the vertical diameter; icons fan the left semicircle
# from 6 o'clock (π/2, down) through 9 (π, left) to 12 (3π/2, up).
const ARC_START       = Float64(π / 2)
const ARC_SWEEP_MIN   = Float64(π / 3)    # 60° for few abilities
const ARC_SWEEP_MAX   = Float64(π)        # full left semicircle 6→12
const ARC_HOVER_SPREAD = 1.0
const ICON_SIZE       = 72.0
# Resting pose: same 6→12 path as hover, but tighter to the player
const PACKED_RADIUS_MAX = 62.0
const PACKED_RADIUS_MIN = 44.0
const HOVER_BUFFER    = 28.0
const STATUS_LABEL_PAD = 18.0  # room for READY/USING under icons
const SCREEN_MARGIN   = 8.0
const ANIMATION_DURATION = 0.3
const HOVER_CLOSE_DELAY = 0.12  # keep fan open briefly across icon/label hit-test gaps
const MAX_ABILITIES_FOR_FULL_ARC = 4
const AVAILABILITY_FLASH_HZ = 3.2

"""bottomLeft anchorOffset bounds so an icon of `icon_size` stays fully on camera."""
function bottom_left_screen_limits(icon_size::Float64)
    cam = MAIN.scene.camera
    W = cam === nothing ? 1280.0 : Float64(cam.size.x)
    H = cam === nothing ? 720.0 : Float64(cam.size.y)
    # screen_x = ox; screen_y = H - icon_size + oy
    min_ox = SCREEN_MARGIN
    max_ox = W - icon_size - SCREEN_MARGIN
    min_oy = SCREEN_MARGIN - H + icon_size          # top edge
    max_oy = -SCREEN_MARGIN                         # bottom edge
    return (min_ox, max_ox, min_oy, max_oy, W, H)
end

function clamp_bottom_left_offset(offset::Math.Vector2, icon_size::Float64)::Math.Vector2
    min_ox, max_ox, min_oy, max_oy, _, _ = bottom_left_screen_limits(icon_size)
    return Math.Vector2(
        clamp(offset.x, min_ox, max(min_ox, max_ox)),
        clamp(offset.y, min_oy, max(min_oy, max_oy))
    )
end

"""Largest radius that keeps the left semicircle (π/2 → 3π/2) on screen."""
function max_on_screen_radius(arcCenter::Math.Vector2, icon_size::Float64)::Float64
    min_ox, _, min_oy, max_oy, _, _ = bottom_left_screen_limits(icon_size)
    r_left = arcCenter.x - min_ox   # 9 o'clock: cx - r
    r_up = arcCenter.y - min_oy     # 12 o'clock: cy - r
    r_down = max_oy - arcCenter.y   # 6 o'clock: cy + r
    return max(0.0, min(ARC_RADIUS_MAX, r_left, r_up, r_down))
end

function springy_ease(t::Float64)::Float64
    if t >= 1.0
        return 1.0
    end
    k = 8.0
    ω = 15.0
    return 1.0 - exp(-k * t) * cos(ω * t)
end

"""
Update ability icon scale animations (similar to MapManager's node scale animations)
"""
function update_ability_scale_animations(this::AbilityDisplay, deltaTime::Float64)
    for (treasure_key, target_scale) in this.abilityTargetScales
        current_scale = get(this.abilityScales, treasure_key, 1.0)
        
        if abs(current_scale - target_scale) > 0.001
            # Determine lerp speed based on direction (same as MapManager)
            if target_scale > current_scale
                # Hovering: instant increase (fast)
                lerp_speed = 20.0 * deltaTime
            else
                # Unhovering: slow decrease with easing (smooth)
                lerp_speed = 2.5 * deltaTime
            end
            
            # Apply lerp with easing for unhover (ease-out cubic)
            diff = target_scale - current_scale
            if target_scale < current_scale
                # Ease-out cubic for smooth unhover
                t = min(lerp_speed, 1.0)
                eased_t = 1.0 - (1.0 - t)^3
                new_scale = current_scale + diff * eased_t
            else
                # Linear for instant hover
                new_scale = current_scale + diff * min(lerp_speed, 1.0)
            end
            
            this.abilityScales[treasure_key] = new_scale
        else
            # Snap to target if very close
            this.abilityScales[treasure_key] = target_scale
        end
    end
end

function ability_arc_radius_and_sweep(n::Int, r_min::Float64, r_max::Float64, arcCenter::Math.Vector2)
    scale = n == 1 ? 0.0 : min((n - 1) / (MAX_ABILITIES_FOR_FULL_ARC - 1), 1.0)
    r_cap = max_on_screen_radius(arcCenter, ICON_SIZE)
    r_hi = min(r_max, r_cap)
    r_lo = min(r_min, r_hi)
    radius = r_lo + (r_hi - r_lo) * scale
    sweep = ARC_SWEEP_MIN + (ARC_SWEEP_MAX - ARC_SWEEP_MIN) * scale
    return radius, sweep
end

function ability_slot_offset(i::Int, n::Int, arcCenter::Math.Vector2, radius::Float64, sweep::Float64)::Math.Vector2
    t = n == 1 ? 0.5 : (i - 1) / (n - 1)
    angle = ARC_START + t * sweep
    return clamp_bottom_left_offset(
        Math.Vector2(
            arcCenter.x + radius * cos(angle),
            arcCenter.y + radius * sin(angle)
        ),
        ICON_SIZE
    )
end

function compute_arc_offset(i::Int, n::Int, arcCenter::Math.Vector2)::Math.Vector2
    radius, sweep = ability_arc_radius_and_sweep(n, ARC_RADIUS_MIN, ARC_RADIUS_MAX, arcCenter)
    return ability_slot_offset(i, n, arcCenter, radius, sweep)
end

function compute_packed_offset(i::Int, n::Int, arcCenter::Math.Vector2)::Math.Vector2
    # Rest along the same 6→12 arc so the cluster feels natural, not a flat stack
    radius, sweep = ability_arc_radius_and_sweep(n, PACKED_RADIUS_MIN, PACKED_RADIUS_MAX, arcCenter)
    return ability_slot_offset(i, n, arcCenter, radius, sweep)
end

function get_active_ability_list(this::AbilityDisplay)
    if this.user === nothing
        return []
    end
    
    globals = JulGame.UserGlobals["Module"]
    active_abilities = []
    
    # Check for Active-type treasures
    for treasure_key in [globals.TreasuresModule.TREASURE_HOCUSPOCUS, 
                          globals.TreasuresModule.TREASURE_DETONATOR,
                          globals.TreasuresModule.TREASURE_NAIL,
                          globals.TreasuresModule.TREASURE_CHESSBOARD,
                          globals.TreasuresModule.TREASURE_SEALEDENVELOPE]
        if globals.UserModule.has_treasure(treasure_key)
            push!(active_abilities, treasure_key)
        end
    end
    
    return active_abilities
end

function show_active_abilities(this::AbilityDisplay)
    if this.user === nothing || this.abilityManager === nothing
        return
    end
    
    globals = JulGame.UserGlobals["Module"]
    
    # Get list of active abilities
    active_abilities = get_active_ability_list(this)
    active_keys = Set(active_abilities)
    
    # Clean up cards and tooltips for abilities that are no longer active
    for key in collect(keys(this.abilityCards))
        if key ∉ active_keys
            if key in this.registeredAbilities
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(
                    this.tooltipManager,
                    "$(this.instanceId)_$(key)_ability"
                )
                delete!(this.registeredAbilities, key)
            end
            delete!(this.abilityCards, key)
            # Clean up scale tracking
            delete!(this.abilityScales, key)
            delete!(this.abilityTargetScales, key)
            if this.hoveredAbility == key
                this.hoveredAbility = nothing
            end
        end
    end
    
    n = length(active_abilities)
    in_arc_state = this.animationProgress > 0.5
    
    # Create/update single hover zone that covers entire ability area
    if n > 0
        min_ox = Inf
        max_ox = -Inf
        min_oy = Inf
        max_oy = -Inf
        
        for i in 1:n
            packed = compute_packed_offset(i, n, this.arcCenter)
            arc = compute_arc_offset(i, n, this.arcCenter)
            
            min_ox = min(min_ox, packed.x, arc.x)
            max_ox = max(max_ox, packed.x, arc.x)
            min_oy = min(min_oy, packed.y, arc.y)
            max_oy = max(max_oy, packed.y, arc.y)
        end
        
        zone_ox = min_ox - HOVER_BUFFER
        zone_oy = max_oy + HOVER_BUFFER + STATUS_LABEL_PAD
        zone_w = max_ox - min_ox + ICON_SIZE + 2 * HOVER_BUFFER
        zone_h = max_oy - min_oy + ICON_SIZE + 2 * HOVER_BUFFER + STATUS_LABEL_PAD
        
        this.hoverZone = JulGame.ImmediateUIModule.immediate_rect(
            "$(this.instanceId)_ability_display_hoverzone";
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(zone_ox, zone_oy),
            size = Math.Vector2(zone_w, zone_h),
            layer = 97,  # below icons/labels so clicks still hit cards
            lifetime = 1500,
            color = (0, 0, 0, 0),  # Invisible
            forceClickCheck = true
        )
    end
    
    # Render each active ability with interpolated positions
    for (i, treasure_key) in enumerate(active_abilities)
        packed_pos = compute_packed_offset(i, n, this.arcCenter)
        arc_pos = compute_arc_offset(i, n, this.arcCenter)
        
        # Interpolate between packed and arc positions
        spread_t = this.animationProgress * ARC_HOVER_SPREAD
        offset = Math.Vector2(
            packed_pos.x + (arc_pos.x - packed_pos.x) * spread_t,
            packed_pos.y + (arc_pos.y - packed_pos.y) * spread_t
        )
        
        # Get treasure info
        treasure = globals.TreasuresModule.ALL_TREASURES[treasure_key]
        treasure_name = lowercase(split(treasure.key, "_")[2])
        icon_path = globals.get_asset_path("treasure", treasure_name)
        
        # Check if ability can be used
        can_use = Scripts.AbilityManagerModule.can_use_ability(this.abilityManager, treasure_key)
        is_envelope = treasure_key == globals.TreasuresModule.TREASURE_SEALEDENVELOPE
        uses_remaining = if treasure_key == globals.TreasuresModule.TREASURE_CHESSBOARD
            this.abilityManager.chessboardCooldown
        elseif is_envelope
            Scripts.SealedEnvelopeModule.stored_count()
        else
            this.abilityManager.maxAbilityUsesPerTurn[treasure.key] -
                get(this.abilityManager.abilityUsesThisTurn, treasure.key, 0)
        end
        
        # Special case: Hocus Pocus is always available and has unlimited uses
        if treasure_key == globals.TreasuresModule.TREASURE_HOCUSPOCUS
            can_use = true
            uses_remaining = -1  # Sentinel for "infinite"
        elseif treasure_key == globals.TreasuresModule.TREASURE_NAIL
            # Allow opening nail mode to remove/move even with 0 uses left.
            can_use = Scripts.AbilityManagerModule.can_activate_nail(this.abilityManager)
        end
        
        # Selection mode only for detonator/nail — Hocus is passive
        is_active = false
        if treasure_key == globals.TreasuresModule.TREASURE_DETONATOR
            is_active = this.abilityManager.isDetonatorSelectionMode
        elseif treasure_key == globals.TreasuresModule.TREASURE_NAIL
            is_active = this.abilityManager.isNailSelectionMode
        elseif is_envelope
            is_active = Scripts.SealedEnvelopeModule.is_capturing()
        end
        is_ready = can_use && !is_active &&
                   treasure_key != globals.TreasuresModule.TREASURE_HOCUSPOCUS
        pulse = 0.5 + 0.5 * sin(this.availabilityFlashPhase * 2π * AVAILABILITY_FLASH_HZ)

        if is_active
            icon_color = (255, 235, 120, 255)
        elseif is_ready
            # Lime pulse — much stronger than a white brightness flicker
            icon_color = (
                Int(round(170 + 70 * pulse)),
                Int(round(230 + 25 * pulse)),
                Int(round(110 + 40 * pulse)),
                255,
            )
        elseif can_use
            icon_color = (255, 255, 255, 255)
        else
            icon_color = (150, 150, 150, 200)
        end
        
        # Get current scale for this ability (default to 1.0)
        current_scale = get(this.abilityScales, treasure.key, 1.0)
        scaled_size = ICON_SIZE * current_scale
        offset = clamp_bottom_left_offset(offset, scaled_size)
        card_rotation = 0.0
        if is_envelope
            _, _, _, _, _, screen_h = bottom_left_screen_limits(scaled_size)
            Scripts.SealedEnvelopeModule.set_target!(offset.x + scaled_size / 2, screen_h - scaled_size / 2 + offset.y)
            shake_x, card_rotation = Scripts.SealedEnvelopeModule.shake_offset()
            offset = Math.Vector2(offset.x + shake_x, offset.y)
        end
        
        # Initialize scale tracking if not present
        if !haskey(this.abilityScales, treasure.key)
            this.abilityScales[treasure.key] = 1.0
            this.abilityTargetScales[treasure.key] = 1.0
        end
        idle_scale = is_active ? 1.12 : 1.0
        if this.hoveredAbility != treasure.key
            this.abilityTargetScales[treasure.key] = idle_scale
        end
        
        # Create clickable image for ability (like CharacterSelection.jl - use image so effects work)
        click_handler = () -> begin
            if is_active
                if treasure_key == globals.TreasuresModule.TREASURE_DETONATOR
                    Scripts.AbilityManagerModule.cancel_detonator_selection(this.abilityManager)
                elseif treasure_key == globals.TreasuresModule.TREASURE_NAIL
                    Scripts.AbilityManagerModule.cancel_nail_selection(this.abilityManager)
                end
            elseif can_use
                Scripts.AbilityManagerModule.activate_ability(this.abilityManager, treasure_key)
            else
                # Show error text
                DisplayTextModule.display_text(
                    "ability_error_$(treasure.key)",
                    "Cannot use $(treasure.en_name) - $(treasure_key == globals.TreasuresModule.TREASURE_CHESSBOARD ? "Recharging" : uses_remaining == 0 ? "No uses remaining" : "Already in use")";
                    fontSize = 18,
                    anchor = :center,
                    lifetime = 2000,
                    color = (255, 80, 80, 255),
                    position = Math.Vector2(640, 200)
                )
            end
        end
        
        card = JulGame.ImmediateUIModule.immediate_image(
            "$(this.instanceId)_$(treasure.key)_ability",
            icon_path;
            anchor = :bottomLeft,
            anchorOffset = offset,
            size = Math.Vector2(scaled_size, scaled_size),
            clickEvents = Function[click_handler],
            layer = 99,
            lifetime = 1500,
            color = icon_color,
            rotation = card_rotation
        )

        # Clear status chrome: frame + label (tint alone is too easy to miss)
        ring_pad = 7.0
        ring_size = Int(round(scaled_size + 2 * ring_pad))
        if is_active
            JulGame.ImmediateUIModule.immediate_rect(
                "$(this.instanceId)_$(treasure.key)_status_ring";
                parent = card,
                anchor = :center,
                size = Math.Vector2(ring_size, ring_size),
                layer = 98,
                lifetime = 1500,
                color = (255, 210, 60, 55),
                borderWidth = 3,
                borderColor = (255, 230, 90, 255),
                borderRadius = 8,
                fillMode = true
            )
            DisplayTextModule.display_text(
                "$(this.instanceId)_$(treasure.key)_status_label",
                is_envelope ? "STORING" : "USING";
                parent = card,
                fontSize = 12,
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(0, -2),
                lifetime = 1500,
                layer = 102,
                color = (255, 235, 110, 255)
            )
        elseif is_ready
            ready_a = Int(round(150 + 105 * pulse))
            JulGame.ImmediateUIModule.immediate_rect(
                "$(this.instanceId)_$(treasure.key)_status_ring";
                parent = card,
                anchor = :center,
                size = Math.Vector2(ring_size, ring_size),
                layer = 98,
                lifetime = 1500,
                color = (80, 220, 120, Int(round(25 + 35 * pulse))),
                borderWidth = 3,
                borderColor = (120, 255, 150, ready_a),
                borderRadius = 8,
                fillMode = true
            )
            DisplayTextModule.display_text(
                "$(this.instanceId)_$(treasure.key)_status_label",
                "READY";
                parent = card,
                fontSize = 12,
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(0, -2),
                lifetime = 1500,
                layer = 102,
                color = (140, 255, 170, ready_a)
            )
        end
        
        # Set up hover events for scale animation
        push!(card.hoverEnterEvents, () -> begin
            this.hoveredAbility = treasure.key
            this.abilityTargetScales[treasure.key] = is_active ? 1.18 : 1.08
        end)
        push!(card.hoverExitEvents, () -> begin
            if this.hoveredAbility == treasure.key
                this.hoveredAbility = nothing
            end
            this.abilityTargetScales[treasure.key] = idle_scale
        end)
        
        # Store card reference
        this.abilityCards[treasure.key] = card
        
        # Register tooltips when in arc state
        if in_arc_state
            if is_envelope
                Scripts.TooltipManagerModule.register_tooltip_item(
                    this.tooltipManager,
                    card,
                    Scripts.SealedEnvelopeModule.tooltip_text("$(treasure.en_name): $(treasure.en_desc)")
                )
                push!(this.registeredAbilities, treasure.key)
            elseif treasure.key ∉ this.registeredAbilities
                tooltip_text = "$(treasure.en_name): $(treasure.en_desc)"
                Scripts.TooltipManagerModule.register_tooltip_item(
                    this.tooltipManager,
                    card,
                    tooltip_text
                )
                push!(this.registeredAbilities, treasure.key)
            end
        else
            if treasure.key in this.registeredAbilities
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(
                    this.tooltipManager,
                    "$(this.instanceId)_$(treasure.key)_ability"
                )
                delete!(this.registeredAbilities, treasure.key)
            end
        end
        
        # Add uses remaining overlay
        # For Hocus Pocus (uses_remaining < 0), show infinity symbol
        uses_label = ""
        if uses_remaining < 0
            uses_label = "∞"
        elseif uses_remaining > 0
            uses_label = string(uses_remaining)
        end
        
        if uses_label != ""
            DisplayTextModule.display_text(
                "$(this.instanceId)_$(treasure.key)_uses",
                uses_label;
                parent = card,
                fontSize = 16,
                anchor = :topRight,
                anchorOffset = Math.Vector2(-5, -5),
                lifetime = 1500,
                layer = 101,
                color = (220, 220, 220, 255)
            )
        end
        
        # Add keyboard shortcut indicator (small number in bottom left)
        shortcut_num = i
        # shortcut_text = DisplayTextModule.display_text(
        #     "$(this.instanceId)_$(treasure.key)_shortcut",
        #     "$shortcut_num";
        #     parent = card,
        #     fontSize = 14,
        #     anchor = :bottomLeft,
        #     anchorOffset = Math.Vector2(5, 5),
        #     lifetime = 1500,
        #     layer = 101,
        #     color = (200, 200, 200, 255)
        # )
    end
end

function JulGame.on_shutdown(this::AbilityDisplay)
    # Clean up if needed
end

export AbilityDisplay

end
