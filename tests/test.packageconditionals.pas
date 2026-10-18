unit test.packageconditionals;
{$mode objfpc}{$H+}

{ #81 / #88: the macOS IME types moved in Lazarus 4.0 (CocoaPrivate -> CocoaFullControlEdit), and a
  uses clause cannot ask a unit of its own clause which Lazarus it is compiled with. #81 had the
  package ask and pass a define down -- which a project compiling source/ itself never gets (#88).
  tyControls.CocoaWS now asks LCLVersion, used in its interface, from its implementation's uses.

  Nothing in this suite compiles for macOS, so this pins the shape of that question; the macOS
  cross-builds (package and a source-path example, Lazarus 3.0 and 4.x) are the real proof. }

interface

uses
  Classes, SysUtils, FileUtil, fpcunit, testregistry, test.designregistry;

type
  TPackageConditionalsTest = class(TTestCase)
  published
    procedure TestTheCocoaImeUnitFollowsTheLazarusVersion;
    { #88 moved the handler class into CocoaWS's implementation: a control that names it no
      longer compiles for macOS -- and nothing here compiles for macOS. The terminal did, on
      main; the controls ask TyCocoaNewImeHandler. }
    procedure TestOnlyCocoaWSNamesTheImeHandlerClass;
    { #82: LCL-GTK3's IsWayland and IMCommitStr exist only from Lazarus 4.99 (trunk) on, so the
      package defines TY_LCL_FROM_4_99 there and tyControls.Gtk3WS reads them only under it. }
    procedure TestTheGtk3TrunkMembersFollowTheLazarusVersion;
    { #89: LCL-Cocoa wraps a form's content and every custom control in an NSScrollView. In a
      full-size-content window AppKit gives each one under the title bar an automatic top
      content inset, and before macOS 15 its hit test keeps that inset to the scroll view:
      a press on a control in TTyTitleBar went to the scroll view around it (seen on 12.7,
      not on 15.3). A category on TCocoaScrollView sends such a press on into the document.
      Nothing here compiles for macOS: this pins the shape, macOS 12 is the proof. }
    procedure TestAPressUnderTheMacTitleBarReachesTheControl;
  end;

implementation

function FileText(const ARel: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(RepoRoot + ARel);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

procedure TPackageConditionalsTest.TestTheCocoaImeUnitFollowsTheLazarusVersion;
var lpk, unitText: string;
  impl, choice: Integer;
begin
  lpk := FileText('tycontrols.lpk');
  unitText := FileText('source' + PathDelim + 'tyControls.CocoaWS.pas');
  impl := Pos(LineEnding + 'implementation' + LineEnding, unitText);
  choice := Pos('{$IF lcl_fullversion >= 4000000}CocoaFullControlEdit{$ELSE}CocoaPrivate{$ENDIF}',
    unitText);
  AssertTrue('the unit reads LCLVersion in its interface',
    (Pos('  LCLVersion,', unitText) > 0) and (Pos('  LCLVersion,', unitText) < impl));
  AssertTrue('and picks the IME unit by it in its implementation''s uses',
    (choice > 0) and (choice > impl));
  AssertTrue('no package define in the unit: a source-path project would not get it',
    Pos('TY_LCL_BEFORE_4', unitText) = 0);
  AssertTrue('nor in the package', Pos('TY_LCL_BEFORE_4', lpk) = 0);
end;

procedure TPackageConditionalsTest.TestOnlyCocoaWSNamesTheImeHandlerClass;
var files: TStringList;
  i, n: Integer;
  sl: TStringList;
  naming: string;
begin
  files := FindAllFiles(RepoRoot + 'source', '*.pas;*.inc', True);
  sl := TStringList.Create;
  try
    n := 0;
    naming := '';
    for i := 0 to files.Count - 1 do
    begin
      if SameText(ExtractFileName(files[i]), 'tyControls.CocoaWS.pas') then Continue;
      Inc(n);
      sl.LoadFromFile(files[i]);
      if Pos('TTyCocoaImeHandler', sl.Text) > 0 then
        naming := naming + ' ' + ExtractFileName(files[i]);
    end;
    AssertTrue('precondition: the scan read the sources', n > 50);
    AssertEquals('units naming the implementation-only class', '', naming);
  finally
    sl.Free;
    files.Free;
  end;
end;

procedure TPackageConditionalsTest.TestTheGtk3TrunkMembersFollowTheLazarusVersion;
var lpk, unitText: string;
begin
  lpk := FileText('tycontrols.lpk');
  unitText := FileText('source' + PathDelim + 'tyControls.Gtk3WS.pas');
  AssertTrue('the package defines TY_LCL_FROM_4_99 from Lazarus 4.99 on',
    Pos('GetIDEValue(&apos;LAZ_FULLVERSION&apos;) &gt;= 4990000 then CustomOptions += &apos; -dTY_LCL_FROM_4_99&apos;', lpk) > 0);
  AssertTrue('IsWayland is read only under it',
    Pos('{$IFDEF TY_LCL_FROM_4_99}' + LineEnding + '  { The backend already knows', unitText) > 0);
  AssertTrue('and so is IMCommitStr',
    Pos('{$IFDEF TY_LCL_FROM_4_99}' + LineEnding + '  if GTK3WidgetSet = nil then Exit;', unitText) > 0);
end;

procedure TPackageConditionalsTest.TestAPressUnderTheMacTitleBarReachesTheControl;
var unitText, body: string;
  i, e: Integer;
begin
  unitText := FileText('source' + PathDelim + 'tyControls.CocoaWS.pas');
  AssertTrue('a category on LCL-Cocoa''s scroll view',
    Pos('objccategory(TCocoaScrollView)', unitText) > 0);
  AssertTrue('replacing hitTest:',
    Pos('function hitTest(aPoint: NSPoint): NSView; message ''hitTest:''; reintroduce;',
      unitText) > 0);
  i := Pos('function TyScrollViewInsetHit.hitTest(aPoint: NSPoint): NSView;', unitText);
  AssertTrue('implemented', i > 0);
  e := Pos(LineEnding + 'end;', Copy(unitText, i, MaxInt));
  body := Copy(unitText, i, e);
  AssertTrue('AppKit''s answer first', Pos('inherited hitTest(aPoint)', body) > 0);
  AssertTrue('only in a window whose frame TTyForm runs (full-size content)',
    Pos('NSFullSizeContentViewWindowMask', body) > 0);
  AssertTrue('and only where AppKit kept the press to the scroll view itself',
    Pos('Result <> NSView(self)', body) > 0);
  AssertTrue('then the document''s own hit test',
    (Pos('doc := NSView(documentView);', body) > 0) and (Pos('doc.hitTest(', body) > 0));
end;

initialization
  RegisterTest(TPackageConditionalsTest);

end.
