# 东大一号通 · NEUPortal

东北大学「一号通门户」（https://personal.neu.edu.cn/portal）的第三方 Material 3 多端客户端。
一套代码，同时构建 **Android / iOS / Windows / Web**。

> 界面为全新设计的 Material 3（Material You）风格；数据来自门户真实接口，另内置一份
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
| 📊 成绩 | **教务系统真实数据**：客户端自动 SSO 进入教务（CASTGC → jwapp 会话），抓取全部学期成绩（支持数字分与五级制「优/良/中/及格」按校标换算绩点）、GPA/加权平均分/学分动画统计；离线时回退演示数据并明确标注 |
| 🌐 打开网页 | **应用内 WebView v2**：自动注入 CAS 会话 Cookie，各业务系统 SSO 免登录直达；**系统返回键优先退站点历史**；**桌面版/手机版一键切换**（PC 页面不再挤成一团）；进度条、出错自动换协议重试、复制链接、系统浏览器兜底；CAS 会话过期自动填表重登 |
| 👤 我的 | 渐变个人卡、主题模式、Material You 动态取色、6 色主题色盘、登录/退出 |
| 📱 自适应 | 窄屏底部导航栏，宽屏（≥900px）侧边导航栏 |

## 🎨 设计

- Material 3 全量：`ColorScheme.fromSeed` 动态色、tonal surface、大圆角卡片、NavigationBar 指示器
- 种子色取自门户 `site/info` 接口的 `theme_color`（`#3553A2`，东大蓝）
- 深浅色双主题；Android 12+ 支持跟随壁纸动态取色（`dynamic_color`）
- 全中文界面；触感反馈（切页/点课表/刷新）

## 🚀 构建与运行

环境：Flutter SDK（本机位于 `D:\flutter`）+ 各平台工具链。

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
（亮色 `#3553A2` / 暗色 `#1F2C60`，见 `android/app/src/main/res/values*/`）。

## 📱 没有 Mac 怎么编 iOS IPA？

仓库自带 GitHub Actions（`.github/workflows/ios-ipa.yml`）：每次 push 到 main 会自动在
**GitHub 免费的 macOS 云跑机**上执行 `flutter build ios --release --no-codesign`，
并打包出**未签名 IPA**（Actions 页 → 对应 run → Artifacts 下载）。

安装到 iPhone（任选其一）：

| 方式 | 签名 | 有效期 |
| --- | --- | --- |
| Sideloadly / AltStore（Windows 可用）+ 个人 Apple ID | 免费 | 7 天，到期重签 |
| 苹果开发者账号（$99/年）+ 证书 | 付费 | 1 年 |
| TrollStore（特定 iOS 版本） | 永久 | 永久 |

> Android APK 同样有 CI（`android-apk.yml`，ubuntu 跑机），push 后自动出包。

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
- 「记住账号」仅保存学号
- 本项目为个人工具，与东北大学官方无关；请遵守学校相关使用规定

## 🧪 质量

```bash
flutter analyze   # 0 issues
flutter test      # RSA 加密 / GPA 计算 / 色板稳定性单测
```
