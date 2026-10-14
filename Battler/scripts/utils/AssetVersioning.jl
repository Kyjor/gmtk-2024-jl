module AssetVersioning

export MAP_VERSIONS
const MAP_VERSIONS = Dict(
    "alpha" => "0000",
    "default" => "0001",
    "v0.0.4-alpha" => "0001",
    "v0.0.5-alpha" => "0001",
)

export get_map_version
# If the version is not in the MAP_VERSIONS, return the default version     
function get_map_version(version::String)
    if version in keys(MAP_VERSIONS)
        return MAP_VERSIONS[version]
    else
        return MAP_VERSIONS["default"]
    end
end

end # module AssetVersioning