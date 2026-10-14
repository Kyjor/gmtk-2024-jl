module IntentModule
using JulGame
include("utils/DisplayText.jl")
using .DisplayTextModule

mutable struct Intent
    parent
    isAttack
    startingY

    # attack
    attackCurrentProgress
    attackStartPosition
    attackEndPosition
    attackTime
    attackTimeElapsed
    isReturn
    sprite

    isBusy
    
    defenseSprite
    intentValue
    
    # Text display
    textOffsetX
    textOffsetY
    textFontSize
    showTextBackground
    textPrefix

    # Next intent display
    showNextIntent
    nextIntentOffset
    nextIntentValue
    nextIntentPrefix
    nextIntentFontSize
    nextIntentOpacity

    battleManager
    gameManager

    function Intent()
        this = new()

        this.isAttack = true
        this.attackTime = 2.0
        this.attackTimeElapsed = this.attackTime
        this.isReturn = false
        this.isBusy = false
        this.intentValue = 0
        
        # Text display configuration
        this.textOffsetX = 100    # Offset in pixels from the sprite position
        this.textOffsetY = 20     # Offset up a bit to show above the sprite
        this.textFontSize = 20    # Font size for the intent text
        this.showTextBackground = true
        this.textPrefix = ""      # Prefix to show before the value
        
        # Next intent display configuration
        this.showNextIntent = true
        this.nextIntentOffset = JulGame.Math.Vector2f(-3, 2)  # Position behind the player
        this.nextIntentValue = 0
        this.nextIntentPrefix = ""  # Will show the intent type directly
        this.nextIntentFontSize = 14  # Smaller than main intent
        this.nextIntentOpacity = 200  # More visible but still semi-transparent
        
        # Initialize references to other scripts (will be set in initialize)
        this.battleManager = nothing
        this.gameManager = nothing
        
        # Initialize other fields that might be used
        this.startingY = 0
        this.attackCurrentProgress = JulGame.Math.Vector2f(0, 0)
        this.attackStartPosition = JulGame.Math.Vector2f(0, 0)
        this.attackEndPosition = JulGame.Math.Vector2f(0, 0)
        this.sprite = nothing
        this.defenseSprite = nothing
        
        return this
    end
end

function JulGame.initialize(this::Intent)
    this.sprite = this.parent.sprite
    this.gameManager = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba")
    this.battleManager = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba").scripts[4]
end

function JulGame.on_shutdown(this::Intent)
end

function JulGame.update(this::Intent, deltaTime)
    try
        # Get game speed multiplier (used for attack animations)
        globals = JulGame.UserGlobals["Module"]
        speed_multiplier = globals.get_data_manager().game_speed_multiplier
        
        # Handle attack animation
        if this.attackTimeElapsed < this.attackTime && this.isAttack
            this.isBusy = true
            # Update progress with deltaTime (scaled by speed)
            this.attackCurrentProgress = JulGame.Math.Vector2f(clamp(this.attackCurrentProgress.x + deltaTime * speed_multiplier, 0, 1), clamp(this.attackCurrentProgress.y + deltaTime * speed_multiplier, 0, 1))
            
            # Apply easing function only if not returning
            progress = if !this.isReturn
                # Clamp the eased values to ensure they don't overshoot
                JulGame.Math.Vector2f(
                    clamp(ease_in_out_back(this.attackCurrentProgress.x), 0, 1),
                    clamp(ease_in_out_back(this.attackCurrentProgress.y), 0, 1)
                )
            else
                this.attackCurrentProgress
            end
            
            # Direct interpolation with no restrictions on X coordinates
            newPos = JulGame.Math.Vector2f(
                this.attackStartPosition.x + (this.attackEndPosition.x - this.attackStartPosition.x) * progress.x,
                clamp(this.attackStartPosition.y + (this.attackEndPosition.y - this.attackStartPosition.y) * progress.y, 0, 4.5)
            )
            
            # If we're very close to completing the movement, snap to the exact end position
            if progress.x > 0.99 && !this.isReturn
                newPos = JulGame.Math.Vector2f(
                    this.attackEndPosition.x,
                    clamp(this.attackEndPosition.y, 0, 4.5)
                )
            end
            
            # Set the new position
            this.parent.transform.position = newPos
            
            # Apply speed multiplier to elapsed time
            this.attackTimeElapsed += deltaTime * speed_multiplier
            if this.attackCurrentProgress.x >= 1 && this.attackCurrentProgress.y >= 1
                this.attackTimeElapsed = this.attackTime
            end
            
            if this.attackTimeElapsed >= this.attackTime && !this.isReturn
                # Safely access game manager
                if this.gameManager !== nothing && isdefined(this.gameManager, :scripts) && length(this.gameManager.scripts) >= 7
                    gm = this.gameManager
                    # Trigger shaking effect
                    gm.scripts[7].elapsed = 0.0
                    gm.scripts[7].shaking = true
                end
                
                this.isReturn = true
                this.attackTimeElapsed = 0
                swap = this.attackStartPosition
                this.attackStartPosition = this.attackEndPosition
                this.attackEndPosition = swap
                @debug " Set attack start position to $(this.attackStartPosition) and end position to $(this.attackEndPosition)"
                this.attackCurrentProgress = JulGame.Math.Vector2f(0, 0)
            elseif this.attackTimeElapsed >= this.attackTime && this.isReturn
                this.isReturn = false
                this.isBusy = false
            end
        end
    catch e
        @warn "Error in Intent update animation: $e"
    end
    
    # Display the next intent if enabled
    if this.showNextIntent
        try
            display_next_intent(this)
        catch e
            @warn "Error displaying next intent: $e"
        end
    end
end

function attack(this::Intent, attackStartPosition, attackEndPosition=JulGame.Math.Vector2f(9, 4))
    #JulGame.Component.toggle_sound(JulGame.SceneModule.get_entity_by_name(MAIN.scene, "MeleeSound").soundSource)
    this.attackTimeElapsed = 0
    this.attackStartPosition = attackStartPosition #this.parent.transform.position
    this.attackCurrentProgress = JulGame.Math.Vector2f(0, 0)

    this.attackEndPosition = attackEndPosition
    @debug "Attack initiated from $(this.attackStartPosition) to $(this.attackEndPosition)"
end

function ease_in_out_back(x::Float64) ::Float64 
    c1 = 1.70158
    c2 = c1 * 1.525
    
    # Ensure x is properly clamped to avoid extreme values
    x_clamped = clamp(x, 0.0, 1.0)
    
    return x_clamped < 0.5 ? 
        (2^(2 * x_clamped) * ((c2 + 1) * 2 * x_clamped - c2)) / 2 : 
        (2^(2 * x_clamped - 2) * ((c2 + 1) * (x_clamped * 2 - 2) + c2) + 2) / 2
end

function display_intent_text(this::Intent)
    # Format the text to display
    if this.battleManager === nothing || !isdefined(this.battleManager, :countDict) || isempty(this.battleManager.countDict)
        # If there's no data yet, just show the default intent value
        this.intentValue = 0
        displayText = "$(this.textPrefix) $(this.intentValue)"
    else
        # Try to safely sort the countDict by value
        try
            # Use sort with collect to safely handle the dictionary
            sorted_count = collect(this.battleManager.countDict)
            if !isempty(sorted_count)
                # Sort by value (second element) in descending order
                sort!(sorted_count, by = x -> x[2], rev = true)
                # Get the highest value
                this.intentValue = sorted_count[1][2]
                displayText = "$(this.textPrefix) $(this.intentValue)"
            else
                displayText = "$(this.textPrefix) $(this.intentValue)"
            end
        catch e
            # If anything goes wrong, still show a reasonable value
            @warn "Error sorting countDict: $e"
            displayText = "$(this.textPrefix) $(this.intentValue)"
        end
    end
    
    # Display the intent value using immediate_text
    DisplayTextModule.display_text(
        "intent_value_text_$(this.parent.name)",  # Unique ID for this text
        displayText;                              # The text content with prefix
        fontSize = this.textFontSize,                        # Font size
        position = JulGame.Math.Vector2(this.parent.transform.position.x - .5, this.parent.transform.position.y),  # Position on screen
        anchor = :none                                    # Is centered horizontally
    )
end

# Display the next potential intent
function display_next_intent(this::Intent)
    # Safely check for countDict
    if this.battleManager === nothing || !isdefined(this.battleManager, :countDict) || length(this.battleManager.countDict) < 2
        #@debug "No next intent to display: battleManager: $(this.battleManager === nothing), countDict: $(this.battleManager.countDict)"
        return
    end
    
    # Try to get the next potential intent
    try
        next_intent_key, next_intent_value = get_next_potential_intent(this)
        
        # If there's no next intent, don't display anything
        if next_intent_key === nothing || next_intent_value === nothing || next_intent_value <= 0
            return
        end
        
        this.nextIntentValue = next_intent_value
        
        # Calculate position (behind player sprite)
        nextIntentPos = JulGame.Math.Vector2f(
            this.parent.transform.position.x + this.nextIntentOffset.x,
            this.parent.transform.position.y + this.nextIntentOffset.y
        )
        
        # Format display text (include the intent type)
        nextDisplayText = "" #"Next: $(next_intent_key) ($(this.nextIntentValue))"
        
        # Display a small indicator to show this is the next potential intent
        DisplayTextModule.display_text(
            "next_intent_arrow_$(this.parent.name)",
            "";
            #"",  # Diamond character as a visual separator
            fontSize = this.nextIntentFontSize,
            position = JulGame.Math.Vector2(-4.51, 6.0),
            anchor = :none,
            isWorldEntity = true
        )
        
        # Display the next intent value with immediate_text in world space
        DisplayTextModule.display_text(
            "next_intent_value_$(this.parent.name)",
            nextDisplayText;
            fontSize = this.nextIntentFontSize,
            position = JulGame.Math.Vector2(-4.5, 6.0),
            anchor = :none,
            isWorldEntity = true
        )
    catch e
        @warn "Error displaying next intent: $e"
    end
end

# Helper function to get the next potential intent
function get_next_potential_intent(this::Intent)
    # Safely check battleManager and countDict
    if this.battleManager === nothing || !isdefined(this.battleManager, :countDict) || isempty(this.battleManager.countDict)
        return nothing, nothing
    end
    
    # Make sure we have an intent field
    if !isdefined(this.battleManager, :intent)
        return nothing, nothing
    end
    
    # Current intent key
    current_intent = this.battleManager.intent
    
    # Find the intent with the highest count that isn't the current intent
    next_intent = nothing
    next_count = 0
    
    for (intent_key, count) in this.battleManager.countDict
        # Skip the current intent
        if intent_key == current_intent
            continue
        end
        
        # Check if this intent has a higher count than what we've found so far
        if count > next_count
            next_intent = intent_key
            next_count = count
        end
    end
    
    # Return the next most common intent and its count
    if next_intent !== nothing && next_count > 0
        return next_intent, next_count
    end
    
    # Return nothing if no next intent found
    return nothing, nothing
end
end
