# Inventory and Item Management Commands

"""
Register all inventory-related commands
"""
function register_inventory_commands(console::DeveloperConsole)
    register_command(console, create_inventory_list_command())
    register_command(console, create_add_treasure_command())
    register_command(console, create_add_all_treasures_command())
    register_command(console, create_remove_treasure_command())
    register_command(console, create_add_potion_command())
    register_command(console, create_add_piece_command())
    register_command(console, create_add_all_pieces_command())
    register_command(console, create_remove_piece_command())
    register_command(console, create_clear_inventory_command())
    register_command(console, create_spawn_item_command())
    register_command(console, create_treasure_info_command())
    register_command(console, create_potion_info_command())
    register_command(console, create_piece_info_command())
end

"""
Get available treasure types from generated constants
"""
function get_available_treasures()
    try
        globals = JulGame.UserGlobals["Module"]
        # Try to get treasures from the generated constants
        if isdefined(globals, :TreasuresModule)
            return collect(keys(globals.TreasuresModule.ALL_TREASURES))
        else
            # Fallback list of common treasures
            return ["TREASURE_DUMBELLS", "TREASURE_KNEEPADS", "TREASURE_CUTEBANDAGE", "TREASURE_IRONSHIELD", "TREASURE_HEALTHRING"]
        end
    catch e
        return ["TREASURE_DUMBELLS", "TREASURE_KNEEPADS", "TREASURE_CUTEBANDAGE"]  # Minimal fallback
    end
end

"""
Get available potion types
"""
function get_available_potions()
    try
        globals = JulGame.UserGlobals["Module"]
        if isdefined(globals, :PotionsModule) && isdefined(globals.PotionsModule, :ALL_POTIONS)
            return collect(keys(globals.PotionsModule.ALL_POTIONS))
        else
            return ["POTION_HEALTHPOTION", "POTION_MANAPOTION", "POTION_STRENGTHPOTION"]
        end
    catch e
        return ["POTION_HEALTHPOTION", "POTION_MANAPOTION"]
    end
end

"""
Get available piece types
"""
function get_available_pieces()
    try
        user = get_user_data_safe()
        globals = JulGame.UserGlobals["Module"]
        if user !== nothing && hasfield(typeof(user), :pieceCollection)
            return collect(keys(user.pieceCollection))
        elseif isdefined(globals, :PiecesModule) && isdefined(globals.PiecesModule, :ALL_PIECES)
            return collect(keys(globals.PiecesModule.ALL_PIECES))
        else
            return ["PIECE_SWORD", "PIECE_POTION", "PIECE_SHIELD", "PIECE_SPELL", "PIECE_SPECIAL"]
        end
    catch e
        return ["PIECE_SWORD", "PIECE_POTION", "PIECE_SHIELD"]
    end
end

"""
Create inventory list command
"""
function create_inventory_list_command()
    execute_func = function (args)
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        inventory_text = "Player Inventory:\n\n"

        # List treasures
        treasures = get(user, :treasures, [])
        inventory_text *= "Treasures ($(length(treasures))):\n"
        if isempty(treasures)
            inventory_text *= "  (none)\n"
        else
            for (i, treasure) in enumerate(treasures)
                treasure_name = string(typeof(treasure))
                inventory_text *= "  $(i). $(treasure_name)\n"
            end
        end

        inventory_text *= "\n"

        # List potions
        potions = get(user, :potions, [])
        inventory_text *= "Potions ($(length(potions))):\n"
        if isempty(potions)
            inventory_text *= "  (none)\n"
        else
            for (i, potion) in enumerate(potions)
                potion_name = string(typeof(potion))
                inventory_text *= "  $(i). $(potion_name)\n"
            end
        end

        inventory_text *= "\n"

        # List pieces
        pieces = get(user, :pieces, [])
        inventory_text *= "Pieces ($(length(pieces))):\n"
        if isempty(pieces)
            inventory_text *= "  (none)\n"
        else
            for (i, piece) in enumerate(pieces)
                piece_name = string(typeof(piece))
                inventory_text *= "  $(i). $(piece_name)\n"
            end
        end

        # Add gold if available
        if hasfield(typeof(user), :gold)
            inventory_text *= "\nGold: $(getfield(user, :gold))\n"
        end

        return CommandResult(true, inventory_text)
    end

    return create_simple_command(
        "inventory",
        "List player inventory contents",
        "inventory",
        execute_func
    )
end

"""
Create add treasure command
"""
function create_add_treasure_command()
    execute_func = function (args)
        validate_exact_args(args, 1, "add_treasure")

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        treasure_name = uppercase("TREASURE_" * args[1])
        # Check if treasure type exists
        globals = JulGame.UserGlobals["Module"]
        if !haskey(globals.TreasuresModule.ALL_TREASURES, treasure_name)
            return CommandResult(false, "Unknown treasure: $(treasure_name). Available: $(join(keys(globals.TreasuresModule.ALL_TREASURES), ", "))")
        end

        try
            # Try to create the treasure instance
            treasure = globals.TreasuresModule.ALL_TREASURES[treasure_name]

            if treasure === nothing
                return CommandResult(false, "Failed to find treasure type: $(treasure_name)")
            end

            push!(user.treasures, treasure)

            return CommandResult(true, "Added treasure: $(treasure_name)")

        catch e
            return CommandResult(false, "Failed to add treasure '$(treasure_name)': $(e)")
        end
    end

    validate_func = function (args)
        validate_exact_args(args, 1, "add_treasure")
        return true
    end

    return BaseCommand(
        "add_treasure",
        "Add a treasure to player inventory",
        "add_treasure <treasure_name>",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Add every in-game treasure once (`currently_available_in_game`); skips types already owned (by `key`) and respects `max_treasures`.
"""
function create_add_all_treasures_command()
    execute_func = function (args)
        if !isempty(args)
            return CommandResult(false, "add_all_treasures takes no arguments")
        end

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        globals = JulGame.UserGlobals["Module"]
        if !isdefined(globals, :TreasuresModule) || !isdefined(globals.TreasuresModule, :ALL_TREASURES)
            return CommandResult(false, "TreasuresModule.ALL_TREASURES not available")
        end
        if !isdefined(globals, :item_available_in_game)
            return CommandResult(false, "item_available_in_game not available on globals module")
        end

        owned_keys = Set(t.key for t in user.treasures)
        added = 0
        skipped = String[]

        for treasure_key in sort(collect(keys(globals.TreasuresModule.ALL_TREASURES)))
            treasure = globals.TreasuresModule.ALL_TREASURES[treasure_key]
            if treasure === nothing
                push!(skipped, treasure_key * " (null)")
                continue
            end
            if !globals.item_available_in_game(treasure)
                push!(skipped, treasure_key * " (not available in game)")
                continue
            end
            if treasure.key in owned_keys
                push!(skipped, treasure_key * " (already owned)")
                continue
            end
            if length(user.treasures) >= user.max_treasures
                push!(skipped, "$(treasure_key) (max treasures $(user.max_treasures) reached)")
                break
            end
            try
                push!(user.treasures, treasure)
                push!(owned_keys, treasure.key)
                added += 1
            catch e
                push!(skipped, "$(treasure_key): $(e)")
            end
        end

        msg = "Added $(added) treasure(s)."
        if !isempty(skipped)
            msg *= "\nSkipped ($(length(skipped))): $(join(skipped, ", "))"
        end
        return CommandResult(true, msg)
    end

    return create_simple_command(
        "add_all_treasures",
        "Add every in-game treasure you do not already have (currently_available_in_game)",
        "add_all_treasures",
        execute_func
    )
end

"""
Create remove treasure command
"""
function create_remove_treasure_command()
    execute_func = function (args)
        validate_exact_args(args, 1, "remove_treasure")

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        treasures = get(user, :treasures, [])
        if isempty(treasures)
            return CommandResult(false, "No treasures in inventory")
        end

        index_or_name = args[1]

        # Try to parse as index first
        try
            index = parse(Int, index_or_name)
            if index < 1 || index > length(treasures)
                return CommandResult(false, "Invalid index. Must be between 1 and $(length(treasures))")
            end

            removed_treasure = treasures[index]
            deleteat!(treasures, index)

            treasure_name = string(typeof(removed_treasure))
            return CommandResult(true, "Removed treasure: $(treasure_name)")

        catch ParseError
            # Try to find by name (convert to proper format)
            search_name = uppercase("TREASURE_" * index_or_name)
            for (i, treasure) in enumerate(treasures)
                if string(typeof(treasure)) == search_name
                    deleteat!(treasures, i)
                    return CommandResult(true, "Removed treasure: $(search_name)")
                end
            end

            return CommandResult(false, "Treasure not found: $(search_name)")
        end
    end

    validate_func = function (args)
        validate_exact_args(args, 1, "remove_treasure")
        return true
    end

    return BaseCommand(
        "remove_treasure",
        "Remove a treasure from inventory by index or name",
        "remove_treasure <index|name>",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Create add potion command
"""
function create_add_potion_command()
    execute_func = function (args)
        validate_arg_range(args, 1, 2, "add_potion")

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        potion_name = uppercase("POTION_" * args[1])
        globals = JulGame.UserGlobals["Module"]
        count = length(args) > 1 ? parse_numeric_arg(args[2], "count") : 1

        if count < 1
            return CommandResult(false, "Count must be at least 1")
        end

        # Check if potion type exists
        if !isdefined(globals, :PotionsModule) || !isdefined(globals.PotionsModule, :ALL_POTIONS) || !haskey(globals.PotionsModule.ALL_POTIONS, potion_name)
            return CommandResult(false, "Unknown potion: $(potion_name). Available: $(join(get_available_potions(), ", "))")
        end

        try
            # Get the potion from the module
            potion = globals.PotionsModule.ALL_POTIONS[potion_name]

            if potion === nothing
                return CommandResult(false, "Failed to find potion type: $(potion_name)")
            end

            # Add multiple potions
            for i in 1:Int(count)
                push!(user.potions, potion)
            end

            return CommandResult(true, "Added $(count) $(potion_name)(s)")

        catch e
            return CommandResult(false, "Failed to add potion '$(potion_name)': $(e)")
        end
    end

    validate_func = function (args)
        validate_arg_range(args, 1, 2, "add_potion")
        return true
    end

    return BaseCommand(
        "add_potion",
        "Add potions to player inventory",
        "add_potion <potion_name> [count]",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Create add piece command
"""
function create_add_piece_command()
    execute_func = function (args)
        validate_exact_args(args, 1, "add_piece")

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        piece_name = uppercase("PIECE_" * args[1])
        globals = JulGame.UserGlobals["Module"]
        if !haskey(globals.PiecesModule.ALL_PIECES, piece_name)
            return CommandResult(false, "Unknown piece: $(piece_name). Available: $(join(get_available_pieces(), ", "))")
        end
        # Check if piece exists in user's piece collection (same as how User.jl accesses pieces)
        try
            # Try to create the piece instance
            piece = globals.PiecesModule.ALL_PIECES[piece_name]

            if piece === nothing
                return CommandResult(false, "Failed to find piece type: $(piece_name)")
            end

            globals.UserModule.add_piece_with_gem_limit!(user, piece)

            return CommandResult(true, "Added piece: $(piece_name)")
        catch e
            return CommandResult(false, "Failed to add piece '$(piece_name)': $(e)")
        end
    end

    validate_func = function (args)
        validate_exact_args(args, 1, "add_piece")
        return true
    end

    return BaseCommand(
        "add_piece",
        "Add a piece to player inventory",
        "add_piece <piece_name>",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Add one of every piece type from ALL_PIECES that is flagged for use in the run
(`currently_available_in_game`, same filter as shop/rewards); respects gem limit like `add_piece`.
"""
function create_add_all_pieces_command()
    execute_func = function (args)
        if !isempty(args)
            return CommandResult(false, "add_all_pieces takes no arguments")
        end

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        globals = JulGame.UserGlobals["Module"]
        if !isdefined(globals, :PiecesModule) || !isdefined(globals.PiecesModule, :ALL_PIECES)
            return CommandResult(false, "PiecesModule.ALL_PIECES not available")
        end
        if !isdefined(globals, :item_available_in_game)
            return CommandResult(false, "item_available_in_game not available on globals module")
        end

        added = 0
        skipped = String[]
        for piece_key in sort(collect(keys(globals.PiecesModule.ALL_PIECES)))
            piece = globals.PiecesModule.ALL_PIECES[piece_key]
            if piece === nothing
                push!(skipped, piece_key * " (null)")
                continue
            end
            if !globals.item_available_in_game(piece)
                push!(skipped, piece_key * " (not available in game)")
                continue
            end
            try
                if globals.UserModule.add_piece_with_gem_limit!(user, piece)
                    added += 1
                else
                    push!(skipped, piece_key)
                end
            catch e
                push!(skipped, "$(piece_key): $(e)")
            end
        end

        msg = "Added $(added) piece type(s) to inventory."
        if !isempty(skipped)
            msg *= "\nSkipped or not added ($(length(skipped))): $(join(skipped, ", "))"
        end
        return CommandResult(true, msg)
    end

    return create_simple_command(
        "add_all_pieces",
        "Add every in-game piece type once (currently_available_in_game); obeys one-gem rule",
        "add_all_pieces",
        execute_func
    )
end

"""
Create remove piece command
"""
function create_remove_piece_command()
    execute_func = function (args)
        validate_exact_args(args, 1, "remove_piece")

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        pieces = get(user, :pieces, [])
        if isempty(pieces)
            return CommandResult(false, "No pieces in inventory")
        end

        index_or_name = args[1]

        # Try to parse as index first
        try
            index = parse(Int, index_or_name)
            if index < 1 || index > length(pieces)
                return CommandResult(false, "Invalid index. Must be between 1 and $(length(pieces))")
            end

            removed_piece = pieces[index]
            deleteat!(pieces, index)

            piece_name = string(typeof(removed_piece))
            return CommandResult(true, "Removed piece: $(piece_name)")

        catch ParseError
            # Try to find by name (convert to proper format)
            search_name = uppercase("PIECE_" * index_or_name)
            for (i, piece) in enumerate(pieces)
                if string(typeof(piece)) == search_name
                    deleteat!(pieces, i)
                    return CommandResult(true, "Removed piece: $(search_name)")
                end
            end

            return CommandResult(false, "Piece not found: $(search_name)")
        end
    end

    validate_func = function (args)
        validate_exact_args(args, 1, "remove_piece")
        return true
    end

    return BaseCommand(
        "remove_piece",
        "Remove a piece from inventory by index or name",
        "remove_piece <index|name>",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Create clear inventory command
"""
function create_clear_inventory_command()
    execute_func = function (args)
        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        cleared_items = 0

        # Clear treasures
        if hasfield(typeof(user), :treasures)
            treasures_count = length(user.treasures)
            empty!(user.treasures)
            cleared_items += treasures_count
        end

        # Clear potions
        if hasfield(typeof(user), :potions)
            potions_count = length(user.potions)
            empty!(user.potions)
            cleared_items += potions_count
        end

        # Clear pieces
        if hasfield(typeof(user), :pieces)
            pieces_count = length(user.pieces)
            empty!(user.pieces)
            cleared_items += pieces_count
        end

        return CommandResult(true, "Cleared $(cleared_items) items from inventory")
    end

    return create_simple_command(
        "clear_inventory",
        "Clear all items from player inventory",
        "inventory",
        execute_func
    )
end

"""
Create spawn item command (generic item spawner)
"""
function create_spawn_item_command()
    execute_func = function (args)
        validate_arg_range(args, 2, 3, "spawn_item")

        item_type = lowercase(args[1])
        item_name = args[2]
        count = length(args) > 2 ? parse_numeric_arg(args[3], "count") : 1

        if count < 1
            return CommandResult(false, "Count must be at least 1")
        end

        if item_type == "treasure"
            # Spawn treasures
            for i in 1:Int(count)
                result = execute_command_safe(
                    BaseCommand("temp", "", "", "", args -> nothing),
                    ["add_treasure", item_name]
                )
                if !result.success
                    @error "Failed to spawn treasure: $(item_name)"
                    @error "Result: $(result)"
                    return result
                end
            end
            return CommandResult(true, "Spawned $(count) $(item_name) treasure(s)")

        elseif item_type == "potion"
            # Spawn potions
            result = execute_command_safe(
                BaseCommand("temp", "", "", "", args -> nothing),
                ["add_potion", item_name, string(Int(count))]
            )
            return result

        elseif item_type == "piece"
            # Spawn pieces
            for i in 1:Int(count)
                result = execute_command_safe(
                    BaseCommand("temp", "", "", "", args -> nothing),
                    ["add_piece", item_name]
                )
                if !result.success
                    return result
                end
            end
            return CommandResult(true, "Spawned $(count) $(item_name) piece(s)")

        else
            return CommandResult(false, "Unknown item type: $(item_type). Available: treasure, potion, piece")
        end
    end

    validate_func = function (args)
        validate_arg_range(args, 2, 3, "spawn_item")
        return true
    end

    return BaseCommand(
        "spawn_item",
        "Spawn items of specified type",
        "spawn_item <treasure|potion|piece> <name> [count]",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Create treasure info command
"""
function create_treasure_info_command()
    execute_func = function (args)
        globals = JulGame.UserGlobals["Module"]
        if isempty(args)
            available_treasures = get_available_treasures()
            return CommandResult(true, "Available treasures:\n• $(join(available_treasures, "\n• "))")
        end

        treasure_name = uppercase("TREASURE_" * args[1])

        if !isdefined(globals, :TreasuresModule) || !haskey(globals.TreasuresModule.ALL_TREASURES, treasure_name)
            return CommandResult(false, "Unknown treasure: $(treasure_name). Available: $(join(get_available_treasures(), ", "))")
        end

        try
            # Get treasure from the module
            treasure = globals.TreasuresModule.ALL_TREASURES[treasure_name]

            info_text = """
Treasure: $(treasure_name)
Type: $(typeof(treasure))
            """

            # Try to get additional properties
            if hasfield(typeof(treasure), :name)
                info_text *= "Name: $(treasure.name)\n"
            end
            if hasfield(typeof(treasure), :description)
                info_text *= "Description: $(treasure.description)\n"
            end

            return CommandResult(true, info_text)

        catch e
            return CommandResult(false, "Error getting treasure info: $(e)")
        end
    end

    validate_func = function (args)
        return length(args) <= 1
    end

    return BaseCommand(
        "treasure_info",
        "Get information about treasures",
        "treasure_info [treasure_name]",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Create potion info command
"""
function create_potion_info_command()
    execute_func = function (args)
        globals = JulGame.UserGlobals["Module"]
        if isempty(args)
            available_potions = get_available_potions()
            return CommandResult(true, "Available potions:\n• $(join(available_potions, "\n• "))")
        end

        potion_name = uppercase("POTION_" * args[1])

        if !isdefined(globals, :PotionsModule) || !isdefined(globals.PotionsModule, :ALL_POTIONS) || !haskey(globals.PotionsModule.ALL_POTIONS, potion_name)
            return CommandResult(false, "Unknown potion: $(potion_name). Available: $(join(get_available_potions(), ", "))")
        end

        try
            # Get potion from the module
            potion = globals.PotionsModule.ALL_POTIONS[potion_name]

            info_text = """
Potion: $(potion_name)
Type: $(typeof(potion))
            """

            if hasfield(typeof(potion), :name)
                info_text *= "Name: $(potion.name)\n"
            end
            if hasfield(typeof(potion), :description)
                info_text *= "Description: $(potion.description)\n"
            end
            if hasfield(typeof(potion), :heal_amount)
                info_text *= "Heal Amount: $(potion.heal_amount)\n"
            end

            return CommandResult(true, info_text)

        catch e
            return CommandResult(false, "Error getting potion info: $(e)")
        end
    end

    validate_func = function (args)
        return length(args) <= 1
    end

    return BaseCommand(
        "potion_info",
        "Get information about potions",
        "potion_info [potion_name]",
        "inventory",
        execute_func,
        validate_func
    )
end

"""
Create piece info command
"""
function create_piece_info_command()
    execute_func = function (args)
        globals = JulGame.UserGlobals["Module"]
        if isempty(args)
            available_pieces = get_available_pieces()
            return CommandResult(true, "Available pieces:\n• $(join(available_pieces, "\n• "))")
        end

        piece_name = uppercase("PIECE_" * args[1])

        user = get_user_data_safe()
        if user === nothing
            return CommandResult(false, "Unable to access player data")
        end

        if !haskey(user.pieceCollection, piece_name)
            return CommandResult(false, "Unknown piece: $(piece_name). Available: $(join(get_available_pieces(), ", "))")
        end

        try
            # Get piece from the user's piece collection
            piece = user.pieceCollection[piece_name]

            info_text = """
Piece: $(piece_name)
Type: $(typeof(piece))
            """

            if hasfield(typeof(piece), :en_name)
                info_text *= "Name: $(piece.name)\n"
            end
            if hasfield(typeof(piece), :en_desc)
                info_text *= "Description: $(piece.en_desc)\n"
            end
            if hasfield(typeof(piece), :attack)
                info_text *= "Attack: $(piece.attack) + $(user.attack)\n"
            end
            if hasfield(typeof(piece), :defense)
                info_text *= "Defense: $(piece.defense)\n"
            end
            if hasfield(typeof(piece), :heal)
                info_text *= "Heal: $(piece.heal)\n"
            end
            if hasfield(typeof(piece), :type)
                info_text *= "Piece Type: $(piece.type)\n"
            end

            return CommandResult(true, info_text)

        catch e
            return CommandResult(false, "Error getting piece info: $(e)")
        end
    end

    validate_func = function (args)
        return length(args) <= 1
    end

    return BaseCommand(
        "piece_info",
        "Get information about pieces",
        "piece_info [piece_name]",
        "inventory",
        execute_func,
        validate_func
    )
end

# Auto-register inventory commands when this file is included

if ccall(:jl_generating_output, Cint, ()) != 1 && !JulGame.IS_PACKAGE_COMPILED
    function __init__()
        if ConsoleInstance !== nothing
            register_inventory_commands(ConsoleInstance)
        end
    end
end
