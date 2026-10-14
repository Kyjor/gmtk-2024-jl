module TypingEffectModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule

    """
    Reusable typing effect controller that can be attached to any text display.
    Animates text character-by-character with configurable speed, sounds, and behavior.
    """
    mutable struct TypingEffectController
        # Full text to display
        full_text::String
        
        # Current state
        current_char_index::Int
        elapsed_time::Float64
        is_complete::Bool
        is_active::Bool
        
        # Speed configuration (milliseconds per character)
        base_speed_ms::Float64
        speed_up_multiplier::Float64
        is_speed_up_held::Bool
        
        # Sound configuration
        sound_files::Vector{String}
        play_sound_every_n_chars::Int
        char_count_for_sound::Int
        punctuation_sounds_enabled::Bool
        
        # Punctuation pause configuration
        punctuation_pause_ms::Float64
        punctuation_chars::Set{Char}
        in_punctuation_pause::Bool
        punctuation_pause_elapsed::Float64
        
        # Visual indicator
        show_completion_indicator::Bool
        completion_indicator_text::String
        completion_indicator_blink_speed::Float64
        completion_indicator_visible::Bool
        completion_indicator_timer::Float64
        
        # Skip/speed controls
        skip_key::String
        speed_up_key::String
        skip_on_click::Bool
        
        function TypingEffectController(
            text::String = "";
            base_speed_ms::Float64 = 50.0,
            speed_up_multiplier::Float64 = 3.0,
            sound_files::Vector{String} = [JulGame.UserGlobals["Module"].get_asset_path("sfx", "tick1")],
            play_sound_every_n_chars::Int = 2,
            punctuation_sounds_enabled::Bool = false,
            punctuation_pause_ms::Float64 = 300.0,
            show_completion_indicator::Bool = true,
            completion_indicator_text::String = "▼",
            completion_indicator_blink_speed::Float64 = 0.5,
            skip_key::String = "RETURN",
            speed_up_key::String = "SPACE",
            skip_on_click::Bool = true
        )
            this = new()
            
            this.full_text = text
            this.current_char_index = 0
            this.elapsed_time = 0.0
            this.is_complete = false
            this.is_active = false
            
            this.base_speed_ms = base_speed_ms
            this.speed_up_multiplier = speed_up_multiplier
            this.is_speed_up_held = false
            
            this.sound_files = sound_files
            this.play_sound_every_n_chars = play_sound_every_n_chars
            this.char_count_for_sound = 0
            this.punctuation_sounds_enabled = punctuation_sounds_enabled
            
            this.punctuation_pause_ms = punctuation_pause_ms
            this.punctuation_chars = Set(['.', '!', '?', ',', ';', ':'])
            this.in_punctuation_pause = false
            this.punctuation_pause_elapsed = 0.0
            
            this.show_completion_indicator = show_completion_indicator
            this.completion_indicator_text = completion_indicator_text
            this.completion_indicator_blink_speed = completion_indicator_blink_speed
            this.completion_indicator_visible = true
            this.completion_indicator_timer = 0.0
            
            this.skip_key = skip_key
            this.speed_up_key = speed_up_key
            this.skip_on_click = skip_on_click
            
            return this
        end
    end
    
    """
    Start typing effect with new text
    """
    function start_typing(this::TypingEffectController, text::String)
        this.full_text = text
        this.current_char_index = 0
        this.elapsed_time = 0.0
        this.is_complete = false
        this.is_active = true
        this.char_count_for_sound = 0
        this.in_punctuation_pause = false
        this.punctuation_pause_elapsed = 0.0
        this.completion_indicator_timer = 0.0
        this.completion_indicator_visible = true
        @debug "Started typing effect for text: $(text[1:min(50, length(text))])..."
    end
    
    """
    Stop/pause typing effect
    """
    function stop_typing(this::TypingEffectController)
        this.is_active = false
    end
    
    """
    Complete typing instantly
    """
    function complete_instantly(this::TypingEffectController)
        this.current_char_index = length(this.full_text)
        this.is_complete = true
        this.in_punctuation_pause = false
        halt_typing_sound()
        @debug "Typing completed instantly"
    end

    function halt_typing_sound()
        try
            globals = JulGame.UserGlobals["Module"]
            JulGame.SDL2.Mix_HaltChannel(globals.AudioManagerModule.SFX_CHANNEL_TYPING)
        catch e
            @warn "Failed to halt typing sound: $e"
        end
    end
    
    """
    Reset to allow re-typing
    """
    function reset(this::TypingEffectController)
        this.current_char_index = 0
        this.elapsed_time = 0.0
        this.is_complete = false
        this.is_active = false
        this.char_count_for_sound = 0
        this.in_punctuation_pause = false
        this.punctuation_pause_elapsed = 0.0
    end
    
    """
    Get the currently visible portion of text
    """
    function get_visible_text(this::TypingEffectController)::String
        if this.current_char_index >= length(this.full_text)
            return this.full_text
        end
        return first(this.full_text, this.current_char_index)
    end
    
    """
    Check if a character is punctuation that should trigger a pause
    """
    function is_pause_punctuation(this::TypingEffectController, char::Char)::Bool
        return char in this.punctuation_chars
    end
    
    """
    Check if a character should be silent (no sound)
    """
    function is_silent_char(this::TypingEffectController, char::Char)::Bool
        # Spaces are always silent
        if char == ' ' || char == '\n' || char == '\t'
            return true
        end
        
        # Punctuation silent unless enabled
        if !this.punctuation_sounds_enabled && is_pause_punctuation(this, char)
            return true
        end
        
        return false
    end
    
    """
    Play a random typing sound
    """
    function play_typing_sound(this::TypingEffectController)
        if isempty(this.sound_files)
            return
        end
        
        try
            globals = JulGame.UserGlobals["Module"]
            sound_file = rand(this.sound_files)
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(),
                sound_file,
                false,
                1.0,
                0,
                globals.AudioManagerModule.SFX_CHANNEL_TYPING,
            )
        catch e
            @warn "Failed to play typing sound: $e"
        end
    end
    
    """
    Update the typing effect. Call this every frame.
    Returns true if text changed this frame.
    """
    function update(this::TypingEffectController, deltaTime::Float64)::Bool
        if !this.is_active || this.is_complete
            # Update completion indicator blinking
            if this.is_complete && this.show_completion_indicator
                this.completion_indicator_timer += deltaTime
                if this.completion_indicator_timer >= this.completion_indicator_blink_speed
                    this.completion_indicator_visible = !this.completion_indicator_visible
                    this.completion_indicator_timer = 0.0
                end
            end
            return false
        end
        
        # Handle input for skipping/speeding up
        handle_input(this)
        
        # Handle punctuation pause
        if this.in_punctuation_pause
            this.punctuation_pause_elapsed += deltaTime * 1000.0  # Convert to ms
            if this.punctuation_pause_elapsed >= this.punctuation_pause_ms
                this.in_punctuation_pause = false
                this.punctuation_pause_elapsed = 0.0
            end
            return false
        end
        
        # Calculate effective speed
        effective_speed = this.base_speed_ms
        if this.is_speed_up_held
            effective_speed /= this.speed_up_multiplier
        end
        
        # Update timer
        this.elapsed_time += deltaTime * 1000.0  # Convert to ms
        
        # Check if we should advance to next character
        text_changed = false
        while this.elapsed_time >= effective_speed && this.current_char_index < length(this.full_text)
            this.elapsed_time -= effective_speed
            this.current_char_index += 1
            text_changed = true
            
            # Get the character we just revealed
            current_char = this.full_text[nextind(this.full_text, 0, this.current_char_index)]
            
            # Play sound if appropriate
            if !is_silent_char(this, current_char)
                this.char_count_for_sound += 1
                if this.char_count_for_sound >= this.play_sound_every_n_chars
                    play_typing_sound(this)
                    this.char_count_for_sound = 0
                end
            end
            
            # Check for punctuation pause
            if is_pause_punctuation(this, current_char)
                this.in_punctuation_pause = true
                this.punctuation_pause_elapsed = 0.0
                break
            end
            
            # Check if complete
            if this.current_char_index >= length(this.full_text)
                this.is_complete = true
                @debug "Typing effect completed"
                break
            end
        end
        
        return text_changed
    end
    
    """
    Handle input for skip/speed up controls
    """
    function handle_input(this::TypingEffectController)
        # Check for instant skip (key press or click)
        skip_pressed = JulGame.InputModule.get_button_pressed(this.skip_key)
        if this.skip_on_click
            skip_pressed = skip_pressed || JulGame.InputModule.get_mouse_button_pressed(1)
        end
        
        if skip_pressed
            complete_instantly(this)
            return
        end
        
        # Check for speed up (key held)
        this.is_speed_up_held = JulGame.InputModule.get_button_held_down(this.speed_up_key)
    end
    
    """
    Draw the completion indicator if typing is complete
    """
    function draw_completion_indicator(
        this::TypingEffectController;
        anchor = :centerBottom,
        anchorOffset = JulGame.Math.Vector2(0, -20),
        fontSize::Int = 32,
        color::Tuple{Int,Int,Int,Int} = (255, 255, 255, 255),
        layer::Int = 10,
        parent = nothing
    )
        if !this.is_complete || !this.show_completion_indicator || !this.completion_indicator_visible
            return
        end
        
        kwargs = Dict(
            :fontSize => fontSize,
            :anchor => anchor,
            :anchorOffset => anchorOffset,
            :color => color,
            :layer => layer
        )
        
        if parent !== nothing
            kwargs[:parent] = parent
        end
        
        DisplayTextModule.display_text(
            "typing_completion_indicator",
            this.completion_indicator_text;
            kwargs...
        )
    end
    
    """
    Check if typing is complete
    """
    function is_typing_complete(this::TypingEffectController)::Bool
        return this.is_complete
    end
    
    """
    Check if typing is active
    """
    function is_typing_active(this::TypingEffectController)::Bool
        return this.is_active
    end

end # module


