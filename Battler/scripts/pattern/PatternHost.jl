"""
Thin adapters between GridController entities and the pure pattern subsystem.
"""
module PatternHostModule
    using JulGame
    using ..PatternKindsModule
    using ..PatternMatchModule
    using ..PatternResolverModule
    using ..PatternAnimatorModule
    using ..PatternVisualsModule
    using ..PatternRegistryModule

    export build_components_from_entities
    export build_match_snapshot
    export build_activation_context
    export apply_pattern_mutations!
    export entity_pattern, set_entity_pattern!
    export collect_entities_at_cells
    export preview_patterns_for_components
    export run_creation_pass!
    export run_activation_pass!
    export run_second_blast_pass!
    export bind_grid_context!

    function entity_grid_cell(entity)::Union{Nothing, PatternCell}
        entity === nothing && return nothing
        try
            if length(entity.scripts) > 0 && hasproperty(entity.scripts[1], :gridPosition)
                gp = entity.scripts[1].gridPosition
                return (convert(Int64, round(gp.x)), convert(Int64, round(gp.y)))
            end
        catch
        end
        return nothing
    end

    function entity_pattern(entity)::PatternKind
        entity === nothing && return PATTERN_NONE
        try
            if length(entity.scripts) > 0 && hasproperty(entity.scripts[1], :pattern)
                return entity.scripts[1].pattern
            end
        catch
        end
        return PATTERN_NONE
    end

    function set_entity_pattern!(entity, kind::PatternKind)
        entity === nothing && return
        try
            if length(entity.scripts) > 0 && hasproperty(entity.scripts[1], :pattern)
                entity.scripts[1].pattern = kind
                apply_pattern_visual!(entity, kind)
            end
        catch e
            @debug "set_entity_pattern!: $e"
        end
    end

    """
    Flood-fill connected components among destroy entities (by name + 4-adjacency),
    with run metadata for pattern classification.
    """
    function build_components_from_entities(entities, match_threshold::Int)::Vector{MatchComponent}
        # Map cell -> type and entity
        cell_type = Dict{PatternCell, String}()
        for ent in entities
            cell = entity_grid_cell(ent)
            cell === nothing && continue
            cell_type[cell] = string(ent.name)
        end
        positions_by_type = Dict{String, Set{PatternCell}}()
        for (cell, t) in cell_type
            push!(get!(positions_by_type, t, Set{PatternCell}()), cell)
        end

        comps = MatchComponent[]
        for (t, pos_set) in positions_by_type
            visited = Set{PatternCell}()
            for pos in pos_set
                pos in visited && continue
                component_cells = _flood(pos, pos_set, visited)
                length(component_cells) < match_threshold && continue
                push!(comps, build_match_component(t, component_cells))
            end
        end
        return comps
    end

    function _flood(start::PatternCell, positions::Set{PatternCell}, visited::Set{PatternCell})::Vector{PatternCell}
        stack = PatternCell[start]
        out = PatternCell[]
        while !isempty(stack)
            p = pop!(stack)
            p in visited && continue
            p in positions || continue
            push!(visited, p)
            push!(out, p)
            for n in ((p[1] - 1, p[2]), (p[1] + 1, p[2]), (p[1], p[2] - 1), (p[1], p[2] + 1))
                n in positions && !(n in visited) && push!(stack, n)
            end
        end
        return out
    end

    function build_match_snapshot(
        entities,
        match_threshold::Int,
        grid_width::Int,
        grid_height::Int;
        swap_anchor::Union{Nothing, PatternCell} = nothing,
        is_bomb::Bool = false,
        is_initial_match::Bool = false,
    )::MatchSnapshot
        comps = is_bomb ? MatchComponent[] : build_components_from_entities(entities, match_threshold)
        return MatchSnapshot(comps, swap_anchor, match_threshold, grid_width, grid_height, is_bomb, is_initial_match)
    end

    function build_activation_context(
        grid_pieces,
        matched_entities,
        grid_width::Int,
        grid_height::Int;
        partner_type::Union{Nothing, String} = nothing,
    )::ActivationContext
        cell_types = Dict{PatternCell, String}()
        cell_patterns = Dict{PatternCell, PatternKind}()
        matched_cells = Set{PatternCell}()

        for i in 1:grid_width
            for j in 1:grid_height
                ent = grid_pieces[i, j]
                ent === nothing && continue
                cell = (convert(Int64, i), convert(Int64, j))
                cell_types[cell] = string(ent.name)
                cell_patterns[cell] = entity_pattern(ent)
            end
        end
        for ent in matched_entities
            cell = entity_grid_cell(ent)
            cell === nothing && continue
            push!(matched_cells, cell)
            cell_types[cell] = string(ent.name)
            cell_patterns[cell] = entity_pattern(ent)
        end

        return ActivationContext(grid_width, grid_height, cell_types, cell_patterns, partner_type, matched_cells)
    end

    function apply_pattern_mutations!(grid_pieces, mutations::Vector{PatternMutation})
        for m in mutations
            c, r = m.cell
            (c < 1 || r < 1 || c > size(grid_pieces, 1) || r > size(grid_pieces, 2)) && continue
            ent = grid_pieces[c, r]
            ent === nothing && continue
            set_entity_pattern!(ent, m.kind)
        end
    end

    function collect_entities_at_cells(grid_pieces, cells)::Vector{Any}
        out = Any[]
        seen = Set{String}()
        for (c, r) in cells
            (c < 1 || r < 1 || c > size(grid_pieces, 1) || r > size(grid_pieces, 2)) && continue
            ent = grid_pieces[c, r]
            ent === nothing && continue
            eid = string(ent.id)
            eid in seen && continue
            push!(seen, eid)
            push!(out, ent)
        end
        return out
    end

    function filter_protected!(entities_to_destroy, protected::Set{PatternCell})
        filter!(entities_to_destroy) do ent
            cell = entity_grid_cell(ent)
            cell === nothing && return true
            return !(cell in protected)
        end
    end

    function preview_patterns_for_components(comps::Vector{MatchComponent}, match_threshold::Int)
        out = NamedTuple[]
        for comp in comps
            kind = preview_pattern_kind(comp, match_threshold)
            kind == PATTERN_NONE && continue
            push!(out, (
                piece_type = comp.piece_type,
                pattern = kind,
                label = pattern_overlay_label(kind),
                cells = copy(comp.cells),
            ))
        end
        return out
    end

    """
    Creation pass: classify → mutate anchors → protect them from destroy → play create anims.
    Skips components that already contain a patterned piece (those activate instead of re-rolling).
    Returns the resolution plan.
    """
    function run_creation_pass!(
        grid_pieces,
        entities_to_destroy,
        snapshot::MatchSnapshot;
        play::Bool = true,
    )::PatternResolution
        # Drop components that are activating existing specials
        filtered = MatchComponent[]
        for comp in snapshot.components
            has_special = false
            for cell in comp.cells
                c, r = cell
                (c < 1 || r < 1 || c > size(grid_pieces, 1) || r > size(grid_pieces, 2)) && continue
                ent = grid_pieces[c, r]
                if is_patterned(entity_pattern(ent))
                    has_special = true
                    break
                end
            end
            has_special && continue
            push!(filtered, comp)
        end
        snap = MatchSnapshot(
            filtered,
            snapshot.swap_anchor,
            snapshot.match_threshold,
            snapshot.grid_width,
            snapshot.grid_height,
            snapshot.is_bomb,
            snapshot.is_initial_match,
        )
        resolution = resolve_creation(snap)
        apply_pattern_mutations!(grid_pieces, resolution.plan.mutations)
        filter_protected!(entities_to_destroy, resolution.plan.protected_cells)
        play && play_events!(resolution.plan.events)
        return resolution
    end

    """
    Activation pass: expand clears from patterned pieces in the match; merge into destroy list.
    """
    function run_activation_pass!(
        grid_pieces,
        entities_to_destroy,
        grid_width::Int,
        grid_height::Int;
        partner_type::Union{Nothing, String} = nothing,
        play::Bool = true,
    )::PatternResolution
        ctx = build_activation_context(grid_pieces, entities_to_destroy, grid_width, grid_height; partner_type = partner_type)
        resolution = resolve_activation(ctx)
        extras = collect_entities_at_cells(grid_pieces, collect(resolution.plan.extra_destroy_cells))
        seen = Set{String}([string(e.id) for e in entities_to_destroy])
        for ent in extras
            eid = string(ent.id)
            eid in seen && continue
            push!(seen, eid)
            push!(entities_to_destroy, ent)
        end
        play && play_events!(resolution.plan.events)
        queue_second_blasts!(resolution.plan.pending_second_blasts)
        return resolution
    end

    """
    After settle: prepare wrapped second blasts.
    Returns (entities_to_destroy, events). Caller plays events + gates destroy.
    """
    function run_second_blast_pass!(grid_pieces, grid_width::Int, grid_height::Int)
        blasts = take_pending_second_blasts!()
        isempty(blasts) && return (Any[], PatternEvent[])
        ctx = build_activation_context(grid_pieces, Any[], grid_width, grid_height)
        resolution = resolve_second_blasts(ctx, blasts)
        ents = collect_entities_at_cells(grid_pieces, collect(resolution.plan.extra_destroy_cells))
        return (ents, resolution.plan.events)
    end

    function bind_grid_context!(grid_controller)
        set_grid_context!(
            start_x = Float64(grid_controller.gridStartX),
            start_y = Float64(grid_controller.gridStartY),
            cell_w = Float64(grid_controller.gridCellWidth),
            cell_h = Float64(grid_controller.gridCellHeight),
            grid_pieces = grid_controller.gridPieces,
        )
    end
end
