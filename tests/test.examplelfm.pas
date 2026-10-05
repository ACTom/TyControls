unit test.examplelfm;
{$mode objfpc}{$H+}

{ What the example forms (examples/*/*.lfm) say, read as text.

  They are written by hand, so they can say things the designer would never write. One such: an
  ItemIndex ahead of the Items it points into. The reader applies properties in the order the
  file gives them, so the index lands on an empty list, is clamped to -1, and the selection is
  gone by the time the items arrive -- the rtl example's button group came up with nothing
  selected. The designer writes Items first (it follows the published order), so only a
  hand-written file gets this wrong, and this sweep is what catches the next one. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, test.designregistry;

type
  TExampleLfmTest = class(TTestCase)
  published
    procedure TestItemIndexComesAfterItems;
  end;

implementation

procedure TExampleLfmTest.TestItemIndexComesAfterItems;
var
  files: TStringList;
  lines: TStringList;
  sr: TSearchRec;
  root, dir, f, s, bad: string;
  i, k, depth, idxLine, itemsLine, scanned: Integer;
  objIndent: array of Integer;
  objIdx, objItems: array of Integer;
  objName: array of string;

  function IndentOf(const L: string): Integer;
  begin
    Result := 1;
    while (Result <= Length(L)) and (L[Result] = ' ') do Inc(Result);
    Dec(Result);
  end;

begin
  root := IncludeTrailingPathDelimiter(RepoRoot) + 'examples' + PathDelim;
  files := TStringList.Create;
  lines := TStringList.Create;
  bad := '';
  scanned := 0;
  try
    if FindFirst(root + '*', faDirectory, sr) = 0 then
    try
      repeat
        if (sr.Name <> '.') and (sr.Name <> '..') and ((sr.Attr and faDirectory) <> 0) then
          files.Add(root + sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    for i := 0 to files.Count - 1 do
    begin
      dir := IncludeTrailingPathDelimiter(files[i]);
      if FindFirst(dir + '*.lfm', faAnyFile, sr) <> 0 then Continue;
      try
        repeat
          f := dir + sr.Name;
          Inc(scanned);
          lines.LoadFromFile(f);
          depth := 0;
          SetLength(objIndent, 0);
          SetLength(objIdx, 0);
          SetLength(objItems, 0);
          SetLength(objName, 0);
          for k := 0 to lines.Count - 1 do
          begin
            s := Trim(lines[k]);
            if (Pos('object ', s) = 1) or (Pos('inherited ', s) = 1) or (Pos('inline ', s) = 1) then
            begin
              Inc(depth);
              SetLength(objIndent, depth);
              SetLength(objIdx, depth);
              SetLength(objItems, depth);
              SetLength(objName, depth);
              objIndent[depth - 1] := IndentOf(lines[k]);
              objIdx[depth - 1] := -1;
              objItems[depth - 1] := -1;
              objName[depth - 1] := s;
            end
            else if (s = 'end') and (depth > 0) and (IndentOf(lines[k]) = objIndent[depth - 1]) then
            begin
              idxLine := objIdx[depth - 1];
              itemsLine := objItems[depth - 1];
              if (idxLine >= 0) and (itemsLine >= 0) and (idxLine < itemsLine) then
                bad := bad + Format('%s:%d  %s', [ExtractRelativePath(root, f), idxLine + 1,
                  objName[depth - 1]]) + LineEnding;
              Dec(depth);
            end
            else if (depth > 0) and (IndentOf(lines[k]) = objIndent[depth - 1] + 2) then
            begin
              if Pos('ItemIndex =', s) = 1 then objIdx[depth - 1] := k;
              if (Pos('Items.Strings', s) = 1) or (Pos('Items =', s) = 1) then
                objItems[depth - 1] := k;
            end;
          end;
        until FindNext(sr) <> 0;
      finally
        FindClose(sr);
      end;
    end;
    AssertTrue(Format('the sweep must read the example forms, and it read %d', [scanned]),
      scanned > 20);
    AssertEquals('example forms that set ItemIndex before the Items it points into:' +
      LineEnding + bad, '', bad);
  finally
    lines.Free;
    files.Free;
  end;
end;

initialization
  RegisterTest(TExampleLfmTest);
end.
