# Character summon scores

The user selected audition files 1 and 3: Vika uses **Cipher**, Eve uses
**Ascending the Vale**, both by Kevin MacLeod under CC BY 4.0. Raisa retains
the existing `content_v290/thunder_summon.ogg` (**Wasteland Overdrive**).

The two new assets preserve the full chosen recordings and original tempo.
They repeat the whole piece from zero, including the natural ending; this is
not a claim of a musically seamless bar loop. Only 5 ms edge fades, constant
gain alignment to -22 LUFS, and Ogg Vorbis conversion are applied.

`manifest.json` records source and delivered checksums, duration, loudness,
peak, sample-boundary checks and exact modifications. `LICENSES.txt` provides
required attribution, source and license links. The same credits appear in
the game's music credits screen. Source MP3s are intentionally kept outside
the game export; restore the exact filenames and hashes recorded in
`tools/audio/character_summon_sources.json` to rebuild.

From the Godot project directory:

```sh
python3 tools/audio/build_character_summon_audio.py --source-dir /path/to/previews
bash tests/run_character_summon_audio_v293.sh
```

The focused test exercises actual Godot stream routing, playback ownership,
crossfade pause, return to the prior player, the music toggle, user volume,
full decode and visible credits. The parent task controls packaging and
publication separately.
