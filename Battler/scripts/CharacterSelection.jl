module CharacterSelectionModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.EffectsModule
    using JulGame.EffectRendererModule
    using JulGame.UI.UIImageModule
    using ..Scripts
    include("utils/FloatingAnimation.jl")
    using .FloatingAnimationModule
    include("utils/UIFloatingAnimation.jl")
    using .UIFloatingAnimationModule
    include("localization/ui_strings.jl")
    using .UIStringsModule

    # Pre-built immediate UI is updated by mutating cached elements; default lifetime (-1) expires
    # widgets not re-invoked through immediate_* every frame, so they get destroyed while refs linger.
    const _CHARSEL_IMMEDIATE_LIFETIME = JulGame.ImmediateUIModule.INFINITE_LIFETIME

    # Screen-thirds click zones (previous / current / next). Everything decorative sits below them;
    # piece icons sit just above (for hover tooltips) and forward clicks; buttons sit on top.
    const _CLICK_ZONES = (("click_zone_left", :topLeft, -1), ("click_zone_center", :centerTop, 0), ("click_zone_right", :topRight, 1))
    const _CLICK_ZONE_LAYER = 50
    const _PIECE_ICON_LAYER = 55
    const _BUTTON_LAYER = 60

    const _START_BUTTON_OFFSET = Math.Vector2(5, -25)
    const _START_BUTTON_SIZE = Math.Vector2(500, 275)
    const _START_JUICE_ID = "charsel_start"

    mutable struct CharacterSelection
        isActive::Bool
        characters::Vector
        selectedCharacterIndex::Int
        previousCharacterIndex::Int
        isCharacterSelected::Bool
        transitionManager

        # Animation state
        characterOffsets::Dict{Int, Float64}
        targetOffsets::Dict{Int, Float64}
        animationSpeed::Float64

        # Start button animation
        startButtonOffset::Float64
        startButtonTargetOffset::Float64

        # Dancing animation for selected character
        danceTime::Float64
        danceConfig::Dict{String, Any}

        # Floating animation for selected character
        selectedCharacterFloating::UIFloatingAnimation

        # Transition state (removed - using SceneTransitionModule instead)

        # Starting pieces (hardcoded for now)
        # TODO: Parse from character data field (comma-separated list)
        # Example in character data: starting_pieces = "SWORD,SHIELD,FIRE,BOOT,POTION,GEM"
        startingPieces::Vector{String}

        # Cached UI elements
        cachedUI::Dict{String, Any}
        isInitialized::Bool

        # UIImages whose effect textures still need baking. Drained a few per
        # frame from the title screen (pump_effect_warm_queue!) so startup
        # doesn't pay for all bakes at once; open() force-bakes any remainder.
        effectWarmQueue::Vector{Any}

        # True after Start until next open/close/init — hides char-select UI without flipping Title to main-menu mode.
        transitioning_to_run::Bool

        # Character order (specify which characters appear first by key)
        # Empty vector means use default dictionary order
        characterOrder::Vector{String}

        # Avoid re-applying preview pieces every frame; reset in open().
        lastPreviewedCharacterKey::String

        function CharacterSelection()
            this = new()
            this.isActive = false
            this.characters = []
            this.selectedCharacterIndex = 1
            this.previousCharacterIndex = 1
            this.isCharacterSelected = false

            # Animation defaults
            this.characterOffsets = Dict{Int, Float64}()
            this.targetOffsets = Dict{Int, Float64}()
            this.animationSpeed = 800.0

            this.startButtonOffset = 0.0
            this.startButtonTargetOffset = 0.0

            # Initialize dancing animation
            this.danceTime = 0.0
            this.danceConfig = Dict(
                "speed" => 1.0,           # Overall animation speed multiplier
                "bounce_height" => 15.0,  # How high the character bounces
                "wiggle_intensity" => 12.0, # How much side-to-side wiggle
                "bounce_rhythm" => 1.2,   # Bounce frequency (higher = faster bounces)
                "wiggle_rhythm" => 1.8,   # Wiggle frequency (higher = faster wiggles)
                "subtlety" => 0.7         # Overall subtlety (0.0 = subtle, 1.0 = very noticeable)
            )

            # Initialize floating animation for selected character (UI-compatible version)
            this.selectedCharacterFloating = UIFloatingAnimation(
                speed = 1.5,
                verticalAmplitude = 20.0,     # Increased for visibility
                horizontalAmplitude = 15.0,  # Increased for visibility
                rotationAmplitude = 8.0       # Increased for visibility
            )

            # Hardcoded starting pieces
            this.startingPieces = ["SWORD", "SHIELD", "FIRE", "BOOT", "POTION", "GEM"]

            # Initialize cached UI elements
            this.cachedUI = Dict{String, Any}()
            this.isInitialized = false
            this.effectWarmQueue = Any[]
            this.transitioning_to_run = false

            # Initialize character order (empty = default dictionary order)
            this.characterOrder = ["CHARACTER_MAGICIAN", "CHARACTER_DEMOLITIONIST", "CHARACTER_KNIGHT"]

            this.lastPreviewedCharacterKey = ""

            return this
        end
    end

    function initialize(this::CharacterSelection)
        globals = JulGame.UserGlobals["Module"]
        characterData = globals.get_data_manager().characters_data

        # Load characters in specified order, or default order if characterOrder is empty
        if !isempty(this.characterOrder)
            # Use specified order
            for key in this.characterOrder
                if haskey(characterData, key)
                    push!(this.characters, characterData[key])
                end
            end
            # Add any remaining characters not in the order list
            for (key, character) in characterData
                if !(key in this.characterOrder)
                    push!(this.characters, character)
                end
            end
        else
            # Use default dictionary order
            for (key, character) in characterData
                push!(this.characters, character)
            end
        end

        # Initialize character offsets
        for i in 1:length(this.characters)
            this.characterOffsets[i] = 0.0
            this.targetOffsets[i] = 0.0
        end

        # Pre-create all UI elements to avoid performance hit when opening
        @time "charsel init: pre_initialize_ui" pre_initialize_ui(this, globals)

        this.isInitialized = true
        hide_cached_character_selection_ui!(this)
        sync_starting_pieces_for_selected_character!(this)

        # Warm piece description / data paths so first hover isn't a JIT lump.
        for p in this.startingPieces
            get_piece_description(p)
        end

        # Effect textures are baked a few per frame from the title screen
        # (pump_effect_warm_queue!) instead of all at once here — baking every
        # BevelEmboss/OuterGlow synchronously costs seconds of startup time.
        queue_effect_warm_jobs!(this)

        this.transitioning_to_run = false
    end

    """Collect every cached UIImage with effects into the warm queue for incremental baking."""
    function queue_effect_warm_jobs!(this::CharacterSelection)
        empty!(this.effectWarmQueue)
        seen = Set{UInt}()
        for el in values(this.cachedUI)
            el isa JulGame.UI.UIImageModule.UIImage || continue
            isempty(el.effects) && continue
            oid = objectid(el)
            oid in seen && continue
            push!(seen, oid)
            push!(this.effectWarmQueue, el)
        end
    end

    """Bake up to `max_bakes` queued effect textures. Called once per frame from the title screen."""
    function pump_effect_warm_queue!(this::CharacterSelection; max_bakes::Int = 1)
        this.isInitialized || return
        JulGame.Renderer == C_NULL && return
        baked = 0
        while !isempty(this.effectWarmQueue) && baked < max_bakes
            el = popfirst!(this.effectWarmQueue)
            if el.texture == C_NULL && el.surface != C_NULL
                JulGame.UI.initialize(el)
            end
            el.needsEffectUpdate = true
            JulGame.UI.UIImageModule.update_effects(el)
            baked += 1
        end
    end

    effect_warm_pending(this::CharacterSelection)::Bool = !isempty(this.effectWarmQueue)

    function pre_initialize_ui(this::CharacterSelection, globals)
        # Pre-create starting pieces UI
        pre_initialize_starting_pieces(this, globals)

        # Pre-create character sprites
        pre_initialize_characters(this, globals)

        # Pre-create treasure info UI
        pre_initialize_treasure_info(this, globals)

        # Pre-create start button UI
        pre_initialize_start_button(this, globals)

        # Pre-create back button UI
        pre_initialize_back_button(this, globals)

        # Pre-create title and name text
        pre_initialize_title_ui(this, globals)

        # Pre-create settings gear
        pre_initialize_settings_gear(this, globals)

        # Pre-create spotlight images
        pre_initialize_spotlight(this, globals)

        # Pre-create invisible screen-thirds click zones
        pre_initialize_click_zones(this, globals)
    end

    function _screen_size()
        camera = JulGame.MAIN.scene.camera
        return camera === nothing ? Math.Vector2(1920, 1080) : camera.size
    end

    """Which click zone (-1 previous, 0 current, 1 next) contains screen x."""
    function zone_delta_at(x::Real)::Int
        third = _screen_size().x / 3
        return x < third ? -1 : (x >= 2 * third ? 1 : 0)
    end

    function pre_initialize_click_zones(this::CharacterSelection, globals)
        screen = _screen_size()
        for (key, anchor, delta) in _CLICK_ZONES
            this.cachedUI[key] = JulGame.ImmediateUIModule.immediate_rect(
                key;
                anchor = anchor,
                size = Math.Vector2(screen.x / 3, screen.y),
                color = (0, 0, 0, 0),
                layer = _CLICK_ZONE_LAYER,
                clickEvent = () -> select_relative!(this, delta),
                lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
            )
        end
    end

    """Neighbor offset of the hovered click zone (0 when none / center)."""
    function hovered_zone_delta(this::CharacterSelection)::Int
        for (key, _, delta) in _CLICK_ZONES
            this.cachedUI[key].isHovered && return delta
        end
        return 0
    end

    function select_relative!(this::CharacterSelection, delta::Int)
        this.transitioning_to_run && return
        newIndex = clamp(this.selectedCharacterIndex + delta, 1, length(this.characters))
        newIndex == this.selectedCharacterIndex && return

        # Trigger character slide animation if selection changed
        this.previousCharacterIndex = this.selectedCharacterIndex
        this.selectedCharacterIndex = newIndex
        calculate_character_positions(this)
        # Reset floating animation UI element reference when selection changes
        this.selectedCharacterFloating.uiElement = nothing
    end

    function hide_cached_character_selection_ui!(this::CharacterSelection)
        this.isInitialized || return
        for el in values(this.cachedUI)
            el.isActive = false
        end
    end

    function render_character_select_name!(charName::String)
        # name_el = DisplayTextModule.display_text(
        #     "char_select_name",
        #     charName;
        #     fontSize = 48,
        #     anchor = :centerTop,
        #     anchorOffset = Math.Vector2(0, 65),
        #     fontPath = "Century-Normal.ttf",
        #     color = (100, 200, 255, 255),
        #     layer = 20,
        #     isActive = true,
        # )
        # if isempty(name_el.effects)
        #     JulGame.apply_effects!(name_el, STYLE_NAME)
        # end
        DisplayTextModule.display_text(
            "char_select_name",
            charName;
            fontSize = 48,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 65),
            fontPath = "Century-Normal.ttf",
            color = (100, 200, 255, 255),
            layer = 20,
            isActive = true,
        )
    end

    function render_character_select_stats!(statsText::String; isActive::Bool = true)
        DisplayTextModule.display_text(
            "char_select_stats",
            statsText;
            fontSize = 28,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 120),
            fontPath = "Century-Normal.ttf",
            color = (220, 220, 220, 255),
            layer = 20,
            isActive = isActive,
        )
    end

    function pre_initialize_starting_pieces(this::CharacterSelection, globals)
        # Create starting pieces label
        this.cachedUI["starting_pieces_label"] = DisplayTextModule.display_text(
            "starting_pieces_label",
            UIStringsModule.UI_STRINGS[:character_starting_pieces];
            fontSize = 32,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(20, 100),
            fontPath = "Century-Normal.ttf",
            color = (255, 255, 255, 255),
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["starting_pieces_label"], STYLE_BODY)

        # Create piece icons
        startX = 5.0
        startY = 125.0
        spacing = 105.0

        for (i, pieceType) in enumerate(this.startingPieces)
            col = mod(i - 1, 6)
            x = startX + (col * spacing)
            y = startY
            spritePath = get_piece_sprite_path(pieceType)

            # UIImage: changing `path` reloads art. ScreenButton only updates path strings and
            # re-textures old surfaces, so icons would stay stale when swapping characters.
            zoneDelta = zone_delta_at(x + 64)
            icon = JulGame.ImmediateUIModule.immediate_image(
                "piece_icon_$i",
                spritePath;
                anchor = :topLeft,
                anchorOffset = Math.Vector2(x, y),
                size = Math.Vector2(128, 128),
                layer = _PIECE_ICON_LAYER,
                clickEvents = Function[() -> select_relative!(this, zoneDelta)],
                lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
                forceClickCheck = true,
            )

            if length(icon.hoverEnterEvents) == 0
                push!(icon.hoverEnterEvents, () -> begin
                    icon.useEffectTexture = true
                end)
            end
            if length(icon.hoverExitEvents) == 0
                push!(icon.hoverExitEvents, () -> begin
                    icon.useEffectTexture = false
                end)
            end

            this.cachedUI["piece_icon_$i"] = icon
        end
    end

    function pre_initialize_characters(this::CharacterSelection, globals)
        scale = 0.75
        glow = [
            OuterGlowEffect(
                radius=20,
                color=(255,255,200,220),
                fade_amount=1.8,
                fade_curve=15.5,
                force_white=true
            )
        ]
        for (i, character) in enumerate(this.characters)
            # Knight swaps art when selected. Two images stay loaded so the swap
            # does not reload the PNG and rebake the glow.
            paths = String[get_character_sprite_path(character)]
            if is_demo_silhouette(character)
                hi = night_silhouette_path(true)
                hi !== nothing && push!(paths, hi)
            end
            for (variant, spritePath) in enumerate(paths)
                id = variant == 1 ? "char_sprite_$i" : "char_sprite_$(i)_hi"
                button = JulGame.ImmediateUIModule.immediate_image(
                    id,
                    spritePath;
                    anchor = :center,
                    anchorOffset = Math.Vector2(0, -100),
                    size = Math.Vector2(415 * scale, 692 * scale),
                    layer = 5,
                    color = (255, 255, 255, 255),
                    lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
                )
                JulGame.apply_effects!(button, glow)
                button.useEffectTexture = false
                button.isActive = false
                this.cachedUI[id] = button
            end
        end
    end

    function _treasure_asset_slug(key)::String
        parts = split(string(key), "_"; keepempty=false)
        return length(parts) >= 2 ? lowercase(parts[2]) : "unknown"
    end

    """Valid image path for treasure_icon before the first `update_treasure_info` (never use \"\" — effect warm-up and loaders require a real file)."""
    function _default_treasure_icon_path(this::CharacterSelection, globals)::String
        if !isempty(this.characters)
            c0 = this.characters[1]
            td = globals.get_data_manager().treasure_data
            if haskey(td, c0.treasure)
                tr = td[c0.treasure]
                tn = _treasure_asset_slug(tr.key)
                p = globals.get_asset_path("treasure", tn)
                if !isempty(strip(p))
                    return p
                end
            end
        end
        return get_piece_sprite_path("GEM")
    end

    function _treasure_icon_cache_key(treasure_key)::String
        safe = lowercase(replace(string(treasure_key), r"[^a-zA-Z0-9_]" => "_"))
        return "treasure_icon_$safe"
    end

    function _treasure_name_cache_key(treasure_key)::String
        safe = lowercase(replace(string(treasure_key), r"[^a-zA-Z0-9_]" => "_"))
        return "treasure_name_$safe"
    end

    function _activate_desc_cache_key(treasure_key)::String
        safe = lowercase(replace(string(treasure_key), r"[^a-zA-Z0-9_]" => "_"))
        return "activate_desc_$safe"
    end

    const CHARACTER_PASSIVE_STRINGS = Dict(
        "CHARACTER_MAGICIAN" => :character_passive_magician,
        "CHARACTER_DEMOLITIONIST" => :character_passive_demolitionist,
    )

    function _passive_desc_cache_key(character_key)::String
        safe = lowercase(replace(string(character_key), r"[^a-zA-Z0-9_]" => "_"))
        return "passive_desc_$safe"
    end

    function _set_all_treasure_icons_active!(this::CharacterSelection, is_active::Bool)
        for (key, el) in this.cachedUI
            key == "treasure_icon" && continue
            startswith(key, "treasure_icon_") || continue
            el isa JulGame.UI.UIImageModule.UIImage || continue
            el.isActive = is_active
        end
    end

    function _set_all_treasure_texts_active!(this::CharacterSelection, is_active::Bool)
        for (key, el) in this.cachedUI
            if startswith(key, "treasure_name_") || startswith(key, "activate_desc_") || startswith(key, "passive_desc_")
                el.isActive = is_active
            end
        end
    end

    function pre_initialize_treasure_info(this::CharacterSelection, globals)
        # Treasure name fallback
        this.cachedUI["treasure_name"] = DisplayTextModule.display_text(
            "treasure_name",
            UIStringsModule.UI_STRINGS[:character_unknown_treasure];
            fontSize = 32,
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(200, -250),
            color = (0, 246, 255, 255),
            fontPath = "Century-Normal.ttf",
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["treasure_name"], STYLE_NAME)
        this.cachedUI["treasure_name_fallback"] = this.cachedUI["treasure_name"]

        treasure_glow_effects = [
            OuterGlowEffect(
                radius=20,
                color=(255,255,0,220),
                fade_amount=0.8,
                fade_curve=20.5,
                force_white=true
            )
        ]
        td = globals.get_data_manager().treasure_data
        created_any_icon = false
        for ch in this.characters
            haskey(td, ch.treasure) || continue
            tr = td[ch.treasure]
            treasure_name = _treasure_asset_slug(tr.key)
            path = globals.get_asset_path("treasure", treasure_name)
            isempty(strip(path)) && continue
            key = _treasure_icon_cache_key(tr.key)
            haskey(this.cachedUI, key) && continue
            icon = JulGame.ImmediateUIModule.immediate_image(
                key,
                path;
                anchor = :bottomLeft,
                anchorOffset = Math.Vector2(0, -50),
                size = Math.Vector2(200, 200),
                layer = 10,
                lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
            )
            JulGame.apply_effects!(icon, treasure_glow_effects)
            icon.isActive = false
            this.cachedUI[key] = icon
            if !haskey(this.cachedUI, "treasure_icon")
                this.cachedUI["treasure_icon"] = icon
            end
            created_any_icon = true
        end

        # Fallback icon if no character treasure image could be resolved.
        if !created_any_icon
            fallback_icon = JulGame.ImmediateUIModule.immediate_image(
                "treasure_icon_fallback",
                _default_treasure_icon_path(this, globals);
                anchor = :bottomLeft,
                anchorOffset = Math.Vector2(0, -50),
                size = Math.Vector2(200, 200),
                layer = 10,
                lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
            )
            JulGame.apply_effects!(fallback_icon, treasure_glow_effects)
            fallback_icon.isActive = false
            this.cachedUI["treasure_icon_fallback"] = fallback_icon
            this.cachedUI["treasure_icon"] = fallback_icon
        end

        # Activate label
        this.cachedUI["activate_label"] = DisplayTextModule.display_text(
            "activate_label",
            UIStringsModule.UI_STRINGS[:character_activate_label];
            fontSize = 32,
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(200, -180),
            color = (255, 252, 0, 255),
            fontPath = "Century-Normal.ttf",
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["activate_label"], STYLE_SECTION_LABEL_ACTIVE)

        # Activate description fallback
        this.cachedUI["activate_desc"] = DisplayTextModule.display_text(
            "activate_desc",
            UIStringsModule.UI_STRINGS[:character_no_description];
            fontSize = 32,
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(this.cachedUI["activate_label"].size.x + this.cachedUI["activate_label"].anchorOffset.x + 5, -178),
            color = (255, 254, 187, 255),
            maxLineWidth = 400,
            wrapWords = true,
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["activate_desc"], STYLE_BODY_ACTIVE)
        this.cachedUI["activate_desc_fallback"] = this.cachedUI["activate_desc"]
        this.cachedUI["treasure_name"].isActive = false
        this.cachedUI["activate_desc"].isActive = false

        # Pre-create static treasure name/description text by treasure key.
        for ch in this.characters
            haskey(td, ch.treasure) || continue
            tr = td[ch.treasure]

            name_key = _treasure_name_cache_key(tr.key)
            if !haskey(this.cachedUI, name_key)
                tname = tr.name !== nothing ? tr.name : UIStringsModule.UI_STRINGS[:character_unknown_treasure]
                name_ui = DisplayTextModule.display_text(
                    name_key,
                    tname;
                    fontSize = 32,
                    anchor = :bottomLeft,
                    anchorOffset = Math.Vector2(200, -250),
                    color = (0, 246, 255, 255),
                    fontPath = "Century-Normal.ttf",
                    lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
                )
                JulGame.apply_effects!(name_ui, STYLE_NAME)
                name_ui.isActive = false
                this.cachedUI[name_key] = name_ui
            end

            desc_key = _activate_desc_cache_key(tr.key)
            if !haskey(this.cachedUI, desc_key)
                adesc = tr.description !== nothing ? tr.description : UIStringsModule.UI_STRINGS[:character_no_description]
                desc_ui = DisplayTextModule.display_text(
                    desc_key,
                    adesc;
                    fontSize = 32,
                    anchor = :bottomLeft,
                    anchorOffset = Math.Vector2(this.cachedUI["activate_label"].size.x + this.cachedUI["activate_label"].anchorOffset.x + 5, -178),
                    color = (255, 254, 187, 255),
                    maxLineWidth = 1200,
                    wrapWords = true,
                    lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
                )
                JulGame.apply_effects!(desc_ui, STYLE_BODY_ACTIVE)
                desc_ui.isActive = false
                this.cachedUI[desc_key] = desc_ui
            end
        end

        # Passive label
        this.cachedUI["passive_label"] = DisplayTextModule.display_text(
            "passive_label",
            UIStringsModule.UI_STRINGS[:character_passive_label];
            fontSize = 32,
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(200, -90),
            color = (131, 131, 131, 255),
            fontPath = "Century-Normal.ttf",
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["passive_label"], STYLE_SECTION_LABEL_PASSIVE)

        # Passive description fallback, then one static text per character.
        passive_offset = Math.Vector2(this.cachedUI["passive_label"].size.x + this.cachedUI["passive_label"].anchorOffset.x + 5, -88)
        make_passive_desc(id, text) = begin
            ui = DisplayTextModule.display_text(
                id,
                text;
                fontSize = 32,
                anchor = :bottomLeft,
                anchorOffset = passive_offset,
                color = (206, 206, 206, 255),
                maxLineWidth = 1200,
                wrapWords = true,
                lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
            )
            JulGame.apply_effects!(ui, STYLE_BODY_DIM)
            ui.isActive = false
            ui
        end
        this.cachedUI["passive_desc"] = make_passive_desc("passive_desc", UIStringsModule.UI_STRINGS[:character_no_passive])
        this.cachedUI["passive_desc_fallback"] = this.cachedUI["passive_desc"]
        for ch in this.characters
            key = _passive_desc_cache_key(ch.key)
            haskey(this.cachedUI, key) && continue
            haskey(CHARACTER_PASSIVE_STRINGS, ch.key) || continue
            this.cachedUI[key] = make_passive_desc(key, UIStringsModule.UI_STRINGS[CHARACTER_PASSIVE_STRINGS[ch.key]])
        end
    end

    function pre_initialize_start_button(this::CharacterSelection, globals)
        # Start button rect
        this.cachedUI["start_button_rect"] = JulGame.ImmediateUIModule.immediate_rect(
            "start_button_rect";
            anchor = :bottomRight,
            anchorOffset = _START_BUTTON_OFFSET,
            size = _START_BUTTON_SIZE,
            color = (3, 60, 5, 50),
            layer = _BUTTON_LAYER,
            borderWidth = 4,
            borderColor = (255, 255, 255, 255),
            clickEvent = () -> press_start!(this),
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["start_button_rect"], [
            RoughEdgeEffect(amount=1, seed=42, erosion=true),
            GradientEffect(; gradientType="LinearGradient", stops=[(0.0, (255, 255, 255, 255)), (1.0, (0, 0, 0, 255))], angle=0.0)
        ])

        # Start button text
        this.cachedUI["start_button"] = DisplayTextModule.display_text(
            "start_button",
            UIStringsModule.UI_STRINGS[:character_start_button];
            fontSize = 128,
            anchor = :center,
            color = (100, 255, 150, 255),
            fontPath = "Century-Normal.ttf",
            layer = _BUTTON_LAYER + 1,
            parent = this.cachedUI["start_button_rect"],
            clickEvent = () -> press_start!(this),
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["start_button"], STYLE_START_BUTTON)
    end

    function pre_initialize_back_button(this::CharacterSelection, globals)
        this.cachedUI["back_button_rect"] = JulGame.ImmediateUIModule.immediate_rect(
            "back_button_rect";
            anchor = :topLeft,
            anchorOffset = Math.Vector2(-5, -5),
            size = Math.Vector2(250, 100), 
            color = (30, 5, 5, 80),
            layer = _BUTTON_LAYER,
            borderWidth = 4,
            borderColor = (255, 255, 255, 255),
            clickEvent = () -> this.transitioning_to_run || close(this),
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["back_button_rect"], [
            JulGame.EffectsModule.RoughEdgeEffect(; amount=1, seed=42, erosion=true),
            #JulGame.EffectsModule.GradientEffect(; gradientType="LinearGradient", stops=[(0.0, (255, 255, 255, 255)), (1.0, (0, 0, 0, 255))], angle=180.0)
        ])

        this.cachedUI["back_button"] = DisplayTextModule.display_text(
            "back_button",
            UIStringsModule.UI_STRINGS[:character_back_button];
            fontSize = 64,
            anchor = :center,
            color = (255, 50, 50, 255),
            fontPath = "Century-Normal.ttf",
            layer = _BUTTON_LAYER + 1,
            parent = this.cachedUI["back_button_rect"],
            clickEvent = () -> this.transitioning_to_run || close(this),
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["back_button"], STYLE_START_BUTTON)
    end
    function pre_initialize_title_ui(this::CharacterSelection, globals)
        # Title text
        this.cachedUI["char_select_title"] = DisplayTextModule.display_text(
            "char_select_title",
            UIStringsModule.UI_STRINGS[:character_select_title];
            fontSize = 28,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 30),
            fontPath = "Century-Normal.ttf",
            color = (200, 200, 200, 255),
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        JulGame.apply_effects!(this.cachedUI["char_select_title"], STYLE_TITLE)

        this.cachedUI["char_locked_label"] = DisplayTextModule.display_text(
            "char_locked",
            UIStringsModule.UI_STRINGS[:character_locked];
            fontSize = 32,
            anchor = :center,
            anchorOffset = Math.Vector2(0, 250),
            color = (150, 150, 150, 255),
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
        this.cachedUI["char_locked_label"].isActive = false
    end

    function pre_initialize_settings_gear(this::CharacterSelection, globals)
        settingsClickEvent = () -> begin
            this.transitioning_to_run && return
            sdm = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[6]
            Scripts.SettingsDisplayManagerModule.open!(sdm)
            globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "settings"), false, 1.0, 0, 1)
        end

        this.cachedUI["settings_gear"] = JulGame.ImmediateUIModule.immediate_image(
            "settings_gear",
            globals.get_asset_path("ui", "settingsbutton");
            anchor = :topRight,
            anchorOffset = Math.Vector2(-30, 30),
            size = Math.Vector2(128, 128),
            clickEvents = Function[settingsClickEvent],
            layer = _BUTTON_LAYER,
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
    end

    function pre_initialize_spotlight(this::CharacterSelection, globals)
        this.cachedUI["spotlight_bottom"] = JulGame.ImmediateUIModule.immediate_image(
            "char_spotlight_bottom",
            globals.get_asset_path("menu", "spotlightbottom");
            anchor = :center,
            anchorOffset = Math.Vector2(0, -150),
            size = Math.Vector2(937, 838),
            color = (255, 255, 255, 255),
            layer = 0,
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )

        this.cachedUI["spotlight_top"] = JulGame.ImmediateUIModule.immediate_image(
            "char_spotlight_top",
            globals.get_asset_path("menu", "spotlighttop");
            anchor = :centerTop,
            size = Math.Vector2(549, 367),
            color = (255, 255, 255, 255),
            layer = 10,
            parent = this.cachedUI["spotlight_bottom"],
            lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
        )
    end

    # === Text Styles matching UI mock ===
    const STYLE_TITLE = [
        # StrokeEffect(width=2, color=(0,0,0,255)),
        OuterGlowEffect(radius=4, color=(0,0,0,100), blur=0.7)
    ]

    const STYLE_NAME = [
        JulGame.EffectsModule.DropShadowEffect(; distance=5.0, angle=135.0, blur_radius=5, color=(0, 0, 0, 255), opacity=180)
    ]

    const STYLE_SECTION_LABEL_ACTIVE = [
        StrokeEffect(width=2, color=(0,0,0,255)),
        OuterGlowEffect(radius=5, color=(0,0,0,120), blur=0.6)
    ]
    const STYLE_SECTION_LABEL_PASSIVE = [
        StrokeEffect(width=2, color=(0,0,0,255)),
        OuterGlowEffect(radius=5, color=(0,0,0,120), blur=0.6)
    ]

    const STYLE_BODY = [
        StrokeEffect(width=2, color=(0,0,0,255))
    ]

    const STYLE_BODY_ACTIVE = [
        StrokeEffect(width=2, color=(0,0,0,255)),
        OuterGlowEffect(radius=5, color=(0,0,0,120), blur=0.6)
    ]

    const STYLE_BODY_DIM = [
        StrokeEffect(width=2, color=(0,0,0,255)),
        OuterGlowEffect(radius=5, color=(0,0,0,120), blur=0.6)
    ]

    const STYLE_START_BUTTON = [
        BevelEmbossEffect(; style=LAYER_INNER_BEVEL, size_px=16, soften=2.9999995f0, depth=62, angle=90.0, altitude=61.0, direction_up=true, contour_enabled=false, range_pct=100, contour_lut=identity_emboss_lut(), contour_antialiased=true, gloss_enabled=true, gloss_lut=identity_emboss_lut(), gloss_antialiased=false, texture_enabled=false, texture_path="", texture_tile=true, texture_scale=100, texture_phase_h_pct=0, texture_phase_v_pct=0, texture_align_with_layer=true, texture_depth=50.0, texture_invert=false, highlight_color=(255, 255, 255, 255), shadow_color=(35, 15, 35, 255), highlight_opacity=166, shadow_opacity=140, highlight_blend=BB_NORMAL, shadow_blend=BB_OVERLAY, intensity=1.0),
        RoughEdgeEffect(; amount=3, seed=42001, erosion=true)
    ]

    function open(this::CharacterSelection)
        this.transitioning_to_run = false
        this.isActive = true
        this.isCharacterSelected = false
        this.lastPreviewedCharacterKey = ""
        this.selectedCharacterIndex = 1
        this.previousCharacterIndex = 1
        this.startButtonOffset = 0.0
        calculate_character_positions(this)
        JulGame.ImmediateUIModule.remove_immediate_component("char_select_name")
        JulGame.ImmediateUIModule.remove_immediate_component("char_select_stats")
        if this.isInitialized
            # Bake anything the per-frame pump hasn't gotten to yet, so the
            # first character-select frame isn't multi-second.
            pump_effect_warm_queue!(this; max_bakes = length(this.effectWarmQueue))
            display_ui(this)
        end
    end

    function close(this::CharacterSelection)
        this.transitioning_to_run = false
        this.isActive = false
        this.isCharacterSelected = false
        JulGame.ImmediateUIModule.remove_immediate_component("char_select_name")
        JulGame.ImmediateUIModule.remove_immediate_component("char_select_stats")
        hide_cached_character_selection_ui!(this)
    end

    function is_character_available(characterIndex::Int)::Bool
        # Characters 1-2 are available, rest are locked
        return characterIndex <= 2
    end

    is_demo_silhouette(character)::Bool =
        Scripts.MapFloorSystemModule.IS_DEMO && string(character.key) == "CHARACTER_KNIGHT"

    """Demo knight art: `character-knightsilhouette` / `character-knightsilhouettehighlighted`."""
    function night_silhouette_path(highlighted::Bool)::Union{Nothing,String}
        globals = JulGame.UserGlobals["Module"]
        slug = highlighted ? "knightsilhouettehighlighted" : "knightsilhouette"
        globals.AssetManager.asset_exists("character", slug) || return nothing
        return globals.get_asset_path("character", slug)
    end

    function parse_character_starting_pieces(character)::Vector{String}
        pieces = String[]
        if !hasproperty(character, :starting_pieces) || character.starting_pieces === nothing
            return pieces
        end

        for piece_key in split(string(character.starting_pieces), ",")
            trimmed_key = strip(piece_key)
            if trimmed_key != ""
                push!(pieces, trimmed_key)
            end
        end

        return pieces
    end

    function sync_starting_pieces_for_selected_character!(this::CharacterSelection)
        if this.selectedCharacterIndex < 1 || this.selectedCharacterIndex > length(this.characters)
            this.startingPieces = String[]
            return
        end

        selectedCharacter = this.characters[this.selectedCharacterIndex]
        this.startingPieces = parse_character_starting_pieces(selectedCharacter)
    end

    """Keep User in sync with the highlighted character while browsing (available slots only)."""
    function sync_user_preview_from_selection!(this::CharacterSelection, globals, isAvailable::Bool)
        user = globals.get_user_data()
        user === nothing && return
        if !isAvailable || this.selectedCharacterIndex < 1 || this.selectedCharacterIndex > length(this.characters)
            return
        end

        char = this.characters[this.selectedCharacterIndex]
        if char.key == this.lastPreviewedCharacterKey
            return
        end
        this.lastPreviewedCharacterKey = char.key

        user.selectedCharacter = char.key
        user.shadowCloakUsed = false
        pcs = globals.UserModule.load_default_pieces_from_character(user, char.key)
        if isempty(pcs)
            globals.UserModule.load_default_pieces(user)
        else
            user.pieces = pcs
        end
    end

    """Map character-select shorthand or a full `PIECE_*` key to a key in `PiecesModule.ALL_PIECES`."""
    function resolve_starting_piece_key(pieceType::String)::Union{Nothing,String}
        globals = JulGame.UserGlobals["Module"]
        pm = globals.PiecesModule
        normalized_piece_type = uppercase(strip(pieceType))
        if startswith(normalized_piece_type, "PIECE_") && haskey(pm.ALL_PIECES, normalized_piece_type)
            return normalized_piece_type
        end
        shorthand = Dict{String,String}(
            "SWORD" => pm.PIECE_SWORD,
            "SHIELD" => pm.PIECE_SHIELD,
            "FIRE" => pm.PIECE_POTION,
            "BOOT" => pm.PIECE_DODGE,
            "POTION" => pm.PIECE_CRIMSONBLADE,
            "GEM" => pm.PIECE_GREENGEM,
        )
        return get(shorthand, normalized_piece_type, nothing)
    end

    function get_piece_sprite_path(pieceType::String)::String
        globals = JulGame.UserGlobals["Module"]
        key = resolve_starting_piece_key(pieceType)
        if key === nothing
            return globals.get_asset_path("piece", "sword")
        end

        name_parts = split(key, "_")
        if length(name_parts) < 2
            return globals.get_asset_path("piece", "sword")
        end
        return globals.get_asset_path("piece", lowercase(name_parts[2]))
    end

    function get_piece_description(pieceType::String)::String
        globals = JulGame.UserGlobals["Module"]
        key = resolve_starting_piece_key(pieceType)
        if key === nothing || !haskey(globals.PiecesModule.ALL_PIECES, key)
            return UIStringsModule.UI_STRINGS[:character_unknown_piece]
        end
        piece = globals.PiecesModule.ALL_PIECES[key]
        desc = piece.description
        return desc !== nothing && desc != "" ? desc : UIStringsModule.UI_STRINGS[:character_unknown_piece]
    end

    function calculate_character_positions(this::CharacterSelection)
        # Calculate target positions for character slide animation
        # Selected character is at center (offset 0)
        # Others are positioned relative to selection

        centerX = 0.0
        spacing = 600.0

        for i in 1:length(this.characters)
            offset = (i - this.selectedCharacterIndex) * spacing
            this.targetOffsets[i] = offset
        end
    end

    function update_animations(this::CharacterSelection, deltaTime::Float64)
        # Smoothly animate character positions
        lerpSpeed = 4.0 * deltaTime  # Fixed lerp speed for smooth animation

        for i in 1:length(this.characters)
            current = get(this.characterOffsets, i, 0.0)
            target = get(this.targetOffsets, i, 0.0)
            diff = target - current

            if abs(diff) > 0.5
                this.characterOffsets[i] = current + diff * min(lerpSpeed, 1.0)
            else
                this.characterOffsets[i] = target
            end
        end

        # Animate start button slide
        if abs(this.startButtonTargetOffset - this.startButtonOffset) > 0.5
            diff = this.startButtonTargetOffset - this.startButtonOffset
            this.startButtonOffset += diff * min(lerpSpeed, 1.0)
        end

        # Update dancing animation
        update_dancing_animation(this, deltaTime)

        # Update floating animation time (but don't update UI element since we calculate directly)
        this.selectedCharacterFloating.animationTime += deltaTime * this.selectedCharacterFloating.speed

    end

    function update_dancing_animation(this::CharacterSelection, deltaTime::Float64)
        # Update dance time
        this.danceTime += deltaTime * this.danceConfig["speed"]

        # Keep dance time manageable to prevent overflow
        if this.danceTime > 1000.0
            this.danceTime = mod(this.danceTime, 1000.0)
        end
    end

    function get_dance_offset(this::CharacterSelection)::Tuple{Float64, Float64}
        # Get current dance offsets for the selected character
        config = this.danceConfig

        # Bounce animation (vertical movement)
        bounce_time = this.danceTime * config["bounce_rhythm"]
        bounce_offset = sin(bounce_time) * config["bounce_height"] * config["subtlety"]

        # Wiggle animation (horizontal movement) - slightly offset phase for more organic feel
        wiggle_time = this.danceTime * config["wiggle_rhythm"] + 0.5
        wiggle_offset = sin(wiggle_time * 1.3) * config["wiggle_intensity"] * config["subtlety"]

        # Add a secondary wiggle for more complexity
        wiggle_offset += sin(wiggle_time * 2.1 + 1.0) * config["wiggle_intensity"] * 0.3 * config["subtlety"]

        return (wiggle_offset, bounce_offset)
    end

    function get_character_sprite_path(character; highlighted::Bool = false)::String
        if is_demo_silhouette(character)
            sil = night_silhouette_path(highlighted)
            sil !== nothing && return sil
        end
        path = Scripts.CharacterPoseControllerModule.get_pose_art(string(character.key), :idle)
        return path === nothing ? JulGame.UserGlobals["Module"].get_asset_path("character", "magician") : path
    end

    """True once the map wipe fully covers the screen; the scene change then destroys the cached UI,
    so nothing may touch immediate UI after this point."""
    function run_transition_covered(this::CharacterSelection)::Bool
        isdefined(this, :transitionManager) || return true
        return this.transitionManager.state != Scripts.SceneTransitionModule.WipingOut
    end

    function handle_input(this::CharacterSelection, deltaTime)
        # Input is locked while starting a run, but visuals keep animating under the wipe.
        if this.transitioning_to_run
            run_transition_covered(this) && return
            update_animations(this, deltaTime)
            display_ui(this)
            return
        end

        # Update animations
        update_animations(this, deltaTime)

        # Handle input
        if JulGame.InputModule.get_button_pressed("LEFT") || JulGame.InputModule.get_button_pressed("A")
            select_relative!(this, -1)
        elseif JulGame.InputModule.get_button_pressed("RIGHT") || JulGame.InputModule.get_button_pressed("D")
            select_relative!(this, 1)
        elseif JulGame.InputModule.get_button_pressed("RETURN") || JulGame.InputModule.get_button_pressed("SPACE")
            press_start!(this)
        elseif JulGame.InputModule.get_button_pressed("ESCAPE")
            close(this)
        end

        # Refresh cached UI only while this screen owns input (close() must not be followed by display_ui in the same frame).
        if this.isActive
            display_ui(this)
        end
    end

    function display_ui(this::CharacterSelection)
        globals = JulGame.UserGlobals["Module"]
        treasure_data = globals.get_data_manager().treasure_data

        if this.selectedCharacterIndex < 1 || this.selectedCharacterIndex > length(this.characters)
            return
        end

        selectedCharacter = this.characters[this.selectedCharacterIndex]
        isAvailable = is_character_available(this.selectedCharacterIndex)

        # === Update cached UI elements ===
        update_cached_ui(this, globals, selectedCharacter, isAvailable, treasure_data)
    end

    function update_cached_ui(this::CharacterSelection, globals, selectedCharacter, isAvailable, treasure_data)
        # Update title and name
        charName = isAvailable ? string(selectedCharacter.name) : "???"
        this.cachedUI["char_select_title"].isActive = true
        render_character_select_name!(charName)
        if isAvailable
            render_character_select_stats!(UIStringsModule.format_string(
                :character_stats;
                hp = selectedCharacter.hp,
                atk = selectedCharacter.atk,
                def = selectedCharacter.def,
            ))
        else
            render_character_select_stats!(""; isActive = false)
        end
        this.cachedUI["settings_gear"].isActive = true
        for (key, _, _) in _CLICK_ZONES
            this.cachedUI[key].isActive = true
        end

        # Update starting pieces visibility
        update_starting_pieces(this, globals, isAvailable)

        # Update character sprites
        update_characters(this, isAvailable)

        # Update treasure info
        if isAvailable && haskey(treasure_data, selectedCharacter.treasure)
            update_treasure_info(this, treasure_data[selectedCharacter.treasure], selectedCharacter.key)
        else
            hide_treasure_info(this)
        end

        # Locked message (cached; do not spawn immediate_text every frame)
        this.cachedUI["char_locked_label"].isActive = !isAvailable

        # Update start button
        update_start_button(this, isAvailable)
        update_back_button(this)

        # Update spotlight
        this.cachedUI["spotlight_bottom"].isActive = true
        this.cachedUI["spotlight_top"].isActive = true
    end

    function update_starting_pieces(this::CharacterSelection, globals, isAvailable::Bool)
        sync_starting_pieces_for_selected_character!(this)
        sync_user_preview_from_selection!(this, globals, isAvailable)
        this.cachedUI["starting_pieces_label"].isActive = true

        iconIndex = 1
        while haskey(this.cachedUI, "piece_icon_$iconIndex")
            icon = this.cachedUI["piece_icon_$iconIndex"]

            if iconIndex <= length(this.startingPieces)
                pieceType = this.startingPieces[iconIndex]
                spritePath = get_piece_sprite_path(pieceType)
                icon = JulGame.ImmediateUIModule.immediate_image(
                    "piece_icon_$iconIndex",
                    spritePath;
                    anchor = icon.anchor.current_state,
                    anchorOffset = icon.anchorOffset,
                    size = icon.size,
                    layer = icon.layer,
                    isActive = true,
                    lifetime = _CHARSEL_IMMEDIATE_LIFETIME,
                    forceClickCheck = true,
                )
                this.cachedUI["piece_icon_$iconIndex"] = icon

                if icon.isHovered
                    # Ephemeral each frame — avoids stale pooled TextBox / missed align.
                    DisplayTextModule.display_text(
                        "piece_tooltip",
                        get_piece_description(pieceType);
                        fontSize = 16,
                        anchor = :topLeft,
                        anchorOffset = Math.Vector2(icon.anchorOffset.x, icon.anchorOffset.y + 125),
                        color = (255, 255, 100, 255),
                        maxLineWidth = 250,
                        wrapWords = true,
                        layer = 10,
                    )
                    break
                end
            else
                icon.isActive = false
            end

            iconIndex += 1
        end
    end

    function update_characters(this::CharacterSelection, isAvailable)
        zoneDelta = hovered_zone_delta(this)
        glowIndex = zoneDelta == 0 ? 0 : this.selectedCharacterIndex + zoneDelta
        for (i, character) in enumerate(this.characters)
            button = this.cachedUI["char_sprite_$i"]
            isSelected = i == this.selectedCharacterIndex
            charIsAvailable = is_character_available(i)

            # Get animated offset
            offset = get(this.characterOffsets, i, 0.0)

            # Calculate position
            x = offset
            y = 0.0

            # Apply dancing animation to unselected characters
            if !isSelected
                dance_x, dance_y = get_dance_offset(this)
                x += dance_x
                y += dance_y
            end

            # Apply floating animation to selected character
            if isSelected
                config = this.selectedCharacterFloating
                bounce_time = this.selectedCharacterFloating.animationTime * config.speed
                wiggle_time = this.selectedCharacterFloating.animationTime * config.speed + 0.5

                vertical_progress = (sin(bounce_time * 2π) + 1) / 2
                vertical_eased = -(cos(π * vertical_progress) - 1) / 2
                vertical_offset = (vertical_eased - 0.5) * config.verticalAmplitude

                horizontal_progress = (sin(wiggle_time * 2π * config.horizontalSpeedMultiplier + config.horizontalPhaseOffset) + 1) / 2
                horizontal_eased = sin((horizontal_progress * π) / 2)
                horizontal_offset = (horizontal_eased - 0.5) * config.horizontalAmplitude

                x += horizontal_offset
                y += vertical_offset
            end

            # Update position and visibility
            yOffset = isSelected ? -100 : -150 * abs(this.selectedCharacterIndex - i)
            alpha = isSelected ? 255 : (charIsAvailable ? 150 : 80)

            hi = get(this.cachedUI, "char_sprite_$(i)_hi", nothing)
            if hi !== nothing
                shown = isSelected ? hi : button
                hidden = isSelected ? button : hi
                hidden.isActive = false
                hidden.useEffectTexture = false
                button = shown
            end
            button.anchorOffset = Math.Vector2(x, y + yOffset)
            button.color = (255, 255, 255, hi !== nothing ? 255 : alpha)
            button.layer = isSelected ? 5 : -1
            button.useEffectTexture = i == glowIndex
            button.isActive = true

            # Initialize floating animation for selected character
            if isSelected
                if this.selectedCharacterFloating.uiElement === nothing
                    initialize_ui_floating_animation(this.selectedCharacterFloating, button)
                end
            end
        end
    end

    function update_treasure_info(this::CharacterSelection, treasure, character_key)
        globals = JulGame.UserGlobals["Module"]

        # Update treasure name from preloaded text cache
        _set_all_treasure_texts_active!(this, false)
        name_key = _treasure_name_cache_key(treasure.key)
        if haskey(this.cachedUI, name_key)
            this.cachedUI["treasure_name"] = this.cachedUI[name_key]
        elseif haskey(this.cachedUI, "treasure_name_fallback")
            this.cachedUI["treasure_name"] = this.cachedUI["treasure_name_fallback"]
        end
        this.cachedUI["treasure_name"].isActive = true

        # Update treasure icon by toggling preloaded images (avoid runtime path swaps and image loads).
        icon_key = _treasure_icon_cache_key(treasure.key)
        _set_all_treasure_icons_active!(this, false)
        if haskey(this.cachedUI, icon_key)
            this.cachedUI["treasure_icon"] = this.cachedUI[icon_key]
            this.cachedUI["treasure_icon"].isActive = true
        elseif haskey(this.cachedUI, "treasure_icon")
            this.cachedUI["treasure_icon"].isActive = true
        end

        # Update activate description from preloaded text cache.
        desc_key = _activate_desc_cache_key(treasure.key)
        if haskey(this.cachedUI, desc_key)
            this.cachedUI["activate_desc"] = this.cachedUI[desc_key]
        elseif haskey(this.cachedUI, "activate_desc_fallback")
            this.cachedUI["activate_desc"] = this.cachedUI["activate_desc_fallback"]
        end
        this.cachedUI["activate_desc"].anchorOffset = Math.Vector2(
            this.cachedUI["activate_label"].size.x + this.cachedUI["activate_label"].anchorOffset.x + 5,
            -178
        )
        this.cachedUI["activate_desc"].isActive = true

        passive_key = _passive_desc_cache_key(character_key)
        this.cachedUI["passive_desc"] = get(this.cachedUI, passive_key, this.cachedUI["passive_desc_fallback"])

        # Show activate/passive labels
        this.cachedUI["activate_label"].isActive = true
        this.cachedUI["passive_label"].isActive = true
        this.cachedUI["passive_desc"].isActive = true
    end

    function hide_treasure_info(this::CharacterSelection)
        _set_all_treasure_texts_active!(this, false)
        this.cachedUI["treasure_name"].isActive = false
        _set_all_treasure_icons_active!(this, false)
        haskey(this.cachedUI, "treasure_icon") && (this.cachedUI["treasure_icon"].isActive = false)
        this.cachedUI["activate_label"].isActive = false
        this.cachedUI["activate_desc"].isActive = false
        this.cachedUI["passive_label"].isActive = false
        this.cachedUI["passive_desc"].isActive = false
    end

    function update_start_button(this::CharacterSelection, isAvailable)
        buttonColor = isAvailable ? (100, 255, 150, 255) : (100, 100, 100, 255)

        this.cachedUI["start_button"].color = buttonColor
        this.cachedUI["start_button"].isActive = true
        this.cachedUI["start_button_rect"].isActive = true

        rect = this.cachedUI["start_button_rect"]
        rect.anchorOffset = _START_BUTTON_OFFSET
        rect.size = _START_BUTTON_SIZE
        hovered = isAvailable && (rect.isHovered || this.cachedUI["start_button"].isHovered)
        Scripts.ButtonJuiceModule.update!(_START_JUICE_ID, rect, hovered)
    end

    function update_back_button(this::CharacterSelection)
        this.cachedUI["back_button"].isActive = true
        this.cachedUI["back_button_rect"].isActive = true
    end

    function start_game(this::CharacterSelection)
        isAvailable = is_character_available(this.selectedCharacterIndex)

        if !isAvailable
            # Don't start if character is locked
            return
        end

        # Store character selection
        confirm_selection(this)
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "startgame"), false, 1.0, 0, 1)
        # Char-select UI stays up under the wipe; the scene change destroys it once covered.
        this.transitioning_to_run = true
        Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "map.json"; duration = 1.25)
    end

    """Start button / Enter: juice the button (fly-off) while the run starts underneath."""
    function press_start!(this::CharacterSelection)
        this.transitioning_to_run && return
        is_character_available(this.selectedCharacterIndex) || return
        # start_game plays sfx-startgame on the same channel as the juice click.
        Scripts.ButtonJuiceModule.click!(_START_JUICE_ID; sfx = false) || return
        start_game(this)
    end

    function confirm_selection(this::CharacterSelection)
        if this.selectedCharacterIndex > 0 && this.selectedCharacterIndex <= length(this.characters)
            selectedCharacter = this.characters[this.selectedCharacterIndex]

            # Get globals
            globals = JulGame.UserGlobals["Module"]
            
            # Note: Reset is now done in Title.jl when "New Run" is clicked
            # Just apply selected character stats
            user = globals.get_user_data()
            if user !== nothing
                user.selectedCharacter = selectedCharacter.key
                user.shadowCloakUsed = false
                user.maxHealth = selectedCharacter.hp
                user.health = user.maxHealth
                user.attack = selectedCharacter.atk
                user.defense = selectedCharacter.def
                user.pieces = globals.UserModule.load_default_pieces_from_character(user, selectedCharacter.key)
                try
                    treasureToAdd = globals.TreasuresModule.ALL_TREASURES[uppercase(selectedCharacter.treasure)]
                    push!(user.treasures, treasureToAdd)
                catch
                    @debug "No treasure found for $(selectedCharacter.key)"
                end
            end

            this.isCharacterSelected = true
            globals.RunRecorderModule.start_run!(selectedCharacter.key)

            @debug("Selected character: $(selectedCharacter.name)")
        end
    end
end # module
