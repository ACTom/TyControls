unit tyControls.Terminal.Keyboard;
{$mode objfpc}{$H+}

{ Keys, paste text and the third-level-shift test, turned into the bytes a terminal
  program expects. Pure functions: no control, no Forms, no Controls -- the terminal
  view (tyControls.Terminal) calls them from KeyDown / UTF8KeyPress.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39:
    src/common/input/Keyboard.ts            evaluateKeyboardEvent, KEYCODE_KEY_MAPPINGS
    src/browser/Clipboard.ts:13-29          prepareTextForTerminal, bracketTextForPaste
    src/browser/CoreBrowserTerminal.ts:937-948   _isThirdLevelShift

    Keyboard.ts:   Copyright (c) 2014 The xterm.js authors. All rights reserved.
                   Copyright (c) 2012-2013, Christopher Jeffrey (MIT License)
    Clipboard.ts:  Copyright (c) 2016 The xterm.js authors. All rights reserved.
    and the repository's LICENSE:
      Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
      Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
      Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
  MIT; the full text is in THIRD-PARTY-NOTICES.md.

  WHAT DIFFERS IN SHAPE (never in result):

  - Key and Code are the browser's KeyboardEvent.key / .code as UTF-8. Where upstream
    asks key.length it means UTF-16 units, so that is what TyTermJsLength counts: an
    astral character is 2, an e with an acute accent 1.
  - AltGraph stands for getModifierState('AltGraph') (LCL: ssAltGr).
  - LCL gives a virtual key and a shift state, not a key name: TyTerminalKeyEventFromLCL
    fills Key and Code from a US-layout table. That table is written once, in
    tools/terminal-oracle/keyboard-cases.js, and the tests hold this one to it row by
    row (the fixture carries it). Characters of other layouts never come through the
    table -- they arrive in UTF8KeyPress.
  - Upstream does not look at the application keypad mode (DECKPAM): the keypad's
    digits and operators send their characters in either mode. So does this port. }

interface

uses
  SysUtils, Classes, LCLType;

type
  { KeyboardEvent's four modifiers + keyCode + key + code (common/Types.ts:55-65) }
  TTyTerminalKeyEvent = record
    KeyCode: Word;
    Key, Code: string;
    Shift, Ctrl, Alt, Meta: Boolean;
    AltGraph: Boolean;                    { getModifierState('AltGraph'); LCL ssAltGr }
  end;
  { Ordinal = upstream's KeyboardResultType (common/Types.ts:71-76): SEND_KEY 0,
    SELECT_ALL 1, PAGE_UP 2, PAGE_DOWN 3 }
  TTyTerminalKeyResultKind = (tkrSendKey, tkrSelectAll, tkrPageUp, tkrPageDown);
  TTyTerminalKeyResult = record
    Kind: TTyTerminalKeyResultKind;
    Cancel: Boolean;
    Key: RawByteString;                   { '' = upstream's undefined: nothing to send }
  end;

const
  TyTerminalIsMac = {$IFDEF DARWIN}True{$ELSE}False{$ENDIF};         { the platform, not the widgetset }
  TyTerminalIsWindows = {$IFDEF MSWINDOWS}True{$ELSE}False{$ENDIF};
  { The key code an input method's keydown carries on Windows (VK_PROCESSKEY there).
    LCLType's VK_PROCESSKEY is $E7 -- Windows' VK_PACKET -- so it is not this one. }
  TyVkImeProcess = $E5;

{ The VK and shift state LCL hands KeyDown, as the browser event a US keyboard would
  make: Key / Code from the layout table (the shifted column under ssShift), the five
  modifiers from ssShift / ssCtrl / ssAlt / ssMeta / ssAltGr. A VK outside the table
  gets 'Unidentified' and ''. }
function TyTerminalKeyEventFromLCL(AKey: Word; AShift: TShiftState): TTyTerminalKeyEvent;
{ evaluateKeyboardEvent, Keyboard.ts:38-380, branch by branch. }
function TyTerminalEvaluateKey(const AEvent: TTyTerminalKeyEvent; AApplicationCursor, AIsMac,
  AMacOptionIsMeta: Boolean): TTyTerminalKeyResult;
{ _isThirdLevelShift, CoreBrowserTerminal.ts:937-948: macOS Option (unless it is Meta),
  Windows Ctrl+Alt, Windows AltGraph -- none with Meta; on a keydown (AKeyPress False)
  only for a key code of 0 or above 47 (not arrows, paging, Backspace ...). }
function TyTerminalIsThirdLevelShift(const AEvent: TTyTerminalKeyEvent; AIsMac, AIsWindows,
  AMacOptionIsMeta, AKeyPress: Boolean): Boolean;
{ prepareTextForTerminal then bracketTextForPaste (Clipboard.ts:13-29), the order
  paste() applies them: every CR LF and lone LF becomes CR (a lone CR stays); under
  bracketed paste every ESC becomes U+241B and the text goes between ESC[200~ and
  ESC[201~. UTF-8 in, UTF-8 out, not validated. }
function TyTerminalPrepareTextForPaste(const AText: string; ABracketed: Boolean): RawByteString;
{ FOR THE TESTS: the layout table, row by row (ARow 0..TyTerminalLayoutCount - 1). }
function TyTerminalLayoutCount: Integer;
procedure TyTerminalLayoutRow(ARow: Integer; out AVk: Word; out AKey, AShiftedKey, ACode: string);
{ String.prototype.length of a UTF-8 string: its UTF-16 units. }
function TyTermJsLength(const S: string): Integer;

implementation

const
  { C0, common/data/EscapeSequences.ts (the few Keyboard.ts uses) }
  C0_NUL = #0;
  C0_ETX = #3;
  C0_BS = #8;
  C0_HT = #9;
  C0_CR = #13;
  C0_ESC = #27;
  C0_FS = #28;
  C0_GS = #29;
  C0_RS = #30;
  C0_US = #31;
  C0_DEL = #127;

type
  TTyLayoutRow = record
    Vk: Word;
    Key, Shifted, Code: string;
  end;

const
  { The US layout (keyboard-cases.js US_LAYOUT; the tests compare the two). Letters,
    the keypad digits and F1-F12 are made by LayoutRowOf; everything else is here,
    in VK order. The digit and symbol pairs are upstream's KEYCODE_KEY_MAPPINGS
    (Keyboard.ts:11-36). }
  LayoutFixed: array[0..45] of TTyLayoutRow = (
    (Vk: 8; Key: 'Backspace'; Shifted: 'Backspace'; Code: 'Backspace'),
    (Vk: 9; Key: 'Tab'; Shifted: 'Tab'; Code: 'Tab'),
    (Vk: 13; Key: 'Enter'; Shifted: 'Enter'; Code: 'Enter'),
    (Vk: 16; Key: 'Shift'; Shifted: 'Shift'; Code: 'ShiftLeft'),
    (Vk: 17; Key: 'Control'; Shifted: 'Control'; Code: 'ControlLeft'),
    (Vk: 18; Key: 'Alt'; Shifted: 'Alt'; Code: 'AltLeft'),
    (Vk: 20; Key: 'CapsLock'; Shifted: 'CapsLock'; Code: 'CapsLock'),
    (Vk: 27; Key: 'Escape'; Shifted: 'Escape'; Code: 'Escape'),
    (Vk: 32; Key: ' '; Shifted: ' '; Code: 'Space'),
    (Vk: 33; Key: 'PageUp'; Shifted: 'PageUp'; Code: 'PageUp'),
    (Vk: 34; Key: 'PageDown'; Shifted: 'PageDown'; Code: 'PageDown'),
    (Vk: 35; Key: 'End'; Shifted: 'End'; Code: 'End'),
    (Vk: 36; Key: 'Home'; Shifted: 'Home'; Code: 'Home'),
    (Vk: 37; Key: 'ArrowLeft'; Shifted: 'ArrowLeft'; Code: 'ArrowLeft'),
    (Vk: 38; Key: 'ArrowUp'; Shifted: 'ArrowUp'; Code: 'ArrowUp'),
    (Vk: 39; Key: 'ArrowRight'; Shifted: 'ArrowRight'; Code: 'ArrowRight'),
    (Vk: 40; Key: 'ArrowDown'; Shifted: 'ArrowDown'; Code: 'ArrowDown'),
    (Vk: 45; Key: 'Insert'; Shifted: 'Insert'; Code: 'Insert'),
    (Vk: 46; Key: 'Delete'; Shifted: 'Delete'; Code: 'Delete'),
    (Vk: 48; Key: '0'; Shifted: ')'; Code: 'Digit0'),
    (Vk: 49; Key: '1'; Shifted: '!'; Code: 'Digit1'),
    (Vk: 50; Key: '2'; Shifted: '@'; Code: 'Digit2'),
    (Vk: 51; Key: '3'; Shifted: '#'; Code: 'Digit3'),
    (Vk: 52; Key: '4'; Shifted: '$'; Code: 'Digit4'),
    (Vk: 53; Key: '5'; Shifted: '%'; Code: 'Digit5'),
    (Vk: 54; Key: '6'; Shifted: '^'; Code: 'Digit6'),
    (Vk: 55; Key: '7'; Shifted: '&'; Code: 'Digit7'),
    (Vk: 56; Key: '8'; Shifted: '*'; Code: 'Digit8'),
    (Vk: 57; Key: '9'; Shifted: '('; Code: 'Digit9'),
    (Vk: 91; Key: 'Meta'; Shifted: 'Meta'; Code: 'MetaLeft'),
    (Vk: 93; Key: 'ContextMenu'; Shifted: 'ContextMenu'; Code: 'ContextMenu'),
    (Vk: 106; Key: '*'; Shifted: '*'; Code: 'NumpadMultiply'),
    (Vk: 107; Key: '+'; Shifted: '+'; Code: 'NumpadAdd'),
    (Vk: 109; Key: '-'; Shifted: '-'; Code: 'NumpadSubtract'),
    (Vk: 110; Key: '.'; Shifted: '.'; Code: 'NumpadDecimal'),
    (Vk: 111; Key: '/'; Shifted: '/'; Code: 'NumpadDivide'),
    (Vk: 144; Key: 'NumLock'; Shifted: 'NumLock'; Code: 'NumLock'),
    (Vk: 186; Key: ';'; Shifted: ':'; Code: 'Semicolon'),
    (Vk: 187; Key: '='; Shifted: '+'; Code: 'Equal'),
    (Vk: 188; Key: ','; Shifted: '<'; Code: 'Comma'),
    (Vk: 189; Key: '-'; Shifted: '_'; Code: 'Minus'),
    (Vk: 190; Key: '.'; Shifted: '>'; Code: 'Period'),
    (Vk: 191; Key: '/'; Shifted: '?'; Code: 'Slash'),
    (Vk: 192; Key: '`'; Shifted: '~'; Code: 'Backquote'),
    (Vk: 219; Key: '['; Shifted: '{'; Code: 'BracketLeft'),
    (Vk: 220; Key: '\'; Shifted: '|'; Code: 'Backslash')
  );
  LayoutFixedTail: array[0..2] of TTyLayoutRow = (
    (Vk: 221; Key: ']'; Shifted: '}'; Code: 'BracketRight'),
    (Vk: 222; Key: ''''; Shifted: '"'; Code: 'Quote'),
    (Vk: 229; Key: 'Process'; Shifted: 'Process'; Code: '')
  );

{ The row of AVk, False when the table has none. }
function LayoutRowOf(AVk: Word; out ARow: TTyLayoutRow): Boolean;
var
  i: Integer;
begin
  Result := True;
  ARow.Vk := AVk;
  case AVk of
    65..90:
      begin
        ARow.Key := Chr(AVk + 32);
        ARow.Shifted := Chr(AVk);
        ARow.Code := 'Key' + Chr(AVk);
        Exit;
      end;
    96..105:
      begin
        ARow.Key := Chr(Ord('0') + AVk - 96);
        ARow.Shifted := ARow.Key;
        ARow.Code := 'Numpad' + ARow.Key;
        Exit;
      end;
    112..123:
      begin
        ARow.Key := 'F' + IntToStr(AVk - 111);
        ARow.Shifted := ARow.Key;
        ARow.Code := ARow.Key;
        Exit;
      end;
  end;
  for i := 0 to High(LayoutFixed) do
    if LayoutFixed[i].Vk = AVk then
    begin
      ARow := LayoutFixed[i];
      Exit;
    end;
  for i := 0 to High(LayoutFixedTail) do
    if LayoutFixedTail[i].Vk = AVk then
    begin
      ARow := LayoutFixedTail[i];
      Exit;
    end;
  Result := False;
end;

function TyTerminalLayoutCount: Integer;
var
  vk: Integer;
  row: TTyLayoutRow;
begin
  Result := 0;
  for vk := 0 to 255 do
    if LayoutRowOf(vk, row) then Inc(Result);
end;

procedure TyTerminalLayoutRow(ARow: Integer; out AVk: Word; out AKey, AShiftedKey, ACode: string);
var
  vk, n: Integer;
  row: TTyLayoutRow;
begin
  n := 0;
  for vk := 0 to 255 do
    if LayoutRowOf(vk, row) then
    begin
      if n = ARow then
      begin
        AVk := row.Vk;
        AKey := row.Key;
        AShiftedKey := row.Shifted;
        ACode := row.Code;
        Exit;
      end;
      Inc(n);
    end;
  raise EArgumentOutOfRangeException.CreateFmt('layout row %d of %d', [ARow, n]);
end;

function TyTerminalKeyEventFromLCL(AKey: Word; AShift: TShiftState): TTyTerminalKeyEvent;
var
  row: TTyLayoutRow;
begin
  Result := Default(TTyTerminalKeyEvent);
  Result.KeyCode := AKey;
  Result.Shift := ssShift in AShift;
  Result.Ctrl := ssCtrl in AShift;
  Result.Alt := ssAlt in AShift;
  Result.Meta := ssMeta in AShift;
  Result.AltGraph := ssAltGr in AShift;
  if LayoutRowOf(AKey, row) then
  begin
    if Result.Shift then Result.Key := row.Shifted else Result.Key := row.Key;
    Result.Code := row.Code;
  end
  else
  begin
    Result.Key := 'Unidentified';
    Result.Code := '';
  end;
end;

function TyTermJsLength(const S: string): Integer;
var
  i: Integer;
  b: Byte;
begin
  { A lead byte starts a code point; a four-byte lead (F0..F7) is two UTF-16 units. }
  Result := 0;
  for i := 1 to Length(S) do
  begin
    b := Ord(S[i]);
    if (b and $C0) <> $80 then
    begin
      Inc(Result);
      if b >= $F0 then Inc(Result);
    end;
  end;
end;

{ ASCII-only case changes: every string they meet here is ASCII (Keyboard.ts:341-356). }
function AsciiUpper(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] in ['a'..'z'] then Result[i] := Chr(Ord(Result[i]) - 32);
end;

function AsciiLower(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] in ['A'..'Z'] then Result[i] := Chr(Ord(Result[i]) + 32);
end;

function TyTerminalEvaluateKey(const AEvent: TTyTerminalKeyEvent; AApplicationCursor, AIsMac,
  AMacOptionIsMeta: Boolean): TTyTerminalKeyResult;
var
  modifiers: Integer;
  ev: TTyTerminalKeyEvent;
  mapped, keyString: string;
  row: TTyLayoutRow;
  keyCode: Integer;

  { '1;' + (modifiers + 1) + ASuffix, the shape most keys share }
  function Mod1(const ASuffix: string): RawByteString;
  begin
    Result := C0_ESC + '[1;' + IntToStr(modifiers + 1) + ASuffix;
  end;

  { the F5..F12 shape: ESC [ n ~ or ESC [ n ; m ~ }
  function Tilde(const ANum: string): RawByteString;
  begin
    if modifiers <> 0 then
      Result := C0_ESC + '[' + ANum + ';' + IntToStr(modifiers + 1) + '~'
    else
      Result := C0_ESC + '[' + ANum + '~';
  end;

  { F1..F4: ESC O x, or ESC [ 1 ; m x }
  function SS3(const ALetter: string): RawByteString;
  begin
    if modifiers <> 0 then
      Result := Mod1(ALetter)
    else
      Result := C0_ESC + 'O' + ALetter;
  end;

  { the arrows, Home and End: modifiers, else application cursor, else CSI }
  function Cursor(const ALetter: string): RawByteString;
  begin
    if modifiers <> 0 then
      Result := Mod1(ALetter)
    else if AApplicationCursor then
      Result := C0_ESC + 'O' + ALetter
    else
      Result := C0_ESC + '[' + ALetter;
  end;

begin
  ev := AEvent;
  Result.Kind := tkrSendKey;
  Result.Cancel := False;
  Result.Key := '';
  modifiers := Ord(ev.Shift) or (Ord(ev.Alt) shl 1) or (Ord(ev.Ctrl) shl 2) or (Ord(ev.Meta) shl 3);
  case ev.KeyCode of
    0:
      begin
        { Keyboard.ts:54-83 }
        if ev.Key = 'UIKeyInputUpArrow' then
        begin
          if AApplicationCursor then Result.Key := C0_ESC + 'OA' else Result.Key := C0_ESC + '[A';
        end
        else if ev.Key = 'UIKeyInputLeftArrow' then
        begin
          if AApplicationCursor then Result.Key := C0_ESC + 'OD' else Result.Key := C0_ESC + '[D';
        end
        else if ev.Key = 'UIKeyInputRightArrow' then
        begin
          if AApplicationCursor then Result.Key := C0_ESC + 'OC' else Result.Key := C0_ESC + '[C';
        end
        else if ev.Key = 'UIKeyInputDownArrow' then
        begin
          if AApplicationCursor then Result.Key := C0_ESC + 'OB' else Result.Key := C0_ESC + '[B';
        end;
      end;
    8:
      begin
        { backspace, :84-90 -- ^H or ^? }
        if ev.Ctrl then Result.Key := C0_BS else Result.Key := C0_DEL;
        if ev.Alt then Result.Key := C0_ESC + Result.Key;
      end;
    9:
      begin
        { tab, :91-99 }
        if ev.Shift then
          Result.Key := C0_ESC + '[Z'
        else
        begin
          Result.Key := C0_HT;
          Result.Cancel := True;
        end;
      end;
    13:
      begin
        { return / enter, :100-110 (key 'c' + ctrl: Safari's Ctrl+C on a hardware keyboard) }
        if (ev.Key = 'c') and ev.Ctrl then
          Result.Key := C0_ETX
        else if ev.Alt then
          Result.Key := C0_ESC + C0_CR
        else
          Result.Key := C0_CR;
        Result.Cancel := True;
      end;
    27:
      begin
        { escape, :111-118 }
        Result.Key := C0_ESC;
        if ev.Alt then Result.Key := C0_ESC + C0_ESC;
        Result.Cancel := True;
      end;
    37:
      { left arrow, :119-131; Meta + arrow sends nothing, before the modifiers are looked at }
      if not ev.Meta then Result.Key := Cursor('D');
    39:
      { right arrow, :132-144 }
      if not ev.Meta then Result.Key := Cursor('C');
    38:
      { up arrow, :145-157 }
      if not ev.Meta then Result.Key := Cursor('A');
    40:
      { down arrow, :158-170 }
      if not ev.Meta then Result.Key := Cursor('B');
    45:
      { insert, :171-178; Shift / Ctrl + Insert are left for copy and paste }
      if not ev.Shift and not ev.Ctrl then Result.Key := C0_ESC + '[2~';
    46:
      { delete, :179-186 }
      if modifiers <> 0 then
        Result.Key := C0_ESC + '[3;' + IntToStr(modifiers + 1) + '~'
      else
        Result.Key := C0_ESC + '[3~';
    36:
      { home, :187-196 }
      Result.Key := Cursor('H');
    35:
      { end, :197-206 }
      Result.Key := Cursor('F');
    33:
      { page up, :207-216: Shift pages locally; only Ctrl adds a modifier code }
      if ev.Shift then
        Result.Kind := tkrPageUp
      else if ev.Ctrl then
        Result.Key := C0_ESC + '[5;' + IntToStr(modifiers + 1) + '~'
      else
        Result.Key := C0_ESC + '[5~';
    34:
      { page down, :217-226 }
      if ev.Shift then
        Result.Kind := tkrPageDown
      else if ev.Ctrl then
        Result.Key := C0_ESC + '[6;' + IntToStr(modifiers + 1) + '~'
      else
        Result.Key := C0_ESC + '[6~';
    112: Result.Key := SS3('P');            { F1, :227-234 }
    113: Result.Key := SS3('Q');
    114: Result.Key := SS3('R');
    115: Result.Key := SS3('S');
    116: Result.Key := Tilde('15');         { F5, :256-262 }
    117: Result.Key := Tilde('17');
    118: Result.Key := Tilde('18');
    119: Result.Key := Tilde('19');
    120: Result.Key := Tilde('20');
    121: Result.Key := Tilde('21');
    122: Result.Key := Tilde('23');
    123: Result.Key := Tilde('24');         { F12, :305-311 }
  else
    begin
      { a-z and space, :312-376 -- four else-ifs in upstream's order }
      keyCode := ev.KeyCode;
      if ev.Ctrl and not ev.Shift and not ev.Alt and not ev.Meta then
      begin
        if (keyCode >= 65) and (keyCode <= 90) then
          Result.Key := Chr(keyCode - 64)
        else if keyCode = 32 then
          Result.Key := C0_NUL
        else if (keyCode >= 51) and (keyCode <= 55) then
          { escape, file sep, group sep, record sep, unit sep }
          Result.Key := Chr(keyCode - 51 + 27)
        else if keyCode = 56 then
          Result.Key := C0_DEL
        else if ev.Key = '/' then
          Result.Key := C0_US                { issue 5457 }
        else if keyCode = 219 then
          Result.Key := C0_ESC
        else if keyCode = 220 then
          Result.Key := C0_FS
        else if keyCode = 221 then
          Result.Key := C0_GS;
      end
      else if ((not AIsMac) or AMacOptionIsMeta) and ev.Alt and not ev.Meta then
      begin
        { on macOS this is a third level shift when not macOptionIsMeta: ESC instead }
        mapped := '';
        if ((keyCode >= 48) and (keyCode <= 57)) or ((keyCode >= 186) and (keyCode <= 192))
          or ((keyCode >= 219) and (keyCode <= 222)) then
          if LayoutRowOf(keyCode, row) then
            if ev.Shift then mapped := row.Shifted else mapped := row.Key;
        if mapped <> '' then
          Result.Key := C0_ESC + mapped
        else if (keyCode >= 65) and (keyCode <= 90) then
        begin
          if ev.Ctrl then keyString := Chr(keyCode - 64) else keyString := Chr(keyCode + 32);
          if ev.Shift then keyString := AsciiUpper(keyString);
          Result.Key := C0_ESC + keyString;
        end
        else if keyCode = 32 then
        begin
          if ev.Ctrl then Result.Key := C0_ESC + C0_NUL else Result.Key := C0_ESC + ' ';
        end
        else if (ev.Key = 'Dead') and (Copy(ev.Code, 1, 3) = 'Key') then
        begin
          { issue 3725: Alt makes a dead key of some US letters (N, E, U) on macOS }
          keyString := Copy(ev.Code, 4, 1);
          if not ev.Shift then keyString := AsciiLower(keyString);
          Result.Key := C0_ESC + keyString;
          Result.Cancel := True;
        end;
      end
      else if AIsMac and not ev.Alt and not ev.Ctrl and not ev.Shift and ev.Meta then
      begin
        if keyCode = 65 then               { cmd + a }
          Result.Kind := tkrSelectAll;
      end
      else if (ev.Key <> '') and not ev.Ctrl and not ev.Alt and not ev.Meta and (keyCode >= 48)
        and (TyTermJsLength(ev.Key) = 1) then
        { only keys that make a single character: not NumLock, volume up ... }
        Result.Key := ev.Key
      else if (ev.Key <> '') and ev.Ctrl and ev.Shift then
      begin
        if ev.Code = 'Minus' then Result.Key := C0_US          { ^_ }
        else if ev.Code = 'Digit2' then Result.Key := C0_NUL   { ^@ }
        else if ev.Code = 'Digit6' then Result.Key := C0_RS;   { ^^ }
      end;
    end;
  end;
end;

function TyTerminalIsThirdLevelShift(const AEvent: TTyTerminalKeyEvent; AIsMac, AIsWindows,
  AMacOptionIsMeta, AKeyPress: Boolean): Boolean;
var
  third: Boolean;
begin
  third := (AIsMac and not AMacOptionIsMeta and AEvent.Alt and not AEvent.Ctrl and not AEvent.Meta)
    or (AIsWindows and AEvent.Alt and AEvent.Ctrl and not AEvent.Meta)
    or (AIsWindows and AEvent.AltGraph);
  if AKeyPress then
    Result := third
  else
    { not for arrows, paging, Home, Backspace ... on a keydown }
    Result := third and ((AEvent.KeyCode = 0) or (AEvent.KeyCode > 47));
end;

function TyTerminalPrepareTextForPaste(const AText: string; ABracketed: Boolean): RawByteString;
var
  i, n: Integer;
  s: RawByteString;
begin
  { /\r?\n/g -> \r: a CR LF or a lone LF becomes one CR, a lone CR stays }
  SetLength(s, Length(AText));
  n := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    if (AText[i] = #13) and (i < Length(AText)) and (AText[i + 1] = #10) then
    begin
      Inc(n);
      s[n] := #13;
      Inc(i, 2);
      Continue;
    end;
    Inc(n);
    if AText[i] = #10 then s[n] := #13 else s[n] := AText[i];
    Inc(i);
  end;
  SetLength(s, n);
  if not ABracketed then
    Exit(s);
  { ESC -> U+241B, so pasted text cannot end the bracket itself }
  Result := C0_ESC + '[200~';
  for i := 1 to Length(s) do
    if s[i] = C0_ESC then
      Result := Result + #$E2#$90#$9B
    else
      Result := Result + s[i];
  Result := Result + C0_ESC + '[201~';
end;

end.
