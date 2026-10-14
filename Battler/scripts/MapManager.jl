module MapManagerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts
    using ..MapFloorSystemModule
    using ..MapSpriteMaskModule
    include("utils/AssetVersioning.jl")
    using .AssetVersioning
    include("MapGenerator.jl")
    using .GridMapGenerator
    include("utils/EnemyCompsConstants.jl")
    using JulGame.EffectsModule
    include("localization/map_strings.jl")
    using .MapStringsModule
    include("utils/Easings.jl")

    # Hover glow effect for map nodes (matches CharacterSelection style)
    const STYLE_MAP_POINT_HOVER = [
        OuterGlowEffect(
            radius=20,
            color=(255,255,200,220),
            fade_amount=1.8,
            fade_curve=15.5,
            force_white=true
        )
    ]

    const MAP_TILE_HOVER_CATEGORIES = ("enemy", "elite", "boss", "shop", "rest", "event", "treasure")

    """
    Queue async baking of the hover glow texture for every map tile variant so
    the first hover is a shared-cache hit instead of a frame spike.
    Idempotent; already-submitted jobs are skipped by the engine.
    """
    function prewarm_hover_effect_textures(theme::MapFloorTheme = floor_theme(1))
        jobs = Tuple{String, Vector{Any}}[]
        for category in MAP_TILE_HOVER_CATEGORIES
            push!(jobs, (map_tile_sprite(theme, category), Any[STYLE_MAP_POINT_HOVER...]))
            push!(jobs, (map_tile_sprite(theme, category; completed = true), Any[STYLE_MAP_POINT_HOVER...]))
        end
        JulGame.SpriteModule.prewarm_effect_textures!(jobs)
    end

    mutable struct MapManager <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        # This is where you define your script's fields
        # Example: speed::Float64
        user

        # Persistent state manager
        persistentStateManager
        floorTheme::MapFloorTheme

        # Tooltip manager
        tooltipManager

        alpha::Int
        fade::Bool

        # Map scrolling
        scrollOffset::Float64
        scrollSpeed::Float64
        minScroll::Float64
        maxScroll::Float64

        # Click and drag scrolling
        isDragging::Bool
        dragStartX
        dragStartCameraX
        dragSensitivity::Float64

        # Y offset for adjusting map position
        yOffset::Float64

        transitionManager

        selectBlocked::Bool

        # Connection tracking for hover states
        connectionEntities::Dict{String, Any}
        hoveredNode::Union{Nothing, String}
        previousHoveredNodes::Set{String}  # Track which nodes were hovered last frame
        
        # Cached entity references for O(1) lookup instead of O(n) search
        mapPointEntities::Dict{String, Any}  # node_id -> entity
        nodeIndexToId::Dict{Int, String}     # index -> node_id for fast reverse lookup
        
        # Node scale animation for hover highlighting
        nodeScales::Dict{String, Float64}      # node_id -> current scale
        nodeTargetScales::Dict{String, Float64}  # node_id -> target scale
        
        # Node flash animation for hover highlighting
        nodeFlashTime::Dict{String, Float64}   # node_id -> accumulated flash time
        nodeIsFlashing::Dict{String, Bool}     # node_id -> whether currently flashing
        nodeHoverEffectsReady::Set{String}     # node_id -> hover glow baked and ready
        nodePulseTime::Float64

        # Player pawn entity
        playerPawnEntity::Union{Nothing, Any}
        
        # Spawn point entity
        spawnPointEntity::Union{Nothing, Any}
        
        # Starting node entity
        startingNodeEntity::Union{Nothing, Any}
        
        # Pawn hop animation state
        isHopping::Bool
        hopped::Bool
        hopStartTime::Float64
        hopDuration::Float64
        hopStartPosition::Math.Vector2f
        hopEndPosition::Math.Vector2f
        hopEncounter::Union{Nothing, Any}  # Store encounter to process after animation
        hopTargetScene::Union{Nothing, String}  # Store target scene name
        originalCameraPosition::Math.Vector3f  # Store original camera position
        originalCameraOffset::Math.Vector2f  # Store original camera offset
        originalCameraZoom::Float64  # Store original camera zoom
        # Hop phases: 1 = ease camera to pawn (prereq), 2 = pawn arc + zoom
        hopPhase::Int
        hopApproachDuration::Float64
        hopCameraApproachTarget::Math.Vector3f

        # Bottom foreground parallax strip (looping tiles)
        fgParallaxEntities::Vector{Any}
        fgParallaxBaseX::Vector{Float64}
        fgParallaxBaseY::Float64
        fgTileWidth::Float64

        # Top canopy strip (world-locked looping tiles, above checkered BG)
        topBgEntities::Vector{Any}
        topBgBaseX::Vector{Float64}
        topBgTileWidth::Float64

        function MapManager()
            this = new() # do not remove this line

            # this is where you initialize your script's fields
            # Example: this.speed = 1.0
            this.alpha = 125
            this.fade = true
            this.floorTheme = floor_theme(1)
            this.fgParallaxEntities = Any[]
            this.fgParallaxBaseX = Float64[]
            this.fgParallaxBaseY = 0.0
            this.fgTileWidth = 1920.0 / JulGame.SCALE_UNITS
            this.topBgEntities = Any[]
            this.topBgBaseX = Float64[]
            this.topBgTileWidth = 1920.0 / JulGame.SCALE_UNITS

            # Initialize scrolling parameters
            this.scrollOffset = 0.0
            this.scrollSpeed = 10.0
            this.minScroll = -5.5  # Adjust based on your map size
            this.maxScroll = 20.0   # Adjust based on your map size

            # Initialize click and drag scrolling
            this.isDragging = false
            this.dragStartX = 0
            this.dragStartCameraX = 0.0
            this.dragSensitivity = 1.5  # Higher = more sensitive panning

            # Shift map nodes up (px) so they clear the lower FG strip
            this.yOffset = 100.0

            this.selectBlocked = false

            # Initialize connection tracking
            this.connectionEntities = Dict{String, Any}()
            this.hoveredNode = nothing
            this.previousHoveredNodes = Set{String}()
            
            # Initialize entity caches
            this.mapPointEntities = Dict{String, Any}()
            this.nodeIndexToId = Dict{Int, String}()
            
            # Initialize node scale tracking
            this.nodeScales = Dict{String, Float64}()
            this.nodeTargetScales = Dict{String, Float64}()
            
            # Initialize node flash tracking
            this.nodeFlashTime = Dict{String, Float64}()
            this.nodeIsFlashing = Dict{String, Bool}()
            this.nodeHoverEffectsReady = Set{String}()
            this.nodePulseTime = 0.0

            # Initialize player pawn
            this.playerPawnEntity = nothing
            
            # Initialize spawn point
            this.spawnPointEntity = nothing
            
            # Initialize starting node
            this.startingNodeEntity = nothing
            
            # Initialize hop animation
            this.isHopping = false
            this.hopped = false
            this.hopStartTime = 0.0
            this.hopDuration = 0.35
            this.hopStartPosition = Math.Vector2f(0, 0)
            this.hopEndPosition = Math.Vector2f(0, 0)
            this.hopEncounter = nothing
            this.hopTargetScene = nothing
            this.originalCameraPosition = Math.Vector3f(0, 0, 0)
            this.originalCameraOffset = Math.Vector2f(0, 0)
            this.originalCameraZoom = 1.0
            this.hopPhase = 0
            this.hopApproachDuration = 0.35
            this.hopCameraApproachTarget = Math.Vector3f(0, 0, 0)

            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # This is where you should register collision events or other events
    # Do not remove this function
    function JulGame.initialize(this::MapManager)
        Scripts.ConsoleIntegrationModule.initialize_console_for_game()
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()
        this.persistentStateManager = globals.get_data_manager().persistent_state_manager
        this.floorTheme = floor_theme(this.persistentStateManager.currentFloor)
        apply_floor_scene_art!(this, this.floorTheme)
        apply_map_camera_zoom!(this)
        setup_foreground_parallax!(this)
        # No-op if already submitted at startup (Title); covers direct map-scene launches
        prewarm_hover_effect_textures(this.floorTheme)

        # Set rich presence with current position if available
        if this.persistentStateManager.currentLevel > 0
            globals.SteamModule.set_rich_presence_with_position(globals.get_steam_data(), "InTheMap", this.persistentStateManager.currentRoom, this.persistentStateManager.currentFloor)
        else
            globals.SteamModule.set_rich_presence(globals.get_steam_data(), "InTheMap")
        end

        # Create and initialize the tooltip manager
        tooltipEntity = JulGame.EntityModule.Entity("TooltipManager")
        tooltipEntity = JulGame.create_entity(tooltipEntity)
        push!(tooltipEntity.scripts, Scripts.TooltipManagerModule.TooltipManager())
        this.tooltipManager = tooltipEntity.scripts[1]

        # Set custom tooltip style if desired
        Scripts.TooltipManagerModule.set_tooltip_style(
            this.tooltipManager,
            hoverDelay = UInt64(120)
        )
        Scripts.PotionTooltipModule.spawn!(this.tooltipManager)

        # start timer 
        timer = time_ns()
        if this.persistentStateManager.mapPoints === nothing ||
           isempty(this.persistentStateManager.mapPoints)
            @debug "Generating map points"
            timer = time_ns()
            generate_map_points(this)
            @debug "Map points generated in $((time_ns() - timer) / 1e9) seconds"
            JulGame.UserGlobals["Module"].SaveManagerModule.try_save_run!()
        elseif this.persistentStateManager.isFloorComplete
            # Update available nodes based on current progress
            @debug "Updating available nodes"
            timer = time_ns()
            update_available_nodes(this)
            @debug "Available nodes updated in $((time_ns() - timer) / 1e9) seconds"
            # Clear selectBlocked when returning from battle after defeating enemy
            this.selectBlocked = false
            globals = JulGame.UserGlobals["Module"]
            globals.SaveManagerModule.try_save_run!()
            # Update sprites for completed nodes
            @debug "Updating completed node sprites"
            timer = time_ns()
            update_completed_node_sprites(this)
            @debug "Completed node sprites updated in $((time_ns() - timer) / 1e9) seconds"
        else
            # Floor not complete - can only replay current node
            this.persistentStateManager.availableNodes = [this.persistentStateManager.currentLevel]
        end
        @debug "Spawning map point entities"
        timer = time_ns()
        spawn_map_point_entities(this)
        @debug "Map point entities spawned in $((time_ns() - timer) / 1e9) seconds"
        @debug "Spawning connection entities"
        timer = time_ns()
        spawn_connection_entities(this)
        @debug "Connection entities spawned in $((time_ns() - timer) / 1e9) seconds"
        @debug "Spawning starting node"
        timer = time_ns()
        spawn_starting_node(this)  # Spawn starting node first
        @debug "Starting node spawned in $((time_ns() - timer) / 1e9) seconds"
        @debug "Spawning starting connections"
        timer = time_ns()
        spawn_starting_connections(this)  # Then its connections
        @debug "Starting connections spawned in $((time_ns() - timer) / 1e9) seconds"
        @debug "Spawning player pawn"
        timer = time_ns()
        spawn_player_pawn(this)
        @debug "Player pawn spawned in $((time_ns() - timer) / 1e9) seconds"
        @debug "Spawning spawn point"
        timer = time_ns()
        spawn_spawn_point(this)
        @debug "Spawn point spawned in $((time_ns() - timer) / 1e9) seconds"
        @debug "Framing map camera"
        timer = time_ns()
        frame_map_camera(this)

        @debug "MapManager initialized in $((time_ns() - timer) / 1e9) seconds"

        try
            this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
        catch e
            @error "SceneTransitionManager not found: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    function apply_floor_scene_art!(this::MapManager, theme::MapFloorTheme)
        for entity in MAIN.scene.entities
            sprite_path = get(theme.sceneArt, entity.name, nothing)
            if sprite_path !== nothing && entity.sprite !== nothing
                entity.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path(sprite_path)
            end
        end
        setup_topbg_parallax!(this, theme)
    end

    const TOPBG_TILE_COUNT = 3

    """Looping canopy strip at the top of the map (tiles the 1920-wide topbg art)."""
    function setup_topbg_parallax!(this::MapManager, theme::MapFloorTheme)
        path = get(theme.sceneArt, "TopBG", nothing)
        path === nothing && return
        path = JulGame.UserGlobals["Module"].get_asset_path(path)

        existing = Any[]
        for entity in MAIN.scene.entities
            entity.name == "TopBG" || continue
            push!(existing, entity)
        end

        while length(existing) < TOPBG_TILE_COUNT
            topbg = JulGame.MainLoopModule.create_new_entity(MAIN)
            topbg.name = "TopBG"
            topbg.transform.position = Math.Vector3f(0.0, 0.0, 0.0)
            topbg.sprite = JulGame.SpriteModule.InternalSprite(
                topbg,
                path,
                Math.Vector4(0, 0, 0, 0),
                false,
                (255, 255, 255, 255),
                false;
                pixelsPerUnit = 0,
                layer = -1,  # Just above checkered BG (-2)
                anchor = :top,
                position = Math.Vector2f(0.0, 0.0),
            )
            push!(existing, topbg)
        end

        tile_w = 1920.0 / JulGame.SCALE_UNITS
        empty!(this.topBgEntities)
        empty!(this.topBgBaseX)
        for i in 1:TOPBG_TILE_COUNT
            entity = existing[i]
            if entity.sprite !== nothing
                entity.sprite.imagePath = path
                entity.sprite.layer = -1
            end
            push!(this.topBgEntities, entity)
            push!(this.topBgBaseX, (i - 1) * tile_w)
        end
        this.topBgTileWidth = tile_w
        update_topbg_parallax!(this)
    end

    function update_topbg_parallax!(this::MapManager)
        isempty(this.topBgEntities) && return

        cam = MAIN.scene.camera
        cam_x = Float64(cam.position.x)
        # World-locked canopy: wrap tiles into view as the camera scrolls, but do not parallax-follow.
        period = this.topBgTileWidth * length(this.topBgEntities)
        period <= 0.0 && return
        min_x = cam_x - this.topBgTileWidth

        for i in eachindex(this.topBgEntities)
            x = this.topBgBaseX[i]
            x -= period * floor((x - min_x) / period)
            this.topBgEntities[i].transform.position = Math.Vector3f(x, 0.0, 0.0)
        end
    end

    """
    apply_zoom_to_center!(camera::Camera, new_zoom::Float64)

    Set `camera.zoom` to `new_zoom` and shift `camera.position` (x, y) so the world point
    that was at the viewport center stays there. `camera.offset` is not modified.
    """
    function apply_zoom_to_center!(camera::JulGame.Camera, new_zoom::Float64)
        S_old = pixels_per_world_unit(camera)
        S_new = JulGame.SCALE_UNITS * new_zoom
        half_w = Float64(camera.size.x) / 2
        half_h = Float64(camera.size.y) / 2
        inv_delta = inv(S_old) - inv(S_new)
        dx = half_w * inv_delta
        dy = half_h * inv_delta
        camera.position = Math.Vector3f(camera.position.x + dx, camera.position.y + dy, camera.position.z)
        camera.zoom = new_zoom
        return camera
    end

    function apply_map_camera_zoom!(this::MapManager)
        cam = MAIN.scene.camera
        target = this.floorTheme.mapZoom
        abs(Float64(cam.zoom) - target) < 1e-4 && return
        apply_zoom_to_center!(cam, target)
    end

    const FOREGROUND_ENTITY_NAME = "mapfab-bottomfgtrees-0000"
    # Above map nodes/pawn/fabs; below modal UI (~500+). Input passes through.
    const FOREGROUND_LAYER = 100

    function setup_foreground_parallax!(this::MapManager)
        empty!(this.fgParallaxEntities)
        empty!(this.fgParallaxBaseX)
        for entity in MAIN.scene.entities
            entity.name == FOREGROUND_ENTITY_NAME || continue
            entity.ignoreInputEvents = true
            if entity.sprite !== nothing
                entity.sprite.layer = FOREGROUND_LAYER
            end
            push!(this.fgParallaxEntities, entity)
            push!(this.fgParallaxBaseX, Float64(entity.transform.position.x))
        end
        isempty(this.fgParallaxEntities) && return

        order = sortperm(this.fgParallaxBaseX)
        this.fgParallaxEntities = this.fgParallaxEntities[order]
        this.fgParallaxBaseX = this.fgParallaxBaseX[order]
        this.fgParallaxBaseY = Float64(this.fgParallaxEntities[1].transform.position.y)

        if length(this.fgParallaxBaseX) >= 2
            this.fgTileWidth = this.fgParallaxBaseX[2] - this.fgParallaxBaseX[1]
        else
            this.fgTileWidth = 1920.0 / JulGame.SCALE_UNITS
        end
        update_foreground_parallax!(this)
    end

    function update_foreground_parallax!(this::MapManager)
        isempty(this.fgParallaxEntities) && return

        cam = MAIN.scene.camera
        cam_x = Float64(cam.position.x)
        cam_y = Float64(cam.position.y)
        S = JulGame.pixels_per_world_unit(cam)
        sprite_h = Float64(this.fgParallaxEntities[1].sprite.size.y)
        # Center-anchored, ppu=0: keep the strip's bottom flush with the viewport bottom
        # even when mapZoom changes (city is zoomed out ~1.5x).
        flush_y = cam_y + Float64(cam.size.y) / S - sprite_h / (2.0 * 64.0) - 0.5
        this.fgParallaxBaseY = flush_y

        factor = this.floorTheme.fgParallaxFactor
        period = this.fgTileWidth * length(this.fgParallaxEntities)
        period <= 0.0 && return
        min_x = cam_x - this.fgTileWidth

        for i in eachindex(this.fgParallaxEntities)
            x = this.fgParallaxBaseX[i]
            if factor > 0.0
                x += cam_x * factor
                x -= period * floor((x - min_x) / period)
            end
            this.fgParallaxEntities[i].transform.position = Math.Vector3f(
                x,
                flush_y,
                0.0,
            )
        end
    end

    function generate_map_points(this)
        @debug("building branching route")
        # Only use branching map in debug mode
        # Generate a branching route using our new method
        route_nodes, starting_points = build_branching_route(
            this.persistentStateManager.currentFloor,
            this.floorTheme,
        )

        # Vertical shift in *pixel* space before converting to world (see spawn_map_point_entities).
        # Center the full route's Y bbox in the viewport. Using only starting_points' average Y
        # skews when those rooms sit in low lanes (small raw y) — shift explodes and the tail/boss drops off-screen.
        vertical_shift = 0
        if !isempty(route_nodes)
            min_raw_y = typemax(Int)
            max_raw_y = typemin(Int)
            for (_, node_data) in route_nodes
                ry = floor(Int, node_data[3])
                min_raw_y = min(min_raw_y, ry)
                max_raw_y = max(max_raw_y, ry)
            end
            # yOffset lifts the route so nodes sit above the lower FG strip.
            desired_center_y = Int(floor(MAIN.scene.camera.size.y / 2 - this.yOffset))
            mid_raw_y = (min_raw_y + max_raw_y) ÷ 2
            vertical_shift = desired_center_y - mid_raw_y
        end

        this.persistentStateManager.mapPoints = Dict()
        this.persistentStateManager.mapConnections = Dict()
        this.persistentStateManager.startingPoints = starting_points

        # Initialize level to 1 if it's not set yet
        if !haskey(this.persistentStateManager.playerData, "currentLevel")
            this.persistentStateManager.currentLevel = 0
        end

        # Apply the same vertical_shift to every node so the whole map moves as one unit
        for (node_id, node_data) in route_nodes
            encounter_data = node_data[1]
            x_pos = floor(Int, node_data[2])
            y_pos = floor(Int, node_data[3]) + vertical_shift
            connections = node_data[4]

            # Determine if the node is enabled (only first node to start, or direct connections from visited nodes)
            enabled = (node_id == 1)  # First node is always enabled

            buttonId = "button_$(node_id)"

            # Add this node to the map points
            this.persistentStateManager.mapPoints[buttonId] = Dict(
                "id" => buttonId,
                "index" => node_id,
                "font" => "Century-Normal.ttf",
                "fontSize" => 24,
                "position" => Math.Vector2(x_pos, y_pos),
                "width" => 200,  # Smaller buttons for a nicer map layout
                "height" => 200,
                "enabled" => enabled,
                "encounter" => encounter_data,
                "completed" => false,
                "connections" => connections
            )
        end

        # Mark all nodes directly connected to the current node as available
        for starting_point in starting_points
            push!(this.persistentStateManager.availableNodes, starting_point)
        end
    end

    function spawn_map_point_entities(this::MapManager)
        # Clear caches before rebuilding
        empty!(this.mapPointEntities)
        empty!(this.nodeIndexToId)
        empty!(this.nodeScales)
        empty!(this.nodeTargetScales)
        empty!(this.nodeFlashTime)
        empty!(this.nodeIsFlashing)
        empty!(this.nodeHoverEffectsReady)
        
        for (node_id, node_data) in this.persistentStateManager.mapPoints
            x_pos = node_data["position"].x / JulGame.SCALE_UNITS
            y_pos = node_data["position"].y / JulGame.SCALE_UNITS
            
            # Check if this node is completed
            node_index = node_data["index"]
            is_completed = node_index in this.persistentStateManager.completedNodes
            
            # Build reverse lookup
            this.nodeIndexToId[node_index] = node_id
            
            # Use completed sprite if the node is completed
            category = lowercase(node_data["encounter"].category)
            path = map_tile_sprite(this.floorTheme, category; completed = is_completed)
            
            new_entity = JulGame.MainLoopModule.create_new_entity(MAIN)
            new_entity.name = "mappoint $(node_id)"
            new_entity.transform.position = Math.Vector3f(x_pos, y_pos, 0)
            new_entity.transform.scale = Math.Vector3f(1.0, 1.0, 1.0)  # Initialize scale
            new_entity.sprite = JulGame.SpriteModule.InternalSprite(
                new_entity,
                path,
                Math.Vector4(0, 0, 0, 0),
                false,
                (255, 255, 255, 255),
                false;
                pixelsPerUnit = 0,
                layer = 16
            )
            
            # Defer expensive glow bake until first actual hover.
            new_entity.sprite.useEffectTexture = false
            
            # Make hitbox smaller for easier clicking of adjacent nodes
            new_entity.sprite.interactionScale = 0.7
            
            new_entity.clickEvents = [() -> handle_clicks(this, node_data)]
            
            # Cache entity reference for O(1) lookup in update loop
            this.mapPointEntities[node_id] = new_entity
            
            # Initialize scale tracking (start at 1.0, target 1.0)
            this.nodeScales[node_id] = 1.0
            this.nodeTargetScales[node_id] = 1.0
            
            # Initialize flash tracking
            this.nodeFlashTime[node_id] = 0.0
            this.nodeIsFlashing[node_id] = false
            
            @debug "spawning point at: $(x_pos),$(y_pos)"
            @debug "connections: $(node_data["connections"])"
        end
    end

    function spawn_connection_entities(this::MapManager)
        # Clear any existing connections
        this.connectionEntities = Dict{String, Any}()
        
        # Iterate through all nodes and create connection entities
        for (node_id, node_data) in this.persistentStateManager.mapPoints
            source_index = node_data["index"]
            source_pos = node_data["position"]
            
            # Draw connections to all connected nodes
            for target_index in node_data["connections"]
                # Find the target node data
                target_node = nothing
                for (tid, tdata) in this.persistentStateManager.mapPoints
                    if tdata["index"] == target_index
                        target_node = tdata
                        break
                    end
                end
                
                if target_node === nothing
                    continue
                end
                
                target_pos = target_node["position"]

                # One sprite per undirected edge (A↔B). Canonical key is lo_to_hi.
                lo, hi = minmax(source_index, target_index)
                source_index == lo || continue
                connection_key = "$(lo)_to_$(hi)"
                haskey(this.connectionEntities, connection_key) && continue
                
                scale = JulGame.SCALE_UNITS
                x1 = Float64(source_pos.x) / scale
                y1 = Float64(source_pos.y) / scale
                x2 = Float64(target_pos.x) / scale
                y2 = Float64(target_pos.y) / scale
                
                # Available if traversable from the current node in either direction
                is_available = (lo == this.persistentStateManager.currentLevel &&
                                hi in this.persistentStateManager.availableNodes) ||
                               (hi == this.persistentStateManager.currentLevel &&
                                lo in this.persistentStateManager.availableNodes)
                sprite_path = map_path_sprite(this.floorTheme, is_available ? :available : :inactive)
                shape = get_sprite_alpha_shape(sprite_path)
                px, py, scale_x, scale_y, angle_deg = path_sprite_placement(shape, x1, y1, x2, y2)
                
                # Create the connection entity
                connection_entity = JulGame.MainLoopModule.create_new_entity(MAIN)
                connection_entity.name = "connection_$(lo)_to_$(hi)"
                connection_entity.transform.position = Math.Vector3f(px, py, 0)
                
                connection_entity.sprite = JulGame.SpriteModule.InternalSprite(
                    connection_entity,
                    sprite_path,
                    Math.Vector4(0, 0, 0, 0),  # No cropping
                    false,
                    (255, 255, 255, 255),
                    false;
                    pixelsPerUnit = 0,
                    layer = 10,
                    rotation = angle_deg
                )
                connection_entity.transform.scale = Math.Vector3f(scale_x, scale_y, 1.0)
                
                this.connectionEntities[connection_key] = Dict(
                    "entity" => connection_entity,
                    "source" => lo,
                    "target" => hi,
                    "is_available" => is_available
                )
                
                @debug "spawning connection from $(lo) to $(hi) at angle $(angle_deg)°"
            end
        end
    end

    function spawn_player_pawn(this::MapManager)
        globals = JulGame.UserGlobals["Module"]
        # Clean up existing pawn if it exists
        if this.playerPawnEntity !== nothing
            # The entity will be cleaned up by the engine
            this.playerPawnEntity = nothing
        end
        
        # Determine pawn position
        pawn_x = 0.0
        pawn_y = 0.0
        
        current_level = this.persistentStateManager.currentLevel
        
        if current_level == 0
            # Player hasn't selected a node yet - position ON the starting node
            if this.startingNodeEntity !== nothing
                pawn_x = this.startingNodeEntity.transform.position.x
                pawn_y = this.startingNodeEntity.transform.position.y
            end
        else
            # Player is on a node - find that node's position
            for (node_id, node_data) in this.persistentStateManager.mapPoints
                if node_data["index"] == current_level
                    pawn_x = node_data["position"].x / JulGame.SCALE_UNITS
                    pawn_y = node_data["position"].y / JulGame.SCALE_UNITS
                    break
                end
            end
        end
        
        # Create the player pawn entity
        pawn_entity = JulGame.MainLoopModule.create_new_entity(MAIN)
        pawn_entity.name = "player_pawn"
        pawn_entity.transform.position = Math.Vector3f(pawn_x, pawn_y, 0)
        pawn_entity.ignoreInputEvents = true
        
        pawn_entity.sprite = JulGame.SpriteModule.InternalSprite(
            pawn_entity,
            globals.get_asset_path("mappawn", String(lowercase(split(this.user.selectedCharacter, "_")[2]))),
            Math.Vector4(0, 0, 0, 0),
            false,
            (255, 255, 255, 255),
            false;
            pixelsPerUnit = 0,
            offset = Math.Vector2f(0.25, -1.75),

            layer = 17  # Above map tiles (11) and connections (10)
        )
        
        # Store reference
        this.playerPawnEntity = pawn_entity
        
        @debug "spawning player pawn at: $(pawn_x), $(pawn_y) (current level: $(current_level))"
    end

    """
    Set camera X so the player pawn is horizontally centered (same framing as hop phase 1).
    """
    const GRAVE_LEFT_MARGIN = 28.0

    function frame_map_camera(this::MapManager)
        if this.persistentStateManager.currentLevel == 0 && this.spawnPointEntity !== nothing
            frame_camera_grave_at_left(this)
        else
            center_camera_x_on_player_pawn(this)
        end
    end

    """
    Opening of a run: the grave sits on the far left, with the route continuing to the right.
    """
    function frame_camera_grave_at_left(this::MapManager)
        grave = this.spawnPointEntity
        grave === nothing && return
        cam = MAIN.scene.camera
        zoom0 = Float64(cam.zoom)
        S0 = JulGame.SCALE_UNITS * zoom0
        S0 <= 0 && return
        gx = Float64(grave.transform.position.x)
        half_w = 64.0
        sprite = grave.sprite
        if sprite !== nothing
            w = Float64(sprite.size.x)
            w > 1 && (half_w = w * S0 / 64.0 / 2)
        end
        screen_x = GRAVE_LEFT_MARGIN + half_w
        target_x = gx - Float64(cam.offset.x) - screen_x / S0
        target_x = clamp(target_x, this.minScroll, this.maxScroll)
        cam.position = Math.Vector3f(target_x, cam.position.y, cam.position.z)
    end

    function center_camera_x_on_player_pawn(this::MapManager)
        if this.playerPawnEntity === nothing
            return
        end
        cam = MAIN.scene.camera
        zoom0 = Float64(cam.zoom)
        S0 = JulGame.SCALE_UNITS * zoom0
        px = Float64(this.playerPawnEntity.transform.position.x)
        target_x = px - Float64(cam.offset.x) - Float64(cam.size.x) / (2 * S0)
        target_x = clamp(target_x, this.minScroll, this.maxScroll)
        cam.position = Math.Vector3f(target_x, cam.position.y, cam.position.z)
    end

    function spawn_spawn_point(this::MapManager)
        # Clean up existing spawn point if it exists
        if this.spawnPointEntity !== nothing
            this.spawnPointEntity = nothing
        end
        
        # Calculate spawn point position (to the left of the starting nodes)
        spawn_x = 0.0
        spawn_y = 0.0
        
        # Find the leftmost nodes (starting positions)
        leftmost_x = Inf
        total_y = 0.0
        count = 0
        
        for (node_id, node_data) in this.persistentStateManager.mapPoints
            x_pos = node_data["position"].x
            if x_pos < leftmost_x + 10  # Within tolerance of leftmost
                if x_pos < leftmost_x
                    leftmost_x = x_pos
                    total_y = node_data["position"].y
                    count = 1
                else
                    total_y += node_data["position"].y
                    count += 1
                end
            end
        end
        
        if count > 0
            spawn_x = (leftmost_x - 300) / JulGame.SCALE_UNITS  # Further left than the leftmost nodes
            # Match node 0 (starting pedestal) on Y — previously used leftmost-node average and sat off-kilter.
            if this.startingNodeEntity !== nothing
                spawn_y = Float64(this.startingNodeEntity.transform.position.y)
            else
                spawn_y = total_y / count / JulGame.SCALE_UNITS
            end
        end
        
        # Create the spawn point entity
        spawn_entity = JulGame.MainLoopModule.create_new_entity(MAIN)
        spawn_entity.name = "spawn_point"
        spawn_entity.transform.position = Math.Vector3f(spawn_x, spawn_y, 0)
        spawn_entity.ignoreInputEvents = true
        
        spawn_entity.sprite = JulGame.SpriteModule.InternalSprite(
            spawn_entity,
            JulGame.UserGlobals["Module"].get_asset_path(this.floorTheme.spawnPointSprite),
            Math.Vector4(0, 0, 0, 0),
            false,
            (255, 255, 255, 255),
            false;
            pixelsPerUnit = 0,
            layer = 11  # Same layer as map tiles
        )
        
        # Store reference
        this.spawnPointEntity = spawn_entity
        
        @debug "spawning spawn point at: $(spawn_x), $(spawn_y)"
    end

    function spawn_starting_node(this::MapManager)
        # Clean up existing starting node if it exists
        if this.startingNodeEntity !== nothing
            this.startingNodeEntity = nothing
        end
        
        # Calculate starting node position (between spawn point and first available nodes)
        starting_x = 0.0
        starting_y = 0.0
        
        # Leftmost map column X for horizontal placement; Y = viewport vertical center in world units (~9 when height ≈ 1152)
        leftmost_x = Inf
        for (_, node_data) in this.persistentStateManager.mapPoints
            x_pos = node_data["position"].x
            if x_pos < leftmost_x
                leftmost_x = x_pos
            end
        end
        
        if leftmost_x < Inf
            center_y_px = Int(floor(MAIN.scene.camera.size.y / 2 - this.yOffset))
            starting_y = center_y_px / JulGame.SCALE_UNITS
            starting_x = (leftmost_x - 150) / JulGame.SCALE_UNITS  # Halfway between spawn point (-300) and first nodes
        end
        
        # Create the starting node entity
        starting_entity = JulGame.MainLoopModule.create_new_entity(MAIN)
        starting_entity.name = "starting_node"
        starting_entity.transform.position = Math.Vector3f(starting_x, starting_y, 0)
        starting_entity.ignoreInputEvents = true  # Decorative only
        
        starting_entity.sprite = JulGame.SpriteModule.InternalSprite(
            starting_entity,
            JulGame.UserGlobals["Module"].get_asset_path(this.floorTheme.startingTileSprite),
            Math.Vector4(0, 0, 0, 0),
            false,
            (255, 255, 255, 255),
            false;
            pixelsPerUnit = 0,
            layer = 11  # Same layer as map tiles
        )
        
        # Store reference
        this.startingNodeEntity = starting_entity
        
        @debug "spawning starting node at: $(starting_x), $(starting_y)"
    end

    function spawn_starting_connections(this::MapManager)
        if this.startingNodeEntity === nothing
            @debug "Starting node entity is nothing, skipping connections"
            return
        end
        
        if this.persistentStateManager.mapPoints === nothing || isempty(this.persistentStateManager.mapPoints)
            @debug "No map points available, skipping starting connections"
            return
        end
        
        starting_pos = this.startingNodeEntity.transform.position
        @debug "Starting node position: $(starting_pos.x), $(starting_pos.y)"
        
        # Use the initial starting points that were set during map generation
        # These should never change regardless of player progression
        starting_node_indices = this.persistentStateManager.startingPoints
        
        @debug "Connecting to $(length(starting_node_indices)) starting nodes: $(starting_node_indices)"
        
        # Create connections from starting node to each available starting node
        for node_index in starting_node_indices
            # Find the node data by index
            target_node = nothing
            for (node_id, node_data) in this.persistentStateManager.mapPoints
                if node_data["index"] == node_index
                    target_node = node_data
                    break
                end
            end
            
            if target_node === nothing
                @warn "Could not find node with index $(node_index)"
                continue
            end
            target_pos = target_node["position"]
            
            scale = JulGame.SCALE_UNITS
            x1 = Float64(starting_pos.x)
            y1 = Float64(starting_pos.y)
            x2 = Float64(target_pos.x) / scale
            y2 = Float64(target_pos.y) / scale
            
            # Show as available only if player hasn't moved yet (currentLevel == 0)
            is_available = this.persistentStateManager.currentLevel == 0
            sprite_path = map_path_sprite(this.floorTheme, is_available ? :available : :inactive)
            shape = get_sprite_alpha_shape(sprite_path)
            px, py, scale_x, scale_y, angle_deg = path_sprite_placement(shape, x1, y1, x2, y2)
            
            # Create the connection entity
            connection_entity = JulGame.MainLoopModule.create_new_entity(MAIN)
            connection_entity.name = "starting_connection_to_$(target_node["index"])"
            connection_entity.transform.position = Math.Vector3f(px, py, 0)
            
            connection_entity.sprite = JulGame.SpriteModule.InternalSprite(
                connection_entity,
                sprite_path,
                Math.Vector4(0, 0, 0, 0),
                false,
                (255, 255, 255, 255),
                false;
                pixelsPerUnit = 0,
                layer = 10,
                rotation = angle_deg
            )
            connection_entity.transform.scale = Math.Vector3f(scale_x, scale_y, 1.0)
            
            @debug "spawning starting connection to node $(target_node["index"])"
        end
    end

    function update_player_pawn_position(this::MapManager)
        # Don't update position if hopping animation is active
        if this.isHopping
            return
        end
        
        if this.playerPawnEntity === nothing
            return
        end
        
        current_level = this.persistentStateManager.currentLevel
        
        # O(1) lookup using cached index -> node_id map
        node_id = get(this.nodeIndexToId, current_level, nothing)
        if node_id !== nothing
            node_data = this.persistentStateManager.mapPoints[node_id]
            pawn_x = node_data["position"].x / JulGame.SCALE_UNITS
            pawn_y = node_data["position"].y / JulGame.SCALE_UNITS
            this.playerPawnEntity.transform.position = Math.Vector3f(pawn_x, pawn_y, 0)
        end
    end
    
    """
    Start the hop animation when moving to a new node
    """
    function start_hop_animation(this::MapManager, start_node_index::Int, target_node_index::Int, encounter, target_scene::Union{Nothing, String})
        if this.playerPawnEntity === nothing
            return
        end
        
        # Get start position (handle level 0 special case)
        if start_node_index == 0
            # Starting from the starting node entity
            if this.startingNodeEntity === nothing
                @debug "Hop animation failed: starting node entity is nothing"
                return
            end
            this.hopStartPosition = Math.Vector2f(
                this.startingNodeEntity.transform.position.x,
                this.startingNodeEntity.transform.position.y
            )
        else
            # Starting from a regular map node
            start_node_id = get(this.nodeIndexToId, start_node_index, nothing)
            if start_node_id === nothing
                @debug "Hop animation failed: start node ID not found for index $start_node_index"
                return
            end
            start_node_data = this.persistentStateManager.mapPoints[start_node_id]
            this.hopStartPosition = Math.Vector2f(
                start_node_data["position"].x / JulGame.SCALE_UNITS,
                start_node_data["position"].y / JulGame.SCALE_UNITS
            )
        end
        
        # Get end position
        end_node_id = get(this.nodeIndexToId, target_node_index, nothing)
        if end_node_id === nothing
            @debug "Hop animation failed: end node ID not found for index $target_node_index"
            return
        end
        end_node_data = this.persistentStateManager.mapPoints[end_node_id]
        this.hopEndPosition = Math.Vector2f(
                end_node_data["position"].x / JulGame.SCALE_UNITS,
                end_node_data["position"].y / JulGame.SCALE_UNITS
        )
        
        # Store encounter and scene for after animation
        this.hopEncounter = encounter
        this.hopTargetScene = "$(target_scene):$(encounter.category)"
        
        # Store original camera state
        this.originalCameraPosition = MAIN.scene.camera.position
        this.originalCameraOffset = MAIN.scene.camera.offset
        this.originalCameraZoom = MAIN.scene.camera.zoom
        
        # Initialize animation (phase 1: ease camera to player; phase 2: pawn moves)
        this.isHopping = true
        this.hopped = true
        this.hopStartTime = 0.0
        this.hopPhase = 1
        
        # Set pawn to start position; it stays here until phase 2
        this.playerPawnEntity.transform.position = Math.Vector3f(this.hopStartPosition.x, this.hopStartPosition.y, 0)
        
        cam = MAIN.scene.camera
        zoom0 = Float64(this.originalCameraZoom)
        S0 = JulGame.SCALE_UNITS * zoom0
        px = Float64(this.hopStartPosition.x)
        py = Float64(this.hopStartPosition.y)
        tx = px - Float64(cam.offset.x) - Float64(cam.size.x) / (2 * S0)
        ty = py - Float64(cam.offset.y) - Float64(cam.size.y) / (2 * S0)
        this.hopCameraApproachTarget = Math.Vector3f(tx, ty, Float64(cam.position.z))
        
        @debug "Started hop animation from node $start_node_index to $target_node_index"
        @debug "Start position: $(this.hopStartPosition), End position: $(this.hopEndPosition)"
    end
    
    """
    Update the hop animation each frame
    """
    function update_hop_animation(this::MapManager, deltaTime::Float64)
        if !this.isHopping || this.playerPawnEntity === nothing
            return
        end
        
        this.hopStartTime += deltaTime
        
        cam = MAIN.scene.camera
        
        if this.hopPhase == 1
            cam.zoom = this.originalCameraZoom
            ta = min(this.hopStartTime / this.hopApproachDuration, 1.0)
            u = ease_in_out_cubic(ta)
            from = this.originalCameraPosition
            to = this.hopCameraApproachTarget
            cam.position = Math.Vector3f(
                from.x + (to.x - from.x) * u,
                from.y + (to.y - from.y) * u,
                from.z + (to.z - from.z) * u,
            )
            this.playerPawnEntity.transform.position = Math.Vector3f(this.hopStartPosition.x, this.hopStartPosition.y, 0)
            if this.playerPawnEntity.sprite !== nothing
                this.playerPawnEntity.sprite.rotation = 0.0
            end
            if ta < 0.5
                return
            end
            this.hopPhase = 2
            this.hopStartTime = 0.0
        end
        
        t = min(this.hopStartTime / this.hopDuration, 1.0)
        
        # Debug output every 0.5 seconds
        if floor(this.hopStartTime * 2) != floor((this.hopStartTime - deltaTime) * 2)
            @debug "Hop animation: t=$t, time=$(this.hopStartTime)"
        end
        
        # Path progress: symmetric ease so takeoff and landing match a ∩ (upside-down U) silhouette
        path_t = ease_in_out_sine(t)
        base_x = this.hopStartPosition.x + (this.hopEndPosition.x - this.hopStartPosition.x) * path_t
        base_y = this.hopStartPosition.y + (this.hopEndPosition.y - this.hopStartPosition.y) * path_t
        
        # Vertical lift: parabolic bump 4·u(1−u), tied to path_t so the apex sits midway along the chord
        arc_height = 0.32
        arc_u = path_t
        arc_offset = arc_height * (4 * arc_u * (1 - arc_u))
        current_x = base_x
        current_y = base_y + arc_offset
        
        # Update pawn position
        this.playerPawnEntity.transform.position = Math.Vector3f(current_x, current_y, 0)
        
        # Add rotation (puppet-like wobble)
        # Rotate back and forth as it moves
        rotation_amount = 5.0  # Max rotation in degrees
        rotation_phase = t * 2.0  # Speed of rotation
        rotation = sin(rotation_phase * π) * rotation_amount
        if this.playerPawnEntity.sprite !== nothing
            this.playerPawnEntity.sprite.rotation = rotation
        end
        
        # Zoom and framing: keep pawn pinned to screen center every frame. Lerping position while zoom
        # changes makes the follow target drift and reads as "snap to player, then zoom".
        zoom_u = t  # ease zoom across the whole hop (no early finish)
        zoom_progress = ease_in_out_sine(zoom_u)
        zoom_depth = 0.45  # added to pre-hop zoom by end of phase 2
        zoom_factor = Float64(this.originalCameraZoom) + zoom_depth * zoom_progress
        cam.zoom = zoom_factor
        S = JulGame.SCALE_UNITS * zoom_factor
        pawn_pos = this.playerPawnEntity.transform.position
        target_x = Float64(pawn_pos.x) - Float64(cam.offset.x) - Float64(cam.size.x) / (2 * S)
        target_y = Float64(pawn_pos.y) - Float64(cam.offset.y) - Float64(cam.size.y) / (2 * S)
        cam.position = Math.Vector3f(target_x, target_y, cam.position.z)
        
        if t >= 1.0
            complete_hop_animation(this)
        end
    end
    
    """
    Complete the hop animation and trigger the fade transition
    """
    function complete_hop_animation(this::MapManager)
        this.isHopping = false
        this.hopPhase = 0
        
        # Reset pawn rotation
        if this.playerPawnEntity !== nothing && this.playerPawnEntity.sprite !== nothing
            this.playerPawnEntity.sprite.rotation = 0.0
        end
        
        # Update pawn to final position
        update_player_pawn_position(this)
        
        # Trigger the fade transition
        if this.hopTargetScene !== nothing
            Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, this.hopTargetScene; direction = Scripts.SceneTransitionModule.Fade)
        end
        
        # Clear stored data
        this.hopEncounter = nothing
        this.hopTargetScene = nothing
    end

    function update_connection_sprites(this::MapManager, hovered_node_id::String, is_hovering::Bool)
        # O(1) hash lookup instead of O(n) iteration
        node_data = get(this.persistentStateManager.mapPoints, hovered_node_id, nothing)
        if node_data === nothing
            return
        end
        hovered_index = node_data["index"]
        
        # Check if this node is available
        is_available = hovered_index in this.persistentStateManager.availableNodes
        if !is_available && !JulGame.IS_DEBUG
            return  # Don't highlight connections to unavailable nodes
        end
        
        # Update connections between the current node and the hovered node
        current_level = this.persistentStateManager.currentLevel
        lo, hi = minmax(current_level, hovered_index)
        connection_key = "$(lo)_to_$(hi)"
        
        if haskey(this.connectionEntities, connection_key)
            conn_data = this.connectionEntities[connection_key]
            if conn_data["is_available"]
                sprite_path = map_path_sprite(this.floorTheme, is_hovering ? :highlighted : :available)
                # Update the sprite path
                conn_data["entity"].sprite.imagePath = sprite_path
            end
        end
    end

    function update_all_connection_sprites(this::MapManager)
        # Update all connection sprites based on current game state
        current_level = this.persistentStateManager.currentLevel
        
        for (connection_key, conn_data) in this.connectionEntities
            source_index = conn_data["source"]
            target_index = conn_data["target"]
            
            # Undirected: available if current node can traverse this edge either way
            is_available = (source_index == current_level &&
                            target_index in this.persistentStateManager.availableNodes) ||
                           (target_index == current_level &&
                            source_index in this.persistentStateManager.availableNodes)
            
            # Update the sprite path
            sprite_path = map_path_sprite(this.floorTheme, is_available ? :available : :inactive)
            conn_data["entity"].sprite.imagePath = sprite_path
            conn_data["is_available"] = is_available
        end
    end

    function update_completed_node_sprites(this::MapManager)
        # Update sprites for all completed nodes using cached entity references
        for (node_id, node_data) in this.persistentStateManager.mapPoints
            node_index = node_data["index"]
            if node_index in this.persistentStateManager.completedNodes
                # Use cached entity lookup (O(1) instead of O(n))
                entity = get(this.mapPointEntities, node_id, nothing)
                
                if entity !== nothing && entity.sprite !== nothing
                    # Update to completed sprite
                    category = lowercase(node_data["encounter"].category)
                    completed_path = map_tile_sprite(this.floorTheme, category; completed = true)
                    entity.sprite.imagePath = completed_path
                end
            end
        end
    end

    function update_node_scale_animations(this::MapManager, deltaTime::Float64)
        # Animate node scales with different speeds for hover vs unhover
        for (node_id, entity) in this.mapPointEntities
            current_scale = get(this.nodeScales, node_id, 1.0)
            target_scale = get(this.nodeTargetScales, node_id, 1.0)
            
            if abs(current_scale - target_scale) > 0.001
                # Determine lerp speed based on direction
                if target_scale > current_scale
                    # Hovering: instant increase (fast)
                    lerp_speed = 20.0 * deltaTime
                else
                    # Unhovering: slow decrease with easing (smooth)
                    lerp_speed = 2.5 * deltaTime
                end
                
                # Apply lerp with easing for unhover (ease-out)
                diff = target_scale - current_scale
                if target_scale < current_scale
                    # Ease-out cubic for smooth unhover
                    t = min(lerp_speed, 1.0)
                    eased_t = 1.0 - (1.0 - t)^3
                    new_scale = current_scale + diff * eased_t
                else
                    # Linear for instant hover
                    new_scale = current_scale + diff * min(lerp_speed, 1.0)
                end
                
                this.nodeScales[node_id] = new_scale
                set_node_scale!(entity, new_scale)
            else
                # Snap to target if very close
                this.nodeScales[node_id] = target_scale
                set_node_scale!(entity, target_scale)
            end
        end
    end

    """Hover/pulse scale, drawn about the node's center."""
    function set_node_scale!(entity, s::Float64)
        (entity === nothing || entity.sprite === nothing) && return
        entity.sprite.renderScale = Math.Vector2f(s, s)
    end

    function update_node_flash_animations(this::MapManager, deltaTime::Float64)
        # Animate node flash effect (brightness pulse) for hovered nodes
        for (node_id, entity) in this.mapPointEntities
            is_flashing = get(this.nodeIsFlashing, node_id, false)
            
            if is_flashing && entity !== nothing && entity.sprite !== nothing
                # Update flash time
                flash_time = get(this.nodeFlashTime, node_id, 0.0)
                flash_time += deltaTime * 1.0  # Flash speed (higher = faster)
                this.nodeFlashTime[node_id] = flash_time
                
                # Calculate flash brightness using sine wave (oscillates between 0.7 and 1.0)
                flash_value = 0.85 + 0.15 * sin(flash_time * 2 * π)
                
                # Apply brightness by modulating color (bright yellow-white pulse)
                base_brightness = round(Int, 255 * flash_value)
                # Add slight yellow tint when brighter
                yellow_boost = round(Int, 40 * (flash_value - 0.85) / 0.15)
                r = min(255, base_brightness + yellow_boost)
                g = min(255, base_brightness + yellow_boost)
                b = base_brightness
                
                entity.sprite.color = (r, g, b, 255)
            end
        end
    end

    const NODE_IDLE_COLOR = (255, 255, 255, 255)
    const NODE_DIM_COLOR = (145, 145, 145, 255)

    """
    Next nodes breathe in scale. Every other node is gray, except the one you are on.
    Hover still owns scale and the flash color.
    """
    function update_node_route_presentation(this::MapManager, deltaTime::Float64)
        this.nodePulseTime += deltaTime
        pulse = 1.0 + 0.08 * sin(this.nodePulseTime * 2π * 0.85)
        available = this.persistentStateManager.availableNodes
        available === nothing && (available = Int[])
        current = this.persistentStateManager.currentLevel
        points = this.persistentStateManager.mapPoints
        points === nothing && return

        for (node_id, entity) in this.mapPointEntities
            node_data = get(points, node_id, nothing)
            node_data === nothing && continue
            index = node_data["index"]
            is_next = index != current && index in available
            hovered = node_id in this.previousHoveredNodes
            flashing = get(this.nodeIsFlashing, node_id, false)

            if entity.sprite !== nothing && !flashing
                entity.sprite.color = (is_next || hovered || index == current) ? NODE_IDLE_COLOR : NODE_DIM_COLOR
            end

            hovered && continue
            is_next || continue
            this.nodeScales[node_id] = pulse
            set_node_scale!(entity, pulse)
        end
    end

    function JulGame.update(this::MapManager, deltaTime)
        # Clear selectBlocked when floor is complete (enemy defeated)
        if this.persistentStateManager.isFloorComplete && this.selectBlocked
            this.selectBlocked = false
        end
        
        # Handle click and drag panning (disabled during hop animation)
        if !this.hopped
            mouse_pos = JulGame.InputModule.get_mouse_position()
            
            if JulGame.InputModule.get_mouse_button_pressed(1)
                # Start dragging
                this.isDragging = true
                this.dragStartX = mouse_pos.x
                this.dragStartCameraX = MAIN.scene.camera.position.x
            elseif JulGame.InputModule.get_mouse_button_released(1)
                # Stop dragging
                this.isDragging = false
            end
            
            if this.isDragging
                # Calculate drag delta and update camera
                drag_delta = (mouse_pos.x - this.dragStartX) * this.dragSensitivity
                ppwu = JulGame.pixels_per_world_unit(MAIN.scene.camera)
                new_camera_x = this.dragStartCameraX - drag_delta / ppwu
                
                # Apply camera position with bounds
                new_camera_x = clamp(new_camera_x, this.minScroll, this.maxScroll)
                MAIN.scene.camera.position = Math.Vector3f(new_camera_x, MAIN.scene.camera.position.y, MAIN.scene.camera.position.z)
            end
            
            # Handle keyboard input for scrolling (only when not dragging)
            if !this.isDragging
                dx = 0.0
                if JulGame.InputModule.get_button_held_down("Left") || JulGame.InputModule.get_button_held_down("A")
                    dx = -this.scrollSpeed * deltaTime
                elseif JulGame.InputModule.get_button_held_down("Right") || JulGame.InputModule.get_button_held_down("D")
                    dx = this.scrollSpeed * deltaTime
                end
                if dx != 0.0
                    cam = MAIN.scene.camera
                    new_x = clamp(cam.position.x + dx, this.minScroll, this.maxScroll)
                    cam.position = Math.Vector3f(new_x, cam.position.y, cam.position.z)
                end
            end
        end

        update_foreground_parallax!(this)
        update_topbg_parallax!(this)

        # # add a button to the bottom left of the screen to regen the map
        if JulGame.IS_DEBUG
            Scripts.NineSliceUIModule.immediate_button(
                "regen_map",
                () -> begin
                    @debug("Regenerating map")
                    generate_map_points(this)
                    spawn_map_point_entities(this)  # Must call to rebuild entity caches
                    spawn_connection_entities(this)
                    spawn_starting_node(this)
                    spawn_starting_connections(this)
                    spawn_player_pawn(this)
                    center_camera_x_on_player_pawn(this)
                end;
                text = MapStringsModule.MAP_STRINGS[:map_regen_button],
                fontSize = 24,
                size = Math.Vector2(150, 50),
                anchor = :bottomLeft,
                anchorOffset = Math.Vector2(10, 10),
                layer = 12
            )
        end

        current_level_x = -9999

        # Check entity hover states using cached references (O(n) instead of O(n*m))
        # Reuse the set by clearing instead of allocating new
        new_hovered = Set{String}()
        globals = JulGame.UserGlobals["Module"]
        
        for (node_id, entity) in this.mapPointEntities
            if entity.isHovered
                push!(new_hovered, node_id)
                # Trigger hover enter if not previously hovered
                if !(node_id in this.previousHoveredNodes)
                    this.hoveredNode = node_id
                    update_connection_sprites(this, node_id, true)
                    # Set target scale to hover size (instant increase)
                    this.nodeTargetScales[node_id] = 1.15
                    # Enable glow effect (like CharacterSelection)
                    if entity.sprite !== nothing
                        if !(node_id in this.nodeHoverEffectsReady)
                            JulGame.apply_effects!(entity.sprite, STYLE_MAP_POINT_HOVER)
                            push!(this.nodeHoverEffectsReady, node_id)
                        end
                        entity.sprite.useEffectTexture = true
                        # Shrink hitbox to compensate for enlarged sprite (0.7 / 1.15 ≈ 0.609)
                        entity.sprite.interactionScale = 0.5
                    end
                    # Start flashing effect
                    this.nodeIsFlashing[node_id] = true
                    this.nodeFlashTime[node_id] = 0.0
                    # Play hover sound
                    globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "hovernewgame"), false, 0.01, 0, 1)
                end
            elseif node_id in this.previousHoveredNodes
                # Trigger hover exit
                if this.hoveredNode == node_id
                    this.hoveredNode = nothing
                    update_connection_sprites(this, node_id, false)
                end
                # Disable glow effect and restore hitbox size
                if entity.sprite !== nothing
                    entity.sprite.useEffectTexture = false
                    entity.sprite.interactionScale = 0.7  # Restore normal hitbox
                end
                # Stop flashing effect and reset color
                this.nodeIsFlashing[node_id] = false
                if entity.sprite !== nothing
                    entity.sprite.color = (255, 255, 255, 255)
                end
                # Set target scale back to normal (slow decrease)
                this.nodeTargetScales[node_id] = 1.0
            end
        end
        # Swap references instead of copying
        this.previousHoveredNodes = new_hovered
        
        # Update node scale animations
        update_node_scale_animations(this, deltaTime)
        
        # Update node flash animations
        update_node_flash_animations(this, deltaTime)
        update_node_route_presentation(this, Float64(deltaTime))
        
        # Update pawn hop animation
        if this.isHopping
            update_hop_animation(this, deltaTime)
        end

        # # Find current hovered encounter or default text
        current_tooltip_text = MapStringsModule.MAP_STRINGS[:map_tooltip_default]
        if this.hoveredNode !== nothing && haskey(this.persistentStateManager.mapPoints, this.hoveredNode)
            node_data = this.persistentStateManager.mapPoints[this.hoveredNode]
            encounter = node_data["encounter"]
            current_tooltip_text = get_encounter_tooltip_text(
                encounter;
                psm = this.persistentStateManager,
                node_index = node_data["index"],
                available_nodes = this.persistentStateManager.availableNodes,
            )
        end

         # # Display persistent tooltip at bottom of screen
         tooltip_width = 800
         tooltip_height = 120
         tooltip_x = (1920 - tooltip_width) / 2  # Center horizontally
         tooltip_y = 1080 - tooltip_height - 20  # Bottom of screen with padding
        Scripts.NineSliceUIModule.immediate_panel(
            "persistent_tooltip_bg";
            position = Math.Vector2(tooltip_x, tooltip_y),
            size = Math.Vector2(tooltip_width, tooltip_height),
            color = (0, 0, 0, 200),  # Black with transparency
            border_color = (255, 255, 255, 255),  # White border
            fill_alpha = 255,
            layer = 15
        )

        # Tooltip text
        DisplayTextModule.display_text(
            "persistent_tooltip_text",
            current_tooltip_text;
            position = Math.Vector2(tooltip_x + 20, tooltip_y + 20),
            fontSize = 18,
            color = (255, 255, 255, 255),  # White text
            layer = 17
        )
    end

    # This is called when the script is removed from an entity (scene change, entity deletion)
    # Do not remove this function
    function JulGame.on_shutdown(this::MapManager)
        # Clean up connection entities
        this.connectionEntities = Dict{String, Any}()
        # Clean up player pawn
        this.playerPawnEntity = nothing
        # Clean up spawn point
        this.spawnPointEntity = nothing
        # Clean up starting node
        this.startingNodeEntity = nothing
        # Clean up entity caches
        empty!(this.mapPointEntities)
        empty!(this.nodeIndexToId)
        empty!(this.nodeScales)
        empty!(this.nodeTargetScales)
        empty!(this.nodeFlashTime)
        empty!(this.nodeIsFlashing)
    end

    function handle_clicks(this::MapManager, node_data)
        # Do not allow clicking new nodes while the pawn is mid-hop
        if this.isHopping
            @debug("Ignoring map click while pawn is hopping")
            return
        end

        globals = JulGame.UserGlobals["Module"]
        @debug("Handling clicks for node $(node_data)")
        node_index = node_data["index"]
        # Only allow clicking if the node is in availableNodes
        if !(node_index in this.persistentStateManager.availableNodes) && !JulGame.IS_DEBUG
            @debug("Node $(node_index) is not available for travel.")
            return
        end
        if this.selectBlocked && !JulGame.IS_DEBUG
            @debug("Node $(node_index) is blocked.")
            return
        end
        #@debug("Handling clicks for node $(node_data)")
        encounter = node_data["encounter"]
        encounter = apply_tutorial_regular_map_encounter_enemies(encounter, this.persistentStateManager, globals)
        
        # Store old level before updating
        old_level = this.persistentStateManager.currentLevel
        is_moving_to_new_node = node_index != old_level

        # Update the current level to this node
        if is_moving_to_new_node
            push!(this.persistentStateManager.completedNodes, old_level)
            this.persistentStateManager.currentRoom += 1
        end
        this.persistentStateManager.currentLevel = node_index

        # Update rich presence with new position
        globals = JulGame.UserGlobals["Module"]
        globals.SteamModule.set_rich_presence_with_position(globals.get_steam_data(), "InTheMap", this.persistentStateManager.currentRoom, this.persistentStateManager.currentFloor)

        # Update available nodes for the new position
        update_available_nodes(this)
        this.persistentStateManager.isFloorComplete = false
        # Process the encounter
        this.persistentStateManager.currentEvent = encounter
        if encounter.type == "Battle"
            this.persistentStateManager.currentEnemies = encounter.enemies
        end
        globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1);
        this.selectBlocked = true
        is_moving_to_new_node && globals.RunRecorderModule.node_selected!(encounter)
        
        globals.SaveManagerModule.try_save_run!()
        
        # Check if moving to a new node - if so, start hop animation
        if is_moving_to_new_node
            # Store encounter and target scene for after animation
            target_scene = nothing
            if encounter.type == "Battle"
                target_scene = "battle.json"
            elseif encounter.type == "Event"
                if encounter.category == "shop"
                    target_scene = resolve_shop_scene(this.persistentStateManager === nothing ? 0 : this.persistentStateManager.seed, node_index)
                elseif encounter.category == "rest"
                    target_scene = "rest.json"
                else
                    target_scene = "event.json"
                end
            elseif encounter.type == "Treasure"
                target_scene = "event.json"
            end
            
            # Start hop animation (pass old_level so it uses the correct start position)
            start_hop_animation(this, old_level, node_index, encounter, target_scene)
        else
            # Same node, no animation needed
            update_player_pawn_position(this)
            if encounter.type == "Treasure"
                Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "event.json"; direction = Scripts.SceneTransitionModule.Fade)
            elseif encounter.type == "Battle"
                Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "battle.json"; direction = Scripts.SceneTransitionModule.Fade)
            elseif encounter.type == "Event"
                if encounter.category == "shop"
                    shop_scene = resolve_shop_scene(this.persistentStateManager === nothing ? 0 : this.persistentStateManager.seed, node_index)
                    Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, shop_scene; direction = Scripts.SceneTransitionModule.Fade)
                elseif encounter.category == "rest"
                    Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "rest.json"; direction = Scripts.SceneTransitionModule.Fade)
                else
                    Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "event.json"; direction = Scripts.SceneTransitionModule.Fade)
                end
            end
        end
    end

    function update_available_nodes(this::MapManager)
        # Only allow forward movement along the current path, no backtracking or path jumping
        # availableNodes should only include the nodes directly connected to the current node
        current_node = this.persistentStateManager.currentLevel
        this.persistentStateManager.availableNodes = Int[]

        # Find the current node's data
        current_button = nothing
        for (id, data) in this.persistentStateManager.mapPoints
            if data["index"] == current_node
                current_button = data
                break
            end
        end

        if current_button !== nothing && haskey(current_button, "connections")
            for connection in current_button["connections"]
                push!(this.persistentStateManager.availableNodes, connection)
            end
        end

        # Update the "enabled" state for all nodes
        for (id, data) in this.persistentStateManager.mapPoints
            data["enabled"] = data["index"] in this.persistentStateManager.availableNodes
        end

        # Update connection sprites based on new availability
        update_all_connection_sprites(this)
    end

    function build_branching_route(current_floor, theme::MapFloorTheme = floor_theme(current_floor))
        # Generate maps using our new GridMapGenerator
        seed = rand(1:1000000)  # Random seed for map generation
        is_ascension_zero = false  # Default to normal difficulty

        # Generate the map
        maps = GridMapGenerator.generate_maps(
            seed,
            theme.mapHeight,
            theme.mapWidth,
            theme.pathDensity,
            is_ascension_zero;
            num_maps = 1,
        )
        map = maps[1]  # Use the first map for now

        # Convert the grid map to our route format
        route_nodes = Dict{Int, Tuple{Any, Int, Int, Vector{Int}}}()
        starting_points = Int[]

        # Track node IDs
        node_counter = 0
        node_id_map = Dict{Point, Int}()

        # First pass: assign IDs to all nodes
        for (y, row) in enumerate(map)
            for (x, node) in enumerate(row)
                if !isempty(node.edges) || !isempty(node.parents)
                    node_counter += 1
                    node_id_map[Point(x-1, y-1)] = node_counter
                end
            end
        end

        encounter_ctx = build_encounter_generation_context(
            theme.encounterFloor;
            node_reachability = build_node_reachability(map, node_id_map),
        )

        # Second pass: create route nodes and connections
        for (y, row) in enumerate(map)
            for (x, node) in enumerate(row)
                if !isempty(node.edges) || !isempty(node.parents)
                    node_id = node_id_map[Point(x-1, y-1)]

                    # Convert room type to encounter
                    @debug "Node $(node_id) at ($(x-1), $(y-1)) has room type: $(node.class)"
                    encounter = get_random_encounter_from_room_type(
                        node.class,
                        theme.encounterFloor,
                        encounter_ctx;
                        node_id = node_id,
                    )

                    # Screen layout: map row (depth) → mostly X; lane (column) → base Y.
                    # Add a deterministic (y-1)*step to Y so deeper nodes are always lower on screen
                    # within the same lane (previous per-node Y jitter could invert that order).
                    lane_y_min = 275
                    lane_y_max = 625
                    col_step = (lane_y_max - lane_y_min) / max(1, length(row) - 1)
                    depth_y_step = 12  # px per map row (ordering within a lane); keep small so ~15 rows + boss still fits the view
                    # Extra gap so the walk from the last rest row to the boss reads as its own stretch.
                    boss_lead_in_x = node.class == :BossRoom ? 140 : 0
                    x_jitter = node.class == :BossRoom ? 0 : rand(-12:12)
                    x_pos = round(Int, 340 + (y - 1) * 150 + boss_lead_in_x + x_jitter)
                    y_pos = round(Int, lane_y_min + (x - 1) * col_step + (y - 1) * depth_y_step)

                    # Get connections
                    connections = Int[]
                    for edge in node.edges
                        target_point = Point(edge.dst_x, edge.dst_y)
                        if haskey(node_id_map, target_point)
                            push!(connections, node_id_map[target_point])
                        end
                    end

                    # Add to route nodes
                    route_nodes[node_id] = (encounter, x_pos, y_pos, connections)

                    # Check if this is a starting point
                    if y == 1 && !isempty(node.edges)
                        push!(starting_points, node_id)
                    end
                end
            end
        end

        return route_nodes, starting_points
    end

    function get_random_encounter_from_room_type(room_type::Union{Nothing, Symbol}, current_floor, encounter_ctx = nothing; node_id = nothing)
        @debug("room_type: $(room_type)")
        if room_type === nothing
            return get_random_encounter("enemy", current_floor, encounter_ctx; node_id = node_id)
        end

        if room_type == :RestRoom
            return get_random_encounter("rest", current_floor, encounter_ctx; node_id = node_id)
        elseif room_type == :ShopRoom
            return get_random_encounter("shop", current_floor, encounter_ctx; node_id = node_id)
        elseif room_type == :MonsterRoomElite
            return get_random_encounter("elite", current_floor, encounter_ctx; node_id = node_id)
        elseif room_type == :EventRoom
            return get_random_encounter("event", current_floor, encounter_ctx; node_id = node_id)
        elseif room_type == :MonsterRoom
            return get_random_encounter("enemy", current_floor, encounter_ctx; node_id = node_id)
        elseif room_type == :TreasureRoom
            return get_random_encounter("treasure", current_floor, encounter_ctx; node_id = node_id)
        elseif room_type == :BossRoom
            return get_random_encounter("boss", current_floor, encounter_ctx; node_id = node_id)
        end

        return get_random_encounter("enemy", current_floor, encounter_ctx; node_id = node_id)  # Default fallback
    end

    function set_enemies_tuples(selected_enemies, encounter_type)
        multiplier = encounter_type == "elite" ? 2 : encounter_type == "boss" ? 3 : 1
        enemies = []
        for enemy in selected_enemies
            push!(enemies, (key = enemy.key, name = enemy.name, level = 1, maxHealth = enemy.average_health * multiplier, health = enemy.average_health * multiplier, attack = enemy.average_attack * multiplier, defense = enemy.average_defense * multiplier, gold = enemy.average_gold * multiplier))
        end
        return enemies
    end

    function is_enemy_available(enemy)
        if !hasproperty(enemy, :currently_available_in_game)
            return false
        end

        value = enemy.currently_available_in_game
        if value isa Bool
            return value
        elseif value isa AbstractString
            lowered = lowercase(strip(value))
            return lowered in ("true", "1", "yes")
        elseif value isa Integer
            return value != 0
        end

        return false
    end

    function selected_enemy_instances_from_comp_entry(selected_enemy_comp, encounter_type::String, globals, available_enemy_data = nothing, available_enemy_keys = nothing)
        if available_enemy_data === nothing
            enemy_data = globals.get_enemy_data()
            available_enemy_data = Dict(
                key => enemy for (key, enemy) in enemy_data
                if is_enemy_available(enemy)
            )
        end
        if available_enemy_keys === nothing
            available_enemy_keys = collect(keys(available_enemy_data))
        end
        selected_enemies = []
        for enemy_key in split(selected_enemy_comp.comp, ",")
            normalized_key = uppercase(strip(enemy_key))
            if normalized_key == "WILDCARD"
                if !isempty(available_enemy_keys)
                    random_key = available_enemy_keys[rand(1:length(available_enemy_keys))]
                    push!(selected_enemies, available_enemy_data[random_key])
                end
            else
                if haskey(available_enemy_data, normalized_key)
                    push!(selected_enemies, available_enemy_data[normalized_key])
                else
                    @debug "Skipping unavailable enemy key $(normalized_key)"
                end
            end
        end
        return set_enemies_tuples(selected_enemies, encounter_type)
    end

    function enemies_from_comp_key(comp_key::String, encounter_type::String, globals)
        comps_dict = globals.get_enemy_comps_data()
        if !haskey(comps_dict, comp_key)
            @warn "Unknown enemy comp key $(comp_key)"
            return nothing
        end
        return selected_enemy_instances_from_comp_entry(comps_dict[comp_key], encounter_type, globals)
    end

    const TUTORIAL_REGULAR_COMP_KEYS = (ENEMYCOMP_SLIMES, ENEMYCOMP_SKELEBATS, ENEMYCOMP_BIRDMAN)
    const TUTORIAL_REGULAR_COMP_LABELS = ("Slimes", "Skelebats", "Birdman")

    function apply_tutorial_regular_map_encounter_enemies(encounter, psm, globals)
        if encounter.type != "Battle" || encounter.category != "enemy"
            return encounter
        end
        n = psm.regularMapBattlesWonThisRun
        if n < 0 || n >= length(TUTORIAL_REGULAR_COMP_KEYS)
            return encounter
        end
        forced = enemies_from_comp_key(TUTORIAL_REGULAR_COMP_KEYS[n + 1], "enemy", globals)
        if forced === nothing
            return encounter
        end
        return (type = encounter.type, category = encounter.category, enemies = forced)
    end

    const POTION_SLOT_EVENT_KEYS = Set(["RANDOMEVENT_UNMARKEDGRAVE"])

    function _has_free_potion_slot()::Bool
        try
            user = JulGame.UserGlobals["Module"].get_user_data()
            user === nothing && return true
            return length(user.potions) < user.max_potions
        catch
            return true
        end
    end

    function build_weighted_event_options(all_random_events)
        options = Tuple{String, Int}[]
        potion_ok = _has_free_potion_slot()
        for (key, event) in all_random_events
            key == "RANDOMEVENT_RESTSITE" && continue
            if key in POTION_SLOT_EVENT_KEYS && !potion_ok
                continue
            end
            if event.currently_available_in_game && event.chance_to_appear > 0
                push!(options, (key, Int(event.chance_to_appear)))
            end
        end
        return options
    end

    function _pick_weighted_event_key(event_weights)
        total_weight = sum(w for (_, w) in event_weights)
        roll = rand() * total_weight
        acc = 0.0
        selected = event_weights[1][1]
        for (key, weight) in event_weights
            acc += weight
            if roll <= acc
                return key
            end
        end
        return selected
    end

    function pick_weighted_random_event_key(event_weights, used_event_keys)
        remaining = filter(opt -> !(first(opt) in used_event_keys), event_weights)
        if isempty(remaining)
            empty!(used_event_keys)
            remaining = event_weights
        end
        if isempty(remaining)
            @warn "No available random events with positive chance_to_appear; falling back to rest site"
            return "RANDOMEVENT_RESTSITE"
        end
        selected = _pick_weighted_event_key(remaining)
        push!(used_event_keys, selected)
        return selected
    end

    function build_node_reachability(map, node_id_map)::Dict{Int, Set{Int}}
        children = Dict{Int, Vector{Int}}()
        for (y, row) in enumerate(map)
            for (x, node) in enumerate(row)
                pt = Point(x - 1, y - 1)
                haskey(node_id_map, pt) || continue
                id = node_id_map[pt]
                kids = Int[]
                for edge in node.edges
                    target = Point(edge.dst_x, edge.dst_y)
                    haskey(node_id_map, target) && push!(kids, node_id_map[target])
                end
                children[id] = kids
            end
        end
        reachable = Dict{Int, Set{Int}}()
        for id in keys(children)
            seen = Set{Int}()
            stack = copy(get(children, id, Int[]))
            while !isempty(stack)
                n = pop!(stack)
                n in seen && continue
                push!(seen, n)
                append!(stack, get(children, n, Int[]))
            end
            reachable[id] = seen
        end
        return reachable
    end

    function nodes_are_covisitable(reachable, a::Int, b::Int)::Bool
        a == b && return true
        return b in get(reachable, a, Set{Int}()) || a in get(reachable, b, Set{Int}())
    end

    function used_path_comp_keys(assigned::Dict{Int, String}, reachable, node_id)
        used = Set{String}()
        node_id === nothing && return used
        if isempty(reachable)
            return Set{String}(values(assigned))
        end
        for (other_id, key) in assigned
            if nodes_are_covisitable(reachable, node_id, other_id)
                push!(used, key)
            end
        end
        return used
    end

    function pick_unused_battle_comp(comps, assigned, reachable, node_id)
        used = used_path_comp_keys(assigned, reachable, node_id)
        remaining = filter(c -> !(string(c.key) in used), comps)
        isempty(remaining) && (remaining = comps)
        return remaining[rand(1:length(remaining))]
    end

    function build_encounter_generation_context(current_floor; node_reachability = Dict{Int, Set{Int}}())
        globals = JulGame.UserGlobals["Module"]
        all_comps = collect(values(globals.get_enemy_comps_data()))
        # Filter comps once for the current floor.
        floor_comps = filter(comp -> begin
            "$(current_floor)" in split(comp.floors, ",")
        end, all_comps)

        enemy_data = globals.get_enemy_data()
        available_enemy_data = Dict(
            key => enemy for (key, enemy) in enemy_data
            if is_enemy_available(enemy)
        )
        available_enemy_keys = collect(keys(available_enemy_data))

        valid_comps = filter(comp -> begin
            comp_keys = split(comp.comp, ",")
            all(key -> begin
                normalized_key = uppercase(strip(key))
                normalized_key == "WILDCARD" || haskey(available_enemy_data, normalized_key)
            end, comp_keys)
        end, floor_comps)

        return (
            globals = globals,
            available_enemy_data = available_enemy_data,
            available_enemy_keys = available_enemy_keys,
            enemy_comps = filter(comp -> comp.type == "enemy", valid_comps),
            elite_comps = filter(comp -> comp.type == "elite", valid_comps),
            boss_comps = filter(comp -> comp.type == "boss", valid_comps),
            event_weights = build_weighted_event_options(globals.RandomEventsModule.ALL_RANDOMEVENTS),
            used_event_keys = Set{String}(),
            assigned_enemy_comps = Dict{Int, String}(),
            assigned_elite_comps = Dict{Int, String}(),
            node_reachability = node_reachability,
        )
    end

    # Chance an event node secretly holds a regular battle (category stays "event" so the map shows an event tile)
    const EVENT_AMBUSH_CHANCE = 0.10

    function get_random_encounter(encounter_type, current_floor, encounter_ctx = nothing; node_id = nothing)
        ctx = encounter_ctx === nothing ? build_encounter_generation_context(current_floor) : encounter_ctx
        globals = ctx.globals

        if encounter_type == "event"
            if rand() < EVENT_AMBUSH_CHANCE
                battle = get_random_encounter("enemy", current_floor, ctx; node_id = node_id)
                battle.type == "Battle" && return (type = "Battle", category = "event", enemies = battle.enemies)
            end
            return (type = "Event", category = "event", name = pick_weighted_random_event_key(ctx.event_weights, ctx.used_event_keys))
        elseif encounter_type == "rest"
            return (type = "Event", category = "rest", name = "RANDOMEVENT_RESTSITE")
        elseif encounter_type == "shop"
            return (type = "Event", category = "shop", name = "Shop")
        elseif encounter_type == "treasure"
            return (type = "Treasure", category = "treasure", name = "Treasure Chest")
        end

        comps = if encounter_type == "enemy"
            ctx.enemy_comps
        elseif encounter_type == "elite"
            ctx.elite_comps
        elseif encounter_type == "boss"
            ctx.boss_comps
        else
            ctx.enemy_comps
        end
        if encounter_type == "elite" && isempty(comps) && !isempty(ctx.enemy_comps)
            @warn "No valid elite enemy comps for floor $(current_floor); using regular comps with elite multipliers"
            comps = ctx.enemy_comps
        end

        if isempty(comps)
            @warn "No valid enemy comps available for floor $(current_floor) and type $(encounter_type)"
            return (type = "Event", category = "rest", name = "RANDOMEVENT_RESTSITE")
        end

        assigned = if encounter_type == "elite"
            ctx.assigned_elite_comps
        elseif encounter_type == "enemy"
            ctx.assigned_enemy_comps
        else
            nothing
        end
        selected_enemy_comp = assigned === nothing ?
            comps[rand(1:length(comps))] :
            pick_unused_battle_comp(comps, assigned, ctx.node_reachability, node_id)
        if assigned !== nothing && node_id !== nothing
            assigned[node_id] = string(selected_enemy_comp.key)
        end
        selected_enemies = selected_enemy_instances_from_comp_entry(
            selected_enemy_comp,
            encounter_type,
            globals,
            ctx.available_enemy_data,
            ctx.available_enemy_keys,
        )
        @debug(selected_enemies)
        #rand_max_health = rand(1:2)
        if encounter_type === nothing
            encounter_type = rand(1:10)
            if encounter_type <= 7
                return get_random_encounter("enemy", current_floor, ctx; node_id = node_id)
            else
                return get_random_encounter("event", current_floor, ctx; node_id = node_id)
            end
        elseif encounter_type == "enemy"
            # Use exact names to match the sprite files
            return (type = "Battle", category = "enemy", enemies = selected_enemies)
        elseif encounter_type == "elite"
            elite_multiplier = 2
            # tuple is immutable, so we need to create a new tuple
            return (type = "Battle", category = "elite", enemies = selected_enemies)
        elseif encounter_type == "boss"
            boss_multiplier = 3
            return (type = "Battle", category = "boss", enemies = selected_enemies)
        end
    end

    """
    Get tooltip text for an encounter
    """
    function get_encounter_tooltip_text(encounter; psm = nothing, node_index = nothing, available_nodes = nothing)
        if encounter.type == "Battle" && encounter.category != "event"
            if encounter.category == "elite"
                return "Elite: A stronger enemy that gives a greater reward."
            elseif encounter.category == "boss"
                return "Boss: The floor's final challenge."
            else
                base = "Enemy: A battle against the enemies of the floor."
                if psm !== nothing && node_index !== nothing && available_nodes !== nothing &&
                   node_index in available_nodes &&
                   psm.regularMapBattlesWonThisRun < length(TUTORIAL_REGULAR_COMP_KEYS)
                    label = TUTORIAL_REGULAR_COMP_LABELS[psm.regularMapBattlesWonThisRun + 1]
                    #return "$(base) ($(label))"
                end
                return base
            end
        elseif encounter.type == "Event" || encounter.category == "event"
            if encounter.category == "shop"
                return "Shop: Purchase items, upgrades, or remove pieces from your inventory."
            elseif encounter.category == "rest"
                return "Rest: Restore health, or use the fire pit."
            else
                return "Event: A random encounter from the floor."
            end
        elseif encounter.type == "Treasure"
            return "Treasure: Open a chest that contains a random reward."
        end
        return "Unknown Encounter"
    end
end
