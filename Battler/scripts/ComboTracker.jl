"""
ComboTracker Module

A modular combo tracking system for match-3 roguelite games that leverages the Observer pattern.
Tracks consecutive matches within cascading sequences and emits events for external systems
(audio, UI, gameplay logic) to respond to independently.

Design Principles:
- Decoupled from specific game logic through Observer pattern
- Tracks combo lifecycle: initiation → progression → termination
- Immutable data structures for match information
- Thread-safe state management
- Clear separation between state tracking and event emission

Integration:
- Works with Observer.jl for event emission
- Integrates with GridController.jl match detection
- Provides subscription interface for external responders
"""

module ComboTrackerModule
    using JulGame
    using ..Scripts

    # Re-bound each battle so the observer always targets the live ComboTracker instance.
    const _combo_tracker_observer_ref = Ref{Union{Nothing, Function}}(nothing)

    # Event type definitions for combo lifecycle
    # These symbols are used with Observer.jl's notify() function
    const COMBO_STARTED = :combo_started
    const COMBO_PROGRESSED = :combo_progressed
    const COMBO_ENDED = :combo_ended

    """
    ComboMatchData
    
    Immutable struct containing detailed information about a single match within a combo chain.
    This data structure is passed to observers with each combo event.
    
    Fields:
    - match_length: Number of items matched in this specific match
    - match_type: Item type matched (e.g., "PIECE_SWORD", "PIECE_SHIELD")
    - positions: Grid positions of matched items [(x, y), ...]
    - sequence_number: Position of this match within the combo chain (1-indexed)
    - timestamp: When this match occurred (for timing calculations)
    """
    struct ComboMatchData
        match_length::Int
        match_type::String
        positions::Vector{Tuple{Int, Int}}
        sequence_number::Int
        timestamp::Float64
        
        function ComboMatchData(match_length::Int, match_type::String, 
                               positions::Vector{Tuple{Int, Int}}, 
                               sequence_number::Int)
            new(match_length, match_type, positions, sequence_number, time())
        end
    end

    """
    ComboState
    
    Immutable struct representing the complete state of a combo at any given moment.
    This is what gets passed to observers in event payloads.
    
    Fields:
    - combo_id: Unique identifier for this combo session
    - combo_length: Number of consecutive matches in the chain
    - total_items_matched: Cumulative count of all items matched across the combo
    - match_history: Complete sequence of all matches in the combo
    - match_type_counts: Dictionary tracking frequency of each match type
    - is_active: Whether the combo is currently in progress
    - duration: Total time elapsed since combo started
    """
    struct ComboState
        combo_id::String
        combo_length::Int
        total_items_matched::Int
        match_history::Vector{ComboMatchData}
        match_type_counts::Dict{String, Int}
        is_active::Bool
        duration::Float64
        
        function ComboState(combo_id::String, combo_length::Int, 
                           total_items_matched::Int,
                           match_history::Vector{ComboMatchData},
                           match_type_counts::Dict{String, Int},
                           is_active::Bool, duration::Float64)
            new(combo_id, combo_length, total_items_matched, 
                match_history, match_type_counts, is_active, duration)
        end
    end

    """
    ComboTracker
    
    Central state manager for combo tracking. This mutable struct maintains the active
    combo state and emits events through the Observer pattern when combo lifecycle
    events occur.
    
    The ComboTracker integrates with Observer.jl by using the global observer instance
    to emit events. External systems subscribe to combo events through Observer.jl's
    add_observer() function.
    
    State Management:
    - Tracks whether a combo is currently active
    - Maintains running totals of match count and items matched
    - Stores complete match history for the current combo
    - Generates unique combo IDs for each combo session
    
    Thread Safety:
    - All state mutations happen in single-threaded update flow
    - Immutable ComboState snapshots passed to observers
    """
    mutable struct ComboTracker
        parent::Any  # Reference to parent entity (JulGame convention)
        
        # Core combo state
        is_combo_active::Bool
        current_combo_id::String
        combo_length::Int
        total_items_matched::Int
        match_history::Vector{ComboMatchData}
        match_type_counts::Dict{String, Int}
        combo_start_time::Float64
        
        # Speed scaling state
        base_game_speed::Float64  # Stores the base game speed when combo started
        combo_speed_multiplier::Float64  # Current combo speed boost (starts at 1.0)
        
        # Configuration
        require_cascade_for_combo::Bool  # If true, initial player match doesn't count
        combo_speed_enabled::Bool  # Toggle for combo speed scaling
        
        function ComboTracker()
            this = new()
            this.is_combo_active = false
            this.current_combo_id = ""
            this.combo_length = 0
            this.total_items_matched = 0
            this.match_history = ComboMatchData[]
            this.match_type_counts = Dict{String, Int}()
            this.combo_start_time = 0.0
            this.base_game_speed = 1.0
            this.combo_speed_multiplier = 1.0
            this.require_cascade_for_combo = false  # Count initial match by default
            this.combo_speed_enabled = true  # Enable combo speed by default
            return this
        end
    end

    """
    register_match(tracker::ComboTracker, match_length::Int, match_type::String, 
                   positions::Vector{Tuple{Int, Int}}, is_initial_match::Bool)
    
    Registers a new match in the combo system. This is the primary integration point
    called from GridController when matches are detected.
    
    Logic Flow:
    1. If no active combo and this is a valid combo start → emit COMBO_STARTED
    2. If combo already active → emit COMBO_PROGRESSED
    3. Update internal state with new match data
    4. Create immutable ComboState snapshot for observers
    
    Parameters:
    - match_length: Number of items in this match
    - match_type: Type identifier (e.g., "PIECE_SWORD")
    - positions: Grid coordinates of matched items
    - is_initial_match: True if this is the player-triggered match (not cascade)
    
    Integration with GridController:
    Call this from the match_event in search_for_matches() after connected_matches
    are computed. For cascading matches, call from check_for_falling_pieces_to_continue_matching().
    """
    function register_match(this::ComboTracker, match_length::Int, match_type::String,
                           positions::Vector{Tuple{Int, Int}}, is_initial_match::Bool)
        
        # Determine if this match should start or continue a combo
        should_start_combo = !this.is_combo_active && 
                           (!this.require_cascade_for_combo || !is_initial_match)
        
        if should_start_combo
            # Initialize new combo
            start_combo(this)
        end
        
        # Only register if we have an active combo
        if !this.is_combo_active
            return  # Skip initial match if require_cascade_for_combo is true
        end
        
        # Increment combo metrics
        this.combo_length += 1
        this.total_items_matched += match_length
        
        # Update match type frequency
        if haskey(this.match_type_counts, match_type)
            this.match_type_counts[match_type] += 1
        else
            this.match_type_counts[match_type] = 1
        end
        
        # Create immutable match data for this specific match
        match_data = ComboMatchData(
            match_length,
            match_type,
            positions,
            this.combo_length,
        )
        push!(this.match_history, match_data)
        
        # Update combo speed (exponential scaling)
        update_combo_speed(this)
        
        # Create immutable combo state snapshot
        combo_state = create_combo_state_snapshot(this)
        
        # Emit appropriate event through Observer pattern
        if this.combo_length == 1
            emit_combo_started(combo_state)
            @debug "Combo started"
        else
            emit_combo_progressed(combo_state)
            @debug "Combo progressed, state: $(combo_state)"
        end
        
        @debug "Combo registered: length=$(this.combo_length), items=$(this.total_items_matched), type=$(match_type)"
    end

    """
    start_combo(tracker::ComboTracker)
    
    Initializes a new combo session. Generates unique combo ID and resets all tracking state.
    Called internally when the first match in a cascade is detected.
    """
    function start_combo(this::ComboTracker)
        this.is_combo_active = true
        this.current_combo_id = generate_combo_id()
        this.combo_length = 0
        this.total_items_matched = 0
        this.match_history = ComboMatchData[]
        this.match_type_counts = Dict{String, Int}()
        this.combo_start_time = time()
        
        # Store the current base game speed and reset combo speed multiplier
        if this.combo_speed_enabled
            try
                globals = JulGame.UserGlobals["Module"]
                data_manager = globals.get_data_manager()
                if data_manager !== nothing
                    # Store the base speed (before any combo multiplier is applied)
                    this.base_game_speed = data_manager.game_speed_multiplier
                    this.combo_speed_multiplier = 1.0
                    @debug "Combo started: stored base speed $(this.base_game_speed)x"
                end
            catch e
                @warn "Failed to store base game speed: $(e)"
                this.base_game_speed = 1.0
            end
        end
        
        @debug "Combo started: ID=$(this.current_combo_id)"
    end

    """
    calculate_combo_speed_multiplier(combo_length::Int)
    
    Calculates the exponential speed multiplier based on combo length.
    Formula: 1.0 * (1.05^combo_length), capped at 3.0
    
    Parameters:
    - combo_length: Current number of matches in the combo chain
    
    Returns:
    - Speed multiplier (1.0 to 3.0)
    """
    function calculate_combo_speed_multiplier(combo_length::Int)
        if combo_length <= 0
            return 1.0
        end
        
        # Exponential growth: 1.05^combo_length
        # This gives: 1->1.0, 2->1.05, 3->1.10, 5->1.28, 10->1.63, 20->2.65, 22->3.06 (capped)
        speed_multiplier = 1.0 * (1.05 ^ combo_length)
        
        # Cap at maximum of 3.0
        return min(speed_multiplier, 3.0)
    end

    """
    update_combo_speed(tracker::ComboTracker)
    
    Updates the global game speed multiplier based on the current combo length.
    Applies exponential speed scaling that increases gradually as combos continue.
    """
    function update_combo_speed(this::ComboTracker)
        if !this.combo_speed_enabled || !this.is_combo_active
            return
        end
        
        try
            # Calculate the new combo speed multiplier (exponential)
            this.combo_speed_multiplier = calculate_combo_speed_multiplier(this.combo_length)
            
            # Apply: effective_speed = base_speed * combo_multiplier
            effective_speed = this.base_game_speed * this.combo_speed_multiplier
            
            # Update global game speed
            globals = JulGame.UserGlobals["Module"]
            data_manager = globals.get_data_manager()
            if data_manager !== nothing
                data_manager.game_speed_multiplier = effective_speed
                @debug "Combo speed updated: base=$(this.base_game_speed)x, combo=$(this.combo_speed_multiplier)x, effective=$(effective_speed)x"
            end
        catch e
            @warn "Failed to update combo speed: $(e)"
        end
    end

    """
    end_combo(tracker::ComboTracker)
    
    Terminates the current combo session and emits the COMBO_ENDED event.
    Resets game speed to the base speed that was stored when combo started.
    
    This should be called from GridController when:
    1. search_for_matches() finds no matches (entities_to_destroy is empty)
    2. check_for_falling_pieces_to_continue_matching() completes with no new matches
    3. The board has stabilized and no more cascades are possible
    
    Integration Point:
    Add a check in GridController.search_for_matches() after line 377:
    ```julia
    elseif this.battleManager.currentState == this.battleManager.battleStates[:processTurn]
        # No matches found, board is stable - end combo if active
        end_combo_if_active(combo_tracker)
    end
    ```
    """
    function end_combo(this::ComboTracker)
        if !this.is_combo_active
            return  # No active combo to end
        end
        
        # Create final combo state snapshot
        combo_state = create_combo_state_snapshot(this)
        # Mark inactive before notify. This tracker also listens for :combo_ended,
        # and the payload below is what Nunchucks reads for its damage.
        this.is_combo_active = false
        
        # Reset game speed to base speed
        if this.combo_speed_enabled
            try
                globals = JulGame.UserGlobals["Module"]
                data_manager = globals.get_data_manager()
                if data_manager !== nothing
                    data_manager.game_speed_multiplier = this.base_game_speed
                    this.combo_speed_multiplier = 1.0
                    @debug "Combo ended: reset speed to base $(this.base_game_speed)x"
                end
            catch e
                @warn "Failed to reset combo speed: $(e)"
            end
        end
        
        # Track combo length in analytics
        try
            Globals.AnalyticsModule.track_action(:combo_length, combo_state.combo_length)
        catch e
            @debug "Could not track combo: $e"
        end
        
        emit_combo_ended(combo_state)
        
        clear_combo_counters!(this)
        
        @debug "Combo ended: length=$(combo_state.combo_length), total_items=$(combo_state.total_items_matched)"
    end

    function clear_combo_counters!(this::ComboTracker)
        this.is_combo_active = false
        this.current_combo_id = ""
        this.combo_length = 0
        this.total_items_matched = 0
        this.match_history = ComboMatchData[]
        this.match_type_counts = Dict{String, Int}()
    end

    """
    create_combo_state_snapshot(tracker::ComboTracker) -> ComboState
    
    Creates an immutable snapshot of the current combo state. This ensures observers
    receive consistent data even if the tracker's state changes during event processing.
    """
    function create_combo_state_snapshot(this::ComboTracker)
        duration = time() - this.combo_start_time
        return ComboState(
            this.current_combo_id,
            this.combo_length,
            this.total_items_matched,
            copy(this.match_history),  # Deep copy to prevent external mutation
            copy(this.match_type_counts),
            this.is_combo_active,
            duration
        )
    end

    """
    generate_combo_id() -> String
    
    Generates a unique identifier for each combo session using timestamp and random component.
    """
    function generate_combo_id()
        return "combo_$(time())_$(rand(1000:9999))"
    end

    # ============================================================================
    # Event Emission Functions
    # These integrate with Observer.jl to notify subscribed systems
    # ============================================================================

    """
    emit_combo_started(combo_state::ComboState)
    
    Emits COMBO_STARTED event through Observer.jl when the first cascading match occurs.
    
    Event Payload:
    - combo_state: Initial combo state with first match data
    
    Subscribers receive: (event::Symbol, data::ComboState)
    Example: observer(:combo_started, combo_state)
    """
    function emit_combo_started(combo_state::ComboState)
        try
            # Access the global observer from JulGame.UserGlobals
            globals = JulGame.UserGlobals["Module"]
            observer_data = globals.get_observer_data()
            
            # Notify all observers with the combo state

            globals.ObserverModule.notify(observer_data, COMBO_STARTED, combo_state)
            
            @debug "Emitted COMBO_STARTED: combo_length=$(combo_state.combo_length)"
        catch e
            @warn "Failed to emit COMBO_STARTED event: $(e)"
        end
    end

    """
    emit_combo_progressed(combo_state::ComboState)
    
    Emits COMBO_PROGRESSED event for each subsequent match in the combo chain.
    
    Event Payload:
    - combo_state: Updated combo state with cumulative statistics
    """
    function emit_combo_progressed(combo_state::ComboState)
        try
            globals = JulGame.UserGlobals["Module"]
            observer_data = globals.get_observer_data()
            globals.ObserverModule.notify(observer_data, COMBO_PROGRESSED, combo_state)
            
            @debug "Emitted COMBO_PROGRESSED: combo_length=$(combo_state.combo_length)"
        catch e
            @warn "Failed to emit COMBO_PROGRESSED event: $(e)"
        end
    end

    """
    emit_combo_ended(combo_state::ComboState)
    
    Emits COMBO_ENDED event when a combo chain completes.
    
    Event Payload:
    - combo_state: Final combo state with complete statistics
    """
    function emit_combo_ended(combo_state::ComboState)
        try
            globals = JulGame.UserGlobals["Module"]
            observer_data = globals.get_observer_data()
            globals.ObserverModule.notify(observer_data, COMBO_ENDED, combo_state)
            
            @debug "Emitted COMBO_ENDED: combo_length=$(combo_state.combo_length)"
        catch e
            @warn "Failed to emit COMBO_ENDED event: $(e)"
        end
    end

    # ============================================================================
    # JulGame Script Interface
    # These functions implement the JulGame script lifecycle
    # ============================================================================

    function register_combo_tracker_observer!(this::ComboTracker)
        globals = JulGame.UserGlobals["Module"]
        prev_obs = _combo_tracker_observer_ref[]
        if prev_obs !== nothing
            try
                globals.ObserverModule.remove_observer(globals.get_observer_data(), prev_obs)
            catch e
                @debug "ComboTracker: could not remove previous observer: $(e)"
            end
        end
        obs = (event, data) -> on_notify(this, event, data)
        _combo_tracker_observer_ref[] = obs
        globals.ObserverModule.add_observer(globals.get_observer_data(), obs)
    end

    function unregister_combo_tracker_observer!()
        prev_obs = _combo_tracker_observer_ref[]
        if prev_obs === nothing
            return
        end
        try
            globals = JulGame.UserGlobals["Module"]
            globals.ObserverModule.remove_observer(globals.get_observer_data(), prev_obs)
        catch e
            @debug "ComboTracker: could not remove observer on shutdown: $(e)"
        end
        _combo_tracker_observer_ref[] = nothing
    end

    function JulGame.initialize(this::ComboTracker)
        @debug "ComboTracker initialized"
        register_combo_tracker_observer!(this)
        reset_combo(this)
    end

    function on_notify(this::ComboTracker, event::Symbol, data::Any)
        if event == :combo_data
            register_match(this, data.length, data.type, data.positions, data.is_initial_match)
            @debug "Combo data: $(data)"
        elseif event == :combo_ended
            @debug "Combo ended"
            end_combo(this)
        end
    end

    function JulGame.update(this::ComboTracker, deltaTime::Float64)
        # ComboTracker is event-driven, no per-frame updates needed
    end

    function JulGame.on_shutdown(this::ComboTracker)
        if this.is_combo_active
            end_combo(this)
        else
            reset_combo(this)
        end
        unregister_combo_tracker_observer!()
    end

    # ============================================================================
    # Utility Functions
    # ============================================================================

    """
    is_combo_active(tracker::ComboTracker) -> Bool
    
    Returns whether a combo is currently in progress.
    """
    function is_combo_active(this::ComboTracker)
        return this.is_combo_active
    end

    """
    get_current_combo_length(tracker::ComboTracker) -> Int
    
    Returns the current combo length (number of matches in chain).
    Returns 0 if no combo is active.
    """
    function get_current_combo_length(this::ComboTracker)
        return this.is_combo_active ? this.combo_length : 0
    end

    """
    reset_combo(tracker::ComboTracker)
    
    Forces a combo reset without emitting end event. Use for game state transitions
    (pause, level end) where normal combo completion doesn't apply.
    Also resets game speed to base speed.
    """
    function reset_combo(this::ComboTracker)
        if this.is_combo_active
            @debug "Force resetting combo: ID=$(this.current_combo_id)"
            
            # Reset game speed to base speed
            if this.combo_speed_enabled
                try
                    globals = JulGame.UserGlobals["Module"]
                    data_manager = globals.get_data_manager()
                    if data_manager !== nothing
                        data_manager.game_speed_multiplier = this.base_game_speed
                        this.combo_speed_multiplier = 1.0
                    end
                catch e
                    @warn "Failed to reset combo speed during force reset: $(e)"
                end
            end
        end
        clear_combo_counters!(this)
    end

end  # module ComboTrackerModule

