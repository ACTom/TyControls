# TTyRibbon / TTyRibbonPage / TTyRibbonGroup

Office 式命令带(Ribbon)的骨架(Phase-3 R1):**标签条 → 分组带 → 命令控件**。命令控件直接用
Batch-C 的按钮家族([TTyGlyphButton](glyphbuttons.md)/[TTyGlyphContainerButton](glyphbuttons.md)/
[TTyDropDownButton](dropbuttons.md)/[TTyColorButton](colorbutton.md)/[TTyButtonGroup](buttongroup.md) 等)。

> R1 是骨架:标签切换、分组排布、组内放按钮。快速访问栏 / 应用菜单 / 画廊 / 上下文标签 / 溢出折叠
> 在后续 R2-R4 批次加入。渲染 / IDE 设计器 / 交互需真机验证。

## TTyRibbon

顶部停靠的命令带宿主,继承 `TTyCustomTabStrip`(复用其标签条引擎:布局/绘制/点击/悬停/键盘)。
标签页是 `TTyRibbonPage` 子控件(窗体拥有、`GetChildren` 流式,与 `TTyPageControl` 同一模式)。
标签复用 `TyTab` 主题,带面用新 typeKey `TyRibbon`。

| 成员 | 说明 |
|------|------|
| `ActivePageIndex` / `ActivePage` | 当前激活页;运行期点标签即切换。 |
| `AddPage(caption): TTyRibbonPage` | 新增一页。 |
| `RemovePage(index)` / `PageCount` / `Pages[i]` | 页管理。 |

## TTyRibbonPage

一个标签页,托管 `TTyRibbonGroup`(分组通过 `Align=alLeft` 自左向右排布)。`Caption` 是**标签文字**
(由宿主标签条绘制,不画在页面上)。设计期标志与 `TTyTabSheet` 一致(固定、可放控件、非激活隐藏)。

## TTyRibbonGroup

带标题的分组盒(typeKey `TyRibbonGroup`):底部标题带 + 右侧分隔线,命令控件放在标题之上的区域
(`AdjustClientRect` 预留底部标题带)。

| 成员 | 说明 |
|------|------|
| `Caption` | 底部分组标题。 |
| `ShowDialogLauncher` | 在标题带右下角显示对话框启动器箭头。 |
| `OnDialogLauncher` | 点击启动器箭头触发。 |

## 纯几何

`TyRibbonGroupContentRect(w, h, captionBandPx)` — 分组托管控件的内容矩形(客户区减去底部标题带),
已 headless 单测。

## 用法

```pascal
Ribbon := TTyRibbon.Create(Self);
Ribbon.Parent := Self;   // Align=alTop
Home := Ribbon.AddPage('开始');
Grp := TTyRibbonGroup.Create(Self);
Grp.Parent := Home;      // Align=alLeft
Grp.Caption := '剪贴板';
// 往 Grp 里放 TTyGlyphButton / TTyGlyphContainerButton …(Align/SetBounds 定位)
```
