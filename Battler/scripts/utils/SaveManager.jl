module SaveManagerModule
    using ..Globals
    using JulGame
    using JulGame.SaveSystemModule: SaveStore, write_save, read_save, validate_save, delete_save,
        SaveOk, SaveNotFound, SaveRestoredFromBackup

    export try_save_run!, try_load_run!, delete_run_save!, has_disk_save, validate_run_save, read_saved_run_recorder

    const RUN_SLOT = "run"
    const SAVE_SCHEMA_VERSION = 1

    function _saves_directory()
        base = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "", create_dir = true)
        dir = joinpath(base, "saves")
        mkpath(dir)
        return dir
    end

    function _save_store()
        return SaveStore(;
            directory = _saves_directory(),
            secret_key = Globals.SAVE_DATA_SECRET_KEY,
            version = SAVE_SCHEMA_VERSION,
            max_backups = 3,
        )
    end

    function _to_json_value(value)
        if value === nothing
            return nothing
        elseif value isa NamedTuple
            return Dict{String, Any}(string(k) => _to_json_value(v) for (k, v) in pairs(value))
        elseif value isa Tuple
            return [_to_json_value(v) for v in value]
        elseif value isa AbstractVector
            return [_to_json_value(v) for v in value]
        elseif value isa AbstractDict
            return Dict{String, Any}(string(k) => _to_json_value(v) for (k, v) in value)
        elseif value isa JulGame.Math.Vector2
            return Dict("x" => value.x, "y" => value.y)
        elseif value isa JulGame.Math.Vector3f
            return Dict("x" => value.x, "y" => value.y, "z" => value.z)
        else
            return value
        end
    end

    function _serialize_map_points(map_points)
        result = Dict{String, Any}()
        map_points === nothing && return result
        for (id, point) in map_points
            point_data = Dict{String, Any}()
            for (key, value) in point
                point_data[string(key)] = _to_json_value(value)
            end
            result[string(id)] = point_data
        end
        return result
    end

    function _restore_encounter(value)
        if value isa NamedTuple
            if hasproperty(value, :enemies)
                return (value..., enemies = _restore_named_tuple_vector(value.enemies))
            end
            return value
        elseif value isa AbstractDict
            normalized = Dict{String, Any}(string(k) => v for (k, v) in pairs(value))
            if haskey(normalized, "enemies")
                normalized["enemies"] = _restore_named_tuple_vector(normalized["enemies"])
            end
            return _dict_to_named_tuple(normalized)
        end
        return value
    end

    function _deserialize_map_points(raw)
        # nothing / {} both mean "no map yet" — MapManager regenerates when mapPoints === nothing.
        if raw === nothing || !(raw isa AbstractDict) || isempty(raw)
            return nothing
        end
        result = Dict{String, Any}()
        for (id, point) in raw
            point_data = Dict{String, Any}()
            for (key, value) in point
                string_key = string(key)
                if string_key == "position" && value isa AbstractDict
                    point_data[string_key] = JulGame.Math.Vector2(value["x"], value["y"])
                elseif string_key == "encounter"
                    point_data[string_key] = _restore_encounter(value)
                elseif string_key == "connections" && value isa AbstractVector
                    point_data[string_key] = _as_int_vector(value)
                elseif string_key == "index"
                    point_data[string_key] = Int(value)
                else
                    point_data[string_key] = value
                end
            end
            result[string(id)] = point_data
        end
        return result
    end

    function _serialize_inventory_keys(items)
        keys = String[]
        for item in items
            if item === nothing
                continue
            elseif hasproperty(item, :key)
                push!(keys, string(getproperty(item, :key)))
            end
        end
        return keys
    end

    # Pieces carry a per-run rarity (board weight) that reward/shop upgrades mutate,
    # so they cannot be restored from the canonical piece table by key alone.
    function _serialize_pieces(pieces)
        entries = Dict{String, Any}[]
        pieces === nothing && return entries
        for piece in pieces
            if piece === nothing || !hasproperty(piece, :key)
                continue
            end
            raw_weight = getfield(piece, :weight)
            weight = _parse_saved_weight(raw_weight)
            push!(entries, Dict{String, Any}(
                "key" => string(getproperty(piece, :key)),
                "weight" => weight === nothing ? 10 : weight,
            ))
        end
        return entries
    end

    function _parse_saved_weight(value)::Union{Nothing, Float64}
        value === nothing && return nothing
        if value isa Number
            return Float64(value)
        end
        s = strip(string(value))
        isempty(s) && return nothing
        return tryparse(Float64, s)
    end

    function _restore_pieces!(user, player_data)
        empty!(user.pieces)
        entries = get(player_data, "pieces", nothing)
        if entries === nothing
            # Legacy saves stored keys only; weights fall back to the table defaults.
            _restore_inventory_keys!(user.pieces, get(player_data, "piece_keys", String[]), user.pieceCollection)
            return
        end
        for entry in entries
            try
                if !(entry isa AbstractDict)
                    piece = _lookup_inventory_item(user.pieceCollection, entry)
                    piece !== nothing && push!(user.pieces, piece)
                    continue
                end
                piece = _lookup_inventory_item(user.pieceCollection, get(entry, "key", ""))
                piece === nothing && continue
                weight = _parse_saved_weight(get(entry, "weight", nothing))
                if weight !== nothing
                    piece = Globals.UserModule.with_weight(piece, weight)
                end
                push!(user.pieces, piece)
            catch e
                @warn "Skipping corrupt piece in save" entry=entry exception=(e, catch_backtrace())
            end
        end
    end

    function _serialize_player(user)
        return Dict{String, Any}(
            "health" => user.health,
            "maxHealth" => user.maxHealth,
            "shield" => user.shield,
            "maxShield" => user.maxShield,
            "attack" => user.attack,
            "defense" => user.defense,
            "speed" => user.speed,
            "luck" => user.luck,
            "gold" => user.gold,
            "base_attack" => user.base_attack,
            "weaken" => user.weaken,
            "burn" => user.burn,
            "freeze" => user.freeze,
            "poison" => user.poison,
            "vulnerable" => user.vulnerable,
            "shock" => user.shock,
            "dodge_chance" => user.dodge_chance,
            "reflect_chance" => user.reflect_chance,
            "selectedCharacter" => user.selectedCharacter,
            "shadowCloakUsed" => user.shadowCloakUsed,
            "first_attack_bonus" => user.first_attack_bonus,
            "stake_applied" => user.stake_applied,
            "ancient_shield_used" => user.ancient_shield_used,
            "pieces" => _serialize_pieces(user.pieces),
            "potion_keys" => _serialize_inventory_keys(user.potions),
            "treasure_keys" => _serialize_inventory_keys(user.treasures),
            "inventory_keys" => _serialize_inventory_keys(user.inventory),
        )
    end

    function _serialize_run_state(psm)
        rng = Globals.PersistentStateManagerModule.capture_piece_placement_rng(psm)
        return Dict{String, Any}(
            "seed" => psm.seed,
            "piecePlacementRNGUseCount" => psm.piecePlacementRNGUseCount,
            "rng_state" => collect(rng.state),
            "currentLevel" => psm.currentLevel,
            "currentFloor" => psm.currentFloor,
            "currentRoom" => psm.currentRoom,
            "isFloorComplete" => psm.isFloorComplete,
            "completedNodes" => collect(psm.completedNodes),
            "currentEnemies" => _to_json_value(psm.currentEnemies),
            "currentEvent" => _to_json_value(psm.currentEvent),
            "mapPoints" => _serialize_map_points(psm.mapPoints),
            "mapConnections" => _to_json_value(psm.mapConnections),
            "availableNodes" => collect(psm.availableNodes),
            "startingPoints" => collect(psm.startingPoints),
            "regularMapBattlesWonThisRun" => psm.regularMapBattlesWonThisRun,
            "runElapsedTime" => psm.runElapsedTime,
            "highestComboThisRun" => psm.highestComboThisRun,
            "scrollBgHue" => psm.scrollBgHue,
            "playerData" => _to_json_value(psm.playerData),
        )
    end

    function _build_payload()
        data_manager = Globals.get_data_manager()
        psm = data_manager.persistent_state_manager
        user = Globals.get_user_data()
        return Dict{String, Any}(
            "schema" => SAVE_SCHEMA_VERSION,
            "game_version" => Globals.get_version(),
            "player" => _serialize_player(user),
            "run_state" => _serialize_run_state(psm),
            "run_recorder" => Globals.RunRecorderModule.to_save(),
        )
    end

    """Raw saved `run_recorder` section without touching live state, or `nothing`."""
    function read_saved_run_recorder()
        try
            status, payload = read_save(_save_store(), RUN_SLOT)
            (status == SaveNotFound || payload === nothing) && return nothing
            return get(payload, "run_recorder", nothing)
        catch e
            @debug "Could not read saved run recorder: $e"
            return nothing
        end
    end

    function _lookup_inventory_item(lookup, key)
        key_str = uppercase(string(key))
        if haskey(lookup, key_str)
            return lookup[key_str]
        elseif haskey(lookup, "PIECE_$key_str")
            return lookup["PIECE_$key_str"]
        end
        return nothing
    end

    function _restore_inventory_keys!(items_field, keys, lookup)
        empty!(items_field)
        for key in keys
            item = _lookup_inventory_item(lookup, key)
            item !== nothing && push!(items_field, item)
        end
    end

    function _dict_to_named_tuple(item)
        normalized = Dict{String, Any}()
        for (k, v) in pairs(item)
            normalized[string(k)] = v
        end
        keys_vec = collect(keys(normalized))
        syms = Tuple(Symbol.(keys_vec))
        vals = Tuple(normalized[string(k)] for k in keys_vec)
        return NamedTuple{syms}(vals)
    end

    function _restore_named_tuple_vector(raw)
        raw === nothing && return []
        if raw isa AbstractVector
            return [_dict_to_named_tuple(item) for item in raw]
        end
        return raw
    end

    function _restore_player!(user, player_data)
        user.health = Int(player_data["health"])
        user.maxHealth = Int(player_data["maxHealth"])
        user.shield = Int(player_data["shield"])
        user.maxShield = Int(player_data["maxShield"])
        user.attack = Int(player_data["attack"])
        user.defense = Int(player_data["defense"])
        user.speed = Int(get(player_data, "speed", 1))
        user.luck = Int(get(player_data, "luck", 0))
        user.gold = Int(player_data["gold"])
        user.base_attack = Int(get(player_data, "base_attack", user.attack))
        user.weaken = Int(get(player_data, "weaken", 0))
        user.burn = Int(get(player_data, "burn", 0))
        user.freeze = Int(get(player_data, "freeze", 0))
        user.poison = Int(get(player_data, "poison", 0))
        user.vulnerable = Int(get(player_data, "vulnerable", 0))
        user.shock = Int(get(player_data, "shock", 0))
        user.dodge_chance = Int(get(player_data, "dodge_chance", 0))
        user.reflect_chance = Int(get(player_data, "reflect_chance", 0))
        user.selectedCharacter = string(get(player_data, "selectedCharacter", "CHARACTER_MAGICIAN"))
        user.shadowCloakUsed = Bool(get(player_data, "shadowCloakUsed", false))
        user.first_attack_bonus = Bool(get(player_data, "first_attack_bonus", false))
        user.stake_applied = Bool(get(player_data, "stake_applied", false))
        user.ancient_shield_used = Bool(get(player_data, "ancient_shield_used", false))

        data_manager = Globals.get_data_manager()
        _restore_pieces!(user, player_data)
        _restore_inventory_keys!(user.potions, get(player_data, "potion_keys", String[]), data_manager.potion_data)
        _restore_inventory_keys!(user.treasures, get(player_data, "treasure_keys", String[]), Globals.TreasuresModule.ALL_TREASURES)
        user.inventory = []
    end

    function _as_int_vector(value)::Vector{Int}
        value === nothing && return Int[]
        result = Int[]
        for x in value
            push!(result, Int(x))
        end
        return result
    end

    function _restore_run_state!(psm, run_state)
        rng_state = Tuple(UInt64.(run_state["rng_state"]))
        Globals.PersistentStateManagerModule.restore_piece_placement_rng!(
            psm;
            seed = Int(run_state["seed"]),
            use_count = Int(run_state["piecePlacementRNGUseCount"]),
            state = rng_state,
        )

        psm.currentLevel = Int(run_state["currentLevel"])
        psm.currentFloor = Int(get(run_state, "currentFloor", 1))
        psm.currentRoom = Int(get(run_state, "currentRoom", 0))
        psm.isFloorComplete = Bool(get(run_state, "isFloorComplete", false))
        # JSON empty arrays arrive as Any[]; Int.(Any[]) stays Any[] and breaks setfield!.
        psm.completedNodes = _as_int_vector(get(run_state, "completedNodes", Int[]))
        psm.currentEnemies = _restore_named_tuple_vector(get(run_state, "currentEnemies", []))
        event_raw = get(run_state, "currentEvent", Dict("type" => "", "name" => ""))
        if event_raw isa AbstractDict
            psm.currentEvent = _dict_to_named_tuple(event_raw)
        else
            psm.currentEvent = event_raw
        end
        psm.mapPoints = _deserialize_map_points(get(run_state, "mapPoints", Dict()))
        psm.mapConnections = Dict{String, Any}(String(k) => v for (k, v) in pairs(get(run_state, "mapConnections", Dict())))
        psm.availableNodes = _as_int_vector(get(run_state, "availableNodes", Int[]))
        psm.startingPoints = _as_int_vector(get(run_state, "startingPoints", Int[]))
        psm.regularMapBattlesWonThisRun = Int(get(run_state, "regularMapBattlesWonThisRun", 0))
        psm.runElapsedTime = Float64(get(run_state, "runElapsedTime", 0.0))
        psm.highestComboThisRun = Int(get(run_state, "highestComboThisRun", 0))
        psm.scrollBgHue = Float64(get(run_state, "scrollBgHue", 0.0))
        psm.playerData = Dict{String, Any}(String(k) => v for (k, v) in pairs(get(run_state, "playerData", Dict())))
        psm.isRunActive = psm.currentLevel > 0
    end

    function _has_meaningful_progress()
        psm = Globals.get_data_manager().persistent_state_manager
        return psm.currentLevel > 0 || psm.currentFloor > 1
    end

    function try_save_run!()::Bool
        if !_has_meaningful_progress()
            @debug "No meaningful run progress to save"
            return false
        end
        psm = Globals.get_data_manager().persistent_state_manager
        # Floor advance clears mapPoints; saving that clobber a good save with an empty map.
        if psm.mapPoints === nothing || isempty(psm.mapPoints)
            @debug "Skip save: map points not generated yet"
            return false
        end
        return write_save(_save_store(), RUN_SLOT, _build_payload())
    end

    function try_load_run!()::Bool
        store = _save_store()
        status, payload = read_save(store, RUN_SLOT)
        if status == SaveNotFound || payload === nothing
            @warn "Cannot load run save" status=validate_save(store, RUN_SLOT)
            return false
        end
        if status == SaveRestoredFromBackup
            @warn "Run save restored from backup"
        end

        data_manager = Globals.get_data_manager()
        psm = data_manager.persistent_state_manager
        user = Globals.get_user_data()

        try
            _restore_player!(user, payload["player"])
        catch e
            @error "Failed to restore player from save" exception=(e, catch_backtrace())
            return false
        end
        try
            _restore_run_state!(psm, payload["run_state"])
        catch e
            @error "Failed to restore run state from save" exception=(e, catch_backtrace())
            return false
        end
        Globals.RunRecorderModule.from_save!(get(payload, "run_recorder", nothing))
        try_save_run!()
        return true
    end

    function delete_run_save!()::Bool
        return delete_save(_save_store(), RUN_SLOT)
    end

    function has_disk_save()::Bool
        status = validate_run_save()
        return status == SaveOk || status == SaveRestoredFromBackup
    end

    function validate_run_save()
        return validate_save(_save_store(), RUN_SLOT)
    end
end
