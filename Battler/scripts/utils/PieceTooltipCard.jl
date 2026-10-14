module PieceTooltipCardModule
    using JulGame
    include("Easings.jl")
    include("DisplayText.jl")

    # Presentation-only card: caller supplies content (name, weight, description, icon, tier lines),
    # this module owns layout, styling and show/hide animation.

    struct CardTier
        label::String   # e.g. "Match 3"
        text::String    # e.g. "Deal 3 damage, Gain 2 shield"
    end

    struct CardContent
        key::String
        name::String
        weightText::String
        description::String
        iconPath::String
        tiers::Vector{CardTier}
    end

    mutable struct PieceTooltipCard
        visible::Bool
        progress::Float64  # 0 = fully hidden, 1 = fully shown
        content::Union{Nothing, CardContent}
        flashTime::Float64

        PieceTooltipCard() = new(false, 0.0, nothing, 0.0)
    end

    const SHOW_DURATION = 0.28
    const HIDE_DURATION = 0.16
    # Two-state blink (not a smooth pulse) so the text only re-renders on each toggle.
    const FLASH_PERIOD  = 0.6
    const FLASH_DIM     = 0.6
    const CURRENT_SUFFIX = " (current)"

    # Layout (80% of 2x original)
    const PAD          = 26
    const ICON_BOX     = 83
    const ICON_SIZE    = 67
    const ROW_H        = 38
    const TIER_LINE_H  = 28
    const LABEL_COL_W  = 138
    const LABEL_GAP    = 16
    const MIN_WIDTH    = 480
    const MAX_WIDTH    = 768
    const EDGE_MARGIN  = 22
    const HEADER_GAP   = 19
    const DIVIDER_GAP  = 18
    const DESC_LINE_H  = 26
    const DESC_PAD     = 13

    # Typography (80% of 2x original)
    const NAME_FS   = 32
    const WEIGHT_FS = 19
    const DESC_FS   = 19
    const TIER_FS   = 22

    const Scripts = parentmodule(parentmodule(@__MODULE__))

    # Palette: dark charcoal panel with warm gold accents
    const COLOR_BG      = Scripts.NineSliceUIModule.DEFAULT_FILL_COLOR
    const BG_ALPHA      = 242
    const COLOR_BORDER  = (218, 178, 90, 210)
    const COLOR_ICON_BG = (255, 255, 255, 18)
    const COLOR_DIVIDER = (218, 178, 90, 90)
    const COLOR_NAME    = (245, 240, 228, 255)
    const COLOR_WEIGHT  = (168, 162, 150, 255)
    const COLOR_DESC    = (232, 230, 224, 255)
    const COLOR_LABEL   = (218, 178, 90, 255)
    const COLOR_EFFECT  = (232, 230, 224, 255)

    """Turn one preview intent line into player-facing text."""
    function effect_text(value::Integer, label::String)::String
        label == "DMG"            && return "Deal $value damage"
        label == "DMG (vuln)"     && return "Deal $value damage (vulnerable)"
        label == "DMG (all)"      && return "Deal $value damage to all enemies"
        label == "DMG (all, vuln)" && return "Deal $value damage to all enemies (vulnerable)"
        label == "SHIELD"         && return "Gain $value shield"
        label == "HEAL"           && return "Heal $value HP"
        label == "HEAL (blocked)" && return "Healing blocked"
        label == "BURN"           && return "Apply $value Burn"
        label == "FREEZE"         && return "Apply $value Freeze"
        label == "VULN"           && return "Apply $value Vulnerable"
        label == "VULN (all)"     && return "Apply $value Vulnerable to all enemies"
        label == "POISON"         && return "Apply $value Poison"
        label == "SHOCK"          && return "Apply $value Shock"
        label == "DODGE %"        && return "$value% Dodge chance"
        label == "REFLECT %"      && return "$value% Reflect chance"
        label == "RECOIL"         && return "Take $value recoil damage"
        label == "DOLLARS"        && return "Gain \$$value"
        startswith(label, "ROLL ") && return "Roll $(label[6:end]) damage"
        label == "COUNT"          && return "x$value"
        return "$label: $value"
    end

    tier_text(lines)::String = join([effect_text(l.value, l.value_label) for l in lines], ", ")

    function show!(card::PieceTooltipCard, content::CardContent)
        if card.visible && card.content !== nothing && card.content.key != content.key
            # Small re-pop when sliding between pieces so the swap reads as a change.
            card.progress = min(card.progress, 0.85)
        end
        card.content = content
        card.visible = true
    end

    function hide!(card::PieceTooltipCard)
        card.visible = false
    end

    _text_w(s::String, fontSize::Int)::Int = round(Int, length(s) * fontSize * 0.56)

    _scaled(color::NTuple{4, Int}, alpha::Float64)::NTuple{4, Int} =
        (color[1], color[2], color[3], round(Int, color[4] * alpha))

    function _wrap_lines(text::String, fontSize::Int, maxW::Int)::Vector{String}
        isempty(text) && return String[]
        lines = String[]
        for paragraph in split(text, '\n')
            words = split(paragraph)
            if isempty(words)
                push!(lines, "")
                continue
            end
            current = ""
            for word in words
                w = String(word)
                candidate = current == "" ? w : current * " " * w
                if current != "" && _text_w(candidate, fontSize) > maxW
                    push!(lines, current)
                    current = w
                else
                    current = candidate
                end
            end
            current != "" && push!(lines, current)
        end
        return lines
    end

    function _draw_text(key::String, text::String, x, y, fontSize::Int, color, layer::Int)
        DisplayTextModule.display_text(
            key,
            text;
            position = Math.Vector2(x, y),
            fontSize = fontSize,
            color = color,
            layer = layer,
        )
    end

    function _draw_divider(key::String, cardX, cardW, y, alpha)
        JulGame.ImmediateUIModule.immediate_rect(
            key;
            position = Math.Vector2(cardX + PAD, y),
            size = Math.Vector2(cardW - 2 * PAD, 2),
            color = _scaled(COLOR_DIVIDER, alpha),
            layer = 901,
        )
    end

    """
    Advance the show/hide animation and render the card. Call every frame.
    `max_right` (screen x, e.g. the board's left edge) caps the card width so it never overlaps it.
    `current` is the tier of the move being aimed: the row with the same label flashes with
    CURRENT_SUFFIX, or it is appended as an extra row when past the listed tiers.
    """
    function draw!(card::PieceTooltipCard, deltaTime; max_right::Union{Nothing, Real} = nothing,
        current::Union{Nothing, CardTier} = nothing)
        target = card.visible ? 1.0 : 0.0
        if card.progress != target
            duration = card.visible ? SHOW_DURATION : HIDE_DURATION
            step = Float64(deltaTime) / duration
            card.progress = clamp(card.progress + (card.visible ? step : -step), 0.0, 1.0)
        end
        (card.progress <= 0.0 || card.content === nothing) && return

        content = card.content
        # Overshooting back-ease on entry gives the card a springy pop; plain ease on exit.
        slide = card.visible ? ease_out_back(card.progress) : ease_out_cubic(card.progress)
        alpha = clamp(card.progress * 1.25, 0.0, 1.0)

        tiers = content.tiers
        currentIdx = 0
        if current !== nothing
            currentIdx = something(findfirst(t -> t.label == current.label, tiers), 0)
            if currentIdx == 0
                tiers = [tiers; current]
                currentIdx = length(tiers)
            end
            card.flashTime += Float64(deltaTime)
        else
            card.flashTime = 0.0
        end
        labels = [i == currentIdx ? tier.label * CURRENT_SUFFIX : tier.label for (i, tier) in enumerate(tiers)]
        flashAlpha = mod(card.flashTime, FLASH_PERIOD) < FLASH_PERIOD / 2 ? alpha : alpha * FLASH_DIM
        labelColW = maximum(l -> _text_w(l, TIER_FS) + LABEL_GAP, labels; init = LABEL_COL_W)

        headerTextX = PAD + ICON_BOX + HEADER_GAP
        headerW = headerTextX + max(_text_w(content.name, NAME_FS), _text_w(content.weightText, WEIGHT_FS)) + PAD
        cardW = headerW
        for tier in tiers
            cardW = max(cardW, PAD + labelColW + _text_w(tier.text, TIER_FS) + PAD)
        end
        cardW = clamp(cardW, MIN_WIDTH, MAX_WIDTH)
        cardX = EDGE_MARGIN
        if max_right !== nothing
            cardW = min(cardW, floor(Int, max_right) - EDGE_MARGIN - cardX)
        end

        textMaxW = cardW - 2 * PAD
        tierLines = [_wrap_lines(tier.text, TIER_FS, textMaxW - labelColW) for tier in tiers]
        tierHeights = [ROW_H + (max(1, length(lines)) - 1) * TIER_LINE_H for lines in tierLines]
        descLines = _wrap_lines(content.description, DESC_FS, textMaxW)
        hasDesc = !isempty(descLines)

        headerBottom = PAD + ICON_BOX
        div1Rel = headerBottom + DIVIDER_GAP
        if hasDesc
            descYRel = div1Rel + DIVIDER_GAP
            descH = length(descLines) * DESC_LINE_H
            div2Rel = descYRel + descH + DESC_PAD
            rowsYRel = div2Rel + DIVIDER_GAP
        else
            rowsYRel = div1Rel + DIVIDER_GAP
        end
        cardH = rowsYRel + sum(tierHeights; init = 0) + PAD

        window = JulGame.WindowManagerModule.get_logical_size()
        shownY = window.y - cardH - EDGE_MARGIN
        cardY = round(Int, shownY + (1.0 - slide) * (cardH + EDGE_MARGIN + 10))

        # Fill at 899, frame at 900.
        Scripts.NineSliceUIModule.immediate_panel(
            "piece_card_bg";
            position = Math.Vector2(cardX, cardY),
            size = Math.Vector2(cardW, cardH),
            color = _scaled(COLOR_BG, alpha),
            border_color = _scaled(COLOR_BORDER, alpha),
            fill_alpha = BG_ALPHA,
            layer = 899,
        )

        # Fill at 901, frame at 902.
        Scripts.NineSliceUIModule.immediate_panel(
            "piece_card_icon_bg";
            position = Math.Vector2(cardX + PAD, cardY + PAD),
            size = Math.Vector2(ICON_BOX, ICON_BOX),
            color = _scaled(COLOR_ICON_BG, alpha),
            border_color = _scaled(COLOR_DIVIDER, alpha),
            fill_alpha = 255,
            layer = 901,
        )
        iconInset = (ICON_BOX - ICON_SIZE) ÷ 2
        JulGame.ImmediateUIModule.immediate_image(
            "piece_card_icon",
            content.iconPath;
            position = Math.Vector2(cardX + PAD + iconInset, cardY + PAD + iconInset),
            size = Math.Vector2(ICON_SIZE, ICON_SIZE),
            color = (255, 255, 255, round(Int, 255 * alpha)),
            layer = 903,
        )

        _draw_text(
            "piece_card_name",
            content.name,
            cardX + headerTextX,
            cardY + PAD + 6,
            NAME_FS,
            _scaled(COLOR_NAME, alpha),
            902,
        )
        if content.weightText != ""
            _draw_text(
                "piece_card_weight",
                content.weightText,
                cardX + headerTextX,
                cardY + PAD + NAME_FS + 19,
                WEIGHT_FS,
                _scaled(COLOR_WEIGHT, alpha),
                902,
            )
        end

        _draw_divider("piece_card_divider", cardX, cardW, cardY + div1Rel, alpha)

        if hasDesc
            for (i, line) in enumerate(descLines)
                _draw_text(
                    "piece_card_desc_$i",
                    line,
                    cardX + PAD,
                    cardY + descYRel + (i - 1) * DESC_LINE_H,
                    DESC_FS,
                    _scaled(COLOR_DESC, alpha),
                    902,
                )
            end
            _draw_divider("piece_card_divider_2", cardX, cardW, cardY + div2Rel, alpha)
        end

        rowY = cardY + rowsYRel
        for i in eachindex(tiers)
            rowAlpha = i == currentIdx ? flashAlpha : alpha
            _draw_text(
                "piece_card_tier_label_$i",
                labels[i],
                cardX + PAD,
                rowY,
                TIER_FS,
                _scaled(COLOR_LABEL, rowAlpha),
                902,
            )
            for (li, line) in enumerate(tierLines[i])
                _draw_text(
                    "piece_card_tier_text_$(i)_$li",
                    line,
                    cardX + PAD + labelColW,
                    rowY + (li - 1) * TIER_LINE_H,
                    TIER_FS,
                    _scaled(COLOR_EFFECT, rowAlpha),
                    902,
                )
            end
            rowY += tierHeights[i]
        end

        blob = content.description
        for tier in tiers
            blob *= " " * tier.text
        end
        Scripts.KeywordGlossaryModule.draw_stacked!(
            "piece_kw",
            blob,
            cardX,
            cardY,
            cardW,
            cardH;
            alpha = alpha,
            layer = 910,
        )
    end
end
