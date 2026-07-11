unit tyControls.Chart;
{$mode objfpc}{$H+}
{ TTyChart — a themed line / bar / pie chart (a custom-drawn re-imagining of the
  BusinessSkinForm chart controls).

  TTyChart is a TTyGraphicControl. Its panel chrome (background / axis text / grid
  lines) comes entirely from the resolved TyPanel style, so it follows the active
  theme — no colour is hard-coded there. The DATA series use a fixed, tasteful
  palette (TyChartPalette, the Tableau-10 hues); an app may override any single
  series colour via TTyChartSeriesItem.Color.

  The chart's SCALE / LAYOUT arithmetic is factored into four PURE interface
  functions (TyChartNiceRange / TyChartValueToY / TyChartBarXRange /
  TyChartPieSweeps) so the whole geometry can be unit-tested headless. RenderTo
  is the real-machine paint path: it calls the pure functions, then fills / strokes
  via the BGRA antialiased Canvas2D.

  v1 does NOT include: tooltips / interaction / zoom / mixed chart types /
  secondary axes. }
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { A named dynamic Double array (FPC cannot return an anonymous `array of Double`).
    Not present in tyControls.Types, and that unit is off-limits this batch, so it is
    declared here. }
  TDoubleArray = array of Double;

  { Which chart TTyChart draws. Line/bar are multi-series (axes + grid); pie uses the
    first series' values as slice sizes. }
  TTyChartType = (ctLine, ctBar, ctPie);

  { One pie slice as an angular span, degrees. StartDeg is measured clockwise; the
    control offsets by -90 so slice 0 starts at the top. }
  TTyChartPieSlice = record
    StartDeg, SweepDeg: Double;
  end;
  TTyChartPieSliceArray = array of TTyChartPieSlice;

{ ---- Pure geometry (headless-testable; no control / painter / handle state) ---- }

{ Nice range: expand [AMin,AMax] to round boundaries so the tick count is ~ATarget.
  AStep is snapped to 1/2/5 x 10^k. Guarantees ANiceMin<=AMin, ANiceMax>=AMax,
  AStep>0. Degenerate input (AMax<=AMin) is expanded to a unit span first. }
procedure TyChartNiceRange(AMin, AMax: Double; ATarget: Integer;
  out ANiceMin, ANiceMax, AStep: Double);

{ Value -> pixel Y (linear). ATop is the pixel row for ANiceMax, ABottom the pixel
  row for ANiceMin. Returns ABottom when the range is degenerate. }
function TyChartValueToY(AValue, ANiceMin, ANiceMax: Double; ATop, ABottom: Integer): Integer;

{ The pixel X span [AX0,AX1] of the AIndex-th of ACount equally-spaced bars laid out
  in [ALeft,ARight], with a group gap so adjacent bars never overlap and every bar
  stays within [ALeft,ARight]. Degenerate (ACount<=0 or out-of-range AIndex) -> an
  empty span anchored at ALeft. }
procedure TyChartBarXRange(AIndex, ACount, ALeft, ARight: Integer; out AX0, AX1: Integer);

{ Pie sweep angles: each value's (StartDeg, SweepDeg) so the sweeps sum to 360 in
  proportion to the positive values. Negatives are clamped to 0. If the positive
  total is 0 (empty / all-zero / all-negative) every sweep is 0 (safe, no divide). }
function TyChartPieSweeps(const AValues: array of Double): TTyChartPieSliceArray;

const
  { Fixed, tasteful series palette (Tableau-10). TColor is $00BBGGRR. Series without
    an explicit Color cycle through these by index. }
  TyChartPalette: array[0..7] of TColor = (
    $00A7794E,   // blue    #4E79A7
    $002B8EF2,   // orange  #F28E2B
    $005957E1,   // red     #E15759
    $00B2B776,   // teal    #76B7B2
    $004FA159,   // green   #59A14F
    $0048C9ED,   // yellow  #EDC948
    $00A17AB0,   // purple  #B07AA1
    $00A79DFF);  // pink    #FF9DA7

type
  TTyChart = class;

  { One data series. Values is a comma-separated list of numbers (stream-friendly,
    designer-editable); ValueArray parses it. Color = clDefault -> the palette. }
  TTyChartSeriesItem = class(TCollectionItem)
  private
    FName: string;
    FColor: TColor;
    FValues: string;
    procedure SetName(const AValue: string);
    procedure SetColor(AValue: TColor);
    procedure SetValues(const AValue: string);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
    { The parsed numeric values ('.' decimal, comma-separated; blanks skipped). }
    function ValueArray: TDoubleArray;
  published
    property Name: string read FName write SetName;
    property Color: TColor read FColor write SetColor default clDefault;
    property Values: string read FValues write SetValues;
  end;

  { The series collection, owned by a TTyChart. }
  TTyChartSeries = class(TCollection)
  private
    FOwner: TPersistent;
    FOnChange: TNotifyEvent;
    function GetItem(AIndex: Integer): TTyChartSeriesItem;
    procedure SetItem(AIndex: Integer; AValue: TTyChartSeriesItem);
  protected
    function GetOwner: TPersistent; override;
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TTyChartSeriesItem;
    property Items[AIndex: Integer]: TTyChartSeriesItem read GetItem write SetItem; default;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TTyChart = class(TTyGraphicControl)
  private
    FChartType: TTyChartType;
    FSeries: TTyChartSeries;
    FCategories: TStrings;
    FTitle: string;
    FShowLegend: Boolean;
    FShowGrid: Boolean;
    FShowValues: Boolean;
    procedure SetChartType(AValue: TTyChartType);
    procedure SetSeries(AValue: TTyChartSeries);
    procedure SetCategories(AValue: TStrings);
    procedure SetTitle(const AValue: string);
    procedure SetShowLegend(AValue: Boolean);
    procedure SetShowGrid(AValue: Boolean);
    procedure SetShowValues(AValue: Boolean);
    procedure SeriesChanged(Sender: TObject);
    procedure CategoriesChanged(Sender: TObject);
    { Palette-resolved colour for series AIndex (its own Color, or the cycled palette). }
    function SeriesColor(AItem: TTyChartSeriesItem; AIndex: Integer): TColor;
    { Data extent across every series (or the first series for pie); false if no data. }
    function DataExtent(out AMin, AMax: Double; out AMaxLen: Integer): Boolean;
    procedure DrawTitle(P: TTyPainter; const S: TTyStyleSet; var ATop: Integer);
    procedure DrawAxesChart(P: TTyPainter; const S: TTyStyleSet; const APlot: TRect);
    procedure DrawPie(P: TTyPainter; const S: TTyStyleSet; const AArea: TRect);
    procedure DrawLegend(P: TTyPainter; const S: TTyStyleSet; const ARect: TRect; APie: Boolean);
  protected
    function GetStyleTypeKey: string; override;   // 'TyPanel' (no new theme token)
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property ChartType: TTyChartType read FChartType write SetChartType default ctLine;
    property Series: TTyChartSeries read FSeries write SetSeries;
    property Categories: TStrings read FCategories write SetCategories;
    property Title: string read FTitle write SetTitle;
    property ShowLegend: Boolean read FShowLegend write SetShowLegend default True;
    property ShowGrid: Boolean read FShowGrid write SetShowGrid default True;
    property ShowValues: Boolean read FShowValues write SetShowValues default False;
    property Align;
    property Anchors;
    property Font;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

{ ============================ pure geometry ============================ }

{ The 1/2/5-x-10^k "nice number" nearest (round) or not-below (ceil) AValue. }
function NiceNum(AValue: Double; ARound: Boolean): Double;
var
  expo, frac: Double;
begin
  if AValue <= 0 then Exit(1);
  expo := Floor(Log10(AValue));
  frac := AValue / Power(10, expo);
  if ARound then
  begin
    if frac < 1.5 then frac := 1
    else if frac < 3 then frac := 2
    else if frac < 7 then frac := 5
    else frac := 10;
  end
  else
  begin
    if frac <= 1 then frac := 1
    else if frac <= 2 then frac := 2
    else if frac <= 5 then frac := 5
    else frac := 10;
  end;
  Result := frac * Power(10, expo);
end;

procedure TyChartNiceRange(AMin, AMax: Double; ATarget: Integer;
  out ANiceMin, ANiceMax, AStep: Double);
var
  span, tmp: Double;
begin
  if ATarget < 2 then ATarget := 2;
  if AMax < AMin then
  begin
    tmp := AMin; AMin := AMax; AMax := tmp;
  end;
  if AMax <= AMin then AMax := AMin + 1;         // degenerate -> unit span
  span := NiceNum(AMax - AMin, False);
  AStep := NiceNum(span / (ATarget - 1), True);
  if AStep <= 0 then AStep := 1;
  ANiceMin := Floor(AMin / AStep) * AStep;
  ANiceMax := Ceil(AMax / AStep) * AStep;
end;

function TyChartValueToY(AValue, ANiceMin, ANiceMax: Double; ATop, ABottom: Integer): Integer;
var
  frac: Double;
begin
  if ANiceMax <= ANiceMin then Exit(ABottom);
  frac := (AValue - ANiceMin) / (ANiceMax - ANiceMin);
  Result := ABottom - Round(frac * (ABottom - ATop));
end;

procedure TyChartBarXRange(AIndex, ACount, ALeft, ARight: Integer; out AX0, AX1: Integer);
var
  slotW: Double;
  e0, e1, ipad: Integer;
begin
  AX0 := ALeft;
  AX1 := ALeft;
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  slotW := (ARight - ALeft) / ACount;
  e0 := ALeft + Round(AIndex * slotW);
  e1 := ALeft + Round((AIndex + 1) * slotW);
  ipad := Round(slotW * 0.15);
  if ipad < 1 then ipad := 1;
  AX0 := e0 + ipad;
  AX1 := e1 - ipad;
  if AX1 < AX0 then AX1 := AX0;                  // never invert on a tiny slot
end;

function TyChartPieSweeps(const AValues: array of Double): TTyChartPieSliceArray;
var
  i, n: Integer;
  total, v, start, acc: Double;
begin
  Result := nil;
  n := Length(AValues);
  if n = 0 then Exit;
  SetLength(Result, n);
  total := 0;
  for i := 0 to n - 1 do
    if AValues[i] > 0 then total := total + AValues[i];
  start := 0;
  if total <= 0 then
  begin
    // all-zero / all-negative: every span 0 (safe; no divide by zero)
    for i := 0 to n - 1 do
    begin
      Result[i].StartDeg := 0;
      Result[i].SweepDeg := 0;
    end;
    Exit;
  end;
  acc := 0;
  for i := 0 to n - 1 do
  begin
    if AValues[i] > 0 then v := AValues[i] else v := 0;
    Result[i].StartDeg := start;
    if i = n - 1 then
      Result[i].SweepDeg := 360 - acc          // absorb float remainder -> exact 360
    else
      Result[i].SweepDeg := (v / total) * 360;
    acc := acc + Result[i].SweepDeg;
    start := start + Result[i].SweepDeg;
  end;
end;

{ Parse a comma-separated numeric list with a '.' decimal separator. }
function ParseValues(const AText: string): TDoubleArray;
var
  parts: TStringList;
  fs: TFormatSettings;
  i, n: Integer;
  v: Double;
begin
  Result := nil;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  parts := TStringList.Create;
  try
    parts.StrictDelimiter := True;
    parts.Delimiter := ',';
    parts.DelimitedText := AText;
    SetLength(Result, parts.Count);
    n := 0;
    for i := 0 to parts.Count - 1 do
      if Trim(parts[i]) <> '' then
      begin
        v := StrToFloatDef(Trim(parts[i]), 0, fs);
        Result[n] := v;
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    parts.Free;
  end;
end;

{ ============================ TTyChartSeriesItem ============================ }

constructor TTyChartSeriesItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FColor := clDefault;
end;

procedure TTyChartSeriesItem.Assign(ASource: TPersistent);
var
  src: TTyChartSeriesItem;
begin
  if ASource is TTyChartSeriesItem then
  begin
    src := TTyChartSeriesItem(ASource);
    FName := src.FName;
    FColor := src.FColor;
    FValues := src.FValues;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

function TTyChartSeriesItem.GetDisplayName: string;
begin
  if FName <> '' then Result := FName
  else Result := inherited GetDisplayName;
end;

procedure TTyChartSeriesItem.SetName(const AValue: string);
begin
  if FName = AValue then Exit;
  FName := AValue;
  Changed(False);
end;

procedure TTyChartSeriesItem.SetColor(AValue: TColor);
begin
  if FColor = AValue then Exit;
  FColor := AValue;
  Changed(False);
end;

procedure TTyChartSeriesItem.SetValues(const AValue: string);
begin
  if FValues = AValue then Exit;
  FValues := AValue;
  Changed(False);
end;

function TTyChartSeriesItem.ValueArray: TDoubleArray;
begin
  Result := ParseValues(FValues);
end;

{ ============================ TTyChartSeries ============================ }

constructor TTyChartSeries.Create(AOwner: TPersistent);
begin
  inherited Create(TTyChartSeriesItem);
  FOwner := AOwner;
end;

function TTyChartSeries.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

function TTyChartSeries.Add: TTyChartSeriesItem;
begin
  Result := TTyChartSeriesItem(inherited Add);
end;

function TTyChartSeries.GetItem(AIndex: Integer): TTyChartSeriesItem;
begin
  Result := TTyChartSeriesItem(inherited Items[AIndex]);
end;

procedure TTyChartSeries.SetItem(AIndex: Integer; AValue: TTyChartSeriesItem);
begin
  inherited Items[AIndex] := AValue;
end;

procedure TTyChartSeries.Notify(Item: TCollectionItem; Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyChartSeries.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if Assigned(FOnChange) then FOnChange(Self);
end;

{ ============================ TTyChart ============================ }

constructor TTyChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChartType := ctLine;
  FSeries := TTyChartSeries.Create(Self);
  FSeries.OnChange := @SeriesChanged;
  FCategories := TStringList.Create;
  TStringList(FCategories).OnChange := @CategoriesChanged;
  FShowLegend := True;
  FShowGrid := True;
  FShowValues := False;
  Width := 260;
  Height := 180;
end;

destructor TTyChart.Destroy;
begin
  FSeries.Free;
  FCategories.Free;
  inherited Destroy;
end;

function TTyChart.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

procedure TTyChart.SetChartType(AValue: TTyChartType);
begin
  if FChartType = AValue then Exit;
  FChartType := AValue;
  Invalidate;
end;

procedure TTyChart.SetSeries(AValue: TTyChartSeries);
begin
  FSeries.Assign(AValue);
  Invalidate;
end;

procedure TTyChart.SetCategories(AValue: TStrings);
begin
  FCategories.Assign(AValue);
  Invalidate;
end;

procedure TTyChart.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  Invalidate;
end;

procedure TTyChart.SetShowLegend(AValue: Boolean);
begin
  if FShowLegend = AValue then Exit;
  FShowLegend := AValue;
  Invalidate;
end;

procedure TTyChart.SetShowGrid(AValue: Boolean);
begin
  if FShowGrid = AValue then Exit;
  FShowGrid := AValue;
  Invalidate;
end;

procedure TTyChart.SetShowValues(AValue: Boolean);
begin
  if FShowValues = AValue then Exit;
  FShowValues := AValue;
  Invalidate;
end;

procedure TTyChart.SeriesChanged(Sender: TObject);
begin
  Invalidate;
end;

procedure TTyChart.CategoriesChanged(Sender: TObject);
begin
  Invalidate;
end;

function TTyChart.SeriesColor(AItem: TTyChartSeriesItem; AIndex: Integer): TColor;
begin
  if AItem.Color = clDefault then
    Result := TyChartPalette[AIndex mod Length(TyChartPalette)]
  else
    Result := AItem.Color;
end;

function TTyChart.DataExtent(out AMin, AMax: Double; out AMaxLen: Integer): Boolean;
var
  si, vi: Integer;
  vals: TDoubleArray;
  seen: Boolean;
begin
  AMin := 0;
  AMax := 0;
  AMaxLen := 0;
  seen := False;
  for si := 0 to FSeries.Count - 1 do
  begin
    vals := FSeries.Items[si].ValueArray;
    if Length(vals) > AMaxLen then AMaxLen := Length(vals);
    for vi := 0 to High(vals) do
    begin
      if not seen then
      begin
        AMin := vals[vi];
        AMax := vals[vi];
        seen := True;
      end
      else
      begin
        if vals[vi] < AMin then AMin := vals[vi];
        if vals[vi] > AMax then AMax := vals[vi];
      end;
    end;
    if FChartType = ctPie then Break;   // pie only uses the first series
  end;
  Result := seen;
end;

procedure TTyChart.DrawTitle(P: TTyPainter; const S: TTyStyleSet; var ATop: Integer);
var
  h: Integer;
begin
  if FTitle = '' then Exit;
  h := P.Scale(20);
  { Left is the horizontal margin, NOT ATop (the running Y cursor) -- they coincide only
    when the title is the first thing drawn. }
  P.DrawText(Rect(P.Scale(8), ATop, P.Bitmap.Width - P.Scale(8), ATop + h),
    FTitle, Font.Name, 11, 700, S.TextColor, taCenter, tlCenter, True);
  Inc(ATop, h);
end;

procedure TTyChart.DrawLegend(P: TTyPainter; const S: TTyStyleSet; const ARect: TRect; APie: Boolean);
var
  i, x, sw, gap, tw, cnt, boxSz: Integer;
  nm: string;
  cy: Integer;
  seriesItem: TTyChartSeriesItem;
  swatch: TColor;
begin
  boxSz := P.Scale(10);
  gap := P.Scale(6);
  sw := P.Scale(14);
  x := ARect.Left;
  cy := (ARect.Top + ARect.Bottom) div 2;
  if APie then
    cnt := FCategories.Count
  else
    cnt := FSeries.Count;
  for i := 0 to cnt - 1 do
  begin
    if APie then
    begin
      nm := FCategories[i];
      swatch := TyChartPalette[i mod Length(TyChartPalette)];
    end
    else
    begin
      seriesItem := FSeries.Items[i];
      nm := seriesItem.Name;
      if nm = '' then nm := 'Series ' + IntToStr(i + 1);
      swatch := SeriesColor(seriesItem, i);
    end;
    P.Bitmap.FillRect(x, cy - boxSz div 2, x + boxSz, cy + boxSz div 2,
      ColorToBGRA(swatch), dmSet);
    Inc(x, boxSz + P.Scale(4));
    tw := P.MeasureText(nm, Font.Name, 9, 400).cx;
    P.DrawText(Rect(x, ARect.Top, x + tw + P.Scale(2), ARect.Bottom),
      nm, Font.Name, 9, 400, S.TextColor, taLeftJustify, tlCenter, False);
    Inc(x, tw + sw + gap);
    if x > ARect.Right then Break;
  end;
end;

procedure TTyChart.DrawAxesChart(P: TTyPainter; const S: TTyStyleSet; const APlot: TRect);
var
  dMin, dMax, niceMin, niceMax, step, v: Double;
  maxLen, catCount, seriesCount, si, ci: Integer;
  ctx: TBGRACanvas2D;
  gridPx, axisPx: TBGRAPixel;
  y, x0, x1, cx0, cx1, y0, px, py: Integer;
  vals: TDoubleArray;
  fs: TFormatSettings;
  lbl: string;
  seriesItem: TTyChartSeriesItem;
  seriesPx: TBGRAPixel;
  first: Boolean;
begin
  if not DataExtent(dMin, dMax, maxLen) then Exit;
  // bars/lines share a zero baseline so heights read honestly
  if dMin > 0 then dMin := 0;
  if dMax < 0 then dMax := 0;
  TyChartNiceRange(dMin, dMax, 5, niceMin, niceMax, step);

  seriesCount := FSeries.Count;
  catCount := maxLen;
  if FCategories.Count > catCount then catCount := FCategories.Count;
  if catCount < 1 then catCount := 1;

  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';

  ctx := P.Bitmap.Canvas2D;
  gridPx := TyColorToBGRA(S.BorderColor);
  gridPx.alpha := 70;
  axisPx := TyColorToBGRA(S.BorderColor);

  // horizontal grid + Y tick labels
  v := niceMin;
  while v <= niceMax + step / 2 do
  begin
    y := TyChartValueToY(v, niceMin, niceMax, APlot.Top, APlot.Bottom);
    if FShowGrid then
    begin
      ctx.beginPath;
      ctx.moveTo(APlot.Left, y + 0.5);
      ctx.lineTo(APlot.Right, y + 0.5);
      ctx.lineWidth := 1;
      ctx.strokeStyle(gridPx);
      ctx.stroke;
    end;
    if Abs(v) < 1e9 then lbl := FormatFloat('0.###', v, fs) else lbl := '';
    P.DrawText(Rect(APlot.Left - P.Scale(34), y - P.Scale(8), APlot.Left - P.Scale(3), y + P.Scale(8)),
      lbl, Font.Name, 8, 400, S.TextColor, taRightJustify, tlCenter, False);
    v := v + step;
  end;

  // axes (left + bottom)
  ctx.beginPath;
  ctx.moveTo(APlot.Left + 0.5, APlot.Top);
  ctx.lineTo(APlot.Left + 0.5, APlot.Bottom + 0.5);
  ctx.lineTo(APlot.Right, APlot.Bottom + 0.5);
  ctx.lineWidth := 1;
  ctx.strokeStyle(axisPx);
  ctx.stroke;

  y0 := TyChartValueToY(0, niceMin, niceMax, APlot.Top, APlot.Bottom);

  // X category labels
  for ci := 0 to catCount - 1 do
  begin
    TyChartBarXRange(ci, catCount, APlot.Left, APlot.Right, cx0, cx1);
    if ci < FCategories.Count then lbl := FCategories[ci] else lbl := IntToStr(ci + 1);
    P.DrawText(Rect(cx0 - P.Scale(4), APlot.Bottom + P.Scale(2), cx1 + P.Scale(4), APlot.Bottom + P.Scale(16)),
      lbl, Font.Name, 8, 400, S.TextColor, taCenter, tlCenter, False);
  end;

  // series
  for si := 0 to seriesCount - 1 do
  begin
    seriesItem := FSeries.Items[si];
    vals := seriesItem.ValueArray;
    seriesPx := ColorToBGRA(SeriesColor(seriesItem, si));
    if FChartType = ctBar then
    begin
      for ci := 0 to High(vals) do
      begin
        TyChartBarXRange(ci, catCount, APlot.Left, APlot.Right, cx0, cx1);
        TyChartBarXRange(si, seriesCount, cx0, cx1, x0, x1);
        y := TyChartValueToY(vals[ci], niceMin, niceMax, APlot.Top, APlot.Bottom);
        if y <= y0 then
          P.Bitmap.FillRect(x0, y, x1, y0, seriesPx, dmSet)
        else
          P.Bitmap.FillRect(x0, y0, x1, y, seriesPx, dmSet);
        if FShowValues then
          P.DrawText(Rect(x0 - P.Scale(6), y - P.Scale(14), x1 + P.Scale(6), y - P.Scale(1)),
            FormatFloat('0.###', vals[ci], fs), Font.Name, 8, 400, S.TextColor,
            taCenter, tlBottom, False);
      end;
    end
    else  // ctLine
    begin
      first := True;
      ctx.beginPath;
      ctx.lineWidth := P.Scale(2);
      ctx.lineJoin := 'round';
      ctx.strokeStyle(seriesPx);
      for ci := 0 to High(vals) do
      begin
        TyChartBarXRange(ci, catCount, APlot.Left, APlot.Right, cx0, cx1);
        px := (cx0 + cx1) div 2;
        py := TyChartValueToY(vals[ci], niceMin, niceMax, APlot.Top, APlot.Bottom);
        if first then begin ctx.moveTo(px, py); first := False; end
        else ctx.lineTo(px, py);
      end;
      ctx.stroke;
      // point markers + optional values
      for ci := 0 to High(vals) do
      begin
        TyChartBarXRange(ci, catCount, APlot.Left, APlot.Right, cx0, cx1);
        px := (cx0 + cx1) div 2;
        py := TyChartValueToY(vals[ci], niceMin, niceMax, APlot.Top, APlot.Bottom);
        ctx.beginPath;
        ctx.arc(px, py, P.Scale(3), 0, 2 * Pi, False);
        ctx.fillStyle(seriesPx);
        ctx.fill;
        if FShowValues then
          P.DrawText(Rect(px - P.Scale(16), py - P.Scale(15), px + P.Scale(16), py - P.Scale(2)),
            FormatFloat('0.###', vals[ci], fs), Font.Name, 8, 400, S.TextColor,
            taCenter, tlBottom, False);
      end;
    end;
  end;
end;

procedure TTyChart.DrawPie(P: TTyPainter; const S: TTyStyleSet; const AArea: TRect);
var
  vals: TDoubleArray;
  slices: TTyChartPieSliceArray;
  ctx: TBGRACanvas2D;
  cx, cy, radius, a0, a1, mid, total: Double;
  i, lx, ly: Integer;
  sepPx: TBGRAPixel;
  fs: TFormatSettings;
begin
  if FSeries.Count = 0 then Exit;
  vals := FSeries.Items[0].ValueArray;
  if Length(vals) = 0 then Exit;
  slices := TyChartPieSweeps(vals);

  cx := (AArea.Left + AArea.Right) / 2;
  cy := (AArea.Top + AArea.Bottom) / 2;
  radius := Min(AArea.Right - AArea.Left, AArea.Bottom - AArea.Top) / 2 - P.Scale(2);
  if radius < 1 then Exit;

  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  total := 0;
  for i := 0 to High(vals) do
    if vals[i] > 0 then total := total + vals[i];

  ctx := P.Bitmap.Canvas2D;
  sepPx := TyColorToBGRA(S.Background.Color);
  for i := 0 to High(slices) do
  begin
    if slices[i].SweepDeg <= 0 then Continue;
    a0 := DegToRad(slices[i].StartDeg - 90);
    a1 := DegToRad(slices[i].StartDeg + slices[i].SweepDeg - 90);
    ctx.beginPath;
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, radius, a0, a1, False);
    ctx.closePath;
    ctx.fillStyle(ColorToBGRA(TyChartPalette[i mod Length(TyChartPalette)]));
    ctx.fill;
    // thin separator in the surface colour
    ctx.lineWidth := P.Scale(1);
    ctx.strokeStyle(sepPx);
    ctx.stroke;
    if FShowValues and (total > 0) then
    begin
      mid := DegToRad(slices[i].StartDeg + slices[i].SweepDeg / 2 - 90);
      lx := Round(cx + Cos(mid) * radius * 0.6);
      ly := Round(cy + Sin(mid) * radius * 0.6);
      P.DrawText(Rect(lx - P.Scale(20), ly - P.Scale(8), lx + P.Scale(20), ly + P.Scale(8)),
        FormatFloat('0.#', (vals[i] / total) * 100, fs) + '%', Font.Name, 8, 700,
        S.TextColor, taCenter, tlCenter, False);
    end;
  end;
end;

procedure TTyChart.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, plot, legendR: TRect;
  topY, margin, legendH, xAxisH, yAxisW: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
    begin
      P.EndPaint;
      Exit;
    end;

    DrawFrame(P, R, S);   // panel background + border (themed)

    margin := P.Scale(8);
    topY := margin;
    DrawTitle(P, S, topY);

    legendH := 0;
    if FShowLegend then legendH := P.Scale(18);

    if FChartType = ctPie then
    begin
      legendR := Rect(margin, R.Bottom - margin - legendH, R.Right - margin, R.Bottom - margin);
      DrawPie(P, S, Rect(margin, topY, R.Right - margin, R.Bottom - margin - legendH));
      if FShowLegend then DrawLegend(P, S, legendR, True);
    end
    else
    begin
      yAxisW := P.Scale(38);
      xAxisH := P.Scale(16);
      plot := Rect(margin + yAxisW, topY + margin,
                   R.Right - margin, R.Bottom - margin - xAxisH - legendH);
      if (plot.Right > plot.Left) and (plot.Bottom > plot.Top) then
        DrawAxesChart(P, S, plot);
      if FShowLegend then
        DrawLegend(P, S, Rect(margin + yAxisW, R.Bottom - margin - legendH, R.Right - margin, R.Bottom - margin), False);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyChart.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

initialization
  RegisterClass(TTyChart);
end.
