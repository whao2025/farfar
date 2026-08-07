# DeepSeek 缓存命中率优化备忘（freepdf, opencode 会话）

> 目标：在 opencode 中执行 freepdf 项目时，DeepSeek 前缀缓存命中率 ≥90%（`prompt_cache_hit_tokens / prompt_tokens`）。
> 本文是该目标的理论依据、已做动作、验收记录与常见坑。基于 DeepSeek KV 缓存官方机制与多次 explore/review 纠错整理。
> **> 基于 2026-08-07 复核修订**：下列「最小触发粒度」「Git 文件树注入」「跨天日期归零」「1-2h 自动 compaction」四点为**未证实或错误认知**，已改正；「非 thinking 别名」建议**已被质量优先决策取代**，勿执行。以项目 `D:\freepdf\AGENTS.md` 的「命中率诊断与戒律」为准。

## 一、DeepSeek 缓存机制（物理前提）

- **前缀匹配**：从 token-0 起**字节级一致**才命中；任一字节变化，自此失效。
- **持久化单元**：官方口径为「完整 prefix unit + 固定 token 间隔持久化」（官方未公布 64/256 颗粒度；旧的「~1024/256 块」说法已作废）。
- **TTL**：缓存闲置后由系统清理，一般**小时级到天级**（不是分钟）。短 idle 不驱逐，无需 keep-alive。
- **尾变头存**：对话尾部变化不影响已缓存头部前缀。
- **全自动、无键可配**：DeepSeek **不支持 `prompt_cache_key` / retention / TTL 配置**，配了也无效。

## 二、决定命中率的三大撞击因素（重要！)

即便前缀设计完美，以下因素任一发生都会导致缓存重建：

1. **编辑 AGENTS.md / 会话注入点向前的内容**：自改动点向后整段前缀失效（本 build 未见「Git 文件树注入 env」机制，已作废该猜测）。
2. **长空档 TTL 逐出**：闲置数小时~数天被清理；**跨天主要是 TTL 损失**，非「日期翻页归零」（opencode 默认不注入日期，旧「跨天日期归零」说法已作废）。
3. **手动 `/compact` 或会话重建**：改写消息序列，换一次 cache 重建。（「约 1-2h 自动 compaction」在本 build 未找到实现串，已作废。）

→ 因此 **90% 目标只在「单自然日 + 未触发 compaction」窗口内可衡量**，跨天/压缩后数字回落属正常，不是 bug。

## 三、字节稳定性规范（命中前提）

- `system` / AGENTS.md 内**禁止**写日期、时间、CWD、绝对路径、随机 UUID 等动态内容。
- 锁定 freepdf 工作目录，避免工具输出路径漂移。
- 保持 AGENTS.md 全局→项目级合并顺序固定；存储为 **UTF-8 无 BOM**，体积 ≥ 约 1.5-2k token（当前已建 `D:\freepdf\AGENTS.md`，16276B / 约 8-11k token，达标）。
- 固定可用工具集合：**尽量避免增删插件 / 依赖动态注册 tool**（工具经 `tools` 数组进入正确前缀，schema 变化会破坏前缀）。

## 四、思考模型（thinking）与 token 成本

- `interleaved` 仅控制**流式交错展示**，并不能阻止 reasoning_content 进入后续输入。
- thinking 模型会把思考内容放大输入 `prompt_tokens`，从而**拉低命中率基线**。
- 若要省 token / 抬基线：官方 API 选用**非 thinking 别名**（`deepseek-v4-flash` 的 non-reasoning 变体）。**> 已被 2026-08-07「质量优先」决策取代：为保代码质量/改 bug 能力，不改 thinking 相关配置，勿执行此条。**
- 验证是否在回灌：观察 `prompt_tokens` 是否随对话轮次显著增长。

## 五、会话操作习惯

- **不要频繁使用子代理**（@explore / @debug / @review）：子代理是**独立 system + 独立消息 = 独立 request**，与主会话**不共享字节前缀**，过度使用会造成缓存碎片化、降低平均命中率。要撑 90% 请以**主会话**为主。
- 连续在单一会话做任务，少 `/new`；同一项目多开窗口会分散/覆盖缓存。
- 长会话内避免让自动 compaction 触发（可控制历史体积、分批提交）。

## 六、度量与验收口径（重要）

- opencode 的 usage 数据来源于**底层响应透传**；代理若未透传 `prompt_cache_*`，opencode 就拿不到。**Zen 代理实测透传不稳定**（首次返回，后续缺失）。
- **只有官方 `api.deepseek.com` 才能硬验证命中率。** 代理阶段只做参考。
- **官方模型名 `deepseek-v4-pro/flash`**，与 Zen 别名 `deepseek-v4-flash-free` 是**不同模型 → 缓存前缀不衔接**，切换后需**单独重测基线**。

**验收步骤**
1. 使用官方 API（模型 `deepseek-v4-flash`；**不再建议**切非 thinking 别名——见第四节取代横幅）。
2. 重启 opencode，使其注入新 AGENTS.md。
3. 当日跑基准会话，记录平均 `prompt_cache_hit_tokens / prompt_tokens` 作为 baseline。
4. 每改一步（见下动作记录）单独测一次，U 型归因，可回退。
5. 当日、未压缩、无文件增删的前提下，目标 ≥90%（最高可达 ~92-95%）；首轮必 miss，随对话趋饱和。

## 七、动作记录（执行日志）

- [x] 删除插件 `@nick-vi/opencode-type-inject 与 opencode-dynamic-context-pruning（改 `~/.config/opencode/…/opencode.jsonc`，需重启生效，最后相应验证行为）。
- [x] 新建 `D:\freepdf\AGENTS.md`（UTF-8 无 BOM，16276B，含 B2/B3/UI 规范更新）。
- [x] B2 export 规范化：全组件/页面统一为具名导出；`@Entry` 页面保持 `struct X` 不导出（export struct 配 @Entry 触发 ACE preview 警告）；仅 `EntryAbility` 保留 `export default class`。
- [x] B3 死代码删除：`GradientStrokeHelper.ets`/`HelloPathData.ets` 已删；保留有引用的 `PDFOCRUtils.ets`。
- [x] 修复 `AutoRecordConfirm` 编译 bug（误 default-import `GlassTokens`、非法 `.backgroundClr`/`ButtonState`）；组件当前零引用，标注"仅供未来"。
- [x] UI 统一：`GlassButton` 去掉 64vp halo 大圆（改 `clickEffect` 轻量缩放）；`PdfEditToolItem` 紧凑化（36/20/10/56）。
- [x] 返回键策略：`PDFConvertPage`/`BookkeepingConfirmPage` 顶栏无返回键；`PDFViewer` 编辑按钮 `widthVp:64`；`PDFEditPage` 顶栏 label 恒为「撤回」。
- [x] 最近文件增强：折叠卡（默认 4 项+展开全部）、星标视图独立置顶（`starPinTime`/`toggleStarPin`/`pinStarBatch`，与全局置顶解耦）、EditTab 星标筛选修复（`setFilter` 写回 AppStorage）。
- [x] 全程 `hvigorw assembleApp` 编译验证 BUILD SUCCESSFUL；已装真机（55K0225322004394）运行确认。
- [x] `opencode.json` 已写入官方 DeepSeek 配置（`openai/deepseek-v4-flash`，baseURL `https://api.deepseek.com`，apiKey 引用 `{env:DEEPSEEK_API_KEY}`），备份 `opencode.json.bak`。
- [ ] 设置 `DEEPSEEK_API_KEY` 环境变量（User 作用域）后重启 opencode，官方模型才生效。
- [ ] 确认实际加载的配置是 `opencode.json` 还是 `opencode.jsonc`（并存时，opencode 可能仅取其一——影响上述插件是否生效）。
- [ ] 切官方 API 后于「单自然日 + 文件静止 + 未压缩」窗口重测基线（见「验收口径」）。

## 八、已知风险与符点

- 若继续使用 Thinking 版本，命中率基线会偏低，请勿按 90% 死盯。
- 若项目大量增删文件（freepdf 近期频繁）、跨天连做、触发压缩，命中率会显著下降，属预期。
- 凭内心建议：代理阶段不要硬设 90% 目标（无法硬验证），切官方后以「单日 + 当日文件不变」窗口验收。
- 制作监控：改 `scripts/ds_cache_monitor.py`（只读，勿写库）。

## 九、监控：命中率实时/复盘实用（2026-08-07）

目的：随时查看某个官方 DeepSeek API 会话的缓存命中率与成本，用于诊断是否跌破 90%、落入哪个根因。**脚本纯只读**（`sqlite3 mode=ro + PRAGMA query_only`），绝不写库。

### 数据源
`opencode.db`（约 768MB，`C:\Users\LENOVO\.local\share\opencode\opencode.db`）：
- `session` 表：每会话汇总 `tokens_input/output/reasoning/cache_read/cache_write/cost` + `model`(JSON) + `time_updated`
- `message` 表：`data` JSON 每条 assistant 消息带 `tokens.{input,output,reasoning,cache.{read,write}}` + `cost` → 支持按轮次粒度

### 口径（与 AGENTS.md 一致）
- 命中率 = `cache.read / (cache.read + input)`；`input` 为未命中新 token；`cache.write` 本 setup 恒 0
- **token 加权**（Σread/(Σread+Σinput)），非逐轮平均（小轮会稀释）
- 剔除 `cache.read==0 且 input==0` 的双零行；保留 `read==0 且 input>0`（正是「前缀尖峰断裂」信号）
- 成本：逐轮用 `message.data.cost`（定位热点），聚合用 `session.cost`；两者做容差对账

### 用法
```
python scripts/ds_cache_monitor.py --recent 5                 # 最近官方会话汇总
python scripts/ds_cache_monitor.py --session <id> --tail 30   # 某官方会话最近 30 轮
python scripts/ds_cache_monitor.py --watch 10                 # 实时轮询活跃会话
python scripts/ds_cache_monitor.py --checkpoint               # 首/后半命中率对比，诊断回落
python scripts/ds_cache_monitor.py --provider all --recent 5  # 连同 Zen(free) 一并查看
python scripts/ds_cache_monitor.py --session <id> --tail 10 --json  # 机器可读
```
- **官方判定**：`session.model` JSON 的 `providerID=='deepseek'`（Zen='opencode'，不计；两者前缀不衔接）
- 活跃会话以 `session.time_updated` 最大者为准
- 换库位置：设环境变量 `OPENCODE_DB` 指向其它路径

### 根因判定矩阵（命中率回落时）
| 现象 | 大概率根因 | 处置 |
|---|---|---|
| 紧接某条 input 尖峰(>5万)后的 1–3 轮 read≈0 | 一次性超大注入破坏前缀 | 戒律#2：分页/摘要，勿回灌大文本 |
| 长时间空档后首轮全漏 | 长空档 TTL 逐出 | 戒律#1：早晨/间歇小请求预热 |
| 改动/新增/删除 .ets 或 AGENTS.md 后全漏 | 前缀漂移重置 | 冷启动批次合并编辑 |
| 逐轮 `reasoning>0` 增多伴随 read 回落 | tool 轮 reasoning_content 协议回填 | 协议强制不可消，勿为缓存改 thinking 配置 |
| 命中率稳定但不达 90% | 首轮/过渡期/模型变体 | 同日+文件静止+未压缩 窗口内再判 |