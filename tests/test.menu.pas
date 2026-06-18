unit test.menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Menus, fpcunit, testregistry, tyControls.Menu;
type
  TMenuModelTest = class(TTestCase)
  published
    procedure TestBuildRowsMapsFields;
  end;
implementation

procedure TMenuModelTest.TestBuildRowsMapsFields;
var mm: TMainMenu; top, sub: TMenuItem; rows: TTyMenuRowArray;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'File';        mm.Items.Add(top);
    // children of 'File': an item with a shortcut, a separator, a checked item, a submenu
    sub := TMenuItem.Create(mm); sub.Caption := 'Open'; sub.ShortCut := ShortCut(Ord('O'), [ssCtrl]);
    top.Add(sub);
    top.Add(NewLine);                                          // separator ('-')
    sub := TMenuItem.Create(mm); sub.Caption := 'Word Wrap'; sub.Checked := True; top.Add(sub);
    sub := TMenuItem.Create(mm); sub.Caption := 'Recent';
    sub.Add(NewItem('doc.txt', 0, False, True, nil, 0, ''));   // makes 'Recent' a submenu
    top.Add(sub);
    sub := TMenuItem.Create(mm); sub.Caption := 'Hidden'; sub.Visible := False; top.Add(sub);

    rows := TyBuildMenuRows(top);                              // rows for File's dropdown
    AssertEquals('visible rows', 4, Length(rows));             // Open, sep, Word Wrap, Recent (Hidden skipped)
    AssertEquals('open caption', 'Open', rows[0].Caption);
    AssertTrue ('open has shortcut text', rows[0].ShortcutText <> '');
    AssertTrue ('row1 is separator', rows[1].Kind = mrkSeparator);
    AssertTrue ('word wrap checked', rows[2].Checked);
    AssertTrue ('recent has submenu', rows[3].HasSubmenu);
  finally
    mm.Free;
  end;
end;

initialization
  RegisterTest(TMenuModelTest);
end.
