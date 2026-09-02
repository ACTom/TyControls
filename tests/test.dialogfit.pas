unit test.dialogfit;
{ ONE scanner over every dialog the library ships, at BOTH densities.

  WHY A SCANNER AND NOT SIX TESTS. The dialogs are laid out by hand, in logical pixels, with
  literal coordinates: a checkbox is given height 22 and the next row starts 26 lower, a
  button column steps by btnH + gap with nothing watching the bottom edge. Every one of those
  literals is a bet that the theme will never make a control taller -- and LCL settles that bet
  the other way, because it ENFORCES Constraints.MinHeight inside SetBounds while the STRIDE
  stays whatever was typed. So the control grows, the stride does not, and rows eat each other.
  That is one defect with many addresses; a guard with one address per site would have to be
  extended by hand every time a dialog is added, which is exactly how the existing sites got in.

  WHY DENSITY IS THE AXIS. test.skinfit and test.englishfit already sweep skins, but neither
  ever assigns Density -- so the whole modern axis was unguarded, which is how fifteen skins
  came to exceed the dialog button box without anyone noticing. Modern is where the theme grows
  most (--font-size-base 9 -> 14, --control-height 30 -> 38), so it is the axis that bites.

  WHAT IS CHECKED, AND WHAT DELIBERATELY IS NOT. Only controls with Align = alNone, because a
  form that was never shown does not run the LCL align engine (AutoSizeDelayedHandle parks the
  whole tree), so an aligned child's bounds here are not what a real window would show and any
  assertion on them would be fiction. alNone is also precisely where the hand-typed literals
  live, so the restriction costs nothing and keeps every failure real. Two questions per
  container: does each child stay inside the band it was given, and do any two children overlap. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, Dialogs, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Dialogs, tyControls.Dialogs.About, tyControls.Dialogs.Color,
  tyControls.Dialogs.Find, tyControls.Dialogs.Font, tyControls.Dialogs.FileDialog,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.ImageCollectionEditor,
  tyControls.Dialogs.TreeNodesEditor,
  tyControls.Edit, tyControls.Memo, tyControls.ListBox,
  tyControls.ImageCollection, tyControls.TreeView, tyControls.Painter;

type
  TDialogFitTest = class(TTestCase)
  private
    FTheme: string;
    FDensity: TTyDensity;
    FFont: string;
    FFailures: TStringList;
    // Record rather than Fail() on the first hit: one run should report every bad
    // dialog, not send the reader back round the loop once per site.
    procedure Note(const AMsg: string);
    procedure ScanContainer(const AWhere: string; AParent: TWinControl; const ABand: TRect);
    procedure ScanDialog(const AName: string; ADlg: TTyDialog);
    procedure SweepAt(ADensity: TTyDensity; const AThemeName, AExtraCss: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryDialogFitsAtEveryDensity;
  end;

implementation

const
  { See the long note in TestEveryDialogFitsAtEveryDensity before switching this on. }
  cSweepRoomyThemes = False;

function RectStr(const R: TRect): string;
begin
  Result := Format('(%d,%d %dx%d)', [R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top]);
end;

function NameOf(AControl: TControl): string;
begin
  Result := AControl.ClassName;
  if AControl.Name <> '' then Result := Result + '"' + AControl.Name + '"';
end;

procedure TDialogFitTest.SetUp;
begin
  TyRegisterBuiltinThemes;
  FTheme := TyDefaultController.ThemeName;
  FDensity := TyDefaultController.Density;
  { PIN THE MEASUREMENT INPUT. TyFallbackFontName is a process-wide global that the FIRST
    controller created in the process seeds from Screen.SystemFont -- so text measures one
    size when this unit runs inside the whole suite and another when it runs alone, and a
    guard whose answer depends on what ran before it is not a guard. Naming a family here
    makes every run identical and, incidentally, closer to a real app than the metric
    fallback an empty name leaves behind. }
  FFont := TyFallbackFontName;
  TyFallbackFontName := 'Arial';
  FFailures := TStringList.Create;
end;

procedure TDialogFitTest.TearDown;
begin
  TyDefaultController.Density := FDensity;
  TyDefaultController.ThemeName := FTheme;
  TyFallbackFontName := FFont;
  FreeAndNil(FFailures);
end;

procedure TDialogFitTest.Note(const AMsg: string);
begin
  FFailures.Add(AMsg);
end;

{ ABand is the usable area of AParent: for a TTyDialog that is ContentRect (the strip between
  the title bar and the action strip, which is what a builder is actually handed), for anything
  else the client rect. }
procedure TDialogFitTest.ScanContainer(const AWhere: string; AParent: TWinControl;
  const ABand: TRect);
var
  i, j: Integer;
  a, b: TControl;
  ra, rb, hit: TRect;
  sub: TRect;
begin
  for i := 0 to AParent.ControlCount - 1 do
  begin
    a := AParent.Controls[i];
    if (not a.Visible) or (a.Align <> alNone) then Continue;
    ra := a.BoundsRect;
    if (ra.Right <= ra.Left) or (ra.Bottom <= ra.Top) then Continue;   // degenerate: nothing to fit

    if ra.Bottom > ABand.Bottom then
      Note(AWhere + ': ' + NameOf(a) + ' ' + RectStr(ra)
        + ' runs past the bottom of its band ' + RectStr(ABand));
    if ra.Right > ABand.Right then
      Note(AWhere + ': ' + NameOf(a) + ' ' + RectStr(ra)
        + ' runs past the right of its band ' + RectStr(ABand));

    for j := i + 1 to AParent.ControlCount - 1 do
    begin
      b := AParent.Controls[j];
      if (not b.Visible) or (b.Align <> alNone) then Continue;
      rb := b.BoundsRect;
      if (rb.Right <= rb.Left) or (rb.Bottom <= rb.Top) then Continue;
      if IntersectRect(hit, ra, rb) then
        Note(AWhere + ': ' + NameOf(a) + ' ' + RectStr(ra) + ' overlaps '
          + NameOf(b) + ' ' + RectStr(rb));
    end;

    if a is TWinControl then
    begin
      sub := TWinControl(a).ClientRect;
      ScanContainer(AWhere + ' > ' + NameOf(a), TWinControl(a), sub);
    end;
  end;
end;

procedure TDialogFitTest.ScanDialog(const AName: string; ADlg: TTyDialog);
begin
  if ADlg = nil then Exit;
  ScanContainer(AName, ADlg, ADlg.ContentRect);
end;

procedure TDialogFitTest.SweepAt(ADensity: TTyDensity; const AThemeName, AExtraCss: string);
var
  where: string;
  ed: TTyEdit;
  mm: TTyMemo;
  lb: TTyListBox;
  items: TStringList;
  fnt: TFont;
  fams: TStringList;
  find: TTyFindForm;
  coll: TTyImageCollection;
  tree: TTyTreeView;
  d: TTyDialog;
begin
  TyDefaultController.ThemeName := AThemeName;   { REPLACE load -- also drops a previous overlay }
  TyDefaultController.Density := ADensity;
  where := AThemeName + '/' + BoolToStr(ADensity = tdModern, 'modern', 'classic');
  if AExtraCss <> '' then
  begin
    TyDefaultController.LoadThemeCssAdditive(AExtraCss);
    where := where + '/roomy';
  end;

  d := TyBuildMessageDialog('A message long enough to wrap onto a second line in this dialog.',
    mtInformation, [mbYes, mbNo, mbCancel]);
  try ScanDialog(where + ' Message', d); finally d.Free; end;

  d := TyBuildInputDialog('Input', 'Name:', 'seed', ed);
  try ScanDialog(where + ' Input', d); finally d.Free; end;

  d := TyBuildPasswordDialog('Password', 'Secret:', '*', ed);
  try ScanDialog(where + ' Password', d); finally d.Free; end;

  d := TyBuildTextDialog('Text', 'Notes:', 'seed', mm);
  try ScanDialog(where + ' Text', d); finally d.Free; end;

  items := TStringList.Create;
  try
    items.Add('One'); items.Add('Two'); items.Add('Three');
    d := TyBuildSelectValueDialog('Pick', 'Choose one:', items, 0, lb);
    try ScanDialog(where + ' SelectValue', d); finally d.Free; end;
  finally items.Free; end;

  d := TyBuildAboutDialog('About', 'App', '1.0', 'A description line.',
    'Copyright', 'MIT', 'https://example.invalid');
  try ScanDialog(where + ' About', d); finally d.Free; end;

  d := TyBuildColorDialog('Colour', TyRGB($33, $66, $99));
  try ScanDialog(where + ' Color', d); finally d.Free; end;

  { Find and Replace are the same form built two ways; the replace row shifts every
    checkbox down, so both arrangements are worth walking. }
  find := TTyFindForm.CreateNew(nil, 0);
  try find.Build(False); ScanDialog(where + ' Find', find); finally find.Free; end;
  find := TTyFindForm.CreateNew(nil, 0);
  try find.Build(True); ScanDialog(where + ' Replace', find); finally find.Free; end;

  fnt := TFont.Create;
  fams := TStringList.Create;
  try
    fams.Add('Arial'); fams.Add('Courier New'); fams.Add('Tahoma');
    d := TyBuildFontDialog('Font', fnt, fams);
    try ScanDialog(where + ' Font', d); finally d.Free; end;
  finally fams.Free; fnt.Free; end;

  d := TyBuildFileDialog(False, False, 'Open');
  try ScanDialog(where + ' FileDialog', d); finally d.Free; end;

  d := TyBuildSelectPathDialog('Folder', '');
  try ScanDialog(where + ' SelectPath', d); finally d.Free; end;

  coll := TTyImageCollection.Create(nil);
  try
    d := TyBuildImageCollectionEditor(coll);
    try ScanDialog(where + ' ImageCollectionEditor', d); finally d.Free; end;
  finally coll.Free; end;

  { The tree editor is the concrete TTyStructureEditorForm; the Cascader and ListGroups
    editors inherit the same button column, so walking one walks the shape of all three. }
  tree := TTyTreeView.Create(nil);
  try
    d := TyBuildTreeNodesEditor(tree);
    try ScanDialog(where + ' TreeNodesEditor', d); finally d.Free; end;
  finally tree.Free; end;
end;

procedure TDialogFitTest.TestEveryDialogFitsAtEveryDensity;
begin
  { 'default' is the lean baseline; 'showcase' is the roomiest built-in skin and the one whose
    button already exceeds the classic dialog box, so it is the honest worst case. }
  SweepAt(tdClassic, 'default', '');
  SweepAt(tdModern, 'default', '');
  SweepAt(tdClassic, 'showcase', '');
  SweepAt(tdModern, 'showcase', '');
  { A ROOMY pass, OFF by design -- and since the reason IS a finding, it is recorded here
    rather than left in a commit message.

    Switched on, it injects padding no shipped skin uses and surfaces ~18 further overlaps:
    every dialog that stacks a caption label above its control steps by a literal, so a theme
    that made LABELS taller would drop the control onto its own caption. That is a real
    fragility, but removing it means making the whole layer read-back-driven -- a refactor
    across five dialogs, not a fix.

    It stays off for two reasons. No built-in skin gives TyLabel any padding, so nothing the
    library ships can trigger it. And a headless runner measures text differently depending on
    what ran before it -- the process-wide fallback font and the text-measure cache are both
    seeded by whoever gets there first -- so this pass reports a different count under --all
    than it does alone. A guard whose answer moves with test order cannot gate a release. The
    shipped-skin sweeps above have neither problem: they are stable in both orders, and the
    overlap they did report (the file dialog's nav buttons at modern density) was real. }
  if cSweepRoomyThemes then
    SweepAt(tdModern, 'default',
      'TyButton, TySpeedButton, TyCheckBox, TyRadioButton, TyEdit, TyComboBox, TyLabel'
      + ' { padding: 14px; }');
  if FFailures.Count > 0 then
    Fail(IntToStr(FFailures.Count) + ' dialog layout problem(s):' + LineEnding
      + FFailures.Text);
end;

initialization
  RegisterTest(TDialogFitTest);
end.
