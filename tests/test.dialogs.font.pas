unit test.dialogs.font;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, Controls, Forms, StdCtrls, Dialogs, fpcunit, testregistry,
  tyControls.Dialogs.Font, tyControls.FontListBox, tyControls.FontFamilies,
  tyControls.SpinEdit, tyControls.CheckBox, tyControls.Button, tyControls.StrConsts,
  test.fontfamilies;
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
  { LCL's TFontDialogOptions on TTyFontDialog (#28), through BuildForm -- the form Execute
    shows, never shown here. }
  TFontDialogOptionsTest = class(TTestCase)
  private
    FDlg: TTyFontDialog;
    FForm: TTyFontForm;
    FAppliedSize: Integer;
    FApplied: Boolean;
    procedure HandleApply(Sender: TObject);
    procedure Build(AOptions: TFontDialogOptions);
    function Box(const ACaption: string): TTyCheckBox;
    function Spin: TTySpinEdit;
    function List: TTyFontListBox;
    function FindButton(const ACaption: string): TTyButton;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaultsKeepTheOldDialog;
    procedure TestNewPropertiesAreNotWrittenAtTheirDefaults;
    procedure TestFixedPitchOnlyListsTheSystemsFixedFamilies;
    procedure TestScalableOnlyDropsBitmapFonts;
    procedure TestLimitSizeClampsTheSize;
    procedure TestLimitSizeOnADefaultSize;
    procedure TestLimitsCountOnlyUnderLimitSize;
    procedure TestNoSizeSelLeavesTheSizeAlone;
    procedure TestNoFaceSelLeavesTheFamilyAlone;
    procedure TestNoStyleSelLeavesTheStylesAlone;
    procedure TestWithoutEffectsTheEffectsStay;
    procedure TestApplyButtonWritesTheFontAndFires;
    procedure TestPreviewText;
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

{ TFontDialogOptionsTest }

procedure TFontDialogOptionsTest.SetUp;
begin
  FDlg := TTyFontDialog.Create(nil);
  FDlg.Font.Name := 'Zz Not Installed';
  FDlg.Font.Size := 14;
  FDlg.Font.Style := [];
  FDlg.OnApplyClicked := @HandleApply;
  FApplied := False;
end;

procedure TFontDialogOptionsTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FDlg);
end;

procedure TFontDialogOptionsTest.HandleApply(Sender: TObject);
begin
  FApplied := Sender = FDlg;
  FAppliedSize := FDlg.Font.Size;   // what the program sees when the event fires
end;

procedure TFontDialogOptionsTest.Build(AOptions: TFontDialogOptions);
begin
  FreeAndNil(FForm);
  FDlg.Options := AOptions;
  FForm := FDlg.BuildForm;
end;

function TFontDialogOptionsTest.Box(const ACaption: string): TTyCheckBox;
var i: Integer;
begin
  for i := 0 to FForm.ComponentCount - 1 do
    if (FForm.Components[i] is TTyCheckBox)
    and (TTyCheckBox(FForm.Components[i]).Caption = ACaption) then
      Exit(TTyCheckBox(FForm.Components[i]));
  Fail('check box not found: ' + ACaption);
  Result := nil;
end;

function TFontDialogOptionsTest.Spin: TTySpinEdit;
var i: Integer;
begin
  for i := 0 to FForm.ComponentCount - 1 do
    if FForm.Components[i] is TTySpinEdit then Exit(TTySpinEdit(FForm.Components[i]));
  Fail('size spin not found');
  Result := nil;
end;

function TFontDialogOptionsTest.List: TTyFontListBox;
var i: Integer;
begin
  for i := 0 to FForm.ComponentCount - 1 do
    if FForm.Components[i] is TTyFontListBox then Exit(TTyFontListBox(FForm.Components[i]));
  Fail('family list not found');
  Result := nil;
end;

function TFontDialogOptionsTest.FindButton(const ACaption: string): TTyButton;
var i: Integer;
begin
  Result := nil;
  for i := 0 to FForm.ComponentCount - 1 do
    if (FForm.Components[i] is TTyButton)
    and (TTyButton(FForm.Components[i]).Caption = ACaption) then
      Exit(TTyButton(FForm.Components[i]));
end;

function FontsWithoutVerticalVariantsCount: Integer;
var L: TStringList;
begin
  L := TStringList.Create;
  try FontsWithoutVerticalVariants(L); Result := L.Count; finally L.Free; end;
end;

procedure TFontDialogOptionsTest.TestDefaultsKeepTheOldDialog;
begin
  AssertTrue('Options default to LCL''s [fdEffects]', FDlg.Options = [fdEffects]);
  AssertEquals('MinFontSize', 0, FDlg.MinFontSize);
  AssertEquals('MaxFontSize', 0, FDlg.MaxFontSize);
  AssertEquals('PreviewText', '', FDlg.PreviewText);
  Build(FDlg.Options);
  AssertEquals('every installed family but the vertical "@" variants',
    FontsWithoutVerticalVariantsCount, FForm.FamilyCount);
  AssertTrue('underline shows', Box(rsDlgFontUnderline).Visible);
  AssertTrue('strikeout shows', Box(rsDlgFontStrike).Visible);
  AssertTrue('colour shows', FindButton(rsDlgFontColor).Visible);
  AssertTrue('no Apply button', FindButton(rsDlgFontApply) = nil);
  AssertEquals('OK and Cancel only', 2, FForm.ButtonCount);
  AssertEquals('the size is there', 14, FForm.SizeValue);
  AssertFalse('and not blank', Spin.ValueEmpty);
  AssertEquals('the sample text', rsDlgFontSample, FForm.SampleText);
end;

procedure TFontDialogOptionsTest.TestNewPropertiesAreNotWrittenAtTheirDefaults;
var src: TForm; ms, ts: TMemoryStream; L: TStringList; d: TTyFontDialog;
begin
  src := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    d := TTyFontDialog.Create(src);
    d.Name := 'D';
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    AssertEquals('Options', 0, Pos('Options', L.Text));
    AssertEquals('MinFontSize', 0, Pos('MinFontSize', L.Text));
    AssertEquals('MaxFontSize', 0, Pos('MaxFontSize', L.Text));
    AssertEquals('PreviewText', 0, Pos('PreviewText', L.Text));
  finally
    L.Free; ts.Free; ms.Free; src.Free;
  end;
end;

procedure TFontDialogOptionsTest.TestFixedPitchOnlyListsTheSystemsFixedFamilies;
var fixed: TStringList;
begin
  if (Screen.Fonts.IndexOf('Courier New') < 0) or (Screen.Fonts.IndexOf('Arial') < 0) then
    Ignore('needs Courier New and Arial installed');
  fixed := TStringList.Create;
  try
    TyGetFontFamilies(fixed, True);
    Build([fdEffects, fdFixedPitchOnly]);
    AssertEquals('the fixed-pitch families', fixed.Count, FForm.FamilyCount);
    AssertTrue('Courier New listed', List.Items.IndexOf('Courier New') >= 0);
    AssertTrue('Arial not listed', List.Items.IndexOf('Arial') < 0);
  finally fixed.Free; end;
end;

procedure TFontDialogOptionsTest.TestScalableOnlyDropsBitmapFonts;
begin
  if Screen.Fonts.IndexOf('Fixedsys') < 0 then Ignore('needs the bitmap Fixedsys (Windows)');
  Build([fdEffects, fdScalableOnly]);
  AssertTrue('Fixedsys is a bitmap font', List.Items.IndexOf('Fixedsys') < 0);
  AssertTrue('a filter, not the whole list', FForm.FamilyCount < Screen.Fonts.Count);
end;

procedure TFontDialogOptionsTest.TestLimitSizeClampsTheSize;
var f: TFont;
begin
  FDlg.MinFontSize := 8;
  FDlg.MaxFontSize := 12;
  FDlg.Font.Size := 20;
  Build([fdEffects, fdLimitSize]);
  AssertEquals('shown clamped to the top', 12, FForm.SizeValue);
  f := TFont.Create;
  try
    f.Size := 20;
    FForm.WriteTo(f);
    AssertEquals('an out-of-range size is written back clamped', 12, f.Size);
  finally f.Free; end;
  FDlg.Font.Size := 10;
  Build([fdEffects, fdLimitSize]);
  f := TFont.Create;
  try
    f.Size := 10;
    FForm.WriteTo(f);
    AssertEquals('an in-range size, untouched, stays', 10, f.Size);
    Spin.Value := 3;   // below the limit: the spin clamps it
    FForm.WriteTo(f);
    AssertEquals('the user cannot go below MinFontSize', 8, f.Size);
  finally f.Free; end;
end;

procedure TFontDialogOptionsTest.TestLimitSizeOnADefaultSize;
var f: TFont;
begin
  { Size 0 ("the default") is shown as 9. Limits that leave the 9 alone keep the 0; limits that
    move it make the moved value the answer -- a 0 would be outside them. }
  FDlg.MinFontSize := 8;
  FDlg.MaxFontSize := 12;
  FDlg.Font.Size := 0;
  Build([fdEffects, fdLimitSize]);
  AssertEquals('the default is shown as 9', 9, FForm.SizeValue);
  f := TFont.Create;
  try
    f.Size := 0;
    FForm.WriteTo(f);
    AssertEquals('9 is inside 8..12: the default stays the default', 0, f.Size);
  finally f.Free; end;
  FDlg.MinFontSize := 10;
  Build([fdEffects, fdLimitSize]);
  AssertEquals('shown clamped to the bottom', 10, FForm.SizeValue);
  f := TFont.Create;
  try
    f.Size := 0;
    FForm.WriteTo(f);
    AssertEquals('9 is below 10: the clamped size is written', 10, f.Size);
  finally f.Free; end;
end;

procedure TFontDialogOptionsTest.TestLimitsCountOnlyUnderLimitSize;
var f: TFont;
begin
  FDlg.MinFontSize := 8;
  FDlg.MaxFontSize := 12;
  FDlg.Font.Size := 20;
  Build([fdEffects]);
  AssertEquals('no fdLimitSize: the limits are ignored', 20, FForm.SizeValue);
  f := TFont.Create;
  try
    f.Size := 20;
    FForm.WriteTo(f);
    AssertEquals('and the size comes back as it was', 20, f.Size);
  finally f.Free; end;
end;

procedure TFontDialogOptionsTest.TestNoSizeSelLeavesTheSizeAlone;
begin
  Build([fdEffects, fdNoSizeSel]);
  AssertTrue('the size box is blank', Spin.ValueEmpty);
  FForm.WriteTo(FDlg.Font);
  AssertEquals('untouched: the size stays', 14, FDlg.Font.Size);
  Spin.Value := 16;
  FForm.WriteTo(FDlg.Font);
  AssertEquals('typed: the new size', 16, FDlg.Font.Size);
end;

procedure TFontDialogOptionsTest.TestNoFaceSelLeavesTheFamilyAlone;
begin
  Build([fdEffects]);
  FDlg.Font.Name := List.Items[0];
  Build([fdEffects]);
  AssertEquals('setup: normally the family is preselected', List.Items[0], FForm.SelectedFamily);
  Build([fdEffects, fdNoFaceSel]);
  AssertEquals('no preselection', -1, List.ItemIndex);
  FDlg.Font.Name := 'Zz Kept';
  FForm.WriteTo(FDlg.Font);
  AssertEquals('untouched: the family stays', 'Zz Kept', FDlg.Font.Name);
end;

procedure TFontDialogOptionsTest.TestNoStyleSelLeavesTheStylesAlone;
begin
  FDlg.Font.Style := [fsBold];
  Build([fdEffects, fdNoStyleSel]);
  AssertTrue('bold is grey', Box(rsDlgFontBold).State = cbGrayed);
  AssertTrue('italic is grey', Box(rsDlgFontItalic).State = cbGrayed);
  AssertTrue('underline is an effect, not a style', Box(rsDlgFontUnderline).State = cbUnchecked);
  FForm.WriteTo(FDlg.Font);
  AssertTrue('untouched: bold stays, italic stays off', FDlg.Font.Style = [fsBold]);
  FDlg.Font.Style := [fsItalic];
  FForm.WriteTo(FDlg.Font);
  AssertTrue('grey keeps whatever the font has', FDlg.Font.Style = [fsItalic]);
  Box(rsDlgFontBold).Click;   // grey -> checked
  FForm.WriteTo(FDlg.Font);
  AssertTrue('clicked on: bold', fsBold in FDlg.Font.Style);
  Box(rsDlgFontBold).Click;   // checked -> unchecked
  FForm.WriteTo(FDlg.Font);
  AssertFalse('clicked off: no bold', fsBold in FDlg.Font.Style);
end;

procedure TFontDialogOptionsTest.TestWithoutEffectsTheEffectsStay;
begin
  FDlg.Font.Style := [fsUnderline];
  FDlg.Font.Color := clRed;
  Build([]);
  AssertFalse('underline hidden', Box(rsDlgFontUnderline).Visible);
  AssertFalse('strikeout hidden', Box(rsDlgFontStrike).Visible);
  AssertFalse('colour hidden', FindButton(rsDlgFontColor).Visible);
  Box(rsDlgFontUnderline).Checked := False;   // a hidden box the user cannot have touched
  Box(rsDlgFontStrike).Checked := True;
  FForm.WriteTo(FDlg.Font);
  AssertTrue('underline and strikeout are the font''s own', FDlg.Font.Style = [fsUnderline]);
  AssertEquals('colour', clRed, FDlg.Font.Color);
end;

procedure TFontDialogOptionsTest.TestApplyButtonWritesTheFontAndFires;
var apply: TTyButton;
begin
  Build([fdEffects]);
  AssertTrue('no Apply without fdApplyButton', FindButton(rsDlgFontApply) = nil);
  Build([fdEffects, fdApplyButton]);
  apply := FindButton(rsDlgFontApply);
  AssertTrue('fdApplyButton adds Apply', apply <> nil);
  AssertTrue('on the button bar', apply.Visible);
  Spin.Value := 20;
  apply.Click;
  AssertTrue('OnApplyClicked fired, Sender = the component', FApplied);
  AssertEquals('Font already held the choice when it fired', 20, FAppliedSize);
  AssertEquals('Apply does not close the dialog', Ord(mrNone), Ord(FForm.ModalResult));
end;

procedure TFontDialogOptionsTest.TestPreviewText;
begin
  FDlg.PreviewText := 'Hello 0Oo1lI';
  Build([fdEffects]);
  AssertEquals('PreviewText is the sample', 'Hello 0Oo1lI', FForm.SampleText);
  FDlg.PreviewText := '';
  Build([fdEffects]);
  AssertEquals('empty -> the built-in sample', rsDlgFontSample, FForm.SampleText);
end;

initialization
  RegisterTest(TFontDialogOptionsTest);
  RegisterTest(TFontMapTest);
  RegisterTest(TFontDialogTest);
  RegisterTest(TFontPreviewTest);
end.
