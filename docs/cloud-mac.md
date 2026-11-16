# 云 Mac 上架手册（A 路线）

目标：在一台**按小时租来的 Mac** 上，把这个工程编译、签名、上传到 TestFlight，然后在自己的 iPhone 上装起来。
全程约 **1.5–2 小时**（不含开发者账号审核时间），云 Mac 花费约 **$3–6**。

> 一句话原理：`.swift` 源码 → Xcode 编译 → 用你的开发者证书签名 → 苹果服务器收包 → TestFlight 分发 → 手机安装。
> 云 Mac 连不上你的 iPhone，所以**真机测试只能通过 TestFlight**。模拟器只能看界面（第 5 节）。

---

## 0. 全流程一览

| 阶段 | 在哪做 | 耗时 | 花钱 |
| --- | --- | --- | --- |
| ① 注册 Apple Developer Program | 浏览器 | 1–3 天（等审核） | $99/年 |
| ② 建 App ID + App 记录 + 准备好 zip | 浏览器（**不用 Mac**） | 30 分钟 | 0 |
| ③ 租云 Mac、编译签名上传 | 云 Mac | 1.5–2 小时 | $3–6 |
| ④ 等苹果处理 + 手机安装 | iPhone | 20–40 分钟 | 0 |

**先做完 ①②，再租 ③**——云 Mac 按分钟计费，别把等审核、建 App 记录这种事放在计费时间里做。

---

## 1. 现在就能做（不用 Mac，浏览器即可）

### 1.1 注册 Apple Developer Program

1. 打开 <https://developer.apple.com/programs/enroll/>，用你的 Apple ID 登录
2. 选 **Individual**（个人）——最快，1–2 天；公司账号要 D-U-N-S 编号，1 周起
3. 填个人信息（姓名要和身份证/护照一致，拼音），付款 **$99/年**
   - 国内卡：一般要带 Visa / MasterCard 标志的双币卡；银联单币卡常常失败
   - 付款失败就先联系苹果支持，别反复提交
4. 等邮件。**审核通过前，后面所有步骤都做不了**（包括 TestFlight）

✅ 检查：登录 <https://developer.apple.com/account>，能看到 **Certificates, Identifiers & Profiles** 这个入口，就说明账号活了。

> 同一时间把 **Apple ID 的双重认证**打开（appleid.apple.com → 登录与安全），后面在 Xcode 里登录会用到。

### 1.2 建 App ID（Bundle ID）

1. <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles** → **Identifiers** → 右边的 **＋**
2. 选 **App IDs** → **App** → Continue
3. Description 随便写 `FilmSim`；**Bundle ID** 选 Explicit，填：
   ```
   com.你的名字拼音.filmsim
   ```
   例如 `com.zhangsan.filmsim`。**这个字符串后面三处必须完全一致**（这里、工程里、App Store Connect 里），大小写也算。
4. 下面的 Capability 一个都不用勾 → Continue → Register

> 如果提示已被占用，就在后面加个年份：`com.zhangsan.filmsim2026`。全世界唯一，抢不到很正常。

### 1.3 建 App 记录（App Store Connect）

1. <https://appstoreconnect.apple.com> → **My Apps** → 左上 **＋** → **New App**
2. 填：
   - **Platforms**：iOS
   - **Name**：App Store 上显示的名字，全球唯一，例如「胶片模拟 FilmSim」（被占用了就加后缀）
   - **Primary Language**：简体中文
   - **Bundle ID**：选 1.2 建的那个
   - **SKU**：随便，例如 `filmsim-001`（不会公开）
   - **User Access**：Full Access
3. Create

> **为什么要先建**：上传时如果 App Store Connect 里没有对应记录，Xcode 会报
> `No suitable application records were found`，这一步在云 Mac 上没法补救（要回浏览器建，浪费时间）。

### 1.4 把工程放到云 Mac 能下载的地方

云 Mac 是新机器，你的文件不在上面。三种传法，任选：

| 方式 | 怎么做 |
| --- | --- |
| **邮件**（最省事） | 把 `filmsim-ios-1.0.zip` 当附件发给自己，云 Mac 浏览器开邮箱下载 |
| **WeTransfer** | <https://wetransfer.com> 上传，拿到链接，云 Mac 打开下载（不用登录） |
| **GitHub** | 建私有仓库上传，云 Mac 里 `git clone`（适合以后反复改） |

zip 只有 800 多 KB，邮件完全够。

### 1.5 顺手准备

- 手机装好 **TestFlight** App（App Store 搜 TestFlight）
- 记住你的 **Apple ID 密码**（云 Mac 上要输一次）+ 手机能收 2FA 验证码

---

## 2. 租一台云 Mac

### 2.1 选哪家

| 服务 | 价格（以官网为准） | 特点 |
| --- | --- | --- |
| **MacinCloud** ✅ 推荐 | 约 $1/小时，需预充值 | 图形界面、Xcode 预装、浏览器直接连，最适合新手 |
| MacStadium | 按月，$99 起 | 更稳更快，但一次买一个月，不划算 |
| Scaleway / AWS EC2 mac | 约 €0.10–0.65/小时，**有 24 小时最低计费** | 便宜但只有命令行 + VNC，要自己装环境 |

**结论：走 MacinCloud 的 Pay-As-You-Go。** 第一次做，图形界面能省掉你几个小时。

### 2.2 MacinCloud 实操

1. <https://www.macincloud.com> → 注册 → **Pay-As-You-Go**
2. 充值（几十美元起，按小时扣）
3. 进入控制台 → **Rent a Server / Pay-As-You-Go** → 选 **Managed Server**
   - 系统镜像选**带 Xcode 的最新版**（Xcode 16 或更高；iOS 17 SDK 是硬要求）
   - 区域优先选离你近的（US West 通常比 East 快一点）
4. 服务器准备好后（5–15 分钟），页面上会出现 **Connect** 按钮：
   - 浏览器里点 **Web Client** 就能连（推荐，不用装东西）
   - 或者用 Windows 自带的「远程桌面连接」，输入页面给的 IP / 用户名 / 密码
5. 连进去看到 macOS 桌面，就成功了

> 国内网络连美国 RDP 可能卡顿。用**有线网**、关掉其他占带宽的程序；远程桌面里别开动画多的窗口。

### 2.3 连上后先做三件事（省钱）

1. 右下角确认**网络正常**（能打开 apple.com）
2. 打开 **Terminal**（`Cmd + 空格` → 输入 `terminal` → 回车）
3. 把屏幕分辨率调大一点（系统设置 → 显示器），Xcode 面板多，屏幕小了很痛苦

> ⚠️ 托管服务器**可能在下一次会话被重置**，别把唯一一份文件只放在云 Mac 上。一次会话内做完。

---

## 3. 把工程跑起来（约 10 分钟）

### 3.1 下载 + 解压

1. 云 Mac 里打开 Safari，登录邮箱 / 打开 WeTransfer 链接，下载 `filmsim-ios-1.0.zip`
2. 双击 zip 解压 → 得到 `filmsim` 文件夹（在「下载」里）

### 3.2 生成 Xcode 工程

Terminal 里逐行执行：

```bash
cd ~/Downloads/filmsim
brew install xcodegen        # 约 1–2 分钟
xcodegen generate            # 生成 FilmSim.xcodeproj
open FilmSim.xcodeproj
```

Xcode 第一次启动会提示 **"Xcode needs to install additional components"** → 点 **Install**，等 2–5 分钟。

看到左侧工程导航里出现 `FilmSim` 蓝色图标，说明成了。

### 3.3 如果 `brew` / `xcodegen` 装不上

**备用一：手工下载 xcodegen**

1. 浏览器打开 <https://github.com/yonaskolb/XcodeGen/releases>，下载最新的 `xcodegen.zip`
2. 解压，把里面的 `xcodegen` 可执行文件拖到 `/usr/local/bin/`
   （Finder → 前往 → 前往文件夹 → 输入 `/usr/local/bin`）
3. Terminal 里 `xcodegen --version` 有输出就行，回到 3.2 的 `xcodegen generate`

**备用二：不装任何东西，手动建工程**

按 [README 第 4 节 方式 B](../README.md) 手动在 Xcode 里新建工程、拖文件进去。大约 10 分钟，但要点很多，容易漏（尤其是 `INFOPLIST_FILE` 那一步）。

---

## 4. 签名配置（最容易卡住的一步，慢慢来）

### 4.1 改 Bundle ID

1. Xcode 左侧最上面点蓝色的 **FilmSim** 工程图标
2. 中间栏选 **TARGETS → FilmSim**
3. 点 **Signing & Capabilities** 标签
4. **Bundle Identifier** 改成 1.2 里建的那个（例如 `com.zhangsan.filmsim`）
5. 勾上 **Automatically manage signing**

### 4.2 登录 Apple ID

1. 同一页 **Team** 下拉 → **Add an Account…**
2. 输入 Apple ID 和密码 → 手机会收到 6 位验证码 → 填进去
3. 关掉窗口，Team 下拉里选你的团队（通常显示为 `你的名字 (Personal Team)` 或公司名）

> 付费账号在这里显示的不是 "Personal Team"，而是你的**开发者团队名**。如果只看到 Personal Team，说明付费账号没登录成功 / 还没审核通过。

### 4.3 等它自己配好

选完 Team 后，Xcode 会自动去苹果服务器申请证书和描述文件，转圈 10–60 秒。
**"Signing Certificate" 和 "Provisioning Profile" 两行都变成正常文字（没有红色 ⚠️）就成功了。**

### 4.4 报错对照

| 报错 | 原因 | 解决 |
| --- | --- | --- |
| `Failed to register bundle identifier` | ID 被占用 | 改成 `com.你的名字.filmsim2026` 之类，并同步改 1.2 和 1.3 |
| `No profiles for 'com.x.filmsim' were found` | 刚创建还没同步 | 点下面的 **Try Again**；还不行就 Xcode → Settings → Accounts → **Download Manual Profiles** |
| `Communication with Apple failed` | 网络 / 2FA 超时 | 换网络重试；重新登录 Apple ID |
| `You already have a current iOS Distribution certificate` | 证书数量到上限 | <https://developer.apple.com/account> → Certificates → 撤销旧的 |
| `requires a development team` | 没选 Team | 回 4.2 |
| 一直转圈 | 云 Mac 网络慢 | 等 1 分钟；或重开 Xcode |

---

## 5. 先看一眼（模拟器，2 分钟）

### 5.1 运行

1. Xcode 顶部中间的设备下拉 → 选 **iPhone 16 Pro**（或任意 iPhone 模拟器）
2. `Cmd + R`

如果提示要下载模拟器运行时（几 GB，10–20 分钟），**可以跳过**：直接做第 6 节 Archive（Archive 不需要模拟器）。代价是你在上传前看不到界面。

### 5.2 你会看到什么

因为没有相机，App 会自动显示一张**测试图**（天空渐变 + 肤色/红绿蓝/白黑色块 + 灰阶条），并弹一条提示「模拟器模式：没有真实相机」。

你可以正常操作：
- 底部横条切 11 种胶片 → 测试图颜色实时变化
- 拖动中间刻度拨盘 → 快门档位变化（模拟器不执行真实曝光）
- 右上角滑杆 → 参数面板（ISO / EV / 颗粒 / 褪色 / 暗角 / 白平衡）
- 点视频模式 → APPLE LOG 按钮（模拟器上会显示「不支持」，正常）

### 5.3 模拟器里哪些是假的

| 功能 | 模拟器 | 说明 |
| --- | --- | --- |
| 取景画面 | ❌ 测试图 | 没有相机硬件 |
| 拍照 | ❌ | 没有 capture connection，会提示「相机还没准备好」 |
| 手动快门 | ❌ | 只是界面变化 |
| Apple Log | ❌ | 需要 iPhone 15 Pro+ 硬件 |
| 界面布局 / 胶片配色 / 拨盘手感 | ✅ | **这才是看模拟器的目的** |

> 如果发现布局错位（比如拨盘文字被裁、底部面板盖住取景器太多），现在改还来得及，比上传后再改省一个小时。

---

## 6. 归档上传（约 15 分钟）

### 6.1 Archive

1. Xcode 顶部设备下拉 → **Any iOS Device (arm64)**（不要选模拟器）
2. 菜单 **Product → Archive**
3. 编译 2–5 分钟，成功后自动弹出 **Organizer**

### 6.2 Distribute

1. Organizer 右侧点 **Distribute App**
2. 选 **App Store Connect** → **Next**
3. 选 **Upload** → **Next**
4. 勾选项保持默认（**Upload your app's symbols** 勾着）→ **Next**
5. 选签名方式 **Automatically manage signing** → **Next**
6. 确认摘要 → **Upload**
7. 等 2–10 分钟，出现 **Upload Successful** 才算完

### 6.3 上传报错对照

| 报错 | 原因 | 解决 |
| --- | --- | --- |
| `No suitable application records were found` | App Store Connect 没建 App 记录 | 回 1.3 建好，重新 Upload |
| `Invalid App Store Icon` / `icon can't be transparent` | 图标带 alpha | 仓库里的图标是无透明的；换图标时注意 |
| `Missing Info.plist key NSCameraUsageDescription` | 权限文案丢了 | 别删 `FilmSim/Info.plist` |
| `The bundle version must be higher...` | build 号没递增 | 改 `project.yml` 里 `CURRENT_PROJECT_VERSION` |
| `Invalid Signature` / `codesign failed` | 证书问题 | 回第 4 节重新配签名 |
| 卡在 "Authenticating with the App Store" | 网络 | 等 2 分钟；或重新登录 Apple ID |

---

## 7. TestFlight 装到自己手机（20–40 分钟）

### 7.1 等苹果处理

1. <https://appstoreconnect.apple.com> → 你的 App → **TestFlight**
2. 左侧 **Builds**，刚才那个 build 会显示「正在处理 / Processing」
3. 等 5–30 分钟，变成可用的状态（有时会收到「Missing Compliance」提示，因为我们在 `Info.plist` 里已经声明了 `ITSAppUsesNonExemptEncryption = false`，一般不会弹）

### 7.2 把自己加成测试员

1. App Store Connect 左上角 → **用户和访问 (Users and Access)** → **＋** → 邀请你自己（或团队成员的 Apple ID），角色选 **Developer**
2. 邮箱里点接受邀请
3. 回到 App → **TestFlight** → 左侧 **内部测试 (Internal Testing)** → **＋** 建组，例如 `Me`
4. 点这个 build 旁边的 **＋**，把组加进去

> 内部测试**不需要 Beta 审核**，加完就能装。外部测试（给非团队成员）才要审核。

### 7.3 手机上装

1. iPhone 上打开 **TestFlight** App，用同一个 Apple ID 登录
2. 会看到 App 和「安装 / Install」按钮
3. 装上，打开，**依次允许相机、麦克风、相册权限**

### 7.4 装完先测这几项

- [ ] 取景画面是真实画面，不是黑的
- [ ] 切胶片，画面颜色实时变化（VELVIA 明显更艳，ACROS 变黑白）
- [ ] 拨盘拨到 **1/8**，画面明显变暗/变糊（真慢门）
- [ ] 拨回 **A**，画面恢复正常亮度
- [ ] 按快门 → 提示「已保存到相册」→ 相册里能看到**带胶片效果**的照片
- [ ] 切到「视频」→ 打开 **APPLE LOG**（iPhone 15 Pro+ 才有）→ 录 5 秒 → 相册里有视频
- [ ] 点取景画面对焦 → 出现黄色对焦框
- [ ] 双指放大 → 画面变焦

任何一项不对，**截屏 + 描述操作**发给我，我改代码你重传（第二次上架只要 15 分钟）。

---

## 8. 收工（省钱 + 安全）

1. **立刻关闭云 Mac**（MacinCloud 控制台 → Stop / Shut Down），否则按分钟继续扣钱
2. Xcode → **Settings → Accounts** → 选中你的 Apple ID → **－** 删除
3. 去 <https://appleid.apple.com> → 设备列表，确认没有陌生 Mac 登录着
4. 云 Mac 上的下载文件不用管（服务器会重置）

> 上传完成就可以关机，不用等 TestFlight 处理完——处理是在苹果服务器上做的。

---

## 9. 全流程报错速查

| 卡在哪 | 现象 | 最可能的原因 |
| --- | --- | --- |
| 注册 | 付款失败 | 卡不支持国际支付，换卡或联系苹果 |
| 建 App ID | 提示已存在 | 换一个后缀 |
| 打开工程 | 找不到 `FilmSim.xcodeproj` | 没跑 `xcodegen generate` |
| 编译 | 大量红字 | 打开的文件不完整 / 拖文件时漏了（按 README 4B 重来） |
| 编译 | 只有一两处错 | Xcode 版本差异，把报错发我 |
| 签名 | 红字 `Failed to register...` | Bundle ID 被占用 |
| Archive | 灰色不可点 | 设备选了模拟器，改成 Any iOS Device |
| Upload | `No suitable application records` | App Store Connect 没建记录 |
| TestFlight | 一直 Processing | 正常，等 30 分钟；超过 2 小时去 App Store Connect 看邮件 |
| 手机 | 装了但打不开 | 权限没给；或 build 过期（90 天） |

---

## 10. 复盘：第二次会快多少

第一次 1.5–2 小时里，大概 40 分钟花在「找按钮」上。第二次：

- 云 Mac 会话缩短到 **30–40 分钟**（工程、签名、App 记录都在）
- 改代码 → 重新 Archive → Upload，**15 分钟**
- 同一个版本号下 build 号递增即可，不用重新建 App

如果你想彻底摆脱按小时租 Mac，配一次 **Codemagic**（工程里已有 `codemagic.yaml`，README 第 3 节 B 路线），之后每次都是网页点一下，免费额度 500 分钟/月够用。
