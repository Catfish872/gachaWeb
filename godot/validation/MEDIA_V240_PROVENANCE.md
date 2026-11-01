# v2.4 scenery and combat feedback

## Original generated scenery

Six backgrounds were generated individually with the built-in image generator, inspected at full output size, then encoded as WebP quality 91 without repainting, cropping, or recoloring. All are 1672 × 941 landscape frames with open foreground platforms. Characters, enemies, loot and containers remain separate runtime objects. No new enemy sprites are included in this iteration.

| Runtime stem | Visual brief |
|---|---|
| ruins_act2 | Subterranean aqueduct, monumental stone arches, turquoise water, bronze rune conduits and wet empty terrace. |
| forest_act2 | Enormous living root labyrinth, jade moss, amber sap, mist and a clear forest floor. |
| sanctum_act2 | Moonlit celestial archive, book galleries integrated into marble architecture, astronomical rings and empty floor. |
| ruins_act3 | Broken obsidian citadel over molten-gold chasms, ember haze and intact dark foreground terrace. |
| forest_act3 | Crystalline silver forest on floating islands, violet cloud sea, aurora and pale empty island platform. |
| sanctum_act3 | Shattered observatory over an eclipsed cosmic abyss, tilted celestial rings and obsidian-silver platform. |

Each generation explicitly requested original hand-painted elemental-fantasy art, no people, monsters, chests, containers, loot, text, UI or modern weapons. Source filenames, dimensions, sizes and SHA256 values are recorded in `SCENERY_V240.json`. Combined encoded scenery size is 3,324,866 bytes.

## Original short battle sounds

`assets/audio/battle/` contains 13 independent short effects. No external sample or third-party recording was used. These are synthesized effects, not newly licensed music and not replacements for the user's rarity reveal clips.

- `slash`: a short filtered-noise sweep with a descending metallic partial.
- `blunt`: low descending impact and softened noise.
- `fire`: low crackling burst.
- `water`: rippling tone and softened fluid noise.
- `ice`: brief high crystal partials and transient.
- `thunder`: broken electrical noise and low transient.
- `wind`: soft bell-shaped filtered-noise sweep.
- `heal`: short ascending harmonic chime.
- `shield_cast`: rising resonant tone and upper partials.
- `shield_hit`: short damped resonant impact.
- `shield_break`: descending brittle noise/partial burst.
- `critical`: fast impact accent.
- `ultimate`: short rising layered accent, for one cast onset rather than every target.

Waveforms use deterministic seeded noise (24011), sine partials, attack/decay envelopes and end tapers, converted to mono Ogg Vorbis at 44.1 kHz. All runtime clips are shorter than 0.8 seconds. Decoded PCM values are finite, peak amplitude is at most 0.501, and no clipping is present. Exact durations, peaks, RMS, file sizes and SHA256 values are in `BATTLE_AUDIO_V240.json`.

Suggested integration: keep existing effects volume with an additional attenuation, bounded voice count and cooldown at 4× speed; use one sound per relevant action/event rather than every target. Existing five BGM tracks and user reveal MP3s are untouched; search remains silent. Runtime policy is owned by the main battle implementation.

## Verification limits

All six images were visually inspected. `tests/test_v240_media_assets.gd` passed 63 checks for imported textures, resolution, uniqueness, audio resource type, brief duration and disabled looping. Import completed without errors. Source creation and numerical decoding do not constitute subjective headphone listening; that has not been verified.
