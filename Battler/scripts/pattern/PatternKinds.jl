module PatternKindsModule
    export PatternKind, PATTERN_NONE, PATTERN_STRIPE_H, PATTERN_STRIPE_V, PATTERN_WRAPPED, PATTERN_COLORBOMB
    export PatternCell, MatchComponent, MatchSnapshot
    export PatternPlan, PatternMutation, PatternEvent, PatternResolution
    export ActivationContext, ClearExpansion
    export is_patterned, is_stripe, pattern_priority_rank

    @enum PatternKind::UInt8 begin
        PATTERN_NONE = 0
        PATTERN_STRIPE_H = 1
        PATTERN_STRIPE_V = 2
        PATTERN_WRAPPED = 3
        PATTERN_COLORBOMB = 4
    end

    const PatternCell = Tuple{Int64, Int64}  # (col, row) 1-based

    """One connected same-type match blob with line-run metadata."""
    struct MatchComponent
        piece_type::String
        cells::Vector{PatternCell}
        max_row_run::Int
        max_col_run::Int
        has_row_col_cross::Bool  # row≥3 and col≥3 share a cell (L/T/+)
    end

    """Immutable board match view for pattern classification (no entity pointers)."""
    struct MatchSnapshot
        components::Vector{MatchComponent}
        swap_anchor::Union{Nothing, PatternCell}
        match_threshold::Int
        grid_width::Int
        grid_height::Int
        is_bomb::Bool
        is_initial_match::Bool
    end

    """Upgrade one cell to a pattern special; keep it on the board."""
    struct PatternMutation
        cell::PatternCell
        kind::PatternKind
        piece_type::String
    end

    """Logic → animator event (animator decides presentation)."""
    struct PatternEvent
        kind::Symbol  # :pattern_create, :pattern_activate, :pattern_clear_sweep, ...
        profile::Symbol
        cell::Union{Nothing, PatternCell}
        cells::Vector{PatternCell}
        meta::Dict{Symbol, Any}
    end

    PatternEvent(kind::Symbol, profile::Symbol; cell = nothing, cells = PatternCell[], meta = Dict{Symbol, Any}()) =
        PatternEvent(kind, profile, cell, cells, meta)

    """Creation / activation plan from the resolver."""
    struct PatternPlan
        mutations::Vector{PatternMutation}
        # Cells that must NOT be destroyed (spawn anchors)
        protected_cells::Set{PatternCell}
        # Extra cells to destroy (activation expansion), beyond the original match set
        extra_destroy_cells::Set{PatternCell}
        events::Vector{PatternEvent}
        # Wrapped second blast after settle
        pending_second_blasts::Vector{PatternCell}
    end

    function PatternPlan()
        PatternPlan(
            PatternMutation[],
            Set{PatternCell}(),
            Set{PatternCell}(),
            PatternEvent[],
            PatternCell[],
        )
    end

    struct PatternResolution
        plan::PatternPlan
    end

    """Context for expanding a special's clear."""
    struct ActivationContext
        grid_width::Int
        grid_height::Int
        # name at each cell for color-bomb partner type, etc.
        cell_types::Dict{PatternCell, String}
        # Pattern kinds currently on the board at cells in the match
        cell_patterns::Dict{PatternCell, PatternKind}
        partner_type::Union{Nothing, String}  # type swapped/matched with color bomb
        matched_cells::Set{PatternCell}
    end

    struct ClearExpansion
        cells::Vector{PatternCell}
        events::Vector{PatternEvent}
        pending_second_blasts::Vector{PatternCell}
        consumes_special::Bool
    end

    function ClearExpansion(cells::Vector{PatternCell}; events = PatternEvent[], pending_second_blasts = PatternCell[], consumes_special::Bool = true)
        ClearExpansion(cells, events, pending_second_blasts, consumes_special)
    end

    is_patterned(k::PatternKind) = k != PATTERN_NONE
    is_stripe(k::PatternKind) = k == PATTERN_STRIPE_H || k == PATTERN_STRIPE_V

    function pattern_priority_rank(k::PatternKind)::Int
        k == PATTERN_COLORBOMB && return 3
        k == PATTERN_WRAPPED && return 2
        is_stripe(k) && return 1
        return 0
    end
end
