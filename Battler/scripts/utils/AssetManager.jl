module AssetManager
    export initialize_asset_registry, get_asset_path, get_available_versions

    # Store asset information: type -> name -> AssetInfo
    struct AssetInfo
        versions::Vector{Int}
        extension::String
    end

    const ASSET_REGISTRY = Dict{String, Dict{String, AssetInfo}}()
    const FALLBACK_PATH = "missing-asset.png"

    """
    Parse a filename that follows the pattern: {type}-{name}-{version}.{ext}
    Returns (type, name, version, extension) or nothing if pattern doesn't match
    """
    function parse_asset_filename(filename::String)
        # Remove extension
        parts = split(filename, '.')
        if length(parts) < 2
            return nothing
        end

        extension = parts[end]
        name_part = join(parts[1:end-1], '.')

        # Split by hyphen
        segments = split(name_part, '-')
        if length(segments) < 3
            return nothing
        end

        # Last segment should be version (4 digits)
        version_str = segments[end]
        if length(version_str) != 4 || !all(isdigit, version_str)
            return nothing
        end

        version = parse(Int, version_str)
        asset_type = segments[1]
        asset_name = join(segments[2:end-1], '-')

        return (asset_type, asset_name, version, extension)
    end

    """
    Initialize the asset registry by scanning all provided asset dictionaries
    """
    function initialize_asset_registry(asset_dicts::Dict{String, Vector{UInt8}}...)
        empty!(ASSET_REGISTRY)

        for asset_dict in asset_dicts
            for (filename, _) in asset_dict
                parsed = parse_asset_filename(filename)
                if parsed !== nothing
                    asset_type, asset_name, version, extension = parsed

                    # Initialize type dict if needed
                    if !haskey(ASSET_REGISTRY, asset_type)
                        ASSET_REGISTRY[asset_type] = Dict{String, AssetInfo}()
                    end

                    # Initialize or update asset info
                    if !haskey(ASSET_REGISTRY[asset_type], asset_name)
                        ASSET_REGISTRY[asset_type][asset_name] = AssetInfo([version], extension)
                    else
                        info = ASSET_REGISTRY[asset_type][asset_name]
                        if version ∉ info.versions
                            push!(info.versions, version)
                            sort!(info.versions)
                        end
                    end
                end
            end
        end

        @debug "Asset registry initialized with $(length(ASSET_REGISTRY)) asset types"
        @debug "Asset registry contains $(length(ASSET_REGISTRY["piece"])) pieces"
        @debug "$(ASSET_REGISTRY["piece"])"
        @debug "Asset registry contains $(length(ASSET_REGISTRY["potion"])) potions"
        @debug "Asset registry contains $(length(ASSET_REGISTRY["treasure"])) treasures"
        @debug "Asset registry contains $(length(ASSET_REGISTRY["enemy"])) enemies"
    end

    """
    Get asset path by type, name, and optional version

    # Arguments
    - `asset_type::String`: Type of asset (e.g., "piece", "potion", "treasure")
    - `asset_name::String`: Name of asset (e.g., "sword", "red")
    - `version`: Optional version - can be:
        - `Int`: Specific version number (0, 1, 2, etc.)
        - `:latest`: Get latest version (default)
        - `:earliest`: Get earliest version

    # Returns
    - Filename string (e.g., "piece-sword-0002.png")
    - Falls back to FALLBACK_PATH if asset not found
    """
    function get_asset_path(asset_type::String, asset_name::String, version=:latest)
        # Check if asset type exists
        @debug "Checking if asset type exists: $asset_type"
        if !haskey(ASSET_REGISTRY, asset_type)
            @warn "Asset type not found: $asset_type"
            return FALLBACK_PATH
        end

        # Check if asset name exists
        @debug "Checking if asset name exists: $asset_name"
        if !haskey(ASSET_REGISTRY[asset_type], asset_name)
            @warn "Asset not found: $asset_type/$asset_name"
            return FALLBACK_PATH
        end

        info = ASSET_REGISTRY[asset_type][asset_name]

        # Determine which version to use
        selected_version = if version == :latest
            maximum(info.versions)
        elseif version == :earliest
            minimum(info.versions)
        elseif version isa Int
            if version ∈ info.versions
                version
            else
                @warn "Version $version not found for $asset_type/$asset_name, using latest"
                maximum(info.versions)
            end
        else
            @warn "Invalid version parameter: $version, using latest"
            maximum(info.versions)
        end

        # Build and return filename
        return "$(asset_type)-$(asset_name)-$(lpad(selected_version, 4, '0')).$(info.extension)"
    end

    """
    Get the latest asset path from an unversioned id `"{type}-{name}"` (e.g. `"ui-newgamebox"`).
    Lets load-time constants name assets before the registry is initialized.
    """
    function get_asset_path(asset_id::AbstractString)
        asset_type, asset_name = split(asset_id, '-'; limit = 2)
        return get_asset_path(String(asset_type), String(asset_name))
    end

    """
    Get all available versions for an asset
    """
    function get_available_versions(asset_type::String, asset_name::String)
        if !haskey(ASSET_REGISTRY, asset_type) || !haskey(ASSET_REGISTRY[asset_type], asset_name)
            return Int[]
        end
        return ASSET_REGISTRY[asset_type][asset_name].versions
    end

    """
    Check if an asset exists
    """
    function asset_exists(asset_type::String, asset_name::String)
        return haskey(ASSET_REGISTRY, asset_type) && haskey(ASSET_REGISTRY[asset_type], asset_name)
    end

end
