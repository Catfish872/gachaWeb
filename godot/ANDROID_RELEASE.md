# Android 构建与 GitHub 更新

## 流程与当前边界

- `godot/android-release-v2` 分支或主分支推送：自动测试，生成 CI 测试 APK，保留在 Actions 构建产物中14天。
- `android-v2.0.0` 这类版本标签：测试通过后使用受保护环境中的正式签名，验证包名/版本/签名指纹，再将 `universal.apk` 和校验文件发布到 Releases。
- 当前尚未配置正式签名，故正式发布会拒绝继续；不会用临时测试密钥冒充正式发布。
- 每次启动等待 3 秒后自动检查一次 GitHub 正式版本；检查在后台进行。发现更新时显示「查看更新」入口，战斗中延后显示，保持当前操作。离线或超时仍可继续游戏。
- 「旅程档案→版本与更新」可关闭自动检查并保存偏好，随时手动检查、阅读发布说明、直接用手机浏览器下载 APK。下载完成后由 Android 提示用户确认安装，无需电脑传文件。测试会话（`--test-session`）跳过启动联网。
- 自动检查仅查询公共仓库，实际下载由用户点击触发。正式发布仍须先配置固定的长期签名并发布正式 APK，才能实现保留存档的覆盖升级。
- Android 系统负责安装确认。相同包名、相同签名、递增版本号才能覆盖升级。更新前建议导出存档。

## 正式签名只由所有者安全配置

请在自己的电脑生成并离线备份长期签名密钥，保留密钥密码与 keystore 密码一致（Godot要求）。不要发送到聊天、提交Git或放进公开附件。
在 GitHub 的 Settings → Environments 创建 `android-release`，设置必要的发布审批与允许的版本标签，再通过安全设置输入：

- Secrets: `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`
- Environment variable: `ANDROID_SIGNING_CERT_SHA256`（正式证书的公开 SHA256 指纹）

签名步骤仅使用这些环境变量，不打印密钥。证书指纹不符、缺少密钥、版本不一致、出现调试签名均拒绝发布。已经存在的同名 Release 不会覆盖。生成/配置密钥与正式发布需要所有者另外完成或明确授权；本次没有处理真实凭据。

## 版本规则

唯一版本元数据在 `data/version.json`，两个 Android 导出预设必须同步：
`versionCode = major*10000 + minor*100 + patch`，minor/patch 均为0–99。
首版2.0.0对应20000；后续2.0.1对应20001。正式标签必须为 `android-v` 加相同版本名。
正式包名永久固定 `org.catfish872.voidrift`。CI 包为 `org.catfish872.voidrift.debug`，可以与正式包并存。

CI 每次使用临时测试签名，因此不同 CI APK 不保证直接覆盖安装；不要在测试包积累唯一存档。正式包签名必须长期不变，不能每次生成新密钥。

## 工具链与验证

Godot引擎和模板固定4.6.3，校验官方SHA512；JDK17，Android build-tools35.0.1，预制模板的minSDK24/targetSDK36。模板默认SDK会在APK导出后用aapt实际检查。
脚本验证ARMv7+ARM64、版本、联网权限、签名、禁止开发资料/密钥混入。单机游戏不上传存档；检查更新只读取指定公共仓库，应用不内置GitHub令牌。

首次 CI 构建成功只证明产物可以构建并通过静态检查，不替代 Android 真机安装、触控、后台恢复及旧版本覆盖升级测试。

官方参考：
- https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html
- https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
- https://developer.android.com/google/play/app-updates
