unit test.toolbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ToolBar, tyControls.Button;
type
  TToolBarGeomTest = class(TTestCase)
  published
    procedure TestLayoutSingleRow;
    procedure TestLayoutWraps;
  end;

  { The FORCED row division (TyToolbarLayout's ABreakBefore) — the input TToolButton.Wrap
    needs and the width rule alone can never express. }
  TToolBarBreakTest = class(TTestCase)
  private
    procedure AssertSameLayout(const AWhat: string;
      const AExpect, AGot: TTyRectArray; AExpectRows, AGotRows: Integer);
  published
    procedure TestNoBreakMatchesLegacySignature;
    procedure TestForcedBreakStartsNewRowEvenWhenItFits;
    procedure TestBreakOnFirstItemIsNoOp;
    procedure TestBreakRebasesTheWidthWrap;
    procedure TestBreakWorksWhenNotWrapable;
    procedure TestShortBreakArrayReadsAsFalse;
    procedure TestLclWrapAfterMapsOntoBreakBefore;
  end;

  TTyToolBarAccess = class(TTyToolBar)
  public
    procedure ForceLayout;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TToolBarControlTest = class(TTestCase)
  published
    procedure TestArrangesButtons;
  end;

  TToolBarPixelTest = class(TTestCase)
  published
    procedure TestBottomHairlineIsLighterThanBody;
  end;

implementation

{ TTyToolBarAccess }
procedure TTyToolBarAccess.ForceLayout;
var dummy: TRect;
begin
  // AlignControls uses ClientWidth internally (it ignores the ARect arg); in the headless
  // runner ClientWidth matches TB.Width, so positions are deterministic.
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;

procedure TTyToolBarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;
procedure TToolBarGeomTest.TestLayoutSingleRow;
var r: TTyRectArray; rows: Integer;
begin
  // two 40x20 items, indent 4, top pad 4, spacing 2, buttonHeight 24, bar 200 wide.
  // Indent (horizontal) and the top pad are separate arguments now -- they used to be one,
  // which is why an indented bar was also a padded, taller one.
  r := TyToolbarLayout([Size(40,20), Size(40,20)], 200, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 1, rows);
  AssertEquals('i0.left', 4, r[0].Left);     AssertEquals('i0.right', 44, r[0].Right);
  AssertEquals('i1.left', 46, r[1].Left);    AssertEquals('i1.right', 86, r[1].Right);
  AssertEquals('i0.height=buttonHeight', 24, r[0].Bottom - r[0].Top);
end;
procedure TToolBarGeomTest.TestLayoutWraps;
var r: TTyRectArray; rows: Integer;
begin
  // bar only 90 wide -> third item wraps to row 2
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], 90, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('i2 wrapped to indent', 4, r[2].Left);
  AssertEquals('i2.Top = TOP PAD + buttonHeight + spacing', 30, r[2].Top);
end;

{ TToolBarBreakTest }

procedure TToolBarBreakTest.AssertSameLayout(const AWhat: string;
  const AExpect, AGot: TTyRectArray; AExpectRows, AGotRows: Integer);
var
  i: Integer;
begin
  AssertEquals(AWhat + ': item count', Length(AExpect), Length(AGot));
  AssertEquals(AWhat + ': rows', AExpectRows, AGotRows);
  for i := 0 to High(AExpect) do
  begin
    AssertEquals(Format('%s: r[%d].Left', [AWhat, i]), AExpect[i].Left, AGot[i].Left);
    AssertEquals(Format('%s: r[%d].Top', [AWhat, i]), AExpect[i].Top, AGot[i].Top);
    AssertEquals(Format('%s: r[%d].Right', [AWhat, i]), AExpect[i].Right, AGot[i].Right);
    AssertEquals(Format('%s: r[%d].Bottom', [AWhat, i]), AExpect[i].Bottom, AGot[i].Bottom);
  end;
end;

procedure TToolBarBreakTest.TestNoBreakMatchesLegacySignature;
const
  { Includes a degenerate 0-wide bar and a bar narrower than one item, because those are the
    inputs where a rewritten wrap condition is most likely to drift. }
  BarWidths: array[0..4] of Integer = (0, 33, 46, 90, 200);
  { Four width profiles: uniform, one over-wide item mid-run, all-too-wide, and a trailing
    monster after three tiny ones. }
  Profiles: array[0..3, 0..3] of Integer = (
    (40, 40, 40, 40),
    (10, 100, 10, 10),
    (60, 60, 60, 60),
    (5,  5,   5,  200));
var
  pi_, bi, ni, mi, i: Integer;
  sizes: array of TSize;
  allFalse, emptyBrk: array of Boolean;
  legacy, viaEmpty, viaFalse: TTyRectArray;
  rowsL, rowsE, rowsF: Integer;
  wrapable: Boolean;
  indent, pad, spacing, bh: Integer;
  tag: string;
begin
  { BYTE-IDENTITY GUARD. Every existing toolbar in the suite goes through the break-free
    entry point, so the one thing this change must not do is move a single pixel when no flag
    is set. The two forms are compared rect-field for rect-field (and on ARows, which is what
    the bar's auto-grown HEIGHT is computed from) across a matrix: 2 metric sets x 4 width
    profiles x 5 bar widths x item counts 0..4 x both Wrapable states = 800 layouts.
    Both "no array at all" and "an array of all False" are checked -- they reach the rule by
    different paths (a short-array read vs. a real False) and only one of them can be got
    wrong. }
  emptyBrk := nil;
  for mi := 0 to 1 do
  begin
    if mi = 0 then begin indent := 4;  pad := 4; spacing := 2; bh := 24; end
              else begin indent := 20; pad := 3; spacing := 0; bh := 38; end;
    for pi_ := 0 to High(Profiles) do
      for bi := 0 to High(BarWidths) do
        for ni := 0 to 4 do
          for wrapable := False to True do
          begin
            SetLength(sizes, ni);
            SetLength(allFalse, ni);
            for i := 0 to ni - 1 do
            begin
              sizes[i].cx := Profiles[pi_][i mod 4];
              sizes[i].cy := 20;
              allFalse[i] := False;
            end;
            tag := Format('profile%d/bar%d/n%d/wrapable%d/metrics%d',
              [pi_, BarWidths[bi], ni, Ord(wrapable), mi]);
            legacy   := TyToolbarLayout(sizes, BarWidths[bi], indent, pad, spacing, bh, wrapable, rowsL);
            viaEmpty := TyToolbarLayout(sizes, emptyBrk, BarWidths[bi], indent, pad, spacing, bh, wrapable, rowsE);
            viaFalse := TyToolbarLayout(sizes, allFalse, BarWidths[bi], indent, pad, spacing, bh, wrapable, rowsF);
            AssertSameLayout(tag + ' [empty break array]', legacy, viaEmpty, rowsL, rowsE);
            AssertSameLayout(tag + ' [all-False break array]', legacy, viaFalse, rowsL, rowsF);
          end;
  end;
end;

procedure TToolBarBreakTest.TestForcedBreakStartsNewRowEvenWhenItFits;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { Three 40px tools on a 200px bar all fit on one row -- TestLayoutSingleRow's arithmetic with
    one more tool. A break on tool 1 must move it down ANYWAY. That is the whole point of the
    parameter: a division the width never demanded. }
  SetLength(brk, 3);
  brk[0] := False; brk[1] := True; brk[2] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('i0 stays on row 1, at the indent', 4, r[0].Left);
  AssertEquals('i0.Top = top pad', 4, r[0].Top);
  AssertEquals('i1 restarts at the indent', 4, r[1].Left);
  AssertEquals('i1.Top = pad + buttonHeight + spacing', 30, r[1].Top);
  AssertEquals('i2 follows i1 on the NEW row', 46, r[2].Left);
  AssertEquals('i2 shares i1''s row', 30, r[2].Top);
end;

procedure TToolBarBreakTest.TestBreakOnFirstItemIsNoOp;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { There is no row above the first tool to leave, so a break on it is ignored rather than
    opening an empty leading row. An empty row would be visible twice over: a blank band at the
    top, AND a bar one button-height taller, because ARows is exactly what AlignControls sizes
    the bar from (padY*2 + rows*bh + (rows-1)*spacing). }
  SetLength(brk, 2);
  brk[0] := True; brk[1] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20)], brk, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('still ONE row -- no empty leading row', 1, rows);
  AssertEquals('i0.Left', 4, r[0].Left);
  AssertEquals('i0.Top = top pad, not pad + a row', 4, r[0].Top);
  AssertEquals('i1.Left', 46, r[1].Left);
  AssertEquals('i1.Top', 4, r[1].Top);
end;

procedure TToolBarBreakTest.TestBreakRebasesTheWidthWrap;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { The same bar as TestLayoutWraps -- 90 wide, three 40px tools -- where the WIDTH alone puts
    tool 2 on row 2. Break tool 1 instead and the two rules compose: tool 1 opens row 2, which
    re-bases x to the indent, so tool 2 now FITS beside it and the width rule does not fire at
    all. A break that inserted a row without re-basing x would strand tool 2 on a third row,
    which is the failure this pins. }
  SetLength(brk, 3);
  brk[0] := False; brk[1] := True; brk[2] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 90, 4, 4, 2, 24, True, rows);
  AssertEquals('two rows, not three', 2, rows);
  AssertEquals('i1 opened row 2 at the indent', 4, r[1].Left);
  AssertEquals('i1.Top', 30, r[1].Top);
  AssertEquals('i2 fits beside i1 on row 2', 46, r[2].Left);
  AssertEquals('i2.Top', 30, r[2].Top);
end;

procedure TToolBarBreakTest.TestBreakWorksWhenNotWrapable;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { AWrapable=False is LCL's "no automatic wrap" mode, and it is the ONLY mode in which LCL
    reads TToolButton.Wrap at all (toolbar.inc:1003, `if not Wrapable and ... Wrap`). So the
    break must be live here even though the width rule is dead.
    First half: confirm the width rule really is off -- three 40px tools on a 90px bar stay on
    one row and the last one overhangs. Without this the second half would pass for the wrong
    reason. }
  SetLength(brk, 3);
  brk[0] := False; brk[1] := False; brk[2] := False;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 90, 4, 4, 2, 24, False, rows);
  AssertEquals('width rule off: one row', 1, rows);
  AssertEquals('i2 overhangs rather than wrapping', 88, r[2].Left);
  AssertEquals('i2 stayed on row 1', 4, r[2].Top);

  brk[2] := True;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 90, 4, 4, 2, 24, False, rows);
  AssertEquals('the break divides even with the width rule off', 2, rows);
  AssertEquals('i2 opened row 2', 4, r[2].Left);
  AssertEquals('i2.Top', 30, r[2].Top);
  AssertEquals('i1 was left where it was', 46, r[1].Left);
  AssertEquals('i1.Top', 4, r[1].Top);
end;

procedure TToolBarBreakTest.TestShortBreakArrayReadsAsFalse;
var
  r: TTyRectArray; rows: Integer; brk: array of Boolean;
begin
  { The flag array is parallel to the item list but need not be as long -- the same tolerance
    TyCoolBarPack's ABreaks has. Two entries against three tools, with the True in the LAST
    supplied slot: a bound read as <= instead of < would run one past the end here, and a bound
    read as one too tight would drop the flag that IS supplied. }
  SetLength(brk, 2);
  brk[0] := False; brk[1] := True;
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], brk, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('the supplied break fired', 4, r[1].Left);
  AssertEquals('i1.Top', 30, r[1].Top);
  AssertEquals('the missing entry read as False -- no third row', 46, r[2].Left);
  AssertEquals('i2.Top', 30, r[2].Top);
end;

procedure TToolBarBreakTest.TestLclWrapAfterMapsOntoBreakBefore;
var
  r: TTyRectArray; rows, i: Integer;
  wrapAfter, breakBefore: array of Boolean;
begin
  { THE SHIFT, pinned. LCL's TToolButton.Wrap is TRAILING -- "the row breaks AFTER this button"
    -- because toolbar.inc applies it in the step-to-next-position, so it moves the NEXT
    control. This solver's flag is LEADING, matching TyCoolBarPack. The conversion is the one
    place TToolButton can go off by one, so here is the worked example it should copy:
        breakBefore[i] := (i > 0) and wrapAfter[i-1]
    Two things the mapping deliberately cannot express. It never produces breakBefore[0]:
    there is no button -1 to trail, and a leading break on tool 0 is a no-op regardless. And it
    DROPS wrapAfter on the last button: LCL still bumps FRowCount for that one and ends up
    reporting a row that has nothing on it. }
  SetLength(wrapAfter, 3);
  wrapAfter[0] := False; wrapAfter[1] := True; wrapAfter[2] := True;   // Wrap set on tools 1 and 2
  SetLength(breakBefore, Length(wrapAfter));
  for i := 0 to High(breakBefore) do
    breakBefore[i] := (i > 0) and wrapAfter[i - 1];
  AssertEquals('tool 0 can never carry a leading break', False, breakBefore[0]);
  AssertEquals('tool 1 does not either -- tool 0 had no Wrap', False, breakBefore[1]);
  AssertEquals('tool 1''s trailing Wrap becomes tool 2''s leading break', True, breakBefore[2]);

  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], breakBefore, 200, 4, 4, 2, 24, True, rows);
  AssertEquals('two rows -- the Wrap on the LAST tool adds none', 2, rows);
  AssertEquals('i0 on row 1', 4, r[0].Top);
  AssertEquals('i1 on row 1 -- its own Wrap breaks AFTER it', 4, r[1].Top);
  AssertEquals('i1.Left', 46, r[1].Left);
  AssertEquals('i2 opened row 2', 30, r[2].Top);
  AssertEquals('i2.Left', 4, r[2].Left);
end;

{ TToolBarControlTest }

procedure TToolBarControlTest.TestArrangesButtons;
var
  Form: TForm;
  TB: TTyToolBarAccess;
  B1, B2: TTyButton;
  ExpectedLeft: Integer;
begin
  // In headless LCL, Realign posts a deferred message that is never processed
  // without a message pump.  We use a thin probe subclass (TTyToolBarAccess)
  // that calls AlignControls directly, bypassing the deferred path.
  // Width is set explicitly so ClientWidth is a known bar width; AlignControls
  // uses ClientWidth internally (it ignores the ARect arg), so positions are deterministic.
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 200);

    TB := TTyToolBarAccess.Create(Form);
    TB.Parent := Form;
    // alNone: prevent LCL alignment engine from fighting our explicit bounds
    TB.Align := alNone;
    TB.Width := 300;
    TB.Indent := 4;
    TB.ButtonSpacing := 2;
    TB.ButtonHeight := 24;
    TB.Wrapable := True;

    B1 := TTyButton.Create(Form);
    B1.Parent := TB;
    B1.Width := 60;

    B2 := TTyButton.Create(Form);
    B2.Parent := TB;
    B2.Width := 60;

    // Direct synchronous layout call (probe exposes the protected AlignControls).
    // The dummy rect uses TB.Width so the bar-width is 300 and no wrapping occurs.
    TB.ForceLayout;

    // Button 1 should start at Indent; Button 2 right after: Indent + B1.Width + ButtonSpacing
    AssertEquals('b1.Left = indent', TB.Indent, B1.Left);
    ExpectedLeft := TB.Indent + B1.Width + TB.ButtonSpacing;
    AssertEquals('b2.Left = indent + b1.width + spacing', ExpectedLeft, B2.Left);
  finally
    Form.Free;
  end;
end;

{ TToolBarPixelTest }

procedure TToolBarPixelTest.TestBottomHairlineIsLighterThanBody;
{ Theme: background: #202020 (32,32,32), border-color: #404040 (64,64,64).
  Control: 200x30 toolbar. RenderTo draws the full body in #202020 and
  a 1px bottom hairline in #404040 (border-color).
  At PPI 96, Scale(BorderWidth=1) = 1px, so y=29 is the hairline row.
  Assert the bottom row (y=29) red channel > mid-body (y=15) red channel.
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  TB: TTyToolBarAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxBody, PxHairline: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyToolBar { background: #202020; border-color: #404040; border-width: 1px; }');

    TB := TTyToolBarAccess.Create(Form);
    TB.Parent := Form;
    TB.Controller := Ctl;
    TB.Align := alNone;
    TB.SetBounds(0, 0, 200, 30);
    TB.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 30);
    // Pre-fill white so background rendering is unambiguous (canvas default is undefined)
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 30);
    TB.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 30), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Mid-body pixel (x=10, y=15): should be dark #202020
      PxBody := Reread.GetPixel(10, 15);
      // Bottom hairline pixel (x=10, y=29): should be #404040 — lighter
      PxHairline := Reread.GetPixel(10, 29);

      AssertTrue(
        Format('body pixel should be dark (r=%d g=%d b=%d, expected < 60)',
          [PxBody.red, PxBody.green, PxBody.blue]),
        (PxBody.red < 60) and (PxBody.green < 60) and (PxBody.blue < 60));

      AssertTrue(
        Format('hairline rendered (hairline.red=%d, expected >=55)',
          [PxHairline.red]),
        PxHairline.red >= 55);

      AssertTrue(
        Format('bottom hairline should be lighter than body (hairline.red=%d > body.red=%d)',
          [PxHairline.red, PxBody.red]),
        PxHairline.red > PxBody.red);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TToolBarGeomTest);
  RegisterTest(TToolBarBreakTest);
  RegisterTest(TToolBarControlTest);
  RegisterTest(TToolBarPixelTest);
end.
