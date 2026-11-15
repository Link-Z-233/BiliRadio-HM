# v0.8-part1-random-play-next bugfix 记录

直接修复（不走 SDD 五阶段）的 bug 按发生顺序在此登记。

## 1. 日志页 player 分类条目错标「网络」

**现象**：日志查询页中播放链路日志（`player` 分类）的类别标签显示为「网络」，用户观感为「日志全是网络标签」；落盘文件与导出文本中 `[player]` 分类准确，仅页面 UI 标签错误。

**根因**：`LogPage.ets` 的 `categoryLabel` 写于 `player` 分类铺开之前（v0.4 日志查询轮），仅映射 `error` → 错误、其余一律归「网络」；后续轮次大量新增 `player` 日志未同步此映射。

**修复**（`LogPage.ets`）：`categoryLabel` 补 `player` → 播放 分支，注释同步。

**验证**：`devecocli check arkts` 目标文件零错误零告警；`devecocli build` 成功。真机复测待用户：触发播放后进日志查询页，播放链路条目标签显示「播放」。
