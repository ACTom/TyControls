unit test.dialogs.find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Dialogs, fpcunit, testregistry, tyControls.Dialogs.Find;

type
  TFindMapTest = class(TTestCase)
  published
    procedure TestOptionsToChecks;
    procedure TestChecksToOptionsRoundTrip;
    procedure TestBasePreserved;
    procedure TestExhaustiveRoundTrip;
  end;

implementation

procedure TFindMapTest.TestOptionsToChecks;
var ch: TTyFindChecks;
begin
  ch := TyFindOptionsToChecks([frMatchCase, frDown]);
  AssertTrue('matchcase', ch.MatchCase);
  AssertFalse('wholeword', ch.WholeWord);
  AssertFalse('searchup (frDown present)', ch.SearchUp);

  ch := TyFindOptionsToChecks([frWholeWord]);   // no frDown -> searching up
  AssertFalse('matchcase', ch.MatchCase);
  AssertTrue('wholeword', ch.WholeWord);
  AssertTrue('searchup (no frDown)', ch.SearchUp);
end;

procedure TFindMapTest.TestChecksToOptionsRoundTrip;
var ch: TTyFindChecks; opts: TFindOptions;
begin
  ch.MatchCase := True; ch.WholeWord := False; ch.SearchUp := False;
  opts := TyChecksToFindOptions(ch, []);
  AssertTrue('frMatchCase', frMatchCase in opts);
  AssertFalse('frWholeWord', frWholeWord in opts);
  AssertTrue('frDown (searchup false)', frDown in opts);

  ch := TyFindOptionsToChecks(opts);
  AssertTrue('rt matchcase', ch.MatchCase);
  AssertFalse('rt wholeword', ch.WholeWord);
  AssertFalse('rt searchup', ch.SearchUp);
end;

procedure TFindMapTest.TestBasePreserved;
var ch: TTyFindChecks; opts: TFindOptions;
begin
  ch.MatchCase := False; ch.WholeWord := True; ch.SearchUp := True;
  // untouched base flags (frReplace, frEntireScope) must survive
  opts := TyChecksToFindOptions(ch, [frReplace, frReplaceAll, frEntireScope, frDown]);
  AssertTrue('frReplace kept', frReplace in opts);
  AssertTrue('frReplaceAll kept', frReplaceAll in opts);
  AssertTrue('frEntireScope kept', frEntireScope in opts);
  AssertTrue('frWholeWord set', frWholeWord in opts);
  AssertFalse('frDown cleared (searchup true)', frDown in opts);
end;

procedure TFindMapTest.TestExhaustiveRoundTrip;
var i: Integer; ch, ch2: TTyFindChecks; opts: TFindOptions;
begin
  for i := 0 to 7 do
  begin
    ch.MatchCase := (i and 1) <> 0;
    ch.WholeWord := (i and 2) <> 0;
    ch.SearchUp  := (i and 4) <> 0;
    opts := TyChecksToFindOptions(ch, []);
    ch2  := TyFindOptionsToChecks(opts);
    AssertTrue('rt ' + IntToStr(i), (ch.MatchCase = ch2.MatchCase)
      and (ch.WholeWord = ch2.WholeWord) and (ch.SearchUp = ch2.SearchUp));
  end;
end;

initialization
  RegisterTest(TFindMapTest);
end.
