# source: https://www.reddit.com/r/Unity3D/comments/d9zy0d/i_made_a_simple_camera_shake_script_for_2d_and_3d/
module CameraShakeModule
using JulGame
using ..Scripts

mutable struct CameraShake
    parent

    gameManager
    interval::Float64
    offset::Float64
    duration::Float64
    original_pos
    elapsed::Float64
    shaking::Bool

    function CameraShake()
        this = new()

        this.elapsed = 0.0
        this.shaking = false
        this.interval = 0.05
        this.offset = 0.25
        this.duration = 0.25

        return this
    end
end

function JulGame.on_shutdown(this::CameraShake)
end

function JulGame.initialize(this::CameraShake)
    this.gameManager = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "Game Manager").scripts[1]
    this.original_pos = MAIN.scene.camera.position
    JulGame.update(this, 0)
end

function JulGame.update(this::CameraShake, deltaTime)
    if JulGame.IS_DEBUG && JulGame.InputModule.get_button_pressed("SPACE") && !this.shaking
        this.elapsed = 0.0
        this.shaking = true   
    end

    if this.shaking
        # Check if screen shake is enabled before applying
        if !Scripts.MainSettingsModule.is_screen_shake_enabled()
            this.shaking = false
            MAIN.scene.camera.position = this.original_pos
            return
        end
        
        this.elapsed += deltaTime
        if this.elapsed >= this.duration
            this.shaking = false
            # reset camera
            MAIN.scene.camera.position = this.original_pos
            return
        end

        MAIN.scene.camera.position = JulGame.Math.Vector3f(this.original_pos.x + rand(-this.offset*10:this.offset*10)/10, this.original_pos.y + rand(-this.offset*10:this.offset*10)/10, this.original_pos.z)
    end
end
end # module
