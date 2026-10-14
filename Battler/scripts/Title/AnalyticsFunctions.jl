mutable struct AnalyticsSettings
    analyticsEnabled::Bool

    function AnalyticsSettings()
        this = new()
        settings = load_analytics_settings()
        this.analyticsEnabled = settings.analyticsEnabled
        return this
    end
end

# Load analytics settings from preference file
function load_analytics_settings()
    analyticsSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "analytics_settings.txt")
    if !isfile(analyticsSettingsPath)
        touch(analyticsSettingsPath)
    end
    config = Dict{String, Any}()
    open(analyticsSettingsPath, "r") do file
        for line in eachline(file)
            if contains(line, "=")
                key, value = split(line, "=")
                config[key] = value
            end
        end
    end
    
    # Default to false (disabled) if not set
    analyticsEnabled = parse(Int, get(config, "AnalyticsEnabled", "0")) == 1
    @debug "Loaded analytics enabled: $analyticsEnabled"
    @debug "path: $analyticsSettingsPath"
    
    return (analyticsEnabled=analyticsEnabled,)
end

# Apply and save analytics settings
function apply_analytics_settings(this::AnalyticsSettings; enabled::Union{Nothing, Bool}=nothing)
    if enabled !== nothing
        this.analyticsEnabled = enabled
        @debug "Analytics $(enabled ? "enabled" : "disabled")"
    end
    
    # Save settings to config file
    save_analytics_settings(this)
    
    # Update the global analytics instance
    try
        globals = JulGame.UserGlobals["Module"]
        analytics_data = globals.get_analytics_data()
        analytics_data.is_analytics_enabled = this.analyticsEnabled
        @debug "Updated global analytics enabled state to: $(this.analyticsEnabled)"
    catch e
        @error "Error updating global analytics state: $e"
    end
end

# Save analytics settings to config file
function save_analytics_settings(this::AnalyticsSettings)
    analyticsSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "analytics_settings.txt")
    settings = Dict{String, Any}(
        "AnalyticsEnabled" => this.analyticsEnabled ? "1" : "0"
    )
    save_settings_to_config(analyticsSettingsPath, settings)
end

