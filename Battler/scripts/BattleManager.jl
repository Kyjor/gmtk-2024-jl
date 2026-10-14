module BattleManagerModule
using JulGame
using JulGame.EffectsModule
using JulGame.SceneManagement.SceneBuilderModule
using ..Scripts
using ..MapFloorSystemModule
@time "battlemanager include piecesconstants" include("utils/PiecesConstants.jl")
@time "battlemanager include easings" include("utils/Easings.jl")
@time "battlemanager include enemiesconstants" include("utils/EnemiesConstants.jl")
@time "battlemanager include kingscourtroster" include("boss/KingsCourtRoster.jl")
using .KingsCourtRosterModule
@time "battlemanager include battlestrings" include("localization/battle_strings.jl")
using .BattleStringsModule
include("ConfirmationDialog.jl")
using .ConfirmationDialogModule
@time "battlemanager include displaytext" include("utils/DisplayText.jl")
using .DisplayTextModule

const STYLE_VICTORY_CONTINUE_TEXT = [
    BevelEmbossEffect(; style=LAYER_INNER_BEVEL, size_px=16, soften=2.9999995f0, depth=62, angle=90.0, altitude=61.0, direction_up=true, contour_enabled=false, range_pct=100, contour_lut=identity_emboss_lut(), contour_antialiased=true, gloss_enabled=true, gloss_lut=identity_emboss_lut(), gloss_antialiased=false, texture_enabled=false, texture_path="", texture_tile=true, texture_scale=100, texture_phase_h_pct=0, texture_phase_v_pct=0, texture_align_with_layer=true, texture_depth=50.0, texture_invert=false, highlight_color=(255, 255, 255, 255), shadow_color=(35, 15, 35, 255), highlight_opacity=166, shadow_opacity=140, highlight_blend=BB_NORMAL, shadow_blend=BB_OVERLAY, intensity=1.0),
    RoughEdgeEffect(; amount=3, seed=42001, erosion=true)
]

const battleStates = Dict(
    :playerTurn => 1,
    :switchingItems => 2,
    :searchingForMatches => 3,
    :replaceItems => 4,
    :processTurn => 5,
    :playerAction => 6,
    :enemyTurn => 7,
    :animatingIntents => 8,
    :battleEnd => 9
)

const ENEMY_PIXELS_PER_UNIT = Dict(
    ENEMY_SNAKE => 0,
    ENEMY_SLIME => 0,
    ENEMY_BIRDMAN => 100,
    ENEMY_PRIEST => 0,
    ENEMY_KNIGHT => 75,
    ENEMY_KING => 0,
    ENEMY_CROWMAN => 0,
    ENEMY_CROW => 0,
    ENEMY_HAND => 0,
    ENEMY_KNIFEHAND => 0,
    ENEMY_SKELEBAT => 0,
    ENEMY_SCYTHEGHOST => 0,
    ENEMY_HAPPYGHOST => 0,
    ENEMY_CYBERSKELETONSHADOW => 0,
    ENEMY_SADGHOST => 0,
    ENEMY_MAGICSKELETONSHADOW => 0,
)


const BATTLE_FORMATIONS = Dict(
    ENEMY_SNAKE => [
        (position=Math.Vector3f(14.85, 4.75, 0.0), heartPosition=Math.Vector3f(15.0, 9.5, 0.0), intentPosition=Math.Vector3f(14.8, -0.5, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SNAKE], selectEnemy=true)
    ],
    "$(ENEMY_SLIME),$(ENEMY_SLIME),$(ENEMY_SLIME)" => [
        (position=Math.Vector3f(13.2, 4.0, 0.0), heartPosition=Math.Vector3f(12.0, 5.2, 0.0), intentPosition=Math.Vector3f(13.0, 1.0, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SLIME], selectEnemy=false),
        (position=Math.Vector3f(15.0, 5.0, 0.0), heartPosition=Math.Vector3f(14.75, 6.25, 0.0), intentPosition=Math.Vector3f(14.75, 1.0, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SLIME], selectEnemy=true),
        (position=Math.Vector3f(16.7, 4.0, 0.0), heartPosition=Math.Vector3f(17.5, 5.2, 0.0), intentPosition=Math.Vector3f(16.7, 1.0, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SLIME], selectEnemy=false)
    ],
    "$(ENEMY_BIRDMAN)" => [
        (position=Math.Vector3f(15.2, 4.6, 0.0), heartPosition=Math.Vector3f(13.5, 0.0, 0.0), intentPosition=Math.Vector3f(15.6, -0.6, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_BIRDMAN], selectEnemy=true),
    ],
    "ENEMY_SLIME,WILDCARD,ENEMY_SLIME" => [
        (position=Math.Vector3f(13.1, 4.0, 0.0), heartPosition=Math.Vector3f(12.0, 5.2, 0.0), intentPosition=Math.Vector3f(13.0, 1.0, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SLIME], selectEnemy=false),
        # Middle enemy resolved at runtime; PPU comes from ENEMY_PIXELS_PER_UNIT[enemy.key] in create_and_place_enemy
        (position=Math.Vector3f(15.0, 5.1, 0.0), heartPosition=Math.Vector3f(15.0, 7.0, 0.0), intentPosition=Math.Vector3f(15.0, 1.0, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_BIRDMAN], selectEnemy=true),
        (position=Math.Vector3f(16.9, 4.0, 0.0), heartPosition=Math.Vector3f(17.9, 5.2, 0.0), intentPosition=Math.Vector3f(17.0, 1.0, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SLIME], selectEnemy=false),
    ],
    # King's Court
    "$(ENEMY_PRIEST),$(ENEMY_KING),$(ENEMY_KNIGHT)" => [
        (position=Math.Vector3f(16.9, 7.9, 0.0), heartPosition=Math.Vector3f(17.9, 9.8, 0.0), intentPosition=Math.Vector3f(16.3, 9.4, 0.0), layer=2, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_PRIEST], selectEnemy=true),
        (position=Math.Vector3f(16.0, 1.65, 0.0), heartPosition=Math.Vector3f(14.85, -0.35, 0.0), intentPosition=Math.Vector3f(13.4, -0.95, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_KING], selectEnemy=true),
        (position=Math.Vector3f(13.2, 6.0, 0.0), heartPosition=Math.Vector3f(14.25, 9.15, 0.0), intentPosition=Math.Vector3f(12.4, 8.9, 0.0), layer=2, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_KNIGHT], selectEnemy=true),
    ],
    "$(ENEMY_KNIGHT)" => [
        (position=Math.Vector3f(14.25, 4.65, 0.0), heartPosition=Math.Vector3f(13.0, 2.3, 0.0), intentPosition=Math.Vector3f(15.75, -1.0, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_KNIGHT], selectEnemy=true),
    ],
    "$(ENEMY_PRIEST)" => [
        (position=Math.Vector3f(14.5, 5.15, 0.0), heartPosition=Math.Vector3f(15.0, 8.0, 0.0), intentPosition=Math.Vector3f(15.35, 1.3, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_PRIEST], selectEnemy=true),
    ],
    "$(ENEMY_HAND),$(ENEMY_KNIFEHAND)" => [
        (position=Math.Vector3f(13.0, 6.85, 0.0), heartPosition=Math.Vector3f(12.7, 10.1, 0.0), intentPosition=Math.Vector3f(14.4, 9.7, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_HAND], selectEnemy=true),
        (position=Math.Vector3f(16.5, 4.6, 0.0), heartPosition=Math.Vector3f(16.3, 8.0, 0.0), intentPosition=Math.Vector3f(18.0, 7.5, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_KNIFEHAND], selectEnemy=true),
    ],
    "$(ENEMY_SCYTHEGHOST),$(ENEMY_HAPPYGHOST),$(ENEMY_SADGHOST)" => [
        (position=Math.Vector3f(16.2, 2.9, 0.0), heartPosition=Math.Vector3f(17.2, 3.6, 0.0), intentPosition=Math.Vector3f(16.8, -0.6, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SCYTHEGHOST], selectEnemy=false),
        (position=Math.Vector3f(14.8, 6.2, 0.0), heartPosition=Math.Vector3f(14.8, 8.95, 0.0), intentPosition=Math.Vector3f(17.2, 7.4, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_HAPPYGHOST], selectEnemy=true),
        (position=Math.Vector3f(13.2, 3.65, 0.0), heartPosition=Math.Vector3f(11.7, 3.45, 0.0), intentPosition=Math.Vector3f(12.9, 0.3, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SADGHOST], selectEnemy=false),
    ],
    "$(ENEMY_CROWMAN),$(ENEMY_CROW),$(ENEMY_CROW),$(ENEMY_CROW)" => [
        (position=Math.Vector3f(16.5, 4.65, 0.0), heartPosition=Math.Vector3f(15.8, 0.1, 0.0), intentPosition=Math.Vector3f(17.75, -0.3, 0.0), layer=2, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_CROWMAN], selectEnemy=true),
        (position=Math.Vector3f(12.5, 1.1, 0.0), heartPosition=Math.Vector3f(11.85, -0.7, 0.0), intentPosition=Math.Vector3f(13.5, -1.0, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_CROW], selectEnemy=false),
        (position=Math.Vector3f(12.35, 5.0, 0.0), heartPosition=Math.Vector3f(11.6, 3.6, 0.0), intentPosition=Math.Vector3f(13.25, 3.25, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_CROW], selectEnemy=false),
        (position=Math.Vector3f(12.5, 9.1, 0.0), heartPosition=Math.Vector3f(11.85, 7.35, 0.0), intentPosition=Math.Vector3f(13.5, 7.0, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_CROW], selectEnemy=false),
    ],
    "$(ENEMY_SKELEBAT),$(ENEMY_SKELEBAT)" => [
        # At least one slot must have selectEnemy=true, or selectedEnemy never gets set during spawn.
        (position=Math.Vector3f(13.4, -0.25, 0.0), heartPosition=Math.Vector3f(12.6, 2.35, 0.0), intentPosition=Math.Vector3f(14.5, 1.0, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SKELEBAT], selectEnemy=true),
        (position=Math.Vector3f(15.5, 6.0, 0.0), heartPosition=Math.Vector3f(15.2, 8.1, 0.0), intentPosition=Math.Vector3f(17.0, 7.85, 0.0), layer=1, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_SKELEBAT], selectEnemy=false),
    ],
    "$(ENEMY_MAGICSKELETONSHADOW)" => [
        (position=Math.Vector3f(14.5, 5.2, 0.0), heartPosition=Math.Vector3f(13.4, 1.2, 0.0), intentPosition=Math.Vector3f(15.5, 0.9, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_MAGICSKELETONSHADOW], selectEnemy=true),
    ],
    "$(ENEMY_CYBERSKELETONSHADOW)" => [
        (position=Math.Vector3f(14.5, 5.2, 0.0), heartPosition=Math.Vector3f(13.4, 1.2, 0.0), intentPosition=Math.Vector3f(15.5, 0.9, 0.0), layer=0, pixelsPerUnit=ENEMY_PIXELS_PER_UNIT[ENEMY_CYBERSKELETONSHADOW], selectEnemy=true),
    ],
)

function default_formation(enemy_count)
    formation = []
    for i in 1:enemy_count
        push!(formation, (position=Math.Vector3f(15.0, 5.0, 0.0), heartPosition=Math.Vector3f(15.0, 8.0, 0.0), intentPosition=Math.Vector3f(15.0, 0.0, 0.0), layer=1, pixelsPerUnit=0, selectEnemy=true))
    end
    return formation
end

BattleManagerInstance = nothing

# Holds the previous battle's global observer callback so we do not stack duplicates on re-entry.
const _battle_manager_observer_ref = Ref{Union{Nothing, Function}}(nothing)

mutable struct BattleManager <: Script
    parent
    intent::String
    battleStates::Any
    currentState
    # Attributes
    enemies
    selectedEnemy::Any
    selectEnemyIndicator::Any
    # Dim clone of SelectionHeart while hovering another enemy's heart (player turn).
    selectEnemyPreview::Any
    # SelectionHeart clones on every other living enemy while the aimed match hits all of them.
    selectEnemyAoePreviews::Vector{Any}

    # Counts
    moveCount::Int64
    countDict::Dict{String,Int}

    # Scripts
    gameManager

    # Textboxes
    battleUpdatesText

    # Timers
    actionTimeLimit::Float64
    actionElapsedTime::Float64

    # entities
    persistentStateManager
    user
    treasureDisplayManager

    # Victory screen
    isPlayerDead::Bool

    # Reward system
    rewardManager

    # Grid controller
    gridController

    # Animation system
    pendingIntents::Vector{Tuple{String,Int}}  # Store intents to apply after animations
    activeAnimations
    animationCoroutine  # Coroutine for running animations

    startingMoveCount::Int64

    # Enemy shake system
    enemyShakeActive::Bool
    enemyShakeElapsed::Float64
    enemyShakeDuration::Float64
    enemyShakeIntensity::Float64
    enemyOriginalPosition::Math.Vector3f

    battlePotionManager
    #abilityManager
    battleEnemyManager
    transitionManager

    # Empty Locket: Track first match type each turn
    firstMatchTypeThisTurn::Union{String, Nothing}

    # King's Court boss: advanced AI for King/Knight/Priest only when roster matches trio at battle start
    kingsCourtMode::Bool
    kingsCourtSummonDelay::Int  # remaining intent cycles before King may revive a minion

    # Phase (radians) for SelectionHeart vertical bob
    selectionHeartBobPhase::Float64

    # Post-run screen (boss / defeat)
    postRunWinAnalyticsSent::Bool
    postRunSnapshotFilled::Bool

    didClearEverything::Bool

    # Enemy attack rounds completed this battle (0 on the opening telegraph).
    battleTurnNumber::Int

    # Player vulnerable when the enemy turn began; stacks applied during the turn skip its decay.
    vulnerableAtEnemyTurnStart::Int

    confirmationDialog

    function BattleManager()
        this = new()
        global BattleManagerInstance = this

        this.startingMoveCount = 3
        this.moveCount = this.startingMoveCount
        this.intent = PIECE_SWORD
        this.actionTimeLimit = 0.4
        this.actionElapsedTime = 0.0
        this.battleStates = battleStates
        this.isPlayerDead = false
        this.firstMatchTypeThisTurn = nothing
        this.vulnerableAtEnemyTurnStart = 0
        this.kingsCourtMode = false
        this.kingsCourtSummonDelay = 1
        this.selectionHeartBobPhase = 0.0
        this.postRunWinAnalyticsSent = false
        this.postRunSnapshotFilled = false
        this.didClearEverything = false
        this.battleTurnNumber = 0
        this.selectEnemyAoePreviews = Any[]
        this.confirmationDialog = ConfirmationDialogModule.ConfirmationDialog()
        # Initialize animation system
        this.pendingIntents = Tuple{String,Int}[]
        this.activeAnimations = []
        this.animationCoroutine = nothing

        # Initialize enemy shake system
        this.enemyShakeActive = false
        this.enemyShakeElapsed = 0.0
        this.enemyShakeDuration = 0.25
        this.enemyShakeIntensity = 0.1
        this.enemyOriginalPosition = Math.Vector3f(0.0, 0.0, 0.0)

        this.enemies = []
        # create_and_place_enemy only assigns selectedEnemy when formation.selectEnemy is true.
        # If every slot is false, selectedEnemy stays nothing until refresh_selected_enemy_indicator!.
        this.selectedEnemy = nothing

        return this
    end
end

function Base.setproperty!(this::BattleManager, prop::Symbol, val)
    if prop == :currentState && isdefined(this, :currentState) && this.currentState == this.battleStates[:battleEnd]
        @debug "Setting current state to $(val)"
        return
    end
    Base.setfield!(this, prop, val)
end

function create_and_place_enemy(this, enemy, enemyPrefab, enemy_count, comp)
    formation = nothing
    try
        formation = BATTLE_FORMATIONS[comp][enemy_count]
    catch e
        formation = default_formation(enemy_count)
        @error "Error getting formation: $(e)"
        Base.show_backtrace(stderr, catch_backtrace())
    end
    enemyEntity = JulGame.duplicate(enemyPrefab)
    enemyEntity.isActive = true
    push!(enemyEntity.scripts, Scripts.EnemyModule.Enemy(formation.heartPosition, formation.intentPosition))
    script = enemyEntity.scripts[1]
    script.parent = enemyEntity
    script.enemyKey = enemy.key
    script.maxHealth = enemy.maxHealth
    script.health = enemy.health
    script.attack = enemy.attack
    script.defense = enemy.defense
    script.gold = enemy.gold
    enemyEntity.transform.position = formation.position
    enemyEntity.sprite.layer = formation.layer
    JulGame.initialize(script, enemy, formation.selectEnemy)
    # Dict is source of truth when enemy.key is known (fixes wildcard + keeps PPU after sprite load)
    enemyEntity.sprite.pixelsPerUnit = get(ENEMY_PIXELS_PER_UNIT, enemy.key, formation.pixelsPerUnit)
    if formation.selectEnemy
        this.selectedEnemy = script
    elseif this.selectedEnemy === nothing && script.health > 0
        # Fallback: formation had no selectEnemy=true — first living spawn becomes target.
        @debug "BattleManager: selectedEnemy fallback to first spawn (comp=$(comp), slot=$(enemy_count))"
        this.selectedEnemy = script
    end
    push!(this.enemies, enemyEntity)
end

"""Set selectedEnemy to the first living enemy and sync the selection heart. Call after spawn and when an enemy dies."""
function refresh_selected_enemy_indicator!(this::BattleManager)
    if this.selectEnemyIndicator === nothing
        enemy_found = false
        for enemy in this.enemies
            if enemy.scripts[1].health > 0
                this.selectedEnemy = enemy.scripts[1]
                enemy_found = true
                break
            end
        end
        if !enemy_found
            this.selectedEnemy = nothing
        end
        return
    end
    enemy_found = false
    for enemy in this.enemies
        if enemy.scripts[1].health > 0
            this.selectedEnemy = enemy.scripts[1]
            es = this.selectedEnemy
            base = es.healthHeart !== nothing ? es.healthHeart.transform.position : es.heartPosition
            bob = selection_heart_bob_y(this)
            this.selectEnemyIndicator.transform.position = Math.Vector3f(base.x, base.y + bob, base.z)
            this.selectEnemyIndicator.isActive = true
            enemy_found = true
            break
        end
    end
    if !enemy_found
        this.selectedEnemy = nothing
        this.selectEnemyIndicator.isActive = false
    end
end

include("boss/KingsCourtSummon.jl")

function JulGame.initialize(this::BattleManager)
    @debug "Initializing BattleManager"
    this.postRunWinAnalyticsSent = false
    this.postRunSnapshotFilled = false
    try
        Scripts.PostRunScreenModule.clear_run_end_snapshot!()
    catch e
        @debug "clear_run_end_snapshot: $e"
    end
    # start timer
    timer = time_ns()
    Scripts.ConsoleIntegrationModule.initialize_console_for_game()
    this.currentState = this.battleStates[:playerTurn]
    this.countDict = Dict{String,Int}()
    this.gameManager = this.parent.scripts[1]
    this.battleUpdatesText = JulGame.SceneModule.get_ui_element_by_name(MAIN.scene, "Battle Updates")
    enemyPrefab = JulGame.SceneModule.get_entity_by_id("7457da04-2705-4391-b297-f77e5dd46e08")
    this.selectEnemyIndicator = JulGame.SceneModule.get_entity_by_id("8dbac0a0-7517-4fbc-83c6-3bcc16c48100")
    this.selectEnemyPreview = nothing
    try
        if this.selectEnemyIndicator !== nothing
            pv = JulGame.duplicate(this.selectEnemyIndicator)
            pv.name = "SelectionHeartPreview"
            pv.isActive = false
            if pv.sprite !== nothing
                base_layer = this.selectEnemyIndicator.sprite.layer
                pv.sprite.layer = max(0, base_layer - 1)
                pv.sprite.color = (255, 255, 255, 105)
            end
            this.selectEnemyPreview = pv
        end
    catch e
        @debug "Could not create selectEnemyPreview: $(e)"
        this.selectEnemyPreview = nothing
    end
    this.gridController = this.parent.scripts[3]
    this.treasureDisplayManager = this.parent.scripts[8]
    this.battlePotionManager = this.parent.scripts[9]
    #this.abilityManager = this.parent.scripts[11]  # AbilityManager
    this.battleEnemyManager = this.parent.scripts[13]  # BattleEnemyManager
    
    # Initialize reward manager
    this.rewardManager = Scripts.RewardManagerModule.RewardManager()
    this.rewardManager.parent = this.parent
    JulGame.initialize(this.rewardManager)
    # Add to parent's scripts so update function gets called
    push!(this.parent.scripts, this.rewardManager)

    # Initialize feedback system observer
    BattleJuiceModule.reset!()
    BattleJuiceModule.initialize_juice_observer!()
    @debug "Battle feedback system initialized"

    globals = JulGame.UserGlobals["Module"]
    this.user = globals.get_user_data()
    this.persistentStateManager = globals.get_data_manager().persistent_state_manager
    globals.UserModule.initialize(this.user)
    globals.get_data_manager().current_battle_manager = this

    @debug "Current run state: $(this.persistentStateManager)"

    # Stake: Decrease Max HP by 90% when acquired (applied once).
    if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_STAKE) && !this.user.stake_applied
        original_max = this.user.maxHealth
        new_max = max(1, floor(Int, original_max * 0.1))
        this.user.maxHealth = new_max
        this.user.health = min(this.user.health, new_max)
        this.user.stake_applied = true
        @debug "Stake effect applied on acquisition: Max HP reduced from $(original_max) to $(new_max)"
    end

    if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_WHITEPAWN)
        this.moveCount = this.startingMoveCount + 1
    end
    prev_obs = _battle_manager_observer_ref[]
    if prev_obs !== nothing
        try
            globals.ObserverModule.remove_observer(globals.get_observer_data(), prev_obs)
        catch e
            @debug "BattleManager: could not remove previous battle observer: $(e)"
        end
    end
    obs = (event, data) -> on_notify(this, event, data)
    _battle_manager_observer_ref[] = obs
    globals.ObserverModule.add_observer(globals.get_observer_data(), obs)
    # Set rich presence with current position if available
    if this.persistentStateManager.currentLevel > 0
        globals.SteamModule.set_rich_presence_with_position(globals.get_steam_data(), "FightingAnEnemy", this.persistentStateManager.currentRoom, this.persistentStateManager.currentFloor)
    else
        globals.SteamModule.set_rich_presence(globals.get_steam_data(), "FightingAnEnemy")
    end

    this.battleTurnNumber = 0
    # Apply enemy stats from persistent state manager
    if this.persistentStateManager.currentEnemies !== nothing
        enemy_count = 1
        # join the enemy keys with a comma
        @debug("Current enemies: $(this.persistentStateManager.currentEnemies)")
        enemy_keys = [ENEMY_SNAKE]
        try
            enemy_keys = [enemy.key for enemy in this.persistentStateManager.currentEnemies]
        catch e
            @error "Error getting enemy keys: $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end
        enemy_comp = join(enemy_keys, ",")
        try
            Scripts.RunScalingModule.register_encounter_enemies!(enemy_keys)
        catch e
            @error "Error registering encounter enemies: $(e)"
        end
        try
            globals.RunRecorderModule.battle_start!(enemy_keys)
        catch e
            @error "Error recording battle start: $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end
        for enemy in this.persistentStateManager.currentEnemies
            create_and_place_enemy(this, enemy, enemyPrefab, enemy_count, enemy_comp)
            enemy_count += 1
        end
        this.kingsCourtMode = KingsCourtRosterModule.is_kings_court_startup(this.persistentStateManager.currentEnemies)
        this.kingsCourtSummonDelay = 1
        # Fallback if no formation slot used selectEnemy=true (should not happen for defined comps).
        if this.selectedEnemy === nothing
            refresh_selected_enemy_indicator!(this)
        end
    else
        @error("No enemies found in currentEnemies")
    end

    if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_BLESSEDAMULET)
        this.user.shield += 10
    end

    if this.user.selectedCharacter == "CHARACTER_DEMOLITIONIST"
        globals.UserModule.add_potion!(this.user, "POTION_GIGABOMB")
    end

    # Dodge and the Shadow Cloak bonus move are per battle.
    this.user.dodge_chance = 0
    this.user.reflect_chance = 0
    this.user.shadowCloakUsed = false

    # Set first attack flag for Warrior Helmet
    if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_WARRIORHELMET)
        this.user.first_attack_bonus = true
        @debug "Warrior Helmet effect ready, first attack will deal +2 damage"
    end

    try
        this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
    catch e
        @error "SceneTransitionManager not found: $e"
        Base.show_backtrace(stderr, catch_backtrace())
    end
    @debug "BattleManager initialized in $((time_ns() - timer) / 1e9) seconds"
end

function process_turn(this::BattleManager)
    globals = JulGame.UserGlobals["Module"]
    skip_move_cost = globals.PiecesModule.empty_locket_dodge_turn(this)
    if !skip_move_cost
        this.moveCount = max(0, this.moveCount - 1)
    end
    @debug "Setting move count to $(this.moveCount) (skip_move_cost=$(skip_move_cost))"

    # Leave :processTurn immediately so a later throw can't re-enter and go negative
    if this.moveCount == 0
        this.currentState = this.battleStates[:playerAction]
        Scripts.SealedEnvelopeModule.end_turn!()
        this.user.luck = max(0, (this.user.luck - 10))
        # Do NOT clear dodge_chance here — it must survive until the enemy attack resolves.
        if this.user.weaken > 0
            this.user.weaken -= 1
        end
        this.firstMatchTypeThisTurn = nothing
        this.countDict = Dict{String,Int}()
        BattleJuiceModule.turn_transition_flash!()
    elseif this.currentState != this.battleStates[:battleEnd]
        this.currentState = this.battleStates[:playerTurn]
    end

    Scripts.GameManagerModule.update_queue_after_move(this.gameManager)

    try
        Globals.AnalyticsModule.track_action(:turn_taken)
    catch e
        @debug "Could not track turn: $e"
    end

    player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
    if player_entity !== nothing
        BattleJuiceModule.scale_pulse!(player_entity; intensity=1.05, duration=0.2)
    end
end

# New function to apply individual intent effects immediately when matches occur
function apply_single_intent(this::BattleManager, intent::String, actionCount::Int)
    #@debug("Applying single intent: $(intent) with count: $(actionCount)")
    globals = JulGame.UserGlobals["Module"]
    try
        ActionResultDisplayModule.set_source!(intent, actionCount)
        globals.PiecesModule.apply_intent(intent, this, actionCount)
        @debug "Applied intent: $(intent) with count: $(actionCount)"
    catch e
        @error "Error applying intent: $(first(string(e), 1000))"
        Base.show_backtrace(stderr, catch_backtrace())
    finally
        ActionResultDisplayModule.clear_source!()
    end
end

    function enemy_defeated(this)
        try
            enemy_count = length(this.persistentStateManager.currentEnemies)
            Globals.AnalyticsModule.track_action(:enemy_killed, enemy_count)
            JulGame.UserGlobals["Module"].AchievementTrackerModule.track_stat!("battles_won")
        catch e
            @debug "Could not track enemy kill: $e"
        end

        if this.persistentStateManager.currentEvent !== nothing && this.persistentStateManager.currentEvent.category == "boss"
            @debug("Boss defeated! Checking for special potion effects...")
            try
                Scripts.BattlePotionManagerModule.PotionEffectsModule.handle_boss_defeat_potions(this.battlePotionManager)
            catch e
                @error "Error handling boss defeat potions: $(e)"
            end
        end

        this.persistentStateManager.isFloorComplete = true
        if this.persistentStateManager.currentEvent !== nothing && this.persistentStateManager.currentEvent.category == "enemy"
            this.persistentStateManager.regularMapBattlesWonThisRun += 1
        end
        @debug("Current level is $(this.persistentStateManager.currentLevel) after enemy death")

        # Bosses and elites get the reward screen too; their rarity curve is shifted
        # upward inside RewardPackages rather than skipping the offer entirely.
        if !Scripts.RewardManagerModule.is_showing(this.rewardManager)
            try
                Scripts.RewardManagerModule.roll_rewards!(this.rewardManager, sum(enemy.gold for enemy in this.persistentStateManager.currentEnemies))
            catch e
                @error "Error generating rewards: $(e)"
                Base.show_backtrace(stderr, catch_backtrace())
            end
        else
            @debug("Rewards already rolled at battle start")
        end

        @debug "Showing victory screen"
        this.currentState = this.battleStates[:battleEnd]
        this.user.shield = 0

        # Cascade may never reach a no-match tick once we leave match states.
        try
            JulGame.UserGlobals["Module"].ObserverModule.notify(:combo_ended)
        catch e
            @debug "Could not end combo on victory: $e"
        end

        if haskey(this.persistentStateManager.playerData, "heal_blocked")
            delete!(this.persistentStateManager.playerData, "heal_blocked")
            @debug "Heal block from devil's bargain has expired"
        end
        JulGame.UserGlobals["Module"].RunRecorderModule.battle_end!("won")
        BattleJuiceModule.victory_screen!()
    end


function JulGame.on_shutdown(this::BattleManager)
end

function selection_heart_bob_y(bm::BattleManager)::Float32
    return Float32(0.078 * sin(bm.selectionHeartBobPhase))
end

function JulGame.update(this::BattleManager, deltaTime)
    this.selectionHeartBobPhase += Float64(deltaTime) * 1.75

    BattleJuiceModule.update(deltaTime)

    globals = JulGame.UserGlobals["Module"]
    globals.UserModule.update(this.user, deltaTime)

    # Display victory screen if enemy is defeated
    if this.currentState == this.battleStates[:battleEnd]
        display_victory_screen(this)
        if this.confirmationDialog !== nothing
            ConfirmationDialogModule.update(this.confirmationDialog, deltaTime)
        end
    end

    all_enemies_dead = true
    for enemy in this.enemies
        if enemy.scripts[1].health > 0
            all_enemies_dead = false
            break
        end
    end
    if all_enemies_dead && this.currentState != this.battleStates[:battleEnd]
        @info "All enemies dead, triggering enemy defeat"
        enemy_defeated(this)
    end
end

function process_enemy_turn(this::BattleManager)
    globals = JulGame.UserGlobals["Module"]
    this.battleTurnNumber += 1
    this.currentState = this.battleStates[:animatingIntents]
    Scripts.SealedEnvelopeModule.end_turn!()

    BattleJuiceModule.enemy_turn_flash!()

    # Poison weakens the poisoned side's own attacks, so it ticks down after the player has attacked
    # (enemies tick after acting) — not right after the enemy turn that applied it.
    if this.user.poison > 0
        this.user.poison -= 1
    end
    # Freeze already cost the player a move this turn.
    if this.user.freeze > 0
        this.user.freeze -= 1
    end
    this.vulnerableAtEnemyTurnStart = this.user.vulnerable

    # Reset enemy shields before their turn
    for enemy in this.enemies
        enemy.scripts[1].shield = 0
    end

    # Start animated enemy turn sequence
    EnemyTurnAnimatorModule.start_enemy_turn_animations(this, () -> on_enemy_turn_complete(this))

    @debug "Enemy turn animations started"
end

# Called when all enemy animations are complete
function on_enemy_turn_complete(this::BattleManager)
    globals = JulGame.UserGlobals["Module"]

    # Check if battle ended during animations
    if this.currentState == this.battleStates[:battleEnd]
        return
    end

    # Apply ongoing burn damage to enemies
    for enemy in this.enemies
        currentEnemy = enemy.scripts[1]
        if currentEnemy.burn > 0
            if !globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_LIGHTER)
                currentEnemy.burn -= 1
                @debug "Lighter effect not applied, decreasing burn duration by 1"
            end
            burn_damage = 1
            if Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_DRAGONSCALE)
                burn_damage *= 2
                @debug "Dragon Scale effect applied, doubling burn damage"
            end

            take_damage(this, currentEnemy, burn_damage)
        end
    end

    # Apply shock damage: each shocked enemy deals 1 damage per shock stack to all other enemies
    for shocked_enemy_entity in this.enemies
        shocked_enemy = shocked_enemy_entity.scripts[1]
        if shocked_enemy.shock > 0 && shocked_enemy.health > 0
            shock_damage = shocked_enemy.shock  # 1 damage per stack
            
            # Deal damage to all OTHER enemies
            for target_enemy_entity in this.enemies
                target_enemy = target_enemy_entity.scripts[1]
                if target_enemy !== shocked_enemy && target_enemy.health > 0
                    @debug "Shock: $(shocked_enemy.shock) stacks from one enemy dealing $(shock_damage) damage to another enemy"
                    
                    take_damage(this, target_enemy, shock_damage)
                    try
                        BattleJuiceModule.shock_arc!(target_enemy_entity)
                    catch
                    end
                end
            end
            
            # Decay shock
            shocked_enemy.shock -= 1
            @debug "Enemy shock decayed to $(shocked_enemy.shock)"
        end
    end

    this.user.shield = 0

    # Decrease player status effects
    if this.user.burn > 0
        this.user.burn -= 1
        burn_damage = 1

        player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
        take_damage(this, this.user, burn_damage; skip_battle_damage_feedback=false)
        @debug "Player takes $(burn_damage) ongoing burn damage, $(this.user.burn) turns remaining"
        if this.currentState == this.battleStates[:battleEnd]
            return
        end
    end
    if this.user.vulnerable > 0 && this.vulnerableAtEnemyTurnStart > 0
        this.user.vulnerable -= 1
    end
    if this.user.shock > 0
        this.user.shock -= 1
    end

    # Stake: At the end of each turn, deal damage equal to your current HP.
    if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_STAKE) &&
       this.user.health > 0
        # Deal damage equal to current HP to a random living enemy
        alive_enemies = [e for e in this.enemies if e.scripts[1].health > 0]
        if !isempty(alive_enemies)
            stake_damage = this.user.health
            target_entity = rand(alive_enemies)
            target = target_entity.scripts[1]
            @debug "Stake end-of-turn effect: dealing $(stake_damage) damage to random enemy $(target.enemyKey)"
            take_damage(this, target, stake_damage)
        end
    end

    # Reset Empty Locket first match type for new player turn
    this.firstMatchTypeThisTurn = nothing

    # Return to enemy turn state (GameManager will transition to player turn)
    this.currentState = this.battleStates[:enemyTurn]
    @debug "Enemy turn complete, transitioning back to player turn"
end

include("utils/ActionResultDisplay.jl")
include("utils/BattleFeedbackSystem.jl")
include("utils/BattleFeedbackPresets.jl")
include("utils/BattleJuice.jl")
include("utils/BattleAnimations.jl")
include("utils/EnemyTurnAnimator.jl")
using .ActionResultDisplayModule
using .BattleFeedbackSystemModule
using .BattleFeedbackPresetsModule
using .BattleJuiceModule
using .EnemyTurnAnimatorModule

"""Ancient Shield + Angel Tears when the hit would actually kill after shield/vulnerable."""
function try_player_death_preventions!(this::BattleManager, damage::Int)::Bool
    globals = JulGame.UserGlobals["Module"]
    death_prevented = false
    if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_ANCIENTSHIELD) &&
       !this.user.ancient_shield_used
        this.user.health = min(this.user.maxHealth, 10)
        this.user.shield = clamp(this.user.shield + 10, 0, this.user.maxShield)
        this.user.ancient_shield_used = true
        death_prevented = true
        globals.RunRecorderModule.note_death_prevented!("TREASURE_ANCIENTSHIELD")
        @debug "Ancient Shield effect applied, surviving with 10 HP and gaining 10 shield"
        DisplayTextModule.display_text(
            "ancient_shield_text",
            "ANCIENT SHIELD ACTIVATED!";
            fontSize=32,
            anchor=:center,
            lifetime=2000,
            color=(255, 215, 0, 255)
        )
    end
    if !death_prevented
        try
            if Scripts.BattlePotionManagerModule.PotionEffectsModule.handle_death_prevention_potions(this.battlePotionManager)
                death_prevented = true
                globals.RunRecorderModule.note_death_prevented!("angel_tears")
                @debug "Angel Tears effect applied, revived with 25% health"
                DisplayTextModule.display_text(
                    "angel_tears_text",
                    BattleStringsModule.BATTLE_STRINGS[:angel_tears_activated];
                    fontSize=32,
                    anchor=:center,
                    lifetime=2000,
                    color=(255, 255, 255, 255)
                )
            end
        catch e
            @error "Error handling Angel Tears death prevention: $(e)"
        end
    end
    return death_prevented
end

# Clears all run state (rewards, persistent state, user) and hides battle-only visuals.
# Run-end UI reads from the snapshot captured prior to calling this, so it stays valid.
function _finalize_run!(this::BattleManager; context::String = "run finalize")
    globals = JulGame.UserGlobals["Module"]
    try
        @debug "Deleting run save on $(context)"
        globals.SaveManagerModule.delete_run_save!()
    catch e
        @error "Could not delete run save on $(context): $(e)"
    end
    try
        @debug "Clearing rewards on $(context)"
        Scripts.RewardManagerModule.reset_rewards(this.rewardManager)
    catch e
        @error "Could not clear rewards on $(context): $(e)"
    end
    try
        @debug "Resetting persistent state on $(context)"
        globals.PersistentStateManagerModule.reset_for_new_run(this.persistentStateManager)
    catch e
        @error "Error resetting persistent state on $(context): $(e)"
    end
        @debug "Resetting player on $(context)"
        globals.UserModule.reset_player(this.user)
    # Post-run UI shows stats from snapshot; hide world battle avatar so reset HP (e.g. 20) isn't shown on the player heart/sprite.
    try
        u = this.user
        if u.healthHeart !== nothing && hasproperty(u.healthHeart, :isActive)
            u.healthHeart.isActive = false
        end
        if u.healthHeartBackground !== nothing && hasproperty(u.healthHeartBackground, :isActive)
            u.healthHeartBackground.isActive = false
        end
        if u.playerEntity !== nothing && hasproperty(u.playerEntity, :isActive)
            u.playerEntity.isActive = false
        end
        if u.shieldUI !== nothing && hasproperty(u.shieldUI, :isActive)
            u.shieldUI.isActive = false
        end
    catch e
        @debug "Could not hide player battle visuals on $(context): $(e)"
    end
end

function trigger_player_defeat!(this::BattleManager)
    @debug "trigger_player_defeat! called"
    if this.currentState == this.battleStates[:battleEnd] || this.isPlayerDead
        return
    end
    if this.user.health > 0
        return
    end
    @debug "Player is dead"
    this.isPlayerDead = true
    globals = JulGame.UserGlobals["Module"]
    try
        Scripts.PostRunScreenModule.capture_run_end_snapshot!(this.user, this.persistentStateManager, false)
    catch e
        @error "Error capturing run end snapshot: $(e)"
    end
    try
        globals.track_run_end(; run_won = false)
    catch e
        @error "Error tracking run end: $(e)"
    end
    this.currentState = this.battleStates[:battleEnd]
    try
        JulGame.UserGlobals["Module"].ObserverModule.notify(:combo_ended)
    catch e
        @debug "Could not end combo on defeat: $e"
    end
    try
        Scripts.PlayerDeathAnimatorModule.play_death!(
            this.user,
            this;
            on_finalize = () -> _finalize_run!(this; context = "defeat"),
            on_exit = () -> begin
                Scripts.SceneTransitionModule.transition_to_scene(
                    this.transitionManager,
                    "title_scene.json";
                    direction = Scripts.SceneTransitionModule.Fade,
                )
                Scripts.PlayerDeathAnimatorModule.reset_animator!()
            end,
        )
        if !Scripts.PlayerDeathAnimatorModule.is_active()
            _finalize_run!(this; context = "defeat")
        end
    catch e
        @error "Error starting player death animation: $(e)"
        _finalize_run!(this; context = "defeat")
    end
end

function play_player_received_damage_sfx(amount::Int)
    amount <= 0 && return
    name = amount > 20 ? "damageheavy" : "damagenormal$(rand(1:6))"
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", name),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "player hurt sfx: $e"
    end
end

function _player_health_damage(user, damage::Int)::Int
    dmg = damage
    try
        if user.vulnerable > 0
            dmg = floor(Int, dmg * 1.5)
        end
        if user.shield > 0
            dmg = max(0, dmg - Int(user.shield))
        end
    catch
    end
    return max(0, dmg)
end

function take_damage(this, target, damage; skip_battle_damage_feedback::Bool = false, damage_icon::String = "", damage_source::String = "")
    globals = JulGame.UserGlobals["Module"]

    if target === this.user && damage > 0
        if Scripts.PlayerFocusZoomModule.would_kill_player(this.user, damage)
            try
                Scripts.PlayerFocusZoomModule.begin_focus!(this.user.playerEntity)
            catch
            end
            if try_player_death_preventions!(this, damage)
                Scripts.PlayerFocusZoomModule.release_focus!()
                return
            end
        end
    end

    if target === this.user
        try
            Globals.AnalyticsModule.track_action(:damage_received, damage)
        catch e
            @debug "Could not track damage received: $e"
        end
    end

    target_entity = nothing
    if isdefined(target, :parent)
        target_entity = target.parent
    elseif hasfield(typeof(target), :transform)
        target_entity = target
    else
        for enemy in this.enemies
            if enemy.scripts[1] === target
                target_entity = enemy
                break
            end
        end
    end

    if target === this.user
        play_player_received_damage_sfx(_player_health_damage(this.user, Int(damage)))
    end

    if target_entity !== nothing && !skip_battle_damage_feedback
        if target === this.user
            BattleJuiceModule.player_damage_feedback!(target_entity, damage)
        else
            BattleJuiceModule.enemy_damage_feedback!(
                target_entity, damage;
                icon = damage_icon,
                source = damage_source,
            )
        end
    elseif target_entity !== nothing && target !== this.user && (!isempty(damage_icon) || !isempty(damage_source))
        BattleJuiceModule.enemy_damage_feedback!(
            target_entity, damage;
            icon = damage_icon,
            source = damage_source,
        )
    end

    globals.UserModule.take_damage(target, damage)

    if target === this.user && this.user.health <= 0
        trigger_player_defeat!(this)
    elseif target === this.user
        Scripts.PlayerFocusZoomModule.release_focus!()
    end
end

function execute_enemy_skill(this::BattleManager, enemy)
    if this.battleEnemyManager !== nothing
        try
            Scripts.EnemyPatternsModule.execute_enemy_skill(enemy, this.gridController)
        catch e
            @error "Error executing enemy skill for $(enemy.enemyKey): $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end
end

function apply_pending_intents(this::BattleManager)
    @debug "💥 Animation complete! Applying $(length(this.pendingIntents)) pending intents"
    for (intent, count) in this.pendingIntents
        apply_single_intent(this, intent, count)
        if this.currentState == this.battleStates[:battleEnd]
            empty!(this.pendingIntents)
            return
        end
    end

    # Clear pending intents
    empty!(this.pendingIntents)

    # Sequential match resolution owns the state until its batch finishes and refills.
    Scripts.GridControllerModule.is_resolving_matches(this.gridController) && return

    # Return to replace items state
    # Grid refill already happened when items were cleared, so we don't need to call it again
    this.currentState = this.battleStates[:replaceItems]
end

function _is_boss_encounter(this::BattleManager)::Bool
    ev = this.persistentStateManager.currentEvent
    ev === nothing && return false
    # After defeat, reset_for_new_run sets currentEvent to (type="", name= "") which has no :category
    return hasproperty(ev, :category) && ev.category == "boss"
end

function _is_final_floor_boss(this::BattleManager)::Bool
    return _is_boss_encounter(this) &&
           !has_next_floor(this.persistentStateManager.currentFloor)
end

function _leave_or_confirm_skip!(this::BattleManager, proceed, unclaimed::Bool)
    unclaimed || return proceed()
    this.confirmationDialog === nothing && return proceed()

    this.rewardManager.inputBlocked = true
    strings = BattleStringsModule.BATTLE_STRINGS
    ConfirmationDialogModule.show_confirmation(
        this.confirmationDialog,
        strings[:battle_reward_skip_title],
        strings[:battle_reward_skip_message],
        () -> begin
            this.rewardManager.inputBlocked = false
            proceed()
        end,
        () -> this.rewardManager.inputBlocked = false;
        confirm_text = strings[:battle_button_skip],
        cancel_text = strings[:battle_reward_skip_cancel],
    )
end

function continue_after_victory!(this::BattleManager)
    if _is_boss_encounter(this) && has_next_floor(this.persistentStateManager.currentFloor)
        advanced = advance_to_next_floor!(this.persistentStateManager)
        if !advanced
            @error "Could not advance after boss victory"
            return
        end
        JulGame.UserGlobals["Module"].SaveManagerModule.try_save_run!()
    end

    Scripts.SceneTransitionModule.transition_to_scene(
        this.transitionManager,
        "map.json";
        direction = Scripts.SceneTransitionModule.Fade,
    )
end

function display_victory_screen(this::BattleManager)
    if this.isPlayerDead
        try
            Scripts.PlayerDeathAnimatorModule.is_active() && return
        catch
        end
    end
    globals = JulGame.UserGlobals["Module"]
    rewards_pending = Scripts.RewardManagerModule.is_showing(this.rewardManager)

    if rewards_pending
        display_reward_section(this)
    end

    # `postRunSnapshotFilled` stays true after the first boss-win frame even though
    # `_finalize_run!` wipes `currentEvent`, so use it as a sticky boss-win indicator.
    boss_post_run = _is_final_floor_boss(this) || this.postRunSnapshotFilled
    is_post_run = this.isPlayerDead || boss_post_run

    # Post-run (boss / defeat) uses the dedicated screen, but it waits behind the
    # reward offer. Rewards are optional, so Continue is what dismisses them.
    use_post_run = is_post_run && !rewards_pending
    if use_post_run
        if boss_post_run && !this.isPlayerDead
            if !this.postRunSnapshotFilled
                try
                    Scripts.PostRunScreenModule.capture_run_end_snapshot!(this.user, this.persistentStateManager, true)
                catch e
                    @error "Error capturing boss run end snapshot: $(e)"
                end
                # Analytics reads live run state, so it must be sent before the wipe below.
                if !this.postRunWinAnalyticsSent
                    try
                        globals.track_run_end(; run_won = true)
                        this.postRunWinAnalyticsSent = true
                    catch e
                        @error "Error tracking run end (win): $(e)"
                    end
                end
                # Snapshot owns the displayed data, so it's safe to wipe live run state now.
                # Mirrors trigger_player_defeat! so map progress, pieces, treasures, gold,
                # heal_blocked, etc. don't leak into the next run.
                _finalize_run!(this; context = "boss win")
                this.postRunSnapshotFilled = true
            end
        end
        if Scripts.PostRunScreenModule.get_snapshot() !== nothing
            if !this.didClearEverything
                # set all ui elements to inactive
                for uiElement in MAIN.scene.uiElements
                    if uiElement.id != "4e8f9d36-d9c2-4005-b8da-816078444aee" && !contains(uiElement.name, "SettingsMenu_")
                        uiElement.isActive = false
                    end
                end
                # set all world entities to inactive (except this one and the background)
                # for entity in MAIN.scene.entities
                #     if entity.id != "4e8f9d36-d9c2-4005-b8da-816078444aee"
                #         entity.isActive = false
                #     end
                # end
                this.didClearEverything = true
            end
            Scripts.PostRunScreenModule.draw_post_run_screen!(this)
            return
        end
    end

    # Default victory / reward flow (regular wins and non-final floor bosses)
    JulGame.ImmediateUIModule.immediate_rect(
        "victory_background";
        size=Math.Vector2(1920, 1080),
        color=(0, 0, 0, 180),
        anchor=:center,
        layer=8
    )

    title_text = this.isPlayerDead ? BattleStringsModule.BATTLE_STRINGS[:battle_defeat] : BattleStringsModule.BATTLE_STRINGS[:battle_victory]

    DisplayTextModule.display_text(
        "victory_text",
        title_text;
        fontSize = 48,
        color = (255, 255, 255, 255),
        anchor = :center,
        anchorOffset = Math.Vector2(0, -400),
        layer = 12,
    )

    unclaimed = Scripts.RewardManagerModule.has_offer(this.rewardManager)
    dialog_showing = this.confirmationDialog !== nothing && this.confirmationDialog.is_showing

    if this.isPlayerDead
        button_label = unclaimed ? BattleStringsModule.BATTLE_STRINGS[:battle_button_skip] : BattleStringsModule.BATTLE_STRINGS[:battle_button_return_to_title]
        proceed = () -> begin
            Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "title_scene.json"; direction = Scripts.SceneTransitionModule.Fade)
        end
        button_color = (220, 140, 90, 255)
    else
        button_label = unclaimed ? BattleStringsModule.BATTLE_STRINGS[:battle_button_skip] : BattleStringsModule.BATTLE_STRINGS[:battle_button_continue]
        proceed = () -> continue_after_victory!(this)
        button_color = (100, 255, 150, 255)
    end
    # Fly the button off only when actually leaving (after any skip confirm).
    leave = proceed
    proceed = () -> Scripts.ButtonJuiceModule.click!("victory_continue") && leave()

    # A post-run screen is queued behind the offer: Skip/Continue clears the offer
    # first, then the next press advances as usual.
    if is_post_run && rewards_pending
        proceed = () -> Scripts.RewardManagerModule.dismiss!(this.rewardManager)
    end

    on_continue = dialog_showing ? (() -> nothing) : (() -> _leave_or_confirm_skip!(this, proceed, unclaimed))

    defeat_bg = this.isPlayerDead ? (60, 12, 8, 50) : (3, 60, 5, 50)
    tb_continue_rect = JulGame.ImmediateUIModule.immediate_rect(
        "victory_continue_rect";
        anchor=:bottomRight,
        anchorOffset=Math.Vector2(5, -25),
        size=Math.Vector2(500, 275),
        color=defeat_bg,
        layer=13,
        borderWidth=4,
        borderColor=(255, 255, 255, 255),
        clickEvent=on_continue,
    )
    JulGame.apply_effects!(tb_continue_rect, [
        RoughEdgeEffect(amount=1, seed=42, erosion=true),
    ])

    tb_continue_text = DisplayTextModule.display_text(
        "victory_ok_button",
        button_label;
        fontSize=100,
        anchor=:center,
        color=button_color,
        fontPath="Century-Normal.ttf",
        layer=14,
        parent=tb_continue_rect,
        clickEvent=on_continue,
    )
    JulGame.apply_effects!(tb_continue_text, STYLE_VICTORY_CONTINUE_TEXT)
    Scripts.ButtonJuiceModule.update!("victory_continue", tb_continue_rect, tb_continue_rect.isHovered || tb_continue_text.isHovered)
end

function display_reward_section(this::BattleManager)
    Scripts.RewardManagerModule.display_rewards(this.rewardManager)
    # Prompt and tree lines are immediate-mode, so they redraw every frame.
    Scripts.RewardManagerModule.draw_choice_prompt(this.rewardManager)
end

function on_notify(this, event::Symbol, data::Any)
    if event == :used_treasure
        @debug "used_treasure: $(data)"
        treasure_index = findfirst(t -> t.key == data.key, this.treasureDisplayManager.treasures)
        if treasure_index !== nothing
            Scripts.TreasureDisplayManagerModule.use_treasure(this.treasureDisplayManager, treasure_index)
        end
    elseif event == :combo_ended
        # Nunchucks: Deal damage equal to your combo number to a random enemy.
        globals = JulGame.UserGlobals["Module"]
        if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_NUNCHUCKS) &&
           data !== nothing && isdefined(data, :combo_length) && data.combo_length > 0
            combo_length = data.combo_length
            alive_enemies = [e for e in this.enemies if e.scripts[1].health > 0]
            if !isempty(alive_enemies)
                target_entity = rand(alive_enemies)
                target = target_entity.scripts[1]
                @debug "Nunchucks: dealing $(combo_length) damage (combo length) to random enemy $(target.enemyKey)"
                take_damage(this, target, combo_length)
            end
        end
    elseif event == :enemy_defeated
        # Death animation is handled in Enemy.jl; no duplicate defeat feedback here.

        # Elemental Focus: Transfer status effects from defeated enemy to random remaining enemy
        defeated_enemy = data
        if defeated_enemy !== nothing && Globals.UserModule.has_treasure(Globals.TreasuresModule.TREASURE_ELEMENTALFOCUS)
            # Find all remaining alive enemies
            alive_enemies = []
            for enemy in this.enemies
                enemy_script = enemy.scripts[1]
                if enemy_script.health > 0 && enemy_script !== defeated_enemy
                    push!(alive_enemies, enemy_script)
                end
            end
            
            # Transfer status effects to a random enemy if any are alive
            if !isempty(alive_enemies)
                target_enemy = rand(alive_enemies)
                transferred = false
                
                # Transfer burn
                if defeated_enemy.burn > 0
                    target_enemy.burn = clamp(target_enemy.burn + defeated_enemy.burn, 0, 5)
                    @debug "Elemental Focus: Transferred $(defeated_enemy.burn) burn from defeated enemy to random enemy"
                    transferred = true
                end
                
                # Transfer freeze
                if defeated_enemy.freeze > 0
                    target_enemy.freeze = clamp(target_enemy.freeze + defeated_enemy.freeze, 0, 5)
                    @debug "Elemental Focus: Transferred $(defeated_enemy.freeze) freeze from defeated enemy to random enemy"
                    transferred = true
                end
                
                # Transfer poison
                if defeated_enemy.poison > 0
                    target_enemy.poison = clamp(target_enemy.poison + defeated_enemy.poison, 0, 5)
                    @debug "Elemental Focus: Transferred $(defeated_enemy.poison) poison from defeated enemy to random enemy"
                    transferred = true
                end
                
                # Transfer shock
                if defeated_enemy.shock > 0
                    target_enemy.shock = clamp(target_enemy.shock + defeated_enemy.shock, 0, 5)
                    @debug "Elemental Focus: Transferred $(defeated_enemy.shock) shock from defeated enemy to random enemy"
                    transferred = true
                end
                
                if transferred
                    # Show visual feedback
                    target_entity = nothing
                    for enemy in this.enemies
                        if enemy.scripts[1] == target_enemy
                            target_entity = enemy
                            break
                        end
                    end
                    if target_entity !== nothing
                        DisplayTextModule.display_text(
                            "elemental_focus_transfer",
                            "EFFECTS TRANSFERRED!";
                            fontSize=24,
                            anchor=:center,
                            anchorOffset=Math.Vector2(0, 50),
                            lifetime=2000,
                            color=(100, 200, 255, 255)
                        )
                        if defeated_enemy.shock > 0
                            try
                                BattleJuiceModule.shock_arc!(target_entity)
                            catch
                            end
                        end
                    end
                end
            end
        end

        refresh_selected_enemy_indicator!(this)
    end
end
end # module
