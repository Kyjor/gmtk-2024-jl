module ReleaseNotesDisplayModule
    using JulGame
    include("utils/DisplayText.jl")
    using .DisplayTextModule
    using JulGame.ImmediateUIModule
    using JulGame.Math
    using ..Scripts

    """
    ReleaseNotesDisplay manages the display of release notes in the game.
    Provides a modal overlay that shows release notes with proper formatting.
    """
    mutable struct ReleaseNotesDisplay
        is_showing::Bool
        background_rect::Union{Nothing, Any}
        title_text::Union{Nothing, Any}
        content_text::Union{Nothing, Any}
        close_hint_text::Union{Nothing, Any}
        page_hint_text::Union{Nothing, Any}
        open_hint_text::Union{Nothing, Any}
        filter_by_keywords::Bool
        pages::Vector{String}
        current_page::Int
        max_versions::Int
        
        function ReleaseNotesDisplay()
            this = new()
            this.is_showing = false
            this.background_rect = nothing
            this.title_text = nothing
            this.content_text = nothing
            this.close_hint_text = nothing
            this.page_hint_text = nothing
            this.open_hint_text = nothing
            this.filter_by_keywords = true
            this.pages = String[]
            this.current_page = 1
            this.max_versions = 10
            return this
        end
    end

    """
    Initialize the release notes display. Pages are fetched lazily in `show`
    (first F1 press) — generating them spawns git subprocesses, which must
    stay off the startup path.
    """
    function initialize(this::ReleaseNotesDisplay, globals)
        this.pages = String[]
        this.current_page = 1
    end

    """
    Show the release notes display overlay.
    """
    function show(this::ReleaseNotesDisplay, globals)
        if this.is_showing
            return
        end
        
        # Hide hint text if showing
        hide_hint(this)
        
        # Refresh pages (cached in globals after first load)
        this.pages = globals.get_release_notes_paged(max_versions = this.max_versions)
        if isempty(this.pages)
            this.pages = ["No release notes available."]
        end
        this.current_page = 1

        this.is_showing = true
        render(this, globals)
    end

    """
    Hide the release notes display overlay.
    """
    function hide(this::ReleaseNotesDisplay)
        if !this.is_showing
            return
        end
        
        this.is_showing = false
        
        # Show hint text again when hiding
        # (will be shown by update function)
        
        # Remove UI elements
        if this.background_rect !== nothing
            try
                ImmediateUIModule.remove_immediate_ui("release_notes_bg")
            catch
            end
            this.background_rect = nothing
        end
        
        if this.title_text !== nothing
            try
                ImmediateUIModule.remove_immediate_ui("release_notes_title")
            catch
            end
            this.title_text = nothing
        end
        
        if this.content_text !== nothing
            try
                ImmediateUIModule.remove_immediate_ui("release_notes_content")
            catch
            end
            this.content_text = nothing
        end
        
        if this.close_hint_text !== nothing
            try
                ImmediateUIModule.remove_immediate_ui("release_notes_close")
            catch
            end
            this.close_hint_text = nothing
        end

        if this.page_hint_text !== nothing
            try
                ImmediateUIModule.remove_immediate_ui("release_notes_page_hint")
            catch
            end
            this.page_hint_text = nothing
        end
    end

    """
    Show a hint text indicating that release notes can be opened with F1.
    Should be called when release notes are not showing.
    """
    function show_hint(this::ReleaseNotesDisplay, globals)
        if this.is_showing || this.open_hint_text !== nothing
            return
        end
        
        # Get localized hint text
        hint_text = globals.get_localized_string("UI_Title_Release_Notes_Open_Hint", "Press F1 for release notes")
        
        # Show hint text in bottom left, above version number
        this.open_hint_text = DisplayTextModule.display_text(
            "release_notes_open_hint",
            hint_text;
            fontPath = "Century-Normal.ttf",
            fontSize = 16,
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(5, -45),
            color = (200, 200, 200, 180)
        )
    end

    """
    Hide the hint text.
    """
    function hide_hint(this::ReleaseNotesDisplay)
        if this.open_hint_text !== nothing
            try
                ImmediateUIModule.remove_immediate_ui("release_notes_open_hint")
            catch
            end
            this.open_hint_text = nothing
        end
    end

    """
    Toggle the release notes display on/off.
    """
    function toggle(this::ReleaseNotesDisplay, globals)
        if this.is_showing
            hide(this)
        else
            show(this, globals)
        end
    end

    """
    Update the release notes display. Handles input for toggling.
    Should be called every frame in the update loop.
    """
    function update(this::ReleaseNotesDisplay, globals, deltaTime::Float64)
        return
        # Check for F1 key press to toggle release notes
        if JulGame.InputModule.get_button_pressed("F1")
            #toggle(this, globals)
        end

        if this.is_showing
            if JulGame.InputModule.get_button_pressed("LEFT") && this.current_page > 1
                this.current_page -= 1
            elseif JulGame.InputModule.get_button_pressed("RIGHT") && this.current_page < length(this.pages)
                this.current_page += 1
            end
            render(this, globals)
        end
        
        # Show/hide hint text based on display state
        if !this.is_showing && this.open_hint_text === nothing
            show_hint(this, globals)
        elseif this.is_showing && this.open_hint_text !== nothing
            hide_hint(this)
        end
    end

    """
    Re-render persistent immediate UI elements each frame to keep them alive.
    """
    function render(this::ReleaseNotesDisplay, globals)
        title_text = globals.get_localized_string("UI_Title_Release_Notes_Title", "Release Notes")
        close_hint = globals.get_localized_string("UI_Title_Release_Notes_Close_Hint", "Press F1 to close")

        this.background_rect = Scripts.NineSliceUIModule.immediate_panel(
            "release_notes_bg";
            anchor = :center,
            anchorOffset = Math.Vector2(0, 0),
            position = Math.Vector2(0, 0),
            size = Math.Vector2(1180, 620),
            layer = 0,
        )

        this.title_text = DisplayTextModule.display_text(
            "release_notes_title",
            title_text;
            fontSize = 32,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 10),
            lifetime = 200,
            parent = this.background_rect
        )

        page_content = isempty(this.pages) ? "" : this.pages[this.current_page]
        this.content_text = DisplayTextModule.display_text(
            "release_notes_content",
            page_content;
            fontSize = 20,
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, 50),
            maxLineWidth = 1100,
            wrapWords = true,
            lifetime = 200,
            parent = this.background_rect
        )

        this.close_hint_text = DisplayTextModule.display_text(
            "release_notes_close",
            close_hint;
            fontPath = "Century-Normal.ttf",
            fontSize = 24,
            anchor = :bottomLeft,
            anchorOffset = Math.Vector2(5, -5),
            lifetime = 200,
            parent = this.background_rect
        )

        n_pages = length(this.pages)
        if n_pages > 1
            nav_text = "◄ $(this.current_page) / $(n_pages) ►"
            this.page_hint_text = DisplayTextModule.display_text(
                "release_notes_page_hint",
                nav_text;
                fontPath = "Century-Normal.ttf",
                fontSize = 24,
                anchor = :bottomRight,
                anchorOffset = Math.Vector2(-5, -5),
                lifetime = 200,
                parent = this.background_rect
            )
        end
    end

    """
    Check if the release notes display is currently showing.
    """
    function is_displaying(this::ReleaseNotesDisplay)::Bool
        return this.is_showing
    end

end # module

