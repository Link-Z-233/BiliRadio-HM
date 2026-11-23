# BiliRadio 验证阶段专用文档

> **用途**：验证阶段专用文档——SDD Phase 5 必用本文档；非 SDD 验证（bugfix 直接修复后验证、轮次内小改动验证等）同样遵循。任何执行验证的一方（主代理/子代理）验证前必读。第 1 节验证范围判定；第 2 节构建验证（静态检查、告警清点、部署与设备）；第 3 节功能验证（UI 工具链、已知坑、交互地图、工作流、UI 行为与代码排查定式）；第 4 节经验追加区。
> **维护约定**：每轮验证结束后，验证执行方把之前没有新技巧**追加到第 4 节经验追加区**（≤10 行/条，可操作、不复述）；追加区条目积累后，由整理轮把内容**整合进第 2/3 节对应板块**（构建/部署经验进第 2 节，UI 验证经验进第 3 节对应小节；整合时去版本标签）并清空追加区——板块是知识的最终归宿，追加区只作缓冲。

## 1. 验证范围判定

- **SDD 轮次**：以 `tasks.md` Verification 阶段的标记为准：
  - `<!-- verification_scope: build-only -->`（默认）：仅执行第 2 节构建验证
  - `<!-- verification_scope: build+ui -->`：第 2 节通过后，再执行第 3 节功能验证
- **非 SDD 验证**：无 tasks.md 标记时，默认同样只做第 2 节构建验证；需要 UI 验证时走第 3 节
- **spec-verify 只验证一次**：失败不重调，报告交主代理处理并修复；主代理自行验证同一目标 ≤3 次
- 验证结果记录：SDD 轮次按 tasks.md 约定产出报告（PASS/FAIL/SKIP + 依据）；非 SDD 验证在对话中报告即可，不入文件

## 2. 构建验证（默认路径）

### 2.1 流程

1. `devecocli check arkts <本轮编辑的全部 .ets>` 静态预检（AGENTS 记作 `arkts_check`，实际调用形式是 devecocli 子命令，裸 `arkts_check` 不在 PATH，报「术语不会被识别」即改走子命令）
2. `devecocli build` 成功 = 构建通过；失败读输出中 `ERROR` 行定位（类型/导入/资源/权限/API 级别），修复后重试，同一目标 ≤3 次
3. 构建成功后 `devecocli run --skip-build` 部署，确认应用可安装启动（部署失败 ≠ 构建失败，按签名/设备问题排查）

### 2.2 静态检查口径

- SDK 自身误报：`@arkts.lang.d.ets` 71/79 行 6 条（interface/Retention/const enum）是 SDK 已知误报——预检通过标准 = 项目文件零错误，勿为 SDK 误报返工
- 单文件预检会把目标文件依赖链上全部文件的既有告警一并带出——单文件通过口径 = 目标文件自身零错误零告警，依赖文件告警与全量构建告警同口径处理（见 2.3 hunk 交叉比对判既有）

### 2.3 构建告警清点

- 告警清点必须全量构建：增量构建（CompileArkTS UP-TO-DATE）不重跑 lint，告警缺失是「没跑」不是「修了」——先 `devecocli build clean` 再 `devecocli build`，全量日志才可作告警验收依据
- 告警对账法：完整日志在 `Temp\deveco\devecocli\build-*.log`（每次构建新文件）；WARN 行恒后随一条消息行，按「WARN 行 + 后随消息行」配对 Group-Object 分组，总数对账后再逐类定位——比逐模式分别计数不易漏项
- syscap 类告警消息形态为 "The system capacity of this api 'X' is not supported on all devices"（清点检索 'system capacity'，非 'syscap' 字样）
- 「本轮新引入还是既有」判定：`git diff -U0 -- <告警文件>` 列出改动 hunk 行号区间，与告警行号交叉比对——告警行落在 hunk 外 = 既有告警非本轮回归，勿顺手修；多批未提交改动共存时共享同一 `git diff -U0`，判法不变（行号法粒度只到「本轮次内/轮次前」，需区分批内归属时按 hunk 内容识别批次）

### 2.4 部署与设备

| 命令 | 用途 | 关键点 |
|---|---|---|
| `devecocli device list` | 真机+模拟器清单 | **只列 active 设备**（无设备时显示 No active devices）；真机优先（用户平时真机测试） |
| `devecocli emulator start/stop <name>` | 模拟器管理 | 设备名用**位置参数**（`--device` 报 unknown option）；MatePad Pro 11，启动慢（分钟级）设长超时；启动可能超时不出现在 hdc list（非阻塞，改真机路径即可） |
| `devecocli run --skip-build` | 部署已构建产物 | 多设备时 `--device <name\|serial>` 指定 |
| `devecocli run --uninstall` | 先卸载再装 | 首装报 `9568263 install version downgrade` 或 `install sign info inconsistent` 时用 |
| `hdc tconn <ip:port>` | 无线真机连接 | hdc 已入 PATH（SDK `toolchains` 目录）；连接后 run 须 `--device <serial>` 显式指定——stopped 模拟器也占设备清单位，单在线设备同样触发 `DEVICE_SELECTION_REQUIRED` |
| `hdc kill; hdc start -r` | hdc server 崩溃恢复 | 连 `hdc list targets` 都空时用；恢复后重新 `hdc tconn` |

- 无设备判定口径：`devecocli device list` 只列 active 设备；`devecocli run` 才暴露 stopped 模拟器占位并以 DEVICE_SELECTION_REQUIRED 拒绝——确认「真机是否在线」以 run 输出为准，二者清单不一致
- 无线部署中途失连（hdc list targets 为空）：先 `hdc tconn <ip:port>` 重连（Connect OK 即恢复），再 `devecocli run --skip-build --device <ip:port>`——devecocli 自身不重连；无线设备频繁掉线时验证序列用 `&&` 串联一次跑完
- 部署 smoke FAIL_CRASH 未必真崩溃：重装会杀旧进程，先 `hdc shell pidof` 看新进程存活再判
- 锁屏：smoke 会误报进程死亡（10106102，开发者模式不可自动解锁）——解锁后装包自动重启或 `aa start`；恢复三步 `hdc shell power-shell wakeup` + `setmode 602` + 上滑解锁

## 3. 功能验证（UI）

### 3.1 工具链（deveco-cli）

#### 交互与检查
| 命令 | 用途 | 关键点 |
|---|---|---|
| `devecocli ui layout [--format json] [--mode simplified] [--depth n]` | dump 可见区域 ArkUI 无障碍树 | **只返回屏上节点**——目标不在屏内先滚动；配合 `--id` 定位 |
| `devecocli ui click [x y]` 或 `--id <id>` | 点击 | **优先 `--id`**（自动解析到节点中心，免坐标换算）；坐标与 id 互斥 |
| `devecocli ui longclick / doubleclick` | 长按/双击 | 同上 |
| `devecocli ui swipe <x1 y1 x2 y2> [--speed n]` | 精确滑动 | 下拉刷新测试用它（从列表中部往下滑）；速度 200–40000 px/s |
| `devecocli ui dircfling <up\|down\|left\|right>` | 定向快滑 | 页面/列表滚动首选（系统默认速度，无需坐标） |
| `devecocli ui text <text> [--id <id>]` | 输入文本 | 特殊字符内部 Base64 传输；无参时输入到当前焦点输入框 |
| `devecocli ui screenshot --path <dir\|png>` | 截图留证 | **不接收位置参数**，输出一律 `--path` 指定；路径必须可写且**不覆盖**已有文件（每张用不同文件名） |
| `devecocli ui window list` | 窗口清单 | 多窗口/半模态排查用 |

#### 验证中修复与日志
| 命令 | 用途 | 关键点 |
|---|---|---|
| `devecocli run --apply <file>` | 增量热修 | 验证中修复代码后比全量 run 快得多；改动文件列表写入 `.hvigor/<file>`（相对路径，一行一个） |
| `devecocli log --bundle-name <pkg> [--level E] [--from 5m] [--tail 200]` | hilog | **不要用 `--follow`**（代理会缓冲到进程退出）；用 `--from`/`--tail` 有界查询；复现问题前 `devecocli log clear` |
| `devecocli log --crash --bundle-name <pkg>` | 崩溃日志 | 闪退/白屏先跑这个 |

### 3.2 已知坑（Troubleshooting）

- **`ui layout` 找不到预期节点** → 节点不在屏内。先 `ui dircfling` 滚动或 `ui swipe` 滚到可见区再 layout。
- **a11y 值可能是渲染停滞时的缓存快照** → layout dump 值陈旧 ≠ 应用逻辑错误；先用点按交互测试响应性，再以 hilog 判定真实状态——日志是权威信号。
- **a11y 容器 bounds 不可靠** → 几何核对以叶子文本 x 反推几何链；触面/认领面二分定位：`ui longclick <x> <y>` 逐点 + 截图 + `recognize_ui_components` 判目标 UI 有无（先在已知认领区对照，确认 longclick 时长可达长按阈值）。
- **半模态 bindSheet** → 弹出后焦点窗口变化，`ui layout` 默认查焦点窗口；查不到时 `--window` 配合 `--id`，或 `ui window list` 先看窗口清单。
- **多设备连接** → 一切 ui/log/run 命令必须带 `--device <name|serial>`。
- **模拟器启动失败/OOM** → 宿主机内存瓶颈。启动前避免并发重负载（如并行构建）；失败重试一次，仍失败则按任务约定跳过 UI 验证不阻塞。
- **真机屏幕常亮**（用户指令）→使用真机 UI 验证开始前，打开屏幕常亮（设置→显示和亮度→休眠调长，或开发者选项「不锁定屏幕」），测试完成后关闭恢复默认——测试中途超时锁屏会打断验证序列（锁屏误报与恢复步骤见 2.4）。

### 3.3 交互地图（导航路径）

#### 首页（HomePage，Navigation 首页）
- 订阅列表：LazyForEach 列表，**单击订阅卡片 → 进入订阅源详情页（SourcePage）**
- 右上角"更多"按钮（ellipsis_circle 图标）→ **直达设置页**（Round 3 起，不再经 MorePage）
- 首页下拉刷新：**已注释禁用**（Round 3）——下拉手势应无任何反应（US3 验证点）
- "＋"入口 → 添加订阅 sheet（粘贴 BV 号/链接）

#### 订阅源详情页（SourcePage）
- **单击单个视频条目 → 仅该条入队并播放**（Round 3 起，US6）
- "播放全部"按钮 → 整源入队

#### 播放层（PlayerOverlay，全屏 bindContentCover）
- 唤起方式：点击底部迷你条（MiniPlayer）
- 播放按钮缓冲态：**加载弧线紧贴按钮**（US1 验证点：无缓存歌曲触发缓冲）
- 无任务空态：**"暂无播放内容"占位**（US2，迷你条与播放层一致）
- 主标题行点击/箭头 → 详情 bindSheet（62%）：**完整标题不被截断**（US10）
- 封面顶部留白（US10：margin top 24）
- ±15 秒按钮在传输区（按钮文字/图标形态）

#### 播放队列（QueueSheet，半模态）
- 打开：迷你条右侧队列图标 / 播放层队列入口
- **头部两行结构**（US5）：第一行"播放队列 共 N 首"，第二行 定位/搜索/多选/清空
- 多选模式：长按条目进入；"完成"按钮已移除（Round 2），**点遮罩关闭**

#### 设置页（SettingsPage，路由页）
- 路由：`pushPathByName('settingsPage', '')`；带参 `'playHistory'`/`'about'` 可直开对应面板
- 区块顺序：账号 → 本地与缓存 → 播放设置 → 音质（新增：Wi-Fi/蜂窝默认音质双设置）→ 省流量（仅剩省流量模式与仅 Wi-Fi 播放两项，原「优先低码率音频流」已移除）→ 外观（主题色板）→ **播放历史 → 日志查询（Round 3 新增）** → 取消收藏历史 → 关于
- 播放历史/日志查询均为 bindSheet 62%；关于 75%
- 日志查询（US9）：触发网络请求后应有 时间/类别（网络/错误）/URL 摘要/响应码 条目，倒序

#### 播控行为
- **顺序模式播完最后一首 → 停止，"播放结束"，不回绕**（US7）；手动点下一首 → 回绕第一首（预期行为非 bug）
- 随机/单曲循环 → 行为同旧版
- 播控中心（US8）：API 26 设备五元组 = 上一首/播放暂停/下一首/快退/快进；一级三元组 = 上一首/播放暂停/下一首（**系统硬规则，非缺陷**）

### 3.4 UI 验证工作流（每故事）

1. **前置**：确认应用已部署且在前台（`ui layout` 能 dump 到首页树）
2. **导航到目标场景**（按 3.3 交互地图）；不在屏内先滚动
3. **断言**：优先 `ui layout --format json` 找节点文本/属性（机器可判）；视觉性结论（间距/贴合度/颜色）用 `ui screenshot` 留证 + 自行判断
   - 瞬态 UI（如 0.6s 缓冲弧线）：截图时机可能错过窗口 → hilog 时序（try stream→initialized→prepared→playing）+ 尺寸链代码核对 + 多截图像素分析交叉取证
4. **失败时**：`devecocli log --from 2m --tail 100` 查异常 → 修复（改动文件写入 `.hvigor/changes.txt` → `devecocli run --apply changes.txt` 增量部署）→ 重新验证（每故事 ≤3 次尝试）
5. **网络依赖**：US1/US6/US9 需真实 B 站网络；订阅数据需账号已登录或有既有订阅。无网/未登录时记录 SKIPPED 原因，不算 FAIL
   - B 站风控：订阅源首次抓取可能触发 -352，静默刷新冷却后恢复——测试数据准备预留冷却时间
6. **每故事结束**：结果（PASS/FAIL/SKIP）+ 尝试次数 + 截图路径（如有）

**取证与提速**
- 应用日志取证直读落盘文件，优先于 UI 翻日志页：`hdc shell "grep -n '<关键字>' /data/app/el2/100/base/com.biliradio.app/haps/entry/files/biliradio_log.txt"` 一条命令定位全部目标行；UI 翻页一次一屏（每屏 10–30s），跨多屏取证成本高一个数量级
- 落盘日志路径是 HAP 级 `haps/entry/files/`（UIAbilityContext.filesDir），不是应用级 `base/<bundle>/files/`（后者只有 hiappevent）——按应用级目录找文件会误判「落盘失效」；调试模式 Logger 双写 hilog（info 级），但 hilog 缓冲区滚动快，历史取证以落盘文件为准
- 排查「单组件状态滞留」：对比同数据源兄弟组件的新鲜度（MiniPlayer vs PlayerOverlay），可快速隔离「广播正常、特定组件未更新」
- 播放完成类用例（如 US7 播完即停）优先入队短流（<3min）加速；手动 next() 回绕是预期行为非 bug

### 3.5 UI 行为与代码排查定式（验证中沉淀的 ArkUI 结论）

#### 动画
- **transition 无动画定式**：`.transition(TransitionEffect.X)` 不带 `.animation()` 且状态翻转不在 animateTo 内 = 组件直接出现/消失（官方文档明示），真机表现为「无动画」；修复二选一——补 `.animation({ duration })` 或状态翻转包 `animateTo`（多选/删除补位先例形态），后者可与既有动画节奏统一（TransitionEffect 自带参数优先于 animateTo，两套并存时曲线不齐）
- **行让位动画（内容被平滑挤压）成立三要素**：单 List（无 if/else 分支替换）+ 让位组件恒挂载（宽度 0↔宽/透明度 0↔1 绑定状态，SelectCheckbox 模式）+ 内容 layoutWeight(1) 真实让位；分支替换销毁重建行节点，补间无从发生
- **`DataChangeListener.onDataMove(from, to)` 官方语义是交换**（本机 lazy_for_each.d.ts 注释「swapped between the from and to positions」），不是移动——单发 onDataMove(idx, 0) 做置顶视觉上是 idx 与 0 互换；移动语义须发相邻交换冒泡序列 onDataMove(idx, idx-1)…onDataMove(1, 0)（同一 animateTo 内全序列补间 = 移动视觉）
- **手动拖拽 translate 挂点避开带 `.animation()` 的节点**：`.animation({ duration })` 无 value 过滤时覆盖组件全部可动画属性（含 translate），拖拽逐帧位移会被平滑成橡皮筋——translate/zIndex 挂 ListItem（无 animation），视觉属性（scale/背景/阴影）留根 Row

#### LazyForEach
- **同键节点跨 onDataReloaded 复用不重执行生成器闭包**（FAQ 828/1642）：行内容靠共享对象引用仍正确、闭包内位置量（startIndex/下标）过期——「重排后高亮/点击错位且滚出缓存区自愈」是此类 bug 的判别特征（尾部追加不动存量位置量所以无感）；免疫修法 = 位置量改复合键：高亮比 `itemKeyOf(...) === currentKey`（@Local，syncFrom 从 controller 当前条目同步，占位 0≡1 归一化天然对齐），点击/扫选/拖选经 `entryIndexOf(key)` 键实时定位下标 + -1 守卫（HistorySheet「点击时实时解析下标」同模式）；行 builder 与 LazyForEach 生成器的 index 参数应一并退场（闭包零位置量才叫根治）
- **随附清理候选**：QueueSheet 删除路径的 startIndex 重对齐循环 + notifyDataChange 强制重绑扫描在位置量清零后成死代码候选——删除前须真机回归删除路径

#### 手势与拖拽
- **行级手势阻塞系统拖拽（LazyForEach.onMove）**：编辑行带 LongPressGesture（同为长按识别）时手势仲裁阻塞 onMove 拖拽、编辑态拖不动；修法行根节点 `.enabled(!editMode)`——编辑态行级交互全禁、触摸穿透给 LazyForEach 拖拽手势，整行恢复可拖（零手势的行 + onMove 才是拖拽正常的前提；合并双 List 为单 List 时编辑行会带上正常态手势，此坑必踩）；`.enabled` 穿透后 swipeAction 绑在 ListItem 层是否被连带压制须真机核验（编辑态不可侧滑要求）
- **手势认领面**：List 恒绑 onMove 后系统拖拽的可达面 = 行内未被手势认领的盒区——行 padding 留在无手势的根节点时，边缘 padding 带长按直接进系统拖拽（非编辑态也触发，落子才被闸拒绝，拖拽视觉已发生）；认领面必须与整卡重合，行 padding 应落在携带 LongPressGesture 的内容节点上
- **`GestureEvent` 无 `globalY`**（该字段属 `FingerInfo`，gesture.d.ts）；PanGesture 跟手位移用 `GestureEvent.offsetY`（按压起算累积偏移，PanGesture 场景专用）——arkts_check 报 `Property 'globalY' does not exist on type 'GestureEvent'` 即此坑

#### 尺寸与几何
- **ArkUI `.width()` 是内容宽、padding 在外另加**（`layoutWeight` 才是含 padding 的总尺寸分配）：width(0)+padding 造隐形残带触面，残带若仅挂 pan 则长按漏给父级内建拖拽——真零宽须 width 与 padding 同条件归零；padding 迁移本身保恒等（内容起点不变）；几何推演按 content-box 逐模式算总占位，勿按 border-box 直觉推
- **换位阈值等令牌计算**：按结构逐项加（行内容高 + 行上下 padding + List space）——令牌取值先 grep Constants 再算，勿凭记忆（TOKEN_SPACE_S 是 8 不是 4 一类）

#### 字段与 API 口径
- **跨模型复用 @Builder 的结构化类型坑**：复制同构 builder 到新宿主时先核行数据源的真实模型类型，形参随宿主数据源改（builder 只读字段时改形参类型即最小修复；arkts-no-structural-typing + assignability 双报错）
- **系统 API 字段以本机 d.ts 为准**：`SharedRecord.content` 注释明示 text/link 内容走 content、`uri` 仅承载文件 URI（`sdk\default\hms\ets\api\@hms.collaboration.systemShare.d.ts`）——接收侧读 `records[0].uri` 会静默拿空、分享导入整体无效；plan/示例写法先查 d.ts 再定字段，勿照抄文档记忆

## 4. 经验追加区（验证执行方维护）

<!-- 每轮验证后在此按固定格式追加（最新在最下，不回改历史条目）：
- <版本号+轮次或场景>（<验证范围：build-only / build+ui>，<部署环境：真机 / 模拟器>）：
  - <一条经验 = 可操作结论 + 触发条件或坑 + 处置方式；≤10 行/条>
  -->

- v0.8-part2 设置页分组重组（build-only，未部署）：
  - bindSheet 第二参必须是 CustomBuilder：直接传组件实例 `OptionSheet({...})` 时 arkts_check 报 "Argument of type 'OptionSheet' is not assignable to parameter of type 'CustomBuilder'"（build 同步拦截）；删旧 @Builder 换公共组件实例时必踩；修法 = 薄 @Builder 方法包组件实例，bindSheet 传 `this.xSheet()`（SettingsPage aboutSheet 既有惯例）

- v0.8-part2 设置页再优化批（build-only，未部署）：
  - 自定义组件尾随闭包后不可链属性：`.bindSheet` 等属性链直接接在 `SettingsGroup({...}) {...}` 尾随闭包之后时 arkts_check 报 "Declaration or statement expected" + "Cannot find name 'bindSheet'"（build 同步拦截；内置组件如 Column 尾随闭包后链属性合法，勿类推到自定义组件）；修法 = 内置容器（Column）包裹该组件，属性链挂包裹容器，就近挂载语义不变

- v0.8-part2 真机自查反馈修复（build-only，未部署）：
  - bindSheet FIT_CONTENT 高度下内容根节点禁 `height('100%')`：fit-content 测量把 '100%' 解析为 sheet 满高（≈全屏），三选项弹窗真机整体全屏；修法 = 根节点与选项列表均内容自适应（去根 `height('100%')` 与 `Scroll.layoutWeight(1)`，内容超 sheet 上限时 Scroll 在约束内转内部滚动）；`height('100%')` 铺满形态仅适用固定百分比高度

- v0.8-part3 无缝音质切换（build-only，未部署）：
  - 全量构建日志（`Temp\deveco\devecocli\build-*.log`）内 WARN 行的文件路径是正斜杠（`File: D:/.../AudioPlayer.ets:128:42`），Select-String 用反斜杠模式（`service\\File`）检索不到——按文件定位告警一律用正斜杠模式（如 `service/(PlayerController|AudioPlayer)\.ets`）；arkts_check 与 build 全量 lint 告警口径不同（build 会多报「Function may throw」类），对账以 build 日志为准、arkts_check 作预检

- v0.8-part3 无缝音质切换模拟器实测（build+ui，模拟器）：
  - 播放行为时序核算以应用日志为权威源（`hdc shell tail /data/app/el2/100/base/com.biliradio.app/haps/entry/files/biliradio_log.txt`）：hilog 只含 state 转换/try stream url 等少数点位，setQualityTier 详情与 statusMsg 只进应用日志；工具调用延迟高达 20-30s/次，位置推进凭体感估算会误判「跳进度」，须按日志时间戳换算（复播起点到操作时刻 × 倍速）

- v0.8-part3 无缝音质切换模拟器实测（build+ui，模拟器）：
  - 模拟器锁屏三步恢复：`power-shell wakeup` + `power-shell setmode 602` → `devecocli ui swipe 640 2600 640 1000 --speed 2000` 上滑解锁 → `hdc shell aa start -a EntryAbility -b com.biliradio.app` 拉回应用（锁屏后应用转后台）；防再锁 `power-shell timeout -o 600000` **仅实体机生效，模拟器无效**（模拟器长测中途再锁屏按三步恢复处置即可）；`devecocli ui` 无 back 命令，swipe 参数是 `--speed` 非 `--duration`；模拟器网络为 eth0 NAT（`NetUtil.isWifi()`=false、wlan0 无 AP 可连），Wi-Fi↔蜂窝翻转类用例（自动换档触发）在模拟器不可测

- v0.8-part4 播放层 UX + 持久化模拟器实测（build+ui，模拟器）：
  - recognize_ui_components 多模态模型 403（Invalid model）时视觉断言降级像素分析：PowerShell System.Drawing 按无障碍树 bounds 分区采样（白/深/彩色/中灰像素占比 + RGB 均值），行高（文字带高 + 带间距 = 行距像素）、选中主题色 vs 未选中灰、蒙层对比度均可量化判定；识别工具要求图片在 worktree 内（截图先拷入），像素分析脚本无此约束；toast 瞬态提示 UI 工具链抓不到，行为断言改走落盘日志（register/play/consumed 链）与 playlist.json 直读
  - 指定名单「弹出即消费」路径下 `consumed on play` 日志不出现属正常：`randomIndex` 选曲时 `shift()` 弹队首（只有 `designated next play` 日志），`markSessionPlayed` 仅对仍留在 FIFO 的键（手动点播场景）补剔落盘；剩余 FIFO 由 13 处保存点顺带落盘，验余量直接读 playlist.json 的 designated 字段

- v0.8-part4 底栏菜单 ListRow 化 + 玻璃统一模拟器实测（build+ui，模拟器）：
  - `devecocli run` 偶发清空应用数据：一次重部署后 files 目录整体重建（订阅/播放列表/日志全失），下次部署又正常保留——长 UI 验证前先确认测试数据在位（`ls .../files/`），被清时按订阅→点播流程重建，勿当回归排查
  - 队列仅剩一首时长验证中自然播完 → 队列空 → 播放层（overlay+迷你条）自动收起，界面跳回下层页面且无日志报警——长测中途界面「无故」消失先查 `state | completed` 再怀疑改动回归；`uitest` 点击在 sheet 弹出动画期偶发落空（点了无反应），重试一次即中，结论前勿单次点击定生死
  - 面板底色统一比对法：同一背景页（播放页封面）下分别截两面板，System.Drawing 对无文字行距带采样 avgRGB/lumStd，磨砂面板方差 <2、两面板均值差 <1 即视觉一致；系统 bindSheet 默认蒙罩（约 20% 黑）比 GlassSheet 的 mask_heavy（浅色 35% 黑）浅约 5 个灰阶，统一蒙罩用 `maskColor: $r('app.color.mask_heavy')`

（追加区条目积累后由整理轮整合进第 2/3 节对应板块并清空本区）
