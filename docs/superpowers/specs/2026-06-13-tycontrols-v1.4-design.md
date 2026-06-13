# TyControls v1.4 设计文档 — TTyTabControl 成熟化

- **日期:** 2026-06-13
- **状态:** 自主推进(用户授权"按你想法来,不要问我任何问题")。
- **前置:** main 含 v1+v1.1+v1.2+v1.3(16 控件、内置默认皮肤、295 测试)。本阶段取 backlog 中明确的 TabControl 项:`RemoveTab`、Notification 悬空保护、可关闭页签;顺带消除 `TyTabHeaderRect` 每帧 O(n²)。

## 0. 动机
`TTyTabControl`(v1.2)只有 `AddTab`,没有删除 API,也没有 `Notification` 覆盖——页面板被外部 `Free` 时 `FPages`/`FCaptions` 不更新 ⇒ 悬空指针/渲染越界(已知隐患)。同时页签头几何 `TyTabHeaderRect(i)` 自身 O(i),在 RenderTo/Mouse 里每个页签调一次 ⇒ 每帧/每事件 O(n²)。买家对 Tab 控件普遍期望"可关闭页签"。

## 1. 范围

### A. RemoveTab + Notification 悬空保护
- `procedure RemoveTab(AIndex: Integer);` —— 越界静默 no-op;否则从并行数组(`FCaptions`/`FPages`)移除该页、**释放该页面板**、修正 `FTabIndex`、`ShowOnlyPage`、`Invalidate`;仅当**当前显示的页(对象身份)发生变化**时触发 `OnChange`(避免"删非活动页只是索引位移"误触发)。
- `Notification(opRemove)`:覆盖,先 `inherited`(基类负责 `FController` 置空),再——若被移除组件是 `FPages` 中的页面板——把它从数组剔除并修正索引(**不再 Free**,它正在被销毁)。用 `FDestroying` 标志在自身析构期间短路(`Destroy` 先 `FDestroying:=True` 再 `FCaptions.Free`/`inherited`,避免 inherited 释放 owned 页时回调 Notification 触碰已释放的 `FCaptions`)。
- `RemoveTab` 与 `Notification` 共用私有 `RemovePageInternal(AIndex; AFree: Boolean)`;`RemoveTab` 传 `AFree=True`,`Notification` 传 `AFree=False`。`RemoveTab` 先把页移出数组再 `Free`,故 `Free` 触发的 Notification 在数组里找不到它 ⇒ 不重入。
- **索引修正规则**(移除 idx 后):`Length=0`→ -1;`idx<FTabIndex`→ `Dec`(同一页仍活动);`idx=FTabIndex`→ 保持 FTabIndex 但夹到 `High`(邻页变活动);`idx>FTabIndex`→ 不变。

### B. 可关闭页签
- `property TabsClosable: Boolean`(published,`default False`)。
- `TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer; var AllowClose: Boolean) of object;`
  `property OnTabClose: TTyTabCloseEvent`(published)。
- `function TyTabCloseRect(AIndex: Integer): TRect;`(公开,device px,(0,0)-local;非 closable 或越界返回 `Rect(0,0,0,0)`)。
- 几何:closable 时每个页签头右侧预留 `closeSlot = closeSize + gap`(`closeSize=Scale(14)`、`gap=Scale(6)`),页签头宽 `= textW + 2*pad + closeSlot`,最小宽 `MinW(=Scale(48)) + closeSlot`;× 命中区为头右侧垂直居中的 `closeSize` 方块,距右边缘 `Scale(6)`。标题文本绘制在"头去掉 closeSlot"的左侧区域,避免与 × 重叠。
- 渲染:closable 时在 `TyTabCloseRect(i)` 用 `P.DrawGlyph(rect, tgClose, TabStyle.TextColor, Scale(1))` 画 ×(`tgClose` 已存在)。
- 交互:`MouseDown` 左键命中某页签头——若 closable 且点在 `TyTabCloseRect(i)` 内 ⇒ `DoCloseTab(i)`(置 `AllowClose:=True`,调 `OnTabClose`,若仍 True 则 `RemoveTab(i)`),**不选中**;否则选中该页。
- 非 closable(默认)时几何与现状**逐像素一致**(现有 `TestHeaderRectsLayout`/`TestMouseDownSelectsTab` 不变即证)。

### C. 几何单遍化(消除 O(n²))
- 私有 `RebuildLayout(APPI)` 一次 O(n) 填 `FHeaderRects`/`FCloseRects: array of TRect`。
- `RenderTo` 顶部调一次 `RebuildLayout(APPI)`,循环读数组(不再每页调 `TyTabHeaderRect`)。`MouseDown`/`MouseMove` 同样先 `RebuildLayout(Font.PixelsPerInch)` 再读数组。
- 公开 `TyTabHeaderRect(i)`/`TyTabCloseRect(i)` 内部 `RebuildLayout(Font.PixelsPerInch)` 后返回数组元素(供测试/外部用;不在每帧热循环里,故不引入 O(n²))。无脏标志缓存——每帧重建一次 O(n),永不陈旧(主题热切换后宽度自动正确)。

## 2. 不做(记 KNOWN_GAPS)
页签**横向滚动**(溢出仍截断);页签**拖拽重排**;关闭 × 的独立 `:hover` 高亮(v1.4 用 tab 文本色画 ×,保持简单)。

## 3. 集成
- 主题:无需改(× 用 `TabStyle.TextColor`)。无新单元 ⇒ lpk 不变。
- `examples/tabcontrol`:演示 `TabsClosable := True` + `OnTabClose`(可选弹确认/直接关闭);demo gallery 的 TabControl 也开 closable 展示。
- 文档:`docs/controls/tabcontrol.md`(RemoveTab/TabsClosable/OnTabClose/TyTabCloseRect);`docs/KNOWN_GAPS.md`(删"页签关闭"项,保留滚动/拖拽);README 控件能力一句话。

## 4. 验收
295 + 新增测试全绿(RemoveTab 索引/OnChange 语义、Notification 外部释放不崩、closable 几何/命中/关闭事件/取消、非 closable 几何不变);构建矩阵全绿;全套件 heaptrc **0 泄漏**(RemoveTab 释放页、反复增删不漏);终审通过;文档同步。
