unit test.defaults.guard;
{ #108: a published ordinal property's declared default must be the value the constructor sets.
  When the two disagree, the designer loses a value: one equal to the declared default is not
  written to the .lfm, and the constructor puts its own back when the form is read. Every
  class on the component palette is checked, so a new mismatch fails here and names itself.

  Left out: what reaches the whole application when created (TTyStyleController,
  TTyNativeStyler, TTyHint) and the two form classes, which are not created this way. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms, fpcunit, testregistry;

type
  TDeclaredDefaultsTest = class(TTestCase)
  published
    procedure TestEveryDeclaredDefaultIsTheConstructedValue;
    procedure TestColorListBoxTopIndexSurvivesTheFormFile;
  end;

implementation

uses
  tyControls.ActivityBar, tyControls.ActivityIndicator, tyControls.AdvanceChart, tyControls.AdvancedComboBox,
  tyControls.AdvancedListBox, tyControls.Alert, tyControls.AnalogClock, tyControls.Arrow,
  tyControls.Badge, tyControls.BalloonHint, tyControls.Bevel, tyControls.Breadcrumb,
  tyControls.Button, tyControls.ButtonGroup, tyControls.CalcCurrencyEdit, tyControls.CalcEdit,
  tyControls.Calculator, tyControls.Calendar, tyControls.Card, tyControls.Cascader,
  tyControls.CharImage, tyControls.Chart, tyControls.CheckBox, tyControls.CheckComboBox,
  tyControls.CheckGroup, tyControls.CheckListBox, tyControls.CircularProgress, tyControls.ColorBox,
  tyControls.ColorButton, tyControls.ColorComboBox, tyControls.ColorGrid, tyControls.ColorListBox,
  tyControls.ComboBox, tyControls.ComboBoxEx, tyControls.ComboEdit, tyControls.ControlBar,
  tyControls.CoolBar, tyControls.CurrencyEdit, tyControls.DateTimePicker, tyControls.DB.Choices,
  tyControls.DB.DateTime, tyControls.DB.Edits, tyControls.DB.Grid, tyControls.DB.Image,
  tyControls.DB.Lists, tyControls.DB.Navigator, tyControls.Dial, tyControls.Dialogs,
  tyControls.Dialogs.About, tyControls.Dialogs.Color, tyControls.Dialogs.FileDialog, tyControls.Dialogs.Find,
  tyControls.Dialogs.Font, tyControls.Dialogs.IconBrowser, tyControls.Dialogs.Progress, tyControls.Dialogs.SelectPath,
  tyControls.Divider, tyControls.DropButtons, tyControls.Edit, tyControls.Empty,
  tyControls.ExPanel, tyControls.FilterComboBox, tyControls.FloatSpinEdit, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.Form, tyControls.FormSurface,
  tyControls.Gauge, tyControls.GearActivityIndicator, tyControls.GearDial, tyControls.GlowLabel,
  tyControls.GlyphButtons, tyControls.GlyphImageList, tyControls.Grid, tyControls.GridPanel,
  tyControls.GroupBox, tyControls.HeaderControl, tyControls.HSColorPicker, tyControls.HtmlLabel,
  tyControls.IconFont, tyControls.Icons.Lucide, tyControls.Image, tyControls.ImageCollection,
  tyControls.ImageView, tyControls.LColorPicker, tyControls.LevelMeter, tyControls.LinkLabel,
  tyControls.ListBox, tyControls.ListGroupPanel, tyControls.ListView, tyControls.MaskEdit,
  tyControls.Memo, tyControls.Menu, tyControls.Meter, tyControls.MRUComboBox,
  tyControls.MultiTrackBar, tyControls.Notification, tyControls.NumericEdit, tyControls.OfficeComboBox,
  tyControls.OfficeListBox, tyControls.PageControl, tyControls.Pagination, tyControls.PaintPanel,
  tyControls.Panel, tyControls.Popover, tyControls.PreviewBox, tyControls.ProgressBar,
  tyControls.PropertyGrid, tyControls.RadioGroup, tyControls.Rating, tyControls.RelativePanel,
  tyControls.Ribbon, tyControls.RibbonAppMenu, tyControls.RibbonBackstage, tyControls.RibbonGallery,
  tyControls.RibbonQuickAccess, tyControls.ScrollBar, tyControls.ScrollBox, tyControls.ScrollPanel,
  tyControls.Segmented, tyControls.ShadowLabel, tyControls.Shape, tyControls.ShellComboBox,
  tyControls.ShellListView, tyControls.ShellTreeView, tyControls.SizeBox, tyControls.Sparkline,
  tyControls.SpinEdit, tyControls.Splitter, tyControls.StarShape, tyControls.StatusBar,
  tyControls.Steps, tyControls.TabSet, tyControls.TabSheet, tyControls.Tag,
  tyControls.Terminal, tyControls.ToggleSwitch, tyControls.ToolBar, tyControls.ToolBarEx,
  tyControls.ToolGroupPanel, tyControls.ToolWindows, tyControls.ToolWindows.Manager, tyControls.TrackBar,
  tyControls.TrackEdit, tyControls.Transfer, tyControls.TreeSelect, tyControls.TreeView,
  tyControls.TyLabel, tyControls.UpDown, tyControls.URLEdit, tyControls.ValueListEditor;

const
  Palette: array[0..195] of TComponentClass = (
    TTyAboutDialog, TTyActivityBar, TTyActivityIndicator, TTyAdvanceChart,
    TTyAdvancedComboBox, TTyAdvancedListBox, TTyAlert, TTyAnalogClock,
    TTyArrow, TTyBadge, TTyBalloonHint, TTyBevel,
    TTyBreadcrumb, TTyButton, TTyButtonGroup, TTyCalcCurrencyEdit,
    TTyCalcEdit, TTyCalculator, TTyCalendar, TTyCard,
    TTyCascader, TTyCharImage, TTyChart, TTyCheckBox,
    TTyCheckComboBox, TTyCheckGroup, TTyCheckListBox, TTyCircularProgress,
    TTyColorBox, TTyColorButton, TTyColorComboBox, TTyColorDialog,
    TTyColorGrid, TTyColorListBox, TTyComboBox, TTyComboBoxEx,
    TTyComboEdit, TTyControlBar, TTyCoolBar, TTyCurrencyEdit,
    TTyDateTimePicker, TTyDBCalendar, TTyDBCheckBox, TTyDBComboBox,
    TTyDBCurrencyEdit, TTyDBDateTimePicker, TTyDBEdit, TTyDBFloatSpinEdit,
    TTyDBGrid, TTyDBImage, TTyDBListBox, TTyDBLookupComboBox,
    TTyDBLookupListBox, TTyDBMaskEdit, TTyDBMemo, TTyDBNavigator,
    TTyDBNumericEdit, TTyDBRadioGroup, TTyDBRating, TTyDBSegmented,
    TTyDBSpinEdit, TTyDBText, TTyDBToggleSwitch, TTyDial,
    TTyDivider, TTyDrawGrid, TTyDropDownButton, TTyEdit,
    TTyEmpty, TTyExPanel, TTyFilterComboBox, TTyFindDialog,
    TTyFloatSpinEdit, TTyFontComboBox, TTyFontDialog, TTyFontListBox,
    TTyFontSizeComboBox, TTyFormSurface, TTyGauge, TTyGearActivityIndicator,
    TTyGearDial, TTyGlowLabel, TTyGlyphButton, TTyGlyphContainerButton,
    TTyGlyphImageList, TTyGradientTrackBar, TTyGridCell, TTyGridPanel,
    TTyGroupBox, TTyHeaderControl, TTyHSColorPicker, TTyHtmlLabel,
    TTyIconBrowserDialog, TTyIconFont, TTyImage, TTyImageCollection,
    TTyImagesMenu, TTyImageView, TTyInputDialog, TTyLabel,
    TTyLColorPicker, TTyLevelMeter, TTyLinkLabel, TTyListBox,
    TTyListGroupPanel, TTyListView, TTyLucideIconFont, TTyLucideImageList,
    TTyMaskEdit, TTyMemo, TTyMenuBar, TTyMenuButton,
    TTyMenuEx, TTyMessage, TTyMeter, TTyMRUComboBox,
    TTyMultiTrackBar, TTyNotification, TTyNumericEdit, TTyOfficeComboBox,
    TTyOfficeListBox, TTyOpenDialog, TTyOpenPictureDialog, TTyOpenPreviewDialog,
    TTyPageControl, TTyPagination, TTyPaintPanel, TTyPanel,
    TTyPasswordDialog, TTyPopover, TTyPopupMenu, TTyPreviewBox,
    TTyProgressBar, TTyProgressDialog, TTyPropertyGrid, TTyRadioButton,
    TTyRadioGroup, TTyRangeTrackBar, TTyRating, TTyRelativePanel,
    TTyReplaceDialog, TTyRibbon, TTyRibbonAppMenu, TTyRibbonBackstage,
    TTyRibbonGallery, TTyRibbonGroup, TTyRibbonPage, TTyRibbonQuickAccess,
    TTySaveDialog, TTySavePictureDialog, TTySavePreviewDialog, TTyScrollBar,
    TTyScrollBox, TTyScrollPanel, TTySegmented, TTySelectPathDialog,
    TTySelectValueDialog, TTyShadowLabel, TTyShape, TTyShellComboBox,
    TTyShellListView, TTyShellTreeView, TTySizeBox, TTySparkline,
    TTySpeedButton, TTySpinEdit, TTySplitter, TTyStarShape,
    TTyStatusBar, TTySteps, TTyStringGrid, TTyTabSet,
    TTyTabSheet, TTyTag, TTyTerminalView, TTyTextDialog,
    TTyTitleBar, TTyToggleSwitch, TTyToolBar, TTyToolBarEx,
    TTyToolButton, TTyToolGroupPanel, TTyToolSeparator, TTyToolWindow,
    TTyToolWindowActions, TTyToolWindowBar, TTyToolWindowManager, TTyTrackBar,
    TTyTrackEdit, TTyTransfer, TTyTreeSelect, TTyTreeView,
    TTyUpDown, TTyURLEdit, TTyValueListEditor, TTyVirtualImageList);

  { Mismatches kept on purpose, each with its reason. }
  Exempt: array[0..0] of string = (
    { Forms saved before the bar snapped to the top carry no Align and rely on alNone. }
    'TTyTitleBar.Align');

function IsExempt(const AName: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(Exempt) do
    if SameText(Exempt[i], AName) then Exit(True);
  Result := False;
end;

procedure TDeclaredDefaultsTest.TestEveryDeclaredDefaultIsTheConstructedValue;
var
  i, j, n: Integer;
  c: TComponent;
  props: PPropList;
  p: PPropInfo;
  cur: Int64;
  found: TStringList;
begin
  found := TStringList.Create;
  try
    for i := 0 to High(Palette) do
    begin
      c := Palette[i].Create(nil);
      try
        n := GetPropList(PTypeInfo(c.ClassInfo), props);
        try
          for j := 0 to n - 1 do
          begin
            p := props^[j];
            if not (p^.PropType^.Kind in [tkInteger, tkChar, tkWChar, tkEnumeration, tkBool, tkSet]) then
              Continue;
            if (p^.GetProc = nil) or (p^.SetProc = nil) then Continue;
            if p^.Default = LongInt($80000000) then Continue;   // nodefault: always written
            if not IsStoredProp(c, p) then Continue;
            if IsExempt(c.ClassName + '.' + p^.Name) then Continue;
            cur := GetOrdProp(c, p);
            if LongInt(cur) <> p^.Default then
              found.Add(Format('%s.%s: declared %d, constructed %d',
                [c.ClassName, p^.Name, p^.Default, cur]));
          end;
        finally
          FreeMem(props);
        end;
      finally
        c.Free;
      end;
    end;
    AssertEquals('a declared default that is not the constructed value:' + LineEnding
      + found.Text, 0, found.Count);
  finally
    found.Free;
  end;
end;

{ The one loss that is not a declared default: the list was refilled after TopIndex arrived. }
procedure TDeclaredDefaultsTest.TestColorListBoxTopIndexSurvivesTheFormFile;
var
  f, f2: TForm;
  b: TTyColorListBox;
  ms: TMemoryStream;
begin
  if GetClass('TTyColorListBox') = nil then RegisterClass(TTyColorListBox);
  f := TForm.CreateNew(nil);
  f2 := nil;
  ms := TMemoryStream.Create;
  try
    b := TTyColorListBox.Create(f);
    b.Name := 'Box';
    b.Parent := f;
    b.SetBounds(0, 0, 180, 150);
    b.TopIndex := 5;
    AssertEquals('precondition: the list scrolled', 5, b.TopIndex);
    ms.WriteComponent(f);
    ms.Position := 0;
    f2 := TForm.CreateNew(nil);
    ms.ReadComponent(f2);
    AssertEquals('TopIndex read back from the form file', 5,
      TTyColorListBox(f2.FindComponent('Box')).TopIndex);
  finally
    ms.Free;
    f2.Free;
    f.Free;
  end;
end;

initialization
  RegisterTest(TDeclaredDefaultsTest);
end.
