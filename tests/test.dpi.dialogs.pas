unit test.dpi.dialogs;
{ The built-in dialogs at a scaling other than 100%.             (ACTom/TyControls#2)

  A dialog is laid out by CODE, from numbers written for 96 PPI, and it is laid out AFTER
  its form was constructed -- by which time LCL has taken the still empty form to the
  monitor's PPI (TCustomForm.AfterConstruction). So no DPI pass ever sees those numbers.
  Used raw, they gave a dialog whose text and buttons were 1.75x larger at 175% inside
  margins, columns and gaps that had stayed at 100%: a message wrapped into a column half
  as wide as it looked at 96, a colour picker a little more than half its designed size.

  Every layout number in a dialog now goes through TTyDialog.Px. What is asserted here is
  the consequence, for each dialog in turn: built on a 168-PPI desktop, every control in it
  is where -- and as large as -- its 96-PPI twin, times 1.75.

  THE SCREEN IS SIMULATED (test.dpi.support). This runner is not a scaled application, so a
  form keeps the PPI its font was born with, and that comes from the screen: a dialog built
  under a simulated 168 is a dialog at 168, exactly as one built after LCL's pass is.

  THE TOLERANCE is 8%, or 6 px for the small numbers. A box fitted to measured text is not
  exactly proportional to the PPI: glyphs are hinted to whole pixels, so Arial is 15 px a
  line at 12 px and 24 at 21, which is 1.6 times and not 1.75 -- five pixels over the two
  lines of a message. The defect this guards against is out by 43%.

  ONLY WHAT IS SHOWN is compared. A list box makes itself a scroll bar the moment its rows
  do not fit and keeps it, hidden, once they do; at 168 PPI that moment comes while the
  list still has the size it was born with. The control is there and nobody can see it. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Forms, Graphics, Dialogs, LCLType,
  fpcunit, testregistry,
  test.dpi.support,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.Edit, tyControls.Memo, tyControls.ListBox, tyControls.TreeView,
  tyControls.ImageCollection,
  tyControls.Dialogs, tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress, tyControls.Dialogs.About,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.FileDialog,
  tyControls.Dialogs.IconBrowser, tyControls.Dialogs.ImageCollectionEditor,
  tyControls.Dialogs.TreeNodesEditor;

type
  TDialogBuilder = function: TTyDialog of object;

  TTyDialogDpiTest = class(TTestCase)
  private
    FSaveScreen: Integer;
    FSaveScaled: Boolean;
    FSaveFontName: string;
    FFont: TFont;
    FImages: TTyImageCollection;
    FTree: TTyTreeView;
    function Tree(ABuilder: TDialogBuilder; APPI: Integer): TStringList;
    procedure CheckScales(const AName: string; ABuilder: TDialogBuilder);
    function BuildMessage: TTyDialog;
    function BuildInput: TTyDialog;
    function BuildPassword: TTyDialog;
    function BuildText: TTyDialog;
    function BuildSelectValue: TTyDialog;
    function BuildColor: TTyDialog;
    function BuildFont: TTyDialog;
    function BuildFind: TTyDialog;
    function BuildReplace: TTyDialog;
    function BuildProgress: TTyDialog;
    function BuildAbout: TTyDialog;
    function BuildSelectPath: TTyDialog;
    function BuildOpen: TTyDialog;
    function BuildOpenWithPreview: TTyDialog;
    function BuildIconBrowser: TTyDialog;
    function BuildImageCollectionEditor: TTyDialog;
    function BuildTreeNodesEditor: TTyDialog;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPxIsTheDialogsOwnPPI;
    procedure TestMessageDialog;
    procedure TestInputDialog;
    procedure TestPasswordDialog;
    procedure TestTextDialog;
    procedure TestSelectValueDialog;
    procedure TestColorDialog;
    procedure TestFontDialog;
    procedure TestFindDialog;
    procedure TestReplaceDialog;
    procedure TestProgressDialog;
    procedure TestAboutDialog;
    procedure TestSelectPathDialog;
    procedure TestOpenDialog;
    procedure TestOpenDialogWithPreview;
    procedure TestIconBrowser;
    procedure TestImageCollectionEditor;
    procedure TestTreeNodesEditor;
    procedure TestTheColorPreviewBandFollowsTheDpiPass;
  end;

implementation

const
  HI = 168;      // 175%

type
  { Resize is protected: it is what re-places the button bar and the content once the
    form has its final size. }
  TDialogAccess = class(TTyDialog);

{ ===== harness ============================================================== }

procedure TTyDialogDpiTest.SetUp;
begin
  inherited SetUp;
  FSaveScreen := TyTestScreenPPI;
  FSaveScaled := Application.Scaled;
  { Not scaled: a scaled application runs a DPI pass of its own towards
    Monitor.PixelsPerInch whenever a form is constructed, and this process has no monitor
    to speak of. The simulated screen is the whole of the PPI here. }
  Application.Scaled := False;
  { The family text is measured in when a theme names none is a process-wide global, seeded
    by whichever controller was created first -- so without this the widths below are one
    thing when the suite runs alone and another after the rest (tests/test.dialogfit). }
  FSaveFontName := TyFallbackFontName;
  TyFallbackFontName := 'Arial';
  FFont := TFont.Create;
  FImages := TTyImageCollection.Create(nil);
  FTree := TTyTreeView.Create(nil);
end;

procedure TTyDialogDpiTest.TearDown;
begin
  FTree.Free;
  FImages.Free;
  FFont.Free;
  TyFallbackFontName := FSaveFontName;
  Application.Scaled := FSaveScaled;
  TyTestSimulateScreen(FSaveScreen);
  inherited TearDown;
end;

function TTyDialogDpiTest.Tree(ABuilder: TDialogBuilder; APPI: Integer): TStringList;
var
  d: TTyDialog;
  all, line: TStringList;
  i: Integer;
begin
  Result := TStringList.Create;
  TyTestSimulateScreen(APPI);
  d := ABuilder();
  try
    AssertEquals('precondition: the dialog is at the simulated PPI', APPI,
      d.Font.PixelsPerInch);
    { What showing it would do: align the title bar and the button strip, then let the
      dialog place its buttons and its content in the size it settled at. }
    TyTestSettle(d);
    TDialogAccess(d).Resize;
    TyTestSettle(d);
    Result.Add(Format('/client|0|0|%d|%d|1|%d', [d.ClientWidth, d.ClientHeight,
      d.Font.PixelsPerInch]));
    all := TStringList.Create;
    line := TStringList.Create;
    try
      line.Delimiter := '|';
      line.StrictDelimiter := True;
      TyTestListTree(d, all);
      { The form itself is the first line and is never "visible" here: nothing shows it.
        Its size is the /client line's business. }
      for i := 1 to all.Count - 1 do
      begin
        line.DelimitedText := all[i];
        if line[5] = '1' then Result.Add(all[i]);
      end;
    finally
      line.Free;
      all.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyDialogDpiTest.CheckScales(const AName: string; ABuilder: TDialogBuilder);
var
  lo, hi_, bad, a, b: TStringList;
  i, k, v, v2, want, tol: Integer;
  what: string;
const
  CField: array[1..4] of string = ('x', 'y', 'width', 'height');
begin
  lo := Tree(ABuilder, 96);
  hi_ := Tree(ABuilder, HI);
  bad := TStringList.Create;
  a := TStringList.Create;
  b := TStringList.Create;
  try
    a.Delimiter := '|';
    a.StrictDelimiter := True;
    b.Delimiter := '|';
    b.StrictDelimiter := True;
    AssertTrue(AName + ': precondition, the dialog has controls', lo.Count > 3);
    if lo.Count <> hi_.Count then
      Fail(AName + ': not the same controls at both scalings.' + LineEnding
        + '--- at 96:' + LineEnding + lo.Text + '--- at 168:' + LineEnding + hi_.Text);
    for i := 0 to lo.Count - 1 do
    begin
      a.DelimitedText := lo[i];
      b.DelimitedText := hi_[i];
      what := '';
      for k := 1 to 4 do
      begin
        v := StrToInt(a[k]);
        v2 := StrToInt(b[k]);
        want := MulDiv(v, HI, 96);
        tol := Max(6, Abs(want) * 8 div 100);
        if Abs(v2 - want) > tol then
          what := what + Format(' %s %d -> %d (wanted %d)', [CField[k], v, v2, want]);
      end;
      if what <> '' then bad.Add(Format('#%d %s:%s', [i, a[0], what]));
    end;
    AssertEquals(AName + ' at 168 PPI is not its 96-PPI self times 1.75:' + LineEnding
      + bad.Text, 0, bad.Count);
  finally
    b.Free;
    a.Free;
    bad.Free;
    hi_.Free;
    lo.Free;
  end;
end;

{ ===== the dialogs ========================================================== }

function TTyDialogDpiTest.BuildMessage: TTyDialog;
begin
  Result := TyBuildMessageDialog('The file has been changed on disk. Reload it and lose the'
    + ' changes made here, or keep editing this copy and decide later?', mtConfirmation,
    [mbYes, mbNo, mbCancel]);
end;

function TTyDialogDpiTest.BuildInput: TTyDialog;
var
  e: TTyEdit;
begin
  Result := TyBuildInputDialog('Rename', 'New name:', 'old.txt', e);
end;

function TTyDialogDpiTest.BuildPassword: TTyDialog;
var
  e: TTyEdit;
begin
  Result := TyBuildPasswordDialog('Sign in', 'Password:', '*', e);
end;

function TTyDialogDpiTest.BuildText: TTyDialog;
var
  m: TTyMemo;
begin
  Result := TyBuildTextDialog('Notes', 'Anything to add?', 'one' + LineEnding + 'two', m);
end;

function TTyDialogDpiTest.BuildSelectValue: TTyDialog;
var
  l: TTyListBox;
  items: TStringList;
begin
  items := TStringList.Create;
  try
    items.Add('Alpha');
    items.Add('Beta');
    items.Add('Gamma');
    Result := TyBuildSelectValueDialog('Pick one', 'Which?', items, 1, l);
  finally
    items.Free;
  end;
end;

function TTyDialogDpiTest.BuildColor: TTyDialog;
begin
  Result := TyBuildColorDialog('Select Color', TyRGB(59, 130, 246));
end;

function TTyDialogDpiTest.BuildFont: TTyDialog;
var
  fams: TStringList;
begin
  fams := TStringList.Create;
  try
    fams.Add('Arial');
    fams.Add('Courier New');
    fams.Add('Tahoma');
    Result := TyBuildFontDialog('Font', FFont, fams);
  finally
    fams.Free;
  end;
end;

function TTyDialogDpiTest.BuildFind: TTyDialog;
begin
  Result := TTyFindForm.CreateNew(nil, 0);
  TTyFindForm(Result).Build(False);
end;

function TTyDialogDpiTest.BuildReplace: TTyDialog;
begin
  Result := TTyFindForm.CreateNew(nil, 0);
  TTyFindForm(Result).Build(True);
end;

function TTyDialogDpiTest.BuildProgress: TTyDialog;
begin
  Result := TTyProgressForm.CreateNew(nil, 0);
  TTyProgressForm(Result).Build(True);
end;

function TTyDialogDpiTest.BuildAbout: TTyDialog;
begin
  Result := TyBuildAboutDialog('About', 'TyControls', '3.0.0', 'Themed controls for'
    + ' Lazarus.' + LineEnding + 'One look on every platform.', '(c) the authors',
    'MIT', 'https://example.invalid');
end;

function TTyDialogDpiTest.BuildSelectPath: TTyDialog;
begin
  Result := TyBuildSelectPathDialog('Select a folder', '');
end;

function TTyDialogDpiTest.BuildOpen: TTyDialog;
begin
  Result := TyBuildFileDialog(False, False, 'Open');
end;

function TTyDialogDpiTest.BuildOpenWithPreview: TTyDialog;
begin
  Result := TyBuildFileDialog(False, True, 'Open');
end;

function TTyDialogDpiTest.BuildIconBrowser: TTyDialog;
begin
  Result := TyBuildIconBrowserDialog('Icons', nil);
end;

function TTyDialogDpiTest.BuildImageCollectionEditor: TTyDialog;
begin
  Result := TyBuildImageCollectionEditor(FImages);
end;

function TTyDialogDpiTest.BuildTreeNodesEditor: TTyDialog;
begin
  { The tree editor is the concrete structure editor; the cascader's and the list groups'
    inherit the same form, so this one stands for all three. }
  Result := TyBuildTreeNodesEditor(FTree);
end;

{ ===== the tests ============================================================ }

procedure TTyDialogDpiTest.TestPxIsTheDialogsOwnPPI;
var
  d: TTyDialog;
begin
  TyTestSimulateScreen(HI);
  d := TTyDialog.CreateNew(nil);
  try
    AssertEquals('precondition: a dialog on a 168-PPI desktop', HI, d.Font.PixelsPerInch);
    AssertEquals('16 logical px', MulDiv(16, HI, 96), d.Px(16));
    AssertEquals('...and nothing at all is still nothing', 0, d.Px(0));
  finally
    d.Free;
  end;
  TyTestSimulateScreen(96);
  d := TTyDialog.CreateNew(nil);
  try
    AssertEquals('the identity at 96 PPI, so no dialog there moves by a pixel', 16, d.Px(16));
  finally
    d.Free;
  end;
end;

procedure TTyDialogDpiTest.TestMessageDialog;
begin
  CheckScales('the message dialog', @BuildMessage);
end;

procedure TTyDialogDpiTest.TestInputDialog;
begin
  CheckScales('the input dialog', @BuildInput);
end;

procedure TTyDialogDpiTest.TestPasswordDialog;
begin
  CheckScales('the password dialog', @BuildPassword);
end;

procedure TTyDialogDpiTest.TestTextDialog;
begin
  CheckScales('the text dialog', @BuildText);
end;

procedure TTyDialogDpiTest.TestSelectValueDialog;
begin
  CheckScales('the select-value dialog', @BuildSelectValue);
end;

procedure TTyDialogDpiTest.TestColorDialog;
begin
  CheckScales('the colour dialog', @BuildColor);
end;

procedure TTyDialogDpiTest.TestFontDialog;
begin
  CheckScales('the font dialog', @BuildFont);
end;

procedure TTyDialogDpiTest.TestFindDialog;
begin
  CheckScales('the find dialog', @BuildFind);
end;

procedure TTyDialogDpiTest.TestReplaceDialog;
begin
  CheckScales('the replace dialog', @BuildReplace);
end;

procedure TTyDialogDpiTest.TestProgressDialog;
begin
  CheckScales('the progress dialog', @BuildProgress);
end;

procedure TTyDialogDpiTest.TestAboutDialog;
begin
  CheckScales('the about dialog', @BuildAbout);
end;

procedure TTyDialogDpiTest.TestSelectPathDialog;
begin
  CheckScales('the select-path dialog', @BuildSelectPath);
end;

procedure TTyDialogDpiTest.TestOpenDialog;
begin
  CheckScales('the open dialog', @BuildOpen);
end;

procedure TTyDialogDpiTest.TestOpenDialogWithPreview;
begin
  CheckScales('the open dialog with a preview pane', @BuildOpenWithPreview);
end;

procedure TTyDialogDpiTest.TestIconBrowser;
begin
  CheckScales('the icon browser', @BuildIconBrowser);
end;

procedure TTyDialogDpiTest.TestImageCollectionEditor;
begin
  CheckScales('the image collection editor', @BuildImageCollectionEditor);
end;

procedure TTyDialogDpiTest.TestTreeNodesEditor;
begin
  CheckScales('the tree nodes editor', @BuildTreeNodesEditor);
end;

procedure TTyDialogDpiTest.TestTheColorPreviewBandFollowsTheDpiPass;
{ The other way a dialog reaches a HiDPI screen: one that builds itself INSIDE its
  constructor is still at 96 PPI when it does, and LCL's pass scales the finished layout.
  The pass scales CONTROLS. The colour dialog's preview band is a rectangle the form
  paints, so nothing scaled it: the band stayed where 96 PPI put it while the swatch grid
  above it moved down over it. }
var
  d: TTyColorForm;
  band96, band: TRect;
  grid96Bottom, gridBottom: Integer;
begin
  TyTestSimulateScreen(96);
  { Built at 96, as inside the constructor of a scaled application... }
  d := TyBuildColorDialog('Select Color', TyRGB(59, 130, 246));
  try
    band96 := d.PreviewRect;
    grid96Bottom := d.Swatches.Top + d.Swatches.Height;
    AssertTrue('precondition: the band is below the swatch grid at 96 PPI',
      band96.Top >= grid96Bottom);
    { ...then the pass. }
    d.AutoAdjustLayout(lapAutoAdjustForDPI, 96, HI, d.Width, MulDiv(d.Width, HI, 96));
    band := d.PreviewRect;
    gridBottom := d.Swatches.Top + d.Swatches.Height;
    AssertTrue(Format('precondition: the pass moved the swatch grid, bottom %d -> %d',
      [grid96Bottom, gridBottom]), Abs(gridBottom - MulDiv(grid96Bottom, HI, 96)) <= 4);
    AssertTrue(Format('the band is still below the grid: band top %d, grid bottom %d',
      [band.Top, gridBottom]), band.Top >= gridBottom);
    AssertTrue(Format('the band is as tall as its 96-PPI self times 1.75: %d -> %d',
      [band96.Bottom - band96.Top, band.Bottom - band.Top]),
      Abs((band.Bottom - band.Top) - MulDiv(band96.Bottom - band96.Top, HI, 96)) <= 2);
    AssertTrue(Format('...and as wide: %d -> %d', [band96.Right - band96.Left,
      band.Right - band.Left]),
      Abs((band.Right - band.Left) - MulDiv(band96.Right - band96.Left, HI, 96)) <= 2);
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyDialogDpiTest);

end.
