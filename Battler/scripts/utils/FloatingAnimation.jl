module FloatingAnimationModule
    using JulGame
    
    export FloatingAnimation, update_floating_animation, initialize_floating_animation

    # Easing functions for smooth animations
    function ease_in_out_sine(x::Float64) :: Float64
        return -(cos(π * x) - 1) / 2
    end

    function ease_out_sine(x::Float64) :: Float64
        return sin((x * π) / 2)
    end

    # Floating animation configuration and state
    mutable struct FloatingAnimation
        # Animation timing
        animationTime::Float64
        speed::Float64                    # Cycles per second
        
        # Movement amplitudes
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
        baseOffset::Math.Vector2f
        baseRotation::Float64
        
        # Target sprite reference
        sprite
        
        function FloatingAnimation(;
            speed::Float64 = 1.5,
            verticalAmplitude::Float64 = 4.2/64.0,
            horizontalAmplitude::Float64 = 3.2/64.0,
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
            
            this.baseOffset = Math.Vector2f(0, 0)
            this.baseRotation = 0.0
            this.sprite = nothing
            
            return this
        end
    end
    
    # Initialize the floating animation with a sprite
    function initialize_floating_animation(animation::FloatingAnimation, sprite)
        animation.sprite = sprite
        if sprite !== nothing
            animation.baseOffset = Math.Vector2f(sprite.offset.x, sprite.offset.y)
            animation.baseRotation = sprite.rotation
        end
    end
    
    # Update the floating animation (call this every frame)
    function update_floating_animation(animation, deltaTime::Float64)
        if animation.sprite === nothing
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
        
        # Apply the floating offset and rotation
        animation.sprite.offset = Math.Vector2f(
            animation.baseOffset.x + horizontalOffset,
            animation.baseOffset.y + verticalOffset
        )
        animation.sprite.rotation = animation.baseRotation + rotationOffset
    end
end 