module UISliderModule
    using JulGame
    using JulGame.Math
    using JulGame.FX.ImageFXModule
    
    export UISlider, update_slider, render_slider, get_slider_value, set_slider_value, SliderDirection, Horizontal, Vertical
    
    # Enum for slider direction
    @enum SliderDirection begin
        Horizontal
        Vertical
    end
    
    mutable struct UISlider
        id::String
        position::Math.Vector2
        size::Math.Vector2  # Size of the slider bar
        knobSize::Math.Vector2  # Size of the knob
        direction::SliderDirection
        
        # Value properties
        value::Float64  # x for horizontal, y for vertical
        minValue::Float64
        maxValue::Float64
        
        # Visual properties
        barColor::NTuple{4, Int}
        knobColor::NTuple{4, Int}
        barImage
        knobImage
        
        # State properties
        isDragging::Bool
        dragOffset::Math.Vector2
        isActive::Bool
        layer::Int
        
        # Anchor properties
        anchor::Symbol
        anchorOffset::Math.Vector2
        
        # Visual effects properties
        showOutline::Bool
        outlineColor::NTuple{4, Int}
        outlineThickness::Int
        glowOnHover::Bool
        glowOnDrag::Bool
        
        # Callback function when value changes
        onValueChanged::Union{Function, Nothing}
        
        function UISlider(
            id::String;
            position::Math.Vector2 = Math.Vector2(0, 0),
            size::Math.Vector2 = Math.Vector2(200, 20),
            knobSize::Math.Vector2 = Math.Vector2(20, 20),
            direction::SliderDirection = Horizontal,
            value::Float64 = 0.5,
            minValue::Float64 = 0.0,
            maxValue::Float64 = 1.0,
            barColor::NTuple{4, Int} = (100, 100, 100, 255),
            knobColor::NTuple{4, Int} = (200, 200, 200, 255),
            barImage = nothing,
            knobImage = nothing,
            isActive::Bool = true,
            layer::Int = 10,
            anchor::Symbol = :none,
            anchorOffset::Math.Vector2 = Math.Vector2(0, 0),
            showOutline::Bool = false,
            outlineColor::NTuple{4, Int} = (255, 255, 255, 128),
            outlineThickness::Int = 2,
            glowOnHover::Bool = true,
            glowOnDrag::Bool = true,
            onValueChanged::Union{Function, Nothing} = nothing
        )
            this = new()
            
            this.id = id
            this.position = position
            this.size = size
            this.knobSize = knobSize
            this.direction = direction
            this.isActive = isActive
            this.layer = layer
            this.anchor = anchor
            this.anchorOffset = anchorOffset
            this.showOutline = showOutline
            this.outlineColor = outlineColor
            this.outlineThickness = outlineThickness
            this.glowOnHover = glowOnHover
            this.glowOnDrag = glowOnDrag
            this.onValueChanged = onValueChanged
            
            # Convert scalar values to Vector2f based on direction
            if direction == Horizontal
                this.value = Float64(value)
                this.minValue = Float64(minValue)
                this.maxValue = Float64(maxValue)
            elseif direction == Vertical
                this.value = Float64(value)
                this.minValue = Float64(minValue)
                this.maxValue = Float64(maxValue)
            end
            
            this.barColor = barColor
            this.knobColor = knobColor
            
            # Get UI elements by ID
            if barImage !== nothing
                this.barImage = JulGame.SceneModule.get_ui_element_by_id(barImage)
                @debug "Slider $(id) - barImage ID: $barImage, found: $(this.barImage !== nothing)"
            else
                this.barImage = nothing
                @debug "Slider $(id) - no barImage provided"
            end
            
            if knobImage !== nothing
                this.knobImage = JulGame.SceneModule.get_ui_element_by_id(knobImage)
                @debug "Slider $(id) - knobImage ID: $knobImage, found: $(this.knobImage !== nothing)"
            else
                this.knobImage = nothing
                @debug "Slider $(id) - no knobImage provided"
            end
            
            this.isDragging = false
            this.dragOffset = Math.Vector2(0, 0)
            
            return this
        end
    end
    
    """
    Update slider logic - handles mouse input and dragging
    """
    function update_slider(slider::UISlider, deltaTime::Float64)
        if !slider.isActive || slider.barImage === nothing || slider.knobImage === nothing
            @debug "Slider $(slider.id) inactive or missing UI elements - barImage: $(slider.barImage), knobImage: $(slider.knobImage)"
            return
        end
        
        mousePos = MAIN.input.mousePosition
        
        # Check if mouse is over knob
        mouseInKnob = slider.knobImage.isHovered
        mouseInBar = slider.barImage.isHovered
        # Debug hover states
        if mouseInKnob || mouseInBar
            @debug "Slider $(slider.id) hover - knob: $mouseInKnob, bar: $mouseInBar, mousePos: $mousePos"
        end
        
        # Handle mouse input
        if JulGame.InputModule.get_mouse_button_pressed(1)
            if mouseInKnob
                # Start dragging: knob center tracks pointer (no grab offset; see set_slider_value)
                slider.isDragging = true
                slider.dragOffset = Math.Vector2(0, 0)
                @debug "Started dragging slider $(slider.id) - knob tracks mouse center"
            elseif mouseInBar
                # Clicked on the track: jump the knob under the pointer and keep dragging.
                @debug "Clicked on bar for slider $(slider.id) - jumping to mouse position"
                slider.isDragging = true
                slider.dragOffset = Math.Vector2(0, 0)
                jump_to_position(slider, mousePos, Math.Vector2(0, 0))  # sliderPos not needed anymore
            end
        elseif JulGame.InputModule.get_mouse_button_released(1)
            if slider.isDragging
                @debug "Stopped dragging slider $(slider.id)"
            end
            slider.isDragging = false
        end
        
        # Handle dragging
        if slider.isDragging && JulGame.InputModule.get_mouse_button(1)
            @debug "Dragging slider $(slider.id) - mousePos: $mousePos, current value: $(get_slider_value(slider))"
            update_value_from_mouse(slider, mousePos, Math.Vector2(0, 0))  # sliderPos not needed anymore
        end
    end
    
    """
    Render the slider using scene UI elements
    """
    function render_slider(slider::UISlider)
        if !slider.isActive || slider.barImage === nothing || slider.knobImage === nothing
            @debug "Cannot render slider $(slider.id) - inactive or missing UI elements"
            return
        end
        
        # Update knob position based on slider value
        update_knob_position(slider)
        
        # Update bar cropping based on slider value
        update_bar_cropping(slider)
        
        # Check if mouse is hovering over knob
        mouseInKnob = slider.knobImage.isHovered
        
        # Apply visual effects
        apply_visual_effects(slider, slider.knobImage, mouseInKnob)
    end
    
    """
    Apply visual effects like outlines and glows to the slider
    """
    function apply_visual_effects(slider::UISlider, knobElement, mouseInKnob::Bool)
        if knobElement === nothing || !knobElement.isActive
            return
        end
        
        shouldGlow = false
        glowColor = slider.outlineColor
        
        # Determine if we should show glow effects
        if slider.isDragging && slider.glowOnDrag
            shouldGlow = true
            glowColor = (255, 200, 100, 180)  # Orange glow when dragging
        elseif mouseInKnob && slider.glowOnHover
            shouldGlow = true
            glowColor = (100, 200, 255, 150)  # Blue glow when hovering
        elseif slider.showOutline
            shouldGlow = true
            glowColor = slider.outlineColor
        end
    end
    
    """
    Get the current slider value(s)
    """
    function get_slider_value(slider::UISlider)
        if slider.direction == Horizontal
            return slider.value
        elseif slider.direction == Vertical
            return slider.value
        else
            return slider.value
        end
    end
    
    """
    Set the slider value from mouse position. Uses the **center** of the knob aligned to
    the pointer: horizontal = only `mousePos.x` matters; vertical = only `mousePos.y`.
    """
    function set_slider_value(slider::UISlider, mousePos::Math.Vector2)
        if slider.barImage === nothing || slider.knobImage === nothing
            @debug "Cannot set slider value - missing bar or knob image"
            return
        end
        
        oldValue = slider.value
        
        # Get bar position and size
        barPos = slider.barImage.position
        barSize = slider.barImage.size
        kw = Float64(slider.knobImage.size.x)
        kh = Float64(slider.knobImage.size.y)
        
        if slider.direction == Horizontal
            # Map pointer X to value so the knob's horizontal center follows the cursor (y ignored).
            barW = Float64(barSize.x)
            minCenterX = barPos.x + kw / 2
            maxCenterX = barPos.x + barW - kw / 2
            if maxCenterX < minCenterX
                minCenterX = barPos.x + barW / 2
                maxCenterX = minCenterX
            end
            spanX = max(maxCenterX - minCenterX, 1.0e-6)
            cx = clamp(Float64(mousePos.x), minCenterX, maxCenterX)
            normalizedX = (cx - minCenterX) / spanX
            newVal = slider.minValue + normalizedX * (slider.maxValue - slider.minValue)
            slider.value = Float64(newVal)
            @debug "Set slider $(slider.id) (H) - cx=$cx, norm=$normalizedX, value=$(slider.value)"
            
        elseif slider.direction == Vertical
            # Map pointer Y so the knob's vertical center follows the cursor (x ignored).
            barH = Float64(barSize.y)
            minCenterY = barPos.y + kh / 2
            maxCenterY = barPos.y + barH - kh / 2
            if maxCenterY < minCenterY
                minCenterY = barPos.y + barH / 2
                maxCenterY = minCenterY
            end
            spanY = max(maxCenterY - minCenterY, 1.0e-6)
            cy = clamp(Float64(mousePos.y), minCenterY, maxCenterY)
            normalizedY = (cy - minCenterY) / spanY
            newVal = slider.minValue + normalizedY * (slider.maxValue - slider.minValue)
            slider.value = Float64(newVal)
            @debug "Set slider $(slider.id) (V) - cy=$cy, norm=$normalizedY, value=$(slider.value)"
        end
        
        @debug "Set slider $(slider.id) value from mouse - mousePos: $mousePos, barPos: $barPos, barSize: $barSize, old: $oldValue, new: $(slider.value)"
        
        # Call callback if value changed
        if slider.onValueChanged !== nothing && slider.value != oldValue
            @debug "Calling value changed callback for slider $(slider.id)"
            slider.onValueChanged(slider, get_slider_value(slider))
        end
    end
    
    """
    Update the knob position based on the current slider value
    """
    function update_knob_position(slider::UISlider)
        if slider.knobImage === nothing || slider.barImage === nothing
            @debug "Cannot update knob position for slider $(slider.id) - missing UI elements"
            return
        end
        
        # Get bar position and size
        barPos = slider.barImage.position
        barSize = slider.barImage.size
        
        @debug "Updating knob position for slider $(slider.id) - barPos: $barPos, barSize: $barSize, value: $(get_slider_value(slider))"
        
        # Calculate knob position based on value and direction
        knobPos = Math.Vector2(barPos.x, barPos.y)
        
        if slider.direction == Horizontal
            # Horizontal positioning
            normalizedX = (slider.value - slider.minValue) / (slider.maxValue - slider.minValue)
            knobPos = Math.Vector2(
                barPos.x + normalizedX * (barSize.x - slider.knobImage.size.x),
                knobPos.y
            )
            @debug "Horizontal positioning - normalizedX: $normalizedX, new knobPos: $knobPos"
        end
        
        if slider.direction == Vertical
            # Vertical positioning
            normalizedY = (slider.value - slider.minValue) / (slider.maxValue - slider.minValue)
            knobPos = Math.Vector2(
                knobPos.x,
                barPos.y + normalizedY * (barSize.y - slider.knobImage.size.y)
            )
            @debug "Vertical positioning - normalizedY: $normalizedY, new knobPos: $knobPos"
        end
        
        # Center knob if not using that axis
        if slider.direction == Horizontal
            knobPos = Math.Vector2(knobPos.x, barPos.y + (barSize.y - slider.knobImage.size.y) / 2)
        elseif slider.direction == Vertical
            knobPos = Math.Vector2(barPos.x + (barSize.x - slider.knobImage.size.x) / 2, knobPos.y)
        end
        
        # Update the knob position
        slider.knobImage.position = knobPos
    end
    
    """
    Update the bar cropping based on the current slider value
    """
    function update_bar_cropping(slider::UISlider)
        if slider.barImage === nothing
            @debug "Cannot update bar cropping for slider $(slider.id) - missing bar image"
            return
        end
        
        # Calculate normalized value (0.0 to 1.0)
        normalizedValue = (slider.value - slider.minValue) / (slider.maxValue - slider.minValue)
        
        if slider.direction == Horizontal
            # Use left-to-right cropping for horizontal sliders
            gfx_filter_health_bar(slider.barImage, normalizedValue, "RightToLeft")
            @debug "Updated horizontal bar cropping for slider $(slider.id) - normalizedValue: $normalizedValue"
            
        elseif slider.direction == Vertical
            # Use bottom-to-top cropping for vertical sliders (like a health bar)
            gfx_filter_health_bar(slider.barImage, normalizedValue, "BottomToTop")
            @debug "Updated vertical bar cropping for slider $(slider.id) - normalizedValue: $normalizedValue"
        end
    end

    # Helper functions
    
    function get_final_position(slider::UISlider)
        # Apply anchor positioning (simplified - could be expanded)
        basePos = slider.position + slider.anchorOffset
        
        if slider.anchor == :center
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x / 2 + basePos.x - slider.size.x / 2,
                windowSize.y / 2 + basePos.y - slider.size.y / 2
            )
        elseif slider.anchor == :centerTop
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x / 2 + basePos.x - slider.size.x / 2,
                basePos.y
            )
        elseif slider.anchor == :centerBottom
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x / 2 + basePos.x - slider.size.x / 2,
                windowSize.y + basePos.y - slider.size.y
            )
        elseif slider.anchor == :topLeft
            return basePos
        elseif slider.anchor == :topRight
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x + basePos.x - slider.size.x,
                basePos.y
            )
        elseif slider.anchor == :bottomLeft
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                basePos.x,
                windowSize.y + basePos.y - slider.size.y
            )
        elseif slider.anchor == :bottomRight
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x + basePos.x - slider.size.x,
                windowSize.y + basePos.y - slider.size.y
            )
        else
            return basePos
        end
    end
    
    function jump_to_position(slider::UISlider, mousePos::Math.Vector2, sliderPos::Math.Vector2)
        # Use the new set_slider_value function that calculates from mouse position
        set_slider_value(slider, mousePos)
    end
    
    function update_value_from_mouse(slider::UISlider, mousePos::Math.Vector2, sliderPos::Math.Vector2)
        # Center-based mapping in set_slider_value. Horizontal uses only x; vertical only y.
        if slider.barImage === nothing
            return
        end
        barPos = slider.barImage.position
        if slider.direction == Horizontal
            set_slider_value(slider, Math.Vector2(mousePos.x, barPos.y))
        elseif slider.direction == Vertical
            set_slider_value(slider, Math.Vector2(barPos.x, mousePos.y))
        else
            set_slider_value(slider, mousePos)
        end
    end
    
end  # module
