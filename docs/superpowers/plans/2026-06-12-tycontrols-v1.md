# TyControls v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a distributable, skinnable Lazarus control library — 8 Tier-1 controls plus a custom window-chrome subsystem — themed by a CSS-lite (.tycss) engine and rendered with BGRABitmap.

**Architecture:** Three decoupled layers. Controls mirror LCL APIs and hold no colors; they ask the style engine for a resolved TTyStyleSet given (typeKey, styleClass, states); TTyPainter renders that set with BGRA primitives. A TTyStyleController loads .tycss themes and broadcasts changes; TTyFormChrome skins plain TForms.

**Tech Stack:** Free Pascal 3.2.2+, Lazarus 3.x, LCL, BGRABitmap, FPCUnit.

**Execution order:** Tasks are grouped by phase P1 to P4 in dependency order; complete sections top to bottom — later sections use units built by earlier ones. Task IDs are Task <SECTION-KEY>.<n>.

---

## Project structure (created by this plan)

```
/source    runtime units (tyControls.*.pas)
/themes    light.tycss / dark.tycss / showcase.tycss
/examples  demo project
/tests     FPCUnit units + tytests.lpr runner
/docs      spec, this plan, known-gaps note
tycontrols.lpk      runtime package (dep: BGRABitmap)
tycontrols_dt.lpk   design package  (dep: tycontrols + LazIDEIntf + IDEIntf)
```

---

## P1 · Style Engine Core: Types + Lexer + Parser

### Task ENGINE-CORE.1: Console test runner skeleton

**Files:**
- Create: `/tests/tytests.lpr`

- [ ] **Step 1: Create the consoletestrunner program skeleton with an empty test-unit uses list.**
  Write `/tests/tytests.lpr`:
  ```pascal
  program tytests;

  {$mode objfpc}{$H+}

  uses
    consoletestrunner;

  type
    TTyTestRunner = class(TTestRunner)
    protected
    end;

  var
    Application: TTyTestRunner;

  begin
    Application := TTyTestRunner.Create(nil);
    Application.Initialize;
    Application.Title := 'TyControls Test Runner';
    Application.Run;
    Application.Free;
  end.
  ```

- [ ] **Step 2: Build the runner to verify it compiles with no registered tests.**
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build succeeds; output reports `Number of run tests: 0` (no tests registered yet).

- [ ] **Step 3: Commit the runner skeleton.**
  Run: `git add tests/tytests.lpr` then `git commit -m "test(tycontrols): add FPCUnit console test runner skeleton"`

### Task ENGINE-CORE.2: Core Types — enums, records, color helpers

**Files:**
- Create: `/source/tyControls.Types.pas`
- Test: `/tests/test.Types.pas`

- [ ] **Step 1: Create the failing test unit for the color helpers and EmptyStyleSet.**
  Write `/tests/test.Types.pas`:
  ```pascal
  unit test.Types;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, fpcunit, testregistry, tyControls.Types;

  type
    TTestTypes = class(TTestCase)
    published
      procedure TestTyRGB;
      procedure TestTyRGBA;
      procedure TestTyAlphaOf;
      procedure TestTyChannelOf;
      procedure TestTransparentConst;
      procedure TestEmptyStyleSet;
    end;

  implementation

  procedure TTestTypes.TestTyRGB;
  begin
    AssertEquals('opaque red', TTyColor($FFFF0000), TyRGB(255, 0, 0));
    AssertEquals('opaque green', TTyColor($FF00FF00), TyRGB(0, 255, 0));
  end;

  procedure TTestTypes.TestTyRGBA;
  begin
    AssertEquals('half-alpha blue', TTyColor($800000FF), TyRGBA(0, 0, 255, $80));
  end;

  procedure TTestTypes.TestTyAlphaOf;
  begin
    AssertEquals('alpha byte', Byte($80), TyAlphaOf(TTyColor($80112233)));
  end;

  procedure TTestTypes.TestTyChannelOf;
  begin
    AssertEquals('red', Byte($11), TyRedOf(TTyColor($FF112233)));
    AssertEquals('green', Byte($22), TyGreenOf(TTyColor($FF112233)));
    AssertEquals('blue', Byte($33), TyBlueOf(TTyColor($FF112233)));
  end;

  procedure TTestTypes.TestTransparentConst;
  begin
    AssertEquals('transparent', TTyColor($00000000), tyTransparent);
  end;

  procedure TTestTypes.TestEmptyStyleSet;
  var
    s: TTyStyleSet;
  begin
    s := EmptyStyleSet;
    AssertTrue('present empty', s.Present = []);
    AssertEquals('opacity default', Single(1.0), s.Opacity, 0.0001);
    AssertTrue('bg none', s.Background.Kind = tfkNone);
  end;

  initialization
    RegisterTest(TTestTypes);
  end.
  ```

- [ ] **Step 2: Add `test.Types` to the runner uses clause and run expecting FAIL (unit not found / compile error).**
  Edit `/tests/tytests.lpr` uses clause to read `consoletestrunner, test.Types;`.
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build FAILS because `tyControls.Types` does not exist yet.

- [ ] **Step 3: Implement `/source/tyControls.Types.pas` with all enums, records, and helpers.**
  Write `/source/tyControls.Types.pas`:
  ```pascal
  unit tyControls.Types;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, Types;

  type
    TTyColor = type Cardinal;            // $AARRGGBB

    TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled);
    TTyStateSet = set of TTyState;

    TTyFillKind = (tfkNone, tfkSolid, tfkLinearGradient, tfkNineSlice);

    TTyFill = record
      Kind: TTyFillKind;
      Color: TTyColor;
      GradFrom, GradTo: TTyColor;
      GradAngleDeg: Single;
      ImagePath: string;
      SliceInsets: TRect;
    end;

    TTyProp = (tpBackground, tpTextColor, tpBorderColor, tpBorderWidth, tpBorderRadius,
               tpPadding, tpFontName, tpFontSize, tpFontWeight, tpOpacity, tpShadow);
    TTyPropSet = set of TTyProp;

    TTyStyleSet = record
      Present: TTyPropSet;
      Background: TTyFill;
      TextColor: TTyColor;
      BorderColor: TTyColor;
      BorderWidth: Integer;
      BorderRadius: Integer;
      Padding: TRect;
      FontName: string;
      FontSize: Integer;
      FontWeight: Integer;
      Opacity: Single;
      ShadowColor: TTyColor;
      ShadowBlur: Integer;
      ShadowOffset: TPoint;
    end;

  const
    tyTransparent: TTyColor = $00000000;

  function TyRGB(R, G, B: Byte): TTyColor;
  function TyRGBA(R, G, B, A: Byte): TTyColor;
  function TyAlphaOf(c: TTyColor): Byte;
  function TyRedOf(c: TTyColor): Byte;
  function TyGreenOf(c: TTyColor): Byte;
  function TyBlueOf(c: TTyColor): Byte;
  function EmptyStyleSet: TTyStyleSet;

  implementation

  function TyRGB(R, G, B: Byte): TTyColor;
  begin
    Result := TTyColor((Cardinal($FF) shl 24) or (Cardinal(R) shl 16) or
                       (Cardinal(G) shl 8) or Cardinal(B));
  end;

  function TyRGBA(R, G, B, A: Byte): TTyColor;
  begin
    Result := TTyColor((Cardinal(A) shl 24) or (Cardinal(R) shl 16) or
                       (Cardinal(G) shl 8) or Cardinal(B));
  end;

  function TyAlphaOf(c: TTyColor): Byte;
  begin
    Result := Byte((Cardinal(c) shr 24) and $FF);
  end;

  function TyRedOf(c: TTyColor): Byte;
  begin
    Result := Byte((Cardinal(c) shr 16) and $FF);
  end;

  function TyGreenOf(c: TTyColor): Byte;
  begin
    Result := Byte((Cardinal(c) shr 8) and $FF);
  end;

  function TyBlueOf(c: TTyColor): Byte;
  begin
    Result := Byte(Cardinal(c) and $FF);
  end;

  function EmptyStyleSet: TTyStyleSet;
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Present := [];
    Result.Background.Kind := tfkNone;
    Result.Opacity := 1.0;
  end;

  end.
  ```

- [ ] **Step 4: Run the tests expecting PASS.**
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build succeeds; `TestTyRGB`, `TestTyRGBA`, `TestTyAlphaOf`, `TestTyChannelOf`, `TestTransparentConst`, `TestEmptyStyleSet` all PASS; `Number of failures: 0`.

- [ ] **Step 5: Commit the Types unit and its test.**
  Run: `git add source/tyControls.Types.pas tests/test.Types.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add core Types enums, records and color helpers"`

### Task ENGINE-CORE.3: CSS token kinds and token record

**Files:**
- Create: `/source/tyControls.Css.Tokens.pas`
- Test: `/tests/test.Css.Tokens.pas`

- [ ] **Step 1: Create the failing test unit asserting the token kind ordinals and record fields.**
  Write `/tests/test.Css.Tokens.pas`:
  ```pascal
  unit test.Css.Tokens;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, fpcunit, testregistry, tyControls.Css.Tokens;

  type
    TTestCssTokens = class(TTestCase)
    published
      procedure TestKindOrdinals;
      procedure TestTokenRecord;
    end;

  implementation

  procedure TTestCssTokens.TestKindOrdinals;
  begin
    AssertEquals('ident first', 0, Ord(ctkIdent));
    AssertEquals('eof last', 15, Ord(ctkEOF));
    AssertTrue('function before delim', Ord(ctkFunction) < Ord(ctkDelim));
  end;

  procedure TTestCssTokens.TestTokenRecord;
  var
    t: TTyCssToken;
  begin
    t.Kind := ctkHash;
    t.Text := '3B82F6';
    t.Line := 4;
    t.Col := 12;
    AssertTrue('kind', t.Kind = ctkHash);
    AssertEquals('text', '3B82F6', t.Text);
    AssertEquals('line', 4, t.Line);
    AssertEquals('col', 12, t.Col);
  end;

  initialization
    RegisterTest(TTestCssTokens);
  end.
  ```

- [ ] **Step 2: Add `test.Css.Tokens` to the runner uses clause and run expecting FAIL.**
  Edit `/tests/tytests.lpr` uses clause to append `, test.Css.Tokens`.
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build FAILS because `tyControls.Css.Tokens` does not exist yet.

- [ ] **Step 3: Implement `/source/tyControls.Css.Tokens.pas`.**
  Write `/source/tyControls.Css.Tokens.pas`:
  ```pascal
  unit tyControls.Css.Tokens;

  {$mode objfpc}{$H+}

  interface

  type
    TTyCssTokenKind = (ctkIdent, ctkHash, ctkNumber, ctkPercent, ctkColon, ctkSemicolon,
        ctkLBrace, ctkRBrace, ctkDot, ctkComma, ctkLParen, ctkRParen, ctkString, ctkFunction, ctkDelim, ctkEOF);

    TTyCssToken = record
      Kind: TTyCssTokenKind;
      Text: string;
      Line, Col: Integer;
    end;

  implementation

  end.
  ```

- [ ] **Step 4: Run the tests expecting PASS.**
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build succeeds; `TestKindOrdinals` and `TestTokenRecord` PASS; `Number of failures: 0`.

- [ ] **Step 5: Commit the Tokens unit and its test.**
  Run: `git add source/tyControls.Css.Tokens.pas tests/test.Css.Tokens.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add CSS token kinds and token record"`

### Task ENGINE-CORE.4: CSS Lexer

**Files:**
- Create: `/source/tyControls.Css.Lexer.pas`
- Test: `/tests/test.Css.Lexer.pas`

- [ ] **Step 1: Create the failing test unit covering idents, hash colors, numbers+px, percent, punctuation, parens, function tokens, strings, comments, EOF, and line/col tracking.**
  Write `/tests/test.Css.Lexer.pas`:
  ```pascal
  unit test.Css.Lexer;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, fpcunit, testregistry, tyControls.Css.Tokens, tyControls.Css.Lexer;

  type
    TTestCssLexer = class(TTestCase)
    published
      procedure TestIdent;
      procedure TestHashColor;
      procedure TestNumberAndPx;
      procedure TestPercent;
      procedure TestPunctuation;
      procedure TestParens;
      procedure TestFunctionToken;
      procedure TestString;
      procedure TestComment;
      procedure TestPeekDoesNotConsume;
      procedure TestLineColTracking;
    end;

  implementation

  procedure TTestCssLexer.TestIdent;
  var
    lex: TTyCssLexer;
    t: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('TyButton');
    try
      t := lex.Next;
      AssertTrue('ident kind', t.Kind = ctkIdent);
      AssertEquals('ident text', 'TyButton', t.Text);
      AssertTrue('then eof', lex.Next.Kind = ctkEOF);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestHashColor;
  var
    lex: TTyCssLexer;
    t: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('#3B82F6');
    try
      t := lex.Next;
      AssertTrue('hash kind', t.Kind = ctkHash);
      AssertEquals('hash text excludes #', '3B82F6', t.Text);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestNumberAndPx;
  var
    lex: TTyCssLexer;
    n, u: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('12px');
    try
      n := lex.Next;
      AssertTrue('number kind', n.Kind = ctkNumber);
      AssertEquals('number text', '12', n.Text);
      u := lex.Next;
      AssertTrue('px is ident', u.Kind = ctkIdent);
      AssertEquals('px text', 'px', u.Text);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestPercent;
  var
    lex: TTyCssLexer;
    n, p: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('8%');
    try
      n := lex.Next;
      AssertTrue('number kind', n.Kind = ctkNumber);
      AssertEquals('number text', '8', n.Text);
      p := lex.Next;
      AssertTrue('percent kind', p.Kind = ctkPercent);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestPunctuation;
  var
    lex: TTyCssLexer;
  begin
    lex := TTyCssLexer.Create('.:;{},');
    try
      AssertTrue('dot', lex.Next.Kind = ctkDot);
      AssertTrue('colon', lex.Next.Kind = ctkColon);
      AssertTrue('semicolon', lex.Next.Kind = ctkSemicolon);
      AssertTrue('lbrace', lex.Next.Kind = ctkLBrace);
      AssertTrue('rbrace', lex.Next.Kind = ctkRBrace);
      AssertTrue('comma', lex.Next.Kind = ctkComma);
      AssertTrue('eof', lex.Next.Kind = ctkEOF);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestParens;
  var
    lex: TTyCssLexer;
  begin
    lex := TTyCssLexer.Create('()');
    try
      AssertTrue('lparen', lex.Next.Kind = ctkLParen);
      AssertTrue('rparen', lex.Next.Kind = ctkRParen);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestFunctionToken;
  var
    lex: TTyCssLexer;
    f: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('lighten(');
    try
      f := lex.Next;
      AssertTrue('function kind', f.Kind = ctkFunction);
      AssertEquals('function name no paren', 'lighten', f.Text);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestString;
  var
    lex: TTyCssLexer;
    s: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('"Segoe UI"');
    try
      s := lex.Next;
      AssertTrue('string kind', s.Kind = ctkString);
      AssertEquals('string text no quotes', 'Segoe UI', s.Text);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestComment;
  var
    lex: TTyCssLexer;
    t: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('/* skip me */ accent');
    try
      t := lex.Next;
      AssertTrue('comment skipped', t.Kind = ctkIdent);
      AssertEquals('ident after comment', 'accent', t.Text);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestPeekDoesNotConsume;
  var
    lex: TTyCssLexer;
  begin
    lex := TTyCssLexer.Create('a b');
    try
      AssertEquals('peek a', 'a', lex.Peek.Text);
      AssertEquals('peek again a', 'a', lex.Peek.Text);
      AssertEquals('next a', 'a', lex.Next.Text);
      AssertEquals('next b', 'b', lex.Next.Text);
    finally
      lex.Free;
    end;
  end;

  procedure TTestCssLexer.TestLineColTracking;
  var
    lex: TTyCssLexer;
    t1, t2: TTyCssToken;
  begin
    lex := TTyCssLexer.Create('ab' + LineEnding + '  cd');
    try
      t1 := lex.Next;
      AssertEquals('t1 line', 1, t1.Line);
      AssertEquals('t1 col', 1, t1.Col);
      t2 := lex.Next;
      AssertEquals('t2 line', 2, t2.Line);
      AssertEquals('t2 col', 3, t2.Col);
    finally
      lex.Free;
    end;
  end;

  initialization
    RegisterTest(TTestCssLexer);
  end.
  ```

- [ ] **Step 2: Add `test.Css.Lexer` to the runner uses clause and run expecting FAIL.**
  Edit `/tests/tytests.lpr` uses clause to append `, test.Css.Lexer`.
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build FAILS because `tyControls.Css.Lexer` does not exist yet.

- [ ] **Step 3: Implement `/source/tyControls.Css.Lexer.pas`.**
  Write `/source/tyControls.Css.Lexer.pas`:
  ```pascal
  unit tyControls.Css.Lexer;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, tyControls.Css.Tokens;

  type
    TTyCssLexer = class
    private
      FSource: string;
      FPos: Integer;
      FLine, FCol: Integer;
      FHasPeek: Boolean;
      FPeeked: TTyCssToken;
      function CurChar: Char;
      function PeekChar(AOffset: Integer): Char;
      procedure Advance;
      procedure SkipWhitespaceAndComments;
      function MakeToken(AKind: TTyCssTokenKind; const AText: string;
        ALine, ACol: Integer): TTyCssToken;
      function ReadToken: TTyCssToken;
    public
      constructor Create(const ASource: string);
      function Next: TTyCssToken;
      function Peek: TTyCssToken;
    end;

  implementation

  constructor TTyCssLexer.Create(const ASource: string);
  begin
    inherited Create;
    FSource := ASource;
    FPos := 1;
    FLine := 1;
    FCol := 1;
    FHasPeek := False;
  end;

  function TTyCssLexer.CurChar: Char;
  begin
    if FPos <= Length(FSource) then
      Result := FSource[FPos]
    else
      Result := #0;
  end;

  function TTyCssLexer.PeekChar(AOffset: Integer): Char;
  var
    p: Integer;
  begin
    p := FPos + AOffset;
    if (p >= 1) and (p <= Length(FSource)) then
      Result := FSource[p]
    else
      Result := #0;
  end;

  procedure TTyCssLexer.Advance;
  begin
    if FPos > Length(FSource) then
      Exit;
    if FSource[FPos] = #10 then
    begin
      Inc(FLine);
      FCol := 1;
    end
    else if FSource[FPos] = #13 then
    begin
      // treat CR as line break unless followed by LF (LF handles it)
      if PeekChar(1) <> #10 then
      begin
        Inc(FLine);
        FCol := 1;
      end
      else
        Inc(FCol);
    end
    else
      Inc(FCol);
    Inc(FPos);
  end;

  procedure TTyCssLexer.SkipWhitespaceAndComments;
  begin
    while FPos <= Length(FSource) do
    begin
      if CurChar in [' ', #9, #10, #13] then
        Advance
      else if (CurChar = '/') and (PeekChar(1) = '*') then
      begin
        Advance; // '/'
        Advance; // '*'
        while FPos <= Length(FSource) do
        begin
          if (CurChar = '*') and (PeekChar(1) = '/') then
          begin
            Advance; // '*'
            Advance; // '/'
            Break;
          end
          else
            Advance;
        end;
      end
      else
        Break;
    end;
  end;

  function TTyCssLexer.MakeToken(AKind: TTyCssTokenKind; const AText: string;
    ALine, ACol: Integer): TTyCssToken;
  begin
    Result.Kind := AKind;
    Result.Text := AText;
    Result.Line := ALine;
    Result.Col := ACol;
  end;

  function TTyCssLexer.ReadToken: TTyCssToken;
  var
    startLine, startCol: Integer;
    s: string;
    quote: Char;
  begin
    SkipWhitespaceAndComments;
    startLine := FLine;
    startCol := FCol;

    if FPos > Length(FSource) then
      Exit(MakeToken(ctkEOF, '', startLine, startCol));

    // Hash color
    if CurChar = '#' then
    begin
      Advance;
      s := '';
      while CurChar in ['0'..'9', 'a'..'f', 'A'..'F'] do
      begin
        s := s + CurChar;
        Advance;
      end;
      Exit(MakeToken(ctkHash, s, startLine, startCol));
    end;

    // Number (no sign, optional fraction)
    if (CurChar in ['0'..'9']) or
       ((CurChar = '.') and (PeekChar(1) in ['0'..'9'])) then
    begin
      s := '';
      while CurChar in ['0'..'9'] do
      begin
        s := s + CurChar;
        Advance;
      end;
      if (CurChar = '.') and (PeekChar(1) in ['0'..'9']) then
      begin
        s := s + CurChar;
        Advance;
        while CurChar in ['0'..'9'] do
        begin
          s := s + CurChar;
          Advance;
        end;
      end;
      Exit(MakeToken(ctkNumber, s, startLine, startCol));
    end;

    // Identifier or function (ident followed immediately by '(')
    if (CurChar in ['a'..'z', 'A'..'Z', '_', '-']) then
    begin
      s := '';
      while CurChar in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-'] do
      begin
        s := s + CurChar;
        Advance;
      end;
      if CurChar = '(' then
      begin
        Advance; // consume '('
        Exit(MakeToken(ctkFunction, s, startLine, startCol));
      end;
      Exit(MakeToken(ctkIdent, s, startLine, startCol));
    end;

    // String
    if (CurChar = '"') or (CurChar = '''') then
    begin
      quote := CurChar;
      Advance;
      s := '';
      while (FPos <= Length(FSource)) and (CurChar <> quote) do
      begin
        s := s + CurChar;
        Advance;
      end;
      if CurChar = quote then
        Advance;
      Exit(MakeToken(ctkString, s, startLine, startCol));
    end;

    // Single-char punctuation
    case CurChar of
      '%': begin Advance; Exit(MakeToken(ctkPercent, '%', startLine, startCol)); end;
      ':': begin Advance; Exit(MakeToken(ctkColon, ':', startLine, startCol)); end;
      ';': begin Advance; Exit(MakeToken(ctkSemicolon, ';', startLine, startCol)); end;
      '{': begin Advance; Exit(MakeToken(ctkLBrace, '{', startLine, startCol)); end;
      '}': begin Advance; Exit(MakeToken(ctkRBrace, '}', startLine, startCol)); end;
      '.': begin Advance; Exit(MakeToken(ctkDot, '.', startLine, startCol)); end;
      ',': begin Advance; Exit(MakeToken(ctkComma, ',', startLine, startCol)); end;
      '(': begin Advance; Exit(MakeToken(ctkLParen, '(', startLine, startCol)); end;
      ')': begin Advance; Exit(MakeToken(ctkRParen, ')', startLine, startCol)); end;
    end;

    // Anything else: delimiter
    s := CurChar;
    Advance;
    Result := MakeToken(ctkDelim, s, startLine, startCol);
  end;

  function TTyCssLexer.Next: TTyCssToken;
  begin
    if FHasPeek then
    begin
      FHasPeek := False;
      Result := FPeeked;
    end
    else
      Result := ReadToken;
  end;

  function TTyCssLexer.Peek: TTyCssToken;
  begin
    if not FHasPeek then
    begin
      FPeeked := ReadToken;
      FHasPeek := True;
    end;
    Result := FPeeked;
  end;

  end.
  ```

- [ ] **Step 4: Run the lexer tests expecting PASS.**
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build succeeds; all 11 `TTestCssLexer` tests PASS; `Number of failures: 0`.

- [ ] **Step 5: Commit the Lexer unit and its test.**
  Run: `git add source/tyControls.Css.Lexer.pas tests/test.Css.Lexer.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add CSS-lite lexer with comment and line/col tracking"`

### Task ENGINE-CORE.5: CSS Parser and AST

**Files:**
- Create: `/source/tyControls.Css.Parser.pas`
- Test: `/tests/test.Css.Parser.pas`

- [ ] **Step 1: Create the failing test unit covering a full stylesheet, :root vars, comma selector lists, type/.variant/:state selectors, and two syntax-error cases.**
  Write `/tests/test.Css.Parser.pas`:
  ```pascal
  unit test.Css.Parser;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, fpcunit, testregistry,
    tyControls.Types, tyControls.Css.Parser;

  type
    TTestCssParser = class(TTestCase)
    private
      function RuleAt(ASheet: TTyCssStylesheet; AIndex: Integer): TTyCssRule;
    published
      procedure TestRootVars;
      procedure TestTypeSelectorAndDeclarations;
      procedure TestVariantAndStateSelector;
      procedure TestCommaSelectorList;
      procedure TestFullStylesheet;
      procedure TestErrorMissingBrace;
      procedure TestErrorMissingSemicolon;
    end;

  implementation

  function TTestCssParser.RuleAt(ASheet: TTyCssStylesheet; AIndex: Integer): TTyCssRule;
  begin
    Result := TTyCssRule(ASheet.Rules[AIndex]);
  end;

  procedure TTestCssParser.TestRootVars;
  var
    p: TTyCssParser;
    sheet: TTyCssStylesheet;
  begin
    p := TTyCssParser.Create(':root { --accent: #3B82F6; --radius: 6px; }');
    try
      sheet := p.Parse;
      try
        AssertEquals('no rules', 0, sheet.Rules.Count);
        AssertEquals('accent var', '#3B82F6', sheet.RootVars.Values['accent']);
        AssertEquals('radius var', '6px', sheet.RootVars.Values['radius']);
      finally
        sheet.Free;
      end;
    finally
      p.Free;
    end;
  end;

  procedure TTestCssParser.TestTypeSelectorAndDeclarations;
  var
    p: TTyCssParser;
    sheet: TTyCssStylesheet;
    r: TTyCssRule;
  begin
    p := TTyCssParser.Create('TyButton { background: var(--surface); color: #FFFFFF; }');
    try
      sheet := p.Parse;
      try
        AssertEquals('one rule', 1, sheet.Rules.Count);
        r := RuleAt(sheet, 0);
        AssertEquals('one selector', 1, Length(r.Selectors));
        AssertEquals('typename', 'TyButton', r.Selectors[0].TypeName);
        AssertEquals('no variant', '', r.Selectors[0].Variant);
        AssertFalse('no state', r.Selectors[0].HasState);
        AssertEquals('two decls', 2, Length(r.Declarations));
        AssertEquals('prop1', 'background', r.Declarations[0].Prop);
        AssertEquals('raw1', 'var(--surface)', r.Declarations[0].RawValue);
        AssertEquals('prop2', 'color', r.Declarations[1].Prop);
        AssertEquals('raw2', '#FFFFFF', r.Declarations[1].RawValue);
      finally
        sheet.Free;
      end;
    finally
      p.Free;
    end;
  end;

  procedure TTestCssParser.TestVariantAndStateSelector;
  var
    p: TTyCssParser;
    sheet: TTyCssStylesheet;
    r: TTyCssRule;
  begin
    p := TTyCssParser.Create('TyButton.primary:hover { opacity: 0.5; }');
    try
      sheet := p.Parse;
      try
        r := RuleAt(sheet, 0);
        AssertEquals('typename', 'TyButton', r.Selectors[0].TypeName);
        AssertEquals('variant', 'primary', r.Selectors[0].Variant);
        AssertTrue('has state', r.Selectors[0].HasState);
        AssertTrue('state hover', r.Selectors[0].State = tysHover);
      finally
        sheet.Free;
      end;
    finally
      p.Free;
    end;
  end;

  procedure TTestCssParser.TestCommaSelectorList;
  var
    p: TTyCssParser;
    sheet: TTyCssStylesheet;
    r: TTyCssRule;
  begin
    p := TTyCssParser.Create('TyButton:active, TyEdit:disabled { color: #000000; }');
    try
      sheet := p.Parse;
      try
        r := RuleAt(sheet, 0);
        AssertEquals('two selectors', 2, Length(r.Selectors));
        AssertEquals('sel0 type', 'TyButton', r.Selectors[0].TypeName);
        AssertTrue('sel0 active', r.Selectors[0].State = tysActive);
        AssertEquals('sel1 type', 'TyEdit', r.Selectors[1].TypeName);
        AssertTrue('sel1 disabled', r.Selectors[1].State = tysDisabled);
      finally
        sheet.Free;
      end;
    finally
      p.Free;
    end;
  end;

  procedure TTestCssParser.TestFullStylesheet;
  var
    p: TTyCssParser;
    sheet: TTyCssStylesheet;
  begin
    p := TTyCssParser.Create(
      ':root { --accent: #3B82F6; }' + LineEnding +
      'TyButton { background: var(--accent); }' + LineEnding +
      'TyButton.primary { background: #FF0000; }' + LineEnding +
      'TyButton:focus { border-width: 2px; }');
    try
      sheet := p.Parse;
      try
        AssertEquals('accent var', '#3B82F6', sheet.RootVars.Values['accent']);
        AssertEquals('three rules', 3, sheet.Rules.Count);
        AssertEquals('rule0 type', 'TyButton', RuleAt(sheet, 0).Selectors[0].TypeName);
        AssertEquals('rule1 variant', 'primary', RuleAt(sheet, 1).Selectors[0].Variant);
        AssertTrue('rule2 focus', RuleAt(sheet, 2).Selectors[0].State = tysFocused);
      finally
        sheet.Free;
      end;
    finally
      p.Free;
    end;
  end;

  procedure TTestCssParser.TestErrorMissingBrace;
  var
    p: TTyCssParser;
    raised: Boolean;
  begin
    p := TTyCssParser.Create('TyButton background: #fff; }');
    raised := False;
    try
      try
        p.Parse.Free;
      except
        on E: ETyCssError do
          raised := True;
      end;
      AssertTrue('missing open brace raises ETyCssError', raised);
    finally
      p.Free;
    end;
  end;

  procedure TTestCssParser.TestErrorMissingSemicolon;
  var
    p: TTyCssParser;
    raised: Boolean;
  begin
    p := TTyCssParser.Create('TyButton { color: #fff border-width: 2px; }');
    raised := False;
    try
      try
        p.Parse.Free;
      except
        on E: ETyCssError do
          raised := True;
      end;
      AssertTrue('missing semicolon raises ETyCssError', raised);
    finally
      p.Free;
    end;
  end;

  initialization
    RegisterTest(TTestCssParser);
  end.
  ```

- [ ] **Step 2: Add `test.Css.Parser` to the runner uses clause and run expecting FAIL.**
  Edit `/tests/tytests.lpr` uses clause to append `, test.Css.Parser`.
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build FAILS because `tyControls.Css.Parser` does not exist yet.

- [ ] **Step 3: Implement `/source/tyControls.Css.Parser.pas` with the AST and recursive-descent parser.**
  Write `/source/tyControls.Css.Parser.pas`:
  ```pascal
  unit tyControls.Css.Parser;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, tyControls.Types, tyControls.Css.Tokens, tyControls.Css.Lexer;

  type
    TTyCssSelector = record
      TypeName: string;
      Variant: string;
      State: TTyState;
      HasState: Boolean;
    end;

    TTyCssDeclaration = record
      Prop: string;
      RawValue: string;
    end;

    TTyCssRule = class
      Selectors: array of TTyCssSelector;
      Declarations: array of TTyCssDeclaration;
    end;

    TTyCssStylesheet = class
      Rules: TFPList;
      RootVars: TStringList;
      constructor Create;
      destructor Destroy; override;
    end;

    ETyCssError = class(Exception);

    TTyCssParser = class
    private
      FLexer: TTyCssLexer;
      function Expect(AKind: TTyCssTokenKind): TTyCssToken;
      procedure Error(const AMsg: string; const ATok: TTyCssToken);
      function PseudoToState(const AName: string; const ATok: TTyCssToken): TTyState;
      function ParseSelector: TTyCssSelector;
      function ReadRawValue: string;
      procedure ParseRootBlock(ASheet: TTyCssStylesheet);
      procedure ParseRule(ASheet: TTyCssStylesheet);
    public
      constructor Create(const ASource: string);
      destructor Destroy; override;
      function Parse: TTyCssStylesheet;
    end;

  implementation

  constructor TTyCssStylesheet.Create;
  begin
    inherited Create;
    Rules := TFPList.Create;
    RootVars := TStringList.Create;
  end;

  destructor TTyCssStylesheet.Destroy;
  var
    i: Integer;
  begin
    if Assigned(Rules) then
    begin
      for i := 0 to Rules.Count - 1 do
        TTyCssRule(Rules[i]).Free;
      Rules.Free;
    end;
    RootVars.Free;
    inherited Destroy;
  end;

  constructor TTyCssParser.Create(const ASource: string);
  begin
    inherited Create;
    FLexer := TTyCssLexer.Create(ASource);
  end;

  destructor TTyCssParser.Destroy;
  begin
    FLexer.Free;
    inherited Destroy;
  end;

  procedure TTyCssParser.Error(const AMsg: string; const ATok: TTyCssToken);
  begin
    raise ETyCssError.CreateFmt('%s at line %d, col %d (got "%s")',
      [AMsg, ATok.Line, ATok.Col, ATok.Text]);
  end;

  function TTyCssParser.Expect(AKind: TTyCssTokenKind): TTyCssToken;
  begin
    Result := FLexer.Next;
    if Result.Kind <> AKind then
      Error('Unexpected token', Result);
  end;

  function TTyCssParser.PseudoToState(const AName: string; const ATok: TTyCssToken): TTyState;
  var
    n: string;
  begin
    n := LowerCase(AName);
    if n = 'hover' then
      Result := tysHover
    else if n = 'active' then
      Result := tysActive
    else if n = 'focus' then
      Result := tysFocused
    else if n = 'disabled' then
      Result := tysDisabled
    else
    begin
      Error('Unknown pseudo-class "' + AName + '"', ATok);
      Result := tysNormal; // unreachable; silences warning
    end;
  end;

  function TTyCssParser.ParseSelector: TTyCssSelector;
  var
    tok: TTyCssToken;
  begin
    Result.TypeName := '';
    Result.Variant := '';
    Result.State := tysNormal;
    Result.HasState := False;

    tok := Expect(ctkIdent);
    Result.TypeName := tok.Text;

    // optional .variant
    if FLexer.Peek.Kind = ctkDot then
    begin
      FLexer.Next; // consume dot
      tok := Expect(ctkIdent);
      Result.Variant := tok.Text;
    end;

    // optional :state
    if FLexer.Peek.Kind = ctkColon then
    begin
      FLexer.Next; // consume colon
      tok := Expect(ctkIdent);
      Result.State := PseudoToState(tok.Text, tok);
      Result.HasState := True;
    end;
  end;

  function TTyCssParser.ReadRawValue: string;
  var
    tok: TTyCssToken;
    sb: string;
  begin
    sb := '';
    while True do
    begin
      tok := FLexer.Peek;
      case tok.Kind of
        ctkSemicolon, ctkRBrace, ctkEOF:
          Break;
        ctkHash:
          begin FLexer.Next; sb := sb + '#' + tok.Text; end;
        ctkPercent:
          begin FLexer.Next; sb := sb + '%'; end;
        ctkFunction:
          begin FLexer.Next; sb := sb + tok.Text + '('; end;
        ctkString:
          begin FLexer.Next; sb := sb + '"' + tok.Text + '"'; end;
        ctkComma:
          begin FLexer.Next; sb := sb + ', '; end;
        ctkLParen:
          begin FLexer.Next; sb := sb + '('; end;
        ctkRParen:
          begin FLexer.Next; sb := sb + ')'; end;
        ctkDot:
          begin FLexer.Next; sb := sb + '.'; end;
        ctkColon:
          begin FLexer.Next; sb := sb + ':'; end;
      else
        begin
          FLexer.Next;
          if sb = '' then
            sb := tok.Text
          else if (tok.Kind = ctkIdent) and (Length(sb) > 0) and (sb[Length(sb)] = '(') then
            sb := sb + tok.Text
          else
            sb := sb + ' ' + tok.Text;
        end;
      end;
    end;
    Result := Trim(sb);
  end;

  procedure TTyCssParser.ParseRootBlock(ASheet: TTyCssStylesheet);
  var
    tok, nameTok: TTyCssToken;
    raw: string;
  begin
    // ':root' ident already consumed by caller; expect '{'
    Expect(ctkLBrace);
    while True do
    begin
      tok := FLexer.Peek;
      if tok.Kind = ctkRBrace then
      begin
        FLexer.Next;
        Break;
      end;
      if tok.Kind = ctkEOF then
        Error('Unterminated :root block', tok);
      // expect identifier of form --name (lexer yields ctkIdent '--name')
      nameTok := Expect(ctkIdent);
      if Copy(nameTok.Text, 1, 2) <> '--' then
        Error('Expected --variable name', nameTok);
      Expect(ctkColon);
      raw := ReadRawValue;
      Expect(ctkSemicolon);
      ASheet.RootVars.Values[Copy(nameTok.Text, 3, Length(nameTok.Text) - 2)] := raw;
    end;
  end;

  procedure TTyCssParser.ParseRule(ASheet: TTyCssStylesheet);
  var
    rule: TTyCssRule;
    sel: TTyCssSelector;
    tok, propTok: TTyCssToken;
    raw: string;
  begin
    rule := TTyCssRule.Create;
    try
      // selector list
      SetLength(rule.Selectors, 1);
      rule.Selectors[0] := ParseSelector;
      while FLexer.Peek.Kind = ctkComma do
      begin
        FLexer.Next; // consume comma
        sel := ParseSelector;
        SetLength(rule.Selectors, Length(rule.Selectors) + 1);
        rule.Selectors[High(rule.Selectors)] := sel;
      end;

      Expect(ctkLBrace);

      while True do
      begin
        tok := FLexer.Peek;
        if tok.Kind = ctkRBrace then
        begin
          FLexer.Next;
          Break;
        end;
        if tok.Kind = ctkEOF then
          Error('Unterminated rule block', tok);
        propTok := Expect(ctkIdent);
        Expect(ctkColon);
        raw := ReadRawValue;
        Expect(ctkSemicolon);
        SetLength(rule.Declarations, Length(rule.Declarations) + 1);
        rule.Declarations[High(rule.Declarations)].Prop := propTok.Text;
        rule.Declarations[High(rule.Declarations)].RawValue := raw;
      end;

      ASheet.Rules.Add(rule);
      rule := nil;
    finally
      rule.Free;
    end;
  end;

  function TTyCssParser.Parse: TTyCssStylesheet;
  var
    tok: TTyCssToken;
  begin
    Result := TTyCssStylesheet.Create;
    try
      while True do
      begin
        tok := FLexer.Peek;
        if tok.Kind = ctkEOF then
          Break;
        if (tok.Kind = ctkColon) then
        begin
          // ':root'
          FLexer.Next; // consume ':'
          tok := Expect(ctkIdent);
          if LowerCase(tok.Text) <> 'root' then
            Error('Expected "root" after ":"', tok);
          ParseRootBlock(Result);
        end
        else if tok.Kind = ctkIdent then
          ParseRule(Result)
        else
          Error('Expected selector or :root', tok);
      end;
    except
      Result.Free;
      raise;
    end;
  end;

  end.
  ```

- [ ] **Step 4: Run the parser tests expecting PASS.**
  Run: `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`
  Expected: build succeeds; `TestRootVars`, `TestTypeSelectorAndDeclarations`, `TestVariantAndStateSelector`, `TestCommaSelectorList`, `TestFullStylesheet`, `TestErrorMissingBrace`, `TestErrorMissingSemicolon` all PASS; `Number of failures: 0`.

- [ ] **Step 5: Commit the Parser unit and its test.**
  Run: `git add source/tyControls.Css.Parser.pas tests/test.Css.Parser.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add CSS-lite parser, AST and ETyCssError"`

---

## P1 · Style Engine Evaluation: Value Functions + StyleModel + ResolveStyle

This section implements two units, depending only on `tyControls.Types` (owned upstream) and `tyControls.Css.*` (owned upstream). `tyControls.Css.Values` provides color/length/float evaluation with `var()` and nested functions. `tyControls.StyleModel` parses CSS into lookup maps and implements the exact `ResolveStyle` merge order. All tests are FPCUnit `TTestCase`s registered via `RegisterTest`, aggregated into `/tests/tytests.lpr`.

> Prerequisite for the test runner steps: `/tests/tytests.lpr` exists (created by the bootstrap section) and `tyControls.Types`, `tyControls.Css.Tokens`, `tyControls.Css.Lexer`, `tyControls.Css.Parser` are compilable. Each task below appends its own test unit to the `uses` clause of `/tests/tytests.lpr`.

### Task ENGINE-RESOLVE.1: Color primitives — TyParseColor, TyLighten, TyDarken, TyAlpha, TyMix

**Files:**
- Create: `/Users/tom/Projects/TyControls/source/tyControls.Css.Values.pas`
- Create: `/Users/tom/Projects/TyControls/tests/test.Css.Values.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/tytests.lpr`

- [ ] **Step 1: Create the test unit `test.Css.Values.pas` with the failing color-primitive tests.** Write the complete unit:
```pascal
unit test.Css.Values;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Types, tyControls.Css.Values;
type
  TTestCssValuesColors = class(TTestCase)
  published
    procedure TestParse3Digit;
    procedure TestParse6Digit;
    procedure TestParse8Digit;
    procedure TestLighten;
    procedure TestDarken;
    procedure TestAlpha;
    procedure TestMix;
  end;
implementation

procedure TTestCssValuesColors.TestParse3Digit;
var c: TTyColor;
begin
  c := TyParseColor('#f00');
  AssertEquals('alpha', 255, TyAlphaOf(c));
  AssertEquals('red', 255, TyRedOf(c));
  AssertEquals('green', 0, TyGreenOf(c));
  AssertEquals('blue', 0, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestParse6Digit;
var c: TTyColor;
begin
  c := TyParseColor('#3B82F6');
  AssertEquals('alpha', 255, TyAlphaOf(c));
  AssertEquals('red', $3B, TyRedOf(c));
  AssertEquals('green', $82, TyGreenOf(c));
  AssertEquals('blue', $F6, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestParse8Digit;
var c: TTyColor;
begin
  c := TyParseColor('#3B82F680');
  AssertEquals('alpha', $80, TyAlphaOf(c));
  AssertEquals('red', $3B, TyRedOf(c));
  AssertEquals('green', $82, TyGreenOf(c));
  AssertEquals('blue', $F6, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestLighten;
var c: TTyColor;
begin
  // base #404040 = 64; lighten 50%: 64 + (255-64)*0.5 = 64 + 95.5 -> round 160 -> 159? see formula
  c := TyLighten(TyRGB($40, $40, $40), 50);
  AssertEquals('red', 160, TyRedOf(c));
  AssertEquals('green', 160, TyGreenOf(c));
  AssertEquals('blue', 160, TyBlueOf(c));
  AssertEquals('alpha preserved', 255, TyAlphaOf(c));
end;

procedure TTestCssValuesColors.TestDarken;
var c: TTyColor;
begin
  // base #808080 = 128; darken 50%: 128*(1-0.5)=64
  c := TyDarken(TyRGB($80, $80, $80), 50);
  AssertEquals('red', 64, TyRedOf(c));
  AssertEquals('green', 64, TyGreenOf(c));
  AssertEquals('blue', 64, TyBlueOf(c));
  AssertEquals('alpha preserved', 255, TyAlphaOf(c));
end;

procedure TTestCssValuesColors.TestAlpha;
var c: TTyColor;
begin
  // A=0.5 -> alpha 128
  c := TyAlpha(TyRGB($10, $20, $30), 0.5);
  AssertEquals('alpha', 128, TyAlphaOf(c));
  AssertEquals('red preserved', $10, TyRedOf(c));
  AssertEquals('green preserved', $20, TyGreenOf(c));
  AssertEquals('blue preserved', $30, TyBlueOf(c));
end;

procedure TTestCssValuesColors.TestMix;
var c: TTyColor;
begin
  // mix(#000000, #FFFFFF, 50%) -> 50% of c2 -> 128 each
  c := TyMix(TyRGB(0, 0, 0), TyRGB($FF, $FF, $FF), 50);
  AssertEquals('red', 128, TyRedOf(c));
  AssertEquals('green', 128, TyGreenOf(c));
  AssertEquals('blue', 128, TyBlueOf(c));
end;

initialization
  RegisterTest(TTestCssValuesColors);
end.
```

- [ ] **Step 2: Add `test.Css.Values` to the `uses` clause of `/tests/tytests.lpr`.** Insert `test.Css.Values` into the comma-separated uses list of the runner program (alongside the existing test units).

- [ ] **Step 3: Run the test runner expecting a BUILD FAILURE.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `tyControls.Css.Values` does not yet exist (unit not found).

- [ ] **Step 4: Create `tyControls.Css.Values.pas` with the color primitives only (no var/length yet).** Write the complete unit; functions `TyEvalColor/TyEvalLength/TyEvalFloat` are added in Task .2 but their declarations are present now so the interface is stable:
```pascal
unit tyControls.Css.Values;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.Types;

function TyParseColor(const S: string): TTyColor;        // #rgb #rrggbb #rrggbbaa
function TyLighten(c: TTyColor; Pct: Single): TTyColor;  // Pct 0..100
function TyDarken(c: TTyColor; Pct: Single): TTyColor;   // Pct 0..100
function TyAlpha(c: TTyColor; A: Single): TTyColor;       // A 0..1
function TyMix(c1, c2: TTyColor; Pct: Single): TTyColor;  // Pct 0..100 of c2

implementation

// Clamp a real channel value into the 0..255 Byte range.
function ClampByte(V: Single): Byte;
var I: Integer;
begin
  I := Round(V);
  if I < 0 then I := 0;
  if I > 255 then I := 255;
  Result := Byte(I);
end;

// Parse one hex digit; raises ETyCssError-equivalent by returning via Valid flag.
function HexDigit(Ch: Char; out OK: Boolean): Integer;
begin
  OK := True;
  case Ch of
    '0'..'9': Result := Ord(Ch) - Ord('0');
    'a'..'f': Result := Ord(Ch) - Ord('a') + 10;
    'A'..'F': Result := Ord(Ch) - Ord('A') + 10;
  else
    Result := 0; OK := False;
  end;
end;

function HexByte(Hi, Lo: Char; out OK: Boolean): Integer;
var ho, lo2: Boolean;
begin
  Result := HexDigit(Hi, ho) * 16 + HexDigit(Lo, lo2);
  OK := ho and lo2;
end;

function TyParseColor(const S: string): TTyColor;
var
  T: string;
  R, G, B, A, n: Integer;
  ok1, ok2, ok3, ok4: Boolean;
begin
  T := Trim(S);
  if (T = '') or (T[1] <> '#') then
    raise Exception.CreateFmt('Invalid color literal: %s', [S]);
  T := Copy(T, 2, Length(T) - 1);
  n := Length(T);
  ok4 := True;
  A := 255;
  case n of
    3:
      begin
        // #rgb -> each digit doubled
        R := HexDigit(T[1], ok1) * 17;
        G := HexDigit(T[2], ok2) * 17;
        B := HexDigit(T[3], ok3) * 17;
      end;
    6:
      begin
        R := HexByte(T[1], T[2], ok1);
        G := HexByte(T[3], T[4], ok2);
        B := HexByte(T[5], T[6], ok3);
      end;
    8:
      begin
        R := HexByte(T[1], T[2], ok1);
        G := HexByte(T[3], T[4], ok2);
        B := HexByte(T[5], T[6], ok3);
        A := HexByte(T[7], T[8], ok4);
      end;
  else
    raise Exception.CreateFmt('Invalid color length: %s', [S]);
  end;
  if not (ok1 and ok2 and ok3 and ok4) then
    raise Exception.CreateFmt('Invalid hex in color: %s', [S]);
  Result := TyRGBA(Byte(R), Byte(G), Byte(B), Byte(A));
end;

function TyLighten(c: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // each channel = ch + (255 - ch) * (Pct/100); alpha preserved
  f := Pct / 100;
  Result := TyRGBA(
    ClampByte(TyRedOf(c)   + (255 - TyRedOf(c))   * f),
    ClampByte(TyGreenOf(c) + (255 - TyGreenOf(c)) * f),
    ClampByte(TyBlueOf(c)  + (255 - TyBlueOf(c))  * f),
    TyAlphaOf(c));
end;

function TyDarken(c: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // each channel = ch * (1 - Pct/100); alpha preserved
  f := 1 - (Pct / 100);
  Result := TyRGBA(
    ClampByte(TyRedOf(c)   * f),
    ClampByte(TyGreenOf(c) * f),
    ClampByte(TyBlueOf(c)  * f),
    TyAlphaOf(c));
end;

function TyAlpha(c: TTyColor; A: Single): TTyColor;
begin
  // replace alpha with A (0..1 -> 0..255); rgb preserved
  Result := TyRGBA(TyRedOf(c), TyGreenOf(c), TyBlueOf(c), ClampByte(A * 255));
end;

function TyMix(c1, c2: TTyColor; Pct: Single): TTyColor;
var f: Single;
begin
  // result = c1*(1-f) + c2*f where f = Pct/100 (Pct is amount of c2)
  f := Pct / 100;
  Result := TyRGBA(
    ClampByte(TyRedOf(c1)   * (1 - f) + TyRedOf(c2)   * f),
    ClampByte(TyGreenOf(c1) * (1 - f) + TyGreenOf(c2) * f),
    ClampByte(TyBlueOf(c1)  * (1 - f) + TyBlueOf(c2)  * f),
    ClampByte(TyAlphaOf(c1) * (1 - f) + TyAlphaOf(c2) * f));
end;

end.
```

- [ ] **Step 5: Run the test runner expecting PASS for `TTestCssValuesColors`.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build succeeds and all 7 methods of `TTestCssValuesColors` pass (Number of errors: 0, failures: 0 for this suite).

- [ ] **Step 6: Commit.** Run `git add source/tyControls.Css.Values.pas tests/test.Css.Values.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add CSS color primitives TyParseColor/Lighten/Darken/Alpha/Mix"`.

### Task ENGINE-RESOLVE.2: Expression evaluation — TyEvalColor, TyEvalLength, TyEvalFloat with var() and nested funcs

**Files:**
- Modify: `/Users/tom/Projects/TyControls/source/tyControls.Css.Values.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/test.Css.Values.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/tytests.lpr`

- [ ] **Step 1: Add failing eval tests to `test.Css.Values.pas`.** Add a second test class and register it; insert this class declaration after the existing one in the interface:
```pascal
  TTestCssValuesEval = class(TTestCase)
  private
    FVars: TStringList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEvalDirectColor;
    procedure TestEvalVarColor;
    procedure TestEvalNestedLightenVar;
    procedure TestEvalMixVars;
    procedure TestEvalLengthPx;
    procedure TestEvalLengthVar;
    procedure TestEvalFloat;
  end;
```
and add the implementation block before the `initialization` line:
```pascal
procedure TTestCssValuesEval.SetUp;
begin
  FVars := TStringList.Create;
  FVars.Values['accent'] := '#3B82F6';
  FVars.Values['surface'] := '#404040';
  FVars.Values['radius'] := '6px';
end;

procedure TTestCssValuesEval.TearDown;
begin
  FVars.Free;
end;

procedure TTestCssValuesEval.TestEvalDirectColor;
var c: TTyColor;
begin
  c := TyEvalColor('#FF8800', FVars);
  AssertEquals('red', $FF, TyRedOf(c));
  AssertEquals('green', $88, TyGreenOf(c));
  AssertEquals('blue', $00, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalVarColor;
var c: TTyColor;
begin
  c := TyEvalColor('var(--accent)', FVars);
  AssertEquals('red', $3B, TyRedOf(c));
  AssertEquals('green', $82, TyGreenOf(c));
  AssertEquals('blue', $F6, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalNestedLightenVar;
var c: TTyColor;
begin
  // surface=#404040=64; lighten 50% -> 64 + (255-64)*0.5 = 159.5 -> 160
  c := TyEvalColor('lighten(var(--surface), 50%)', FVars);
  AssertEquals('red', 160, TyRedOf(c));
  AssertEquals('green', 160, TyGreenOf(c));
  AssertEquals('blue', 160, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalMixVars;
var c: TTyColor;
begin
  // mix(#404040, #3B82F6, 0%) -> 0% of c2 -> equals c1
  c := TyEvalColor('mix(var(--surface), var(--accent), 0%)', FVars);
  AssertEquals('red', $40, TyRedOf(c));
  AssertEquals('green', $40, TyGreenOf(c));
  AssertEquals('blue', $40, TyBlueOf(c));
end;

procedure TTestCssValuesEval.TestEvalLengthPx;
begin
  AssertEquals('length', 12, TyEvalLength('12px', FVars));
end;

procedure TTestCssValuesEval.TestEvalLengthVar;
begin
  AssertEquals('var length', 6, TyEvalLength('var(--radius)', FVars));
end;

procedure TTestCssValuesEval.TestEvalFloat;
begin
  AssertTrue('float 0.5', Abs(TyEvalFloat('0.5', FVars) - 0.5) < 0.0001);
end;
```
Then change the `initialization` block to also register the new class:
```pascal
initialization
  RegisterTest(TTestCssValuesColors);
  RegisterTest(TTestCssValuesEval);
```

- [ ] **Step 2: Run the test runner expecting FAILURE.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `TyEvalColor`, `TyEvalLength`, `TyEvalFloat` are not yet declared in `tyControls.Css.Values`.

- [ ] **Step 3: Add the three eval function declarations to the interface of `tyControls.Css.Values.pas`.** Insert after the existing `function TyMix(...)` line in the interface:
```pascal
function TyEvalColor(const Expr: string; Vars: TStrings): TTyColor;  // resolves var()/funcs
function TyEvalLength(const Expr: string; Vars: TStrings): Integer;  // '6px'->6, var() ok
function TyEvalFloat(const Expr: string; Vars: TStrings): Single;    // '0.5'
// Exported so tyControls.StyleModel can split gradient/function arg lists with
// nested parens (e.g. 'lighten(--accent, 16%)') without mis-splitting commas.
procedure SplitArgs(const ArgStr: string; Args: TStrings);
```

- [ ] **Step 4: Add the eval implementation to `tyControls.Css.Values.pas`.** Insert this block before the final `end.`:
```pascal
// --- expression evaluation -------------------------------------------------

// Resolve var(--name) -> the raw string from Vars (name without leading --).
// Vars holds entries 'name=value'; var(--accent) looks up 'accent'.
function ResolveVarRef(const Expr: string; Vars: TStrings): string;
var
  inner, key: string;
begin
  inner := Trim(Copy(Expr, 5, Length(Expr) - 5)); // strip 'var(' .. ')'
  if (Length(inner) >= 2) and (inner[1] = '-') and (inner[2] = '-') then
    key := Copy(inner, 3, Length(inner) - 2)
  else
    key := inner;
  if Vars = nil then
    raise Exception.CreateFmt('var(%s) but no vars provided', [inner]);
  if Vars.IndexOfName(key) < 0 then
    raise Exception.CreateFmt('Undefined variable: --%s', [key]);
  Result := Vars.Values[key];
end;

// Split the comma-separated argument list of a function call, honoring nested parens.
procedure SplitArgs(const ArgStr: string; Args: TStrings);
var
  i, depth, start: Integer;
begin
  Args.Clear;
  depth := 0;
  start := 1;
  for i := 1 to Length(ArgStr) do
  begin
    case ArgStr[i] of
      '(': Inc(depth);
      ')': Dec(depth);
      ',':
        if depth = 0 then
        begin
          Args.Add(Trim(Copy(ArgStr, start, i - start)));
          start := i + 1;
        end;
    end;
  end;
  if start <= Length(ArgStr) then
    Args.Add(Trim(Copy(ArgStr, start, Length(ArgStr) - start + 1)));
end;

// Parse a percentage/number token like '8%' or '50' into a Single.
function ParsePctOrNum(const S: string): Single;
var
  T: string;
  fmt: TFormatSettings;
begin
  T := Trim(S);
  if (T <> '') and (T[Length(T)] = '%') then
    T := Trim(Copy(T, 1, Length(T) - 1));
  fmt := DefaultFormatSettings;
  fmt.DecimalSeparator := '.';
  Result := StrToFloat(T, fmt);
end;

function TyEvalColor(const Expr: string; Vars: TStrings): TTyColor;
var
  E, fn, body: string;
  p: Integer;
  args: TStringList;
begin
  E := Trim(Expr);
  if E = '' then
    raise Exception.Create('Empty color expression');
  // direct hex
  if E[1] = '#' then
    Exit(TyParseColor(E));
  // var(...)
  if (Length(E) >= 4) and (LowerCase(Copy(E, 1, 4)) = 'var(') and (E[Length(E)] = ')') then
    Exit(TyEvalColor(ResolveVarRef(E, Vars), Vars));
  // function call: name( args )
  p := Pos('(', E);
  if (p > 0) and (E[Length(E)] = ')') then
  begin
    fn := LowerCase(Trim(Copy(E, 1, p - 1)));
    body := Copy(E, p + 1, Length(E) - p - 1);
    args := TStringList.Create;
    try
      SplitArgs(body, args);
      if (fn = 'lighten') and (args.Count = 2) then
        Exit(TyLighten(TyEvalColor(args[0], Vars), ParsePctOrNum(args[1])));
      if (fn = 'darken') and (args.Count = 2) then
        Exit(TyDarken(TyEvalColor(args[0], Vars), ParsePctOrNum(args[1])));
      if (fn = 'alpha') and (args.Count = 2) then
        Exit(TyAlpha(TyEvalColor(args[0], Vars), ParsePctOrNum(args[1])));
      if (fn = 'mix') and (args.Count = 3) then
        Exit(TyMix(TyEvalColor(args[0], Vars), TyEvalColor(args[1], Vars), ParsePctOrNum(args[2])));
      raise Exception.CreateFmt('Unknown color function: %s/%d', [fn, args.Count]);
    finally
      args.Free;
    end;
  end;
  // bare '--name' leaf: look up in Vars and recurse
  if (Length(E) >= 2) and (E[1] = '-') and (E[2] = '-') then
    Exit(TyEvalColor(Vars.Values[Copy(E, 3, MaxInt)], Vars));
  raise Exception.CreateFmt('Cannot evaluate color: %s', [Expr]);
end;

function TyEvalLength(const Expr: string; Vars: TStrings): Integer;
var
  E: string;
begin
  E := Trim(Expr);
  if (Length(E) >= 4) and (LowerCase(Copy(E, 1, 4)) = 'var(') and (E[Length(E)] = ')') then
    E := Trim(ResolveVarRef(E, Vars));
  // bare '--name' leaf: look up in Vars and recurse
  if (Length(E) >= 2) and (E[1] = '-') and (E[2] = '-') then
    Exit(TyEvalLength(Vars.Values[Copy(E, 3, MaxInt)], Vars));
  if (Length(E) >= 2) and (LowerCase(Copy(E, Length(E) - 1, 2)) = 'px') then
    E := Trim(Copy(E, 1, Length(E) - 2));
  Result := Round(ParsePctOrNum(E));
end;

function TyEvalFloat(const Expr: string; Vars: TStrings): Single;
var
  E: string;
begin
  E := Trim(Expr);
  if (Length(E) >= 4) and (LowerCase(Copy(E, 1, 4)) = 'var(') and (E[Length(E)] = ')') then
    E := Trim(ResolveVarRef(E, Vars));
  // bare '--name' leaf: look up in Vars and recurse
  if (Length(E) >= 2) and (E[1] = '-') and (E[2] = '-') then
    Exit(TyEvalFloat(Vars.Values[Copy(E, 3, MaxInt)], Vars));
  Result := ParsePctOrNum(E);
end;
```

- [ ] **Step 5: Run the test runner expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build succeeds; both `TTestCssValuesColors` (7) and `TTestCssValuesEval` (7) pass with 0 failures/errors.

- [ ] **Step 6: Commit.** Run `git add source/tyControls.Css.Values.pas tests/test.Css.Values.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): evaluate CSS color/length/float exprs with var() and nested funcs"`.

### Task ENGINE-RESOLVE.3: Property dispatch — map a CSS declaration onto a TTyStyleSet field + Present flag

**Files:**
- Create: `/Users/tom/Projects/TyControls/source/tyControls.StyleModel.pas`
- Create: `/Users/tom/Projects/TyControls/tests/test.StyleModel.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/tytests.lpr`

This task builds the lowest layer of `StyleModel`: a single-declaration dispatcher and `TyMergeStyleSet`. The class skeleton with `Clear`/`LoadFromCss`/`LoadFromFile`/`ResolveStyle` stubs is created so the interface is final; full parsing/resolution lands in Task .4 and .5.

- [ ] **Step 1: Create `test.StyleModel.pas` with failing dispatch + merge tests.** Write the complete unit:
```pascal
unit test.StyleModel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Types, tyControls.StyleModel;
type
  TTestStyleMerge = class(TTestCase)
  published
    procedure TestMergeUnionPresent;
    procedure TestMergeOverlaysOnlyPresent;
  end;
implementation

procedure TTestStyleMerge.TestMergeUnionPresent;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  base.Present := [tpTextColor];
  base.TextColor := TyRGB($FF, $FF, $FF);
  over := EmptyStyleSet;
  over.Present := [tpBorderWidth];
  over.BorderWidth := 2;
  TyMergeStyleSet(base, over);
  AssertTrue('textcolor still present', tpTextColor in base.Present);
  AssertTrue('borderwidth now present', tpBorderWidth in base.Present);
  AssertEquals('borderwidth value', 2, base.BorderWidth);
  AssertEquals('textcolor preserved', Integer(TyRGB($FF, $FF, $FF)), Integer(base.TextColor));
end;

procedure TTestStyleMerge.TestMergeOverlaysOnlyPresent;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  base.Present := [tpBorderWidth];
  base.BorderWidth := 1;
  over := EmptyStyleSet;
  over.Present := [];          // nothing present -> base unchanged
  over.BorderWidth := 99;
  TyMergeStyleSet(base, over);
  AssertEquals('borderwidth unchanged', 1, base.BorderWidth);
end;

initialization
  RegisterTest(TTestStyleMerge);
end.
```

- [ ] **Step 2: Add `test.StyleModel` to the `uses` clause of `/tests/tytests.lpr`.** Insert `test.StyleModel` into the runner's uses list.

- [ ] **Step 3: Run the test runner expecting BUILD FAILURE.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `tyControls.StyleModel` does not exist.

- [ ] **Step 4: Create `tyControls.StyleModel.pas` with the merge routine, the per-declaration dispatcher, and stub class methods.** Write the complete unit:
```pascal
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
```

- [ ] **Step 5: Run the test runner expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build succeeds; `TTestStyleMerge` (2 methods) passes with 0 failures/errors.

- [ ] **Step 6: Commit.** Run `git add source/tyControls.StyleModel.pas tests/test.StyleModel.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add StyleModel TyMergeStyleSet + per-declaration property dispatch"`.

### Task ENGINE-RESOLVE.4: LoadFromCss — parse stylesheet into (typeName,variant,state) lookup entries, incl. gradient & nine-slice fills

**Files:**
- Modify: `/Users/tom/Projects/TyControls/source/tyControls.StyleModel.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/test.StyleModel.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/tytests.lpr`

- [ ] **Step 1: Add failing load tests to `test.StyleModel.pas`.** Add this class to the interface (after `TTestStyleMerge`):
```pascal
  TTestStyleLoad = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoadSolidBackgroundResolvesVar;
    procedure TestLoadGradientBackground;
    procedure TestLoadNineSliceBackgroundImage;
  end;
```
and add the implementation before the `initialization` line:
```pascal
const
  CSS_LOAD =
    ':root {' + LineEnding +
    '  --accent: #3B82F6;' + LineEnding +
    '  --surface: #1E1E1E;' + LineEnding +
    '}' + LineEnding +
    'TyButton {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '}' + LineEnding +
    'TyButton.primary {' + LineEnding +
    '  background: linear-gradient(90deg, #000000, #FFFFFF);' + LineEnding +
    '}' + LineEnding +
    'TyPanel {' + LineEnding +
    '  background-image: url(panel.png) slice(4 5 6 7);' + LineEnding +
    '}' + LineEnding;

procedure TTestStyleLoad.SetUp;
begin
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss(CSS_LOAD);
end;

procedure TTestStyleLoad.TearDown;
begin
  FModel.Free;
end;

procedure TTestStyleLoad.TestLoadSolidBackgroundResolvesVar;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertTrue('bg present', tpBackground in s.Present);
  AssertTrue('solid kind', s.Background.Kind = tfkSolid);
  // #1E1E1E
  AssertEquals('bg red', $1E, TyRedOf(s.Background.Color));
  AssertEquals('bg green', $1E, TyGreenOf(s.Background.Color));
  AssertEquals('bg blue', $1E, TyBlueOf(s.Background.Color));
end;

procedure TTestStyleLoad.TestLoadGradientBackground;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', 'primary', []);
  AssertTrue('gradient kind', s.Background.Kind = tfkLinearGradient);
  AssertEquals('grad from red', $00, TyRedOf(s.Background.GradFrom));
  AssertEquals('grad to red', $FF, TyRedOf(s.Background.GradTo));
  AssertTrue('grad angle 90', Abs(s.Background.GradAngleDeg - 90) < 0.01);
end;

procedure TTestStyleLoad.TestLoadNineSliceBackgroundImage;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyPanel', '', []);
  AssertTrue('nineslice kind', s.Background.Kind = tfkNineSlice);
  AssertEquals('image path', 'panel.png', s.Background.ImagePath);
  AssertEquals('slice top', 4, s.Background.SliceInsets.Top);
  AssertEquals('slice right', 5, s.Background.SliceInsets.Right);
  AssertEquals('slice bottom', 6, s.Background.SliceInsets.Bottom);
  AssertEquals('slice left', 7, s.Background.SliceInsets.Left);
end;
```
Then update `initialization` to also register the new class:
```pascal
initialization
  RegisterTest(TTestStyleMerge);
  RegisterTest(TTestStyleLoad);
```

- [ ] **Step 2: Run the test runner expecting FAILURE.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build succeeds but `TTestStyleLoad` tests FAIL (the stub `LoadFromCss` clears, so `ResolveStyle` returns EmptyStyleSet -> `tpBackground in s.Present` is False).

- [ ] **Step 3: Add fill-parsing helpers to the implementation of `tyControls.StyleModel.pas`.** Insert this block immediately before `function TyApplyDeclaration(`:
```pascal
// Parse 'linear-gradient(<angle>deg, <colorA>, <colorB>)' into a gradient fill.
function ParseLinearGradient(const ARaw: string; Vars: TStrings): TTyFill;
var
  inner, angleTok: string;
  p, q: Integer;
  parts: TStringList;
  fmt: TFormatSettings;
begin
  Result.Kind := tfkLinearGradient;
  Result.Color := tyTransparent;
  Result.ImagePath := '';
  Result.SliceInsets := Rect(0, 0, 0, 0);
  Result.GradAngleDeg := 0;
  p := Pos('(', ARaw);
  q := Length(ARaw);
  while (q > p) and (ARaw[q] <> ')') do Dec(q);
  inner := Copy(ARaw, p + 1, q - p - 1);
  parts := TStringList.Create;
  try
    // angle, colorA, colorB; nested-paren-aware so function color args with
    // inner commas (e.g. 'lighten(--accent, 16%)') are not mis-split.
    SplitArgs(inner, parts);
    if parts.Count <> 3 then
      raise Exception.CreateFmt('Invalid linear-gradient: %s', [ARaw]);
    angleTok := LowerCase(Trim(parts[0]));
    if (Length(angleTok) >= 3) and (Copy(angleTok, Length(angleTok) - 2, 3) = 'deg') then
      angleTok := Trim(Copy(angleTok, 1, Length(angleTok) - 3));
    fmt := DefaultFormatSettings;
    fmt.DecimalSeparator := '.';
    Result.GradAngleDeg := StrToFloat(angleTok, fmt);
    Result.GradFrom := TyEvalColor(Trim(parts[1]), Vars);
    Result.GradTo := TyEvalColor(Trim(parts[2]), Vars);
  finally
    parts.Free;
  end;
end;

// Parse 'url(path) slice(t r b l)' into a nine-slice fill.
function ParseNineSlice(const ARaw: string): TTyFill;
var
  lo, urlInner, sliceInner: string;
  pu, qu, ps, qs: Integer;
  nums: TStringList;
  t, r, b, l: Integer;
begin
  Result.Kind := tfkNineSlice;
  Result.Color := tyTransparent;
  Result.GradAngleDeg := 0;
  lo := ARaw;
  pu := Pos('url(', LowerCase(lo));
  if pu = 0 then raise Exception.CreateFmt('background-image needs url(): %s', [ARaw]);
  qu := pu + 4;
  while (qu <= Length(lo)) and (lo[qu] <> ')') do Inc(qu);
  urlInner := Trim(Copy(lo, pu + 4, qu - (pu + 4)));
  // strip optional quotes
  if (Length(urlInner) >= 2) and ((urlInner[1] = '''') or (urlInner[1] = '"')) then
    urlInner := Copy(urlInner, 2, Length(urlInner) - 2);
  Result.ImagePath := urlInner;
  ps := Pos('slice(', LowerCase(lo));
  if ps = 0 then raise Exception.CreateFmt('background-image needs slice(): %s', [ARaw]);
  qs := ps + 6;
  while (qs <= Length(lo)) and (lo[qs] <> ')') do Inc(qs);
  sliceInner := Trim(Copy(lo, ps + 6, qs - (ps + 6)));
  nums := TStringList.Create;
  try
    nums.Delimiter := ' ';
    nums.StrictDelimiter := False; // collapse runs of spaces
    nums.DelimitedText := sliceInner;
    if nums.Count <> 4 then
      raise Exception.CreateFmt('slice() needs 4 values: %s', [ARaw]);
    t := StrToInt(Trim(nums[0]));
    r := StrToInt(Trim(nums[1]));
    b := StrToInt(Trim(nums[2]));
    l := StrToInt(Trim(nums[3]));
    Result.SliceInsets := Rect(l, t, r, b); // TRect = Left,Top,Right,Bottom
  finally
    nums.Free;
  end;
end;
```

- [ ] **Step 4: Extend `TyApplyDeclaration` to handle gradient backgrounds, `shadow`, and `background-image`.** Replace the existing `background` branch and add two branches. In `tyControls.StyleModel.pas`, replace this block:
```pascal
  if prop = 'background' then
  begin
    fill := AStyle.Background;
    fill.Kind := tfkSolid;
    fill.Color := TyEvalColor(raw, Vars);
    AStyle.Background := fill;
    Include(AStyle.Present, tpBackground);
  end
```
with:
```pascal
  if prop = 'background' then
  begin
    if LowerCase(Copy(raw, 1, 16)) = 'linear-gradient(' then
      AStyle.Background := ParseLinearGradient(raw, Vars)
    else
    begin
      fill := AStyle.Background;
      fill.Kind := tfkSolid;
      fill.Color := TyEvalColor(raw, Vars);
      fill.ImagePath := '';
      AStyle.Background := fill;
    end;
    Include(AStyle.Present, tpBackground);
  end
  else if prop = 'background-image' then
  begin
    AStyle.Background := ParseNineSlice(raw);
    Include(AStyle.Present, tpBackground);
  end
  else if prop = 'shadow' then
  begin
    // shadow: <offsetX> <offsetY> <blur> <color>  (logical px)
    ApplyShadow(AStyle, raw, Vars);
    Include(AStyle.Present, tpShadow);
  end
```

- [ ] **Step 5: Add the `ApplyShadow` helper used above.** Insert this block immediately before `function TyApplyDeclaration(` in `tyControls.StyleModel.pas`:
```pascal
// Parse 'shadow: <offX> <offY> <blur> <color>' (logical px + color expr).
procedure ApplyShadow(var AStyle: TTyStyleSet; const ARaw: string; Vars: TStrings);
var
  parts: TStringList;
  i: Integer;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := False;
    parts.DelimitedText := Trim(ARaw);
    for i := parts.Count - 1 downto 0 do
      if Trim(parts[i]) = '' then parts.Delete(i);
    if parts.Count <> 4 then
      raise Exception.CreateFmt('Invalid shadow: %s', [ARaw]);
    AStyle.ShadowOffset.X := TyEvalLength(parts[0], Vars);
    AStyle.ShadowOffset.Y := TyEvalLength(parts[1], Vars);
    AStyle.ShadowBlur := TyEvalLength(parts[2], Vars);
    AStyle.ShadowColor := TyEvalColor(parts[3], Vars);
  finally
    parts.Free;
  end;
end;
```

- [ ] **Step 6: Implement `LoadFromCss` to parse and populate lookup entries.** Replace the stub body:
```pascal
procedure TTyStyleModel.LoadFromCss(const ASource: string);
begin
  // implemented in Task .4
  Clear;
end;
```
with:
```pascal
procedure TTyStyleModel.LoadFromCss(const ASource: string);
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  ri, si, di: Integer;
  rule: TTyCssRule;
  sel: TTyCssSelector;
  decl: TTyCssDeclaration;
  st: TTyStyleSet;
begin
  Clear;
  parser := TTyCssParser.Create(ASource);
  try
    sheet := parser.Parse;
    try
      // copy :root vars (already stored name=value, no leading --)
      FVars.Assign(sheet.RootVars);
      for ri := 0 to sheet.Rules.Count - 1 do
      begin
        rule := TTyCssRule(sheet.Rules[ri]);
        // build the style set once from this rule's declarations
        st := EmptyStyleSet;
        for di := 0 to High(rule.Declarations) do
        begin
          decl := rule.Declarations[di];
          TyApplyDeclaration(st, decl.Prop, decl.RawValue, FVars);
        end;
        // register it for every selector in this rule
        for si := 0 to High(rule.Selectors) do
        begin
          sel := rule.Selectors[si];
          AddEntry(sel.TypeName, sel.Variant, sel.HasState, sel.State, st);
        end;
      end;
    finally
      sheet.Free;
    end;
  finally
    parser.Free;
  end;
end;
```

- [ ] **Step 7: Temporarily implement `ResolveStyle` enough for load tests (single exact lookup).** Replace the stub:
```pascal
function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
begin
  // implemented in Task .5
  Result := EmptyStyleSet;
end;
```
with a base+single-variant lookup (the full fixed-order merge replaces this in Task .5):
```pascal
function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
var
  found: TTyStyleSet;
  variant: string;
begin
  Result := EmptyStyleSet;
  if FindStyle(ATypeKey, '', False, tysNormal, found) then
    TyMergeStyleSet(Result, found);
  variant := Trim(AStyleClass);
  if variant <> '' then
    if FindStyle(ATypeKey, variant, False, tysNormal, found) then
      TyMergeStyleSet(Result, found);
end;
```

- [ ] **Step 8: Run the test runner expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build succeeds; `TTestStyleMerge` (2) and `TTestStyleLoad` (3) pass with 0 failures/errors.

- [ ] **Step 9: Commit.** Run `git add source/tyControls.StyleModel.pas tests/test.StyleModel.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): StyleModel.LoadFromCss builds lookup entries incl gradient/nine-slice/shadow"`.

### Task ENGINE-RESOLVE.5: ResolveStyle — exact fixed-order merge across base, variants, and state layers

**Files:**
- Modify: `/Users/tom/Projects/TyControls/source/tyControls.StyleModel.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/test.StyleModel.pas`
- Modify: `/Users/tom/Projects/TyControls/tests/tytests.lpr`

- [ ] **Step 1: Add failing resolve-order tests to `test.StyleModel.pas`.** Add this class to the interface (after `TTestStyleLoad`):
```pascal
  TTestStyleResolve = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestButtonNormal;
    procedure TestButtonPrimary;
    procedure TestButtonHover;
    procedure TestButtonDisabled;
    procedure TestPrimaryHoverCombo;
    procedure TestStateOrderDisabledWinsOverHover;
  end;
```
and add the implementation before the `initialization` line:
```pascal
const
  CSS_RESOLVE =
    ':root {' + LineEnding +
    '  --accent: #3B82F6;' + LineEnding +
    '  --surface: #404040;' + LineEnding +
    '}' + LineEnding +
    'TyButton {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: #FFFFFF;' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: 6px;' + LineEnding +
    '}' + LineEnding +
    'TyButton.primary {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '}' + LineEnding +
    'TyButton:hover {' + LineEnding +
    '  background: lighten(var(--surface), 50%);' + LineEnding +
    '}' + LineEnding +
    'TyButton.primary:hover {' + LineEnding +
    '  border-width: 3px;' + LineEnding +
    '}' + LineEnding +
    'TyButton:disabled {' + LineEnding +
    '  opacity: 0.5;' + LineEnding +
    '  background: #111111;' + LineEnding +
    '}' + LineEnding;

procedure TTestStyleResolve.SetUp;
begin
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss(CSS_RESOLVE);
end;

procedure TTestStyleResolve.TearDown;
begin
  FModel.Free;
end;

procedure TTestStyleResolve.TestButtonNormal;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertTrue('bg present', tpBackground in s.Present);
  AssertTrue('color present', tpTextColor in s.Present);
  AssertTrue('borderwidth present', tpBorderWidth in s.Present);
  AssertTrue('radius present', tpBorderRadius in s.Present);
  // surface #404040
  AssertEquals('bg red', $40, TyRedOf(s.Background.Color));
  AssertEquals('text white', $FF, TyRedOf(s.TextColor));
  AssertEquals('borderwidth', 1, s.BorderWidth);
  AssertEquals('radius', 6, s.BorderRadius);
end;

procedure TTestStyleResolve.TestButtonPrimary;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', 'primary', []);
  // variant overrides background to accent #3B82F6 but keeps base color/border
  AssertEquals('bg red accent', $3B, TyRedOf(s.Background.Color));
  AssertEquals('bg green accent', $82, TyGreenOf(s.Background.Color));
  AssertEquals('bg blue accent', $F6, TyBlueOf(s.Background.Color));
  AssertEquals('inherited text white', $FF, TyRedOf(s.TextColor));
  AssertEquals('inherited borderwidth', 1, s.BorderWidth);
end;

procedure TTestStyleResolve.TestButtonHover;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', [tysHover]);
  // hover overrides bg to lighten(#404040,50%) = 160
  AssertEquals('hover bg', 160, TyRedOf(s.Background.Color));
  // base props still present
  AssertEquals('text still white', $FF, TyRedOf(s.TextColor));
end;

procedure TTestStyleResolve.TestButtonDisabled;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', [tysDisabled]);
  AssertTrue('opacity present', tpOpacity in s.Present);
  AssertTrue('opacity 0.5', Abs(s.Opacity - 0.5) < 0.0001);
  // disabled bg #111111
  AssertEquals('disabled bg', $11, TyRedOf(s.Background.Color));
end;

procedure TTestStyleResolve.TestPrimaryHoverCombo;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', 'primary', [tysHover]);
  // TyButton.primary sets bg=accent; TyButton.primary:hover sets borderwidth=3
  AssertEquals('combo borderwidth', 3, s.BorderWidth);
  AssertEquals('combo bg accent red', $3B, TyRedOf(s.Background.Color));
end;

procedure TTestStyleResolve.TestStateOrderDisabledWinsOverHover;
var s: TTyStyleSet;
begin
  // both hover and disabled active: disabled is applied last -> bg #111111
  s := FModel.ResolveStyle('TyButton', '', [tysHover, tysDisabled]);
  AssertEquals('disabled bg wins', $11, TyRedOf(s.Background.Color));
  AssertTrue('opacity from disabled', Abs(s.Opacity - 0.5) < 0.0001);
end;
```
Then update `initialization` to also register the new class:
```pascal
initialization
  RegisterTest(TTestStyleMerge);
  RegisterTest(TTestStyleLoad);
  RegisterTest(TTestStyleResolve);
```

- [ ] **Step 2: Run the test runner expecting FAILURE.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build succeeds but `TTestStyleResolve` tests FAIL (the interim `ResolveStyle` ignores state layers and multi-token variants, so hover/disabled/combo assertions fail).

- [ ] **Step 3: Replace `ResolveStyle` with the full fixed-order merge.** In `tyControls.StyleModel.pas`, replace the entire interim body:
```pascal
function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
var
  found: TTyStyleSet;
  variant: string;
begin
  Result := EmptyStyleSet;
  if FindStyle(ATypeKey, '', False, tysNormal, found) then
    TyMergeStyleSet(Result, found);
  variant := Trim(AStyleClass);
  if variant <> '' then
    if FindStyle(ATypeKey, variant, False, tysNormal, found) then
      TyMergeStyleSet(Result, found);
end;
```
with:
```pascal
function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
const
  // fixed state application order: hover, focused, active, disabled
  cStateOrder: array[0..3] of TTyState = (tysHover, tysFocused, tysActive, tysDisabled);
var
  variants: TStringList;
  found: TTyStyleSet;
  vi, si: Integer;
  v: string;
  st: TTyState;
begin
  Result := EmptyStyleSet;
  variants := TStringList.Create;
  try
    variants.Delimiter := ' ';
    variants.StrictDelimiter := False; // collapse multiple spaces
    variants.DelimitedText := Trim(AStyleClass);
    // 1) type base rule (no variant, no state)
    if FindStyle(ATypeKey, '', False, tysNormal, found) then
      TyMergeStyleSet(Result, found);
    // 2) each variant token, in textual order, base-state rule (TypeName.variant)
    for vi := 0 to variants.Count - 1 do
    begin
      v := Trim(variants[vi]);
      if v = '' then Continue;
      if FindStyle(ATypeKey, v, False, tysNormal, found) then
        TyMergeStyleSet(Result, found);
    end;
    // 3) state layers present in AStates, in fixed order;
    //    for each state apply TypeName:state then each TypeName.variant:state
    for si := 0 to High(cStateOrder) do
    begin
      st := cStateOrder[si];
      if not (st in AStates) then Continue;
      if FindStyle(ATypeKey, '', True, st, found) then
        TyMergeStyleSet(Result, found);
      for vi := 0 to variants.Count - 1 do
      begin
        v := Trim(variants[vi]);
        if v = '' then Continue;
        if FindStyle(ATypeKey, v, True, st, found) then
          TyMergeStyleSet(Result, found);
      end;
    end;
  finally
    variants.Free;
  end;
end;
```

- [ ] **Step 4: Run the test runner expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build succeeds; `TTestStyleMerge` (2), `TTestStyleLoad` (3), and `TTestStyleResolve` (6) all pass with 0 failures/errors.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.StyleModel.pas tests/test.StyleModel.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): ResolveStyle applies exact base->variant->state merge order"`.

---

## P1 · Drawing Primitives TTyPainter (BGRA)

This section implements `tyControls.Painter.pas`, the sole unit that touches `BGRABitmap`/`BGRABitmapTypes`. It owns `TyColorToBGRA`, the `TTyGlyphKind` enum, and the full `TTyPainter` class (BeginPaint/EndPaint/Scale, FillBackground, StrokeBorder, DropShadow, DrawText, DrawGlyph, NineSlice). All logical lengths are 96dpi px and scaled by PPI via `Scale`. Types (`TTyColor`, `TTyFill`, `TTyFillKind`) and the `TyAlphaOf/TyRedOf/TyGreenOf/TyBlueOf` helpers are owned by `tyControls.Types` and referenced via `uses`.

### Task PAINTER.1: TyColorToBGRA conversion + unit skeleton

- **Files:**
  - Create: `/source/tyControls.Painter.pas`
  - Create: `/tests/test.painter.pas`
  - Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the painter unit skeleton with TyColorToBGRA and the glyph enum.** Write `/source/tyControls.Painter.pas`:
```pascal
unit tyControls.Painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Types;

type
  TTyGlyphKind = (tgClose, tgMinimize, tgMaximize, tgRestore, tgCheck,
    tgRadioDot, tgChevronDown, tgArrowUp, tgArrowDown);

  TTyPainter = class
  private
    FBmp: TBGRABitmap;
    FCanvas: TCanvas;
    FRect: TRect;
    FPPI: Integer;
  public
    procedure BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure EndPaint;
    function Scale(ALogical: Integer): Integer;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer);
    procedure StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
    procedure DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
    procedure DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean);
    procedure DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer);
    procedure NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect);
    property Bitmap: TBGRABitmap read FBmp;
  end;

function TyColorToBGRA(c: TTyColor): TBGRAPixel;

implementation

function TyColorToBGRA(c: TTyColor): TBGRAPixel;
begin
  Result := BGRA(TyRedOf(c), TyGreenOf(c), TyBlueOf(c), TyAlphaOf(c));
end;

procedure TTyPainter.BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  FCanvas := ACanvas;
  FRect := ARect;
  if APPI <= 0 then
    FPPI := 96
  else
    FPPI := APPI;
  FBmp := TBGRABitmap.Create(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  FBmp.Fill(BGRAPixelTransparent);
end;

procedure TTyPainter.EndPaint;
begin
  if Assigned(FBmp) then
  begin
    if Assigned(FCanvas) then
      FBmp.Draw(FCanvas, FRect.Left, FRect.Top, False);
    FreeAndNil(FBmp);
  end;
end;

function TTyPainter.Scale(ALogical: Integer): Integer;
begin
  Result := MulDiv(ALogical, FPPI, 96);
end;

procedure TTyPainter.FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer);
begin
end;

procedure TTyPainter.StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
begin
end;

procedure TTyPainter.DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
begin
end;

procedure TTyPainter.DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean);
begin
end;

procedure TTyPainter.DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer);
begin
end;

procedure TTyPainter.NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect);
begin
end;

end.
```

- [ ] **Step 2: Create the test unit with the painter test helper and TyColorToBGRA tests.** Write `/tests/test.painter.pas`. The helper `MakePainter` builds a real LCL `TBitmap`, opens a painter over its canvas at 96 PPI, and returns the device rect; `FreePainter` ends paint and frees the host bitmap. The internal `TBGRABitmap` is reachable via the `Bitmap` property for pixel asserts:
```pascal
unit test.painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter;

type
  TPainterTest = class(TTestCase)
  private
    FHost: TBitmap;
    FPainter: TTyPainter;
    function MakePainter(AWidth, AHeight, APPI: Integer): TRect;
    procedure FreePainter;
    function PixelAt(X, Y: Integer): TBGRAPixel;
  protected
    procedure TearDown; override;
  published
    procedure TestColorToBGRAChannels;
    procedure TestColorToBGRATransparent;
  end;

implementation

function TPainterTest.MakePainter(AWidth, AHeight, APPI: Integer): TRect;
begin
  FHost := TBitmap.Create;
  FHost.SetSize(AWidth, AHeight);
  Result := Rect(0, 0, AWidth, AHeight);
  FPainter := TTyPainter.Create;
  FPainter.BeginPaint(FHost.Canvas, Result, APPI);
end;

procedure TPainterTest.FreePainter;
begin
  if Assigned(FPainter) then
  begin
    FPainter.EndPaint;
    FreeAndNil(FPainter);
  end;
  FreeAndNil(FHost);
end;

function TPainterTest.PixelAt(X, Y: Integer): TBGRAPixel;
begin
  Result := FPainter.Bitmap.GetPixel(X, Y);
end;

procedure TPainterTest.TearDown;
begin
  FreePainter;
  inherited TearDown;
end;

procedure TPainterTest.TestColorToBGRAChannels;
var
  px: TBGRAPixel;
begin
  px := TyColorToBGRA(TyRGBA(10, 20, 30, 200));
  AssertEquals('red', 10, px.red);
  AssertEquals('green', 20, px.green);
  AssertEquals('blue', 30, px.blue);
  AssertEquals('alpha', 200, px.alpha);
end;

procedure TPainterTest.TestColorToBGRATransparent;
var
  px: TBGRAPixel;
begin
  px := TyColorToBGRA(tyTransparent);
  AssertEquals('alpha zero', 0, px.alpha);
end;

initialization
  RegisterTest(TPainterTest);

end.
```

- [ ] **Step 3: Add the test unit to the runner uses clause.** In `/tests/tytests.lpr`, add `test.painter` to the `uses` clause (alongside the existing aggregated test units and the `consoletestrunner` unit) so it is registered before `Application.Run`.

- [ ] **Step 4: Build and run, expecting these two tests to PASS.** Run:
```
lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain
```
Expected: `TPainterTest.TestColorToBGRAChannels` and `TPainterTest.TestColorToBGRATransparent` PASS (TyColorToBGRA, BeginPaint, EndPaint, the test helper, and the runner registration are all in place; no pixel-render asserts yet so no failures).

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyPainter skeleton with TyColorToBGRA"`.

### Task PAINTER.2: FillBackground — solid with rounded corners

- **Files:**
  - Modify: `/source/tyControls.Painter.pas`
  - Test: `/tests/test.painter.pas`

- [ ] **Step 1: Add a failing test for a solid fill center pixel and a clipped corner.** Add these two methods to `TPainterTest` (declare them under `published` and implement them). After a solid `FillBackground` the geometric center must equal the fill color, and a pixel in the extreme top-left corner (outside a large radius) must stay fully transparent:
```pascal
procedure TPainterTest.TestSolidFillCenter;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 10);
  px := PixelAt(20, 20);
  AssertEquals('center red', 255, px.red);
  AssertEquals('center green', 0, px.green);
  AssertEquals('center blue', 0, px.blue);
  AssertEquals('center alpha', 255, px.alpha);
end;

procedure TPainterTest.TestSolidFillCornerTransparent;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(255, 0, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 16);
  px := PixelAt(0, 0);
  AssertEquals('corner alpha transparent', 0, px.alpha);
end;
```

- [ ] **Step 2: Run, expecting the two new tests to FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestSolidFillCenter` and `TPainterTest.TestSolidFillCornerTransparent` FAIL (FillBackground is still an empty body, so the bitmap stays transparent — center alpha is 0, not 255).

- [ ] **Step 3: Implement solid fill with antialiased rounded corners.** Replace the empty `FillBackground` body. For `tfkSolid` with radius 0 use a plain rectangle; with radius > 0 use BGRABitmap's antialiased `FillRoundRectAntialias`. Gradient and nineslice are added in later tasks; for now leave them as a no-op fallthrough so the method compiles:
```pascal
procedure TTyPainter.FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer);
var
  r: Integer;
  px: TBGRAPixel;
begin
  if FBmp = nil then
    Exit;
  r := Scale(ARadiusLogical);
  case AFill.Kind of
    tfkSolid:
      begin
        px := TyColorToBGRA(AFill.Color);
        if r <= 0 then
          FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, px, dmDrawWithTransparency)
        else
          FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, px, []);
      end;
    tfkNone: ;
    tfkLinearGradient: ;
    tfkNineSlice: ;
  end;
end;
```

- [ ] **Step 4: Run, expecting the two new tests to PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestSolidFillCenter` and `TPainterTest.TestSolidFillCornerTransparent` PASS (center is opaque red; the rounded corner at (0,0) is left transparent by the antialiased round-rect), and all earlier tests still PASS.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas` then `git commit -m "feat(tycontrols): implement solid rounded FillBackground in TTyPainter"`.

### Task PAINTER.3: FillBackground — linear gradient

- **Files:**
  - Modify: `/source/tyControls.Painter.pas`
  - Test: `/tests/test.painter.pas`

- [ ] **Step 1: Add a failing test for a vertical gradient.** Add this method to `TPainterTest` (declare under `published`). A 90deg gradient runs top->bottom; the top edge must be near `GradFrom` and the bottom edge near `GradTo`:
```pascal
procedure TPainterTest.TestLinearGradientVertical;
var
  fill: TTyFill;
  top, bottom: TBGRAPixel;
begin
  MakePainter(20, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkLinearGradient;
  fill.GradFrom := TyRGBA(0, 0, 0, 255);
  fill.GradTo := TyRGBA(255, 255, 255, 255);
  fill.GradAngleDeg := 90;
  FPainter.FillBackground(Rect(0, 0, 20, 40), fill, 0);
  top := PixelAt(10, 1);
  bottom := PixelAt(10, 38);
  AssertTrue('top dark', top.red < 60);
  AssertTrue('bottom light', bottom.red > 195);
  AssertEquals('top opaque', 255, top.alpha);
end;
```

- [ ] **Step 2: Run, expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestLinearGradientVertical` FAILS (the `tfkLinearGradient` branch is empty, so the pixels stay transparent — `top.alpha` is 0 and `top.red` reads 0 only by coincidence of transparency, the opaque assert fails).

- [ ] **Step 3: Implement the linear gradient branch with a private angle helper.** Add a private method `GradientEndpoints` to the class declaration (`private procedure GradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);`) and fill the `tfkLinearGradient` case. The angle maps 0deg to left->right and 90deg to top->bottom; endpoints are computed from the rect center along the angle vector:
```pascal
procedure TTyPainter.GradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);
var
  rad, dx, dy, cx, cy, hw, hh, t: Single;
begin
  rad := AAngleDeg * Pi / 180;
  dx := Cos(rad);
  dy := Sin(rad);
  cx := (ARect.Left + ARect.Right) / 2;
  cy := (ARect.Top + ARect.Bottom) / 2;
  hw := (ARect.Right - ARect.Left) / 2;
  hh := (ARect.Bottom - ARect.Top) / 2;
  t := Abs(dx) * hw + Abs(dy) * hh;
  P1.x := cx - dx * t;
  P1.y := cy - dy * t;
  P2.x := cx + dx * t;
  P2.y := cy + dy * t;
end;
```
Then replace the `tfkLinearGradient: ;` line in `FillBackground` with:
```pascal
    tfkLinearGradient:
      begin
        GradientEndpoints(ARect, AFill.GradAngleDeg, p1f, p2f);
        grad := FBmp.CreateLinearGradient(p1f, p2f, TyColorToBGRA(AFill.GradFrom), TyColorToBGRA(AFill.GradTo));
        try
          if r <= 0 then
            FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, grad, dmDrawWithTransparency)
          else
            FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, grad, [rrDefault]);
        finally
          grad.Free;
        end;
      end;
```
Declare the locals at the top of `FillBackground`: `p1f, p2f: TPointF; grad: TBGRACustomScanner;`.

- [ ] **Step 4: Run, expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestLinearGradientVertical` PASSES (top is dark/opaque, bottom is light), all prior tests still PASS.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas` then `git commit -m "feat(tycontrols): add linear-gradient FillBackground to TTyPainter"`.

### Task PAINTER.4: StrokeBorder

- **Files:**
  - Modify: `/source/tyControls.Painter.pas`
  - Test: `/tests/test.painter.pas`

- [ ] **Step 1: Add a failing test asserting a border pixel equals the border color.** Add this method to `TPainterTest` (declare under `published`). Fill green, then stroke a 4px blue border; a pixel on the top edge inside the stroke band must read blue:
```pascal
procedure TPainterTest.TestBorderPixelColor;
var
  fill: TTyFill;
  px: TBGRAPixel;
begin
  MakePainter(40, 40, 96);
  FillChar(fill, SizeOf(fill), 0);
  fill.Kind := tfkSolid;
  fill.Color := TyRGBA(0, 255, 0, 255);
  FPainter.FillBackground(Rect(0, 0, 40, 40), fill, 0);
  FPainter.StrokeBorder(Rect(0, 0, 40, 40), 0, 4, TyRGBA(0, 0, 255, 255));
  px := PixelAt(20, 1);
  AssertTrue('border blue dominant', px.blue > 200);
  AssertTrue('border green low', px.green < 80);
  AssertEquals('border opaque', 255, px.alpha);
end;
```

- [ ] **Step 2: Run, expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestBorderPixelColor` FAILS (StrokeBorder is empty, so the top edge still shows the green fill — `px.blue` is 0, not > 200).

- [ ] **Step 3: Implement StrokeBorder.** Replace the empty body. The stroke is drawn inset by half the width so it stays inside the rect; round-rect uses the antialiased variant:
```pascal
procedure TTyPainter.StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
var
  w, r: Integer;
  half: Single;
  px: TBGRAPixel;
  l, t, rr, b: Single;
begin
  if FBmp = nil then
    Exit;
  w := Scale(AWidthLogical);
  if w <= 0 then
    Exit;
  r := Scale(ARadiusLogical);
  px := TyColorToBGRA(AColor);
  half := w / 2;
  l := ARect.Left + half;
  t := ARect.Top + half;
  rr := ARect.Right - 1 - half;
  b := ARect.Bottom - 1 - half;
  if r <= 0 then
    FBmp.RectangleAntialias(l, t, rr, b, px, w)
  else
    FBmp.RoundRectAntialias(l, t, rr, b, r, r, px, w);
end;
```

- [ ] **Step 4: Run, expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestBorderPixelColor` PASSES (top edge band reads opaque blue), all prior tests still PASS.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas` then `git commit -m "feat(tycontrols): implement StrokeBorder in TTyPainter"`.

### Task PAINTER.5: DropShadow

- **Files:**
  - Modify: `/source/tyControls.Painter.pas`
  - Test: `/tests/test.painter.pas`

- [ ] **Step 1: Add a failing test for a shadow leaving alpha outside the shape.** Add this method to `TPainterTest` (declare under `published`). Drop a shadow offset down-right with blur; a pixel just below-right of the shape rect must pick up partial shadow alpha (it was transparent before):
```pascal
procedure TPainterTest.TestDropShadowAlpha;
var
  px: TBGRAPixel;
begin
  MakePainter(60, 60, 96);
  FPainter.DropShadow(Rect(10, 10, 40, 40), 4, TyRGBA(0, 0, 0, 200), 6, Point(4, 4));
  px := PixelAt(44, 44);
  AssertTrue('shadow alpha present', px.alpha > 0);
  AssertTrue('shadow alpha partial', px.alpha < 200);
end;
```

- [ ] **Step 2: Run, expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestDropShadowAlpha` FAILS (DropShadow is empty; the pixel stays at alpha 0, so `px.alpha > 0` fails).

- [ ] **Step 3: Implement DropShadow via an offscreen blurred round-rect.** Replace the empty body. Paint a filled round-rect of the shadow color into a temporary BGRABitmap, gaussian-blur it, then blit at the offset onto the main bitmap:
```pascal
procedure TTyPainter.DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
var
  r, blur, ox, oy: Integer;
  shadow, blurred: TBGRABitmap;
  px: TBGRAPixel;
begin
  if FBmp = nil then
    Exit;
  r := Scale(ARadiusLogical);
  blur := Scale(ABlurLogical);
  ox := Scale(AOffsetLogical.X);
  oy := Scale(AOffsetLogical.Y);
  px := TyColorToBGRA(AColor);
  shadow := TBGRABitmap.Create(FBmp.Width, FBmp.Height, BGRAPixelTransparent);
  try
    if r <= 0 then
      shadow.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, px, dmSet)
    else
      shadow.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, px, [rrDefault]);
    if blur > 0 then
    begin
      blurred := shadow.FilterBlurRadial(blur, rbFast) as TBGRABitmap;
      try
        FBmp.PutImage(ox, oy, blurred, dmDrawWithTransparency);
      finally
        blurred.Free;
      end;
    end
    else
      FBmp.PutImage(ox, oy, shadow, dmDrawWithTransparency);
  finally
    shadow.Free;
  end;
end;
```

- [ ] **Step 4: Run, expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestDropShadowAlpha` PASSES (the blurred shadow bleeds partial alpha past the shape edge), all prior tests still PASS.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas` then `git commit -m "feat(tycontrols): implement blurred DropShadow in TTyPainter"`.

### Task PAINTER.6: DrawText with scaling, weight, align, ellipsis

- **Files:**
  - Modify: `/source/tyControls.Painter.pas`
  - Test: `/tests/test.painter.pas`

- [ ] **Step 1: Add a failing test that text paints visible pixels of the text color.** Add this method to `TPainterTest` (declare under `published`). Draw black text on a transparent surface and assert that at least one pixel in the text band is opaque-ish dark, proving glyphs were rasterized:
```pascal
procedure TPainterTest.TestDrawTextRastersPixels;
var
  x, y, hits: Integer;
  px: TBGRAPixel;
begin
  MakePainter(120, 40, 96);
  FPainter.DrawText(Rect(0, 0, 120, 40), 'Ty', 'DejaVu Sans', 14, 700,
    TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
  hits := 0;
  for y := 0 to 39 do
    for x := 0 to 119 do
    begin
      px := PixelAt(x, y);
      if px.alpha > 100 then
        Inc(hits);
    end;
  AssertTrue('glyph pixels rendered', hits > 0);
end;
```

- [ ] **Step 2: Run, expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestDrawTextRastersPixels` FAILS (DrawText is empty; no opaque pixels, `hits` is 0).

- [ ] **Step 3: Implement DrawText using BGRABitmap font rendering.** Replace the empty body. Configure font name, scaled height (`Scale` of the logical pt converted to px), weight (bold when >= 600), color, and use a private helper to map alignments. Apply ellipsis trimming when the text is wider than the rect:
```pascal
procedure TTyPainter.DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean);
var
  style: TTextStyle;
  s: string;
  sz: TSize;
  px: TBGRAPixel;
  fh: Integer;
begin
  if FBmp = nil then
    Exit;
  px := TyColorToBGRA(AColor);
  FBmp.FontName := AFontName;
  fh := Scale(Round(AFontSizeLogical * 96 / 72));
  FBmp.FontHeight := fh;
  FBmp.FontQuality := fqFineAntialiasing;
  if AWeight >= 600 then
    FBmp.FontStyle := [fsBold]
  else
    FBmp.FontStyle := [];
  s := AText;
  if AEllipsis then
  begin
    sz := FBmp.TextSize(s);
    while (Length(s) > 1) and (sz.cx > (ARect.Right - ARect.Left)) do
    begin
      Delete(s, Length(s), 1);
      sz := FBmp.TextSize(s + '...');
    end;
    if s <> AText then
      s := s + '...';
  end;
  FillChar(style, SizeOf(style), 0);
  style.Alignment := AHAlign;
  style.Layout := AVAlign;
  style.SingleLine := True;
  style.Clipping := True;
  FBmp.TextRect(ARect, ARect.Left, ARect.Top, s, style, px);
end;
```

- [ ] **Step 4: Run, expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestDrawTextRastersPixels` PASSES (`hits` > 0 because the glyphs are rasterized), all prior tests still PASS.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas` then `git commit -m "feat(tycontrols): implement DrawText with scaling and ellipsis in TTyPainter"`.

### Task PAINTER.7: DrawGlyph vector strokes for every TTyGlyphKind

- **Files:**
  - Modify: `/source/tyControls.Painter.pas`
  - Test: `/tests/test.painter.pas`

- [ ] **Step 1: Add a failing test that every glyph kind paints something.** Add this method to `TPainterTest` (declare under `published`). Loop over all glyph kinds; each must rasterize at least one opaque pixel in its box:
```pascal
procedure TPainterTest.TestDrawGlyphAllKinds;
var
  g: TTyGlyphKind;
  x, y, hits: Integer;
  px: TBGRAPixel;
begin
  for g := Low(TTyGlyphKind) to High(TTyGlyphKind) do
  begin
    MakePainter(24, 24, 96);
    FPainter.DrawGlyph(Rect(0, 0, 24, 24), g, TyRGBA(0, 0, 0, 255), 2);
    hits := 0;
    for y := 0 to 23 do
      for x := 0 to 23 do
      begin
        px := PixelAt(x, y);
        if px.alpha > 100 then
          Inc(hits);
      end;
    AssertTrue('glyph ' + IntToStr(Ord(g)) + ' painted', hits > 0);
    FreePainter;
  end;
end;
```

- [ ] **Step 2: Run, expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestDrawGlyphAllKinds` FAILS (DrawGlyph is empty; the first glyph already yields 0 hits).

- [ ] **Step 3: Implement DrawGlyph as antialiased vector strokes per kind.** Replace the empty body. Compute a padded inner box, derive scaled thickness, and stroke/fill each glyph with BGRABitmap antialiased line and shape calls. Every enum case is handled explicitly:
```pascal
procedure TTyPainter.DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer);
var
  px: TBGRAPixel;
  th: Single;
  pad: Integer;
  l, t, r, b, cx, cy, w, h, m: Single;
  pts: array of TPointF;
begin
  if FBmp = nil then
    Exit;
  px := TyColorToBGRA(AColor);
  th := Scale(AThicknessLogical);
  if th < 1 then
    th := 1;
  pad := Scale(4);
  l := ARect.Left + pad;
  t := ARect.Top + pad;
  r := ARect.Right - 1 - pad;
  b := ARect.Bottom - 1 - pad;
  cx := (l + r) / 2;
  cy := (t + b) / 2;
  w := r - l;
  h := b - t;
  m := w;
  if h < m then
    m := h;
  case AGlyph of
    tgClose:
      begin
        FBmp.DrawLineAntialias(l, t, r, b, px, th, True);
        FBmp.DrawLineAntialias(r, t, l, b, px, th, True);
      end;
    tgMinimize:
      FBmp.DrawLineAntialias(l, cy, r, cy, px, th, True);
    tgMaximize:
      FBmp.RectangleAntialias(l, t, r, b, px, th);
    tgRestore:
      begin
        FBmp.RectangleAntialias(l, t + h * 0.25, r - w * 0.25, b, px, th);
        FBmp.DrawPolyLineAntialias([PointF(l + w * 0.25, t + h * 0.25),
          PointF(l + w * 0.25, t), PointF(r, t), PointF(r, b - h * 0.25),
          PointF(r - w * 0.25, b - h * 0.25)], px, th);
      end;
    tgCheck:
      FBmp.DrawPolyLineAntialias([PointF(l, cy), PointF(l + w * 0.35, b),
        PointF(r, t)], px, th);
    tgRadioDot:
      FBmp.FillEllipseAntialias(cx, cy, m * 0.3, m * 0.3, px);
    tgChevronDown:
      FBmp.DrawPolyLineAntialias([PointF(l, t + h * 0.3),
        PointF(cx, b - h * 0.2), PointF(r, t + h * 0.3)], px, th);
    tgArrowUp:
      begin
        FBmp.DrawLineAntialias(cx, b, cx, t, px, th, True);
        FBmp.DrawPolyLineAntialias([PointF(l + w * 0.25, t + h * 0.35),
          PointF(cx, t), PointF(r - w * 0.25, t + h * 0.35)], px, th);
      end;
    tgArrowDown:
      begin
        FBmp.DrawLineAntialias(cx, t, cx, b, px, th, True);
        FBmp.DrawPolyLineAntialias([PointF(l + w * 0.25, b - h * 0.35),
          PointF(cx, b), PointF(r - w * 0.25, b - h * 0.35)], px, th);
      end;
  end;
  pts := nil;
end;
```

- [ ] **Step 4: Run, expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestDrawGlyphAllKinds` PASSES (every glyph rasterizes at least one opaque pixel), all prior tests still PASS.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas` then `git commit -m "feat(tycontrols): implement vector DrawGlyph for all glyph kinds"`.

### Task PAINTER.8: NineSlice image drawing and tfkNineSlice fill

- **Files:**
  - Modify: `/source/tyControls.Painter.pas`
  - Test: `/tests/test.painter.pas`

- [ ] **Step 1: Add a failing test that draws a generated 9-slice image and checks region color.** Add this method to `TPainterTest` (declare under `published`). It writes a small temp PNG whose center is red, calls `NineSlice`, and asserts the stretched center region of the destination is red. A private helper `WriteTempNineSlice` creates the PNG:
```pascal
function TPainterTest.WriteTempNineSlice: string;
var
  bmp: TBGRABitmap;
begin
  Result := GetTempDir(False) + 'tyninetest.png';
  bmp := TBGRABitmap.Create(9, 9, BGRA(0, 0, 255, 255));
  try
    bmp.FillRect(3, 3, 6, 6, BGRA(255, 0, 0, 255), dmSet);
    bmp.SaveToFile(Result);
  finally
    bmp.Free;
  end;
end;

procedure TPainterTest.TestNineSliceCenterRegion;
var
  fn: string;
  px: TBGRAPixel;
begin
  fn := WriteTempNineSlice;
  try
    MakePainter(60, 60, 96);
    FPainter.NineSlice(Rect(0, 0, 60, 60), fn, Rect(3, 3, 3, 3));
    px := PixelAt(30, 30);
    AssertTrue('center red', px.red > 200);
    AssertTrue('center blue low', px.blue < 80);
  finally
    DeleteFile(fn);
  end;
end;
```
Also add the `WriteTempNineSlice: string;` declaration in the `private` section of `TPainterTest`.

- [ ] **Step 2: Run, expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestNineSliceCenterRegion` FAILS (NineSlice is empty; the destination center stays transparent — `px.red` is 0, not > 200).

- [ ] **Step 3: Implement NineSlice and wire tfkNineSlice into FillBackground.** Replace the empty `NineSlice` body. Load the source image, compute the 9 source/destination region rectangles from the insets (insets are image px = `Left,Top,Right,Bottom`), and stretch-blit each region. The `SliceInsets` are device-independent image px and are NOT scaled. Add a private helper `BlitRegion`:
```pascal
procedure TTyPainter.BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect);
var
  part: TBGRABitmap;
begin
  if (ASrcR.Right <= ASrcR.Left) or (ASrcR.Bottom <= ASrcR.Top) then
    Exit;
  if (ADstR.Right <= ADstR.Left) or (ADstR.Bottom <= ADstR.Top) then
    Exit;
  part := ASrc.GetPart(ASrcR) as TBGRABitmap;
  try
    FBmp.StretchPutImage(ADstR, part, dmDrawWithTransparency);
  finally
    part.Free;
  end;
end;

procedure TTyPainter.NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect);
var
  src: TBGRABitmap;
  iw, ih: Integer;
  sl, st, sr, sb: Integer;
  dl, dt, dr, db: Integer;
  sxL, sxR, syT, syB: Integer;
begin
  if FBmp = nil then
    Exit;
  if not FileExists(AImagePath) then
    Exit;
  src := TBGRABitmap.Create(AImagePath);
  try
    iw := src.Width;
    ih := src.Height;
    sl := AInsets.Left;
    st := AInsets.Top;
    sr := AInsets.Right;
    sb := AInsets.Bottom;
    sxL := sl;
    sxR := iw - sr;
    syT := st;
    syB := ih - sb;
    dl := ARect.Left;
    dt := ARect.Top;
    dr := ARect.Right;
    db := ARect.Bottom;
    BlitRegion(src, Rect(0, 0, sxL, syT), Rect(dl, dt, dl + sl, dt + st));
    BlitRegion(src, Rect(sxL, 0, sxR, syT), Rect(dl + sl, dt, dr - sr, dt + st));
    BlitRegion(src, Rect(sxR, 0, iw, syT), Rect(dr - sr, dt, dr, dt + st));
    BlitRegion(src, Rect(0, syT, sxL, syB), Rect(dl, dt + st, dl + sl, db - sb));
    BlitRegion(src, Rect(sxL, syT, sxR, syB), Rect(dl + sl, dt + st, dr - sr, db - sb));
    BlitRegion(src, Rect(sxR, syT, iw, syB), Rect(dr - sr, dt + st, dr, db - sb));
    BlitRegion(src, Rect(0, syB, sxL, ih), Rect(dl, db - sb, dl + sl, db));
    BlitRegion(src, Rect(sxL, syB, sxR, ih), Rect(dl + sl, db - sb, dr - sr, db));
    BlitRegion(src, Rect(sxR, syB, iw, ih), Rect(dr - sr, db - sb, dr, db));
  finally
    src.Free;
  end;
end;
```
Declare both helpers in the class `private` section: `procedure BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect);`. Then replace the `tfkNineSlice: ;` line in `FillBackground` with `tfkNineSlice: NineSlice(ARect, AFill.ImagePath, AFill.SliceInsets);`.

- [ ] **Step 4: Run, expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TPainterTest.TestNineSliceCenterRegion` PASSES (the red center tile is stretched into the destination center, so `px.red` > 200 and `px.blue` < 80), all prior tests still PASS.

- [ ] **Step 5: Commit.** Run `git add source/tyControls.Painter.pas tests/test.painter.pas` then `git commit -m "feat(tycontrols): implement NineSlice drawing and tfkNineSlice fill"`.

---

The directories don't exist yet (this is a greenfield plan). I have the spec and the authoritative contract. I have everything I need to write my section.

## P2 · StyleController + Control Base Classes

### Task CONTROLLER-BASE.1: TTyStyleController component (owns model, registry, theme loading)

**Files:**
- Create: `/source/tyControls.Controller.pas`
- Test: `/tests/test.controller.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit.** Write `/tests/test.controller.pas` exercising `LoadThemeCss` + `ResolveStyle` round-trip and the registry counter.

```pascal
unit test.controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller;
type
  TControllerTest = class(TTestCase)
  published
    procedure TestLoadThemeCssResolves;
    procedure TestDefaultControllerIsSingleton;
  end;
implementation
procedure TControllerTest.TestLoadThemeCssResolves;
var
  c: TTyStyleController;
  s: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss('TyButton { color: #FF0000; border-width: 3px; }');
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertTrue('TextColor present', tpTextColor in s.Present);
    AssertEquals('TextColor value', Integer(TyRGB($FF, $00, $00)), Integer(s.TextColor));
    AssertEquals('BorderWidth value', 3, s.BorderWidth);
  finally
    c.Free;
  end;
end;
procedure TControllerTest.TestDefaultControllerIsSingleton;
begin
  AssertSame('same instance', TyDefaultController, TyDefaultController);
  AssertTrue('not nil', TyDefaultController <> nil);
end;
initialization
  RegisterTest(TControllerTest);
end.
```

- [ ] **Step 2: Add the test unit to the runner uses clause.** In `/tests/tytests.lpr`, add `test.controller` to the `uses` clause (after the existing CSS/style-model test units).
- [ ] **Step 3: Run expecting FAIL (unit does not compile yet).** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `tyControls.Controller` does not exist.
- [ ] **Step 4: Create the controller unit (minimal compilable skeleton).** Write `/source/tyControls.Controller.pas`.

```pascal
unit tyControls.Controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls,
  tyControls.Types, tyControls.StyleModel;
type
  TTyStyleController = class(TComponent)
  private
    FModel: TTyStyleModel;
    FThemeFile: string;
    FControls: TFPList;
    procedure SetThemeFile(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Model: TTyStyleModel read FModel;
    procedure LoadTheme(const AFileName: string);
    procedure LoadThemeCss(const ASource: string);
    procedure RegisterStyleable(AControl: TControl);
    procedure UnregisterStyleable(AControl: TControl);
    procedure Changed;
  published
    property ThemeFile: string read FThemeFile write SetThemeFile;
  end;

function TyDefaultController: TTyStyleController;

implementation

var
  GDefaultController: TTyStyleController = nil;

constructor TTyStyleController.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModel := TTyStyleModel.Create;
  FControls := TFPList.Create;
end;

destructor TTyStyleController.Destroy;
begin
  FControls.Free;
  FModel.Free;
  inherited Destroy;
end;

procedure TTyStyleController.SetThemeFile(const AValue: string);
begin
  if FThemeFile = AValue then Exit;
  FThemeFile := AValue;
  if (AValue <> '') and FileExists(AValue) then
    LoadTheme(AValue);
end;

procedure TTyStyleController.LoadTheme(const AFileName: string);
begin
  FModel.LoadFromFile(AFileName);
  FThemeFile := AFileName;
  Changed;
end;

procedure TTyStyleController.LoadThemeCss(const ASource: string);
begin
  FModel.LoadFromCss(ASource);
  Changed;
end;

procedure TTyStyleController.RegisterStyleable(AControl: TControl);
begin
  if (AControl <> nil) and (FControls.IndexOf(AControl) < 0) then
    FControls.Add(AControl);
end;

procedure TTyStyleController.UnregisterStyleable(AControl: TControl);
var
  i: Integer;
begin
  i := FControls.IndexOf(AControl);
  if i >= 0 then
    FControls.Delete(i);
end;

procedure TTyStyleController.Changed;
var
  i: Integer;
begin
  for i := 0 to FControls.Count - 1 do
    TControl(FControls[i]).Invalidate;
end;

function TyDefaultController: TTyStyleController;
begin
  if GDefaultController = nil then
    GDefaultController := TTyStyleController.Create(nil);
  Result := GDefaultController;
end;

finalization
  FreeAndNil(GDefaultController);
end.
```

- [ ] **Step 5: Run expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TControllerTest.TestLoadThemeCssResolves` and `TControllerTest.TestDefaultControllerIsSingleton` PASS.
- [ ] **Step 6: Commit.** Run `git add source/tyControls.Controller.pas tests/test.controller.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyStyleController with model, registry, and default singleton"`.

### Task CONTROLLER-BASE.2: ITyStyleable + base class shared members (StyleClass, Controller, state queries)

**Files:**
- Create: `/source/tyControls.Base.pas`
- Test: `/tests/test.base.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Write the failing test for CurrentStates.** Write `/tests/test.base.pas` with a minimal in-test descendant that exposes the protected members and asserts the state set tracks `FHover`/`FPressed`/`Enabled`.

```pascal
unit test.base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Base;
type
  TTestStyleControl = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    procedure SetHover(AValue: Boolean);
    procedure SetPressed(AValue: Boolean);
    function PublicCurrentStates: TTyStateSet;
  end;

  TBaseTest = class(TTestCase)
  published
    procedure TestNormalState;
    procedure TestHoverState;
    procedure TestPressedAddsActive;
    procedure TestDisabledState;
    procedure TestStyleTypeKey;
  end;
implementation

function TTestStyleControl.GetStyleTypeKey: string;
begin
  Result := 'TyButton';
end;

procedure TTestStyleControl.SetHover(AValue: Boolean);
begin
  FHover := AValue;
end;

procedure TTestStyleControl.SetPressed(AValue: Boolean);
begin
  FPressed := AValue;
end;

function TTestStyleControl.PublicCurrentStates: TTyStateSet;
begin
  Result := CurrentStates;
end;

procedure TBaseTest.TestNormalState;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    AssertTrue('normal present', tysNormal in ctl.PublicCurrentStates);
    AssertFalse('hover absent', tysHover in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestHoverState;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    ctl.SetHover(True);
    AssertTrue('hover present', tysHover in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestPressedAddsActive;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    ctl.SetPressed(True);
    AssertTrue('active present', tysActive in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestDisabledState;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    ctl.Enabled := False;
    AssertTrue('disabled present', tysDisabled in ctl.PublicCurrentStates);
    AssertFalse('normal absent when disabled', tysNormal in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestStyleTypeKey;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    AssertEquals('typekey', 'TyButton', ctl.GetStyleTypeKey);
  finally
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TBaseTest);
end.
```

- [ ] **Step 2: Add the test unit to the runner uses clause.** In `/tests/tytests.lpr`, add `test.base` to the `uses` clause.
- [ ] **Step 3: Run expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `tyControls.Base` does not exist.
- [ ] **Step 4: Create the base unit with interface, both base classes, and shared members.** Write `/source/tyControls.Base.pas`. Implement `TTyGraphicControl` and `TTyCustomControl` with identical shared bodies, including state tracking overrides and `DrawFrame`.

```pascal
unit tyControls.Base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LMessages, LCLType,
  tyControls.Types, tyControls.Controller, tyControls.StyleModel,
  tyControls.Painter;
type
  ITyStyleable = interface
    ['{A1B2C3D4-0001-0002-0003-00000000TYST}']
    function GetStyleTypeKey: string;
  end;

  TTyGraphicControl = class(TGraphicControl, ITyStyleable)
  private
    FStyleClass: string;
    FController: TTyStyleController;
    procedure SetStyleClass(const AValue: string);
    procedure SetController(AValue: TTyStyleController);
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
  protected
    FHover, FPressed: Boolean;
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet;
    function CurrentStyle: TTyStyleSet;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    destructor Destroy; override;
  published
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
  end;

  TTyCustomControl = class(TCustomControl, ITyStyleable)
  private
    FStyleClass: string;
    FController: TTyStyleController;
    procedure SetStyleClass(const AValue: string);
    procedure SetController(AValue: TTyStyleController);
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
  protected
    FHover, FPressed: Boolean;
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet;
    function CurrentStyle: TTyStyleSet;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    destructor Destroy; override;
  published
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
  end;

implementation

{ TTyGraphicControl }

destructor TTyGraphicControl.Destroy;
begin
  if FController <> nil then
    FController.UnregisterStyleable(Self)
  else
    TyDefaultController.UnregisterStyleable(Self);
  inherited Destroy;
end;

procedure TTyGraphicControl.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Invalidate;
end;

procedure TTyGraphicControl.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then
    FController.UnregisterStyleable(Self)
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyGraphicControl.CMEnabledChanged(var Msg: TLMessage);
begin
  Invalidate;
end;

function TTyGraphicControl.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyGraphicControl.CurrentStates: TTyStateSet;
begin
  Result := [];
  if not Enabled then
  begin
    Include(Result, tysDisabled);
    Exit;
  end;
  if FHover then Include(Result, tysHover);
  if FPressed then Include(Result, tysActive);
  if Result = [] then
    Include(Result, tysNormal);
end;

function TTyGraphicControl.CurrentStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(GetStyleTypeKey, FStyleClass, CurrentStates);
end;

procedure TTyGraphicControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
begin
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, AStyle.BorderRadius);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0) then
    APainter.StrokeBorder(ARect, AStyle.BorderRadius, AStyle.BorderWidth, AStyle.BorderColor);
end;

procedure TTyGraphicControl.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TTyGraphicControl.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TTyGraphicControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
  end;
end;

procedure TTyGraphicControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := False;
    Invalidate;
  end;
end;

{ TTyCustomControl }

destructor TTyCustomControl.Destroy;
begin
  if FController <> nil then
    FController.UnregisterStyleable(Self)
  else
    TyDefaultController.UnregisterStyleable(Self);
  inherited Destroy;
end;

procedure TTyCustomControl.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Invalidate;
end;

procedure TTyCustomControl.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then
    FController.UnregisterStyleable(Self)
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyCustomControl.CMEnabledChanged(var Msg: TLMessage);
begin
  Invalidate;
end;

function TTyCustomControl.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyCustomControl.CurrentStates: TTyStateSet;
begin
  Result := [];
  if not Enabled then
  begin
    Include(Result, tysDisabled);
    Exit;
  end;
  if FHover then Include(Result, tysHover);
  if FPressed then Include(Result, tysActive);
  if Focused then Include(Result, tysFocused);
  if Result = [] then
    Include(Result, tysNormal);
end;

function TTyCustomControl.CurrentStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(GetStyleTypeKey, FStyleClass, CurrentStates);
end;

procedure TTyCustomControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
begin
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, AStyle.BorderRadius);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0) then
    APainter.StrokeBorder(ARect, AStyle.BorderRadius, AStyle.BorderWidth, AStyle.BorderColor);
end;

procedure TTyCustomControl.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TTyCustomControl.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TTyCustomControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
  end;
end;

procedure TTyCustomControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := False;
    Invalidate;
  end;
end;

procedure TTyCustomControl.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TTyCustomControl.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

end.
```

- [ ] **Step 5: Run expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TBaseTest.TestNormalState`, `TestHoverState`, `TestPressedAddsActive`, `TestDisabledState`, `TestStyleTypeKey` PASS.
- [ ] **Step 6: Commit.** Run `git add source/tyControls.Base.pas tests/test.base.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add ITyStyleable and TTyGraphicControl/TTyCustomControl base classes"`.

### Task CONTROLLER-BASE.3: DrawFrame background pixel render (offscreen painter integration)

**Files:**
- Create: `/tests/test.base.drawframe.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Write the failing render test.** Write `/tests/test.base.drawframe.pas`. It builds a solid-fill `TTyStyleSet`, drives `DrawFrame` through a `TTyPainter` rendering into an offscreen `TBGRABitmap` via a `TBitmap` canvas, and asserts the center pixel equals the fill color. Use a local helper descendant to call the protected `DrawFrame`.

```pascal
unit test.base.drawframe;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Painter;
type
  TDrawFrameProbe = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    procedure RunDrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
  end;

  TDrawFrameTest = class(TTestCase)
  published
    procedure TestSolidBackgroundCenterPixel;
  end;
implementation

function TDrawFrameProbe.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

procedure TDrawFrameProbe.RunDrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
begin
  DrawFrame(APainter, ARect, AStyle);
end;

procedure TDrawFrameTest.TestSolidBackgroundCenterPixel;
var
  probe: TDrawFrameProbe;
  painter: TTyPainter;
  bmp: TBitmap;
  style: TTyStyleSet;
  r: TRect;
  px: TBGRAPixel;
  reread: TBGRABitmap;
begin
  bmp := TBitmap.Create;
  probe := TDrawFrameProbe.Create(nil);
  painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);
    style := EmptyStyleSet;
    style.Background.Kind := tfkSolid;
    style.Background.Color := TyRGB($20, $C0, $40);
    Include(style.Present, tpBackground);

    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;

    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(20, 20);
      AssertEquals('red channel', $20, px.red);
      AssertEquals('green channel', $C0, px.green);
      AssertEquals('blue channel', $40, px.blue);
    finally
      reread.Free;
    end;
  finally
    painter.Free;
    probe.Free;
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TDrawFrameTest);
end.
```

- [ ] **Step 2: Add the test unit to the runner uses clause.** In `/tests/tytests.lpr`, add `test.base.drawframe` to the `uses` clause.
- [ ] **Step 3: Run expecting FAIL then PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build SUCCEEDS (base + painter already exist) and `TDrawFrameTest.TestSolidBackgroundCenterPixel` PASSES; if the center pixel does not match the fill color the test FAILS, proving `DrawFrame` routes the background through the painter correctly.
- [ ] **Step 4: Commit.** Run `git add tests/test.base.drawframe.pas tests/tytests.lpr` then `git commit -m "test(tycontrols): verify DrawFrame renders solid background to offscreen bitmap"`.

---

I have the spec and contract. The source/tests dirs don't exist yet (other sections create them). I'll write my section using the exact contract signatures, referencing types from other units via uses. Let me produce the fragment.

## P2 · Controls (1): Button / Label / Edit / CheckBox / RadioButton

### Task CONTROLS-A.1: TTyButton — typeKey, click, paint

**Files:**
- Create: `/source/tyControls.Button.pas`
- Create: `/tests/test.button.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit for TTyButton.** Create `/tests/test.button.pas` with a `TTestCase` that asserts the typeKey and that `OnClick` fires:
  ```pascal
  unit test.button;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
    tyControls.Base, tyControls.Button;
  type
    TButtonTest = class(TTestCase)
    private
      FClicked: Integer;
      procedure HandleClick(Sender: TObject);
    published
      procedure TestTypeKey;
      procedure TestOnClickFires;
      procedure TestPaintSmoke;
    end;
  implementation

  procedure TButtonTest.HandleClick(Sender: TObject);
  begin
    Inc(FClicked);
  end;

  procedure TButtonTest.TestTypeKey;
  var
    B: TTyButton;
  begin
    B := TTyButton.Create(nil);
    try
      AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
    finally
      B.Free;
    end;
  end;

  procedure TButtonTest.TestOnClickFires;
  var
    F: TCustomForm;
    B: TTyButton;
  begin
    FClicked := 0;
    F := TCustomForm.CreateNew(nil);
    try
      B := TTyButton.Create(F);
      B.Parent := F;
      B.OnClick := @HandleClick;
      B.Click;
      AssertEquals(1, FClicked);
    finally
      F.Free;
    end;
  end;

  procedure TButtonTest.TestPaintSmoke;
  var
    F: TCustomForm;
    B: TTyButton;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      B := TTyButton.Create(F);
      B.Parent := F;
      B.SetBounds(0, 0, 80, 28);
      B.Caption := 'OK';
      B.Repaint;
      AssertTrue('button painted without crash', True);
    finally
      F.Free;
    end;
  end;

  initialization
    RegisterTest(TButtonTest);
  end.
  ```

- [ ] **Step 2: Add test.button to the runner uses clause.** In `/tests/tytests.lpr`, add `test.button` to the `uses` clause (after the last existing test unit, before the runner setup).

- [ ] **Step 3: Run the test expecting FAIL (unit does not compile yet).** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `/source/tyControls.Button.pas` does not exist (`tyControls.Button` not found).

- [ ] **Step 4: Implement TTyButton minimally.** Create `/source/tyControls.Button.pas` with the full implementation:
  ```pascal
  unit tyControls.Button;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, Controls, Graphics, LCLType,
    tyControls.Types, tyControls.Painter, tyControls.Base;
  type
    TTyButton = class(TTyCustomControl)
    protected
      function GetStyleTypeKey: string; override;
      procedure Paint; override;
    published
      property Caption;
      property Enabled;
      property Font;
      property Align;
      property Anchors;
      property StyleClass;
      property Controller;
      property OnClick;
    end;
  implementation

  function TTyButton.GetStyleTypeKey: string;
  begin
    Result := 'TyButton';
  end;

  procedure TTyButton.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R, ContentRect: TRect;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
      DrawFrame(P, ContentRect, S);
      P.DrawText(ContentRect, Caption, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taCenter, tlCenter, True);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;

  end.
  ```

- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TButtonTest.TestTypeKey`, `TButtonTest.TestOnClickFires`, and `TButtonTest.TestPaintSmoke` all PASS.

- [ ] **Step 6: Commit.** Run `git add source/tyControls.Button.pas tests/test.button.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyButton control with click and paint tests"`.

### Task CONTROLS-A.2: TTyLabel — typeKey, text-only paint (no frame)

**Files:**
- Create: `/source/tyControls.Label.pas`
- Create: `/tests/test.label.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit for TTyLabel.** Create `/tests/test.label.pas`:
  ```pascal
  unit test.label;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
    tyControls.Base, tyControls.Label;
  type
    TLabelTest = class(TTestCase)
    published
      procedure TestTypeKey;
      procedure TestCaptionProperty;
      procedure TestPaintSmoke;
    end;
  implementation

  procedure TLabelTest.TestTypeKey;
  var
    L: TTyLabel;
  begin
    L := TTyLabel.Create(nil);
    try
      AssertEquals('TyLabel', (L as ITyStyleable).GetStyleTypeKey);
    finally
      L.Free;
    end;
  end;

  procedure TLabelTest.TestCaptionProperty;
  var
    L: TTyLabel;
  begin
    L := TTyLabel.Create(nil);
    try
      L.Caption := 'Hello';
      AssertEquals('Hello', L.Caption);
    finally
      L.Free;
    end;
  end;

  procedure TLabelTest.TestPaintSmoke;
  var
    F: TCustomForm;
    L: TTyLabel;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      L := TTyLabel.Create(F);
      L.Parent := F;
      L.SetBounds(0, 0, 120, 20);
      L.Caption := 'Label';
      L.Repaint;
      AssertTrue('label painted without crash', True);
    finally
      F.Free;
    end;
  end;

  initialization
    RegisterTest(TLabelTest);
  end.
  ```

- [ ] **Step 2: Add test.label to the runner uses clause.** In `/tests/tytests.lpr`, add `test.label` to the `uses` clause.

- [ ] **Step 3: Run the test expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `tyControls.Label` does not exist.

- [ ] **Step 4: Implement TTyLabel minimally (text only, no frame).** Create `/source/tyControls.Label.pas`:
  ```pascal
  unit tyControls.Label;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, Controls, Graphics, LCLType,
    tyControls.Types, tyControls.Painter, tyControls.Base;
  type
    TTyLabel = class(TTyGraphicControl)
    protected
      function GetStyleTypeKey: string; override;
      procedure Paint; override;
    published
      property Caption;
      property Enabled;
      property Font;
      property Align;
      property Anchors;
      property StyleClass;
      property Controller;
      property OnClick;
    end;
  implementation

  function TTyLabel.GetStyleTypeKey: string;
  begin
    Result := 'TyLabel';
  end;

  procedure TTyLabel.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R, ContentRect: TRect;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
      P.DrawText(ContentRect, Caption, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, False);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;

  end.
  ```

- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TLabelTest.TestTypeKey`, `TLabelTest.TestCaptionProperty`, and `TLabelTest.TestPaintSmoke` all PASS.

- [ ] **Step 6: Commit.** Run `git add source/tyControls.Label.pas tests/test.label.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyLabel text-only control with tests"`.

### Task CONTROLS-A.3: TTyEdit — typeKey, frame + text + caret + key input

**Files:**
- Create: `/source/tyControls.Edit.pas`
- Create: `/tests/test.edit.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit for TTyEdit.** Create `/tests/test.edit.pas` (asserts typeKey and that `UTF8KeyPress` appends to `Text`):
  ```pascal
  unit test.edit;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, fpcunit, testregistry, Forms, Controls, LCLType,
    tyControls.Base, tyControls.Edit;
  type
    TEditTest = class(TTestCase)
    published
      procedure TestTypeKey;
      procedure TestKeyInputAppendsText;
      procedure TestBackspaceRemovesChar;
      procedure TestPaintSmoke;
    end;
  implementation

  procedure TEditTest.TestTypeKey;
  var
    E: TTyEdit;
  begin
    E := TTyEdit.Create(nil);
    try
      AssertEquals('TyEdit', (E as ITyStyleable).GetStyleTypeKey);
    finally
      E.Free;
    end;
  end;

  procedure TEditTest.TestKeyInputAppendsText;
  var
    F: TCustomForm;
    E: TTyEdit;
    K: TUTF8Char;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      E := TTyEdit.Create(F);
      E.Parent := F;
      E.Text := '';
      K := 'A';
      E.InjectKey(K);
      K := 'b';
      E.InjectKey(K);
      AssertEquals('Ab', E.Text);
    finally
      F.Free;
    end;
  end;

  procedure TEditTest.TestBackspaceRemovesChar;
  var
    F: TCustomForm;
    E: TTyEdit;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      E := TTyEdit.Create(F);
      E.Parent := F;
      E.Text := 'abc';
      E.InjectBackspace;
      AssertEquals('ab', E.Text);
    finally
      F.Free;
    end;
  end;

  procedure TEditTest.TestPaintSmoke;
  var
    F: TCustomForm;
    E: TTyEdit;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      E := TTyEdit.Create(F);
      E.Parent := F;
      E.SetBounds(0, 0, 140, 24);
      E.Text := 'typed';
      E.Repaint;
      AssertTrue('edit painted without crash', True);
    finally
      F.Free;
    end;
  end;

  initialization
    RegisterTest(TEditTest);
  end.
  ```

- [ ] **Step 2: Add test.edit to the runner uses clause.** In `/tests/tytests.lpr`, add `test.edit` to the `uses` clause.

- [ ] **Step 3: Run the test expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `tyControls.Edit` does not exist.

- [ ] **Step 4: Implement TTyEdit minimally (frame + text + caret + key routing).** Create `/source/tyControls.Edit.pas`. `InjectKey`/`InjectBackspace` are testable helpers that the real key handlers delegate to:
  ```pascal
  unit tyControls.Edit;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, Controls, Graphics, LCLType,
    tyControls.Types, tyControls.Painter, tyControls.Base;
  type
    TTyEdit = class(TTyCustomControl)
    private
      FText: string;
      procedure SetText(const AValue: string);
    protected
      function GetStyleTypeKey: string; override;
      procedure Paint; override;
      procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
      procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    public
      constructor Create(AOwner: TComponent); override;
      procedure InjectKey(const AChar: TUTF8Char);
      procedure InjectBackspace;
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
  end;

  function TTyEdit.GetStyleTypeKey: string;
  begin
    Result := 'TyEdit';
  end;

  procedure TTyEdit.SetText(const AValue: string);
  begin
    if FText = AValue then Exit;
    FText := AValue;
    Invalidate;
  end;

  procedure TTyEdit.InjectKey(const AChar: TUTF8Char);
  begin
    if (AChar <> '') and (AChar[1] >= #32) then
    begin
      FText := FText + AChar;
      Invalidate;
    end;
  end;

  procedure TTyEdit.InjectBackspace;
  begin
    if FText <> '' then
    begin
      System.Delete(FText, Length(FText), 1);
      Invalidate;
    end;
  end;

  procedure TTyEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
  begin
    inherited UTF8KeyPress(UTF8Key);
    InjectKey(UTF8Key);
  end;

  procedure TTyEdit.KeyDown(var Key: Word; Shift: TShiftState);
  begin
    inherited KeyDown(Key, Shift);
    if Key = VK_BACK then
    begin
      InjectBackspace;
      Key := 0;
    end;
  end;

  procedure TTyEdit.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R, ContentRect, CaretRect: TRect;
    PadL: Integer;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
      DrawFrame(P, ContentRect, S);
      PadL := P.Scale(S.Padding.Left);
      P.DrawText(Rect(ContentRect.Left + PadL, ContentRect.Top,
        ContentRect.Right, ContentRect.Bottom), FText, S.FontName, S.FontSize,
        S.FontWeight, S.TextColor, taLeftJustify, tlCenter, True);
      if Focused then
      begin
        CaretRect := Rect(ContentRect.Left + PadL, ContentRect.Top + P.Scale(4),
          ContentRect.Left + PadL + P.Scale(1), ContentRect.Bottom - P.Scale(4));
        P.FillBackground(CaretRect, Default(TTyFill), 0);
        P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
      end;
      P.EndPaint;
    finally
      P.Free;
    end;
  end;

  end.
  ```

- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TEditTest.TestTypeKey`, `TEditTest.TestKeyInputAppendsText`, `TEditTest.TestBackspaceRemovesChar`, and `TEditTest.TestPaintSmoke` all PASS.

- [ ] **Step 6: Commit.** Run `git add source/tyControls.Edit.pas tests/test.edit.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyEdit control with key input and caret tests"`.

### Task CONTROLS-A.4: TTyCheckBox — typeKey, toggle-on-click, glyph + caption paint

**Files:**
- Create: `/source/tyControls.CheckBox.pas`
- Create: `/tests/test.checkbox.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit for TTyCheckBox.** Create `/tests/test.checkbox.pas` (clicking toggles `Checked`):
  ```pascal
  unit test.checkbox;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
    tyControls.Base, tyControls.CheckBox;
  type
    TCheckBoxTest = class(TTestCase)
    published
      procedure TestTypeKey;
      procedure TestClickTogglesChecked;
      procedure TestPaintSmoke;
    end;
  implementation

  procedure TCheckBoxTest.TestTypeKey;
  var
    C: TTyCheckBox;
  begin
    C := TTyCheckBox.Create(nil);
    try
      AssertEquals('TyCheckBox', (C as ITyStyleable).GetStyleTypeKey);
    finally
      C.Free;
    end;
  end;

  procedure TCheckBoxTest.TestClickTogglesChecked;
  var
    F: TCustomForm;
    C: TTyCheckBox;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      C := TTyCheckBox.Create(F);
      C.Parent := F;
      AssertFalse('starts unchecked', C.Checked);
      C.Click;
      AssertTrue('checked after first click', C.Checked);
      C.Click;
      AssertFalse('unchecked after second click', C.Checked);
    finally
      F.Free;
    end;
  end;

  procedure TCheckBoxTest.TestPaintSmoke;
  var
    F: TCustomForm;
    C: TTyCheckBox;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      C := TTyCheckBox.Create(F);
      C.Parent := F;
      C.SetBounds(0, 0, 120, 22);
      C.Caption := 'Accept';
      C.Checked := True;
      C.Repaint;
      AssertTrue('checkbox painted without crash', True);
    finally
      F.Free;
    end;
  end;

  initialization
    RegisterTest(TCheckBoxTest);
  end.
  ```

- [ ] **Step 2: Add test.checkbox to the runner uses clause.** In `/tests/tytests.lpr`, add `test.checkbox` to the `uses` clause.

- [ ] **Step 3: Run the test expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build FAILS because `tyControls.CheckBox` does not exist.

- [ ] **Step 4: Implement TTyCheckBox and TTyRadioButton minimally.** Create `/source/tyControls.CheckBox.pas` with both classes (RadioButton un-checks siblings sharing the same Parent):
  ```pascal
  unit tyControls.CheckBox;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, Controls, Graphics, LCLType,
    tyControls.Types, tyControls.Painter, tyControls.Base;
  type
    TTyCheckBox = class(TTyCustomControl)
    private
      FChecked: Boolean;
      procedure SetChecked(const AValue: Boolean);
    protected
      function GetStyleTypeKey: string; override;
      procedure Click; override;
      procedure Paint; override;
    published
      property Checked: Boolean read FChecked write SetChecked default False;
      property Caption;
      property Enabled;
      property Font;
      property Align;
      property Anchors;
      property StyleClass;
      property Controller;
      property OnClick;
    end;

    TTyRadioButton = class(TTyCustomControl)
    private
      FChecked: Boolean;
      procedure SetChecked(const AValue: Boolean);
      procedure UncheckSiblings;
    protected
      function GetStyleTypeKey: string; override;
      procedure Click; override;
      procedure Paint; override;
    published
      property Checked: Boolean read FChecked write SetChecked default False;
      property Caption;
      property Enabled;
      property Font;
      property Align;
      property Anchors;
      property StyleClass;
      property Controller;
      property OnClick;
    end;
  implementation

  { TTyCheckBox }

  function TTyCheckBox.GetStyleTypeKey: string;
  begin
    Result := 'TyCheckBox';
  end;

  procedure TTyCheckBox.SetChecked(const AValue: Boolean);
  begin
    if FChecked = AValue then Exit;
    FChecked := AValue;
    Invalidate;
  end;

  procedure TTyCheckBox.Click;
  begin
    SetChecked(not FChecked);
    inherited Click;
  end;

  procedure TTyCheckBox.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R, ContentRect, BoxRect, TextRect: TRect;
    BoxSize, Gap: Integer;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
      BoxSize := P.Scale(16);
      Gap := P.Scale(6);
      BoxRect := Rect(ContentRect.Left,
        ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2),
        ContentRect.Left + BoxSize,
        ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2) + BoxSize);
      P.FillBackground(BoxRect, S.Background, S.BorderRadius);
      P.StrokeBorder(BoxRect, S.BorderRadius, S.BorderWidth, S.BorderColor);
      if FChecked then
        P.DrawGlyph(BoxRect, tgCheck, S.TextColor, 2);
      TextRect := Rect(BoxRect.Right + Gap, ContentRect.Top,
        ContentRect.Right, ContentRect.Bottom);
      P.DrawText(TextRect, Caption, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;

  { TTyRadioButton }

  function TTyRadioButton.GetStyleTypeKey: string;
  begin
    Result := 'TyRadioButton';
  end;

  procedure TTyRadioButton.SetChecked(const AValue: Boolean);
  begin
    if FChecked = AValue then Exit;
    FChecked := AValue;
    if FChecked then
      UncheckSiblings;
    Invalidate;
  end;

  procedure TTyRadioButton.UncheckSiblings;
  var
    I: Integer;
    Sib: TControl;
  begin
    if Parent = nil then Exit;
    for I := 0 to Parent.ControlCount - 1 do
    begin
      Sib := Parent.Controls[I];
      if (Sib <> Self) and (Sib is TTyRadioButton) then
        TTyRadioButton(Sib).SetChecked(False);
    end;
  end;

  procedure TTyRadioButton.Click;
  begin
    SetChecked(True);
    inherited Click;
  end;

  procedure TTyRadioButton.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R, ContentRect, DotRect, TextRect: TRect;
    BoxSize, Gap: Integer;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
      BoxSize := P.Scale(16);
      Gap := P.Scale(6);
      DotRect := Rect(ContentRect.Left,
        ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2),
        ContentRect.Left + BoxSize,
        ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2) + BoxSize);
      P.FillBackground(DotRect, S.Background, BoxSize div 2);
      P.StrokeBorder(DotRect, BoxSize div 2, S.BorderWidth, S.BorderColor);
      if FChecked then
        P.DrawGlyph(DotRect, tgRadioDot, S.TextColor, 2);
      TextRect := Rect(DotRect.Right + Gap, ContentRect.Top,
        ContentRect.Right, ContentRect.Bottom);
      P.DrawText(TextRect, Caption, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;

  end.
  ```

- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TCheckBoxTest.TestTypeKey`, `TCheckBoxTest.TestClickTogglesChecked`, and `TCheckBoxTest.TestPaintSmoke` all PASS.

- [ ] **Step 6: Commit.** Run `git add source/tyControls.CheckBox.pas tests/test.checkbox.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyCheckBox and TTyRadioButton controls with toggle tests"`.

### Task CONTROLS-A.5: TTyRadioButton group exclusivity test

**Files:**
- Create: `/tests/test.radiobutton.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit for TTyRadioButton group behavior.** Create `/tests/test.radiobutton.pas` (clicking one radio in a Parent clears the others, but not radios in a different Parent):
  ```pascal
  unit test.radiobutton;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, fpcunit, testregistry, Forms, Controls, ExtCtrls,
    tyControls.Base, tyControls.CheckBox;
  type
    TRadioButtonTest = class(TTestCase)
    published
      procedure TestTypeKey;
      procedure TestClickClearsGroup;
      procedure TestSeparateParentsAreIndependent;
    end;
  implementation

  procedure TRadioButtonTest.TestTypeKey;
  var
    Rb: TTyRadioButton;
  begin
    Rb := TTyRadioButton.Create(nil);
    try
      AssertEquals('TyRadioButton', (Rb as ITyStyleable).GetStyleTypeKey);
    finally
      Rb.Free;
    end;
  end;

  procedure TRadioButtonTest.TestClickClearsGroup;
  var
    F: TCustomForm;
    A, B, C: TTyRadioButton;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      A := TTyRadioButton.Create(F); A.Parent := F;
      B := TTyRadioButton.Create(F); B.Parent := F;
      C := TTyRadioButton.Create(F); C.Parent := F;
      A.Click;
      AssertTrue('A checked', A.Checked);
      B.Click;
      AssertTrue('B checked', B.Checked);
      AssertFalse('A cleared by B', A.Checked);
      AssertFalse('C still clear', C.Checked);
    finally
      F.Free;
    end;
  end;

  procedure TRadioButtonTest.TestSeparateParentsAreIndependent;
  var
    F: TCustomForm;
    P1, P2: TPanel;
    A, B: TTyRadioButton;
  begin
    F := TCustomForm.CreateNew(nil);
    try
      P1 := TPanel.Create(F); P1.Parent := F;
      P2 := TPanel.Create(F); P2.Parent := F;
      A := TTyRadioButton.Create(F); A.Parent := P1;
      B := TTyRadioButton.Create(F); B.Parent := P2;
      A.Click;
      B.Click;
      AssertTrue('A stays checked in its own group', A.Checked);
      AssertTrue('B checked in its own group', B.Checked);
    finally
      F.Free;
    end;
  end;

  initialization
    RegisterTest(TRadioButtonTest);
  end.
  ```

- [ ] **Step 2: Add test.radiobutton to the runner uses clause.** In `/tests/tytests.lpr`, add `test.radiobutton` to the `uses` clause.

- [ ] **Step 3: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: `TRadioButtonTest.TestTypeKey`, `TRadioButtonTest.TestClickClearsGroup`, and `TRadioButtonTest.TestSeparateParentsAreIndependent` all PASS (behavior already implemented in CONTROLS-A.4; this task locks it in with explicit group tests).

- [ ] **Step 4: Commit.** Run `git add tests/test.radiobutton.pas tests/tytests.lpr` then `git commit -m "test(tycontrols): add TTyRadioButton group exclusivity tests"`.

---

```markdown
## P2 · Controls (2): Panel / ComboBox / ScrollBar

This section implements three Tier-1 controls. It depends on the already-contracted units `tyControls.Types`, `tyControls.Painter`, `tyControls.Controller`, and `tyControls.Base` (referenced via `uses`, never redefined here). Each control overrides `GetStyleTypeKey` and follows the Paint pattern from the Base contract. Tests construct controls headlessly with a `TForm` parent and assert behavior; the pure `TyScrollThumbRect` geometry helper is unit-tested without any window.

### Task CONTROLS-B.1: TTyPanel container control

**Files:**
- Create: `/source/tyControls.Panel.pas`
- Test: `/tests/test.controls.panel.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit `/tests/test.controls.panel.pas`.** Write a `TTestCase` that constructs the panel under a hidden `TForm` parent and asserts its typeKey, default caption, and that it accepts a child control. Full content:
  ```pascal
  unit test.controls.panel;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Forms, Controls, StdCtrls, fpcunit, testregistry,
    tyControls.Base, tyControls.Panel;
  type
    TTyPanelTest = class(TTestCase)
    private
      FForm: TForm;
      FPanel: TTyPanel;
    protected
      procedure SetUp; override;
      procedure TearDown; override;
    published
      procedure TestTypeKey;
      procedure TestDefaultCaptionEmpty;
      procedure TestImplementsStyleable;
      procedure TestHostsChild;
    end;
  implementation
  procedure TTyPanelTest.SetUp;
  begin
    FForm := TForm.CreateNew(nil);
    FPanel := TTyPanel.Create(FForm);
    FPanel.Parent := FForm;
  end;
  procedure TTyPanelTest.TearDown;
  begin
    FForm.Free;
  end;
  procedure TTyPanelTest.TestTypeKey;
  begin
    AssertEquals('TyPanel', FPanel.GetStyleTypeKey);
  end;
  procedure TTyPanelTest.TestDefaultCaptionEmpty;
  begin
    AssertEquals('', FPanel.Caption);
  end;
  procedure TTyPanelTest.TestImplementsStyleable;
  var
    Styleable: ITyStyleable;
  begin
    AssertTrue('TTyPanel must support ITyStyleable',
      Supports(FPanel, ITyStyleable, Styleable));
    AssertEquals('TyPanel', Styleable.GetStyleTypeKey);
  end;
  procedure TTyPanelTest.TestHostsChild;
  var
    Child: TButton;
  begin
    Child := TButton.Create(FPanel);
    Child.Parent := FPanel;
    AssertSame('child parent must be the panel', FPanel, Child.Parent);
    AssertEquals('panel must report one child control', 1, FPanel.ControlCount);
  end;
  initialization
    RegisterTest(TTyPanelTest);
  end.
  ```

- [ ] **Step 2: Add `test.controls.panel` to the runner uses clause.** In `/tests/tytests.lpr`, add `test.controls.panel` to the `uses` clause so the test is registered into the aggregate runner.

- [ ] **Step 3: Run the test expecting a BUILD FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build fails because unit `tyControls.Panel` does not exist yet (`Can't find unit tyControls.Panel`).

- [ ] **Step 4: Create `/source/tyControls.Panel.pas` with minimal compilable implementation.** `TTyPanel` is a `TTyGraphicControl` (non-focusable container per contract), publishes `Caption`, overrides `GetStyleTypeKey`, and paints frame + optional caption text. Full content:
  ```pascal
  unit tyControls.Panel;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, Controls, Graphics,
    tyControls.Types, tyControls.Painter, tyControls.Base;
  type
    TTyPanel = class(TTyGraphicControl)
    private
      FCaption: string;
      procedure SetCaption(const AValue: string);
    protected
      procedure Paint; override;
    public
      function GetStyleTypeKey: string; override;
      constructor Create(AOwner: TComponent); override;
    published
      property Caption: string read FCaption write SetCaption;
      property Align;
      property Anchors;
      property StyleClass;
      property Controller;
    end;
  implementation
  constructor TTyPanel.Create(AOwner: TComponent);
  begin
    inherited Create(AOwner);
    FCaption := '';
    Width := 185;
    Height := 41;
  end;
  function TTyPanel.GetStyleTypeKey: string;
  begin
    Result := 'TyPanel';
  end;
  procedure TTyPanel.SetCaption(const AValue: string);
  begin
    if FCaption = AValue then Exit;
    FCaption := AValue;
    Invalidate;
  end;
  procedure TTyPanel.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R: TRect;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      DrawFrame(P, R, S);
      if FCaption <> '' then
        P.DrawText(R, FCaption, S.FontName, S.FontSize, S.FontWeight,
          S.TextColor, taLeftJustify, tlCenter, True);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  end.
  ```

- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: all four `TTyPanelTest` tests pass (`TestTypeKey`, `TestDefaultCaptionEmpty`, `TestImplementsStyleable`, `TestHostsChild`).

- [ ] **Step 6: Commit.** Run `git add source/tyControls.Panel.pas tests/test.controls.panel.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyPanel container control with caption"`.

### Task CONTROLS-B.2: TTyComboBox selection logic

**Files:**
- Create: `/source/tyControls.ComboBox.pas`
- Test: `/tests/test.controls.combobox.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit `/tests/test.controls.combobox.pas`.** Assert typeKey, that `Items` is a live `TStrings`, and that selecting via the public `SelectItem` method sets both `ItemIndex` and `Text`. Full content:
  ```pascal
  unit test.controls.combobox;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Forms, Controls, fpcunit, testregistry,
    tyControls.Base, tyControls.ComboBox;
  type
    TTyComboBoxTest = class(TTestCase)
    private
      FForm: TForm;
      FCombo: TTyComboBox;
    protected
      procedure SetUp; override;
      procedure TearDown; override;
    published
      procedure TestTypeKey;
      procedure TestItemsLive;
      procedure TestSelectItemSetsIndexAndText;
      procedure TestSelectOutOfRangeClears;
      procedure TestChangeEventFires;
    end;
  implementation
  type
    TChangeProbe = class
    public
      Count: Integer;
      procedure Handle(Sender: TObject);
    end;
  procedure TChangeProbe.Handle(Sender: TObject);
  begin
    Inc(Count);
  end;
  procedure TTyComboBoxTest.SetUp;
  begin
    FForm := TForm.CreateNew(nil);
    FCombo := TTyComboBox.Create(FForm);
    FCombo.Parent := FForm;
    FCombo.Items.Add('Apple');
    FCombo.Items.Add('Banana');
    FCombo.Items.Add('Cherry');
  end;
  procedure TTyComboBoxTest.TearDown;
  begin
    FForm.Free;
  end;
  procedure TTyComboBoxTest.TestTypeKey;
  begin
    AssertEquals('TyComboBox', FCombo.GetStyleTypeKey);
  end;
  procedure TTyComboBoxTest.TestItemsLive;
  begin
    AssertEquals('items count after SetUp adds', 3, FCombo.Items.Count);
    AssertEquals('Banana', FCombo.Items[1]);
  end;
  procedure TTyComboBoxTest.TestSelectItemSetsIndexAndText;
  begin
    FCombo.SelectItem(2);
    AssertEquals('ItemIndex must follow selection', 2, FCombo.ItemIndex);
    AssertEquals('Text must mirror selected item', 'Cherry', FCombo.Text);
  end;
  procedure TTyComboBoxTest.TestSelectOutOfRangeClears;
  begin
    FCombo.SelectItem(1);
    FCombo.SelectItem(99);
    AssertEquals('out-of-range selection clears index', -1, FCombo.ItemIndex);
    AssertEquals('out-of-range selection clears text', '', FCombo.Text);
  end;
  procedure TTyComboBoxTest.TestChangeEventFires;
  var
    Probe: TChangeProbe;
  begin
    Probe := TChangeProbe.Create;
    try
      FCombo.OnChange := @Probe.Handle;
      FCombo.SelectItem(0);
      AssertEquals('OnChange fires once on real change', 1, Probe.Count);
      FCombo.SelectItem(0);
      AssertEquals('OnChange does not fire when index unchanged', 1, Probe.Count);
    finally
      Probe.Free;
    end;
  end;
  initialization
    RegisterTest(TTyComboBoxTest);
  end.
  ```

- [ ] **Step 2: Add `test.controls.combobox` to the runner uses clause.** In `/tests/tytests.lpr`, add `test.controls.combobox` to the `uses` clause.

- [ ] **Step 3: Run the test expecting a BUILD FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build fails because unit `tyControls.ComboBox` does not exist yet (`Can't find unit tyControls.ComboBox`).

- [ ] **Step 4: Create `/source/tyControls.ComboBox.pas` with minimal compilable implementation.** `TTyComboBox` is a focusable `TTyCustomControl`; owns an `Items: TStrings`, an `ItemIndex`, a `Text`, an `OnChange`, a public `SelectItem` that drives index/text and fires the event only on real change, and paints a frame, current text, and a `tgChevronDown` drop button. Full content:
  ```pascal
  unit tyControls.ComboBox;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, Controls, Graphics,
    tyControls.Types, tyControls.Painter, tyControls.Base;
  type
    TTyComboBox = class(TTyCustomControl)
    private
      FItems: TStringList;
      FItemIndex: Integer;
      FText: string;
      FOnChange: TNotifyEvent;
      procedure SetItems(const AValue: TStringList);
      procedure SetItemIndex(const AValue: Integer);
      procedure SetText(const AValue: string);
      function ButtonWidthLogical: Integer;
    protected
      procedure Paint; override;
      procedure Click; override;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      function GetStyleTypeKey: string; override;
      procedure SelectItem(AIndex: Integer);
    published
      property Items: TStringList read FItems write SetItems;
      property ItemIndex: Integer read FItemIndex write SetItemIndex;
      property Text: string read FText write SetText;
      property OnChange: TNotifyEvent read FOnChange write FOnChange;
      property TabStop default True;
      property Align;
      property Anchors;
      property StyleClass;
      property Controller;
    end;
  implementation
  constructor TTyComboBox.Create(AOwner: TComponent);
  begin
    inherited Create(AOwner);
    FItems := TStringList.Create;
    FItemIndex := -1;
    FText := '';
    TabStop := True;
    Width := 145;
    Height := 26;
  end;
  destructor TTyComboBox.Destroy;
  begin
    FItems.Free;
    inherited Destroy;
  end;
  function TTyComboBox.GetStyleTypeKey: string;
  begin
    Result := 'TyComboBox';
  end;
  procedure TTyComboBox.SetItems(const AValue: TStringList);
  begin
    FItems.Assign(AValue);
    Invalidate;
  end;
  procedure TTyComboBox.SetText(const AValue: string);
  begin
    if FText = AValue then Exit;
    FText := AValue;
    Invalidate;
  end;
  procedure TTyComboBox.SetItemIndex(const AValue: Integer);
  begin
    SelectItem(AValue);
  end;
  function TTyComboBox.ButtonWidthLogical: Integer;
  begin
    Result := 18;
  end;
  procedure TTyComboBox.SelectItem(AIndex: Integer);
  var
    NewIndex: Integer;
    NewText: string;
  begin
    if (AIndex >= 0) and (AIndex < FItems.Count) then
    begin
      NewIndex := AIndex;
      NewText := FItems[AIndex];
    end
    else
    begin
      NewIndex := -1;
      NewText := '';
    end;
    if (NewIndex = FItemIndex) and (NewText = FText) then Exit;
    FItemIndex := NewIndex;
    FText := NewText;
    Invalidate;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
  procedure TTyComboBox.Click;
  begin
    inherited Click;
    if FItems.Count = 0 then Exit;
    if FItemIndex < 0 then
      SelectItem(0)
    else if FItemIndex < FItems.Count - 1 then
      SelectItem(FItemIndex + 1)
    else
      SelectItem(0);
  end;
  procedure TTyComboBox.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R, TextR, BtnR: TRect;
    BtnW: Integer;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      DrawFrame(P, R, S);
      BtnW := P.Scale(ButtonWidthLogical);
      BtnR := Rect(R.Right - BtnW, R.Top, R.Right, R.Bottom);
      TextR := Rect(R.Left + P.Scale(6), R.Top, R.Right - BtnW, R.Bottom);
      if FText <> '' then
        P.DrawText(TextR, FText, S.FontName, S.FontSize, S.FontWeight,
          S.TextColor, taLeftJustify, tlCenter, True);
      P.DrawGlyph(BtnR, tgChevronDown, S.TextColor, 2);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  end.
  ```

- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: all five `TTyComboBoxTest` tests pass (`TestTypeKey`, `TestItemsLive`, `TestSelectItemSetsIndexAndText`, `TestSelectOutOfRangeClears`, `TestChangeEventFires`).

- [ ] **Step 6: Commit.** Run `git add source/tyControls.ComboBox.pas tests/test.controls.combobox.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyComboBox with selection logic and chevron glyph"`.

### Task CONTROLS-B.3: TyScrollThumbRect pure geometry helper

**Files:**
- Create: `/source/tyControls.ScrollBar.pas`
- Test: `/tests/test.controls.scrollbar.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the failing test unit `/tests/test.controls.scrollbar.pas`.** Test ONLY the pure helper `TyScrollThumbRect` (no window needed): a vertical track of 0..100, position 0, pageSize 25 yields a thumb at the top occupying a quarter of the track height; position 75 puts the thumb at the bottom. Full content:
  ```pascal
  unit test.controls.scrollbar;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, fpcunit, testregistry,
    tyControls.ScrollBar;
  type
    TTyScrollGeometryTest = class(TTestCase)
    published
      procedure TestVerticalThumbAtTop;
      procedure TestVerticalThumbAtBottom;
      procedure TestVerticalThumbMidway;
      procedure TestHorizontalThumbAtTop;
      procedure TestZeroRangeFillsTrack;
    end;
  implementation
  procedure TTyScrollGeometryTest.TestVerticalThumbAtTop;
  var
    R: TRect;
  begin
    // track 0,0..20,200 ; range 0..100 ; page 25 ; pos 0
    R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 0, 25);
    AssertEquals('thumb top at position 0', 0, R.Top);
    AssertEquals('thumb left spans track', 0, R.Left);
    AssertEquals('thumb right spans track', 20, R.Right);
    // 25/(100-0+25)=25/125=0.2 of 200 = 40
    AssertEquals('thumb height = page fraction of track', 40, R.Bottom - R.Top);
  end;
  procedure TTyScrollGeometryTest.TestVerticalThumbAtBottom;
  var
    R: TRect;
  begin
    // pos 100 is max (range 0..100, page 25 -> effective max 100)
    R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 100, 25);
    AssertEquals('thumb bottom hugs track end', 200, R.Bottom);
    AssertEquals('thumb height stays page-sized', 40, R.Bottom - R.Top);
  end;
  procedure TTyScrollGeometryTest.TestVerticalThumbMidway;
  var
    R: TRect;
  begin
    // pos 50 of travel 100 -> 0.5 of free space (200-40=160) -> top 80
    R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 0, 100, 50, 25);
    AssertEquals('thumb top at half travel', 80, R.Top);
    AssertEquals('thumb height stays page-sized', 40, R.Bottom - R.Top);
  end;
  procedure TTyScrollGeometryTest.TestHorizontalThumbAtTop;
  var
    R: TRect;
  begin
    R := TyScrollThumbRect(Rect(0, 0, 200, 20), sbHorizontal, 0, 100, 0, 25);
    AssertEquals('horizontal thumb left at position 0', 0, R.Left);
    AssertEquals('horizontal thumb top spans track', 0, R.Top);
    AssertEquals('horizontal thumb bottom spans track', 20, R.Bottom);
    AssertEquals('horizontal thumb width = page fraction', 40, R.Right - R.Left);
  end;
  procedure TTyScrollGeometryTest.TestZeroRangeFillsTrack;
  var
    R: TRect;
  begin
    // min=max -> nothing to scroll, thumb fills whole track
    R := TyScrollThumbRect(Rect(0, 0, 20, 200), sbVertical, 5, 5, 5, 10);
    AssertEquals('degenerate range: thumb top is track top', 0, R.Top);
    AssertEquals('degenerate range: thumb fills track', 200, R.Bottom);
  end;
  initialization
    RegisterTest(TTyScrollGeometryTest);
  end.
  ```

- [ ] **Step 2: Add `test.controls.scrollbar` to the runner uses clause.** In `/tests/tytests.lpr`, add `test.controls.scrollbar` to the `uses` clause.

- [ ] **Step 3: Run the test expecting a BUILD FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build fails because unit `tyControls.ScrollBar` does not exist yet (`Can't find unit tyControls.ScrollBar`).

- [ ] **Step 4: Create `/source/tyControls.ScrollBar.pas` with the pure helper plus a minimal control shell.** Declare `TTyScrollBarKind` and the pure `TyScrollThumbRect`, and a `TTyScrollBar` control that compiles (full painting/drag added in the next task). Full content:
  ```pascal
  unit tyControls.ScrollBar;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Types, Controls, Graphics,
    tyControls.Types, tyControls.Painter, tyControls.Base;
  type
    TTyScrollBarKind = (sbHorizontal, sbVertical);

    TTyScrollBar = class(TTyCustomControl)
    private
      FKind: TTyScrollBarKind;
      FMin, FMax, FPosition, FPageSize: Integer;
      FOnChange: TNotifyEvent;
      procedure SetKind(const AValue: TTyScrollBarKind);
      procedure SetMin(const AValue: Integer);
      procedure SetMax(const AValue: Integer);
      procedure SetPosition(const AValue: Integer);
      procedure SetPageSize(const AValue: Integer);
    protected
      procedure Paint; override;
    public
      constructor Create(AOwner: TComponent); override;
      function GetStyleTypeKey: string; override;
    published
      property Kind: TTyScrollBarKind read FKind write SetKind default sbVertical;
      property Min: Integer read FMin write SetMin default 0;
      property Max: Integer read FMax write SetMax default 100;
      property Position: Integer read FPosition write SetPosition default 0;
      property PageSize: Integer read FPageSize write SetPageSize default 10;
      property OnChange: TNotifyEvent read FOnChange write FOnChange;
      property Align;
      property Anchors;
      property StyleClass;
      property Controller;
    end;

  function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
    AMin, AMax, APosition, APageSize: Integer): TRect;

  implementation

  function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
    AMin, AMax, APosition, APageSize: Integer): TRect;
  var
    TrackLen, Span, ThumbLen, FreeSpace, Travel, Pos0, Offset: Integer;
  begin
    if AKind = sbVertical then
      TrackLen := ATrack.Bottom - ATrack.Top
    else
      TrackLen := ATrack.Right - ATrack.Left;
    Span := (AMax - AMin) + APageSize;
    if (Span <= 0) or (APageSize <= 0) or (AMax <= AMin) then
    begin
      // degenerate: nothing to scroll, thumb fills the whole track
      Result := ATrack;
      Exit;
    end;
    ThumbLen := (APageSize * TrackLen) div Span;
    if ThumbLen < 1 then ThumbLen := 1;
    if ThumbLen > TrackLen then ThumbLen := TrackLen;
    FreeSpace := TrackLen - ThumbLen;
    Travel := AMax - AMin;
    Pos0 := APosition - AMin;
    if Pos0 < 0 then Pos0 := 0;
    if Pos0 > Travel then Pos0 := Travel;
    if Travel <= 0 then
      Offset := 0
    else
      Offset := (Pos0 * FreeSpace) div Travel;
    if AKind = sbVertical then
      Result := Rect(ATrack.Left, ATrack.Top + Offset,
        ATrack.Right, ATrack.Top + Offset + ThumbLen)
    else
      Result := Rect(ATrack.Left + Offset, ATrack.Top,
        ATrack.Left + Offset + ThumbLen, ATrack.Bottom);
  end;

  constructor TTyScrollBar.Create(AOwner: TComponent);
  begin
    inherited Create(AOwner);
    FKind := sbVertical;
    FMin := 0;
    FMax := 100;
    FPosition := 0;
    FPageSize := 10;
    Width := 16;
    Height := 160;
  end;

  function TTyScrollBar.GetStyleTypeKey: string;
  begin
    Result := 'TyScrollBar';
  end;

  procedure TTyScrollBar.SetKind(const AValue: TTyScrollBarKind);
  begin
    if FKind = AValue then Exit;
    FKind := AValue;
    Invalidate;
  end;

  procedure TTyScrollBar.SetMin(const AValue: Integer);
  begin
    if FMin = AValue then Exit;
    FMin := AValue;
    if FPosition < FMin then FPosition := FMin;
    Invalidate;
  end;

  procedure TTyScrollBar.SetMax(const AValue: Integer);
  begin
    if FMax = AValue then Exit;
    FMax := AValue;
    if FPosition > FMax then FPosition := FMax;
    Invalidate;
  end;

  procedure TTyScrollBar.SetPosition(const AValue: Integer);
  var
    Clamped: Integer;
  begin
    Clamped := AValue;
    if Clamped < FMin then Clamped := FMin;
    if Clamped > FMax then Clamped := FMax;
    if FPosition = Clamped then Exit;
    FPosition := Clamped;
    Invalidate;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;

  procedure TTyScrollBar.SetPageSize(const AValue: Integer);
  begin
    if FPageSize = AValue then Exit;
    if AValue < 0 then
      FPageSize := 0
    else
      FPageSize := AValue;
    Invalidate;
  end;

  procedure TTyScrollBar.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    R, ThumbR: TRect;
  begin
    P := TTyPainter.Create;
    try
      R := ClientRect;
      P.BeginPaint(Canvas, R, Font.PixelsPerInch);
      S := CurrentStyle;
      DrawFrame(P, R, S);
      ThumbR := TyScrollThumbRect(R, FKind, FMin, FMax, FPosition, FPageSize);
      P.FillBackground(ThumbR, S.Background, S.BorderRadius);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;

  end.
  ```

- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: all five `TTyScrollGeometryTest` tests pass (`TestVerticalThumbAtTop`, `TestVerticalThumbAtBottom`, `TestVerticalThumbMidway`, `TestHorizontalThumbAtTop`, `TestZeroRangeFillsTrack`).

- [ ] **Step 6: Commit.** Run `git add source/tyControls.ScrollBar.pas tests/test.controls.scrollbar.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TTyScrollBar with pure TyScrollThumbRect geometry"`.

### Task CONTROLS-B.4: TTyScrollBar thumb drag updates Position and fires OnChange

**Files:**
- Modify: `/source/tyControls.ScrollBar.pas`
- Modify: `/tests/test.controls.scrollbar.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Add a failing drag test to `/tests/test.controls.scrollbar.pas`.** Add a second `TTestCase`, `TTyScrollBarDragTest`, that constructs the bar under a `TForm`, simulates a thumb grab and a downward drag via the public `DragThumbTo` method, and asserts `Position` advances and `OnChange` fires. Insert this new test class declaration into the `interface` `type` block (after `TTyScrollGeometryTest`):
  ```pascal
    TTyScrollBarDragTest = class(TTestCase)
    private
      FForm: TForm;
      FBar: TTyScrollBar;
      FChanges: Integer;
      procedure OnBarChange(Sender: TObject);
    protected
      procedure SetUp; override;
      procedure TearDown; override;
    published
      procedure TestDragMovesPosition;
      procedure TestDragFiresOnChange;
      procedure TestDragClampsAtMax;
    end;
  ```
  Add `Forms, Controls,` to the test unit's `uses` clause (they are needed for `TForm`). Then add these implementations before the `initialization` block:
  ```pascal
  procedure TTyScrollBarDragTest.OnBarChange(Sender: TObject);
  begin
    Inc(FChanges);
  end;
  procedure TTyScrollBarDragTest.SetUp;
  begin
    FForm := TForm.CreateNew(nil);
    FBar := TTyScrollBar.Create(FForm);
    FBar.Parent := FForm;
    FBar.Kind := sbVertical;
    FBar.SetBounds(0, 0, 16, 200);
    FBar.Min := 0;
    FBar.Max := 100;
    FBar.PageSize := 25;
    FBar.Position := 0;
    FChanges := 0;
    FBar.OnChange := @OnBarChange;
  end;
  procedure TTyScrollBarDragTest.TearDown;
  begin
    FForm.Free;
  end;
  procedure TTyScrollBarDragTest.TestDragMovesPosition;
  begin
    // grab at thumb top (y=0), drag down by 80px = half of free space (160) -> pos 50
    FBar.BeginThumbDrag(0);
    FBar.DragThumbTo(80);
    AssertEquals('drag of half free-space moves to mid position', 50, FBar.Position);
  end;
  procedure TTyScrollBarDragTest.TestDragFiresOnChange;
  begin
    FBar.BeginThumbDrag(0);
    FBar.DragThumbTo(80);
    AssertTrue('OnChange fired at least once during drag', FChanges >= 1);
  end;
  procedure TTyScrollBarDragTest.TestDragClampsAtMax;
  begin
    FBar.BeginThumbDrag(0);
    FBar.DragThumbTo(10000);
    AssertEquals('drag past end clamps at Max', 100, FBar.Position);
  end;
  ```
  And register the new class in the `initialization` block by adding `RegisterTest(TTyScrollBarDragTest);` after the existing `RegisterTest(TTyScrollGeometryTest);`.

- [ ] **Step 2: Confirm the runner already lists the unit.** Verify `/tests/tytests.lpr` `uses` clause still contains `test.controls.scrollbar` (added in CONTROLS-B.3 Step 2); no edit needed if present.

- [ ] **Step 3: Run the test expecting a BUILD FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: build fails because `BeginThumbDrag` and `DragThumbTo` are not yet declared on `TTyScrollBar` (`identifier idents no member "BeginThumbDrag"`).

- [ ] **Step 4: Add drag methods to `TTyScrollBar` in `/source/tyControls.ScrollBar.pas`.** Add the public drag API and the private drag state. First add the fields and method declarations. In the `private` section, after `FOnChange: TNotifyEvent;`, add:
  ```pascal
      FDragging: Boolean;
      FDragGrabOffset: Integer;
      FDragStartTop: Integer;
      function TrackLength: Integer;
  ```
  In the `public` section, after `function GetStyleTypeKey: string; override;`, add:
  ```pascal
      procedure BeginThumbDrag(AGrabPosAlongTrack: Integer);
      procedure DragThumbTo(APosAlongTrack: Integer);
      procedure EndThumbDrag;
  ```

- [ ] **Step 5: Implement the drag methods in the `implementation` section.** Add these implementations before the final `end.`:
  ```pascal
  function TTyScrollBar.TrackLength: Integer;
  begin
    if FKind = sbVertical then
      Result := Height
    else
      Result := Width;
  end;

  procedure TTyScrollBar.BeginThumbDrag(AGrabPosAlongTrack: Integer);
  var
    ThumbR: TRect;
    ThumbStart: Integer;
  begin
    ThumbR := TyScrollThumbRect(ClientRect, FKind, FMin, FMax, FPosition, FPageSize);
    if FKind = sbVertical then
      ThumbStart := ThumbR.Top
    else
      ThumbStart := ThumbR.Left;
    FDragging := True;
    FDragStartTop := ThumbStart;
    FDragGrabOffset := AGrabPosAlongTrack - ThumbStart;
  end;

  procedure TTyScrollBar.DragThumbTo(APosAlongTrack: Integer);
  var
    ThumbR: TRect;
    ThumbLen, FreeSpace, NewTop, Travel, NewPos: Integer;
  begin
    if not FDragging then Exit;
    ThumbR := TyScrollThumbRect(ClientRect, FKind, FMin, FMax, FPosition, FPageSize);
    if FKind = sbVertical then
      ThumbLen := ThumbR.Bottom - ThumbR.Top
    else
      ThumbLen := ThumbR.Right - ThumbR.Left;
    FreeSpace := TrackLength - ThumbLen;
    if FreeSpace < 1 then FreeSpace := 1;
    NewTop := APosAlongTrack - FDragGrabOffset;
    if NewTop < 0 then NewTop := 0;
    if NewTop > FreeSpace then NewTop := FreeSpace;
    Travel := FMax - FMin;
    NewPos := FMin + (NewTop * Travel) div FreeSpace;
    Position := NewPos;
  end;

  procedure TTyScrollBar.EndThumbDrag;
  begin
    FDragging := False;
  end;
  ```

- [ ] **Step 6: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: all three `TTyScrollBarDragTest` tests pass (`TestDragMovesPosition`, `TestDragFiresOnChange`, `TestDragClampsAtMax`) and the earlier `TTyScrollGeometryTest` tests still pass.

- [ ] **Step 7: Commit.** Run `git add source/tyControls.ScrollBar.pas tests/test.controls.scrollbar.pas` then `git commit -m "feat(tycontrols): add TTyScrollBar thumb drag updating Position with OnChange"`.
```

---

```markdown
## P3 · Window Subsystem: CaptionButton / TitleBar / FormChrome

This section implements `/source/tyControls.Form.pas` (`TTyCaptionButton`, `TTyTitleBar`, `TTyFormChrome`, plus the pure helpers `TyHitTestBorder`, `TyMaximizedBounds`, and the `TTyBorderHit` enum), tests them via FPCUnit, and documents the known gaps. It references types from the CONTRACT verbatim: `ITyStyleable`, `TTyCustomControl` (from `tyControls.Base`), `TTyPainter`, `TTyGlyphKind` (from `tyControls.Painter`), and `TTyStyleSet` (from `tyControls.Types`). The pure helpers are written first so they are unit-testable with no window.

### Task FORM.1: Pure window helpers (TyHitTestBorder, TyMaximizedBounds, TTyBorderHit)

**Files:**
- Create: `/source/tyControls.Form.pas`
- Create: `/tests/test.form.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Create the unit skeleton with the public helper declarations only.** Write `/source/tyControls.Form.pas` containing the enum, the two function signatures and their implementations (no classes yet so the test can compile against it):
  ```pascal
  unit tyControls.Form;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, Types;

  type
    TTyBorderHit = (bhNone, bhLeft, bhTop, bhRight, bhBottom,
                    bhTopLeft, bhTopRight, bhBottomLeft, bhBottomRight);

  function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
  function TyMaximizedBounds(const AWorkArea: TRect): TRect;

  implementation

  function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
  var
    OnLeft, OnRight, OnTop, OnBottom: Boolean;
  begin
    Result := bhNone;
    if AZone <= 0 then
      Exit;
    if (APt.X < AClient.Left) or (APt.X > AClient.Right) or
       (APt.Y < AClient.Top) or (APt.Y > AClient.Bottom) then
      Exit;
    OnLeft := APt.X < (AClient.Left + AZone);
    OnRight := APt.X > (AClient.Right - AZone);
    OnTop := APt.Y < (AClient.Top + AZone);
    OnBottom := APt.Y > (AClient.Bottom - AZone);
    if OnTop and OnLeft then
      Result := bhTopLeft
    else if OnTop and OnRight then
      Result := bhTopRight
    else if OnBottom and OnLeft then
      Result := bhBottomLeft
    else if OnBottom and OnRight then
      Result := bhBottomRight
    else if OnLeft then
      Result := bhLeft
    else if OnRight then
      Result := bhRight
    else if OnTop then
      Result := bhTop
    else if OnBottom then
      Result := bhBottom
    else
      Result := bhNone;
  end;

  function TyMaximizedBounds(const AWorkArea: TRect): TRect;
  begin
    Result.Left := AWorkArea.Left;
    Result.Top := AWorkArea.Top;
    Result.Right := AWorkArea.Right;
    Result.Bottom := AWorkArea.Bottom;
  end;

  end.
  ```

- [ ] **Step 2: Write the failing FPCUnit test for the helpers.** Create `/tests/test.form.pas` with a `TTestCase` exercising every border zone, the center, and the maximize helper:
  ```pascal
  unit test.form;

  {$mode objfpc}{$H+}

  interface

  uses
    Classes, SysUtils, Types, fpcunit, testregistry,
    tyControls.Form;

  type
    TFormHelpersTest = class(TTestCase)
    published
      procedure TestCenterIsNone;
      procedure TestLeftEdge;
      procedure TestRightEdge;
      procedure TestTopEdge;
      procedure TestBottomEdge;
      procedure TestTopLeftCorner;
      procedure TestTopRightCorner;
      procedure TestBottomLeftCorner;
      procedure TestBottomRightCorner;
      procedure TestZeroZoneIsNone;
      procedure TestMaximizedBoundsEqualsWorkArea;
    end;

  implementation

  const
    CR: TRect = (Left: 0; Top: 0; Right: 200; Bottom: 100);
    ZONE = 6;

  procedure TFormHelpersTest.TestCenterIsNone;
  begin
    AssertTrue('center', TyHitTestBorder(CR, Point(100, 50), ZONE) = bhNone);
  end;

  procedure TFormHelpersTest.TestLeftEdge;
  begin
    AssertTrue('left', TyHitTestBorder(CR, Point(2, 50), ZONE) = bhLeft);
  end;

  procedure TFormHelpersTest.TestRightEdge;
  begin
    AssertTrue('right', TyHitTestBorder(CR, Point(198, 50), ZONE) = bhRight);
  end;

  procedure TFormHelpersTest.TestTopEdge;
  begin
    AssertTrue('top', TyHitTestBorder(CR, Point(100, 2), ZONE) = bhTop);
  end;

  procedure TFormHelpersTest.TestBottomEdge;
  begin
    AssertTrue('bottom', TyHitTestBorder(CR, Point(100, 98), ZONE) = bhBottom);
  end;

  procedure TFormHelpersTest.TestTopLeftCorner;
  begin
    AssertTrue('topleft', TyHitTestBorder(CR, Point(2, 2), ZONE) = bhTopLeft);
  end;

  procedure TFormHelpersTest.TestTopRightCorner;
  begin
    AssertTrue('topright', TyHitTestBorder(CR, Point(198, 2), ZONE) = bhTopRight);
  end;

  procedure TFormHelpersTest.TestBottomLeftCorner;
  begin
    AssertTrue('bottomleft', TyHitTestBorder(CR, Point(2, 98), ZONE) = bhBottomLeft);
  end;

  procedure TFormHelpersTest.TestBottomRightCorner;
  begin
    AssertTrue('bottomright', TyHitTestBorder(CR, Point(198, 98), ZONE) = bhBottomRight);
  end;

  procedure TFormHelpersTest.TestZeroZoneIsNone;
  begin
    AssertTrue('zerozone', TyHitTestBorder(CR, Point(0, 0), 0) = bhNone);
  end;

  procedure TFormHelpersTest.TestMaximizedBoundsEqualsWorkArea;
  var
    Wa, R: TRect;
  begin
    Wa := Rect(0, 0, 1920, 1040);
    R := TyMaximizedBounds(Wa);
    AssertEquals('left', 0, R.Left);
    AssertEquals('top', 0, R.Top);
    AssertEquals('right', 1920, R.Right);
    AssertEquals('bottom', 1040, R.Bottom);
  end;

  initialization
    RegisterTest(TFormHelpersTest);

  end.
  ```

- [ ] **Step 3: Add `test.form` to the runner uses clause.** In `/tests/tytests.lpr`, add `test.form` to the `uses` clause of the console test runner program so the registered tests are linked in.

- [ ] **Step 4: Run the suite expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`.
  Expected: all `TFormHelpersTest` tests pass (the helper implementation in Step 1 already satisfies them; this task front-loads helper code because the rest of the section depends on it). If any zone assertion fails, the bug is in `TyHitTestBorder`.

- [ ] **Step 5: Commit.** `git add source/tyControls.Form.pas tests/test.form.pas tests/tytests.lpr` then `git commit -m "feat(tycontrols): add TyHitTestBorder/TyMaximizedBounds window helpers with tests"`.

### Task FORM.2: TTyCaptionButton (Kind drives variant + glyph)

**Files:**
- Modify: `/source/tyControls.Form.pas`
- Modify: `/tests/test.form.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Write the failing test for caption-button Kind→variant/glyph mapping.** Add a new test case to `/tests/test.form.pas` covering all four kinds. Append to the `uses` of `test.form` the units `Controls, Graphics, tyControls.Painter` (for `TTyGlyphKind`) and add the class:
  ```pascal
  type
    TCaptionButtonTest = class(TTestCase)
    published
      procedure TestCloseVariantAndGlyph;
      procedure TestMinVariantAndGlyph;
      procedure TestMaxVariantAndGlyph;
      procedure TestRestoreVariantAndGlyph;
      procedure TestTypeKey;
    end;
  ```
  And the implementations:
  ```pascal
  procedure TCaptionButtonTest.TestCloseVariantAndGlyph;
  var
    B: TTyCaptionButton;
  begin
    B := TTyCaptionButton.Create(nil);
    try
      B.Kind := cbkClose;
      AssertEquals('variant', 'close', B.KindVariant);
      AssertTrue('glyph', B.KindGlyph = tgClose);
    finally
      B.Free;
    end;
  end;

  procedure TCaptionButtonTest.TestMinVariantAndGlyph;
  var
    B: TTyCaptionButton;
  begin
    B := TTyCaptionButton.Create(nil);
    try
      B.Kind := cbkMin;
      AssertEquals('variant', 'min', B.KindVariant);
      AssertTrue('glyph', B.KindGlyph = tgMinimize);
    finally
      B.Free;
    end;
  end;

  procedure TCaptionButtonTest.TestMaxVariantAndGlyph;
  var
    B: TTyCaptionButton;
  begin
    B := TTyCaptionButton.Create(nil);
    try
      B.Kind := cbkMax;
      AssertEquals('variant', 'max', B.KindVariant);
      AssertTrue('glyph', B.KindGlyph = tgMaximize);
    finally
      B.Free;
    end;
  end;

  procedure TCaptionButtonTest.TestRestoreVariantAndGlyph;
  var
    B: TTyCaptionButton;
  begin
    B := TTyCaptionButton.Create(nil);
    try
      B.Kind := cbkRestore;
      AssertEquals('variant', 'restore', B.KindVariant);
      AssertTrue('glyph', B.KindGlyph = tgRestore);
    finally
      B.Free;
    end;
  end;

  procedure TCaptionButtonTest.TestTypeKey;
  var
    B: TTyCaptionButton;
  begin
    B := TTyCaptionButton.Create(nil);
    try
      AssertEquals('typekey', 'TyCaptionButton', B.GetStyleTypeKey);
    finally
      B.Free;
    end;
  end;
  ```
  Register it in the `initialization` block: `RegisterTest(TCaptionButtonTest);` and add `tyControls.Form` is already in uses.

- [ ] **Step 2: Run the suite expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`.
  Expected: build fails (compile error) because `TTyCaptionButton`, `cbkClose`, `KindVariant`, `KindGlyph` do not yet exist in `tyControls.Form`.

- [ ] **Step 3: Add the unit dependencies to the implementation unit.** In `/source/tyControls.Form.pas`, extend the `uses` clause to:
  ```pascal
  uses
    Classes, SysUtils, Types, Controls, Graphics, Forms,
    tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller;
  ```

- [ ] **Step 4: Declare TTyCaptionButton in the interface.** Add the kind enum and class declaration to the `interface` of `/source/tyControls.Form.pas` (before the `function` lines is fine; place after the `TTyBorderHit` type):
  ```pascal
  type
    TTyCaptionButtonKind = (cbkClose, cbkMin, cbkMax, cbkRestore);

    TTyCaptionButton = class(TTyCustomControl)
    private
      FKind: TTyCaptionButtonKind;
      procedure SetKind(AValue: TTyCaptionButtonKind);
    protected
      function GetStyleTypeKey: string; override;
      procedure Paint; override;
      procedure Click; override;
    public
      function KindVariant: string;
      function KindGlyph: TTyGlyphKind;
    published
      property Kind: TTyCaptionButtonKind read FKind write SetKind;
      property OnClick;
    end;
  ```

- [ ] **Step 5: Implement TTyCaptionButton.** Add to the `implementation` section of `/source/tyControls.Form.pas`:
  ```pascal
  procedure TTyCaptionButton.SetKind(AValue: TTyCaptionButtonKind);
  begin
    if FKind = AValue then
      Exit;
    FKind := AValue;
    StyleClass := KindVariant;
    Invalidate;
  end;

  function TTyCaptionButton.GetStyleTypeKey: string;
  begin
    Result := 'TyCaptionButton';
  end;

  function TTyCaptionButton.KindVariant: string;
  begin
    case FKind of
      cbkClose: Result := 'close';
      cbkMin: Result := 'min';
      cbkMax: Result := 'max';
      cbkRestore: Result := 'restore';
    else
      Result := 'close';
    end;
  end;

  function TTyCaptionButton.KindGlyph: TTyGlyphKind;
  begin
    case FKind of
      cbkClose: Result := tgClose;
      cbkMin: Result := tgMinimize;
      cbkMax: Result := tgMaximize;
      cbkRestore: Result := tgRestore;
    else
      Result := tgClose;
    end;
  end;

  procedure TTyCaptionButton.Click;
  begin
    inherited Click;
  end;

  procedure TTyCaptionButton.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    GlyphRect: TRect;
    GlyphSize: Integer;
    CX, CY: Integer;
  begin
    P := TTyPainter.Create;
    try
      P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
      S := CurrentStyle;
      DrawFrame(P, ClientRect, S);
      GlyphSize := P.Scale(10);
      CX := (ClientWidth - GlyphSize) div 2;
      CY := (ClientHeight - GlyphSize) div 2;
      GlyphRect := Rect(CX, CY, CX + GlyphSize, CY + GlyphSize);
      P.DrawGlyph(GlyphRect, KindGlyph, S.TextColor, P.Scale(1));
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  ```

- [ ] **Step 6: Run the suite expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`.
  Expected: all `TCaptionButtonTest` tests pass (`KindVariant`='close' and `KindGlyph`=`tgClose` for `cbkClose`, etc.); `TFormHelpersTest` still passes.

- [ ] **Step 7: Commit.** `git add source/tyControls.Form.pas tests/test.form.pas` then `git commit -m "feat(tycontrols): add TTyCaptionButton with Kind-driven variant and glyph"`.

### Task FORM.3: TTyTitleBar (icon + caption + three caption buttons, laid out on Resize)

**Files:**
- Modify: `/source/tyControls.Form.pas`
- Modify: `/tests/test.form.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Write the failing test for the title bar.** Add to `/tests/test.form.pas` a test that verifies the title bar owns three caption buttons of the correct kinds, exposes `Caption`, reports its typeKey, and right-aligns the buttons after a resize:
  ```pascal
  type
    TTitleBarTest = class(TTestCase)
    published
      procedure TestTypeKey;
      procedure TestCaptionProperty;
      procedure TestHasThreeButtons;
      procedure TestButtonKinds;
      procedure TestButtonsRightAlignedAfterResize;
    end;
  ```
  Implementations:
  ```pascal
  procedure TTitleBarTest.TestTypeKey;
  var
    T: TTyTitleBar;
  begin
    T := TTyTitleBar.Create(nil);
    try
      AssertEquals('typekey', 'TyTitleBar', T.GetStyleTypeKey);
    finally
      T.Free;
    end;
  end;

  procedure TTitleBarTest.TestCaptionProperty;
  var
    T: TTyTitleBar;
  begin
    T := TTyTitleBar.Create(nil);
    try
      T.Caption := 'Hello';
      AssertEquals('caption', 'Hello', T.Caption);
    finally
      T.Free;
    end;
  end;

  procedure TTitleBarTest.TestHasThreeButtons;
  var
    T: TTyTitleBar;
  begin
    T := TTyTitleBar.Create(nil);
    try
      AssertTrue('min', T.MinButton <> nil);
      AssertTrue('max', T.MaxButton <> nil);
      AssertTrue('close', T.CloseButton <> nil);
    finally
      T.Free;
    end;
  end;

  procedure TTitleBarTest.TestButtonKinds;
  var
    T: TTyTitleBar;
  begin
    T := TTyTitleBar.Create(nil);
    try
      AssertTrue('min kind', T.MinButton.Kind = cbkMin);
      AssertTrue('max kind', T.MaxButton.Kind = cbkMax);
      AssertTrue('close kind', T.CloseButton.Kind = cbkClose);
    finally
      T.Free;
    end;
  end;

  procedure TTitleBarTest.TestButtonsRightAlignedAfterResize;
  var
    T: TTyTitleBar;
  begin
    T := TTyTitleBar.Create(nil);
    try
      T.SetBounds(0, 0, 300, 32);
      AssertEquals('close at right', 300, T.CloseButton.Left + T.CloseButton.Width);
      AssertTrue('max left of close', T.MaxButton.Left < T.CloseButton.Left);
      AssertTrue('min left of max', T.MinButton.Left < T.MaxButton.Left);
    finally
      T.Free;
    end;
  end;
  ```
  Add `RegisterTest(TTitleBarTest);` in the `initialization` block.

- [ ] **Step 2: Run the suite expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`.
  Expected: build fails because `TTyTitleBar`, `MinButton`, `MaxButton`, `CloseButton` do not yet exist.

- [ ] **Step 3: Declare TTyTitleBar in the interface.** Add to the `interface` of `/source/tyControls.Form.pas` (after `TTyCaptionButton`):
  ```pascal
  type
    TTyTitleBar = class(TTyCustomControl)
    private
      FCaption: string;
      FMinButton: TTyCaptionButton;
      FMaxButton: TTyCaptionButton;
      FCloseButton: TTyCaptionButton;
      FButtonWidth: Integer;
      procedure SetCaption(const AValue: string);
      procedure LayoutButtons;
    protected
      function GetStyleTypeKey: string; override;
      procedure Resize; override;
      procedure Paint; override;
    public
      constructor Create(AOwner: TComponent); override;
      property MinButton: TTyCaptionButton read FMinButton;
      property MaxButton: TTyCaptionButton read FMaxButton;
      property CloseButton: TTyCaptionButton read FCloseButton;
    published
      property Caption: string read FCaption write SetCaption;
    end;
  ```

- [ ] **Step 4: Implement TTyTitleBar.** Add to the `implementation` of `/source/tyControls.Form.pas`:
  ```pascal
  constructor TTyTitleBar.Create(AOwner: TComponent);
  begin
    inherited Create(AOwner);
    FButtonWidth := 46;
    SetBounds(0, 0, 200, 32);
    FMinButton := TTyCaptionButton.Create(Self);
    FMinButton.Kind := cbkMin;
    FMinButton.Parent := Self;
    FMaxButton := TTyCaptionButton.Create(Self);
    FMaxButton.Kind := cbkMax;
    FMaxButton.Parent := Self;
    FCloseButton := TTyCaptionButton.Create(Self);
    FCloseButton.Kind := cbkClose;
    FCloseButton.Parent := Self;
    LayoutButtons;
  end;

  function TTyTitleBar.GetStyleTypeKey: string;
  begin
    Result := 'TyTitleBar';
  end;

  procedure TTyTitleBar.SetCaption(const AValue: string);
  begin
    if FCaption = AValue then
      Exit;
    FCaption := AValue;
    Invalidate;
  end;

  procedure TTyTitleBar.LayoutButtons;
  var
    W, H, X: Integer;
  begin
    if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then
      Exit;
    W := FButtonWidth;
    H := ClientHeight;
    X := ClientWidth - W;
    FCloseButton.SetBounds(X, 0, W, H);
    Dec(X, W);
    FMaxButton.SetBounds(X, 0, W, H);
    Dec(X, W);
    FMinButton.SetBounds(X, 0, W, H);
  end;

  procedure TTyTitleBar.Resize;
  begin
    inherited Resize;
    LayoutButtons;
  end;

  procedure TTyTitleBar.Paint;
  var
    P: TTyPainter;
    S: TTyStyleSet;
    TextRect: TRect;
  begin
    P := TTyPainter.Create;
    try
      P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
      S := CurrentStyle;
      DrawFrame(P, ClientRect, S);
      TextRect := Rect(P.Scale(8), 0, ClientWidth - 3 * FButtonWidth, ClientHeight);
      P.DrawText(TextRect, FCaption, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);
      P.EndPaint;
    finally
      P.Free;
    end;
  end;
  ```

- [ ] **Step 5: Run the suite expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`.
  Expected: all `TTitleBarTest` tests pass (three buttons exist with kinds `cbkMin`/`cbkMax`/`cbkClose`, close button right edge = 300 after `SetBounds(0,0,300,32)`); earlier tests still pass.

- [ ] **Step 6: Commit.** `git add source/tyControls.Form.pas tests/test.form.pas` then `git commit -m "feat(tycontrols): add TTyTitleBar hosting caption and three caption buttons"`.

### Task FORM.4: TTyFormChrome (Active runtime install, drag/resize/min-max-close, double-click maximize)

**Files:**
- Modify: `/source/tyControls.Form.pas`
- Modify: `/tests/test.form.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Write the failing test for TTyFormChrome defaults and design-time inactivity.** Add to `/tests/test.form.pas`:
  ```pascal
  type
    TFormChromeTest = class(TTestCase)
    published
      procedure TestDefaultTitleHeight;
      procedure TestDefaultBorderZone;
      procedure TestDefaultShowFlags;
      procedure TestTitleBarCreated;
      procedure TestActiveDefaultsFalse;
    end;
  ```
  Implementations:
  ```pascal
  procedure TFormChromeTest.TestDefaultTitleHeight;
  var
    C: TTyFormChrome;
  begin
    C := TTyFormChrome.Create(nil);
    try
      AssertEquals('titleheight', 32, C.TitleHeight);
    finally
      C.Free;
    end;
  end;

  procedure TFormChromeTest.TestDefaultBorderZone;
  var
    C: TTyFormChrome;
  begin
    C := TTyFormChrome.Create(nil);
    try
      AssertEquals('borderzone', 6, C.BorderZone);
    finally
      C.Free;
    end;
  end;

  procedure TFormChromeTest.TestDefaultShowFlags;
  var
    C: TTyFormChrome;
  begin
    C := TTyFormChrome.Create(nil);
    try
      AssertTrue('min', C.ShowMinimize);
      AssertTrue('max', C.ShowMaximize);
    finally
      C.Free;
    end;
  end;

  procedure TFormChromeTest.TestTitleBarCreated;
  var
    C: TTyFormChrome;
  begin
    C := TTyFormChrome.Create(nil);
    try
      AssertTrue('titlebar', C.TitleBar <> nil);
    finally
      C.Free;
    end;
  end;

  procedure TFormChromeTest.TestActiveDefaultsFalse;
  var
    C: TTyFormChrome;
  begin
    C := TTyFormChrome.Create(nil);
    try
      AssertFalse('active', C.Active);
    finally
      C.Free;
    end;
  end;
  ```
  Add `RegisterTest(TFormChromeTest);` in the `initialization` block.

- [ ] **Step 2: Run the suite expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`.
  Expected: build fails because `TTyFormChrome`, `TitleHeight`, `BorderZone`, `ShowMinimize`, `ShowMaximize`, `TitleBar`, `Active` do not yet exist.

- [ ] **Step 3: Declare TTyFormChrome in the interface.** Add to the `interface` of `/source/tyControls.Form.pas`:
  ```pascal
  type
    TTyFormChrome = class(TComponent)
    private
      FActive: Boolean;
      FTitleHeight: Integer;
      FBorderZone: Integer;
      FShowMinimize: Boolean;
      FShowMaximize: Boolean;
      FTitleBar: TTyTitleBar;
      FForm: TCustomForm;
      FDragging: Boolean;
      FDragStart: TPoint;
      FResizeHit: TTyBorderHit;
      FResizing: Boolean;
      FResizeStartBounds: TRect;
      FResizeStartMouse: TPoint;
      FSavedBounds: TRect;
      FMaximized: Boolean;
      procedure SetActive(AValue: Boolean);
      procedure SetTitleHeight(AValue: Integer);
      function HostForm: TCustomForm;
      procedure InstallChrome;
      procedure UninstallChrome;
      procedure FormMouseDown(Sender: TObject; Button: TMouseButton;
        Shift: TShiftState; X, Y: Integer);
      procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
      procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
        Shift: TShiftState; X, Y: Integer);
      procedure TitleBarMouseDown(Sender: TObject; Button: TMouseButton;
        Shift: TShiftState; X, Y: Integer);
      procedure TitleBarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
      procedure TitleBarMouseUp(Sender: TObject; Button: TMouseButton;
        Shift: TShiftState; X, Y: Integer);
      procedure TitleBarDblClick(Sender: TObject);
      procedure DoMinimize(Sender: TObject);
      procedure DoMaxRestore(Sender: TObject);
      procedure DoClose(Sender: TObject);
    public
      constructor Create(AOwner: TComponent); override;
      property TitleBar: TTyTitleBar read FTitleBar;
      procedure ToggleMaximize;
    published
      property Active: Boolean read FActive write SetActive default False;
      property TitleHeight: Integer read FTitleHeight write SetTitleHeight default 32;
      property BorderZone: Integer read FBorderZone write FBorderZone default 6;
      property ShowMinimize: Boolean read FShowMinimize write FShowMinimize default True;
      property ShowMaximize: Boolean read FShowMaximize write FShowMaximize default True;
    end;
  ```

- [ ] **Step 4: Implement TTyFormChrome construction, properties, and install/uninstall.** Add to the `implementation` of `/source/tyControls.Form.pas`:
  ```pascal
  constructor TTyFormChrome.Create(AOwner: TComponent);
  begin
    inherited Create(AOwner);
    FTitleHeight := 32;
    FBorderZone := 6;
    FShowMinimize := True;
    FShowMaximize := True;
    FActive := False;
    FMaximized := False;
    FTitleBar := TTyTitleBar.Create(Self);
    FTitleBar.MinButton.OnClick := @DoMinimize;
    FTitleBar.MaxButton.OnClick := @DoMaxRestore;
    FTitleBar.CloseButton.OnClick := @DoClose;
  end;

  function TTyFormChrome.HostForm: TCustomForm;
  begin
    Result := nil;
    if (Owner <> nil) and (Owner is TCustomForm) then
      Result := TCustomForm(Owner);
  end;

  procedure TTyFormChrome.SetTitleHeight(AValue: Integer);
  begin
    if FTitleHeight = AValue then
      Exit;
    FTitleHeight := AValue;
    if FActive and (FForm <> nil) then
      FTitleBar.SetBounds(0, 0, FForm.ClientWidth, FTitleHeight);
  end;

  procedure TTyFormChrome.SetActive(AValue: Boolean);
  begin
    if FActive = AValue then
      Exit;
    FActive := AValue;
    if csDesigning in ComponentState then
      Exit;
    if FActive then
      InstallChrome
    else
      UninstallChrome;
  end;

  procedure TTyFormChrome.InstallChrome;
  begin
    FForm := HostForm;
    if FForm = nil then
      Exit;
    FForm.BorderStyle := bsNone;
    FTitleBar.Parent := FForm;
    FTitleBar.Align := alTop;
    FTitleBar.SetBounds(0, 0, FForm.ClientWidth, FTitleHeight);
    FTitleBar.MinButton.Visible := FShowMinimize;
    FTitleBar.MaxButton.Visible := FShowMaximize;
    FForm.OnMouseDown := @FormMouseDown;
    FForm.OnMouseMove := @FormMouseMove;
    FForm.OnMouseUp := @FormMouseUp;
    FTitleBar.OnMouseDown := @TitleBarMouseDown;
    FTitleBar.OnMouseMove := @TitleBarMouseMove;
    FTitleBar.OnMouseUp := @TitleBarMouseUp;
    FTitleBar.OnDblClick := @TitleBarDblClick;
  end;

  procedure TTyFormChrome.UninstallChrome;
  begin
    if FForm = nil then
      Exit;
    FForm.OnMouseDown := nil;
    FForm.OnMouseMove := nil;
    FForm.OnMouseUp := nil;
    FTitleBar.Parent := nil;
    FForm := nil;
  end;
  ```

- [ ] **Step 5: Implement the drag, resize, and window-state behaviors.** Add to the `implementation` of `/source/tyControls.Form.pas`:
  ```pascal
  procedure TTyFormChrome.TitleBarMouseDown(Sender: TObject; Button: TMouseButton;
    Shift: TShiftState; X, Y: Integer);
  begin
    if (Button = mbLeft) and (FForm <> nil) and not FMaximized then
    begin
      FDragging := True;
      FDragStart := Point(X, Y);
    end;
  end;

  procedure TTyFormChrome.TitleBarMouseMove(Sender: TObject; Shift: TShiftState;
    X, Y: Integer);
  begin
    if FDragging and (FForm <> nil) then
    begin
      FForm.Left := FForm.Left + (X - FDragStart.X);
      FForm.Top := FForm.Top + (Y - FDragStart.Y);
    end;
  end;

  procedure TTyFormChrome.TitleBarMouseUp(Sender: TObject; Button: TMouseButton;
    Shift: TShiftState; X, Y: Integer);
  begin
    FDragging := False;
  end;

  procedure TTyFormChrome.TitleBarDblClick(Sender: TObject);
  begin
    ToggleMaximize;
  end;

  procedure TTyFormChrome.FormMouseDown(Sender: TObject; Button: TMouseButton;
    Shift: TShiftState; X, Y: Integer);
  begin
    if (Button <> mbLeft) or (FForm = nil) or FMaximized then
      Exit;
    FResizeHit := TyHitTestBorder(Rect(0, 0, FForm.Width, FForm.Height),
      Point(X, Y), FBorderZone);
    if FResizeHit <> bhNone then
    begin
      FResizing := True;
      FResizeStartBounds := FForm.BoundsRect;
      FResizeStartMouse := FForm.ClientToScreen(Point(X, Y));
    end;
  end;

  procedure TTyFormChrome.FormMouseMove(Sender: TObject; Shift: TShiftState;
    X, Y: Integer);
  var
    M: TPoint;
    DX, DY: Integer;
    B: TRect;
  begin
    if not FResizing or (FForm = nil) then
      Exit;
    M := FForm.ClientToScreen(Point(X, Y));
    DX := M.X - FResizeStartMouse.X;
    DY := M.Y - FResizeStartMouse.Y;
    B := FResizeStartBounds;
    case FResizeHit of
      bhLeft: B.Left := B.Left + DX;
      bhRight: B.Right := B.Right + DX;
      bhTop: B.Top := B.Top + DY;
      bhBottom: B.Bottom := B.Bottom + DY;
      bhTopLeft: begin B.Left := B.Left + DX; B.Top := B.Top + DY; end;
      bhTopRight: begin B.Right := B.Right + DX; B.Top := B.Top + DY; end;
      bhBottomLeft: begin B.Left := B.Left + DX; B.Bottom := B.Bottom + DY; end;
      bhBottomRight: begin B.Right := B.Right + DX; B.Bottom := B.Bottom + DY; end;
    end;
    if B.Right - B.Left < 80 then
      B.Right := B.Left + 80;
    if B.Bottom - B.Top < 60 then
      B.Bottom := B.Top + 60;
    FForm.BoundsRect := B;
  end;

  procedure TTyFormChrome.FormMouseUp(Sender: TObject; Button: TMouseButton;
    Shift: TShiftState; X, Y: Integer);
  begin
    FResizing := False;
    FResizeHit := bhNone;
  end;

  procedure TTyFormChrome.ToggleMaximize;
  var
    Wa: TRect;
  begin
    if FForm = nil then
      Exit;
    if FMaximized then
    begin
      FForm.BoundsRect := FSavedBounds;
      FMaximized := False;
      FTitleBar.MaxButton.Kind := cbkMax;
    end
    else
    begin
      FSavedBounds := FForm.BoundsRect;
      Wa := Screen.MonitorFromWindow(FForm.Handle).WorkareaRect;
      FForm.BoundsRect := TyMaximizedBounds(Wa);
      FMaximized := True;
      FTitleBar.MaxButton.Kind := cbkRestore;
    end;
  end;

  procedure TTyFormChrome.DoMinimize(Sender: TObject);
  begin
    if FForm <> nil then
      FForm.WindowState := wsMinimized;
  end;

  procedure TTyFormChrome.DoMaxRestore(Sender: TObject);
  begin
    ToggleMaximize;
  end;

  procedure TTyFormChrome.DoClose(Sender: TObject);
  begin
    if FForm <> nil then
      FForm.Close;
  end;
  ```

- [ ] **Step 6: Run the suite expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`.
  Expected: all `TFormChromeTest` tests pass (`TitleHeight`=32, `BorderZone`=6, `ShowMinimize`/`ShowMaximize`=True, `TitleBar`<>nil, `Active`=False by default); all earlier form tests still pass.

- [ ] **Step 7: Commit.** `git add source/tyControls.Form.pas tests/test.form.pas` then `git commit -m "feat(tycontrols): add TTyFormChrome with drag/resize/min-max-close behaviors"`.

### Task FORM.5: Document the known window-subsystem gaps

**Files:**
- Create: `/docs/tycontrols-known-gaps.md`

- [ ] **Step 1: Create the known-gaps doc.** Write `/docs/tycontrols-known-gaps.md` documenting the v1 window-subsystem limitations:
  ```markdown
  # TyControls — Known Gaps (Window Subsystem, v1)

  The v1 window subsystem (`TTyFormChrome` / `TTyTitleBar`) is a cross-platform
  manual implementation chosen for consistent appearance across Windows, Linux,
  and macOS. It deliberately does NOT implement the following native behaviors.
  These are tracked for a Tier-2 native enhancement layer and must NOT be assumed
  present in v1.

  ## Not implemented in v1

  - **Windows Aero Snap** — dragging to a screen edge does not trigger
    snap-to-half / snap-to-quadrant tiling. Drag only moves the form.
  - **Native drop shadow on borderless windows** — because the form uses
    `BorderStyle := bsNone`, the OS-provided window shadow is lost. v1 renders
    no substitute shadow around the form frame.
  - **macOS traffic-light buttons** — the close/minimize/maximize buttons are
    drawn by `TTyCaptionButton` (vector glyphs), not the native macOS red/yellow/
    green controls; macOS users do not get platform-standard window controls.
  - **Cross-monitor DPI switching** — moving a maximized or dragged window between
    monitors with different scaling factors does not re-scale chrome metrics on
    the fly; PPI is sampled from the host form's font at paint time.

  ## Scope note

  Maximize uses the active monitor work area (`Screen.MonitorFromWindow(...)
  .WorkareaRect` via `TyMaximizedBounds`) so the taskbar is avoided, but the
  above native integrations remain out of scope for v1.
  ```

- [ ] **Step 2: Verify the doc renders.** Run `ls -l docs/tycontrols-known-gaps.md` to confirm the file exists and is non-empty.
  Expected: the file is listed with a non-zero byte size.

- [ ] **Step 3: Commit.** `git add docs/tycontrols-known-gaps.md` then `git commit -m "docs(tycontrols): document v1 window subsystem known gaps"`.
```

---

## P4 · Themes + Packaging + Design-time + Examples

### Task INTEGRATION.1: Light theme stylesheet

**Files:**
- Create: `/themes/light.tycss`

> Note: theme `font-size` values are interpreted as points; any `px` suffix is stripped and the number is used directly as the logical point size (the numbers are not rescaled).

- [ ] **Step 1: Write `/themes/light.tycss` with a full `:root` palette and rules for every typeKey.** Create the file with exactly this content (every typeKey from the contract styled via palette vars, variants, and states):
  ```css
  /* TyControls — Light theme */
  :root {
    --accent:     #3B82F6;
    --surface:    #FFFFFF;
    --on-surface: #1F2937;
    --border:     #D1D5DB;
    --danger:     #EF4444;
    --radius:     6px;
  }

  TyButton {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 6px;
    font-size: 10px;
    font-weight: 400;
  }
  TyButton:hover    { background: darken(--surface, 4%); }
  TyButton:focus    { border-color: var(--accent); }
  TyButton:active   { background: darken(--surface, 10%); }
  TyButton:disabled { opacity: 0.5; }
  TyButton.primary  { background: var(--accent); color: #FFFFFF; border-color: var(--accent); }
  TyButton.primary:hover    { background: lighten(--accent, 8%); }
  TyButton.primary:active   { background: darken(--accent, 8%); }
  TyButton.danger   { background: var(--danger); color: #FFFFFF; border-color: var(--danger); }
  TyButton.danger:hover     { background: lighten(--danger, 8%); }
  TyButton.danger:active    { background: darken(--danger, 8%); }

  TyLabel {
    background: alpha(#FFFFFF, 0);
    color: var(--on-surface);
    font-size: 10px;
    font-weight: 400;
  }
  TyLabel:disabled { opacity: 0.5; }

  TyEdit {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 4px;
    font-size: 10px;
  }
  TyEdit:hover    { border-color: darken(--border, 10%); }
  TyEdit:focus    { border-color: var(--accent); }
  TyEdit:disabled { opacity: 0.5; }

  TyCheckBox {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: 3px;
  }
  TyCheckBox:hover    { border-color: var(--accent); }
  TyCheckBox:active   { background: var(--accent); }
  TyCheckBox:disabled { opacity: 0.5; }

  TyRadioButton {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: 8px;
  }
  TyRadioButton:hover    { border-color: var(--accent); }
  TyRadioButton:active   { background: var(--accent); }
  TyRadioButton:disabled { opacity: 0.5; }

  TyPanel {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 8px;
  }

  TyComboBox {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 4px;
    font-size: 10px;
  }
  TyComboBox:hover    { border-color: darken(--border, 10%); }
  TyComboBox:focus    { border-color: var(--accent); }
  TyComboBox:disabled { opacity: 0.5; }

  TyScrollBar {
    background: darken(--surface, 6%);
    color: var(--border);
    border-radius: 4px;
  }
  TyScrollBar:hover  { color: darken(--border, 15%); }
  TyScrollBar:active { color: var(--accent); }

  TyTitleBar {
    background: darken(--surface, 6%);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    font-size: 10px;
    font-weight: 700;
  }

  TyCaptionButton {
    background: alpha(#FFFFFF, 0);
    color: var(--on-surface);
    border-radius: 0px;
  }
  TyCaptionButton:hover  { background: darken(--surface, 12%); }
  TyCaptionButton:active { background: darken(--surface, 20%); }
  TyCaptionButton.close:hover  { background: var(--danger); color: #FFFFFF; }
  TyCaptionButton.close:active { background: darken(--danger, 10%); color: #FFFFFF; }
  TyCaptionButton.min:hover    { background: darken(--surface, 12%); }
  TyCaptionButton.max:hover    { background: darken(--surface, 12%); }
  ```
- [ ] **Step 2: Verify the file is syntactically loadable.** Run `lazbuild --version >/dev/null 2>&1; test -s /themes/light.tycss && grep -c 'TyButton' /Users/tom/Projects/TyControls/themes/light.tycss`. Expected: prints a count >= 1 (file exists and references TyButton). The authoritative load check runs in Task INTEGRATION.10.
- [ ] **Step 3: Commit.** Run `git add themes/light.tycss && git commit -m "feat(tycontrols): add light.tycss theme styling all typeKeys"`.

### Task INTEGRATION.2: Dark theme stylesheet

**Files:**
- Create: `/themes/dark.tycss`

- [ ] **Step 1: Write `/themes/dark.tycss` with a full `:root` palette and rules for every typeKey.** Create the file with exactly this content:
  ```css
  /* TyControls — Dark theme */
  :root {
    --accent:     #60A5FA;
    --surface:    #1E1E1E;
    --on-surface: #E5E7EB;
    --border:     #3F3F46;
    --danger:     #F87171;
    --radius:     6px;
  }

  TyButton {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 6px;
    font-size: 10px;
    font-weight: 400;
  }
  TyButton:hover    { background: lighten(--surface, 8%); }
  TyButton:focus    { border-color: var(--accent); }
  TyButton:active   { background: darken(--surface, 6%); }
  TyButton:disabled { opacity: 0.5; }
  TyButton.primary  { background: var(--accent); color: #0B1120; border-color: var(--accent); }
  TyButton.primary:hover    { background: lighten(--accent, 8%); }
  TyButton.primary:active   { background: darken(--accent, 8%); }
  TyButton.danger   { background: var(--danger); color: #0B1120; border-color: var(--danger); }
  TyButton.danger:hover     { background: lighten(--danger, 8%); }
  TyButton.danger:active    { background: darken(--danger, 8%); }

  TyLabel {
    background: alpha(#000000, 0);
    color: var(--on-surface);
    font-size: 10px;
    font-weight: 400;
  }
  TyLabel:disabled { opacity: 0.5; }

  TyEdit {
    background: lighten(--surface, 4%);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 4px;
    font-size: 10px;
  }
  TyEdit:hover    { border-color: lighten(--border, 12%); }
  TyEdit:focus    { border-color: var(--accent); }
  TyEdit:disabled { opacity: 0.5; }

  TyCheckBox {
    background: lighten(--surface, 4%);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: 3px;
  }
  TyCheckBox:hover    { border-color: var(--accent); }
  TyCheckBox:active   { background: var(--accent); }
  TyCheckBox:disabled { opacity: 0.5; }

  TyRadioButton {
    background: lighten(--surface, 4%);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: 8px;
  }
  TyRadioButton:hover    { border-color: var(--accent); }
  TyRadioButton:active   { background: var(--accent); }
  TyRadioButton:disabled { opacity: 0.5; }

  TyPanel {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 8px;
  }

  TyComboBox {
    background: lighten(--surface, 4%);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 4px;
    font-size: 10px;
  }
  TyComboBox:hover    { border-color: lighten(--border, 12%); }
  TyComboBox:focus    { border-color: var(--accent); }
  TyComboBox:disabled { opacity: 0.5; }

  TyScrollBar {
    background: darken(--surface, 4%);
    color: lighten(--border, 10%);
    border-radius: 4px;
  }
  TyScrollBar:hover  { color: lighten(--border, 25%); }
  TyScrollBar:active { color: var(--accent); }

  TyTitleBar {
    background: lighten(--surface, 4%);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    font-size: 10px;
    font-weight: 700;
  }

  TyCaptionButton {
    background: alpha(#000000, 0);
    color: var(--on-surface);
    border-radius: 0px;
  }
  TyCaptionButton:hover  { background: lighten(--surface, 16%); }
  TyCaptionButton:active { background: lighten(--surface, 24%); }
  TyCaptionButton.close:hover  { background: var(--danger); color: #0B1120; }
  TyCaptionButton.close:active { background: darken(--danger, 10%); color: #0B1120; }
  TyCaptionButton.min:hover    { background: lighten(--surface, 16%); }
  TyCaptionButton.max:hover    { background: lighten(--surface, 16%); }
  ```
- [ ] **Step 2: Verify the file exists and references the dark surface palette.** Run `test -s /Users/tom/Projects/TyControls/themes/dark.tycss && grep -c '#1E1E1E' /Users/tom/Projects/TyControls/themes/dark.tycss`. Expected: prints a count >= 1.
- [ ] **Step 3: Commit.** Run `git add themes/dark.tycss && git commit -m "feat(tycontrols): add dark.tycss theme styling all typeKeys"`.

### Task INTEGRATION.3: Showcase facade theme stylesheet

**Files:**
- Create: `/themes/showcase.tycss`

- [ ] **Step 1: Write `/themes/showcase.tycss` (a distinctive Material-ish facade) styling every typeKey via palette vars, gradients, and shadow.** Create the file with exactly this content:
  ```css
  /* TyControls — Showcase facade theme (Material-ish) */
  :root {
    --accent:     #7C3AED;
    --surface:    #F5F3FF;
    --on-surface: #2E1065;
    --border:     #C4B5FD;
    --danger:     #DB2777;
    --radius:     10px;
  }

  TyButton {
    background: linear-gradient(90deg, var(--surface), darken(--surface, 6%));
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 8px;
    font-size: 10px;
    font-weight: 700;
    shadow: alpha(#000000, 0.18);
  }
  TyButton:hover    { background: linear-gradient(90deg, lighten(--surface, 3%), darken(--surface, 4%)); }
  TyButton:focus    { border-color: var(--accent); }
  TyButton:active   { background: darken(--surface, 10%); }
  TyButton:disabled { opacity: 0.45; }
  TyButton.primary  { background: linear-gradient(90deg, lighten(--accent, 10%), var(--accent)); color: #FFFFFF; border-color: var(--accent); }
  TyButton.primary:hover    { background: linear-gradient(90deg, lighten(--accent, 16%), lighten(--accent, 4%)); }
  TyButton.primary:active   { background: darken(--accent, 10%); }
  TyButton.danger   { background: linear-gradient(90deg, lighten(--danger, 10%), var(--danger)); color: #FFFFFF; border-color: var(--danger); }
  TyButton.danger:hover     { background: linear-gradient(90deg, lighten(--danger, 16%), lighten(--danger, 4%)); }
  TyButton.danger:active    { background: darken(--danger, 10%); }

  TyLabel {
    background: alpha(#FFFFFF, 0);
    color: var(--on-surface);
    font-size: 10px;
    font-weight: 400;
  }
  TyLabel:disabled { opacity: 0.45; }

  TyEdit {
    background: #FFFFFF;
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 2px;
    border-radius: var(--radius);
    padding: 6px;
    font-size: 10px;
  }
  TyEdit:hover    { border-color: lighten(--accent, 10%); }
  TyEdit:focus    { border-color: var(--accent); }
  TyEdit:disabled { opacity: 0.45; }

  TyCheckBox {
    background: #FFFFFF;
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 2px;
    border-radius: 4px;
  }
  TyCheckBox:hover    { border-color: var(--accent); }
  TyCheckBox:active   { background: var(--accent); }
  TyCheckBox:disabled { opacity: 0.45; }

  TyRadioButton {
    background: #FFFFFF;
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 2px;
    border-radius: 9px;
  }
  TyRadioButton:hover    { border-color: var(--accent); }
  TyRadioButton:active   { background: var(--accent); }
  TyRadioButton:disabled { opacity: 0.45; }

  TyPanel {
    background: var(--surface);
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 1px;
    border-radius: var(--radius);
    padding: 10px;
    shadow: alpha(#000000, 0.12);
  }

  TyComboBox {
    background: #FFFFFF;
    color: var(--on-surface);
    border-color: var(--border);
    border-width: 2px;
    border-radius: var(--radius);
    padding: 6px;
    font-size: 10px;
  }
  TyComboBox:hover    { border-color: lighten(--accent, 10%); }
  TyComboBox:focus    { border-color: var(--accent); }
  TyComboBox:disabled { opacity: 0.45; }

  TyScrollBar {
    background: darken(--surface, 4%);
    color: var(--border);
    border-radius: 6px;
  }
  TyScrollBar:hover  { color: var(--accent); }
  TyScrollBar:active { color: darken(--accent, 8%); }

  TyTitleBar {
    background: linear-gradient(90deg, lighten(--accent, 8%), var(--accent));
    color: #FFFFFF;
    border-color: var(--accent);
    border-width: 0px;
    font-size: 11px;
    font-weight: 700;
  }

  TyCaptionButton {
    background: alpha(#FFFFFF, 0);
    color: #FFFFFF;
    border-radius: 0px;
  }
  TyCaptionButton:hover  { background: alpha(#FFFFFF, 0.18); }
  TyCaptionButton:active { background: alpha(#FFFFFF, 0.30); }
  TyCaptionButton.close:hover  { background: var(--danger); color: #FFFFFF; }
  TyCaptionButton.close:active { background: darken(--danger, 10%); color: #FFFFFF; }
  TyCaptionButton.min:hover    { background: alpha(#FFFFFF, 0.18); }
  TyCaptionButton.max:hover    { background: alpha(#FFFFFF, 0.18); }
  ```
- [ ] **Step 2: Verify the file exists and uses a gradient.** Run `test -s /Users/tom/Projects/TyControls/themes/showcase.tycss && grep -c 'linear-gradient' /Users/tom/Projects/TyControls/themes/showcase.tycss`. Expected: prints a count >= 1.
- [ ] **Step 3: Commit.** Run `git add themes/showcase.tycss && git commit -m "feat(tycontrols): add showcase.tycss facade theme styling all typeKeys"`.

### Task INTEGRATION.4: Runtime package tycontrols.lpk

**Files:**
- Create: `/tycontrols.lpk`

- [ ] **Step 1: Write `/tycontrols.lpk` listing every `/source` unit except `tyControls.Design`, requiring BGRABitmapPack.** Create the file with exactly this content:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <CONFIG>
    <Package Version="5">
      <Name Value="tycontrols"/>
      <Type Value="RunTime"/>
      <CompilerOptions>
        <Version Value="11"/>
        <SearchPaths>
          <OtherUnitFiles Value="source"/>
          <UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>
        </SearchPaths>
        <SyntaxOptions>
          <SyntaxMode Value="ObjFPC"/>
        </SyntaxOptions>
      </CompilerOptions>
      <Files Count="14">
        <Item1><Filename Value="source/tyControls.Types.pas"/><UnitName Value="tyControls.Types"/></Item1>
        <Item2><Filename Value="source/tyControls.Css.Tokens.pas"/><UnitName Value="tyControls.Css.Tokens"/></Item2>
        <Item3><Filename Value="source/tyControls.Css.Lexer.pas"/><UnitName Value="tyControls.Css.Lexer"/></Item3>
        <Item4><Filename Value="source/tyControls.Css.Parser.pas"/><UnitName Value="tyControls.Css.Parser"/></Item4>
        <Item5><Filename Value="source/tyControls.Css.Values.pas"/><UnitName Value="tyControls.Css.Values"/></Item5>
        <Item6><Filename Value="source/tyControls.StyleModel.pas"/><UnitName Value="tyControls.StyleModel"/></Item6>
        <Item7><Filename Value="source/tyControls.Painter.pas"/><UnitName Value="tyControls.Painter"/></Item7>
        <Item8><Filename Value="source/tyControls.Controller.pas"/><UnitName Value="tyControls.Controller"/></Item8>
        <Item9><Filename Value="source/tyControls.Base.pas"/><UnitName Value="tyControls.Base"/></Item9>
        <Item10><Filename Value="source/tyControls.Button.pas"/><UnitName Value="tyControls.Button"/></Item10>
        <Item11><Filename Value="source/tyControls.Label.pas"/><UnitName Value="tyControls.Label"/></Item11>
        <Item12><Filename Value="source/tyControls.Edit.pas"/><UnitName Value="tyControls.Edit"/></Item12>
        <Item13><Filename Value="source/tyControls.CheckBox.pas"/><UnitName Value="tyControls.CheckBox"/></Item13>
        <Item14><Filename Value="source/tyControls.Panel.pas"/><UnitName Value="tyControls.Panel"/></Item14>
      </Files>
      <RequiredPkgs Count="2">
        <Item1><PackageName Value="BGRABitmapPack"/></Item1>
        <Item2><PackageName Value="LCL"/></Item2>
      </RequiredPkgs>
    </Package>
  </CONFIG>
  ```
- [ ] **Step 2: Append the remaining runtime units to the `<Files>` list so all `/source` units except `tyControls.Design` are present.** Edit `/tycontrols.lpk`: change `<Files Count="14">` to `<Files Count="17">` and insert before `</Files>` exactly these three items:
  ```xml
        <Item15><Filename Value="source/tyControls.ComboBox.pas"/><UnitName Value="tyControls.ComboBox"/></Item15>
        <Item16><Filename Value="source/tyControls.ScrollBar.pas"/><UnitName Value="tyControls.ScrollBar"/></Item16>
        <Item17><Filename Value="source/tyControls.Form.pas"/><UnitName Value="tyControls.Form"/></Item17>
  ```
  The final list now contains each of these 17 distinct units exactly once: Types, Css.Tokens, Css.Lexer, Css.Parser, Css.Values, StyleModel, Painter, Controller, Base, Button, Label, Edit, CheckBox, Panel, ComboBox, ScrollBar, Form. Base remains Item9 only (do not add a second Base entry).
- [ ] **Step 2b: Verify the file lists exactly 17 distinct units.** Run `grep -o 'source/tyControls\.[A-Za-z.]*\.pas' /Users/tom/Projects/TyControls/tycontrols.lpk | sort -u | wc -l`. Expected: prints `17`. Run `grep -c 'tyControls.Design' /Users/tom/Projects/TyControls/tycontrols.lpk`. Expected: prints `0`.
- [ ] **Step 3: Build the runtime package.** Run `lazbuild /Users/tom/Projects/TyControls/tycontrols.lpk`. Expected: build succeeds, output ends with a line containing `Linking` or `lazbuild ... done` and exit code 0. Build success replaces TDD for this artifact.
- [ ] **Step 4: Commit.** Run `git add tycontrols.lpk && git commit -m "build(tycontrols): add runtime package tycontrols.lpk (BGRABitmap dep)"`.

### Task INTEGRATION.5: Design-time registration unit tyControls.Design.pas

**Files:**
- Create: `/source/tyControls.Design.pas`
- Test: `/tests/test.design.pas`

- [ ] **Step 1: Write the failing test `/tests/test.design.pas` that registers components and exercises the property editor class.** Create the file with exactly this content:
  ```pascal
  unit test.design;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, fpcunit, testregistry, PropEdits,
    tyControls.Design;
  type
    TTestDesign = class(TTestCase)
    published
      procedure TestPropertyEditorAttributesIncludeValueList;
      procedure TestRegisterDoesNotRaise;
    end;
  implementation

  procedure TTestDesign.TestPropertyEditorAttributesIncludeValueList;
  var
    ed: TTyStyleClassPropertyEditor;
  begin
    ed := TTyStyleClassPropertyEditor.Create(nil, 1);
    try
      AssertTrue('paValueList must be in attributes',
        paValueList in ed.GetAttributes);
    finally
      ed.Free;
    end;
  end;

  procedure TTestDesign.TestRegisterDoesNotRaise;
  begin
    try
      Register;
      AssertTrue('Register completed', True);
    except
      on E: Exception do
        Fail('Register raised: ' + E.Message);
    end;
  end;

  initialization
    RegisterTest(TTestDesign);
  end.
  ```
- [ ] **Step 2: Add `test.design` to the uses clause of `/tests/tytests.lpr`.** Edit `/tests/tytests.lpr` and add `test.design,` to the uses clause (after the last existing test unit, before the closing of the uses list).
- [ ] **Step 3: Run the test expecting FAIL (compile error: unit `tyControls.Design` does not exist yet).** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: FAIL — compilation fails because `/source/tyControls.Design.pas` is missing (cannot find unit `tyControls.Design`).
- [ ] **Step 4: Create `/source/tyControls.Design.pas` with `Register` and `TTyStyleClassPropertyEditor`.** Write the file with exactly this content:
  ```pascal
  unit tyControls.Design;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, PropEdits,
    tyControls.Controller, tyControls.StyleModel,
    tyControls.Button, tyControls.Label, tyControls.Edit,
    tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
    tyControls.ScrollBar, tyControls.Form;
  type
    TTyStyleClassPropertyEditor = class(TStringPropertyEditor)
    public
      function GetAttributes: TPropertyAttributes; override;
      procedure GetValues(Proc: TGetStrProc); override;
    end;

  procedure Register;

  implementation

  function TTyStyleClassPropertyEditor.GetAttributes: TPropertyAttributes;
  begin
    Result := (inherited GetAttributes) + [paValueList, paMultiSelect];
  end;

  procedure TTyStyleClassPropertyEditor.GetValues(Proc: TGetStrProc);
  begin
    Proc('primary');
    Proc('danger');
    Proc('close');
    Proc('min');
    Proc('max');
  end;

  procedure Register;
  begin
    RegisterComponents('TyControls',
      [TTyButton, TTyLabel, TTyEdit, TTyCheckBox, TTyRadioButton,
       TTyPanel, TTyComboBox, TTyScrollBar, TTyTitleBar,
       TTyFormChrome, TTyStyleController]);
    RegisterPropertyEditor(TypeInfo(string), TTyButton, 'StyleClass',
      TTyStyleClassPropertyEditor);
  end;

  end.
  ```
- [ ] **Step 5: Run the test expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: PASS — `TestPropertyEditorAttributesIncludeValueList` asserts `paValueList` is present, `TestRegisterDoesNotRaise` completes without exception.
- [ ] **Step 6: Commit.** Run `git add source/tyControls.Design.pas tests/test.design.pas tests/tytests.lpr && git commit -m "feat(tycontrols): add design-time Register and StyleClass property editor"`.

### Task INTEGRATION.6: Design-time package tycontrols_dt.lpk

**Files:**
- Create: `/tycontrols_dt.lpk`

- [ ] **Step 1: Write `/tycontrols_dt.lpk` (design-time, depends on tycontrols + LazIDEIntf + IDEIntf).** Create the file with exactly this content:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <CONFIG>
    <Package Version="5">
      <Name Value="tycontrols_dt"/>
      <Type Value="DesignTime"/>
      <AddToProjectUsesSection Value="False"/>
      <CompilerOptions>
        <Version Value="11"/>
        <SearchPaths>
          <OtherUnitFiles Value="source"/>
          <UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>
        </SearchPaths>
        <SyntaxOptions>
          <SyntaxMode Value="ObjFPC"/>
        </SyntaxOptions>
      </CompilerOptions>
      <Files Count="1">
        <Item1>
          <Filename Value="source/tyControls.Design.pas"/>
          <HasRegisterProc Value="True"/>
          <UnitName Value="tyControls.Design"/>
        </Item1>
      </Files>
      <RequiredPkgs Count="3">
        <Item1><PackageName Value="tycontrols"/></Item1>
        <Item2><PackageName Value="LazIDEIntf"/></Item2>
        <Item3><PackageName Value="IDEIntf"/></Item3>
      </RequiredPkgs>
    </Package>
  </CONFIG>
  ```
- [ ] **Step 2: Verify the package declares DesignTime type, HasRegisterProc, and the three required deps.** Run `grep -c '<Type Value="DesignTime"/>' /Users/tom/Projects/TyControls/tycontrols_dt.lpk` (expect `1`), `grep -c 'HasRegisterProc Value="True"' /Users/tom/Projects/TyControls/tycontrols_dt.lpk` (expect `1`), and `grep -E -c 'tycontrols|LazIDEIntf|IDEIntf' /Users/tom/Projects/TyControls/tycontrols_dt.lpk` (expect a count >= 3).
- [ ] **Step 3: Build the design-time package.** Run `lazbuild /Users/tom/Projects/TyControls/tycontrols_dt.lpk`. Expected: build succeeds with exit code 0 (it resolves `tyControls.Design`, the runtime package, and the IDE interface packages). Build success replaces TDD for this artifact.
- [ ] **Step 4: Commit.** Run `git add tycontrols_dt.lpk && git commit -m "build(tycontrols): add design-time package tycontrols_dt.lpk (LazIDEIntf/IDEIntf deps)"`.

### Task INTEGRATION.7: Demo main form unit

**Files:**
- Create: `/examples/demo/mainform.pas`
- Create: `/examples/demo/mainform.lfm`

- [ ] **Step 1: Write `/examples/demo/mainform.lfm` with one of every control, a controller, and theme-switch buttons.** Create the file with exactly this content:
  ```
  object DemoMainForm: TDemoMainForm
    Left = 200
    Top = 120
    Width = 640
    Height = 480
    Caption = 'TyControls Demo'
    object Controller: TTyStyleController
      Left = 16
      Top = 16
    end
    object Chrome: TTyFormChrome
      Active = False
      TitleHeight = 32
      ShowMinimize = True
      ShowMaximize = True
      Left = 64
      Top = 16
    end
    object BtnLight: TTyButton
      Left = 16
      Top = 16
      Width = 90
      Height = 30
      Caption = 'Light'
      OnClick = BtnLightClick
    end
    object BtnDark: TTyButton
      Left = 114
      Top = 16
      Width = 90
      Height = 30
      Caption = 'Dark'
      OnClick = BtnDarkClick
    end
    object BtnShowcase: TTyButton
      Left = 212
      Top = 16
      Width = 110
      Height = 30
      Caption = 'Showcase'
      OnClick = BtnShowcaseClick
    end
    object BtnPrimary: TTyButton
      Left = 16
      Top = 60
      Width = 110
      Height = 30
      Caption = 'Primary'
      StyleClass = 'primary'
    end
    object BtnDanger: TTyButton
      Left = 134
      Top = 60
      Width = 110
      Height = 30
      Caption = 'Danger'
      StyleClass = 'danger'
    end
    object LblHello: TTyLabel
      Left = 16
      Top = 104
      Width = 120
      Height = 20
      Caption = 'Hello TyControls'
    end
    object EditName: TTyEdit
      Left = 16
      Top = 132
      Width = 200
      Height = 26
    end
    object ChkAgree: TTyCheckBox
      Left = 16
      Top = 168
      Width = 120
      Height = 22
      Caption = 'Agree'
    end
    object RadOne: TTyRadioButton
      Left = 16
      Top = 196
      Width = 120
      Height = 22
      Caption = 'Option One'
    end
    object PanelBox: TTyPanel
      Left = 240
      Top = 60
      Width = 200
      Height = 160
    end
    object ComboKind: TTyComboBox
      Left = 16
      Top = 228
      Width = 200
      Height = 26
    end
    object ScrollV: TTyScrollBar
      Left = 460
      Top = 60
      Width = 18
      Height = 160
    end
  end
  ```
- [ ] **Step 2: Write `/examples/demo/mainform.pas` implementing the theme-switch handlers (hot-reload proof).** Create the file with exactly this content:
  ```pascal
  unit mainform;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Forms, Controls,
    tyControls.Controller, tyControls.Button, tyControls.Label,
    tyControls.Edit, tyControls.CheckBox, tyControls.Panel,
    tyControls.ComboBox, tyControls.ScrollBar, tyControls.Form;
  type
    TDemoMainForm = class(TForm)
      Controller: TTyStyleController;
      Chrome: TTyFormChrome;
      BtnLight: TTyButton;
      BtnDark: TTyButton;
      BtnShowcase: TTyButton;
      BtnPrimary: TTyButton;
      BtnDanger: TTyButton;
      LblHello: TTyLabel;
      EditName: TTyEdit;
      ChkAgree: TTyCheckBox;
      RadOne: TTyRadioButton;
      PanelBox: TTyPanel;
      ComboKind: TTyComboBox;
      ScrollV: TTyScrollBar;
      procedure FormCreate(Sender: TObject);
      procedure BtnLightClick(Sender: TObject);
      procedure BtnDarkClick(Sender: TObject);
      procedure BtnShowcaseClick(Sender: TObject);
    private
      function ThemeDir: string;
      procedure ApplyTheme(const AFile: string);
    end;
  var
    DemoMainForm: TDemoMainForm;
  implementation
  {$R *.lfm}

  function TDemoMainForm.ThemeDir: string;
  begin
    Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' +
      PathDelim + 'themes' + PathDelim;
  end;

  procedure TDemoMainForm.ApplyTheme(const AFile: string);
  begin
    Controller.LoadTheme(ThemeDir + AFile);
    Controller.Changed;
  end;

  procedure TDemoMainForm.FormCreate(Sender: TObject);
  begin
    ApplyTheme('light.tycss');
  end;

  procedure TDemoMainForm.BtnLightClick(Sender: TObject);
  begin
    ApplyTheme('light.tycss');
  end;

  procedure TDemoMainForm.BtnDarkClick(Sender: TObject);
  begin
    ApplyTheme('dark.tycss');
  end;

  procedure TDemoMainForm.BtnShowcaseClick(Sender: TObject);
  begin
    ApplyTheme('showcase.tycss');
  end;

  end.
  ```
- [ ] **Step 3: Add the `OnCreate` handler wiring to the .lfm so `FormCreate` runs.** Edit `/examples/demo/mainform.lfm`: add the line `  OnCreate = FormCreate` immediately after the `Caption = 'TyControls Demo'` line.
- [ ] **Step 4: Verify both files exist and the form declares every Tier-1 control plus chrome.** Run `grep -E -c 'TTyButton|TTyLabel|TTyEdit|TTyCheckBox|TTyRadioButton|TTyPanel|TTyComboBox|TTyScrollBar|TTyFormChrome|TTyStyleController' /Users/tom/Projects/TyControls/examples/demo/mainform.pas`. Expected: a count >= 10 (one declaration per control type plus controller and chrome). Final compile happens in Task INTEGRATION.8.
- [ ] **Step 5: Commit.** Run `git add examples/demo/mainform.pas examples/demo/mainform.lfm && git commit -m "feat(tycontrols): add demo main form with every control and theme switching"`.

### Task INTEGRATION.8: Demo project files and build

**Files:**
- Create: `/examples/demo/demo.lpr`
- Create: `/examples/demo/demo.lpi`

- [ ] **Step 1: Write `/examples/demo/demo.lpr` (program entry that builds the main form).** Create the file with exactly this content:
  ```pascal
  program demo;
  {$mode objfpc}{$H+}
  uses
    {$IFDEF UNIX}cthreads,{$ENDIF}
    Interfaces, Forms,
    mainform;
  {$R *.res}
  begin
    RequireDerivedFormResource := True;
    Application.Scaled := True;
    Application.Initialize;
    Application.CreateForm(TDemoMainForm, DemoMainForm);
    Application.Run;
  end.
  ```
- [ ] **Step 2: Write `/examples/demo/demo.lpi` (project requiring the runtime package).** Create the file with exactly this content:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <CONFIG>
    <ProjectOptions>
      <Version Value="12"/>
      <General>
        <Flags>
          <MainUnitHasCreateFormStatements Value="True"/>
          <MainUnitHasTitleStatement Value="False"/>
        </Flags>
        <Title Value="TyControls Demo"/>
      </General>
      <BuildModes Count="1">
        <Item1 Name="Default" Default="True"/>
      </BuildModes>
      <RequiredPackages Count="2">
        <Item1><PackageName Value="LCL"/></Item1>
        <Item2><PackageName Value="tycontrols"/></Item2>
      </RequiredPackages>
      <Units Count="2">
        <Unit0>
          <Filename Value="demo.lpr"/>
          <IsPartOfProject Value="True"/>
        </Unit0>
        <Unit1>
          <Filename Value="mainform.pas"/>
          <IsPartOfProject Value="True"/>
          <ComponentName Value="DemoMainForm"/>
          <ResourceBaseClass Value="Form"/>
          <UnitName Value="mainform"/>
        </Unit1>
      </Units>
    </ProjectOptions>
    <CompilerOptions>
      <Version Value="11"/>
      <SearchPaths>
        <OtherUnitFiles Value="."/>
        <UnitOutputDirectory Value="lib/$(TargetCPU)-$(TargetOS)"/>
      </SearchPaths>
      <SyntaxOptions>
        <SyntaxMode Value="ObjFPC"/>
      </SyntaxOptions>
    </CompilerOptions>
  </CONFIG>
  ```
- [ ] **Step 3: Build the demo project.** Run `lazbuild /Users/tom/Projects/TyControls/examples/demo/demo.lpi`. Expected: build succeeds with exit code 0; it links `mainform` against the runtime package and produces the `demo` executable. Build success replaces TDD for this artifact.
- [ ] **Step 4: Commit.** Run `git add examples/demo/demo.lpr examples/demo/demo.lpi && git commit -m "build(tycontrols): add demo project (demo.lpr/.lpi) building against runtime package"`.

### Task INTEGRATION.9: TTyFormChrome demo form

**Files:**
- Create: `/examples/demo/chromeform.pas`
- Create: `/examples/demo/chromeform.lfm`
- Modify: `/examples/demo/demo.lpr`
- Modify: `/examples/demo/demo.lpi`

- [ ] **Step 1: Write `/examples/demo/chromeform.lfm` with an active chrome titlebar.** Create the file with exactly this content:
  ```
  object ChromeForm: TChromeForm
    Left = 280
    Top = 180
    Width = 520
    Height = 360
    Caption = 'Custom Chrome Window'
    BorderStyle = bsSizeable
    object Chrome: TTyFormChrome
      Active = True
      TitleHeight = 34
      ShowMinimize = True
      ShowMaximize = True
      Left = 16
      Top = 48
    end
    object Controller: TTyStyleController
      Left = 64
      Top = 48
    end
    object LblInfo: TTyLabel
      Left = 24
      Top = 80
      Width = 360
      Height = 20
      Caption = 'Drag the title bar; resize from edges; double-click to maximize.'
    end
  end
  ```
- [ ] **Step 2: Write `/examples/demo/chromeform.pas` that loads a theme and activates chrome at runtime.** Create the file with exactly this content:
  ```pascal
  unit chromeform;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, Forms,
    tyControls.Controller, tyControls.Label, tyControls.Form;
  type
    TChromeForm = class(TForm)
      Chrome: TTyFormChrome;
      Controller: TTyStyleController;
      LblInfo: TTyLabel;
      procedure FormCreate(Sender: TObject);
    private
      function ThemeDir: string;
    end;
  var
    ChromeForm: TChromeForm;
  implementation
  {$R *.lfm}

  function TChromeForm.ThemeDir: string;
  begin
    Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' +
      PathDelim + 'themes' + PathDelim;
  end;

  procedure TChromeForm.FormCreate(Sender: TObject);
  begin
    Controller.LoadTheme(ThemeDir + 'showcase.tycss');
    Chrome.TitleBar.Caption := 'Custom Chrome Window';
    Controller.Changed;
  end;

  end.
  ```
- [ ] **Step 3: Add the `OnCreate` handler to the chrome form .lfm.** Edit `/examples/demo/chromeform.lfm`: add the line `  OnCreate = FormCreate` immediately after the `BorderStyle = bsSizeable` line.
- [ ] **Step 4: Wire the chrome form into the program.** Edit `/examples/demo/demo.lpr`: change the uses line `    mainform;` to `    mainform, chromeform;` and add `  Application.CreateForm(TChromeForm, ChromeForm);` immediately after the existing `Application.CreateForm(TDemoMainForm, DemoMainForm);` line.
- [ ] **Step 5: Register the chrome unit in the project file.** Edit `/examples/demo/demo.lpi`: change `<Units Count="2">` to `<Units Count="3">` and insert before `</Units>`:
  ```xml
        <Unit2>
          <Filename Value="chromeform.pas"/>
          <IsPartOfProject Value="True"/>
          <ComponentName Value="ChromeForm"/>
          <ResourceBaseClass Value="Form"/>
          <UnitName Value="chromeform"/>
        </Unit2>
  ```
- [ ] **Step 6: Rebuild the demo with the chrome form.** Run `lazbuild /Users/tom/Projects/TyControls/examples/demo/demo.lpi`. Expected: build succeeds with exit code 0; both forms compile and the `demo` executable is produced. Build success replaces TDD for this artifact.
- [ ] **Step 7: Commit.** Run `git add examples/demo/chromeform.pas examples/demo/chromeform.lfm examples/demo/demo.lpr examples/demo/demo.lpi && git commit -m "feat(tycontrols): add TTyFormChrome demo form to demo project"`.

### Task INTEGRATION.10: Shipped-theme load test

**Files:**
- Create: `/tests/test.themes.pas`
- Modify: `/tests/tytests.lpr`

- [ ] **Step 1: Write the failing test `/tests/test.themes.pas` that loads each shipped theme and resolves a TyButton style.** Create the file with exactly this content:
  ```pascal
  unit test.themes;
  {$mode objfpc}{$H+}
  interface
  uses
    Classes, SysUtils, fpcunit, testregistry,
    tyControls.Types, tyControls.StyleModel;
  type
    TTestThemes = class(TTestCase)
    private
      function ThemePath(const AName: string): string;
      procedure CheckTheme(const AName: string);
    published
      procedure TestLightLoadsAndResolvesButton;
      procedure TestDarkLoadsAndResolvesButton;
      procedure TestShowcaseLoadsAndResolvesButton;
    end;
  implementation

  function TTestThemes.ThemePath(const AName: string): string;
  begin
    // Resolve relative to the test executable (in /tests) so the path does not
    // depend on the current working directory.
    Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
      + 'themes' + PathDelim + AName;
  end;

  procedure TTestThemes.CheckTheme(const AName: string);
  var
    model: TTyStyleModel;
    base, prim: TTyStyleSet;
  begin
    model := TTyStyleModel.Create;
    try
      AssertTrue('theme file must exist: ' + AName,
        FileExists(ThemePath(AName)));
      model.LoadFromFile(ThemePath(AName));
      base := model.ResolveStyle('TyButton', '', []);
      AssertTrue('TyButton base must set Background: ' + AName,
        tpBackground in base.Present);
      AssertTrue('TyButton base must set TextColor: ' + AName,
        tpTextColor in base.Present);
      prim := model.ResolveStyle('TyButton', 'primary', [tysHover]);
      AssertTrue('TyButton.primary:hover must set Background: ' + AName,
        tpBackground in prim.Present);
    finally
      model.Free;
    end;
  end;

  procedure TTestThemes.TestLightLoadsAndResolvesButton;
  begin
    CheckTheme('light.tycss');
  end;

  procedure TTestThemes.TestDarkLoadsAndResolvesButton;
  begin
    CheckTheme('dark.tycss');
  end;

  procedure TTestThemes.TestShowcaseLoadsAndResolvesButton;
  begin
    CheckTheme('showcase.tycss');
  end;

  initialization
    RegisterTest(TTestThemes);
  end.
  ```
- [ ] **Step 2: Add `test.themes` to the uses clause of `/tests/tytests.lpr`.** Edit `/tests/tytests.lpr` and add `test.themes,` to the uses clause (after `test.design,`, before the closing of the uses list).
- [ ] **Step 3: Run the test expecting FAIL.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: FAIL if a shipped theme contains a function/var the parser cannot evaluate, in which case `LoadFromFile` raises `ETyCssError` and the test errors. The theme path is resolved from the executable via `ExtractFilePath(ParamStr(0))`, so it does not depend on the current working directory. (If all three themes are valid and reachable, this step instead confirms PASS and you proceed; the FAIL→PASS gate here protects against an unparseable theme.)
- [ ] **Step 4: Re-run expecting PASS.** Run `lazbuild tests/tytests.lpr && ./tests/tytests -a --format=plain`. Expected: PASS — `ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes'` resolves the three shipped files regardless of the working directory, each loads without `ETyCssError`, and `ResolveStyle('TyButton', ...)` reports `tpBackground` and `tpTextColor` present for base and `tpBackground` for `primary:hover`.
- [ ] **Step 5: Commit.** Run `git add tests/test.themes.pas tests/tytests.lpr && git commit -m "test(tycontrols): load each shipped theme and assert TyButton resolves"`.

### Task INTEGRATION.11: Cross-platform build matrix

**Files:**
- Create: `/scripts/build-matrix.sh`

- [ ] **Step 1: Write `/scripts/build-matrix.sh` documenting and driving Win/Linux/macOS builds via lazbuild.** Create the file with exactly this content:
  ```bash
  #!/usr/bin/env bash
  # TyControls cross-platform build matrix.
  # Run on each target host (Windows/Linux/macOS); lazbuild selects the
  # host widgetset by default. Override with TY_WS to force a widgetset.
  set -euo pipefail

  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  WS="${TY_WS:-}"
  WS_ARG=""
  if [ -n "$WS" ]; then
    WS_ARG="--ws=$WS"
  fi

  echo "== TyControls build matrix =="
  echo "Root: $ROOT"
  echo "Widgetset override: ${WS:-<host default>}"

  echo "-- runtime package --"
  lazbuild $WS_ARG "$ROOT/tycontrols.lpk"

  echo "-- design-time package --"
  lazbuild $WS_ARG "$ROOT/tycontrols_dt.lpk"

  echo "-- demo project --"
  lazbuild $WS_ARG "$ROOT/examples/demo/demo.lpi"

  echo "-- test runner --"
  lazbuild $WS_ARG "$ROOT/tests/tytests.lpr"

  echo "== matrix OK =="
  ```
- [ ] **Step 2: Make the script executable.** Run `chmod +x /Users/tom/Projects/TyControls/scripts/build-matrix.sh`.
- [ ] **Step 3: Run the build matrix on this host (macOS) to verify all four artifacts build green.** Run `/Users/tom/Projects/TyControls/scripts/build-matrix.sh`. Expected: prints `== matrix OK ==` and exits 0; the runtime package, design package, demo, and test runner all build. On Windows run the same script under Git Bash / WSL with `TY_WS=win32`; on Linux with `TY_WS=gtk2` or `qt5`; on macOS with `TY_WS=cocoa`.
- [ ] **Step 4: Commit.** Run `git add scripts/build-matrix.sh && git commit -m "build(tycontrols): add cross-platform lazbuild matrix script"`.

### Task INTEGRATION.12: Known-gaps documentation note

**Files:**
- Create: `/docs/KNOWN_GAPS.md`

- [ ] **Step 1: Write `/docs/KNOWN_GAPS.md` recording the contract's Tier-2 form-chrome gaps and design-time WYSIWYG caveat.** Create the file with exactly this content:
  ```markdown
  # TyControls — Known Gaps (v1)

  These behaviors are intentionally NOT implemented in v1. They are tracked
  for a future Tier-2 native enhancement layer.

  ## Form chrome (TTyFormChrome) native window behavior
  - Windows Aero Snap (edge tiling) is not supported.
  - Borderless-window native drop shadow is not provided.
  - macOS traffic-light (red/yellow/green) caption buttons are not emulated;
    TyControls draws its own close/min/max glyphs instead.
  - Cross-monitor DPI switching is not handled.

  ## Design-time rendering
  - The Lazarus form designer shows the native (non-skinned) frame; full
    self-drawn window chrome appears only at runtime. This is the standard
    behavior for skin-window libraries and is expected.
  ```
- [ ] **Step 2: Verify the note records all four chrome gaps.** Run `grep -E -c 'Aero Snap|drop shadow|traffic-light|DPI' /Users/tom/Projects/TyControls/docs/KNOWN_GAPS.md`. Expected: a count >= 4.
- [ ] **Step 3: Commit.** Run `git add docs/KNOWN_GAPS.md && git commit -m "docs(tycontrols): record v1 form-chrome known gaps"`.
