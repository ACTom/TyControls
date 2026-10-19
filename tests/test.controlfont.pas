unit test.controlfont;
{ #92: what an author changes on a control's own Font -- name, bold, italic, underline,
  strikeout, colour -- is drawn. It used to be the size only: a TTyLabel whose Font.Name was
  set in the Object Inspector kept the theme's face.

  The rule under test (TyApplyControlFont, called by both base classes' CurrentStyle):
  with ParentFont False the font is laid over the theme's style, before StyleOverride, which
  still wins; with ParentFont True the theme decides. Italic, underline and strikeout ride on
  the weight every text call already passes, above the CSS weight's range, and the two font
  set-ups (TyConfigureTextFont, TyConfigureMeasureFont) are the only readers. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Graphics, Controls, Forms, FileUtil, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Painter,
  tyControls.TyLabel, tyControls.Button, tyControls.HtmlLabel, test.designregistry,
  test.dpi.support;

type
  TControlFontTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FLabel: TTyLabel;
    FButton: TTyButton;
    function LabelStyle: TTyStyleSet;
    function ButtonStyle: TTyStyleSet;
    function LabelInk(const AName: string): TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFontNameReachesTheStyle;
    procedure TestParentFontKeepsTheTheme;
    procedure TestBoldSetsTheWeight;
    procedure TestItalicUnderlineAndStrikeOutRideTheWeight;
    procedure TestNoStyleKeepsTheThemeWeight;
    procedure TestFontColorExceptWhenDisabled;
    procedure TestStyleOverrideStillWins;
    procedure TestWindowedControlsToo;
    procedure TestTheTextFontTakesTheStyle;
    procedure TestTheMeasureFontTakesTheStyle;
    procedure TestTheLabelIsDrawnInItsFont;
    procedure TestNoUnitReadsTheWeightAsANumber;
    procedure TestTheHtmlLabelTakesItsFontStyle;
  end;

implementation

type
  TLabelAccess = class(TTyLabel);
  TButtonAccess = class(TTyButton);

procedure TControlFontTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FLabel := TTyLabel.Create(nil);
  FLabel.Controller := FCtl;
  FLabel.Caption := 'Illuminate 节点';
  FButton := TTyButton.Create(nil);
  FButton.Controller := FCtl;
  FButton.Caption := 'Illuminate';
end;

procedure TControlFontTest.TearDown;
begin
  FButton.Free;
  FLabel.Free;
  FCtl.Free;
end;

function TControlFontTest.LabelStyle: TTyStyleSet;
begin
  Result := TLabelAccess(FLabel).CurrentStyle;
end;

function TControlFontTest.ButtonStyle: TTyStyleSet;
begin
  Result := TButtonAccess(FButton).CurrentStyle;
end;

procedure TControlFontTest.TestFontNameReachesTheStyle;
begin
  FLabel.Font.Name := 'Courier New';
  AssertFalse('precondition: setting the font clears ParentFont', TLabelAccess(FLabel).ParentFont);
  AssertEquals('the label''s face', 'Courier New', LabelStyle.FontName);
  AssertTrue('and the style says it has one', tpFontName in LabelStyle.Present);
end;

procedure TControlFontTest.TestParentFontKeepsTheTheme;
var themed: string;
begin
  themed := LabelStyle.FontName;
  FLabel.Font.Name := 'Courier New';
  FLabel.Font.Style := [fsBold, fsItalic];
  FLabel.Font.Color := clRed;
  TLabelAccess(FLabel).ParentFont := True;
  AssertEquals('ParentFont True: the theme''s face', themed, LabelStyle.FontName);
  AssertEquals('and the theme''s weight, no flags', TyFontWeightOf(LabelStyle.FontWeight),
    LabelStyle.FontWeight);
end;

procedure TControlFontTest.TestBoldSetsTheWeight;
var themed: string;
begin
  themed := LabelStyle.FontName;
  FLabel.Font.Style := [fsBold];
  AssertEquals('LCL''s ''default'' face is not a face: the theme''s stays', themed,
    LabelStyle.FontName);
  AssertEquals('bold is 700', 700, TyFontWeightOf(LabelStyle.FontWeight));
  AssertTrue('and drawn bold', fsBold in TyFontStylesOf(LabelStyle.FontWeight));
end;

procedure TControlFontTest.TestItalicUnderlineAndStrikeOutRideTheWeight;
var w: Integer;
begin
  FLabel.Font.Style := [fsItalic, fsUnderline, fsStrikeOut];
  w := LabelStyle.FontWeight;
  AssertTrue('italic', fsItalic in TyFontStylesOf(w));
  AssertTrue('underline', fsUnderline in TyFontStylesOf(w));
  AssertTrue('strikeout', fsStrikeOut in TyFontStylesOf(w));
  AssertFalse('not bold', fsBold in TyFontStylesOf(w));
  FLabel.Font.Style := [fsItalic];
  w := LabelStyle.FontWeight;
  AssertTrue('italic alone', TyFontStylesOf(w) = [fsItalic]);
end;

procedure TControlFontTest.TestNoStyleKeepsTheThemeWeight;
var themed: Integer;
begin
  themed := LabelStyle.FontWeight;
  FLabel.Font.Name := 'Courier New';   // ParentFont False, no style
  AssertEquals('an unstyled font leaves the theme''s weight', themed, LabelStyle.FontWeight);
  { the themes give a label 400, so the combiner is asked with another weight too }
  AssertEquals('no bold keeps a 600', 600 or TyFontItalic, TyFontWeightWithStyle(600, [fsItalic]));
  AssertEquals('bold makes 700', 700 or TyFontUnderline,
    TyFontWeightWithStyle(300, [fsBold, fsUnderline]));
  AssertEquals('flags already there are dropped first', 500,
    TyFontWeightWithStyle(500 or TyFontStrikeOut, []));
end;

procedure TControlFontTest.TestFontColorExceptWhenDisabled;
var themedDisabled: TTyColor;
begin
  FLabel.Enabled := False;
  themedDisabled := LabelStyle.TextColor;
  FLabel.Enabled := True;
  FLabel.Font.Color := clRed;
  AssertTrue('the text is red', (LabelStyle.TextColor = TyRGBA(255, 0, 0, 255)));
  FLabel.Enabled := False;
  AssertTrue('disabled keeps the theme''s disabled colour',
    (LabelStyle.TextColor = themedDisabled));
end;

procedure TControlFontTest.TestStyleOverrideStillWins;
begin
  FLabel.Font.Name := 'Courier New';
  FLabel.StyleOverride := 'font-family: Arial';
  AssertEquals('StyleOverride over the font', 'Arial', LabelStyle.FontName);
end;

procedure TControlFontTest.TestWindowedControlsToo;
begin
  FButton.Font.Name := 'Courier New';
  FButton.Font.Style := [fsItalic];
  FButton.Font.Color := clBlue;
  AssertEquals('a button''s face', 'Courier New', ButtonStyle.FontName);
  AssertTrue('italic', fsItalic in TyFontStylesOf(ButtonStyle.FontWeight));
  AssertTrue('blue', (ButtonStyle.TextColor = TyRGBA(0, 0, 255, 255)));
end;

procedure TControlFontTest.TestTheTextFontTakesTheStyle;
var b: TBGRABitmap;
begin
  b := TBGRABitmap.Create(4, 4);
  try
    TyConfigureTextFont(b, 'Segoe UI', 10, 400 or TyFontItalic or TyFontUnderline, 96);
    AssertTrue('italic and underline, not bold', b.FontStyle = [fsItalic, fsUnderline]);
    TyConfigureTextFont(b, 'Segoe UI', 10, 700 or TyFontStrikeOut, 96);
    AssertTrue('bold and strikeout', b.FontStyle = [fsBold, fsStrikeOut]);
  finally
    b.Free;
  end;
end;

procedure TControlFontTest.TestTheMeasureFontTakesTheStyle;
var b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.SetSize(4, 4);
    TyConfigureMeasureFont(b.Canvas, 'Segoe UI', 10, 400 or TyFontItalic, 96);
    AssertTrue('measured italic', b.Canvas.Font.Style = [fsItalic]);
    TyConfigureMeasureFont(b.Canvas, 'Segoe UI', 10, 600 or TyFontUnderline, 96);
    AssertTrue('measured bold and underlined', b.Canvas.Font.Style = [fsBold, fsUnderline]);
  finally
    b.Free;
  end;
end;

function TControlFontTest.LabelInk(const AName: string): TBGRABitmap;
var host: TBitmap;
begin
  host := TBitmap.Create;
  try
    host.SetSize(160, 24);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, 160, 24);
    if AName <> '' then FLabel.Font.Name := AName else TLabelAccess(FLabel).ParentFont := True;
    TLabelAccess(FLabel).RenderTo(host.Canvas, Rect(0, 0, 160, 24), 96);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

procedure TControlFontTest.TestTheLabelIsDrawnInItsFont;
var themed, courier: TBGRABitmap;
  x, y, diff: Integer;
begin
  themed := LabelInk('');
  courier := LabelInk('Courier New');
  try
    diff := 0;
    for y := 0 to 23 do
      for x := 0 to 159 do
        if themed.GetPixel(x, y) <> courier.GetPixel(x, y) then Inc(diff);
    AssertTrue('a label in Courier New does not look like the themed one (' + IntToStr(diff)
      + ' pixels differ)', diff > 50);
  finally
    themed.Free;
    courier.Free;
  end;
end;

{ The flags ride above the CSS weight, so `FontWeight >= 600` would call an italic regular
  font bold. Every reading of a weight as a number goes through TyFontWeightOf or
  TyFontStylesOf; a comparison or arithmetic on a bare FontWeight / AWeight anywhere else in
  source/ is a reader that forgot. }
procedure TControlFontTest.TestNoUnitReadsTheWeightAsANumber;
var files, sl: TStringList;
  i, j: Integer;
  ln, lc, bad: string;
begin
  files := FindAllFiles(RepoRoot + 'source', '*.pas', True);
  sl := TStringList.Create;
  try
    AssertTrue('the sources were found', files.Count > 100);
    bad := '';
    for i := 0 to files.Count - 1 do
    begin
      sl.LoadFromFile(files[i]);
      sl.Text := TyTestCodeOnly(sl.Text);   // prose about a weight is not a reading of one
      for j := 0 to sl.Count - 1 do
      begin
        ln := sl[j];
        lc := LowerCase(Trim(ln));
        if lc = '' then Continue;
        if (Pos('tyfontweightof', lc) > 0) or (Pos('tyfontstylesof', lc) > 0) then Continue;
        if ((Pos('fontweight', lc) > 0) or (Pos('aweight', lc) > 0))
          and ((Pos('>= ', lc) > 0) or (Pos('<= ', lc) > 0) or (Pos(' > ', lc) > 0)
            or (Pos(' < ', lc) > 0) or (Pos('fontweight = ', lc) > 0)
            or (Pos('aweight = ', lc) > 0)) then
          bad := bad + LineEnding + ExtractFileName(files[i]) + ':' + IntToStr(j + 1) + ': '
            + Trim(ln);
      end;
    end;
    AssertEquals('weights read as numbers outside TyFontWeightOf / TyFontStylesOf', '', bad);
  finally
    sl.Free;
    files.Free;
  end;
end;

type
  THtmlAccess = class(TTyHtmlLabel);

procedure TControlFontTest.TestTheHtmlLabelTakesItsFontStyle;
var h: THtmlAccess;
  plain, italic: TBGRABitmap;

  function Shot: TBGRABitmap;
  var host: TBitmap;
  begin
    host := TBitmap.Create;
    try
      host.SetSize(200, 24);
      host.Canvas.Brush.Color := clWhite;
      host.Canvas.FillRect(0, 0, 200, 24);
      h.RenderTo(host.Canvas, Rect(0, 0, 200, 24), 96);
      Result := TBGRABitmap.Create(host);
    finally
      host.Free;
    end;
  end;

var x, y, diff: Integer;
begin
  h := THtmlAccess.Create(nil);
  plain := nil;
  italic := nil;
  try
    h.Controller := FCtl;
    h.SetBounds(0, 0, 200, 24);
    h.Html := 'Illuminate <b>bold</b> text';
    plain := Shot;
    h.Font.Style := [fsItalic];
    italic := Shot;
    diff := 0;
    for y := 0 to 23 do
      for x := 0 to 199 do
        if plain.GetPixel(x, y) <> italic.GetPixel(x, y) then Inc(diff);
    AssertTrue('the label''s italic reaches its runs (' + IntToStr(diff) + ' pixels differ)',
      diff > 50);
  finally
    italic.Free;
    plain.Free;
    h.Free;
  end;
end;

initialization
  RegisterTest(TControlFontTest);
end.
