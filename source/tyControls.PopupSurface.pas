unit tyControls.PopupSurface;
{$mode objfpc}{$H+}

{ TTyPopupSurface — a borderless, themed floating window used as a transient flyout by the
  ribbon: the collapsed-group popup (F3), the minimized-ribbon tab flyout (F4) and the
  KeyTip overlay (F5). Ribbon pages / groups / command buttons are WINDOWED controls, so a
  flyout that must appear ABOVE them cannot be painted on the ribbon's own canvas — it needs
  a real top-level window. This is that window.

  It can ADOPT an existing control (temporarily re-parent it into the popup so its live child
  controls keep working), and RELEASE it back to its original parent on close — the LCL-native
  way Office moves a group's content into a flyout. It closes on Escape or when it loses focus
  (a click outside).

  Colours come from TyDefaultController's resolved StyleKey style (default 'TyRibbon'); the
  window has no OS chrome. Pure placement (TyPopupPlaceBelow) is headless-unit-tested; the
  on-screen popup + re-parenting need a real machine. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.PlatformWS,
  tyControls.QtWS, tyControls.GtkWS;

type
  TTyPopupSurface = class(TForm)
  private
    FContent: TControl;
    FOrigParent: TWinControl;
    FOrigAlign: TAlign;
    FOrigBounds: TRect;
    FOrigVisible: Boolean;
    FStyleKey: string;
    FOnPopupClose: TNotifyEvent;
    procedure DoDeactivate(Sender: TObject);
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); reintroduce;
    { Re-parent AControl into this popup (fills it, alClient), remembering its original
      parent/align/bounds/visible so ReleaseContent (called by ClosePopup) restores it. Only
      one control is adopted at a time; adopting a second releases the first. }
    procedure AdoptContent(AControl: TControl);
    { Restore a previously adopted control to its original parent/align/bounds/visibility.
      No-op when nothing was adopted. }
    procedure ReleaseContent;
    { Position at AScreenRect (screen px) and show on top. AAnchor (optional) is the control the
      popup drops from -- used ONLY on GTK3/Wayland, where a top-level cannot be placed by screen
      coords and the popup must be anchored to it (see TyGtk3MakePopup). Win/Qt/X11 ignore it. }
    procedure ShowAt(const AScreenRect: TRect; AAnchor: TControl = nil);
    { Release any adopted content and hide. Fires OnPopupClose. Idempotent. }
    procedure ClosePopup;
    { The token whose resolved style paints the popup background/border. Default 'TyRibbon'. }
    property StyleKey: string read FStyleKey write FStyleKey;
    { Fired after the popup hides (Escape / lost focus / ClosePopup). }
    property OnPopupClose: TNotifyEvent read FOnPopupClose write FOnPopupClose;
  end;

{ Pure placement (screen px): put a AW x AH popup directly BELOW AAnchor; if it would run off
  the bottom of the AScreen work area, flip it ABOVE the anchor; clamp X into AScreen. }
function TyPopupPlaceBelow(const AAnchor: TRect; AW, AH: Integer; const AScreen: TRect): TRect;

implementation

function TyPopupPlaceBelow(const AAnchor: TRect; AW, AH: Integer; const AScreen: TRect): TRect;
var
  x, y: Integer;
begin
  x := AAnchor.Left;
  y := AAnchor.Bottom;
  if y + AH > AScreen.Bottom then
  begin
    y := AAnchor.Top - AH;               // flip above
    if y < AScreen.Top then y := AScreen.Top;
  end;
  if x + AW > AScreen.Right then x := AScreen.Right - AW;
  if x < AScreen.Left then x := AScreen.Left;
  Result := Rect(x, y, x + AW, y + AH);
end;

constructor TTyPopupSurface.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  BorderStyle := bsNone;
  TyPreparePopupWindow(Self);   // GTK3: opt into a native POPUP window (switch, default off)
  FormStyle := fsStayOnTop;
  ShowInTaskBar := stNever;
  Position := poDesigned;
  KeyPreview := True;
  FStyleKey := 'TyRibbon';
  OnDeactivate := @DoDeactivate;
  Visible := False;
end;

procedure TTyPopupSurface.DoDeactivate(Sender: TObject);
begin
  // Lost focus (a click outside) -> dismiss, like a menu/flyout.
  ClosePopup;
end;

procedure TTyPopupSurface.AdoptContent(AControl: TControl);
begin
  if AControl = nil then Exit;
  if FContent <> nil then ReleaseContent;
  FContent := AControl;
  FOrigParent := AControl.Parent;
  FOrigAlign := AControl.Align;
  FOrigBounds := AControl.BoundsRect;
  FOrigVisible := AControl.Visible;
  AControl.Parent := Self;
  AControl.Align := alClient;
  AControl.Visible := True;
end;

procedure TTyPopupSurface.ReleaseContent;
var
  c: TControl;
begin
  if FContent = nil then Exit;
  c := FContent;
  FContent := nil;                 // clear first (SetParent can re-enter via alignment)
  c.Align := alNone;
  c.Parent := FOrigParent;
  c.BoundsRect := FOrigBounds;
  c.Align := FOrigAlign;
  c.Visible := FOrigVisible;
end;

procedure TTyPopupSurface.ShowAt(const AScreenRect: TRect; AAnchor: TControl = nil);
var
  S: TTyStyleSet;
begin
  // Set the form's Color to the resolved surface bg BEFORE showing. Windowed children with a
  // transparent/ghost fill erase to their parent's Color (TyResolveParentBg's last resort); without
  // this the popup keeps the OS default clBtnFace — which is DARK on a dark-mode OS — so flat/ghost
  // child buttons would render on a dark plate even under a light theme.
  S := TyDefaultController.Model.ResolveStyle(FStyleKey, '', []);
  if (tpBackground in S.Present) and (S.Background.Kind = tfkSolid) then
    Color := TyColorToLCL(S.Background.Color);
  SetBounds(AScreenRect.Left, AScreenRect.Top,
    AScreenRect.Right - AScreenRect.Left, AScreenRect.Bottom - AScreenRect.Top);
  // Qt6: re-type as a Qt::Popup BEFORE Show so it maps app-positioned (no WM centering / top-left
  // flash) and grabs the mouse like a menu -- the same call the themed menus + Popup make. No-op
  // off Qt. Without it a plain top-level TTyPopupSurface is centred by the WM: the ribbon flyout
  // and the toolbar/coolbar overflow flyout both hit this on Qt6.
  TyQtMakePopup(Self);
  // GTK3/Wayland: a top-level can't be placed by screen coords, so anchor the popup to the
  // control it drops from (no-op off GTK3, and off GTK3-Wayland; harmless when AAnchor is nil).
  TyGtk3MakePopup(Self, AAnchor);
  Show;
  BringToFront;
end;

procedure TTyPopupSurface.ClosePopup;
begin
  ReleaseContent;
  if Visible then Hide;
  if Assigned(FOnPopupClose) then FOnPopupClose(Self);
end;

procedure TTyPopupSurface.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    ClosePopup;
  end;
end;

procedure TTyPopupSurface.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H: Integer;
begin
  S := TyDefaultController.Model.ResolveStyle(FStyleKey, '', []);
  W := ClientWidth;
  H := ClientHeight;
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, Rect(0, 0, W, H), Font.PixelsPerInch);
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, W, H), S.Background, S.BorderRadius);
    // A visible edge even when the theme's ribbon surface has no border of its own.
    if (tpBorderColor in S.Present) and (S.BorderWidth > 0) then
      P.StrokeBorder(Rect(0, 0, W, H), S.BorderRadius, S.BorderWidth, S.BorderColor)
    else
      P.StrokeBorder(Rect(0, 0, W, H), S.BorderRadius, 1, S.TextColor);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
