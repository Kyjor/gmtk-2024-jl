module TitleModule
    using JulGame 
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.UI.TextBoxModule
    using JulGame.EffectsModule
    using JulGame.EffectRendererModule
    using JulGame.FX.ImageFXModule 
    using ..Scripts
    include("utils/UIFloatingAnimation.jl")
    using .UIFloatingAnimationModule

    include("Title/MenuStructs.jl")
    include("Acknowledgments.jl")
    using .AcknowledgmentsModule
    include("ConfirmationDialog.jl")
    using .ConfirmationDialogModule
    include("ReleaseNotesDisplay.jl")
    using .ReleaseNotesDisplayModule
    include("localization/ui_strings.jl")
    using .UIStringsModule

    # Structure to hold game settings
    mutable struct Title
        fade
        parent
        availableLanguages
        selectedLanguage
        
        versionNumber::String
        releaseNotesDisplay::Union{Nothing, ReleaseNotesDisplayModule.ReleaseNotesDisplay}

        # Update Title struct to use MenuItems
        mainMenuItems::Vector{JulGame.UI.UIElement}
        selectedItem::Union{Nothing, JulGame.UI.UIElement}

        #main menu
        logo::Union{Nothing, JulGame.UI.UIElement}
        logoFloat::UIFloatingAnimation
        logoBaseAnchorY::Float64
        playText::Union{Nothing, JulGame.UI.UIElement}
        settingsText::Union{Nothing, JulGame.UI.UIElement}
        settingsCog::Union{Nothing, JulGame.UI.UIElement}
        quitText::Union{Nothing, JulGame.UI.UIElement}
        doorExit::Union{Nothing, JulGame.UI.UIElement}
        # Character selection
        characterSelection
        necropedia

        # Pre-built version label (avoid immediate_text every frame on the title menu)
        versionImmediate
        
        # Confirmation dialog
        confirmationDialog::Union{Nothing, ConfirmationDialogModule.ConfirmationDialog}
        
        # Settings cog animation
        settingsCogTargetRotation::Float64
        settingsCogCurrentRotation::Float64
        settingsCogAnimationSpeed::Float64

        effect::Any

        settingsButton::JulGame.UI.UIElement

        transitionManager
        acknowledgmentManager::AcknowledgmentsModule.AcknowledgmentManager
        
        function Title()
            this = new()

            this.fade = true
            this.parent = C_NULL
            this.availableLanguages = ["EN", "JP"]
         
            this.selectedLanguage = this.availableLanguages[1]
            
            # Initialize settings cog animation
            this.settingsCogTargetRotation = 0.0
            this.settingsCogCurrentRotation = 0.0
            this.settingsCogAnimationSpeed = 8.0  # Speed of rotation animation
            
            globals = JulGame.UserGlobals["Module"]
            this.versionNumber = globals.get_version()
            
            # Initialize release notes display
            this.releaseNotesDisplay = ReleaseNotesDisplayModule.ReleaseNotesDisplay()
            ReleaseNotesDisplayModule.initialize(this.releaseNotesDisplay, globals)
            
            # Initialize acknowledgment manager
            this.acknowledgmentManager = AcknowledgmentsModule.AcknowledgmentManager()
            
            # Initialize confirmation dialog
            this.confirmationDialog = ConfirmationDialogModule.ConfirmationDialog()

            this.logoFloat = UIFloatingAnimation(
                speed = 0.45,
                verticalAmplitude = 10.0,
                horizontalAmplitude = 0.0,
                rotationAmplitude = 0.0,
            )
            this.logoBaseAnchorY = 0.0
            
            return this
        end
    end

    # Helper function to add standard menu item effects
    function apply_standard_menu_effects(element, includeGlow::Bool = false)
        effects = [
            RoughEdgeEffect(amount=3, seed=123, erosion=true),
            DropShadowEffect(distance=20.0, angle=80.0, blur_radius=6, color=(0,0,0,20), opacity=20)
        ]
        
        if includeGlow
            push!(effects, OuterGlowEffect(radius=4, color=(50,49,70,255), blur=0.7, force_white=true))
        end
        
        JulGame.apply_effects!(element, effects)
    end
    
    function play_title_menu_hover_sound()
        g = JulGame.UserGlobals["Module"]
        g.AudioManagerModule.play_audio_oneshot(g.get_audio_manager(), g.get_asset_path("sfx", "tick1"), false, 1.0, 0, 1)
    end

    # Helper function to setup menu item with click and hover events
    function setup_menu_item(this::Title, element, clickEvent, includeGlow::Bool = false)
        if element === nothing
            return
        end
        
        JulGame.UI.add_click_event(element, clickEvent)
        JulGame.UI.add_hover_enter_event(element, () -> begin
            this.selectedItem = element
            get_shake_effect_event(element)()
        end)
        push!(this.mainMenuItems, element)
        apply_standard_menu_effects(element, includeGlow)
    end

    """
    Start a new run - resets all state and opens character selection
    """
    function start_new_run(this::Title, globals)
        @debug "Starting new run - resetting all state"
        
        globals.AnalyticsModule.track_abandoned_run(globals.get_analytics_data())
        globals.SaveManagerModule.delete_run_save!()
        
        # Reset persistent state
        persistentState = globals.get_data_manager().persistent_state_manager
        globals.PersistentStateManagerModule.reset_for_new_run(persistentState)
        
        # Reset player
        user = globals.get_user_data()
        globals.UserModule.reset_player(user)

        try
            JulGame.UserGlobals["Module"].AchievementTrackerModule.track_stat!("runs_started")
        catch e
            @debug "Could not track runs_started: $e"
        end
        
        # Open character selection
        Scripts.CharacterSelectionModule.open(this.characterSelection)
    end

    function JulGame.initialize(this::Title)
        this.characterSelection = Scripts.CharacterSelectionModule.CharacterSelection()
        this.necropedia = Scripts.NecropediaModule.Necropedia()

        this.effect = nothing

        globals = JulGame.UserGlobals["Module"]
        globals.SteamModule.set_rich_presence(globals.get_steam_data(), "AtMainMenu")

        # Kick off async baking of map hover glow textures while the player
        # is on the title screen, so map hover never spikes a frame
        try
            Scripts.MapManagerModule.prewarm_hover_effect_textures()
        catch e
            @warn "Failed to start hover effect prewarm: $e"
        end

        # Create scene transition manager if it doesn't exist
        try
            this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
            this.characterSelection.transitionManager = this.transitionManager
        catch e
            @error "SceneTransitionManager not found: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end

        @time "title init: character selection" Scripts.CharacterSelectionModule.initialize(this.characterSelection)

        this.versionImmediate = DisplayTextModule.display_text(
            "version_text",
            this.versionNumber;
            fontPath = "Century-Normal.ttf",
            fontSize = 24,
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(5, -21),
            lifetime = JulGame.ImmediateUIModule.INFINITE_LIFETIME,
        )
        this.versionImmediate.isActive = false

        this.mainMenuItems = []
        this.selectedItem = nothing

        this.playText = JulGame.SceneModule.get_ui_element_by_name("PlayText")
        this.quitText = JulGame.SceneModule.get_ui_element_by_name("QuitText")
        this.settingsText = JulGame.SceneModule.get_ui_element_by_name("SettingsText")
        rectangle = JulGame.SceneModule.get_ui_element_by_id("8d625411-a72e-430b-beb9-fcb438121661")
        newRunText = JulGame.SceneModule.get_ui_element_by_id("ae8b52c8-f648-41ed-9067-9f1bcbeadd57")
        this.settingsCog = JulGame.SceneModule.get_ui_element_by_id("09193d27-3014-40d0-872d-f2d980c4452b")
        this.logo = JulGame.SceneModule.get_ui_element_by_id("3b43ed23-e97a-4e7a-abf5-e36ca601b20d")
        this.doorExit = JulGame.SceneModule.get_ui_element_by_id("74dd5d3d-522d-45cb-96c5-6a6ce876088c")
        settingsDisplayManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[6]

        # Setup settings button
        if this.settingsText !== nothing
            @debug "adding settings button"
            settingsClickEvent = () -> begin
                Scripts.SettingsDisplayManagerModule.open!(settingsDisplayManager)
                globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "settings"), false, 1.0, 0, 1)
            end
            setup_menu_item(this, this.settingsText, settingsClickEvent, false)
        end
        
        # Setup quit button
        if this.quitText !== nothing
            quitClickEvent = () -> MAIN.input.quit = true
            setup_menu_item(this, this.quitText, quitClickEvent, true)
        end
        # Setup logo
        if this.logo !== nothing
            get_shake_effect_event(this.logo, 100.0f0, false)
            JulGame.apply_effects!(this.logo, [
                OuterGlowEffect(radius=4, color=(50,49,70,255), blur=0.7, force_white=true),
            ])
            initialize_ui_floating_animation(this.logoFloat, this.logo)
            try
                this.logoBaseAnchorY = Float64(this.logo.anchorOffset.y)
            catch
                this.logoBaseAnchorY = 0.0
            end
            push!(this.mainMenuItems, this.logo)
        end
        
        # Setup play/new run buttons
        playClickEvent = () -> begin
            globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "newrun"), false, 1.0, 0, 1)
            
            # Check if there's an active run
            persistentState = globals.get_data_manager().persistent_state_manager
            if persistentState.isRunActive || globals.SaveManagerModule.has_disk_save()
                # Show confirmation dialog - using JSON-based localization
                ConfirmationDialogModule.show_confirmation(
                    this.confirmationDialog,
                    globals.get_localized_string("UI_Title_New_Run_Title", "New Run"),
                    globals.get_localized_string("UI_Title_New_Run_Message", "Starting a new run will erase your current progress.\n\nAre you sure you want to continue?"),
                    () -> start_new_run(this, globals),
                    nothing;
                    confirm_text = globals.get_localized_string("UI_Start_New_Run", "Start New Run"),
                    cancel_text = globals.get_localized_string("UI_Cancel_Button", "Cancel")
                )
            else
                # No active run, proceed directly
                start_new_run(this, globals)
            end
        end
        
        if rectangle !== nothing
            JulGame.apply_effects!(rectangle, [
                RoughEdgeEffect(amount=1, seed=123, erosion=true),
            ])
            JulGame.UI.add_click_event(rectangle, playClickEvent)
            if newRunText !== nothing
                JulGame.UI.add_hover_enter_event(rectangle, () -> begin
                    this.selectedItem = newRunText
                    get_shake_effect_event(newRunText)()
                    rectangle.path = globals.get_asset_path("ui", "newgameboxhovered")
                end)
                JulGame.UI.add_hover_exit_event(rectangle, () -> begin
                    rectangle.path = globals.get_asset_path("ui", "newgamebox")
                end)
                JulGame.apply_effects!(newRunText, Any[
                    BevelEmbossEffect(; style=LAYER_INNER_BEVEL, size_px=16, soften=2.9999995f0, depth=62, angle=90.0, altitude=61.0, direction_up=true, contour_enabled=false, range_pct=100, contour_lut=identity_emboss_lut(), contour_antialiased=true, gloss_enabled=true, gloss_lut=identity_emboss_lut(), gloss_antialiased=false, texture_enabled=false, texture_path="", texture_tile=true, texture_scale=100, texture_phase_h_pct=0, texture_phase_v_pct=0, texture_align_with_layer=true, texture_depth=50.0, texture_invert=false, highlight_color=(255, 255, 255, 255), shadow_color=(35, 15, 35, 255), highlight_opacity=166, shadow_opacity=140, highlight_blend=BB_NORMAL, shadow_blend=BB_OVERLAY, intensity=1.0),
                    RoughEdgeEffect(; amount=3, seed=42001, erosion=true)
                ])
            end
            push!(this.mainMenuItems, rectangle)
        end
        
        if newRunText !== nothing
            JulGame.UI.add_click_event(newRunText, playClickEvent)
            push!(this.mainMenuItems, newRunText)
        end
        if this.settingsCog !== nothing
            JulGame.apply_effects!(this.settingsCog, [
                InvertEffect()
            ])
            
            # Add hover events for gear rotation animation
            JulGame.UI.add_hover_enter_event(this.settingsText, () -> begin
                this.settingsCogTargetRotation = 45.0
            end)
            JulGame.UI.add_hover_exit_event(this.settingsText, () -> begin
                this.settingsCogTargetRotation = 0.0
            end)
            
            push!(this.mainMenuItems, this.settingsCog)
        end
        if this.doorExit !== nothing
            if this.quitText !== nothing
                JulGame.UI.add_hover_enter_event(this.quitText, () -> begin
                    this.doorExit.path = globals.get_asset_path("ui", "exitdooropen")
                end)
                JulGame.UI.add_hover_exit_event(this.quitText, () -> begin
                    this.doorExit.path = globals.get_asset_path("ui", "exitdoorclosed")
                end)
            end
            push!(this.mainMenuItems, this.doorExit)
        end

        discordButton = JulGame.SceneModule.get_ui_element_by_id("discord_link_image")
        if discordButton !== nothing
            JulGame.UI.add_click_event(discordButton, () -> begin
                JulGame.SDL2.SDL_OpenURL("https://discord.gg/gFkrEtA35m")
            end)
            JulGame.UI.add_hover_enter_event(discordButton, () -> begin
                play_title_menu_hover_sound()
                discordButton.path = globals.get_asset_path("promo", "discordhovered")
            end)
            JulGame.UI.add_hover_exit_event(discordButton, () -> begin
                discordButton.path = globals.get_asset_path("promo", "discord")
            end)
            push!(this.mainMenuItems, discordButton)
        end
        steamButton = JulGame.SceneModule.get_ui_element_by_id("wishlist_link_image")
        if steamButton !== nothing
            JulGame.UI.add_click_event(steamButton, () -> begin
                JulGame.SDL2.SDL_OpenURL("https://store.steampowered.com/app/1410040?utm_source=title")
            end)
            JulGame.UI.add_hover_enter_event(steamButton, () -> begin
                play_title_menu_hover_sound()
                steamButton.path = globals.get_asset_path("promo", "wishlisthovered")
            end)
            JulGame.UI.add_hover_exit_event(steamButton, () -> begin
                steamButton.path = globals.get_asset_path("promo", "wishlist")
            end)
            push!(this.mainMenuItems, steamButton)
        end

        testMode = get(ENV, "BUILD_MODE_TEST", "false") == "true" || get(ENV, "TEST_MODE", "false") == "true"
        tmName = "TestManager"
        testManager = JulGame.SceneModule.get_entity_by_name(tmName)
        if testMode && testManager === nothing
            testManager = JulGame.EntityModule.Entity(tmName)
            testManager.scripts = [Scripts.TestManagerModule.TestManager()]
            testManager.scripts[1].parent = testManager
            JulGame.initialize(testManager.scripts[1])
            @debug "Initialized test manager"
            testManager = JulGame.create_entity(testManager)
            @debug "Created test manager"
            testManager.persistentBetweenScenes = true
        end

        # Set up analytics choice callback
        this.acknowledgmentManager.on_analytics_choice = (enabled::Bool) -> begin
            globals = JulGame.UserGlobals["Module"]
            @debug "Analytics choice made: $enabled"
            # Load or create analytics settings and save the choice
            analyticsSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "analytics_settings.txt")
            globals.save_settings_to_config(analyticsSettingsPath, Dict("AnalyticsEnabled" => enabled ? "1" : "0"))
            
            # Update the global analytics instance
            try
                analytics_data = globals.get_analytics_data()
                analytics_data.is_analytics_enabled = enabled
                @debug "Updated global analytics enabled state to: $enabled"
                
                # If user enabled analytics, track the startup now
                if enabled
                    # Set user_id_hashed if not already set (Steam ID)
                    if analytics_data.user_id_hashed == 0
                        try
                            steam = globals.get_steam_data()
                            analytics_data.user_id_hashed = steam.steam_id
                        catch e
                            @warn "Could not get Steam ID for analytics: $e"
                        end
                    end
                    JulGame.UserGlobals["Module"].AnalyticsModule.track_startup(analytics_data)
                end
            catch e
                @error "Error updating global analytics state: $e"
            end
        end
        
        if get(ENV, "TEST_MODE", "false") == "false"
            AcknowledgmentsModule.show_acknowledgments(this.acknowledgmentManager, ["early_access", "analytics"])
        end
    end

    function get_shake_effect_event(element, duration=0.4f0, useAudio::Bool=true)
        @debug "Starting shake effect on $(element.name)"
        hoverEnterEvent = () -> begin
            @debug "Starting shake effect on newRunText"
            if useAudio
                globals = JulGame.UserGlobals["Module"]
                globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "tick1"), false, 1.0, 0, 1)
            end
            Scripts.ShakeEffectControllerModule.shake_effect(element; 
                intensity=3.5f0, 
                duration=duration, 
                frequency=6.0f0,
                rotation_intensity=0.5f0,
                position_intensity=1.0f0,
                use_sine_wave=true
            )
        end
        return hoverEnterEvent
    end

    function display_necropedia_menu_link(this::Title)
        Scripts.NecropediaModule.create_menu_link(this.necropedia, play_title_menu_hover_sound)
    end

    function JulGame.update(this::Title, deltaTime)
        # Bake deferred character-select effect textures a little at a time
        # while the player sits on the title screen (see CharacterSelection.initialize).
        Scripts.CharacterSelectionModule.pump_effect_warm_queue!(this.characterSelection)

        # @static if ccall(:jl_generating_output, Cint, ()) == 0 || JulGame.IS_DEBUG
        #     @debug "Title.update not generating output"
        # end
        # @static if ccall(:jl_generating_output, Cint, ()) == 1 #|| JulGame.IS_DEBUG
        #     @debug "Title.update generating output"
        # end
        # if ccall(:jl_generating_output, Cint, ()) == 0
        #     @debug "Title.update not generating output -- non static"
        # end
        # Update acknowledgment manager first (blocks other UI when showing)
        AcknowledgmentsModule.update(this.acknowledgmentManager, deltaTime)
        
        # Update confirmation dialog (also blocks other UI when showing)
        if this.confirmationDialog !== nothing
            ConfirmationDialogModule.update(this.confirmationDialog, deltaTime)
        end
        
        # Update release notes display (handles its own input)
        if this.releaseNotesDisplay !== nothing
            globals = JulGame.UserGlobals["Module"]
            ReleaseNotesDisplayModule.update(this.releaseNotesDisplay, globals, deltaTime)
        end
        
        # Only process other UI if acknowledgments, confirmation dialog, and release notes are not showing
        isDialogShowing = (this.confirmationDialog !== nothing && this.confirmationDialog.is_showing)
        isReleaseNotesShowing = (this.releaseNotesDisplay !== nothing && ReleaseNotesDisplayModule.is_displaying(this.releaseNotesDisplay))
        if !this.acknowledgmentManager.is_showing && !isDialogShowing && !isReleaseNotesShowing
            if this.necropedia.isActive
                if this.necropedia.menuLink !== nothing
                    this.necropedia.menuLink.isActive = false
                end
                if this.versionImmediate !== nothing
                    this.versionImmediate.isActive = false
                end
                for item in this.mainMenuItems
                    item.isActive = false
                end
                Scripts.NecropediaModule.handle_input(this.necropedia, deltaTime)
            elseif this.characterSelection.isActive
                if this.necropedia.menuLink !== nothing
                    this.necropedia.menuLink.isActive = false
                end
                if this.versionImmediate !== nothing
                    this.versionImmediate.isActive = false
                end
                for item in this.mainMenuItems
                    item.isActive = false
                end
                Scripts.CharacterSelectionModule.handle_input(this.characterSelection, deltaTime)
            else
                display_necropedia_menu_link(this)
                for item in this.mainMenuItems
                    item.isActive = true
                end
                display_version_number(this)
                if this.selectedItem !== nothing
                    handle_text_fade(this)
                    handle_mouse_hover(this)
                end

                # Update settings cog rotation animation
                update_settings_cog_animation(this, deltaTime)
                update_logo_bob!(this, Float64(deltaTime))
            end
        end

        # Subtle indicator while hover effect textures are baked in the background
        if JulGame.SpriteModule.effect_prewarm_pending() ||
           Scripts.CharacterSelectionModule.effect_warm_pending(this.characterSelection)
            DisplayTextModule.display_text(
                "effect_prewarm_loading",
                "Loading...";
                fontPath = "Century-Normal.ttf",
                fontSize = 18,
                anchor = :bottomRight,
                anchorOffset = Math.Vector2(-10, -28),
                color = (255, 255, 255, 160)
            )
        end
    end

    function handle_mouse_hover(this::Title)
        for element in this.mainMenuItems
            if element.isHovered
                if this.selectedItem != element
                    this.selectedItem.color = (255, 255, 255, 255)
                    this.selectedItem = this.selectedItem
                end
            end
        end
    end

    function display_version_number(this::Title)
        if this.versionImmediate === nothing
            return
        end
        this.versionImmediate.text = this.versionNumber
        this.versionImmediate.isActive = true
    end


    # Centralized function to handle text fade effects for menu items
    function handle_text_fade(this::Title)
        if this.selectedItem === nothing
            return
        end
        if this.fade 
            # Fade out (decrease alpha)
            current_alpha = this.selectedItem.color[4]
            new_alpha = max(current_alpha - 8, 50)
           # @debug "setting color to $(this.selectedItem.color[1]), $(this.selectedItem.color[2]), $(this.selectedItem.color[3]), $(new_alpha)"
            JulGame.UI.set_color(this.selectedItem; a=new_alpha)
            
            # Check if we've reached minimum alpha
            if new_alpha <= 50
                this.fade = false
            end
        else
            # Fade in (increase alpha)
            current_alpha = this.selectedItem.color[4]
            new_alpha = min(current_alpha + 8, 255)
            JulGame.UI.set_color(this.selectedItem; a=new_alpha)
            
            # Check if we've reached maximum alpha
            if new_alpha >= 255
                this.fade = true
            end
        end
    end

    function update_logo_bob!(this::Title, deltaTime::Float64)
        this.logo === nothing && return
        update_ui_floating_animation(this.logoFloat, deltaTime)
        try
            dy = Float64(this.logo.position.y) - Float64(this.logoFloat.basePosition.y)
            ao = this.logo.anchorOffset
            this.logo.anchorOffset = Math.Vector2(ao.x, this.logoBaseAnchorY + dy)
        catch
        end
    end

    function update_settings_cog_animation(this::Title, deltaTime::Float64)
        if this.settingsCog === nothing
            return
        end
        
        # Smoothly interpolate towards target rotation
        diff = this.settingsCogTargetRotation - this.settingsCogCurrentRotation
        if abs(diff) > 0.1
            # Use lerp for smooth animation
            lerpSpeed = this.settingsCogAnimationSpeed * deltaTime
            this.settingsCogCurrentRotation += diff * min(lerpSpeed, 1.0)
            
            # Apply the rotation to the actual UI element
            this.settingsCog.rotation = this.settingsCogCurrentRotation
        else
            # Snap to target when close enough
            this.settingsCogCurrentRotation = this.settingsCogTargetRotation
            this.settingsCog.rotation = this.settingsCogCurrentRotation
        end
    end

    function get_text(key::String, default::String)
        globals = JulGame.UserGlobals["Module"]
        return get(globals.get_localization_data(), "\$gamedata.Localization.$(globals.get_current_language()).$(key)", default)
    end

end # module

