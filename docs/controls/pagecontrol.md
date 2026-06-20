# TTyPageControl

## 1. 概述

`TTyPageControl` 是 TyControls 的主题化多页容器，对标 Lazarus 的 `TPageControl`：顶部一排标签页头，每个页签对应一个 `TTyTabSheet` 页面板；同一时刻只显示当前活动页。它**取代了旧的 `TTyTabControl`**——旧控件是“运行期分页面板”，页由控件自身拥有、随 `Tabs` 集合流式化，导致在 IDE 设计器里无法把控件拖进页里。新模型让页成为**窗体拥有、命名、走标准 `GetChildren` 流式化**的真正设计器容器：在设计器里可以直接往每页拖放控件并随 `.lfm` 持久化。

三个单元各司其职：

| 单元 | 类 | 职责 |
|---|---|---|
| `tyControls.TabStrip` | `TTyCustomTabStrip` | 共享的标签头引擎（布局/悬停/横向滚动/关闭×/拖拽重排/活动页交叉淡入/键盘）。与“页”无关，标签数据靠抽象方法供给 |
| `tyControls.TabSheet` | `TTyTabSheet` | 一个页：主题化背景面板 + published `Caption`（页签文字，不画在页面体上）+ 设计期 `ControlStyle` 标志 |
| `tyControls.PageControl` | `TTyPageControl` | 容器：`TTyTabSheet` 页 + 设计器集成（窗体拥有、`GetChildren` 流式化、`csNoDesignVisible` 切换、组件编辑器） |

## 2. typeKey

| 部件 | typeKey | 说明 |
|---|---|---|
| 页控件外框 | `TyPageControl` | `.tycss` 中控件本体的选择器前缀 |
| 页面板 | `TyTabSheet` | 每页背景 |
| 页签头 | `TyTab` | 单个标签头（`:active` 为当前页） |
| 关闭 × 底片 | `TyTabClose` | `TabsClosable = True` 时悬停底片 |

（标签头沿用 `TyTab` / `TyTabClose` 选择器；控件本体用 `TyPageControl`，主题未显式定义时由 seed 派生默认值。）

## 3. 属性与方法

### TTyPageControl

| 成员 | 类型 | 说明 |
|---|---|---|
| `ActivePageIndex` | `Integer`（published, 默认 -1） | 当前活动页零基索引；-1 表示无；赋值裁剪越界；真变化才触发 `OnChange`；随 `.lfm` 往返（载入期写入的值在 `Loaded` 应用） |
| `ActivePage` | `TTyTabSheet`（public） | 当前活动页（读/写；写入即切到该页） |
| `Pages[i]` | `TTyTabSheet`（public, 只读 indexed） | 第 i 页；越界返回 `nil` |
| `PageCount` | `Integer` | 页数 |
| `AddPage(caption)` / `AddTab(caption)` | `: TTyTabSheet` | 追加一页（`Owner` = 控件的 Owner，即窗体；`Parent` = 控件），返回该页；首次追加自动选中 |
| `RemovePage(i)` | 方法 | 移除并释放第 i 页，自动修正活动页 |
| `TabHeight` | `Integer`（默认 28） | 页签头条带逻辑高度（按 PPI 缩放） |
| `TabsClosable` | `Boolean`（默认 False） | 页签头是否显示关闭 × |
| `AnimationsEnabled` | `Boolean`（默认 True） | 切页时活动页签头是否交叉淡入（无窗口句柄时直接定格，保证 headless 测试稳定） |
| `OnChange` / `OnChanging` / `OnTabClose` / `OnReorder` | 事件 | 切换后 / 切换前可否决 / 点关闭×可否决 / 拖拽重排提交后 |

页签文字来自各页的 `TTyTabSheet.Caption`（没有 `Tabs` 集合）。

### TTyTabSheet

| 成员 | 说明 |
|---|---|
| `Caption`（published） | 该页的**标签文字**；改动时通知宿主重排标签头；**不**画在页面体上 |
| `ControlStyle` | 构造时加 `csAcceptsControls, csDesignFixedBounds, csNoDesignVisible, csNoFocus`；`Align = alClient` |

## 4. 设计器里使用

1. 从 “TyControls” 调色板拖一个 `TTyPageControl` 到窗体。
2. 右键控件 → 组件编辑器动词：
   - **Add Page** —— 新建一页（窗体拥有、自动命名、设为活动页）。
   - **Delete Page** —— 删除当前活动页。
   - **Show Next Page / Show Previous Page** —— 切换活动页。
   - 也可在对象检查器改 `ActivePageIndex` 切页。
3. 把控件拖到**当前可见页**的主体上——落在该 `TTyTabSheet` 上，随 `.lfm` 持久化（嵌套在该页的 `object` 块里）。切到别的页继续拖，逐页布局。

> **没有“点页签头切页”**：本控件是自绘的，不像原生 `TPageControl` 能靠 OS 原生控件在设计期点 tab 切页；自绘控件无法既让设计器转发点击切页、又保留正常的选中/拖放（详见设计的根因分析）。因此设计期切页一律用组件编辑器动词 / 对象检查器。

改动控件库代码后需重新编译/安装 `tycontrols_dt.lpk` 并重启 Lazarus，调色板与设计器才用上新行为。

## 5. 给每页添加控件（代码）

```pascal
var Pg: TTyTabSheet;
Pg := PageCtrl.AddPage('设置');     // 返回新页
MyEdit.Parent := Pg;                 // 往该页放控件
MyEdit2.Parent := PageCtrl.Pages[0]; // 或按索引
PageCtrl.ActivePage := Pg;           // 切到该页
```

## 6. 标签头能力（继承自 TTyCustomTabStrip）

- **横向滚动**：标签头溢出时显示左右箭头；`ScrollTabIntoView`/`SetHeaderScroll`/`TyMaxHeaderScroll` 等几何 API（设备像素）供测试与自定义命中。
- **拖拽重排**：按住页签头拖动可重排页顺序，提交后触发 `OnReorder(从, 到)`。
- **可关闭页签**：`TabsClosable = True` 时每页签头右侧有关闭 ×，点击触发 `OnTabClose`（可否决）。
- **活动页交叉淡入**：切页时活动页签头背景从非活动样式淡入活动样式（仅页签头颜色淡入，页内容瞬时切换）。
- **键盘**：`←/→` 上一/下一页，`Home/End` 首/末页，`Ctrl+Tab` / `Ctrl+PageUp/PageDown` 切页。

## 7. 流式化（.lfm）

与 `TPageControl` 同构——页是窗体拥有的子控件，走默认 `GetChildren`（`Owner = Root`），页和页内控件都按标准方式嵌套保存：

```
object TabCtrl1: TTyPageControl
  ActivePageIndex = 0
  object TyTabSheet1: TTyTabSheet
    Caption = 'Tab 1'
    object Btn: TTyButton ... end   // 拖到该页的控件，嵌套于此
  end
  object TyTabSheet2: TTyTabSheet
    Caption = 'Tab 2'
  end
end
```

载入时页经 `TTyTabSheet.SetParent` 自动注册到宿主，`ActivePageIndex` 在 `Loaded` 应用。运行期表单加载需要页类已注册——`TTyTabSheet`/`TTyPageControl` 在各自单元 `initialization` 调用 `RegisterClass`。

## 8. 仅要“标签条”而非容器？

若只需要一排标签（不托管页、自己在 `OnChange` 里切内容），请用 **`TTyTabSet`**（SP2，纯标签条，与 `TTyPageControl` 共享 `TTyCustomTabStrip` 基类）。
