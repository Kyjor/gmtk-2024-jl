module SfxChannelsModule
    """
    SDL mixer channel assignments.

    Never use channel -1 for SFX volume: Mix_Volume(-1, vol) sets ALL channels,
    which stomps the drums layer on channel 4 and rest-site ambience on channel 6.

    Music uses Mix_VolumeMusic (not a channel slot).
    """
    const SFX_CHANNEL_UI = 0
    const SFX_CHANNEL_GAMEPLAY = 1
    const SFX_CHANNEL_TYPING = 2
    const SFX_CHANNEL_MISC = 3
    const DRUMS_CHANNEL = 4
    const SFX_CHANNEL_COMBO = 5
    const AMBIENCE_CHANNEL = 6

    const DEFAULT_SFX_CHANNEL = SFX_CHANNEL_GAMEPLAY

    # Gameplay one-shots are redirected to a free channel in this range so they overlap
    # instead of cutting each other off on SFX_CHANNEL_GAMEPLAY.
    const MIXER_CHANNEL_COUNT = 32
    const SFX_POOL_FIRST = 8
    const SFX_POOL_LAST = MIXER_CHANNEL_COUNT - 1
    const SFX_POOL_TAG = 1

    export SFX_CHANNEL_UI, SFX_CHANNEL_GAMEPLAY, SFX_CHANNEL_TYPING,
           SFX_CHANNEL_MISC, DRUMS_CHANNEL, SFX_CHANNEL_COMBO, AMBIENCE_CHANNEL,
           DEFAULT_SFX_CHANNEL, MIXER_CHANNEL_COUNT, SFX_POOL_FIRST, SFX_POOL_LAST, SFX_POOL_TAG
end
