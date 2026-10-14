module BackgroundModule
    using JulGame
    using ..Scripts

    # Draw the shared scrolling background one layer behind this sprite. Only useful once the
    # battle bg has a transparent sky (bg-floor1battle-0000.png is currently fully opaque).
    const SHOW_SCROLL_BG_BEHIND_BATTLE = false

    mutable struct Background <: Script
        parent

        function Background()
            this = new()

            this.parent = C_NULL

            return this
        end
    end

    function JulGame.initialize(this::Background)
    end

    function JulGame.update(this::Background, deltaTime)
        this.parent.transform.position = JulGame.Math.Vector3f(MAIN.scene.camera.position.x + 14.5, MAIN.scene.camera.position.y + 7.9, 0)
        if SHOW_SCROLL_BG_BEHIND_BATTLE && this.parent.sprite != C_NULL && this.parent.sprite !== nothing
            Scripts.ScratchModule.draw_scroll_bg!(; layer = this.parent.sprite.layer - 1, isWorldEntity = true)
        end
    end

    function JulGame.on_shutdown(this::Background)
    end
end # module