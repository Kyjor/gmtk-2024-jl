module InputHandlerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using ..Scripts 
    include("utils/PieceTooltipCard.jl")
    using .PieceTooltipCardModule

    mutable struct InputHandler
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        
        # entities 
        crosshair
        selected_entity
        
        #scripts
        gameManager
        gridController
        battleManager
        moveIndicatorManager
        mousePosText

        switchSound
        user

        cursor_highlighted
        cursor
        cursor_enemy_target
        battlePotionManager
        queueManager
        switchPreviewTooltipManager
        switchPreviewTooltipText
        switchPreviewRows
        pieceTooltipCard::PieceTooltipCardModule.PieceTooltipCard

        # Cached swappable cells for the current selection (avoids per-frame recompute)
        cachedPossibleMoves::Vector{Math.Vector2f}
        lastAimGridX::Int
        lastAimGridY::Int
        selectionPulseTime::Float64
        selectionGlowEntity::Any
        hoverShakeEntity::Any
        hoverPulseTime::Float64

        function InputHandler()
            this = new() # do not remove this line

            this.selected_entity = nothing
            this.moveIndicatorManager = nothing
            this.cachedPossibleMoves = Math.Vector2f[]
            this.lastAimGridX = 0
            this.lastAimGridY = 0
            this.selectionPulseTime = 0.0
            this.selectionGlowEntity = nothing
            this.hoverShakeEntity = nothing
            this.hoverPulseTime = 0.0
            this.cursor_highlighted = JulGame.InputModule.set_cursor_with_image(JulGame.UserGlobals["Module"].get_asset_path("cursor", "activering"), 83, 81, 0.5)
            this.cursor = JulGame.InputModule.set_cursor_with_image(JulGame.UserGlobals["Module"].get_asset_path("cursor", "inactivering"), 83, 81, 0.5)
            # Slightly larger ring reads as “target enemy” vs grid highlight (same art; tweak scale).
            this.cursor_enemy_target = JulGame.InputModule.set_cursor_with_image(JulGame.UserGlobals["Module"].get_asset_path("cursor", "activering"), 83, 81, 0.62)
        this.switchPreviewTooltipManager = nothing
        this.switchPreviewTooltipText = ""
        this.switchPreviewRows = []
        this.pieceTooltipCard = PieceTooltipCardModule.PieceTooltipCard()

        return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # This is where you should register collision events or other events
    # Do not remove this function
    function JulGame.initialize(this::InputHandler)
        this.crosshair = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "38f77eee-c2e5-4b7e-b471-e47bc3e65981")
        # Behind board pieces (layer 2) so the + doesn't cover the selected gem.
        if this.crosshair !== nothing && this.crosshair.sprite !== nothing
            this.crosshair.sprite.layer = 1
        end
        this.switchSound = JulGame.SceneModule.get_entity_by_id(MAIN.scene, "4f27bb49-990a-4809-93a7-c857230a6371").soundSource
        this.battlePotionManager = this.parent.scripts[9]
        this.queueManager = this.parent.scripts[6]
        
        this.gameManager = this.parent.scripts[1]
        this.gridController = this.parent.scripts[3]
        this.battleManager = this.parent.scripts[4]
        this.moveIndicatorManager = this.parent.scripts[14]
        if this.gameManager !== nothing
            this.switchPreviewTooltipManager = this.gameManager.tooltipManager
        end
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()

    end

    """Treasure detonator / nail modes draw their own targets; avoid piece-selection cursor and switch UI fighting them."""
    function ability_blocks_standard_grid_cursor(this::InputHandler)::Bool
        s = this.parent.scripts[17]
        s isa Scripts.AbilityManagerModule.AbilityManager || return false
        return s.isDetonatorSelectionMode || s.isNailSelectionMode
    end

    # This is called every frame
    function JulGame.update(this::InputHandler, deltaTime)
        tutorialBlocks = Scripts.TutorialModule.blocks_board_input()
        isStandardPlayerTurn = this.battleManager.currentState == this.battleManager.battleStates[:playerTurn] && !this.gameManager.pauseMenu.paused && !this.battlePotionManager.isBombSelectionMode && !ability_blocks_standard_grid_cursor(this) && !tutorialBlocks
        if isStandardPlayerTurn
            handle_crosshair(this, deltaTime)
            draw_switch_preview_immediate!(this)
            apply_enemy_target_hover_ui!(this)
        elseif this.battleManager.currentState == this.battleManager.battleStates[:playerTurn] && !this.gameManager.pauseMenu.paused && !this.battlePotionManager.isBombSelectionMode && ability_blocks_standard_grid_cursor(this) && !tutorialBlocks
            handle_crosshair_movement_only(this, deltaTime)
            hide_enemy_target_preview!(this)
            clear_switch_preview_tooltip!(this)
        elseif is_match_resolution_state(this) && !this.gameManager.pauseMenu.paused
            handle_crosshair_movement_only(this, deltaTime)
            hide_enemy_target_preview!(this)
            clear_switch_preview_tooltip!(this)
        else
            hide_enemy_target_preview!(this)
            clear_switch_preview_tooltip!(this)
        end
        update_piece_tooltip_card!(this, deltaTime, isStandardPlayerTurn)
        update_board_piece_feedback!(this, deltaTime, isStandardPlayerTurn)
    end

    # World units (~4px at 150 ppu) — same feel as ButtonJuice's hover shake.
    const HOVER_WOBBLE_AMOUNT = 0.03
    const HOVER_WOBBLE_DURATION = 0.25

    const SELECTION_GLOW = Any[
        JulGame.EffectsModule.OuterGlowEffect(
            radius = 12,
            color = (255, 236, 170, 220),
            fade_amount = 1.6,
            fade_curve = 14.0,
            force_white = true,
        ),
    ]

    function _set_piece_glow!(entity, on::Bool)
        entity === nothing && return
        spr = try entity.sprite catch; nothing end
        spr === nothing && return
        try
            if on
                JulGame.apply_effects!(spr, SELECTION_GLOW)
            end
            if hasproperty(spr, :useEffectTexture)
                spr.useEffectTexture = on
            end
        catch e
            @debug "selection glow: $e"
        end
    end

    function _set_render_scale!(entity, s::Float64)
        try
            entity.sprite.renderScale = Math.Vector2f(s, s)
        catch
        end
    end

    function _clear_selection_feedback!(this::InputHandler)
        ent = this.selectionGlowEntity
        this.selectionGlowEntity = nothing
        this.selectionPulseTime = 0.0
        ent === nothing && return
        _set_piece_glow!(ent, false)
        _set_render_scale!(ent, 1.0)
    end

    function hovered_board_piece(this::InputHandler)
        is_mouse_in_grid(this) || return nothing
        grid_position = convert_world_position_to_grid_position(this, MAIN.input.mousePositionWorld)
        x = convert(Int64, grid_position.x)
        y = convert(Int64, grid_position.y)
        if x < 1 || x > this.gridController.gridWidth || y < 1 || y > this.gridController.gridHeight
            return nothing
        end
        return this.gridController.gridPieces[x, y]
    end

    """Hover juice matching UI buttons: a decaying wobble on enter, then a gentle scale pulse."""
    function _set_hover_piece!(this::InputHandler, hovered)
        hovered === this.hoverShakeEntity && return
        prev = this.hoverShakeEntity
        if prev !== nothing
            # The wobble writes absolute positions; a piece that starts swapping/falling must not be pulled back.
            Scripts.BattleManagerModule.BattleJuiceModule.cancel_shake!(prev)
            prev !== this.selectionGlowEntity && _set_render_scale!(prev, 1.0)
        end
        this.hoverShakeEntity = hovered
        this.hoverPulseTime = 0.0
        hovered === nothing && return
        try
            Scripts.BattleManagerModule.BattleJuiceModule.shake!(hovered; intensity = HOVER_WOBBLE_AMOUNT, duration = HOVER_WOBBLE_DURATION, wobble = true)
        catch e
            @debug "hover shake: $e"
        end
    end

    """Pulse the selected piece, and give a short shake to whichever piece the cursor enters."""
    function update_board_piece_feedback!(this::InputHandler, deltaTime, allowHover::Bool)
        selected = this.selected_entity
        if selected !== this.selectionGlowEntity
            _clear_selection_feedback!(this)
            if selected !== nothing
                this.selectionGlowEntity = selected
                _set_piece_glow!(selected, true)
            end
        end
        if this.selectionGlowEntity !== nothing
            this.selectionPulseTime += Float64(deltaTime)
            _set_render_scale!(this.selectionGlowEntity, 1.0 + 0.07 * sin(this.selectionPulseTime * 5.5))
        end

        hovered = allowHover ? hovered_board_piece(this) : nothing
        if hovered === this.selected_entity
            hovered = nothing
        end
        _set_hover_piece!(this, hovered)
        if hovered !== nothing
            this.hoverPulseTime += Float64(deltaTime)
            _set_render_scale!(hovered, Scripts.ButtonJuiceModule.hover_pulse_scale(this.hoverPulseTime))
        end
    end

    """
    Piece card (bottom-left, under the player). Shows match 3/4/5 values via the
    same preview pipeline as the swap tooltip. A Hocus Pocus drag takes priority
    (shows the held queue piece), then the selected piece while choosing a swap
    target, then the hovered board piece. The card stays left of the board and fades
    out while the mouse is on the character side (a pinned selection fades back in
    when the mouse returns to the board).
    """
    function update_piece_tooltip_card!(this::InputHandler, deltaTime, allowHover::Bool)
        card = this.pieceTooltipCard
        key = if !allowHover
            nothing
        elseif dragged_queue_piece_key(this) !== nothing
            dragged_queue_piece_key(this)
        elseif is_mouse_on_character_side(this)
            nothing
        elseif this.selected_entity !== nothing
            this.selected_entity.name
        else
            hovered_piece_key(this)
        end
        if key === nothing
            PieceTooltipCardModule.hide!(card)
        elseif !card.visible || card.content === nothing || card.content.key != key
            content = build_piece_card_content(this, key)
            content === nothing ? PieceTooltipCardModule.hide!(card) : PieceTooltipCardModule.show!(card, content)
        end
        boardLeft, _ = Scripts.ComboStarsModule.world_to_screen(Float64(this.gridController.gridStartX), Float64(this.gridController.gridStartY))
        current = key === nothing ? nothing : aimed_card_tier(this, key)
        PieceTooltipCardModule.draw!(card, deltaTime; max_right = boardLeft, current = current)
    end

    """Card tier for the match `key` would make with the move being aimed (swap target, Hocus Pocus drop or Eye Dropper), or nothing."""
    function aimed_card_tier(this::InputHandler, key::String)::Union{Nothing, PieceTooltipCardModule.CardTier}
        if this.battlePotionManager.isEyeDropperSelectionMode
            # Eye Dropper clears every `key` on the board as one bomb-style match: action count = pieces cleared.
            n = count(p -> p !== nothing && p.name == key, this.gridController.gridPieces)
            n > 0 || return nothing
            return _card_tier(this, key, n, "Eye Dropper ($n)")
        end
        matches = dragged_queue_piece_key(this) == key ? hocus_drop_preview_matches(this, key) : this.switchPreviewRows
        counts = [m.action_count for m in matches if m.piece_key == key]
        isempty(counts) && return nothing
        action_count = maximum(counts)
        return _card_tier(this, key, action_count, "Match $(this.gridController.matchThreshold + action_count - 1)")
    end

    function _card_tier(this::InputHandler, key::String, action_count::Int, label::String)
        lines = Scripts.GridControllerModule.get_preview_intent_lines(this.gridController, key, action_count)
        return PieceTooltipCardModule.CardTier(label, PieceTooltipCardModule.tier_text(lines))
    end

    function hocus_drop_preview_matches(this::InputHandler, key::String)
        globals = JulGame.UserGlobals["Module"]
        globals.UserModule.has_treasure(globals.TreasuresModule.TREASURE_HOCUSPOCUS) || return []
        cell = hovered_grid_cell(this)
        cell === nothing && return []
        x, y = cell
        existing = this.gridController.gridPieces[x, y]
        if existing !== nothing && (existing.name == key || Scripts.AbilityManagerModule.is_piece_nailed(existing))
            return []
        end
        return Scripts.GridControllerModule.get_drop_preview_matches(this.gridController, key, x, y)
    end

    is_mouse_on_character_side(this::InputHandler)::Bool =
        MAIN.input.mousePositionWorld.x < this.gridController.gridStartX

    function dragged_queue_piece_key(this::InputHandler)::Union{Nothing, String}
        qm = this.queueManager
        qm === nothing && return nothing
        if qm.dragging_piece && qm.dragged_piece_data !== nothing
            return qm.dragged_piece_data.key
        end
        return nothing
    end

    function hovered_grid_cell(this::InputHandler)::Union{Nothing, Tuple{Int64, Int64}}
        is_mouse_in_grid(this) || return nothing
        grid_position = convert_world_position_to_grid_position(this, MAIN.input.mousePositionWorld)
        x = convert(Int64, grid_position.x)
        y = convert(Int64, grid_position.y)
        if x < 1 || x > this.gridController.gridWidth || y < 1 || y > this.gridController.gridHeight
            return nothing
        end
        return (x, y)
    end

    function hovered_piece_key(this::InputHandler)::Union{Nothing, String}
        cell = hovered_grid_cell(this)
        cell === nothing && return nothing
        piece = this.gridController.gridPieces[cell...]
        piece === nothing && return nothing
        return piece.name # entity name is the piece key, e.g. "PIECE_SWORD"
    end

    function build_piece_card_content(this::InputHandler, key::String)::Union{Nothing, PieceTooltipCardModule.CardContent}
        globals = JulGame.UserGlobals["Module"]
        piece_map = globals.get_piece_data()
        haskey(piece_map, key) || return nothing
        piece = piece_map[key]

        weight_text = ""
        pool = [p for p in this.user.pieces if p !== nothing]
        owned = findfirst(p -> string(p.key) == key, pool)
        # Cursed skulls sit on the board without being in the bag. Weight is only the bag share.
        if owned !== nothing
            rarity = Float64(pool[owned].weight)
            total_rarity = sum(Float64(p.weight) for p in pool)
            if total_rarity > 0
                weight_text = "Weight: $(round(rarity / total_rarity * 100, digits = 1))%"
            end
        end

        icon_path = globals.get_asset_path("piece", lowercase(split(key, "_")[2]))
        raw_desc = piece.description
        description = raw_desc === nothing ? "" : String(raw_desc)
        threshold = this.gridController.matchThreshold
        tiers = PieceTooltipCardModule.CardTier[]
        for n in 1:3
            lines = Scripts.GridControllerModule.get_preview_intent_lines(this.gridController, key, n)
            push!(tiers, PieceTooltipCardModule.CardTier(
                "Match $(threshold + n - 1)",
                PieceTooltipCardModule.tier_text(lines),
            ))
        end
        return PieceTooltipCardModule.CardContent(key, piece.name, weight_text, description, icon_path, tiers)
    end

    function hide_enemy_target_preview!(this::InputHandler)
        prev = this.battleManager.selectEnemyPreview
        if prev !== nothing
            prev.isActive = false
        end
        hide_aoe_match_hearts!(this.battleManager)
    end

    function hide_aoe_match_hearts!(bm)
        hearts = bm.selectEnemyAoePreviews
        hearts === nothing && return
        for pv in hearts
            pv !== nothing && (pv.isActive = false)
        end
    end

    function ensure_aoe_match_heart!(bm, index::Int)
        hearts = bm.selectEnemyAoePreviews
        if hearts === nothing
            hearts = Any[]
            bm.selectEnemyAoePreviews = hearts
        end
        try
            while length(hearts) < index
                indicator = bm.selectEnemyIndicator
                indicator === nothing && return nothing
                pv = JulGame.duplicate(indicator)
                pv.name = "SelectionHeartAoe$(length(hearts) + 1)"
                pv.isActive = false
                if pv.sprite !== nothing
                    pv.sprite.color = (255, 255, 255, 255)
                    if indicator.sprite !== nothing
                        pv.sprite.layer = indicator.sprite.layer
                    end
                end
                push!(hearts, pv)
            end
        catch e
            @debug "Could not create AOE selection heart: $(e)"
            return nothing
        end
        return hearts[index]
    end

    function piece_match_affects_all_enemies(piece_key::String)::Bool
        globals = JulGame.UserGlobals["Module"]
        pieces = globals.get_piece_data()
        haskey(pieces, piece_key) || return false
        return globals.PiecesModule.is_aoe(pieces[piece_key])
    end

    function aimed_move_affects_all_enemies(this::InputHandler)::Bool
        for row in this.switchPreviewRows
            piece_match_affects_all_enemies(string(row.piece_key)) && return true
        end
        dragged = dragged_queue_piece_key(this)
        dragged === nothing && return false
        for match in hocus_drop_preview_matches(this, dragged)
            piece_match_affects_all_enemies(string(match.piece_key)) && return true
        end
        return false
    end

    """Selection hearts on every living enemy while the aimed swap or drop would hit all of them."""
    function show_aoe_match_hearts!(this::InputHandler)::Bool
        bm = this.battleManager
        if !aimed_move_affects_all_enemies(this)
            hide_aoe_match_hearts!(bm)
            return false
        end
        bob = Scripts.BattleManagerModule.selection_heart_bob_y(bm)
        index = 1
        any_living = false
        for enemy in bm.enemies
            es = enemy.scripts[1]
            if es.health <= 0 || es.healthHeart === nothing
                continue
            end
            any_living = true
            if es === bm.selectedEnemy && bm.selectEnemyIndicator !== nothing && bm.selectEnemyIndicator.isActive
                continue
            end
            pv = ensure_aoe_match_heart!(bm, index)
            pv === nothing && break
            p = es.healthHeart.transform.position
            pv.transform.position = Math.Vector3f(p.x, p.y + bob, p.z)
            pv.isActive = true
            if pv.sprite !== nothing
                pv.sprite.color = (255, 255, 255, 255)
            end
            index += 1
        end
        hearts = bm.selectEnemyAoePreviews
        if hearts !== nothing
            for i in index:length(hearts)
                hearts[i] !== nothing && (hearts[i].isActive = false)
            end
        end
        return any_living
    end

    function clear_switch_preview_tooltip!(this::InputHandler)
        this.switchPreviewTooltipText = ""
        this.switchPreviewRows = []
    end

    function build_switch_preview_text(rows)::String
        lines = String[]
        for row in rows
            push!(lines, "$(row.value_label): $(row.value)  (x$(row.action_count))")
        end
        return join(lines, "\n")
    end

    function _mouse_snapped_grid_origin_world(this::InputHandler)::Math.Vector2f
        mousePos = MAIN.input.mousePositionWorld
        localX = (mousePos.x - this.gridController.gridStartX) / this.gridController.gridCellWidth
        localY = (mousePos.y - this.gridController.gridStartY) / this.gridController.gridCellHeight
        xIdx = clamp(convert(Int64, floor(localX)) + 1, 1, this.gridController.gridWidth)
        yIdx = clamp(convert(Int64, floor(localY)) + 1, 1, this.gridController.gridHeight)
        return Math.Vector2f(
            (xIdx - 1) * this.gridController.gridCellWidth + this.gridController.gridStartX,
            (yIdx - 1) * this.gridController.gridCellHeight + this.gridController.gridStartY,
        )
    end

    function swap_preview_target_world(this::InputHandler)
        if this.selected_entity === nothing
            return nothing
        end
        # Cell-based aim: mouse snap when over grid, otherwise crosshair.
        if is_mouse_in_grid(this)
            return _mouse_snapped_grid_origin_world(this)
        end
        return this.crosshair.transform.position
    end

    """
    World position used for non-mouse confirm (SPACE / gamepad): aimed cell is
    wherever the crosshair sits (moved freely while a piece is selected).
    """
    function grid_action_target_world(this::InputHandler)
        return this.crosshair.transform.position
    end

    function is_board_confirm_pressed(this::InputHandler)::Bool
        mouseConfirm = JulGame.InputModule.get_mouse_button_pressed(1) && is_mouse_in_grid(this)
        return mouseConfirm
    end

    function hide_move_indicators!(this::InputHandler)
        mim = this.moveIndicatorManager
        mim === nothing && return
        Scripts.MoveIndicatorManagerModule.hide_all_indicators(mim)
    end

    function clear_move_cache!(this::InputHandler)
        empty!(this.cachedPossibleMoves)
        this.lastAimGridX = 0
        this.lastAimGridY = 0
    end

    function clear_selection_ui!(this::InputHandler)
        this.selected_entity = nothing
        clear_switch_preview_tooltip!(this)
        hide_move_indicators!(this)
        clear_move_cache!(this)
    end

    function show_moves_for_selection!(this::InputHandler)
        mim = this.moveIndicatorManager
        mim === nothing && return
        this.cachedPossibleMoves = compute_possible_movement(this)
        Scripts.MoveIndicatorManagerModule.show_available_moves(mim, this.cachedPossibleMoves)
        this.lastAimGridX = 0
        this.lastAimGridY = 0
    end

    function update_aim_highlight!(this::InputHandler, worldPos::Math.Vector2f)
        globals = JulGame.UserGlobals["Module"]
        mim = this.moveIndicatorManager
        mim === nothing && return
        gp = convert_world_position_to_grid_position(this, worldPos)
        ax = Int(gp.x)
        ay = Int(gp.y)
        if ax == this.lastAimGridX && ay == this.lastAimGridY
            return
        end
        this.lastAimGridX = ax
        this.lastAimGridY = ay
        if Scripts.MoveIndicatorManagerModule.is_valid_move_target(mim, gp)
            Scripts.MoveIndicatorManagerModule.highlight_move(mim, gp)
        else
            Scripts.MoveIndicatorManagerModule.clear_highlight(mim)
        end
    end

    """Quiet ownership check — `UserModule.has_treasure` notifies observers (UI flash)."""
    function player_owns_treasure(key::String)::Bool
        globals = JulGame.UserGlobals["Module"]
        treasures = globals.get_data_manager().user_data.treasures
        treasures === nothing && return false
        for treasure in treasures
            if treasure.key == key
                return true
            end
        end
        return false
    end

    function draw_switch_preview_immediate!(this::InputHandler)
        if isempty(this.switchPreviewRows)
            return
        end
        tm = this.switchPreviewTooltipManager
        if tm === nothing && this.gameManager !== nothing && isdefined(this.gameManager, :tooltipManager)
            this.switchPreviewTooltipManager = this.gameManager.tooltipManager
            tm = this.switchPreviewTooltipManager
        end
        tm === nothing && return

        mouse_position = MAIN.input.mousePosition
        lines = String[]
        for row in this.switchPreviewRows
            push!(lines, "$(row.value_label): $(row.value)  (x$(row.action_count))")
        end
        font_size = tm.fontSize
        icon_col_w = 26
        max_line_width = 0
        for line in lines
            max_line_width = max(max_line_width, length(line) * (font_size ÷ 1.5))
        end
        tooltip_width = max(min(max_line_width, tm.maxWidth) + 2 * tm.padding + icon_col_w, 100)
        line_h = font_size + 6
        tooltip_height = length(lines) * line_h + 2 * tm.padding
        window_size = JulGame.WindowManagerModule.get_logical_size()
        tooltip_x = mouse_position.x + 15
        tooltip_y = mouse_position.y
        if tooltip_x + tooltip_width > window_size.x
            tooltip_x = mouse_position.x - tooltip_width - 10
        end
        if tooltip_x < 0
            tooltip_x = 5
        end
        if tooltip_x + tooltip_width > window_size.x
            tooltip_x = window_size.x - tooltip_width - 5
        end
        if mouse_position.y + tooltip_height > window_size.y
            tooltip_y = mouse_position.y - tooltip_height - 10
        end
        if tooltip_y < 0
            tooltip_y = 5
        end
        if tooltip_y + tooltip_height > window_size.y
            tooltip_y = window_size.y - tooltip_height - 5
        end

        Scripts.NineSliceUIModule.immediate_panel(
            "switch_preview_bg";
            position = Math.Vector2(tooltip_x, tooltip_y),
            size = Math.Vector2(tooltip_width, tooltip_height),
            color = tm.bgColor,
            border_color = tm.borderColor,
            layer = 999,
        )

        globals = JulGame.UserGlobals["Module"]
        for (i, row) in enumerate(this.switchPreviewRows)
            line = lines[i]
            base_y = tooltip_y + tm.padding + (i - 1) * line_h
            piece_name = lowercase(split(string(row.piece_key), "_")[2])
            image_name = globals.get_asset_path("piece", piece_name)
            icon_size = 20
            icon_y = base_y + (line_h - icon_size) ÷ 2
            JulGame.ImmediateUIModule.immediate_image(
                "switch_preview_icon_$(i)",
                image_name;
                position = Math.Vector2(tooltip_x + tm.padding + 3, icon_y),
                size = Math.Vector2(icon_size, icon_size),
                layer = 1002,
            )
            DisplayTextModule.display_text(
                "switch_preview_line_$(i)",
                line;
                position = Math.Vector2(tooltip_x + tm.padding + icon_col_w, base_y),
                fontSize = font_size,
                color = tm.textColor,
                layer = 1001,
            )
        end
    end

    function update_switch_preview_tooltip!(this::InputHandler, target_position)
        if this.selected_entity === nothing
            clear_switch_preview_tooltip!(this)
            return
        end
        if this.switchPreviewTooltipManager === nothing && this.gameManager !== nothing && isdefined(this.gameManager, :tooltipManager)
            this.switchPreviewTooltipManager = this.gameManager.tooltipManager
        end
        tm = this.switchPreviewTooltipManager
        if tm === nothing || !can_switch(this, target_position)
            clear_switch_preview_tooltip!(this)
            return
        end
        target_grid_pos = convert_world_position_to_grid_position(this, target_position)
        tx = convert(Int64, target_grid_pos.x)
        ty = convert(Int64, target_grid_pos.y)
        if tx < 1 || tx > this.gridController.gridWidth || ty < 1 || ty > this.gridController.gridHeight
            clear_switch_preview_tooltip!(this)
            return
        end
        target_piece = this.gridController.gridPieces[tx, ty]
        if target_piece === nothing || target_piece === this.selected_entity
            clear_switch_preview_tooltip!(this)
            return
        end
        if Scripts.AbilityManagerModule.is_piece_nailed(this.selected_entity) || Scripts.AbilityManagerModule.is_piece_nailed(target_piece)
            clear_switch_preview_tooltip!(this)
            return
        end

        preview_matches = Scripts.GridControllerModule.get_swap_preview_matches(this.gridController, this.selected_entity, target_piece)
        if isempty(preview_matches)
            clear_switch_preview_tooltip!(this)
            return
        end

        rows = []
        pattern_hints = String[]
        for match in preview_matches
            if hasproperty(match, :pattern_label) && !isempty(match.pattern_label)
                push!(pattern_hints, "CREATE $(match.pattern_label)")
            end
            for line in Scripts.GridControllerModule.get_preview_intent_lines(this.gridController, match.piece_key, match.action_count)
                push!(rows, (
                    piece_key = match.piece_key,
                    value = line.value,
                    value_label = line.value_label,
                    action_count = match.action_count,
                ))
            end
        end

        tooltip_text = build_switch_preview_text(rows)
        if !isempty(pattern_hints)
            tooltip_text = join(unique(pattern_hints), " · ") * "\n" * tooltip_text
        end
        this.switchPreviewTooltipText = tooltip_text
        this.switchPreviewRows = rows
    end

    """
    After grid cursor logic: show dim SelectionHeart clone and enemy-target cursor when hovering
    a living enemy's health heart (only if that enemy is not already the selected target).
    """
    function apply_enemy_target_hover_ui!(this::InputHandler)
        bm = this.battleManager
        prev = bm.selectEnemyPreview
        if bm.currentState != bm.battleStates[:playerTurn] ||
           this.gameManager.pauseMenu.paused ||
           this.battlePotionManager.isBombSelectionMode ||
           ability_blocks_standard_grid_cursor(this)
            hide_enemy_target_preview!(this)
            return
        end
        if show_aoe_match_hearts!(this)
            if prev !== nothing
                prev.isActive = false
            end
            return
        end
        if prev === nothing
            return
        end
        hovered_script = nothing
        for eent in bm.enemies
            es = eent.scripts[1]
            if es.health <= 0 || es.healthHeart === nothing
                continue
            end
            if JulGame.Component.is_mouse_hovering(es.healthHeart.transform)
                hovered_script = es
                break
            end
        end
        if hovered_script !== nothing && hovered_script !== bm.selectedEnemy
            p = hovered_script.healthHeart.transform.position
            bob = Scripts.BattleManagerModule.selection_heart_bob_y(bm)
            prev.transform.position = Math.Vector3f(p.x, p.y + bob, p.z)
            prev.isActive = true
            if prev.sprite !== nothing
                prev.sprite.color = (255, 255, 255, 105)
            end
            JulGame.InputModule.set_cursor(this.cursor_enemy_target)
        else
            prev.isActive = false
        end
    end

    # This is called when the script is removed from an entity (scene change, entity deletion)
    # Do not remove this function
    function JulGame.on_shutdown(this::InputHandler)
        clear_selection_ui!(this)
    end 

    """Match-resolution crosshair tint: darker when aim isn't a legal swap."""
    const CROSSHAIR_VALID_COLOR = (255, 255, 255, 255)
    const CROSSHAIR_INVALID_COLOR = (128, 128, 128, 255)

    function update_crosshair_aim_tint!(this::InputHandler)
        if this.selected_entity === nothing
            this.crosshair.sprite.color = CROSSHAIR_VALID_COLOR
            return
        end
        aim = swap_preview_target_world(this)
        if aim !== nothing && can_switch(this, aim)
            this.crosshair.sprite.color = CROSSHAIR_VALID_COLOR
        else
            this.crosshair.sprite.color = CROSSHAIR_INVALID_COLOR
        end
    end

    function handle_crosshair(this::InputHandler, deltaTime)
        crosshairPos = this.crosshair.transform.position
        mousePos = MAIN.input.mousePositionWorld
        globals = JulGame.UserGlobals["Module"]

        if JulGame.InputModule.get_mouse_button_pressed(1) && !is_mouse_in_grid(this)
            clear_selection_ui!(this)
            update_crosshair_aim_tint!(this)
            return
        end

        mouseConfirm = JulGame.InputModule.get_mouse_button_pressed(1) && is_mouse_in_grid(this)
        if is_board_confirm_pressed(this)
            if this.battleManager.moveCount < 1
                clear_selection_ui!(this)
                update_crosshair_aim_tint!(this)
                return
            end
            actionPos = mouseConfirm ? mousePos : grid_action_target_world(this)

            @debug "crosshairPos: $(crosshairPos)"
            @debug "mousePos: $(mousePos)"
            @debug "actionPos: $(actionPos)"
        
            if this.selected_entity !== nothing
                clicked_same = actionPos == selected_cell_world(this) ||
                    (mouseConfirm && begin
                        sg = selected_grid_position(this)
                        ag = convert_world_position_to_grid_position(this, actionPos)
                        Int(sg.x) == Int(ag.x) && Int(sg.y) == Int(ag.y)
                    end)
                clicked_outside = mouseConfirm && click_in_grid_but_outside_of_possible_movement(this, actionPos)

                if clicked_same || clicked_outside
                    this.crosshair.sprite.color = (255, 255, 255, 255)
                    JulGame.InputModule.set_cursor(this.cursor)
                    clear_selection_ui!(this)
                    globals.AudioManagerModule.play_audio_oneshot(
                        globals.get_audio_manager(),
                        globals.get_asset_path("sfx", "hoverbad"),
                        false, 0.5, 0, 1,
                    )
                elseif can_switch(this, actionPos)
                    target_grid_pos = convert_world_position_to_grid_position(this, actionPos)
                    target_piece = this.gridController.gridPieces[
                        convert(Int64, target_grid_pos.x),
                        convert(Int64, target_grid_pos.y)
                    ]

                    if Scripts.AbilityManagerModule.is_piece_nailed(this.selected_entity) ||
                       (target_piece !== nothing && Scripts.AbilityManagerModule.is_piece_nailed(target_piece))
                        DisplayTextModule.display_text(
                            "nail_switch_blocked",
                            "Cannot move nailed pieces!";
                            fontSize = 18,
                            anchor = :center,
                            lifetime = 1500,
                            color = (255, 100, 100, 255)
                        )
                        clear_selection_ui!(this)
                    elseif !Scripts.TutorialModule.allows_swap(this.selected_entity, target_piece)
                        clear_selection_ui!(this)
                        globals.AudioManagerModule.play_audio_oneshot(
                            globals.get_audio_manager(),
                            globals.get_asset_path("sfx", "hoverbad"),
                            false, 0.5, 0, 1,
                        )
                    else
                        Scripts.TutorialModule.note_swap!()
                        Scripts.GridControllerModule.set_grid_items_to_switch(
                            this.gridController,
                            this.selected_entity,
                            target_piece
                        )
                        this.crosshair.sprite.color = (255, 255, 255, 255)
                        JulGame.InputModule.set_cursor(this.cursor)
                        clear_selection_ui!(this)
                    end
                else
                    # Invalid confirm (e.g. digital on non-move cell) — cancel selection
                    clear_selection_ui!(this)
                end
            else
                JulGame.InputModule.set_cursor(this.cursor_highlighted)
                selectPos = mouseConfirm ? mousePos : crosshairPos
                grid_position = convert_world_position_to_grid_position(this, selectPos)
                x::Int64 = grid_position.x
                y::Int64 = grid_position.y
                if x < 1 || x > this.gridController.gridWidth || y < 1 || y > this.gridController.gridHeight
                    return
                end
                potential_selected_entity = this.gridController.gridPieces[x, y]
                if potential_selected_entity === nothing
                    return
                end
            
                # Check if the piece is nailed - if so, don't allow selection
                if Scripts.AbilityManagerModule.is_piece_nailed(potential_selected_entity)
                    @debug "Cannot select nailed piece: $(potential_selected_entity.name)"
                    return  # Don't select nailed pieces
                end
            
                this.selected_entity = potential_selected_entity
                @debug "selected_entity: $(this.selected_entity.name)"
                try
                    globals = JulGame.UserGlobals["Module"]
                    globals.AudioManagerModule.play_audio_oneshot(
                        globals.get_audio_manager(),
                        globals.get_asset_path("sfx", "selectpiece"),
                        false, 1.0, 0, 1,
                    )
                catch
                end
                piece_world_position = cell_world(this, x, y)
                this.crosshair.transform.position = piece_world_position
                show_moves_for_selection!(this)
                clear_switch_preview_tooltip!(this)
            end
        end

        # Mouse and digital (keyboard / gamepad) movement are independent so mouse
        # motion over the grid doesn't eat controller frames.
        if MAIN.input.didMouseMotionOccur && is_mouse_in_grid(this)
            localX = (mousePos.x - this.gridController.gridStartX) / this.gridController.gridCellWidth
		    localY = (mousePos.y - this.gridController.gridStartY) / this.gridController.gridCellHeight
            xIdx = convert(Int64, floor(localX)) + 1
            yIdx = convert(Int64, floor(localY)) + 1
            xIdx = clamp(xIdx, 1, this.gridController.gridWidth)
            yIdx = clamp(yIdx, 1, this.gridController.gridHeight)
            target_position = Math.Vector2f(
                (xIdx - 1) * this.gridController.gridCellWidth + this.gridController.gridStartX,
                (yIdx - 1) * this.gridController.gridCellHeight + this.gridController.gridStartY
            )

            if this.selected_entity === nothing 
                if target_position != crosshairPos && can_crosshair_move(this, target_position)
                    this.crosshair.transform.position = Math.Vector2f(target_position.x, target_position.y)
                end
                clear_switch_preview_tooltip!(this)
            elseif target_position != crosshairPos && can_crosshair_move(this, target_position)
                this.crosshair.transform.position = Math.Vector2f(target_position.x, target_position.y)
            end
        end

        if this.selected_entity !== nothing
            tw = swap_preview_target_world(this)
            if tw !== nothing
                gp = convert_world_position_to_grid_position(this, tw)
                ax = Int(gp.x)
                ay = Int(gp.y)
                aim_changed = ax != this.lastAimGridX || ay != this.lastAimGridY
                if aim_changed
                    update_aim_highlight!(this, tw)
                    update_switch_preview_tooltip!(this, tw)
                end
            else
                clear_switch_preview_tooltip!(this)
            end
        end

        update_crosshair_aim_tint!(this)
    end    

    function convert_world_position_to_grid_position(this, world_position)
        localX = (world_position.x - this.gridController.gridStartX) / this.gridController.gridCellWidth
        localY = (world_position.y - this.gridController.gridStartY) / this.gridController.gridCellHeight
        xIdx = convert(Int64, floor(localX)) + 1
        yIdx = convert(Int64, floor(localY)) + 1
        return Math.Vector2f(xIdx, yIdx)
    end

    """Rounds (not floors) so hover-shake / pulse offsets on the piece can't shift it a cell."""
    function selected_grid_position(this::InputHandler)
        return Scripts.GridControllerModule.convert_world_position_to_grid_position(this.gridController, this.selected_entity.transform.position)
    end

    function cell_world(this::InputHandler, x, y)::Math.Vector2f
        gc = this.gridController
        return Math.Vector2f(
            Scripts.GridControllerModule.calculate_placement_x(gc, x),
            Scripts.GridControllerModule.calculate_placement_y(gc, y),
        )
    end

    function selected_cell_world(this::InputHandler)::Math.Vector2f
        g = selected_grid_position(this)
        return cell_world(this, g.x, g.y)
    end

    function can_crosshair_move(this::InputHandler, target_position::Math.Vector2f)
        grid_position = convert_world_position_to_grid_position(this, target_position)
        if grid_position.x < 1 || grid_position.x > this.gridController.gridWidth || grid_position.y < 1 || grid_position.y > this.gridController.gridHeight
            return false
        end
        return true
    end

    function calculate_possible_movement(this::InputHandler)::Vector{Math.Vector2f}
        return this.cachedPossibleMoves
    end

    function compute_possible_movement(this::InputHandler)::Vector{Math.Vector2f}
        if this.selected_entity === nothing
            return Math.Vector2f[]
        end
        if Scripts.AbilityManagerModule.is_piece_nailed(this.selected_entity)
            return Math.Vector2f[]
        end

        grid_position = selected_grid_position(this)
        origin = (Int(grid_position.x), Int(grid_position.y))
        gridW = Int(this.gridController.gridWidth)
        gridH = Int(this.gridController.gridHeight)

        has_black_pawn = player_owns_treasure(JulGame.UserGlobals["Module"].TreasuresModule.TREASURE_BLACKPAWN)
        has_white_bishop = player_owns_treasure(JulGame.UserGlobals["Module"].TreasuresModule.TREASURE_WHITEBISHOP)

        cells = Scripts.MovementRulesModule.swappable_cells(
            origin,
            this.gridController.gridPieces,
            gridW,
            gridH,
            has_black_pawn,
            has_white_bishop,
        )

        result = Vector{Math.Vector2f}()
        for cell in cells
            piece = this.gridController.gridPieces[Int(cell.x), Int(cell.y)]
            if piece !== nothing && !Scripts.AbilityManagerModule.is_piece_nailed(piece)
                push!(result, cell)
            end
        end
        return result
    end

    function click_in_grid_but_outside_of_possible_movement(this::InputHandler, mousePos)
        grid_pos = convert_world_position_to_grid_position(this, mousePos)
        for movement in calculate_possible_movement(this)
            if movement == grid_pos
                return false
            end
        end
        @debug "click_in_grid_but_outside_of_possible_movement $(mousePos) grid=$(grid_pos)"
        return true
    end

    function can_switch(this::InputHandler, target_position)
        grid_position = convert_world_position_to_grid_position(this, target_position)
        if grid_position.x < 1 || grid_position.x > this.gridController.gridWidth ||
           grid_position.y < 1 || grid_position.y > this.gridController.gridHeight
            @debug "target_position is outside the grid: $(target_position)"
            return false
        end

        selected_entity_grid_position = selected_grid_position(this)
        if selected_entity_grid_position.x == grid_position.x && selected_entity_grid_position.y == grid_position.y
            @debug "target_position is the same as the selected_entity"
            return false
        end

        possible_movements = calculate_possible_movement(this)
        @debug "possible_movements: $(possible_movements)"
        @debug "grid_position: $(grid_position)"
        for movement in possible_movements
            if movement == grid_position
                return true
            end
        end
        return false
    end

    function is_mouse_in_grid(this)
        mousePos = MAIN.input.mousePositionWorld
        # need to update to work with the new grid

        return this.gridController.gridStartX <= mousePos.x <= this.gridController.gridStartX + this.gridController.gridWidth * this.gridController.gridCellWidth && this.gridController.gridStartY <= mousePos.y <= this.gridController.gridStartY + this.gridController.gridHeight * this.gridController.gridCellHeight
    end

    function is_match_resolution_state(this::InputHandler)
        return this.battleManager.currentState == this.battleManager.battleStates[:switchingItems] ||
               this.battleManager.currentState == this.battleManager.battleStates[:searchingForMatches] ||
               this.battleManager.currentState == this.battleManager.battleStates[:replaceItems] ||
               this.battleManager.currentState == this.battleManager.battleStates[:processTurn] ||
               this.battleManager.currentState == this.battleManager.battleStates[:animatingIntents]
    end

    function handle_crosshair_movement_only(this::InputHandler, deltaTime)
        crosshairPos = this.crosshair.transform.position
        mousePos = MAIN.input.mousePositionWorld
        
        # Same dim tint as invalid aim while a piece is selected
        this.crosshair.sprite.color = CROSSHAIR_INVALID_COLOR
        
        # Ensure no selection is active
        clear_selection_ui!(this)
        
        if MAIN.input.didMouseMotionOccur && is_mouse_in_grid(this)
            localX = (mousePos.x - this.gridController.gridStartX) / this.gridController.gridCellWidth
            localY = (mousePos.y - this.gridController.gridStartY) / this.gridController.gridCellHeight
            xIdx = convert(Int64, floor(localX)) + 1
            yIdx = convert(Int64, floor(localY)) + 1
            xIdx = clamp(xIdx, 1, this.gridController.gridWidth)
            yIdx = clamp(yIdx, 1, this.gridController.gridHeight)
            target_position = Math.Vector2f(
                (xIdx - 1) * this.gridController.gridCellWidth + this.gridController.gridStartX,
                (yIdx - 1) * this.gridController.gridCellHeight + this.gridController.gridStartY
            )

            if target_position != crosshairPos && can_crosshair_move(this, target_position)
                this.crosshair.transform.position = Math.Vector2f(target_position.x, target_position.y)
            end
        end
    end
end
