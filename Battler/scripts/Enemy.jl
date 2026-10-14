module EnemyModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.FX.ImageFXModule  # Add import for ImageFXModule
    using JulGame.EffectsModule
    using JSON3
    include("shared-types/Combatant.jl")
    include("utils/Constants.jl")
    include("utils/FloatingAnimation.jl")
    include("utils/EnemySpriteAnimations.jl")
    using .FloatingAnimationModule
    using .EnemySpriteAnimationsModule
    using ..Scripts

    mutable struct Enemy <: Combatant
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        # This is where you define your script's fields
        # Example: speed::Float64

        currentIntent::String 
        intentValue::Int

        pattern::Vector
        patternIndex::Int

        enemyKey::String
        id
        persistentStateManager

        enemyData
        floatingAnimation::FloatingAnimation
        heartPosition::Math.Vector3f
        healthHeart
        healthHeartBackground
        shieldUI
        intent
        intentPosition
        selectEnemy
        battleManager
        battleEnemyManager
        # Tint duplicated from ui-healthheart prefab; used when not hover-highlighting.
        healthHeartIdleColor::Union{Nothing, NTuple{4, Int}}
        # Base tint of the enemy body sprite; restore after revive.
        enemyBodyAliveColor::Union{Nothing, NTuple{4, Int}}
        # Prevent repeated :enemy_defeated notifications while dead.
        hasReportedDefeat::Bool
        deathStarted::Bool
        # Intent HUD was fired as this turn's projectile; hidden until the next player turn.
        intentLaunched::Bool
        intentFade::Float64

    function Enemy()
            this = new() # do not remove this line
            this.heartPosition = Math.Vector3f(0.0, 0.0, 0.0)
            this.intentPosition = Math.Vector3f(0.0, 0.0, 0.0)
            this.id = rand(1:1000000)
            this.healthHeartIdleColor = nothing
            this.enemyBodyAliveColor = nothing
            this.hasReportedDefeat = false
            this.deathStarted = false
            this.intentLaunched = false
            this.intentFade = 1.0
            return this # do not remove this line
        end

        function Enemy(heartPosition::Math.Vector3f, intentPosition::Math.Vector3f)
            this = new() # do not remove this line
            this.heartPosition = heartPosition
            this.intentPosition = intentPosition
            # this is where you initialize your script's fields
            # Example: this.speed = 1.0
            reset_enemy(this)
            this.enemyKey = "Default"
            this.pattern = []
            this.intentValue = 0
            this.currentIntent = ""
            this.enemyData = nothing
            this.id = rand(1:1000000)

            this.floatingAnimation = FloatingAnimation(
                speed = 0.88 + 0.24 * rand(),
                verticalAmplitude = 4.0/128.0,
                horizontalAmplitude = 3.0/128.0,
                rotationAmplitude = 3.0,
                horizontalPhaseOffset = rand() * 2π,
                rotationPhaseOffset = rand() * 2π,
            )
            # Randomize time base so vertical motion (and coupled axes) are not in phase across enemies
            this.floatingAnimation.animationTime = rand() * 20.0
            this.healthHeartIdleColor = nothing
            this.enemyBodyAliveColor = nothing
            this.hasReportedDefeat = false
            this.deathStarted = false
            this.intentLaunched = false
            this.intentFade = 1.0

            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # This is where you should register collision events or other events
    # Do not remove this function
    function _resolve_enemy_key(enemy)::String
        # Prefer canonical data key when available (already in ENEMY_* format)
        if hasproperty(enemy, :key)
            k = string(getproperty(enemy, :key))
            if !isempty(k)
                return k
            end
        end
        # Fallback to name-derived key: strip spaces/non-alnum to match generated constants.
        name_token = uppercase(replace(string(enemy.name), r"[^A-Za-z0-9]" => ""))
        return "ENEMY_$(name_token)"
    end

    function JulGame.initialize(this::Enemy, enemy, selectEnemy::Bool = false)
        globals = JulGame.UserGlobals["Module"]
        enemies = collect(values(globals.get_enemy_data()))  # Use the new accessor function
        battleEntity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba")
        this.battleManager = battleEntity.scripts[4]
        this.battleEnemyManager = battleEntity.scripts[13]  # BattleEnemyManager

        this.persistentStateManager = globals.get_data_manager().persistent_state_manager
        this.enemyKey = _resolve_enemy_key(enemy)

        # Set the enemy sprite based on the enemy name
        # remove spaces from the enemy name
        this.parent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("enemy", lowercase(replace(enemy.name, " " => ""))) # TODO: make this dynamic
        @debug "Updated enemy sprite to $(this.parent.sprite.imagePath) for $(enemy.name)"
        if this.parent.sprite !== nothing
            c = this.parent.sprite.color
            this.enemyBodyAliveColor = (Int(c[1]), Int(c[2]), Int(c[3]), Int(c[4]))
        end
        EnemySpriteAnimationsModule.attach_enemy_animation!(this.parent, this.enemyKey)

        for enemy_data in enemies
            @debug("enemy key: $(this.enemyKey)")
            if enemy_data.key == this.enemyKey
                this.pattern = split(enemy_data.pattern, ",")
                # convert all elements in this.pattern to String
                this.pattern = [string(x) for x in this.pattern]
                # Randomize starting position in attack pattern
                if !isempty(this.pattern)
                    this.patternIndex = rand(0:(length(this.pattern) - 1))
                else
                    this.patternIndex = 0
                end
                @debug("setting attack pattern to: $(this.pattern) for $(this.enemyKey), starting at index $(this.patternIndex)")
                enemyFound = true
                this.enemyData = enemy_data
                this.gold = enemy_data.average_gold
                this.maxHealth = enemy_data.average_health
                this.health = enemy_data.average_health
                this.attack = Scripts.RunScalingModule.scale_attack(
                    Int(enemy_data.average_attack),
                    string(this.enemyKey);
                    pattern = string(enemy_data.pattern),
                )
                this.defense = Scripts.RunScalingModule.scale_defense(
                    Int(enemy_data.average_defense),
                    string(this.enemyKey);
                    pattern = string(enemy_data.pattern),
                )
                this.gold = enemy_data.average_gold
            end
        end

        heartPrefab = JulGame.SceneModule.get_entity_by_id("ddcd7067-e80b-4459-89c5-abf09daa8277")
        this.healthHeart = JulGame.duplicate(heartPrefab)
        this.healthHeartBackground = JulGame.duplicate(JulGame.SceneModule.get_entity_by_id("180a83e2-c1e7-4d49-a8dd-426840499fb6"))
        this.healthHeartBackground.transform.scale = Math.Vector2f(1.04, 1.04)
        this.healthHeartBackground.isActive = true
        this.healthHeart.isActive = true
        
        # Apply border effect to enemy heart sprite (thin black border)
        if this.healthHeart !== nothing && this.healthHeart.sprite !== nothing
            # heart_border_effect = [
            #     EffectsModule.StrokeEffect(width=3, color=(0,0,0,255))
            # ]
            # JulGame.apply_effects!(this.healthHeart.sprite, heart_border_effect)
        end
        
        this.intent = JulGame.duplicate(JulGame.SceneModule.get_entity_by_id("37c7c93a-a8c8-4d65-987d-17d706401770"))
        this.intent.transform.position = this.intentPosition
        this.selectEnemy = JulGame.SceneModule.get_entity_by_id("8dbac0a0-7517-4fbc-83c6-3bcc16c48100")

        this.healthHeart.transform.position = this.heartPosition
        this.healthHeart.sprite.layer = 4
        # Duplicate may not copy prefab tint; idle color comes from scene template (battle.json).
        srcSprite = heartPrefab !== nothing && heartPrefab.sprite !== nothing ? heartPrefab.sprite : this.healthHeart.sprite
        c = srcSprite.color
        this.healthHeartIdleColor = (Int(c[1]), Int(c[2]), Int(c[3]), Int(c[4]))
        this.healthHeart.sprite.color = this.healthHeartIdleColor
        this.healthHeartBackground.transform.position = Math.Vector3f(
            this.heartPosition.x + HEART_BACKGROUND_OFFSET,
            this.heartPosition.y + HEART_BACKGROUND_OFFSET,
            this.heartPosition.z,
        )
        this.healthHeartBackground.sprite.layer = 3
        this.shieldUI = JulGame.duplicate(JulGame.SceneModule.get_entity_by_id("91d4a2d0-ed2a-4a3c-bcc6-215e8f86dec3"))
        this.shieldUI.transform.position = this.heartPosition
        this.shieldUI.sprite.layer = 4
        this.intent.isActive = true
        this.intent.transform.position = this.intentPosition
        this.intent.sprite.layer = 4
        if selectEnemy
            this.selectEnemy.transform.position = this.heartPosition
        end

        set_next_enemy_intent(this)
        
        # Register intent entity with tooltip system
        gameEntity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba")
        if gameEntity !== nothing && length(gameEntity.scripts) > 0
            gameManager = gameEntity.scripts[1]
            if gameManager !== nothing && isdefined(gameManager, :enemyIntentTooltip) && gameManager.enemyIntentTooltip !== nothing
                Scripts.EnemyIntentTooltipModule.register_enemy_intent(gameManager.enemyIntentTooltip, this, this.intent)
            end
        end

        if this.parent.sprite !== nothing && this.parent.sprite !== C_NULL
            initialize_floating_animation(this.floatingAnimation, this.parent.sprite)
        end

        # Per-enemy status HUD (compact under heart; expands on hover)
        bsd = Scripts.BattleStatusDisplayModule.BattleStatusDisplay(
            Math.Vector2(0.0, 0.0),
            "enemy_status_$(this.id)",
            :enemy_compact,
        )
        bsd.parent = this.parent
        push!(this.parent.scripts, bsd)
        JulGame.initialize(bsd)
    end

    const INTENT_FADE_IN = 0.35

    """Bring back an intent HUD that was fired this enemy turn, fading in its newly rolled intent."""
    function reveal_intent!(this::Enemy)
        this.intentLaunched || return
        this.intentLaunched = false
        this.health > 0 || return
        this.intentFade = 0.0
        this.intent.sprite.color = (255, 255, 255, 0)
        this.intent.isActive = true
    end

    function enemy_targeting_allowed(bm)::Bool
        bm === nothing && return false
        try
            return bm.currentState == bm.battleStates[:playerTurn]
        catch
            return false
        end
    end

    function is_revivable_kings_court_minion(this::Enemy)::Bool
        bm = this.battleManager
        bm === nothing && return false
        try
            return bm.kingsCourtMode &&
                   (this.enemyKey == "ENEMY_KNIGHT" || this.enemyKey == "ENEMY_PRIEST")
        catch
            return false
        end
    end

    function select_target!(this::Enemy)
        this.selectEnemy.transform.position = this.healthHeart.transform.position
        this.battleManager.selectedEnemy = this
        apply_enemy_select_feedback(this)
    end

    function apply_enemy_select_feedback(this::Enemy)
        try
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(), globals.get_asset_path("sfx", "select"), false, 0.82, 0, 1
            )
        catch e
            @debug "Enemy select SFX: $(e)"
        end
        try
            Scripts.BattleManagerModule.BattleJuiceModule.shake!(this.healthHeart; intensity=0.07, duration=0.22)
            Scripts.BattleManagerModule.BattleJuiceModule.scale_pulse!(this.selectEnemy; intensity=1.42, duration=0.18)
        catch e
            @debug "Enemy select feedback: $(e)"
        end
    end

    # This is called every frame
    # Do not remove this function
    function JulGame.update(this::Enemy, deltaTime)
        label = string("Enemy(", this.parent.name, ":", this.parent.id, ")")
        if this.health > 0
            update_floating_animation(this.floatingAnimation, deltaTime)
        else
            # Keep dead enemies static (no idle bob/tilt); revive resumes animation.
            if this.floatingAnimation.sprite !== nothing
                this.floatingAnimation.sprite.offset = this.floatingAnimation.baseOffset
                this.floatingAnimation.sprite.rotation = this.floatingAnimation.baseRotation
            end
        end
        # Heart clock sweep mutates full SDL surfaces; only while alive (dead ratio would repeat 0 forever).
        heart_highlight = -1.0
        if this.health > 0 && this.healthHeart !== nothing && this.healthHeart.sprite !== nothing
            max_hp = max(this.maxHealth, 1)
            shown, heart_highlight = Scripts.HeartFillFXModule.present!(
                "enemy-$(this.parent.id)",
                Float64(this.health) / Float64(max_hp),
                Float64(deltaTime),
            )
            gfx_clock_hand_sweep(
                this.healthHeart.sprite,
                shown;
                highlight_below=heart_highlight,
                bake_tint=Scripts.HeartFillFXModule.BAKE_TINT,
            )
        end

        # Subtle idle bob for intent icon (world-space), phase-shifted per enemy.
        if this.intent !== nothing && this.intent.isActive && this.health > 0 && !this.intentLaunched
            t = this.floatingAnimation.animationTime
            phase = this.floatingAnimation.rotationPhaseOffset
            bob = Float32(0.06 * sin(t * 2π * 0.58 + phase))
            base = this.intentPosition
            this.intent.transform.position = Math.Vector3f(base.x, base.y + bob, base.z)
            if this.intentFade < 1.0
                this.intentFade = min(1.0, this.intentFade + Float64(deltaTime) / INTENT_FADE_IN)
                this.intent.sprite.color = (255, 255, 255, round(Int, 255 * this.intentFade))
            end
        end

        if this.health > 0 && this.healthHeart !== nothing && this.healthHeart.sprite !== nothing
            bm = this.battleManager
            allowed = enemy_targeting_allowed(bm) && !Scripts.TutorialModule.blocks_enemy_target()
            hovering = JulGame.Component.is_mouse_hovering(this.healthHeart.transform)

            if allowed && hovering && JulGame.InputModule.get_mouse_button_pressed(1)
                if bm.selectedEnemy !== this
                    select_target!(this)
                else
                    try
                        globals = JulGame.UserGlobals["Module"]
                        globals.AudioManagerModule.play_audio_oneshot(
                            globals.get_audio_manager(), globals.get_asset_path("sfx", "tick1"), false, 0.38, 0, 1
                        )
                    catch e
                        @debug "Enemy re-select SFX: $(e)"
                    end
                end
            end

            if heart_highlight >= 0
                this.healthHeart.sprite.color = Scripts.HeartFillFXModule.FLASH_COLOR
            elseif this.healthHeartIdleColor !== nothing
                if allowed
                    this.healthHeart.sprite.color =
                        hovering ? (228, 242, 255, 255) : this.healthHeartIdleColor
                else
                    this.healthHeart.sprite.color = this.healthHeartIdleColor
                end
            end
        end

        if this.health <= 0
            this.healthHeartBackground.isActive = false
            this.healthHeart.isActive = false
            this.intent.isActive = false
            this.shieldUI.isActive = false

            if is_revivable_kings_court_minion(this)
                if this.parent !== nothing && this.parent.sprite !== nothing
                    this.parent.sprite.color = (125, 125, 125, 190)
                end
                this.parent.isActive = true
            elseif !this.deathStarted && this.parent !== nothing
                this.deathStarted = true
                style = Scripts.BattleManagerModule.BattleJuiceModule.death_style_for_enemy(this.enemyKey)
                Scripts.BattleManagerModule.BattleJuiceModule.play_death!(
                    this.parent;
                    style = style,
                    on_complete = () -> begin
                        if this.parent !== nothing
                            this.parent.isActive = false
                        end
                    end,
                )
            end

            if !this.hasReportedDefeat
                globals = JulGame.UserGlobals["Module"]
                globals.ObserverModule.notify(globals.get_observer_data(), :enemy_defeated, this)
                this.hasReportedDefeat = true
            end
        else
            this.hasReportedDefeat = false
            this.deathStarted = false
            if this.parent !== nothing && this.parent.sprite !== nothing && this.enemyBodyAliveColor !== nothing
                shock = Scripts.BattleManagerModule.BattleJuiceModule.shock_body_color(this.parent)
                this.parent.sprite.color = shock === nothing ? this.enemyBodyAliveColor : shock
            end
            # render health text 
            anchor = this.shield > 0 ? :centerBottom : :center
            anchorOffset = this.shield > 0 ? Math.Vector2(0, 10) : Math.Vector2(0, 0)
            if this.battleManager !== nothing && this.battleManager.didClearEverything == false
                DisplayTextModule.display_text(
                    "health_text_$(this.id)",
                    "$(this.health)";
                    fontSize = BATTLE_NUMBER_FONT_SIZE,
                    fontPath = BATTLE_NUMBER_FONT,
                    anchor = anchor,
                    anchorOffset = anchorOffset,
                    color = (255, 255, 255, 255),
                    parent = this.healthHeart.sprite
                )
            end
            if this.shield > 0 && this.shieldUI.isActive == false
                this.shieldUI.isActive = true
            elseif this.shield <= 0 && this.shieldUI.isActive == true
                this.shieldUI.isActive = false
            end
        end


        if this.shieldUI.isActive && this.shield > 0
            # render immediate text with the shield value
            if this.battleManager !== nothing && this.battleManager.didClearEverything == false
            DisplayTextModule.display_text(
                "shield_text_$(this.id)",
                    "$(this.shield)";
                    fontSize = BATTLE_NUMBER_FONT_SIZE,
                    fontPath = BATTLE_NUMBER_FONT,
                    anchor = :center,
                    color = (255, 255, 255, 255),
                    parent = this.shieldUI.sprite
                )
            end
        end

        if this.intent.isActive && !this.intentLaunched && this.intentValue > 0 && this.battleManager !== nothing && this.battleManager.didClearEverything == false
            # render immediate text with the intent value 
            DisplayTextModule.display_text(
                "intent_text_$(this.id)",
                "$(shown_intent_value(this))";
                fontSize = BATTLE_INTENT_FONT_SIZE,
                fontPath = BATTLE_NUMBER_FONT,
                anchor = :centerBottom,
                anchorOffset = JulGame.Math.Vector2(
                    0,
                    -5
                ),
                color = (255, 255, 255, round(Int, 255 * this.intentFade)),
                parent = this.intent.sprite
            )
        end

        bm = this.battleManager
        if bm !== nothing && this.health > 0 && bm.selectedEnemy === this && this.selectEnemy !== nothing && this.healthHeart !== nothing
            bob = Scripts.BattleManagerModule.selection_heart_bob_y(bm)
            p = this.healthHeart.transform.position
            this.selectEnemy.transform.position = Math.Vector3f(p.x, p.y + bob, p.z)
        end
    end

    # This is called when the script is removed from an entity (scene change, entity deletion)
    # Do not remove this function
    function JulGame.on_shutdown(this::Enemy)
        # Unregister intent tooltip when enemy is destroyed
        if isdefined(this, :intent) && this.intent !== nothing
            gameEntity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba")
            if gameEntity !== nothing && length(gameEntity.scripts) > 0
                gameManager = gameEntity.scripts[1]
                if gameManager !== nothing && isdefined(gameManager, :enemyIntentTooltip) && gameManager.enemyIntentTooltip !== nothing
                    Scripts.EnemyIntentTooltipModule.unregister_enemy_intent(gameManager.enemyIntentTooltip, this.intent)
                end
            end
        end
    end 

    function reset_enemy(this::Enemy)
        this.health = 50
        this.attack = 1
        this.defense = 1
        this.speed = 1
        this.luck = 0
        this.inventory = []
        this.gold = 0
        this.pieces = []
        this.treasures = []
    end

    function set_next_enemy_intent(this::Enemy)
        if length(this.pattern) < 1
            @error "No attack pattern set for $(this.parent.name), enemy key: $(this.enemyKey)"
            return
        end

        # Try advanced AI first if BattleEnemyManager is available
        advanced_result = nothing
        try
            if this.battleEnemyManager !== nothing
                advanced_result = Scripts.BattleEnemyManagerModule.determine_enemy_intent(this.battleEnemyManager, this)
            end
        catch e
            @error "Error in advanced AI, falling back to standard pattern: $(e)"
            Base.show_backtrace(stderr, catch_backtrace())
        end

        # Use advanced AI result if available, otherwise use standard pattern
        if advanced_result !== nothing
            this.currentIntent = advanced_result[1]
            this.intentValue = advanced_result[2]
            @debug "Advanced AI set intent for $(this.parent.name) to $(this.currentIntent) with value $(this.intentValue)"
        else
            # Standard pattern cycling
            this.patternIndex = (this.patternIndex % length(this.pattern)) + 1
            this.currentIntent = this.pattern[this.patternIndex]
            this.intentValue = get_intent_value(this)
            @debug "Standard pattern set intent for $(this.parent.name) to $(this.currentIntent)"
        end

        # Update intent sprite based on intent type
        this.intent.sprite.isFlipped = false
        if uppercase(this.currentIntent) == "ATTACK"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("intent", "spikey-sword")
            this.intent.sprite.isFlipped = true
        elseif uppercase(this.currentIntent) == "DEFEND"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("intent", "shield")
        elseif uppercase(this.currentIntent) == "HEAL"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("intent", "potion")
        elseif uppercase(this.currentIntent) == "TEAMHEAL"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("intent", "potion")
        elseif uppercase(this.currentIntent) == "CURSE"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("piece", "skull")
        elseif uppercase(this.currentIntent) == "SKILL"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("intent", "special")
        elseif uppercase(this.currentIntent) == "BASH"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("piece", "mace")
            this.intent.sprite.isFlipped = true
        elseif uppercase(this.currentIntent) == "WEAKEN"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("piece", "greengem")
        elseif uppercase(this.currentIntent) == "POISON"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("status", "poison")
        elseif uppercase(this.currentIntent) == "HEALKING"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("intent", "potion")
        elseif uppercase(this.currentIntent) == "ALLYSHIELD"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("intent", "shield")
        elseif uppercase(this.currentIntent) == "SUMMON"
            this.intent.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("enemy", "crow")
        end
        
        # Update tooltip text when intent changes
        gameEntity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "7a8aa3ba-17c8-4346-a606-361c29fbfeba")
        if gameEntity !== nothing && length(gameEntity.scripts) > 0
            gameManager = gameEntity.scripts[1]
            if gameManager !== nothing && isdefined(gameManager, :enemyIntentTooltip) && gameManager.enemyIntentTooltip !== nothing
                Scripts.EnemyIntentTooltipModule.update_enemy_intent_tooltip(gameManager.enemyIntentTooltip, this, this.intent)
            end
        end
    end

    """Strikes show the damage the player would take (poison, vulnerable), matching the hit."""
    function shown_intent_value(this::Enemy)::Int
        uppercase(this.currentIntent) in ("ATTACK", "BASH") || return this.intentValue
        return Scripts.BattleManagerModule.EnemyTurnAnimatorModule.effective_incoming_attack_damage(
            this.battleManager, (value = this.intentValue, script = this))
    end

    function get_intent_value(this::Enemy)
        pat = string(this.enemyData.pattern)
        key = string(this.enemyKey)
        if this.currentIntent == "Attack"
            return Scripts.RunScalingModule.scale_attack(
                Int(this.enemyData.average_attack),
                key;
                pattern = pat,
            )
        elseif this.currentIntent == "Defend"
            return Scripts.RunScalingModule.scale_defense(
                Int(this.enemyData.average_defense),
                key;
                pattern = pat,
            )
        elseif this.currentIntent == "Heal"
            base = round(Int, this.enemyData.average_heal * this.enemyData.average_health)
            return Scripts.RunScalingModule.scale_heal(base, key; pattern = pat)
        elseif this.currentIntent == "TeamHeal"
            base = round(Int, this.enemyData.average_heal * this.enemyData.average_health)
            return Scripts.RunScalingModule.scale_heal(base, key; pattern = pat)
        elseif this.currentIntent == "Curse"
            return 4
        elseif this.currentIntent == "Bash"
            return Scripts.RunScalingModule.scale_attack(
                Int(this.enemyData.average_attack),
                key;
                pattern = pat,
            )
        elseif this.currentIntent == "Weaken" || this.currentIntent == "Poison"
            return 2
        elseif this.currentIntent == "HealKing"
            base = round(Int, this.enemyData.average_heal * this.enemyData.average_health)
            return Scripts.RunScalingModule.scale_heal(base, key; pattern = pat)
        elseif this.currentIntent == "AllyShield"
            return Scripts.RunScalingModule.scale_defense(
                Int(this.enemyData.average_defense),
                key;
                pattern = pat,
            )
        elseif this.currentIntent == "Summon"
            return 1
        else
            return 0
        end
    end
end

