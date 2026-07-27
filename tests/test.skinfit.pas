unit test.skinfit;
{$mode objfpc}{$H+}
{ Guards the examples against SKIN-INDUCED text clipping.

  A skin may legitimately change a control's font (family, size, weight) and its padding:
  `xp` asks for  TyButton { padding: 5px 12px }  where the default asks for  6px, i.e. 24px
  of horizontal padding instead of 12. So a control whose Width was hand-set to fit the
  default skin clips its caption the moment the user picks another one -- which is exactly
  what happened, on 36 controls, and is invisible until somebody switches skin and looks.

  The same mechanism bites cross-platform: a different default font measures the same string
  differently, and a hand-set Width has no way to absorb it.

  The rule this asserts: a captioned control in an example either
    (a) sets AutoSize = True, and sizes itself under whatever skin is loaded, or
    (b) is wide enough for the WIDEST skin, not merely for the default one.

  The comparison is relative on purpose. An absolute "needed width" cannot be exact from
  outside the control -- a check box also reserves an indicator, a dropdown an arrow -- but
  those addends do not vary between skins, and the skin-to-skin delta is what breaks layouts.
  So a control is only reported when it fits under `default` and stops fitting under another
  skin: the fixed overhead cancels out of that comparison. }
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel,
  tyControls.Controller, tyControls.BuiltinThemes;
type
  TSkinFitTest = class(TTestCase)
  published
    procedure TestNoExampleCaptionClipsUnderAnySkin;
  end;
implementation

type
  TCap = record
    Example, Name, Key, Caption: string;
    Width: Integer;
    AutoSize: Boolean;
  end;

{ The classes this guard measures, and the theme key each resolves. Deliberately a short
  explicit list rather than anything derived: these are the controls whose visible width IS
  their caption. Adding one is a single line here. }
function KeyOfClass(const ACls: string): string;
begin
  if      ACls = 'TTyButton'               then Result := 'TyButton'
  else if ACls = 'TTySpeedButton'          then Result := 'TyButton'
  else if ACls = 'TTyGlyphContainerButton' then Result := 'TyButton'
  else if ACls = 'TTyDropDownButton'       then Result := 'TyButton'
  else if ACls = 'TTyMenuButton'           then Result := 'TyButton'
  else if ACls = 'TTyColorButton'          then Result := 'TyButton'
  else if ACls = 'TTyCheckBox'             then Result := 'TyCheckBox'
  else if ACls = 'TTyRadioButton'          then Result := 'TyRadioButton'
  else if ACls = 'TTyToggleSwitch'         then Result := 'TyToggleSwitch'
  else if ACls = 'TTyLabel'                then Result := 'TyLabel'
  else Result := '';
end;

function ExamplesDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples' + PathDelim;
end;

function Unquote(const S: string): string;
begin
  Result := S;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''',
      [rfReplaceAll]);
end;

{ Collects every captioned control of a guarded class from one .lfm.
  `item ... end` blocks inside a collection close with `end` too, so they have to be pushed
  as well or their `end` pops a real object and everything after it is attributed wrongly. }
procedure ScanLfm(const APath, AExample: string; var ACaps: array of TCap;
  var ACount: Integer);
type
  TFrame = record Cls, Nm, Cap: string; W: Integer; Auto: Boolean; end;
var
  L: TStringList;
  stack: array[0..63] of TFrame;
  sp, i, p: Integer;
  s, lhs, rhs: string;

  procedure Flush(const F: TFrame);
  begin
    if (F.Cap = '') or (F.W <= 0) or (KeyOfClass(F.Cls) = '') then Exit;
    if ACount > High(ACaps) then Exit;
    ACaps[ACount].Example  := AExample;
    ACaps[ACount].Name     := F.Nm;
    ACaps[ACount].Key      := KeyOfClass(F.Cls);
    ACaps[ACount].Caption  := F.Cap;
    ACaps[ACount].Width    := F.W;
    ACaps[ACount].AutoSize := F.Auto;
    Inc(ACount);
  end;

begin
  L := TStringList.Create;
  try
    L.LoadFromFile(APath);
    sp := -1;
    for i := 0 to L.Count - 1 do
    begin
      s := Trim(L[i]);
      if s = '' then Continue;
      if (Copy(s, 1, 7) = 'object ') or (Copy(s, 1, 10) = 'inherited ')
         or (Copy(s, 1, 7) = 'inline ') then
      begin
        if sp >= High(stack) then Continue;
        Inc(sp);
        stack[sp].Nm := ''; stack[sp].Cls := ''; stack[sp].Cap := '';
        stack[sp].W := 0;   stack[sp].Auto := False;
        p := Pos(':', s);
        if p > 0 then
        begin
          stack[sp].Nm  := Trim(Copy(s, Pos(' ', s) + 1, p - Pos(' ', s) - 1));
          stack[sp].Cls := Trim(Copy(s, p + 1, MaxInt));
        end;
        Continue;
      end;
      if (s = 'item') or (Copy(s, 1, 5) = 'item ') then
      begin
        if sp < High(stack) then
        begin
          Inc(sp);
          stack[sp].Cls := '';  stack[sp].Cap := '';
          stack[sp].W := 0;     stack[sp].Auto := False;
        end;
        Continue;
      end;
      if s = 'end' then
      begin
        if sp >= 0 then begin Flush(stack[sp]); Dec(sp); end;
        Continue;
      end;
      if sp < 0 then Continue;
      p := Pos('=', s);
      if p = 0 then Continue;
      lhs := Trim(Copy(s, 1, p - 1));
      rhs := Trim(Copy(s, p + 1, MaxInt));
      if      lhs = 'Caption'  then stack[sp].Cap  := Unquote(rhs)
      else if lhs = 'Width'    then stack[sp].W    := StrToIntDef(rhs, 0)
      else if lhs = 'AutoSize' then stack[sp].Auto := SameText(rhs, 'True');
    end;
  finally
    L.Free;
  end;
end;

procedure TSkinFitTest.TestNoExampleCaptionClipsUnderAnySkin;
var
  caps: array[0..4095] of TCap;
  n, i, t, m, need: Integer;
  baseW, worstW, worstIdx: array of Integer;
  dirs, files: TStringList;
  sr: TSearchRec;
  ctl: TTyStyleController;
  names: TStringArray;
  bmp: TBitmap;
  pnt: TTyPainter;
  S: TTyStyleSet;
  sz: TSize;
  bad: TStringList;

  function NeededW: Integer;
  begin
    S := ctl.Model.ResolveStyle(caps[i].Key, '', []);
    if tpFontSize in S.Present then
      sz := pnt.MeasureText(caps[i].Caption, S.FontName, S.FontSize, S.FontWeight)
    else
      sz := pnt.MeasureText(caps[i].Caption, S.FontName, 9, S.FontWeight);
    Result := sz.cx;
    if tpPadding in S.Present then
      Result := Result + S.Padding.Left + S.Padding.Right;
  end;

begin
  n := 0;
  dirs := TStringList.Create;
  files := TStringList.Create;
  bad := TStringList.Create;
  try
    if FindFirst(ExamplesDir + '*', faDirectory, sr) = 0 then
    begin
      repeat
        if (sr.Name <> '.') and (sr.Name <> '..') and ((sr.Attr and faDirectory) <> 0) then
          dirs.Add(sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    AssertTrue('the examples directory was found', dirs.Count > 0);

    for i := 0 to dirs.Count - 1 do
      if FindFirst(ExamplesDir + dirs[i] + PathDelim + '*.lfm', faAnyFile, sr) = 0 then
      begin
        repeat
          ScanLfm(ExamplesDir + dirs[i] + PathDelim + sr.Name, dirs[i], caps, n);
        until FindNext(sr) <> 0;
        FindClose(sr);
      end;
    AssertTrue('captioned controls were found to measure', n > 0);

    bmp := TBitmap.Create;
    bmp.SetSize(8, 8);
    pnt := TTyPainter.Create;
    pnt.BeginPaint(bmp.Canvas, Rect(0, 0, 8, 8), 96);
    TyRegisterBuiltinThemes;
    names := TyBuiltinThemeNames;
    ctl := TTyStyleController.Create(nil);
    try
      { Setting ThemeName re-parses the whole skin, so the THEME loop has to be the outer
        one. The natural nesting -- per control, walk the skins -- reloads a theme for every
        control and the test never finishes. }
      SetLength(baseW, n);
      SetLength(worstW, n);
      SetLength(worstIdx, n);
      ctl.ThemeName := 'default';
      ctl.Mode := 'light';
      for i := 0 to n - 1 do
      begin
        baseW[i]   := NeededW;
        worstW[i]  := baseW[i];
        worstIdx[i] := -1;
      end;
      for t := 0 to High(names) do
        for m := 0 to 1 do
        begin
          ctl.ThemeName := names[t];
          if m = 0 then ctl.Mode := 'light' else ctl.Mode := 'dark';
          for i := 0 to n - 1 do
          begin
            need := NeededW;
            if need > worstW[i] then begin worstW[i] := need; worstIdx[i] := t; end;
          end;
        end;

      for i := 0 to n - 1 do
      begin
        if caps[i].AutoSize then Continue;        // sizes itself: immune by construction
        if baseW[i] > caps[i].Width then Continue; // already tight by design, not skin-induced
        if worstW[i] > caps[i].Width then
          bad.Add(Format('%s.%s (%s): Width=%d, needs %d under "%s"',
            [caps[i].Example, caps[i].Name, caps[i].Key, caps[i].Width, worstW[i],
             names[worstIdx[i]]]));
      end;
    finally
      ctl.Free;
      pnt.EndPaint;
      pnt.Free;
      bmp.Free;
    end;

    if bad.Count > 0 then
      Fail(Format('%d example control(s) fit under the default skin but clip under another.'
        + ' Set AutoSize = True on them, or widen them to the worst skin:'#10'%s',
        [bad.Count, bad.Text]));
  finally
    bad.Free;
    files.Free;
    dirs.Free;
  end;
end;

initialization
  RegisterTest(TSkinFitTest);
end.
