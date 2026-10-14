# Command Base Interface and Registry System

"""
Abstract base type for all console commands
"""
abstract type ConsoleCommand end

"""
Base struct for all console commands with common functionality
"""
mutable struct BaseCommand <: ConsoleCommand
    name::String
    description::String
    usage::String
    category::String
    execute::Function
    validate_args::Function
    
    function BaseCommand(name::String, description::String, usage::String, category::String, execute_func::Function, validate_func::Function = args -> true)
        new(name, description, usage, category, execute_func, validate_func)
    end
end

"""
Command execution result struct
"""
struct CommandResult
    success::Bool
    message::String
    data::Any
    
    function CommandResult(success::Bool, message::String = "", data::Any = nothing)
        new(success, message, data)
    end
end

"""
Register a command with the console
"""
function register_command(console::DeveloperConsole, command::BaseCommand)
    console.commandRegistry[command.name] = command
    
    # Add to category
    if !haskey(console.commandCategories, command.category)
        console.commandCategories[command.category] = String[]
    end
    
    if !(command.name in console.commandCategories[command.category])
        push!(console.commandCategories[command.category], command.name)
    end
end

"""
Validate command arguments
"""
function validate_command_args(command::BaseCommand, args::Vector{String})
    try
        return command.validate_args(args)
    catch e
        @warn "Argument validation failed for command $(command.name): $e"
        return false
    end
end

"""
Execute a command safely with error handling
"""
function execute_command_safe(command::BaseCommand, args::Vector{String})
    try
        # Validate arguments first
        if !validate_command_args(command, args)
            return CommandResult(false, "Invalid arguments. Usage: $(command.usage)")
        end
        
        # Execute the command
        result = command.execute(args)
        
        # Handle different return types
        if isa(result, CommandResult)
            return result
        elseif isa(result, String)
            return CommandResult(true, result)
        elseif result === nothing
            return CommandResult(true, "")
        else
            return CommandResult(true, string(result))
        end
        
    catch e
        error_msg = "Command execution failed: $(e)"
        @error error_msg
        Base.show_backtrace(stderr, backtrace())
        return CommandResult(false, error_msg)
    end
end

"""
Create a simple command with just a function
"""
function create_simple_command(name::String, description::String, category::String, func::Function)
    usage = "$(name)"
    
    execute_func = function(args)
        return func(args)
    end
    
    return BaseCommand(name, description, usage, category, execute_func)
end

"""
Utility function to parse numeric arguments
"""
function parse_numeric_arg(arg::String, arg_name::String = "argument")
    try
        # Try integer first
        if occursin(r"^-?\d+$", arg)
            return parse(Int, arg)
        else
            return parse(Float64, arg)
        end
    catch
        throw(ArgumentError("$(arg_name) must be a number, got: $(arg)"))
    end
end

"""
Utility function to parse boolean arguments
"""
function parse_boolean_arg(arg::String, arg_name::String = "argument")
    lower_arg = lowercase(strip(arg))
    if lower_arg in ["true", "1", "yes", "on", "enabled"]
        return true
    elseif lower_arg in ["false", "0", "no", "off", "disabled"]
        return false
    else
        throw(ArgumentError("$(arg_name) must be true/false, got: $(arg)"))
    end
end

"""
Utility function to validate exact argument count
"""
function validate_exact_args(args::Vector{String}, exact_count::Int, command_name::String = "command")
    if length(args) != exact_count
        throw(ArgumentError("$(command_name) requires exactly $(exact_count) arguments, got $(length(args))"))
    end
    return true
end

"""
Utility function to validate argument count range
"""
function validate_arg_range(args::Vector{String}, min_count::Int, max_count::Int, command_name::String = "command")
    arg_count = length(args)
    if arg_count < min_count || arg_count > max_count
        throw(ArgumentError("$(command_name) requires $(min_count)-$(max_count) arguments, got $(arg_count)"))
    end
    return true
end 