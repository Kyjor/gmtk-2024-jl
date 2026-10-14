module DiceEffectModule
    using JulGame
    using ..Scripts
    include("../utils/PotionsConstants.jl")

    """
    Execute the dice potion effect
    This rerolls the entire queue in battle
    """
    function execute_dice_effect(battle_potion_manager, slot_index::Int)
        @debug("Executing dice potion effect - rerolling queue")
        
        # Get QueueManager from parent scripts (script 6)
        queueManager = battle_potion_manager.parent.scripts[6]
        
        # Call handle_reroll to reroll the queue
        Scripts.QueueManagerModule.handle_reroll(queueManager, nothing)
        
        # Remove potion from inventory
        deleteat!(battle_potion_manager.user.potions, slot_index)
        
        @debug("Dice potion effect completed - queue rerolled")
    end

end
