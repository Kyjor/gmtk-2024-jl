module ObserverModule
    using JulGame

    mutable struct Observer
        parent
        observers::Vector{Function}

        function Observer()
            this = new()

            this.observers = []

            return this
        end
    end

    function add_observer(this::Observer, observer::Function)
        push!(this.observers, observer)
    end

    function add_observer(observer::Function)
        globals = JulGame.UserGlobals["Module"]
        this = globals.get_observer_data()
        add_observer(this, observer)
    end

    
    function remove_observer(this::Observer, observer::Function)
        filter!(ob -> ob != observer, this.observers)
    end
    function remove_observer(observer::Function)
        globals = JulGame.UserGlobals["Module"]
        this = globals.get_observer_data()
        remove_observer(this, observer)
    end
    
    function notify(this::Observer, event::Symbol, data::Any=nothing)
        for observer in this.observers
            observer(event, data)
        end
    end

    function notify(event::Symbol, data::Any=nothing)
        globals = JulGame.UserGlobals["Module"]
        this = globals.get_observer_data()
        notify(this, event, data)
    end
end