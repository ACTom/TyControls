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
