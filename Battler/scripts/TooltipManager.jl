module TooltipManagerModule
    using JulGame
    using JulGame.SDL2
    using ..Scripts

    include("utils/DisplayText.jl")
    using .DisplayTextModule

    export TooltipManager, register_tooltip_area, check_tooltip_hovers, set_tooltip_style

    const TITLE_COLOR = (255, 82, 96, 255)
    const TITLE_UNDERLINE_HEIGHT = 3
    # A line starting with `{icon:<asset path>}` draws that image before the line's text.
    const ICON_TOKEN = r"^\{icon:([^}]+)\}[ \t]*"m
    const ICON_GAP = 6

    mutable struct TooltipArea
        id::String
        x::Number
        y::Number
        width::Number
        height::Number
        text::String
        hoverStartTime::UInt64
        isHovered::Bool

        TooltipArea(id::String, x::Number, y::Number, width::Number, height::Number, text::String) = new(
            id, x, y, width, height, text, UInt64(0), false
        )
    end

    mutable struct TooltipManager <: Script
        parent # Reference to the entity this script is attached to
        tooltipAreas::Dict{String, TooltipArea}
        tooltipItems::Dict
        activeTooltip
        hoverDelay::UInt64 # Delay in milliseconds before showing tooltip

        # Tooltip appearance customization
        bgColor::NTuple{4, Int}
        textColor::NTuple{4, Int}
        borderColor::NTuple{4, Int}
        fontSize::Int
        padding::Int
        maxWidth::Int
        fontName::String

        function TooltipManager()
            this = new()
            this.tooltipAreas = Dict{String, TooltipArea}()
            this.tooltipItems = Dict()
            this.activeTooltip = nothing
            this.hoverDelay = UInt64(120) # Default delay before showing tooltip

            # Default tooltip style
            this.bgColor = Scripts.NineSliceUIModule.DEFAULT_FILL_COLOR
            this.textColor = (255, 255, 255, 255)
            this.borderColor = Scripts.NineSliceUIModule.DEFAULT_PANEL_COLOR
            this.fontSize = 24
            this.padding = 15
            this.maxWidth = 300
            this.fontName = "Century-Normal.ttf"

            return this
        end
    end

    # Initialize the TooltipManager when added to a scene
    function JulGame.initialize(this::TooltipManager)
        @debug("TooltipManager initialized")
    end

    # Register an area that will trigger a tooltip
    function register_tooltip_area(this::TooltipManager, id::String, x::Number, y::Number,
                                  width::Number, height::Number, text::String)
        if haskey(this.tooltipAreas, id)
            #@warn("Tooltip area with id $id already registered. Overwriting.")
            this.tooltipAreas[id].x = x
            this.tooltipAreas[id].y = y
            this.tooltipAreas[id].width = width
            this.tooltipAreas[id].height = height
            this.tooltipAreas[id].text = text
        else
            this.tooltipAreas[id] = TooltipArea(id, x, y, width, height, text)
        end
        return this.tooltipAreas[id]
    end

    function deregister_tooltip_area(this::TooltipManager, id::String)
        delete!(this.tooltipAreas, id)
    end

    function register_tooltip_item(this::TooltipManager, item::Any, tooltipText::String)
        if haskey(this.tooltipItems, item)
            area = this.tooltipItems[item]
            area.text = tooltipText
            area.id = item.id
            return area
        end
        this.tooltipItems[item] = TooltipArea(item.id, 0, 0, 0, 0, tooltipText)
        @debug "Registered tooltip item: $(this.tooltipItems[item])"
        return this.tooltipItems[item]
    end

    function deregister_tooltip_item(this::TooltipManager, item::Any)
        delete!(this.tooltipItems, item)
    end

    function deregister_tooltip_item_by_id(this::TooltipManager, id::String)
        for (item, area) in this.tooltipItems
            @debug "Item: $(item.id)"
            @debug "ID: $(id)"
            if item.id == id
                @debug "Deregistered tooltip item: $(id)"
                delete!(this.tooltipItems, item)
                return
            end
        end
    end

    # Update tooltip styles
    function set_tooltip_style(this::TooltipManager;
                              bgColor::Union{NTuple{4, Int}, Nothing}=nothing,
                              textColor::Union{NTuple{4, Int}, Nothing}=nothing,
                              borderColor::Union{NTuple{4, Int}, Nothing}=nothing,
                              fontSize::Union{Int, Nothing}=nothing,
                              padding::Union{Int, Nothing}=nothing,
                              maxWidth::Union{Int, Nothing}=nothing,
                              fontName::Union{String, Nothing}=nothing,
                              hoverDelay::Union{UInt64, Nothing}=nothing)

        if bgColor !== nothing
            this.bgColor = bgColor
        end
        if textColor !== nothing
            this.textColor = textColor
        end
        if borderColor !== nothing
            this.borderColor = borderColor
        end
        if fontSize !== nothing
            this.fontSize = fontSize
        end
        if padding !== nothing
            this.padding = padding
        end
        if maxWidth !== nothing
            this.maxWidth = maxWidth
        end
        if fontName !== nothing
            this.fontName = fontName
        end
        if hoverDelay !== nothing
            this.hoverDelay = hoverDelay
        end
    end

    # Check if mouse is over any registered tooltip areas
    function check_tooltip_hovers(this::TooltipManager)
        mousePosition = MAIN.input.mousePosition
        currentTime = SDL2.SDL_GetTicks()
        hoveredAny = false

        for (item, area) in this.tooltipItems
            isInside = item.isHovered && item.isActive
            if isInside
                hoveredAny = true
                if !area.isHovered
                    area.isHovered = true
                    area.hoverStartTime = currentTime
                elseif currentTime - area.hoverStartTime >= this.hoverDelay
                    display_tooltip(this, area, mousePosition; id = item.id)
                end
            else
                area.isHovered = false
            end
        end

        mx = mousePosition.x
        my = mousePosition.y
        for (_, area) in this.tooltipAreas
            isInside = mx >= area.x && mx <= area.x + area.width &&
                       my >= area.y && my <= area.y + area.height
            if isInside
                hoveredAny = true
                if !area.isHovered
                    area.isHovered = true
                    area.hoverStartTime = currentTime
                elseif currentTime - area.hoverStartTime >= this.hoverDelay
                    display_tooltip(this, area, mousePosition; id = area.id)
                end
            else
                area.isHovered = false
            end
        end

        if !hoveredAny && this.activeTooltip !== nothing
            this.activeTooltip = nothing
        end
    end

    function display_tooltip(this::TooltipManager, item::Any, mousePosition::Math.Vector2)
        display_tooltip(this, this.tooltipItems[item], mousePosition; id = item.id)
    end

    """
    Shop/inventory strings are `Name: body` on one line. Piece tooltips already
    use a newline after the name. Split the colon form so the title stays alone.
    """
    function _normalize_tooltip_text(text::String)::String
        occursin('\n', text) && return text
        sep = findfirst(": ", text)
        sep === nothing && return text
        title = strip(text[1:first(sep)-1])
        body = strip(text[last(sep)+1:end])
        (isempty(title) || isempty(body)) && return text
        return string(title, "\n", body)
    end

    # No font metrics are exposed to scripts; average glyph width of the tooltip font.
    _text_width(s::AbstractString, fontSize::Int)::Int = round(Int, length(s) * fontSize * 0.56)

    # Display a tooltip with improved boundary handling and custom geometry
    function display_tooltip(this::TooltipManager, area::TooltipArea, mousePosition::Math.Vector2; id::String = area.id)
        this.activeTooltip = id

        # Get logical size for boundary checking (mouse coords are in logical space)
        window_size = JulGame.WindowManagerModule.get_logical_size()

        # Get tooltip text and calculate dimensions
        tooltipText = _normalize_tooltip_text(area.text)

        # Break text into multiple lines - first split on explicit newlines, then wrap long lines
        lines = String[]
        lineIcons = Union{Nothing, String}[]
        maxLineWidth = 0
        iconWidth = this.fontSize + ICON_GAP

        # Split on explicit newlines first
        explicitLines = split(tooltipText, "\n")

        for explicitLine in explicitLines
            iconMatch = match(ICON_TOKEN, explicitLine)
            icon = iconMatch === nothing ? nothing : String(iconMatch.captures[1])
            icon === nothing || (explicitLine = replace(explicitLine, ICON_TOKEN => ""))
            words = split(explicitLine, " ")
            currentLine = ""
            lineWidth = icon === nothing ? 0 : iconWidth

            for word in words
                # Approximate word width
                candidate = currentLine == "" ? String(word) : currentLine * " " * word
                candidateWidth = (icon === nothing ? 0 : iconWidth) + _text_width(candidate, this.fontSize)

                if currentLine == "" || candidateWidth <= this.maxWidth
                    currentLine = candidate
                    lineWidth = candidateWidth
                else
                    push!(lines, currentLine)
                    push!(lineIcons, icon)
                    icon = nothing
                    maxLineWidth = max(maxLineWidth, lineWidth)
                    currentLine = String(word)
                    lineWidth = _text_width(currentLine, this.fontSize)
                end
            end

            if currentLine != ""
                push!(lines, currentLine)
                push!(lineIcons, icon)
                maxLineWidth = max(maxLineWidth, lineWidth)
            end
        end

        # Calculate tooltip dimensions based on actual content
        tooltipWidth = min(maxLineWidth, this.maxWidth) + 2 * this.padding
        tooltipHeight = length(lines) * (this.fontSize + 15) + 2 * this.padding

        # Ensure minimum width for short text
        tooltipWidth = max(tooltipWidth, 100)

        # Calculate tooltip position with improved boundary adjustments
        # Start with default position (to the right of cursor)
        tooltipX = mousePosition.x + 15
        tooltipY = mousePosition.y

        # Check right boundary - if tooltip would go off screen, try left side
        if tooltipX + tooltipWidth > window_size.x
            # Not enough space on right, try left side
            tooltipX = mousePosition.x - tooltipWidth - 10
        end

        # Ensure tooltip doesn't go off left edge
        if tooltipX < 0
            tooltipX = 5  # Small margin from left edge
        end

        # Ensure tooltip doesn't go off right edge (clamp to fit)
        if tooltipX + tooltipWidth > window_size.x
            tooltipX = window_size.x - tooltipWidth - 5  # Small margin from right edge
        end

        # Check vertical bounds - prefer below cursor, but go above if needed
        if mousePosition.y + tooltipHeight > window_size.y
            # Not enough space below, try above
            tooltipY = mousePosition.y - tooltipHeight - 10
        end

        # Ensure tooltip doesn't go off top edge
        if tooltipY < 0
            tooltipY = 5  # Small margin from top edge
        end

        # Ensure tooltip doesn't go off bottom edge (clamp to fit)
        if tooltipY + tooltipHeight > window_size.y
            tooltipY = window_size.y - tooltipHeight - 5  # Small margin from bottom edge
        end

        # Fill at 999, frame at 1000; contents sit above both.
        panel = Scripts.NineSliceUIModule.immediate_panel(
            "tooltip_bg_$(id)";
            position = Math.Vector2(tooltipX, tooltipY),
            size = Math.Vector2(tooltipWidth, tooltipHeight),
            color = this.bgColor,
            border_color = this.borderColor,
            layer = 999,
        )

        # Draw tooltip text, line by line — parented to the panel
        for (i, line) in enumerate(lines)
            lineY = tooltipY + this.padding + (i - 1) * (this.fontSize + 15)
            is_title = i == 1
            line_color = is_title ? TITLE_COLOR : this.textColor
            icon = lineIcons[i]
            textX = tooltipX + this.padding

            if icon !== nothing
                JulGame.ImmediateUIModule.immediate_image(
                    "tooltip_icon_$(id)_line_$(i)",
                    icon;
                    position = Math.Vector2(textX, lineY),
                    size = Math.Vector2(this.fontSize, this.fontSize),
                    layer = 1001,
                    parent = panel,
                )
                textX += iconWidth
            end

            DisplayTextModule.display_text(
                "tooltip_text_$(id)_line_$(i)",
                "$(line)";
                position = Math.Vector2(textX, lineY),
                layer = 1001,
                fontSize = this.fontSize,
                color = line_color,
                parent = panel,
            )

            if is_title && length(lines) > 1
                sep_w = max(1, tooltipWidth - 2 * this.padding)
                JulGame.ImmediateUIModule.immediate_rect(
                    "tooltip_title_underline_$(id)";
                    position = Math.Vector2(tooltipX + this.padding, lineY + this.fontSize + 10),
                    size = Math.Vector2(sep_w, TITLE_UNDERLINE_HEIGHT),
                    color = TITLE_COLOR,
                    layer = 1001,
                    parent = panel,
                )
            end
        end

        Scripts.KeywordGlossaryModule.draw_beside!(
            "tooltip_kw_$(id)",
            replace(tooltipText, ICON_TOKEN => ""),
            tooltipX,
            tooltipY,
            tooltipWidth,
            tooltipHeight;
            avoid_x = mousePosition.x,
        )
    end

    """True while matched pieces, intents, or the enemy turn are playing out."""
    function battle_board_in_action()::Bool
        try
            bm = JulGame.UserGlobals["Module"].get_data_manager().current_battle_manager
            bm === nothing && return false
            parent = bm.parent
            parent === nothing && return false
            on_battle_scene = false
            for e in MAIN.scene.entities
                if e === parent
                    on_battle_scene = true
                    break
                end
            end
            on_battle_scene || return false
            st = bm.currentState
            bs = bm.battleStates
            return st == bs[:switchingItems] || st == bs[:searchingForMatches] ||
                   st == bs[:replaceItems] || st == bs[:processTurn] ||
                   st == bs[:playerAction] || st == bs[:animatingIntents] ||
                   st == bs[:enemyTurn]
        catch
            return false
        end
    end

    # Update function called every frame
    function JulGame.update(this::TooltipManager, deltaTime)
        # Hover cards must not stay up over a resolving board.
        battle_board_in_action() && return
        check_tooltip_hovers(this)
    end

    # Cleanup when script is removed
    function JulGame.on_shutdown(this::TooltipManager)
        # Clear tooltip areas
        empty!(this.tooltipAreas)
        empty!(this.tooltipItems)
        this.activeTooltip = nothing
    end
end
