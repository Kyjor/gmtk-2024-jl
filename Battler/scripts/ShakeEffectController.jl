module ShakeEffectControllerModule
    using JulGame
    using Random
    using ..Scripts
    export ShakeEffect, shake_effect, update_shake_effects, start_shake!, stop_shake!
    
    """
        ShakeEffect - A visual shake effect that can be applied to any UI element
    
    Creates a pleasing shake animation with customizable parameters for intensity,
    duration, frequency, and decay patterns. Supports both position and rotation shake.
    """
    mutable struct ShakeEffectController <: Script
        parent
        #shakeEffects::Vector{ShakeEffect}

        function ShakeEffectController()
            this = new()
            @debug "ShakeEffectController constructor"
            #this.shakeEffects = ShakeEffect[]
            this.parent = C_NULL
            return this
        end
    end

    function JulGame.update(this::ShakeEffectController, deltaTime)
        update_shake_effects()
    end

    function JulGame.on_shutdown(this::ShakeEffectController)
    end

    function JulGame.initialize(this::ShakeEffectController)
        @debug "ShakeEffectController initialized"
    end

    mutable struct ShakeEffect
        # Core shake parameters
        intensity          # Base shake strength (0.0 to 10.0)
        duration           # How long the shake lasts (seconds)
        frequency          # How fast it shakes (Hz)
        
        # Advanced customization
        decay_rate         # How quickly intensity fades (0.0 = no decay, 1.0 = linear)
        rotation_intensity # How much rotation to apply (0.0 to 1.0)
        position_intensity # How much position offset (0.0 to 1.0)
        
        # Pattern customization
        use_sine_wave::Bool         # Use smooth sine wave vs random jitter
        seed::Int                   # Random seed for consistent patterns
        
        # Internal state (not set by user)
        start_time::Float64         # When the shake started
        is_active::Bool            # Whether shake is currently running
        original_position::Math.Vector2  # Original position before shake
        original_rotation  # Original rotation before shake
        
        # Target element
        target_element::Any         # The element being shaken

        parent
        
        function ShakeEffect(;
            intensity = 3.0f0,
            duration = 0.5f0,
            frequency = 8.0f0,
            decay_rate = 0.8f0,
            rotation_intensity = 0.3f0,
            position_intensity = 1.0f0,
            use_sine_wave::Bool = true,
            seed::Int = 12345
        )
            this = new()
            this.intensity = intensity
            this.duration = duration
            this.frequency = frequency
            this.decay_rate = decay_rate
            this.rotation_intensity = rotation_intensity
            this.position_intensity = position_intensity
            this.use_sine_wave = use_sine_wave
            this.seed = seed
            this.start_time = 0.0
            this.is_active = false
            this.original_position = Math.Vector2(0, 0)
            this.original_rotation = 0.0f0
            this.target_element = nothing

            return this
        end
    end
    
    # Global shake effects manager
    const ACTIVE_SHAKE_EFFECTS = ShakeEffect[]
    
    """
        shake_effect(element; kwargs...) -> ShakeEffect
    
    Convenience function to create and apply a shake effect to any visual element.
    Works with sprites, UI elements, text, etc.
    
    # Arguments
    - `element`: The visual element to shake (sprite, UIElement, etc.)
    - `intensity`: Base shake strength (default: 3.0)
    - `duration`: How long the shake lasts in seconds (default: 0.5)
    - `frequency`: Shake frequency in Hz (default: 8.0)
    - `decay_rate`: How quickly intensity fades (default: 0.8)
    - `rotation_intensity`: How much rotation to apply (default: 0.3)
    - `position_intensity`: How much position offset (default: 1.0)
    - `use_sine_wave`: Use smooth sine wave vs random jitter (default: true)
    - `seed`: Random seed for consistent patterns (default: 12345)
    
    # Examples
    ```julia
    # Simple shake
    shake_effect(my_sprite; intensity=5.0, duration=1.0)
    
    # Intense rotation shake
    shake_effect(ui_element; intensity=8.0, rotation_intensity=1.0, duration=0.3)
    
    # Gentle position shake
    shake_effect(text_element; intensity=2.0, position_intensity=1.0, rotation_intensity=0.0)
    ```
    """
    function shake_effect(element; 
        intensity = 3.0f0,
        duration = 0.5f0,
        frequency = 8.0f0,
        decay_rate = 0.8f0,
        rotation_intensity = 0.3f0,
        position_intensity = 1.0f0,
        use_sine_wave::Bool = true,
        seed::Int = 12345
    )
        # Create the shake effect
        effect = ShakeEffect(
            intensity=intensity,
            duration=duration,
            frequency=frequency,
            decay_rate=decay_rate,
            rotation_intensity=rotation_intensity,
            position_intensity=position_intensity,
            use_sine_wave=use_sine_wave,
            seed=seed
        )
        
        # Set the target element
        effect.target_element = element

        # If there are already active effects on this element, stop them FIRST
        # to ensure we capture the true original position/rotation and avoid drift
        existing_effects = filter(e -> e.target_element === element && e.is_active, ACTIVE_SHAKE_EFFECTS)
        if !isempty(existing_effects)
            @debug("Warning: $(length(existing_effects)) existing shake effects found for this element. Stopping them first.")
            for existing_effect in existing_effects
                stop_shake!(existing_effect)
            end
            # Remove stopped effects from the list
            filter!(e -> e.is_active, ACTIVE_SHAKE_EFFECTS)
        end

        # Now capture original position and rotation AFTER clearing previous shakes
        effect.original_position = get_element_position(element)
        effect.original_rotation = get_element_rotation(element)

        # @debug("Creating shake effect for element: $(element)")
        # @debug("Captured original position: $(effect.original_position)")
        # @debug("Captured original rotation: $(effect.original_rotation)")

        # Add to active effects
        push!(ACTIVE_SHAKE_EFFECTS, effect)
        
        # Start the shake
        start_shake!(effect)
        
        return effect
    end
    
    """
        start_shake!(effect::ShakeEffect)
    
    Start the shake effect immediately.
    """
    function start_shake!(effect::ShakeEffect)
        effect.start_time = time()
        effect.is_active = true
    end
    
    """
        stop_shake!(effect::ShakeEffect)
    
    Stop the shake effect immediately and restore original position/rotation.
    """
    function stop_shake!(effect::ShakeEffect)
        @debug("Stopping shake effect for element: $(effect.target_element)")
        if effect.target_element !== nothing
            # Restore original position and rotation
            @debug("Restoring original position: $(effect.original_position), rotation: $(effect.original_rotation)")
            set_element_position(effect.target_element, effect.original_position)
            set_element_rotation(effect.target_element, effect.original_rotation)
        end
        effect.is_active = false
    end
    
    """
        update_shake_effects(deltaTime)
    
    Update all active shake effects. Call this from your main update loop.
    """
    function update_shake_effects()
        @debug "Active shake effects: $(length(ACTIVE_SHAKE_EFFECTS))"
        current_time = time()
        effects_to_remove = Int[]
        for (i, effect) in enumerate(ACTIVE_SHAKE_EFFECTS)
            if !effect.is_active
                continue
            end
            @debug "Shake effect update"
            @debug "Current time: $(current_time)"
            @debug "Start time: $(effect.start_time)"
            @debug "Duration: $(effect.duration)"
            @debug "Elapsed: $(current_time - effect.start_time)"
            @debug "Is active: $(effect.is_active)"
            @debug "Target element: $(effect.target_element)"
            @debug "Original position: $(effect.original_position)"
            @debug "Original rotation: $(effect.original_rotation)"
            
            elapsed = current_time - effect.start_time
            if elapsed >= effect.duration
                # Shake finished, restore original position/rotation
                @debug("Shake effect duration completed for element: $(effect.target_element)")
                stop_shake!(effect)
                push!(effects_to_remove, i)
                continue
            end
            
            # Calculate decay factor
            decay_factor = 1.0f0 - (elapsed / effect.duration) * effect.decay_rate
            decay_factor = max(0.0f0, decay_factor)
            
            # Calculate current intensity
            current_intensity = effect.intensity * decay_factor
            
            # Generate shake values
            if effect.use_sine_wave
                # Smooth sine wave pattern
                time_factor = elapsed * effect.frequency * 2π
                x_offset = sin(time_factor) * current_intensity * effect.position_intensity
                y_offset = cos(time_factor * 1.3f0) * current_intensity * effect.position_intensity
                rotation_offset = sin(time_factor * 0.7f0) * current_intensity * effect.rotation_intensity * 0.1f0
            else
                # Random jitter pattern
                Random.seed!(effect.seed + floor(Int, elapsed * effect.frequency))
                x_offset = (rand() - 0.5f0) * 2.0f0 * current_intensity * effect.position_intensity
                y_offset = (rand() - 0.5f0) * 2.0f0 * current_intensity * effect.position_intensity
                rotation_offset = (rand() - 0.5f0) * 2.0f0 * current_intensity * effect.rotation_intensity * 0.1f0
            end
            
            # Apply the shake to the element
            if effect.target_element !== nothing
                new_position = effect.original_position + Math.Vector2(x_offset, y_offset)
                new_rotation = effect.original_rotation + rotation_offset
                
                @debug "Shake offsets - x: $x_offset, y: $y_offset, rotation: $rotation_offset"
                @debug "New position: $new_position, Original: $(effect.original_position)"
                
                set_element_position(effect.target_element, new_position)
                set_element_rotation(effect.target_element, new_rotation)
            end
        end
        
        # Remove finished effects (in reverse order to maintain indices)
        @debug("Removing $(length(effects_to_remove)) finished shake effects")
        for i in reverse(effects_to_remove)
            deleteat!(ACTIVE_SHAKE_EFFECTS, i)
        end
    end
    
    # Helper functions to get/set element properties
    function get_element_position(element)
        # For UI elements, prioritize anchorOffset over position
        if isa(element, JulGame.UI.UIElement) && element.anchor.current_state !== :none
            return element.anchorOffset
        elseif element.position !== nothing
            return element.position
        else
            return Math.Vector2(0, 0)
        end
    end
    
    function set_element_position(element, position::Math.Vector2)
        # For UI elements, prioritize anchorOffset over position
        if isa(element, JulGame.UI.UIElement) && element.anchor.current_state !== :none
            element.anchorOffset = position
            @debug "Set anchorOffset to: $position"
        else
            element.position = position
            @debug "Set position to: $position"
        end
    end
    
    function get_element_rotation(element)
        if hasfield(typeof(element), :rotation)
            return element.rotation
        else
            return 0.0f0
        end
    end
    
    function set_element_rotation(element, rotation)
        if hasfield(typeof(element), :rotation)
            element.rotation = rotation
        end
    end
    
    """
        clear_all_shake_effects()
    
    Stop and clear all active shake effects.
    """
    function clear_all_shake_effects()
        for effect in ACTIVE_SHAKE_EFFECTS
            stop_shake!(effect)
        end
        empty!(ACTIVE_SHAKE_EFFECTS)
    end
    
    """
        get_active_shake_count() -> Int
    
    Get the number of currently active shake effects.
    """
    function get_active_shake_count()::Int
        return length(ACTIVE_SHAKE_EFFECTS)
    end
end # module
