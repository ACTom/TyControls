unit tyControls.HtmlLabel;
{$mode objfpc}{$H+}
{ TTyHtmlLabel -- a mini rich-text label rendering an INLINE HTML SUBSET (NOT a
  browser). Supported: plain text + <b> <i> <u> <s>, <font color=#rrggbb size=N>,
  <a href="...">, <br>, and the entities &lt; &gt; &amp; &quot; &nbsp;. Tags are
  case-insensitive; malformed / unknown tags are tolerated (skipped), never raise.
  Not supported (v1): tables, images, CSS, lists, block/box layout (<div>/<p>).

  Windowed (TTyCustomControl) because links need mouse hit-testing. GetStyleTypeKey
  = 'TyLabel' so it reuses the themed label text style with ZERO new tokens; link
  runs are painted in the theme accent colour.

  The pure markup->runs logic lives in the interface function TyHtmlParse so it is
  headless-testable; wrapping/painting/mouse are real-machine (they need BGRA text
  measurement and a live window). }
interface
uses
  Classes, SysUtils, StrUtils, Types, Math, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

type
  { One styled fragment of parsed rich text. A run with LineBreak=True carries no
    text and forces the next content onto a new line (from <br>). Color is an LCL
    TColor and only meaningful when HasColor=True; SizePt=0 means "use the themed
    default size"; Href='' means the run is not a link. }
  TTyHtmlRun = record
    Text: string;
    Bold, Italic, Underline, Strike, LineBreak: Boolean;
    Color: TColor;
    HasColor: Boolean;
    SizePt: Integer;   // 0 = default
    Href: string;      // '' = not a link
  end;
  TTyHtmlRunArray = array of TTyHtmlRun;

  { A laid-out fragment: a run plus the client-space rectangle it occupies. }
  TTyHtmlFrag = record
    Run: TTyHtmlRun;
    Rect: TRect;
  end;
  TTyHtmlFragArray = array of TTyHtmlFrag;

  TTyHtmlLinkEvent = procedure(Sender: TObject; const AHref: string) of object;

  TTyHtmlLabel = class(TTyCustomControl)
  private
    FHtml: string;
    FRuns: TTyHtmlRunArray;
    FLayout: TTyHtmlFragArray;
    FWordWrap: Boolean;
    FOnLinkClick: TTyHtmlLinkEvent;
    procedure SetHtml(const AValue: string);
    procedure SetWordWrap(AValue: Boolean);
    { Wrap FRuns into positioned fragments within [AContentLeft .. AContentLeft+AContentWidth],
      filling FLayout; returns the used extents (device px). AContentWidth is only honored
      when WordWrap is on. }
    procedure BuildLayout(AContentLeft, AContentTop, AContentWidth, APPI: Integer;
      out AExtW, AExtH: Integer);
    { Rebuild FLayout from the current client width if it is empty (e.g. a mouse event
      arrives before the first paint). }
    procedure EnsureLayout;
    { The href of the link fragment under the client point, or '' if none. }
    function LinkAt(X, Y: Integer): string;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure DoSetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Html: string read FHtml write SetHtml;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default True;
    property OnLinkClick: TTyHtmlLinkEvent read FOnLinkClick write FOnLinkClick;
    property AutoSize;
    property Align;
    property Anchors;
    property Visible;
  end;

{ Parse an inline-HTML-subset string into a flat sequence of styled runs. A style
  STACK is pushed by opening tags (<b>/<i>/<u>/<s>/<font>/<a>) and popped by their
  matching close tags; <br> emits a LineBreak run; entities are decoded; malformed
  or unknown tags are skipped. Never raises. }
function TyHtmlParse(const AHtml: string): TTyHtmlRunArray;

implementation

{ ---- pure helpers ---- }

function LclColorToTy(c: TColor): TTyColor;
var r, g, b: Byte;
begin
  RedGreenBlue(ColorToRGB(c), r, g, b);
  Result := TyRGB(r, g, b);
end;

{ Decode a bare entity name (no '&' / ';', already lower-cased). Returns '' when
  the name is unknown, so the caller keeps the literal '&'. &nbsp; decodes to a
  UTF-8 no-break space (so it never becomes a wrap point). }
function DecodeEntity(const AName: string): string;
begin
  if AName = 'lt' then Result := '<'
  else if AName = 'gt' then Result := '>'
  else if AName = 'amp' then Result := '&'
  else if AName = 'quot' then Result := '"'
  else if AName = 'nbsp' then Result := #$C2#$A0
  else Result := '';
end;

{ Extract the value of attribute AName from a tag body (e.g. 'font color=#ff0000 size=14').
  Case-insensitive name match; the value may be double/single quoted or bare. '' if absent.
  The returned value preserves the original case (href / hex need it). }
function GetTagAttr(const ATag, AName: string): string;
var
  low, ln: string;
  p, q, e: Integer;
  quote: Char;
begin
  Result := '';
  low := LowerCase(ATag);
  ln := LowerCase(AName);
  if ln = '' then Exit;
  p := Pos(ln, low);
  while p > 0 do
  begin
    q := p + Length(ln);
    // The name must be a standalone token: preceded by whitespace/start.
    if (p = 1) or (low[p - 1] = ' ') or (low[p - 1] = #9) then
    begin
      while (q <= Length(low)) and ((low[q] = ' ') or (low[q] = #9)) do Inc(q);
      if (q <= Length(low)) and (low[q] = '=') then
      begin
        Inc(q);
        while (q <= Length(ATag)) and ((ATag[q] = ' ') or (ATag[q] = #9)) do Inc(q);
        if q > Length(ATag) then Exit;
        if (ATag[q] = '"') or (ATag[q] = '''') then
        begin
          quote := ATag[q];
          Inc(q);
          e := q;
          while (e <= Length(ATag)) and (ATag[e] <> quote) do Inc(e);
          Result := Copy(ATag, q, e - q);
        end
        else
        begin
          e := q;
          while (e <= Length(ATag)) and (ATag[e] <> ' ') and (ATag[e] <> #9) do Inc(e);
          Result := Copy(ATag, q, e - q);
        end;
        Exit;
      end;
    end;
    p := PosEx(ln, low, p + 1);
  end;
end;

{ Parse a 6-hex-digit '#rrggbb' body (the 'rrggbb' part) into an LCL TColor. False
  when the string is not exactly six hex digits. }
function TryParseHexColor(const AHex: string; out AColor: TColor): Boolean;
var r, g, b: Integer;
begin
  Result := False;
  if Length(AHex) <> 6 then Exit;
  if not TryStrToInt('$' + Copy(AHex, 1, 2), r) then Exit;
  if not TryStrToInt('$' + Copy(AHex, 3, 2), g) then Exit;
  if not TryStrToInt('$' + Copy(AHex, 5, 2), b) then Exit;
  AColor := RGBToColor(r, g, b);
  Result := True;
end;

function TyHtmlParse(const AHtml: string): TTyHtmlRunArray;
var
  stack: TTyHtmlRunArray;   // style stack; stack[0] is the base (empty) style
  sp: Integer;              // top-of-stack index
  cur: string;             // pending decoded text
  i, n, j: Integer;
  ch: Char;
  ent, decoded: string;

  procedure AppendRun(const ARun: TTyHtmlRun);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ARun;
  end;

  procedure FlushText;
  var r: TTyHtmlRun;
  begin
    if cur = '' then Exit;
    r := stack[sp];        // inherit the current style
    r.Text := cur;
    r.LineBreak := False;
    AppendRun(r);
    cur := '';
  end;

  procedure EmitLineBreak;
  var r: TTyHtmlRun;
  begin
    r := Default(TTyHtmlRun);
    r.LineBreak := True;
    AppendRun(r);
  end;

  procedure StackPush(const ANew: TTyHtmlRun);
  begin
    Inc(sp);
    if sp > High(stack) then SetLength(stack, sp + 1);
    stack[sp] := ANew;
  end;

  procedure StackPop;
  begin
    if sp > 0 then Dec(sp);   // never pop the base
  end;

  procedure HandleTag(const ATag: string);
  var
    t, nm: string;
    k: Integer;
    st: TTyHtmlRun;
    cv: string;
    tc: TColor;
  begin
    t := Trim(ATag);
    if t = '' then Exit;
    if t[1] = '/' then
    begin
      nm := LowerCase(Trim(Copy(t, 2, Length(t))));
      k := Pos(' ', nm);
      if k > 0 then nm := Copy(nm, 1, k - 1);
      if (nm = 'b') or (nm = 'i') or (nm = 'u') or (nm = 's')
         or (nm = 'font') or (nm = 'a') then
        StackPop;
      Exit;
    end;
    // Opening (or self-closing) tag: isolate the tag name.
    k := 1;
    while (k <= Length(t)) and (t[k] <> ' ') and (t[k] <> #9) and (t[k] <> '/') do
      Inc(k);
    nm := LowerCase(Copy(t, 1, k - 1));
    if nm = 'br' then
    begin
      EmitLineBreak;
      Exit;
    end;
    st := stack[sp];   // inherit and modify
    if nm = 'b' then
    begin st.Bold := True; StackPush(st); end
    else if nm = 'i' then
    begin st.Italic := True; StackPush(st); end
    else if nm = 'u' then
    begin st.Underline := True; StackPush(st); end
    else if nm = 's' then
    begin st.Strike := True; StackPush(st); end
    else if nm = 'font' then
    begin
      cv := GetTagAttr(t, 'color');
      if (Length(cv) = 7) and (cv[1] = '#') and TryParseHexColor(Copy(cv, 2, 6), tc) then
      begin st.Color := tc; st.HasColor := True; end;
      cv := GetTagAttr(t, 'size');
      if cv <> '' then
      begin
        k := StrToIntDef(cv, 0);
        if k > 0 then st.SizePt := k;
      end;
      StackPush(st);
    end
    else if nm = 'a' then
    begin
      st.Href := GetTagAttr(t, 'href');
      StackPush(st);
    end;
    // Any other tag name is ignored (tolerant): no push, so no close is expected.
  end;

begin
  Result := nil;
  SetLength(stack, 1);
  stack[0] := Default(TTyHtmlRun);
  sp := 0;
  cur := '';
  i := 1;
  n := Length(AHtml);
  while i <= n do
  begin
    ch := AHtml[i];
    if ch = '<' then
    begin
      j := i + 1;
      while (j <= n) and (AHtml[j] <> '>') do Inc(j);
      if j > n then
      begin
        // No closing '>' -> treat the '<' as a literal character (tolerant).
        cur := cur + '<';
        Inc(i);
        Continue;
      end;
      FlushText;
      HandleTag(Copy(AHtml, i + 1, j - i - 1));
      i := j + 1;
    end
    else if ch = '&' then
    begin
      j := i + 1;
      while (j <= n) and (j <= i + 10) and (AHtml[j] <> ';') do Inc(j);
      if (j <= n) and (j <= i + 10) and (AHtml[j] = ';') then
      begin
        ent := LowerCase(Copy(AHtml, i + 1, j - i - 1));
        decoded := DecodeEntity(ent);
        if decoded <> '' then
        begin cur := cur + decoded; i := j + 1; end
        else
        begin cur := cur + '&'; Inc(i); end;
      end
      else
      begin cur := cur + '&'; Inc(i); end;
    end
    else
    begin
      cur := cur + ch;
      Inc(i);
    end;
  end;
  FlushText;
end;

{ ---- font configuration shared by measure + draw ---- }

procedure ConfigRunFont(ABmp: TBGRABitmap; const ARun: TTyHtmlRun;
  const AFontName: string; ABaseSize, APPI: Integer);
var
  sz: Integer;
  fs: TFontStyles;
begin
  if ARun.SizePt > 0 then sz := ARun.SizePt else sz := ABaseSize;
  if sz <= 0 then sz := TyFallbackFontSize;
  ABmp.FontName := TyEffectiveFontName(AFontName);
  ABmp.FontHeight := MulDiv(Round(sz * 96 / 72), APPI, 96);
  ABmp.FontQuality := fqFineAntialiasing;
  fs := [];
  if ARun.Bold then Include(fs, fsBold);
  if ARun.Italic then Include(fs, fsItalic);
  ABmp.FontStyle := fs;
end;

{ ---- TTyHtmlLabel ---- }

constructor TTyHtmlLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWordWrap := True;
  TabStop := False;   // a label is not a tab stop by default
  SetInitialBounds(0, 0, 120, 20);
end;

function TTyHtmlLabel.GetStyleTypeKey: string;
begin
  Result := 'TyLabel';
end;

procedure TTyHtmlLabel.SetHtml(const AValue: string);
begin
  if FHtml = AValue then Exit;
  FHtml := AValue;
  FRuns := TyHtmlParse(FHtml);
  SetLength(FLayout, 0);   // force a re-layout
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyHtmlLabel.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  SetLength(FLayout, 0);
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyHtmlLabel.BuildLayout(AContentLeft, AContentTop, AContentWidth, APPI: Integer;
  out AExtW, AExtH: Integer);
var
  bmp: TBGRABitmap;
  S: TTyStyleSet;
  baseSize: Integer;
  fontName: string;
  frags: TTyHtmlFragArray;
  fragLine: array of Integer;
  lineH, lineTop: array of Integer;
  nf, curLine, penX, curLineH, ii, jj, kk, rh, sLen, yy, maxRight, h: Integer;
  run: TTyHtmlRun;

  procedure EnsureLine(idx: Integer);
  begin
    if idx > High(lineH) then SetLength(lineH, idx + 1);
  end;

  procedure NewLine;
  begin
    EnsureLine(curLine);
    if curLineH > lineH[curLine] then lineH[curLine] := curLineH;
    Inc(curLine);
    EnsureLine(curLine);
    penX := AContentLeft;
    curLineH := 0;
  end;

  procedure PlaceToken(const ATok: string; AIsSpace: Boolean);
  var w: Integer;
  begin
    w := bmp.TextSize(ATok).cx;
    if FWordWrap and (AContentWidth > 0) and (penX > AContentLeft)
       and (penX + w > AContentLeft + AContentWidth) then
    begin
      NewLine;
      if AIsSpace then Exit;   // drop a wrapping space
    end;
    if AIsSpace and (penX = AContentLeft) then Exit;   // skip a leading space
    if nf > High(frags) then
    begin
      SetLength(frags, (nf + 1) * 2);
      SetLength(fragLine, (nf + 1) * 2);
    end;
    frags[nf].Run := run;
    frags[nf].Run.Text := ATok;
    frags[nf].Rect := Rect(penX, 0, penX + w, rh);   // Rect.Bottom carries the height for now
    fragLine[nf] := curLine;
    Inc(nf);
    Inc(penX, w);
    if rh > curLineH then curLineH := rh;
  end;

begin
  AExtW := 0;
  AExtH := 0;
  SetLength(FLayout, 0);
  S := CurrentStyle;
  baseSize := ResolveFontSize(S);
  fontName := S.FontName;

  bmp := TBGRABitmap.Create(1, 1);
  try
    nf := 0;
    curLine := 0;
    penX := AContentLeft;
    curLineH := 0;
    SetLength(lineH, 1);
    lineH[0] := 0;

    for ii := 0 to High(FRuns) do
    begin
      run := FRuns[ii];
      if run.LineBreak then
      begin
        if curLineH = 0 then
        begin
          ConfigRunFont(bmp, run, fontName, baseSize, APPI);
          curLineH := bmp.TextSize('Ag').cy;   // an empty line still has height
        end;
        NewLine;
        Continue;
      end;
      if run.Text = '' then Continue;
      ConfigRunFont(bmp, run, fontName, baseSize, APPI);
      rh := bmp.TextSize('Ag').cy;
      jj := 1;
      sLen := Length(run.Text);
      while jj <= sLen do
      begin
        if (run.Text[jj] = ' ') or (run.Text[jj] = #9)
           or (run.Text[jj] = #10) or (run.Text[jj] = #13) then
        begin
          while (jj <= sLen) and ((run.Text[jj] = ' ') or (run.Text[jj] = #9)
                or (run.Text[jj] = #10) or (run.Text[jj] = #13)) do Inc(jj);
          PlaceToken(' ', True);
        end
        else
        begin
          kk := jj;
          while (jj <= sLen) and not ((run.Text[jj] = ' ') or (run.Text[jj] = #9)
                or (run.Text[jj] = #10) or (run.Text[jj] = #13)) do Inc(jj);
          PlaceToken(Copy(run.Text, kk, jj - kk), False);
        end;
      end;
    end;

    // Finalize the last line's height.
    EnsureLine(curLine);
    if curLineH > lineH[curLine] then lineH[curLine] := curLineH;

    // Cumulative line tops.
    SetLength(lineTop, Length(lineH));
    yy := AContentTop;
    for ii := 0 to High(lineH) do
    begin
      lineTop[ii] := yy;
      Inc(yy, lineH[ii]);
    end;
    AExtH := yy - AContentTop;

    // Assign final Y and collect FLayout; compute width extent.
    SetLength(FLayout, nf);
    maxRight := AContentLeft;
    for ii := 0 to nf - 1 do
    begin
      FLayout[ii] := frags[ii];
      h := frags[ii].Rect.Bottom;   // height stashed earlier
      FLayout[ii].Rect.Top := lineTop[fragLine[ii]];
      FLayout[ii].Rect.Bottom := lineTop[fragLine[ii]] + h;
      if FLayout[ii].Rect.Right > maxRight then maxRight := FLayout[ii].Rect.Right;
    end;
    AExtW := maxRight - AContentLeft;
  finally
    bmp.Free;
  end;
end;

procedure TTyHtmlLabel.EnsureLayout;
var
  S: TTyStyleSet;
  ppi, cl, ct, cw, ew, eh: Integer;
begin
  if Length(FLayout) > 0 then Exit;
  if Length(FRuns) = 0 then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  cl := MulDiv(S.Padding.Left, ppi, 96);
  ct := MulDiv(S.Padding.Top, ppi, 96);
  cw := ClientWidth - MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  if cw < 1 then cw := 1;
  BuildLayout(cl, ct, cw, ppi, ew, eh);
end;

function TTyHtmlLabel.LinkAt(X, Y: Integer): string;
var
  ii: Integer;
  pt: TPoint;
begin
  Result := '';
  pt := Point(X, Y);
  for ii := 0 to High(FLayout) do
    if (FLayout[ii].Run.Href <> '') and PtInRect(FLayout[ii].Rect, pt) then
      Exit(FLayout[ii].Run.Href);
end;

procedure TTyHtmlLabel.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, padW, padH, cl, ct, cw, ew, eh: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  padW := MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  padH := MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);
  cl := MulDiv(S.Padding.Left, ppi, 96);
  ct := MulDiv(S.Padding.Top, ppi, 96);
  if FWordWrap then
  begin
    cw := ClientWidth - padW;
    if cw < 1 then cw := 1;
  end
  else
    cw := 0;   // no wrapping -> natural width
  BuildLayout(cl, ct, cw, ppi, ew, eh);
  PreferredWidth := ew + padW;
  PreferredHeight := eh + padH;
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

procedure TTyHtmlLabel.DoSetBounds(ALeft, ATop, AWidth, AHeight: Integer);
var
  widthChanged: Boolean;
begin
  widthChanged := AWidth <> Width;
  inherited DoSetBounds(ALeft, ATop, AWidth, AHeight);
  SetLength(FLayout, 0);   // width may have changed -> stale layout
  if widthChanged and FWordWrap and AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
end;

procedure TTyHtmlLabel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, ov: TTyStyleSet;
  fb: TBGRABitmap;
  contentRect: TRect;
  cl, ct, cw, ew, eh, baseSize, ii, th, ly: Integer;
  fontName: string;
  linkColor, col: TTyColor;
  run: TTyHtmlRun;
  isLink: Boolean;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // Fill the (transparent-fill) label background + honor disabled opacity, and
    // composite the parent backdrop behind this windowed control.
    contentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, contentRect, S);

    cl := P.Scale(S.Padding.Left);
    ct := P.Scale(S.Padding.Top);
    cw := (contentRect.Right - contentRect.Left) - P.Scale(S.Padding.Left + S.Padding.Right);
    if cw < 1 then cw := 1;
    BuildLayout(cl, ct, cw, APPI, ew, eh);

    // Link colour = the theme accent (fall back to the text colour if unavailable).
    ov := ActiveController.Model.ResolveOverride('color: var(--accent);');
    if tpTextColor in ov.Present then linkColor := ov.TextColor
    else linkColor := S.TextColor;

    baseSize := ResolveFontSize(S);
    fontName := S.FontName;
    th := P.Scale(1);
    if th < 1 then th := 1;

    fb := P.Bitmap;
    for ii := 0 to High(FLayout) do
    begin
      run := FLayout[ii].Run;
      isLink := run.Href <> '';
      ConfigRunFont(fb, run, fontName, baseSize, APPI);
      if isLink then col := linkColor
      else if run.HasColor then col := LclColorToTy(run.Color)
      else col := S.TextColor;
      fb.TextOut(FLayout[ii].Rect.Left, FLayout[ii].Rect.Top, run.Text, TyColorToBGRA(col));
      // Links are underlined for affordance; <u> underlines any run; <s> strikes it.
      if run.Underline or isLink then
      begin
        ly := FLayout[ii].Rect.Bottom - th;
        fb.FillRect(FLayout[ii].Rect.Left, ly, FLayout[ii].Rect.Right, ly + th,
          TyColorToBGRA(col), dmDrawWithTransparency);
      end;
      if run.Strike then
      begin
        ly := (FLayout[ii].Rect.Top + FLayout[ii].Rect.Bottom) div 2;
        fb.FillRect(FLayout[ii].Rect.Left, ly, FLayout[ii].Rect.Right, ly + th,
          TyColorToBGRA(col), dmDrawWithTransparency);
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyHtmlLabel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyHtmlLabel.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  EnsureLayout;
  if LinkAt(X, Y) <> '' then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  inherited MouseMove(Shift, X, Y);
end;

procedure TTyHtmlLabel.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  href: string;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    EnsureLayout;
    href := LinkAt(X, Y);
    if (href <> '') and Assigned(FOnLinkClick) then
      FOnLinkClick(Self, href);
  end;
end;

initialization
  RegisterClass(TTyHtmlLabel);

end.
