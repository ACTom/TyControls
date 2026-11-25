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
  container: does each child stay inside the band it was given, and do any two children overlap.

  AND THE SAME AGAIN AT 175%. The literals are 96-PPI numbers and a dialog is built after LCL
  has taken its form to the monitor's PPI, so each of them is scaled where it is used
  (TTyDialog.Px) -- each of them, which is the kind of promise one forgotten literal breaks.
  A row given 22 px at a scaling where its control's floor is 39 is this unit's defect exactly,
  so the second sweep asks the same two questions on a simulated 168-PPI desktop
  (ACTom/TyControls#2). tests/test.dpi.dialogs asks the other one, whether the dialog is its
  96-PPI self times 1.75.

  AND A THIRD QUESTION, ACROSS: IS EACH CONTROL AS WIDE AS WHAT IT SHOWS (#248). The same bet
  was made on widths -- a label given 64 px, a view box 120, a colour channel 56 -- and lost
  the same way at modern density, where --font-size-base is 14 instead of 9: "File name:" lost
  its end, "Large icons" its last letters, and 255 read as 55. Height failures show as
  overlaps, which the two questions above find; a width that is too small overlaps nothing,
  it just cuts what the control shows, so it needs asking for itself. A label, a check box
  and a button are asked for their preferred width; a pick-only combo and a spin edit for
  the width their longest item or number needs (FieldWidthFor, itself held to the pixels by
  tests/test.fieldwidth). Only a plain TTyComboBox is asked: the paths in a look-in box and
  the filters an application supplies are not the library's words and can be any length. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, Dialogs, fpcunit, testregistry,
  test.dpi.support,
  tyControls.Types, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Dialogs, tyControls.Dialogs.About, tyControls.Dialogs.Color,
  tyControls.Dialogs.Find, tyControls.Dialogs.Font, tyControls.Dialogs.FileDialog,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.ImageCollectionEditor,
  tyControls.Dialogs.TreeNodesEditor,
  tyControls.Edit, tyControls.Memo, tyControls.ListBox,
  tyControls.ImageCollection, tyControls.TreeView, tyControls.Painter,
  tyControls.TyLabel, tyControls.CheckBox, tyControls.Button, tyControls.ComboBox,
  tyControls.SpinEdit, tyControls.StrConsts;

type
  TDialogFitTest = class(TTestCase)
  private
    FTheme: string;
    FDensity: TTyDensity;
    FFont: string;
    FFailures: TStringList;
    FCut: TStringList;    // #248: what is wider than the control that shows it
    // Record rather than Fail() on the first hit: one run should report every bad
    // dialog, not send the reader back round the loop once per site.
    procedure Note(const AMsg: string);
    procedure ScanContainer(const AWhere: string; AParent: TWinControl; const ABand: TRect);
    procedure ScanCaptions(const AWhere: string; AParent: TWinControl);
    { The first visible unaligned child of AParent of exactly AClass -- and, when ACaption
      is given, with that caption. }
    function Child(AParent: TWinControl; AClass: TClass; const ACaption: string = ''): TControl;
    procedure UseDefaultTheme(ADensity: TTyDensity);
    procedure ScanDialog(const AName: string; ADlg: TTyDialog);
    procedure SweepAt(ADensity: TTyDensity; const AThemeName, AExtraCss: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryDialogFitsAtEveryDensity;
    procedure TestEveryDialogFitsAt175Percent;
    procedure TestNothingADialogShowsIsCutAtEitherDensity;
    procedure TestNothingADialogShowsIsCutAt175Percent;
    procedure TestAtClassicDensityTheDesignedWidthsStand;
    procedure TestTheButtonsOfAStructureEditorShareOneColumn;
    procedure TestWithALargerFontEachCaptionGetsItsOwnWidth;
  end;

implementation

const
  { See the long note in TestEveryDialogFitsAtEveryDensity before switching this on. }
  cSweepRoomyThemes = False;

type
  TCtlAcc = class(TControl);
  TComboAcc = class(TTyComboBox);
  TSpinAcc = class(TTySpinEdit);

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
  FCut := TStringList.Create;
end;

procedure TDialogFitTest.TearDown;
begin
  UseDefaultTheme(FDensity);   { drops whatever a test loaded on top of the theme }
  TyDefaultController.ThemeName := FTheme;
  TyFallbackFontName := FFont;
  FreeAndNil(FFailures);
  FreeAndNil(FCut);
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

{ The same walk as ScanContainer -- visible, unaligned, and into the containers among them --
  asking each control whether what it shows fits across it. }
procedure TDialogFitTest.ScanCaptions(const AWhere: string; AParent: TWinControl);
var
  i, j, pw, ph: Integer;
  a: TControl;
  sp: TTySpinEdit;

  procedure Ask(const AShown: string; ANeed: Integer);
  begin
    if ANeed > a.Width then
      FCut.Add(Format('%s: %s is %d wide and "%s" needs %d',
        [AWhere, NameOf(a), a.Width, AShown, ANeed]));
  end;

begin
  for i := 0 to AParent.ControlCount - 1 do
  begin
    a := AParent.Controls[i];
    if (not a.Visible) or (a.Align <> alNone) then Continue;
    if ((a is TTyLabel) and not TTyLabel(a).WordWrap) or (a is TTyCheckBox)
       or (a is TTyRadioButton) or (a is TTyButton) then
    begin
      pw := 0; ph := 0;
      a.GetPreferredSize(pw, ph, True);
      Ask(TCtlAcc(a).Caption, pw);
    end
    else if (a.ClassType = TTyComboBox) and not TyComboStyleHasEditBox(TTyComboBox(a).Style) then
    begin
      for j := 0 to TTyComboBox(a).Items.Count - 1 do
        Ask(TTyComboBox(a).Items[j], TComboAcc(a).FieldWidthFor(TTyComboBox(a).Items[j]));
    end
    else if a is TTySpinEdit then
    begin
      sp := TTySpinEdit(a);
      Ask(sp.Text, TSpinAcc(sp).FieldWidthFor(sp.Text));
      if sp.MaxValue > sp.MinValue then   { a range: both of its ends have to fit }
      begin
        Ask(sp.ValueToStr(sp.MaxValue), TSpinAcc(sp).FieldWidthFor(sp.ValueToStr(sp.MaxValue)));
        Ask(sp.ValueToStr(sp.MinValue), TSpinAcc(sp).FieldWidthFor(sp.ValueToStr(sp.MinValue)));
      end;
    end;
    if a is TWinControl then
      ScanCaptions(AWhere + ' > ' + NameOf(a), TWinControl(a));
  end;
end;

function TDialogFitTest.Child(AParent: TWinControl; AClass: TClass;
  const ACaption: string): TControl;
var
  i: Integer;
  a: TControl;
begin
  Result := nil;
  for i := 0 to AParent.ControlCount - 1 do
  begin
    a := AParent.Controls[i];
    if a.Visible and (a.Align = alNone) and (a.ClassType = AClass)
       and ((ACaption = '') or (TCtlAcc(a).Caption = ACaption)) then Exit(a);
  end;
  Fail('no ' + AClass.ClassName + ' "' + ACaption + '" in ' + AParent.ClassName);
end;

procedure TDialogFitTest.UseDefaultTheme(ADensity: TTyDensity);
begin
  { By way of another theme: a controller that is given the name it already has does
    nothing, and the rules a test added on top (LoadThemeCssAdditive) would stay loaded --
    for this test and for every one that runs after it. }
  TyDefaultController.ThemeName := 'showcase';
  TyDefaultController.ThemeName := 'default';
  TyDefaultController.Density := ADensity;
end;

procedure TDialogFitTest.ScanDialog(const AName: string; ADlg: TTyDialog);
begin
  if ADlg = nil then Exit;
  ScanContainer(AName, ADlg, ADlg.ContentRect);
  ScanCaptions(AName, ADlg);
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

procedure TDialogFitTest.TestEveryDialogFitsAt175Percent;
var
  saveScreen: Integer;
  saveScaled: Boolean;
begin
  saveScreen := TyTestScreenPPI;
  saveScaled := Application.Scaled;
  { Not a scaled application: a form then keeps the PPI it was born with, which is the
    simulated screen's -- the state a real dialog is in when its builder starts placing
    controls, LCL's pass over the empty form being behind it. }
  Application.Scaled := False;
  TyTestSimulateScreen(168);
  try
    SweepAt(tdClassic, 'default', '');
    SweepAt(tdModern, 'default', '');
    SweepAt(tdClassic, 'showcase', '');
    SweepAt(tdModern, 'showcase', '');
  finally
    TyTestSimulateScreen(saveScreen);
    Application.Scaled := saveScaled;
  end;
  if FFailures.Count > 0 then
    Fail(IntToStr(FFailures.Count) + ' dialog layout problem(s) at 168 PPI:' + LineEnding
      + FFailures.Text);
end;

procedure TDialogFitTest.TestNothingADialogShowsIsCutAtEitherDensity;
begin
  SweepAt(tdClassic, 'default', '');
  SweepAt(tdModern, 'default', '');
  SweepAt(tdClassic, 'showcase', '');
  SweepAt(tdModern, 'showcase', '');
  if FCut.Count > 0 then
    Fail(IntToStr(FCut.Count) + ' text(s) wider than the control that shows them:' + LineEnding
      + FCut.Text);
end;

procedure TDialogFitTest.TestNothingADialogShowsIsCutAt175Percent;
var
  saveScreen: Integer;
  saveScaled: Boolean;
begin
  saveScreen := TyTestScreenPPI;
  saveScaled := Application.Scaled;
  Application.Scaled := False;   { as TestEveryDialogFitsAt175Percent, and for its reason }
  TyTestSimulateScreen(168);
  try
    SweepAt(tdClassic, 'default', '');
    SweepAt(tdModern, 'default', '');
    SweepAt(tdClassic, 'showcase', '');
    SweepAt(tdModern, 'showcase', '');
  finally
    TyTestSimulateScreen(saveScreen);
    Application.Scaled := saveScaled;
  end;
  if FCut.Count > 0 then
    Fail(IntToStr(FCut.Count) + ' text(s) wider than the control that shows them at 168 PPI:'
      + LineEnding + FCut.Text);
end;

{ The other half of #248: a width follows what is shown only where the designed number is
  too small. At classic density, with the default theme, every one of them is big enough,
  so each control is exactly as wide as it always was -- the dialogs an application shows
  today do not move by a pixel. }
procedure TDialogFitTest.TestAtClassicDensityTheDesignedWidthsStand;
var
  d: TTyDialog;
  find: TTyFindForm;
  tree: TTyTreeView;
  lbl: TControl;
  i, n: Integer;
begin
  UseDefaultTheme(tdClassic);

  d := TyBuildFileDialog(False, False, 'Open');
  try
    AssertEquals('file dialog: the File name label', 64, Child(d, TTyLabel, rsFdFileNameLbl).Width);
    AssertEquals('file dialog: the File type label', 64, Child(d, TTyLabel, rsFdFileTypeLbl).Width);
    AssertEquals('file dialog: the view box', 120, Child(d, TTyComboBox).Width);
  finally d.Free; end;

  find := TTyFindForm.CreateNew(nil, 0);
  try
    find.Build(True);
    lbl := Child(find, TTyLabel, rsDlgReplaceWith);
    AssertEquals('replace dialog: the Replace with label', 96, lbl.Width);
    n := 0;
    for i := 0 to find.ControlCount - 1 do
      if find.Controls[i] is TTyEdit then
      begin
        Inc(n);
        AssertEquals('replace dialog: an edit box starts 100 px after its label starts',
          lbl.Left + 100, find.Controls[i].Left);
      end;
    AssertEquals('replace dialog: precondition -- two edit boxes were looked at', 2, n);
  finally find.Free; end;

  { A channel box holds three digits, and with the family pinned here they need 57 px at the
    classic font -- one more than the designed 56, which the box now gives them. What is
    asked here is the other side, that 56 stands when it is enough: so the boxes get a font
    at which it is. }
  TyDefaultController.LoadThemeCssAdditive('TySpinEdit { font-size: 7px; }');
  d := TyBuildColorDialog('Colour', TyRGB($33, $66, $99));
  try
    n := 0;
    for i := 0 to d.ControlCount - 1 do
      if d.Controls[i] is TTySpinEdit then
      begin
        Inc(n);
        AssertEquals('colour dialog: a channel box', 56, d.Controls[i].Width);
      end;
    AssertEquals('colour dialog: precondition -- R G B, C M Y K and alpha were looked at', 8, n);
    AssertEquals('colour dialog: the label of a channel', 14, Child(d, TTyLabel, 'M').Width);
  finally d.Free; end;
  UseDefaultTheme(tdClassic);   { the overlay off again }

  tree := TTyTreeView.Create(nil);
  try
    d := TyBuildTreeNodesEditor(tree);
    try
      n := 0;
      for i := 0 to d.ControlCount - 1 do
        if (d.Controls[i] is TTyButton) and (d.Controls[i].Align = alNone) then
        begin
          Inc(n);
          AssertEquals('structure editor: a button of the column', 120, d.Controls[i].Width);
        end;
      AssertTrue('structure editor: precondition -- the column has buttons', n >= 3);
    finally d.Free; end;
  finally tree.Free; end;
end;

{ At modern density "Move Down" needs more than the 120 px of the column. LCL raised that
  one button to its own floor, so it stood 10 px wider than the four above it and reached
  into the dialog's right margin. The column is as wide as its widest button needs, all of
  them are that wide, and the margin right of it is the one left of the tree.

  How much a caption needs is the font's to say, and with the family this unit pins the
  captions still fit at 14 px; the larger font here is what makes the widest of them need
  more than the column on any machine. }
procedure TDialogFitTest.TestTheButtonsOfAStructureEditorShareOneColumn;
var
  d: TTyDialog;
  tree, view: TTyTreeView;
  first, b: TControl;
  i, n, margin: Integer;
begin
  UseDefaultTheme(tdModern);
  TyDefaultController.LoadThemeCssAdditive('TyButton { font-size: 22px; }');
  tree := TTyTreeView.Create(nil);
  try
    d := TyBuildTreeNodesEditor(tree);
    try
      view := Child(d, TTyTreeView) as TTyTreeView;
      margin := view.Left - d.ContentRect.Left;
      first := nil;
      n := 0;
      for i := 0 to d.ControlCount - 1 do
      begin
        b := d.Controls[i];
        if not ((b is TTyButton) and (b.Align = alNone)) then Continue;
        Inc(n);
        if first = nil then first := b;
        AssertEquals('"' + TCtlAcc(b).Caption + '" starts where the first button starts',
          first.Left, b.Left);
        AssertEquals('"' + TCtlAcc(b).Caption + '" is as wide as the first button',
          first.Width, b.Width);
        AssertEquals('"' + TCtlAcc(b).Caption + '" ends one margin short of the dialog''s edge',
          d.ContentRect.Right - margin, b.Left + b.Width);
        AssertTrue('"' + TCtlAcc(b).Caption + '" starts right of the tree',
          b.Left > view.Left + view.Width);
      end;
      AssertTrue('precondition: the column has buttons', n >= 3);
      AssertTrue('precondition: at this font the column is wider than the 120 px it was typed as',
        first.Width > 120);
    finally d.Free; end;
  finally tree.Free; end;
end;

{ Which caption a width is taken from. At the font this unit pins and at modern density the
  shorter captions still fit their floors -- "Find what:" in 96 px, "File type:" in what
  "File name:" needs -- so a layout that measured the wrong label, or only one of two, would
  cut nothing here and would on the first translation that is longer. With the label font
  this large every caption needs more than its floor, and no two the same. }
procedure TDialogFitTest.TestWithALargerFontEachCaptionGetsItsOwnWidth;
var
  d: TTyDialog;
  find: TTyFindForm;
  a, b: TControl;
  i, n: Integer;

  function Need(C: TControl): Integer;
  var
    w, h: Integer;
  begin
    w := 0; h := 0;
    C.GetPreferredSize(w, h, True);
    Result := w;
  end;

begin
  UseDefaultTheme(tdClassic);
  TyDefaultController.LoadThemeCssAdditive('TyLabel { font-size: 20px; }');

  d := TyBuildFileDialog(False, False, 'Open');
  try
    a := Child(d, TTyLabel, rsFdFileNameLbl);
    b := Child(d, TTyLabel, rsFdFileTypeLbl);
    AssertTrue('precondition: both captions need more than their 64 px floor, and not the same',
      (Need(a) > 64) and (Need(b) > 64) and (Need(a) <> Need(b)));
    AssertEquals('file dialog: the File name label is as wide as its own caption needs',
      Need(a), a.Width);
    AssertEquals('file dialog: the File type label is as wide as its own caption needs',
      Need(b), b.Width);
  finally d.Free; end;

  find := TTyFindForm.CreateNew(nil, 0);
  try
    find.Build(False);
    a := Child(find, TTyLabel, rsDlgFindWhat);
    AssertTrue('precondition: the find caption needs more than its 96 px floor', Need(a) > 96);
    AssertEquals('find dialog: its one caption is as wide as it needs', Need(a), a.Width);
    n := 0;
    for i := 0 to find.ControlCount - 1 do
      if find.Controls[i] is TTyEdit then
      begin
        Inc(n);
        AssertEquals('find dialog: the edit box starts 4 px after the caption ends',
          a.Left + a.Width + 4, find.Controls[i].Left);
      end;
    AssertEquals('find dialog: precondition -- one edit box was looked at', 1, n);
  finally find.Free; end;

  find := TTyFindForm.CreateNew(nil, 0);
  try
    find.Build(True);
    a := Child(find, TTyLabel, rsDlgFindWhat);
    b := Child(find, TTyLabel, rsDlgReplaceWith);
    AssertTrue('precondition: the replace caption is the longer of the two', Need(b) > Need(a));
    AssertEquals('replace dialog: the two captions share a column as wide as the longer needs',
      Need(b), a.Width);
    AssertEquals('replace dialog: and the longer one has that width too', Need(b), b.Width);
    n := 0;
    for i := 0 to find.ControlCount - 1 do
      if find.Controls[i] is TTyEdit then
      begin
        Inc(n);
        AssertEquals('replace dialog: an edit box starts 4 px after the column ends',
          a.Left + Need(b) + 4, find.Controls[i].Left);
      end;
    AssertEquals('replace dialog: precondition -- two edit boxes were looked at', 2, n);
  finally find.Free; end;

  UseDefaultTheme(tdClassic);   { the larger font off again }
end;

initialization
  RegisterTest(TDialogFitTest);
end.
