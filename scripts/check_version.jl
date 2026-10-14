#!/usr/bin/env julia
# Version validation script
# Checks if version in Project.toml matches required version based on commits
# Can be run locally or in CI

using Pkg
try
    using TOML
catch
    Pkg.add("TOML")
    using TOML
end
try
    using JSON3
catch
    Pkg.add("JSON3")
    using JSON3
end

const PROJECT_TOML_PATH = joinpath(@__DIR__, "..", "Battler", "Project.toml")
const CONFIG_PATH = joinpath(@__DIR__, "..", ".version_config.json")
const REPO_PATH = joinpath(@__DIR__, "..")

# Version bump types
@enum VersionBumpType PATCH MINOR MAJOR

# Commit keyword mappings for semantic versioning
const PATCH_KEYWORDS = ["fix:", "bug:", "improve:", "perf:"]
const MINOR_KEYWORDS = ["feature:", "feat:", "add:", "new:", "update:", "upd:", "change:", "modify:"]
const BREAKING_KEYWORDS = ["[BREAKING]", "BREAKING:", "breaking:"]

function get_git_call()::String
    if haskey(ENV, "SHOULD_BUILD")
        if Sys.iswindows()
            return "C:\\Program Files\\Git\\bin\\git.exe"
        elseif Sys.islinux()
            return "/usr/bin/git"
        elseif Sys.isapple()
            return "/opt/homebrew/bin/git"
        else
            return "git"
        end
    else
        return "git"
    end
end

function get_last_tag()::Union{String, Nothing}
    try
        git_cmd = `$(get_git_call()) -C $REPO_PATH describe --tags --abbrev=0`
        # Suppress stderr (e.g. when no tags exist) without relying on shell redirection
        tag = chomp(read(pipeline(git_cmd; stderr=devnull), String))
        return isempty(tag) ? nothing : tag
    catch
        return nothing
    end
end

function get_commits_since_tag(tag::Union{String, Nothing}, base_ref::Union{String, Nothing}=nothing)::Vector{String}
    try
        if tag === nothing && base_ref === nothing
            # Get all commits
            git_cmd = `$(get_git_call()) -C $REPO_PATH log --pretty=format:"%s"`
        elseif base_ref !== nothing
            # Use origin/<branch> in CI where only remote-tracking refs exist
            base_range = startswith(base_ref, "origin/") ? base_ref : "origin/$base_ref"
            git_cmd = `$(get_git_call()) -C $REPO_PATH log $(base_range)..HEAD --pretty=format:"%s"`
        elseif tag !== nothing
            # Get commits since tag
            git_cmd = `$(get_git_call()) -C $REPO_PATH log $(tag)..HEAD --pretty=format:"%s"`
        else
            return String[]
        end
        
        commits_str = read(git_cmd, String)
        commits = filter(!isempty, split(commits_str, '\n'))
        return String.(commits)
    catch
        return String[]
    end
end

function analyze_commits_for_version_bump(commits::Vector{String})::VersionBumpType
    if isempty(commits)
        return PATCH  # Default to patch if no commits
    end
    
    has_breaking = false
    has_minor = false
    has_patch = false
    
    for commit in commits
        commit_lower = lowercase(commit)
        
        # Check for breaking changes
        if any(occursin(keyword, commit_lower) for keyword in BREAKING_KEYWORDS)
            has_breaking = true
            continue
        end
        
        # Check for minor version changes
        if any(startswith(commit_lower, keyword) for keyword in MINOR_KEYWORDS)
            has_minor = true
            continue
        end
        
        # Check for patch version changes
        if any(startswith(commit_lower, keyword) for keyword in PATCH_KEYWORDS)
            has_patch = true
        end
    end
    
    # Determine bump type (highest priority)
    if has_breaking
        return MAJOR
    elseif has_minor
        return MINOR
    elseif has_patch
        return PATCH
    else
        # If commits don't match keywords, default to patch
        return PATCH
    end
end

function get_current_version()::String
    try
        project_data = TOML.parsefile(PROJECT_TOML_PATH)
        return project_data["version"]
    catch e
        error("Failed to read version from Project.toml: $e")
    end
end

function parse_version(version_str::String)::Tuple{Int, Int, Int, Union{String, Nothing}}
    # Parse version like "0.0.5-alpha" or "1.2.3"
    parts = split(version_str, '-')
    version_part = parts[1]
    prerelease = length(parts) > 1 ? parts[2] : nothing
    
    version_numbers = split(version_part, '.')
    major = parse(Int, version_numbers[1])
    minor = length(version_numbers) > 1 ? parse(Int, version_numbers[2]) : 0
    patch = length(version_numbers) > 2 ? parse(Int, version_numbers[3]) : 0
    
    return (major, minor, patch, prerelease)
end

function bump_version(current_version::String, bump_type::VersionBumpType, tag_type::String)::String
    major, minor, patch, _ = parse_version(current_version)
    
    if bump_type == MAJOR
        major += 1
        minor = 0
        patch = 0
    elseif bump_type == MINOR
        minor += 1
        patch = 0
    elseif bump_type == PATCH
        patch += 1
    end
    
    new_version = "$major.$minor.$patch"
    if tag_type != "release"
        new_version = "$new_version-$tag_type"
    end
    
    return new_version
end

function get_tag_type()::String
    try
        if isfile(CONFIG_PATH)
            config = JSON3.read(read(CONFIG_PATH, String))
            tag_type = get(config, :tag_type, "alpha")
            allowed = get(config, :allowed_tag_types, ["alpha", "beta", "release"])
            if tag_type in allowed
                return tag_type
            end
        end
    catch
    end
    return "alpha"  # Default
end

function main(exit_on_error::Bool=true, base_ref::Union{String, Nothing}=nothing)
    println("🔍 Checking version consistency...")
    
    # Get last tag from base branch (for PR scenarios) or current branch
    last_tag = get_last_tag()
    if last_tag !== nothing
        println("📌 Last tag: $last_tag")
    else
        println("📌 No previous tags found")
    end
    
    # Get commits since last tag (or since base_ref for PRs)
    commits = get_commits_since_tag(last_tag, base_ref)
    if base_ref !== nothing
        println("📝 Found $(length(commits)) commit(s) in PR (since $base_ref)")
    else
        println("📝 Found $(length(commits)) commit(s) since last tag")
    end
    
    if isempty(commits)
        println("✅ No commits since last tag. Version check passed.")
        return true
    end
    
    # Analyze commits
    bump_type = analyze_commits_for_version_bump(commits)
    bump_type_str = bump_type == MAJOR ? "MAJOR" : bump_type == MINOR ? "MINOR" : "PATCH"
    println("📊 Required version bump: $bump_type_str")
    
    # Get current version
    current_version = get_current_version()
    println("📦 Current version in Project.toml: $current_version")
    
    # Get tag type from config
    tag_type = get_tag_type()
    
    # Calculate required version
    # For PRs, we need to get the base version from the base branch
    base_version = current_version
    if base_ref !== nothing
        # Try to get version from base branch's Project.toml
        try
            git_cmd = `$(get_git_call()) -C $REPO_PATH show origin/$(base_ref):Battler/Project.toml`
            base_toml = read(git_cmd, String)
            base_data = TOML.parse(base_toml)
            base_version = base_data["version"]
            println("📦 Base branch version: $base_version")
        catch
            # Fall back to using last tag version
            if last_tag !== nothing
                base_version = replace(last_tag, "v" => "")
                println("📦 Using last tag version as base: $base_version")
            end
        end
    elseif last_tag !== nothing
        # Extract version from tag (remove 'v' prefix)
        base_version = replace(last_tag, "v" => "")
        println("📦 Using last tag version as base: $base_version")
    end
    
    # Calculate required version based on base version
    required_version = bump_version(base_version, bump_type, tag_type)
    println("✨ Required version: $required_version")
    
    # Compare versions
    if current_version == required_version
        println("✅ Version check passed! Current version matches required version.")
        return true
    else
        println("❌ Version check failed!")
        println("   Current version:  $current_version")
        println("   Required version: $required_version")
        println("\n💡 Run the version bump script to fix this:")
        println("   julia scripts/bump_version.jl")
        
        if exit_on_error
            exit(1)
        end
        return false
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

