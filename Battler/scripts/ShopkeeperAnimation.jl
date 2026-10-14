module ShopkeeperAnimationModule
    using JulGame
    include("localization/shop_strings.jl")
    using .ShopStringsModule

    mutable struct ShopkeeperAnimation <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        
        # Shopkeeper entity reference
        shopkeeperEntity
        
        # Animation state
        currentEmotion::String
        animationTimer::Float64
        animationDuration::Float64
        
        # Emotion configurations
        emotions::Dict{String, Dict{String, Any}}

        # Color configurations
        availableColors::Vector{String}
        currentColor::String
        
        function ShopkeeperAnimation()
            this = new() # do not remove this line
            
            # Initialize animation state
            this.currentEmotion = "default"
            this.availableColors = ["blue", "orange", "purple", "gold"]
            this.currentColor = this.availableColors[1]
            this.animationTimer = 0.0
            this.animationDuration = 0.0
            
            # Define emotion configurations
            this.emotions = Dict(
                "default" => Dict(
                    "image" => JulGame.UserGlobals["Module"].get_asset_path("npc", "shopkeeper$(this.currentColor)default"),
                    "duration" => 0.0,  # Permanent until changed
                    "message" => ""
                ),
                "awkward" => Dict(
                    "image" => JulGame.UserGlobals["Module"].get_asset_path("npc", "shopkeeper$(this.currentColor)awkward"), 
                    "duration" => 2.0,  # 2 seconds
                    "message" => ShopStringsModule.SHOP_STRINGS[:shopkeeper_not_enough_gold]
                ),
                "grateful" => Dict(
                    "image" => JulGame.UserGlobals["Module"].get_asset_path("npc", "shopkeeper$(this.currentColor)grateful"),
                    "duration" => 3.0,  # 3 seconds
                    "message" => ShopStringsModule.SHOP_STRINGS[:shopkeeper_thank_you]
                ),
                "happy" => Dict(
                    "image" => JulGame.UserGlobals["Module"].get_asset_path("npc", "shopkeeper$(this.currentColor)happy"),
                    "duration" => 1.0,  # 4 seconds
                    "message" => ShopStringsModule.SHOP_STRINGS[:shopkeeper_bought_everything]
                )
            )
            
            return this # do not remove this line
        end
    end

    # This is called when a scene is loaded, or when script is added to an entity
    function JulGame.initialize(this::ShopkeeperAnimation)
        # Get reference to the shopkeeper entity
        this.shopkeeperEntity = JulGame.SceneModule.get_entity_by_id("eec17755-f894-4703-be61-d1f1ac52f261")
        
        if this.shopkeeperEntity === nothing
            @warn("Shopkeeper entity not found! Animation system will not work.")
        else
            @debug("Shopkeeper animation system initialized")
            # Set initial default emotion
            set_emotion(this, "default")
        end
    end

    # This is called every frame
    function JulGame.update(this::ShopkeeperAnimation, deltaTime)
        # Update animation timer
        if this.animationTimer > 0
            this.animationTimer -= deltaTime
            
            # If animation time is up, revert to default
            if this.animationTimer <= 0 && this.currentEmotion != "default" && this.currentEmotion != "happy"
                set_emotion(this, "default")
            end
        end
    end

    # This is called when the script is removed from an entity
    function JulGame.on_shutdown(this::ShopkeeperAnimation)
        # Clean up if needed
    end

    """
    Set the shopkeeper's emotion and start animation
    """
    function set_emotion(this::ShopkeeperAnimation, emotion::String)
        if !haskey(this.emotions, emotion)
            @warn("Unknown emotion: $(emotion)")
            return
        end
        
        if this.shopkeeperEntity === nothing
            @warn("Shopkeeper entity not available for animation")
            return
        end
        
        # Get emotion configuration
        emotion_config = this.emotions[emotion]
        
        # Update shopkeeper sprite
        this.shopkeeperEntity.sprite.imagePath = emotion_config["image"]
        
        # Set animation state
        this.currentEmotion = emotion
        this.animationDuration = emotion_config["duration"]
        this.animationTimer = emotion_config["duration"]
        
        @debug("Shopkeeper emotion set to: $(emotion) for $(emotion_config["duration"]) seconds")
        
        # Show message if emotion has one
        if emotion_config["message"] != ""
            show_emotion_message(this, emotion_config["message"])
        end
    end

    """
    Show a message for the current emotion
    """
    function show_emotion_message(this::ShopkeeperAnimation, message::String)
        # This could be enhanced to show a speech bubble or message
        @debug("Shopkeeper says: $(message)")
    end

    """
    Trigger awkward emotion (not enough money)
    """
    function trigger_awkward(this::ShopkeeperAnimation)
        set_emotion(this, "awkward")
    end

    """
    Trigger grateful emotion (purchase made)
    """
    function trigger_grateful(this::ShopkeeperAnimation)
        set_emotion(this, "grateful")
    end

    """
    Trigger happy emotion (bought everything)
    """
    function trigger_happy(this::ShopkeeperAnimation)
        set_emotion(this, "happy")
    end

    """
    Reset to default emotion
    """
    function reset_to_default(this::ShopkeeperAnimation)
        set_emotion(this, "default")
    end

    """
    Check if currently animating
    """
    function is_animating(this::ShopkeeperAnimation)
        return this.animationTimer > 0
    end

    """
    Get current emotion
    """
    function get_current_emotion(this::ShopkeeperAnimation)
        return this.currentEmotion
    end

    # Export functions that might be called from other scripts
    export set_emotion, trigger_awkward, trigger_grateful, trigger_happy, reset_to_default, is_animating, get_current_emotion
end
