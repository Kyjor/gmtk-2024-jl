module PatternRegistryModule
    using ..PatternKindsModule
    using ..PatternMatchModule
    export PatternDefinition, ComboDefinition
    export register_pattern!, register_combo!, clear_registry!
    export all_pattern_definitions, find_pattern_def, find_combo_def
    export anim_profile_for

    struct PatternDefinition
        id::Symbol
        kind::PatternKind
        priority::Int
        anim_profile::Symbol
        # (snapshot, component) -> Union{Nothing, PatternPlan}  (creation fragment)
        try_create::Function
        # (ActivationContext, cell, kind) -> ClearExpansion
        expand_clear::Function
    end

    struct ComboDefinition
        id::Symbol
        kind_a::PatternKind
        kind_b::PatternKind
        priority::Int
        anim_profile::Symbol
        # (ActivationContext, cell_a, cell_b) -> ClearExpansion
        expand_combo::Function
    end

    const _PATTERNS = PatternDefinition[]
    const _COMBOS = ComboDefinition[]

    function clear_registry!()
        empty!(_PATTERNS)
        empty!(_COMBOS)
    end

    function register_pattern!(def::PatternDefinition)
        filter!(d -> d.id != def.id, _PATTERNS)
        push!(_PATTERNS, def)
        sort!(_PATTERNS, by = d -> -d.priority)
        return def
    end

    function register_combo!(def::ComboDefinition)
        filter!(d -> d.id != def.id, _COMBOS)
        push!(_COMBOS, def)
        sort!(_COMBOS, by = d -> -d.priority)
        return def
    end

    all_pattern_definitions() = _PATTERNS

    function find_pattern_def(kind::PatternKind)::Union{Nothing, PatternDefinition}
        for d in _PATTERNS
            d.kind == kind && return d
        end
        return nothing
    end

    """Match combo defs. `PATTERN_STRIPE_H` in a def means any stripe (H or V)."""
    function find_combo_def(a::PatternKind, b::PatternKind)::Union{Nothing, ComboDefinition}
        function side_match(def_kind::PatternKind, actual::PatternKind)::Bool
            if is_stripe(def_kind)
                return is_stripe(actual)
            end
            return def_kind == actual
        end
        for d in _COMBOS
            if (side_match(d.kind_a, a) && side_match(d.kind_b, b)) ||
               (side_match(d.kind_a, b) && side_match(d.kind_b, a))
                return d
            end
        end
        return nothing
    end

    function anim_profile_for(kind::PatternKind)::Symbol
        def = find_pattern_def(kind)
        def === nothing && return :pattern_none
        return def.anim_profile
    end
end
