module UIDropdownModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule
    using JulGame.Math
    using JulGame.FX.ImageFXModule
    include("UISlider.jl")
    using .UISliderModule
    
    export UIDropdown, DropdownItem, update_dropdown, render_dropdown, add_dropdown_item
    
    # Represents a single item in the dropdown
    mutable struct DropdownItem
        id::String
        text::String
        value::Any
        isSelected::Bool
        isActive::Bool
        image::Union{JulGame.UI.UIImageModule.UIImage, Nothing}
        position::Math.Vector2
        size::Math.Vector2
    end
    
    mutable struct UIDropdown
        id::String
        position::Math.Vector2
        size::Math.Vector2
        isOpen::Bool
        isActive::Bool
        layer::Int
        
        # Items
        items::Vector{DropdownItem}
        selectedIndex::Int
        maxVisibleItems::Int
        
        # Visual properties
        closedImage          # Main dropdown button when closed
        itemImagePath        # Path to item background image (ui-dropdownitem-0000.png)
        scrollbarImage      # Scrollbar background
        scrollbarKnobImage  # Scrollbar knob
        
        # Scrollbar
        scrollbar::Union{UISlider, Nothing}
        scrollOffset::Float64
        itemHeight::Float64
        
        # Anchor properties
        anchor::Symbol
        anchorOffset::Math.Vector2
        
        # Visual effects properties
        showOutline::Bool
        outlineColor::NTuple{4, Int}
        outlineThickness::Int
        glowOnHover::Bool
        glowOnClick::Bool
        
        # Callback functions
        onValueChanged::Union{Function, Nothing}
        onItemSelected::Union{Function, Nothing}
        
        function UIDropdown(
            id::String;
            position::Math.Vector2 = Math.Vector2(0, 0),
            size::Math.Vector2 = Math.Vector2(200, 30),
            isOpen::Bool = false,
            isActive::Bool = true,
            layer::Int = 10,
            maxVisibleItems::Int = 5,
            closedImage = nothing,
            itemImagePath = JulGame.UserGlobals["Module"].get_asset_path("ui", "dropdownitem"),
            scrollbarImage = nothing,
            scrollbarKnobImage = nothing,
            anchor::Symbol = :none,
            anchorOffset::Math.Vector2 = Math.Vector2(0, 0),
            showOutline::Bool = false,
            outlineColor::NTuple{4, Int} = (255, 255, 255, 128),
            outlineThickness::Int = 2,
            glowOnHover::Bool = true,
            glowOnClick::Bool = true,
            onValueChanged::Union{Function, Nothing} = nothing,
            onItemSelected::Union{Function, Nothing} = nothing
        )
            this = new()
            
            this.id = id
            this.position = position
            this.size = size
            this.isOpen = isOpen
            this.isActive = isActive
            this.layer = layer
            this.maxVisibleItems = maxVisibleItems
            this.anchor = anchor
            this.anchorOffset = anchorOffset
            this.showOutline = showOutline
            this.outlineColor = outlineColor
            this.outlineThickness = outlineThickness
            this.glowOnHover = glowOnHover
            this.glowOnClick = glowOnClick
            this.onValueChanged = onValueChanged
            this.onItemSelected = onItemSelected
            
            # Initialize items
            this.items = DropdownItem[]
            this.selectedIndex = 1
            this.scrollOffset = 0.0
            this.itemHeight = 25.0
            
            # Get UI elements by ID
            if closedImage !== nothing
                this.closedImage = JulGame.SceneModule.get_ui_element_by_id(closedImage)
                this.position = this.closedImage.position
                this.size = this.closedImage.size
                this.closedImage.forceClickCheck = true
                # Sync layer to the closed image so option items always sit above it,
                # even when the host scene bumps the closed image's layer post-construction
                # (e.g. SettingsDisplayManager adds +1000 to "SettingsMenu_*" elements).
                this.layer = max(this.layer, this.closedImage.layer)
                @debug "Dropdown $(id) - closedImage ID: $closedImage, found: $(this.closedImage !== nothing)"
            else
                this.closedImage = nothing
                @debug "Dropdown $(id) - no closedImage provided"
            end
            
            
            this.itemImagePath = itemImagePath
            @debug "Dropdown $(id) - itemImagePath: $itemImagePath"
            
            if scrollbarImage !== nothing && scrollbarKnobImage !== nothing
                # Create scrollbar slider
                this.scrollbar = UISlider(
                    "$(id)_scrollbar";
                    position = Math.Vector2(0, 0),
                    size = Math.Vector2(15, size.y - 2),
                    knobSize = Math.Vector2(15, 20),
                    direction = Vertical,
                    value = 0.0,
                    minValue = 0.0,
                    maxValue = 1.0,
                    barImage = scrollbarImage,
                    knobImage = scrollbarKnobImage,
                    isActive = false,  # Initially hidden
                    layer = layer + 1
                )
                @debug "Dropdown $(id) - scrollbar created"
            else
                this.scrollbar = nothing
                @debug "Dropdown $(id) - no scrollbar images provided"
            end

            clickEvent = () -> begin
                # Handle main dropdown button click
                this.isOpen = !this.isOpen
                
                # Show/hide scrollbar
                if this.scrollbar !== nothing
                    this.scrollbar.isActive = this.isOpen && length(this.items) > this.maxVisibleItems
                end
            end
            # Match checkboxes: engine click events on the hit target.
            JulGame.UI.add_click_event(this.closedImage, clickEvent)
            
            return this
        end
    end

    @inline function _ignore_text_input!(text)
        text === nothing && return
        try
            text.ignoreInputEvents = true
        catch
        end
    end
    
    """
    Update dropdown logic - handles mouse input and interactions
    """
    function update_dropdown(dropdown::UIDropdown, deltaTime::Float64)
        if !dropdown.isActive
            @debug "Dropdown $(dropdown.id) inactive"
            return
        end
        
        mousePos = MAIN.input.mousePosition
        
        # Handle dropdown panel interactions when open
        if dropdown.isOpen
            update_dropdown_panel(dropdown, mousePos, deltaTime)
        end
        
        # Update scrollbar if it exists and is active
        if dropdown.scrollbar !== nothing && dropdown.scrollbar.isActive
            update_slider(dropdown.scrollbar, deltaTime)
            render_slider(dropdown.scrollbar)
            
            # Update scroll offset based on scrollbar value
            maxScroll = max(0.0, length(dropdown.items) - dropdown.maxVisibleItems)
            dropdown.scrollOffset = get_slider_value(dropdown.scrollbar) * maxScroll
        end
    end
    
    """
    Close the panel when clicking outside. Item selection uses clickEvents on the images.
    """
    function update_dropdown_panel(dropdown::UIDropdown, mousePos::Math.Vector2, deltaTime::Float64)
        if length(dropdown.items) == 0
            return
        end
        
        # Calculate which items are visible
        startIndex = Int(floor(dropdown.scrollOffset)) + 1
        endIndex = min(startIndex + dropdown.maxVisibleItems - 1, length(dropdown.items))
        
        mouseInDropdownArea = false
        didClick = JulGame.InputModule.get_mouse_button_pressed(1)
        for i in startIndex:endIndex
            item = dropdown.items[i]
            if item.image !== nothing && item.image.isHovered
                mouseInDropdownArea = true
                break
            end
        end
        if dropdown.closedImage !== nothing && dropdown.closedImage.isHovered
            mouseInDropdownArea = true
        end
        # Close dropdown if clicking outside any item
        if didClick && !mouseInDropdownArea
            @debug "Dropdown $(dropdown.id) closed"
            dropdown.isOpen = false
            if dropdown.scrollbar !== nothing
                dropdown.scrollbar.isActive = false
            end
        end
    end
    
    """
    Render the dropdown using scene UI elements
    """
    function render_dropdown(dropdown::UIDropdown)
        if !dropdown.isActive || dropdown.closedImage === nothing
            @warn "Cannot render dropdown $(dropdown.id) - inactive or no closed image"
            return
        end
        
        # Show text of the selected item inside the closed image
        if dropdown.selectedIndex >= 1 && dropdown.selectedIndex <= length(dropdown.items)
            closed_text = DisplayTextModule.display_text(
                "$(dropdown.id)_closed_image_text",
                dropdown.items[dropdown.selectedIndex].text;
                parent = dropdown.closedImage,
                anchor = :center,
                anchorOffset = Math.Vector2(0, 0),
                layer = dropdown.layer + 1,
                fontSize = 48
            )
            # Labels must not steal clicks from the closed image / option rows.
            _ignore_text_input!(closed_text)
        end

        # Render main dropdown button
        apply_visual_effects(dropdown, dropdown.closedImage)
        
        # Render dropdown panel when open
        if dropdown.isOpen
            render_dropdown_panel(dropdown)
        else
            # Hide all items
            for item in dropdown.items
                if item.image !== nothing
                    item.image.isActive = false
                end
            end
        end
    end
    
    """
    Render the dropdown items
    """
    function render_dropdown_panel(dropdown::UIDropdown)
        if length(dropdown.items) == 0
            return
        end
        
        dropdownPos = get_final_position(dropdown)
        
        # Calculate which items are visible based on scroll offset
        startIndex = Int(floor(dropdown.scrollOffset)) + 1
        endIndex = min(startIndex + dropdown.maxVisibleItems - 1, length(dropdown.items))
        
        # Hide all items first
        for item in dropdown.items
            if item.image !== nothing
                item.image.isActive = false
            end
        end
        
        # Show and position visible items
        for i in startIndex:endIndex
            item = dropdown.items[i]
            visibleIndex = i - startIndex + 1
            
            # Calculate item position - stack them vertically below the dropdown button
            itemPos = Math.Vector2(
                dropdownPos.x - 10,
                dropdownPos.y + item.size.y + (visibleIndex - 1) * item.size.y
            )
            
            # Update item image position and show it
            if item.image !== nothing
                item.image.position = itemPos
                item.image.isActive = true
                
                # Apply visual effects for selected items
                if item.isSelected
                    # You could add special effects here, like different color or outline
                    item.image.color = (255, 255, 200, 255)  # Slightly yellow tint
                else
                    item.image.color = (255, 255, 255, 255)  # Normal white
                end
            end
            
            # Render item text (using immediate UI)
            item_text = DisplayTextModule.display_text(
                "$(dropdown.id)_item_$(i)_text",
                item.text;
                parent = item.image,
                anchor = :center,
                anchorOffset = Math.Vector2(0, 0),
                layer = dropdown.layer + 6,
                fontSize = 48
            )
            _ignore_text_input!(item_text)
        end
        
        # Position and show scrollbar if needed
        if dropdown.scrollbar !== nothing && dropdown.scrollbar.isActive
            scrollbarPos = Math.Vector2(
                dropdownPos.x + dropdown.size.x - 15,
                dropdownPos.y + dropdown.size.y + 1
            )
            dropdown.scrollbar.position = scrollbarPos
        end
    end
    
    """
    Apply visual effects like outlines and glows to the dropdown
    """
    function apply_visual_effects(dropdown::UIDropdown, imageElement)
        if imageElement === nothing || !imageElement.isActive
            return
        end
        
        shouldGlow = false
        glowColor = dropdown.outlineColor
        
        # Determine if we should show glow effects
        if imageElement.isHovered && dropdown.glowOnHover
            shouldGlow = true
            glowColor = (100, 200, 255, 150)  # Blue glow when hovering
        elseif dropdown.showOutline
            shouldGlow = true
            glowColor = dropdown.outlineColor
        end
    end
    
    """
    Select a dropdown item by index
    """
    function select_dropdown_item(dropdown::UIDropdown, index::Int, triggerCallbacks::Bool = true)
        if index < 1 || index > length(dropdown.items)
            @debug "Dropdown $(dropdown.id) - invalid item index: $index"
            return
        end
        
        oldIndex = dropdown.selectedIndex
        
        # Deselect old item
        if oldIndex >= 1 && oldIndex <= length(dropdown.items)
            dropdown.items[oldIndex].isSelected = false
        end
        
        # Select new item
        dropdown.selectedIndex = index
        dropdown.items[index].isSelected = true
        
        # Close dropdown
        dropdown.isOpen = false
        if dropdown.scrollbar !== nothing
            dropdown.scrollbar.isActive = false
        end
        
        @debug "Dropdown $(dropdown.id) - selected item $index: $(dropdown.items[index].text)"
        
        # Call callbacks
        if dropdown.onValueChanged !== nothing && triggerCallbacks
            dropdown.onValueChanged(dropdown, dropdown.items[index].value)
        end
        
        if dropdown.onItemSelected !== nothing && triggerCallbacks
            dropdown.onItemSelected(dropdown, dropdown.items[index])
        end
    end
    
    """
    Add an item to the dropdown
    """
    function add_dropdown_item(dropdown::UIDropdown, text::String, value::Any; isSelected::Bool = false)
        itemId = "$(dropdown.id)_item_$(length(dropdown.items) + 1)"
        
        # Create a new UI image for this item
        itemImage = JulGame.UI.UIImageModule.UIImage(
            dropdown.itemImagePath;
            id = itemId,
            position = Math.Vector2(0, 0),
            layer = dropdown.layer + 5,
            size = Math.Vector2(dropdown.size.x, dropdown.size.y),
            forceClickCheck = true,
            isActive = false  # Initially hidden
        )
        
        # Add the image to the scene
        push!(MAIN.scene.uiElements, itemImage)
        
        item = DropdownItem(
            itemId,
            text,
            value,
            isSelected,
            false,  # Initially hidden
            itemImage,
            Math.Vector2(0, 0),
            Math.Vector2(itemImage.size.x, itemImage.size.y)
        )
        
        push!(dropdown.items, item)

        # Select via clickEvents (same path as checkboxes), not hover+poll.
        JulGame.UI.add_click_event(itemImage, () -> begin
            idx = findfirst(it -> it.image === itemImage, dropdown.items)
            idx !== nothing && select_dropdown_item(dropdown, idx)
        end)
        
        # If this is the first item or explicitly selected, select it
        if isSelected
            select_dropdown_item(dropdown, length(dropdown.items), false)
        end
        
        # Update scrollbar max value
        if dropdown.scrollbar !== nothing
            maxScroll = max(0.0, length(dropdown.items) - dropdown.maxVisibleItems)
            dropdown.scrollbar.maxValue = maxScroll
        end
        
        @debug "Dropdown $(dropdown.id) - added item: $text with image ID: $itemId"
    end
    
    # Helper functions
    
    function get_final_position(dropdown::UIDropdown)
        return dropdown.position
    end
    
    
end  # module

