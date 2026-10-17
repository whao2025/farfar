# 鸿蒙 7.0（API 26）适配方案

> 编写：2026-10-18 · 状态：方案已定，**阻塞于工具链**（本机未安装 HarmonyOS SDK 26.0.0）

## 0. 事实基线（官方，2026-10）

| 项 | 值 | 来源 |
|---|---|---|
| HarmonyOS 7.0 对应 API | **26.0.0**（语义化版本，X.Y.Z） | 版本号格式调整说明 |
| SDK 正式发布 | HarmonyOS SDK 26.0.0 Release（基于 OpenHarmony Ohos_sdk_public 26.0.0.105），2026-08-29 | 版本概览 |
| DevEco Studio | 26.0.0 Release **26.0.0.851**（Patch，2026-09-23）；基线 .821（2026-08-29） | 新增和增强特性 |
| 配套 Hvigor | 6.26.8（.821 为 6.26.4） | 同上 |
| 配套 ohpm | 26.0.0.630 | 同上 |
| 配套 Node.js | 24.14.1（当前 6.1.1 为 18.20.1） | 同上 |
| IDE 底座 | IntelliJ 2026.1.1 + JDK 25（默认新 UI） | IDE 变更说明 |
| modelVersion | **26.0.0** | 同上 |
| compileSdkVersion | **26.0.0**（固定） | 同上 |
| targetSdkVersion | 4.0.0(10) ~ 26.0.0 | 同上 |
| compatibleSdkVersion | 最低 4.0.0(10) | 同上 |

**本机现状**：DevEco Studio 6.1.1.290（SDK 24 / HarmonyOS 6.1.1）、Hvigor 6.24.3、Node 18.20.1；
工程 `build-profile.json5` 为 `targetSdkVersion/compatibleSdkVersion = 6.1.1(24)`，`modelVersion = 5.0.0`。
**SDK 26 内嵌在 DevEco Studio 安装包中，只能随 IDE / Command Line Tools 一起获取（下载中心需登录华为账号）。**

## 1. 前置：工具链升级（必须，当前唯一阻塞项）

1. 安装 **DevEco Studio 26.0.0 Release（26.0.0.851）**：
   - 下载中心 → DevEco Studio（登录华为账号）→ Windows 版；安装后 SDK 自动内置（`<IDE>\sdk\default`）。
   - 或安装同版本 **Command Line Tools 26.0.0.851**（同样内嵌 SDK，适合 CLI 构建）。
2. 验证：IDE 菜单 `Help > About DevEco Studio` 应显示 26.0.0.851；`Help > About HarmonyOS SDK` 应显示 26.0.0 Release。
3. 本工程 CLI 构建脚本 `scripts/build.ps1` 的 `DEVECO_SDK_HOME` 指向 `<DevEco Studio>\sdk`，装到默认路径则无需改；换路径需同步脚本。

> ⚠️ API 25 不存在官方发布版本，不要使用。

## 2. 工程配置改动（**已应用，2026-10-18**）

| 文件 | 字段 | 原值 | 新值 | 状态 |
|---|---|---|---|---|
| `build-profile.json5` | products.default.targetSdkVersion | `6.1.1(24)` | `26.0.0` | ✅ 已改 |
| `build-profile.json5` | products.default.compatibleSdkVersion | `6.1.1(24)` | **保持 `6.1.1(24)`**（用户决策：继续支持鸿蒙 6.x） | ✅ 不变 |
| `hvigor/hvigor-config.json5` | modelVersion | `5.0.0` | `26.0.0` | ✅ 已改（该文件被 .gitignore 忽略，仅本地生效） |
| `oh-package.json5` | modelVersion | `5.0.0` | `26.0.0` | ✅ 已改 |
| `AppScope/app.json5` | minAPIVersion / targetAPIVersion | `23` / `24` | **无需手改** | 官方文档：这两个字段“在应用编译构建时自动生成，手动配置无效”，分别由 build-profile 的 compatibleSdkVersion / targetSdkVersion 生成 |
| `build-profile.json5` | products.default.signingConfig | `debug` | 出正式包时切 `release`（见 PUBLISH_GUIDE） | ⏳ 未动 |

注：升级后 Hvigor 为 **6.26.8**，必须用 **DevEco 26 自带 hvigor** 构建；旧的 6.24.3 会直接拒绝 modelVersion 26.0.0。

### 当前进度：✅ **API 26 构建已通过（2026-10-18）**

工具链已就绪：**DevEco Studio 26.0.0.851** 安装于 `D:\DevEcoStudio26`（SDK 26.0.0 / Hvigor 6.26.8 / Node 24.14.1），与旧版 6.1.1 + SDK 24 **并存**（旧版未动，可回退）。
`scripts/build.ps1` 已改为**自动探测** DevEco 安装路径（优先 `D:\DevEcoStudio26`，回退 `C:\Program Files\Huawei\DevEco Studio`），可用 `-DevEcoHome` 覆盖。

构建结果（`build.ps1 -Mode release -Clean`）：

```text
DevEco: D:\DevEcoStudio26 (SDK: HarmonyOS 26.0.0)
> hvigor BUILD SUCCESSFUL in 20 s 100 ms
BUILD release SUCCESS
WARN 0 / ERROR 0
```

产物 `entry/build/default/outputs/default/entry-default-signed.hap`（8.68MB），`pack.info` 校验：
`"apiVersion":{"compatible":24,"releaseType":"Release","target":26}` —— 与“target 26 + 兼容 24”策略一致。

### 升级过程中遇到并已解决的 3 个问题

1. **Hvigor 6.24.3 拒绝 modelVersion 26.0.0**（`00303028`）→ 升级 IDE 后消失（Hvigor 6.26.8）。
2. **SignHap `00308018` / `ENOENT: no such file or directory, stat 'D:\freepdf\material'`**
   → 根因：DevEco 6+ 将签名密码的**解密密钥放在项目根 `material/` 目录**（5 个 16–48 字节文件），hvigor 的 `DecipherUtil.getKey` 会 stat 该目录；清理 git 历史时该目录被误删 → 从备份恢复后签名通过。
   ⚠️ **`material/` 绝对不能删**（.gitignore 忽略可以，但本地必须保留）。
3. **API 26 编译器告警 3 条**：`PDFEditPage.ets` 高亮色选择器用 `Circle().fill()/.stroke()`，SDK 26 为 CircleAttribute 新增了 `fill/stroke(ResourceColor|ColorMetrics)` 重载（@since 26.0.0），在 compatible=24 下告警 → 改为 `Column` + `borderRadius/backgroundColor/border` 实现同视觉，**WARN 归零**。

### 回滚（回到 6.x 基线）
```bash
git checkout -- build-profile.json5 oh-package.json5
# 并把 hvigor/hvigor-config.json5 的 modelVersion 改回 5.0.0
```
旧 IDE 与 SDK 24 仍在 `C:\Program Files\Huawei\DevEco Studio`（未改动）。

## 3. API 26 行为变更影响分析（已逐条对照本工程源码）

来源：官方《26.0.0 的行为变更汇总》/ `changelogs-for-all-apps-7001/7002/7003`、`changelogs-ux-7001`。

| 变更 | 生效规则 | 本项目影响 | 处理 |
|---|---|---|---|
| Image 组件 autoResize 默认行为变更 | 全部生效 | **无**：全工程未使用 `Image` 组件（PDF 渲染走 PdfView） | 无需处理 |
| 阴影模糊半径 radius=0 语义变更 | target ≥ 26 | **无**：`GlassTokens.SHADOW` radius=16；但 target 升级后需真机目检阴影浓淡 | 真机目检 |
| 沉浸光感新增生效约束 | target ≥ 26 | **无**：未使用 systemMaterial / ImmersiveMaterial（本工程用 backgroundBlurStyle+手绘 halo） | 无需处理 |
| Dialog/Toast/AlphabetIndexer/文本菜单默认开启沉浸式系统材质 | target ≥ 26 | **⚠️ 有**：使用 `openCustomDialog`（RecentFilesPanel 删除确认）+ 全局 `showToast`；升级后系统会叠加沉浸材质，可能出现过厚/双材质观感 | 真机核对；必要时显式设置弹窗背景/材质参数 |
| 表单类组件触摸热区最小 28→32vp | target ≥ 26 | **无**：未用 `ControlSize.SMALL` 的 Button、按钮式 Toggle、Chip/ChipGroup、Select；Toggle 用的是 Switch | 无需处理 |
| 半模态居中弹窗最大高度变更 | target ≥ 26 | **无**：未使用半模态 | 无需处理 |
| 沙箱 /storage/Users/currentUser/appdata 下 stat/access 权限收紧 | target ≥ 26 | **无**：未硬编码该路径，全部走 context.filesDir / 沙盒相对路径 | 无需处理 |
| READ_IMAGEVIDEO 可读媒体库范围变更 | 全部生效 | **无**：图片入口全部是 `photoAccessHelper.PhotoViewPicker`（免权限），未申请该权限 | 无需处理 |
| 部分公共事件（包安装/卸载等）增加管控 | target ≥ 26 | **无**：未订阅任何公共事件 | 无需处理 |
| KernelPermission/ bin 独立进程权限策略 | target ≥ 26 | **无**：纯 ArkTS 应用，无 bin/内核权限 | 无需处理 |
| JSVM Chromium/v8 132→144、ArkWeb 144 | 全部生效 | **无**：未使用 Web 组件 / wasm | 需编译回归 |
| async 函数类型判定修复 | 全部生效 | **低风险**：需全量编译+回归（本项目大量 async） | 编译验证 |
| ArkUI：LayoutPolicy.matchParent / WithTheme / NodeAdapter / EmbeddedComponent / NavDestination / List 事件 / 鼠标 rawDelta / Swiper 事件 | 混合 | **无**：源码 grep 均未使用 | 无需处理 |
| Core File / I18n / MDM 错误码 string→number | target ≥ 26 | **无**：未使用 I18n/MDM；Core File 只用 filesDir 常规读写 | 无需处理 |

**结论：代码层面基本没有“必改”项**；风险集中在 ①Dialog/Toast 默认沉浸材质（视觉）②阴影/玻璃观感的真机核对 ③新编译器（ArkTS 26）可能新增告警/错误。真正的工作量 = 工具链 + 配置 + 编译修复 + 真机回归。

## 4. 编译与修复流程（装好 IDE 后）

1. 备份：`git status` 确认工作区（当前 28 项未提交，先提交或 stash）。
2. 用 DevEco 26 打开工程 → 接受工程迁移（hvigor/modelVersion）→ 核对第 2 节表格。
3. CLI：`scripts/build.ps1 -Mode release -Clean`，预期先出一批新告警/错误，逐条修。
4. IDE `Tools > API Change Assistant`：对比 SDK 24 → 26，扫描行为变更并按其 Guidance 链接核对（本方案第 3 节已预判无必改）。
5. `codelinter`（26 新版）全量扫描，清零 warning。
6. 构建通过后跑：`node scripts/verify_parser.js`、`node scripts/verify_rewrite.js`、`python scripts/verify_docs.py`。

## 5. 验证清单

- 新设备（HarmonyOS 7.0 / API 26）：安装+启动 → TEST_CHECKLIST 7 项 → 图片记账 G1-G11 → 多选改字（单块/批量/撤回）→ 深色模式 → 弹窗/Toast 观感（重点）。
- 老设备（HarmonyOS 6.x）：同链路冒烟（compatibleSdkVersion 保持 24 时必须验）。
- 无设备时可用 DevEco 26 自带 **HarmonyOS Emulator 26.0.0.402** 做首轮冒烟，再上真机。
- 记录结果到 `docs/TEST_CHECKLIST.md`（当前 7 项核心项尚未勾选，`verify_docs.py` 会因此报错）。

## 6. 风险与回滚

- 风险：新 ArkTS 编译器更严格（历史上 153 警告清零过一次，需再清）；Dialog/Toast 观感变化；Hvigor 6.26.8 与旧工程 modelVersion 不兼容。
- 回滚：`git checkout -- build-profile.json5 hvigor/hvigor-config.json5 oh-package.json5 AppScope/app.json5`，并用 DevEco 6.1.1 打开旧工程；SDK 24 工程不受影响。
- 建议在独立分支 `harmonyos7` 上做迁移，验证通过后合并 master。

## 7. 待确认决策

1. compatibleSdkVersion：保持 `6.1.1(24)`（继续支持鸿蒙 6.x，推荐）还是设为 `26.0.0`（仅 7.0+）？
2. 是否同时把 release 签名链与版本号（当前 app.json5 = 1.0.0/1000000，CHANGELOG = 0.5.1）在对齐到 v0.6/1.0 时一并处理？
