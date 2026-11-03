# Licensed wind chapter music, 2026-11-03

This change uses four external recordings approved by the user after audition. These are licensed third-party music, not new original compositions by the game. Enchanted Journey is excluded. The existing windpass_core boss music and all sound effects remain unchanged.

## Attribution and alterations

### Bright Wish · 缇娅卡池

Kevin MacLeod (incompetech.com)

Source: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100377

License: CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/

改动：响度对齐、末尾 5 毫秒柔化、Ogg 转码；保留整曲自然落音。

### Happy moments 1.4 · 露弥卡池

Centurion_of_war

Source: https://opengameart.org/content/happy-moments

License: CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/

改动：响度对齐、保留引子并从 25.6 秒循环、末尾 20 毫秒接缝修整、Ogg 转码。

### Happy Flutes · 风谷

Tomasz Kucza / magory.games

Source: https://opengameart.org/content/happy-flutes-for-fantasy-setting

License: CC BY 3.0（OpenGameArt 文件许可） — https://creativecommons.org/licenses/by/3.0/

改动：响度对齐、末尾 5 毫秒柔化、Ogg 转码；保留整曲。

采样：Improvisation with Sopranino recorder，piermic，CC0 1.0
https://freesound.org/people/piermic/sounds/324085/
https://creativecommons.org/publicdomain/zero/1.0/

### The World At Your Door · 风廊

Composed by Jonathan Shaw (www.jshaw.co.uk)

Source: https://opengameart.org/content/the-world-at-your-door-rpg-orchestral-essentials-overworld-music

License: CC BY 3.0 — https://creativecommons.org/licenses/by/3.0/

改动：截取原曲第二个完整循环、末尾 20 毫秒接缝修整、响度对齐及 Ogg 转码。

## Specific-file license record

Happy moments uses the original piano1.4.ogg, not the MP3 preview. The original piano1.3.ogg was retained for comparison only and is not shipped. The OpenGameArt work page identifies Centurion_of_war and CC0. Source page direct retrieval returned HTTP 403 in this verification environment; its indexed primary-source record and the parent's research independently provided the work and license information.

Bright Wish uses Kevin MacLeod's official MP3. The current official work page identifies CC BY 4.0, so an older third-party CC BY 3.0 description was not used.

Happy Flutes uses the OpenGameArt tkucza-happyflutes.mp3 under that work page's CC BY 3.0, confirmed by the parent's source research. Direct work-page retrieval returned HTTP 403 in this environment. The author's music page (https://magory.net/music-assets/) separately offers all listed files under CC BY 4.0; its Happy Flutes MP3 has the exact same SHA256 as the OpenGameArt file: 40cb712d9b0c1b6ba8c02338f845790252ea19214c3d0777e221a0024b116b7d. This is recorded as two license notices for byte-identical content, not as an automatic upgrade from 3.0. The shipped copy keeps the OpenGameArt 3.0 notice and credits Tomasz Kucza / magory.games plus piermic's CC0 recorder source. The Freesound source page was directly checked.

The World At Your Door uses the audio in the author's original OpenGameArt ZIP. The work page identifies InspectorJ / Jonathan Shaw, CC BY 3.0, and requires the title, composer and www.jshaw.co.uk credit. The original ZIP also includes the author's 2019 EULA and README, retained in the local source archive. The EULA states downloading/using constitutes acceptance and permits credited commercial and non-commercial game use. Its current-version URL is https://www.jshaw.co.uk/RPG-Orchestral-Essentials-eula (not retrievable through the web tool during this pass). No click-through acceptance was performed. No extra restrictions are imposed on the CC-licensed copies by this project.

## Reproduction and playback

Run `python godot/tools/audio/build_licensed_wind_audio.py --root LOCAL_PREP_DIRECTORY`, where `sources/` contains the originals listed in sources.json. Python 3, numpy and ffmpeg 7.1.5 with libvorbis are required. Exact source SHA256, output SHA256, sample counts and transformation details appear in manifest.json and the local TECHNICAL_VERIFICATION.json. Downloads and retained PDFs stay local, outside the game repository delivery assets.

All four files are Ogg Vorbis quality 6, stereo 44100 Hz. They are matched by constant gain to approximately -22 LUFS, without a compressor or limiter. The player's existing master volume and fades remain effective. No pitch, melody, meter or tempo changes were made. Decoding MP3 to float before gain avoids integer clipping from MP3 overshoot; transcoding does not upgrade original MP3 fidelity.

Bright Wish is 40.881633 seconds and Happy Flutes 45.400612 seconds. These repeat the full composition with its natural cadence/pause, not a claim of a musically seamless measure loop. A 5 ms terminal fade suppresses numerical edge discontinuity without removing notes.

Happy moments 1.4 remains 76.8 seconds; initial playback starts at zero and subsequent playback wraps to 25.6 seconds. The last 20 ms blends to the existing audio just before the loop-start point. The corresponding AudioStreamOggVorbis.loop_offset must be set explicitly by the player.

The World At Your Door uses source frames 3293392 through 6586783 at 44100 Hz, a 74.680091 second authored cycle. Four separate source windows correlate with their repeated counterparts at 0.992–0.998. The final 20 ms blends to the source immediately before the loop start to reduce the boundary discontinuity. The author's unused ending/reverb tail is not played between loops.

## Verification limits

Checks cover successful decode, exact frame length, integrated loudness, true peak, sample-boundary continuity, resource mapping and untouched prior assets. No game run or subjective audition was performed. Technical seam checks do not prove perceptually seamless rhythm or approved timbre. Four local 12-second loop-join previews are provided for human audition, with each join at 6 seconds. No claim of subjective listening approval is made.

The existing Settings → 音乐鸣谢 screen contains the four source credits, license URLs, transformations and sample attribution. Documentation alone is not relied on for release attribution. Keep the original CC0 and lantern credits as well.
