module GameManagerModule
using JulGame
using ..Scripts
include("utils/PiecesConstants.jl")

mutable struct GameManager
	parent::Any
	round::Int64
	
	# Scripts
	battleManager
	gridController::Any
	user
	persistentStateManager
	queueManager
	pauseMenu
	inputHandler
    tooltipManager  # Added tooltipManager reference
    enemyIntentTooltip  # Manager for enemy intent tooltips
    potionTooltip  # Manager for potion slot tooltips

	# Matching 
	matchEvent::Any
	waitForMatchTime::Float64
	waitForMatchElapsedTime::Float64

	flashUp::Bool
	
	# Treasures
	treasures::Vector
	shield_block_base::Int
	potion_heal_base::Int

	function GameManager()
		this = new()

		this.round = 1
		this.waitForMatchTime = 0.18
		this.waitForMatchElapsedTime = 0.0
		this.matchEvent = nothing
		this.flashUp = false
		# Initialize treasures      
		this.shield_block_base = 1
		this.potion_heal_base = 1

		return this
	end
end

function JulGame.initialize(this::GameManager)
    globals = JulGame.UserGlobals["Module"]
	this.user = globals.get_user_data()
    
	this.persistentStateManager = globals.get_data_manager().persistent_state_manager
    
	# Initialize grid
	this.inputHandler = this.parent.scripts[2]
	this.gridController = this.parent.scripts[3]
	this.battleManager = this.parent.scripts[4]
	this.pauseMenu = this.parent.scripts[5]
	this.queueManager = this.parent.scripts[6]
	
    # Create and initialize the tooltip manager if it doesn't exist
    tooltipEntity = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "TooltipManager")
    if tooltipEntity === nothing
        tooltipEntity = JulGame.EntityModule.Entity("TooltipManager")
        tooltipEntity = JulGame.create_entity(tooltipEntity)
        push!(tooltipEntity.scripts, Scripts.TooltipManagerModule.TooltipManager())
    end
    this.tooltipManager = tooltipEntity.scripts[1]
    
    # Configure tooltip appearance for treasures
    Scripts.TooltipManagerModule.set_tooltip_style(
        this.tooltipManager,
        bgColor = (30, 30, 50, 230),
        borderColor = (100, 100, 200, 200),
        fontSize = 16,
        padding = 12,
        hoverDelay = UInt64(120)
    )
    
    # Create and initialize the enemy intent tooltip manager
    intentTooltipEntity = JulGame.EntityModule.Entity("EnemyIntentTooltipManager")
    intentTooltipEntity = JulGame.create_entity(intentTooltipEntity)
    push!(intentTooltipEntity.scripts, Scripts.EnemyIntentTooltipModule.EnemyIntentTooltip())
    this.enemyIntentTooltip = intentTooltipEntity.scripts[1]
    Scripts.EnemyIntentTooltipModule.JulGame.initialize(this.enemyIntentTooltip)
    
    # Create and initialize the potion tooltip manager
    potionTooltipEntity = JulGame.EntityModule.Entity("PotionTooltipManager")
    potionTooltipEntity = JulGame.create_entity(potionTooltipEntity)
    push!(potionTooltipEntity.scripts, Scripts.PotionTooltipModule.PotionTooltip())
    this.potionTooltip = potionTooltipEntity.scripts[1]
    Scripts.PotionTooltipModule.JulGame.initialize(this.potionTooltip)

    Scripts.TutorialModule.on_battle_start!(this)
end

function JulGame.on_shutdown(this::GameManager)
    Scripts.TutorialModule.on_battle_end!()
end

# Facilitate the in game scene. We should be able to understand the flow of the game from this file and it should be the ultimate authority
function JulGame.update(this::GameManager, deltaTime)
	# Pattern piece animator (create / activate / idle timing)
	try
		Scripts.PatternAnimatorModule.update_animator!(Float64(deltaTime))
	catch e
		@debug "PatternAnimator update: $e"
	end

	try
		Scripts.DieRollAnimatorModule.update_animator!(Float64(deltaTime))
	catch e
		@debug "DieRollAnimator update: $e"
	end

	try
		Scripts.PlayerFocusZoomModule.update!(Float64(deltaTime))
	catch e
		@debug "PlayerFocusZoom update: $e"
	end

	try
		Scripts.PlayerDeathAnimatorModule.update_animator!(Float64(deltaTime))
	catch e
		@debug "PlayerDeathAnimator update: $e"
	end

	# Player pose / shadow / combatant hover popup (self-contained modules)
	try
		if this.user !== nothing && this.user.playerEntity !== nothing
		Scripts.CharacterPoseControllerModule.ensure_player!(this.user)
		# SpriteShadowEffect disabled for now — ellipse read poorly under the player.
		try
			this.user.playerEntity !== nothing && Scripts.SpriteShadowEffectModule.detach!(this.user.playerEntity)
		catch
		end
		Scripts.PlayerCombatantPopupModule.ensure!(this.user)
		Scripts.CharacterPoseControllerModule.update!(Float64(deltaTime), this.user)
		Scripts.PlayerCombatantPopupModule.update!(Float64(deltaTime))
		Scripts.PlayerCombatantPopupModule.draw!(Float64(deltaTime))
		end
	catch e
		@debug "Player presentation update: $e"
	end

	# Combo star HUD VFX
	try
		Scripts.ComboStarsModule.update(Float64(deltaTime), this.gridController)
	catch e
		@debug "ComboStars update: $e"
	end

	try
		Scripts.TutorialModule.update!(Float64(deltaTime))
	catch e
		@debug "Tutorial update: $e"
	end

	# Grid Controller - Check if pieces are reset
	areGridPiecesReset = Scripts.GridControllerModule.are_grid_pieces_reset(this.gridController)
    # Ensure the tooltipManager exists and is initialized
    if !isdefined(this, :tooltipManager) || this.tooltipManager === nothing
        # Re-initialize tooltipManager if not available
        tooltipEntity = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "TooltipManager")
        if tooltipEntity !== nothing && length(tooltipEntity.scripts) > 0
            this.tooltipManager = tooltipEntity.scripts[1]
        end
    end

	# Give player control over turn - Input Handler 
	if this.battleManager.currentState == this.battleManager.battleStates[:playerTurn] && !this.pauseMenu.paused
		#Scripts.InputHandlerModule.handle_crosshair(this.inputHandler, deltaTime)
		@debug("Player turn active - input would be handled here")
	elseif this.battleManager.currentState == this.battleManager.battleStates[:switchingItems]
		Scripts.GridControllerModule.switch_pieces(this.gridController, deltaTime)
	elseif this.battleManager.currentState == this.battleManager.battleStates[:searchingForMatches]
		# Pattern VFX may be holding the match (blocking) after matchEvent already ran.
		pattern_blocking = false
		die_blocking = false
		try
			pattern_blocking = Scripts.PatternAnimatorModule.is_animator_blocking()
		catch
		end
		try
			die_blocking = Scripts.DieRollAnimatorModule.is_blocking()
		catch
		end
		if pattern_blocking || die_blocking || Scripts.GridControllerModule.is_resolving_matches(this.gridController)
			# Wait for sweep/blast/die-roll gate or sequential match steps; do not re-arm match wait.
		elseif this.waitForMatchElapsedTime < this.waitForMatchTime
			# Apply game speed multiplier to wait time
			globals = JulGame.UserGlobals["Module"]
			speed_multiplier = globals.get_data_manager().game_speed_multiplier
			this.waitForMatchElapsedTime += deltaTime * speed_multiplier
			flash_match_highlight(this)
		elseif this.matchEvent !== nothing
			@debug("Match event")
			this.waitForMatchElapsedTime = 0.0
			this.matchEvent(nothing)
			this.matchEvent = nothing
		end
	elseif this.battleManager.currentState == this.battleManager.battleStates[:replaceItems] && areGridPiecesReset
		this.battleManager.currentState = this.battleManager.battleStates[:searchingForMatches]
		Scripts.GridControllerModule.check_for_falling_pieces_to_continue_matching(this.gridController)
	elseif this.battleManager.currentState == this.battleManager.battleStates[:processTurn]
        Scripts.BattleManagerModule.process_turn(this.battleManager)
	elseif this.battleManager.currentState == this.battleManager.battleStates[:playerAction]
		this.battleManager.actionElapsedTime += deltaTime
		if this.battleManager.actionElapsedTime >= this.battleManager.actionTimeLimit
			this.battleManager.moveCount = 3
			this.battleManager.countDict = Dict{String, Int}()
			this.battleManager.actionElapsedTime = 0.0
			this.battleManager.intent = PIECE_SWORD
			Scripts.BattleManagerModule.process_enemy_turn(this.battleManager)
		end
	elseif this.battleManager.currentState == this.battleManager.battleStates[:animatingIntents]
		# Update enemy turn animations
		still_animating = Scripts.BattleManagerModule.EnemyTurnAnimatorModule.update(deltaTime)
		
		# Animation system handles state transition via callback when complete
		# No need to check here - the callback sets state to :enemyTurn
	elseif this.battleManager.currentState == this.battleManager.battleStates[:enemyTurn]
		this.battleManager.actionElapsedTime += deltaTime
		if this.battleManager.actionElapsedTime >= this.battleManager.actionTimeLimit && this.battleManager.currentState != this.battleManager.battleStates[:battleEnd]
			this.battleManager.currentState = this.battleManager.battleStates[:playerTurn]
			this.battleManager.actionElapsedTime = 0.0
			
			# Increment round counter when player's turn starts
			this.round += 1
			# Dodge built last turn only covers the enemy turn that just resolved.
			this.battleManager.user.dodge_chance = 0
			
			# Reset ability uses for the new player turn
			abilityManager = this.parent.scripts[17]  # AbilityManager is script 19
			if abilityManager !== nothing
				Scripts.AbilityManagerModule.reset_turn_abilities(abilityManager)
			end
		end
	end
end

function flash_match_highlight(this::GameManager)
	for entity in JulGame.SceneModule.get_entities_by_name(MAIN.scene, "Board_Highlight")
		flash_step = this.flashUp ? 16 : -16
		flash = clamp(entity.sprite.color[1] + flash_step, 0, 255)
		if flash == 0 || flash == 255
			this.flashUp = !this.flashUp
		end

		entity.sprite.color = (flash, flash, flash, 255)
	end
end

function update_queue_after_move(this::GameManager)
	Scripts.QueueManagerModule.update_queue_display(this.queueManager)
end
end # module
