# Implementation Plan: 播放页 UX 反馈修复 + 指定队列持久化

**Input**: Feature specification from `spec/v0.8-part4-player-ux-persist/spec.md`

## Summary

两个主轴：①「下一首播放」指定名单（designatedNextQueue FIFO）随 playlist.json 持久化——存储层加字段、恢复层过滤重建、消费层补同步保存，跨重启有效；②播放页七项 UX 修复——封面「视频」按钮改深色蒙层+白前景、窄屏五个选择面板改系统 bindSheet 底部浮窗（宽屏保持居中弹窗双轨）、播放顺序选项前置图标、详情简介排版与滚动条槽、底栏播放顺序/定时换位、源页文案统一与去计数；③模拟器实测反馈补充——底栏四菜单（倍速/定时/音质/播放顺序）选项统一 ListRow 行列表、五浮窗面板底色与队列面板玻璃公式统一（透明度一致）。

## Technical Context

**Language/Version**: ArkTS / ArkUI，compatibleSdkVersion 26.0.0
**Primary Dependencies**: 零第三方依赖；系统 bindSheet（common.d.ts 单声明）、Preferences、文件存储
**State Management**: 增量改动沿用现状——PlayerOverlay 为 V2 代装饰器 + V2State 包装（connectBool/connectNum），面板开关为 connectBool 包装或 bindSheet 直绑布尔；不引入新代际
**Storage**: playlist.json（AppStore.savePlaylistFile/loadPlaylistFile + FileUtil）；本轮起携带指定名单
**Testing**: `devecocli check arkts` + `devecocli build`（项目无测试套件）
**Target Platform**: HarmonyOS NEXT 手机/平板，窄屏断点 600vp（Constants.WIDE_BREAKPOINT_VP）
**Project Type**: 单模块移动应用（既有项目）
**Performance Goals**: 持久化为既有保存路径顺带写入，无新增 IO 独立请求；浮窗为系统转场，无自绘动画开销
**Constraints**: Constants 唯一真相源（新数值入 token、色彩入 $r('app.color.*')）；禁 any/unknown/as 断言；历史行为兼容（旧 playlist.json）

## Project Structure

### Documentation (this feature)

```text
spec/v0.8-part4-player-ux-persist/
├── spec.md
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── service/
│   ├── AppStore.ets            # save/loadPlaylistFile 增指定名单参数与字段
│   ├── PlayerController.ets    # 冷启动恢复过滤重建；markSessionPlayed 消费分支补保存
│   └── Constants.ets           # 新增行高 token；「添加至队列末」注释口径同步
├── pages/
│   ├── PlayerOverlay.ets       # 浮窗双轨、封面按钮配色、顺序图标、详情排版、底栏换位
│   ├── SourcePage.ets          # 多选按钮去计数、文案统一
│   └── SettingsPage.ets        # 单曲插入位置选项文案统一
└── component/
    └── ListRow.ets             # 增可选 selected/iconRotate 参数（默认零影响），播放顺序行列表复用
```

**Structure Decision**: 遵循既有项目架构（service/model/pages/component 分层，依赖单向），不引入新目录与新文件；改动全部落在六个既有文件 + 零新增资源（配色复用既有色资源）。无 MVVM 迁移诉求。

## Complexity Tracking

（无违宪项——不新增抽象层：五个面板窄屏化直接复用既有 builder 内容，不抽 SheetPanel 通用组件；抽取的收益点（倍速/音质面板结构相似）不足以抵消新抽象的认知成本。）

## Research & Decisions

- **D1 持久化载体**
  - **Decision**: playlist.json 根对象新增 `'designated': string[]` 字段（有序复合键列表），随既有 15 处 savePlaylistFile 调用点统一写入。
  - **Rationale**: 与队列条目同文件同生命周期，保存时机天然复用；冷启动一次读取即得队列+名单，无跨文件一致性窗口。
  - **Alternatives considered**: 独立 Preferences 键（需自管两处保存时序，产生名单与队列漂移窗口）；单独 designated.json（同漂移问题，多一个文件）。

- **D2 恢复契约**
  - **Decision**: loadPlaylistFile 解析 `'designated'`（缺省空数组）进 PlaylistSnapshot 新字段 designatedKeys；PlayerController 冷启动恢复处（loadPlaylistFile 调用点）在 items 恢复后按「队列中存在该 key」过滤，顺序保留，赋值 designatedNextQueue。
  - **Rationale**: 过滤保证被移除条目不复活；顺序保留满足多条指定的兑现次序（spec US1 场景 2）；旧文件缺字段走空名单默认路径，零迁移代码。
  - **Alternatives considered**: 不过滤直接恢复（重启后 randomIndex 的 indexOfKey 校验会消费失败静默跳过，但名单残留脏 key 影响后续 total 计数与日志可读性）。

- **D3 消费同步**
  - **Decision**: 盘点 designatedNextQueue 全部突变路径的落盘覆盖——randomIndex 弹出→playIndex 内既有保存（已含弹出后名单）；moveFlatItems→函数内既有保存；移除/清空路径→既有保存；markSessionPlayed 播放消费分支现状无保存（最近保存点在其前后事件），补一次 savePlaylistFile。
  - **Rationale**: FR-004 要求各路径同步持久化；逐路径核实后仅一处缺口，补一即闭环，避免「为保险到处加保存」的冗余 IO。
  - **Alternatives considered**: 给 designatedNextQueue 封装 setter 统一触发保存（新增间接层，改动面大于收益）。

- **D4 浮窗宿主分配**
  - **Decision**: 单节点仅可绑一个 bindSheet（SDK common.d.ts 单声明、重复绑定覆盖风险，与 SettingsPage 多 sheet 分散多宿主先例一致）→ 五浮窗五宿主：倍速/定时/音质/播放顺序四个 sheet 分别绑底栏对应按钮 Row，自定义定时 sheet 借队列按钮 Row 作宿主（BOTTOM sheet 宿主只承载生命周期与上下文，不决定视觉位置；代码注释说明借宿主原因）。
  - **Rationale**: 全部宿主为底栏稳定节点，生命周期与 PlayerOverlay 一致；避免根 Stack 二次绑定（已绑详情 sheet）。
  - **Alternatives considered**: 自定义定时并入定时 sheet 内容原位切换（改二级交互，超出本轮授权）；根 Stack 多绑（单节点单 sheet 约束下后绑覆盖前绑，详情 sheet 会被顶掉）。

- **D5 断点响应（双轨派生）**
  - **Decision**: 同一状态变量驱动双轨——宽屏 overlay 渲染条件 `isWide && showX`，窄屏 bindSheet 的 isShow 为 `!isWide && showX` 派生表达式；旋转/分屏断点切换时已打开面板即时转为新形态（sheet 关闭动画与 overlay 淡入无缝接管），spec 边界场景已就地修订为该最终态。
  - **Rationale**: 派生表达式零额外状态、零同步代码；「保持形态直至关闭」需捕获打开时形态的额外状态且收益仅限罕见旋转场景。
  - **Alternatives considered**: 打开时锁定形态直至关闭（多两个状态变量与分支，复杂度不成比例）。

- **D6 封面「视频」按钮配色**
  - **Decision**: 药丸底改 `duration_badge_scrim`（#99000000，封面时长角标既有深色蒙层）、前景（图标+文字）改 `fg_on_dark`（#FFFFFF）——即封面角标同款视觉语言；零新增色资源。
  - **Rationale**: 同一封面场景已有验证过的对比度方案，视觉一致且免新增 token。
  - **Alternatives considered**: 新增专用色资源（重复事实，违反同一事实一处维护）；玻璃底加描边（纯白封面上提升不足）。

- **D7 详情简介排版**
  - **Decision**: 简介行高由裸 24 改新 token `TOKEN_LINE_HEIGHT_DESC = 28`（Constants 注册，含注释）；简介 Text 移入滚动内容右 padding 留出滚动条槽（滚动条落在留白内不压字）；detailSheet 内边距区域级加大（上下/左右用既有 TOKEN_SPACE 系 token 上调一档）。
  - **Rationale**: 行高 24 对多行长文偏挤，28 为正文可读常规值；滚动条槽是压字问题的直接解；token 化消除既有裸数字债务。
  - **Alternatives considered**: scrollBar(BarState.Off) 直接隐藏滚动条（牺牲滚动位置感知，用户未要求去除滚动条）。

- **D8 选择面板行列表化（ListRow）**
  - **Decision**: 四菜单（倍速/定时/音质/播放顺序）选项均为 ListRow 全宽行列表。播放顺序四行取 playModeIcon 四态映射（顺序/倒序=order_play、随机=shuffle、单曲循环=repeat_1，倒序经旋转 180° 区分）、行尾 ✓ 标当前模式；倍速六档/音质 dash 音轨为普通行（选中项主题色高亮 + 行尾 ✓）；定时面板与底层单选模型对齐——预设/自定义/播完暂停全部为单选行（激活档位行尾 ✓，自定义激活时行尾显示设定时长；播完暂停点击武装并关闭面板，选任一项取代既有定时）；定时入口播完暂停武装时于表盘图标旁显示主题色 pause 小图标（与倒计时剩余数字同位同字号，复刻既有后缀槽模式）、「取消定时」（激活时）为危险行、选档生效延迟到面板关闭动画之后（启动/武装/取消在收起后执行，防条件插入的「取消定时」红行被退出动画带出闪红）。ListRow 增两个可选参数 `selected: boolean = false`（选中态：图标与标题主题色高亮 + 行尾 ✓）与 `iconRotate: number = 0`（图标旋转角），默认值下现有全部调用方行为逐像素不变。
  - **Rationale**: 播放顺序与设置页浮窗行视觉统一（用户选定 B 案），图标在选项前满足 FR-007；实测反馈要求四菜单行视觉一致；定时底层本为三态单选（无/倒计时/播完暂停，后选取代先选），开关形态暗示可叠加、与模型相悖，单选行 + ✓ 与主流音频 app 一致；可选参数默认零影响既有复用方（SettingsPage 等）。
  - **Alternatives considered**: 播完暂停保留 Toggle 开关形态（形态暗示独立可叠加，实际取代倒计时，语义矛盾）；保持 2×2 按钮网格内嵌图标（A 案，改动最小但视觉不统一）；ListRow 零改动用 trailing 槽放 ✓（选中行无主题色高亮，辨识弱于 ✓+高亮组合）；仅播放顺序改行列表（四菜单观感割裂）。
- **D10 浮窗面板底色玻璃公式统一**
  - **Decision**: 五个 bindSheet 的 `backgroundColor` 改 `Color.Transparent`，面板内容根自绘玻璃公式（与队列 GlassSheet/详情 detailSheet 同款）：`sheet_panel_background` + `backdropBlur(GLASS_BLUR)` + 顶部分隔线；宽屏 overlay 卡片（page_background）形态不变，内容根玻璃属性按 isWide 条件取空值（宽轨逐像素维持现状）。
  - **Rationale**: 实测反馈「四菜单浮窗比播放列表更透」——根因是四菜单 sheet 底色（sheet_background）无背景模糊，背后画面锐利透出；队列/详情的既有玻璃公式（v0.4 US6）已验证，照抄即统一。
  - **Alternatives considered**: bindSheet `blurStyle` 系统模糊样式（系统材质半径不可控，无法与 backdropBlur(20) 精确一致）；仅调 α 色值（色值本就近同，差异在模糊缺失）。

- **D9 文案与计数**
  - **Decision**: 全部「队列末播放」字面量替换为「添加至队列末」（SourcePage 多选按钮、SettingsPage 单曲插入位置选项文案与选项数组、Constants 相关注释同步口径）；源页多选两枚胶囊按钮模板串去掉 `(${selectedKeys.size})` 拼接。
  - **Rationale**: 单一词面全局统一；顶栏「已选 N 项」为计数唯一展示点。
  - **Alternatives considered**: 仅改按钮保留设置页旧词（用户已确认全部统一）。

## Data Model

- **playlist.json（存储格式，向后兼容）**
  - 既有：`{ lastIndex: number, lastPosMs: number, items: BiliVideo.record[] }`
  - 新增：`designated: string[]`——有序复合键列表（`bvid:page`，与 designatedNextQueue 元素同构）；旧文件无此字段按空数组解析
- **PlaylistSnapshot（内存快照）**
  - 既有：items: BiliVideo[]、lastIndex、lastPosMs
  - 新增：designatedKeys: string[]（默认空数组）
- **designatedNextQueue（PlayerController 既有 FIFO）**
  - 元素类型与语义不变（string[] 复合键，随机模式消费顺序）；本轮起生命周期扩展为「随队列文件持久化」，重启恢复后为过滤子集

## Contracts & Interfaces

- **AppStore.savePlaylistFile(items: BiliVideo[], lastIndex: number, lastPosMs: number, lastQualityCode: number, designatedKeys: string[]): void**
  - 新增第 5 参；写入 `'designated'` 字段；15 个既有调用点全部传 `this.designatedNextQueue`（PlayerController 内 14 处 + 无外部调用方，改动机械）
- **AppStore.loadPlaylistFile(): PlaylistSnapshot**
  - 返回值增 designatedKeys；解析缺省空数组，损坏走既有 catch 空快照路径
- **PlayerController 冷启动恢复（loadPlaylistFile 调用处）**
  - items 赋值后：designatedNextQueue = snapshot.designatedKeys 中存在于 playlist 的子集（顺序保留）；不存在的 key 静默丢弃
- **PlayerController.markSessionPlayed（播放消费分支）**
  - 消费指定键后补调 savePlaylistFile（D3 唯一缺口）
- **PlayerOverlay 面板双轨（内部结构契约）**
  - 面板内容 builder（标题+选项行）为窄屏 sheet 与宽屏 overlay 共用内容；宽屏 wrapper（mask_heavy+居中 76% 卡片）仅宽轨渲染；窄轨 bindSheet options 统一 `height: SheetSize.FIT_CONTENT, dragBar: true, showClose: false, preferType: SheetType.BOTTOM, backgroundColor: Color.Transparent, maskColor: mask_heavy`（系统默认遮罩比 GlassSheet 遮罩浅 15 个黑点，统一遮罩后面板底色与队列逐像素一致）；内容根玻璃属性按 isWide 条件：窄轨 `sheet_panel_background` + `backdropBlur(GLASS_BLUR)` + 顶部分隔线，宽轨全取空值（卡片形态不变）
  - 宿主：倍速→倍速按钮 Row、定时→定时按钮 Row、音质→音质按钮 Row、播放顺序→播放模式按钮 Row、自定义定时→队列按钮 Row（借宿主注释）
- **ListRow（共享组件，向后兼容扩展）**
  - 新增可选参数 `selected: boolean = false`（选中态：图标/标题主题色高亮 + 行尾 ✓）与 `iconRotate: number = 0`（图标旋转角）；默认值行为与现状逐像素一致
  - 播放顺序面板四个模式行为新增调用方之一：`ListRow({ title: 模式名, rowIcon: playModeIcon(mode), iconRotate: 倒序 180 其余 0, selected: 当前模式, rowAction: 选中该模式 })`；倍速/定时/音质面板选项行复用同组件（普通行/箭头行/Toggle 行/危险行）
