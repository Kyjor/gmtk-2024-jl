module Globals
using JSON3
using Dates
using JulGame

include("Observer.jl")
include("User.jl")
include("../types/Treasures.jl")
include("../types/Characters.jl")
include("../types/Potions.jl")
include("../types/RandomEvents.jl")
include("../types/Enemies.jl")
include("../types/EnemyComps.jl")
include("../types/Pieces.jl")
include("../types/Encounters.jl")
include("../types/Statuses.jl")
#include("../types/Settings.jl") # TODO: Add Settings.jl
include("PersistentStateManager.jl")
include("RunRecorder.jl")
include("SaveManager.jl")
include("SfxChannels.jl")
include("AudioManager.jl")
include("MetaProgress.jl")
include("AchievementTracker.jl")
include("Analytics.jl")
include("Steam.jl")
include("AssetManager.jl")

using .TreasuresModule
using .CharactersModule
using .PotionsModule
using .RandomEventsModule
using .EnemiesModule
using .EnemyCompsModule
using .PiecesModule
using .PersistentStateManagerModule
using .SaveManagerModule
using .StatusesModule
using .UserModule
using .AudioManagerModule
using .AnalyticsModule
using .MetaProgressModule
using .AchievementTrackerModule
using .SteamModule
using .ObserverModule
using .AssetManager
using ..DJModule

# Constants
const SUPPORTED_LANGUAGES = [
    "EN", 
    "JP", 
    # "DE", 
    # "FR", 
    # "ES", 
    # "IT", 
    # "KO", 
    # "PT", 
    # "RU", 
    # "ZH"
]

# Keywords to filter commit messages - commits containing any of these will be included
const COMMIT_KEYWORDS = [
    "feature:", "feat:",
    "fix:", "bug:",
    "update:", "upd:",
    "add:", "new:",
    "change:", "modify:",
    "improve:", "perf:",
    #"refactor:", "ref:",
    #"doc", "docs",
    #"style", #"ui",
    #"test", "tests",
    #"chore", "build",
    #"revert", "rollback"
]

# Secret key for HMAC validation - in a real application, this could be loaded from a secure location
# This constant is deliberately long and unique but would be better if loaded from environment variables
const SAVE_DATA_SECRET_KEY = "7c42a14b8be54e3d9c5a8d1f3b6e9a2d5f8c7b4a1e3d6f9c2b5a8d1f3e6c9b2a5d8f1c4e7a"

# Game-data JSON baked into the module at compile time (like scenes/assets in
# Battler.jl) so built exes don't depend on on-disk source paths.
const LOCALIZATION_JSON_BYTES = read(joinpath(@__DIR__, "..", "..", "assets", "game-data-manager", "localization", "Localization_.json"))
const BASE_NUMBERS_JSON_BYTES = read(joinpath(@__DIR__, "..", "..", "assets", "game-data-manager", "json", "BaseNumbers.json"))

# Prefer the on-disk file in dev (supports hot-reload); fall back to baked bytes in built exes.
function _read_game_data_json(baked_bytes::Vector{UInt8}, path_parts::String...)
    path = joinpath(@__DIR__, "..", "..", "assets", "game-data-manager", path_parts...)
    return isfile(path) ? read(path) : baked_bytes
end

# True in dev (repo checkout); false in built exes where the baked @__DIR__ path is dead.
_git_repo_available() = isdir(joinpath(@__DIR__, "..", "..", "..", ".git"))

"""Version from Project.toml, or `nothing` when the file is unreachable (built exe)."""
function _read_project_toml_version()::Union{String, Nothing}
    try
        project_path = joinpath(@__DIR__, "..", "..", "Project.toml")
        isfile(project_path) || return nothing
        version_match = match(r"version\s*=\s*\"([^\"]+)\"", read(project_path, String))
        return version_match !== nothing ? String(version_match.captures[1]) : nothing
    catch e
        @error "Failed to read Project.toml: $e"
        return nothing
    end
end

# Define the struct to hold all managed data
mutable struct GameDataManager
    current_language::String
    localization_data::Union{JSON3.Object, Nothing}
    piece_data::Dict{String, PiecesModule.Piece}
    potion_data::Dict{String, PotionsModule.Potion}
    enemy_data::Dict{String, EnemiesModule.Enemie}
    random_event_data::Dict{String, RandomEventsModule.RandomEvent}
    treasure_data::Dict{String, TreasuresModule.Treasure}
    potions_data::Dict{String, PotionsModule.Potion}
    characters_data::Dict{String, CharactersModule.Character}
    enemy_comps_data::Dict{String, EnemyCompsModule.EnemyComp}
    encounter_data::Dict{String, EncountersModule.Encounter}
    filtered_release_notes::Union{String, Nothing}
    release_notes::Union{String, Nothing}
    paged_release_notes::Union{Vector{String}, Nothing}
    version::Union{String, Nothing}
    persistent_state_manager::Union{PersistentStateManagerModule.PersistentStateManager, Nothing}
    user_data::Union{UserModule.User, Nothing}
    base_numbers_data::Union{Vector{JSON3.Object}, Nothing}
    analytics_data::Union{AnalyticsModule.Analytics, Nothing}
    steam_data::Union{SteamModule.Steam, Nothing}
    meta_progress::Union{MetaProgressModule.MetaProgress, Nothing}
    current_battle_manager
    observer::Union{ObserverModule.Observer, Nothing}
    # Audio settings
    audio_manager::Union{Nothing, Any}
    master_volume::Int
    music_volume::Int
    sfx_volume::Int
    menu_sound_volume::Int
    # Game speed (0.5x to 3.0x multiplier, default 1.0x)
    game_speed_multiplier::Float64
    
    # Constructor for initial default state
    function GameDataManager() 
        new(
            "EN", 
            nothing, 
            PiecesModule.ALL_PIECES, 
            PotionsModule.ALL_POTIONS, 
            EnemiesModule.ALL_ENEMIES, 
            RandomEventsModule.ALL_RANDOMEVENTS, 
            TreasuresModule.ALL_TREASURES, 
            PotionsModule.ALL_POTIONS, 
            CharactersModule.ALL_CHARACTERS, 
            EnemyCompsModule.ALL_ENEMYCOMPS,
            EncountersModule.ALL_ENCOUNTERS,
            nothing,
            nothing,
            nothing,
            nothing, 
            nothing, 
            nothing, 
            nothing, 
            nothing, 
            nothing, 
            nothing,
            nothing,
            ObserverModule.Observer(),
            nothing,
            100, 
            100, 
            100, 
            100,
            1.0  # Default game speed multiplier (1.0x = normal speed)
        )
    end
end

# Singleton instance reference
const _DATA_MANAGER_INSTANCE = Ref{Union{GameDataManager, Nothing}}(nothing)

"""
    get_data_manager() -> GameDataManager

Returns the singleton instance of the GameDataManager.
Initializes the instance on the first call.
"""
function get_data_manager()::GameDataManager
    # Check if already initialized
    if _DATA_MANAGER_INSTANCE[] === nothing
        @debug "Initializing GameDataManager singleton"
        _DATA_MANAGER_INSTANCE[] = GameDataManager()
        _load_localization_data(_DATA_MANAGER_INSTANCE[])
        _load_piece_data(_DATA_MANAGER_INSTANCE[])
        _load_enemy_data(_DATA_MANAGER_INSTANCE[])
        _load_random_event_data(_DATA_MANAGER_INSTANCE[])
        _load_treasure_data(_DATA_MANAGER_INSTANCE[])
        _load_potion_data(_DATA_MANAGER_INSTANCE[])
        # Version and release notes are loaded lazily via get_version()/get_release_notes*()
        # — they spawn git subprocesses and must stay off the startup path.
        _load_user_data(_DATA_MANAGER_INSTANCE[], _DATA_MANAGER_INSTANCE[].piece_data)
        _load_persistent_state_manager(_DATA_MANAGER_INSTANCE[])
        _initialize_audio_manager(_DATA_MANAGER_INSTANCE[])
        _load_audio_volumes(_DATA_MANAGER_INSTANCE[])
        _load_base_numbers_data(_DATA_MANAGER_INSTANCE[])
        _load_potions_data(_DATA_MANAGER_INSTANCE[])
        _load_characters_data(_DATA_MANAGER_INSTANCE[])
        _load_enemy_comps_data(_DATA_MANAGER_INSTANCE[])
        _load_encounter_data(_DATA_MANAGER_INSTANCE[])
        _load_analytics_data(_DATA_MANAGER_INSTANCE[])
        _load_meta_progress(_DATA_MANAGER_INSTANCE[])
        _load_observer_data(_DATA_MANAGER_INSTANCE[])
        # DO NOT LOAD STEAM DATA HERE, IT WILL COMPILE AND BREAK THE APP IN BUILD
    end
    return _DATA_MANAGER_INSTANCE[]
end

# Private loading functions
function _load_localization_data(manager::GameDataManager)
    if manager.localization_data === nothing
        try
            bytes = _read_game_data_json(LOCALIZATION_JSON_BYTES, "localization", "Localization_.json")
            manager.localization_data = JSON3.read(String(copy(bytes)))
        catch e
            @error "Failed to load localization data: $e"
            # Optionally set to an empty object or rethrow
            manager.localization_data = JSON3.read("{}")
        end
    end
end

function _load_piece_data(manager::GameDataManager)
    if manager.piece_data === nothing
        try
            manager.piece_data = PiecesModule.ALL_PIECES
        catch e
            @error "Failed to load piece data: $e"
            manager.piece_data = Dict{String, PiecesModule.Piece}()
        end
    end
end

function _load_enemy_data(manager::GameDataManager)
    if manager.enemy_data === nothing
        try
            manager.enemy_data = EnemiesModule.ALL_ENEMIES
        catch e
            @error "Failed to load enemy data: $e"
            manager.enemy_data = Dict{String, EnemiesModule.Enemie}()
        end
    end
end

function _load_random_event_data(manager::GameDataManager)
    if manager.random_event_data === nothing
        try
            manager.random_event_data = RandomEventsModule.ALL_RANDOMEVENTS
        catch e
            @error "Failed to load random event data: $e"
            manager.random_event_data = Dict{String, RandomEventsModule.RandomEvent}()
        end
    end
end

function _load_treasure_data(manager::GameDataManager)
    if manager.treasure_data === nothing
        try
            manager.treasure_data = TreasuresModule.ALL_TREASURES
        catch e
            @error "Failed to load treasure data: $e"
            manager.treasure_data = Dict{String, TreasuresModule.Treasure}()
        end
    end
end

function _load_potion_data(manager::GameDataManager)
    if manager.potion_data === nothing
        try
            manager.potion_data = PotionsModule.ALL_POTIONS
        catch e
            @error "Failed to load potion data: $e"
            manager.potion_data = Dict{String, PotionsModule.Potion}()
        end
    end
end

function _load_base_numbers_data(manager::GameDataManager)
    if manager.base_numbers_data === nothing
        try
            bytes = _read_game_data_json(BASE_NUMBERS_JSON_BYTES, "json", "BaseNumbers.json")
            manager.base_numbers_data = JSON3.read(String(copy(bytes)))
        catch e
            @error "Failed to load base numbers data: $e"
            manager.base_numbers_data = [JSON3.Object()]
        end
    end
end

function _load_potions_data(manager::GameDataManager)
    if manager.potions_data === nothing
        try
            manager.potions_data = PotionsModule.ALL_POTIONS
        catch e
            @error "Failed to load potions data: $e"
            manager.potions_data = Dict{String, PotionsModule.Potion}()
        end
    end
end

function _load_characters_data(manager::GameDataManager)
    if manager.characters_data === nothing
        try
            manager.characters_data = CharactersModule.ALL_CHARACTERS
        catch e
            @error "Failed to load characters data: $e"
            manager.characters_data = Dict{String, CharactersModule.Character}()
        end
    end
end

function _load_enemy_comps_data(manager::GameDataManager)

    if manager.enemy_comps_data === nothing
        manager.enemy_comps_data = EnemyCompsModule.ALL_ENEMYCOMPS
    end
end

function _load_encounter_data(manager::GameDataManager)
    if manager.encounter_data === nothing
        try
            manager.encounter_data = EncountersModule.ALL_ENCOUNTERS
        catch e
            @error "Failed to load encounter data: $e"
            manager.encounter_data = Dict{String, EncountersModule.Encounter}()
        end
    end
end

function _load_analytics_data(manager::GameDataManager)
    if manager.analytics_data === nothing
        manager.analytics_data = AnalyticsModule.Analytics()
    end
end

function _load_meta_progress(manager::GameDataManager)
    if manager.meta_progress === nothing
        manager.meta_progress = MetaProgressModule.load_meta_progress()
        AchievementTrackerModule.check_achievements!(manager.meta_progress)
        try
            AchievementTrackerModule.sync_steam_achievements!(manager.meta_progress)
        catch e
            @debug "Steam achievement sync on profile load skipped: $e"
        end
    end
end

function get_meta_progress()::MetaProgressModule.MetaProgress
    manager = get_data_manager()
    _load_meta_progress(manager)
    return manager.meta_progress
end

function _load_steam_data(manager::GameDataManager)
    if manager.steam_data === nothing
        @debug("Setting up steam data")
        manager.steam_data = SteamModule.Steam()
        @debug("Steam data set up")
    else
        @debug("Steam data already set up")
    end
end

function _load_observer_data(manager::GameDataManager)
    if manager.observer === nothing
        manager.observer = ObserverModule.Observer()
    end
end

function _load_version(manager::GameDataManager)
    if manager.version === nothing
        version_str = "0.1.0-alpha" # Default
        git_hash = ""
        build_date = Dates.format(Dates.now(), "yyyy/mm/dd")

        # Dev: read Project.toml fresh. Built exe: the @__DIR__ path is dead, so
        # fall back to the version baked in at sysimage-build time.
        project_version = _read_project_toml_version()
        if project_version !== nothing
            version_str = project_version
        elseif BAKED_PROJECT_VERSION != ""
            version_str = BAKED_PROJECT_VERSION
        else
            @warn "Could not read version from Project.toml and no baked version available. Using default version."
        end

        # Get Git commit hash as build number.
        # Dev: run git for a fresh hash. Built exe: use the hash baked at build time.
        if _git_repo_available()
            try
                @debug "Getting git commit hash"
                repo_path = joinpath(@__DIR__, "..", "..", "..")
                git_command = `$(get_git_call()) -C $repo_path rev-parse --short HEAD`
                git_hash = "+$(chomp(read(git_command, String)))"
            catch e
                @warn "Failed to get git commit hash: $e. Skipping git hash."
                # git_hash remains ""
            end
        else
            git_hash = BAKED_GIT_HASH
        end

        # Combine version components
        version_obj = VersionNumber(version_str) # Validate version string format
        manager.version = "v$(version_obj)$(git_hash):$(build_date)"
        @debug "Version loaded: $(manager.version)"
    end
end

function _initialize_audio_manager(manager::GameDataManager)
    if manager.audio_manager === nothing
        @debug "Initializing AudioManager"
        manager.audio_manager = AudioManager()
        
        # Register common sound files first (predefined list of known sounds)
        try
            register_common_sounds()
            @debug "Registered common sound files with AudioManager"
        catch e
            @warn "Failed to register common sounds: $e"
        end
        
        # Then register any existing sounds from the current scene
        try
            AudioManagerModule.register_existing_sounds(manager.audio_manager)
        catch e
            @warn "Failed to register existing sounds: $e"
        end
    end
end

function _load_audio_volumes(manager::GameDataManager)
    # Load audio settings from config file if available
    configPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "audio_settings.txt")
    if !isfile(configPath)
        # Fresh user default: master at 50%, keep category sliders at 100%.
        manager.master_volume = 50
        manager.music_volume = 100
        manager.sfx_volume = 100
    end
    try
        config = Dict{String, Any}()
        open(configPath, "r") do file
            for line in eachline(file)
                if contains(line, "=")
                    key, value = split(line, "=")
                    config[key] = value
                end
            end
        end
        
        # Load audio settings from config
        manager.master_volume = parse(Int, get(config, "MasterVolume", "50"))
        manager.music_volume = parse(Int, get(config, "MusicVolume", "100"))
        manager.sfx_volume = parse(Int, get(config, "SFXVolume", "100"))
        
        manager.master_volume = clamp(manager.master_volume, 0, 100)
        manager.music_volume = clamp(manager.music_volume, 0, 100)
        manager.sfx_volume = clamp(manager.sfx_volume, 0, 100)
        
        @debug "Loaded audio volumes: Master=$(manager.master_volume)%, Music=$(manager.music_volume)%, SFX=$(manager.sfx_volume)%, Menu=$(manager.menu_sound_volume)%"
    catch e
        @warn "Failed to load audio volumes: $e"
    end
    
    # Update AudioManager volumes if initialized
    if manager.audio_manager !== nothing
        # Set AudioManager volumes
        AudioManagerModule.set_volumes(manager.audio_manager, manager.master_volume, manager.music_volume, manager.sfx_volume)
    end
    
    # # Try to apply volumes to any existing audio sources (this will be no-op if scene isn't loaded yet)
    # try
    #     @debug "Applying audio volumes on initial load"
    #     apply_audio_volumes()
    # catch e
    #     @debug "Could not apply audio volumes on initial load: $e"
    # end
end

function _load_release_notes(manager::GameDataManager)
    if manager.release_notes === nothing
        manager.release_notes = generate_release_notes()
    end
    if manager.filtered_release_notes === nothing
        manager.filtered_release_notes = generate_release_notes(true)
    end
end

"""
    get_release_notes_paged(; max_versions::Int = 10) -> Vector{String}

Returns release notes split per version (newest first).
Page 1 = HEAD since last tag, subsequent pages = each prior tag interval.
Results are cached after the first call.
"""
function get_release_notes_paged(; max_versions::Int = 10)::Vector{String}
    manager = get_data_manager()
    if manager.paged_release_notes === nothing
        # Dev: generate fresh from git. Built exe: use pages baked at build time
        # (no repo/git on player machines, and ~30 git spawns cost seconds).
        manager.paged_release_notes = _git_repo_available() ?
            generate_paged_release_notes(max_versions) :
            BAKED_PAGED_RELEASE_NOTES
    end
    return manager.paged_release_notes
end

function _filter_commits(raw::AbstractString)::String
    lines = filter(!isempty, split(raw, '\n'))
    filtered = filter(line -> any(occursin(lowercase(kw), lowercase(line)) for kw in COMMIT_KEYWORDS), lines)
    return join(filtered, '\n')
end

function _tag_date(repo_path, tag::AbstractString)::String
    try
        return chomp(read(`$(get_git_call()) -C $repo_path log -1 --format=%ad --date=short $tag`, String))
    catch
        return ""
    end
end

function generate_paged_release_notes(max_versions::Int)::Vector{String}
    repo_path = joinpath(@__DIR__, "..", "..", "..")
    format_arg = "format:- %s%n"
    pages = String[]

    try
        # Get all tags sorted newest first
        tags_raw = chomp(read(`$(get_git_call()) -C $repo_path tag --sort=-version:refname`, String))
        tags = filter(!isempty, split(tags_raw, '\n'))

        head_hash = chomp(read(`$(get_git_call()) -C $repo_path rev-parse --short HEAD`, String))
        head_date = chomp(read(`$(get_git_call()) -C $repo_path log -1 --format=%ad --date=short HEAD`, String))

        # Page 1: HEAD since most recent tag (or all commits if no tags)
        if isempty(tags)
            raw = chomp(read(`$(get_git_call()) -C $repo_path log --pretty=$format_arg`, String))
            body = _filter_commits(raw)
            header = "All Commits ($head_date, $head_hash)"
            isempty(body) || push!(pages, "$(header)\n\n$(body)")
        else
            tag1 = tags[1]
            tag1_date = _tag_date(repo_path, tag1)
            raw = chomp(read(`$(get_git_call()) -C $repo_path log $tag1..HEAD --pretty=$format_arg`, String))
            body = _filter_commits(raw)
            date_range = isempty(tag1_date) ? head_date : "$(tag1_date) – $(head_date)"
            isempty(body) || push!(pages, "$(tag1) → current  ($date_range)\n\n$(body)")
        end

        # Subsequent pages: each tag pair
        limit = min(length(tags) - 1, max_versions - 1)
        for i in 1:limit
            newer = tags[i]
            older = tags[i + 1]
            newer_date = _tag_date(repo_path, newer)
            older_date = _tag_date(repo_path, older)
            raw = chomp(read(`$(get_git_call()) -C $repo_path log $older..$newer --pretty=$format_arg`, String))
            body = _filter_commits(raw)
            date_range = (isempty(older_date) || isempty(newer_date)) ? "" : "  ($(older_date) – $(newer_date))"
            isempty(body) || push!(pages, "$(older) → $(newer)$(date_range)\n\n$(body)")
        end
    catch e
        @error "Error generating paged release notes: $e"
        push!(pages, "Unable to generate release notes: $e")
    end

    return pages
end

function _load_persistent_state_manager(manager::GameDataManager)
    if manager.persistent_state_manager === nothing
        manager.persistent_state_manager = PersistentStateManagerModule.PersistentStateManager()
    end
end

function _load_user_data(manager::GameDataManager, piece_data::Dict{String, PiecesModule.Piece})
    if manager.user_data === nothing
        manager.user_data = UserModule.User(piece_data)
    end
end

# Public accessor functions
"""
    supported_languages()

Returns the list of supported language codes.
"""
supported_languages() = SUPPORTED_LANGUAGES

"""
    get_current_language()

Returns the currently set language code.
"""
get_current_language() = get_data_manager().current_language

"""
    set_current_language(lang::String)

Sets the current language to `lang` if it's in the supported languages list.
Returns `true` if successful, `false` otherwise.
"""
function set_current_language(lang::String)
    manager = get_data_manager()
    if lang in SUPPORTED_LANGUAGES
        old_lang = manager.current_language
        manager.current_language = lang
        @debug "Current language set to: $lang"
        
        # Notify observers of language change
        if manager.observer !== nothing
            ObserverModule.notify(manager.observer, :language_changed, (old=old_lang, new=lang))
        end
        
        return true
    else
        @warn "Attempted to set unsupported language: $lang"
        return false
    end
end

"""
    get_localization_data()

Returns the loaded localization data.
"""
function get_localization_data()
    manager = get_data_manager()
    _load_localization_data(manager) # Load if not already loaded
    return manager.localization_data
end

"""
    get_localized_string(key::String, default::String=""; kwargs...)

Returns a localized string for the given key in the current language.
Supports placeholder replacement using keyword arguments.

# Arguments
- `key::String`: The localization key (e.g., "UI_Title_New_Run_Title")
- `default::String`: Fallback value if key not found (defaults to empty string)
- `kwargs...`: Key-value pairs for placeholder replacement (e.g., amount=5, name="Sword")

# Examples
```julia
get_localized_string("UI_Title_New_Run_Title")  # Returns "New Run" or "新しいラン"
get_localized_string("Shop_Not_Enough_Gold", "Not enough gold!", amount=50)  # "Not enough gold! You need 50 gold."
```
"""
function get_localized_string(key::String, default::String=""; kwargs...)
    localization_data = get_localization_data()
    current_language = get_current_language()
    
    # Build the full key path
    full_key = "\$gamedata.Localization.$(uppercase(current_language)).$(key)"
    
    # Get the localized string, falling back to English if not found
    result = get(localization_data, full_key, nothing)
    
    # If not found in current language, try English as fallback
    if result === nothing && current_language != "EN"
        en_key = "\$gamedata.Localization.EN.$(key)"
        result = get(localization_data, en_key, default)
    elseif result === nothing
        result = default
    end
    
    # Replace placeholders like {amount}, {name}, etc.
    for (placeholder, value) in kwargs
        result = replace(result, "{$(placeholder)}" => string(value))
    end
    
    return result
end

"""
    refresh_all_localized_texts()

Manually trigger a refresh of all localized UI texts in the current scene.
This is useful when you need to force an update after programmatically changing text.
"""
function refresh_all_localized_texts()
    # This will be called by LocalizationManager if it exists
    # For now, we'll rely on the LocalizationManager's automatic update
    @debug "refresh_all_localized_texts called - LocalizationManager should handle this automatically"
end

"""
    get_piece_data()

Returns the loaded piece data.
"""
function get_piece_data()
    manager = get_data_manager()
    _load_piece_data(manager) # Load if not already loaded
    return manager.piece_data
end

"""
    get_enemy_data()

Returns the loaded enemy data.
"""
function get_enemy_data()
    manager = get_data_manager()
    _load_enemy_data(manager) # Load if not already loaded
    return manager.enemy_data
end

"""
    get_enemy_comps_data()

Returns the loaded enemy comps data.
"""

function get_enemy_comps_data()
    manager = get_data_manager()
    _load_enemy_comps_data(manager) # Load if not already loaded
    return manager.enemy_comps_data
end

"""
    get_encounter_data()

Returns the loaded encounter data.
"""
function get_encounter_data()
    manager = get_data_manager()
    _load_encounter_data(manager) # Load if not already loaded
    return manager.encounter_data
end

"""
    get_random_event_data()

Returns the loaded random event data.
"""
function get_random_event_data()
    manager = get_data_manager()
    _load_random_event_data(manager) # Load if not already loaded
    return manager.random_event_data
end

"""
    get_treasure_data()

Returns the loaded treasure data.
"""
function get_treasure_data()
    manager = get_data_manager()
    _load_treasure_data(manager) # Load if not already loaded
    return manager.treasure_data
end

"""
    get_potion_data()

Returns the loaded potion data.
"""
function get_potion_data()
    manager = get_data_manager()
    _load_potion_data(manager) # Load if not already loaded
    return manager.potion_data
end

function item_available_in_game(x)::Bool
    hasproperty(x, :currently_available_in_game) && x.currently_available_in_game
end

function get_user_data()
    manager = get_data_manager()
    _load_user_data(manager, get_piece_data()) # Load if not already loaded
    return manager.user_data
end

function get_base_numbers_data()
    manager = get_data_manager()
    _load_base_numbers_data(manager) # Load if not already loaded
    return manager.base_numbers_data
end

function get_potions_data()
    manager = get_data_manager()
    _load_potions_data(manager) # Load if not already loaded
    return manager.potions_data
end

function get_characters_data()
    manager = get_data_manager()
    _load_characters_data(manager) # Load if not already loaded
    return manager.characters_data
end

function get_analytics_data()
    manager = get_data_manager()
    _load_analytics_data(manager) # Load if not already loaded
    return manager.analytics_data
end

function get_observer_data()
    manager = get_data_manager()
    _load_observer_data(manager) # Load if not already loaded
    return manager.observer
end

function get_release_notes(filter_by_keywords::Bool=false)
    manager = get_data_manager()
    _load_release_notes(manager) # Load if not already loaded
    @debug "Getting release notes"
    if filter_by_keywords
        return manager.filtered_release_notes
    else
        return manager.release_notes
    end
end

function get_steam_data()
    @debug("Getting steam data")
    manager = get_data_manager()
    _load_steam_data(manager) # Load if not already loaded
    @debug("Steam data loaded")
    return manager.steam_data
end

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

"""
    get_version()

Returns the version string including git hash and build date.
"""
function get_version()
    manager = get_data_manager()
    _load_version(manager) # Load if not already loaded
    return manager.version
end

"""
    get_audio_volumes()

Returns the current audio volume settings as a tuple (master, music, sfx).
Each value is in the range 0-100.
"""
function get_audio_volumes()
    manager = get_data_manager()
    return (manager.master_volume, manager.music_volume, manager.sfx_volume, manager.menu_sound_volume)
end

"""
    set_audio_volumes(master::Int, music::Int, sfx::Int)

Sets the audio volume levels for master, music, sound effects, and menu sounds.
Each value should be in the range 0-100.
"""
function set_audio_volumes(master::Int, music::Int, sfx::Int)
    manager = get_data_manager()
    
    # Clamp values to valid range
    manager.master_volume = clamp(master, 0, 100)
    manager.music_volume = clamp(music, 0, 100)
    manager.sfx_volume = clamp(sfx, 0, 100)
    
    # Update AudioManager if initialized
    if manager.audio_manager !== nothing
        # Set AudioManager volumes
        AudioManagerModule.set_volumes(manager.audio_manager, manager.master_volume, manager.music_volume, manager.sfx_volume)
    else
        # Apply the volume settings to any active audio sources directly
        @debug "Applying audio volumes on set_audio_volumes"
        apply_audio_volumes()
    end
    
    return (manager.master_volume, manager.music_volume, manager.sfx_volume)
end

"""
    apply_dj_volume_settings!()

Updates DJ-managed layered music (patientbravery drums crossfade on event/rest).
"""
function apply_dj_volume_settings!()
    try
        dj = DJModule.try_get_dj()
        if dj !== nothing
            DJModule.apply_volume_settings!(dj)
        end
    catch e
        @debug "apply_dj_volume_settings!: $e"
    end
end

"""
    apply_audio_volumes()

Applies the current volume settings to all active audio sources in the game.
This is called internally when volumes are changed, but can be called manually
if needed when new audio sources are created.
"""
function apply_audio_volumes()
    manager = get_data_manager()
    
    # If AudioManager is initialized, use it to apply volumes
    if manager.audio_manager !== nothing
        @debug "Applying audio volumes on apply_audio_volumes"
        AudioManagerModule.apply_volumes_to_active_sources(manager.audio_manager)
        return
    end
    
    # Legacy fallback if AudioManager is not available
    # Convert percentage to volume scale (0.0-1.0)
    master_vol = manager.master_volume 
    music_vol = round(Int, (manager.music_volume) * (master_vol/100.0))
    sfx_vol = round(Int, (manager.sfx_volume) * (master_vol/100.0))
    
    # Apply to all audio sources in the scene
    if @isdefined(MAIN) && isdefined(MAIN, :scene)
        try
            # Find all entities with sound sources
            for entity in MAIN.scene.entities
                if hasfield(typeof(entity), :soundSource) && entity.soundSource !== nothing
                    # Determine which volume to apply based on sound type
                    # We'll use naming convention - entity names containing "Music" use music volume,
                    # names containing "Menu" use menu volume, all others use SFX volume
                    sound_source = entity.soundSource
                    if entity.name == "CampfireAmbience"
                        continue
                    end
                    
                    if occursin("Music", entity.name)
                        effective_volume = Int32(round(music_vol * 128.0))
                    else
                        effective_volume = Int32(round(sfx_vol * 128.0))
                        @debug "effective_volume: $(effective_volume) for sound_source.path $(sound_source.path) and channel $(sound_source.channel)"
                    end
                    JulGame.Component.set_volume(sound_source, round(Int, clamp(effective_volume, 0, 128)), sound_source.channel)
                end
            end
        catch e
            @warn "Error applying audio volumes: $e"
        end
        @debug "Applying DJ volume settings on apply_audio_volumes"
        apply_dj_volume_settings!()
    end

    # save audio settings to config file
    if manager.audio_manager !== nothing
        save_audio_settings(manager.audio_manager)
    end
end
"""
    save_audio_settings(manager::AudioManager)

Saves the current audio volume settings to the config file.
"""
function save_audio_settings(manager::AudioManager)
    save_settings_to_config(JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "audio_settings.txt"), Dict("MasterVolume" => manager.master_volume, "MusicVolume" => manager.music_volume, "SFXVolume" => manager.sfx_volume))
end

function save_settings_to_config(configPath::String, settings::Dict)
    config = Dict()
    
    # Read existing config
    if isfile(configPath)
        open(configPath, "r") do file
            for line in eachline(file)
                if contains(line, "=")
                    key, value = split(line, "=")
                    config[key] = value
                end
            end
        end
    end
    
    # Update with new settings
    merge!(config, settings)
    
    # Write updated config
    open(configPath, "w") do file
        for (key, value) in config
            write(file, "$(key)=$(value)\n")
        end
    end
end

# Function to reload all data (useful for development/testing)
"""
    reload_all_data()

Reloads all game data from disk.
"""
function reload_all_data()
    manager = get_data_manager() # Get the current instance
    # Reset fields to trigger lazy reloading on next access
    manager.current_language = "EN" # Reset language to default
    manager.localization_data = nothing
    manager.piece_data = nothing
    manager.enemy_data = nothing
    manager.random_event_data = nothing
    manager.treasure_data = nothing
    manager.potion_data = nothing
    manager.version = nothing # Also reload version
    manager.base_numbers_data = nothing
    manager.potions_data = nothing
    manager.characters_data = nothing
    manager.enemy_comps_data = nothing
    manager.encounter_data = nothing
    # Reset audio volumes to default (will be reloaded from config on next access)
    manager.master_volume = 100
    manager.music_volume = 100
    manager.sfx_volume = 100
    manager.menu_sound_volume = 100
    _load_audio_volumes(manager) # Reload from config
    _load_base_numbers_data(manager)
    _load_potions_data(manager)
    _load_characters_data(manager)
    _load_enemy_comps_data(manager)
    _load_encounter_data(manager)
    @debug "All game data fields reset for reloading."

    # Optionally, you could force immediate reloading here by calling _load_* functions
    # e.g., _load_localization_data(manager), _load_piece_data(manager), etc.
    # But lazy loading on next get_* call is often sufficient.
    @debug "Game data reload triggered. Data will be loaded on next access."
end

"""
    generate_release_notes(filter_by_keywords::Bool=false)

Generates release notes by retrieving commit messages between the most recent Git tag and HEAD.
Returns a string containing formatted release notes.

# Arguments
- `filter_by_keywords::Bool`: If true, only include commits containing keywords from COMMIT_KEYWORDS.
"""
function generate_release_notes(filter_by_keywords::Bool=false)
    repo_path = joinpath(@__DIR__, "..", "..", "..")
    @debug "Generating release notes"
    try
        # Get the most recent tag - using separate commands to avoid shell special characters
        last_tag = ""
        tag_commit_hash = ""
        head_commit_hash = ""
        
        # Get the current HEAD commit hash
        try
            head_hash_cmd = `$(get_git_call()) -C $repo_path rev-parse --short HEAD`
            head_commit_hash = chomp(read(head_hash_cmd, String))
        catch e
            @error "Error getting HEAD commit hash: $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end
        
        try
            last_tag_cmd = `$(get_git_call()) -C $repo_path describe --tags --abbrev=0`
            last_tag = chomp(read(last_tag_cmd, String))
            
            # Get the commit hash for the tag
            if !isempty(last_tag)
                tag_hash_cmd = `$(get_git_call()) -C $repo_path rev-list -n 1 $last_tag`
                full_hash = chomp(read(tag_hash_cmd, String))
                tag_commit_hash = !isempty(full_hash) ? full_hash[1:7] : ""  # Get first 7 chars of hash
            end
        catch e
            @error "Error getting most recent tag: $(e)"
            # If the command fails (no tags), we'll use an empty string
            last_tag = ""
        end
        
        # If no tags exist, get all commits
        local commit_messages
        local notes_header
        
        # The format argument needs to be a single string with quotes
        # Using %n will insert a newline after each commit
        format_arg = "format:- %s%n"
        
        if isempty(last_tag)
            log_cmd = `$(get_git_call()) -C $repo_path log --pretty=$format_arg`
            try
                commit_messages = read(log_cmd, String)
                
                # For all commits, show from beginning to current HEAD
                if !isempty(head_commit_hash)
                    notes_header = "Release Notes (All Commits to $(head_commit_hash))"
                else
                    notes_header = "Release Notes (All Commits)"
                end
            catch e
                @error "Error getting all commit messages: $(e)"
                commit_messages = ""
                notes_header = ""
            end
        else
            # Get commit messages between last tag and HEAD
            log_cmd = `$(get_git_call()) -C $repo_path log $last_tag..HEAD --pretty=$format_arg`
            try
                commit_messages = read(log_cmd, String)
                
                # Include commit hashes in the header if available
                if !isempty(tag_commit_hash) && !isempty(head_commit_hash)
                    notes_header = "($(last_tag)-$(tag_commit_hash) to $(head_commit_hash))"
                elseif !isempty(tag_commit_hash)
                    notes_header = "Release Notes ($(last_tag)-$(tag_commit_hash) to Current)"
                elseif !isempty(head_commit_hash)
                    notes_header = "Release Notes ($(last_tag) to $(head_commit_hash))"
                else
                    notes_header = "Release Notes ($(last_tag) to Current)"
                end
            catch e
                @error "Error retrieving release notes: $(e)"
                commit_messages = ""
                notes_header = ""
            end
        end
        
        if isempty(commit_messages)
            return "No changes since last release."
        end
        
        # Filter commit messages by keywords if requested
        if filter_by_keywords
            filtered_messages = String[]
            for line in split(commit_messages, '\n')
                if !isempty(line)
                    # Check if the line contains any of the keywords
                    if any(occursin(lowercase(keyword), lowercase(line)) for keyword in COMMIT_KEYWORDS)
                        push!(filtered_messages, line)
                    end
                end
            end
            
            # Update the header to indicate filtering
            notes_header = "$(notes_header) (Important Changes Only)"
            
            # If no messages match the filter, provide a note
            if isempty(filtered_messages)
                commit_messages = "Bug fixes and improvements."
            else
                commit_messages = join(filtered_messages, "\n")
            end
        end
        
        # Format the release notes
        return """
        $(notes_header)
        
        $(commit_messages)
        """
    catch e
        return "Unable to generate release notes: $(e)"
    end
end

# --- Build-time baked git data ---------------------------------------------
# Shipped builds have no git repo (the baked @__DIR__ path is dead), so
# git-derived data is computed once here at sysimage-build time and baked into
# the module, like LOCALIZATION_JSON_BYTES. Dev runs (repo present) compute
# fresh values at runtime instead, so baking is skipped there to keep package
# precompiles from spawning ~30 git processes.
const _BAKE_GIT_DATA = get(ENV, "PackageCompiling", "false") == "true"

const BAKED_GIT_HASH = _BAKE_GIT_DATA ? (try
    _git_repo_available() ?
        "+$(chomp(read(`$(get_git_call()) -C $(joinpath(@__DIR__, "..", "..", "..")) rev-parse --short HEAD`, String)))" :
        ""
catch
    ""
end) : ""

const BAKED_PAGED_RELEASE_NOTES = _BAKE_GIT_DATA ? (try
    _git_repo_available() ? generate_paged_release_notes(10) : String[]
catch
    String[]
end) : String[]

# Project.toml is also unreachable in shipped builds; bake its version string too.
const BAKED_PROJECT_VERSION = _BAKE_GIT_DATA ? (something(_read_project_toml_version(), "")) : ""

"""
    load_sound(path::String, is_music::Bool, base_volume::Float64 = 1.0, sound_type::Symbol = :sfx)

Registers a sound with the audio manager.
- `path`: Path to the sound file relative to the assets/sounds directory
- `is_music`: Whether this is a music track (true) or a sound effect (false)
- `base_volume`: The base volume for this sound (0.0-1.0)
- `sound_type`: The type of sound - :music, :sfx, or :menu

Returns the loaded sound object or nothing if loading failed.
"""
function load_sound(path::String, is_music::Bool, base_volume::Float64 = 1.0, sound_type::Symbol = :sfx)
    manager = get_data_manager()
    if manager.audio_manager === nothing
        @warn "AudioManager not initialized"
        return nothing
    end
    
    return AudioManagerModule.load_sound(manager.audio_manager, path, is_music, base_volume, sound_type)
end

"""
    play_sound(path::String, loops::Int = 0, channel::Int = SfxChannelsModule.DEFAULT_SFX_CHANNEL)

Plays a sound that has been registered with the audio manager.
- `path`: Path to the sound file
- `loops`: Number of times to loop (-1 for infinite)
- `channel`: SDL audio channel (see SfxChannelsModule)

Returns true if successful, false otherwise.
"""
function play_sound(path::String, loops::Int = 0, channel::Int = SfxChannelsModule.DEFAULT_SFX_CHANNEL)
    manager = get_data_manager()
    if manager.audio_manager === nothing
        @warn "AudioManager not initialized"
        return false
    end
    
    return AudioManagerModule.play_sound(manager.audio_manager, path, loops, channel)
end

"""
    get_audio_manager()

Returns the AudioManager instance.
"""
function get_audio_manager()
    manager = get_data_manager()
    if manager.audio_manager === nothing
        _initialize_audio_manager(manager)
    end
    return manager.audio_manager
end

"""
    register_existing_sounds()

Scans the current scene for entities with sound sources and registers them with the audio manager.
This makes existing sounds work with the volume controls.
"""
function register_existing_sounds()
    manager = get_data_manager()
    
    if manager.audio_manager === nothing
        _initialize_audio_manager(manager)
    end
    
    return AudioManagerModule.register_existing_sounds(manager.audio_manager)
end

"""
    register_common_sounds()

Registers common game sounds with appropriate types and base volumes.
This is useful for ensuring critical sounds have consistent behavior.
"""
function register_common_sounds()
    manager = get_data_manager()
    
    if manager.audio_manager === nothing
        _initialize_audio_manager(manager)
    end
    
    # Common music tracks
    music_files = [
        get_asset_path("music", "synthetichistory"),  # Battle music
    ]
    
    # Common menu sounds
    menu_files = [
        "cursor_hover.wav",
        "cursor_select.wav",
        "click.wav",
        "menu_open.wav",
        "menu_close.wav",
    ]
    
    # Common game SFX
    sfx_files = [
        get_asset_path("sfx", "hit"),      # Default hit sound
        "break_0000.wav",    # Break sound
        "match_0000.wav",    # Match sound
        "collect_0000.wav",  # Collect sound
        "spell_0000.wav",    # Spell cast sound
        "damage_0000.wav",   # Damage sound
        "heal_0000.wav",     # Heal sound
        "shield_0000.wav",   # Shield sound
    ]
    
    # Register all music files
    for file in music_files
        AudioManagerModule.load_sound(manager.audio_manager, file, true, 1.0, :music)
    end
    
    # Register all menu sound files
    for file in menu_files
        AudioManagerModule.load_sound(manager.audio_manager, file, false, 1.0, :menu)
    end
    
    # Register all SFX files
    for file in sfx_files
        AudioManagerModule.load_sound(manager.audio_manager, file, false, 1.0, :sfx)
    end
    
    @debug "Registered $(length(music_files) + length(menu_files) + length(sfx_files)) common sound files"
    
    return manager.audio_manager.loaded_sounds
end

function load_graphics_settings()
    graphicsSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "graphics_settings.txt")
    if !isfile(graphicsSettingsPath)
        touch(graphicsSettingsPath)
    end
    config = Dict{String, Any}()
    open(graphicsSettingsPath, "r") do file
        for line in eachline(file)
            if contains(line, "=")
                key, value = split(line, "=")
                config[key] = value
            end
        end
    end
    
    # Get current window dimensions
    width = parse(Int, get(config, "Width", "1280"))
    height = parse(Int, get(config, "Height", "720"))
    @debug "Loaded width: $width"
    @debug "Loaded height: $height"
    @debug "path: $graphicsSettingsPath"
    
    # Load boolean settings
    fullscreen = parse(Int, get(config, "Fullscreen", "0")) == 1
    vsync = parse(Int, get(config, "Vsync", "0")) == 1
    resizable = false#parse(Int, get(config, "IsResizable", "0")) == 1
    borderless = false  # Not directly in config, default to false
    return (width=width, height=height, fullscreen=fullscreen, vsync=vsync, resizable=resizable, borderless=borderless)
end


function track_run_end(; run_won::Union{Nothing,Bool} = nothing, outcome::Union{Nothing,String} = nothing)
    data_manager = get_data_manager()
    persistent_state = try
        data_manager.persistent_state_manager
    catch
        nothing
    end
    user_data = get_user_data()
    analytics_data = get_analytics_data()

    floors_climbed = try
        ps = persistent_state
        ps === nothing ? 0 : max(0, getproperty(ps, :currentLevel) - 1)
    catch
        0
    end
    max_hp = try
        user_data === nothing ? 40 : convert(Int, getproperty(user_data, :maxHealth))
    catch
        40
    end

    AnalyticsModule.track_run_end(
        analytics_data, floors_climbed, max_hp;
        run_won = run_won,
        outcome = outcome,
    )

    try
        AchievementTrackerModule.on_run_end!(; run_won = something(run_won, false))
    catch e
        @error "Failed to merge run-end meta progress: $e"
    end
end

# Export public functions
export supported_languages, 
       get_current_language, set_current_language,
       get_localization_data, get_localized_string, 
       get_piece_data,
       get_enemy_data,
       get_encounter_data,
       get_random_event_data,
       get_treasure_data,
       get_potion_data,
       item_available_in_game,
       reload_all_data,
       get_version,
       get_release_notes,
       get_release_notes_paged,
       get_audio_volumes,
       set_audio_volumes,
       apply_audio_volumes,
       load_sound,
       play_sound,
       get_audio_manager,
       register_existing_sounds,
       register_common_sounds,
       track_run_end,
       get_meta_progress,
       get_asset_path,
       get_available_versions,
       SaveManagerModule
end # module
