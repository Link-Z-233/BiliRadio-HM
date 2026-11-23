# v0.8-part4-player-ux-persist bugfix 记录

直接修复（不走 SDD 五阶段）的 bug 按发生顺序在此登记。

## 1. 批量入队跳过条目 toast 不透明 & 混合全跳误报「已在队列中」

**现象**：批量入队含被剔条目（复合键去重/互动拦截）时 toast 恒为「已加入队列」，被剔数量与原因不透明；混合全跳（部分重复+部分互动、无一入队）时结果落 DUPLICATE，toast「已在队列中」对互动被剔条目构成误报。

**修复**（用户直定方案，仅改 toast，statusMsg 维持现状）：
1. `PlayerController`：新增公开跳过计数字段 `lastEnqueueSkipped`/`lastEnqueueInteractiveSkipped`（`loadPlaylistAndPlay` 过滤后透出，调用方 then 中随即读取）；`enqueueToast` 扩为 `(result, skipped=0, interactiveSkipped=0)` 并新增 `skipToastText` 分型——有跳过时 toast 只报「跳过N个（重复/互动）视频」（单一类型点名重复/互动、双类型合并总数；入队结果由 statusMsg 承载）；全跳过精确分流：全重复仍「已在队列中」、全互动仍「互动视频不支持播放」、混合全跳改「跳过N个视频」修正误报；空队起步仅可能跳互动，同样报跳过明细。
2. `SourcePage` 两处批量调用点（多选批量入队/单击+）传入计数；单曲路径（首页分享直入队、添加订阅弹窗）走默认参不动。
3. `Constants`：新增 `TOAST_SKIP_DUPLICATE`/`TOAST_SKIP_INTERACTIVE`/`TOAST_SKIP_MIXED` 三模板（N 占位，沿 `TOAST_MARK_WATCHED` 的 replace 惯例）。

**验证**：`devecocli check arkts` 三文件零错误（39 条 warning 均依赖链既有类别）；`devecocli build` 成功。真机自查待用户：批量入队含重复/互动条目时 toast 分型与计数、混合全跳提示、单曲重复添加提示仍为「已在队列中」。
