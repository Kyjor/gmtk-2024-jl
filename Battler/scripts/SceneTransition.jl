module SceneTransitionModule
    using JulGame
    using ..DJModule
    include("utils/Easings.jl")
    
    @enum TransitionDirection begin
        LeftToRight
        RightToLeft
        TopToBottom
        BottomToTop
        Fade  # Whole screen fade transition
    end
    
    @enum TransitionState begin
        Idle
        WipingOut      # Covering the screen
        ChangingScene  # Actually changing the scene
        WipingIn       # Revealing the new scene
    end
    
    mutable struct TransitionConfig
        duration::Float64
        color::Tuple{Int,Int,Int,Int}
        direction::TransitionDirection
        easing_function::Function
        fade_music::Bool
        
        function TransitionConfig(;
            duration::Float64 = 0.45,
            color::Tuple{Int,Int,Int,Int} = (0, 0, 0, 255),
            direction::TransitionDirection = LeftToRight,
            easing_function::Function = ease_in_out_cubic,
            fade_music::Bool = true
        )
            new(duration, color, direction, easing_function, fade_music)
        end
    end
    
    mutable struct SceneTransition
        parent::Any
        
        # Transition state
        state::TransitionState
        progress::Float64
        target_scene::String
        config::TransitionConfig
        
        # Music fade tracking
        original_music_volume::Int
        music_fade_started::Bool
        pending_transition_wipe_in::Bool
        pending_transition_config::TransitionConfig
        function SceneTransition()
            this = new()
            this.parent = C_NULL
            this.state = Idle
            this.progress = 0.0
            this.target_scene = ""
            this.config = TransitionConfig()
            this.original_music_volume = 0
            this.music_fade_started = false
            this.pending_transition_wipe_in = false
            this.pending_transition_config = TransitionConfig()

            return this
        end
    end
    
    function JulGame.initialize(this::SceneTransition)
        @debug "SceneTransition initialized"
        
        # Check if we should start with a wipe-in (entering a new scene)
        if this.pending_transition_wipe_in
            this.state = WipingIn
            this.progress = 0.0
            this.config = this.pending_transition_config
            this.pending_transition_wipe_in = false
            @debug "Starting wipe-in for new scene"
        end
    end
    
    function JulGame.update(this::SceneTransition, deltaTime::Float64)
        if this.state == Idle
            return
        end
        
        # Update progress
        this.progress += deltaTime / this.config.duration
        
        if this.state == WipingOut
            handle_wipe_out(this, deltaTime)
        elseif this.state == WipingIn
            handle_wipe_in(this, deltaTime)
        end
    end
    
    function handle_wipe_out(this::SceneTransition, deltaTime::Float64)
        # Start music fade if configured
        if this.config.fade_music && !this.music_fade_started
            globals = JulGame.UserGlobals["Module"]
            audio_manager = globals.get_audio_manager()
            this.original_music_volume = Int(round(audio_manager.music_volume * audio_manager.master_volume / 100.0))
            this.music_fade_started = true
            @debug "Starting music fade from $(this.original_music_volume)"
        end
        
        # Update music volume during fade
        if this.config.fade_music
            globals = JulGame.UserGlobals["Module"]
            audio_manager = globals.get_audio_manager()
            fade_progress = clamp(this.progress, 0.0, 1.0)
            current_volume = Int(round(this.original_music_volume * (1.0 - fade_progress)))
            @debug "Fading music volume to $(current_volume)"
            @debug "Original volume: $(sdl_volume(this.original_music_volume))"
            # globals.AudioManagerModule.set_volumes(audio_manager, audio_manager.master_volume, current_volume, audio_manager.sfx_volume)
            set_dj_music_volume!(round(Int, sdl_volume(current_volume)))
        end
        
        # Draw the wipe rectangle
        draw_wipe_rect(this, this.progress, false)
        
        # When fully covered, change scene
        if this.progress >= 1.0
            this.state = ChangingScene
            change_to_target_scene(this)
        end
    end
    
    function handle_wipe_in(this::SceneTransition, deltaTime::Float64)
        # Draw the wipe rectangle (revealing the scene)
        draw_wipe_rect(this, 1.0 - this.progress, false)
        
        # Restore music volume
        if this.config.fade_music && this.progress > 0.0
            globals = JulGame.UserGlobals["Module"]
            audio_manager = globals.get_audio_manager()
            fade_progress = clamp(this.progress, 0.0, 1.0)
            current_volume = Int(round(this.original_music_volume * fade_progress))
            @debug "Restoring music volume to $(current_volume)"
            @debug "Original volume: $(sdl_volume(this.original_music_volume))"
            # globals.AudioManagerModule.set_volumes(audio_manager, audio_manager.master_volume, current_volume, audio_manager.sfx_volume)
            set_dj_music_volume!(round(Int, sdl_volume(current_volume)))
        end
        
        # When fully revealed, return to idle
        if this.progress >= 1.0
            this.state = Idle
            this.progress = 0.0
            this.music_fade_started = false
            @debug "Wipe-in complete"
            
            # Restore original music volume
            if this.config.fade_music
                # globals = JulGame.UserGlobals["Module"]
                # audio_manager = globals.get_audio_manager()
                # globals.AudioManagerModule.set_volumes(audio_manager, audio_manager.master_volume, this.original_music_volume, audio_manager.sfx_volume)
                set_dj_music_volume!(round(Int, sdl_volume(this.original_music_volume)))
            end
        end
    end

    function sdl_volume(volume::Int)
        return Int32(round(clamp(volume/100.0 * 128.0, 0.0, 128.0)))
    end

    function set_dj_music_volume!(volume::Int)
        dj = DJModule.try_get_dj()
        music_source = dj === nothing ? nothing : dj.musicSource
        if music_source === nothing
            return
        end
        JulGame.Component.set_volume(music_source, round(Int, clamp(volume, 0, 128)), music_source.channel)
    end
    
    # Get music for a scene using DJ module's mapping (source of truth)
    function get_music_for_scene(scene_name::String)::Union{String, Nothing}
        music_key = DJModule.resolve_music_scene_key(scene_name)
        @debug "scene_name: $(scene_name)"
        @debug "music_key: $(music_key)"
        song_name = DJModule.theme_for_scene(scene_name)
        @debug "song_name: $(song_name)"
        return song_name
    end
    
    function scenes_use_same_music(current_scene::String, target_scene::String)::Bool
        current_music = get_music_for_scene(current_scene)
        target_music = get_music_for_scene(target_scene)
        
        # If either scene has no music configured, don't prevent fading
        if current_music === nothing || target_music === nothing
            return false
        end
        
        return current_music == target_music
    end
    
    function draw_wipe_rect(this::SceneTransition, progress::Float64, is_reverse::Bool)
        # Apply easing
        eased_progress = this.config.easing_function(clamp(progress, 0.0, 1.0))
        
        # Use logical size for consistent rendering across all devices (web + desktop)
        logical_size = JulGame.WindowManagerModule.get_logical_size()
        window_width = Float64(logical_size.x)
        window_height = Float64(logical_size.y)
        
        position = JulGame.Math.Vector2(0, 0)
        size = JulGame.Math.Vector2(0, 0)
        fade_color = this.config.color
        
        # Calculate position and size based on direction
        if this.config.direction == Fade
            # For fade transition, cover the entire screen with alpha based on progress
            size = JulGame.Math.Vector2(window_width, window_height)
            position = JulGame.Math.Vector2(0, 0)
            # Modify the color alpha based on progress
            fade_alpha = Int(round(eased_progress * 255))
            fade_color = (this.config.color[1], this.config.color[2], this.config.color[3], fade_alpha)
        elseif this.config.direction == LeftToRight
            size = JulGame.Math.Vector2(window_width * eased_progress, window_height)
            position = JulGame.Math.Vector2(0, 0)
            fade_color = this.config.color
        elseif this.config.direction == RightToLeft
            size = JulGame.Math.Vector2(window_width * eased_progress, window_height)
            position = JulGame.Math.Vector2(window_width * (1.0 - eased_progress), 0)
            fade_color = this.config.color
        elseif this.config.direction == TopToBottom
            size = JulGame.Math.Vector2(window_width, window_height * eased_progress)
            position = JulGame.Math.Vector2(0, 0)
            fade_color = this.config.color
        elseif this.config.direction == BottomToTop
            size = JulGame.Math.Vector2(window_width, window_height * eased_progress)
            position = JulGame.Math.Vector2(0, window_height * (1.0 - eased_progress))
            fade_color = this.config.color
        end
        
        # Draw the rectangle
        JulGame.ImmediateUIModule.immediate_rect(
            "scene_transition_wipe";
            position = position,
            size = Vector2(size.x + 10, size.y + 10),
            color = fade_color,
            layer = 9999  # Very high layer to be on top of everything
        )
    end
    
    function change_to_target_scene(this::SceneTransition)
        @debug "Changing scene to: $(this.target_scene)"
        
        # Store transition config for the next scene's wipe-in
        this.pending_transition_wipe_in = true
        this.pending_transition_config = this.config
        
        # Change the scene
        if occursin(":", this.target_scene)
            JulGame.change_scene(String(split(this.target_scene, ":")[1]))
        else
            JulGame.change_scene(this.target_scene)
        end
    end
    
    """
        begin_transition(this::SceneTransition, target_scene::String; config::Union{Nothing, TransitionConfig} = nothing)
    
    Starts a scene transition to the target scene.
    You can provide a custom TransitionConfig or use the default.
    """
    function begin_transition(this::SceneTransition, target_scene::String; config::Union{Nothing, TransitionConfig} = nothing)
        if this.state != Idle
            @warn "Transition already in progress"
            return
        end
        
        this.target_scene = target_scene
        this.config = config !== nothing ? config : TransitionConfig()
        
        # Check if music stays the same - if so, disable music fading
        try
            current_scene_name = JulGame.MAIN.scene.name
            if scenes_use_same_music(current_scene_name, target_scene)
                @debug "Music stays the same between $current_scene_name and $target_scene, disabling music fade"
                this.config.fade_music = false
            end
        catch e
            @debug "Could not check music for scenes: $e"
            # Continue with original config if check fails
        end
        
        this.state = WipingOut
        this.progress = 0.0
        this.music_fade_started = false
        
        # Store original music volume
        globals = JulGame.UserGlobals["Module"]
        audio_manager = globals.get_audio_manager()
        this.original_music_volume = Int(round(audio_manager.music_volume * audio_manager.master_volume / 100.0))
        
        @debug "Beginning transition to $(target_scene)"
    end
    
    function JulGame.on_shutdown(this::SceneTransition)
        # Don't do anything - we want the transition to persist
    end
    
    # ===== GLOBAL HELPER FUNCTIONS =====
    
    """
        transition_to_scene(this::SceneTransition, target_scene::String; kwargs...)
    
    Convenience function to start a transition from anywhere in your code.
    
    # Arguments
    - `target_scene::String`: The scene file to transition to (e.g., "battle.json")
    
    # Keyword Arguments
    - `duration::Float64 = 0.45`: Duration of each wipe phase (out and in) in seconds (~0.9s total by default)
    - `color::Tuple{Int,Int,Int,Int} = (0, 0, 0, 255)`: RGBA color of the wipe
    - `direction::TransitionDirection = LeftToRight`: Direction of the wipe (LeftToRight, RightToLeft, TopToBottom, BottomToTop, Fade)
    - `easing::Function = ease_in_out_cubic`: Easing function from Easings.jl
    - `fade_music::Bool = true`: Whether to fade out/in music during transition
    
    # Example
    ```julia
    # Simple transition with defaults (fast black wipe left-to-right)
    transition_to_scene(this, "battle.json")
    
    # Custom red wipe from right to left with 1 second duration
    transition_to_scene(this, "shop.json"; 
        duration = 1.0, 
        color = (255, 0, 0, 255), 
        direction = RightToLeft
    )
    
    # Fast top-to-bottom white wipe without music fade
    transition_to_scene(this, "map.json"; 
        duration = 0.5, 
        color = (255, 255, 255, 255),
        direction = TopToBottom,
        fade_music = false
    )
    
    # Fade transition (whole screen fades to black)
    transition_to_scene(this, "battle.json"; 
        duration = 1.0, 
        color = (0, 0, 0, 255),
        direction = Fade
    )
    ```
    """
    function transition_to_scene(this::SceneTransition, target_scene::String; 
        duration::Float64 = 0.45,
        color::Tuple{Int,Int,Int,Int} = (0, 0, 0, 255),
        direction::TransitionDirection = LeftToRight,
        easing::Function = ease_in_out_cubic,
        fade_music::Union{Bool, Nothing} = nothing
    )
        
        # If fade_music is not explicitly set, check if music stays the same
        should_fade_music = true
        if fade_music === nothing
            try
                current_scene_name = JulGame.MAIN.scene.name
                if scenes_use_same_music(current_scene_name, target_scene)
                    @debug "Music stays the same between $current_scene_name and $target_scene, disabling music fade"
                    should_fade_music = false
                end
            catch e
                @debug "Could not check music for scenes: $e"
                should_fade_music = true
            end
        else
            should_fade_music = fade_music
        end
        
        config = TransitionConfig(
            duration = duration,
            color = color,
            direction = direction,
            easing_function = easing,
            fade_music = should_fade_music
        )
        
        begin_transition(this, target_scene; config = config)
    end
    
    """
        fade_to_scene(this::SceneTransition, target_scene::String; kwargs...)
    
    Convenience helper for a whole-screen fade-out/fade-in transition.
    
    This is equivalent to calling `transition_to_scene` with `direction = Fade`.
    All keyword arguments are forwarded to `transition_to_scene`.
    """
    function fade_to_scene(this::SceneTransition, target_scene::String; 
        duration::Float64 = 0.45,
        color::Tuple{Int,Int,Int,Int} = (0, 0, 0, 255),
        easing::Function = ease_in_out_cubic,
        fade_music::Union{Bool, Nothing} = nothing
    )
        transition_to_scene(
            this,
            target_scene;
            duration = duration,
            color = color,
            direction = Fade,
            easing = easing,
            fade_music = fade_music,
        )
    end
    
    export SceneTransition, TransitionConfig, TransitionDirection, TransitionState
    export LeftToRight, RightToLeft, TopToBottom, BottomToTop, Fade
    export begin_transition, transition_to_scene, fade_to_scene
end

