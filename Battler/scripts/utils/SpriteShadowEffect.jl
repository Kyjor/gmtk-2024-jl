"""
Reusable sprite shadow. Attach to any entity that has a sprite/image.

Modes:
  :silhouette — slightly offset low-opacity dark outline (DropShadow + soft Stroke)
  :ellipse    — simple ground blob under the sprite (ImmediateUI oval)
  :both       — silhouette + ellipse
"""
module SpriteShadowEffectModule
    using JulGame
    using JulGame.EffectsModule

    export attach!, detach!, refresh!, update!, is_attached, ensure!

    const DEFAULT_SHADOW_COLOR = (0, 0, 0, 255)
    const DEFAULT_OPACITY = 140
    const DEFAULT_DISTANCE = 6.0
    const DEFAULT_ANGLE = 115.0
    const DEFAULT_BLUR = 5
    const ELLIPSE_W_FRAC = 0.55
    const ELLIPSE_H_FRAC = 0.12
    const ELLIPSE_Y_FRAC = 0.92

    mutable struct ShadowAttachment
        entity::Any
        mode::Symbol
        distance::Float64
        angle::Float64
        blur_radius::Int
        color::NTuple{4, Int}
        opacity::Int
        ellipse_key::String
        last_image_path::String
    end

    const ATTACHMENTS = Dict{UInt, ShadowAttachment}()

    function _entity_id(entity)::UInt
        try
            return objectid(entity)
        catch
            return UInt(0)
        end
    end

    function _silhouette_effects(att::ShadowAttachment)
        # DropShadow only — StrokeEffect + useEffectTexture corrupts large character sprites.
        return Any[
            DropShadowEffect(
                distance = att.distance,
                angle = att.angle,
                blur_radius = att.blur_radius,
                color = att.color,
                opacity = att.opacity,
            ),
        ]
    end

    function _apply_silhouette!(att::ShadowAttachment)
        spr = att.entity === nothing ? nothing : att.entity.sprite
        (spr === nothing || spr == C_NULL) && return
        try
            JulGame.apply_effects!(spr, _silhouette_effects(att))
            if hasproperty(spr, :useEffectTexture)
                spr.useEffectTexture = true
            end
            att.last_image_path = string(something(spr.imagePath, ""))
        catch e
            @debug "SpriteShadowEffect silhouette: $e"
        end
    end

    function _clear_silhouette!(att::ShadowAttachment)
        spr = att.entity === nothing ? nothing : att.entity.sprite
        (spr === nothing || spr == C_NULL) && return
        try
            if hasproperty(spr, :useEffectTexture)
                spr.useEffectTexture = false
            end
        catch
        end
    end

    function _draw_ellipse!(att::ShadowAttachment)
        (att.mode === :silhouette) && return
        spr = att.entity === nothing ? nothing : att.entity.sprite
        (spr === nothing || spr == C_NULL) && return
        try
            pos = spr.lastRenderedScreenPosition
            size = spr.lastRenderedScreenSize
            (pos === nothing || size === nothing) && return
            base_w = max(Float64(size.x) * ELLIPSE_W_FRAC, 28.0)
            base_h = max(Float64(size.y) * ELLIPSE_H_FRAC, 12.0)
            cx = Float64(pos.x) + Float64(size.x) * 0.5
            cy = Float64(pos.y) + Float64(size.y) * ELLIPSE_Y_FRAC
            layer = max(Int(something(try spr.layer catch; 0 end, 0)) - 1, 0)
            # Soft oval blob: concentric capsules (borderRadius = half height → ellipse silhouette).
            for (i, (scale, alpha)) in enumerate(((1.35, 28), (1.1, 55), (0.85, 95)))
                w = base_w * scale
                h = base_h * scale
                JulGame.ImmediateUIModule.immediate_rect(
                    "$(att.ellipse_key)_$i";
                    position = Math.Vector2(cx - w * 0.5, cy - h * 0.5),
                    size = Math.Vector2(w, h),
                    color = (0, 0, 0, alpha),
                    borderRadius = max(round(Int, h * 0.5), 1),
                    layer = layer,
                )
            end
        catch e
            @debug "SpriteShadowEffect ellipse: $e"
        end
    end

    """
    Attach a reusable shadow to `entity` (must have `.sprite`).
    `mode` ∈ (:silhouette, :ellipse, :both)
    """
    function attach!(
        entity;
        mode::Symbol = :both,
        distance::Float64 = DEFAULT_DISTANCE,
        angle::Float64 = DEFAULT_ANGLE,
        blur_radius::Int = DEFAULT_BLUR,
        color::NTuple{4, Int} = DEFAULT_SHADOW_COLOR,
        opacity::Int = DEFAULT_OPACITY,
    )::Bool
        entity === nothing && return false
        spr = try entity.sprite catch; nothing end
        (spr === nothing || spr == C_NULL) && return false

        id = _entity_id(entity)
        id == 0 && return false
        key = "sprite_shadow_$(id)"
        att = ShadowAttachment(
            entity,
            mode,
            distance,
            angle,
            blur_radius,
            color,
            opacity,
            key,
            "",
        )
        ATTACHMENTS[id] = att
        if mode === :silhouette || mode === :both
            _apply_silhouette!(att)
        else
            # Ellipse-only: never bake effect textures onto the source sprite.
            _clear_silhouette!(att)
        end
        return true
    end

    function detach!(entity)
        id = _entity_id(entity)
        att = get(ATTACHMENTS, id, nothing)
        att === nothing && return
        _clear_silhouette!(att)
        try
            JulGame.ImmediateUIModule.remove_immediate_component(att.ellipse_key)
            for i in 1:3
                JulGame.ImmediateUIModule.remove_immediate_component("$(att.ellipse_key)_$i")
            end
        catch
        end
        delete!(ATTACHMENTS, id)
    end

    function is_attached(entity)::Bool
        return haskey(ATTACHMENTS, _entity_id(entity))
    end

    function ensure!(entity; kwargs...)::Bool
        id = _entity_id(entity)
        att = get(ATTACHMENTS, id, nothing)
        if att !== nothing
            wanted = get(kwargs, :mode, att.mode)
            if wanted != att.mode
                detach!(entity)
                return attach!(entity; kwargs...)
            end
            return true
        end
        return attach!(entity; kwargs...)
    end

    """Re-bake silhouette after `imagePath` / pose changes."""
    function refresh!(entity)
        att = get(ATTACHMENTS, _entity_id(entity), nothing)
        att === nothing && return
        if att.mode === :silhouette || att.mode === :both
            _apply_silhouette!(att)
        end
    end

    function update!(_deltaTime = 0.0)
        for att in values(ATTACHMENTS)
            spr = try att.entity.sprite catch; nothing end
            if spr !== nothing && spr != C_NULL
                path = string(something(spr.imagePath, ""))
                if (att.mode === :silhouette || att.mode === :both) && path != att.last_image_path
                    _apply_silhouette!(att)
                end
            end
            _draw_ellipse!(att)
        end
    end
end
