"""
ComboResponders Module

Example implementations of combo responders that subscribe to combo events through
the Observer pattern. These demonstrate how different game systems can independently
react to combo progression.

Design Pattern:
Each responder is implemented as a closure function that matches Observer.jl's
signature: observer(event::Symbol, data::Any)

The responders can be registered with Observer.jl using:
```julia
Scripts.ObserverModule.add_observer(audio_combo_responder)
Scripts.ObserverModule.add_observer(ui_combo_responder)
```

Responders remain decoupled from ComboTracker and only react to emitted events.
"""

module ComboResponderModule
    include("localization/battle_strings.jl")
    using .BattleStringsModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts

    # Ensure we only register one global combo observer across scene loads
    # This prevents duplicate combo sound/visual triggers when the battle scene is re-entered.
    global combo_observer_registered = false

    mutable struct ComboResponder <: Script
        parent
        audio_responder::Function
        ui_responder::Function
        gameplay_responder::Function
        isInCombo::Bool
        currentComboData
        lastComboSoundLength::Int  # Track last combo length that played a sound

        function ComboResponder()
            this = new()
            # this.audio_responder = create_audio_combo_responder(this)
            # this.ui_responder = create_ui_combo_responder(this)
            # this.gameplay_responder = create_gameplay_combo_responder(this)
            this.isInCombo = false
            this.lastComboSoundLength = 0

            return this
        end
    end

    function JulGame.initialize(this::ComboResponder)
        # Set up combo system observer exactly once globally.
        # Re-entering the battle scene creates new ComboResponder instances,
        # but we only want a single observer listening for combo events.
        global combo_observer_registered
        if !combo_observer_registered
            globals = JulGame.UserGlobals["Module"]
            globals.ObserverModule.add_observer((event, data) -> on_notify(this, event, data))
            combo_observer_registered = true
        end
    end

    function on_notify(this::ComboResponder, event::Symbol, data::Any)
        if event == :combo_started || event == :combo_progressed
            @debug event == :combo_started ? "Combo started" : "Combo progressed"
            this.isInCombo = true
            this.currentComboData = data

            # One SFX per combo length step (shared by normal + pattern clears)
            if data.combo_length != this.lastComboSoundLength
                play_combo_sound(data.combo_length)
                this.lastComboSoundLength = data.combo_length
            end

            # Show combo image immediately on combo progress event.
            # Doing this here (event-driven) avoids relying on a specific
            # ComboResponder instance being the one wired to the observer.
            if data.combo_length > 1 && data.combo_length <= 19
                image = JulGame.ImmediateUIModule.immediate_image(
                    "combo_image",
                    JulGame.UserGlobals["Module"].get_asset_path("combo", "$(data.combo_length)");
                    anchor = :centerTop,
                    anchorOffset = JulGame.Math.Vector2(350, 50),
                    lifetime = 3000
                )
                @debug "Combo image (event): $(image.size)"
            end

            try
                Scripts.ComboStarsModule.spawn_to!(data.combo_length, data)
            catch e
                @debug "ComboStars spawn: $e"
            end
        elseif event == :combo_ended
            @debug "Combo ended"
            this.isInCombo = false
            this.currentComboData = nothing
            this.lastComboSoundLength = 0  # Reset for next combo
            try
                Scripts.StarfallModule.dismiss_stars!()
            catch e
                @debug "ComboStars dismiss: $e"
            end
            try
                len = getfield(data, :combo_length)::Int
                globals = JulGame.UserGlobals["Module"]
                ps = globals.get_data_manager().persistent_state_manager
                if len > ps.highestComboThisRun
                    ps.highestComboThisRun = len
                end
            catch e
                @debug "Could not update highestComboThisRun: $e"
            end
        end
    end
    
    function play_combo_sound(combo_length::Int)
        try
            globals = JulGame.UserGlobals["Module"]
            # Length 1 = first match; 2+ use combo ladder (combo1 asset was renamed to combo2)
            sound_file = if combo_length <= 1
                globals.get_asset_path("sfx", "firstmatch")
            else
                JulGame.UserGlobals["Module"].get_asset_path("sfx", "combo$(clamp(combo_length, 2, 25))")
            end
            volume = combo_length <= 1 ? 1.0 : 2.0
            # Dedicated channel so ladder SFX aren't cut off by other gameplay audio
            channel = globals.AudioManagerModule.SFX_CHANNEL_COMBO
            globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), sound_file, false, volume, 0, channel)
            @debug "Playing combo sound: $(sound_file)"
        catch e
            @warn "Failed to play combo sound: $(e)"
        end
    end

    function JulGame.update(this::ComboResponder, deltaTime::Float64)
        if this.isInCombo && this.currentComboData !== nothing
            @debug "Displaying combo text"
            # display a text "COMBO x1!" in the top center of the screen
            @debug "Displaying combo image"
            @debug "Combo length: $(this.currentComboData.combo_length)"

            if this.currentComboData.combo_length > 1 && this.currentComboData.combo_length <= 19
                image =JulGame.ImmediateUIModule.immediate_image(
                    "combo_image",
                    JulGame.UserGlobals["Module"].get_asset_path("combo", "$(this.currentComboData.combo_length)");
                    anchor = :centerTop,
                    anchorOffset = JulGame.Math.Vector2(350, 50),
                    lifetime = 3000
                )
                @debug "Combo image: $(image.size)"
            end
        end
    end


    """
    create_audio_combo_responder(sound_entities::Dict{Symbol, Any}) -> Function
    
    Creates an audio responder that plays escalating sounds based on combo progression.
    
    Audio Strategy:
    - COMBO_STARTED: Play initial combo sound
    - COMBO_PROGRESSED: Play escalating sounds based on combo_length
      - 2-3 matches: Light combo sound
      - 4-5 matches: Medium combo sound  
      - 6+ matches: Heavy combo sound with increasing pitch
    - COMBO_ENDED: Play combo complete sound with pitch based on final length
    
    Parameters:
    - sound_entities: Dictionary mapping sound events to JulGame sound sources
      Expected keys: :combo_start, :combo_light, :combo_medium, :combo_heavy, :combo_end
    
    Returns:
    - Observer function that can be registered with Observer.jl
    
    Example Usage:
    ```julia
    sounds = Dict(
        :combo_start => get_entity_by_name("ComboStartSound").soundSource,
        :combo_light => get_entity_by_name("ComboLightSound").soundSource,
        :combo_medium => get_entity_by_name("ComboMediumSound").soundSource,
        :combo_heavy => get_entity_by_name("ComboHeavySound").soundSource,
        :combo_end => get_entity_by_name("ComboEndSound").soundSource
    )
    audio_responder = create_audio_combo_responder(sounds)
    Scripts.ObserverModule.add_observer(audio_responder)
    ```
    """
    function create_audio_combo_responder(sound_entities::Dict{Symbol, Any})
        # Return a closure that maintains reference to sound entities
        function audio_responder(event::Symbol, data::Any)
            # Type check: ensure we're receiving combo events
            if !(data isa Scripts.ComboTrackerModule.ComboState)
                return  # Not a combo event, ignore
            end
            
            combo_state = data::Scripts.ComboTrackerModule.ComboState
            
            try
                if event == Scripts.ComboTrackerModule.COMBO_STARTED
                    # Play initial combo sound
                    if haskey(sound_entities, :combo_start)
                        JulGame.Component.toggle_sound(sound_entities[:combo_start])
                    end
                    @debug "🎵 Combo started sound played"
                    
                elseif event == Scripts.ComboTrackerModule.COMBO_PROGRESSED
                    # Play escalating sounds based on combo length
                    combo_length = combo_state.combo_length
                    
                    if combo_length <= 3 && haskey(sound_entities, :combo_light)
                        JulGame.Component.toggle_sound(sound_entities[:combo_light])
                        @debug "🎵 Light combo sound (length=$(combo_length))"
                    elseif combo_length <= 5 && haskey(sound_entities, :combo_medium)
                        JulGame.Component.toggle_sound(sound_entities[:combo_medium])
                        @debug "🎵 Medium combo sound (length=$(combo_length))"
                    elseif combo_length > 5 && haskey(sound_entities, :combo_heavy)
                        JulGame.Component.toggle_sound(sound_entities[:combo_heavy])
                        @debug "🎵 Heavy combo sound (length=$(combo_length))"
                    end
                    
                elseif event == Scripts.ComboTrackerModule.COMBO_ENDED
                    # Play completion sound with special effect for large combos
                    if haskey(sound_entities, :combo_end)
                        JulGame.Component.toggle_sound(sound_entities[:combo_end])
                    end
                    @debug "🎵 Combo ended sound (final_length=$(combo_state.combo_length))"
                end
                
            catch e
                @warn "Audio responder error: $(e)"
            end
        end
        
        return audio_responder
    end

    """
    create_ui_combo_responder(ui_text_id::String, ui_position::Tuple{Float64, Float64}) -> Function
    
    Creates a UI responder that displays combo information using JulGame's immediate UI.
    
    Display Strategy:
    - COMBO_STARTED: Show "COMBO x1!" text
    - COMBO_PROGRESSED: Update text to show current combo length and items matched
      - Example: "COMBO x5! (23 items)"
      - Text size and color intensity increase with combo length
    - COMBO_ENDED: Show final combo stats briefly, then fade out
    
    Parameters:
    - ui_text_id: Unique identifier for the UI text element
    - ui_position: (x, y) screen position for the combo counter
    
    Returns:
    - Observer function that can be registered with Observer.jl
    
    Example Usage:
    ```julia
    ui_responder = create_ui_combo_responder("combo_counter", (0.0, 2.0))
    Scripts.ObserverModule.add_observer(ui_responder)
    ```
    """
    function create_ui_combo_responder(ui_text_id::String, ui_position::Tuple{Float64, Float64})
        function ui_responder(event::Symbol, data::Any)
            if !(data isa Scripts.ComboTrackerModule.ComboState)
                return
            end
            
            combo_state = data::Scripts.ComboTrackerModule.ComboState
            
            try
                if event == Scripts.ComboTrackerModule.COMBO_STARTED
                    # Display initial combo text
                    display_combo_text(
                        ui_text_id,
                        BattleStringsModule.BATTLE_STRINGS[:combo_start],
                        ui_position,
                        combo_state.combo_length,
                        2000  # 2 second lifetime
                    )
                    @debug "📊 Combo UI: Started (x1)"
                    
                elseif event == Scripts.ComboTrackerModule.COMBO_PROGRESSED
                    # Update combo display with current stats
                    combo_text = BattleStringsModule.format_string(:combo_active, length=combo_state.combo_length, items=combo_state.total_items_matched)
                    
                    display_combo_text(
                        ui_text_id,
                        combo_text,
                        ui_position,
                        combo_state.combo_length,
                        2000
                    )
                    @debug "📊 Combo UI: Progressed (x$(combo_state.combo_length))"
                    
                elseif event == Scripts.ComboTrackerModule.COMBO_ENDED
                    # Show final combo summary
                    final_text = BattleStringsModule.format_string(:combo_complete, length=combo_state.combo_length, items=combo_state.total_items_matched)
                    
                    display_combo_text(
                        ui_text_id,
                        final_text,
                        ui_position,
                        combo_state.combo_length,
                        3000  # 3 second lifetime for final display
                    )
                    @debug "📊 Combo UI: Ended (final x$(combo_state.combo_length))"
                end
                
            catch e
                @warn "UI responder error: $(e)"
            end
        end
        
        return ui_responder
    end

    """
    Helper function to display combo text with dynamic styling based on combo length.
    """
    function display_combo_text(text_id::String, text::String, position::Tuple{Float64, Float64},
                                combo_length::Int, lifetime::Int)
        # Calculate dynamic font size based on combo length
        base_size = 24
        size_increase = min(combo_length * 2, 24)  # Cap at +24 pixels
        font_size = base_size + size_increase
        
        # Calculate color intensity (more intense as combo grows)
        # Start at yellow, transition to orange, then red for big combos
        intensity = min(combo_length / 10.0, 1.0)
        red = 255
        green = Int(round(255 * (1.0 - intensity * 0.5)))  # Fade from 255 to 127
        blue = Int(round(255 * (1.0 - intensity)))  # Fade from 255 to 0
        
        try
            DisplayTextModule.display_text(
                text_id,
                text;
                fontSize = font_size,
                anchor = :center,
                lifetime = lifetime,
                color = (red, green, blue, 255)
            )
        catch e
            @warn "Failed to display combo text: $(e)"
        end
    end

    """
    create_gameplay_combo_responder(battle_manager::Any) -> Function
    
    Creates a gameplay responder that applies score multipliers and bonuses based on combos.
    
    Gameplay Effects:
    - COMBO_STARTED: Enable combo multiplier mode
    - COMBO_PROGRESSED: Increase multiplier with each match
      - Multiplier = 1.0 + (combo_length * 0.1)
      - Example: 5 matches = 1.5x multiplier
    - COMBO_ENDED: Apply final bonus based on total combo stats
      - Bonus damage/healing based on combo length
      - Special rewards for combos with diverse match types
    
    Parameters:
    - battle_manager: Reference to BattleManager for applying gameplay effects
    
    Returns:
    - Observer function that can be registered with Observer.jl
    
    Example Usage:
    ```julia
    gameplay_responder = create_gameplay_combo_responder(this.battleManager)
    Scripts.ObserverModule.add_observer(gameplay_responder)
    ```
    """
    function create_gameplay_combo_responder(battle_manager::Any)
        function gameplay_responder(event::Symbol, data::Any)
            if !(data isa Scripts.ComboTrackerModule.ComboState)
                return
            end
            
            combo_state = data::Scripts.ComboTrackerModule.ComboState
            
            try
                if event == Scripts.ComboTrackerModule.COMBO_STARTED
                    @debug "🎮 Combo gameplay: Multiplier activated"
                    # Could enable visual effects, UI indicators, etc.
                    
                elseif event == Scripts.ComboTrackerModule.COMBO_PROGRESSED
                    # Calculate and log current multiplier
                    multiplier = 1.0 + (combo_state.combo_length * 0.1)
                    @debug "🎮 Combo gameplay: Multiplier = $(multiplier)x"
                    
                    # Could apply progressive effects here
                    # Example: Increase damage of next attack by multiplier
                    
                elseif event == Scripts.ComboTrackerModule.COMBO_ENDED
                    # Apply final combo bonuses
                    final_multiplier = 1.0 + (combo_state.combo_length * 0.1)
                    
                    @debug "🎮 Combo gameplay: Final bonus applied ($(final_multiplier)x)"
                    
                    # Example bonus effects based on combo stats:
                    if combo_state.combo_length >= 5
                        # Large combo bonus: deal bonus damage
                        bonus_damage = combo_state.combo_length * 2
                        @debug "🎮 Large combo bonus: $(bonus_damage) damage"
                        # Scripts.BattleManagerModule.apply_bonus_damage(battle_manager, bonus_damage)
                    end
                    
                    # Diversity bonus: reward combos with multiple match types
                    if length(combo_state.match_type_counts) >= 3
                        @debug "🎮 Diversity bonus: Matched $(length(combo_state.match_type_counts)) different types"
                        # Could grant extra resources, healing, etc.
                    end
                end
                
            catch e
                @warn "Gameplay responder error: $(e)"
            end
        end
        
        return gameplay_responder
    end

    """
    register_default_combo_responders(battle_manager::Any, sound_entities::Dict{Symbol, Any})
    
    Convenience function to register a standard set of combo responders.
    Call this during battle scene initialization to set up combo system.
    
    Parameters:
    - battle_manager: Reference to BattleManager
    - sound_entities: Dictionary of combo sound sources
    
    Example Usage in BattleManager initialization:
    ```julia

    ```
    """
    function register_default_combo_responders(battle_manager::Any, sound_entities::Dict{Symbol, Any})
        try
            # Register audio responder
            audio_responder = create_audio_combo_responder(sound_entities)
            Scripts.ObserverModule.add_observer(audio_responder)
            @debug "Registered audio combo responder"
            
            # Register UI responder (position at top center of screen)
            ui_responder = create_ui_combo_responder("combo_counter", (0.0, 3.0))
            Scripts.ObserverModule.add_observer(ui_responder)
            @debug "Registered UI combo responder"
            
            # Register gameplay responder
            gameplay_responder = create_gameplay_combo_responder(battle_manager)
            Scripts.ObserverModule.add_observer(gameplay_responder)
            @debug "Registered gameplay combo responder"
            
            @debug "All default combo responders registered successfully"
        catch e
            @error "Failed to register combo responders: $(e)"
        end
    end

end  # module ComboRespondersModule

