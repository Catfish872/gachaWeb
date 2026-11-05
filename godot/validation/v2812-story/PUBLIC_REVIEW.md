# Chapter 4 focused validation

The approved 294 text entries across 28 scenes passed 118 structural checks and 4709 headless layout checks at 960×540 and 1280×720. Five representative scenes passed 110 actual desktop OpenGL rendering and input checks at both sizes. Continue, Skip, final-line completion and repeated closure were covered. All ten local screenshots were visually inspected and are excluded from this public record.

The final version-bound summary is in `../v2812-release-focused/release-evidence.json`. Desktop rendering does not establish Android hardware validation. The final renderer reported an unsupported V-Sync setting warning and no script errors.

Reproduce layout checks with `godot --headless --path godot --script tests/test_chapter4_copy_v2812.gd -- --test-session`. Run `godot --path godot --script tests/test_chapter4_render_v2812.gd -- --test-session` in a graphical session for rendering/input checks. Rendered captures are written to this directory.
