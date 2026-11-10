# Thunder avatar framing and minification review

Baseline: f94a243b28d19f48943f7c42a00137028819a375 (Android 2.9.2).

Raisa and Vika's upper-body composition anchors now center their torso within the decorative aura in party cards, growth cards and traveler archive previews. Their face crops remain unchanged. Eve's composition and all original PNG bytes remain unchanged.

The three 1024×1536 illustrations now import mipmaps and explicitly use linear mipmap filtering in their portrait controls. This resolves the severe minification aliasing on Eve's fine umbrella, lace and hair details that made the alpha edges look fragmented. An image-generation cleanup candidate was evaluated and discarded; the released 2.9.2 artwork, including Eve's corrected umbrella hand, is retained byte-for-byte.

Actual Godot 4.6.3 OpenGL/llvmpipe rendering at 960×540 and 1440×810 covers party, growth and traveler archive for all three characters. The final screenshots have resolution prefixes. Earlier baseline screenshots are in before/. The native game's character collection view is titled 角色养成, and the summon preview is 旅者档案; the legacy web frontend called its entry 角色图鉴.

Validation: final renderer test 113 checks, zero failures; character avatars 141 checks, zero failures; thunder art review 42 checks, zero failures; thunder visuals including battle form/action restoration 134 checks, zero failures. Original-art verifier passes all 13 manifest hashes and alpha metadata. git diff --check passes. Full repository aggregate and Android build were not run in this scoped avatar task.

Reproduce rendered checks with a graphical display: bash tests/run_thunder_avatar_v293.sh from the godot directory. Headless structural coverage: godot --headless --path . --script tests/test_thunder_avatar_framing_v293.gd -- --test-session --mobile-ui.
