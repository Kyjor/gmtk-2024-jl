module Scripts
    const _SCRIPTS_DIR = joinpath(@__DIR__, "..", "scripts")
    include(joinpath(_SCRIPTS_DIR, "utils", "MapFloorSystem.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "MapSpriteMask.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "MapFabZones.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "MapFabClusters.jl"))
    # Pattern piece subsystem (must load before Piece.jl / GridController consumers).
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternKinds.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternDebug.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternMatch.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternClearHelpers.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternRegistry.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternVisuals.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternAnimator.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternResolver.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternDefinitions.jl"))
    include(joinpath(_SCRIPTS_DIR, "pattern", "PatternHost.jl"))
    # Combo star HUD VFX (must load before ComboResponder).
    include(joinpath(_SCRIPTS_DIR, "utils", "NineSliceUI.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "ComboStars.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "Starfall.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "DieRollAnimator.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "PlayerFocusZoom.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "PlayerDeathAnimator.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "SpriteShadowEffect.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "CharacterPoseController.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "PlayerCombatantPopup.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "OverworldFeedback.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "TreasureChest.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "HeartFillFX.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "KeywordGlossary.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "SealedEnvelope.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "RunScaling.jl"))
    include(joinpath(_SCRIPTS_DIR, "utils", "ButtonJuice.jl"))
    # Movement reach rules (must load before InputHandler consumers).
    include(joinpath(_SCRIPTS_DIR, "movement", "MovementRules.jl"))
    # Load before other scripts (readdir order is not guaranteed); battle code references this module.
    _script_files = filter(contains(r".jl$"), readdir(_SCRIPTS_DIR; join=true))
    @time "battler scripts include" include.(_script_files)
    @time "battler scripts include globals" include(joinpath(_SCRIPTS_DIR, "utils", "Globals.jl"))
    export Globals
    ##using .Globals
end
# WARNING: This is a hack to make the scripts module work.
# It's not a good practice to do this, but it's the only way to make the scripts module work.
# The correct way to do this would be to use a proper module system, but that's a lot of work.
# So, we're just going to do this.
# TODO: Fix this.

