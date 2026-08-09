unit test.glyphthickness;
{$mode objfpc}{$H+}

{ Glyph stroke width must be scaled ONCE.

  THE BUG THIS ENDS. TTyPainter.DrawGlyph takes AThicknessLogical and scales it itself
  (`th := Scale(AThicknessLogical)`). Nine call sites handed it `P.Scale(1)` -- already device
  px -- so the stroke was scaled twice. At 100% that is invisible (1 -> 1 -> 1), which is why it
  survived: every developer screenshot is at 100%. At 250% it is
  Scale(1) = MulDiv(1,240,96) = 3, then Scale(3) = 8 -- an 8px stroke where 3px was intended,
  and the caption min/max/close read as heavy-handed. Reported from a 250% monitor.

  TWO GUARDS, because one alone is not enough:

  BEHAVIOUR (TheStrokeGrowsLinearlyWithDpi) pins DrawGlyph itself: render the same glyph at 96
  and at 240 PPI and measure the ink. Linear growth is right; quadratic is the bug. This is the
  assertion that stays meaningful if the whole call convention is ever reworked.

  SOURCE (NoCallerPreScalesTheThickness) pins the CALLERS, and it is the one that actually
  catches a regression -- the defect was never in DrawGlyph, it was in what was handed to it,
  and no run-time assertion can see a caller that is not on the current paint path. It reads
  source/ the way test.lucide's opt-in guard does. }

interface

uses
  Classes, SysUtils, StrUtils, Types, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes, Graphics,
  tyControls.Types, tyControls.Painter;

type
  TGlyphThicknessTest = class(TTestCase)
  private
    { Ink pixels of one glyph drawn into a bitmap of ASize, at APPI, with logical thickness 1. }
    function InkAt(APPI, ASize: Integer): Integer;
  published
    procedure TheStrokeGrowsLinearlyWithDpi;
    procedure NoCallerPreScalesTheThickness;
  end;

implementation

uses
  FileUtil, test.designregistry;

function TGlyphThicknessTest.InkAt(APPI, ASize: Integer): Integer;
var
  bmp: TBGRABitmap;
  cv: TBitmap;
  P: TTyPainter;
  x, y: Integer;
begin
  Result := 0;
  cv := TBitmap.Create;
  bmp := nil;
  try
    cv.SetSize(ASize, ASize);
    P := TTyPainter.Create;
    try
      P.BeginPaint(cv.Canvas, Rect(0, 0, ASize, ASize), APPI);
      { A single horizontal bar: the simplest shape whose ink area is proportional to the
        stroke width alone, so the count is not confounded by the glyph's geometry. }
      P.DrawGlyph(Rect(0, 0, ASize, ASize), tgMinimize, TyRGB(0, 0, 0), 1, 4);
      bmp := TBGRABitmap.Create(P.Bitmap);
      P.EndPaint;
    finally
      P.Free;
    end;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
        if bmp.GetPixel(x, y).alpha > 40 then Inc(Result);
  finally
    bmp.Free;
    cv.Free;
  end;
end;

procedure TGlyphThicknessTest.TheStrokeGrowsLinearlyWithDpi;
var
  a, b: Integer;
  ratio: Double;
begin
  { The bar's LENGTH scales with the box (which is scaled by the caller), so a 2.5x box with a
    2.5x stroke is 6.25x the ink. Doubly-scaled thickness would make it ~2.5x that again. The
    window below separates the two answers with room to spare and does not pretend to
    pixel-exactness -- antialiasing and rounding move the count a little either way. }
  a := InkAt(96, 40);
  b := InkAt(240, 100);
  AssertTrue('the glyph drew something at 96 PPI', a > 0);
  AssertTrue('and at 240 PPI', b > 0);
  ratio := b / a;
  AssertTrue(Format('ink grew %.2fx from 96 to 240 PPI; expected about 6.25x '
    + '(2.5x box * 2.5x stroke). Above ~10x means the thickness was scaled twice.',
    [ratio]), (ratio > 4.0) and (ratio < 10.0));
end;

procedure TGlyphThicknessTest.NoCallerPreScalesTheThickness;
var
  files, src: TStringList;
  i, p, q, depth, argStart, comma, argNo, found: Integer;
  txt, call, args, arg, bad: string;

  { The Nth top-level (comma-separated, bracket-aware) argument of an argument list. }
  function ArgN(const AList: string; AIndex: Integer): string;
  var k, d, start, n: Integer;
  begin
    Result := ''; d := 0; start := 1; n := 0;
    for k := 1 to Length(AList) do
    begin
      if AList[k] in ['(', '['] then Inc(d)
      else if AList[k] in [')', ']'] then Dec(d)
      else if (AList[k] = ',') and (d = 0) then
      begin
        if n = AIndex then Exit(Trim(Copy(AList, start, k - start)));
        Inc(n); start := k + 1;
      end;
    end;
    if n = AIndex then Result := Trim(Copy(AList, start, MaxInt));
  end;

begin
  { P.DrawGlyph(rect, kind, colour, THICKNESS, pad)                        -> argument 3 (0-based)
    TyDrawGlyph(painter, ctrl, rect, kind, colour, THICKNESS, pad)         -> argument 5
    TyDrawGlyph(painter, ctrl, rect, token, kind, colour, THICKNESS, pad)  -> argument 6

    The two TyDrawGlyph overloads are told apart by argument 3, NOT by the argument COUNT: the
    token-less form WITH a pad and the token form WITHOUT one both have seven arguments, and
    counting picked the wrong slot for exactly the call this test exists to catch (its own
    mutation test caught that). Argument 3 is a tg* kind in the token-less form and a token
    expression in the other. }
  bad := '';
  found := 0;
  files := FindAllFiles(RepoRoot + 'source', '*.pas', False);
  src := TStringList.Create;
  try
    for i := 0 to files.Count - 1 do
    begin
      src.LoadFromFile(files[i]);
      txt := src.Text;
      p := 1;
      repeat
        p := PosEx('DrawGlyph(', txt, p);
        if p = 0 then Break;
        call := 'DrawGlyph';
        if (p > 2) and (Copy(txt, p - 2, 2) = 'Ty') then call := 'TyDrawGlyph';
        { DrawGlyphBitmap is a different routine -- it has no thickness at all. }
        argStart := p + Length('DrawGlyph(');
        q := argStart; depth := 1;
        while (q <= Length(txt)) and (depth > 0) do
        begin
          if txt[q] = '(' then Inc(depth)
          else if txt[q] = ')' then Dec(depth);
          Inc(q);
        end;
        args := Copy(txt, argStart, q - argStart - 1);
        p := q;
        { how many top-level arguments? }
        argNo := 0; depth := 0;
        for comma := 1 to Length(args) do
          if args[comma] in ['(', '['] then Inc(depth)
          else if args[comma] in [')', ']'] then Dec(depth)
          else if (args[comma] = ',') and (depth = 0) then Inc(argNo);
        Inc(argNo);                              { commas + 1 = arguments }
        if call = 'TyDrawGlyph' then
        begin
          if StartsText('tg', ArgN(args, 3)) then arg := ArgN(args, 5)  { kind at 3 -> no token }
          else arg := ArgN(args, 6);
        end
        else
        begin
          if argNo < 4 then Continue;            { DrawGlyph overload with no thickness }
          arg := ArgN(args, 3);
        end;
        Inc(found);
        if Pos('Scale(', arg) > 0 then
          bad := bad + LineEnding + '  ' + ExtractFileName(files[i]) + ': ' + call
                 + ' thickness = ' + arg;
      until False;
    end;
    { Anti-vacuity, and it is not decoration: the first version of this test PASSED under its
      own mutation because it read the wrong argument slot. A count is the cheapest thing that
      notices the scan has stopped understanding the source. }
    AssertTrue(Format('the scan inspected %d DrawGlyph calls; the library has dozens, so a '
      + 'number this low means the parser stopped matching', [found]), found >= 20);
    AssertEquals('DrawGlyph callers passing an ALREADY-SCALED thickness (it is scaled again '
      + 'inside, so the stroke comes out 2-3x too heavy on a HiDPI monitor):' + bad, '', bad);
  finally
    src.Free;
    files.Free;
  end;
end;

initialization
  RegisterTest(TGlyphThicknessTest);

end.
