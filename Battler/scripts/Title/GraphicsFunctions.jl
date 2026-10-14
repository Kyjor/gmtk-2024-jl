mutable struct GraphicsSettings
    width::Int
    height::Int
    fullscreen::Bool
    vsync::Bool
    resizable::Bool
    borderless::Bool
    
    function GraphicsSettings()
        this = new()
        settings = load_graphics_settings()
        this.width = settings.width
        this.height = settings.height
        this.fullscreen = settings.fullscreen
        this.vsync = settings.vsync
        this.resizable = settings.resizable
        this.borderless = settings.borderless
        return this
    end
end

# Always union these into SDL-reported modes so common presets stay in the dropdown.
const _DEFAULT_RESOLUTION_DIMS = Tuple{Int, Int}[
    (1280, 720),
    (1920, 1080),
    (2560, 1440),
    (3840, 2160),
]

function _fallback_available_resolutions()::Vector{String}
    opts = String[]
    for (w, h) in _DEFAULT_RESOLUTION_DIMS
        push!(opts, "$(w)x$(h)")
    end
    for (w, h) in _DEFAULT_RESOLUTION_DIMS
        push!(opts, "$(w)x$(h) FS")
    end
    return opts
end

"""
    get_available_resolutions()::Vector{String}

Builds resolution dropdown options from SDL display modes for *all* displays.
Each unique mode resolution is returned as `\"WxH\"` and a fullscreen variant `\"WxH FS\"`.
Standard presets (720p–4K) are always included even if SDL does not list them.
"""
function get_available_resolutions()::Vector{String}
    try
        #TODO: Remove this once we have a way to get the available resolutions from SDL
        return _fallback_available_resolutions()
        #TODO: End TOR

        displays = JulGame.WindowManagerModule.get_available_displays()
        if isempty(displays)
            return _fallback_available_resolutions()
        end

        # Unique by width/height across all displays; SDL refresh rate varies by mode.
        unique_dims = Dict{Tuple{Int, Int}, Bool}()

        for (display_index, display_name, current_mode) in displays
            @debug "SDL display $(display_index) '$(display_name)' current: $(Int(current_mode.w))x$(Int(current_mode.h)) @ $(current_mode.refresh_rate)Hz"

            modes = JulGame.WindowManagerModule.get_display_modes(display_index)
            for (idx, m) in enumerate(modes)
                @debug "SDL display $(display_index) mode $(idx): $(Int(m.w))x$(Int(m.h)) @ $(m.refresh_rate)Hz"

                w = Int(m.w)
                h = Int(m.h)
                if w > 0 && h > 0
                    unique_dims[(w, h)] = true
                end
            end
        end

        for (w, h) in _DEFAULT_RESOLUTION_DIMS
            unique_dims[(w, h)] = true
        end

        dims = collect(keys(unique_dims))
        sort!(dims; by = t -> t[1] * t[2])  # area-sorted for nicer UX

        # Filter to only 16:9 aspect ratio (width/height ≈ 1.777)
        dims = filter(d -> abs(d[1] / d[2] - 16/9) < 0.01, dims)

        options = String[]
        for (w, h) in dims
            push!(options, "$(w)x$(h)")
        end
        for (w, h) in dims
            push!(options, "$(w)x$(h) FS")
        end

        return options
    catch e
        @warn "Failed to build available resolutions from SDL: $e"
        return _fallback_available_resolutions()
    end
end

#   # Refactored load_graphics_settings
function load_graphics_settings()
    globals = JulGame.UserGlobals["Module"]
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

# Apply graphics settings to the current window
function apply_graphics_settings(this::GraphicsSettings; resolution::Union{Nothing, String}=nothing, fullscreen::Union{Nothing, Bool}=nothing, vsync::Union{Nothing, Bool}=nothing, resizable::Union{Nothing, Bool}=nothing, borderless::Union{Nothing, Bool}=nothing)
    if resolution !== nothing
        w_str, h_str = split(String(resolution), "x")
        width = parse(Int, w_str)
        height = parse(Int, h_str)
        @debug "Resizing window to $width x $height"
        if resolution != "$(this.width)x$(this.height)"
            this.width = width
            this.height = height
            JulGame.WindowManagerModule.resize_window(width, height)
        end
    end
    if fullscreen !== nothing && fullscreen != this.fullscreen
        this.fullscreen = fullscreen
        JulGame.WindowManagerModule.set_fullscreen(fullscreen)
    end
    if vsync !== nothing && vsync != this.vsync
        this.vsync = vsync
        JulGame.WindowManagerModule.set_vsync(vsync)
    end
    if resizable !== nothing && resizable != this.resizable
        this.resizable = resizable
        JulGame.WindowManagerModule.set_resizable(resizable)
    end
    # if borderless !== nothing && borderless != this.borderless
    #     this.borderless = borderless
    JulGame.WindowManagerModule.set_borderless_fullscreen(false)
    # end
    
    # Save settings to config file
    save_graphics_settings(this)
end

# Refactored save_graphics_settings
function save_graphics_settings(this::GraphicsSettings)
    globals = JulGame.UserGlobals["Module"]
    graphicsSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "graphics_settings.txt")
    settings = Dict{String, Any}(
        "Width" => this.width,
        "Height" => this.height,
        "Fullscreen" => this.fullscreen ? "1" : "0",
        "Vsync" => this.vsync ? "1" : "0",
        "Borderless" => this.borderless ? "1" : "0"
    )
    save_settings_to_config(graphicsSettingsPath, settings)
end