module DeveloperConsoleModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts

    # Global console instance for external access
    global ConsoleInstance = nothing

    mutable struct DeveloperConsole <: Script
        parent::Any
        
        # Console UI state
        isConsoleOpen::Bool
        consolePanelHeight::Int
        consolePanelWidth::Int
        consoleX::Int
        consoleY::Int
        
        # Input handling
        currentInput::String
        inputActive::Bool
        cursorPosition::Int
        
        # Command history
        commandHistory::Vector{String}
        historyPosition::Int
        maxHistorySize::Int
        
        # Output display
        outputLines::Vector{String}
        maxOutputLines::Int
        scrollOffset::Int
        
        # Auto-completion
        autoCompleteActive::Bool
        autoCompleteSuggestions::Vector{String}
        autoCompleteIndex::Int
        
        # Command registry
        commandRegistry::Dict{String, Any}
        commandCategories::Dict{String, Vector{String}}
        
        # UI styling
        backgroundColor::Tuple{Int, Int, Int, Int}
        textColor::Tuple{Int, Int, Int, Int}
        inputColor::Tuple{Int, Int, Int, Int}
        borderColor::Tuple{Int, Int, Int, Int}
        fontSize::Int
        padding::Int

        # Debug menu (panel beside console)
        debugMenuWidth::Int
        debugMenuGap::Int
        debugSectionOpen::Dict{String, Bool}

        user
        
        function DeveloperConsole()
            this = new()
            
            # Initialize UI state
            this.isConsoleOpen = false
            this.consolePanelHeight = 400
            this.consolePanelWidth = 1200
            this.consoleX = 50
            this.consoleY = 50
            
            # Initialize input
            this.currentInput = ""
            this.inputActive = false
            this.cursorPosition = 0
            
            # Initialize history
            this.commandHistory = String[]
            this.historyPosition = 0
            this.maxHistorySize = 50
            
            # Initialize output
            this.outputLines = String[]
            this.maxOutputLines = 100
            this.scrollOffset = 0
            
            # Initialize auto-completion
            this.autoCompleteActive = false
            this.autoCompleteSuggestions = String[]
            this.autoCompleteIndex = 0
            
            # Initialize command system
            this.commandRegistry = Dict{String, Any}()
            this.commandCategories = Dict{String, Vector{String}}()
            
            # Initialize styling
            this.backgroundColor = (20, 20, 30, 240)
            this.textColor = (255, 255, 255, 255)
            this.inputColor = (200, 200, 255, 255)
            this.borderColor = (100, 100, 150, 255)
            this.fontSize = 14
            this.padding = 10

            this.debugMenuWidth = 280
            this.debugMenuGap = 12
            this.debugSectionOpen = Dict{String, Bool}("patterns" => true)
            
            return this
        end
    end

    function JulGame.initialize(this::DeveloperConsole)
        global ConsoleInstance = this
        # start timer 
        @debug "Initializing DeveloperConsole"
        timer = time_ns()
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()
        
        # Register built-in commands
        register_built_in_commands(this)
        
        # Register all command categories
        try
            register_scene_commands(this)
            register_player_commands(this)
            register_inventory_commands(this)
        catch e
            @warn "Failed to register some command categories: $e"
        end
        
        # Add welcome message
        add_output_line(this, "Developer Console Initialized")
        add_output_line(this, "Type 'help' for available commands")
        add_output_line(this, "Press ~ (tilde) to toggle console")
        add_output_line(this, "")
        @debug "DeveloperConsole initialized in $((time_ns() - timer) / 1e9) seconds"
    end

    function JulGame.update(this::DeveloperConsole, deltaTime)
        # Open only in debug mode; always allow close (e.g. after F3 turns debug off)
        if JulGame.InputModule.get_button_pressed("BACKSLASH")
            if this.isConsoleOpen || JulGame.IS_DEBUG
                toggle_console(this)
            end
        end
        
        if this.isConsoleOpen
            handle_console_input(this)
            draw_console_ui(this)
        end
    end

    function JulGame.on_shutdown(this::DeveloperConsole)
        global ConsoleInstance = nothing
    end

    """
    Toggle the console open/closed
    """
    function toggle_console(this::DeveloperConsole)
        this.isConsoleOpen = !this.isConsoleOpen
        if this.isConsoleOpen
            this.inputActive = true
            this.cursorPosition = length(this.currentInput)
            this.autoCompleteActive = false
        else
            this.inputActive = false
        end
    end

    """
    Add a line to console output
    """
    function add_output_line(this::DeveloperConsole, line::String, color::Tuple{Int,Int,Int,Int} = (255,255,255,255))
        push!(this.outputLines, line)
        
        # Trim output if too many lines
        if length(this.outputLines) > this.maxOutputLines
            this.outputLines = this.outputLines[(end - this.maxOutputLines + 1):end]
        end
        
        # Auto-scroll to bottom
        this.scrollOffset = max(0, length(this.outputLines) - get_visible_lines(this))
    end

    """
    Handle console input (keyboard events)
    """
    function handle_console_input(this::DeveloperConsole)
        if !this.inputActive
           # @debug "Console is not active"
            return
        end
        
        # Handle special keys
        if JulGame.InputModule.get_button_pressed("Return")
            @debug "Enter pressed"
            execute_command(this, this.currentInput)
            add_to_history(this, this.currentInput)
            this.currentInput = ""
            this.cursorPosition = 0
            this.autoCompleteActive = false
            return
        end
        
        if JulGame.InputModule.get_button_pressed("Escape")
            @debug "Escape pressed"
            toggle_console(this)
            return
        end
        
        # Handle history navigation
        if JulGame.InputModule.get_button_pressed("Up")
            @debug "Up pressed"
            navigate_history(this, -1)
            return
        end
        
        if JulGame.InputModule.get_button_pressed("Down")
            @debug "Down pressed"
            navigate_history(this, 1)
            return
        end
        
        # Handle tab for auto-completion
        if JulGame.InputModule.get_button_pressed("Tab")
            @debug "Tab pressed"
            handle_auto_complete(this)
            return
        end
        
        # Handle backspace
        if JulGame.InputModule.get_button_pressed("Backspace")
            @debug "Backspace pressed"
            if this.cursorPosition > 0
                this.currentInput = this.currentInput[1:this.cursorPosition-1] * this.currentInput[this.cursorPosition+1:end]
                this.cursorPosition -= 1
                this.autoCompleteActive = false
            end
            return
        end
        
        # Handle delete
        if JulGame.InputModule.get_button_pressed("Delete")
            @debug "Delete pressed"
            if this.cursorPosition < length(this.currentInput)
                this.currentInput = this.currentInput[1:this.cursorPosition] * this.currentInput[this.cursorPosition+2:end]
                this.autoCompleteActive = false
            end
            return
        end
        
        # Handle left/right arrow keys for cursor movement
        if JulGame.InputModule.get_button_pressed("Left")
            @debug "Left pressed"
            this.cursorPosition = max(0, this.cursorPosition - 1)
            return
        end
        
        if JulGame.InputModule.get_button_pressed("Right")
            @debug "Right pressed"
            this.cursorPosition = min(length(this.currentInput), this.cursorPosition + 1)
            return
        end
        
        # Debug key detection - remove this once you figure out the right key names
        #debug_key_detection(this)
        
        # Handle text input
        # Note: In a real implementation, you'd need proper text input handling
        # This is a simplified version
        handle_text_input(this)
    end

    """
    Debug function to detect key names - remove once you figure out the right names
    """
    function debug_key_detection(this::DeveloperConsole)
        # Test common shift key names
        shift_keys = ["LSHIFT", "LEFTSHIFT", "SHIFT", "LEFT_SHIFT", "LShift"]
        minus_keys = ["MINUS", "DASH", "HYPHEN", "-", "SUBTRACT"]
        
        for shift_key in shift_keys
            if JulGame.InputModule.get_button_pressed(shift_key)
                @debug "Shift key detected: $(shift_key)"
            end
        end
        
        for minus_key in minus_keys
            if JulGame.InputModule.get_button_pressed(minus_key)
                @debug "Minus key detected: $(minus_key)"
            end
        end
        
        # Test the combination manually
        if JulGame.InputModule.get_button_pressed("LSHIFT") && JulGame.InputModule.get_button_pressed("MINUS")
            @debug "LSHIFT + MINUS detected manually"
        end
    end

    """
    Handle text input (simplified - would need proper JulGame text input API)
    """
    function handle_text_input(this::DeveloperConsole)
        # This is a placeholder - JulGame would need proper text input handling
        # For now, we'll simulate with key presses for demo purposes
        
        char_map = Dict(
            "A" => "a", "B" => "b", "C" => "c", "D" => "d", "E" => "e",
            "F" => "f", "G" => "g", "H" => "h", "I" => "i", "J" => "j",
            "K" => "k", "L" => "l", "M" => "m", "N" => "n", "O" => "o",
            "P" => "p", "Q" => "q", "R" => "r", "S" => "s", "T" => "t",
            "U" => "u", "V" => "v", "W" => "w", "X" => "x", "Y" => "y",
            "Z" => "z", "SPACE" => " ", "PERIOD" => ".", "LSHIFT,MINUS" => "_", "LEFTSHIFT,MINUS" => "_", "SHIFT,MINUS" => "_",
            "0" => "0", "1" => "1", "2" => "2", "3" => "3", "4" => "4",
            "5" => "5", "6" => "6", "7" => "7", "8" => "8", "9" => "9"
        )
        
        for (key_combo, char) in char_map
            split_keys = split(key_combo, ",")
            is_pressed = true
            count = 0
            for individual_key in split_keys
                count += 1
                key_name = strip(individual_key)
                is_key_pressed = (length(split_keys) == 1 || count > 1) ? JulGame.InputModule.get_button_pressed("$(key_name)") : JulGame.InputModule.get_button_held_down("$(key_name)")
                if !is_key_pressed
                    is_pressed = false
                    break
                end
            end
            if is_pressed
                # Debug output for key combinations
                if length(split_keys) > 1
                    @debug "Key combo pressed: $(key_combo) -> '$(char)'"
                end
                insert_char_at_cursor(this, char)
                break
            end
        end
    end

    """
    Insert character at cursor position
    """
    function insert_char_at_cursor(this::DeveloperConsole, char::String)
        this.currentInput = this.currentInput[1:this.cursorPosition] * char * this.currentInput[this.cursorPosition+1:end]
        this.cursorPosition += length(char)
        this.autoCompleteActive = false
    end

    """
    Draw the console UI
    """
    function draw_console_ui(this::DeveloperConsole)
        # Draw main console background
        console_bg = JulGame.ImmediateUIModule.immediate_rect(
            "console_background";
            position = Math.Vector2(this.consoleX, this.consoleY),
            size = Math.Vector2(this.consolePanelWidth, this.consolePanelHeight),
            color = this.backgroundColor,
            borderWidth = 2,
            borderColor = this.borderColor,
            borderRadius = 4,
            layer = 1000
        )
        
        # Draw title bar
        DisplayTextModule.display_text(
            "console_title",
            "Developer Console";
            position = Math.Vector2(this.consoleX + this.padding, this.consoleY + this.padding),
            fontSize = this.fontSize + 2,
            color = this.inputColor,
            layer = 1001,
            applyEffects = false,
        )
        
        # Draw output area
        draw_output_area(this, console_bg)
        
        # Draw input area
        draw_input_area(this, console_bg)
        
        # Draw auto-complete suggestions
        if this.autoCompleteActive
            draw_auto_complete(this, console_bg)
        end

        draw_debug_menu(this)
    end

    """
    Clickable debug panel docked to the right of the console.
    """
    function draw_debug_menu(this::DeveloperConsole)
        menu_x = this.consoleX + this.consolePanelWidth + this.debugMenuGap
        menu_y = this.consoleY
        menu_w = this.debugMenuWidth
        menu_h = this.consolePanelHeight
        PD = Scripts.PatternDebugModule

        JulGame.ImmediateUIModule.immediate_rect(
            "debug_menu_background";
            position = Math.Vector2(menu_x, menu_y),
            size = Math.Vector2(menu_w, menu_h),
            color = this.backgroundColor,
            borderWidth = 2,
            borderColor = this.borderColor,
            borderRadius = 4,
            layer = 1000
        )

        DisplayTextModule.display_text(
            "debug_menu_title",
            "Debug Menu";
            position = Math.Vector2(menu_x + this.padding, menu_y + this.padding),
            fontSize = this.fontSize + 2,
            color = this.inputColor,
            layer = 1001,
            applyEffects = false,
        )

        cursor_y = menu_y + this.padding + 28
        cursor_y = draw_debug_section_patterns(this, PD, menu_x, cursor_y, menu_w)
    end

    function is_debug_section_open(this::DeveloperConsole, id::String)::Bool
        return get(this.debugSectionOpen, id, false)
    end

    function toggle_debug_section!(this::DeveloperConsole, id::String)
        this.debugSectionOpen[id] = !is_debug_section_open(this, id)
    end

    function draw_debug_section_header(this::DeveloperConsole, id::String, title::String, x::Int, y::Int, width::Int)::Int
        open = is_debug_section_open(this, id)
        caret = open ? "▼" : "▶"
        Scripts.NineSliceUIModule.immediate_button(
            "debug_section_$(id)",
            () -> toggle_debug_section!(this, id);
            text = "$(caret)  $(title)",
            position = Math.Vector2(x + this.padding, y),
            size = Math.Vector2(width - this.padding * 2, 28),
            fontSize = this.fontSize,
            color = this.inputColor,
            layer = 1001,
            isCentered = false,
            forceClickCheck = true
        )
        return y + 32
    end

    function draw_debug_section_patterns(this::DeveloperConsole, PD, menu_x::Int, cursor_y::Int, menu_w::Int)::Int
        cursor_y = draw_debug_section_header(this, "patterns", "Patterns", menu_x, cursor_y, menu_w)
        if !is_debug_section_open(this, "patterns")
            return cursor_y
        end

        DisplayTextModule.display_text(
            "debug_patterns_hint",
            "Off = no new special piece";
            position = Math.Vector2(menu_x + this.padding, cursor_y),
            fontSize = this.fontSize - 2,
            color = (160, 160, 180, 255),
            layer = 1001,
            applyEffects = false,
        )
        cursor_y += 22

        for (kind, label) in PD.pattern_debug_entries()
            enabled = PD.is_pattern_creation_enabled(kind)
            status = enabled ? "ON" : "OFF"
            color = enabled ? (120, 220, 140, 255) : (200, 110, 110, 255)
            kind_capture = kind
            Scripts.NineSliceUIModule.immediate_button(
                "debug_pattern_toggle_$(Int(kind))",
                () -> PD.toggle_pattern_creation!(kind_capture);
                text = "[$(status)]  $(label)",
                position = Math.Vector2(menu_x + this.padding, cursor_y),
                size = Math.Vector2(menu_w - this.padding * 2, 28),
                fontSize = this.fontSize - 1,
                color = color,
                layer = 1001,
                isCentered = false,
                forceClickCheck = true
            )
            cursor_y += 32
        end

        return cursor_y
    end

    """
    Draw the output text area
    """
    function draw_output_area(this::DeveloperConsole, parent)
        output_height = this.consolePanelHeight - 80  # Leave space for input
        output_y = this.consoleY + 40
        visible_lines = get_visible_lines(this)
        
        # Calculate which lines to show based on scroll
        start_line = max(1, length(this.outputLines) - visible_lines - this.scrollOffset + 1)
        end_line = min(length(this.outputLines), start_line + visible_lines - 1)
        
        # Draw each visible line
        for i in start_line:end_line
            line_y = output_y + (i - start_line) * (this.fontSize + 2)
            DisplayTextModule.display_text(
                "console_output_$(i)",
                this.outputLines[i];
                position = Math.Vector2(this.consoleX + this.padding, line_y),
                fontSize = this.fontSize,
                color = this.textColor,
                layer = 1001,
                applyEffects = false,
            )
        end
    end

    """
    Draw the input area
    """
    function draw_input_area(this::DeveloperConsole, parent)
        input_y = this.consoleY + this.consolePanelHeight - 40
        
        # Draw input prompt
        DisplayTextModule.display_text(
            "console_prompt",
            "> ";
            position = Math.Vector2(this.consoleX + this.padding, input_y),
            fontSize = this.fontSize,
            color = this.inputColor,
            layer = 1001,
            applyEffects = false,
        )
        
        # Draw input text
        DisplayTextModule.display_text(
            "console_input",
            this.currentInput;
            position = Math.Vector2(this.consoleX + this.padding + 20, input_y),
            fontSize = this.fontSize,
            color = this.inputColor,
            layer = 1001,
            applyEffects = false,
        )
        
        # Draw cursor (simplified)
        if this.inputActive
            cursor_x = this.consoleX + this.padding + 20 + (this.cursorPosition * 8)  # Approximate character width
            DisplayTextModule.display_text(
                "console_cursor",
                "_";
                position = Math.Vector2(cursor_x, input_y),
                fontSize = this.fontSize,
                color = this.inputColor,
                layer = 1002,
                applyEffects = false,
            )
        end
    end

    """
    Draw auto-complete suggestions
    """
    function draw_auto_complete(this::DeveloperConsole, parent)
        if isempty(this.autoCompleteSuggestions)
            return
        end
        
        suggest_y = this.consoleY + this.consolePanelHeight - 80
        max_suggestions = min(5, length(this.autoCompleteSuggestions))
        
        # Draw suggestion background
        JulGame.ImmediateUIModule.immediate_rect(
            "autocomplete_bg";
            position = Math.Vector2(this.consoleX + this.padding, suggest_y - (max_suggestions * 20)),
            size = Math.Vector2(300, max_suggestions * 20),
            color = (40, 40, 50, 230),
            borderWidth = 1,
            borderColor = this.borderColor,
            layer = 1003
        )
        
        # Draw each suggestion
        for i in 1:max_suggestions
            suggestion = this.autoCompleteSuggestions[i]
            color = i == this.autoCompleteIndex + 1 ? (255, 255, 100, 255) : this.textColor
            
            DisplayTextModule.display_text(
                "autocomplete_$(i)",
                suggestion;
                position = Math.Vector2(this.consoleX + this.padding + 5, suggest_y - (i * 20)),
                fontSize = this.fontSize - 1,
                color = color,
                layer = 1004,
                applyEffects = false,
            )
        end
    end

    """
    Get number of visible output lines
    """
    function get_visible_lines(this::DeveloperConsole)
        available_height = this.consolePanelHeight - 80  # Subtract space for title and input
        return Int(floor(available_height / (this.fontSize + 2)))
    end

    """
    Add command to history
    """
    function add_to_history(this::DeveloperConsole, command::String)
        if !isempty(command) && (isempty(this.commandHistory) || this.commandHistory[end] != command)
            push!(this.commandHistory, command)
            
            # Trim history if too long
            if length(this.commandHistory) > this.maxHistorySize
                this.commandHistory = this.commandHistory[(end - this.maxHistorySize + 1):end]
            end
        end
        
        this.historyPosition = length(this.commandHistory) + 1
    end

    """
    Navigate command history
    """
    function navigate_history(this::DeveloperConsole, direction::Int)
        if isempty(this.commandHistory)
            return
        end
        
        this.historyPosition = clamp(this.historyPosition + direction, 1, length(this.commandHistory) + 1)
        
        if this.historyPosition <= length(this.commandHistory)
            this.currentInput = this.commandHistory[this.historyPosition]
        else
            this.currentInput = ""
        end
        
        this.cursorPosition = length(this.currentInput)
        this.autoCompleteActive = false
    end

    """
    Handle auto-completion
    """
    function handle_auto_complete(this::DeveloperConsole)
        if this.autoCompleteActive && !isempty(this.autoCompleteSuggestions)
            # Select current suggestion
            if this.autoCompleteIndex < length(this.autoCompleteSuggestions)
                suggestion = this.autoCompleteSuggestions[this.autoCompleteIndex + 1]
                # Replace the partial command with the full suggestion
                words = split(this.currentInput)
                if !isempty(words)
                    words[end] = suggestion
                    this.currentInput = join(words, " ")
                else
                    this.currentInput = suggestion
                end
                this.cursorPosition = length(this.currentInput)
            end
            this.autoCompleteActive = false
        else
            # Start auto-completion
            generate_auto_complete_suggestions(this)
        end
    end

    """
    Generate auto-complete suggestions based on current input
    """
    function generate_auto_complete_suggestions(this::DeveloperConsole)
        words = split(this.currentInput)
        if isempty(words)
            this.autoCompleteSuggestions = collect(keys(this.commandRegistry))
        else
            partial = words[end]
            suggestions = String[]
            
            # Match command names
            for cmd_name in keys(this.commandRegistry)
                if startswith(cmd_name, partial)
                    push!(suggestions, cmd_name)
                end
            end
            
            this.autoCompleteSuggestions = sort(suggestions)
        end
        
        this.autoCompleteActive = !isempty(this.autoCompleteSuggestions)
        this.autoCompleteIndex = 0
    end

    """
    Execute a command
    """
    function execute_command(this::DeveloperConsole, command_text::String)
        globals = JulGame.UserGlobals["Module"]
        @debug "Executing command: $(command_text)"
        if isempty(strip(command_text))
            @debug "Command is empty"
            return
        end
        
        add_output_line(this, "> " * command_text, this.inputColor)
        
        # Parse command and arguments
        parts = split(strip(command_text))
        cmd_name = lowercase(parts[1])
        
        args = String[]
        for i in eachindex(parts)   
            if i > 1
                push!(args, string(parts[i]))
            end
        end
        # Execute command
        if haskey(this.commandRegistry, cmd_name)
            try
                command = this.commandRegistry[cmd_name]
                result = execute_command_safe(command, args)
                
                if !result.success
                    add_output_line(this, result.message, (255, 100, 100, 255))
                else
                    if !isempty(result.message)
                        add_output_line(this, result.message)
                    end
                end
            catch e
                add_output_line(this, "Error executing command: $(e)", (255, 100, 100, 255))
                @error "Error executing command: $(e)"
            end
        else
            add_output_line(this, "Unknown command: $(cmd_name)", (255, 100, 100, 255))
            add_output_line(this, "Type 'help' for available commands")
        end
    end

    # Include command system files
    include("console/CommandBase.jl")
    include("console/BuiltInCommands.jl")
    include("console/SceneCommands.jl")
    include("console/PlayerCommands.jl")
    include("console/InventoryCommands.jl")

    # Export functions for external use
    export toggle_console, add_output_line, register_command
    
    # Global convenience functions
    function toggle_console()
        if ConsoleInstance !== nothing
            toggle_console(ConsoleInstance)
        end
    end
    
    function add_console_output(line::String, color::Tuple{Int,Int,Int,Int} = (255,255,255,255))
        if ConsoleInstance !== nothing
            add_output_line(ConsoleInstance, line, color)
        end
    end

end 