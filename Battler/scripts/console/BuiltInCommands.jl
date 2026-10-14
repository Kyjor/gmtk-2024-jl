# Built-in Console Commands
using Dates

"""
Register all built-in commands with the console
"""
function register_built_in_commands(console::DeveloperConsole)
    # Help command
    register_command(console, create_help_command())
    
    # Clear command
    register_command(console, create_clear_command())
    
    # History command
    register_command(console, create_history_command())
    
    # Echo command
    register_command(console, create_echo_command())
    
    # Time command
    register_command(console, create_time_command())
    
    # Version command
    register_command(console, create_version_command())
    
    # List commands
    register_command(console, create_list_commands())
    
    # Set console properties
    register_command(console, create_set_command())
    
    # Quit/Exit command
    register_command(console, create_quit_command())
end

"""
Create help command
"""
function create_help_command()
    execute_func = function(args)
        if isempty(args)
            # Show general help
            help_text = """
Available command categories:
• system - System and console commands
• scene - Scene management commands
• player - Player statistics commands
• inventory - Inventory and item commands

Usage:
• help <command> - Show detailed help for specific command
• help <category> - Show all commands in category
• list - Show all available commands
• clear - Clear console output
• history - Show command history

Press Tab for auto-completion, Up/Down arrows for command history.
            """
            return CommandResult(true, help_text)
        else
            # Show help for specific command or category
            target = lowercase(args[1])
            
            # Check if it's a specific command
            if haskey(ConsoleInstance.commandRegistry, target)
                cmd = ConsoleInstance.commandRegistry[target]
                help_text = """
Command: $(cmd.name)
Category: $(cmd.category)
Description: $(cmd.description)
Usage: $(cmd.usage)
                """
                return CommandResult(true, help_text)
            end
            
            # Check if it's a category
            if haskey(ConsoleInstance.commandCategories, target)
                commands = ConsoleInstance.commandCategories[target]
                help_text = "Commands in category '$(target)':\n"
                for cmd_name in sort(commands)
                    cmd = ConsoleInstance.commandRegistry[cmd_name]
                    help_text *= "• $(cmd_name) - $(cmd.description)\n"
                end
                return CommandResult(true, help_text)
            end
            
            return CommandResult(false, "Unknown command or category: $(target)")
        end
    end
    
    validate_func = function(args)
        return length(args) <= 1
    end
    
    return BaseCommand(
        "help",
        "Show help information for commands",
        "help [command|category]",
        "system",
        execute_func,
        validate_func
    )
end

"""
Create clear command
"""
function create_clear_command()
    execute_func = function(args)
        ConsoleInstance.outputLines = String[]
        ConsoleInstance.scrollOffset = 0
        return nothing
    end
    
    return create_simple_command(
        "clear",
        "Clear console output",
        "system",
        execute_func
    )
end

"""
Create history command
"""
function create_history_command()
    execute_func = function(args)
        if isempty(ConsoleInstance.commandHistory)
            return "No command history available"
        end
        
        history_text = "Command History:\n"
        for (i, cmd) in enumerate(ConsoleInstance.commandHistory)
            history_text *= "$(i): $(cmd)\n"
        end
        
        return CommandResult(true, history_text)
    end
    
    return create_simple_command(
        "history",
        "Show command history",
        "system",
        execute_func
    )
end

"""
Create echo command
"""
function create_echo_command()
    execute_func = function(args)
        if isempty(args)
            return ""
        end
        return join(args, " ")
    end
    
    return BaseCommand(
        "echo",
        "Echo text to console output",
        "echo <text...>",
        "system",
        execute_func
    )
end

"""
Create time command
"""
function create_time_command()
    execute_func = function(args)
        current_time = Dates.now()
        return "Current time: $(current_time)"
    end
    
    return create_simple_command(
        "time",
        "Show current time",
        "system",
        execute_func
    )
end

"""
Create version command
"""
function create_version_command()
    execute_func = function(args)
        version_info = """
Game: Necro-Matcher
Engine: JulGame
Julia Version: $(VERSION)
Developer Console Version: 1.0.0
        """
        return CommandResult(true, version_info)
    end
    
    return create_simple_command(
        "version",
        "Show version information",
        "system",
        execute_func
    )
end

"""
Create list command
"""
function create_list_commands()
    execute_func = function(args)
        if isempty(args)
            # List all commands
            commands_text = "Available Commands:\n"
            
            for category in sort(collect(keys(ConsoleInstance.commandCategories)))
                commands_text *= "\n$(category):\n"
                for cmd_name in sort(ConsoleInstance.commandCategories[category])
                    cmd = ConsoleInstance.commandRegistry[cmd_name]
                    commands_text *= "  • $(cmd_name) - $(cmd.description)\n"
                end
            end
            
            return CommandResult(true, commands_text)
        else
            # List commands in specific category
            category = lowercase(args[1])
            if haskey(ConsoleInstance.commandCategories, category)
                commands = ConsoleInstance.commandCategories[category]
                commands_text = "Commands in '$(category)' category:\n"
                
                for cmd_name in sort(commands)
                    cmd = ConsoleInstance.commandRegistry[cmd_name]
                    commands_text *= "• $(cmd_name) - $(cmd.description)\n"
                end
                
                return CommandResult(true, commands_text)
            else
                return CommandResult(false, "Unknown category: $(category)")
            end
        end
    end
    
    validate_func = function(args)
        return length(args) <= 1
    end
    
    return BaseCommand(
        "list",
        "List available commands",
        "list [category]",
        "system",
        execute_func,
        validate_func
    )
end

"""
Create set command for console properties
"""
function create_set_command()
    execute_func = function(args)
        validate_exact_args(args, 2, "set")
        
        property = lowercase(args[1])
        value = args[2]
        
        if property == "fontsize"
            new_size = parse_numeric_arg(value, "font size")
            if new_size < 8 || new_size > 32
                return CommandResult(false, "Font size must be between 8 and 32")
            end
            ConsoleInstance.fontSize = Int(new_size)
            return "Font size set to $(new_size)"
        elseif property == "height"
            new_height = parse_numeric_arg(value, "height")
            if new_height < 200 || new_height > 800
                return CommandResult(false, "Height must be between 200 and 800")
            end
            ConsoleInstance.consolePanelHeight = Int(new_height)
            return "Console height set to $(new_height)"
        elseif property == "width"
            new_width = parse_numeric_arg(value, "width")
            if new_width < 400 || new_width > 1600
                return CommandResult(false, "Width must be between 400 and 1600")
            end
            ConsoleInstance.consolePanelWidth = Int(new_width)
            return "Console width set to $(new_width)"
        elseif property == "opacity"
            opacity = parse_numeric_arg(value, "opacity")
            if opacity < 0.1 || opacity > 1.0
                return CommandResult(false, "Opacity must be between 0.1 and 1.0")
            end
            alpha = Int(round(opacity * 255))
            ConsoleInstance.backgroundColor = (
                ConsoleInstance.backgroundColor[1],
                ConsoleInstance.backgroundColor[2],
                ConsoleInstance.backgroundColor[3],
                alpha
            )
            return "Console opacity set to $(opacity)"
        else
            return CommandResult(false, "Unknown property: $(property). Available: fontsize, height, width, opacity")
        end
    end
    
    validate_func = function(args)
        validate_exact_args(args, 2, "set")
        return true
    end
    
    return BaseCommand(
        "set",
        "Set console properties",
        "set <property> <value>",
        "system",
        execute_func,
        validate_func
    )
end

"""
Create quit/exit command
"""
function create_quit_command()
    execute_func = function(args)
        ConsoleInstance.isConsoleOpen = false
        ConsoleInstance.inputActive = false
        return "Console closed"
    end
    
    quit_cmd = create_simple_command(
        "quit",
        "Close the developer console",
        "system",
        execute_func
    )
    
    # Also register as "exit"
    exit_cmd = BaseCommand(
        "exit",
        "Close the developer console",
        "exit",
        "system",
        execute_func
    )
    
    # Register both commands
    register_command(ConsoleInstance, quit_cmd)
    register_command(ConsoleInstance, exit_cmd)
    
    return quit_cmd
end 