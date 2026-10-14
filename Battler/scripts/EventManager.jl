module EventManagerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.EffectsModule
    using Random
    using ..Scripts
    using ..OverworldFeedbackModule
    using ..TreasureChestModule

    const EVENT_ART_EFFECTS = [
        RoughEdgeEffect(; amount=2, seed=42042, erosion=true)
    ]
    include("TypingEffect.jl")
    using .TypingEffectModule
    include("localization/event_strings.jl")
    using .EventStringsModule

    const DIALOG_PANEL_W = 1000
    const DIALOG_PANEL_H = 250
    const TEXT_SCROLL_TILE = 128
    const TEXT_SCROLL_SPEED = 14.0  # px/s on both axes (diagonal)
    const EVENT_BUTTON_YES_COLOR = (100, 200, 110, 255)
    const EVENT_BUTTON_NO_COLOR = (210, 80, 80, 255)

    function event_action_button(id::String, click::Function; text::String, fontSize::Int, size, anchor::Symbol, anchorOffset, layer::Int=0, color::NTuple{4, Int}=(255, 255, 255, 255), downArt::String=Scripts.NineSliceUIModule.BUTTON_DOWN_PATH, downColor::NTuple{4, Int}=color)
        button = Scripts.NineSliceUIModule.immediate_button(
            id,
            click;
            downArt = downArt,
            text = text,
            fontSize = fontSize,
            size = size,
            anchor = anchor,
            anchorOffset = anchorOffset,
            layer = layer,
            color = color,
            forceClickCheck = true,
        )
        tint = button.isHovered ? downColor : color
        if button.color != tint
            JulGame.UI.set_color(button; r=tint[1], g=tint[2], b=tint[3], a=tint[4])
        end
        return button
    end
    
    mutable struct EventManager <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        # This is where you define your script's fields
        # Example: speed::Float64
        currentEvent
        answered::Bool

        persistentStateManager
        user
        playerEntity
        transitionManager

        # New Event UI state
        pages
        pageIndex::Int
        hasQuestion::Bool
        yesSlideT::Float64
        noSlideT::Float64
        oddsFadeT::Float64
        oddsDelayMs::Float64
        oddsVisibleOnce::Bool
        settledForOdds::Bool
        illustrationScale::Float64
        isZooming::Bool
        zoomT::Float64
        fadeToBlackA::Int
        declineShown::Bool
        declineTimer::Float64
        endReached::Bool
        eventResolved::Bool  # True after player clicks Yes - prevents spam and shows Continue
        textScrollT::Float64
        
        # Typing effect
        typingEffect::TypingEffectModule.TypingEffectController
        viewedPages::Set{Int}
        # Typing was still running at frame start; the click that skips it must not also page/choose.
        typingWasBusy::Bool

        # Event art presentation
        artAnimT::Float64
        artJitterSeed::Float64
        artEffectsIllustration::String

        doorHover::Int
        doorChosen::Int
        doorOutcomes::Vector{Symbol}

        treasureChest::Union{Nothing, TreasureChestModule.TreasureChest}  # set on treasure nodes
        fireMenu::Symbol  # rest site: :closed, :kinds or :potions

        function EventManager()
            this = new() # do not remove this line
            
            # this is where you initialize your script's fields
            # Example: this.speed = 1.0
            this.answered = false
            this.playerEntity = nothing
            
            # Initialize new UI state
            this.pages = [
                EventStringsModule.EVENT_STRINGS[:event_mousehole_page1],
                EventStringsModule.EVENT_STRINGS[:event_mousehole_page2]
            ]
            this.pageIndex = 1
            this.hasQuestion = false
            this.yesSlideT = 0.0
            this.noSlideT = 0.0
            this.oddsFadeT = 0.0
            this.oddsDelayMs = 1200.0
            this.oddsVisibleOnce = false
            this.settledForOdds = false
            this.illustrationScale = 1.0
            this.isZooming = false
            this.zoomT = 0.0
            this.fadeToBlackA = 0
            this.declineShown = false
            this.declineTimer = 0.0
            this.endReached = false
            this.eventResolved = false
            this.textScrollT = 0.0
            
            # Initialize typing effect
            this.typingEffect = TypingEffectModule.TypingEffectController(
                "";
                base_speed_ms = 50.0,
                speed_up_multiplier = 3.0,
                sound_files = [JulGame.UserGlobals["Module"].get_asset_path("sfx", "tick1")],
                play_sound_every_n_chars = 2,
                punctuation_sounds_enabled = false,
                punctuation_pause_ms = 300.0,
                show_completion_indicator = true,
                completion_indicator_text = EventStringsModule.EVENT_STRINGS[:typing_completion_indicator],
                completion_indicator_blink_speed = 0.5,
                skip_key = "RETURN",
                speed_up_key = "SPACE",
                skip_on_click = true
            )
            this.viewedPages = Set{Int}()
            this.typingWasBusy = false
            this.artAnimT = 0.0
            this.artJitterSeed = 0.0
            this.artEffectsIllustration = ""
            this.doorHover = 0
            this.doorChosen = 0
            this.doorOutcomes = Symbol[]
            this.treasureChest = nothing
            this.fireMenu = :closed

            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # This is where you should register collision events or other events
    # Do not remove this function
    function JulGame.initialize(this::EventManager)
        @debug("Event manager initialized")
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()
        this.persistentStateManager = globals.get_data_manager().persistent_state_manager
        try
            this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
        catch e
            @error "SceneTransitionManager not found: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end

        # Set rich presence for events
        if this.persistentStateManager.currentLevel > 0
            globals.SteamModule.set_rich_presence_with_position(globals.get_steam_data(), "Event", this.persistentStateManager.currentRoom, this.persistentStateManager.currentFloor)
        else
            globals.SteamModule.set_rich_presence(globals.get_steam_data(), "Event")
        end
        userEntity = JulGame.SceneModule.get_entity_by_name("Player")
        this.playerEntity = userEntity
        if userEntity !== nothing
            if this.user.selectedCharacter == "CHARACTER_MAGICIAN"
                userEntity.sprite.imagePath = globals.get_asset_path("shop", "magician_backpersp")
            elseif this.user.selectedCharacter == "CHARACTER_DEMOLITIONIST"
                userEntity.sprite.imagePath = globals.get_asset_path("shop", "demolitionist_backpersp")
            elseif this.user.selectedCharacter == "CHARACTER_KNIGHT"
                userEntity.sprite.imagePath = globals.get_asset_path("shop", "knight_backpersp")
            end
        end
        if this.persistentStateManager.currentEvent.type == "Treasure"
            this.treasureChest = TreasureChestModule.TreasureChest(this.user)
            this.currentEvent = (key = "TREASURE_CHEST", type = "Treasure", illustration = nothing)
        else
            this.currentEvent = globals.RandomEventsModule.ALL_RANDOMEVENTS[uppercase(this.persistentStateManager.currentEvent.name)]
        end
        @debug "Current event: $(this.currentEvent)"
        if this.treasureChest !== nothing
            this.pages = [EventStringsModule.EVENT_STRINGS[:treasure_chest_intro]]
        elseif this.currentEvent.key == "RANDOMEVENT_RESTSITE"
            this.pages = [
                EventStringsModule.EVENT_STRINGS[:event_restsite_page1],
                EventStringsModule.EVENT_STRINGS[:event_restsite_page2]
            ]
        else
            this.pages = [
                this.currentEvent.description
            ]
        end
        
        # Start typing effect for first page
        if !isempty(this.pages)
            TypingEffectModule.start_typing(this.typingEffect, this.pages[1])
        end
        
        # If only one page, automatically show choices/odds without extra click
        # (page 1 is marked viewed by render once typing completes)
        if length(this.pages) == 1
            this.endReached = true
            this.hasQuestion = true
        end

        this.artAnimT = 0.0
        this.artJitterSeed = rand() * 2π
        this.artEffectsIllustration = ""
        this.doorHover = 0
        this.doorChosen = 0
        this.doorOutcomes = if this.currentEvent.key == "RANDOMEVENT_THREEDOORS"
            Random.shuffle(Symbol[:treasure, :pain, :empty])
        else
            Symbol[]
        end
        OverworldFeedbackModule.reset!()
        OverworldFeedbackModule.set_player!(this.playerEntity)
        Scripts.PotionTooltipModule.spawn!()

    end

    # This is called every frame
    # Do not remove this function
    function JulGame.update(this::EventManager, deltaTime)
        OverworldFeedbackModule.update(deltaTime)
        if Scripts.SettingsDisplayManagerModule.is_settings_open()
            return
        end
        # Update typing effect
        this.typingWasBusy = !(this.pageIndex in this.viewedPages) && !TypingEffectModule.is_typing_complete(this.typingEffect)
        TypingEffectModule.update(this.typingEffect, deltaTime)
        
        # Narrative event rendering pipeline
        render_narrative_event(this, deltaTime)
    end

    # This is called when the script is removed from an entity (scene change, entity deletion)
    # Do not remove this function
    function JulGame.on_shutdown(this::EventManager)
        OverworldFeedbackModule.reset!()
    end

    const THREE_DOORS_OPEN = ("doorsleftopen", "doorsmiddleopen", "doorsrightopen")
    const THREE_DOORS_HITS = (
        (84, 142, 273, 366),
        (389, 142, 273, 366),
        (693, 142, 273, 366),
    )

    function event_illustration_key(this::EventManager)
        ev = this.currentEvent
        ev === nothing && return "wip"
        if ev.key == "RANDOMEVENT_THREEDOORS"
            door = this.doorChosen > 0 ? this.doorChosen : this.doorHover
            return 1 <= door <= 3 ? THREE_DOORS_OPEN[door] : "doorsnoneopen"
        end
        ev.illustration !== nothing && ev.illustration != "" && return ev.illustration
        ev.key == "RANDOMEVENT_RESTSITE" && return "rest"
        return "wip"
    end

    function draw_three_door_hitboxes(this::EventManager, art)
        (this.eventResolved || this.isZooming || this.declineShown || !(this.pageIndex in this.viewedPages)) && return
        globals = JulGame.UserGlobals["Module"]
        for door in 1:3
            x, y, w, h = THREE_DOORS_HITS[door]
            btn = JulGame.ImmediateUIModule.immediate_button(
                "event_door_$(door)",
                () -> begin
                    if !this.eventResolved
                        _record_event_choice(this, string(door))
                        globals.RandomEventsModule.handle_choice(this, this.currentEvent, string(door))
                        this.persistentStateManager.isFloorComplete = true
                    end
                end;
                size = Math.Vector2(w, h),
                buttonUpPath = "pixel.png",
                buttonDownPath = "pixel.png",
                parent = art,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(x, y),
                layer = 5,
                color = (255, 255, 255, 1),
                forceClickCheck = true,
            )
            if length(btn.hoverEnterEvents) == 0
                push!(btn.hoverEnterEvents, () -> (this.doorHover = door))
            end
            if length(btn.hoverExitEvents) == 0
                push!(btn.hoverExitEvents, () -> begin
                    if this.doorHover == door
                        this.doorHover = 0
                    end
                end)
            end
        end
    end

    # ================= Treasure chest node =================
    function update_treasure_chest(this::EventManager, deltaTime, scale)
        signal = TreasureChestModule.update!(this.treasureChest, deltaTime; zoom = scale)
        if signal == :clicked
            treasure_open!(this)
        elseif signal == :presented
            set_event_text!(this, treasure_reward_text(this.treasureChest))
        elseif signal == :finished
            this.eventResolved = true
        end
    end

    function treasure_reward_text(chest)
        reward = chest.reward
        reward === nothing && return EventStringsModule.format_string(:treasure_chest_gold; gold_amount = chest.gold)
        return EventStringsModule.format_string(:treasure_chest_found; treasure_name = reward.name, treasure_desc = reward.description)
    end

    function set_event_text!(this::EventManager, text::String)
        this.pages[this.pageIndex] = text
        delete!(this.viewedPages, this.pageIndex)
        TypingEffectModule.start_typing(this.typingEffect, text)
    end

    function treasure_open!(this::EventManager)
        TreasureChestModule.open_chest!(this.treasureChest) && _record_event_choice(this, "open")
    end

    function treasure_take!(this::EventManager)
        chest = this.treasureChest
        TreasureChestModule.take_reward!(chest, this.playerEntity) || return
        _record_event_choice(this, "take")
        set_event_text!(this, chest.reward === nothing ?
            EventStringsModule.format_string(:treasure_chest_gold_taken; gold_amount = chest.gold) :
            EventStringsModule.format_string(:treasure_chest_taken; treasure_name = chest.reward.name))
        this.persistentStateManager.isFloorComplete = true
    end

    function treasure_leave!(this::EventManager)
        TreasureChestModule.leave_reward!(this.treasureChest) || return
        _record_event_choice(this, "leave")
        set_event_text!(this, EventStringsModule.EVENT_STRINGS[:treasure_chest_left])
        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
        this.persistentStateManager.isFloorComplete = true
    end

    function draw_treasure_choices(this::EventManager)
        if this.treasureChest.phase == :presented
            event_action_button(
                "event_treasure_take_btn",
                () -> treasure_take!(this);
                text = EventStringsModule.EVENT_STRINGS[:treasure_chest_take],
                fontSize = 44,
                size = Math.Vector2(280, 90),
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(-170, -50),
                layer = 10,
                color = EVENT_BUTTON_YES_COLOR,
            )
            event_action_button(
                "event_treasure_leave_btn",
                () -> treasure_leave!(this);
                text = EventStringsModule.EVENT_STRINGS[:treasure_chest_leave],
                fontSize = 44,
                size = Math.Vector2(280, 90),
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(170, -50),
                layer = 10,
                color = EVENT_BUTTON_NO_COLOR,
            )
        end
    end

    # ================= Rest site =================
    const FIRE_BUTTON_COLOR = (230, 130, 50, 255)
    const FIRE_BUTTON_DOWN_ART = Scripts.NineSliceUIModule.BUTTON_UP_PATH  # the cyan hover art tints orange into green
    const FIRE_BUTTON_DOWN_COLOR = (255, 200, 110, 255)

    function rest_offer!(this::EventManager, choice::String)
        this.eventResolved && return
        _record_event_choice(this, choice)
        Globals.RandomEventsModule.handle_choice(this, this.currentEvent, choice)
        this.fireMenu = :closed
        this.persistentStateManager.isFloorComplete = true
    end

    function rest_menu_buttons(this::EventManager)
        S = EventStringsModule.EVENT_STRINGS
        back(menu) = (S[:fire_offer_back], EVENT_BUTTON_NO_COLOR, () -> (this.fireMenu = menu))
        kinds = Globals.RandomEventsModule.fire_offer_kinds(this.user)
        if this.fireMenu == :potions
            return [[(p.en_name, FIRE_BUTTON_COLOR, () -> rest_offer!(this, "fire_potion_$i")) for (i, p) in enumerate(this.user.potions)]; back(:kinds)]
        elseif this.fireMenu == :kinds
            pick = kind -> kind == :potion ? (this.fireMenu = :potions) : rest_offer!(this, "fire_$(kind)")
            return [[(S[Symbol(:fire_offer_, kind)], FIRE_BUTTON_COLOR, () -> pick(kind)) for kind in kinds]; back(:closed)]
        end
        rest = (S[:rest_site_rest], EVENT_BUTTON_YES_COLOR, () -> begin
            this.eventResolved && return
            _record_event_choice(this, "accept")
            Globals.RandomEventsModule.handle_accept(this, this.currentEvent)
            this.persistentStateManager.isFloorComplete = true
        end)
        return isempty(kinds) ? [rest] : [rest, (S[:rest_site_offer], FIRE_BUTTON_COLOR, () -> (this.fireMenu = :kinds))]
    end

    function draw_rest_choices(this::EventManager)
        buttons = rest_menu_buttons(this)
        n = length(buttons)
        for (i, (label, color, click)) in enumerate(buttons)
            event_action_button(
                "event_rest_$(this.fireMenu)_$(i)",
                click;
                text = label,
                fontSize = this.fireMenu == :potions ? 32 : 44,
                size = Math.Vector2(280, 90),
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(round(Int, (i - (n + 1) / 2) * 300), -50),
                layer = 10,
                color = color,
                downArt = color == FIRE_BUTTON_COLOR ? FIRE_BUTTON_DOWN_ART : Scripts.NineSliceUIModule.BUTTON_DOWN_PATH,
                downColor = color == FIRE_BUTTON_COLOR ? FIRE_BUTTON_DOWN_COLOR : color,
            )
        end
    end
    
    function exit_event(this::EventManager)
        globals = JulGame.UserGlobals["Module"]
        globals.SaveManagerModule.try_save_run!()
        try
            dj = Scripts.DJModule.try_get_dj()
            if dj !== nothing
                Scripts.DJModule.fade_out_campfire_layer(dj)
            end
        catch e
            @debug "fade_out_campfire_layer: $e"
        end
        Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "map.json"; direction = Scripts.SceneTransitionModule.Fade)
    end

    function show_message(this::EventManager, message::String)
        DisplayTextModule.display_text(
            "result_text",
            message;
            anchor = :center,
            fontSize = 28,
            anchorOffset = Math.Vector2(0, -100),
            lifetime = 500
        )
    end

    function compute_event_art_jitter_offset(t::Float64, seed::Float64)
        ox = sin(t * 2.8 + seed) * 3.5 + sin(t * 4.7 + seed * 1.7) * 1.8 + sin(t * 7.5 + seed * 2.3) * 0.9
        oy = cos(t * 2.5 + seed * 0.9) * 3.0 + sin(t * 4.2 + seed * 2.1) * 1.6 + cos(t * 7.0 + seed * 1.5) * 0.8
        return (ox, oy)
    end

    const EVENT_PLAYER_HP_HEART_H = 72
    const EVENT_PLAYER_HP_HEART_W = round(Int, EVENT_PLAYER_HP_HEART_H * 108 / 95)

    function draw_player_hp_display(this::EventManager, deltaTime = 0.0)
        player = this.playerEntity
        if player === nothing || player.sprite === nothing || this.user === nothing
            return
        end

        heart = JulGame.ImmediateUIModule.immediate_image(
            "event_player_hp_heart",
            JulGame.UserGlobals["Module"].get_asset_path("ui", "healthheart");
            size = Math.Vector2(EVENT_PLAYER_HP_HEART_W, EVENT_PLAYER_HP_HEART_H),
            color = (255, 70, 127, 255),
            parent = player.sprite,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(-EVENT_PLAYER_HP_HEART_W - 10, -40),  # left of the head, clear of the No button on the right edge
            layer = 20,
        )
        max_hp = max(Int(this.user.maxHealth), 1)
        shown, highlight = Scripts.HeartFillFXModule.present!(
            "event_hp",
            Float64(this.user.health) / Float64(max_hp),
            Float64(deltaTime),
        )
        heart.color = highlight >= 0 ? Scripts.HeartFillFXModule.FLASH_COLOR : Scripts.HeartFillFXModule.IDLE_COLOR
        Scripts.CurrentRunStatusModule.gfx_clock_hand_sweep_ui(
            heart,
            shown;
            highlight_below = highlight,
            bake_tint = Scripts.HeartFillFXModule.BAKE_TINT,
        )
        DisplayTextModule.display_text(
            "event_player_hp_text",
            "$(this.user.health)";
            fontSize = 28,
            anchor = :center,
            color = (255, 255, 255, 255),
            parent = heart,
            layer = 21,
        )
    end

    function draw_dialog_scroll_bg(panel, scrollT::Float64)
        tile = TEXT_SCROLL_TILE
        il, it, ir, ib = Scripts.NineSliceUIModule.PANEL_INNER
        panelW = Int(panel.size.x)
        panelH = Int(panel.size.y)
        innerLeft = il
        innerTop = it
        innerRight = panelW - ir
        innerBottom = panelH - ib

        # Integer scroll so edges meet exactly; wrap in [0, tile)
        ox = Int(floor(mod(scrollT * TEXT_SCROLL_SPEED, Float64(tile))))
        oy = ox

        # Fixed overscan grid: always +1 tile so scroll offset can never leave a full hole
        nCols = Int(ceil(Float64(innerRight - innerLeft) / tile)) + 1
        nRows = Int(ceil(Float64(innerBottom - innerTop) / tile)) + 1

        for row in 0:(nRows - 1)
            for col in 0:(nCols - 1)
                # -ox moves left, +oy moves down; -tile on y keeps top coverage with overscan
                x = innerLeft + col * tile - ox
                y = innerTop + row * tile + oy - tile

                visLeft = max(x, innerLeft)
                visTop = max(y, innerTop)
                visRight = min(x + tile, innerRight)
                visBottom = min(y + tile, innerBottom)
                if visRight <= visLeft || visBottom <= visTop
                    continue
                end

                srcX = visLeft - x
                srcY = visTop - y
                srcW = visRight - visLeft
                srcH = visBottom - visTop

                crop = (srcX == 0 && srcY == 0 && srcW == tile && srcH == tile) ?
                    C_NULL : Math.Vector4(srcX, srcY, srcW, srcH)

                img = JulGame.ImmediateUIModule.immediate_image(
                    "event_scroll_$(col)_$(row)",
                    JulGame.UserGlobals["Module"].get_asset_path("ui", "textscroll");
                    anchor = :topLeft,
                    anchorOffset = Math.Vector2(visLeft, visTop),
                    size = Math.Vector2(srcW, srcH),
                    crop = crop,
                    parent = panel,
                    layer = 2,
                    color = (255, 255, 255, 255)
                )
                # Force both fields — ImmediateUI may skip size when originalSize already matches
                img.size = Math.Vector2(srcW, srcH)
                img.originalSize = Math.Vector2(srcW, srcH)
            end
        end
    end

    # ================= New Narrative Event UI =================
    function render_narrative_event(this::EventManager, deltaTime)
        globals = JulGame.UserGlobals["Module"]
        # 1) Illustration placeholder with optional zoom
        scale = this.illustrationScale
        if this.isZooming
            this.zoomT += deltaTime
            scale = 1.0 + min(this.zoomT / 400.0, 1.0) * 1.2  # ~0.4s to reach +120%
            this.illustrationScale = scale
            # Fade to black after zoom starts
            this.fadeToBlackA = min(this.fadeToBlackA + 12, 255)
        else
            this.artAnimT += deltaTime
        end
        if this.treasureChest !== nothing
            update_treasure_chest(this, deltaTime, scale)
        else
            jx, jy = this.isZooming ? (0.0, 0.0) : compute_event_art_jitter_offset(this.artAnimT, this.artJitterSeed)
            illustration_key = event_illustration_key(this)
            baseSize = Math.Vector2(1050, 591)
            drawSize = Math.Vector2(Int(round(baseSize.x * scale)), Int(round(baseSize.y * scale)))
            rect = JulGame.ImmediateUIModule.immediate_image(
                "event_art_image",
                globals.get_asset_path("eventimg", illustration_key);
                anchor = :centerTop,
                anchorOffset = Math.Vector2(jx, jy + 15),
                size = drawSize,
                color = (255, 255, 255, 255)
            )
            if this.artEffectsIllustration != illustration_key
                JulGame.apply_effects!(rect, EVENT_ART_EFFECTS)
                this.artEffectsIllustration = illustration_key
            end
            if this.currentEvent !== nothing && this.currentEvent.key == "RANDOMEVENT_THREEDOORS"
                draw_three_door_hitboxes(this, rect)
            end
        end

        draw_player_hp_display(this, deltaTime)

        # Optional fade to black overlay during zoom
        if this.fadeToBlackA > 0
            JulGame.ImmediateUIModule.immediate_rect(
                "event_fade_black";
                anchor = :center,
                anchorOffset = Math.Vector2(0, 0),
                size = Math.Vector2(1920, 1080),
                color = (0, 0, 0, this.fadeToBlackA)
            )
            if this.fadeToBlackA >= 255
                # End the event when fully faded
                exit_event(this)
                return
            end
        end

        # 2) Dialogue panel
        this.textScrollT += deltaTime
        panel = Scripts.NineSliceUIModule.immediate_panel(
            "event_dialog_bg";
            anchor = :centerBottom,
            anchorOffset = Math.Vector2(0, -200),
            size = Math.Vector2(DIALOG_PANEL_W, DIALOG_PANEL_H),
            layer = 1,
        )
        draw_dialog_scroll_bg(panel, this.textScrollT)
        
        # Determine text to display
        txt = this.pages[this.pageIndex]
        color = (255, 255, 255, 255)
        if this.declineShown
            txt = EventStringsModule.EVENT_STRINGS[:event_decline_message]
            color = (230, 80, 80, 255)
        elseif !(this.pageIndex in this.viewedPages)
            # First time viewing this page - use typing effect
            txt = TypingEffectModule.get_visible_text(this.typingEffect)
            # Mark as viewed once typing completes
            if TypingEffectModule.is_typing_complete(this.typingEffect)
                push!(this.viewedPages, this.pageIndex)
            end
        end
        
        DisplayTextModule.display_text(
            "event_dialog_text",
            txt;
            fontSize = 36,
            anchor = :center,
            anchorOffset = Math.Vector2(0, 0),
            maxLineWidth = DIALOG_PANEL_W - 2 * Scripts.NineSliceUIModule.PANEL_SLICE,
            wrapWords = true,
            parent = panel,
            layer = 3,
            color = color
        )
        
        # Show typing completion indicator
        if !(this.pageIndex in this.viewedPages) && !this.declineShown
            TypingEffectModule.draw_completion_indicator(
                this.typingEffect;
                anchor = :bottomRight,
                anchorOffset = Math.Vector2(-20, -20),
                fontSize = 32,
                color = (255, 255, 255, 255),
                layer = 3,
                parent = panel
            )
        end
        # Page indicator
        if this.eventResolved # is resolved, show page indicator
        DisplayTextModule.display_text(
            "event_page_indicator",
            string(this.pageIndex, "/", length(this.pages));
            fontSize = 28,
            anchor = :topRight,
            anchorOffset = Math.Vector2(50, -50),
            parent = panel,
            layer = 3
        )
        end
        # 3) Paging arrows (only show if typing is complete on current page)
        typing_complete_or_viewed = !this.typingWasBusy &&
            ((this.pageIndex in this.viewedPages) || TypingEffectModule.is_typing_complete(this.typingEffect))
        
        if this.pageIndex > 1 && this.endReached && length(this.pages) > 1 && typing_complete_or_viewed
            DisplayTextModule.display_text(
                "event_prev_text",
                "◀";
                clickEvent = () -> begin
                    old_page = this.pageIndex
                    this.pageIndex = max(1, this.pageIndex - 1)
                    this.hasQuestion = (this.pageIndex == length(this.pages))
                    # Page already viewed, so no typing effect needed
                end,
                fontSize = 48,
                anchor = :centerLeft,
                anchorOffset = Math.Vector2(- 70, 0),
                parent = panel,
                layer = 3
            )
        end
        if this.pageIndex < length(this.pages) && this.endReached && length(this.pages) > 1 && typing_complete_or_viewed
            DisplayTextModule.display_text(
                "event_next_text",
                "▶";
                clickEvent = () -> begin
                    this.pageIndex = min(length(this.pages), this.pageIndex + 1)
                    
                    # Start typing effect if this is a new page
                    if !(this.pageIndex in this.viewedPages)
                        TypingEffectModule.start_typing(this.typingEffect, this.pages[this.pageIndex])
                    end
                    
                    # Reset animations when entering question page
                    if this.pageIndex == length(this.pages)
                        this.hasQuestion = true
                        this.yesSlideT = 0.0
                        this.noSlideT = 0.0
                        this.settledForOdds = false
                        # randomize delay between 1000-2000 ms
                        this.oddsDelayMs = 1000.0 + rand() * 1000.0
                    end
                end,
                fontSize = 48,
                anchor = :centerRight,
                anchorOffset = Math.Vector2(70, 0),
                parent = panel,
                layer = 3
            )
        end

        # Allow keyboard navigation for pages (A/LEFT, D/RIGHT)
        # Only allow navigation if typing is complete or page already viewed
        mouse_pos = JulGame.InputModule.get_mouse_position()
        if !this.isZooming && !this.declineShown && typing_complete_or_viewed
            if (JulGame.InputModule.get_button_pressed("LEFT") || JulGame.InputModule.get_button_pressed("A")) && this.endReached
                if this.pageIndex > 1
                    this.pageIndex -= 1
                    this.hasQuestion = (this.pageIndex == length(this.pages))
                end
            elseif JulGame.InputModule.get_button_pressed("RIGHT") || JulGame.InputModule.get_button_pressed("D") || (!this.endReached && JulGame.InputModule.get_mouse_button_pressed(1) && mouse_pos.y > 120)
                if this.pageIndex < length(this.pages)
                    old_page = this.pageIndex
                    this.pageIndex += 1
                    
                    # Start typing effect if this is a new page
                    if !(this.pageIndex in this.viewedPages)
                        TypingEffectModule.start_typing(this.typingEffect, this.pages[this.pageIndex])
                    end
                    
                    if this.pageIndex == length(this.pages)
                        this.hasQuestion = true
                        this.yesSlideT = 0.0
                        this.noSlideT = 0.0
                        this.settledForOdds = false
                        this.oddsDelayMs = 1000.0 + rand() * 1000.0
                        this.endReached = true
                        
                        # Mark last page as viewed when reached
                        push!(this.viewedPages, this.pageIndex)
                    end
                end
            end
        end

        # 4) Choices on question page (only show when typing is complete)
        if this.pageIndex == length(this.pages) && typing_complete_or_viewed
            if this.eventResolved
                # Show Continue button after event outcome is resolved
                event_action_button(
                    "event_continue_btn",
                    () -> begin
                        # Trigger zoom/fade exit
                        this.isZooming = true
                        this.zoomT = 0.0
                        this.fadeToBlackA = 0
                        Globals.AudioManagerModule.play_audio_oneshot(Globals.get_audio_manager(), Globals.get_asset_path("sfx", "select"), false, 1.0, 0, 1)
                    end;
                    text = EventStringsModule.EVENT_STRINGS[:event_button_continue],
                    fontSize = 44,
                    size = Math.Vector2(280, 90),
                    anchor = :centerBottom,
                    anchorOffset = Math.Vector2(0, -50),
                    layer = 10
                )
            elseif this.treasureChest !== nothing
                draw_treasure_choices(this)
            elseif this.currentEvent.key == "RANDOMEVENT_RESTSITE"
                draw_rest_choices(this)
            elseif this.currentEvent.type == "Yes_No"
                # Slide in animation over 300ms
                slideTime = 0.1
                this.yesSlideT = min(this.yesSlideT + deltaTime, 2.0)
                this.noSlideT = min(this.noSlideT + deltaTime, 2.0)
                yesX = -300 + Int(round(300 * this.yesSlideT / 2))
                noX  =  300 - Int(round(300 * this.noSlideT / 2))

                event_action_button(
                    "event_yes_btn",
                    () -> begin
                        if !this.eventResolved  # Prevent spam clicks
                            _record_event_choice(this, "accept")
                            Globals.RandomEventsModule.handle_accept(this, this.currentEvent)
                            this.persistentStateManager.isFloorComplete = true
                        end
                    end;
                    text = EventStringsModule.EVENT_STRINGS[:event_button_yes],
                    fontSize = 44,
                    size = Math.Vector2(280, 90),
                    anchor = :centerLeft,
                    anchorOffset = Math.Vector2(yesX, 0),
                    color = EVENT_BUTTON_YES_COLOR
                )
                event_action_button(
                    "event_no_btn",
                    () -> begin
                        _record_event_choice(this, "decline")
                        Globals.RandomEventsModule.handle_decline(this, this.currentEvent)
                        this.persistentStateManager.isFloorComplete = true
                    end;
                    text = EventStringsModule.EVENT_STRINGS[:event_button_no],
                    fontSize = 44,
                    size = Math.Vector2(280, 90),
                    anchor = :centerRight,
                    anchorOffset = Math.Vector2(noX, 0),
                    color = EVENT_BUTTON_NO_COLOR
                )

                if !this.settledForOdds && this.yesSlideT >= slideTime && this.noSlideT >= slideTime
                    this.settledForOdds = true
                    # Keep oddsFadeT as elapsed timer post-settle
                    this.oddsFadeT = max(this.oddsFadeT, -1200.0)  # negative means wait
                end
                if this.settledForOdds
                    this.oddsFadeT += deltaTime
                    alpha = this.oddsVisibleOnce ? 255 : clamp(Int(round((this.oddsFadeT - this.oddsDelayMs) / 300.0 * 255)), 0, 255)
                    if alpha >= 255
                        this.oddsVisibleOnce = true
                    end
                    # Draw odds text group
                    if this.currentEvent.success > 0
                        DisplayTextModule.display_text(
                            "event_odds_success",
                            EventStringsModule.format_string(:event_odds_success, percent=this.currentEvent.success);
                            fontSize = 32,
                            anchor = :centerLeft,
                            anchorOffset = Math.Vector2(80, 60),
                            color = (50, 220, 80, alpha)
                        )
                    end
                    if this.currentEvent.special > 0
                        DisplayTextModule.display_text(
                            "event_odds_special",
                            EventStringsModule.format_string(:event_odds_special, percent=this.currentEvent.special);
                            fontSize = 28,
                            anchor = :centerLeft,
                            anchorOffset = Math.Vector2(80, 100),
                            color = (80, 160, 255, alpha)
                        )
                    end
                    if this.currentEvent.failure > 0
                        DisplayTextModule.display_text(
                            "event_odds_failure",
                            EventStringsModule.format_string(:event_odds_failure, percent=this.currentEvent.failure);
                            fontSize = 32,
                            anchor = :centerLeft,
                            anchorOffset = Math.Vector2(80, 140),
                            color = (220, 60, 60, alpha)
                        )
                    end
                end
            elseif this.currentEvent.type == "Multiple_Choice"
                # Show multiple choice buttons
                choice1 = JulGame.ImmediateUIModule.immediate_button(
                    "event_choice_1_btn",
                    () -> begin
                        @debug "Choice 1"
                        _record_event_choice(this, "1_1")
                        Globals.RandomEventsModule.handle_choice(this, this.currentEvent, "1_1")
                        this.persistentStateManager.isFloorComplete = true
                    end;
                    text = this.currentEvent.choice_1_1,
                    fontSize = 32,
                    size = Math.Vector2(1000, 90),
                    anchor = :centerBottom,
                    anchorOffset = Math.Vector2(0, -100),
                    buttonUpPath = "pixel.png",
                    buttonDownPath = "pixel.png",
                    color = (0, 0, 0, 255),
                )
                if length(choice1.hoverEnterEvents) == 0
                    enterEvent = () -> begin
                        choice1.color = (50, 50, 50, 255)
                    end
                    exitEvent = () -> begin
                        choice1.color = (0, 0, 0, 255)
                    end
                    push!(choice1.hoverEnterEvents, enterEvent)
                    push!(choice1.hoverExitEvents, exitEvent)
                end
    
                choice2 = JulGame.ImmediateUIModule.immediate_button(
                    "event_choice_2_btn",
                    () -> begin
                        @debug "Choice 2"
                        _record_event_choice(this, "1_2")
                        Globals.RandomEventsModule.handle_choice(this, this.currentEvent, "1_2")
                        this.persistentStateManager.isFloorComplete = true
                    end;
                    text = this.currentEvent.choice_1_2,
                    fontSize = 32,
                    size = Math.Vector2(1000, 90),
                    anchor = :centerBottom,
                    anchorOffset = Math.Vector2(0, 0),
                    buttonUpPath = "pixel.png",
                    buttonDownPath = "pixel.png",
                    color = (0, 0, 0, 255)
                )
                if length(choice2.hoverEnterEvents) == 0
                    enterEvent = () -> begin
                        choice2.color = (50, 50, 50, 255)
                    end
                    push!(choice2.hoverEnterEvents, enterEvent)
                end
                if length(choice2.hoverExitEvents) == 0
                    exitEvent = () -> begin
                        choice2.color = (0, 0, 0, 255)
                    end
                    push!(choice2.hoverExitEvents, exitEvent)
                end
            elseif this.currentEvent.key == "RANDOMEVENT_THREEDOORS"
                event_action_button(
                    "event_leave_btn",
                    () -> begin
                        if !this.eventResolved
                            _record_event_choice(this, "leave")
                            Globals.RandomEventsModule.handle_choice(this, this.currentEvent, "leave")
                            this.persistentStateManager.isFloorComplete = true
                        end
                    end;
                    text = EventStringsModule.EVENT_STRINGS[:three_doors_leave],
                    fontSize = 44,
                    size = Math.Vector2(280, 90),
                    anchor = :centerBottom,
                    anchorOffset = Math.Vector2(0, -50),
                    layer = 10
                )
            end
        else
            # If leaving question page but odds were already shown, keep them visible when returning
            if this.oddsVisibleOnce
                # no-op; state preserved
            else
                this.oddsFadeT = 0.0
                this.settledForOdds = false
            end
        end

        # 5) Decline page handling
        if this.declineShown
            this.declineTimer += deltaTime
            if this.declineTimer >= 0.8
                exit_event(this)
                return
            end
        end
    end


    function _record_event_choice(this, choice::AbstractString)
        ev = this.currentEvent
        key = ev !== nothing && hasproperty(ev, :key) ? string(ev.key) : ""
        JulGame.UserGlobals["Module"].RunRecorderModule.record!("event_choice"; event = key, choice = String(choice))
    end

end
