# Android 正式更新渠道

游戏沿用 `godot/android-release-v2` 开发分支，日常安装统一使用 GitHub Releases 中的正式 `universal.apk`。内部模拟器仍使用隔离的测试包验证界面和运行状态；这些测试包用于构建检查，不作为用户的日常更新渠道。

## 发布与版本

当前源版本为 **2.1.0 / 20100**。唯一版本元数据在 `data/version.json`，两个 Android 导出预设同步。版本号规则为 `major*10000 + minor*100 + patch`，minor 和 patch 各为 0–99。每次发布递增版本号，正式标签为 `android-v` 加版本名。

推送原分支后，`test-debug` 执行完整游戏、更新、手机布局和 Android 模拟器检查。`signed-release` 依赖同一次运行的验证结果，并检查检出提交等于工作流提交、版本与标签一致。固定签名 APK 通过包名、版本、签名指纹、权限、资源与架构校验后，创建草稿 Release、上传 APK 和 SHA256SUMS，最后转为正式发布。同名 Release 保持不可覆盖。

正式发布可以通过工作流的 `publish=true` 手动触发，或精确版本标签触发。设置仓库变量 `ANDROID_RELEASE_ENABLED=true` 后，原分支推送会自动进入正式发布阶段。未启用时，普通推送仍独立完成检查，保留继续开发与验证的能力。

## 固定签名配置

正式包名固定为 `org.catfish872.voidrift`。持续覆盖升级依赖相同包名、相同长期签名与递增版本号。签名缺失或指纹不符时，正式导出停止，保持原发布可用。

长期签名的生成、向 GitHub 传输和保存须经所有者明确授权。私钥、密码和密钥文件仅进入安全备份及该仓库 GitHub Actions 的加密 Secret，避免进入聊天、代码、构建产物或公开附件。

受保护环境 `android-release` 使用以下字段：

- Secret `ANDROID_KEYSTORE_BASE64`：长期签名 keystore 的 Base64 内容。
- Secret `ANDROID_KEY_ALIAS`：签名别名。
- Secret `ANDROID_KEY_PASSWORD`：keystore 与密钥共用密码，符合 Godot 导出约束。
- Variable `ANDROID_SIGNING_CERT_SHA256`：公开签名证书 SHA256 指纹。

现有代码和配置完成不等于密钥已经建立或正式 Release 已发布。以实际工作流结果和 Releases 附件为交付依据。

## 手机内更新

每次启动等待 3 秒后检查一次 GitHub 正式版本。检查在后台进行，战斗期间延后显示更新提示；离线时继续游玩。设置页可关闭自动检查和 Wi-Fi 自动下载，偏好保存在本机。

Android 使用 Godot 4.6 内置 `AndroidRuntime` 与 `JavaClassWrapper` 访问系统 `DownloadManager`。下载限定该仓库 Release 的 `universal.apk`，在 Wi-Fi 下保存到应用外部私有目录，由系统管理断线、后台与进度；游戏重启后恢复查询同一下载记录。界面提供进度、取消和重试。桌面仍可通过发布页下载。

下载结束后按 GitHub Release asset 的 SHA256 `digest` 和文件大小校验；安装前再次校验。缺少有效摘要、大小异常、内容不符或下载失败时停止安装。下载包上限为 512 MiB。旧版更新包在新版本启动后清理。

游戏声明 `REQUEST_INSTALL_PACKAGES`，用于打开 Android 系统安装器。首次使用时，所有者需要在系统设置中允许本应用安装更新，再返回游戏点击安装；游戏提供打开该设置的按钮，由用户决定设置内容。每次覆盖安装仍由 Android 显示确认界面。下载、摘要校验和更新发现由游戏处理，系统负责安装与签名匹配。该渠道面向 GitHub 直接分发，未声明符合 Google Play 的自更新政策。

## 从旧测试包迁移

旧测试包名为 `org.catfish872.voidrift.debug`，正式包与它可以并存。旧测试包采用临时签名，正式包采用固定签名，因此首次切换需要一次存档迁移。先保留旧包，在旧包导出存档后导入正式包；确认角色、装备、资源与进度后再自行处理旧包。正式包后续更新保持包名和签名一致，通常直接覆盖安装并保留本地数据。

本版导入、导出使用 Android 原生文件选择器。Storage Access Framework 返回的 `content://` 导出采用直接写入后重新读取校验，内部存档仍采用原子替换；导入经完整数据校验后提交，失败保留原档。旧版本自身的导出能力需要在该已安装版本实际确认，不能由本版实现推定。游戏不会在迁移时自动卸载旧包。

## 验证范围

Godot 与 Android 模板固定 4.6.3，校验官方 SHA512；JDK 17，Android build-tools 35.0.1。APK 校验 ARMv7/ARM64、包名、版本、SDK、联网和系统安装权限、正式证书指纹、禁止密钥及开发材料混入。测试会话跳过启动联网。

更新的离线测试覆盖版本比较、来源限制、摘要解析、持久化下载记录校验、启动去重、失败重试入口、下载/安装/授权状态显示和手机布局。Android 运行探针检查内置桥、系统下载服务和只读查询。实际发布后的下载、校验、系统授权与跨版本覆盖安装仍需对应运行结果，离线测试或桥探测本身不代表完整更新链路通过。

官方实现依据：

- https://docs.godotengine.org/en/4.6/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.html
- https://raw.githubusercontent.com/godotengine/godot/4.6-stable/platform/android/java_class_wrapper.cpp
- https://developer.android.com/reference/android/app/DownloadManager
- https://developer.android.com/reference/android/content/Intent#ACTION_INSTALL_PACKAGE
- https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html
- https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
