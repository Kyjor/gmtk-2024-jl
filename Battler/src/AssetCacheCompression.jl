module AssetCacheCompression

const BUNDLE_DIRNAME = "release-bundle"

function asset_bundle_root(project_root::String)
    joinpath(project_root, BUNDLE_DIRNAME)
end

function folders_after_base_folder(path::String, base_folder::String)
    normalized_path = replace(path, '\\' => '/')
    parts = split(normalized_path, '/')
    base_folder_index = findfirst(==(base_folder), parts)
    if base_folder_index === nothing
        return ""
end
    subdirs = parts[(base_folder_index + 1):end]
    isempty(subdirs) ? "" : join(subdirs, ",") * ","
end

export asset_bundle_root, folders_after_base_folder

end
