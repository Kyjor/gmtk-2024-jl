module NineSliceUIModule
    using JulGame

    """
    Nine-slice source art description, in source pixels.
    - `slice`: (l, t, r, b) edges drawn unstretched; must fully contain the corners.
    - `inner`: (l, t, r, b) visual inner edge of the frame; tiled content sits inside it.
    - `fill`: opaque fill art drawn under `path` (the frame) and tinted separately; "" when `path` is the whole panel.
    """
    struct PanelSpec
        path::String
        fill::String
        src_w::Int
        src_h::Int
        slice::NTuple{4, Int}
        inner::NTuple{4, Int}
    end

    const PANEL_FLAT = PanelSpec("ui-panelframe", "ui-panelfill", 548, 161, (16, 16, 16, 16), (8, 8, 8, 8))
    const PANEL_GRADIENT = PanelSpec("ui-panelframe", "ui-panelfillgradient", 548, 161, (16, 16, 16, 16), (8, 8, 8, 8))
    # Visual inner edge of the frame (l, t, r, b). Tucked 2px into the charcoal
    # fade so center fill / tiles cover the dark crop inside the 40px slice.
    const PANEL_NEWGAMEBOX = PanelSpec("ui-newgamebox", "", 587, 190, (40, 40, 40, 40), (28, 23, 32, 27))
    const DEFAULT_PANEL = PANEL_FLAT

    # Panel art is white (shape in alpha), so `color` tints it to any RGB. Presets:
    const PANEL_COLORS = (
        lavender = (214, 186, 255, 255),
        purple = (150, 90, 230, 255),
        red = (230, 60, 60, 255),
        orange = (245, 150, 60, 255),
        gold = (255, 210, 70, 255),
        green = (90, 210, 110, 255),
        teal = (60, 200, 190, 255),
        blue = (80, 150, 255, 255),
        pink = (255, 120, 200, 255),
        gray = (140, 140, 150, 255),
        white = (255, 255, 255, 255),
        bone = (210, 200, 180, 255),
        charcoal = (26, 24, 38, 255),
    )
    const DEFAULT_PANEL_COLOR = PANEL_COLORS.bone
    const DEFAULT_FILL_COLOR = PANEL_COLORS.charcoal
    const DEFAULT_FILL_ALPHA = 191

    # Single-image panel art, for widgets that take one image (e.g. immediate_button).
    const PANEL_PATH = "ui-panel"
    const PANEL_HOVER_PATH = "ui-panelgradient75"
    const BUTTON_UP_PATH = "ui-newgamebox"
    const BUTTON_DOWN_PATH = "ui-newgameboxhovered"

    """`JulGame.ImmediateUIModule.immediate_button` with the game's default button art."""
    function immediate_button(id::String, click; downArt::String = BUTTON_DOWN_PATH, kwargs...)
        g = JulGame.UserGlobals["Module"]
        return JulGame.ImmediateUIModule.immediate_button(id, click;
            buttonUpPath = g.get_asset_path(BUTTON_UP_PATH),
            buttonDownPath = g.get_asset_path(downArt),
            kwargs...,
        )
    end
    const PANEL_SLICE = maximum(DEFAULT_PANEL.slice)
    const PANEL_INNER = DEFAULT_PANEL.inner

    function dest_slices(dw::Int, dh::Int, sl::Int, st::Int, sr::Int, sb::Int)
        l = min(sl, dw ÷ 2)
        r = min(sr, dw - l)
        t = min(st, dh ÷ 2)
        b = min(sb, dh - t)
        return l, t, r, b, dw - l - r, dh - t - b
    end

    function draw_nine_slice!(id::String, art::String, host, size, tint::NTuple{4, Int}, layer::Int, spec::PanelSpec)
        path = JulGame.UserGlobals["Module"].get_asset_path(art)
        src_w, src_h = spec.src_w, spec.src_h
        sl, st, sr, sb = spec.slice
        dw = Int(size.x)
        dh = Int(size.y)
        l, t, r, b, cw, ch = dest_slices(dw, dh, sl, st, sr, sb)
        patches = (
            (:tl, 0, 0, sl, st),
            (:t, sl, 0, src_w - sl - sr, st),
            (:tr, src_w - sr, 0, sr, st),
            (:l, 0, st, sl, src_h - st - sb),
            (:c, sl, st, src_w - sl - sr, src_h - st - sb),
            (:r, src_w - sr, st, sr, src_h - st - sb),
            (:bl, 0, src_h - sb, sl, sb),
            (:b, sl, src_h - sb, src_w - sl - sr, sb),
            (:br, src_w - sr, src_h - sb, sr, sb),
        )
        dest = (
            (0, 0, l, t),
            (l, 0, cw, t),
            (l + cw, 0, r, t),
            (0, t, l, ch),
            (l, t, cw, ch),
            (l + cw, t, r, ch),
            (0, t + ch, l, b),
            (l, t + ch, cw, b),
            (l + cw, t + ch, r, b),
        )
        for i in 1:9
            name, sx, sy, sw, sh = patches[i]
            dx, dy, dw_i, dh_i = dest[i]
            (dw_i <= 0 || dh_i <= 0 || sw <= 0 || sh <= 0) && continue
            img = JulGame.ImmediateUIModule.immediate_image(
                "$(id)_$(name)",
                path;
                parent = host,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(dx, dy),
                size = Math.Vector2(dw_i, dh_i),
                crop = Math.Vector4(sx, sy, sw, sh),
                color = tint,
                layer = layer,
            )
            # Desktop UIImage renders at `originalSize`, which immediate_image never updates on resize.
            img !== nothing && img.originalSize != img.size && (img.originalSize = img.size)
        end
    end

    """
    `color` tints the fill and `fill_alpha` sets its opacity; `border_color` tints the frame (defaults to `color`).
    Without `color`, the fill is DEFAULT_FILL_COLOR and the frame DEFAULT_PANEL_COLOR.
    With a separate fill, the frame draws at `layer + 1` (same-layer draw order is not guaranteed).
    """
    function immediate_panel(id::String;
        size,
        anchor::Symbol = :none,
        anchorOffset = Math.Vector2(0, 0),
        position = Math.Vector2(0, 0),
        layer::Int = 0,
        color::Union{Nothing, NTuple{4, Int}} = nothing,
        border_color::Union{Nothing, NTuple{4, Int}} = nothing,
        fill_alpha::Int = DEFAULT_FILL_ALPHA,
        parent = nothing,
        spec::PanelSpec = DEFAULT_PANEL,
    )
        border = something(border_color, color, DEFAULT_PANEL_COLOR)
        color = something(color, DEFAULT_FILL_COLOR)
        host = JulGame.ImmediateUIModule.immediate_rect(
            id;
            size = size,
            anchor = anchor,
            anchorOffset = anchorOffset,
            position = position,
            layer = layer,
            color = (0, 0, 0, 0),
            parent = parent,
        )
        frame_layer = layer
        if !isempty(spec.fill)
            fill = (color[1], color[2], color[3], round(Int, color[4] * fill_alpha / 255))
            draw_nine_slice!("$(id)_fill", spec.fill, host, size, fill, layer, spec)
            frame_layer = layer + 1
        end
        draw_nine_slice!("$(id)_frame", spec.path, host, size, border, frame_layer, spec)
        return host
    end

    export immediate_panel, immediate_button, BUTTON_UP_PATH, BUTTON_DOWN_PATH, PanelSpec, PANEL_GRADIENT, PANEL_FLAT, PANEL_NEWGAMEBOX, DEFAULT_PANEL,
        PANEL_PATH, PANEL_HOVER_PATH, PANEL_SLICE, PANEL_INNER, PANEL_COLORS, DEFAULT_PANEL_COLOR, DEFAULT_FILL_COLOR, DEFAULT_FILL_ALPHA
end
