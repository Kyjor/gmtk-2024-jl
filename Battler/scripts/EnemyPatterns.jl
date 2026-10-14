module EnemyPatternsModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule

    """
    Context struct containing all information needed for advanced AI decisions
    """
    struct AIContext
        battleManager      # Full BattleManager reference
        gridController     # GridController reference
        player            # Player state (user)
        allEnemies        # Array of all living Enemy scripts
        currentEnemy      # The enemy making the decision
        enemyComp         # String of enemy composition
        turnNumber        # Current turn number
        kingsCourtMode::Bool
    end

    """
    Registry of enemy AI modules.
    Dynamically populated as enemy AI files are included.
    """
    const ENEMY_AI_REGISTRY = Dict{String, Function}()
    
    """
    Registry of enemy skill execution functions.
    Maps enemy keys to their skill implementations.
    """
    const ENEMY_SKILL_REGISTRY = Dict{String, Function}()

    """
    Register an enemy AI function for a specific enemy key
    """
    function register_enemy_ai(enemy_key::String, ai_function::Function)
        ENEMY_AI_REGISTRY[enemy_key] = ai_function
        @debug("Registered advanced AI for $(enemy_key)")
    end
    
    """
    Register an enemy skill execution function for a specific enemy key
    """
    function register_enemy_skill(enemy_key::String, skill_function::Function)
        ENEMY_SKILL_REGISTRY[enemy_key] = skill_function
        @debug("Registered skill execution for $(enemy_key)")
    end

    """
    Execute advanced pattern for an enemy if one exists.
    Returns (intent::String, value::Int) or nothing to use standard pattern.
    """
    function execute_advanced_pattern(enemy_key::String, enemy, context::AIContext)
        if haskey(ENEMY_AI_REGISTRY, enemy_key)
            ai_function = ENEMY_AI_REGISTRY[enemy_key]
            try
                result = ai_function(enemy, context)
                return result
            catch e
                @error("Error executing advanced AI for $(enemy_key): $(e)")
                Base.show_backtrace(stderr, catch_backtrace())
                return nothing
            end
        end
        
        # No advanced AI registered for this enemy
        return nothing
    end
    
    """
    Execute an enemy's skill ability.
    Called when the enemy performs a "Skill" intent.
    """
    function execute_enemy_skill(enemy, gridController)
        if haskey(ENEMY_SKILL_REGISTRY, enemy.enemyKey)
            skill_function = ENEMY_SKILL_REGISTRY[enemy.enemyKey]
            try
                skill_function(enemy, gridController)
            catch e
                @error("Error executing skill for $(enemy.enemyKey): $(e)")
                Base.show_backtrace(stderr, catch_backtrace())
            end
        else
            @debug("No skill registered for $(enemy.enemyKey)")
        end
    end

    # Include specific enemy AI files here
    # Each file should call register_enemy_ai() to register itself
    include("enemies/BirdmanAI.jl")
    include("enemies/KingAI.jl")
    include("enemies/KnightAI.jl")
    include("enemies/PriestAI.jl")
    # include("SlimeAI.jl")
    # include("SnakeAI.jl")
    # ... add more as needed

    export AIContext, execute_advanced_pattern, execute_enemy_skill, register_enemy_ai, register_enemy_skill

end

