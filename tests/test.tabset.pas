unit test.tabset;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.TabSet;
type
  TTabSetTest = class(TTestCase)
  private
    FChanged: Boolean;
    procedure OnChangeHandler(Sender: TObject);
  published
    procedure TestTabCountFromTabs;
    procedure TestSelectFiresOnChange;
    procedure TestRemoveClampsIndex;
    procedure TestStyleTypeKey;
    procedure TestRemoveBeforeSelected;
    procedure TestRemoveAfterSelected;
    procedure TestRemoveOnlyTab;
    procedure TestRemoveSelectedNotLast;
  end;
implementation

procedure TTabSetTest.OnChangeHandler(Sender: TObject); begin FChanged := True; end;

procedure TTabSetTest.TestTabCountFromTabs;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['One','Two','Three']);
    AssertEquals('count', 3, t.TabCountForTest);
    AssertEquals('caption', 'Two', t.TabCaptionForTest(1));
  finally t.Free; end;
end;

procedure TTabSetTest.TestSelectFiresOnChange;
var t: TTyTabSet;
begin
  FChanged := False;
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B']);
    t.OnChange := @OnChangeHandler;
    t.TabIndex := 1;
    AssertEquals('index', 1, t.TabIndex);
    AssertTrue('OnChange fired', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveClampsIndex;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 2;
    t.RemoveTabForTest(2);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('clamped', 1, t.TabIndex);
  finally t.Free; end;
end;

procedure TTabSetTest.TestStyleTypeKey;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try AssertEquals('TyTabControl', t.StyleTypeKeyForTest); finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveBeforeSelected;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 2;
    t.OnChange := @OnChangeHandler;
    FChanged := False;
    t.RemoveTabForTest(0);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('decremented', 1, t.TabIndex);
    AssertTrue('OnChange fired', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveAfterSelected;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 0;
    t.OnChange := @OnChangeHandler;
    FChanged := False;
    t.RemoveTabForTest(2);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('unchanged', 0, t.TabIndex);
    AssertFalse('OnChange did not fire', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveOnlyTab;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A']);
    t.TabIndex := 0;
    t.RemoveTabForTest(0);
    AssertEquals('tabs', 0, t.Tabs.Count);
    AssertEquals('none', -1, t.TabIndex);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveSelectedNotLast;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 1;
    t.OnChange := @OnChangeHandler;
    FChanged := False;
    t.RemoveTabForTest(1);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('numerically unchanged', 1, t.TabIndex);
    AssertFalse('OnChange did not fire (deliberate no-notify)', FChanged);
  finally t.Free; end;
end;

initialization
  RegisterTest(TTabSetTest);
end.
