# Dialogue illustration aspect ratios

The fifth chapter CG source images are 1536×1024. Dialogue previously applied center-cover to both ordinary scene backgrounds and complete illustrations. At a 2048×945 screen ratio, center-cover discarded the upper part of the CG and cropped character faces.

`main.gd::_render_dialogue()` now uses centered aspect-fit for CG illustrations identified by the existing `_dialogue_has_cg()` helper. This preserves the full source composition inside the viewport with the existing dark backdrop visible at its sides. Ordinary dialogue scenery retains center-cover; scene selection, dialogue text, buttons, audio, and portrait suppression retain their existing behavior.

`tests/test_dialogue_cg_layout_v290.gd` covers all nine current/legacy CG illustrations, two ordinary scenes, 864×540, 960×540, 2048×945, and 540×960 window sizes. It verifies the selected texture, full source rectangle containment, CG portrait suppression, ordinary full-bleed background mode, and Next/Skip visibility. Desktop and forced-mobile runs each pass 380 checks. The existing chapter-five integration test passes 886 checks after the change. Final logs are adjacent to this file.

Commands from the repository root, using writable temporary HOME/XDG directories:

    godot --headless --path godot --script res://tests/test_dialogue_cg_layout_v290.gd -- --test-session
    godot --headless --path godot --script res://tests/test_dialogue_cg_layout_v290.gd -- --test-session --mobile-ui
    godot --headless --path godot --script res://tests/test_chapter5_v290.gd -- --test-session

These checks are targeted engine regressions, with separate rendered screenshot review. They do not constitute Android-device or packaged-release validation.
