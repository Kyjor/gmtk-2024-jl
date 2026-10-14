module UIFloatingAnimationModule
    using JulGame
    
    export UIFloatingAnimation, update_ui_floating_animation, initialize_ui_floating_animation

    # Easing functions for smooth animations
    function ease_in_out_sine(x::Float64) :: Float64
        return -(cos(π * x) - 1) / 2
    end

    function ease_out_sine(x::Float64) :: Float64
        return sin((x * π) / 2)
    end

    # UI Floating animation configuration and state
    mutable struct UIFloatingAnimation
        # Animation timing
        animationTime::Float64
        speed::Float64                    # Cycles per second
        
        # Movement amplitudes (in screen pixels)
        verticalAmplitude::Float64        # Vertical floating distance
        horizontalAmplitude::Float64      # Horizontal drift distance  
        rotationAmplitude::Float64        # Rotation amount in degrees
        
        # Phase offsets for natural movement
        horizontalPhaseOffset::Float64    # Phase offset for horizontal motion
        rotationPhaseOffset::Float64      # Phase offset for rotation
        
        # Speed multipliers for each axis
        horizontalSpeedMultiplier::Float64
        rotationSpeedMultiplier::Float64
        
        # Base positions (set during initialization)
        basePosition::Math.Vector2f
        baseRotation::Float64
        
        # Target UI element reference
        uiElement
        
        function UIFloatingAnimation(;
            speed::Float64 = 1.5,
            verticalAmplitude::Float64 = 4.0,      # Screen pixels instead of world units
            horizontalAmplitude::Float64 = 3.0,    # Screen pixels instead of world units
            rotationAmplitude::Float64 = 4.0,
            horizontalPhaseOffset::Float64 = π/3,
            rotationPhaseOffset::Float64 = π/6,
            horizontalSpeedMultiplier::Float64 = 0.6,
            rotationSpeedMultiplier::Float64 = 0.4
        )
            this = new()
            
            this.animationTime = 0.0
            this.speed = speed
            this.verticalAmplitude = verticalAmplitude
            this.horizontalAmplitude = horizontalAmplitude
            this.rotationAmplitude = rotationAmplitude
            this.horizontalPhaseOffset = horizontalPhaseOffset
            this.rotationPhaseOffset = rotationPhaseOffset
            this.horizontalSpeedMultiplier = horizontalSpeedMultiplier
            this.rotationSpeedMultiplier = rotationSpeedMultiplier
            
            this.basePosition = Math.Vector2f(0, 0)
            this.baseRotation = 0.0
            this.uiElement = nothing
            
            return this
        end
    end
    
    # Initialize the UI floating animation with a UI element
    function initialize_ui_floating_animation(animation::UIFloatingAnimation, uiElement)
        animation.uiElement = uiElement
        if uiElement !== nothing
            animation.basePosition = Math.Vector2f(uiElement.position.x, uiElement.position.y)
            animation.baseRotation = uiElement.rotation
        end
    end
    
    # Update the UI floating animation (call this every frame)
    function update_ui_floating_animation(animation, deltaTime::Float64)
        if animation.uiElement === nothing
            return
        end
        
        animation.animationTime += deltaTime * animation.speed
        
        # Primary vertical float (main up/down motion)
        verticalProgress = (sin(animation.animationTime * 2π) + 1) / 2  # 0 to 1
        verticalEased = ease_in_out_sine(verticalProgress)
        verticalOffset = (verticalEased - 0.5) * animation.verticalAmplitude
        
        # Secondary horizontal drift (slower, offset phase)
        horizontalProgress = (sin(animation.animationTime * 2π * animation.horizontalSpeedMultiplier + animation.horizontalPhaseOffset) + 1) / 2
        horizontalEased = ease_out_sine(horizontalProgress)
        horizontalOffset = (horizontalEased - 0.5) * animation.horizontalAmplitude
        
        # Rotation animation (different phase and speed for natural movement)
        rotationProgress = (sin(animation.animationTime * 2π * animation.rotationSpeedMultiplier + animation.rotationPhaseOffset) + 1) / 2
        rotationEased = ease_in_out_sine(rotationProgress)
        rotationOffset = (rotationEased - 0.5) * animation.rotationAmplitude
        
        # Apply the floating offset and rotation to UI element
        animation.uiElement.position = Math.Vector2(
            animation.basePosition.x + horizontalOffset,
            animation.basePosition.y + verticalOffset
        )
        animation.uiElement.rotation = animation.baseRotation + rotationOffset
    end
end
