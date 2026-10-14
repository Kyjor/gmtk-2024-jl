# Tutorial Strings Dictionary
# Used in: scripts/Tutorial.jl
# Contains the first-battle guided lesson and the settings "How to play" page

module TutorialStringsModule

const TUTORIAL_STRINGS = Dict(
    # Offer bar
    :offer_label => "Tutorial",
    :bubble_title => "Tutorial",
    :continue_hint => "Click anywhere to continue",

    # Guided steps
    :board => "This is the board. Line up 3 or more of the same piece to make a match.",
    :enemies => "Enemies show their next move. Some can even alter the board to their advantage.",
    :pieces => "Each piece does something when matched. Swords attack, shields defend, and potions heal. Weight is how often a piece appears.",
    :match => "Swap the two glowing pieces to make a match.",
    :match_none => "There's nothing to match right now. Try again next turn.",
    :combo_intro => "When you make multiple matches in one move, that's a combo. Each match shows a star up here.",
    :combo_match => "Try another one. Learn how the pieces fall.",
    :combo_result_hit => "Combo x{count}! Think ahead to try and make more happen efficiently.",
    :combo_result_none => "No combo this time, but you will see one soon.",
    :target => "Your attacks hit the enemy with the heart marker. Click another enemy's heart to switch targets.",
    :target_done => "Target switched. If you defeat an enemy in the middle of a combo, it'll automatically switch to another enemy.",
    :treasure => "Treasures award passive and active abilities that will help you in battles. They sit down here.",
    :shield => "Shield prevents attack damage, but you lose it all at the end of every turn.",
    :ability_magician => "Your ability allows you to drag a piece from your queue straight onto the board. As the Magician, your combo stars also deal damage to enemies.",
    :ability_demolitionist => "Your ability allows you to blow up a whole row or column. As the Demolitionist, you also start every battle with a free Giga Bomb potion.",
    :ability_knight => "Your ability allows you to do nothing. As the Knight, you do nothing.",
    :ability_default => "This is your ability. Use it on your turn to do something.",
    :ability_more => "Each character starts with a rare treasure that grants them an ability, and some treasures grant new ones.",
    :potions => "Potions are here in the potion bar. You can use them during your turn for no move cost.",
    :done => "Good luck in the battle!",

    # Settings "How to play" page
    :primer_button => "How to play",
    :primer_title => "How to play",
    :primer_close => "Click anywhere or press Esc to close",
    :primer_match => "Swap pieces to line up 3 or more. Matches activates that piece's effect.",
    :primer_enemies => "Enemies telegraph their next move. Defeat them before they defeat you.",
    :primer_weight => "Pieces with higher weight show up more often.",
    :primer_items => "Treasures grant passive and active abilities. Potions are single-use items that can be used during your turn.",
    :primer_ability => "Your character starts with a treasure that grants them an ability. Use it on your turn.",
    :primer_shield => "Shield prevents attack damage, but you lose it all at the end of every turn.",
)

end # module
