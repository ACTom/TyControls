unit test.dialogs.font;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, Controls, fpcunit, testregistry, tyControls.Dialogs.Font,
  tyControls.FontListBox, tyControls.SpinEdit, tyControls.CheckBox, tyControls.StrConsts;
type
  TFontMapTest = class(TTestCase)
  published
    procedure TestStyleRoundTrip;
  end;
  TFontDialogTest = class(TTestCase)
  published
    procedure TestBuildSeedsChecksAndList;
    procedure TestSeedWriteIdempotentSize;
  end;
  { The preview strip is drawn by the FORM, from the child controls' current values —
    two things that are easy to get wrong and impossible to see headlessly, so both are
    pinned here: WHAT the sample is drawn in (PreviewFamily, the single family source
    Paint uses) and WHETHER a control change ever reaches the form (PreviewChangeCount).
    Families are deliberately synthetic names no installed font can match, so a preview
    that falls back to the form's own font can't accidentally look right. }
  TFontPreviewTest = class(TTestCase)
  private
    FFont: TFont;
    FFamilies: TStringList;
    FDlg: TTyFontForm;
    procedure Build(const ASeedFamily: string);
    function List: TTyFontListBox;
    function Spin: TTySpinEdit;
    function Check(const ACaption: string): TTyCheckBox;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPreviewUsesSelectedFamily;
    procedure TestPreviewFallsBackToSeedFamily;
    procedure TestEveryInputAsksForARepaint;
  end;
implementation
procedure TFontMapTest.TestStyleRoundTrip;
var i: Integer; st, st2: TFontStyles; ch: TTyFontChecks;
begin
  for i := 0 to 15 do
  begin
    st := [];
    if (i and 1)<>0 then Include(st, fsBold);
    if (i and 2)<>0 then Include(st, fsItalic);
    if (i and 4)<>0 then Include(st, fsUnderline);
    if (i and 8)<>0 then Include(st, fsStrikeOut);
    ch := TyFontStyleToChecks(st);
    st2 := TyChecksToFontStyle(ch);
    AssertTrue('rt '+IntToStr(i), st = st2);
  end;
end;
procedure TFontDialogTest.TestBuildSeedsChecksAndList;
var f: TFont; d: TTyFontForm; fams: TStringList;
begin
  f := TFont.Create;
  fams := TStringList.Create;
  try
    f.Name := 'Courier New'; f.Size := 14; f.Style := [fsBold, fsItalic];
    fams.Add('Arial'); fams.Add('Courier New'); fams.Add('Segoe UI');
    d := TyBuildFontDialog('Font', f, fams);
    try
      AssertEquals('size seeded', 14, d.SizeValue);
      AssertTrue('bold seeded', d.BoldChecked);
      AssertTrue('italic seeded', d.ItalicChecked);
      AssertFalse('underline', d.UnderlineChecked);
      AssertEquals('family count', 3, d.FamilyCount);
      AssertEquals('family selected', 'Courier New', d.SelectedFamily);
    finally d.Free; end;
  finally f.Free; fams.Free; end;
end;

procedure TFontDialogTest.TestSeedWriteIdempotentSize;
var f: TFont; d: TTyFontForm; fams: TStringList;
begin
  fams := TStringList.Create;
  try
    fams.Add('Arial');
    // (a) default font Size=0 must survive open + OK-untouched (was silently coerced to 1)
    f := TFont.Create;
    try
      f.Size := 0;
      d := TyBuildFontDialog('F', f, fams);
      try d.WriteTo(f); finally d.Free; end;
      AssertEquals('default size preserved', 0, f.Size);
    finally f.Free; end;
    // (b) an explicit size, untouched, must survive
    f := TFont.Create;
    try
      f.Size := 14;
      d := TyBuildFontDialog('F', f, fams);
      try d.WriteTo(f); finally d.Free; end;
      AssertEquals('explicit size preserved', 14, f.Size);
    finally f.Free; end;
  finally fams.Free; end;
end;

{ TFontPreviewTest }

procedure TFontPreviewTest.SetUp;
begin
  FFont := TFont.Create;
  FFont.Size := 12;
  FFont.Style := [];
  FFamilies := TStringList.Create;
  FFamilies.Add('Zz Preview One');
  FFamilies.Add('Zz Preview Two');
end;

procedure TFontPreviewTest.TearDown;
begin
  FreeAndNil(FDlg);
  FreeAndNil(FFamilies);
  FreeAndNil(FFont);
end;

procedure TFontPreviewTest.Build(const ASeedFamily: string);
begin
  FFont.Name := ASeedFamily;
  FDlg := TyBuildFontDialog('Font', FFont, FFamilies);
end;

{ The dialog names none of its children, so reach them by class/caption rather than
  widening the public surface just for the tests. }
function TFontPreviewTest.List: TTyFontListBox;
var i: Integer;
begin
  Result := nil;
  for i := 0 to FDlg.ComponentCount - 1 do
    if FDlg.Components[i] is TTyFontListBox then Exit(TTyFontListBox(FDlg.Components[i]));
  Fail('family list not found on the dialog');
end;

function TFontPreviewTest.Spin: TTySpinEdit;
var i: Integer;
begin
  Result := nil;
  for i := 0 to FDlg.ComponentCount - 1 do
    if FDlg.Components[i] is TTySpinEdit then Exit(TTySpinEdit(FDlg.Components[i]));
  Fail('size spin not found on the dialog');
end;

function TFontPreviewTest.Check(const ACaption: string): TTyCheckBox;
var i: Integer;
begin
  Result := nil;
  for i := 0 to FDlg.ComponentCount - 1 do
    if (FDlg.Components[i] is TTyCheckBox)
    and (TTyCheckBox(FDlg.Components[i]).Caption = ACaption) then
      Exit(TTyCheckBox(FDlg.Components[i]));
  Fail('style check not found: ' + ACaption);
end;

procedure TFontPreviewTest.TestPreviewUsesSelectedFamily;
begin
  Build('Zz Preview One');
  // Paint used to hand its own Font.Name to TyConfigureTextFont, so the sample was
  // drawn in the dialog's face whatever the user picked. It must follow the list.
  AssertEquals('preview starts on the seeded family', 'Zz Preview One', FDlg.PreviewFamily);
  List.ItemIndex := 1;
  AssertEquals('preview follows the selection', 'Zz Preview Two', FDlg.PreviewFamily);
  AssertEquals('and matches what the dialog returns', 'Zz Preview Two', FDlg.SelectedFamily);
end;

procedure TFontPreviewTest.TestPreviewFallsBackToSeedFamily;
begin
  // A family that isn't in the list leaves the list unselected; WriteTo then keeps the
  // caller's name, so the preview has to show that same name and not something else.
  Build('Zz Not Installed');
  AssertEquals('list has no selection', -1, List.ItemIndex);
  AssertEquals('nothing selected', '', FDlg.SelectedFamily);
  AssertEquals('preview keeps the caller family', 'Zz Not Installed', FDlg.PreviewFamily);
  FDlg.WriteTo(FFont);
  AssertEquals('WriteTo agrees with the preview', 'Zz Not Installed', FFont.Name);
end;

procedure TFontPreviewTest.TestEveryInputAsksForARepaint;
var
  n: Integer;

  procedure Bumped(const AWhat: string);
  begin
    if FDlg.PreviewChangeCount <= n then
      Fail(AWhat + ' changed without asking the preview to repaint');
    n := FDlg.PreviewChangeCount;
  end;

begin
  Build('Zz Preview One');
  n := FDlg.PreviewChangeCount;
  List.ItemIndex := 1;
  Bumped('family');
  Spin.Value := Spin.Value + 1;
  Bumped('size');
  Check(rsDlgFontBold).Checked := not Check(rsDlgFontBold).Checked;
  Bumped('bold');
  Check(rsDlgFontItalic).Checked := not Check(rsDlgFontItalic).Checked;
  Bumped('italic');
  Check(rsDlgFontUnderline).Checked := not Check(rsDlgFontUnderline).Checked;
  Bumped('underline');
  Check(rsDlgFontStrike).Checked := not Check(rsDlgFontStrike).Checked;
  Bumped('strikeout');
end;

initialization
  RegisterTest(TFontMapTest);
  RegisterTest(TFontDialogTest);
  RegisterTest(TFontPreviewTest);
end.
