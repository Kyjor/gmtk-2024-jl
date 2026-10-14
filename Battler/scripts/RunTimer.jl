module RunTimerModule
    using JulGame

    mutable struct RunTimer
        parent
        elapsedTime

        function RunTimer()
            this = new()

            this.elapsedTime = 0.0

            return this
        end
    end

    function JulGame.initialize(this::RunTimer)
    end

    function JulGame.update(this::RunTimer, deltaTime)
        # Skip time tracking in title_scene (main menu) - we only want to track 
        # time during actual gameplay (map, battle, shop, event scenes)
        if MAIN.scene.name == "title_scene"
            return
        end
        
        # Update local elapsed time
        this.elapsedTime += deltaTime
        
        # Update the persistent state manager's run elapsed time
        try
            globals = JulGame.UserGlobals["Module"]
            persistentState = globals.get_data_manager().persistent_state_manager
            if persistentState.isRunActive
                persistentState.runElapsedTime += deltaTime
            end
        catch e
            @debug "Could not update persistent run time: $e"
        end
    end
    
    function JulGame.on_shutdown(this::RunTimer)
    end 
end
