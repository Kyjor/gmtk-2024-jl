module MapFabPlacementDebugModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule
    using JulGame.SDL2
    using ...MapFabZonesModule

    export build_placement_debug!, draw_placement_debug!, cycle_placement_debug_layer!

    const LAYER_OFF = 0
    const LAYER_SKELETON = 1
    const LAYER_REGIONS = 2
    const LAYER_REGIONS_LABELS = 3
    const LAYER_COUNT = 4
    const DEBUG_LAYER = 60
    const GRID_CELL = 0.85

    const REGION_COLORS = Dict{RegionType, NTuple{4, UInt8}}(
        OuterCrust => (60, 100, 220, 70),
        Interstitial => (40, 200, 90, 70),
        Sidewalk => (40, 200, 220, 90),
        Enclosed => (240, 140, 40, 90),
        Forbidden => (220, 50, 50, 100),
    )

    const REGION_LABELS = (
        (OuterCrust, "1 OuterCrust"),
        (Interstitial, "2 Interstitial (open)"),
        (Sidewalk, "3 Sidewalk"),
        (Enclosed, "4 Enclosed pocket"),
        (Forbidden, "5 Forbidden (art)"),
    )

    function build_placement_debug!(spawner)
        catalog = build_zone_catalog!(spawner)
        spawner.zoneCatalog = catalog
        empty!(spawner.placementDebugRegions)
        append!(spawner.placementDebugRegions, catalog.debug_regions)
    end

    function cycle_placement_debug_layer!(spawner)
        spawner.placementDebugLayer = (spawner.placementDebugLayer + 1) % LAYER_COUNT
    end

    function draw_placement_debug!(spawner)
        !JulGame.IS_DEBUG && return
        if JulGame.InputModule.get_button_pressed("F4")
            cycle_placement_debug_layer!(spawner)
        end

        layer = spawner.placementDebugLayer
        layer == LAYER_OFF && return

        cam = MAIN.scene.camera
        cam === nothing && return

        if layer >= LAYER_REGIONS
            _draw_regions!(spawner.placementDebugRegions, cam)
        end
        if layer >= LAYER_SKELETON
            _draw_skeleton!(spawner, cam)
        end
        if layer >= LAYER_REGIONS_LABELS
            _draw_region_labels!(spawner.placementDebugRegions, cam)
            _draw_legend!()
        end
    end

    function _world_to_screen(wx::Float64, wy::Float64, cam)
        S = JulGame.pixels_per_world_unit(cam)
        sx = (wx - (Float64(cam.position.x) + Float64(cam.offset.x))) * S
        sy = (wy - (Float64(cam.position.y) + Float64(cam.offset.y))) * S
        return sx, sy
    end

    function _draw_regions!(regions, cam)
        order = (OuterCrust, Interstitial, Enclosed, Sidewalk, Forbidden)
        for rtype in order
            for region in regions
                region.region_type == rtype || continue
                color = get(REGION_COLORS, region.region_type, (255, 255, 255, 80))
                _queue_filled_polygon!(region.vertices, color, cam)
            end
        end
    end

    function _queue_filled_polygon!(verts_world::Vector{NTuple{2, Float64}}, color::NTuple{4, UInt8}, cam)
        n = length(verts_world)
        n < 3 && return

        screen = NTuple{2, Float32}[]
        sizehint!(screen, n)
        for (wx, wy) in verts_world
            sx, sy = _world_to_screen(wx, wy, cam)
            push!(screen, (Float32(sx), Float32(sy)))
        end

        sdl_color = SDL2.SDL_Color(color[1], color[2], color[3], color[4])
        tri_count = n - 2
        vertices = Vector{SDL2.SDL_Vertex}(undef, tri_count * 3)
        v0 = screen[1]
        idx = 1
        for t in 1:tri_count
            a = screen[t + 1]
            b = screen[t + 2]
            vertices[idx] = SDL2.SDL_Vertex(SDL2.SDL_FPoint(v0[1], v0[2]), sdl_color, SDL2.SDL_FPoint(0.0f0, 0.0f0))
            vertices[idx + 1] = SDL2.SDL_Vertex(SDL2.SDL_FPoint(a[1], a[2]), sdl_color, SDL2.SDL_FPoint(0.0f0, 0.0f0))
            vertices[idx + 2] = SDL2.SDL_Vertex(SDL2.SDL_FPoint(b[1], b[2]), sdl_color, SDL2.SDL_FPoint(0.0f0, 0.0f0))
            idx += 3
        end

        JulGame.Rendering.queue_render_function(
            () -> begin
                SDL2.SDL_SetRenderDrawBlendMode(JulGame.Renderer::Ptr{SDL2.SDL_Renderer}, SDL2.SDL_BLENDMODE_BLEND)
                SDL2.SDL_RenderGeometry(
                    JulGame.Renderer::Ptr{SDL2.SDL_Renderer},
                    C_NULL,
                    vertices,
                    length(vertices),
                    C_NULL,
                    0,
                )
            end;
            layer = DEBUG_LAYER,
            isWorldEntity = false,
        )
    end

    function _draw_skeleton!(spawner, cam)
        seg_lines = NTuple{4, Float32}[]
        for (x1, y1, x2, y2) in spawner.connectionSegments
            sx1, sy1 = _world_to_screen(x1, y1, cam)
            sx2, sy2 = _world_to_screen(x2, y2, cam)
            push!(seg_lines, (Float32(sx1), Float32(sy1), Float32(sx2), Float32(sy2)))
        end

        node_lines = NTuple{4, Float32}[]
        for hull in spawner.nodeCollisionHulls
            n = length(hull)
            n < 2 && continue
            for j in 1:n
                x1, y1 = hull[j]
                x2, y2 = hull[mod1(j + 1, n)]
                sx1, sy1 = _world_to_screen(x1, y1, cam)
                sx2, sy2 = _world_to_screen(x2, y2, cam)
                push!(node_lines, (Float32(sx1), Float32(sy1), Float32(sx2), Float32(sy2)))
            end
        end

        JulGame.Rendering.queue_render_function(
            () -> begin
                renderer = JulGame.Renderer::Ptr{SDL2.SDL_Renderer}
                SDL2.SDL_SetRenderDrawBlendMode(renderer, SDL2.SDL_BLENDMODE_BLEND)
                SDL2.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xc8)
                for (x1, y1, x2, y2) in seg_lines
                    SDL2.SDL_RenderDrawLineF(renderer, x1, y1, x2, y2)
                end
                SDL2.SDL_SetRenderDrawColor(renderer, 0xff, 0xdc, 0x50, 0xdc)
                for (x1, y1, x2, y2) in node_lines
                    SDL2.SDL_RenderDrawLineF(renderer, x1, y1, x2, y2)
                end
            end;
            layer = DEBUG_LAYER + 1,
            isWorldEntity = false,
        )
    end

    function _draw_region_labels!(regions, cam)
        for (i, region) in enumerate(regions)
            if region.region_type == OuterCrust ||
               region.region_type == Interstitial ||
               region.region_type == Enclosed
                _region_span_x(region) < GRID_CELL * 2.5 && continue
            end
            cx, cy = region.centroid
            sx, sy = _world_to_screen(cx, cy, cam)
            DisplayTextModule.display_text(
                "fabdbg_lbl_$i",
                string(Int(region.region_type));
                position = JulGame.Math.Vector2(round(Int, sx) - 4, round(Int, sy) - 8),
                fontSize = 14,
                color = (255, 255, 255, 255),
                isWorldEntity = false,
                layer = DEBUG_LAYER + 2,
            )
        end
    end

    function _region_span_x(region::PlacementRegion)
        isempty(region.vertices) && return 0.0
        xs = (v[1] for v in region.vertices)
        return maximum(xs) - minimum(xs)
    end

    function _draw_legend!()
        DisplayTextModule.display_text(
            "fabdbg_legend_title",
            "Fab placement (F4)";
            position = JulGame.Math.Vector2(12, 12),
            fontSize = 16,
            color = (255, 255, 255, 255),
            isWorldEntity = false,
            layer = DEBUG_LAYER + 3,
        )
        for (i, (_, label)) in enumerate(REGION_LABELS)
            DisplayTextModule.display_text(
                "fabdbg_legend_$i",
                label;
                position = JulGame.Math.Vector2(12, 12 + 20 * i),
                fontSize = 14,
                color = (220, 220, 220, 255),
                isWorldEntity = false,
                layer = DEBUG_LAYER + 3,
            )
        end
    end
end
