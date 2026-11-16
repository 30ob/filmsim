# FilmSim · iPhone 胶片模拟相机

一个 SwiftUI + AVFoundation + Core Image 的 iPhone 相机 App：取景时**实时**套用富士风格的胶片模拟，快门是一格一格的胶片机刻度拨盘（真正的曝光时间锁定），视频支持 **Apple Log** 录制，工程可以直接 Archive 上传 TestFlight。

> **先把话说清楚**：这个仓库在 Windows 上编写，我无法在这里编译 iOS 工程，也无法替你把包传到 TestFlight。你要做的只有一件事——让一台 Mac 编译它（云 Mac 也算，见第 3 节），然后上传（第 8 节）。代码按 iOS 17 API 编写，第一次编译如果有个别报错，通常是 Xcode 版本差异，改起来都是一两行的事。

---

## 1. 它现在能做什么

| 能力 | 实现方式 | 备注 |
| --- | --- | --- |
| 11 种胶片外观 | Core Image 滤镜链：通道混合 → 特性曲线 → 饱和/自然饱和 → 高光溢出 → 颗粒 → 暗角 | PROVIA / VELVIA / ASTIA / CLASSIC CHROME / CLASSIC NEG / PRO NEG Hi / PRO NEG Std / ETERNA / ACROS / MONOCHROME / SEPIA |
| 实时取景预览 | `AVCaptureVideoDataOutput` → `CIImage` → Metal（MTKView）逐帧渲染 | 看到的就是拍到的 |
| 全分辨率拍照 | `AVCapturePhotoOutput` → 同一套渲染器烘焙 → JPEG 存相册 | 4800 万像素格式会自动选用，处理前有 30MP 上限保护 |
| 快门拨盘 | `setExposureModeCustom(duration:iso:)` | A 档自动；1″–1/8000 整档手动 |
| ISO | 手动时用 `activeFormat.minISO...maxISO` 夹取 | 只锁 ISO 时沿用当前自动快门 |
| 曝光补偿 | `setExposureTargetBias` | −3…+3 EV |
| 白平衡偏移 | R / B 双通道增益（仿富士 R/B 偏移） | −1…+1 |
| 对焦 / 变焦 | 点击对焦（自动换算 aspect fill 坐标）+ 双指缩放 | 后置 1×–6× 数字变焦 |
| Apple Log 录像 | `device.activeColorSpace = .appleLog` + `AVCaptureMovieFileOutput`（HEVC） | 需要 iPhone 15 Pro 及更新机型 / iOS 17 |
| 相册落盘 | `PHAssetCreationRequest` | 只申请「添加到相册」权限 |

---

## 2. 目录结构

```
filmsim/
├─ project.yml                     # XcodeGen 工程定义（推荐）
├─ codemagic.yaml                  # 没有 Mac 时用的云构建配置（见 docs/codemagic.md）
├─ ExportOptions.plist             # Archive 导出配置（TestFlight 用）
├─ docs/
│  ├─ install-only.md              # ★ 只想装到自己手机上：一页速查卡（0 元）
│  ├─ cloud-mac.md                 # A 路线：按小时租云 Mac 的逐屏步骤
│  ├─ codemagic.md                 # B 路线：全程不碰 Mac 的云构建步骤
│  └─ no-dev-account.md            # 不买 $99 开发者账号怎么装到自己手机上
├─ scripts/
│  ├─ upload_testflight.sh         # 归档 + 导出 + 上传 一条龙
│  └─ make_app_icon.py             # 重新生成 1024 图标
└─ FilmSim/
   ├─ Info.plist                   # 权限文案 / 方向 / 深色模式
   ├─ PrivacyInfo.xcprivacy        # 隐私清单（App Store 强制）
   ├─ Assets.xcassets/             # AppIcon + AccentColor
   ├─ App/FilmSimApp.swift
   ├─ Camera/
   │  ├─ CaptureSettings.swift     # 快门档位 / ISO / 模式
   │  ├─ CameraSession.swift       # 相机会话：格式、曝光、录像、对焦
   │  └─ PhotoCaptureProcessor.swift
   ├─ Render/
   │  ├─ FilmStock.swift           # 11 套胶片参数（就在这个文件里调色）
   │  ├─ FilmRenderer.swift        # 滤镜链 + JPEG 编码
   │  └─ MetalPreviewView.swift    # MTKView 预览
   ├─ UI/
   │  ├─ CameraView.swift          # 主界面
   │  ├─ DialComponents.swift      # 刻度拨盘 / 胶片条 / 信息胶囊
   │  └─ AdjustPanel.swift         # 参数面板 + 关于页
   └─ Utilities/PhotoLibrarySaver.swift
```

---

## 3. 前置条件

| 项 | 要求 |
| --- | --- |
| Mac | macOS 13.5+，装 Xcode 15.4 或更新（要 iOS 17 SDK） |
| 账号 | Apple Developer Program，**99 美元/年**。免费账号只能连自己手机跑 7 天，**不能上 TestFlight** |
| 真机 | 任意 iPhone（iOS 17+）。Apple Log 必须 iPhone 15 Pro / Pro Max 及更新机型 |
| 可选 | `brew install xcodegen`（用来生成 .xcodeproj） |

没有 Mac 的话：MacinCloud / MacStadium 按小时租一台（选带 Xcode 的镜像），或者找有 Mac 的朋友帮你跑第 5、8 节。

### 没有 Mac？三条路

iOS 没有"双击安装"这回事：`.swift` 源码必须先被 **macOS 上的 Xcode** 编译、再用你的开发者证书**签名**，iPhone 才肯装。所以没有 Mac 不是"导入方式"的问题，是"借一台 Mac"的问题。三条路，按省心程度排：

| 方式 | 花费 | 你需要准备 | 适合 |
| --- | --- | --- | --- |
| **A. 按小时租云 Mac**（MacinCloud / MacStadium） | 约 ¥10–30/小时，**1–2 小时够用** | 浏览器 + 自己的 Apple ID（会收 2FA 验证码） | 想一次成功、报错能现场改（推荐） |
| **B. Codemagic 云构建**（仓库里已配好 `codemagic.yaml`） | 免费额度 500 分钟/月 | GitHub 账号 + App Store Connect API Key | 不想碰 Mac，愿意照文档配一次（之后一键出包） |
| **C. 找人代打** | 人工费 ¥200–800 | 把工程给对方，用**你的**账号上传 | 完全不想动手 |

**A. 云 Mac（最稳）**

1. [macincloud.com](https://www.macincloud.com) 注册，选 **Pay-As-You-Go**（按小时计费），服务器类型选 **Managed Server**，镜像选带 Xcode 16 的
2. 浏览器里连上去，把 `filmsim-ios-1.0.zip` 传上去解压（用网盘/邮件附件/微信传文件都行）
3. 打开终端：`brew install xcodegen && cd filmsim && xcodegen generate`
4. `open FilmSim.xcodeproj` → 填 Bundle ID → Signing 里登录你的 Apple ID（验证码会发到你手机）→ 选 Team
5. Product → Archive → Distribute App → App Store Connect → Upload
6. **用完立刻关机**（按分钟计费），并在设置里退出 Apple ID

**B. Codemagic（不用 Mac，配一次以后一键出包）**

1. 把 `filmsim/` 推到一个 **GitHub 私有仓库**（网页上传也行，不用命令行）
2. [codemagic.io](https://codemagic.io) 用 GitHub 登录 → Add application → 选这个仓库
3. 先建好 App 记录：App Store Connect → My Apps → **+** → New App（Bundle ID 要和 `codemagic.yaml` 里一致）
4. 拿 API Key：App Store Connect → 用户和访问 → 集成 → App Store Connect API → 生成密钥（角色选 **App Manager**），`.p8` 文件只能下载一次
5. Codemagic → Teams → Integrations → **App Store Connect** → 把 Issuer ID / Key ID / `.p8` 填进去
6. 改 `codemagic.yaml` 里两处 `com.yourcompany.filmsim` 成你自己的 → Start new build → 选 `ios-testflight`
7. 等约 10 分钟，build 自动出现在 TestFlight

**C. 代打**：把 zip 和一个临时加入 App Store Connect 团队的邀请发过去即可（别把 Apple ID 密码给别人）。

📖 逐屏操作手册：**A 路线（云 Mac）** → [docs/cloud-mac.md](docs/cloud-mac.md) ｜ **B 路线（Codemagic）** → [docs/codemagic.md](docs/codemagic.md)

💸 **不想买 $99 的开发者账号？** TestFlight 用不了（这是付费会员专属），但可以免费装到自己手机上玩 7 天，见 [docs/no-dev-account.md](docs/no-dev-account.md)。

⚡ **只想装到自己手机上、不上架？** 直接照 [docs/install-only.md](docs/install-only.md) 做——一页速查卡，0 元，云端编译 + Windows 自签。

> ⚠️ 三条路都绕不开 **99 美元/年的 Apple Developer Program**。没有它就没有 TestFlight，也没有能装到自己手机上的证书——这是苹果的规矩，不是工程的限制。

---

## 4. 工程怎么来的

仓库里没有提交 `.xcodeproj`（二进制工程文件容易冲突，也不方便手写）。两种方式二选一。

### 方式 A：XcodeGen（推荐，一条命令）

```bash
brew install xcodegen
cd filmsim
xcodegen generate
open FilmSim.xcodeproj
```

### 方式 B：手动建工程（不用装东西）

1. Xcode → File → New → Project → iOS → App
2. Product Name 填 `FilmSim`，Interface 选 **SwiftUI**，Language 选 **Swift**
3. 删掉模板生成的 `ContentView.swift` 和 `FilmSimApp.swift`
4. 把本仓库 `FilmSim/` 下的 4 个分组（App / Camera / Render / UI / Utilities）整个拖进工程，勾选 **Copy items if needed** 和 **Create groups**
5. 把 `FilmSim/Assets.xcassets` 拖进去替换默认的
6. 选中 Target → Build Settings → 搜索 `Info.plist`，把 `INFOPLIST_FILE` 改成 `FilmSim/Info.plist`，并确认 `Generate Info.plist File` 为 **No**
7. 把 `FilmSim/PrivacyInfo.xcprivacy` 加到 Target 的 Copy Bundle Resources（新版 Xcode 拖进去默认就是资源）
8. Signing & Capabilities → Team 选你的开发者账号，Bundle Identifier 改成你自己的（例如 `com.yourname.filmsim`）

---

## 5. 先在真机上跑通

1. iPhone 用数据线连 Mac，手机上「信任此电脑」
2. Xcode 顶部设备选你的 iPhone（**不是模拟器**，模拟器没有相机）
3. `Cmd + R`
4. 首次启动会依次弹出相机、麦克风、相册权限，全部允许

跑起来后：底部横条选胶片 → 拖动中间刻度盘改快门 → 点按取景器对焦 → 白色快门键拍照 → 相册里能看到已经带胶片味的成片。

顶栏右侧滑杆按钮是参数面板（ISO / EV / 颗粒 / 褪色 / 暗角 / 白平衡偏移）。

---

## 6. 快门是怎么"真的"调下来的

不是模拟的动画，是真的改了曝光时间：

```swift
try device.lockForConfiguration()
device.setExposureModeCustom(duration: CMTime(value: 1, timescale: 125), iso: iso)
device.unlockForConfiguration()
```

两个必须处理的坑，代码里都做了：

1. **帧时长**：曝光时间不能长于帧间隔。选 1/8 秒时，代码会同时把 `activeVideoMinFrameDuration` / `activeVideoMaxFrameDuration` 拉长到 1/8，再调曝光；否则机身会把曝光默默夹回 1/30。
2. **实际生效值**：`setExposureModeCustom` 的 completion 会回传机器真正用上的时长。拨盘上方那行「实际 1/30」就是它——慢门机型受限时会和拨盘值不一样，这是真实情况，不是 bug。

A 档 = `exposureMode = .continuousAutoExposure`，此时 EV 补偿才生效；手动快门档下 EV 补偿会被忽略（符合相机逻辑）。

---

## 7. Apple Log 是怎么接的、限制在哪

- 打开「视频」模式里的 `APPLE LOG`：代码在 `device.formats` 里筛出 `supportedColorSpaces` 含 `.appleLog` 的格式，切换格式后设置 `device.activeColorSpace = .appleLog`，再用 `AVCaptureMovieFileOutput` + HEVC 录制。这样录出来的是 BT.2020 / 10-bit 的 Log 素材，带着正确的色彩标签，能直接丢进 Resolve / Final Cut 套官方 LUT。
- 取景器里看到的是**近似还原**（一段固定的 S 曲线 + 轻微提饱和），只为了看得舒服，不影响录制文件。想精确预览，就在后期软件里套 Apple 的官方 LUT。
- 硬性限制：`iPhone 15 Pro / Pro Max` 及更新机型，iOS 17+。其它机型上按钮是灰的，文案会告诉你原因。
- 4K ProRes Log 需要外接存储，这个 App 目前只走 HEVC，不碰 ProRes。

---

## 8. 上传 TestFlight 的完整流程

### 8.1 注册与 App ID

1. [developer.apple.com/programs](https://developer.apple.com/programs/) 注册 Apple Developer Program（个人 99 美元/年，公司需要 D-U-N-S 号，1–3 天审核）。
2. 登录 [developer.apple.com/account](https://developer.apple.com/account) → Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App → 填 Bundle ID（要和工程里完全一致，例如 `com.yourname.filmsim`），不需要勾任何 Capability。
3. Xcode → Settings → Accounts → 用同一个 Apple ID 登录。

### 8.2 建 App 记录

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → **+** → New App
2. Platform 选 iOS；Name 是 App Store 上显示的名字（**必须全球唯一**）；Primary Language 选简体中文；Bundle ID 选刚建的那个；SKU 随便填（例如 `filmsim001`）。

### 8.3 Archive 上传

1. Xcode 里设备选 **Any iOS Device (arm64)**，Product → **Archive**
2. 归档完自动弹 Organizer → **Distribute App** → **App Store Connect** → **Upload** → 一路 Next
3. 等 5–30 分钟，App Store Connect 的 TestFlight 页会出现这个 build，处理完状态从「正在处理」变成「准备提交」

命令行等价做法（第 9 节脚本会自动干这些）：

```bash
xcodebuild -project FilmSim.xcodeproj -scheme FilmSim -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/FilmSim.xcarchive \
  DEVELOPMENT_TEAM=XXXXXXXXXX -allowProvisioningUpdates archive
```

### 8.4 发给自己 / 团队（内部测试）

1. App Store Connect → 你的 App → **TestFlight** → 左侧「内部测试」
2. 点 **+** 建一个测试组，添加测试员（测试员的 Apple ID 必须先在「用户和访问」里被邀请进团队，角色选 Developer 或 Marketing）
3. 给这个 build 点「添加测试员」→ 测试员手机会收到 TestFlight 邀请邮件
4. **内部测试不需要 Beta 审核**，build 处理完就能装，通常十几分钟搞定

### 8.5 发给外部用户（外部测试）

1. TestFlight → 左侧「外部测试」→ 建组（最多 60 个组 / 10000 人）
2. 填 **Test Information**：Beta App Description（这个 App 干什么）、Feedback Email、联系人、What to Test（例如「测试手动快门 1/8–1/1000、Log 录制」）
3. 提交 **Beta App Review**：首个外部 build 要审核，一般 1–2 天，之后同一版本的后续 build 通常不用再审
4. 通过后把公开链接发给用户，或直接发邀请邮件

### 8.6 版本节奏

- 每个 build 保质期 **90 天**，过期后测试员打不开
- 同一个 `CFBundleShortVersionString`（1.0.0）下新建 build 时，`CFBundleVersion` 必须**递增**（1、2、3…）
- 改版本号：`project.yml` 里 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，或 Xcode Target → General

---

## 9. 一条命令上传（可选）

```bash
cd filmsim
export TEAM_ID=你的十位团队ID          # developer 网站 Membership 页能看到
export ASC_KEY_ID=XXXXXXXXXX           # App Store Connect API Key
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8
./scripts/upload_testflight.sh
```

脚本会：用 `xcodebuild` 归档 → 导出 ipa → `xcrun altool --upload-app` 上传。没有 API Key 也可以改用 App 专用密码：

```bash
export APPLE_ID=you@example.com
export APP_SPECIFIC_PASSWORD=abcd-efgh-ijkl-mnop
```

（App 专用密码在 [appleid.apple.com](https://appleid.apple.com) → 登录与安全 → App 专用密码 生成。）

> 首次上传前，请先把 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 和 `ExportOptions.plist` 里的 `YOURTEAMID` 改成你自己的。

---

## 10. 上架/审核的几个真坑

1. **权限文案缺失 = 启动闪退 = 秒拒**。`NSCameraUsageDescription`、`NSMicrophoneUsageDescription`、`NSPhotoLibraryAddUsageDescription` 已经写在 `Info.plist` 里，别删。
2. **App 图标不能带 alpha 通道**，否则上传报 `Invalid App Store Icon`。仓库里的 `AppIcon.png` 是 RGB 无透明，重新出图时注意保持。
3. **隐私清单**：`PrivacyInfo.xcprivacy` 已声明使用 UserDefaults（原因码 CA92.1）。2024 年起缺隐私清单会被拒。
4. **出口合规**：`ITSAppUsesNonExemptEncryption = false` 已设，省掉每次上传的问询。
5. **商标风险（重要）**：`Fujifilm`、`PROVIA`、`VELVIA`、`ACROS`、`CLASSIC CHROME` 都是富士的注册商标。**自己 TestFlight 内部测试完全没问题**；如果要公开上架 App Store，建议：
   - App 名不要带「富士 / Fuji / Fujifilm」
   - 胶片名改成中性词（Standard / Vivid / Soft / Chrome / Negative / Cinema / B&W）
   - 描述里加一句「风格灵感来自经典胶片，与富士胶片公司无关联」
   
   改名字只需要动 `Render/FilmStock.swift` 里的 `name` / `chineseName` 两个属性 + `Info.plist` 的 `CFBundleDisplayName`，五分钟的事。
6. **审核员看不到相机画面**：相机类 App 审核时如果拒绝授权就一片黑，建议在「关于」里写清楚这是相机应用，并在 Review Notes 里说明「需要真机测试，模拟器无相机」。
7. **模拟器构建会失败/黑屏**：预览管线依赖 Metal + 相机，只能用真机。

---

## 11. 想改效果，改哪儿

| 想改的东西 | 位置 |
| --- | --- |
| 胶片的对比/饱和/色偏 | `FilmStock.swift` 里每个 `FilmProfile`：`curve`（5 个点，x 固定 0/0.25/0.5/0.75/1）、`saturation`、`matrix`（通道混合）、`warmth` |
| 颗粒强度 | `profile.grain`（默认值）× 面板里的「颗粒」倍率 |
| 暗角 | `profile.vignette` × 面板倍率 |
| 高光溢出 | `profile.halation`（ETERNA / CLASSIC NEG 开了） |
| 滤镜顺序/新增一步 | `FilmRenderer.render(_:look:)` 里按注释编号插入 |
| 拨盘档位 | `CaptureSettings.swift` 的 `ShutterSpeed` 与 `dialOrder` |
| 界面配色 | `FilmStock.accent` + `Assets.xcassets/AccentColor` |
| 图标 | 改 `scripts/make_app_icon.py` 后重跑：`python scripts/make_app_icon.py FilmSim/Assets.xcassets/AppIcon.appiconset/AppIcon.png` |

---

## 12. 已知限制 / 下一步

- 视频**不烘焙**胶片模拟（Log 是原片，标准模式也是原片）。想加「录完自动套胶片导出」可以用 `AVVideoComposition(asset:applyingCIFiltersWithHandler:)` + `AVAssetExportSession`，渲染器可以直接复用。
- 48MP 以上照片会先降到 30MP 再处理，避免内存峰值。
- 预览是逐帧 GPU 渲染，A 系列芯片无压力，但老机型长时间录制 Log 可能掉帧。
- 没有 Live Photo、没有 ProRAW、没有多镜头无缝变焦（1× / 2× 走的是数字变焦）。
- 前置摄像头不支持 Log（硬件限制），切过去会自动关掉开关。

---

## 13. 排错

| 现象 | 处理 |
| --- | --- |
| `Cannot find 'AVCaptureColorSpace.appleLog'` | Xcode 太旧，升到 15.4+（要 iOS 17 SDK） |
| 编译报 `Missing package product` / 找不到文件 | 方式 B 手动拖文件时漏了分组，检查 Target → Build Phases → Compile Sources |
| 启动黑屏、没有任何报错 | 没给相机权限，或跑在模拟器上 |
| 拍照后相册里没有 | 检查「照片 → 添加照片」权限；`Info.plist` 的 `NSPhotoLibraryAddUsageDescription` |
| 快门拨到 1/8 但画面没变暗 | 正常：手动快门锁的是曝光时间，画面亮度由 ISO 和光线决定，把 ISO 调低才变暗 |
| 上传报 `Invalid Bundle` / 图标错误 | 图标带 alpha 或尺寸不是 1024×1024 |
| TestFlight 看不到 build | 还在处理（等 30 分钟）；或 build 号没递增 |

---

## 14. 做完之后

想继续加东西，比较有价值的顺序：

1. 视频烘焙（录完套胶片导出）——复用现成渲染器，工作量不大
2. 3D LUT 导入（`CIColorCubeWithColorSpace`），让用户能导入自己的胶片 LUT
3. 相册内置浏览 + 一键换胶片重出片（RAW/原图保留，后期再套）
4. 多镜头虚拟设备（`.builtInTripleCamera`）做顺滑变焦

需要我做哪一块，直接说。
