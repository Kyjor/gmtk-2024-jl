module SettingsDisplayManagerModule
    using JulGame
    using ..Scripts

    const BACKGROUND_NAME = "SettingsMenu_BG"
    const FADE_DURATION = 0.15
    const FLY_DURATION = 0.2
    const FLY_MAX_STAGGER = 0.1
    const TRANSITION_DURATION = FLY_DURATION + FLY_MAX_STAGGER
    const FLY_OVERSHOOT = 1.0

    # Easing functions for smooth animations
    function ease_out_bounce(x::Float64) :: Float64
        n1 = 7.5625
        d1 = 2.75
        
        if x < 1 / d1
            return n1 * x ^ 2
        elseif x < 2 / d1
            return n1 * (x - 1.5 / d1) ^ 2 + 0.75
        elseif x < 2.5 / d1
            return n1 * (x - 2.25 / d1) ^ 2 + 0.9375
        else
            return n1 * (x - 2.625 / d1) ^ 2 + 0.984375
        end
    end

    function ease_out_back(x::Float64; c1::Float64 = 1.70158) :: Float64
        c3 = c1 + 1
        
        return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
    end

    mutable struct SettingsDisplayManager
        parent
        settingsCanvas
        settingsLoaded::Bool
        background
        # 0 = closed, 1 = fully open
        transitionProgress::Float64
        isClosing::Bool
        visualsQueued::Bool
        lingerFrames::Int

        function SettingsDisplayManager()
            this = new()

            this.settingsLoaded = false
            this.background = nothing
            this.transitionProgress = 0.0
            this.isClosing = false
            this.visualsQueued = false
            this.lingerFrames = 0

            return this
        end
    end

    function JulGame.initialize(this::SettingsDisplayManager)
        if !this.settingsLoaded
            this.settingsCanvas = JulGame.MainLoopModule.create_new_canvas()
            this.settingsCanvas.persistentBetweenScenes = true

            for uiElement in MAIN.scene.uiElements
                if contains(uiElement.name, "SettingsMenu_")
                    uiElement.persistentBetweenScenes = true
                    uiElement.layer += 1000
                    push!(this.settingsCanvas.children, uiElement)
                    if uiElement.name == BACKGROUND_NAME
                        this.background = uiElement
                    end
                end
            end
            this.settingsLoaded = true
        end
        this.settingsCanvas.isActive = false
        this.transitionProgress = 0.0
        this.isClosing = false
        this.visualsQueued = false
        this.lingerFrames = 0
    end

    function JulGame.update(this::SettingsDisplayManager, deltaTime)
        if JulGame.IS_DEBUG && JulGame.InputModule.get_mouse_button_pressed(3)
            toggle_settings(this)
            @debug "settingsCanvas.isActive: $(this.settingsCanvas.isActive)"
            @debug "settingsCanvas.children length: $(length(this.settingsCanvas.children))"
        end

        if !this.settingsCanvas.isActive
            if this.lingerFrames > 0
                this.lingerFrames -= 1
                queue_transition_visuals!(this)
            end
            return
        end
        step = Float64(deltaTime) / TRANSITION_DURATION
        this.transitionProgress = clamp(this.transitionProgress + (this.isClosing ? -step : step), 0.0, 1.0)
        if this.isClosing && this.transitionProgress == 0.0
            this.isClosing = false
            this.settingsCanvas.isActive = false
            # Immediate UI parented to settings elements (dropdown label, How to play button)
            # survives up to 2 frames after its last draw; keep it flown off-screen until it expires.
            this.lingerFrames = 3
            queue_transition_visuals!(this)
            return
        end
        queue_transition_visuals!(this)
    end

    """Show the menu: background fades in, options fly up into place. Reverses a close in progress."""
    function open!(this::SettingsDisplayManager)
        this.isClosing = false
        this.lingerFrames = 0
        this.settingsCanvas.isActive = true
        # Opened after this frame's update: still hide the options this frame.
        queue_transition_visuals!(this)
    end

    """Reverse the open animation; the canvas is deactivated once it finishes."""
    function close!(this::SettingsDisplayManager)
        this.settingsCanvas.isActive || return
        this.isClosing = true
    end

    is_open(this::SettingsDisplayManager) = this.settingsCanvas.isActive && !this.isClosing

    function toggle_settings(this::SettingsDisplayManager)
        is_open(this) ? close!(this) : open!(this)
    end

    function queue_transition_visuals!(this::SettingsDisplayManager)
        this.visualsQueued && return
        this.visualsQueued = true

        elapsed = this.transitionProgress * TRANSITION_DURATION
        alpha = clamp(elapsed / FADE_DURATION, 0.0, 1.0)
        if this.background !== nothing
            c = this.background.color
            this.background.color = (c[1], c[2], c[3], round(Int, 255 * alpha))
            Scripts.ScratchModule.draw_scroll_bg!(; layer = this.background.layer, alpha = alpha)
        end

        # Offsets exist only while the UI pass renders, so hit-testing and scripts that
        # write positions (sliders, analytics selector) always see the resting layout.
        applied = Tuple{Any, JulGame.Math.Vector2, Bool}[]
        JulGame.Rendering.queue_render_function(
            () -> apply_fly_offsets!(this, applied, elapsed);
            layer = typemin(Int),
            isWorldEntity = false,
        )
        JulGame.Rendering.queue_render_function(
            () -> begin
                revert_fly_offsets!(applied)
                this.visualsQueued = false
            end;
            layer = typemax(Int),
            isWorldEntity = false,
        )
    end

    is_anchored(uiElement) = uiElement.anchor !== nothing && uiElement.anchor.current_state != :none

    function apply_fly_offsets!(this::SettingsDisplayManager, applied, elapsed::Float64)
        elapsed >= TRANSITION_DURATION && return
        screenHeight = Float64(MAIN.scene.camera.size.y)
        for uiElement in this.settingsCanvas.children
            anchored = is_anchored(uiElement)
            # Anchored children follow their parent's offset
            (uiElement === this.background || (anchored && uiElement.parent !== nothing)) && continue
            delay = FLY_MAX_STAGGER * clamp(uiElement.position.y / screenHeight, 0.0, 1.0)
            t = clamp((elapsed - delay) / FLY_DURATION, 0.0, 1.0)
            dy = round(Int, (1.0 - ease_out_back(t; c1 = FLY_OVERSHOOT)) * screenHeight)
            dy == 0 && continue
            offset = JulGame.Math.Vector2(0, dy)
            uiElement.position += offset
            anchored && (uiElement.anchorOffset += offset)
            push!(applied, (uiElement, offset, anchored))
        end
    end

    function revert_fly_offsets!(applied)
        for (uiElement, offset, anchored) in applied
            uiElement.position -= offset
            anchored && (uiElement.anchorOffset -= offset)
        end
    end

    function is_settings_open()
        try
            ent = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc")
            ent === nothing && return false
            for script in ent.scripts
                if script isa SettingsDisplayManager
                    return script.settingsCanvas !== nothing && script.settingsCanvas.isActive
                end
            end
        catch
        end
        return false
    end

    function JulGame.on_shutdown(this::SettingsDisplayManager)
    end 
end
