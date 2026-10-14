module PostRunScreenModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.EffectsModule
    using ..Scripts
    include("localization/ui_strings.jl")
    using .UIStringsModule
    using ..CurrentRunStatusModule

    # battle.json — entity "Background" (Sprite `bg-floor1battle-0000.png`, layer -35)
    const BATTLE_SCENE_BACKGROUND_ENTITY_ID = "f9786556-2cc4-40fc-bb38-9c68e940a375"

    """Ensure the battle scene floor Background entity stays active so it renders in the world pass under immediate UI."""
    function _ensure_battle_floor_background_visible!()
        try
            ent = JulGame.SceneModule.get_entity_by_id(BATTLE_SCENE_BACKGROUND_ENTITY_ID)
            ent === nothing && return
            ent.isActive = true
            if ent.sprite !== nothing && ent.sprite != C_NULL
                ent.sprite.layer = 30
            end
        catch e
            @debug "Post-run: could not ensure battle Background entity: $(e)"
        end
    end

    """
    Captured run state for the end-of-run screen (survives defeat resets).
    """
    mutable struct RunEndSnapshot
        runElapsedTime::Float64
        currentFloor::Int
        currentRoom::Int
        health::Int
        maxHealth::Int
        gold::Int
        selectedCharacter::String
        pieces::Vector{Any}
        potions::Vector{Any}
        treasures::Vector{Any}
        highestCombo::Int
        isVictory::Bool
    end

    const _run_snapshot = Ref{Union{Nothing,RunEndSnapshot}}(nothing)
    const _tooltip_manager = Ref{Any}(nothing)

    function capture_run_end_snapshot!(user, persistentState, is_victory::Bool)
        _run_snapshot[] = RunEndSnapshot(
            persistentState.runElapsedTime,
            persistentState.currentFloor,
            persistentState.currentRoom,
            user.health,
            user.maxHealth,
            user.gold,
            user.selectedCharacter,
            Vector{Any}(copy(user.pieces)),
            Vector{Any}(copy(user.potions)),
            Vector{Any}(copy(user.treasures)),
            persistentState.highestComboThisRun,
            is_victory,
        )
        return nothing
    end

    function get_snapshot()::Union{Nothing,RunEndSnapshot}
        return _run_snapshot[]
    end

    function clear_run_end_snapshot!()
        _run_snapshot[] = nothing
        return nothing
    end

    function _ensure_tooltip!()
        if _tooltip_manager[] === nothing
            try
                ent = JulGame.EntityModule.Entity("PostRunEndTooltip")
                ent = JulGame.create_entity(ent)
                push!(ent.scripts, Scripts.TooltipManagerModule.TooltipManager())
                _tooltip_manager[] = ent.scripts[1]
                Scripts.TooltipManagerModule.set_tooltip_style(
                    _tooltip_manager[],
                    hoverDelay = UInt64(120)
                )
            catch e
                @debug "PostRun screen tooltip init: $e"
            end
        end
        return _tooltip_manager[]
    end

    function _draw_left_summary_panel!(snap::RunEndSnapshot, panel_parent)
        font_path = "Century-Normal.ttf"
        text_color = (255, 255, 255, 255)
        body_font = 18
        small_font = 15
        portrait_size = 100
        item_size = 90
        items_per_row = 3
        panel_w = 480
        panel_h = 560
        portrait_end_x = 20 + portrait_size + 15
        info_center_x = portrait_end_x + div(panel_w - portrait_end_x - 20, 2) - 60

        header = snap.isVictory ? UI_STRINGS[:post_run_victory] : UI_STRINGS[:post_run_defeat]
        DisplayTextModule.display_text(
            "post_run_header", header;
            fontPath = font_path,
            fontSize = 42,
            color = text_color,
            parent = panel_parent,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(0, -55),
            layer = 52,
        )

        main = JulGame.ImmediateUIModule.immediate_rect(
            "post_run_left_panel";
            size = Math.Vector2(panel_w, panel_h),
            color = (24, 18, 36, 245),
            borderWidth = 3,
            borderColor = (240, 240, 255, 255),
            parent = panel_parent,
            anchor = :topLeft,
            layer = 50,
        )
        JulGame.apply_effects!(main, [RoughEdgeEffect(amount = 1, seed = 42, erosion = true)])

        time_str = CurrentRunStatusModule.format_elapsed_time(snap.runElapsedTime)
        DisplayTextModule.display_text(
            "post_run_game_time",
            UIStringsModule.format_string(:current_run_game_time, time = time_str);
            fontPath = font_path,
            fontSize = small_font,
            color = text_color,
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(info_center_x, 25),
            layer = 51,
        )

        JulGame.ImmediateUIModule.immediate_rect(
            "post_run_portrait_bg";
            size = Math.Vector2(portrait_size, portrait_size),
            color = (60, 60, 60, 255),
            borderWidth = 2,
            borderColor = (200, 200, 200, 255),
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(20, 20),
            layer = 51,
        )
        portrait_path = if snap.selectedCharacter == "CHARACTER_DEMOLITIONIST"
            JulGame.UserGlobals["Module"].get_asset_path("character", "demolitionistportrait")
        elseif snap.selectedCharacter == "CHARACTER_KNIGHT"
            JulGame.UserGlobals["Module"].get_asset_path("character", "knightportrait")
        else
            JulGame.UserGlobals["Module"].get_asset_path("character", "magicianportrait")
        end
        JulGame.ImmediateUIModule.immediate_button(
            "post_run_portrait",
            () -> nothing;
            size = Math.Vector2(portrait_size, portrait_size),
            buttonUpPath = portrait_path,
            buttonDownPath = portrait_path,
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(20, 20),
            layer = 52,
        )

        quarter = div(panel_w - portrait_end_x - 20, 4)
        DisplayTextModule.display_text(
            "post_run_floor",
            UIStringsModule.format_string(:current_run_floor, floor = snap.currentFloor);
            fontPath = font_path,
            fontSize = body_font,
            color = (100, 255, 100, 255),
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portrait_end_x + quarter - 20, 50),
            layer = 51,
        )
        DisplayTextModule.display_text(
            "post_run_room",
            UIStringsModule.format_string(:current_run_room, room = snap.currentRoom);
            fontPath = font_path,
            fontSize = body_font,
            color = (100, 255, 100, 255),
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portrait_end_x + 3 * quarter - 40, 50),
            layer = 51,
        )

        combo_txt = UIStringsModule.format_string(:post_run_highest_combo, n = snap.highestCombo)
        DisplayTextModule.display_text(
            "post_run_combo_line",
            combo_txt;
            fontPath = font_path,
            fontSize = small_font,
            color = (200, 200, 200, 255),
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portrait_end_x + 55, 75),
            layer = 51,
        )

        stats_y = 125
        third_w = div(panel_w - 40, 3)
        heart = JulGame.ImmediateUIModule.immediate_image(
            "post_run_heart", JulGame.UserGlobals["Module"].get_asset_path("ui", "healthheart");
            size = Math.Vector2(24, 24),
            color = (255, 70, 127, 255),
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(20, stats_y),
            layer = 52,
        )
        ratio = snap.maxHealth > 0 ? Float64(snap.health) / Float64(snap.maxHealth) : 0.0
        CurrentRunStatusModule.gfx_clock_hand_sweep_ui(heart, ratio)
        DisplayTextModule.display_text(
            "post_run_hp", "$(snap.health)/$(snap.maxHealth)";
            fontPath = font_path,
            fontSize = body_font,
            color = text_color,
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(52, stats_y + 2),
            layer = 51,
        )

        JulGame.ImmediateUIModule.immediate_button(
            "post_run_gold",
            () -> nothing;
            size = Math.Vector2(24, 24),
            buttonUpPath = JulGame.UserGlobals["Module"].get_asset_path("ui", "money"),
            buttonDownPath = JulGame.UserGlobals["Module"].get_asset_path("ui", "money"),
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(20 + third_w, stats_y),
            layer = 52,
        )
        DisplayTextModule.display_text(
            "post_run_goldv", "$(snap.gold)";
            fontPath = font_path,
            fontSize = body_font,
            color = text_color,
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(52 + third_w, stats_y + 2),
            layer = 51,
        )
        for (i, pot) in enumerate(snap.potions)
            if i > 3
                break
            end
            path = CurrentRunStatusModule.get_potion_icon_path(pot.key)
            pbtn = JulGame.ImmediateUIModule.immediate_button(
                "post_run_p$(i)", () -> nothing;
                size = Math.Vector2(28, 28),
                buttonUpPath = path,
                buttonDownPath = path,
                parent = main,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(20 + 2 * third_w + (i - 1) * 32, stats_y - 2),
                layer = 52,
            )
            tm = _ensure_tooltip!()
            if tm !== nothing
                Scripts.TooltipManagerModule.register_tooltip_item(tm, pbtn, CurrentRunStatusModule.get_potion_tooltip_text(pot))
            end
        end

        JulGame.ImmediateUIModule.immediate_rect(
            "post_run_divider_h";
            size = Math.Vector2(panel_w - 40, 2),
            color = (200, 200, 200, 200),
            parent = main,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 160),
            layer = 51,
        )
        JulGame.ImmediateUIModule.immediate_rect(
            "post_run_divider_v";
            size = Math.Vector2(2, 300),
            color = (200, 200, 200, 200),
            parent = main,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 200),
            layer = 51,
        )

        section_y = 170
        DisplayTextModule.display_text(
            "post_run_pieces_title",
            UIStringsModule.format_string(:current_run_pieces_count, count = length(snap.pieces));
            fontPath = font_path,
            fontSize = body_font,
            color = text_color,
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(70, section_y),
            layer = 51,
        )
        for (i, piece) in enumerate(snap.pieces)
            col = (i - 1) % items_per_row
            row = (i - 1) ÷ items_per_row
            item_x = -5 + col * (item_size - 25)
            item_y = -row * (item_size - 25)
            slot = JulGame.ImmediateUIModule.immediate_rect(
                "post_run_pslot_$(i)";
                size = Math.Vector2(100, 100),
                color = (60, 80, 100, 0),
                parent = main,
                anchor = :bottomLeft,
                anchorOffset = Math.Vector2(item_x, item_y - 20),
                layer = 51,
            )
            ip = CurrentRunStatusModule.get_icon_path(piece.key)
            ib = JulGame.ImmediateUIModule.immediate_button(
                "post_run_piece_$(i)", () -> nothing;
                size = Math.Vector2(90, 90),
                buttonUpPath = ip,
                buttonDownPath = ip,
                layer = 52,
                anchor = :center,
                parent = slot,
                forceClickCheck = true,
            )
            tm = _ensure_tooltip!()
            if tm !== nothing
                Scripts.TooltipManagerModule.register_tooltip_item(tm, ib, CurrentRunStatusModule.get_piece_tooltip_text(piece, collect(Any, snap.pieces)))
            end
        end

        DisplayTextModule.display_text(
            "post_run_treasure_title",
            UIStringsModule.format_string(:current_run_treasures_count, count = length(snap.treasures));
            fontPath = font_path,
            fontSize = body_font,
            color = text_color,
            parent = main,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(255, section_y),
            layer = 51,
        )
        for (i, tr) in enumerate(snap.treasures)
            col = (i - 1) % items_per_row
            row = (i - 1) ÷ items_per_row
            item_x = panel_w ÷ 2 + 20 + col * (item_size - 25)
            item_y = section_y + 30 + row * (item_size - 15)
            tp = CurrentRunStatusModule.get_treasure_icon_path(tr.key)
            tbtn = JulGame.ImmediateUIModule.immediate_button(
                "post_run_tr_$(i)", () -> nothing;
                size = Math.Vector2(90, 90),
                buttonUpPath = tp,
                buttonDownPath = tp,
                parent = main,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(item_x, item_y + 0),
                layer = 52,
            )
            tm = _ensure_tooltip!()
            if tm !== nothing
                Scripts.TooltipManagerModule.register_tooltip_item(tm, tbtn, CurrentRunStatusModule.get_treasure_tooltip_text(tr))
            end
        end

        return main
    end

    # Layout from Battler/scenes/scratch.json UIElements (1920x1080, top-left)
    const _SCRATCH_FONT_BODY = "Bahnschrift-Regular.ttf"
    const _SCRATCH_FONT_EXIT = "18thCentury-Regular.ttf"

    function _draw_scratch_post_run_promo!(root, on_exit::Function, on_wish::Function, on_disc::Function)
        JulGame.ImmediateUIModule.immediate_image(
            "post_run_scratch_logo",
            "logo-necromatcher-final-1.png";
            size = Math.Vector2(1420, 490),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(488, 102),
            layer = 42,
            color = (255, 255, 255, 255),
        )

        DisplayTextModule.display_text(
            "post_run_scratch_thanks",
            "Thank you for playing...";
            fontPath = _SCRATCH_FONT_BODY,
            fontSize = 83,
            color = (255, 255, 255, 255),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(828, 69),
            maxLineWidth = 900,
            layer = 43,
        )
        DisplayTextModule.display_text(
            "post_run_scratch_enjoyed",
            "If you enjoyed the game, please give it a wishlist!";
            fontPath = _SCRATCH_FONT_BODY,
            fontSize = 50,
            color = (255, 255, 255, 255),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(720, 525),
            maxLineWidth = 1100,
            layer = 43,
        )
        DisplayTextModule.display_text(
            "post_run_scratch_tuned",
            "Stay tuned as we continue to develop the game!";
            fontPath = _SCRATCH_FONT_BODY,
            fontSize = 50,
            color = (255, 255, 255, 255),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(725, 575),
            maxLineWidth = 1100,
            layer = 43,
        )
        DisplayTextModule.display_text(
            "post_run_scratch_items",
            "More items, more characters, more floors...";
            fontPath = _SCRATCH_FONT_BODY,
            fontSize = 50,
            color = (255, 255, 255, 255),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(760, 625),
            maxLineWidth = 1000,
            layer = 43,
        )
        DisplayTextModule.display_text(
            "post_run_scratch_news",
            "Get the latest news and developments in our Discord! Wishlist on Steam!";
            fontPath = _SCRATCH_FONT_BODY,
            fontSize = 35,
            color = (255, 255, 255, 255),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(666, 727),
            maxLineWidth = 1200,
            layer = 43,
        )

        JulGame.ImmediateUIModule.immediate_button(
            "post_run_scratch_wishlist",
            on_wish;
            text = "",
            name = "Wishlist",
            anchor = :topLeft,
            anchorOffset = Math.Vector2(827, 809),
            size = Math.Vector2(350, 250),
            buttonUpPath = JulGame.UserGlobals["Module"].get_asset_path("promo", "wishlist"),
            buttonDownPath = JulGame.UserGlobals["Module"].get_asset_path("promo", "wishlisthovered"),
            parent = root,
            layer = 45,
            isCentered = false,
            forceClickCheck = true,
        )
        JulGame.ImmediateUIModule.immediate_button(
            "post_run_scratch_discord",
            on_disc;
            text = "",
            name = "Discord",
            anchor = :topLeft,
            anchorOffset = Math.Vector2(1263, 805),
            size = Math.Vector2(350, 250),
            buttonUpPath = JulGame.UserGlobals["Module"].get_asset_path("promo", "discord"),
            buttonDownPath = JulGame.UserGlobals["Module"].get_asset_path("promo", "discordhovered"),
            parent = root,
            layer = 45,
            isCentered = false,
            forceClickCheck = true,
        )

        JulGame.ImmediateUIModule.immediate_button(
            "post_run_scratch_exit_door",
            on_exit;
            text = "",
            name = "Exit",
            anchor = :topLeft,
            anchorOffset = Math.Vector2(26, 810),
            size = Math.Vector2(198, 267),
            buttonUpPath = JulGame.UserGlobals["Module"].get_asset_path("ui", "exitdoorclosed"),
            buttonDownPath = JulGame.UserGlobals["Module"].get_asset_path("ui", "exitdooropen"),
            parent = root,
            layer = 45,
            isCentered = false,
            forceClickCheck = true,
        )
        DisplayTextModule.display_text(
            "post_run_scratch_exit_word",
            "Exit";
            fontPath = _SCRATCH_FONT_EXIT,
            fontSize = 220,
            color = (255, 255, 255, 255),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(230, 880),
            clickEvent = on_exit,
            layer = 46,
            maxLineWidth = 400,
        )
    end

    function draw_post_run_screen!(battle_manager)
        snap = get_snapshot()
        if snap === nothing
            return
        end
        trans = battle_manager.transitionManager
        on_exit = () -> begin
            try
                Scripts.SceneTransitionModule.transition_to_scene(trans, "title_scene.json"; direction = Scripts.SceneTransitionModule.Fade)
            catch e
                @error "Post-run exit transition: $e"
            end
        end
        on_wish = () -> JulGame.SDL2.SDL_OpenURL("https://store.steampowered.com/app/1410040?utm_source=postrun")
        on_disc = () -> JulGame.SDL2.SDL_OpenURL("https://discord.gg/gFkrEtA35m")

        # World sprites (including battle.json Background) render before immediate UI; keep that entity on and use a light dim so the floor art stays readable.
        _ensure_battle_floor_background_visible!()
        JulGame.ImmediateUIModule.immediate_rect(
            "post_run_fullbg";
            size = Math.Vector2(1920, 1080),
            color = (0, 0, 0, 95),
            anchor = :center,
            layer = 8,
        )

        root = JulGame.ImmediateUIModule.immediate_rect(
            "post_run_root";
            size = Math.Vector2(1920, 1080),
            color = (0, 0, 0, 0),
            anchor = :center,
            layer = 9,
        )

        left_wrap = JulGame.ImmediateUIModule.immediate_rect(
            "post_run_left_wrap";
            size = Math.Vector2(1, 1),
            color = (0, 0, 0, 0),
            parent = root,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(40, 80),
            layer = 48,
        )
        _draw_left_summary_panel!(snap, left_wrap)

        _draw_scratch_post_run_promo!(root, on_exit, on_wish, on_disc)

        tm = _ensure_tooltip!()
        if tm !== nothing
            Scripts.TooltipManagerModule.check_tooltip_hovers(tm)
        end
    end

    export RunEndSnapshot, capture_run_end_snapshot!, get_snapshot, clear_run_end_snapshot!, draw_post_run_screen!
end
