# freepdf 上架华为应用市场指南

## 概览
- 应用名：freepdf（⚠️ 建议 AGC 提交时使用带品牌辨识度的名称，如「freepdf 阅读器」；纯 "PDF" 行业词可能被判定为广义功能名）
- 包名：com.freepdf.app
- 格式：HarmonyOS NEXT (.app)
- 目标平台：phone / tablet / 2in1
- 最低 API：23 (6.1.0)
- 编译/目标 API：24 (6.1.1)
- 纯本地应用，无联网、无支付、无第三方 SDK
- 无需 ICP 备案（单机 APP）
- 不申请任何敏感权限（PDF 文件经系统文件选择器访问）

---

## 上架前本地准备

### 1. DevEco Studio 环境配置

**首次配置：**

| 配置项 | 路径 | 设置 |
|---|---|---|
| JDK | `Settings → Build, Execution, Deployment → Build Tools → Gradle` | 使用 DevEco Studio 自带 JDK |
| HarmonyOS SDK | `Settings → SDK` | 6.1.1 (apiVersion 24) |
| local.properties | `File → Project Structure → SDK Location` | 自动生成，确认 SDK 路径 |

**Sync 项目：**
- `File → Sync Project with Gradle Files`
- 等待 `hvigor/` 和 `hvigor-wrapper/` 自动生成

---

### 2. 签名证书（四件套）
按顺序执行：

1. **生成 .p12 密钥库**
   - DevEco Studio → `Build → Generate Key and CSR`
   - Key Store File：`freepdf.p12`（DevEco 生成的 .p12；`.keystore` 扩展名已被签名工具拒绝——报 `11012005 Not support file`，勿再用）
   - 密码：至少 8 位，含大小写+数字+符号
   - Key Alias：`freepdf_release`
   - 有效期：建议 25 年

2. **申请发布证书**
   - 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/agc/)
   - 证书管理 → 新增证书 → 上传 `.csr`
   - 下载 `.cer` 证书

3. **创建 Profile (.p7b)**
   - AGC → HAP Provision Profile → 新增
   - 类型：发布 (release)
   - 关联步骤 2 的发布证书
   - Bundle Name 必须完全匹配 `com.freepdf.app`
   - 权限列表：无（应用不申请任何权限）
   - 下载 `.p7b`

4. **DevEco Studio 配置签名**
   - `File → Project Structure → Signing Configs`
   - Store File、Key Alias、密码、Profile (.p7b)、Cert (.cer)
   - 不要勾选 `Automatically generate signature`（自动生成会创建新密钥，导致 .cer/.p7b 失效）；手动选入已有 .p12/.p7b/.cer，IDE 会自动加密密码并生成 `material/` 目录（明文密码无法通过校验——报 `00303116`）

5. **验证 release 构建（官方硬指标，缺省即驳回）**
   - ✅ 当前状态（2026-08-03 完成）：签名已配置成功，release 构建产出 `D:\freepdf\build\outputs\default\freepdf-default-signed.app`（173,780 字节，bundleName com.freepdf.app 已核对）；重构后已复验签名 verify-app success
   - 签名材料在项目根目录：`freepdf.p12`、`freepdf_release.cer`、`freepdf_releaseRelease.p7b` + 自动生成的 `material/` 目录；备份在 `D:\freepdf_signing_backup\`
   - `build-profile.json5` 中密码为 IDE 加密串（`0000001C...`，≥32 位偶数），**勿改回明文**
   - 建议密码改用环境变量（`storePasswordEnv`/`keyPasswordEnv`），避免明文入库（可选）
   - 构建：`Build → Build Hap(s)/APP(s)`，Build Mode 选 **release**（官方：发布版 debug 属性必须为 false，app.json5 缺省即 false ✅ 已确认）
   - 注意：debug 构建也会带发布证书签名（products 固定绑定 release signingConfig），本地联调勿误用正式证书

### 3. 运行验证

在发布前先在 Mate 70 上跑通：

1. **连接设备**
   - Mate 70 → 设置 → 开发者选项 → USB 调试
   - USB 连接电脑，选择"仅充电"模式下允许 ADB
   - DevEco Studio → `Device Manager` 可见设备

2. **Trust Project**
   - 首次运行 DevEco Studio 打开项目 → Trust Project
   - 确认 SDK 配置 → Sync Now

3. **运行**
   - `Run → Run 'entry'`
   - 选择 Mate 70 设备

4. **检查日志**
   - `Logcat` 面板查看运行日志

---

### 4. 完善隐私政策（方案 A：AGC 隐私托管，代码侧已实施 ✅）

**代码侧已完成**：自定义隐私弹窗（PrivacyDialog）已移除，`EntryAbility.ets` 集成 `@kit.AppGalleryKit` 的 `privacyManager.requestAppPrivacyConsent`（系统标准化弹窗；错误码 `1006700003` 表示未开通托管/模拟器，降级放行）。应用包内不再含隐私 HTML。

**AGC 侧配置（待托管开通）**：
1. 发邮件到 `agconnect@huawei.com` 申请开通标准化隐私声明托管服务（标题格式 `[托管隐私声明]-freepdf-com.freepdf.app-[APP ID]-[Developer ID]`，1-3 个工作日对接）
2. 开通后 AGC → 版本信息 → 数据安全 → 隐私政策 → 在线编辑器撰写或上传 `docs/privacy-policy.html`
3. 保存后获得官方 HTTPS 链接
4. **将链接填入 `AppScope/privacy.json` 的 `privacyPolicyUrl` 字段**（未回填前不得提审，否则 AGC-RJ-001 驳回）
5. 用户协议：使用 `docs/user-agreement.html`，按 AGC 托管要求配置链接

**已废弃**：rawfile 本地隐私政策（文件已删除）、GitHub Pages 备用方案。

### 5. 准备商店素材

#### 应用图标（必做）
| 尺寸 | 路径 | 用途 |
|---|---|---|
| 216×216 PNG | `entry/src/main/resources/base/media/app_icon_216.png` | AGC 应用图标（无透明通道） |
| 512×512 PNG | `entry/src/main/resources/base/media/app_icon_512.png` | 图标源图（高清备用） |
| 1024×1024 PNG | `entry/src/main/resources/base/media/startIcon.png` | 启动图标 |

⚠️ AGC 图标上传 216×216 或 1024×1024 正方形 PNG（≤3MB，无透明通道，禁动图）。已生成 `app_icon_216.png`。如需按后台提示使用其他尺寸，以 AGC 实际要求为准。

需要补充 商店截图（3–5 张）：
- 在 Mate 70 上运行应用，截取关键界面：竖屏 720×1280（9:16）或 1080×1920，横屏 1920×1080（16:9）（以 AGC 后台实际提示为准）
- 截图 PNG/JPG ≤5MB / WEBP ≤200KB，禁动图，不得含状态栏或调试信息
- 截图内容必须与当前版本真实界面一致，且与提交语言一致（中文界面）
- 介绍视频（可选）：1–3 个，16:9 1280×720 或 9:16 720×1280，MOV/MP4 ≤500MB，15 秒–2 分钟

> ⚠️ 说明：特色图形 1024×500（`feature_graphic.png`）已生成备用，但华为官方素材规范中**无此素材类型**（为 Google Play 概念），以 AGC 后台实际表单为准，如无对应上传位可忽略。

#### 版本说明模板（≤ 500 字）
```
【更新内容】
- 新增 PDF 导入功能，支持从文件管理器选择 PDF 文件
- 新增 PDF 预览，支持单页显示、连续滚动、宽度适配
- 支持返回上一页重新选择文件
- 优化液态玻璃 UI 视觉效果
- 优化应用图标

【功能说明】
freepdf 是一款纯本地 PDF 阅读应用，所有数据处理均在设备端完成，不收集用户数据。
```

---

### 6. local.properties（首次配置）

如果 DevEco Studio 首次打开项目时没有自动生成 `local.properties`，手动创建：

文件路径：`D:\freepdf\local.properties`

```properties
sdk.dir=C\:\\Program Files\\Huawei\\DevEco Studio\\sdk\default\hms
```

⚠️ 路径需与实际安装位置一致。如果 DevEco Studio 安装在其他目录，请修改 `sdk.dir` 的值。

`.gitignore` 已排除 `local.properties`，不会被提交到版本库。

### 7. Mate 70 真机测试

#### 设备设置
1. Mate 70 → 设置 → 系统和更新 → 开发者选项
2. 开启 USB 调试
3. 开启 允许 ADB 安装（USB 调试模式下）

#### USB 连接
1. 用 USB 数据线连接 Mate 70 和电脑
2. 手机上弹出"允许 USB 调试？" → 点击确定
3. 手机选择"仅充电"模式（不要选"文件传输"）
4. DevEco Studio → Device Manager → 应显示 Mate 70 设备

#### 运行验证
1. DevEco Studio → Run → Run 'entry'
2. 选择 Mate 70 设备
3. 等待安装和启动
4. 验证以下功能：
   - 应用正常启动
   - 首次启动弹出系统隐私声明弹窗（AGC 托管内容，经 `privacyManager.requestAppPrivacyConsent`），同意/拒绝符合预期
   - "导入 PDF" 按钮拉出文件选择器
   - 选择 PDF 后能跳转到预览页
   - PDF 能正常渲染和翻页
   - 系统切换深色模式后，主页/预览页背景与文字随动（freepdf 已实现 `environment` 监听同步 AppStorage('darkMode')）
5. DevEco Studio → Logcat → 过滤 `harmonyos` 查看运行日志

#### 常见问题
- 设备不显示 → 确认 USB 驱动已安装，尝试换 USB 口
- 无法安装 → 确认调试模式已打开，信任电脑授权
- 白屏 → 确认 `local.properties` SDK 路径正确，Sync 项目

---

### 8. Release 构建与上传

#### 构建 Release 包

**方式一：DevEco Studio GUI**
1. `Build → Build Hap(s)/App(s) → Release`
2. 选择输出目录和签名配置
3. 构建完成后输出 `.app` 文件

**方式二：命令行**
```powershell
# 设置 SDK 路径（hvigor 运行必需）
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"

# 进入项目根目录
cd D:\freepdf

# 构建 Release 包（DevEco Studio 自带 hvigorw；项目级打包任务为 assembleApp，assembleRelease 不存在）
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleApp --mode project -p product=default -p buildMode=release --no-daemon

# 输出路径
build\outputs\default\freepdf-default-signed.app
```

**验证签名包**
```powershell
# 检查签名是否有效（如已配置签名）
& "C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe" -jar "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar" verify-app -inFile D:\freepdf\build\outputs\default\freepdf-default-signed.app -outCertChain D:\temp\chain.cer -outProfile D:\temp\profile.p7b
```

#### 上传到 AGC
1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/agc/)
2. 选择 freepdf 应用 → 版本信息
3. 点击"上传软件包"
4. 选择 `.app` 文件
5. **"使用场景"必须选"测试和正式上架"**（选"仅测试"将无法正式发布）
6. 填写：
   - 版本说明（≤ 500 字，使用上方模板）
   - 屏幕截图（3–5 张，竖 720×1280 / 横 1920×1080，≤5MB，禁动图）
   - 应用图标 216×216 PNG（无透明通道，≤3MB）
   - 勾选"单机 APP"
7. 提交前完成"AGC 提审前清单"（见下方章节），等合法性检测与上架自检通过后再点击"提交审核"

#### 上传后合法性检测（三态）
- **已达标**：可提交审核
- **待优化**：不阻塞提交，但存在驳回风险，建议优化后提交
- **不通过**：显示错误码（如 993），点击错误码链接查询对应 FAQ，修复后重新上传

#### 上架自检（官方推荐）
- 上传软件包后执行：真机兼容性、稳定性、性能、功耗、UX、隐私实测
- 结果以邮件通知；"待优化"项建议修复后再提审

#### 审核跟踪
- AGC → 应用 → 版本信息 → 查看审核状态
- 审核周期：工作日 16:00 前提交，1-3 个工作日
- 审核服务：官方支持"催审、1v1 专家沟通"等多重审核服务（AGC 后台发起）
- 被驳回：下载**审核报告与日志**，查看驳回原因，按照"常见驳回原因"修复后重新提交
- 审核通过但提示"需优化"：**必须在下个版本修复**后再更新

---

## AGC 提审前清单（提交审核前逐项确认）

1. **年龄分级问卷**：AGC → 内容分级 → 完成问卷（freepdf 预计 3+）。⚠️ **必须据实填写**：虚假陈述可致应用下架/开发者冻结；问卷更新后须重新填写才能上架；选 3/8/12 级需确认"是否仅面向儿童"（答"否"）
2. **隐私标签**：AGC → 数据安全 → "是否涉及个人信息收集"选"否"（freepdf 零收集）
3. **AI 功能声明**：无 AI 功能，选"不涉及"
4. **隐私政策网址 + 隐私权利网址**（两个独立字段）：均填独立 HTTPS 链接；隐私权利网址指向删除/导出数据入口（可复用隐私政策页锚点）
5. **应用信息**：
   - 名称：**必须与包内 app 名称一致**；≤15 个汉字（或 30 个英文/数字字符）；一个自然年内最多修改 2 次；中国大陆**不得与任何开发者的 HarmonyOS 应用/元服务重名**（重名可经互动中心申诉）
   - **图标必须与包内图标一致**（不一致即驳回点）
   - 分类/标签选"实用工具"（与 PDF 阅读功能相符）
   - 应用介绍 ≤8000 字；一句话简介中文 ≤17 字；新版本特性 ≤500 字
   - 文案与实际功能一致；不得含"适合幼儿/儿童"等字样；不得承诺未实现功能（如"编辑/批注/转化"）
6. **单机 APP 警告**：勾选"单机 APP"后，包内不得有任何联网调用、统计/崩溃上报 SDK——freepdf 为纯本地应用已满足；隐私声明由系统隐私弹窗（AppGalleryKit）展示，应用自身零联网调用
7. **签名**：确认签名四件套来自同一证书链，AGC Profile 权限列表为"无"
8. **上传后**：等待合法性检测"已达标" + 执行上架自检（官方《应用审核 Checklist》文档号 50170）后再提交

---

## 审核风险提示（提交前阅读）

### §3.5 功能单一驳回风险（PDF 类应用高发）
PDF 阅读器类应用可能被判定"功能单一、缺乏实质服务"而驳回。首次提审前建议：
- 已实现：PDF 导入 + 单页预览 + 连续滚动 + 宽度适配（真实可用，非空壳）
- 应用介绍中突出"纯本地、无联网、隐私安全"卖点

#### v2 差异化功能规划（上架后迭代，PDF Kit 能力已验证 ✅）
依据：桌面《移动应用设计方案》（Flutter 版 PDF 工具箱，思路参考非代码）+ 本机 SDK `@hms.officeservice.pdfservice.d.ts` / `@hms.officeservice.PdfView.d.ets` 核查。**全部能力均有 API 支撑**：

| 功能 | API 依据 | 说明 |
|---|---|---|
| PDF 合并 | `insertPageFromDocument(doc, fromIndex, pageCount, index)` (pdfservice:578) | 无专用 merge API，此接口组合实现 |
| PDF 拆分 | `createDocument(w,h)` (523) + `insertPageFromDocument` (578) + `saveDocument` (513) | 按页拆出独立文件 |
| 页面旋转 | `PdfPage.setRotation/getRotation` (1867/1874)，`RotationAngle` 0/90/180/270 | 保存后持久化写入文档 |
| 转图片 | `convertToImage(path, format, onProgress)` (630) 或 `PdfPage.getPagePixelMap()` (1881) | 全文档或单页导出 PNG/JPEG |
| 水印/页眉页脚 | `addWatermark` (716) / `addHeaderFooter` (683) | 整文档范围 |
| 文本搜索 | `searchKey` (pdfservice:789) | 查看器内搜索 |
| 缩略图 | `PdfController.getPagePixelMap(pageIndex, isSync?)` (PdfView:524) | 多文件管理/页面跳转 |

⚠️ **实现要点**：`PdfDocument.loadDocument`/`saveDocument` 为**同步 API**（pdfservice:497/513），UI 线程直调必卡死，必须走 taskpool/worker 线程。导出图片注意大文档内存（onProgress 反馈进度）。
- 已验证不可行：应用层"按需渲染（仅渲染可见页±1）"——PdfView 为黑盒组件，SDK 无光栅化/预加载/释放控制 API，伪优化，勿立项
- 低价值项：大文件分块流式读取（PDFImportUtils.ts 当前整块 ArrayBuffer 读入）——API 支持（fs ReadOptions offset/length），但收益仅为省一份全量 buf，<50MB 文件收益小，可推迟

### UI 规范自查（已按官方设计规范执行 ✅）
依据：华为官方设计规范（design.harmonyos.com 组件/字体/图标文档，以及 developer.huawei.com/consumer/cn/design 资源站）。
- 触控目标 ≥48vp：主操作按钮已 48vp（Home 导入 PDF）；工具栏次级按钮（返回 40vp/重新选择 44vp）属小尺寸辅助控件，列表行高/页签仍保持官方 48vp 体系
- 正文文字 ≥14fp：全应用已无 13fp（正文统一 ≥14fp，标题 18/20fp）
- 圆角体系：面板/卡片 20vp（官方 4/8/16/20/32vp 体系中取 20），按钮为胶囊（h/2），符合组件规范
- 间距 8vp 网格：内边距 16/24vp，均为 8vp 倍数 ✅
- 深色模式：已适配（colorModeChange 监听），真机验证深浅色切换正常
- 深色对比度：正文浅色 #F2F2F7 / 深色 #1A1A1F 对比，真机抽查可读性
- 玻璃材质分层（官方"沉浸光感"按场景分档）：
  - 工具栏（顶部悬浮）→ ULTRA_THIN（GlassTokens.BLUR_TOOLBAR）
  - 按钮 → THIN（BLUR_BUTTON）
  - 面板/卡片（非常驻浮层）→ THICK（BLUR_PANEL）
  - 页面根背景 → REGULAR（BLUR）
  - 弹层/半模态 → ULTRA_THICK（BLUR_MODAL，预留）
- 图标规范确认（官方）：图标为正方形、无圆角（系统自动遮罩裁切），背景层无透明像素，图形居中留安全边距——当前图标已满足 ✅

### 官方上架检测 FAQ（置顶精华帖，持续更新）
官方索引帖（应用市场官方账号，2025-12 发布持续更新）：https://developer.huawei.com/consumer/cn/forum/topic/0201200869157353958
共 89 个 FAQ 分帖，7 大专项：UX(18)/稳定性(5)/功耗(5)/性能(11)/兼容性(39)/安全(16)。

**与本项目直接相关的硬指标（已逐一对照 ✅/⏳）：**

| 硬指标 | 原文要点 | 状态 |
|---|---|---|
| 发布版 debug 属性 | app.json5 的 debug 必须为 false（缺省即 false），构建选 Build Mode=release，否则"存在被攻击安全隐患"驳回 | ✅ debug 缺省已确认；release 构建已完成并签名复验通过（verify-app success） |
| 权限清单必须指定 | 所有 hap/hsp/har 的 ReqPermissions 必须指定（可为空）；user_grant 权限 name/reason/usedScene 必填 | ✅ 零权限声明 |
| 禁止频繁申请权限 | 用户拒绝后不得循环弹窗、杀进程重进不得再弹、不得弹窗引导去系统设置 | ✅ 无任何权限申请 |
| bundleName 不可缺省 | 反域名形式命名 | ✅ com.freepdf.app |
| 必须有图标 | icon 字段不可缺省、资源必须真实存在 | ✅ 已生成 |
| 包结构规范 | AppPack 有且仅有一个 entry 类型 Hap，可带 0+ feature/shared | ✅ 单 entry |
| 深色模式 | 必须适配系统深色模式，未适配直接不符 UX 规范 | ✅ 已适配 |
| 应用崩溃 | 各界面遍历测试至少连续 8h 无 JsCrash/CppCrash；建议 Source Maps 归档、HiAppEvent 订阅 | ⏳ 真机待做（PDF 大文件 OOM 高发） |
| 卸载无残留 | 文件/数据/进程均须无残留 | ✅ 纯本地无沙箱外写入 |
| 个人信息标签一致性 | 隐私标签与实际行为一致 | ⏳ 上架时在 AGC 勾选"不收集个人信息" |

**官方预检工具（提审前建议跑一遍）**：DevEco Testing 应用上架预检（本地/云测黑盒测试）+ AppAnalyzer 诊断。
来源：上述分帖，官方入口 https://developer.huawei.com/consumer/cn/doc/app/50000-1

### 官方通知渠道（审核/驳回/投诉）
- **邮件为主**：审核结果、驳回、整改/下架通知均自动推送注册邮箱（联运协议规定联系不上后果自负），上架期间每天查邮箱
- **AGC 互动中心**：`https://developer.huawei.com/consumer/cn/service/josp/agc/index.html` → `#/interactive`：驳回详情、整改要求、客服沟通、申诉
- **站内消息**：个人中心"我的消息"（新地址 `https://developer.huawei.com/consumer/cn/message-center/myMessage/`），与邮件互为备份；"消息设置"中保持通知开启
- **申诉**：互动中心提交（附测试步骤与合规依据）；无 AGC 账号才发邮件 developer@huawei.com
- 用户侧投诉路径：应用详情页"内容举报"（隐私相关问题官方确认渠道）

### 鸿蒙应用开发者激励计划 2026（可选）
- 2026-09-30 前正式上架可报名，新应用奖励 3000 元/款
- 条件：任一自然月有效月活 ≥400、评分 >3 且 ≥10 条评价；需开通商户服务
- 入口：华为开发者联盟活动页"鸿蒙应用开发者激励计划 2026"

---

## 审核通过后的步骤

1. 选择发布策略（立即发布 / 定时发布）
2. 确认发布国家/地区
3. 等待审核（1-3 个工作日）
4. 审核通过后应用上架

---

## 上架后运营与发布策略

### 分阶段发布（灰度）——官方规则
- **适用前提**：仅当当前在架版本为"全网发布"时，**升级版本**才可用分阶段发布；**首次上架不适用**
- 节奏：7 天内每 24 小时按 1%→2%→5%→10%→20%→50%→100% 自动覆盖已开启自动更新的用户；覆盖范围内用户可被自动更新，所有用户均可主动搜索下载新版本
- 控制操作：
  - **暂停**：无需人工审核；最多累计暂停 30 天，第 31 天自动恢复
  - **恢复**：无需人工审核；暂停状态下不支持"加速更新"
  - **加速更新**：进度只能从 1% 跳到 2%（不能跳档至更大比例）
  - **申请下架**：需人工审核；下架后任何用户无法搜索到该应用
- 提审时可选：分阶段发布说明 1–500 字符（仅开发者可见）

### 质量监控（上架后义务）
- 每周查看 AGC 质量分析：崩溃/卡顿/ANR/启动耗时，崩溃服务提供最近 24 小时实时报告 + 崩溃提醒邮件
- 关注用户评价并回复（评价会影响激励计划"评分 >3 且 ≥10 条"条件）
- 崩溃率/ANR 阈值（如"8‰ 自动暂停分发"）在官方文档无明确数字，**以 AGC 控制台实际界面为准**
- 华为对应用质量问题有警告→下架阶梯处理机制（见官方 50109 处罚文档）

### 投诉与反馈渠道（供用户/开发者使用）
- 应用市场详情页"问题反馈"；应用市场"我的 > 帮助与客服 > 在线客服"
- 应用隐私类问题：用户通过应用详情页"内容举报"提交（官方确认渠道）
- 开发者被投诉后的处理通知：邮件 + AGC 互动中心（非邮件直达，见"官方通知渠道"章节）
- 注：早期版本记录的 devComplaint@huawei.com 邮箱未经官方文档证实，已不再引用

### 应用转移（信息性，小概率用到）
- 仅账号持有者可见"应用转移"按钮；支持跨站点转移
- 审核中（上架/升级/下架/回退）不可转移
- 需《应用转移申请表》+《应用转移自检表》盖章扫描件 + 转入方版权/版号资质，3 个工作日内处理
- 转入方须在 72 小时内提交应用审核并更新资质，否则华为有权下架；App ID 不变

---

## 常见驳回原因（避免踩坑）

> 软著提示：华为审核要求软著（软件著作权）主体与开发者账号主体一致。个人开发者可申请个人软著，需提前办理（周期约 1-3 个月），在 AGC 提交时上传；首次提审前建议先了解当前类目是否强制要求软著。

| 驳回代码 | 原因 | 修复 |
|---|---|---|
| AGC-RJ-001 | 隐私政策链接 404 或缺失 | 确保 URL 有效且有独立 HTTPS 页面 |
| AGC-RJ-002 | 权限过度申请或无场景说明 | 确保每个 permission 都有合理 reason |
| AGC-RJ-003 | 实名认证 / 资质缺失 | 个人开发者需完成实名认证 |
| AGC-RJ-006 | API Level 不匹配 | `targetSdkVersion` 与 AGC 设置一致 |
| AGC-RJ-007 | 调试日志泄漏 | release 包移除 `console.info` |
| AGC-RJ-010 | 跨境数据未声明 | freepdf 无跨境数据，但需确认隐私政策声明 |
| 图标不规范 | 图标含透明通道 | 使用 512×512 PNG，Alpha 通道实心填充 |
| 签名不一致 | .p12 / .p7b / .cer 不匹配 | 三者必须来自同一证书链条 |

---

## 文件清单

| 文件 | 路径 | 用途 |
|---|---|---|
| 签名配置 | `build-profile.json5` | 含 signingConfigs 结构（待填写证书后生效） |
| 包信息 | `AppScope/app.json5` | bundleName = com.freepdf.app，targetAPIVersion 6.1.1(24) |
| 隐私政策 | `AppScope/privacy.json` | 本地隐私数据清单（无权限申请）+ privacyPolicyUrl（待填 AGC 托管链接） |
| 隐私政策文档 | `docs/privacy-policy.html` | AGC 隐私托管上传源（运营者：王浩清；邮箱 whao2025@qq.com） |
| 用户协议 | `docs/user-agreement.html` | AGC 托管配置用（生效日期 2026-08-03） |
| 应用图标 | `entry/src/main/resources/base/media/app_icon_512.png` | AGC 应用图标 |
| 启动图标 | `entry/src/main/resources/base/media/startIcon.png` | 应用启动图标 |
| 特色图形 | `entry/src/main/resources/base/media/feature_graphic.png` | 备用素材（华为无此素材类型，以 AGC 后台为准） |
| 自适应图标前景 | `entry/src/main/resources/base/media/icon_foreground.png` | 自适应图标 |
| 自适应图标背景 | `entry/src/main/resources/base/media/icon_background.png` | 自适应图标 |

---

## HarmonyOS 7 (API 26) 升级路径（**已正式发布，2026-10 更新**）

- 当前基线：HarmonyOS 6.1.1 = API 24（2026/05/26 转正）；鸿蒙 7 已正式发布，工程需尽快升级到 API 26 基线。
- **HarmonyOS 7 = API 26.0.0**：SDK 26.0.0 Release 已于 2026/08/29 发布；开发套件版本号自 26.0.0 起改为语义化 `X.Y.Z`。
- 配套工具链（官方配套关系）：DevEco Studio **26.0.0 Release 26.0.0.851**（Patch，2026/09/23；基线 .821）、Hvigor **6.26.8**、ohpm 26.0.0.630、Node.js 24.14.1、**modelVersion 26.0.0**、compileSdkVersion 26.0.0。
- 升级步骤（✅ **已完成 API 26 构建**，见 `docs/HARMONYOS7_MIGRATION.md`）：
  1. ✅ 安装 DevEco Studio 26.0.0.851（`D:\DevEcoStudio26`，HarmonyOS SDK 26.0.0 内嵌）；旧版 6.1.1 + SDK 24 仍保留在 `C:\Program Files\Huawei\DevEco Studio` 可回退
  2. ✅ `build-profile.json5`：`targetSdkVersion` → `26.0.0`；`compatibleSdkVersion` 保持 `6.1.1(24)`（继续支持鸿蒙 6.x）
  3. ✅ `hvigor/hvigor-config.json5`、`oh-package.json5`：`modelVersion` → `26.0.0`
  4. `AppScope/app.json5` 的 minAPIVersion/targetAPIVersion **无需手改**：官方文档明确二者在编译时由 build-profile 自动生成（手动配置无效）
  5. ⏳ 用 API Change Assistant（SDK 24→26）扫描行为变更 → 新老设备回归（当前本机无设备连接）→ 提审；构建已通过（WARN 0）
- 完整适配方案（行为变更逐条影响分析、验证清单、回滚）：见 `docs/HARMONYOS7_MIGRATION.md`
- 注意：API 25 无官方发布版本，不要使用；HarmonyOS 7 正式版 SDK（releaseType=Release）才可商用上架。