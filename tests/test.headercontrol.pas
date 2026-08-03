unit test.headercontrol;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller,
  tyControls.Base, tyControls.HeaderControl;
type
  TTyHeaderControlTest = class(TTestCase)
  private
    FForm: TForm;
    FHdr: TTyHeaderControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // model / API
    procedure TestTypeKey;
    procedure TestAddSectionReturnsIndex;
    procedure TestSectionAccessors;
    procedure TestMinWidthClamp;
    procedure TestDeleteSection;
    procedure TestToggleSortCycles;
    procedure TestToggleSortSingleColumn;
    // pure geometry — rects tile the width
    procedure TestRectsTileWidthLastAbsorbs;
    procedure TestRectsLastKeepsOwnWidthWhenOverfull;
    procedure TestRectsEmpty;
    procedure TestRectsClampNegative;
    // pure geometry — section at x
    procedure TestSectionAtXBoundaries;
    procedure TestSectionAtXOutOfRange;
    // pure geometry — resize edge detection
    procedure TestResizeEdgeWithinGrip;
    procedure TestResizeEdgeLastEdgeNotResizable;
    procedure TestResizeEdgeNearestWins;
    // sort triangle geometry
    procedure TestSortTriangleDirection;
    // interaction
    procedure TestClickTogglesSortAndFires;
    procedure TestResizeDragChangesWidth;
    procedure TestNonLeftUpEndsResize;
    procedure TestRenderSelectedRowAccent;
  end;

implementation

type
  THeaderAccess = class(TTyHeaderControl)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressDown(Shift: TShiftState; X, Y: Integer);
    procedure PressMove(Shift: TShiftState; X, Y: Integer);
    procedure PressUp(Shift: TShiftState; X, Y: Integer);
    procedure PressUpRight(Shift: TShiftState; X, Y: Integer);   // a RIGHT-button release
  end;

  TClickProbe = class
  public
    Count, LastIndex: Integer;
    constructor Create;
    procedure Handle(AHeader: TTyHeaderControl; AIndex: Integer);
  end;

  TResizeProbe = class
  public
    Count, LastIndex, LastWidth: Integer;
    constructor Create;
    procedure Handle(AHeader: TTyHeaderControl; AIndex, AWidth: Integer);
  end;

  { OnSectionTrack carries the drag PHASE as well; the phase-level guards live in
    test.parity.header, so this one only needs a handler of the right shape. }
  TTrackProbe = class
  public
    Count, LastIndex, LastWidth: Integer;
    LastState: TTyHeaderTrackState;
    constructor Create;
    procedure Handle(AHeader: TTyHeaderControl; AIndex, AWidth: Integer;
      AState: TTyHeaderTrackState);
  end;

function THeaderAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure THeaderAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure THeaderAccess.PressDown(Shift: TShiftState; X, Y: Integer);
begin
  MouseDown(mbLeft, Shift, X, Y);
end;

procedure THeaderAccess.PressMove(Shift: TShiftState; X, Y: Integer);
begin
  MouseMove(Shift, X, Y);
end;

procedure THeaderAccess.PressUp(Shift: TShiftState; X, Y: Integer);
begin
  MouseUp(mbLeft, Shift, X, Y);
end;

procedure THeaderAccess.PressUpRight(Shift: TShiftState; X, Y: Integer);
begin
  MouseUp(mbRight, Shift, X, Y);
end;

constructor TClickProbe.Create;
begin
  inherited Create;
  Count := 0; LastIndex := -99;
end;

procedure TClickProbe.Handle(AHeader: TTyHeaderControl; AIndex: Integer);
begin
  Inc(Count); LastIndex := AIndex;
end;

constructor TResizeProbe.Create;
begin
  inherited Create;
  Count := 0; LastIndex := -99; LastWidth := -99;
end;

procedure TResizeProbe.Handle(AHeader: TTyHeaderControl; AIndex, AWidth: Integer);
begin
  Inc(Count); LastIndex := AIndex; LastWidth := AWidth;
end;

constructor TTrackProbe.Create;
begin
  inherited Create;
  Count := 0; LastIndex := -99; LastWidth := -99; LastState := tsTrackBegin;
end;

procedure TTrackProbe.Handle(AHeader: TTyHeaderControl; AIndex, AWidth: Integer;
  AState: TTyHeaderTrackState);
begin
  Inc(Count); LastIndex := AIndex; LastWidth := AWidth; LastState := AState;
end;

{ TTyHeaderControlTest }

procedure TTyHeaderControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FHdr := TTyHeaderControl.Create(FForm);
  FHdr.Parent := FForm;
  FHdr.Font.PixelsPerInch := 96;   // pin PPI (macOS defaults to 72)
end;

procedure TTyHeaderControlTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyHeaderControlTest.TestTypeKey;
var Acc: THeaderAccess;
begin
  Acc := THeaderAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    AssertEquals('TyHeaderControl', Acc.StyleTypeKey);
  finally
    Acc.Free;
  end;
end;

procedure TTyHeaderControlTest.TestAddSectionReturnsIndex;
begin
  AssertEquals('first index 0', 0, FHdr.AddSection('Name', 120));
  AssertEquals('second index 1', 1, FHdr.AddSection('Size', 80));
  AssertEquals('third index 2', 2, FHdr.AddSection('Date', 100));
  AssertEquals('section count', 3, FHdr.SectionCount);
  AssertEquals('sec0 text', 'Name', FHdr.SectionText[0]);
  AssertEquals('sec1 width', 80, FHdr.SectionWidth[1]);
end;

procedure TTyHeaderControlTest.TestSectionAccessors;
var s: TTyHeaderSection;
begin
  FHdr.AddSection('A', 100);
  FHdr.SectionText[0] := 'Alpha';
  FHdr.SectionWidth[0] := 140;
  FHdr.Sort[0] := hsdDescending;
  AssertEquals('text set', 'Alpha', FHdr.SectionText[0]);
  AssertEquals('width set', 140, FHdr.SectionWidth[0]);
  AssertTrue('sort set', FHdr.Sort[0] = hsdDescending);
  s := FHdr.Sections[0];
  AssertEquals('record text', 'Alpha', s.Text);
  AssertEquals('record width', 140, s.Width);
end;

procedure TTyHeaderControlTest.TestMinWidthClamp;
begin
  FHdr.AddSection('A', 5);   // below the min
  AssertEquals('add clamps to min', TyHeaderMinSectionWidth, FHdr.SectionWidth[0]);
  FHdr.SectionWidth[0] := 2;  // below the min
  AssertEquals('set clamps to min', TyHeaderMinSectionWidth, FHdr.SectionWidth[0]);
end;

procedure TTyHeaderControlTest.TestDeleteSection;
begin
  FHdr.AddSection('A', 100);
  FHdr.AddSection('B', 100);
  FHdr.AddSection('C', 100);
  FHdr.DeleteSection(1);   // remove 'B'
  AssertEquals('count after delete', 2, FHdr.SectionCount);
  AssertEquals('idx0 still A', 'A', FHdr.SectionText[0]);
  AssertEquals('idx1 now C', 'C', FHdr.SectionText[1]);
end;

procedure TTyHeaderControlTest.TestToggleSortCycles;
begin
  FHdr.AddSection('A', 100);
  AssertTrue('starts none', FHdr.Sort[0] = hsdNone);
  FHdr.ToggleSort(0);
  AssertTrue('none -> asc', FHdr.Sort[0] = hsdAscending);
  FHdr.ToggleSort(0);
  AssertTrue('asc -> desc', FHdr.Sort[0] = hsdDescending);
  FHdr.ToggleSort(0);
  AssertTrue('desc -> asc', FHdr.Sort[0] = hsdAscending);
end;

procedure TTyHeaderControlTest.TestToggleSortSingleColumn;
begin
  FHdr.AddSection('A', 100);
  FHdr.AddSection('B', 100);
  FHdr.ToggleSort(0);          // A ascending
  FHdr.ToggleSort(1);          // B ascending, A must clear
  AssertTrue('A cleared when B sorts', FHdr.Sort[0] = hsdNone);
  AssertTrue('B ascending', FHdr.Sort[1] = hsdAscending);
end;

{ ── pure geometry: rects tile the width ── }

procedure TTyHeaderControlTest.TestRectsTileWidthLastAbsorbs;
var
  rects: TTyHeaderRectArray;
  client: TRect;
begin
  // 3 sections summing 60+70+40=170 in a 300px client -> last absorbs remainder.
  client := Rect(0, 0, 300, 26);
  rects := TyHeaderSectionRects([60, 70, 40], client);
  AssertEquals('3 rects', 3, Length(rects));
  AssertEquals('r0 left', 0, rects[0].Left);
  AssertEquals('r0 right', 60, rects[0].Right);
  AssertEquals('r1 left', 60, rects[1].Left);
  AssertEquals('r1 right', 130, rects[1].Right);
  AssertEquals('r2 left', 130, rects[2].Left);
  AssertEquals('r2 absorbs to client right', 300, rects[2].Right);
  // Rects are contiguous and cover the full client.
  AssertEquals('cover client left', client.Left, rects[0].Left);
  AssertEquals('cover client right', client.Right, rects[High(rects)].Right);
  // Top/bottom come from the client.
  AssertEquals('rect top', 0, rects[1].Top);
  AssertEquals('rect bottom', 26, rects[1].Bottom);
end;

procedure TTyHeaderControlTest.TestRectsLastKeepsOwnWidthWhenOverfull;
var
  rects: TTyHeaderRectArray;
begin
  // Sums 200+150=350 > client 300 -> last keeps its OWN width (overruns, no shrink).
  rects := TyHeaderSectionRects([200, 150], Rect(0, 0, 300, 26));
  AssertEquals('r0 right', 200, rects[0].Right);
  AssertEquals('r1 left', 200, rects[1].Left);
  AssertEquals('r1 keeps own width (overruns)', 350, rects[1].Right);
end;

procedure TTyHeaderControlTest.TestRectsEmpty;
var rects: TTyHeaderRectArray;
begin
  rects := TyHeaderSectionRects([], Rect(0, 0, 300, 26));
  AssertEquals('no rects for no sections', 0, Length(rects));
end;

procedure TTyHeaderControlTest.TestRectsClampNegative;
var rects: TTyHeaderRectArray;
begin
  // A negative width is treated as 0; the (last) section still absorbs remainder.
  rects := TyHeaderSectionRects([-10, 50], Rect(0, 0, 200, 26));
  AssertEquals('neg width -> 0 span', 0, rects[0].Right - rects[0].Left);
  AssertEquals('r1 left at 0', 0, rects[1].Left);
  AssertEquals('r1 absorbs to 200', 200, rects[1].Right);
end;

{ ── pure geometry: section at x ── }

procedure TTyHeaderControlTest.TestSectionAtXBoundaries;
var client: TRect;
begin
  // rects: [0,60) [60,130) [130,300]
  client := Rect(0, 0, 300, 26);
  AssertEquals('x=0 -> section 0', 0, TyHeaderSectionAtX([60, 70, 40], client, 0));
  AssertEquals('x=59 -> section 0', 0, TyHeaderSectionAtX([60, 70, 40], client, 59));
  // boundary at 60 belongs to the section on its RIGHT (half-open [60,130))
  AssertEquals('x=60 -> section 1', 1, TyHeaderSectionAtX([60, 70, 40], client, 60));
  AssertEquals('x=129 -> section 1', 1, TyHeaderSectionAtX([60, 70, 40], client, 129));
  AssertEquals('x=130 -> section 2', 2, TyHeaderSectionAtX([60, 70, 40], client, 130));
  AssertEquals('x=299 -> section 2', 2, TyHeaderSectionAtX([60, 70, 40], client, 299));
  // exact final right edge still maps to the last section
  AssertEquals('x=300 (edge) -> last', 2, TyHeaderSectionAtX([60, 70, 40], client, 300));
end;

procedure TTyHeaderControlTest.TestSectionAtXOutOfRange;
var client: TRect;
begin
  client := Rect(0, 0, 200, 26);
  AssertEquals('x<left -> -1', -1, TyHeaderSectionAtX([60, 40], client, -1));
  // widths under-fill so the last section absorbs to 200; x=201 is past it.
  AssertEquals('x>right -> -1', -1, TyHeaderSectionAtX([60, 40], client, 201));
end;

{ ── pure geometry: resize edge ── }

procedure TTyHeaderControlTest.TestResizeEdgeWithinGrip;
var client: TRect;
begin
  // rects: [0,60) [60,130) [130,300]; interior boundaries at x=60 and x=130.
  client := Rect(0, 0, 300, 26);
  AssertEquals('exactly on edge 60 -> section 0', 0,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 60, 4));
  AssertEquals('62 within grip of 60 -> section 0', 0,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 62, 4));
  AssertEquals('57 within grip of 60 -> section 0', 0,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 57, 4));
  AssertEquals('128 within grip of 130 -> section 1', 1,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 128, 4));
  AssertEquals('90 mid-cell, no edge -> -1', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 90, 4));
  AssertEquals('65 outside grip of 60 -> -1', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 65, 4));
end;

procedure TTyHeaderControlTest.TestResizeEdgeLastEdgeNotResizable;
var client: TRect;
begin
  // The final section's right edge (x=300 / client edge) is NOT a resize boundary.
  client := Rect(0, 0, 300, 26);
  AssertEquals('final client edge not resizable', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 300, 4));
  // Also the last section's own right edge when it absorbs remainder.
  AssertEquals('near final edge not resizable', -1,
    TyHeaderResizeEdgeAtX([60, 70, 40], client, 299, 4));
end;

procedure TTyHeaderControlTest.TestResizeEdgeNearestWins;
var client: TRect;
begin
  // Two boundaries 6px apart (at 60 and 66) with a big grip: nearest to x wins.
  // widths [60, 6, ...]; boundaries at 60 and 66.
  client := Rect(0, 0, 300, 26);
  AssertEquals('x=61 closest to 60 -> section 0', 0,
    TyHeaderResizeEdgeAtX([60, 6, 40, 40], client, 61, 10));
  AssertEquals('x=65 closest to 66 -> section 1', 1,
    TyHeaderResizeEdgeAtX([60, 6, 40, 40], client, 65, 10));
end;

{ ── sort triangle ── }

procedure TTyHeaderControlTest.TestSortTriangleDirection;
var
  cell: TRect;
  triA, triD: TTyHeaderTriangle;
begin
  cell := Rect(100, 0, 200, 26);
  triA := TyHeaderSortTriangle(cell, hsdAscending, 8);
  triD := TyHeaderSortTriangle(cell, hsdDescending, 8);
  // Ascending points UP: apex (index 2) is ABOVE the base (indices 0/1).
  AssertTrue('asc apex above base', triA[2].Y < triA[0].Y);
  // Descending points DOWN: apex (index 2) is BELOW the base.
  AssertTrue('desc apex below base', triD[2].Y > triD[0].Y);
  // The glyph sits in the right gutter of the cell.
  AssertTrue('triangle in right half of cell', triA[2].X > (cell.Left + cell.Right) div 2);
end;

{ ── interaction ── }

procedure TTyHeaderControlTest.TestClickTogglesSortAndFires;
var
  Acc: THeaderAccess;
  Probe: TClickProbe;
begin
  Acc := THeaderAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 26);
  Acc.AddSection('A', 100);
  Acc.AddSection('B', 100);
  Acc.AddSection('C', 100);
  Probe := TClickProbe.Create;
  try
    Acc.OnSectionClick := @Probe.Handle;
    // Click the MIDDLE of section 1 (x in [100,200), away from the boundary grips).
    Acc.PressDown([], 150, 12);
    Acc.PressUp([], 150, 12);
    AssertEquals('click fired once', 1, Probe.Count);
    AssertEquals('click index 1', 1, Probe.LastIndex);
    AssertTrue('section 1 sorted ascending', Acc.Sort[1] = hsdAscending);
    // A second click on the same section cycles asc -> desc.
    Acc.PressDown([], 150, 12);
    Acc.PressUp([], 150, 12);
    AssertEquals('click fired twice', 2, Probe.Count);
    AssertTrue('section 1 now descending', Acc.Sort[1] = hsdDescending);
  finally
    Probe.Free;
  end;
end;

procedure TTyHeaderControlTest.TestNonLeftUpEndsResize;
var Acc: THeaderAccess;
begin
  // A right-button-up mid-resize (the control holds MouseCapture, so it's delivered here too) must
  // END the resize — otherwise FResizing stays armed and a later button-less move keeps resizing.
  Acc := THeaderAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 26);
  Acc.AddSection('A', 100);
  Acc.AddSection('B', 100);
  Acc.AddSection('C', 100);
  Acc.PressDown([], 100, 12);          // grab boundary 0 -> resizing
  Acc.PressUpRight([], 100, 12);       // RIGHT-button up mid-drag -> must tear down the resize
  Acc.PressMove([], 200, 12);          // button-less move: if still armed it would widen section A
  AssertEquals('resize ended: section width unchanged by the button-less move', 100, Acc.SectionWidth[0]);
end;

procedure TTyHeaderControlTest.TestResizeDragChangesWidth;
var
  Acc: THeaderAccess;
  Probe: TResizeProbe;
  Track: TTrackProbe;
begin
  Acc := THeaderAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 26);
  Acc.AddSection('A', 100);    // boundary between A and B at x=100
  Acc.AddSection('B', 100);
  Acc.AddSection('C', 100);
  Probe := TResizeProbe.Create;
  Track := TTrackProbe.Create;
  try
    Acc.OnSectionResize := @Probe.Handle;
    Acc.OnSectionTrack := @Track.Handle;
    // Grab the boundary at x=100 (within grip) and drag +40 px to the right.
    Acc.PressDown([], 100, 12);
    Acc.PressMove([], 140, 12);
    AssertEquals('section A widened to 140', 140, Acc.SectionWidth[0]);
    // OnSectionTrack is the continuous one. OnSectionResize used to fire here too, so a
    // handler that did anything real -- re-query, relayout a grid, save a setting -- ran
    // once per mouse-move pixel.
    // Two calls by now: tsTrackBegin on the grab, tsTrackMove on the move. The phase
    // sequence itself is guarded in test.parity.header.
    AssertTrue('track fired during drag', Track.Count >= 2);
    AssertEquals('track width is 140', 140, Track.LastWidth);
    AssertTrue('the last track call is a MOVE', Track.LastState = tsTrackMove);
    AssertEquals('resize did NOT fire during the drag', 0, Probe.Count);
    Acc.PressUp([], 140, 12);
    AssertEquals('width persists after release', 140, Acc.SectionWidth[0]);
    AssertEquals('resize fires exactly once, on release', 1, Probe.Count);
    AssertEquals('resize index is 0', 0, Probe.LastIndex);
    AssertEquals('resize width is 140', 140, Probe.LastWidth);
    // Dragging below the minimum clamps.
    Acc.PressDown([], 140, 12);          // boundary now at x=140
    Acc.PressMove([], 140 - 200, 12);    // way left, past the min
    AssertEquals('clamps to min width', TyHeaderMinSectionWidth, Acc.SectionWidth[0]);
    Acc.PressUp([], 140 - 200, 12);
  finally
    Track.Free;
    Probe.Free;
  end;
end;

{ Render 3 sections; section 1 hovered. The hovered cell must paint the
  TyTreeHeaderSection:hover accent (blue) while a non-hovered cell does not. }
procedure TTyHeaderControlTest.TestRenderSelectedRowAccent;
var
  Ctl: TTyStyleController;
  Acc: THeaderAccess;
  F: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyTreeHeader { background: #101010; border-width: 0px; color: #CCCCCC; } ' +
      'TyTreeHeaderSection { background: none; color: #CCCCCC; } ' +
      'TyTreeHeaderSection:hover { background: #3B82F6; }');
    Acc := THeaderAccess.Create(F);
    Acc.Parent := F;
    Acc.Controller := Ctl;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(0, 0, 300, 26);
    Acc.AddSection('A', 100);
    Acc.AddSection('B', 100);
    Acc.AddSection('C', 100);
    // Hover section 1 (its cell spans x=[100,200)).
    Acc.PressMove([], 150, 12);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(300, 26);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 300, 26);
    Acc.RenderTo(Bmp.Canvas, Rect(0, 0, 300, 26), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Section 1 (hovered) — probe far from the caption glyphs.
      Px := Reread.GetPixel(180, 13);
      AssertTrue(Format('hovered section blue (R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]), (Px.blue > 180) and (Px.red < 120));
      // Section 0 (not hovered) — NOT the accent.
      Px := Reread.GetPixel(30, 13);
      AssertFalse(Format('non-hovered section not blue (R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]), (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyHeaderControlTest);
end.
