module BobModule
    using JulGame

    mutable struct Bob
        parent
        elapsedTime
        speed::Float64
        startingY

        function Bob()
            this = new()

            this.elapsedTime = 0.0
            this.startingY = 0
            this.speed = 2.0

            return this
        end
    end

    function JulGame.initialize(this::Bob)
    end

    function JulGame.update(this::Bob, deltaTime)
        bob(this)
        this.elapsedTime += deltaTime
    end
    
    function JulGame.on_shutdown(this::Bob)
    end 

    function bob(this::Bob)
        # Define bobbing parameters
        bobHeight = -0.20  # The maximum height the item will bob
        scaleRange = 0.2
        minBobHeight = -0.10

        # Calculate a sine wave for bobbing motion
        bobOffset = minBobHeight + bobHeight * (1.0 - sin(this.speed * this.elapsedTime)) / 2.0
        scaleOffset = scaleRange * (1.0 - cos(this.speed * this.elapsedTime)) / 2.0

        # Update the item's Y-coordinate
        this.parent.sprite.offset = JulGame.Math.Vector2f(this.parent.sprite.offset.x, this.startingY + bobOffset)
    end
end
