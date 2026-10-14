abstract type BaseStruct end
using ...Globals

function Base.getproperty(script::BaseStruct, property::Symbol)
    dm = Globals.get_data_manager()
    current_language = dm.current_language
    if property == :name
        # check if the property exists
        if hasfield(typeof(script), Symbol("$(lowercase(current_language))_name"))
            name = getfield(script, Symbol("$(lowercase(current_language))_name"))
        else
            name = getfield(script, :en_name)
        end

        if name === nothing || name == ""
            name = getfield(script, :en_name)
        end

        return replace_placeholders(script, name)
    elseif property == :description
        description = getfield(script, Symbol("$(lowercase(current_language))_desc"))
        if description === nothing || description == ""
            return getfield(script, :en_desc)
        end
        return replace_placeholders(script, description)
    elseif property == :average_price || property == :defense || property == :burn || property == :attack || property == :poison || property == :attack_self || property == :vulnerable || property == :hit_percentage || property == :freeze || property == :heal || property == :rarity
        return apply_modifications(script, property)
    end

    return getfield(script, property)
end

function replace_placeholders(script::BaseStruct, input::String)
    # Replace all occurrences of the placeholder in the string
    # get every instance of {} and get the string between them
    placeholders = collect(eachmatch(r"\{(.*?)\}", input))
    if !isempty(placeholders)
        for match in placeholders
            placeholder = match.captures[1]
            input = replace(input, "{" * placeholder * "}" => string(apply_modifications(script, Symbol(lowercase(placeholder)))))
        end
    end

    return input
end

function parse_stat_value(val)
    if val === nothing
        return 0
    end
    # Live-data / spreadsheet export can leave numeric stats as strings ("2", "0.75").
    # Combat and tooltips compare/multiply these as numbers.
    if val isa AbstractString
        s = strip(val)
        if !isempty(s) && !startswith(s, "#")
            n = tryparse(Float64, s)
            if n !== nothing
                return isinteger(n) ? Int(n) : n
            end
        end
        return 0
    end
    return val
end

function apply_modifications(script, property::Symbol)
    return parse_stat_value(getfield(script, property))
end
