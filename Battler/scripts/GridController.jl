module GridControllerModule
	using JulGame
	using ..Scripts
	using Random: shuffle!
    include("utils/Easings.jl")
	
	"""Flying skull tween from cluster center into a grid cell (enemy Curse intent)."""
	mutable struct CurseSkullTween
		entity::Any
		target_x::Float64
		target_y::Float64
		start_x::Float64
		start_y::Float64
		gi::Int64
		gj::Int64
		elapsed::Float64
		duration::Float64
	end

	"""Board scramble: existing piece eases from its old world pos to a new cell."""
	mutable struct RearrangeTween
		entity::Any
		start_x::Float64
		start_y::Float64
		target_x::Float64
		target_y::Float64
		elapsed::Float64
		duration::Float64
		delay::Float64
	end

	const REARRANGE_DURATION = 0.65
	const REARRANGE_STAGGER = 0.018
	const REARRANGE_HOP = 0.55

	"""Counterweight treasure: icon flash on a cleared bottom-row cell."""
	mutable struct CounterweightFlash
		entity::Any
		elapsed::Float64
		duration::Float64
		cell_w::Float64
		cell_h::Float64
	end

	const MATCH_TIMING_ROLLING_WINDOW = 32
	# Pause after a sequential match's effect lands before the next match resolves
	const MATCH_STEP_BEAT = 0.3
	const COUNTERWEIGHT_FLASH_DURATION = 0.48
	const COUNTERWEIGHT_ICON = "treasure-counterweight"

	# Chess-themed swap presentation (Black Pawn / White Bishop reach moves)
	const SWITCH_LAYER_FIRST = 11
	const SWITCH_LAYER_LAST = 10
	const SWITCH_LAYER_VFX = 12
	const SWITCH_PIECE_LAYER_DEFAULT = 2
	# ~50% slower than first pass so the choreography reads clearly
	const SWITCH_PAWN_LENGTH = 1.8
	const SWITCH_BISHOP_LENGTH = 2.25
	const SWITCH_DEFAULT_LENGTH = 0.9
	const SWITCH_DEFAULT_SPEED = 3.0
	const SWITCH_PAWN_ICON = "treasure-blackpawn"
	const SWITCH_BISHOP_ICON = "treasure-whitebishop"

	"""Fixed-window rolling mean of recent timings (seconds)."""
	mutable struct RollingTiming
		window::Int
		samples::Vector{Float64}
		head::Int
		filled::Int
		sum::Float64
	end

	function RollingTiming(window::Int = MATCH_TIMING_ROLLING_WINDOW)
		RollingTiming(window, Vector{Float64}(undef, window), 1, 0, 0.0)
	end

	function record_rolling_timing!(rt::RollingTiming, elapsed_sec::Float64)::Float64
		if rt.filled < rt.window
			rt.filled += 1
			rt.samples[rt.filled] = elapsed_sec
			rt.sum += elapsed_sec
		else
			old = rt.samples[rt.head]
			rt.sum -= old
			rt.samples[rt.head] = elapsed_sec
			rt.sum += elapsed_sec
			rt.head = rt.head >= rt.window ? 1 : rt.head + 1
		end
		return rt.sum / rt.filled
	end

	mutable struct GridController
		parent::Any # do not remove this line, this is a reference to the entity that this script is attached to
		# This is where you define your script's fields
		first::Any
		last::Any

		switchElapsedTime::Any
		switchLength::Any
		switchSpeed::Any
		firstStart::Any
		lastStart::Any
		fallingPieces::Any
		switchStyle::Symbol
		switchFirstBaseLayer::Int
		switchLastBaseLayer::Int
		switchFirstBaseScale::Any
		switchLastBaseScale::Any
		switchFirstBaseRotation::Float64
		switchLastBaseRotation::Float64
		switchFirstBaseColor::Any
		switchLastBaseColor::Any
		switchVfxEntities::Vector{Any}
		switchBishopFlashSpawned::Bool

		battleManager
		gameManager
		queueManager
		persistentStateManager
		user

		curseSkullAnimations::Any
		rearrangeAnimations::Any
		rearranging::Bool
		pendingCommonSkullReplace::Bool
		counterweightFlashes::Vector{CounterweightFlash}

		matchThreshold::Int64
		breakSound

		grid
		gridPieces

		gridStartX
		gridStartY
		gridWidth
		gridHeight
		gridCellWidth
		gridCellHeight
		consumeTurnForCurrentChain::Bool

		# Rolling averages for match-search timings (seconds); see `record_match_timing!`
		match_timing_stats::Dict{Symbol, RollingTiming}

		# Last player-swap destination (pattern spawn anchor)
		lastSwapAnchor::Union{Nothing, Tuple{Int64, Int64}}

		# Sequential match resolution (Fast Mode off); see `update_match_steps!`
		matchSteps::Vector{Function}
		matchStepsOnDone::Union{Nothing, Function}
		matchStepBeat::Float64

		function GridController()
			this = new() # do not remove this line

			this.first = nothing
			this.last = nothing
			this.firstStart = nothing
			this.lastStart = nothing
			this.switchElapsedTime = 0.0
			this.switchLength = SWITCH_DEFAULT_LENGTH
			this.switchSpeed = SWITCH_DEFAULT_SPEED
			this.fallingPieces = []
			this.matchThreshold = 3
			this.gridWidth = 7
			this.gridHeight = 7
			this.gridStartX = -1.53
			this.gridStartY = -1.75
			this.gridCellWidth = 1.85
			this.gridCellHeight = 1.85
			this.consumeTurnForCurrentChain = true
			this.match_timing_stats = Dict{Symbol, RollingTiming}()
			this.lastSwapAnchor = nothing
			this.counterweightFlashes = CounterweightFlash[]
			this.rearrangeAnimations = RearrangeTween[]
			this.rearranging = false
			this.pendingCommonSkullReplace = false
			this.switchStyle = :adjacent
			this.switchFirstBaseLayer = SWITCH_PIECE_LAYER_DEFAULT
			this.switchLastBaseLayer = SWITCH_PIECE_LAYER_DEFAULT
			this.switchFirstBaseScale = nothing
			this.switchLastBaseScale = nothing
			this.switchFirstBaseRotation = 0.0
			this.switchLastBaseRotation = 0.0
			this.switchFirstBaseColor = (255, 255, 255, 255)
			this.switchLastBaseColor = (255, 255, 255, 255)
			this.switchVfxEntities = Any[]
			this.switchBishopFlashSpawned = false
			this.matchSteps = Function[]
			this.matchStepsOnDone = nothing
			this.matchStepBeat = 0.0

			return this # do not remove this line
		end
	end

	function record_match_timing!(this::GridController, key::Symbol, elapsed_sec::Float64)::Float64
		stats = this.match_timing_stats
		rt = get!(stats, key) do
			RollingTiming()
		end
		return record_rolling_timing!(rt, elapsed_sec)
	end

	function log_match_timing(this::GridController, key::Symbol, elapsed_sec::Float64, extra::String = "")
		avg = record_match_timing!(this, key, elapsed_sec)
		rt = this.match_timing_stats[key]
		suffix = isempty(extra) ? "" : " $extra"
		@debug "$(key) took $(elapsed_sec)s (rolling avg $(avg)s, n=$(rt.filled)/$(rt.window))$suffix"
	end

	# Helper function for eased interpolation
	function eased_lerp(start_val, end_val, progress)
		# Normalize progress to [0, 1] range
		t = clamp(progress, 0.0, 1.0)
		# Apply easing function - using ease_in_out_cubic for smooth acceleration/deceleration
		eased_t = ease_in_out_cubic(t)
		# Linear interpolation with eased value
		return start_val + (end_val - start_val) * eased_t
	end

	# This is called when a scene is loaded, or when script is added to an entity
	# This is where you should register collision events or other events
	# Do not remove this function
	function JulGame.initialize(this::GridController)
		globals = JulGame.UserGlobals["Module"]
		this.user = globals.get_user_data()
        
		this.gameManager = this.parent.scripts[1]
		this.battleManager = this.parent.scripts[4]
		this.breakSound = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "4f27bb49-990a-4809-93a7-c857230a6371").soundSource
		this.curseSkullAnimations = Vector{CurseSkullTween}()
		this.rearrangeAnimations = RearrangeTween[]
		this.rearranging = false
		this.pendingCommonSkullReplace = false
		this.counterweightFlashes = CounterweightFlash[]

		this.persistentStateManager = globals.get_data_manager().persistent_state_manager
        
		this.queueManager = this.parent.scripts[6]
		
		this.gridPieces = Array{Union{Nothing, JulGame.EntityModule.Entity}}(undef, this.gridWidth, this.gridHeight)
		try 
			this.grid = Scripts.QueueManagerModule.init_grid_and_populate_queue(this.queueManager, this.persistentStateManager, this.gridWidth, this.gridHeight)
			place_items(this)
		catch e
			#limit the error to 1000 characters
			@error "Error initializing grid: $(string(e)[1:min(length(string(e)), 1000)])"
			Base.show_backtrace(stdout, Base.catch_backtrace())
			@debug "type of this.queueManager: $(typeof(this.queueManager))"
			@debug "type of this.persistentStateManager: $(typeof(this.persistentStateManager))"
		end
	end

	# This is called every frame
	# Do not remove this function
	function JulGame.update(this::GridController, deltaTime)
		globals = JulGame.UserGlobals["Module"]
		speed_mult = try
			globals.get_data_manager().game_speed_multiplier
		catch
			1.0
		end
		dt = Float64(deltaTime) * speed_mult
		update_curse_skull_animations(this, dt)
		update_rearrange_animations(this, dt)
		update_counterweight_flashes(this, dt)
		update_match_steps!(this, dt)
		# Check if mouse is in grid bounds
		mousePos = MAIN.input.mousePositionWorld
	end

	function calculate_grid_piece_at_mouse_position(this, mousePos)
		if mousePos.x < this.gridStartX || mousePos.x >= this.gridStartX + this.gridWidth * this.gridCellWidth ||
		   mousePos.y < this.gridStartY || mousePos.y >= this.gridStartY + this.gridHeight * this.gridCellHeight
			return nothing
		end

		localX = (mousePos.x - this.gridStartX) / this.gridCellWidth
		localY = (mousePos.y - this.gridStartY) / this.gridCellHeight
		xIdx = convert(Int64, floor(localX)) + 1
		yIdx = convert(Int64, floor(localY)) + 1
		xIdx = clamp(xIdx, 1, this.gridWidth)
		yIdx = clamp(yIdx, 1, this.gridHeight)
		return this.gridPieces[xIdx, yIdx]
	end

	# This is called when the script is removed from an entity (scene change, entity deletion)
	# Do not remove this function
	function JulGame.on_shutdown(this::GridController)
		cleanup_switch_presentation!(this)
	end

	function build_entity_position_maps(this, entities_to_destroy)
		entity_positions = Set{Tuple{Int64, Int64}}()
		entity_types = Dict{Tuple{Int64, Int64}, String}()
		
		for entity in entities_to_destroy
			pos = convert_world_position_to_grid_position(this, entity.transform.position)
			gridPos = (convert(Int64, round(pos.x)), convert(Int64, round(pos.y)))
			push!(entity_positions, gridPos)
			entity_types[gridPos] = entity.name
		end
		
		return entity_positions, entity_types
	end
	
	function group_entities_by_type(entity_types)
		type_groups = Dict{String, Set{Tuple{Int64, Int64}}}()
		for (pos, type) in entity_types
			if !haskey(type_groups, type)
				type_groups[type] = Set{Tuple{Int64, Int64}}()
			end
			push!(type_groups[type], pos)
		end
		return type_groups
	end
	
	function find_connected_component_flood_fill(start_pos, positions, visited)
		component = Set{Tuple{Int64, Int64}}()
		queue = [start_pos]
		
		while !isempty(queue)
			current = pop!(queue)
			if current in visited
				continue
			end
			
			push!(visited, current)
			push!(component, current)
			
			x, y = current
			neighbors = [(x+1, y), (x-1, y), (x, y+1), (x, y-1)]
			
			for neighbor in neighbors
				if neighbor in positions && !(neighbor in visited)
					push!(queue, neighbor)
				end
			end
		end
		
		return component
	end

	function find_connected_matches(this, entities_to_destroy, isBomb::Bool = false)
		@debug "Finding connected matches"
		entity_positions, entity_types = build_entity_position_maps(this, entities_to_destroy)
		type_groups = group_entities_by_type(entity_types)
		connected_matches = []
	
		for (match_type, positions) in type_groups
			if isBomb
				# Just count all of the same type regardless of connectivity
				@debug("Bomb match: $(match_type) with length: $(length(positions))")
				if length(positions) >= 3
					@debug("Bomb match: $(match_type) with length: $(length(positions))")
					push!(connected_matches, (length = length(positions), type = match_type))
				end
			else
				# Connected component (flood fill) logic
				visited = Set{Tuple{Int64, Int64}}()
				for pos in positions
					if pos in visited
						continue
					end
					
					component = find_connected_component_flood_fill(pos, positions, visited)
					
					if length(component) >= 3
						push!(connected_matches, (length = length(component), type = match_type))
					end
				end
			end
		end
	
		return connected_matches
	end
	

	# id -> entity for a single column or row run through a seed cell
	const PiecePathDict = Dict{String, Any}

	function collect_column_and_row_paths(this, objects)
		t0 = time_ns()
		column_paths = Dict{String, PiecePathDict}()
		row_paths = Dict{String, PiecePathDict}()

		for obj in objects
			start_position = convert_world_position_to_grid_position(this, obj.transform.position)
			obj_id = obj.id

			@debug("Need to find path for: $(obj.name)")
			column_path, row_path = search_for_columns_and_rows(this, start_position, obj.name)
			@debug("column_path:")
			@debug("row_path:")

			column_paths[obj_id] = column_path
			@debug("set column_paths")
			row_paths[obj_id] = row_path
			@debug("set row_paths")
		end

		log_match_timing(this, :collect_column_and_row_paths, (time_ns() - t0) / 1e9, "($(length(objects)) seeds)")
		return column_paths, row_paths
	end

	function consolidate_entities_to_destroy(
		this::GridController,
		column_paths::Dict{String, PiecePathDict},
		row_paths::Dict{String, PiecePathDict},
		match_threshold::Int64,
		deleted_ids::Set{String},
		entities_to_destroy,
	)
		t0 = time_ns()
		for paths in (column_paths, row_paths)
			for (_, path) in paths
				length(path) < match_threshold && continue
				for (_, entity) in path
					eid = entity.id::String
					eid in deleted_ids && continue
					push!(deleted_ids, eid)
					push!(entities_to_destroy, entity)
				end
			end
		end
		log_match_timing(
			this,
			:consolidate_entities_to_destroy,
			(time_ns() - t0) / 1e9,
			"($(length(entities_to_destroy)) entities)",
		)
	end
	
	function apply_treasure_effects(this, connected_match)
		globals = JulGame.UserGlobals["Module"]
		@debug "connected_match.length: $(connected_match.length)"
		
		# Log treasure effect: deal 4 damage on 4+ matches
		if connected_match.length >= 4 && JulGame.UserGlobals["Module"].UserModule.has_treasure(globals.TreasuresModule.TREASURE_LOG)
			log_damage = 4
			# deal damage to a random enemy
			range = length(this.battleManager.enemies)
			random_enemy = this.battleManager.enemies[rand(1:range)]
			# Track damage dealt from Log treasure
			try
				Globals.AnalyticsModule.track_action(:damage_dealt, log_damage)
			catch e
				@debug "Could not track log damage: $e"
			end
			Scripts.BattleManagerModule.take_damage(this.battleManager, random_enemy.scripts[1], log_damage)
			@debug "Log effect applied, dealing $(log_damage) bonus damage for 4+ match"
		end
		
		# Counterweight treasure effect: remove random bottom row piece on any match
		if JulGame.UserGlobals["Module"].UserModule.has_treasure(globals.TreasuresModule.TREASURE_COUNTERWEIGHT)
			apply_counterweight_effect(this)
		end
	end
	
	function apply_counterweight_effect(this)
		globals = JulGame.UserGlobals["Module"]
		# Find pieces in bottom row (row this.gridHeight)
		bottom_row_pieces = []
		for i in 1:size(this.gridPieces, 1)
			if this.gridPieces[i, this.gridHeight] !== nothing
				push!(bottom_row_pieces, (i, this.gridHeight, this.gridPieces[i, this.gridHeight]))
			end
		end
		
		if !isempty(bottom_row_pieces)
			# Remove random piece from bottom row
			random_index = rand(1:length(bottom_row_pieces))
			x, y, piece = bottom_row_pieces[random_index]
			wx = calculate_placement_x(this, x)
			wy = calculate_placement_y(this, y)
			
			this.gridPieces[x, y] = nothing
			JulGame.destroy_entity(MAIN, piece)
			@debug "Counterweight effect applied, removing piece from bottom row at ($x, $y)"

			# Recycling Bin: For each piece you destroy, gain 1 dollar.
			if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_RECYCLINGBIN)
				this.user.gold += 1
			end

			spawn_counterweight_flash!(this, wx, wy)
		end
	end

	"""Pop/grow scale drawn about the sprite's center; transform.scale stays at the cell size."""
	function set_render_scale!(entity, s::Float64)
		entity.sprite === nothing && return
		entity.sprite.renderScale = Math.Vector2f(s, s)
	end

	function spawn_counterweight_flash!(this, wx, wy)
		crop = Math.Vector4(0, 0, 0, 0)
		ent = JulGame.EntityModule.Entity("Counterweight_VFX")
		ent.sprite = JulGame.SpriteModule.InternalSprite(
			ent, JulGame.UserGlobals["Module"].get_asset_path(COUNTERWEIGHT_ICON), crop, false, (255, 255, 255, 255), false;
			pixelsPerUnit = 150, layer = 6,
		)
		ent = JulGame.create_entity(ent)
		ent.transform.position = Math.Vector2f(wx, wy)
		ent.transform.scale = Math.Vector2f(this.gridCellWidth, this.gridCellHeight)
		set_render_scale!(ent, 0.4)
		push!(
			this.counterweightFlashes,
			CounterweightFlash(
				ent,
				0.0,
				COUNTERWEIGHT_FLASH_DURATION,
				Float64(this.gridCellWidth),
				Float64(this.gridCellHeight),
			),
		)
	end

	function update_counterweight_flashes(this::GridController, dt::Float64)
		flashes = this.counterweightFlashes
		isempty(flashes) && return
		keep = CounterweightFlash[]
		for flash in flashes
			flash.elapsed += dt
			t = clamp(flash.elapsed / flash.duration, 0.0, 1.0)
			# Pop out quickly, then settle/fade
			pop = t < 0.35 ? ease_out_cubic(t / 0.35) : (1.0 - ease_in_cubic((t - 0.35) / 0.65) * 0.35)
			scale = 0.4 + 0.95 * pop
			alpha = t < 0.2 ? 255 : round(Int, 255 * (1.0 - (t - 0.2) / 0.8))
			# Brief white flash into cool steel tint
			tint_mix = clamp(t / 0.25, 0.0, 1.0)
			r = round(Int, 255 * (1.0 - tint_mix) + 170 * tint_mix)
			g = round(Int, 255 * (1.0 - tint_mix) + 180 * tint_mix)
			b = round(Int, 255 * (1.0 - tint_mix) + 210 * tint_mix)
			try
				if flash.entity !== nothing
					set_render_scale!(flash.entity, scale)
					if flash.entity.sprite !== nothing
						flash.entity.sprite.color = (r, g, b, clamp(alpha, 0, 255))
					end
				end
			catch e
				@debug "counterweight flash step: $(e)"
			end
			if t < 1.0
				push!(keep, flash)
			else
				try
					flash.entity !== nothing && JulGame.destroy_entity(MAIN, flash.entity)
				catch
				end
			end
		end
		this.counterweightFlashes = keep
	end

	function register_combo_data(connected_match, entities_to_destroy, is_initial_match, this)
		globals = JulGame.UserGlobals["Module"]
		positions = Vector{Tuple{Int, Int}}()
		for entity in entities_to_destroy
			if entity.name == connected_match.type
				pos = convert_world_position_to_grid_position(this, entity.transform.position)
				grid_pos = (convert(Int64, round(pos.x)), convert(Int64, round(pos.y)))
				push!(positions, grid_pos)
			end
		end
		
		try
			globals.ObserverModule.notify(:combo_data, (
				length = connected_match.length,
				type = connected_match.type,
				positions = positions,
				is_initial_match = is_initial_match
			))
		catch e
			@debug "Failed to register combo: $(e)"
		end
	end
	
	function destroy_matched_entities(this, entities_to_destroy)
		for entity in entities_to_destroy
			# Check if the piece is nailed before destroying it
			if Scripts.AbilityManagerModule.is_piece_nailed(entity)
				@debug "Skipping destruction of nailed piece: $(entity.name)"
				continue  # Skip nailed pieces
			end
			
			pos = convert_world_position_to_grid_position(this, entity.transform.position)
			this.gridPieces[
				convert(Int64, round(pos.x)),
				convert(Int64, round(pos.y)),
			] = nothing
			JulGame.destroy_entity(MAIN, entity)

			# Recycling Bin: For each piece you destroy, gain 1 dollar.
			globals = JulGame.UserGlobals["Module"]
			if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_RECYCLINGBIN)
				this.user.gold += 1
			end
		end
	end
	
	function force_waiting_pieces_to_fall(this)
		# Force all pieces that are suspended in air to start falling immediately
		for i in 1:size(this.gridPieces, 1)
			for j in 1:size(this.gridPieces, 2)
				item = this.gridPieces[i, j]
				if item !== nothing && length(item.scripts) > 0
					piece_script = item.scripts[1]
					gridPosWorld = Scripts.PieceModule.convert_grid_position_to_world_position(piece_script, piece_script.gridPosition)
					currentPos = item.transform.position
					
					# If piece is above its target position, force it to start falling
					if currentPos.y < gridPosWorld.y
						Scripts.PieceModule.start_fall_animation(piece_script, gridPosWorld)
					end
				end
			end
		end
	end
	
	"""True while a batch of matches is being resolved one at a time (holds the refill)."""
	is_resolving_matches(this::GridController)::Bool = this.matchStepsOnDone !== nothing

	function start_match_steps!(this::GridController, steps::Vector{Function}, on_done::Function)
		this.matchSteps = steps
		this.matchStepsOnDone = on_done
		this.matchStepBeat = 0.0
	end

	"""Runs one match step at a time: waits for its intent to land, then a short beat. Stops early on battle end."""
	function update_match_steps!(this::GridController, dt::Float64)
		is_resolving_matches(this) || return
		bm = this.battleManager
		(!isempty(bm.pendingIntents) || !isempty(bm.activeAnimations)) && return
		if this.matchStepBeat > 0.0
			this.matchStepBeat -= dt
			return
		end
		if isempty(this.matchSteps) || bm.currentState == bm.battleStates[:battleEnd]
			on_done = this.matchStepsOnDone
			this.matchStepsOnDone = nothing
			empty!(this.matchSteps)
			on_done()
			return
		end
		popfirst!(this.matchSteps)()
		this.matchStepBeat = MATCH_STEP_BEAT
	end

	function create_match_event(this, entities_to_destroy, isBomb, is_initial_match, is_destroy::Bool = false)
		return JulGame.Macros.@argevent (none) begin
			remove_grid_highlights()
			@debug("Matching event: $(length(entities_to_destroy)), arg: $none, is_destroy: $is_destroy")

			if is_destroy
				destroy_matched_entities(this, entities_to_destroy)
				this.battleManager.currentState = this.battleManager.battleStates[:replaceItems]
				refill_grid(this)
				return
			end

			# Match/clear SFX is owned by ComboResponder (firstmatch + combo ladder).

			PH = Scripts.PatternHostModule
			PA = Scripts.PatternAnimatorModule
			pattern_expanded = false
			original_match = entities_to_destroy
			fx_events = Scripts.PatternKindsModule.PatternEvent[]

			# --- Pattern subsystem (activation → intents → creation) ---
			if !isBomb
				# Snapshot the line-match set before activation expands it.
				original_match = copy(entities_to_destroy)

				partner_type = nothing
				if this.first !== nothing && this.last !== nothing
					partner_type = string(this.last.name)
				end

				# 1) Activate specials already on matched cells (expand clear set)
				act = PH.run_activation_pass!(
					this.gridPieces,
					entities_to_destroy,
					this.gridWidth,
					this.gridHeight;
					partner_type = partner_type,
					play = false,
				)
				pattern_expanded = !isempty(act.plan.extra_destroy_cells)
				append!(fx_events, act.plan.events)
			end

			# Intents before creation removes protected anchors (keeps 4-match bonuses).
			connected_matches = if pattern_expanded || isBomb
				find_clear_intents(this, entities_to_destroy)
			else
				find_connected_matches(this, original_match, isBomb)
			end

			if !isBomb
				# 2) Create new specials from original line patterns only (anchors survive)
				snap = PH.build_match_snapshot(
					original_match,
					this.matchThreshold,
					this.gridWidth,
					this.gridHeight;
					swap_anchor = this.lastSwapAnchor,
					is_bomb = false,
					is_initial_match = is_initial_match,
				)
				create_res = PH.run_creation_pass!(this.gridPieces, entities_to_destroy, snap; play = false)
				append!(fx_events, create_res.plan.events)
			end

			# Board piece type per match (before Empty Locket rewrites intent types)
			match_types = [string(cm.type) for cm in connected_matches]
			
			# Empty Locket: Track first match type each turn and convert subsequent matches
			globals = JulGame.UserGlobals["Module"]
			has_empty_locket = globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_EMPTYLOCKET)
			
			if has_empty_locket && !isempty(connected_matches)
				if this.battleManager.firstMatchTypeThisTurn === nothing
					# First match of the turn (swap, hocus pocus, eyedropper, etc.)
					this.battleManager.firstMatchTypeThisTurn = connected_matches[1].type
					@debug "Empty Locket: First match type this turn is $(this.battleManager.firstMatchTypeThisTurn)"
					
					# Convert all other matches in this first event to the first match type
					for i in 2:length(connected_matches)
						original_type = connected_matches[i].type
						connected_matches[i] = (
							length = connected_matches[i].length,
							type = this.battleManager.firstMatchTypeThisTurn
						)
						@debug "Empty Locket: Converted match type from $(original_type) to $(this.battleManager.firstMatchTypeThisTurn) in first event"
					end
				elseif this.battleManager.firstMatchTypeThisTurn !== nothing
					# Convert all matches to the first match type (for cascade matches)
					for i in eachindex(connected_matches)
						original_type = connected_matches[i].type
						connected_matches[i] = (
							length = connected_matches[i].length,
							type = this.battleManager.firstMatchTypeThisTurn
						)
						@debug "Empty Locket: Converted match type from $(original_type) to $(this.battleManager.firstMatchTypeThisTurn)"
					end
				end
			end
			
			# Register matches with combo tracker - register each connected match separately
			# Each connected match represents a distinct match type and should count separately
			for connected_match in connected_matches
				register_combo_data(connected_match, entities_to_destroy, is_initial_match, this)
			end

			match_count_of(cm) = begin
				if pattern_expanded || isBomb
					max(1, cm.length)
				else
					1 + clamp(cm.length - this.matchThreshold, 0, 999)
				end
			end

			die_clusters = []
			die_faces = Dict{Int, Int}()
			for (i, connected_match) in enumerate(connected_matches)
				Scripts.DieRollAnimatorModule.is_die_piece(connected_match.type) || continue
				total_count = match_count_of(connected_match)
				lo, hi = Scripts.DieRollAnimatorModule.die_roll_range(total_count)
				face = Scripts.DieRollAnimatorModule.roll_die_face(total_count)
				die_faces[i] = face
				ents = [e for e in entities_to_destroy if e !== nothing && string(e.name) == string(connected_match.type)]
				push!(die_clusters, (entities = ents, face = face, lo = lo, hi = hi))
			end

			fire_intent! = (i, connected_match) -> begin
				total_count = get(die_faces, i, match_count_of(connected_match))
				@debug("Applying intent: $(connected_match.type) with total $(total_count)")
				Globals.RunRecorderModule.note_match!(connected_match.type, total_count)
				if !Scripts.SealedEnvelopeModule.capture_intents!(connected_match.type, total_count, entities_to_destroy)
					origin = Scripts.BattleManagerModule.match_fly_origin(entities_to_destroy, connected_match.type)
					Scripts.BattleManagerModule.trigger_intent_animation(connected_match.type, total_count, origin)
				end
				apply_treasure_effects(this, connected_match)
			end

			fire_intents! = () -> begin
				for (i, connected_match) in enumerate(connected_matches)
					fire_intent!(i, connected_match)
				end
			end

			finish_match! = (ents) -> begin
				destroy_matched_entities(this, ents)
				this.battleManager.currentState = this.battleManager.battleStates[:replaceItems]
				refill_grid(this)
			end

			# Sequential mode: clear + fire one match per step; refill once the batch is done.
			remaining = collect(entities_to_destroy)
			resolve_step! = (i, connected_match) -> begin
				step_ents = [e for e in remaining if string(e.name) == match_types[i]]
				filter!(e -> !(e in step_ents), remaining)
				remove_grid_highlights()
				fire_intent!(i, connected_match)
				destroy_matched_entities(this, step_ents)
				highlight_grid(this, remaining)
			end
			resolve_sequentially! = () -> begin
				steps = Function[() -> resolve_step!(i, cm) for (i, cm) in enumerate(connected_matches)]
				start_match_steps!(this, steps, () -> begin
					remove_grid_highlights()
					finish_match!(remaining)
				end)
			end

			resolve_after_roll! = () -> begin
				fast_mode = Scripts.MainSettingsModule.is_fast_mode_enabled()
				fast_mode && fire_intents!()
				on_gate = fast_mode ? (() -> finish_match!(entities_to_destroy)) : resolve_sequentially!
				if !isempty(fx_events)
					PH.bind_grid_context!(this)
					PA.play_events!(fx_events; on_gate = on_gate)
				else
					on_gate()
				end
			end

			if !isempty(die_clusters)
				Scripts.DieRollAnimatorModule.play_clusters!(
					die_clusters;
					cell_h = Float64(this.gridCellHeight),
					on_complete = resolve_after_roll!,
				)
			else
				resolve_after_roll!()
			end

			#JulGame.Component.toggle_sound(this.breakSound)
		end
	end

	"""Per-type clear intents (no adjacency / no min-3). Used for pattern & bomb area clears."""
	function find_clear_intents(this, entities_to_destroy)
		counts = Dict{String, Int}()
		for entity in entities_to_destroy
			t = string(entity.name)
			counts[t] = get(counts, t, 0) + 1
		end
		connected_matches = []
		for (match_type, n) in counts
			n <= 0 && continue
			push!(connected_matches, (length = n, type = match_type))
		end
		return connected_matches
	end

	function process_match(battleManager, match_type, match_data, match_threshold, idx)
		if !haskey(battleManager.countDict, match_data.type)
			battleManager.countDict[match_data.type] = 1
		else
			battleManager.countDict[match_data.type] += 1
		end
		bonus = clamp(match_data.length - match_threshold, 0, 999)
		battleManager.countDict[match_data.type] += bonus
		@debug("$(match_type) $(idx) match with length: $(match_data.length), of type $(match_data.type), bonus: $(bonus)")
	end

	function search_for_matches(this, objects, isBomb::Bool = false, is_initial_match::Bool = false, is_destroy::Bool = false, consume_turn::Bool = true)
		# start timer 
		timer = time_ns()
		globals = JulGame.UserGlobals["Module"]

		this.battleManager.currentState = this.battleManager.battleStates[:searchingForMatches]
		@debug "Searching for matches (initial=$(is_initial_match))"
		if !consume_turn
			this.consumeTurnForCurrentChain = false
		end
		
		deleted_ids = Set{String}()
		entities_to_destroy = isBomb ? objects : []

		# Find paths for all provided objects
		if !isBomb
			column_paths, row_paths = collect_column_and_row_paths(this, objects)
			consolidate_entities_to_destroy(this, column_paths, row_paths, this.matchThreshold, deleted_ids, entities_to_destroy)
		end
		
		# Mark grid for refill if any entities were destroyed
		@debug "entities_to_destroy: $(length(entities_to_destroy))"
		if length(entities_to_destroy) > 0
			@debug("highlighting grid")
			t_highlight = time_ns()
			highlight_grid(this, entities_to_destroy)
			log_match_timing(this, :highlight_grid, (time_ns() - t_highlight) / 1e9)
			@debug "highlighted grid"
			t_match_event = time_ns()
			match_event = create_match_event(this, entities_to_destroy, isBomb, is_initial_match, is_destroy)
			log_match_timing(this, :create_match_event, (time_ns() - t_match_event) / 1e9)
			this.gameManager.matchEvent = match_event
		elseif this.battleManager.currentState == this.battleManager.battleStates[:replaceItems] || this.battleManager.currentState == this.battleManager.battleStates[:searchingForMatches]
			@debug "skipping highlight grid"
			globals.ObserverModule.notify(:combo_ended)
			if this.consumeTurnForCurrentChain
				this.battleManager.currentState = this.battleManager.battleStates[:processTurn]
			else
				@debug "Consume turn for current chain is false, setting current state to player turn"
				this.battleManager.currentState = this.battleManager.battleStates[:playerTurn]
			end
			this.consumeTurnForCurrentChain = true
		end
		log_match_timing(this, :search_for_matches, (time_ns() - timer) / 1e9)
	end

	function search_for_columns_and_rows(this, start, name::String)
		t0 = time_ns()
		column_path = PiecePathDict()
		row_path = PiecePathDict()
		grid = this.gridPieces
		x = convert(Int64, round(start.x))
		y = convert(Int64, round(start.y))
		@debug "Searching for columns at $(x), $(y)"

		has_seen_start = false
		for j in axes(grid, 2)  # Iterate over columns
			@debug("Checking column: $(x), row: $(j) (columns)")
			if j == y
				@debug("start found at $(x), $(j)")
				has_seen_start = true
			end

			cell = grid[x, j]
			if has_seen_start && (cell === nothing || cell.name != name)
				@debug("break found at $(x), $(j)")
				break
			elseif cell !== nothing && cell.name == name
				@debug "adding $(cell.id) to column_path"
				eid = cell.id::String
				if !haskey(column_path, eid)
					column_path[eid] = cell
				end
			elseif !has_seen_start && (cell === nothing || cell.name != name) && !isempty(column_path)
				empty!(column_path)
			end
		end
		@debug("Column path length: $(length(column_path))")
		if length(column_path) < this.matchThreshold
			empty!(column_path)
		end

		has_seen_start = false
		@debug("Searching for rows")

		for j in axes(grid, 1)  # Iterate over rows
			@debug("Checking column: $(j), row: $(y) (rows)")
			if j == x
				has_seen_start = true
			end

			@debug "grid[j, y] check: "
			cell = grid[j, y]
			if has_seen_start && (cell === nothing || cell.name != name)
				break
			elseif cell !== nothing && cell.name == name
				@debug "adding $(cell.id) to row_path"
				eid = cell.id::String
				if !haskey(row_path, eid)
					row_path[eid] = cell
				end
			elseif !has_seen_start && (cell === nothing || cell.name != name) && !isempty(row_path)
				empty!(row_path)
			end
		end

		#@debug "row_path length: $(length(row_path))"
		if length(row_path) < this.matchThreshold
			empty!(row_path)
		end

		log_match_timing(this, :search_for_columns_and_rows, (time_ns() - t0) / 1e9, "($(name))")
		return column_path, row_path
	end

	function highlight_grid(this, entities_to_destroy)
		@debug "highlight_grid: $(length(entities_to_destroy)) entities to destroy"
		for entity in entities_to_destroy
			crop = Math.Vector4(0, 0, 0, 0)
		
			newItem = JulGame.EntityModule.Entity("Board_Highlight")
			newItem.sprite = JulGame.SpriteModule.InternalSprite(newItem, "highlight.png", crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 150, layer = 4)
		
			newItem = JulGame.create_entity(newItem)
			x = (entity.scripts[1].gridPosition.x - 1) * this.gridCellWidth + this.gridStartX
			y = (entity.scripts[1].gridPosition.y - 1) * this.gridCellHeight + this.gridStartY
			newItem.transform.position = Math.Vector2f(x, y)
			@debug "highlighting grid at $(x), $(y)"
			@debug "grid position: $(entity.scripts[1].gridPosition)"
			newItem.transform.scale = Math.Vector2f(this.gridCellWidth, this.gridCellHeight)
			
			@debug("Placed $(newItem.name) at $(x), $(y) successfully: scale $(this.gridCellWidth), $(this.gridCellHeight) 	(Highlight)")
		end
	end

	function remove_grid_highlights()
		for entity in JulGame.SceneModule.get_entities_by_name(MAIN.scene, "Board_Highlight")
			JulGame.destroy_entity(MAIN, entity)
		end
	end

	"""Match highlights only use `Board_Highlight`. Ability overlays use their own names."""
	function remove_hocus_pocus_highlights()
		for entity in JulGame.SceneModule.get_entities_by_name(MAIN.scene, "HocusPocus_Highlight")
			JulGame.destroy_entity(MAIN, entity)
		end
	end

	function remove_detonator_highlights()
		for entity in JulGame.SceneModule.get_entities_by_name(MAIN.scene, "Detonator_Highlight")
			JulGame.destroy_entity(MAIN, entity)
		end
	end

	function interpolate_position_component(current_val, target_val, start_val, elapsed_time, switch_length)
		if current_val != target_val
			return eased_lerp(start_val, target_val, min(elapsed_time, switch_length))
		end
		return current_val
	end

	function classify_switch_style(dx::Int, dy::Int)::Symbol
		adx = abs(dx)
		ady = abs(dy)
		if adx == ady && adx > 0
			return :bishop_slide
		elseif (adx == 0 && ady == 2) || (ady == 0 && adx == 2)
			return :pawn_double_step
		end
		return :adjacent
	end

	function _piece_sprite_layer(ent)::Int
		try
			ent !== nothing && ent.sprite !== nothing && return Int(ent.sprite.layer)
		catch
		end
		return SWITCH_PIECE_LAYER_DEFAULT
	end

	function _piece_sprite_rotation(ent)::Float64
		try
			ent !== nothing && ent.sprite !== nothing && return Float64(ent.sprite.rotation)
		catch
		end
		return 0.0
	end

	function _piece_sprite_color(ent)
		try
			ent !== nothing && ent.sprite !== nothing && return ent.sprite.color
		catch
		end
		return (255, 255, 255, 255)
	end

	function begin_switch_presentation!(this, style::Symbol)
		this.switchStyle = style
		this.switchElapsedTime = 0.0
		this.switchBishopFlashSpawned = false
		this.switchVfxEntities = Any[]
		this.switchSpeed = SWITCH_DEFAULT_SPEED
		if style == :pawn_double_step
			this.switchLength = SWITCH_PAWN_LENGTH
		elseif style == :bishop_slide
			this.switchLength = SWITCH_BISHOP_LENGTH
		else
			this.switchLength = SWITCH_DEFAULT_LENGTH
		end

		this.switchFirstBaseLayer = _piece_sprite_layer(this.first)
		this.switchLastBaseLayer = _piece_sprite_layer(this.last)
		this.switchFirstBaseScale = this.first !== nothing ? Math.Vector2f(this.first.transform.scale.x, this.first.transform.scale.y) : nothing
		this.switchLastBaseScale = this.last !== nothing ? Math.Vector2f(this.last.transform.scale.x, this.last.transform.scale.y) : nothing
		this.switchFirstBaseRotation = _piece_sprite_rotation(this.first)
		this.switchLastBaseRotation = _piece_sprite_rotation(this.last)
		this.switchFirstBaseColor = _piece_sprite_color(this.first)
		this.switchLastBaseColor = _piece_sprite_color(this.last)

		try
			if this.first !== nothing && this.first.sprite !== nothing
				this.first.sprite.layer = SWITCH_LAYER_FIRST
			end
			if this.last !== nothing && this.last.sprite !== nothing
				this.last.sprite.layer = SWITCH_LAYER_LAST
			end
		catch e
			@debug "begin_switch_presentation! layer boost: $e"
		end
	end

	function destroy_switch_vfx!(this)
		for ent in this.switchVfxEntities
			try
				ent !== nothing && JulGame.destroy_entity(MAIN, ent)
			catch
			end
		end
		empty!(this.switchVfxEntities)
	end

	function cleanup_switch_presentation!(this)
		try
			if this.first !== nothing
				if this.switchFirstBaseScale !== nothing
					this.first.transform.scale = this.switchFirstBaseScale
				end
				if this.first.sprite !== nothing
					this.first.sprite.layer = this.switchFirstBaseLayer
					this.first.sprite.rotation = this.switchFirstBaseRotation
					this.first.sprite.color = this.switchFirstBaseColor
				end
			end
		catch e
			@debug "cleanup first switch piece: $e"
		end
		try
			if this.last !== nothing
				if this.switchLastBaseScale !== nothing
					this.last.transform.scale = this.switchLastBaseScale
				end
				if this.last.sprite !== nothing
					this.last.sprite.layer = this.switchLastBaseLayer
					this.last.sprite.rotation = this.switchLastBaseRotation
					this.last.sprite.color = this.switchLastBaseColor
				end
			end
		catch e
			@debug "cleanup last switch piece: $e"
		end
		destroy_switch_vfx!(this)
		this.switchStyle = :adjacent
		this.switchBishopFlashSpawned = false
		this.switchLength = SWITCH_DEFAULT_LENGTH
		this.switchSpeed = SWITCH_DEFAULT_SPEED
	end

	function _lerp2(ax, ay, bx, by, t)
		return (ax + (bx - ax) * t, ay + (by - ay) * t)
	end

	"""Two-beat pawn hop along a cardinal path with lift + squash."""
	function _pawn_hop_pose(start_pos, end_pos, t::Float64, base_scale, cell_h)
		# Phase split: hop to midpoint, then hop to destination
		mid_x = (start_pos.x + end_pos.x) * 0.5
		mid_y = (start_pos.y + end_pos.y) * 0.5
		if t < 0.45
			local_t = clamp(t / 0.45, 0.0, 1.0)
			eased = ease_out_cubic(local_t)
			px, py = _lerp2(start_pos.x, start_pos.y, mid_x, mid_y, eased)
			hop = sin(local_t * π) * cell_h * 0.28
			squash = 1.0 - 0.18 * sin(local_t * π)^2
			stretch = 1.0 + 0.12 * sin(local_t * π)
			# Landing stamp near end of hop
			if local_t > 0.75
				land = (local_t - 0.75) / 0.25
				squash = 1.0 - 0.22 * land
				stretch = 1.0 + 0.16 * land
			end
			return (px, py - hop, base_scale.x * stretch, base_scale.y * squash)
		else
			local_t = clamp((t - 0.45) / 0.55, 0.0, 1.0)
			eased = ease_in_out_cubic(local_t)
			px, py = _lerp2(mid_x, mid_y, end_pos.x, end_pos.y, eased)
			hop = sin(local_t * π) * cell_h * 0.38
			squash = 1.0 - 0.22 * sin(local_t * π)^2
			stretch = 1.0 + 0.14 * sin(local_t * π)
			if local_t > 0.8
				land = (local_t - 0.8) / 0.2
				squash = 1.0 - 0.28 * (1.0 - land)
				stretch = 1.0 + 0.2 * (1.0 - land)
				# settle back
				squash = 1.0 - 0.28 * sin((1.0 - land) * π * 0.5)
				stretch = 1.0 + 0.2 * sin((1.0 - land) * π * 0.5)
			end
			return (px, py - hop, base_scale.x * stretch, base_scale.y * squash)
		end
	end

	function spawn_switch_icon_vfx!(this, path::String, cx::Float64, cy::Float64, rotations)
		crop = Math.Vector4(0, 0, 0, 0)
		for rot in rotations
			ent = JulGame.EntityModule.Entity("Switch_Treasure_VFX")
			ent.sprite = JulGame.SpriteModule.InternalSprite(
				ent, JulGame.UserGlobals["Module"].get_asset_path(path), crop, false, (255, 255, 255, 255), false;
				pixelsPerUnit = 150, layer = SWITCH_LAYER_VFX, rotation = Float64(rot),
			)
			ent = JulGame.create_entity(ent)
			ent.transform.position = Math.Vector2f(cx, cy)
			ent.transform.scale = Math.Vector2f(this.gridCellWidth, this.gridCellHeight)
			set_render_scale!(ent, 0.55)
			push!(this.switchVfxEntities, ent)
		end
	end

	function update_switch_icon_vfx!(this, t::Float64; spawn_at::Float64 = 0.45)
		isempty(this.switchVfxEntities) && return
		vt = clamp((t - spawn_at) / max(1.0 - spawn_at, 0.001), 0.0, 1.0)
		# Hold readable size longer, then fade
		pop = vt < 0.35 ? ease_out_cubic(vt / 0.35) : 1.0
		fade = vt < 0.55 ? 1.0 : (1.0 - (vt - 0.55) / 0.45)
		scale = 0.55 + 0.55 * pop
		alpha = round(Int, 255 * clamp(fade, 0.0, 1.0))
		for ent in this.switchVfxEntities
			try
				set_render_scale!(ent, scale)
				if ent.sprite !== nothing
					ent.sprite.color = (255, 255, 255, clamp(alpha, 0, 255))
				end
			catch
			end
		end
	end

	function apply_pawn_double_step!(this, t::Float64)
		bs1 = this.switchFirstBaseScale === nothing ? Math.Vector2f(this.gridCellWidth, this.gridCellHeight) : this.switchFirstBaseScale
		bs2 = this.switchLastBaseScale === nothing ? Math.Vector2f(this.gridCellWidth, this.gridCellHeight) : this.switchLastBaseScale
		fx, fy, fsx, fsy = _pawn_hop_pose(this.firstStart, this.lastStart, t, bs1, Float64(this.gridCellHeight))
		lx, ly, lsx, lsy = _pawn_hop_pose(this.lastStart, this.firstStart, t, bs2, Float64(this.gridCellHeight))
		this.first.transform.position = Math.Vector2f(fx, fy)
		this.last.transform.position = Math.Vector2f(lx, ly)
		this.first.transform.scale = Math.Vector2f(fsx, fsy)
		this.last.transform.scale = Math.Vector2f(lsx, lsy)

		# Center black-pawn icon between hops
		if !this.switchBishopFlashSpawned && t >= 0.42
			this.switchBishopFlashSpawned = true
			cx = (this.firstStart.x + this.lastStart.x) * 0.5
			cy = (this.firstStart.y + this.lastStart.y) * 0.5
			spawn_switch_icon_vfx!(this, SWITCH_PAWN_ICON, cx, cy, (0.0,))
		end
		update_switch_icon_vfx!(this, t; spawn_at = 0.42)
	end

	function apply_bishop_slide!(this, t::Float64)
		eased = ease_in_out_cubic(t)
		fx, fy = _lerp2(this.firstStart.x, this.firstStart.y, this.lastStart.x, this.lastStart.y, eased)
		lx, ly = _lerp2(this.lastStart.x, this.lastStart.y, this.firstStart.x, this.firstStart.y, eased)
		this.first.transform.position = Math.Vector2f(fx, fy)
		this.last.transform.position = Math.Vector2f(lx, ly)

		# Mitre lean into the diagonal, unwind on arrival
		dx = this.lastStart.x - this.firstStart.x
		dy = this.lastStart.y - this.firstStart.y
		lean_sign = (dx * dy) >= 0 ? 1.0 : -1.0
		lean = sin(t * π) * 18.0 * lean_sign
		try
			if this.first.sprite !== nothing
				this.first.sprite.rotation = this.switchFirstBaseRotation + lean
			end
			if this.last.sprite !== nothing
				this.last.sprite.rotation = this.switchLastBaseRotation - lean
			end
		catch
		end

		# Soft gold tint pulse
		pulse = 0.35 + 0.65 * sin(t * π)
		r = round(Int, 255)
		g = round(Int, 255 - 40 * pulse)
		b = round(Int, 255 - 80 * pulse)
		try
			if this.first.sprite !== nothing
				this.first.sprite.color = (r, g, b, 255)
			end
			if this.last.sprite !== nothing
				this.last.sprite.color = (r, g, b, 255)
			end
		catch
		end

		# Midpoint: two crossed bishop treasure icons
		if !this.switchBishopFlashSpawned && t >= 0.45
			this.switchBishopFlashSpawned = true
			cx = (this.firstStart.x + this.lastStart.x) * 0.5
			cy = (this.firstStart.y + this.lastStart.y) * 0.5
			spawn_switch_icon_vfx!(this, SWITCH_BISHOP_ICON, cx, cy, (0.0,))
		end
		update_switch_icon_vfx!(this, t; spawn_at = 0.45)
	end

	function apply_adjacent_switch!(this, progress)
		new_first_x = interpolate_position_component(
			this.first.transform.position.x, this.lastStart.x,
			this.firstStart.x, progress, this.switchLength
		)
		new_first_y = interpolate_position_component(
			this.first.transform.position.y, this.lastStart.y,
			this.firstStart.y, progress, this.switchLength
		)
		this.first.transform.position = Math.Vector2f(new_first_x, new_first_y)

		new_last_x = interpolate_position_component(
			this.last.transform.position.x, this.firstStart.x,
			this.lastStart.x, progress, this.switchLength
		)
		new_last_y = interpolate_position_component(
			this.last.transform.position.y, this.firstStart.y,
			this.lastStart.y, progress, this.switchLength
		)
		this.last.transform.position = Math.Vector2f(new_last_x, new_last_y)
	end
	
	function switch_pieces(this, deltaTime)
		if this.first === nothing || this.last === nothing
			return
		end
		# Apply game speed multiplier to switch animation
		globals = JulGame.UserGlobals["Module"]
		speed_multiplier = globals.get_data_manager().game_speed_multiplier
		this.switchElapsedTime += (this.switchSpeed * deltaTime * speed_multiplier)
		progress = min(this.switchElapsedTime, this.switchLength)
		t = clamp(this.switchElapsedTime / max(this.switchLength, 0.001), 0.0, 1.0)

		if this.switchStyle == :pawn_double_step
			apply_pawn_double_step!(this, t)
		elseif this.switchStyle == :bishop_slide
			apply_bishop_slide!(this, t)
		else
			apply_adjacent_switch!(this, progress)
		end

		if this.switchElapsedTime >= this.switchLength
			@debug "finished switching, forcing final positions: $(this.firstStart.x), $(this.firstStart.y) and $(this.lastStart.x), $(this.lastStart.y)"
			this.first.transform.position = Math.Vector2f(this.lastStart.x, this.lastStart.y)
			this.last.transform.position = Math.Vector2f(this.firstStart.x, this.firstStart.y)
			finished_first = this.first
			finished_last = this.last
			cleanup_switch_presentation!(this)
			search_for_matches(this, [finished_first, finished_last], false, true)

			# Track switch usage in analytics
			try
				Globals.AnalyticsModule.track_action(:switch_used)
			catch e
				@debug "Could not track switch usage: $e"
			end

			this.first = nothing
			this.last = nothing
			this.switchElapsedTime = 0.0
		end
	end

	function place_items(this)
		for i in 1:size(this.grid, 1)  # Iterate over rows
			for j in 1:size(this.grid, 2)  # Iterate over columns
				value = this.grid[i, j]
				@debug "placing item: $(value.key) at $(i), $(j)"
				place_item(this, value, i, j, 0, true)  # Pass first=true for initial grid setup
			end
		end
	end

	function place_item(this, item, placementX, placementY, offsetY = 0, first = false)
		placementXWorld = calculate_placement_x(this, placementX)
		@debug "placementX: $(placementX)"
		placementYWorld = calculate_placement_y(this, placementY)
		@debug "placementY: $(placementY)"
		# @warn "BOUNCE DEBUG place_item: gridPos=($placementX,$placementY) worldPos=($placementXWorld,$placementYWorld) offsetY=$offsetY finalY=$(placementYWorld + offsetY)"
		crop = Math.Vector4(0, 0, 0, 0)
		newItem = JulGame.EntityModule.Entity(item.key)
		try
			newItem.sprite = JulGame.SpriteModule.InternalSprite(newItem, JulGame.UserGlobals["Module"].get_asset_path("piece", lowercase(split(item.key, "_")[2])), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 150, layer = 2)
		catch e
			#@error first(string(e), 1000)
			@error "Error placing item: $(item.key), placing error sprite"
			newItem.sprite = JulGame.SpriteModule.InternalSprite(newItem, JulGame.UserGlobals["Module"].get_asset_path("piece", "error"), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 8, layer = 2)
		end
		newItem.scripts = [Scripts.PieceModule.Piece(Math.Vector2(placementX, placementY), item)]
		newItem.scripts[1].parent = newItem
		JulGame.initialize(newItem.scripts[1])
		newItem = JulGame.create_entity(newItem)
		newItem.transform.scale = Math.Vector2f(this.gridCellWidth, this.gridCellHeight)
		newItem.transform.position = Math.Vector2f(placementXWorld, placementYWorld + offsetY)
		
		this.gridPieces[placementX, placementY] = newItem

		@debug("Placed $(newItem.name) at $(placementX), $(placementY + offsetY) successfully")
		return newItem
	end

	function calculate_placement_x(this, placementX)
		#@debug "calculate_placement_x: $((placementX - 1) * this.gridCellWidth + this.gridStartX)"
		return (placementX - 1) * this.gridCellWidth + this.gridStartX
	end

	function calculate_placement_y(this, placementY)
		#@debug "calculate_placement_y: $((placementY - 1) * this.gridCellHeight + this.gridStartY)"
		return (placementY - 1) * this.gridCellHeight + this.gridStartY
	end

	function analyze_column(this, column_index)
		should_replace = false
		column_items = []
		nailed_positions = Dict{Int, Any}()
		new_items = 0
		column_break_start = 0

		for j in 1:size(this.gridPieces, 2)
			item = this.gridPieces[column_index, j]
			if item !== nothing
				if Scripts.AbilityManagerModule.is_piece_nailed(item)
					nailed_positions[j] = item
					@debug "Found nailed piece at $(column_index), $(j): $(item.name)"
				else
					push!(column_items, item)
				end
			else
				should_replace = true
				new_items += 1
			end
		end

		for j in size(this.gridPieces, 2):-1:1
			if this.gridPieces[column_index, j] === nothing && column_break_start == 0
				column_break_start = j
			end
		end

		return should_replace, column_items, nailed_positions, new_items, column_break_start
	end
	
	function place_falling_items(this, column_index, column_items, nailed_positions)
		current_row = size(this.gridPieces, 2)
		for n in 1:length(column_items)
			piece = column_items[length(column_items) - n + 1]
			if piece !== nothing
				while current_row > 0 && (haskey(nailed_positions, current_row) || this.gridPieces[column_index, current_row] !== nothing)
					current_row -= 1
				end
				
				if current_row > 0
					this.gridPieces[column_index, current_row] = piece
					old_grid_pos = piece.scripts[1].gridPosition
					piece.scripts[1].gridPosition = Math.Vector2(column_index, current_row)
					# @warn "BOUNCE DEBUG place_falling: $(piece.name) old_grid=$(old_grid_pos) new_grid=($column_index,$current_row) current_transform_y=$(piece.transform.position.y)"
					current_row -= 1
				end
			end
		end
	end
	
	function place_new_items(this, column_index, new_items, column_break_start)
		if new_items == 0
			return
		end
		
		# Calculate available empty positions from top
		empty_positions = []
		for j in 1:size(this.gridPieces, 2)
			if this.gridPieces[column_index, j] === nothing
				push!(empty_positions, j)
			end
		end
		
		# Place new items in available empty positions, starting from the bottom-most
		items_to_place = min(new_items, length(empty_positions))
		for n in 1:items_to_place
			# Take rows from the end so the first dequeued (front of queue)
			# piece goes to the lowest available row in this column.
			target_row = empty_positions[end - (n - 1)]
			Scripts.QueueManagerModule.dequeue_piece_for_grid_with_animation(this.queueManager, this.persistentStateManager, column_index, target_row, -items_to_place)
			@debug "Placing new item at column $(column_index), row $(target_row) (respecting nailed pieces)"
		end

		for j in size(this.gridPieces, 2):-1:1
			item = this.gridPieces[column_index, j]
			if item === nothing
				continue
			end

			if column_break_start > 0 && j <= column_break_start
				push!(this.fallingPieces, item)
			end
			
			if j > (1+length(new_items))
				continue
			end
		end
	end
	
	function refill_grid(this)
		# Iterate over columns first
		for i in size(this.gridPieces, 1):-1:1
			should_replace, column_items, nailed_positions, new_items, column_break_start = analyze_column(this, i)

			if should_replace
				this.battleManager.currentState = this.battleManager.battleStates[:replaceItems]
				
				# Clear the column first, but preserve nailed pieces
				for j in 1:size(this.gridPieces, 2)
					if !haskey(nailed_positions, j)
						this.gridPieces[i, j] = nothing
					end
				end
				
				place_falling_items(this, i, column_items, nailed_positions)
				place_new_items(this, i, new_items, column_break_start)
			end
		end
		
		# Force all waiting pieces to fall immediately after refilling
		force_waiting_pieces_to_fall(this)
	end

	function _piece_key(ent)::String
		try
			return string(ent.scripts[1].pieceData.key)
		catch
			return string(ent.name)
		end
	end

	function _is_identity_perm(from, to)::Bool
		length(from) != length(to) && return false
		for i in eachindex(from)
			from[i] != to[i] && return false
		end
		return true
	end

	function _creates_three_at(keys, x::Int, y::Int, key::String, w::Int, h::Int, threshold::Int)::Bool
		key == "" && return false
		left = 0
		i = x - 1
		while i >= 1 && keys[i, y] == key
			left += 1
			i -= 1
		end
		right = 0
		i = x + 1
		while i <= w && keys[i, y] == key
			right += 1
			i += 1
		end
		left + 1 + right >= threshold && return true
		below = 0
		j = y - 1
		while j >= 1 && keys[x, j] == key
			below += 1
			j -= 1
		end
		above = 0
		j = y + 1
		while j <= h && keys[x, j] == key
			above += 1
			j += 1
		end
		return below + 1 + above >= threshold
	end

	function _board_has_three(keys, w::Int, h::Int, threshold::Int)::Bool
		for y in 1:h
			run = 1
			prev = keys[1, y]
			for x in 2:w
				cur = keys[x, y]
				if cur !== nothing && cur == prev
					run += 1
					run >= threshold && return true
				else
					run = 1
					prev = cur
				end
			end
		end
		for x in 1:w
			run = 1
			prev = keys[x, 1]
			for y in 2:h
				cur = keys[x, y]
				if cur !== nothing && cur == prev
					run += 1
					run >= threshold && return true
				else
					run = 1
					prev = cur
				end
			end
		end
		return false
	end

	const REARRANGE_LAYOUT_ATTEMPTS = 48

	function _pick_no_match_positions(this, pieces, positions)
		w = size(this.gridPieces, 1)
		h = size(this.gridPieces, 2)
		th = Int(this.matchThreshold)
		locked = Matrix{Union{Nothing, String}}(nothing, w, h)
		for i in 1:w, j in 1:h
			ent = this.gridPieces[i, j]
			ent === nothing && continue
			Scripts.AbilityManagerModule.is_piece_nailed(ent) || continue
			locked[i, j] = _piece_key(ent)
		end

		fallback = nothing
		clean = nothing
		for _ in 1:REARRANGE_LAYOUT_ATTEMPTS
			keys = copy(locked)
			remaining = copy(positions)
			shuffle!(remaining)
			order = shuffle!(collect(eachindex(pieces)))
			assignment = Vector{Tuple{Int64, Int64}}(undef, length(pieces))
			forced = false
			for idx in order
				key = _piece_key(pieces[idx])
				placed = false
				for s in 1:length(remaining)
					x, y = remaining[s]
					_creates_three_at(keys, x, y, key, w, h, th) && continue
					assignment[idx] = (x, y)
					keys[x, y] = key
					deleteat!(remaining, s)
					placed = true
					break
				end
				if !placed
					isempty(remaining) && break
					x, y = remaining[1]
					assignment[idx] = (x, y)
					keys[x, y] = key
					deleteat!(remaining, 1)
					forced = true
				end
			end
			length(remaining) == 0 || continue
			fallback === nothing && (fallback = assignment)
			if !forced && !_board_has_three(keys, w, h, th)
				if !_is_identity_perm(positions, assignment)
					return assignment
				end
				clean = assignment
			end
		end
		return clean !== nothing ? clean : fallback
	end

	function start_animated_rearrange!(this)::Bool
		this.rearranging && return false
		existing_pieces = Any[]
		valid_positions = Tuple{Int64,Int64}[]
		for i in 1:size(this.gridPieces, 1)
			for j in 1:size(this.gridPieces, 2)
				ent = this.gridPieces[i, j]
				ent === nothing && continue
				Scripts.AbilityManagerModule.is_piece_nailed(ent) && continue
				push!(existing_pieces, ent)
				push!(valid_positions, (i, j))
			end
		end
		length(existing_pieces) < 2 && return false

		shuffled_positions = _pick_no_match_positions(this, existing_pieces, valid_positions)
		shuffled_positions === nothing && return false

		for (i, j) in valid_positions
			this.gridPieces[i, j] = nothing
		end

		this.rearrangeAnimations = RearrangeTween[]
		this.rearranging = true
		for (piece_idx, piece) in enumerate(existing_pieces)
			new_x, new_y = shuffled_positions[piece_idx]
			this.gridPieces[new_x, new_y] = piece
			try
				piece.scripts[1].gridPosition = Math.Vector2(new_x, new_y)
			catch e
				@debug "rearrange gridPosition: $e"
			end
			sx = Float64(piece.transform.position.x)
			sy = Float64(piece.transform.position.y)
			tx = calculate_placement_x(this, new_x)
			ty = calculate_placement_y(this, new_y)
			push!(this.rearrangeAnimations, RearrangeTween(
				piece, sx, sy, tx, ty, 0.0, REARRANGE_DURATION, (piece_idx - 1) * REARRANGE_STAGGER,
			))
		end
		@debug "Grid pieces rearranging. Total pieces moved: $(length(existing_pieces))"
		return true
	end

	function _most_common_piece_cells(this)
		counts = Dict{String, Int}()
		cells = Dict{String, Vector{Tuple{Int64,Int64}}}()
		rarities = Dict{String, Float64}()
		for i in 1:size(this.gridPieces, 1)
			for j in 1:size(this.gridPieces, 2)
				ent = this.gridPieces[i, j]
				ent === nothing && continue
				Scripts.AbilityManagerModule.is_piece_nailed(ent) && continue
				key = _piece_key(ent)
				key == PIECE_SKULL_KEY && continue
				counts[key] = get(counts, key, 0) + 1
				bucket = get!(cells, key) do
					Tuple{Int64,Int64}[]
				end
				push!(bucket, (i, j))
				if !haskey(rarities, key)
					rarity = try
						Float64(ent.scripts[1].pieceData.weight)
					catch
						1.0
					end
					rarities[key] = rarity
				end
			end
		end
		isempty(counts) && return Tuple{Int64,Int64}[]
		best_key = ""
		best_count = 0
		best_rarity = typemax(Float64)
		for (key, n) in counts
			rarity = get(rarities, key, 1.0)
			if n > best_count || (n == best_count && rarity < best_rarity)
				best_key = key
				best_count = n
				best_rarity = rarity
			end
		end
		return get(cells, best_key, Tuple{Int64,Int64}[])
	end

	function replace_most_common_with_skulls!(this)
		selected = _most_common_piece_cells(this)
		isempty(selected) && return
		start_curse_skulls_at_cells!(this, selected)
	end

	function start_birdman_special!(this)
		this.pendingCommonSkullReplace = true
		if !start_animated_rearrange!(this)
			this.pendingCommonSkullReplace = false
			replace_most_common_with_skulls!(this)
		end
	end

	function update_rearrange_animations(this, dt::Float64)
		tweens = this.rearrangeAnimations
		isempty(tweens) && return
		keep = Int[]
		hop = this.gridCellHeight * REARRANGE_HOP
		for i in eachindex(tweens)
			tw = tweens[i]
			tw.elapsed += dt
			if tw.elapsed < tw.delay
				push!(keep, i)
				continue
			end
			t = clamp((tw.elapsed - tw.delay) / tw.duration, 0.0, 1.0)
			eased = ease_in_out_cubic(t)
			nx = tw.start_x + (tw.target_x - tw.start_x) * eased
			ny = tw.start_y + (tw.target_y - tw.start_y) * eased + sin(eased * π) * hop
			try
				tw.entity.transform.position = Math.Vector2f(nx, ny)
			catch e
				@debug "rearrange tween step: $e"
			end
			if t < 1.0
				push!(keep, i)
			else
				try
					tw.entity.transform.position = Math.Vector2f(tw.target_x, tw.target_y)
				catch
				end
			end
		end
		if length(keep) < length(tweens)
			this.rearrangeAnimations = [tweens[i] for i in keep]
		end
		if isempty(this.rearrangeAnimations)
			this.rearranging = false
			if this.pendingCommonSkullReplace
				this.pendingCommonSkullReplace = false
				replace_most_common_with_skulls!(this)
			end
		end
	end

	function set_grid_items_to_switch(this, first, last)
		@debug "setting grid items to switch"
		# Hover wobble offsets transform.position; settle both pieces before reading grid cells.
		Scripts.BattleManagerModule.BattleJuiceModule.cancel_shake!(first)
		Scripts.BattleManagerModule.BattleJuiceModule.cancel_shake!(last)
		Scripts.PieceModule.stop_fall_animation!(first.scripts[1])
		Scripts.PieceModule.stop_fall_animation!(last.scripts[1])
		this.first = first
		this.last = last
		this.switchElapsedTime = 0.0
		try
			globals = JulGame.UserGlobals["Module"]
			globals.AudioManagerModule.play_audio_oneshot(
				globals.get_audio_manager(),
				globals.get_asset_path("sfx", "swappiece"),
				false, 1.0, 0, 1,
			)
		catch
		end
		x1Grid::Int64 = convert(Int64, convert_world_position_to_grid_position(this, this.first.transform.position).x)
		y1Grid::Int64 = convert(Int64, convert_world_position_to_grid_position(this, this.first.transform.position).y)
		x2Grid::Int64 = convert(Int64, convert_world_position_to_grid_position(this, this.last.transform.position).x)
		y2Grid::Int64 = convert(Int64, convert_world_position_to_grid_position(this, this.last.transform.position).y)

		this.gridPieces[x1Grid, y1Grid] = this.last
		this.gridPieces[x2Grid, y2Grid] = this.first

		@debug "grid pieces set to switch"
		if this.first !== nothing && this.last !== nothing
			this.first.scripts[1].gridPosition = Math.Vector2(x2Grid, y2Grid)
			this.last.scripts[1].gridPosition  = Math.Vector2(x1Grid, y1Grid)
			this.firstStart                     = Math.Vector2f(this.first.transform.position.x, this.first.transform.position.y)
			this.lastStart                      = Math.Vector2f(this.last.transform.position.x, this.last.transform.position.y)
			# Player-moved piece lands at (x2,y2) — preferred pattern spawn anchor.
			this.lastSwapAnchor = (convert(Int64, x2Grid), convert(Int64, y2Grid))

			dx = convert(Int64, x2Grid) - convert(Int64, x1Grid)
			dy = convert(Int64, y2Grid) - convert(Int64, y1Grid)
			style = classify_switch_style(dx, dy)
			begin_switch_presentation!(this, style)
			@debug "switch style: $(style) dx=$(dx) dy=$(dy)"

			@debug "updating battle manager state to switching items"
			this.battleManager.currentState = this.battleManager.battleStates[:switchingItems]
		end
	end

	function convert_world_position_to_grid_position(this, world_position)
        localX = (world_position.x - this.gridStartX) / this.gridCellWidth
        localY = (world_position.y - this.gridStartY) / this.gridCellHeight
        xIdx = convert(Int64, round(localX)) + 1
        yIdx = convert(Int64, round(localY)) + 1
		xIdx = clamp(xIdx, 1, this.gridWidth)
		yIdx = clamp(yIdx, 1, this.gridHeight)

        return Math.Vector2f(xIdx, yIdx)
    end

	function _piece_name_after_virtual_swap(this::GridController, i::Int64, j::Int64,
		sx::Int64, sy::Int64, tx::Int64, ty::Int64,
		selected_name::String, target_name::String)::String
		if i == tx && j == ty
			return selected_name
		elseif i == sx && j == sy
			return target_name
		end
		ent = this.gridPieces[i, j]
		return ent === nothing ? "" : string(ent.name)
	end

	"""
	Column segment through `(x, y)` that `search_for_columns_and_rows` would keep, on a virtually
	swapped grid (same rules as live `grid[x, j].name == search_name`).
	"""
	function _virtual_line_path_column(this::GridController, x::Int64, y::Int64, search_name::String,
		sx::Int64, sy::Int64, tx::Int64, ty::Int64, selected_name::String, target_name::String)
		column_path = Set{Tuple{Int64, Int64}}()
		has_seen_start = false
		grid = this.gridPieces
		for j in axes(grid, 2)
			if j == y
				has_seen_start = true
			end
			vname = _piece_name_after_virtual_swap(this, x, j, sx, sy, tx, ty, selected_name, target_name)
			if has_seen_start && (vname == "" || vname != search_name)
				break
			elseif vname != "" && vname == search_name
				push!(column_path, (x, j))
			elseif !has_seen_start && (vname == "" || vname != search_name) && !isempty(column_path)
				column_path = Set{Tuple{Int64, Int64}}()
			end
		end
		if length(column_path) < this.matchThreshold
			return Set{Tuple{Int64, Int64}}()
		end
		return column_path
	end

	"""
	Row segment through `(x, y)` (mirrors `search_for_columns_and_rows` row scan).
	"""
	function _virtual_line_path_row(this::GridController, x::Int64, y::Int64, search_name::String,
		sx::Int64, sy::Int64, tx::Int64, ty::Int64, selected_name::String, target_name::String)
		row_path = Set{Tuple{Int64, Int64}}()
		has_seen_start = false
		grid = this.gridPieces
		for jj in axes(grid, 1)
			if jj == x
				has_seen_start = true
			end
			vname = _piece_name_after_virtual_swap(this, jj, y, sx, sy, tx, ty, selected_name, target_name)
			if has_seen_start && (vname == "" || vname != search_name)
				break
			elseif vname != "" && vname == search_name
				push!(row_path, (jj, y))
			elseif !has_seen_start && (vname == "" || vname != search_name) && !isempty(row_path)
				row_path = Set{Tuple{Int64, Int64}}()
			end
		end
		if length(row_path) < this.matchThreshold
			return Set{Tuple{Int64, Int64}}()
		end
		return row_path
	end

	function _preview_component_key(component::Set{Tuple{Int64, Int64}})::String
		coords = collect(component)
		sort!(coords)
		return join(["$(c[1]):$(c[2])" for c in coords], "|")
	end

	function _preview_alive_enemy_count(this::GridController)::Int64
		n = Int64(0)
		for e in this.battleManager.enemies
			if e.scripts[1].health > 0
				n += 1
			end
		end
		return n
	end

	"""
	Read-only swap preview. Mirrors post-switch `search_for_matches`: only straight
	column/row runs of length ≥ `matchThreshold` through each swapped piece, then
	`find_connected_matches`-style components among those cells (no arbitrary blobs).
	"""
	function get_swap_preview_matches(this::GridController, selected_entity, target_entity)
		if selected_entity === nothing || target_entity === nothing
			return []
		end
		selected_script = selected_entity.scripts[1]
		target_script = target_entity.scripts[1]
		sx = convert(Int64, round(selected_script.gridPosition.x))
		sy = convert(Int64, round(selected_script.gridPosition.y))
		tx = convert(Int64, round(target_script.gridPosition.x))
		ty = convert(Int64, round(target_script.gridPosition.y))
		selected_name = string(selected_entity.name)
		target_name = string(target_entity.name)

		# Same two searches as `collect_column_and_row_paths` for [first, last] after swap.
		searches = ((tx, ty, selected_name), (sx, sy, target_name))
		return _virtual_preview_matches(this, searches, sx, sy, tx, ty, selected_name, target_name)
	end

	"""Read-only Hocus Pocus drop preview: `piece_key` placed at `(x, y)`, modelled as a swap of that cell with itself."""
	get_drop_preview_matches(this::GridController, piece_key::String, x::Int64, y::Int64) =
		_virtual_preview_matches(this, ((x, y, piece_key),), x, y, x, y, piece_key, piece_key)

	function _virtual_preview_matches(this::GridController, searches, sx::Int64, sy::Int64, tx::Int64, ty::Int64,
		selected_name::String, target_name::String)
		positions = Set{Tuple{Int64, Int64}}()
		for (gx, gy, search_name) in searches
			union!(positions, _virtual_line_path_column(this, gx, gy, search_name, sx, sy, tx, ty, selected_name, target_name))
			union!(positions, _virtual_line_path_row(this, gx, gy, search_name, sx, sy, tx, ty, selected_name, target_name))
		end
		if isempty(positions)
			return []
		end

		entity_types = Dict{Tuple{Int64, Int64}, String}()
		for (i, j) in positions
			entity_types[(i, j)] = _piece_name_after_virtual_swap(this, i, j, sx, sy, tx, ty, selected_name, target_name)
		end
		type_groups = group_entities_by_type(entity_types)

		results = []
		seen = Set{String}()
		th = this.matchThreshold
		PM = Scripts.PatternMatchModule
		for (_match_type, pos_set) in type_groups
			visited = Set{Tuple{Int64, Int64}}()
			for pos in pos_set
				if pos in visited
					continue
				end
				component = find_connected_component_flood_fill(pos, pos_set, visited)
				if length(component) < th
					continue
				end
				component_key = _preview_component_key(component)
				if component_key in seen
					continue
				end
				push!(seen, component_key)
				piece_key = entity_types[first(component)]
				action_count = 1 + clamp(length(component) - th, 0, 999)
				comp_cells = Tuple{Int64, Int64}[(convert(Int64, c[1]), convert(Int64, c[2])) for c in component]
				comp = PM.build_match_component(piece_key, comp_cells)
				pattern_kind = PM.preview_pattern_kind(comp, th)
				pattern_label = Scripts.PatternVisualsModule.pattern_overlay_label(pattern_kind)
				push!(results, (
					piece_key = piece_key,
					match_length = length(component),
					action_count = action_count,
					pattern = pattern_kind,
					pattern_label = pattern_label,
				))
			end
		end
		sort!(results, by = r -> r.match_length, rev = true)
		return results
	end

	"""Single-target uses the living selected enemy. AOE sums each living enemy, boosting vulnerable ones."""
	function _preview_attack_line(this::GridController, damage::Int, aoe::Bool)
		PM = Globals.PiecesModule
		bm = this.battleManager
		if bm === nothing
			return damage, aoe ? "DMG (all)" : "DMG"
		end
		if aoe
			alive = [e.scripts[1] for e in bm.enemies if e.scripts[1].health > 0]
			if isempty(alive)
				return damage, "DMG (all)"
			end
			rep = PM.live_enemy_target(bm)
			if rep === nothing || rep.health <= 0
				rep = alive[1]
			end
			stacks = Int(rep.vulnerable)
			if stacks > 0
				return PM.damage_after_vulnerable(damage, stacks), "DMG (all, vuln)"
			end
			return damage, "DMG (all)"
		end
		target = PM.live_enemy_target(bm)
		if target !== nothing && Int(target.vulnerable) > 0
			return PM.damage_after_vulnerable(damage, Int(target.vulnerable)), "DMG (vuln)"
		end
		return damage, "DMG"
	end

	function get_preview_intent_lines(this::GridController, piece_key::String, action_count::Int)
		globals = JulGame.UserGlobals["Module"]
		piece_map = globals.get_piece_data()
		if !haskey(piece_map, piece_key)
			return [(value = Int64(action_count), value_label = "COUNT")]
		end
		piece = piece_map[piece_key]
		user = this.user
		out = Vector{NamedTuple{(:value, :value_label), Tuple{Int64, String}}}()

		if piece_key == "PIECE_DIE"
			lo, hi = Scripts.DieRollAnimatorModule.die_roll_range(action_count)
			push!(out, (value = Int64(lo), value_label = "ROLL $lo-$hi"))
			return out
		end
		if piece_key == "PIECE_REFLECTIVESHIELD"
			push!(out, (value = Int64(min(action_count, 100)), value_label = "REFLECT %"))
			return out
		end
		if piece_key == "PIECE_DODGE"
			pieces = Globals.PiecesModule
			push!(out, (value = Int64(min(pieces.DODGE_PER_MATCH * action_count, pieces.MAX_DODGE_CHANCE)), value_label = "DODGE %"))
			return out
		end
		if piece_key == "PIECE_VAMPIRESWORD"
			raw = Globals.PiecesModule.attack_damage_with_user_stat(user, piece.attack, action_count)
			dmg = Int64(Globals.PiecesModule.effective_attack_damage_after_debuffs(user, raw))
			shown, label = _preview_attack_line(this, dmg, false)
			push!(out, (value = shown, value_label = label))
			return out
		end
		if haskey(Globals.PiecesModule.GEM_GOLD, piece_key)
			push!(out, (value = Int64(Globals.PiecesModule.gem_gold(piece_key, action_count)), value_label = "DOLLARS"))
			return out
		end
		if piece_key == "PIECE_LIGHTNING"
			if piece.attack > 0
				atk_raw = Globals.PiecesModule.attack_damage_with_user_stat(user, piece.attack, action_count)
				atk = Int64(Globals.PiecesModule.effective_attack_damage_after_debuffs(user, atk_raw))
				shown, label = _preview_attack_line(this, atk, Globals.PiecesModule.is_aoe(piece))
				push!(out, (value = shown, value_label = label))
			end
			shock = piece.shock * action_count
			if globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_THUNDERGEM)
				shock += 1
			end
			if shock > 0
				push!(out, (value = Int64(shock), value_label = "SHOCK"))
			end
			return out
		end

		PM = Globals.PiecesModule
		defense_val = PM.piece_shield_amount(piece, user, action_count)
		if defense_val > 0
			push!(out, (value = Int64(defense_val), value_label = "SHIELD"))
		end
		burn_val = piece.burn * action_count
		if burn_val > 0
			push!(out, (value = Int64(burn_val), value_label = "BURN"))
		end
		freeze_val = PM.piece_freeze_amount(piece, action_count)
		if freeze_val > 0
			push!(out, (value = Int64(freeze_val), value_label = "FREEZE"))
		end
		vuln_val = piece.vulnerable * action_count
		if vuln_val > 0
			push!(out, (value = Int64(vuln_val), value_label = PM.is_aoe(piece) ? "VULN (all)" : "VULN"))
		end
		poison_val = piece.poison * action_count
		if poison_val > 0
			push!(out, (value = Int64(poison_val), value_label = "POISON"))
		end
		if piece.heal > 0
			if get(this.persistentStateManager.playerData, "heal_blocked", false)
				push!(out, (value = Int64(0), value_label = "HEAL (blocked)"))
			else
				push!(out, (value = Int64(PM.piece_heal_amount(piece, action_count)), value_label = "HEAL"))
			end
		end
		recoil = piece.attack_self * action_count
		if recoil > 0
			push!(out, (value = Int64(recoil), value_label = "RECOIL"))
		end
		if piece.attack > 0
			atk = PM.piece_attack_damage(piece, user, action_count, _preview_alive_enemy_count(this))
			shown, label = _preview_attack_line(this, atk, PM.is_aoe(piece))
			push!(out, (value = shown, value_label = label))
		end

		if isempty(out)
			push!(out, (value = Int64(action_count), value_label = "COUNT"))
		end
		return out
	end

	function are_grid_pieces_reset(this)
		arePiecesReset = true
		for i in 1:size(this.gridPieces, 1)  # Iterate over columns
			for j in 1:size(this.gridPieces, 2)  # Iterate over rows
				item = this.gridPieces[i, j]
				if item !== nothing
					x = convert_world_position_to_grid_position(this, item.transform.position).x
					y = convert_world_position_to_grid_position(this, item.transform.position).y
					
					# Check if piece is still animating
					if length(item.scripts) > 0 && item.scripts[1].isAnimating
						arePiecesReset = false
						continue
					end
				else
					x = 0
					y = 0
				end
				if item === nothing || x != i || y != j
					if item !== nothing
						# @debug "grid piece $(item.name) at $(i), $(j) is not reset"
						# @debug "needs to get to $(x), $(y) to be reset"
					end
					arePiecesReset = false
				end
			end
		end

		return arePiecesReset
	end

	function check_for_falling_pieces_to_continue_matching(this)
		try
			# Wrapped second blast after settle, before cascade re-search.
			PH = Scripts.PatternHostModule
			PA = Scripts.PatternAnimatorModule
			blast_ents, blast_events = PH.run_second_blast_pass!(this.gridPieces, this.gridWidth, this.gridHeight)
			if !isempty(blast_ents)
				@debug "Pattern second blast clearing $(length(blast_ents)) entities"
				if !isempty(blast_events)
					PH.bind_grid_context!(this)
					this.battleManager.currentState = this.battleManager.battleStates[:searchingForMatches]
					PA.play_events!(blast_events; on_gate = () -> begin
						search_for_matches(this, blast_ents, true, false)
					end)
				else
					search_for_matches(this, blast_ents, true, false)
				end
				this.fallingPieces = []
				return
			end

			@debug "continue to search for matches"
			search_for_matches(this, this.gridPieces)
		catch e
			@error first(string(e), 1000)
		end
		this.fallingPieces = []
	end

	const PIECE_SKULL_KEY = "PIECE_SKULL"
	const CURSE_SKULL_ANIM_DURATION = 0.55

	function spawn_skull_entity_at_world(this, piece_data, gi::Int64, gj::Int64, wx::Float64, wy::Float64, start_scale::Float64)
		crop = Math.Vector4(0, 0, 0, 0)
		newItem = JulGame.EntityModule.Entity(piece_data.key)
		try
			newItem.sprite = JulGame.SpriteModule.InternalSprite(newItem, JulGame.UserGlobals["Module"].get_asset_path("piece", lowercase(split(piece_data.key, "_")[2])), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 150, layer = 2)
		catch e
			@debug "Curse skull sprite fallback: $(e)"
			newItem.sprite = JulGame.SpriteModule.InternalSprite(newItem, JulGame.UserGlobals["Module"].get_asset_path("piece", "error"), crop, false, (255, 255, 255, 255), false; pixelsPerUnit = 8, layer = 2)
		end
		newItem.scripts = [Scripts.PieceModule.Piece(Math.Vector2(gi, gj), piece_data)]
		newItem.scripts[1].parent = newItem
		JulGame.initialize(newItem.scripts[1])
		newItem = JulGame.create_entity(newItem)
		newItem.transform.scale = Math.Vector2f(this.gridCellWidth, this.gridCellHeight)
		set_render_scale!(newItem, start_scale)
		newItem.transform.position = Math.Vector2f(wx, wy)
		return newItem
	end

	function finalize_curse_skull_tween(this, tw::CurseSkullTween)
		ent = tw.entity
		if ent === nothing
			return
		end
		try
			ent.transform.position = Math.Vector2f(tw.target_x, tw.target_y)
			set_render_scale!(ent, 1.0)
			if ent.sprite !== nothing
				ent.sprite.color = (255, 255, 255, 255)
			end
			this.gridPieces[tw.gi, tw.gj] = ent
		catch e
			@debug "finalize_curse_skull_tween: $(e)"
		end
	end

	function update_curse_skull_animations(this::GridController, dt::Float64)
		tweens = this.curseSkullAnimations
		isempty(tweens) && return
		keep = Int[]
		for i in eachindex(tweens)
			tw = tweens[i]
			tw.elapsed += dt
			t = clamp(tw.elapsed / tw.duration, 0.0, 1.0)
			eased = ease_out_cubic(t)
			nx = tw.start_x + (tw.target_x - tw.start_x) * eased
			ny = tw.start_y + (tw.target_y - tw.start_y) * eased
			try
				tw.entity.transform.position = Math.Vector2f(nx, ny)
				set_render_scale!(tw.entity, 0.38 + 0.62 * eased)
			catch e
				@debug "curse skull tween step: $(e)"
			end
			if t >= 1.0
				finalize_curse_skull_tween(this, tw)
			else
				push!(keep, i)
			end
		end
		if length(keep) < length(tweens)
			this.curseSkullAnimations = [tweens[i] for i in keep]
		end
	end

	"""
	Replace `num_skulls` random non-nailed pieces with skulls. Old entities are destroyed; new skulls
	spawn in a tight cluster above the board center and ease into their cells.
	"""
	function start_curse_skull_cluster_animation(this::GridController, num_skulls::Int)
		candidates = Tuple{Int64,Int64}[]
		for i in 1:size(this.gridPieces, 1)
			for j in 1:size(this.gridPieces, 2)
				ent = this.gridPieces[i, j]
				if ent !== nothing && !Scripts.AbilityManagerModule.is_piece_nailed(ent)
					push!(candidates, (i, j))
				end
			end
		end
		n = max(1, num_skulls)
		n = min(n, length(candidates))
		if n == 0 || isempty(candidates)
			return
		end
		shuffle!(candidates)
		selected = candidates[1:n]
		start_curse_skulls_at_cells!(this, selected)
	end

	function start_curse_skulls_at_cells!(this::GridController, selected)
		isempty(selected) && return
		globals = JulGame.UserGlobals["Module"]
		piece_map = globals.get_piece_data()
		if !haskey(piece_map, PIECE_SKULL_KEY)
			@warn "Curse: PIECE_SKULL not in piece data"
			return
		end
		skull_data = piece_map[PIECE_SKULL_KEY]
		cluster_cx = this.gridStartX + (this.gridWidth * this.gridCellWidth) / 2
		cluster_cy = this.gridStartY + (this.gridHeight * this.gridCellHeight) / 2 + this.gridCellHeight * 1.1
		jitter() = (rand() - 0.5) * this.gridCellWidth * 0.42

		for (gi, gj) in selected
			ent_old = this.gridPieces[gi, gj]
			if ent_old !== nothing
				this.gridPieces[gi, gj] = nothing
				try
					JulGame.destroy_entity(MAIN, ent_old)
				catch e
					@debug "Curse destroy old piece: $(e)"
				end
			end
			sx = cluster_cx + jitter()
			sy = cluster_cy + jitter()
			tx = calculate_placement_x(this, gi)
			ty = calculate_placement_y(this, gj)
			sk_ent = spawn_skull_entity_at_world(this, skull_data, gi, gj, sx, sy, 0.38)
			push!(this.curseSkullAnimations, CurseSkullTween(sk_ent, tx, ty, sx, sy, gi, gj, 0.0, CURSE_SKULL_ANIM_DURATION))
		end
	end
end