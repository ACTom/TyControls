unit tyControls.StatusBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyStatusPanel = class(TCollectionItem)
  private
    FText: string;
    FWidth: Integer;
    FAlignment: TAlignment;
    procedure SetText(const AValue: string);
    procedure SetWidth(AValue: Integer);
    procedure SetAlignment(AValue: TAlignment);
  public
    constructor Create(ACollection: TCollection); override;
  published
    property Text: string read FText write SetText;
    property Width: Integer read FWidth write SetWidth default 50;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
  end;

  TTyStatusBar = class;

  TTyStatusPanels = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyStatusPanel;
  protected
    procedure Update(Item: TCollectionItem); override;   // repaint owner on any panel change
  public
    function Add: TTyStatusPanel;
    property Items[AIndex: Integer]: TTyStatusPanel read GetItem; default;
  end;

  TTyStatusBar = class(TTyCustomControl)
  private
    FPanels: TTyStatusPanels;
    FSimplePanel: Boolean;
    FSimpleText: string;
    FSizeGrip: Boolean;
    procedure SetPanels(AValue: TTyStatusPanels);
    procedure SetSimplePanel(AValue: Boolean);
    procedure SetSimpleText(const AValue: string);
    procedure SetSizeGrip(AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PanelAtPos(X, Y: Integer): Integer;   // -1 outside any panel / SimplePanel mode
  published
    property Panels: TTyStatusPanels read FPanels write SetPanels;
    property SimplePanel: Boolean read FSimplePanel write SetSimplePanel default False;
    property SimpleText: string read FSimpleText write SetSimpleText;
    property SizeGrip: Boolean read FSizeGrip write SetSizeGrip default True;
    property Align default alBottom;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyStatusPanelRects(const AWidths: array of Integer; ATotalWidth, APadding: Integer): TTyRectArray;

implementation

function TyStatusPanelRects(const AWidths: array of Integer; ATotalWidth, APadding: Integer): TTyRectArray;
var
  i, x, fixed, fillIdx, fillW: Integer;
begin
  SetLength(Result, Length(AWidths));
  // total fixed width + locate the first fill (<=0) panel
  fixed := 0; fillIdx := -1;
  for i := 0 to High(AWidths) do
    if AWidths[i] > 0 then Inc(fixed, AWidths[i])
    else if fillIdx < 0 then fillIdx := i;
  fillW := ATotalWidth - 2*APadding - fixed;
  if fillW < 0 then fillW := 0;
  x := APadding;
  for i := 0 to High(AWidths) do
  begin
    Result[i].Left := x;
    Result[i].Top := 0;
    if AWidths[i] > 0 then Inc(x, AWidths[i])
    else if i = fillIdx then Inc(x, fillW);   // later <=0 panels add 0
    Result[i].Right := x;
    Result[i].Bottom := 0;   // caller sets vertical extent
  end;
end;

{ TTyStatusPanel }
constructor TTyStatusPanel.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FWidth := 50;
  FAlignment := taLeftJustify;
end;
procedure TTyStatusPanel.SetText(const AValue: string);
begin if FText = AValue then Exit; FText := AValue; Changed(False); end;
procedure TTyStatusPanel.SetWidth(AValue: Integer);
begin if FWidth = AValue then Exit; FWidth := AValue; Changed(False); end;
procedure TTyStatusPanel.SetAlignment(AValue: TAlignment);
begin if FAlignment = AValue then Exit; FAlignment := AValue; Changed(False); end;

{ TTyStatusPanels }
function TTyStatusPanels.GetItem(AIndex: Integer): TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Items[AIndex]); end;
function TTyStatusPanels.Add: TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Add); end;

procedure TTyStatusPanels.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if (GetOwner <> nil) and (GetOwner is TControl) then TControl(GetOwner).Invalidate;
end;

{ TTyStatusBar }
constructor TTyStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPanels := TTyStatusPanels.Create(Self, TTyStatusPanel);
  FSizeGrip := True;
  Align := alBottom;
  Width := 200;
  Height := 22;
end;
destructor TTyStatusBar.Destroy;
begin
  FPanels.Free;
  inherited Destroy;
end;
procedure TTyStatusBar.SetPanels(AValue: TTyStatusPanels); begin FPanels.Assign(AValue); end;
procedure TTyStatusBar.SetSimplePanel(AValue: Boolean); begin if FSimplePanel = AValue then Exit; FSimplePanel := AValue; Invalidate; end;
procedure TTyStatusBar.SetSimpleText(const AValue: string); begin if FSimpleText = AValue then Exit; FSimpleText := AValue; if FSimplePanel then Invalidate; end;
procedure TTyStatusBar.SetSizeGrip(AValue: Boolean); begin if FSizeGrip = AValue then Exit; FSizeGrip := AValue; Invalidate; end;

function TTyStatusBar.GetStyleTypeKey: string;
begin Result := 'TyStatusBar'; end;

function TTyStatusBar.PanelAtPos(X, Y: Integer): Integer;
var
  rects: TTyRectArray;
  ws: array of Integer;
  i: Integer;
begin
  Result := -1;
  if FSimplePanel or (FPanels.Count = 0) then Exit;
  SetLength(ws, FPanels.Count);
  for i := 0 to FPanels.Count - 1 do ws[i] := FPanels[i].Width;
  rects := TyStatusPanelRects(ws, ClientWidth, 6);   // 6 = logical padding; see RenderTo
  for i := 0 to High(rects) do
    if (X >= rects[i].Left) and (X < rects[i].Right) then Exit(i);
end;

procedure TTyStatusBar.Paint;
begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;

procedure TTyStatusBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, i, padX, fs, bw, gx, gy, k: Integer;
  bg, grip: TTyFill;
  rects: TTyRectArray;
  ws: array of Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    padX := P.Scale(6);
    fs := ResolveFontSize(S);
    // background fill (whole) + a 1px top border line (status-bar look — not a full frame)
    bg := Default(TTyFill); bg.Kind := tfkSolid; bg.Color := S.Background.Color;
    if tpBackground in S.Present then P.FillBackground(Rect(0, 0, W, H), bg, 0);
    bw := P.Scale(S.BorderWidth); if bw < 1 then bw := 1;
    if tpBorderColor in S.Present then
    begin
      bg.Color := S.BorderColor;
      P.FillBackground(Rect(0, 0, W, bw), bg, 0);   // top hairline
    end;
    if FSimplePanel then
      P.DrawText(Rect(padX, 0, W - padX, H), FSimpleText, S.FontName, fs, S.FontWeight, S.TextColor, taLeftJustify, tlCenter, True)
    else
    begin
      SetLength(ws, FPanels.Count);
      for i := 0 to FPanels.Count - 1 do ws[i] := FPanels[i].Width;
      rects := TyStatusPanelRects(ws, W, padX);
      for i := 0 to High(rects) do
      begin
        if i > 0 then   // separator before each panel after the first
        begin
          bg.Color := S.BorderColor;
          P.FillBackground(Rect(rects[i].Left, P.Scale(3), rects[i].Left + 1, H - P.Scale(3)), bg, 0);
        end;
        P.DrawText(Rect(rects[i].Left + P.Scale(2), 0, rects[i].Right - P.Scale(2), H),
          FPanels[i].Text, S.FontName, fs, S.FontWeight, S.TextColor, FPanels[i].Alignment, tlCenter, True);
      end;
    end;
    if FSizeGrip then    // 3 diagonal dots, bottom-right, in muted text color
    begin
      grip := Default(TTyFill); grip.Kind := tfkSolid; grip.Color := S.TextColor;
      for k := 0 to 2 do
      begin
        gx := W - P.Scale(3) - k*P.Scale(4);
        gy := H - P.Scale(3) - k*P.Scale(4);
        P.FillBackground(Rect(gx, gy, gx + P.Scale(2), gy + P.Scale(2)), grip, P.Scale(1));
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
