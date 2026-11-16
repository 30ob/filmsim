# 速查卡：只想装到自己手机上（0 元）

目标：把 FilmSim 装进你的 iPhone，自己拍着玩。不上架、不用 TestFlight、不买开发者账号。

```
云端编译（不要账号） → 下载未签名 ipa → Windows 上自签 → 装进手机 → 7 天后重签
```

**总花费：0 元。第一次约 1 小时，之后每 7 天续签 2 分钟。**

---

## 先做三个检查

- [ ] **iPhone 系统是 iOS 17 或更新**：设置 → 通用 → 关于本机 → 看「iOS 版本」
- [ ] **有 Windows 电脑**，并且有一根**能传数据**的线（原装或 MFi 线；只能充电的杂牌线会失败）
- [ ] **一个 Apple ID**（建议注册一个专用小号，别用主账号）

> 系统低于 iOS 17 的话，先别往下做——这个 App 用了 iOS 17 的相机 API，装上也打不开。告诉我你的型号和版本，我改代码降到 16。

---

## 第 1 步：云端编译出 ipa（约 15 分钟）

1. <https://github.com> → 新建仓库 `filmsim` → 选 **Private**
2. 点 **uploading an existing file**，把 `filmsim` 文件夹**里面的内容**拖进去（`codemagic.yaml`、`project.yml`、`FilmSim/`、`docs/`、`scripts/`）
   - ⚠️ 别传 `filmsim-ios-1.0.zip` 这个文件本身，要传解压后的内容
   - ⚠️ `codemagic.yaml` 必须在仓库**根目录**
3. <https://codemagic.io> → **Sign up with GitHub**
4. **Add application** → 选 `filmsim` → 项目类型选 iOS
5. **Start new build** → Workflow 选 **`FilmSim → 未签名 ipa（自签用，不需要开发者账号）`** → Start
6. 等 8–12 分钟，构建成功后页面底部 **Artifacts** → 下载 **`FilmSim-unsigned.ipa`**

> 这一步**不需要 Apple 账号、不需要 API Key、不需要付任何钱**。
> 如果失败：把日志里带 `error:` 的那几行发给我。

---

## 第 2 步：Windows 装两个东西（约 10 分钟）

| 装什么 | 去哪 | 干什么用 |
| --- | --- | --- |
| **Apple 设备**（或 iTunes） | 微软商店搜「Apple 设备」 | 给 iPhone 提供 USB 驱动 |
| **Sideloadly** | <https://sideloadly.io> | 用你的 Apple ID 给 ipa 签名并安装 |

---

## 第 3 步：手机打开开发者模式

设置 → 隐私与安全性 → **开发者模式** → 打开 → 重启手机 → 重启后确认打开

（iOS 16 以后必须开，不开装上去也打不开。）

---

## 第 4 步：签名并安装（约 3 分钟）

1. iPhone 用线插上 Windows → 手机上点「信任此电脑」
2. 打开 **Sideloadly**，顶部能看到你的设备名就说明识别成功
3. 把 `FilmSim-unsigned.ipa` 拖进 Sideloadly 的 **IPA** 框
4. **Apple ID** 填你的账号 → **Start** → 输密码
   - 如果它要「App 专用密码」：<https://appleid.apple.com> → 登录与安全 → App 专用密码 → 生成 → 粘贴
5. 等 1–3 分钟，桌面出现 App 图标
6. 手机：设置 → 通用 → **VPN与设备管理** → 点你的 Apple ID → **信任** → 打开 App

第一次打开会依次要相机、麦克风、相册权限，全给。

---

## 第 5 步：确认能用

- [ ] 取景画面是真实画面（不是黑的）
- [ ] 切胶片，画面颜色实时变（ACROS 变黑白）
- [ ] 拨盘拨到 1/8，画面明显变暗
- [ ] 按快门 → 「已保存到相册」→ 相册里有带胶片效果的照片

---

## 7 天后

App 点开闪退 = 签名过期。**重新插上电脑，第 4 步再跑一遍**（同一个 ipa，不用重新下载）。

想免插线：装 **AltStore + AltServer**（Windows 后台常驻），同一 Wi-Fi 下自动续签。

---

## 常见卡点

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| Sideloadly 看不到设备 | 驱动没装 / 线只充电 | 装「Apple 设备」；换线；手机上点信任 |
| `bundle identifier is not available` | `com.yourcompany.filmsim` 被占用了 | 改 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 成 `com.你的名字.filmsim2026`，重新构建 |
| `Your device is not registered` | 免费账号的额度/注册失败 | 重试一次；换 Apple ID 小号 |
| 装上但闪退 | 没开开发者模式 / 没信任证书 | 回第 3、4 步 |
| 提示「App 无法验证」 | 证书没被信任 | 设置 → 通用 → VPN与设备管理 → 信任 |
| 打开后黑屏 | 相机权限被拒 | 设置 → 胶片模拟 → 打开相机 |
| 7 天后打不开 | 签名过期 | 重跑第 4 步 |

---

## 这件事的边界（先说清，省得白折腾）

- 只能装在**你自己的**设备上（最多 3 个自签 App），**不能发给别人**
- 每 7 天必须重签一次，这是免费账号的硬限制
- 用 Sideloadly 意味着把 Apple ID 密码（或专用密码）交给第三方工具——**用小号**
- 照片存在系统相册里，App 过期/重装**不会丢照片**

---

## 如果你能借到一台 Mac（更短的路）

有 Mac 的话根本不用这么麻烦：Xcode 打开工程 → Signing 选 `Personal Team`（登录免费 Apple ID）→ 数据线连 iPhone → `Cmd + R`。20 分钟，不用第三方工具，不用交密码。7 天后同样要重跑一次。
