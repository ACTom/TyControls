unit tyControls.ToggleSwitch;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyToggleSwitch = class(TTyCustomControl)
  private
    FChecked: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetChecked(const AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    function CurrentStates: TTyStateSet; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Toggle;
    procedure Click; override;
  published
    property Checked: Boolean read FChecked write SetChecked default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

implementation

{ TTyToggleSwitch }

constructor TTyToggleSwitch.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FChecked := False;
  Width := 44;
  Height := 24;
end;

function TTyToggleSwitch.GetStyleTypeKey: string;
begin
  Result := 'TyToggleSwitch';
end;

function TTyToggleSwitch.CurrentStates: TTyStateSet;
begin
  Result := inherited CurrentStates;
  if FChecked then
    Include(Result, tysActive);
end;

procedure TTyToggleSwitch.SetChecked(const AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyToggleSwitch.Toggle;
begin
  SetChecked(not FChecked);
end;

procedure TTyToggleSwitch.Click;
begin
  Toggle;
  inherited Click;
end;

procedure TTyToggleSwitch.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if Key = VK_SPACE then
  begin
    Toggle;
    Key := 0;
  end;
end;

procedure TTyToggleSwitch.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, TrackS: TTyStyleSet;
  R: TRect;
  TrackRadius: Integer;
  DevH, Margin, KnobSide, KnobLogical, KnobX, KnobRadiusLogical: Integer;
  KnobRect: TRect;
  KnobFill: TTyFill;
begin
  P := TTyPainter.Create;
  try
    R := ARect;
    P.BeginPaint(ACanvas, R, APPI);
    S := CurrentStyle;

    // Build a track style with a pill border-radius.
    // If the theme supplies a BorderRadius, use it; otherwise half the device height.
    TrackS := S;
    DevH := R.Bottom - R.Top;
    if TrackS.BorderRadius = 0 then
    begin
      // Compute logical radius so that Scale() → device half-height
      TrackRadius := MulDiv(DevH, 96, APPI) div 2;
      TrackS.BorderRadius := TrackRadius;
    end;
    DrawFrame(P, R, TrackS);

    // Knob geometry (device pixels)
    Margin := P.Scale(3);
    KnobSide := DevH - 2 * Margin;
    if KnobSide < 1 then KnobSide := 1;

    if FChecked then
      KnobX := (R.Right - R.Left) - Margin - KnobSide
    else
      KnobX := Margin;

    KnobRect := Rect(KnobX, Margin, KnobX + KnobSide, Margin + KnobSide);

    // Logical knob values for FillBackground (which calls Scale internally)
    KnobLogical := MulDiv(KnobSide, 96, APPI);
    KnobRadiusLogical := KnobLogical div 2;

    // Knob fill: solid TextColor (white in the spec)
    KnobFill := Default(TTyFill);
    KnobFill.Kind := tfkSolid;
    KnobFill.Color := S.TextColor;

    P.FillBackground(KnobRect, KnobFill, KnobRadiusLogical);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyToggleSwitch.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
