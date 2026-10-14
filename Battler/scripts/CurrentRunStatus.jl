module CurrentRunStatusModule
    using JulGame
    using JulGame.EffectsModule
    using ..Scripts
    using ..MapFloorSystemModule
    using JulGame.FX.SDL2
    include("utils/Constants.jl")
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    include("localization/ui_strings.jl")
    using .UIStringsModule
    
    # Cache for original surfaces (similar to ImageFX)
    const ORIGINAL_UI_IMAGE_CACHE = Dict{String, Ptr{SDL2.LibSDL2.SDL_Surface}}()
    const C_NULL = Ptr{Nothing}(0)

    const PANEL_HOVER_COLOR = (100, 150, 110, 255)  # Lighter green when hovered
    const PORTRAIT_FRAME_PAD = 8
    const CONTINUE_TEXT_SHOWN_OFFSET_Y = -80.0
    const CONTINUE_TEXT_HIDDEN_PAD = 90

    function continue_text_hidden_offset_y(this)
        return Float64(this.panelHeight - CONTINUE_TEXT_HIDDEN_PAD)
    end

    function continue_text_at_rest(this)
        hidden = continue_text_hidden_offset_y(this)
        return !this.isHovered && abs(this.continueTextOffsetY - hidden) < 1.0
    end

    function current_run_map_node_sprite(persistentState)::String
        theme = floor_theme(persistentState.currentFloor)
        current_node = persistentState.currentLevel
        map_points = persistentState.mapPoints
        if current_node == 0 || map_points === nothing
            return JulGame.UserGlobals["Module"].get_asset_path(theme.startingTileSprite)
        end
        for (_, data) in map_points
            if data["index"] == current_node
                encounter = data["encounter"]
                category = lowercase(string(encounter.category))
                is_completed = current_node in persistentState.completedNodes
                return map_tile_sprite(theme, category; completed = is_completed)
            end
        end
        return JulGame.UserGlobals["Module"].get_asset_path(theme.startingTileSprite)
    end
    
    """
    Apply clock hand sweep effect to a UI image element
    """
    function gfx_clock_hand_sweep_ui(image::JulGame.UI.UIImageModule.UIImage, percentage::Float64; start_angle::Float64=0.0, clockwise::Bool=true, highlight_below::Float64=-1.0, bake_tint::NTuple{3, Int}=(255, 255, 255))
        percentage = clamp(percentage, 0.0, 1.0)
        highlight_below = highlight_below < 0.0 ? -1.0 : clamp(highlight_below, 0.0, 1.0)
        
        if image.surface == C_NULL
            @error "Cannot apply clock hand sweep: UI image has no surface"
            return image
        end
        
        # Create cache key from image path
        cache_key = image.path
        
        # Cache the original surface if not already cached
        if !haskey(ORIGINAL_UI_IMAGE_CACHE, cache_key)
            original_surface = SDL2.SDL_DuplicateSurface(image.surface)
            if original_surface == C_NULL
                @error "Failed to duplicate original surface for UI image caching"
                return image
            end
            ORIGINAL_UI_IMAGE_CACHE[cache_key] = original_surface
        end
        
        # Get the original surface from cache
        original_surface = ORIGINAL_UI_IMAGE_CACHE[cache_key]
        
        # Access the raw pixel data
        surface = unsafe_wrap(Array, original_surface, 10; own = false)[1]
        width = surface.w
        height = surface.h
        format = unsafe_wrap(Array, surface.format, 10; own = false)[1]
        bpp = format.BytesPerPixel
        
        # Create a new surface to work with
        new_surface = SDL2.SDL_CreateRGBSurfaceWithFormat(0, width, height, 32, format.format)
        
        if new_surface == C_NULL
            @error "Failed to create new surface for UI clock hand sweep"
            return image
        end
        
        # Copy original surface to new surface
        SDL2.SDL_BlitSurface(original_surface, C_NULL, new_surface, C_NULL)
        
        # Lock the surface to access the pixels
        SDL2.SDL_LockSurface(new_surface)
        
        # Get pixel data as bytes
        pixels_ptr = convert(Ptr{UInt8}, unsafe_load(new_surface).pixels)
        total_bytes = height * width * bpp
        
        # Create buffer arrays for processing
        src_buffer = Vector{UInt8}(undef, total_bytes)
        dest_buffer = Vector{UInt8}(undef, total_bytes)
        
        # Copy pixel data to our buffer
        unsafe_copyto!(pointer(src_buffer), pixels_ptr, total_bytes)
        
        # Center point for the sweep
        center_x = width / 2
        center_y = height / 2
        
        # Convert start angle to radians
        start_rad = deg2rad(start_angle - 90)
        
        # Calculate sweep angle based on percentage
        sweep_angle_deg = 360.0 * (1.0 - percentage)
        sweep_angle_rad = deg2rad(sweep_angle_deg)
        
        # Copy the buffer to destination first
        dest_buffer .= src_buffer
        
        # Early exit if nothing should be hidden
        if percentage >= 1.0 && highlight_below < 0.0
            unsafe_copyto!(pixels_ptr, pointer(dest_buffer), total_bytes)
            SDL2.SDL_UnlockSurface(new_surface)
            
            # Clean up existing texture
            if image.texture != C_NULL
                SDL2.SDL_DestroyTexture(image.texture)
                image.texture = C_NULL
            end
            
            # Clean up previous surface
            if image.surface != C_NULL && image.surface != original_surface
                SDL2.SDL_FreeSurface(image.surface)
            end
            
            # Update image with new surface
            image.surface = new_surface
            image.texture = SDL2.SDL_CreateTextureFromSurface(JulGame.Renderer, new_surface)
            SDL2.SDL_SetTextureBlendMode(image.texture, SDL2.SDL_BLENDMODE_BLEND)
            
            return image
        end
        
        start_angle_norm = start_rad < 0 ? start_rad + 2π : start_rad
        function hides(fill::Float64, pixel_angle::Float64)::Bool
            fill >= 1.0 && return false
            sweep = deg2rad(360.0 * (1.0 - fill))
            if clockwise
                end_angle = start_angle_norm + sweep
                if end_angle <= 2π
                    return pixel_angle >= start_angle_norm && pixel_angle <= end_angle
                end
                return pixel_angle >= start_angle_norm || pixel_angle <= end_angle - 2π
            end
            end_angle = start_angle_norm - sweep
            if end_angle >= 0
                return pixel_angle >= end_angle && pixel_angle <= start_angle_norm
            end
            return pixel_angle >= end_angle + 2π || pixel_angle <= start_angle_norm
        end

        # Process each pixel
        @inbounds for y in 0:(height-1)
            for x in 0:(width-1)
                dx = x - center_x
                dy = y - center_y
                pixel_angle = atan(dy, dx)
                pixel_angle = pixel_angle < 0 ? pixel_angle + 2π : pixel_angle

                pixel_index = (y * width + x) * bpp
                tinting = highlight_below >= 0.0
                outer_fill = tinting ? max(percentage, highlight_below) : percentage
                inner_fill = tinting ? min(percentage, highlight_below) : percentage
                if hides(outer_fill, pixel_angle)
                    for byte_offset in 0:(bpp-1)
                        dest_buffer[pixel_index + byte_offset + 1] = 0x00
                    end
                elseif tinting && inner_fill < outer_fill && hides(inner_fill, pixel_angle)
                    for byte_offset in 0:(bpp-2)
                        dest_buffer[pixel_index + byte_offset + 1] = 0xFF
                    end
                elseif tinting
                    channels = min(3, bpp - 1)
                    for byte_offset in 0:(channels-1)
                        src = dest_buffer[pixel_index + byte_offset + 1]
                        dest_buffer[pixel_index + byte_offset + 1] = UInt8(clamp(round(Int, src * bake_tint[byte_offset + 1] / 255), 0, 255))
                    end
                end
            end
        end
        
        # Copy processed buffer back to surface
        unsafe_copyto!(pixels_ptr, pointer(dest_buffer), total_bytes)
        SDL2.SDL_UnlockSurface(new_surface)
        
        # Clean up existing texture
        if image.texture != C_NULL
            SDL2.SDL_DestroyTexture(image.texture)
            image.texture = C_NULL
        end
        
        # Clean up previous surface
        if image.surface != C_NULL && image.surface != original_surface
            SDL2.SDL_FreeSurface(image.surface)
        end
        
        # Update image with new surface
        image.surface = new_surface
        image.texture = SDL2.SDL_CreateTextureFromSurface(JulGame.Renderer, new_surface)
        SDL2.SDL_SetTextureBlendMode(image.texture, SDL2.SDL_BLENDMODE_BLEND)
        
        return image
    end
    
    mutable struct CurrentRunStatus <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        
        # UI state
        isVisible::Bool
        isHovered::Bool
        isClickable::Bool
        transitionManager
        mainPanelElement::Any  # Reference to the main panel rect element
        lastHoverState::Bool
        wasMouseDown::Bool
        
        # Continue text animation
        continueTextOffsetY::Float64  # Current Y offset of continue text (relative to panel)
        targetTextOffsetY::Float64    # Target Y offset
        startTextOffsetY::Float64     # Starting Y offset for animation
        textAnimationTime::Float64    # Animation progress (0.0 to 1.0)
        textAnimationSpeed::Float64
        
        # Panel dimensions and positioning
        panelWidth::Int
        panelHeight::Int
        panelX::Int
        titlePanelX::Int
        panelY::Int
        
        # Panel Y position animation (for map scene hover effect)
        currentPanelY::Float64      # Current animated Y position
        targetPanelY::Float64       # Target Y position for animation
        startPanelY::Float64        # Starting Y position for animation
        panelYAnimationTime::Float64 # Animation progress (0.0 to 1.0)
        panelYAnimationSpeed::Float64
        panelRestingY::Int          # Resting Y position in map scene (925)
        mapSceneInitialized::Bool   # Track if map scene panel position was initialized
        
        # Character portrait
        characterPortraitSize::Int
        
        # Item grid settings
        itemSize::Int
        itemSpacing::Int
        itemsPerRow::Int
        piecesScrollOffset::Int
        treasuresScrollOffset::Int
        
        # Colors
        backgroundColor::Tuple{Int, Int, Int, Int}
        borderColor::Tuple{Int, Int, Int, Int}
        textColor::Tuple{Int, Int, Int, Int}
        accentColor::Tuple{Int, Int, Int, Int}
        
        # Font settings
        fontPath::String
        titleFontSize::Int
        bodyFontSize::Int
        smallFontSize::Int
        
        # Tooltip manager
        tooltipManager
        
        function CurrentRunStatus()
            this = new()
            
            # Initialize UI state
            this.isVisible = true
            this.isHovered = false
            this.isClickable = false  # Only clickable in main menu when run is active
            this.transitionManager = nothing
            this.mainPanelElement = nothing
            this.lastHoverState = false
            this.wasMouseDown = false

            # Panel layout settings
            this.panelWidth = 450
            this.panelHeight = 550
            this.panelX = (1920 - 500)
            this.titlePanelX = 50
            this.panelY = (1080 - 600)

            # Continue text sits fully inside the panel (behind it) until hover
            hidden_y = continue_text_hidden_offset_y(this)
            this.continueTextOffsetY = hidden_y
            this.targetTextOffsetY = hidden_y
            this.startTextOffsetY = hidden_y
            this.textAnimationTime = 0.0
            this.textAnimationSpeed = 0.8

            # Panel Y animation settings (for map scene)
            this.panelRestingY = 925
        this.currentPanelY = Float64(this.panelY)  # Start at normal position
        this.targetPanelY = Float64(this.panelY)
        this.startPanelY = Float64(this.panelY)
        this.panelYAnimationTime = 0.0
        this.panelYAnimationSpeed = 0.8  # Animation speed multiplier (slower for smoother animation)
        this.mapSceneInitialized = false
            
            # Character portrait
            this.characterPortraitSize = 100
            
            # Item grid settings
            this.itemSize = 80
            this.itemSpacing = 5
            this.itemsPerRow = 3
            this.piecesScrollOffset = 0
            this.treasuresScrollOffset = 0
            
            # Colors (dark green chalkboard theme)
            this.backgroundColor = (70, 110, 80, 255)  # Green panel tint
            this.borderColor = (200, 200, 200, 255)  # White border
            this.textColor = (255, 255, 255, 255)    # White text
            this.accentColor = (100, 200, 255, 255)  # Blue accent
            
            # Font settings
            this.fontPath = "Century-Normal.ttf"
            this.titleFontSize = 32
            this.bodyFontSize = 26
            this.smallFontSize = 24
            
            # Tooltip manager (initialized in initialize function)
            this.tooltipManager = nothing
            
            return this
        end
    end
    
    # This is called when a scene is loaded, or when script is added to an entity
    function JulGame.initialize(this::CurrentRunStatus)
        # Initialize any required resources
        show(this)

        if JulGame.MAIN.scene.name == "title_scene"
            globals = JulGame.UserGlobals["Module"]
            persistentState = globals.get_data_manager().persistent_state_manager
            if !persistentState.isRunActive && globals.SaveManagerModule.has_disk_save()
                try
                    if !globals.SaveManagerModule.try_load_run!()
                        @warn "Could not restore saved run for title screen"
                    end
                catch e
                    @error "Failed to restore saved run for title screen" exception=(e, catch_backtrace())
                end
            end
        end
        
        # Create and initialize the tooltip manager if not provided
        if !isdefined(this, :tooltipManager) || this.tooltipManager === nothing
            tooltipEntity = JulGame.EntityModule.Entity("CurrentRunStatusTooltipManager")
            tooltipEntity = JulGame.create_entity(tooltipEntity)
            push!(tooltipEntity.scripts, Scripts.TooltipManagerModule.TooltipManager())
            this.tooltipManager = tooltipEntity.scripts[1]
            
            # Set custom tooltip style
            Scripts.TooltipManagerModule.set_tooltip_style(
                this.tooltipManager,
                hoverDelay = UInt64(120)
            )
        end
    end
    
    # This is called every frame
    function JulGame.update(this::CurrentRunStatus, deltaTime)
        # Check current scene
        current_scene_name = JulGame.MAIN.scene.name
        
        # Only show in title_scene and map scene
        if current_scene_name == "title_scene" || current_scene_name == "map"
            # In title scene, only display if a run is active
            if current_scene_name == "title_scene"
                globals = JulGame.UserGlobals["Module"]
                persistentState = globals.get_data_manager().persistent_state_manager
                has_save = persistentState.isRunActive || globals.SaveManagerModule.has_disk_save()
                if !has_save
                    if this.isVisible
                        this.isVisible = false
                    end
                    return
                end
            end
            if !this.isVisible
                this.isVisible = true
            end
            
            # Title scene behavior (unchanged)
            if current_scene_name == "title_scene"
                this.isClickable = true
                this.mapSceneInitialized = false  # Reset so map scene re-initializes
                
                # Get transition manager if we don't have it
                if this.transitionManager === nothing
                    try
                        this.transitionManager = JulGame.SceneModule.get_entity_by_id("44077ce5-c10f-4c9f-a9e2-e968d24ec1cc").scripts[3]
                    catch e
                        @debug "Could not get transition manager: $e"
                    end
                end
                
                # Check for hover and click (title scene only)
                if !Scripts.SettingsDisplayManagerModule.is_settings_open()
                    check_hover_and_click(this, deltaTime)
                else
                    this.isHovered = false
                    this.lastHoverState = false
                    this.wasMouseDown = true
                    this.targetTextOffsetY = continue_text_hidden_offset_y(this)
                    this.continueTextOffsetY = this.targetTextOffsetY
                end
                
                # Reset panel Y to normal position in title scene
                this.currentPanelY = Float64(this.panelY)
                this.targetPanelY = Float64(this.panelY)
                
            # Map scene behavior (new hover animation)
            elseif current_scene_name == "map"
                this.isClickable = false
                
                # Initialize panel Y to resting position ONCE when entering map scene
                if !this.mapSceneInitialized
                    this.currentPanelY = Float64(this.panelRestingY)
                    this.targetPanelY = Float64(this.panelRestingY)
                    this.startPanelY = Float64(this.panelRestingY)
                    this.mapSceneInitialized = true
                end
                
                # Check for hover (for animation, not click)
                check_map_hover(this, deltaTime)
                
                # Update panel Y animation
                update_panel_y_animation(this, deltaTime)
            end
            
            draw_current_run_status(this, Float64(deltaTime))
            
            # Update tooltip manager to check for hovers
            if this.tooltipManager !== nothing && !Scripts.SettingsDisplayManagerModule.is_settings_open()
                Scripts.TooltipManagerModule.check_tooltip_hovers(this.tooltipManager)
            end
        else
            # Hide in other scenes
            if this.isVisible
                this.isVisible = false
            end
        end
    end
    
    # This is called when the script is removed from an entity
    function JulGame.on_shutdown(this::CurrentRunStatus)
        # Clean up any resources if needed
    end
    
    """
    Toggle the status panel visibility
    """
    function toggle_visibility(this::CurrentRunStatus)
        this.isVisible = !this.isVisible
    end
    
    """
    Show the status panel
    """
    function show(this::CurrentRunStatus)
        this.isVisible = true
    end
    
    """
    Hide the status panel
    """
    function hide(this::CurrentRunStatus)
        this.isVisible = false
    end
    
    """
    Draw the complete current run status UI
    """
    function draw_current_run_status(this::CurrentRunStatus, deltaTime::Float64 = 0.0)
        # Get user data
        globals = JulGame.UserGlobals["Module"]
        user = globals.get_user_data()
        persistentState = globals.get_data_manager().persistent_state_manager
        
        # Draw main panel background
        main_panel = draw_main_panel(this)
        
        # Draw top section - portrait and info
        draw_character_portrait(this, user, main_panel)
        draw_run_info_section(this, persistentState, main_panel)
        
        # Draw stats bar (health, gold, potions) - above the horizontal divider
        draw_stats_bar(this, user, main_panel, deltaTime)
        
        # Draw bottom section - inventory
        draw_inventory_section(this, user, main_panel)
    end
    
    """
    Check for hover in map scene (for panel Y animation only)
    """
    function check_map_hover(this::CurrentRunStatus, deltaTime::Float64)
        mouse_pos = JulGame.InputModule.get_mouse_position()
        mouse_x = mouse_pos.x
        mouse_y = mouse_pos.y
        
        was_hovered = this.lastHoverState
        
        # Add buffer zone to catch hover while panel is moving
        hover_buffer_top = 80
        hover_buffer_bottom = 80
        hover_buffer_left = 20
        
        # Use CURRENT panel position (animated) for hover detection
        current_y = Int(round(this.currentPanelY))
        hover_min_x = this.panelX - hover_buffer_left
        # No right buffer limit - panel is at screen edge, allow any X >= panelX
        hover_max_x = 9999
        # Use current panel Y position for bounds
        hover_min_y = current_y - hover_buffer_top
        hover_max_y = current_y + this.panelHeight + hover_buffer_bottom
        
        this.isHovered = (mouse_x >= hover_min_x && mouse_x <= hover_max_x &&
                         mouse_y >= hover_min_y && mouse_y <= hover_max_y)
        
        @debug "[check_map_hover] mouse=($mouse_x, $mouse_y), bounds=($hover_min_x-$hover_max_x, $hover_min_y-$hover_max_y), isHovered=$(this.isHovered), currentPanelY=$(this.currentPanelY)"
        
        # Continuously update target based on current hover state
        expected_target = this.isHovered ? Float64(this.panelY) : Float64(this.panelRestingY)
        
        # Only update animation if target changed
        if abs(this.targetPanelY - expected_target) > 0.1
            @debug "[check_map_hover] Target changed! expected_target=$expected_target, was $(this.targetPanelY)"
            this.startPanelY = this.currentPanelY
            this.targetPanelY = expected_target
            this.panelYAnimationTime = 0.0
        end
        
        this.lastHoverState = this.isHovered
    end
    
    """
    Update panel Y position animation with easing
    """
    function update_panel_y_animation(this::CurrentRunStatus, deltaTime::Float64)
        # Check if we need to animate
        if abs(this.currentPanelY - this.targetPanelY) < 0.1
            if this.panelYAnimationTime > 0.0
                @debug "[update_panel_y_animation] Animation complete at currentPanelY=$(this.currentPanelY)"
            end
            this.currentPanelY = this.targetPanelY
            this.panelYAnimationTime = 0.0
            return
        end
        
        # Update animation time
        this.panelYAnimationTime += deltaTime * this.panelYAnimationSpeed
        
        # Clamp animation time
        if this.panelYAnimationTime > 1.0
            this.panelYAnimationTime = 1.0
            this.currentPanelY = this.targetPanelY
            @debug "[update_panel_y_animation] Animation clamped to complete"
            return
        end
        
        # Calculate eased progress (using smooth cubic ease out)
        eased_t = ease_out_cubic_smooth(this.panelYAnimationTime)
        
        # Interpolate Y position from start to target
        this.currentPanelY = this.startPanelY + (this.targetPanelY - this.startPanelY) * eased_t
    end
    
    """
    Check for hover and click on the panel (title scene only)
    """
    function check_hover_and_click(this::CurrentRunStatus, deltaTime::Float64)
        mouse_pos = JulGame.InputModule.get_mouse_position()
        mouse_x = mouse_pos.x
        mouse_y = mouse_pos.y
        
        # Check if mouse is over panel (continuously check, not just on state change)
        was_hovered = this.lastHoverState
        this.isHovered = (mouse_x >= this.titlePanelX && mouse_x <= this.titlePanelX + this.panelWidth &&
                         mouse_y >= this.panelY && mouse_y <= this.panelY + this.panelHeight)
        
        # Continuously update target based on current hover state
        # This ensures the animation target stays correct even after animation completes
        expected_target = this.isHovered ? CONTINUE_TEXT_SHOWN_OFFSET_Y : continue_text_hidden_offset_y(this)
        
        # Only update animation if target changed or if we're not at the expected target
        if abs(this.targetTextOffsetY - expected_target) > 0.1
            # Target changed - restart animation from current position
            this.startTextOffsetY = this.continueTextOffsetY
            this.targetTextOffsetY = expected_target
            this.textAnimationTime = 0.0
            
            # Trigger shake only on state transition (hover -> unhover or vice versa)
            if this.isHovered && !was_hovered
                trigger_hover_shake(this)
            end
        end
        
        # Update text animation
        update_text_animation(this, deltaTime)
        
        # Update last hover state
        this.lastHoverState = this.isHovered
        
        # Check for click (detect button press, not held)
        isMouseDown = JulGame.InputModule.get_mouse_button_pressed(1)  # Left mouse button
        if this.isHovered && isMouseDown && !this.wasMouseDown
            # Mouse button just pressed
            trigger_click_shake(this)
            continue_run(this)
        end
        this.wasMouseDown = isMouseDown
    end
    
    """
    Update continue text animation with smooth cubic easing
    """
    function update_text_animation(this::CurrentRunStatus, deltaTime::Float64)
        # Check if we need to animate
        if abs(this.continueTextOffsetY - this.targetTextOffsetY) < 0.1
            this.continueTextOffsetY = this.targetTextOffsetY
            this.textAnimationTime = 0.0
            return
        end
        
        # Update animation time
        this.textAnimationTime += deltaTime * this.textAnimationSpeed
        
        # Clamp animation time
        if this.textAnimationTime > 1.0
            this.textAnimationTime = 1.0
            this.continueTextOffsetY = this.targetTextOffsetY
            return
        end
        
        # Calculate eased progress (using smooth cubic ease out like panel animation)
        eased_t = ease_out_cubic_smooth(this.textAnimationTime)
        
        # Interpolate offset from start to target
        this.continueTextOffsetY = this.startTextOffsetY + (this.targetTextOffsetY - this.startTextOffsetY) * eased_t
    end
    
    """
    Smooth cubic ease out function (for panel Y animation)
    """
    function ease_out_cubic_smooth(t::Float64)::Float64
        t = clamp(t, 0.0, 1.0)
        return 1.0 - (1.0 - t)^3
    end
    
    """
    Bounce easing function (easeOutBounce) - used for text animation
    """
    function bounce_ease_out(t::Float64)::Float64
        t = clamp(t, 0.0, 1.0)
        if t < 1.0 / 2.75
            return 7.5625 * t * t
        elseif t < 2.0 / 2.75
            t -= 1.5 / 2.75
            return 7.5625 * t * t + 0.75
        elseif t < 2.5 / 2.75
            t -= 2.25 / 2.75
            return 7.5625 * t * t + 0.9375
        else
            t -= 2.625 / 2.75
            return 7.5625 * t * t + 0.984375
        end
    end
    
    """
    Trigger shake effect on hover
    """
    function trigger_hover_shake(this::CurrentRunStatus)
        if this.mainPanelElement !== nothing
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "tick1"), false, 1.0, 0, 1)
            
            # Apply shake effect
            Scripts.ShakeEffectControllerModule.shake_effect(this.mainPanelElement;
                intensity=3.5f0,
                duration=0.4f0,
                frequency=6.0f0,
                rotation_intensity=0.5f0,
                position_intensity=1.0f0,
                use_sine_wave=true
            )
        end
    end
    
    """
    Trigger shake effect on click
    """
    function trigger_click_shake(this::CurrentRunStatus)
        if this.mainPanelElement !== nothing
            globals = JulGame.UserGlobals["Module"]
            globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "tick1"), false, 1.0, 0, 1)
            
            # Apply stronger shake on click
            Scripts.ShakeEffectControllerModule.shake_effect(this.mainPanelElement;
                intensity=5.0f0,
                duration=0.3f0,
                frequency=8.0f0,
                rotation_intensity=0.8f0,
                position_intensity=1.5f0,
                use_sine_wave=true
            )
        end
    end
    
    """
    Scene to resume into. Unfinished encounters skip the map.
    """
    function continue_run_target_scene(persistentState)::String
        if persistentState.isFloorComplete || persistentState.currentLevel == 0
            return "map.json"
        end
        ev = persistentState.currentEvent
        (ev === nothing || !hasproperty(ev, :type)) && return "map.json"
        ev_type = string(ev.type)
        ev_type == "" && return "map.json"
        category = hasproperty(ev, :category) ? lowercase(string(ev.category)) : ""
        if ev_type == "Battle"
            return "battle.json"
        elseif ev_type == "Event"
            if category == "shop"
                return resolve_shop_scene(persistentState.seed, persistentState.currentLevel)
            elseif category == "rest"
                return "rest.json"
            else
                return "event.json"
            end
        elseif ev_type == "Treasure"
            return "event.json"
        end
        return "map.json"
    end

    """
    Status line key: traversing on the map, otherwise the activity the saved run resumes into.
    """
    function current_run_status_key(persistentState)::Symbol
        JulGame.MAIN.scene.name == "map" && return :current_run_status_traversing
        scene = continue_run_target_scene(persistentState)
        scene == "battle.json" && return :current_run_status_battling
        scene == "rest.json" && return :current_run_status_resting
        scene == "event.json" && return :current_run_status_random_event
        endswith(scene, "shop.json") && return :current_run_status_shopping
        return :current_run_status_traversing
    end

    """
    Continue the current run
    """
    function continue_run(this::CurrentRunStatus)
        if this.transitionManager !== nothing
            # Play continue run sound effect
            globals = JulGame.UserGlobals["Module"]
            persistentState = globals.get_data_manager().persistent_state_manager
            if !persistentState.isRunActive
                local loaded = false
                try
                    loaded = globals.SaveManagerModule.try_load_run!()
                catch e
                    @error "Cannot continue run: save restore failed" exception=(e, catch_backtrace())
                    return
                end
                if !loaded
                    @error "Cannot continue run: no valid save found"
                    return
                end
            end
            globals.AudioManagerModule.play_audio_oneshot(globals.get_audio_manager(), globals.get_asset_path("sfx", "continuerun"), false, 1.0, 0, 1)

            target_scene = continue_run_target_scene(persistentState)
            @debug "Continuing run - transitioning to $target_scene"
            Scripts.SceneTransitionModule.transition_to_scene(this.transitionManager, target_scene)
        else
            @error "Cannot continue run: transition manager not available"
        end
    end
    
    """
    Draw the main panel background
    """
    function draw_main_panel(this::CurrentRunStatus)
        # Use animated Y position for map scene, normal position for title scene
        current_scene_name = JulGame.MAIN.scene.name
        panel_y_pos = current_scene_name == "map" ? Int(round(this.currentPanelY)) : this.panelY
        panel_x_pos = current_scene_name == "title_scene" ? this.titlePanelX : this.panelX
        
        hovered = this.isHovered && this.isClickable

        # Main panel background (draw first so text can be parented to it)
        panel = Scripts.NineSliceUIModule.immediate_panel(
            "current_run_panel";
            position = Math.Vector2(panel_x_pos, panel_y_pos),
            size = Math.Vector2(this.panelWidth, this.panelHeight),
            color = hovered ? PANEL_HOVER_COLOR : this.backgroundColor,
            border_color = (255, 255, 255, 255),
            spec = hovered ? Scripts.NineSliceUIModule.PANEL_GRADIENT : Scripts.NineSliceUIModule.DEFAULT_PANEL,
            layer = 100
        )
        
        # Store panel element reference for shake
        this.mainPanelElement = panel
        
        # Draw "Continue run?" text parented to panel (layer 99 so it's behind)
        if this.isClickable
            DisplayTextModule.display_text(
                "continue_run_text",
                UIStringsModule.UI_STRINGS[:current_run_continue];
                fontSize = 28,
                color = this.textColor,
                parent = panel,
                anchor = :centerTop,
                anchorOffset = Math.Vector2(0, Int(round(this.continueTextOffsetY))),
                layer = 99,
                isActive = !continue_text_at_rest(this)
            )
        end
        
        return panel
    end
    
    """
    Draw the run information section (to the right of portrait)
    """
    function draw_run_info_section(this::CurrentRunStatus, persistentState, main_panel)
        # Calculate the info area (right of portrait)
        portraitEndX = 20 + this.characterPortraitSize + 15  # 135
        infoAreaWidth = this.panelWidth - portraitEndX - 20  # remaining width minus right padding
        infoAreaCenterX = portraitEndX + (infoAreaWidth ÷ 2)  # relative center X of info area
        
        # Title "Current Run:" + current map-node icon (title scene only)
        current_scene_name = JulGame.MAIN.scene.name
        if current_scene_name == "title_scene"
            title_x = 20
            icon_size = 120  # 48 * 2.5
            icon_y = -icon_size + 40
            title_y = icon_y + 40
            title = DisplayTextModule.display_text(
                "current_run_title",
                UIStringsModule.UI_STRINGS[:current_run_title];
                fontPath = BATTLE_NUMBER_FONT,
                fontSize = 28,
                color = this.textColor,
                parent = main_panel,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(title_x, title_y),
                layer = 102
            )
            apply_battle_number_text_effects!(title)
            text_w = title === nothing ? 160 : Int(title.size.x)
            JulGame.ImmediateUIModule.immediate_image(
                "current_run_node_icon",
                current_run_map_node_sprite(persistentState);
                size = Math.Vector2(icon_size, icon_size),
                parent = main_panel,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(title_x + text_w + 8, icon_y),
                layer = 102
            )
        end
        
        # Line 1: Game time - centered in the info area
        time_string = format_elapsed_time(persistentState.runElapsedTime)
        DisplayTextModule.display_text(
            "game_time",
            UIStringsModule.format_string(:current_run_game_time, time=time_string);
            fontSize = this.smallFontSize,
            color = this.textColor,
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(185, 25),
            layer = 102
        )
        
        # Line 2: Floor and Room - evenly spaced on same line (both green)
        floorRoomY = 50
        quarterWidth = infoAreaWidth ÷ 4
        
        DisplayTextModule.display_text(
            "floor_info",
            UIStringsModule.format_string(:current_run_floor, floor=persistentState.currentFloor);
            fontSize = this.bodyFontSize,
            color = (100, 255, 100, 255),  # Green
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portraitEndX + quarterWidth - 20, floorRoomY),
            layer = 102
        )
        
        DisplayTextModule.display_text(
            "room_info",
            UIStringsModule.format_string(:current_run_room, room=persistentState.currentRoom);
            fontSize = this.bodyFontSize,
            color = (100, 255, 100, 255),  # Green (same as floor)
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portraitEndX + quarterWidth * 3 - 40, floorRoomY),
            layer = 102
        )
        
        # Line 3: Status text - positioned in info area
        DisplayTextModule.display_text(
            "current_action",
            UIStringsModule.UI_STRINGS[current_run_status_key(persistentState)];
            fontSize = this.smallFontSize,
            color = (200, 200, 200, 255),  # Grey
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portraitEndX + 25, 75),
            layer = 102
        )
    end
    
    """
    Draw the character portrait (top left)
    """
    function draw_character_portrait(this::CurrentRunStatus, user, main_panel)
        portraitX = 20
        portraitY = 20
        
        pad = PORTRAIT_FRAME_PAD
        Scripts.NineSliceUIModule.immediate_panel(
            "character_portrait_frame";
            size = Math.Vector2(this.characterPortraitSize + 2 * pad, this.characterPortraitSize + 2 * pad),
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portraitX - pad, portraitY - pad),
            color = this.borderColor,
            layer = 102
        )

        # Character portrait background
        JulGame.ImmediateUIModule.immediate_rect(
            "character_portrait_bg";
            size = Math.Vector2(this.characterPortraitSize, this.characterPortraitSize),
            color = (60, 60, 60, 255),
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portraitX, portraitY),
            layer = 104
        )
        
        # Determine portrait image based on selected character
        portraitPath = JulGame.UserGlobals["Module"].get_asset_path("character", "magicianportrait")  # default
        if user.selectedCharacter == "CHARACTER_MAGICIAN"
            portraitPath = JulGame.UserGlobals["Module"].get_asset_path("character", "magicianportrait")
        elseif user.selectedCharacter == "CHARACTER_DEMOLITIONIST"
            portraitPath = JulGame.UserGlobals["Module"].get_asset_path("character", "demolitionistportrait")
        elseif user.selectedCharacter == "CHARACTER_KNIGHT"
            portraitPath = JulGame.UserGlobals["Module"].get_asset_path("character", "knightportrait")
        end
        
        # Character portrait image
        JulGame.ImmediateUIModule.immediate_button(
            "character_portrait",
            () -> @debug("Character portrait clicked");
            size = Math.Vector2(this.characterPortraitSize, this.characterPortraitSize),
            buttonUpPath = portraitPath,
            buttonDownPath = portraitPath,
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(portraitX, portraitY),
            layer = 105
        )
    end
    
    """
    Draw the stats bar (health, gold, potions) - positioned above horizontal divider
    """
    function draw_stats_bar(this::CurrentRunStatus, user, main_panel, deltaTime::Float64 = 0.0)
        # Stats bar Y position (just above the horizontal divider at y=160)
        statsBarY = 125
        thirdWidth = (this.panelWidth - 40) ÷ 3  # Divide available width into thirds
        iconSize = 24
        
        # Left third: Health with clock hand sweep effect
        healthX = 20
        heartSize = 24
        
        # Create heart UI image
        heart_image = JulGame.ImmediateUIModule.immediate_image(
            "health_heart",
            JulGame.UserGlobals["Module"].get_asset_path("ui", "healthheart");
            size = Math.Vector2(heartSize, heartSize),
            color = (255, 70, 127, 255),  # Color from battle.json
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(healthX, statsBarY),
            layer = 104
        )
        
        # Apply clock hand sweep effect to UI image
        max_hp = max(Int(user.maxHealth), 1)
        shown, highlight = Scripts.HeartFillFXModule.present!(
            "run_status",
            Float64(user.health) / Float64(max_hp),
            deltaTime,
        )
        heart_image.color = highlight >= 0 ? Scripts.HeartFillFXModule.FLASH_COLOR : Scripts.HeartFillFXModule.IDLE_COLOR
        gfx_clock_hand_sweep_ui(
            heart_image,
            shown;
            highlight_below=highlight,
            bake_tint=Scripts.HeartFillFXModule.BAKE_TINT,
        )
        
        # Show health text next to heart
        DisplayTextModule.display_text(
            "health_value",
            "$(user.health)/$(user.maxHealth)";
            fontSize = this.bodyFontSize,
            color = this.textColor,
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(healthX + heartSize + 5, statsBarY - 10),
            layer = 102
        )
        
        # Middle third: Gold
        goldX = 20 + thirdWidth
        JulGame.ImmediateUIModule.immediate_button(
            "gold_icon",
            () -> @debug("Gold clicked");
            size = Math.Vector2(iconSize, iconSize),
            buttonUpPath = JulGame.UserGlobals["Module"].get_asset_path("ui", "money"),
            buttonDownPath = JulGame.UserGlobals["Module"].get_asset_path("ui", "money"),
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(goldX, statsBarY),
            layer = 104
        )
        
        DisplayTextModule.display_text(
            "gold_value",
            "$(user.gold)";
            fontSize = this.bodyFontSize,
            color = this.textColor,
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(goldX + iconSize + 5, statsBarY - 10),
            layer = 102
        )
        
        # Right third: Potions (up to 3)
        potionsX = 20 + thirdWidth * 2
        potionIconSize = 36
        potionSpacing = 42
        
        potions = user.potions
        for (i, potion) in enumerate(potions)
            if i > 3  # Max 3 potions shown
                break
            end
            
            iconPath = get_potion_icon_path(potion.key)
            potion_button = JulGame.ImmediateUIModule.immediate_button(
                "potion_icon_$(i)",
                () -> @debug("Potion $(potion.key) clicked");
                size = Math.Vector2(potionIconSize, potionIconSize),
                buttonUpPath = iconPath,
                buttonDownPath = iconPath,
                parent = main_panel,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(potionsX + (i-1) * potionSpacing, statsBarY - 6),
                layer = 104
            )
            
            # Register tooltip for this potion
            if this.tooltipManager !== nothing
                tooltip_text = get_potion_tooltip_text(potion)
                Scripts.TooltipManagerModule.register_tooltip_item(
                    this.tooltipManager,
                    potion_button,
                    tooltip_text
                )
            end
        end
    end
    
    """
    Get icon path for pieces
    """
    function get_icon_path(key::String)
        globals = JulGame.UserGlobals["Module"]
        name = lowercase(split(key, "_")[2])
        return globals.get_asset_path("piece", name)
    end

    """
    Get icon path for potions
    """
    function get_potion_icon_path(key::String)
        globals = JulGame.UserGlobals["Module"]
        name = lowercase(split(key, "_")[2])
        return globals.get_asset_path("potion", name)
    end 

    """
    Get icon path for treasures
    """
    function get_treasure_icon_path(key::String)
        globals = JulGame.UserGlobals["Module"]
        name = lowercase(split(key, "_")[2])
        return globals.get_asset_path("treasure", name)
    end

    
    const INVENTORY_GRID_TOP = 195
    const INVENTORY_VIEWPORT_HEIGHT = 335
    const SCROLL_BTN_SIZE = 40
    const SCROLL_ARROW_W = 28
    const SCROLL_ARROW_H = 19
    const SCROLL_ARROW_NUDGE_X = 5

    function current_panel_screen_x(this::CurrentRunStatus)
        return JulGame.MAIN.scene.name == "title_scene" ? this.titlePanelX : this.panelX
    end

    function current_panel_screen_y(this::CurrentRunStatus)
        return JulGame.MAIN.scene.name == "map" ? Int(round(this.currentPanelY)) : this.panelY
    end

    function inventory_cell_stride(this::CurrentRunStatus)
        return this.itemSize - 18
    end

    function inventory_visible_rows(this::CurrentRunStatus)
        return max(1, INVENTORY_VIEWPORT_HEIGHT ÷ inventory_cell_stride(this))
    end

    function inventory_max_scroll(this::CurrentRunStatus, itemCount::Int, itemsPerRow::Int)
        totalRows = cld(max(itemCount, 0), max(itemsPerRow, 1))
        return max(0, totalRows - inventory_visible_rows(this))
    end

    function point_in_rect(x, y, rx, ry, rw, rh)
        return x >= rx && x <= rx + rw && y >= ry && y <= ry + rh
    end

    function is_over_inventory_area(this::CurrentRunStatus, mouseX, mouseY)
        panelX = current_panel_screen_x(this)
        panelY = current_panel_screen_y(this)
        return mouseX >= panelX && mouseX <= panelX + this.panelWidth &&
               mouseY >= panelY + 160 && mouseY <= panelY + this.panelHeight
    end

    function inventory_list_metrics(this::CurrentRunStatus, kind::Symbol, itemCount::Int)
        stride = inventory_cell_stride(this)
        itemsPerRow = kind == :treasures ? 3 : this.itemsPerRow
        maxScroll = inventory_max_scroll(this, itemCount, itemsPerRow)
        scrollOffset = clamp(kind == :pieces ? this.piecesScrollOffset : this.treasuresScrollOffset, 0, maxScroll)
        itemOriginX = kind == :pieces ? -5 : this.panelWidth ÷ 2
        viewportX = kind == :pieces ? 0 : this.panelWidth ÷ 2 + 4
        viewportW = this.panelWidth ÷ 2 - 8
        buttonX = kind == :pieces ? this.panelWidth ÷ 2 - SCROLL_BTN_SIZE - 4 : this.panelWidth - SCROLL_BTN_SIZE - 6
        return (
            kind = kind,
            stride = stride,
            itemsPerRow = itemsPerRow,
            maxScroll = maxScroll,
            scrollOffset = scrollOffset,
            itemOriginX = itemOriginX,
            viewportX = viewportX,
            viewportW = viewportW,
            buttonX = buttonX,
        )
    end

    function set_list_scroll(this::CurrentRunStatus, kind::Symbol, value, maxScroll::Int)
        next = clamp(Int(round(value)), 0, maxScroll)
        if kind == :pieces
            this.piecesScrollOffset = next
        else
            this.treasuresScrollOffset = next
        end
    end

    function handle_inventory_scroll_input(this::CurrentRunStatus, user)
        mouse = JulGame.InputModule.get_mouse_position()
        mouseX = mouse.x
        mouseY = mouse.y
        panelY = current_panel_screen_y(this)
        panelX = current_panel_screen_x(this)
        piecesCount = user.pieces === nothing ? 0 : length(user.pieces)
        treasuresCount = user.treasures === nothing ? 0 : length(user.treasures)
        lists = (
            inventory_list_metrics(this, :pieces, piecesCount),
            inventory_list_metrics(this, :treasures, treasuresCount),
        )

        rowDelta = 0
        if JulGame.InputModule.get_button_pressed("Up")
            rowDelta = -1
        elseif JulGame.InputModule.get_button_pressed("Down")
            rowDelta = 1
        end
        if rowDelta != 0
            for metrics in lists
                metrics.maxScroll <= 0 && continue
                overViewport = point_in_rect(
                    mouseX, mouseY,
                    panelX + metrics.viewportX, panelY + INVENTORY_GRID_TOP,
                    metrics.viewportW, INVENTORY_VIEWPORT_HEIGHT,
                )
                if overViewport
                    set_list_scroll(this, metrics.kind, metrics.scrollOffset + rowDelta, metrics.maxScroll)
                    break
                end
            end
        end

        this.piecesScrollOffset = clamp(this.piecesScrollOffset, 0, inventory_max_scroll(this, piecesCount, this.itemsPerRow))
        this.treasuresScrollOffset = clamp(this.treasuresScrollOffset, 0, inventory_max_scroll(this, treasuresCount, 3))
    end

    function draw_scroll_button(this::CurrentRunStatus, main_panel, id::String, arrow::String, x::Int, y::Int, onClick, enabled::Bool)
        button = JulGame.ImmediateUIModule.immediate_rect(
            id;
            size = Math.Vector2(SCROLL_BTN_SIZE, SCROLL_BTN_SIZE),
            color = (0, 0, 0, 0),
            layer = 106,  # above the arrow so the invisible hit rect receives the click
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(x + SCROLL_ARROW_NUDGE_X, y),
            clickEvent = enabled ? onClick : () -> nothing,
            forceClickCheck = true,
        )
        JulGame.ImmediateUIModule.immediate_image(
            "$(id)_arrow",
            JulGame.UserGlobals["Module"].get_asset_path("ui", arrow);
            size = Math.Vector2(SCROLL_ARROW_W, SCROLL_ARROW_H),
            color = enabled ? (255, 255, 255, 255) : (160, 160, 160, 180),
            parent = button,
            anchor = :center,
            layer = 105,
        )
    end

    function draw_list_scroll_buttons(this::CurrentRunStatus, main_panel, metrics)
        metrics.maxScroll <= 0 && return
        upY = INVENTORY_GRID_TOP
        downY = INVENTORY_GRID_TOP + INVENTORY_VIEWPORT_HEIGHT - SCROLL_BTN_SIZE
        draw_scroll_button(
            this, main_panel, "$(metrics.kind)_scroll_up", "arrowup", metrics.buttonX, upY,
            () -> set_list_scroll(this, metrics.kind, metrics.scrollOffset - 1, metrics.maxScroll),
            metrics.scrollOffset > 0,
        )
        draw_scroll_button(
            this, main_panel, "$(metrics.kind)_scroll_down", "arrowdown", metrics.buttonX, downY,
            () -> set_list_scroll(this, metrics.kind, metrics.scrollOffset + 1, metrics.maxScroll),
            metrics.scrollOffset < metrics.maxScroll,
        )
    end

    """
    Center column rule. Alpha runs from clear at the top to the border color at the bottom.
    """
    function draw_faded_vertical_divider(main_panel, color, y::Int, height::Int)
        steps = 16
        seg = height / steps
        for i in 0:(steps - 1)
            t = (i + 0.5) / steps
            alpha = round(Int, color[4] * t)
            JulGame.ImmediateUIModule.immediate_rect(
                "inventory_divider_$(i)";
                size = Math.Vector2(2, ceil(Int, seg) + 1),
                color = (color[1], color[2], color[3], alpha),
                layer = 102,
                parent = main_panel,
                anchor = :centerTop,
                anchorOffset = Math.Vector2(0, y + round(Int, i * seg)),
            )
        end
    end

    """
    Draw the inventory section (bottom)
    """
    function draw_inventory_section(this::CurrentRunStatus, user, main_panel)
        handle_inventory_scroll_input(this, user)

        # Horizontal divider line
        dividerX = this.panelX + this.panelWidth ÷ 2
        dividerY = this.panelY + 100
        JulGame.ImmediateUIModule.immediate_rect(
            "inventory_divider_horizontal";
            size = Math.Vector2(this.panelWidth - 40, 2),
            color = this.borderColor,
            layer = 102,
            parent = main_panel,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 160),
        )

        # Vertical divider fades in from the top of the columns to the bottom.
        draw_faded_vertical_divider(main_panel, this.borderColor, 200, 320)
        
        # Draw pieces section (left)
        draw_pieces_section(this, user, main_panel)
        
        # Draw items section (right)
        draw_treasures_section(this, user, main_panel)
    end
    
    """
    Draw the pieces section (left side)
    """
    function draw_pieces_section(this::CurrentRunStatus, user, main_panel)
        sectionX = -5
        sectionY = 165
        pieces = user.pieces === nothing ? [] : user.pieces
        metrics = inventory_list_metrics(this, :pieces, length(pieces))
        
        # Section title
        DisplayTextModule.display_text(
            "pieces_title",
            UIStringsModule.format_string(:current_run_pieces_count, count=length(pieces));
            fontSize = this.bodyFontSize,
            color = this.textColor, 
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(sectionX + 50, sectionY),
            layer = 102
        )
        
        # Draw pieces grid
        startRow = metrics.scrollOffset
        visibleRows = inventory_visible_rows(this)
        for (i, piece) in enumerate(pieces)
            # Calculate grid position
            col = (i - 1) % metrics.itemsPerRow
            row = (i - 1) ÷ metrics.itemsPerRow
            (row < startRow || row >= startRow + visibleRows) && continue
            
            itemX = metrics.itemOriginX + col * metrics.stride
            itemY = INVENTORY_GRID_TOP + (row - startRow) * metrics.stride
            
            # Draw piece slot
            slot_rect = JulGame.ImmediateUIModule.immediate_rect(
                "piece_slot_$(i)";
                size = Math.Vector2(this.itemSize, this.itemSize),
                color = (60, 80, 100, 0),
                layer = 103,
                parent = main_panel,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(itemX, itemY),
            )
            
            # Draw piece icon using proper asset path
            iconPath = get_icon_path(piece.key)
            icon_button = JulGame.ImmediateUIModule.immediate_button(
                "piece_icon_$(i)",
                () -> @debug("Piece $(piece.key) clicked");
                size = Math.Vector2(this.itemSize - 10, this.itemSize - 10),
                buttonUpPath = iconPath,
                buttonDownPath = iconPath,
                layer = 104,
                anchor = :center,
                parent = slot_rect,
                anchorOffset = Math.Vector2(0, 0),
                forceClickCheck = true,
            )
            
            # Register tooltip for this piece
            if this.tooltipManager !== nothing
                tooltip_text = get_piece_tooltip_text(piece, user)
                Scripts.TooltipManagerModule.register_tooltip_item(
                    this.tooltipManager,
                    icon_button,
                    tooltip_text
                )
            end
        end

        draw_list_scroll_buttons(this, main_panel, metrics)
    end
    
    """
    Draw the treasures section (right side)
    """
    function draw_treasures_section(this::CurrentRunStatus, user, main_panel)
        sectionX = this.panelWidth ÷ 2 + 20
        sectionY = 165
        treasures = user.treasures === nothing ? [] : user.treasures
        metrics = inventory_list_metrics(this, :treasures, length(treasures))
        
        # Section title
        DisplayTextModule.display_text(
            "treasures_title",
            UIStringsModule.format_string(:current_run_treasures_count, count=length(treasures));
            fontSize = this.bodyFontSize,
            color = this.textColor,
            parent = main_panel,
            anchor = :topLeft,
            anchorOffset = Math.Vector2(sectionX - 5, sectionY),
            layer = 102
        )
        
        # Draw items grid
        startRow = metrics.scrollOffset
        visibleRows = inventory_visible_rows(this)
        for (i, treasure) in enumerate(treasures)
            # Calculate grid position
            col = (i - 1) % metrics.itemsPerRow
            row = (i - 1) ÷ metrics.itemsPerRow
            (row < startRow || row >= startRow + visibleRows) && continue
            
            itemX = metrics.itemOriginX + col * metrics.stride
            itemY = INVENTORY_GRID_TOP + (row - startRow) * metrics.stride
            
            # Draw item slot
            slot_rect = JulGame.ImmediateUIModule.immediate_rect(
                "treasure_slot_$(i)";
                size = Math.Vector2(this.itemSize, this.itemSize),
                color = (100, 80, 60, 0),
                layer = 103,
                parent = main_panel,
                anchor = :topLeft,
                anchorOffset = Math.Vector2(itemX, itemY),
            )
            
            # Draw item icon using proper treasure asset path
            iconPath = get_treasure_icon_path(treasure.key)
            treasure_button = JulGame.ImmediateUIModule.immediate_button(
                "treasure_icon_$(i)",
                () -> @debug("Treasure $(treasure.key) clicked");
                size = Math.Vector2(this.itemSize - 16, this.itemSize - 16),
                buttonUpPath = iconPath,
                buttonDownPath = iconPath,
                layer = 104,
                anchor = :center,
                parent = slot_rect,
                anchorOffset = Math.Vector2(0, 0),
                forceClickCheck = true
            )
            
            # Register tooltip for this treasure
            if this.tooltipManager !== nothing
                tooltip_text = get_treasure_tooltip_text(treasure)
                Scripts.TooltipManagerModule.register_tooltip_item(
                    this.tooltipManager,
                    treasure_button,
                    tooltip_text
                )
            end
        end

        draw_list_scroll_buttons(this, main_panel, metrics)
    end
    
    """
    Get tooltip text for a piece
    """
    function get_piece_tooltip_text(piece, context; weight_percent = nothing)
        tooltip = "$(piece.name)"
        if piece.description !== nothing && piece.description != ""
            tooltip *= "\n$(piece.description)"
        end
        pieces = context
        try
            pieces = context.pieces
        catch
            # Older callers pass the piece pool directly.
        end
        attack_bonus = 0
        try
            attack_bonus = context.attack
        catch
            try
                current_user = JulGame.UserGlobals["Module"].get_user_data()
                attack_bonus = current_user.attack
            catch e
                @debug "Could not read user attack for piece tooltip: $e"
            end
        end
        if piece.attack > 0
            attack_value = attack_bonus > 0 ? "$(piece.attack) + $(attack_bonus)" : "$(piece.attack)"
            tooltip *= "\n" * UIStringsModule.format_string(:current_run_tooltip_attack, value=attack_value)
        end
        if piece.defense > 0
            tooltip *= "\n" * UIStringsModule.format_string(:current_run_tooltip_defense, value=piece.defense)
        end
        # Add rarity/weight information (relative to all pieces)
        if weight_percent === nothing
            total_rarity = sum(p.weight for p in pieces)
            if total_rarity > 0
                weight_percent = round((piece.weight / total_rarity) * 100, digits=2)
            end
        end
        if weight_percent !== nothing
            tooltip *= "\n" * UIStringsModule.format_string(:current_run_tooltip_weight, percent=weight_percent)
        end
        return tooltip
    end
    
    """
    Get tooltip text for a potion
    """
    function get_potion_tooltip_text(potion)
        tooltip = "$(potion.name)"
        if potion.description !== nothing && potion.description != ""
            tooltip *= "\n$(potion.description)"
        end
        return tooltip
    end
    
    """
    Get tooltip text for a treasure
    """
    function get_treasure_tooltip_text(treasure)
        tooltip = "$(treasure.name)"
        if treasure.description !== nothing && treasure.description != ""
            tooltip *= "\n$(treasure.description)"
        end
        return tooltip
    end
    
    """
    Format elapsed time in seconds to a human-readable string (e.g., "12m56s" or "1h05m")
    """
    function format_elapsed_time(elapsed_seconds::Float64)::String
        total_seconds = Int(floor(elapsed_seconds))
        hours = total_seconds ÷ 3600
        minutes = (total_seconds % 3600) ÷ 60
        seconds = total_seconds % 60
        
        if hours > 0
            return "$(hours)h$(lpad(minutes, 2, '0'))m"
        else
            return "$(minutes)m$(lpad(seconds, 2, '0'))s"
        end
    end
    
end # module
