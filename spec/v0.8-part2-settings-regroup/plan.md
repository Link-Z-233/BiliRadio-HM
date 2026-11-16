# Implementation Plan: v0.8-part2 设置页分组重组与选项弹窗公共组件

**Input**: Feature specification from `spec/v0.8-part2-settings-regroup/spec.md`

## Summary

设置页结构轮（含再优化批）：① 分组重组最终态——历史同步与取消收藏提醒留在账号分组（不设独立同步组）；退出登录由独立危险行改为用户行右端「登出」胶囊按钮（ListRow 新增行尾槽位）；播放历史独立为无标题单行卡片；单集插入位置回归播放设置组末行；「通用」改名「系统」；② 订阅管理合并——独立分组删除，「系统」分组头部新增订阅管理行（副标题 + 箭头），点击弹 OptionSheet（导出订阅/导入订阅），返回链接入；③ 新建 `OptionSheet` 选项弹窗面板组件（固定标题 + 可选固定通知 + 可滚动选项列表 + 背景铺满全弹窗），音质/单集插入/订阅管理三处弹窗共用；④ 弹窗体验修正——高度改内容自适应（SheetSize.FIT_CONTENT 消底部留白）、浅色 sheet_background 不透明度提升至与深色对齐（90% alpha）；⑤ 设置页底部遗留迷你播放器净空删除（设置层物理覆盖胶囊，净空为纯空白）；⑥ 外观组主题色色板行均匀分布（色板集合与选择行为不变，自定义色需求已放弃）。全部设置项持久化键与行为零变化。

## Technical Context

**Language/Version**: ArkTS（ArkUI），compatibleSdkVersion 26.0.0
**Primary Dependencies**: 零第三方依赖
**State Management**: 增量改动沿用现状——SettingsPage/ListRow/OptionSheet 均为 `@ComponentV2`（`@Param` 纯展示，无内部状态观测）
**Storage**: 既有 `AppStore`/preferences 键零变化（KEY_HISTORY_SYNC / KEY_UNFAVORITE_ASK / KEY_SINGLE_INSERT_NEXT / KEY_WIFI_AUDIO_QUALITY / KEY_CELLULAR_AUDIO_QUALITY / KEY_ACCENT_COLOR 原样）
**Testing**: 无测试套件；验证 = `arkts_check` 静态预检 + `devecocli build`（build-only 规范）
**Target Platform**: HarmonyOS NEXT 单模块应用
**Performance Goals**: 弹窗打开/滚动无卡顿（与现状一致）
**Constraints**: 全部被移动设置项行为与重组前逐字节一致；bindSheet 宿主挂载点不迁移（API 24 平板已知坑，见 SettingsPage 既有 ponytail 注记）
**Scale/Scope**: 改动文件——SettingsPage（核心）、ListRow（行尾槽位）、Constants（TOKEN_SPACE_13，初版批已加）、浅色 color.json、docs/architecture.md；OptionSheet 组件本轮零改动（初版批已建）

## Project Structure

### Documentation (this feature)

```text
spec/v0.8-part2-settings-regroup/
├── spec.md
├── plan.md              # This file
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── component/
│   ├── OptionSheet.ets        # 初版批新建：选项弹窗面板（本轮再优化批零改动）
│   └── ListRow.ets        # 改：新增行尾 @BuilderParam trailing 槽位（登出胶囊注入）
├── pages/
│   └── SettingsPage.ets       # 改：分组重组最终态；三弹窗接线；登出胶囊；底部净空删除；色板行均匀分布
└── service/
    └── Constants.ets          # 改：新增 TOKEN_SPACE_13（初版批已加）；胶囊尺寸令牌缺失时补

entry/src/main/resources/base/element/
└── color.json                 # 改：浅色 sheet_background #80FFFFFF → #E6FFFFFF（alpha 对齐深色）

docs/
└── architecture.md            # 改：组件表 OptionSheet/ListRow 行更新、SettingsPage 分组描述同步
```

**Structure Decision**: 遵循现有项目架构（pages/component/service 分层）。行尾自定义内容走 ListRow 槽位扩展（而非在 SettingsPage 重写用户行，避免头像/大会员徽标渲染逻辑复制）；分组重组与接线全部在 `pages/SettingsPage.ets` 单文件内完成；浅色色值改动仅动 `resources/base/element/color.json` 单点（该色使用面全为选项弹窗，无外溢）。

## Complexity Tracking

无宪法检查违规，无需填表。

## Research & Decisions

### D1: OptionSheet 组件边界——面板组件，不封装 bindSheet

- **Decision**: `OptionSheet` 只做弹窗**内容面板**（标题/通知/列表三段 + 背景铺满）；`bindSheet` 仍由 SettingsPage 在既有挂载点声明（单集插入挂标题 Row、音质挂内层 Stack；新增订阅管理弹窗就近挂系统分组卡片），`onDisappear` 与高度声明保持在 bindSheet 侧。
- **Rationale**: bindSheet 宿主迁移存在平台坑（SettingsPage 既有 ponytail 注记：外层根 Column 挂载在 API 24 平板自动关闭）；现挂载点已验证稳定，新弹窗就近挂系统分组卡片，最小改动。
- **Alternatives considered**: 组件自封装 bindSheet（需自造锚点组件，复杂且重蹈宿主坑）——弃。

### D2: 弹窗高度内容自适应 + 背景全覆盖

- **Decision**: 三个选项弹窗 bindSheet 高度由固定百分比（40%/25%）改为 `SheetSize.FIT_CONTENT`（API 11+，内容自适应高度）；面板根节点高度内容自适应（背景 `sheet_background` 覆盖内容区）；选项列表 `Scroll` 内容自适应（不用 `layoutWeight`）、`edgeEffect(EdgeEffect.Spring)`；bindSheet options 的 `backgroundColor` 维持 `sheet_background`。根节点底部 padding = `navBarHeight + TOKEN_SPACE_S` 避让手势指示条（真机反馈：内容贴窗口物理底部，最后一行被指示条叠压、点击被手势区吞掉；FIT_CONTENT 测量自动计入避让量，弹窗随之增高）；about 弹窗内容底部同步 `navBarHeight + TOKEN_SPACE_XL`（内容超 75% 可滚时生效，短内容行为不变）。
- **Rationale**: 留白根因 = 固定屏高百分比在短内容下强制撑出大片空白；FIT_CONTENT 让弹窗高度贴合内容（2 选项弹窗矮、VIP 7 档弹窗高），同一声明通吃三处。真机实测（用户反馈）：fit-content 测量下根节点 `height('100%')` 解析为 sheet 满高（≈全屏），三弹窗整体变全屏——`100%` + `layoutWeight` 是固定百分比高度的铺满形态，FIT_CONTENT 下不可用；根节点与列表均内容自适应后，弹窗高度贴合内容，内容超出 sheet 上限时 `Scroll` 在约束内转列表内部滚动（本项目最长 VIP 7 档 ≈460vp，低于屏高上限，不触该边界）。
- **Alternatives considered**: 按选项数算百分比高度（魔法公式，观感随档位数漂移）——弃；恢复手调固定高度（每弹窗一个魔数，留白只减不消）——弃；根节点保留 `height('100%')` 的「标准组合」（真机实测全屏，已否）——弃。

### D3: 组件契约与令牌化

- **Decision**: `OptionSheet` 为 `@ComponentV2` 纯展示组件：`@Param title: string`、`@Param notice: string = ''`（空串不渲染通知区）、`@Param optionLabels: string[]`、`@Param selectedLabel: string`（无选中态场景传 `''`，不渲染 ✓）、普通回调属性 `onSelect: (index: number) => void`。选项行渲染内聚在组件内（Text + 条件 ✓ 强调色高亮）。字体/间距全令牌化：标题字号用既有 `TOKEN_FONT_17`；行内边距 13 用 `Constants.TOKEN_SPACE_13`（数值不变，纯标准化）。
- **Rationale**: 三个弹窗的行结构完全同构（label + 条件 ✓），内聚后 SettingsPage 只喂数据；选中态用 `selectedLabel` 字符串比对即可；订阅管理为动作菜单语义，传 `''` 自然退化为无选中态，无需组件加开关。
- **Alternatives considered**: `@BuilderParam` 让宿主注入行渲染——三处行结构相同，注入是多余灵活性；`onSelect(label: string)`——字符串回传需宿主反查，索引更直接。

### D4: 分组重组最终态落位（SettingsPage build 内纯搬移）

- **Decision**: 「播放与同步」分组拆解，内容各归其位：
  - **账号分组**（登录分支）：用户行（ListRow，avatar/vipBadge/showDivider 不变，新增 trailing 槽注入「登出」胶囊）→ 历史同步（`showDivider: true`，开关行为不变）→ 取消收藏提醒（末行无 divider，开关行为不变）；未登录分支（loginControls + Divider + cookieBlock）与 accountLoading 分支不变；原独立「退出登录」危险行删除。
  - **播放历史**：独立 `SettingsGroup({ title: '' })` 无标题单行卡片，插在账号分组之后（状态提示行位置不变），单行无 divider，clock 图标入口行为不变。
  - **播放设置**：「仅在 Wi-Fi 环境播放」恢复 `showDivider: true`，单集插入位置回归末行（无 divider）。
  - 「通用」→「系统」（订阅管理/日志查询/关于，见 D6）。
  - 全部 ListRow 对象原样搬移（键、文案、回调零变化）。
- **Rationale**: 用户反馈回归——历史同步/取消收藏提醒本就源自账号分组（本轮初版移出，再优化批移回）；未登录时两开关在登录分支内自然隐藏，无空分组问题；「退出登录」独立危险行与用户信息分离，改为行尾胶囊后账号组信息密度更优。
- **Alternatives considered**: 独立「同步」分组——用户明确要求挪回账号分组；登出保持独立危险行——用户明确要求改为行尾按钮。

### D5: 三弹窗迁移接线

- **Decision**: 删除 `qualitySheetPanel` / `singleInsertSheetPanel` 两个 `@Builder`，bindSheet builder 换为薄 `@Builder` 包裹的 `OptionSheet` 实例（CustomBuilder 类型约束，沿 aboutSheet 惯例）：
  - 音质：`title` 按 qualityEditTarget（'Wi-Fi 默认音质'/'移动网络默认音质'），`notice` 按登录/会员态（三态文案不变），`optionLabels` = qualityOptions() 映射 label，`selectedLabel` = AudioQuality.label(currentEditTier())，`onSelect` 反查 tier 调 applyQualityTier。
  - 单集插入：`title='单集插入位置'`，`notice=''`，`optionLabels` = singleInsertOptions()，`selectedLabel` = singleInsertLabel()，`onSelect` 调 applySingleInsert(index === 1)。
  - 订阅管理：`title='订阅管理'`，`notice=''`，`optionLabels` = ['导出订阅', '导入订阅']，`selectedLabel=''`，`onSelect` 按 index 分发导出/导入既有链路。
- **Rationale**: 档位过滤、✓ 高亮、持久化、关闭逻辑、导出导入链路全部留在页面（现状代码），组件零业务知识；薄 @Builder 包裹规避 `Argument of type 'OptionSheet' is not assignable to parameter of type 'CustomBuilder'` 编译错（初版批实施已验证的既有惯例）。
- **Alternatives considered**: 组件接收 tier 枚举——引入 model 依赖，破坏纯展示定位。

### D6: 订阅管理合并接线（US2）

- **Decision**: 删除「订阅管理」独立分组（导出/导入两 ListRow 及其组壳，行回调方法保留）；「系统」分组头部插入「订阅管理」行：标题「订阅管理」、副标题「导出或导入订阅备份」、`showArrow: true`、`showDivider: true`，图标从 sys.symbol 现有条目选取（导入导出语义，以 sysResource.js 校验存在性）；新增状态字段 `showSubManageSheet: boolean = false`；行点击置 true，bindSheet（FIT_CONTENT + sheet_background）就近挂系统分组卡片；薄 @Builder `subManageSheet` 包 OptionSheet（见 D5）；`registerSettingsBack` 返回链头部插入 `showSubManageSheet` 分支（优先关闭）。
- **Rationale**: 合并消掉单行数最少的独立分组；导出（空列表拦截 + 分享）与导入（选择器 + 校验合并 toast）链路已是页面既有方法，onSelect 按 index 分发零新逻辑；返回链是三弹窗一致契约。
- **Alternatives considered**: 保留独立分组——用户已明确要求合并；弹窗带合并说明 notice——用户已选「仅选项标签」。

### D7: 登出胶囊与 ListRow 行尾槽位（FR-004/FR-005）

- **Decision**:
  - **ListRow** 新增 `@BuilderParam trailing: () => void`（默认空 @Builder，渲染于行内容 Row 末段——valueText 之后、toggle/arrow 之前；未传时零渲染，既有全部调用零影响）。
  - **登出胶囊**（SettingsPage 注入的 @Builder）：`Button('登出')`，高度/圆角/字号取 Constants 现有令牌（缺失则在 Constants 新增语义化令牌，如胶囊高度令牌），中性淡底（`page_background`，同登录页「扫码登录」次要按钮底）+ `danger_red` 文字，横向内边距适度；点击调既有 `confirmLogout()`（确认弹窗行为不变）。
  - 用户行 rowAction 为空，胶囊点击无冒泡冲突。
- **Rationale**: 行尾自定义内容走共享组件槽位而非重写用户行——头像加载回退、大会员徽标等渲染逻辑零复制；胶囊底色取中性淡底而非 accent 淡底，避免红字与主题色撞色；Button 消费点击事件，行本身无 rowAction，天然无冲突。
- **Alternatives considered**: SettingsPage 内联手写用户行（复制头像/徽标逻辑，重复代码）——弃；tintBg 底（accent 淡底 + 红字撞色风险）——弃。

### D8: 浅色不透明度修正（FR-011）

- **Decision**: `resources/base/element/color.json` 浅色 `sheet_background` `#80FFFFFF` → `#E6FFFFFF`（alpha 80→E6，即 50%→90%，镜像深色 `#E61E1E22` 的 90% alpha）；深色值与 `sheet_panel_background` 不动。
- **Rationale**: 浅色 50% 白导致页面内容透出、观感「过透」；对齐深色 90% alpha 后深浅一致。该色引用仅 3 处（OptionSheet 根节点 + 两 bindSheet options），全部为选项弹窗面，无外溢。
- **Alternatives considered**: 顺带调 `sheet_panel_background`——用户未反馈该面问题，不动（最小改动）。

### D9: 设置页底部净空删除（FR-016）

- **Decision**: SettingsPage 滚动内容 Column 底部 padding 由 `MINI_PLAYER_CLEARANCE + navBarHeight` 改为 `navBarHeight + TOKEN_SPACE_L`（常规留白令牌）；HomePage/SourcePage 的 MINI_PLAYER_CLEARANCE 让位不动（胶囊在那两层可见）。
- **Rationale**: Index Stack 层序中设置层（L2）物理覆盖迷你播放胶囊（注释原话「物理覆盖替代原显隐动画」），打开设置页时胶囊不可见，88 净空表现为纯空白；同为覆盖层的 LogPage 仅留 navBarHeight（L256），为覆盖层正确模式。
- **Alternatives considered**: 保留净空以备胶囊层级回调——层序变更须整轮评估，不预留死代码。

### D10: 主题色色板行均匀分布（FR-017）

- **Decision**: `accentSwatch` 外层槽位容器加 `.layoutWeight(1)`（6 槽等宽铺满整行），外层 Row 去 `space`（等宽槽位自足），左右 padding（TOKEN_SPACE_14）与内圈 24 圆点、选中描边逻辑不变；色板集合 `ACCENT_PRESETS` 与 `Appearance.setAccentColor` 校验零改动。
- **Rationale**: 现状固定 32 宽 + space 左排，右侧留空不均；`layoutWeight(1)` 等分与外观模式三选项行同一模式（appearanceOption 已用 layoutWeight(1)），模式一致。
- **Alternatives considered**: 均匀分布 + 自定义色入口（第 7 槽）——用户已明确放弃自定义需求。

### D11: 文档同步

- **Decision**: `docs/architecture.md` 同步：component/ 文件数（8→9，OptionSheet）与组件表（OptionSheet 行：选项弹窗面板，音质/单集插入/订阅管理三处共用；ListRow 行补行尾槽位）；SettingsPage 职责描述同步分组最终态（账号组含同步开关与登出胶囊/播放历史独立卡片/系统组含订阅管理合并行/底部净空模式）。token-exemptions 无新增（TOKEN_SPACE_13 消裸数字，非豁免）。
- **Rationale**: 活文档随代码同步规范；本轮源码有文件新增与共享组件变更，架构文件表必动。

## Data Model

无新数据实体。组件输入为纯字符串数组与回调；既有持久化键与默认值零变化（FR-015）：

| 键 | 类型 | 默认 | 归属行（重组后） |
|---|---|---|---|
| KEY_HISTORY_SYNC | number(0/1) | 1 | 账号 · 历史同步（仅登录显示） |
| KEY_UNFAVORITE_ASK | number(0/1) | 1 | 账号 · 取消收藏提醒（仅登录显示） |
| KEY_SINGLE_INSERT_NEXT | number(0/1) | 0 | 播放设置 · 单集插入位置（末行） |
| KEY_WIFI_AUDIO_QUALITY | number(tier) | MAX | 播放设置 · Wi-Fi 默认音质 |
| KEY_CELLULAR_AUDIO_QUALITY | number(tier) | Q132K | 播放设置 · 移动网络默认音质 |
| KEY_ACCENT_COLOR | string(hex) | #FB7299 | 外观 · 主题色（色板与校验不变） |

## Contracts & Interfaces

### OptionSheet 组件接口（component/OptionSheet.ets，本轮零改动）

| 成员 | 类型 | 必填 | 语义 |
|---|---|---|---|
| title | string (@Param) | 是 | 固定标题，渲染于面板顶部 |
| notice | string (@Param) | 否（默认 ''） | 状态通知，渲染于标题下方固定区；空串不渲染 |
| optionLabels | string[] (@Param) | 是 | 选项标签列表，渲染于可滚动列表 |
| selectedLabel | string (@Param) | 是 | 当前选中项标签（✓ + 强调色依据）；传 '' 表示无选中态 |
| onSelect | (index: number) => void | 否（默认空实现） | 点选选项行回调（选项在 optionLabels 中的下标） |

视觉契约：根节点高度内容自适应（背景 `sheet_background` 覆盖内容区）；标题固定、通知固定、列表滚动（Spring 过冲，超 sheet 上限时内部滚动）；选中行强调色 + ✓（`selectedLabel=''` 时全部无 ✓）。

### ListRow 新增接口（component/ListRow.ets）

| 成员 | 类型 | 必填 | 语义 |
|---|---|---|---|
| trailing | () => void (@BuilderParam) | 否（默认空 @Builder） | 行尾自定义内容槽位；渲染于 valueText 之后、toggle/arrow 之前；未传时零渲染 |

既有 24+ 处 ListRow 调用零改动（默认空实现向后兼容）；登出胶囊为该槽位首个使用方。

### SettingsPage 消费契约

- bindSheet 挂载点不迁移；三个选项弹窗高度统一 `SheetSize.FIT_CONTENT`（about 弹窗 75% 不动）；`onDisappear`、`registerSettingsBack` 返回链全覆盖三弹窗；OptionSheet 接入 `AS_NAV_BAR_HEIGHT`，根节点与 about 内容底部加 navBarHeight 避让手势指示条（FR-018）；「关于」弹窗「完成」按钮移除，showAbout 纳入返回链，核心功能与项目地址条目保持紧凑文本行、内容一屏完整展示（FR-019）
- `showQualitySheet` / `qualityEditTarget` / `showSingleInsertSheet` 状态字段与赋值路径不动；新增 `showSubManageSheet` 字段与返回链分支
- 分组行搬移后所有 `AppStore.putNumber` 调用点随行原样迁移，语义零变化；导出/导入方法原样复用；`confirmLogout()` 原样复用
- 滚动内容底部 padding 模式与 LogPage 覆盖层对齐（navBarHeight + 常规留白，不含 MINI_PLAYER_CLEARANCE）
