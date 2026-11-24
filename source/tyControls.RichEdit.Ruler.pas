unit tyControls.RichEdit.Ruler;

{ TTyRichEditRuler: the horizontal ruler an application puts above a TTyRichEdit and links to
  it (RichEdit). It shows the paragraph a paragraph format change would begin at (the
  caret's, or the first one the selection touches: the one Paragraph reads and a drag
  changes) - the first line's indent, the indent
  of its other lines (the hanging marker), a box under that one which moves both, the right
  indent, and the tab stops, each drawn by its kind (left, centre, right, decimal: the kinds
  the document holds) - on a scale of centimetres or inches (MeasureUnit) that follows the
  rich edit's zoom, the screen's PPI and its horizontal scroll. Its zero is the left edge of
  that paragraph's text: the page's text edge (WrapMode rwmPage), the text area's (rwmWindow,
  rwmNone), or - in a table - its cell's text edge, the ruler dimmed outside the
  cell's width (and outside the width the text wraps at).

  Dragging a marker shows a line through the rich edit where it would put the text (the rich
  edit draws it: GuideLine), snaps to a quarter of the unit (Alt held: no snap), stays inside
  the text with CTyRulerMinTextTwips of it left between the indents; Esc, the capture lost, a
  relink or the paragraph changing end it with nothing changed. The release is ONE command
  through the rich edit's paragraph format action (ApplyParagraphFormat: one undo step, a
  refusal told through its OnEditRefused); a release where nothing moved runs nothing. A
  double click on empty ruler space adds a left tab stop there; a stop dragged off the ruler
  (above or below it by more than its height) goes, one dragged along moves - each one step,
  the stops kept sorted, never two at one place, at most CTyMaxTabStops of them. With several
  paragraphs selected the markers are the first one's and a drag gives its one property
  to every paragraph the selection touches (the format API's rule): the first-line marker the
  first lines (RichMemo's FirstLine), the hanging marker the other lines (HeadIndent), the box
  the whole paragraph, each keeping its own offset (Delphi's FirstIndent), the right marker
  the right indent, a tab stop the tab stops.

  In a table the ruler shows the caret's row's column edges too (CaretRowEdges, placed from
  the cell paragraph's zero like everything else): a box across the strip at each, which a
  drag moves as the rich edit's own edge drag does - the guide line through the text, the
  rich edit's limits (Shift: the rest of the row follows), ONE command at the release
  (MoveCaretRowEdge: the selected rows, else every row with an edge there), Esc or no move
  nothing. The indent markers keep meaning the cell's paragraph.

  Nothing may be dragged - the markers show, in the theme's disabled look, and do not move -
  while the rich edit is read-only, disabled, loading (or incomplete, or saving), inside its
  document's update, in the designer, with no rich edit linked, or where the rich edit would
  refuse a paragraph format (CanFormatParagraphs: every paragraph shown in a field's result or a
  row that holds a nested table) - asked again at every press. A plain-text rich edit is
  formatted as its format API formats it.

  It knows the rich edit through public calls only - ParagraphView (what to show, laid
  out by the rich edit; markers are placed with its own twips conversion, so the first line's
  first character stands under the first-line marker to the pixel), AddHandlerOnParagraphView
  (when to look again), GuideLine and ApplyParagraphFormat - so an application's own ruler can
  do all of this one does. It never takes the focus: the caret stays in the rich edit, which
  keeps its selection shown, and after a drag the keys go to the rich edit.

  Right to left: the rich edit lays every paragraph out from the left (a paragraph's
  right-to-left flag is kept and written back, not laid out; BiDiMode only puts its vertical
  scroll bar on the left). The ruler agrees with what is on screen: its zero is always the
  text's left edge, its scale never mirrored.

  Look: the type key TyRichEditRuler (the ground, the dimmed span, the labels' font), its parts
  TyRulerTick (the active span's ground, the ticks and the labels; :disabled in the dimmed
  span) and TyRulerMarker (fill and outline; :hover, :active while dragged, :disabled). Every
  size follows the ruler's font: its height (AutoSize), the markers, the ticks. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, LCLType, LCLIntf,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter, tyControls.Base,
  tyControls.RichEdit.Model, tyControls.RichEdit.Layout, tyControls.RichEdit.Attrs,
  tyControls.RichEdit;

type
  { ruAuto: the system's measurement system where the platform tells it (Windows' locale; a
    POSIX locale's territory), else centimetres. }
  TTyRulerUnit = (ruAuto, ruCentimeters, ruInches);

  { What a marker is: the first line's indent, the other lines' (hanging), the box that moves
    both, the right indent, a tab stop, a table column's edge (ATab: its place in the edges the
    ruler shows; values from the cell paragraph's zero, twips). }
  TTyRulerMarker = (rmkNone, rmkFirstIndent, rmkHangingIndent, rmkLeftIndent, rmkRightIndent,
    rmkTabStop, rmkColumnEdge);

  TTyRulerMarkerState = (rmsNormal, rmsHover, rmsDragged, rmsDisabled);

  { A marker's change, before it is applied (AAllow False: nothing happens) and after. Values
    in twips: the first line's place (rmkFirstIndent), the other lines' (rmkHangingIndent,
    rmkLeftIndent), the right indent, a stop's place (ATab its index in the paragraph's stops,
    -1 for the others: OnMarkerChanging gives the index the stop has before the change,
    OnMarkerChanged the index it has after it - the stops sorted, an added one where it went;
    a removed one the index it had); a stop added has AOldTwips CTyRulerNoTab, one removed
    ANewTwips. The ruler may be freed by a handler of these events, or by one the rich edit's
    command runs: nothing of it is touched after that. }
  TTyRulerChangingEvent = procedure(Sender: TObject; AMarker: TTyRulerMarker; ATab: Integer;
    AOldTwips, ANewTwips: Integer; var AAllow: Boolean) of object;
  TTyRulerChangedEvent = procedure(Sender: TObject; AMarker: TTyRulerMarker; ATab: Integer;
    AOldTwips, ANewTwips: Integer) of object;

  { A tick of the scale: its x (ruler client pixels), its level (0 a whole unit, 1 a half, 2 a
    quarter), whether it is in the dimmed span, its label ('' none) and the label's box. }
  TTyRulerTick = record
    X: Integer;
    Level: Integer;
    Dimmed: Boolean;
    Text: string;
    LabelRect: TRect;
  end;
  TTyRulerTicks = array of TTyRulerTick;

const
  { A stop's place when there is none (added: the old one; removed: the new one). }
  CTyRulerNoTab = Low(Integer);
  { What a drag of an indent leaves of the text's width between the indents, in twips (a
    quarter of an inch). }
  CTyRulerMinTextTwips = 360;

type
  TTyCustomRichEditRuler = class(TTyCustomControl)
  private
    FRichEdit: TTyCustomRichEdit;
    FMeasureUnit: TTyRulerUnit;
    FView: TTyRichParaView;
    FHasView: Boolean;
    FViewChecks, FViewChanges: Integer;
    // a drag: the marker, its stop, its value at the press and now (twips), the press's x less
    // the marker's, a stop dragged off the ruler
    FDragging: Boolean;
    FDragMarker: TTyRulerMarker;
    FDragTab: Integer;
    FDragOld, FDragNew: Integer;
    FDragGrab: Integer;
    FDragOff: Boolean;
    FDragShift: Boolean;
    // the caret's row's column edges (none outside a table)
    FEdges: TTyRichColumnEdges;
    FKeysHooked: Boolean;
    FHoverMarker: TTyRulerMarker;
    FHoverTab: Integer;
    FOnMarkerChanging: TTyRulerChangingEvent;
    FOnMarkerChanged: TTyRulerChangedEvent;
    { Set by the destructor: a handler the ruler's command runs freed it (one flag per call
      that runs handlers, on that call's stack; nested calls pass it on). }
    FGone: PBoolean;
    procedure SetRichEdit(AValue: TTyCustomRichEdit);
    procedure SetMeasureUnit(AValue: TTyRulerUnit);
    procedure RichEditViewChanged(Sender: TObject);
    procedure HookKeys(AOn: Boolean);
    procedure AppKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FinishDrag(ACommit, AFocus: Boolean);
    procedure CommitDrag;
    procedure CommitDragIn(var AGone: Boolean);
    procedure AddTabAt(AX: Integer; AShift: TShiftState);
    procedure AddTabAtIn(AX: Integer; AShift: TShiftState; var AGone: Boolean);
    function RunFormat(AMask: TTyParaFormatMask; const AValue: TTyParaFormat): Boolean;
    procedure ShowGuide;
    function WidthTwips: Integer;
    function ClampValue(AMarker: TTyRulerMarker; AValue: Integer): Integer;
    function ValueOf(const AFormat: TTyParaFormat; AMarker: TTyRulerMarker; ATab: Integer): Integer;
    function FontPx(APPI: Integer): Integer;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    { A capture taken away while the button is still held (not the one the release lets go
      of) ends a drag with nothing changed. }
    procedure CaptureChanged; override;
    procedure EnabledChanged; override;
    procedure VisibleChanged; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { ---- for a descendant ---- }
    { Draws AMarker (ATab: which stop) in ARect (ruler client pixels; its x the marker's place
      is ARect's middle column) in AState: by default the theme's TyRulerMarker in the state's
      look - triangles for the indents, a box, a stop by its kind. }
    procedure DrawMarker(APainter: TTyPainter; AMarker: TTyRulerMarker; ATab: Integer;
      const ARect: TRect; AState: TTyRulerMarkerState); virtual;
    { Draws a tick's label AText centred in ARect, in TyRulerTick's colour (ADimmed: its
      :disabled one). }
    procedure DrawTickLabel(APainter: TTyPainter; const AText: string; const ARect: TRect;
      ADimmed: Boolean); virtual;
    { Where a drag at ATwips (from the paragraph's zero) puts the marker: by default the
      nearest quarter of the unit, ATwips itself with Alt held. }
    function Snap(ATwips: Integer; AShift: TShiftState): Integer; virtual;
    { OnMarkerChanging and OnMarkerChanged. }
    procedure DoMarkerChanging(AMarker: TTyRulerMarker; ATab: Integer; AOldTwips,
      ANewTwips: Integer; var AAllow: Boolean); virtual;
    procedure DoMarkerChanged(AMarker: TTyRulerMarker; ATab: Integer; AOldTwips,
      ANewTwips: Integer); virtual;
    { The unit the system measures in (ruAuto's answer; a test seam). }
    function SystemMeasureUnit: TTyRulerUnit; virtual;
    { After a drag: the keys go to the rich edit (it takes the focus when it can). }
    procedure FocusRichEdit; virtual;
    { The left button is down now (the system's state): what tells a capture taken away from
      the one a release lets go of. }
    function LeftButtonHeld: Boolean; virtual;
    { Esc during a drag ends it with nothing changed (Key 0: taken). The keys go to the rich
      edit, which has the focus: the ruler hears them before it while a drag runs. }
    procedure KeyWhileDragging(var Key: Word; Shift: TShiftState); virtual;
    { ---- the geometry, in ruler client pixels (and what a test reads) ---- }
    function EffectiveUnit: TTyRulerUnit;
    { One unit in twips (1440 / 2.54 or 1440). }
    function UnitTwips: Double;
    { The rich edit's client x less the ruler's (0 with no rich edit). }
    function EditOffset: Integer;
    { The ruler x of ATwips from the paragraph's zero, rounded as the layout rounds it. }
    function XOfTwips(ATwips: Integer): Integer;
    { The twips from the paragraph's zero at ruler x AX. }
    function TwipsOfX(AX: Integer): Integer;
    { The height the font asks: the markers above and below the strip, the labels' line in it. }
    function FontHeight: Integer;
    function MarkerSize: Integer;
    function StripTop: Integer;
    function StripBottom: Integer;
    { The active span: from the zero to where the text wraps (the text area's right edge
      when it does not). }
    function SpanLeft: Integer;
    function SpanRight: Integer;
    { The paragraph's format as it is shown: ParagraphView's, a drag's value applied. }
    function ShownFormat: TTyParaFormat;
    { Where AMarker is drawn (x: its column) and the box it is drawn and hit in; False when it
      is not shown (no view; the right indent of a text that does not wrap; no such stop). }
    function MarkerX(AMarker: TTyRulerMarker; ATab: Integer): Integer;
    function MarkerRect(AMarker: TTyRulerMarker; ATab: Integer; out ARect: TRect): Boolean;
    function MarkerAt(X, Y: Integer; out ATab: Integer): TTyRulerMarker;
    function TickMarks: TTyRulerTicks;
    { A press may begin a drag now (see the unit's head). }
    function CanDrag: Boolean;
    property View: TTyRichParaView read FView;
    property HasView: Boolean read FHasView;
    { How often the rich edit was asked (CheckView) and how often what it showed changed. }
    property ViewChecks: Integer read FViewChecks;
    property ViewChanges: Integer read FViewChanges;
    property Dragging: Boolean read FDragging;
    property DragMarker: TTyRulerMarker read FDragMarker;
    property DragValue: Integer read FDragNew;
    property DragOff: Boolean read FDragOff;
    property Edges: TTyRichColumnEdges read FEdges;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The ruler never takes the focus (TabStop has no effect, as on the scroll bars). }
    function CanFocus: Boolean; override;
    { Asks the rich edit what to show (ParagraphView) and paints again only when that
      changed. The ruler does it itself whenever the rich edit says its view may have changed. }
    procedure CheckView;
    { Ends a drag with nothing changed (Esc does this). }
    procedure CancelMarkerDrag;
    { Paints the whole ruler into ACanvas at ARect (a preview, a test). }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The linked rich edit (another form's too); freed or unlinked, the ruler shows an empty
      scale. A relink ends a drag with nothing changed. }
    property RichEdit: TTyCustomRichEdit read FRichEdit write SetRichEdit;
    property MeasureUnit: TTyRulerUnit read FMeasureUnit write SetMeasureUnit default ruAuto;
    property OnMarkerChanging: TTyRulerChangingEvent read FOnMarkerChanging write FOnMarkerChanging;
    property OnMarkerChanged: TTyRulerChangedEvent read FOnMarkerChanged write FOnMarkerChanged;
    property TabStop default False;
    { A new ruler is as tall as its font asks; True keeps it so when the font, the theme or
      the PPI changes (the width is the form's: Align it to the top). }
    property AutoSize default False;
  end;

  TTyRichEditRuler = class(TTyCustomRichEditRuler)
  published
    property Version;
    property Align;
    property Anchors;
    property AutoSize;
    property BorderSpacing;
    property Constraints;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property ParentShowHint;
    property PopupMenu;
    property TabOrder;
    property TabStop;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property RichEdit;
    property MeasureUnit;
    property OnMarkerChanging;
    property OnMarkerChanged;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property OnShowHint;
    property OnPaint;
  end;

implementation

{$IFDEF MSWINDOWS}
const
  CLocaleUserDefault = $0400;
  CLocaleIMeasure = $000D;

function GetLocaleInfoW(ALocale, ALCType: LongWord; AData: PWideChar; ACount: Integer): Integer;
  stdcall; external 'kernel32' name 'GetLocaleInfoW';
{$ENDIF}

function FloorDivI(A: Int64; B: Integer): Int64;
begin
  Result := A div B;
  if (A mod B <> 0) and ((A < 0) <> (B < 0)) then Dec(Result);
end;

{ ---- TTyCustomRichEditRuler ---- }

constructor TTyCustomRichEditRuler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // never a tab stop, never the focus (CanFocus): the caret stays in the rich edit
  TabStop := False;
  FMeasureUnit := ruAuto;
  FDragTab := -1;
  FHoverTab := -1;
  Width := 320;
  // the font's height (AutoSize keeps it so when the font or the theme changes)
  Height := FontHeight;
end;

destructor TTyCustomRichEditRuler.Destroy;
begin
  if FGone <> nil then FGone^ := True;
  HookKeys(False);
  if FRichEdit <> nil then
  begin
    if FDragging and not (csDestroying in FRichEdit.ComponentState) then
      FRichEdit.GuideLine := -1;
    FDragging := False;
    FRichEdit.RemoveHandlerOnParagraphView(@RichEditViewChanged);
    FRichEdit.RemoveFreeNotification(Self);
    FRichEdit := nil;
  end;
  inherited Destroy;
end;

function TTyCustomRichEditRuler.GetStyleTypeKey: string;
begin
  Result := 'TyRichEditRuler';
end;

function TTyCustomRichEditRuler.CanFocus: Boolean;
begin
  Result := False;
end;

procedure TTyCustomRichEditRuler.SetRichEdit(AValue: TTyCustomRichEdit);
begin
  if AValue = FRichEdit then Exit;
  // a relink ends a drag with nothing changed (its line goes from the old rich edit)
  if FDragging then FinishDrag(False, False);
  if FRichEdit <> nil then
  begin
    FRichEdit.RemoveHandlerOnParagraphView(@RichEditViewChanged);
    FRichEdit.RemoveFreeNotification(Self);
  end;
  FRichEdit := AValue;
  if FRichEdit <> nil then
  begin
    FRichEdit.FreeNotification(Self);
    FRichEdit.AddHandlerOnParagraphView(@RichEditViewChanged);
  end;
  FHasView := False;
  FView := Default(TTyRichParaView);
  CheckView;
  Invalidate;
end;

procedure TTyCustomRichEditRuler.SetMeasureUnit(AValue: TTyRulerUnit);
begin
  if AValue = FMeasureUnit then Exit;
  FMeasureUnit := AValue;
  Invalidate;
end;

procedure TTyCustomRichEditRuler.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FRichEdit) and (FRichEdit <> nil) then
  begin
    // the rich edit is going: nothing of it is touched any more (its handlers go with it)
    FDragging := False;
    HookKeys(False);
    FRichEdit := nil;
    FHasView := False;
    FView := Default(TTyRichParaView);
    Invalidate;
  end;
end;

procedure TTyCustomRichEditRuler.RichEditViewChanged(Sender: TObject);
begin
  CheckView;
end;

{ What is shown is the same (the paragraph's index is not shown: another paragraph of the same
  format at the same place looks the same). }
function SameParaView(const A, B: TTyRichParaView): Boolean;
begin
  Result := (A.InCell = B.InCell) and (A.Origin = B.Origin) and
    (A.ZeroRaster = B.ZeroRaster) and (A.TextWidthRaster = B.TextWidthRaster) and
    (A.ViewRaster = B.ViewRaster) and (A.PPI = B.PPI) and (A.Zoom = B.Zoom) and
    (A.Scale = B.Scale) and (A.ClipLeft = B.ClipLeft) and (A.ClipTop = B.ClipTop) and
    (A.ClipRight = B.ClipRight) and (A.ClipBottom = B.ClipBottom) and
    (A.Editable = B.Editable) and A.Format.Equals(B.Format);
end;

function SameEdges(const A, B: TTyRichColumnEdges): Boolean;
var
  i: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for i := 0 to High(A) do
    if (A[i].Index <> B[i].Index) or (A[i].Twips <> B[i].Twips) or (A[i].Offset <> B[i].Offset) or
       (A[i].MinOffset <> B[i].MinOffset) or (A[i].MaxOffset <> B[i].MaxOffset) or
       (A[i].Hidden <> B[i].Hidden) then
      Exit(False);
end;

procedure TTyCustomRichEditRuler.CheckView;
var
  v: TTyRichParaView;
  has, same, ends: Boolean;
  e: TTyRichColumnEdges;
begin
  Inc(FViewChecks);
  if FRichEdit = nil then has := False
  else has := FRichEdit.ParagraphView(v);
  if not has then v := Default(TTyRichParaView);
  e := nil;
  if has and v.InCell then FRichEdit.CaretRowEdges(e);
  same := (has = FHasView) and (not has or SameParaView(v, FView)) and SameEdges(e, FEdges);
  if same and (v.Para = FView.Para) then Exit;
  // (a column edge's drag is of the edges it began on)
  if FDragging and (FDragMarker = rmkColumnEdge) and not SameEdges(e, FEdges) then
  begin
    FEdges := e;
    FView := v;
    FHasView := has;
    FinishDrag(False, False);
    Inc(FViewChanges);
    Invalidate;
    Exit;
  end;
  FEdges := e;
  { A drag is of the paragraph and the format it began on: another paragraph under the caret,
    or the format changed by someone else, ends it with nothing changed. A scroll or a zoom
    does not (the line follows). }
  ends := FDragging and (not has or (v.Para <> FView.Para) or (v.InCell <> FView.InCell) or
    not v.Format.Equals(FView.Format) or not v.Editable);
  FView := v;
  FHasView := has;
  if ends then FinishDrag(False, False);
  if same then Exit;
  Inc(FViewChanges);
  if FDragging then ShowGuide;
  Invalidate;
end;

function TTyCustomRichEditRuler.CanDrag: Boolean;
begin
  Result := (FRichEdit <> nil) and FHasView and FView.Editable and IsEnabled and
    not (csDesigning in ComponentState);
end;

{ ---- geometry ---- }

function TTyCustomRichEditRuler.EffectiveUnit: TTyRulerUnit;
begin
  Result := FMeasureUnit;
  if Result = ruAuto then Result := SystemMeasureUnit;
  if Result = ruAuto then Result := ruCentimeters;
end;

function TTyCustomRichEditRuler.SystemMeasureUnit: TTyRulerUnit;
{$IFDEF MSWINDOWS}
var
  buf: array[0..3] of WideChar;
{$ENDIF}
{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
var
  loc: string;
  p: Integer;
{$ENDIF}
begin
  Result := ruCentimeters;
  {$IFDEF MSWINDOWS}
  // LOCALE_IMEASURE: '0' metric, '1' U.S.
  FillChar(buf, SizeOf(buf), 0);
  if (GetLocaleInfoW(CLocaleUserDefault, CLocaleIMeasure, @buf[0], Length(buf)) > 0) and
    (buf[0] = '1') then
    Result := ruInches;
  {$ENDIF}
  {$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
  // the locale that decides LC_MEASUREMENT: the territories that measure in inches
  loc := GetEnvironmentVariable('LC_ALL');
  if loc = '' then loc := GetEnvironmentVariable('LC_MEASUREMENT');
  if loc = '' then loc := GetEnvironmentVariable('LANG');
  p := Pos('_', loc);
  if p > 0 then
  begin
    loc := UpperCase(Copy(loc, p + 1, 2));
    if (loc = 'US') or (loc = 'LR') or (loc = 'MM') then Result := ruInches;
  end;
  {$ENDIF}
end;

function TTyCustomRichEditRuler.UnitTwips: Double;
begin
  if EffectiveUnit = ruInches then Result := 1440 else Result := 1440 / 2.54;
end;

function TTyCustomRichEditRuler.EditOffset: Integer;
begin
  Result := 0;
  if FRichEdit = nil then Exit;
  try
    Result := FRichEdit.ClientOrigin.X - ClientOrigin.X;
  except
    // (a control with neither a window nor a parent has no place on the screen)
    Result := 0;
  end;
end;

function TTyCustomRichEditRuler.XOfTwips(ATwips: Integer): Integer;
var
  s: Integer;
begin
  s := Math.Max(1, FView.Scale);
  Result := EditOffset + FView.Origin + Integer(FloorDivI(FView.ZeroRaster +
    TyRichTwipsToPx(ATwips, FView.PPI, FView.Zoom), s));
end;

function TTyCustomRichEditRuler.TwipsOfX(AX: Integer): Integer;
var
  raster: Int64;
  d: Double;
begin
  Result := 0;
  if (FView.PPI <= 0) or (FView.Zoom <= 0) then Exit;
  raster := Int64(AX - EditOffset - FView.Origin) * Math.Max(1, FView.Scale) - FView.ZeroRaster;
  d := raster * 1440.0 / (FView.PPI * Double(FView.Zoom));
  if d > MaxInt div 2 then d := MaxInt div 2;
  if d < -(MaxInt div 2) then d := -(MaxInt div 2);
  Result := Round(d);
end;

function TTyCustomRichEditRuler.FontPx(APPI: Integer): Integer;
var
  s: TTyStyleSet;
begin
  s := CurrentStyle;
  if APPI <= 0 then APPI := 96;
  Result := Math.Max(1, MulDiv(ResolveFontSize(s), APPI, 72));
end;

function TTyCustomRichEditRuler.MarkerSize: Integer;
begin
  // half the font, odd: a triangle with a middle column
  Result := Math.Max(3, FontPx(Font.PixelsPerInch) div 2);
  if not Odd(Result) then Inc(Result);
end;

function TTyCustomRichEditRuler.StripTop: Integer;
begin
  Result := MarkerSize;
end;

function TTyCustomRichEditRuler.StripBottom: Integer;
begin
  Result := Math.Max(StripTop + 1, ClientHeight - 2 * MarkerSize);
end;

function TTyCustomRichEditRuler.SpanLeft: Integer;
begin
  Result := XOfTwips(0);
end;

function TTyCustomRichEditRuler.SpanRight: Integer;
var
  s: Integer;
begin
  s := Math.Max(1, FView.Scale);
  if FView.TextWidthRaster = CRichNoWrap then
    Result := EditOffset + FView.Origin + Integer(FloorDivI(FView.ViewRaster, s))
  else
    Result := EditOffset + FView.Origin + Integer(FloorDivI(FView.ZeroRaster +
      FView.TextWidthRaster, s));
end;

{ The text's width from the zero in twips: where it wraps, else the text area's right edge. }
function TTyCustomRichEditRuler.WidthTwips: Integer;
var
  w: Int64;
begin
  Result := 0;
  if (FView.PPI <= 0) or (FView.Zoom <= 0) then Exit;
  if FView.TextWidthRaster = CRichNoWrap then w := Int64(FView.ViewRaster) - FView.ZeroRaster
  else w := FView.TextWidthRaster;
  Result := Math.Max(0, Round(Math.Min(w * 1440.0 / (FView.PPI * Double(FView.Zoom)),
    MaxInt div 2)));
end;

function TTyCustomRichEditRuler.ValueOf(const AFormat: TTyParaFormat; AMarker: TTyRulerMarker;
  ATab: Integer): Integer;
begin
  if AMarker = rmkColumnEdge then
  begin
    if (ATab >= 0) and (ATab < Length(FEdges)) then Exit(FEdges[ATab].Offset);
    Exit(0);
  end;
  case AMarker of
    rmkFirstIndent: Result := AFormat.LeftIndent + AFormat.FirstIndent;
    rmkHangingIndent, rmkLeftIndent: Result := AFormat.LeftIndent;
    rmkRightIndent: Result := AFormat.RightIndent;
    rmkTabStop:
      if (ATab >= 0) and (ATab < Length(AFormat.Tabs)) then Result := AFormat.Tabs[ATab].Position
      else Result := CTyRulerNoTab;
  else
    Result := 0;
  end;
end;

function TTyCustomRichEditRuler.ShownFormat: TTyParaFormat;
var
  first: Integer;
begin
  Result := FView.Format;
  Result.Tabs := Copy(FView.Format.Tabs);
  if not FDragging then Exit;
  case FDragMarker of
    rmkFirstIndent: Result.FirstIndent := FDragNew - Result.LeftIndent;
    rmkHangingIndent:
      begin
        // the other lines move, the first line stays
        first := Result.LeftIndent + Result.FirstIndent;
        Result.LeftIndent := FDragNew;
        Result.FirstIndent := first - FDragNew;
      end;
    rmkLeftIndent: Result.LeftIndent := FDragNew;
    rmkRightIndent: Result.RightIndent := FDragNew;
    rmkTabStop:
      if (FDragTab >= 0) and (FDragTab < Length(Result.Tabs)) and not FDragOff then
        Result.Tabs[FDragTab].Position := FDragNew;
  end;
end;

function TTyCustomRichEditRuler.MarkerX(AMarker: TTyRulerMarker; ATab: Integer): Integer;
var
  f: TTyParaFormat;
  hang: Integer;

  function Px(ATwips: Integer): Integer;
  begin
    Result := TyRichTwipsToPx(ATwips, FView.PPI, FView.Zoom);
  end;

  function ClientOfRaster(ARaster: Int64): Integer;
  begin
    Result := EditOffset + FView.Origin + Integer(FloorDivI(FView.ZeroRaster + ARaster,
      Math.Max(1, FView.Scale)));
  end;

begin
  f := ShownFormat;
  // the layout's own places: the other lines at the left indent (never left of the zero), the
  // first line its offset from there (neither), the right indent from where the text wraps
  hang := Math.Max(0, Px(f.LeftIndent));
  case AMarker of
    rmkFirstIndent: Result := ClientOfRaster(Math.Max(0, hang + Px(f.FirstIndent)));
    rmkHangingIndent, rmkLeftIndent: Result := ClientOfRaster(hang);
    rmkRightIndent: Result := ClientOfRaster(Int64(FView.TextWidthRaster) - Px(f.RightIndent));
    rmkTabStop:
      if (ATab >= 0) and (ATab < Length(f.Tabs)) then Result := ClientOfRaster(Px(f.Tabs[ATab].Position))
      else Result := 0;
    rmkColumnEdge:
      if FDragging and (FDragMarker = rmkColumnEdge) and (ATab = FDragTab) then
        Result := XOfTwips(FDragNew)
      else if (ATab >= 0) and (ATab < Length(FEdges)) then Result := XOfTwips(FEdges[ATab].Offset)
      else Result := 0;
  else
    Result := 0;
  end;
end;

function TTyCustomRichEditRuler.MarkerRect(AMarker: TTyRulerMarker; ATab: Integer;
  out ARect: TRect): Boolean;
var
  x, m, half, h: Integer;
  f: TTyParaFormat;
begin
  ARect := Rect(0, 0, 0, 0);
  Result := False;
  if not FHasView or (AMarker = rmkNone) then Exit;
  if (AMarker = rmkRightIndent) and (FView.TextWidthRaster = CRichNoWrap) then Exit;
  if AMarker = rmkTabStop then
  begin
    f := ShownFormat;
    if (ATab < 0) or (ATab >= Length(f.Tabs)) then Exit;
    if FDragging and FDragOff and (FDragMarker = rmkTabStop) and (ATab = FDragTab) then Exit;
  end;
  if AMarker = rmkColumnEdge then
    if (ATab < 0) or (ATab >= Length(FEdges)) or FEdges[ATab].Hidden then Exit;
  x := MarkerX(AMarker, ATab);
  m := MarkerSize;
  half := m div 2;
  h := ClientHeight;
  case AMarker of
    rmkFirstIndent: ARect := Rect(x - half, 0, x + half + 1, m);
    rmkHangingIndent, rmkRightIndent: ARect := Rect(x - half, h - 2 * m, x + half + 1, h - m);
    rmkLeftIndent: ARect := Rect(x - half, h - m, x + half + 1, h);
    rmkTabStop: ARect := Rect(x - half, StripBottom - m, x + half + 1, StripBottom);
    // across the strip, half a marker wide: the stops' feet stay clear of it
    rmkColumnEdge: ARect := Rect(x - half div 2, StripTop, x + half div 2 + 1, StripBottom);
  end;
  Result := True;
end;

function TTyCustomRichEditRuler.MarkerAt(X, Y: Integer; out ATab: Integer): TTyRulerMarker;
const
  COrder: array[0..3] of TTyRulerMarker = (rmkLeftIndent, rmkHangingIndent, rmkRightIndent,
    rmkFirstIndent);
var
  r: TRect;
  i: Integer;
  f: TTyParaFormat;
begin
  ATab := -1;
  Result := rmkNone;
  if not FHasView then Exit;
  for i := 0 to High(COrder) do
    if MarkerRect(COrder[i], -1, r) and PtInRect(r, Point(X, Y)) then Exit(COrder[i]);
  f := ShownFormat;
  // the last stop drawn is on top
  for i := High(f.Tabs) downto 0 do
    if MarkerRect(rmkTabStop, i, r) and PtInRect(r, Point(X, Y)) then
    begin
      ATab := i;
      Exit(rmkTabStop);
    end;
  for i := High(FEdges) downto 0 do
    if MarkerRect(rmkColumnEdge, i, r) and PtInRect(r, Point(X, Y)) then
    begin
      ATab := i;
      Exit(rmkColumnEdge);
    end;
end;

function TTyCustomRichEditRuler.Snap(ATwips: Integer; AShift: TShiftState): Integer;
var
  grid: Double;
begin
  if ssAlt in AShift then Exit(ATwips);
  grid := UnitTwips / 4;
  Result := Round(Round(ATwips / grid) * grid);
end;

function TTyCustomRichEditRuler.ClampValue(AMarker: TTyRulerMarker; AValue: Integer): Integer;
var
  w, lo, hi, li, fi, ri: Integer;
begin
  w := WidthTwips;
  li := FView.Format.LeftIndent;
  fi := FView.Format.FirstIndent;
  ri := FView.Format.RightIndent;
  if FView.TextWidthRaster = CRichNoWrap then ri := 0;
  lo := 0;
  case AMarker of
    rmkFirstIndent, rmkHangingIndent: hi := w - ri - CTyRulerMinTextTwips;
    rmkLeftIndent:
      begin
        // the box moves both: neither line left of the zero, both short of the right indent
        lo := Math.Max(0, -fi);
        hi := w - ri - CTyRulerMinTextTwips - Math.Max(0, fi);
      end;
    rmkRightIndent: hi := w - Math.Max(li, li + fi) - CTyRulerMinTextTwips;
  else
    hi := w;
  end;
  if hi < lo then hi := lo;
  Result := Math.Max(lo, Math.Min(hi, AValue));
end;

{ ---- dragging ---- }

procedure TTyCustomRichEditRuler.HookKeys(AOn: Boolean);
begin
  if AOn = FKeysHooked then Exit;
  if Application = nil then Exit;
  FKeysHooked := AOn;
  if AOn then Application.AddOnKeyDownBeforeHandler(@AppKeyDown)
  else Application.RemoveOnKeyDownBeforeHandler(@AppKeyDown);
end;

procedure TTyCustomRichEditRuler.AppKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FDragging then KeyWhileDragging(Key, Shift);
end;

procedure TTyCustomRichEditRuler.KeyWhileDragging(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    CancelMarkerDrag;
    Key := 0;
  end;
end;

procedure TTyCustomRichEditRuler.ShowGuide;
var
  x: Integer;
begin
  if FRichEdit = nil then Exit;
  if not FDragging or FDragOff then
  begin
    FRichEdit.GuideLine := -1;
    Exit;
  end;
  // the rich edit's client x of where the marker would put the text
  x := MarkerX(FDragMarker, FDragTab) - EditOffset;
  FRichEdit.GuideLine := Math.Max(0, x);
end;

procedure TTyCustomRichEditRuler.CancelMarkerDrag;
begin
  if not FDragging then Exit;
  FinishDrag(False, True);
end;

procedure TTyCustomRichEditRuler.FinishDrag(ACommit, AFocus: Boolean);
var
  gone: Boolean;
  keep: PBoolean;
begin
  FDragging := False;
  HookKeys(False);
  if FRichEdit <> nil then FRichEdit.GuideLine := -1;
  Invalidate;
  gone := False;
  keep := FGone;
  FGone := @gone;
  try
    if ACommit then CommitDrag;
    if gone then Exit;
    // whatever the user's drag did, the keys go to the rich edit after it
    if AFocus then FocusRichEdit;
  finally
    if gone then
    begin
      if keep <> nil then keep^ := True;
    end
    else
      FGone := keep;
  end;
end;

function SortedTabs(const ATabs: TTyTabStops): TTyTabStops;
var
  i, j: Integer;
  t: TTyTabStop;
begin
  Result := Copy(ATabs);
  for i := 1 to High(Result) do
  begin
    t := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j].Position > t.Position) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := t;
  end;
end;

function TTyCustomRichEditRuler.RunFormat(AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat): Boolean;
var
  re: TTyCustomRichEdit;
  gone: PBoolean;
begin
  re := FRichEdit;
  if re = nil then Exit(False);
  // (the caller's flag: a handler the command runs may free this ruler too)
  gone := FGone;
  Result := re.ApplyParagraphFormat(AMask, AValue);
  if (gone <> nil) and gone^ then Exit(False);
  // a handler the command ran may have freed the rich edit (the notification unlinked it)
  if FRichEdit <> re then Result := False;
end;

procedure TTyCustomRichEditRuler.CommitDrag;
var
  gone: Boolean;
  keep: PBoolean;
begin
  gone := False;
  keep := FGone;
  FGone := @gone;
  try
    CommitDragIn(gone);
  finally
    if gone then
    begin
      if keep <> nil then keep^ := True;
    end
    else
      FGone := keep;
  end;
end;

procedure TTyCustomRichEditRuler.CommitDragIn(var AGone: Boolean);
var
  m: TTyRulerMarker;
  tab, old, nw, i, j, after: Integer;
  allow: Boolean;
  v: TTyParaFormat;
  mask: TTyParaFormatMask;
  tabs: TTyTabStops;
begin
  m := FDragMarker;
  tab := FDragTab;
  old := FDragOld;
  if (m = rmkTabStop) and FDragOff then nw := CTyRulerNoTab
  else nw := FDragNew;
  // a release where nothing moved runs nothing
  if nw = old then Exit;
  if (FRichEdit = nil) or not CanDrag then Exit;
  allow := True;
  DoMarkerChanging(m, tab, old, nw, allow);
  if AGone or not allow or (FRichEdit = nil) or not CanDrag then Exit;
  after := tab;
  if m = rmkColumnEdge then
  begin
    if (tab < 0) or (tab >= Length(FEdges)) then Exit;
    if not FRichEdit.MoveCaretRowEdge(FEdges[tab].Index, nw, FDragShift) or AGone then Exit;
    DoMarkerChanged(m, after, old, nw);
    Exit;
  end;
  v := TyDefaultParaFormat;
  case m of
    rmkFirstIndent:
      begin
        // the first lines go there, the other lines stay (RichMemo's FirstLine)
        mask := [pffFirstLine];
        v.LeftIndent := nw;
        v.FirstIndent := 0;
      end;
    rmkHangingIndent:
      begin
        // the other lines go there, the first lines stay (RichMemo's HeadIndent)
        mask := [pffHeadIndent];
        v.LeftIndent := nw;
      end;
    rmkLeftIndent:
      begin
        { The whole paragraph moves, each keeping its own offset (Delphi's FirstIndent): the
          shown paragraph's first line goes where its other lines' move takes it. }
        mask := [pffStartIndent];
        v.LeftIndent := nw;
        v.FirstIndent := FView.Format.FirstIndent;
      end;
    rmkRightIndent:
      begin
        mask := [pffRightIndent];
        v.RightIndent := nw;
      end;
  else
    begin
      mask := [pffTabs];
      tabs := Copy(FView.Format.Tabs);
      if (tab < 0) or (tab >= Length(tabs)) then Exit;
      if nw = CTyRulerNoTab then
      begin
        for i := tab to High(tabs) - 1 do tabs[i] := tabs[i + 1];
        SetLength(tabs, Length(tabs) - 1);
      end
      else
      begin
        tabs[tab].Position := nw;
        // two stops never end on one place: the one moved there takes it
        for i := High(tabs) downto 0 do
          if (i <> tab) and (tabs[i].Position = nw) then
          begin
            for j := i to High(tabs) - 1 do tabs[j] := tabs[j + 1];
            SetLength(tabs, Length(tabs) - 1);
            if i < tab then Dec(tab);
          end;
      end;
      v.Tabs := SortedTabs(tabs);
      // the moved stop's index after the sort (a removed one keeps the index it had)
      if nw <> CTyRulerNoTab then
        for i := 0 to High(v.Tabs) do
          if v.Tabs[i].Position = nw then after := i;
    end;
  end;
  if not RunFormat(mask, v) or AGone then Exit;
  DoMarkerChanged(m, after, old, nw);
end;

procedure TTyCustomRichEditRuler.AddTabAt(AX: Integer; AShift: TShiftState);
var
  gone: Boolean;
  keep: PBoolean;
begin
  gone := False;
  keep := FGone;
  FGone := @gone;
  try
    AddTabAtIn(AX, AShift, gone);
  finally
    if gone then
    begin
      if keep <> nil then keep^ := True;
    end
    else
      FGone := keep;
  end;
end;

procedure TTyCustomRichEditRuler.AddTabAtIn(AX: Integer; AShift: TShiftState; var AGone: Boolean);
var
  v, i, at: Integer;
  allow: Boolean;
  tabs: TTyTabStops;
  f: TTyParaFormat;
begin
  tabs := Copy(FView.Format.Tabs);
  if Length(tabs) >= CTyMaxTabStops then Exit;
  v := Math.Max(0, Math.Min(WidthTwips, Snap(TwipsOfX(AX), AShift)));
  for i := 0 to High(tabs) do
    if tabs[i].Position = v then Exit;
  SetLength(tabs, Length(tabs) + 1);
  tabs[High(tabs)].Position := v;
  tabs[High(tabs)].Align := ttaLeft;
  tabs[High(tabs)].Leader := ttlNone;
  tabs := SortedTabs(tabs);
  at := 0;
  for i := 0 to High(tabs) do
    if tabs[i].Position = v then at := i;
  allow := True;
  DoMarkerChanging(rmkTabStop, at, CTyRulerNoTab, v, allow);
  if AGone or not allow or not CanDrag then Exit;
  f := TyDefaultParaFormat;
  f.Tabs := tabs;
  if RunFormat([pffTabs], f) and not AGone then DoMarkerChanged(rmkTabStop, at, CTyRulerNoTab, v);
  if AGone then Exit;
  FocusRichEdit;
end;

procedure TTyCustomRichEditRuler.DoMarkerChanging(AMarker: TTyRulerMarker; ATab: Integer;
  AOldTwips, ANewTwips: Integer; var AAllow: Boolean);
begin
  if Assigned(FOnMarkerChanging) then
    FOnMarkerChanging(Self, AMarker, ATab, AOldTwips, ANewTwips, AAllow);
end;

procedure TTyCustomRichEditRuler.DoMarkerChanged(AMarker: TTyRulerMarker; ATab: Integer;
  AOldTwips, ANewTwips: Integer);
begin
  if Assigned(FOnMarkerChanged) then FOnMarkerChanged(Self, AMarker, ATab, AOldTwips, ANewTwips);
end;

procedure TTyCustomRichEditRuler.FocusRichEdit;
begin
  if (FRichEdit = nil) or FRichEdit.Focused or not FRichEdit.CanFocus then Exit;
  try
    FRichEdit.SetFocus;
  except
    // (a form that cannot take the focus now: the keys stay where they are)
  end;
end;

function TTyCustomRichEditRuler.LeftButtonHeld: Boolean;
begin
  Result := GetKeyState(VK_LBUTTON) < 0;
end;

procedure TTyCustomRichEditRuler.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  m: TTyRulerMarker;
  tab: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
  begin
    // another button during a drag ends it
    if FDragging then CancelMarkerDrag;
    Exit;
  end;
  if FDragging then Exit;
  CheckView;
  if not CanDrag then Exit;
  m := MarkerAt(X, Y, tab);
  if ssDouble in Shift then
  begin
    if m = rmkNone then AddTabAt(X, Shift);
    Exit;
  end;
  if m = rmkNone then Exit;
  if (m = rmkColumnEdge) and not FRichEdit.CanResizeColumns then Exit;
  FDragShift := ssShift in Shift;
  FDragMarker := m;
  FDragTab := tab;
  FDragOld := ValueOf(FView.Format, m, tab);
  FDragNew := FDragOld;
  FDragOff := False;
  // the marker does not jump to the pointer: it keeps the press's distance from it
  FDragGrab := X - MarkerX(m, tab);
  FDragging := True;
  HookKeys(True);
  ShowGuide;
  Invalidate;
end;

procedure TTyCustomRichEditRuler.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  v, tab: Integer;
  off: Boolean;
  m: TTyRulerMarker;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    // the button let go where no release came (a capture taken): nothing changes
    if not (ssLeft in Shift) then
    begin
      CancelMarkerDrag;
      Exit;
    end;
    // the marker's place snaps to the scale; the right indent is counted from the text's end
    v := Snap(TwipsOfX(X - FDragGrab), Shift);
    if FDragMarker = rmkRightIndent then v := WidthTwips - v;
    if FDragMarker = rmkColumnEdge then
    begin
      // the rich edit's limits: as it is, or with the rest of the row following (Shift)
      FDragShift := ssShift in Shift;
      if (FDragTab >= 0) and (FDragTab < Length(FEdges)) then
        if FDragShift then
          v := Math.Max(FEdges[FDragTab].ShiftMinOffset, Math.Min(FEdges[FDragTab].ShiftMaxOffset, v))
        else
          v := Math.Max(FEdges[FDragTab].MinOffset, Math.Min(FEdges[FDragTab].MaxOffset, v));
    end
    else
      v := ClampValue(FDragMarker, v);
    off := (FDragMarker = rmkTabStop) and ((Y < -Height) or (Y >= 2 * Height));
    if (v = FDragNew) and (off = FDragOff) then Exit;
    FDragNew := v;
    FDragOff := off;
    ShowGuide;
    Invalidate;
    Exit;
  end;
  m := MarkerAt(X, Y, tab);
  if (m <> FHoverMarker) or (tab <> FHoverTab) then
  begin
    FHoverMarker := m;
    FHoverTab := tab;
    Invalidate;
  end;
end;

procedure TTyCustomRichEditRuler.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging and (Button = mbLeft) then FinishDrag(True, True);
end;

procedure TTyCustomRichEditRuler.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverMarker <> rmkNone then
  begin
    FHoverMarker := rmkNone;
    FHoverTab := -1;
    Invalidate;
  end;
end;

procedure TTyCustomRichEditRuler.CaptureChanged;
begin
  inherited CaptureChanged;
  if FDragging and LeftButtonHeld then CancelMarkerDrag;
end;

procedure TTyCustomRichEditRuler.EnabledChanged;
begin
  inherited EnabledChanged;
  CancelMarkerDrag;
  Invalidate;
end;

procedure TTyCustomRichEditRuler.VisibleChanged;
begin
  inherited VisibleChanged;
  CancelMarkerDrag;
end;

procedure TTyCustomRichEditRuler.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
begin
  inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
  PreferredHeight := FontHeight;
  PreferredWidth := 0;
end;

function TTyCustomRichEditRuler.FontHeight: Integer;
begin
  // the strip a line of figures tall, the markers' three half-font rows around it
  Result := (FontPx(Font.PixelsPerInch) * 11 + 2) div 4;
end;

{ ---- ticks ---- }

function TTyCustomRichEditRuler.TickMarks: TTyRulerTicks;
const
  // the units between two labels, the fewest that keeps them apart
  CSteps: array[0..9] of Integer = (1, 2, 5, 10, 20, 50, 100, 200, 500, 1000);
var
  unitTw, perUnit, minGap: Double;
  f, step, labelW, n, q, qFrom, qTo, count, x, spanL, spanR, half, level: Integer;
  showQuarter, showHalf: Boolean;
  t: TTyRulerTick;
  s: string;
begin
  Result := nil;
  if not FHasView or (FView.PPI <= 0) or (FView.Zoom <= 0) then Exit;
  unitTw := UnitTwips;
  f := FontPx(Font.PixelsPerInch);
  // client pixels a unit takes on the screen, as the rich edit shows it
  perUnit := FView.PPI * Double(FView.Zoom) * unitTw / 1440 / Math.Max(1, FView.Scale);
  if perUnit <= 0 then Exit;
  qFrom := Floor(TwipsOfX(0) / unitTw * 4) - 1;
  qTo := Ceil(TwipsOfX(ClientWidth) / unitTw * 4) + 1;
  // a pathological size never makes an endless list
  if qTo - qFrom > 4 * Math.Max(1, ClientWidth) then Exit;
  // labels: the widest one shown (its digits, each three fifths of the font) and half a font
  // between two
  labelW := ((f * 3 + 4) div 5) *
    Length(IntToStr(Math.Max(Abs(qFrom), Abs(qTo)) div 4 + 1));
  step := CSteps[High(CSteps)];
  for n := 0 to High(CSteps) do
    if CSteps[n] * perUnit >= labelW + f div 2 then
    begin
      step := CSteps[n];
      Break;
    end;
  minGap := f / 3;
  showQuarter := (step = 1) and (perUnit / 4 >= minGap);
  showHalf := (step = 1) and (perUnit / 2 >= minGap);
  spanL := SpanLeft;
  spanR := SpanRight;
  count := 0;
  SetLength(Result, Math.Max(0, qTo - qFrom + 1));
  half := StripTop + (StripBottom - StripTop) div 2;
  for q := qFrom to qTo do
  begin
    if q mod 4 = 0 then level := 0
    else if q mod 2 = 0 then level := 1
    else level := 2;
    if (level = 2) and not showQuarter then Continue;
    if (level = 1) and not showHalf then Continue;
    n := q div 4;
    if (level = 0) and (n mod step <> 0) and (perUnit < minGap) then Continue;
    x := XOfTwips(Round(q * unitTw / 4));
    if (x < 0) or (x >= ClientWidth) then Continue;
    t := Default(TTyRulerTick);
    t.X := x;
    t.Level := level;
    t.Dimmed := (x < spanL) or (x > spanR);
    if (level = 0) and (n <> 0) and (n mod step = 0) then
    begin
      s := IntToStr(Abs(n));
      t.Text := s;
      t.LabelRect := Rect(x - labelW div 2, half - f div 2, x - labelW div 2 + labelW,
        half - f div 2 + f);
    end;
    Result[count] := t;
    Inc(count);
  end;
  SetLength(Result, count);
end;

{ ---- painting ---- }

procedure TTyCustomRichEditRuler.Paint;
begin
  RenderTo(Canvas, Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
end;

function SolidFill(AColor: TTyColor): TTyFill;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  Result.Color := AColor;
end;

procedure TTyCustomRichEditRuler.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, tick, dim: TTyStyleSet;
  w, h, i, y0, y1, len, sTop, sBottom, l, r: Integer;
  ticks: TTyRulerTicks;
  f: TTyParaFormat;
  st: TTyStateSet;
  mr: TRect;
  c: TTyColor;

  function StateOf(AMarker: TTyRulerMarker; ATab: Integer): TTyRulerMarkerState;
  begin
    if not CanDrag then Result := rmsDisabled
    else if FDragging and (AMarker = FDragMarker) and
      ((AMarker <> rmkTabStop) or (ATab = FDragTab)) then Result := rmsDragged
    else if (AMarker = FHoverMarker) and ((AMarker <> rmkTabStop) or (ATab = FHoverTab)) then
      Result := rmsHover
    else Result := rmsNormal;
  end;

  procedure One(AMarker: TTyRulerMarker; ATab: Integer);
  begin
    if MarkerRect(AMarker, ATab, mr) then DrawMarker(P, AMarker, ATab, mr, StateOf(AMarker, ATab));
  end;

begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    w := ARect.Right - ARect.Left;
    h := ARect.Bottom - ARect.Top;
    DrawFrame(P, Rect(0, 0, w, h), S);
    if not IsEnabled then st := [tysDisabled] else st := [];
    tick := PartStyle('TyRulerTick', StyleClass, st);
    dim := PartStyle('TyRulerTick', StyleClass, [tysDisabled]);
    sTop := StripTop;
    sBottom := StripBottom;
    if FHasView then
    begin
      // the active span's ground
      l := Math.Max(0, SpanLeft);
      r := Math.Min(w, SpanRight + 1);
      if (r > l) and (tpBackground in tick.Present) then
        P.FillBackground(Rect(l, sTop, r, sBottom), tick.Background, 0);
      ticks := TickMarks;
      for i := 0 to High(ticks) do
      begin
        if ticks[i].Dimmed then c := dim.TextColor else c := tick.TextColor;
        if ticks[i].Text <> '' then
          DrawTickLabel(P, ticks[i].Text, ticks[i].LabelRect, ticks[i].Dimmed)
        else
        begin
          case ticks[i].Level of
            0: len := (sBottom - sTop) div 2;
            1: len := (sBottom - sTop) div 3;
          else
            len := (sBottom - sTop) div 5;
          end;
          len := Math.Max(1, len);
          y0 := sTop + (sBottom - sTop - len) div 2;
          y1 := y0 + len;
          P.DrawRule(ticks[i].X, y0, ticks[i].X, y1, TyColorToBGRA(c));
        end;
      end;
      f := ShownFormat;
      for i := 0 to High(FEdges) do One(rmkColumnEdge, i);
      for i := 0 to High(f.Tabs) do One(rmkTabStop, i);
      One(rmkLeftIndent, -1);
      One(rmkHangingIndent, -1);
      One(rmkRightIndent, -1);
      One(rmkFirstIndent, -1);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomRichEditRuler.DrawTickLabel(APainter: TTyPainter; const AText: string;
  const ARect: TRect; ADimmed: Boolean);
var
  s: TTyStyleSet;
begin
  if ADimmed then s := PartStyle('TyRulerTick', StyleClass, [tysDisabled])
  else if IsEnabled then s := PartStyle('TyRulerTick', StyleClass, [])
  else s := PartStyle('TyRulerTick', StyleClass, [tysDisabled]);
  APainter.DrawText(ARect, AText, s.FontName, ResolveFontSize(s), s.FontWeight, s.TextColor,
    taCenter, tlCenter, False);
end;

procedure TTyCustomRichEditRuler.DrawMarker(APainter: TTyPainter; AMarker: TTyRulerMarker;
  ATab: Integer; const ARect: TRect; AState: TTyRulerMarkerState);
var
  s: TTyStyleSet;
  st: TTyStateSet;
  fill, ink: TTyColor;
  cx, l, t, r, b: Double;
  x, bw, footTop, arm: Integer;
  f: TTyParaFormat;
  al: TTyTabAlign;
begin
  case AState of
    rmsHover: st := [tysHover];
    rmsDragged: st := [tysActive];
    rmsDisabled: st := [tysDisabled];
  else
    st := [];
  end;
  s := PartStyle('TyRulerMarker', StyleClass, st);
  if tpBackground in s.Present then fill := s.Background.Color else fill := s.TextColor;
  if tpBorderColor in s.Present then ink := s.BorderColor else ink := s.TextColor;
  l := ARect.Left;
  t := ARect.Top;
  r := ARect.Right;
  b := ARect.Bottom;
  cx := ARect.Left + (ARect.Right - ARect.Left) / 2;
  case AMarker of
    rmkFirstIndent:
      begin
        // pointing down at the strip
        APainter.BeginPath;
        APainter.MoveTo(l + 0.5, t + 0.5);
        APainter.LineTo(r - 0.5, t + 0.5);
        APainter.LineTo(cx, b - 0.5);
        APainter.ClosePath;
        APainter.FillAndStrokePath(fill, ink, 1);
      end;
    rmkHangingIndent, rmkRightIndent:
      begin
        // pointing up at the strip
        APainter.BeginPath;
        APainter.MoveTo(cx, t + 0.5);
        APainter.LineTo(r - 0.5, b - 0.5);
        APainter.LineTo(l + 0.5, b - 0.5);
        APainter.ClosePath;
        APainter.FillAndStrokePath(fill, ink, 1);
      end;
    rmkLeftIndent:
      begin
        APainter.BeginPath;
        APainter.RectPath(l + 0.5, t + 0.5, r - 0.5, b - 0.5);
        APainter.FillAndStrokePath(fill, ink, 1);
      end;
    rmkColumnEdge:
      begin
        // a column's edge: a box across the strip, filled, in the outline's ink
        APainter.BeginPath;
        APainter.RectPath(l + 0.5, t + 0.5, r - 0.5, b - 0.5);
        APainter.FillAndStrokePath(fill, ink, 1);
      end;
    rmkTabStop:
      begin
        // a stop by its kind, in the outline's ink: a stem at its place and its foot
        f := ShownFormat;
        if (ATab >= 0) and (ATab < Length(f.Tabs)) then al := f.Tabs[ATab].Align
        else al := ttaLeft;
        x := ARect.Left + (ARect.Right - ARect.Left) div 2;
        // the strokes a quarter of the marker thick (at least a pixel)
        bw := Math.Max(1, (ARect.Bottom - ARect.Top) div 4);
        arm := (ARect.Right - ARect.Left) div 2;
        footTop := ARect.Bottom - bw;
        case al of
          ttaLeft: APainter.FillBackground(Rect(x, footTop, x + arm + 1, ARect.Bottom),
            SolidFill(ink), 0);
          ttaRight: APainter.FillBackground(Rect(x - arm, footTop, x + 1, ARect.Bottom),
            SolidFill(ink), 0);
        else
          APainter.FillBackground(Rect(x - arm, footTop, x + arm + 1, ARect.Bottom),
            SolidFill(ink), 0);
        end;
        // the stem: the stop's own column
        APainter.FillBackground(Rect(x, ARect.Top, x + Math.Max(1, (bw + 1) div 2), ARect.Bottom),
          SolidFill(ink), 0);
        // a decimal stop's point, right of the stem
        if al = ttaDecimal then
          APainter.FillBackground(Rect(x + bw + 1, ARect.Top + bw, x + 2 * bw + 1,
            ARect.Top + 2 * bw), SolidFill(ink), 0);
      end;
  end;
end;

end.
