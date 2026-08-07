# 缓存命中率记录 & DeepSeek API 会话状态

> 每次真机测试/会话切换后追加记录。HR = cache.read / (cache.read + input)

## HR 趋势记录

| 日期 | 会话 | HR | cost | inp | read | 备注 |
|---|---|---|---|---|---|---|
| 2026-08-07 | DeepSeek API项目 | 88.2% | $0.60 | 7.9M | 59.4M | 总览 |
| 2026-08-07 | DeepSeek API项目 | 99.8% | $0.002 | 5.4k | 2.2M | 近期轮次 |
| 2026-08-07 | DeepSeek API项目 | 99.9% | $0.001 | 904 | 894k | 最近几轮 |

## 关键结论
- 缓存命中率近期稳定在 99.6%~100%
- 单轮 input < 1k token，符合缓存纪律
- 单次大文件注入会导致前缀断裂，HR 归零

## DeepSeek API 会话状态
- 当前会话: ses_02c0fad1affeAHUIaK3qtAzYxp
- 状态: screenToPdf 公式已落地，Overlay 接入完成，正在清理死代码
- 卡点: 真机验证未做
- 下一步: 死代码清理完成 → 真机跑 TEST_CHECKLIST.md 7 项