# TTyFormSurface —— 子内容宿主设计文档

> 状态:设计草案(待评审)  ·  日期:2026-07-15  ·  作者:讨论产出

## 1. 目标

让 `TTyForm` 的**内容画到窗口真正的可见边缘**(消除右/下那条 ~5px 的填不满死带),同时**保留** `WS_THICKFRAME` 带来的原生 Aero Snap、原生缩放、DWM 圆角/阴影。做法与 Chromium / Electron / Windows Terminal 完全一致:**内容渲染进一个铺满 client 的子窗口(内容宿主),顶层窗口只管边框**。

## 2. 根因回顾(为什么必须这么做)

- 顶层窗口若是 `WS_THICKFRAME`,DWM 把它的**可绘制后备面高度锁死在 `窗口高 − 2×边框`**,比可见窗口还矮 ~7px(顶边没有隐形余量,那圈顶框必须显示在某处)。
- 直接在**顶层 Form 的 client DC** 上用 GDI 绘制,永远有一条 ~边框宽的带填不满,只能选它出现在顶部 / 底部 / 平分。当前放在底部(≈5px)。
- **子 HWND 没有 `WS_THICKFRAME`,后备面 = 自身完整矩形**,能画到真边缘(已实测:statusbar / 品红描边子控件都到边)。
- 结论:纯顶层 GDI 到边**没有干净解**;业界统一用**子内容宿主**。三轮检索一致。

## 3. 架构总览

```
TTyForm  (顶层窗口 = 边框所有者)
│   职责: WS_THICKFRAME(Snap/缩放) + NCCALCSIZE(去系统标题) + DWM 圆角/阴影
│         Form 自身不透明; 自身 Paint 退化为兜底(内容由 Surface 盖住)
│   Object Inspector 里可见组件: 仅 Form + Controller
│
└─ TTyFormSurface  (子 HWND · csSubComponent · Align=alClient · 不进面板 · 不可删)
   │   职责:
   │     1) 铺满 Form 的 client(子窗口画到真边缘 → 盖掉 Form 的死带)
   │     2) 渲染 CSS 里 `form` 选择器的背景(纯色 / 渐变 / 图片 / 玻璃)
   │     3) 作为 ITyGlassHost —— 提供 backdrop 快照给玻璃子控件采样
   │     4) 承载所有内容(标题栏 + 用户控件)
   │   .lfm: 容器本身隐式(内部件);其名下控件正常流式化(GetChildren)
   │
   ├─ TTyTitleBar   (csSubComponent · Align=alTop · 不可删)
   └─ 用户控件……(设计器直接拖到这里,所见即所得)
```

**最终视觉结果:** ~5px 死带被 Surface 盖掉,边缘只剩**一圈 1px 系统窗口边框**(标准窗口都有的那圈,已接受)。Snap / 缩放 / 阴影全在。

## 4. `TTyFormSurface` 组件设计

- 新单元 `tyControls.FormSurface`(或并入 Form 单元)。类型 `TTyFormSurface = class(TTyCustomControl)`(窗口化,已 DoubleBuffered)。
- **不注册进组件面板**(不 `RegisterComponents`),用户无法从面板拖出。
- 由 `TTyForm` 在**构造函数**里创建(设计期与运行期都创建),`SetSubComponent(True)`,`Align := alClient`,`ControlStyle := ControlStyle + [csNoDesignVisible?]`(见 §6 防泄漏)。
- `csAcceptsControls` 打开,作为设计器拖放目标。
- Owner = Form,`Name` 固定(如 `Surface`),`Parent = Form`。
- 提供 Form 转发:`TTyForm` 上原来直接用的一些属性/方法转发到 Surface(见 §8 兼容)。

## 5. 设计器行为(WYSIWYG)

- **拖放天然落进容器:** Surface `alClient` 铺满并在最上层,设计器命中最顶层 → 控件落进 Surface。
- **流式化(核心工作量):** 用 `GetChildren` 让 Surface 名下的控件流式化,参考已有的 `TTyPageControl`/`TTyTabSheet`(form-owned、GetChildren 流式)。目标 `.lfm`:用户控件挂在 Surface 名下;容器本身作为内部件不需要用户手写。
- **限制"Form 上只能放容器":**
  - 99% 由"容器盖住 Form"天然阻挡。
  - 极端情况(用户在 OI 里硬把 `Parent` 设成 Form):设计期校验(`Loaded` / 设计器通知里遍历子控件),发现直接挂 Form 且非 Surface/TitleBar 的控件 → **自动 reparent 进 Surface + 弹提示**。
- **不可删:** `csSubComponent` + 未注册面板 → 设计器删除/剪切被拒。

## 6. 防"设计器内部件泄漏"

参考 memory「designer internal-subcontrol leak」:内部件容易泄漏进 IDE 设计器 objectinspector/树。措施:
- Surface / TitleBar 设 `csSubComponent`;必要时对**不希望出现在 OI 组件树**的辅助内部件设 `csNoDesignVisible`(注意:对页面型容器要在 `Visible` 之前设,memory 有坑)。
- Surface 本身**要在设计器画布可见**(WYSIWYG),但**不作为可选中/可删的独立组件**——用 `csSubComponent` 达到"可见但受保护"。
- 逐项在真 IDE 里验证(headless 测不出设计器行为)。

## 7. 主题与玻璃(green + 嵌套图)—— 关键兼容点

- **backdrop / 玻璃机制整体从 `TTyForm` 搬到 `TTyFormSurface`:**
  - `ITyGlassHost` 由 Surface 实现(`GlassBackdrop` / `GlassSharpBackdrop` / `GlassClientOrigin` / `GlassUnderTitlebar`)。
  - `FSharpBackdrop` / `FGlassBackdrop` / `FGlassKey` / `RebuildBackdrop` 移到 Surface,基于 Surface 渲染的 `form` 背景图构建。
- **玻璃子控件自动找到 Surface:** `TyResolveGlassHost`(Base.pas:481)沿父链向上找第一个 `ITyGlassHost`;控件是 Surface 的子,向上**先命中 Surface**(在 Form 之前)。无需改查找逻辑。
- **green(整窗照片 + 玻璃):支持。** Surface 渲染照片 → 建 backdrop → 玻璃子控件采样。行为与现在等价,只是宿主从 Form 变 Surface。
- **底图 A + 中间容器/按钮图 B:**
  - 各控件按自己 style 的 `Background`(`tfkImage`/`tfkNineSlice`)画自己的图 —— **已支持,保留**。
  - 玻璃当前采"父链最近的 ITyGlassHost"= Surface 的 A。**要让玻璃采中间容器的 B**,让那容器也实现 `ITyGlassHost` + 建自己的 backdrop 即可 —— **父链机制天生支持嵌套**,列为将来增强,不阻塞本设计。
- **资产 base dir:** memory「theme resolve-time asset base dir」——图片 url() 在 resolve 时求值,Surface 渲染背景时同样要在 ResolveStyle 期间恢复主题目录(否则 green 照片/玻璃断链)。移动 backdrop 逻辑时一并带过去。

## 8. 兼容 / 转发(尽量不破坏现有 API)

- 现有代码/主题里用 `TyForm`(CSS 选择器)描述背景 —— **不变**,只是由 Surface 来 resolve+渲染 `form` 背景。
- `TTyForm.Paint` 退化:非图片主题时也可保留一层兜底纯色(避免 Surface 建好前的白闪),但视觉以 Surface 为准。
- `ApplyChromeTheme` / `ApplyResizeStrategy` / `ApplyWindowEffects` 仍在 Form 层(边框是 Form 的事)。
- Surface 尺寸随 Form client 变化(`alClient` 自动);缩放时 Surface 跟随。

## 9. 边框 / 圆角 / 阴影(留在 Form 层,各 widgetset 现状)

- **不因本设计改变**——这些是顶层窗口/DWM 的事,Surface 不碰。
- **圆角:** 是平台各异的老限制,**CSS 任意半径无法在 Win 精确表达**:
  - Win32:仅 DWM 档位 `DWMWCP_ROUND(≈8px)`/`ROUNDSMALL(≈4px)`/无(Win10 方角);现状即"归桶"。
  - macOS:`layer.cornerRadius` 任意 + AA。
  - Qt/GTK:目前 no-op(GTK shape 锯齿;Qt 将来可 translucent+AA)。
  - 「跨平台任意 AA 圆角 + 还能放 GDI 子控件」是另一个专门硬课题,**本设计不解决,单独立项**。
- **半透明窗体:** 不在本设计范围,也不预作记录(将来做不做另说)。架构上无需为它妥协——Surface 按 `form` 背景色的 alpha 绘制即可,不影响未来在 Form 层单独加 DWM acrylic/mica。

## 10. 非 Win32 平台

- **边缘死带是 Win32-DWM 特有问题**;Qt/GTK/Cocoa 的缩放走各自路径(AdjustClientRect gutter / styleMask),不一定有这条带。
- 但 Surface 作为**统一的内容宿主 + backdrop 提供者**在所有 widgetset 都成立(就是个普通窗口化控件),让主题/玻璃行为跨平台一致。故 **Surface 全平台启用**,Win32 额外收获"盖死带"。

## 11. 迁移范围

- **先迁 `button` / `demo` / `ribbon` 三个做验证**,确认拖放/流式化/主题/边缘/Snap 都没问题后,再迁其余全部。
- 所有 `examples/*/`(`.lfm` + 处理器)改成新结构:控件挂 Surface;去掉显式 `TitleBar = Bar`(改内部件)。
- IDE 新建项模板(memory「ide new-item templates」:TyControls Form / Application / Dialog)同步。
- demo 是用户设计面(memory「demo edits: .lfm not code」),迁移时保留其设计,不回退。
- 文档 README(`.md` + `.en.md`)、i18n(若涉及可翻译串)按 memory「pre-merge checklist」检查。

## 12. 风险 / 开放问题

- **GetChildren 流式化 + 设计器集成**是最费神、最易踩坑的一块(真 IDE 才能验)。
- **现有 .lfm 迁移**:控件从 Form 子变 Surface 子,anchor/align/tab 顺序/bounds 要逐一核对。
- **内部件泄漏**、**Loaded 时序**、**csNoDesignVisible 与 Visible 的先后**(memory 有坑)。
- **backdrop 搬家**后 green / 玻璃 / 资产 base dir 要回归测试(有 golden 像素守护)。
- 真机核对:1px 系统边框在 Win10/11 的观感、Snap、圆角、阴影(headless 测不了)。

## 13. 测试

- headless:GetChildren 流式化往返(存/读 .lfm 一致)、backdrop 键值、玻璃宿主解析(Surface 命中)、golden 像素(green)。
- 真 IDE:拖放落容器、内部件不可删/不泄漏、直接挂 Form 的警告+自动 reparent、新建模板。
- 真机:各 widgetset 的边缘、Snap、圆角、阴影;green 主题照片+玻璃。

---

### 已确认决策(2026-07-15)
1. 命名:`TTyFormSurface`,内部实例名 `Surface`。
2. **TitleBar 放 Surface 内**(单一宿主,统一 backdrop)。
3. 迁移**分批**:先 `button` / `demo` / `ribbon` 验证,过了再全改。
4. 半透明:不做、不记录(架构无需为它妥协)。

### 实现分期(roadmap)
- **① Surface 骨架 + 盖死带:** 建 `TTyFormSurface`,Form 构造时创建、`alClient`、`csSubComponent`;背景绘制从 `TTyForm.Paint` 搬进来;子 HWND 覆盖 Form 死带。真机看边缘。
- **② 内容承载 + TitleBar 内移:** TitleBar 变 Surface 内部件;运行期把内容摆进 Surface。
- **③ GetChildren 流式化 + 设计器集成:** WYSIWYG 拖放、不可删、防泄漏、"只准放容器"警告(真 IDE 验)。
- **④ 主题 / 玻璃搬家:** `ITyGlassHost` + `RebuildBackdrop` + backdrop 快照移到 Surface;green + 嵌套图回归(golden 守护)。
- **⑤ 迁移:** button/demo/ribbon → 验证 → 其余全部 + IDE 新建模板 + README/i18n。
