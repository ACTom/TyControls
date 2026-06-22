unit tyControls.Form;

{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}
{$modeswitch objectivec1}
{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType, LMessages,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller,
  tyControls.Menu, tyControls.WindowEffects;

type
  TTyBorderHit = (bhNone, bhLeft, bhTop, bhRight, bhBottom,
                  bhTopLeft, bhTopRight, bhBottomLeft, bhBottomRight);

  TTyCaptionButtonKind = (cbkClose, cbkMin, cbkMax, cbkRestore);

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

  TTyTitleBar = class(TTyCustomControl, ITyTitleBarTag)
  private
    FCaption: string;
    FMinButton: TTyCaptionButton;
    FMaxButton: TTyCaptionButton;
    FCloseButton: TTyCaptionButton;
    FButtonWidth: Integer;
    FTitleAlignment: TAlignment;
    FEngine: TTyChromeEngine;
    procedure SetCaption(const AValue: string);
    procedure SetButtonWidth(AValue: Integer);
    procedure SetTitleAlignment(AValue: TAlignment);
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
    { Left (default) or centered title text. Centered lays out within the content
      zone (left pad .. start of the caption buttons), so it never overlaps them. }
    property TitleAlignment: TAlignment read FTitleAlignment write SetTitleAlignment default taLeftJustify;
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
    constructor Create;
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
    property TitleBar: TTyTitleBar read FTitleBar write FTitleBar;
    property BorderZone: Integer read FBorderZone write FBorderZone;
    property Maximized: Boolean read FMaximized write FMaximized;
    property Dragging: Boolean read FDragging;
  end;

  { A borderless form that owns a persistent chrome engine but is born EMPTY (no
    title bar). Drop a palette TTyTitleBar onto it: the bar auto-associates via the
    Notification(opInsert) hook (the LCL Form.Menu -> TMainMenu pattern), and the
    engine + caption buttons wire to it at RUNTIME. Otherwise it behaves like an
    ordinary TForm: drop your controls straight onto it and design them in place. }
  TTyForm = class(TForm, ITyGlassHost, ITyThemedBackground)
  private
    FTitleBar: TTyTitleBar;
    FMenuBar: TTyMenuBar;             // the primary menu bar (shortcut dispatch / mac global bar)
    FShowMinimize: Boolean;
    FShowMaximize: Boolean;
    FController: TTyStyleController;   // set by ApplyChromeTheme; used by Paint
    FSharpBackdrop: TBGRABitmap;      // form bg snapshot, UNblurred (fills glass corners)
    FGlassBackdrop: TBGRABitmap;      // same snapshot, blurred once for the glass pane
    FGlassKey: string;                // imagepath|WxH|blurDev — rebuild when it changes
    FGlassBlurLogical: Integer;       // theme-wide glass blur radius (0 = no glass)
    FFollowTimer: TTimer;             // P4 live-follow: polls the OS scheme/accent while following (nil unless armed)
    procedure DoFollowTick(Sender: TObject);
    procedure UpdateFollowWatch;      // (re)arm/disarm FFollowTimer per the controller's Follow policy
    // ITyGlassHost
    function GlassBackdrop: TBGRABitmap;
    function GlassSharpBackdrop: TBGRABitmap;
    function GlassClientOrigin: TPoint;
    function GlassUnderTitlebar: Boolean;
    // ITyThemedBackground — the form's themed TyForm bg, for children's parent-bg fill.
    function ThemedBgColor(out AColor: TTyColor): Boolean;
    procedure SetupChrome;
    procedure SetTitleBar(AValue: TTyTitleBar);
    procedure SetMenuBar(AValue: TTyMenuBar);
    procedure WireTitleBarButtons;
    procedure ArmEngine;
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
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    { Non-mac: the associated menu bar owns shortcut dispatch — forward the key to
      its TMainMenu before the inherited (Form.Menu / action-list) handling. On mac
      the global Form.Menu already does this, so the override just calls inherited. }
    function IsShortcut(var Message: TLMKey): Boolean; override;
    procedure Paint; override;   // draws an image backdrop when the TyForm token sets one
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoOnChangeBounds; override;
    procedure DoShow; override;   // first show: apply window corners + shadow once the handle exists
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    procedure ApplyChromeTheme(AController: TTyStyleController);
    procedure ApplyWindowEffects;   // (re)apply OS rounded corners + native shadow from the TyForm style
    function GetAbout: string;
  published
    { Read-only library version (TyVersion); the design-time editor opens the About dialog. }
    property About: string read GetAbout;
    property TitleBar: TTyTitleBar read FTitleBar write SetTitleBar;
    { Designate the primary application menu bar. Non-mac: the bar stays visible and
      owns shortcut dispatch (IsShortcut forwards to its TMainMenu). Mac: the bar's
      TMainMenu is handed to the inherited Form.Menu (the global top-of-screen bar)
      and the in-window bar is hidden. Freeing the bar nils this (FreeNotification). }
    property MenuBar: TTyMenuBar read FMenuBar write SetMenuBar;
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

{$IFDEF WINDOWS}
uses
  strings;   // StrComp(PAnsiChar, PAnsiChar) for the WM_SETTINGCHANGE area check
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
      // DrawGlyph insets ~4 logical px per side, so the glyph box must be that much
      // larger than the desired stroke extent or the icon collapses to a few pixels.
      GlyphSize := P.Scale(18);
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

{ TTyTitleBar }

constructor TTyTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Act as a real container: the designer drops controls INTO the bar (a menubar,
  // a button, …) instead of as siblings, and they lay out in the content zone that
  // AdjustClientRect carves out (left pad .. start of the caption buttons).
  ControlStyle := ControlStyle + [csAcceptsControls];
  FButtonWidth := TyTitleButtonWidth;
  FTitleAlignment := taLeftJustify;
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
  { If the owner form auto-assigned this bar during InsertComponent (which fires
    BEFORE this ctor body, so the buttons were nil then), wire them now that they
    exist. The TTyForm-side method is design-time/nil guarded. }
  if (AOwner is TTyForm) and (TTyForm(AOwner).TitleBar = Self) then
    TTyForm(AOwner).WireTitleBarButtons;
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

procedure TTyTitleBar.SetTitleAlignment(AValue: TAlignment);
begin
  if FTitleAlignment = AValue then
    Exit;
  FTitleAlignment := AValue;
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
      S.TextColor, FTitleAlignment, tlCenter, True);
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
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarMouseDown(Button, Shift, X, Y);
end;

procedure TTyTitleBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarMouseMove(Shift, X, Y);
end;

procedure TTyTitleBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarMouseUp(Button, Shift, X, Y);
end;

procedure TTyTitleBar.DblClick;
begin
  inherited DblClick;
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarDblClick;
end;

{ TTyChromeEngine }

constructor TTyChromeEngine.Create;
begin
  inherited Create;
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
  if FTitleBar = nil then Exit;
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
    if FTitleBar <> nil then FTitleBar.MaxButton.Kind := cbkMax;
  end
  else
  begin
    FSavedBounds := FForm.BoundsRect;
    Wa := Screen.MonitorFromWindow(FForm.Handle).WorkareaRect;
    FForm.BoundsRect := TyMaximizedBounds(Wa);
    FMaximized := True;
    if FTitleBar <> nil then FTitleBar.MaxButton.Kind := cbkRestore;
  end;
  // corners must go square when maximized and round again when restored
  if FForm is TTyForm then TTyForm(FForm).ApplyWindowEffects;
end;

{ TTyForm }

procedure TTyForm.SetupChrome;
begin
  BorderStyle := bsNone;
  FShowMinimize := True;
  FShowMaximize := True;
  FEngine := TTyChromeEngine.Create;
  FEngine.Form := Self;
end;

function TTyForm.GetAbout: string;
begin
  Result := TyVersion;
end;

constructor TTyForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  if FEngine = nil then SetupChrome;
end;

constructor TTyForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  if FEngine = nil then SetupChrome;
end;

destructor TTyForm.Destroy;
begin
  FreeAndNil(FFollowTimer);   // disarm the OS-follow poll
  FreeAndNil(FSharpBackdrop);
  FreeAndNil(FGlassBackdrop);
  if FTitleBar <> nil then FTitleBar.FEngine := nil;
  FEngine.Free;
  inherited Destroy;
end;

procedure TTyForm.SetTitleBar(AValue: TTyTitleBar);
begin
  if AValue = FTitleBar then Exit;
  // unwire old bar
  if FTitleBar <> nil then
  begin
    FTitleBar.FEngine := nil;
    // The buttons are created in the bar's ctor body. When SetTitleBar runs from
    // the owner-form Notification(opInsert) — which TComponent.Create fires BEFORE
    // the bar's ctor body — they may still be nil, so guard every deref.
    if FTitleBar.MinButton <> nil then FTitleBar.MinButton.OnClick := nil;
    if FTitleBar.MaxButton <> nil then FTitleBar.MaxButton.OnClick := nil;
    if FTitleBar.CloseButton <> nil then FTitleBar.CloseButton.OnClick := nil;
  end;
  FTitleBar := AValue;
  if FEngine <> nil then FEngine.TitleBar := AValue;
  if AValue <> nil then
  begin
    AValue.FreeNotification(Self);
    // Arm the live engine ONLY at runtime — never in the designer (dragging the
    // title bar would move/maximize the window instead of selecting it), and not
    // mid-load: when the bar comes from the .lfm this setter runs at fixup time
    // while csLoading is still set, and ArmEngine touches Monitor (premature handle
    // realization). Loaded arms it once streaming has finished.
    if not (csDesigning in ComponentState) and not (csLoading in ComponentState) then
      ArmEngine;
  end;
end;

{ Designate (or clear) the primary application menu bar. The cross-platform split:
  on macOS the bar's TMainMenu becomes the inherited Form.Menu (LCL renders it as
  the global top-of-screen bar) and the in-window bar is hidden; everywhere else the
  in-window bar stays visible and owns shortcut dispatch via IsShortcut. }
procedure TTyForm.SetMenuBar(AValue: TTyMenuBar);
begin
  if AValue = FMenuBar then Exit;
  {$IFDEF DARWIN}
  // Detach the previous bar's menu from the global bar before switching.
  if (FMenuBar <> nil) and (Menu = FMenuBar.Menu) then
    Menu := nil;
  {$ENDIF}
  FMenuBar := AValue;
  if AValue <> nil then
  begin
    AValue.FreeNotification(Self);
    {$IFDEF DARWIN}
    // Hand the bar's TMainMenu to the inherited Form.Menu (the global bar) and hide
    // the in-window bar; the OS draws the menu at the top of the screen.
    Menu := AValue.Menu;
    AValue.Visible := False;
    {$ENDIF}
  end;
end;

function TTyForm.IsShortcut(var Message: TLMKey): Boolean;
begin
  {$IFNDEF DARWIN}
  // Non-mac: the in-window menu bar owns dispatch. Let its TMainMenu try to match
  // and fire the shortcut first; on mac the inherited path already consults the
  // global Form.Menu (assigned in SetMenuBar), so we skip straight to inherited.
  if (FMenuBar <> nil) and (FMenuBar.Menu <> nil)
     and FMenuBar.Menu.IsShortCut(Message) then
    Exit(True);
  {$ENDIF}
  Result := inherited IsShortcut(Message);
end;

{ Connect the title bar to the live engine: back-reference so the bar's mouse
  events reach the engine, capture the install DPI, and wire the caption buttons.
  Safe to call repeatedly; never runs in the designer or before load completes. }
procedure TTyForm.ArmEngine;
begin
  if (FTitleBar = nil) or (csDesigning in ComponentState) then Exit;
  FTitleBar.FEngine := FEngine;
  if FEngine <> nil then FEngine.CaptureInstalledPPI;
  WireTitleBarButtons;
end;

procedure TTyForm.Loaded;
begin
  inherited Loaded;
  // A title bar associated from the .lfm had its engine-arming deferred (see
  // SetTitleBar); now that streaming has finished, wire it to the live engine.
  ArmEngine;
  ApplyWindowEffects;   // handle exists post-load -> apply corners + shadow
end;

procedure TTyForm.UpdateFollowWatch;
{ P4 (D8 / §3.7) LIVE FOLLOW. Arm a low-frequency poll timer exactly while the bound
  controller is following the OS; free it otherwise. We POLL rather than hook a window
  message because LCL-Win32 swallows WM_SETTINGCHANGE in its own callback (it calls
  Application.IntfSettingsChange and never DeliverMessage's it to a control's WndProc) and
  drops WM_DWMCOLORIZATIONCOLORCHANGED (< WM_USER) outright — so an overridden WndProc can
  never see either. The tick is cheap (PollSystemTheme no-ops until the OS scheme/accent
  actually moves), and re-evaluated on every ApplyChromeTheme so a Light/Dark button (which
  sets Follow:=tfManual) disarms it and an Auto/System button (tfFollowSystem) re-arms it. }
begin
  if (FController <> nil) and (FController.Follow = tfFollowSystem) then
  begin
    if FFollowTimer = nil then
    begin
      FFollowTimer := TTimer.Create(nil);   // no Owner: kept off the form's component list
      FFollowTimer.Enabled := False;
      FFollowTimer.Interval := 750;          // ≤0.75s latency on an OS toggle — imperceptible
      FFollowTimer.OnTimer := @DoFollowTick;
    end;
    FFollowTimer.Enabled := True;
  end
  else
    FreeAndNil(FFollowTimer);
end;

procedure TTyForm.DoFollowTick(Sender: TObject);
{ One poll tick. PollSystemTheme re-detects the OS scheme/accent and, only when it changed,
  re-applies it to the model + repaints registered controls, returning True. On True we also
  re-apply the form's OWN chrome (its solid Color / image backdrop / glass radius live in
  ApplyChromeTheme, which Changed does not touch). The whole effect is in PollSystemTheme so
  the logic stays headless-testable; this just drives it from the clock. }
begin
  if (FController <> nil) and FController.PollSystemTheme then
    ApplyChromeTheme(FController);
end;

{ Wire the caption-button click handlers. Split out so it can run both from
  SetTitleBar and from the title bar's own ctor tail — because when the bar is
  auto-assigned via Notification(opInsert) its buttons aren't created yet. }
procedure TTyForm.WireTitleBarButtons;
begin
  if (FTitleBar = nil) or (csDesigning in ComponentState) then Exit;
  if FTitleBar.MinButton <> nil then FTitleBar.MinButton.OnClick := @DoMinimizeClick;
  if FTitleBar.MaxButton <> nil then FTitleBar.MaxButton.OnClick := @DoMaxRestoreClick;
  if FTitleBar.CloseButton <> nil then FTitleBar.CloseButton.OnClick := @DoCloseClick;
end;

procedure TTyForm.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opInsert) and not (csLoading in ComponentState)
     and (FTitleBar = nil) and (AComponent.Owner = Self)
     and (AComponent is TTyTitleBar) then
    TitleBar := TTyTitleBar(AComponent)          // routes through SetTitleBar
  else if (Operation = opRemove) and (AComponent = FTitleBar) then
  begin
    FTitleBar := nil;
    if FEngine <> nil then FEngine.TitleBar := nil;
  end
  else if (Operation = opRemove) and (AComponent = FMenuBar) then
  begin
    {$IFDEF DARWIN}
    if Menu = FMenuBar.Menu then Menu := nil;
    {$ENDIF}
    FMenuBar := nil;
  end;
end;

procedure TTyForm.DoMinimizeClick(Sender: TObject);
begin WindowState := wsMinimized; end;

procedure TTyForm.DoMaxRestoreClick(Sender: TObject);
begin if FEngine <> nil then FEngine.ToggleMaximize; end;

procedure TTyForm.DoCloseClick(Sender: TObject);
begin Close; end;

procedure TTyForm.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.FormMouseDown(Button, Shift, X, Y);
end;

procedure TTyForm.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.FormMouseMove(Shift, X, Y);
end;

procedure TTyForm.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.FormMouseUp(Button, Shift, X, Y);
end;

procedure TTyForm.DoOnChangeBounds;
begin
  inherited DoOnChangeBounds;
  FGlassKey := '';   // client size changed -> next Paint resnapshots the backdrop
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.HandleChangeBounds;
end;

function TTyForm.GetTitleHeight: Integer;
begin
  if FTitleBar <> nil then Result := FTitleBar.Height else Result := 0;
end;

procedure TTyForm.SetTitleHeight(AValue: Integer);
begin
  if (FTitleBar <> nil) and (FTitleBar.Height <> AValue) then FTitleBar.Height := AValue;
end;

procedure TTyForm.SetShowMinimize(AValue: Boolean);
begin
  FShowMinimize := AValue;
  if FTitleBar <> nil then
  begin
    FTitleBar.MinButton.Visible := AValue;
    FTitleBar.LayoutButtons;
  end;
end;

procedure TTyForm.SetShowMaximize(AValue: Boolean);
begin
  FShowMaximize := AValue;
  if FTitleBar <> nil then
  begin
    FTitleBar.MaxButton.Visible := AValue;
    FTitleBar.LayoutButtons;
  end;
end;

function TTyForm.GlassBackdrop: TBGRABitmap;
begin
  Result := FGlassBackdrop;
end;

function TTyForm.GlassSharpBackdrop: TBGRABitmap;
begin
  Result := FSharpBackdrop;
end;

function TTyForm.GlassClientOrigin: TPoint;
begin
  Result := ClientOrigin;
end;

function TTyForm.GlassUnderTitlebar: Boolean;
begin
  Result := (FController <> nil)
    and FController.Model.ResolveStyle('TyForm', '', []).BackgroundUnderTitlebar;
end;

procedure TTyForm.Paint;
var
  bg: TTyStyleSet;
  P: TTyPainter;
  blurDev: Integer;
  newKey: string;
begin
  // When the TyForm token sets a background IMAGE, paint it across the whole client
  // (cover/stretch/center + optional blur). Otherwise fall back to the plain solid
  // Color fill the widgetset does. App controls paint on top in their own windows.
  if FController <> nil then
  begin
    bg := FController.Model.ResolveStyle('TyForm', '', []);
    if (tpBackground in bg.Present) and (bg.Background.Kind = tfkImage) then
    begin
      P := TTyPainter.Create;
      try
        P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
        P.FillBackground(ClientRect, bg.Background, 0);
        // Snapshot the form's own composited image. FSharpBackdrop is the photo base
        // EVERY control samples for its corners, so build it for ANY image theme; the
        // once-blurred FGlassBackdrop is built only when the theme uses glass. Keyed on
        // image+client-size+blur so it rebuilds only when something changes (the blur
        // dev-px is in the key, so an image->image switch that drops glass rebuilds and
        // frees the old blurred backdrop). Must duplicate before EndPaint frees P.Bitmap.
        blurDev := MulDiv(FGlassBlurLogical, Font.PixelsPerInch, 96);
        newKey := bg.Background.ImagePath + '|' + IntToStr(ClientWidth) + 'x'
          + IntToStr(ClientHeight) + '|' + IntToStr(blurDev);
        if (FSharpBackdrop = nil) or (newKey <> FGlassKey) then
        begin
          FreeAndNil(FSharpBackdrop);
          FreeAndNil(FGlassBackdrop);
          FSharpBackdrop := P.Bitmap.Duplicate as TBGRABitmap;  // photo base (all controls)
          if FGlassBlurLogical > 0 then
          begin
            if blurDev > 0 then
              FGlassBackdrop := FSharpBackdrop.FilterBlurRadial(blurDev, rbFast) as TBGRABitmap
            else
              FGlassBackdrop := FSharpBackdrop.Duplicate as TBGRABitmap;
          end;
          FGlassKey := newKey;
        end;
        P.EndPaint;
      finally
        P.Free;
      end;
      Exit;
    end;
  end;
  FreeAndNil(FSharpBackdrop);   // non-image theme: drop any stale backdrop
  FreeAndNil(FGlassBackdrop);
  inherited Paint;
end;

function TTyForm.ThemedBgColor(out AColor: TTyColor): Boolean;
{ The form's themed TyForm background colour, for a child's parent-bg fill. Resolves from
  the form's own controller when themed (= the LCL Color ApplyChromeTheme set), else from
  TyDefaultController (the built-in theme) — so it is correct in the DESIGNER too, where
  ApplyChromeTheme has not run and the raw LCL Color is the dark default. }
var
  ctrl: TTyStyleController;
  bg: TTyStyleSet;
begin
  Result := False;
  if FController <> nil then ctrl := FController else ctrl := TyDefaultController;
  bg := ctrl.Model.ResolveStyle('TyForm', '', []);
  if (tpBackground in bg.Present) and (bg.Background.Kind = tfkSolid) then
  begin
    AColor := bg.Background.Color;
    Result := True;
  end;
end;

procedure TTyForm.ApplyChromeTheme(AController: TTyStyleController);
var bg: TTyStyleSet;
begin
  if AController = nil then Exit;
  FController := AController;   // remembered so Paint can resolve an image backdrop
  FGlassBlurLogical := AController.Model.MaxGlassBlur;  // theme-wide glass radius
  FGlassKey := '';             // force a backdrop rebuild for the new theme
  { Propagate the controller to every chrome sub-component FIRST, so the whole
    window chrome themes from the SAME controller the app loaded its theme into
    (each styleable control resolves its theme via its Controller). }
  if FTitleBar <> nil then
  begin
    FTitleBar.Controller := AController;
    FTitleBar.MinButton.Controller := AController;
    FTitleBar.MaxButton.Controller := AController;
    FTitleBar.CloseButton.Controller := AController;
  end;
  bg := AController.Model.ResolveStyle('TyForm', '', []);
  if (tpBackground in bg.Present) and (bg.Background.Kind = tfkSolid) then
    Color := TyColorToLCL(bg.Background.Color);
  UpdateFollowWatch;   // arm/disarm the OS-follow poll to match the controller's Follow policy
  ApplyWindowEffects;  // re-apply corners + shadow (theme may have changed border-radius/window-shadow)
  Invalidate;
end;

procedure TTyForm.ApplyWindowEffects;
var maximized: Boolean; ctrl: TTyStyleController;
begin
  if csDesigning in ComponentState then Exit;   // never poke DWM/Cocoa on the IDE design surface
  if not HandleAllocated then Exit;
  // Default-on must work even when ApplyChromeTheme was never called: fall back to the
  // always-available built-in controller (mirrors ThemedBgColor). TyResolveWindowEffect
  // supplies the radius/shadow defaults regardless of which controller resolves the style.
  if FController <> nil then ctrl := FController else ctrl := TyDefaultController;
  // The chrome engine fakes maximize via BoundsRect, so read ITS flag (not WindowState).
  maximized := (FEngine <> nil) and FEngine.Maximized;
  TyApplyWindowEffects(Self,
    TyResolveWindowEffect(ctrl.Model.ResolveStyle('TyForm', '', []), maximized));
end;

procedure TTyForm.DoShow;
begin
  inherited DoShow;
  ApplyWindowEffects;
end;

initialization
  { Register for streaming so a TTyTitleBar dropped on a form persists/loads from
    the .lfm at RUNTIME. A form's own published fields resolve their class via RTTI,
    but an associated title bar may be an unnamed/owner-only object — without this,
    loading such an .lfm raises EClassNotFound: Class "TTyTitleBar" not found. }
  RegisterClass(TTyTitleBar);
  { Same streaming lesson for the associated menu bar (TTyForm.MenuBar): register it
    so an .lfm referencing it loads without EClassNotFound. }
  RegisterClass(TTyMenuBar);

end.
