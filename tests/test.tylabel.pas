unit test.tylabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, Forms, Controls, StdCtrls,
  Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.TyLabel, tyControls.Painter, tyControls.Controller,
  tyControls.ToolBar;
type
  TTyLabelAccess = class(TTyLabel)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallPreferredSize(var W, H: Integer);
    procedure DoClick;
  end;

  { Handle-free focus target: reports focusable and records SetFocus so the
    click-to-focus path is verifiable headlessly (no win32 handle / no 1407). }
  TFocusProbe = class(TEdit)
  public
    Focused_: Boolean;
    function CanFocus: Boolean; override;
    procedure SetFocus; override;
  end;

  TLabelTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestCaptionProperty;
    procedure TestPaintSmoke;
    procedure TestAlignmentLayoutRender;
    procedure TestAutoSizeFitsCaption;
    procedure TestAutoSizeRefiresOnRuntimeCaption;
    procedure TestWordWrapWraps;
    procedure TestWordWrapCJK;
    procedure TestWordWrapKeepsAuthoredLineBreaks;
    procedure TestWordWrapLayoutBottom;
    procedure TestFocusControlOnClick;
    procedure TestTransparentDefault;
    procedure TestAuthoredBreakRendersASecondLine;
    procedure TestLineHeightTokenSizesTheCaptionBlock;
  end;

  { A hand-set Height is a REQUEST; what is possible is decided by the font and the padding,
    and only the control knows both. On Linux/Qt6 the same 9pt CJK caption resolves a fallback
    face whose ink is taller than Windows', and the text is drawn clipped — so a box shorter
    than the ink loses the BOTTOM of it. These cover the floor the label publishes, including
    the two things it deliberately does DIFFERENTLY when wrapping: no width floor at all, and
    a height floor that does not move with the width. }
  TLabelSizeFloorTest = class(TTestCase)
  published
    procedure TestMinimumFitsTheCaption;
    procedure TestMinimumIsThePreferredSize;
    procedure TestWrappingLabelHasNoWidthFloor;
    procedure TestWrappingFloorDoesNotMoveWithTheWidth;
    procedure TestSmallerFontLowersTheMinimum;
    procedure TestMinimumSurvivesAHeightPinningParent;
  end;
implementation

procedure TTyLabelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyLabelAccess.CallPreferredSize(var W, H: Integer);
begin
  CalculatePreferredSize(W, H, True);
end;

procedure TTyLabelAccess.DoClick;
begin
  Click;
end;

function TFocusProbe.CanFocus: Boolean;
begin
  Result := True;
end;

procedure TFocusProbe.SetFocus;
begin
  Focused_ := True;
end;

procedure TLabelTest.TestTypeKey;
var
  L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    AssertEquals('TyLabel', (L as ITyStyleable).GetStyleTypeKey);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestCaptionProperty;
var
  L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    L.Caption := 'Hello';
    AssertEquals('Hello', L.Caption);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestPaintSmoke;
var
  F: TCustomForm;
  L: TTyLabelAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    L := TTyLabelAccess.Create(F);
    L.Parent := F;
    L.Caption := 'Label';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 20);
    L.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 20), 96);
    AssertTrue('label RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

{ Ink centroid (X and Y) of the dark caption pixels over a white backdrop,
  rendered with the given Alignment/Layout. }
procedure RenderCentroid(A: TAlignment; L: TTextLayout; out CX, CY: Double);
var
  G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap;
  x, y, n: Integer; sx, sy: Double; px: TBGRAPixel;
begin
  G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
  try
    G.Caption := 'Hi'; G.Alignment := A; G.Layout := L; G.Font.PixelsPerInch := 96;
    Bmp.PixelFormat := pf32bit; Bmp.SetSize(200, 60);
    Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 200, 60);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 60), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      sx := 0; sy := 0; n := 0;
      for x := 0 to 199 do for y := 0 to 59 do
      begin
        px := Reread.GetPixel(x, y);
        if (px.red < 160) and (px.green < 160) then
        begin sx := sx + x; sy := sy + y; Inc(n); end;
      end;
      if n = 0 then begin CX := -1; CY := -1; end
      else begin CX := sx / n; CY := sy / n; end;
    finally Reread.Free; end;
  finally Bmp.Free; G.Free; end;
end;

procedure TLabelTest.TestAlignmentLayoutRender;
var
  lcx, lcy, rcx, rcy, tcy, bcy, dummy: Double;
begin
  RenderCentroid(taLeftJustify, tlCenter, lcx, lcy);
  RenderCentroid(taRightJustify, tlCenter, rcx, dummy);
  AssertTrue('left-aligned caption ink present', lcx > 0);
  AssertTrue('right-aligned caption further right', rcx > lcx + 20);

  RenderCentroid(taLeftJustify, tlTop, dummy, tcy);
  RenderCentroid(taLeftJustify, tlBottom, dummy, bcy);
  AssertTrue('top layout ink present', tcy > 0);
  AssertTrue('bottom-layout caption lower than top-layout', bcy > tcy + 15);
end;

procedure TLabelTest.TestAutoSizeFitsCaption;
var
  L: TTyLabelAccess; wShort, hShort, wLong, hLong, wWrap, hWrap: Integer;
begin
  // AutoSize drives CalculatePreferredSize; assert the measured extent tracks the
  // caption. (Applying it to on-screen bounds needs a window handle, flaky headless.)
  L := TTyLabelAccess.Create(nil);
  try
    L.Font.PixelsPerInch := 96;
    AssertFalse('AutoSize default False', L.AutoSize);
    L.AutoSize := True;
    AssertTrue('AutoSize settable True', L.AutoSize);

    L.Caption := 'Hi';
    wShort := 0; hShort := 0; L.CallPreferredSize(wShort, hShort);
    AssertTrue('short caption preferred width > 0', wShort > 0);
    AssertTrue('preferred height fits a line (>=8px)', hShort >= 8);

    L.Caption := 'A much wider caption text here';
    wLong := 0; hLong := 0; L.CallPreferredSize(wLong, hLong);
    AssertTrue('wider caption -> wider preferred width', wLong > wShort + 40);

    // WordWrap+AutoSize: at a narrow width the wrapped text is taller (>1 line).
    L.Width := 60;
    L.WordWrap := True;
    L.Caption := 'one two three four five six';
    wWrap := 0; hWrap := 0; L.CallPreferredSize(wWrap, hWrap);
    AssertTrue('wrapped preferred width bounded by control width', wWrap <= 60 + 8);
    AssertTrue('wrapped preferred height spans multiple lines', hWrap > hShort + 8);
  finally
    L.Free;
  end;
end;

{ Runtime Caption change must re-fire AutoSize: assigning a longer Caption after
  the preferred size was already cached has to invalidate that cache (via TextChanged)
  so the next GetPreferredSize returns a larger width. We never call
  CalculatePreferredSize directly here — only the public GetPreferredSize cache path,
  which is exactly what AdjustSize uses on-screen. }
procedure TLabelTest.TestAutoSizeRefiresOnRuntimeCaption;
var
  L: TTyLabel; w0, h0, w1, h1: Integer;
begin
  L := TTyLabel.Create(nil);
  try
    L.Font.PixelsPerInch := 96;
    L.AutoSize := True;
    L.Caption := 'Hi';
    // Prime + validate the preferred-size cache for the short caption.
    w0 := 0; h0 := 0; L.GetPreferredSize(w0, h0);
    AssertTrue('short caption preferred width > 0', w0 > 0);

    // Assign a much longer caption at runtime; TextChanged must invalidate the cache.
    L.Caption := 'A considerably wider runtime caption text';
    w1 := 0; h1 := 0; L.GetPreferredSize(w1, h1);
    AssertTrue('runtime longer Caption grows preferred width (TextChanged re-fired AutoSize)',
      w1 > w0 + 40);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestWordWrapWraps;
  function InkBands(WordWrap: Boolean): Integer;
  var
    G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap;
    x, y, bands: Integer; rowHasInk, prevRowInk: Boolean; px: TBGRAPixel;
  begin
    G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
    try
      G.Font.PixelsPerInch := 96;
      G.WordWrap := WordWrap;
      G.Caption := 'one two three four five six';
      Bmp.PixelFormat := pf32bit; Bmp.SetSize(60, 80);
      Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 60, 80);
      G.RenderTo(Bmp.Canvas, Rect(0, 0, 60, 80), 96);
      Reread := TBGRABitmap.Create(Bmp);
      try
        bands := 0; prevRowInk := False;
        for y := 0 to 79 do
        begin
          rowHasInk := False;
          for x := 0 to 59 do
          begin
            px := Reread.GetPixel(x, y);
            if (px.red < 160) and (px.green < 160) then
            begin rowHasInk := True; Break; end;
          end;
          if rowHasInk and not prevRowInk then Inc(bands);
          prevRowInk := rowHasInk;
        end;
        Result := bands;
      finally Reread.Free; end;
    finally Bmp.Free; G.Free; end;
  end;
begin
  AssertEquals('no-wrap single ink band', 1, InkBands(False));
  AssertTrue('word-wrap produces >1 ink band', InkBands(True) >= 2);
end;

{ Pure-CJK text carries no spaces, so a space-only word-wrap treats the whole
  run as one unbreakable word and it overflows a narrow label -- exactly what
  clipped the Chinese card descriptions at modern density. WordWrap must break
  between CJK characters. Measured headlessly via the public MeasureCaption:
  at a width well under the single-line extent the wrapped block must be taller
  (more than one line) and each line must stay within the constraint. }
{ The wrapper only knew about spaces and CJK codepoints, so a caption carrying an explicit
  line break came out as ONE run: WordWrap silently swallowed every line the author wrote.
  TTyNotification looked correct only because its caller pre-split the message on CR/LF.

  The measurement has to be CONSTRAINED to exercise it: MeasureCaption only calls the wrapper
  when AAvailWidthPx > 0, and takes `Lines.Text := caption` otherwise -- which splits on
  authored breaks all by itself. Aiming an unconstrained measurement at this bug tests the
  path that never had it. The width used here is deliberately generous, so the joined
  'one two' fits on a single line and any extra height can only come from the break. }
{ The wrapper only knew about spaces and CJK codepoints, so a caption carrying an explicit
  line break came out as ONE run: WordWrap silently swallowed every line the author wrote.
  TTyNotification looked correct only because its caller pre-split the message on CR/LF.

  Driven through TyWrapTextCJK, the shared algorithm, rather than through MeasureCaption:
  MeasureCaption only reaches the wrapper when AAvailWidthPx > 0 and takes
  `Lines.Text := caption` otherwise -- which honours authored breaks by itself -- so an
  unconstrained measurement tests the path that never had the bug. (TTyLabel.WrapText is
  private, and it is a one-line forward to this function anyway.) }
procedure TLabelTest.TestWordWrapKeepsAuthoredLineBreaks;
var
  bmp: TBitmap;
  L: TStringList;
begin
  bmp := TBitmap.Create;
  L := TStringList.Create;
  try
    bmp.SetSize(8, 8);
    bmp.Canvas.Font.Name := 'Tahoma';
    bmp.Canvas.Font.Size := 9;

    TyWrapTextCJK('one' + LineEnding + 'two', 400, bmp.Canvas, L);
    AssertEquals('an authored break makes two lines', 2, L.Count);
    AssertEquals('first', 'one', L[0]);
    AssertEquals('second', 'two', L[1]);

    L.Clear;
    TyWrapTextCJK('a' + LineEnding + 'b' + LineEnding + 'c', 400, bmp.Canvas, L);
    AssertEquals('three authored lines stay three', 3, L.Count);

    L.Clear;
    TyWrapTextCJK('one' + LineEnding + LineEnding + 'two', 400, bmp.Canvas, L);
    AssertEquals('a blank line between paragraphs is content', 3, L.Count);
    AssertEquals('and it is the empty one', '', L[1]);

    L.Clear;
    TyWrapTextCJK('aaa bbb ccc ddd eee fff ggg hhh', 40, bmp.Canvas, L);
    AssertTrue('width still folds a long segment', L.Count > 1);
  finally
    L.Free;
    bmp.Free;
  end;
end;

procedure TLabelTest.TestWordWrapCJK;
var
  L: TTyLabel;
  w1, h1, wN, hN, cap: Integer;
begin
  L := TTyLabel.Create(nil);
  try
    L.Font.PixelsPerInch := 96;
    L.WordWrap := True;
    L.Caption := '积压任务徽标挂在按钮上不是按钮内置的';  // 18 CJK glyphs, no spaces
    L.MeasureCaption(96, 0, w1, h1);          // unconstrained -> single line
    AssertTrue('CJK single-line width measured', w1 > 0);
    cap := w1 div 3;                          // ~6 glyphs wide
    L.MeasureCaption(96, cap, wN, hN);        // constrained -> must wrap
    AssertTrue('CJK wraps: constrained block spans multiple lines', hN > h1 + 4);
    AssertTrue('CJK wraps: each line bounded by the width constraint',
      wN <= cap + (w1 div 18) + 4);           // + one glyph slack
  finally
    L.Free;
  end;
end;

{ Under WordWrap the whole wrapped block must be positioned per Layout. In a tall
  control a short caption wraps to fewer lines than the height, so tlBottom's ink
  centroid sits lower than tlTop's. }
procedure TLabelTest.TestWordWrapLayoutBottom;
  function WrapCentroidY(L: TTextLayout): Double;
  var
    G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap;
    x, y, n: Integer; sy: Double; px: TBGRAPixel;
  begin
    G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
    try
      G.Font.PixelsPerInch := 96;
      G.WordWrap := True;
      G.Layout := L;
      // Wraps to ~2 lines at width 60, well short of the 120px tall control.
      G.Caption := 'one two three four';
      Bmp.PixelFormat := pf32bit; Bmp.SetSize(60, 120);
      Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 60, 120);
      G.RenderTo(Bmp.Canvas, Rect(0, 0, 60, 120), 96);
      Reread := TBGRABitmap.Create(Bmp);
      try
        sy := 0; n := 0;
        for x := 0 to 59 do for y := 0 to 119 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.red < 160) and (px.green < 160) then
          begin sy := sy + y; Inc(n); end;
        end;
        if n = 0 then Result := -1 else Result := sy / n;
      finally Reread.Free; end;
    finally Bmp.Free; G.Free; end;
  end;
var
  topY, bottomY: Double;
begin
  topY := WrapCentroidY(tlTop);
  bottomY := WrapCentroidY(tlBottom);
  AssertTrue('wrapped tlTop ink present', topY > 0);
  AssertTrue('wrapped tlBottom block sits lower than tlTop', bottomY > topY + 15);
end;

procedure TLabelTest.TestFocusControlOnClick;
var
  L: TTyLabelAccess; E: TFocusProbe;
begin
  E := TFocusProbe.Create(nil);
  L := TTyLabelAccess.Create(nil);
  try
    L.FocusControl := E;
    AssertSame('FocusControl round-trips', TWinControl(E), L.FocusControl);
    AssertFalse('not focused before click', E.Focused_);
    L.DoClick;
    AssertTrue('clicking label focuses the FocusControl (CanFocus path)', E.Focused_);

    // No target: Click must be a safe no-op.
    L.FocusControl := nil;
    L.DoClick;
    AssertTrue('click with nil FocusControl does not raise', True);
  finally
    L.Free;
    E.Free;
  end;
end;

procedure TLabelTest.TestTransparentDefault;
var
  L: TTyLabel;
  G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap; px: TBGRAPixel;
begin
  L := TTyLabel.Create(nil);
  try
    AssertTrue('Transparent default is True', L.Transparent);
  finally
    L.Free;
  end;

  // Default (transparent): a white backdrop shows through where there is no text.
  G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
  try
    G.Font.PixelsPerInch := 96;
    G.Caption := '';
    Bmp.PixelFormat := pf32bit; Bmp.SetSize(80, 24);
    Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 80, 24);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 80, 24), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      px := Reread.GetPixel(40, 12);
      AssertTrue('transparent label leaves backdrop white', (px.red > 240) and (px.green > 240) and (px.blue > 240));
    finally Reread.Free; end;
  finally Bmp.Free; G.Free; end;
end;

{ Vertical extent of the caption ink for a label rendered at 200x100: the first and last row
  carrying dark pixels. The question these two tests ask is how far down the text reaches. }
procedure RenderInkSpan(const ACaption: string; out ATop, ABottom: Integer);
var
  G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap;
  x, y: Integer; px: TBGRAPixel; inked: Boolean;
begin
  ATop := -1; ABottom := -1;
  G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
  try
    G.Caption := ACaption; G.Font.PixelsPerInch := 96;
    Bmp.PixelFormat := pf32bit; Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 200, 100);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 100), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      for y := 0 to 99 do
      begin
        inked := False;
        for x := 0 to 199 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.red < 160) and (px.green < 160) then
          begin inked := True; Break; end;
        end;
        if inked then
        begin
          if ATop < 0 then ATop := y;
          ABottom := y;
        end;
      end;
    finally Reread.Free; end;
  finally Bmp.Free; G.Free; end;
end;

procedure TLabelTest.TestAuthoredBreakRendersASecondLine;
{ MeasureCaption has always counted the author's line breaks as lines, so an AutoSize label
  was already given room for them — but the draw forced SingleLine and ran them together, so
  the room went to nothing and the second line was never on screen. Same label, same box,
  one caption with a break and one without: the broken one must reach further down. }
var
  t1, b1, t2, b2: Integer;
begin
  RenderInkSpan('Ay', t1, b1);
  RenderInkSpan('Ay' + LineEnding + 'Ay', t2, b2);
  AssertTrue('the one-line caption inked something to compare against', b1 > 0);
  AssertTrue(Format('a break reaches further down (%d vs %d)', [b2, b1]), b2 > b1);
  AssertTrue(Format('and starts higher — the block is centred (%d vs %d)', [t2, t1]),
    t2 < t1);
end;

procedure TLabelTest.TestLineHeightTokenSizesTheCaptionBlock;
{ The line box a multi-line caption sits on must be the THEME's to set, and derived rather
  than floored: a theme asking for more leading gets a taller block, and one asking for less
  gets a shorter one. Everything else about the rule is held constant across the three
  loads, so only --line-height can explain the numbers. }
const
  cRule = 'TyLabel { background: #FFFFFF; color: #000000; border-width: 0px; ' +
          'padding: 0px 0px; font-size: 12px; }';
var
  Ctl: TTyStyleController;
  L: TTyLabel;
  w, hNat, h40, h6: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    L := TTyLabel.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;
      L.Caption := 'one' + LineEnding + 'two';

      Ctl.LoadThemeCss(cRule);
      L.MeasureCaption(96, 0, w, hNat);

      Ctl.LoadThemeCss(':root { --line-height: 40px; }' + cRule);
      L.MeasureCaption(96, 0, w, h40);

      Ctl.LoadThemeCss(':root { --line-height: 6px; }' + cRule);
      L.MeasureCaption(96, 0, w, h6);

      AssertTrue('unset, the block is the font own two line boxes', hNat > 0);
      AssertEquals('two lines on a 40px line box', 80, h40);
      AssertTrue(Format('which is taller than unset (%d vs %d)', [h40, hNat]), h40 > hNat);
      AssertEquals('two lines on a 6px line box', 12, h6);
      AssertTrue(Format('a theme that shrinks the line box lowers the block (%d vs %d)',
        [h6, hNat]), h6 < hNat);
    finally
      L.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

{ TLabelSizeFloorTest }

procedure TLabelSizeFloorTest.TestMinimumFitsTheCaption;
{ The floor covers the block the label must draw, and an impossible request is clamped up
  instead of silently cutting the bottom off the text. }
var
  F: TForm;
  L: TTyLabel;
  w, h: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    L := TTyLabel.Create(F);
    L.Parent := F;
    L.Font.PixelsPerInch := 96;
    L.Caption := '新建';
    L.MeasureCaption(96, 0, w, h);

    AssertTrue('the height floor covers the measured block', L.Constraints.MinHeight >= h);

    L.Height := 2;
    L.Width := 2;
    AssertTrue('a too-short request is clamped up', L.Height >= h);
  finally
    F.Free;
  end;
end;

procedure TLabelSizeFloorTest.TestMinimumIsThePreferredSize;
{ HEIGHT only, and the height IS the preferred height: the label already measures its own
  block plus the padding RenderTo insets by, and a second copy of that sum is a second thing
  that can drift from what gets drawn.

  There is deliberately NO width floor, wrapping or not. Clipping a caption vertically is
  never what anyone wanted -- that is the bug this floor exists to stop -- but being NARROWER
  than the text is ordinary for a label: it ellipsises, and a status strip or a fixed column
  showing 'Some very long value...' is a layout, not a mistake. A width floor would silently
  overrule the Width its host set. (Buttons are the opposite case and DO floor their width:
  there the caption is the affordance, and an ellipsised button label is a usability failure.) }
var
  Ctl: TTyStyleController;
  L: TTyLabelAccess;
  pw, ph: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  L := TTyLabelAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyLabel { font-size: 12px; padding: 5px 7px; }');
    L.Controller := Ctl;
    L.Font.PixelsPerInch := 96;
    L.Caption := 'Measured once';
    L.Invalidate;

    pw := 0; ph := 0;
    L.CallPreferredSize(pw, ph);
    AssertEquals('the height floor IS the preferred height', ph, L.Constraints.MinHeight);
    AssertEquals('and there is no width floor', 0, L.Constraints.MinWidth);
    AssertTrue('sanity: the preferred width was actually computed', pw > 0);
  finally
    L.Free;
    Ctl.Free;
  end;
end;

procedure TLabelSizeFloorTest.TestWrappingLabelHasNoWidthFloor;
{ A wrapping label is MEANT to be narrower than its text: flooring it at the widest line
  would make wrapping impossible. The message dialog is the case that proves it — it measures
  the block at a column it picks and then pins that column, so a width floor would snap it
  back into the single-line ribbon it used to be. Caption first, WordWrap second: that is the
  order the dialog builds it in, and the order in which a stale floor would bite. }
var
  F: TForm;
  L: TTyLabel;
begin
  F := TForm.CreateNew(nil);
  try
    L := TTyLabel.Create(F);
    L.Parent := F;
    L.Font.PixelsPerInch := 96;
    L.Caption := 'The operation could not be completed because the destination folder is '
      + 'read-only and the source file is still open in another application.';
    L.WordWrap := True;
    AssertEquals('a wrapping label publishes no width floor', 0, L.Constraints.MinWidth);
    L.Width := 120;
    AssertEquals('so a narrow column sticks', 120, L.Width);
  finally
    F.Free;
  end;
end;

procedure TLabelSizeFloorTest.TestWrappingFloorDoesNotMoveWithTheWidth;
{ The height floor of a wrapping label is the block measured WITHOUT wrapping — the one thing
  about a wrapped block that does not move with the width, since a width can only ADD breaks.
  Flooring at the block AT THE CURRENT WIDTH would be a different number for every width, so
  a caller that sets width and height in one SetBounds (the message dialog again) would be
  clamped by a height measured at the width the label had a moment ago. }
var
  F: TForm;
  L: TTyLabel;
  wide, narrow, oneLineW, oneLineH: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    L := TTyLabel.Create(F);
    L.Parent := F;
    L.Font.PixelsPerInch := 96;
    L.WordWrap := True;
    L.Caption := 'A caption long enough that a narrow label has to break it into several '
      + 'lines, and a wide one does not.';

    L.Width := 400;
    L.Invalidate;
    wide := L.Constraints.MinHeight;
    L.Width := 60;                       // now it wraps into many lines
    L.Invalidate;
    narrow := L.Constraints.MinHeight;
    AssertEquals('the wrap floor does not move with the width', wide, narrow);

    { It is still a real floor: one line of ink must fit, whatever the width. }
    L.MeasureCaption(96, 0, oneLineW, oneLineH);
    AssertTrue('and it still covers one line', narrow >= oneLineH);
    L.Height := 1;
    AssertTrue('so a 1px wrapping label is clamped up', L.Height >= oneLineH);
  finally
    F.Free;
  end;
end;

procedure TLabelSizeFloorTest.TestSmallerFontLowersTheMinimum;
{ The floor is DERIVED, not a wall: shrink the font and the padding in the theme and the
  minimum shrinks with them. That is what makes "override the CSS if you want it smaller" a
  coherent answer instead of a refusal. }
var
  F: TForm;
  Ctl: TTyStyleController;
  L: TTyLabel;
  big, small: Integer;
begin
  F := TForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    L := TTyLabel.Create(F);
    L.Parent := F;
    L.Controller := Ctl;
    L.Caption := '新建';

    Ctl.LoadThemeCss('TyLabel { color: #000000; font-size: 20px; padding: 8px; }');
    L.Invalidate;
    big := L.Constraints.MinHeight;

    Ctl.LoadThemeCss('TyLabel { color: #000000; font-size: 8px; padding: 0px; }');
    L.Invalidate;
    small := L.Constraints.MinHeight;

    AssertTrue(Format('a smaller font + padding lowers the floor (%d -> %d)', [big, small]),
      small < big);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TLabelSizeFloorTest.TestMinimumSurvivesAHeightPinningParent;
{ A label can sit on a tool bar, and the bar pins every child to its ButtonHeight. A control
  that answers back with a height of its own bounced against that until LCL aborted with
  "ChangeBounds loop detected" — the demo died at startup. Constraints clamp inside SetBounds
  with no negotiation. Reaching the end of this test IS the assertion. }
var
  F: TForm;
  Bar: TTyToolBar;
  L: TTyLabel;
begin
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.ButtonHeight := 40;
    L := TTyLabel.Create(Bar);
    L.Parent := Bar;
    L.Caption := '新建';
    L.AutoSize := True;
    Bar.ButtonHeight := 41;              // a loop would abort the process here
    AssertTrue('the bar asks for a height the floor can honour',
      L.Constraints.MinHeight <= 40);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TLabelTest);
  RegisterTest(TLabelSizeFloorTest);
end.
