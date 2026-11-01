# Android lifecycle renderer candidate — 2026-11-01

## Confirmed observations

CI 41267453005 passed startup, all menu pages, extraction map/scene-container input, inventory preservation and landscape; the third background return stopped producing frames with EGL_BAD_SURFACE. This is a rendering failure, not a relaxed test timeout.

Official `platform/android/java/lib/src/main/java/org/godotengine/godot/gl/GLSurfaceView.java` was downloaded for tags `4.6.3-stable`, `4.7.2-stable`, and `master`. All three files have SHA256 `15d56bda1cf68e72bb3b48f8e2b0cd6a57dfab9832a674a6f2b4ce82b2f44dbb`. Their bad-surface recovery logic is identical. It marks the surface bad after failed buffer swap and only clears that flag when the rendering thread observes a missing surface. Asynchronous destroy/create callbacks can overwrite the missing-surface boolean before that observation. This is a source-supported race hypothesis consistent with the captured failure, not a proven instrumented trace of every native state.


## Candidate

Use Godot's supported Mobile renderer on mobile platforms; desktop remains Compatibility. Keep the documented OpenGL fallback enabled. No gameplay state reset, activity recreation, native patch, lifecycle-test removal or error suppression.

The isolated test APK reports actual RenderingServer method, driver and adapter. The Android smoke test writes `renderer.json` and requires `mobile` + `vulkan`, preventing a silent GL fallback from being mistaken for validation of this candidate. All existing input/landscape/background checks remain required.

Local checks: official Godot 4.6.3 clean headless import and direct runtime-probe parse passed; Android smoke unit tests 33/33. Actual Android success remains pending CI; this document is not release approval.

## Compatibility limits

Godot's fallback is documented but pinned 4.6.3 lacks the Android Vulkan-initialization ordering fix in PR #114922. Official 4.7.2 contains that fix; neither version fixes the GL lost-edge code. Thus this candidate avoids the failing GL lifecycle path on Vulkan-capable devices, not a claim of universal old-device safety. Play Store device filtering with Mobile is separately discussed in issue #111729; this project delivers a direct APK, not an AAB through Play Store.

## Primary sources

- https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/gl/GLSurfaceView.java
- https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/gl/GLSurfaceView.java
- https://github.com/godotengine/godot/pull/114922
- https://github.com/godotengine/godot/issues/111729
- https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html
- https://docs.godotengine.org/en/4.4/classes/class_renderingserver.html

## CI16 result and next supported candidate

CI16 `41268548502` did select Vulkan 1.3 Mobile / SwiftShader Device (Subzero), but failed startup with QueuePresentKHR error 5 immediately following Swappy startup. Official issue https://github.com/godotengine/godot/issues/121035 reports that exact emulator failure for 4.6.3; its fix targets 4.8 (https://github.com/godotengine/godot/pull/121701).

The next candidate sets documented `display/window/frame_pacing/android/enable_frame_pacing=false` in the shared production project. This routes presentation through ordinary Vulkan QueuePresentKHR instead of the optional Swappy pacer; vsync and all errors/lifecycle tests remain enabled. The production build and test build have the same rendering setting. Local clean headless import passes. Actual Android outcome pending.

## CI18 verified result

CI18 run `41269031780` on commit `259eaed52f04516028df04636928a1f2e1de9466` completed the native Android smoke suite successfully. Independent QA decoded 338 complete probe frames. `renderer.json` confirms Mobile / Vulkan / SwiftShader Device (Subzero), and all three required background cases (`rapid`, `settled`, `rapid_again`) passed. Fresh home frames 333–338 follow the third resume; the third-resume menu screenshot renders correctly. The extracted backpack screenshot contains the two normally generated items and intact grid. The log contains no EGL_BAD_SURFACE, QueuePresentKHR failure, SwappyDisplayManager startup, or script errors. Summaries are preserved in `validation/android-ci18/`.

This result validates the shared Vulkan plus disabled Android Swappy configuration on the API 35 x86_64 emulator. The OpenGL fallback and physical-device GPU/performance limits stated above remain separate validation boundaries.


## Final released CI20 confirmation

CI20 `41270718020`, commit `b63cefa5066d162c24ba6fd3c768288714aa7208`, passed all jobs and published `android-v2.1.0`. Independent QA decoded 335 complete native frames and confirmed actual Mobile/Vulkan/SwiftShader plus all three background-resume cases. The final rapid-resume menu screenshot renders correctly; the native log contains none of the prior EGL_BAD_SURFACE or QueuePresentKHR errors. Shared production settings retain Vulkan and disabled Android Swappy.

Production job `124744045360` additionally validated the canonical binary Android manifest, 16 KB native-library alignment, fixed-key signing and certificate check, and APK package/version/SDK/permissions/ARM contents. Fourteen manifest fixtures passed, including safe ZIP entry copying through `copy.copy(ZipInfo)`. Final APK SHA256 is `cf1157c3b62994892a32ea75d24de5f61a09ed5948bcbc1698cf0225bbdd36f3` (98,934,769 bytes). Evidence summaries and build excerpts are in `validation/android-ci20/`.

This confirms the released Vulkan emulator path. Physical S23 testing and an actual in-app cross-version download/install cycle remain untested; GL fallback compatibility retains the limits above. Existing-release idempotent skip is fixture-tested, not yet verified through a real repeated release run.
