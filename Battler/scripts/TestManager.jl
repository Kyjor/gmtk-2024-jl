module TestManagerModule
    using JulGame
    using JulGame.SceneManagement.SceneBuilderModule
    using ..Scripts

    const GM_ENTITY_ID = "7a8aa3ba-17c8-4346-a606-361c29fbfeba"
    const MAP_ENTITY_ID = "ccb08b1f-35ba-4372-aa65-232d702a1e05"
    const SHOP_ENTITY_ID = "58ca72a3-0f2d-4b7d-9a7c-8b998e48c615"
    const EVENT_ENTITY_ID = "094a004a-7ce3-4497-8b8b-038b8ae84a25"

    const MOVE_COOLDOWN_SEC = 1.0
    const TUTORIAL_STEP_COOLDOWN_SEC = 0.4
    const SCENE_ACTION_COOLDOWN_SEC = 0.5
    const TEST_RUN_TIMEOUT_SEC = 600.0
    # Max of the settings slider (0.5x-3.0x); fast mode is forced on via TEST_MODE in MainSettings.
    const TEST_GAME_SPEED = 3.0
    const TARGET_RUNS = 2

    # Potions with a battle effect in PotionEffectsModule.execute_potion_effect; cycled so each one runs.
    const BATTLE_POTION_KEYS = (
        "POTION_BASICBATTERY",
        "POTION_BOMB",
        "POTION_EYEDROPPER",
        "POTION_ACTIVEBATTERY",
        "POTION_DICE",
        "POTION_GIGABOMB",
        "POTION_DEVILTEARS",
        "POTION_MEGABOMB",
        "POTION_ANGELTEARS",
        "POTION_HERBALTEA",
    )
    # Active treasures routed through AbilityManagerModule.activate_ability (Hocus Pocus is drag-driven).
    const ABILITY_TREASURE_KEYS = (
        "TREASURE_DETONATOR",
        "TREASURE_NAIL",
        "TREASURE_CHESSBOARD",
        "TREASURE_SEALEDENVELOPE",
    )
    # Swap-score bonus for a piece type / pattern kind the bot has not matched yet.
    const UNSEEN_MATCH_BONUS = 1000.0

    mutable struct TestManager <: Script
        parent
        playTextClicked::Bool
        characterButtonClicked::Bool
        timer::Float64
        totalTime::Float64
        selected_entity::Bool
        seed::Int
        seedSet::Bool
        inputHandler
        user
        persistentStateManager

        # Script references
        title
        mapManager
        gridController
        battleManager
        shopManager
        eventManager

        moveCooldown::Float64
        sceneActionCooldown::Float64
        battlesWon::Int
        battleVictoryHandled::Bool
        runsCompleted::Int
        targetCharacterIndex::Int
        characterRunStarted::Bool

        # Coverage: one potion or ability per executed swap, cycling through every type.
        sideActionReady::Bool
        preferAbility::Bool
        potionCursor::Int
        abilityCursor::Int
        gemCursor::Int
        matchedPieceKeys::Set{String}
        matchedPatterns::Set{Any}
        usedPotionKeys::Set{String}
        usedAbilityKeys::Set{String}

        function TestManager()
            this = new()

            this.playTextClicked = false
            this.characterButtonClicked = false
            this.inputHandler = nothing
            this.selected_entity = false
            this.seed = 1
            this.seedSet = false
            this.timer = 0.0
            this.totalTime = 0.0
            this.persistentStateManager = nothing
            this.mapManager = nothing
            this.gridController = nothing
            this.battleManager = nothing
            this.shopManager = nothing
            this.eventManager = nothing
            this.moveCooldown = 0.0
            this.sceneActionCooldown = 0.0
            this.battlesWon = 0
            this.battleVictoryHandled = false
            this.runsCompleted = 0
            this.targetCharacterIndex = 1
            this.characterRunStarted = false
            this.sideActionReady = true
            this.preferAbility = false
            this.potionCursor = 0
            this.abilityCursor = 0
            this.gemCursor = 0
            this.matchedPieceKeys = Set{String}()
            this.matchedPatterns = Set{Any}()
            this.usedPotionKeys = Set{String}()
            this.usedAbilityKeys = Set{String}()
            return this
        end
    end

    function reset_title_run_flags!(this::TestManager)
        this.playTextClicked = false
        this.characterButtonClicked = false
        this.characterRunStarted = false
    end

    function is_run_victory_screen(bm)::Bool
        return bm.postRunSnapshotFilled &&
               !bm.isPlayerDead &&
               Scripts.PostRunScreenModule.get_snapshot() !== nothing
    end

    is_battle_potion(potion) = potion.key in BATTLE_POTION_KEYS

    """Keep one battle potion in the bag, granting the next type in BATTLE_POTION_KEYS when none is held."""
    function ensure_test_potion!(this::TestManager, user)
        if user === nothing || any(is_battle_potion, user.potions)
            return
        end
        data = JulGame.UserGlobals["Module"].get_data_manager()
        if data === nothing
            return
        end
        # Shop-bought potions with no battle effect would otherwise fill every slot.
        if length(user.potions) >= user.max_potions
            deleteat!(user.potions, findfirst(!is_battle_potion, user.potions))
        end
        n = length(BATTLE_POTION_KEYS)
        for _ in 1:n
            this.potionCursor = mod1(this.potionCursor + 1, n)
            key = BATTLE_POTION_KEYS[this.potionCursor]
            if haskey(data.potion_data, key)
                push!(user.potions, data.potion_data[key])
                @debug "TestManager: granted test potion $(key)"
                return
            end
        end
    end

    """Grant every in-game treasure not already owned (same filter as the add_all_treasures console command)."""
    function grant_all_treasures!(user)
        globals = JulGame.UserGlobals["Module"]
        all_treasures = globals.TreasuresModule.ALL_TREASURES
        owned = Set(t.key for t in user.treasures)
        for key in sort(collect(keys(all_treasures)))
            treasure = all_treasures[key]
            if treasure === nothing || treasure.key in owned || !globals.item_available_in_game(treasure)
                continue
            end
            push!(user.treasures, treasure)
        end
    end

    """Grant every in-game non-gem piece not already owned; gems go through rotate_gem! (one gem at a time)."""
    function grant_all_pieces!(user)
        globals = JulGame.UserGlobals["Module"]
        all_pieces = globals.PiecesModule.ALL_PIECES
        owned = Set(p.key for p in user.pieces)
        for key in sort(collect(keys(all_pieces)))
            piece = all_pieces[key]
            if piece === nothing || piece.key in owned || !globals.item_available_in_game(piece) ||
               globals.UserModule.is_gem_piece(piece)
                continue
            end
            push!(user.pieces, globals.UserModule.with_new_piece_weight(piece, user.pieces))
        end
    end

    """Swap the owned gem for the next in-game gem so each gem type shows up across battles."""
    function rotate_gem!(this::TestManager, user)
        globals = JulGame.UserGlobals["Module"]
        all_pieces = globals.PiecesModule.ALL_PIECES
        gem_keys = sort([k for k in keys(all_pieces)
            if all_pieces[k] !== nothing && globals.UserModule.is_gem_piece(all_pieces[k]) &&
               globals.item_available_in_game(all_pieces[k])])
        isempty(gem_keys) && return
        this.gemCursor = mod1(this.gemCursor + 1, length(gem_keys))
        filter!(p -> !globals.UserModule.is_gem_piece(p), user.pieces)
        push!(user.pieces, globals.UserModule.with_new_piece_weight(all_pieces[gem_keys[this.gemCursor]], user.pieces))
        @debug "TestManager: rotated gem to $(gem_keys[this.gemCursor])"
    end

    """(BattlePotionManager, AbilityManager) when a potion/ability may be used this frame, else nothing."""
    function side_action_scripts(this::TestManager)
        # Opening battle runs the tutorial; leave its board alone (items are granted after it anyway).
        (this.sideActionReady && this.battlesWon >= 1) || return nothing
        bm = this.battleManager
        if bm === nothing || bm.currentState != bm.battleStates[:playerTurn]
            return nothing
        end
        gc = this.gridController
        if gc === nothing || !Scripts.GridControllerModule.are_grid_pieces_reset(gc)
            return nothing
        end
        if this.moveCooldown > 0.0 || Scripts.TutorialModule.blocks_side_actions()
            return nothing
        end
        gm = JulGame.SceneModule.get_entity_by_id(GM_ENTITY_ID)
        if gm === nothing || length(gm.scripts) < 17
            return nothing
        end
        return gm.scripts[9], gm.scripts[17]
    end

    function try_use_potion!(this::TestManager, battle_potion_manager)
        user = battle_potion_manager.user
        ensure_test_potion!(this, user)
        slot = findfirst(is_battle_potion, user.potions)
        slot === nothing && return false

        potion_key = user.potions[slot].key
        Scripts.BattlePotionManagerModule.use_potion(battle_potion_manager, slot)
        push!(this.usedPotionKeys, potion_key)
        this.sideActionReady = false
        this.moveCooldown = MOVE_COOLDOWN_SEC
        @info "TestManager: used potion $(potion_key)"
        return true
    end

    function try_use_ability!(this::TestManager, ability_manager)
        AM = Scripts.AbilityManagerModule
        n = length(ABILITY_TREASURE_KEYS)
        for _ in 1:n
            this.abilityCursor = mod1(this.abilityCursor + 1, n)
            key = ABILITY_TREASURE_KEYS[this.abilityCursor]
            AM.can_use_ability(ability_manager, key) || continue
            AM.activate_ability(ability_manager, key) || continue
            push!(this.usedAbilityKeys, key)
            this.sideActionReady = false
            this.moveCooldown = MOVE_COOLDOWN_SEC
            @info "TestManager: used ability $(key)"
            return true
        end
        return false
    end

    """Complete a potion/ability that is waiting for a grid click (bomb, eye dropper, detonator, nail)."""
    function finish_pending_selection!(this::TestManager)::Bool
        gm = JulGame.SceneModule.get_entity_by_id(GM_ENTITY_ID)
        if gm === nothing || length(gm.scripts) < 17
            return false
        end
        bpm = gm.scripts[9]
        am = gm.scripts[17]
        if !(bpm.isBombSelectionMode || bpm.isEyeDropperSelectionMode || am.isDetonatorSelectionMode || am.isNailSelectionMode)
            return false
        end
        this.moveCooldown > 0.0 && return true

        gc = this.gridController
        cx = cld(Int(gc.gridWidth), 2)
        cy = cld(Int(gc.gridHeight), 2)
        center = gc.gridPieces[cx, cy]
        PE = Scripts.BattlePotionManagerModule.PotionEffectsModule
        AM = Scripts.AbilityManagerModule
        if bpm.isBombSelectionMode
            PE.BombEffectModule.execute_bomb(bpm, cx, cy)
        elseif bpm.isEyeDropperSelectionMode
            center === nothing ? PE.EyeDropperEffectModule.cancel_eyedropper_selection(bpm) :
                PE.EyeDropperEffectModule.execute_eyedropper_clear(bpm, center.name)
        elseif am.isDetonatorSelectionMode
            am.detonatorSelectedRowCol = isodd(this.abilityCursor) ? ("row", cy) : ("column", cx)
            AM.execute_detonator(am)
        elseif center === nothing || !AM.can_use_ability(am, "TREASURE_NAIL")
            AM.cancel_nail_selection(am)
        else
            AM.execute_nail(am, center)
        end
        this.moveCooldown = MOVE_COOLDOWN_SEC
        @debug "TestManager: finished pending grid selection"
        return true
    end

    function log_coverage(this::TestManager)
        @info "TestManager coverage" matched_pieces = sort(collect(this.matchedPieceKeys)) matched_patterns = sort(string.(collect(this.matchedPatterns))) potions_used = sort(collect(this.usedPotionKeys)) abilities_used = sort(collect(this.usedAbilityKeys))
    end

    function end_test!(this::TestManager)
        log_coverage(this)
        MAIN.input.quit = true
    end

    function update_title_ai(this::TestManager, deltaTime)
        if this.runsCompleted >= TARGET_RUNS
            @info "TestManager: completed $(TARGET_RUNS) runs, ending test"
            end_test!(this)
            return
        end

        # A saved run makes "New Run" ask for confirmation before erasing it.
        dialog = this.title.confirmationDialog
        if dialog !== nothing && dialog.is_showing
            if tick_scene_cooldown!(this, deltaTime)
                Scripts.TitleModule.ConfirmationDialogModule.confirm(dialog)
                @debug "TestManager: confirmed new run over saved run"
                start_scene_cooldown!(this)
            end
            return
        end

        cs = this.title.characterSelection
        if cs.isActive
            this.playTextClicked = true
        end

        playText = JulGame.SceneModule.get_ui_element_by_id("8d625411-a72e-430b-beb9-fcb438121661")
        if playText !== nothing && !this.playTextClicked
            if !tick_scene_cooldown!(this, deltaTime)
                return
            end
            centerX = round(Int, playText.position.x + 1)
            centerY = round(Int, playText.position.y + 1)
            JulGame.InputModule.simulate_mouse_click(centerX, centerY)
            @debug "TestManager: clicked new run (run $(this.runsCompleted + 1), character index $(this.targetCharacterIndex))"
            start_scene_cooldown!(this)
            return
        end

        if cs.isActive && !cs.transitioning_to_run
            if cs.selectedCharacterIndex != this.targetCharacterIndex
                cs.selectedCharacterIndex = this.targetCharacterIndex
            end
            if !this.characterRunStarted
                if !tick_scene_cooldown!(this, deltaTime)
                    return
                end
                Scripts.CharacterSelectionModule.start_game(cs)
                this.characterRunStarted = true
                @debug "TestManager: started run with character index $(this.targetCharacterIndex)"
                start_scene_cooldown!(this, 1.5)
            end
        end
    end

    function tick_scene_cooldown!(this::TestManager, deltaTime)::Bool
        if this.sceneActionCooldown > 0.0
            this.sceneActionCooldown = max(0.0, this.sceneActionCooldown - deltaTime)
            return false
        end
        return true
    end

    function start_scene_cooldown!(this::TestManager, duration::Float64 = SCENE_ACTION_COOLDOWN_SEC)
        this.sceneActionCooldown = duration
    end

    function ensure_battle_refs!(this::TestManager)
        if this.gridController !== nothing && this.battleManager !== nothing
            return true
        end
        gm = JulGame.SceneModule.get_entity_by_id(GM_ENTITY_ID)
        if gm === nothing || length(gm.scripts) < 4
            return false
        end
        this.gridController = gm.scripts[3]
        this.battleManager = gm.scripts[4]
        return true
    end

    function ensure_map_refs!(this::TestManager)
        if this.mapManager !== nothing
            return true
        end
        entity = JulGame.SceneModule.get_entity_by_id(MAP_ENTITY_ID)
        if entity === nothing || isempty(entity.scripts)
            return false
        end
        this.mapManager = entity.scripts[1]
        return true
    end

    function ensure_shop_refs!(this::TestManager)
        if this.shopManager !== nothing
            return true
        end
        entity = JulGame.SceneModule.get_entity_by_id(SHOP_ENTITY_ID)
        if entity === nothing || isempty(entity.scripts)
            return false
        end
        this.shopManager = entity.scripts[1]
        return true
    end

    function ensure_event_refs!(this::TestManager)
        if this.eventManager !== nothing
            return true
        end
        entity = JulGame.SceneModule.get_entity_by_id(EVENT_ENTITY_ID)
        if entity === nothing || isempty(entity.scripts)
            return false
        end
        this.eventManager = entity.scripts[1]
        return true
    end

    function is_piece_swappable(piece)::Bool
        return piece !== nothing && !Scripts.AbilityManagerModule.is_piece_nailed(piece)
    end

    function intent_line_weight(value_label::String)::Float64
        label = uppercase(value_label)
        if occursin("DMG", label)
            return 10.0
        elseif label == "HEAL" || occursin("SHIELD", label)
            return 3.0
        elseif label in ("BURN", "POISON", "FREEZE", "VULN", "VULN (ALL)", "SHOCK")
            return 1.0
        elseif label == "DOLLARS"
            return 0.5
        elseif label == "RECOIL"
            return -2.0
        end
        return 0.5
    end

    function score_swap(this::TestManager, gridController, piece_a, piece_b)::Float64
        preview_matches = Scripts.GridControllerModule.get_swap_preview_matches(gridController, piece_a, piece_b)
        if isempty(preview_matches)
            return 0.0
        end
        total = 0.0
        for match in preview_matches
            for line in Scripts.GridControllerModule.get_preview_intent_lines(gridController, match.piece_key, match.action_count)
                total += Float64(line.value) * intent_line_weight(line.value_label)
            end
            # Favor unseen piece types / match shapes so more effect and pattern paths compile.
            match.piece_key in this.matchedPieceKeys || (total += UNSEEN_MATCH_BONUS)
            match.pattern in this.matchedPatterns || (total += UNSEEN_MATCH_BONUS)
        end
        return total
    end

    function record_swap_matches!(this::TestManager, gridController, piece_a, piece_b)
        for match in Scripts.GridControllerModule.get_swap_preview_matches(gridController, piece_a, piece_b)
            push!(this.matchedPieceKeys, match.piece_key)
            push!(this.matchedPatterns, match.pattern)
        end
    end

    function find_best_swap(this::TestManager, gridController)
        best_a = nothing
        best_b = nothing
        best_score = 0.0
        fallback_a = nothing
        fallback_b = nothing
        gw = gridController.gridWidth
        gh = gridController.gridHeight
        grid = gridController.gridPieces

        for x in 1:gw, y in 1:gh
            piece_a = grid[x, y]
            if !is_piece_swappable(piece_a)
                continue
            end
            for (nx, ny) in ((x + 1, y), (x, y + 1))
                if nx > gw || ny > gh
                    continue
                end
                piece_b = grid[nx, ny]
                if !is_piece_swappable(piece_b)
                    continue
                end
                if fallback_a === nothing
                    fallback_a = piece_a
                    fallback_b = piece_b
                end
                swap_score = score_swap(this, gridController, piece_a, piece_b)
                if swap_score > best_score
                    best_score = swap_score
                    best_a = piece_a
                    best_b = piece_b
                end
            end
        end

        if best_a !== nothing && best_b !== nothing
            return best_a, best_b, best_score
        end
        return fallback_a, fallback_b, 0.0
    end

    function try_execute_swap!(this::TestManager)
        gc = this.gridController
        bm = this.battleManager
        if gc === nothing || bm === nothing
            return false
        end
        if bm.currentState != bm.battleStates[:playerTurn]
            return false
        end
        if !Scripts.GridControllerModule.are_grid_pieces_reset(gc)
            return false
        end
        tutorial = Scripts.TutorialModule
        if this.moveCooldown > 0.0 || tutorial.blocks_board_input()
            return false
        end

        hint = tutorial.match_hint()
        piece_a, piece_b, swap_score = hint === nothing ? find_best_swap(this, gc) : (hint..., 0.0)
        if piece_a === nothing || piece_b === nothing
            @debug "TestManager: no legal swap found"
            return false
        end
        tutorial.allows_swap(piece_a, piece_b) || return false

        tutorial.note_swap!()
        record_swap_matches!(this, gc, piece_a, piece_b)
        Scripts.GridControllerModule.set_grid_items_to_switch(gc, piece_a, piece_b)
        this.sideActionReady = true
        this.moveCooldown = MOVE_COOLDOWN_SEC
        @debug "TestManager: executed swap (score=$(swap_score))"
        return true
    end

    """Play through the opening-battle tutorial like a player: pick the pointed-at enemy, advance talk steps."""
    function drive_tutorial!(this::TestManager)::Bool
        tutorial = Scripts.TutorialModule
        enemy = tutorial.target_hint()
        (enemy !== nothing || tutorial.awaiting_advance()) || return false
        this.moveCooldown > 0.0 && return true
        enemy === nothing ? tutorial.advance!() : Scripts.EnemyModule.select_target!(enemy)
        this.moveCooldown = TUTORIAL_STEP_COOLDOWN_SEC
        return true
    end

    function node_travel_priority(node_data)::Int
        encounter = node_data["encounter"]
        if encounter.type == "Battle"
            if encounter.category == "enemy"
                return 100
            elseif encounter.category == "elite"
                return 50
            elseif encounter.category == "boss"
                return 10
            end
            return 30
        elseif encounter.type == "Event"
            if encounter.category == "shop"
                return 80
            elseif encounter.category == "rest"
                return 70
            end
            return 40
        elseif encounter.type == "Treasure"
            return 60
        end
        return 0
    end

    function pick_next_map_node(mapManager)
        psm = mapManager.persistentStateManager
        if isempty(psm.availableNodes)
            return nothing
        end

        best_node = nothing
        best_priority = typemin(Int)
        for node_index in psm.availableNodes
            for (_, node_data) in psm.mapPoints
                if node_data["index"] != node_index
                    continue
                end
                priority = node_travel_priority(node_data)
                if priority > best_priority || (priority == best_priority && (best_node === nothing || node_index < best_node["index"]))
                    best_priority = priority
                    best_node = node_data
                end
            end
        end
        return best_node
    end

    function can_travel_on_map(mapManager)::Bool
        psm = mapManager.persistentStateManager
        return (psm.isFloorComplete || psm.currentLevel == 0) &&
               !mapManager.isHopping &&
               !mapManager.selectBlocked &&
               !isempty(psm.availableNodes)
    end

    function update_map_ai(this::TestManager, deltaTime)
        if !ensure_map_refs!(this)
            return
        end
        mm = this.mapManager
        if !can_travel_on_map(mm)
            return
        end
        if !tick_scene_cooldown!(this, deltaTime)
            return
        end

        node_data = pick_next_map_node(mm)
        if node_data === nothing
            return
        end

        @debug "TestManager: traveling to map node $(node_data["index"]) ($(node_data["encounter"].category))"
        Scripts.MapManagerModule.handle_clicks(mm, node_data)
        start_scene_cooldown!(this, 1.0)
    end

    function shop_module(shop)
        if shop isa Scripts.HamsterShopManagerModule.HamsterShopManager
            return Scripts.HamsterShopManagerModule
        end
        return Scripts.ShopManagerModule
    end

    function try_shop_purchase!(shop)::Bool
        user = shop.user
        api = shop_module(shop)
        purchases = Tuple{Int, Function}[]

        if shop.leftPieceSlot !== nothing && shop.leftPieceSlot.isActive && length(shop.availablePieces) >= 1
            piece = shop.availablePieces[1]
            if user.gold >= piece.average_price
                push!(purchases, (piece.average_price, () -> api.on_piece_click(shop, 1, piece)))
            end
        end
        if shop.rightPieceSlot !== nothing && shop.rightPieceSlot.isActive && length(shop.availablePieces) >= 2
            piece = shop.availablePieces[2]
            if user.gold >= piece.average_price
                push!(purchases, (piece.average_price, () -> api.on_piece_click(shop, 2, piece)))
            end
        end
        if shop.leftTreasureSlot !== nothing && shop.leftTreasureSlot.isActive && length(shop.availableTreasures) >= 1
            price = shop.availableTreasures[1].average_price
            if user.gold >= price
                push!(purchases, (price, () -> api.on_treasure_click(shop, 1)))
            end
        end
        if shop.rightTreasureSlot !== nothing && shop.rightTreasureSlot.isActive && length(shop.availableTreasures) >= 2
            price = shop.availableTreasures[2].average_price
            if user.gold >= price
                push!(purchases, (price, () -> api.on_treasure_click(shop, 2)))
            end
        end
        for (slot_idx, slot, sold_sign) in (
            (1, shop.leftPotionSlot, shop.leftPotionSoldSign),
            (2, shop.middlePotionSlot, shop.middlePotionSoldSign),
            (3, shop.rightPotionSlot, shop.rightPotionSoldSign),
        )
            if slot !== nothing && slot.isActive && length(shop.availablePotions) >= slot_idx
                potion = shop.availablePotions[slot_idx]
                if user.gold >= potion.average_price && length(user.potions) < 4
                    push!(purchases, (potion.average_price, () -> api.on_potion_click(shop, slot_idx, potion)))
                end
            end
        end

        if isempty(purchases)
            return false
        end
        sort!(purchases, by = p -> p[1])
        purchases[1][2]()
        return true
    end

    function update_shop_ai(this::TestManager, deltaTime)
        if !ensure_shop_refs!(this)
            return
        end
        if !tick_scene_cooldown!(this, deltaTime)
            return
        end

        shop = this.shopManager
        if try_shop_purchase!(shop)
            @debug "TestManager: purchased shop item (gold=$(shop.user.gold))"
            start_scene_cooldown!(this)
            return
        end

        @debug "TestManager: leaving shop"
        shop_module(shop).on_exit_click(shop)
        start_scene_cooldown!(this)
    end

    function update_event_ai(this::TestManager, deltaTime)
        if !ensure_event_refs!(this)
            return
        end
        em = this.eventManager
        if em.declineShown || em.isZooming
            return
        end
        if !tick_scene_cooldown!(this, deltaTime)
            return
        end

        if !em.endReached && !isempty(em.pages)
            em.pageIndex = length(em.pages)
            em.endReached = true
            em.hasQuestion = true
            push!(em.viewedPages, em.pageIndex)
            start_scene_cooldown!(this)
            return
        end

        chest = em.treasureChest
        if chest !== nothing && !em.eventResolved
            if chest.phase == :closed
                Scripts.EventManagerModule.treasure_open!(em)
            elseif chest.phase == :presented
                Scripts.EventManagerModule.treasure_take!(em)
                @debug "TestManager: took map treasure"
            end
            start_scene_cooldown!(this)
            return
        end

        if !em.eventResolved
            globals = JulGame.UserGlobals["Module"]
            globals.RandomEventsModule.handle_accept(em, em.currentEvent)
            @debug "TestManager: accepted event $(em.currentEvent.key)"
            start_scene_cooldown!(this)
            return
        end

        em.isZooming = true
        em.zoomT = 0.0
        em.fadeToBlackA = 0
        start_scene_cooldown!(this)
    end

    function handle_battle_victory!(this::TestManager, deltaTime)
        bm = this.battleManager
        if bm === nothing || bm.currentState != bm.battleStates[:battleEnd] || bm.isPlayerDead
            return
        end

        if is_run_victory_screen(bm)
            if !tick_scene_cooldown!(this, deltaTime)
                return
            end
            this.runsCompleted += 1
            @info "TestManager: run victory $(this.runsCompleted)/$(TARGET_RUNS)"
            if this.runsCompleted >= TARGET_RUNS
                @info "TestManager: all runs complete, ending test"
                end_test!(this)
                return
            end
            this.targetCharacterIndex = this.runsCompleted + 1
            this.seed += 1
            this.seedSet = false
            this.battlesWon = 0
            reset_title_run_flags!(this)
            if bm.transitionManager !== nothing
                Scripts.SceneTransitionModule.transition_to_scene(
                    bm.transitionManager,
                    "title_scene.json";
                    direction = Scripts.SceneTransitionModule.Fade,
                )
            end
            start_scene_cooldown!(this, 2.0)
            return
        end

        if !this.battleVictoryHandled
            this.battlesWon += 1
            this.battleVictoryHandled = true
            @info "TestManager: battle won (total=$(this.battlesWon))"
            if this.battlesWon == 1
                apply_test_player_buffs!(this)
                @info "TestManager: applied test buffs after first battle"
            end
        end

        rm = bm.rewardManager
        if rm === nothing
            return
        end

        if !tick_scene_cooldown!(this, deltaTime)
            return
        end

        # Claim the optional dollars, then take the first option. Both are
        # independent, and only one option can ever be taken.
        if !rm.goldClaimed && rm.goldReward !== nothing
            Scripts.RewardManagerModule.claim_gold!(rm)
            @debug "TestManager: claimed reward dollars"
            start_scene_cooldown!(this)
            return
        end

        if rm.chosenIndex == 0 && !isempty(rm.choices)
            Scripts.RewardManagerModule.choose!(rm, 1)
            @debug "TestManager: chose reward option 1"
            start_scene_cooldown!(this)
            return
        end

        if bm.transitionManager !== nothing
            @debug "TestManager: continuing to map after victory"
            Scripts.BattleManagerModule.continue_after_victory!(bm)
            start_scene_cooldown!(this, 1.0)
        end
    end

    function update_battle_ai(this::TestManager, deltaTime)
        if !ensure_battle_refs!(this)
            return
        end

        this.moveCooldown = max(0.0, this.moveCooldown - deltaTime)
        bm = this.battleManager

        if bm.currentState == bm.battleStates[:battleEnd]
            handle_battle_victory!(this, deltaTime)
            return
        end

        if drive_tutorial!(this)
            return
        end

        if finish_pending_selection!(this)
            return
        end

        # Alternate potion / ability per swap; fall back to the other when one has nothing usable.
        scripts = side_action_scripts(this)
        if scripts !== nothing
            bpm, am = scripts
            this.preferAbility = !this.preferAbility
            used = this.preferAbility ?
                (try_use_ability!(this, am) || try_use_potion!(this, bpm)) :
                (try_use_potion!(this, bpm) || try_use_ability!(this, am))
            used && return
            this.sideActionReady = false
        end

        try_execute_swap!(this)
    end

    function apply_test_player_buffs!(this::TestManager)
        # Wait until after the first battle so enemies can attack an unbuffed player.
        if this.battlesWon < 1
            return
        end
        user = this.user
        if user === nothing
            try
                user = JulGame.UserGlobals["Module"].get_user_data()
            catch
                return
            end
        end
        JulGame.UserGlobals["Module"].UserModule.apply_automated_test_buffs!(user)
        grant_all_treasures!(user)
        grant_all_pieces!(user)
        ensure_test_potion!(this, user)
    end

    function JulGame.initialize(this::TestManager)
        if MAIN.scene.name == "scene"
            gm = JulGame.SceneModule.get_entity_by_id(GM_ENTITY_ID)
            this.inputHandler = gm.scripts[2]
        elseif MAIN.scene.name == "map"
            globals = JulGame.UserGlobals["Module"]
            this.persistentStateManager = globals.get_data_manager().persistent_state_manager
            if !this.seedSet
                globals.PersistentStateManagerModule.init_seed(this.persistentStateManager, seed = this.seed)
                this.seedSet = true
            end
            this.user = globals.get_user_data()
            apply_test_player_buffs!(this)
            this.battlesWon >= 1 && rotate_gem!(this, this.user)
            this.mapManager = nothing
            ensure_map_refs!(this)
        elseif MAIN.scene.name == "title_scene"
            this.title = JulGame.SceneModule.get_entity_by_id("1faa9aa0-2a10-4452-8024-7eb64b02da6e").scripts[1]
        elseif MAIN.scene.name == "battle"
            this.gridController = nothing
            this.battleManager = nothing
            this.moveCooldown = 0.0
            this.battleVictoryHandled = false
            this.sideActionReady = true
            apply_test_player_buffs!(this)
            ensure_battle_refs!(this)
        elseif MAIN.scene.name == "upgraded-shop" || MAIN.scene.name == "hamster-shop"
            this.shopManager = nothing
            apply_test_player_buffs!(this)
            ensure_shop_refs!(this)
        elseif MAIN.scene.name == "event" || MAIN.scene.name == "rest"
            this.eventManager = nothing
            ensure_event_refs!(this)
        end
    end

    function JulGame.update(this::TestManager, deltaTime)
        try
            this.totalTime += deltaTime
            # MainSettings re-applies the saved slider on init, so pin it every frame.
            JulGame.UserGlobals["Module"].get_data_manager().game_speed_multiplier = TEST_GAME_SPEED

            if MAIN.scene.name == "title_scene"
                update_title_ai(this, deltaTime)
            elseif MAIN.scene.name == "map"
                update_map_ai(this, deltaTime)
            elseif MAIN.scene.name == "battle"
                update_battle_ai(this, deltaTime)
            elseif MAIN.scene.name == "upgraded-shop" || MAIN.scene.name == "hamster-shop"
                update_shop_ai(this, deltaTime)
            elseif MAIN.scene.name == "event" || MAIN.scene.name == "rest"
                update_event_ai(this, deltaTime)
            elseif MAIN.scene.name == "shop"
                this.timer += deltaTime
            end

            if this.totalTime > TEST_RUN_TIMEOUT_SEC
                @info "TestManager: timed out (runs=$(this.runsCompleted)/$(TARGET_RUNS), battles won=$(this.battlesWon), elapsed=$(round(this.totalTime, digits=1))s)"
                end_test!(this)
            end
        catch e
            @error "Error in test manager" exception=e
            Base.show_backtrace(stdout, catch_backtrace())
        end
    end

    function JulGame.on_shutdown(this::TestManager)
    end
end
