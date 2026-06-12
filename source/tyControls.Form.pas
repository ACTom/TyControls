unit tyControls.Form;

{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}
{$modeswitch objectivec1}
{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller;

type
  TTyBorderHit = (bhNone, bhLeft, bhTop, bhRight, bhBottom,
                  bhTopLeft, bhTopRight, bhBottomLeft, bhBottomRight);

  TTyCaptionButtonKind = (cbkClose, cbkMin, cbkMax, cbkRestore);

  TTyCaptionButton = class(TTyCustomControl)
  private
    FKind: TTyCaptionButtonKind;
    FShowGlyphOnHoverOnly: Boolean;
    procedure SetKind(AValue: TTyCaptionButtonKind);
    procedure SetShowGlyphOnHoverOnly(AValue: Boolean);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
  public
    function GetStyleTypeKey: string; override;
    function KindVariant: string;
    function KindGlyph: TTyGlyphKind;
  published
    property Kind: TTyCaptionButtonKind read FKind write SetKind;
    property ShowGlyphOnHoverOnly: Boolean read FShowGlyphOnHoverOnly
      write SetShowGlyphOnHoverOnly default False;
    property OnClick;
  end;

  TTyTitleBar = class(TTyCustomControl)
  private
    FCaption: string;
    FMinButton: TTyCaptionButton;
    FMaxButton: TTyCaptionButton;
    FCloseButton: TTyCaptionButton;
    FButtonWidth: Integer;
    procedure SetCaption(const AValue: string);
    procedure LayoutButtons;
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Resize; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    property MinButton: TTyCaptionButton read FMinButton;
    property MaxButton: TTyCaptionButton read FMaxButton;
    property CloseButton: TTyCaptionButton read FCloseButton;
  published
    property Caption: string read FCaption write SetCaption;
  end;

  TTyFormChrome = class(TComponent)
  private
    FActive: Boolean;
    FTitleHeight: Integer;
    FBorderZone: Integer;
    FShowMinimize: Boolean;
    FShowMaximize: Boolean;
    FTitleBar: TTyTitleBar;
    FForm: TCustomForm;
    FDragging: Boolean;
    FDragStart: TPoint;
    FResizeHit: TTyBorderHit;
    FResizing: Boolean;
    FResizeStartBounds: TRect;
    FResizeStartMouse: TPoint;
    FSavedBounds: TRect;
    FMaximized: Boolean;
    FOldBorderStyle: TFormBorderStyle;
    FOldMouseDown: TMouseEvent;
    FOldMouseMove: TMouseMoveEvent;
    FOldMouseUp: TMouseEvent;
    FOldChangeBounds: TNotifyEvent;
    FInstalledPPI: Integer;
    procedure SetActive(AValue: Boolean);
    procedure SetTitleHeight(AValue: Integer);
    function HostForm: TCustomForm;
    procedure InstallChrome;
    procedure UninstallChrome;
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormChangeBounds(Sender: TObject);
    procedure TitleBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TitleBarDblClick(Sender: TObject);
    procedure DoMinimize(Sender: TObject);
    procedure DoMaxRestore(Sender: TObject);
    procedure DoClose(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    property TitleBar: TTyTitleBar read FTitleBar;
    procedure ToggleMaximize;
  published
    property Active: Boolean read FActive write SetActive default False;
    property TitleHeight: Integer read FTitleHeight write SetTitleHeight default 32;
    property BorderZone: Integer read FBorderZone write FBorderZone default 6;
    property ShowMinimize: Boolean read FShowMinimize write FShowMinimize default True;
    property ShowMaximize: Boolean read FShowMaximize write FShowMaximize default True;
  end;

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
function TyMaximizedBounds(const AWorkArea: TRect): TRect;
function TyRescaleChromeMetric(AValue, AFromPPI, AToPPI: Integer): Integer;

implementation

{$IFDEF LCLCOCOA}
uses
  CocoaAll;
{$ENDIF}

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
var
  OnLeft, OnRight, OnTop, OnBottom: Boolean;
begin
  Result := bhNone;
  if AZone <= 0 then
    Exit;
  if (APt.X < AClient.Left) or (APt.X > AClient.Right) or
     (APt.Y < AClient.Top) or (APt.Y > AClient.Bottom) then
    Exit;
  OnLeft := APt.X < (AClient.Left + AZone);
  OnRight := APt.X > (AClient.Right - AZone);
  OnTop := APt.Y < (AClient.Top + AZone);
  OnBottom := APt.Y > (AClient.Bottom - AZone);
  if OnTop and OnLeft then
    Result := bhTopLeft
  else if OnTop and OnRight then
    Result := bhTopRight
  else if OnBottom and OnLeft then
    Result := bhBottomLeft
  else if OnBottom and OnRight then
    Result := bhBottomRight
  else if OnLeft then
    Result := bhLeft
  else if OnRight then
    Result := bhRight
  else if OnTop then
    Result := bhTop
  else if OnBottom then
    Result := bhBottom
  else
    Result := bhNone;
end;

function TyMaximizedBounds(const AWorkArea: TRect): TRect;
begin
  Result.Left := AWorkArea.Left;
  Result.Top := AWorkArea.Top;
  Result.Right := AWorkArea.Right;
  Result.Bottom := AWorkArea.Bottom;
end;

function TyRescaleChromeMetric(AValue, AFromPPI, AToPPI: Integer): Integer;
begin
  if AFromPPI <= 0 then
  begin
    Result := AValue;
    Exit;
  end;
  Result := (AValue * AToPPI + AFromPPI div 2) div AFromPPI;
end;

{ TTyCaptionButton }

procedure TTyCaptionButton.SetKind(AValue: TTyCaptionButtonKind);
begin
  if FKind = AValue then
    Exit;
  FKind := AValue;
  StyleClass := KindVariant;
  Invalidate;
end;

function TTyCaptionButton.GetStyleTypeKey: string;
begin
  Result := 'TyCaptionButton';
end;

function TTyCaptionButton.KindVariant: string;
begin
  case FKind of
    cbkClose: Result := 'close';
    cbkMin: Result := 'min';
    cbkMax: Result := 'max';
    cbkRestore: Result := 'restore';
  end;
end;

function TTyCaptionButton.KindGlyph: TTyGlyphKind;
begin
  case FKind of
    cbkClose: Result := tgClose;
    cbkMin: Result := tgMinimize;
    cbkMax: Result := tgMaximize;
    cbkRestore: Result := tgRestore;
  end;
end;

procedure TTyCaptionButton.SetShowGlyphOnHoverOnly(AValue: Boolean);
begin
  if FShowGlyphOnHoverOnly = AValue then
    Exit;
  FShowGlyphOnHoverOnly := AValue;
  Invalidate;
end;

procedure TTyCaptionButton.Click;
begin
  inherited Click;
end;

procedure TTyCaptionButton.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  GlyphRect: TRect;
  GlyphSize: Integer;
  CX, CY: Integer;
  DrawGlyph: Boolean;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, ARect, S);
    { Determine whether glyph should be drawn }
    if FShowGlyphOnHoverOnly then
      DrawGlyph := FHover or FPressed
    else
      DrawGlyph := True;
    if DrawGlyph then
    begin
      GlyphSize := P.Scale(10);
      CX := ARect.Left + (ARect.Right - ARect.Left - GlyphSize) div 2;
      CY := ARect.Top + (ARect.Bottom - ARect.Top - GlyphSize) div 2;
      GlyphRect := Rect(CX, CY, CX + GlyphSize, CY + GlyphSize);
      P.DrawGlyph(GlyphRect, KindGlyph, S.TextColor, P.Scale(1));
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCaptionButton.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ TTyTitleBar }

constructor TTyTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FButtonWidth := 46;
  SetBounds(0, 0, 200, 32);
  FMinButton := TTyCaptionButton.Create(Self);
  FMinButton.Kind := cbkMin;
  FMinButton.Parent := Self;
  FMaxButton := TTyCaptionButton.Create(Self);
  FMaxButton.Kind := cbkMax;
  FMaxButton.Parent := Self;
  FCloseButton := TTyCaptionButton.Create(Self);
  FCloseButton.Kind := cbkClose;
  FCloseButton.Parent := Self;
  LayoutButtons;
end;

function TTyTitleBar.GetStyleTypeKey: string;
begin
  Result := 'TyTitleBar';
end;

procedure TTyTitleBar.SetCaption(const AValue: string);
begin
  if FCaption = AValue then
    Exit;
  FCaption := AValue;
  Invalidate;
end;

procedure TTyTitleBar.LayoutButtons;
var
  W, H, X: Integer;
begin
  if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then
    Exit;
  W := FButtonWidth;
  H := ClientHeight;
  X := ClientWidth - W;
  FCloseButton.SetBounds(X, 0, W, H);
  Dec(X, W);
  FMaxButton.SetBounds(X, 0, W, H);
  Dec(X, W);
  FMinButton.SetBounds(X, 0, W, H);
end;

procedure TTyTitleBar.Resize;
begin
  inherited Resize;
  LayoutButtons;
end;

procedure TTyTitleBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  TextRect: TRect;
  W, H: Integer;
begin
  W := ARect.Right - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, ARect, S);
    TextRect := Rect(ARect.Left + P.Scale(8), ARect.Top,
                     ARect.Left + W - 3 * FButtonWidth, ARect.Top + H);
    P.DrawText(TextRect, FCaption, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTitleBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ TTyFormChrome }

constructor TTyFormChrome.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTitleHeight := 32;
  FBorderZone := 6;
  FShowMinimize := True;
  FShowMaximize := True;
  FActive := False;
  FMaximized := False;
  FTitleBar := TTyTitleBar.Create(Self);
  FTitleBar.MinButton.OnClick := @DoMinimize;
  FTitleBar.MaxButton.OnClick := @DoMaxRestore;
  FTitleBar.CloseButton.OnClick := @DoClose;
end;

function TTyFormChrome.HostForm: TCustomForm;
begin
  Result := nil;
  if (Owner <> nil) and (Owner is TCustomForm) then
    Result := TCustomForm(Owner);
end;

procedure TTyFormChrome.SetTitleHeight(AValue: Integer);
begin
  if FTitleHeight = AValue then
    Exit;
  FTitleHeight := AValue;
  if FActive and (FForm <> nil) then
    FTitleBar.SetBounds(0, 0, FForm.ClientWidth, FTitleHeight);
end;

procedure TTyFormChrome.SetActive(AValue: Boolean);
begin
  if FActive = AValue then
    Exit;
  FActive := AValue;
  if csDesigning in ComponentState then
    Exit;
  if FActive then
    InstallChrome
  else
    UninstallChrome;
end;

procedure TTyFormChrome.InstallChrome;
begin
  FForm := HostForm;
  if FForm = nil then
    Exit;
  FOldBorderStyle := FForm.BorderStyle;
  FForm.BorderStyle := bsNone;
  { After BorderStyle:=bsNone the window handle is recreated.
    Ensure it exists before we access it. }
  FForm.HandleNeeded;
  {$IFDEF LCLCOCOA}
  { Restore the native NSWindow shadow lost when BorderStyle is set to bsNone.
    Form.Handle is a TCocoaWindowContent (NSView subclass); .window gives the
    backing NSWindow. }
  if FForm.HandleAllocated then
    NSView(FForm.Handle).window.setHasShadow(True);
  {$ENDIF}
  { Sample PPI at install time for cross-monitor rescaling }
  if FForm.Monitor <> nil then
    FInstalledPPI := FForm.Monitor.PixelsPerInch
  else
    FInstalledPPI := Screen.PixelsPerInch;
  FTitleBar.Parent := FForm;
  FTitleBar.Align := alTop;
  FTitleBar.SetBounds(0, 0, FForm.ClientWidth, FTitleHeight);
  FTitleBar.MinButton.Visible := FShowMinimize;
  FTitleBar.MaxButton.Visible := FShowMaximize;
  FOldMouseDown := TForm(FForm).OnMouseDown;
  FOldMouseMove := TForm(FForm).OnMouseMove;
  FOldMouseUp := TForm(FForm).OnMouseUp;
  FOldChangeBounds := TForm(FForm).OnChangeBounds;
  TForm(FForm).OnMouseDown := @FormMouseDown;
  TForm(FForm).OnMouseMove := @FormMouseMove;
  TForm(FForm).OnMouseUp := @FormMouseUp;
  TForm(FForm).OnChangeBounds := @FormChangeBounds;
  FTitleBar.OnMouseDown := @TitleBarMouseDown;
  FTitleBar.OnMouseMove := @TitleBarMouseMove;
  FTitleBar.OnMouseUp := @TitleBarMouseUp;
  FTitleBar.OnDblClick := @TitleBarDblClick;
end;

procedure TTyFormChrome.UninstallChrome;
begin
  if FForm = nil then
    Exit;
  TForm(FForm).OnMouseDown := FOldMouseDown;
  TForm(FForm).OnMouseMove := FOldMouseMove;
  TForm(FForm).OnMouseUp := FOldMouseUp;
  TForm(FForm).OnChangeBounds := FOldChangeBounds;
  FForm.BorderStyle := FOldBorderStyle;
  FMaximized := False;
  FTitleBar.MaxButton.Kind := cbkMax;
  FTitleBar.Parent := nil;
  FForm := nil;
end;

procedure TTyFormChrome.TitleBarMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (FForm <> nil) and not FMaximized then
  begin
    FDragging := True;
    FDragStart := Point(X, Y);
  end;
end;

procedure TTyFormChrome.TitleBarMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  if FDragging and (FForm <> nil) then
  begin
    FForm.Left := FForm.Left + (X - FDragStart.X);
    FForm.Top := FForm.Top + (Y - FDragStart.Y);
  end;
end;

procedure TTyFormChrome.TitleBarMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
end;

procedure TTyFormChrome.TitleBarDblClick(Sender: TObject);
begin
  ToggleMaximize;
end;

procedure TTyFormChrome.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button <> mbLeft) or (FForm = nil) or FMaximized then
    Exit;
  FResizeHit := TyHitTestBorder(Rect(0, 0, FForm.Width, FForm.Height),
    Point(X, Y), FBorderZone);
  if FResizeHit <> bhNone then
  begin
    FResizing := True;
    FResizeStartBounds := FForm.BoundsRect;
    FResizeStartMouse := FForm.ClientToScreen(Point(X, Y));
  end;
end;

procedure TTyFormChrome.FormMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  M: TPoint;
  DX, DY: Integer;
  B: TRect;
begin
  if not FResizing or (FForm = nil) then
    Exit;
  M := FForm.ClientToScreen(Point(X, Y));
  DX := M.X - FResizeStartMouse.X;
  DY := M.Y - FResizeStartMouse.Y;
  B := FResizeStartBounds;
  case FResizeHit of
    bhNone: ;
    bhLeft: B.Left := B.Left + DX;
    bhRight: B.Right := B.Right + DX;
    bhTop: B.Top := B.Top + DY;
    bhBottom: B.Bottom := B.Bottom + DY;
    bhTopLeft: begin B.Left := B.Left + DX; B.Top := B.Top + DY; end;
    bhTopRight: begin B.Right := B.Right + DX; B.Top := B.Top + DY; end;
    bhBottomLeft: begin B.Left := B.Left + DX; B.Bottom := B.Bottom + DY; end;
    bhBottomRight: begin B.Right := B.Right + DX; B.Bottom := B.Bottom + DY; end;
  end;
  if B.Right - B.Left < 80 then
    case FResizeHit of
      bhLeft, bhTopLeft, bhBottomLeft: B.Left := B.Right - 80;
    else
      B.Right := B.Left + 80;
    end;
  if B.Bottom - B.Top < 60 then
    case FResizeHit of
      bhTop, bhTopLeft, bhTopRight: B.Top := B.Bottom - 60;
    else
      B.Bottom := B.Top + 60;
    end;
  FForm.BoundsRect := B;
end;

procedure TTyFormChrome.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FResizing := False;
  FResizeHit := bhNone;
end;

procedure TTyFormChrome.FormChangeBounds(Sender: TObject);
var
  CurPPI: Integer;
begin
  { Cross-monitor DPI rescale: when the form moves to a monitor with different
    PPI, rescale TitleHeight and the title bar button width proportionally. }
  if FForm <> nil then
  begin
    if FForm.Monitor <> nil then
      CurPPI := FForm.Monitor.PixelsPerInch
    else
      CurPPI := Screen.PixelsPerInch;
    if (FInstalledPPI > 0) and (CurPPI <> FInstalledPPI) then
    begin
      FTitleHeight := TyRescaleChromeMetric(FTitleHeight, FInstalledPPI, CurPPI);
      FTitleBar.FButtonWidth := TyRescaleChromeMetric(FTitleBar.FButtonWidth, FInstalledPPI, CurPPI);
      FInstalledPPI := CurPPI;
      FTitleBar.SetBounds(0, 0, FForm.ClientWidth, FTitleHeight);
      FForm.Invalidate;
    end;
  end;
  if Assigned(FOldChangeBounds) then
    FOldChangeBounds(Sender);
end;

procedure TTyFormChrome.ToggleMaximize;
var
  Wa: TRect;
begin
  if FForm = nil then
    Exit;
  if FMaximized then
  begin
    FForm.BoundsRect := FSavedBounds;
    FMaximized := False;
    FTitleBar.MaxButton.Kind := cbkMax;
  end
  else
  begin
    FSavedBounds := FForm.BoundsRect;
    Wa := Screen.MonitorFromWindow(FForm.Handle).WorkareaRect;
    FForm.BoundsRect := TyMaximizedBounds(Wa);
    FMaximized := True;
    FTitleBar.MaxButton.Kind := cbkRestore;
  end;
end;

procedure TTyFormChrome.DoMinimize(Sender: TObject);
begin
  if FForm <> nil then
    FForm.WindowState := wsMinimized;
end;

procedure TTyFormChrome.DoMaxRestore(Sender: TObject);
begin
  ToggleMaximize;
end;

procedure TTyFormChrome.DoClose(Sender: TObject);
begin
  if FForm <> nil then
    FForm.Close;
end;

end.
