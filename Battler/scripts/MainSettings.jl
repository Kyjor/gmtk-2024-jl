module MainSettingsModule
    using JulGame
    using JulGame.Math
    include("utils/UIDropdown.jl")
    using .UIDropdownModule

    include("utils/UISlider.jl")
    using .UISliderModule

    include("utils/UICheckbox.jl")
    using .UICheckboxModule

    include(joinpath(@__DIR__, "Title", "GraphicsFunctions.jl"))
    include(joinpath(@__DIR__, "Title", "AudioFunctions.jl"))
    include(joinpath(@__DIR__, "Title", "AnalyticsFunctions.jl"))
    using ..Scripts
    include("localization/ui_strings.jl")
    using .UIStringsModule
    include("ConfirmationDialog.jl")
    import .ConfirmationDialogModule: ConfirmationDialog
    mutable struct MainSettings
        # Dropdowns
        resolutionDropdown::UIDropdown
        languageDropdown::UIDropdown
        
        # State tracking
        selectedResolution::String
        selectedLanguage::String
        parent::JulGame.Entity

        # Stats selection
        statsConfirmationText::JulGame.UI.UIElement
        statsDenialText::JulGame.UI.UIElement
        statsSelectionImage::JulGame.UI.UIElement

        # Sliders
        masterVolumeSlider::UISlider
        masterVolumeValueText::JulGame.UI.UIElement
        musicVolumeSlider::UISlider
        musicVolumeValueText::JulGame.UI.UIElement
        sfxVolumeSlider::UISlider
        sfxVolumeValueText::JulGame.UI.UIElement
        gameSpeedSlider::UISlider
        gameSpeedValueText::JulGame.UI.UIElement

        # Checkboxes
        screenShakeCheckbox::UICheckbox
        fullscreenCheckbox::UICheckbox
        fastModeCheckbox::UICheckbox
        
        # State tracking
        screenShakeEnabled::Bool
        checkmarkImage
        fullscreenCheckmarkImage
        fastModeCheckmarkImage

        # Settings
        graphicsSettings::GraphicsSettings
        audioSettings::AudioSettings
        analyticsSettings::AnalyticsSettings

        #buttons
        backButton::JulGame.UI.UIElement
        saveAndQuitButton::JulGame.UI.UIElement

        transitionManager
        settingsDisplayManager
        confirmationDialog::ConfirmationDialog
        wasSettingsActive::Bool
        persistentStateManager

        function MainSettings()
            this = new()
            this.confirmationDialog = ConfirmationDialog()
            this.wasSettingsActive = false
            return this
        end
    end

    """Reload analytics preference from disk and move the YES/NO selector to match."""
    function sync_analytics_selection_ui!(this::MainSettings)
        loaded = load_analytics_settings()
        this.analyticsSettings.analyticsEnabled = loaded.analyticsEnabled
        if this.statsSelectionImage !== nothing
            this.statsSelectionImage.position = loaded.analyticsEnabled ?
                Math.Vector2(290, 920) :
                Math.Vector2(530, 920)
        end
    end

    function _sync_fullscreen_checkbox_visual!(this::MainSettings, is_fs::Bool)
        this.fullscreenCheckbox.isChecked = is_fs
        if this.fullscreenCheckbox.checkedImage !== nothing
            this.fullscreenCheckbox.checkedImage.isActive = is_fs
        end
        if this.fullscreenCheckbox.uncheckedImage !== nothing
            this.fullscreenCheckbox.uncheckedImage.isActive = !is_fs
        end
        if this.fullscreenCheckmarkImage !== nothing
            this.fullscreenCheckmarkImage.isActive = is_fs
        end
    end

    function _select_resolution_dropdown_silent(this::MainSettings, value::String)
        for (i, item) in enumerate(this.resolutionDropdown.items)
            if string(item.value) == value
                UIDropdownModule.select_dropdown_item(this.resolutionDropdown, i, false)
                return
            end
        end
        @debug "Could not find resolution dropdown item for: $(value)"
    end

    function center_label_on_settings_button!(label, button)
        (label === nothing || button === nothing) && return
        label.parent = button
        label.anchor.current_state = :center
        # Sit on the isometric top face, not the 3D sides at the bottom of the sprite
        label.anchorOffset = Math.Vector2(0, -40)
        JulGame.UI.align_to_anchor(label)
    end

    # The baked effect texture is keyed on the text only when effects are applied; re-apply to rebake.
    function set_settings_value_text!(label, text::String)
        label.text = text
        UIDropdownModule.DisplayTextModule.apply_battle_number_text_effects!(label)
    end
    
    function JulGame.initialize(this::MainSettings)
        this.settingsDisplayManager = this.parent.scripts[6]
        @debug "MainSettings initialized"
         # Initialize settings
         this.graphicsSettings = GraphicsSettings()
         this.audioSettings = AudioSettings()
         this.analyticsSettings = AnalyticsSettings()
        # Initialize state based on current graphics settings
        this.selectedResolution = "$(this.graphicsSettings.width)x$(this.graphicsSettings.height)" * (this.graphicsSettings.fullscreen ? " FS" : "")
        this.persistentStateManager = JulGame.UserGlobals["Module"].get_data_manager().persistent_state_manager

         # Fullscreen toggle (UI must exist before resolution dropdown so the dropdown can sync the checkbox)
         this.fullscreenCheckbox = UICheckbox(
             "fullscreen_checkbox";
             position = Math.Vector2(0, 0),
             size = Math.Vector2(99, 95),
             isChecked = this.graphicsSettings.fullscreen,
             checkedImage = "a9f3e1c2-5d4b-4e1a-9f0c-8b7a6d5c4b3c",
             uncheckedImage = "a9f3e1c2-5d4b-4e1a-9f0c-8b7a6d5c4b3b",
             anchor = :topLeft,
             showOutline = true,
             outlineColor = (100, 200, 255, 150),
             outlineThickness = 2,
             glowOnHover = true,
             onValueChanged = (checkbox, value) -> begin
                 apply_graphics_settings(this.graphicsSettings; resolution = nothing, fullscreen = value)
                 this.selectedResolution = "$(this.graphicsSettings.width)x$(this.graphicsSettings.height)" * (value ? " FS" : "")
                 _select_resolution_dropdown_silent(this, this.selectedResolution)
                 if this.fullscreenCheckmarkImage !== nothing
                     this.fullscreenCheckmarkImage.isActive = value
                 end
             end,
             layer = 1010,
         )
         this.fullscreenCheckmarkImage = JulGame.SceneModule.get_ui_element_by_id("a9f3e1c2-5d4b-4e1a-9f0c-8b7a6d5c4b3d")
         if this.fullscreenCheckmarkImage !== nothing
             this.fullscreenCheckmarkImage.isActive = this.graphicsSettings.fullscreen
             this.fullscreenCheckmarkImage.ignoreInputEvents = true
         end
         if this.fullscreenCheckbox !== nothing
             if this.fullscreenCheckbox.checkedImage !== nothing
                 this.fullscreenCheckbox.checkedImage.isActive = this.graphicsSettings.fullscreen
             end
             if this.fullscreenCheckbox.uncheckedImage !== nothing
                 this.fullscreenCheckbox.uncheckedImage.isActive = !this.graphicsSettings.fullscreen
             end
         end

         # Create resolution dropdown
         this.resolutionDropdown = UIDropdown(
             "resolution_dropdown";
             maxVisibleItems = 4,
             closedImage = "6c402068-ede7-45e4-832f-ea49aaa97ead",        # Replace with actual image IDs
             itemImagePath = JulGame.UserGlobals["Module"].get_asset_path("ui", "dropdownitem"), # Path to item background image
             anchor = :none,
             showOutline = true,
             outlineColor = (100, 200, 255, 150),
             outlineThickness = 2,
             glowOnHover = true,
            onValueChanged = (dropdown, value) -> begin
                this.selectedResolution = value
                @debug("Resolution changed to: $value")
                # Detect ` FS` suffix to toggle fullscreen and strip suffix for resolution parsing
                isFullscreen = endswith(value, " FS")
                cleanValue = isFullscreen ? String(first(split(value, " "))) : String(value)
                apply_graphics_settings(this.graphicsSettings; resolution = cleanValue, fullscreen = isFullscreen)
                _sync_fullscreen_checkbox_visual!(this, isFullscreen)
            end,
            layer = 2010,
         )
         
         # Add resolution options (all 16:9 up to 4K)
        for resolution in get_available_resolutions()
             @debug "Resolution: $resolution"
             @debug "selected resolution: $(this.graphicsSettings.width)x$(this.graphicsSettings.height)"
             @debug "isSelected: $(resolution == "$(this.graphicsSettings.width)x$(this.graphicsSettings.height)")"
            add_dropdown_item(this.resolutionDropdown, resolution, resolution, isSelected = resolution == this.selectedResolution)
         end
         
         # Load saved language and apply it
        #  saved_language = load_language_setting()
        #  this.selectedLanguage = saved_language
         
         # Apply saved language to global setting
        #  try
        #      globals = JulGame.UserGlobals["Module"]
        #      data_manager = globals.get_data_manager()
        #      if saved_language in ["EN", "JP"]  # Supported languages
        #          old_lang = data_manager.current_language
        #          data_manager.current_language = saved_language
        #          @debug "Current language set to: $saved_language"
        #          # Notify observers if available
        #          if data_manager.observer !== nothing
        #              Scripts.Globals.ObserverModule.notify(data_manager.observer, :language_changed, (old=old_lang, new=saved_language))
        #          end
        #      end
        #  catch e
        #      @warn "Failed to set language on startup: $e"
        #  end
         
        #  # Create language dropdown
        #  this.languageDropdown = UIDropdown(
        #      "language_dropdown";
        #      maxVisibleItems = 5,
        #      closedImage = "b5545ef0-0f06-4604-8db8-171de0c67ce1",        # Replace with actual image IDs
        #      itemImagePath = "ui-dropdownitem-0000.png", # Path to item background image
        #      anchor = :none,
        #      showOutline = true,
        #      outlineColor = (100, 200, 255, 150),
        #      outlineThickness = 2,
        #      glowOnHover = true,
        #      layer = 1010,
        #      onValueChanged = (dropdown, value) -> begin
        #          this.selectedLanguage = value
        #          @debug("Language changed to: $value")
        #          # Update global language
        #          try
        #              globals = JulGame.UserGlobals["Module"]
        #              data_manager = globals.get_data_manager()
        #              if value in ["EN", "JP"]  # Supported languages
        #                  old_lang = data_manager.current_language
        #                  data_manager.current_language = value
        #                  @debug "Current language set to: $value"
        #                  # Notify observers if available
        #                  if data_manager.observer !== nothing
        #                      Scripts.Globals.ObserverModule.notify(data_manager.observer, :language_changed, (old=old_lang, new=value))
        #                  end
        #              end
        #          catch e
        #              @warn "Failed to set language: $e"
        #          end
        #          # Save the setting
        #          save_language_setting(value)
        #      end
        #  )
         
        #  # Add language options
        #  add_dropdown_item(this.languageDropdown, "English", "EN", isSelected = saved_language == "EN")
        #  add_dropdown_item(this.languageDropdown, "Japanese", "JP", isSelected = saved_language == "JP")

         this.masterVolumeValueText = JulGame.SceneModule.get_ui_element_by_id("6fec5a89-5c7a-4b17-b02d-a4296b77e41d")
         this.sfxVolumeValueText = JulGame.SceneModule.get_ui_element_by_id("e61b2a98-8f53-442f-b2d8-ad1131cb61f3")
         this.musicVolumeValueText = JulGame.SceneModule.get_ui_element_by_id("aebfd965-2948-41db-91fd-a4dfd91cfbd6")
         this.musicVolumeValueText.text = "$(string(this.audioSettings.musicVolume))%"
         this.sfxVolumeValueText.text = "$(string(this.audioSettings.sfxVolume))%"
         this.masterVolumeValueText.text = "$(string(this.audioSettings.masterVolume))%"
         this.gameSpeedValueText = JulGame.SceneModule.get_ui_element_by_id("de1dcb4b-7f93-407c-b87a-ed1e93cfed04")

         this.masterVolumeSlider = UISlider(
             "image_slider";
             anchor = :center,
             anchorOffset = Math.Vector2(0, 200),
             size = Math.Vector2(250, 30),
             knobSize = Math.Vector2(25, 35),
             direction = Horizontal,
             value = this.audioSettings.masterVolume / 100,
             minValue = 0.0,
             maxValue = 1.0,
             barImage = "ab9e22bf-d5b8-40b6-af5a-3d043e63bc02",  # Background bar image
             knobImage = "4d27aeb4-6a95-48c4-9590-6bab1fdfc308",  # Knob image
             onValueChanged = (slider, value) -> begin
                 set_settings_value_text!(this.masterVolumeValueText, "$(string(round(Int, value * 100)))%")
                 this.audioSettings.masterVolume = round(Int, value * 100)
                 apply_audio_settings(this.audioSettings)
                 @debug("Image slider value: $(value)")
             end,
             layer = 1010,
         )
         this.musicVolumeSlider = UISlider(
             "image_slider";
             anchor = :center,
             anchorOffset = Math.Vector2(0, 200),
             size = Math.Vector2(250, 30),
             knobSize = Math.Vector2(25, 35),
             direction = Horizontal,
             value = this.audioSettings.musicVolume / 100,
             minValue = 0.0,
             maxValue = 1.0,
             barImage = "157b0743-a115-43d6-8254-119f408ac9d3",  # Background bar image
             knobImage = "96681c5d-9a28-4970-b419-f9a1d85419ba",  # Knob image
             onValueChanged = (slider, value) -> begin
                 set_settings_value_text!(this.musicVolumeValueText, "$(string(round(Int, value * 100)))%")
                 this.audioSettings.musicVolume = round(Int, value * 100)
                 apply_audio_settings(this.audioSettings)
                 @debug("Image slider value: $(value)")
             end,
             layer = 1010,
         )
         this.sfxVolumeSlider = UISlider(
             "image_slider";
             anchor = :center,
             anchorOffset = Math.Vector2(0, 200),
             size = Math.Vector2(250, 30),
             knobSize = Math.Vector2(25, 35),
             direction = Horizontal,
             value = this.audioSettings.sfxVolume / 100,
             minValue = 0.0,
             maxValue = 1.0,
             barImage = "3f115db7-683a-4eb5-b098-86fe092e4855",  # Background bar image
             knobImage = "18757fc9-8559-416b-a37b-b7e6c5ac877c",  # Knob image
             onValueChanged = (slider, value) -> begin
                 set_settings_value_text!(this.sfxVolumeValueText, "$(string(round(Int, value * 100)))%")
                 this.audioSettings.sfxVolume = round(Int, value * 100)
                 apply_audio_settings(this.audioSettings)
                 @debug("Image slider value: $(value)")
             end,
             layer = 1010,
         )
         # Load saved game speed (slider value 0.0-1.0 maps to speed 0.5x-3.0x)
         default_slider_value = 0.2  # Maps to 1.0x speed (normal)
         saved_slider_value = load_game_speed_setting()
         this.gameSpeedSlider = UISlider(
             "image_slider";
             anchor = :center,
             anchorOffset = Math.Vector2(0, 200),
             size = Math.Vector2(250, 30),
             knobSize = Math.Vector2(25, 35),
             direction = Horizontal,
             value = saved_slider_value !== nothing ? saved_slider_value : default_slider_value,
             minValue = 0.0,
             maxValue = 1.0,
             barImage = "e882d28e-7e6e-4ff7-a53c-3e25d25b4122",  # Foreground bar image
             knobImage = "32b01e63-9d75-4711-986d-892bed17e158",  # Knob image
             onValueChanged = (slider, value) -> begin
                 # Convert slider value (0.0-1.0) to speed multiplier (0.5x-3.0x)
                 speed_multiplier = 0.5 + (value * 2.5)
                 speed_percent = round(Int, speed_multiplier * 100)
                 set_settings_value_text!(this.gameSpeedValueText, "$(speed_percent)%")
                 save_game_speed_setting(value)
                 # Update global game speed
                 update_global_game_speed(speed_multiplier)
             end,
             layer = 1010,
         )
         # Set initial display text
         initial_speed = 0.5 + (this.gameSpeedSlider.value * 2.5)
         this.gameSpeedValueText.text = "$(round(Int, initial_speed * 100))%"
         # Initialize global game speed
         update_global_game_speed(initial_speed)
         # Initialize state - load from saved settings
         this.screenShakeEnabled = load_screen_shake_setting()
         
         # Create music checkbox
         this.screenShakeCheckbox = UICheckbox(
             "screen_shake_checkbox";
             position = Math.Vector2(50, 150),
             size = Math.Vector2(30, 30),
             isChecked = this.screenShakeEnabled,
             checkedImage = "e86dd059-e546-42ef-a86b-e7e11523a2ed",    
             uncheckedImage = "8a529ec0-6e50-41ca-9dfa-3d0cce5bdb70",    
             anchor = :topLeft,
             showOutline = true,
             outlineColor = (100, 200, 255, 150),
             outlineThickness = 2,
             glowOnHover = true,
             onValueChanged = (checkbox, value) -> begin
                 this.screenShakeEnabled = value
                 save_screen_shake_setting(value)
                 @debug("Screen shake $(value ? "enabled" : "disabled")")
                 this.checkmarkImage.isActive = value
             end,
             layer = 1010,
         )

       this.statsConfirmationText = JulGame.SceneModule.get_ui_element_by_id("3371dcd6-8b22-4e21-9e0c-101ca56b2882")
       this.statsDenialText = JulGame.SceneModule.get_ui_element_by_id("074fc512-597b-4243-af9c-4ba713ab139a")
       this.statsSelectionImage = JulGame.SceneModule.get_ui_element_by_id("c25929a9-d4af-4028-b435-9d5dce36db62")
       sync_analytics_selection_ui!(this)

        this.checkmarkImage = JulGame.SceneModule.get_ui_element_by_id("d4f266bb-e580-434e-8da7-3f6ae73b6dec")
        # Set checkmark image state to match loaded setting
        if this.checkmarkImage !== nothing
            this.checkmarkImage.isActive = this.screenShakeEnabled
            this.checkmarkImage.ignoreInputEvents = true
        end
        
        # Ensure checkbox visual state is synced with loaded value
        # This will properly show/hide the checked/unchecked images
        if this.screenShakeCheckbox !== nothing
            if this.screenShakeCheckbox.checkedImage !== nothing
                this.screenShakeCheckbox.checkedImage.isActive = this.screenShakeEnabled
            end
            if this.screenShakeCheckbox.uncheckedImage !== nothing
                this.screenShakeCheckbox.uncheckedImage.isActive = !this.screenShakeEnabled
            end
        end

        # Fast Mode: resolve all matches of a batch at once instead of one by one
        fastModeEnabled = load_fast_mode_setting()
        this.fastModeCheckbox = UICheckbox(
            "fast_mode_checkbox";
            position = Math.Vector2(0, 0),
            size = Math.Vector2(99, 95),
            isChecked = fastModeEnabled,
            checkedImage = "b7d2c4e8-6f1a-4c3b-9e5d-2a8f7c6b5e4c",
            uncheckedImage = "b7d2c4e8-6f1a-4c3b-9e5d-2a8f7c6b5e4b",
            anchor = :topLeft,
            showOutline = true,
            outlineColor = (100, 200, 255, 150),
            outlineThickness = 2,
            glowOnHover = true,
            onValueChanged = (checkbox, value) -> begin
                save_fast_mode_setting(value)
                if this.fastModeCheckmarkImage !== nothing
                    this.fastModeCheckmarkImage.isActive = value
                end
            end,
            layer = 1010,
        )
        this.fastModeCheckmarkImage = JulGame.SceneModule.get_ui_element_by_id("b7d2c4e8-6f1a-4c3b-9e5d-2a8f7c6b5e4d")
        if this.fastModeCheckmarkImage !== nothing
            this.fastModeCheckmarkImage.isActive = fastModeEnabled
            this.fastModeCheckmarkImage.ignoreInputEvents = true
        end
        if this.fastModeCheckbox.checkedImage !== nothing
            this.fastModeCheckbox.checkedImage.isActive = fastModeEnabled
        end
        if this.fastModeCheckbox.uncheckedImage !== nothing
            this.fastModeCheckbox.uncheckedImage.isActive = !fastModeEnabled
        end
        fastModeText = JulGame.SceneModule.get_ui_element_by_id("b7d2c4e8-6f1a-4c3b-9e5d-2a8f7c6b5e4a")
        if fastModeText !== nothing
            fastModeText.text = UIStringsModule.UI_STRINGS[:settings_fast_mode]
        end
        closeButton = JulGame.SceneModule.get_ui_element_by_id("5dc599a3-d644-44d9-81bf-33ec822cb355")
        event = () -> begin 
            Scripts.SettingsDisplayManagerModule.close!(this.settingsDisplayManager)
            # Also update pauseMenu.paused state to match
            try
                gameManager = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "Game Manager")
                if gameManager !== nothing && length(gameManager.scripts) >= 5
                    pauseMenu = gameManager.scripts[5]
                    pauseMenu.paused = false
                end
            catch e
                @debug "Could not update pauseMenu state: $(e)"
            end

        end
        closeButton.clickEvents = Function[event]
             
        # Save and quit with confirmation
        quitEvent = () -> begin
            globals = JulGame.UserGlobals["Module"]
            ConfirmationDialogModule.show_confirmation(
                this.confirmationDialog,
                "Quit Game?",
                "Are you sure you want to quit? If you are in a battle, your current battle progress will be lost.",
                () -> begin
                    # Save the game
                    # if globals.save_game_data()
                    #     @debug "Game saved successfully, quitting"
                    # else
                    #     @debug "Failed to save game, but quitting anyway"
                    # end
                    MAIN.input.quit = true
                end,
                () -> @debug "Quit cancelled";
                layer = 99999
            )
        end
        quitText = JulGame.SceneModule.get_ui_element_by_id("0b28dca7-9ffe-4162-8346-b2bc64296aaa")
        this.saveAndQuitButton = JulGame.SceneModule.get_ui_element_by_id("3c02ffab-9fcc-4487-9d13-b69257e3b0b7")
        this.saveAndQuitButton.clickEvents = Function[quitEvent]
        quitText.clickEvents = Function[quitEvent]
        center_label_on_settings_button!(quitText, this.saveAndQuitButton)

        try
            this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
        catch e
            @error "SceneTransitionManager not found: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end
        return_text_element = JulGame.SceneModule.get_ui_element_by_id("4b53961a-bfdf-4182-8c89-342ab3731f90")
        this.backButton = JulGame.SceneModule.get_ui_element_by_id("ec2270f6-646e-4f4e-a46a-12952f1f72c7")
        return_scene = "title_scene.json"
        return_text = UIStringsModule.UI_STRINGS[:settings_main_menu]
        # Leaving a map node early rewinds to the checkpoint saved when the node was picked.
        leaves_node = MAIN.scene.name in ("battle", "event", "rest")
        if leaves_node
            return_scene = "map.json"
            return_text = UIStringsModule.UI_STRINGS[:settings_map]
        end
        return_text_element.text = return_text
        center_label_on_settings_button!(return_text_element, this.backButton)
        return_event = nothing
        if JulGame.MAIN.scene.name == "title_scene"
            # just close the settings menu
            return_event = () -> Scripts.SettingsDisplayManagerModule.close!(this.settingsDisplayManager)
        elseif leaves_node 
            return_event = () -> begin
                globals = JulGame.UserGlobals["Module"]
                if !this.persistentStateManager.isFloorComplete && !globals.SaveManagerModule.try_load_run!()
                    @warn "Could not restore pre-$(MAIN.scene.name) checkpoint"
                end
                Scripts.SceneTransitionModule.transition_to_scene(
                    this.transitionManager,
                    return_scene;
                    direction = Scripts.SceneTransitionModule.Fade,
                )
            end
        else
            direction = return_scene == "title_scene.json" ? Scripts.SceneTransitionModule.LeftToRight : Scripts.SceneTransitionModule.Fade
            return_event = () -> Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, return_scene; direction = direction)
        end
        this.backButton.clickEvents = Function[return_event]
        return_text_element.clickEvents = Function[return_event]

        for el in MAIN.scene.uiElements
            if el isa JulGame.TextBoxModule.TextBox && contains(el.name, "SettingsMenu_")
                UIDropdownModule.DisplayTextModule.apply_battle_number_text_effects!(el)
            end
        end
    end
    
    function JulGame.update(this::MainSettings, deltaTime)
        # Update confirmation dialog if showing (always update, even if settings canvas is inactive)
        if this.confirmationDialog.is_showing
            ConfirmationDialogModule.update(this.confirmationDialog, deltaTime)
        end
        
        settingsActive = this.settingsDisplayManager.settingsCanvas !== nothing &&
            this.settingsDisplayManager.settingsCanvas.isActive
        if settingsActive && !this.wasSettingsActive
            # First-run analytics prompt can write the pref after MainSettings init;
            # refresh the YES/NO selector whenever the panel opens.
            sync_analytics_selection_ui!(this)
        end
        this.wasSettingsActive = settingsActive
        Scripts.TutorialModule.update_primer!(this.settingsDisplayManager)
        if !settingsActive || Scripts.TutorialModule.is_primer_open()
            return
        end
        # Update stats selection
        update_stats_selection(this)

        # Update dropdowns
        update_dropdown(this.resolutionDropdown, deltaTime)
        # update_dropdown(this.languageDropdown, deltaTime)
        
        # Render dropdowns
        render_dropdown(this.resolutionDropdown)
#        render_dropdown(this.languageDropdown)

        # Render sliders
        update_slider(this.masterVolumeSlider, deltaTime)
        update_slider(this.musicVolumeSlider, deltaTime)
        update_slider(this.sfxVolumeSlider, deltaTime)
        update_slider(this.gameSpeedSlider, deltaTime)
        # Render sliders
        render_slider(this.masterVolumeSlider)
        render_slider(this.musicVolumeSlider)
        render_slider(this.sfxVolumeSlider)
        render_slider(this.gameSpeedSlider)
        # Update checkboxes
        render_checkbox(this.screenShakeCheckbox)
        render_checkbox(this.fullscreenCheckbox)
        render_checkbox(this.fastModeCheckbox)
    end
    
    function update_stats_selection(this::MainSettings)
        isClicked = JulGame.InputModule.get_mouse_button_pressed(1)
        if this.statsConfirmationText.isHovered && isClicked
            this.statsSelectionImage.position = Math.Vector2(290, 920)
            # Enable analytics
            apply_analytics_settings(this.analyticsSettings; enabled = true)
            @debug "Analytics enabled via settings"
        elseif this.statsDenialText.isHovered && isClicked
            this.statsSelectionImage.position = Math.Vector2(530, 920)
            # Disable analytics
            apply_analytics_settings(this.analyticsSettings; enabled = false)
            @debug "Analytics disabled via settings"
        end
    end
    function JulGame.on_shutdown(this::MainSettings)
        @debug "MainSettings shutdown"
    end

     # Generic settings saver function
     function save_settings_to_config(configPath::String, settings::Dict{String, Any})
        config = Dict{String, Any}()
        
        # Read existing config
        if isfile(configPath)
            open(configPath, "r") do file
                for line in eachline(file)
                    if contains(line, "=")
                        key, value = split(line, "=")
                        config[key] = value
                    end
                end
            end
        end
        
        # Update with new settings
        merge!(config, settings)
        
        # Write updated config
        open(configPath, "w") do file
            for (key, value) in config
                write(file, "$(key)=$(value)\n")
            end
        end
    end
    
    # Load screen shake setting from preference file
    function load_screen_shake_setting()
        screenShakeSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "screen_shake_settings.txt")
        if !isfile(screenShakeSettingsPath)
            touch(screenShakeSettingsPath)
            # Default to enabled
            return true
        end
        config = Dict{String, Any}()
        open(screenShakeSettingsPath, "r") do file
            for line in eachline(file)
                if contains(line, "=")
                    key, value = split(line, "=")
                    config[key] = value
                end
            end
        end
        
        # Default to enabled if not set
        screenShakeEnabled = parse(Int, get(config, "ScreenShakeEnabled", "1")) == 1
        @debug "Loaded screen shake enabled: $screenShakeEnabled"
        
        return screenShakeEnabled
    end
    
    # Save screen shake setting to preference file
    function save_screen_shake_setting(enabled::Bool)
        screenShakeSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "screen_shake_settings.txt")
        settings = Dict{String, Any}("ScreenShakeEnabled" => enabled ? "1" : "0")
        save_settings_to_config(screenShakeSettingsPath, settings)
        @debug "Saved screen shake enabled: $enabled"
    end
    
    # Global function to check if screen shake is enabled
    function is_screen_shake_enabled()
        return load_screen_shake_setting()
    end

    # Load fast mode setting from preference file (off by default)
    function load_fast_mode_setting()
        fastModeSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "fast_mode_settings.txt")
        if !isfile(fastModeSettingsPath)
            touch(fastModeSettingsPath)
            return false
        end
        config = Dict{String, Any}()
        open(fastModeSettingsPath, "r") do file
            for line in eachline(file)
                if contains(line, "=")
                    key, value = split(line, "=")
                    config[key] = value
                end
            end
        end

        return parse(Int, get(config, "FastModeEnabled", "0")) == 1
    end

    # Save fast mode setting to preference file
    function save_fast_mode_setting(enabled::Bool)
        fastModeSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "fast_mode_settings.txt")
        settings = Dict{String, Any}("FastModeEnabled" => enabled ? "1" : "0")
        save_settings_to_config(fastModeSettingsPath, settings)
        @debug "Saved fast mode enabled: $enabled"
    end

    # Global function to check if fast mode (resolve all matches at once) is enabled
    function is_fast_mode_enabled()
        get(ENV, "TEST_MODE", "false") == "true" && return true
        return load_fast_mode_setting()
    end
    
    # Load game speed setting from preference file (returns slider value 0.0-1.0)
    function load_game_speed_setting()
        gameSpeedSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "game_speed_settings.txt")
        if !isfile(gameSpeedSettingsPath)
            touch(gameSpeedSettingsPath)
            return nothing  # Use default
        end
        config = Dict{String, Any}()
        open(gameSpeedSettingsPath, "r") do file
            for line in eachline(file)
                if contains(line, "=")
                    key, value = split(line, "=")
                    config[key] = value
                end
            end
        end
        
        # Default to 0.2 (1.0x speed) if not set
        slider_value = parse(Float64, get(config, "GameSpeedSlider", "0.2"))
        @debug "Loaded game speed slider value: $slider_value"
        
        return slider_value
    end
    
    # Save game speed setting to preference file (saves slider value 0.0-1.0)
    function save_game_speed_setting(slider_value::Float64)
        gameSpeedSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "game_speed_settings.txt")
        settings = Dict{String, Any}("GameSpeedSlider" => string(slider_value))
        save_settings_to_config(gameSpeedSettingsPath, settings)
        @debug "Saved game speed slider value: $slider_value"
    end
    
    # Update global game speed multiplier (0.5x-3.0x)
    function update_global_game_speed(speed_multiplier::Float64)
        try
            globals = JulGame.UserGlobals["Module"]
            data_manager = globals.get_data_manager()
            if data_manager !== nothing
                data_manager.game_speed_multiplier = speed_multiplier
                @debug "Updated global game speed multiplier to: $(speed_multiplier)x"
            end
        catch e
            @warn "Failed to update global game speed: $(e)"
        end
    end
    
    # Get current game speed multiplier (0.5x-3.0x, default 1.0x)
    function get_game_speed_multiplier()
        try
            globals = JulGame.UserGlobals["Module"]
            data_manager = globals.get_data_manager()
            if data_manager !== nothing
                return data_manager.game_speed_multiplier
            end
        catch e
            @warn "Failed to get game speed: $(e)"
        end
        return 1.0  # Default to normal speed
    end
    
    # Load language setting from preference file
    function load_language_setting()
        languageSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "language_settings.txt")
        if !isfile(languageSettingsPath)
            touch(languageSettingsPath)
            # Default to English
            return "EN"
        end
        config = Dict{String, Any}()
        open(languageSettingsPath, "r") do file
            for line in eachline(file)
                if contains(line, "=")
                    key, value = split(line, "=")
                    config[key] = value
                end
            end
        end
        
        # Default to English if not set
        language = get(config, "Language", "EN")
        @debug "Loaded language: $language"
        
        return language
    end
    
    # Save language setting to preference file
    function save_language_setting(language::String)
        languageSettingsPath = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "language_settings.txt")
        settings = Dict{String, Any}("Language" => language)
        save_settings_to_config(languageSettingsPath, settings)
        @debug "Saved language: $language"
    end
    
end  # module

