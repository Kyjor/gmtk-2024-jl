module EnemyIntentTooltipModule
using JulGame
using ..Scripts
include("localization/battle_strings.jl")
using .BattleStringsModule

"""
Manager for displaying tooltips when hovering over enemy intents.
Tracks all enemy intent entities and registers them with the TooltipManager.
"""
mutable struct EnemyIntentTooltip
    parent
    tooltipManager
    gameManager
    registeredIntents::Dict  # Maps intent entity -> enemy instance

    function EnemyIntentTooltip()
        this = new()
        this.tooltipManager = nothing
        this.gameManager = nothing
        this.registeredIntents = Dict()
        return this
    end
end

function JulGame.initialize(this::EnemyIntentTooltip)
    # Get GameManager which has the tooltip manager
    gameEntity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba")
    if gameEntity !== nothing && length(gameEntity.scripts) > 0
        this.gameManager = gameEntity.scripts[1]
        if this.gameManager !== nothing && isdefined(this.gameManager, :tooltipManager)
            this.tooltipManager = this.gameManager.tooltipManager

            # Set very short delay for intent tooltips (100ms)
            if this.tooltipManager !== nothing
                Scripts.TooltipManagerModule.set_tooltip_style(
                    this.tooltipManager,
                    hoverDelay = UInt64(100)
                )
            end
        end
    end
end

function JulGame.on_shutdown(this::EnemyIntentTooltip)
    # Clean up all registered intents
    if this.tooltipManager !== nothing
        for intentEntity in keys(this.registeredIntents)
            Scripts.TooltipManagerModule.deregister_tooltip_item(this.tooltipManager, intentEntity)
        end
    end
    empty!(this.registeredIntents)
end

"""
Register an enemy's intent entity for tooltip display.
Called when an enemy is created or its intent changes.
"""
function register_enemy_intent(this::EnemyIntentTooltip, enemy, intentEntity)
    if this.tooltipManager === nothing
        # Try to get tooltip manager again
        if this.gameManager !== nothing && isdefined(this.gameManager, :tooltipManager)
            this.tooltipManager = this.gameManager.tooltipManager
        end
        if this.tooltipManager === nothing
            return
        end
    end

    # Generate tooltip text based on enemy's current intent
    tooltipText = generate_intent_tooltip_text(enemy)

    # Register the intent entity with the tooltip manager
    Scripts.TooltipManagerModule.register_tooltip_item(
        this.tooltipManager,
        intentEntity,
        tooltipText
    )

    # Track this registration
    this.registeredIntents[intentEntity] = enemy

    @debug "Registered tooltip for enemy intent: $(intentEntity.id) - $(tooltipText)"
end

"""
Update the tooltip text for an already registered intent.
Called when an enemy's intent changes.
"""
function update_enemy_intent_tooltip(this::EnemyIntentTooltip, enemy, intentEntity)
    if this.tooltipManager === nothing
        return
    end

    if !haskey(this.registeredIntents, intentEntity)
        # Not registered yet, register it now
        register_enemy_intent(this, enemy, intentEntity)
        return
    end

    # Generate new tooltip text
    tooltipText = generate_intent_tooltip_text(enemy)

    # Re-register with updated text (this will overwrite the existing registration)
    Scripts.TooltipManagerModule.register_tooltip_item(
        this.tooltipManager,
        intentEntity,
        tooltipText
    )

    @debug "Updated tooltip for enemy intent: $(intentEntity.id) - $(tooltipText)"
end

"""
Unregister an enemy's intent entity.
Called when an enemy is destroyed.
"""
function unregister_enemy_intent(this::EnemyIntentTooltip, intentEntity)
    if this.tooltipManager === nothing
        return
    end

    if haskey(this.registeredIntents, intentEntity)
        Scripts.TooltipManagerModule.deregister_tooltip_item(this.tooltipManager, intentEntity)
        delete!(this.registeredIntents, intentEntity)
        @debug "Unregistered tooltip for enemy intent: $(intentEntity.id)"
    end
end

"""
Generate tooltip text describing what the enemy will do.
"""
function generate_intent_tooltip_text(enemy)::String
    if !isdefined(enemy, :currentIntent) || !isdefined(enemy, :intentValue)
        return BattleStringsModule.BATTLE_STRINGS[:enemy_intent_unknown]
    end

    intentType = uppercase(enemy.currentIntent)
    value = enemy.intentValue
    fmt = BattleStringsModule.format_string
    apply(n, status) = fmt(:enemy_intent_line_apply, value=n, status=status)

    effects = if intentType == "ATTACK"
        [fmt(:enemy_intent_line_attack, value=value)]
    elseif intentType == "DEFEND"
        [fmt(:enemy_intent_line_defend, value=value)]
    elseif intentType == "HEAL"
        [fmt(:enemy_intent_line_heal, value=value)]
    elseif intentType == "SKILL"
        [fmt(:enemy_intent_line_skill, value=value)]
    elseif intentType == "BASH"
        [fmt(:enemy_intent_line_attack, value=value), apply(1, "Vulnerable")]
    elseif intentType == "WEAKEN"
        [apply(value, "Weaken"), BattleStringsModule.BATTLE_STRINGS[:enemy_intent_line_weaken_note]]
    elseif intentType in ("BURN", "FREEZE", "POISON")
        [apply(value, titlecase(intentType))]
    elseif intentType == "HEALKING"
        [fmt(:enemy_intent_line_heal_king, value=value)]
    elseif intentType == "ALLYSHIELD"
        [fmt(:enemy_intent_line_ally_shield, value=value)]
    elseif intentType == "SUMMON"
        [fmt(:enemy_intent_line_summon, value=value)]
    else
        [fmt(:enemy_intent_line_generic, intent_type=intentType, value=value)]
    end

    header = fmt(:enemy_intent_header, name=enemy_display_name(enemy))
    return join([header; effects], "\n")
end

function enemy_display_name(enemy)::String
    data = isdefined(enemy, :enemyData) ? enemy.enemyData : nothing
    name = data === nothing ? "" : string(data.name)  # `name` is a localized virtual property
    return isempty(name) ? BattleStringsModule.BATTLE_STRINGS[:enemy_intent_default_name] : name
end

"""
Update function called every frame to ensure tooltips stay up to date.
"""
function JulGame.update(this::EnemyIntentTooltip, deltaTime)
    # Update tooltips for all registered intents in case their values changed
    for (intentEntity, enemy) in this.registeredIntents
        if intentEntity !== nothing && isdefined(enemy, :currentIntent) && isdefined(enemy, :intentValue)
            # Check if the tooltip text needs updating
            currentText = generate_intent_tooltip_text(enemy)

            # Get the current registered text
            if this.tooltipManager !== nothing && haskey(this.tooltipManager.tooltipItems, intentEntity)
                registeredText = this.tooltipManager.tooltipItems[intentEntity].text

                # Update if text has changed
                if registeredText != currentText
                    update_enemy_intent_tooltip(this, enemy, intentEntity)
                end
            end
        end
    end
end

export EnemyIntentTooltip, register_enemy_intent, update_enemy_intent_tooltip, unregister_enemy_intent
end
