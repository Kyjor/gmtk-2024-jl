module BattleEnemyManagerModule
    using JulGame
    using ..Scripts

    mutable struct BattleEnemyManager <: Script
        parent # reference to the entity this script is attached to
        
        # References to managers
        battleManager
        gridController
        gameManager
        
        function BattleEnemyManager()
            this = new()
            return this
        end
    end

    function JulGame.initialize(this::BattleEnemyManager)
        @debug("BattleEnemyManager.initialize called")
        
        # Get references to other scripts from parent entity
        set_references(this)
    end
    function set_references(this::BattleEnemyManager)
        this.battleManager = this.parent.scripts[4]  # BattleManager is script 4
        this.gridController = this.parent.scripts[3]  # GridController is script 3
        this.gameManager = this.parent.scripts[1]    # GameManager is script 1
    end

    function JulGame.update(this::BattleEnemyManager, deltaTime)
        # This manager is primarily called from BattleManager's process_enemy_turn
        # No per-frame updates needed
    end

    function JulGame.on_shutdown(this::BattleEnemyManager)
        # Clean up if needed
    end

    """
    Determines the next intent for an enemy, using advanced AI if available.
    Falls back to standard pattern cycling if no advanced behavior is defined.
    
    Returns: (intent::String, intentValue::Int) or nothing to use standard pattern
    """
    function determine_enemy_intent(this::BattleEnemyManager, enemy)
        set_references(this)
        # Build context for advanced AI decision making
        globals = JulGame.UserGlobals["Module"]

        @debug "Setting up context for advanced AI decision making"
        kcm = isdefined(this.battleManager, :kingsCourtMode) && this.battleManager.kingsCourtMode
        context = Scripts.EnemyPatternsModule.AIContext(
            this.battleManager,
            this.gridController,
            globals.get_user_data(),
            [e.scripts[1] for e in this.battleManager.enemies],
            enemy,
            get_enemy_composition(this),
            get_turn_number(this),
            kcm
        )
        @debug "Created context for advanced AI decision making"
        # Try to execute advanced pattern
        result = nothing
        result = Scripts.EnemyPatternsModule.execute_advanced_pattern(enemy.enemyKey, enemy, context)
        
        if result !== nothing
            @debug("Advanced AI for $(enemy.enemyKey) chose: $(result[1]) with value $(result[2])")
            return result
        end
        
        # Return nothing to signal fallback to standard pattern
        return nothing
    end

    """
    Helper to get the current enemy composition as a string
    """
    function get_enemy_composition(this::BattleEnemyManager)
        enemy_keys = [e.scripts[1].enemyKey for e in this.battleManager.enemies]
        return join(enemy_keys, ",")
    end

    """
    Helper to get the current turn number
    """
    function get_turn_number(this::BattleEnemyManager)
        # Calculate based on starting moves minus current moves
        return this.battleManager.startingMoveCount - this.battleManager.moveCount
    end

    # Export the main function for use in Enemy.jl
    export determine_enemy_intent

end

