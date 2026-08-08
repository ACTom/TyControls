unit test.appicon;
{$mode objfpc}{$H+}

{ The application mark that every example links as MAINICON.

  WHY THIS EXISTS. An .ico that Windows reads perfectly can still be one LCL cannot, and the
  way that failure presents is the worst kind: the program starts, burns about eleven seconds
  of CPU, and then sits there forever with a main form it never shows. No exception dialog, no
  console output, nothing in the build log -- `lazbuild` is green and all 46 examples are
  bricked. That happened here, and it was the user who noticed, not the toolchain.

  The mechanism is one line of LCL:

    lcl/include/icon.inc, TCustomIcon.ReadStream
      if (IconDir[n].bWidth = 0) or (IconDir[n].bHeight = 0) then
        ... sniff for the PNG signature, use TLazReaderPNG ...
      else
        ... TLazReaderDIB, unconditionally ...

  ICONDIRENTRY stores a 256px entry's size as 0 (it does not fit in a byte), so 256 is the ONLY
  slot where LCL even looks for a PNG. A PNG payload anywhere else reaches the DIB reader, which
  reads the PNG's IHDR width where biCompression belongs -- 64 becomes 0x40000000 -- and raises
  FPImageException.

  And it raises it in the worst possible place. TApplication.Initialize resolves MAINICON itself,
  and TIcon.LoadFromResourceHandle does not ask for one size: it concatenates every RT_ICON into
  a synthetic .ico and parses all of them. So a single bad entry throws inside Initialize, which
  runs BEFORE Application.CreateForm -- no main form is ever built, Application.Run is never
  reached, and nothing is ever shown.

  So: NoPngEntryOutsideThe256Slot states that invariant on the bytes, and LclReadsEveryIcon runs
  the actual reader that breaks. The byte check names the defect; the reader check proves the
  consumer is happy. tools/genappicon self-checks the same way at generation time -- this is the
  guard for the file that gets hand-edited, replaced, or copied in from somewhere else.

  The two .lpi guards are the same class of defect one level up: an icon nothing references and
  a manifest that declares DPI-unawareness are both settings that LOOK present and do nothing. }

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry;

type
  TAppIconTests = class(TTestCase)
  private
    procedure CollectExampleProjects(ADest: TStrings);
  published
    procedure EveryExampleShipsTheMark;
    procedure EveryExampleReferencesItsIcon;
    procedure NoPngEntryOutsideThe256Slot;
    procedure LclReadsEveryIcon;
    procedure TheSizesWindowsAsksForArePresent;
    procedure EveryExampleDeclaresPerMonitorDpi;
  end;

implementation

uses
  FileUtil, test.designregistry;

type
  TIcoDirEntry = packed record
    bWidth, bHeight, bColorCount, bReserved: Byte;
    wPlanes, wBitCount: Word;
    dwBytesInRes, dwImageOffset: LongWord;
  end;

const
  PngSignature: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);

{ Every example project, excluding the untracked backup/ copies a few folders carry. }
procedure TAppIconTests.CollectExampleProjects(ADest: TStrings);
var
  all: TStringList;
  i: Integer;
begin
  ADest.Clear;
  all := FindAllFiles(RepoRoot + 'examples', '*.lpi', True);
  try
    for i := 0 to all.Count - 1 do
      if Pos(PathDelim + 'backup' + PathDelim, all[i]) = 0 then
        ADest.Add(all[i]);
  finally
    all.Free;
  end;
  AssertTrue('no example projects found under ' + RepoRoot + 'examples', ADest.Count > 0);
end;

{ Read an .ico's directory. Returns the entries; raises through AssertTrue on a malformed head. }
function ReadIcoDir(const AFile: string; out AEntries: array of TIcoDirEntry;
  out ACount: Integer; AStream: TMemoryStream): Boolean;
var
  reserved, kind, n: Word;
  i: Integer;
begin
  Result := False;
  ACount := 0;
  AStream.LoadFromFile(AFile);
  if AStream.Size < 6 then Exit;
  AStream.Position := 0;
  AStream.ReadBuffer(reserved, 2);
  AStream.ReadBuffer(kind, 2);
  AStream.ReadBuffer(n, 2);
  if (reserved <> 0) or (kind <> 1) or (n = 0) or (n > Length(AEntries)) then Exit;
  for i := 0 to n - 1 do
    AStream.ReadBuffer(AEntries[i], SizeOf(TIcoDirEntry));
  ACount := n;
  Result := True;
end;

procedure TAppIconTests.EveryExampleShipsTheMark;
var
  projects: TStringList;
  i: Integer;
  ico: string;
  missing: string;
begin
  projects := TStringList.Create;
  try
    CollectExampleProjects(projects);
    missing := '';
    for i := 0 to projects.Count - 1 do
    begin
      ico := ChangeFileExt(projects[i], '.ico');
      if not FileExists(ico) then
        missing := missing + LineEnding + '  ' + ExtractFileName(ico);
    end;
    AssertEquals('examples with no .ico beside the .lpi (Lazarus takes the project icon from' +
      ' ChangeFileExt(lpi, ''.ico'') and nowhere else; run scripts/gen-appicon.ps1):' + missing,
      '', missing);
  finally
    projects.Free;
  end;
end;

procedure TAppIconTests.EveryExampleReferencesItsIcon;
var
  projects: TStringList;
  src: TStringList;
  i: Integer;
  bad: string;
begin
  projects := TStringList.Create;
  src := TStringList.Create;
  try
    CollectExampleProjects(projects);
    bad := '';
    for i := 0 to projects.Count - 1 do
    begin
      src.LoadFromFile(projects[i]);
      { <Icon Value="0"/> is TProjectIcon.IsEmpty = False. Without it the .ico on disk is
        never read and the executable ships with no icon at all -- silently. }
      if Pos('<Icon Value="0"/>', src.Text) = 0 then
        bad := bad + LineEnding + '  ' + ExtractFileName(projects[i]);
    end;
    AssertEquals('examples whose .lpi never claims its icon (missing <Icon Value="0"/>, so the' +
      ' .ico beside it is decorative):' + bad, '', bad);
  finally
    src.Free;
    projects.Free;
  end;
end;

procedure TAppIconTests.NoPngEntryOutsideThe256Slot;
var
  projects: TStringList;
  st: TMemoryStream;
  entries: array[0..63] of TIcoDirEntry;
  count, i, n, k: Integer;
  sig: array[0..7] of Byte;
  isPng: Boolean;
  ico, bad: string;
begin
  projects := TStringList.Create;
  st := TMemoryStream.Create;
  try
    CollectExampleProjects(projects);
    bad := '';
    for i := 0 to projects.Count - 1 do
    begin
      ico := ChangeFileExt(projects[i], '.ico');
      if not FileExists(ico) then Continue;      { EveryExampleShipsTheMark owns that }
      AssertTrue(ExtractFileName(ico) + ': not a readable icon directory',
        ReadIcoDir(ico, entries, count, st));
      for n := 0 to count - 1 do
      begin
        if entries[n].dwImageOffset + 8 > LongWord(st.Size) then
        begin
          bad := bad + LineEnding + '  ' + ExtractFileName(ico) + ' entry ' + IntToStr(n) +
                 ': offset past end of file';
          Continue;
        end;
        st.Position := entries[n].dwImageOffset;
        st.ReadBuffer(sig, SizeOf(sig));
        isPng := True;
        for k := 0 to 7 do
          if sig[k] <> PngSignature[k] then begin isPng := False; Break; end;
        { bWidth = 0 IS 256 -- the one slot LCL sniffs for a PNG signature. }
        if isPng and (entries[n].bWidth <> 0) then
          bad := bad + LineEnding + '  ' + ExtractFileName(ico) + ': PNG-compressed ' +
                 IntToStr(entries[n].bWidth) + 'px entry';
      end;
    end;
    AssertEquals('PNG payloads outside the 256 slot. LCL sends these to the DIB reader, which' +
      ' reads the PNG IHDR width as biCompression and raises during startup -- the program' +
      ' never shows its window and says nothing (see the unit header):' + bad, '', bad);
  finally
    st.Free;
    projects.Free;
  end;
end;

procedure TAppIconTests.LclReadsEveryIcon;
var
  projects: TStringList;
  i: Integer;
  ic: TIcon;
  ico, bad: string;
begin
  projects := TStringList.Create;
  try
    CollectExampleProjects(projects);
    bad := '';
    for i := 0 to projects.Count - 1 do
    begin
      ico := ChangeFileExt(projects[i], '.ico');
      if not FileExists(ico) then Continue;
      ic := TIcon.Create;
      try
        try
          ic.LoadFromFile(ico);
          if ic.Count = 0 then
            bad := bad + LineEnding + '  ' + ExtractFileName(ico) + ': LCL read 0 entries';
        except
          on E: Exception do
            bad := bad + LineEnding + '  ' + ExtractFileName(ico) + ': ' + E.ClassName +
                   ': ' + E.Message;
        end;
      finally
        ic.Free;
      end;
    end;
    { This is the reader every LCL program runs over MAINICON at startup. If it throws here it
      throws there, and there it is invisible. }
    AssertEquals('LCL''s own TIcon cannot read these:' + bad, '', bad);
  finally
    projects.Free;
  end;
end;

procedure TAppIconTests.TheSizesWindowsAsksForArePresent;
var
  projects: TStringList;
  st: TMemoryStream;
  entries: array[0..63] of TIcoDirEntry;
  count, i, n, w: Integer;
  ico, bad, have: string;
  found16, found32, found48: Boolean;
begin
  projects := TStringList.Create;
  st := TMemoryStream.Create;
  try
    CollectExampleProjects(projects);
    bad := '';
    for i := 0 to projects.Count - 1 do
    begin
      ico := ChangeFileExt(projects[i], '.ico');
      if not FileExists(ico) then Continue;
      AssertTrue(ExtractFileName(ico) + ': not a readable icon directory',
        ReadIcoDir(ico, entries, count, st));
      found16 := False; found32 := False; found48 := False;
      have := '';
      for n := 0 to count - 1 do
      begin
        if entries[n].bWidth = 0 then w := 256 else w := entries[n].bWidth;
        have := have + ' ' + IntToStr(w);
        if w = 16 then found16 := True;
        if w = 32 then found32 := True;
        if w = 48 then found48 := True;
      end;
      { Windows asks for these three by name -- title bar and small task-switcher (16), shell
        and Alt-Tab (32), large icons (48). A file missing one of them gets a stretched
        neighbour instead, which is exactly the blurry look this whole change set to fix. }
      if not (found16 and found32 and found48) then
        bad := bad + LineEnding + '  ' + ExtractFileName(ico) + ' has only:' + have;
    end;
    AssertEquals('icons missing 16, 32 or 48:' + bad, '', bad);
  finally
    st.Free;
    projects.Free;
  end;
end;

procedure TAppIconTests.EveryExampleDeclaresPerMonitorDpi;
var
  projects: TStringList;
  src: TStringList;
  i: Integer;
  bad: string;
begin
  projects := TStringList.Create;
  src := TStringList.Create;
  try
    CollectExampleProjects(projects);
    bad := '';
    for i := 0 to projects.Count - 1 do
    begin
      src.LoadFromFile(projects[i]);
      { UseXPManifest alone links a manifest that says <dpiAware>False</dpiAware>: Windows then
        bitmap-stretches the window on a HiDPI screen and none of the per-monitor DPI code in
        this library ever runs. 44 of the 46 examples shipped that way. }
      if Pos('<DpiAware Value="True/PM_V2"/>', src.Text) = 0 then
        bad := bad + LineEnding + '  ' + ExtractFileName(projects[i]);
    end;
    AssertEquals('examples that link a DPI-UNAWARE manifest (UseXPManifest with no <XPManifest>' +
      ' block declares dpiAware=False):' + bad, '', bad);
  finally
    src.Free;
    projects.Free;
  end;
end;

initialization
  RegisterTest(TAppIconTests);

end.
