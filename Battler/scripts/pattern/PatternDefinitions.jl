module PatternDefinitionsModule
    using ..PatternKindsModule
    using ..PatternMatchModule
    using ..PatternRegistryModule
    using ..PatternClearHelpersModule
    export register_default_patterns!

    function _make_create(kind::PatternKind, profile::Symbol)
        return function (snapshot::MatchSnapshot, comp::MatchComponent)
            classified = classify_component_kind(comp, snapshot.match_threshold)
            classified != kind && return nothing
            anchor = pick_anchor_cell(comp, kind, snapshot.swap_anchor)
            plan = PatternPlan()
            push!(plan.mutations, PatternMutation(anchor, kind, comp.piece_type))
            push!(plan.protected_cells, anchor)
            push!(plan.events, PatternEvent(:pattern_create, profile;
                cell = anchor,
                cells = copy(comp.cells),
                meta = Dict{Symbol, Any}(:pattern_kind => kind, :piece_type => comp.piece_type)))
            return plan
        end
    end

    function register_default_patterns!()
        clear_registry!()

        register_pattern!(PatternDefinition(
            :colorbomb, PATTERN_COLORBOMB, 300, :colorbomb,
            _make_create(PATTERN_COLORBOMB, :colorbomb),
            expand_colorbomb,
        ))
        register_pattern!(PatternDefinition(
            :wrapped, PATTERN_WRAPPED, 200, :wrapped,
            _make_create(PATTERN_WRAPPED, :wrapped),
            expand_wrapped,
        ))
        register_pattern!(PatternDefinition(
            :stripe_h, PATTERN_STRIPE_H, 100, :stripe_h,
            _make_create(PATTERN_STRIPE_H, :stripe_h),
            expand_stripe,
        ))
        register_pattern!(PatternDefinition(
            :stripe_v, PATTERN_STRIPE_V, 100, :stripe_v,
            _make_create(PATTERN_STRIPE_V, :stripe_v),
            expand_stripe,
        ))

        # Combos — stripe H sentinel means "any stripe" when paired with itself via find_combo_def
        register_combo!(ComboDefinition(
            :stripe_stripe, PATTERN_STRIPE_H, PATTERN_STRIPE_H, 400, :combo,
            (ctx, a, b) -> expand_stripe_cross(ctx, a, b),
        ))
        register_combo!(ComboDefinition(
            :stripe_wrapped, PATTERN_STRIPE_H, PATTERN_WRAPPED, 350, :combo,
            function (ctx, a, b)
                ka = get(ctx.cell_patterns, a, PATTERN_NONE)
                kb = get(ctx.cell_patterns, b, PATTERN_NONE)
                if is_stripe(ka)
                    return expand_stripe_wrapped_band(ctx, a, ka, b)
                else
                    return expand_stripe_wrapped_band(ctx, b, kb, a)
                end
            end,
        ))
        register_combo!(ComboDefinition(
            :wrapped_wrapped, PATTERN_WRAPPED, PATTERN_WRAPPED, 360, :combo,
            (ctx, a, b) -> expand_wrapped_large(ctx, a, b),
        ))
        register_combo!(ComboDefinition(
            :bomb_stripe, PATTERN_COLORBOMB, PATTERN_STRIPE_H, 380, :combo,
            function (ctx, a, b)
                # Clear all of partner type (from the non-bomb / matched type), then stripe axis through bomb cell
                bomb_cell = get(ctx.cell_patterns, a, PATTERN_NONE) == PATTERN_COLORBOMB ? a : b
                other = bomb_cell == a ? b : a
                other_kind = get(ctx.cell_patterns, other, PATTERN_NONE)
                partner = get(ctx.cell_types, other, ctx.partner_type)
                cells = partner === nothing ? PatternCell[] : cells_of_type(ctx, partner)
                append!(cells, expand_stripe(ctx, bomb_cell, is_stripe(other_kind) ? other_kind : PATTERN_STRIPE_H).cells)
                cells = unique(cells)
                return ClearExpansion(cells; events = [PatternEvent(:pattern_combo, :combo; cell = bomb_cell, cells = cells)])
            end,
        ))
        register_combo!(ComboDefinition(
            :bomb_wrapped, PATTERN_COLORBOMB, PATTERN_WRAPPED, 380, :combo,
            function (ctx, a, b)
                bomb_cell = get(ctx.cell_patterns, a, PATTERN_NONE) == PATTERN_COLORBOMB ? a : b
                wrap_cell = bomb_cell == a ? b : a
                partner = ctx.partner_type
                if partner === nothing
                    partner = get(ctx.cell_types, wrap_cell, nothing)
                end
                cells = partner === nothing ? PatternCell[] : cells_of_type(ctx, partner)
                append!(cells, cells_in_rect(wrap_cell[1], wrap_cell[2], 1, ctx.grid_width, ctx.grid_height))
                cells = unique(cells)
                return ClearExpansion(
                    cells;
                    events = [PatternEvent(:pattern_combo, :combo; cell = bomb_cell, cells = cells)],
                    pending_second_blasts = PatternCell[wrap_cell],
                )
            end,
        ))
    end

    # Auto-register on load
    register_default_patterns!()
end
