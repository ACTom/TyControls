unit tyControls.ToolBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Button;
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
    FButtonSpacing: Integer;
    FIndent: Integer;
    FWrapable: Boolean;
    FShowCaptions: Boolean;
    FFlat: Boolean;
    FImages: TImageList;
    FInLayout: Boolean;
    procedure SetButtonHeight(AValue: Integer);
    procedure SetButtonSpacing(AValue: Integer);
    procedure SetIndent(AValue: Integer);
    procedure SetWrapable(AValue: Boolean);
    procedure SetShowCaptions(AValue: Boolean);
    procedure SetImages(AValue: TImageList);
    procedure SetFlat(AValue: Boolean);
    procedure Relayout;
    procedure ApplyToButton(B: TTyButton);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ButtonHeight: Integer read FButtonHeight write SetButtonHeight default 24;
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
begin inherited Create(AOwner); Width := 8; Height := 24; end;
function TTyToolSeparator.GetStyleTypeKey: string; begin Result := 'TyToolBar'; end;  // borrows the bar's border color
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
  FButtonHeight := 24; FButtonSpacing := 2; FIndent := 4; FWrapable := True; FFlat := True;
  Align := alTop;
  Width := 300; Height := 30;
end;

function TTyToolBar.GetStyleTypeKey: string; begin Result := 'TyToolBar'; end;

procedure TTyToolBar.SetButtonHeight(AValue: Integer); begin if FButtonHeight = AValue then Exit; FButtonHeight := AValue; Relayout; end;
procedure TTyToolBar.SetButtonSpacing(AValue: Integer); begin if FButtonSpacing = AValue then Exit; FButtonSpacing := AValue; Relayout; end;
procedure TTyToolBar.SetIndent(AValue: Integer); begin if FIndent = AValue then Exit; FIndent := AValue; Relayout; end;
procedure TTyToolBar.SetWrapable(AValue: Boolean); begin if FWrapable = AValue then Exit; FWrapable := AValue; Relayout; end;
procedure TTyToolBar.SetShowCaptions(AValue: Boolean); begin if FShowCaptions = AValue then Exit; FShowCaptions := AValue; Relayout; end;
procedure TTyToolBar.SetImages(AValue: TImageList); begin FImages := AValue; Relayout; end;
procedure TTyToolBar.SetFlat(AValue: Boolean); begin if FFlat = AValue then Exit; FFlat := AValue; Relayout; end;

procedure TTyToolBar.ApplyToButton(B: TTyButton);
begin
  // reuse the ghost/flat TTyButton; propagate the bar's button metrics.
  // NOTE: the toolbar owns the ghost/non-ghost StyleClass entirely — it does NOT
  // preserve whatever StyleClass a child button had before being added.
  if FFlat then B.StyleClass := 'ghost'
  else B.StyleClass := '';
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
  i, n, rows: Integer;
  sizes: array of TSize;
  rects: TTyRectArray;
  ctl: TControl;
  list: array of TControl;
  newH: Integer;
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
    rects := TyToolbarLayout(sizes, ClientWidth, FIndent, FButtonSpacing, FButtonHeight, FWrapable, rows);
    for i := 0 to n - 1 do
      list[i].SetBounds(rects[i].Left, rects[i].Top, list[i].Width, FButtonHeight);
    // grow the bar to fit the rows when alTop/alBottom
    if (Align in [alTop, alBottom]) and (rows > 0) then
    begin
      newH := FIndent*2 + rows*FButtonHeight + (rows-1)*FButtonSpacing;
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
