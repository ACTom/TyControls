unit test.parity.header;
{ API-PARITY guards for the two header defects, written against the LCL declarations
  they mirror:

    C:/lazarus/lcl/comctrls.pp:3956   THeaderSection — the OBJECT LCL's section events carry
    C:/lazarus/lcl/comctrls.pp:3991   THeaderSection.ImageIndex
    C:/lazarus/lcl/comctrls.pp:4021   TSectionTrackState = (tsTrackBegin, tsTrackMove, tsTrackEnd)
    C:/lazarus/lcl/comctrls.pp:4022   TCustomSectionTrackEvent  (HeaderControl, Section, Width, State)
    C:/lazarus/lcl/comctrls.pp:4025   TCustomSectionNotifyEvent (HeaderControl, Section)
    C:/lazarus/lcl/comctrls.pp:4037   TCustomHeaderControl.Images
    C:/lazarus/lcl/include/headercontrol.inc:236 / :255 / :300-301
                                      tsTrackBegin on grab, tsTrackMove per move,
                                      tsTrackEnd THEN SectionResize on release

  Defect 1 — the three section events carried the wrong things.
    OnSectionTrack is a CONTINUOUS event, and it could only report a width. A handler
    was therefore told the drag was somewhere in the middle of itself and had to guess
    the ends: "spin up a live preview when the drag starts, tear it down when it ends"
    — the one job a continuous event exists for — was not expressible. LCL says which
    phase each call is (comctrls.pp:4021), and hands the handler the header control
    rather than a bare TObject.

  Defect 2 — a column header could not show an icon.
    TTyColumn.ImageIndex (tyControls.Columns.pas:95) and TTyHeader.Images (:216) were
    both in the model and NEITHER was read by any header paint, so setting them in the
    Object Inspector did nothing at all. Worse, Images was typed TCustomImageList — an
    LCL native list our BGRA painters cannot draw — so even a paint that wanted to read
    it had nothing it could do with it.

  Everything here is headless: no shown form, no handle. The paint guards render
  through the controls' own RenderTo into an offscreen TBitmap, as the rest of the
  repo's pixel tests do. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.ImageCollection,
  tyControls.Columns, tyControls.ListView.Layout, tyControls.ListView,
  tyControls.HeaderControl;

type
  { Reaches the protected mouse seam. Mirrors THeaderAccess in test.headercontrol. }
  THeaderParityAccess = class(TTyHeaderControl)
  public
    procedure PressDown(X, Y: Integer);
    procedure PressMove(X, Y: Integer);
    procedure PressUp(X, Y: Integer);
  end;

  { One recorded call. Kind keeps track and resize in ONE array, which is what lets a
    test assert ORDER across the two streams — LCL fires tsTrackEnd and only then
    SectionResize (headercontrol.inc:300-301), and a handler that rebuilds a layout on
    resize while a preview is still up depends on that order. }
  THdrKind = (hkClick, hkTrack, hkResize);

  THdrRec = record
    Kind:   THdrKind;
    Header: TObject;      { the event's FIRST argument, as received }
    Index:  Integer;
    Width:  Integer;
    State:  TTyHeaderTrackState;
  end;

  { -----------------------------------------------------------------------
    Defect 1 — TTyHeaderControl's three section events
    ----------------------------------------------------------------------- }
  THeaderSectionEventParityTest = class(TTestCase)
  private
    FForm: TForm;
    FHdr:  THeaderParityAccess;
    FLog:  array of THdrRec;
    procedure HClick(AHeader: TTyHeaderControl; AIndex: Integer);
    procedure HResize(AHeader: TTyHeaderControl; AIndex, AWidth: Integer);
    procedure HTrack(AHeader: TTyHeaderControl; AIndex, AWidth: Integer;
      AState: TTyHeaderTrackState);
    procedure Log(AKind: THdrKind; AHeader: TObject; AIndex, AWidth: Integer;
      AState: TTyHeaderTrackState);
    function  Count(AKind: THdrKind): Integer;
    { The AN'th (0-based) entry of one stream. }
    function  Nth(AKind: THdrKind; AN: Integer): THdrRec;
    { Position in the WHOLE log of the AN'th entry of one stream, or -1. }
    function  PosOf(AKind: THdrKind; AN: Integer): Integer;
    { Position in the whole log of the first track entry in phase AState, or -1. }
    function  PosOfState(AState: TTyHeaderTrackState): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Grabbing a divider opens the drag with tsTrackBegin, carrying the width the
      section starts at — headercontrol.inc:236 }
    procedure TestTrackOpensWithBeginPhase;
    { Every width-changing move reports tsTrackMove — headercontrol.inc:255 }
    procedure TestTrackReportsMovePhaseDuringDrag;
    { Releasing closes the drag with tsTrackEnd and the settled width —
      headercontrol.inc:300 }
    procedure TestTrackClosesWithEndPhase;
    { tsTrackEnd comes BEFORE OnSectionResize — headercontrol.inc:300-301 }
    procedure TestTrackEndPrecedesResize;
    { A whole drag is Begin, Move.., End — in that order, each phase exactly where it
      belongs. This is the guard that a phase-less event cannot satisfy at all. }
    procedure TestWholeDragPhaseSequence;
    { Every one of the three events hands the handler the header CONTROL, typed —
      comctrls.pp:4022/4025 both take a TCustomHeaderControl, not a bare TObject. }
    procedure TestEveryEventCarriesTheHeaderControl;
    { The index is what identifies a section here: LCL passes a THeaderSection object,
      and every facet that object exposes is reachable from the index. }
    procedure TestIndexReachesTheSectionFacets;
  end;

  { -----------------------------------------------------------------------
    Defect 2 — the column-header icon
    ----------------------------------------------------------------------- }
  TListViewAccess = class(TTyListView)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TColumnHeaderIconParityTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl:  TTyStyleController;
    FColl: TTyImageCollection;
    FImgs: TTyVirtualImageList;
    FLV:   TListViewAccess;
    FBmp:  TBitmap;
    { Leftmost and rightmost x of CAPTION ink (near-black) inside column 0's header
      cell. Both ends, deliberately: an icon painted ON TOP of the caption also pushes
      the leftmost dark pixel right, so a left-edge-only assertion is blind to the very
      bug it is supposed to catch. When the caption really steps aside the whole string
      moves and the RIGHT end moves with it. (The same trap was found and pinned in the
      grid's TestHeaderCaptionIndentsForColumnImage.) }
    procedure CaptionInk(out ALeft, ARight: Integer);
    { True when any pure-red (the icon) pixel is inside column 0's header cell. }
    function  IconInk: Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Header.Images must be a list our painters can actually draw. It was declared
      TCustomImageList — an LCL native list that no TTyPainter path can consume — so
      the property was unusable by construction, not merely unread. }
    procedure TestHeaderImagesTakesOurImageList;
    { The headline: a column with ImageIndex >= 0 draws its icon in the header. }
    procedure TestColumnImageIndexDrawsAnIcon;
    { And the caption steps aside for it rather than being painted over. }
    procedure TestHeaderCaptionIndentsForColumnImage;
    { ImageIndex = -1 (the default) draws nothing — the property is opt-in, so a header
      that never sets it must look exactly as it always did. }
    procedure TestNoIconWhenImageIndexIsMinusOne;
    { With no Header.Images the control's SmallImages answers instead, which is what
      Delphi/LCL resolve TListColumn.ImageIndex against. }
    procedure TestSmallImagesAnswerWhenHeaderImagesUnset;
    { Header.Images WINS over SmallImages when both are set — otherwise the override
      is not an override. }
    procedure TestHeaderImagesOverridesSmallImages;
  end;

implementation

const
  { Column 0's header cell: 120 logical px wide, and the band is 24 high. Font.PixelsPerInch
    is pinned to 96 in SetUp so logical == device px and these are exact. }
  ColW    = 120;
  HdrH    = 24;
  CanvasW = 400;
  CanvasH = 300;

{ ---- THeaderParityAccess ---- }

procedure THeaderParityAccess.PressDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure THeaderParityAccess.PressMove(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure THeaderParityAccess.PressUp(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

{ ---- THeaderSectionEventParityTest ---- }

procedure THeaderSectionEventParityTest.Log(AKind: THdrKind; AHeader: TObject;
  AIndex, AWidth: Integer; AState: TTyHeaderTrackState);
var
  n: Integer;
begin
  n := Length(FLog);
  SetLength(FLog, n + 1);
  FLog[n].Kind   := AKind;
  FLog[n].Header := AHeader;
  FLog[n].Index  := AIndex;
  FLog[n].Width  := AWidth;
  FLog[n].State  := AState;
end;

procedure THeaderSectionEventParityTest.HClick(AHeader: TTyHeaderControl; AIndex: Integer);
begin
  Log(hkClick, AHeader, AIndex, 0, tsTrackBegin);
end;

procedure THeaderSectionEventParityTest.HResize(AHeader: TTyHeaderControl;
  AIndex, AWidth: Integer);
begin
  Log(hkResize, AHeader, AIndex, AWidth, tsTrackEnd);
end;

procedure THeaderSectionEventParityTest.HTrack(AHeader: TTyHeaderControl;
  AIndex, AWidth: Integer; AState: TTyHeaderTrackState);
begin
  Log(hkTrack, AHeader, AIndex, AWidth, AState);
end;

function THeaderSectionEventParityTest.Count(AKind: THdrKind): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FLog) do
    if FLog[i].Kind = AKind then Inc(Result);
end;

function THeaderSectionEventParityTest.Nth(AKind: THdrKind; AN: Integer): THdrRec;
var
  i, seen: Integer;
begin
  Result := Default(THdrRec);
  Result.Index := -99;
  Result.Width := -99;
  seen := 0;
  for i := 0 to High(FLog) do
    if FLog[i].Kind = AKind then
    begin
      if seen = AN then Exit(FLog[i]);
      Inc(seen);
    end;
end;

function THeaderSectionEventParityTest.PosOf(AKind: THdrKind; AN: Integer): Integer;
var
  i, seen: Integer;
begin
  Result := -1;
  seen := 0;
  for i := 0 to High(FLog) do
    if FLog[i].Kind = AKind then
    begin
      if seen = AN then Exit(i);
      Inc(seen);
    end;
end;

function THeaderSectionEventParityTest.PosOfState(AState: TTyHeaderTrackState): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FLog) do
    if (FLog[i].Kind = hkTrack) and (FLog[i].State = AState) then Exit(i);
end;

procedure THeaderSectionEventParityTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FHdr := THeaderParityAccess.Create(FForm);
  FHdr.Parent := FForm;
  FHdr.Font.PixelsPerInch := 96;       { logical == device px, so x=100 IS the boundary }
  FHdr.SetBounds(0, 0, 300, 26);
  FHdr.AddSection('Name', 100);        { boundary A|B at x = 100 }
  FHdr.AddSection('Size', 100);
  FHdr.AddSection('Kind', 100);
  FHdr.OnSectionClick  := @HClick;
  FHdr.OnSectionResize := @HResize;
  FHdr.OnSectionTrack  := @HTrack;
  SetLength(FLog, 0);
end;

procedure THeaderSectionEventParityTest.TearDown;
begin
  SetLength(FLog, 0);
  FreeAndNil(FForm);                   { owns FHdr }
  FHdr := nil;
end;

procedure THeaderSectionEventParityTest.TestTrackOpensWithBeginPhase;
begin
  FHdr.PressDown(100, 12);             { grab the A|B divider; no move yet }
  AssertEquals('grabbing a divider reports one track call', 1, Count(hkTrack));
  AssertTrue('and it is the BEGIN phase', Nth(hkTrack, 0).State = tsTrackBegin);
  AssertEquals('begin names section 0', 0, Nth(hkTrack, 0).Index);
  { LCL passes Section.FWidth (headercontrol.inc:167), i.e. the width the drag OPENS at,
    not a delta — a preview needs the starting number to draw its first frame. }
  AssertEquals('begin carries the starting width', 100, Nth(hkTrack, 0).Width);
  AssertEquals('resize does NOT fire on grab', 0, Count(hkResize));
end;

procedure THeaderSectionEventParityTest.TestTrackReportsMovePhaseDuringDrag;
var
  r: THdrRec;
begin
  FHdr.PressDown(100, 12);
  FHdr.PressMove(140, 12);             { +40 px }
  AssertTrue('a move adds a second track call', Count(hkTrack) >= 2);
  r := Nth(hkTrack, 1);
  AssertTrue('the second call is the MOVE phase', r.State = tsTrackMove);
  AssertEquals('move carries the live width', 140, r.Width);
  AssertEquals('move names section 0', 0, r.Index);
end;

procedure THeaderSectionEventParityTest.TestTrackClosesWithEndPhase;
var
  p: Integer;
  r: THdrRec;
begin
  FHdr.PressDown(100, 12);
  FHdr.PressMove(140, 12);
  FHdr.PressUp(140, 12);
  p := PosOfState(tsTrackEnd);
  AssertTrue('releasing reports an END phase', p >= 0);
  r := FLog[p];
  AssertEquals('end names section 0', 0, r.Index);
  AssertEquals('end carries the settled width', 140, r.Width);
  AssertTrue('END is the LAST track call of the drag',
    PosOf(hkTrack, Count(hkTrack) - 1) = p);
end;

procedure THeaderSectionEventParityTest.TestTrackEndPrecedesResize;
var
  endPos, resizePos: Integer;
begin
  FHdr.PressDown(100, 12);
  FHdr.PressMove(140, 12);
  FHdr.PressUp(140, 12);
  endPos    := PosOfState(tsTrackEnd);
  resizePos := PosOf(hkResize, 0);
  AssertTrue('END fired', endPos >= 0);
  AssertTrue('resize fired', resizePos >= 0);
  { headercontrol.inc:300-301 — SectionTrack(tsTrackEnd) then SectionResize. A preview
    torn down in the END handler must be gone before the resize handler relayouts, or
    the relayout measures a control that is still wearing the preview. }
  AssertTrue(Format('tsTrackEnd must precede OnSectionResize (end@%d resize@%d)',
    [endPos, resizePos]), endPos < resizePos);
end;

procedure THeaderSectionEventParityTest.TestWholeDragPhaseSequence;
var
  i, moves: Integer;
begin
  FHdr.PressDown(100, 12);
  FHdr.PressMove(120, 12);
  FHdr.PressMove(140, 12);
  FHdr.PressUp(140, 12);
  AssertTrue('at least begin + 2 moves + end', Count(hkTrack) >= 4);
  AssertTrue('first phase is BEGIN', Nth(hkTrack, 0).State = tsTrackBegin);
  AssertTrue('last phase is END',
    Nth(hkTrack, Count(hkTrack) - 1).State = tsTrackEnd);
  { Everything strictly between the ends is a MOVE — no second BEGIN, no early END. }
  moves := 0;
  for i := 1 to Count(hkTrack) - 2 do
  begin
    AssertTrue(Format('track call %d is a MOVE', [i]),
      Nth(hkTrack, i).State = tsTrackMove);
    Inc(moves);
  end;
  AssertTrue('both moves reported', moves >= 2);
  AssertEquals('exactly one resize for the whole drag', 1, Count(hkResize));
end;

procedure THeaderSectionEventParityTest.TestEveryEventCarriesTheHeaderControl;
var
  i: Integer;
begin
  FHdr.PressDown(100, 12);
  FHdr.PressMove(140, 12);
  FHdr.PressUp(140, 12);
  FHdr.PressDown(150, 12);             { a body click, away from any divider grip }
  FHdr.PressUp(150, 12);
  AssertTrue('click fired', Count(hkClick) > 0);
  AssertTrue('track fired', Count(hkTrack) > 0);
  AssertTrue('resize fired', Count(hkResize) > 0);
  for i := 0 to High(FLog) do
    AssertSame(Format('event %d carries the header control', [i]), FHdr, FLog[i].Header);
end;

procedure THeaderSectionEventParityTest.TestIndexReachesTheSectionFacets;
begin
  FHdr.PressDown(150, 12);             { section 1's body }
  FHdr.PressUp(150, 12);
  AssertEquals('one click', 1, Count(hkClick));
  AssertEquals('click names section 1', 1, Nth(hkClick, 0).Index);
  { LCL hands over a THeaderSection so the handler can read its Text / Width / sort
    state. Ours hands over the index; these are the same facets, one hop away. }
  AssertEquals('Text via the index', 'Size', FHdr.SectionText[Nth(hkClick, 0).Index]);
  AssertEquals('Width via the index', 100, FHdr.SectionWidth[Nth(hkClick, 0).Index]);
  AssertTrue('sort state via the index',
    FHdr.Sort[Nth(hkClick, 0).Index] = hsdAscending);
end;

{ ---- TListViewAccess ---- }

procedure TListViewAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ ---- TColumnHeaderIconParityTest ---- }

procedure TColumnHeaderIconParityTest.SetUp;
var
  src: TBGRABitmap;
  c: TTyColumn;
begin
  FCtl := TTyStyleController.Create(nil);
  { White plate, BLACK caption ink, no border: the icon is pure red and can never be
    confused with either. }
  FCtl.LoadThemeCss(
    'TyListView { background: #FFFFFF; color: #000000; border-width: 0px; } ' +
    'TyListViewHeader { background: #FFFFFF; color: #000000; } ' +
    'TyListViewHeaderSection { background: #FFFFFF; color: #000000; }');

  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, CanvasW, CanvasH);

  FColl := TTyImageCollection.Create(nil);
  src := TBGRABitmap.Create(16, 16, BGRA(255, 0, 0, 255));   { fully opaque red square }
  try
    FColl.AddBitmap('red', src);
  finally
    src.Free;
  end;
  FImgs := TTyVirtualImageList.Create(nil);
  FImgs.Names.Add('red');
  FImgs.Collection := FColl;          { a TTyVirtualImageList exposes nothing until Names is set }

  FLV := TListViewAccess.Create(FForm);
  FLV.Parent := FForm;
  FLV.Controller := FCtl;
  FLV.Font.PixelsPerInch := 96;
  FLV.SetBounds(0, 0, CanvasW, CanvasH);
  FLV.ViewStyle := lvsReport;
  FLV.ShowColumnHeaders := True;
  FLV.Header.Height := HdrH;
  c := FLV.Header.Columns.Add as TTyColumn;
  c.Text  := 'MMMM';                  { wide ink, so both ends of the string are easy to find }
  c.Width := ColW;
  c := FLV.Header.Columns.Add as TTyColumn;
  c.Text  := 'Size';
  c.Width := ColW;
  FLV.Items.Add;                      { one row, so the report body is not degenerate }

  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf32bit;
  FBmp.SetSize(CanvasW, CanvasH);
end;

procedure TColumnHeaderIconParityTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);                  { owns FLV }
  FLV := nil;
  FreeAndNil(FImgs);
  FreeAndNil(FColl);
  FreeAndNil(FCtl);
end;

procedure TColumnHeaderIconParityTest.CaptionInk(out ALeft, ARight: Integer);
var
  re: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
  hit: Boolean;
begin
  FBmp.Canvas.Brush.Color := clWhite;
  FBmp.Canvas.FillRect(Rect(0, 0, CanvasW, CanvasH));
  FLV.DoRenderTo(FBmp.Canvas, Rect(0, 0, CanvasW, CanvasH), 96);
  ALeft  := -1;
  ARight := -1;
  re := TBGRABitmap.Create(FBmp);
  try
    for x := 0 to ColW - 1 do
    begin
      hit := False;
      for y := 0 to HdrH - 1 do
      begin
        px := re.GetPixel(x, y);
        { Near-black only. The icon is (255,0,0), so its red channel excludes it. }
        if (px.red < 100) and (px.green < 100) and (px.blue < 100) then
        begin
          hit := True;
          Break;
        end;
      end;
      if hit then
      begin
        if ALeft < 0 then ALeft := x;
        ARight := x;
      end;
    end;
  finally
    re.Free;
  end;
end;

function TColumnHeaderIconParityTest.IconInk: Boolean;
var
  re: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := False;
  FBmp.Canvas.Brush.Color := clWhite;
  FBmp.Canvas.FillRect(Rect(0, 0, CanvasW, CanvasH));
  FLV.DoRenderTo(FBmp.Canvas, Rect(0, 0, CanvasW, CanvasH), 96);
  re := TBGRABitmap.Create(FBmp);
  try
    for x := 0 to ColW - 1 do
      for y := 0 to HdrH - 1 do
      begin
        px := re.GetPixel(x, y);
        if (px.red > 200) and (px.green < 80) and (px.blue < 80) then
          Exit(True);
      end;
  finally
    re.Free;
  end;
end;

procedure TColumnHeaderIconParityTest.TestHeaderImagesTakesOurImageList;
begin
  { Not a style preference: TTyVirtualImageList is not a TCustomImageList descendant
    (it renders on demand instead of holding a fixed-resolution set), so while Images
    was typed TCustomImageList the ONLY lists assignable to it were exactly the ones no
    TTyPainter can draw. }
  FLV.Header.Images := FImgs;
  AssertSame('Header.Images holds the list it was given', FImgs, FLV.Header.Images);
end;

procedure TColumnHeaderIconParityTest.TestColumnImageIndexDrawsAnIcon;
begin
  FLV.Header.Images := FImgs;
  AssertFalse('precondition: no icon ink before ImageIndex is set', IconInk);
  (FLV.Header.Columns.Items[0] as TTyColumn).ImageIndex := 0;
  AssertTrue('a column with ImageIndex 0 draws its icon in the header', IconInk);
end;

procedure TColumnHeaderIconParityTest.TestHeaderCaptionIndentsForColumnImage;
var
  noIconL, noIconR, withIconL, withIconR: Integer;
begin
  FLV.Header.Images := FImgs;
  CaptionInk(noIconL, noIconR);
  AssertTrue('precondition: the caption has ink without an icon', noIconL >= 0);

  (FLV.Header.Columns.Items[0] as TTyColumn).ImageIndex := 0;
  CaptionInk(withIconL, withIconR);
  AssertTrue('precondition: the caption still has ink with an icon', withIconL >= 0);

  AssertTrue(Format('the caption''s LEFT end makes room for the icon (%d -> %d)',
    [noIconL, withIconL]), withIconL > noIconL + 8);
  { The discriminating one. An icon painted over the caption moves the left end too;
    only a caption that actually stepped aside moves its RIGHT end as well. }
  AssertTrue(Format('the caption''s RIGHT end moves too, or it was merely painted over (%d -> %d)',
    [noIconR, withIconR]), withIconR > noIconR + 8);
end;

procedure TColumnHeaderIconParityTest.TestNoIconWhenImageIndexIsMinusOne;
var
  bareL, bareR, stillL, stillR: Integer;
begin
  { The baseline is a header with NO list wired at all, so there is certainly no slot.
    Measuring the baseline with the list already wired -- which is what this guard did
    first -- compares a state to itself: a bug that reserves the slot for EVERY column
    shifts both measurements equally and the assertion never notices. Mutating the
    ImageIndex test from `>= 0` to `>= -1` walked straight through the old version. }
  FLV.Header.Images := nil;
  FLV.SmallImages := nil;
  CaptionInk(bareL, bareR);
  AssertTrue('precondition: the bare caption has ink', bareL >= 0);

  { Now wire a list up but leave ImageIndex at its -1 default. Nothing may change: the
    OFF value must reserve no slot, not merely draw no pixels. }
  FLV.Header.Images := FImgs;
  (FLV.Header.Columns.Items[0] as TTyColumn).ImageIndex := -1;
  AssertFalse('ImageIndex -1 draws no icon', IconInk);
  CaptionInk(stillL, stillR);
  AssertEquals('and reserves no slot for one: the caption does not move', bareL, stillL);
  AssertEquals('at either end', bareR, stillR);
end;

procedure TColumnHeaderIconParityTest.TestSmallImagesAnswerWhenHeaderImagesUnset;
begin
  { Delphi/LCL resolve TListColumn.ImageIndex against the list view's SmallImages —
    there is no separate header list on TListView — so the fallback IS the ported
    behaviour, not a convenience. }
  FLV.Header.Images := nil;
  FLV.SmallImages := FImgs;
  (FLV.Header.Columns.Items[0] as TTyColumn).ImageIndex := 0;
  AssertTrue('SmallImages answers when the header has no list of its own', IconInk);
end;

procedure TColumnHeaderIconParityTest.TestHeaderImagesOverridesSmallImages;
var
  empty: TTyVirtualImageList;
begin
  { Header.Images set to a list that can draw NOTHING at index 0 (no Names). If the
    header still drew red, it would be reading SmallImages — i.e. the "override" would
    not override. }
  empty := TTyVirtualImageList.Create(nil);
  try
    empty.Collection := FColl;
    FLV.SmallImages := FImgs;
    FLV.Header.Images := empty;
    (FLV.Header.Columns.Items[0] as TTyColumn).ImageIndex := 0;
    AssertFalse('Header.Images wins over SmallImages', IconInk);
  finally
    empty.Free;
  end;
end;

initialization
  RegisterTest(THeaderSectionEventParityTest);
  RegisterTest(TColumnHeaderIconParityTest);
end.
