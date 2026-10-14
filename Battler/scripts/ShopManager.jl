module ShopManagerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using Random
    using ..Scripts
    using ..OverworldFeedbackModule
    include("localization/shop_strings.jl")
    using .ShopStringsModule
    include("utils/WeightPreviewPanel.jl")
    using .WeightPreviewPanelModule

    mutable struct ShopManager <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        # This is where you define your script's fields
        user
        persistentStateManager

        # Track upgrades and items
        hasPieceUpgrade::Bool
        hasUsedTrashCan::Bool

        # Items owned
        orbCount::Int
        fireCount::Int
        bombCount::Int

        # Shop inventory
        availablePieces::Vector  # Available pieces to buy
        availableTreasures::Vector  # Available treasures to buy
        availablePotions::Vector  # Available potions to buy
        piecePrices::Vector{Int}
        treasurePrices::Vector{Int}
        potionPrices::Vector{Int}
        pieceOnSale::Vector{Bool}
        treasureOnSale::Vector{Bool}
        potionOnSale::Vector{Bool}

        # UI state
        messageText::String
        messageTimeout::Float64

        # UI positions and sizes
        fontPath::String

        rectColor

        # Shop item slots
        leftPieceSlot
        leftPieceSign
        leftPieceSoldSign

        rightPieceSlot
        rightPieceSign
        rightPieceSoldSign

        leftTreasureSlot
        leftTreasureSign
        leftTreasureSoldSign

        rightTreasureSlot
        rightTreasureSign
        rightTreasureSoldSign

        # Shop potion slots
        leftPotionSlot
        leftPotionSign
        leftPotionSoldSign

        middlePotionSlot
        middlePotionSign
        middlePotionSoldSign

        rightPotionSlot
        rightPotionSign
        rightPotionSoldSign

        pieceUpgradeBox
        pieceTrashBox

        hoveredEntity::Union{Nothing, JulGame.Entity}
        cachedOutlines::Dict
        alpha::Int
        fade::Bool

        tooltipManager

        weightPreview

        # Shopkeeper animation system
        shopkeeperAnimation

        # Context menu for inventory potions
        contextMenuManager

        transitionManager

        exitDoor

        function ShopManager()
            this = new() # do not remove this line

            # Debug output to confirm script is loaded
            @debug("ShopManager constructor called")

            # Initialize upgrade states
            this.hasPieceUpgrade = false
            this.hasUsedTrashCan = false

            # Initialize item counts
            this.orbCount = 0
            this.fireCount = 0
            this.bombCount = 0

            # Initialize shop inventory
            this.availablePieces = []
            this.availableTreasures = []
            this.availablePotions = []
            this.piecePrices = Int[]
            this.treasurePrices = Int[]
            this.potionPrices = Int[]
            this.pieceOnSale = Bool[]
            this.treasureOnSale = Bool[]
            this.potionOnSale = Bool[]
            # Initialize UI state
            this.messageText = ""
            this.messageTimeout = 0.0
            this.hoveredEntity = nothing
            this.cachedOutlines = Dict()

            # Set font path
            this.fontPath = "Caveat-VariableFont_wght.ttf"
            #"PlaywriteNZGuides-Regular.ttf" #"Caveat-VariableFont_wght.ttf"

            this.rectColor = (220, 240, 250, 0)
            this.alpha = 125
            this.fade = true
            this.contextMenuManager = Scripts.ContextMenuModule.ContextMenuManager()
            this.weightPreview = WeightPreviewPanelModule.WeightPreviewPanel("shop_weight_preview")


            return this # do not remove this line
        end
    end

    # Center-anchored sprite, pixelsPerUnit 0. Puts the image bottom on the screen bottom.
    function seat_backpersp_on_screen_bottom(userEntity)
        userEntity === nothing && return
        sprite = userEntity.sprite
        sprite === nothing && return
        cam = JulGame.MAIN.scene.camera
        cam === nothing && return
        S = JulGame.SCALE_UNITS * Float64(cam.zoom)
        S <= 0 && return
        scale_y = Float64(userEntity.transform.scale.y)
        height = Float64(sprite.size.y) * scale_y * S / 64.0
        cam_y = Float64(cam.position.y) + Float64(cam.offset.y)
        screen_h = Float64(cam.size.y)
        wy = cam_y - Float64(sprite.offset.y) + (screen_h - height / 2 - (S * scale_y) / 2) / S
        pos = userEntity.transform.position
        userEntity.transform.position = Math.Vector3f(Float64(pos.x), wy, Float64(pos.z))
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # This is where you should register collision events or other events
    # Do not remove this function
    function JulGame.initialize(this::ShopManager)
        # start timer 
        timer = time_ns()
        @debug "Initializing ShopManager"
        register_shop_slots(this)
        # Debug output to confirm initialization
        @debug("ShopManager.initialize called")

        # Get user and persistent state manager
        globals = JulGame.UserGlobals["Module"]
        this.user = globals.get_user_data()
        this.persistentStateManager = globals.get_data_manager().persistent_state_manager

        # Set rich presence with current position if available
        if this.persistentStateManager.currentLevel > 0
            globals.SteamModule.set_rich_presence_with_position(globals.get_steam_data(), "AtTheShop", this.persistentStateManager.currentRoom, this.persistentStateManager.currentFloor)
        else
            globals.SteamModule.set_rich_presence(globals.get_steam_data(), "AtTheShop")
        end

        # Reset upgrade and trash flags each time shop is opened (per-visit, not persistent)
        this.hasPieceUpgrade = false
        this.hasUsedTrashCan = false
        # Clear from persistent state so they don't persist across shop visits
        if haskey(this.persistentStateManager.playerData, "hasPieceUpgrade")
            delete!(this.persistentStateManager.playerData, "hasPieceUpgrade")
        end
        if haskey(this.persistentStateManager.playerData, "hasUsedTrashCan")
            delete!(this.persistentStateManager.playerData, "hasUsedTrashCan")
        end

        userEntity = JulGame.SceneModule.get_entity_by_name("Player")
        if userEntity !== nothing
            if this.user.selectedCharacter == "CHARACTER_MAGICIAN"
                userEntity.sprite.imagePath = globals.get_asset_path("shop", "magician_backpersp")
            elseif this.user.selectedCharacter == "CHARACTER_DEMOLITIONIST"
                userEntity.sprite.imagePath = globals.get_asset_path("shop", "demolitionist_backpersp")
            elseif this.user.selectedCharacter == "CHARACTER_KNIGHT"
                userEntity.sprite.imagePath = globals.get_asset_path("shop", "knight_backpersp")
            end
            seat_backpersp_on_screen_bottom(userEntity)
        end


        Scripts.RunScalingModule.register_shop_visit()
        generate_shop_inventory(this)
        register_tooltip_manager(this)
        OverworldFeedbackModule.set_player!(userEntity)
        initialize_shopkeeper_animation(this)
        try
            this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
        catch e
            @error "SceneTransitionManager not found: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end

        this.pieceUpgradeBox = JulGame.SceneModule.get_entity_by_id("7742f20a-845d-4972-b436-50100d4d26be")
        this.pieceTrashBox = JulGame.SceneModule.get_entity_by_id("267b9070-df8c-43c6-af81-5d5abda46fbb")

        # Get exit door entity
        this.exitDoor = JulGame.SceneModule.get_entity_by_id("0f0cabcc-11d4-4350-b5d2-92bf663c0c44")
        if this.exitDoor !== nothing
            this.exitDoor.clickEvents = [() -> begin
                on_exit_click(this)
            end]
        end
        @debug "ShopManager initialized in $((time_ns() - timer) / 1e9) seconds"
    end

    function register_tooltip_manager(this::ShopManager)
        # Create and initialize the tooltip manager
        tooltipEntity = JulGame.EntityModule.Entity("TooltipManager")
        tooltipEntity = JulGame.create_entity(tooltipEntity)
        push!(tooltipEntity.scripts, Scripts.TooltipManagerModule.TooltipManager())
        this.tooltipManager = tooltipEntity.scripts[1]

        # Set custom tooltip style if desired
        Scripts.TooltipManagerModule.set_tooltip_style(
            this.tooltipManager,
            hoverDelay = UInt64(100)
        )
        OverworldFeedbackModule.reset!()
    end

    function initialize_shopkeeper_animation(this::ShopManager)
        # Create and initialize the shopkeeper animation system
        this.shopkeeperAnimation = this.parent.scripts[2]

        @debug("Shopkeeper animation system initialized")
    end

    function register_shop_slots(this::ShopManager)
        this.leftPieceSlot = JulGame.SceneModule.get_entity_by_id("5cffa35b-1da0-4f05-b3c0-bf9ee6d80938")
        this.leftPieceSign = JulGame.SceneModule.get_entity_by_id("edb75c7b-4e58-4bd6-a956-7724d17e2327")
        this.leftPieceSoldSign = JulGame.SceneModule.get_entity_by_id("a932827f-cbb0-4840-bff7-fbcc0ff6b86f")

        this.rightPieceSlot = JulGame.SceneModule.get_entity_by_id("c373499e-b167-48fb-b03c-8e8e44d3419e")
        this.rightPieceSign = JulGame.SceneModule.get_entity_by_id("981fd830-a988-4aaa-9d75-17347a02b8cd")
        this.rightPieceSoldSign = JulGame.SceneModule.get_entity_by_id("40bc5890-04e1-4c03-a89f-94804da935e9")

        this.leftTreasureSlot = JulGame.SceneModule.get_entity_by_id("e6fe1d85-9a54-43bb-bdb0-50e05b9d48ec")
        this.leftTreasureSign = JulGame.SceneModule.get_entity_by_id("d1c99054-58ca-4020-b5af-dc59a981cdad")
        this.leftTreasureSoldSign = JulGame.SceneModule.get_entity_by_id("119e7ceb-ef80-4e47-9081-03eff187040c")

        this.rightTreasureSlot = JulGame.SceneModule.get_entity_by_id("d00708a1-c090-467a-89e8-cc6c5783c066")
        this.rightTreasureSign = JulGame.SceneModule.get_entity_by_id("273ca489-64db-420c-9fc8-098c084d738e")
        this.rightTreasureSoldSign = JulGame.SceneModule.get_entity_by_id("fcddc569-bef7-4d1b-9a6e-c20463b1030b")

        this.leftPotionSlot = JulGame.SceneModule.get_entity_by_id("14f9f71a-d4e6-4d7e-bc51-96ba33f74db3")
        this.leftPotionSign = JulGame.SceneModule.get_entity_by_id("4652e280-aeff-4cd7-82a7-793cf0047de1")
        this.leftPotionSoldSign = JulGame.SceneModule.get_entity_by_id("b8802e9b-92e2-4cf7-b59c-0f2cd0ff7688")

        this.middlePotionSlot = JulGame.SceneModule.get_entity_by_id("270c8f27-48d7-402d-bf6f-4351243f81dc")
        this.middlePotionSign = JulGame.SceneModule.get_entity_by_id("bea8bbc6-fb7e-403f-859c-d2f5abc959f9")
        this.middlePotionSoldSign = JulGame.SceneModule.get_entity_by_id("e0c26619-1315-4374-bdc7-5263c0098063")

        this.rightPotionSlot = JulGame.SceneModule.get_entity_by_id("fee356ea-e654-4518-b088-f26fe6fc6f29")
        this.rightPotionSign = JulGame.SceneModule.get_entity_by_id("973219bd-8bf6-4a15-bbad-a73ad1f18fd7")
        this.rightPotionSoldSign = JulGame.SceneModule.get_entity_by_id("359377a9-2618-41db-a811-4c71984a03f0")
    end

    # Generate random shop inventory from CSV data
    function generate_shop_inventory(this::ShopManager)
        # Clear existing inventory
        this.availablePieces = []
        this.availableTreasures = []
        this.availablePotions = []

        # Get CSV data
        globals = JulGame.UserGlobals["Module"]
        data = globals.get_data_manager()
        if data === nothing
            @error("CSV data not available for shop inventory")
            return
        end

        pieces = filter(globals.item_available_in_game, collect(values(data.piece_data)))

        # filter out pieces the player already has (compare by key)
        owned_piece_keys = Set(p.key for p in this.user.pieces)
        available_pieces = filter(p -> !in(p.key, owned_piece_keys), pieces)

        # Select 2 random unique pieces (excluding basic ones)
        special_pieces = filter(row -> row.rarity > 0.0, available_pieces)  # Only more rare pieces
        if length(special_pieces) > 0
            num_pieces = min(2, length(special_pieces))
            # Shuffle and take first N to avoid duplicates
            shuffled = shuffle(special_pieces)
            for i in 1:num_pieces
                piece = shuffled[i]
                push!(this.availablePieces, piece)
            end
        end

        treasures = filter(globals.item_available_in_game, collect(values(data.treasure_data)))
        # filter out treasures the player already has (compare by key)
        owned_keys = Set(t.key for t in this.user.treasures)
        treasures = filter(row -> !in(row.key, owned_keys), treasures)
        # Select 2 random unique treasures
        if length(treasures) > 0
            num_treasures = min(2, length(treasures))
            # Shuffle and take first N to avoid duplicates
            shuffled = Random.shuffle(treasures)
            for i in 1:num_treasures
                treasure = shuffled[i]
                push!(this.availableTreasures, treasure)
            end
        end

        potions = filter(globals.item_available_in_game, collect(values(data.potion_data)))

        if length(potions) > 0
            num_potions = min(3, length(potions))
            # Shuffle and take first N to avoid duplicates
            shuffled = Random.shuffle(potions)
            for i in 1:num_potions
                potion = shuffled[i]
                push!(this.availablePotions, potion)
            end
        end

        apply_shop_pricing!(this)

        @debug("Generated shop inventory with $(length(this.availablePieces)) pieces, $(length(this.availableTreasures)) treasures and $(length(this.availablePotions)) potions")
    end

    function apply_shop_pricing!(this::ShopManager)
        this.piecePrices = [Scripts.RunScalingModule.scale_price(Int(p.average_price)) for p in this.availablePieces]
        this.treasurePrices = [Scripts.RunScalingModule.scale_price(Int(t.average_price)) for t in this.availableTreasures]
        this.potionPrices = [Scripts.RunScalingModule.scale_price(Int(p.average_price)) for p in this.availablePotions]
        this.pieceOnSale = fill(false, length(this.piecePrices))
        this.treasureOnSale = fill(false, length(this.treasurePrices))
        this.potionOnSale = fill(false, length(this.potionPrices))

        kind = Scripts.RunScalingModule.roll_shop_sale_kind(
            !isempty(this.piecePrices),
            !isempty(this.potionPrices),
            !isempty(this.treasurePrices),
        )
        kind === nothing && return

        if kind == :piece
            i = rand(1:length(this.piecePrices))
            this.pieceOnSale[i] = true
            this.piecePrices[i] = max(1, this.piecePrices[i] ÷ 2)
        elseif kind == :potion
            i = rand(1:length(this.potionPrices))
            this.potionOnSale[i] = true
            this.potionPrices[i] = max(1, this.potionPrices[i] ÷ 2)
        elseif kind == :treasure
            i = rand(1:length(this.treasurePrices))
            this.treasureOnSale[i] = true
            this.treasurePrices[i] = max(1, this.treasurePrices[i] ÷ 2)
        end
    end

    function shop_price_color(on_sale::Bool)
        return on_sale ? (255, 210, 70, 255) : (200, 200, 200, 255)
    end

    # This is called every frame
    # Do not remove this function
    function JulGame.update(this::ShopManager, deltaTime)
        OverworldFeedbackModule.update(deltaTime)
        if Scripts.SettingsDisplayManagerModule.is_settings_open()
            return
        end
        if JulGame.IS_DEBUG
            this.rectColor = (220, 240, 250, 100)
        else
            this.rectColor = (220, 240, 250, 0)
        end


        color = (255, 255, 255, 125)
        thickness = 4
        if this.hoveredEntity !== nothing
            outline_entity(this, this.hoveredEntity)
            handle_outline_fade(this)
        end
        # Update message timeout
        if this.messageTimeout > 0
            this.messageTimeout -= deltaTime
        end

        # Update context menu
        Scripts.ContextMenuModule.update_context_menu(this.contextMenuManager)

        # Handle exit door hover animation
        handle_exit_door_hover(this)

        # Draw shop UI
        draw_shop_ui(this)
        sync_and_draw_weight_preview!(this, deltaTime)
    end

    function handle_outline_fade(this::ShopManager)
        tick = 4
        if this.fade
            # Fade out (decrease alpha)
            current_alpha = this.alpha
            min_alpha = 50
            new_alpha = max(current_alpha - tick, min_alpha)
            this.alpha = new_alpha

            # Check if we've reached minimum alpha
            if new_alpha <= min_alpha
                this.fade = false
            end
        else
            # Fade in (increase alpha)
            current_alpha = this.alpha
            max_alpha = 255
            new_alpha = min(current_alpha + tick, max_alpha)
            this.alpha = new_alpha

            # Check if we've reached maximum alpha
            if new_alpha >= max_alpha
                this.fade = true
            end
        end
    end

    function outline_entity(this::ShopManager, entity::JulGame.Entity)
        if !entity.isActive
            return
        end
        color = (255, 255, 255, this.alpha)
        thickness = 4

        if !haskey(this.cachedOutlines, entity.id)
            this.cachedOutlines[entity.id] = draw_outline_from_surface(this, entity, entity.sprite.image; color = color, thickness = thickness, target_colors = [(0, 0, 0)], variance = 125)
        end
        draw_outline(this.cachedOutlines[entity.id], color)
    end

    function draw_outline(cachedOutline, color)
        for (pos_x, pos_y, r, g, b, a) in cachedOutline
            JulGame.SDL2.LibSDL2.pixelRGBA(JulGame.Renderer, pos_x, pos_y, color[1], color[2], color[3], color[4])
        end
    end

    function draw_outline_from_surface(
        this::ShopManager,
        entity::JulGame.Entity,
        surface::Ptr{JulGame.SDL2.SDL_Surface};
        color::NTuple{4, Int} = (255, 255, 255, 255),
        thickness::Int = 1,
        color_keys::Vector{NTuple{3, Int}} = NTuple{3, Int}[],
        target_colors::Union{Nothing, Vector{NTuple{3, Int}}} = nothing,
        variance::Int = 0
    )

        JulGame.SDL2.LibSDL2.SDL_LockSurface(surface)

        w = unsafe_load(Ptr{Cint}(surface + offsetof(JulGame.SDL2.SDL_Surface, Val(:w))))
        h = unsafe_load(Ptr{Cint}(surface + offsetof(JulGame.SDL2.SDL_Surface, Val(:h))))
        pitch = unsafe_load(Ptr{Cint}(surface + offsetof(JulGame.SDL2.SDL_Surface, Val(:pitch)))) ÷ 4
        pixels_ptr = unsafe_load(Ptr{Ptr{UInt8}}(surface + offsetof(JulGame.SDL2.SDL_Surface, Val(:pixels))))
        pixels_array = unsafe_wrap(Array, Ptr{UInt32}(pixels_ptr), (pitch * h,); own = false)

        function is_transparent(x, y)
            return x < 0 || y < 0 || x ≥ w || y ≥ h || begin
                pixel = pixels_array[y * pitch + x + 1]
                r, g, b, a = get_rgba(pixel, surfaceValues[1].format)

                for key in color_keys
                    if color_match(r, g, b, key, variance)
                        return true
                    end
                end

                return a == 0
            end
        end

        # Position of sprite on screen
        position = entity.sprite.lastRenderedScreenPosition
        surfaceValues = unsafe_wrap(Array, surface, 10; own = false)
        cache = []
        for y in 0:h-1
            for x in 0:w-1
                pixel = pixels_array[y * pitch + x + 1]
                r, g, b, a = get_rgba(pixel, surfaceValues[1].format)

                skip = a == 0
                for key in color_keys
                    if r == key[1] && g == key[2] && b == key[3]
                        skip = true
                        break
                    end
                end

                if !skip && (target_colors === nothing || any(c -> color_match(r, g, b, c, variance), target_colors)                    )
                    outlined = false
                    for dy in -thickness:thickness
                        for dx in -thickness:thickness
                            nx, ny = x + dx, y + dy
                            if abs(dx) + abs(dy) ≤ thickness && is_transparent(nx, ny)
                                outlined = true
                                break
                            end
                        end
                        if outlined
                            break
                        end
                    end
                    if outlined
                        or, og, ob, oa = color
                        pos_x = x + position.x
                        pos_y = y + position.y
                        push!(cache, (pos_x, pos_y, or, og, ob, oa))
                        JulGame.SDL2.LibSDL2.pixelRGBA(JulGame.Renderer, pos_x, pos_y, or, og, ob, oa)
                    end
                end
            end
        end

        JulGame.SDL2.LibSDL2.SDL_UnlockSurface(surface)

        return cache
    end

    function get_rgba(pixel::UInt32, format::Ptr{JulGame.SDL2.SDL_PixelFormat})
        r = Ref{UInt8}()
        g = Ref{UInt8}()
        b = Ref{UInt8}()
        a = Ref{UInt8}()
        JulGame.SDL2.LibSDL2.SDL_GetRGBA(pixel, format, r, g, b, a)
        return (r[], g[], b[], a[])
    end

    function color_match(r::UInt8, g::UInt8, b::UInt8, target::NTuple{3, Int}, variance::Int)
        tr, tg, tb = target
        return abs(r - tr) ≤ variance &&
               abs(g - tg) ≤ variance &&
               abs(b - tb) ≤ variance
    end

    @generated function offsetof(::Type{X}, ::Val{field}) where {X,field}
        idx = findfirst(f->f==field, fieldnames(X))
        return fieldoffset(X, idx)
    end

    # This is called when the script is removed from an entity (scene change, entity deletion)
    # Do not remove this function
    function JulGame.on_shutdown(this::ShopManager)
        @debug("ShopManager.on_shutdown called")
        OverworldFeedbackModule.reset!()

        # Don't persist upgrade/trash flags - they should reset each shop visit
        # (These are set temporarily in persistent state by InventoryManager during the visit,
        # but we clear them on initialize so they don't persist across shop visits)
    end

    function draw_shop_ui(this::ShopManager)
        # Draw the shopkeeper character on the right side
        # (This would be handled by the sprite in the scene, but we can add a placeholder)

        # Draw upgrade sections
        draw_upgrade_section(this)

        # Draw items section
        draw_items_section(this)

        # Draw treasures section
        draw_treasures_section(this)

        # Draw potions section
        draw_potions_section(this)

        # Draw current message if active
        if this.messageTimeout > 0
            # Draw message background panel
            JulGame.ImmediateUIModule.immediate_rect(
                "message_panel";
                size = Math.Vector2(600, 60),
                color = (76, 76, 76, 230),
                anchor = :center,
                anchorOffset = Math.Vector2(0, 50),
                borderWidth = 1,
                borderRadius = 5,
                layer = -1,
            )

            DisplayTextModule.display_text(
                "message_text",
                this.messageText;
                fontPath = this.fontPath,
                fontSize = 28,
                anchor = :center,
                anchorOffset = Math.Vector2(0, 50),
                clickEvent = () -> this.messageTimeout = 0.0,
            )
        end
    end

    function draw_upgrade_section(this::ShopManager)
        # Sync flags from persistent state so UI updates immediately after confirmations
        if haskey(this.persistentStateManager.playerData, "hasPieceUpgrade")
            this.hasPieceUpgrade = this.persistentStateManager.playerData["hasPieceUpgrade"]
        end
        if haskey(this.persistentStateManager.playerData, "hasUsedTrashCan")
            this.hasUsedTrashCan = this.persistentStateManager.playerData["hasUsedTrashCan"]
        end
        # Piece upgrade box (single-use)
        if this.hasPieceUpgrade
            draw_interactable_rect(this, "piece_upgrade_box_disabled", this.pieceUpgradeBox, () -> show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_sold_out]); size = Math.Vector2(240, 360), tooltipText = "Upgrade an item for 75 dollars")
            if this.pieceUpgradeBox.sprite.imagePath == JulGame.UserGlobals["Module"].get_asset_path("shop", "upgradeanvil")
                this.pieceUpgradeBox.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("shop", "upgradeanvil-inactive")
            end
        else
            draw_interactable_rect(this, "piece_upgrade_box_enabled", this.pieceUpgradeBox, () -> on_piece_upgrade_click(this); size = Math.Vector2(240, 360), tooltipText = "Upgrade an item for 75 dollars")
        end

        # Draw price for piece upgrade (dim if used)
        DisplayTextModule.display_text(
            "piece_upgrade_price",
            this.hasPieceUpgrade ? ShopStringsModule.SHOP_STRINGS[:shop_price_sold_out] : ShopStringsModule.SHOP_STRINGS[:shop_price_piece_upgrade];
            fontPath = this.fontPath,
            fontSize = 64,
            parent = this.pieceUpgradeBox.sprite,
            anchor = :centerBottom,
            color = this.hasPieceUpgrade ? (160, 160, 160, 220) : (255, 255, 255, 255)
        )

        # Bottom left upgrade box (Trash, single-use)
        if this.hasUsedTrashCan
            draw_interactable_rect(this, "piece_trash_box_disabled", this.pieceTrashBox, () -> show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_sold_out]); size = Math.Vector2(240, 360), tooltipText = "Trash an item for 50 dollars")
            if this.pieceTrashBox.sprite.imagePath == JulGame.UserGlobals["Module"].get_asset_path("shop", "removetrashcan")
                this.pieceTrashBox.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("shop", "removetrashcan-inactive")
            end
        else
            draw_interactable_rect(this, "piece_trash_box_enabled", this.pieceTrashBox, () -> on_trash_click(this); size = Math.Vector2(240, 360), tooltipText = "Trash an item for 50 dollars")
        end

        # Draw price in red for trash (dim if used)
        DisplayTextModule.display_text(
            "trash_price",
            this.hasUsedTrashCan ? ShopStringsModule.SHOP_STRINGS[:shop_price_sold_out] : ShopStringsModule.SHOP_STRINGS[:shop_price_trash];
            fontPath = this.fontPath,
            fontSize = 64,
            parent = this.pieceTrashBox.sprite,
            anchor = :centerBottom,
            color = this.hasUsedTrashCan ? (160, 160, 160, 220) : (255, 128, 128, 255)
        )
    end

    function shop_new_piece_weight_percent()
        return round(JulGame.UserGlobals["Module"].UserModule.NEW_PIECE_ENTRY_SHARE * 100, digits = 2)
    end

    function shop_piece_tooltip(piece, user; display_name = nothing)
        text = Scripts.CurrentRunStatusModule.get_piece_tooltip_text(
            piece, user;
            weight_percent = shop_new_piece_weight_percent(),
        )
        display_name === nothing && return text
        rest = findfirst('\n', text)
        return rest === nothing ? String(display_name) : string(display_name, text[rest:end])
    end

    function hovered_for_sale_piece(this::ShopManager)
        h = this.hoveredEntity
        h === nothing && return nothing
        if h === this.leftPieceSlot && (this.leftPieceSoldSign === nothing || !this.leftPieceSoldSign.isActive) && length(this.availablePieces) >= 1
            return (this.availablePieces[1], this.leftPieceSlot)
        elseif h === this.rightPieceSlot && (this.rightPieceSoldSign === nothing || !this.rightPieceSoldSign.isActive) && length(this.availablePieces) >= 2
            return (this.availablePieces[2], this.rightPieceSlot)
        end
        return nothing
    end

    function sync_and_draw_weight_preview!(this::ShopManager, deltaTime)
        hit = hovered_for_sale_piece(this)
        if hit === nothing
            WeightPreviewPanelModule.hide!(this.weightPreview)
        else
            piece, _ = hit
            globals = JulGame.UserGlobals["Module"]
            rarity = globals.UserModule.weight_for_new_piece(this.user.pieces)
            rows = WeightPreviewPanelModule.rows_for_change(this.user.pieces, piece, rarity; is_new = true)
            WeightPreviewPanelModule.show!(this.weightPreview, rows)
        end
        WeightPreviewPanelModule.tick!(this.weightPreview, deltaTime)
        sprite = hit === nothing ? nothing : hit[2].sprite
        WeightPreviewPanelModule.draw_beside_sprite!(this.weightPreview, sprite)
    end

    function draw_items_section(this::ShopManager)
        if !isempty(this.availablePieces)
            piece_count = 2

            for i in 1:piece_count
                piece = this.availablePieces[i]

                entity = nothing
                if i == 1
                    entity = this.leftPieceSlot
                    if entity.sprite.imagePath != get_icon_path(piece.key) && entity.sprite.imagePath != "fallback.png"
                        entity.sprite.imagePath = get_icon_path(piece.key)
                    end
                    if this.leftPieceSoldSign.isActive
                        continue
                    end
                elseif i == 2
                    entity = this.rightPieceSlot
                    if entity.sprite.imagePath != get_icon_path(piece.key) && entity.sprite.imagePath != "fallback.png"
                        entity.sprite.imagePath = get_icon_path(piece.key)
                    end
                    if this.rightPieceSoldSign.isActive
                        continue
                    end
                end

                # Background slot
                draw_interactable_rect(this, "piece_slot_$(i)", entity, () -> on_piece_click(this, i, piece); hoverEnterEvent = () -> this.hoveredEntity = entity, tooltipText = shop_piece_tooltip(piece, this.user))

                # Draw piece price
                price = this.piecePrices[i]
                on_sale = this.pieceOnSale[i]
                DisplayTextModule.display_text(
                    "piece_price_$(i)",
                    on_sale ? "$(price)!" : string(price),
                    fontPath = this.fontPath,
                    fontSize = 32,
                    parent = i == 1 ? this.leftPieceSign.sprite : this.rightPieceSign.sprite,
                    anchor = :center,
                    color = shop_price_color(on_sale),
                    lifetime = 200
                )
            end
        else
            # TODO:Show "Sold Out" if no pieces available
        end
    end

    function draw_treasures_section(this::ShopManager)
        # Draw treasure slots
        if !isempty(this.availableTreasures)
            treasure_count = 2
            for (i, treasure) in enumerate(this.availableTreasures)
                entity = nothing
                if i == 1
                    entity = this.leftTreasureSlot
                    if entity.sprite.imagePath != get_treasure_icon_path(treasure.key) && entity.sprite.imagePath != "fallback.png"
                        entity.sprite.imagePath = get_treasure_icon_path(treasure.key)
                    end
                    if this.leftTreasureSoldSign.isActive
                        continue
                    end
                elseif i == 2
                    entity = this.rightTreasureSlot
                    if entity.sprite.imagePath != get_treasure_icon_path(treasure.key) && entity.sprite.imagePath != "fallback.png"
                        entity.sprite.imagePath = get_treasure_icon_path(treasure.key)
                    end
                    if this.rightTreasureSoldSign.isActive
                        continue
                    end
                end

                # Background slot
                draw_interactable_rect(this, "treasure_slot_$(i)", entity, () -> on_treasure_click(this, i); hoverEnterEvent = () -> this.hoveredEntity = entity, tooltipText = "$(treasure.name): $(treasure.description)")

                # Draw treasure price
                price = this.treasurePrices[i]
                on_sale = this.treasureOnSale[i]
                DisplayTextModule.display_text(
                    "treasure_price_$(i)",
                    on_sale ? "$(price)!" : string(price);
                    parent = i == 1 ? this.leftTreasureSign.sprite : this.rightTreasureSign.sprite,
                    fontPath = this.fontPath,
                    fontSize = 32,
                    anchor = :center,
                    color = shop_price_color(on_sale)
                )
            end
        end
    end

    function draw_potions_section(this::ShopManager)
        draw_potion_slot(this, Math.Vector2(520, 350), 1, "left")
        draw_potion_slot(this, Math.Vector2(685, 350), 2, "middle")
        draw_potion_slot(this, Math.Vector2(850, 350), 3, "right")
    end

    function draw_potion_slot(this::ShopManager, position::Math.Vector2, index::Int, potion::String)
        potionObj = nothing
        entity = nothing
        signObj = nothing
        if index == 1
            entity = this.leftPotionSlot
            potionObj = this.availablePotions[1]
            if entity.sprite.imagePath != get_potion_icon_path(potionObj.key) && entity.sprite.imagePath != "fallback.png"
                entity.sprite.imagePath = get_potion_icon_path(potionObj.key)
            end
            signObj = this.leftPotionSign
            if this.leftPotionSoldSign.isActive
                return
            end
        elseif index == 2
            entity = this.middlePotionSlot
            potionObj = this.availablePotions[2]
            if entity.sprite.imagePath != get_potion_icon_path(potionObj.key) && entity.sprite.imagePath != "fallback.png"
                entity.sprite.imagePath = get_potion_icon_path(potionObj.key)
            end
            signObj = this.middlePotionSign
            if this.middlePotionSoldSign.isActive
                return
            end
        elseif index == 3
            entity = this.rightPotionSlot
            potionObj = this.availablePotions[3]
            if entity.sprite.imagePath != get_potion_icon_path(potionObj.key) && entity.sprite.imagePath != "fallback.png"
                entity.sprite.imagePath = get_potion_icon_path(potionObj.key)
            end
            signObj = this.rightPotionSign
            if this.rightPotionSoldSign.isActive
                return
            end
        end
        draw_interactable_rect(this,"potion_slot_$(index)", entity, () -> on_potion_click(this, index, potionObj); hoverEnterEvent = () -> this.hoveredEntity = entity, tooltipText = "$(potionObj.name): $(potionObj.description)")
        # Draw potion price
        price = this.potionPrices[index]
        on_sale = this.potionOnSale[index]
        DisplayTextModule.display_text(
            "potion_price_$(index)",
            on_sale ? "$(price)!" : string(price),
            fontPath = this.fontPath,
            fontSize = 32,
            parent = index == 1 ? this.leftPotionSign.sprite : index == 2 ? this.middlePotionSign.sprite : this.rightPotionSign.sprite,
            anchor = :center,
            color = shop_price_color(on_sale)
        )
    end

    function draw_interactable_rect(this::ShopManager, id::String, parent, clickEvent::Function; hoverEnterEvent::Function = () -> @debug("Hovering over slot"), hoverExitEvent::Function = () -> @debug("Hovering over slot"), tooltipText::String = "None", size::Math.Vector2 = Math.Vector2(0, 0))
        rect = JulGame.ImmediateUIModule.immediate_rect(
            id;
            parent = parent.sprite,
            anchor = :center,
            size = size != Math.Vector2(0, 0) ? size : parent.sprite.size,
            color = this.rectColor,
            borderWidth = 0,
            clickEvent = clickEvent,
            hoverEnterEvent = hoverEnterEvent,
            hoverExitEvent = () -> this.hoveredEntity = nothing
        )

        Scripts.TooltipManagerModule.register_tooltip_item(
            this.tooltipManager,
            rect,
            tooltipText
        )
    end

    # Button click handlers
    function on_piece_upgrade_click(this::ShopManager)
        @debug("ShopManager.on_piece_upgrade_click called")
        if this.hasPieceUpgrade
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_sold_out])
            return
        end

        # Open inventory in upgrade mode
        if Scripts.InventoryManagerModule.InventoryManagerInstance !== nothing
            Scripts.InventoryManagerModule.open_upgrade_inventory(
                Scripts.InventoryManagerModule.InventoryManagerInstance,
                75  # Cost to upgrade an item
            )
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_select_item_upgrade])
        else
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_inventory_unavailable])
        end
    end

    function on_trash_click(this::ShopManager)
        cost = 50
        @debug("ShopManager.on_trash_click called")
        if this.hasUsedTrashCan
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_sold_out])
            return
        end

        # Check if player has enough gold for the upgrade
        if this.user.gold < cost
            message = ShopStringsModule.format_string(:shop_not_enough_gold, amount=50)
            show_message(this, message)

            # Trigger awkward animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_awkward(this.shopkeeperAnimation)
            end
            return
        end

        # Open inventory in deletion mode
        if Scripts.InventoryManagerModule.InventoryManagerInstance !== nothing
            Scripts.InventoryManagerModule.open_deletion_inventory(
                Scripts.InventoryManagerModule.InventoryManagerInstance,
                cost  # Cost to delete an item
            )
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_select_item_trash])
        else
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_inventory_unavailable])
        end
    end

    function handle_exit_door_hover(this::ShopManager)
        if this.exitDoor === nothing
            return
        end

        if this.exitDoor.isHovered
            if this.exitDoor.sprite.imagePath != JulGame.UserGlobals["Module"].get_asset_path("shop", "exithovered")
                this.exitDoor.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("shop", "exithovered")
            end
        else
            if this.exitDoor.sprite.imagePath != JulGame.UserGlobals["Module"].get_asset_path("shop", "exit")
                this.exitDoor.sprite.imagePath = JulGame.UserGlobals["Module"].get_asset_path("shop", "exit")
            end
        end
    end

    function on_exit_click(this::ShopManager)
        @debug("ShopManager.on_exit_click called")
        this.persistentStateManager.isFloorComplete = true
        globals = JulGame.UserGlobals["Module"]
        globals.SaveManagerModule.try_save_run!()
        Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, "map.json")
    end

    function show_message(this::ShopManager, message::String)
        @debug("ShopManager.show_message called: $(message)")
        this.messageText = message
        this.messageTimeout = 2.0  # Show message for 2 seconds
    end

    """
    Check if all items are sold and trigger happy animation if so
    """
    function check_all_items_sold(this::ShopManager)
        # Check if all pieces are sold
        pieces_sold = this.leftPieceSoldSign.isActive && this.rightPieceSoldSign.isActive

        # Check if all treasures are sold
        treasures_sold = this.leftTreasureSoldSign.isActive && this.rightTreasureSoldSign.isActive

        # Check if all potions are sold
        potions_sold = this.leftPotionSoldSign.isActive && this.middlePotionSoldSign.isActive && this.rightPotionSoldSign.isActive

        if pieces_sold && treasures_sold && potions_sold
            # Trigger happy animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_happy(this.shopkeeperAnimation)
            end
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_bought_everything])
        end
    end

    function play_purchase_sfx()
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", "buyitem"),
            false, 1.0, 0, 1,
        )
    end

    # Button click handlers for purchasing and refreshing
    function on_piece_click(this::ShopManager, index::Int, piece)
        globals = JulGame.UserGlobals["Module"]
        piece_price = this.piecePrices[index]

        if this.user.gold >= piece_price
            this.user.gold -= piece_price
            play_purchase_sfx()
            OverworldFeedbackModule.gold!(-piece_price; sfx = false)
            OverworldFeedbackModule.piece!(piece; sfx = false)

            # Track gold spent in analytics
            try
                globals.AnalyticsModule.track_action(:gold_spent, piece_price)
            catch e
                @debug "Could not track gold spent: $e"
            end

            # Add the piece to the user's collection
            piece_key = piece.key

            piece_to_add = nothing
            for piece in collect(values(this.user.pieceCollection))
                if piece.key == piece_key
                    piece_to_add = piece
                    break
                end
            end

            piece_to_add = globals.UserModule.with_new_piece_weight(piece_to_add, this.user.pieces)
            globals.UserModule.add_piece_with_gem_limit!(this.user, piece_to_add)
            globals.RunRecorderModule.record!("shop_buy"; kind = "piece", key = piece_to_add.key, price = piece_price)

            # Remove from available pieces
            if index == 1
                this.leftPieceSlot.isActive = false
                this.leftPieceSoldSign.isActive = true
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(this.tooltipManager, "immediate_piece_slot_1")
            elseif index == 2
                this.rightPieceSlot.isActive = false
                this.rightPieceSoldSign.isActive = true
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(this.tooltipManager, "immediate_piece_slot_2")
            end

            message = ShopStringsModule.format_string(:shop_purchased_piece, piece_name=piece.name, price=piece_price)
            show_message(this, message)

            # Trigger grateful animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_grateful(this.shopkeeperAnimation)
            end

            # Check if all items are sold
            check_all_items_sold(this)
        else
            message = ShopStringsModule.format_string(:shop_not_enough_gold, amount=piece_price)
            show_message(this, message)

            # Trigger awkward animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_awkward(this.shopkeeperAnimation)
            end
        end
    end

    function on_potion_click(this::ShopManager, index::Int, potion)
        globals = JulGame.UserGlobals["Module"]
        potion_price = this.potionPrices[index]

        if this.user.gold >= potion_price
            if length(this.user.potions) < 4
                push!(this.user.potions, potion)
                this.user.gold -= potion_price
                play_purchase_sfx()
                OverworldFeedbackModule.gold!(-potion_price; sfx = false)
                OverworldFeedbackModule.potion!(1; key = potion.key, sfx = false)
                globals.RunRecorderModule.record!("shop_buy"; kind = "potion", key = potion.key, price = potion_price)

                # Track gold spent in analytics
                try
                    globals.AnalyticsModule.track_action(:gold_spent, potion_price)
                catch e
                    @debug "Could not track gold spent: $e"
                end
            else
                show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_potion_limit])
                return
            end
            message = ShopStringsModule.format_string(:shop_purchased_potion, count=length(this.user.potions))
            show_message(this, message)

            # Trigger grateful animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_grateful(this.shopkeeperAnimation)
            end
            if index == 1
                this.leftPotionSlot.isActive = false
                this.leftPotionSoldSign.isActive = true
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(this.tooltipManager, "immediate_potion_slot_1")
            elseif index == 2
                this.middlePotionSlot.isActive = false
                this.middlePotionSoldSign.isActive = true
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(this.tooltipManager, "immediate_potion_slot_2")
            elseif index == 3
                this.rightPotionSlot.isActive = false
                this.rightPotionSoldSign.isActive = true
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(this.tooltipManager, "immediate_potion_slot_3")
            end
        else
            message = ShopStringsModule.format_string(:shop_not_enough_gold, amount=potion_price)
            show_message(this, message)

            # Trigger awkward animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_awkward(this.shopkeeperAnimation)
            end
        end
    end


    function on_treasure_click(this::ShopManager, index::Int)
        globals = JulGame.UserGlobals["Module"]
        treasure = this.availableTreasures[index]
        treasure_price = this.treasurePrices[index]
        # Scaled shop price (sale already baked in when rolled)

        if this.user.gold >= treasure_price
            this.user.gold -= treasure_price
            play_purchase_sfx()
            OverworldFeedbackModule.gold!(-treasure_price; sfx = false)
            OverworldFeedbackModule.treasure!(treasure; sfx = false)

            # Track gold spent in analytics
            try
                globals.AnalyticsModule.track_action(:gold_spent, treasure_price)
            catch e
                @debug "Could not track gold spent: $e"
            end

            # Add the treasure to the user's collection
            treasure_key = treasure.key
            treasure_name = treasure.name

            # Add treasure to user's collection
            push!(this.user.treasures, treasure)
            globals.RunRecorderModule.record!("shop_buy"; kind = "treasure", key = treasure.key, price = treasure_price)
            if index == 1
                this.leftTreasureSlot.isActive = false
                this.leftTreasureSoldSign.isActive = true
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(this.tooltipManager, "immediate_treasure_slot_1")
            elseif index == 2
                this.rightTreasureSlot.isActive = false
                this.rightTreasureSoldSign.isActive = true
                Scripts.TooltipManagerModule.deregister_tooltip_item_by_id(this.tooltipManager, "immediate_treasure_slot_2")
            end

            message = ShopStringsModule.format_string(:shop_purchased_treasure, treasure_name=treasure_name, price=treasure_price)
            show_message(this, message)

            # Trigger grateful animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_grateful(this.shopkeeperAnimation)
            end
        else
            message = ShopStringsModule.format_string(:shop_not_enough_gold, amount=treasure_price)
            show_message(this, message)

            # Trigger awkward animation
            if this.shopkeeperAnimation !== nothing
                Scripts.ShopkeeperAnimationModule.trigger_awkward(this.shopkeeperAnimation)
            end
        end
    end

    function get_icon_path(key::String)
        globals = JulGame.UserGlobals["Module"]
        name = lowercase(split(key, "_")[2])
        return globals.get_asset_path("piece", name)
    end

    function get_potion_icon_path(key::String)
        globals = JulGame.UserGlobals["Module"]
        name = lowercase(split(key, "_")[2])
        return globals.get_asset_path("potion", name)
    end

    function get_treasure_icon_path(key::String)
        globals = JulGame.UserGlobals["Module"]
        name = lowercase(split(key, "_")[2])
        return globals.get_asset_path("treasure", name)
    end

    """
    Open context menu for inventory potion
    """
    function open_inventory_potion_context_menu(this::ShopManager, potion_index::Int)
        if potion_index > length(this.user.potions)
            return
        end

        potion = this.user.potions[potion_index]

        # Create menu items
        menu_items = [
            Scripts.ContextMenuModule.ContextMenuItem(
                text = ShopStringsModule.format_string(:shop_context_sell_price, price=potion_sell_price(potion)),
                action = () -> sell_inventory_potion(this, potion_index),
                #icon = "piece-error-0000.png"
            ),
            Scripts.ContextMenuModule.ContextMenuItem(
                text = ShopStringsModule.SHOP_STRINGS[:shop_context_discard],
                action = () -> discard_inventory_potion(this, potion_index),
                #icon = "piece-error-0000.png"
            )
        ]

        if contains(potion.type, "Shop")
            # add use and separator to the front of the menu
            insert!(menu_items, 1, Scripts.ContextMenuModule.ContextMenuItem(is_separator = true))
            insert!(menu_items, 1, Scripts.ContextMenuModule.ContextMenuItem(
                text = ShopStringsModule.SHOP_STRINGS[:shop_context_use],
                action = () -> use_inventory_potion(this, potion_index),
                #icon = "piece-error-0000.png"
            ))
        end

        # Open the context menu
        Scripts.ContextMenuModule.open_context_menu(
            "inventory_potion_$(potion_index)",
            menu_items;
            manager = this.contextMenuManager
        )
    end

    function show_battle_only_potion_blocked(this::ShopManager, potion)
        message = ShopStringsModule.format_string(:shop_potion_battle_only, potion_name=potion.name)
        show_message(this, message)
    end

    """
    Use a potion from inventory
    """
    function use_inventory_potion(this::ShopManager, potion_index::Int)
        if potion_index > length(this.user.potions)
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_potion_not_found])
            return
        end

        potion = this.user.potions[potion_index]

        # Check if it's a dice potion (shop reroll)
        if potion.en_name == "Dice"
            # Reset all sold signs
            this.leftPieceSoldSign.isActive = false
            this.rightPieceSoldSign.isActive = false
            this.leftTreasureSoldSign.isActive = false
            this.rightTreasureSoldSign.isActive = false
            this.leftPotionSoldSign.isActive = false
            this.middlePotionSoldSign.isActive = false
            this.rightPotionSoldSign.isActive = false

            # Reactivate all slots
            this.leftPieceSlot.isActive = true
            this.rightPieceSlot.isActive = true
            this.leftTreasureSlot.isActive = true
            this.rightTreasureSlot.isActive = true
            this.leftPotionSlot.isActive = true
            this.middlePotionSlot.isActive = true
            this.rightPotionSlot.isActive = true

            # Reroll the shop inventory
            generate_shop_inventory(this)

            # Force update slot sprites with new items
            for (i, piece) in enumerate(this.availablePieces)
                if i == 1
                    this.leftPieceSlot.sprite.imagePath = get_icon_path(piece.key)
                elseif i == 2
                    this.rightPieceSlot.sprite.imagePath = get_icon_path(piece.key)
                end
            end
            for (i, treasure) in enumerate(this.availableTreasures)
                if i == 1
                    this.leftTreasureSlot.sprite.imagePath = get_treasure_icon_path(treasure.key)
                elseif i == 2
                    this.rightTreasureSlot.sprite.imagePath = get_treasure_icon_path(treasure.key)
                end
            end
            for (i, potionObj) in enumerate(this.availablePotions)
                if i == 1
                    this.leftPotionSlot.sprite.imagePath = get_potion_icon_path(potionObj.key)
                elseif i == 2
                    this.middlePotionSlot.sprite.imagePath = get_potion_icon_path(potionObj.key)
                elseif i == 3
                    this.rightPotionSlot.sprite.imagePath = get_potion_icon_path(potionObj.key)
                end
            end

            # Remove potion from inventory
            deleteat!(this.user.potions, potion_index)

            Scripts.BattlePotionManagerModule.play_potion_drink_sfx()
            JulGame.UserGlobals["Module"].RunRecorderModule.note_potion!(potion.key, "used")
            JulGame.UserGlobals["Module"].RunRecorderModule.record!("shop_reroll"; kind = "dice", price = 0)
            message = ShopStringsModule.format_string(:shop_potion_used_reroll, potion_name=potion.name)
            show_message(this, message)
            return
        elseif potion.key == "POTION_HERBALTEA"
            herbal_tea = Scripts.BattlePotionManagerModule.PotionEffectsModule.HerbalTeaEffectModule
            gained = herbal_tea.drink_herbal_tea!(this.user)
            deleteat!(this.user.potions, potion_index)
            Scripts.BattlePotionManagerModule.play_potion_drink_sfx()
            OverworldFeedbackModule.heal!(gained; icon = herbal_tea.herbal_tea_icon())
            JulGame.UserGlobals["Module"].RunRecorderModule.note_potion!(potion.key, "used")
            show_message(this, ShopStringsModule.format_string(:shop_potion_used_heal, potion_name=potion.name, amount=gained))
            JulGame.UserGlobals["Module"].SaveManagerModule.try_save_run!()
        else
            message = ShopStringsModule.format_string(:shop_potion_used_no_effect, potion_name=potion.name)
            show_message(this, message)
        end
    end

    """
    Discard a potion from inventory
    """
    function discard_inventory_potion(this::ShopManager, potion_index::Int)
        if potion_index > length(this.user.potions)
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_potion_not_found])
            return
        end

        potion = this.user.potions[potion_index]

        # Remove potion from inventory
        deleteat!(this.user.potions, potion_index)

        JulGame.UserGlobals["Module"].RunRecorderModule.note_potion!(potion.key, "discarded")
        message = ShopStringsModule.format_string(:shop_potion_discarded, potion_name=potion.name)
        show_message(this, message)
        JulGame.UserGlobals["Module"].SaveManagerModule.try_save_run!()
    end

    potion_sell_price(potion)::Int = potion.average_price ÷ 2

    """
    Sell a potion from inventory
    """
    function sell_inventory_potion(this::ShopManager, potion_index::Int)
        if potion_index > length(this.user.potions)
            show_message(this, ShopStringsModule.SHOP_STRINGS[:shop_potion_not_found])
            return
        end

        potion = this.user.potions[potion_index]
        sell_price = potion_sell_price(potion)  # Sell for half price

        # Add gold and remove potion
        this.user.gold += sell_price
        OverworldFeedbackModule.gold!(sell_price)
        deleteat!(this.user.potions, potion_index)

        JulGame.UserGlobals["Module"].RunRecorderModule.note_potion!(potion.key, "sold")
        message = ShopStringsModule.format_string(:shop_potion_sold, potion_name=potion.name, price=sell_price)
        show_message(this, message)
        JulGame.UserGlobals["Module"].SaveManagerModule.try_save_run!()

        # Trigger grateful animation
        if this.shopkeeperAnimation !== nothing
            Scripts.ShopkeeperAnimationModule.trigger_grateful(this.shopkeeperAnimation)
        end
    end
end
