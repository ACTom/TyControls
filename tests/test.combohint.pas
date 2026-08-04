unit test.combohint;
{$mode objfpc}{$H+}
{ TextHint (LCL stdctrls.pp:444) is painted by TTyComboBox.PaintTextHint, which the EMPTY
  branch of PaintFieldContent calls. Every subclass that replaces PaintFieldContent has to
  route its own empty state back there, or the placeholder silently vanishes on exactly the
  controls a host is most likely to leave unset.

  One guard per subclass -- checked individually, because the six are not shaped alike:
  four replace the paint and hand their empty branch back to the base, and two do not
  replace it at all. Each is proved by two renders that DIFFER; a property test would pass
  with the paint left unwired. The counter-guards below pin the other direction, because a
  placeholder that paints behind real content is worse than none. }
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  tyControls.ComboBox, tyControls.ColorBox, tyControls.FilterComboBox,
  tyControls.FontComboBox, tyControls.OfficeComboBox, tyControls.ShellComboBox,
  tyControls.AdvancedComboBox;

type
  { RenderTo is protected on TTyComboBox; a descendant declared HERE can reach it on any
    combo instance, which saves six probe classes differing only in their ancestor. }
  TComboRenderAccess = class(TTyComboBox);

  TComboHintTest = class(TTestCase)
  private
    { True when the two combos paint differently at the same size -- the only honest proof
      that the paint path READS TextHint. }
    function RendersDiffer(A, B: TTyComboBox): Boolean;
  published
    procedure TestColorBoxPaintsTheHintWhenEmpty;
    procedure TestFilterComboBoxPaintsTheHintWhenEmpty;
    procedure TestFontComboBoxPaintsTheHintWhenEmpty;
    procedure TestOfficeComboBoxPaintsTheHintWhenEmpty;
    procedure TestShellComboBoxPaintsTheHintWhenEmpty;
    procedure TestAdvancedComboBoxPaintsTheHintWhenEmpty;
    { The other direction, on the four that draw their own field content. }
    procedure TestColorBoxHidesTheHintBehindASwatch;
    procedure TestFontComboBoxHidesTheHintBehindAFontName;
    procedure TestAdvancedComboBoxHidesTheHintBehindAnItem;
    procedure TestShellComboBoxHidesTheHintBehindADirectory;
  end;

implementation

const
  HintW = 160;
  HintH = 26;

function TComboHintTest.RendersDiffer(A, B: TTyComboBox): Boolean;
var
  BmpA, BmpB: TBitmap;
  x, y: Integer;
begin
  Result := False;
  BmpA := TBitmap.Create;
  BmpB := TBitmap.Create;
  try
    BmpA.PixelFormat := pf32bit; BmpA.SetSize(HintW, HintH);
    BmpB.PixelFormat := pf32bit; BmpB.SetSize(HintW, HintH);
    TComboRenderAccess(A).RenderTo(BmpA.Canvas, Rect(0, 0, HintW, HintH), 96);
    TComboRenderAccess(B).RenderTo(BmpB.Canvas, Rect(0, 0, HintW, HintH), 96);
    for y := 0 to HintH - 1 do
      for x := 0 to HintW - 1 do
        if ColorToRGB(BmpA.Canvas.Pixels[x, y]) <> ColorToRGB(BmpB.Canvas.Pixels[x, y]) then
          Exit(True);
  finally
    BmpA.Free; BmpB.Free;
  end;
end;

{ ---- empty field: the hint has to reach the pixels ---- }

procedure TComboHintTest.TestColorBoxPaintsTheHintWhenEmpty;
var plain, hinted: TTyColorBox;
begin
  { A colour box is born with the curated 16 selected, so "empty" means ClearColors. }
  plain  := TTyColorBox.Create(nil);
  hinted := TTyColorBox.Create(nil);
  try
    plain.ClearColors;
    hinted.ClearColors;
    hinted.TextHint := 'Pick a colour';
    AssertEquals('the palette really is empty', -1, hinted.ItemIndex);
    AssertTrue('an empty colour box paints its TextHint', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestFilterComboBoxPaintsTheHintWhenEmpty;
var plain, hinted: TTyFilterComboBox;
begin
  { No Filter string -> no rows -> nothing selected. This one never replaced
    PaintFieldContent, so the guard pins that it stays that way. }
  plain  := TTyFilterComboBox.Create(nil);
  hinted := TTyFilterComboBox.Create(nil);
  try
    hinted.TextHint := 'All files';
    AssertEquals('no filter parsed yet', -1, hinted.ItemIndex);
    AssertTrue('an empty filter combo paints its TextHint', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestFontComboBoxPaintsTheHintWhenEmpty;
var plain, hinted: TTyFontComboBox;
begin
  { The constructor selects the first installed family, so "empty" means Clear. }
  plain  := TTyFontComboBox.Create(nil);
  hinted := TTyFontComboBox.Create(nil);
  try
    plain.Clear;
    hinted.Clear;
    hinted.TextHint := 'Pick a font';
    AssertEquals('no family selected', -1, hinted.ItemIndex);
    AssertTrue('an empty font combo paints its TextHint', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestOfficeComboBoxPaintsTheHintWhenEmpty;
var plain, hinted: TTyOfficeComboBox;
begin
  { Grouped combos start with no rows at all. This one never replaced PaintFieldContent
    either -- only the popup list's row paint. }
  plain  := TTyOfficeComboBox.Create(nil);
  hinted := TTyOfficeComboBox.Create(nil);
  try
    hinted.TextHint := 'Choose a style';
    AssertEquals('nothing selected', -1, hinted.ItemIndex);
    AssertTrue('an empty grouped combo paints its TextHint', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestShellComboBoxPaintsTheHintWhenEmpty;
var plain, hinted: TTyShellComboBox;
begin
  { Its empty branch is `Directory = ''`, not `ItemIndex < 0` -- which is why each of the
    six had to be read rather than assumed alike. }
  plain  := TTyShellComboBox.Create(nil);
  hinted := TTyShellComboBox.Create(nil);
  try
    hinted.TextHint := 'Look in...';
    AssertEquals('no directory yet', '', hinted.Directory);
    AssertTrue('a directory-less look-in combo paints its TextHint',
      RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestAdvancedComboBoxPaintsTheHintWhenEmpty;
var plain, hinted: TTyAdvancedComboBox;
begin
  plain  := TTyAdvancedComboBox.Create(nil);
  hinted := TTyAdvancedComboBox.Create(nil);
  try
    hinted.TextHint := 'Choose an account';
    AssertEquals('nothing selected', -1, hinted.ItemIndex);
    AssertTrue('an empty rich combo paints its TextHint', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

{ ---- filled field: the hint must NOT paint behind real content ---- }

procedure TComboHintTest.TestColorBoxHidesTheHintBehindASwatch;
var plain, hinted: TTyColorBox;
begin
  plain  := TTyColorBox.Create(nil);
  hinted := TTyColorBox.Create(nil);
  try
    plain.ItemIndex  := 0;
    hinted.ItemIndex := 0;
    hinted.TextHint  := 'Pick a colour';
    AssertFalse('a hint never shows behind a selected swatch', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestFontComboBoxHidesTheHintBehindAFontName;
var plain, hinted: TTyFontComboBox;
begin
  plain  := TTyFontComboBox.Create(nil);
  hinted := TTyFontComboBox.Create(nil);
  try
    hinted.TextHint := 'Pick a font';
    AssertTrue('the constructor selected a family', plain.ItemIndex >= 0);
    AssertFalse('a hint never shows behind a font name', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestAdvancedComboBoxHidesTheHintBehindAnItem;
var plain, hinted: TTyAdvancedComboBox;
begin
  plain  := TTyAdvancedComboBox.Create(nil);
  hinted := TTyAdvancedComboBox.Create(nil);
  try
    plain.AddItem('Work', 'work@example.com', -1);
    hinted.AddItem('Work', 'work@example.com', -1);
    plain.ItemIndex  := 0;
    hinted.ItemIndex := 0;
    hinted.TextHint  := 'Choose an account';
    AssertFalse('a hint never shows behind a rich row', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboHintTest.TestShellComboBoxHidesTheHintBehindADirectory;
var
  plain, hinted: TTyShellComboBox;
  dir: string;
begin
  dir := ExcludeTrailingPathDelimiter(GetCurrentDir);
  plain  := TTyShellComboBox.Create(nil);
  hinted := TTyShellComboBox.Create(nil);
  try
    plain.Directory  := dir;
    hinted.Directory := dir;
    hinted.TextHint  := 'Look in...';
    AssertTrue('the directory took', hinted.Directory <> '');
    AssertFalse('a hint never shows behind a directory label', RendersDiffer(plain, hinted));
  finally
    plain.Free; hinted.Free;
  end;
end;

initialization
  RegisterTest(TComboHintTest);
end.
