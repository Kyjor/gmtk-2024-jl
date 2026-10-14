#!/usr/bin/env julia
# Version bump script for semantic versioning
# Analyzes commits since last tag and determines required version bump
# Updates Project.toml and creates git tag

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
        git_cmd = `$(get_git_call()) -C $REPO_PATH describe --tags --abbrev=0 2>/dev/null`
        tag = chomp(read(git_cmd, String))
        return isempty(tag) ? nothing : tag
    catch
        return nothing
    end
end

function get_commits_since_tag(tag::Union{String, Nothing})::Vector{String}
    if tag === nothing
        # Get all commits
        git_cmd = `$(get_git_call()) -C $REPO_PATH log --pretty=format:"%s"`
    else
        # Get commits since tag
        git_cmd = `$(get_git_call()) -C $REPO_PATH log $(tag)..HEAD --pretty=format:"%s"`
    end
    
    try
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

function update_project_toml(new_version::String)
    try
        project_data = TOML.parsefile(PROJECT_TOML_PATH)
        project_data["version"] = new_version
        
        open(PROJECT_TOML_PATH, "w") do io
            TOML.print(io, project_data)
        end
        
        println("✓ Updated Project.toml: version = \"$new_version\"")
    catch e
        error("Failed to update Project.toml: $e")
    end
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

function create_git_tag(version::String)
    tag_name = "v$version"
    try
        git_cmd = `$(get_git_call()) -C $REPO_PATH tag $tag_name`
        run(git_cmd)
        println("✓ Created git tag: $tag_name")
    catch e
        error("Failed to create git tag: $e")
    end
end

function create_version_commit(new_version::String)
    try
        git_cmd_add = `$(get_git_call()) -C $REPO_PATH add $PROJECT_TOML_PATH`
        run(git_cmd_add)
        
        commit_msg = "update: Bump version to $new_version [version: $new_version]"
        git_cmd_commit = `$(get_git_call()) -C $REPO_PATH commit -m $commit_msg`
        run(git_cmd_commit)
        
        println("✓ Created commit: $commit_msg")
    catch e
        error("Failed to create commit: $e")
    end
end

function main()
    println("🔍 Analyzing commits for version bump...")
    
    # Get last tag
    last_tag = get_last_tag()
    if last_tag !== nothing
        println("📌 Last tag: $last_tag")
    else
        println("📌 No previous tags found")
    end
    
    # Get commits since last tag
    commits = get_commits_since_tag(last_tag)
    println("📝 Found $(length(commits)) commit(s) since last tag")
    
    if isempty(commits)
        println("⚠️  No commits found. Nothing to bump.")
        return
    end
    
    # Analyze commits
    bump_type = analyze_commits_for_version_bump(commits)
    bump_type_str = bump_type == MAJOR ? "MAJOR" : bump_type == MINOR ? "MINOR" : "PATCH"
    println("📊 Required version bump: $bump_type_str")
    
    # Get current version
    current_version = get_current_version()
    println("📦 Current version: $current_version")
    
    # Get tag type from config
    tag_type = get_tag_type()
    println("🏷️  Tag type: $tag_type")
    
    # Calculate new version
    new_version = bump_version(current_version, bump_type, tag_type)
    println("✨ New version: $new_version")
    
    # Confirm
    print("Proceed with version bump? (y/n): ")
    response = readline()
    if lowercase(strip(response)) != "y"
        println("Cancelled.")
        return
    end
    
    # Update Project.toml
    update_project_toml(new_version)
    
    # Create commit
    create_version_commit(new_version)
    
    # Create tag
    create_git_tag(new_version)
    
    println("\n✅ Version bump complete!")
    println("   New version: $new_version")
    println("   Tag: v$new_version")
    println("\n💡 Don't forget to push the commit and tag:")
    println("   git push")
    println("   git push --tags")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

