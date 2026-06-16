unit tyControls.TyLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyLabel = class(TTyGraphicControl)
  private
    FAlignment: TAlignment;
    FLayout: TTextLayout;
    FWordWrap: Boolean;
    FTransparent: Boolean;
    FFocusControl: TWinControl;
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLayout(AValue: TTextLayout);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetTransparent(AValue: Boolean);
    procedure SetFocusControl(AValue: TWinControl);
    { Resolve the effective font size (theme, then control Font, then a default).
      TTyGraphicControl has no ResolveFontSize helper, so it lives here. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { Greedy word-wrap of AText so each line fits AMaxWidth pixels, measured with
      the given (already PPI-scaled) canvas font. Returns the lines. }
    procedure WrapText(const AText: string; AMaxWidthPx: Integer;
      ACanvas: TCanvas; ALines: TStrings);
    { Measure the caption: width = widest line, height = line-count * line-height.
      Honors WordWrap at AAvailWidthPx (only used when WordWrap=True; <=0 = no wrap). }
    procedure MeasureCaption(APPI, AAvailWidthPx: Integer; out AWidthPx, AHeightPx: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property Layout: TTextLayout read FLayout write SetLayout default tlCenter;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    property AutoSize;
    property Transparent: Boolean read FTransparent write SetTransparent default True;
    property FocusControl: TWinControl read FFocusControl write SetFocusControl;
  end;

implementation

constructor TTyLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlignment := taLeftJustify;
  FLayout := tlCenter;
  FWordWrap := False;
  FTransparent := True;
end;

function TTyLabel.GetStyleTypeKey: string;
begin
  Result := 'TyLabel';
end;

function TTyLabel.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  if AStyle.FontSize > 0 then
    Result := AStyle.FontSize
  else if Font.Size > 0 then
    Result := Font.Size
  else
    Result := 9;
end;

procedure TTyLabel.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyLabel.SetLayout(AValue: TTextLayout);
begin
  if FLayout = AValue then Exit;
  FLayout := AValue;
  Invalidate;
end;

procedure TTyLabel.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  if AutoSize then
    InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TTyLabel.SetTransparent(AValue: Boolean);
begin
  if FTransparent = AValue then Exit;
  FTransparent := AValue;
  Invalidate;
end;

procedure TTyLabel.SetFocusControl(AValue: TWinControl);
begin
  if FFocusControl = AValue then Exit;
  if FFocusControl <> nil then
    FFocusControl.RemoveFreeNotification(Self);
  FFocusControl := AValue;
  if FFocusControl <> nil then
    FFocusControl.FreeNotification(Self);
end;

procedure TTyLabel.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FFocusControl) then
    FFocusControl := nil;
end;

procedure TTyLabel.Click;
begin
  inherited Click;
  if (FFocusControl <> nil) and FFocusControl.CanFocus then
    FFocusControl.SetFocus;
end;

procedure TTyLabel.WrapText(const AText: string; AMaxWidthPx: Integer;
  ACanvas: TCanvas; ALines: TStrings);
var
  i: Integer;
  word, cur, trial: string;
  function NextWord(var p: Integer): string;
  var startP: Integer;
  begin
    Result := '';
    // skip leading spaces (collapse runs of whitespace to a single break point)
    while (p <= Length(AText)) and (AText[p] = ' ') do Inc(p);
    startP := p;
    while (p <= Length(AText)) and (AText[p] <> ' ') do Inc(p);
    Result := Copy(AText, startP, p - startP);
  end;
begin
  ALines.Clear;
  if AText = '' then
  begin
    ALines.Add('');
    Exit;
  end;
  cur := '';
  i := 1;
  while i <= Length(AText) do
  begin
    word := NextWord(i);
    if word = '' then Break;
    if cur = '' then
      trial := word
    else
      trial := cur + ' ' + word;
    if (AMaxWidthPx > 0) and (cur <> '') and (ACanvas.TextWidth(trial) > AMaxWidthPx) then
    begin
      ALines.Add(cur);
      cur := word;
    end
    else
      cur := trial;
  end;
  if cur <> '' then
    ALines.Add(cur);
  if ALines.Count = 0 then
    ALines.Add(AText);
end;

procedure TTyLabel.MeasureCaption(APPI, AAvailWidthPx: Integer;
  out AWidthPx, AHeightPx: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
  Lines: TStringList;
  i, w, lineH: Integer;
begin
  S := CurrentStyle;
  AWidthPx := 0;
  AHeightPx := 0;
  Meas := TBitmap.Create;
  Lines := TStringList.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    if S.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    lineH := Meas.Canvas.TextHeight('Ag');
    if lineH < 1 then lineH := 1;

    if FWordWrap and (AAvailWidthPx > 0) then
      WrapText(Caption, AAvailWidthPx, Meas.Canvas, Lines)
    else
      Lines.Text := Caption; // splits on existing line breaks; usually one line

    if Lines.Count = 0 then
      Lines.Add(Caption);

    for i := 0 to Lines.Count - 1 do
    begin
      w := Meas.Canvas.TextWidth(Lines[i]);
      if w > AWidthPx then AWidthPx := w;
    end;
    AHeightPx := Lines.Count * lineH;
  finally
    Lines.Free;
    Meas.Free;
  end;
end;

procedure TTyLabel.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, availW, padW, padH, tw, th: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  padW := MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  padH := MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);

  // For WordWrap, wrap at the current content width; non-wrap measures the whole line.
  if FWordWrap then
  begin
    availW := Width - padW;
    if availW < 1 then availW := 1;
  end
  else
    availW := 0;

  MeasureCaption(ppi, availW, tw, th);
  PreferredWidth := tw + padW;
  PreferredHeight := th + padH;
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

procedure TTyLabel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect, LineRect: TRect;
  Meas: TBitmap;
  Lines: TStringList;
  lineH, i, availW, fontSize: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    fontSize := ResolveFontSize(S);
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // When opaque, paint the style background (DrawFrame fill). When transparent
    // (default), skip the fill so no background paints regardless of theme — but
    // still honor the style opacity (e.g. :disabled { opacity: 0.5 }) so the
    // default transparent label dims exactly as before.
    if not FTransparent then
      DrawFrame(P, ContentRect, S)
    else if tpOpacity in S.Present then
      P.Opacity := S.Opacity;
    // Inset content by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );

    if FWordWrap then
    begin
      Meas := TBitmap.Create;
      Lines := TStringList.Create;
      try
        Meas.SetSize(1, 1);
        Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
        Meas.Canvas.Font.Size := MulDiv(fontSize, APPI, 96);
        if S.FontWeight >= 600 then
          Meas.Canvas.Font.Style := [fsBold]
        else
          Meas.Canvas.Font.Style := [];
        lineH := Meas.Canvas.TextHeight('Ag');
        if lineH < 1 then lineH := 1;
        availW := ContentRect.Right - ContentRect.Left;
        WrapText(Caption, availW, Meas.Canvas, Lines);
        for i := 0 to Lines.Count - 1 do
        begin
          LineRect := Rect(ContentRect.Left, ContentRect.Top + i * lineH,
            ContentRect.Right, ContentRect.Top + (i + 1) * lineH);
          if LineRect.Top >= ContentRect.Bottom then Break;
          P.DrawText(LineRect, Lines[i], S.FontName, fontSize, S.FontWeight,
            S.TextColor, FAlignment, tlCenter, False);
        end;
      finally
        Lines.Free;
        Meas.Free;
      end;
    end
    else
      P.DrawText(ContentRect, Caption, S.FontName, fontSize, S.FontWeight,
        S.TextColor, FAlignment, FLayout, False);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyLabel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
