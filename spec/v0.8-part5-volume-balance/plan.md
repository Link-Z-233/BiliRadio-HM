# Implementation Plan: 音量均衡（服务端响度归一）+ 设置页重排（账号组音质提示/网络设置独立组）

**Input**: Feature specification from `spec/v0.8-part5-volume-balance/spec.md`（US1-US4、FR-001~011）；API 实测依据 `BILI_NOTES.md` §3.14。

## Summary

取流链恒携带 `voice_balance=1` 使 playurl 响应下发服务端预计算的响度数据（`volume` 对象），解析为 `LoudnessData` 模型随 `ResolvedAudio` 上行；播控中枢按开关状态以 `gain_dB = target_i − measured_i` 计算静态增益（含可疑测量守卫、防削波钳制、接口区间钳制），经 `AudioPlayer` 的「期望增益」机制（`desiredRate` 同款）在 prepared 时应用、已 prepared 即时应用；设置页播放设置组提供「音量均衡」开关（默认关闭，0/1 持久化），切换对当前曲目即时生效。无数据/异常/应用失败一律静默不增益，仅日志。

设置页重排（US4）：未登录/非会员音质提示挪至账号组卡片内底部（提示本质是登录/会员态说明，语义归位），「Wi-Fi 默认音质」「移动网络默认音质」「仅在 Wi-Fi 环境播放」三行析出为独立「网络设置」组——纯 UI 结构调整，零逻辑改动。

## Technical Context

**Language/Version**: ArkTS（ArkUI），compatibleSdkVersion 26.0.0（`setLoudnessGain` API 21+ 可用）
**Primary Dependencies**: 零第三方依赖；`@kit.MediaKit`（media.AVPlayer）、`@kit.AudioKit`（audio.StreamUsage）
**State Management**: 沿既有——`PlayerController` 零装饰器广播、设置页 `@ComponentV2`（`@Local` 开关态）、`AppStore`（preferences 0/1 持久化）
**Storage**: preferences（`AppStore`，新增 `KEY_VOLUME_BALANCE`，0/1 数字模式沿 `KEY_INTERRUPT_RESUME` 先例）
**Testing**: 无测试套件（项目事实）；增益公式以 §3.14 实测样本值（-6.6 / -0.5 dB）经模拟器/真机日志验证；设置页重排经模拟器 UI 验证（三种登录态提示位置 + 组结构 + 迁移三行功能）
**Target Platform**: HarmonyOS NEXT 单模块应用
**Performance Goals**: 增益应用无感（prepared 即时）；零新增网络请求（`voice_balance` 搭车既有 playurl）；重排零新增渲染层级
**Constraints**: `setLoudnessGain` 仅 prepared/playing/paused/completed/stopped 态可调、区间 [-90, +24] dB、前置条件 `audioRendererInfo.usage` 为 MUSIC/MOVIE/AUDIOBOOK（现有 `AudioPlayer` 已配 `STREAM_USAGE_MUSIC`，实测核对通过）
**Scale/Scope**: 6 个既有文件改动，0 新增文件（设置页重排落在已改动的 `SettingsPage.ets` 内）

## Project Structure

### Documentation (this feature)

```text
spec/v0.8-part5-volume-balance/
├── spec.md
├── plan.md               # 本文件
└── tasks.md              # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── model/
│   └── AudioQuality.ets        # [改] 新增 LoudnessData 类（字段 + parseVolume 静态解析 + computeGainDb 静态增益公式）；ResolvedAudio 增加 loudness 字段
├── service/
│   ├── BiliService.ets         # [改] fetchDashAudioTracks/fetchDurlCandidates 请求 URL 追加 voice_balance=1、解析 data.volume；resolveAudioTrack 两链 loudness 汇聚进 ResolvedAudio
│   ├── AudioPlayer.ets         # [改] desiredLoudnessGainDb 期望增益机制（desiredRate 同款）：setLoudnessGainDb 方法 + prepared 时应用 + 失败静默日志
│   ├── PlayerController.ets    # [改] currentLoudness 字段；playIndex/setQualityTier 应用增益；setVolumeBalance 开关入口（读开关态、按 currentLoudness 计算、即时应用、日志埋点）
│   ├── Constants.ets           # [改] 新增 KEY_VOLUME_BALANCE
│   └── AppStore.ets            # [无改动]（0/1 读写走既有 getNumber/putNumber）
└── pages/
    └── SettingsPage.ets        # [改] 播放设置组新增「音量均衡」ListRow 开关；US4 重排——音质提示挪账号组卡内底部 + 三行析出「网络设置」组（纯结构调整零逻辑改动）
```

**Structure Decision**: 沿既有项目架构（分层：model 纯数据与静态工具 / service 业务 / pages 组装），不引入新目录与新文件；响度数据模型并入 `model/AudioQuality.ets`（该文件即「音频播放数据模型」内聚承载：AudioTrack/ResolvedAudio/静态映射工具先例）。既有 `@Entry`、导航、五层 z 序零触碰。

## Complexity Tracking

无 Constitution 违规。唯一边界说明：`LoudnessData` 的增益区间常量（-90/+24 dB）定义在 model 类内而非 `Constants.ets`——model 边界契约禁止依赖 service（`Constants` 属 service），类内命名常量非裸数字，不触发令牌豁免登记。

## Research & Decisions

- **Decision D1**: `voice_balance=1` 与开关状态**解耦恒携带**（dash/durl 两链统一）。
  **Rationale**: 开关即开即用（当前曲目响度数据已在手，切换零额外请求）；参数与开关耦合需把开关状态穿透 resolve 链三层，成本高；响应仅多字段，无用户可感知差异（FR-008 精神：关闭时听感与取流结果与现版本一致）。响应多一个 `volume` 字段无兼容风险（§3.14 实测）。
  **Alternatives considered**: 仅开启时携带 + 切换开关时按需重新 resolveAudioTrack（多一次 playurl 请求且实现复杂，否决）。

- **Decision D2**: 增益应用采用 AudioPlayer「期望值」机制（`desiredRate` 同款）：`setLoudnessGainDb(db)` 存期望值，prepared 事件时应用，已 prepared 立即应用。
  **Rationale**: 一个机制天然覆盖全部路径——新曲起播（prepared 应用）、openStreamWithRetry 多 URL 重建（recreatePlayer 后 prepared 重放）、音质换档旁路（standby 实例 prepared 应用）、播放中切换开关（已 prepared 即时应用）、completed 重播（实例保持增益）。`setLoudnessGain` 在 initialized 态不可调，期望值模式是唯一能统一覆盖的形态。
  **Alternatives considered**: 各调用点在 prepared 后手动 await 应用（散点多、换档旁路时序复杂，否决）。

- **Decision D3**: 增益计算与守卫全部收敛为 `LoudnessData.computeGainDb()` 静态方法（model 层），调用方（PlayerController）只负责开关判定与日志。
  **Rationale**: 公式+守卫是纯函数（实测样本可验证），model 层静态工具先例充分（`AudioQuality.fromStored/clampTier`）；集中一处防多调用点公式漂移。
  **Alternatives considered**: 守卫拆在调用方（playIndex 与 setQualityTier 双份，漂移风险，否决）。

- **Decision D4**: 防削波钳制仅约束**放大方向**：`gain > 0 且 measured_tp + gain > 0` 时钳制到 `max(0, −measured_tp)`；衰减方向永不限幅。
  **Rationale**: 钳制目的是「增益不使峰值比源更糟」——衰减只会降低峰值（样本一 tp=1.1 配 -0.5 dB 后峰值 0.6 仍越 0 但优于源，属源内既有削波，非增益引入）；`measured_tp ≥ 0`（源已越满刻度）时放大禁用为最保守正确行为。B 站音频峰值普遍接近满刻度（PiliPlus 实测注释佐证）。
  **Alternatives considered**: 官方 PC 完全不做峰值钳制（增益可放大越限峰值，违背 spec 防削波要求，否决）；全向钳制（改变样本一的 -0.5 dB 为 -1.1 dB，偏离官方听感，否决）。

- **Decision D5**: `measured_tp` 缺失/非法时按 `0 dBFS` 参与防削波（等效禁止放大）；`multi_scene_args.undersized_target_i` 缺失时按 `-Infinity`（守卫惰性）。
  **Rationale**: 缺峰值数据时保守假设峰值已满刻度（符合 B 站内容常态），绝不在未知峰值下放大；undersized 守卫缺阈值时不误杀。
  **Alternatives considered**: tp 缺失跳过防削波（在未知峰值下允许放大，违背「绝不削减防数据丢失的错误处理」，否决）。

- **Decision D6**: 开关持久化沿 0/1 数字模式（`KEY_INTERRUPT_RESUME` 先例），`PlayerController` 按需读 `AppStore`，不镜像进内存广播字段。
  **Rationale**: 开关消费点唯一（播放链），无 UI 联动需求；`isHistorySyncEnabled()` 同款读取先例。
  **Alternatives considered**: 开关入 PlayerController emitUi 广播（消费方只有自身，过度设计，否决）。

- **Decision D7**: `setLoudnessGain` 调用失败（Promise reject）静默捕获并记日志，期望值保留（下次 prepared 重试）。
  **Rationale**: FR-006——增益是增强功能，任何失败不得影响播放；期望值不回滚使换流重建后自然重试。
  **Alternatives considered**: 失败回滚期望值为 0（瞬时状态错误导致的功能永久失效，否决）。

- **Decision D8**: durl 兜底链同样携带 `voice_balance=1` 并解析 `volume`（存在则均衡、缺失则静默跳过）。
  **Rationale**: 与 dash 链同端点同参数家族，追加零风险零成本；兜底内容有机会同样获得均衡。§3.14 未实测项③（durl 是否下发 volume）由真机验证回填。
  **Alternatives considered**: durl 链不均衡（无理由放弃兜底内容，否决）。

- **Decision D9**: 设置页重排为纯 UI 结构调整：音质提示 Text 原样挪入账号组卡片内底部（已登录分支「取消收藏提醒」行之后；未登录分支二维码块之后；大会员与冷启动占位不渲染——条件渲染沿现状三态判定），「Wi-Fi 默认音质」「移动网络默认音质」「仅在 Wi-Fi 环境播放」三行析出为紧随「播放设置」组的新「网络设置」SettingsGroup；所有行的 toggle/弹层/持久化代码随节点移动零改动，divider 按新组内位置重排（非末行有、末行无）。
  **Rationale**: 提示本质是登录/会员态说明，归属账号组卡内底部即消除「像仅在 Wi-Fi 环境播放行的说明」的误读；网络相关三行成簇恢复分组语义；纯节点移动是 FR-011 零回归的最小实现路径。
  **Alternatives considered**: 提示挪至音质行 subtitle（仍与具体行绑定，语义仍是登录态说明，否决）；仅挪提示不拆组（分组混装问题残留，否决）。

## Data Model

### LoudnessData（model/AudioQuality.ets 新增，纯数据 + 静态工具）

| 字段 | 类型 | 语义 | 缺失/非法回退 |
|---|---|---|---|
| measuredI | number | 服务端实测综合响度（LUFS） | 核心字段，无效则整体视为无数据 |
| measuredTp | number | 服务端实测真峰值（dBTP） | 0（防削波保守假设，D5） |
| targetI | number | 目标响度（LUFS，实测恒 -14） | 核心字段，无效则整体视为无数据 |
| undersizedTargetI | number | 可疑测量下限（dB，实测恒 -28） | -Infinity（守卫惰性，D5） |

- 类常量：`GAIN_MIN_DB = -90`、`GAIN_MAX_DB = 24`（播放器接口有效区间；类内定义的边界依据见 Complexity Tracking）。
- `parseVolume(raw)`：静态解析 playurl 响应 `data.volume`；`volume` 缺失、`measured_i`/`target_i` 非有限数值 → 返回 undefined（无数据）；`undersized_target_i` 自 `multi_scene_args`（字符串 map）解析。
- `computeGainDb()`：静态纯函数，`gain = targetI − measuredI`；守卫序：① `measuredI < undersizedTargetI` → 返回 0（可疑测量，调用方日志区分）；② 防削波钳制（D4）；③ 区间钳制 `[-90, +24]`。

### ResolvedAudio（model/AudioQuality.ets 既有，扩字段）

新增 `loudness: LoudnessData | undefined`（默认 undefined），随 resolveAudioTrack 两链（dash/durl）填充；`durl` 为空数组语义不变。

### DashFetchResult / DurlFetchResult（BiliService.ets 内部类，扩字段）

各新增 `loudness: LoudnessData | undefined = undefined`，自响应 `data.volume` 解析。

### 播放器与播控状态（service 层，非持久化）

- `AudioPlayer.desiredLoudnessGainDb: number = 0`（实例期望增益，prepared 应用）。
- `PlayerController.currentLoudness: LoudnessData | undefined`（当前曲目响度数据，随每次 resolve 刷新，不缓存跨曲目）。
- `Constants.KEY_VOLUME_BALANCE: string = 'volumeBalance'`（preferences 0/1，默认 0=关闭）。

## Contracts & Interfaces

### playurl 请求契约（BiliService，对外行为变更）

```
GET x/player/playurl?...&fnval=4048&voice_balance=1   （dash 链）
GET x/player/playurl?...&fnval=0&voice_balance=1      （durl 链）
```

响应新增消费字段：`data.volume`（对象，含 `measured_i/measured_tp/target_i/multi_scene_args.undersized_target_i`），§3.14 实测形状。既有字段消费零变化。

### AudioPlayer 公开接口（新增）

- `setLoudnessGainDb(db: number): void` —— 存期望增益；avPlayer 已 prepared 时立即应用（`setLoudnessGain` Promise 失败静默日志，D7）；prepared 事件时统一应用（desiredRate 同点位）。

### PlayerController 公开接口（新增）

- `setVolumeBalance(enabled: boolean): void` —— 设置页开关回调唯一入口：按 `currentLoudness` 与开关态计算增益（开启且有数据：`computeGainDb()`；其余：0），对当前 `player` 即时应用，换档在途（`standbyPlayer` 非空）同步旁路实例（交接后增益不滞留旧值），Logger 'player' 埋点（开关切换、gain 值、无数据/守卫跳过原因）。

### PlayerController 内部增益应用点（既有流程插入）

- `playIndex`：resolve 后存 `currentLoudness`，`openStreamWithRetry(this.player, ...)` 前置 `setLoudnessGainDb`。
- `setQualityTier`：旁路实例 `standby` 在 `openStreamWithRetry(standby, ...)` 前置 `setLoudnessGainDb`（同一曲目响度随新 resolve 刷新 `currentLoudness`）。

### 设置页 UI 契约（SettingsPage）

- 「音量均衡」ListRow：标题「音量均衡」、说明「自动平衡不同视频间的音量大小」、`showToggle` 开关；`@Local volumeBalanceOn` 初值自 `AppStore.getNumber(KEY_VOLUME_BALANCE, 0)`；`toggleChange`：持久化 + `PlayerController.getInstance().setVolumeBalance(isOn)`。行形态沿播放设置组既有行。
- US4 重排（纯结构调整，零逻辑改动）：音质提示 Text 挪入账号组卡内底部——已登录分支「取消收藏提醒」行之后、未登录分支二维码块之后，条件渲染沿现状（未登录 → 64K 提示；非会员 → 192K/Hi-Res/杜比提示；大会员/冷启动占位 → 无），「播放设置」组内原位置移除；新「网络设置」SettingsGroup 含 Wi-Fi 默认音质、移动网络默认音质、仅在 Wi-Fi 环境播放三行，插于「播放设置」组之后，「播放设置」组保留启动时自动播放、后台打断续播、音量均衡、单集插入位置四行。

### 日志契约（Logger 'player' 频道）

- 增益应用：开关态、gain 值（两位小数）、measured/target 摘要。
- 跳过路径：无数据 / 可疑测量（undersized）/ 解析失败，各自可区分。
- `setLoudnessGain` 失败：错误码与消息。

### 验证与文档同步锚点

- 真机/模拟器验证样本锚点：§3.14 两样本（gain ≈ -6.6 / -0.5 dB）；命中率与 durl 形态回填 §3.14 未实测项。
- 设置页重排 UI 验证锚点：三种登录态账号组底部提示位置与文案、原位置无残留；「网络设置」组三行功能（toggle 持久化、音质弹层与 notice、取值展示）零回归。
- `docs/architecture.md` 同步：AudioPlayer 职责（响度增益）、BiliService 取流（voice_balance/volume 解析）、SettingsPage 播放/网络设置组与账号组提示、源码结构表零文件增删。
