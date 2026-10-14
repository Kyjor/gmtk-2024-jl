module PatternMatchModule
    using ..PatternKindsModule
    using ..PatternDebugModule
    export longest_runs_in_component, classify_component_kind, pick_anchor_cell
    export build_match_component, preview_pattern_kind

    """
    Longest contiguous horizontal / vertical runs inside `cells` (same-type component).
    Also reports whether any cell sits on both a row-run≥3 and col-run≥3 (L/T/+).
    """
    function longest_runs_in_component(cells::Vector{PatternCell})
        cell_set = Set{PatternCell}(cells)
        max_row = 0
        max_col = 0
        has_cross = false

        # Group by row → sort cols; group by col → sort rows
        by_row = Dict{Int64, Vector{Int64}}()
        by_col = Dict{Int64, Vector{Int64}}()
        for (c, r) in cells
            push!(get!(by_row, r, Int64[]), c)
            push!(get!(by_col, c, Int64[]), r)
        end

        row_run_at = Dict{PatternCell, Int}()
        col_run_at = Dict{PatternCell, Int}()

        for (r, cols) in by_row
            sort!(cols)
            i = 1
            while i <= length(cols)
                j = i
                while j + 1 <= length(cols) && cols[j + 1] == cols[j] + 1
                    j += 1
                end
                run_len = j - i + 1
                max_row = max(max_row, run_len)
                for k in i:j
                    row_run_at[(cols[k], r)] = run_len
                end
                i = j + 1
            end
        end

        for (c, rows) in by_col
            sort!(rows)
            i = 1
            while i <= length(rows)
                j = i
                while j + 1 <= length(rows) && rows[j + 1] == rows[j] + 1
                    j += 1
                end
                run_len = j - i + 1
                max_col = max(max_col, run_len)
                for k in i:j
                    col_run_at[(c, rows[k])] = run_len
                end
                i = j + 1
            end
        end

        for cell in cells
            rr = get(row_run_at, cell, 0)
            cr = get(col_run_at, cell, 0)
            if rr >= 3 && cr >= 3
                has_cross = true
                break
            end
        end

        return (max_row_run = max_row, max_col_run = max_col, has_row_col_cross = has_cross,
                row_run_at = row_run_at, col_run_at = col_run_at)
    end

    function build_match_component(piece_type::String, cells::Vector{PatternCell})::MatchComponent
        runs = longest_runs_in_component(cells)
        return MatchComponent(
            piece_type,
            copy(cells),
            runs.max_row_run,
            runs.max_col_run,
            runs.has_row_col_cross,
        )
    end

    """
    Classify one component into a pattern kind (or PATTERN_NONE for plain 3).
    Priority: color bomb (5+) > wrapped (L/T) > stripe (exactly 4 in one axis).
    Honors PatternDebug creation toggles (disabled kinds produce no special).
    """
    function classify_component_kind(comp::MatchComponent, match_threshold::Int = 3)::PatternKind
        kind = classify_component_kind_raw(comp, match_threshold)
        kind == PATTERN_NONE && return PATTERN_NONE
        is_pattern_creation_enabled(kind) || return PATTERN_NONE
        return kind
    end

    function classify_component_kind_raw(comp::MatchComponent, match_threshold::Int = 3)::PatternKind
        length(comp.cells) < match_threshold && return PATTERN_NONE

        if comp.max_row_run >= 5 || comp.max_col_run >= 5
            return PATTERN_COLORBOMB
        end
        if comp.has_row_col_cross
            return PATTERN_WRAPPED
        end
        # Exactly 4 on one axis (5+ already handled). Prefer the longer axis; ties → H then V.
        if comp.max_row_run == 4 && comp.max_col_run == 4
            return PATTERN_STRIPE_H
        elseif comp.max_row_run == 4
            return PATTERN_STRIPE_H
        elseif comp.max_col_run == 4
            return PATTERN_STRIPE_V
        end
        return PATTERN_NONE
    end

    function pick_anchor_cell(
        comp::MatchComponent,
        kind::PatternKind,
        swap_anchor::Union{Nothing, PatternCell},
    )::PatternCell
        cell_set = Set{PatternCell}(comp.cells)
        if swap_anchor !== nothing && swap_anchor in cell_set
            return swap_anchor
        end

        runs = longest_runs_in_component(comp.cells)
        if kind == PATTERN_WRAPPED || kind == PATTERN_COLORBOMB
            # Prefer a cross cell (intersection), else centroid.
            for cell in comp.cells
                rr = get(runs.row_run_at, cell, 0)
                cr = get(runs.col_run_at, cell, 0)
                if rr >= 3 && cr >= 3
                    return cell
                end
            end
        elseif kind == PATTERN_STRIPE_H
            for cell in comp.cells
                if get(runs.row_run_at, cell, 0) == 4
                    return cell
                end
            end
        elseif kind == PATTERN_STRIPE_V
            for cell in comp.cells
                if get(runs.col_run_at, cell, 0) == 4
                    return cell
                end
            end
        end

        # Geometric center of bounding box, snap to nearest component cell.
        sx = 0
        sy = 0
        for (c, r) in comp.cells
            sx += c
            sy += r
        end
        n = length(comp.cells)
        cx = sx / n
        cy = sy / n
        best = comp.cells[1]
        best_d = Inf
        for cell in comp.cells
            d = (cell[1] - cx)^2 + (cell[2] - cy)^2
            if d < best_d
                best_d = d
                best = cell
            end
        end
        return best
    end

    """For swap preview: what pattern would this component create?"""
    function preview_pattern_kind(comp::MatchComponent, match_threshold::Int = 3)::PatternKind
        return classify_component_kind(comp, match_threshold)
    end
end
