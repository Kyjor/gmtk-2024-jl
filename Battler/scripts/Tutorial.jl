"""
TutorialModule

One-time guided lesson in the opening battle of a run, plus the settings "How to play" page.

- Offer bar: slides down from top center before the first swap. Checked on first play.
  Tucks to a sliver if untouched; hover pops it back out. Unchecking aborts.
- Steps: speech bubbles (typing effect + DisplayText) with bouncing arrows. Some steps wait
  for a real action (a pointed match, a target switch).
- Gameplay code only calls the small gate/notify API below.
"""
module TutorialModule
    using JulGame
    using JulGame.Math
    using ..Scripts
    include("TypingEffect.jl")
    using .TypingEffectModule
    include("localization/tutorial_strings.jl")
    using .TutorialStringsModule

    const DT = TypingEffectModule.DisplayTextModule
    const T = TutorialStringsModule.TUTORIAL_STRINGS

    const FONT = "Century-Normal.ttf"
    const LAYER = 950
    const PRIMER_LAYER = 5000       # settings menu elements sit around 3000
    const PRIMER_HOST_NAME = "SettingsMenu_Settings title"
    const PRIMER_BUTTON_OFFSET = Vector2(1104, 19)  # from the title's top-left: puts the button at (1335, 40)

    const BAR_W = 250
    const BAR_H = 96                # nine-slice needs > 2 * PANEL_SLICE to fill
    const BAR_OUT_Y = 8.0
    const BAR_PEEK_PX = 12
    const BAR_TUCK_DELAY_S = 8.0
    const BAR_SLIDE_RATE = 10.0

    const BUBBLE_W = 620
    const BUBBLE_H = 240
    const BUBBLE_PAD = 40
    const BUBBLE_MARGIN = 60

    const ARROW_SIZE = 56
    const ARROW_BOB_PX = 12.0
    const ARROW_BOB_HZ = 1.6
    const ARROW_COLOR = (255, 214, 90, 255)
    const ACCENT = (214, 186, 255, 255)

    const CHECKBOX_PATH = "ui-checkboxactive"
    const CHECKMARK_PATH = "ui-checkmark"
    const TAIL_PATH = "gem-arrow"

    const FLASH_HZ = 2.5
    const FLASH_DEPTH = 130

    const RESOLVING_STATES = (:switchingItems, :searchingForMatches, :replaceItems, :processTurn)

    struct Step
        id::Symbol
        kind::Symbol    # :talk | :match | :target
        arrow::Symbol   # where the arrow points
    end

    const STEPS = Step[
        Step(:board, :talk, :grid),
        Step(:enemies, :talk, :intent),
        Step(:pieces, :talk, :piece),
        Step(:match, :match, :none),
        Step(:combo_intro, :talk, :combo),
        Step(:combo_match, :match, :none),
        Step(:combo_result, :talk, :combo),
        Step(:target, :target, :other_enemy),
        Step(:treasure, :talk, :treasures),
        Step(:shield, :talk, :shield),
        Step(:ability, :talk, :ability),
        Step(:potions, :talk, :potions),
        Step(:done, :talk, :none),
    ]

    mutable struct TutorialState
        phase::Symbol               # :inactive | :pending | :offer | :steps | :hidden
        checked::Bool
        anySwap::Bool
        barY::Float64
        tuckTimer::Float64
        stepIndex::Int
        stepKind::Symbol
        arrow::Symbol
        typing::Any
        hint::Any                   # (a, b, ax, ay, bx, by) or nothing
        flashed::Vector{Tuple{Any, Any}}  # (piece, original sprite color)
        swapPending::Bool
        stepChain::Int
        targetBefore::Any
        frame::Int
        clickFrame::Int
        time::Float64
        gm::Any
        observer::Any
        primerOpen::Bool
        primerOpenedAt::Float64
    end

    const S = TutorialState(:inactive, false, false, -BAR_H - 20.0, 0.0, 0, :talk, :none,
        nothing, nothing, Tuple{Any, Any}[], false, 0, nothing, 0, -1, 0.0, nothing, nothing, false, 0.0)

    # ---------------------------------------------------------------- persistence

    _globals() = JulGame.UserGlobals["Module"]

    function is_completed()::Bool
        try
            return _globals().get_meta_progress().tutorial_completed
        catch
            return false
        end
    end

    function mark_completed!()
        try
            g = _globals()
            meta = g.get_meta_progress()
            meta.tutorial_completed && return
            meta.tutorial_completed = true
            g.MetaProgressModule.try_save_profile!(meta)
        catch e
            @warn "Tutorial: could not save completion" exception = e
        end
    end

    # ---------------------------------------------------------------- lifecycle

    function is_opening_battle()::Bool
        try
            psm = _globals().get_data_manager().persistent_state_manager
            return psm.currentFloor == 1 && psm.regularMapBattlesWonThisRun == 0
        catch
            return false
        end
    end

    function on_battle_start!(gm)
        on_battle_end!()
        S.gm = gm
        S.frame = 0
        S.clickFrame = -1
        S.anySwap = false
        S.hint = nothing
        S.swapPending = false
        S.barY = -BAR_H - 20.0
        S.tuckTimer = 0.0
        S.phase = is_opening_battle() ? :pending : :inactive
        S.phase == :inactive && return
        S.checked = !is_completed()
        S.typing = TypingEffectModule.TypingEffectController("";
            base_speed_ms = 28.0,
            play_sound_every_n_chars = 2,
            punctuation_pause_ms = 220.0,
            skip_key = "RETURN",
            skip_on_click = false,
        )
        register_observer!()
    end

    function on_battle_end!()
        unregister_observer!()
        restore_flash!()
        S.phase != :inactive && S.typing !== nothing && TypingEffectModule.halt_typing_sound()
        S.phase = :inactive
        S.gm = nothing
        S.typing = nothing
    end

    function register_observer!()
        g = _globals()
        obs = (event, data) -> on_notify(event, data)
        S.observer = obs
        g.ObserverModule.add_observer(g.get_observer_data(), obs)
    end

    function unregister_observer!()
        S.observer === nothing && return
        try
            g = _globals()
            g.ObserverModule.remove_observer(g.get_observer_data(), S.observer)
        catch
        end
        S.observer = nothing
    end

    function on_notify(event::Symbol, _data)
        event == :combo_data && S.swapPending && (S.stepChain += 1)
    end

    # ---------------------------------------------------------------- gameplay gates

    consumed_click() = S.clickFrame == S.frame
    offer_armed() = S.phase == :offer && S.checked

    function blocks_board_input()::Bool
        S.phase == :inactive && return false
        (consumed_click() || bar_hovered() || offer_armed()) && return true
        return S.phase == :steps && S.stepKind != :match
    end

    function blocks_enemy_target()::Bool
        S.phase == :inactive && return false
        (consumed_click() || offer_armed()) && return true
        return S.phase == :steps && S.stepKind != :target
    end

    function blocks_side_actions()::Bool
        S.phase == :inactive && return false
        (consumed_click() || offer_armed()) && return true
        return S.phase == :steps
    end

    function allows_swap(a, b)::Bool
        (S.phase == :steps && S.stepKind == :match) || return true
        h = S.hint
        h === nothing && return false
        return (a === h[1] && b === h[2]) || (a === h[2] && b === h[1])
    end

    """Call before the swap starts: the swap animation captures piece colors as its base."""
    function note_swap!()
        S.anySwap = true
        restore_flash!()
        if S.phase == :offer && !S.checked
            S.phase = :hidden
        elseif S.phase == :steps && S.stepKind == :match
            S.swapPending = true
            S.stepChain = 0
        end
    end

    # ---------------------------------------------------------------- hint flash

    function set_piece_color!(piece, color)
        try
            piece.sprite.color = color
        catch
        end
    end

    function restore_flash!()
        for (piece, color) in S.flashed
            set_piece_color!(piece, color)
        end
        empty!(S.flashed)
    end

    function update_flash!()
        h = S.hint
        want = (S.phase == :steps && S.stepKind == :match && h !== nothing && !S.swapPending) ? (h[1], h[2]) : ()
        if length(S.flashed) != length(want) || any(i -> S.flashed[i][1] !== want[i], eachindex(S.flashed))
            restore_flash!()
            for piece in want
                color = try piece.sprite.color catch; (255, 255, 255, 255) end
                push!(S.flashed, (piece, color))
            end
        end
        isempty(S.flashed) && return
        v = round(Int, 255 - FLASH_DEPTH * (0.5 + 0.5 * sin(S.time * 2π * FLASH_HZ)))
        for (piece, color) in S.flashed
            set_piece_color!(piece, (v * color[1] ÷ 255, v * color[2] ÷ 255, v * color[3] ÷ 255, color[4]))
        end
    end

    # ---------------------------------------------------------------- screen helpers

    function screen_size()
        cam = MAIN.scene.camera
        cam === nothing && return (1920.0, 1080.0)
        return (Float64(cam.size.x), Float64(cam.size.y))
    end

    function world_to_screen(wx, wy)
        cam = MAIN.scene.camera
        cam === nothing && return (0.0, 0.0)
        s = Float64(JulGame.pixels_per_world_unit(cam))
        return ((Float64(wx) - (cam.position.x + cam.offset.x)) * s,
                (Float64(wy) - (cam.position.y + cam.offset.y)) * s)
    end

    mouse() = (Float64(MAIN.input.mousePosition.x), Float64(MAIN.input.mousePosition.y))

    function in_rect(p, x, y, w, h)
        return x <= p[1] <= x + w && y <= p[2] <= y + h
    end

    function sprite_rect(entity)
        try
            (entity === nothing || !entity.isActive) && return nothing
            spr = entity.sprite
            (spr === nothing || spr == C_NULL) && return nothing
            pos = spr.lastRenderedScreenPosition
            sz = spr.lastRenderedScreenSize
            (pos === nothing || sz === nothing || sz.x <= 0) && return nothing
            return (Float64(pos.x), Float64(pos.y), Float64(sz.x), Float64(sz.y))
        catch
            return nothing
        end
    end

    ui_rect(el) = el === nothing ? nothing :
        (Float64(el.position.x), Float64(el.position.y), Float64(el.size.x), Float64(el.size.y))

    function find_script(::Type{X}) where X
        for e in MAIN.scene.entities, s in e.scripts
            s isa X && return s
        end
        return nothing
    end

    bar_x() = screen_size()[1] / 2 - BAR_W / 2
    bar_hovered() = S.phase in (:offer, :steps) && in_rect(mouse(), bar_x(), S.barY, BAR_W, BAR_H)

    # ---------------------------------------------------------------- battle helpers

    bm() = S.gm.battleManager
    gc() = S.gm.gridController
    in_state(sym::Symbol) = bm().currentState == bm().battleStates[sym]

    function living_enemies()
        out = Any[]
        for e in bm().enemies
            es = e.scripts[1]
            es.health > 0 && push!(out, es)
        end
        return out
    end

    function other_enemy()
        for es in living_enemies()
            es !== bm().selectedEnemy && return es
        end
        return nothing
    end

    nailed(p) = try Scripts.AbilityManagerModule.is_piece_nailed(p) catch; false end

    function find_matching_swap()
        g = gc()
        w, h = Int(g.gridWidth), Int(g.gridHeight)
        for y in 1:h, x in 1:w
            a = g.gridPieces[x, y]
            (a === nothing || nailed(a)) && continue
            for (dx, dy) in ((1, 0), (0, 1))
                nx, ny = x + dx, y + dy
                (nx > w || ny > h) && continue
                b = g.gridPieces[nx, ny]
                (b === nothing || nailed(b) || a.name == b.name) && continue
                isempty(Scripts.GridControllerModule.get_swap_preview_matches(g, a, b)) && continue
                return (a, b, x, y, nx, ny)
            end
        end
        return nothing
    end

    function hint_valid()
        h = S.hint
        h === nothing && return false
        g = gc()
        (g.gridPieces[h[3], h[4]] === h[1] && g.gridPieces[h[5], h[6]] === h[2]) || return false
        return !isempty(Scripts.GridControllerModule.get_swap_preview_matches(g, h[1], h[2]))
    end

    character_name() = lowercase(replace(string(_globals().get_user_data().selectedCharacter), "CHARACTER_" => ""))

    ability_key() = character_name() == "demolitionist" ? "TREASURE_DETONATOR" : "TREASURE_HOCUSPOCUS"

    function ability_text()
        key = Symbol("ability_", character_name())
        return get(T, key, T[:ability_default]) * " " * T[:ability_more]
    end

    # ---------------------------------------------------------------- step flow

    function say!(text::String)
        TypingEffectModule.start_typing(S.typing, text)
    end

    function start_steps!()
        S.phase = :steps
        S.stepIndex = 0
        next_step!()
    end

    function next_step!()
        S.stepIndex += 1
        if S.stepIndex > length(STEPS)
            finish!()
            return
        end
        enter_step!(STEPS[S.stepIndex])
    end

    function enter_step!(step::Step)
        S.stepKind = step.kind
        S.arrow = step.arrow
        S.swapPending = false
        S.hint = nothing
        if step.id == :target
            if length(living_enemies()) < 2
                next_step!()
                return
            end
            S.targetBefore = bm().selectedEnemy
        end
        say!(step_text(step.id))
    end

    function step_text(id::Symbol)::String
        id == :ability && return ability_text()
        if id == :combo_result
            return S.stepChain >= 2 ? replace(T[:combo_result_hit], "{count}" => string(S.stepChain)) : T[:combo_result_none]
        end
        return T[id]
    end

    function fallback_to_talk!(text::String)
        S.stepKind = :talk
        S.arrow = :none
        S.hint = nothing
        say!(text)
    end

    function finish!()
        mark_completed!()
        TypingEffectModule.halt_typing_sound()
        S.phase = :hidden
    end

    function abort!()
        TypingEffectModule.halt_typing_sound()
        S.phase = S.anySwap ? :hidden : :offer
        S.tuckTimer = 0.0
    end

    function update_match_step!()
        if S.swapPending
            any(in_state, RESOLVING_STATES) && return
            S.swapPending = false
            STEPS[S.stepIndex].id == :combo_match || (S.stepChain = 0)
            next_step!()
            return
        end
        if !in_state(:playerTurn)
            S.hint = nothing
            return
        end
        hint_valid() && return
        S.hint = find_matching_swap()
        if S.hint === nothing
            if STEPS[S.stepIndex].id == :combo_match
                S.stepChain = 0
                next_step!()
            else
                fallback_to_talk!(T[:match_none])
            end
        end
    end

    function update_target_step!()
        sel = bm().selectedEnemy
        if sel !== S.targetBefore && sel !== nothing
            S.stepKind = :talk
            S.arrow = :none
            say!(T[:target_done])
        elseif other_enemy() === nothing
            next_step!()
        end
    end

    function update_steps!(dt::Float64, clicked::Bool, bar_hover::Bool)
        busy = !TypingEffectModule.is_typing_complete(S.typing)
        TypingEffectModule.update(S.typing, dt)

        if S.stepKind == :match
            update_match_step!()
        elseif S.stepKind == :target
            update_target_step!()
        else
            advance = (clicked && !bar_hover) ||
                JulGame.InputModule.get_button_pressed("RETURN") ||
                JulGame.InputModule.get_button_pressed("SPACE")
            if advance
                clicked && (S.clickFrame = S.frame)
                advance!(busy)
            end
        end
    end

    """A click or RETURN on a talk step: finish the typing first, then move on."""
    function advance!(busy::Bool = !TypingEffectModule.is_typing_complete(S.typing))
        busy ? TypingEffectModule.complete_instantly(S.typing) : next_step!()
    end

    # ---------------------------------------------------------------- offer bar

    function update_bar!(dt::Float64, clicked::Bool, hovered::Bool)
        if clicked && hovered
            S.clickFrame = S.frame
            S.checked = !S.checked
            S.tuckTimer = 0.0
            if S.phase == :steps && !S.checked
                abort!()
            end
        end
        if S.phase == :offer
            if S.checked
                start_steps!()
                return
            end
            S.tuckTimer += dt
            if S.tuckTimer >= BAR_TUCK_DELAY_S && !hovered
                S.tuckTimer = BAR_TUCK_DELAY_S
            end
        end
    end

    function bar_target_y()::Float64
        S.phase == :hidden && return -BAR_H - 20.0
        S.phase == :offer && S.tuckTimer < BAR_TUCK_DELAY_S && return BAR_OUT_Y
        bar_hovered() && return BAR_OUT_Y
        return -(BAR_H - BAR_PEEK_PX)
    end

    function draw_bar!(dt::Float64)
        S.barY += (bar_target_y() - S.barY) * min(1.0, dt * BAR_SLIDE_RATE)
        S.barY < -BAR_H - 10 && return
        panel = Scripts.NineSliceUIModule.immediate_panel("tutorial_offer_bar";
            size = Vector2(BAR_W, BAR_H),
            position = Vector2(bar_x(), S.barY),
            layer = LAYER,
        )
        box = 34
        JulGame.ImmediateUIModule.immediate_image("tutorial_offer_box", JulGame.UserGlobals["Module"].get_asset_path(CHECKBOX_PATH);
            parent = panel, anchor = :topLeft,
            anchorOffset = Vector2(34, (BAR_H - box) ÷ 2),
            size = Vector2(box, box), layer = LAYER + 2,
        )
        if S.checked
            JulGame.ImmediateUIModule.immediate_image("tutorial_offer_check", JulGame.UserGlobals["Module"].get_asset_path(CHECKMARK_PATH);
                parent = panel, anchor = :topLeft,
                anchorOffset = Vector2(38, (BAR_H - box) ÷ 2 - 6),
                size = Vector2(30, 36), color = ACCENT, layer = LAYER + 3,
            )
        end
        DT.display_text("tutorial_offer_label", T[:offer_label];
            fontPath = FONT, fontSize = 30, parent = panel, anchor = :topLeft,
            anchorOffset = Vector2(84, (BAR_H - 36) ÷ 2), layer = LAYER + 2, applyEffects = false,
        )
    end

    # ---------------------------------------------------------------- arrows + bubble

    """Screen rects (x, y, w, h) the current arrow points at."""
    function arrow_rects()
        a = S.arrow
        W, H = screen_size()
        user = _globals().get_user_data()
        if a == :grid
            g = gc()
            x0, y0 = world_to_screen(g.gridStartX, g.gridStartY)
            x1, y1 = world_to_screen(g.gridStartX + g.gridWidth * g.gridCellWidth, g.gridStartY + g.gridHeight * g.gridCellHeight)
            return [(x0, y0, x1 - x0, y1 - y0)]
        elseif a == :intent
            for es in living_enemies()
                r = sprite_rect(es.intent)
                r !== nothing && return [r]
            end
        elseif a == :piece
            g = gc()
            p = g.gridPieces[cld(Int(g.gridWidth), 2), cld(Int(g.gridHeight), 2)]
            r = sprite_rect(p)
            r !== nothing && return [r]
        elseif a == :combo
            return [(W / 2 + 300, 20.0, 100.0, 60.0)]
        elseif a == :other_enemy
            es = other_enemy()
            es !== nothing && (r = sprite_rect(es.healthHeart)) !== nothing && return [r]
        elseif a == :treasures
            isempty(user.treasures) || return [(0.0, H - 101.0, 96.0, 96.0)]
        elseif a == :shield
            r = sprite_rect(user.shieldUI)
            r === nothing && (r = sprite_rect(user.healthHeart))
            r !== nothing && return [r]
        elseif a == :ability
            ad = find_script(Scripts.AbilityDisplayModule.AbilityDisplay)
            if ad !== nothing && !isempty(ad.abilityCards)
                card = get(ad.abilityCards, ability_key(), first(values(ad.abilityCards)))
                return [ui_rect(card)]
            end
        elseif a == :potions
            el = JulGame.SceneModule.get_ui_element_by_id("ui_potion_holder")
            el !== nothing && el.isActive && return [ui_rect(el)]
            return [(W - 420.0, 20.0, 400.0, 110.0)]
        end
        return []
    end

    function draw_arrow!(id::String, r)
        x, y, w, h = r
        bob = ARROW_BOB_PX * (0.5 + 0.5 * sin(S.time * 2π * ARROW_BOB_HZ))
        W, H = screen_size()
        cx = x + w / 2 - ARROW_SIZE * 0.4
        # Targets in the top third get an arrow underneath pointing up.
        up = y + h / 2 < H / 3
        ay = up ? y + h + 4 + bob : y - ARROW_SIZE - 4 - bob
        DT.display_text(id, up ? "▲" : "▼";
            fontSize = ARROW_SIZE, color = ARROW_COLOR,
            position = Vector2(cx, ay), layer = LAYER + 4,
        )
    end

    bubble_side() = S.arrow in (:treasures, :shield, :ability) ? :right : :left

    function draw_bubble!()
        W, H = screen_size()
        bx = bubble_side() == :left ? BUBBLE_MARGIN : W - BUBBLE_MARGIN - BUBBLE_W
        by = H * 0.34
        panel = Scripts.NineSliceUIModule.immediate_panel("tutorial_bubble";
            size = Vector2(BUBBLE_W, BUBBLE_H),
            position = Vector2(bx, by),
            layer = LAYER,
        )
        JulGame.ImmediateUIModule.immediate_image("tutorial_bubble_tail", JulGame.UserGlobals["Module"].get_asset_path(TAIL_PATH);
            position = Vector2(bx + BUBBLE_W ÷ 2 - 20, by + BUBBLE_H - 6),
            size = Vector2(40, 22), rotation = 180.0, color = ACCENT, layer = LAYER + 2,
        )
        DT.display_text("tutorial_bubble_title", T[:bubble_title];
            fontPath = FONT, fontSize = 20, color = ACCENT, parent = panel, anchor = :topLeft,
            anchorOffset = Vector2(BUBBLE_PAD, 22), layer = LAYER + 2, applyEffects = false,
        )
        DT.display_text("tutorial_bubble_text", TypingEffectModule.get_visible_text(S.typing);
            fontPath = FONT, fontSize = 26, parent = panel, anchor = :topLeft,
            anchorOffset = Vector2(BUBBLE_PAD, 52), layer = LAYER + 2,
            maxLineWidth = BUBBLE_W - 2 * BUBBLE_PAD, wrapWords = true, applyEffects = false,
        )
        if S.stepKind == :talk && TypingEffectModule.is_typing_complete(S.typing) && S.typing.completion_indicator_visible
            DT.display_text("tutorial_bubble_continue", T[:continue_hint];
                fontPath = FONT, fontSize = 18, color = (200, 200, 210, 255), parent = panel,
                anchor = :bottomRight, anchorOffset = Vector2(-BUBBLE_PAD - 150, -34),
                layer = LAYER + 2, applyEffects = false,
            )
        end
        rects = try
            arrow_rects()
        catch e
            @debug "Tutorial arrow target: $e"
            []
        end
        for (i, r) in enumerate(rects)
            draw_arrow!("tutorial_arrow_$(i)", r)
        end
    end

    # ---------------------------------------------------------------- tick

    function update!(dt::Float64)
        S.phase == :inactive && return
        S.gm === nothing && return
        S.frame += 1
        S.time += dt
        if in_state(:battleEnd)
            on_battle_end!()
            return
        end
        (S.gm.pauseMenu.paused || Scripts.SettingsDisplayManagerModule.is_settings_open()) && return

        if S.phase == :pending
            in_state(:playerTurn) || return
            S.checked ? start_steps!() : (S.phase = :offer)
        end

        clicked = JulGame.InputModule.get_mouse_button_pressed(1)
        hovered = bar_hovered()
        S.phase in (:offer, :steps) && update_bar!(dt, clicked, hovered)
        S.phase == :steps && update_steps!(dt, clicked, hovered)
        update_flash!()

        draw_bar!(dt)
        S.phase == :steps && draw_bubble!()
    end

    # ---------------------------------------------------------------- settings primer

    const PRIMER_ROWS = (
        ("piece-sword", :primer_match),
        ("intent-spikey-sword", :primer_enemies),
        ("piece-potion", :primer_weight),
        ("treasure-log", :primer_items),
        ("treasure-hocuspocus", :primer_ability),
        ("piece-shield", :primer_shield),
    )

    is_primer_open() = S.primerOpen

    function toggle_primer!()
        S.primerOpen = !S.primerOpen
        S.primerOpenedAt = time()
    end

    """Call every frame from the settings screen with its SettingsDisplayManager."""
    function update_primer!(sdm)
        canvas = sdm.settingsCanvas
        if canvas === nothing || !canvas.isActive
            S.primerOpen = false
            return
        end
        if S.primerOpen
            draw_primer!()
            return
        end
        # Parented to a settings element so the button flies in/out with the menu.
        i = findfirst(el -> el.name == PRIMER_HOST_NAME, canvas.children)
        i === nothing && return
        host = canvas.children[i]
        JulGame.ImmediateUIModule.immediate_button("tutorial_primer_button", () -> S.primerOpen || toggle_primer!();
            text = T[:primer_button],
            fontSize = 30,
            parent = host,
            anchor = :topLeft,
            anchorOffset = PRIMER_BUTTON_OFFSET,
            size = Vector2(330, 96),
            buttonUpPath = JulGame.UserGlobals["Module"].get_asset_path(Scripts.NineSliceUIModule.PANEL_PATH),
            buttonDownPath = JulGame.UserGlobals["Module"].get_asset_path(Scripts.NineSliceUIModule.PANEL_HOVER_PATH),
            color = Scripts.NineSliceUIModule.DEFAULT_PANEL_COLOR,
            layer = host.layer + 10,
            forceClickCheck = true,
        )
    end

    function draw_primer!()
        if time() - S.primerOpenedAt > 0.15 &&
            (JulGame.InputModule.get_mouse_button_pressed(1) || JulGame.InputModule.get_button_pressed("ESCAPE"))
            S.primerOpen = false
            return
        end
        W, H = screen_size()
        pw, ph = 1100, 700
        JulGame.ImmediateUIModule.immediate_rect("tutorial_primer_dim";
            position = Vector2(0, 0), size = Vector2(W, H),
            color = (0, 0, 0, 190), layer = PRIMER_LAYER,
        )
        panel = Scripts.NineSliceUIModule.immediate_panel("tutorial_primer_panel";
            size = Vector2(pw, ph),
            position = Vector2((W - pw) / 2, (H - ph) / 2),
            layer = PRIMER_LAYER + 1,
        )
        DT.display_text("tutorial_primer_title", T[:primer_title];
            fontPath = FONT, fontSize = 48, color = ACCENT, parent = panel, anchor = :topLeft,
            anchorOffset = Vector2(60, 40), layer = PRIMER_LAYER + 2, applyEffects = false,
        )
        for (i, (icon, key)) in enumerate(PRIMER_ROWS)
            row_y = 120 + (i - 1) * 84
            JulGame.ImmediateUIModule.immediate_image("tutorial_primer_icon_$(i)", JulGame.UserGlobals["Module"].get_asset_path(icon);
                parent = panel, anchor = :topLeft, anchorOffset = Vector2(70, row_y),
                size = Vector2(64, 64), layer = PRIMER_LAYER + 2,
            )
            DT.display_text("tutorial_primer_row_$(i)", T[key];
                fontPath = FONT, fontSize = 28, parent = panel, anchor = :topLeft,
                anchorOffset = Vector2(160, row_y + 14), layer = PRIMER_LAYER + 2,
                maxLineWidth = pw - 220, wrapWords = true, applyEffects = false,
            )
        end
        DT.display_text("tutorial_primer_close", T[:primer_close];
            fontPath = FONT, fontSize = 20, color = (180, 180, 190, 255), parent = panel,
            anchor = :bottomLeft, anchorOffset = Vector2(60, -50), layer = PRIMER_LAYER + 2,
            applyEffects = false,
        )
    end

    # ---------------------------------------------------------------- scripted player (TestManager)

    """The hinted swap `(a, b)` while a match step is waiting for it, else nothing."""
    match_hint() = (S.phase == :steps && S.stepKind == :match && S.hint !== nothing) ? (S.hint[1], S.hint[2]) : nothing

    """The enemy the target step wants selected, else nothing."""
    target_hint() = (S.phase == :steps && S.stepKind == :target) ? other_enemy() : nothing

    """True while a talk step waits for a click or RETURN."""
    awaiting_advance() = S.phase == :steps && S.stepKind == :talk

    export on_battle_start!, on_battle_end!, update!,
        blocks_board_input, blocks_enemy_target, blocks_side_actions, allows_swap, note_swap!,
        update_primer!, draw_primer!, toggle_primer!, is_primer_open, is_completed, mark_completed!,
        match_hint, target_hint, awaiting_advance, advance!
end # module
