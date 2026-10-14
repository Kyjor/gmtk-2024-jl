module MapFabSpawnerModule
    using JulGame
    using Random
    using ..Scripts
    using ..MapFloorSystemModule
    using ..MapSpriteMaskModule
    using ..MapFabZonesModule
    using ..MapFabClustersModule
    include("utils/MapFabInteractions.jl")
    using .MapFabInteractionsModule
    include("utils/MapFabPlacementDebug.jl")
    using .MapFabPlacementDebugModule

    function _map_fab_rng(persistent_state)
        persistent_state === nothing && return Random.Xoshiro()
        # Isolated stream from run seed + floor so map décor is stable per visit but does not touch piecePlacementRNG.
        s = UInt64(hash((persistent_state.seed, persistent_state.currentFloor, 0xfab5eed01)) & typemax(UInt64))
        return Random.Xoshiro(s == 0 ? 0x1 : s)
    end

    mutable struct MapFabSpawner <: Script
        parent
        mapManager
        fogEntities
        fogDirections
        spawnedPositions # (x, y, opaque_radius) for fab–fab broadphase
        spawnedHulls # world-space opaque hulls parallel to spawnedPositions
        spawnedNames # fab type name parallel to spawnedPositions
        spatialGrid # cell => indices into spawnedPositions
        spatialCellSize
        connectionSegments # (x1, y1, x2, y2) world-space map connection segments
        nodeCollisionHulls # world-space opaque hulls for map nodes
        pathCollisionHalfWidth # world-space half-thickness of path art (+ pad)
        fabInteractions
        interactionRNG
        timedFabEntities # (entity, remaining lifetime)
        zoneCatalog
        placementDebugRegions
        placementDebugLayer
        
        # Configurable collision buffers
        nodeCollisionRadius
        lineCollisionBuffer
        entitySpacingMultiplier

        function MapFabSpawner()
            this = new()
            this.fogEntities = Any[]
            this.fogDirections = Float64[]
            this.spawnedPositions = NTuple{3, Float64}[]
            this.spawnedHulls = Vector{NTuple{2, Float64}}[]
            this.spawnedNames = String[]
            this.spatialGrid = Dict{Tuple{Int, Int}, Vector{Int}}()
            this.spatialCellSize = 2.0
            this.connectionSegments = NTuple{4, Float64}[]
            this.nodeCollisionHulls = Vector{NTuple{2, Float64}}[]
            this.pathCollisionHalfWidth = 0.35
            this.fabInteractions = Any[]
            this.interactionRNG = Random.Xoshiro()
            this.timedFabEntities = Tuple{Any, Float64}[]
            this.zoneCatalog = empty_zone_catalog()
            this.placementDebugRegions = PlacementRegion[]
            this.placementDebugLayer = 0
            
            # Fallback circle/segment buffers when alpha masks are unavailable
            this.nodeCollisionRadius = 2.0
            this.lineCollisionBuffer = 0.75
            this.entitySpacingMultiplier = 1.0

            return this
        end
    end

    function JulGame.initialize(this::MapFabSpawner)
        this.mapManager = this.parent.scripts[1]
        empty!(this.fogEntities)
        empty!(this.fogDirections)
        empty!(this.spawnedPositions)
        empty!(this.spawnedHulls)
        empty!(this.spawnedNames)
        empty!(this.spatialGrid)
        empty!(this.connectionSegments)
        empty!(this.nodeCollisionHulls)
        empty!(this.fabInteractions)
        empty!(this.timedFabEntities)
        
        # Populate node positions for collision detection
        populate_node_positions(this)
        populate_connection_segments(this)
        # Shared zone catalog for spawn + debug overlay
        build_placement_debug!(this)

        # start timer 
        timer = time_ns()
        rng = _map_fab_rng(this.mapManager.persistentStateManager)
        this.interactionRNG = rng
        if rand(rng) > 0.01
            stamp_theme_fab_clusters!(this, rng)
            for fab in this.mapManager.floorTheme.fabs
                spawn_map_fab(this, rng, fab)
            end
            ensure_min_crows!(this, rng)
        else
            @debug "No map fabs spawned"
        end
        @debug "Map fabs spawned in $((time_ns() - timer) / 1e9) seconds"
    end

    function JulGame.update(this::MapFabSpawner, deltaTime)
        update_map_fab_interactions!(
            this.fabInteractions,
            deltaTime,
            this.interactionRNG,
        )
        _update_timed_fab_entities!(this, deltaTime)

        # Animate fog entities - move them back and forth slowly
        fog_speed = 0.5  # Very slow movement speed
        for (i, fog_entity) in enumerate(this.fogEntities)
            # Move fog in its current direction
            fog_entity.transform.position = Math.Vector3f(
                fog_entity.transform.position.x + this.fogDirections[i] * fog_speed * deltaTime,
                fog_entity.transform.position.y,
                fog_entity.transform.position.z
            )
            
            # Reverse direction if fog goes too far (boundaries)
            min_fog_x, max_fog_x = this.mapManager.floorTheme.fogHorizontalBounds
            if fog_entity.transform.position.x > max_fog_x || fog_entity.transform.position.x < min_fog_x
                this.fogDirections[i] = -this.fogDirections[i]
            end
        end

        draw_placement_debug!(this)
    end

    function JulGame.on_shutdown(this::MapFabSpawner)
    end

    @inline function _spatial_cell(this::MapFabSpawner, x::Float64, y::Float64)
        return (
            floor(Int, x / this.spatialCellSize),
            floor(Int, y / this.spatialCellSize),
        )
    end

    function _register_spawned_fab!(
        this::MapFabSpawner,
        x::Float64,
        y::Float64,
        opaque_radius::Float64,
        hull::Vector{NTuple{2, Float64}},
        name::String,
    )
        push!(this.spawnedPositions, (x, y, opaque_radius))
        push!(this.spawnedHulls, hull)
        push!(this.spawnedNames, name)
        idx = length(this.spawnedPositions)
        cell = _spatial_cell(this, x, y)
        if !haskey(this.spatialGrid, cell)
            this.spatialGrid[cell] = Int[]
        end
        push!(this.spatialGrid[cell], idx)
    end

    """Place at most one formation per fab type, before individual fill."""
    function stamp_theme_fab_clusters!(this::MapFabSpawner, rng::AbstractRNG)
        theme = this.mapManager.floorTheme
        min_x, max_x, min_y, max_y = theme.fabBounds
        globals = JulGame.UserGlobals["Module"]
        asset_prefix = theme.assetPrefix

        sample_anchor = (fab, _form) -> begin
            theme_radius = fab.collisionRadius
            # Cheap anchor probe: any valid solo placement in the fab's zone.
            image_path = map_fab_asset_path(globals, fab.name, fab.assetCount, rng, asset_prefix)
            shape = get_sprite_alpha_shape(image_path)
            opaque_r = opaque_radius_wu(shape; pad_wu = 0.08)
            footprint_r = max(theme_radius, opaque_r)
            return find_position_for_fab(
                this, rng, fab, min_x, max_x, min_y, max_y,
                theme_radius, footprint_r, shape,
            )
        end

        member_ok = (fab, x, y) -> begin
            (x < min_x || x > max_x || y < min_y || y > max_y) && return false
            image_path = map_fab_asset_path(globals, fab.name, fab.assetCount, rng, asset_prefix)
            shape = get_sprite_alpha_shape(image_path)
            opaque_r = opaque_radius_wu(shape; pad_wu = 0.08)
            footprint_r = max(fab.collisionRadius, opaque_r)
            return is_position_valid(
                this, x, y, fab.collisionRadius;
                avoid_connections = true,
                footprint_radius = footprint_r,
                shape = shape,
                fab_name = fab.name,
                min_same_type_distance = fab.minSameTypeDistance,
            )
        end

        place_member! = (fab, vis_x, vis_y) -> begin
            image_path = map_fab_asset_path(globals, fab.name, fab.assetCount, rng, asset_prefix)
            shape = get_sprite_alpha_shape(image_path)
            opaque_r = opaque_radius_wu(shape; pad_wu = 0.08)
            tx, ty = ppu0_transform_from_visual_center(vis_x, vis_y, 1.0, 1.0)
            fab_hull = hull_to_world(shape, vis_x, vis_y)
            create_map_fab_entity(
                this, rng, fab.name, fab.assetCount, tx, ty;
                imagePath = image_path,
            )
            _register_spawned_fab!(this, vis_x, vis_y, opaque_r, fab_hull, fab.name)
        end

        stamped = stamp_fab_clusters!(
            rng,
            theme.fabs,
            sample_anchor,
            member_ok,
            place_member!,
        )
        @debug "Stamped fab clusters: $(join(sort!(collect(stamped)), ", "))"
    end

    """If no crow landed during normal spawn, force at least one onto the map."""
    function ensure_min_crows!(this::MapFabSpawner, rng::AbstractRNG; min_count::Int = 1)
        crow_count = count(n -> n == "crow", this.spawnedNames)
        crow_count >= min_count && return

        theme = this.mapManager.floorTheme
        fab_idx = findfirst(f -> f.name == "crow", theme.fabs)
        fab_idx === nothing && return
        fab = theme.fabs[fab_idx]
        min_x, max_x, min_y, max_y = theme.fabBounds
        globals = JulGame.UserGlobals["Module"]
        asset_prefix = theme.assetPrefix
        theme_radius = fab.collisionRadius

        for _ in 1:(min_count - crow_count)
            image_path = map_fab_asset_path(globals, fab.name, fab.assetCount, rng, asset_prefix)
            shape = get_sprite_alpha_shape(image_path)
            opaque_r = opaque_radius_wu(shape; pad_wu = 0.08)
            footprint_r = max(theme_radius, opaque_r)

            position = find_position_for_fab(
                this, rng, fab, min_x, max_x, min_y, max_y,
                theme_radius, footprint_r, shape,
            )
            if position === nothing
                # Last resort: ignore zone preference, hunt any clear cell.
                position = find_valid_position(
                    this, rng, min_x, max_x, min_y, max_y, theme_radius;
                    avoid_connections = true,
                    max_attempts = 400,
                    footprint_radius = footprint_r,
                    shape = shape,
                    fab_name = fab.name,
                    min_same_type_distance = 0.0,
                )
            end
            position === nothing && continue

            vis_x, vis_y = position
            tx, ty = ppu0_transform_from_visual_center(vis_x, vis_y, 1.0, 1.0)
            fab_hull = hull_to_world(shape, vis_x, vis_y)
            create_map_fab_entity(
                this, rng, fab.name, fab.assetCount, tx, ty;
                imagePath = image_path,
            )
            _register_spawned_fab!(this, vis_x, vis_y, opaque_r, fab_hull, fab.name)
            crow_count += 1
        end
        @debug "ensure_min_crows!: placed up to $min_count (have $crow_count)"
    end

    function spawn_map_fab(this::MapFabSpawner, rng::AbstractRNG, fab::MapFabSpec)
        min_x, max_x, min_y, max_y = this.mapManager.floorTheme.fabBounds
        theme_radius = get_entity_radius(this.mapManager.floorTheme, fab.name)
        globals = JulGame.UserGlobals["Module"]
        asset_prefix = this.mapManager.floorTheme.assetPrefix
        spawn_count = fab.spawnCount
        if fab.name == "grass"
            spawn_count = max(0, round(Int, fab.spawnCount * this.mapManager.floorTheme.grassFillMultiplier))
        elseif fab.name == "flowers"
            spawn_count = max(0, round(Int, fab.spawnCount * this.mapManager.floorTheme.flowerFillMultiplier))
        end

        # Same-type anchors for light clustering (graves/bushes/street furniture groups).
        cluster_anchors = NTuple{2, Float64}[]

        for i in 1:spawn_count
            if fab.name == "fog"
                x_pos = rand(rng, min_x:1.0:max_x)
                y_pos = rand(rng, min_y:1.0:max_y)
                new_entity = create_map_fab_entity(
                    this, rng, fab.name, fab.assetCount, x_pos, y_pos,
                )
                push!(this.fogEntities, new_entity)
                push!(this.fogDirections, rand(rng) < 0.5 ? -1.0 : 1.0)
                continue
            end

            # Pick the sprite first so clearance matches the opaque silhouette we spawn.
            image_path = map_fab_asset_path(globals, fab.name, fab.assetCount, rng, asset_prefix)
            shape = get_sprite_alpha_shape(image_path)
            opaque_r = opaque_radius_wu(shape; pad_wu = 0.08)
            footprint_r = max(theme_radius, opaque_r)

            position = find_position_for_fab(
                this,
                rng,
                fab,
                min_x,
                max_x,
                min_y,
                max_y,
                theme_radius,
                footprint_r,
                shape,
                cluster_anchors,
            )
            if position === nothing
                @debug "Could not find valid position for $(fab.name), skipping"
                continue
            end
            # Placement coords are visual centers (match node/path Forbidden geometry).
            vis_x, vis_y = position
            if fab.placement == :enclosed
                pocket = find_enclosed_pocket(this.zoneCatalog, vis_x, vis_y)
                role = _enclosed_fab_role(fab.name)
                if pocket !== nothing && role != :fill && role != :any
                    if !_pocket_role_ok(pocket, role)
                        continue
                    end
                    note_enclosed_placement!(pocket, role)
                end
            end
            tx, ty = ppu0_transform_from_visual_center(vis_x, vis_y, 1.0, 1.0)
            fab_hull = hull_to_world(shape, vis_x, vis_y)

            create_map_fab_entity(
                this,
                rng,
                fab.name,
                fab.assetCount,
                tx,
                ty;
                imagePath = image_path,
            )
            _register_spawned_fab!(this, vis_x, vis_y, opaque_r, fab_hull, fab.name)
            push!(cluster_anchors, (vis_x, vis_y))
        end
    end

    @inline function _enclosed_fab_role(name::String)::Symbol
        name == "flowers" && return :flowers
        (name == "bush" || name == "grave") && return :large
        name == "grass" && return :fill
        return :any
    end

    @inline function _pocket_role_ok(pocket, role::Symbol)::Bool
        role == :large && return pocket.largePlaced[] < 2
        role == :flowers && return pocket.flowersPlaced[] < 3
        return true
    end

    function find_position_for_fab(
        this::MapFabSpawner,
        rng::AbstractRNG,
        fab::MapFabSpec,
        min_x,
        max_x,
        min_y,
        max_y,
        spacing_radius,
        footprint_radius,
        shape::SpriteAlphaShape,
        cluster_anchors::Vector{NTuple{2, Float64}} = NTuple{2, Float64}[],
    )
        catalog = this.zoneCatalog
        validate = (x, y) -> begin
            (x < min_x || x > max_x || y < min_y || y > max_y) && return false
            return is_position_valid(
                this, x, y, spacing_radius;
                avoid_connections = true,
                footprint_radius = footprint_radius,
                shape = shape,
                fab_name = fab.name,
                min_same_type_distance = fab.minSameTypeDistance,
            )
        end

        placement = fab.placement
        path_hw = Float64(this.pathCollisionHalfWidth)
        sample_r = Float64(footprint_radius)
        # Cluster denser props; skip for carpet fillers (grass/flowers/fog).
        cluster = if fab.name in ("grass", "flowers", "fog")
            nothing
        else
            cluster_anchors
        end
        cluster_chance = fab.name in ("grave", "skull", "bush", "streetlight", "bench") ? 0.55 : 0.4
        enclosed_role = _enclosed_fab_role(fab.name)

        if placement == :enclosed
            # Enclosed pockets are rare on open graphs — fall back to Interstitial.
            pos = sample_zone_position(
                catalog, rng, RegionType[Enclosed], sample_r, validate;
                max_attempts = 280,
                enclosed_role = enclosed_role,
                cluster_anchors = cluster, cluster_chance = cluster_chance,
            )
            pos !== nothing && return pos
            return sample_zone_position(
                catalog, rng, RegionType[Interstitial], sample_r, validate;
                cluster_anchors = cluster, cluster_chance = cluster_chance,
            )
        elseif placement == :interstitial
            return sample_zone_position(
                catalog, rng, RegionType[Interstitial], sample_r, validate;
                max_attempts = fab.name == "grass" ? 220 : 160,
                cluster_anchors = cluster, cluster_chance = cluster_chance,
            )
        elseif placement == :sidewalk
            return sample_zone_position(
                catalog, rng, RegionType[Sidewalk], sample_r, validate;
                cluster_anchors = cluster, cluster_chance = 0.35,
                cluster_min = 2.5, cluster_max = 5.5,
            )
        elseif placement == :outer || placement == :edge
            if fab.name == "crow"
                # OuterCrust is mostly the void left of the grave, past the scroll limit.
                # Sample the node span so birds sit along the yard you can actually see.
                span = _crow_route_span(this, min_x, max_x, min_y, max_y)
                if span !== nothing
                    sx0, sx1, sy0, sy1 = span
                    pos = find_valid_position(
                        this, rng, sx0, sx1, sy0, sy1, spacing_radius;
                        avoid_connections = true,
                        max_attempts = 280,
                        footprint_radius = footprint_radius,
                        shape = shape,
                        fab_name = fab.name,
                        min_same_type_distance = fab.minSameTypeDistance,
                    )
                    pos !== nothing && return pos
                    # Spacing can fail once a few birds are down. Keep hunting the same span.
                    return find_valid_position(
                        this, rng, sx0, sx1, sy0, sy1, spacing_radius;
                        avoid_connections = true,
                        max_attempts = 200,
                        footprint_radius = footprint_radius,
                        shape = shape,
                        fab_name = fab.name,
                        min_same_type_distance = 0.0,
                    )
                end
            end
            pos = sample_zone_position(
                catalog, rng, RegionType[OuterCrust], sample_r, validate;
                max_attempts = 160,
                cluster_anchors = cluster, cluster_chance = 0.35,
            )
            pos !== nothing && return pos
            # OuterCrust is sparse after trees/paths — keep edge décor alive.
            return sample_zone_position(
                catalog, rng, RegionType[Interstitial], sample_r, validate;
                max_attempts = 160,
                cluster_anchors = cluster, cluster_chance = cluster_chance,
            )
        elseif placement == :road
            return sample_zone_position(
                catalog, rng, RegionType[Interstitial], sample_r, validate;
                prefer_near_segments = this.connectionSegments,
                near_seg_min = path_hw + 0.25 + sample_r * 0.5,
                near_seg_max = path_hw + 2.5,
                cluster_anchors = cluster, cluster_chance = 0.45,
            )
        elseif placement == :pathside
            return sample_zone_position(
                catalog, rng, RegionType[Interstitial], sample_r, validate;
                prefer_near_segments = this.connectionSegments,
                near_seg_min = 1.15,
                near_seg_max = 2.6,
                cluster_anchors = cluster, cluster_chance = 0.45,
            )
        elseif placement == :scatter
            return sample_zone_position(
                catalog, rng,
                RegionType[Interstitial, OuterCrust, Enclosed],
                sample_r, validate;
                # Prefer near-route cells so grass isn't mostly void OuterCrust.
                cluster_anchors = nothing,
            )
        end

        return find_valid_position(
            this, rng, min_x, max_x, min_y, max_y, spacing_radius;
            avoid_connections = true,
            max_attempts = 140,
            footprint_radius = footprint_radius,
            shape = shape,
            fab_name = fab.name,
            min_same_type_distance = fab.minSameTypeDistance,
        )
    end

    function create_map_fab_entity(
        this::MapFabSpawner,
        rng::AbstractRNG,
        name::String,
        assetCount::Int,
        x::Float64,
        y::Float64;
        startFlying::Bool = false,
        assetName::Union{Nothing, String} = nothing,
        imagePath::Union{Nothing, String} = nothing,
        lifetime::Union{Nothing, Float64} = nothing,
        registerInteractions::Bool = true,
        layer::Union{Nothing, Int} = nothing,
    )
        globals = JulGame.UserGlobals["Module"]
        assetPrefix = this.mapManager.floorTheme.assetPrefix
        entity = JulGame.MainLoopModule.create_new_entity(MAIN)
        entity.name = name
        entity.transform.position = Math.Vector3f(x, y, 0)
        resolved_path = if imagePath !== nothing
            imagePath
        elseif assetName !== nothing
            map_fab_prefixed_asset(globals, assetPrefix, assetName)
        else
            map_fab_asset_path(globals, name, assetCount, rng, assetPrefix)
        end
        spriteColor = if name == "fog"
            this.mapManager.floorTheme.fogColor
        else
            (255, 255, 255, 255)
        end
        entity.sprite = JulGame.SpriteModule.InternalSprite(
            entity,
            resolved_path,
            Math.Vector4(0, 0, 0, 0),
            false,
            spriteColor,
            false;
            pixelsPerUnit = 0,
            layer = layer === nothing ? (name == "grass" ? 1 : 2) : layer,
        )

        if lifetime !== nothing
            push!(this.timedFabEntities, (entity, lifetime))
            entity.ignoreInputEvents = true
            return entity
        end

        if !registerInteractions
            entity.ignoreInputEvents = true
            return entity
        end

        spawnCrow = () -> spawn_flying_crow!(
            this,
            rng,
            entity.transform.position,
        )
        spawnNearbyFab = (lootName::String, lootAssetCount::Int; kwargs...) ->
            spawn_nearby_fab!(this, rng, entity.transform.position, lootName, lootAssetCount; kwargs...)
        interaction = register_map_fab_interaction!(
            this.fabInteractions,
            entity,
            name,
            rng,
            assetPrefix;
            spawnCrow = spawnCrow,
            spawnNearbyFab = spawnNearbyFab,
        )
        entity.ignoreInputEvents = interaction === nothing
        if startFlying && interaction !== nothing
            start_crow_flight!(interaction, rng)
        end
        return entity
    end

    function spawn_nearby_fab!(
        this::MapFabSpawner,
        rng::AbstractRNG,
        sourcePosition::Math.Vector3f,
        name::String,
        assetCount::Int;
        assetName::Union{Nothing, String} = nothing,
        lifetime::Union{Nothing, Float64} = nothing,
        offsetY::Float64 = 0.0,
        scatter::Float64 = 1.4,
    )
        x = sourcePosition.x + (rand(rng) - 0.5) * scatter
        y = sourcePosition.y + offsetY + (rand(rng) - 0.35) * (scatter * 0.65)
        return create_map_fab_entity(
            this,
            rng,
            name,
            assetCount,
            x,
            y;
            assetName = assetName,
            lifetime = lifetime,
            registerInteractions = lifetime === nothing && name != "popeffect",
            layer = name == "popeffect" ? 3 : nothing,
        )
    end

    function spawn_flying_crow!(
        this::MapFabSpawner,
        rng::AbstractRNG,
        sourcePosition::Math.Vector3f,
    )
        return create_map_fab_entity(
            this,
            rng,
            "crow",
            1,
            sourcePosition.x + (rand(rng) - 0.5) * 0.4,
            sourcePosition.y - 0.3;
            startFlying = true,
        )
    end

    function _update_timed_fab_entities!(this::MapFabSpawner, deltaTime)
        isempty(this.timedFabEntities) && return
        remaining = Tuple{Any, Float64}[]
        for (entity, timeLeft) in this.timedFabEntities
            nextTime = timeLeft - deltaTime
            if nextTime <= 0.0
                entity.isActive = false
            else
                push!(remaining, (entity, nextTime))
            end
        end
        empty!(this.timedFabEntities)
        append!(this.timedFabEntities, remaining)
    end

    """X across the route, Y a little past the nodes, so crows aren't stuck left of the grave."""
    function _crow_route_span(this::MapFabSpawner, min_x, max_x, min_y, max_y)
        xs = Float64[]
        ys = Float64[]
        for hull in this.nodeCollisionHulls
            for (hx, hy) in hull
                push!(xs, hx)
                push!(ys, hy)
            end
        end
        isempty(xs) && return nothing
        pad_y = 4.0
        sx0 = max(Float64(min_x), minimum(xs))
        sx1 = min(Float64(max_x), maximum(xs))
        sy0 = max(Float64(min_y), minimum(ys) - pad_y)
        sy1 = min(Float64(max_y), maximum(ys) + pad_y)
        (sx0 >= sx1 || sy0 >= sy1) && return nothing
        return (sx0, sx1, sy0, sy1)
    end

    function populate_node_positions(this::MapFabSpawner)
        empty!(this.nodeCollisionHulls)
        if this.mapManager.persistentStateManager === nothing || 
           this.mapManager.persistentStateManager.mapPoints === nothing
            return
        end
        
        theme = this.mapManager.floorTheme
        psm = this.mapManager.persistentStateManager
        scale = JulGame.SCALE_UNITS
        for (_, node_data) in psm.mapPoints
            pos = node_data["position"]
            x_pos = Float64(pos.x) / scale
            y_pos = Float64(pos.y) / scale
            cx, cy = sprite_visual_center(x_pos, y_pos)

            category = lowercase(node_data["encounter"].category)
            node_index = node_data["index"]
            is_completed = node_index in psm.completedNodes
            sprite_path = map_tile_sprite(theme, category; completed = is_completed)
            shape = get_sprite_alpha_shape(sprite_path)
            hull = hull_to_world(shape, cx, cy)
            push!(this.nodeCollisionHulls, hull)
        end

        # Starting pedestal (node 0) is not in mapPoints — still blocks fab space.
        _append_starting_node_hull!(this)
    end

    function _append_starting_node_hull!(this::MapFabSpawner)
        start_ent = this.mapManager.startingNodeEntity
        start_ent === nothing && return
        theme = this.mapManager.floorTheme
        tx = Float64(start_ent.transform.position.x)
        ty = Float64(start_ent.transform.position.y)
        cx, cy = sprite_visual_center(tx, ty)
        shape = get_sprite_alpha_shape(JulGame.UserGlobals["Module"].get_asset_path(theme.startingTileSprite))
        push!(this.nodeCollisionHulls, hull_to_world(shape, cx, cy))
    end

    function populate_connection_segments(this::MapFabSpawner)
        empty!(this.connectionSegments)
        if this.mapManager.persistentStateManager === nothing ||
           this.mapManager.persistentStateManager.mapPoints === nothing
            return
        end

        map_points = this.mapManager.persistentStateManager.mapPoints
        scale = JulGame.SCALE_UNITS
        index_to_world = Dict{Any, Tuple{Float64, Float64}}()
        for (_, node_data) in map_points
            pos = node_data["position"]
            tx = Float64(pos.x) / scale
            ty = Float64(pos.y) / scale
            index_to_world[node_data["index"]] = sprite_visual_center(tx, ty)
        end

        for (_, node_data) in map_points
            source_idx = node_data["index"]
            haskey(index_to_world, source_idx) || continue
            x1, y1 = index_to_world[source_idx]
            for target_idx in node_data["connections"]
                haskey(index_to_world, target_idx) || continue
                x2, y2 = index_to_world[target_idx]
                # Deduplicate undirected edges (A->B and B->A) by canonical ordering.
                if (x1 < x2) || (x1 == x2 && y1 <= y2)
                    push!(this.connectionSegments, (x1, y1, x2, y2))
                else
                    push!(this.connectionSegments, (x2, y2, x1, y1))
                end
            end
        end

        # Edges from the starting pedestal to the first-column nodes.
        _append_starting_connection_segments!(this, index_to_world)

        # Keep deterministic, unique segment list.
        unique!(this.connectionSegments)

        # Path forbidden width from opaque band in the path PNG (inactive is the common case).
        theme = this.mapManager.floorTheme
        path_sprite = map_path_sprite(theme, :inactive)
        path_shape = get_sprite_alpha_shape(path_sprite)
        this.pathCollisionHalfWidth = path_half_width_wu(path_shape)
    end

    function _append_starting_connection_segments!(
        this::MapFabSpawner,
        index_to_world::Dict{Any, Tuple{Float64, Float64}},
    )
        start_ent = this.mapManager.startingNodeEntity
        start_ent === nothing && return
        psm = this.mapManager.persistentStateManager
        psm === nothing && return

        sx, sy = sprite_visual_center(
            Float64(start_ent.transform.position.x),
            Float64(start_ent.transform.position.y),
        )
        for target_idx in psm.startingPoints
            haskey(index_to_world, target_idx) || continue
            x2, y2 = index_to_world[target_idx]
            if (sx < x2) || (sx == x2 && sy <= y2)
                push!(this.connectionSegments, (sx, sy, x2, y2))
            else
                push!(this.connectionSegments, (x2, y2, sx, sy))
            end
        end
    end

    function get_entity_radius(theme::MapFloorTheme, name::String)
        # Define base collision radii for different entity types (smaller values)
        index = findfirst(fab -> fab.name == name, theme.fabs)
        index === nothing && return 0.6  # Default radius
        return theme.fabs[index].collisionRadius
    end

    function find_valid_position(
        this::MapFabSpawner,
        rng::AbstractRNG,
        min_x,
        max_x,
        min_y,
        max_y,
        radius;
        avoid_connections::Bool = true,
        max_attempts::Int = 100,
        footprint_radius::Union{Nothing, Float64} = nothing,
        shape::Union{Nothing, SpriteAlphaShape} = nothing,
        fab_name::String = "",
        min_same_type_distance::Float64 = 0.0,
    )
        for _ in 1:max_attempts
            x = rand(rng, min_x:1.0:max_x)
            y = rand(rng, min_y:1.0:max_y)
            if is_position_valid(
                this, x, y, radius;
                avoid_connections = avoid_connections,
                footprint_radius = footprint_radius,
                shape = shape,
                fab_name = fab_name,
                min_same_type_distance = min_same_type_distance,
            )
                return (x, y)
            end
        end
        return nothing
    end

    function is_position_valid(
        this::MapFabSpawner,
        x::Float64,
        y::Float64,
        spacing_radius::Float64;
        avoid_connections::Bool = true,
        connection_buffer::Union{Nothing, Float64} = nothing,
        footprint_radius::Union{Nothing, Float64} = nothing,
        shape::Union{Nothing, SpriteAlphaShape} = nothing,
        fab_name::String = "",
        min_same_type_distance::Float64 = 0.0,
    )
        fab_hull = shape === nothing ? nothing : hull_to_world(shape, x, y)
        opaque_r = footprint_radius === nothing ? spacing_radius : footprint_radius

        # Fab-vs-fab: same-type distance + opaque broadphase / hull overlap.
        max_existing_radius = 2.5
        query_radius = max(opaque_r + max_existing_radius, min_same_type_distance)
        cell_range = ceil(Int, query_radius / this.spatialCellSize)
        cx, cy = _spatial_cell(this, x, y)
        min_same_sq = min_same_type_distance * min_same_type_distance

        for gx in (cx - cell_range):(cx + cell_range)
            for gy in (cy - cell_range):(cy + cell_range)
                cell = (gx, gy)
                haskey(this.spatialGrid, cell) || continue
                for idx in this.spatialGrid[cell]
                    ex_x, ex_y, ex_radius = this.spawnedPositions[idx]
                    dx = x - ex_x
                    dy = y - ex_y
                    dist_sq = dx * dx + dy * dy

                    if min_same_type_distance > 0.0 &&
                       idx <= length(this.spawnedNames) &&
                       this.spawnedNames[idx] == fab_name &&
                       dist_sq < min_same_sq
                        return false
                    end

                    min_distance = opaque_r + ex_radius
                    if dist_sq >= (min_distance * min_distance)
                        continue
                    end
                    # Circles overlap — confirm with opaque hulls when available.
                    if fab_hull !== nothing && idx <= length(this.spawnedHulls)
                        if hulls_overlap(fab_hull, this.spawnedHulls[idx]; pad = 0.1)
                            return false
                        end
                    else
                        return false
                    end
                end
            end
        end

        clear_r = if shape !== nothing
            max(spacing_radius, 0.2)
        else
            opaque_r
        end

        # Fast disk reject against Forbidden.
        if !is_clear_of_nodes(this, x, y, clear_r)
            return false
        end
        if avoid_connections && !is_clear_of_connections(
            this,
            x,
            y,
            clear_r;
            connection_buffer = connection_buffer,
        )
            return false
        end

        # Exact silhouette: entire opaque hull must stay clear of Forbidden.
        if fab_hull !== nothing
            if hull_hits_forbidden(
                fab_hull,
                this.nodeCollisionHulls,
                this.connectionSegments,
                Float64(this.pathCollisionHalfWidth);
                pad = 0.1,
            )
                return false
            end
        end
        return true
    end

    function is_clear_of_nodes(
        this::MapFabSpawner,
        x::Float64,
        y::Float64,
        radius::Float64,
    )
        for hull in this.nodeCollisionHulls
            if point_hits_hull(x, y, radius, hull)
                return false
            end
        end
        return true
    end

    function is_clear_of_connections(
        this::MapFabSpawner,
        x::Float64,
        y::Float64,
        radius::Float64;
        connection_buffer::Union{Nothing, Float64} = nothing,
    )
        isempty(this.connectionSegments) && return true

        # Default buffer is opaque path half-width from the path PNG.
        buffer = connection_buffer === nothing ? this.pathCollisionHalfWidth : connection_buffer
        min_distance_to_line = radius + buffer

        for (x1, y1, x2, y2) in this.connectionSegments
            dist = distance_to_line_segment(x, y, x1, y1, x2, y2)
            if dist < min_distance_to_line
                return false
            end
        end
        return true
    end

    function distance_to_line_segment(px::Float64, py::Float64, x1::Float64, y1::Float64, x2::Float64, y2::Float64)
        # Calculate distance from point (px, py) to line segment (x1,y1)-(x2,y2)
        dx = x2 - x1
        dy = y2 - y1
        
        if dx == 0 && dy == 0
            # Line segment is a point
            return sqrt((px - x1)^2 + (py - y1)^2)
        end
        
        # Parameter t represents position along line (0 = start, 1 = end)
        t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / (dx^2 + dy^2)))
        
        # Find closest point on line segment
        closest_x = x1 + t * dx
        closest_y = y1 + t * dy
        
        # Return distance to closest point
        return sqrt((px - closest_x)^2 + (py - closest_y)^2)
    end
end
