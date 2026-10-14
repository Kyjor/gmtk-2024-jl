module MapSpriteMaskModule
    using JulGame
    using JulGame.SDL2

    export SpriteAlphaShape,
           get_sprite_alpha_shape,
           hull_to_world,
           path_half_width_wu,
           opaque_radius_wu,
           point_hits_hull,
           hull_hits_forbidden,
           hulls_overlap,
           clear_sprite_alpha_shape_cache!,
           sprite_visual_center,
           ppu0_transform_from_visual_center,
           path_sprite_placement

    const ALPHA_THRESHOLD = UInt8(16)

    # Center-anchored sprites with pixelsPerUnit==0 and scale==1 are laid out on the
    # 1×1 world cell at `transform.position`; visual center is therefore position + 0.5.
    # With non-uniform scale, visual center is transform + 0.5 * scale (per axis).
    const PPU0_CENTER_OFFSET = 0.5

    """
    Cached opaque silhouette for a map sprite (pixelsPerUnit == 0 → world = px / SCALE_UNITS).
    `hullLocalPx` is convex hull in pixel space with origin at image center (+y down).
    `opaqueCenterLocalPx` is the opaque spine/centroid offset from image center (+y down).
    """
    struct SpriteAlphaShape
        imagePath::String
        widthPx::Int
        heightPx::Int
        hullLocalPx::Vector{NTuple{2, Float64}}
        opaqueHalfHeightPx::Float64
        opaqueRadiusPx::Float64
        opaqueCenterLocalPx::NTuple{2, Float64}
    end

    const SHAPE_CACHE = Dict{String, SpriteAlphaShape}()

    """World-space visual center for a ppu==0, :center-anchored sprite at unit scale."""
    @inline function sprite_visual_center(transform_x::Float64, transform_y::Float64)
        return (transform_x + PPU0_CENTER_OFFSET, transform_y + PPU0_CENTER_OFFSET)
    end

    """
    Transform position so a ppu==0 center-anchored sprite's rendered box center
    lands on `(visual_x, visual_y)` given its transform scale.
    """
    @inline function ppu0_transform_from_visual_center(
        visual_x::Float64,
        visual_y::Float64,
        scale_x::Float64,
        scale_y::Float64,
    )
        return (visual_x - 0.5 * scale_x, visual_y - 0.5 * scale_y)
    end

    """
    Place a stretched/rotated path sprite so its geometric center sits on the
    segment midpoint. Endpoints should be node *transform* positions (not +0.5);
    ppu0 center-anchoring is compensated via scale so the rendered center lands
    on the same visual mid as unit-scale nodes (transform + 0.5).
    Returns `(tx, ty, scale_x, scale_y, angle_deg)`.
    """
    function path_sprite_placement(
        shape::SpriteAlphaShape,
        x1::Float64, y1::Float64,
        x2::Float64, y2::Float64;
        pixels_per_world::Float64 = Float64(JulGame.SCALE_UNITS),
    )
        dx = x2 - x1
        dy = y2 - y1
        dist_px = hypot(dx, dy) * pixels_per_world
        scale_x = shape.widthPx > 0 ? dist_px / Float64(shape.widthPx) : 1.0
        scale_y = 1.0
        mid_x = (x1 + x2) * 0.5
        mid_y = (y1 + y2) * 0.5
        # Unit-scale node visual mid is (mid + 0.5, mid + 0.5). Path visual
        # center is transform + 0.5*scale — solve for transform.
        tx = mid_x + PPU0_CENTER_OFFSET - 0.5 * scale_x
        ty = mid_y + PPU0_CENTER_OFFSET - 0.5 * scale_y
        return (tx, ty, scale_x, scale_y, rad2deg(atan(dy, dx)))
    end

    function clear_sprite_alpha_shape_cache!()
        empty!(SHAPE_CACHE)
    end

    function get_sprite_alpha_shape(imagePath::String)::SpriteAlphaShape
        return get!(SHAPE_CACHE, imagePath) do
            _build_sprite_alpha_shape(imagePath)
        end
    end

    function hull_to_world(
        shape::SpriteAlphaShape,
        world_x::Float64,
        world_y::Float64;
        pixels_per_world::Float64 = Float64(JulGame.SCALE_UNITS),
    )
        s = 1.0 / pixels_per_world
        return NTuple{2, Float64}[
            (world_x + lx * s, world_y + ly * s) for (lx, ly) in shape.hullLocalPx
        ]
    end

    function path_half_width_wu(
        shape::SpriteAlphaShape;
        pad_wu::Float64 = 0.06,
        pixels_per_world::Float64 = Float64(JulGame.SCALE_UNITS),
    )
        return shape.opaqueHalfHeightPx / pixels_per_world + pad_wu
    end

    function opaque_radius_wu(
        shape::SpriteAlphaShape;
        pad_wu::Float64 = 0.06,
        pixels_per_world::Float64 = Float64(JulGame.SCALE_UNITS),
    )
        return shape.opaqueRadiusPx / pixels_per_world + pad_wu
    end

    """
    True if a disk at (px,py) with radius `r` intersects the hull (inside or within `r` of an edge).
    """
    function point_hits_hull(
        px::Float64,
        py::Float64,
        r::Float64,
        hull::Vector{NTuple{2, Float64}},
    )::Bool
        isempty(hull) && return false
        if _point_in_polygon(px, py, hull)
            return true
        end
        n = length(hull)
        r2 = r * r
        for i in 1:n
            x1, y1 = hull[i]
            x2, y2 = hull[mod1(i + 1, n)]
            if _dist_point_segment_sq(px, py, x1, y1, x2, y2) < r2
                return true
            end
        end
        return false
    end

    """
    True if the fab opaque hull (world space, centered at visual center) intersects
    any node hull or the path forbidden band.
    """
    function hull_hits_forbidden(
        fab_hull::Vector{NTuple{2, Float64}},
        node_hulls::Vector{Vector{NTuple{2, Float64}}},
        segments::Vector{NTuple{4, Float64}},
        path_half_width::Float64;
        pad::Float64 = 0.06,
    )::Bool
        isempty(fab_hull) && return false
        # Fab verts vs node hulls + path band
        for (fx, fy) in fab_hull
            for nh in node_hulls
                point_hits_hull(fx, fy, pad, nh) && return true
            end
            if !isempty(segments)
                min_d = path_half_width + pad
                for (x1, y1, x2, y2) in segments
                    if sqrt(_dist_point_segment_sq(fx, fy, x1, y1, x2, y2)) < min_d
                        return true
                    end
                end
            end
        end
        # Node verts inside fab hull (convex–convex catch for deep overlaps)
        for nh in node_hulls
            for (nx, ny) in nh
                point_hits_hull(nx, ny, pad, fab_hull) && return true
            end
        end
        return false
    end

    """
    True if two convex world-space hulls overlap (vertex / edge-mid samples with pad).
    """
    function hulls_overlap(
        a::Vector{NTuple{2, Float64}},
        b::Vector{NTuple{2, Float64}};
        pad::Float64 = 0.08,
    )::Bool
        (isempty(a) || isempty(b)) && return false
        _hull_samples_hit_other(a, b, pad) && return true
        _hull_samples_hit_other(b, a, pad) && return true
        return false
    end

    function _hull_samples_hit_other(
        src::Vector{NTuple{2, Float64}},
        other::Vector{NTuple{2, Float64}},
        pad::Float64,
    )::Bool
        n = length(src)
        for i in 1:n
            x, y = src[i]
            point_hits_hull(x, y, pad, other) && return true
            x2, y2 = src[mod1(i + 1, n)]
            mx = (x + x2) * 0.5
            my = (y + y2) * 0.5
            point_hits_hull(mx, my, pad, other) && return true
        end
        return false
    end

    function _build_sprite_alpha_shape(imagePath::String)::SpriteAlphaShape
        fullPath = joinpath(JulGame.BasePath, "assets", "images", imagePath)
        surface = JulGame.Component.SpriteModule.get_or_load_surface(fullPath, imagePath)
        if surface == C_NULL
            @warn "MapSpriteMask: failed to load $imagePath"
            return SpriteAlphaShape(imagePath, 1, 1, NTuple{2, Float64}[(0.0, 0.0)], 0.0, 0.0, (0.0, 0.0))
        end

        SDL2.LibSDL2.SDL_LockSurface(surface)
        try
            surf = unsafe_load(surface)
            w = Int(surf.w)
            h = Int(surf.h)
            pitch = Int(surf.pitch) ÷ 4
            pixels = unsafe_wrap(Array, Ptr{UInt32}(surf.pixels), (pitch * h,); own = false)
            format = surf.format

            cx = (w - 1) * 0.5
            cy = (h - 1) * 0.5
            silhouette = NTuple{2, Float64}[]
            max_r = 0.0
            max_abs_y = 0.0
            opaque_cols = 0
            thickness_sum = 0.0
            spine_y_sum = 0.0
            opaque_area = 0
            opaque_x_sum = 0.0
            opaque_y_sum = 0.0

            for y in 0:(h - 1)
                row_min = typemax(Int)
                row_max = typemin(Int)
                for x in 0:(w - 1)
                    a = _pixel_alpha(pixels[y * pitch + x + 1], format)
                    a < ALPHA_THRESHOLD && continue
                    row_min = min(row_min, x)
                    row_max = max(row_max, x)
                    dx = x - cx
                    dy = y - cy
                    max_r = max(max_r, hypot(dx, dy))
                    max_abs_y = max(max_abs_y, abs(dy))
                    opaque_area += 1
                    opaque_x_sum += x
                    opaque_y_sum += y
                end
                if row_min <= row_max
                    push!(silhouette, (row_min - cx, y - cy))
                    push!(silhouette, (row_max - cx, y - cy))
                end
            end

            for x in 0:(w - 1)
                col_min = typemax(Int)
                col_max = typemin(Int)
                for y in 0:(h - 1)
                    a = _pixel_alpha(pixels[y * pitch + x + 1], format)
                    a < ALPHA_THRESHOLD && continue
                    col_min = min(col_min, y)
                    col_max = max(col_max, y)
                end
                if col_min <= col_max
                    push!(silhouette, (x - cx, col_min - cy))
                    push!(silhouette, (x - cx, col_max - cy))
                    opaque_cols += 1
                    thickness_sum += (col_max - col_min + 1)
                    spine_y_sum += 0.5 * (col_min + col_max)
                end
            end

            half_h = if opaque_cols > 0
                0.5 * (thickness_sum / opaque_cols)
            else
                max_abs_y
            end
            half_h = max(half_h, 0.0)

            # Prefer column-spine for path strips; fall back to area centroid.
            opaque_center = if opaque_cols > 0
                (0.0, spine_y_sum / opaque_cols - cy)
            elseif opaque_area > 0
                (opaque_x_sum / opaque_area - cx, opaque_y_sum / opaque_area - cy)
            else
                (0.0, 0.0)
            end

            hull = _convex_hull(silhouette)
            if isempty(hull)
                hull = NTuple{2, Float64}[(0.0, 0.0)]
                max_r = 0.0
                half_h = 0.0
                opaque_center = (0.0, 0.0)
            end

            return SpriteAlphaShape(imagePath, w, h, hull, half_h, max_r, opaque_center)
        finally
            SDL2.LibSDL2.SDL_UnlockSurface(surface)
        end
    end

    function _pixel_alpha(pixel::UInt32, format::Ptr{SDL2.SDL_PixelFormat})::UInt8
        r = Ref{UInt8}()
        g = Ref{UInt8}()
        b = Ref{UInt8}()
        a = Ref{UInt8}()
        SDL2.LibSDL2.SDL_GetRGBA(pixel, format, r, g, b, a)
        return a[]
    end

    function _convex_hull(points::Vector{NTuple{2, Float64}})
        isempty(points) && return NTuple{2, Float64}[]
        uniq = unique(points)
        length(uniq) == 1 && return uniq
        sorted = sort(uniq)
        length(sorted) == 2 && return sorted

        function cross(o, a, b)
            return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
        end

        lower = NTuple{2, Float64}[]
        for p in sorted
            while length(lower) >= 2 && cross(lower[end - 1], lower[end], p) <= 0
                pop!(lower)
            end
            push!(lower, p)
        end
        upper = NTuple{2, Float64}[]
        for p in Iterators.reverse(sorted)
            while length(upper) >= 2 && cross(upper[end - 1], upper[end], p) <= 0
                pop!(upper)
            end
            push!(upper, p)
        end
        pop!(lower)
        pop!(upper)
        return vcat(lower, upper)
    end

    function _point_in_polygon(px::Float64, py::Float64, hull::Vector{NTuple{2, Float64}})::Bool
        n = length(hull)
        n < 3 && return false
        inside = false
        j = n
        for i in 1:n
            xi, yi = hull[i]
            xj, yj = hull[j]
            if ((yi > py) != (yj > py)) &&
               (px < (xj - xi) * (py - yi) / (yj - yi + 0.0) + xi)
                inside = !inside
            end
            j = i
        end
        return inside
    end

    function _dist_point_segment_sq(
        px::Float64, py::Float64,
        x1::Float64, y1::Float64,
        x2::Float64, y2::Float64,
    )::Float64
        dx = x2 - x1
        dy = y2 - y1
        if dx == 0.0 && dy == 0.0
            ex = px - x1
            ey = py - y1
            return ex * ex + ey * ey
        end
        t = clamp(((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
        ex = px - (x1 + t * dx)
        ey = py - (y1 + t * dy)
        return ex * ex + ey * ey
    end
end
