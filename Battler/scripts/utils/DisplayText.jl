module DisplayTextModule
    using JulGame
    using JulGame.FX.ImageFXModule  # Add import for ImageFXModule
    using JulGame.EffectsModule

    include("Constants.jl")

    function display_text(
        key::String,
        text::String;
        fontPath::String = BATTLE_NUMBER_FONT,
        fontSize::Any = 24,
        color::Any = (255, 255, 255, 255),
        parent::Any = nothing,
        anchor::Any = :none,
        anchorOffset::Any = Math.Vector2(0, 0),
        position::Any = Math.Vector2(0, 0),
        layer::Any = 1,
        isActive::Bool = true,
        rotation::Real = 0.0,
        lifetime::Any = nothing,
        applyEffects::Union{Nothing, Bool} = nothing,
        kwargs...
    )
        text = lifetime === nothing ?
            JulGame.ImmediateUIModule.immediate_text(
                key,
                text;
                fontPath = fontPath,
                fontSize = fontSize,
                color = color,
                parent = parent,
                position = position,
                anchor = anchor,
                anchorOffset = anchorOffset,
                layer = layer,
                isActive = isActive,
                kwargs...
            ) :
            JulGame.ImmediateUIModule.immediate_text(
                key,
                text;
                fontPath = fontPath,
                fontSize = fontSize,
                color = color,
                parent = parent,
                position = position,
                anchor = anchor,
                anchorOffset = anchorOffset,
                layer = layer,
                isActive = isActive,
                lifetime = lifetime,
                kwargs...
            )

        should_apply = applyEffects === nothing ? (fontPath == BATTLE_NUMBER_FONT) : applyEffects
        should_apply && apply_battle_number_text_effects!(text)
        rotation != 0 && text !== nothing && (text.rotation = Float64(rotation))

        return text
    end

    export display_text
end
