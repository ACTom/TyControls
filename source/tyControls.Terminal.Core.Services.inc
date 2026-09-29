{ Part of tyControls.Terminal.Core (included, not a unit): the services around the
  input handler -- CoreService, CharsetService, MouseStateService with the mouse
  trigger, colours and focus, the dirty-row tracker, the old-ConPTY heuristics, the
  options and the size / reset / scroll / input entry points. Moved out of the unit
  only to keep it readable; the port, its sources and its licence are in the unit
  header. }

{ ---- CoreService (CoreService.ts) --------------------------------------------------------- }

procedure TTyTerminalCore.CoreServiceReset;                                  { :68-72 }
begin
  { modes and kitty state; isCursorHidden and isCursorInitialized stay }
  FInsertMode := False;
  FApplicationCursorKeys := False;
  FApplicationKeypad := False;
  FBracketedPasteMode := False;
  FColorSchemeUpdates := False;
  FCursorBlinkRequest := tbrDefault;
  FCursorStyleRequest := tcrDefault;
  FOrigin := False;
  FReverseWraparound := False;
  FSendFocus := False;
  FSynchronizedOutput := False;
  FWin32InputMode := False;
  FWraparound := True;
  FKittyFlags := 0;
  FKittyMainFlags := 0;
  FKittyAltFlags := 0;
  FKittyMainStack := nil;
  FKittyAltStack := nil;
end;

procedure TTyTerminalCore.TriggerDataEvent(const AData: RawByteString; AWasUserInput: Boolean);
var
  buf: TTyTerminalBuffer;
begin                                                                        { :74-95 }
  if FOptions.DisableStdin then
    Exit;
  buf := Buffer;
  if AWasUserInput and FOptions.ScrollOnUserInput and (buf.YBase <> buf.YDisp) then
  begin
    if Assigned(FOnRequestScrollToBottom) then
      FOnRequestScrollToBottom(Self);
    ScrollToBottom;                      { CoreTerminal.ts:150 }
  end;
  if AWasUserInput and Assigned(FOnUserInput) then
    FOnUserInput(Self);                  { :86-89, before onData }
  if AWasUserInput then
    FDidUserInput := True;               { CoreTerminal.ts:151 -> WriteBuffer.handleUserInput }
  if Assigned(FOnData) then
    FOnData(Self, AData);
end;

{ triggerBinaryEvent, CoreService.ts:97-104: the default mouse encoding's bytes, no
  scroll to the bottom, no user input }
procedure TTyTerminalCore.TriggerBinaryEvent(const AData: RawByteString);
begin
  if FOptions.DisableStdin then
    Exit;
  if Assigned(FOnData) then
    FOnData(Self, AData);
end;

function TTyTerminalCore.GetModes: TTyTerminalModes;
begin
  Result.ApplicationCursorKeys := FApplicationCursorKeys;
  Result.ApplicationKeypad := FApplicationKeypad;
  Result.BracketedPaste := FBracketedPasteMode;
  Result.Insert := FInsertMode;
  Result.Origin := FOrigin;
  Result.ReverseWraparound := FReverseWraparound;
  Result.SendFocus := FSendFocus;
  Result.ShowCursor := not FIsCursorHidden;
  Result.SynchronizedOutput := FSynchronizedOutput;
  Result.Win32Input := FWin32InputMode;
  Result.Wraparound := FWraparound;
  Result.ColorSchemeUpdates := FColorSchemeUpdates;
  Result.MouseProtocol := FMouseProtocol;
  Result.MouseEncoding := FMouseEncoding;
  Result.CursorRequest := FCursorStyleRequest;
  Result.BlinkRequest := FCursorBlinkRequest;
end;

function SameModes(const A, B: TTyTerminalModes): Boolean;
begin
  Result := (A.ApplicationCursorKeys = B.ApplicationCursorKeys) and (A.ApplicationKeypad = B.ApplicationKeypad)
    and (A.BracketedPaste = B.BracketedPaste) and (A.Insert = B.Insert) and (A.Origin = B.Origin)
    and (A.ReverseWraparound = B.ReverseWraparound) and (A.SendFocus = B.SendFocus)
    and (A.ShowCursor = B.ShowCursor) and (A.SynchronizedOutput = B.SynchronizedOutput)
    and (A.Win32Input = B.Win32Input) and (A.Wraparound = B.Wraparound)
    and (A.ColorSchemeUpdates = B.ColorSchemeUpdates) and (A.MouseProtocol = B.MouseProtocol)
    and (A.MouseEncoding = B.MouseEncoding) and (A.CursorRequest = B.CursorRequest)
    and (A.BlinkRequest = B.BlinkRequest);
end;

{ OnModesChange: once per sequence that changed a mode (upstream has no such event) }
procedure TTyTerminalCore.ModesChangedSince(const ABefore: TTyTerminalModes);
begin
  if Assigned(FOnModesChange) and not SameModes(ABefore, GetModes) then
    FOnModesChange(Self);
end;

{ ---- CharsetService ------------------------------------------------------------------------ }

procedure TTyTerminalCore.CharsetReset;
begin
  FCharset := 0;
  FCharsets := nil;
  FGLevel := 0;
end;

procedure TTyTerminalCore.SetGLevel(AG: Integer);
begin
  FGLevel := AG;
  FCharset := CharsetOfG(AG);
end;

procedure TTyTerminalCore.SetGCharset(AG: Integer; ACharset: TTyTermCharsetId);
var
  i, old: Integer;
begin
  if AG < 0 then
    Exit;
  if AG > High(FCharsets) then
  begin
    old := Length(FCharsets);
    SetLength(FCharsets, AG + 1);
    for i := old to AG do
      FCharsets[i] := 0;                 { holes: undefined }
  end;
  FCharsets[AG] := ACharset;
  if FGLevel = AG then
    FCharset := ACharset;
end;

function TTyTerminalCore.CharsetOfG(AG: Integer): TTyTermCharsetId;
begin
  if (AG >= 0) and (AG <= High(FCharsets)) then
    Result := FCharsets[AG]
  else
    Result := 0;
end;

function TTyTerminalCore.CharsetKey(AId: TTyTermCharsetId): string;
var
  k: Integer;
begin
  Result := '';
  if AId = 0 then
    Exit;
  for k := 0 to TyTermCharsetKeyCount - 1 do
    if TyTermCharsetOfKey[k] = AId then
      Exit(TyTermCharsetKeys[k]);
end;

{ ---- MouseStateService (MouseStateService.ts) ---------------------------------------------- }

procedure TTyTerminalCore.SetMouseProtocol(AValue: TTyTerminalMouseProtocol);
begin
  FMouseProtocol := AValue;
end;

{ the five restrict functions, :13-83 }
function TTyTerminalCore.RestrictMouseEvent(var AEvent: TTyTerminalMouseEvent): Boolean;
begin
  case FMouseProtocol of
    tmpNone: Result := False;
    tmpX10:
      begin
        { no wheel, no move, no up, no modifiers }
        if (AEvent.Button = tmbWheel) or (AEvent.Action <> tmaDown) then
          Exit(False);
        AEvent.Ctrl := False;
        AEvent.Alt := False;
        AEvent.Shift := False;
        Result := True;
      end;
    tmpVT200: Result := AEvent.Action <> tmaMove;
    tmpDrag: Result := not ((AEvent.Action = tmaMove) and (AEvent.Button = tmbNone));
  else
    Result := True;
  end;
end;

{ eventCode, :92-113 }
function MouseEventCode(const E: TTyTerminalMouseEvent; AIsSgr: Boolean): Integer;
var
  button: Integer;
begin
  Result := 0;
  if E.Ctrl then Result := Result or 16;
  if E.Shift then Result := Result or 4;
  if E.Alt then Result := Result or 8;
  button := Ord(E.Button);
  if E.Button = tmbWheel then
  begin
    Result := Result or 64;
    Result := Result or TyTermMouseActionCode(E.Action);
  end
  else
  begin
    Result := Result or (button and 3);
    if button and 4 <> 0 then Result := Result or 64;
    if button and 8 <> 0 then Result := Result or 128;
    if E.Action = tmaMove then
      Result := Result or 32
    else if (E.Action = tmaUp) and not AIsSgr then
      Result := Result or Ord(tmbNone);  { only SGR reports the released button }
  end;
end;

{ the three encodings, :121-151; the default one is bytes (spec 3.3) }
function TTyTerminalCore.EncodeMouseEvent(const AEvent: TTyTerminalMouseEvent): RawByteString;
var
  p0, p1, p2: Integer;
  fin: Char;
begin
  case FMouseEncoding of
    tmeDefault:
      begin
        p0 := MouseEventCode(AEvent, False) + 32;
        p1 := AEvent.Col + 32;
        p2 := AEvent.Row + 32;
        { past the addressable range: no report (as vte and konsole) }
        if (p0 > 255) or (p1 > 255) or (p2 > 255) then
          Exit('');
        Result := #27'[M' + Chr(p0) + Chr(p1) + Chr(p2);
      end;
  else
    if (AEvent.Action = tmaUp) and (AEvent.Button <> tmbWheel) then fin := 'm' else fin := 'M';
    if FMouseEncoding = tmeSgr then
      Result := Format(#27'[<%d;%d;%d%s', [MouseEventCode(AEvent, True), AEvent.Col, AEvent.Row, fin])
    else
      Result := Format(#27'[<%d;%d;%d%s', [MouseEventCode(AEvent, True), AEvent.X, AEvent.Y, fin]);
  end;
end;

{ _equalEvents, MouseService.ts:557-570 }
function SameMouseEvent(const A, B: TTyTerminalMouseEvent; APixels: Boolean): Boolean;
begin
  if APixels then
    Result := (A.X = B.X) and (A.Y = B.Y)
  else
    Result := (A.Col = B.Col) and (A.Row = B.Row);
  Result := Result and (A.Button = B.Button) and (A.Action = B.Action) and (A.Ctrl = B.Ctrl)
    and (A.Alt = B.Alt) and (A.Shift = B.Shift);
end;

{ _triggerMouseEvent, MouseService.ts:497-545 }
function TTyTerminalCore.TriggerMouseEvent(const AEvent: TTyTerminalMouseEvent): Boolean;
var
  e: TTyTerminalMouseEvent;
  report: RawByteString;
begin
  CheckThread('TriggerMouseEvent');
  e := AEvent;
  if (e.Col < 0) or (e.Col >= Cols) or (e.Row < 0) or (e.Row >= Rows) then
    Exit(False);
  { nonsense combinations of button and action }
  if (e.Button = tmbWheel) and (e.Action = tmaMove) then
    Exit(False);
  if (e.Button = tmbNone) and (e.Action <> tmaMove) then
    Exit(False);
  if (e.Button <> tmbWheel) and (e.Action in [tmaLeft, tmaRight]) then
    Exit(False);
  { reports are 1-based }
  Inc(e.Col);
  Inc(e.Row);
  { a move only when it lands on another cell (another pixel under SGR-pixels) }
  if (e.Action = tmaMove) and FHasLastMouse and SameMouseEvent(FLastMouse, e, FMouseEncoding = tmeSgrPixels) then
    Exit(False);
  if not RestrictMouseEvent(e) then
    Exit(False);
  report := EncodeMouseEvent(e);
  if report <> '' then
  begin
    if FMouseEncoding = tmeDefault then
      TriggerBinaryEvent(report)
    else
      TriggerDataEvent(report, True);
  end;
  FLastMouse := e;
  FHasLastMouse := True;
  Result := True;
end;

{ ---- colours and focus ----------------------------------------------------------------------- }

function TTyTerminalCore.ResolveColor(AIndex: Integer): Cardinal;
begin
  Result := 0;
  if (AIndex < 0) or (AIndex > 258) then
    Exit;
  if FOverrides[AIndex].IsSet then
    Exit(FOverrides[AIndex].Rgb);
  if Assigned(FOnQueryBaseColor) then
    FOnQueryBaseColor(Self, AIndex, Result);
end;

function TTyTerminalCore.HasColorOverride(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= 258) and FOverrides[AIndex].IsSet;
end;

{ CoreBrowserTerminal.ts:238-240. Without OnQueryBaseColor there is no theme to
  answer from: no reply, as headless xterm.js (unit header). }
procedure TTyTerminalCore.ReportColor(AIndex: Integer);
var
  ident: string;
begin
  if not Assigned(FOnQueryBaseColor) then
    Exit;
  case AIndex of
    ColorFg: ident := '10';
    ColorBg: ident := '11';
    ColorCursor: ident := '12';
  else
    ident := '4;' + IntToStr(AIndex);
  end;
  TriggerDataEvent(#27']' + ident + ';' + TyTermToRgbString(ResolveColor(AIndex)) + #27'\');
end;

procedure TTyTerminalCore.SetColor(AIndex: Integer; ARgb: Cardinal);
begin
  FOverrides[AIndex].IsSet := True;
  FOverrides[AIndex].Rgb := ARgb and $FFFFFF;
  ColorsChanged;                         { modifyColors fires onChangeColors }
end;

procedure TTyTerminalCore.RestoreColor(AIndex: Integer);
var
  i: Integer;
begin
  { no index restores the 256 palette entries only (ThemeService.ts:156-161) }
  if AIndex < 0 then
    for i := 0 to 255 do
      FOverrides[i].IsSet := False
  else
    FOverrides[AIndex].IsSet := False;
  ColorsChanged;                         { restoreColor fires onChangeColors }
end;

{ CoreBrowserTerminal.ts:526-531: every colour change reports when 2031 is on }
procedure TTyTerminalCore.ColorsChanged;
begin
  if FColorSchemeUpdates then
    ReportColorScheme;
end;

{ CoreBrowserTerminal.ts:261-268; silent without OnQueryBaseColor, as ReportColor }
procedure TTyTerminalCore.ReportColorScheme;
var
  mode: Integer;
begin
  if not Assigned(FOnQueryBaseColor) then
    Exit;
  if TyTermRelativeLuminance(ResolveColor(ColorBg)) < TyTermRelativeLuminance(ResolveColor(ColorFg)) then
    mode := 1
  else
    mode := 2;
  TriggerDataEvent(#27'[?997;' + IntToStr(mode) + 'n');
end;

procedure TTyTerminalCore.NotifyColorSchemeChanged;
var
  i: Integer;
begin
  CheckThread('NotifyColorSchemeChanged');
  { a new theme rebuilds the whole colour set upstream: the overrides go }
  for i := 0 to High(FOverrides) do
    FOverrides[i].IsSet := False;
  ColorsChanged;
end;

{ CoreBrowserTerminal.ts:1124-1130, sent when DECSET 1004 is turned on }
procedure TTyTerminalCore.ReportFocusNow;
begin
  if FFocused then
    TriggerDataEvent(#27'[I')
  else
    TriggerDataEvent(#27'[O');
end;

{ CoreBrowserTerminal.ts:305-331 }
procedure TTyTerminalCore.ReportFocus(AFocused: Boolean);
begin
  CheckThread('ReportFocus');
  FFocused := AFocused;
  if FSendFocus then
    ReportFocusNow;
end;

{ SynchronizedOutputHandler's timeout, RenderService.ts:359-363 }
procedure TTyTerminalCore.EndSynchronizedOutput;
var
  before: TTyTerminalModes;
begin
  CheckThread('EndSynchronizedOutput');
  if not FSynchronizedOutput then
    Exit;
  before := GetModes;
  FSynchronizedOutput := False;
  RefreshAll;                            { _onTimeout: _fullRefresh }
  ModesChangedSince(before);
end;

{ ---- DirtyRowTracker ---------------------------------------------------------------------------- }

procedure TTyTerminalCore.ClearRange;
begin
  FDirtyStart := Buffer.Y;
  FDirtyEnd := Buffer.Y;
end;

procedure TTyTerminalCore.MarkDirty(AY: Integer);
begin
  if AY < FDirtyStart then
    FDirtyStart := AY
  else if AY > FDirtyEnd then
    FDirtyEnd := AY;
end;

procedure TTyTerminalCore.MarkRangeDirty(AY1, AY2: Integer);
var
  t: Integer;
begin
  if AY1 > AY2 then
  begin
    t := AY1;
    AY1 := AY2;
    AY2 := t;
  end;
  if AY1 < FDirtyStart then
    FDirtyStart := AY1;
  if AY2 > FDirtyEnd then
    FDirtyEnd := AY2;
end;

procedure TTyTerminalCore.MarkAllDirty;
begin
  MarkRangeDirty(0, Rows - 1);
end;

{ onRequestRefreshRows(undefined): headless maps it to the whole screen }
procedure TTyTerminalCore.RefreshAll;
begin
  if Assigned(FOnRefreshRows) then
    FOnRefreshRows(Self, 0, Rows - 1);
end;

{ ---- the old-ConPTY heuristics ------------------------------------------------------------------- }

procedure TTyTerminalCore.HandleWindowsPtyOptionChange;                      { CoreTerminal.ts:279-289 }
var
  value: Boolean;
begin
  value := (FOptions.WindowsPty.Backend <> twpNone) and (FOptions.WindowsPty.BuildNumber <> 0)
    and (FOptions.WindowsPty.Backend = twpConPty) and (FOptions.WindowsPty.BuildNumber < 21376);
  if value then
  begin
    if not FWindowsHeuristics then
    begin
      FWindowsHeuristics := True;
      { a CSI H handler that runs before cursorPosition and lets it through }
      FWindowsCsiHandle := FParser.RegisterCsiHandler(Id('', '', 'H'), @WindowsHeuristicCsiH);
    end;
  end
  else if FWindowsHeuristics then
  begin
    FWindowsHeuristics := False;
    FParser.Unregister(FWindowsCsiHandle);
    FWindowsCsiHandle := 0;
  end;
end;

function TTyTerminalCore.WindowsHeuristicCsiH(AParams: TTyTerminalParams): Boolean;
begin
  UpdateWindowsModeWrappedState;
  Result := False;
end;

{ WindowsMode.ts: mark the next line wrapped when the last character of this one is
  neither empty nor a space. For a combined cell upstream looks at the last UTF-16
  unit of its text, which is never 0 or 32 -- the same answer as its code point. }
procedure TTyTerminalCore.UpdateWindowsModeWrappedState;
var
  buf: TTyTerminalBuffer;
  line, below: TTyTerminalLine;
  code: Cardinal;
begin
  buf := Buffer;
  line := buf.Lines.Get(buf.YBase + buf.Y - 1);
  below := buf.Lines.Get(buf.YBase + buf.Y);
  if (below <> nil) and (line <> nil) then
  begin
    code := line.GetCodePoint(Cols - 1);
    below.IsWrapped := (code <> TyTermNullCellCode) and (code <> TyTermWhitespaceCellCode);
  end;
end;

{ ---- options ------------------------------------------------------------------------------------ }

function TTyTerminalCore.GetScrollback: Integer;
begin
  Result := FOptions.Scrollback;
end;

function TTyTerminalCore.GetTabStopWidth: Integer;
begin
  Result := FOptions.TabStopWidth;
end;

{ an option change event only fires for a different value (OptionsService.ts:135) }
procedure TTyTerminalCore.SetScrollback(AValue: Integer);
begin
  if AValue < 0 then
    raise EArgumentException.CreateFmt('scrollback cannot be less than 0, value: %d', [AValue]);
  { the ring allocates its slots up front (unit header of the buffer) }
  if AValue > TyTermMaxScrollback then
    AValue := TyTermMaxScrollback;
  if FOptions.Scrollback = AValue then
    Exit;
  FOptions.Scrollback := AValue;
  FBufferService.ScrollbackChanged;
end;

procedure TTyTerminalCore.SetTabStopWidth(AValue: Integer);
begin
  if AValue < 1 then
    raise EArgumentException.CreateFmt('tabStopWidth cannot be less than 1, value: %d', [AValue]);
  if FOptions.TabStopWidth = AValue then
    Exit;
  FOptions.TabStopWidth := AValue;
  FBufferService.TabStopWidthChanged;
end;

function TTyTerminalCore.GetWindowsPty: TTyTerminalWindowsPty;
begin
  Result := FOptions.WindowsPty;
end;

procedure TTyTerminalCore.SetWindowsPty(const AValue: TTyTerminalWindowsPty);
begin
  FOptions.WindowsPty := AValue;
  HandleWindowsPtyOptionChange;
end;

function TTyTerminalCore.GetOptBool(AIndex: Integer): Boolean;
begin
  case AIndex of
    0: Result := FOptions.ConvertEol;
    1: Result := FOptions.ScrollOnUserInput;
    2: Result := FOptions.DisableStdin;
    3: Result := FOptions.CursorBlink;
    4: Result := FOptions.ScrollOnEraseInDisplay;
  else
    Result := FOptions.AllowSetCursorBlink;
  end;
end;

procedure TTyTerminalCore.SetOptBool(AIndex: Integer; AValue: Boolean);
begin
  case AIndex of
    0: FOptions.ConvertEol := AValue;
    1: FOptions.ScrollOnUserInput := AValue;
    2: FOptions.DisableStdin := AValue;
    3: FOptions.CursorBlink := AValue;
    4: FOptions.ScrollOnEraseInDisplay := AValue;
  else
    FOptions.AllowSetCursorBlink := AValue;
  end;
end;

function TTyTerminalCore.GetCursorStyle: TTyTermCursorStyleOption;
begin
  Result := FOptions.CursorStyle;
end;

procedure TTyTerminalCore.SetCursorStyle(AValue: TTyTermCursorStyleOption);
begin
  FOptions.CursorStyle := AValue;
end;

{ ---- size, reset, scroll, input ------------------------------------------------------------------ }

procedure TTyTerminalCore.Resize(ACols, ARows: Integer);
begin
  CheckThread('Resize');
  if FBusy > 0 then
  begin
    Defer(tdkResize, ACols, ARows, '');  { from an event: after the chunk (unit header) }
    Exit;
  end;
  { headless Terminal.ts:90-96, then CoreTerminal.ts:187-200 }
  if (ACols = Cols) and (ARows = Rows) then
    Exit;
  if ACols < TyTermMinimumCols then ACols := TyTermMinimumCols;
  if ARows < TyTermMinimumRows then ARows := TyTermMinimumRows;
  { pending writes are parsed at the old size first }
  FlushSync;
  Inc(FBusy);
  try
    FBufferService.Resize(ACols, ARows);
  finally
    Dec(FBusy);
  end;
  RunDeferred;
  AfterDrive;
end;

{ headless Terminal.ts:122-132. From an event while the core is busy it waits for
  the chunk to finish, like Resize. }
procedure TTyTerminalCore.Reset;
begin
  CheckThread('Reset');
  if FBusy > 0 then
  begin
    Defer(tdkReset, 0, 0, '');
    Exit;
  end;
  Inc(FBusy);
  try
    DoReset;
  finally
    Dec(FBusy);
  end;
  RunDeferred;
  AfterDrive;
end;

{ CoreTerminal.ts:270-276 (and CoreBrowserTerminal.reset's mouse reset, :1110).
  Partial on purpose (unit header): not the parser, the title, the link numbers, a
  hidden cursor. RIS and DECCOLM run it from inside the parse. }
procedure TTyTerminalCore.DoReset;
var
  before: TTyTerminalModes;
begin
  before := GetModes;
  HandleWindowsPtyOptionChange;          { _setup() }
  InputHandlerReset;
  FBufferService.Reset;
  CharsetReset;
  CoreServiceReset;
  SetMouseProtocol(tmpNone);             { mouseStateService.reset }
  FMouseEncoding := tmeDefault;
  FHasLastMouse := False;                { mouseService.reset: _lastEvent = null }
  ModesChangedSince(before);
end;

procedure TTyTerminalCore.ScrollLines(ADelta: Integer);
begin
  CheckThread('ScrollLines');
  FBufferService.ScrollLines(ADelta);
end;

procedure TTyTerminalCore.ScrollPages(APages: Integer);
begin
  CheckThread('ScrollPages');
  { pages x rows in Int64: a huge page count scrolls to the end, it does not wrap }
  ScrollLines(ClampInt(Int64(APages) * (Rows - 1)));
end;

procedure TTyTerminalCore.ScrollToBottom;
begin
  CheckThread('ScrollToBottom');
  ScrollLines(Buffer.YBase - Buffer.YDisp);
end;

procedure TTyTerminalCore.ScrollToTop;
begin
  CheckThread('ScrollToTop');
  ScrollLines(-Buffer.YDisp);
end;

{ headless Terminal.ts:101-112: the cursor's line becomes the first line. The slot
  store takes the new reference before it drops the old one, so moving the cursor
  row into slot 0 needs no pin. }
procedure TTyTerminalCore.ClearScrollback;
var
  buf: TTyTerminalBuffer;
  row: TTyTerminalLine;
  i: Integer;
begin
  CheckThread('ClearScrollback');
  buf := Buffer;
  buf.ClearAllMarkers;
  row := buf.Lines.Get(buf.YBase + buf.Y);
  if row <> nil then
    buf.Lines.SetItem(0, row);
  buf.Lines.Length := 1;
  buf.YDisp := 0;
  buf.YBase := 0;
  buf.Y := 0;
  for i := 1 to Rows - 1 do
    buf.Lines.PushOwned(buf.GetBlankLine(TyTermDefaultAttr));
  { straight to onScroll, not through the buffer service: no dirty rows }
  if Assigned(FOnScroll) then
    FOnScroll(Self, buf.YDisp);
  if Assigned(FOnScrollbackCleared) then
    FOnScrollbackCleared(Self);
end;

procedure TTyTerminalCore.Input(const AData: RawByteString; AWasUserInput: Boolean);
begin
  CheckThread('Input');
  TriggerDataEvent(AData, AWasUserInput);
end;

function TTyTerminalCore.WindowTitleStack: TStringDynArray;
begin
  Result := Copy(FWindowTitleStack);
end;

function TTyTerminalCore.IconNameStack: TStringDynArray;
begin
  Result := Copy(FIconNameStack);
end;

function TTyTerminalCore.KittyStacks(AAlt: Boolean): TIntegerDynArray;
begin
  if AAlt then
    Result := Copy(FKittyAltStack)
  else
    Result := Copy(FKittyMainStack);
end;
