unit tyControls.MaskEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, LCLType,
  tyControls.Edit;

const
  { The placeholder LCL and Delphi both default to (maskedit.pp DefaultBlank). }
  TyMaskDefaultBlank = '_';

type
  { Raised for a mask this control cannot honour. See TTyMaskEdit.Mask. }
  ETyMaskError = class(Exception);

  { What a slot accepts, before '>' / '<' case forcing is applied. }
  TTyMaskKind = (mkDigit, mkLetter, mkAlnum, mkAny, mkHex, mkBin);
  { The '>' / '<' region a slot sits in ('<>' turns forcing back off). }
  TTyMaskCase = (mcAsTyped, mcUpper, mcLower);

  { One position of the display string: either a fixed literal or an editable slot.
    Every mask compiles to exactly one of these per displayed character, which is what
    makes the display string addressable by index -- the whole basis of in-place editing. }
  TTyMaskCell = record
    IsLiteral: Boolean;
    Literal:   Char;          // meaningful when IsLiteral
    Kind:      TTyMaskKind;   // meaningful when not IsLiteral
    Required:  Boolean;       // 'L' vs 'l': a required slot must be filled to be complete
    CaseMode:  TTyMaskCase;
  end;
  TTyMaskCells = array of TTyMaskCell;

  { A compiled mask. Reject <> '' means the mask is refused and nothing else in here
    is meaningful. }
  TTyMaskSpec = record
    Cells:        TTyMaskCells;
    Blank:        Char;         // the ';;blank' field, when the mask carried one
    HasBlank:     Boolean;
    SaveLiterals: Boolean;      // the ';save;' field -- see TTyMaskEdit.MaskSavesLiterals
    TrimLeft:     Boolean;      // '!' -- see the note on TTyMaskEdit.Mask
    Reject:       string;       // '' = usable
  end;

{ Compile AMask. This is LCL/Delphi's mask language (maskedit.pp), with the two
  deliberate departures documented on TTyMaskEdit.Mask -- '#' is refused, and ':' / '/'
  are ordinary literals rather than locale separators. }
function TyMaskParse(const AMask: string): TTyMaskSpec;
{ '' when AMask is usable, otherwise the reason it is not. Setting Mask raises
  ETyMaskError with this text; call it first to check a mask without raising. }
function TyMaskRejectReason(const AMask: string): string;
{ Does the slot written ASlot accept ACh? ASlot is a mask CODE ('0', 'l', 'C', 'h' ...);
  anything that is not a slot code answers False. ABlank, when given, is excluded from
  every slot -- the placeholder is never content. Case forcing is a property of the
  MASK ('>' / '<' regions), not of a code, so it cannot be expressed here. }
function TyMaskSlotAccepts(ASlot, ACh: Char; ABlank: Char = #0): Boolean;
{ Lay the significant chars of ARaw into AMask's slots in order, inserting literals
  between them. This is the PACKING interpretation, the one paste and `Text :=` use.

  ABlank = #0 keeps the SHORT form: emission stops at the end of the input and a pending
  trailing literal is dropped, so "12" on '00/00' stays "12".

  ABlank <> #0 emits the SKELETON: the whole mask, every literal in place, and ABlank in
  every slot the input did not reach -- '__/__/____' empty, '12/__/____' half-typed. }
function TyMaskApply(const AMask, ARaw: string; ABlank: Char = #0): string;
{ Rebuild AText POSITIONALLY: cell by cell, a literal emits its literal and a slot keeps
  the character sitting at that position if the slot accepts it (case-forced) and emits
  ABlank if it does not. Unlike TyMaskApply this preserves HOLES -- '1_/_4' stays
  '1_/_4' -- which is what in-place editing produces and append-only entry never could.
  A no-op on a string that already conforms, which is exactly the test SetMaskedText
  needs; see the warning about re-filtering there. }
function TyMaskNormalize(const AMask, AText: string; ABlank: Char): string;
{ True when AText is EXACTLY what AMask produces for the characters it carries: literals
  in their own places, every significant char legal for its slot, and nothing left over. }
function TyMaskConforms(const AMask, AText: string; ABlank: Char = #0): Boolean;
{ Recover the significant characters from AText for AMask. Slots holding ABlank
  contribute nothing; literals contribute nothing UNLESS the mask asked for them with a
  ';1;' save field. A misaligned literal ends the recovery. }
function TyMaskExtract(const AMask, AText: string; ABlank: Char = #0): string;
{ Mask code of the (AFilledCount+1)-th editable slot, or #0 when all slots are filled.
  The code returned is the canonical spelling of that slot ('0'/'9', 'L'/'l', 'A'/'a',
  'C'/'c', 'H'/'h', 'B'/'b'); a '>' / '<' region is not expressible in one character. }
function TyMaskNextSlot(const AMask: string; AFilledCount: Integer): Char;
{ Caret index (0-based, into the string TyMaskApply produces) that AFilledCount filled
  characters leave next in line, or the display length when they fill the mask. The caret
  belongs THERE and not at the end of the display string: with a skeleton in the box those
  two stopped being the same place. }
function TyMaskCaretSlot(const AMask: string; AFilledCount: Integer): Integer;
{ True when every REQUIRED slot in AMask is filled by AText and every literal lines up.
  Optional slots ('9', 'l', 'a', 'c', 'h', 'b') may be blank and still be complete --
  that is what makes them optional. ABlank never counts as filled. }
function TyMaskIsComplete(const AMask, AText: string; ABlank: Char = #0): Boolean;
{ Number of display positions the mask occupies (literals included). }
function TyMaskCellCount(const AMask: string): Integer;
{ True when the 1-based display position AIndex is a fixed literal (or out of range). }
function TyMaskIsLiteralAt(const AMask: string; AIndex: Integer): Boolean;
{ First editable display position >= AFrom (1-based), or 0 when there is none. }
function TyMaskNextEditable(const AMask: string; AFrom: Integer): Integer;
{ Last editable display position <= ABefore (1-based), or 0 when there is none. }
function TyMaskPrevEditable(const AMask: string; ABefore: Integer): Integer;

type
  { A masked edit (date / phone / IP ...). Subclasses TTyEdit and reuses its text engine +
    'TyEdit' theme. The displayed Text is always the whole mask -- literals in place and
    the placeholder in every slot not yet filled -- so it is addressable by position, and
    entry is IN PLACE: the caret can sit in any editable slot and typing overwrites that
    slot. Set Mask to '' to fall back to a plain edit.

    SpaceChar = #0 removes the placeholder, and with it the slots a caret could sit in;
    that mode keeps the older append-only behaviour. }
  TTyMaskEdit = class(TTyEdit)
  private
    FMask: string;
    FSpec: TTyMaskSpec;
    FSpaceChar: Char;
    { Text as it stood when this focus visit began, and the "already reported" latch. Both are
      LCL's (maskedit.pp FTextOnEnter / FValidationFailed): the on-exit check must only fire
      when the USER changed something during the visit, and must never raise a second time
      while the first exception is still unwound. }
    FTextOnEnter: string;
    FValidationFailed: Boolean;
    procedure SetMask(const AValue: string);
    procedure SetSpaceChar(const AValue: Char);
    procedure ApplyRaw(const ARaw: string);
    procedure SetMaskedText(const AValue: TCaption);
    function  GetMaskSavesLiterals: Boolean;
    { The significant characters currently held, blanks excluded. }
    function  RawText: string;
    { True while the display string is a full addressable skeleton, i.e. while a caret can
      be put IN a slot. The append-only model is what is left when it is not. }
    function  InPlace: Boolean;
    { Text, repaired to the mask's shape. Everything positional starts here, so a display
      string that some other code path left misaligned cannot corrupt an edit. }
    function  ShapedText: string;
    procedure Commit(const AText: string; ACaret: Integer);
    procedure BlankRange(var AText: string; AFrom, ATo: Integer);
    procedure TypeInPlace(ACh: Char);
    procedure ErasePlace(AForward: Boolean);
    function  PasteInPlace(const AText: string): Boolean;
  protected
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    { The validation MOMENT LCL has and this control did not (maskedit.pp:2094-2112). Without
      it a half-typed '12/__/____' left the control in silence and reached business code
      unless every caller remembered to poll IsComplete at every exit point -- and one that
      forgets is exactly the bug a mask edit exists to prevent.

      LCL's own three guards, all load-bearing: `inherited DoExit` runs FIRST so an OnExit
      handler can fix the value before anything is raised; nothing is checked unless the user
      actually CHANGED the text during this visit (tabbing through an untouched field is not
      an error); and FValidationFailed stops a second raise while the first is still unwound,
      which would abort the application rather than report anything. }
    procedure DoExit; override;
    { The seam TTyEdit provides for exactly this, and the one path this control never
      took. Typing was masked because UTF8KeyPress is overridden; PASTE is not typing --
      it funnels through InjectStringAt -> FilterInsert, which was inherited unchanged.
      So Ctrl+V put arbitrary text into a masked field: a phone mask happily held
      "hello world", IsComplete then answered about a string the mask never approved,
      and the caller's TyMaskExtract read back nonsense. LCL guards the same three
      messages (LM_PASTE/LM_CUT/LM_CLEAR) for the same reason. }
    function FilterInsert(const AText: string): string; override;
  public
    constructor Create(AOwner: TComponent); override;
    { The two erase entry points that do NOT go through KeyDown, so overriding KeyDown alone
      left them cutting raw characters out of the display -- literals and placeholders with
      them. Both mean here what Backspace and Delete mean at the keyboard: Backspace blanks
      the slot before the caret, Delete blanks the slot at it. }
    procedure InjectBackspace; override;
    procedure InjectDelete; override;
    // True when every REQUIRED slot of the mask is filled (e.g. gate an OK button).
    function IsComplete: Boolean;
    { The significant characters, with placeholders stripped -- the VALUE behind the
      display. `M.Text` is what the user sees ('12/__/____'); this is what it means ('12').
      Literals are stripped too unless the mask asked to keep them; see
      MaskSavesLiterals. }
    function MaskedValue: string;
    { Raise ETyMaskError when a mask is in force and its required slots are not all filled.
      Public and virtual, as LCL's is (maskedit.pp:315): call it from an OK button to refuse
      a half-typed value, or override it to report differently. A no-op when Mask is '' --
      an unmasked edit has nothing to validate against. }
    procedure ValidateEdit; virtual;
    { The ';save;' field of the mask, LCL's MaskSave: True keeps the mask's literals in
      MaskedValue, False strips them. A mask that does not spell the field reads False,
      which is this control's long-standing MaskedValue ('12/__/____' -> '12'); LCL's
      implicit default is the other way, but LCL is answering about its Text and ours is
      the display string, so there is nothing to be compatible with. }
    property MaskSavesLiterals: Boolean read GetMaskSavesLiterals;
  published
    { THE MASK LANGUAGE.

      This is LCL and Delphi's language (maskedit.pp), not the three-code dialect this
      control used to speak. Slot codes, required on the left, optional on the right:

        0 / 9   a digit
        L / l   a letter
        A / a   a letter or a digit
        C / c   any character except the placeholder
        H / h   a hex digit          (Lazarus extension)
        B / b   a binary digit       (Lazarus extension)

      Plus the directives: '\' makes the next character a literal, '>' forces the slots
      after it to upper case, '<' to lower case and '<>' back to neither, and a trailing
      ';save;blank' sets MaskSavesLiterals and SpaceChar. EVERY other character is a fixed
      literal, auto-inserted between slots.

      TWO DELIBERATE DEPARTURES, both of which would otherwise be silent:

        * '#' is REFUSED. It is the one code the two languages disagree about: here it
          used to mean a required digit, in LCL/Delphi it means an optional digit-or-sign.
          Reinterpreting it would quietly turn every existing '##/##/####' into a mask
          IsComplete and ValidateEdit wave through EMPTY -- a validator going silent,
          which is the single failure a masked edit exists to prevent. Write '0' for the
          old meaning, '9' for an optional digit, '\#' for a literal '#'.
        * ':' and '/' stay ordinary literals. In LCL they render the locale's time and
          date separator, but Text here IS the display string and is published and
          streamed, so a locale-dependent literal would make one .lfm mean two different
          strings on two machines. Write the separator you want.

      '!' is accepted and has nothing left to do: it asks LCL to trim leading rather than
      trailing blanks from the data, and MaskedValue already contains no blanks at either
      end or in the middle.

      Still refused, for the reason it always was: a non-empty mask with NO editable slot
      ('---', '()'). A field that cannot accept input has no legitimate use -- an inert
      edit is spelled Mask := '' (plain edit, still supported) or ReadOnly := True. }
    property Mask: string read FMask write SetMask;
    { The placeholder drawn in every slot the user has not filled -- LCL's SpaceChar
      (maskedit.pp:305, published :364), default '_' on both. It is what makes the display
      string a full-length, addressable skeleton, and therefore what makes the caret able
      to sit in a slot at all.

      #0 turns the skeleton off and restores the older, shorter display, in which Text
      holds only what has been typed and entry is append-only (there is no empty slot to
      put a caret in). Two consequences worth knowing before choosing:
        * Text is the DISPLAY string, so with a skeleton in force an untouched field reads
          '__/__/____' rather than ''. MaskedValue is the value ('' there); IsComplete and
          TyMaskExtract both already ignore placeholders.
        * TextHint only shows for an empty Text, so a skeleton supersedes it. That is the
          intent -- a skeleton says more than a hint and does not vanish at the first
          keystroke -- but a control relying on TextHint wants SpaceChar := #0.

      A mask carrying a ';save;blank' field sets this; an explicit assignment afterwards
      wins. Unlike LCL, a mask WITHOUT that field leaves it alone rather than resetting it
      to '_', so SpaceChar := #0 survives a change of mask. }
    property SpaceChar: Char read FSpaceChar write SetSpaceChar default TyMaskDefaultBlank;
    { LCL and Delphi both call this property EditMask (maskedit.pp), so code ported
      from either failed to compile on the name alone. This is an alias on the same
      field, not a second mask. Not streamed: Mask is the persisted name. }
    property EditMask: string read FMask write SetMask stored False;
    { Typing (UTF8KeyPress), Delete/Backspace (KeyDown) and paste (FilterInsert) were all
      overridden. The plainest entry point of all was not: `Ed.Text := 'hello world'` went
      straight to TTyEdit's setter, so a phone field held a sentence, IsComplete then
      answered about a string the mask had never approved -- it counted slot POSITIONS, not
      legal characters, so '000-000' holding 'abc-def' reported COMPLETE -- and the
      caller's TyMaskExtract read back 'abcdef'.

      An assignment is now judged exactly as a paste into an empty field is: feed the
      incoming characters through the free slots in turn, keep what fits, drop the rest,
      rebuild the literals. One rule for both, so `Ed.Text := S` and Ctrl+V of the same S
      can never disagree.

      It never rejects and never raises -- LCL does not either (maskedit.pp:1656
      ApplyMaskToText, whose own comment ends "The text that is set, does not need to
      validate"; it pads and truncates instead). We do both.

      Static binding, unavoidable: this is a property override, so it intercepts
      assignments made through a TTyMaskEdit-typed (or descendant) reference. Casting to
      the base -- `TTyEdit(M).Text := X` -- still reaches TTyEdit's setter unfiltered.
      Do not do that. }
    property Text write SetMaskedText;
  end;

implementation

{ ------------------------------------------------------------------ compiling a mask --- }

function UpCh(c: Char): Char;
begin
  if c in ['a'..'z'] then Result := Chr(Ord(c) - 32) else Result := c;
end;

function LoCh(c: Char): Char;
begin
  if c in ['A'..'Z'] then Result := Chr(Ord(c) + 32) else Result := c;
end;

{ Split the trailing 'mask;save;blank' fields off, exactly where LCL's SplitEditMask finds
  them (maskedit.pp): the last two or four characters, and only when the ';' is not itself
  escaped. Anywhere else a ';' is an ordinary literal, in LCL and here. }
procedure SplitMaskFields(var AMask: string; out ABlank: Char; out AHasBlank: Boolean;
  out ASave: Boolean; out AHasSave: Boolean);
var
  L: Integer;
begin
  ABlank := #0;
  AHasBlank := False;
  ASave := False;
  AHasSave := False;
  L := Length(AMask);
  if (L >= 4) and (AMask[L - 1] = ';') and (AMask[L - 3] = ';') and
     (AMask[L - 2] <> '\') and ((L = 4) or (AMask[L - 4] <> '\')) then
  begin
    ABlank := AMask[L];
    AHasBlank := True;
    ASave := AMask[L - 2] <> '0';
    AHasSave := True;
    Delete(AMask, L - 3, 4);
  end
  else if (L >= 2) and (AMask[L - 1] = ';') and ((L = 2) or (AMask[L - 2] <> '\')) then
  begin
    ASave := AMask[L] <> '0';
    AHasSave := True;
    Delete(AMask, L - 1, 2);
  end;
end;

function TyMaskParse(const AMask: string): TTyMaskSpec;
var
  body: string;
  i, n: Integer;
  c: Char;
  inUp, inDown, special, anySlot: Boolean;
  hasSave: Boolean;

  procedure Add(AIsLiteral: Boolean; ALit: Char; AKind: TTyMaskKind; AReq: Boolean);
  begin
    if n = Length(Result.Cells) then
      SetLength(Result.Cells, n + 16);
    Result.Cells[n].IsLiteral := AIsLiteral;
    Result.Cells[n].Literal := ALit;
    Result.Cells[n].Kind := AKind;
    Result.Cells[n].Required := AReq;
    if inUp then Result.Cells[n].CaseMode := mcUpper
    else if inDown then Result.Cells[n].CaseMode := mcLower
    else Result.Cells[n].CaseMode := mcAsTyped;
    Inc(n);
  end;

  procedure Slot(AKind: TTyMaskKind; AReq: Boolean);
  begin
    Add(False, #0, AKind, AReq);
    anySlot := True;
  end;

begin
  Result.Cells := nil;
  Result.Blank := #0;
  Result.HasBlank := False;
  Result.SaveLiterals := False;
  Result.TrimLeft := False;
  Result.Reject := '';
  if AMask = '' then Exit;   // documented: no mask at all = plain edit

  body := AMask;
  SplitMaskFields(body, Result.Blank, Result.HasBlank, Result.SaveLiterals, hasSave);

  n := 0;
  inUp := False;
  inDown := False;
  special := False;
  anySlot := False;
  i := 1;
  while i <= Length(body) do
  begin
    c := body[i];
    if special then
    begin
      Add(True, c, mkDigit, False);
      special := False;
    end
    else
      case c of
        '\': special := True;
        '!': Result.TrimLeft := True;
        '>':
          { '<>' means "stop forcing"; a bare '>' starts an upper-case region. }
          if (i > 1) and (body[i - 1] = '<') then
          begin
            inUp := False;
            inDown := False;
          end
          else
          begin
            inUp := True;
            inDown := False;
          end;
        '<':
          begin
            inDown := True;
            inUp := False;
          end;
        '#':
          begin
            Result.Cells := nil;
            Result.Reject := Format('mask "%s" uses "#". In this control''s former ' +
              'three-code mask language "#" was a REQUIRED digit; in LCL/Delphi''s ' +
              'language, which this control now speaks, it is an OPTIONAL digit or sign. ' +
              'Reading it the new way would silently turn a required field into one that ' +
              'IsComplete and ValidateEdit pass while it is empty, so it is refused ' +
              'rather than reinterpreted. Write "0" for a required digit, "9" for an ' +
              'optional one, or "\#" for a literal "#".', [AMask]);
            Exit;
          end;
        '0': Slot(mkDigit,  True);
        '9': Slot(mkDigit,  False);
        'L': Slot(mkLetter, True);
        'l': Slot(mkLetter, False);
        'A': Slot(mkAlnum,  True);
        'a': Slot(mkAlnum,  False);
        'C': Slot(mkAny,    True);
        'c': Slot(mkAny,    False);
        'H': Slot(mkHex,    True);
        'h': Slot(mkHex,    False);
        'B': Slot(mkBin,    True);
        'b': Slot(mkBin,    False);
      else
        Add(True, c, mkDigit, False);
      end;
    Inc(i);
  end;
  SetLength(Result.Cells, n);

  if not anySlot then
  begin
    Result.Cells := nil;
    Result.Reject := Format('mask "%s" has no editable slot, so the field could never ' +
      'accept input. The slot codes are 0/9 (digit), L/l (letter), A/a (alphanumeric), ' +
      'C/c (any character), H/h (hex) and B/b (binary) -- upper case required, lower ' +
      'case optional. Use Mask := '''' for an unmasked edit.', [AMask]);
  end;
end;

function TyMaskRejectReason(const AMask: string): string;
begin
  Result := TyMaskParse(AMask).Reject;
end;

{ ------------------------------------------------------------------- reading one cell --- }

{ The case region converts BEFORE the range is tested, as LCL does (maskedit.pp
  CanInsertChar): '>L' takes a typed 'a' and stores 'A' rather than rejecting it. }
function CellCase(const ACell: TTyMaskCell; ACh: Char): Char;
begin
  case ACell.CaseMode of
    mcUpper: Result := UpCh(ACh);
    mcLower: Result := LoCh(ACh);
  else
    Result := ACh;
  end;
end;

function CellRangeOK(const ACell: TTyMaskCell; ACh: Char; ABlank: Char): Boolean;
begin
  if ACell.IsLiteral then Exit(False);
  { The placeholder is never CONTENT, whatever the slot would otherwise say about it --
    'C' takes any character, so without this line assigning a skeleton back into a 'C'
    mask would lay its own placeholders in as data. }
  if (ABlank <> #0) and (ACh = ABlank) then Exit(False);
  case ACell.Kind of
    mkDigit:  Result := ACh in ['0'..'9'];
    mkLetter: Result := ACh in ['A'..'Z', 'a'..'z'];
    mkAlnum:  Result := ACh in ['A'..'Z', 'a'..'z', '0'..'9'];
    mkHex:    Result := ACh in ['0'..'9', 'A'..'F', 'a'..'f'];
    mkBin:    Result := ACh in ['0', '1'];
    mkAny:    Result := ACh >= ' ';
  else
    Result := False;
  end;
end;

{ Case-convert ACh for the cell and report whether the cell then takes it. }
function CellTake(const ACell: TTyMaskCell; ACh: Char; ABlank: Char; out AOut: Char): Boolean;
begin
  AOut := CellCase(ACell, ACh);
  Result := CellRangeOK(ACell, AOut, ABlank);
end;

function CanonicalCode(const ACell: TTyMaskCell): Char;
begin
  case ACell.Kind of
    mkDigit:  if ACell.Required then Result := '0' else Result := '9';
    mkLetter: if ACell.Required then Result := 'L' else Result := 'l';
    mkAlnum:  if ACell.Required then Result := 'A' else Result := 'a';
    mkAny:    if ACell.Required then Result := 'C' else Result := 'c';
    mkHex:    if ACell.Required then Result := 'H' else Result := 'h';
    mkBin:    if ACell.Required then Result := 'B' else Result := 'b';
  else
    Result := #0;
  end;
end;

function TyMaskSlotAccepts(ASlot, ACh: Char; ABlank: Char = #0): Boolean;
var
  spec: TTyMaskSpec;
begin
  spec := TyMaskParse(ASlot);
  Result := (spec.Reject = '') and (Length(spec.Cells) = 1) and
            not spec.Cells[0].IsLiteral and
            CellRangeOK(spec.Cells[0], ACh, ABlank);
end;

{ ------------------------------------------------------------------- the pure engine --- }

function ApplySpec(const ASpec: TTyMaskSpec; const ARaw: string; ABlank: Char): string;
var
  i, ri: Integer;
  pending: string;
begin
  Result := '';
  pending := '';
  ri := 1;
  for i := 0 to High(ASpec.Cells) do
    if ASpec.Cells[i].IsLiteral then
      pending := pending + ASpec.Cells[i].Literal   // hold until the next slot is filled
    else
    begin
      if ri > Length(ARaw) then
      begin
        if ABlank = #0 then Break;   // short form: drop any pending trailing literal
        Result := Result + pending + ABlank;   // skeleton: the slot still shows
        pending := '';
        Continue;
      end;
      Result := Result + pending + ARaw[ri];
      pending := '';
      Inc(ri);
    end;
  { Skeleton only: a mask may end in literals with no slot after them ('00-' or '(000)').
    The short form deliberately drops those; the skeleton is the whole mask, so they belong. }
  if (ABlank <> #0) and (pending <> '') then
    Result := Result + pending;
end;

function TyMaskApply(const AMask, ARaw: string; ABlank: Char = #0): string;
begin
  Result := ApplySpec(TyMaskParse(AMask), ARaw, ABlank);
end;

function NormalizeSpec(const ASpec: TTyMaskSpec; const AText: string; ABlank: Char): string;
var
  i: Integer;
  o: Char;
begin
  Result := '';
  for i := 0 to High(ASpec.Cells) do
    if ASpec.Cells[i].IsLiteral then
      Result := Result + ASpec.Cells[i].Literal
    else if (i < Length(AText)) and
            CellTake(ASpec.Cells[i], AText[i + 1], ABlank, o) then
      Result := Result + o
    else
      Result := Result + ABlank;
end;

function TyMaskNormalize(const AMask, AText: string; ABlank: Char): string;
begin
  Result := NormalizeSpec(TyMaskParse(AMask), AText, ABlank);
end;

function ExtractSpec(const ASpec: TTyMaskSpec; const AText: string; ABlank: Char): string;
var
  i, ti: Integer;
begin
  Result := '';
  ti := 1;
  for i := 0 to High(ASpec.Cells) do
  begin
    if ti > Length(AText) then Break;
    if ASpec.Cells[i].IsLiteral then
    begin
      if AText[ti] <> ASpec.Cells[i].Literal then Break;   // misaligned: stop
      if ASpec.SaveLiterals then Result := Result + AText[ti];
      Inc(ti);
    end
    else
    begin
      { A blank is a slot nobody has filled, not a character of the value. In-place entry
        can leave one in the MIDDLE, so this skips rather than stops -- append-only entry
        could not, which is why this used to end the recovery at the first blank. }
      if (ABlank = #0) or (AText[ti] <> ABlank) then Result := Result + AText[ti];
      Inc(ti);
    end;
  end;
end;

function TyMaskExtract(const AMask, AText: string; ABlank: Char = #0): string;
begin
  Result := ExtractSpec(TyMaskParse(AMask), AText, ABlank);
end;

{ True when AText is EXACTLY what ASpec produces for the characters it carries.

  With a skeleton this is one line -- the shape is fixed-length, so "conforming" means
  "normalising changes nothing". Without one the display is a prefix, so the old
  short-form walk is still needed. Not the same question as ExtractSpec, which copies
  whatever sits at a slot POSITION without asking whether it belongs there -- that is why
  IsComplete used to answer True for '000-000' holding 'abc-def'. }
function ConformsSpec(const ASpec: TTyMaskSpec; const AText: string; ABlank: Char): Boolean;
var
  i, ti: Integer;
  raw: string;
  o: Char;
begin
  if ABlank <> #0 then
    Exit((Length(AText) = Length(ASpec.Cells)) and
         (NormalizeSpec(ASpec, AText, ABlank) = AText));
  raw := '';
  ti := 1;
  for i := 0 to High(ASpec.Cells) do
  begin
    if ti > Length(AText) then Break;
    if ASpec.Cells[i].IsLiteral then
    begin
      if AText[ti] <> ASpec.Cells[i].Literal then Exit(False);
      Inc(ti);
    end
    else
    begin
      if not CellTake(ASpec.Cells[i], AText[ti], ABlank, o) then Exit(False);
      if o <> AText[ti] then Exit(False);
      raw := raw + AText[ti];
      Inc(ti);
    end;
  end;
  { Nothing left over, and no dangling trailing literal ('12/' on '00/00' extracts to
    '12', which re-applies to '12' -- so '12/' is NOT conforming and gets normalised). }
  Result := (ti > Length(AText)) and (ApplySpec(ASpec, raw, ABlank) = AText);
end;

function TyMaskConforms(const AMask, AText: string; ABlank: Char = #0): Boolean;
begin
  Result := ConformsSpec(TyMaskParse(AMask), AText, ABlank);
end;

function NextSlotSpec(const ASpec: TTyMaskSpec; AFilledCount: Integer): Integer;
var
  i, cnt: Integer;
begin
  cnt := 0;
  for i := 0 to High(ASpec.Cells) do
    if not ASpec.Cells[i].IsLiteral then
    begin
      if cnt = AFilledCount then Exit(i);
      Inc(cnt);
    end;
  Result := -1;
end;

function TyMaskNextSlot(const AMask: string; AFilledCount: Integer): Char;
var
  spec: TTyMaskSpec;
  i: Integer;
begin
  spec := TyMaskParse(AMask);
  i := NextSlotSpec(spec, AFilledCount);
  if i < 0 then Result := #0 else Result := CanonicalCode(spec.Cells[i]);
end;

function CaretSlotSpec(const ASpec: TTyMaskSpec; AFilledCount: Integer): Integer;
var
  i: Integer;
begin
  i := NextSlotSpec(ASpec, AFilledCount);
  if i < 0 then
    Result := Length(ASpec.Cells)   // every slot filled: caret at the end of the display
  else
    Result := i;                    // caret sits BEFORE that slot
end;

function TyMaskCaretSlot(const AMask: string; AFilledCount: Integer): Integer;
begin
  Result := CaretSlotSpec(TyMaskParse(AMask), AFilledCount);
end;

function IsCompleteSpec(const ASpec: TTyMaskSpec; const AText: string; ABlank: Char): Boolean;
var
  i, ti: Integer;
  anySlot: Boolean;
  o: Char;
begin
  anySlot := False;
  ti := 1;
  for i := 0 to High(ASpec.Cells) do
  begin
    if ASpec.Cells[i].IsLiteral then
    begin
      if (ti > Length(AText)) or (AText[ti] <> ASpec.Cells[i].Literal) then Exit(False);
      Inc(ti);
    end
    else
    begin
      anySlot := True;
      if ASpec.Cells[i].Required then
      begin
        if ti > Length(AText) then Exit(False);
        if not CellTake(ASpec.Cells[i], AText[ti], ABlank, o) then Exit(False);
        if o <> AText[ti] then Exit(False);
      end;
      Inc(ti);
    end;
  end;
  Result := anySlot;
end;

function TyMaskIsComplete(const AMask, AText: string; ABlank: Char = #0): Boolean;
begin
  Result := IsCompleteSpec(TyMaskParse(AMask), AText, ABlank);
end;

function TyMaskCellCount(const AMask: string): Integer;
begin
  Result := Length(TyMaskParse(AMask).Cells);
end;

function IsLiteralAtSpec(const ASpec: TTyMaskSpec; AIndex: Integer): Boolean;
begin
  Result := (AIndex < 1) or (AIndex > Length(ASpec.Cells)) or
            ASpec.Cells[AIndex - 1].IsLiteral;
end;

function TyMaskIsLiteralAt(const AMask: string; AIndex: Integer): Boolean;
begin
  Result := IsLiteralAtSpec(TyMaskParse(AMask), AIndex);
end;

function NextEditableSpec(const ASpec: TTyMaskSpec; AFrom: Integer): Integer;
var
  i: Integer;
begin
  if AFrom < 1 then AFrom := 1;
  for i := AFrom to Length(ASpec.Cells) do
    if not ASpec.Cells[i - 1].IsLiteral then Exit(i);
  Result := 0;
end;

function TyMaskNextEditable(const AMask: string; AFrom: Integer): Integer;
begin
  Result := NextEditableSpec(TyMaskParse(AMask), AFrom);
end;

function PrevEditableSpec(const ASpec: TTyMaskSpec; ABefore: Integer): Integer;
var
  i: Integer;
begin
  if ABefore > Length(ASpec.Cells) then ABefore := Length(ASpec.Cells);
  for i := ABefore downto 1 do
    if not ASpec.Cells[i - 1].IsLiteral then Exit(i);
  Result := 0;
end;

function TyMaskPrevEditable(const AMask: string; ABefore: Integer): Integer;
begin
  Result := PrevEditableSpec(TyMaskParse(AMask), ABefore);
end;

{ The characters of AInput this mask will take, in order, when appended after the ARaw
  already laid down. Shared by paste-into-the-short-form and by `Text :=` so the two
  cannot disagree. }
function AcceptedFrom(const ASpec: TTyMaskSpec; const ARaw, AInput: string;
  ABlank: Char): string;
var
  i, si: Integer;
  o: Char;
begin
  Result := '';
  for i := 1 to Length(AInput) do
  begin
    si := NextSlotSpec(ASpec, Length(ARaw) + Length(Result));
    if si < 0 then Break;                  // every slot filled: ignore the rest
    if CellTake(ASpec.Cells[si], AInput[i], ABlank, o) then Result := Result + o;
  end;
end;

{ ---------------------------------------------------------------------- TTyMaskEdit --- }

constructor TTyMaskEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSpaceChar := TyMaskDefaultBlank;
  FValidationFailed := False;
  FTextOnEnter := '';
  FSpec := TyMaskParse('');
end;

function TTyMaskEdit.GetMaskSavesLiterals: Boolean;
begin
  Result := FSpec.SaveLiterals;
end;

function TTyMaskEdit.RawText: string;
begin
  Result := ExtractSpec(FSpec, Text, FSpaceChar);
end;

function TTyMaskEdit.InPlace: Boolean;
begin
  Result := (FMask <> '') and (FSpaceChar <> #0);
end;

function TTyMaskEdit.ShapedText: string;
begin
  Result := NormalizeSpec(FSpec, Text, FSpaceChar);
end;

procedure TTyMaskEdit.Commit(const AText: string; ACaret: Integer);
begin
  { Straight to the base writer on purpose: AText is already a display string this mask
    produced, so SetMaskedText would only re-derive it. AByCode=False because this IS the
    keystroke path -- this control rewrites its whole display string per accepted
    character, and the programmatic route would clear Modified on every one of them. }
  SetTextInternal(AText, False);
  CaretPos := ACaret;
end;

procedure TTyMaskEdit.BlankRange(var AText: string; AFrom, ATo: Integer);
var
  i: Integer;
begin
  if AFrom < 1 then AFrom := 1;
  if ATo > Length(AText) then ATo := Length(AText);
  for i := AFrom to ATo do
    if not IsLiteralAtSpec(FSpec, i) then AText[i] := FSpaceChar;
end;

procedure TTyMaskEdit.SetSpaceChar(const AValue: Char);
var
  s, raw: string;
  i, caret: Integer;
begin
  if FSpaceChar = AValue then Exit;
  if FMask = '' then
  begin
    FSpaceChar := AValue;
    Exit;
  end;
  if (FSpaceChar <> #0) and (AValue <> #0) then
  begin
    { Skeleton to skeleton: swap the placeholder in place. Re-deriving from the VALUE
      would pack the filled slots back to the left and lose every hole in-place editing
      had opened. }
    s := ShapedText;
    caret := CaretPos;
    for i := 1 to Length(s) do
      if (not IsLiteralAtSpec(FSpec, i)) and (s[i] = FSpaceChar) then s[i] := AValue;
    FSpaceChar := AValue;
    Commit(s, caret);
    Exit;
  end;
  raw := RawText;             // read the value under the OLD placeholder
  FSpaceChar := AValue;
  ApplyRaw(raw);              // and re-render it under the new one
end;

procedure TTyMaskEdit.SetMask(const AValue: string);
var
  spec: TTyMaskSpec;
begin
  if FMask = AValue then Exit;
  spec := TyMaskParse(AValue);
  if spec.Reject <> '' then raise ETyMaskError.Create('TTyMaskEdit.Mask: ' + spec.Reject);
  FMask := AValue;
  FSpec := spec;
  { A mask that spells its own blank character sets SpaceChar, as LCL does. A mask that
    does not spell one leaves it alone -- LCL resets it to '_' either way, which would
    silently undo SpaceChar := #0 on every change of mask. }
  if spec.HasBlank then FSpaceChar := spec.Blank;
  if csLoading in ComponentState then
    { Streaming order is fixed and against us: Text keeps the RTTI slot it inherited from
      TTyEdit, so the writer emits it BEFORE this descendant's Mask and the reader has
      already handed it over with no mask in force. Clearing here (below) threw away every
      value designed in the Object Inspector. Re-run it through the new mask instead. }
    SetMaskedText(Text)
  else
    Text := '';   // a new mask starts empty (predictable; masks are set before use)
end;

procedure TTyMaskEdit.ApplyRaw(const ARaw: string);
begin
  { Entry through the append path: the display is rebuilt from the accepted characters and
    the caret parks on the slot the next one will fill. That is NOT the end of the display
    string once a skeleton fills the box -- after '12' on '00/00/0000' the display runs to
    '____' and the caret belongs on the third slot, not past the eighth. }
  Commit(ApplySpec(FSpec, ARaw, FSpaceChar), CaretSlotSpec(FSpec, Length(ARaw)));
end;

procedure TTyMaskEdit.SetMaskedText(const AValue: TCaption);
var
  raw: string;
  i, caret: Integer;
begin
  if FMask = '' then
  begin
    inherited Text := AValue;   // no mask -> plain edit, byte-identical
    Exit;
  end;
  { An already-conforming value (our own display string, an .lfm value, a copy from a
    sibling edit) is kept verbatim. Re-filtering it is NOT a no-op: 'C' accepts any
    character, so on mask 'C-C' the filter eats the mask's own '-' as CONTENT and turns
    'a-b' into 'a--'. Without this branch `Ed.Text := Ed.Text` corrupts itself. }
  if ConformsSpec(FSpec, AValue, FSpaceChar) then
  begin
    inherited Text := AValue;
    { The base setter parks the caret at the end of the string it was handed, which with a
      skeleton in the box is the end of the PLACEHOLDERS -- an empty date field opened with
      the caret sitting after '____'. It belongs on the first slot still waiting. }
    caret := Length(AValue);
    if FSpaceChar <> #0 then
      for i := 1 to Length(AValue) do
        if (not IsLiteralAtSpec(FSpec, i)) and (AValue[i] = FSpaceChar) then
        begin
          caret := i - 1;
          Break;
        end;
    CaretPos := caret;
    Exit;
  end;
  raw := AcceptedFrom(FSpec, '', AValue, FSpaceChar);
  inherited Text := ApplySpec(FSpec, raw, FSpaceChar);
  CaretPos := CaretSlotSpec(FSpec, Length(raw));
end;

procedure TTyMaskEdit.TypeInPlace(ACh: Char);
var
  s: string;
  idx, nxt, ss, sl: Integer;
  o: Char;
begin
  s := ShapedText;
  ss := SelStart;
  sl := SelLength;
  if sl > 0 then BlankRange(s, ss + 1, ss + sl);
  idx := NextEditableSpec(FSpec, ss + 1);
  if (idx = 0) or not CellTake(FSpec.Cells[idx - 1], ACh, FSpaceChar, o) then
  begin
    { The key is refused, but a selection it was meant to replace has already been
      cleared -- LCL does the same (maskedit.pp InsertChar). Commit that much or the
      display and the model disagree. }
    if sl > 0 then Commit(s, ss);
    Exit;
  end;
  s[idx] := o;
  nxt := NextEditableSpec(FSpec, idx + 1);
  if nxt = 0 then nxt := Length(s) + 1;
  Commit(s, nxt - 1);
end;

procedure TTyMaskEdit.ErasePlace(AForward: Boolean);
var
  s: string;
  idx, ss, sl: Integer;
begin
  s := ShapedText;
  ss := SelStart;
  sl := SelLength;
  if sl > 0 then
  begin
    BlankRange(s, ss + 1, ss + sl);
    Commit(s, ss);
    Exit;
  end;
  if AForward then
    idx := NextEditableSpec(FSpec, CaretPos + 1)   // Delete: the slot AT the caret
  else
    idx := PrevEditableSpec(FSpec, CaretPos);      // Backspace: the slot BEFORE it
  if idx = 0 then Exit;
  s[idx] := FSpaceChar;
  Commit(s, idx - 1);
end;

function TTyMaskEdit.PasteInPlace(const AText: string): Boolean;
var
  s: string;
  i, idx, ss, sl: Integer;
  o: Char;
  wrote: Boolean;
begin
  s := ShapedText;
  ss := SelStart;
  sl := SelLength;
  if sl > 0 then BlankRange(s, ss + 1, ss + sl);
  idx := NextEditableSpec(FSpec, ss + 1);
  wrote := False;
  for i := 1 to Length(AText) do
  begin
    if idx = 0 then Break;                        // past the last slot: ignore the rest
    if AText[i] = FSpaceChar then Continue;       // a pasted placeholder is not content
    if CellTake(FSpec.Cells[idx - 1], AText[i], FSpaceChar, o) then
    begin
      { Literals in the pasted text are dropped rather than matched -- the mask re-inserts
        them itself, so pasting "2026-07-30" into '0000-00-00' lands the digits and
        rebuilds the dashes. }
      s[idx] := o;
      wrote := True;
      idx := NextEditableSpec(FSpec, idx + 1);
    end;
  end;
  Result := wrote or (sl > 0);
  if not Result then Exit;
  if idx = 0 then idx := Length(s) + 1;
  Commit(s, idx - 1);
end;

procedure TTyMaskEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  raw: string;
  c, o: Char;
  si: Integer;
begin
  if FMask = '' then
  begin
    inherited UTF8KeyPress(UTF8Key);   // no mask -> behave as a plain edit
    Exit;
  end;
  { The base class reaches ReadOnly and Enabled through InjectKey, which this override
    does not call -- so a read-only masked field took dictation. }
  if Enabled and not ReadOnly and (Length(UTF8Key) = 1) then
  begin
    c := UTF8Key[1];
    if InPlace then
      TypeInPlace(c)
    else
    begin
      raw := RawText;
      si := NextSlotSpec(FSpec, Length(raw));
      if (si >= 0) and CellTake(FSpec.Cells[si], c, FSpaceChar, o) then ApplyRaw(raw + o);
    end;
  end;
  UTF8Key := '';   // always swallow: we manage Text ourselves (also rejects multibyte)
end;

procedure TTyMaskEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if FMask <> '' then
  begin
    { Cut and paste are intercepted HERE rather than left to TTyEdit. Both splice the
      display string directly (TTyEdit.DeleteSelection / InjectStringAt), and a splice
      shortens it -- which slides every character past the cut into a cell that means
      something else. Neither routine is virtual, so this is the last point at which the
      mask can still see the operation whole.

      Only while a skeleton is in force: everything positional starts from a full-length
      display string, and without a placeholder there is no such string to start from.
      The short form keeps the paths it always had (FilterInsert for paste, the base class
      for cut). }
    if InPlace and (Key = VK_V) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
    begin
      if not ReadOnly then PasteInPlace(ReadClipboardText);
      Key := 0;
      Exit;
    end;
    if InPlace and (Key = VK_X) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
    begin
      if HasSelection then
      begin
        CopyToClipboard;
        if not ReadOnly then ErasePlace(False);
      end;
      Key := 0;
      Exit;
    end;
    if (Shift = []) and ((Key = VK_BACK) or (Key = VK_DELETE)) then
    begin
      { Delete used to fall through to the plain edit, which removes the character at the
        caret -- including a mask LITERAL, leaving Text no longer conforming to the mask
        the control claims to enforce. }
      if Key = VK_BACK then InjectBackspace else InjectDelete;
      Key := 0;
      Exit;
    end;
  end;
  inherited KeyDown(Key, Shift);
end;

function TTyMaskEdit.FilterInsert(const AText: string): string;
var
  raw, keep: string;
begin
  if FMask = '' then Exit(inherited FilterInsert(AText));   // plain edit, unchanged
  if InPlace then
    PasteInPlace(AText)
  else
  begin
    { Append-only: an insertion is judged the same way a keystroke is -- feed the incoming
      chars through the next free slot in turn and keep the ones it accepts (the same rule
      `Text :=` uses, so paste and assignment cannot drift apart). }
    raw := RawText;
    keep := AcceptedFrom(FSpec, raw, AText, FSpaceChar);
    if keep <> '' then ApplyRaw(raw + keep);
  end;
  { The display has already been rewritten through the mask, so there is nothing left for
    the base insert to do -- '' is InjectStringAt's documented "insert nothing". }
  Result := '';
end;

procedure TTyMaskEdit.InjectBackspace;
var
  raw: string;
begin
  if FMask = '' then
  begin
    inherited InjectBackspace;   // no mask -> plain edit, unchanged
    Exit;
  end;
  if ReadOnly then Exit;
  if InPlace then
  begin
    ErasePlace(False);
    Exit;
  end;
  raw := RawText;
  if raw = '' then Exit;
  Delete(raw, Length(raw), 1);
  ApplyRaw(raw);
end;

procedure TTyMaskEdit.InjectDelete;
begin
  if FMask = '' then
  begin
    inherited InjectDelete;
    Exit;
  end;
  if ReadOnly then Exit;
  if InPlace then
    ErasePlace(True)
  else
    { The short form has no mid-text hole, so there Delete still means what Backspace
      means: drop the last significant character. }
    InjectBackspace;
end;

function TTyMaskEdit.IsComplete: Boolean;
begin
  Result := IsCompleteSpec(FSpec, Text, FSpaceChar);
end;

function TTyMaskEdit.MaskedValue: string;
begin
  Result := RawText;
end;

procedure TTyMaskEdit.ValidateEdit;
begin
  if FMask = '' then Exit;          // nothing to validate against
  if IsComplete then Exit;
  raise ETyMaskError.CreateFmt('TTyMaskEdit: "%s" does not fill the mask "%s".',
    [Text, FMask]);
end;

procedure TTyMaskEdit.DoEnter;
begin
  inherited DoEnter;
  FTextOnEnter := Text;             // the baseline the exit check compares against
  FValidationFailed := False;
end;

procedure TTyMaskEdit.DoExit;
begin
  { OnExit gets its chance FIRST, exactly as in LCL -- a handler that completes or clears the
    value must be able to do so before anything is raised. }
  inherited DoExit;
  if (FMask = '') or FValidationFailed then Exit;
  if FTextOnEnter = Text then Exit; // untouched: tabbing through is not an error
  try
    ValidateEdit;
  except
    { Latch BEFORE re-raising: the exception travels out through the focus change, and a
      second one raised while this is still unwound aborts the application instead of
      reporting anything. Cleared on the next DoEnter. }
    FValidationFailed := True;
    raise;
  end;
end;

end.
