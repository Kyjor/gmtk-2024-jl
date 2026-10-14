# Player Statistics and Game State Commands

"""
Register all player-related commands
"""
function register_player_commands(console::DeveloperConsole)
    register_command(console, create_player_info_command())
    register_command(console, create_set_health_command())
    register_command(console, create_set_level_command())
    register_command(console, create_add_experience_command())
    register_command(console, create_heal_player_command())
    register_command(console, create_damage_player_command())
    register_command(console, create_set_attribute_command())
    register_command(console, create_reset_player_command())
    register_command(console, create_god_mode_command())
end

"""
Get the user/player data safely
"""
function get_user_data_safe()
    try
        globals = JulGame.UserGlobals["Module"]
        return globals.get_user_data()
    catch e
        return nothing
    end
end

"""
Create player info command
"""
function create_player_info_command()
    execute_func = function(args)
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        info_text = """
Player Information:
• Health: $(user.health)/$(user.max_health)
• Level: $(user.level)
• Experience: $(user.experience)
• Gold: $(get(user, :gold, "N/A"))
• Potions: $(length(get(user, :potions, [])))
• Treasures: $(length(get(user, :treasures, [])))
        """
        
        # Add battle-specific info if available
        try
            battle_manager = get_battle_manager()
            if battle_manager !== nothing
                info_text *= "\nBattle Status:\n"
                info_text *= "• Shield: $(battle_manager.shield)\n"
                info_text *= "• Move Count: $(battle_manager.moveCount)\n"
                info_text *= "• Intent: $(battle_manager.intent)\n"
            end
        catch e
            # Battle manager not available, ignore
        end
        
        return CommandResult(true, info_text)
    end
    
    return create_simple_command(
        "player_info",
        "Show player statistics and status",
        "player",
        execute_func
    )
end

"""
Create set health command
"""
function create_set_health_command()
    execute_func = function(args)
        validate_exact_args(args, 1, "set_health")
        
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        new_health = parse_numeric_arg(args[1], "health")
        if new_health < 0
            return CommandResult(false, "Health cannot be negative")
        end
        
        if new_health > user.max_health
            user.max_health = Int(new_health)
        end
        
        user.health = Int(new_health)
        
        return CommandResult(true, "Player health set to $(new_health)")
    end
    
    validate_func = function(args)
        validate_exact_args(args, 1, "set_health")
        return true
    end
    
    return BaseCommand(
        "set_health",
        "Set player health to specific value",
        "set_health <amount>",
        "player",
        execute_func,
        validate_func
    )
end

"""
Create set level command
"""
function create_set_level_command()
    execute_func = function(args)
        validate_exact_args(args, 1, "set_level")
        
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        new_level = parse_numeric_arg(args[1], "level")
        if new_level < 1
            return CommandResult(false, "Level must be at least 1")
        end
        
        if new_level > 100
            return CommandResult(false, "Level cannot exceed 100")
        end
        
        user.level = Int(new_level)
        
        return CommandResult(true, "Player level set to $(new_level)")
    end
    
    validate_func = function(args)
        validate_exact_args(args, 1, "set_level")
        return true
    end
    
    return BaseCommand(
        "set_level",
        "Set player level",
        "set_level <level>",
        "player",
        execute_func,
        validate_func
    )
end

"""
Create add experience command
"""
function create_add_experience_command()
    execute_func = function(args)
        validate_exact_args(args, 1, "add_exp")
        
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        exp_amount = parse_numeric_arg(args[1], "experience")
        if exp_amount < 0
            return CommandResult(false, "Experience amount cannot be negative")
        end
        
        old_exp = user.experience
        user.experience += Int(exp_amount)
        
        return CommandResult(true, "Added $(exp_amount) experience ($(old_exp) → $(user.experience))")
    end
    
    validate_func = function(args)
        validate_exact_args(args, 1, "add_exp")
        return true
    end
    
    return BaseCommand(
        "add_exp",
        "Add experience points to player",
        "add_exp <amount>",
        "player",
        execute_func,
        validate_func
    )
end

"""
Create heal player command
"""
function create_heal_player_command()
    execute_func = function(args)
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        if isempty(args)
            # Full heal
            old_health = user.health
            user.health = user.max_health
            healed = user.max_health - old_health
            return CommandResult(true, "Player fully healed (+$(healed) health)")
        else
            # Heal specific amount
            heal_amount = parse_numeric_arg(args[1], "heal amount")
            if heal_amount < 0
                return CommandResult(false, "Heal amount cannot be negative")
            end
            
            old_health = user.health
            user.health = min(user.max_health, user.health + Int(heal_amount))
            actual_heal = user.health - old_health
            
            return CommandResult(true, "Player healed for $(actual_heal) health ($(old_health) → $(user.health))")
        end
    end
    
    validate_func = function(args)
        return length(args) <= 1
    end
    
    return BaseCommand(
        "heal",
        "Heal player by amount or fully",
        "heal [amount]",
        "player",
        execute_func,
        validate_func
    )
end

"""
Create damage player command
"""
function create_damage_player_command()
    execute_func = function(args)
        validate_exact_args(args, 1, "damage")
        
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        damage_amount = parse_numeric_arg(args[1], "damage amount")
        if damage_amount < 0
            return CommandResult(false, "Damage amount cannot be negative")
        end
        
        old_health = user.health
        user.health = max(0, user.health - Int(damage_amount))
        actual_damage = old_health - user.health
        
        result_text = "Player took $(actual_damage) damage ($(old_health) → $(user.health))"
        if user.health == 0
            result_text *= " - PLAYER DEFEATED!"
        end
        
        return CommandResult(true, result_text)
    end
    
    validate_func = function(args)
        validate_exact_args(args, 1, "damage")
        return true
    end
    
    return BaseCommand(
        "damage",
        "Deal damage to player",
        "damage <amount>",
        "player",
        execute_func,
        validate_func
    )
end

"""
Create set attribute command
"""
function create_set_attribute_command()
    execute_func = function(args)
        validate_exact_args(args, 2, "set_attr")
        
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        attribute = lowercase(args[1])
        value_str = args[2]
        
        @debug "attribute: $(attribute)"
        if attribute == "max_health"
            new_value = parse_numeric_arg(value_str, "max health")
            if new_value < 1
                return CommandResult(false, "Max health must be at least 1")
            end
            user.max_health = Int(new_value)
            # Adjust current health if needed
            if user.health > user.max_health
                user.health = user.max_health
            end
            return "Max health set to $(new_value)"
        elseif attribute == "gold"
            new_value = parse_numeric_arg(value_str, "gold")
            if new_value < 0
                return CommandResult(false, "Gold cannot be negative")
            end
            setproperty!(user, :gold, Int(new_value))
            return "Gold set to $(new_value)"
        else
            try
                new_value = parse_numeric_arg(value_str, attribute)
                setproperty!(user, Symbol(attribute), Int(new_value))
                return "Attribute set to $(new_value)"
            catch e
                return CommandResult(false, "Unknown or unsupported attribute: $(attribute). Available: max_health, gold")
            end
        end
    end
    
    validate_func = function(args)
        validate_exact_args(args, 2, "set_attr")
        return true
    end
    
    return BaseCommand(
        "set_attr",
        "Set player attribute value",
        "set_attr <attribute> <value>",
        "player",
        execute_func,
        validate_func
    )
end

"""
Create reset player command
"""
function create_reset_player_command()
    execute_func = function(args)
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        # Reset to default values
        user.health = user.max_health
        user.level = 1
        user.experience = 0
        
        # Clear collections if they exist
        if hasfield(typeof(user), :potions)
            empty!(user.potions)
        end
        if hasfield(typeof(user), :treasures)
            empty!(user.treasures)
        end
        if hasfield(typeof(user), :gold)
            setproperty!(user, :gold, 0)
        end
        
        return CommandResult(true, "Player stats reset to default values")
    end
    
    return create_simple_command(
        "reset_player",
        "Reset player stats to default values",
        "player",
        execute_func
    )
end

"""
Create god mode command
"""
function create_god_mode_command()
    execute_func = function(args)
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end
        
        # God mode: max health, high level, lots of resources
        user.health = 9999
        user.max_health = 9999
        user.level = 99
        user.experience = 999999
        
        if hasfield(typeof(user), :gold)
            setproperty!(user, :gold, 999999)
        end
        
        return CommandResult(true, "God mode activated! Player now has maximum stats.")
    end
    
    return create_simple_command(
        "god_mode",
        "Activate god mode (max stats)",
        "player",
        execute_func
    )
end

"""
Helper function to get battle manager if available
"""
function get_battle_manager()
    try
        if MAIN.scene !== nothing
            for entity in MAIN.scene.entities
                for script in entity.scripts
                    if typeof(script) <: Scripts.BattleManagerModule.BattleManager
                        return script
                    end
                end
            end
        end
        return nothing
    catch e
        return nothing
    end
end

# Auto-register player commands when this file is included
if ccall(:jl_generating_output, Cint, ()) != 1 && !JulGame.IS_PACKAGE_COMPILED
function __init__()
    if ConsoleInstance !== nothing
        register_player_commands(ConsoleInstance)
    end
end 
end