module Battler 
    using JulGame
    using JSON3
    using SteamWorks
    
    include(joinpath(@__DIR__, "Scripts.jl"))
    using .Scripts
    using .Scripts.Globals

    include(joinpath(@__DIR__, "AssetCacheCompression.jl"))
    using .AssetCacheCompression

    const EXE_BUILD = get(ENV, "PackageCompiling", "false") == "true"
    # Mac release sysimage: skip GameDataManager/XLSX (Ncurses/ICU JLLs break Steam).
    # Mac local/dev still loads live data.
    if !(Sys.isapple() && EXE_BUILD)
        include(joinpath(@__DIR__, "SynchronizeExcel.jl"))
    end
    include(joinpath(@__DIR__, "LiveGameData.jl"))

    function get_folders_after_base_folder(path::String, base_folder::String)
        AssetCacheCompression.folders_after_base_folder(path, base_folder)
    end

    function get_all_files(folder::String, extensions, folderToPrefix)
        bytes_files = Dict{String, Vector{UInt8}}()

        for (root, _, files) in walkdir(folder)
            for file in files
                ext = lowercase(last(split(file, '.')))
                if ext in extensions
                    file_path = joinpath(root, file)
                    prefix = get_folders_after_base_folder(root, folderToPrefix)
                    bytes_files["$(prefix)$file"] = read(file_path)
                end
            end
        end
    
        return bytes_files
    end

    function log_asset_cache_load(label::String, file_count::Int, total_bytes::Int)
        if total_bytes > 0
            println("  → $label: $file_count files, $(round(total_bytes / 1024^2; digits=1)) MiB")
        else
            println("  → $label: $file_count files")
        end
    end
    
    # Initialize an empty dictionary
    json_dict = Dict{String, Any}()
    project_root = normpath(joinpath(@__DIR__, ".."))
    const PRECOMPILING = ccall(:jl_generating_output, Cint, ()) == 1
    const SHOULD_BAKE_ASSETS = PRECOMPILING && EXE_BUILD
    # Only bake assets into the module during sysimage creation for exe builds.
    # Everything else keeps caches empty so `run()` loads from disk/runtime.
    defer_asset_load = !SHOULD_BAKE_ASSETS
    scenes_dir = joinpath(project_root, "scenes")
    @time "asset load: scene json" begin
        for file in readdir(scenes_dir)
            full_path = joinpath(scenes_dir, file)
            if endswith(file, ".json")
                json_dict[file] = JSON3.read(read(full_path, String))
            end
        end
    end
    log_asset_cache_load("scene json", length(json_dict), 0)

    # Sysimage builds bake the JS-optimized release-bundle bytes into the module
    # globals under the same cache keys as the raw assets ("images" etc. stays a
    # path component inside release-bundle/assets/, so key generation is identical).
    asset_load_root = if SHOULD_BAKE_ASSETS
        bundle_assets = joinpath(asset_bundle_root(project_root), "assets")
        isdir(bundle_assets) ||
            error("release-bundle missing at $bundle_assets — run `npm run prepare:release-bundle` in Battler/ first")
        bundle_assets
    else
        joinpath(project_root, "assets")
    end

    function load_assets_from_disk(assets_root::String)
        images = get_all_files(joinpath(assets_root, "images"), Set(["png", "jpg", "jpeg", "bmp", "gif", "tiff"]), "images")
        fonts = get_all_files(joinpath(assets_root, "fonts"), Set(["ttf", "otf", "woff", "woff2"]), "fonts")
        sounds = get_all_files(joinpath(assets_root, "sounds"), Set(["wav", "mp3", "ogg", "flac"]), "sounds")
        return images, fonts, sounds
    end

    if defer_asset_load
        cached_images = Dict{String, Vector{UInt8}}()
        cached_fonts = Dict{String, Vector{UInt8}}()
        cached_sounds = Dict{String, Vector{UInt8}}()
    else
        @time "asset load: assets ($asset_load_root)" cached_images, cached_fonts, cached_sounds = load_assets_from_disk(asset_load_root)
        log_asset_cache_load("images", length(cached_images), sum(length(v) for v in values(cached_images); init=0))
        log_asset_cache_load("fonts", length(cached_fonts), sum(length(v) for v in values(cached_fonts); init=0))
        log_asset_cache_load("sounds", length(cached_sounds), sum(length(v) for v in values(cached_sounds); init=0))
        if !SHOULD_BAKE_ASSETS
            @time "asset load: asset registry" Globals.AssetManager.initialize_asset_registry(cached_images, cached_fonts, cached_sounds)
        end
    end

    function resolve_runtime_asset_caches()
        if isempty(cached_images)
            # Nothing was baked at precompile time — load raw assets from disk now.
            @time "asset load: runtime assets" images, fonts, sounds = load_assets_from_disk(joinpath(project_root, "assets"))
            log_asset_cache_load("images", length(images), sum(length(v) for v in values(images); init=0))
            log_asset_cache_load("fonts", length(fonts), sum(length(v) for v in values(fonts); init=0))
            log_asset_cache_load("sounds", length(sounds), sum(length(v) for v in values(sounds); init=0))
            Globals.AssetManager.initialize_asset_registry(images, fonts, sounds)
            return images, fonts, sounds
        end
        Globals.AssetManager.initialize_asset_registry(cached_images, cached_fonts, cached_sounds)
        return cached_images, cached_fonts, cached_sounds
    end
    
    const ANALYTICS = Ref{Any}(nothing)

    function setup_macos_scripts_cwd_if_needed()
        Sys.isapple() || return
        # Built app/tests often start with cwd at repo root. JulGame then resolves sibling `../scripts`
        # (outside the Battler folder). Force cwd under Battler/src so script paths resolve correctly.
        scripts_here = normpath(joinpath(@__DIR__, "..", "scripts"))
        battler_src = normpath(joinpath(@__DIR__, "..", "src"))
        if isdir(scripts_here) && isdir(battler_src)
            cd(battler_src)
            return
        end
        repo_scripts = normpath(joinpath(pwd(), "Battler", "scripts"))
        repo_src = normpath(joinpath(pwd(), "Battler", "src"))
        if isdir(repo_scripts) && isdir(repo_src)
            cd(repo_src)
        end
    end

    function run()
        # @__DIR__ is baked at compile time; in a relocated exe it may not exist.
        isdir(@__DIR__) && cd(@__DIR__)
        setup_macos_scripts_cwd_if_needed()
        JulGame.ProjectModule = "Battler"
        JulGame.SCENE_CACHE = json_dict
        images, fonts, sounds = resolve_runtime_asset_caches()
        JulGame.IMAGE_CACHE = images
        JulGame.FONT_CACHE = fonts
        JulGame.AUDIO_CACHE = sounds

        if live_data_enabled()
            if isdefined(@__MODULE__, :sync_spreadsheet_to_json!)
                println("JULGAME_LIVE_DATA: syncing spreadsheet overrides…")
                try
                    sync_spreadsheet_to_json!()
                    reload_game_data_from_json!()
                catch e
                    @error "JULGAME_LIVE_DATA: sync/reload failed: $(e)"
                    Base.show_backtrace(stdout, catch_backtrace())
                end
            else
                println("JULGAME_LIVE_DATA: skipped (not compiled into this Mac release build)")
            end
        end

        ANALYTICS[] = Globals.get_analytics_data()
        analytics_data = ANALYTICS[]

        scene = SceneBuilderModule.Scene(get(ENV, "SCENE", "title_scene.json"))

        # Initialize Steamworks
        if get(ENV, "TEST_MODE", "false") == "false" && get(ENV, "SKIP", "false") == "false"
            try
                println("Initializing Steamworks from run()")
                @time "startup: steam init" steam = Globals.get_steam_data()
                analytics_data.user_id_hashed = steam.steam_id
                @time "startup: track_startup" Globals.AnalyticsModule.track_startup(analytics_data)
            catch e
                @error "Error initializing Steamworks: $(e)"
            end
        else
            println("Skipping Steamworks initialization from run()")
        end
        JulGame.UserGlobals["Module"] = Globals

    
        # Log file path
        log_file_path = joinpath(pwd(), "error_log.txt")
        window_config = Dict(
            "Width" => "1280",
            "Zoom" => "1.0",
            "Height" => "720",
            "FrameRate" => "60",
            "Vsync" => "1",
            "Fullscreen" => "0"
        )

        # Load graphics settings with proper error handling
        globals = JulGame.UserGlobals["Module"]
        graphicsSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "audio_settings.txt")
        settings = try
            @time "startup: graphics settings" globals.load_graphics_settings()
        catch e
            @warn "Failed to load graphics settings: $e. Using defaults."
            (width=1280, height=720, fullscreen=false, vsync=false, resizable=false, borderless=false)
        end
        window_config["Width"] = string(settings.width)
        window_config["Height"] = string(settings.height)
        window_config["Fullscreen"] = settings.fullscreen ? "1" : "0"
        window_config["IsResizable"] = "0"
        window_config["Borderless"] = settings.borderless ? "1" : "0"
        window_config["Zoom"] = "1.0"
        window_config["FrameRate"] = "60"
        window_config["Vsync"] = settings.vsync ? "1" : "0"

        # Helper function to log errors
        function log_error(e)
            open(log_file_path, "a") do file
                println(file, "ERROR:")
                println(file, e)
                Base.show_backtrace(file, catch_backtrace())
                
                println(file, "\n---\n")
            end
            Base.show_backtrace(stdout, catch_backtrace())
            try
                Globals.AnalyticsModule.track_crash(analytics_data, string(e))
            catch e
                @error "Error tracking crash: $(e)"
            end
        end
    
        try
            SceneBuilderModule.load_and_prepare_scene(scene; config=window_config, windowName="Necro-Matcher", preloadAllScenes=false)
        catch e
            @error first(string(e), min(length(string(e)), 500))
            log_error(first(string(e), min(length(string(e)), 500)))
            return Cint(-1)
        end
    
        @debug("Game ran successfully")
        return Cint(0)
    end

    # Include after all module definitions so precompile() statements can resolve
    # symbols like log_asset_cache_load that live in this module.
    if get(ENV, "SKIP_PRECOMPILE", "false") == "false" && !JulGame.IS_EDITOR
        additional_precompile_path = joinpath(@__DIR__, "additional_precompile.jl")
        isfile(additional_precompile_path) && include(additional_precompile_path)
    end
    if !JulGame.IS_EDITOR && get(ENV, "ALWAYS_PRECOMPILE", "true") == "true"
        include(joinpath(@__DIR__, "always_precompile.jl")) 
        include(joinpath(@__DIR__, "always_precompile_manual.jl"))
    end

    julia_main() = run()
end

# # PROFILE=1 julia Run.jl
# get(ENV, "PROFILE", "0") == "0" && exit(0)
#     using ProfilePerfetto
#     @perfetto_open Battler.run() max_rounds=1