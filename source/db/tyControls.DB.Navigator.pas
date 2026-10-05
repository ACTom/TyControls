unit tyControls.DB.Navigator;
{$mode objfpc}{$H+}
{ The data-aware navigator (issue #34, plan D9): LCL's TDBNavigator as one owner-drawn control.
  TTyCustomDBNavigator holds the data link and all the code, TTyDBNavigator publishes.

  ONE WINDOW, NOT ELEVEN. LCL builds the navigator out of ten button controls on a panel (twenty
  with the focusable set). Here the ten buttons are rects this control paints and hit-tests
  itself: every windowed control costs its form tens of milliseconds to start on this machine,
  and the buttons do nothing a rect cannot. So the navigator is not focusable (TabStop False,
  no keys) and LCL's Options (navFocusableButtons) and Flat are not published -- there are no
  button controls to make focusable or flat; the theme says how a button looks.

  The buttons and their order, VisibleButtons, Direction, Hints, Images, ConfirmDelete,
  BeforeAction and OnClick are LCL's own types and names (DBCtrls), so a form written for
  TDBNavigator reads the same values. The visible buttons share the length of the strip
  equally; a right-to-left horizontal strip puts First on the right.

  WHEN A BUTTON IS ENABLED is LCL's rule (TDBCustomNavigator.DataChanged / EditingChanged /
  ActiveChanged), asked afresh at every paint and every click rather than cached: First and
  Prior need a dataset that is not at BOF, Next and Last one not at EOF; Delete needs a
  modifiable dataset that is not empty; Insert a modifiable one; Edit a modifiable one not
  being edited; Post and Cancel one being edited. Refresh is enabled while the dataset is
  open and not being edited. LCL's two button sets disagree there -- the plain buttons enable
  Refresh with CanModify, the focusable ones with "active and not editing" -- and the second
  is the right one: refreshing a read-only dataset is exactly what a viewer wants, and a
  refresh in the middle of an edit throws the edit away.

  A CLICK is a press and a release on the same enabled button. BeforeAction runs before the
  dataset is told, OnClick after. Delete asks first when ConfirmDelete is set, through
  ConfirmDeleteRecord: a themed TyMessageDlg, which a subclass replaces (a test does).

  HINTS. Each button has its own: Hints[i] when that line is not empty, the translated default
  (tyControls.DB.StrConsts) otherwise. ShowButtonHints False leaves the control's own Hint.
  LCL shows the button hints through the buttons' own ShowHint; here the buttons are the
  control, so the control is born with ShowHint True.

  LOOK. The strip resolves 'TyDBNavigator', which falls back to 'TyToolBar'; each button
  resolves 'TyDBNavigatorButton' -- falling back to 'TyButton' -- in its own state (:hover,
  :active, :disabled) with the control's StyleClass as its variant, so `TyDBNavigator.ghost`
  buttons follow a theme's ghost buttons. A button's opacity (a theme's opacity for ':disabled')
  fades that button alone. The mark on a button is, in order: Images[Ord(button)] when there is
  one; the theme's icon-font glyph '--glyph-db-first' ... '--glyph-db-refresh'; otherwise the
  mark this unit draws with the painter's paths in the button's text colour. Its size is the
  theme metric '--dbnav-glyph-size', the gap between buttons '--dbnav-gap'. }
interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ImgList, LCLType, LMessages,
  DB, DBCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base;

const
  { Fallbacks (logical px at 96 PPI) for a theme that sets neither metric. }
  TyDBNavGap = 2;          // between two buttons
  TyDBNavGlyphSize = 12;   // the square a button's mark is drawn in
  TyDBNavGapVar = '--dbnav-gap';
  TyDBNavGlyphSizeVar = '--dbnav-glyph-size';

  { The icon-font override each button's mark looks for (v3/C5). }
  TyDBNavGlyphTokens: array[TDBNavButtonType] of string = (
    '--glyph-db-first', '--glyph-db-prior', '--glyph-db-next', '--glyph-db-last',
    '--glyph-db-insert', '--glyph-db-delete', '--glyph-db-edit', '--glyph-db-post',
    '--glyph-db-cancel', '--glyph-db-refresh');

type
  TTyDBNavButtonRects = array[TDBNavButtonType] of TRect;

{ Where each button goes in AArea (device px): the buttons in AVisible, in LCL's order, share
  its width (nbdHorizontal) or height (nbdVertical) equally, AGap between two of them; the
  pixels a division leaves over go one each to the first buttons. ARightToLeft mirrors a
  horizontal strip. A hidden button's rect is empty. The paint and the hit test both read it. }
function TyDBNavButtonRects(const AArea: TRect; AVisible: TDBNavButtonSet;
  ADirection: TDBNavButtonDirection; AGap: Integer; ARightToLeft: Boolean): TTyDBNavButtonRects;

type
  TTyCustomDBNavigator = class;

  { LCL's TDBNavDataLink, which DBCtrls keeps to itself: what the dataset does, the navigator
    repaints for. }
  TTyDBNavDataLink = class(TDataLink)
  private
    FNavigator: TTyCustomDBNavigator;
  protected
    procedure ActiveChanged; override;
    procedure DataSetChanged; override;
    procedure EditingChanged; override;
  public
    constructor Create(ANavigator: TTyCustomDBNavigator);
  end;

  TTyCustomDBNavigator = class(TTyCustomControl)
  private
    FDataLink: TTyDBNavDataLink;
    FVisibleButtons: TDBNavButtonSet;
    FDirection: TDBNavButtonDirection;
    FConfirmDelete: Boolean;
    FShowButtonHints: Boolean;
    FHints: TStrings;
    FImages: TCustomImageList;
    FImageChangeLink: TChangeLink;
    FBeforeAction: TDBNavClickEvent;
    FOnNavClick: TDBNavClickEvent;
    FHoverButton: Integer;     // Ord of the button under the pointer, -1 for none
    FPressedButton: Integer;   // Ord of the button the left press went down on, -1 for none
    function GetDataSource: TDataSource;
    procedure SetDataSource(AValue: TDataSource);
    procedure SetVisibleButtons(AValue: TDBNavButtonSet);
    procedure SetDirection(AValue: TDBNavButtonDirection);
    procedure SetHints(AValue: TStrings);
    procedure SetImages(AValue: TCustomImageList);
    procedure ImageListChange(Sender: TObject);
    { Ord of the button at (X, Y), -1 between buttons or outside them. }
    function ButtonIndexAt(X, Y: Integer): Integer;
    procedure SetHoverButton(AIndex: Integer);
    function ButtonRectsFor(AWidth, AHeight, APPI: Integer): TTyDBNavButtonRects;
    { The resolved style of one button in its present state. }
    function ButtonStyle(AButton: TDBNavButtonType): TTyStyleSet;
    procedure DrawButton(APainter: TTyPainter; AButton: TDBNavButtonType; const ARect: TRect;
      const AStrip: TTyStyleSet; APPI: Integer);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
    procedure CMHintShow(var Message: TLMessage); message CM_HINTSHOW;
  protected
    class function GetControlClassDefaultSize: TSize; override;
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { Asked before the Delete button deletes, when ConfirmDelete is set: True deletes. A themed
      TyMessageDlg with OK and Cancel, as LCL asks with its MessageDlg. }
    function ConfirmDeleteRecord: Boolean; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Do what button AButton does, as a click on it does -- enabled or not, as LCL's. }
    procedure BtnClick(AButton: TDBNavButtonType); virtual;
    function VisibleButtonCount: Integer;
    { Can the button be clicked now (the rules in the unit comment)? }
    function ButtonEnabled(AButton: TDBNavButtonType): Boolean;
    { The button's rect in client device px; empty when it is hidden. }
    function ButtonRect(AButton: TDBNavButtonType): TRect;
    function ButtonAt(X, Y: Integer; out AButton: TDBNavButtonType): Boolean;
    { The hint the button shows: Hints[Ord(AButton)] unless that line is empty or missing, the
      default from tyControls.DB.StrConsts otherwise. }
    function ButtonHint(AButton: TDBNavButtonType): string;
    property TabStop default False;
    property ShowHint default True;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property VisibleButtons: TDBNavButtonSet read FVisibleButtons write SetVisibleButtons
      default DefaultDBNavigatorButtons;
    property Direction: TDBNavButtonDirection read FDirection write SetDirection
      default nbdHorizontal;
    property ConfirmDelete: Boolean read FConfirmDelete write FConfirmDelete default True;
    property ShowButtonHints: Boolean read FShowButtonHints write FShowButtonHints default True;
    { Read when a hint is asked for: a change needs no repaint. }
    property Hints: TStrings read FHints write SetHints;
    { Images[Ord(button)] is that button's mark, in place of the built-in one. }
    property Images: TCustomImageList read FImages write SetImages;
    property BeforeAction: TDBNavClickEvent read FBeforeAction write FBeforeAction;
    { LCL's: which button was clicked, after the dataset has done it. }
    property OnClick: TDBNavClickEvent read FOnNavClick write FOnNavClick;
  end;

  { TTyDBNavigator publishes TTyCustomDBNavigator's properties; everything lives in
    TTyCustomDBNavigator. }
  TTyDBNavigator = class(TTyCustomDBNavigator)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property OnPaint;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Align;
    property Anchors;
    property BeforeAction;
    property ConfirmDelete;
    property DataSource;
    property Direction;
    property Hints;
    property ShowButtonHints;
    property VisibleButtons;
    property Images;
  end;

implementation

uses
  Dialogs, tyControls.StyleModel, tyControls.ImageDraw, tyControls.Dialogs,
  tyControls.DB.StrConsts;

function TyDBNavButtonRects(const AArea: TRect; AVisible: TDBNavButtonSet;
  ADirection: TDBNavButtonDirection; AGap: Integer; ARightToLeft: Boolean): TTyDBNavButtonRects;
var
  b: TDBNavButtonType;
  n, i, total, base, extra, pos, size: Integer;
begin
  n := 0;
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
  begin
    Result[b] := Rect(0, 0, 0, 0);
    if b in AVisible then Inc(n);
  end;
  if n = 0 then Exit;
  if AGap < 0 then AGap := 0;
  if ADirection = nbdHorizontal then
  begin
    total := AArea.Right - AArea.Left - AGap * (n - 1);
    pos := AArea.Left;
  end
  else
  begin
    total := AArea.Bottom - AArea.Top - AGap * (n - 1);
    pos := AArea.Top;
  end;
  if total < 0 then total := 0;
  base := total div n;
  extra := total mod n;
  i := 0;
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
  begin
    if not (b in AVisible) then Continue;
    size := base;
    if i < extra then Inc(size);
    if ADirection = nbdVertical then
      Result[b] := Rect(AArea.Left, pos, AArea.Right, pos + size)
    else if ARightToLeft then
      Result[b] := Rect(AArea.Left + AArea.Right - (pos + size), AArea.Top,
        AArea.Left + AArea.Right - pos, AArea.Bottom)
    else
      Result[b] := Rect(pos, AArea.Top, pos + size, AArea.Bottom);
    pos := pos + size + AGap;
    Inc(i);
  end;
end;

{ ---- the marks this unit draws when neither Images nor the theme gives one ---------------- }

type
  { One point of a mark, in the unit square of its box (0..1 across and down). }
  TNavPt = record
    X, Y: Double;
  end;

function NavPt(AX, AY: Double): TNavPt;
begin
  Result.X := AX;
  Result.Y := AY;
end;

{ The mark of AButton in the square ABox (device px), stroked or filled in AColor; AMirror
  turns the four moving buttons round (a right-to-left strip reads the other way). The stroke
  is an eighth of the box, so the mark keeps its weight at every glyph size and DPI. }
procedure DrawNavMark(P: TTyPainter; const ABox: TRect; AButton: TDBNavButtonType;
  AColor: TTyColor; AMirror: Boolean);
var
  side, stroke: Double;

  function X(AX: Double): Double;
  begin
    if AMirror then AX := 1 - AX;
    Result := ABox.Left + AX * side;
  end;

  function Y(AY: Double): Double;
  begin
    Result := ABox.Top + AY * side;
  end;

  procedure Line(const A, B: TNavPt);
  begin
    P.BeginPath;
    P.MoveTo(X(A.X), Y(A.Y));
    P.LineTo(X(B.X), Y(B.Y));
    P.StrokePath(AColor, stroke);
  end;

  procedure Polygon(const APts: array of TNavPt; AFill: Boolean);
  var
    i: Integer;
  begin
    P.BeginPath;
    P.MoveTo(X(APts[0].X), Y(APts[0].Y));
    for i := 1 to High(APts) do
      P.LineTo(X(APts[i].X), Y(APts[i].Y));
    P.ClosePath;
    if AFill then
      P.FillPath(AColor)
    else
      P.StrokePath(AColor, stroke);
  end;

  procedure Refresh;
  var
    cx, cy, r, a0, a1, h, ex, ey, dx, dy, nx, ny: Double;
  begin
    cx := ABox.Left + 0.5 * side;
    cy := ABox.Top + 0.5 * side;
    r := 0.3 * side;
    a0 := -0.25 * Pi;      // up and to the right
    a1 := a0 + 1.5 * Pi;   // three quarters round, clockwise
    P.BeginPath;
    P.ArcTo(cx, cy, r, a0, a1);
    P.StrokePath(AColor, stroke);
    { The arrowhead at the end of the arc, pointing on along it. }
    h := 0.18 * side;
    ex := cx + r * Cos(a1);
    ey := cy + r * Sin(a1);
    dx := -Sin(a1);
    dy := Cos(a1);
    nx := Cos(a1);
    ny := Sin(a1);
    P.BeginPath;
    P.MoveTo(ex + dx * h, ey + dy * h);
    P.LineTo(ex + nx * h * 0.8, ey + ny * h * 0.8);
    P.LineTo(ex - nx * h * 0.8, ey - ny * h * 0.8);
    P.ClosePath;
    P.FillPath(AColor);
  end;

begin
  side := ABox.Right - ABox.Left;
  if side <= 0 then Exit;
  { StrokePath takes logical px and scales them itself: an eighth of the box, unscaled. }
  stroke := P.Unscale(Round(side)) / 8;
  if stroke <= 0 then stroke := side / 8;
  P.SaveState;
  try
    P.SetLineCap(tlcRound);
    P.SetLineJoin(tljRound);
    case AButton of
      nbFirst:
        begin
          Line(NavPt(0.25, 0.22), NavPt(0.25, 0.78));
          Polygon([NavPt(0.78, 0.22), NavPt(0.78, 0.78), NavPt(0.36, 0.5)], True);
        end;
      nbPrior:
        Polygon([NavPt(0.68, 0.22), NavPt(0.68, 0.78), NavPt(0.3, 0.5)], True);
      nbNext:
        Polygon([NavPt(0.32, 0.22), NavPt(0.32, 0.78), NavPt(0.7, 0.5)], True);
      nbLast:
        begin
          Line(NavPt(0.75, 0.22), NavPt(0.75, 0.78));
          Polygon([NavPt(0.22, 0.22), NavPt(0.22, 0.78), NavPt(0.64, 0.5)], True);
        end;
      nbInsert:
        begin
          Line(NavPt(0.2, 0.5), NavPt(0.8, 0.5));
          Line(NavPt(0.5, 0.2), NavPt(0.5, 0.8));
        end;
      nbDelete:
        Line(NavPt(0.2, 0.5), NavPt(0.8, 0.5));
      nbEdit:
        begin
          Polygon([NavPt(0.62, 0.16), NavPt(0.84, 0.38), NavPt(0.42, 0.8), NavPt(0.2, 0.58)],
            False);
          Polygon([NavPt(0.2, 0.58), NavPt(0.42, 0.8), NavPt(0.14, 0.86)], True);
        end;
      nbPost:
        begin
          P.BeginPath;
          P.MoveTo(X(0.2), Y(0.52));
          P.LineTo(X(0.42), Y(0.74));
          P.LineTo(X(0.8), Y(0.28));
          P.StrokePath(AColor, stroke);
        end;
      nbCancel:
        begin
          Line(NavPt(0.25, 0.25), NavPt(0.75, 0.75));
          Line(NavPt(0.75, 0.25), NavPt(0.25, 0.75));
        end;
      nbRefresh:
        Refresh;
    end;
  finally
    P.RestoreState;
  end;
end;

{ AColor with its alpha multiplied by AOpacity (0..1). }
function FadeColor(AColor: TTyColor; AOpacity: Single): TTyColor;
var
  a: Integer;
begin
  if AOpacity >= 1 then Exit(AColor);
  if AOpacity < 0 then AOpacity := 0;
  a := Round(TyAlphaOf(AColor) * AOpacity);
  Result := (AColor and $00FFFFFF) or (TTyColor(a) shl 24);
end;

function FadeFill(const AFill: TTyFill; AOpacity: Single): TTyFill;
var
  i: Integer;
begin
  Result := AFill;
  if AOpacity >= 1 then Exit;
  Result.Color := FadeColor(AFill.Color, AOpacity);
  Result.GradFrom := FadeColor(AFill.GradFrom, AOpacity);
  Result.GradTo := FadeColor(AFill.GradTo, AOpacity);
  Result.GradStops := Copy(AFill.GradStops);
  for i := 0 to High(Result.GradStops) do
    Result.GradStops[i].Color := FadeColor(AFill.GradStops[i].Color, AOpacity);
end;

const
  CButtonHints: array[TDBNavButtonType] of PString = (
    @rsTyDBNavFirst, @rsTyDBNavPrior, @rsTyDBNavNext, @rsTyDBNavLast, @rsTyDBNavInsert,
    @rsTyDBNavDelete, @rsTyDBNavEdit, @rsTyDBNavPost, @rsTyDBNavCancel, @rsTyDBNavRefresh);

{ ================================================================== TTyDBNavDataLink == }

constructor TTyDBNavDataLink.Create(ANavigator: TTyCustomDBNavigator);
begin
  inherited Create;
  FNavigator := ANavigator;
  VisualControl := True;
end;

procedure TTyDBNavDataLink.ActiveChanged;
begin
  if FNavigator <> nil then FNavigator.Invalidate;
end;

procedure TTyDBNavDataLink.DataSetChanged;
begin
  if FNavigator <> nil then FNavigator.Invalidate;
end;

procedure TTyDBNavDataLink.EditingChanged;
begin
  if FNavigator <> nil then FNavigator.Invalidate;
end;

{ ============================================================== TTyCustomDBNavigator == }

constructor TTyCustomDBNavigator.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csAcceptsControls, csSetCaption];
  FDataLink := TTyDBNavDataLink.Create(Self);
  FVisibleButtons := DefaultDBNavigatorButtons;
  FDirection := nbdHorizontal;
  FConfirmDelete := True;
  FShowButtonHints := True;
  FHints := TStringList.Create;
  FImageChangeLink := TChangeLink.Create;
  FImageChangeLink.OnChange := @ImageListChange;
  FHoverButton := -1;
  FPressedButton := -1;
  ShowHint := True;   // the button hints; see the unit comment
  with GetControlClassDefaultSize do
    SetInitialBounds(0, 0, CX, CY);
end;

destructor TTyCustomDBNavigator.Destroy;
begin
  if FImages <> nil then FImages.UnRegisterChanges(FImageChangeLink);
  FreeAndNil(FDataLink);
  FreeAndNil(FHints);
  FreeAndNil(FImageChangeLink);
  inherited Destroy;
end;

class function TTyCustomDBNavigator.GetControlClassDefaultSize: TSize;
begin
  Result.CX := 241;   // LCL's TDBNavigator
  Result.CY := 25;
end;

function TTyCustomDBNavigator.GetStyleTypeKey: string;
begin
  Result := 'TyDBNavigator';
end;

function TTyCustomDBNavigator.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

procedure TTyCustomDBNavigator.SetDataSource(AValue: TDataSource);
begin
  if AValue = DataSource then Exit;
  ChangeDataSource(Self, FDataLink, AValue);
  Invalidate;
end;

procedure TTyCustomDBNavigator.SetVisibleButtons(AValue: TDBNavButtonSet);
begin
  if FVisibleButtons = AValue then Exit;
  FVisibleButtons := AValue;
  FHoverButton := -1;
  FPressedButton := -1;
  Invalidate;
end;

procedure TTyCustomDBNavigator.SetDirection(AValue: TDBNavButtonDirection);
begin
  if FDirection = AValue then Exit;
  FDirection := AValue;
  Invalidate;
end;

procedure TTyCustomDBNavigator.SetHints(AValue: TStrings);
begin
  FHints.Assign(AValue);
end;

procedure TTyCustomDBNavigator.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then
  begin
    FImages.UnRegisterChanges(FImageChangeLink);
    FImages.RemoveFreeNotification(Self);
  end;
  FImages := AValue;
  if FImages <> nil then
  begin
    FImages.RegisterChanges(FImageChangeLink);
    FImages.FreeNotification(Self);
  end;
  Invalidate;
end;

procedure TTyCustomDBNavigator.ImageListChange(Sender: TObject);
begin
  Invalidate;
end;

procedure TTyCustomDBNavigator.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  if (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
  if AComponent = FImages then
    Images := nil;
end;

procedure TTyCustomDBNavigator.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

function TTyCustomDBNavigator.VisibleButtonCount: Integer;
var
  b: TDBNavButtonType;
begin
  Result := 0;
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
    if b in FVisibleButtons then Inc(Result);
end;

function TTyCustomDBNavigator.ButtonEnabled(AButton: TDBNavButtonType): Boolean;
var
  ds: TDataSet;
  active, canModify: Boolean;
begin
  active := Enabled and (FDataLink <> nil) and FDataLink.Active;
  if not active then Exit(False);
  ds := FDataLink.DataSet;
  canModify := ds.CanModify;
  case AButton of
    nbFirst, nbPrior: Result := not ds.BOF;
    nbNext, nbLast: Result := not ds.EOF;
    nbDelete: Result := canModify and not (ds.BOF and ds.EOF);
    nbInsert: Result := canModify;
    nbEdit: Result := canModify and not FDataLink.Editing;
    nbPost, nbCancel: Result := canModify and FDataLink.Editing;
    nbRefresh: Result := not FDataLink.Editing;
  else
    Result := False;
  end;
end;

function TTyCustomDBNavigator.ButtonRectsFor(AWidth, AHeight, APPI: Integer): TTyDBNavButtonRects;
var
  S: TTyStyleSet;
  area: TRect;
  bw: Integer;
begin
  if APPI <= 0 then APPI := 96;
  S := CurrentStyle;
  { Inside the strip's own border and padding -- the same numbers DrawFrame paints with. }
  bw := 0;
  if TyBorderVisible(S) then bw := MulDiv(S.BorderWidth, APPI, 96);
  area := Rect(bw + MulDiv(S.Padding.Left, APPI, 96), bw + MulDiv(S.Padding.Top, APPI, 96),
    AWidth - bw - MulDiv(S.Padding.Right, APPI, 96),
    AHeight - bw - MulDiv(S.Padding.Bottom, APPI, 96));
  if area.Right < area.Left then area.Right := area.Left;
  if area.Bottom < area.Top then area.Bottom := area.Top;
  Result := TyDBNavButtonRects(area, FVisibleButtons, FDirection,
    MulDiv(ActiveController.Metric(TyDBNavGapVar, TyDBNavGap), APPI, 96),
    (FDirection = nbdHorizontal) and IsRightToLeft);
end;

function TTyCustomDBNavigator.ButtonRect(AButton: TDBNavButtonType): TRect;
begin
  Result := ButtonRectsFor(ClientWidth, ClientHeight, Font.PixelsPerInch)[AButton];
end;

function TTyCustomDBNavigator.ButtonIndexAt(X, Y: Integer): Integer;
var
  rects: TTyDBNavButtonRects;
  b: TDBNavButtonType;
begin
  Result := -1;
  rects := ButtonRectsFor(ClientWidth, ClientHeight, Font.PixelsPerInch);
  for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
    if (b in FVisibleButtons) and PtInRect(rects[b], Point(X, Y)) then
      Exit(Ord(b));
end;

function TTyCustomDBNavigator.ButtonAt(X, Y: Integer; out AButton: TDBNavButtonType): Boolean;
var
  i: Integer;
begin
  i := ButtonIndexAt(X, Y);
  Result := i >= 0;
  if Result then AButton := TDBNavButtonType(i) else AButton := nbFirst;
end;

function TTyCustomDBNavigator.ButtonHint(AButton: TDBNavButtonType): string;
begin
  Result := '';
  if Ord(AButton) < FHints.Count then
    Result := FHints[Ord(AButton)];
  if Result = '' then
    Result := CButtonHints[AButton]^;
end;

procedure TTyCustomDBNavigator.CMHintShow(var Message: TLMessage);
var
  info: PHintInfo;
  i: Integer;
begin
  info := PHintInfo(Message.LParam);
  if (info = nil) or not FShowButtonHints then
  begin
    inherited;
    Exit;
  end;
  i := ButtonIndexAt(info^.CursorPos.X, info^.CursorPos.Y);
  if i < 0 then
  begin
    inherited;   // between buttons: the control's own hint
    Exit;
  end;
  info^.HintStr := ButtonHint(TDBNavButtonType(i));
  info^.CursorRect := ButtonRect(TDBNavButtonType(i));   // moving to the next button asks again
  Message.Result := 0;
end;

procedure TTyCustomDBNavigator.SetHoverButton(AIndex: Integer);
begin
  if FHoverButton = AIndex then Exit;
  FHoverButton := AIndex;
  Invalidate;
end;

procedure TTyCustomDBNavigator.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  i: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  i := ButtonIndexAt(X, Y);
  if (i >= 0) and not ButtonEnabled(TDBNavButtonType(i)) then i := -1;
  FPressedButton := i;
  SetHoverButton(ButtonIndexAt(X, Y));
  Invalidate;
end;

procedure TTyCustomDBNavigator.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHoverButton(ButtonIndexAt(X, Y));
end;

procedure TTyCustomDBNavigator.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  pressed: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  pressed := FPressedButton;
  FPressedButton := -1;
  Invalidate;
  { A click is a press and a release on the same button, still enabled when it is released
    (the press may have been the last thing that happened to the dataset). }
  if (pressed >= 0) and (ButtonIndexAt(X, Y) = pressed)
    and ButtonEnabled(TDBNavButtonType(pressed)) then
    BtnClick(TDBNavButtonType(pressed));
end;

procedure TTyCustomDBNavigator.MouseLeave;
begin
  inherited MouseLeave;
  SetHoverButton(-1);
end;

function TTyCustomDBNavigator.ConfirmDeleteRecord: Boolean;
begin
  Result := TyMessageDlg(rsTyDBNavConfirmDelete, mtConfirmation, [mbOK, mbCancel], 0) <> mrCancel;
end;

procedure TTyCustomDBNavigator.BtnClick(AButton: TDBNavButtonType);
var
  ds: TDataSet;
begin
  if (DataSource <> nil) and (DataSource.State <> dsInactive) then
  begin
    if not (csDesigning in ComponentState) and Assigned(FBeforeAction) then
      FBeforeAction(Self, AButton);
    ds := DataSource.DataSet;
    case AButton of
      nbFirst: ds.First;
      nbPrior: ds.Prior;
      nbNext: ds.Next;
      nbLast: ds.Last;
      nbInsert: ds.Insert;
      nbDelete:
        if not FConfirmDelete or ConfirmDeleteRecord then
          ds.Delete;
      nbEdit: ds.Edit;
      nbPost: ds.Post;
      nbCancel: ds.Cancel;
      nbRefresh: ds.Refresh;
    end;
  end;
  if not (csDesigning in ComponentState) and Assigned(FOnNavClick) then
    FOnNavClick(Self, AButton);
end;

function TTyCustomDBNavigator.ButtonStyle(AButton: TDBNavButtonType): TTyStyleSet;
var
  states: TTyStateSet;
begin
  states := [];
  if not ButtonEnabled(AButton) then
    Include(states, tysDisabled)
  else
  begin
    if FHoverButton = Ord(AButton) then
    begin
      Include(states, tysHover);
      if FPressedButton = Ord(AButton) then Include(states, tysActive);
    end;
    if states = [] then Include(states, tysNormal);
  end;
  Result := ActiveController.Model.ResolveStyle('TyDBNavigatorButton',
    TyStyleClassFor(Self, StyleClass), states);
end;

procedure TTyCustomDBNavigator.DrawButton(APainter: TTyPainter; AButton: TDBNavButtonType;
  const ARect: TRect; const AStrip: TTyStyleSet; APPI: Integer);
var
  S: TTyStyleSet;
  op: Single;
  ink: TTyColor;
  inner, box: TRect;
  bw, side, cx, cy: Integer;
  usable: Boolean;
begin
  usable := ButtonEnabled(AButton);
  S := ButtonStyle(AButton);
  if tpOpacity in S.Present then op := S.Opacity else op := 1;
  if tpBackground in S.Present then
    APainter.FillBackground(ARect, FadeFill(S.Background, op), TyEffectiveCorners(S));
  bw := 0;
  if TyBorderVisible(S) then
  begin
    APainter.StrokeBorder(ARect, TyEffectiveCorners(S), S.BorderWidth,
      FadeColor(S.BorderColor, op));
    bw := APainter.Scale(S.BorderWidth);
  end;
  { The mark's colour: the button's own, the strip's where the theme gives the button none. }
  if tpTextColor in S.Present then ink := S.TextColor else ink := AStrip.TextColor;
  ink := FadeColor(ink, op);

  inner := ARect;
  InflateRect(inner, -bw, -bw);
  side := APainter.Scale(ActiveController.Metric(TyDBNavGlyphSizeVar, TyDBNavGlyphSize));
  side := Min(side, Min(inner.Right - inner.Left, inner.Bottom - inner.Top));
  if side <= 0 then Exit;
  cx := (inner.Left + inner.Right) div 2;
  cy := (inner.Top + inner.Bottom) div 2;
  box := Rect(cx - side div 2, cy - side div 2, cx - side div 2 + side, cy - side div 2 + side);

  if (FImages <> nil) and (Ord(AButton) < TyImageCount(FImages)) then
    TyBlitImage(APainter.Bitmap, FImages, Ord(AButton), box.Left, box.Top, side, APPI,
      not usable)
  else if not TyTryDrawGlyphOverride(APainter, ActiveController, box,
    TyDBNavGlyphTokens[AButton], ink) then
    DrawNavMark(APainter, box, AButton, ink,
      (FDirection = nbdHorizontal) and IsRightToLeft);
end;

procedure TTyCustomDBNavigator.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  rects: TTyDBNavButtonRects;
  b: TDBNavButtonType;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    rects := ButtonRectsFor(R.Right, R.Bottom, APPI);
    for b := Low(TDBNavButtonType) to High(TDBNavButtonType) do
      if (b in FVisibleButtons) and (rects[b].Right > rects[b].Left)
        and (rects[b].Bottom > rects[b].Top) then
        DrawButton(P, b, rects[b], S, APPI);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomDBNavigator.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

initialization
  { The strip falls back to the tool bar's look, each button to a button's (plan D8). }
  TyTryRegisterTypeKeyParent('TyDBNavigator', 'TyToolBar');
  TyTryRegisterTypeKeyParent('TyDBNavigatorButton', 'TyButton');

finalization
  TyUnregisterTypeKeyParent('TyDBNavigator');
  TyUnregisterTypeKeyParent('TyDBNavigatorButton');

end.
