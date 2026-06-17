unit tyControls.Form;

{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}
{$modeswitch objectivec1}
{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller;

type
  TTyBorderHit = (bhNone, bhLeft, bhTop, bhRight, bhBottom,
                  bhTopLeft, bhTopRight, bhBottomLeft, bhBottomRight);

  TTyCaptionButtonKind = (cbkClose, cbkMin, cbkMax, cbkRestore);

  TTyContentPanel = class(TTyCustomControl)
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    function GetStyleTypeKey: string; override;
  end;

  TTyChromeEngine = class;

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
    FEngine: TTyChromeEngine;
    procedure SetCaption(const AValue: string);
    procedure SetButtonWidth(AValue: Integer);
    function VisibleButtonCount: Integer;
    function LeftInsetPx: Integer;
  protected
    procedure LayoutButtons;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Resize; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure Paint; override;
    { Window-drag / double-click-maximize are wired via these METHOD OVERRIDES
      (each calls inherited first, so a user-assigned published OnMouseDown/Move/
      Up/DblClick still fires) then delegates to the chrome engine. This frees the
      mouse-event slots for user assignment without clobbering the engine wiring. }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    property MinButton: TTyCaptionButton read FMinButton;
    property MaxButton: TTyCaptionButton read FMaxButton;
    property CloseButton: TTyCaptionButton read FCloseButton;
    function RightInset: Integer;
  published
    property Caption: string read FCaption write SetCaption;
    property Align;
    property Anchors;
    property ButtonWidth: Integer read FButtonWidth write SetButtonWidth;
  end;

  TTyChromeEngine = class(TObject)
  private
    FForm: TCustomForm;
    FTitleBar: TTyTitleBar;
    FBorderZone: Integer;
    FInstalledPPI: Integer;
    FDragging: Boolean;
    FDragStart: TPoint;
    FResizing: Boolean;
    FResizeHit: TTyBorderHit;
    FResizeStartBounds: TRect;
    FResizeStartMouse: TPoint;
    FMaximized: Boolean;
    FSavedBounds: TRect;
  public
    constructor Create(ATitleBar: TTyTitleBar);
    procedure CaptureInstalledPPI;
    procedure TitleBarMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarDblClick;
    procedure FormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure FormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HandleChangeBounds;
    procedure ToggleMaximize;
    property Form: TCustomForm read FForm write FForm;
    property BorderZone: Integer read FBorderZone write FBorderZone;
    property Maximized: Boolean read FMaximized write FMaximized;
    property Dragging: Boolean read FDragging;
  end;

  TTyForm = class(TForm)
  private
    FTitleBar: TTyTitleBar;
    FContent: TTyContentPanel;
    FResizeBorder: Integer;
    FShowMinimize: Boolean;
    FShowMaximize: Boolean;
    procedure SetupChrome;
    function GetTitleHeight: Integer;
    procedure SetTitleHeight(AValue: Integer);
    procedure SetShowMinimize(AValue: Boolean);
    procedure SetShowMaximize(AValue: Boolean);
    procedure DoMinimizeClick(Sender: TObject);
    procedure DoMaxRestoreClick(Sender: TObject);
    procedure DoCloseClick(Sender: TObject);
  protected
    { The window-behavior engine. Protected so a test access subclass can read its
      drag/maximize state through it. }
    FEngine: TTyChromeEngine;
    procedure Loaded; override;
    procedure ReparentContentChildren(Data: PtrInt);
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoOnChangeBounds; override;
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    procedure ApplyChromeTheme(AController: TTyStyleController);
    property TitleBar: TTyTitleBar read FTitleBar;
    property ContentPanel: TTyContentPanel read FContent;
  published
    property TitleHeight: Integer read GetTitleHeight write SetTitleHeight default 32;
    property ShowMinimize: Boolean read FShowMinimize write SetShowMinimize default True;
    property ShowMaximize: Boolean read FShowMaximize write SetShowMaximize default True;
  end;

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
function TyResizeCursor(AHit: TTyBorderHit): TCursor;
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

function TyResizeCursor(AHit: TTyBorderHit): TCursor;
begin
  case AHit of
    bhLeft, bhRight: Result := crSizeWE;
    bhTop, bhBottom: Result := crSizeNS;
    bhTopLeft, bhBottomRight: Result := crSizeNWSE;
    bhTopRight, bhBottomLeft: Result := crSizeNESW;
  else
    Result := crDefault;
  end;
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
  R, GlyphRect: TRect;
  GlyphSize: Integer;
  CX, CY: Integer;
  DrawGlyph: Boolean;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    { Determine whether glyph should be drawn }
    if FShowGlyphOnHoverOnly then
      DrawGlyph := FHover or FPressed
    else
      DrawGlyph := True;
    if DrawGlyph then
    begin
      GlyphSize := P.Scale(10);
      CX := R.Left + (R.Right - R.Left - GlyphSize) div 2;
      CY := R.Top + (R.Bottom - R.Top - GlyphSize) div 2;
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

{ TTyContentPanel }

function TTyContentPanel.GetStyleTypeKey: string;
begin
  Result := 'TyContentPanel';
end;

procedure TTyContentPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top), S);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyContentPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ TTyTitleBar }

constructor TTyTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FButtonWidth := TyTitleButtonWidth;
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

procedure TTyTitleBar.SetButtonWidth(AValue: Integer);
begin
  if FButtonWidth = AValue then
    Exit;
  FButtonWidth := AValue;
  LayoutButtons;
  Invalidate;
end;

function TTyTitleBar.VisibleButtonCount: Integer;
begin
  if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then
    Exit(0);
  Result := Ord(FMinButton.Visible) + Ord(FMaxButton.Visible) + Ord(FCloseButton.Visible);
end;

function TTyTitleBar.RightInset: Integer;
begin
  Result := VisibleButtonCount * FButtonWidth;
end;

function TTyTitleBar.LeftInsetPx: Integer;
begin
  Result := MulDiv(TyTitleBarPad, Font.PixelsPerInch, 96);
end;

procedure TTyTitleBar.LayoutButtons;
var
  W, H, X: Integer;
begin
  if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then
    Exit;
  W := FButtonWidth;
  H := ClientHeight;
  X := ClientWidth;
  if FCloseButton.Visible then begin Dec(X, W); FCloseButton.SetBounds(X, 0, W, H); end;
  if FMaxButton.Visible then begin Dec(X, W); FMaxButton.SetBounds(X, 0, W, H); end;
  if FMinButton.Visible then begin Dec(X, W); FMinButton.SetBounds(X, 0, W, H); end;
end;

procedure TTyTitleBar.Resize;
begin
  inherited Resize;
  LayoutButtons;
end;

procedure TTyTitleBar.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Left, LeftInsetPx);
  Dec(ARect.Right, RightInset);
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
end;

procedure TTyTitleBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextRect: TRect;
  W, H: Integer;
begin
  W := ARect.Right - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, W, H);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    TextRect := Rect(R.Left + P.Scale(TyTitleBarPad), R.Top,
                     R.Left + W - RightInset, R.Top + H);
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

procedure TTyTitleBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FEngine <> nil then
    FEngine.TitleBarMouseDown(Button, Shift, X, Y);
end;

procedure TTyTitleBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FEngine <> nil then
    FEngine.TitleBarMouseMove(Shift, X, Y);
end;

procedure TTyTitleBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FEngine <> nil then
    FEngine.TitleBarMouseUp(Button, Shift, X, Y);
end;

procedure TTyTitleBar.DblClick;
begin
  inherited DblClick;
  if FEngine <> nil then
    FEngine.TitleBarDblClick;
end;

{ TTyChromeEngine }

constructor TTyChromeEngine.Create(ATitleBar: TTyTitleBar);
begin
  inherited Create;
  FTitleBar := ATitleBar;
  FBorderZone := 6;
  FMaximized := False;
end;

procedure TTyChromeEngine.CaptureInstalledPPI;
begin
  if (FForm <> nil) and (FForm.Monitor <> nil) then
    FInstalledPPI := FForm.Monitor.PixelsPerInch
  else
    FInstalledPPI := Screen.PixelsPerInch;
end;

procedure TTyChromeEngine.TitleBarMouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (FForm <> nil) and not FMaximized then
  begin
    FDragging := True;
    FDragStart := Point(X, Y);
  end;
end;

procedure TTyChromeEngine.TitleBarMouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if FDragging and (FForm <> nil) then
  begin
    FForm.Left := FForm.Left + (X - FDragStart.X);
    FForm.Top := FForm.Top + (Y - FDragStart.Y);
  end;
end;

procedure TTyChromeEngine.TitleBarMouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
end;

procedure TTyChromeEngine.TitleBarDblClick;
begin
  ToggleMaximize;
end;

procedure TTyChromeEngine.FormMouseDown(Button: TMouseButton;
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

procedure TTyChromeEngine.FormMouseMove(Shift: TShiftState; X, Y: Integer);
var
  M: TPoint;
  DX, DY: Integer;
  B: TRect;
begin
  if FForm = nil then
    Exit;
  { Hover path (not actively resizing): reflect the border zone under the cursor
    so the user sees the native resize cursor before pressing. While FResizing is
    True the cursor was already set on the hit press and the form is being sized,
    so we leave it alone and fall through to the resize-drag logic below. }
  if not FResizing then
  begin
    FForm.Cursor := TyResizeCursor(TyHitTestBorder(
      Rect(0, 0, FForm.Width, FForm.Height), Point(X, Y), FBorderZone));
    Exit;
  end;
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

procedure TTyChromeEngine.FormMouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FResizing := False;
  FResizeHit := bhNone;
end;

procedure TTyChromeEngine.HandleChangeBounds;
var
  CurPPI: Integer;
begin
  if FForm = nil then Exit;
  if FForm.Monitor <> nil then
    CurPPI := FForm.Monitor.PixelsPerInch
  else
    CurPPI := Screen.PixelsPerInch;
  if (FInstalledPPI > 0) and (CurPPI <> FInstalledPPI) then
  begin
    FTitleBar.Height := TyRescaleChromeMetric(FTitleBar.Height, FInstalledPPI, CurPPI);
    FTitleBar.FButtonWidth := TyRescaleChromeMetric(FTitleBar.FButtonWidth, FInstalledPPI, CurPPI);
    FTitleBar.LayoutButtons;
    FInstalledPPI := CurPPI;
    FForm.Invalidate;
  end;
end;

procedure TTyChromeEngine.ToggleMaximize;
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

{ TTyForm }

procedure TTyForm.SetupChrome;
begin
  BorderStyle := bsNone;
  FResizeBorder := 6;
  FShowMinimize := True;
  FShowMaximize := True;

  FTitleBar := TTyTitleBar.Create(Self);
  FTitleBar.Name := 'TyTitleBar';
  FTitleBar.SetSubComponent(True);
  FTitleBar.Parent := Self;
  FTitleBar.Align := alTop;
  FTitleBar.Height := 32;

  FContent := TTyContentPanel.Create(Self);
  FContent.Name := 'TyContent';
  FContent.SetSubComponent(True);
  FContent.Parent := Self;
  FContent.Align := alClient;
  FContent.BorderSpacing.Left := FResizeBorder;
  FContent.BorderSpacing.Right := FResizeBorder;
  FContent.BorderSpacing.Bottom := FResizeBorder;

  FEngine := TTyChromeEngine.Create(FTitleBar);
  FEngine.Form := Self;
  FEngine.BorderZone := FResizeBorder;
  FEngine.CaptureInstalledPPI;
  FTitleBar.FEngine := FEngine;

  FTitleBar.MinButton.OnClick := @DoMinimizeClick;
  FTitleBar.MaxButton.OnClick := @DoMaxRestoreClick;
  FTitleBar.CloseButton.OnClick := @DoCloseClick;
end;

constructor TTyForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  if FTitleBar = nil then SetupChrome;
end;

constructor TTyForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  if FTitleBar = nil then SetupChrome;
end;

destructor TTyForm.Destroy;
begin
  if FTitleBar <> nil then FTitleBar.FEngine := nil;
  FEngine.Free;
  inherited Destroy;
end;

procedure TTyForm.DoMinimizeClick(Sender: TObject);
begin WindowState := wsMinimized; end;

procedure TTyForm.DoMaxRestoreClick(Sender: TObject);
begin if FEngine <> nil then FEngine.ToggleMaximize; end;

procedure TTyForm.DoCloseClick(Sender: TObject);
begin Close; end;

procedure TTyForm.Loaded;
begin
  inherited Loaded;
  // Defer the stray-child reparent to after the form is fully loaded and shown.
  // Reparenting during Loaded leaves the form's autosizing locked
  // (AutoSizeDelayed=True), which makes TWinControl.UpdateShowing skip the show —
  // the form ends up Visible=True but never actually displayed.
  Application.QueueAsyncCall(@ReparentContentChildren, 0);
end;

procedure TTyForm.ReparentContentChildren(Data: PtrInt);
var i: Integer; Ctl: TControl;
begin
  for i := ControlCount - 1 downto 0 do
  begin
    Ctl := Controls[i];
    if (Ctl <> FTitleBar) and (Ctl <> FContent) then
      Ctl.Parent := FContent;
  end;
end;

procedure TTyForm.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FEngine <> nil then FEngine.FormMouseDown(Button, Shift, X, Y);
end;

procedure TTyForm.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FEngine <> nil then FEngine.FormMouseMove(Shift, X, Y);
end;

procedure TTyForm.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FEngine <> nil then FEngine.FormMouseUp(Button, Shift, X, Y);
end;

procedure TTyForm.DoOnChangeBounds;
begin
  inherited DoOnChangeBounds;
  if FEngine <> nil then FEngine.HandleChangeBounds;
end;

function TTyForm.GetTitleHeight: Integer;
begin Result := FTitleBar.Height; end;

procedure TTyForm.SetTitleHeight(AValue: Integer);
begin if FTitleBar.Height <> AValue then FTitleBar.Height := AValue; end;

procedure TTyForm.SetShowMinimize(AValue: Boolean);
begin FShowMinimize := AValue; FTitleBar.MinButton.Visible := AValue; FTitleBar.LayoutButtons; end;

procedure TTyForm.SetShowMaximize(AValue: Boolean);
begin FShowMaximize := AValue; FTitleBar.MaxButton.Visible := AValue; FTitleBar.LayoutButtons; end;

procedure TTyForm.ApplyChromeTheme(AController: TTyStyleController);
var bg: TTyStyleSet;
begin
  if AController = nil then Exit;
  { Propagate the controller to every chrome sub-component FIRST, so the whole
    window chrome themes from the SAME controller the app loaded its theme into
    (each styleable control resolves its theme via its Controller). }
  FTitleBar.Controller := AController;
  FContent.Controller := AController;
  FTitleBar.MinButton.Controller := AController;
  FTitleBar.MaxButton.Controller := AController;
  FTitleBar.CloseButton.Controller := AController;
  bg := AController.Model.ResolveStyle('TyForm', '', []);
  if (tpBackground in bg.Present) and (bg.Background.Kind = tfkSolid) then
    Color := TyColorToLCL(bg.Background.Color);
  Invalidate;
end;

end.
