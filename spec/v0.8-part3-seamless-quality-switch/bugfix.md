# v0.8-part3-seamless-quality-switch bugfix 记录

直接修复（不走 SDD 五阶段）的 bug 按发生顺序在此登记。

## 1. 随机模式「下一首播放」不兑现为下一首（指定 FIFO 顺序与队列线性顺序矛盾）

**现象**：随机模式下，队列中已有未消费的「下一首播放」指定项时，源页再对同一/新条目做「下一首播放」，当前条目播完切歌播的是较早添加的指定项而非最新操作条目；队列面板「下一首播放」移动后播完切歌同样播旧指定项，移动对随机播放顺序完全无效（日志：两次 `designated next play` 均为早前添加的条目）。

**根因**（`PlayerController.ets`，两处叠加）：
1. `loadPlaylistAndPlay` 的 afterCurrent 登记把新复合键 `push` 到 `designatedNextQueue` 尾部，而条目线性插入位置是「当前播放条目游程之后」（最新在最前）——FIFO 时间序与队列线性序相反，随机模式按 FIFO 消费时旧指定项插队，最新「下一首播放」被压后。
2. `moveFlatItems`（队列面板「下一首播放」/「移到最后」共用）只重排线性位置、不触碰 `designatedNextQueue`——随机模式的下一首由该 FIFO 决定，移动条目对随机播放顺序为零效果。

**修复**（`PlayerController.ets`）：
1. `loadPlaylistAndPlay`：afterCurrent 登记改为 toAdd 复合键整批前插 FIFO 队首（`concat` 到头部），与线性插入位置一致；补一条 `designated next register` 日志（此前登记无日志，排查只能靠消费侧逆推）。
2. `moveFlatItems`：movers 复合键先从 FIFO 整体剔除（移到最后的旧指定不再兑现为下一首），「下一首播放」（非 toEnd）再按移动后顺序整批前插 FIFO 队首，随机模式下队列面板移动同样生效为下一首；同样补 `designated next register` 日志。

多批次语义随之修正为「最新批次最先兑现」（与队列线性顺序一致，即队列 UI 所见顺序）；单批次/单条目行为不变（v0.8-part1 SC-003 的组内连播优先、消费时校验跳播等机制不动）。

**验证**：`devecocli check arkts` 零错误；`devecocli build` 成功。真机复测待用户：随机模式播放中，① 源页「下一首播放」插入条目 X（此前已有未消费指定项 A）→ 播完切歌应为 X（再下一轮才是 A）；② 队列面板多选「下一首播放」移动条目 X → 播完切歌应为 X。

## 2. 「下一首播放」修复后用户回访报「未生效」——实为冷启动清空内存态指定名单（设计边界，非缺陷）

**现象**：用户回访称 ## 1. 修复「未生效」（日志 biliradio_log_20261120_182627）。新构建确认在跑（`designated next register` 日志在），但 12:46-12:47 登记的 3 条指定（enqueue 1 + move 2，total=3）在 16:15/16:25 两次播完切歌时未被消费（无 `designated next play`，走随机抽取）。

**排查**：日志时间线还原——12:47:39 暂停后应用被杀；16:04:40 冷启动签名（`subscribe owner=Index listeners=1` + finger/spi/ExClimbWuzhi/nav 启动初始化请求）后恢复播放；此后 FIFO 为空（16:41:37 重新登记时 total=1 印证）。16:42:04 播完切歌 `designated next play | BV15Zst6eEPD:1` ——**## 1. 修复本身有效**；16:42:38 登记→16:43:16 播放→`consumed on play` 链路亦正常。「未生效」感知全部指向冷启动丢失。

**根因**：`designatedNextQueue` 为纯内存 FIFO（v0.8-part1 设计「均不持久化」），冷启动即清空；用户实际使用横跨数小时含应用重启，登记随之失效。

**处置**：非缺陷，属设计边界撞上真实使用模式。按用户决定升级为持久化功能——指定名单随 playlist.json 保存、冷启动过滤重建，走 SDD 轮次 `spec/v0.8-part4-player-ux-persist/` 实施（US1）；本轮不另行代码修复。

**验证**：无代码改动，无本轮验证项；持久化功能验证归 v0.8-part4 轮（构建验证 + 用户真机自查：随机模式登记指定 → 杀应用重启 → 播完切歌兑现指定）。
