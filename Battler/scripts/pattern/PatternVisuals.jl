module PatternVisualsModule
    using JulGame
    using ..PatternKindsModule
    export apply_pattern_visual!, clear_pattern_visual!, pattern_tint, pattern_overlay_label

    function pattern_tint(kind::PatternKind)::NTuple{4, Int}
        kind == PATTERN_STRIPE_H && return (255, 230, 120, 255)
        kind == PATTERN_STRIPE_V && return (120, 220, 255, 255)
        kind == PATTERN_WRAPPED && return (255, 160, 90, 255)
        kind == PATTERN_COLORBOMB && return (230, 140, 255, 255)
        return (255, 255, 255, 255)
    end

    function pattern_overlay_label(kind::PatternKind)::String
        kind == PATTERN_STRIPE_H && return "═"
        kind == PATTERN_STRIPE_V && return "║"
        kind == PATTERN_WRAPPED && return "▣"
        kind == PATTERN_COLORBOMB && return "✦"
        return ""
    end

    """Tint the piece sprite as a placeholder overlay for the pattern kind."""
    function apply_pattern_visual!(entity, kind::PatternKind)
        entity === nothing && return
        try
            if entity.sprite !== nothing
                entity.sprite.color = pattern_tint(kind)
            end
        catch e
            @debug "apply_pattern_visual!: $e"
        end
    end

    function clear_pattern_visual!(entity)
        entity === nothing && return
        try
            if entity.sprite !== nothing
                entity.sprite.color = (255, 255, 255, 255)
            end
        catch e
            @debug "clear_pattern_visual!: $e"
        end
    end
end
