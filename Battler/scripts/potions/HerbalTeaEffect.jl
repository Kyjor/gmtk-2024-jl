module HerbalTeaEffectModule
    using JulGame
    using ..Scripts

    const HERBAL_TEA_HEAL = 10

    """
    Restore HERBAL_TEA_HEAL health (capped at max health). Returns the health actually gained.
    """
    function drink_herbal_tea!(user)::Int
        before = user.health
        user.health = min(user.maxHealth, user.health + HERBAL_TEA_HEAL)
        return user.health - before
    end

    herbal_tea_icon() = JulGame.UserGlobals["Module"].get_asset_path("potion", "herbaltea")

    """
    Execute herbal tea effect in battle - restore +10 health
    """
    function execute_herbal_tea_effect(battle_potion_manager, slot_index::Int)
        gained = drink_herbal_tea!(battle_potion_manager.user)
        deleteat!(battle_potion_manager.user.potions, slot_index)
        JulGame.UserGlobals["Module"].ObserverModule.notify(:healing_received, Dict(:battle_manager => battle_potion_manager.battleManager, :amount => gained, :icon => herbal_tea_icon()))
        @debug("Herbal tea effect executed - healed $gained")
    end

    export drink_herbal_tea!, execute_herbal_tea_effect, herbal_tea_icon

end
