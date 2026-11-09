unit test.advchart.themedump;
{$mode objfpc}{$H+}

{ Test support, not a suite: a deterministic JSON dump of what every built-in theme, in both
  modes, resolves for the chart. Two things go in:
    - each of the chart's --advchart-* tokens (TyAdvChartThemeTokens), read with ResolveToken;
    - each of the chart's TyAdvChart* typeKeys (TyAdvChartThemeTypeKeys), resolved with no
      style class under no state and under each pseudo-state, every field of the result
      written as text.
  The two lists are the ones themes/light.tycss carried when the chart was split out of the
  core (the same regexes as scripts/gen-tycss-catalog.ps1 pull). They are constants here
  because after the split light.tycss no longer holds them.

  The text is the same on every run and on every machine: names and keys are sorted ordinally,
  floats use a fixed format, and a path under the checkout is written relative to it. A
  baseline taken before the split and the dump taken after it can be compared as they are. }

interface

// The dump as JSON. One object keyed '<theme>|<light|dark>', each holding 'tokens' (token name to
// value) and 'typeKeys' (typeKey to one text line per state).
function TyAdvChartThemeDump: string;

implementation

uses
  Classes, SysUtils, tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.ThemeRegistry, tyControls.BuiltinThemes;

const
  cTokens: array[0..9] of string = (
    '--advchart-axispointer-margin',
    '--advchart-label-margin',
    '--advchart-minor-tick-length',
    '--advchart-name-gap',
    '--advchart-single-tick-length',
    '--advchart-tick-length',
    '--advchart-tooltip-gap',
    '--advchart-tooltip-gutter',
    '--advchart-tooltip-marker',
    '--advchart-tooltip-marker-gap'
  );

  cTypeKeys: array[0..86] of string = (
    'TyAdvChart',
    'TyAdvChartAxisLabel',
    'TyAdvChartAxisLabelPrimary',
    'TyAdvChartAxisLine',
    'TyAdvChartAxisName',
    'TyAdvChartAxisPointer',
    'TyAdvChartAxisPointerLabel',
    'TyAdvChartAxisPointerShadow',
    'TyAdvChartAxisTick',
    'TyAdvChartBarBackground',
    'TyAdvChartBreadcrumb',
    'TyAdvChartBreakArea',
    'TyAdvChartBrush',
    'TyAdvChartBrushOut',
    'TyAdvChartCandleDown',
    'TyAdvChartCandleUp',
    'TyAdvChartDataZoom',
    'TyAdvChartDataZoomBackground',
    'TyAdvChartDataZoomBorder',
    'TyAdvChartDataZoomBrush',
    'TyAdvChartDataZoomFiller',
    'TyAdvChartDataZoomHandle',
    'TyAdvChartDataZoomMoveHandle',
    'TyAdvChartDataZoomShadow',
    'TyAdvChartDataZoomShadowSelected',
    'TyAdvChartDecal',
    'TyAdvChartEmptyCircle',
    'TyAdvChartFocusItem',
    'TyAdvChartGaugeDetail',
    'TyAdvChartGeoArea',
    'TyAdvChartGeoLabel',
    'TyAdvChartGridBorder',
    'TyAdvChartLabel',
    'TyAdvChartLabelOnDark',
    'TyAdvChartLabelOnLight',
    'TyAdvChartLabelOnMid',
    'TyAdvChartLegend',
    'TyAdvChartLegendBackground',
    'TyAdvChartLegendBorder',
    'TyAdvChartLegendInactive',
    'TyAdvChartLegendPageIcon',
    'TyAdvChartLegendPageIconInactive',
    'TyAdvChartLegendPageText',
    'TyAdvChartLegendSelector',
    'TyAdvChartLoading',
    'TyAdvChartLoadingSpinner',
    'TyAdvChartMapArea',
    'TyAdvChartMinorSplitLine',
    'TyAdvChartMinorTick',
    'TyAdvChartParallelSelect',
    'TyAdvChartSankeyLink',
    'TyAdvChartSeries1',
    'TyAdvChartSeries2',
    'TyAdvChartSeries3',
    'TyAdvChartSeries4',
    'TyAdvChartSeries5',
    'TyAdvChartSeries6',
    'TyAdvChartSeries7',
    'TyAdvChartSeries8',
    'TyAdvChartSeries9',
    'TyAdvChartShadow',
    'TyAdvChartSplitArea',
    'TyAdvChartSplitLine',
    'TyAdvChartSubtitle',
    'TyAdvChartThumbnail',
    'TyAdvChartThumbnailWindow',
    'TyAdvChartTimeline',
    'TyAdvChartTimelineCheckpoint',
    'TyAdvChartTimelineControl',
    'TyAdvChartTimelineItem',
    'TyAdvChartTimelineLabel',
    'TyAdvChartTimelineProgress',
    'TyAdvChartTitle',
    'TyAdvChartToolbox',
    'TyAdvChartToolboxBackground',
    'TyAdvChartToolboxBorder',
    'TyAdvChartToolboxBrush',
    'TyAdvChartTooltip',
    'TyAdvChartTooltipValue',
    'TyAdvChartTreeEdge',
    'TyAdvChartTreeNode',
    'TyAdvChartTreemapLabel',
    'TyAdvChartVisualMap',
    'TyAdvChartVisualMapBackground',
    'TyAdvChartVisualMapBorder',
    'TyAdvChartVisualMapHandle',
    'TyAdvChartVisualMapInactive'
  );

  cStateNames: array[0..5] of string =
    ('normal', 'hover', 'active', 'focused', 'disabled', 'selected');

var
  GFS: TFormatSettings;

function JsonStr(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '"';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9:  Result := Result + '\t';
    else
      if c < ' ' then
        Result := Result + '\u' + IntToHex(Ord(c), 4)
      else
        Result := Result + c;
    end;
  end;
  Result := Result + '"';
end;

function Flt(V: Double): string;
begin
  Result := FormatFloat('0.######', V, GFS);
  if Result = '-0' then Result := '0';
end;

function Clr(C: TTyColor): string;
begin
  Result := '#' + IntToHex(Cardinal(C), 8);
end;

{ A path the style carries, with the checkout's own location taken out so it reads the same
  wherever the tree is. }
function PathText(const P: string): string;
var
  root: string;
begin
  Result := P;
  if Result = '' then Exit;
  root := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim);
  if (root <> '') and (Pos(root, Result) = 1) then
    Result := '<root>' + PathDelim + Copy(Result, Length(root) + 1, MaxInt);
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
end;

function FillText(const F: TTyFill): string;
var
  i: Integer;
begin
  Result := Format('kind=%d color=%s from=%s to=%s angle=%s slice=%d,%d,%d,%d repeat=%d mode=%d ' +
    'blur=%d glassblur=%d glasstint=%s img=%s stops=[',
    [Ord(F.Kind), Clr(F.Color), Clr(F.GradFrom), Clr(F.GradTo), Flt(F.GradAngleDeg),
     F.SliceInsets.Left, F.SliceInsets.Top, F.SliceInsets.Right, F.SliceInsets.Bottom,
     Ord(F.SliceRepeat), Ord(F.ImageMode), F.Blur, F.GlassBlur, Clr(F.GlassTint),
     PathText(F.ImagePath)]);
  for i := 0 to High(F.GradStops) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + Clr(F.GradStops[i].Color) + '@' + Flt(F.GradStops[i].Pos);
  end;
  Result := Result + ']';
end;

function StyleText(const S: TTyStyleSet): string;
var
  p: TTyProp;
  present: string;
begin
  present := '';
  for p := Low(TTyProp) to High(TTyProp) do
    if p in S.Present then
      present := present + IntToStr(Ord(p)) + ',';
  Result := Format('present=[%s] bg={%s} bgUnderTitle=%d windowShadow=%d text=%s border=%s ' +
    'bw=%d bstyle=%d rstyle=%d br=%d radius=%d,%d,%d,%d pad=%d,%d,%d,%d font=%s fsize=%d ' +
    'fweight=%d opacity=%s shadow=%s,%d,%d,%d outline=%s,%d,%d',
    [present, FillText(S.Background), Ord(S.BackgroundUnderTitlebar), Ord(S.WindowShadow),
     Clr(S.TextColor), Clr(S.BorderColor), S.BorderWidth, Ord(S.BorderStyle),
     Ord(S.RenderStyle), S.BorderRadius, S.Radius.TL, S.Radius.TR, S.Radius.BR, S.Radius.BL,
     S.Padding.Left, S.Padding.Top, S.Padding.Right, S.Padding.Bottom, S.FontName,
     S.FontSize, S.FontWeight, Flt(S.Opacity), Clr(S.ShadowColor), S.ShadowBlur,
     S.ShadowOffset.X, S.ShadowOffset.Y, Clr(S.OutlineColor), S.OutlineWidth,
     S.OutlineOffset]);
end;

function StatesOf(AIndex: Integer): TTyStateSet;
begin
  Result := [];
  case AIndex of
    1: Result := [tysHover];
    2: Result := [tysActive];
    3: Result := [tysFocused];
    4: Result := [tysDisabled];
    5: Result := [tysSelected];
  end;
end;

function SortedNames: TStringList;
var
  names: TStringArray;
  i, j: Integer;
  t: string;
begin
  names := TyBuiltinThemeNames;
  Result := TStringList.Create;
  for i := 0 to High(names) do
    Result.Add(names[i]);
  // ordinal order, so the text does not depend on the locale
  for i := 0 to Result.Count - 2 do
    for j := i + 1 to Result.Count - 1 do
      if CompareStr(Result[j], Result[i]) < 0 then
      begin
        t := Result[i]; Result[i] := Result[j]; Result[j] := t;
      end;
end;

function TyAdvChartThemeDump: string;
var
  c: TTyStyleController;
  names: TStringList;
  sb: TStringBuilder;
  i, m, k, s: Integer;
  mode, line: string;
  firstEntry: Boolean;
begin
  TyRegisterBuiltinThemes;
  GFS := DefaultFormatSettings;
  GFS.DecimalSeparator := '.';
  sb := TStringBuilder.Create;
  names := SortedNames;
  c := TTyStyleController.Create(nil);
  try
    sb.Append('{').Append(#10);
    firstEntry := True;
    for i := 0 to names.Count - 1 do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        if not firstEntry then sb.Append(',').Append(#10);
        firstEntry := False;
        sb.Append(JsonStr(names[i] + '|' + mode)).Append(': {').Append(#10);
        sb.Append('  "tokens": {').Append(#10);
        for k := 0 to High(cTokens) do
        begin
          sb.Append('    ').Append(JsonStr(cTokens[k])).Append(': ')
            .Append(JsonStr(c.Model.ResolveToken(cTokens[k])));
          if k < High(cTokens) then sb.Append(',');
          sb.Append(#10);
        end;
        sb.Append('  },').Append(#10);
        sb.Append('  "typeKeys": {').Append(#10);
        for k := 0 to High(cTypeKeys) do
        begin
          line := '';
          for s := 0 to High(cStateNames) do
          begin
            if s > 0 then line := line + #10;
            line := line + cStateNames[s] + ': ' +
              StyleText(c.Model.ResolveStyle(cTypeKeys[k], '', StatesOf(s)));
          end;
          sb.Append('    ').Append(JsonStr(cTypeKeys[k])).Append(': ').Append(JsonStr(line));
          if k < High(cTypeKeys) then sb.Append(',');
          sb.Append(#10);
        end;
        sb.Append('  }').Append(#10).Append('}');
      end;
    sb.Append(#10).Append('}').Append(#10);
    Result := sb.ToString;
  finally
    c.Free;
    names.Free;
    sb.Free;
  end;
end;

end.
