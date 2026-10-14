"""
Hover the player combatant → OuterGlow highlight + STS-style stats/status popup.
Glow is pre-baked (PotionTooltip pattern): useEffectTexture stays false until hover.
"""
module PlayerCombatantPopupModule
    using JulGame
    using JulGame.EffectsModule
    include("DisplayText.jl")
    using .DisplayTextModule
    include("Easings.jl")

    export ensure!, attach!, detach!, update!, draw!

    const PLAYER_ENTITY_ID = "95b3f5d9-a580-4a15-b745-9ecf1fc76620"
    const SHOW_DURATION = 0.22
    const HIDE_DURATION = 0.14
    const PAD = 22
    const MIN_W = 340
    const MAX_W = 520
    const TITLE_FS = 28
    const BODY_FS = 20
    const LINE_H = 28
    const EDGE = 18
    const COLOR_BG = (22, 20, 32, 245)
    const COLOR_BORDER = (218, 178, 90, 220)
    const COLOR_TITLE = (245, 240, 228, 255)
    const COLOR_BODY = (220, 216, 208, 255)
    const COLOR_MUTED = (160, 154, 142, 255)
    const COLOR_BUFF = (120, 210, 150, 255)
    const COLOR_DEBUFF = (230, 120, 110, 255)
    const HIGHLIGHT = Any[
        OuterGlowEffect(
            radius = 15,
            color = (255, 240, 180, 210),
            fade_amount = 1.8,
            fade_curve = 15.5,
            force_white = true,
        ),
    ]

    const STATUS_LINES = (
        (:burn, "Burn", false),
        (:freeze, "Freeze", false),
        (:poison, "Poison", false),
        (:vulnerable, "Vulnerable", false),
        (:weaken, "Weaken", false),
        (:shock, "Shock", false),
        (:dodge_chance, "Dodge", true),
        (:reflect_chance, "Reflect", true),
    )

    mutable struct PopupState
        entity::Any
        combatant::Any
        visible::Bool
        progress::Float64
        highlighted::Bool
        character_name::String
        last_image_path::String
        glow_ready::Bool
    end

    const STATE = PopupState(nothing, nothing, false, 0.0, false, "Player", "", false)

    _scaled(c::NTuple{4, Int}, a::Float64) = (c[1], c[2], c[3], round(Int, c[4] * a))
    _text_w(s::String, fs::Int) = round(Int, length(s) * fs * 0.55)

    function _character_label(combatant)::String
        try
            key = String(combatant.selectedCharacter)
            key == "CHARACTER_MAGICIAN" && return "Magician"
            key == "CHARACTER_DEMOLITIONIST" && return "Demolitionist"
            key == "CHARACTER_KNIGHT" && return "Knight"
            return replace(key, "CHARACTER_" => "")
        catch
            return "Player"
        end
    end

    function _sprite_hovered(entity)::Bool
        entity === nothing && return false
        try
            if hasproperty(entity, :isHovered) && entity.isHovered === true
                return true
            end
        catch
        end
        spr = try entity.sprite catch; nothing end
        (spr === nothing || spr == C_NULL) && return false
        try
            if hasproperty(spr, :isHovered) && spr.isHovered === true
                return true
            end
        catch
        end
        try
            pos = spr.lastRenderedScreenPosition
            size = spr.lastRenderedScreenSize
            (pos === nothing || size === nothing) && return false
            mouse = MAIN.input.mousePosition
            mx, my = Float64(mouse.x), Float64(mouse.y)
            return mx >= Float64(pos.x) && mx <= Float64(pos.x) + Float64(size.x) &&
                   my >= Float64(pos.y) && my <= Float64(pos.y) + Float64(size.y)
        catch
            return false
        end
    end

    """Bake OuterGlow for the current imagePath; keep useEffectTexture off until hover."""
    function _prepare_glow!()
        spr = STATE.entity === nothing ? nothing : STATE.entity.sprite
        (spr === nothing || spr == C_NULL) && return
        try
            path = string(something(spr.imagePath, ""))
            JulGame.apply_effects!(spr, HIGHLIGHT)
            if hasproperty(spr, :useEffectTexture)
                spr.useEffectTexture = STATE.highlighted
            end
            STATE.last_image_path = path
            STATE.glow_ready = true
        catch e
            @debug "PlayerCombatantPopup prepare glow: $e"
            STATE.glow_ready = false
        end
    end

    function _set_highlight!(on::Bool)
        spr = STATE.entity === nothing ? nothing : STATE.entity.sprite
        (spr === nothing || spr == C_NULL) && return
        STATE.highlighted == on && return
        STATE.highlighted = on
        try
            if !STATE.glow_ready
                _prepare_glow!()
            end
            if hasproperty(spr, :useEffectTexture)
                spr.useEffectTexture = on
            end
        catch e
            @debug "PlayerCombatantPopup highlight: $e"
        end
    end

    function attach!(entity, combatant)::Bool
        entity === nothing && return false
        STATE.entity = entity
        STATE.combatant = combatant
        STATE.character_name = _character_label(combatant)
        STATE.visible = false
        STATE.progress = 0.0
        STATE.highlighted = false
        STATE.last_image_path = ""
        STATE.glow_ready = false
        _prepare_glow!()
        return true
    end

    function detach!()
        _set_highlight!(false)
        spr = STATE.entity === nothing ? nothing : try STATE.entity.sprite catch; nothing end
        if spr !== nothing && spr != C_NULL && hasproperty(spr, :useEffectTexture)
            spr.useEffectTexture = false
        end
        STATE.entity = nothing
        STATE.combatant = nothing
        STATE.visible = false
        STATE.progress = 0.0
        STATE.glow_ready = false
    end

    function ensure!(user)::Bool
        user === nothing && return false
        entity = try user.playerEntity catch; nothing end
        if entity === nothing
            try
                entity = JulGame.SceneModule.get_entity_by_id(MAIN.scene, PLAYER_ENTITY_ID)
            catch
            end
        end
        entity === nothing && return false
        if STATE.entity === entity && STATE.combatant === user
            return true
        end
        return attach!(entity, user)
    end

    function update!(deltaTime)
        STATE.entity === nothing && return
        spr = try STATE.entity.sprite catch; nothing end
        if spr !== nothing && spr != C_NULL
            path = string(something(spr.imagePath, ""))
            if path != STATE.last_image_path
                was = STATE.highlighted
                STATE.highlighted = false
                _prepare_glow!()
                if was
                    STATE.highlighted = true
                    if hasproperty(spr, :useEffectTexture)
                        spr.useEffectTexture = true
                    end
                end
            end
        end

        board_busy = false
        try
            board_busy = parentmodule(@__MODULE__).TooltipManagerModule.battle_board_in_action()
        catch
        end
        hovered = !board_busy && _sprite_hovered(STATE.entity)
        STATE.visible = hovered
        _set_highlight!(hovered)

        target = STATE.visible ? 1.0 : 0.0
        if STATE.progress != target
            duration = STATE.visible ? SHOW_DURATION : HIDE_DURATION
            step = Float64(deltaTime) / duration
            STATE.progress = clamp(STATE.progress + (STATE.visible ? step : -step), 0.0, 1.0)
        end
    end

    function _stat_rows(c)
        rows = String[]
        try
            push!(rows, "HP  $(c.health) / $(c.maxHealth)")
            if Int(c.shield) > 0
                push!(rows, "Shield  $(c.shield)")
            end
            push!(rows, "ATK  $(c.attack)    DEF  $(c.defense)")
            push!(rows, "SPD  $(c.speed)    LUCK  $(c.luck)")
            for (field, label, is_pct) in STATUS_LINES
                val = try
                    PM = JulGame.UserGlobals["Module"].PiecesModule
                    field === :dodge_chance ? PM.player_dodge_chance(c) :
                    field === :reflect_chance ? PM.player_reflect_chance(c) : Int(getproperty(c, field))
                catch
                    0
                end
                val <= 0 && continue
                if is_pct
                    push!(rows, "$label  $(val)%")
                else
                    push!(rows, "$label  $val")
                end
            end
        catch e
            @debug "PlayerCombatantPopup stats: $e"
        end
        return rows
    end

    function _status_color(line::String)
        for (_, label, is_buff) in STATUS_LINES
            if startswith(line, label)
                return is_buff ? COLOR_BUFF : COLOR_DEBUFF
            end
        end
        return COLOR_BODY
    end

    function draw!(_deltaTime = 0.0)
        (STATE.progress <= 0.0 || STATE.combatant === nothing) && return
        c = STATE.combatant
        rows = _stat_rows(c)
        isempty(rows) && return

        alpha = clamp(STATE.progress * 1.2, 0.0, 1.0)
        slide = STATE.visible ? ease_out_back(STATE.progress) : ease_out_cubic(STATE.progress)

        title = STATE.character_name
        card_w = max(_text_w(title, TITLE_FS) + 2 * PAD, MIN_W)
        for row in rows
            card_w = max(card_w, _text_w(row, BODY_FS) + 2 * PAD)
        end
        card_w = clamp(card_w, MIN_W, MAX_W)
        card_h = PAD + TITLE_FS + 12 + length(rows) * LINE_H + PAD

        # Anchor to the right of the player sprite when possible.
        card_x = 72.0
        card_y = 160.0
        try
            spr = STATE.entity.sprite
            pos = spr.lastRenderedScreenPosition
            size = spr.lastRenderedScreenSize
            if pos !== nothing && size !== nothing
                card_x = Float64(pos.x) + Float64(size.x) + 16.0
                card_y = Float64(pos.y) + 8.0
                cam = MAIN.scene.camera
                if cam !== nothing
                    max_x = Float64(cam.size.x) - card_w - EDGE
                    max_y = Float64(cam.size.y) - card_h - EDGE
                    card_x = clamp(card_x, EDGE, max_x)
                    card_y = clamp(card_y, EDGE, max_y)
                end
            end
        catch
        end
        card_y -= (1.0 - slide) * 28.0

        JulGame.ImmediateUIModule.immediate_rect(
            "player_combatant_popup_bg";
            position = Math.Vector2(card_x, card_y),
            size = Math.Vector2(card_w, card_h),
            color = _scaled(COLOR_BG, alpha),
            layer = 950,
        )
        JulGame.ImmediateUIModule.immediate_rect(
            "player_combatant_popup_border";
            position = Math.Vector2(card_x, card_y),
            size = Math.Vector2(card_w, 3),
            color = _scaled(COLOR_BORDER, alpha),
            layer = 951,
        )

        DisplayTextModule.display_text(
            "player_combatant_popup_title",
            title;
            position = Math.Vector2(card_x + PAD, card_y + PAD),
            fontSize = TITLE_FS,
            color = _scaled(COLOR_TITLE, alpha),
            layer = 952,
        )

        y = card_y + PAD + TITLE_FS + 10
        for (i, row) in enumerate(rows)
            DisplayTextModule.display_text(
                "player_combatant_popup_row_$i",
                row;
                position = Math.Vector2(card_x + PAD, y),
                fontSize = BODY_FS,
                color = _scaled(_status_color(row), alpha),
                layer = 952,
            )
            y += LINE_H
        end
    end
end
