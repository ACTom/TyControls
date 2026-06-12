unit tyControls.Edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8, Clipbrd,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyIntArray = array of Integer;

  TTyEdit = class(TTyCustomControl)
  private
    FText: string;
    FCaret: Integer;      // codepoint index 0..UTF8Length(FText)
    FSelAnchor: Integer;  // codepoint index; no selection <=> FSelAnchor = FCaret
    FMouseSelecting: Boolean;  // true while left button held for drag-select
    procedure SetText(const AValue: string);
    procedure SetCaretPos(AValue: Integer);
    // Selection helpers
    procedure DeleteSelection;
    procedure SetSelAnchorAndCaret(AAnchor, ACaret: Integer);
    // Insert a raw UTF-8 string at the current caret position
    procedure InjectStringAt(const AStr: string);
    // Text measurement helper
    function TextStartX(APPI: Integer): Integer;
    function MeasureCodepointWidths(APPI: Integer): TTyIntArray;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // Clipboard virtual hooks (override in tests to avoid real clipboard)
    function ReadClipboardText: string; virtual;
    procedure WriteClipboardText(const S: string); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    procedure InjectKey(const AChar: TUTF8Char);
    procedure InjectBackspace;
    procedure InjectDelete;
    // Selection API
    function HasSelection: Boolean;
    function SelStart: Integer;
    function SelLength: Integer;
    function SelText: string;
    procedure SelectAll;
    procedure ClearSelection;
    // Mouse hit test
    function CaretIndexAtX(AX: Integer): Integer;
    // Clipboard API
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    // Rendering helpers (public for headless tests)
    function CaretPixelXAt(ACaretIndex, APPI: Integer): Integer;
    property CaretPos: Integer read FCaret write SetCaretPos;
  published
    property Text: string read FText write SetText;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;
implementation

constructor TTyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FText := '';
  FCaret := 0;
  FSelAnchor := 0;
end;

function TTyEdit.GetStyleTypeKey: string;
begin
  Result := 'TyEdit';
end;

// ---- Selection read helpers ----

function TTyEdit.HasSelection: Boolean;
begin
  Result := FCaret <> FSelAnchor;
end;

function TTyEdit.SelStart: Integer;
begin
  if FCaret < FSelAnchor then
    Result := FCaret
  else
    Result := FSelAnchor;
end;

function TTyEdit.SelLength: Integer;
begin
  Result := Abs(FCaret - FSelAnchor);
end;

function TTyEdit.SelText: string;
begin
  Result := UTF8Copy(FText, SelStart + 1, SelLength);
end;

procedure TTyEdit.SelectAll;
begin
  FSelAnchor := 0;
  FCaret := UTF8Length(FText);
  Invalidate;
end;

procedure TTyEdit.ClearSelection;
begin
  FSelAnchor := FCaret;
  Invalidate;
end;

// ---- Internal mutators ----

procedure TTyEdit.SetSelAnchorAndCaret(AAnchor, ACaret: Integer);
begin
  FSelAnchor := AAnchor;
  FCaret := ACaret;
  Invalidate;
end;

procedure TTyEdit.DeleteSelection;
var
  SS, SL: Integer;
  Before, After: string;
begin
  if not HasSelection then Exit;
  SS := SelStart;
  SL := SelLength;
  Before := UTF8Copy(FText, 1, SS);
  After  := UTF8Copy(FText, SS + SL + 1, UTF8Length(FText) - SS - SL);
  FText  := Before + After;
  FCaret := SS;
  FSelAnchor := FCaret;
  Invalidate;
end;

procedure TTyEdit.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  // Caret moves to end on SetText; collapse selection
  FCaret := UTF8Length(FText);
  FSelAnchor := FCaret;
  Invalidate;
end;

procedure TTyEdit.SetCaretPos(AValue: Integer);
var
  Len: Integer;
begin
  Len := UTF8Length(FText);
  if AValue < 0 then AValue := 0;
  if AValue > Len then AValue := Len;
  if (FCaret = AValue) and (FSelAnchor = AValue) then Exit;
  FCaret := AValue;
  FSelAnchor := AValue;  // direct CaretPos write collapses selection
  Invalidate;
end;

// ---- Text measurement helpers ----

function TTyEdit.TextStartX(APPI: Integer): Integer;
var
  S: TTyStyleSet;
begin
  S := CurrentStyle;
  // Same inset logic as RenderTo: left padding scaled at APPI
  Result := MulDiv(S.Padding.Left, APPI, 96);
end;

function TTyEdit.MeasureCodepointWidths(APPI: Integer): TTyIntArray;
// Returns an array of Length=UTF8Length(FText)+1 cumulative x positions (in px)
// relative to the text start, measured on a temp bitmap matching current font.
var
  S: TTyStyleSet;
  Bmp: TBitmap;
  FontHeight: Integer;
  i, Len: Integer;
  CP: string;
  CumW: Integer;
  W: TSize;
begin
  Len := UTF8Length(FText);
  SetLength(Result, Len + 1);
  Result[0] := 0;
  if Len = 0 then
    Exit;

  S := CurrentStyle;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(1, 1);
    Bmp.Canvas.Font.Name := S.FontName;
    // FontSize in the style is logical pt; convert to px at APPI
    if S.FontSize > 0 then
      FontHeight := MulDiv(S.FontSize, APPI, 72)
    else
      FontHeight := MulDiv(12, APPI, 72);   // fallback 12pt
    Bmp.Canvas.Font.Height := -FontHeight;
    if S.FontWeight >= 600 then
      Bmp.Canvas.Font.Style := [fsBold]
    else
      Bmp.Canvas.Font.Style := [];

    CumW := 0;
    for i := 1 to Len do
    begin
      CP := UTF8Copy(FText, i, 1);
      W := Bmp.Canvas.TextExtent(CP);
      CumW := CumW + W.cx;
      Result[i] := CumW;
    end;
  finally
    Bmp.Free;
  end;
end;

// ---- Mouse caret hit-test ----

function TTyEdit.CaretIndexAtX(AX: Integer): Integer;
var
  APPI: Integer;
  Widths: TTyIntArray;
  StartX: Integer;
  RelX: Integer;
  Len, i: Integer;
  LeftEdge, RightEdge, MidPoint: Integer;
begin
  APPI := Font.PixelsPerInch;
  StartX := TextStartX(APPI);
  RelX := AX - StartX;
  Len := UTF8Length(FText);

  if RelX <= 0 then
  begin
    Result := 0;
    Exit;
  end;

  Widths := MeasureCodepointWidths(APPI);

  if RelX >= Widths[Len] then
  begin
    Result := Len;
    Exit;
  end;

  // Walk codepoints: find the boundary nearest to RelX
  // Widths[i] = cumulative width after i codepoints
  // Boundary i lies at Widths[i]; pick the nearest
  Result := 0;
  for i := 0 to Len do
  begin
    if i = 0 then
      LeftEdge := 0
    else
      LeftEdge := Widths[i - 1];

    if i = Len then
    begin
      // Past last codepoint
      if RelX >= LeftEdge then
        Result := Len;
      Break;
    end;

    RightEdge := Widths[i + 1];  // end of codepoint i+1
    // We're between boundary i (at Widths[i]) and boundary i+1 (at Widths[i+1])
    // But boundaries are: 0, Widths[1], Widths[2], ..., Widths[Len]
    // Boundary at index i is at Widths[i]
    // So boundary i and i+1 are at Widths[i] and Widths[i+1]
    // The midpoint determines which boundary is nearest
    if i < Len then
    begin
      MidPoint := (Widths[i] + Widths[i + 1]) div 2;
      if RelX <= MidPoint then
      begin
        Result := i;
        Break;
      end
      else
        Result := i + 1;
    end;
  end;
end;

// ---- Caret pixel position helper ----

function TTyEdit.CaretPixelXAt(ACaretIndex, APPI: Integer): Integer;
var
  Widths: TTyIntArray;
  Len: Integer;
begin
  Len := UTF8Length(FText);
  if ACaretIndex < 0 then ACaretIndex := 0;
  if ACaretIndex > Len then ACaretIndex := Len;
  Result := TextStartX(APPI);
  if Len = 0 then
    Exit;
  Widths := MeasureCodepointWidths(APPI);
  Result := Result + Widths[ACaretIndex];
end;

// ---- Clipboard implementation ----

function TTyEdit.ReadClipboardText: string;
begin
  Result := Clipboard.AsText;
end;

procedure TTyEdit.WriteClipboardText(const S: string);
begin
  Clipboard.AsText := S;
end;

procedure TTyEdit.CopyToClipboard;
begin
  if not HasSelection then Exit;
  WriteClipboardText(SelText);
end;

procedure TTyEdit.CutToClipboard;
begin
  if not HasSelection then Exit;
  WriteClipboardText(SelText);
  DeleteSelection;
end;

procedure TTyEdit.PasteFromClipboard;
var
  S: string;
  i: Integer;
  Filtered: string;
begin
  S := ReadClipboardText;
  // Strip CR and LF characters (single-line control)
  Filtered := '';
  for i := 1 to Length(S) do
    if (S[i] <> #13) and (S[i] <> #10) then
      Filtered := Filtered + S[i];
  if Filtered = '' then Exit;
  // Replace selection if any, then insert at caret
  if HasSelection then
    DeleteSelection;
  // Insert each codepoint
  InjectStringAt(Filtered);
end;

procedure TTyEdit.InjectStringAt(const AStr: string);
var
  Before, After: string;
  InsLen: Integer;
begin
  if AStr = '' then Exit;
  Before := UTF8Copy(FText, 1, FCaret);
  After  := UTF8Copy(FText, FCaret + 1, UTF8Length(FText) - FCaret);
  FText  := Before + AStr + After;
  InsLen := UTF8Length(AStr);
  FCaret := FCaret + InsLen;
  FSelAnchor := FCaret;
  Invalidate;
end;

// ---- Mouse overrides ----

procedure TTyEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if ssDouble in Shift then
    begin
      // Double-click: select all
      SelectAll;
      FMouseSelecting := False;
    end
    else
    begin
      // Single click: position caret, collapse selection
      FCaret := CaretIndexAtX(X);
      FSelAnchor := FCaret;
      FMouseSelecting := True;
      Invalidate;
    end;
    try
      if CanFocus then
        SetFocus;
    except
      // Ignore focus errors in headless/test environments
    end;
  end;
end;

procedure TTyEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FMouseSelecting then
  begin
    // Drag-select: move caret, keep anchor fixed
    FCaret := CaretIndexAtX(X);
    Invalidate;
  end;
end;

procedure TTyEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
    FMouseSelecting := False;
end;

procedure TTyEdit.InjectKey(const AChar: TUTF8Char);
var
  Before, After: string;
begin
  if (AChar = '') or (AChar[1] < #32) then Exit;
  // Replace selection if any
  if HasSelection then
    DeleteSelection;
  Before := UTF8Copy(FText, 1, FCaret);
  After  := UTF8Copy(FText, FCaret + 1, UTF8Length(FText) - FCaret);
  FText  := Before + AChar + After;
  Inc(FCaret);
  FSelAnchor := FCaret;
  Invalidate;
end;

procedure TTyEdit.InjectBackspace;
var
  Len: Integer;
  Before, After: string;
begin
  if HasSelection then
  begin
    DeleteSelection;
    Exit;
  end;
  if FCaret = 0 then Exit;
  Len    := UTF8Length(FText);
  Before := UTF8Copy(FText, 1, FCaret - 1);
  After  := UTF8Copy(FText, FCaret + 1, Len - FCaret);
  FText  := Before + After;
  Dec(FCaret);
  FSelAnchor := FCaret;
  Invalidate;
end;

procedure TTyEdit.InjectDelete;
var
  Len: Integer;
  Before, After: string;
begin
  if HasSelection then
  begin
    DeleteSelection;
    Exit;
  end;
  Len := UTF8Length(FText);
  if FCaret >= Len then Exit;  // no-op at end
  Before := UTF8Copy(FText, 1, FCaret);
  After  := UTF8Copy(FText, FCaret + 2, Len - FCaret - 1);
  FText  := Before + After;
  // caret stays; collapse anchor
  FSelAnchor := FCaret;
  Invalidate;
end;

procedure TTyEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  InjectKey(UTF8Key);
end;

procedure TTyEdit.KeyDown(var Key: Word; Shift: TShiftState);
var
  Len: Integer;
  Extending: Boolean;
begin
  inherited KeyDown(Key, Shift);
  Len := UTF8Length(FText);

  // Ctrl+A / Meta+A
  if (Key = VK_A) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    SelectAll;
    Key := 0;
    Exit;
  end;

  // Ctrl+C / Meta+C
  if (Key = VK_C) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    CopyToClipboard;
    Key := 0;
    Exit;
  end;

  // Ctrl+X / Meta+X
  if (Key = VK_X) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    CutToClipboard;
    Key := 0;
    Exit;
  end;

  // Ctrl+V / Meta+V
  if (Key = VK_V) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    PasteFromClipboard;
    Key := 0;
    Exit;
  end;

  Extending := ssShift in Shift;

  case Key of
    VK_BACK:
    begin
      InjectBackspace;
      Key := 0;
    end;
    VK_DELETE:
    begin
      InjectDelete;
      Key := 0;
    end;
    VK_LEFT:
    begin
      if Extending then
      begin
        // Shift held: move caret left (anchor stays)
        if FCaret > 0 then
        begin
          Dec(FCaret);
          Invalidate;
        end;
      end
      else
      begin
        // No shift: if selection exists collapse to left edge, else move
        if HasSelection then
        begin
          FCaret := SelStart;
          FSelAnchor := FCaret;
          Invalidate;
        end
        else if FCaret > 0 then
        begin
          Dec(FCaret);
          FSelAnchor := FCaret;
          Invalidate;
        end;
      end;
      Key := 0;
    end;
    VK_RIGHT:
    begin
      if Extending then
      begin
        // Shift held: move caret right (anchor stays)
        if FCaret < Len then
        begin
          Inc(FCaret);
          Invalidate;
        end;
      end
      else
      begin
        // No shift: if selection exists collapse to right edge, else move
        if HasSelection then
        begin
          FCaret := SelStart + SelLength;
          FSelAnchor := FCaret;
          Invalidate;
        end
        else if FCaret < Len then
        begin
          Inc(FCaret);
          FSelAnchor := FCaret;
          Invalidate;
        end;
      end;
      Key := 0;
    end;
    VK_HOME:
    begin
      if Extending then
      begin
        FCaret := 0;
        Invalidate;
      end
      else
      begin
        FCaret := 0;
        FSelAnchor := 0;
        Invalidate;
      end;
      Key := 0;
    end;
    VK_END:
    begin
      if Extending then
      begin
        FCaret := Len;
        Invalidate;
      end
      else
      begin
        FCaret := Len;
        FSelAnchor := Len;
        Invalidate;
      end;
      Key := 0;
    end;
  end;
end;

procedure TTyEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FS: TTyStyleSet;
  ContentRect, BandRect, CaretRect: TRect;
  Widths: TTyIntArray;
  X1, X2, CaretX: Integer;
  BandFill: TTyFill;
  BandColor: TTyColor;
  BandAlpha: Byte;
  FocusBorderColor: TTyColor;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    // Inset content by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );

    // 1. Selection band (drawn before text so glyphs appear on top)
    if HasSelection then
    begin
      // Resolve focused style for border-color (used as band color)
      FS := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysFocused]);
      if tpBorderColor in FS.Present then
        FocusBorderColor := FS.BorderColor
      else
        FocusBorderColor := S.TextColor;

      Widths := MeasureCodepointWidths(APPI);
      X1 := ContentRect.Left + Widths[SelStart];
      X2 := ContentRect.Left + Widths[SelStart + SelLength];
      // Clamp to content rect
      if X1 < ContentRect.Left then X1 := ContentRect.Left;
      if X2 > ContentRect.Right then X2 := ContentRect.Right;
      if X1 < X2 then
      begin
        BandRect := Rect(X1, ContentRect.Top, X2, ContentRect.Bottom);
        // ~35% alpha: $59 ≈ 255 * 0.35
        BandAlpha := $59;
        BandColor := TyRGBA(TyRedOf(FocusBorderColor), TyGreenOf(FocusBorderColor),
          TyBlueOf(FocusBorderColor), BandAlpha);
        BandFill := Default(TTyFill);
        BandFill.Kind := tfkSolid;
        BandFill.Color := BandColor;
        P.FillBackground(BandRect, BandFill, 0);
      end;
    end;

    // 2. Draw text (on top of selection band)
    P.DrawText(ContentRect, FText, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, True);

    // 3. Caret (only when focused and no selection)
    if Focused and not HasSelection then
    begin
      if Length(Widths) = 0 then
        Widths := MeasureCodepointWidths(APPI);
      CaretX := ContentRect.Left + Widths[FCaret];
      CaretRect := Rect(CaretX, ContentRect.Top + P.Scale(2),
        CaretX + P.Scale(1), ContentRect.Bottom - P.Scale(2));
      P.FillBackground(CaretRect, Default(TTyFill), 0);
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyEdit.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
