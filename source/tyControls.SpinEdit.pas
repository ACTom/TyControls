unit tyControls.SpinEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8,
  ExtCtrls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation;
type
  TTySpinEdit = class(TTyCustomControl)
  private
    FMinValue, FMaxValue, FValue, FIncrement: Integer;
    FOnChange: TNotifyEvent;
    procedure SetMinValue(const AValue: Integer);
    procedure SetMaxValue(const AValue: Integer);
    procedure SetValue(const AValue: Integer);
    procedure SetIncrement(const AValue: Integer);
  protected
    // Inline edit buffer (lightweight, no selection/clipboard). Protected so
    // headless access subclasses (tests) can reach the buffer + helpers.
    FEditText: string;
    FCaret: Integer;      // codepoint index 0..UTF8Length(FEditText)
    FMeasureBmp: TBGRABitmap;  // lazy; used only for text measurement
    // Blinking caret (Task 10). FCaretVisible defaults True; the timer is created
    // lazily and started ONLY when HandleAllocated, so headless tests never blink
    // and the static-caret pixel tests stay deterministic.
    FCaretVisible: Boolean;
    FBlinkTimer: TTimer;
    FBlinkElapsedMs: Integer;
    procedure EnsureBlinkTimer;
    procedure HandleBlink(Sender: TObject);
    procedure ResetCaretBlink;
    procedure DoEnter; override;
    // Edit-buffer helpers
    procedure SyncBufferToValue;
    procedure CommitEdit;
    procedure InsertEditChar(const C: TUTF8Char);
    procedure EditBackspace;
    procedure EditDelete;
    function CaretPixelX(AIdx, APPI: Integer): Integer;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoExit; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property MinValue: Integer read FMinValue write SetMinValue default 0;
    property MaxValue: Integer read FMaxValue write SetMaxValue default 100;
    property Value: Integer read FValue write SetValue default 0;
    property Increment: Integer read FIncrement write SetIncrement default 1;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;

implementation

function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
var
  BtnW, X0, HalfY: Integer;
begin
  BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, ALocal.Top, ALocal.Right, HalfY);
end;

function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;
var
  BtnW, X0, HalfY: Integer;
begin
  BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, HalfY, ALocal.Right, ALocal.Bottom);
end;

{ TTySpinEdit }

constructor TTySpinEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMinValue := 0;
  FMaxValue := 100;
  FValue := 0;
  FIncrement := 1;
  Width := 120;
  Height := 28;
  FCaretVisible := True;       // solid caret until a real timer toggles it
  FBlinkTimer := nil;          // lazy: created only when HandleAllocated
  FBlinkElapsedMs := 0;
  SyncBufferToValue;
end;

destructor TTySpinEdit.Destroy;
begin
  // Free the timer first so its OnTimer callback can never fire mid-teardown.
  FreeAndNil(FBlinkTimer);
  FMeasureBmp.Free;
  inherited Destroy;
end;

// ---- Blinking caret (Task 10) ----

procedure TTySpinEdit.EnsureBlinkTimer;
begin
  if FBlinkTimer = nil then
  begin
    FBlinkTimer := TTimer.Create(Self);
    FBlinkTimer.Enabled := False;
    FBlinkTimer.Interval := 530;
    FBlinkTimer.OnTimer := @HandleBlink;
  end;
end;

procedure TTySpinEdit.HandleBlink(Sender: TObject);
begin
  Inc(FBlinkElapsedMs, FBlinkTimer.Interval);
  FCaretVisible := TyCaretVisible(FBlinkElapsedMs, FBlinkTimer.Interval);
  Invalidate;
end;

procedure TTySpinEdit.ResetCaretBlink;
begin
  FCaretVisible := True;
  FBlinkElapsedMs := 0;
end;

procedure TTySpinEdit.DoEnter;
begin
  inherited DoEnter;
  ResetCaretBlink;
  if HandleAllocated then
  begin
    EnsureBlinkTimer;
    FBlinkTimer.Enabled := True;
  end;
end;

function TTySpinEdit.GetStyleTypeKey: string;
begin
  Result := 'TySpinEdit';
end;

procedure TTySpinEdit.SetValue(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMinValue then Clamped := FMinValue;
  if Clamped > FMaxValue then Clamped := FMaxValue;
  if FValue <> Clamped then
  begin
    FValue := Clamped;
    if Assigned(FOnChange) then FOnChange(Self);
  end;
  SyncBufferToValue;          // always keep buffer in step with Value
  Invalidate;
end;

procedure TTySpinEdit.SetMinValue(const AValue: Integer);
begin
  if FMinValue = AValue then Exit;
  FMinValue := AValue;
  if FValue < FMinValue then FValue := FMinValue;
  SyncBufferToValue;
  Invalidate;
end;

procedure TTySpinEdit.SetMaxValue(const AValue: Integer);
begin
  if FMaxValue = AValue then Exit;
  FMaxValue := AValue;
  if FValue > FMaxValue then FValue := FMaxValue;
  SyncBufferToValue;
  Invalidate;
end;

procedure TTySpinEdit.SetIncrement(const AValue: Integer);
begin
  if FIncrement = AValue then Exit;
  if AValue < 1 then
    FIncrement := 1
  else
    FIncrement := AValue;
  Invalidate;
end;

procedure TTySpinEdit.SyncBufferToValue;
begin
  FEditText := IntToStr(FValue);
  FCaret := UTF8Length(FEditText);
  ResetCaretBlink;
end;

function TTySpinEdit.CaretPixelX(AIdx, APPI: Integer): Integer;
var
  S: TTyStyleSet;
  EffSize: Integer;
begin
  S := CurrentStyle;
  EffSize := ResolveFontSize(S);   // theme font-size > Font.Size > 9; shared with RenderTo so caret stays aligned
  Result := MulDiv(S.Padding.Left, APPI, 96);   // local-left text start
  if (FEditText = '') or (AIdx <= 0) then Exit;
  if AIdx > UTF8Length(FEditText) then AIdx := UTF8Length(FEditText);
  if FMeasureBmp = nil then FMeasureBmp := TBGRABitmap.Create(1, 1);
  TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
  Result := Result + FMeasureBmp.TextSize(UTF8Copy(FEditText, 1, AIdx)).cx;
end;

procedure TTySpinEdit.CommitEdit;
var
  v: Integer;
begin
  v := StrToIntDef(Trim(FEditText), FValue);
  Value := v;                 // setter clamps to [Min,Max] + fires OnChange if changed
  SyncBufferToValue;          // resync to the (possibly clamped) value
  Invalidate;
end;

procedure TTySpinEdit.InsertEditChar(const C: TUTF8Char);
var
  Before, After: string;
  L: Integer;
begin
  // Accept digits 0..9 always; accept '-' only at position 0 and when no '-' yet.
  if C = '' then Exit;
  if not ( ((Length(C)=1) and (C[1] in ['0'..'9']))
           or ((C = '-') and (FCaret = 0) and (Pos('-', FEditText) = 0)) ) then Exit;
  L := UTF8Length(FEditText);
  if FCaret > L then FCaret := L;
  Before := UTF8Copy(FEditText, 1, FCaret);
  After  := UTF8Copy(FEditText, FCaret + 1, L - FCaret);
  FEditText := Before + C + After;
  Inc(FCaret);
  ResetCaretBlink;
end;

procedure TTySpinEdit.EditBackspace;
var
  Before, After: string;
  L: Integer;
begin
  if FCaret = 0 then Exit;
  L := UTF8Length(FEditText);
  Before := UTF8Copy(FEditText, 1, FCaret - 1);
  After  := UTF8Copy(FEditText, FCaret + 1, L - FCaret);
  FEditText := Before + After;
  Dec(FCaret);
  ResetCaretBlink;
end;

procedure TTySpinEdit.EditDelete;
var
  Before, After: string;
  L: Integer;
begin
  L := UTF8Length(FEditText);
  if FCaret >= L then Exit;
  Before := UTF8Copy(FEditText, 1, FCaret);
  After  := UTF8Copy(FEditText, FCaret + 2, L - FCaret - 1);
  FEditText := Before + After;
  ResetCaretBlink;
end;

procedure TTySpinEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextR, UpR, DownR, CaretRect: TRect;
  BtnW, EffSize, cx: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    UpR := TySpinUpButtonRect(R, APPI);
    DownR := TySpinDownButtonRect(R, APPI);
    BtnW := P.Scale(TyFieldButtonWidth);
    TextR := Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW, R.Bottom - P.Scale(S.Padding.Bottom));
    EffSize := ResolveFontSize(S);   // same size feeds DrawText and CaretPixelX (caret alignment)
    P.DrawText(TextR, FEditText, S.FontName, EffSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, True);
    P.DrawGlyph(UpR, tgArrowUp, S.TextColor, 2);
    P.DrawGlyph(DownR, tgArrowDown, S.TextColor, 2);
    if Focused and FCaretVisible then
    begin
      cx := CaretPixelX(FCaret, APPI);
      CaretRect := Rect(cx, TextR.Top + P.Scale(2), cx + P.Scale(1), TextR.Bottom - P.Scale(2));
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTySpinEdit.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTySpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if not Enabled then Exit;
  inherited UTF8KeyPress(UTF8Key);
  InsertEditChar(UTF8Key);
  Invalidate;
end;

procedure TTySpinEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  case Key of
    VK_UP:
      begin
        Value := FValue + FIncrement;
        Key := 0;
      end;
    VK_DOWN:
      begin
        Value := FValue - FIncrement;
        Key := 0;
      end;
    VK_RETURN: begin CommitEdit; Key := 0; end;
    VK_ESCAPE: begin SyncBufferToValue; Invalidate; Key := 0; end;
    VK_BACK:   begin EditBackspace; Invalidate; Key := 0; end;
    VK_DELETE: begin EditDelete; Invalidate; Key := 0; end;
    VK_LEFT:   begin if FCaret > 0 then Dec(FCaret); ResetCaretBlink; Invalidate; Key := 0; end;
    VK_RIGHT:  begin if FCaret < UTF8Length(FEditText) then Inc(FCaret); ResetCaretBlink; Invalidate; Key := 0; end;
    VK_HOME:   begin FCaret := 0; ResetCaretBlink; Invalidate; Key := 0; end;
    VK_END:    begin FCaret := UTF8Length(FEditText); ResetCaretBlink; Invalidate; Key := 0; end;
  end;
end;

procedure TTySpinEdit.DoExit;
begin
  inherited DoExit;
  CommitEdit;
  if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  FCaretVisible := True;
  Invalidate;
end;

function TTySpinEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if not Enabled then Exit(False);
  // Let the user's OnMouseWheel handler run first; if it consumes the event, stop.
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then
  begin
    Result := True;
    Exit;
  end;
  if WheelDelta > 0 then
    Value := FValue + FIncrement
  else
    Value := FValue - FIncrement;
  Result := True;
end;

procedure TTySpinEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if PtInRect(TySpinUpButtonRect(ClientRect, Font.PixelsPerInch), Point(X, Y)) then
      Value := FValue + FIncrement
    else if PtInRect(TySpinDownButtonRect(ClientRect, Font.PixelsPerInch), Point(X, Y)) then
      Value := FValue - FIncrement;
    try
      if CanFocus then SetFocus;
    except
    end;
  end;
end;

end.
