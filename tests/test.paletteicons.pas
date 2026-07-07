unit test.paletteicons;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, LResources;

type
  TPaletteIconTest = class(TTestCase)
  published
    procedure TestAllResourcesPresentAndPng;
  end;

implementation

const
  // Must stay in sync with RegisterComponents in designtime/tyControls.Design.pas and the
  // $classes list in scripts/gen-icons.ps1 (which enforces RegisterComponents <-> $classes).
  CClasses: array[0..101] of string = (
    'TTyButton',
    'TTyGlyphButton','TTyGlyphContainerButton','TTySpeedButton','TTyDropDownButton','TTyMenuButton','TTyColorButton','TTyButtonGroup',
    'TTyRibbon','TTyRibbonPage','TTyRibbonGroup','TTyRibbonAppMenu','TTyRibbonQuickAccess','TTyRibbonGallery','TTyRibbonBackstage',
    'TTyLabel','TTyEdit','TTyNumericEdit','TTyCurrencyEdit','TTyMaskEdit','TTyURLEdit','TTyComboEdit','TTyTrackEdit','TTyColorBox','TTyColorComboBox','TTyMRUComboBox','TTyComboBoxEx','TTyOfficeListBox','TTyOfficeComboBox','TTyColorGrid','TTyLColorPicker','TTyHSColorPicker','TTyAdvancedListBox','TTyAdvancedComboBox','TTyColorListBox','TTyFontComboBox','TTyFontListBox','TTyFontSizeComboBox','TTyCheckListBox','TTyCheckBox','TTyRadioButton',
    'TTyComboBox','TTyToggleSwitch','TTyTrackBar','TTyProgressBar','TTyGauge','TTyCircularProgress','TTyActivityIndicator','TTyActivityBar','TTyMeter','TTyLevelMeter','TTyDial','TTyAnalogClock','TTySparkline','TTyRating','TTyGearDial','TTyGearActivityIndicator','TTyUpDown','TTyLinkLabel','TTyShadowLabel','TTyGlowLabel','TTyListBox',
    'TTyPageControl','TTyTabSheet','TTyGroupBox','TTyPanel','TTyScrollBar','TTySpinEdit',
    'TTyMemo','TTyTitleBar','TTyMenuBar','TTyStyleController','TTyPopupMenu',
    'TTyNativeStyler','TTyHint','TTyBalloonHint',
    'TTyIconFont','TTyCharImage','TTyGlyphImageList','TTyImage','TTyImageCollection','TTyVirtualImageList',
    'TTySplitter','TTyStatusBar','TTyToolBar','TTyToolSeparator',
    'TTyCalendar','TTyDateTimePicker',
    'TTyTreeView',
    // Dialogs palette group
    'TTyMessage','TTyInputDialog','TTyPasswordDialog','TTyTextDialog',
    'TTySelectValueDialog','TTySelectPathDialog','TTyColorDialog','TTyFontDialog',
    'TTyFindDialog','TTyReplaceDialog','TTyProgressDialog','TTyAboutDialog',
    'TTyTabSet');

procedure TPaletteIconTest.TestAllResourcesPresentAndPng;
const
  // HiDPI variants: '' = 100% (24px), '_150' = 150% (36px), '_200' = 200% (48px).
  Suffixes: array[0..2] of string = ('', '_150', '_200');
var
  i, j: Integer;
  nm: string;
  res: TLResource;
begin
  for i := 0 to High(CClasses) do
    for j := 0 to High(Suffixes) do
    begin
      nm := CClasses[i] + Suffixes[j];
      res := LazarusResources.Find(nm);
      AssertNotNull('palette icon resource missing: ' + nm, res);
      AssertEquals('palette icon resource not PNG: ' + nm, 'PNG', res.ValueType);
    end;
end;

initialization
  {$I ../designtime/tycontrols_icons.lrs}
  RegisterTest(TPaletteIconTest);
end.
