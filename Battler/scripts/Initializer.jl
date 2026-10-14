   

module InitializerModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.EffectsModule
    include("utils/Constants.jl")
    using ..Scripts

    mutable struct Initializer <: Script
        parent
        bagUI
        uiBackground
        settingsUI
        moneyUI
        user

        potionSlotPanel 
        potionSlot1
        potionSlot2
        potionSlot3
        potionSlot4


        function Initializer()
            this = new()

            this.moneyUI = nothing
            this.uiBackground = nothing
            this.bagUI = nothing
            this.settingsUI = nothing
            this.user = nothing

            this.potionSlotPanel = nothing
            this.potionSlot1 = nothing
            this.potionSlot2 = nothing
            this.potionSlot3 = nothing
            this.potionSlot4 = nothing

            return this
        end
    end

    function JulGame.initialize(this::Initializer)
        # Apply audio settings to ensure they persist across scene changes
        try
            globals = JulGame.UserGlobals["Module"]
            globals.register_existing_sounds()
            # @debug "Applying audio volumes on initialization of Initializer"
            # globals.apply_audio_volumes()
            @debug("Applied audio settings on User initialization")
        catch e
            @warn("Failed to apply audio settings: $e")
        end
        this.user = JulGame.UserGlobals["Module"].get_user_data()
        this.moneyUI = JulGame.SceneModule.get_ui_element_by_id("149e1989-c4be-4de0-95da-5d3642e234a8")
        this.uiBackground = JulGame.SceneModule.get_ui_element_by_id("ed096d64-33b9-4818-b451-6c0c18c71861")
        this.bagUI = JulGame.SceneModule.get_ui_element_by_id("77b0eee2-0df4-4aeb-b443-b52f51850fd2")
        this.settingsUI = JulGame.SceneModule.get_ui_element_by_id("6cc5a58a-5ec2-4a22-ae16-b5c06bbd4064")
        wire_hud_hover!(this.bagUI)
        wire_hud_hover!(this.moneyUI)
        wire_hud_hover!(this.settingsUI)
        allExist = this.moneyUI !== nothing && this.uiBackground !== nothing && this.bagUI !== nothing && this.settingsUI !== nothing
        if allExist && (MAIN.scene.name == "title_scene" || MAIN.scene.name == "title_scene_settings")
            this.moneyUI.isActive = false
            this.uiBackground.isActive = false
            this.bagUI.isActive = false
            this.settingsUI.isActive = false
        elseif allExist
            this.moneyUI.isActive = true
            this.uiBackground.isActive = true
            this.bagUI.isActive = true
            this.settingsUI.isActive = true
        end
    end

    function wire_hud_hover!(element)
        element === nothing && return
        try
            length(element.hoverEnterEvents) > 0 && return
        catch
        end
        JulGame.UI.add_hover_enter_event(element, () -> begin
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(), globals.get_asset_path("sfx", "tick1"), false, 1.0, 0, 1,
            )
            Scripts.ShakeEffectControllerModule.shake_effect(element;
                intensity=3.5f0,
                duration=0.4f0,
                frequency=6.0f0,
                rotation_intensity=0.5f0,
                position_intensity=1.0f0,
                use_sine_wave=true,
            )
        end)
    end

    function JulGame.update(this::Initializer, dt::Float64)
        if this.moneyUI !== nothing && this.moneyUI.isActive
            # render immediate text with the money value
            DisplayTextModule.display_text(
                "money_text",
                "$(this.user.gold)";
                fontSize = BATTLE_NUMBER_FONT_SIZE,
                fontPath = BATTLE_NUMBER_FONT,
                anchor = :bottomRight,
                anchorOffset = JulGame.Math.Vector2(
                    0,
                    -5
                ),
                color = (255, 255, 255, 255),
                parent = this.moneyUI
            )
        end
    end
end
