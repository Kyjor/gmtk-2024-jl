module PotionTooltipModule
using JulGame
using JulGame.EffectsModule
using ..Scripts
include("utils/PotionsConstants.jl")

# Hover glow effect for potion slots
const STYLE_POTION_HOVER = [
    OuterGlowEffect(
        radius=15,
        color=(200,220,255,200),
        fade_amount=1.8,
        fade_curve=15.5,
        force_white=true
    )
]

# Scene name -> potion Type context that allows "Use" there
const USE_CONTEXT_BY_SCENE = Dict("battle" => "Combat", "map" => "Map", "event" => "Event")

"""
Manager for displaying tooltips, hover effects, and context menus
for potion slots in battle, map and event scenes.
"""
mutable struct PotionTooltip
    parent
    tooltipManager
    user
    
    # Potion slot UI elements
    potionSlots::Vector
    registeredSlots::Dict  # Maps slot entity -> potion index
    lastPotionCount::Int
    hoveredSlots::Set{Int}  # Track which slots are currently hovered
    effectsApplied::Bool  # Whether glow effects have been applied to current sprites
    
    # Scale animation for hover enlarging
    slotScales::Dict{Int, Float64}        # slot index -> current scale
    slotTargetScales::Dict{Int, Float64}  # slot index -> target scale
    slotBasePositions::Dict{Int, Any}     # slot index -> base UI position
    slotBaseSizes::Dict{Int, Any}         # slot index -> base UI size
    
    # Flash animation for hover highlighting
    slotFlashTime::Dict{Int, Float64}     # slot index -> flash time accumulator
    slotIsFlashing::Dict{Int, Bool}       # slot index -> is currently flashing
    
    # Context menu
    contextMenuManager
    useContext::String  # "Combat", "Map" or "Event"
    
    # Battle references (for checking player turn & using potions)
    battleManager
    battlePotionManager
    gameManager
    
    function PotionTooltip()
        this = new()
        this.tooltipManager = nothing
        this.user = nothing
        this.potionSlots = []
        this.registeredSlots = Dict()
        this.lastPotionCount = -1
        this.hoveredSlots = Set{Int}()
        this.effectsApplied = false
        this.slotScales = Dict{Int, Float64}()
        this.slotTargetScales = Dict{Int, Float64}()
        this.slotBasePositions = Dict{Int, Any}()
        this.slotBaseSizes = Dict{Int, Any}()
        this.slotFlashTime = Dict{Int, Float64}()
        this.slotIsFlashing = Dict{Int, Bool}()
        this.contextMenuManager = Scripts.ContextMenuModule.ContextMenuManager()
        this.useContext = ""
        this.battleManager = nothing
        this.battlePotionManager = nothing
        this.gameManager = nothing
        return this
    end
end

function JulGame.initialize(this::PotionTooltip)
    # Get user data
    globals = JulGame.UserGlobals["Module"]
    this.user = globals.get_user_data()
    this.useContext = get(USE_CONTEXT_BY_SCENE, MAIN.scene.name, "")
    
    # Get GameManager entity which holds tooltip manager, battle manager, etc.
    gameEntity = this.useContext == "Combat" ? JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba") : nothing
    if gameEntity !== nothing && length(gameEntity.scripts) > 0
        this.gameManager = gameEntity.scripts[1]
        if this.gameManager !== nothing && isdefined(this.gameManager, :tooltipManager)
            this.tooltipManager = this.gameManager.tooltipManager
        end
        # BattleManager is script 4, BattlePotionManager is script 9
        if length(gameEntity.scripts) >= 4
            this.battleManager = gameEntity.scripts[4]
        end
        if length(gameEntity.scripts) >= 9
            this.battlePotionManager = gameEntity.scripts[9]
        end
    end
    
    # Get potion slot UI elements by ID
    slot_ids = [
        "ui_potion_slot_1",
        "ui_potion_slot_2",
        "ui_potion_slot_3",
        "ui_potion_slot_4",
    ]
    
    for (idx, id) in enumerate(slot_ids)
        el = JulGame.SceneModule.get_ui_element_by_id(id)
        if el !== nothing
            push!(this.potionSlots, el)
            this.slotScales[idx] = 1.0
            this.slotTargetScales[idx] = 1.0
            this.slotFlashTime[idx] = 0.0
            this.slotIsFlashing[idx] = false
            this.slotBasePositions[idx] = Math.Vector2(el.position.x, el.position.y)
            this.slotBaseSizes[idx] = Math.Vector2(el.size.x, el.size.y)
        end
    end
end

function JulGame.on_shutdown(this::PotionTooltip)
    # Clean up all registered tooltips
    if this.tooltipManager !== nothing
        for slotEntity in keys(this.registeredSlots)
            Scripts.TooltipManagerModule.deregister_tooltip_item(this.tooltipManager, slotEntity)
        end
    end
    empty!(this.registeredSlots)
    
    # Close context menu if open
    if this.contextMenuManager.isOpen
        Scripts.ContextMenuModule.close_context_menu(this.contextMenuManager)
    end
    
    # Disable any active glow effects, reset scales and colors
    for (i, slot) in enumerate(this.potionSlots)
        if hasproperty(slot, :useEffectTexture)
            slot.useEffectTexture = false
        end
        if hasproperty(slot, :color)
            slot.color = (255, 255, 255, 255)
        end
        if haskey(this.slotBaseSizes, i)
            slot.size = this.slotBaseSizes[i]
        end
        if haskey(this.slotBasePositions, i)
            slot.position = this.slotBasePositions[i]
        end
    end
    empty!(this.hoveredSlots)
    empty!(this.slotScales)
    empty!(this.slotTargetScales)
    empty!(this.slotBasePositions)
    empty!(this.slotBaseSizes)
    empty!(this.slotFlashTime)
    empty!(this.slotIsFlashing)
end

"""
Update tooltip registrations and glow effects when potions change.
Re-applies effects so the glow texture matches the current sprite image.
"""
function update_potion_tooltips(this::PotionTooltip)
    if this.tooltipManager === nothing || this.user === nothing
        return
    end
    
    potionCount = length(this.user.potions)
    
    # Deregister all existing tooltips first
    for slotEntity in keys(this.registeredSlots)
        Scripts.TooltipManagerModule.deregister_tooltip_item(this.tooltipManager, slotEntity)
    end
    empty!(this.registeredSlots)
    
    # Register tooltips and re-apply glow effects for active potion slots
    maxPotions = min(4, potionCount)
    for i in 1:length(this.potionSlots)
        slot = this.potionSlots[i]
        if i <= maxPotions
            potion = this.user.potions[i]
            tooltipText = "$(potion.en_name): $(potion.en_desc)"
            
            Scripts.TooltipManagerModule.register_tooltip_item(
                this.tooltipManager,
                slot,
                tooltipText
            )
            this.registeredSlots[slot] = i
            
            # Re-apply glow effect so it matches the current sprite image
            JulGame.apply_effects!(slot, STYLE_POTION_HOVER)
            if hasproperty(slot, :useEffectTexture)
                slot.useEffectTexture = false
            end
        else
            # Inactive slot — ensure glow is off and color reset
            if hasproperty(slot, :useEffectTexture)
                slot.useEffectTexture = false
            end
            if hasproperty(slot, :color)
                slot.color = (255, 255, 255, 255)
            end
        end
        # Reset flash state
        this.slotIsFlashing[i] = false
        this.slotFlashTime[i] = 0.0
    end
    
    empty!(this.hoveredSlots)
    this.lastPotionCount = potionCount
    this.effectsApplied = potionCount > 0
end

"""
Update function called every frame to detect potion changes, hover effects, and context menu.
"""
function JulGame.update(this::PotionTooltip, deltaTime)
    if this.user === nothing
        return
    end
    
    potionCount = length(this.user.potions)
    
    # Detect potion count change (including initial setup after PotionDisplayManager sets sprites)
    if potionCount != this.lastPotionCount
        update_potion_tooltips(this)
    end
    
    # Update context menu each frame
    Scripts.ContextMenuModule.update_context_menu(this.contextMenuManager)
    
    # Update hover glow, scale targets, and flash for active potion slots
    maxPotions = min(4, potionCount)
    for i in 1:length(this.potionSlots)
        slot = this.potionSlots[i]
        if i <= maxPotions && slot.isActive
            if slot.isHovered
                if !(i in this.hoveredSlots)
                    # Hover enter
                    if hasproperty(slot, :useEffectTexture)
                        slot.useEffectTexture = true
                    end
                    push!(this.hoveredSlots, i)
                    this.slotTargetScales[i] = 1.15
                    this.slotIsFlashing[i] = true
                    this.slotFlashTime[i] = 0.0
                    play_potion_hover_sfx()
                end
                
                # Handle left-click to open context menu
                if JulGame.InputModule.get_mouse_button_pressed(1) && !this.contextMenuManager.isOpen && !Scripts.TutorialModule.blocks_side_actions() &&
                   !(this.battlePotionManager !== nothing && Scripts.BattlePotionManagerModule.ability_targeting_blocks_potion(this.battlePotionManager))
                    open_potion_context_menu(this, i)
                end
            else
                if i in this.hoveredSlots
                    # Hover exit
                    if hasproperty(slot, :useEffectTexture)
                        slot.useEffectTexture = false
                    end
                    delete!(this.hoveredSlots, i)
                    this.slotTargetScales[i] = 1.0
                    # Stop flashing and reset color
                    this.slotIsFlashing[i] = false
                    if hasproperty(slot, :color)
                        slot.color = (255, 255, 255, 255)
                    end
                end
            end
        else
            # Slot not active, ensure glow is off and scale reset
            if i in this.hoveredSlots
                if hasproperty(slot, :useEffectTexture)
                    slot.useEffectTexture = false
                end
                if hasproperty(slot, :color)
                    slot.color = (255, 255, 255, 255)
                end
                delete!(this.hoveredSlots, i)
            end
            this.slotTargetScales[i] = 1.0
            this.slotIsFlashing[i] = false
        end
    end
    
    # Animate scales
    update_slot_scale_animations(this, deltaTime)
    
    # Animate flashing
    update_slot_flash_animations(this, deltaTime)
end

"""
Animate scale on hover (fast enlarge, slow ease-out shrink).
"""
function update_slot_scale_animations(this::PotionTooltip, deltaTime)
    for i in 1:length(this.potionSlots)
        current = get(this.slotScales, i, 1.0)
        target = get(this.slotTargetScales, i, 1.0)
        
        if abs(current - target) > 0.001
            diff = target - current
            if target > current
                # Hover: fast increase
                new_scale = current + diff * min(20.0 * deltaTime, 1.0)
            else
                # Unhover: slow ease-out cubic
                t = min(2.5 * deltaTime, 1.0)
                eased_t = 1.0 - (1.0 - t)^3
                new_scale = current + diff * eased_t
            end
            this.slotScales[i] = new_scale
        else
            new_scale = target
            this.slotScales[i] = target
        end
        
        slot = this.potionSlots[i]
        if haskey(this.slotBaseSizes, i) && haskey(this.slotBasePositions, i)
            base_size = this.slotBaseSizes[i]
            base_pos = this.slotBasePositions[i]
            new_width = base_size.x * new_scale
            new_height = base_size.y * new_scale
            slot.size = Math.Vector2(new_width, new_height)
            slot.position = Math.Vector2(
                base_pos.x - (new_width - base_size.x) / 2,
                base_pos.y - (new_height - base_size.y) / 2
            )
        end
    end
end

"""
Animate a brightness flash pulse on hovered potion slots (sine wave color modulation).
"""
function update_slot_flash_animations(this::PotionTooltip, deltaTime)
    for i in 1:length(this.potionSlots)
        is_flashing = get(this.slotIsFlashing, i, false)
        slot = this.potionSlots[i]
        
        if is_flashing
            # Update flash time
            flash_time = get(this.slotFlashTime, i, 0.0)
            flash_time += deltaTime * 1.0  # Flash speed
            this.slotFlashTime[i] = flash_time
            
            # Calculate flash brightness using sine wave (oscillates between 0.7 and 1.0)
            flash_value = 0.85 + 0.15 * sin(flash_time * 2 * π)
            
            # Apply brightness with slight blue-white tint when brighter
            base_brightness = round(Int, 255 * flash_value)
            blue_boost = round(Int, 40 * (flash_value - 0.85) / 0.15)
            r = base_brightness
            g = base_brightness
            b = min(255, base_brightness + blue_boost)
            
            if hasproperty(slot, :color)
                slot.color = (r, g, b, 255)
            end
        end
    end
end

"""
Open a context menu for the potion at the given slot index.
Shows "Use" (if potion type lists the current context) and "Discard".
"""
function open_potion_context_menu(this::PotionTooltip, slot_index::Int)
    if slot_index > length(this.user.potions)
        return
    end
    
    potion = this.user.potions[slot_index]
    
    menu_items = Scripts.ContextMenuModule.ContextMenuItem[]
    
    # Check if potion is usable in the current context
    if Scripts.BattlePotionManagerModule.PotionEffectsModule.usable_in(potion, this.useContext)
        push!(menu_items, Scripts.ContextMenuModule.ContextMenuItem(
            text = "Use",
            action = () -> use_potion_from_menu(this, slot_index)
        ))
        push!(menu_items, Scripts.ContextMenuModule.ContextMenuItem(is_separator = true))
    end
    
    # Always allow discarding
    push!(menu_items, Scripts.ContextMenuModule.ContextMenuItem(
        text = "Discard",
        action = () -> discard_potion_from_menu(this, slot_index)
    ))
    
    Scripts.ContextMenuModule.open_context_menu(
        "battle_potion_$(slot_index)",
        menu_items;
        manager = this.contextMenuManager
    )
end

"""
Use a potion via the context menu (delegates to BattlePotionManager in battle).
"""
function use_potion_from_menu(this::PotionTooltip, slot_index::Int)
    if this.useContext != "Combat"
        Scripts.BattlePotionManagerModule.PotionEffectsModule.use_outside_battle!(this.user, slot_index)
        return
    end
    if this.battlePotionManager === nothing
        @warn("BattlePotionManager not available")
        return
    end
    
    # Check player turn
    if this.battleManager !== nothing &&
       this.battleManager.currentState != this.battleManager.battleStates[:playerTurn]
        @debug "Not player turn, cannot use potion"
        return
    end
    
    Scripts.BattlePotionManagerModule.use_potion(this.battlePotionManager, slot_index)
end

"""
Discard a potion via the context menu (removes it from inventory).
"""
function discard_potion_from_menu(this::PotionTooltip, slot_index::Int)
    if slot_index > length(this.user.potions)
        return
    end
    
    @debug("Discarding potion from slot $slot_index")
    deleteat!(this.user.potions, slot_index)
    this.useContext == "Combat" || JulGame.UserGlobals["Module"].SaveManagerModule.try_save_run!()
    # Display will update next frame via potion count change detection
end

"""
Spawn the potion bar's tooltip/context-menu manager outside battle.
Creates a TooltipManager when the scene has none.
"""
function spawn!(tooltipManager = nothing)
    if tooltipManager === nothing
        tooltipEntity = JulGame.create_entity(JulGame.EntityModule.Entity("TooltipManager"))
        push!(tooltipEntity.scripts, Scripts.TooltipManagerModule.TooltipManager())
        tooltipManager = tooltipEntity.scripts[1]
    end
    entity = JulGame.create_entity(JulGame.EntityModule.Entity("PotionTooltipManager"))
    push!(entity.scripts, PotionTooltip())
    this = entity.scripts[1]
    this.tooltipManager = tooltipManager
    JulGame.initialize(this)
    return this
end

function play_potion_hover_sfx()
    name = rand(("potionhover1", "potionhover2", "potionhover3", "potionhover4"))
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", name),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "potion hover sfx: $e"
    end
end

export PotionTooltip, update_potion_tooltips, spawn!
end
