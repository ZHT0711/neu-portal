# 东大一号通 · NEUPortal

东北大学「一号通门户」（https://personal.neu.edu.cn/portal）的第三方多端客户端：Android 遵循 Material Design 3，iOS 使用 Apple 风格组件。
一套代码，同时构建 **Android / iOS / Windows / Web**。

> Android 使用 Material 3（Material You），iOS 使用 Cupertino 导航、搜索与设置控件；数据来自门户真实接口，另内置一份
> 2026-10-30 抓取的真实数据快照用于离线体验。

---

## ✨ 功能

| 模块 | 说明 |
| --- | --- |
| 🔐 统一身份认证 | 完整实现 NEU CAS 登录流程（RSA-PKCS1v15 加密 + 票据重定向），密码**仅在内存中使用，绝不存储** |
| 🎫 一次登录处处通行 | 登录时勾选「保持登录」（默认开）：凭证加密存入本机安全存储（Android Keystore / iOS Keychain），App 重启自动静默续登；打开任何系统时 WebView 注入会话 Cookie 走 SSO，CAS 会话过期还会自动填表重登——**点应用不再出现登录页** |
| 🏠 首页仪表盘 | 问候头部、数据条（数字滚动动画）、下一节课横幅、今日课程时间轴（进行中标记）、常用应用分页格、办事动态横滑卡、校园资讯（下拉刷新、错落入场动画） |
| 📅 课表 | **教务规范节次网格**（第1-2节…第9-10节，真实作息时间），课程块含周次与教室；**智能学期模型**：教学周 1-16 + 考试周 17-18、每门课有周次范围、国庆/元旦自动停课、当前时刻指示线；登录态拉取任意一周真实课表（含考试/活动）；**添加日程**：本机日程即时上格，登录态可一键打开门户官方日程页（免登录）做真实同步（含提醒/重复） |
| 🧭 服务大厅 | 全部校内应用（实时 41 个，含图标/分类/访问量）+ 专题服务 22 项；**智慧搜索**：门户热搜词（实时接口）+ 本地即时过滤 + 一键跳转智搜平台全校搜索（SSO 免登录） |
| 📝 学习任务 | 服务页进入，支持 CG 逐题评判、慕课普通课程及 SPOC 作业/测验、学习通作业及任务点进度与课程截止日期。按课程汇总，支持搜索和完成/过期筛选；Android/iOS 在平台网页完成登录后点击“同步”，结果保存在当前会话，部分失败保留已有数据 |
| 💳 校园卡 | 服务页进入，Android/iOS 在卡务网页认证后同步真实主钱包与补助余额、按月读取流水，支持前后月份切换。每次最多读取 10 页并提示截断；失败保留已读数据 |
| 📊 成绩 | 进入成绩页时读取教务数据，支持下拉刷新、Android/iOS 教务网页补充同步、全部学期数字分及五级制成绩、GPA/加权平均分/学分统计；部分学期失败时保留已有成绩并显示未读取学期，登录后的空状态与演示数据分别展示 |
| 🌐 打开网页 | **应用内 WebView v2**：自动注入 CAS 会话 Cookie，各业务系统 SSO 免登录直达；**返回智能分层**：系统返回键/侧滑手势优先退站点历史，SPA 标签页（如教务系统的页内标签）无历史时自动退出页面；**桌面版/手机版一键切换**（PC 页面不再挤成一团）；进度条、出错自动换协议重试、复制链接、系统浏览器兜底；CAS 会话过期自动填表重登 |
| 🔀 网络线路 | 默认自动探测，校内直连、校外经 WebVPN。登录、门户接口与服务网页共用线路，回到前台、刷新或打开服务时重新判断。「我的 → 网络线路」支持手动选择直连或 WebVPN，并保存选择 |
| 👤 我的 | 渐变个人卡、主题模式、Material You 动态取色、6 色主题色盘、登录/退出 |
| 📱 自适应 | 窄屏底部导航栏，宽屏（≥900px）侧边导航栏 |

## 🎨 设计

- Android：MD3 标准字阶、`ColorScheme.fromSeed`、tonal surface、80dp NavigationBar、ChoiceChip 与胶囊按钮
- iOS：通过 `real_liquid_glass` 接入原生 `UITabBar` / `UIGlassEffect`（iOS 26+），导航和搜索使用玻璃材质；旧版 iOS 使用系统模糊；保留分组背景、滑动分段控件和日期/时间滚轮
- 小屏与大字体：应用入口按屏宽分页、外观设置独立一行、登录/日程表单可在键盘上方滚动；课表保持最小可读宽度，可左右滑动
- 交互：首页快捷入口切换现有页签，保留搜索与滚动状态；再次点击当前底栏页签即可回顶（双击同样支持）；登录支持自动填充、行内错误和重复提交保护
- 辅助功能：主题色选中语义、完整应用名称朗读、减少动态效果设置、深色课程颜色适配
- 种子色取自门户 `site/info` 接口的 `theme_color`（`#3553A2`，东大蓝）
- 深浅色双主题；Android 12+ 支持跟随壁纸动态取色（`dynamic_color`）
- 全中文界面；触感反馈（切页/点课表/刷新）

Tab 在启动动画结束后的空闲帧逐页准备，切换保留搜索和滚动状态；主页面直接显示内容，避免重复的列表渐入和数字滚动。iOS 内容卡片使用不透明材质，模糊集中在导航层；悬浮胶囊和全宽底栏共用轻量选中态，并适配减少动态效果、高对比度和底部安全区。课表七列等宽，表头、节次和课程块共用行高。

设计依据：[Apple Liquid Glass 原则](https://developer.apple.com/videos/play/wwdc2025/219/)建议将玻璃留在导航层、避免层层叠加；[Flutter 性能建议](https://docs.flutter.dev/perf/best-practices)强调控制构建成本，减少不必要的透明度和合成效果。实际帧率仍需在物理设备的 profile/release 构建中测量；widget 测试和截图只验证布局、状态保留与交互。

## 🚀 构建与运行

环境：Flutter 3.47.8 / Dart 3.12.1+（本机 Flutter 位于 `D:\flutter`）+ 各平台工具链。iOS 原生液态玻璃需 Xcode 26+ / iOS 26 SDK 编译，运行时仍支持 iOS 15+。

```bash
# Web（最快的预览方式）
flutter build web --release
# 产物在 build/web，任意静态服务器即可，例如：
python -m http.server 8618 -d build/web

# Android APK
flutter build apk --release          # 产物 build/app/outputs/flutter-apk/app-release.apk
flutter build apk --split-per-abi    # 更小的单架构包

# iOS（需 macOS + Xcode）
flutter build ios --release

# Windows（需 Visual Studio C++ 桌面开发负载）
flutter build windows --release

# 开发调试
flutter run -d <device>
```

应用图标由 `flutter_launcher_icons` 从 `assets/icon/` 生成（改完图标重跑
`dart run flutter_launcher_icons` 即可）。Android 启动屏为品牌蓝纯色
（亮色 `#3553A2` / 暗色 `#111318`，见 `android/app/src/main/res/values*/`）。
iOS 原生启动屏使用随系统深浅色变化的背景与校徽着色；Flutter 启动层沿用当前主题表面色。

## 📱 没有 Mac 怎么编 iOS IPA？

仓库自带 GitHub Actions（`.github/workflows/build.yml`）：每次 push 到 main 会自动在
**GitHub 免费的 macOS 云跑机**上执行 `flutter build ios --release --no-codesign`，
并打包出**未签名 IPA**（Actions 页 → 对应 run → Artifacts 下载）。

也可从 [每夜版 Releases](https://github.com/ZHT0711/neu-portal/releases/tag/nightly)
下载 `dongda-yihaotong-nightly-ios.zip`，**先解压一层，取出 `.ipa`，再导入签名工具**。
裸 `.ipa` 仍保留供直接下载；不要把外层 ZIP 或下载错误页面改名为 `.ipa`。

若导入时报 `missingEndOfCentralDirectoryRecord`，表示工具未找到 ZIP 尾部目录记录，
应先检查下载是否完整，而非反复重签：删除不完整的下载，重新下载 ZIP，解压后导入其中的 IPA。
Release 的 `SHA256SUMS.txt` 列出各文件的 SHA-256；Windows 可用
`Get-FileHash .\dongda-yihaotong-nightly-unsigned.ipa -Algorithm SHA256` 核对。
也可在仓库中运行 `python tools/verify_ipa.py <文件路径>`，检查目录记录、全部文件 CRC、
应用元数据与 Flutter 可执行文件。CI 在打包和发布前均执行这项校验。

安装到 iPhone（任选其一）：

| 方式 | 签名 | 有效期 |
| --- | --- | --- |
| Sideloadly / AltStore（Windows 可用）+ 个人 Apple ID | 免费 | 7 天，到期重签 |
| 苹果开发者账号（$99/年）+ 证书 | 付费 | 1 年 |
| TrollStore（特定 iOS 版本） | 永久 | 永久 |

> **签名说明**：仓库内含个人自用的 `upload-keystore.jks` 与 `key.properties`
> （密码 neuPortal2026），保证本地与 CI 出的包签名一致、可互相覆盖安装。
> 若要公开分发请自行更换密钥（`keytool -genkeypair`）后重新提交。

> Android APK 同样有 CI（同一个 `build.yml`，Ubuntu 跑机），push 后自动出包。

## 🏗️ 架构

```
lib/
├── main.dart                 # 入口
├── app.dart                  # MaterialApp + 动态取色 + 状态注入
├── core/
│   ├── theme.dart            # Material 3 主题 / 课程色板 / 中文日期工具
│   ├── cas_crypto.dart       # CAS 密码 RSA-PKCS1v15 加密（纯 Dart BigInt 实现）
│   ├── portal_client.dart    # 门户 HTTP 客户端：手动重定向 + Cookie 罐 + 全部业务接口
│   ├── links.dart            # 打开链接统一入口（WebView / Custom Tabs 分流）
│   ├── app_state.dart        # 全局状态（会话/数据/外观设置，ChangeNotifier）
│   ├── models.dart           # 数据模型
│   └── demo_data.dart        # 真实数据快照（离线演示）
├── pages/                    # 登录 / 外壳 / 首页 / 课表 / 服务 / 成绩 / 我的 / 应用内浏览器
└── widgets/common.dart       # 通用组件（分组面板 / 入场动画 / 数字动画 / 磁贴）
```

- **登录模式**：CAS 登录成功后走门户实时接口（课表/应用/资讯/待办/余额），任一接口失败自动回退离线数据，校外无 VPN 也能用
- **离线模式**：不登录直接体验，内置真实快照
- 已知限制：成绩页为演示数据（教务系统独立 SSO，未提供开放接口）；Web 端受 CORS 限制实际运行在离线模式；校园卡余额门户端即返回 `***`

## 🔒 隐私与安全

- 密码默认只参与本次认证；若勾选「保持登录」，密码经系统级安全存储（Keystore / Keychain）加密保存在本机，仅用于静默续登与 WebView 内自动重登，**不上传、不打日志**，退出登录即清除
- 浏览器方式校外登录后，会话 Cookie、浏览器 UA 和个人资料加密保存在本机安全存储；重启优先恢复该会话，无需保存密码。恢复时也将 Cookie 写回系统 WebView，保持网关和应用内网页可用。临时断网或门户 403 不会清除已保存会话；学校明确要求重新认证、Cookie 到期或主动退出登录后，需要重新登录。升级至 `1.0.0+8` 后完成一次网页登录即可建立快照。
- 「记住账号」仅保存学号
- 本项目为个人工具，与东北大学官方无关；请遵守学校相关使用规定

## 🧪 质量

```bash
flutter analyze   # 0 issues
flutter test      # 业务单测 + 双平台导航/搜索/设置/表单/大字体回归
```

### UI 验证与预览

`test/platform_ux_test.dart` 在 Android / iOS 平台覆盖下检查导航、搜索保留、主题切换、320px 宽 + 1.3 倍字体、键盘避让、日程保存与减少动态效果。
`test/performance_regression_test.dart` 覆盖千项服务列表的按需创建、切页首帧与状态保留、启动层生命周期，以及数据更新时的主题复用。
Windows 本地可生成预览（采用本机微软雅黑，字体与 iPhone / Android 真机会有差异）：

```powershell
flutter test --dart-define=UI_PREVIEWS=true --update-goldens test/platform_ux_test.dart
```

图片位于 `outputs/ui/`。iOS 真机侧滑、VoiceOver、系统字体和系统材质效果仍需 macOS / iPhone 验收。

### 2026-11-01 兼容性性能优化（1.0.0+5）

- 服务大厅使用单层 sliver 网格，按视口创建应用与专题服务，减少首次切入时的布局和图标加载。
- 页签立即显示，保留已访问页面的搜索、滚动状态；不可见页面暂停 ticker，页面重绘彼此隔离。
- 普通业务数据更新复用主题，仅外观设置变化或动态取色结果更新时重新生成主题。
- 应用图标按显示尺寸和设备像素比解码，减少大图标占用的图片缓存内存。
- 启动层使用柔和徽章、深色适配与有限动画；淡出后保持首页实例，避免重复初始化。减少动态效果时直接显示首页，慢网等待设有上限。

验证范围与构建结果见 [性能优化记录](outputs/performance-20261101.md)。

### iOS 液态玻璃与校内网页兼容

- iOS 26+ 使用插件原生 `UITabBar` 和 `UIGlassEffect`，旧版系统回退系统模糊。Windows / Web 预览仅能展示 Flutter 模糊回退，不能代表原生玻璃的折射和触感；原生效果需 iPhone 验收。
- 浮动底栏之下允许内容滚动，各页面预留末尾空间，最后一项能完整移出底栏。高对比度预览采用不透明表面，原生材质遵循系统辅助功能设置。
- `Info.plist` 的 `NSAllowsArbitraryLoadsInWebContent` 允许 WKWebView 打开校园 HTTP-only 系统和其网页资源；未设置全局 `NSAllowsArbitraryLoads`。
- 门户明确提供的 `http://` 链接原样加载，保留端口、路径和 SSO 参数；iOS 手机版使用真实 WKWebView 默认 UA，不再伪装 Android Chrome。保留桌面版切换、网页新窗口入口与系统浏览器兜底。
- 校内 HTTPS 页面加载失败后自动尝试 HTTP，使用重定向后的当前地址，并保留端口、路径和查询参数。同一次加载中每个 HTTPS 来源最多自动尝试一次，避免 HTTP / HTTPS 重定向循环；明确的 HTTP 入口不会被反向升级。统一认证、门户和 VPN 登录入口保持 HTTPS。失败页保留手动切换和系统浏览器入口；复制、重试、外部浏览器均使用当前地址。
- iOS 构建工作流选择 macOS 26 / Xcode 26；这里只修改构建配置，尚未执行远程构建。Windows 测试使用 WebView 平台替身，不能替代真实站点 SSO / WebKit 兼容测试。
