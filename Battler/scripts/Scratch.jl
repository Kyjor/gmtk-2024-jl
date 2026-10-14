module ScratchModule
    using JulGame
    mutable struct Scratch <: Script
        parent # do not remove this line, this is a reference to the entity that this script is attached to
        # This is where you define your script's fields
        scrollTime::Float32
        previousPositions::Dict{Tuple{Int, Int}, Tuple{Float32, Float32}}  # Store previous positions for each square
        permanentOffsets::Dict{Tuple{Int, Int}, Tuple{Float32, Float32}}  # Store permanent offsets for each square
        function Scratch()
            this = new() # do not remove this line
            
            # this is where you initialize your script's fields
            this.scrollTime = 0.0f0
            this.previousPositions = Dict{Tuple{Int, Int}, Tuple{Float32, Float32}}()
            this.permanentOffsets = Dict{Tuple{Int, Int}, Tuple{Float32, Float32}}()
            return this # do not remove this line
        end
    end

    # Custom easing function for depth curve
    function applyDepthCurve(t::Float32, curveType::String="linear")::Float32
        if curveType == "easeIn"
            # Starts slow, accelerates
            return t * t
        elseif curveType == "easeOut"
            # Starts fast, decelerates
            return 1.0f0 - (1.0f0 - t) * (1.0f0 - t)
        elseif curveType == "easeInOut"
            # Slow start, fast middle, slow end
            return t < 0.5f0 ? 2.0f0 * t * t : 1.0f0 - 2.0f0 * (1.0f0 - t) * (1.0f0 - t)
        elseif curveType == "exponential"
            # Exponential curve for dramatic effect
            return t * t * t
        elseif curveType == "sine"
            # Smooth sine curve
            return sin(t * π / 2.0f0)
        elseif curveType == "bounce"
            # Bounce effect
            if t < 0.5f0
                return 2.0f0 * t * t
            else
                return 1.0f0 - 2.0f0 * (1.0f0 - t) * (1.0f0 - t)
            end
        else
            # Linear (default)
            return t
        end
    end

    # Append a slanted rectangle (two triangles) to a geometry batch
    function appendSlantedRect!(vertices::Vector{JulGame.SDL2.SDL_Vertex}, indices::Vector{Cint},
                                centerX::Float32, centerY::Float32, width::Float32, height::Float32,
                                angleDegrees::Float32, color::JulGame.SDL2.SDL_Color)
        # Calculate slant offset using trigonometry
        slantAngleRadians = angleDegrees * π / 180.0f0
        slantOffset = height * tan(slantAngleRadians)

        baseIndex = Cint(length(vertices))
        # Top vertices (moved inward by slantOffset)
        push!(vertices, JulGame.SDL2.SDL_Vertex(JulGame.SDL2.SDL_FPoint(centerX - width - slantOffset, centerY - height), color, JulGame.SDL2.SDL_FPoint(0.0f0, 0.0f0)))
        push!(vertices, JulGame.SDL2.SDL_Vertex(JulGame.SDL2.SDL_FPoint(centerX + width - slantOffset, centerY - height), color, JulGame.SDL2.SDL_FPoint(0.0f0, 0.0f0)))
        # Bottom vertices (full width)
        push!(vertices, JulGame.SDL2.SDL_Vertex(JulGame.SDL2.SDL_FPoint(centerX + width, centerY + height), color, JulGame.SDL2.SDL_FPoint(0.0f0, 0.0f0)))
        push!(vertices, JulGame.SDL2.SDL_Vertex(JulGame.SDL2.SDL_FPoint(centerX - width, centerY + height), color, JulGame.SDL2.SDL_FPoint(0.0f0, 0.0f0)))

        # Define indices for the shape (two triangles)
        append!(indices, baseIndex .+ Cint[0, 1, 2, 0, 2, 3])
    end

    function queueGeometry(vertices::Vector{JulGame.SDL2.SDL_Vertex}, indices::Vector{Cint}; layer::Int = -2, isWorldEntity::Bool = false)
        isempty(vertices) && return
        # Render using SDL_RenderGeometry
        JulGame.Rendering.queue_render_function(
            () -> begin
                JulGame.SDL2.SDL_SetRenderDrawBlendMode(JulGame.Renderer, JulGame.SDL2.SDL_BLENDMODE_BLEND)
                JulGame.SDL2.SDL_RenderGeometry(
                    JulGame.Renderer, 
                    C_NULL,  # No texture
                    vertices, 
                    length(vertices), 
                    indices, 
                    length(indices)
                )
            end;
            layer = layer,
            isWorldEntity = isWorldEntity
        )
    end

    # Shared scrolling background (title, settings, optionally battle). Scroll state is
    # module-global so the pattern continues seamlessly across screens and scene loads.
    const SCROLL_BG_COLOR = JulGame.SDL2.SDL_Color(7, 0, 15, 255)
    const SCROLL_BG_MAX_STEP = 1.0 / 15.0
    const scrollBgTime = Ref(0.0)
    const scrollBgLastDraw = Ref(0.0)
    const scrollBgHasLogged = Ref(false)

    function _persistent_state_manager()
        try
            return JulGame.UserGlobals["Module"].get_data_manager().persistent_state_manager
        catch
            return nothing
        end
    end

    function get_scroll_bg_hue()::Float64
        psm = _persistent_state_manager()
        return psm === nothing ? 0.0 : Float64(psm.scrollBgHue)
    end

    # SVG/CSS hue-rotate matrix
    function hueShift(color::JulGame.SDL2.SDL_Color, deg::Float64)::JulGame.SDL2.SDL_Color
        deg == 0.0 && return color
        c = cos(deg * π / 180.0)
        s = sin(deg * π / 180.0)
        r = Float64(color.r); g = Float64(color.g); b = Float64(color.b)
        nr = (0.213 + 0.787c - 0.213s) * r + (0.715 - 0.715c - 0.715s) * g + (0.072 - 0.072c + 0.928s) * b
        ng = (0.213 - 0.213c + 0.143s) * r + (0.715 + 0.285c + 0.140s) * g + (0.072 - 0.072c - 0.283s) * b
        nb = (0.213 - 0.213c - 0.787s) * r + (0.715 - 0.715c + 0.715s) * g + (0.072 + 0.928c + 0.072s) * b
        toByte(x) = UInt8(clamp(round(Int, x), 0, 255))
        return JulGame.SDL2.SDL_Color(toByte(nr), toByte(ng), toByte(nb), color.a)
    end

    function _scroll_bg_screen_size()::Tuple{Float32, Float32}
        cam = JulGame.MAIN.scene.camera
        if cam !== nothing && cam.size.x > 0 && cam.size.y > 0
            return Float32(cam.size.x), Float32(cam.size.y)
        end
        out_w = Ref{Cint}(0); out_h = Ref{Cint}(0)
        JulGame.SDL2.SDL_GetRendererOutputSize(JulGame.Renderer, out_w, out_h)
        return Float32(out_w[]), Float32(out_h[])
    end

    """
    Queue the diagonal scrolling background. Safe to call from several places in one frame:
    scroll time advances by wall-clock delta (clamped), so extra calls add ~0 time.
    """
    function draw_scroll_bg!(; layer::Int = -2, alpha::Float64 = 1.0, isWorldEntity::Bool = false)
        # Update scroll time
        now = time()
        if scrollBgLastDraw[] > 0.0
            scrollBgTime[] += min(now - scrollBgLastDraw[], SCROLL_BG_MAX_STEP)
        end
        scrollBgLastDraw[] = now

        a = clamp(round(Int, 255 * alpha), 0, 255)
        a == 0 && return
        tint = hueShift(SCROLL_BG_COLOR, get_scroll_bg_hue())
        dark_purple = JulGame.SDL2.SDL_Color(tint.r, tint.g, tint.b, UInt8(a))
        
        rectWidth = 58.0f0
        rectHeight = 38.0f0
        spacingX = 116.0f0
        spacingY = 76.0f0
        baseOffsetX = -920.0f0
        offsetY = -40.0f0
        
        # Add scrolling effect
        scrollSpeedX = 50.0f0  # pixels per second (right)
        scrollSpeedY = 30.0f0  # pixels per second (down)
        # The tiling repeats every 2 rows (shifted 2 * 65 px) and every 2 columns; wrap to keep Float32 precision
        rawOffsetY = offsetY + scrollBgTime[] * scrollSpeedY
        rowPeriods = floor(rawOffsetY / (2 * spacingY))
        scrollOffsetY = Float32(rawOffsetY - rowPeriods * 2 * spacingY)
        scrollOffsetX = Float32(mod(baseOffsetX + scrollBgTime[] * scrollSpeedX - rowPeriods * 2 * 65.0, 2 * spacingX))
        
        # Compute screen size once. Geometry is drawn in logical (camera) units, which differ
        # from renderer output pixels whenever the window isn't the camera size.
        screen_w, screen_h = _scroll_bg_screen_size()

        # Cover the screen with a margin; no per-tile state, no modulo
        # (200px >= tile half-width + slant offset)
        margin = 200.0f0
        rowStart = floor(Int, (-margin - scrollOffsetY) / spacingY)
        rowEnd   = ceil(Int,  (screen_h + margin - scrollOffsetY) / spacingY)

        # One batched draw call for the whole pattern
        vertices = JulGame.SDL2.SDL_Vertex[]
        indices = Cint[]
        for row in rowStart:rowEnd
            # Diagonal shift per row (keep your 65.0f0 pattern)
            rowShiftX = (row - 1) * 65.0f0

            colStart = floor(Int, (-margin - scrollOffsetX - rowShiftX) / spacingX)
            colEnd   = ceil(Int,  (screen_w + margin - scrollOffsetX - rowShiftX) / spacingX)

            for col in colStart:colEnd
                (row + col) % 2 == 0 || continue
                x = col * spacingX + scrollOffsetX + rowShiftX
                y = row * spacingY + scrollOffsetY

                angle = 60.0f0
                appendSlantedRect!(vertices, indices, x, y, rectWidth, rectHeight, angle, dark_purple)
            end
        end
        queueGeometry(vertices, indices; layer = layer, isWorldEntity = isWorldEntity)
    end

    # This is called every frame
    # Do not remove this function
    function JulGame.update(this::Scratch, deltaTime)
        draw_scroll_bg!()
    end
end

