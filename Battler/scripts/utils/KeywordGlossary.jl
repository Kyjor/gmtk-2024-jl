module KeywordGlossaryModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule

    # Keys are the quoted word, lowercased. Add a row when a new "term" shows up.
    # `{Term}` counts too (Japanese descriptions). Unknown quotes draw nothing.
    const KEYWORDS = Dict{String, Tuple{String, String}}(
        "burn" => ("Burn", "Lose 1 HP at the end of the turn. Each stack lasts one turn."),
        "freeze" => ("Freeze", "Enemies skip their turn. On you, you lose a move."),
        "poison" => ("Poison", "Attacks deal less damage, reduced by the number of stacks."),
        "vulnerable" => ("Vulnerable", "Attacks against this combatant deal 1 extra damage per stack."),
        "shock" => ("Shock", "At the end of the turn, deal damage equal to the stacks to other enemies."),
        "status" => ("Status", "A temporary combat effect, such as Burn, Freeze, Poison, Vulnerable, or Shock."),
    )

    const PAD = 16
    const TITLE_FS = 22
    const BODY_FS = 18
    const BODY_LINE_H = 24
    const BLOCK_GAP = 14
    const PANEL_W = 340
    const GAP = 12
    const NineSlice = parentmodule(@__MODULE__).NineSliceUIModule
    const COLOR_BG = NineSlice.DEFAULT_FILL_COLOR
    const BG_ALPHA = 242
    const COLOR_BORDER = (168, 140, 210, 220)
    const COLOR_TITLE = (214, 186, 255, 255)
    const COLOR_BODY = (232, 230, 224, 255)

    struct KeywordDef
        title::String
        body::String
    end

    function definitions_in(text::AbstractString)::Vector{KeywordDef}
        found = KeywordDef[]
        seen = Set{String}()
        for m in eachmatch(r"(?:\"([^\"]+)\"|\{([^}]+)\})", String(text))
            raw = m.captures[1] !== nothing ? m.captures[1] : m.captures[2]
            key = lowercase(strip(raw))
            def = get(KEYWORDS, key, nothing)
            def === nothing && continue
            key in seen && continue
            push!(seen, key)
            push!(found, KeywordDef(def[1], def[2]))
        end
        return found
    end

    _text_w(s::String, fontSize::Int)::Int = round(Int, length(s) * fontSize * 0.56)

    function _wrap(text::String, fontSize::Int, maxW::Int)::Vector{String}
        lines = String[]
        current = ""
        for word in split(text)
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
        return lines
    end

    function _scaled(color::NTuple{4, Int}, alpha::Float64)::NTuple{4, Int}
        return (color[1], color[2], color[3], round(Int, color[4] * alpha))
    end

    function _layout(defs::Vector{KeywordDef}, panel_w::Int)
        text_w = panel_w - 2 * PAD
        blocks = Tuple{KeywordDef, Vector{String}}[]
        panel_h = PAD
        for def in defs
            lines = _wrap(def.body, BODY_FS, text_w)
            isempty(lines) && push!(lines, "")
            push!(blocks, (def, lines))
            panel_h += TITLE_FS + 8 + length(lines) * BODY_LINE_H + BLOCK_GAP
        end
        panel_h += PAD - BLOCK_GAP
        return blocks, panel_h
    end

    """Draw known keyword definitions beside an existing tooltip. No-op when none match."""
    function draw_beside!(id::String, source::AbstractString, anchor_x, anchor_y, anchor_w, _anchor_h; alpha::Float64 = 1.0, layer::Int = 1002, avoid_x::Union{Nothing, Real} = nothing)
        alpha <= 0 && return
        defs = definitions_in(source)
        isempty(defs) && return

        blocks, panel_h = _layout(defs, PANEL_W)

        window = JulGame.WindowManagerModule.get_logical_size()
        right = anchor_x + anchor_w + GAP
        left = anchor_x - PANEL_W - GAP
        x = right
        if right + PANEL_W > window.x - 8 && left >= 8
            x = left
        elseif avoid_x !== nothing && right <= avoid_x <= right + PANEL_W && left >= 8
            x = left
        end
        x = clamp(x, 8, max(8, window.x - PANEL_W - 8))
        y = anchor_y
        if y + panel_h > window.y - 8
            y = window.y - panel_h - 8
        end
        y = max(8, y)

        _render(id, blocks, x, y, PANEL_W, panel_h, alpha, layer)
    end

    """Draw known keyword definitions below a tooltip (above when there is no room), matching its width."""
    function draw_stacked!(id::String, source::AbstractString, anchor_x, anchor_y, anchor_w, anchor_h; alpha::Float64 = 1.0, layer::Int = 1002)
        alpha <= 0 && return
        defs = definitions_in(source)
        isempty(defs) && return

        panel_w = round(Int, anchor_w)
        blocks, panel_h = _layout(defs, panel_w)

        window = JulGame.WindowManagerModule.get_logical_size()
        below = anchor_y + anchor_h + GAP
        y = below + panel_h <= window.y - 8 ? below : max(8, anchor_y - panel_h - GAP)

        _render(id, blocks, anchor_x, y, panel_w, panel_h, alpha, layer)
    end

    function _render(id::String, blocks, x, y, panel_w, panel_h, alpha::Float64, layer::Int)
        # Fill at `layer`, frame at `layer + 1`; text above both.
        NineSlice.immediate_panel(
            "$(id)_bg";
            position = Math.Vector2(x, y),
            size = Math.Vector2(panel_w, panel_h),
            color = _scaled(COLOR_BG, alpha),
            border_color = _scaled(COLOR_BORDER, alpha),
            fill_alpha = BG_ALPHA,
            layer = layer,
        )

        cursor = y + PAD
        for (i, (def, lines)) in enumerate(blocks)
            DisplayTextModule.display_text(
                "$(id)_title_$i",
                def.title;
                position = Math.Vector2(x + PAD, cursor),
                fontSize = TITLE_FS,
                color = _scaled(COLOR_TITLE, alpha),
                layer = layer + 2,
            )
            cursor += TITLE_FS + 8
            for (li, line) in enumerate(lines)
                DisplayTextModule.display_text(
                    "$(id)_body_$(i)_$li",
                    line;
                    position = Math.Vector2(x + PAD, cursor),
                    fontSize = BODY_FS,
                    color = _scaled(COLOR_BODY, alpha),
                    layer = layer + 2,
                )
                cursor += BODY_LINE_H
            end
            cursor += BLOCK_GAP
        end
    end

    export definitions_in, draw_beside!, draw_stacked!
end
