module PatternClearHelpersModule
    using ..PatternKindsModule
    export cells_in_row, cells_in_col, cells_in_rect, cells_of_type
    export expand_stripe, expand_wrapped, expand_colorbomb
    export expand_stripe_cross, expand_stripe_wrapped_band, expand_wrapped_large

    function cells_in_row(row::Int, width::Int)::Vector{PatternCell}
        return PatternCell[(c, row) for c in 1:width]
    end

    function cells_in_col(col::Int, height::Int)::Vector{PatternCell}
        return PatternCell[(col, r) for r in 1:height]
    end

    function cells_in_rect(cx::Int, cy::Int, radius::Int, width::Int, height::Int)::Vector{PatternCell}
        out = PatternCell[]
        for c in (cx - radius):(cx + radius)
            for r in (cy - radius):(cy + radius)
                (c < 1 || r < 1 || c > width || r > height) && continue
                push!(out, (c, r))
            end
        end
        return out
    end

    function cells_of_type(ctx::ActivationContext, piece_type::String)::Vector{PatternCell}
        out = PatternCell[]
        for (cell, t) in ctx.cell_types
            t == piece_type && push!(out, cell)
        end
        return out
    end

    function expand_stripe(ctx::ActivationContext, cell::PatternCell, kind::PatternKind)::ClearExpansion
        cells = kind == PATTERN_STRIPE_H ? cells_in_row(cell[2], ctx.grid_width) :
                kind == PATTERN_STRIPE_V ? cells_in_col(cell[1], ctx.grid_height) :
                PatternCell[]
        return ClearExpansion(
            cells;
            events = [PatternEvent(:pattern_clear_sweep, kind == PATTERN_STRIPE_H ? :stripe_h : :stripe_v;
                cell = cell, cells = cells, meta = Dict{Symbol, Any}(:axis => kind == PATTERN_STRIPE_H ? :row : :col))],
        )
    end

    function expand_wrapped(ctx::ActivationContext, cell::PatternCell, _kind::PatternKind)::ClearExpansion
        cells = cells_in_rect(cell[1], cell[2], 1, ctx.grid_width, ctx.grid_height)
        return ClearExpansion(
            cells;
            events = [
                PatternEvent(:pattern_clear_sweep, :wrapped; cell = cell, cells = cells),
            ],
            pending_second_blasts = PatternCell[cell],
        )
    end

    function expand_colorbomb(ctx::ActivationContext, cell::PatternCell, _kind::PatternKind)::ClearExpansion
        partner = ctx.partner_type
        if partner === nothing
            # Fallback: pick most common type among matched cells (excluding bomb cell)
            counts = Dict{String, Int}()
            for mc in ctx.matched_cells
                mc == cell && continue
                t = get(ctx.cell_types, mc, "")
                isempty(t) && continue
                counts[t] = get(counts, t, 0) + 1
            end
            if !isempty(counts)
                partner = first(sort(collect(counts); by = p -> -p[2]))[1]
            end
        end
        cells = partner === nothing ? PatternCell[cell] : cells_of_type(ctx, partner)
        if !(cell in cells)
            push!(cells, cell)
        end
        return ClearExpansion(
            cells;
            events = [PatternEvent(:pattern_clear_sweep, :colorbomb;
                cell = cell, cells = cells, meta = Dict{Symbol, Any}(:partner_type => partner))],
        )
    end

    function expand_stripe_cross(ctx::ActivationContext, cell_a::PatternCell, cell_b::PatternCell)::ClearExpansion
        # Clear row of one and col of the other (full cross through both if same cell).
        cells = unique(vcat(
            cells_in_row(cell_a[2], ctx.grid_width),
            cells_in_col(cell_a[1], ctx.grid_height),
            cells_in_row(cell_b[2], ctx.grid_width),
            cells_in_col(cell_b[1], ctx.grid_height),
        ))
        return ClearExpansion(
            cells;
            events = [PatternEvent(:pattern_combo, :combo; cell = cell_a, cells = cells)],
        )
    end

    function expand_stripe_wrapped_band(ctx::ActivationContext, stripe_cell::PatternCell, stripe_kind::PatternKind, _wrap_cell::PatternCell)::ClearExpansion
        cells = PatternCell[]
        if stripe_kind == PATTERN_STRIPE_H
            for dr in -1:1
                r = stripe_cell[2] + dr
                (r < 1 || r > ctx.grid_height) && continue
                append!(cells, cells_in_row(r, ctx.grid_width))
            end
        else
            for dc in -1:1
                c = stripe_cell[1] + dc
                (c < 1 || c > ctx.grid_width) && continue
                append!(cells, cells_in_col(c, ctx.grid_height))
            end
        end
        cells = unique(cells)
        return ClearExpansion(
            cells;
            events = [PatternEvent(:pattern_combo, :combo; cell = stripe_cell, cells = cells)],
        )
    end

    function expand_wrapped_large(ctx::ActivationContext, cell_a::PatternCell, cell_b::PatternCell)::ClearExpansion
        # ~5x5 around midpoint
        mx = div(cell_a[1] + cell_b[1], 2)
        my = div(cell_a[2] + cell_b[2], 2)
        cells = cells_in_rect(mx, my, 2, ctx.grid_width, ctx.grid_height)
        return ClearExpansion(
            cells;
            events = [PatternEvent(:pattern_combo, :combo; cell = (mx, my), cells = cells)],
            pending_second_blasts = PatternCell[(mx, my)],
        )
    end
end
