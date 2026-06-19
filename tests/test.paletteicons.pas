unit test.paletteicons;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, LResources;

type
  TPaletteIconTest = class(TTestCase)
  published
    procedure TestAllTwentyResourcesPresentAndPng;
  end;

implementation

const
  // Must stay in sync with RegisterComponents in designtime/tyControls.Design.pas and the
  // $classes list in scripts/gen-icons.ps1 (which enforces RegisterComponents <-> $classes).
  CClasses: array[0..19] of string = (
    'TTyButton','TTyLabel','TTyEdit','TTyCheckBox','TTyRadioButton',
    'TTyComboBox','TTyToggleSwitch','TTyTrackBar','TTyProgressBar','TTyListBox',
    'TTyTabControl','TTyGroupBox','TTyPanel','TTyScrollBar','TTySpinEdit',
    'TTyMemo','TTyTitleBar','TTyMenuBar','TTyStyleController','TTyPopupMenu');

procedure TPaletteIconTest.TestAllTwentyResourcesPresentAndPng;
var
  i: Integer;
  res: TLResource;
begin
  for i := 0 to High(CClasses) do
  begin
    res := LazarusResources.Find(CClasses[i]);
    AssertNotNull('palette icon resource missing: ' + CClasses[i], res);
    AssertEquals('palette icon resource not PNG: ' + CClasses[i], 'PNG', res.ValueType);
  end;
end;

initialization
  {$I ../designtime/tycontrols_icons.lrs}
  RegisterTest(TPaletteIconTest);
end.
