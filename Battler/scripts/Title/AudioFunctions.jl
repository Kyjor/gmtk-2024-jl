 mutable struct AudioSettings
    masterVolume::Int
    musicVolume::Int
    sfxVolume::Int

    function AudioSettings()
        this = new()
        settings = load_audio_settings()
        this.masterVolume = settings.masterVolume
        this.musicVolume = settings.musicVolume
        this.sfxVolume = settings.sfxVolume
        return this
    end
 end

# Apply audio settings to the current game
function apply_audio_settings(this::AudioSettings)
    # Apply settings to global audio system
    try
        # First, register any existing sounds that might not be managed by AudioManager
        globals = JulGame.UserGlobals["Module"]
        globals.register_existing_sounds()
        
        globals.set_audio_volumes(
            round(Int, clamp(this.masterVolume, 0, 100)),
            round(Int, clamp(this.musicVolume, 0, 100)), 
            round(Int, clamp(this.sfxVolume, 0, 100)), 
        )
        
        @debug("Applied audio settings: Master=$(this.masterVolume)%, Music=$(this.musicVolume)%, SFX=$(this.sfxVolume)%")
    catch e
        @error "Error applying audio settings: $e"
    end
end

# Load audio settings from the data manager
function load_audio_settings()
    try
    globals = JulGame.UserGlobals["Module"]
        data_manager = globals.get_data_manager()
        return (masterVolume=data_manager.audio_manager.master_volume, musicVolume=data_manager.audio_manager.music_volume, sfxVolume=data_manager.audio_manager.sfx_volume)
    catch e
        @error "Error loading audio settings: $e"
        return (masterVolume=100, musicVolume=100, sfxVolume=100)
    end
end
