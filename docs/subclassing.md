# 从 TyControls 控件派生

> English: [subclassing.en.md](subclassing.en.md)

从 4.0 起，每个控件都分成两层，跟 LCL 的 `TCustomEdit` / `TEdit` 一个路数：

- `TTyCustomXxx`：全部实现都在这里。属性按 LCL 的规矩放在 public 或 protected，一个都不发布。
- `TTyXxx`：组件面板上的那个类，只有一段 `published`，把该露的属性列出来。

想包一个自己的控件、只给用户看一部分属性，就从 `TTyCustomXxx` 派生；想要全部属性再加几个，就从 `TTyXxx` 派生。后一种跟 3.0 一样，什么都不用改。

本页先讲怎么派生，后面是限制，最后一节是从 3.0 升级要注意的地方。

---

## 1. 一个最小的例子

一个只露文字、只读开关和 `OnChange` 的标签输入框：

```pascal
unit MyTagEdit;
{$mode objfpc}{$H+}

interface

uses
  Classes, tyControls.Edit;

type
  TMyTagEdit = class(TTyCustomEdit)
  published
    property Text;
    property ReadOnly;
    property OnChange;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('My Controls', [TMyTagEdit]);
end;

end.
```

放进自己的设计期包，装上就能在面板上看到。对象查看器里只有这三个，加上 LCL 根类本来就发布、藏不掉的那几个（`Name`、`Left`、`Top`、`Width`、`Height`、`Hint`、`Cursor`、`Anchor*`、`Help*`，共 15 个）。

`property Text;` 这样不带类型的一行，会把 `TTyCustomEdit` 里那条声明的 default、stored、读写方法原样带过来，`.lfm` 里写不写、写什么，跟 `TTyEdit` 完全一样。**不要**写成 `property Text: string;`，那是另起一个新属性，default 和 stored 全丢。

### 发布顺序就是 `.lfm` 的写出顺序

IDE 存窗体时按 published 段的顺序写属性，读回来时按文件里的顺序一个个调 setter。所以有些控件要求「范围在前、值在后」，先写值就会被默认的范围钳住：

| Custom 类 | 要先发布 | 再发布 |
|---|---|---|
| `TTyCustomSpinEdit` | `MinValue`、`MaxValue` | `Value` |
| `TTyCustomProgressBar` | `Max` | `Position` |
| `TTyCustomGauge` | `Max` | `Value` |
| `TTyCustomTrackBar` | `Min`、`Max` | `Position` |
| `TTyCustomScrollBar` | `Min`、`Max` | `Position` |

拿不准就照对应 `TTyXxx` 的发布顺序抄。

下面这些不讲究顺序，读窗体期间值会先存着，等 `Loaded` 时再落：

- 数值编辑框一族（`TTyCustomNumericEdit` 及货币、滑块、计算器、小数微调框）的 `Value`，按最终的 `Decimals` / `MinValue` / `MaxValue` 设进去；
- 组合框、列表框一族、`TTyCustomButtonGroup`、`TTyCustomRadioGroup` 的 `ItemIndex`（列表框还有 `TopIndex`），`TTyCustomStringGrid` 的 `Col` / `Row`，读到时条目还没有就先存着；
- `TTyCustomColorBox` / `TTyCustomColorListBox` 的 `Selected`；
- `TTyCustomPagination` 的 `PageIndex`、`TTyCustomToolWindowBar` 的 `ActiveIndex`、`TTyCustomRibbon` 的 `ActivePageIndex` 和 `Minimized`、`TTyCustomRibbonGallery` / `TTyCustomRibbonBackstage` 的 `ItemIndex`；
- `TTyCustomSteps` 的 `StepIndex` 本来就不按条目钳。

---

## 2. 主题

控件靠 `GetStyleTypeKey` 报出的主题键找样式（`TTyEdit` 报 `'TyEdit'`），这个覆写在 Custom 类里。所以 `TMyTagEdit` 什么都不写，就吃 `TyEdit` 的全部 tycss 规则，换主题跟着变。`.tycss` 里不会出现 `TyCustomEdit` 这种键，永远写 `TyEdit`。

如果你覆写 `GetStyleTypeKey` 换成自己的键（比如 `'MyTagEdit'`），主题里就得有 `MyTagEdit { ... }` 的规则，否则这个控件拿不到任何样式——现在还没有「找不到就退回 `TyEdit`」的机制，这件事记在 [#14](https://github.com/ACTom/TyControls/issues/14)。在那之前，要么不覆写，要么自己的主题里把规则写全。

---

## 3. Custom 类里属性的可见性

跟 LCL 对应的 Custom 类一致：同名属性照抄 LCL 的可见性，没有 LCL 对应物的控件放 public。大致是：

- 编辑框、组合框、列表框、按钮、滑块、滚动条、图像：多数 public；
- 标签、树、列表视图、上下按钮、网格基类（`TTyCustomGrid`）：多数 protected；
- `TTyCustomCheckBox` / `TTyCustomRadioButton` / `TTyCustomToggleSwitch` 的 `Checked` 是 protected（LCL 的 `TButtonControl.Checked` 就是）。

protected 的属性照样能在自己的 published 段里发布。只是想让代码从外面访问、又不想进对象查看器，就提到 public：

```pascal
  TMyCheck = class(TTyCustomCheckBox)
  public
    property Checked;
  published
    property Caption;
  end;
```

---

## 4. 设计期

**属性编辑器会跟过来。** 库里的属性编辑器注册在 Custom 类上，或者按属性类型注册（`GlyphName`、`ImageName`、`Directory`、`StyleClass`、`StyleOverride`、`ThemeName` 这些），你发布了对应属性，对象查看器里就是同一个编辑器。

**组件编辑器不会跟过来。** 双击、右键菜单里的那些动作（组件编辑器）留在最终类上，因为它们会改属性，而你的子类未必发布了那些属性。下面这些在你的子类上没有：

| 组件编辑器 | 注册在 | 动作 |
|---|---|---|
| 页控件编辑器 | `TTyPageControl` | 添加页、删除页、下一页、上一页、显示页 |
| 工具窗口栏编辑器 | `TTyToolWindowBar` | 新建工具窗口、显示窗口 |
| 工具窗口编辑器 | `TTyToolWindow` | 添加操作区、移到另一侧、移回栏里 |
| 树节点编辑器 | `TTyTreeView` | 双击编辑节点 |
| 级联选择 / 树形选择的节点编辑器 | `TTyCascader`、`TTyTreeSelect` | 双击编辑选项树 |
| 列表分组编辑器 | `TTyListGroupPanel` | 编辑分组 |
| 终端编辑器 | `TTyTerminalView` | 导入 / 导出配色方案 |
| 图像集合编辑器 | `TTyImageCollection` | 管理图片 |
| 对话框预览 | 各对话框 | 预览 |
| 图标浏览器 | `TTyIconFont`、`TTyLucideIconFont`、`TTyVirtualImageList`、`TTyLucideImageList` | 浏览图标 |

`TTyFormSurface` 的 `Purpose` 说明和 `Version` 编辑器也留在最终类上；你的表面子类发布 `Purpose` 时，它只是一个普通的只读字符串。

这些编辑器的实现里写的是 `Component as TTyPageControl` 这样的最终类，所以**不能**直接把它们注册给你的类——一点菜单就抛 `EInvalidCast`。唯一的例外是图标浏览器（`TTyIconBrowserComponentEditor`），它认任何 `TTyCustomIconFont` / `TTyCustomVirtualImageList`，可以直接 `RegisterComponentEditor(TMyIconFont, TTyIconBrowserComponentEditor)`。

其余的要自己写一个，不长。以页控件的「添加页」为例：

```pascal
uses
  Classes, ComponentEditors, PropEdits, tyControls.PageControl, tyControls.TabSheet;

type
  TMyPageControlEditor = class(TDefaultComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

function TMyPageControlEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TMyPageControlEditor.GetVerb(Index: Integer): string;
begin
  Result := 'Add page';
end;

procedure TMyPageControlEditor.ExecuteVerb(Index: Integer);
var
  PC: TTyCustomPageControl;
  Hook: TPropertyEditorHook;
  NewPage: TTyTabSheet;
  NewName: string;
begin
  PC := Component as TTyCustomPageControl;
  Hook := nil;
  if not GetHook(Hook) then Exit;
  NewPage := TTyTabSheet.Create(PC.Owner);
  NewPage.Parent := PC;    // 先挂到页控件上，页才算进去
  NewName := GetDesigner.CreateUniqueComponentName(NewPage.ClassName);
  NewPage.Caption := NewName;
  NewPage.Name := NewName;
  PC.ActivePage := NewPage;
  Hook.PersistentAdded(NewPage, True);
  Modified;
end;

// 在设计期包的 Register 里：
//   RegisterComponentEditor(TMyPageControl, TMyPageControlEditor);
```

删页、翻页要用的 `Pages[]`、`PageCount`、`ActivePage`、`ActivePageIndex` 在 `TTyCustomPageControl` 上都是 public。别的家族同理：组件编辑器里把对象当成 Custom 类来用。

**`DefineProperties` 写的数据照样存。** 有些控件用 `DefineProperties` 往 `.lfm` 里存不在 published 里的东西（比如图像列表丢弃的像素块、窗体设计位置），这段代码在 Custom 类里，你的子类哪怕没发布相关属性，这些数据也会写进 `.lfm`。

---

## 5. 限制

- **LCL 根类发布的 15 个属性藏不掉。** `TComponent` 的 `Name`、`Tag`，`TControl` 的 `Left`、`Top`、`Width`、`Height`、`Hint`、`Cursor`、四个 `AnchorSide*`、三个 `Help*`。Pascal 没法取消发布，LCL 自己的 Custom 类也一样。
- **宿主交出的子项有时仍是最终类型。** 多数宿主属性已经写成 Custom 类（见第 7 节），但只交出自己建的那个类的保持不变：`TTyRadioGroup` 的按钮是 `TTyRadioButton`，`TTyCheckGroup` 的是 `TTyCheckBox`，`TTyPageControl.AddPage` 返回 `TTyTabSheet`，`TTyFilterComboBox.ShellListView` 是 `TTyShellListView`（照 LCL 的 `TFilterComboBox`）。
- **自己的样式控制器挂不到控件上。** 所有 `Controller` 属性在 4.0 首版仍是 `TTyStyleController` 类型，从 `TTyCustomStyleController` 派生的控制器可以单独用（加载主题、解析样式、通知监听者），但赋不给任何控件的 `Controller`。要么从 `TTyStyleController` 派生，要么等后续版本把这个类型放宽。
- **`GlyphName` 编辑器按名字找宿主的 `IconFont`。** 你的子类要在对象查看器里用图标下拉，就得发布 `IconFont`。
- **`TTyGridCell` 由 `TTyGridPanel` 自己建。** 你的格子子类只能在代码里手动放进去。
- **你的 `TTyCustomScrollBar` 子类永远是独立滚动条。** 宿主只内嵌自己建的 `TTyScrollBar`，不会把你的条当成内嵌条。
- **可以放心不发布的：** 编辑框、多行编辑框、组合框的 `Text`。这三个家族的 `Caption` 就是 `Text`，`TTyUpDown` 之类按 `Caption` 驱动的东西照样能用。

---

## 6. 直接从基类写一个全新的控件

`TTyCustomControl`（窗口化）和 `TTyGraphicControl`（图形）在 4.0 里什么都不发布，跟 LCL 的 `TCustomControl` / `TGraphicControl` 一样。从它们直接派生的控件，下面这段是 Ty 控件惯用的通用属性，整段抄进自己的 published 段即可（顺序就是 Ty 控件的顺序）：

```pascal
  published
    property Version;          // 库版本，对象查看器里点开是 About 对话框
    property Enabled;
    property Visible;          // 对象查看器和 .lfm 里能直接藏控件
    property Font;             // 主要用来传 PPI；字体族与字号由主题决定
    property ShowHint;
    property TabOrder;         // 窗口化才有
    property TabStop;          // 窗口化才有
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;         // 实现了 CalculatePreferredSize 才有意义
    property BorderWidth;      // 窗口化才有：子控件区域整体内缩，不是边框粗细
    property ChildSizing;      // 窗口化才有：LCL 的子控件自动排布
    property DragMode;         // 拖放全由 LCL 分发，自绘控件白拿
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz; // 横向滚轮、倾斜轮、触控板横扫只从这三个到达
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;       // 按指针位置换提示文字的唯一入口
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;          // 控件画完之后触发，叠加用，不是自绘
    property OnKeyDown;        // 以下七个窗口化才有
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;       // 主题变体，比如 'primary'
    property StyleOverride;    // 只改这一个控件的 tycss 片段
    property Controller;       // 用哪个样式控制器，空着就是全局默认
```

图形控件把标了「窗口化才有」的几行删掉。多数 Ty 控件另外还发布 `Align`、`Anchors`，按需加。

这些属性各自的行为见 [events.md](events.md)。

---

## 7. 从 3.0 升级

**`.lfm` 不用改，主题不用改。** 每个控件的属性名、默认值、写出顺序、默认尺寸、主题键都跟 3.0 一样。要改的只是代码里涉及类层级和类型的地方，编译器会帮你找出大部分。

### 7.1 父类变了的控件

派生控件现在挂在 Custom 链上，不再是原来父控件的后代。`TTyGlyphButton is TTyButton` 在 3.0 是 True，在 4.0 是 False。

| 控件 | 3.0 的父类 | 4.0 的父类（`TTyCustomXxx` 的父类） | 不再是谁的后代 |
|---|---|---|---|
| TTyDropDownButton | TTyButton | TTyCustomButton | TTyButton |
| TTyMenuButton | TTyButton | TTyCustomButton | TTyButton |
| TTyColorButton | TTyButton | TTyCustomButton | TTyButton |
| TTyGlyphButton | TTyGlyphButtonBase | TTyGlyphButtonBase（← TTyCustomButton） | TTyButton |
| TTyGlyphContainerButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTySpeedButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTyToolButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTyRibbonAppMenu | TTyMenuButton | TTyCustomMenuButton | TTyMenuButton、TTyButton |
| TTyNumericEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyMaskEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyURLEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyComboEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyCurrencyEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyTrackEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyCalcEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyFloatSpinEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit、TTyEdit |
| TTyCalcCurrencyEdit | TTyCurrencyEdit | TTyCustomCurrencyEdit | TTyCurrencyEdit、TTyNumericEdit、TTyEdit |
| TTyMRUComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyComboBoxEx | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyOfficeComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyAdvancedComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyCheckComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyColorBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyFontComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyFontSizeComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyFilterComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyShellComboBox | TTyComboBox | TTyCustomComboBox | TTyComboBox |
| TTyColorComboBox | TTyColorBox | TTyCustomColorBox | TTyColorBox、TTyComboBox |
| TTyCheckListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyOfficeListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyAdvancedListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyValueListEditor | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyColorListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyFontListBox | TTyListBox | TTyCustomListBox | TTyListBox |
| TTyRadioGroup | TTyGroupBox | TTyCustomGroupBox | TTyGroupBox |
| TTyCheckGroup | TTyGroupBox | TTyCustomGroupBox | TTyGroupBox |
| TTyToolGroupPanel | TTyGroupBox | TTyCustomGroupBox | TTyGroupBox |
| TTyPaintPanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyExPanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyGridPanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyRelativePanel | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyScrollBox | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyControlBar | TTyPanel | TTyCustomPanel | TTyPanel |
| TTyScrollPanel | TTyScrollBox | TTyCustomScrollBox | TTyScrollBox、TTyPanel |
| TTyCoolBar | TTyControlBar | TTyCustomControlBar | TTyControlBar、TTyPanel |
| TTyToolBarEx | TTyToolBar | TTyCustomToolBar | TTyToolBar |
| TTyShellTreeView | TTyShellTreeLink | TTyShellTreeLink（← TTyCustomTreeView） | TTyTreeView |
| TTyShellListView | TTyListView | TTyCustomListView | TTyListView |
| TTyStringGrid | TTyDrawGrid | TTyCustomDrawGrid | TTyDrawGrid |
| TTyLucideIconFont | TTyIconPackFont | TTyIconPackFont（← TTyCustomIconFont） | TTyIconFont |
| TTyLucideImageList | TTyVirtualImageList | TTyCustomVirtualImageList | TTyVirtualImageList |

`TTyPageControl`、`TTyTabSet`、`TTyRibbon`（在 `TTyCustomTabStrip` 下）和 `TTyDrawGrid`（在 `TTyCustomGrid` 下）父类没变，只是中间类不再发布东西。

### 7.2 `is`、`as` 和强转

规则只有一条：**想表示「任意 Xxx」，就判 `TTyCustomXxx`**；只想要「恰好这个类」的，保持原样。

```pascal
// 3.0：工具栏上的 TTyToolButton、TTyGlyphButton 在 4.0 下会抛 EInvalidCast
StatusBar1.SimpleText := (Sender as TTyButton).Caption;
// 4.0
StatusBar1.SimpleText := (Sender as TTyCustomButton).Caption;

// 3.0：对 TTyNumericEdit、TTyMaskEdit 等静默变成 False
if AControl is TTyEdit then ...
// 4.0
if AControl is TTyCustomEdit then ...
```

`is` 静默变 False、`as` 运行时抛 `EInvalidCast`、把派生控件赋给父控件类型的变量编不过——三种都可能遇到。硬转 `TTyButton(AGlyphButton)` 仍然「能跑」（最终类不加字段），但对象不是那个类，按上面的规则改掉。

判成 Custom 类以后，如果要访问的属性在 Custom 类里是 protected（见第 3 节），而对象确实是库里的控件，就强转成那个最终类，这对库里的控件是真话；对第三方子类会抛 `EInvalidCast` 而不是悄悄读错。

### 7.3 事件处理过程的签名

有 Custom 类的家族里，事件的 Sender 写的是 Custom 类（跟 LCL 的 `TTVCustomDrawEvent = procedure(Sender: TCustomTreeView; ...)` 一样）。涉及：

- `TTyTreeView` 的 21 个事件类型（`OnGetText`、`OnPaintText`、`OnCompareNodes`、`OnInitChildren`、`OnChecking` 等）：`Sender: TTyCustomTreeView`；
- `TTyHeaderControl` 的 `TTyHeaderSectionEvent`、`TTyHeaderResizeEvent`、`TTyHeaderTrackEvent`：`TTyCustomHeaderControl`；
- `TTyStatusBar.OnDrawPanel`：`AStatusBar: TTyCustomStatusBar`；
- `TTyToolBar.OnPaintButton`：`Sender: TTyCustomToolButton`；
- `TTyRibbonGroup.OnDialogLauncher`：`Sender: TTyCustomRibbonGroup`；
- `TTyToolWindowManager.OnCanMoveWindow` / `OnWindowMoved` 的窗口、栏参数（不是 Sender）：`TTyCustomToolWindow`、`TTyCustomToolWindowBar`。

```pascal
// 3.0
procedure TForm1.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
// 4.0
procedure TForm1.TreeGetText(Sender: TTyCustomTreeView; Node: PTyTreeNode; var Text: string);
```

`.lfm` 里按方法名关联，不查签名，所以窗体文件不用动；改完声明重新编译即可。

### 7.4 属性、返回值的类型

引用组件的属性照 LCL（`Images: TCustomImageList`）写 Custom 类，这样库里的派生组件和你自己的子类都挂得上：

| 属性 | 3.0 | 4.0 |
|---|---|---|
| 所有 `IconFont` | `TTyIconFont` | `TTyCustomIconFont` |
| `Controller` | `TTyStyleController` | 不变（见第 5 节） |
| `Images` / `HotImages` / `DisabledImages`（图像集合）、`TTyVirtualImageList.Collection` | `TTyImageCollection` | `TTyCustomImageCollection` |
| `TTyForm.TitleBar` / `MenuBar`（`TTyDialog` 同） | `TTyTitleBar` / `TTyMenuBar` | `TTyCustomTitleBar` / `TTyCustomMenuBar` |
| `TTyRibbon.Backstage`、`TTyRibbonAppMenu.Backstage` | `TTyRibbonBackstage` | `TTyCustomRibbonBackstage` |
| `TTyShellTreeView.ShellListView` | `TTyShellListView` | `TTyCustomShellListView` |

宿主交出「它接受的任意子项」时也写 Custom 类：

- `TTyPageControl.ActivePage` / `Pages[]`：`TTyCustomTabSheet`；
- `TTyRibbon.ActivePage` / `Pages[]`：`TTyCustomRibbonPage`；
- `TTyToolBar.Buttons[]`、`IndexOfButton`、`TTyToolButton.ToolBar`：`TTyCustomToolButton` / `TTyCustomToolBar`；
- `TTySpeedButton.FindDownButton`：`TTyCustomSpeedButton`；
- 工具窗口一族交出的窗口、栏、操作区（`Windows[]`、`ActiveWindow`、`Bar`、`Actions`、`EnsureActions` 等）：对应的 Custom 类；
- 组合框弹层 API（`CreatePopupList` 等）：`TTyCustomListBox`。

于是 `var Ts: TTyTabSheet := PageControl1.ActivePage;` 这样的赋值编不过。把变量类型改成 Custom 类；确知拿到的是库里的控件、又要用最终类才有的东西，就 `as TTyTabSheet`。

覆写了这些虚方法的，签名一起改。

### 7.5 经基类或 Custom 类引用访问 protected 成员

3.0 的两个基类把 `TControl` 的一批 protected 成员提成了 published，4.0 还给 LCL。经 `TTyCustomControl`、`TTyGraphicControl` 或任何 `TTyCustomXxx` 类型的引用访问它们就编不过（经最终类类型照常）：

`OnDblClick`、`OnMouseDown`、`OnMouseUp`、`OnMouseMove`、`OnMouseEnter`、`OnMouseLeave`、`OnMouseWheel`、`OnMouseWheelUp`、`OnMouseWheelDown`、`OnMouseWheelHorz`、`OnMouseWheelLeft`、`OnMouseWheelRight`、`OnContextPopup`、`DragMode`、`DragKind`、`DragCursor`、`OnDragOver`、`OnDragDrop`、`OnStartDrag`、`OnEndDrag`、`ParentShowHint`，外加窗口化的 `OnEditingDone`、图形控件的 `OnPaint`。

`OnKeyDown`、`OnEnter`、`TabOrder`、`Enabled`、`Visible`、`Font`、`OnClick`、`PopupMenu` 这些在 LCL 里本来就是 public，不受影响。

要给「任意 Ty 控件」统一挂事件，用 LCL 惯用的 access 类：

```pascal
type
  TControlAccess = class(TControl);

TControlAccess(C).OnMouseDown := @MyMouseDown;   // 对一切 TControl 都成立
```

或者按 RTTI：`SetMethodProp(C, 'OnMouseDown', TMethod(Handler))`，每个最终类都发布了这些名字。

### 7.6 直接继承基类的自定义控件

如果你的控件直接继承 `TTyCustomControl` / `TTyGraphicControl` / `TTyComponent`，它在 4.0 里少了 `Enabled`、`Visible`、`Font`、`OnClick` 等约 50 个 published 属性，已有 `.lfm` 读入时会报「Unknown property」。把第 6 节那段 published 抄进自己的类就好；非可视组件只需要 `property Version;`。从任何 `TTyXxx` 最终类派生的不受影响。

### 7.7 中间类

`TTyGlyphButtonBase`、`TTyCustomTabStrip`、`TTyCustomGrid`、`TTyIconPackFont` 不再发布任何东西；`TTyGlyphButtonBase`、`TTyShellTreeLink`、`TTyIconPackFont` 的父类也换成了 Custom 类。直接继承它们的类要自己发布需要的属性，或者改从对应的最终类派生。`.lfm` 里写着 `object X: TTyCustomGrid` 的，换成 `TTyDrawGrid`。

### 7.8 其他

- `TTyIconFont.Version: Integer`（字形变更计数）改名 `ChangeStamp`；`Version` 现在是库版本字符串，跟其他组件一样。
- `Base.pas` 里原来解释「基类为什么发布这些属性」的长注释删了，内容并进了第 6 节那段代码的逐行说明和 [events.md](events.md)。
