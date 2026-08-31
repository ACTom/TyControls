unit tyControls.Design;
{$mode objfpc}{$H+}
{ The package's registration TRUNK: the component palette, the IDE-level wiring (theme
  pack, designer base classes, the OI-refresh bridge) and the calls into the three
  sibling units that own the actual editors:

    tyControls.Design.PropEditors — every property editor + RegisterPropertyEditors
    tyControls.Design.CompEditors — every component editor + RegisterComponentEditors
    tyControls.Design.NewItems    — File > New templates + RegisterNewItems
    tyControls.Design.Css.Editor  — the SynEdit-backed tycss editor (used by PropEditors)

  The drift-guard tests (test.version / test.designeditors / test.designregistry /
  test.paletteicons) scan the whole designtime/ directory, so a registration is found
  whichever unit it lives in — but the PALETTE groups must stay in THIS file:
  scripts/gen-icons.ps1 and test.paletteicons parse the RegisterComponents groups here. }
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, StdCtrls, ExtCtrls, Graphics, LCLIntf, LCLType,
  PropEdits, PropEditUtils, ComponentEditors, ProjectIntf, FormEditingIntf, LazIDEIntf,
  LResources, tyControls.Types, tyControls.Component,
  tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit, tyControls.NumericEdit,
  tyControls.CurrencyEdit, tyControls.MaskEdit, tyControls.URLEdit, tyControls.ComboEdit,
  tyControls.TrackEdit, tyControls.ColorBox, tyControls.ColorListBox, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.CheckListBox,
  tyControls.ColorComboBox, tyControls.MRUComboBox, tyControls.ComboBoxEx,
  tyControls.OfficeListBox, tyControls.OfficeComboBox,
  tyControls.ColorGrid, tyControls.LColorPicker, tyControls.HSColorPicker,
  tyControls.AdvancedListBox, tyControls.AdvancedComboBox, tyControls.CheckComboBox,
  tyControls.ValueListEditor, tyControls.Calculator, tyControls.CalcEdit,
  tyControls.CalcCurrencyEdit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.Gauge,
  tyControls.CircularProgress, tyControls.ActivityIndicator, tyControls.ActivityBar,
  tyControls.Meter, tyControls.LevelMeter, tyControls.Dial, tyControls.AnalogClock,
  tyControls.Sparkline, tyControls.Rating, tyControls.GearDial,
  tyControls.GearActivityIndicator, tyControls.UpDown,
  tyControls.LinkLabel, tyControls.ShadowLabel, tyControls.GlowLabel,
  tyControls.Hint, tyControls.BalloonHint,
  tyControls.IconFont, tyControls.Icons.Lucide, tyControls.CharImage,
  tyControls.GlyphImageList,
  tyControls.Image, tyControls.ImageCollection,
  tyControls.GlyphButtons, tyControls.DropButtons, tyControls.ColorButton,
  tyControls.ButtonGroup, tyControls.Ribbon, tyControls.RibbonAppMenu,
  tyControls.RibbonQuickAccess, tyControls.RibbonGallery, tyControls.RibbonBackstage,
  tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.FloatSpinEdit,
  tyControls.Memo, tyControls.Menu, tyControls.NativeStyler,
  tyControls.Splitter, tyControls.StatusBar, tyControls.ToolBar,
  tyControls.Calendar, tyControls.DateTimePicker, tyControls.TabSet,
  tyControls.TreeView, tyControls.Dialogs, tyControls.Dialogs.SelectPath,
  tyControls.Dialogs.IconBrowser,
  tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress, tyControls.Dialogs.About,
  tyControls.Dialogs.FileDialog, tyControls.PreviewBox, tyControls.ImageView,
  tyControls.Chart, tyControls.HtmlLabel,
  tyControls.Bevel, tyControls.Divider, tyControls.PaintPanel, tyControls.SizeBox,
  tyControls.RadioGroup, tyControls.CheckGroup, tyControls.ToolGroupPanel,
  tyControls.ScrollBox, tyControls.ScrollPanel, tyControls.ExPanel,
  tyControls.GridPanel, tyControls.GridCell, tyControls.RelativePanel,
  tyControls.ToolBarEx, tyControls.ControlBar, tyControls.CoolBar,
  tyControls.HeaderControl, tyControls.ListGroupPanel,
  tyControls.Shape, tyControls.StarShape, tyControls.Arrow,
  tyControls.Card, tyControls.Tag, tyControls.Badge, tyControls.Grid,
  tyControls.Alert, tyControls.Notification, tyControls.Empty, tyControls.Segmented,
  tyControls.Pagination, tyControls.Steps, tyControls.Breadcrumb,
  tyControls.Transfer, tyControls.TreeSelect, tyControls.Cascader, tyControls.Popover,
  tyControls.ListView, tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.FilterComboBox, tyControls.ShellComboBox,
  { The vocabulary source of the theme dropdowns, published into the IDE process here. }
  tyControls.BuiltinThemes, tyControls.ThemeRegistry,
  { The three sibling units this trunk registers. }
  tyControls.Design.PropEditors, tyControls.Design.CompEditors, tyControls.Design.NewItems;

procedure Register;

implementation

procedure RefreshInspectorValues;
begin
  if GlobalDesignHook <> nil then
    GlobalDesignHook.RefreshPropertyValues;
end;

procedure Register;
begin
  { Publish the compiled-in theme pack into THIS PROCESS (the IDE). An application does this
    itself at startup; the IDE never did, which made a design-time ThemeName inert — the
    controller resolved the name against an empty registry, loaded nothing, and the designer
    went on drawing the base layer. Two things depend on it now: picking a theme in the Object
    Inspector actually re-skins the form under the designer, and the Mode dropdown can list the
    '@mode' blocks of the theme that is loaded (an unloaded model declares none). Design-time
    only —nothing here runs in a built application, whose own TyRegisterBuiltinThemes call is
    still what makes ThemeName resolve at run time. }
  TyRegisterBuiltinThemes;
  { The runtime side of the IDE bridge (tyControls.Types): a control whose design-time
    gesture changed a published value (a designer tab click switching ActivePageIndex)
    calls through this to make the Object Inspector re-read what it shows -- the
    RefreshPropertyValues hook is the only signal the OI re-reads on. }
  TyDesignerRefreshValuesProc := @RefreshInspectorValues;
  // Register the component-palette icons (24x24 PNG per class, generated by
  // tools/genicons -> scripts/gen-icons.ps1). The IDE looks each up by class name;
  // this MUST run before RegisterComponents so the palette finds them.
  {$I tycontrols_icons.lrs}
  // Make TTyForm a recognized designer base class. Without this the form designer
  // cannot resolve `class(TTyForm)` as an ancestor and silently falls back to TForm
  // (sourcefilemanager FindBaseComponentClass -> StandardDesignerBaseClasses[TForm]),
  // so the Object Inspector shows none of TTyForm's published chrome properties
  // (TitleBar / TitleHeight / BorderIcons / Resizable). RegisterComponents only
  // covers droppable controls, not base form classes —this is the form-level analog.
  if FormEditingHook <> nil then
  begin
    FormEditingHook.RegisterDesignerBaseClass(TTyForm);
    // TTyDialog is a distinct designer base class (close-only modal dialog): register it so
    // `class(TTyDialog)` resolves as an ancestor and the OI shows its chrome, same as TTyForm.
    FormEditingHook.RegisterDesignerBaseClass(TTyDialog);
  end;
  // The palette is split into functional groups so no single tab is overcrowded. NOTE: both
  // scripts/gen-icons.ps1 and tests/test.paletteicons.pas parse EVERY
  // RegisterComponents('TyControls...', [...]) group here and require each registered class to
  // have a generated icon —a new control must land in one of these groups (and get a glyph in
  // genicons.lpr + the $classes entry), never a standalone unlisted class. The TEST is the guard
  // that fires without anyone running the script: TTyDrawGrid/TTyStringGrid once reached this
  // list with no icon and nothing noticed, because the test kept its own copy of the class list.
  // === Palette groups, organised by control TYPE (same class set as before) ===
  // Core (non-visual).
  RegisterComponents('TyControls',
    [TTyStyleController, TTyNativeStyler]);
  // Buttons.
  RegisterComponents('TyControls Buttons',
    [TTyButton, TTyGlyphButton, TTyGlyphContainerButton, TTySpeedButton,
     TTyDropDownButton, TTyMenuButton, TTyColorButton, TTyButtonGroup]);
  // Labels.
  RegisterComponents('TyControls Labels',
    [TTyLabel, TTyHtmlLabel, TTyLinkLabel, TTyShadowLabel, TTyGlowLabel,
     TTyTag, TTyBadge]);
  // Text edits: single/multi-line, formatted, calculator, spin.
  RegisterComponents('TyControls Edits',
    [TTyEdit, TTyNumericEdit, TTyCurrencyEdit, TTyMaskEdit, TTyURLEdit, TTyComboEdit,
     TTyTrackEdit, TTyCalcEdit, TTyCalcCurrencyEdit, TTyCalculator,
     TTyMemo, TTySpinEdit, TTyFloatSpinEdit, TTyUpDown]);
  // Checks / radios / switches + their groups.
  RegisterComponents('TyControls Choices',
    [TTyCheckBox, TTyRadioButton, TTyToggleSwitch, TTyRadioGroup, TTyCheckGroup, TTySegmented]);
  // Combo boxes & list boxes.
  RegisterComponents('TyControls Lists',
    [TTyComboBox, TTyMRUComboBox, TTyComboBoxEx, TTyOfficeComboBox, TTyAdvancedComboBox,
     TTyCheckComboBox,
     TTyListBox, TTyCheckListBox, TTyOfficeListBox, TTyAdvancedListBox, TTyValueListEditor,
     TTyTransfer, TTyTreeSelect, TTyCascader]);
  // Rich pickers: colour / font / filter / shell selectors.
  RegisterComponents('TyControls Pickers',
    [TTyColorBox, TTyColorComboBox, TTyColorListBox, TTyColorGrid, TTyLColorPicker,
     TTyHSColorPicker, TTyFontComboBox, TTyFontListBox, TTyFontSizeComboBox,
     TTyFilterComboBox, TTyShellComboBox]);
  // Instruments & indicators.
  RegisterComponents('TyControls Gauges',
    [TTyGauge, TTyMeter, TTyLevelMeter, TTyDial, TTyGearDial, TTyAnalogClock,
     TTyCircularProgress, TTyActivityIndicator, TTyActivityBar, TTyGearActivityIndicator,
     TTySparkline, TTyRating]);
  // Bars: sliders / progress / scroll / status / tool bars + header.
  RegisterComponents('TyControls Bars',
    [TTyTrackBar, TTyProgressBar, TTyScrollBar, TTyStatusBar,
     TTyToolBar, TTyToolButton, TTyToolSeparator, TTyToolBarEx, TTyControlBar, TTyCoolBar,
     TTyAlert, TTyPagination, TTySteps, TTyBreadcrumb, TTyHeaderControl]);
  // Containers & layout.
  RegisterComponents('TyControls Containers',
    [TTyPanel, TTyGroupBox, TTyBevel, TTyDivider, TTySplitter, TTyPaintPanel, TTySizeBox,
     TTyScrollBox, TTyScrollPanel, TTyExPanel, TTyGridPanel, TTyRelativePanel,
     TTyToolGroupPanel, TTyListGroupPanel,
     TTyPageControl, TTyTabSheet, TTyTabSet, TTyTitleBar,
     TTyCard, TTyEmpty]);
  // Cells are created/owned by the grid, not dragged from the palette —register the
  // class (for streaming + OI selection) without a palette button.
  RegisterNoIcon([TTyGridCell]);
  // Data views + shell/file views + date/time.
  RegisterComponents('TyControls Data Views',
    [TTyTreeView, TTyListView, TTyShellListView, TTyShellTreeView, TTyPreviewBox, TTyImageView,
     TTyCalendar, TTyDateTimePicker,
     TTyDrawGrid, TTyStringGrid]);
  // Menus.
  RegisterComponents('TyControls Menus',
    [TTyMenuBar, TTyPopupMenu, TTyImagesMenu, TTyMenuEx]);
  // Office-style ribbon parts.
  RegisterComponents('TyControls Ribbon',
    [TTyRibbon, TTyRibbonPage, TTyRibbonGroup, TTyRibbonAppMenu,
     TTyRibbonQuickAccess, TTyRibbonGallery, TTyRibbonBackstage]);
  // Icon-font, images, hints.
  RegisterComponents('TyControls Images',
    [TTyIconFont, TTyLucideIconFont, TTyLucideImageList, TTyCharImage, TTyGlyphImageList,
     TTyImage, TTyImageCollection, TTyVirtualImageList, TTyHint, TTyBalloonHint,
     TTyPopover]);
  // Decorative vector shapes + charts.
  RegisterComponents('TyControls Shapes & Charts',
    [TTyShape, TTyStarShape, TTyArrow, TTyChart]);
  // Dialogs: message / input family / pickers / find-replace / progress / about / file.
  RegisterComponents('TyControls Dialogs',
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog,
     TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog, TTyAboutDialog,
     TTyOpenDialog, TTySaveDialog, TTyOpenPictureDialog, TTySavePictureDialog,
     TTyOpenPreviewDialog, TTySavePreviewDialog, TTyNotification,
     TTyIconBrowserDialog]);
  { The content host MUST be a registered component class, or deleting it is unrecoverable. The
    designer records a delete by SERIALIZING the component to LFM text (TDesigner.AddUndoAction ->
    CopySelectionToStream) and undoes it by PASTING that text back —so undo runs through the same
    registry paste does. RegisterNoIcon, not RegisterComponents: registered (so undo works) but with
    no palette icon, since the surface only ever comes from the form template.
    Pasting a stray surface is NOT blocked: the designer's paste reaches its parent without routing
    through the SetParent a guard could hook, so the guards we tried only ever caught the form itself
    while every other container let one through —half a fence, so they were removed. Harmless in
    practice: the surface is not on the palette, so a stray one only appears if you deliberately copy
    it, and a form ignores any surface that is not its own. }
  RegisterNoIcon([TTyFormSurface]);
  { The three sibling units own everything else. }
  RegisterPropertyEditors;
  RegisterComponentEditors;
  RegisterNewItems;
end;

end.
