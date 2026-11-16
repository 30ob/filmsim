# Codemagic 云构建手册（B 路线 · 全程不碰 Mac）

目标：代码放 GitHub，Codemagic 用它的云 Mac 打包并直接上传 TestFlight。你只需要一个浏览器。

**一次配好，以后每次改完代码点一下按钮，10 分钟后新 build 就在 TestFlight 里。**
代价是：没有模拟器可看，你第一次见到这个 App 是在手机上。

---

## 0. 全流程一览

| 阶段 | 在哪做 | 耗时 | 花钱 |
| --- | --- | --- | --- |
| ① 注册 Apple Developer Program | 浏览器 | 1–3 天（等审核） | $99/年 |
| ② 建 App ID + App 记录 | 浏览器 | 15 分钟 | 0 |
| ③ 生成 App Store Connect API Key | 浏览器 | 5 分钟 | 0 |
| ④ 代码推到 GitHub | 浏览器 | 10 分钟 | 0 |
| ⑤ Codemagic 接入 + 首次构建 | 浏览器 | 30 分钟 | 免费额度 |
| ⑥ TestFlight 安装 | iPhone | 20–40 分钟 | 0 |

Codemagic 免费额度约 **500 分钟/月**，一次构建 8–15 分钟，够你迭代几十次。

---

## 1. 先决条件

- **Apple Developer Program**（$99/年）已审核通过 —— 没有它，Codemagic 也签不出证书
- **GitHub 账号**（免费）
- **App Store Connect 里已建好 App 记录**（这一步没法自动化）

如果 ① ② 还没做，先去 [cloud-mac.md](cloud-mac.md) 的第 1 节做完，两条路线的准备工作完全一样。

---

## 2. 生成 App Store Connect API Key（最关键的一步）

Codemagic 靠这个 key 去苹果服务器自动创建证书和描述文件，**没有它整个流程走不通**。

1. 打开 <https://appstoreconnect.apple.com> → 右上角 **用户和访问 (Users and Access)**
2. 顶部切到 **集成 (Integrations)** 标签
3. 左侧选 **App Store Connect API** → 点 **团队密钥 (Team Keys)** 下面的 **＋**（或 "生成 API 密钥"）
4. 填：
   - **名称**：`Codemagic`
   - **访问权限**：**App 经理 (App Manager)**（想省事选 Admin 也行）
5. 点 **生成**，然后**立刻点「下载 API 密钥」**——`.p8` 文件**只能下载一次**，关掉页面就再也拿不到，只能重新生成

记下页面上的三个值：

| 名称 | 长什么样 | 在哪 |
| --- | --- | --- |
| **Issuer ID** | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | 密钥列表正上方，整个团队共用一个 |
| **Key ID** | `ABCDE12345`（10 位） | 密钥列表里那一行的 "密钥 ID" |
| **API 密钥文件** | `AuthKey_ABCDE12345.p8` | 刚下载的那个文件 |

> 把 `.p8` 存好。丢了不影响已配置的构建，但重新配就得重新生成一把 key。

---

## 3. 把工程推到 GitHub

### 3.1 建仓库

1. <https://github.com> → 右上 **＋** → **New repository**
2. 名称 `filmsim`，选 **Private**（私有，只有你能看）
3. **不要**勾 "Add a README file"（保持空仓库）→ Create

### 3.2 上传代码（网页操作，不用装 Git）

1. 在新仓库页面点 **uploading an existing file**（或 Add file → Upload files）
2. 把本地 `filmsim` 文件夹**里面的内容**（不是文件夹本身）拖进虚线框：
   ```
   codemagic.yaml      ← 必须在仓库根目录，Codemagic 才认
   project.yml
   ExportOptions.plist
   README.md
   .gitignore
   FilmSim/            ← 整个文件夹
   scripts/
   docs/
   ```
3. 底部 Commit changes

✅ **检查**：仓库首页的文件列表里能直接看到 `codemagic.yaml` 和 `FilmSim` 文件夹。
如果变成 `filmsim/codemagic.yaml`（多套了一层），Codemagic 会找不到配置——把文件挪到根目录，或者删掉重传。

> 网页拖拽文件夹时如果丢失目录结构，改用 GitHub Desktop 或者 `git` 命令行推上去更稳。

---

## 4. 接上 Codemagic

### 4.1 注册并添加应用

1. <https://codemagic.io> → **Sign up with GitHub** → 授权
2. 左侧 **Applications** → **Add application**
3. 选 **GitHub** → 找到刚建的 `filmsim` 仓库 → **Check repository**
4. 项目类型选 **Native iOS**（或 "Other"）→ 下一步
5. Codemagic 检测到仓库里有 `codemagic.yaml`，会提示使用该配置——**选它**，别用自动生成的脚本

### 4.2 填 API Key

1. 左侧回到 **Teams** → 选你的团队 → **Integrations**
2. 找到 **App Store Connect**（有的界面在 "Developer Portal" 分组下）→ **Add key**
3. 填：
   - **Issuer ID**：第 2 节的 Issuer ID
   - **Key ID**：第 2 节的 Key ID
   - **API Key (.p8)**：上传那个文件
   - 名称随便，例如 `ASC`
4. 保存

> ⚠️ 这个 key 必须加在 **Team 级别**（不是在 App 的环境变量里），否则 `ios_signing` 自动签名不会生效。

### 4.3 改成你自己的 Bundle ID

在 GitHub 网页上直接编辑 `codemagic.yaml`（铅笔图标），把两处 `com.yourcompany.filmsim` 换成你的：

```yaml
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.zhangsan.filmsim   # ← 改这里

      vars:
        BUNDLE_ID: "com.zhangsan.filmsim"          # ← 和这里
```

**同时**改 `project.yml` 里的：

```yaml
        PRODUCT_BUNDLE_IDENTIFIER: com.zhangsan.filmsim
```

三处（加 App Store Connect 里的记录）必须**完全相同**。改完 Commit。

---

## 5. 第一次构建

1. Codemagic 里进入这个 App → 右上 **Start new build**
2. Branch 选 `main`（或你的默认分支）
3. Workflow 选 **FilmSim → TestFlight**
4. **Start new build**

构建分 4 步，总共 8–15 分钟：

| 步骤 | 干什么 | 耗时 |
| --- | --- | --- |
| 安装 XcodeGen 并生成工程 | `brew install xcodegen` + `xcodegen generate` | 1–2 分钟 |
| 设置 build 号 | `agvtool new-version -all $BUILD_NUMBER`，每次自动 +1 | 5 秒 |
| 应用签名描述文件 | 用 API Key 拉证书，写进工程 | 10–30 秒 |
| 打包 ipa + 上传 | `xcodebuild archive` + 上传 App Store Connect | 5–10 分钟 |

日志是实时滚动的，**最后出现 `Build successfully published` 或 `Uploaded to App Store Connect` 就是成功了**。

---

## 6. 构建失败怎么读日志

| 日志里的关键字 | 原因 | 怎么修 |
| --- | --- | --- |
| `Invalid codemagic.yaml` | 缩进错了（YAML 对空格敏感，不能用 Tab） | 按报错行号改，或从仓库重新复制一份 |
| `brew: command not found` | 极少见，镜像异常 | 重新构建一次 |
| `xcodegen: command not found` | 上一步装失败了 | 看上一段日志；实在不行改用 `mint run yonaskolb/xcodegen` |
| `No matching profiles found for bundle identifier` | 三处 Bundle ID 不一致 | 检查 yaml / project.yml / App Store Connect |
| `Failed to create certificate` / `maximum number of certificates` | 证书到上限（每个账号有数量限制） | <https://developer.apple.com/account> → Certificates → 撤销旧的 |
| `Authentication failed` / `401` | API Key 填错 / 过期 | 重新检查 Issuer ID、Key ID、.p8 是否配对 |
| `The requested app is not available` | App Store Connect 没建 App 记录 | 回第 1 节 |
| `agvtool` 报 `Cannot find VERSIONING_SYSTEM` | 工程的 `project.yml` 是旧版 | 确认 `project.yml` 里有 `VERSIONING_SYSTEM: apple-generic` |
| `Provisioning profile doesn't include the ...` | 描述文件类型不对 | 确认 `distribution_type: app_store` |
| 编译报错（Swift 语法） | 代码问题 | 把日志里 `error:` 那几行发我 |

失败后可以点构建详情里的 **Download artifacts** 或看 **xcodebuild log**，把报错贴出来最快。

---

## 7. 等 TestFlight

构建成功 ≠ 马上能装，苹果还要处理 5–30 分钟：

1. <https://appstoreconnect.apple.com> → 你的 App → **TestFlight** → **Builds**
2. 状态从「处理中 / Processing」变成可用
3. 把自己加成内部测试员：
   - **用户和访问** → 邀请自己（角色 Developer）→ 邮件里接受
   - App → TestFlight → **内部测试** → 建组 → 把这个 build 加进去
4. iPhone 上装 **TestFlight** App → 登录同一 Apple ID → 安装

> 内部测试不需要 Beta 审核。外部测试才需要，且首个 build 要审 1–2 天。

---

## 8. 改完代码怎么重新出包

1. GitHub 网页上改文件（或重新上传改过的文件）→ Commit
2. Codemagic → **Start new build** → 同一 workflow
3. build 号会自动 +1，不会因为「build 号重复」被拒
4. 10 分钟后 TestFlight 里出现新 build，手机上 TestFlight 里点更新

想让它 push 后自动构建，在 `codemagic.yaml` 的 `workflows.ios-testflight` 下加：

```yaml
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
```

---

## 9. 免费额度够不够

| 项 | 数值 |
| --- | --- |
| 免费额度 | 约 500 分钟/月 |
| 单次构建 | 8–15 分钟 |
| 每月可构建 | 30–60 次 |

个人迭代完全够。真要超了，Codemagic 的付费也是按分钟买，比租 Mac 便宜。

---

## 10. B 路线 vs A 路线

| | A：租云 Mac | B：Codemagic |
| --- | --- | --- |
| 要不要 Mac | 要（租的） | 不要 |
| 第一次上手 | 1.5–2 小时，要会点 Xcode | 30 分钟配好，纯网页 |
| 能不能看界面 | 能（模拟器 + 测试图） | 不能，只能等 TestFlight |
| 报错能不能现场改 | 能 | 只能看日志，改完重新构建 |
| 后续迭代成本 | 每次都要租机器 | 点一下，免费 |
| 适合 | 想一次搞定、要看界面 | 能照着文档走、以后要反复改 |

**建议**：如果你打算继续改进这个 App（大概率会），B 更划算；如果只想尽快看到它在手机上跑起来、中间出问题有人能现场处理，A 更稳。两条路互斥，也可以先 A 后 B——证书和 App 记录是通用的。
