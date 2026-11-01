# Extraction UI/audio reference review — 2026-11-01

## Observed visual evidence

The following were inspected as actual pixels in the cloud browser, not inferred from search snippets.

- Official Delta Force mobile stash: https://web.df.garena.com/03_news/news_banner/SMP/202602_NewToOperations/2.png (linked by https://deltaforce.garena.com/en/news/system/RMDWVM). Personal equipment and carried inventory occupy the left pane; storage occupies the right. Each pane has an independent lower action strip. Currency stays in the upper chrome. Item art dominates each slot, with secondary labels subordinate to art. Category icons form a narrow rail. This supports bounded panes with internal scrolling rather than one long page.
- Official mobile loadout: https://web.df.garena.com/03_news/news_banner/SMP/202602_NewToOperations/8.png. Weapon slots, armor slots and supplies each have separate boxes. Central character art separates visual identity from the actionable gear region. Confirm is anchored near the lower-right edge.
- Actual public PC extraction clip: https://www.douyin.com/video/7686455118384036017. At 00:55 an interactable safe has a clear outline in the world. At 01:12 the container's header says it is searching, while the current cell area shows diagonal hatching and a magnifying-glass mark. At 01:14 a one-by-two water-pipe item is revealed in that same location and remains visible; the header returns to the container name. This is an edited/zoomed clip and does not establish exact real-time reveal duration.
- Actual public inventory/search clip tagged by its uploader as mobile (platform not independently authenticated): https://www.douyin.com/video/7600323642626873158. At 00:03 the personal pockets/backpack remain visible on the left while the searched inventory is on the right; an already revealed gold picture coexists with the hatched searching region. At 00:11 selected equipment opens a local right-side detail panel with image, price, weight and discard/equip buttons while the personal inventory stays visible. This supplies direct evidence for simultaneous self/target inventory and contextual details, but the uploader tag alone does not prove the input device or client build.

## Sources attempted but not visually verified

YouTube CweWTGki32A and the official guide's linked 9iSjVZjchoE at 03:18 loaded titles/subtitles but remained black/buffering. Bilibili BV1bDpXzBEea explicitly reported media unavailable. No claims of watching those videos are made. Arena Breakout's official tutorial page and a secondary inventory guide were found, but this review does not claim its UI was visually inspected. The successful Douyin clips were muted during browser observation; their audio was not auditioned by the reviewer.

## Current implementation causes found before rewrite

`extraction_view.gd` reveals an item, immediately removes it through automatic pickup, and only then rebuilds the container modal. The automatic-pickup path therefore never draws the newly found item in the container. Every item also rebuilds the modal, waits 1.05 seconds to search, and adds 0.28/0.7/1.8 seconds after common/purple/gold-or-red results. This combines lost context with unnecessary stop-start pacing.

`inventory_grid.gd` previously computed icon size as the smaller of item width minus 8 and item height minus 28, then only drew an icon when at least 18 pixels. A one-cell, 44-pixel-high item gets 16 pixels and its image is suppressed. This is a direct cause of missing images even when textures exist.

Audio was driven by one AudioStreamPlayer. Every item restarted the full search clip from zero, then replaced that same player with a reward clip. Search, reward and future background audio require separate lifetimes.

## Interaction requirements derived for this game

Keep the container and player's bag visible together. Use stable panels and update the affected item cells instead of reconstructing the whole window. Show search progress inside the active item's footprint. Reveal image, short name, value and rarity together, then allow a brief visible hold and transfer animation before auto-pickup. Keep a small recent-find receipt so a fast auto-pickup remains understandable. Next-item search can proceed while a prior reward animation or sound finishes. Full-bag items stay visible and offer use/equip directly. Selecting a revealed item should not reset or cancel unrelated search progress.

Use touch-sized controls with icon + short caption. Buying, selling, moving and equipping should be adjacent to the selected object or in its pane's fixed action strip. Preserve scroll positions when inspecting, selecting or returning. Long-press enters batch selection; a drag over items adds each crossed item once. Scrolling and selecting must have explicit, separate gesture ownership. Selection totals and the action button remain on screen.

## Audio deliverables and provenance

All five user-supplied MP3 files remain byte-identical. `search_loop.ogg` is a new derived 0.30-second sample from original search.mp3 at 0.42–0.72 seconds, filtered and tapered. The original search clip shares long PCM regions with red.mp3: matching 0.2-second red windows at 0.4–1.4 seconds align to search at +0.7627 seconds with correlation about 0.97–0.995. This proves shared audio content, not the subjective label of an individual sound. The selected short loop avoids the shared strong onset and later region; actual headphone listening is still required to confirm perceived quality.

Two new original 32-second procedural music loops (`ruins_ambient.ogg`, `ruins_battle.ogg`) use sparse minor-key pads and soft bell notes, with a light pulse in the battle variant. Five original short UI effects (`tap`, `back`, `equip`, `use`, `coin`) are included. All are generated by `tools/audio/build_soundscape.py` from oscillators; no third-party music or game sound was copied. This is a restrained original soundscape, not an externally commissioned orchestral score.

Latest user instruction supersedes the search-loop proposal: searching is silent and the 10-second clip is unused. The derived search loop is a disabled candidate, not a runtime dependency. Keep the supplied rarity clips at reveal time. Separate music, reward and UI players; crossfade scene music and avoid replaying stale rewards after background resume. Music may briefly duck around a rarity reveal, not merely because searching is active. Original procedural 32-second music is a prototype candidate, not the final musical direction. Three longer CC0 tracks have now been sourced separately; see AUDIO_LICENSES.md. Player gains for normalized licensed music begin at -8 dB ambient and -10 dB battle, reward clips -10 dB, UI tap/back -23 dB and other UI -19 dB; these are technical starting points pending actual listening, not listening-validated mastering.

`audio-v220-analysis.json` records decode, peak/RMS and loop-boundary checks. These validate technical integrity, not subjective sound quality or on-device loudness. Browser video audio and actual phone speakers were not auditioned.
