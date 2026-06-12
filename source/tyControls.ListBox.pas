unit tyControls.ListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyListBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FItemHeight: Integer;
    FTopIndex: Integer;
    FOnChange: TNotifyEvent;
    procedure SetItems(const AValue: TStringList);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetItemHeight(const AValue: Integer);
    procedure SetTopIndex(const AValue: Integer);
    function ScaledItemHeight: Integer;
    function MaxTopIndex: Integer;
    procedure EnsureSelectionVisible;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SelectItem(AIndex: Integer);
    function VisibleRows: Integer;
    // Public helper for headless keyboard tests
    procedure SimulateKeyDown(AKey: Word);
  published
    property Items: TStringList read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property ItemHeight: Integer read FItemHeight write SetItemHeight default 24;
    property TopIndex: Integer read FTopIndex write SetTopIndex default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyListBox }

constructor TTyListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItemIndex := -1;
  FItemHeight := 24;
  FTopIndex := 0;
  TabStop := True;
  Width := 160;
  Height := 120;
end;

destructor TTyListBox.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TTyListBox.GetStyleTypeKey: string;
begin
  Result := 'TyListBox';
end;

procedure TTyListBox.SetItems(const AValue: TStringList);
begin
  FItems.Assign(AValue);
  // Clamp TopIndex and ItemIndex in case list shrank
  if FTopIndex > MaxTopIndex then
    FTopIndex := MaxTopIndex;
  if (FItemIndex >= 0) and (FItemIndex >= FItems.Count) then
  begin
    FItemIndex := -1;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
  Invalidate;
end;

procedure TTyListBox.SetItemIndex(const AValue: Integer);
begin
  SelectItem(AValue);
end;

procedure TTyListBox.SetItemHeight(const AValue: Integer);
begin
  if FItemHeight = AValue then Exit;
  FItemHeight := AValue;
  if FItemHeight < 1 then FItemHeight := 1;
  Invalidate;
end;

function TTyListBox.MaxTopIndex: Integer;
begin
  Result := FItems.Count - VisibleRows;
  if Result < 0 then Result := 0;
end;

procedure TTyListBox.SetTopIndex(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < 0 then Clamped := 0;
  if Clamped > MaxTopIndex then Clamped := MaxTopIndex;
  if FTopIndex = Clamped then Exit;
  FTopIndex := Clamped;
  Invalidate;
end;

function TTyListBox.ScaledItemHeight: Integer;
begin
  Result := MulDiv(FItemHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyListBox.VisibleRows: Integer;
var
  SH: Integer;
begin
  SH := ScaledItemHeight;
  // Use Height rather than ClientHeight so the result is testable headlessly
  // (in headless LCL without a native handle, ClientHeight can lag behind SetBounds).
  // For this borderless control Height = ClientHeight at runtime.
  Result := Height div SH;
  if Result < 1 then Result := 1;
end;

procedure TTyListBox.EnsureSelectionVisible;
var
  VR: Integer;
begin
  if FItemIndex < 0 then Exit;
  VR := VisibleRows;
  if FItemIndex < FTopIndex then
    FTopIndex := FItemIndex
  else if FItemIndex >= FTopIndex + VR then
    FTopIndex := FItemIndex - VR + 1;
  // Clamp TopIndex to valid range
  if FTopIndex < 0 then FTopIndex := 0;
  if FTopIndex > MaxTopIndex then FTopIndex := MaxTopIndex;
end;

procedure TTyListBox.SelectItem(AIndex: Integer);
var
  NewIndex: Integer;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
    NewIndex := AIndex
  else
    NewIndex := -1;
  if NewIndex = FItemIndex then Exit;
  FItemIndex := NewIndex;
  EnsureSelectionVisible;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyListBox.KeyDown(var Key: Word; Shift: TShiftState);
var
  Count, NewIndex: Integer;
begin
  inherited KeyDown(Key, Shift);
  Count := FItems.Count;
  if Count = 0 then Exit;

  case Key of
    VK_UP:
    begin
      if FItemIndex <= 0 then
        NewIndex := 0
      else
        NewIndex := FItemIndex - 1;
      SelectItem(NewIndex);
      Key := 0;
    end;
    VK_DOWN:
    begin
      if FItemIndex < 0 then
        NewIndex := 0
      else if FItemIndex < Count - 1 then
        NewIndex := FItemIndex + 1
      else
        NewIndex := Count - 1;
      SelectItem(NewIndex);
      Key := 0;
    end;
    VK_HOME:
    begin
      SelectItem(0);
      Key := 0;
    end;
    VK_END:
    begin
      SelectItem(Count - 1);
      Key := 0;
    end;
  end;
end;

procedure TTyListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
  SH: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    SH := ScaledItemHeight;
    Row := FTopIndex + (Y div SH);
    if (Row >= 0) and (Row < FItems.Count) then
      SelectItem(Row);
    try
      if CanFocus then
        SetFocus;
    except
      // Ignore focus errors in headless/test environments
    end;
  end;
end;

function TTyListBox.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Delta: Integer;
begin
  // WheelDelta > 0 = scroll up (TopIndex decreases)
  // WheelDelta < 0 = scroll down (TopIndex increases)
  if WheelDelta > 0 then
    Delta := -3
  else
    Delta := 3;
  SetTopIndex(FTopIndex + Delta);
  Result := True;
end;

procedure TTyListBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
begin
  P := TTyPainter.Create;
  try
    R := ARect;
    P.BeginPaint(ACanvas, R, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyListBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyListBox.SimulateKeyDown(AKey: Word);
begin
  KeyDown(AKey, []);
end;

end.
