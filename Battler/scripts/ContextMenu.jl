module ContextMenuModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts

    export ContextMenuItem, ContextMenuStyle, ContextMenuManager, open_context_menu, close_context_menu, update_context_menu

    """
    Represents a single item in a context menu
    """
    struct ContextMenuItem
        text::String
        action::Function
        icon::Union{Nothing, String}
        disabled::Bool
        is_separator::Bool
        
        function ContextMenuItem(;
            text::String = "",
            action::Function = () -> nothing,
            icon::Union{Nothing, String} = nothing,
            disabled::Bool = false,
            is_separator::Bool = false
        )
            new(text, action, icon, disabled, is_separator)
        end
    end

    """
    Style configuration for context menus
    """
    struct ContextMenuStyle
        bgColor::Tuple{Int, Int, Int, Int}
        borderWidth::Int
        borderColor::Tuple{Int, Int, Int, Int}
        borderRadius::Int
        fontSize::Int
        itemHeight::Int
        itemPadding::Int
        minWidth::Int
        hoverColor::Tuple{Int, Int, Int, Int}
        clickColor::Tuple{Int, Int, Int, Int}
        disabledColor::Tuple{Int, Int, Int, Int}
        separatorColor::Tuple{Int, Int, Int, Int}
        separatorHeight::Int
        iconSize::Int
        
        function ContextMenuStyle(;
            bgColor::Tuple{Int, Int, Int, Int} = (60, 60, 60, 230),
            borderWidth::Int = 2,
            borderColor::Tuple{Int, Int, Int, Int} = (100, 100, 100, 255),
            borderRadius::Int = 4,
            fontSize::Int = 18,
            itemHeight::Int = 30,
            itemPadding::Int = 10,
            minWidth::Int = 150,
            hoverColor::Tuple{Int, Int, Int, Int} = (80, 120, 160, 255),
            clickColor::Tuple{Int, Int, Int, Int} = (100, 140, 180, 255),
            disabledColor::Tuple{Int, Int, Int, Int} = (100, 100, 100, 150),
            separatorColor::Tuple{Int, Int, Int, Int} = (80, 80, 80, 255),
            separatorHeight::Int = 2,
            iconSize::Int = 20
        )
            new(bgColor, borderWidth, borderColor, borderRadius, fontSize, itemHeight, 
                itemPadding, minWidth, hoverColor, clickColor, disabledColor, 
                separatorColor, separatorHeight, iconSize)
        end
    end

    """
    Manager for handling context menu state and rendering
    """
    mutable struct ContextMenuManager
        isOpen::Bool
        menuId::String
        items::Vector{ContextMenuItem}
        position::Math.Vector2
        style::ContextMenuStyle
        hoveredIndex::Int
        clickedIndex::Int
        menuWidth::Int
        menuHeight::Int
        justOpened::Bool
        
        function ContextMenuManager()
            new(false, "", ContextMenuItem[], Math.Vector2(0, 0), ContextMenuStyle(), 
                0, 0, 0, 0, false)
        end
    end

    # Global instance for convenience
    global_context_menu = nothing

    function get_global_context_menu()
        global global_context_menu
        if global_context_menu === nothing
            global_context_menu = ContextMenuManager()
        end
        return global_context_menu
    end

    """
    Open a context menu with the specified items and styling
    
    # Arguments
    - `menu_id::String`: Unique identifier for this menu
    - `items::Vector{ContextMenuItem}`: Menu items to display
    - `position::Union{Nothing, Math.Vector2}`: Position to display menu (nothing = mouse position)
    - `style::ContextMenuStyle`: Styling configuration
    - `manager::Union{Nothing, ContextMenuManager}`: Manager instance (nothing = use global)
    """
    function open_context_menu(
        menu_id::String,
        items::Vector{ContextMenuItem};
        position::Union{Nothing, Math.Vector2} = nothing,
        style::ContextMenuStyle = ContextMenuStyle(),
        manager::Union{Nothing, ContextMenuManager} = nothing
    )
        @debug "open_context_menu"
        mgr = manager === nothing ? get_global_context_menu() : manager
        
        # Use mouse position if not specified
        menu_pos = position === nothing ? Math.Vector2(MAIN.input.mousePosition.x, MAIN.input.mousePosition.y) : position
        
        # Calculate menu dimensions
        menu_width, menu_height = calculate_menu_dimensions(items, style)
        
        # Ensure menu stays on screen
        screen_width = 1920  # TODO: Get from engine
        screen_height = 1080
        
        if menu_pos.x + menu_width > screen_width
            menu_pos = Math.Vector2(screen_width - menu_width - 5, menu_pos.y)
        end
        if menu_pos.y + menu_height > screen_height
            menu_pos = Math.Vector2(menu_pos.x, screen_height - menu_height - 5)
        end
        
        # Ensure menu doesn't go off left/top edges
        menu_pos = Math.Vector2(max(5, menu_pos.x), max(5, menu_pos.y))
        
        mgr.isOpen = true
        mgr.menuId = menu_id
        mgr.items = items
        mgr.position = menu_pos
        mgr.style = style
        mgr.hoveredIndex = 0
        mgr.clickedIndex = 0
        mgr.menuWidth = menu_width
        mgr.menuHeight = menu_height
        mgr.justOpened = true
        
        return mgr
    end

    """
    Close the context menu
    """
    function close_context_menu(manager::Union{Nothing, ContextMenuManager} = nothing)
        @debug "close_context_menu"
        mgr = manager === nothing ? get_global_context_menu() : manager
        mgr.isOpen = false
        mgr.hoveredIndex = 0
        mgr.clickedIndex = 0
    end

    """
    Calculate the dimensions needed for the menu
    """
    function calculate_menu_dimensions(items::Vector{ContextMenuItem}, style::ContextMenuStyle)
        width = style.minWidth
        height = style.itemPadding * 2
        
        for item in items
            if item.is_separator
                height += style.separatorHeight + 4
            else
                height += style.itemHeight
            end
        end
        
        return (width, height)
    end

    """
    Check if a click occurred on any menu item and handle it
    Returns true if an item was clicked (menu will be closed)
    """
    function check_item_clicks(mgr::ContextMenuManager, ignore_clicks::Bool = false)
        # Ignore clicks on the frame the menu was just opened
        if ignore_clicks
            return false
        end
        
        if !JulGame.InputModule.get_mouse_button_pressed(1)
            return false
        end
        @debug "check_item_clicks"
        
        mouse_pos = MAIN.input.mousePosition
        style = mgr.style
        current_y = mgr.position.y + style.itemPadding
        
        for (index, item) in enumerate(mgr.items)
            if item.is_separator
                current_y += style.separatorHeight + 4
                continue
            end
            
            if item.disabled
                current_y += style.itemHeight
                continue
            end
            
            # Check if mouse is over this item
            item_rect_x = mgr.position.x
            item_rect_y = current_y
            item_rect_width = mgr.menuWidth
            item_rect_height = style.itemHeight
            
            is_hovered = mouse_pos.x >= item_rect_x && 
                        mouse_pos.x <= item_rect_x + item_rect_width &&
                        mouse_pos.y >= item_rect_y && 
                        mouse_pos.y <= item_rect_y + item_rect_height
            
            if is_hovered
                mgr.clickedIndex = index
                # Execute action and close menu
                try
                    item.action()
                catch e
                    @error "Error executing context menu action: $(e)"
                end
                close_context_menu(mgr)
                return true
            end
            
            current_y += style.itemHeight
        end
        
        return false
    end

    """
    Update and draw the context menu (call this each frame)
    """
    function update_context_menu(manager::Union{Nothing, ContextMenuManager} = nothing)
        mgr = manager === nothing ? get_global_context_menu() : manager
        
        if !mgr.isOpen
            return
        end
        
        # Track if we should ignore clicks this frame (first frame after opening)
        should_ignore_clicks = mgr.justOpened
        
        # Reset justOpened flag after first frame
        if mgr.justOpened
            mgr.justOpened = false
        end
        
        # Check for clicks on menu items first
        if check_item_clicks(mgr, should_ignore_clicks)
            return
        end
        
        # Check for clicks outside menu to close (any mouse button)
        # Also ignore on first frame to prevent immediate closing
        mouse_pos = MAIN.input.mousePosition
        if !should_ignore_clicks && (JulGame.InputModule.get_mouse_button_pressed(1) || JulGame.InputModule.get_mouse_button_pressed(2))
            if !is_point_in_menu(mouse_pos, mgr)
                close_context_menu(mgr)
                return
            end
        end
        
        # Draw the menu
        draw_context_menu(mgr)
    end

    """
    Check if a point is inside the menu bounds
    """
    function is_point_in_menu(point::Math.Vector2, mgr::ContextMenuManager)
        return point.x >= mgr.position.x && 
               point.x <= mgr.position.x + mgr.menuWidth &&
               point.y >= mgr.position.y && 
               point.y <= mgr.position.y + mgr.menuHeight
    end

    """
    Draw the context menu
    """
    function draw_context_menu(mgr::ContextMenuManager)
        style = mgr.style
        
        # Draw background
        menu_bg = JulGame.ImmediateUIModule.immediate_rect(
            "$(mgr.menuId)_bg";
            position = mgr.position,
            size = Math.Vector2(mgr.menuWidth, mgr.menuHeight),
            color = style.bgColor,
            borderWidth = style.borderWidth,
            borderColor = style.borderColor,
            borderRadius = style.borderRadius,
            layer = 500
        )
        
        # Draw menu items
        current_y = mgr.position.y + style.itemPadding
        mouse_pos = MAIN.input.mousePosition
        mgr.hoveredIndex = 0
        
        for (index, item) in enumerate(mgr.items)
            if item.is_separator
                # Draw separator
                separator_y = current_y + (style.separatorHeight ÷ 2)
                JulGame.ImmediateUIModule.immediate_rect(
                    "$(mgr.menuId)_sep_$(index)";
                    position = Math.Vector2(mgr.position.x + style.itemPadding, separator_y),
                    size = Math.Vector2(mgr.menuWidth - style.itemPadding * 2, style.separatorHeight),
                    color = style.separatorColor,
                    layer = 501
                )
                current_y += style.separatorHeight + 4
            else
                # Check if mouse is over this item
                item_rect_x = mgr.position.x
                item_rect_y = current_y
                item_rect_width = mgr.menuWidth
                item_rect_height = style.itemHeight
                
                is_hovered = mouse_pos.x >= item_rect_x && 
                            mouse_pos.x <= item_rect_x + item_rect_width &&
                            mouse_pos.y >= item_rect_y && 
                            mouse_pos.y <= item_rect_y + item_rect_height 
                
                if is_hovered && !item.disabled
                    mgr.hoveredIndex = index
                end
                
                # Draw item background on hover
                if is_hovered && !item.disabled
                    item_color = mgr.clickedIndex == index ? style.clickColor : style.hoverColor
                    JulGame.ImmediateUIModule.immediate_rect(
                        "$(mgr.menuId)_hover_$(index)";
                        position = Math.Vector2(item_rect_x + 2, item_rect_y),
                        size = Math.Vector2(item_rect_width - 4, item_rect_height),
                        color = item_color,
                        borderRadius = style.borderRadius - 1,
                        layer = 501
                    )
                end
                
                # Draw icon if present
                text_offset_x = style.itemPadding
                if item.icon !== nothing
                    icon_x = mgr.position.x + style.itemPadding
                    icon_y = current_y + (style.itemHeight - style.iconSize) ÷ 2
                    
                    JulGame.ImmediateUIModule.immediate_image(
                        "$(mgr.menuId)_icon_$(index)",
                        item.icon;
                        position = Math.Vector2(icon_x, icon_y),
                        size = Math.Vector2(style.iconSize, style.iconSize),
                        layer = 502
                    )
                    
                    text_offset_x += style.iconSize + 5
                end
                
                # Draw text
                text_color = item.disabled ? style.disabledColor : (255, 255, 255, 255)
                DisplayTextModule.display_text(
                    "$(mgr.menuId)_text_$(index)",
                    item.text;
                    position = Math.Vector2(mgr.position.x + text_offset_x, current_y + (style.itemHeight - style.fontSize) ÷ 2),
                    fontSize = style.fontSize,
                    color = text_color,
                    layer = 502
                )
                
                
                current_y += style.itemHeight
            end
        end
    end
end

