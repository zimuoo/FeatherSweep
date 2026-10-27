<div align="center">
  <img src="Resources/AppLogo.png" width="96" alt="FeatherSweep Logo" />
  <h1>轻扫 · FeatherSweep</h1>
  <p><strong>给 Mac 腾出空间，也给自己留一份安心。</strong></p>
  <p>原生 macOS 定向清理工具 · 小窗口 · 菜单栏常驻</p>
  <p>
    <a href="https://github.com/zimuoo/FeatherSweep/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/zimuoo/FeatherSweep?style=flat-square&color=007AFF" /></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&amp;logo=apple&amp;logoColor=white" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple_Silicon-arm64-007AFF?style=flat-square" />
    <img alt="DMG 1.4 MB" src="https://img.shields.io/badge/DMG-1.4_MB-007AFF?style=flat-square" />
    <img alt="Native SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native-FA7343?style=flat-square&amp;logo=swift&amp;logoColor=white" />
    <img alt="32 local safety tests" src="https://img.shields.io/badge/safety_tests-32_passed-22A06B?style=flat-square" />
  </p>
  <p><a href="https://github.com/zimuoo/FeatherSweep/releases/latest/download/FeatherSweep-1.0.0-arm64.dmg"><strong>下载 DMG 安装包</strong></a> · <a href="README.en.md">English</a> · <a href="#开发与验证">开发说明</a></p>
</div>

---

## 一眼看懂，轻松清理

轻扫把常见的开发缓存、历史快照和重复打包文件集中到一个小窗口。先点 **查看垃圾**，展开明细确认路径，再点 **清理垃圾**。窗口关闭后，它会安静留在菜单栏，需要时随时唤回。

<p align="center">
  <img src="docs/images/overview.png" width="460" alt="轻扫原生小窗口：可清理空间、六类明细和两个主要操作" />
  <br /><sub>实机原生界面，截图使用演示数据，不代表当前磁盘扫描结果。</sub>
</p>

### 轻巧，也足够认真

| | 体验 |
|---|---|
| **原生小窗口** | SwiftUI / AppKit 构建，无第三方运行时；本次 DMG 约 **1.4 MB**，以 Release 文件为准。 |
| **两步完成** | 查看路径与原因 → 重新校验后清理。启动时不会自动删除文件。 |
| **菜单栏常驻** | 关闭主窗口继续运行；可打开窗口、查看垃圾、清理或退出。 |
| **细腻动效** | 扫描环、数字过渡、清理粒子与完成动画，支持“减少动态效果”。 |
| **完全本地** | 无需账号，不发起网络请求，不上传文件内容。 |
| **明确保护** | 浏览器密码、Cookie、登录状态、源码、正式发布文件及最新场景备份均保留。 |

## 下载与安装

1. 在 [Releases](https://github.com/zimuoo/FeatherSweep/releases/latest) 下载 `FeatherSweep-1.0.0-arm64.dmg`。
2. 打开 DMG，将 **轻扫.app** 拖入 **Applications**。
3. 从“应用程序”打开 **轻扫**，点击 **查看垃圾**。

**系统要求：** Apple Silicon（M 系列芯片），macOS 14 或更高版本。本次 Release 为 arm64 本机版。

> 当前版本使用本机 ad hoc 签名，尚未取得 Apple Developer ID 公证。从互联网下载后，macOS 可能要求确认应用来源；请仅使用本仓库的 Release。不会要求关闭 Gatekeeper 或安装 root 辅助程序。

可同时下载 `SHA256SUMS.txt` 校验安装包：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## 只清理这些内容

| 分类 | 识别范围 | 始终保留 |
|---|---|---|
| **Go / Rust 编译缓存** | 具有 Go 标准缓存标记的目录、指定项目的 Rust 编译中间目录 | 源码、Go 模糊测试语料、可运行的 Rust 程序 |
| **Cursor 旧快照** | 历史代码快照、可重建的聊天搜索索引 | 设置、插件、主状态数据库与登录数据 |
| **打包与签名副本** | `yisora/artifacts` 内已识别的解压副本；与发布包 SHA-256 相同的多余文件；闲置浏览器签名副本 | 正式发布安装包、验证记录、正在使用及最新的签名副本 |
| **过期更新下载** | 比已安装版本旧的 Cursor 更新、重复或过时的 Telegram 更新下载 | 已安装应用、最新待安装下载 |
| **应用静态缓存** | Chrome 中已识别的飞书 / Cloudflare 静态资源 | 密码、Cookie、IndexedDB、Local Storage、会话及登录状态 |
| **Blender 旧备份** | Agent Bridge 已识别的场景检查点 | **每个场景修改时间最新的 1 份备份** |

规则来自实际目录核对，不使用“文件夹名称像垃圾就删除”的泛化策略。项目缓存规则以当前用户主目录为基础，部分规则对应 `Desktop/docker/yijun_project` 中已确认的项目；换一台 Mac 时，不存在的目录会自然跳过。

**不会批量清空“下载”目录或删除全部 DMG，也不会清理有效模型、SDK、项目仓库或整个浏览器用户目录。**

## 清理前，会再检查一遍

```mermaid
flowchart LR
    A[只读扫描] --> B[展示路径与原因]
    B --> C[重新核对占用与元数据]
    C --> D[按白名单清理]
    D --> E[报告完成、跳过与部分结果]
```

- 文件正在使用、编译仍在运行或 Cargo 编译锁被占用时跳过。
- 扫描结果超过 30 分钟、文件身份或目录元数据发生变化时拒绝沿用旧结果。
- 使用目录文件描述符与 `O_NOFOLLOW` 逐级处理路径，防止符号链接逃逸。
- 删除重复安装包前，校验内容 SHA-256，并再次确认正式保留文件未变化。
- 占用检查不完整时停止清理；部分删除也会如实统计。
- APFS 签名副本的共享空间不计入字节估算，避免出现虚假的 TB 级回收数字。
- 仅在本地保留最近 20 次清理的汇总计数，不记录文件内容。

> **清理会直接移除通过复核的文件，不进入废纸篓。** 请先展开明细确认范围。若 macOS 拒绝目录访问，轻扫会跳过并显示原因；无需 root 权限。

## 开发与验证

```sh
git clone https://github.com/zimuoo/FeatherSweep.git
cd FeatherSweep

# 全部测试只在临时目录构造样本
swift test --scratch-path /private/tmp/feathersweep-test-build

# 生成本机 arm64 DMG
bash scripts/build.sh
```

打包脚本使用系统 Swift、AppKit、`iconutil`、`codesign` 与 `hdiutil`。每次构建使用独立的 `dist/.feathersweep-build.XXXXXX` 临时目录，完成后移除；校验后的 DMG 原子发布到 `dist/`。无需下载依赖。

安全演示与真实只读诊断：

```sh
# 只使用示例数据，清理按钮仅模拟，不会删除真实文件
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --demo

# 真实只读扫描，JSON 输出到终端；不会执行清理
"/Applications/轻扫.app/Contents/MacOS/FeatherSweep" --scan-json
```

32 项本地测试涵盖：凭据与源码保留、只读扫描、文件变化跳过、符号链接保护、Cargo 锁、使用中途打开文件、Blender 场景名边界、签名副本保留顺序、重复包引用保护、静态缓存识别及部分清理统计。

<details>
<summary><strong>项目结构</strong></summary>

```text
Sources/
├── CleanerCore/       # 扫描规则、保护校验与原生删除
└── FeatherSweep/      # 小窗口、动效、菜单栏与矢量 Logo
Tests/                 # 临时目录安全回归测试
Resources/             # 原创 Logo、ICNS 和多分辨率图标
scripts/               # 图标渲染与 DMG 打包
docs/                  # 设计说明与界面截图
```

</details>

## 常见问题

**为什么可清理空间比文件的逻辑大小小？** 轻扫优先按实际分配块估算；APFS 克隆、硬链接和并发磁盘活动仍会影响最终空间变化，清理后会分别显示移除文件大小与磁盘可用空间变化。

**为什么某些项目被跳过？** 通常是正在使用、发生变化、无访问权限，或不满足已确认的规则。展开提示可以看到原因；重新扫描即可核对最新状态。

**关闭窗口后如何退出？** 点菜单栏中的轻扫图标，选择“退出 轻扫”。

**支持 Intel Mac 吗？** 当前公开安装包为 Apple Silicon arm64 版本；本仓库尚未提供或验证 Intel 安装包。

---

<p align="center"><sub>轻扫 FeatherSweep · 体积轻，边界清楚。</sub></p>
