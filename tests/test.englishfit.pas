unit test.englishfit;
{$mode objfpc}{$H+}
{ Guards the examples against ENGLISH-caption clipping under the DEFAULT skin.

  Sibling to test.skinfit, but the opposite axis. skinfit asks "does a caption that
  fits the default skin still fit the WIDEST other skin?" -- a relative, skin-to-skin
  question that cancels out the fixed overhead (a check box's indicator, a dropdown's
  arrow) it cannot measure from outside. This test asks the ABSOLUTE question skinfit
  deliberately skips: "does the caption's own text overflow the control's hand-set
  Width in English, under the default skin?"

  It exists because the examples were authored with Chinese captions and hand-set
  widths, then re-captioned to English (with a zh_CN.po mapping each English msgid
  back to Chinese) WITHOUT re-sizing -- so the longer English text overruns a width
  that was tight for the CJK original.

  The measure is a LOWER BOUND on purpose: it counts only the caption text (mnemonic
  '&' stripped) plus the theme's horizontal padding. A check box's indicator, a
  dropdown's arrow and a glyph button's glyph all ADD width, so a control this test
  flags is overflowing for EVERY class -- there are no false positives from the
  overhead it omits. It can under-report (a caption that fits on text alone but not
  once the indicator is added); those are caught by the visual pass, not here.

  Excluded, because they do not truncate:
    * AutoSize = True  -- the control grows to its caption.
    * TTyLabel WordWrap = True -- the text wraps to a second line instead of clipping. }
interface
uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel,
  tyControls.Controller, tyControls.BuiltinThemes;
type
  TEnglishFitTest = class(TTestCase)
  published
    procedure TestNoExampleCaptionClipsInEnglish;
  end;
implementation

type
  TCap = record
    Example, Name, Key, Caption: string;
    Width, Height: Integer;
    AutoSize, WordWrap: Boolean;
  end;

{ Same guarded set as test.skinfit: the controls whose visible width IS their caption. }
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

{ Drop the accelerator marker so the width matches what is drawn: '&&' is a literal
  ampersand, a lone '&' underlines the next char and takes no space of its own. }
function StripAmp(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '&' then
    begin
      if (i < Length(S)) and (S[i + 1] = '&') then begin Result := Result + '&'; Inc(i, 2); end
      else Inc(i);
    end
    else begin Result := Result + S[i]; Inc(i); end;
  end;
end;

procedure ScanLfm(const APath, AExample: string; var ACaps: array of TCap;
  var ACount: Integer);
type
  TFrame = record Cls, Nm, Cap: string; W, H: Integer; Auto, WW: Boolean; end;
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
    ACaps[ACount].Height   := F.H;
    ACaps[ACount].AutoSize := F.Auto;
    ACaps[ACount].WordWrap := F.WW;
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
        stack[sp].W := 0;   stack[sp].H := 0;   stack[sp].Auto := False; stack[sp].WW := False;
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
          stack[sp].W := 0;     stack[sp].H := 0;   stack[sp].Auto := False; stack[sp].WW := False;
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
      else if lhs = 'Height'   then stack[sp].H    := StrToIntDef(rhs, 0)
      else if lhs = 'AutoSize' then stack[sp].Auto := SameText(rhs, 'True')
      else if lhs = 'WordWrap' then stack[sp].WW   := SameText(rhs, 'True');
    end;
  finally
    L.Free;
  end;
end;

procedure TEnglishFitTest.TestNoExampleCaptionClipsInEnglish;
var
  caps: array[0..4095] of TCap;
  n, i, need: Integer;
  dirs: TStringList;
  sr: TSearchRec;
  ctl: TTyStyleController;
  bmp: TBitmap;
  pnt: TTyPainter;
  S: TTyStyleSet;
  sz: TSize;
  bad: TStringList;
  txt: string;
begin
  n := 0;
  dirs := TStringList.Create;
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
    ctl := TTyStyleController.Create(nil);
    try
      ctl.ThemeName := 'default';
      ctl.Mode := 'light';
      for i := 0 to n - 1 do
      begin
        if caps[i].AutoSize then Continue;                       // grows to its caption
        if (caps[i].Key = 'TyLabel') and caps[i].WordWrap then Continue;  // wraps, not clips
        txt := StripAmp(caps[i].Caption);
        S := ctl.Model.ResolveStyle(caps[i].Key, '', []);
        if tpFontSize in S.Present then
          sz := pnt.MeasureText(txt, S.FontName, S.FontSize, S.FontWeight)
        else
          sz := pnt.MeasureText(txt, S.FontName, 9, S.FontWeight);
        need := sz.cx;
        if tpPadding in S.Present then
          need := need + S.Padding.Left + S.Padding.Right;
        { A check box / radio reserves an indicator box + gap to the LEFT of the caption
          (CalculatePreferredSize = padding + box + gap + text), so the caption clips when
          text + padding + indicator exceeds the Width. A button/label has no such addend
          -- its visible width IS text + padding -- so only these two classes get it. }
        if caps[i].Key = 'TyCheckBox' then
          need := need + ctl.Metric('--checkbox-size', TyCheckBoxBox) + ctl.Metric('--checkbox-gap', TyCheckBoxGap)
        else if caps[i].Key = 'TyRadioButton' then
          need := need + ctl.Metric('--radio-size', TyCheckBoxBox) + ctl.Metric('--radio-gap', TyCheckBoxGap);
        if need > caps[i].Width then
          bad.Add(Format('%s | %s.%s (%s) Width=%d needs>=%d | "%s"',
            [caps[i].Example, caps[i].Example, caps[i].Name, caps[i].Key,
             caps[i].Width, need, caps[i].Caption]));
      end;
    finally
      ctl.Free;
      pnt.EndPaint;
      pnt.Free;
      bmp.Free;
    end;

    if bad.Count > 0 then
    begin
      bad.Sort;
      Fail(Format('%d example caption(s) overflow their Width in English (default skin).'
        + ' Shorten the English caption (and sync the zh_CN.po msgid) or widen the control:'
        + #10'%s', [bad.Count, bad.Text]));
    end;
  finally
    bad.Free;
    dirs.Free;
  end;
end;

initialization
  RegisterTest(TEnglishFitTest);
end.
