module PersistentStateManagerModule
    using Random
    using ..Globals

    export reset_for_new_run

    mutable struct PersistentStateManager
        parent
        seed::Int
        seedText
        piecePlacementRNG
        piecePlacementRNGUseCount::Int

        # Map progress
        currentLevel::Int
        currentFloor::Int
        currentRoom::Int
        isFloorComplete::Bool
        isRunActive::Bool
        completedNodes::Vector{Int}
        currentEnemies
        mapPoints
        currentEvent
        mapConnections
        availableNodes
        startingPoints::Vector{Int}
        """Regular map battles won this run (category \"enemy\" only); used for first-three tutorial comps."""
        regularMapBattlesWonThisRun::Int

        # Player persistent data for shop and other events
        playerData::Dict{String, Any}
        
        # Run timer - tracks total elapsed time during a run
        runElapsedTime::Float64

        """Max match combo length achieved this run (gameplay; not analytics-gated)."""
        highestComboThisRun::Int

        """Hue shift (degrees) of the shared scrolling background; 0 = default purple."""
        scrollBgHue::Float64

        function PersistentStateManager()
            this = new()
            @debug("PersistentStateManager initialized")

            this.piecePlacementRNGUseCount = 0
            init_seed(this)

            this.currentLevel = 0
            this.currentFloor = 1
            this.currentRoom = 0
            this.isFloorComplete = false
            this.isRunActive = false
            this.currentEnemies = [(name = "Snake", level = 1, maxHealth = 20, health = 20, attack = 10, defense = 5)]
            this.currentEvent = (type = "", name = "")

            this.mapPoints = nothing

            # Initialize player data
            this.playerData = Dict{String, Any}()
            this.mapConnections = Dict{String, Any}()
            this.availableNodes = []
            this.completedNodes = Int[]
            this.startingPoints = Int[]
            this.regularMapBattlesWonThisRun = 0
            
            # Initialize run timer
            this.runElapsedTime = 0.0
            this.highestComboThisRun = 0
            this.scrollBgHue = 0.0

            return this
        end
    end

    function initialize(this::PersistentStateManager)
        if MAIN.scene.name != "title_scene"
            # this.seedText = JulGame.SceneModule.get_ui_element_by_name(MAIN.scene, "Seed Text")
            # this.seedText.text = "Seed: $(this.seed)"
            # this.seedText.persistentBetweenScenes = true
        end
    end

    function init_seed(this::PersistentStateManager; seed::Int = rand(1:100))
        this.seed = seed
        this.piecePlacementRNG = Random.Xoshiro(this.seed);
        @debug("Seed initialized: $(this.seed)")
    end

    """
    Reset all persistent state for a new run
    """
    function reset_for_new_run(this::PersistentStateManager)
        @debug("Resetting persistent state for new run")
        
        # Reset seed and RNG
        init_seed(this)
        this.piecePlacementRNGUseCount = 0
        
        # Reset map progress
        this.currentLevel = 0  # This will also set isRunActive = false
        this.currentFloor = 1
        this.currentRoom = 0
        this.isFloorComplete = false
        this.completedNodes = Int[]
        
        # Reset map data
        this.mapPoints = nothing
        this.mapConnections = Dict()
        this.availableNodes = []
        this.startingPoints = Int[]
        this.regularMapBattlesWonThisRun = 0
        
        # Reset current enemies and event
        this.currentEnemies = [(name = "Snake", level = 1, maxHealth = 20, health = 20, attack = 10, defense = 5)]
        this.currentEvent = (type = "", name = "")
        
        # Clear player data (shop flags, etc.)
        this.playerData = Dict{String, Any}()

        # try
        #     parentmodule(parentmodule(@__MODULE__)).RunScalingModule.reset!()
        # catch 
        # end
        
        # Reset run timer
        this.runElapsedTime = 0.0
        this.highestComboThisRun = 0
        this.scrollBgHue = 0.0

        adata = Globals.get_analytics_data()
        if adata !== nothing && adata.is_analytics_enabled
            Globals.AnalyticsModule.reset(adata)
        end
        Globals.RunRecorderModule.reset!()
        
        @debug("Persistent state reset complete. New seed: $(this.seed)")
    end

    function get_rand_0_1_from_seed_and_update_seed_use_count(this)
        this.piecePlacementRNGUseCount += 1;

        return rand(this.piecePlacementRNG)
    end

    function get_rand_from_seed_and_update_seed_use_count(this)
        this.piecePlacementRNGUseCount += 1;

        return pick_item_based_on_weight(this)
    end

    function get_rand_grid_from_seed_and_update_seed_use_count(this, gridWidth, gridHeight)
        this.piecePlacementRNGUseCount += (gridWidth * gridHeight)

        # Create and fill a 7x7 array
        board = Array{Any}(undef, gridWidth, gridHeight)

        for i in 1:gridWidth, j in 1:gridHeight
            # Keep trying items until we find one that works
            item = pick_item_based_on_weight(this)
            attempts = 1

            # If the first item creates a match, try up to 10 more times
            while creates_three_in_a_row_or_column(board, i, j, item) && attempts < 10
                item = pick_item_based_on_weight(this)
                attempts += 1
            end

            if attempts >= 10
                @debug("Failed to find a valid item for position $(i),$(j) after 10 attempts")
            end

            # Use the best item we found
            board[i, j] = item
        end

        return board
    end
    function creates_three_in_a_row_or_column(board, i, j, item)
        # Check row
        if j >= 3 && board[i, j-1] == item && board[i, j-2] == item
            return true
        end

        # Check column
        if i >= 3 && board[i-1, j] == item && board[i-2, j] == item
            return true
        end

        return false
    end

    function pick_item_based_on_weight(this)
        # Parse the JSON file
        data = nothing
        data = Globals.get_user_data().pieces  # Use the new accessor function

        #@debug "Piece data: $(data)"
        # Extract keys and rarities
        items = [entry for entry in data if entry !== nothing]
        weights = [entry.weight for entry in data if entry !== nothing]

        # Normalize rarities to create probabilities
        total_weight = sum(weights)
        cumulative_probabilities = cumsum(weights) ./ total_weight

        # Generate a random number and find the corresponding item
        random_value = get_rand_0_1_from_seed_and_update_seed_use_count(this)
        for (i, cp) in enumerate(cumulative_probabilities)
            if random_value <= cp
                #@debug("Selected item: $(items[i])")
                #@debug("Selected item info: $(data[items[i]])")
                return items[i]
            end
        end
    end

    function Base.setproperty!(script::PersistentStateManager, property::Symbol, value)
        if property == :isFloorComplete && value == true
            push!(script.completedNodes, script.currentLevel)
            setfield!(script, property, value)  # Actually set the property!
        elseif property == :currentLevel
            # Update isRunActive when currentLevel changes
            setfield!(script, property, value)
            # Run is active when currentLevel > 0
            setfield!(script, :isRunActive, value > 0)
        elseif property == :currentFloor
            # Track floor changes and reset per-floor effects
            setfield!(script, property, value)
            # Ancient Shield: "This only works once per floor."
            try
                user = Globals.get_user_data()
                user.ancient_shield_used = false
            catch e
                @debug("Error resetting Ancient Shield state on floor change: $e")
            end
        else
            setfield!(script, property, value)
        end
    end

    function capture_piece_placement_rng(this::PersistentStateManager)
        rng = this.piecePlacementRNG
        return (
            seed = this.seed,
            use_count = this.piecePlacementRNGUseCount,
            state = (rng.s0, rng.s1, rng.s2, rng.s3),
        )
    end

    function restore_piece_placement_rng!(
        this::PersistentStateManager;
        seed::Int,
        use_count::Int,
        state::NTuple{4, UInt64},
    )
        this.seed = seed
        this.piecePlacementRNGUseCount = use_count
        rng = Random.Xoshiro(0)
        rng.s0 = state[1]
        rng.s1 = state[2]
        rng.s2 = state[3]
        rng.s3 = state[4]
        this.piecePlacementRNG = rng
    end
end
