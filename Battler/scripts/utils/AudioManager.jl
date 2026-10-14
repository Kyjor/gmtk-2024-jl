module AudioManagerModule
    using JulGame
    using ..Globals
    using ..SfxChannelsModule: SFX_CHANNEL_UI, SFX_CHANNEL_GAMEPLAY, SFX_CHANNEL_TYPING,
                                SFX_CHANNEL_MISC, DRUMS_CHANNEL, SFX_CHANNEL_COMBO, AMBIENCE_CHANNEL,
                                DEFAULT_SFX_CHANNEL, MIXER_CHANNEL_COUNT, SFX_POOL_FIRST, SFX_POOL_LAST, SFX_POOL_TAG
    export AudioManager, SFX_CHANNEL_UI, SFX_CHANNEL_GAMEPLAY, SFX_CHANNEL_TYPING,
           SFX_CHANNEL_MISC, DRUMS_CHANNEL, SFX_CHANNEL_COMBO, AMBIENCE_CHANNEL,
           DEFAULT_SFX_CHANNEL
    
    global audio_volume_applied = false
    mutable struct LoadedSound
        path::String
        is_music::Bool
        base_volume::Float64
        sound_type::Symbol # :music, :sfx
        sound::Union{Ptr{Nothing}, Any} # Reference to the actual sound object
        
        LoadedSound(path::String, is_music::Bool, base_volume::Float64, sound_type::Symbol, sound::Any) = 
            new(path, is_music, base_volume, sound_type, sound)
    end
    
    mutable struct AudioManager
        loaded_sounds::Dict{String, LoadedSound}
        master_volume::Int
        music_volume::Int
        sfx_volume::Int
        
        function AudioManager()
            this = new()
            this.loaded_sounds = Dict{String, LoadedSound}()
            this.master_volume = 50
            this.music_volume = 50
            this.sfx_volume = 50
            return this
        end
    end
    
    """
        load_sound(manager::AudioManager, path::String, is_music::Bool, base_volume::Float64, sound_type::Symbol = :sfx)
    
    Loads a sound file and stores it in the audio manager.
    - `path`: Path to the sound file relative to the assets/sounds directory
    - `is_music`: Whether this is a music track (true) or a sound effect (false)
    - `base_volume`: The base volume for this sound (0.0-1.0)
    - `sound_type`: The type of sound - :music, :sfx
    
    Returns the loaded sound object or nothing if loading failed.
    """
    function load_sound(manager::AudioManager, path::String, is_music::Bool, base_volume::Float64 = 1.0, sound_type::Symbol = :sfx)
        # Check if already loaded
        if haskey(manager.loaded_sounds, path)
            @debug "Sound already loaded: $path"
            return manager.loaded_sounds[path]
        end
        
        try
            # We're not actually loading the sound here, just creating a placeholder
            # The actual loading is done by JulGame when a SoundSource component is created
            sound = nothing
            @debug "Loading sound: $path ($(sound_type)) as $(is_music)"
            # Create the LoadedSound object
            loaded_sound = LoadedSound(path, is_music, base_volume, sound_type, sound)
            
            # Store in the dictionary
            manager.loaded_sounds[path] = loaded_sound
            
            @debug "Registered sound: $path ($(sound_type))"
            return loaded_sound
        catch e
            @error "Failed to load sound $path: $e"
            return nothing
        end
    end
    
    """
        set_volumes(manager::AudioManager, master::Float64, music::Float64, sfx::Float64)
    
    Sets all volume levels for the audio manager.
    All values should be in the range 0.0-1.0.
    """
    function set_volumes(manager::AudioManager, master::Int, music::Int, sfx::Int)
        manager.master_volume = clamp(master, 0, 100)
        manager.music_volume = clamp(music, 0, 100)
        manager.sfx_volume = clamp(sfx, 0, 100)
        
        # Apply volumes to any active sound sources
        @debug "Applying volumes to active sources on set_volumes"
        apply_volumes_to_active_sources(manager)

        # save audio settings to config file
        Globals.save_audio_settings(manager)
        
        return (manager.master_volume, manager.music_volume, manager.sfx_volume)
    end
    
    """
        get_effective_volume(manager::AudioManager, sound_path::String)
    
    Calculates the effective volume for a sound based on its type and base volume.
    Master volume scales the category volumes (master * category = effective).
    Returns a value in the range 0-128 for SDL volume.
    """
    function get_effective_volume(manager::AudioManager, sound_path::String)
        if !haskey(manager.loaded_sounds, sound_path)
            @debug "Sound not found: $sound_path"
            # Default behavior for sounds not registered with the manager
            return Int32(128)
        end
        
        sound = manager.loaded_sounds[sound_path]
        base_volume = sound.base_volume
        @debug "Base volume: $base_volume"
        
        # Get category volume (0-100)
        if sound.sound_type == :music || occursin("music-patientbraverydrums-0000", sound_path)
            @debug "Music volume for $sound_path is $(manager.music_volume)"
            @debug "Music volume: $(manager.music_volume)"
            category = manager.music_volume
        else # :sfx
            @debug "SFX volume: $manager.sfx_volume"
            category = manager.sfx_volume
        end

        # Master volume scaling: master (0-100) * category (0-100) / 100 = effective category (0-100)
        effective_category = (manager.master_volume * category) / 100.0
        
        # Scale: base (0.0-1.0) * effective_category (0-100%) -> 0.0-1.0, then to SDL 0-128
        scaled = base_volume * (effective_category / 100) * 128.0
        @debug "Master: $(manager.master_volume), Category: $category, Effective: $effective_category, Scaled: $scaled"
        final_volume = Int32(round(clamp(scaled, 0.0, 128.0)))
        @debug "Final volume (SDL 0-128): $final_volume"
        return final_volume
    end
    
    """
        apply_volumes_to_active_sources(manager::AudioManager)
    
    Applies the current volume settings to all active sound sources in the game.
    """
    function apply_volumes_to_active_sources(manager::AudioManager)
        if !@isdefined(MAIN) || !isdefined(MAIN, :scene)
            @warn "No active scene to scan for sound sources"
            return
        end
        @debug "Applying volumes to active sources"
        #blacklist = ["DrumsLayer"]
        # Find all entities with sound sources
        for entity in MAIN.scene.entities
            if entity.name == "CampfireAmbience"
                continue
            end
            if entity.soundSource !== nothing && entity.soundSource != C_NULL #&& !in(entity.name, blacklist)
                sound_source = entity.soundSource
                    
                # For sounds registered with the manager, use their settings
                if haskey(manager.loaded_sounds, sound_source.path)
                    if entity.name == "DrumsLayer"
                        @debug "DrumsLayer registered: $(entity.name)"
                    end
                    # Sound is registered with AudioManager
                    sound = manager.loaded_sounds[sound_source.path]
                            
                    # Calculate effective volume based on sound type and base volume
                    sdl_volume = get_effective_volume(manager, sound_source.path)
                    @debug "Setting volume for sound: $(sound_source.path) to $sdl_volume 0"
                        
                    if MAIN.scene.name != "event" && MAIN.scene.name != "rest"
                        # Don't set volume if channel is -1 (auto-assign) - Mix_Volume(-1, volume) sets ALL channels which would affect drums
                        if sound_source.channel != -1 || sound_source.isMusic
                            @debug "apply_volumes_to_active_sources: setting volume for sound: $(sound_source.path) to $sdl_volume for channel $(sound_source.channel)"
                            JulGame.Component.set_volume(sound_source, round(Int, clamp(sdl_volume, 0, 128)), sound_source.channel)
                        end
                    end
                else
                    # Sound is not registered - use fallback based on entity name
                    if entity.name == "DrumsLayer"
                        @debug "DrumsLayer not registered: $(entity.name)"
                        continue
                    end
                    sound_type = if sound_source.isMusic || entity.name == "DrumsLayer"
                        :music
                    else
                        :sfx
                    end
                        
                    # Calculate volume based on sound type (unregistered sounds use base=1.0)
                    category = if sound_type == :music
                        manager.music_volume
                    else
                        manager.sfx_volume
                    end

                    # Apply master volume scaling to unregistered sounds too
                    effective_category = (manager.master_volume * category) / 100.0
                    
                    # Scale effective category percent to SDL 0-128
                    sdl_volume = round(Int, clamp((effective_category / 100) * 128.0, 0.0, 128.0))
                    channel = if !sound_source.isMusic
                        sound_source.channel
                    else
                        -1
                    end
                    @debug "Setting volume for sound: $(sound_source.path) to $sdl_volume (master: $(manager.master_volume), category: $category, effective: $effective_category)"
                    # Don't set volume if channel is -1 (auto-assign) - Mix_Volume(-1, volume) sets ALL channels which would affect drums
                    if channel != -1 || sound_source.isMusic
                        @debug "apply_volumes_to_active_sources1: setting volume for sound: $(sound_source.path) to $sdl_volume for channel $(channel)"
                        JulGame.Component.set_volume(sound_source, clamp(sdl_volume, 0, 128), channel)
                    end
                end
                # Note: We no longer set SDL master volume since we handle scaling ourselves
            end
        end

        # Event/rest layered music (drums + melody) is managed by DJ, not scene SoundSources.
        try
            @debug "Applying DJ volume settings on apply_volumes_to_active_sources"
            Globals.apply_dj_volume_settings!()
        catch e
            @debug "apply_dj_volume_settings: $e"
        end
    end
    
    const SFX_POOL_READY = Ref(false)

    # Must run after Mix_OpenAudio (which resets the channel count), so it is done lazily on first play.
    function ensure_sfx_pool!()::Bool
        SFX_POOL_READY[] && return true
        if JulGame.SDL2.Mix_AllocateChannels(Int32(-1)) < MIXER_CHANNEL_COUNT
            JulGame.SDL2.Mix_AllocateChannels(Int32(MIXER_CHANNEL_COUNT))
        end
        SFX_POOL_READY[] = JulGame.SDL2.Mix_GroupChannels(Int32(SFX_POOL_FIRST), Int32(SFX_POOL_LAST), Int32(SFX_POOL_TAG)) > 0
        return SFX_POOL_READY[]
    end

    """Maps SFX_CHANNEL_GAMEPLAY to a free (else the oldest) pooled channel; other channels pass through."""
    function resolve_sfx_channel(channel::Int, is_music::Bool)::Int
        (is_music || channel != SFX_CHANNEL_GAMEPLAY) && return channel
        try
            ensure_sfx_pool!() || return channel
            ch = JulGame.SDL2.Mix_GroupAvailable(Int32(SFX_POOL_TAG))
            if ch == -1
                ch = JulGame.SDL2.Mix_GroupOldest(Int32(SFX_POOL_TAG))
            end
            return ch == -1 ? channel : Int(ch)
        catch e
            @debug "resolve_sfx_channel: $e"
            return channel
        end
    end

    """
        play_sound(manager::AudioManager, path::String, loops::Int = 0, channel::Int = DEFAULT_SFX_CHANNEL)
    
    Plays a sound that has been registered with the audio manager.
    - `path`: Path to the sound file
    - `loops`: Number of times to loop (-1 for infinite)
    - `channel`: SDL audio channel (see SfxChannelsModule; never -1 for SFX).
      SFX_CHANNEL_GAMEPLAY is redirected to a pooled channel so one-shots overlap.
    
    Returns true if successful, false otherwise.
    """
    function play_sound(manager::AudioManager, path::String, loops::Int = 0, channel::Int = DEFAULT_SFX_CHANNEL)
        if !haskey(manager.loaded_sounds, path)
            @warn "Sound not found: $path"
            return false
        end
        
        entity = nothing
        try
            sound = manager.loaded_sounds[path]
            channel = resolve_sfx_channel(channel, sound.is_music)
            
            # Create a temporary sound source to play this sound
            entity = JulGame.EntityModule.Entity("TempSoundPlayer_$(path)")
            sound_source = JulGame.add_sound_source(entity, JulGame.SoundSourceModule.SoundSource(channel, sound.is_music, path, true, get_effective_volume(manager, path)))
            @debug "Created temporary sound source: $(sound_source.path)"
            # Add entity to scene (this will actually load the sound)
            entity = JulGame.create_entity(entity)
            @debug "Created temporary entity: $(entity.name)"
            # Play the sound
            JulGame.Component.play(sound_source, loops)
            @debug "Played sound: $(sound_source.path)"
            return true
        catch e
            @error "Failed to play sound $path: $e"
            return false
        finally
            # Clean up the temporary entity
            # if entity !== nothing
            #     JulGame.destroy_entity(entity)
            # end
           #@debug "Destroyed temporary entity: $(entity.name)"
        end
    end
    
    """
        play_audio_oneshot(manager::AudioManager, path::String, is_music::Bool, base_volume::Float64 = 1.0, loops::Int = 0, channel::Int = DEFAULT_SFX_CHANNEL)
    
    Convenience function to play a sound with automatic registration and caching.
    - `path`: Path to the sound file relative to the assets/sounds directory
    - `is_music`: Whether this is a music track (true) or a sound effect (false)
    - `base_volume`: The base volume for this sound (0.0-1.0)
    - `loops`: Number of times to loop (-1 for infinite)
    - `channel`: SDL audio channel (see SfxChannelsModule; never -1 for SFX)
    
    Returns true if successful, false otherwise.
    """
    function play_audio_oneshot(manager::AudioManager, path::String, is_music::Bool, base_volume::Float64 = 1.0, loops::Int = 0, channel::Int = DEFAULT_SFX_CHANNEL)
        # Determine sound type based on is_music parameter
        sound_type = is_music ? :music : :sfx
        
        # Register the sound if it's not already loaded
        if !haskey(manager.loaded_sounds, path)
            @debug "Auto-registering sound: $path ($(sound_type))"
            load_sound(manager, path, is_music, base_volume, sound_type)
        end
        
        # Play the sound using the existing play_sound function
        return play_sound(manager, path, loops, channel)
    end
    
    """
        register_existing_sounds(manager::AudioManager)
        
    Scans the current scene for entities with sound sources and registers them with the audio manager.
    This allows existing sounds to benefit from the AudioManager's volume control.
    """
    function register_existing_sounds(manager::AudioManager)
        if !@isdefined(MAIN) || !isdefined(MAIN, :scene) # Will throw an error if not defined (yes it does that)
            @warn "No active scene to scan for sound sources"
            return
        end

        registered_count = 0
        try
            # Find all entities with sound sources
            for entity in MAIN.scene.entities
                @debug "Checking entity: $(entity.name)"
                if entity.soundSource !== nothing && entity.soundSource != C_NULL
                    sound_source = entity.soundSource
                    path = sound_source.path
                    
                    # Skip if already registered
                    if haskey(manager.loaded_sounds, path)
                        @debug "Sound already registered: $path"
                        continue
                    end
                    
                    # Determine sound type based on entity name or path
                    # Calculate base volume (convert from SDL volume range 0-128 to 0.0-1.0)
                    base_volume = 1.0
                    if sound_source.volume > 0
                        base_volume = sound_source.volume / 128.0
                    end
                    
                    # Determine sound type based on entity name or content
                    sound_type = if sound_source.isMusic || occursin("Music", entity.name)
                        :music
                    else
                        :sfx
                    end
                    
                    # Register the sound
                    @debug "Registering sound: $path ($(sound_type))"
                    @debug "Registering sound: $path ($(sound_type))"
                    load_sound(manager, path, sound_source.isMusic || occursin("music-patientbraverydrums", path), base_volume, sound_type)
                    registered_count += 1
                else
                    @debug "Entity $(entity.name) does not have a sound source"
                end
            end
            
            @debug "Registered $registered_count existing sound sources with AudioManager"
            
            # Apply volume settings to all sources
            @debug "Applying volumes to active sources on register_existing_sounds"
            apply_volumes_to_active_sources(manager)
            
            return registered_count
        catch e
            @error "Error registering existing sounds: $e"
            return 0
        end
    end
end 