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
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet;
    function CurrentStyle: TTyStyleSet;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    destructor Destroy; override;
  published
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
  end;

  TTyCustomControl = class(TCustomControl, ITyStyleable)
  private
    FStyleClass: string;
    FController: TTyStyleController;
    procedure SetStyleClass(const AValue: string);
    procedure SetController(AValue: TTyStyleController);
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
  protected
    FHover, FPressed: Boolean;
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet;
    function CurrentStyle: TTyStyleSet;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    destructor Destroy; override;
  published
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
  end;

implementation

{ TTyGraphicControl }

destructor TTyGraphicControl.Destroy;
begin
  if FController <> nil then
    FController.UnregisterStyleable(Self)
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
  if FController <> nil then
    FController.UnregisterStyleable(Self)
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyGraphicControl.CMEnabledChanged(var Msg: TLMessage);
begin
  Invalidate;
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
begin
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, AStyle.BorderRadius);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0) then
    APainter.StrokeBorder(ARect, AStyle.BorderRadius, AStyle.BorderWidth, AStyle.BorderColor);
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

destructor TTyCustomControl.Destroy;
begin
  if FController <> nil then
    FController.UnregisterStyleable(Self)
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
  if FController <> nil then
    FController.UnregisterStyleable(Self)
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyCustomControl.CMEnabledChanged(var Msg: TLMessage);
begin
  Invalidate;
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

procedure TTyCustomControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
begin
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, AStyle.BorderRadius);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0) then
    APainter.StrokeBorder(ARect, AStyle.BorderRadius, AStyle.BorderWidth, AStyle.BorderColor);
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
