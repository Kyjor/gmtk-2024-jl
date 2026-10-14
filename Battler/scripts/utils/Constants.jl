# Constants for pieces
const SWORD = "Sword"
const SHIELD = "Shield"
const POTION = "Potion"
const DODGE = "Dodge"
const CRIMSON_BLADE = "CrimsonBlade"
const GEM_GREEN = "GreenGem"

# World-space X nudge for heart BG sprites (scaled 1.1x) so FG clock-sweep hearts sit centered.
const HEART_BACKGROUND_OFFSET = -0.02f0

const BATTLE_NUMBER_FONT = "Noto_Sans_JP/static/NotoSansJP-Bold.ttf"
const BATTLE_NUMBER_FONT_SIZE = 31
const BATTLE_INTENT_FONT_SIZE = 35

const BATTLE_NUMBER_TEXT_EFFECTS = [
    RoughEdgeEffect(; amount=2, seed=42, erosion=true),
    DropShadowEffect(; distance=1.0, angle=90.0, blur_radius=2, color=(0, 0, 0, 255), opacity=80),
]

function apply_battle_number_text_effects!(tb)
    tb === nothing && return tb
    JulGame.apply_effects!(tb, BATTLE_NUMBER_TEXT_EFFECTS)
    return tb
end