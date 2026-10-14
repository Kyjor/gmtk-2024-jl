"""
ComboStarsModule

Screen-space combo star VFX: one star per combo step flies from the triggering
match to a packed row under the "Combo! +N" HUD, lands with squash-stretch,
and flies away when the combo ends.
"""
module ComboStarsModule
    using JulGame
    include("Easings.jl")

    export spawn_to!, dismiss!, clear!, update

    # --- Tunables ---
    const STAR_SIZE = 40.0
    const STARS_PER_ROW = 5
    const GAP_X = 6.0
    const GAP_Y = 4.0
    const ROW_ANCHOR_OFFSET = (350.0, 175.0)  # under combo image at (350, 50)
    const MAX_STARS = 19

    const FLY_DURATION = 0.38
    const LAND_DURATION = 0.26
    const LEAVE_DURATION = 0.50
    const LEAVE_STAGGER = 0.04
    const IDLE_FOLLOW = 12.0

    const FLY_SPIN = 360.0  # degrees; lands upright (multiple of 360)
    const LEAVE_SPIN = 720.0
    const SQUASH_AMOUNT = 0.35
    const FLY_START_SCALE = 0.6
    const LEAVE_END_SCALE = 0.5
    const BEZIER_LIFT = 120.0

    const RENDER_LIFETIME_MS = 100
    const UI_LAYER = 25

    mutable struct ComboStar
        uid::Int
        slot::Int
        phase::Symbol          # :flying | :landing | :idle | :leaving
        elapsed::Float64
        leave_delay::Float64
        pos_x::Float64
        pos_y::Float64
        from_x::Float64
        from_y::Float64
        ctrl_x::Float64
        ctrl_y::Float64
        to_x::Float64
        to_y::Float64
        spin::Float64
        rotation::Float64
        scale_x::Float64
        scale_y::Float64
        alpha::Int
        on_arrive::Union{Nothing, Function}  # set by a targeted dismiss; called when the leave ends
    end

    mutable struct ComboStarsState
        stars::Vector{ComboStar}
        next_uid::Int
        combo_length::Int
        art_path::String
        grid_controller::Any
    end

    const STATE = ComboStarsState(ComboStar[], 1, 0, "", nothing)

    function star_art_for_length(combo_length::Int)::String
        globals = JulGame.UserGlobals["Module"]
        name = combo_length >= 10 ? "star10to19" : "star1to9"
        return globals.get_asset_path("combo", name)
    end

    """Hi-res star for the damage chip. Flying row stars stay on the small art."""
    function star_chip_art()::String
        return JulGame.UserGlobals["Module"].get_asset_path("combo", "starchip")
    end

    function refresh_art!()
        STATE.art_path = star_art_for_length(STATE.combo_length)
    end

    function screen_size()
        cam = MAIN.scene.camera
        if cam === nothing
            return (1920.0, 1080.0)
        end
        return (Float64(cam.size.x), Float64(cam.size.y))
    end

    """Rows of STARS_PER_ROW, each row centered on the combo HUD anchor."""
    function slot_screen_pos(slot::Int, total::Int)
        W, _ = screen_size()
        anchor_x = W / 2.0 + ROW_ANCHOR_OFFSET[1]
        anchor_y = ROW_ANCHOR_OFFSET[2]

        row = div(slot - 1, STARS_PER_ROW)
        col = (slot - 1) % STARS_PER_ROW
        stars_in_row = min(STARS_PER_ROW, total - row * STARS_PER_ROW)

        row_width = stars_in_row * STAR_SIZE + max(0, stars_in_row - 1) * GAP_X
        start_x = anchor_x - row_width / 2.0

        x = start_x + col * (STAR_SIZE + GAP_X) + STAR_SIZE / 2.0
        y = anchor_y + row * (STAR_SIZE + GAP_Y) + STAR_SIZE / 2.0
        return (x, y)
    end

    function world_to_screen(wx::Float64, wy::Float64)
        cam = MAIN.scene.camera
        if cam === nothing
            W, H = screen_size()
            return (W / 2.0, H / 2.0)
        end
        S = Float64(JulGame.pixels_per_world_unit(cam))
        sx = (wx - (Float64(cam.position.x) + Float64(cam.offset.x))) * S
        sy = (wy - (Float64(cam.position.y) + Float64(cam.offset.y))) * S
        return (sx, sy)
    end

    function grid_cell_to_world(grid, gx::Int, gy::Int)
        wx = Float64(grid.gridStartX) + (Float64(gx) - 1.0) * Float64(grid.gridCellWidth)
        wy = Float64(grid.gridStartY) + (Float64(gy) - 1.0) * Float64(grid.gridCellHeight)
        return (wx, wy)
    end

    function match_screen_origin(positions, gridController)
        if gridController === nothing || positions === nothing || isempty(positions)
            W, H = screen_size()
            return (W / 2.0, H / 2.0)
        end
        try
            sx = 0.0
            sy = 0.0
            n = 0
            for pos in positions
                gx = Int(pos[1])
                gy = Int(pos[2])
                wx, wy = grid_cell_to_world(gridController, gx, gy)
                px, py = world_to_screen(wx, wy)
                sx += px
                sy += py
                n += 1
            end
            if n == 0
                W, H = screen_size()
                return (W / 2.0, H / 2.0)
            end
            return (sx / n, sy / n)
        catch
            W, H = screen_size()
            return (W / 2.0, H / 2.0)
        end
    end

    function resolve_grid(gridController)
        gridController !== nothing && return gridController
        STATE.grid_controller !== nothing && return STATE.grid_controller
        try
            ent = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "Grid")
            if ent !== nothing && !isempty(ent.scripts)
                return ent.scripts[1]
            end
        catch
        end
        return nothing
    end

    function bezier2(x0, y0, cx, cy, x1, y1, t)
        inv = 1.0 - t
        x = inv * inv * x0 + 2 * inv * t * cx + t * t * x1
        y = inv * inv * y0 + 2 * inv * t * cy + t * t * y1
        return (x, y)
    end

    function make_star(slot::Int, from_x::Float64, from_y::Float64, total::Int)::ComboStar
        to_x, to_y = slot_screen_pos(slot, total)
        mid_x = (from_x + to_x) / 2.0
        mid_y = min(from_y, to_y) - BEZIER_LIFT
        spin = FLY_SPIN * (slot % 2 == 0 ? 1.0 : -1.0)
        return ComboStar(
            STATE.next_uid,
            slot,
            :flying,
            0.0,
            0.0,
            from_x, from_y,
            from_x, from_y,
            mid_x, mid_y,
            to_x, to_y,
            spin,
            0.0,
            FLY_START_SCALE, FLY_START_SCALE,
            255,
            nothing,
        )
    end

    function positions_for_slot(state, slot::Int)
        try
            history = state.match_history
            if history !== nothing && length(history) >= slot
                return history[slot].positions
            end
        catch
        end
        return nothing
    end

    """
    Spawn stars so the row matches `target_count` (capped at MAX_STARS).
    Only missing stars are created; each uses its match_history entry as origin.
    """
    function spawn_to!(target_count::Int, state=nothing; gridController=nothing)
        target = clamp(target_count, 0, MAX_STARS)
        STATE.combo_length = target_count
        refresh_art!()
        grid = resolve_grid(gridController)

        current = count(s -> s.phase != :leaving, STATE.stars)
        if target <= current
            recompute_idle_targets!()
            return
        end

        total_after = target
        for slot in (current + 1):target
            positions = positions_for_slot(state, slot)
            from_x, from_y = match_screen_origin(positions, grid)
            star = make_star(slot, from_x, from_y, total_after)
            STATE.next_uid += 1
            push!(STATE.stars, star)
        end
        recompute_idle_targets!()
    end

    function recompute_idle_targets!()
        active = filter(s -> s.phase != :leaving, STATE.stars)
        total = length(active)
        for (i, star) in enumerate(active)
            star.slot = i
            tx, ty = slot_screen_pos(i, total)
            star.to_x = tx
            star.to_y = ty
        end
    end

    """
    Send every star away. `target_for(i, star)` may return `(x, y, on_arrive)` to fly that star to a
    screen point and call `on_arrive()` when it lands; `nothing` keeps the default fly-off.
    """
    function dismiss!(; target_for = nothing)
        for (i, star) in enumerate(STATE.stars)
            if star.phase == :leaving
                continue
            end
            star.phase = :leaving
            star.elapsed = 0.0
            star.leave_delay = (i - 1) * LEAVE_STAGGER
            star.from_x = star.pos_x
            star.from_y = star.pos_y
            star.spin = LEAVE_SPIN * (i % 2 == 0 ? 1.0 : -1.0)
            target = target_for === nothing ? nothing : target_for(i, star)
            if target === nothing
                # Fly outward/up from current slot
                star.to_x = star.pos_x + (star.pos_x - screen_size()[1] / 2.0) * 0.35
                star.to_y = star.pos_y - 180.0 - 20.0 * (i % 3)
                star.ctrl_x = (star.from_x + star.to_x) / 2.0
                star.ctrl_y = star.from_y - 80.0
            else
                star.to_x, star.to_y, star.on_arrive = Float64(target[1]), Float64(target[2]), target[3]
                star.ctrl_x = (star.from_x + star.to_x) / 2.0
                star.ctrl_y = min(star.from_y, star.to_y) - BEZIER_LIFT
            end
        end
        STATE.combo_length = 0
    end

    function clear!()
        empty!(STATE.stars)
        STATE.combo_length = 0
        STATE.art_path = ""
        STATE.grid_controller = nothing
    end

    function update_star!(star::ComboStar, dt::Float64)
        if star.phase == :flying
            star.elapsed += dt
            t = clamp(star.elapsed / FLY_DURATION, 0.0, 1.0)
            eased = ease_in_out_cubic(t)
            star.pos_x, star.pos_y = bezier2(
                star.from_x, star.from_y,
                star.ctrl_x, star.ctrl_y,
                star.to_x, star.to_y,
                eased,
            )
            spin_t = ease_out_cubic(t)
            star.rotation = star.spin * spin_t
            s = FLY_START_SCALE + (1.0 - FLY_START_SCALE) * ease_out_cubic(t)
            star.scale_x = s
            star.scale_y = s
            star.alpha = 255
            if t >= 1.0
                star.phase = :landing
                star.elapsed = 0.0
                star.pos_x = star.to_x
                star.pos_y = star.to_y
                star.rotation = 0.0
                star.scale_x = 1.0
                star.scale_y = 1.0
            end
        elseif star.phase == :landing
            star.elapsed += dt
            t = clamp(star.elapsed / LAND_DURATION, 0.0, 1.0)
            e = exp(-6.0 * t) * sin(2π * 2.2 * t)
            star.scale_x = 1.0 + SQUASH_AMOUNT * e
            star.scale_y = 1.0 - SQUASH_AMOUNT * e
            star.pos_x = star.to_x
            star.pos_y = star.to_y
            star.rotation = 0.0
            star.alpha = 255
            if t >= 1.0
                star.phase = :idle
                star.elapsed = 0.0
                star.scale_x = 1.0
                star.scale_y = 1.0
            end
        elseif star.phase == :idle
            # Ease toward current slot (row re-pack when new stars arrive)
            k = 1.0 - exp(-IDLE_FOLLOW * dt)
            star.pos_x += (star.to_x - star.pos_x) * k
            star.pos_y += (star.to_y - star.pos_y) * k
            star.rotation = 0.0
            star.scale_x = 1.0
            star.scale_y = 1.0
            star.alpha = 255
        elseif star.phase == :leaving
            if star.leave_delay > 0.0
                star.leave_delay -= dt
                return true
            end
            star.elapsed += dt
            t = clamp(star.elapsed / LEAVE_DURATION, 0.0, 1.0)
            eased = ease_in_cubic(t)
            star.pos_x, star.pos_y = bezier2(
                star.from_x, star.from_y,
                star.ctrl_x, star.ctrl_y,
                star.to_x, star.to_y,
                eased,
            )
            star.rotation = star.spin * t * t
            s = 1.0 + (LEAVE_END_SCALE - 1.0) * eased
            star.scale_x = s
            star.scale_y = s
            star.alpha = star.on_arrive === nothing ? Int(round(255 * (1.0 - eased))) : 255
            if t >= 1.0
                if star.on_arrive !== nothing
                    try
                        star.on_arrive()
                    catch e
                        @debug "ComboStars on_arrive: $e"
                    end
                end
                return false
            end
        end
        return true
    end

    function render_star!(star::ComboStar)
        art = isempty(STATE.art_path) ? star_art_for_length(max(STATE.combo_length, 1)) : STATE.art_path
        w = STAR_SIZE * star.scale_x
        h = STAR_SIZE * star.scale_y
        # position is top-left with anchor=:none
        px = star.pos_x - w / 2.0
        py = star.pos_y - h / 2.0
        try
            img = JulGame.ImmediateUIModule.immediate_image(
                "combo_star_$(star.uid)",
                art;
                anchor = :none,
                position = JulGame.Math.Vector2(px, py),
                size = JulGame.Math.Vector2(w, h),
                rotation = Float64(star.rotation),
                color = (255, 255, 255, clamp(star.alpha, 0, 255)),
                layer = UI_LAYER,
                lifetime = RENDER_LIFETIME_MS,
            )
            # UIImage renders originalSize, and ImmediateUI only writes size — lock both
            # every frame or fly-in scale from the first frame sticks.
            if img !== nothing
                sz = JulGame.Math.Vector2(w, h)
                img.size = sz
                img.originalSize = sz
            end
        catch e
            @debug "ComboStars render: $e"
        end
    end

    function update(deltaTime::Float64, gridController=nothing)
        if gridController !== nothing
            STATE.grid_controller = gridController
        end
        isempty(STATE.stars) && return

        keep = ComboStar[]
        for star in STATE.stars
            if update_star!(star, Float64(deltaTime))
                push!(keep, star)
                render_star!(star)
            end
        end
        if length(keep) != length(STATE.stars)
            empty!(STATE.stars)
            append!(STATE.stars, keep)
        end
    end
end
