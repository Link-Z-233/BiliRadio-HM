# Implementation Plan: v0.8-part1 随机播放去重与随机下一首播放

**Input**: Feature specification from `spec/v0.8-part1-random-play-next/spec.md`

## Summary

随机模式条目级抽取改为分层排除：候选池 = 未完播条目 − 本会话已播条目，耗尽后清会话标记重抽未完播，全完播停止自动连播。源页 insertAfterCurrent 插入的新条目登记为「指定下一首」FIFO 队列，在 next() 优先级链（前进重放 > 组内连播 > 指定下一首 > 随机抽取 > 回退）中兑现。改动全部集中于 `PlayerController.ets`，附带 `app.json5` 版本号升级。

## Technical Context

**Language/Version**: ArkTS（ArkUI），compatibleSdkVersion 26.0.0
**Primary Dependencies**: 零第三方依赖；@kit.AvPlayer / @kit.ArkUI
**State Management**: 增量改动，沿用现状——PlayerController 零装饰器广播模式（字段 + emitUi，消费方 syncFrom），新增字段不加观测装饰器
**Storage**: 会话已播集与指定下一首队列纯内存（不持久化）；完播排除直接引用既有持久化 playHistory（progress=-1）
**Testing**: 无测试套件（项目现状）；验证 = `arkts_check` + `devecocli build`（build-only）+ 真机人工抽查
**Target Platform**: HarmonyOS NEXT 单模块应用
**Project Type**: mobile-app（单模块 HarmonyOS）
**Performance Goals**: next() 决策 O(歌单长)（候选构建线性扫描，与现状 getQueueEntryGroups 同量级）
**Constraints**: 顺序/倒序模式、列表页移动、prev() 轨迹回溯行为零变化；已播判定挂 AVPlayer 'playing' 真实出声点，prepare 失败不标记
**Scale/Scope**: 歌单 ≤ Constants.HISTORY_MAX 量级（500）

## Project Structure

### Documentation (this feature)

```text
spec/v0.8-part1-random-play-next/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/service/PlayerController.ets   # 全部核心改动（随机抽取/已播标记/FIFO/停止判定）
AppScope/app.json5                                # versionName 0.7.0→0.8.0、versionCode 7000→8000
docs/architecture.md                              # 若记载随机播放机制则同步描述（实施时检查）
```

**Structure Decision**: 遵循现有单模块架构，零新文件。改动集中于 `PlayerController.ets`（上帝对象已登记不拆分，本项目惯例是就地扩展播控状态）；随机机制属播控内部决策，无 UI 结构变化、无新页面。

## Complexity Tracking

无（不引入新结构、新依赖、新抽象层）。

## Research & Decisions

### D1 起播标记钩子 = AVPlayer 'playing' 状态回调

- **Decision**: 会话已播标记挂在 stateChanged 的 `'playing'` 分支（`recordOnPlaying` 同点，PlayerController.ets:653-667），标记粒度为当前条目 bvid
- **Rationale**: 所有播放来源（随机抽中、手动点选、轨迹回溯、指定下一首、组内连播）最终都经 AVPlayer 出声，单一钩子覆盖 FR-002 全部来源且天然满足「真正出声才算、prepare 失败不标记」；暂停后恢复重复触发为幂等
- **Alternatives considered**: 在 playIndex 进门标记（prepare 失败也标记，坏条目被排除后无法重试，违背 spec Edge Cases）；在各切歌分支分别标记（分散、漏覆盖、维护面大）

### D2 已播集条目级键 = bvid

- **Decision**: `Set<string>` 存 bvid（条目级），不存 bvid:page 复合键
- **Rationale**: spec 粒度为条目级（多P 任一分P 起播即整条目已播），bvid 键天然实现；同 bvid 游程被拖拽拆散为多个组的极端情况下仍保持整条目口径，与 spec「整条目」表述一致
- **Alternatives considered**: 分P 级复合键 + 组内聚合判定（每次抽取对每个组做全分P 查询，成本高且拆散游程时口径漂移）

### D3 完播排除为派生查询，零新存储

- **Decision**: 不复制完播状态；抽取时按「歌单内该 bvid 的全部分P 在 playHistory 中 progress=-1」派生判定条目完播
- **Rationale**: 完播标记唯一真相源是持久化 playHistory（不变式①：-1 仅由完播写入）；重播已听完条目时 `recordOnPlaying` 将 -1→0（既有不变式①行为），条目自动重新入池——手动重听后重新参与随机的语义自洽；异常条目防假标记（D5 anomaly guard）自动继承：异常条目永不完播、永留重抽池，每次手动 next 重试一次（失败路径 stopFailedPlayback 停声，无自动死循环）
- **Alternatives considered**: 会话内单独维护完播集（与持久化标记双轨，违反「同一事实一处维护」）；仅会话内完播判定（违背用户已定夺的「沿用持久化完播标记、跨会话生效」）

### D4 指定下一首 = 复合键 FIFO，消费与登记双向维护

- **Decision**: `string[]` FIFO 存 `BiliVideo.itemKeyOf` 复合键；登记点在 `loadPlaylistAndPlay` 实际插到当前游程之后的分支（afterCurrent 用户意图判定：insertAfterCurrent 且命中当前游程，含游程在队尾、insertAt 恰等于原长度的场景——几何判定 insertAt < origLen 会漏掉队尾游程的登记，与 FR-005 MUST 语义冲突，已修）；消费点在 `randomIndex` 组内连播之后（弹出队首、`indexOfKey` 校验在队列则跳播，不在则丢弃弹下一个）；`'playing'` 钩子同步剔除当前条目键（手动点播 FIFO 条目视为消费）；`removeSelectedFromPlaylist` 剔除被移键
- **Rationale**: 复合键与 shuffleHistory/forwardHistory 同构，重组歌单不失效；多选插入 N 条按序兑现（一次一条出队，多P 插入条目由组内连播自然接力后续分P）；消费时校验兜住一切移除路径（含 unfavorite 的 splice 直删不经过 removeSelectedFromPlaylist 的场景）
- **Alternatives considered**: 单槽「指定下一首」（多选插入时后续条目退化为随机抽签，破坏 US3 场景 3 的顺序兑现）；插入边界标记 + 扁平邻接推进（需要维护边界失效条件，复杂度不成比例）

### D5 全完播停止判定挂 handleCompleted，手动 next 维持回退

- **Decision**: `handleCompleted`（PlayerController.ets:705-740）新增 RANDOM 分支：FIFO 为空且歌单内全部条目完播时走 US7 同款停止路径（statusMsg='播放结束'、currentItemEnded=true、playIntent=false），否则照旧 `next()`；手动 next()（按钮/MediaSession）不改停止语义——`randomIndex` 候选空且全完播时回退重播当前（现状回退，US2 场景 4）
- **Rationale**: 自动连播与手动切歌语义解耦（对齐顺序模式 US7「自动停止、手动回绕」的既有先例）；停止条件须含 FIFO 空判断——全完播但指定下一首待兑现时自动连播继续（FR-006 指定优先于随机）；组内连播无需单独判断——当前多P 存在未完播分P 时该 bvid 天然未完播，next() 内组内连播自然接管
- **Alternatives considered**: next() 内统一停止并返回信号（需给 next() 加调用来源参数，侵入手动路径语义）；重洗全量清空继续播（用户已定夺「停止」）

### D6 候选耗尽重抽在抽取时点执行

- **Decision**: `randomIndex` 构建候选时排除「已播 bvid + 完播 bvid + 当前组」；候选空且存在未完播条目 → 清空已播集就地重建候选（当前组仍排除）；候选空且全完播 → 回退当前
- **Rationale**: 重抽在耗尽瞬间发生，无需独立状态机；当前组始终排除避免重抽后立刻重播当前；仅剩当前一个未完播条目时回退重播当前直至完播（与现状回退行为一致）
- **Alternatives considered**: 独立「轮次」状态字段（多一份需同步的状态，收益为零）

### D7 不新增测试套件

- **Decision**: 不为本次逻辑引入 hypium 测试文件；关键路径（重抽触发、FIFO 消费、停止判定）留 Logger.log 便于真机自查
- **Rationale**: 项目零测试现状，引入测试套件超出最小改动；验证由 build + 用户真机抽查兜底
- **Alternatives considered**: 新增单测目录与用例（拉入测试基建，非本次范围；用户如需可另开轮次）

## Data Model

### 新增内存态（PlayerController 私有字段，随实例生命周期）

| 字段 | 类型 | 语义 | 生命周期事件 |
|---|---|---|---|
| 会话已播集 | `Set<string>`（bvid） | 本会话已真实出声的条目（条目级） | 出声时 add；歌单清空重生成时 clear；重启丢失 |
| 指定下一首队列 | `string[]`（复合键，FIFO） | 源页 insertAfterCurrent 插入条目的兑现顺序 | 插入到当前游程后时按序 push；消费/移除/清空重生成时剔除；重启丢失 |

### 派生判定（零存储，查询时计算）

| 判定 | 口径 |
|---|---|
| 条目已播 | 已播集含该 bvid |
| 条目完播 | 歌单内该 bvid 的全部分P 在 playHistory 中 progress=-1 |
| 全完播 | 歌单内全部 bvid 条目均完播 |
| 随机候选池 | 条目组 − 已播 bvid − 完播 bvid − 当前组 |

### 生命周期事件表

| 事件 | 已播集 | FIFO |
|---|---|---|
| AVPlayer 'playing' 出声 | add 当前条目 bvid | 剔除当前条目复合键（消费） |
| 源页 insertAfterCurrent 插入实际落在当前游程后（afterCurrent，含游程在队尾、insertAt 恰等于原长度） | — | 按序 push 新条目复合键 |
| 源页插入命中去重 / 互动拦截 / 非 insertAfterCurrent 的纯追加队尾 | — | 不登记 |
| removeSelectedFromPlaylist / unfavorite 移除 | — | 剔除被移键（消费时校验兜底） |
| 歌单清空重生成（loadPlaylistAndPlay 空歌单分支） | clear（随 shuffleHistory/forwardHistory） | clear |
| 应用重启 | 丢失 | 丢失 |

## Contracts & Interfaces

全部为 PlayerController 内部契约，无跨模块接口变化。

### next()（RANDOM 模式决策序，FR-006）

1. 前进轨迹重放（现状不动，forwardHistory 非空先重放）
2. `randomIndex()`：
   a. 组内连播（现状优先级 1 不动）
   b. FIFO 弹出校验（新增：队首键在歌单则跳播，不在则丢弃续弹）
   c. 排除式随机抽取（新增：候选池构建按 D6，耗尽重抽）
   d. 回退重播当前（现状兜底不动）

### handleCompleted()（自动连播停止，FR-004）

RANDOM 分支（REPEAT_ONE/睡眠定时/pausedByUser 判定之后、next() 之前）：FIFO 空 且 全完播 → 停止（US7 同款字段置位）；否则 `next()`。SEQUENTIAL/REVERSE 的 US7 逻辑零改动。

### loadPlaylistAndPlay()（FIFO 登记，FR-005/FR-007/FR-011）

非空歌单 + 实际插到当前游程后（afterCurrent，用户意图判定：insertAfterCurrent 且命中当前游程，含游程在队尾、insertAt 恰等于原长度的场景）分支：`toAdd` 各条目复合键按序入 FIFO。去重命中（skipped）与非 insertAfterCurrent 的纯追加队尾路径不登记。空歌单重生成分支：已播集与 FIFO 随 shuffleHistory/forwardHistory 一并 clear。

### 'playing' 状态回调（已播标记，FR-002）

在 recordOnPlaying 同点：已播集 add 当前条目 bvid；FIFO 剔除当前条目复合键。

### 移除路径（FR-007）

removeSelectedFromPlaylist 移除后剔除 FIFO 中被移键；消费时 `indexOfKey` 校验兜底其余移除路径。

### 版本号（FR-010）

AppScope/app.json5：versionName `0.7.0`→`0.8.0`、versionCode `7000`→`8000`。

### 文档同步（AGENTS 活文档随代码同步）

实施后检查 `docs/architecture.md` 是否记载随机播放机制描述，有则同步（分层排除、指定下一首队列、全完播停止）；未记载则不新增。源码无文件增删，架构文件表零变化。
