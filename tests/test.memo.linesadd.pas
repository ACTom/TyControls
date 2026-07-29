unit test.memo.linesadd;
{$mode objfpc}{$H+}
{ TTyMemo.Lines is handed out bare, so a mutation THROUGH it -- Lines.Add, Lines.Delete,
  Lines[i] := ... -- never reaches the control. Only the Lines SETTER invalidates.

  It looks like it works, which is what makes it expensive: the visual-row cache starts invalid,
  so lines added while the form is being built render fine. It breaks on the append that happens
  AFTER the memo has painted once -- the running-log pattern, which two shipped demos use on
  real TTyMemo instances (examples/dialogs, examples/filedialog).

  TTyComboBox hooks its own list one line into its constructor (FItems.OnChange := @ItemsChanged),
  which is what makes this an oversight rather than a design position. }
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Memo;
type
  TMemoLinesProbe = class(TTyMemo)
  public
    { Force the state a painted memo is in: the visual rows built and marked valid. }
    procedure ProbeEnsureRows(APPI: Integer);
    function ProbeRowCount: Integer;
  end;

  TMemoLinesAddTest = class(TTestCase)
  published
    procedure AddAfterFirstPaintIsSeen;
    procedure DeleteAfterFirstPaintIsSeen;
    procedure AssigningLinesStillWorks;
  end;

implementation

procedure TMemoLinesProbe.ProbeEnsureRows(APPI: Integer);
begin
  EnsureVisualRows(APPI);
end;

function TMemoLinesProbe.ProbeRowCount: Integer;
begin
  { Goes THROUGH the cache -- which is the point: a mutation the control never heard about
    leaves EnsureVisualRows short-circuiting on a stale FVisualRowsValid. }
  Result := TotalVisualRows(96);
end;

procedure TMemoLinesAddTest.AddAfterFirstPaintIsSeen;
var m: TMemoLinesProbe;
begin
  m := TMemoLinesProbe.Create(nil);
  try
    m.SetBounds(0, 0, 200, 100);
    m.Lines.Text := 'one';
    m.ProbeEnsureRows(96);                 // the memo has now "painted"
    AssertEquals('one line to start', 1, m.ProbeRowCount);
    m.Lines.Add('two');                    // the running-log pattern
    AssertEquals('the appended line is part of the content', 2, m.ProbeRowCount);
  finally
    m.Free;
  end;
end;

procedure TMemoLinesAddTest.DeleteAfterFirstPaintIsSeen;
var m: TMemoLinesProbe;
begin
  m := TMemoLinesProbe.Create(nil);
  try
    m.SetBounds(0, 0, 200, 100);
    m.Lines.Text := 'one' + LineEnding + 'two';
    m.ProbeEnsureRows(96);
    AssertEquals('two lines to start', 2, m.ProbeRowCount);
    m.Lines.Delete(1);
    AssertEquals('the removed line is gone from the content', 1, m.ProbeRowCount);
  finally
    m.Free;
  end;
end;

procedure TMemoLinesAddTest.AssigningLinesStillWorks;
var m: TMemoLinesProbe;
begin
  { The setter path already invalidated; hooking the list must not break it, and must not
    double-invalidate its way into a loop. }
  m := TMemoLinesProbe.Create(nil);
  try
    m.SetBounds(0, 0, 200, 100);
    m.Lines.Text := 'a';
    m.ProbeEnsureRows(96);
    m.Lines.Text := 'a' + LineEnding + 'b' + LineEnding + 'c';
    AssertEquals('assignment is still seen', 3, m.ProbeRowCount);
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TMemoLinesAddTest);
end.
