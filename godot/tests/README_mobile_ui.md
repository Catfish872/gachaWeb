# Mobile UI regression

`test_mobile_ui.gd` runs the actual Godot scene with mobile layout enabled. Window sizes are physical phone framebuffer dimensions: 1080 × 2400, 1080 × 1920, 720 × 1600, 2400 × 1080 and 1920 × 1080. The test checks the resulting logical viewport, with a 360-unit short edge, rather than treating a tiny desktop window as a phone. At 1080 pixels on the short edge this models a 360 dp, 3× phone; at 720 pixels it models a 360 dp, 2× phone. Physical hardware density and Android font/display-scale settings require separate device acceptance.

From the Godot project directory, run:

```sh
mkdir -p /tmp/voidrift-mobile/{data,config,cache}
XDG_DATA_HOME=/tmp/voidrift-mobile/data \
XDG_CONFIG_HOME=/tmp/voidrift-mobile/config \
XDG_CACHE_HOME=/tmp/voidrift-mobile/cache \
godot --headless --path . --script res://tests/test_mobile_ui.gd -- --test-session --mobile-ui
```

The isolated test session keeps gameplay progress in memory. The test exits with status 1 for failed assertions. A successful run also has to be free of `SCRIPT ERROR` and `ERROR:` log entries.

The suite measures all nine page layouts, character-art aspect modes, usable scroll viewport height and 48-unit fixed navigation targets. Synthetic `InputEventScreenTouch` and `InputEventScreenDrag` events enter the actual viewport event path, starting on scene artwork and clickable party portraits. They verify scrolling and cancellation of card activation while dragging. Synthetic mouse press, motion and release events separately exercise Godot's pointer hit testing for card taps, drag cancellation, opening the navigation menu, scrolling the menu and selecting its final destination. The test uses dispatched input rather than emitting button signals for these interaction checks.

Android Back is simulated with Godot's `NOTIFICATION_WM_GO_BACK_REQUEST`, and Escape is dispatched as a keyboard event. Tests cover page history, confirmation dismissal, interrupted prebattle dialogue and retreat confirmation that preserves the active battle when dismissed. An open navigation modal is rotated between portrait and landscape and remains within the viewport and dismissible.

## Acceptance boundary

These checks run in Godot 4.6.3 on Linux with synthetic input. They establish responsive layout and application-level event handling. Actual Android packaging, Android-to-Godot event translation, touch-to-mouse emulation ordering, system back gestures, screen cutouts/insets, display scaling, keyboard interaction, background/resume, installation and GPU rendering belong to Android emulator/device acceptance. A native Linux GUI visual review is complementary evidence for appearance. The phone release should be labeled according to the Android acceptance evidence actually obtained.

For real Android acceptance, install the candidate APK and record Android version, framebuffer size, density, orientation and app version. Swipe starting directly over the home image and party portraits, tap a portrait once, reach the final navigation destination, rotate with a modal open, cancel prebattle dialogue with system Back, and dismiss retreat confirmation while preserving the battle. Verify status/navigation-bar and cutout clearance, readable controls and full character artwork. Capture screenshots and the device log for that same APK.
