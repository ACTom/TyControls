unit tyControls.StyleModel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types,
  tyControls.Types, tyControls.Css.Parser, tyControls.Css.Values;

type
  TTyStyleModel = class
  private
    FRules: TFPList;          // owns TTyStyleRuleEntry
    FVars: TStringList;       // name=value, no leading --
    procedure AddEntry(const ATypeName, AVariant: string; AHasState: Boolean;
      AState: TTyState; const AStyle: TTyStyleSet);
    function FindStyle(const ATypeName, AVariant: string; AHasState: Boolean;
      AState: TTyState; out AStyle: TTyStyleSet): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadFromCss(const ASource: string);   // raises ETyCssError
    procedure LoadFromFile(const AFileName: string);
    function ResolveStyle(const ATypeKey, AStyleClass: string; AStates: TTyStateSet): TTyStyleSet;
  end;

procedure TyMergeStyleSet(var ABase: TTyStyleSet; const AOver: TTyStyleSet);

// Apply one CSS declaration (prop name + raw value) to a style set, resolving
// values against Vars, and set the matching Present flag. Returns False for
// unknown property names (caller may ignore).
function TyApplyDeclaration(var AStyle: TTyStyleSet; const AProp, ARawValue: string;
  Vars: TStrings): Boolean;

implementation

type
  TTyStyleRuleEntry = class
    TypeName: string;
    Variant: string;
    HasState: Boolean;
    State: TTyState;
    Style: TTyStyleSet;
  end;

procedure TyMergeStyleSet(var ABase: TTyStyleSet; const AOver: TTyStyleSet);
begin
  if tpBackground   in AOver.Present then ABase.Background   := AOver.Background;
  if tpTextColor    in AOver.Present then ABase.TextColor    := AOver.TextColor;
  if tpBorderColor  in AOver.Present then ABase.BorderColor  := AOver.BorderColor;
  if tpBorderWidth  in AOver.Present then ABase.BorderWidth  := AOver.BorderWidth;
  if tpBorderRadius in AOver.Present then ABase.BorderRadius := AOver.BorderRadius;
  if tpPadding      in AOver.Present then ABase.Padding      := AOver.Padding;
  if tpFontName     in AOver.Present then ABase.FontName     := AOver.FontName;
  if tpFontSize     in AOver.Present then ABase.FontSize     := AOver.FontSize;
  if tpFontWeight   in AOver.Present then ABase.FontWeight   := AOver.FontWeight;
  if tpOpacity      in AOver.Present then ABase.Opacity      := AOver.Opacity;
  if tpShadow       in AOver.Present then
  begin
    ABase.ShadowColor  := AOver.ShadowColor;
    ABase.ShadowBlur   := AOver.ShadowBlur;
    ABase.ShadowOffset := AOver.ShadowOffset;
  end;
  ABase.Present := ABase.Present + AOver.Present;
end;

// Parse 'a b c d' (space-separated logical px) into a TRect (Left Top Right Bottom);
// 1 value = all sides, 2 = vert/horiz, 4 = explicit.
function ParsePadding(const ARaw: string; Vars: TStrings): TRect;
var
  parts: TStringList;
  v: array[0..3] of Integer;
  i: Integer;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := True;
    parts.DelimitedText := Trim(ARaw);
    // drop empties produced by multiple spaces
    for i := parts.Count - 1 downto 0 do
      if Trim(parts[i]) = '' then parts.Delete(i);
    for i := 0 to 3 do v[i] := 0;
    case parts.Count of
      1:
        begin
          v[0] := TyEvalLength(parts[0], Vars);
          v[1] := v[0]; v[2] := v[0]; v[3] := v[0];
        end;
      2:
        begin
          v[1] := TyEvalLength(parts[0], Vars); // top
          v[3] := v[1];                          // bottom
          v[0] := TyEvalLength(parts[1], Vars); // left
          v[2] := v[0];                          // right
        end;
      4:
        begin
          v[1] := TyEvalLength(parts[0], Vars); // top
          v[2] := TyEvalLength(parts[1], Vars); // right
          v[3] := TyEvalLength(parts[2], Vars); // bottom
          v[0] := TyEvalLength(parts[3], Vars); // left
        end;
    else
      raise Exception.CreateFmt('Invalid padding: %s', [ARaw]);
    end;
    Result := Rect(v[0], v[1], v[2], v[3]);
  finally
    parts.Free;
  end;
end;

function TyApplyDeclaration(var AStyle: TTyStyleSet; const AProp, ARawValue: string;
  Vars: TStrings): Boolean;
var
  prop, raw: string;
  fill: TTyFill;
begin
  Result := True;
  prop := LowerCase(Trim(AProp));
  raw := Trim(ARawValue);
  if prop = 'background' then
  begin
    fill := AStyle.Background;
    fill.Kind := tfkSolid;
    fill.Color := TyEvalColor(raw, Vars);
    AStyle.Background := fill;
    Include(AStyle.Present, tpBackground);
  end
  else if prop = 'color' then
  begin
    AStyle.TextColor := TyEvalColor(raw, Vars);
    Include(AStyle.Present, tpTextColor);
  end
  else if prop = 'border-color' then
  begin
    AStyle.BorderColor := TyEvalColor(raw, Vars);
    Include(AStyle.Present, tpBorderColor);
  end
  else if prop = 'border-width' then
  begin
    AStyle.BorderWidth := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpBorderWidth);
  end
  else if prop = 'border-radius' then
  begin
    AStyle.BorderRadius := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpBorderRadius);
  end
  else if prop = 'padding' then
  begin
    AStyle.Padding := ParsePadding(raw, Vars);
    Include(AStyle.Present, tpPadding);
  end
  else if prop = 'font-family' then
  begin
    AStyle.FontName := raw;
    Include(AStyle.Present, tpFontName);
  end
  else if prop = 'font-size' then
  begin
    AStyle.FontSize := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpFontSize);
  end
  else if prop = 'font-weight' then
  begin
    if LowerCase(raw) = 'bold' then
      AStyle.FontWeight := 700
    else if LowerCase(raw) = 'normal' then
      AStyle.FontWeight := 400
    else
      AStyle.FontWeight := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpFontWeight);
  end
  else if prop = 'opacity' then
  begin
    AStyle.Opacity := TyEvalFloat(raw, Vars);
    Include(AStyle.Present, tpOpacity);
  end
  else
    Result := False;
end;

constructor TTyStyleModel.Create;
begin
  inherited Create;
  FRules := TFPList.Create;
  FVars := TStringList.Create;
end;

destructor TTyStyleModel.Destroy;
begin
  Clear;
  FRules.Free;
  FVars.Free;
  inherited Destroy;
end;

procedure TTyStyleModel.Clear;
var i: Integer;
begin
  for i := 0 to FRules.Count - 1 do
    TObject(FRules[i]).Free;
  FRules.Clear;
  FVars.Clear;
end;

procedure TTyStyleModel.AddEntry(const ATypeName, AVariant: string; AHasState: Boolean;
  AState: TTyState; const AStyle: TTyStyleSet);
var e: TTyStyleRuleEntry;
begin
  e := TTyStyleRuleEntry.Create;
  e.TypeName := ATypeName;
  e.Variant := AVariant;
  e.HasState := AHasState;
  e.State := AState;
  e.Style := AStyle;
  FRules.Add(e);
end;

function TTyStyleModel.FindStyle(const ATypeName, AVariant: string; AHasState: Boolean;
  AState: TTyState; out AStyle: TTyStyleSet): Boolean;
var
  i: Integer;
  e: TTyStyleRuleEntry;
begin
  Result := False;
  AStyle := EmptyStyleSet;
  for i := 0 to FRules.Count - 1 do
  begin
    e := TTyStyleRuleEntry(FRules[i]);
    if SameText(e.TypeName, ATypeName) and SameText(e.Variant, AVariant)
       and (e.HasState = AHasState) and ((not AHasState) or (e.State = AState)) then
    begin
      AStyle := e.Style;
      Result := True;
      Exit;
    end;
  end;
end;

procedure TTyStyleModel.LoadFromCss(const ASource: string);
begin
  // implemented in Task .4
  Clear;
end;

procedure TTyStyleModel.LoadFromFile(const AFileName: string);
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFileName);
    LoadFromCss(sl.Text);
  finally
    sl.Free;
  end;
end;

function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
begin
  // implemented in Task .5
  Result := EmptyStyleSet;
end;

end.
