# Advanced AI for [ENEMY_NAME] enemy
# Copy this file and rename it to match your enemy (e.g., SlimeAI.jl, SnakeAI.jl)
# Then include it in EnemyPatterns.jl
using ..EnemyPatternsModule

"""
[ENEMY_NAME] advanced AI logic.
Makes intelligent decisions based on battle state.

Parameters:
- enemy: The current enemy instance
- context: AIContext containing:
  - battleManager: Full BattleManager reference
  - gridController: GridController reference
  - player: Player state (user)
  - allEnemies: Array of all living Enemy scripts
  - currentEnemy: The enemy making the decision
  - enemyComp: String of enemy composition
  - turnNumber: Current turn number

Returns: (intent::String, value::Int) or nothing for standard pattern

Available intents: "Attack", "Defend", "Heal", "Skill", "Burn", "Freeze"
"""
function ENEMYNAME_ai(enemy, context::EnemyPatternsModule.AIContext)
    # Example: Phase-based behavior
    health_percent = enemy.health / enemy.maxHealth
    
    # Example 1: Low health behavior
    if health_percent < 0.3
        # Consider healing or defending
        defend_amount = enemy.enemyData.average_defense
        @debug("[ENEMY_NAME] AI: Low health ($(health_percent*100)%), choosing to defend")
        return ("Defend", defend_amount)
    end
    
    # Example 2: Check player state
    if context.player.shield > 15
        # Player has high shield, maybe use a special attack
        attack_amount = enemy.enemyData.average_attack
        @debug("[ENEMY_NAME] AI: Player has high shield, attacking harder")
        return ("Attack", attack_amount + 2)
    end
    
    # Example 3: Multi-enemy coordination
    if length(context.allEnemies) > 1
        # Find weakest ally
        weakest_ally = nothing
        weakest_health_percent = 1.0
        
        for ally in context.allEnemies
            if ally.id != enemy.id  # Don't consider self
                ally_health_percent = ally.health / ally.maxHealth
                if ally_health_percent < weakest_health_percent
                    weakest_ally = ally
                    weakest_health_percent = ally_health_percent
                end
            end
        end
        
        # If ally is critical, consider supporting them
        if weakest_ally !== nothing && weakest_health_percent < 0.4
            @debug("[ENEMY_NAME] AI: Ally at $(weakest_health_percent*100)% health")
            # Could choose to defend them, heal them, or use skill
        end
    end
    
    # Example 4: Turn-based patterns
    if context.turnNumber <= 3
        # Early game behavior
        @debug("[ENEMY_NAME] AI: Early game, being aggressive")
    end
    
    # Example 5: Reactive to player statuses
    if context.player.burn > 0 || context.player.freeze > 0
        # Player is already afflicted, capitalize
        attack_amount = enemy.enemyData.average_attack
        @debug("[ENEMY_NAME] AI: Player afflicted, attacking")
        return ("Attack", attack_amount)
    end
    
    # No special condition met - use standard pattern
    return nothing
end

"""
[ENEMY_NAME] skill execution - implement special skill behavior.
This is called when the enemy performs a "Skill" intent.

Parameters:
- enemy: The current enemy instance
- gridController: GridController for manipulating the game board
"""
function ENEMYNAME_skill(enemy, gridController)
    @debug("[ENEMY_NAME] using skill")
    
    # Example skill implementations:
    
    # 1. Scramble the board
    # Scripts.GridControllerModule.randomly_rearrange_grid_pieces(gridController)
    
    # 2. Add specific pieces to the board
    # Scripts.GridControllerModule.add_piece_to_grid(gridController, piece_type, position)
    
    # 3. Remove pieces from the board
    # Scripts.GridControllerModule.remove_pieces_from_grid(gridController, piece_type)
    
    # 4. Apply effects (through battleManager if needed)
    # Access via enemy.battleManager
    
    # Implement your skill logic here
end

# Register this AI and skill with the system
# Replace ENEMY_[NAME] with your actual enemy key (e.g., ENEMY_SLIME, ENEMY_SNAKE)
EnemyPatternsModule.register_enemy_ai("ENEMY_[NAME]", ENEMYNAME_ai)
EnemyPatternsModule.register_enemy_skill("ENEMY_[NAME]", ENEMYNAME_skill)

