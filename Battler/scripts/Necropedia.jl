module NecropediaModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.EffectsModule
    using ..Scripts
    include("utils/AchievementCard.jl")
    using .AchievementCardModule
    include("localization/ui_strings.jl")
    using .UIStringsModule

    const _LIFETIME = JulGame.ImmediateUIModule.INFINITE_LIFETIME
    const PANEL_W = 1040
    const PANEL_H = 660
    const SIDEBAR_W = 150
    const ITEM_SIZE = 72
    const ITEM_SPACING = 10
    const ITEMS_PER_ROW = 8
    const VISIBLE_ROWS = 4
    const ACH_COLS = 2
    const SCROLL_SPEED = 280.0

    _g() = JulGame.UserGlobals["Module"]

    mutable struct Necropedia
        isActive::Bool
        section::Symbol
        unlock_subsection::Symbol
        scrollOffset::Float64
        achievementScrollOffset::Float64
        selectedItemKey::Union{String, Nothing}
        panelX::Int
        panelY::Int
        menuLink

        function Necropedia()
            this = new()
            this.isActive = false
            this.section = :unlocks
            this.unlock_subsection = :pieces
            this.scrollOffset = 0.0
            this.achievementScrollOffset = 0.0
            this.selectedItemKey = nothing
            this.panelX = (1920 - PANEL_W) ÷ 2
            this.panelY = (1080 - PANEL_H) ÷ 2
            this.menuLink = nothing
            return this
        end
    end

    function open(this::Necropedia)
        this.isActive = true
        this.scrollOffset = 0.0
        this.achievementScrollOffset = 0.0
        this.selectedItemKey = nothing
        if this.menuLink !== nothing
            this.menuLink.isActive = false
        end
    end

    function close(this::Necropedia)
        this.isActive = false
        this.selectedItemKey = nothing
        if this.menuLink !== nothing
            this.menuLink.isActive = true
        end
    end

    function item_icon_path(key::String)::String
        parts = split(key, "_", limit = 2)
        length(parts) < 2 && return "missing-asset.png"
        return _g().get_asset_path(lowercase(parts[1]), lowercase(parts[2]))
    end

    function catalog_for_subsection(subsection::Symbol)
        data = _g().get_data_manager()
        if subsection == :pieces
            return data.piece_data
        elseif subsection == :treasures
            return data.treasure_data
        elseif subsection == :potions
            return data.potion_data
        end
        return Dict{String, Any}()
    end

    function sorted_catalog_keys(subsection::Symbol)::Vector{String}
        catalog = catalog_for_subsection(subsection)
        keys = String[]
        for (key, item) in catalog
            _g().item_available_in_game(item) || continue
            push!(keys, string(key))
        end
        sort!(keys)
        return keys
    end

    function item_display_name(key::String, unlocked::Bool)::String
        unlocked || return UIStringsModule.UI_STRINGS[:necropedia_locked_name]
        catalog = catalog_for_subsection(
            startswith(key, "PIECE_") ? :pieces :
            startswith(key, "TREASURE_") ? :treasures : :potions
        )
        item = get(catalog, key, nothing)
        item === nothing && return key
        return item.name
    end

    function item_display_description(key::String, unlocked::Bool)::String
        if !unlocked
            achievement = _g().AchievementTrackerModule.unlock_hint_for_item(key)
            if achievement !== nothing
                return _g().AchievementTrackerModule.description(achievement)
            end
            return UIStringsModule.UI_STRINGS[:necropedia_locked_hint]
        end
        catalog = catalog_for_subsection(
            startswith(key, "PIECE_") ? :pieces :
            startswith(key, "TREASURE_") ? :treasures : :potions
        )
        item = get(catalog, key, nothing)
        item === nothing && return ""
        return item.description
    end

    function format_play_time(seconds::Int)::String
        seconds <= 0 && return "0m"
        hours = seconds ÷ 3600
        minutes = (seconds % 3600) ÷ 60
        hours > 0 && return "$(hours)h $(minutes)m"
        return "$(minutes)m"
    end

    function collection_percent(meta)::Int
        data = _g().get_data_manager()
        total = 0
        unlocked = 0
        for catalog in (data.piece_data, data.treasure_data, data.potion_data)
            for (key, item) in catalog
                _g().item_available_in_game(item) || continue
                total += 1
                _g().MetaProgressModule.is_unlocked(meta, string(key)) && (unlocked += 1)
            end
        end
        total == 0 && return 0
        return round(Int, 100 * unlocked / total)
    end

    function create_menu_link(this::Necropedia, play_click_sound::Function)
        open_necropedia = () -> begin
            play_click_sound()
            open(this)
        end
        this.menuLink = DisplayTextModule.display_text(
            "necropedia_menu_link",
            UIStringsModule.UI_STRINGS[:necropedia_menu_label];
            anchor = :topRight,
            anchorOffset = Math.Vector2(-30, 40),
            fontSize = 28,
            color = (255, 240, 200, 255),
            fontPath = "Century-Normal.ttf",
            layer = 50,
            isActive = true,
            clickEvent = open_necropedia,
            lifetime = _LIFETIME,
        )
        if isempty(this.menuLink.effects)
            JulGame.apply_effects!(this.menuLink, [
                DropShadowEffect(distance = 4.0, angle = 135.0, blur_radius = 4, color = (0, 0, 0, 255), opacity = 120),
            ])
        end
    end

    function handle_scrolling!(this::Necropedia, deltaTime::Float64)
        if this.section == :unlocks
            keys = sorted_catalog_keys(this.unlock_subsection)
            total_rows = ceil(Int, length(keys) / ITEMS_PER_ROW)
            max_scroll = max(0.0, Float64((total_rows - VISIBLE_ROWS) * (ITEM_SIZE + ITEM_SPACING)))
            if JulGame.InputModule.get_button_held_down("Up")
                this.scrollOffset = max(0.0, this.scrollOffset - SCROLL_SPEED * deltaTime)
            elseif JulGame.InputModule.get_button_held_down("Down")
                this.scrollOffset = min(max_scroll, this.scrollOffset + SCROLL_SPEED * deltaTime)
            end
        elseif this.section == :achievements
            achievements = _g().AchievementTrackerModule.get_all_achievements()
            total_rows = ceil(Int, length(achievements) / ACH_COLS)
            visible_rows = 3
            card_stride = AchievementCardModule.CARD_HEIGHT + 12
            max_scroll = max(0.0, Float64((total_rows - visible_rows) * card_stride))
            if JulGame.InputModule.get_button_held_down("Up")
                this.achievementScrollOffset = max(0.0, this.achievementScrollOffset - SCROLL_SPEED * deltaTime)
            elseif JulGame.InputModule.get_button_held_down("Down")
                this.achievementScrollOffset = min(max_scroll, this.achievementScrollOffset + SCROLL_SPEED * deltaTime)
            end
        end
    end

    function draw_sidebar_nav(this::Necropedia)
        content_x = this.panelX + 16
        y = this.panelY + 56
        for (section, label_key) in (
            (:unlocks, :necropedia_section_unlocks),
            (:stats, :necropedia_section_stats),
            (:achievements, :necropedia_section_achievements),
        )
            is_selected = this.section == section
            btn_color = is_selected ? (70, 70, 100, 255) : (45, 45, 60, 200)
            Scripts.NineSliceUIModule.immediate_button(
                "necropedia_nav_$(section)",
                () -> begin
                    this.section = section
                    this.scrollOffset = 0.0
                    this.achievementScrollOffset = 0.0
                    this.selectedItemKey = nothing
                end;
                position = Math.Vector2(content_x, y),
                size = Math.Vector2(SIDEBAR_W, 40),
                text = UIStringsModule.UI_STRINGS[label_key],
                fontSize = 18,
                color = btn_color,
                layer = 111,
            )
            y += 48
        end
    end

    function draw_unlock_subtabs(this::Necropedia)
        base_x = this.panelX + SIDEBAR_W + 28
        y = this.panelY + 56
        meta = _g().get_meta_progress()
        for (sub, label_key) in (
            (:pieces, :necropedia_sub_pieces),
            (:treasures, :necropedia_sub_treasures),
            (:potions, :necropedia_sub_potions),
        )
            is_selected = this.unlock_subsection == sub
            unlocked, total = _g().MetaProgressModule.completion_ratio(meta, catalog_for_subsection(sub))
            tab_label = "$(UIStringsModule.UI_STRINGS[label_key]) ($unlocked/$total)"
            btn_color = is_selected ? (90, 80, 120, 255) : (50, 50, 65, 200)
            x_off = sub == :pieces ? 0 : sub == :treasures ? 150 : 310
            Scripts.NineSliceUIModule.immediate_button(
                "necropedia_sub_$(sub)",
                () -> begin
                    this.unlock_subsection = sub
                    this.scrollOffset = 0.0
                    this.selectedItemKey = nothing
                end;
                position = Math.Vector2(base_x + x_off, y),
                size = Math.Vector2(140, 32),
                text = tab_label,
                fontSize = 15,
                color = btn_color,
                layer = 111,
            )
        end
    end

    function draw_unlocks_section(this::Necropedia)
        draw_unlock_subtabs(this)
        meta = _g().get_meta_progress()
        keys = sorted_catalog_keys(this.unlock_subsection)
        grid_x = this.panelX + SIDEBAR_W + 28
        grid_y = this.panelY + 100
        row_stride = ITEM_SIZE + ITEM_SPACING
        start_row = round(Int, this.scrollOffset / row_stride)

        for (index, key) in enumerate(keys)
            row = (index - 1) ÷ ITEMS_PER_ROW
            col = (index - 1) % ITEMS_PER_ROW
            row < start_row && continue
            row > start_row + VISIBLE_ROWS && continue

            y = Int(round(grid_y + (row - start_row) * row_stride - (this.scrollOffset % row_stride)))
            x = grid_x + col * (ITEM_SIZE + ITEM_SPACING)
            unlocked = _g().MetaProgressModule.is_unlocked(meta, key)
            icon_color = unlocked ? (255, 255, 255, 255) : (0, 0, 0, 255)

            JulGame.ImmediateUIModule.immediate_rect(
                "necropedia_slot_$(key)";
                position = Math.Vector2(x, y),
                size = Math.Vector2(ITEM_SIZE, ITEM_SIZE),
                color = (25, 25, 35, 200),
                borderWidth = unlocked ? 2 : 1,
                borderColor = unlocked ? (120, 120, 160, 255) : (40, 40, 40, 255),
                borderRadius = 4,
                layer = 111,
            )

            JulGame.ImmediateUIModule.immediate_image(
                "necropedia_icon_$(key)",
                item_icon_path(key);
                position = Math.Vector2(x + 6, y + 6),
                size = Math.Vector2(ITEM_SIZE - 12, ITEM_SIZE - 12),
                color = icon_color,
                layer = 112,
                clickEvents = Function[() -> (this.selectedItemKey = key)],
            )
        end

        if this.selectedItemKey !== nothing
            key = this.selectedItemKey
            unlocked = _g().MetaProgressModule.is_unlocked(meta, key)
            detail_y = this.panelY + PANEL_H - 110
            JulGame.ImmediateUIModule.immediate_rect(
                "necropedia_detail_bg";
                position = Math.Vector2(this.panelX + SIDEBAR_W + 20, detail_y),
                size = Math.Vector2(PANEL_W - SIDEBAR_W - 40, 90),
                color = (20, 20, 30, 230),
                borderWidth = 1,
                borderColor = (80, 80, 100, 255),
                borderRadius = 4,
                layer = 111,
            )
            DisplayTextModule.display_text(
                "necropedia_detail_name",
                item_display_name(key, unlocked);
                position = Math.Vector2(this.panelX + SIDEBAR_W + 32, detail_y + 10),
                fontSize = 22,
                color = unlocked ? (240, 240, 255, 255) : (120, 120, 120, 255),
                fontPath = "Century-Normal.ttf",
                layer = 112,
            )
            DisplayTextModule.display_text(
                "necropedia_detail_desc",
                item_display_description(key, unlocked);
                position = Math.Vector2(this.panelX + SIDEBAR_W + 32, detail_y + 40),
                fontSize = 15,
                color = (180, 180, 200, 255),
                fontPath = "Century-Normal.ttf",
                layer = 112,
            )
        end

        total_rows = ceil(Int, length(keys) / ITEMS_PER_ROW)
        if total_rows > VISIBLE_ROWS
            DisplayTextModule.display_text(
                "necropedia_scroll_hint",
                UIStringsModule.UI_STRINGS[:necropedia_scroll_hint];
                position = Math.Vector2(this.panelX + PANEL_W - 200, this.panelY + PANEL_H - 28),
                fontSize = 13,
                color = (140, 140, 160, 255),
                layer = 112,
            )
        end
    end

    function draw_stat_card(id::String, label::String, value::String, position::Math.Vector2)
        px = Int(round(position.x))
        py = Int(round(position.y))
        JulGame.ImmediateUIModule.immediate_rect(
            "$(id)_bg";
            position = position,
            size = Math.Vector2(200, 90),
            color = (35, 35, 50, 220),
            borderWidth = 1,
            borderColor = (90, 90, 120, 255),
            borderRadius = 6,
            layer = 111,
        )
        DisplayTextModule.display_text(
            "$(id)_label",
            label;
            position = Math.Vector2(px + 12, py + 10),
            fontSize = 14,
            color = (160, 160, 190, 255),
            fontPath = "Century-Normal.ttf",
            layer = 112,
        )
        DisplayTextModule.display_text(
            "$(id)_value",
            value;
            position = Math.Vector2(px + 12, py + 36),
            fontSize = 28,
            color = (240, 240, 255, 255),
            fontPath = "Century-Normal.ttf",
            layer = 112,
        )
    end

    function draw_stats_section(this::Necropedia)
        meta = _g().get_meta_progress()
        base_x = this.panelX + SIDEBAR_W + 28
        base_y = this.panelY + 80
        col_w = 220
        stats = [
            ("stat_runs", UIStringsModule.UI_STRINGS[:necropedia_stat_runs_started], string(_g().MetaProgressModule.get_stat(meta, "runs_started"))),
            ("stat_won", UIStringsModule.UI_STRINGS[:necropedia_stat_runs_won], string(_g().MetaProgressModule.get_stat(meta, "runs_won"))),
            ("stat_lost", UIStringsModule.UI_STRINGS[:necropedia_stat_runs_lost], string(_g().MetaProgressModule.get_stat(meta, "runs_lost"))),
            ("stat_enemies", UIStringsModule.UI_STRINGS[:necropedia_stat_enemies], string(_g().MetaProgressModule.get_stat(meta, "enemies_killed"))),
            ("stat_combo", UIStringsModule.UI_STRINGS[:necropedia_stat_combo], string(_g().MetaProgressModule.get_stat(meta, "longest_combo"))),
            ("stat_floor", UIStringsModule.UI_STRINGS[:necropedia_stat_floor], string(_g().MetaProgressModule.get_stat(meta, "floors_reached_best"))),
            ("stat_time", UIStringsModule.UI_STRINGS[:necropedia_stat_playtime], format_play_time(_g().MetaProgressModule.get_stat(meta, "total_play_time_sec"))),
            ("stat_coll", UIStringsModule.UI_STRINGS[:necropedia_stat_collection], "$(collection_percent(meta))%"),
            ("stat_dmg", UIStringsModule.UI_STRINGS[:necropedia_stat_damage], string(_g().MetaProgressModule.get_stat(meta, "total_damage_dealt"))),
            ("stat_pots", UIStringsModule.UI_STRINGS[:necropedia_stat_potions], string(_g().MetaProgressModule.get_stat(meta, "potions_used"))),
            ("stat_gold", UIStringsModule.UI_STRINGS[:necropedia_stat_gold], string(_g().MetaProgressModule.get_stat(meta, "gold_spent"))),
        ]
        for (i, (id, label, value)) in enumerate(stats)
            row = (i - 1) ÷ 3
            col = (i - 1) % 3
            draw_stat_card(id, label, value, Math.Vector2(base_x + col * col_w, base_y + row * 105))
        end
    end

    function draw_achievements_section(this::Necropedia)
        meta = _g().get_meta_progress()
        achievements = _g().AchievementTrackerModule.get_all_achievements()
        base_x = this.panelX + SIDEBAR_W + 28
        base_y = this.panelY + 80
        card_w = AchievementCardModule.CARD_WIDTH + 16
        card_h = AchievementCardModule.CARD_HEIGHT + 12
        start_row = round(Int, this.achievementScrollOffset / card_h)

        for (index, achievement) in enumerate(achievements)
            row = (index - 1) ÷ ACH_COLS
            col = (index - 1) % ACH_COLS
            row < start_row && continue
            row > start_row + 3 && continue

            y = base_y + (row - start_row) * card_h - (this.achievementScrollOffset % card_h)
            x = base_x + col * card_w
            is_complete = achievement.key in meta.completed_achievements
            progress = _g().AchievementTrackerModule.achievement_progress(meta, achievement)
            AchievementCardModule.draw_achievement_card(
                achievement,
                Math.Vector2(x, y),
                is_complete,
                progress;
                card_id = "necropedia_ach_$(achievement.key)",
                completed_label = UIStringsModule.UI_STRINGS[:necropedia_completed],
                unlocks_prefix = UIStringsModule.UI_STRINGS[:necropedia_unlocks_prefix],
            )
        end

        total_rows = ceil(Int, length(achievements) / ACH_COLS)
        if total_rows > 3
            DisplayTextModule.display_text(
                "necropedia_ach_scroll",
                UIStringsModule.UI_STRINGS[:necropedia_scroll_hint];
                position = Math.Vector2(this.panelX + PANEL_W - 200, this.panelY + PANEL_H - 28),
                fontSize = 13,
                color = (140, 140, 160, 255),
                layer = 112,
            )
        end
    end

    function display_ui(this::Necropedia)
        JulGame.ImmediateUIModule.immediate_rect(
            "necropedia_overlay";
            position = Math.Vector2(0, 0),
            size = Math.Vector2(1920, 1080),
            color = (0, 0, 0, 160),
            layer = 105,
        )

        Scripts.NineSliceUIModule.immediate_panel(
            "necropedia_panel";
            position = Math.Vector2(this.panelX, this.panelY),
            size = Math.Vector2(PANEL_W, PANEL_H),
            layer = 110,
        )

        DisplayTextModule.display_text(
            "necropedia_title",
            UIStringsModule.UI_STRINGS[:necropedia_title];
            position = Math.Vector2(this.panelX + PANEL_W ÷ 2 - 80, this.panelY + 14),
            fontSize = 30,
            color = (220, 200, 255, 255),
            fontPath = "Century-Normal.ttf",
            layer = 111,
        )

        Scripts.NineSliceUIModule.immediate_button(
            "necropedia_back",
            () -> close(this);
            position = Math.Vector2(this.panelX + 16, this.panelY + 12),
            size = Math.Vector2(90, 34),
            text = UIStringsModule.UI_STRINGS[:necropedia_back],
            fontSize = 18,
            color = (80, 60, 60, 255),
            layer = 111,
        )

        draw_sidebar_nav(this)

        if this.section == :unlocks
            draw_unlocks_section(this)
        elseif this.section == :stats
            draw_stats_section(this)
        elseif this.section == :achievements
            draw_achievements_section(this)
        end
    end

    function handle_input(this::Necropedia, deltaTime::Float64)
        if !this.isActive
            return
        end
        handle_scrolling!(this, deltaTime)
        display_ui(this)
    end
end
