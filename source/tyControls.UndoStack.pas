unit tyControls.UndoStack;

{ Reusable snapshot-based undo/redo stack with typing coalescing.

  A control serializes its full editable state to an opaque string snapshot
  and pushes it (with a "kind" tag) BEFORE each mutation. Consecutive
  single-character typing inserts collapse into ONE undo step. Any non-typing
  mutation (delete/backspace/Enter/paste/cut/word-delete), an Undo/Redo, or an
  explicit BreakCoalescing (e.g. caret nav / selection change) starts a fresh
  step. New pushes always clear the redo stack. The stack is bounded by FCap;
  when exceeded, the oldest entry is dropped.

  Usage contract: the caller checks CanUndo/CanRedo first; Undo/Redo receive
  the CURRENT serialized state so it can be moved onto the opposite stack. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  uskNone        = 0;
  uskTyping      = 1;
  uskDelete      = 2;
  uskBackspace   = 3;
  uskNewline     = 4;
  uskPaste       = 5;
  uskCut         = 6;

type
  TTyUndoStack = class
  private
    FUndo: TStringList;       // snapshots, top = last index
    FRedo: TStringList;       // snapshots, top = last index
    FLastKind: Byte;          // kind of the most recent push
    FBroken: Boolean;         // coalescing broken (next typing starts fresh)
    function GetUndoDepth: Integer;
    function GetRedoDepth: Integer;
  public
    const FCap = 200;
    constructor Create;
    destructor Destroy; override;
    procedure Push(const ASnapshot: string; AKind: Byte);
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function Undo(const ACurrent: string): string;
    function Redo(const ACurrent: string): string;
    procedure Clear;
    procedure BreakCoalescing;
    property UndoDepth: Integer read GetUndoDepth;
    property RedoDepth: Integer read GetRedoDepth;
  end;

implementation

constructor TTyUndoStack.Create;
begin
  inherited Create;
  FUndo := TStringList.Create;
  FRedo := TStringList.Create;
  FLastKind := uskNone;
  FBroken := False;
end;

destructor TTyUndoStack.Destroy;
begin
  FUndo.Free;
  FRedo.Free;
  inherited Destroy;
end;

function TTyUndoStack.GetUndoDepth: Integer;
begin
  Result := FUndo.Count;
end;

function TTyUndoStack.GetRedoDepth: Integer;
begin
  Result := FRedo.Count;
end;

function TTyUndoStack.CanUndo: Boolean;
begin
  Result := FUndo.Count > 0;
end;

function TTyUndoStack.CanRedo: Boolean;
begin
  Result := FRedo.Count > 0;
end;

procedure TTyUndoStack.Push(const ASnapshot: string; AKind: Byte);
begin
  // Any new edit invalidates the redo history.
  FRedo.Clear;

  // Coalesce consecutive typing into a single step.
  if (AKind = uskTyping) and (FLastKind = uskTyping)
     and (not FBroken) and (FUndo.Count > 0) then
  begin
    // Skip pushing a new snapshot: the existing top already represents the
    // state before this typing run began.
    Exit;
  end;

  FUndo.Add(ASnapshot);

  // Enforce the bounded capacity by dropping the oldest entry.
  while FUndo.Count > FCap do
    FUndo.Delete(0);

  FLastKind := AKind;
  FBroken := False;
end;

function TTyUndoStack.Undo(const ACurrent: string): string;
var
  idx: Integer;
begin
  if FUndo.Count = 0 then
  begin
    // Caller should check CanUndo first; be safe and no-op.
    Result := ACurrent;
    Exit;
  end;
  // Move current state onto the redo stack.
  FRedo.Add(ACurrent);
  while FRedo.Count > FCap do
    FRedo.Delete(0);

  idx := FUndo.Count - 1;
  Result := FUndo[idx];
  FUndo.Delete(idx);

  // An undo always breaks the coalescing run.
  FBroken := True;
  FLastKind := uskNone;
end;

function TTyUndoStack.Redo(const ACurrent: string): string;
var
  idx: Integer;
begin
  if FRedo.Count = 0 then
  begin
    Result := ACurrent;
    Exit;
  end;
  // Move current state back onto the undo stack.
  FUndo.Add(ACurrent);
  while FUndo.Count > FCap do
    FUndo.Delete(0);

  idx := FRedo.Count - 1;
  Result := FRedo[idx];
  FRedo.Delete(idx);

  // A redo also breaks the coalescing run.
  FBroken := True;
  FLastKind := uskNone;
end;

procedure TTyUndoStack.Clear;
begin
  FUndo.Clear;
  FRedo.Clear;
  FLastKind := uskNone;
  FBroken := False;
end;

procedure TTyUndoStack.BreakCoalescing;
begin
  FBroken := True;
end;

end.
