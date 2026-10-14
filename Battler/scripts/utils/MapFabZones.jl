module MapFabZonesModule
    using JulGame
    using Random
    using ..MapSpriteMaskModule

    export RegionType, OuterCrust, Interstitial, Sidewalk, Enclosed, Forbidden
    export PlacementRegion, ZonePocket, ZoneCatalog
    export build_zone_catalog!, empty_zone_catalog, sample_zone_position
    export find_enclosed_pocket, note_enclosed_placement!

    @enum RegionType::Int8 begin
        OuterCrust = 1
        Interstitial = 2
        Sidewalk = 3
        Enclosed = 4
        Forbidden = 5
    end

    struct PlacementRegion
        region_type::RegionType
        vertices::Vector{NTuple{2, Float64}}
        centroid::NTuple{2, Float64}
    end

    struct ZonePocket
        region_type::RegionType
        cells::Vector{NTuple{2, Float64}}
        area::Float64
        largePlaced::Base.RefValue{Int}
        flowersPlaced::Base.RefValue{Int}
    end

    function ZonePocket(region_type::RegionType, cells::Vector{NTuple{2, Float64}}, area::Float64)
        return ZonePocket(region_type, cells, area, Ref(0), Ref(0))
    end

    mutable struct ZoneCatalog
        cell_size::Float64
        cells::Dict{RegionType, Vector{NTuple{2, Float64}}}
        enclosed_pockets::Vector{ZonePocket}
        debug_regions::Vector{PlacementRegion}
    end

    function empty_zone_catalog()
        return ZoneCatalog(
            GRID_CELL,
            Dict{RegionType, Vector{NTuple{2, Float64}}}(
                OuterCrust => NTuple{2, Float64}[],
                Interstitial => NTuple{2, Float64}[],
                Sidewalk => NTuple{2, Float64}[],
                Enclosed => NTuple{2, Float64}[],
            ),
            ZonePocket[],
            PlacementRegion[],
        )
    end

    const GRID_CELL = 0.85
    # Interstitial band around the node AABB (too small → empty; too large → void slab).
    const ROUTE_CORRIDOR_PAD = 1.05
    # Tighter curb bands so street furniture sits nearer the route AABB.
    const SIDEWALK_CURB = 2.0
    const SIDEWALK_BAND = 1.4
    const SIDEWALK_STREET_PAD = 1.5
    # Relative weights when sampling multi-zone placements like :scatter.
    const SCATTER_ZONE_WEIGHT = Dict{RegionType, Float64}(
        Interstitial => 0.55,
        OuterCrust => 0.30,
        Enclosed => 0.15,
        Sidewalk => 0.0,
        Forbidden => 0.0,
    )

    const CELL_BLOCKED = Int8(0)
    const CELL_OUTER = Int8(1)
    const CELL_GAP = Int8(2)
    const CELL_SIDEWALK = Int8(3)

    function build_zone_catalog!(spawner)::ZoneCatalog
        catalog = empty_zone_catalog()
        map_manager = spawner.mapManager
        map_manager === nothing && return catalog
        theme = map_manager.floorTheme
        theme === nothing && return catalog

        min_x, max_x, min_y, max_y = theme.fabBounds
        nodes = _collect_node_positions(spawner)
        segments = spawner.connectionSegments
        hulls = spawner.nodeCollisionHulls
        path_hw = Float64(spawner.pathCollisionHalfWidth)
        bounds = _node_aabb(nodes)

        # Forbidden viz (path then hulls)
        for (x1, y1, x2, y2) in segments
            quad = _segment_quad(x1, y1, x2, y2, path_hw)
            quad === nothing && continue
            push!(catalog.debug_regions, PlacementRegion(Forbidden, quad, _centroid(quad)))
        end
        for hull in hulls
            isempty(hull) && continue
            push!(catalog.debug_regions, PlacementRegion(Forbidden, copy(hull), _centroid(hull)))
        end

        if bounds !== nothing
            nmin_x, nmax_x, nmin_y, nmax_y = bounds
            x0 = nmin_x - SIDEWALK_STREET_PAD
            x1 = nmax_x + SIDEWALK_STREET_PAD
            y0 = nmin_y - SIDEWALK_STREET_PAD
            y1 = nmax_y + SIDEWALK_STREET_PAD
            north = _rect_verts(x0, nmax_y + SIDEWALK_CURB, x1, nmax_y + SIDEWALK_CURB + SIDEWALK_BAND)
            south = _rect_verts(x0, nmin_y - SIDEWALK_CURB - SIDEWALK_BAND, x1, nmin_y - SIDEWALK_CURB)
            west = _rect_verts(nmin_x - SIDEWALK_CURB - SIDEWALK_BAND, y0, nmin_x - SIDEWALK_CURB, y1)
            east = _rect_verts(nmax_x + SIDEWALK_CURB, y0, nmax_x + SIDEWALK_CURB + SIDEWALK_BAND, y1)
            for rect in (north, south, west, east)
                push!(catalog.debug_regions, PlacementRegion(Sidewalk, rect, _centroid(rect)))
            end
        end

        _fill_grid_catalog!(
            catalog, min_x, max_x, min_y, max_y,
            hulls, segments, path_hw, bounds,
        )
        return catalog
    end

    function _fill_grid_catalog!(
        catalog::ZoneCatalog,
        min_x, max_x, min_y, max_y,
        hulls, segments, path_hw, bounds,
    )
        width = max_x - min_x
        height = max_y - min_y
        (width <= 0 || height <= 0) && return

        cols = max(1, ceil(Int, width / GRID_CELL))
        rows = max(1, ceil(Int, height / GRID_CELL))
        cell_w = width / cols
        cell_h = height / rows
        catalog.cell_size = min(cell_w, cell_h)
        cell_area = cell_w * cell_h

        types = Matrix{Int8}(undef, cols, rows)
        centers = Matrix{NTuple{2, Float64}}(undef, cols, rows)
        for j in 1:rows, i in 1:cols
            cx = min_x + (i - 0.5) * cell_w
            cy = min_y + (j - 0.5) * cell_h
            centers[i, j] = (cx, cy)
            types[i, j] = _cell_raw_type(cx, cy, hulls, segments, path_hw, bounds)
        end

        _classify_gap_components!(types)

        # Collect cells + enclosed pockets
        enclosed_components = Vector{Vector{NTuple{2, Int}}}()
        visited_enc = falses(cols, rows)
        for j in 1:rows, i in 1:cols
            t = types[i, j]
            t == CELL_BLOCKED && continue
            rtype = RegionType(t)
            push!(catalog.cells[rtype], centers[i, j])

            if rtype == Enclosed && !visited_enc[i, j]
                component = NTuple{2, Int}[]
                stack = NTuple{2, Int}[(i, j)]
                visited_enc[i, j] = true
                while !isempty(stack)
                    ci, cj = pop!(stack)
                    push!(component, (ci, cj))
                    for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                        ni, nj = ci + di, cj + dj
                        (ni < 1 || ni > cols || nj < 1 || nj > rows) && continue
                        visited_enc[ni, nj] && continue
                        types[ni, nj] == Int8(Enclosed) || continue
                        visited_enc[ni, nj] = true
                        push!(stack, (ni, nj))
                    end
                end
                push!(enclosed_components, component)
            end
        end

        for component in enclosed_components
            pocket_cells = NTuple{2, Float64}[centers[ci, cj] for (ci, cj) in component]
            push!(
                catalog.enclosed_pockets,
                ZonePocket(Enclosed, pocket_cells, length(pocket_cells) * cell_area),
            )
        end

        # Debug strips (Sidewalk uses continuous curb rects above; skip here)
        for j in 1:rows
            i = 1
            while i <= cols
                t = types[i, j]
                if t == CELL_BLOCKED || t == Int8(Sidewalk)
                    i += 1
                    continue
                end
                i_end = i
                while i_end <= cols && types[i_end, j] == t
                    i_end += 1
                end
                x0 = min_x + (i - 1) * cell_w
                x1 = min_x + (i_end - 1) * cell_w
                y0 = min_y + (j - 1) * cell_h
                y1 = y0 + cell_h
                rect = _rect_verts(x0, y0, x1, y1)
                push!(catalog.debug_regions, PlacementRegion(RegionType(t), rect, _centroid(rect)))
                i = i_end
            end
        end
    end

    function _cell_raw_type(
        cx::Float64, cy::Float64,
        hulls, segments, path_hw::Float64, bounds,
    )::Int8
        block_hw = path_hw + 0.12
        if _point_hits_any_hull(cx, cy, hulls, 0.08)
            return CELL_BLOCKED
        end
        if _dist_to_segments(cx, cy, segments) < block_hw
            return CELL_BLOCKED
        end
        if _in_sidewalk(cx, cy, bounds)
            return CELL_SIDEWALK
        end
        return _in_route_corridor(cx, cy, bounds) ? CELL_GAP : CELL_OUTER
    end

    function _classify_gap_components!(raw::Matrix{Int8})
        cols, rows = size(raw)
        visited = falses(cols, rows)
        for j in 1:rows, i in 1:cols
            raw[i, j] == CELL_GAP || continue
            visited[i, j] && continue

            component = NTuple{2, Int}[]
            stack = NTuple{2, Int}[(i, j)]
            visited[i, j] = true
            touches_open = false

            while !isempty(stack)
                ci, cj = pop!(stack)
                push!(component, (ci, cj))
                if ci == 1 || ci == cols || cj == 1 || cj == rows
                    touches_open = true
                end
                for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                    ni, nj = ci + di, cj + dj
                    if ni < 1 || ni > cols || nj < 1 || nj > rows
                        touches_open = true
                        continue
                    end
                    ntype = raw[ni, nj]
                    if ntype == CELL_OUTER
                        touches_open = true
                        continue
                    end
                    ntype == CELL_GAP || continue
                    visited[ni, nj] && continue
                    visited[ni, nj] = true
                    push!(stack, (ni, nj))
                end
            end

            final = touches_open ? Int8(Interstitial) : Int8(Enclosed)
            for (ci, cj) in component
                raw[ci, cj] = final
            end
        end

        for j in 1:rows, i in 1:cols
            if raw[i, j] == CELL_OUTER
                raw[i, j] = Int8(OuterCrust)
            elseif raw[i, j] == CELL_SIDEWALK
                raw[i, j] = Int8(Sidewalk)
            end
        end
    end

    """
    Sample a world position inside `allowed` zone types.
    `validate(x,y)` must return true for acceptance.
    Optional `cluster_anchors`: with `cluster_chance`, bias samples near prior same-type spawns.
    """
    function sample_zone_position(
        catalog::ZoneCatalog,
        rng::AbstractRNG,
        allowed::Vector{RegionType},
        radius::Float64,
        validate::Function;
        max_attempts::Int = 160,
        prefer_near_segments = nothing, # Vector of segments or nothing
        near_seg_min::Float64 = 0.0,
        near_seg_max::Float64 = Inf,
        zone_weights::Union{Nothing, Dict{RegionType, Float64}} = nothing,
        cluster_anchors = nothing, # Vector{<:NTuple{2,Float64}} or nothing
        cluster_chance::Float64 = 0.5,
        cluster_min::Float64 = 1.2,
        cluster_max::Float64 = 3.2,
        enclosed_role::Symbol = :any, # :large | :flowers | :fill | :any
    )
        catalog === nothing && return nothing

        # Enclosed with size-fit: filter pockets by area vs radius
        use_enclosed_pockets = length(allowed) == 1 && allowed[1] == Enclosed &&
                               !isempty(catalog.enclosed_pockets)
        weights = zone_weights === nothing ?
            (length(allowed) > 1 ? SCATTER_ZONE_WEIGHT : nothing) :
            zone_weights

        for _ in 1:max_attempts
            use_cluster = cluster_anchors !== nothing &&
                !isempty(cluster_anchors) &&
                rand(rng) < cluster_chance

            x, y = if use_cluster
                ax, ay = rand(rng, cluster_anchors)
                ang = rand(rng) * 2π
                dist = cluster_min + rand(rng) * (cluster_max - cluster_min)
                (ax + cos(ang) * dist, ay + sin(ang) * dist)
            else
                cx, cy = if use_enclosed_pockets
                    _sample_enclosed_cell(catalog, rng, radius; role = enclosed_role)
                else
                    _sample_allowed_cell(catalog, rng, allowed, weights)
                end
                cx === nothing && return nothing
                # Jitter inside cell
                half = catalog.cell_size * 0.35
                (cx + (rand(rng) * 2 - 1) * half, cy + (rand(rng) * 2 - 1) * half)
            end

            if prefer_near_segments !== nothing
                d = _dist_to_segments(x, y, prefer_near_segments)
                (d < near_seg_min || d > near_seg_max) && continue
            end

            validate(x, y) || continue
            return (x, y)
        end
        return nothing
    end

    function _sample_allowed_cell(
        catalog::ZoneCatalog,
        rng,
        allowed::Vector{RegionType},
        weights::Union{Nothing, Dict{RegionType, Float64}} = nothing,
    )
        if weights === nothing
            total = 0
            for t in allowed
                total += length(get(catalog.cells, t, NTuple{2, Float64}[]))
            end
            total == 0 && return (nothing, nothing)
            pick = rand(rng, 1:total)
            for t in allowed
                cells = get(catalog.cells, t, NTuple{2, Float64}[])
                n = length(cells)
                if pick <= n
                    return cells[pick]
                end
                pick -= n
            end
            return (nothing, nothing)
        end

        # Weighted by (cell count * zone weight) so OuterCrust doesn't dominate :scatter.
        weighted = Float64[]
        types = RegionType[]
        total_w = 0.0
        for t in allowed
            cells = get(catalog.cells, t, NTuple{2, Float64}[])
            n = length(cells)
            n == 0 && continue
            w = n * get(weights, t, 1.0)
            w <= 0 && continue
            push!(types, t)
            push!(weighted, w)
            total_w += w
        end
        total_w == 0 && return (nothing, nothing)
        r = rand(rng) * total_w
        acc = 0.0
        for (i, t) in enumerate(types)
            acc += weighted[i]
            if r <= acc
                return rand(rng, catalog.cells[t])
            end
        end
        return rand(rng, catalog.cells[types[end]])
    end

    function _pocket_allows_role(pocket::ZonePocket, role::Symbol)::Bool
        role == :any && return true
        role == :fill && return true
        role == :large && return pocket.largePlaced[] < 2
        role == :flowers && return pocket.flowersPlaced[] < 3
        return true
    end

    function _sample_enclosed_cell(
        catalog::ZoneCatalog,
        rng,
        radius::Float64;
        role::Symbol = :any,
    )
        min_area = max(0.5, π * radius * radius * 2.5)
        eligible = ZonePocket[]
        for p in catalog.enclosed_pockets
            _pocket_allows_role(p, role) || continue
            p.area >= min_area && push!(eligible, p)
        end
        if isempty(eligible)
            for p in catalog.enclosed_pockets
                _pocket_allows_role(p, role) || continue
                push!(eligible, p)
            end
        end
        isempty(eligible) && return (nothing, nothing)

        weights = Float64[p.area for p in eligible]
        total_w = sum(weights)
        r = rand(rng) * total_w
        acc = 0.0
        pocket = eligible[1]
        for (i, p) in enumerate(eligible)
            acc += weights[i]
            if r <= acc
                pocket = p
                break
            end
        end
        isempty(pocket.cells) && return (nothing, nothing)
        return rand(rng, pocket.cells)
    end

    """Nearest enclosed pocket to a world point, or nothing if far from all cells."""
    function find_enclosed_pocket(catalog::ZoneCatalog, x::Float64, y::Float64)
        best = nothing
        best_d = Inf
        max_d = catalog.cell_size * 1.6
        for p in catalog.enclosed_pockets
            for (cx, cy) in p.cells
                d = hypot(x - cx, y - cy)
                if d < best_d
                    best_d = d
                    best = p
                end
            end
        end
        (best !== nothing && best_d <= max_d) ? best : nothing
    end

    function note_enclosed_placement!(pocket::ZonePocket, role::Symbol)
        if role == :large
            pocket.largePlaced[] += 1
        elseif role == :flowers
            pocket.flowersPlaced[] += 1
        end
    end

    # --- geometry helpers ---

    function _collect_node_positions(spawner)
        nodes = NTuple{2, Float64}[]
        psm = spawner.mapManager.persistentStateManager
        (psm === nothing || psm.mapPoints === nothing) && return nodes
        scale = JulGame.SCALE_UNITS
        for (_, node_data) in psm.mapPoints
            pos = node_data["position"]
            push!(nodes, sprite_visual_center(Float64(pos.x) / scale, Float64(pos.y) / scale))
        end
        start_ent = spawner.mapManager.startingNodeEntity
        if start_ent !== nothing
            push!(
                nodes,
                sprite_visual_center(
                    Float64(start_ent.transform.position.x),
                    Float64(start_ent.transform.position.y),
                ),
            )
        end
        return nodes
    end

    function _node_aabb(nodes::Vector{NTuple{2, Float64}})
        isempty(nodes) && return nothing
        min_x = Inf
        max_x = -Inf
        min_y = Inf
        max_y = -Inf
        for (x, y) in nodes
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)
        end
        return (min_x, max_x, min_y, max_y)
    end

    function _segment_quad(x1::Float64, y1::Float64, x2::Float64, y2::Float64, half_width::Float64)
        dx = x2 - x1
        dy = y2 - y1
        len = hypot(dx, dy)
        len < 1e-6 && return nothing
        nx = -dy / len
        ny = dx / len
        return NTuple{2, Float64}[
            (x1 + nx * half_width, y1 + ny * half_width),
            (x2 + nx * half_width, y2 + ny * half_width),
            (x2 - nx * half_width, y2 - ny * half_width),
            (x1 - nx * half_width, y1 - ny * half_width),
        ]
    end

    function _rect_verts(x0::Float64, y0::Float64, x1::Float64, y1::Float64)
        return NTuple{2, Float64}[(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    end

    function _centroid(verts::Vector{NTuple{2, Float64}})
        isempty(verts) && return (0.0, 0.0)
        sx = 0.0
        sy = 0.0
        for (x, y) in verts
            sx += x
            sy += y
        end
        n = length(verts)
        return (sx / n, sy / n)
    end

    function _point_hits_any_hull(px::Float64, py::Float64, hulls, pad::Float64 = 0.0)
        for hull in hulls
            point_hits_hull(px, py, pad, hull) && return true
        end
        return false
    end

    function _dist_to_segments(px::Float64, py::Float64, segments)
        best = Inf
        for (x1, y1, x2, y2) in segments
            d = _dist_point_segment(px, py, x1, y1, x2, y2)
            best = min(best, d)
        end
        return best
    end

    function _dist_point_segment(px::Float64, py::Float64, x1::Float64, y1::Float64, x2::Float64, y2::Float64)
        dx = x2 - x1
        dy = y2 - y1
        if dx == 0.0 && dy == 0.0
            return hypot(px - x1, py - y1)
        end
        t = clamp(((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
        return hypot(px - (x1 + t * dx), py - (y1 + t * dy))
    end

    function _in_sidewalk(px::Float64, py::Float64, bounds)
        bounds === nothing && return false
        nmin_x, nmax_x, nmin_y, nmax_y = bounds
        x0 = nmin_x - SIDEWALK_STREET_PAD
        x1 = nmax_x + SIDEWALK_STREET_PAD
        y0 = nmin_y - SIDEWALK_STREET_PAD
        y1 = nmax_y + SIDEWALK_STREET_PAD

        north_y0 = nmax_y + SIDEWALK_CURB
        north_y1 = north_y0 + SIDEWALK_BAND
        south_y0 = nmin_y - SIDEWALK_CURB - SIDEWALK_BAND
        south_y1 = nmin_y - SIDEWALK_CURB
        in_ns = (px >= x0 && px <= x1) &&
            ((py >= north_y0 && py <= north_y1) || (py >= south_y0 && py <= south_y1))

        west_x0 = nmin_x - SIDEWALK_CURB - SIDEWALK_BAND
        west_x1 = nmin_x - SIDEWALK_CURB
        east_x0 = nmax_x + SIDEWALK_CURB
        east_x1 = nmax_x + SIDEWALK_CURB + SIDEWALK_BAND
        in_ew = (py >= y0 && py <= y1) &&
            ((px >= west_x0 && px <= west_x1) || (px >= east_x0 && px <= east_x1))

        return in_ns || in_ew
    end

    function _in_route_corridor(px::Float64, py::Float64, bounds)::Bool
        bounds === nothing && return false
        nmin_x, nmax_x, nmin_y, nmax_y = bounds
        return px >= nmin_x - ROUTE_CORRIDOR_PAD &&
               px <= nmax_x + ROUTE_CORRIDOR_PAD &&
               py >= nmin_y - ROUTE_CORRIDOR_PAD &&
               py <= nmax_y + ROUTE_CORRIDOR_PAD
    end
end
