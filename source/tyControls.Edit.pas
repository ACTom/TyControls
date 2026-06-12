unit tyControls.Edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyEdit = class(TTyCustomControl)
  private
    FText: string;
    FCaret: Integer;      // codepoint index 0..UTF8Length(FText)
    FSelAnchor: Integer;  // codepoint index; no selection <=> FSelAnchor = FCaret
    procedure SetText(const AValue: string);
    procedure SetCaretPos(AValue: Integer);
    // Selection helpers
    procedure DeleteSelection;
    procedure SetSelAnchorAndCaret(AAnchor, ACaret: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
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
  S: TTyStyleSet;
  ContentRect, CaretRect: TRect;
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
    P.DrawText(ContentRect, FText, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, True);
    if Focused then
    begin
      CaretRect := Rect(ContentRect.Left, ContentRect.Top + P.Scale(4),
        ContentRect.Left + P.Scale(1), ContentRect.Bottom - P.Scale(4));
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
