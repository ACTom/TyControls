unit tyControls.ToolBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Button,
  tyControls.Controller;
type
  TTyToolSeparator = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align;
    property StyleClass;
    property Controller;
  end;

  TTyToolBar = class(TTyCustomControl)
  private
    FButtonHeight: Integer;
    FButtonHeightExplicit: Boolean;
    FButtonSpacing: Integer;
    FIndent: Integer;
    FWrapable: Boolean;
    FShowCaptions: Boolean;
    FFlat: Boolean;
    FImages: TImageList;
    FInLayout: Boolean;
    function GetButtonHeight: Integer;
    procedure SetButtonHeight(AValue: Integer);
    procedure SetButtonSpacing(AValue: Integer);
    procedure SetIndent(AValue: Integer);
    procedure SetWrapable(AValue: Boolean);
    procedure SetShowCaptions(AValue: Boolean);
    procedure SetImages(AValue: TImageList);
    procedure SetFlat(AValue: Boolean);
    procedure Relayout;
  protected
    { Protected rather than private so a test can drive the one call a relayout makes
      without needing a window handle and a live align pass. }
    procedure ApplyToButton(B: TTyButton);
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    { Density-aware: unset follows --control-height (classic 24 / modern 38). A host/.lfm value
      pins it (streamed only when explicitly set -- stored FButtonHeightExplicit). }
    property ButtonHeight: Integer read GetButtonHeight write SetButtonHeight stored FButtonHeightExplicit;
    property ButtonSpacing: Integer read FButtonSpacing write SetButtonSpacing default 2;
    property Indent: Integer read FIndent write SetIndent default 4;
    property Wrapable: Boolean read FWrapable write SetWrapable default True;
    { Reserved (not yet wired): in the reuse-TTyButton model each child button owns its own
      caption + image, so these have no effect today; kept for forward LCL-parity. }
    property ShowCaptions: Boolean read FShowCaptions write SetShowCaptions default False;
    property Flat: Boolean read FFlat write SetFlat default True;
    property Images: TImageList read FImages write SetImages;
    property Align default alTop;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray;

implementation

function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray;
var
  i, x, y: Integer;
begin
  SetLength(Result, Length(AItemSizes));
  ARows := 1;
  x := AIndent; y := AIndent;
  for i := 0 to High(AItemSizes) do
  begin
    if AWrapable and (i > 0) and (x + AItemSizes[i].cx > ABarWidth - AIndent) then
    begin
      x := AIndent; Inc(y, AButtonHeight + ASpacing); Inc(ARows);
    end;
    Result[i].Left := x;
    Result[i].Top := y;
    Result[i].Right := x + AItemSizes[i].cx;
    Result[i].Bottom := y + AButtonHeight;
    Inc(x, AItemSizes[i].cx + ASpacing);
  end;
end;

{ TTyToolSeparator }
constructor TTyToolSeparator.Create(AOwner: TComponent);
begin inherited Create(AOwner); Width := 8; Height := TyDensityHeight(ActiveController, 24); end;
// Its own key, NOT the bar's. The separator draws ink the bar does not — an inset
// vertical rule — and borrowing 'TyToolBar' made that rule the SAME colour as the bar's
// own bottom hairline BY CONSTRUCTION, so a theme could not dim, thicken or suppress the
// divider while keeping the bar's edge (the classic "lighter inset divider on a bordered
// bar"). It needs background too: that fill is what keeps the separator seamless with
// the bar it sits on.
function TTyToolSeparator.GetStyleTypeKey: string; begin Result := 'TyToolSeparator'; end;
procedure TTyToolSeparator.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolSeparator.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H: Integer; line: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    FillSharpBackdrop(P, Rect(0, 0, W, H));   // photo through the separator on an image theme (no-op on solid)
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, W, H), S.Background, 0);   // match the toolbar bg (seamless on solid; transparent->photo on green)
    line := Default(TTyFill); line.Kind := tfkSolid; line.Color := S.BorderColor;
    P.FillBackground(Rect(W div 2, P.Scale(3), W div 2 + 1, H - P.Scale(3)), line, 0);
    P.EndPaint;
  finally P.Free; end;
end;

{ TTyToolBar }
constructor TTyToolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];   // hosts the tool buttons
  FButtonHeight := 24; FButtonHeightExplicit := False;   // follow --control-height (density-aware) until set
  FButtonSpacing := 2; FIndent := 4; FWrapable := True; FFlat := True;
  Align := alTop;
  Width := 300; Height := 30;
end;

function TTyToolBar.GetStyleTypeKey: string; begin Result := 'TyToolBar'; end;

function TTyToolBar.GetButtonHeight: Integer;
begin
  if FButtonHeightExplicit then
    Result := FButtonHeight
  else
    Result := TyDensityMetric(ActiveController, 24, '--control-height');
end;
procedure TTyToolBar.SetButtonHeight(AValue: Integer); begin FButtonHeightExplicit := True; if FButtonHeight = AValue then Exit; FButtonHeight := AValue; Relayout; end;
procedure TTyToolBar.SetButtonSpacing(AValue: Integer); begin if FButtonSpacing = AValue then Exit; FButtonSpacing := AValue; Relayout; end;
procedure TTyToolBar.SetIndent(AValue: Integer); begin if FIndent = AValue then Exit; FIndent := AValue; Relayout; end;
procedure TTyToolBar.SetWrapable(AValue: Boolean); begin if FWrapable = AValue then Exit; FWrapable := AValue; Relayout; end;
procedure TTyToolBar.SetShowCaptions(AValue: Boolean); begin if FShowCaptions = AValue then Exit; FShowCaptions := AValue; Relayout; end;
procedure TTyToolBar.SetImages(AValue: TImageList); begin FImages := AValue; Relayout; end;
procedure TTyToolBar.SetFlat(AValue: Boolean); begin if FFlat = AValue then Exit; FFlat := AValue; Relayout; end;

procedure TTyToolBar.ApplyToButton(B: TTyButton);
begin
  // Reuse the ghost/flat TTyButton look, but only over a class the bar itself put
  // there. Assigning unconditionally (which is what this did) meant every relayout
  // wiped a caller's StyleClass := 'primary' -- and a relayout runs on any metric
  // change, so the styling vanished at an unpredictable moment rather than at once.
  if FFlat then
  begin
    if B.StyleClass = '' then B.StyleClass := 'ghost';
  end
  else
    if B.StyleClass = 'ghost' then B.StyleClass := '';
  // (Images/ShowCaptions propagation hooks here if/when TTyButton exposes them.)
end;

procedure TTyToolBar.Relayout;
begin
  if csDestroying in ComponentState then Exit;
  Realign;        // re-runs AlignControls over the children
  Invalidate;
end;

procedure TTyToolBar.AlignControls(AControl: TControl; var ARect: TRect);
var
  ih: Integer;
  i, n, rows: Integer;
  sizes: array of TSize;
  rects: TTyRectArray;
  ctl: TControl;
  list: array of TControl;
  newH, bh: Integer;
begin
  // re-entrancy guard: Height assignment at the end triggers another AlignControls call
  if FInLayout then Exit;
  FInLayout := True;
  try
    // collect visible children in child order
    SetLength(list, ControlCount); n := 0;
    for i := 0 to ControlCount - 1 do
    begin
      ctl := Controls[i];
      if ctl.Visible then begin list[n] := ctl; Inc(n); end;
    end;
    SetLength(list, n); SetLength(sizes, n);
    for i := 0 to n - 1 do
    begin
      if list[i] is TTyButton then ApplyToButton(TTyButton(list[i]));
      sizes[i].cx := list[i].Width;
      sizes[i].cy := list[i].Height;  // cy is not used by TyToolbarLayout (AButtonHeight governs row height)
    end;
    { ButtonHeight is what the bar ASKS for; a child may refuse to be that short. Controls
      whose caption decides their size publish Constraints.MinHeight, and SetBounds clamps to
      it -- so a row sized purely from ButtonHeight left the child overflowing DOWNWARD out
      of its slot: it covered the bar's bottom border and stopped lining up with the children
      that did fit. Take the tallest floor in the row first, then lay out against that. }
    bh := GetButtonHeight;
    for i := 0 to n - 1 do
      if list[i].Constraints.MinHeight > bh then bh := list[i].Constraints.MinHeight;
    rects := TyToolbarLayout(sizes, ClientWidth, FIndent, FButtonSpacing, bh, FWrapable, rows);
    for i := 0 to n - 1 do
    begin
      { Centre each child in the row. A child SHORTER than the row (a separator, a combo that
        is happy at 24 while a CJK caption needs 29) must sit on the row's centre line, or the
        bar reads as ragged -- which is the second half of the same report. }
      ih := list[i].Height;
      if ih > bh then ih := bh;
      if list[i].Constraints.MinHeight > ih then ih := list[i].Constraints.MinHeight;
      list[i].SetBounds(rects[i].Left, rects[i].Top + (bh - ih) div 2, list[i].Width, ih);
    end;
    // grow the bar to fit the rows when alTop/alBottom
    if (Align in [alTop, alBottom]) and (rows > 0) then
    begin
      newH := FIndent*2 + rows*bh + (rows-1)*FButtonSpacing;
      if Height <> newH then
        Height := newH;
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TTyToolBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then FImages := nil;
end;

procedure TTyToolBar.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H, bw: Integer; bg: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    // Lay the form's photo down FIRST so an alpha CSS background tints the photo (glass),
    // like TTyPanel. No-op (False) on solid/non-image themes -> their look is unchanged.
    FillSharpBackdrop(P, Rect(0, 0, W, H));
    // Paint S.Background directly (not a solid bg.Color rebuild) so an alpha() background is
    // honored OVER the backdrop instead of replacing it with an opaque tint.
    if tpBackground in S.Present then P.FillBackground(Rect(0, 0, W, H), S.Background, 0);
    bg := Default(TTyFill); bg.Kind := tfkSolid;
    bw := P.Scale(S.BorderWidth); if bw < 1 then bw := 1;
    if tpBorderColor in S.Present then
    begin
      bg.Color := S.BorderColor;
      P.FillBackground(Rect(0, H - bw, W, H), bg, 0);   // bottom hairline
    end;
    P.EndPaint;
  finally P.Free; end;
end;

end.
