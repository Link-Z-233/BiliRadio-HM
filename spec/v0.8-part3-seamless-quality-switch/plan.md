# Implementation Plan: v0.8-part3 无缝音质切换

**Input**: Feature specification from `spec/v0.8-part3-seamless-quality-switch/spec.md`

## Summary

换档（网络稳定切换自动档 / 面板手动档）从「释放旧实例→重建→prepare→seek」改为双播放器旁路预载：旧实例全程出声不动，新档流经独立 AudioPlayer 实例预加载，prepared 后 seek 到旧实例实时进度并起播，确认出声即停旧换新，交接无静音缝隙。预载/起播失败或超时整体丢弃新实例，旧流无感知继续。暂停态切档走同机制的无声变体（新实例 prepared 后直接替换，保持暂停与进度）。

## Technical Context

**Language/Version**: ArkTS（API 26 / compatibleSdkVersion 26.0.0）
**Primary Dependencies**: 系统能力 `@kit.MediaKit`（AVPlayer/MediaSource/PlaybackStrategy）、`@kit.NetworkKit`；零第三方依赖
**State Management**: 增量改动沿用现状——PlayerController 零装饰器广播模式（字段 + emitUi，消费方 syncFrom）；AudioPlayer 为普通 class（无观测装饰器），双实例并存无状态代际问题
**Storage**: 无新增持久化（AppStore 既有键零变化）
**Testing**: 无测试套件（devDependencies 有 hypium 未启用）；验证走 `devecocli build` + 真机人工，非平凡交接序列以 hilog 日志点自检
**Target Platform**: HarmonyOS NEXT 单模块应用
**Project Type**: mobile-app
**Performance Goals**: 交接静音缝隙 0（允许毫秒级音频重叠）；预载超时上限约 19s（initialized 8s + prepared 8s + 起播确认 3s），超时保旧流
**Constraints**: Constants.ets 唯一真相源（新超时 token 落此）；代码零注释（`ponytail:` 除外）；禁 any/unknown/as 断言
**Scale/Scope**: 改动 3 个 service 文件，零新文件，零新持久化

## Project Structure

### Documentation (this feature)

```text
spec/v0.8-part3-seamless-quality-switch/
├── spec.md
├── plan.md               # 本文件
└── tasks.md              # /spec-tasks 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/service/
├── AudioPlayer.ets       # 新增 waitPrepared 公开方法（旁路实例等待 prepared 落定）
├── PlayerController.ets  # 回调挂载抽公共方法；standbyPlayer 字段；setQualityTier 重构双路径
└── Constants.ets         # 两个换档超时 token
docs/architecture.md      # PlayerController 换档机制描述同步（活文档随代码同步）
```

**Structure Decision**: 沿用现有项目架构（service→model 单向依赖、pages 消费 service），不引入新目录/新文件/MVVM 调整。改动全部落在既有三个 service 文件内，AudioPlayer/PlayerController 的对外行为面（UI 消费的字段与广播）零变化。

## Complexity Tracking

无 Constitution 违规，省略。

## Research & Decisions

- **Decision D1 旁路实例模型**：播放中换档时新建独立 `AudioPlayer` 实例作旁路预载，不复用/不改造主实例。
  **Rationale**: AudioPlayer 回调字段为实例级可空字段——新实例回调全程 undefined 即天然静默，内部 generation 机制独立防串扰；`setStreamSource` 自带 recreatePlayer 全配置（rendererInfo/interruptMode），零改造复用。
  **Alternatives considered**: ① 改造 AudioPlayer 支持单实例双源切换——AVPlayer 换源必重建，等价于隐藏重建，无缝不成立；② AudioPlayer 内建双实例管理——把编排逻辑下沉进播放器层，越权（编排归 PlayerController，现状分层）。

- **Decision D2 交接时序（播放中路径）**：旁路实例 prepared → `setRate` 同步倍速 → seek 至旧实例实时进度 → `play()` → 轮询其 `isPlaying` 确认真实出声 → 暂停旧实例 → 引用替换（this.player = 旁路）→ 重挂回调 → release 旧实例。
  **Rationale**: 先起新后停旧保证零静音缝隙（重叠窗口为旧流前进量，毫秒级）；「等真实出声再停旧」覆盖 seek 后网络拉流的等待期——等待期间旧流继续出声，这才是无缝的本质；出声确认失败即整体放弃保旧流。
  **Alternatives considered**: ① 先 pause 旧再起新——必然产生缝隙，违背 FR-002；② 预先 seek 到预估交接点对齐时间轴——需时间轴监控，复杂度不成比例，进度漂移量（seek 完成到出声间旧流前进量）用户无感。

- **Decision D3 暂停态路径（无声变体）**：暂停中切档走同机制但不起播——旁路实例 prepared → seek 至暂停进度 → 引用替换 + 重挂回调 → release 旧实例，保持暂停态。
  **Rationale**: 统一机制少一条特殊路径；暂停态无出声，替换即无感，且失败同样保旧流（旧实例未动）。
  **Alternatives considered**: 暂停态沿用现有重建路径——两套换流逻辑并存，维护面翻倍，否。

- **Decision D4 isPreparing 语义**：无缝路径全程不置 `isPreparing`（该标志会令 onTimeUpdate 守卫冻结进度显示，且 UI 呈加载态——而旧流在正常播）；「正在切换音质…」仅经 statusMsg 提示。
  **Rationale**: isPreparing 语义绑定「主实例重建中、进度不可信」，与旁路模型矛盾；保持 false 使进度/事件链路照常。
  **Alternatives considered**: 引入独立 isSwitching 标志——仅多一个 UI 不消费的布尔，先不建，需要时再加（ponytail）。

- **Decision D5 并发与生命周期**：loadToken 沿用「最后触发者为准」；`setQualityTier` 在途判定改为「standbyPlayer 非空或 isPreparing」；新触发先释放旧旁路实例再重开；切歌/停止等既有 token++ 路径令在途换档各阶段校验失配后自行丢弃旁路实例。
  **Rationale**: 旁路实例生命周期必须有唯一归口（所有丢弃点统一 release），否则泄漏双实例；token 机制是既有并发真相源，零新概念。
  **Alternatives considered**: 在途时拒绝新切档——违背「最后触发者为准」既有语义。

- **Decision D6 超时取值**：initialized 等待 8s（既有 waitForState 内建）不重定义；prepared 等待 8s；播放路径出声确认 3s。三者任一超时/出错均释放旁路实例、旧流继续、界面提示失败。
  **Rationale**: 与现有首开链路耗时同量级；spec Open Question（预载超时上限）就此定案。token 落 `Constants.TOKEN_SWITCH_PREPARED_TIMEOUT_MS` / `TOKEN_SWITCH_SWITCH_PLAY_TIMEOUT_MS`。
  **Alternatives considered**: 更长上限（30s）——网络差时用户界面「正在切换」悬挂过久，早放弃早回旧流。

- **Decision D7 AudioPlayer 增量**：仅新增公开方法 `waitPrepared(timeoutMs): Promise<void>`（内部复用既有私有 `waitForState('prepared', ...)`，超时抛错），供旁路实例等待 prepared 落定（现 `setStreamSource` 在 `prepare()` 发出后即返回，prepared 落定无对外等待手段）。
  **Rationale**: 最小增量；主实例路径零改动。
  **Alternatives considered**: setStreamSource 内部等待 prepared——改变主实例既有异步时序（首开在 prepared 前有 UI 态流转），回归面大，否。

- **Decision D8 已知风险登记（真机验证覆盖）**：双 AVPlayer 短暂并存（一播一备）的音频焦点互斥——standby play 声明焦点时系统理论上不打断同 app 旧 MUSIC 实例；即便打断，旧实例本就在交接中即将停止，无实际影响；若被打断的是新实例则走保旧路径。风险可控，Phase 5 真机验证覆盖。
  **Rationale**: 不为此预写规避代码（无先例问题不预设方案），验证发现实际打断行为再定对策。

## Data Model

无新增持久化实体、无新增 AppStorage 键、无新增观测状态。新增运行时成员：

- `PlayerController.standbyPlayer: AudioPlayer | undefined`——在途旁路实例唯一归口（非 undefined 即换档在途）
- `Constants.TOKEN_SWITCH_PREPARED_TIMEOUT_MS`、`Constants.TOKEN_SWITCH_PLAY_TIMEOUT_MS`——换档超时上限
- `AudioPlayer.waitPrepared(timeoutMs)`——公开等待方法（见 D7）

## Contracts & Interfaces

内部项目，无外部接口。对内契约变化：

- `AudioPlayer` 公开面新增 `waitPrepared(timeoutMs: number): Promise<void>`；既有方法签名零变化。
- `PlayerController` 对 UI 消费面（公开字段、emitUi 广播、playIndex/setQualityTier/seek 等公开方法）签名零变化；`setQualityTier(tier, writeBack)` 行为语义变化：内部由重建改旁路交接（调用方无感）。
- init 内联的四处回调挂载抽为私有公共方法，供 init 与交接两处复用（挂载内容不变）。
