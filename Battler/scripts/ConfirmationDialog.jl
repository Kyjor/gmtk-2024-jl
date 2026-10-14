module ConfirmationDialogModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.Math
    using ..Scripts
    include("localization/ui_strings.jl")
    using .UIStringsModule

    mutable struct ConfirmationDialog
        is_showing::Bool
        title::String
        message::String
        on_confirm::Union{Nothing, Function}
        on_cancel::Union{Nothing, Function}
        confirm_text::String
        cancel_text::String
        layer::Int
        
        function ConfirmationDialog()
            this = new()
            
            this.is_showing = false
            this.title = ""
            this.message = ""
            this.on_confirm = nothing
            this.on_cancel = nothing
            this.confirm_text = UIStringsModule.UI_STRINGS[:confirm_button]
            this.cancel_text = UIStringsModule.UI_STRINGS[:cancel_button]
            this.layer = 500
            
            return this
        end
    end

    """
    Show a confirmation dialog with custom callbacks
    
    Example:
    show_confirmation(dialog, 
        "New Run", 
        "Starting a new run will erase your current progress. Continue?",
        () -> start_new_run(),
        () -> @debug("Canceled");
        confirm_text = "Start New Run",
        cancel_text = "Cancel"
    )
    """
    function show_confirmation(
        this::ConfirmationDialog, 
        title::String, 
        message::String,
        on_confirm::Function,
        on_cancel::Union{Nothing, Function} = nothing;
        confirm_text::String = UIStringsModule.UI_STRINGS[:confirm_button],
        cancel_text::String = UIStringsModule.UI_STRINGS[:cancel_button],
        layer::Int = 500
    )
        this.title = title
        this.message = message
        this.on_confirm = on_confirm
        this.on_cancel = on_cancel
        this.confirm_text = confirm_text
        this.cancel_text = cancel_text
        this.is_showing = true
        this.layer = layer
        @debug "Showing confirmation dialog: $title"
    end

    """
    Handle confirm button click
    """
    function confirm(this::ConfirmationDialog)
        if this.on_confirm !== nothing
            this.on_confirm()
        end
        close_dialog(this)
    end

    """
    Handle cancel button click
    """
    function cancel(this::ConfirmationDialog)
        if this.on_cancel !== nothing
            this.on_cancel()
        end
        close_dialog(this)
    end

    """
    Close the dialog
    """
    function close_dialog(this::ConfirmationDialog)
        this.is_showing = false
        this.on_confirm = nothing
        this.on_cancel = nothing
        @debug "Confirmation dialog closed"
    end

    """
    Draw the confirmation dialog UI
    """
    function draw_dialog(this::ConfirmationDialog)
        if !this.is_showing
            return
        end
        
        # Draw semi-transparent overlay background
        overlay = JulGame.ImmediateUIModule.immediate_rect(
            "confirmation_overlay";
            size = Math.Vector2(1920, 1080),
            color = (0, 0, 0, 180),
            anchor = :center,
            layer = this.layer,
            clickEvent = () -> nothing,
        )
        
        panel = Scripts.NineSliceUIModule.immediate_panel(
            "confirmation_panel";
            size = Math.Vector2(700, 350),
            anchor = :center,
            layer = this.layer + 1,
        )
        
        # Draw title
        DisplayTextModule.display_text(
            "confirmation_title",
            this.title;
            fontSize = 32,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 30),
            color = (255, 255, 255, 255),
            layer = this.layer + 2,
            parent = panel
        )
        
        # Draw message with word wrapping
        DisplayTextModule.display_text(
            "confirmation_message",
            this.message;
            fontSize = 22,
            anchor = :center,
            anchorOffset = Math.Vector2(0, 0),
            color = (220, 220, 220, 255),
            layer = this.layer + 2,
            maxLineWidth = 620,
            wrapWords = true,
            parent = panel
        )
        
        # Draw confirm button (left)
        Scripts.NineSliceUIModule.immediate_button(
            "confirmation_button_confirm",
            () -> confirm(this);
            text = this.confirm_text,
            fontSize = 24,
            size = Math.Vector2(250, 60),
            anchor = :centerBottom,
            anchorOffset = Math.Vector2(-140, -30),
            color = (100, 150, 100, 255),
            layer = this.layer + 2,
            parent = panel
        )
        
        # Draw cancel button (right)
        Scripts.NineSliceUIModule.immediate_button(
            "confirmation_button_cancel",
            () -> cancel(this);
            text = this.cancel_text,
            fontSize = 24,
            size = Math.Vector2(250, 60),
            anchor = :centerBottom,
            anchorOffset = Math.Vector2(140, -30),
            color = (150, 100, 100, 255),
            layer = this.layer + 2,
            parent = panel
        )
    end

    """
    Update function to be called each frame
    """
    function update(this::ConfirmationDialog, deltaTime)
        if this.is_showing
            draw_dialog(this)
        end
    end

end # module

