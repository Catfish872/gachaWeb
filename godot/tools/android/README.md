# Android runtime smoke

The Android workflow runs an API 35 x86_64 emulator with KVM,
ANGLE over SwiftShader software graphics and a 720 × 1280 display before exporting the ARM delivery APK. It requires
existing accepted Android SDK licenses. With the explicitly approved workflow
opt-in, it temporarily grants only the current UID read/write access to KVM on
a GitHub-hosted Linux runner, preserves the original ACL, and restores and
verifies it after stopping the emulator. Existing access needs no ACL change.
Local and self-hosted runs require existing KVM access. The script accepts no
new license agreements. Setup or cleanup failure fails the workflow and
preserves available logs.

`export_smoke.sh OUTPUT` creates an isolated project copy, changes only that
copy to x86_64, and installs an observation-only subclass of the production
main scene. The probe reports actual Android control positions and application
state. All tested interactions come from Android `adb shell input`, rather
than invoking game navigation methods. The regular ARM export excludes this
tools directory; its production scene and preset are unchanged.

`run_emulator.sh APK EVIDENCE` boots the emulator and runs `smoke_test.py`.
Checks cover portrait launch, menu dismissal by Android Back, touch navigation
to eight pages, horizontal page bounds, finger scrolling where necessary,
Back to home, landscape adaptation, and touch after background/resume. Android
and Godot runtime errors fail the test. Screenshots, logcat and window/activity
diagnostics are uploaded even on failure. Delivery APK publication is gated
on success.

This test exercises Android lifecycle, rendering and input on an emulator.
It does not establish physical-device frame rate, GPU compatibility, battery
use, every gameplay flow, or visual quality. Inspect the screenshot evidence
and retain physical-device validation for those claims. The x86_64 probe APK
is test-only and is never uploaded as a user delivery APK.

The emulator uses the supported `swangle` backend. The deprecated
`swiftshader_indirect` backend exposes legacy SwiftShader GLES uniform limits
that fail Godot's compatibility shaders. Before launch, the driver waits for
Android boot broadcasts and a stable configuration so first-boot resource
updates finish before the activity initializes. Application errors remain fatal.


## 搜打撤运行检查

临时模拟器 APK 的测试入口仅把随机种子固定为 2，使用正常生成的连通地图和战利品。所有操作均由真实 ADB 触摸执行；探针只记录游戏状态、画布平移和点击位置，不授予物品、不代替搜索、不伪造战斗胜利。正式 APK 使用原入口，不包含固定种子。

驱动检查仓库、出发、地图拖动不误入房间、点击相邻节点进入房间、点击场景中的独立容器、连续自动搜索和自动拾取。沿实际相连的非战斗房间找到普通容器，检查返回地图、重访房间与切换页面后背包和容器状态仍保留，并保存截图。如果自然遇到装不下，也检查再次拾取不丢物；背包满不是这个短流程的必达条件，完整满包原子性由核心和 UI 套件另行覆盖。地图和场景点击使用探针报告的真实绘制坐标，不调用游戏方法或控件信号。此前所有页面、横竖屏、返回键、滚动与后台恢复检查继续保留。

这些是模拟器驱动的覆盖目标；必须以对应构建的 CI 日志和截图判断是否实际通过，离线 Python 单元测试并不等于 Android 实测。战斗与撤离由真实 BattleModel 集成测试另行覆盖；模拟器也不能代替手机真机体验验收。

启动时还会执行一次 Android 下载桥接能力检查：读取应用上下文和包名，构造 DownloadManager 的请求与查询对象。该检查不开始下载、不打开安装器、不申请权限；实际下载与覆盖安装仍需单独验收。
