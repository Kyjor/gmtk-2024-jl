module PauseMenuModule
    using JulGame
    using ..Scripts

    mutable struct PauseMenu <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        # This is where you define your script's fields
        # Example: speed::Float64

        paused::Bool

        scene_to_load::EditorExport{String}

        pauseMenuButton
        transitionManager

        function PauseMenu()
            this = new() # do not remove this line

            this.paused = false
            this.scene_to_load = "map.json"
            # this is where you initialize your script's fields
            # Example: this.speed = 1.0

            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    # This is where you should register collision events or other events
    # Do not remove this function
    function JulGame.initialize(this::PauseMenu)
        globals = JulGame.UserGlobals["Module"]
        this.pauseMenuButton = JulGame.SceneModule.get_ui_element_by_id("6cc5a58a-5ec2-4a22-ae16-b5c06bbd4064")
        if this.pauseMenuButton !== nothing
            this.pauseMenuButton.clickEvents = Function[]
            JulGame.UI.add_click_event(this.pauseMenuButton, () -> begin
                toggle_pause(this)
                globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "settings"), false, 1.0, 0, 1)
            end)
        end

        try
            this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
        catch e
            @error "SceneTransitionManager not found: $e"
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end

    # This is called every frame
    # Do not remove this function
    function JulGame.update(this::PauseMenu, deltaTime)
        if JulGame.InputModule.get_button_pressed("ESCAPE")
            toggle_pause(this)
        end

        # Sync paused state with settings canvas state (in case it was changed externally)
        try
            settingsDisplayManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[6]
            if settingsDisplayManager !== nothing && settingsDisplayManager.settingsCanvas !== nothing
                this.paused = settingsDisplayManager.settingsCanvas.isActive
            end
        catch e
            @debug "Could not sync pause state: $(e)"
        end

        # Display pause menu when paused
        display_pause_menu(this)
    end

    # This is called when the script is removed from an entity (scene change, entity deletion)
    # Do not remove this function
    function JulGame.on_shutdown(this::PauseMenu)
    end

    function toggle_pause(this::PauseMenu)
        settingsDisplayManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[6]
        Scripts.SettingsDisplayManagerModule.toggle_settings(settingsDisplayManager)
        this.paused = settingsDisplayManager.settingsCanvas.isActive
    end

    function display_pause_menu(this::PauseMenu)

    end
end
