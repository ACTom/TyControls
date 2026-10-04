# Deriving from TyControls controls

> 中文版见 [subclassing.md](subclassing.md)。

Since 4.0 most controls come in two layers, the way LCL does `TCustomEdit` / `TEdit` (the few that do not are listed at the end of section 5):

- `TTyCustomXxx` holds the whole implementation. Its properties sit in public or protected, following LCL, and none of them is published.
- `TTyXxx` is the class on the component palette. It is nothing but a `published` section listing what the Object Inspector shows.

To wrap a control and show your users only some of its properties, derive from `TTyCustomXxx`. To keep everything and add a few of your own, derive from `TTyXxx` — that works exactly as it did in 3.0.

This page covers how to derive, then the limits, and ends with what changes when you upgrade from 3.0.

---

## 1. A minimal example

A tag edit that exposes only its text, a read-only switch and `OnChange`:

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

Put it in a design-time package of your own and install it. The Object Inspector shows those three, plus the fifteen the LCL root classes publish and nobody can hide (`Name`, `Tag`, `Left`, `Top`, `Width`, `Height`, `Hint`, `Cursor`, the `Anchor*` and `Help*` properties).

A bare `property Text;` line takes the default, the stored clause and the accessors from the declaration in `TTyCustomEdit`, so what lands in the `.lfm` is exactly what `TTyEdit` writes. Do **not** write `property Text: string;` — that declares a new property and drops the default and the stored clause.

### Publishing order is `.lfm` order

The IDE writes properties in the order of the published section, and reads them back in file order, calling each setter as it goes. Some setters clamp against another property on the spot, so that property has to be published first. Mostly it is the range before the value; publish the value first and it gets clamped by the default range:

| Custom class | Publish first | Then |
|---|---|---|
| `TTyCustomSpinEdit` | `MinValue`, `MaxValue` | `Value`, then `ValueEmpty` |
| `TTyCustomProgressBar` | `Min`, `Max` | `Position` |
| `TTyCustomCircularProgress` | `Min`, `Max` | `Position` |
| `TTyCustomGauge` | `Min`, `Max` | `Value` |
| `TTyCustomMeter` | `Min`, `Max` | `Value` |
| `TTyCustomLevelMeter` | `Min`, `Max` | `Value` |
| `TTyCustomDial` | `Min`, `Max` | `Value` |
| `TTyCustomGearDial` | `Min`, `Max` | `Value` |
| `TTyCustomTrackBar` | `Min`, `Max` | `Position` |
| `TTyCustomScrollBar` | `Min`, `Max` | `Position` |
| `TTyCustomUpDown` | `Min`, `Max` | `Position` |
| `TTyCustomRating` | `Count` | `Value` |
| `TTyCustomFilterComboBox` | `Filter` | `FilterIndex` |
| `TTyCustomMaskEdit` | `Mask` | `SpaceChar` |

The last three are not ranges: a rating's value is clamped to the number of stars, `FilterIndex` to the number of filters in `Filter`, and a mask that spells its own blank character sets `SpaceChar` when it is assigned. `ValueEmpty` goes after `Value` on the spin edit because writing a number clears the empty state.

When in doubt, copy the order of the matching `TTyXxx`.

These do not care about order — the value is held while the form loads and applied in `Loaded`:

- `Value` on the numeric edits (`TTyCustomNumericEdit` and the currency, track, calculator and float-spin edits), applied against the final `Decimals` / `MinValue` / `MaxValue`;
- `ItemIndex` on the combo boxes, the list boxes, `TTyCustomButtonGroup` and `TTyCustomRadioGroup` (and `TopIndex` on list boxes), `Col` / `Row` on `TTyCustomStringGrid`, when the items are not there yet;
- `Selected` on `TTyCustomColorBox` / `TTyCustomColorListBox`;
- `PageIndex` on `TTyCustomPagination`, `ActiveIndex` on `TTyCustomToolWindowBar`, `ActivePageIndex` and `Minimized` on `TTyCustomRibbon`, `ItemIndex` on `TTyCustomRibbonGallery` / `TTyCustomRibbonBackstage`;
- `StepIndex` on `TTyCustomSteps` is never clamped to the items in the first place.

---

## 2. Themes

A control finds its styles through the type key `GetStyleTypeKey` returns (`'TyEdit'` for `TTyEdit`), and that override lives in the custom class. So `TMyTagEdit`, without a line of extra code, picks up every `TyEdit` rule and follows theme switches. You never write `TyCustomEdit` in a `.tycss` file; it is always `TyEdit`.

If you override `GetStyleTypeKey` to return a key of your own (`'MyTagEdit'`, say), the theme needs `MyTagEdit { ... }` rules or the control gets no style at all — there is no "fall back to `TyEdit`" yet; that is [#14](https://github.com/ACTom/TyControls/issues/14). Until it lands, either keep the inherited key or write the full rule set in your own theme.

---

## 3. Visibility in the custom classes

It follows the matching LCL custom class: a property with an LCL namesake takes its visibility, and controls with no LCL counterpart use public. Roughly:

- edits, combo boxes, list boxes, buttons, sliders, scroll bars, images: mostly public;
- labels, trees, list views, up-down, the grid base (`TTyCustomGrid`): mostly protected;
- `Checked` on `TTyCustomCheckBox` / `TTyCustomRadioButton` / `TTyCustomToggleSwitch` is protected, as LCL's `TButtonControl.Checked` is.

A protected property can still go in your published section. If you only want code to reach it, without putting it in the Object Inspector, promote it to public:

```pascal
  TMyCheck = class(TTyCustomCheckBox)
  public
    property Checked;
  published
    property Caption;
  end;
```

---

## 4. Design time

**Property editors come along.** The library registers them on the custom classes, or higher up on a base or intermediate class (`StyleClass`, `StyleOverride` and `Version` on `TTyCustomControl` / `TTyGraphicControl` / `TTyComponent`, the glyph buttons' `GlyphName` on `TTyGlyphButtonBase`). The IDE matches by inheritance, so publish the property and you get the same editor. The one editor registered by property type is `TTyColor`'s: every property of that type shows a hex value and a colour picker behind "...".

Hidden properties come in two kinds. Those the custom class declares `stored False` (the Lucide image list's `IconFont`, the `Controller` of tool windows and actions areas) are hidden on the custom class too, so they stay hidden even if you publish them — an edit there would never be saved anyway. The other hide rules stay on the final classes and only shape the library's own control; publish such a property and you can see and edit it.

**Component editors do not.** The double-click and right-click actions stay on the final classes, because they write properties your subclass may not publish. Your subclass does not get these:

| Component editor | Registered for | Actions |
|---|---|---|
| Page control editor | `TTyPageControl` | Add page, delete page, next page, previous page, show page |
| Tool window bar editor | `TTyToolWindowBar` | New tool window, show window |
| Tool window editor | `TTyToolWindow` | Add actions area, move to the other side, move back into the bar |
| Tree node editor | `TTyTreeView` | Double-click to edit the nodes |
| Cascader / tree-select node editors | `TTyCascader`, `TTyTreeSelect` | Double-click to edit the option tree |
| List group editor | `TTyListGroupPanel` | Edit the groups |
| Terminal editor | `TTyTerminalView` | Import / export a colour scheme |
| Image collection editor | `TTyImageCollection` | Manage the images |
| Dialog preview | each dialog | Preview |
| Icon browser | `TTyIconFont`, `TTyLucideIconFont`, `TTyVirtualImageList`, `TTyLucideImageList` | Browse icons |

`TTyFormSurface`'s `Purpose` and `Version` editors stay on the final class too; a surface subclass that publishes `Purpose` shows it as a plain read-only string.

Their implementations say `Component as TTyPageControl` and the like, so you **cannot** register them for your class — the first menu click raises `EInvalidCast`. The dialog preview (`TTyDialogComponentEditor`) checks for the final classes too, but with `is`: registered for your dialog class it raises nothing, and "Preview" simply does nothing.

The one you can borrow as is is the icon browser (`TTyIconBrowserComponentEditor`), which accepts any `TTyCustomIconFont` or `TTyCustomVirtualImageList`. It lives in the `tyControls.Design.CompEditors` unit of the design-time package `tycontrols_dt`, so make your design-time package require `tycontrols_dt`, use that unit, and call `RegisterComponentEditor(TMyIconFont, TTyIconBrowserComponentEditor)` in `Register`.

For the rest, write your own; it is short. Here is "Add page" for a page control:

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
  NewPage.Parent := PC;    // parent it first: that is what makes it a page
  NewName := GetDesigner.CreateUniqueComponentName(NewPage.ClassName);
  NewPage.Caption := NewName;
  NewPage.Name := NewName;
  PC.ActivePage := NewPage;
  Hook.PersistentAdded(NewPage, True);
  Modified;
end;

// In your design-time package's Register:
//   RegisterComponentEditor(TMyPageControl, TMyPageControlEditor);
```

`Pages[]`, `PageCount`, `ActivePage` and `ActivePageIndex`, which deleting and paging need, are all public on `TTyCustomPageControl`. Other families work the same way: treat the component as the custom class.

**`DefineProperties` lives in the custom class too.** The only override in the library is `TTyCustomVirtualImageList`'s (the Lucide image list inherits it). It writes the component's design-time position on the form (`Left` / `Top`) as usual, and **deliberately leaves out** `TCustomImageList`'s `Bitmap` pixel blob: the images are rebuilt by name in `Loaded`, and a blob found in an older form is read and thrown away. Your subclass behaves the same whatever it publishes.

---

## 5. Limits

- **The fifteen properties the LCL roots publish cannot be hidden.** `Name` and `Tag` from `TComponent`; `Left`, `Top`, `Width`, `Height`, `Hint`, `Cursor`, the four `AnchorSide*` and the three `Help*` from `TControl`. Pascal cannot unpublish, and LCL's own custom classes carry them too.
- **Some hosts still hand out a final class.** Most host properties now name the custom class (see section 7), but a host that only ever hands out what it built itself keeps the final type: `TTyRadioGroup`'s buttons are `TTyRadioButton`, `TTyCheckGroup`'s are `TTyCheckBox`, `TTyPageControl.AddPage` returns `TTyTabSheet`, and `TTyFilterComboBox.ShellListView` is `TTyShellListView`, as in LCL's `TFilterComboBox`.
- **Your own style controller cannot be attached to a control.** In the first 4.0 release every `Controller` property is still typed `TTyStyleController`. A controller derived from `TTyCustomStyleController` works on its own (loads a theme, resolves styles, notifies its listeners) but cannot be assigned to any control's `Controller`. Derive from `TTyStyleController` instead, or wait for a later release to widen the type.
- **The `GlyphName` editor looks the host's `IconFont` up by name.** Publish `IconFont` if your subclass should get the icon drop-down in the Object Inspector.
- **`TTyGridCell` is created by `TTyGridPanel`.** A cell subclass of yours has to be put in from code.
- **A `TTyCustomScrollBar` subclass is always a standalone scroll bar.** Hosts only embed the `TTyScrollBar` they create themselves; they never treat yours as their embedded bar.
- **Safe to leave unpublished:** `Text` on edits, memos and combo boxes. In those three families `Caption` is the text, so anything that drives a control through `Caption` — `TTyUpDown`, for one — still works.

### Classes that are not split

These have no `TTyCustomXxx`. To derive one, derive from the class on the palette; you inherit everything it publishes and cannot hide any of it.

| Class | Why it is not split | How to derive | Will it be split? |
|---|---|---|---|
| Menus: `TTyPopupMenu`, `TTyImagesMenu`, `TTyMenuEx` | LCL does not split `TPopupMenu` either | Derive directly | No, as in LCL |
| Dialogs: `TTySelectPathDialog`, `TTyColorDialog`, `TTyFontDialog`, `TTyFindDialog`, `TTyReplaceDialog`, `TTyOpenDialog`, `TTySaveDialog`, `TTyOpenPictureDialog`, `TTySavePictureDialog`, `TTyOpenPreviewDialog`, `TTySavePreviewDialog` | LCL's `TCommonDialog` family (`TOpenDialog`, `TColorDialog`…) publishes at every level | Derive directly | No, as in LCL |
| `TTyForm`, `TTyDialog` | They play the part of `TForm`: your forms already derive from them | New Form as usual, or `class(TTyForm)` | No |
| `TTyToolWindowManager` | There is a `TTyCustomToolWindowManager` (it publishes nothing), but moving windows across bars, the move queue and layout saving live in the final class, for unit dependencies | Derive from `TTyToolWindowManager`, not from `TTyCustomToolWindowManager` — the latter fits a bar's `Manager` but cannot move windows or save a layout | Once the implementation can move into the custom class; not scheduled |
| `TTyAdvanceChart`, `TTyCalendar`, `TTyDateTimePicker` | Another branch is still changing them | Derive directly | After that branch merges |

Ty's own eight dialogs (`TTyMessage`, `TTyInputDialog`, `TTyPasswordDialog`, `TTyTextDialog`, `TTySelectValueDialog`, `TTyProgressDialog`, `TTyAboutDialog`, `TTyIconBrowserDialog`) are split, as LCL splits `TCustomTaskDialog` / `TTaskDialog`.

---

## 6. Writing a brand-new control on the base classes

In 4.0 `TTyCustomControl` (windowed) and `TTyGraphicControl` (graphic) publish nothing, just like LCL's `TCustomControl` / `TGraphicControl`. For a control that derives from them directly, this is the set of common properties Ty controls publish; paste it into your published section as is (it is in Ty's order):

```pascal
  published
    property Version;          // library version; its '...' opens the About box
    property Enabled;
    property Visible;          // hide the control from the Object Inspector / .lfm
    property Font;             // mainly carries the PPI; the theme sets family and size
    property ShowHint;
    property TabOrder;         // windowed only
    property TabStop;          // windowed only
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
    property AutoSize;         // only does something if you implement CalculatePreferredSize
    property BorderWidth;      // windowed only: insets the child area, not the border
    property ChildSizing;      // windowed only: LCL's child layout engine
    property DragMode;         // LCL dispatches drag and drop; owner-drawn controls get it free
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz; // horizontal wheels, tilt wheels and touchpad swipes arrive only here
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;       // the one way to vary the hint by pointer position
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;          // fires after the control has painted: an overlay, not owner draw
    property OnKeyDown;        // the next seven are windowed only
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;       // theme variant, e.g. 'primary'
    property StyleOverride;    // a tycss snippet for this control only
    property Controller;       // which style controller; empty means the global default
```

For a graphic control, drop the lines marked "windowed only". Most Ty controls also publish `Align` and `Anchors`; add them if you want them.

[events.en.md](events.en.md) describes each of these.

---

## 7. Upgrading from 3.0

**Your `.lfm` files and your themes need no changes.** Every control keeps its property names, defaults, streaming order, default size and theme key. What changes is code that deals with class hierarchy and types, and the compiler finds most of it for you.

### 7.1 Controls whose parent changed

Derived controls now hang on the custom chain and are no longer descendants of their old parent control. `TTyGlyphButton is TTyButton` was True in 3.0 and is False in 4.0.

| Control | Parent in 3.0 | Parent in 4.0 (of `TTyCustomXxx`) | No longer a descendant of |
|---|---|---|---|
| TTyDropDownButton | TTyButton | TTyCustomButton | TTyButton |
| TTyMenuButton | TTyButton | TTyCustomButton | TTyButton |
| TTyColorButton | TTyButton | TTyCustomButton | TTyButton |
| TTyGlyphButton | TTyGlyphButtonBase | TTyGlyphButtonBase (← TTyCustomButton) | TTyButton |
| TTyGlyphContainerButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTySpeedButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTyToolButton | TTyGlyphButtonBase | TTyGlyphButtonBase | TTyButton |
| TTyRibbonAppMenu | TTyMenuButton | TTyCustomMenuButton | TTyMenuButton, TTyButton |
| TTyNumericEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyMaskEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyURLEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyComboEdit | TTyEdit | TTyCustomEdit | TTyEdit |
| TTyCurrencyEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit, TTyEdit |
| TTyTrackEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit, TTyEdit |
| TTyCalcEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit, TTyEdit |
| TTyFloatSpinEdit | TTyNumericEdit | TTyCustomNumericEdit | TTyNumericEdit, TTyEdit |
| TTyCalcCurrencyEdit | TTyCurrencyEdit | TTyCustomCurrencyEdit | TTyCurrencyEdit, TTyNumericEdit, TTyEdit |
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
| TTyColorComboBox | TTyColorBox | TTyCustomColorBox | TTyColorBox, TTyComboBox |
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
| TTyScrollPanel | TTyScrollBox | TTyCustomScrollBox | TTyScrollBox, TTyPanel |
| TTyCoolBar | TTyControlBar | TTyCustomControlBar | TTyControlBar, TTyPanel |
| TTyToolBarEx | TTyToolBar | TTyCustomToolBar | TTyToolBar |
| TTyShellTreeView | TTyShellTreeLink | TTyShellTreeLink (← TTyCustomTreeView) | TTyTreeView |
| TTyShellListView | TTyListView | TTyCustomListView | TTyListView |
| TTyStringGrid | TTyDrawGrid | TTyCustomDrawGrid | TTyDrawGrid |
| TTyLucideIconFont | TTyIconPackFont | TTyIconPackFont (← TTyCustomIconFont) | TTyIconFont |
| TTyLucideImageList | TTyVirtualImageList | TTyCustomVirtualImageList | TTyVirtualImageList |

`TTyPageControl`, `TTyTabSet`, `TTyRibbon` (under `TTyCustomTabStrip`) and `TTyDrawGrid` (under `TTyCustomGrid`) keep their parent; only the intermediate class stopped publishing.

### 7.2 `is`, `as` and casts

One rule: **when you mean "any Xxx", test for `TTyCustomXxx`**. When you mean exactly that class, leave it.

```pascal
// 3.0: raises EInvalidCast in 4.0 for the TTyToolButton and TTyGlyphButton on a tool bar
StatusBar1.SimpleText := (Sender as TTyButton).Caption;
// 4.0
StatusBar1.SimpleText := (Sender as TTyCustomButton).Caption;

// 3.0: silently False in 4.0 for TTyNumericEdit, TTyMaskEdit and friends
if AControl is TTyEdit then ...
// 4.0
if AControl is TTyCustomEdit then ...
```

You can hit all three symptoms: `is` quietly turns False, `as` raises `EInvalidCast` at run time, and assigning a derived control to a variable of the old parent type no longer compiles. A hard cast like `TTyButton(AGlyphButton)` still "runs" (final classes add no fields), but it lies about the object; change it by the same rule.

If, after switching to the custom class, the property you need is protected there (section 3) and the object is one of the library's controls, get the final class with `as TTyXxx`. That is fine for the library's control, and should a third-party subclass turn up, it raises `EInvalidCast` instead of quietly reading the wrong thing.

### 7.3 Event handler signatures

In families with a custom class, the event's Sender is the custom class, as in LCL (`TTVCustomDrawEvent = procedure(Sender: TCustomTreeView; ...)`). This affects:

- the 21 `TTyTreeView` event types (`OnGetText`, `OnPaintText`, `OnCompareNodes`, `OnInitChildren`, `OnChecking` and the rest): `Sender: TTyCustomTreeView`;
- `TTyHeaderControl`'s `TTyHeaderSectionEvent`, `TTyHeaderResizeEvent`, `TTyHeaderTrackEvent`: `TTyCustomHeaderControl`;
- `TTyStatusBar.OnDrawPanel`: `AStatusBar: TTyCustomStatusBar`;
- `TTyToolBar.OnPaintButton`: `Sender: TTyCustomToolButton`;
- `TTyRibbonGroup.OnDialogLauncher`: `Sender: TTyCustomRibbonGroup`;
- the window and bar parameters (not the Sender) of `TTyToolWindowManager.OnCanMoveWindow` / `OnWindowMoved`: `TTyCustomToolWindow`, `TTyCustomToolWindowBar`.

```pascal
// 3.0
procedure TForm1.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
// 4.0
procedure TForm1.TreeGetText(Sender: TTyCustomTreeView; Node: PTyTreeNode; var Text: string);
```

The `.lfm` links handlers by method name and never checks the signature, so form files stay as they are; fix the declarations and rebuild.

### 7.4 Property and return types

Properties that reference a component name the custom class, as LCL does (`Images: TCustomImageList`), so both the library's derived components and your own subclasses can be assigned:

| Property | 3.0 | 4.0 |
|---|---|---|
| every `IconFont` | `TTyIconFont` | `TTyCustomIconFont` |
| `Controller` | `TTyStyleController` | unchanged (see section 5) |
| `Images` / `HotImages` / `DisabledImages` (image collections), `TTyVirtualImageList.Collection` | `TTyImageCollection` | `TTyCustomImageCollection` |
| `TTyForm.TitleBar` / `MenuBar` (same on `TTyDialog`) | `TTyTitleBar` / `TTyMenuBar` | `TTyCustomTitleBar` / `TTyCustomMenuBar` |
| `TTyRibbon.Backstage`, `TTyRibbonAppMenu.Backstage` | `TTyRibbonBackstage` | `TTyCustomRibbonBackstage` |
| `TTyShellTreeView.ShellListView` | `TTyShellListView` | `TTyCustomShellListView` |

A host that hands out whatever child it accepts also uses the custom class:

- `TTyPageControl.ActivePage` / `Pages[]`: `TTyCustomTabSheet`;
- `TTyRibbon.ActivePage` / `Pages[]`: `TTyCustomRibbonPage`;
- `TTyToolBar.Buttons[]`, `IndexOfButton`, `TTyToolButton.ToolBar`: `TTyCustomToolButton` / `TTyCustomToolBar`;
- `TTySpeedButton.FindDownButton`: `TTyCustomSpeedButton`;
- the windows, bars and actions areas the tool-window family hands out (`Windows[]`, `ActiveWindow`, `Bar`, `Actions`, `EnsureActions` and so on): the matching custom classes;
- the combo-box popup API (`CreatePopupList` and friends): `TTyCustomListBox`.

So an assignment like this no longer compiles:

```pascal
var
  Ts: TTyTabSheet;
begin
  Ts := PageControl1.ActivePage;   // 4.0: ActivePage is a TTyCustomTabSheet
```

Change the variable to the custom class; if you know it is the library's control and need something only the final class has, write `Ts := PageControl1.ActivePage as TTyTabSheet;`.

If you override any of these virtual methods, update the signature too.

### 7.5 Protected members through a base or custom reference

3.0's two base classes promoted a group of `TControl`'s protected members to published; 4.0 gives them back to LCL. Through a `TTyCustomControl`, `TTyGraphicControl` or any `TTyCustomXxx` reference they no longer compile (through a final-class reference they still do):

`OnDblClick`, `OnMouseDown`, `OnMouseUp`, `OnMouseMove`, `OnMouseEnter`, `OnMouseLeave`, `OnMouseWheel`, `OnMouseWheelUp`, `OnMouseWheelDown`, `OnMouseWheelHorz`, `OnMouseWheelLeft`, `OnMouseWheelRight`, `OnContextPopup`, `DragMode`, `DragKind`, `DragCursor`, `OnDragOver`, `OnDragDrop`, `OnStartDrag`, `OnEndDrag`, `ParentShowHint`, plus `OnEditingDone` on windowed controls and `OnPaint` on graphic ones.

`OnKeyDown`, `OnEnter`, `TabOrder`, `Enabled`, `Visible`, `Font`, `OnClick`, `PopupMenu` and the like are public in LCL already and are not affected.

To hook an event on "any Ty control", use LCL's usual access class:

```pascal
type
  TControlAccess = class(TControl);

TControlAccess(C).OnMouseDown := @MyMouseDown;   // works for any TControl
```

or go through RTTI with `SetMethodProp(C, 'OnMouseDown', TMethod(Handler))` — every final class publishes these names.

### 7.6 Your own controls on the base classes

A control that derives straight from `TTyCustomControl` / `TTyGraphicControl` / `TTyComponent` loses about fifty published properties in 4.0 (`Enabled`, `Visible`, `Font`, `OnClick`…), and existing `.lfm` files report "Unknown property" on load. Paste the published section from section 6 into your class; a non-visual component only needs `property Version;`. Anything derived from a `TTyXxx` final class is unaffected.

### 7.7 Intermediate classes

`TTyGlyphButtonBase`, `TTyCustomTabStrip`, `TTyCustomGrid` and `TTyIconPackFont` publish nothing any more, and `TTyGlyphButtonBase`, `TTyShellTreeLink` and `TTyIconPackFont` now sit on custom classes. A class deriving from them must publish what it needs, or derive from the matching final class instead. An `.lfm` that says `object X: TTyCustomGrid` should say `TTyDrawGrid`.

### 7.8 Other

- `TTyIconFont.Version: Integer` (the glyph change counter) is now `ChangeStamp`; `Version` is the library version string, as on every other component.
- The long comments in `Base.pas` that explained why the base classes published these properties are gone; their content is in the per-line notes of the section 6 listing and in [events.en.md](events.en.md).
