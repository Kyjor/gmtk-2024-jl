module DJModule
    using JulGame
    using ..Scripts
    include("utils/Easings.jl")
    include("utils/SfxChannels.jl")
    using .SfxChannelsModule

    # Map scenes to their music themes (logical names, not raw filenames) - source of truth
    function get_scene_to_song_map()::Dict{String, String}
        return Dict(
            # Title themes
            "title_scene" => "sleeperbeginnings",

            # Map theme
            "map" => "patientbravery",
            "event" => "patientbravery",
            "rest" => "patientbravery",
            
            # Battle theme
            "battle" => "chivalrousbravery",
            "battle:enemy" => "chivalrousbravery",
            "battle:elite" => "chivalrousbravery",
            "battle:event" => "chivalrousbravery",
            "battle:boss" => "syntheticpresent",

            # Other scenes currently share the existing synthetic history track
            "shop" => "synthetichistory",
            "upgraded-shop" => "shop",
            "hamster-shop" => "shop",
        )
    end

    """Strip `.json` from a scene file name (not from `battle.json:boss` composites)."""
    function normalize_scene_name(scene_name::String)::String
        return replace(scene_name, ".json" => "")
    end

    function _current_battle_category()::Union{String, Nothing}
        try
            globals = JulGame.UserGlobals["Module"]
            data_manager = globals.get_data_manager()
            psm = data_manager === nothing ? nothing : data_manager.persistent_state_manager
            if psm === nothing
                return nothing
            end
            ev = psm.currentEvent
            if ev === nothing
                return nothing
            end
            ev_type = ev isa NamedTuple ? ev.type : getproperty(ev, :type)
            if ev_type != "Battle"
                return nothing
            end
            cat = ev isa NamedTuple ? ev.category : getproperty(ev, :category)
            cat === nothing && return nothing
            s = lowercase(strip(string(cat)))
            return isempty(s) ? nothing : s
        catch
            return nothing
        end
    end

    """
    Map key used for music lookup — matches transition targets like `battle.json:boss`
    and plain scene names like `battle` (uses `currentEvent.category` when available).
    """
    function resolve_music_scene_key(scene_name::String)::String
        if occursin(":", scene_name)
            parts = split(scene_name, ":", limit=2)
            base = normalize_scene_name(parts[1])
            return "$(base):$(parts[2])"
        end
        base = normalize_scene_name(scene_name)
        if base == "battle"
            cat = _current_battle_category()
            if cat !== nothing
                composite = "battle:$(cat)"
                if haskey(get_scene_to_song_map(), composite)
                    return composite
                end
            end
        end
        return base
    end

    function theme_for_scene(scene_name::String)::Union{String, Nothing}
        return get(get_scene_to_song_map(), resolve_music_scene_key(scene_name), nothing)
    end

    const PERSISTENT_USER_ENTITY_ID = "44077ce5-c10f-4c9f-a9e2-e968d24ec1cc"

    @enum DrumsFadeState begin
        DrumsIdle
        DrumsFadingIn
        DrumsFadingOut
    end

    @enum CampfireFadeState begin
        CampfireIdle
        CampfireFadingIn
        CampfireFadingOut
    end

    const CAMPFIRE_ENTITY_NAME = "CampfireAmbience"

    """SDL music volume (0–128) from master × music sliders."""
    function music_effective_volume_sdl()::Int
        globals = JulGame.UserGlobals["Module"]
        audio_manager = globals.get_audio_manager()
        @debug "audio_manager.music_volume: $(audio_manager.music_volume)"
        @debug "audio_manager.master_volume: $(audio_manager.master_volume)"
        return Int(round(audio_manager.music_volume * audio_manager.master_volume / 100.0 * 128.0 / 100.0))
    end

    """SDL SFX volume (0–128) from master × sfx sliders."""
    function sfx_effective_volume_sdl()::Int
        globals = JulGame.UserGlobals["Module"]
        audio_manager = globals.get_audio_manager()
        return Int(round(audio_manager.sfx_volume * audio_manager.master_volume / 100.0 * 128.0 / 100.0))
    end

    function try_get_dj()::Union{Nothing, DJ}
        try
            if !@isdefined(MAIN) || !isdefined(MAIN, :scene)
                return nothing
            end
            entity = JulGame.SceneModule.get_entity_by_id(PERSISTENT_USER_ENTITY_ID)
            if entity === nothing
                return nothing
            end
            for script in entity.scripts
                if script isa DJ
                    return script
                end
            end
        catch e
            @debug "try_get_dj: $e"
        end
        return nothing
    end

    mutable struct DJ <: Script
        parent
        currentSong::String
        musicEntity::Union{Nothing, JulGame.Entity}
        sceneToSongMap::Dict{String, String}
        musicSource 
        
        # Drums layer system
        drumsEntity::Union{Nothing, JulGame.Entity}
        drumsSoundSource::Union{Nothing, Any}
        drumsFadeState::DrumsFadeState
        drumsFadeProgress::Float64
        drumsFadeDuration::Float64
        drumsCurrentVolume::Int
        drumsStartVolume::Int
        drumsTargetVolume::Int
        musicCurrentVolume::Int
        musicStartVolume::Int
        musicTargetVolume::Int
        originalMusicVolume::Int

        campfireEntity::Union{Nothing, JulGame.Entity}
        campfireSoundSource::Union{Nothing, Any}
        campfireFadeState::CampfireFadeState
        campfireFadeProgress::Float64
        campfireFadeDuration::Float64
        campfireCurrentVolume::Int
        campfireStartVolume::Int
        campfireTargetVolume::Int

        function DJ()
            this = new()
            this.currentSong = ""
            this.musicEntity = nothing
            this.sceneToSongMap = get_scene_to_song_map()
            this.drumsEntity = nothing
            this.drumsSoundSource = nothing
            this.drumsFadeState = DrumsIdle
            this.drumsFadeProgress = 0.0
            this.drumsFadeDuration = 1.0
            this.drumsCurrentVolume = 0
            this.drumsStartVolume = 0
            this.drumsTargetVolume = 0
            this.musicCurrentVolume = 128
            this.musicStartVolume = 128
            this.musicTargetVolume = 128
            this.originalMusicVolume = 128
            this.campfireEntity = nothing
            this.campfireSoundSource = nothing
            this.campfireFadeState = CampfireIdle
            this.campfireFadeProgress = 0.0
            this.campfireFadeDuration = 1.0
            this.campfireCurrentVolume = 0
            this.campfireStartVolume = 0
            this.campfireTargetVolume = 0
            return this
        end
    end

    function JulGame.initialize(this::DJ)
        try
            @debug "updating music for scene: $(MAIN.scene.name)"
            this.musicSource = this.parent.soundSource
            change_music_for_scene(this, MAIN.scene.name)
        catch e
            @error "Failed to initialize DJ: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function JulGame.update(this::DJ, dt::Float64)
        if this.drumsFadeState != DrumsIdle
            update_drums_fade(this, dt)
        end
        if this.campfireFadeState != CampfireIdle
            update_campfire_fade(this, dt)
        end
    end
    
    function change_music_for_scene(this::DJ, scene_name::String)
        @debug "changing music for scene: $(scene_name), currentSong: $(this.currentSong)"
        normalized_scene_name = normalize_scene_name(scene_name)
        music_scene_key = resolve_music_scene_key(scene_name)
        sync_campfire_for_scene(this, normalized_scene_name)
        
        desired_theme = get(this.sceneToSongMap, music_scene_key, nothing)
        if desired_theme === nothing
            @debug "No music configured for scene: $music_scene_key"
            return
        end
        
        # Special handling for event/rest scenes when patientbravery is playing
        if (normalized_scene_name == "event" || normalized_scene_name == "rest") && this.currentSong == "patientbravery"
            @debug "Entering event/rest - fading to drums"
            # Ensure drums layer exists
            if this.drumsSoundSource === nothing
                start_drums_layer(this)
            end
            # Only start fade if not already fading
            # Make sure we're in the correct starting state (map state: drums 0, music full)
            if this.drumsFadeState == DrumsIdle
                # Reset to map state first to ensure we fade from the correct starting point
                effective_volume = music_effective_volume_sdl()
                JulGame.Component.set_volume(this.drumsSoundSource, round(Int, clamp(0, 0, 128)), this.drumsSoundSource.channel)
                JulGame.Component.set_volume(this.musicSource, round(Int, clamp(effective_volume, 0, 128)), this.musicSource.channel)
                this.drumsCurrentVolume = 0
                this.musicCurrentVolume = effective_volume
                this.originalMusicVolume = effective_volume
                fade_in_drums_layer(this)
            end
            return
        end
        
        # Special handling: returning to map from event/rest
        if normalized_scene_name == "map" && this.currentSong == "patientbravery" && 
           this.drumsSoundSource !== nothing && 
           (this.drumsFadeState != DrumsIdle || this.drumsCurrentVolume > 0)
            @debug "Returning to map - fading to music"
            fade_out_drums_layer(this)
            return
        end
        
        # If the desired theme is already playing, don't restart it
        if this.currentSong == desired_theme
            @debug "Theme $desired_theme already playing, not restarting"
            return
        end
        
        @debug "Changing music from '$(this.currentSong)' to '$desired_theme' for scene '$music_scene_key' ($(scene_name))"
        
        # Stop current music if any
        stop_current_music(this)
        
        # Stop drums layer if switching away from patientbravery
        if this.currentSong == "patientbravery"
            stop_drums_layer(this)
        end
        
        # Play the new theme
        play_music(this, desired_theme)
        
        # Track the logical theme name
        this.currentSong = desired_theme
    end
    
    function stop_current_music(this::DJ)
       JulGame.Component.stop_music(this.musicSource)
    end
    
    function play_music(this::DJ, theme_name::String)
        globals = JulGame.UserGlobals["Module"]
        audio_manager = globals.get_audio_manager()

        resolved_path = globals.get_asset_path("music", theme_name)
        this.musicSource.path = resolved_path

        try
            JulGame.Component.load_sound(this.musicSource, this.musicSource.path, true)
            JulGame.Component.play(this.musicSource, -1)
            
            @debug "Started playing theme '$theme_name'"
            
            # If this is the patientbravery theme, start the drums layer
            if theme_name == "patientbravery"
                start_drums_layer(this)
                # Don't set volumes here - let change_music_for_scene handle it
                # This prevents immediate volume changes during scene transitions
            else
                stop_drums_layer(this)
            end
        catch e
            @error "Error playing music: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end
    
    function start_drums_layer(this::DJ)
        @debug "Starting drums layer"
        # Clean up existing drums if any
        stop_drums_layer(this)
        
        globals = JulGame.UserGlobals["Module"]
        drums_path = globals.get_asset_path("music", "patientbraverydrums")
        
        try
            drums_entity = JulGame.EntityModule.Entity("DrumsLayer")
            drums_entity.ignoreInputEvents = true
            drums_entity.persistentBetweenScenes = true
            
            drums_sound_source = JulGame.add_sound_source(
                drums_entity,
                JulGame.SoundSourceModule.SoundSource(DRUMS_CHANNEL, false, drums_path, false, 0)
            )
            
            drums_entity = JulGame.create_entity(drums_entity)
            JulGame.Component.load_sound(drums_sound_source, drums_path, false)
            JulGame.Component.play(drums_sound_source, -1)
            JulGame.Component.set_volume(drums_sound_source, round(Int, clamp(0, 0, 128)), drums_sound_source.channel)
            
            this.drumsEntity = drums_entity
            this.drumsSoundSource = drums_sound_source
            this.drumsCurrentVolume = 0
            this.drumsFadeState = DrumsIdle
            

            @debug "originalMusicVolume: $(music_effective_volume_sdl())"
            this.originalMusicVolume = music_effective_volume_sdl()
            @debug "this.originalMusicVolume: $(this.originalMusicVolume)"
            this.musicCurrentVolume = this.originalMusicVolume
            
            @debug "Started drums layer"
        catch e
            @error "Error starting drums layer: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end
    
    function stop_drums_layer(this::DJ)
        if this.drumsSoundSource !== nothing
            try
                JulGame.SDL2.Mix_HaltChannel(DRUMS_CHANNEL)
            catch e
                @debug "Error halting drums channel: $e"
            end
        end
        
        if this.drumsEntity !== nothing
            try
                JulGame.destroy_entity(this.drumsEntity)
            catch e
                @debug "Error destroying drums entity: $e"
            end
        end
        
        JulGame.destroy_entity(this.drumsEntity)
        this.drumsEntity = nothing
        this.drumsSoundSource = nothing
        this.drumsFadeState = DrumsIdle
        this.drumsCurrentVolume = 0
    end
    
    function fade_in_drums_layer(this::DJ)
        if this.drumsSoundSource === nothing
            @warn "Cannot fade in drums layer: not initialized"
            return
        end
        
        effective_volume = music_effective_volume_sdl()
        
        # Use the tracked volumes as starting point (they should be set correctly before calling this)
        @debug "fading in drums layer"
        @debug "effective_volume: $(effective_volume)"
        @debug "this.drumsCurrentVolume: $(this.drumsCurrentVolume)"
        @debug "this.musicCurrentVolume: $(this.musicCurrentVolume)"
        this.drumsStartVolume = this.drumsCurrentVolume
        this.musicStartVolume = this.musicCurrentVolume
        this.drumsTargetVolume = effective_volume
        this.musicTargetVolume = 0
        
        this.drumsFadeState = DrumsFadingIn
        this.drumsFadeProgress = 0.0
        
        @debug "Starting drums fade in from drums=$(this.drumsStartVolume) music=$(this.musicStartVolume) to drums=$effective_volume music=0"
    end
    
    function fade_out_drums_layer(this::DJ)
        if this.drumsSoundSource === nothing
            @warn "Cannot fade out drums layer: not initialized"
            return
        end
        
        effective_volume = music_effective_volume_sdl()
        
        this.drumsStartVolume = this.drumsCurrentVolume
        this.musicStartVolume = this.musicCurrentVolume
        this.drumsTargetVolume = 0
        this.musicTargetVolume = effective_volume
        this.originalMusicVolume = effective_volume
        
        this.drumsFadeState = DrumsFadingOut
        this.drumsFadeProgress = 0.0
        
        @debug "Starting drums fade out"
    end
    
    function update_drums_fade(this::DJ, dt::Float64)
        this.drumsFadeProgress += dt / this.drumsFadeDuration
        @debug "drumsFadeProgress: $(this.drumsFadeProgress)"
        if this.drumsFadeProgress >= 1.0
            this.drumsFadeProgress = 1.0
            this.drumsCurrentVolume = this.drumsTargetVolume
            this.musicCurrentVolume = this.musicTargetVolume
            this.drumsFadeState = DrumsIdle
        else
            eased_progress = ease_in_out_cubic(clamp(this.drumsFadeProgress, 0.0, 1.0))
            @debug "eased_progress: $(eased_progress)"
            this.drumsCurrentVolume = Int(round(this.drumsStartVolume + (this.drumsTargetVolume - this.drumsStartVolume) * eased_progress))
            @debug "this.drumsCurrentVolume: $(this.drumsCurrentVolume)"
            this.musicCurrentVolume = Int(round(this.musicStartVolume + (this.musicTargetVolume - this.musicStartVolume) * eased_progress))
            @debug "this.musicCurrentVolume: $(this.musicCurrentVolume)"
        end
        
        try
            JulGame.Component.set_volume(this.drumsSoundSource, round(Int, clamp(this.drumsCurrentVolume, 0, 128)), this.drumsSoundSource.channel)
            JulGame.Component.set_volume(this.musicSource, round(Int, clamp(this.musicCurrentVolume, 0, 128)), this.musicSource.channel)
        catch e
            @error "Error setting volumes during fade: $e"
        end
    end

    function start_campfire_layer(this::DJ)
        stop_campfire_layer(this)

        globals = JulGame.UserGlobals["Module"]
        campfire_path = globals.get_asset_path("ambience", "campfire")

        try
            campfire_entity = JulGame.EntityModule.Entity(CAMPFIRE_ENTITY_NAME)
            campfire_entity.ignoreInputEvents = true
            campfire_entity.persistentBetweenScenes = true

            campfire_sound_source = JulGame.add_sound_source(
                campfire_entity,
                JulGame.SoundSourceModule.SoundSource(AMBIENCE_CHANNEL, false, campfire_path, false, 0)
            )

            campfire_entity = JulGame.create_entity(campfire_entity)
            JulGame.Component.load_sound(campfire_sound_source, campfire_path, false)
            JulGame.Component.play(campfire_sound_source, -1)
            JulGame.Component.set_volume(campfire_sound_source, 0, campfire_sound_source.channel)

            this.campfireEntity = campfire_entity
            this.campfireSoundSource = campfire_sound_source
            this.campfireCurrentVolume = 0
            this.campfireFadeState = CampfireIdle
        catch e
            @error "Error starting campfire layer: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function stop_campfire_layer(this::DJ)
        if this.campfireSoundSource !== nothing
            try
                JulGame.SDL2.Mix_HaltChannel(AMBIENCE_CHANNEL)
            catch e
                @debug "Error halting campfire channel: $e"
            end
        end

        if this.campfireEntity !== nothing
            try
                JulGame.destroy_entity(this.campfireEntity)
            catch e
                @debug "Error destroying campfire entity: $e"
            end
        end

        this.campfireEntity = nothing
        this.campfireSoundSource = nothing
        this.campfireFadeState = CampfireIdle
        this.campfireCurrentVolume = 0
    end

    function fade_in_campfire_layer(this::DJ)
        if this.campfireSoundSource === nothing
            start_campfire_layer(this)
        end
        if this.campfireSoundSource === nothing
            @warn "Cannot fade in campfire layer: not initialized"
            return
        end

        this.campfireStartVolume = this.campfireCurrentVolume
        this.campfireTargetVolume = sfx_effective_volume_sdl()
        this.campfireFadeState = CampfireFadingIn
        this.campfireFadeProgress = 0.0
    end

    function fade_out_campfire_layer(this::DJ)
        if this.campfireSoundSource === nothing
            return
        end

        this.campfireStartVolume = this.campfireCurrentVolume
        this.campfireTargetVolume = 0
        this.campfireFadeState = CampfireFadingOut
        this.campfireFadeProgress = 0.0
    end

    function update_campfire_fade(this::DJ, dt::Float64)
        this.campfireFadeProgress += dt / this.campfireFadeDuration
        if this.campfireFadeProgress >= 1.0
            this.campfireFadeProgress = 1.0
            this.campfireCurrentVolume = this.campfireTargetVolume
            this.campfireFadeState = CampfireIdle
        else
            eased_progress = ease_in_out_cubic(clamp(this.campfireFadeProgress, 0.0, 1.0))
            this.campfireCurrentVolume = Int(round(this.campfireStartVolume + (this.campfireTargetVolume - this.campfireStartVolume) * eased_progress))
        end

        try
            JulGame.Component.set_volume(this.campfireSoundSource, round(Int, clamp(this.campfireCurrentVolume, 0, 128)), this.campfireSoundSource.channel)
        catch e
            @error "Error setting campfire volume during fade: $e"
        end

        if this.campfireFadeState == CampfireIdle && this.campfireCurrentVolume <= 0
            stop_campfire_layer(this)
        end
    end

    function sync_campfire_for_scene(this::DJ, normalized_scene_name::String)
        if normalized_scene_name == "rest"
            if this.campfireSoundSource === nothing
                start_campfire_layer(this)
            end
            if this.campfireFadeState == CampfireFadingOut || this.campfireFadeState == CampfireIdle
                fade_in_campfire_layer(this)
            end
        elseif this.campfireSoundSource !== nothing && this.campfireFadeState != CampfireFadingOut
            fade_out_campfire_layer(this)
        end
    end

    function apply_campfire_volume_settings!(this::DJ)
        this.campfireSoundSource === nothing && return
        vol = sfx_effective_volume_sdl()
        scene = normalize_scene_name(MAIN.scene.name)

        if this.campfireFadeState == CampfireFadingIn
            this.campfireTargetVolume = vol
        elseif this.campfireFadeState == CampfireFadingOut
            this.campfireTargetVolume = 0
        elseif scene == "rest"
            this.campfireCurrentVolume = vol
            this.campfireTargetVolume = vol
        else
            this.campfireCurrentVolume = 0
            this.campfireTargetVolume = 0
        end

        try
            JulGame.Component.set_volume(this.campfireSoundSource, round(Int, clamp(this.campfireCurrentVolume, 0, 128)), this.campfireSoundSource.channel)
        catch e
            @warn "Failed to apply campfire volume: $e"
        end
    end

    """
    Re-apply music/drums SDL volumes from settings.
    Event/rest layered mix is skipped by AudioManager scene SoundSources; call when sliders change.
    """
    function apply_volume_settings!(this::DJ)
        @debug "Applying volume settings to DJ"
        vol = music_effective_volume_sdl()

        if this.drumsSoundSource === nothing || this.currentSong != "patientbravery"
            @debug "Applying volume settings to DJ: no drums sound source or not patientbravery"
            this.musicCurrentVolume = vol
            this.originalMusicVolume = vol
            try
                JulGame.Component.set_volume(this.musicSource, round(Int, clamp(vol, 0, 128)), this.musicSource.channel)
            catch e
                @warn "Failed to apply music volume: $e"
                Base.show_backtrace(stderr, catch_backtrace())
            end
            apply_campfire_volume_settings!(this)
            return
        end

        scene = normalize_scene_name(MAIN.scene.name)
        on_event_rest = scene == "event" || scene == "rest"

        if this.drumsFadeState == DrumsFadingIn
            @debug "Applying volume settings to DJ: drums fading in"
            this.drumsTargetVolume = vol
            this.musicTargetVolume = 0
        elseif this.drumsFadeState == DrumsFadingOut
            @debug "Applying volume settings to DJ: drums fading out"
            this.drumsTargetVolume = 0
            this.musicTargetVolume = vol
        elseif on_event_rest
            @debug "Applying volume settings to DJ: event/rest"
            this.drumsCurrentVolume = vol
            this.musicCurrentVolume = 0
            this.drumsTargetVolume = vol
            this.musicTargetVolume = 0
        else
            @debug "Applying volume settings to DJ: other"
            this.drumsCurrentVolume = 0
            this.musicCurrentVolume = vol
            this.drumsTargetVolume = 0
            this.musicTargetVolume = vol
        end
        this.originalMusicVolume = vol

        try
            @debug "Applying volume settings to DJ: setting volumes"
            JulGame.Component.set_volume(this.drumsSoundSource, round(Int, clamp(this.drumsCurrentVolume, 0, 128)), this.drumsSoundSource.channel)
            JulGame.Component.set_volume(this.musicSource, round(Int, clamp(this.musicCurrentVolume, 0, 128)), this.musicSource.channel)
        catch e
            @warn "Failed to apply layered music volume: $e"
        end
        apply_campfire_volume_settings!(this)
    end

    export get_scene_to_song_map, normalize_scene_name, resolve_music_scene_key, theme_for_scene,
           music_effective_volume_sdl, sfx_effective_volume_sdl, try_get_dj, apply_volume_settings!,
           fade_in_campfire_layer, fade_out_campfire_layer
end
