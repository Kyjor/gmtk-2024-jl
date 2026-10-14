live_data_enabled() =
    get(ENV, "JULGAME_LIVE_DATA", "false") == "true" ||
    "JULGAME_LIVE_DATA" in ARGS ||
    "JULGAME_TEST" in ARGS

function to_julia_field_name(field_name::String)
    clean_name = lowercase(replace(field_name, r"[^a-zA-Z0-9_]" => "_"))
    clean_name = replace(clean_name, r"^_+|_+$" => "")
    clean_name = replace(clean_name, r"_+" => "_")
    if !isempty(clean_name) && !isletter(first(clean_name)) && first(clean_name) != '_'
        clean_name = "_" * clean_name
    end
    return isempty(clean_name) ? "_field" : clean_name
end

function convert_json_value(raw, ::Type{T}) where T
    if raw === nothing
        Nothing <: T && return nothing
        T <: AbstractString && return ""
        error("Got null for non-nullable field type $T")
    end

    if T isa Union
        non_nothing = filter(t -> t !== Nothing, Base.uniontypes(T))
        if length(non_nothing) == 1
            return convert_json_value(raw, only(non_nothing))
        end
    end

    if T <: Integer
        if raw isa AbstractString
            s = strip(raw)
            (isempty(s) || startswith(s, "#")) && error("non-numeric string for $T: $(repr(raw))")
            return T(round(Int, parse(Float64, s)))
        end
        n = raw isa Number ? raw : parse(Float64, string(raw))
        return T(round(Int, n))
    elseif T <: AbstractFloat
        if raw isa AbstractString
            s = strip(raw)
            (isempty(s) || startswith(s, "#")) && error("non-numeric string for $T: $(repr(raw))")
            return T(parse(Float64, s))
        end
        n = raw isa Number ? raw : parse(Float64, string(raw))
        return T(n)
    elseif T <: Bool
        return raw isa Bool ? raw : parse(Bool, string(raw))
    elseif T <: AbstractString
        # Prefer "2" over "2.0" for whole-number stats stored as strings
        if raw isa AbstractFloat && isinteger(raw)
            return string(Int(raw))
        end
        return string(raw)
    else
        return convert(T, raw)
    end
end

function build_julia_to_json_map(row)::Dict{String, String}
    Dict{String, String}(to_julia_field_name(String(k)) => String(k) for k in keys(row))
end

function json_row_get(row, json_key::String)
    if haskey(row, Symbol(json_key))
        return row[Symbol(json_key)]
    elseif haskey(row, json_key)
        return row[json_key]
    else
        return nothing
    end
end

function rebuild_entry_from_json(old, row, julia_to_json::Dict{String, String})
    T = typeof(old)
    args = Vector{Any}(undef, fieldcount(T))
    for (i, fname) in enumerate(fieldnames(T))
        json_key = get(julia_to_json, String(fname), nothing)
        raw = json_key === nothing ? nothing : json_row_get(row, json_key)
        if String(fname) == "key" && raw !== nothing
            raw = uppercase(strip(string(raw)))
        end
        args[i] = convert_json_value(raw, fieldtype(T, fname))
    end
    return T(args...)
end

function reload_sheet_dict!(dict::AbstractDict{String, V}, json_path::String) where V
    if !isfile(json_path)
        @warn "JULGAME_LIVE_DATA: JSON not found, skipping" path=json_path
        return
    end

    data = JSON3.read(read(json_path, String))
    if isempty(data)
        @warn "JULGAME_LIVE_DATA: empty JSON, skipping" path=json_path
        return
    end

    julia_to_json = build_julia_to_json_map(first(data))
    updated = 0
    skipped = 0

    for row in data
        isa(row, JSON3.Object) || continue
        haskey(row, :Key) || haskey(row, "Key") || continue
        key_raw = haskey(row, :Key) ? row[:Key] : row["Key"]
        isa(key_raw, String) || continue
        key = uppercase(strip(key_raw))

        if !haskey(dict, key)
            @info "JULGAME_LIVE_DATA: unknown key (needs rebuild for new types)" key=key sheet=basename(json_path)
            skipped += 1
            continue
        end

        try
            dict[key] = rebuild_entry_from_json(dict[key], row, julia_to_json)
            updated += 1
        catch e
            @warn "JULGAME_LIVE_DATA: failed to rebuild entry; keeping compiled value" key=key error=e
            skipped += 1
        end
    end
end

function reload_game_data_from_json!()
    gdm_dir = resolve_game_data_manager_dir()
    json_dir = joinpath(gdm_dir, "json")

    targets = (
        ("Treasures.json", Scripts.Globals.TreasuresModule.ALL_TREASURES),
        ("Pieces.json", Scripts.Globals.PiecesModule.ALL_PIECES),
        ("Potions.json", Scripts.Globals.PotionsModule.ALL_POTIONS),
        ("Enemies.json", Scripts.Globals.EnemiesModule.ALL_ENEMIES),
        ("RandomEvents.json", Scripts.Globals.RandomEventsModule.ALL_RANDOMEVENTS),
        ("Characters.json", Scripts.Globals.CharactersModule.ALL_CHARACTERS),
        ("EnemyComps.json", Scripts.Globals.EnemyCompsModule.ALL_ENEMYCOMPS),
        ("Encounters.json", Scripts.Globals.EncountersModule.ALL_ENCOUNTERS),
        ("Statuses.json", Scripts.Globals.StatusesModule.ALL_STATUSES),
    )

    for (filename, dict) in targets
        reload_sheet_dict!(dict, joinpath(json_dir, filename))
    end
    return nothing
end
