module UICheckboxModule
    using JulGame
    using JulGame.Math
    using JulGame.FX.ImageFXModule
    
    export UICheckbox, render_checkbox, set_checkbox_value, toggle_checkbox
    
    mutable struct UICheckbox
        id::String
        position::Math.Vector2
        size::Math.Vector2
        isChecked::Bool
        isActive::Bool
        layer::Int
        
        # Visual properties
        checkedImage
        uncheckedImage
        
        # Anchor properties
        anchor::Symbol
        anchorOffset::Math.Vector2
        
        # Visual effects properties
        showOutline::Bool
        outlineColor::NTuple{4, Int}
        outlineThickness::Int
        glowOnHover::Bool
        glowOnClick::Bool
        
        # Callback function when value changes
        onValueChanged::Union{Function, Nothing}
        
        function UICheckbox(
            id::String;
            position::Math.Vector2 = Math.Vector2(0, 0),
            size::Math.Vector2 = Math.Vector2(20, 20),
            isChecked::Bool = false,
            checkedImage = nothing,
            uncheckedImage = nothing,
            isActive::Bool = true,
            layer::Int = 10,
            anchor::Symbol = :none,
            anchorOffset::Math.Vector2 = Math.Vector2(0, 0),
            showOutline::Bool = false,
            outlineColor::NTuple{4, Int} = (255, 255, 255, 128),
            outlineThickness::Int = 2,
            glowOnHover::Bool = true,
            glowOnClick::Bool = true,
            onValueChanged::Union{Function, Nothing} = nothing
        )
            this = new()
            
            this.id = id
            this.position = position
            this.size = size
            this.isChecked = isChecked
            this.isActive = isActive
            this.layer = layer
            this.anchor = anchor
            this.anchorOffset = anchorOffset
            this.showOutline = showOutline
            this.outlineColor = outlineColor
            this.outlineThickness = outlineThickness
            this.glowOnHover = glowOnHover
            this.glowOnClick = glowOnClick
            this.onValueChanged = onValueChanged
            
            # Get UI elements by ID
            if checkedImage !== nothing
                this.checkedImage = JulGame.SceneModule.get_ui_element_by_id(checkedImage)
                checkboxClickEvent = () -> toggle_checkbox(this)
                JulGame.UI.add_click_event(this.checkedImage, checkboxClickEvent)
                @debug "Checkbox $(id) - checkedImage ID: $checkedImage, found: $(this.checkedImage !== nothing)"
            else
                this.checkedImage = nothing
                @debug "Checkbox $(id) - no checkedImage provided"
            end
            
            if uncheckedImage !== nothing
                this.uncheckedImage = JulGame.SceneModule.get_ui_element_by_id(uncheckedImage)
                checkboxClickEvent = () -> toggle_checkbox(this)
                JulGame.UI.add_click_event(this.uncheckedImage, checkboxClickEvent)
                @debug "Checkbox $(id) - uncheckedImage ID: $uncheckedImage, found: $(this.uncheckedImage !== nothing)"
            else
                this.uncheckedImage = nothing
                @debug "Checkbox $(id) - no uncheckedImage provided"
            end
            
            return this
        end
    end
  
    """
    Render the checkbox using scene UI elements
    """
    function render_checkbox(checkbox::UICheckbox)
        if !checkbox.isActive
            @debug "Cannot render checkbox $(checkbox.id) - inactive"
            return
        end
        
        # Get the current visible image (checked or unchecked)
        currentImage = checkbox.isChecked ? checkbox.checkedImage : checkbox.uncheckedImage
        
        if currentImage === nothing
            @debug "Cannot render checkbox $(checkbox.id) - no current image"
            return
        end
        
        # Hide the other image
        if checkbox.isChecked && checkbox.uncheckedImage !== nothing
            checkbox.uncheckedImage.isActive = false
        elseif !checkbox.isChecked && checkbox.checkedImage !== nothing
            checkbox.checkedImage.isActive = false
        end
        
        # Show the current image
        currentImage.isActive = true
        
        # Apply visual effects
        apply_visual_effects(checkbox, currentImage)
    end
    
    """
    Apply visual effects like outlines and glows to the checkbox
    """
    function apply_visual_effects(checkbox::UICheckbox, imageElement)
        if imageElement === nothing || !imageElement.isActive
            return
        end
        
        shouldGlow = false
        glowColor = checkbox.outlineColor
        
        # Determine if we should show glow effects
        if imageElement.isHovered && checkbox.glowOnHover
            shouldGlow = true
            glowColor = (100, 200, 255, 150)  # Blue glow when hovering
        elseif checkbox.showOutline
            shouldGlow = true
            glowColor = checkbox.outlineColor
        end
    end
    
    """
    Set the checkbox value directly
    """
    function set_checkbox_value(checkbox::UICheckbox, value::Bool)
        oldValue = checkbox.isChecked
        checkbox.isChecked = value
        
        @debug "Set checkbox $(checkbox.id) value - old: $oldValue, new: $value"
        
        # Call callback if value changed
        if checkbox.onValueChanged !== nothing && checkbox.isChecked != oldValue
            @debug "Calling value changed callback for checkbox $(checkbox.id)"
            checkbox.onValueChanged(checkbox, checkbox.isChecked)
        end
    end
    
    """
    Toggle the checkbox value
    """
    function toggle_checkbox(checkbox::UICheckbox)
        set_checkbox_value(checkbox, !checkbox.isChecked)
    end
    
    # Helper functions
    
    function get_final_position(checkbox::UICheckbox)
        # Apply anchor positioning (simplified - could be expanded)
        basePos = checkbox.position + checkbox.anchorOffset
        
        if checkbox.anchor == :center
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x / 2 + basePos.x - checkbox.size.x / 2,
                windowSize.y / 2 + basePos.y - checkbox.size.y / 2
            )
        elseif checkbox.anchor == :centerTop
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x / 2 + basePos.x - checkbox.size.x / 2,
                basePos.y
            )
        elseif checkbox.anchor == :centerBottom
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x / 2 + basePos.x - checkbox.size.x / 2,
                windowSize.y + basePos.y - checkbox.size.y
            )
        elseif checkbox.anchor == :topLeft
            return basePos
        elseif checkbox.anchor == :topRight
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x + basePos.x - checkbox.size.x,
                basePos.y
            )
        elseif checkbox.anchor == :bottomLeft
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                basePos.x,
                windowSize.y + basePos.y - checkbox.size.y
            )
        elseif checkbox.anchor == :bottomRight
            windowSize = JulGame.get_window_size()
            return Math.Vector2(
                windowSize.x + basePos.x - checkbox.size.x,
                windowSize.y + basePos.y - checkbox.size.y
            )
        else
            return basePos
        end
    end
    
end  # module

