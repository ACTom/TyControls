unit tyControls.Base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LMessages, LCLType,
  tyControls.Types, tyControls.Controller, tyControls.StyleModel,
  tyControls.Painter;
type
  ITyStyleable = interface
    ['{A1B2C3D4-0001-0002-0003-000000000001}']
    function GetStyleTypeKey: string;
  end;

  TTyGraphicControl = class(TGraphicControl, ITyStyleable)
  private
    FStyleClass: string;
    FController: TTyStyleController;
    procedure SetStyleClass(const AValue: string);
    procedure SetController(AValue: TTyStyleController);
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
  protected
    FHover, FPressed: Boolean;
    function _AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet; virtual;
    function CurrentStyle: TTyStyleSet;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Enabled;
    property Font;
    property Hint;
    property ShowHint;
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
  end;

  TTyCustomControl = class(TCustomControl, ITyStyleable)
  private
    FStyleClass: string;
    FController: TTyStyleController;
    procedure SetStyleClass(const AValue: string);
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
  protected
    FHover, FPressed: Boolean;
    procedure SetController(AValue: TTyStyleController); virtual;
    function _AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet; virtual;
    function CurrentStyle: TTyStyleSet;
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Enabled;
    property Font;
    property Hint;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
  end;

implementation

{ TTyGraphicControl }

constructor TTyGraphicControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ActiveController.RegisterStyleable(Self);
end;

function TTyGraphicControl._AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

function TTyGraphicControl._Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

destructor TTyGraphicControl.Destroy;
begin
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  inherited Destroy;
end;

procedure TTyGraphicControl.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Invalidate;
end;

procedure TTyGraphicControl.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  { Unregister from current active controller and remove free-notification }
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  { Register with new active controller and wire free-notification }
  if FController <> nil then
    FController.FreeNotification(Self);
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyGraphicControl.CMEnabledChanged(var Msg{%H-}: TLMessage);
begin
  Invalidate;
end;

procedure TTyGraphicControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FController) then
    FController := nil;
end;

function TTyGraphicControl.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyGraphicControl.CurrentStates: TTyStateSet;
begin
  Result := [];
  if not Enabled then
  begin
    Include(Result, tysDisabled);
    Exit;
  end;
  if FHover then Include(Result, tysHover);
  if FPressed then Include(Result, tysActive);
  if Result = [] then
    Include(Result, tysNormal);
end;

function TTyGraphicControl.CurrentStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(GetStyleTypeKey, FStyleClass, CurrentStates);
end;

procedure TTyGraphicControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var
  corners, ringCorners: TTyCorners;
  off: Integer;
  ringRect: TRect;
begin
  if tpOpacity in AStyle.Present then
    APainter.Opacity := AStyle.Opacity;
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  corners := TyEffectiveCorners(AStyle);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, corners);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0)
     and not ((tpBorderStyle in AStyle.Present) and (AStyle.BorderStyle = tbsNone)) then
    APainter.StrokeBorder(ARect, corners, AStyle.BorderWidth, AStyle.BorderColor);
  // Focus ring: only present when a ':focus { outline: ... }' rule resolved.
  if (tpOutline in AStyle.Present) and (AStyle.OutlineWidth > 0) then
  begin
    off := APainter.Scale(AStyle.OutlineOffset);
    ringRect := Rect(ARect.Left + off, ARect.Top + off, ARect.Right - off, ARect.Bottom - off);
    ringCorners.TL := corners.TL - AStyle.OutlineOffset; if ringCorners.TL < 0 then ringCorners.TL := 0;
    ringCorners.TR := corners.TR - AStyle.OutlineOffset; if ringCorners.TR < 0 then ringCorners.TR := 0;
    ringCorners.BR := corners.BR - AStyle.OutlineOffset; if ringCorners.BR < 0 then ringCorners.BR := 0;
    ringCorners.BL := corners.BL - AStyle.OutlineOffset; if ringCorners.BL < 0 then ringCorners.BL := 0;
    APainter.StrokeBorder(ringRect, ringCorners, AStyle.OutlineWidth, AStyle.OutlineColor);
  end;
end;

procedure TTyGraphicControl.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TTyGraphicControl.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TTyGraphicControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
  end;
end;

procedure TTyGraphicControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := False;
    Invalidate;
  end;
end;

{ TTyCustomControl }

constructor TTyCustomControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Render to one offscreen buffer and blit once: eliminates the background-erase
  // flash on every repaint (notably the 530ms caret-blink Invalidate). Pixel output
  // is unchanged; only the on-screen WMPaint path is affected (RenderTo bypasses it).
  DoubleBuffered := True;
  ActiveController.RegisterStyleable(Self);
end;

function TTyCustomControl._AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

function TTyCustomControl._Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

destructor TTyCustomControl.Destroy;
begin
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  inherited Destroy;
end;

procedure TTyCustomControl.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Invalidate;
end;

procedure TTyCustomControl.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  { Unregister from current active controller and remove free-notification }
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  { Register with new active controller and wire free-notification }
  if FController <> nil then
    FController.FreeNotification(Self);
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyCustomControl.CMEnabledChanged(var Msg{%H-}: TLMessage);
begin
  Invalidate;
end;

procedure TTyCustomControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FController) then
    FController := nil;
end;

function TTyCustomControl.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyCustomControl.CurrentStates: TTyStateSet;
begin
  Result := [];
  if not Enabled then
  begin
    Include(Result, tysDisabled);
    Exit;
  end;
  if FHover then Include(Result, tysHover);
  if FPressed then Include(Result, tysActive);
  if Focused then Include(Result, tysFocused);
  if Result = [] then
    Include(Result, tysNormal);
end;

function TTyCustomControl.CurrentStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(GetStyleTypeKey, FStyleClass, CurrentStates);
end;

function TTyCustomControl.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  // Text size priority: theme font-size, then the control's own Font.Size, then a
  // readable default — so a typeKey without a font-size rule (or an unstyled Font)
  // never renders zero-height text.
  if AStyle.FontSize > 0 then
    Result := AStyle.FontSize
  else if Font.Size > 0 then
    Result := Font.Size
  else
    Result := 10;
end;

procedure TTyCustomControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var
  corners, ringCorners: TTyCorners;
  off: Integer;
  ringRect: TRect;
begin
  if tpOpacity in AStyle.Present then
    APainter.Opacity := AStyle.Opacity;
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  corners := TyEffectiveCorners(AStyle);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, corners);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0)
     and not ((tpBorderStyle in AStyle.Present) and (AStyle.BorderStyle = tbsNone)) then
    APainter.StrokeBorder(ARect, corners, AStyle.BorderWidth, AStyle.BorderColor);
  // Focus ring: only present when a ':focus { outline: ... }' rule resolved.
  if (tpOutline in AStyle.Present) and (AStyle.OutlineWidth > 0) then
  begin
    off := APainter.Scale(AStyle.OutlineOffset);
    ringRect := Rect(ARect.Left + off, ARect.Top + off, ARect.Right - off, ARect.Bottom - off);
    ringCorners.TL := corners.TL - AStyle.OutlineOffset; if ringCorners.TL < 0 then ringCorners.TL := 0;
    ringCorners.TR := corners.TR - AStyle.OutlineOffset; if ringCorners.TR < 0 then ringCorners.TR := 0;
    ringCorners.BR := corners.BR - AStyle.OutlineOffset; if ringCorners.BR < 0 then ringCorners.BR := 0;
    ringCorners.BL := corners.BL - AStyle.OutlineOffset; if ringCorners.BL < 0 then ringCorners.BL := 0;
    APainter.StrokeBorder(ringRect, ringCorners, AStyle.OutlineWidth, AStyle.OutlineColor);
  end;
end;

procedure TTyCustomControl.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TTyCustomControl.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TTyCustomControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
  end;
end;

procedure TTyCustomControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := False;
    Invalidate;
  end;
end;

procedure TTyCustomControl.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TTyCustomControl.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

end.
