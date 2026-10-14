module PatternResolverModule
    using ..PatternKindsModule
    using ..PatternMatchModule
    using ..PatternRegistryModule
    using ..PatternClearHelpersModule
    using ..PatternAnimatorModule
    export resolve_creation, resolve_activation, resolve_second_blasts
    export PendingSecondBlasts, take_pending_second_blasts!, queue_second_blasts!

    const _PENDING_BLASTS = PatternCell[]

    function queue_second_blasts!(cells::Vector{PatternCell})
        for c in cells
            c in _PENDING_BLASTS || push!(_PENDING_BLASTS, c)
        end
    end

    function take_pending_second_blasts!()::Vector{PatternCell}
        out = copy(_PENDING_BLASTS)
        empty!(_PENDING_BLASTS)
        return out
    end

    """
    For each match component, try registry definitions (by priority via classify)
    and build mutations + create events. Bomb clears skip creation.
    """
    function resolve_creation(snapshot::MatchSnapshot)::PatternResolution
        plan = PatternPlan()
        snapshot.is_bomb && return PatternResolution(plan)

        for comp in snapshot.components
            kind = classify_component_kind(comp, snapshot.match_threshold)
            kind == PATTERN_NONE && continue

            def = find_pattern_def(kind)
            if def !== nothing
                frag = def.try_create(snapshot, comp)
                if frag !== nothing
                    _merge_plan!(plan, frag)
                    continue
                end
            end

            # Fallback create without definition
            anchor = pick_anchor_cell(comp, kind, snapshot.swap_anchor)
            push!(plan.mutations, PatternMutation(anchor, kind, comp.piece_type))
            push!(plan.protected_cells, anchor)
            profile = anim_profile_for(kind)
            if profile == :pattern_none
                profile = kind == PATTERN_STRIPE_H ? :stripe_h :
                          kind == PATTERN_STRIPE_V ? :stripe_v :
                          kind == PATTERN_WRAPPED ? :wrapped : :colorbomb
            end
            push!(plan.events, PatternEvent(:pattern_create, profile;
                cell = anchor,
                cells = copy(comp.cells),
                meta = Dict{Symbol, Any}(:pattern_kind => kind, :piece_type => comp.piece_type)))
        end

        return PatternResolution(plan)
    end

    function _merge_plan!(dest::PatternPlan, src::PatternPlan)
        append!(dest.mutations, src.mutations)
        union!(dest.protected_cells, src.protected_cells)
        union!(dest.extra_destroy_cells, src.extra_destroy_cells)
        append!(dest.events, src.events)
        append!(dest.pending_second_blasts, src.pending_second_blasts)
    end

    """
    Expand clears for patterned pieces inside the current match set.
    Handles special+special combos via registry before single expansions.
    """
    function resolve_activation(ctx::ActivationContext)::PatternResolution
        plan = PatternPlan()

        # Collect patterned cells in the match
        patterned = PatternCell[]
        for cell in ctx.matched_cells
            k = get(ctx.cell_patterns, cell, PATTERN_NONE)
            is_patterned(k) && push!(patterned, cell)
        end
        isempty(patterned) && return PatternResolution(plan)

        used = Set{PatternCell}()

        # Combo pairs first
        for i in 1:length(patterned)
            patterned[i] in used && continue
            for j in (i + 1):length(patterned)
                patterned[j] in used && continue
                a = patterned[i]
                b = patterned[j]
                ka = ctx.cell_patterns[a]
                kb = ctx.cell_patterns[b]
                combo = find_combo_def(ka, kb)
                combo === nothing && continue
                expansion = combo.expand_combo(ctx, a, b)
                push!(used, a)
                push!(used, b)
                union!(plan.extra_destroy_cells, expansion.cells)
                append!(plan.events, expansion.events)
                append!(plan.pending_second_blasts, expansion.pending_second_blasts)
            end
        end

        # Remaining singles (expand_clear events include activate/sweep VFX)
        for cell in patterned
            cell in used && continue
            kind = ctx.cell_patterns[cell]
            def = find_pattern_def(kind)
            def === nothing && continue
            expansion = def.expand_clear(ctx, cell, kind)
            union!(plan.extra_destroy_cells, expansion.cells)
            append!(plan.events, expansion.events)
            append!(plan.pending_second_blasts, expansion.pending_second_blasts)
        end

        return PatternResolution(plan)
    end

    """Build a clear plan for queued wrapped second blasts after settle."""
    function resolve_second_blasts(ctx::ActivationContext, blast_cells::Vector{PatternCell})::PatternResolution
        plan = PatternPlan()
        for cell in blast_cells
            cells = cells_in_rect(cell[1], cell[2], 1, ctx.grid_width, ctx.grid_height)
            union!(plan.extra_destroy_cells, cells)
            push!(plan.events, PatternEvent(:pattern_second_blast, :wrapped; cell = cell, cells = cells))
        end
        return PatternResolution(plan)
    end
end
