# Chapter responsive layout validation

The desktop chapter selector used a single HBox. With five full chapter names, its minimum width exceeded the 864×540 viewport and widened both the selector and the details below it. The chapter selector now uses the existing HFlow container at every width. It wraps complete, 44-point-high buttons while the existing stage list, detail scrolling, fixed actions, and selection behavior stay intact.

`tests/test_story_responsive_v290.gd` exercises 800×540, 844×390, 864×540, 960×540, 1168×730, and 2048×945 physical windows. It checks every chapter, first and last stages, actual mouse input, stage scroll preservation, detail text horizontal containment, action/replay visibility, repeated chapter clicks and story re-entry. The viewport scaling code maps mobile 1168×730 to 864×540 logical coordinates and mobile 2048×945 to 1170×539.

Godot 4.6.3 headless results: desktop mode 1,142 checks passed; forced mobile mode 1,392 checks passed. Existing `test_story_button_delta_v285.gd` passed 28 checks in mobile mode, including actual touch-driven detail scrolling with fixed action position. The initial narrow-window reproduction failed six of 120 geometry assertions; all 120 passed after the container change. Final logs are adjacent to this file.

Commands from the project root, with HOME, XDG_DATA_HOME and XDG_CACHE_HOME set to writable temporary directories:

    godot --headless --path godot --script res://tests/test_story_responsive_v290.gd -- --test-session
    godot --headless --path godot --script res://tests/test_story_responsive_v290.gd -- --test-session --mobile-ui
    godot --headless --path godot --script res://tests/test_story_button_delta_v285.gd -- --test-session --mobile-ui

These are targeted layout regressions. They do not constitute Android-device testing or a packaged-release test. GUI screenshot review is tracked separately by the desktop QA worker.
