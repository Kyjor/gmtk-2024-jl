module AchievementCardModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule
    using JulGame.EffectsModule

    const CARD_WIDTH = 360
    const CARD_HEIGHT = 130
    const ICON_SIZE = 64

    _g() = JulGame.UserGlobals["Module"]

    """Resolve achievement icon path from `type/slug` or item key fallback."""
    function achievement_icon_path(icon::String)
        parts = split(icon, "/")
        if length(parts) >= 2
            return _g().get_asset_path(string(parts[1]), string(parts[2]))
        end
        return _g().get_asset_path("ui", "settingsbutton")
    end

    function unlock_item_label(item_key::String)::String
        parts = split(item_key, "_", limit = 2)
        length(parts) < 2 && return item_key
        catalog_type = lowercase(parts[1])
        data = _g().get_data_manager()
        if catalog_type == "piece" && haskey(data.piece_data, item_key)
            return data.piece_data[item_key].name
        elseif catalog_type == "treasure" && haskey(data.treasure_data, item_key)
            return data.treasure_data[item_key].name
        elseif catalog_type == "potion" && haskey(data.potion_data, item_key)
            return data.potion_data[item_key].name
        end
        return replace(parts[2], "_" => " ")
    end

    function unlocks_summary(achievement)::String
        isempty(achievement.unlocks) && return ""
        names = [unlock_item_label(key) for key in achievement.unlocks]
        return join(names, ", ")
    end

    """
    Draw one achievement card at absolute screen `position`.
    Children use absolute coords (same pattern as InventoryManager).
    """
    function draw_achievement_card(
        achievement,
        position::Math.Vector2,
        is_complete::Bool,
        progress::Float64;
        card_id::String,
        layer::Int = 120,
        completed_label::String = "Completed",
        unlocks_prefix::String = "Unlocks:",
    )
        bg_color = is_complete ? (35, 50, 35, 230) : (30, 30, 42, 220)
        border_color = is_complete ? (80, 180, 80, 255) : (90, 90, 110, 255)
        px = Int(round(position.x))
        py = Int(round(position.y))

        card_bg = JulGame.ImmediateUIModule.immediate_rect(
            "$(card_id)_bg";
            position = position,
            size = Math.Vector2(CARD_WIDTH, CARD_HEIGHT),
            color = bg_color,
            borderWidth = 2,
            borderColor = border_color,
            borderRadius = 6,
            layer = layer,
        )

        icon_color = is_complete ? (255, 255, 255, 255) : (200, 200, 200, 200)
        JulGame.ImmediateUIModule.immediate_image(
            "$(card_id)_icon",
            achievement_icon_path(achievement.icon);
            position = Math.Vector2(px + 12, py + 12),
            size = Math.Vector2(ICON_SIZE, ICON_SIZE),
            color = icon_color,
            layer = layer + 1,
        )

        tracker = _g().AchievementTrackerModule
        title_color = is_complete ? (220, 255, 200, 255) : (240, 240, 255, 255)
        DisplayTextModule.display_text(
            "$(card_id)_title",
            tracker.name(achievement);
            position = Math.Vector2(px + 88, py + 10),
            fontSize = 20,
            color = title_color,
            fontPath = "Century-Normal.ttf",
            layer = layer + 1,
        )

        DisplayTextModule.display_text(
            "$(card_id)_desc",
            tracker.description(achievement);
            position = Math.Vector2(px + 88, py + 36),
            fontSize = 14,
            color = (180, 180, 200, 255),
            fontPath = "Century-Normal.ttf",
            layer = layer + 1,
        )

        unlock_text = unlocks_summary(achievement)
        if !isempty(unlock_text)
            DisplayTextModule.display_text(
                "$(card_id)_unlocks",
                "$(unlocks_prefix) $(unlock_text)";
                position = Math.Vector2(px + 12, py + 88),
                fontSize = 13,
                color = (200, 200, 140, 255),
                fontPath = "Century-Normal.ttf",
                layer = layer + 1,
            )
        end

        footer_y = py + CARD_HEIGHT - 28
        if is_complete
            DisplayTextModule.display_text(
                "$(card_id)_status",
                "✓ $(completed_label)";
                position = Math.Vector2(px + 12, footer_y),
                fontSize = 14,
                color = (120, 255, 120, 255),
                fontPath = "Century-Normal.ttf",
                layer = layer + 1,
            )
        elseif progress > 0.0
            bar_width = CARD_WIDTH - 24
            filled = round(Int, bar_width * clamp(progress, 0.0, 1.0))
            JulGame.ImmediateUIModule.immediate_rect(
                "$(card_id)_bar_bg";
                position = Math.Vector2(px + 12, footer_y + 4),
                size = Math.Vector2(bar_width, 10),
                color = (20, 20, 30, 200),
                borderRadius = 3,
                layer = layer + 1,
            )
            if filled > 0
                JulGame.ImmediateUIModule.immediate_rect(
                    "$(card_id)_bar_fill";
                    position = Math.Vector2(px + 12, footer_y + 4),
                    size = Math.Vector2(filled, 10),
                    color = (100, 160, 255, 255),
                    borderRadius = 3,
                    layer = layer + 2,
                )
            end
            pct = round(Int, progress * 100)
            DisplayTextModule.display_text(
                "$(card_id)_pct",
                "$(pct)%";
                position = Math.Vector2(px + bar_width - 8, footer_y - 2),
                fontSize = 12,
                color = (160, 180, 220, 255),
                fontPath = "Century-Normal.ttf",
                layer = layer + 2,
            )
        end

        return card_bg
    end
end
