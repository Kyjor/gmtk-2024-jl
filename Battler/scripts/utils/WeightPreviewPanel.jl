module WeightPreviewPanelModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule
    include("Easings.jl")

    # Presentation-only list: caller supplies rows (or builds them via rows_for_change).
    # This module owns layout, colors, and show/hide animation.

    struct WeightChangeRow
        key::String
        icon_path::String
        old_share::Float64
        new_share::Float64
        is_new::Bool
    end

    mutable struct WeightPreviewPanel
        id::String
        visible::Bool
        progress::Float64
        rows::Vector{WeightChangeRow}

        WeightPreviewPanel(id::String = "weight_preview") = new(id, false, 0.0, WeightChangeRow[])
    end

    const SHOW_DURATION = 0.2
    const HIDE_DURATION = 0.12
    const PAD = 16
    const ICON_SIZE = 36
    const ROW_H = 44
    const COL_GAP = 12
    const TEXT_FS = 22
    const MIN_WIDTH = 240
    const MAX_WIDTH = 340
    const SLIDE_PX = 28
    const LAYER = 80

    const NineSlice = parentmodule(parentmodule(@__MODULE__)).NineSliceUIModule
    const COLOR_BG = NineSlice.DEFAULT_FILL_COLOR
    const BG_ALPHA = 242
    const COLOR_BORDER = (218, 178, 90, 210)
    const COLOR_TEXT = (236, 231, 216, 255)
    const COLOR_UP = (92, 214, 112, 255)
    const COLOR_DOWN = (230, 78, 86, 255)
    const COLOR_DIVIDER = (218, 178, 90, 90)

    function percent_text(share::Float64)::String
        return string(round(share * 100.0, digits = 2), "%")
    end

    function icon_path_for_piece(piece)::String
        (piece === nothing || !hasproperty(piece, :key)) && return ""
        parts = split(lowercase(string(piece.key)), "_")
        length(parts) < 2 && return ""
        return JulGame.UserGlobals["Module"].get_asset_path(String(parts[1]), String(parts[2]))
    end

    function _piece_key(piece)::String
        (piece === nothing || !hasproperty(piece, :key)) && return ""
        return uppercase(strip(string(piece.key)))
    end

    function _shares(rarities::Vector{Float64})::Vector{Float64}
        total = sum(rarities)
        total <= 0.0 && return zeros(Float64, length(rarities))
        return [r / total for r in rarities]
    end

    """
    Project every owned piece's board share after `target` is set to `new_rarity`.
    When `is_new`, `target` is appended (old share 0) and listed last; a gem follows the
    one-gem limit (replaces the owned gem, or changes nothing when the owned one is better).
    """
    function rows_for_change(owned, target, new_rarity; is_new::Bool = false)::Vector{WeightChangeRow}
        pieces = [p for p in owned if p !== nothing]
        old_r = Float64[Float64(p.weight) for p in pieces]
        old_s = _shares(old_r)
        rows = WeightChangeRow[]

        if is_new
            new_r = vcat(old_r, Float64(new_rarity))
            slot = JulGame.UserGlobals["Module"].UserModule.gem_limit_slot(pieces, target)
            if slot === :ignored
                new_r[end] = 0.0
            elseif slot isa Integer
                new_r[slot] = 0.0
            end
            new_s = _shares(new_r)
            for (i, piece) in enumerate(pieces)
                push!(rows, WeightChangeRow(_piece_key(piece), icon_path_for_piece(piece), old_s[i], new_s[i], false))
            end
            target !== nothing && push!(
                rows,
                WeightChangeRow(_piece_key(target), icon_path_for_piece(target), 0.0, new_s[end], true),
            )
            return rows
        end

        new_r = copy(old_r)
        want = _piece_key(target)
        for (i, piece) in enumerate(pieces)
            _piece_key(piece) == want && (new_r[i] = Float64(new_rarity))
        end
        new_s = _shares(new_r)
        for (i, piece) in enumerate(pieces)
            push!(rows, WeightChangeRow(_piece_key(piece), icon_path_for_piece(piece), old_s[i], new_s[i], false))
        end
        return rows
    end

    function show!(panel::WeightPreviewPanel, rows::Vector{WeightChangeRow})
        panel.rows = rows
        panel.visible = !isempty(rows)
    end

    function hide!(panel::WeightPreviewPanel)
        panel.visible = false
    end

    function tick!(panel::WeightPreviewPanel, deltaTime)
        target = panel.visible ? 1.0 : 0.0
        panel.progress == target && return
        duration = panel.visible ? SHOW_DURATION : HIDE_DURATION
        step = Float64(deltaTime) / duration
        panel.progress = clamp(panel.progress + (panel.visible ? step : -step), 0.0, 1.0)
    end

    _text_w(s::String, fontSize::Int)::Int = round(Int, length(s) * fontSize * 0.56)

    _scaled(color::NTuple{4, Int}, alpha::Float64)::NTuple{4, Int} =
        (color[1], color[2], color[3], round(Int, color[4] * alpha))

    function _new_color(old_share::Float64, new_share::Float64)::NTuple{4, Int}
        new_share > old_share + 0.0001 && return COLOR_UP
        new_share < old_share - 0.0001 && return COLOR_DOWN
        return COLOR_TEXT
    end

    """
    Draw the panel with its right edge at `right_x`, vertically centered on `center_y`.
    Call every frame after `tick!`.
    """
    function draw!(panel::WeightPreviewPanel; right_x::Float64, center_y::Float64, alpha::Float64 = 1.0)
        (panel.progress <= 0.0 || isempty(panel.rows)) && return

        slide = panel.visible ? ease_out_back(panel.progress) : ease_out_cubic(panel.progress)
        fade = clamp(panel.progress * 1.25, 0.0, 1.0) * clamp(alpha, 0.0, 1.0)
        fade <= 0.01 && return

        change_w = 0
        for row in panel.rows
            change_w = max(change_w, _text_w(string(percent_text(row.old_share), " -> ", percent_text(row.new_share)), TEXT_FS))
        end
        card_w = clamp(PAD + ICON_SIZE + COL_GAP + change_w + PAD, MIN_WIDTH, MAX_WIDTH)
        card_h = PAD + length(panel.rows) * ROW_H + PAD

        window = JulGame.WindowManagerModule.get_logical_size()
        card_x = round(Int, right_x - card_w - (1.0 - slide) * SLIDE_PX)
        card_y = round(Int, clamp(center_y - card_h / 2.0, 16.0, max(16.0, Float64(window.y) - card_h - 16.0)))

        # Fill at LAYER - 1, frame at LAYER.
        NineSlice.immediate_panel(
            "$(panel.id)_bg";
            position = Math.Vector2(card_x, card_y),
            size = Math.Vector2(card_w, card_h),
            color = _scaled(COLOR_BG, fade),
            border_color = _scaled(COLOR_BORDER, fade),
            fill_alpha = BG_ALPHA,
            layer = LAYER - 1,
        )

        for (i, row) in enumerate(panel.rows)
            row_y = card_y + PAD + (i - 1) * ROW_H
            if row.is_new && i > 1
                JulGame.ImmediateUIModule.immediate_rect(
                    "$(panel.id)_div";
                    position = Math.Vector2(card_x + PAD, row_y - 6),
                    size = Math.Vector2(card_w - 2 * PAD, 1),
                    color = _scaled(COLOR_DIVIDER, fade),
                    layer = LAYER + 1,
                )
            end

            if row.icon_path != ""
                JulGame.ImmediateUIModule.immediate_image(
                    "$(panel.id)_icon_$(i)",
                    row.icon_path;
                    position = Math.Vector2(card_x + PAD, row_y + (ROW_H - ICON_SIZE) ÷ 2),
                    size = Math.Vector2(ICON_SIZE, ICON_SIZE),
                    color = (255, 255, 255, round(Int, 255 * fade)),
                    layer = LAYER + 2,
                )
            end

            old_label = percent_text(row.old_share)
            arrow = " -> "
            new_label = percent_text(row.new_share)
            text_x = card_x + PAD + ICON_SIZE + COL_GAP
            text_y = row_y + (ROW_H - TEXT_FS) ÷ 2

            DisplayTextModule.display_text(
                "$(panel.id)_old_$(i)",
                string(old_label, arrow);
                position = Math.Vector2(text_x, text_y),
                fontSize = TEXT_FS,
                color = _scaled(COLOR_TEXT, fade),
                layer = LAYER + 2,
            )
            DisplayTextModule.display_text(
                "$(panel.id)_new_$(i)",
                new_label;
                position = Math.Vector2(text_x + _text_w(string(old_label, arrow), TEXT_FS), text_y),
                fontSize = TEXT_FS,
                color = _scaled(_new_color(row.old_share, row.new_share), fade),
                layer = LAYER + 2,
            )
        end
    end

    """Place the panel next to a sprite: to its right if it fits, otherwise to its left."""
    function draw_beside_sprite!(panel::WeightPreviewPanel, sprite; gutter::Float64 = 24.0, alpha::Float64 = 1.0)
        window = JulGame.WindowManagerModule.get_logical_size()
        center_y = Float64(window.y) / 2.0
        right_x = Float64(window.x) - 16.0
        if sprite !== nothing
            try
                pos = sprite.lastRenderedScreenPosition
                sz = sprite.lastRenderedScreenSize
                if pos !== nothing && sz !== nothing
                    center_y = Float64(pos.y) + Float64(sz.y) / 2.0
                    slot_right = Float64(pos.x) + Float64(sz.x)
                    slot_left = Float64(pos.x)
                    if slot_right + gutter + MAX_WIDTH < Float64(window.x) - 16.0
                        right_x = slot_right + gutter + MAX_WIDTH
                    else
                        right_x = slot_left - gutter
                    end
                end
            catch
            end
        end
        draw!(panel; right_x = right_x, center_y = center_y, alpha = alpha)
    end
end
