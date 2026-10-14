module AcknowledgmentsModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.Math
    using JSON3
    using ..Scripts
    include("localization/ui_strings.jl")
    using .UIStringsModule
    
    # Acknowledgment messages
    const ACKNOWLEDGMENT_MESSAGES = Dict(
        "early_access" => Dict(
            "title" => UIStringsModule.UI_STRINGS[:ack_early_access_title],
            "message" => UIStringsModule.UI_STRINGS[:ack_early_access_message],
            "button" => UIStringsModule.UI_STRINGS[:ack_early_access_button]
        ),
        "analytics" => Dict(
            "title" => UIStringsModule.UI_STRINGS[:ack_analytics_title],
            "message" => UIStringsModule.UI_STRINGS[:ack_analytics_message],
            "button" => UIStringsModule.UI_STRINGS[:ack_analytics_button_enable],
            "button2" => UIStringsModule.UI_STRINGS[:ack_analytics_button_no_thanks],
            "has_choice" => true
        ),
        "terms" => Dict(
            "title" => UIStringsModule.UI_STRINGS[:ack_terms_title],
            "message" => UIStringsModule.UI_STRINGS[:ack_terms_message],
            "button" => UIStringsModule.UI_STRINGS[:ack_terms_button]
        )
    )

    mutable struct AcknowledgmentManager
        acknowledgments_to_show::Vector{String}
        current_index::Int
        is_showing::Bool
        acknowledged_items::Dict{String, Bool}
        pref_file_path::String
        on_analytics_choice::Union{Nothing, Function}
        
        function AcknowledgmentManager()
            this = new()
            
            this.acknowledgments_to_show = []
            this.current_index = 1
            this.is_showing = false
            this.acknowledged_items = Dict{String, Bool}()
            this.pref_file_path = JulGame.PrefHandlerModule.get_pref_path("kyjor", "necromatcher"; file_name = "acknowledgments.json")
            this.on_analytics_choice = nothing
            
            if get(ENV, "TEST_MODE", "false") == "true"
                this.is_showing = false
                return this
            end
            # Load existing acknowledgments
            load_acknowledgments(this)
            
            return this
        end
    end

    """
    Load acknowledgments from the preference file
    """
    function load_acknowledgments(this::AcknowledgmentManager)
        try
            if isfile(this.pref_file_path)
                data = JSON3.read(this.pref_file_path)
                # Convert symbol keys to strings
                this.acknowledged_items = Dict{String, Bool}(String(k) => v for (k, v) in pairs(data))
                @debug "Loaded acknowledgments from $(this.pref_file_path): $(this.acknowledged_items)"
            else
                @debug "No acknowledgments file found at $(this.pref_file_path), starting fresh"
            end
        catch e
            @error "Failed to load acknowledgments: $e"
            this.acknowledged_items = Dict{String, Bool}()
        end
    end

    """
    Save acknowledgments to the preference file
    """
    function save_acknowledgments(this::AcknowledgmentManager)
        try
            # Ensure directory exists
            dir = dirname(this.pref_file_path)
            if !isdir(dir)
                mkpath(dir)
            end
            
            # Write to file
            open(this.pref_file_path, "w") do io
                JSON3.write(io, this.acknowledged_items)
            end
            @debug "Saved acknowledgments to $(this.pref_file_path)"
        catch e
            @error "Failed to save acknowledgments: $e"
        end
    end

    """
    Queue acknowledgments to be shown. They will be displayed one after another.
    Example: show_acknowledgments(manager, ["early_access", "analytics"])
    """
    function show_acknowledgments(this::AcknowledgmentManager, acknowledgment_ids::Vector{String})
        # Filter out already acknowledged items
        items_to_show = filter(id -> !get(this.acknowledged_items, id, false), acknowledgment_ids)
        
        if isempty(items_to_show)
            @debug "All acknowledgments already acknowledged"
            return
        end
        
        this.acknowledgments_to_show = items_to_show
        this.current_index = 1
        this.is_showing = true
        @debug "Queued $(length(items_to_show)) acknowledgments to show: $items_to_show"
    end

    """
    Show a single acknowledgment. It will only show if not already acknowledged.
    Example: show_acknowledgment(manager, "early_access")
    """
    function show_acknowledgment(this::AcknowledgmentManager, acknowledgment_id::String)
        show_acknowledgments(this, [acknowledgment_id])
    end

    """
    Mark current acknowledgment as acknowledged and move to next, or close if done
    choice: true for accepting/enabling, false for declining (only used for analytics)
    """
    function acknowledge_current(this::AcknowledgmentManager, choice::Bool = true)
        if !this.is_showing || isempty(this.acknowledgments_to_show)
            return
        end
        
        # Mark current acknowledgment as acknowledged
        current_id = this.acknowledgments_to_show[this.current_index]
        this.acknowledged_items[current_id] = true
        @debug "Acknowledged: $current_id with choice: $choice"
        
        # Handle analytics choice
        if current_id == "analytics" && this.on_analytics_choice !== nothing
            this.on_analytics_choice(choice)
        end
        
        # Save to file
        save_acknowledgments(this)
        
        # Move to next acknowledgment or close
        if this.current_index < length(this.acknowledgments_to_show)
            this.current_index += 1
            @debug "Moving to next acknowledgment ($(this.current_index)/$(length(this.acknowledgments_to_show)))"
        else
            # All acknowledgments shown
            this.is_showing = false
            this.acknowledgments_to_show = []
            this.current_index = 1
            @debug "All acknowledgments complete"
        end
    end

    """
    Draw the acknowledgment panel UI
    """
    function draw_acknowledgment_panel(this::AcknowledgmentManager)
        if !this.is_showing || isempty(this.acknowledgments_to_show)
            return
        end
        
        current_id = this.acknowledgments_to_show[this.current_index]
        
        # Check if acknowledgment exists in our messages dictionary
        if !haskey(ACKNOWLEDGMENT_MESSAGES, current_id)
            @error "Unknown acknowledgment ID: $current_id"
            acknowledge_current(this)  # Skip to next
            return
        end
        
        message_data = ACKNOWLEDGMENT_MESSAGES[current_id]
        
        # Draw semi-transparent overlay background
        overlay = JulGame.ImmediateUIModule.immediate_rect(
            "acknowledgment_overlay";
            size = Math.Vector2(1920, 1080),
            color = (0, 0, 0, 180),
            anchor = :center,
            layer = 500
        )
        
        panel = Scripts.NineSliceUIModule.immediate_panel(
            "acknowledgment_panel";
            size = Math.Vector2(800, 450),
            anchor = :center,
            layer = 501,
        )
        
        # Draw title
        DisplayTextModule.display_text(
            "acknowledgment_title",
            message_data["title"];
            fontSize = 32,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 30),
            color = (255, 255, 255, 255),
            layer = 502,
            parent = panel
        )
        
        # Draw message with word wrapping
        DisplayTextModule.display_text(
            "acknowledgment_message",
            message_data["message"];
            fontSize = 22,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 90),
            color = (220, 220, 220, 255),
            layer = 502,
            maxLineWidth = 720,
            wrapWords = true,
            parent = panel
        )
        
        # Draw acknowledge button(s)
        if get(message_data, "has_choice", false)
            # Draw two buttons for choice
            Scripts.NineSliceUIModule.immediate_button(
                "acknowledgment_button_accept",
                () -> acknowledge_current(this, true);
                text = message_data["button"],
                fontSize = 24,
                size = Math.Vector2(200, 60),
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(-110, -30),
                color = (100, 150, 100, 255),
                layer = 502,
                parent = panel
            )
            
            Scripts.NineSliceUIModule.immediate_button(
                "acknowledgment_button_decline",
                () -> acknowledge_current(this, false);
                text = message_data["button2"],
                fontSize = 24,
                size = Math.Vector2(200, 60),
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(110, -30),
                color = (150, 100, 100, 255),
                layer = 502,
                parent = panel
            )
        else
            # Draw single button
            Scripts.NineSliceUIModule.immediate_button(
                "acknowledgment_button",
                () -> acknowledge_current(this);
                text = message_data["button"],
                fontSize = 24,
                size = Math.Vector2(200, 60),
                anchor = :centerBottom,
                anchorOffset = Math.Vector2(0, -30),
                color = (100, 150, 100, 255),
                layer = 502,
                parent = panel
            )
        end
        
        # Draw progress indicator if multiple acknowledgments
        if length(this.acknowledgments_to_show) > 1
            progress_text = "$(this.current_index) / $(length(this.acknowledgments_to_show))"
            DisplayTextModule.display_text(
                "acknowledgment_progress",
                progress_text;
                fontSize = 16,
                anchor = :bottomRight,
                anchorOffset = Math.Vector2(-15, -10),
                color = (180, 180, 180, 255),
                layer = 502,
                parent = panel
            )
        end
    end

    """
    Update function to be called each frame
    """
    function update(this::AcknowledgmentManager, deltaTime)
        if this.is_showing && get(ENV, "TEST_MODE", "false") == "false"
            draw_acknowledgment_panel(this)
        end
    end

end # module

