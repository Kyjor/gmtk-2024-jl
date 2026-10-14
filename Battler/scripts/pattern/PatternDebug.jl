module PatternDebugModule
    using ..PatternKindsModule
    export is_pattern_creation_enabled, set_pattern_creation_enabled!, toggle_pattern_creation!
    export pattern_debug_entries, reset_pattern_creation_enabled!

    const _CREATION_ENABLED = Dict{PatternKind, Bool}(
        PATTERN_STRIPE_H => false,
        PATTERN_STRIPE_V => false,
        PATTERN_WRAPPED => false,
        PATTERN_COLORBOMB => false,
    )

    """Toggleable pattern kinds with UI labels (creation only)."""
    function pattern_debug_entries()::Vector{Tuple{PatternKind, String}}
        return [
            (PATTERN_STRIPE_H, "Stripe H"),
            (PATTERN_STRIPE_V, "Stripe V"),
            (PATTERN_WRAPPED, "Wrapped"),
            (PATTERN_COLORBOMB, "Color Bomb"),
        ]
    end

    function is_pattern_creation_enabled(kind::PatternKind)::Bool
        kind == PATTERN_NONE && return true
        return get(_CREATION_ENABLED, kind, false)
    end

    function set_pattern_creation_enabled!(kind::PatternKind, enabled::Bool)
        kind == PATTERN_NONE && return
        _CREATION_ENABLED[kind] = enabled
    end

    function toggle_pattern_creation!(kind::PatternKind)::Bool
        kind == PATTERN_NONE && return true
        next = !is_pattern_creation_enabled(kind)
        set_pattern_creation_enabled!(kind, next)
        return next
    end

    function reset_pattern_creation_enabled!()
        for (kind, _) in pattern_debug_entries()
            _CREATION_ENABLED[kind] = false
        end
    end
end
