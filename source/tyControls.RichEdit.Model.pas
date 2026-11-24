unit tyControls.RichEdit.Model;

{ The document model under TTyRichEdit: character and paragraph formats (values, interned in
  a pool so equal formats share an id), paragraphs made of runs, embedded objects, tables, and
  TTyRichDocument, which owns the text storage (tyControls.RichEdit.Text) and hangs each
  paragraph's formatting on the paragraph's data slot there.

  Paragraph data is an immutable, reference-counted value. A change never edits it in place:
  it builds a new value and puts that in the slot. So whoever holds an old value - an undo
  record, or a piece snapshot the text took before a delete - can put it back later, any
  number of undo/redo cycles on, and gets exactly the old runs, formats and objects. A slot
  holds one reference; the text reports what a merge drops, and the document lets go of it.

  A paragraph whose slot is nil costs nothing: it is plain, in the document's default formats.
  When a loader is installed (the on-demand RTF reader), nil means "not parsed yet" instead,
  and every reader goes through EnsureParsed, which asks the loader for that paragraph.

  The only public way to change a document is a command: TTyRichDocument.Execute runs it and
  keeps it in the document's undo history. The primitives commands are built from are
  protected here; each returns a TTyRichUndoData that Revert puts back exactly. TTyRichCommand
  hands them on to its subclasses (built-in ones in tyControls.RichEdit.Commands, or a
  program's own), only while the document is running that command, and keeps what they
  return, so undo is the records reverted newest first and redo is the command run again. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Graphics, LCLType, Generics.Collections, tyControls.RichEdit.Text,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.TableProps;

const
  { Insert without a format: the text takes the format of the character before it in the same
    paragraph, or of the character after it at the paragraph's start (as WordPad does). }
  TyRichInheritFormat = -1;

type
  ETyRichModel = class(Exception);
  { The document refused a change and changed nothing (a command reverted what it had done):
    FixedRow - a row that holds a nested table was in the way (TTyRichRow.HoldsNestedTable),
    else the range could not be changed for another reason (a command's CanExecute). }
  ETyRichRefused = class(ETyRichModel)
  public
    FixedRow: Boolean;
    { A field's result was in the way (TTyRichFieldMark): a change inside it, or one that
      would take one of its marks without the other. }
    Field: Boolean;
  end;

  { Why the text cannot change at a place (TTyRichDocument.ChangeRefusal): rcrFixedRow, a row
    that holds a nested table is kept as the file has it; rcrField, a field's result is
    read-only (a change inside it, or one that takes one of its marks and not the other). }
  TTyRichChangeRefusal = (rcrNone, rcrFixedRow, rcrField);

  TTyCharFormatId = Integer;
  TTyParaFormatId = Integer;

  { Unknown RTF attributes, kept as the raw fragments they were read as, in order, so a writer
    can put them back byte for byte. Two formats that differ only here are two formats. Empty,
    the usual case, is one nil pointer. }
  TTyOpaqueAttrs = record
  private
    FItems: array of RawByteString;
  public
    function Count: Integer;
    function Item(AIndex: Integer): RawByteString;
    procedure Add(const AFragment: RawByteString);
    procedure Clear;
    function Equals(const B: TTyOpaqueAttrs): Boolean;
    function Hash: Cardinal;
  end;

  TTyVertAlign = (vaNone, vaSuper, vaSub);

  { FontName '' and SizeHalfPt 0 mean "the control's theme font / size"; Color clDefault means
    the theme's text colour, HighlightColor clNone no highlight. Style holds bold, italic and
    underline; strike-through is Strike (the pool moves an fsStrikeOut in Style there). }
  TTyCharFormat = record
    FontName: string;
    Charset: Integer;
    SizeHalfPt: Integer;
    Style: TFontStyles;
    Strike: Boolean;
    VertAlign: TTyVertAlign;
    Color: TColor;
    HighlightColor: TColor;
    Extra: TTyOpaqueAttrs;
    function Equals(const B: TTyCharFormat): Boolean;
    function Hash: Cardinal;
  end;

  TTyCharFormatField = (cffFontName, cffCharset, cffSize, cffBold, cffItalic, cffUnderline,
    cffStrike, cffVertAlign, cffColor, cffHighlight, cffExtra);
  TTyCharFormatMask = set of TTyCharFormatField;

  { paraLeft..paraJustify, not paLeft..: Menus.TPopupAlignment already has paLeft,
    paCenter and paRight, and the control units use Menus. }
  TTyParaAlign = (paraLeft, paraCenter, paraRight, paraJustify);
  { lsMultiple: any other multiple, LineSpacingValue / 240 times the line's own height (a
    file's \slN\slmult1: Word's 1.08 is 259) - the four named ones are never written so
    (TyRichSetLineMultiple), so equal spacings are equal formats. Last, so that the ordinals
    of the others, which a form streams, stay. }
  TTyLineSpacing = (lsSingle, ls115, ls15, lsDouble, lsExact, lsAtLeast, lsMultiple);
  TTyTabAlign = (ttaLeft, ttaCenter, ttaRight, ttaDecimal);
  TTyTabLeader = (ttlNone, ttlDot, ttlHyphen, ttlUnderline, ttlThick, ttlEqual);

  TTyTabStop = record
    Position: Integer;      // twips from the left indent's origin (RTF \tx)
    Align: TTyTabAlign;
    Leader: TTyTabLeader;
  end;
  TTyTabStops = array of TTyTabStop;

  TTyListKind = (lkNone, lkBullet, lkDecimal, lkLowerAlpha, lkUpperAlpha, lkLowerRoman,
    lkUpperRoman);

  TTyListFormat = record
    Kind: TTyListKind;
    Level: Integer;
    { The number an item given a start begins a new list at (whatever stands before it);
      0: no start given - the item goes on from the item before it on its level (a first
      item, after a shallower item or a paragraph that is no item, at 1). A bullet: 0. }
    StartAt: Integer;
    { A bullet's own text in place of the round bullet ('' for that one); nothing for a
      numbered kind. One nil pointer when empty. }
    Bullet: UTF8String;
  end;

  TTyParaFormat = record
    Align: TTyParaAlign;
    LeftIndent: Integer;    // twips
    RightIndent: Integer;
    FirstIndent: Integer;
    SpaceBefore: Integer;
    SpaceAfter: Integer;
    LineSpacing: TTyLineSpacing;
    { twips, for lsExact and lsAtLeast; 240ths of the line's own height for lsMultiple }
    LineSpacingValue: Integer;
    Tabs: TTyTabStops;
    List: TTyListFormat;
    RtlPar: Boolean;        // kept and written back, not rendered (no bidirectional layout)
    { The paragraph's own ground (RTF \cbpat, with \cfpat and \shading mixed in), a colour of
      the document's: clNone for none. }
    Shading: TColor;
    Extra: TTyOpaqueAttrs;
    function Equals(const B: TTyParaFormat): Boolean;
    function Hash: Cardinal;
  end;

  { The fields of a paragraph format a write sets (TyMergeParaFormat). The last five set no
    field of their own: they move one indent meaning per paragraph and keep another, each
    paragraph from its own values - LeftIndent is where the lines after the first
    start, LeftIndent + FirstIndent where the first line starts; AValue gives them in those
    terms:
    pffStartIndent  the first line at AValue.LeftIndent + AValue.FirstIndent, the other lines
                    keeping their offset from it (the paragraph moves: Delphi's FirstIndent);
    pffOffset       the first line's offset from the other lines becomes AValue.FirstIndent,
                    the first line staying where it is (Delphi's LeftIndent);
    pffFirstLine    the first line at AValue.LeftIndent + AValue.FirstIndent, the other lines
                    staying (RichMemo's FirstLine);
    pffHeadIndent   the other lines at AValue.LeftIndent, the first line staying (RichMemo's
                    HeadIndent);
    pffListIndents  with pffList (or pffListKind): a paragraph that becomes a list item and has no indent
                    (both 0) takes AValue's LeftIndent and FirstIndent - the default hanging
                    indent; one that stops being a list item gets both back to 0 (Windows' rich
                    edit's and WordPad's rule); others keep theirs.
    They are applied after the absolute fields, in this order. Four more set one part of a
    record each paragraph keeps the rest of, applied with the absolute fields:
    pffListKind     the list kind (lkNone: the list record at its default; another kind:
                    the paragraph's own start, which may be none - it goes on);
    pffListStart    the list's start number, the kind staying (0: it goes on);
    pffListRestart  with pffListStart, for a command over paragraphs (TTyRichSetParaFormat):
                    the first list item among them gets AValue's start, the others go on
                    (0) - a start given to a selection begins one list there;
    pffSpacingRule  the line spacing rule; a height stays where the rule is exactly or at
                    least (a paragraph without one takes AValue's), else it is 0;
    pffSpacingHeight the height (LineSpacingValue), the rule staying where it is exactly or
                    at least, else at least (Word's way).
    Three more set a field or a part of the list record alone: pffShading (Shading),
    pffListLevel (List.Level, the kind and the rest staying), pffListBullet (List.Bullet). }
  TTyParaFormatField = (pffAlign, pffLeftIndent, pffRightIndent, pffFirstIndent,
    pffSpaceBefore, pffSpaceAfter, pffLineSpacing, pffTabs, pffList, pffRtlPar, pffExtra,
    pffStartIndent, pffOffset, pffFirstLine, pffHeadIndent, pffListIndents,
    pffListKind, pffListStart, pffSpacingRule, pffSpacingHeight, pffShading, pffListLevel,
    pffListBullet, pffListRestart);
  TTyParaFormatMask = set of TTyParaFormatField;

  { Equal formats get the same id; ids are never reused, so an id an undo record keeps stays
    valid. }
  TTyFormatPool = class
  private
    FChars: array of TTyCharFormat;
    FCharHash: array of Cardinal;
    FCharNext: array of Integer;
    FCharBucket: array of Integer;
    FCharCount: Integer;
    FParas: array of TTyParaFormat;
    FParaHash: array of Cardinal;
    FParaNext: array of Integer;
    FParaBucket: array of Integer;
    FParaCount: Integer;
    procedure RehashChars;
    procedure RehashParas;
  public
    function InternChar(const F: TTyCharFormat): TTyCharFormatId;
    function InternPara(const F: TTyParaFormat): TTyParaFormatId;
    function CharFormat(AId: TTyCharFormatId): TTyCharFormat;
    function ParaFormat(AId: TTyParaFormatId): TTyParaFormat;
    property CharCount: Integer read FCharCount;
    property ParaCount: Integer read FParaCount;
  end;

  { AddRef/Release: freed when the count falls back to 0. The document holds one reference per
    paragraph value that uses it; a command that must re-attach it on redo holds its own. One
    that was never attached and never AddRef'd belongs to whoever created it. }
  { (A TPersistent: an object can be handed to what takes a persistent - a picture to a
    TPicture's Assign.) }
  TTyRichRefCounted = class(TPersistent)
  private
    FRefCount: Integer;
  public
    procedure AddRef;
    procedure Release;
    property RefCount: Integer read FRefCount;
  end;

  { An embedded object: one U+FFFC character in the text; the object rides on the paragraph's
    run list. Immutable once created - an undo record may still show the old one, so a change
    (a resized picture) is a new object (Clone and change). }
  TTyRichObject = class(TTyRichRefCounted)
  private
    FRawUc: Integer;
  public
    constructor Create;
    function Clone: TTyRichObject; virtual; abstract;
    { The bytes its data takes (an image, kept RTF): what a history step that keeps it alive
      counts toward the history's memory limit (TTyRichDocument.MaxUndoBytes). }
    function DataBytes: Int64; virtual;
    { The part of DataBytes that other objects may share with it - a resized picture shares
      its image's bytes with the picture it was made from: the block's identity (nil: none)
      and its size. The history counts a block once however many objects it holds share it. }
    function SharedData(out ABytes: Int64): Pointer; virtual;
    { Its display size in twips, when it has one of its own (a picture); False by default. }
    function DisplaySize(out AWidthTwips, AHeightTwips: Integer): Boolean; virtual;
    { It can be shown at another size: Resized makes the object that is. False by default (a
      block of RTF kept as it was read). A class of an application's answers for itself. }
    function CanResize: Boolean; virtual;
    { A new object of the same class (one no reference was taken of) like this one but shown
      AWidthTwips x AHeightTwips; nil when it cannot be resized. This one stays as it is -
      objects are immutable, an undo puts it back. }
    function Resized(AWidthTwips, AHeightTwips: Integer): TTyRichObject; virtual;
    { For an object that keeps RTF bytes as they were read (TTyRichOpaque.Bytes,
      TTyRichPicture.RawRtf): the \ucN in effect where they were read - how many fallback
      bytes follow each \uN in them, which the bytes themselves do not say. A writer puts
      them back under that \uc. 1 (RTF's default) for an object made here. }
    property RawUc: Integer read FRawUc;
  end;

  TTyRichPictureFormat = (rpfUnknown, rpfPng, rpfJpeg, rpfBmp, rpfDib, rpfEmf, rpfWmf);

  { A picture: an image file's bytes (MakeImageData) shown at a display size. One read from a
    file the document keeps (its load holds the file's bytes for the paragraphs nobody
    changed) does not convert or copy anything when its paragraph is parsed: it holds a
    reference to that buffer, where its image's bytes are in it (hex digits, or \bin's bytes)
    and where its group is (RawRtf) - so parsing a paragraph with a picture costs what finding
    the group's end costs, whatever the picture's size, and the buffer lives as long as one
    such picture does (TTyRichFieldMark.CreateInFile is the same). Its bytes are made where
    they are needed, by MakeImageData, each time it is called: the layout's decode makes them
    once a decode (a step of the control's idle work, on the user-interface thread: the
    conversion is part of that step), a writer of a resized picture once a save; a writer
    writes its group where it is. They are not kept: kept, they would be memory that comes
    and goes with no command (the history counts what an object holds by DataBytes, which
    must not change while it lives). A clone, and what goes to another document, owns its
    bytes. }
  TTyRichPicture = class(TTyRichObject)
  private
    FFormat: TTyRichPictureFormat;
    FData: TBytes;
    FWidthTwips: Integer;
    FHeightTwips: Integer;
    FRawRtf: RawByteString;
    FShown: Byte;      // 0 not worked out yet, 1 shown, 2 a placeholder
    FShowFormat: TTyRichPictureFormat;
    FShowStart, FShowCount: Integer;
    // in a file's bytes (CreateInFile): the file, its image's bytes, its group (length 0: none)
    FFile: TBytes;
    FFileData, FFileDataLen: Int64;
    FFileBin: Boolean;
    FFileRaw, FFileRawLen: Int64;
    function GetRawRtf: RawByteString;
    // FShown and the rest, from the image's bytes themselves
    procedure ShowFrom(const AData: TBytes);
  public
    constructor Create(AFormat: TTyRichPictureFormat; const AData: TBytes;
      AWidthTwips, AHeightTwips: Integer; const ARawRtf: RawByteString = '';
      ARawUc: Integer = 1);
    { A picture whose image's bytes are ADataLen bytes of AFile from ADataAt - hex digits, as
      a reader takes them (anything else among them passed over, a lone digit at the end
      dropped), or with ABin those very bytes - and whose group is ARawLen bytes from ARawAt
      (0: none). A reference to AFile is kept; nothing is copied or converted. }
    constructor CreateInFile(AFormat: TTyRichPictureFormat; const AFile: TBytes;
      ADataAt, ADataLen: Int64; ABin: Boolean; AWidthTwips, AHeightTwips: Integer;
      ARawAt, ARawLen: Int64; ARawUc: Integer = 1);
    // Its own bytes and group, the file's made into its own (what leaves the document).
    function Clone: TTyRichObject; override;
    // its bytes are a range of its file's (CreateInFile), not its own
    function InFile: Boolean;
    { Where its image's bytes are - its own block, or the place in its file's bytes - nil for
      none: two pictures of the same identity and format show the same (a resized one, one
      parsed again). Meaningful only while the picture lives: a freed block's address may be
      another's later. }
    function DataIdentity: Pointer;
    { Its group where it is: RawRtfLength bytes from RawRtfData, valid while it lives (a
      writer reads them in place). }
    function RawRtfData: PByte;
    function RawRtfLength: Int64;
    { False only where DisplayData is False, answered without reading its bytes for one whose
      bytes are its file's and whose answer is not known yet (beyond the first two digits; a
      metafile then may show) - what a paint asks, before the decode in an idle step (on the
      user-interface thread) finds out. }
    function MayShow: Boolean;
    { The image file's bytes - made from its file's bytes each time it is called (a new array
      each time: call it once and keep what it gives, never in a loop over the bytes); for a
      picture that owns them, its very bytes, not a copy. Do not change them. }
    function MakeImageData: TBytes; virtual;
    { How many bytes MakeImageData gives, without making them: for hex digits of a file a
      count of the digits (a look at each, no array). }
    function ImageDataLength: Int64; virtual;
    { DisplayData and the bytes it speaks of, made once: what a decode for display asks
      (the answer worked out from the made bytes - nothing is counted or made twice). False:
      nothing can be shown, AData nil. }
    function DisplayBytes(out AFormat: TTyRichPictureFormat; out AStart, ACount: Integer;
      out AData: TBytes): Boolean;
    { The picture as an image at its own size in pixels (not the size it is shown at) into a
      TPicture or a TBitmap: TPicture.Assign(APicture) and TBitmap.Assign(APicture) come here.
      PNG, JPEG, a bitmap and a metafile whose drawing is one bitmap (that bitmap); what the
      control draws as a placeholder - any other metafile, an unknown or empty picture -
      raises EInvalidGraphic (rsRichPictureNotShown). Its image's bytes are made for the call
      (MakeImageData, once) and not kept. Any other Dest: as TPersistent (EConvertError). }
    procedure AssignTo(Dest: TPersistent); override;
    { The image file's own bytes (MakeImageData) written to AStream: a PNG, a JPEG, a bitmap,
      a metafile as the document holds it. }
    procedure SaveImageToStream(AStream: TStream);
    function DataBytes: Int64; override;
    // its own bytes: a resized picture shares them
    function SharedData(out ABytes: Int64): Pointer; override;
    function DisplaySize(out AWidthTwips, AHeightTwips: Integer): Boolean; override;
    { True: a picture can be shown at any size - also one shown as a placeholder (a metafile
      nothing here draws). }
    function CanResize: Boolean; override;
    { The same format and the very same bytes (shared, not copied), the new display size, and no
      RawRtf: a writer writes it from the model at its new size - what the file's group said
      besides the picture (scaling words, cropping, other representations of it) is not kept.
      Made by the class reference, so a subclass's object is of its class; a subclass with
      fields of its own overrides this to copy them. }
    function Resized(AWidthTwips, AHeightTwips: Integer): TTyRichObject; override;
    { What an image decoder can show of this picture: the format to decode as and the part of
      its image's bytes (MakeImageData) to hand it, [AStart, AStart + ACount). PNG, JPEG, BMP
      and DIB pictures are their data; a metafile whose whole drawing is one bitmap is that
      bitmap (rpfDib, the BITMAPINFO inside the metafile). False for any other metafile, and
      for an unknown or empty picture: the layout draws a placeholder. Worked out once; for a
      picture of its file's bytes that counts the hex digits, and walks a metafile in a copy
      made for that only (a decode asks DisplayBytes, which does neither). PictureFormat and
      the bytes stay what the file had (writing is unchanged). }
    function DisplayData(out AFormat: TTyRichPictureFormat; out AStart, ACount: Integer): Boolean;
    property PictureFormat: TTyRichPictureFormat read FFormat;
    property WidthTwips: Integer read FWidthTwips;  // display size
    property HeightTwips: Integer read FHeightTwips;
    { The {\pict ...} group as read, '' if new - a copy, for a picture whose bytes are its
      file's (RawRtfData reads it in place). }
    property RawRtf: RawByteString read GetRawRtf;
  end;

  { The picture a block of kept RTF carries inside its own bytes for readers that cannot draw
    the block itself (TTyRichOpaque.DisplayPicture): what the layout shows for the block. It is
    never in a document - the block is - and has no bytes of its own: the image file's bytes
    are [DataStart, DataStart + DataLength) of Source, the block's own bytes (the same string,
    not a copy), written there as hex digits or, with Hex False, as \bin's bytes;
    MakeImageData decodes them, each time it is called. DisplayData answers in the decoded bytes, PictureFormat and
    the display size are those of the block's \pict group. It cannot be resized: the block it shows is
    one object of bytes no one rewrites. }
  TTyRichKeptPicture = class(TTyRichPicture)
  private
    FSource: RawByteString;
    FDataAt, FDataLen: Integer;
    FHex: Boolean;
  public
    function Clone: TTyRichObject; override;
    function DataBytes: Int64; override;
    // the block's bytes it holds: what a cache that keeps it keeps alive
    function SharedData(out ABytes: Int64): Pointer; override;
    function CanResize: Boolean; override;
    function Resized(AWidthTwips, AHeightTwips: Integer): TTyRichObject; override;
    { The image file's bytes, decoded from Source as a reader decodes a picture's (a lone hex
      digit at the end is dropped). }
    function MakeImageData: TBytes; override;
    function ImageDataLength: Int64; override;
    property Source: RawByteString read FSource;
    property DataStart: Integer read FDataAt;      // 0-based, in Source
    property DataLength: Integer read FDataLen;
    property Hex: Boolean read FHex;
  end;

  // An RTF group this model does not understand ({\*\...}, fields, equations, ...), kept as
  // its bytes.
  TTyRichOpaque = class(TTyRichObject)
  private
    FBytes: RawByteString;
    FDisplayText: UTF8String;
    FPicture: TTyRichKeptPicture;
    FPictureSought: Boolean;
  public
    constructor Create(const ABytes: RawByteString; const ADisplayText: UTF8String = '';
      ARawUc: Integer = 1);
    destructor Destroy; override;
    function Clone: TTyRichObject; override;
    function DataBytes: Int64; override;
    { The picture the block's own bytes carry for readers that cannot draw it, when the layout
      can show it, the first of its pictures the layout can draw: an equation's (\mmath: the
      pictures of its \mmathPict), an embedded object's (\object: those of its \result) or a
      shape's (\shp: those of its \shprslt in order, then that of its pib property - Word keeps
      a metafile in the result of a floating image and the image itself in pib). A picture is
      a \pict group, also one inside Word's \*\shppict and \nonshppict groups. nil for any
      other block, for one with display text, and for one none of whose pictures can be drawn
      (a metafile that is not one bitmap, an unknown format, no image bytes, a group cut off
      by the end of the file). Looked for the first time it is asked - the layout asks when it
      first measures the block - and never again; nothing of the bytes is copied. }
    function DisplayPicture: TTyRichKeptPicture;
    { The picture it shows (DisplayPicture) handed over as TTyRichPicture.AssignTo does; a
      block that shows none: as TPersistent (EConvertError). }
    procedure AssignTo(Dest: TPersistent); override;
    property Bytes: RawByteString read FBytes;
    // what stands for it on screen, as plain text: a field's result ('' for most blocks)
    property DisplayText: UTF8String read FDisplayText;
  end;

  TTyRichBookmarkKind = (rbmStart, rbmEnd);

  { Counts by a bookmark name's hash (TyRichBookmarkHash), for the work over a file's many
    bookmarks: an open table - a key's slot from its own bits, the next free one after it -
    much quicker than a dictionary for hundreds of thousands of names. }
  TTyRichHashCounts = class
  private
    FKeys: array of Cardinal;
    FVals: array of Int64;
    FUsed: array of Boolean;
    FMask: Integer;
    FCount: Integer;
    function Slot(AKey: Cardinal): Integer;
    procedure Grow;
  public
    // room for about ACapacity keys before it grows
    constructor Create(ACapacity: Integer = 16);
    // AKey's value AValue more (0 when it was not there); the value now
    function Add(AKey: Cardinal; AValue: Int64): Int64;
    function TryGet(AKey: Cardinal; out AValue: Int64): Boolean;
    property Count: Integer read FCount;
  end;

  { One end of a bookmark: its start or its end, by name. A kept block with no width and
    nothing to show, as before it had a class of its own - so the caret, the keys, the layout
    and a writer treat it as they treat such a block (no width, never a key's step, its bytes
    written as they are). One read from a file keeps the file's group ({\*\bkmkstart name}) and
    is written so, byte for byte; one made here (CreateNew) is given Word's syntax, its name
    written as text is (\uN for what is not ASCII). Name is the name decoded as the reader
    decodes text. Names compare without regard to case (TyRichSameBookmarkName), as Word's. }
  TTyRichBookmarkMark = class(TTyRichOpaque)
  private
    FKind: TTyRichBookmarkKind;
    FName: UTF8String;
    FMade: Boolean;
  public
    { Read from a file: ABytes its group as the file has it, under \uc ARawUc. }
    constructor Create(AKind: TTyRichBookmarkKind; const AName: UTF8String;
      const ABytes: RawByteString; ARawUc: Integer = 1);
    { Made here: its bytes are Word's syntax for AName. }
    constructor CreateNew(AKind: TTyRichBookmarkKind; const AName: UTF8String);
    function Clone: TTyRichObject; override;
    function DataBytes: Int64; override;
    property Kind: TTyRichBookmarkKind read FKind;
    property Name: UTF8String read FName;
    { Made here (CreateNew): a writer writes it as Word writes a bookmark - its name in the
      file's code page where every character has bytes there, Bytes (\uN) otherwise. One
      read from a file is written as its Bytes. }
    property Made: Boolean read FMade;
  end;

  TTyRichFieldMarkKind = (rfmOpen, rfmClose);

  { One edge of a field whose stored result is shown as the document's own content (a
    hyperlink, a page number, a table of contents read from RTF): the open mark stands before
    the result, the close mark after it, and the result between them is ordinary text,
    paragraphs, pictures - and the marks of fields nested in it. The open mark keeps the whole
    field group's bytes as the file has them (and the \uc they were read under): while both
    marks of a pair are in the document, a writer writes those bytes and nothing of what lies
    between the marks, so a field nobody could change goes out as it came in. The result is
    read-only: the document refuses every change between the two marks, and every change
    that would take one mark without the other (TTyRichDocument.ChangeRefusal).
    Not a TTyRichOpaque: no code that treats a kept block takes a mark for one. It has no
    width and is never drawn. Id pairs the two marks of a field: the byte offset of the
    field's group in its file, or a number below zero for marks made elsewhere (NewId); the
    pairs themselves go by nesting order, as the marks stand in the text.
    An open mark read from a file the document keeps (its load holds the file's bytes for the
    paragraphs nobody changed) does not copy its group: it holds a reference to that buffer
    and where its group is in it - a field around most of a large file, and the fields nested
    in it, cost nothing more for their bytes, and the buffer lives as long as one of them
    does. A mark made otherwise, and a clone (what a copy, the clipboard and another document
    get), owns its bytes. }
  TTyRichFieldMark = class(TTyRichObject)
  private
    FKind: TTyRichFieldMarkKind;
    FId: Int64;
    FBytes: RawByteString;
    FFile: TBytes;
    FFileStart, FFileLen: Int64;
    FSlotNames: array[0..2] of UTF8String;
    FSlotCharsets: array[0..2] of Integer;
    FSlot: Byte;
    FOwned: Boolean;
    FInstruction: UTF8String;
    FFlags: Byte;
    function GetBytes: RawByteString;
  public
    { ABytes and ARawUc: the open mark's (a close mark keeps none). }
    constructor Create(AKind: TTyRichFieldMarkKind; AId: Int64;
      const ABytes: RawByteString = ''; ARawUc: Integer = 1);
    { An open mark whose group is ALen bytes of AFile from AStart: a reference to AFile is
      kept, nothing copied. }
    constructor CreateInFile(AId: Int64; const AFile: TBytes; AStart, ALen: Int64;
      ARawUc: Integer = 1);
    { A mark of a field the model owns: one that came from elsewhere (a paste, a drop) whose
      file bytes could not be right here. It keeps no bytes - the open mark the instruction's
      text (decoded) and the field's own state words (AFlags: CTyRichFieldDirty ...) - and the
      writer builds the field's group around its content, written from the model. A close
      mark of such a field is owned too. }
    constructor CreateOwned(AKind: TTyRichFieldMarkKind; AId: Int64;
      const AInstruction: UTF8String = ''; AFlags: Byte = 0);
    destructor Destroy; override;
    { How many owned marks live now, in any document or history (a writer that finds none
      need not look for their fields). }
    class function OwnedAlive: Int64;
    { The same kind, field and bytes - its own copy of them when this one's are a file's. }
    function Clone: TTyRichObject; override;
    { Its bytes when it owns them; nothing of a file's buffer, which the document keeps for
      its paragraphs anyway (and which is counted once, as the load's, not per mark). }
    function DataBytes: Int64; override;
    // the bytes it owns: a clone of it shares them, and the history counts them once
    function SharedData(out ABytes: Int64): Pointer; override;
    { A fresh identity for marks not read from a file: below zero, never given twice. }
    class function NewId: Int64;
    property Kind: TTyRichFieldMarkKind read FKind;
    property Id: Int64 read FId;
    { The open mark: the field's whole group, as read (RawUc: the \uc it was read under) - a
      copy, for a mark whose bytes are its file's; a writer reads them in place (BytesData). }
    property Bytes: RawByteString read GetBytes;
    { Its bytes where they are: BytesLength of them from BytesData, valid while it lives. }
    function BytesData: PByte;
    function BytesLength: Int64;
    // its bytes are a range of its file's (CreateInFile), not its own
    function InFile: Boolean;
    { Read from RTF: the fonts of Word's three slots in force where its group began - AIndex 0
      \loch\afN, 1 \hich\afN, 2 \dbch\afN: the font's name and charset ('' none named) -
      and the slot named last (SetSlot: 0 none, 1 \loch, 2 \hich, 3 \dbch, 4 \ltrch,
      5 \rtlch). The group's own \loch
      \hich \dbch words fall back on them: a writer that writes the bytes after text of its
      own puts them in force first, by its own numbers. }
    procedure SetSlotFont(AIndex: Integer; const AName: UTF8String; ACharset: Integer);
    procedure SetSlot(ASlot: Byte);
    function HasSlots: Boolean;
    function SlotName(AIndex: Integer): UTF8String;
    function SlotCharset(AIndex: Integer): Integer;
    property Slot: Byte read FSlot;
    property Owned: Boolean read FOwned;
    // an owned open mark's instruction and state words ('' and 0 for any other mark)
    property Instruction: UTF8String read FInstruction;
    property Flags: Byte read FFlags;
  end;

const
  // an owned field's state words (TTyRichFieldMark.Flags)
  CTyRichFieldDirty = 1;   // \flddirty
  CTyRichFieldEdit = 2;    // \fldedit
  CTyRichFieldLock = 4;    // \fldlock
  CTyRichFieldPriv = 8;    // \fldpriv

type
  TTyRichTable = class;
  TTyRichRow = class;
  TTyRichEdges = array of Integer;
  TTyRichRowList = array of TTyRichRow;

  TTyRichCell = class
  private
    FRow: TTyRichRow;
    FIndex: Integer;
  public
    function Table: TTyRichTable;
    property Row: TTyRichRow read FRow;
    property Index: Integer read FIndex;
  end;

  TTyRichRow = class
  private
    FTable: TTyRichTable;
    FIndex: Integer;
    FCells: array of TTyRichCell;
    FBoundaries: array of Integer;
    FRawFormat: RawByteString;
    FHoldsNestedTable: Boolean;
    { Its edges are not what RawFormat says (an edit moved them): written from the model
      (Edited) - the \cellx and Word's preferred widths made again from CellEdges. }
    FEdgesMoved: Boolean;
    { A row an edit made (Freeable) lives as long as something refers to it - the table's
      rows of now (FRows), an undo step that holds it (FRowsOld / FRowsNew), a paragraph
      value whose cell is one of its cells - and no longer: FRefs counts them, the last
      release frees it (its slot in the table's FOwned, FOwnedAt, goes nil). The rows a reader
      added are the table's for its life (a reader that gives paragraphs later finds them by
      their number). }
    FRefs: Integer;
    FFreeable: Boolean;
    FOwnedAt: Integer;
    // (see Format, BaseFormat; nil until asked: decoded from FRawFormat then)
    FFormat, FBase: TTyRichRowFormat;
    function GetCell(AIndex: Integer): TTyRichCell;
    function GetBoundary(AIndex: Integer): Integer;
    procedure SetFormats(ABase, AFormat: TTyRichRowFormat);
  public
    destructor Destroy; override;
    { The row's look now: its cells' borders, shading, padding, alignment and its own
      properties (tyControls.RichEdit.TableProps). The same object as BaseFormat until a
      property edit changes it; a writer then makes the row's definition again from
      RawFormat (TyRichRowFormatBytes), and a layout shows it. }
    function Format: TTyRichRowFormat;
    { What RawFormat says (the reader decodes it with its file's colours; a row made here
      without them has the colour words as automatic). }
    function BaseFormat: TTyRichRowFormat;
    { RawFormat no longer says how the row looks: Format is not BaseFormat, or its edges
      moved (a width's edit). }
    function Edited: Boolean;
    { What the row is shown with: TyRtfRowDisplay of RawFormat (TyDefaultRowDisplay without
      one) while it is not Edited, else the display of its Format. }
    function Display: TTyRowDisplay;
    function CellCount: Integer;
    function BoundaryCount: Integer;
    { Its cells' right edges in twips, as a row with no format of its own is written: its
      own, else (when it has none) the table's, else 1440 twips a cell. }
    function CellEdges: TTyRichEdges;
    property Cells[AIndex: Integer]: TTyRichCell read GetCell;
    { This row's own cell right edges in twips (\cellx); none means the table's. }
    property Boundaries[AIndex: Integer]: Integer read GetBoundary;
    { The row's \trowd ... \cellx fragment as read, '' for a new row. }
    property RawFormat: RawByteString read FRawFormat;
    { One of the row's cells holds a table of its own. The model has no nested tables: the
      inner cells' paragraphs are paragraphs of the outer cell, and what made them a table is
      only in the file's bytes. So the row stays as the file has it: the primitives refuse to
      change the text of its paragraphs and leave their formats alone (see
      TTyRichDocument.CanChange). }
    property HoldsNestedTable: Boolean read FHoldsNestedTable;
    property Table: TTyRichTable read FTable;
    property Index: Integer read FIndex;
  end;

  { A table is a contiguous range of paragraphs. A paragraph's data points to its cell; the
    table knows no paragraph index, so paragraphs before it come and go without touching it.
    Its rows and cells are fixed once a paragraph uses it (AddRow raises then): a change of
    its structure (TTyRichDocument's table edits) gives the paragraphs the cells of a new
    table, and the old one stays with the values an undo can put back. }
  TTyRichTable = class(TTyRichRefCounted)
  private
    FRows: array of TTyRichRow;
    { Every row made for it, freed with it: those AddRow made first (FAdded of them, in
      order: what a reader that sets its paragraphs later goes by), then those its edits
      made. FRows are the rows the document has now, in order; a row an edit replaced or took
      out stays here for the undo that puts it back. }
    FOwned: array of TTyRichRow;
    FOwnedCount: Integer;
    FAdded: Integer;
    { FRows are exactly the rows that have paragraphs, in their order, each row's Index its
      place among them. A plain delete that takes a row's last paragraph away clears it (the
      row stays in FRows, with no paragraph); the next table edit puts it right, as a step
      of its own undo. While it is False, row numbers are found by a walk of the table. }
    FRowsValid: Boolean;
    FColBoundaries: array of Integer;
    FStructureLocked: Boolean;
    FContentLocked: Boolean;
    FCut: Boolean;
    FFrozen: Boolean;
    FParaRefs: Integer;
    function GetRow(AIndex: Integer): TTyRichRow;
    function GetColBoundary(AIndex: Integer): Integer;
  public
    { AContentLocked: what the table holds forbids a change of its structure (merged cells,
      a nested table). ACut: the table is a part of a table of its file, as a reader that
      parses on demand gives it (see Cut). }
    constructor Create(const AColBoundaries: array of Integer; AContentLocked: Boolean = False;
      ACut: Boolean = False);
    destructor Destroy; override;
    function AddRow(ACellCount: Integer; const ARawFormat: RawByteString = ''): TTyRichRow;
      overload;
    function AddRow(ACellCount: Integer; const ARawFormat: RawByteString;
      const ABoundaries: array of Integer; AHoldsNestedTable: Boolean = False): TTyRichRow;
      overload;
    { A row as AddRow made it, AIndex-th (what a reader that gives the table's paragraphs
      their cells later goes by: the rows an edit made or replaced since are not among
      them). }
    function AddedRow(AIndex: Integer): TTyRichRow;
    function AddedRowCount: Integer;
    { The row objects alive in it: those a reader added and the versions an edit made that
      something still refers to (the rows of now, an undo step, a paragraph value). }
    function LiveRowCount: Integer;
    { Sets the format of the row AddRow made last as its bytes say it (TTyRichRow.BaseFormat;
      the reader decodes it with its file's colours). The table takes a reference of its
      own. Only before a paragraph uses the table. }
    procedure SetLastRowFormat(AFormat: TTyRichRowFormat);
    function RowCount: Integer;
    function CellCount: Integer;
    function ColBoundaryCount: Integer;
    { Bytes the table, its rows, cells, formats and edges take. }
    function MemSize: Int64;
    property Rows[AIndex: Integer]: TTyRichRow read GetRow;
    property ColBoundaries[AIndex: Integer]: Integer read GetColBoundary;  // twips
    { Merged cells and the like, or a part of a table: shown and kept, but its structure
      cannot be edited as this object (ContentLocked or Cut). }
    property StructureLocked: Boolean read FStructureLocked;
    { What it holds forbids a change of its structure: merged cells, a nested table. }
    property ContentLocked: Boolean read FContentLocked;
    { One of the parts a reader that parses on demand cut a table of its file into (one too
      big to parse whole for a read, one still open where the load stood, one cut where a
      parsing block ends). The paragraphs of the next part are another table object. A
      table edit takes the parts together when the paragraph loader says the table is whole
      (TTyRichParaLoader.WholeTable) and refuses it otherwise. }
    property Cut: Boolean read FCut;
  end;

  TTyRichTables = array of TTyRichTable;

  { The structural table edits (TTyRichDocument.TableEditRefusal, and the commands of
    tyControls.RichEdit.Commands that make them). A table is named by a position inside it
    (a table object does not outlive a change of its structure); rows are counted over the
    rows that have paragraphs, in text order, from 0; cells by their index in the row. }
  TTyRichTableEditKind = (rtkInsertTable, rtkInsertRow, rtkDeleteRow, rtkInsertColumn,
    rtkDeleteColumn, rtkMergeCells, rtkSplitCell, rtkInsertGridColumn, rtkDeleteGridColumns);

  TTyRichTableEdit = record
    Kind: TTyRichTableEditKind;
    { rtkInsertTable: where the table goes; the others: any position in the table. }
    Pos: TTyRichPos;
    { The row (rtkInsertRow 0 .. row count: the new row's index, or CRichRowAbove /
      CRichRowBelow) or the cell index (rtkInsertColumn 0 .. cell count; the delete kinds:
      an existing one). }
    Index: Integer;
    // rtkInsertTable: its size, and its width in twips (0: the document's text width)
    Rows, Cols, Width: Integer;
    { rtkMergeCells: rows Row0 .. Row1, and in each the cells that meet X0 .. X1 (twips; a
      cell from its left edge to its right): they become one cell - the first of them in each
      row, as wide as they were together, the first row's starting a vertical merge the
      others' continue (one row: no vertical merge). The cells that go must be empty (the
      paragraph each keeps goes with it): TTyRichDocument's caller moves their content first
      (tyControls.RichEdit.TableSel's TyRichMergeCommand does). }
    Row0, Row1, X0, X1: Integer;
    { rtkSplitCell: cell Index of row Row0, which covers SpanRows rows (1: none below it), split
      into Cols cells across - at SplitEdges (twips, inside the cell, rising: Cols - 1 of
      them) - and Rows down: over SpanRows rows Rows must divide them (each part a vertical
      merge of SpanRows div Rows rows, or none); in one row (SpanRows 1) Rows - 1 rows go in
      below it and every other cell of the row reaches down over them (a vertical merge). The
      content stays in the first cell; the new ones are empty and look as the split cell did,
      their inner lines its left (between columns) and its top (between rows). }
    SpanRows: Integer;
    SplitEdges: TTyRichEdges;
    { rtkInsertGridColumn: a column Width twips wide at X0 (twips; a grid edge): in a row with
      an edge there, a new cell (empty, as the cell beside it looks, merged with nothing); in a
      row whose cell reaches over X0 (a merged cell, a wide one), that cell Width wider; every
      edge after it Width further right.
      rtkDeleteGridColumns: the grid's columns from X0 to X1 (twips): a cell wholly inside
      goes, one that reaches out of it keeps its content and is what is left of it wide;
      every edge after them that much further left. Both by the grid, for any table that holds
      no nested table - merged cells, rows of different cells. }
  end;

  { Why a table edit cannot be made (rtrNone: it can):
    rtrReadOnly      the document is loading, incomplete or being saved;
    rtrNoTable       the position is in no table;
    rtrInTable       an insert of a table into a table (nested tables are not edited);
    rtrMergedCells   the table has merged cells;
    rtrNestedTable   a row of it holds a nested table;
    rtrNotWhole      a table a reader that parses on demand gives in parts, which it cannot
                     give whole: one bigger than it parses at once, or one still loading;
    rtrIrregularRows a column edit of a table whose rows do not all have as many cells;
    rtrOutOfRange    a row or cell index, a size or a position out of range;
    rtrInField       an insert of a table inside a field's result (it is read-only);
    rtrNotEmpty      a merge of cells whose cells that go (or that become covered) are not
                     empty: their content would go with them. }
  TTyRichTableRefusal = (rtrNone, rtrReadOnly, rtrNoTable, rtrInTable, rtrMergedCells,
    rtrNestedTable, rtrNotWhole, rtrIrregularRows, rtrOutOfRange, rtrInField, rtrNotEmpty);

const
  { Two rows share an edge when their edges are at most this far apart (twips): a Word table's
    rows often differ by a few twips where a person sees one line. }
  CRichSharedEdgeTwips = 15;

type

  { An edit of table properties (TTyRichDocument.TablePropsRefusal, EditTableProps; the
    commands TTyRichSetCellProps and TTyRichSetRowProps make them): the table a position is
    in, rows ARow0 .. ARow1 counted as the table edits count them, and for a cell edit cells
    ACol0 .. ACol1 of each (a row with fewer cells has those it has). Only the fields Valid
    names change. }
  { What a change of the rows' edges does (TTyRichPropEdit.EdgeKind):
    rekNone        no edge moves (but those a width or a left in the properties moves);
    rekMove        the edge at EdgeFrom (twips; a row's edge within CRichSharedEdgeTwips of
                   it - its left, or a cell's right edge) moves by EdgeTo - EdgeFrom: the
                   cells on either side trade width (a row's left: its first cell's width
                   follows, its right side stays; its last edge: the last cell and the row's
                   width change), or with EdgeShift the cell to its left changes and every edge
                   after it moves too (a left: the whole row moves). A row with no edge there
                   is left as it is. A cell never becomes narrower than a twip;
    rekDistribute  every cell of a row as wide as the others, the row's width kept;
    rekFit         a row's widths in proportion, the row FitWidth twips wide. }
  TTyRichEdgeKind = (rekNone, rekMove, rekDistribute, rekFit);

  TTyRichPropEdit = record
    Pos: TTyRichPos;
    Row0, Row1, Col0, Col1: Integer;
    // a row edit (RowProps): Row; a cell edit: Cell
    OfRows: Boolean;
    Cell: TTyRichCellProps;
    Row: TTyRichRowProps;
    // a change of the edges (a row edit: OfRows True)
    EdgeKind: TTyRichEdgeKind;
    EdgeFrom, EdgeTo, FitWidth: Integer;
    EdgeShift: Boolean;
  end;

  { Where a paragraph is in its table (TTyRichDocument.TableInfoAt): the table's paragraphs,
    its rows (those that have paragraphs), the paragraph's row and its paragraphs, its cell's
    index, the row's cells, and the cell's paragraphs. }
  TTyRichTableInfo = record
    First, Last: Integer;
    RowCount: Integer;
    Row: Integer;
    RowFirst, RowLast: Integer;
    Cell: Integer;
    CellCount: Integer;
    CellFirst, CellLast: Integer;
  end;

const
  // the size of a table made here: Word's limits, 63 columns and 32767 rows
  CRichMaxTableCols = 63;
  CRichMaxTableRows = 32767;
  { rtkInsertRow's Index for a row right above / below the row Pos is in: the edit finds that
    row in the read it makes anyway, so a caller that knows only the position reads nothing. }
  CRichRowAbove = -1;
  CRichRowBelow = -2;

type

  { A run starts at Start (characters from the paragraph's start) and reaches the next run's
    Start, the last one the paragraph's end. With Obj set, the run is that object's one U+FFFC
    character. }
  TTyRichRun = record
    Start: Integer;
    Format: TTyCharFormatId;
    Obj: TTyRichObject;
  end;
  TTyRunArray = array of TTyRichRun;

  { Objects a history step holds (GatherObjects): duplicates allowed, the history counts
    each distinct one once. }
  TTyRichObjectList = array of TTyRichObject;

  { One paragraph's formatting, immutable once made (internal; see the unit comment). FRuns
    nil means one run in the document's default character format. }
  TTyRichParaData = class
  private
    FRefCount: Integer;
    FPrev, FNext: TTyRichParaData;
    FParaFormat: TTyParaFormatId;
    { Fields open at the paragraph's start (TTyRichFieldMark): the open marks before it whose
      close mark is not before it. The invariant every value of a document keeps: the first
      paragraph's is 0, and each next paragraph's is the one before's plus the open marks
      less the close marks in that one's runs - so whether a place lies inside a field's
      result is known from its own paragraph, never by a walk back through the paragraphs of
      a long result. A reader sets it; an edit keeps it (TTyRichDocument.FixDepths). (Next to
      FParaFormat: the two fill one word, the value is no larger for it.) }
    FFieldDepth: Integer;
    FCell: TTyRichCell;
    FRuns: TTyRunArray;
    // the file's own marker text of a list item (TTyRichDocument.ListTextOf)
    FListText: UTF8String;
    { A table edit gave the paragraph a cell of a new table whose row is the same as the
      row of FSource's cell (TTyRichDocument.ValueSource): held, nil otherwise. }
    FSource: TTyRichParaData;
    { The identity of its objects, in order (for the history, which counts each object
      once): 0 when its runs hold none; a value
      made from another one with the very same objects (typing in a paragraph that holds
      pictures) shares that one's key, so the history knows those objects are counted
      without walking them again. }
    FObjKey: Int64;
  end;

  TTyRichChangeKind = (rckText, rckFormat, rckStructure);
  TTyRichChangeKinds = set of TTyRichChangeKind;

  { What a change did: the characters [Pos, Pos+OldLen) became [Pos, Pos+NewLen), and the
    paragraphs FirstPara..FirstPara+OldParaCount-1 became FirstPara..FirstPara+NewParaCount-1.
    rckStructure: paragraphs came or went, or table structure changed. }
  TTyRichChange = record
    Kinds: TTyRichChangeKinds;
    Pos: TTyRichPos;
    OldLen: TTyRichPos;
    NewLen: TTyRichPos;
    FirstPara: Integer;
    OldParaCount: Integer;
    NewParaCount: Integer;
  end;

  TTyRichChangeEvent = procedure(Sender: TObject; const AChange: TTyRichChange) of object;

  { What a document has besides its paragraphs (TTyRichDocument.Settings): the page, in twips
    (what a page-wide layout wraps at), the formats of a paragraph with nothing of its own
    (DefaultCharFormat, DefaultParaFormatId), and the document's own ground - clNone: none,
    a view shows its own. Start a change from the document's own (Document.Settings) and
    change the members you mean: members may be added, and a record built from nothing would
    give them zero. }
  TTyRichDocSettings = record
    PaperWidth, PaperHeight, MarginLeft, MarginRight: Integer;
    CharFormat: TTyCharFormat;
    ParaFormat: TTyParaFormat;
    Color: TColor;
  end;

  { How a plain text file is encoded (tyControls.RichEdit.TextIO reads and writes it).
    teAuto only asks the reader to find out; teAnsi's code page is a number beside it. }
  TTyTextEncoding = (teAuto, teUtf8, teUtf8Bom, teUtf16LE, teUtf16BE, teAnsi);

  TTyRichDocument = class;

  { Count paragraphs in a row that had the same old value: a format change over two million
    plain paragraphs keeps one entry, not two million pointers. }
  TTyRichOldData = record
    Data: TTyRichParaData;
    Count: Integer;
  end;

  { A paragraph ReplaceInParas changed: its index (that edit keeps every paragraph where it
    was), its pieces before - whole, its separator with them (First, Count in
    TTyRichUndoData's swap pieces) - and its value before. }
  TTyRichParaSwap = record
    Para: Integer;
    First, Count: Integer;
    Old: TTyRichParaData;
  end;

  { What a primitive took away, kept so that Revert can put it back: the removed text's pieces
    (with the data of the paragraphs that followed their separators) and the old data of the
    paragraphs that survived. It holds references, no text. Free it when the command that made
    it goes; it must not outlive its document. }
  TTyRichUndoData = class
  private
    FDoc: TTyRichDocument;
    FChange: TTyRichChange;
    FInserted: TTyRichPos;        // characters the change put at FChange.Pos
    FRemoved: TTyRichPieces;      // what it took away there
    { The storage at the places the change split or decoded, as it was (the paragraph's lazy
      piece among them): Revert gives it back once the text is the same again, so a paragraph
      an undo returns to what it was is its file's bytes again. FSpan2: a delete's other
      end, when it is apart from the first. }
    FSpan, FSpan2: TTyRichSpan;
    FFirstPara: Integer;
    FOldData: array of TTyRichOldData;   // run-length: one reference per entry
    FOldCount: Integer;
    // ReplaceInParas: the paragraphs it changed, in the order it changed them
    FSwaps: array of TTyRichParaSwap;
    FSwapCount: Integer;
    FSwapPieces: TTyRichPieceArray;
    FSwapPieceCount: Integer;
    { A table edit: the records of the edits it is made of, in the order they were made
      (Revert reverts them newest first); a part whose change has no kinds told nobody of
      itself (a paragraph given an equal cell of a new table). }
    FParts: array of TTyRichUndoData;
    FPartCount: Integer;           // used of FParts while the edit is made (SealParts)
    { A table edit's change of a table's rows (TTyRichTable's FRows): FRowsOld at FRowAt
      became FRowsNew; FRowsOldIdx their indexes before, FRowsOldValid the table's
      FRowsValid before (FRowTable held). }
    FRowTable: TTyRichTable;
    FRowAt: Integer;
    FRowsOld, FRowsNew: array of TTyRichRow;
    FRowsOldIdx: array of Integer;
    FRowsOldValid, FRowsNewValid: Boolean;
    { What else only it keeps alive, counted when it was made: the old values a table edit
      gave other cells and the table objects they are in. }
    FExtraBytes: Int64;
    { The document's settings before a change of them (TTyRichDocument.ChangeSettings), and
      whether that change made the shared plain value keep the look it had. }
    FHasSettings: Boolean;
    FSettings: TTyRichDocSettings;
    FFroze: Boolean;
    procedure AddPart(APart: TTyRichUndoData);
    procedure SealParts;
    procedure AddOld(D: TTyRichParaData);
    procedure SealOld;
    procedure AddSwap(APara: Integer; AOld: TTyRichParaData; const APieces: TTyRichPieces);
    procedure SealSwaps;
  public
    destructor Destroy; override;
    { Bytes this record keeps alive, for the history's memory limit (the paragraph values
      themselves are shared and not counted, nor the objects they hold: GatherObjects). }
    function MemSize: Int64;
    { Appends the objects the values this record keeps hold (a deleted picture, a paragraph's
      old value with its picture) to AList (ACount used). }
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
    property Change: TTyRichChange read FChange;
  end;

  { The way in for readers (RTF): sets a paragraph's formatting, the document defaults and the
    page, as loading, not as a change - no OnChange, no undo, Modified untouched. Subclass it
    and call the class methods. }
  TTyRichDocBuilder = class
  protected
    { Sets the paragraph's formatting if it has none yet and returns True; leaves a paragraph
      that already has formatting (edited, or parsed before) alone and returns False. ARuns as
      RunsOf returns them: the first starts at 0, starts increase, an object run is one
      character. AListText: the marker text the file gives the paragraph (ListTextOf); a
      value of its own then, never the one plain paragraphs share. AFieldDepth: the fields
      open at the paragraph's start (the field marks before it not yet closed); not 0: a
      value of its own too. }
    class function SetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
      AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell = nil;
      const AListText: UTF8String = ''; AFieldDepth: Integer = 0): Boolean;
    { The value SetParagraph would give paragraph AIndex (the same checks, the runs clipped
      to its text alike), put in no paragraph's slot and held once for the caller, who lets
      it go with ReleaseValue: for a reader that hands a walk what it parsed without setting
      it (TTyRichTextProvider.WalkValue), so that a walk leaves nothing behind. A plain
      paragraph gets the value parsed plain paragraphs share. }
    class function MakeValue(ADoc: TTyRichDocument; AIndex: Integer;
      AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell = nil;
      const AListText: UTF8String = ''; AFieldDepth: Integer = 0): Pointer;
    class procedure SetDefaultCharFormat(ADoc: TTyRichDocument; const AFormat: TTyCharFormat);
    class procedure SetPage(ADoc: TTyRichDocument; APaperWidth, APaperHeight, AMarginLeft,
      AMarginRight: Integer);
    { The format a paragraph with nothing of its own has (an RTF file's \defpap group), and the
      document's ground (clNone: none). }
    class procedure SetDefaultParaFormat(ADoc: TTyRichDocument; const AFormat: TTyParaFormat);
    class procedure SetDocumentColor(ADoc: TTyRichDocument; AColor: TColor);
    { Puts AText in place of ADoc's whole content - a file opened into an existing document.
      ADoc takes AText over, also when this raises; AText must be one no document has used
      (its paragraph slots nil). The history goes, every paragraph value of the old content
      is let go of, an installed loader goes with the content it parsed, the default
      character format and the page go back to a new document's (a reader that has its own
      sets them afterwards), Modified becomes False, and the source metadata is set; then
      OnChange reports one change of everything:
      Kinds [rckText, rckFormat, rckStructure], Pos 0, the old and new lengths, paragraphs 0
      with the old and new counts (a view throws all its layout away on it). Raises
      ETyRichModel while a command runs, inside BeginUpdate .. EndUpdate, while the document
      is being saved or inside a read scope (BeginRead) - it frees AText then. Without the
      metadata: UTF-8 without a BOM, and the majority line break of AText's load scan. }
    class procedure ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText); overload;
    class procedure ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText;
      AEncoding: TTyTextEncoding; ACodePage: Integer; AHasBom: Boolean;
      ALineBreak: TTyRichSeparator); overload;
    { A reader that loads in slices: while ALoading the document can be read but not changed
      (Execute returns False); AIncomplete: the load stopped before the end of the file, and
      the document stays read-only (a writer must not save it as the file). ReplaceText
      clears both. }
    class procedure SetLoadState(ADoc: TTyRichDocument; ALoading, AIncomplete: Boolean);
    { Raises OnChange for what a slice of loading added (no undo, Modified untouched). }
    class procedure ReportLoad(ADoc: TTyRichDocument; const AChange: TTyRichChange);
    { For a loader that sends parsed paragraphs back to unparsed. ParagraphValue: the
      paragraph's value as it is, without parsing it (nil: none). HoldValue/ReleaseValue
      keep a value alive (so that its identity means "unchanged" while held). UnsetParagraph:
      when the paragraph still has AValue, it becomes unparsed (True). }
    class function ParagraphValue(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
    class procedure HoldValue(ADoc: TTyRichDocument; AValue: Pointer);
    class procedure ReleaseValue(ADoc: TTyRichDocument; AValue: Pointer);
    { Somebody besides the caller's own hold keeps AValue alive: a paragraph has it, or an
      undo record that can put it back. Never True for the one value all plain parsed
      paragraphs share: it says nothing about any one of them. }
    class function ValueShared(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
    { AValue is that one shared value: whether a paragraph that has it is the file's own
      cannot be told from the value - only from what the file makes of the paragraph. }
    class function IsPlainValue(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
    class function UnsetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
      AValue: Pointer): Boolean;
    { A command is running, the text is being changed, or a read scope is open
      (TTyRichDocument.BeginRead): values read earlier are in use, and nothing may be sent
      back to unparsed. }
    class function DocumentBusy(ADoc: TTyRichDocument): Boolean;
  end;

  { Parses paragraphs on demand. EnsureParsed calls LoadParagraph for a paragraph that has no
    formatting yet; it sets that paragraph's (and, if it likes, its neighbours') formatting with
    SetParagraph. A paragraph it leaves unset counts as plain and is not asked about again.
    A loader that sends parsed paragraphs back to unparsed (UnsetParagraph) does so only
    while DocumentBusy is False - never inside a read scope, never while a command runs. }
  TTyRichParaLoader = class(TTyRichDocBuilder)
  public
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); virtual; abstract;
    { A read found paragraph AIndex parsed already: it is in use (for a loader that keeps
      the most recently used paragraphs parsed). Called for every such read: keep it cheap. }
    procedure ParagraphRead(ADoc: TTyRichDocument; AIndex: Integer); virtual;
    { The outermost read scope ended: nothing read inside it is held any longer. }
    procedure ReadsEnded(ADoc: TTyRichDocument); virtual;
    { Paragraph AIndex is in a table this loader gave in parts (TTyRichTable.Cut): True when
      that table of the file can be taken as one - the file is read to its end, the table is
      closed and no bigger than the loader parses at once - with the paragraphs its parts
      have together, AFirst .. ALast. Called inside a read scope; it may read (parse) the
      parts. False by default: such a table's structure is not edited. }
    function WholeTable(ADoc: TTyRichDocument; AIndex: Integer;
      out AFirst, ALast: Integer): Boolean; virtual;
    { Paragraph AIndex, not parsed (no value yet): how many fields are open at its start, and
      the fewest open anywhere in it (its start and its end included), as the loader's index
      knows them - without parsing it. Cheap: a field query asks it of every paragraph of a
      field. False by default: not known (the paragraph is parsed to tell). }
    function ParaFieldDepths(ADoc: TTyRichDocument; AIndex: Integer;
      out AStart, ALow: Integer): Boolean; virtual;
    { Whether paragraph AIndex holds a field's mark, as the loader's index knows it - without
      parsing it. False by default: not known (the paragraph is parsed to tell). }
    function ParaHoldsMarks(ADoc: TTyRichDocument; AIndex: Integer;
      out AHolds: Boolean): Boolean; virtual;
    { The bookmark ends its index found in the file, in the file's order - so a document read
      on demand finds a bookmark by name without parsing (tyControls.RichEdit.Bookmarks). -1 by
      default: no index (every paragraph's value is asked). }
    function BookmarkIndexCount: Integer; virtual;
    { Entry AIndex: its kind, the hash of its name (TyRichBookmarkHash), the file offset of the
      paragraph it is in (TTyRichText.ParaOfLazySource finds the paragraph while that one is
      unedited) and of its group. }
    procedure BookmarkIndexEntry(AIndex: Integer; out AKind: TTyRichBookmarkKind;
      out AHash: Cardinal; out AParaSrc, AGroupSrc: Int64); virtual;
    // entry AIndex's name, decoded from the file's bytes (nothing parsed)
    function BookmarkIndexName(AIndex: Integer): UTF8String; virtual;
    // entry AIndex's name is a hidden bookmark's ("_" first), told without decoding it
    function BookmarkIndexHidden(AIndex: Integer): Boolean; virtual;
  end;

  TTyRichRange = record
    Pos: TTyRichPos;
    Len: TTyRichPos;
  end;

  { A view's selection: its anchor, its caret, and whether the caret stands at the end of a
    wrapped line (its affinity). }
  TTyRichSelectionMark = record
    Anchor: TTyRichPos;
    Caret: TTyRichPos;
    AtLineEnd: Boolean;
  end;

  { Where the view that made a step had its selection before the step and after it
    (TTyRichCommand.Marks): the view's, not the document's - the document only keeps it with
    the step, so that an undo can put the selection back as it was and a redo where the step
    left it, which the change's extent cannot tell (a deleted selection and a character taken
    by Backspace report the same range). A step made by code has none (HasBefore and HasAfter
    False). A merged run of typing keeps the Before of its first insert and the After of its
    last; the marks go with the step when the history lets it go. }
  TTyRichStepMarks = record
    HasBefore: Boolean;
    HasAfter: Boolean;
    Before: TTyRichSelectionMark;
    After: TTyRichSelectionMark;
  end;

  { What a fragment carries of its source's kept bytes into a document whose file's header
    tables are not the source's (TTyRichFragment, AFilter). A format's Extra, a row's
    RawFormat and an opaque object's bytes may name fonts, colours, styles and lists by the
    numbers of the source's tables; in another document those numbers mean the target's
    entries. Who reads such bytes implements it (tyControls.RichEdit.RtfRead's
    TyRichFragmentFilterFor, which also says what is kept where the tables agree); the model
    only asks it. It never changes the source. }
  TTyRichFragmentFilter = class
  public
    { A fragment of a format's Extra (APara: a paragraph format's) goes along. }
    function KeepFragment(const AFragment: RawByteString; APara: Boolean): Boolean; virtual; abstract;
    { A row's RawFormat as the row made again for the target has it. }
    function RowFormat(const ARaw: RawByteString): RawByteString; virtual; abstract;
    { What ARaw (a RawFormat RowFormat gave) says of a row of ACellCount cells, its colour
      words read by the colours they name (TyRichDecodeRowFormat; pooled, one reference for
      the caller). By default no colour is known: they read as automatic. }
    function RowLook(const ARaw: RawByteString; ACellCount: Integer): TTyRichRowFormat; virtual;
    { AObj as it goes along: AObj itself; an object made again (a new one no reference was
      taken of - the fragment's paragraph values take theirs); or nil: it is left out, and
      AText ('' none) stands in its character's place, in its run's format. }
    function MapObject(AObj: TTyRichObject; out AText: UTF8String): TTyRichObject; virtual; abstract;
  end;

  { A stretch of a document's own content, read for a copy or a move of it to another place of
    the same document (tyControls.RichEdit.Commands' TTyRichCopy and TTyRichMove) - what
    TTyRichFragment.CreateOfContent makes ready to go in. It is what the control's own
    clipboard round trip carries of [AFrom, AFrom + ALen) (the paragraphs RtfWrite's
    TyRichCopyRange gives): the range's characters; with AWiden, a range that reaches into
    more than one cell, or across a row's edge, takes every row it meets whole, as a copy
    does (a move takes its range as it is); a range inside one cell is paragraphs of no table;
    the document's last paragraph taken to its end is taken whole, as if a paragraph mark
    followed it (so is an empty last paragraph by a range that reaches the end through the
    separator before it).
    What it holds: a reference to each paragraph's value (nil: a plain one), and the text as
    the pieces it is made of - references, never a copy of the text; only when a paragraph of
    the range is still a lazy load's own (its pieces must stay where the file has them, in the
    order of the file) the text itself, decoded. Every reference stays good while the range is
    deleted (a move reads its content before it deletes it). Free it before its document. }
  TTyRichRangeContent = class
  private
    FDoc: TTyRichDocument;
    FValues: array of TTyRichParaData;   // per paragraph taken, one reference each
    FLens: array of Int64;               // its characters taken (no separator)
    FCount: Integer;
    FFirst, FLast: Integer;
    // the first paragraph is taken from FFirstFrom, the last to FLastTo; their own lengths
    FFirstFrom, FLastTo, FFirstLen, FLastLen: Int64;
    FPieces: TTyRichPieces;              // the separators' data held
    FUseText: Boolean;
    FText: UTF8String;                   // FUseText: the paragraphs' text, #10 between them
    FTextLen: PtrInt;
    FEnds, FEndsInText, FInOneCell: Boolean;
    FCharCount: Int64;
    procedure TakePara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    function FieldOverParagraphs: Boolean;
  public
    { AIntoCell: it goes into a table cell - a range that holds a field whose result holds a
      paragraph's end is then held as text (the fragment takes that field's marks out:
      TTyRichFragment). }
    constructor Create(ADoc: TTyRichDocument; AFrom, ALen: TTyRichPos; AWiden: Boolean;
      AIntoCell: Boolean = False);
    destructor Destroy; override;
    { Paragraphs taken (a part of one counts). }
    property ParaCount: Integer read FCount;
    { Characters of the document taken (separators included). }
    property CharCount: Int64 read FCharCount;
    { The text is held as text (a lazy paragraph is among it), not as pieces. }
    property HoldsText: Boolean read FUseText;
    { The pieces of the characters taken (none when HoldsText). }
    property TextPieces: TTyRichPieces read FPieces;
  end;

  { Content of a document of its own (what a reader made of a clipboard's RTF) made ready to
    go into another document at one place - what TTyRichDocument's InsertFragment inserts.
    Made by the target document's terms: the source's character and paragraph formats are
    interned in the target's pool (a run with no font of its own gets the source's default
    font, and the source's default size where it has none: it is shown as it was where it was
    copied, whatever the target's defaults are); objects and tables are shared, each with the
    references the target's paragraph values take (they are immutable, so a second document
    may hold them); the source's document-level things (its page, its default character
    format, its loader) do not come along. The source is only read: the caller frees it, and
    may do so as soon as this is made.

    The paragraphs are "parts": part 0 joins the text before APos, the last part the text after
    it, the ones between are paragraphs of their own, each a value of the target held here (so
    a redo puts the very same values back). AEndsWithParagraph: the source's last paragraph
    ended with a paragraph mark (in RTF, a \par after it): the text after APos then stays a
    paragraph of its own (a last part that is the target's own). Tables: rows go in as rows
    when APos is in no table and AFlatten is False - the paragraph at APos is split before the
    first row when text stands before APos, and after a last row always (no row is ever joined
    with text, no row is left half); otherwise (APos in a cell, or AFlatten) every paragraph
    is a plain paragraph of the cell (or of no table) APos is in: never a nested table. A
    source table one of whose rows holds a nested table (TTyRichRow.HoldsNestedTable) goes in
    as its paragraphs, plain, in no table - the model's own view of the inner table: what made
    it a table is only in the source file's bytes. The
    list markers a file gave are not taken: the numbers are counted, as after any edit.

    AFilter (nil: everything goes as the source has it - what a paste inside one document,
    or between two documents whose files' header tables agree, wants): what the source keeps
    of its file's bytes goes through it - a format's Extra fragment by fragment, each object -
    and its tables are made again for the target, each row with the RawFormat the filter
    gives (the rows are then the fragment's own, not the source's). The filter is used only
    while the fragment is made; the caller frees it.
    The values hold references into the target document: free a fragment before its target. }
  TTyRichFragment = class
  private
    FDoc, FSrc: TTyRichDocument;
    FText: UTF8String;
    FTextLen: PtrInt;
    FParts: array of TTyRichParaData;   // per part (nil: plain), one reference each
    FLens: array of Int64;              // its characters
    FOwn: array of Boolean;             // the target's own: no content, the target's format
    FCount: Integer;
    FFlat: Boolean;
    FFlatCell: TTyRichCell;
    FCharMap, FParaMap: array of Integer;
    FSrcDefault: TTyCharFormat;
    FFilter: TTyRichFragmentFilter;
    // what the first insert put in the text, as its pieces: a redo puts these back instead of
    // copying the text into the add buffer once more (it only grows)
    FPieces: TTyRichPieces;
    FHavePieces: Boolean;
    FTextBytes: Int64;
    // the source's tables met, and what goes in for each (made again, or the very one)
    FTabSrc, FTabNew: array of TTyRichTable;
    FTabCount: Integer;
    { Made of a document's own content (CreateOfContent): the text is FBodyPieces (their
      separators' data held) with FLead paragraph marks before it and FTrail after it, until
      the first insert has put it in (FPieces then); FTabMin: the first row of each source
      table taken (a table made again has the rows taken only). }
    FBody: Boolean;
    FBodyPieces: TTyRichPieces;
    FLead: Boolean;
    FTrail: Integer;
    // the marks the first run inserted, as their pieces (what a redo puts back)
    FBodyRan: Boolean;
    FLeadPieces, FTrailPieces: TTyRichPieces;
    FTabMin: array of Integer;
    procedure AddMark;
    procedure DropBody;
    procedure OwnTables(AContent: TTyRichRangeContent);
    function MapOwnCell(ACell: TTyRichCell): TTyRichCell;
    procedure AddPart(AValue: TTyRichParaData; ALen: Int64; AOwn: Boolean);
    procedure InsertOwnFirst;
    procedure AddText(P: PByte; ALen: PtrInt);
    function MapChar(AId: TTyCharFormatId): TTyCharFormatId;
    function MapPara(AId: TTyParaFormatId): TTyParaFormatId;
    function MapExtra(const AExtra: TTyOpaqueAttrs; APara: Boolean): TTyOpaqueAttrs;
    function MapCell(ACell: TTyRichCell): TTyRichCell;
    procedure MapObjects(var AText: RawByteString; var ARuns: TTyRunArray; var AChars: Int64);
    procedure UnfieldOverParagraphs;
    procedure TakePara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    function PartCell(AIndex: Integer): TTyRichCell;
  public
    constructor Create(ATarget: TTyRichDocument; APos: TTyRichPos; ASource: TTyRichDocument;
      AEndsWithParagraph: Boolean; AFlatten: Boolean = False;
      AFilter: TTyRichFragmentFilter = nil);
    { AContent, a stretch of ATarget's own content, made ready to go in at APos (in ATarget
      as it is now: for a move, after its range went) by the same rules as a fragment of
      another document: the paragraphs' formats are their own already (the same pool), rows
      go in as rows where APos is in no table and as the text of the cell APos is in
      otherwise, and the paragraph mark the content ends with, or that a last row needs, is
      this document's. Tables are always made again: rows of their own (the rows taken, with
      their RawFormat), never the source's - two runs of paragraphs never share a table.
      AKeepObjects: the very objects go in (a move: undo and the file's bytes need that very
      one); otherwise a clone of each (a copy: a picture's clone shares its bytes, which are
      not copied - one whose bytes are its file's gets them as its own). The text is not copied: its pieces go in (unless AContent holds text). }
    constructor CreateOfContent(ATarget: TTyRichDocument; APos: TTyRichPos;
      AContent: TTyRichRangeContent; AKeepObjects: Boolean);
    destructor Destroy; override;
    { Parts (paragraph separators inserted + 1); 0: nothing to insert. }
    property PartCount: Integer read FCount;
    { The tables went in as plain paragraphs. }
    property Flattened: Boolean read FFlat;
    { Characters inserted (separators counted). }
    function CharCount: Int64;
    { Made of a document's own content: the pieces of its text, which it holds for every run
      (none when it holds text). }
    property BodyPieces: TTyRichPieces read FBodyPieces;
    { Every field mark it holds has its partner in it (TTyRichFieldMark): each close mark
      follows an open mark of its own, and no open mark is left. InsertFragment refuses one
      that is not so. }
    function MarksPaired: Boolean;
    { It holds a field mark, or a part that starts inside a field (one taken from a field's
      result): InsertFragment then works out the depth of every paragraph it makes. }
    function HoldsFields: Boolean;
    { Its text and values (the objects they bring: GatherObjects). }
    function MemSize: Int64;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
  end;

  { A change to a document, and the one way to make one: TTyRichDocument.Execute runs it and
    keeps it for undo. A subclass changes the document in DoExecute through the protected
    InsertText .. ReplaceObject below - they work only while the document runs this command, and
    each keeps what its primitive returned. So the inherited DoUndo (revert those records,
    newest first) and DoRedo (DoExecute again: after an exact undo the same arguments give
    the same result) are already right for a command that only calls them. }
  TTyRichCommand = class
  private
    FRecords: array of TTyRichUndoData;
    FRecordCount: Integer;
    FSummary: TTyRichChange;
    FChanged: Boolean;
    FDoc: TTyRichDocument;    // the document running this command, nil otherwise
    FMarks: TTyRichStepMarks;
    { The document's states (TTyRichDocument's saved point) before this step ran and after
      it: an undo goes back to the one, a redo forward to the other. }
    FStateBefore, FStateAfter: Int64;
    FOnFreed: TNotifyEvent;
    procedure CheckRunning(ADoc: TTyRichDocument);
    function Keep(AUndo: TTyRichUndoData): TTyRichChange;
    procedure AddSummary(const AChange: TTyRichChange);
    procedure ResetSummary;
    procedure FreeRecords;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); virtual; abstract;
    { Reverts the kept records, newest first. }
    procedure DoUndo(ADoc: TTyRichDocument); virtual;
    { Runs DoExecute again. }
    procedure DoRedo(ADoc: TTyRichDocument); virtual;

    { The document's primitives (see TTyRichDocument), for DoExecute. Each returns what the
      change did. Called when this command is not being run by ADoc, they raise. }
    function InsertText(ADoc: TTyRichDocument; APos: TTyRichPos; const AText: UTF8String;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichChange;
    function InsertObject(ADoc: TTyRichDocument; APos: TTyRichPos; AObject: TTyRichObject;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichChange;
    function DeleteRange(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): TTyRichChange; overload;
    { The same, APieces being the snapshot of the range taken of the text as it is now (the
      record keeps that very array - a command that holds it too keeps the pieces once). }
    function DeleteRange(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
      const APieces: TTyRichPieces): TTyRichChange; overload;
    function ApplyCharFormat(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
      AMask: TTyCharFormatMask; const AValue: TTyCharFormat;
      AKeepNone: TTyCharFormatMask = []): TTyRichChange;
    function ApplyParaFormat(ADoc: TTyRichDocument; AFirstPara, ALastPara: Integer;
      AMask: TTyParaFormatMask; const AValue: TTyParaFormat): TTyRichChange;
    function MarkTable(ADoc: TTyRichDocument; AFirstPara: Integer; ATable: TTyRichTable;
      const ACellParas: array of Integer): TTyRichChange;
    function InsertFragment(ADoc: TTyRichDocument; APos: TTyRichPos;
      AFragment: TTyRichFragment): TTyRichChange;
    function ReplaceInParas(ADoc: TTyRichDocument; const APos: array of TTyRichPos;
      AFrom, ACount: Integer; ALen: TTyRichPos; const AText: UTF8String;
      out ASkipped: Integer): TTyRichChange;
    function EditTableProps(ADoc: TTyRichDocument; const AEdit: TTyRichPropEdit): TTyRichChange;
    function EditTable(ADoc: TTyRichDocument; const AEdit: TTyRichTableEdit;
      var ATables: TTyRichTables): TTyRichChange;
    function ReplaceObject(ADoc: TTyRichDocument; APos: TTyRichPos;
      AObject: TTyRichObject): TTyRichChange;
    function ChangeSettings(ADoc: TTyRichDocument;
      const ASettings: TTyRichDocSettings): TTyRichChange;
    { A field's two marks put in or taken out as a pair, around content that is there already -
      the way a command makes a field of text or unmakes one (the primitives never take a mark
      alone). Each raises ETyRichModel before anything changes when the place does not allow
      it; what it does is a few records, reverted exactly.
      WrapInField: AOpen before the ALen characters at APos and AClose after them, both in
      AFormat (TyRichInheritFormat: the character's before APos). The range lies in one
      paragraph, outside every field's result (both ends; ETyRichRefused with Field
      otherwise), holds no field mark, and the text may change there (CanChange: a row that
      holds a nested table). The document takes a reference to each mark.
      UnwrapField: the two marks of the field whose open mark is at AOpenPos go, its content
      stays where it is (a field over paragraphs: the paragraphs after its first are as deep
      in fields as its start again). The field may not lie in another field's result.
      ReplaceFieldMarks: AOpen and AClose (a new identity of their own) in place of the two
      marks of the field whose open mark is at AOpenPos; its content stays. The same place
      rule as UnwrapField. }
    { The one object character at APos goes, whatever it belongs to - a bookmark's end alone
      (DeleteRange keeps a bookmark's end whose other end stays: TTyRichCommand.DeleteRange).
      The primitive's rules hold otherwise (a field's mark is refused). }
    function DeleteObjectAt(ADoc: TTyRichDocument; APos: TTyRichPos): TTyRichChange;
    procedure WrapInField(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
      AOpen, AClose: TTyRichFieldMark; AFormat: TTyCharFormatId = TyRichInheritFormat);
    procedure UnwrapField(ADoc: TTyRichDocument; AOpenPos: TTyRichPos);
    procedure ReplaceFieldMarks(ADoc: TTyRichDocument; AOpenPos: TTyRichPos;
      AOpen, AClose: TTyRichFieldMark);
    { One more part of this command's work, as part of the step it is
      (TTyRichDocument.ExecutePart): it changes the document through the primitives as DoExecute
      does; its records join the step's. The default raises: a command goes on only when it
      says how. }
    procedure DoContinue(ADoc: TTyRichDocument); virtual;
    { What the records from AFrom on keep (their MemSize), for a command that counts its own
      size as it goes. }
    function RecordsSize(AFrom: Integer): Int64;

    { For a command made of commands: runs, undoes or redoes AChild as part of this one, and
      counts its change as this command's. A child whose execute or redo raises is reverted
      first. }
    procedure ExecuteChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
    procedure UndoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
    procedure RedoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
    { Counts the change of AChild, which has already run, as this command's. }
    procedure AdoptChange(AChild: TTyRichCommand);
    { For TryMerge: takes ANext's records (they are reverted before this command's own) and
      its change. }
    procedure TakeOver(ANext: TTyRichCommand);
    property RecordCount: Integer read FRecordCount;
  public
    procedure BeforeDestruction; override;
    destructor Destroy; override;
    { Raised once, first thing when the command is freed - whoever frees it, and while it is
      still whole. The ways a command the history holds goes: the history cleared (ClearUndo,
      a new content, the document freed, a history dropped because an undo or a part of a
      step failed), its oldest steps let go for MaxUndoBytes, the redo side dropped by a new
      step or by a redo that failed, an undo that raised; and before it is the history's: a
      run that was refused, raised or changed nothing, a merge into the step before, an
      update's commands when the history is cleared inside it, a composite's parts with the
      composite. Whoever keeps a reference to a command beside the history sets this and
      gives the reference up in it. The handler is called from inside whatever frees the
      command: it must not change the document, nor run the application's handlers. }
    property OnFreed: TNotifyEvent read FOnFreed write FOnFreed;
    { False: Execute leaves the document alone and frees the command. }
    function CanExecute(ADoc: TTyRichDocument): Boolean; virtual;
    { ANext ran right after this command; True when this command took it over (TakeOver),
      and the history then frees ANext. }
    function TryMerge(ANext: TTyRichCommand): Boolean; virtual;
    { For the undo menu. }
    function Description: string; virtual;
    { The characters the command changed, in the document as it left it. }
    function ChangedRange: TTyRichRange;
    { Bytes the history keeps for it (MaxUndoBytes): its own - records, texts -, without the
      objects it holds, which GatherObjects names and the history counts once each however
      many steps hold them. }
    function MemSize: Int64; virtual;
    { Appends the objects this step keeps alive to AList (ACount used): those of its records;
      a command that holds an object itself adds it (TTyRichInsertObject, a fragment's, a
      composite's parts'). }
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); virtual;
    { Its last run changed something; one that did not is not kept in the history. }
    property Changed: Boolean read FChanged;
    { What its last execute or redo changed, composed as the document reports it (inside the
      document's update the observers hear it only as part of the block's one change, so a
      view that places its own edits there reads it here). Meaningful when Changed. }
    property Change: TTyRichChange read FSummary;
    { The selection of the view that made this step, before it and after it (see
      TTyRichStepMarks). The document never reads or changes them; TakeOver (a merge) keeps
      this command's Before and takes ANext's After. }
    property Marks: TTyRichStepMarks read FMarks write FMarks;
    { Another step went on top of this one in the history: it is not the top step any more,
      so it will not be continued (ExecutePart goes on with the top step only) - a command that
      holds what only its next part would need lets go of it here. Nothing by default. }
    procedure Covered; virtual;
  end;

  TTyRichKeyList = array of Int64;

  TTyRichHistoryEntry = record
    Cmd: TTyRichCommand;
    Bytes: Int64;                 // the step's own (MemSize)
    Objs: TTyRichObjectList;      // the distinct objects it holds, each counted in FObjHolds
    { The object keys (TTyRichParaData.FObjKey) of the values whose objects are in Objs: a
      value with one of them adds nothing when a merge brings it. }
    Keys: TTyRichKeyList;
  end;

  { How many steps of the history hold each object: an object counts toward the
    history's bytes once, while at least one step holds it. }
  TTyRichObjHolds = specialize TDictionary<Pointer, Integer>;
  // the object keys a gathering has met (or skips)
  TTyRichKeySet = specialize TDictionary<Int64, Boolean>;

  TTyRichDocument = class
  private
    // history
    FUndo: array of TTyRichHistoryEntry;
    FUndoCount: Integer;
    FRedo: array of TTyRichHistoryEntry;
    FRedoCount: Integer;
    FHistoryBytes: Int64;
    FHistoryObjectVisits: Int64;
    FObjHolds: TTyRichObjHolds;
    { How many of the objects the history holds share each block of data
      (TTyRichObject.SharedData): a block counts toward the history's bytes once, while one
      of them is held. }
    FDataHolds: TTyRichObjHolds;
    { A gathering of a step's objects (BeginGather .. EndGather): the keys met or skipped -
      a value whose key is here adds nothing -, the ones met first, and the next key. }
    FGathering: Boolean;
    FKeyMet: TTyRichKeySet;
    FGatherKeys: TTyRichKeyList;
    FGatherKeyCount: Integer;
    FNextObjKey: Int64;
    FMaxUndoBytes: Int64;
    FMergeBroken: Boolean;
    FRunning: TTyRichCommand;
    FUpdateCount: Integer;
    FBlock: array of TTyRichCommand;
    FBlockCount: Integer;
    FBlockDescription: string;
    FHold: Integer;
    FPending: TTyRichChange;
    FHasPending: Boolean;
    { The saved point: every content the document goes through has a number of its own
      (FState), never given twice (FNextState); FSavedState is the number of the content last
      loaded or saved (-1: none it can come back to). A step remembers the numbers before and
      after it, so an undo or a redo brings back the number with the content. }
    FState, FSavedState, FNextState: Int64;
    FModifiedSeen: Boolean;
    FOnModifiedChange: TNotifyEvent;
    function NewState: Int64;
    function GetModified: Boolean;
    procedure SetModified(AValue: Boolean);
    { The content changed outside the history (a primitive outside a command, an edit straight
      on Text, an undo that failed): a number of its own, and the saved point is gone. }
    procedure LeftHistory;
    { OnModifiedChange when Modified is not what it was when it was last raised. }
    procedure NoteModified;
    procedure RunStep(ACmd: TTyRichCommand; AStep: Integer);
    procedure Flush;
    procedure PushUndo(ACmd: TTyRichCommand);
    procedure HoldObjects(var AEntry: TTyRichHistoryEntry);
    procedure LetGoObjects(var AEntry: TTyRichHistoryEntry);
    { The history holds AObj from now on (AHold) or no longer: its bytes, its shared block's
      once (FDataHolds). }
    procedure CountHeld(AObj: TTyRichObject; AHold: Boolean);
    { A gathering that passes over the values whose key is in ASkip or met before in it;
      EndGather gives the keys it met. MeetKey: True the first time a key is met. }
    procedure BeginGather(const ASkip: array of Int64);
    function EndGather: TTyRichKeyList;
    function MeetKey(AKey: Int64): Boolean;
    { The distinct objects of AList[0..ACount) the step does not hold yet are held by it
      (counted once in the history's bytes), and AKeys join its keys: what a merge brings. }
    procedure HoldMore(var AEntry: TTyRichHistoryEntry; var AList: TTyRichObjectList;
      ACount: Integer; const AKeys: TTyRichKeyList);
    procedure DropOldestUndo;
    procedure ClearRedo;
    procedure ClearHistory;
    procedure TrimHistory;
    procedure SetMaxUndoBytes(AValue: Int64);
    procedure CheckIdle(const AWhat: string);
  private
    FText: TTyRichText;
    FFormats: TTyFormatPool;
    FDefaultCharFormat: TTyCharFormat;
    FDefaultCharId: TTyCharFormatId;
    FDefaultParaId: TTyParaFormatId;
    FDefaultRuns: TTyRunArray;
    FPaperWidth: Integer;
    FPaperHeight: Integer;
    FMarginLeft: Integer;
    FMarginRight: Integer;
    FDocumentColor: TColor;
    { The shared plain value (FPlainParsed) keeps the formats it had when the defaults changed
      (its own runs and format id, not the defaults'): ChangeSettings. }
    FPlainFrozen: Boolean;
    FOnChange: TTyRichChangeEvent;
    FOnUpdatingEnd: TNotifyEvent;
    FLoader: TTyRichParaLoader;
    FOwnsLoader: Boolean;
    FInLoad: Boolean;
    FPlainParsed: TTyRichParaData;
    FFirstData: TTyRichParaData;
    FLiveData: Integer;
    FEditing: Integer;
    FReading: Integer;
    FValuesGone: Boolean;
    FSourceEncoding: TTyTextEncoding;
    FSourceCodePage: Integer;
    FSourceHasBom: Boolean;
    FDominantLineBreak: TTyRichSeparator;
    FKnownRemoved: TTyRichPieces;
    FLoadingContent: Boolean;
    FIncomplete: Boolean;
    FSaving: Integer;
    FBaseFontName: string;
    FBaseFontSizeHalfPt: Integer;
    FTableParaVisits: Int64;
    FTableEditSteps: Int64;
    FPropsSkipped: Integer;
    { The rows a property edit's refusal read (a TTyRichShape on the heap, nil none), for the
      edit itself when it runs at once after it - a command's CanExecute and then its work, with
      nothing changed between (ContentState as it was, the same edit): a column's edge in ten
      thousand rows reads them once. }
    FPropShape: Pointer;
    FPropShapeState: Int64;
    FPropShapeEdit: TTyRichPropEdit;
    { A command's pair of field marks is going in or out (TTyRichCommand.WrapInField and its
      siblings, which ask the field rule themselves first): the primitives do not refuse a
      mark or a place for the field rule meanwhile - only for a row's. }
    FMarkEdit: Integer;
    { Paragraphs AFirst..ALast start ADelta fields deeper than they did: the field around
      them lost its marks (UnwrapField). One record of their old values. }
    function ShiftFieldDepths(AFirst, ALast, ADelta: Integer): TTyRichUndoData;
    function GetSaving: Boolean;
    function GetUpdating: Boolean;
    procedure Init;
    procedure ResetContent(AText: TTyRichText; AEncoding: TTyTextEncoding; ACodePage: Integer;
      AHasBom: Boolean; ALineBreak: TTyRichSeparator);
    procedure SetDefaults(const AFormat: TTyCharFormat);
    procedure SetDefaultPara(const AFormat: TTyParaFormat);
    procedure SetDefaultPage;
    procedure PutSettings(const ASettings: TTyRichDocSettings);
    procedure TextParasChanged(Sender: TObject; AFirst, AOldCount, ANewCount: Integer);
    procedure TextDataDropped(Sender: TObject; AData: Pointer);
    // (MapParaData: an empty slot, its reference not counted - the caller's to put right)
    function NoDataMap(AIndex: Integer; AData: Pointer): Pointer;
    // paragraph values
    function NewData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      ACell: TTyRichCell; AFieldDepth: Integer = 0): TTyRichParaData;
    procedure DisposeData(D: TTyRichParaData);
    procedure AcquireData(D: TTyRichParaData);
    procedure ReleaseData(D: TTyRichParaData);
    function PlainValue: TTyRichParaData;
    function MakeData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      ACell: TTyRichCell; AFieldDepth: Integer = 0): TTyRichParaData;
    // fields: the depth a value gives its paragraph's start, and at its end
    function DepthOfData(D: TTyRichParaData): Integer; inline;
    function EndDepthOfData(D: TTyRichParaData): Integer;
    { D with AFieldDepth: D itself when it has it; a value no one holds yet, given it; else a
      new value like D with it (not held). }
    function WithDepth(D: TTyRichParaData; AFieldDepth: Integer): TTyRichParaData;
    { Paragraph AFirst starts AStartDepth fields deep, and each up to ALast as deep as the one
      before it leaves: the values an edit made there are given the depths its text makes. }
    procedure FixDepths(AFirst, ALast, AStartDepth: Integer);
    { The fields open at position APos (the paragraph's start depth and the marks before APos
      in it), with the paragraph's value; parses that paragraph. }
    function DepthAt(APos: TTyRichPos): Integer;
    { Paragraph AIndex's fields: how many are open at its start, and the fewest open anywhere
      in it (start and end included) - from its value when it has one, else from the
      loader's index (TTyRichParaLoader.ParaFieldDepths) without parsing it. }
    procedure ParaDepths(AIndex: Integer; out AStart, ALow: Integer);
    function MakeDataLike(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      ACell: TTyRichCell; AFrom: TTyRichParaData): TTyRichParaData;
    procedure PutData(AIndex: Integer; AOld, ANew: TTyRichParaData);
    function SlotData(AIndex: Integer): TTyRichParaData;
    function DataOf(AIndex: Integer): TTyRichParaData;
    function RunsOfData(D: TTyRichParaData): TTyRunArray; inline;
    function FormatOfData(D: TTyRichParaData): TTyParaFormatId; inline;
    function CellOfData(D: TTyRichParaData): TTyRichCell; inline;
    procedure ClipRuns(AIndex: Integer);
    // edits
    function NewUndo(const AChange: TTyRichChange): TTyRichUndoData;
    procedure Notify(const AChange: TTyRichChange);
    function InsertCore(APos: TTyRichPos; const AText: UTF8String; AFormat: TTyCharFormatId;
      AObj: TTyRichObject): TTyRichUndoData;
    procedure CheckCharId(AId: TTyCharFormatId);
    procedure CheckParaId(AId: TTyParaFormatId);
    function DeleteCore(APos, ALen: TTyRichPos): TTyRichUndoData;
    { (DeleteRange's snapshot of what it removes, when the caller has it already: the same
      pieces, taken of the same text - a move keeps one array of them, not two) }
    function DeleteKnownRange(APos, ALen: TTyRichPos; const APieces: TTyRichPieces): TTyRichUndoData;
    function FixedData(D: TTyRichParaData): Boolean; inline;
    function FixedRowAt(AIndex: Integer): TTyRichRow;
    function RowAt(AIndex: Integer): TTyRichRow;
    function ChangeRefused(APos, ALen: TTyRichPos): Boolean;
    function RowRefused(APos, ALen: TTyRichPos): Boolean;
    function FieldRefused(APos, ALen: TTyRichPos): Boolean;
    // the primitives' refusal, with its reason
    procedure RaiseRefused(APos, ALen: TTyRichPos);
    procedure RevertSwaps(AUndo: TTyRichUndoData);
    // table rows (TTyRichTable's FRows)
    function SpliceRows(ATable: TTyRichTable; AAt, AOldCount: Integer;
      const ANew: array of TTyRichRow; ANewValid: Boolean): TTyRichUndoData;
    procedure RevertRows(AUndo: TTyRichUndoData);
    procedure RowsLost(AFirst: Integer; AOld: TTyRichParaData; const ARemoved: TTyRichPieces);
  protected
    { The modification primitives. Each changes the document, raises OnChange, sets Modified
      and returns what Revert needs to undo it exactly (never nil; a no-op returns an empty
      record and notifies nothing). Undo records must be reverted in the reverse order they
      were made. A redo runs the primitive again.

      A row that holds a nested table (TTyRichRow.HoldsNestedTable) stays as it is:
      InsertText, InsertObject and DeleteRange raise ETyRichModel, before anything changes,
      when they would change a paragraph of such a row or take away a part of the row
      (CanChange says which); ApplyCharFormat and ApplyParaFormat leave the paragraphs of
      such rows as they are and change the rest of their range.

      A field's result (TTyRichFieldMark) is read-only in the same way: InsertText,
      InsertObject, InsertFragment, ReplaceObject and DeleteRange raise ETyRichRefused (Field)
      before anything changes for a place inside a result or a range that would take one mark
      of a field and not the other (CanChange); ApplyCharFormat leaves the marks and the
      characters of results as they are and formats the rest of its range; ApplyParaFormat
      leaves a paragraph whose paragraph mark is inside a result (ParaEndsInField); the
      replace of many matches keeps those inside results. A field mark is never inserted
      or replaced on its own (InsertObject, ReplaceObject raise); marks come into a
      document with a reader's paragraphs or a fragment that holds both marks of each of
      its fields (InsertFragment raises for one that does not). }

    { AText may hold paragraph separators. A split gives every part the paragraph's format and
      cell; the runs split at APos. AFormat: a character format id, or TyRichInheritFormat.
      AText must not start with a byte that continues a UTF-8 sequence nor end inside one
      (raises ETyRichModel before anything changes): the storage would count those bytes as
      other characters than a reader of the paragraph's bytes does. A byte that is no text
      inside it (a stray continuation in the middle) is a character of its own, as in a file. }
    function InsertText(APos: TTyRichPos; const AText: UTF8String;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichUndoData;
    { Inserts the object's U+FFFC; the document takes a reference to AObject. }
    function InsertObject(APos: TTyRichPos; AObject: TTyRichObject;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichUndoData;
    { Across paragraphs (as WordPad): the merged paragraph takes the format of the paragraph
      the range ends in, except when the range is one separator and nothing else and the
      paragraph before it is not empty - then the format of that paragraph. (The separator
      of an empty paragraph takes the empty paragraph away: what follows stays as it is.) }
    function DeleteRange(APos, ALen: TTyRichPos): TTyRichUndoData;
    { Changes only the AMask fields of every run in the range (an empty paragraph whose
      separator is in the range: its one run). Paragraphs of a row that holds a nested
      table are passed over. AKeepNone (cffFontName, cffSize): a run that has no name / size
      of its own keeps none - for a view that writes the value such text is shown in, which
      it shows already (the base's value is not frozen into it). }
    function ApplyCharFormat(APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat; AKeepNone: TTyCharFormatMask = []): TTyRichUndoData;
    { Paragraphs of a row that holds a nested table are passed over. }
    function ApplyParaFormat(AFirstPara, ALastPara: Integer; AMask: TTyParaFormatMask;
      const AValue: TTyParaFormat): TTyRichUndoData;
    { Makes the paragraphs from AFirstPara on a table: ACellParas[i] paragraphs for each cell,
      row by row. ATable must not be in use; the paragraphs must not be in a table. }
    function MarkTable(AFirstPara: Integer; ATable: TTyRichTable;
      const ACellParas: array of Integer): TTyRichUndoData;
    { Inserts AFragment (made for this document at APos) at APos: its text in one insert, then
      its parts' values in the paragraphs it made. How a part meets the paragraph at APos - the
      paragraph format goes with the paragraph's end, as in Word: a paragraph that ends with a
      paragraph mark of the fragment has that paragraph's format, one that ends with a mark of
      this document has its own. So part 0 joined with the text before APos takes part 0's
      format (unless the fragment is one part: inline, the paragraph keeps its own), the last
      part joined with the text after APos keeps the paragraph's format and cell, and the
      parts between are the fragment's paragraphs. Runs: the text before APos keeps its runs,
      each part's follow, then the text after APos. One undo record, of an insert's size: a
      revert deletes the inserted characters and gives the paragraph at APos its value back.
      Refused (ETyRichModel, before anything changes) inside a row that holds a nested table. }
    function InsertFragment(APos: TTyRichPos; AFragment: TTyRichFragment): TTyRichUndoData;
    { Replaces the matches APos[AFrom .. AFrom + ACount - 1] - rising, none overlapping, each
      inside one paragraph (no separator in it) - of ALen characters each by AText (no
      separator either), each in the format of the first character it replaces; the
      paragraphs' formats, cells and objects stay. A paragraph of a row that holds a nested
      table keeps its matches (ASkipped counts them). One record for all of them, small:
      for each paragraph changed its pieces before and its value before - references, no
      text: a few dozen bytes a paragraph however many matches it holds. Matches closer
      than a few hundred characters are one stretch of the text: what lies between them is
      copied with the replacements, so the text keeps few pieces. Revert gives each
      paragraph its pieces and its value back (a lazily read one is its file's bytes again,
      so that an edit undone saves the file as it was; the paragraph after it the value it
      had). For a replace of every match
      (tyControls.RichEdit.Find's TTyRichReplaceAllCommand). Raises ETyRichModel for
      matches out of order or range, a separator in them or in AText, before anything
      changes. }
    function ReplaceInParas(const APos: array of TTyRichPos; AFrom, ACount: Integer;
      ALen: TTyRichPos; const AText: UTF8String; out ASkipped: Integer): TTyRichUndoData;
    { Makes the table edit AEdit, which TableEditRefusal allows (raises ETyRichRefused before
      anything changes otherwise). One record for the whole edit, made of the edits it is:
      the new rows' and cells' paragraphs inserted, the deleted ones' deleted (whole
      paragraphs: the paragraphs around them keep their text and values), and every
      paragraph that stays in the table given its cell in a new table object - so the
      table of the range has exactly the rows that have paragraphs, in order, and every
      cell of it at least one paragraph (rows a plain delete left with no paragraph are
      not taken along). An undo gives every paragraph its value back, and with it the cell
      of the very table it was in.
        rtkInsertTable: at a paragraph's start the table goes before the paragraph; in the
      middle of one, or at the end of the text after text, the paragraph is split and the
      table goes between its parts; directly after another table a paragraph in no table
      comes first (two tables never touch). A paragraph in no table follows it always. Its
      columns have equal widths, the last edge at the width exactly; each cell holds one
      empty paragraph in the formats in effect at APos (its paragraph's format without a
      list and with no indents; the character format typing there gets). Its rows are
      given a format of their own: single lines of 10 twips on every side of every cell,
      Word's half gap (TyRtfGridRowFormat), so it looks the same here, in a file and in
      other programs.
        rtkInsertRow: the new row is the row beside it (the one above; for index 0 the one
      below) again: its cells, edges and format; each cell one empty paragraph in the
      formats of the first paragraph of the matching cell there.
        rtkDeleteRow: the row's paragraphs go; the last row takes the table with it (what
      is left there, when the table ended the text, is one empty paragraph in no table).
        rtkInsertColumn / rtkDeleteColumn: in every row (all have as many cells). A new
      column is as wide as the cell it is put beside (the one left of it; for index 0 the
      one right of it), and the edges after it move right by that; a deleted one's width is
      taken out of the edges after it. A row's format keeps the words of each cell that
      stays and of the row as they were, only the edges change; a new cell has the words of
      the cell it is put beside (TyRtfSplitRowFormat; a format that cannot be split so is
      replaced by TyRtfGridRowFormat). A new cell's paragraph is formatted like the first
      paragraph of the cell beside it. Deleting the only column deletes the table.
      ATables: the table objects the edit made, kept by the command for its redo: empty, it
      gets them (one reference each, the caller's); given, they are used again when they
      fit. The rows of an edit of rows are those of the file still (TTyRichDocument's
      ValueSource), so a writer keeps the bytes of the rows the edit did not make. Costs:
      the table's paragraphs are visited twice (read, and given their cells), the new ones
      made; nothing outside the table is read. }
    function EditTable(const AEdit: TTyRichTableEdit; var ATables: TTyRichTables): TTyRichUndoData;
    { Sets the properties AEdit names on its rows or cells (TTyRichPropEdit): each row whose
      format changes is given a new row object in the same table with that format (and, for a
      width or a row's left, its edges), its paragraphs the cells of it; no other paragraph
      is touched, and nothing of the table is read but the paragraphs between AEdit.Pos and
      those rows. A writer makes such a row's definition again from its file's bytes: the
      words of what changed, every other word as it was. Raises ETyRichRefused, before
      anything changes, when TablePropsRefusal is not rtrNone. }
    function EditTableProps(const AEdit: TTyRichPropEdit): TTyRichUndoData;
    { The object whose character is at APos is replaced by AObject (the document takes a
      reference to it): the text, the run's character format and everything else of the
      paragraph stay. One record of the paragraph's old value (a revert puts the very object
      back); reported as a format change of that one character. AObject the object already
      there: no change. Raises ETyRichModel, before anything changes, when there is no object
      at APos or the paragraph is one of a row that holds a nested table (CanChange). }
    function ReplaceObject(APos: TTyRichPos; AObject: TTyRichObject): TTyRichUndoData;
    { The document's settings become ASettings (the page, the defaults, the ground), all at
      once: one record of the settings before. Reported as a format change of the whole text
      when anything differs (a page-wide layout wraps elsewhere, a plain paragraph looks
      otherwise, the ground is another), nothing otherwise. A paragraph with nothing of its own
      in a document that is not read on demand shows in the new defaults; in one that is (a
      file's), what was read keeps its look - read already or not - and paragraphs made in
      the new defaults later have them: the value parsed plain paragraphs share keeps the
      formats it had (FPlainFrozen) until the record that froze it is reverted. Formats with
      an Extra are taken as given. Raises ETyRichModel for a page whose margins leave no
      text width. }
    function ChangeSettings(const ASettings: TTyRichDocSettings): TTyRichUndoData;
    { Puts back what the primitive that returned AUndo changed, frees AUndo and sets it nil. }
    procedure Revert(var AUndo: TTyRichUndoData);
    { The paragraph's data value (an opaque identity, for tests and the history). }
    function ParaDataOf(AIndex: Integer): Pointer;
    function IsLiveParaData(AData: Pointer): Boolean;
    property LiveParaData: Integer read FLiveData;
  public
    constructor Create;
    { The buffer is referenced, not copied (TTyRichText.CreateFromUtf8). }
    constructor CreateFromUtf8(const ABuffer: TBytes);
    { Takes ownership of AText, e.g. a lazy text from the RTF scan. }
    constructor CreateOnText(AText: TTyRichText);
    destructor Destroy; override;

    { Install right after creating the document, before anything reads it. }
    procedure InstallLoader(ALoader: TTyRichParaLoader; AOwnsLoader: Boolean);
    procedure EnsureParsed(AIndex: Integer);
    { A read scope, counted (BeginRead .. EndRead may nest; pair them with try .. finally).
      In a document that parses on demand, a read may send paragraphs read earlier back to
      unparsed, and the tables, cells and objects they gave out go with them: what TableAt,
      CellAt or a run's Obj returned is good until the next read. Inside a read scope nothing
      is sent back, and a load into the document is refused (ETyRichModel): everything read
      stays as it was returned until the outermost EndRead.
      So whoever holds a table, a cell or an object across another read does it inside one -
      a layout pass over the visible paragraphs, a save, TableParas and CellParas themselves.
      (Format ids, RunsOf's copy and text are values: they need no scope. A running command
      is a scope by itself.) A scope costs nothing to open; keep it as short as the pass it
      protects: parsed paragraphs only pile up while it is open. }
    procedure BeginRead;
    procedure EndRead;
    { A save is in progress, counted (pair them with try .. finally; the writers do it
      themselves). A save plans with the paragraphs as they are when it starts, and its
      progress callback or its stream may let the application run - so in between nothing
      may change the document: Execute returns False, Undo and Redo do nothing (CanUndo and
      CanRedo are False), as while the document is Loading, and a load into it (any reader's,
      through TTyRichDocBuilder.ReplaceText) raises ETyRichModel and leaves it as it was.
      Reading is fine. }
    procedure BeginSave;
    procedure EndSave;

    function ParaFormatOf(AIndex: Integer): TTyParaFormatId;
    { A copy: the paragraph's runs. A plain paragraph has one run in DefaultCharFormatId. }
    function RunsOf(AIndex: Integer): TTyRunArray;
    { The format text typed at APos gets. }
    function TypingFormatAt(APos: TTyRichPos): TTyCharFormatId;
    function TableAt(AIndex: Integer): TTyRichTable;
    function CellAt(AIndex: Integer): TTyRichCell;
    { The object whose character is at APos; nil when there is none (or APos is outside the
      text). Parses that paragraph; good until the next read (see BeginRead). }
    function ObjectAt(APos: TTyRichPos): TTyRichObject;
    { The paragraph range of the table AIndex is in; False outside a table. Walks the table's
      paragraphs. }
    function TableParas(AIndex: Integer; out AFirst, ALast: Integer): Boolean;
    { The paragraph range of ACell, a cell of the table AIndex is in. Walks the paragraphs
      between AIndex and the cell. In a document that parses on demand, read ACell and call
      this inside one read scope (BeginRead). }
    function CellParas(AIndex: Integer; ACell: TTyRichCell; out AFirst, ALast: Integer): Boolean;
    { What a paragraph's value holds, for a reader that walks the text itself and has the
      value from the walk (AData of TTyRichText.WalkParas and WalkParaTexts): the
      paragraph's format, runs and cell with no lookup, nothing parsed, and without the
      loader hearing of a read. A paragraph with no value (AData nil) is plain - but in a
      document that parses on demand it is one not parsed yet: False then, and the caller
      reads it by its index (ParaFormatOf, RunsOf, CellAt), which parses it. ARuns is the
      value's own array, not a copy: it is not to be changed. What is returned is good
      while the value is the paragraph's: until the document is changed, and for a cell or
      an object inside a read scope (BeginRead). A walk that asks for values (WalkParaTexts
      with AValues) hands an unparsed paragraph of a reader that parses on demand a value
      of the moment instead of nil: True for it, and what it gives is good during that call
      only - a cell or an object kept past it needs a reference of its own (a cell's
      table's AddRef); the paragraph stays unparsed. }
    function ReadValue(AData: Pointer; out AFormat: TTyParaFormatId; out ARuns: TTyRunArray;
      out ACell: TTyRichCell): Boolean;
    { The marker text the file gave list paragraph AIndex - its {\listtext ...} or {\pntext ...},
      decoded as the reader decodes text, the tab and spaces at its end dropped: the number
      Word or WordPad showed ("2.", "iii)"). '' when the file gave none, for a document not
      read from RTF, and for a paragraph an edit made (inserted, the later parts of a split);
      an edit inside a paragraph (typing, a format, a split's first part, a join's first
      paragraph) keeps it, and an undo brings back what it had - the value; whether a layout
      shows it is the layout's business (TTyRichLayouter stops trusting the markers from a
      change that can renumber on, and an undo does not bring that trust back). Read only: it
      is not written (a paragraph written back as its bytes has its own; one written from the model gets
      the marker the writer generates), takes no part in format equality, and goes with the
      paragraph's value when a document that parses on demand lets the paragraph go. Parses
      the paragraph (as RunsOf). }
    function ListTextOf(AIndex: Integer): UTF8String;
    { The same from a value of a walk (AData as ReadValue takes it): no lookup, nothing
      parsed; '' for none. }
    function ValueListText(AData: Pointer): UTF8String;
    { May the text change here: False when inserting at APos (ALen 0) or deleting ALen
      characters from APos would be refused because of a row that holds a nested table
      (TTyRichRow.HoldsNestedTable). Inserting is refused inside a paragraph of such a row.
      Deleting is refused when a paragraph of such a row would lose characters or be joined
      with another, or when the row would lose some of its paragraphs but not all: a range
      that takes whole such rows away, with whatever is around them, is fine. A range that
      is not inside the text is not this question (True; the primitive raises). Parses the
      paragraphs at the range's ends. A command asks this in CanExecute; the insert and
      delete commands do.
      A field's result (TTyRichFieldMark) is read-only too: inserting is refused at a place
      inside one (after its open mark, up to and with the place before its close mark), and
      deleting is refused when either end of the range is such a place - a range whose two
      ends are outside every field holds whole fields, both marks and all between them, and
      may go. ChangeRefusal says which rule refused. }
    function CanChange(APos, ALen: TTyRichPos): Boolean;
    { Why inserting at APos (ALen 0) or deleting ALen characters there is refused - rcrNone:
      it is not (CanChange). A place in a row that holds a nested table answers rcrFixedRow
      before the field rule is asked. }
    function ChangeRefusal(APos, ALen: TTyRichPos): TTyRichChangeRefusal;
    { Fields: how many are open at position APos - 0 outside every field's result. A place
      right before an open mark or right after a close mark is outside that field; one right
      after an open mark or right before a close mark is inside it. Parses APos's paragraph
      and walks its runs (its value knows the depth at its start: no other paragraph is
      read). }
    function FieldDepthAt(APos: TTyRichPos): Integer;
    { The fields open at paragraph AIndex's start (its value's; parses it). }
    function ParaFieldDepth(AIndex: Integer): Integer;
    { Paragraph AIndex's fields without parsing it: how many are open at its start, and the
      fewest open anywhere in it (its start and its end included) - from its value when it
      has one, else from the loader's index. A paragraph with both above 0 lies wholly inside
      a field's result: a writer that writes that field as its bytes need not read it. }
    procedure ParaFieldDepths(AIndex: Integer; out AStart, ALow: Integer);
    { Paragraph AIndex holds a field's mark: from its value when it has one, else from the
      loader's index (nothing parsed), else it is parsed. }
    function ParaHoldsMarks(AIndex: Integer): Boolean;
    { The same of paragraph AIndex whose value (as a walk of the paragraphs hands it out,
      nil: not parsed) is AData - no look-up of the paragraph for a value. }
    procedure ValueFieldDepths(AData: Pointer; AIndex: Integer; out AStart, ALow: Integer);
    { The innermost field whose result APos is inside: the positions of its open mark and its
      close mark. False outside every field. The cost: APos's paragraph and the two marks'
      paragraphs are read (parsed when the document is read on demand); the paragraphs between
      are passed over by their depths (ParaDepths: a look-up each, in the loader's index for
      one not parsed) - a field of N paragraphs is N look-ups and at most three paragraphs
      read. A caller that asks per key keeps the answer until the document changes. }
    function FieldRangeAt(APos: TTyRichPos; out AOpen, AClose: TTyRichPos): Boolean;
    { The position of the other mark of the field whose mark stands at AMarkPos; -1 when no
      field mark stands there. The mark's paragraph and its partner's are read, the paragraphs
      between looked up by their depths (as FieldRangeAt). }
    function FieldPartner(AMarkPos: TTyRichPos): TTyRichPos;
    { Every character of [APos, APos + ALen) is a field's - a mark, or a character of a
      result: a character format change there changes nothing (ApplyCharFormat passes them
      over). False for an empty range. Walks the range's paragraphs' runs. }
    function FieldOnly(APos, ALen: TTyRichPos): Boolean;
    { Paragraph AIndex ends inside a field's result (its paragraph mark is the result's): a
      paragraph format change passes it over (ApplyParaFormat). }
    function ParaEndsInField(AIndex: Integer): Boolean;
    { The one place of the rule that a user's edit never joins text across a cell's or a
      row's edge (a change of a table's structure is a table edit's: EditTable): may
      [AStart, AStart + ALen) be
      deleted or replaced as a user's edit - a key, the menu, a find's replace? The paragraph
      the deletion then joins with counts: the range INCLUDING the paragraph after it must not
      cross a cell's or a row's edge, unless it is whole rows (WholeRows). A range that begins
      outside a table and ends exactly where the table's first row starts keeps its last
      separator (ALen one less: the paragraph before the table stays, Word's way) - a caller
      that cannot take a shorter range treats that as a refusal. False: refused. Reads the
      cells inside a read scope of its own. }
    function UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
    { [AFrom, ATo) is whole rows of one table: from a row's first paragraph's start to the
      start of the paragraph after a row (never the text's end). Call it inside a read scope. }
    function WholeRows(AFrom, ATo: TTyRichPos): Boolean;
    { APos is the start of its paragraph, or only zero-width marks (a bookmark's, a field's)
      lie between that start and it - where a place set at a bookmark's start rests. }
    function AtParaStart(APos: TTyRichPos): Boolean;

    { Why AEdit cannot be made (TTyRichTableRefusal; rtrNone: it can) - what a table
      command's CanExecute asks, and what a view greys its table actions by. Reads inside
      a read scope of its own: the paragraph at the position and, for an edit of a table,
      the table's paragraphs (a table a loader gives in parts, the parts). }
    function TableEditRefusal(const AEdit: TTyRichTableEdit): TTyRichTableRefusal;
    { Where paragraph APara is in its table, rows counted as the table edits count them
      (those that have paragraphs; a table given in parts that its loader can give whole,
      as one). False outside a table. Walks the table's paragraphs once, inside a read scope
      of its own (TableParaVisits counts them): use it inside one when the answer is used
      with other reads. }
    function TableInfoAt(APara: Integer; out AInfo: TTyRichTableInfo): Boolean;
    { The paragraphs of cell ACell of row ARow (counted as TableInfoAt counts them) of the
      table paragraph ATablePara is in. False when there is no such cell, or the cell has no
      paragraph. One walk of the table's paragraphs. }
    function TableCellParas(ATablePara, ARow, ACell: Integer; out AFirst, ALast: Integer): Boolean;
    { Rows ARow0 .. ARow1 (cut to the table's) of the table APos is in, counted as the table
      edits count them, AFirstRow the first's index and ARowCount the table's rows (a table a
      loader gives in parts that it cannot give whole: the part's). The row objects are good
      inside a read scope - call it inside one. A window of the rows when they are known, else
      one walk of the table's paragraphs. False in no table. }
    function TableRowsAt(APos: TTyRichPos; ARow0, ARow1: Integer; out ARows: TTyRichRowList;
      out AFirstRow, ARowCount: Integer): Boolean;
    { Why AEdit cannot be made (rtrNone: it can): rtrReadOnly, rtrNoTable, rtrOutOfRange (rows
      or cells out of range, ARow0 > ARow1, ACol0 > ACol1), rtrNestedTable (every row named
      holds a nested table: such a row is only its file's bytes - one among others is left as
      it is, PropsSkipped counts it), rtrMergedCells (a width or a
      row's left, which move edges, on a table with merged cells). A table a loader gives in
      parts that it cannot give whole counts its rows in the part APos is in: its other parts
      are not read. }
    function TablePropsRefusal(const AEdit: TTyRichPropEdit): TTyRichTableRefusal;
    { The properties of cell ACol of row ARow (counted as TableInfoAt counts them) of the
      table ATablePos is in: every field valid (the padding the cell takes - its own, else
      its row's; the width from the row's edges). Valid empty: no such cell. Reads no
      paragraph of the table but the one at ATablePos while the table's rows are known
      (TTyRichTable's row list, put right by every table edit); otherwise one walk of it. }
    function CellProps(ATablePos: TTyRichPos; ARow, ACol: Integer): TTyRichCellProps;
    { Row ARow's properties, as CellProps finds the row; Valid empty: no such row. }
    function RowProps(ATablePos: TTyRichPos; ARow: Integer): TTyRichRowProps;
    { The row paragraph APara is in, counted as the table edits count them, and how many rows
      its table has (a table a loader gives in parts and cannot give whole: in its part).
      False outside a table. Reads one paragraph while the table's rows are known; otherwise
      one walk of the table. }
    function TableRowIndex(APara: Integer; out ARow, ARowCount: Integer): Boolean;
    { The width the text has on the page, in twips: the paper's width less the left and the
      right margin (what a page-wide layout wraps at). A table made without a width of its
      own is this wide. }
    function TextWidthTwips: Integer;
    { For a writer: AData (a paragraph's value) was made by a table edit that only gave the
      paragraph a cell of a new table object, in a row that is the same as the row of the
      value it was given in place of - the same format, cells, edges, the same cell. The
      first such value: the paragraph is that value's paragraph, as far as its file is
      concerned (the very row of the very table in the file). nil: none (also for nil). }
    function ValueSource(AData: Pointer): Pointer;
    { Table paragraphs the table edits and readers looked at, for the tests that count them. }
    property TableParaVisits: Int64 read FTableParaVisits write FTableParaVisits;
    { The table edits' own steps (a cell matched, an edit planned and applied), for the tests
      that hold them linear in the table. }
    property TableEditSteps: Int64 read FTableEditSteps write FTableEditSteps;
    { Rows a table properties edit left as they were because they hold a nested table, counted
      as the edits run (a caller sets it to 0 before and reads it after). }
    property PropsSkipped: Integer read FPropsSkipped write FPropsSkipped;

    { Runs ACmd and keeps it for undo; the document owns ACmd from here on, also when this
      returns False or raises. False: ACmd.CanExecute said no, or the document is Loading,
      Incomplete or Saving, and nothing changed. A command that changed nothing is not kept.
      Consecutive typing merges into one step until
      BreakMerge, an Undo or Redo, or any other command. A new command drops the redo side.
      Outside BeginUpdate .. EndUpdate it raises OnChange once. Raises inside a running
      command; if ACmd raises, what it did is reverted first. }
    function Execute(ACmd: TTyRichCommand): Boolean;
    { One step back / forward, one OnChange. Nothing to undo / redo, or the document is
      Saving: nothing happens. They raise inside BeginUpdate .. EndUpdate or a running
      command. }
    { Runs one more part of ACmd (TTyRichCommand.DoContinue) as part of the step it is: the
      work of a command that runs in parts - a replace of every match, range by range - is
      one undo step, never merged with another, the document consistent and reported
      between two parts. ACmd must be the newest undo step and the content the one it left:
      nothing changed since (no edit, undo or redo; the redo side empty), no saved point set
      on it since (Modified := False, a save: the step would carry its "after" past it), no
      update block open, the document not loading, incomplete or saving. Otherwise False,
      and nothing ran - nothing of the part is anywhere, the redo side included. True: the
      part ran; what it changed is reported (one OnChange) and joins the step (its bytes,
      its objects; the history trimmed as after any step). If the part raises, what it did
      is reverted and the step is as it was (were the revert to fail, the history goes, as
      for a failed undo). BreakMerge does not stop it: the step merges with nothing. }
    function ExecutePart(ACmd: TTyRichCommand): Boolean;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { Every undo and redo step goes; the content stays as it is (not Modified by it). Raises
      inside BeginUpdate .. EndUpdate or a running command. }
    procedure ClearUndo;
    function UndoDescription: string;    // '' when there is nothing
    function RedoDescription: string;
    { The step Undo takes back next / Redo puts in next (nil: none), for a view that keeps its
      selection with the step it made (TTyRichCommand.Marks). The history owns it: it is
      good until the history changes. }
    function UndoStep: TTyRichCommand;
    function RedoStep: TTyRichCommand;
    { Nested. The commands executed until the outermost EndUpdate become one undo step
      (TTyRichCompositeCommand, described by ADescription of the outermost BeginUpdate, or by
      its only command), and that EndUpdate raises the block's one OnChange covering all of
      it. A block that changed nothing keeps nothing and raises nothing. }
    procedure BeginUpdate(const ADescription: string = '');
    procedure EndUpdate;
    { True while the document holds its changes back from OnChange: from BeginUpdate to the
      outermost EndUpdate, and while a command (or an undo or redo step) runs. The text may
      then differ from what an observer last heard of: a view must not look its blocks up by
      what it knows until the change is reported (it is False again inside that OnChange). }
    property Updating: Boolean read GetUpdating;
    { Updating turned False: raised at the outermost EndUpdate and at the end of a command's,
      an undo's or a redo's run (outside an update), after the OnChange that reports what
      changed - also when nothing changed and nothing was reported. Updating is False inside
      it. What an observer put off while the document held its changes back is done here. }
    property OnUpdatingEnd: TNotifyEvent read FOnUpdatingEnd write FOnUpdatingEnd;
    { The caret moved: the next typing does not merge with the typing before. }
    procedure BreakMerge;
    property UndoDepth: Integer read FUndoCount;
    property RedoDepth: Integer read FRedoCount;
    { What the undo and redo steps keep, as their MemSize when they were stored. }
    property HistoryBytes: Int64 read FHistoryBytes;
    { Object references the history's byte count looked at (for tests that check it takes
      one pass: a step's count is done when the step is stored). }
    property HistoryObjectVisits: Int64 read FHistoryObjectVisits write FHistoryObjectVisits;
    { The history's limit: past it the oldest undo steps go, never the newest. 0 or less: no
      limit. }
    property MaxUndoBytes: Int64 read FMaxUndoBytes write SetMaxUndoBytes;

    { Read it; changing it directly bypasses the model (no undo, no OnChange: the touched
      paragraph's runs are only clipped to its text, new paragraphs are plain). Such a change
      also loses to a later undo of a step whose range it overlaps: the undo gives back the
      pieces the step's edit split (TTyRichText.RestoreSpan), which holds the text from
      before the bypass where it has the same length. }
    property Text: TTyRichText read FText;
    property Formats: TTyFormatPool read FFormats;
    property DefaultCharFormat: TTyCharFormat read FDefaultCharFormat;
    property DefaultCharFormatId: TTyCharFormatId read FDefaultCharId;
    property DefaultParaFormatId: TTyParaFormatId read FDefaultParaId;
    property PaperWidth: Integer read FPaperWidth;      // twips
    property PaperHeight: Integer read FPaperHeight;
    property MarginLeft: Integer read FMarginLeft;
    property MarginRight: Integer read FMarginRight;
    { The document's own ground: clNone (none - a view shows its theme's) unless a file or a
      change of the settings gave it one (RTF: Word's page colour, the \background group). }
    property DocumentColor: TColor read FDocumentColor;
    { All of them in one record (what ChangeSettings takes). }
    function Settings: TTyRichDocSettings;
    property Loader: TTyRichParaLoader read FLoader;
    { The content differs from the one last loaded or saved. The history remembers the
      saved point: Modified is False exactly when the document is at that content again - an
      undo back to it, a redo forward to it - and True otherwise; True for good (until the next
      Modified := False or load) once the step that led back to it is gone (the history's
      memory bound dropped it, ClearUndo, a new step after an undo past it) or the content was
      changed outside the history (a primitive outside a command, an edit straight on Text, an
      undo that failed). ClearUndo at the saved point keeps it: the content is still that one.
      A load (ReplaceText) sets the saved point. Modified := False sets it here (and the next
      typing does not merge into the step before: an undo can come back here);
      Modified := True forces True until the next saved point. Not a change: no OnChange. }
    property Modified: Boolean read GetModified write SetModified;
    { Modified turned (raised at the end of the step, the undo, the redo, the update block,
      the load or the assignment that turned it; an edit straight on Text is noticed at the
      next of these). }
    property OnModifiedChange: TNotifyEvent read FOnModifiedChange write FOnModifiedChange;
    { The number of the content as it is now (Modified's): a step, an undo, a redo, a load
      or an edit outside the history gives another one; the same number is the same
      content. What a reader may remember an answer by (the control's
      ConsistentAttributes). A lazy load's slices and parses change no content and keep it. }
    property ContentState: Int64 read FState;
    property OnChange: TTyRichChangeEvent read FOnChange write FOnChange;

    { Where the content came from, so a text file goes back out as it came in; set by the
      reader through TTyRichDocBuilder.ReplaceText. A new document: teUtf8, no BOM, code
      page 0 (it is the ANSI code page only for teAnsi). }
    property SourceEncoding: TTyTextEncoding read FSourceEncoding;
    property SourceCodePage: Integer read FSourceCodePage;
    property SourceHasBom: Boolean read FSourceHasBom;
    { The kind of line break every inserted one becomes (InsertText turns CR, LF and CRLF in
      the inserted text into it; the breaks already there stay as they are). The file's
      majority kind; a new document, a tie or a text without one: the platform's. }
    property DominantLineBreak: TTyRichSeparator read FDominantLineBreak;
    { A reader is still loading the content in slices: what is there can be read, scrolled
      and laid out, but not changed (Execute returns False) until the last slice is in. }
    property Loading: Boolean read FLoadingContent;
    { The load was cancelled: the document holds only the part of the file read before, and
      stays read-only; a writer must refuse to save it in place of that file. }
    property Incomplete: Boolean read FIncomplete;
    { Inside BeginSave .. EndSave: the document cannot be changed. }
    property Saving: Boolean read GetSaving;
    { The font a view shows the text in that names none of its own (a character format's
      FontName '' is "the view's font"): TTyRichEdit puts its base font here. Not content -
      no command, no OnChange, not Modified, kept by a load - but what a writer names when it
      must: RTF written for a document that was not read from RTF (a new one, a text file)
      defines it as \f0, the document's default font, with the charset its name or the text
      in it calls for. '' (a document no view set it for): such text is written in no font. }
    property BaseFontName: string read FBaseFontName write FBaseFontName;
    { ... and the size it shows that text in (a character format's SizeHalfPt 0), in half
      points: TTyRichEdit puts its base size here, as BaseFontName. Not content either; what
      RTF written of the document gives such text (\fsN) - a reader would show it in 12 pt,
      RTF's own. 0 (a document no view set it for): such text is written with no size. }
    property BaseFontSizeHalfPt: Integer read FBaseFontSizeHalfPt write FBaseFontSizeHalfPt;
  end;

function TyDefaultCharFormat: TTyCharFormat;
function TyDefaultParaFormat: TTyParaFormat;
function TyMergeCharFormat(const ABase: TTyCharFormat; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat): TTyCharFormat;
function TyMergeParaFormat(const ABase: TTyParaFormat; AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat): TTyParaFormat;
{ The multiple of the line's own height a paragraph's lines are (1, 1.15, 1.5, 2, or any
  other: lsMultiple); 0 for exactly and at least, which are heights. }
function TyRichLineMultiple(const AFormat: TTyParaFormat): Double;
{ AFormat's lines AMultiple times their own height, to a 240th (what RTF holds): one of the
  four named rules where it is one of them, else lsMultiple. 0 or less: single. }
procedure TyRichSetLineMultiple(var AFormat: TTyParaFormat; AMultiple: Double);
{ U+FFFC in UTF-8, the character an object occupies. }
function TyRichObjectChar: UTF8String;
{ The platform's line break (sLineBreak) as a separator kind. }
function TyRichPlatformLineBreak: TTyRichSeparator;
{ The kind most of the counted breaks are; a tie for the most, or no break at all: the
  platform's. }
function TyRichMajorityLineBreak(ACR, ALF, ACRLF: Int64): TTyRichSeparator;
{ The caret's word rule (what a double click and Ctrl+Left / Right take, and a find's whole
  word): white space (a space, a tab, U+00A0, U+000B) and ASCII punctuation are no word (0),
  an object (U+FFFC) is a word by itself (2), every other character is a word character (1) -
  letters, digits, ideographs, marks, a byte that is no text. A paragraph's end (a find's
  $FFFFFFFF) and "no character" ($FFFFFFFE, before the text's start) are no word. }
function TyRichWordClass(C: Cardinal): Integer;
{ A character of a script written without spaces - Hangul Jamo and syllables, the CJK
  radicals, punctuation, kana, Bopomofo, the ideographs of every extension, Yi, the
  compatibility ideographs and forms, the full-width forms: a word ends on both of its sides
  (a find's whole word). The line breaker's set (tyControls.Painter's TyIsCJKCodepoint, a unit
  of the controls this one does not use; a test holds the two equal). }
function TyRichNoSpaceScript(C: Cardinal): Boolean;
{ Paragraph values alive in all documents together (for the tests that count what a document
  or its history lets go of). }
function TyRichLiveParaValues: Int64;
{ How many times a kept block's bytes were searched for the picture it carries
  (TTyRichOpaque.DisplayPicture), in every document - for tests. }
function TyRichKeptPictureLookups: Int64;
{ What making a picture's bytes from its file's bytes cost, in every document - for tests: the
  bytes made, and the bytes looked at only to count a picture's hex digits. }
function TyRichPictureBytesMade: Int64;
function TyRichPictureDigitsCounted: Int64;
{ Bookmark names, as Word compares them: without regard to case (Unicode case folding of the
  name's text). TyRichBookmarkHash is the same for two names that compare the same. }
function TyRichSameBookmarkName(const A, B: UTF8String): Boolean;
function TyRichBookmarkHash(const AName: UTF8String): Cardinal;
{ Word's syntax for a bookmark's end: {\*\bkmkstart name} or {\*\bkmkend name}, the name's
  ASCII as it is (\ { } escaped), anything else \uN with a ? for readers without Unicode. }
function TyRichBookmarkBytes(AKind: TTyRichBookmarkKind; const AName: UTF8String): RawByteString;
{ What a decoder reads of APicture: the image file's bytes the control draws (a metafile's
  one bitmap with a bitmap file's header put in front), AFormat what to read them as; nil
  when the control draws a placeholder for it (TTyRichPicture.DisplayBytes). The caller
  frees it. }
function TyRichPictureImageStream(APicture: TTyRichPicture;
  out AFormat: TTyRichPictureFormat): TMemoryStream;

implementation

uses
  LazUTF8, tyControls.StrConsts, tyControls.RichEdit.Commands, tyControls.RichEdit.Wmf;

var
  // paragraph values alive in every document (TyRichLiveParaValues)
  GLiveParaValues: Int64 = 0;
  // TyRichKeptPictureLookups
  GKeptPictureLookups: Int64 = 0;
  // TyRichPictureBytesMade, TyRichPictureDigitsCounted
  GPictureBytesMade: Int64 = 0;
  GPictureDigitsCounted: Int64 = 0;

const
  // RunStep
  StepExecute = 0;
  StepUndo = 1;
  StepRedo = 2;
  DefaultMaxUndoBytes = 64 * 1024 * 1024;

// hashes wrap around on purpose, also in a build with overflow and range checks
{$PUSH}{$Q-}{$R-}

const
  HashBasis = Cardinal(2166136261);
  HashPrime = Cardinal(16777619);

function HashMix(AHash, AValue: Cardinal): Cardinal; inline;
begin
  Result := (AHash xor AValue) * HashPrime;
end;

function HashBytes(AHash: Cardinal; P: PByte; ACount: Integer): Cardinal;
var
  i: Integer;
begin
  Result := AHash;
  for i := 0 to ACount - 1 do
    Result := (Result xor P[i]) * HashPrime;
end;

function HashStr(AHash: Cardinal; const S: RawByteString): Cardinal; inline;
begin
  Result := HashMix(HashBytes(AHash, PByte(PAnsiChar(S)), Length(S)), Length(S));
end;

function SameBytes(const A, B: RawByteString): Boolean; inline;
begin
  // byte compare: comparing with = could convert between code pages
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or (CompareByte(A[1], B[1], Length(A)) = 0));
end;

function TyRichLiveParaValues: Int64;
begin
  Result := GLiveParaValues;
end;

function TyRichKeptPictureLookups: Int64;
begin
  Result := GKeptPictureLookups;
end;

function TyRichPictureBytesMade: Int64;
begin
  Result := GPictureBytesMade;
end;

function TyRichPictureDigitsCounted: Int64;
begin
  Result := GPictureDigitsCounted;
end;

function TyRichNoSpaceScript(C: Cardinal): Boolean;
begin
  Result :=
    ((C >= $1100) and (C <= $11FF)) or     // Hangul Jamo
    ((C >= $2E80) and (C <= $A4CF)) or     // radicals .. CJK punctuation .. kana .. Ext-A .. Yi
    ((C >= $AC00) and (C <= $D7A3)) or     // Hangul syllables
    ((C >= $F900) and (C <= $FAFF)) or     // CJK compatibility ideographs
    ((C >= $FE30) and (C <= $FE4F)) or     // CJK compatibility forms
    ((C >= $FF00) and (C <= $FF60)) or     // full-width forms
    ((C >= $FFE0) and (C <= $FFE6)) or     // full-width signs
    ((C >= $20000) and (C <= $2FA1F));     // CJK Ext B-F
end;

function TyRichWordClass(C: Cardinal): Integer;
begin
  case C of
    $FFFC: Result := 2;
    9, 11, 32, $A0, 33..47, 58..64, 91..94, 96, 123..126, $FFFFFFFE, $FFFFFFFF: Result := 0;
  else
    Result := 1;
  end;
end;

function TyRichObjectChar: UTF8String;
begin
  Result := '';
  SetLength(Result, 3);
  Result[1] := Chr($EF);
  Result[2] := Chr($BF);
  Result[3] := Chr($BC);
end;

function TyRichPlatformLineBreak: TTyRichSeparator;
var
  s: string;
begin
  // through a variable: comparing the constant itself leaves unreachable branches
  s := sLineBreak;
  if s = #13#10 then Result := rsCRLF
  else if s = #13 then Result := rsCR
  else Result := rsLF;
end;

function TyRichMajorityLineBreak(ACR, ALF, ACRLF: Int64): TTyRichSeparator;
var
  top: Int64;
  n: Integer;
begin
  top := ACR;
  if ALF > top then top := ALF;
  if ACRLF > top then top := ACRLF;
  n := 0;
  if ACR = top then Inc(n);
  if ALF = top then Inc(n);
  if ACRLF = top then Inc(n);
  if (top = 0) or (n > 1) then Result := TyRichPlatformLineBreak
  else if ACRLF = top then Result := rsCRLF
  else if ALF = top then Result := rsLF
  else Result := rsCR;
end;

{ AText with every CR, LF and CRLF in it made ABreak; AText itself when it holds none. A CR
  or LF byte is always a break in UTF-8 (no multi-byte sequence contains one). }
function WithBreaks(const AText: UTF8String; ABreak: TTyRichSeparator): UTF8String;
var
  i, n, k: Integer;
  found: Boolean;
begin
  found := False;
  for i := 1 to Length(AText) do
    if (AText[i] = #13) or (AText[i] = #10) then
    begin
      found := True;
      Break;
    end;
  if not found then Exit(AText);
  Result := '';
  SetLength(Result, Length(AText) * 2);
  n := Length(AText);
  i := 1;
  k := 0;
  while i <= n do
  begin
    if (AText[i] = #13) or (AText[i] = #10) then
    begin
      if (AText[i] = #13) and (i < n) and (AText[i + 1] = #10) then Inc(i);
      if ABreak <> rsLF then
      begin
        Inc(k);
        Result[k] := #13;
      end;
      if ABreak <> rsCR then
      begin
        Inc(k);
        Result[k] := #10;
      end;
    end
    else
    begin
      Inc(k);
      Result[k] := AText[i];
    end;
    Inc(i);
  end;
  SetLength(Result, k);
end;

{ ---- TTyOpaqueAttrs ---- }

function TTyOpaqueAttrs.Count: Integer;
begin
  Result := Length(FItems);
end;

function TTyOpaqueAttrs.Item(AIndex: Integer): RawByteString;
begin
  Result := FItems[AIndex];
end;

procedure TTyOpaqueAttrs.Add(const AFragment: RawByteString);
var
  a: array of RawByteString;
  n: Integer;
begin
  // a fresh array: a copied record shares FItems, and the pool's copy must not change
  n := Length(FItems);
  a := Copy(FItems, 0, n);
  SetLength(a, n + 1);
  a[n] := AFragment;
  FItems := a;
end;

procedure TTyOpaqueAttrs.Clear;
begin
  FItems := nil;
end;

function TTyOpaqueAttrs.Equals(const B: TTyOpaqueAttrs): Boolean;
var
  i: Integer;
begin
  if Length(FItems) <> Length(B.FItems) then Exit(False);
  for i := 0 to High(FItems) do
    if not SameBytes(FItems[i], B.FItems[i]) then Exit(False);
  Result := True;
end;

function TTyOpaqueAttrs.Hash: Cardinal;
var
  i: Integer;
begin
  Result := HashMix(HashBasis, Length(FItems));
  for i := 0 to High(FItems) do
    Result := HashStr(Result, FItems[i]);
end;

{ ---- formats ---- }

function TTyCharFormat.Equals(const B: TTyCharFormat): Boolean;
begin
  Result := SameBytes(FontName, B.FontName) and (Charset = B.Charset) and
    (SizeHalfPt = B.SizeHalfPt) and (Style = B.Style) and (Strike = B.Strike) and
    (VertAlign = B.VertAlign) and (Color = B.Color) and
    (HighlightColor = B.HighlightColor) and Extra.Equals(B.Extra);
end;

function TTyCharFormat.Hash: Cardinal;
var
  st: Byte;
begin
  st := 0;
  if fsBold in Style then st := st or 1;
  if fsItalic in Style then st := st or 2;
  if fsUnderline in Style then st := st or 4;
  if fsStrikeOut in Style then st := st or 8;
  Result := HashStr(HashBasis, FontName);
  Result := HashMix(Result, Cardinal(Charset));
  Result := HashMix(Result, Cardinal(SizeHalfPt));
  Result := HashMix(Result, st or (Ord(Strike) shl 4) or (Ord(VertAlign) shl 5));
  Result := HashMix(Result, Cardinal(Color));
  Result := HashMix(Result, Cardinal(HighlightColor));
  Result := HashMix(Result, Extra.Hash);
end;

function TTyParaFormat.Equals(const B: TTyParaFormat): Boolean;
var
  i: Integer;
begin
  Result := (Align = B.Align) and (LeftIndent = B.LeftIndent) and
    (RightIndent = B.RightIndent) and (FirstIndent = B.FirstIndent) and
    (SpaceBefore = B.SpaceBefore) and (SpaceAfter = B.SpaceAfter) and
    (LineSpacing = B.LineSpacing) and (LineSpacingValue = B.LineSpacingValue) and
    (Length(Tabs) = Length(B.Tabs)) and (List.Kind = B.List.Kind) and
    (List.Level = B.List.Level) and (List.StartAt = B.List.StartAt) and
    (RtlPar = B.RtlPar) and (Shading = B.Shading) and (List.Bullet = B.List.Bullet) and
    Extra.Equals(B.Extra);
  if not Result then Exit;
  for i := 0 to High(Tabs) do
    if (Tabs[i].Position <> B.Tabs[i].Position) or (Tabs[i].Align <> B.Tabs[i].Align) or
       (Tabs[i].Leader <> B.Tabs[i].Leader) then
      Exit(False);
end;

function TTyParaFormat.Hash: Cardinal;
var
  i: Integer;
begin
  Result := HashMix(HashBasis, Ord(Align) or (Ord(LineSpacing) shl 4) or (Ord(RtlPar) shl 8));
  Result := HashMix(Result, Cardinal(LeftIndent));
  Result := HashMix(Result, Cardinal(RightIndent));
  Result := HashMix(Result, Cardinal(FirstIndent));
  Result := HashMix(Result, Cardinal(SpaceBefore));
  Result := HashMix(Result, Cardinal(SpaceAfter));
  Result := HashMix(Result, Cardinal(LineSpacingValue));
  Result := HashMix(Result, Ord(List.Kind) or (Cardinal(List.Level) shl 4));
  Result := HashMix(Result, Cardinal(List.StartAt));
  Result := HashMix(Result, Cardinal(Shading));
  // a bullet's own text: its length is enough to spread the few there are
  Result := HashMix(Result, Length(List.Bullet));
  Result := HashMix(Result, Length(Tabs));
  for i := 0 to High(Tabs) do
    Result := HashMix(Result, Cardinal(Tabs[i].Position) xor
      (Cardinal(Ord(Tabs[i].Align)) shl 24) xor (Cardinal(Ord(Tabs[i].Leader)) shl 28));
  Result := HashMix(Result, Extra.Hash);
end;

{$POP}

function TyDefaultCharFormat: TTyCharFormat;
begin
  Result := Default(TTyCharFormat);
  Result.FontName := '';
  Result.Charset := DEFAULT_CHARSET;
  Result.SizeHalfPt := 0;
  Result.Style := [];
  Result.Strike := False;
  Result.VertAlign := vaNone;
  Result.Color := clDefault;
  Result.HighlightColor := clNone;
end;

function TyDefaultParaFormat: TTyParaFormat;
begin
  Result := Default(TTyParaFormat);
  Result.Align := paraLeft;
  Result.LineSpacing := lsSingle;
  Result.List.Kind := lkNone;
  Result.Shading := clNone;
end;

function TyRichLineMultiple(const AFormat: TTyParaFormat): Double;
begin
  case AFormat.LineSpacing of
    lsSingle: Result := 1;
    ls115: Result := 1.15;
    ls15: Result := 1.5;
    lsDouble: Result := 2;
    lsMultiple: Result := AFormat.LineSpacingValue / 240;
  else
    Result := 0;
  end;
end;

procedure TyRichSetLineMultiple(var AFormat: TTyParaFormat; AMultiple: Double);
var
  n: Int64;
begin
  if AMultiple <= 0 then n := 240
  else if AMultiple > 1000 then n := 240000
  else n := Round(AMultiple * 240);
  if n <= 0 then n := 1;
  AFormat.LineSpacingValue := 0;
  case n of
    240: AFormat.LineSpacing := lsSingle;
    276: AFormat.LineSpacing := ls115;
    360: AFormat.LineSpacing := ls15;
    480: AFormat.LineSpacing := lsDouble;
  else
    AFormat.LineSpacing := lsMultiple;
    AFormat.LineSpacingValue := n;
  end;
end;

function TakeStyle(AStyles: TFontStyles; AStyle: TFontStyle; AFrom: TFontStyles): TFontStyles;
begin
  Result := AStyles;
  if AStyle in AFrom then Include(Result, AStyle) else Exclude(Result, AStyle);
end;

function TyMergeCharFormat(const ABase: TTyCharFormat; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat): TTyCharFormat;
begin
  Result := ABase;
  if cffFontName in AMask then Result.FontName := AValue.FontName;
  if cffCharset in AMask then Result.Charset := AValue.Charset;
  if cffSize in AMask then Result.SizeHalfPt := AValue.SizeHalfPt;
  if cffBold in AMask then Result.Style := TakeStyle(Result.Style, fsBold, AValue.Style);
  if cffItalic in AMask then Result.Style := TakeStyle(Result.Style, fsItalic, AValue.Style);
  if cffUnderline in AMask then
    Result.Style := TakeStyle(Result.Style, fsUnderline, AValue.Style);
  if cffStrike in AMask then Result.Strike := AValue.Strike or (fsStrikeOut in AValue.Style);
  if cffVertAlign in AMask then Result.VertAlign := AValue.VertAlign;
  if cffColor in AMask then Result.Color := AValue.Color;
  if cffHighlight in AMask then Result.HighlightColor := AValue.HighlightColor;
  if cffExtra in AMask then Result.Extra := AValue.Extra;
end;

function TyMergeParaFormat(const ABase: TTyParaFormat; AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat): TTyParaFormat;
var
  first: Integer;
  wasList, isList: Boolean;
begin
  Result := ABase;
  if pffAlign in AMask then Result.Align := AValue.Align;
  if pffLeftIndent in AMask then Result.LeftIndent := AValue.LeftIndent;
  if pffRightIndent in AMask then Result.RightIndent := AValue.RightIndent;
  if pffFirstIndent in AMask then Result.FirstIndent := AValue.FirstIndent;
  if pffSpaceBefore in AMask then Result.SpaceBefore := AValue.SpaceBefore;
  if pffSpaceAfter in AMask then Result.SpaceAfter := AValue.SpaceAfter;
  if pffLineSpacing in AMask then
  begin
    Result.LineSpacing := AValue.LineSpacing;
    Result.LineSpacingValue := AValue.LineSpacingValue;
  end;
  if pffTabs in AMask then Result.Tabs := Copy(AValue.Tabs);
  if pffList in AMask then Result.List := AValue.List;
  // one part of the list record and of the spacing, each paragraph keeping the rest
  if pffListKind in AMask then
    if AValue.List.Kind = lkNone then
      Result.List := TyDefaultParaFormat.List
    else
      Result.List.Kind := AValue.List.Kind;
  if pffListStart in AMask then
    if AValue.List.StartAt > 0 then Result.List.StartAt := AValue.List.StartAt
    else Result.List.StartAt := 0;
  if pffSpacingRule in AMask then
  begin
    Result.LineSpacing := AValue.LineSpacing;
    // (a multiple of its own is the rule's own number, as a named one is)
    if AValue.LineSpacing = lsMultiple then
      Result.LineSpacingValue := AValue.LineSpacingValue
    else if not (AValue.LineSpacing in [lsExact, lsAtLeast]) then
      Result.LineSpacingValue := 0
    else if Result.LineSpacingValue <= 0 then
      Result.LineSpacingValue := AValue.LineSpacingValue;
  end;
  if pffSpacingHeight in AMask then
  begin
    if not (Result.LineSpacing in [lsExact, lsAtLeast]) then Result.LineSpacing := lsAtLeast;
    Result.LineSpacingValue := AValue.LineSpacingValue;
  end;
  if pffRtlPar in AMask then Result.RtlPar := AValue.RtlPar;
  if pffShading in AMask then Result.Shading := AValue.Shading;
  if pffListLevel in AMask then
    if AValue.List.Level > 0 then Result.List.Level := AValue.List.Level
    else Result.List.Level := 0;
  if pffListBullet in AMask then Result.List.Bullet := AValue.List.Bullet;
  if pffExtra in AMask then Result.Extra := AValue.Extra;
  // the relative indent fields (see TTyParaFormatField), each from this paragraph's values
  if pffStartIndent in AMask then
    Result.LeftIndent := AValue.LeftIndent + AValue.FirstIndent - Result.FirstIndent;
  if pffOffset in AMask then
  begin
    first := Result.LeftIndent + Result.FirstIndent;
    Result.FirstIndent := AValue.FirstIndent;
    Result.LeftIndent := first - AValue.FirstIndent;
  end;
  if pffFirstLine in AMask then
    Result.FirstIndent := AValue.LeftIndent + AValue.FirstIndent - Result.LeftIndent;
  if pffHeadIndent in AMask then
  begin
    first := Result.LeftIndent + Result.FirstIndent;
    Result.LeftIndent := AValue.LeftIndent;
    Result.FirstIndent := first - AValue.LeftIndent;
  end;
  if pffListIndents in AMask then
  begin
    wasList := ABase.List.Kind <> lkNone;
    isList := Result.List.Kind <> lkNone;
    if isList and not wasList and (Result.LeftIndent = 0) and (Result.FirstIndent = 0) then
    begin
      Result.LeftIndent := AValue.LeftIndent;
      Result.FirstIndent := AValue.FirstIndent;
    end
    else if wasList and not isList then
    begin
      Result.LeftIndent := 0;
      Result.FirstIndent := 0;
    end;
  end;
end;

{ ---- TTyFormatPool ---- }

procedure TTyFormatPool.RehashChars;
var
  i, n: Integer;
  b: Cardinal;
begin
  n := Length(FCharBucket) * 2;
  if n < 16 then n := 16;
  SetLength(FCharBucket, n);
  for i := 0 to n - 1 do FCharBucket[i] := -1;
  for i := 0 to FCharCount - 1 do
  begin
    b := FCharHash[i] and Cardinal(n - 1);
    FCharNext[i] := FCharBucket[b];
    FCharBucket[b] := i;
  end;
end;

procedure TTyFormatPool.RehashParas;
var
  i, n: Integer;
  b: Cardinal;
begin
  n := Length(FParaBucket) * 2;
  if n < 16 then n := 16;
  SetLength(FParaBucket, n);
  for i := 0 to n - 1 do FParaBucket[i] := -1;
  for i := 0 to FParaCount - 1 do
  begin
    b := FParaHash[i] and Cardinal(n - 1);
    FParaNext[i] := FParaBucket[b];
    FParaBucket[b] := i;
  end;
end;

function TTyFormatPool.InternChar(const F: TTyCharFormat): TTyCharFormatId;
var
  g: TTyCharFormat;
  h, b: Cardinal;
  i: Integer;
begin
  g := F;
  if fsStrikeOut in g.Style then
  begin
    Exclude(g.Style, fsStrikeOut);
    g.Strike := True;
  end;
  h := g.Hash;
  if Length(FCharBucket) > 0 then
  begin
    i := FCharBucket[h and Cardinal(Length(FCharBucket) - 1)];
    while i >= 0 do
    begin
      if (FCharHash[i] = h) and FChars[i].Equals(g) then Exit(i);
      i := FCharNext[i];
    end;
  end;
  if FCharCount = Length(FChars) then
  begin
    SetLength(FChars, FCharCount * 2 + 8);
    SetLength(FCharHash, Length(FChars));
    SetLength(FCharNext, Length(FChars));
  end;
  Result := FCharCount;
  g.Extra.FItems := Copy(g.Extra.FItems);
  FChars[Result] := g;
  FCharHash[Result] := h;
  Inc(FCharCount);
  if FCharCount > Length(FCharBucket) then
    RehashChars
  else
  begin
    b := h and Cardinal(Length(FCharBucket) - 1);
    FCharNext[Result] := FCharBucket[b];
    FCharBucket[b] := Result;
  end;
end;

function TTyFormatPool.InternPara(const F: TTyParaFormat): TTyParaFormatId;
var
  g: TTyParaFormat;
  h, b: Cardinal;
  i: Integer;
begin
  g := F;
  h := g.Hash;
  if Length(FParaBucket) > 0 then
  begin
    i := FParaBucket[h and Cardinal(Length(FParaBucket) - 1)];
    while i >= 0 do
    begin
      if (FParaHash[i] = h) and FParas[i].Equals(g) then Exit(i);
      i := FParaNext[i];
    end;
  end;
  if FParaCount = Length(FParas) then
  begin
    SetLength(FParas, FParaCount * 2 + 8);
    SetLength(FParaHash, Length(FParas));
    SetLength(FParaNext, Length(FParas));
  end;
  Result := FParaCount;
  // the caller's arrays are shared with this copy; the pool keeps its own
  g.Tabs := Copy(g.Tabs);
  g.Extra.FItems := Copy(g.Extra.FItems);
  FParas[Result] := g;
  FParaHash[Result] := h;
  Inc(FParaCount);
  if FParaCount > Length(FParaBucket) then
    RehashParas
  else
  begin
    b := h and Cardinal(Length(FParaBucket) - 1);
    FParaNext[Result] := FParaBucket[b];
    FParaBucket[b] := Result;
  end;
end;

function TTyFormatPool.CharFormat(AId: TTyCharFormatId): TTyCharFormat;
begin
  if (AId < 0) or (AId >= FCharCount) then
    raise ETyRichModel.CreateFmt('Character format id %d out of range', [AId]);
  // Extra's array is private and Add replaces it, so sharing it is safe
  Result := FChars[AId];
end;

function TTyFormatPool.ParaFormat(AId: TTyParaFormatId): TTyParaFormat;
begin
  if (AId < 0) or (AId >= FParaCount) then
    raise ETyRichModel.CreateFmt('Paragraph format id %d out of range', [AId]);
  Result := FParas[AId];
  // Tabs is a public array: writing an element of a shared one would change the pool's
  Result.Tabs := Copy(Result.Tabs);
end;

{ ---- TTyRichRefCounted ---- }

procedure TTyRichRefCounted.AddRef;
begin
  Inc(FRefCount);
end;

procedure TTyRichRefCounted.Release;
begin
  if FRefCount <= 0 then
    raise ETyRichModel.CreateFmt('%s released more often than referenced', [ClassName]);
  Dec(FRefCount);
  if FRefCount = 0 then Free;
end;

{ ---- objects ---- }

constructor TTyRichObject.Create;
begin
  inherited Create;
  FRawUc := 1;
end;

constructor TTyRichPicture.Create(AFormat: TTyRichPictureFormat; const AData: TBytes;
  AWidthTwips, AHeightTwips: Integer; const ARawRtf: RawByteString; ARawUc: Integer);
begin
  inherited Create;
  FFormat := AFormat;
  FData := AData;
  FWidthTwips := AWidthTwips;
  FHeightTwips := AHeightTwips;
  FRawRtf := ARawRtf;
  if ARawUc >= 0 then FRawUc := ARawUc;
end;

constructor TTyRichPicture.CreateInFile(AFormat: TTyRichPictureFormat; const AFile: TBytes;
  ADataAt, ADataLen: Int64; ABin: Boolean; AWidthTwips, AHeightTwips: Integer;
  ARawAt, ARawLen: Int64; ARawUc: Integer);
begin
  inherited Create;
  if (ADataAt < 0) or (ADataLen < 0) or (ADataAt + ADataLen > Length(AFile)) or
     (ARawAt < 0) or (ARawLen < 0) or (ARawAt + ARawLen > Length(AFile)) then
    raise ETyRichModel.Create('A picture''s bytes must lie in its file');
  FFormat := AFormat;
  FWidthTwips := AWidthTwips;
  FHeightTwips := AHeightTwips;
  FFile := AFile;
  FFileData := ADataAt;
  FFileDataLen := ADataLen;
  FFileBin := ABin;
  FFileRaw := ARawAt;
  FFileRawLen := ARawLen;
  if ARawUc >= 0 then FRawUc := ARawUc;
end;

function KeptDecodeHex(P: PByte; ALen: PtrInt): TBytes; forward;
function KeptHexDigits(P: PByte; ALen: PtrInt): Int64; forward;

function IsHexDigit(B: Byte): Boolean; inline;
begin
  Result := ((B >= Ord('0')) and (B <= Ord('9'))) or ((B >= Ord('a')) and (B <= Ord('f'))) or
    ((B >= Ord('A')) and (B <= Ord('F')));
end;

function TTyRichPicture.InFile: Boolean;
begin
  Result := FFile <> nil;
end;

function TTyRichPicture.MakeImageData: TBytes;
begin
  if FFile = nil then Exit(FData);
  Result := nil;
  if FFileDataLen <= 0 then Exit;
  if FFileBin then
  begin
    SetLength(Result, FFileDataLen);
    Move(FFile[FFileData], Result[0], FFileDataLen);
  end
  else
    Result := KeptDecodeHex(@FFile[FFileData], FFileDataLen);
  Inc(GPictureBytesMade, Length(Result));
end;

function TTyRichPicture.GetRawRtf: RawByteString;
begin
  if FFile = nil then Exit(FRawRtf);
  Result := '';
  if FFileRawLen <= 0 then Exit;
  SetLength(Result, FFileRawLen);
  Move(FFile[FFileRaw], Result[1], FFileRawLen);
end;

function TTyRichPicture.RawRtfData: PByte;
begin
  if FFile <> nil then
  begin
    if FFileRawLen > 0 then Result := @FFile[FFileRaw] else Result := nil;
  end
  else if FRawRtf <> '' then Result := PByte(PAnsiChar(FRawRtf))
  else Result := nil;
end;

function TTyRichPicture.RawRtfLength: Int64;
begin
  if FFile <> nil then Result := FFileRawLen else Result := Length(FRawRtf);
end;

function TTyRichPicture.DataIdentity: Pointer;
begin
  if FFile <> nil then
  begin
    if FFileDataLen > 0 then Result := @FFile[FFileData] else Result := nil;
  end
  else if Length(FData) > 0 then Result := Pointer(FData)
  else Result := nil;
end;

function TTyRichPicture.MayShow: Boolean;
var
  fmt: TTyRichPictureFormat;
  s, c: Integer;
  i, digits: Int64;
begin
  if (FFile = nil) or (FShown <> 0) then Exit(DisplayData(fmt, s, c));
  if not (FFormat in [rpfPng, rpfJpeg, rpfBmp, rpfDib, rpfWmf]) then Exit(False);
  // at least one byte: \bin's, or two digits (looked for from the start: they are there)
  if FFileBin then Exit(FFileDataLen > 0);
  digits := 0;
  i := FFileData;
  while (i < FFileData + FFileDataLen) and (digits < 2) do
  begin
    if IsHexDigit(FFile[i]) then Inc(digits);
    Inc(i);
  end;
  Result := digits >= 2;
end;

function TTyRichObject.DataBytes: Int64;
begin
  Result := InstanceSize;
end;

function TTyRichPicture.DataBytes: Int64;
begin
  Result := InstanceSize + Length(FData) + Length(FRawRtf);
end;

function TTyRichOpaque.DataBytes: Int64;
begin
  Result := InstanceSize + Length(FBytes) + Length(FDisplayText);
end;

function TTyRichObject.SharedData(out ABytes: Int64): Pointer;
begin
  ABytes := 0;
  Result := nil;
end;

function TTyRichObject.DisplaySize(out AWidthTwips, AHeightTwips: Integer): Boolean;
begin
  AWidthTwips := 0;
  AHeightTwips := 0;
  Result := False;
end;

function TTyRichObject.CanResize: Boolean;
begin
  Result := False;
end;

function TTyRichObject.Resized(AWidthTwips, AHeightTwips: Integer): TTyRichObject;
begin
  Result := nil;
end;

function TTyRichPicture.SharedData(out ABytes: Int64): Pointer;
begin
  ABytes := Length(FData);
  if ABytes > 0 then Result := Pointer(FData) else Result := nil;
end;

function TTyRichPicture.DisplaySize(out AWidthTwips, AHeightTwips: Integer): Boolean;
begin
  AWidthTwips := FWidthTwips;
  AHeightTwips := FHeightTwips;
  Result := True;
end;

function TTyRichPicture.CanResize: Boolean;
begin
  Result := True;
end;

type
  TTyRichPictureClass = class of TTyRichPicture;

function TTyRichPicture.Resized(AWidthTwips, AHeightTwips: Integer): TTyRichObject;
var
  p: TTyRichPicture;
begin
  p := TTyRichPictureClass(ClassType).Create(FFormat, FData, AWidthTwips, AHeightTwips, '', 1);
  // one whose bytes are its file's: the same place in the file (nothing converted), no group
  p.FFile := FFile;
  p.FFileData := FFileData;
  p.FFileDataLen := FFileDataLen;
  p.FFileBin := FFileBin;
  // the same bytes show the same: what DisplayData found of them is not looked for again
  p.FShown := FShown;
  p.FShowFormat := FShowFormat;
  p.FShowStart := FShowStart;
  p.FShowCount := FShowCount;
  Result := p;
end;

function TTyRichPicture.Clone: TTyRichObject;
begin
  // (a file's bytes made its own: MakeImageData and GetRawRtf copy them)
  Result := TTyRichPicture.Create(FFormat, MakeImageData, FWidthTwips, FHeightTwips, GetRawRtf,
    FRawUc);
end;

procedure TTyRichPicture.ShowFrom(const AData: TBytes);
var
  bm: TTyWmfBitmap;
begin
  FShown := 2;
  FShowFormat := rpfUnknown;
  FShowStart := 0;
  FShowCount := 0;
  if Length(AData) = 0 then Exit;
  case FFormat of
    rpfPng, rpfJpeg, rpfBmp, rpfDib:
      begin
        FShown := 1;
        FShowFormat := FFormat;
        FShowCount := Length(AData);
      end;
    rpfWmf:
      if TyWmfSingleBitmap(AData, bm) then
      begin
        FShown := 1;
        FShowFormat := rpfDib;
        FShowStart := bm.DibStart;
        FShowCount := bm.DibCount;
      end;
  else
    ;  // EMF and other metafiles are drawn by nothing in phase 1
  end;
end;

function TTyRichPicture.DisplayData(out AFormat: TTyRichPictureFormat;
  out AStart, ACount: Integer): Boolean;
var
  bm: TTyWmfBitmap;
  n: Int64;
begin
  // the picture never changes, so the metafile's records are walked once
  if FShown = 0 then
    if FFile = nil then
      ShowFrom(FData)
    else if FFormat = rpfWmf then
    begin
      // walked in place (\bin), or in a copy made for that only
      if FFileBin and (FFileDataLen > 0) then
      begin
        ShowFrom(nil);
        if TyWmfSingleBitmap(@FFile[FFileData], FFileDataLen, bm) then
        begin
          FShown := 1;
          FShowFormat := rpfDib;
          FShowStart := bm.DibStart;
          FShowCount := bm.DibCount;
        end;
      end
      else
        ShowFrom(MakeImageData);
    end
    else
    begin
      // the same answers without the bytes: how many there are
      ShowFrom(nil);
      n := ImageDataLength;
      if (n > 0) and (n <= MaxInt) and (FFormat in [rpfPng, rpfJpeg, rpfBmp, rpfDib]) then
      begin
        FShown := 1;
        FShowFormat := FFormat;
        FShowCount := Integer(n);
      end;
    end;
  Result := FShown = 1;
  AFormat := FShowFormat;
  AStart := FShowStart;
  ACount := FShowCount;
end;

function TTyRichPicture.DisplayBytes(out AFormat: TTyRichPictureFormat;
  out AStart, ACount: Integer; out AData: TBytes): Boolean;
begin
  AData := nil;
  // nothing to make for what is known to show nothing, or of a kind nothing here draws
  if (FShown = 2) or ((FShown = 0) and
    not (FFormat in [rpfPng, rpfJpeg, rpfBmp, rpfDib, rpfWmf])) then
    Exit(DisplayData(AFormat, AStart, ACount));
  AData := MakeImageData;
  // (worked out from these bytes when it was not yet: nothing counted, nothing made again)
  if FShown = 0 then ShowFrom(AData);
  Result := DisplayData(AFormat, AStart, ACount);
  if not Result then AData := nil;
end;

function TTyRichPicture.ImageDataLength: Int64;
begin
  if FFile = nil then Exit(Length(FData));
  if FFileDataLen <= 0 then Exit(0);
  if FFileBin then Exit(FFileDataLen);
  Inc(GPictureDigitsCounted, FFileDataLen);
  Result := KeptHexDigits(@FFile[FFileData], FFileDataLen) div 2;
end;

constructor TTyRichOpaque.Create(const ABytes: RawByteString; const ADisplayText: UTF8String;
  ARawUc: Integer);
begin
  inherited Create;
  FBytes := ABytes;
  FDisplayText := ADisplayText;
  if ARawUc >= 0 then FRawUc := ARawUc;
end;

function TTyRichOpaque.Clone: TTyRichObject;
begin
  Result := TTyRichOpaque.Create(FBytes, FDisplayText, FRawUc);
end;

destructor TTyRichOpaque.Destroy;
begin
  if FPicture <> nil then FPicture.Release;
  inherited Destroy;
end;

{ ---- the picture a kept block carries ---- }

type
  TKeptKind = (kkGroup, kkEnd, kkWord, kkSymbol, kkText, kkBin);

  { The tokens of a kept block's bytes, as much of RTF as finding its picture needs: braces,
    control words (\bin with its bytes), control symbols, runs of text - offsets into the
    bytes, nothing copied. }
  TKeptLexer = record
    P: PByte;
    Pos, Stop: PtrInt;
    Kind: TKeptKind;
    NameAt, NameLen: PtrInt;   // kkWord, kkBin; kkSymbol: NameAt is its character (-1: none)
    Param: Int64;              // 0 when it has none
    DataAt, DataLen: PtrInt;   // kkText: the run; kkBin: its bytes
    Cut: Boolean;              // kkBin: the bytes end before the count it gives
  end;

  // A {\pict ...} group: its words, and where its image bytes are in the block's.
  TKeptPict = record
    Format: TTyRichPictureFormat;
    W, H, WGoal, HGoal, SX, SY: Int64;
    DataAt, DataLen: PtrInt;
    Hex: Boolean;
  end;

function KeptHexVal(B: Byte): Integer; inline;
begin
  case B of
    Ord('0')..Ord('9'): Result := B - Ord('0');
    Ord('a')..Ord('f'): Result := B - Ord('a') + 10;
    Ord('A')..Ord('F'): Result := B - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

// The bytes the hex digits among ALen bytes at P stand for, as a reader takes them.
function KeptDecodeHex(P: PByte; ALen: PtrInt): TBytes;
var
  i, n: PtrInt;
  h, nib: Integer;
begin
  Result := nil;
  SetLength(Result, ALen div 2);
  n := 0;
  nib := -1;
  for i := 0 to ALen - 1 do
  begin
    h := KeptHexVal(P[i]);
    if h < 0 then Continue;
    if nib < 0 then
      nib := h
    else
    begin
      Result[n] := Byte((nib shl 4) or h);
      Inc(n);
      nib := -1;
    end;
  end;
  SetLength(Result, n);
end;

function KeptHexDigits(P: PByte; ALen: PtrInt): Int64;
var
  i: PtrInt;
begin
  Result := 0;
  for i := 0 to ALen - 1 do
    if KeptHexVal(P[i]) >= 0 then Inc(Result);
end;

procedure KeptInit(out L: TKeptLexer; const S: RawByteString);
begin
  FillChar(L, SizeOf(L), 0);
  L.P := PByte(PAnsiChar(S));
  L.Pos := 0;
  L.Stop := Length(S);
end;

function KeptLetter(B: Byte): Boolean; inline;
begin
  Result := ((B >= Ord('a')) and (B <= Ord('z'))) or ((B >= Ord('A')) and (B <= Ord('Z')));
end;

function KeptNext(var L: TKeptLexer): Boolean;
var
  q: PtrInt;
  v: Int64;
  neg, digits: Boolean;
begin
  Result := L.Pos < L.Stop;
  if not Result then Exit;
  L.Param := 0;
  L.Cut := False;
  case L.P[L.Pos] of
    Ord('{'):
      begin
        L.Kind := kkGroup;
        Inc(L.Pos);
      end;
    Ord('}'):
      begin
        L.Kind := kkEnd;
        Inc(L.Pos);
      end;
    Ord('\'):
      begin
        q := L.Pos + 1;
        if (q < L.Stop) and KeptLetter(L.P[q]) then
        begin
          L.Kind := kkWord;
          L.NameAt := q;
          while (q < L.Stop) and KeptLetter(L.P[q]) do Inc(q);
          L.NameLen := q - L.NameAt;
          neg := (q < L.Stop) and (L.P[q] = Ord('-'));
          if neg then Inc(q);
          v := 0;
          digits := False;
          while (q < L.Stop) and (L.P[q] >= Ord('0')) and (L.P[q] <= Ord('9')) do
          begin
            if v < 100000000000 then v := v * 10 + (L.P[q] - Ord('0'));
            digits := True;
            Inc(q);
          end;
          if neg and not digits then Dec(q)
          else if neg then v := -v;
          L.Param := v;
          if (q < L.Stop) and (L.P[q] = Ord(' ')) then Inc(q);
          L.Pos := q;
          if (L.NameLen = 3) and (L.P[L.NameAt] = Ord('b')) and (L.P[L.NameAt + 1] = Ord('i')) and
            (L.P[L.NameAt + 2] = Ord('n')) and (v > 0) then
          begin
            L.Kind := kkBin;
            L.DataAt := q;
            if v > L.Stop - q then
            begin
              v := L.Stop - q;
              L.Cut := True;
            end;
            L.DataLen := v;
            L.Pos := q + v;
          end;
        end
        else
        begin
          L.Kind := kkSymbol;
          if q >= L.Stop then
          begin
            L.NameAt := -1;
            L.Pos := q;
          end
          else
          begin
            L.NameAt := q;
            L.Pos := q + 1;
            // \'xx: its two digits are part of it
            if L.P[q] = Ord('''') then
            begin
              Inc(L.Pos, 2);
              if L.Pos > L.Stop then L.Pos := L.Stop;
            end;
          end;
        end;
      end;
  else
    L.Kind := kkText;
    q := L.Pos;
    while (q < L.Stop) and (L.P[q] <> Ord('{')) and (L.P[q] <> Ord('}')) and
      (L.P[q] <> Ord('\')) do
      Inc(q);
    L.DataAt := L.Pos;
    L.DataLen := q - L.Pos;
    L.Pos := q;
  end;
end;

function KeptNameIs(const L: TKeptLexer; const S: string): Boolean;
begin
  Result := (L.Kind = kkWord) and (L.NameLen = Length(S)) and
    (CompareByte(L.P[L.NameAt], S[1], L.NameLen) = 0);
end;

{ L has just read a group's brace: when the group's first word (after a \*) is S, L moves past
  that word and True. Otherwise L stays. }
function KeptEnter(var L: TKeptLexer; const S: string): Boolean;
var
  m: TKeptLexer;
begin
  m := L;
  if not KeptNext(m) then Exit(False);
  if (m.Kind = kkSymbol) and (m.NameAt >= 0) and (m.P[m.NameAt] = Ord('*')) and
    not KeptNext(m) then
    Exit(False);
  Result := KeptNameIs(m, S);
  if Result then L := m;
end;

// L inside a group: to after its closing brace. False when the bytes end first.
function KeptSkipGroup(var L: TKeptLexer): Boolean;
var
  depth: Integer;
begin
  depth := 1;
  while KeptNext(L) do
    case L.Kind of
      kkGroup: Inc(depth);
      kkEnd:
        begin
          Dec(depth);
          if depth = 0 then Exit(True);
        end;
    end;
  Result := False;
end;

{ L inside a group: to the first group in it named S - a child of it, or with AAnyDepth one
  at any depth -, L past its name. False when the group ends first (L after its brace). }
function KeptFindGroup(var L: TKeptLexer; const S: string; AAnyDepth: Boolean): Boolean;
var
  depth: Integer;
begin
  depth := 0;
  while KeptNext(L) do
    case L.Kind of
      kkGroup:
        if ((depth = 0) or AAnyDepth) and KeptEnter(L, S) then
          Exit(True)
        else
          Inc(depth);
      kkEnd:
        begin
          if depth = 0 then Exit(False);
          Dec(depth);
        end;
    end;
  Result := False;
end;

function KeptTextHasHex(const L: TKeptLexer): Boolean;
var
  i: PtrInt;
begin
  for i := L.DataAt to L.DataAt + L.DataLen - 1 do
    if KeptHexVal(L.P[i]) >= 0 then Exit(True);
  Result := False;
end;

procedure KeptPictWord(const L: TKeptLexer; var APict: TKeptPict);
begin
  if KeptNameIs(L, 'pngblip') then APict.Format := rpfPng
  else if KeptNameIs(L, 'jpegblip') then APict.Format := rpfJpeg
  else if KeptNameIs(L, 'dibitmap') then APict.Format := rpfDib
  else if KeptNameIs(L, 'wbitmap') then APict.Format := rpfBmp
  else if KeptNameIs(L, 'wmetafile') then APict.Format := rpfWmf
  else if KeptNameIs(L, 'emfblip') then APict.Format := rpfEmf
  else if KeptNameIs(L, 'picw') then APict.W := L.Param
  else if KeptNameIs(L, 'pich') then APict.H := L.Param
  else if KeptNameIs(L, 'picwgoal') then APict.WGoal := L.Param
  else if KeptNameIs(L, 'pichgoal') then APict.HGoal := L.Param
  else if KeptNameIs(L, 'picscalex') then APict.SX := L.Param
  else if KeptNameIs(L, 'picscaley') then APict.SY := L.Param;
end;

{ The \pict group L has just entered: its words and where its image bytes are, L after
  its closing brace. False when the bytes end inside it, and when its image bytes are not one
  stretch (hex digits with a word or a group between them, \bin twice, \bin and hex digits):
  no writer puts them so, and a reader of such a group would see other bytes. }
function KeptReadPict(var L: TKeptLexer; out APict: TKeptPict): Boolean;
var
  depth: Integer;
  first, last: PtrInt;
  closed, broken, bin: Boolean;
begin
  FillChar(APict, SizeOf(APict), 0);
  APict.Format := rpfUnknown;
  APict.SX := 100;
  APict.SY := 100;
  depth := 1;
  first := -1;
  last := -1;
  closed := False;
  broken := False;
  bin := False;
  while True do
  begin
    if not KeptNext(L) then Exit(False);
    case L.Kind of
      kkGroup:
        begin
          Inc(depth);
          if first >= 0 then closed := True;
        end;
      kkEnd:
        begin
          Dec(depth);
          if depth = 0 then Break;
        end;
      kkWord:
        if depth = 1 then
        begin
          if first >= 0 then closed := True;
          KeptPictWord(L, APict);
        end;
      kkSymbol:
        if (depth = 1) and (first >= 0) then closed := True;
      kkText:
        if (depth = 1) and KeptTextHasHex(L) then
        begin
          if closed or bin then
            broken := True
          else
          begin
            if first < 0 then first := L.DataAt;
            last := L.DataAt + L.DataLen;
          end;
        end;
      kkBin:
        if depth = 1 then
        begin
          if L.Cut then Exit(False);
          if bin or (first >= 0) then
            broken := True
          else
          begin
            bin := True;
            APict.DataAt := L.DataAt;
            APict.DataLen := L.DataLen;
          end;
        end;
    end;
  end;
  if broken then Exit(False);
  if not bin and (first >= 0) then
  begin
    APict.Hex := True;
    APict.DataAt := first;
    APict.DataLen := last - first;
  end;
  Result := True;
end;

{ The picture of APict for the block ASource, when the layout can show it - what
  TTyRichPicture.DisplayData shows of a picture, worked out here once: PNG, JPEG, BMP and DIB
  are their bytes, a metafile whose drawing is one bitmap is that bitmap; nil for anything
  else and for no bytes. The display size is a reader's: \picwgoal / \pichgoal, else \picw /
  \pich (hundredths of a millimetre for metafiles, pixels at 96 dpi for the rest), then
  \picscalex / \picscaley. }
function KeptPictureOf(const ASource: RawByteString; const APict: TKeptPict): TTyRichKeptPicture;
var
  count, w, h: Int64;
  data: TBytes;
  bm: TTyWmfBitmap;
  fmt: TTyRichPictureFormat;
  start, cnt: Int64;
  ok: Boolean;
  p: PByte;
begin
  Result := nil;
  if (APict.DataLen <= 0) or (APict.DataAt < 0) or
    (Int64(APict.DataAt) + APict.DataLen > Length(ASource)) then
    Exit;
  p := PByte(PAnsiChar(ASource)) + APict.DataAt;
  if APict.Hex then count := KeptHexDigits(p, APict.DataLen) div 2
  else count := APict.DataLen;
  if (count <= 0) or (count > MaxInt) then Exit;
  fmt := APict.Format;
  start := 0;
  cnt := count;
  case APict.Format of
    rpfPng, rpfJpeg, rpfBmp, rpfDib:
      ok := True;
    rpfWmf:
      begin
        // (its records are walked once: a decoded copy only for that, let go at once)
        if APict.Hex then
        begin
          data := KeptDecodeHex(p, APict.DataLen);
          ok := TyWmfSingleBitmap(data, bm);
          data := nil;
        end
        else
          ok := TyWmfSingleBitmap(p, APict.DataLen, bm);
        if ok then
        begin
          fmt := rpfDib;
          start := bm.DibStart;
          cnt := bm.DibCount;
        end;
      end;
  else
    ok := False;
  end;
  if not ok or (cnt <= 0) or (start < 0) or (start + cnt > count) then Exit;
  w := APict.WGoal;
  h := APict.HGoal;
  if w <= 0 then
    if APict.Format in [rpfWmf, rpfEmf] then w := APict.W * 1440 div 2540
    else w := APict.W * 15;
  if h <= 0 then
    if APict.Format in [rpfWmf, rpfEmf] then h := APict.H * 1440 div 2540
    else h := APict.H * 15;
  if APict.SX > 0 then w := w * APict.SX div 100;
  if APict.SY > 0 then h := h * APict.SY div 100;
  if w > High(Integer) then w := High(Integer) else if w < 0 then w := 0;
  if h > High(Integer) then h := High(Integer) else if h < 0 then h := 0;
  Result := TTyRichKeptPicture.Create(APict.Format, nil, Integer(w), Integer(h));
  Result.FSource := ASource;
  Result.FDataAt := APict.DataAt;
  Result.FDataLen := APict.DataLen;
  Result.FHex := APict.Hex;
  Result.FShown := 1;
  Result.FShowFormat := fmt;
  Result.FShowStart := Integer(start);
  Result.FShowCount := Integer(cnt);
end;

{ L inside a group, past its name: the first picture in it the layout can show - of its \pict
  groups wherever they are in it (also inside Word's \*\shppict and \nonshppict groups), in
  order, the first that can be drawn. True when there is one (APic); False when there is none,
  L after the group's brace or at the end of the bytes. }
function KeptFindIn(var L: TKeptLexer; const ASource: RawByteString;
  out APic: TTyRichKeptPicture): Boolean;
var
  depth: Integer;
  pk: TKeptPict;
begin
  APic := nil;
  depth := 0;
  while KeptNext(L) do
    case L.Kind of
      kkGroup:
        if KeptEnter(L, 'pict') then
        begin
          // (one that cannot be read leaves L after it, or at the end of a cut-off block)
          if KeptReadPict(L, pk) then APic := KeptPictureOf(ASource, pk);
          if APic <> nil then Exit(True);
        end
        else
          Inc(depth);
      kkEnd:
        begin
          if depth = 0 then Exit(False);
          Dec(depth);
        end;
    end;
  Result := False;
end;

// L inside a group, past its name: its text (of the group itself, not of groups in it), L after its brace.
function KeptGroupText(var L: TKeptLexer): RawByteString;
var
  depth: Integer;
  s: RawByteString;
begin
  Result := '';
  depth := 0;
  while KeptNext(L) do
    case L.Kind of
      kkGroup: Inc(depth);
      kkEnd:
        begin
          if depth = 0 then Break;
          Dec(depth);
        end;
      kkText:
        if depth = 0 then
        begin
          SetString(s, PAnsiChar(L.P) + L.DataAt, L.DataLen);
          Result := Result + s;
        end;
    end;
  Result := Trim(Result);
end;

{ L inside a shape's \*\shpinst group: the picture of its property pib - the \sp group whose
  \sn group says pib, its \sv group holding the \pict group. True when it holds one the layout
  can show (APic). }
function KeptPibPicture(var L: TKeptLexer; const ASource: RawByteString;
  out APic: TTyRichKeptPicture): Boolean;
var
  isPib: Boolean;
begin
  APic := nil;
  while KeptFindGroup(L, 'sp', False) do
  begin
    isPib := False;
    while KeptNext(L) do
    begin
      if L.Kind = kkEnd then Break;
      if L.Kind <> kkGroup then Continue;
      if KeptEnter(L, 'sn') then
        isPib := KeptGroupText(L) = 'pib'
      else if isPib and KeptEnter(L, 'sv') then
        Exit(KeptFindIn(L, ASource, APic))
      else if not KeptSkipGroup(L) then
        Exit(False);
    end;
  end;
  Result := False;
end;

// The picture the block S carries for readers that cannot draw it (TTyRichOpaque.DisplayPicture).
function KeptBlockPicture(const S: RawByteString): TTyRichKeptPicture;
var
  L, m: TKeptLexer;
begin
  Result := nil;
  if S = '' then Exit;
  KeptInit(L, S);
  if not KeptNext(L) or (L.Kind <> kkGroup) then Exit;
  if KeptEnter(L, 'mmath') then
  begin
    // the picture Word puts beside the equation's own words, at any depth in it
    if KeptFindGroup(L, 'mmathPict', True) then KeptFindIn(L, S, Result);
  end
  else if KeptEnter(L, 'object') then
  begin
    if KeptFindGroup(L, 'result', False) then KeptFindIn(L, S, Result);
  end
  else if KeptEnter(L, 'shp') then
  begin
    m := L;
    if KeptFindGroup(m, 'shprslt', False) and KeptFindIn(m, S, Result) then Exit;
    // none of the result's can be drawn: the picture the shape is filled with
    if KeptFindGroup(L, 'shpinst', False) then KeptPibPicture(L, S, Result);
  end;
end;

function TTyRichOpaque.DisplayPicture: TTyRichKeptPicture;
begin
  if not FPictureSought then
  begin
    FPictureSought := True;
    // a block shown as its text (a field's result) stays its text
    if FDisplayText = '' then
    begin
      Inc(GKeptPictureLookups);
      FPicture := KeptBlockPicture(FBytes);
      if FPicture <> nil then FPicture.AddRef;
    end;
  end;
  Result := FPicture;
end;

{ ---- TTyRichKeptPicture ---- }

function TTyRichKeptPicture.Clone: TTyRichObject;
var
  p: TTyRichKeptPicture;
begin
  p := TTyRichKeptPicture.Create(PictureFormat, nil, WidthTwips, HeightTwips, '', RawUc);
  p.FSource := FSource;
  p.FDataAt := FDataAt;
  p.FDataLen := FDataLen;
  p.FHex := FHex;
  p.FShown := FShown;
  p.FShowFormat := FShowFormat;
  p.FShowStart := FShowStart;
  p.FShowCount := FShowCount;
  Result := p;
end;

function TTyRichKeptPicture.DataBytes: Int64;
begin
  // the block's bytes are the block's
  Result := InstanceSize;
end;

function TTyRichKeptPicture.SharedData(out ABytes: Int64): Pointer;
begin
  ABytes := Length(FSource);
  if ABytes > 0 then Result := Pointer(FSource) else Result := nil;
end;

function TTyRichKeptPicture.CanResize: Boolean;
begin
  Result := False;
end;

function TTyRichKeptPicture.Resized(AWidthTwips, AHeightTwips: Integer): TTyRichObject;
begin
  Result := nil;
end;

function TTyRichKeptPicture.ImageDataLength: Int64;
begin
  if (FDataLen <= 0) or (FDataAt < 0) or (Int64(FDataAt) + FDataLen > Length(FSource)) then
    Exit(0);
  if FHex then
  begin
    Inc(GPictureDigitsCounted, FDataLen);
    Result := KeptHexDigits(PByte(PAnsiChar(FSource)) + FDataAt, FDataLen) div 2;
  end
  else
    Result := FDataLen;
end;

function TTyRichKeptPicture.MakeImageData: TBytes;
begin
  Result := nil;
  if (FDataLen <= 0) or (FDataAt < 0) or (Int64(FDataAt) + FDataLen > Length(FSource)) then Exit;
  if FHex then
    Result := KeptDecodeHex(PByte(PAnsiChar(FSource)) + FDataAt, FDataLen)
  else
  begin
    SetLength(Result, FDataLen);
    Move((PByte(PAnsiChar(FSource)) + FDataAt)^, Result[0], FDataLen);
  end;
end;

var
  GNextFieldId: Int64 = 0;
  GOwnedMarks: Int64 = 0;

constructor TTyRichFieldMark.CreateOwned(AKind: TTyRichFieldMarkKind; AId: Int64;
  const AInstruction: UTF8String; AFlags: Byte);
begin
  inherited Create;
  FKind := AKind;
  FId := AId;
  FOwned := True;
  if AKind = rfmOpen then
  begin
    FInstruction := AInstruction;
    FFlags := AFlags;
  end;
  Inc(GOwnedMarks);
end;

destructor TTyRichFieldMark.Destroy;
begin
  if FOwned then Dec(GOwnedMarks);
  inherited Destroy;
end;

class function TTyRichFieldMark.OwnedAlive: Int64;
begin
  Result := GOwnedMarks;
end;

constructor TTyRichFieldMark.Create(AKind: TTyRichFieldMarkKind; AId: Int64;
  const ABytes: RawByteString; ARawUc: Integer);
begin
  inherited Create;
  FKind := AKind;
  FId := AId;
  if AKind = rfmOpen then FBytes := ABytes;
  if ARawUc >= 0 then FRawUc := ARawUc;
end;

constructor TTyRichFieldMark.CreateInFile(AId: Int64; const AFile: TBytes; AStart, ALen: Int64;
  ARawUc: Integer);
begin
  inherited Create;
  if (AStart < 0) or (ALen <= 0) or (AStart + ALen > Length(AFile)) then
    raise ETyRichModel.Create('A field mark''s bytes must lie in its file');
  FKind := rfmOpen;
  FId := AId;
  FFile := AFile;
  FFileStart := AStart;
  FFileLen := ALen;
  if ARawUc >= 0 then FRawUc := ARawUc;
end;

procedure TTyRichFieldMark.SetSlotFont(AIndex: Integer; const AName: UTF8String; ACharset: Integer);
begin
  FSlotNames[AIndex] := AName;
  FSlotCharsets[AIndex] := ACharset;
end;

procedure TTyRichFieldMark.SetSlot(ASlot: Byte);
begin
  FSlot := ASlot;
end;

function TTyRichFieldMark.HasSlots: Boolean;
begin
  Result := (FSlotNames[0] <> '') or (FSlotNames[1] <> '') or (FSlotNames[2] <> '');
end;

function TTyRichFieldMark.SlotName(AIndex: Integer): UTF8String;
begin
  Result := FSlotNames[AIndex];
end;

function TTyRichFieldMark.SlotCharset(AIndex: Integer): Integer;
begin
  Result := FSlotCharsets[AIndex];
end;

function TTyRichFieldMark.InFile: Boolean;
begin
  Result := FFile <> nil;
end;

function TTyRichFieldMark.BytesData: PByte;
begin
  if FFile <> nil then Result := @FFile[FFileStart]
  else if FBytes <> '' then Result := PByte(PAnsiChar(FBytes))
  else Result := nil;
end;

function TTyRichFieldMark.BytesLength: Int64;
begin
  if FFile <> nil then Result := FFileLen else Result := Length(FBytes);
end;

function TTyRichFieldMark.GetBytes: RawByteString;
begin
  if FFile = nil then Exit(FBytes);
  Result := '';
  SetLength(Result, FFileLen);
  Move(FFile[FFileStart], Result[1], FFileLen);
  SetCodePage(Result, CP_NONE, False);
end;

function TTyRichFieldMark.Clone: TTyRichObject;
var
  i: Integer;
begin
  if FOwned then Exit(TTyRichFieldMark.CreateOwned(FKind, FId, FInstruction, FFlags));
  Result := TTyRichFieldMark.Create(FKind, FId, GetBytes, FRawUc);
  for i := 0 to 2 do TTyRichFieldMark(Result).SetSlotFont(i, FSlotNames[i], FSlotCharsets[i]);
  TTyRichFieldMark(Result).FSlot := FSlot;
end;

function TTyRichFieldMark.DataBytes: Int64;
begin
  Result := InstanceSize + Length(FBytes) + Length(FInstruction);
end;

function TTyRichFieldMark.SharedData(out ABytes: Int64): Pointer;
begin
  ABytes := Length(FBytes);
  if ABytes > 0 then Result := Pointer(FBytes) else Result := nil;
end;

class function TTyRichFieldMark.NewId: Int64;
begin
  Dec(GNextFieldId);
  Result := GNextFieldId;
end;

{ The marks of a paragraph's runs: open ones less close ones. }
function MarkBalance(const ARuns: TTyRunArray): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(ARuns) do
    if ARuns[i].Obj is TTyRichFieldMark then
      if TTyRichFieldMark(ARuns[i].Obj).Kind = rfmOpen then Inc(Result) else Dec(Result);
end;

{ The run is a field mark of AKind. }
function IsMark(const ARun: TTyRichRun; AKind: TTyRichFieldMarkKind): Boolean; inline;
begin
  Result := (ARun.Obj is TTyRichFieldMark) and (TTyRichFieldMark(ARun.Obj).Kind = AKind);
end;

{ ---- tables ---- }

function TTyRichCell.Table: TTyRichTable;
begin
  Result := FRow.FTable;
end;

destructor TTyRichRow.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FCells) do FCells[i].Free;
  if FFormat <> nil then FFormat.Release;
  if FBase <> nil then FBase.Release;
  inherited Destroy;
end;

procedure TTyRichRow.SetFormats(ABase, AFormat: TTyRichRowFormat);
begin
  // (references of its own, taken before the old ones go: they may be the same)
  if ABase <> nil then ABase.AddRef;
  if AFormat <> nil then AFormat.AddRef;
  if FBase <> nil then FBase.Release;
  if FFormat <> nil then FFormat.Release;
  FBase := ABase;
  FFormat := AFormat;
  if (FFormat = nil) <> (FBase = nil) then
  begin
    // one alone means both: what the bytes say
    if FFormat = nil then FFormat := FBase else FBase := FFormat;
    FFormat.AddRef;
  end;
end;

function TTyRichRow.Format: TTyRichRowFormat;
begin
  if FFormat = nil then
  begin
    // (a row made without one: its bytes have no colour of a file to resolve)
    FFormat := TyRichDecodeRowFormat(FRawFormat, Length(FCells), []);
    FBase := FFormat;
    FBase.AddRef;
  end;
  Result := FFormat;
end;

function TTyRichRow.BaseFormat: TTyRichRowFormat;
begin
  Format;
  Result := FBase;
end;

function TTyRichRow.Edited: Boolean;
begin
  Result := (FFormat <> nil) and ((FFormat <> FBase) or FEdgesMoved);
end;

function TTyRichRow.Display: TTyRowDisplay;
begin
  if Edited then Exit(TyRichFormatDisplay(FFormat, CellEdges));
  if FRawFormat <> '' then Result := TyRtfRowDisplay(FRawFormat)
  else if Length(FCells) > 1 then Result := TyDefaultRowDisplay(Length(FCells))
  else Result := TyDefaultRowDisplay(1);
end;

function TTyRichRow.GetCell(AIndex: Integer): TTyRichCell;
begin
  if (AIndex < 0) or (AIndex > High(FCells)) then
    raise ETyRichModel.CreateFmt('Cell index %d out of range', [AIndex]);
  Result := FCells[AIndex];
end;

function TTyRichRow.GetBoundary(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > High(FBoundaries)) then
    raise ETyRichModel.CreateFmt('Boundary index %d out of range', [AIndex]);
  Result := FBoundaries[AIndex];
end;

function TTyRichRow.CellCount: Integer;
begin
  Result := Length(FCells);
end;

function TTyRichRow.BoundaryCount: Integer;
begin
  Result := Length(FBoundaries);
end;

function TTyRichRow.CellEdges: TTyRichEdges;
var
  i, e: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FCells));
  e := 0;
  for i := 0 to High(Result) do
  begin
    if i < Length(FBoundaries) then e := FBoundaries[i]
    else if (Length(FBoundaries) = 0) and (i < Length(FTable.FColBoundaries)) then
      e := FTable.FColBoundaries[i]
    else
      Inc(e, 1440);
    Result[i] := e;
  end;
end;

constructor TTyRichTable.Create(const AColBoundaries: array of Integer;
  AContentLocked: Boolean; ACut: Boolean);
var
  i: Integer;
begin
  inherited Create;
  SetLength(FColBoundaries, Length(AColBoundaries));
  for i := 0 to High(AColBoundaries) do FColBoundaries[i] := AColBoundaries[i];
  FContentLocked := AContentLocked;
  FCut := ACut;
  FStructureLocked := AContentLocked or ACut;
  // (every row AddRow makes gets its paragraphs: a reader's, MarkTable's, an edit's)
  FRowsValid := True;
end;

destructor TTyRichTable.Destroy;
var
  i: Integer;
begin
  // (a row freed before is a nil slot)
  for i := 0 to FOwnedCount - 1 do FOwned[i].Free;
  inherited Destroy;
end;

function TTyRichTable.LiveRowCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FOwnedCount - 1 do
    if FOwned[i] <> nil then Inc(Result);
end;

procedure OwnRow(T: TTyRichTable; R: TTyRichRow);
begin
  if T.FOwnedCount = Length(T.FOwned) then SetLength(T.FOwned, T.FOwnedCount * 2 + 4);
  T.FOwned[T.FOwnedCount] := R;
  R.FOwnedAt := T.FOwnedCount;
  Inc(T.FOwnedCount);
end;

// one more refers to row R (an edit's row; the others are their table's for its life)
procedure RowAddRef(R: TTyRichRow); inline;
begin
  if (R <> nil) and R.FFreeable then Inc(R.FRefs);
end;

{ One less refers to row R: the last one frees it - never a row that is still one of its
  table's rows of now. }
procedure RowRelease(R: TTyRichRow);
var
  t: TTyRichTable;
begin
  if (R = nil) or not R.FFreeable or (R.FRefs <= 0) then Exit;
  Dec(R.FRefs);
  if R.FRefs > 0 then Exit;
  t := R.FTable;
  if (R.FIndex >= 0) and (R.FIndex <= High(t.FRows)) and (t.FRows[R.FIndex] = R) then Exit;
  if (R.FOwnedAt >= 0) and (R.FOwnedAt < t.FOwnedCount) and (t.FOwned[R.FOwnedAt] = R) then
    t.FOwned[R.FOwnedAt] := nil;
  R.Free;
end;

{ A row of T that is in none of its places yet (Index -1): an edit's new row or a row's new
  look. ABase / AFormat nil: decoded from ARaw when asked. }
function NewRowIn(T: TTyRichTable; ACellCount: Integer; const ARaw: RawByteString;
  const AEdges: array of Integer; ANested: Boolean; ABase, AFormat: TTyRichRowFormat): TTyRichRow;
var
  i: Integer;
  c: TTyRichCell;
begin
  if ACellCount < 1 then
    raise ETyRichModel.Create('A row needs at least one cell');
  Result := TTyRichRow.Create;
  OwnRow(T, Result);
  Result.FFreeable := True;
  Result.FTable := T;
  Result.FIndex := -1;
  Result.FRawFormat := ARaw;
  Result.FHoldsNestedTable := ANested;
  SetLength(Result.FBoundaries, Length(AEdges));
  for i := 0 to High(AEdges) do Result.FBoundaries[i] := AEdges[i];
  SetLength(Result.FCells, ACellCount);
  for i := 0 to ACellCount - 1 do
  begin
    c := TTyRichCell.Create;
    c.FRow := Result;
    c.FIndex := i;
    Result.FCells[i] := c;
  end;
  Result.SetFormats(ABase, AFormat);
end;

{ T's rows AAt .. AAt + AOldCount - 1 become ANew; every row from AAt on is given its place
  as its index. }
procedure ReplaceRowRange(T: TTyRichTable; AAt, AOldCount: Integer; const ANew: array of TTyRichRow);
var
  n, d, tail, i: Integer;
  old: array of TTyRichRow;
begin
  // (the rows that come in are referred to by the table first, those that go let go last)
  for i := 0 to High(ANew) do RowAddRef(ANew[i]);
  old := nil;
  SetLength(old, AOldCount);
  for i := 0 to AOldCount - 1 do old[i] := T.FRows[AAt + i];
  n := Length(T.FRows);
  d := Length(ANew) - AOldCount;
  tail := n - AAt - AOldCount;
  if d > 0 then
  begin
    SetLength(T.FRows, n + d);
    if tail > 0 then
      Move(T.FRows[AAt + AOldCount], T.FRows[AAt + AOldCount + d], tail * SizeOf(Pointer));
  end
  else if d < 0 then
  begin
    if tail > 0 then
      Move(T.FRows[AAt + AOldCount], T.FRows[AAt + Length(ANew)], tail * SizeOf(Pointer));
    SetLength(T.FRows, n + d);
  end;
  for i := 0 to High(ANew) do T.FRows[AAt + i] := ANew[i];
  if d = 0 then n := AAt + Length(ANew) else n := Length(T.FRows);
  for i := AAt to n - 1 do T.FRows[i].FIndex := i;
  for i := 0 to High(old) do RowRelease(old[i]);
end;

function TTyRichTable.AddRow(ACellCount: Integer; const ARawFormat: RawByteString): TTyRichRow;
begin
  Result := AddRow(ACellCount, ARawFormat, []);
end;

function TTyRichTable.AddRow(ACellCount: Integer; const ARawFormat: RawByteString;
  const ABoundaries: array of Integer; AHoldsNestedTable: Boolean): TTyRichRow;
begin
  if FFrozen then
    raise ETyRichModel.Create('A table in use cannot change its rows');
  if FAdded < FOwnedCount then
    raise ETyRichModel.Create('A table an edit changed cannot be given rows');
  Result := NewRowIn(Self, ACellCount, ARawFormat, ABoundaries, AHoldsNestedTable, nil, nil);
  // (the table's for its life: a reader finds it by its number)
  Result.FFreeable := False;
  Inc(FAdded);
  Result.FIndex := Length(FRows);
  SetLength(FRows, Length(FRows) + 1);
  FRows[High(FRows)] := Result;
end;

function TTyRichTable.AddedRow(AIndex: Integer): TTyRichRow;
begin
  if (AIndex < 0) or (AIndex >= FAdded) then
    raise ETyRichModel.CreateFmt('Row index %d out of range', [AIndex]);
  Result := FOwned[AIndex];
end;

function TTyRichTable.AddedRowCount: Integer;
begin
  Result := FAdded;
end;

procedure TTyRichTable.SetLastRowFormat(AFormat: TTyRichRowFormat);
begin
  if FFrozen then
    raise ETyRichModel.Create('A table in use cannot change its rows');
  if FAdded = 0 then
    raise ETyRichModel.Create('The table has no row');
  FOwned[FAdded - 1].SetFormats(AFormat, AFormat);
end;

function TTyRichTable.GetRow(AIndex: Integer): TTyRichRow;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
    raise ETyRichModel.CreateFmt('Row index %d out of range', [AIndex]);
  Result := FRows[AIndex];
end;

function TTyRichTable.GetColBoundary(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > High(FColBoundaries)) then
    raise ETyRichModel.CreateFmt('Column boundary index %d out of range', [AIndex]);
  Result := FColBoundaries[AIndex];
end;

function TTyRichTable.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TTyRichTable.CellCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FRows) do Inc(Result, Length(FRows[i].FCells));
end;

function TTyRichTable.ColBoundaryCount: Integer;
begin
  Result := Length(FColBoundaries);
end;

function TTyRichTable.MemSize: Int64;
var
  i: Integer;
  r: TTyRichRow;
begin
  Result := InstanceSize + Length(FRows) * SizeOf(Pointer) +
    Length(FColBoundaries) * SizeOf(Integer) + Length(FOwned) * SizeOf(Pointer);
  // every row alive: of now, and the versions steps and values hold
  for i := 0 to FOwnedCount - 1 do
  begin
    r := FOwned[i];
    if r = nil then Continue;
    Inc(Result, r.InstanceSize + Length(r.FRawFormat) + Length(r.FBoundaries) * SizeOf(Integer) +
      Length(r.FCells) * (TTyRichCell.InstanceSize + SizeOf(Pointer)));
  end;
end;

{ ---- TTyRichUndoData ---- }

destructor TTyRichUndoData.Destroy;
var
  i: Integer;
begin
  for i := High(FParts) downto 0 do FreeAndNil(FParts[i]);
  for i := 0 to FOldCount - 1 do FDoc.ReleaseData(FOldData[i].Data);
  for i := 0 to High(FRemoved.Pieces) do
    if (FRemoved.Pieces[i].Separator <> rsNone) and (FRemoved.Pieces[i].Data <> nil) then
      FDoc.ReleaseData(TTyRichParaData(FRemoved.Pieces[i].Data));
  for i := 0 to FSwapCount - 1 do FDoc.ReleaseData(FSwaps[i].Old);
  for i := 0 to FSwapPieceCount - 1 do
    if (FSwapPieces[i].Separator <> rsNone) and (FSwapPieces[i].Data <> nil) then
      FDoc.ReleaseData(TTyRichParaData(FSwapPieces[i].Data));
  // the row versions the step held (after the values, which may name their cells; before the
  // table, which frees what is left of its rows with it)
  for i := 0 to High(FRowsOld) do RowRelease(FRowsOld[i]);
  for i := 0 to High(FRowsNew) do RowRelease(FRowsNew[i]);
  if FRowTable <> nil then FRowTable.Release;
  inherited Destroy;
end;

function TTyRichUndoData.MemSize: Int64;
var
  i: Integer;
begin
  Result := InstanceSize + (Length(FRemoved.Pieces) + Length(FSpan.Pieces.Pieces) +
    Length(FSpan2.Pieces.Pieces) + Length(FSwapPieces)) * SizeOf(TTyRichPiece) +
    Length(FOldData) * SizeOf(TTyRichOldData) + Length(FSwaps) * SizeOf(TTyRichParaSwap) +
    Length(FParts) * SizeOf(Pointer) + FExtraBytes +
    (Length(FRowsOld) + Length(FRowsNew)) * SizeOf(Pointer) + Length(FRowsOldIdx) * SizeOf(Integer);
  for i := 0 to High(FParts) do Inc(Result, FParts[i].MemSize);
end;

procedure ComposeChange(var A: TTyRichChange; var AHas: Boolean; const B: TTyRichChange); forward;

procedure TTyRichUndoData.SealParts;
begin
  SetLength(FParts, FPartCount);
end;

procedure TTyRichUndoData.AddPart(APart: TTyRichUndoData);
var
  has: Boolean;
begin
  // (one part a row for an edit of columns: the list grows by halves, not one by one)
  if FPartCount = Length(FParts) then SetLength(FParts, FPartCount * 2 + 4);
  FParts[FPartCount] := APart;
  Inc(FPartCount);
  // what it reports is what its parts that told of themselves did, one after the other
  if APart.FChange.Kinds = [] then Exit;
  has := FChange.Kinds <> [];
  ComposeChange(FChange, has, APart.FChange);
end;

procedure AddObject(var AList: TTyRichObjectList; var ACount: Integer; AObj: TTyRichObject);
begin
  if ACount = Length(AList) then SetLength(AList, ACount * 2 + 4);
  AList[ACount] := AObj;
  Inc(ACount);
end;

procedure SortObjects(var AList: TTyRichObjectList; ALo, AHi: Integer);
var
  i, j: Integer;
  p, t: TTyRichObject;
begin
  while ALo < AHi do
  begin
    i := ALo;
    j := AHi;
    p := AList[(ALo + AHi) div 2];
    repeat
      while PtrUInt(AList[i]) < PtrUInt(p) do Inc(i);
      while PtrUInt(AList[j]) > PtrUInt(p) do Dec(j);
      if i <= j then
      begin
        t := AList[i];
        AList[i] := AList[j];
        AList[j] := t;
        Inc(i);
        Dec(j);
      end;
    until i > j;
    if j - ALo < AHi - i then
    begin
      if ALo < j then SortObjects(AList, ALo, j);
      ALo := i;
    end
    else
    begin
      if i < AHi then SortObjects(AList, i, AHi);
      AHi := j;
    end;
  end;
end;

procedure TTyRichUndoData.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
var
  i: Integer;

  // the objects of a value this record holds
  procedure Take(D: TTyRichParaData);
  var
    j: Integer;
  begin
    if D = nil then Exit;
    { In the history's gathering: a value of no objects, or of objects already gathered or
      held by the step (its key met), adds nothing - no walk of its runs. }
    if FDoc.FGathering and ((D.FObjKey = 0) or not FDoc.MeetKey(D.FObjKey)) then Exit;
    for j := 0 to High(D.FRuns) do
      if D.FRuns[j].Obj <> nil then
      begin
        Inc(FDoc.FHistoryObjectVisits);
        AddObject(AList, ACount, D.FRuns[j].Obj);
      end;
  end;

begin
  { Every object a value this record keeps holds - also while the document or a reader's
    resident values hold it too: the history counts it once however many steps hold it,
    which over-counts one the document still shows (the safe side, bounded by the
    document's own pictures). One pass over the values, no lookup per object. }
  for i := 0 to FOldCount - 1 do Take(FOldData[i].Data);
  for i := 0 to High(FRemoved.Pieces) do
    if FRemoved.Pieces[i].Separator <> rsNone then Take(TTyRichParaData(FRemoved.Pieces[i].Data));
  for i := 0 to FSwapCount - 1 do Take(FSwaps[i].Old);
  for i := 0 to FSwapPieceCount - 1 do
    if FSwapPieces[i].Separator <> rsNone then Take(TTyRichParaData(FSwapPieces[i].Data));
  for i := 0 to High(FParts) do FParts[i].GatherObjects(AList, ACount);
end;

procedure TTyRichUndoData.AddOld(D: TTyRichParaData);
begin
  if (FOldCount > 0) and (FOldData[FOldCount - 1].Data = D) then
  begin
    Inc(FOldData[FOldCount - 1].Count);
    Exit;
  end;
  if FOldCount = Length(FOldData) then SetLength(FOldData, FOldCount * 2 + 1);
  FOldData[FOldCount].Data := D;
  FOldData[FOldCount].Count := 1;
  Inc(FOldCount);
  FDoc.AcquireData(D);
end;

procedure TTyRichUndoData.SealOld;
begin
  SetLength(FOldData, FOldCount);
end;

procedure TTyRichUndoData.AddSwap(APara: Integer; AOld: TTyRichParaData;
  const APieces: TTyRichPieces);
var
  i: Integer;
begin
  if FSwapCount = Length(FSwaps) then SetLength(FSwaps, FSwapCount * 2 + 4);
  FSwaps[FSwapCount].Para := APara;
  FSwaps[FSwapCount].Old := AOld;
  FSwaps[FSwapCount].First := FSwapPieceCount;
  FSwaps[FSwapCount].Count := Length(APieces.Pieces);
  Inc(FSwapCount);
  FDoc.AcquireData(AOld);
  for i := 0 to High(APieces.Pieces) do
  begin
    if FSwapPieceCount = Length(FSwapPieces) then
      SetLength(FSwapPieces, FSwapPieceCount * 2 + 4);
    FSwapPieces[FSwapPieceCount] := APieces.Pieces[i];
    Inc(FSwapPieceCount);
    // (the value after its separator: the one the paragraph after it gets back)
    if (APieces.Pieces[i].Separator <> rsNone) and (APieces.Pieces[i].Data <> nil) then
      FDoc.AcquireData(TTyRichParaData(APieces.Pieces[i].Data));
  end;
end;

procedure TTyRichUndoData.SealSwaps;
begin
  SetLength(FSwaps, FSwapCount);
  SetLength(FSwapPieces, FSwapPieceCount);
end;

{ ---- runs ---- }

procedure AppendRun(var A: TTyRunArray; var N: Integer; AStart: Int64;
  AFormat: TTyCharFormatId; AObj: TTyRichObject);
begin
  if AStart > High(LongInt) then
    raise ETyRichModel.Create('A formatted paragraph is limited to 2^31-1 characters');
  // a run that would be empty gives way; an equal plain neighbour absorbs the new one
  while (N > 0) and (A[N - 1].Start >= AStart) do Dec(N);
  if (N > 0) and (AObj = nil) and (A[N - 1].Obj = nil) and (A[N - 1].Format = AFormat) then
    Exit;
  if N = Length(A) then SetLength(A, N * 2 + 4);
  A[N].Start := AStart;
  A[N].Format := AFormat;
  A[N].Obj := AObj;
  Inc(N);
end;

function RunEnd(const R: TTyRunArray; AIndex: Integer; ALen: Int64): Int64; inline;
begin
  if AIndex < High(R) then Result := R[AIndex + 1].Start else Result := ALen;
end;

{ Appends the parts of R (a paragraph of ALen characters) inside [AFrom, ATo), moved by
  ADelta. }
procedure AppendSlice(var A: TTyRunArray; var N: Integer; const R: TTyRunArray; ALen: Int64;
  AFrom, ATo, ADelta: Int64);
var
  j: Integer;
  s, e: Int64;
begin
  for j := 0 to High(R) do
  begin
    s := R[j].Start;
    if s >= ATo then Break;
    e := RunEnd(R, j, ALen);
    if e <= AFrom then Continue;
    if s < AFrom then s := AFrom;
    if e > ATo then e := ATo;
    if s < e then AppendRun(A, N, s + ADelta, R[j].Format, R[j].Obj);
  end;
end;

function RunIndexAt(const R: TTyRunArray; AOffset: Int64): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(R);
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if R[mid].Start <= AOffset then lo := mid else hi := mid - 1;
  end;
  Result := lo;
end;

function InheritedFormat(const R: TTyRunArray; AOffset: Int64): TTyCharFormatId;
begin
  if AOffset > 0 then
    Result := R[RunIndexAt(R, AOffset - 1)].Format
  else
    Result := R[0].Format;
end;

function SameRuns(const A, B: TTyRunArray): Boolean;
var
  i: Integer;
begin
  if Pointer(A) = Pointer(B) then Exit(True);
  if Length(A) <> Length(B) then Exit(False);
  for i := 0 to High(A) do
    if (A[i].Start <> B[i].Start) or (A[i].Format <> B[i].Format) or (A[i].Obj <> B[i].Obj) then
      Exit(False);
  Result := True;
end;

{ ---- TTyRichDocBuilder ---- }

{ Checks a reader's runs for paragraph AIndex (raises when malformed); its length. }
function CheckReaderRuns(ADoc: TTyRichDocument; AIndex: Integer; AParaFormat: TTyParaFormatId;
  const ARuns: TTyRunArray): Int64;
var
  i: Integer;
begin
  ADoc.CheckParaId(AParaFormat);
  if Length(ARuns) = 0 then
    raise ETyRichModel.Create('A paragraph needs at least one run');
  Result := ADoc.FText.ParaLength(AIndex);
  for i := 0 to High(ARuns) do
  begin
    ADoc.CheckCharId(ARuns[i].Format);
    if ((i = 0) and (ARuns[i].Start <> 0)) or ((i > 0) and (ARuns[i].Start <= ARuns[i - 1].Start)) or
       ((i > 0) and (ARuns[i].Start >= Result)) or
       ((ARuns[i].Obj <> nil) and (RunEnd(ARuns, i, Result) <> ARuns[i].Start + 1)) then
      raise ETyRichModel.CreateFmt('Runs of paragraph %d are malformed', [AIndex]);
  end;
end;

{ A reader's value for a paragraph of ALen characters (checked runs), not held. }
function ReaderValue(ADoc: TTyRichDocument; ALen: Int64; AParaFormat: TTyParaFormatId;
  const ARuns: TTyRunArray; ACell: TTyRichCell; const AListText: UTF8String;
  AFieldDepth: Integer): TTyRichParaData;
var
  runs: TTyRunArray;
  n: Integer;
begin
  if AFieldDepth < 0 then
    raise ETyRichModel.Create('A paragraph cannot start inside fewer than no fields');
  runs := nil;
  n := 0;
  if ALen = 0 then
    AppendRun(runs, n, 0, ARuns[0].Format, ARuns[0].Obj)
  else
    AppendSlice(runs, n, ARuns, ALen, 0, ALen, 0);
  SetLength(runs, n);
  if AListText <> '' then
  begin
    Result := ADoc.NewData(AParaFormat, runs, ACell, AFieldDepth);
    Result.FListText := AListText;
  end
  else
    Result := ADoc.MakeData(AParaFormat, runs, ACell, AFieldDepth);
end;

class function TTyRichDocBuilder.MakeValue(ADoc: TTyRichDocument; AIndex: Integer;
  AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell;
  const AListText: UTF8String; AFieldDepth: Integer): Pointer;
var
  d: TTyRichParaData;
begin
  d := ReaderValue(ADoc, CheckReaderRuns(ADoc, AIndex, AParaFormat, ARuns), AParaFormat, ARuns,
    ACell, AListText, AFieldDepth);
  ADoc.AcquireData(d);
  Result := d;
end;

class function TTyRichDocBuilder.SetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
  AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell;
  const AListText: UTF8String; AFieldDepth: Integer): Boolean;
var
  len: Int64;
begin
  len := CheckReaderRuns(ADoc, AIndex, AParaFormat, ARuns);
  if ADoc.SlotData(AIndex) <> nil then Exit(False);
  ADoc.PutData(AIndex, nil, ReaderValue(ADoc, len, AParaFormat, ARuns, ACell, AListText,
    AFieldDepth));
  Result := True;
end;

class procedure TTyRichDocBuilder.SetDefaultCharFormat(ADoc: TTyRichDocument;
  const AFormat: TTyCharFormat);
begin
  ADoc.SetDefaults(AFormat);
end;

class procedure TTyRichDocBuilder.SetPage(ADoc: TTyRichDocument; APaperWidth, APaperHeight,
  AMarginLeft, AMarginRight: Integer);
begin
  ADoc.FPaperWidth := APaperWidth;
  ADoc.FPaperHeight := APaperHeight;
  ADoc.FMarginLeft := AMarginLeft;
  ADoc.FMarginRight := AMarginRight;
end;

class procedure TTyRichDocBuilder.SetDefaultParaFormat(ADoc: TTyRichDocument;
  const AFormat: TTyParaFormat);
begin
  ADoc.SetDefaultPara(AFormat);
end;

class procedure TTyRichDocBuilder.SetDocumentColor(ADoc: TTyRichDocument; AColor: TColor);
begin
  ADoc.FDocumentColor := AColor;
end;

class procedure TTyRichDocBuilder.ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText);
begin
  if AText = nil then
    raise ETyRichModel.Create('ReplaceText needs a text');
  ADoc.ResetContent(AText, teUtf8, 0, False, TyRichMajorityLineBreak(
    AText.LoadedSeparators(rsCR), AText.LoadedSeparators(rsLF), AText.LoadedSeparators(rsCRLF)));
end;

class procedure TTyRichDocBuilder.ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText;
  AEncoding: TTyTextEncoding; ACodePage: Integer; AHasBom: Boolean;
  ALineBreak: TTyRichSeparator);
begin
  ADoc.ResetContent(AText, AEncoding, ACodePage, AHasBom, ALineBreak);
end;

class procedure TTyRichDocBuilder.SetLoadState(ADoc: TTyRichDocument; ALoading,
  AIncomplete: Boolean);
begin
  ADoc.FLoadingContent := ALoading;
  ADoc.FIncomplete := AIncomplete;
end;

class procedure TTyRichDocBuilder.ReportLoad(ADoc: TTyRichDocument; const AChange: TTyRichChange);
begin
  if Assigned(ADoc.FOnChange) then ADoc.FOnChange(ADoc, AChange);
end;

class function TTyRichDocBuilder.ParagraphValue(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
begin
  Result := ADoc.SlotData(AIndex);
end;

class procedure TTyRichDocBuilder.HoldValue(ADoc: TTyRichDocument; AValue: Pointer);
begin
  ADoc.AcquireData(TTyRichParaData(AValue));
end;

class procedure TTyRichDocBuilder.ReleaseValue(ADoc: TTyRichDocument; AValue: Pointer);
begin
  ADoc.ReleaseData(TTyRichParaData(AValue));
end;

class function TTyRichDocBuilder.ValueShared(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
begin
  Result := (AValue <> nil) and (AValue <> Pointer(ADoc.FPlainParsed)) and
    (TTyRichParaData(AValue).FRefCount > 1);
end;

class function TTyRichDocBuilder.IsPlainValue(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
begin
  Result := (AValue <> nil) and (AValue = Pointer(ADoc.FPlainParsed));
end;

class function TTyRichDocBuilder.UnsetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
  AValue: Pointer): Boolean;
begin
  // without a loader nil means plain, not unparsed
  Result := (ADoc.FLoader <> nil) and (AValue <> nil) and
    (Pointer(ADoc.SlotData(AIndex)) = AValue);
  if Result then ADoc.PutData(AIndex, TTyRichParaData(AValue), nil);
end;

class function TTyRichDocBuilder.DocumentBusy(ADoc: TTyRichDocument): Boolean;
begin
  Result := (ADoc.FRunning <> nil) or (ADoc.FEditing > 0) or (ADoc.FReading > 0);
end;

{ ---- TTyRichParaLoader ---- }

procedure TTyRichParaLoader.ParagraphRead(ADoc: TTyRichDocument; AIndex: Integer);
begin
end;

procedure TTyRichParaLoader.ReadsEnded(ADoc: TTyRichDocument);
begin
end;

function TTyRichParaLoader.WholeTable(ADoc: TTyRichDocument; AIndex: Integer;
  out AFirst, ALast: Integer): Boolean;
begin
  AFirst := -1;
  ALast := -1;
  Result := False;
end;

function TTyRichParaLoader.ParaFieldDepths(ADoc: TTyRichDocument; AIndex: Integer;
  out AStart, ALow: Integer): Boolean;
begin
  AStart := 0;
  ALow := 0;
  Result := False;
end;

function TTyRichParaLoader.ParaHoldsMarks(ADoc: TTyRichDocument; AIndex: Integer;
  out AHolds: Boolean): Boolean;
begin
  AHolds := False;
  Result := False;
end;

{ ---- TTyRichDocument: life ---- }

constructor TTyRichDocument.Create;
begin
  inherited Create;
  FText := TTyRichText.Create;
  Init;
end;

constructor TTyRichDocument.CreateFromUtf8(const ABuffer: TBytes);
begin
  inherited Create;
  FText := TTyRichText.CreateFromUtf8(ABuffer);
  Init;
end;

constructor TTyRichDocument.CreateOnText(AText: TTyRichText);
begin
  inherited Create;
  if AText = nil then
    raise ETyRichModel.Create('CreateOnText needs a text');
  FText := AText;
  Init;
end;

procedure TTyRichDocument.Init;
begin
  FFormats := TTyFormatPool.Create;
  FDefaultParaId := FFormats.InternPara(TyDefaultParaFormat);
  SetDefaults(TyDefaultCharFormat);
  SetDefaultPage;
  FMaxUndoBytes := DefaultMaxUndoBytes;
  FState := 0;
  FSavedState := 0;
  FNextState := 1;
  FText.OnParasChanged := @TextParasChanged;
  FText.OnParaDataDropped := @TextDataDropped;
  FSourceEncoding := teUtf8;
  FSourceCodePage := 0;
  FSourceHasBom := False;
  // over a buffer: the majority of its breaks; empty or lazy: none counted, the platform's
  FDominantLineBreak := TyRichMajorityLineBreak(FText.LoadedSeparators(rsCR),
    FText.LoadedSeparators(rsLF), FText.LoadedSeparators(rsCRLF));
end;

procedure TTyRichDocument.ResetContent(AText: TTyRichText; AEncoding: TTyTextEncoding;
  ACodePage: Integer; AHasBom: Boolean; ALineBreak: TTyRichSeparator);
var
  c: TTyRichChange;
begin
  if AText = nil then
    raise ETyRichModel.Create('ReplaceText needs a text');
  if AText = FText then
    raise ETyRichModel.Create('ReplaceText needs a new text');
  if (FRunning <> nil) or (FUpdateCount > 0) or FInLoad then
  begin
    AText.Free;
    // the history being built refers to the old content's paragraphs and pieces
    raise ETyRichModel.Create('A document cannot be replaced while a command runs or ' +
      'inside BeginUpdate .. EndUpdate');
  end;
  if (FSaving > 0) or (FReading > 0) then
  begin
    AText.Free;
    // a save walks the text and copies from the loader this would free; a read scope holds
    // tables, cells and objects of the content this would free
    raise ETyRichModel.Create('A document cannot be loaded into while it is being saved ' +
      'or read (inside BeginRead .. EndRead)');
  end;
  c := Default(TTyRichChange);
  c.Kinds := [rckText, rckFormat, rckStructure];
  c.OldLen := FText.Length;
  c.OldParaCount := FText.ParaCount;
  // as in Destroy: the history first, its records hold references to the values
  ClearHistory;
  FMergeBroken := False;
  FHasPending := False;
  FPending := Default(TTyRichChange);
  FText.OnParasChanged := nil;
  FText.OnParaDataDropped := nil;
  FValuesGone := True;
  while FFirstData <> nil do
    DisposeData(FFirstData);
  FValuesGone := False;
  FText.Free;
  FText := AText;
  FText.OnParasChanged := @TextParasChanged;
  FText.OnParaDataDropped := @TextDataDropped;
  // a loader parses the content it was made for
  if FOwnsLoader then FLoader.Free;
  FLoader := nil;
  FOwnsLoader := False;
  // the default font and the page were the old content's (an RTF file's): a text file
  // loaded next has neither, and would show in them
  FPlainFrozen := False;
  SetDefaults(TyDefaultCharFormat);
  SetDefaultPara(TyDefaultParaFormat);
  SetDefaultPage;
  FSourceEncoding := AEncoding;
  FSourceCodePage := ACodePage;
  FSourceHasBom := AHasBom;
  if ALineBreak = rsNone then ALineBreak := TyRichPlatformLineBreak;
  FDominantLineBreak := ALineBreak;
  // the content as loaded is the saved point
  FState := NewState;
  FSavedState := FState;
  FLoadingContent := False;
  FIncomplete := False;
  c.NewLen := FText.Length;
  c.NewParaCount := FText.ParaCount;
  if Assigned(FOnChange) then FOnChange(Self, c);
  NoteModified;
end;

procedure DropPropShape(ADoc: TTyRichDocument); forward;

destructor TTyRichDocument.Destroy;
var
  d: TTyRichParaData;
begin
  DropPropShape(Self);
  // the history first: its records hold references to the values disposed below
  ClearHistory;
  FreeAndNil(FObjHolds);
  FreeAndNil(FDataHolds);
  FreeAndNil(FKeyMet);
  if FText <> nil then
  begin
    FText.OnParasChanged := nil;
    FText.OnParaDataDropped := nil;
  end;
  // nothing may outlive the document (the history goes first), so every value still alive is
  // the text's or the plain sentinel; the text itself never frees data. From here on a
  // release can only come from a record that outlived its document: it raises instead of
  // writing into a freed value
  FValuesGone := True;
  while FFirstData <> nil do
  begin
    d := FFirstData;
    DisposeData(d);
  end;
  FText.Free;
  FFormats.Free;
  if FOwnsLoader then FLoader.Free;
  inherited Destroy;
end;

procedure TTyRichDocument.SetDefaultPage;
begin
  { A new document's page, and one not read from RTF (a reader of RTF sets the file's):
    A4 (Word's default page for a Chinese locale: a control for Chinese users), WordPad's 1.25"
    side margins }
  FPaperWidth := 11906;
  FPaperHeight := 16838;
  FMarginLeft := 1800;
  FMarginRight := 1800;
  FDocumentColor := clNone;
end;

procedure TTyRichDocument.SetDefaultPara(const AFormat: TTyParaFormat);
begin
  FDefaultParaId := FFormats.InternPara(AFormat);
  // the shared plain value follows the defaults, unless a change of them froze it
  if (FPlainParsed <> nil) and not FPlainFrozen then FPlainParsed.FParaFormat := FDefaultParaId;
end;

function TTyRichDocument.Settings: TTyRichDocSettings;
begin
  Result.PaperWidth := FPaperWidth;
  Result.PaperHeight := FPaperHeight;
  Result.MarginLeft := FMarginLeft;
  Result.MarginRight := FMarginRight;
  Result.CharFormat := FDefaultCharFormat;
  Result.ParaFormat := FFormats.ParaFormat(FDefaultParaId);
  Result.Color := FDocumentColor;
end;

procedure TTyRichDocument.PutSettings(const ASettings: TTyRichDocSettings);
begin
  FPaperWidth := ASettings.PaperWidth;
  FPaperHeight := ASettings.PaperHeight;
  FMarginLeft := ASettings.MarginLeft;
  FMarginRight := ASettings.MarginRight;
  if not ASettings.CharFormat.Equals(FDefaultCharFormat) then SetDefaults(ASettings.CharFormat);
  if not ASettings.ParaFormat.Equals(FFormats.ParaFormat(FDefaultParaId)) then
    SetDefaultPara(ASettings.ParaFormat);
  FDocumentColor := ASettings.Color;
end;

function TTyRichDocument.ChangeSettings(const ASettings: TTyRichDocSettings): TTyRichUndoData;
var
  c: TTyRichChange;
  old: TTyRichDocSettings;
  defaults: Boolean;
begin
  if (ASettings.PaperWidth <= 0) or (ASettings.MarginLeft < 0) or (ASettings.MarginRight < 0) or
     (Int64(ASettings.PaperWidth) - ASettings.MarginLeft - ASettings.MarginRight <= 0) then
    raise ETyRichModel.CreateFmt('A page %d twips wide with margins %d and %d has no room ' +
      'for text', [ASettings.PaperWidth, ASettings.MarginLeft, ASettings.MarginRight]);
  c := Default(TTyRichChange);
  old := Settings;
  defaults := not ASettings.CharFormat.Equals(old.CharFormat) or
    not ASettings.ParaFormat.Equals(old.ParaFormat);
  if not defaults and (ASettings.PaperWidth = old.PaperWidth) and
     (ASettings.PaperHeight = old.PaperHeight) and (ASettings.MarginLeft = old.MarginLeft) and
     (ASettings.MarginRight = old.MarginRight) and (ASettings.Color = old.Color) then
    Exit(NewUndo(c));
  Result := NewUndo(c);
  Result.FHasSettings := True;
  Result.FSettings := old;
  { What was read of a file keeps its look: the shared plain value takes the formats it shows
    as its own (the old defaults' runs - an array no one changes - and the format id it has),
    so that a paragraph parsed later in them is that value too (MakeData) and one parsed
    before stays as it was. }
  if defaults and (FPlainParsed <> nil) and not FPlainFrozen then
  begin
    FPlainParsed.FRuns := FDefaultRuns;
    FPlainParsed.FParaFormat := FDefaultParaId;
    FPlainFrozen := True;
    Result.FFroze := True;
  end;
  PutSettings(ASettings);
  c.Kinds := [rckFormat];
  c.Pos := 0;
  c.OldLen := FText.Length;
  c.NewLen := FText.Length;
  c.FirstPara := 0;
  c.OldParaCount := FText.ParaCount;
  c.NewParaCount := FText.ParaCount;
  Result.FChange := c;
  Notify(c);
end;

procedure TTyRichDocument.SetDefaults(const AFormat: TTyCharFormat);
begin
  FDefaultCharId := FFormats.InternChar(AFormat);
  FDefaultCharFormat := FFormats.CharFormat(FDefaultCharId);
  // a new array: values made earlier may share the old one
  FDefaultRuns := nil;
  SetLength(FDefaultRuns, 1);
  FDefaultRuns[0].Start := 0;
  FDefaultRuns[0].Format := FDefaultCharId;
  FDefaultRuns[0].Obj := nil;
end;

procedure TTyRichDocument.InstallLoader(ALoader: TTyRichParaLoader; AOwnsLoader: Boolean);
var
  d: TTyRichParaData;
begin
  if FOwnsLoader and (FLoader <> ALoader) then FLoader.Free;
  FLoader := ALoader;
  FOwnsLoader := AOwnsLoader;
  if (FLoader <> nil) and (FPlainParsed = nil) then
  begin
    // with a loader nil means "not parsed", so a parsed plain paragraph needs a value; one
    // shared value, held by the document itself
    d := TTyRichParaData.Create;
    d.FParaFormat := FDefaultParaId;
    d.FNext := FFirstData;
    if FFirstData <> nil then FFirstData.FPrev := d;
    FFirstData := d;
    Inc(FLiveData);
    Inc(GLiveParaValues);
    AcquireData(d);
    FPlainParsed := d;
  end;
end;

{ ---- paragraph values ---- }

function TTyRichDocument.NewData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
  ACell: TTyRichCell; AFieldDepth: Integer): TTyRichParaData;
var
  i: Integer;
  t: TTyRichTable;
begin
  Result := TTyRichParaData.Create;
  Result.FParaFormat := AParaFormat;
  Result.FRuns := ARuns;
  Result.FCell := ACell;
  Result.FFieldDepth := AFieldDepth;
  for i := 0 to High(ARuns) do
    if ARuns[i].Obj <> nil then
    begin
      ARuns[i].Obj.AddRef;
      // objects: a key of its own (MakeDataLike may give it its source's)
      if Result.FObjKey = 0 then
      begin
        Inc(FNextObjKey);
        Result.FObjKey := FNextObjKey;
      end;
    end;
  if ACell <> nil then
  begin
    t := ACell.Table;
    t.AddRef;
    Inc(t.FParaRefs);
    t.FFrozen := True;
    // (a value whose cell is one of a row's keeps that row alive)
    RowAddRef(ACell.FRow);
  end;
  Result.FNext := FFirstData;
  if FFirstData <> nil then FFirstData.FPrev := Result;
  FFirstData := Result;
  Inc(FLiveData);
  Inc(GLiveParaValues);
end;

procedure TTyRichDocument.DisposeData(D: TTyRichParaData);
var
  i: Integer;
  t: TTyRichTable;
  src: TTyRichParaData;
begin
  if D.FPrev <> nil then D.FPrev.FNext := D.FNext else FFirstData := D.FNext;
  if D.FNext <> nil then D.FNext.FPrev := D.FPrev;
  Dec(FLiveData);
  Dec(GLiveParaValues);
  if D = FPlainParsed then FPlainParsed := nil;
  for i := 0 to High(D.FRuns) do
    if D.FRuns[i].Obj <> nil then D.FRuns[i].Obj.Release;
  if D.FCell <> nil then
  begin
    t := D.FCell.Table;
    Dec(t.FParaRefs);
    // (the row first: the table's last release frees its rows with it)
    RowRelease(D.FCell.FRow);
    t.Release;
  end;
  src := D.FSource;
  // poison: a value used after it is gone shows up as garbage formats, not as the old ones
  D.FParaFormat := -1;
  D.FCell := nil;
  D.FRuns := nil;
  D.FListText := '';
  D.FSource := nil;
  D.FRefCount := -1;
  D.Free;
  // (never a chain: a source has no source of its own. When every value goes at once, the
  // source goes by itself, maybe already gone)
  if (src <> nil) and not FValuesGone then ReleaseData(src);
end;

procedure TTyRichDocument.AcquireData(D: TTyRichParaData);
begin
  if D <> nil then Inc(D.FRefCount);
end;

procedure TTyRichDocument.ReleaseData(D: TTyRichParaData);
begin
  if D = nil then Exit;
  if FValuesGone then
    raise ETyRichModel.Create('An undo record outlived the values of its document');
  if D.FRefCount <= 0 then
    raise ETyRichModel.Create('Paragraph data released more often than referenced');
  Dec(D.FRefCount);
  if D.FRefCount = 0 then DisposeData(D);
end;

function TTyRichDocument.PlainValue: TTyRichParaData;
begin
  if FLoader <> nil then Result := FPlainParsed else Result := nil;
end;

function TTyRichDocument.MakeData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
  ACell: TTyRichCell; AFieldDepth: Integer): TTyRichParaData;
begin
  // (the plain value starts outside every field: a paragraph of a result has one of its own)
  if FPlainFrozen and (FLoader <> nil) and (FPlainParsed <> nil) then
  begin
    // the shared value keeps the formats it had (ChangeSettings): what it shows is plain
    if (AParaFormat = FPlainParsed.FParaFormat) and (ACell = nil) and (Length(ARuns) = 1) and
       (ARuns[0].Format = FPlainParsed.FRuns[0].Format) and (ARuns[0].Obj = nil) and
       (AFieldDepth = 0) then
      Result := FPlainParsed
    else
      Result := NewData(AParaFormat, ARuns, ACell, AFieldDepth);
  end
  else if (AParaFormat = FDefaultParaId) and (ACell = nil) and (Length(ARuns) = 1) and
     (ARuns[0].Format = FDefaultCharId) and (ARuns[0].Obj = nil) and (AFieldDepth = 0) then
    Result := PlainValue
  else
    Result := NewData(AParaFormat, ARuns, ACell, AFieldDepth);
end;

function TTyRichDocument.DepthOfData(D: TTyRichParaData): Integer;
begin
  if D = nil then Result := 0 else Result := D.FFieldDepth;
end;

function TTyRichDocument.EndDepthOfData(D: TTyRichParaData): Integer;
begin
  Result := DepthOfData(D);
  if D <> nil then Inc(Result, MarkBalance(D.FRuns));
end;

function TTyRichDocument.WithDepth(D: TTyRichParaData; AFieldDepth: Integer): TTyRichParaData;
begin
  if DepthOfData(D) = AFieldDepth then Exit(D);
  // (made just now and held by no one - not the shared plain one: nobody can see it change)
  if (D <> nil) and (D.FRefCount = 0) and (D <> FPlainParsed) then
  begin
    D.FFieldDepth := AFieldDepth;
    Exit(D);
  end;
  Result := NewData(FormatOfData(D), RunsOfData(D), CellOfData(D), AFieldDepth);
  if D = nil then Exit;
  Result.FListText := D.FListText;
  // the very same objects: the same key
  if D.FObjKey <> 0 then Result.FObjKey := D.FObjKey;
  if D.FSource <> nil then
  begin
    AcquireData(D.FSource);
    Result.FSource := D.FSource;
  end;
end;

procedure TTyRichDocument.FixDepths(AFirst, ALast, AStartDepth: Integer);
var
  i, depth: Integer;
  d, nd: TTyRichParaData;
begin
  depth := AStartDepth;
  for i := AFirst to ALast do
  begin
    d := SlotData(i);
    nd := WithDepth(d, depth);
    if nd <> d then PutData(i, d, nd);
    depth := EndDepthOfData(nd);
  end;
end;

function TTyRichDocument.ParaHoldsMarks(AIndex: Integer): Boolean;
var
  d: TTyRichParaData;
  i: Integer;
begin
  d := TTyRichParaData(SlotData(AIndex));
  if (d = nil) and (FLoader <> nil) then
  begin
    if FLoader.ParaHoldsMarks(Self, AIndex, Result) then Exit;
    d := DataOf(AIndex);
  end;
  Result := False;
  if d = nil then Exit;
  for i := 0 to High(d.FRuns) do
    if d.FRuns[i].Obj is TTyRichFieldMark then Exit(True);
end;

procedure TTyRichDocument.ParaDepths(AIndex: Integer; out AStart, ALow: Integer);
begin
  ValueFieldDepths(SlotData(AIndex), AIndex, AStart, ALow);
end;

procedure TTyRichDocument.ValueFieldDepths(AData: Pointer; AIndex: Integer; out AStart,
  ALow: Integer);
var
  d: TTyRichParaData;
  i, depth: Integer;
begin
  d := TTyRichParaData(AData);
  if (d = nil) and (FLoader <> nil) then
  begin
    if FLoader.ParaFieldDepths(Self, AIndex, AStart, ALow) then Exit;
    d := DataOf(AIndex);
  end;
  AStart := DepthOfData(d);
  ALow := AStart;
  if d = nil then Exit;
  depth := AStart;
  for i := 0 to High(d.FRuns) do
    if d.FRuns[i].Obj is TTyRichFieldMark then
      if TTyRichFieldMark(d.FRuns[i].Obj).Kind = rfmOpen then Inc(depth)
      else
      begin
        Dec(depth);
        if depth < ALow then ALow := depth;
      end;
end;

procedure TTyRichDocument.ParaFieldDepths(AIndex: Integer; out AStart, ALow: Integer);
begin
  ParaDepths(AIndex, AStart, ALow);
end;

function TTyRichDocument.DepthAt(APos: TTyRichPos): Integer;
var
  k, i: Integer;
  d: TTyRichParaData;
  o: Int64;
begin
  k := FText.ParaOfPos(APos);
  d := DataOf(k);
  Result := DepthOfData(d);
  if d = nil then Exit;
  o := APos - FText.ParaStart(k);
  for i := 0 to High(d.FRuns) do
  begin
    if d.FRuns[i].Start >= o then Break;
    if d.FRuns[i].Obj is TTyRichFieldMark then
      if TTyRichFieldMark(d.FRuns[i].Obj).Kind = rfmOpen then Inc(Result) else Dec(Result);
  end;
end;

{ A new value for the paragraph AFrom was the value of (the same paragraph after an edit in
  it: typing, a format, the first part of a split): it keeps the file's marker text, and its
  start, as deep in fields as AFrom's. }
function TTyRichDocument.MakeDataLike(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
  ACell: TTyRichCell; AFrom: TTyRichParaData): TTyRichParaData;
var
  i, j: Integer;
  same: Boolean;
begin
  if (AFrom <> nil) and (AFrom.FListText <> '') then
  begin
    Result := NewData(AParaFormat, ARuns, ACell, AFrom.FFieldDepth);
    Result.FListText := AFrom.FListText;
  end
  else
    Result := MakeData(AParaFormat, ARuns, ACell, DepthOfData(AFrom));
  { The very same objects in the same order as the value it was made from (typing, a format
    change): the same key - one pass, beside NewData's own over the runs. }
  // (nil: the plain value of a document without a loader - no objects)
  if (AFrom = nil) or (Result = nil) or (Result.FObjKey = 0) or (AFrom.FObjKey = 0) then Exit;
  j := 0;
  same := True;
  for i := 0 to High(Result.FRuns) do
    if Result.FRuns[i].Obj <> nil then
    begin
      while (j <= High(AFrom.FRuns)) and (AFrom.FRuns[j].Obj = nil) do Inc(j);
      if (j > High(AFrom.FRuns)) or (AFrom.FRuns[j].Obj <> Result.FRuns[i].Obj) then
      begin
        same := False;
        Break;
      end;
      Inc(j);
    end;
  if same then
  begin
    while (j <= High(AFrom.FRuns)) and (AFrom.FRuns[j].Obj = nil) do Inc(j);
    if j > High(AFrom.FRuns) then Result.FObjKey := AFrom.FObjKey;
  end;
end;

procedure TTyRichDocument.PutData(AIndex: Integer; AOld, ANew: TTyRichParaData);
begin
  if AOld = ANew then Exit;
  AcquireData(ANew);
  FText.ParaData[AIndex] := ANew;
  ReleaseData(AOld);
end;

function TTyRichDocument.SlotData(AIndex: Integer): TTyRichParaData;
begin
  Result := TTyRichParaData(FText.ParaData[AIndex]);
end;

function TTyRichDocument.DataOf(AIndex: Integer): TTyRichParaData;
begin
  Result := SlotData(AIndex);
  if (FLoader = nil) or FInLoad then Exit;
  if Result <> nil then
  begin
    // parsed already: the loader hears that it is in use
    FLoader.ParagraphRead(Self, AIndex);
    Exit;
  end;
  FInLoad := True;
  try
    FLoader.LoadParagraph(Self, AIndex);
  finally
    FInLoad := False;
  end;
  Result := SlotData(AIndex);
  if Result = nil then
  begin
    Result := FPlainParsed;
    PutData(AIndex, nil, Result);
  end;
end;

function TTyRichDocument.RunsOfData(D: TTyRichParaData): TTyRunArray;
begin
  if (D = nil) or (D.FRuns = nil) then Result := FDefaultRuns else Result := D.FRuns;
end;

function TTyRichDocument.FormatOfData(D: TTyRichParaData): TTyParaFormatId;
begin
  if D = nil then Result := FDefaultParaId else Result := D.FParaFormat;
end;

function TTyRichDocument.CellOfData(D: TTyRichParaData): TTyRichCell;
begin
  if D = nil then Result := nil else Result := D.FCell;
end;

function TTyRichDocument.NoDataMap(AIndex: Integer; AData: Pointer): Pointer;
begin
  Result := nil;
end;

procedure TTyRichDocument.TextDataDropped(Sender: TObject; AData: Pointer);
begin
  // the slot's reference goes; an undo record that still needs the value holds its own
  ReleaseData(TTyRichParaData(AData));
end;

procedure TTyRichDocument.TextParasChanged(Sender: TObject; AFirst, AOldCount,
  ANewCount: Integer);
begin
  if FEditing > 0 then Exit;
  // an edit made straight on Text: no undo, no notification; keep the runs inside the text
  LeftHistory;
  ClipRuns(AFirst);
end;

procedure TTyRichDocument.ClipRuns(AIndex: Integer);
var
  d: TTyRichParaData;
  len: Int64;
  runs: TTyRunArray;
  n: Integer;
begin
  d := SlotData(AIndex);
  if (d = nil) or (d.FRuns = nil) then Exit;
  len := FText.ParaLength(AIndex);
  runs := nil;
  n := 0;
  if len = 0 then
    AppendRun(runs, n, 0, d.FRuns[0].Format, nil)
  else
  begin
    AppendSlice(runs, n, d.FRuns, len, 0, len, 0);
    // an object whose character went is dropped
    if (n > 0) and (runs[n - 1].Obj <> nil) and (runs[n - 1].Start + 1 > len) then
      runs[n - 1].Obj := nil;
    if n = 0 then AppendRun(runs, n, 0, d.FRuns[0].Format, nil);
  end;
  SetLength(runs, n);
  if SameRuns(runs, d.FRuns) then Exit;
  PutData(AIndex, d, MakeDataLike(d.FParaFormat, runs, d.FCell, d));
end;

{ ---- readers ---- }

procedure TTyRichDocument.EnsureParsed(AIndex: Integer);
begin
  DataOf(AIndex);
end;

procedure TTyRichDocument.BeginRead;
begin
  Inc(FReading);
end;

procedure TTyRichDocument.EndRead;
begin
  if FReading <= 0 then
    raise ETyRichModel.Create('EndRead without BeginRead');
  Dec(FReading);
  if (FReading = 0) and (FLoader <> nil) and not FInLoad then FLoader.ReadsEnded(Self);
end;

procedure TTyRichDocument.BeginSave;
begin
  Inc(FSaving);
end;

procedure TTyRichDocument.EndSave;
begin
  if FSaving <= 0 then
    raise ETyRichModel.Create('EndSave without BeginSave');
  Dec(FSaving);
end;

function TTyRichDocument.GetSaving: Boolean;
begin
  Result := FSaving > 0;
end;

function TTyRichDocument.ParaFormatOf(AIndex: Integer): TTyParaFormatId;
begin
  Result := FormatOfData(DataOf(AIndex));
end;

function TTyRichDocument.RunsOf(AIndex: Integer): TTyRunArray;
begin
  Result := Copy(RunsOfData(DataOf(AIndex)));
end;

function TTyRichDocument.TypingFormatAt(APos: TTyRichPos): TTyCharFormatId;
var
  k: Integer;
begin
  k := FText.ParaOfPos(APos);
  Result := InheritedFormat(RunsOfData(DataOf(k)), APos - FText.ParaStart(k));
end;

function TTyRichDocument.CellAt(AIndex: Integer): TTyRichCell;
begin
  Result := CellOfData(DataOf(AIndex));
end;

{ The run of the object character at offset AOffset of a paragraph's runs; -1: none. }
function ObjectRunAt(const ARuns: TTyRunArray; AOffset: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(ARuns) do
  begin
    if ARuns[i].Start > AOffset then Break;
    if (ARuns[i].Start = AOffset) and (ARuns[i].Obj <> nil) then Exit(i);
  end;
  Result := -1;
end;

function TTyRichDocument.ObjectAt(APos: TTyRichPos): TTyRichObject;
var
  k, i: Integer;
  runs: TTyRunArray;
begin
  Result := nil;
  if (APos < 0) or (APos >= FText.Length) then Exit;
  k := FText.ParaOfPos(APos);
  runs := RunsOfData(DataOf(k));
  i := ObjectRunAt(runs, APos - FText.ParaStart(k));
  if i >= 0 then Result := runs[i].Obj;
end;

function TTyRichDocument.ReadValue(AData: Pointer; out AFormat: TTyParaFormatId;
  out ARuns: TTyRunArray; out ACell: TTyRichCell): Boolean;
var
  d: TTyRichParaData;
begin
  d := TTyRichParaData(AData);
  Result := (d <> nil) or (FLoader = nil);
  AFormat := FormatOfData(d);
  ARuns := RunsOfData(d);
  ACell := CellOfData(d);
end;

function TTyRichDocument.ListTextOf(AIndex: Integer): UTF8String;
begin
  Result := ValueListText(DataOf(AIndex));
end;

function TTyRichDocument.ValueListText(AData: Pointer): UTF8String;
begin
  if AData = nil then Exit('');
  Result := TTyRichParaData(AData).FListText;
end;

{ ---- rows that hold a nested table ---- }

function NestedRowRefused: ETyRichRefused;
begin
  Result := ETyRichRefused.Create(rsRichModelNestedRow);
  Result.FixedRow := True;
end;

function TTyRichDocument.FixedData(D: TTyRichParaData): Boolean;
begin
  Result := (D <> nil) and (D.FCell <> nil) and D.FCell.FRow.FHoldsNestedTable;
end;

function TTyRichDocument.RowAt(AIndex: Integer): TTyRichRow;
var
  c: TTyRichCell;
begin
  c := CellOfData(DataOf(AIndex));
  if c = nil then Result := nil else Result := c.FRow;
end;

function TTyRichDocument.FixedRowAt(AIndex: Integer): TTyRichRow;
begin
  Result := RowAt(AIndex);
  if (Result <> nil) and not Result.FHoldsNestedTable then Result := nil;
end;

{ What a delete leaves of the paragraphs k .. m its range lies in: one paragraph, made of
  k's head and m's tail. A paragraph is changed when it loses characters or is joined with
  another; the ones between, and k when the range starts at its start, go whole. Only k and
  m are read (the delete reads them anyway), and a neighbour of one that is in such a row:
  paragraphs that go whole are not parsed for this. }
function TTyRichDocument.ChangeRefused(APos, ALen: TTyRichPos): Boolean;
begin
  Result := ChangeRefusal(APos, ALen) <> rcrNone;
end;

function TTyRichDocument.ChangeRefusal(APos, ALen: TTyRichPos): TTyRichChangeRefusal;
begin
  Result := rcrNone;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then Exit;
  if RowRefused(APos, ALen) then Result := rcrFixedRow
  else if FieldRefused(APos, ALen) then Result := rcrField;
end;

procedure TTyRichDocument.RaiseRefused(APos, ALen: TTyRichPos);
var
  e: ETyRichRefused;
begin
  case ChangeRefusal(APos, ALen) of
    rcrFixedRow: raise NestedRowRefused;
    rcrField:
      begin
        e := ETyRichRefused.Create(rsRichEditRefusedField);
        e.Field := True;
        raise e;
      end;
  end;
end;

{ The field rule of ChangeRefusal: an insert at a place inside a result, a delete with an end
  at one. Both ends outside every field: the marks between them are whole pairs (a close mark
  with its open mark before the range would leave the depth below the start's, which is 0). }
function TTyRichDocument.FieldRefused(APos, ALen: TTyRichPos): Boolean;
begin
  // (a command's pair of marks: it asked the rule before it began)
  if FMarkEdit > 0 then Exit(False);
  BeginRead;
  try
    Result := (DepthAt(APos) > 0) or ((ALen > 0) and (DepthAt(APos + ALen) > 0));
  finally
    EndRead;
  end;
end;

function TTyRichDocument.RowRefused(APos, ALen: TTyRichPos): Boolean;
var
  k, m: Integer;
  e: TTyRichPos;
  headOfK, headOfM: Boolean;
  rk, rm: TTyRichRow;
begin
  Result := False;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then Exit;
  BeginRead;
  try
    k := FText.ParaOfPos(APos);
    if ALen = 0 then Exit(FixedRowAt(k) <> nil);
    e := APos + ALen;
    m := FText.ParaOfPos(e);
    if m = k then Exit(FixedRowAt(k) <> nil);
    headOfK := APos > FText.ParaStart(k);      // k keeps a head: it is joined with m's tail
    headOfM := e > FText.ParaStart(m);         // m loses a head
    rk := FixedRowAt(k);
    rm := FixedRowAt(m);
    if headOfK and (rk <> nil) then Exit(True);
    if (headOfK or headOfM) and (rm <> nil) then Exit(True);
    // a row among the paragraphs that go whole must go whole too. A row is a run of
    // paragraphs, so it is cut only where a paragraph of it stays just outside them: the
    // one before k (when k goes), or m (when the one before m goes with it)
    if not headOfK and (rk <> nil) and (k > 0) and (RowAt(k - 1) = rk) then Exit(True);
    if (rm <> nil) and (RowAt(m - 1) = rm) then Exit(True);
  finally
    EndRead;
  end;
end;

function TTyRichDocument.CanChange(APos, ALen: TTyRichPos): Boolean;
begin
  Result := not ChangeRefused(APos, ALen);
end;

function TTyRichDocument.FieldDepthAt(APos: TTyRichPos): Integer;
begin
  if (APos < 0) or (APos > FText.Length) then Exit(0);
  BeginRead;
  try
    Result := DepthAt(APos);
  finally
    EndRead;
  end;
end;

function TTyRichDocument.ParaFieldDepth(AIndex: Integer): Integer;
begin
  Result := DepthOfData(DataOf(AIndex));
end;

{ From position APos, APos's depth ADepth (> 0): the open mark of the innermost field there -
  the last open mark before APos that brings the depth to ADepth with no fall below it after
  it. In APos's paragraph up to APos; else in the last paragraph before it where the depth
  falls below ADepth (ParaDepths, without reading the ones between): the last such open mark
  in it. }
function FindOpenBefore(ADoc: TTyRichDocument; APos: TTyRichPos; ADepth: Integer): TTyRichPos;
var
  k, depth, s, low: Integer;
  d: TTyRichParaData;
  o, ps: Int64;
  found: TTyRichPos;

  procedure Walk(AUpTo: Int64);
  var
    i: Integer;
  begin
    found := -1;
    if d <> nil then
      for i := 0 to High(d.FRuns) do
      begin
        if d.FRuns[i].Start >= AUpTo then Break;
        if d.FRuns[i].Obj is TTyRichFieldMark then
          if TTyRichFieldMark(d.FRuns[i].Obj).Kind = rfmOpen then
          begin
            Inc(depth);
            if depth = ADepth then found := ps + d.FRuns[i].Start;
          end
          else
          begin
            Dec(depth);
            if depth < ADepth then found := -1;
          end;
      end;
  end;

begin
  Result := -1;
  k := ADoc.FText.ParaOfPos(APos);
  ps := ADoc.FText.ParaStart(k);
  o := APos - ps;
  d := ADoc.DataOf(k);
  depth := ADoc.DepthOfData(d);
  Walk(o);
  if found >= 0 then Exit(found);
  // (a paragraph that starts outside the field cannot follow its open mark)
  if ADoc.DepthOfData(d) < ADepth then Exit;
  Dec(k);
  while k >= 0 do
  begin
    ADoc.ParaDepths(k, s, low);
    if low < ADepth then
    begin
      d := ADoc.DataOf(k);
      ps := ADoc.FText.ParaStart(k);
      depth := ADoc.DepthOfData(d);
      Walk(High(Int64));
      Exit(found);
    end;
    Dec(k);
  end;
end;

{ From position APos (inside ADepth fields): the close mark that brings the depth below
  ADepth - in APos's paragraph after APos, else in the first paragraph after it where the
  depth falls below ADepth (ParaDepths, without reading the ones between). }
function FindCloseAfter(ADoc: TTyRichDocument; APos: TTyRichPos; ADepth: Integer): TTyRichPos;
var
  k, i, depth, last, s, low: Integer;
  d: TTyRichParaData;
  ps, o: Int64;
begin
  Result := -1;
  k := ADoc.FText.ParaOfPos(APos);
  last := ADoc.FText.ParaCount - 1;
  depth := ADepth;
  o := APos - ADoc.FText.ParaStart(k);
  while k <= last do
  begin
    if o = 0 then
    begin
      // (a paragraph walked whole: only the one where the depth falls is read)
      ADoc.ParaDepths(k, s, low);
      if low >= ADepth then
      begin
        Inc(k);
        Continue;
      end;
      depth := s;
    end;
    d := ADoc.DataOf(k);
    ps := ADoc.FText.ParaStart(k);
    if o = 0 then depth := ADoc.DepthOfData(d);
    if d <> nil then
      for i := 0 to High(d.FRuns) do
      begin
        if d.FRuns[i].Start < o then Continue;
        if d.FRuns[i].Obj is TTyRichFieldMark then
          if TTyRichFieldMark(d.FRuns[i].Obj).Kind = rfmOpen then
            Inc(depth)
          else
          begin
            Dec(depth);
            if depth < ADepth then Exit(ps + d.FRuns[i].Start);
          end;
      end;
    // (the place's own paragraph ends as deep: the paragraphs after it)
    if o = 0 then Exit;
    Inc(k);
    o := 0;
  end;
end;

function TTyRichDocument.FieldRangeAt(APos: TTyRichPos; out AOpen, AClose: TTyRichPos): Boolean;
var
  depth: Integer;
begin
  AOpen := -1;
  AClose := -1;
  Result := False;
  if (APos < 0) or (APos > FText.Length) then Exit;
  BeginRead;
  try
    depth := DepthAt(APos);
    if depth <= 0 then Exit;
    AOpen := FindOpenBefore(Self, APos, depth);
    AClose := FindCloseAfter(Self, APos, depth);
    Result := (AOpen >= 0) and (AClose >= 0);
    if not Result then
    begin
      AOpen := -1;
      AClose := -1;
    end;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.FieldPartner(AMarkPos: TTyRichPos): TTyRichPos;
var
  o: TTyRichObject;
  depth: Integer;
begin
  Result := -1;
  if (AMarkPos < 0) or (AMarkPos >= FText.Length) then Exit;
  BeginRead;
  try
    o := ObjectAt(AMarkPos);
    if not (o is TTyRichFieldMark) then Exit;
    if TTyRichFieldMark(o).Kind = rfmOpen then
    begin
      // inside it right after the mark
      depth := DepthAt(AMarkPos + 1);
      Result := FindCloseAfter(Self, AMarkPos + 1, depth);
    end
    else
    begin
      depth := DepthAt(AMarkPos);
      Result := FindOpenBefore(Self, AMarkPos, depth);
    end;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.FieldOnly(APos, ALen: TTyRichPos): Boolean;
var
  k, m, i, depth: Integer;
  d: TTyRichParaData;
  r: TTyRunArray;
  ps, lo, hi, s, e, len: Int64;
begin
  Result := False;
  if (ALen <= 0) or (APos < 0) or (APos + ALen > FText.Length) then Exit;
  BeginRead;
  try
    k := FText.ParaOfPos(APos);
    m := FText.ParaOfPos(APos + ALen - 1);
    while k <= m do
    begin
      d := DataOf(k);
      ps := FText.ParaStart(k);
      len := FText.ParaLength(k);
      lo := APos - ps;
      if lo < 0 then lo := 0;
      hi := APos + ALen - ps;
      // (a plain paragraph is no field's: one of a result has a value of its own)
      if d = nil then Exit;
      depth := DepthOfData(d);
      // (the plain value's runs are the document's default ones)
      r := RunsOfData(d);
      for i := 0 to High(r) do
      begin
        s := r[i].Start;
        e := RunEnd(r, i, len);
        if (e > lo) and (s < hi) and not (r[i].Obj is TTyRichFieldMark) and (depth = 0) then
          Exit;
        if r[i].Obj is TTyRichFieldMark then
          if TTyRichFieldMark(r[i].Obj).Kind = rfmOpen then Inc(depth) else Dec(depth);
      end;
      // its paragraph mark, taken by the range: a result's when the paragraph ends in one
      if (hi > len) and (depth = 0) then Exit;
      Inc(k);
    end;
    Result := True;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.ParaEndsInField(AIndex: Integer): Boolean;
begin
  Result := EndDepthOfData(DataOf(AIndex)) > 0;
end;

function TTyRichDocument.WholeRows(AFrom, ATo: TTyRichPos): Boolean;
var
  k, m: Integer;
  ck, cl, cn: TTyRichCell;
begin
  Result := False;
  k := FText.ParaOfPos(AFrom);
  ck := CellAt(k);
  if (ck = nil) or (AFrom <> FText.ParaStart(k)) then Exit;
  // from a row's first paragraph
  if (k > 0) and (CellAt(k - 1) <> nil) and (CellAt(k - 1).Row = ck.Row) then Exit;
  { To the start of the paragraph after a row of the same table. Not to the text's end: a
    range that ends there ends inside a table that ends the text (only code makes one: a
    file read from RTF ends after its last row), whose last paragraph has no separator to
    go with it - the engine would leave it in its cell and the row's other cells with no
    paragraph. Refused: the row goes with a table edit (EditTable's rtkDeleteRow). }
  if ATo >= FText.Length then Exit;
  m := FText.ParaOfPos(ATo);
  if (m = 0) or (ATo <> FText.ParaStart(m)) then Exit;
  cl := CellAt(m - 1);
  if (cl = nil) or (cl.Row.Table <> ck.Row.Table) then Exit;
  if m < FText.ParaCount then
  begin
    cn := CellAt(m);
    if (cn <> nil) and (cn.Row = cl.Row) then Exit;
  end;
  Result := True;
end;

function TTyRichDocument.AtParaStart(APos: TTyRichPos): Boolean;
var
  p, p0: TTyRichPos;
  o: TTyRichObject;
begin
  if (APos < 0) or (APos > FText.Length) then Exit(False);
  p0 := FText.ParaStart(FText.ParaOfPos(APos));
  BeginRead;
  try
    for p := p0 to APos - 1 do
    begin
      o := ObjectAt(p);
      if not ((o is TTyRichBookmarkMark) or (o is TTyRichFieldMark)) then Exit(False);
    end;
  finally
    EndRead;
  end;
  Result := True;
end;

function TTyRichDocument.UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
var
  k, m: Integer;
  ck, cm, cp: TTyRichCell;
begin
  Result := True;
  if ALen <= 0 then Exit;
  // (the cells are compared inside one read: a document that parses on demand keeps them)
  BeginRead;
  try
    k := FText.ParaOfPos(AStart);
    // the paragraph the deletion joins with: the one its end lies in (after a separator, the next)
    m := FText.ParaOfPos(AStart + ALen);
    if m = k then Exit;
    ck := CellAt(k);
    cm := CellAt(m);
    { A range that begins outside a table and ends exactly where its first row starts keeps
      its last separator: the text goes, the paragraph before the table stays (Word's way) -
      the engine would merge it into the first cell. }
    if (cm <> nil) and (AStart + ALen = FText.ParaStart(m)) and
      ((ck = nil) or (ck.Row.Table <> cm.Row.Table)) then
    begin
      cp := CellAt(m - 1);
      if (cp = nil) or (cp.Row.Table <> cm.Row.Table) then
      begin
        Dec(ALen);
        m := FText.ParaOfPos(AStart + ALen);
        if m = k then Exit;
        cm := CellAt(m);
      end;
    end;
    { One that crosses a cell's or a row's edge is refused: the engine would merge paragraphs
      of two cells and leave a cell with no paragraph, no place for the caret. Whole rows,
      from a row's start to a row's end, the engine deletes cleanly. }
    { Whole rows from after the zero-width marks at a row's start (a place set at a
      bookmark's start rests after its opening mark): from the row's start - the marks go
      with the row. }
    if (ck <> cm) and (AStart > FText.ParaStart(k)) and AtParaStart(AStart) and
       WholeRows(FText.ParaStart(k), AStart + ALen) then
    begin
      Inc(ALen, AStart - FText.ParaStart(k));
      AStart := FText.ParaStart(k);
    end;
    if (ck <> cm) and not WholeRows(AStart, AStart + ALen) then Result := False;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.TableAt(AIndex: Integer): TTyRichTable;
var
  c: TTyRichCell;
begin
  c := CellAt(AIndex);
  if c = nil then Result := nil else Result := c.Table;
end;

function TTyRichDocument.TableParas(AIndex: Integer; out AFirst, ALast: Integer): Boolean;
var
  t: TTyRichTable;
  last: Integer;
begin
  AFirst := -1;
  ALast := -1;
  // t is held across the reads of its neighbours
  BeginRead;
  try
    t := TableAt(AIndex);
    if t = nil then Exit(False);
    AFirst := AIndex;
    while (AFirst > 0) and (TableAt(AFirst - 1) = t) do Dec(AFirst);
    ALast := AIndex;
    last := FText.ParaCount - 1;
    while (ALast < last) and (TableAt(ALast + 1) = t) do Inc(ALast);
    Result := True;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.CellParas(AIndex: Integer; ACell: TTyRichCell;
  out AFirst, ALast: Integer): Boolean;
var
  t: TTyRichTable;
  c: TTyRichCell;
  i, last: Integer;

  function Before(A, B: TTyRichCell): Boolean;
  begin
    Result := (A.Row.Index < B.Row.Index) or
      ((A.Row.Index = B.Row.Index) and (A.Index < B.Index));
  end;

begin
  AFirst := -1;
  ALast := -1;
  // (ACell is the caller's: it reads it and calls this inside one read scope)
  BeginRead;
  try
    t := TableAt(AIndex);
    if (t = nil) or (ACell = nil) or (ACell.Table <> t) then Exit(False);
    last := FText.ParaCount - 1;
    i := AIndex;
    c := CellAt(i);
    // walk towards the cell: cells lie in row order
    while c <> ACell do
    begin
      if Before(c, ACell) then Inc(i) else Dec(i);
      if (i < 0) or (i > last) then Exit(False);
      c := CellAt(i);
      if (c = nil) or (c.Table <> t) then Exit(False);
    end;
    AFirst := i;
    while (AFirst > 0) and (CellAt(AFirst - 1) = ACell) do Dec(AFirst);
    ALast := i;
    while (ALast < last) and (CellAt(ALast + 1) = ACell) do Inc(ALast);
    Result := True;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.ParaDataOf(AIndex: Integer): Pointer;
begin
  Result := DataOf(AIndex);
end;

function TTyRichDocument.IsLiveParaData(AData: Pointer): Boolean;
var
  d: TTyRichParaData;
begin
  d := FFirstData;
  while d <> nil do
  begin
    if Pointer(d) = AData then Exit(True);
    d := d.FNext;
  end;
  Result := False;
end;

{ ---- primitives ---- }

procedure TTyRichDocument.CheckCharId(AId: TTyCharFormatId);
begin
  if (AId < 0) or (AId >= FFormats.CharCount) then
    raise ETyRichModel.CreateFmt('Character format id %d out of range', [AId]);
end;

procedure TTyRichDocument.CheckParaId(AId: TTyParaFormatId);
begin
  if (AId < 0) or (AId >= FFormats.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraph format id %d out of range', [AId]);
end;

function TTyRichDocument.NewUndo(const AChange: TTyRichChange): TTyRichUndoData;
begin
  Result := TTyRichUndoData.Create;
  Result.FDoc := Self;
  Result.FChange := AChange;
end;

{ A then B, as one change: the span of both, in the coordinates before A (old) and after B
  (new). Outside the span the two documents differ only by the shift A and B made. }
procedure ComposeChange(var A: TTyRichChange; var AHas: Boolean; const B: TTyRichChange);
var
  s, e: TTyRichPos;
  ps, pe: Integer;
begin
  if not AHas then
  begin
    A := B;
    AHas := True;
    Exit;
  end;
  s := A.Pos;
  if B.Pos < s then s := B.Pos;
  e := A.Pos + A.NewLen;
  if B.Pos + B.OldLen > e then e := B.Pos + B.OldLen;
  A.OldLen := (e - s) - (A.NewLen - A.OldLen);
  A.NewLen := (e - s) + (B.NewLen - B.OldLen);
  A.Pos := s;
  ps := A.FirstPara;
  if B.FirstPara < ps then ps := B.FirstPara;
  pe := A.FirstPara + A.NewParaCount;
  if B.FirstPara + B.OldParaCount > pe then pe := B.FirstPara + B.OldParaCount;
  A.OldParaCount := (pe - ps) - (A.NewParaCount - A.OldParaCount);
  A.NewParaCount := (pe - ps) + (B.NewParaCount - B.OldParaCount);
  A.FirstPara := ps;
  A.Kinds := A.Kinds + B.Kinds;
end;

procedure TTyRichDocument.Notify(const AChange: TTyRichChange);
begin
  // inside a command the history numbers the content (Execute, Undo, Redo)
  if FRunning = nil then LeftHistory;
  // inside a command the observers hear one change at the end (Flush; in an update block,
  // at the outermost EndUpdate)
  if FHold > 0 then
  begin
    ComposeChange(FPending, FHasPending, AChange);
    Exit;
  end;
  if Assigned(FOnChange) then FOnChange(Self, AChange);
end;

{ ---- format walks (one MapParaData pass, see ApplyCharFormat) ---- }

type
  TTyRichCharWalk = class
  public
    Doc: TTyRichDocument;
    Undo: TTyRichUndoData;
    K, Last: Integer;
    APos, B: Int64;
    PsK, LenK, PsLast, LenLast: Int64;
    Mask: TTyCharFormatMask;
    Value: TTyCharFormat;
    // of FontName and SizeHalfPt: a run with none of its own keeps none
    KeepNone: TTyCharFormatMask;
    FromIds, ToIds: array of TTyCharFormatId;
    PrevD, PrevNew: TTyRichParaData;
    Changed: Boolean;     // a value changed (a write of what is there is no step)
    function MapId(AId: TTyCharFormatId): TTyCharFormatId;
    { ARun's format mapped, unless it is a field's (a mark, or a run of a result: ADepth
      fields open before it); ADepth goes on past it. AMap False: only counted. }
    function MapFree(const ARun: TTyRichRun; var ADepth: Integer;
      AMap: Boolean = True): TTyCharFormatId;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

  TTyRichParaWalk = class
  public
    Doc: TTyRichDocument;
    Undo: TTyRichUndoData;
    First: Integer;
    Mask: TTyParaFormatMask;
    Value: TTyParaFormat;
    FromIds, ToIds: array of TTyParaFormatId;
    PrevD, PrevNew: TTyRichParaData;
    Changed: Boolean;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

  TTyRichRevertWalk = class
  public
    Doc: TTyRichDocument;
    Undo: TTyRichUndoData;
    Run: Integer;
    Left: Integer;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

function TTyRichCharWalk.MapId(AId: TTyCharFormatId): TTyCharFormatId;
var
  x: Integer;
  f: TTyCharFormat;
  m: TTyCharFormatMask;
begin
  for x := 0 to High(FromIds) do
    if FromIds[x] = AId then Exit(ToIds[x]);
  f := Doc.FFormats.CharFormat(AId);
  m := Mask;
  if (cffFontName in KeepNone) and (f.FontName = '') then Exclude(m, cffFontName);
  if (cffSize in KeepNone) and (f.SizeHalfPt <= 0) then Exclude(m, cffSize);
  Result := Doc.FFormats.InternChar(TyMergeCharFormat(f, m, Value));
  SetLength(FromIds, Length(FromIds) + 1);
  SetLength(ToIds, Length(ToIds) + 1);
  FromIds[High(FromIds)] := AId;
  ToIds[High(ToIds)] := Result;
end;

function TTyRichCharWalk.MapFree(const ARun: TTyRichRun; var ADepth: Integer;
  AMap: Boolean): TTyCharFormatId;
begin
  Result := ARun.Format;
  if ARun.Obj is TTyRichFieldMark then
  begin
    if TTyRichFieldMark(ARun.Obj).Kind = rfmOpen then Inc(ADepth) else Dec(ADepth);
    Exit;
  end;
  if AMap and (ADepth = 0) then Result := MapId(ARun.Format);
end;

function TTyRichCharWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  d, nd: TTyRichParaData;
  r, runs: TTyRunArray;
  whole: Boolean;
  j, n, depth: Integer;
  ps, len, lo, hi, s, e: Int64;
begin
  d := TTyRichParaData(AData);
  // not parsed yet: parse it (the slot then holds d)
  if (d = nil) and (Doc.FLoader <> nil) then d := Doc.DataOf(AIndex);
  Undo.AddOld(d);
  Result := d;
  // a row that holds a nested table stays as the file has it
  if Doc.FixedData(d) then Exit;
  r := Doc.RunsOfData(d);
  whole := (AIndex > K) and (AIndex < Last);
  runs := nil;
  n := 0;
  { A field's marks and the characters of its result keep their look (a result is read-only):
    a run is one or the other as a whole, for a mark is a run of its own. }
  depth := Doc.DepthOfData(d);
  if whole then
  begin
    // a paragraph inside the range: every run, no lengths needed; equal values (plain
    // paragraphs) map to one shared result
    if (AIndex > K + 1) and (d = PrevD) then
      nd := PrevNew
    else
    begin
      for j := 0 to High(r) do
        AppendRun(runs, n, r[j].Start, MapFree(r[j], depth), r[j].Obj);
      SetLength(runs, n);
      if SameRuns(runs, r) then nd := d
      else nd := Doc.MakeDataLike(Doc.FormatOfData(d), runs, Doc.CellOfData(d), d);
      PrevD := d;
      PrevNew := nd;
    end;
  end
  else
  begin
    if AIndex = K then
    begin
      ps := PsK;
      len := LenK;
    end
    else
    begin
      ps := PsLast;
      len := LenLast;
    end;
    lo := APos - ps;
    if lo < 0 then lo := 0;
    hi := B - ps;
    if hi > len then hi := len;
    if len = 0 then
    begin
      // (an empty paragraph of a result keeps its look)
      if (APos <= ps) and (ps < B) and (depth = 0) then
        AppendRun(runs, n, 0, MapId(r[0].Format), nil)
      else
        Exit;
    end
    else if lo >= hi then
      Exit
    else
      for j := 0 to High(r) do
      begin
        s := r[j].Start;
        e := RunEnd(r, j, len);
        if (s < lo) then AppendRun(runs, n, s, r[j].Format, r[j].Obj);
        if (e > lo) and (s < hi) then
        begin
          if s < lo then s := lo;
          AppendRun(runs, n, s, MapFree(r[j], depth), r[j].Obj);
        end
        else
          // (its marks still count)
          MapFree(r[j], depth, False);
        if e > hi then
        begin
          if s < hi then s := hi;
          AppendRun(runs, n, s, r[j].Format, r[j].Obj);
        end;
      end;
    SetLength(runs, n);
    if SameRuns(runs, r) then nd := d
    else nd := Doc.MakeDataLike(Doc.FormatOfData(d), runs, Doc.CellOfData(d), d);
  end;
  if nd <> d then
  begin
    // the slot's reference moves to the new value; the record keeps d alive
    Doc.AcquireData(nd);
    Doc.ReleaseData(d);
    Changed := True;
  end;
  Result := nd;
end;

function TTyRichParaWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  d, nd: TTyRichParaData;
  oldFmt, newFmt: TTyParaFormatId;
  x: Integer;
begin
  d := TTyRichParaData(AData);
  if (d = nil) and (Doc.FLoader <> nil) then d := Doc.DataOf(AIndex);
  Undo.AddOld(d);
  // a row that holds a nested table stays as the file has it; so does a paragraph whose
  // paragraph mark is a field's result's (it is read-only)
  if Doc.FixedData(d) or (Doc.EndDepthOfData(d) > 0) then Exit(d);
  if (AIndex > First) and (d = PrevD) then
    nd := PrevNew
  else
  begin
    oldFmt := Doc.FormatOfData(d);
    newFmt := -1;
    for x := 0 to High(FromIds) do
      if FromIds[x] = oldFmt then newFmt := ToIds[x];
    if newFmt < 0 then
    begin
      newFmt := Doc.FFormats.InternPara(TyMergeParaFormat(Doc.FFormats.ParaFormat(oldFmt), Mask,
        Value));
      SetLength(FromIds, Length(FromIds) + 1);
      SetLength(ToIds, Length(ToIds) + 1);
      FromIds[High(FromIds)] := oldFmt;
      ToIds[High(ToIds)] := newFmt;
    end;
    // the runs are immutable, so the new value shares them
    if newFmt = oldFmt then nd := d
    else nd := Doc.MakeDataLike(newFmt, Doc.RunsOfData(d), Doc.CellOfData(d), d);
    PrevD := d;
    PrevNew := nd;
  end;
  if nd <> d then
  begin
    Doc.AcquireData(nd);
    Doc.ReleaseData(d);
    Changed := True;
  end;
  Result := nd;
end;

function TTyRichRevertWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  old: TTyRichParaData;
begin
  old := Undo.FOldData[Run].Data;
  Dec(Left);
  if (Left = 0) and (Run + 1 < Undo.FOldCount) then
  begin
    Inc(Run);
    Left := Undo.FOldData[Run].Count;
  end;
  if Pointer(old) <> AData then
  begin
    Doc.AcquireData(old);
    Doc.ReleaseData(TTyRichParaData(AData));
  end;
  Result := old;
end;

{ AText starts with a byte that continues a UTF-8 sequence (80..BF), or ends inside one: a lead
  byte (C2..F4, or F8..FB, the first of a text file's escaped byte) that its last bytes do not
  complete. The storage counts characters piece by piece and keeps an insert in pieces of its
  own, while the copy and the layout read a paragraph's bytes as one stretch: such ends would
  join with the bytes next to them there and be counted as other characters than the storage
  counts. }
function CutSequence(const AText: UTF8String): Boolean;
var
  n, i, need: Integer;
begin
  n := Length(AText);
  if n = 0 then Exit(False);
  if Byte(AText[1]) and $C0 = $80 then Exit(True);
  i := n;
  while (i > 1) and (n - i < 3) and (Byte(AText[i]) and $C0 = $80) do Dec(i);
  case Byte(AText[i]) of
    $C2..$DF, $F8..$FB: need := 2;
    $E0..$EF: need := 3;
    $F0..$F4: need := 4;
  else
    Exit(False);
  end;
  Result := n - i + 1 < need;
end;

function TTyRichDocument.InsertCore(APos: TTyRichPos; const AText: UTF8String;
  AFormat: TTyCharFormatId; AObj: TTyRichObject): TTyRichUndoData;
var
  c: TTyRichChange;
  k, s, i, n1, n2: Integer;
  d, mid: TTyRichParaData;
  r, runs1, runs2, one: TTyRunArray;
  ps, o, len, len1, lenLast, added, oldChars: Int64;
  f: TTyCharFormatId;
  fmt, fmtNext: TTyParaFormatId;
  pfv: TTyParaFormat;
  cell: TTyRichCell;
  oldCount: Integer;
  txt: UTF8String;
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  FText.ParaOfPos(APos);   // range check before anything changes
  if AText = '' then Exit(NewUndo(c));
  if CutSequence(AText) then
    raise ETyRichModel.Create('The text to insert starts or ends inside a UTF-8 sequence');
  RaiseRefused(APos, 0);
  // new breaks take the document's majority kind, so saving writes the stored bytes as they
  // are: the breaks already there stay what they were in the file
  txt := WithBreaks(AText, FDominantLineBreak);
  if AFormat <> TyRichInheritFormat then CheckCharId(AFormat);
  k := FText.ParaOfPos(APos);
  d := DataOf(k);
  r := RunsOfData(d);
  ps := FText.ParaStart(k);
  o := APos - ps;
  len := FText.ParaLength(k);
  if AFormat = TyRichInheritFormat then f := InheritedFormat(r, o) else f := AFormat;
  fmt := FormatOfData(d);
  cell := CellOfData(d);
  oldChars := FText.Length;
  oldCount := FText.ParaCount;
  Result := NewUndo(c);
  try
    Result.FFirstPara := k;
    Result.AddOld(d);
    Result.SealOld;
    // the pieces the insert splits (a lazy paragraph's one), for the undo to give back
    Result.FSpan := FText.PieceSpan(APos, APos);
    Inc(FEditing);
    try
      FText.Insert(APos, txt);
    finally
      Dec(FEditing);
    end;
    added := FText.Length - oldChars;
    s := FText.ParaCount - oldCount;
    runs1 := nil;
    n1 := 0;
    if s = 0 then
    begin
      SetLength(runs1, Length(r) + 2);
      AppendSlice(runs1, n1, r, len, 0, o, 0);
      AppendRun(runs1, n1, o, f, AObj);
      AppendSlice(runs1, n1, r, len, o, len, added);
      SetLength(runs1, n1);
      PutData(k, d, MakeDataLike(fmt, runs1, cell, d));
    end
    else
    begin
      // the storage left d with the first part and nil on the new paragraphs; every part
      // carries the paragraph's format, the runs split at APos
      len1 := FText.ParaLength(k);
      AppendSlice(runs1, n1, r, len, 0, o, 0);
      if len1 > o then AppendRun(runs1, n1, o, f, nil);
      if n1 = 0 then AppendRun(runs1, n1, 0, f, nil);
      SetLength(runs1, n1);
      lenLast := FText.ParaLength(k + s) - (len - o);
      runs2 := nil;
      n2 := 0;
      if lenLast > 0 then AppendRun(runs2, n2, 0, f, nil);
      AppendSlice(runs2, n2, r, len, o, len, lenLast - o);
      if n2 = 0 then AppendRun(runs2, n2, 0, f, nil);
      SetLength(runs2, n2);
      // a list item given a start begins its list in the first part; the parts after it
      // go on from it (an item split by Enter is the next number)
      fmtNext := fmt;
      pfv := FFormats.ParaFormat(fmt);
      if pfv.List.StartAt > 0 then
      begin
        pfv.List.StartAt := 0;
        fmtNext := FFormats.InternPara(pfv);
      end;
      if s > 1 then
      begin
        // the paragraphs in between are alike: one shared value
        one := nil;
        SetLength(one, 1);
        one[0].Start := 0;
        one[0].Format := f;
        one[0].Obj := nil;
        mid := MakeData(fmtNext, one, cell);
        if mid <> nil then
        begin
          AcquireData(mid);
          for i := k + 1 to k + s - 1 do PutData(i, nil, mid);
          ReleaseData(mid);
        end;
      end;
      PutData(k, d, MakeDataLike(fmt, runs1, cell, d));
      PutData(k + s, nil, MakeData(fmtNext, runs2, cell));
      { (a split is outside every field - RaiseRefused - and the text has no mark: the new
        paragraphs start at 0, MakeData's; the first keeps its depth, MakeDataLike's) }
    end;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckText];
  if s > 0 then Include(c.Kinds, rckStructure);
  c.NewLen := added;
  Result.FInserted := added;
  c.FirstPara := k;
  c.OldParaCount := 1;
  c.NewParaCount := 1 + s;
  Result.FChange := c;
  Notify(c);
end;

function TTyRichDocument.InsertText(APos: TTyRichPos; const AText: UTF8String;
  AFormat: TTyCharFormatId): TTyRichUndoData;
begin
  Result := InsertCore(APos, AText, AFormat, nil);
end;

function TTyRichDocument.InsertObject(APos: TTyRichPos; AObject: TTyRichObject;
  AFormat: TTyCharFormatId): TTyRichUndoData;
begin
  if AObject = nil then
    raise ETyRichModel.Create('InsertObject needs an object');
  // one mark alone would leave its field without its other edge
  if AObject is TTyRichFieldMark then
    raise ETyRichModel.Create('A field mark goes into a document only with its field');
  Result := InsertCore(APos, TyRichObjectChar, AFormat, AObject);
end;

function TTyRichDocument.ReplaceObject(APos: TTyRichPos;
  AObject: TTyRichObject): TTyRichUndoData;
var
  c: TTyRichChange;
  k, i: Integer;
  d: TTyRichParaData;
  runs: TTyRunArray;
begin
  if AObject = nil then
    raise ETyRichModel.Create('ReplaceObject needs an object');
  if (APos < 0) or (APos >= FText.Length) then
    raise ETyRichModel.CreateFmt('Position %d out of 0..%d', [APos, FText.Length - 1]);
  RaiseRefused(APos, 0);
  c := Default(TTyRichChange);
  c.Pos := APos;
  k := FText.ParaOfPos(APos);
  d := DataOf(k);
  i := ObjectRunAt(RunsOfData(d), APos - FText.ParaStart(k));
  if i < 0 then
    raise ETyRichModel.CreateFmt('No object at %d', [APos]);
  if RunsOfData(d)[i].Obj = AObject then Exit(NewUndo(c));
  // a field's edge is its field's: it neither goes nor comes alone
  if (FMarkEdit = 0) and ((AObject is TTyRichFieldMark) or
    (RunsOfData(d)[i].Obj is TTyRichFieldMark)) then
    raise ETyRichModel.Create('A field mark is not replaced on its own');
  // a value is immutable: a copy of its runs with the one object put in
  runs := Copy(RunsOfData(d));
  runs[i].Obj := AObject;
  Result := NewUndo(c);
  try
    Result.FFirstPara := k;
    Result.AddOld(d);
    PutData(k, d, MakeDataLike(FormatOfData(d), runs, CellOfData(d), d));
    Result.SealOld;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckFormat];
  c.OldLen := 1;
  c.NewLen := 1;
  c.FirstPara := k;
  c.OldParaCount := 1;
  c.NewParaCount := 1;
  Result.FChange := c;
  Notify(c);
end;

function TTyRichDocument.DeleteRange(APos, ALen: TTyRichPos): TTyRichUndoData;
begin
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, FText.Length]);
  if ALen > 0 then RaiseRefused(APos, ALen);
  // the values of the two end paragraphs are held while the other is read
  BeginRead;
  try
    Result := DeleteCore(APos, ALen);
  finally
    EndRead;
  end;
end;

function TTyRichDocument.DeleteKnownRange(APos, ALen: TTyRichPos;
  const APieces: TTyRichPieces): TTyRichUndoData;
begin
  FKnownRemoved := APieces;
  try
    Result := DeleteRange(APos, ALen);
  finally
    FKnownRemoved := Default(TTyRichPieces);
  end;
end;

function TTyRichDocument.DeleteCore(APos, ALen: TTyRichPos): TTyRichUndoData;
var
  c: TTyRichChange;
  k, m, n, i: Integer;
  dk, dm, merged, src: TTyRichParaData;
  rk, rm, runs: TTyRunArray;
  e, psk, lenk, ok, lenm, om: Int64;
  fmt: TTyParaFormatId;
  cell: TTyRichCell;
  join: Boolean;
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  if ALen = 0 then Exit(NewUndo(c));
  e := APos + ALen;
  k := FText.ParaOfPos(APos);
  m := FText.ParaOfPos(e);
  dk := DataOf(k);
  if m <> k then dm := DataOf(m) else dm := dk;
  rk := RunsOfData(dk);
  psk := FText.ParaStart(k);
  lenk := FText.ParaLength(k);
  ok := APos - psk;
  runs := nil;
  n := 0;
  if m = k then
  begin
    AppendSlice(runs, n, rk, lenk, 0, ok, 0);
    AppendSlice(runs, n, rk, lenk, ok + ALen, lenk, -ALen);
    if n = 0 then AppendRun(runs, n, 0, rk[RunIndexAt(rk, ok)].Format, nil);
    SetLength(runs, n);
    merged := MakeDataLike(FormatOfData(dk), runs, CellOfData(dk), dk);
  end
  else
  begin
    rm := RunsOfData(dm);
    lenm := FText.ParaLength(m);
    om := e - FText.ParaStart(m);
    // one separator and nothing else, after text: the paragraph before it gives the format.
    // After an empty paragraph it does not (measured in WordPad's engine): that is the
    // empty paragraph going, a whole paragraph like any other
    join := (m = k + 1) and (ALen = 1) and (lenk > 0);
    if join then
    begin
      fmt := FormatOfData(dk);
      cell := CellOfData(dk);
      src := dk;
    end
    else
    begin
      // otherwise the paragraph the range ends in does (measured in WordPad)
      fmt := FormatOfData(dm);
      cell := CellOfData(dm);
      src := dm;
    end;
    if (ok = 0) and (om = 0) and not join then
      merged := dm   // whole paragraphs went: the next one is untouched
    else
    begin
      AppendSlice(runs, n, rk, lenk, 0, ok, 0);
      AppendSlice(runs, n, rm, lenm, om, lenm, ok - om);
      if n = 0 then AppendRun(runs, n, 0, rk[RunIndexAt(rk, ok)].Format, nil);
      SetLength(runs, n);
      merged := MakeDataLike(fmt, runs, cell, src);
    end;
    // the joined paragraph starts where k did: as deep in fields as k (the range between is
    // whole fields - RaiseRefused - so what follows it is as deep as before)
    merged := WithDepth(merged, DepthOfData(dk));
  end;
  Result := NewUndo(c);
  try
    if (Length(FKnownRemoved.Pieces) > 0) and (FKnownRemoved.CharCount = ALen) then
      Result.FRemoved := FKnownRemoved
    else
      Result.FRemoved := FText.PieceSnapshot(APos, ALen);
    for i := 0 to High(Result.FRemoved.Pieces) do
      if (Result.FRemoved.Pieces[i].Separator <> rsNone) and
         (Result.FRemoved.Pieces[i].Data <> nil) then
        AcquireData(TTyRichParaData(Result.FRemoved.Pieces[i].Data));
    Result.FFirstPara := k;
    Result.AddOld(dk);
    Result.SealOld;
    { The pieces the delete splits at its two ends (a lazy paragraph it cuts into), for the
      undo to give back: one span when the ends are that close. }
    Result.FSpan := FText.PieceSpan(APos, APos);
    Result.FSpan2 := FText.PieceSpan(e, e);
    if Result.FSpan.Pos + Result.FSpan.Pieces.CharCount > Result.FSpan2.Pos then
    begin
      Result.FSpan := FText.PieceSpan(APos, e);
      Result.FSpan2 := Default(TTyRichSpan);
    end;
    AcquireData(merged);   // it may be dm, whose slot the delete drops
    try
      Inc(FEditing);
      try
        FText.Delete(APos, ALen);
      finally
        Dec(FEditing);
      end;
      PutData(k, dk, merged);
      // a row whose last paragraph went: its table's rows are no longer known
      if m > k then RowsLost(k, dk, Result.FRemoved);
    finally
      ReleaseData(merged);
    end;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckText];
  if m > k then Include(c.Kinds, rckStructure);
  c.OldLen := ALen;
  c.FirstPara := k;
  c.OldParaCount := m - k + 1;
  c.NewParaCount := 1;
  Result.FChange := c;
  Notify(c);
end;

{ The text storage's sequence rule (tyControls.RichEdit.Text's SeqLen): the length of the valid
  UTF-8 sequence at P, 1 for a byte that starts none (a character of its own). }
function StoredSeqLen(P: PByte; AAvail: PtrInt): Integer; inline;
var
  b0, b1: Byte;
begin
  b0 := P^;
  if b0 < $C2 then Exit(1);
  if b0 < $E0 then
  begin
    if (AAvail >= 2) and (P[1] and $C0 = $80) then Exit(2);
    Exit(1);
  end;
  if b0 < $F0 then
  begin
    if AAvail < 3 then Exit(1);
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) then Exit(1);
    if (b0 = $E0) and (b1 < $A0) then Exit(1);
    if (b0 = $ED) and (b1 > $9F) then Exit(1);
    Exit(3);
  end;
  if b0 < $F5 then
  begin
    if AAvail < 4 then Exit(1);
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) or (P[3] and $C0 <> $80) then Exit(1);
    if (b0 = $F0) and (b1 < $90) then Exit(1);
    if (b0 = $F4) and (b1 > $8F) then Exit(1);
    Exit(4);
  end;
  Result := 1;
end;

function StoredChars(const S: RawByteString): Int64;
var
  p, stop: PByte;
begin
  Result := 0;
  if S = '' then Exit;
  p := PByte(Pointer(S));
  stop := p + Length(S);
  while p < stop do
  begin
    if p^ < $80 then Inc(p) else Inc(p, StoredSeqLen(p, stop - p));
    Inc(Result);
  end;
end;

{ A growing buffer of bytes: a stretch's new text, built once. }
type
  TReplaceBuf = record
    S: RawByteString;
    N: PtrInt;
  end;

procedure BufAdd(var B: TReplaceBuf; P: PByte; ACount: PtrInt);
var
  cap: PtrInt;
begin
  if ACount <= 0 then Exit;
  if B.N + ACount > Length(B.S) then
  begin
    cap := Length(B.S) * 2;
    if cap < B.N + ACount then cap := B.N + ACount;
    if cap < 256 then cap := 256;
    SetLength(B.S, cap);
  end;
  Move(P^, B.S[B.N + 1], ACount);
  Inc(B.N, ACount);
end;

function TTyRichDocument.ReplaceInParas(const APos: array of TTyRichPos; AFrom, ACount: Integer;
  ALen: TTyRichPos; const AText: UTF8String; out ASkipped: Integer): TTyRichUndoData;
const
  // two matches this close are one stretch of the text: what lies between them is copied
  CGap = 256;
var
  c: TTyRichChange;
  i, j, x, y, z, para, nr, lowPara, highPara: Integer;
  d: TTyRichParaData;
  runs, nruns: TTyRunArray;
  ps, len, off, shift, prevEnd, rlen, a, b, total, grow, oldLo, oldHi, at: TTyRichPos;
  snap: TTyRichPieces;
  seg: UTF8String;
  buf: TReplaceBuf;
  p, stop, gapFrom: PByte;
  k, nk, nf, fp: Integer;
  kept: array of TTyRichPos;
  fh: Boolean;
  fe: TTyRichPos;
begin
  ASkipped := 0;
  c := Default(TTyRichChange);
  Result := nil;
  if ACount <= 0 then Exit(NewUndo(c));
  if CutSequence(AText) then
    raise ETyRichModel.Create('The text to insert starts or ends inside a UTF-8 sequence');
  for k := 1 to Length(AText) do
    if AText[k] in [#10, #13] then
      raise ETyRichModel.Create('ReplaceInParas takes no paragraph separator');
  if ALen <= 0 then raise ETyRichModel.Create('ReplaceInParas needs matches of a length');
  for i := AFrom to AFrom + ACount - 1 do
    if (APos[i] < 0) or (APos[i] + ALen > FText.Length) or
      ((i > AFrom) and (APos[i] < APos[i - 1] + ALen)) then
      raise ETyRichModel.Create('ReplaceInParas: matches out of range or out of order');
  { A match inside a field's result (or one that would take a mark of a field and not the
    other) stays as it is, as one in a row that holds a nested table does: the others are
    replaced. Asked only where there can be one: in a paragraph that starts inside a field or
    holds a mark (the find, which asks the same of the matches it gives, passes over the
    others; this is the primitive's own guard). }
  kept := nil;
  SetLength(kept, ACount);
  nk := 0;
  fp := -1;
  fh := False;
  fe := 0;
  BeginRead;
  try
    for i := AFrom to AFrom + ACount - 1 do
    begin
      if (fp < 0) or (APos[i] >= fe) then
      begin
        fp := FText.ParaOfPos(APos[i]);
        fe := FText.ParaStart(fp) + FText.ParaLength(fp);
        d := DataOf(fp);
        fh := DepthOfData(d) <> 0;
        if (d <> nil) and not fh then
          for j := 0 to High(d.FRuns) do
            if d.FRuns[j].Obj is TTyRichFieldMark then
            begin
              fh := True;
              Break;
            end;
      end;
      if (fh or (APos[i] + ALen > fe)) and FieldRefused(APos[i], ALen) then Inc(ASkipped)
      else
      begin
        kept[nk] := APos[i];
        Inc(nk);
      end;
    end;
  finally
    EndRead;
  end;
  if nk < ACount then
  begin
    nf := ASkipped;
    Result := ReplaceInParas(kept, 0, nk, ALen, AText, ASkipped);
    Inc(ASkipped, nf);
    Exit;
  end;
  kept := nil;
  rlen := StoredChars(AText);
  Result := NewUndo(c);
  lowPara := -1;
  highPara := -1;
  grow := 0;
  oldLo := 0;
  oldHi := 0;
  buf.S := '';
  buf.N := 0;
  // (the values read are held while the others are: one read scope)
  BeginRead;
  try
    try
      // paragraph by paragraph, the last first: positions before stay where they are
      i := AFrom + ACount - 1;
      while i >= AFrom do
      begin
        para := FText.ParaOfPos(APos[i]);
        ps := FText.ParaStart(para);
        len := FText.ParaLength(para);
        j := i;
        while (j > AFrom) and (APos[j - 1] >= ps) do Dec(j);
        if APos[i] + ALen > ps + len then
          raise ETyRichModel.Create('ReplaceInParas: a match takes a paragraph separator');
        d := DataOf(para);
        // a row that holds a nested table stays as the file has it
        if FixedData(d) then
        begin
          Inc(ASkipped, i - j + 1);
          i := j - 1;
          Continue;
        end;
        runs := RunsOfData(d);
        // its runs after: each replacement in the format of the first character it replaces
        nruns := nil;
        nr := 0;
        shift := 0;
        prevEnd := 0;
        for x := j to i do
        begin
          off := APos[x] - ps;
          AppendSlice(nruns, nr, runs, len, prevEnd, off, shift);
          if rlen > 0 then AppendRun(nruns, nr, off + shift, runs[RunIndexAt(runs, off)].Format, nil);
          Inc(shift, rlen - ALen);
          prevEnd := off + ALen;
        end;
        AppendSlice(nruns, nr, runs, len, prevEnd, len, shift);
        if nr = 0 then AppendRun(nruns, nr, 0, runs[RunIndexAt(runs, APos[j] - ps)].Format, nil);
        SetLength(nruns, nr);
        // its pieces as they are, whole, with its separator (a lazy paragraph: one, the file's)
        total := len;
        if para < FText.ParaCount - 1 then Inc(total);
        snap := FText.PieceSnapshot(ps, total);
        Result.AddSwap(para, d, snap);
        // the text: stretch by stretch, the last first
        Inc(FEditing);
        try
          x := i;
          while x >= j do
          begin
            y := x;
            while (y > j) and (APos[y] - (APos[y - 1] + ALen) <= CGap) do Dec(y);
            a := APos[y];
            b := APos[x] + ALen;
            buf.N := 0;
            if y = x then
              BufAdd(buf, PByte(Pointer(AText)), Length(AText))
            else
            begin
              // the stretch once, and what lies between its matches out of it
              seg := FText.GetText(a, b - a);
              p := PByte(Pointer(seg));
              stop := p + Length(seg);
              at := a;
              for z := y to x do
              begin
                // at the match z: its characters go, the text comes
                gapFrom := nil;
                while at < APos[z] + ALen do
                begin
                  if at = APos[z] then
                    BufAdd(buf, PByte(Pointer(AText)), Length(AText));
                  if p^ < $80 then Inc(p) else Inc(p, StoredSeqLen(p, stop - p));
                  Inc(at);
                end;
                if z < x then
                begin
                  gapFrom := p;
                  while at < APos[z + 1] do
                  begin
                    if p^ < $80 then Inc(p) else Inc(p, StoredSeqLen(p, stop - p));
                    Inc(at);
                  end;
                  BufAdd(buf, gapFrom, p - gapFrom);
                end;
              end;
            end;
            FText.Delete(a, b - a);
            if buf.N > 0 then FText.Insert(a, Copy(buf.S, 1, buf.N));
            x := y - 1;
          end;
        finally
          Dec(FEditing);
        end;
        PutData(para, d, MakeDataLike(FormatOfData(d), nruns, CellOfData(d), d));
        Inc(grow, shift);
        if highPara < 0 then
        begin
          highPara := para;
          oldHi := ps + len;
        end;
        lowPara := para;
        oldLo := ps;
        i := j - 1;
      end;
      Result.SealSwaps;
    except
      // what was changed goes back before the error travels on
      try
        Revert(Result);
      except
      end;
      Result.Free;
      raise;
    end;
  finally
    EndRead;
  end;
  // (all of them in rows the document keeps: nothing changed, an empty record)
  if lowPara < 0 then Exit;
  c.Kinds := [rckText];
  c.Pos := oldLo;
  c.OldLen := oldHi - oldLo;
  c.NewLen := c.OldLen + grow;
  c.FirstPara := lowPara;
  c.OldParaCount := highPara - lowPara + 1;
  c.NewParaCount := c.OldParaCount;
  Result.FChange := c;
  Notify(c);
end;

{ Undoes what ReplaceInParas did, the paragraph changed last first: each paragraph's text goes
  whole, with its separator, and its pieces come back (a lazy one: the file's bytes again, so
  that an edit undone saves the file as it was; the paragraph after it gets the value it had
  then), then its value. }
procedure TTyRichDocument.RevertSwaps(AUndo: TTyRichUndoData);
var
  e, i: Integer;
  ps, n: TTyRichPos;
  p: TTyRichPieces;
begin
  for e := AUndo.FSwapCount - 1 downto 0 do
  begin
    ps := FText.ParaStart(AUndo.FSwaps[e].Para);
    n := FText.ParaLength(AUndo.FSwaps[e].Para);
    if AUndo.FSwaps[e].Para < FText.ParaCount - 1 then Inc(n);
    p.Pieces := Copy(AUndo.FSwapPieces, AUndo.FSwaps[e].First, AUndo.FSwaps[e].Count);
    p.CharCount := 0;
    for i := 0 to High(p.Pieces) do Inc(p.CharCount, p.Pieces[i].CharCount);
    // the restored separator puts its value back in a slot: the slot's reference
    for i := 0 to High(p.Pieces) do
      if (p.Pieces[i].Separator <> rsNone) and (p.Pieces[i].Data <> nil) then
        AcquireData(TTyRichParaData(p.Pieces[i].Data));
    FText.Delete(ps, n);
    FText.RestorePieces(ps, p);
    PutData(AUndo.FSwaps[e].Para, SlotData(AUndo.FSwaps[e].Para), AUndo.FSwaps[e].Old);
  end;
end;

function TTyRichDocument.ApplyCharFormat(APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat; AKeepNone: TTyCharFormatMask): TTyRichUndoData;
var
  c: TTyRichChange;
  k, last: Integer;
  w: TTyRichCharWalk;
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, FText.Length]);
  if (ALen = 0) or (AMask = []) then Exit(NewUndo(c));
  k := FText.ParaOfPos(APos);
  last := FText.ParaOfPos(APos + ALen);
  if (last > k) and (FText.ParaStart(last) = APos + ALen) then Dec(last);
  Result := NewUndo(c);
  w := TTyRichCharWalk.Create;
  try
    try
      w.Doc := Self;
      w.Undo := Result;
      w.K := k;
      w.Last := last;
      w.APos := APos;
      w.B := APos + ALen;
      w.Mask := AMask;
      w.Value := AValue;
      w.KeepNone := AKeepNone * [cffFontName, cffSize];
      // only the two end paragraphs need their place; the walk itself does no lookups
      w.PsK := FText.ParaStart(k);
      w.LenK := FText.ParaLength(k);
      w.PsLast := FText.ParaStart(last);
      w.LenLast := FText.ParaLength(last);
      Result.FFirstPara := k;
      FText.MapParaData(k, last, @w.Map);
      Result.SealOld;
      { No value changed (a write of what the text has, or a range wholly inside a row
        that holds a nested table): no change - the command is then not kept. }
      if not w.Changed then
      begin
        Result.FChange := c;
        Exit;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    w.Free;
  end;
  c.Kinds := [rckFormat];
  c.OldLen := ALen;
  c.NewLen := ALen;
  c.FirstPara := k;
  c.OldParaCount := last - k + 1;
  c.NewParaCount := last - k + 1;
  Result.FChange := c;
  Notify(c);
end;

function TTyRichDocument.ApplyParaFormat(AFirstPara, ALastPara: Integer;
  AMask: TTyParaFormatMask; const AValue: TTyParaFormat): TTyRichUndoData;
var
  c: TTyRichChange;
  w: TTyRichParaWalk;
begin
  c := Default(TTyRichChange);
  if (AFirstPara < 0) or (ALastPara < AFirstPara) or (ALastPara >= FText.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraphs %d..%d out of 0..%d',
      [AFirstPara, ALastPara, FText.ParaCount - 1]);
  c.Pos := FText.ParaStart(AFirstPara);
  if AMask = [] then Exit(NewUndo(c));
  Result := NewUndo(c);
  w := TTyRichParaWalk.Create;
  try
    try
      w.Doc := Self;
      w.Undo := Result;
      w.First := AFirstPara;
      w.Mask := AMask;
      w.Value := AValue;
      Result.FFirstPara := AFirstPara;
      FText.MapParaData(AFirstPara, ALastPara, @w.Map);
      Result.SealOld;
      // no value changed: no change, the command is not kept
      if not w.Changed then
      begin
        Result.FChange := c;
        Exit;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    w.Free;
  end;
  c.Kinds := [rckFormat];
  c.OldLen := FText.ParaStart(ALastPara) + FText.ParaLength(ALastPara) - c.Pos;
  c.NewLen := c.OldLen;
  c.FirstPara := AFirstPara;
  c.OldParaCount := ALastPara - AFirstPara + 1;
  c.NewParaCount := c.OldParaCount;
  Result.FChange := c;
  Notify(c);
end;

function TTyRichDocument.MarkTable(AFirstPara: Integer; ATable: TTyRichTable;
  const ACellParas: array of Integer): TTyRichUndoData;
var
  c: TTyRichChange;
  total, i, p, r, ci, x, lastPara: Integer;
  cells: array of TTyRichCell;
  d: TTyRichParaData;
begin
  if ATable = nil then
    raise ETyRichModel.Create('MarkTable needs a table');
  if ATable.FParaRefs > 0 then
    raise ETyRichModel.Create('The table is already in use');
  if Length(ACellParas) <> ATable.CellCount then
    raise ETyRichModel.CreateFmt('%d paragraph counts for %d cells',
      [Length(ACellParas), ATable.CellCount]);
  total := 0;
  for i := 0 to High(ACellParas) do
  begin
    if ACellParas[i] < 1 then
      raise ETyRichModel.Create('Every cell needs at least one paragraph');
    Inc(total, ACellParas[i]);
  end;
  // no row yet: there is no paragraph range to mark (and none to report as changed)
  if total = 0 then
    raise ETyRichModel.Create('A table without cells cannot be marked');
  lastPara := AFirstPara + total - 1;
  if (AFirstPara < 0) or (lastPara >= FText.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraphs %d..%d out of 0..%d',
      [AFirstPara, lastPara, FText.ParaCount - 1]);
  for i := AFirstPara to lastPara do
    if CellOfData(DataOf(i)) <> nil then
      raise ETyRichModel.CreateFmt('Paragraph %d is already in a table', [i]);
  cells := nil;
  SetLength(cells, total);
  p := 0;
  i := 0;
  for r := 0 to ATable.RowCount - 1 do
    for ci := 0 to ATable.Rows[r].CellCount - 1 do
    begin
      for x := 1 to ACellParas[i] do
      begin
        cells[p] := ATable.Rows[r].Cells[ci];
        Inc(p);
      end;
      Inc(i);
    end;
  c := Default(TTyRichChange);
  c.Pos := FText.ParaStart(AFirstPara);
  Result := NewUndo(c);
  try
    Result.FFirstPara := AFirstPara;
    for i := 0 to total - 1 do
    begin
      d := DataOf(AFirstPara + i);
      Result.AddOld(d);
      PutData(AFirstPara + i, d, MakeDataLike(FormatOfData(d), RunsOfData(d), cells[i], d));
    end;
    Result.SealOld;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckStructure];
  c.OldLen := FText.ParaStart(lastPara) + FText.ParaLength(lastPara) - c.Pos;
  c.NewLen := c.OldLen;
  c.FirstPara := AFirstPara;
  c.OldParaCount := total;
  c.NewParaCount := total;
  Result.FChange := c;
  Notify(c);
end;

{ ---- table edits ---- }

type
  TTyIntArray = TTyRichEdges;

  // a cell's paragraphs in its row (First -1: none)
  TTyRichShapeCell = record
    First, Last: Integer;
  end;

  // a row of a table as its paragraphs have it
  TTyRichShapeRow = record
    Row: TTyRichRow;
    First, Last: Integer;
    Cells: array of TTyRichShapeCell;
  end;

  { The table a paragraph is in, as the table edits count it: its paragraphs, and its rows
    as runs of paragraphs of one row object (a row a plain delete left with none is not
    there). }
  TTyRichShape = record
    First, Last: Integer;
    Rows: array of TTyRichShapeRow;
    RowCount: Integer;
    Cells: array of TTyRichCell;   // each paragraph's, from First on (good in the read scope)
    Locked: TTyRichTableRefusal;   // rtrNone, rtrMergedCells or rtrNestedTable
    Regular: Boolean;              // every row has as many cells
    Ordered: Boolean;              // in every row each cell's paragraphs follow each other, in cell order
    { Rows of a table whose rows are known (TTyRichTable.FRowsValid; no part a loader cut):
      Rows are its rows Base .. Base + RowCount - 1 alone (ReadRowWindow). Not Window: the
      table read whole, or the part (ReadTableShape), Base 0. }
    Window: Boolean;
    Base: Integer;
    Table: TTyRichTable;
    // an edit of rows: the row it names (CRichRowAbove / CRichRowBelow resolved), as Base counts
    RowIndex: Integer;
  end;

  // a paragraph a table edit puts in: empty, one run
  TTyRichNewPara = record
    Cell: TTyRichCell;
    ParaFormat: TTyParaFormatId;
    CharFormat: TTyCharFormatId;
  end;
  TTyRichNewParas = array of TTyRichNewPara;

  // a row of the table an edit makes
  TTyRichPlanRow = record
    Shape: Integer;                // the row of the shape it is, -1 a new one
    // that row as it is (an edit of rows leaves the rows it does not make as they are)
    Same: Boolean;
    // its formats (nil: decoded from Raw; TTyRichRow.BaseFormat, Format)
    Base, Format: TTyRichRowFormat;
    Raw: RawByteString;
    Edges: array of Integer;
    Nested: Boolean;
    CellFrom: array of Integer;    // per cell: the shape row's cell it is, -1 a new one
    NewFormat: array of TTyRichNewPara;   // the formats of a new cell's paragraph
  end;

  // what an edit does to the text, by the paragraphs as they were before it
  TTyRichTableOp = record
    Anchor: Integer;               // a delete's first paragraph; an insert goes before it
    Last: Integer;                 // a delete's last paragraph
    Insert: Boolean;
    Paras: TTyRichNewParas;
  end;

  TTyRichTableEditor = class
  private
    Doc: TTyRichDocument;
    Edit: TTyRichTableEdit;
    Kept: ^TTyRichTables;
    Own: TTyRichTables;            // the tables made in this run, held until it ends
    Shape: TTyRichShape;
    Plan: array of TTyRichPlanRow;
    Ops: array of TTyRichTableOp;
    OpCount: Integer;
    Pending: TTyRichNewParas;
    PendingCount: Integer;
    // the plan's row an edit of rows puts in or takes out, as the shape counts its rows
    RowAt: Integer;
    // formats the plan holds a reference of (let go of with the editor)
    Held: array of TTyRichRowFormat;
    function Hold(AFormat: TTyRichRowFormat): TTyRichRowFormat;
    function NewTable(const AColBoundaries: array of Integer): TTyRichTable;
    function TableFor(const AColBoundaries: array of Integer): TTyRichTable;
    function Repointed(D: TTyRichParaData; ACell: TTyRichCell): TTyRichParaData;
    function SetCells(AFirst: Integer; const ACells: array of TTyRichCell;
      AKinds: TTyRichChangeKinds): TTyRichUndoData;
    function InsertParas(APara: Integer; const AParas: array of TTyRichNewPara): TTyRichUndoData;
    function DeleteParas(AFirst, ALast: Integer): TTyRichUndoData;
    function FormatOf(APara: Integer): TTyRichNewPara;
    function Unlisted(AFormat: TTyParaFormatId): TTyParaFormatId;
    procedure AddOp(AAnchor, ALast: Integer; AInsert: Boolean; const AParas: TTyRichNewParas);
    procedure Pend(const APara: TTyRichNewPara);
    procedure Flush(AAnchor: Integer);
    procedure PlanRows;
    procedure PlanColumns;
    procedure PlanMerge;
    procedure PlanSplit;
    procedure PlanGridColumns;
    procedure InsertTable(U: TTyRichUndoData);
    procedure EditShape(U: TTyRichUndoData);
  public
    destructor Destroy; override;
    function Run: TTyRichUndoData;
  end;

function RefusalName(R: TTyRichTableRefusal): string;
const
  Names: array[TTyRichTableRefusal] of string = ('none', 'read-only', 'no table', 'in a table',
    'merged cells', 'nested table', 'not whole', 'irregular rows', 'out of range',
    'in a field''s result', 'cells not empty');
begin
  Result := Names[R];
end;


{ Two rows a file cannot tell apart: the same format bytes, cells, edges, nested table. }
function RowsAlike(A, B: TTyRichRow): Boolean;
var
  ea, eb: TTyRichEdges;
  i: Integer;
begin
  if A = B then Exit(True);
  // (the same bytes and a look of its own set since: another row to a writer)
  Result := (Length(A.FCells) = Length(B.FCells)) and
    (A.FHoldsNestedTable = B.FHoldsNestedTable) and SameBytes(A.FRawFormat, B.FRawFormat) and
    (A.Format = B.Format);
  if not Result then Exit;
  ea := A.CellEdges;
  eb := B.CellEdges;
  for i := 0 to High(ea) do
    if ea[i] <> eb[i] then Exit(False);
end;

procedure FillShape(ADoc: TTyRichDocument; AFirst, ALast: Integer; var S: TTyRichShape); forward;

{ Reads the table paragraph APara is in into S: rtrNoTable outside one; rtrNotWhole for a part
  of a table its loader cannot give whole (S is then the part); else rtrNone (S.Locked says
  what its content forbids). Call it inside a read scope. }
function ReadTableShape(ADoc: TTyRichDocument; APara: Integer; out S: TTyRichShape): TTyRichTableRefusal;
var
  t: TTyRichTable;
  f, l, k, i: Integer;
  c, c0: TTyRichCell;
begin
  S := Default(TTyRichShape);
  S.Locked := rtrNone;
  S.First := -1;
  S.Last := -1;
  Inc(ADoc.FTableParaVisits);
  c0 := ADoc.CellAt(APara);
  c := c0;
  if c = nil then Exit(rtrNoTable);
  t := c.FRow.FTable;
  Result := rtrNone;
  f := -1;
  if t.FCut then
  begin
    // (the loader's range starts and ends with the parts' own first and last paragraphs)
    if (ADoc.FLoader <> nil) and ADoc.FLoader.WholeTable(ADoc, APara, f, l) then
    begin
      SetLength(S.Cells, l - f + 1);
      for k := f to l do
      begin
        Inc(ADoc.FTableParaVisits);
        S.Cells[k - f] := ADoc.CellAt(k);
        if S.Cells[k - f] = nil then
        begin
          // a range with a paragraph in no table: not a table to go by
          f := -1;
          Break;
        end;
      end;
    end;
    if f < 0 then Result := rtrNotWhole;
  end;
  if f < 0 then
  begin
    // the object's paragraphs, each read once: back from APara, then on from it (and the
    // paragraph on either side, which ends the walk)
    l := APara;
    f := APara;
    SetLength(S.Cells, 16);
    i := 0;
    while f > 0 do
    begin
      Inc(ADoc.FTableParaVisits);
      c := ADoc.CellAt(f - 1);
      if (c = nil) or (c.FRow.FTable <> t) then Break;
      if i = Length(S.Cells) then SetLength(S.Cells, i * 2);
      S.Cells[i] := c;
      Inc(i);
      Dec(f);
    end;
    // (read backwards: turned round, then APara's and those after it)
    for k := 0 to i div 2 - 1 do
    begin
      c := S.Cells[k];
      S.Cells[k] := S.Cells[i - 1 - k];
      S.Cells[i - 1 - k] := c;
    end;
    if i = Length(S.Cells) then SetLength(S.Cells, i * 2 + 1);
    S.Cells[i] := c0;
    Inc(i);
    while l < ADoc.FText.ParaCount - 1 do
    begin
      Inc(ADoc.FTableParaVisits);
      c := ADoc.CellAt(l + 1);
      if (c = nil) or (c.FRow.FTable <> t) then Break;
      if i = Length(S.Cells) then SetLength(S.Cells, i * 2);
      S.Cells[i] := c;
      Inc(i);
      Inc(l);
    end;
    SetLength(S.Cells, i);
  end;
  FillShape(ADoc, f, l, S);
end;

{ S's rows from its cells, S.Cells[0] being paragraph AFirst's and the last ALast's: each
  run of paragraphs of one row object a row, its cells' paragraphs, and what its rows and
  their tables say of it (Locked, Regular, Ordered). }
procedure FillShape(ADoc: TTyRichDocument; AFirst, ALast: Integer; var S: TTyRichShape);
var
  f, l, k, r, ci, i: Integer;
  c: TTyRichCell;
  row: TTyRichRow;
  nested: Boolean;
begin
  f := AFirst;
  l := ALast;
  S.First := f;
  S.Last := l;
  S.Rows := nil;
  row := nil;
  r := -1;
  nested := False;
  S.Ordered := True;
  for k := f to l do
  begin
    c := S.Cells[k - f];
    if c.FRow.FHoldsNestedTable then nested := True;
    if c.FRow <> row then
    begin
      row := c.FRow;
      Inc(r);
      if r = Length(S.Rows) then SetLength(S.Rows, r * 2 + 4);
      S.Rows[r].Row := row;
      S.Rows[r].First := k;
      S.Rows[r].Cells := nil;
      SetLength(S.Rows[r].Cells, Length(row.FCells));
      for i := 0 to High(S.Rows[r].Cells) do
      begin
        S.Rows[r].Cells[i].First := -1;
        S.Rows[r].Cells[i].Last := -1;
      end;
    end;
    S.Rows[r].Last := k;
    ci := c.FIndex;
    // a cell's paragraphs follow each other, and the cells their order
    if (k > S.Rows[r].First) and (S.Cells[k - 1 - f].FIndex <> ci) and
       ((S.Cells[k - 1 - f].FIndex > ci) or (S.Rows[r].Cells[ci].First >= 0)) then
      S.Ordered := False;
    if S.Rows[r].Cells[ci].First < 0 then S.Rows[r].Cells[ci].First := k;
    S.Rows[r].Cells[ci].Last := k;
  end;
  S.RowCount := r + 1;
  SetLength(S.Rows, S.RowCount);
  // (merged cells forbid no structure edit: they go by the grid)
  if nested then S.Locked := rtrNestedTable;
  S.Regular := True;
  for r := 1 to S.RowCount - 1 do
    if Length(S.Rows[r].Row.FCells) <> Length(S.Rows[0].Row.FCells) then S.Regular := False;
  if ADoc = nil then Exit;
end;

{ Rows W0 .. W1 of table T, whose rows are known (T.FRowsValid), as a window S, found from
  paragraph APara of T: the paragraphs between it and them are read and theirs, each once,
  and the one after them. False when the paragraphs are not where T's rows say (S says
  nothing then). Call it inside a read scope. }
function ReadRowWindow(ADoc: TTyRichDocument; APara: Integer; T: TTyRichTable;
  W0, W1: Integer; out S: TTyRichShape): Boolean;
var
  p, last, n, nb, i, first: Integer;
  c, c0: TTyRichCell;
  back: array of TTyRichCell;
begin
  S := Default(TTyRichShape);
  Result := False;
  if (W0 < 0) or (W1 < W0) or (W1 >= Length(T.FRows)) then Exit;
  last := ADoc.FText.ParaCount - 1;
  Inc(ADoc.FTableParaVisits);
  c0 := ADoc.CellAt(APara);
  if (c0 = nil) or (c0.FRow.FTable <> T) then Exit;
  n := 0;
  SetLength(S.Cells, 16);
  if c0.FRow.FIndex >= W0 then
  begin
    // back from APara: the window's paragraphs before it, to the first of row W0
    back := nil;
    nb := 0;
    p := APara;
    while p > 0 do
    begin
      Inc(ADoc.FTableParaVisits);
      c := ADoc.CellAt(p - 1);
      if (c = nil) or (c.FRow.FTable <> T) or (c.FRow.FIndex < W0) then Break;
      if c.FRow.FIndex <= W1 then
      begin
        if nb = Length(back) then SetLength(back, nb * 2 + 8);
        back[nb] := c;
        Inc(nb);
      end;
      Dec(p);
    end;
    // (read backwards: turned round)
    if nb + 1 > Length(S.Cells) then SetLength(S.Cells, nb + 16);
    for i := 0 to nb - 1 do S.Cells[i] := back[nb - 1 - i];
    n := nb;
    first := p;
    if c0.FRow.FIndex > W1 then
    begin
      // the window lies before APara, whole
      SetLength(S.Cells, n);
      if n = 0 then Exit;
      FillShape(ADoc, first, first + n - 1, S);
    end
    else
    begin
      S.Cells[n] := c0;
      Inc(n);
      p := APara;
    end;
  end
  else
  begin
    // on from APara to the first paragraph of row W0
    p := APara;
    repeat
      Inc(p);
      if p > last then Exit;
      Inc(ADoc.FTableParaVisits);
      c := ADoc.CellAt(p);
      if (c = nil) or (c.FRow.FTable <> T) then Exit;
    until c.FRow.FIndex >= W0;
    if c.FRow.FIndex > W1 then Exit;
    first := p;
    S.Cells[0] := c;
    n := 1;
  end;
  if S.RowCount = 0 then
  begin
    // and on to the last paragraph of row W1
    while p < last do
    begin
      Inc(ADoc.FTableParaVisits);
      c := ADoc.CellAt(p + 1);
      if (c = nil) or (c.FRow.FTable <> T) or (c.FRow.FIndex > W1) then Break;
      if n = Length(S.Cells) then SetLength(S.Cells, n * 2);
      S.Cells[n] := c;
      Inc(n);
      Inc(p);
    end;
    SetLength(S.Cells, n);
    FillShape(ADoc, first, first + n - 1, S);
  end;
  // the rows found are T's, in their order
  if S.RowCount <> W1 - W0 + 1 then Exit;
  for i := 0 to S.RowCount - 1 do
    if S.Rows[i].Row <> T.FRows[W0 + i] then Exit;
  S.Window := True;
  S.Base := W0;
  S.Table := T;
  Result := True;
end;

{ What a table's content forbids a change of its structure for: a row that holds a nested
  table (read from its rows - a row object is no paragraph), else merged cells. }
function RowMerged(R: TTyRichRow): Boolean;
var
  f: TTyRichRowFormat;
  i: Integer;
begin
  f := R.Format;
  for i := 0 to f.CellCount - 1 do
    if (f.Cells[i].HMerge <> rcmNone) or (f.Cells[i].VMerge <> rcmNone) then Exit(True);
  Result := False;
end;

// a cell of the row begins or continues a merge down
function RowMergedDown(R: TTyRichRow): Boolean;
var
  f: TTyRichRowFormat;
  i: Integer;
begin
  f := R.Format;
  for i := 0 to f.CellCount - 1 do
    if f.Cells[i].VMerge <> rcmNone then Exit(True);
  Result := False;
end;

{ What a table's content forbids of every structure edit: a nested table (its rows are their
  file's bytes). Merged cells forbid nothing: the edits go by the grid. }
function TableLock(T: TTyRichTable): TTyRichTableRefusal;
var
  i: Integer;
begin
  for i := 0 to High(T.FRows) do
    if T.FRows[i].FHoldsNestedTable then Exit(rtrNestedTable);
  Result := rtrNone;
end;

destructor TTyRichTableEditor.Destroy;
var
  i: Integer;
begin
  // the paragraphs that use them hold their own references
  for i := 0 to High(Own) do Own[i].Release;
  for i := 0 to High(Held) do Held[i].Release;
  inherited Destroy;
end;

function TTyRichTableEditor.Hold(AFormat: TTyRichRowFormat): TTyRichRowFormat;
begin
  SetLength(Held, Length(Held) + 1);
  Held[High(Held)] := AFormat;
  Result := AFormat;
end;

function TTyRichTableEditor.NewTable(const AColBoundaries: array of Integer): TTyRichTable;
begin
  Result := TTyRichTable.Create(AColBoundaries);
  Result.AddRef;
  SetLength(Own, Length(Own) + 1);
  Own[High(Own)] := Result;
end;

{ The table the edit's rows go into: the one the command kept from its first run when it has
  those rows (a redo after an exact undo: the very same object again), else a new one, which
  the command keeps when it keeps none yet. }
function TTyRichTableEditor.TableFor(const AColBoundaries: array of Integer): TTyRichTable;
var
  t: TTyRichTable;
  fits: Boolean;
  r, i: Integer;
begin
  if Length(Kept^) > 0 then
  begin
    t := Kept^[0];
    fits := Length(t.FRows) = Length(Plan);
    if fits then
      for r := 0 to High(Plan) do
      begin
        if (Length(t.FRows[r].FCells) <> Length(Plan[r].CellFrom)) or
           not SameBytes(t.FRows[r].FRawFormat, Plan[r].Raw) or
           (Length(t.FRows[r].FBoundaries) <> Length(Plan[r].Edges)) or
           ((Plan[r].Format <> nil) and (t.FRows[r].Format <> Plan[r].Format)) then
        begin
          fits := False;
          Break;
        end;
        for i := 0 to High(Plan[r].Edges) do
          if t.FRows[r].FBoundaries[i] <> Plan[r].Edges[i] then fits := False;
      end;
    if fits then Exit(t);
  end;
  Result := NewTable(AColBoundaries);
  for r := 0 to High(Plan) do
  begin
    Result.AddRow(Length(Plan[r].CellFrom), Plan[r].Raw, Plan[r].Edges, Plan[r].Nested);
    if Plan[r].Format <> nil then Result.FRows[r].SetFormats(Plan[r].Base, Plan[r].Format);
  end;
  if Length(Kept^) = 0 then
  begin
    Result.AddRef;
    SetLength(Kept^, 1);
    Kept^[0] := Result;
  end;
end;

{ D's paragraph with ACell in place of its cell: its formats, runs and marker text. In a row
  the file cannot tell from the row of the cell the first such value had (an edit of rows
  makes the very rows of the file again), the new value names that first one as its source -
  a writer then still has the file's bytes for the paragraph. }
function TTyRichTableEditor.Repointed(D: TTyRichParaData; ACell: TTyRichCell): TTyRichParaData;
var
  root: TTyRichParaData;
begin
  Result := Doc.MakeDataLike(Doc.FormatOfData(D), Doc.RunsOfData(D), ACell, D);
  // (only a document read from a file has bytes to keep: a source is of use to its writer)
  if (ACell = nil) or (Result = nil) or (D = nil) or (Doc.FLoader = nil) then Exit;
  root := D;
  if D.FSource <> nil then root := D.FSource;
  if (root.FCell <> nil) and (root.FCell.FIndex = ACell.FIndex) and
     RowsAlike(root.FCell.FRow, ACell.FRow) then
  begin
    Doc.AcquireData(root);
    Result.FSource := root;
  end;
end;

{ Paragraphs AFirst .. get ACells[i] for their cells. AKinds []: the change is told nobody -
  for paragraphs whose rows look as they did (only the table object is another), so that a
  view keeps what it laid out of them. }
function TTyRichTableEditor.SetCells(AFirst: Integer; const ACells: array of TTyRichCell;
  AKinds: TTyRichChangeKinds): TTyRichUndoData;
var
  c: TTyRichChange;
  i, last: Integer;
  d: TTyRichParaData;
  met: TTyRichTable;
begin
  c := Default(TTyRichChange);
  c.Pos := Doc.FText.ParaStart(AFirst);
  Result := Doc.NewUndo(c);
  try
    Result.FFirstPara := AFirst;
    met := nil;
    for i := 0 to High(ACells) do
    begin
      Inc(Doc.FTableParaVisits);
      d := Doc.DataOf(AFirst + i);
      Result.AddOld(d);
      if Doc.CellOfData(d) <> ACells[i] then
      begin
        { the old value is the step's to keep now, and the table it is in when the new cell
          is another table's (counted once: the paragraphs of one table object follow each
          other) }
        Inc(Result.FExtraBytes, d.InstanceSize + Length(d.FRuns) * SizeOf(TTyRichRun) +
          Length(d.FListText));
        if (d.FCell <> nil) and (d.FCell.FRow.FTable <> met) and
           ((ACells[i] = nil) or (ACells[i].FRow.FTable <> d.FCell.FRow.FTable)) then
        begin
          met := d.FCell.FRow.FTable;
          Inc(Result.FExtraBytes, met.MemSize);
        end;
        Doc.PutData(AFirst + i, d, Repointed(d, ACells[i]));
      end;
    end;
    Result.SealOld;
  except
    // (the values set so far go back; nothing was told)
    Doc.Revert(Result);
    raise;
  end;
  if AKinds = [] then Exit;
  last := AFirst + High(ACells);
  c.Kinds := AKinds;
  c.OldLen := Doc.FText.ParaStart(last) + Doc.FText.ParaLength(last) - c.Pos;
  c.NewLen := c.OldLen;
  c.FirstPara := AFirst;
  c.OldParaCount := Length(ACells);
  c.NewParaCount := c.OldParaCount;
  Result.FChange := c;
  Doc.Notify(c);
end;

{ Empty paragraphs, AParas, before paragraph APara - which keeps its text and its value: a
  paragraph of a file stays the file's own (the separators go in at its start, where no piece
  of its text is split, and its value goes with its text). One insert's record; its revert
  deletes the separators and gives the paragraph its value back. }
function TTyRichTableEditor.InsertParas(APara: Integer;
  const AParas: array of TTyRichNewPara): TTyRichUndoData;
var
  c: TTyRichChange;
  n, i: Integer;
  p, before: TTyRichPos;
  d, v: TTyRichParaData;
  seps: UTF8String;
  one: TTyRunArray;
begin
  n := Length(AParas);
  p := Doc.FText.ParaStart(APara);
  d := Doc.DataOf(APara);
  seps := '';
  SetLength(seps, n);
  for i := 1 to n do seps[i] := #10;
  seps := WithBreaks(seps, Doc.FDominantLineBreak);
  c := Default(TTyRichChange);
  c.Pos := p;
  Result := Doc.NewUndo(c);
  try
    Result.FFirstPara := APara;
    Result.AddOld(d);
    Result.SealOld;
    Result.FSpan := Doc.FText.PieceSpan(p, p);
    before := Doc.FText.Length;
    Inc(Doc.FEditing);
    try
      Doc.FText.Insert(p, seps);
    finally
      Dec(Doc.FEditing);
    end;
    Result.FInserted := Doc.FText.Length - before;
    // the storage left d with the first part, the first new paragraph: it goes with its text
    Doc.PutData(APara + n, nil, d);
    for i := 0 to n - 1 do
    begin
      one := nil;
      SetLength(one, 1);
      one[0].Start := 0;
      one[0].Format := AParas[i].CharFormat;
      one[0].Obj := nil;
      v := Doc.MakeData(AParas[i].ParaFormat, one, AParas[i].Cell);
      if i = 0 then Doc.PutData(APara, d, v) else Doc.PutData(APara + i, nil, v);
    end;
  except
    Doc.Revert(Result);
    raise;
  end;
  c.Kinds := [rckText, rckStructure];
  c.NewLen := Result.FInserted;
  c.FirstPara := APara;
  c.OldParaCount := 1;
  c.NewParaCount := 1 + n;
  Result.FChange := c;
  Doc.Notify(c);
end;

// Whole paragraphs AFirst .. ALast go; a paragraph follows them (the editor sees to that).
function TTyRichTableEditor.DeleteParas(AFirst, ALast: Integer): TTyRichUndoData;
var
  s: TTyRichPos;
begin
  s := Doc.FText.ParaStart(AFirst);
  Result := Doc.DeleteRange(s, Doc.FText.ParaStart(ALast + 1) - s);
end;

// AFormat in no list and with no indents.
function TTyRichTableEditor.Unlisted(AFormat: TTyParaFormatId): TTyParaFormatId;
var
  pf: TTyParaFormat;
begin
  pf := Doc.FFormats.ParaFormat(AFormat);
  pf.List := TyDefaultParaFormat.List;
  pf.LeftIndent := 0;
  pf.RightIndent := 0;
  pf.FirstIndent := 0;
  Result := Doc.FFormats.InternPara(pf);
end;

// The formats of paragraph APara, for an empty paragraph made like it.
function TTyRichTableEditor.FormatOf(APara: Integer): TTyRichNewPara;
begin
  Result.Cell := nil;
  Result.ParaFormat := Doc.ParaFormatOf(APara);
  Result.CharFormat := Doc.TypingFormatAt(Doc.FText.ParaStart(APara));
end;

procedure TTyRichTableEditor.AddOp(AAnchor, ALast: Integer; AInsert: Boolean;
  const AParas: TTyRichNewParas);
begin
  if OpCount = Length(Ops) then SetLength(Ops, OpCount * 2 + 8);
  Ops[OpCount].Anchor := AAnchor;
  Ops[OpCount].Last := ALast;
  Ops[OpCount].Insert := AInsert;
  Ops[OpCount].Paras := AParas;
  Inc(OpCount);
end;

procedure TTyRichTableEditor.Pend(const APara: TTyRichNewPara);
begin
  if PendingCount = Length(Pending) then SetLength(Pending, PendingCount * 2 + 4);
  Pending[PendingCount] := APara;
  Inc(PendingCount);
end;

// The new paragraphs met since the last paragraph that stays go in before AAnchor.
procedure TTyRichTableEditor.Flush(AAnchor: Integer);
begin
  if PendingCount = 0 then Exit;
  AddOp(AAnchor, -1, True, Copy(Pending, 0, PendingCount));
  PendingCount := 0;
end;

{ The rows of an edit of rows: the shape's rows, each again with its own format, cells and
  edges, a new one put in (the row beside it again) or one left out. }
{ Every cell's words with Word's preferred width (in twips) the width its edges now give. }
procedure FitPreferredWidths(var ACells: TTyRtfCellWords; const AEdges: array of Integer; ALeft: Integer);
var
  i, l: Integer;
begin
  for i := 0 to High(ACells) do
  begin
    if i > High(AEdges) then Break;
    if i = 0 then l := ALeft else l := AEdges[i - 1];
    ACells[i] := TyRichCellWordsWidth(ACells[i], AEdges[i] - l);
  end;
end;

{ ARow's format for a row put in above ABelow (nil: none below): each cell's merge down - it
  continues one where ABelow's cell there continues one, else none. nil: nothing to change
  (no cell of ARow is merged down). Pooled, one reference for the caller. }
function MergedDownInto(ARow, ABelow: TTyRichRow): TTyRichRowFormat;
var
  f, c: TTyRichRowFormat;
  i, o: Integer;
  e, be: TTyRichEdges;
  any: Boolean;
begin
  Result := nil;
  f := ARow.Format;
  any := False;
  for i := 0 to f.CellCount - 1 do
    if f.Cells[i].VMerge <> rcmNone then any := True;
  if not any then Exit;
  c := f.Clone;
  e := ARow.CellEdges;
  if ABelow <> nil then be := ABelow.CellEdges else be := nil;
  for i := 0 to c.CellCount - 1 do
  begin
    o := -1;
    if ABelow <> nil then
      o := TyRichFacingCell(e, f.Row.LeftTwips, i, be, ABelow.Format.Row.LeftTwips);
    if (o >= 0) and (o < ABelow.Format.CellCount) and (ABelow.Format.Cells[o].VMerge = rcmContinue) then
      c.Cells[i].VMerge := rcmContinue
    else
      c.Cells[i].VMerge := rcmNone;
  end;
  Result := TyRichInternRowFormat(c);
end;

function TyRichCellHMergeOf(R: TTyRichRow; AI: Integer): Integer;
begin
  if (AI < 0) or (AI >= R.Format.CellCount) then Exit(0);
  Result := Ord(R.Format.Cells[AI].HMerge);
end;

// cell AI of row A: the cell of row B with its edges (-1: none)
function FacingIn(A: TTyRichRow; AI: Integer; B: TTyRichRow): Integer;
begin
  Result := -1;
  if (A = nil) or (B = nil) then Exit;
  Result := TyRichFacingCell(A.CellEdges, A.Format.Row.LeftTwips, AI, B.CellEdges, B.Format.Row.LeftTwips);
  if Result >= B.Format.CellCount then Result := -1;
end;

function VMergeOf(R: TTyRichRow; AI: Integer): TTyRowCellMerge;
begin
  if (R = nil) or (AI < 0) or (AI >= R.Format.CellCount) then Exit(rcmNone);
  Result := R.Format.Cells[AI].VMerge;
end;

procedure TTyRichTableEditor.PlanRows;
var
  n, r, k, b, ci: Integer;
  src: TTyRichShapeRow;
  para: Integer;
  fmt: TTyRichRowFormat;

  { Row ARow of the shape (its plan row) with the merge down of cell AI made AMerge: the row
    is made again (its format a new one). }
  procedure SetMerge(ARow, AI: Integer; AMerge: TTyRowCellMerge);
  var
    pr: Integer;
    c: TTyRichRowFormat;
  begin
    for pr := 0 to High(Plan) do
      if Plan[pr].Shape = ARow then
      begin
        if Plan[pr].Format = nil then Plan[pr].Format := Self.Shape.Rows[ARow].Row.Format;
        if Plan[pr].Format.Cells[AI].VMerge = AMerge then Exit;
        c := Plan[pr].Format.Clone;
        c.Cells[AI].VMerge := AMerge;
        Plan[pr].Format := Hold(TyRichInternRowFormat(c));
        Plan[pr].Same := False;
        Exit;
      end;
  end;

  { A row deleted (RowAt): a merge down that began in the row above and ended in it is one
    cell again; one that began in it and goes on begins in the row below (its content moved
    there first: DeleteRowRefusal), and is one cell when it ends there. }
  procedure SpansAroundTheDeleted;
  var
    d, i, o, o2: Integer;
    ra, rd, rb, rbb: TTyRichRow;
  begin
    d := RowAt;
    rd := Self.Shape.Rows[d].Row;
    if d > 0 then ra := Self.Shape.Rows[d - 1].Row else ra := nil;
    if d + 1 < Self.Shape.RowCount then rb := Self.Shape.Rows[d + 1].Row else rb := nil;
    if d + 2 < Self.Shape.RowCount then rbb := Self.Shape.Rows[d + 2].Row else rbb := nil;
    if ra <> nil then
      for i := 0 to ra.Format.CellCount - 1 do
        if VMergeOf(ra, i) = rcmFirst then
        begin
          o := FacingIn(ra, i, rd);
          if VMergeOf(rd, o) <> rcmContinue then Continue;
          o2 := FacingIn(ra, i, rb);
          if VMergeOf(rb, o2) <> rcmContinue then SetMerge(d - 1, i, rcmNone);
        end;
    if rb <> nil then
      for i := 0 to rb.Format.CellCount - 1 do
        if VMergeOf(rb, i) = rcmContinue then
        begin
          o := FacingIn(rb, i, rd);
          if VMergeOf(rd, o) <> rcmFirst then Continue;
          o2 := FacingIn(rb, i, rbb);
          if VMergeOf(rbb, o2) = rcmContinue then SetMerge(d + 1, i, rcmFirst)
          else SetMerge(d + 1, i, rcmNone);
        end;
  end;

begin
  Plan := nil;
  n := 0;
  SetLength(Plan, Shape.RowCount + 1);
  for r := 0 to Shape.RowCount do
  begin
    if (Edit.Kind = rtkInsertRow) and (r = RowAt) then
    begin
      // the row above, or for the first the row below
      if r > 0 then b := r - 1 else b := 0;
      src := Shape.Rows[b];
      with Plan[n] do
      begin
        Shape := -1;
        Same := False;
        // (the numbers taken out are no property: the look is the row's)
        Base := src.Row.BaseFormat;
        Format := src.Row.Format;
        // (Word numbers its rows in their formats: the new one is no copy of that number)
        Raw := TyRtfRowFormatUnnumbered(src.Row.FRawFormat);
        { A merge down: the new row's cell continues it where the row below continues one
          (the new row is inside it), else it is a cell of its own. }
        if r < Self.Shape.RowCount then fmt := MergedDownInto(src.Row, Self.Shape.Rows[r].Row)
        else fmt := MergedDownInto(src.Row, nil);
        if fmt <> nil then Format := Hold(fmt);
        Edges := Copy(src.Row.FBoundaries);
        Nested := False;
        SetLength(CellFrom, Length(src.Cells));
        SetLength(NewFormat, Length(src.Cells));
        for ci := 0 to High(src.Cells) do
        begin
          CellFrom[ci] := -1;
          para := src.Cells[ci].First;
          if para < 0 then para := src.First;
          NewFormat[ci] := FormatOf(para);
        end;
      end;
      Inc(n);
    end;
    if r = Shape.RowCount then Break;
    if (Edit.Kind = rtkDeleteRow) and (r = RowAt) then Continue;
    src := Shape.Rows[r];
    with Plan[n] do
    begin
      Shape := r;
      Same := True;
      Base := src.Row.BaseFormat;
      Format := src.Row.Format;
      Raw := src.Row.FRawFormat;
      Edges := Copy(src.Row.FBoundaries);
      Nested := src.Row.FHoldsNestedTable;
      SetLength(CellFrom, Length(src.Cells));
      SetLength(NewFormat, Length(src.Cells));
      for k := 0 to High(src.Cells) do
      begin
        CellFrom[k] := k;
        NewFormat[k] := FormatOf(src.First);
      end;
    end;
    Inc(n);
  end;
  SetLength(Plan, n);
  if (Edit.Kind = rtkDeleteRow) and (RowAt >= 0) and (RowAt < Shape.RowCount) then
    SpansAroundTheDeleted;
end;

{ The rows of an edit of columns: every row with a cell more or less, the edges after it
  moved by its width, the format's words kept with their cells. }
procedure TTyRichTableEditor.PlanColumns;
var
  fmt: TTyRichRowFormat;
  r, i, j, b, n, w, left, para: Integer;
  src: TTyRichShapeRow;
  oldEdges, newEdges: TTyIntArray;
  rowWords, tail: RawByteString;
  cells, newCells: TTyRtfCellWords;
  split: Boolean;
  perm: array of Integer;
  joined: Boolean;
begin
  Plan := nil;
  if (Edit.Kind = rtkDeleteColumn) and (Length(Shape.Rows[0].Cells) = 1) then
    Exit;   // the only column: the table goes
  SetLength(Plan, Shape.RowCount);
  j := Edit.Index;
  for r := 0 to Shape.RowCount - 1 do
  begin
    src := Shape.Rows[r];
    n := Length(src.Cells);
    oldEdges := src.Row.CellEdges;
    // where the row's first cell starts (what its bytes say, or an edit set)
    left := src.Row.Format.Row.LeftTwips;
    newEdges := nil;
    with Plan[r] do
    begin
      Shape := r;
      Same := False;
      Nested := src.Row.FHoldsNestedTable;
      if Edit.Kind = rtkInsertColumn then
      begin
        // the cell beside it: the one left of it, for the first the one right of it
        if j > 0 then b := j - 1 else b := 0;
        if b > 0 then w := oldEdges[b] - oldEdges[b - 1] else w := oldEdges[0] - left;
        SetLength(newEdges, n + 1);
        SetLength(CellFrom, n + 1);
        SetLength(NewFormat, n + 1);
        for i := 0 to n do
        begin
          if i < j then
          begin
            newEdges[i] := oldEdges[i];
            CellFrom[i] := i;
          end
          else if i = j then
          begin
            if j > 0 then newEdges[i] := oldEdges[j - 1] + w else newEdges[i] := left + w;
            CellFrom[i] := -1;
          end
          else
          begin
            newEdges[i] := oldEdges[i - 1] + w;
            CellFrom[i] := i - 1;
          end;
          para := src.First;
          if CellFrom[i] < 0 then
          begin
            para := src.Cells[b].First;
            if para < 0 then para := src.First;
          end;
          NewFormat[i] := FormatOf(para);
        end;
      end
      else
      begin
        if j > 0 then w := oldEdges[j] - oldEdges[j - 1] else w := oldEdges[0] - left;
        SetLength(newEdges, n - 1);
        SetLength(CellFrom, n - 1);
        SetLength(NewFormat, n - 1);
        for i := 0 to n - 2 do
        begin
          if i < j then
          begin
            newEdges[i] := oldEdges[i];
            CellFrom[i] := i;
          end
          else
          begin
            newEdges[i] := oldEdges[i + 1] - w;
            CellFrom[i] := i + 1;
          end;
          NewFormat[i] := FormatOf(src.First);
        end;
      end;
      Edges := newEdges;
      // the format: each cell's words with the cell, the row's with the row
      Raw := '';
      joined := False;
      if SameBytes(src.Row.FRawFormat, TyRtfGridRowFormat(oldEdges)) then
        // a grid made here: made again for the new edges (its gap follows the narrowest cell)
        Raw := TyRtfGridRowFormat(newEdges)
      else if src.Row.FRawFormat <> '' then
      begin
        split := TyRtfSplitRowFormat(src.Row.FRawFormat, n, rowWords, cells, tail);
        if split then
        begin
          newCells := nil;
          SetLength(newCells, Length(CellFrom));
          for i := 0 to High(CellFrom) do
            if CellFrom[i] >= 0 then newCells[i] := cells[CellFrom[i]]
            else newCells[i] := cells[b];
          FitPreferredWidths(newCells, newEdges, left);
          rowWords := TyRichRowWordsWidth(rowWords, newEdges[High(newEdges)] - left);
          Raw := TyRtfJoinRowFormat(rowWords, newCells, newEdges, tail);
          joined := True;
        end
        else
          Raw := TyRtfGridRowFormat(newEdges);
      end;
      { The look goes with the cells as their words do: a cell's that stays, the one beside
        a new one. What the new bytes say is the same taken of the old ones - when they were
        put together of the old ones' words; else read of the new bytes (no file colour in
        them). }
      perm := nil;
      SetLength(perm, Length(CellFrom));
      for i := 0 to High(CellFrom) do
        if CellFrom[i] >= 0 then perm[i] := CellFrom[i] else perm[i] := b;
      Format := Hold(src.Row.Format.Permuted(perm));
      // (a new cell merges with nothing)
      for i := 0 to High(CellFrom) do
        if (CellFrom[i] < 0) and ((Format.Cells[i].HMerge <> rcmNone) or (Format.Cells[i].VMerge <> rcmNone)) then
        begin
          fmt := Format.Clone;
          fmt.Cells[i].HMerge := rcmNone;
          fmt.Cells[i].VMerge := rcmNone;
          Format := Hold(TyRichInternRowFormat(fmt));
        end;
      if joined then Base := Hold(src.Row.BaseFormat.Permuted(perm))
      else Base := Hold(TyRichDecodeRowFormat(Raw, Length(CellFrom), []));
    end;
  end;
end;

function MergeRun(ARow: TTyRichRow; AX0, AX1: Integer; out AFirst, ALast: Integer): Boolean; forward;

function CellAtExtent(ARow: TTyRichRow; ALeft, ARight: Integer): Integer; forward;

{ The rows of the merge: in rows Row0 .. Row1 the cells meeting X0 .. X1 become the first of
  them, as wide as they were (its right edge the last one's); the first row's begins a
  vertical merge and the others' continue it (one row: none). The merged cell looks as the
  top-left cell did - its shading, padding and alignment - and its outline keeps the lines
  that were on the rectangle's outline: in each row its left from the first of the cells,
  its right from the last; the top from the top-left cell, the bottom from the bottom-left
  one (the neighbours' facing sides agreed with those, and still do). The other rows stay as
  they are. }
procedure TTyRichTableEditor.PlanMerge;
var
  r, n, i, i0, i1, d, rr0, rr1, t0, t1: Integer;
  src: TTyRichShapeRow;
  oldEdges, newEdges: TTyIntArray;
  rowWords, tail: RawByteString;
  cells, newCells: TTyRtfCellWords;
  joined: Boolean;
  perm: array of Integer;
  p, c: TTyRichRowFormat;
  tl, me: TTyRichCellFormat;
  top, bottom: TTyRichBorder;
begin
  SetLength(Plan, Shape.RowCount);
  rr0 := Edit.Row0 - Shape.Base;
  rr1 := Edit.Row1 - Shape.Base;
  // the top-left cell's look, the top-left's top and the bottom-left's bottom
  tl := Default(TTyRichCellFormat);
  top := TyRichBorder(rbsNone, 0);
  bottom := top;
  if MergeRun(Shape.Rows[rr0].Row, Edit.X0, Edit.X1, t0, t1) then
  begin
    tl := Shape.Rows[rr0].Row.Format.Cells[t0];
    top := tl.Props.Borders[rcsTop];
  end;
  for r := rr1 downto rr0 do
    if MergeRun(Shape.Rows[r].Row, Edit.X0, Edit.X1, t0, t1) then
    begin
      bottom := Shape.Rows[r].Row.Format.Cells[t0].Props.Borders[rcsBottom];
      Break;
    end;
  for r := 0 to Shape.RowCount - 1 do
  begin
    src := Shape.Rows[r];
    n := Length(src.Cells);
    oldEdges := src.Row.CellEdges;
    with Plan[r] do
    begin
      Shape := r;
      Nested := src.Row.FHoldsNestedTable;
      if (r < rr0) or (r > rr1) or not MergeRun(src.Row, Edit.X0, Edit.X1, i0, i1) then
      begin
        // a row the merge does not touch: as it is
        Same := True;
        Edges := Copy(oldEdges);
        SetLength(CellFrom, n);
        SetLength(NewFormat, n);
        for i := 0 to n - 1 do
        begin
          CellFrom[i] := i;
          NewFormat[i] := FormatOf(src.First);
        end;
        Raw := src.Row.FRawFormat;
        Continue;
      end;
      Same := False;
      d := i1 - i0;
      SetLength(newEdges, n - d);
      SetLength(CellFrom, n - d);
      SetLength(NewFormat, n - d);
      for i := 0 to n - d - 1 do
      begin
        Inc(Doc.FTableEditSteps);
        if i < i0 then CellFrom[i] := i
        else if i = i0 then CellFrom[i] := i0
        else CellFrom[i] := i + d;
        if i = i0 then newEdges[i] := oldEdges[i1] else newEdges[i] := oldEdges[CellFrom[i]];
        NewFormat[i] := FormatOf(src.First);
      end;
      Edges := newEdges;
      Raw := '';
      joined := False;
      if SameBytes(src.Row.FRawFormat, TyRtfGridRowFormat(oldEdges)) then
        Raw := TyRtfGridRowFormat(newEdges)
      else if src.Row.FRawFormat <> '' then
      begin
        if TyRtfSplitRowFormat(src.Row.FRawFormat, n, rowWords, cells, tail) then
        begin
          newCells := nil;
          SetLength(newCells, Length(CellFrom));
          for i := 0 to High(CellFrom) do newCells[i] := cells[CellFrom[i]];
          FitPreferredWidths(newCells, newEdges, src.Row.Format.Row.LeftTwips);
          Raw := TyRtfJoinRowFormat(rowWords, newCells, newEdges, tail);
          joined := True;
        end
        else
          Raw := TyRtfGridRowFormat(newEdges);
      end;
      perm := nil;
      SetLength(perm, Length(CellFrom));
      for i := 0 to High(CellFrom) do perm[i] := CellFrom[i];
      // the merged cell: the top-left's look, the outline's lines, the merge
      p := src.Row.Format.Permuted(perm);
      c := p.Clone;
      p.Release;
      me := tl;
      me.Props.Borders[rcsLeft] := src.Row.Format.Cells[i0].Props.Borders[rcsLeft];
      me.Props.Borders[rcsRight] := src.Row.Format.Cells[i1].Props.Borders[rcsRight];
      if r = rr0 then me.Props.Borders[rcsTop] := top
      else me.Props.Borders[rcsTop] := src.Row.Format.Cells[i0].Props.Borders[rcsTop];
      if r = rr1 then me.Props.Borders[rcsBottom] := bottom
      else me.Props.Borders[rcsBottom] := src.Row.Format.Cells[i0].Props.Borders[rcsBottom];
      me.HMerge := rcmNone;
      if rr1 = rr0 then me.VMerge := rcmNone
      else if r = rr0 then me.VMerge := rcmFirst
      else me.VMerge := rcmContinue;
      c.Cells[i0] := me;
      Format := Hold(TyRichInternRowFormat(c));
      if joined then Base := Hold(src.Row.BaseFormat.Permuted(perm))
      else Base := Hold(TyRichDecodeRowFormat(Raw, Length(CellFrom), []));
    end;
  end;
end;

{ The rows of the split (TTyRichTableEdit.SplitEdges says what it does): in each row of the
  cell's span its cell there is Cols cells; the vertical merge in parts of SpanRows div Rows
  rows; for one row, Rows - 1 rows after it whose other cells continue the row's. }
procedure TTyRichTableEditor.PlanSplit;
var
  r, n, i, j, k, m, d, q, partRows, add, pr, r0, l, rt, a: Integer;
  src: TTyRichShapeRow;
  oldEdges, newEdges, firstEdges: TTyIntArray;
  rowWords, tail, firstRaw: RawByteString;
  cells, newCells: TTyRtfCellWords;
  joined: Boolean;
  perm: array of Integer;
  isNew: array of Boolean;
  p, c, firstFmt: TTyRichRowFormat;
  cf, nf: TTyRichCellFormat;
  firstNew: TTyRichNewParas;

  // cell m of the k a cell was split into, from its format cf
  function Part(const ACell: TTyRichCellFormat; AM, AQ: Integer): TTyRichCellFormat;
  begin
    Result := ACell;
    Result.HMerge := rcmNone;
    if AM > 0 then Result.Props.Borders[rcsLeft] := ACell.Props.Borders[rcsLeft];
    if AM < k - 1 then Result.Props.Borders[rcsRight] := ACell.Props.Borders[rcsLeft];
    if partRows > 1 then
    begin
      if AQ mod partRows = 0 then Result.VMerge := rcmFirst else Result.VMerge := rcmContinue;
      // between the parts: the cell's top
      if (AQ mod partRows = 0) and (AQ > 0) then Result.Props.Borders[rcsTop] := ACell.Props.Borders[rcsTop];
      if ((AQ + 1) mod partRows = 0) and (AQ + 1 < Edit.SpanRows) then
        Result.Props.Borders[rcsBottom] := ACell.Props.Borders[rcsTop];
    end
    else
    begin
      Result.VMerge := rcmNone;
      if AQ > 0 then Result.Props.Borders[rcsTop] := ACell.Props.Borders[rcsTop];
      if AQ + 1 < Edit.SpanRows then Result.Props.Borders[rcsBottom] := ACell.Props.Borders[rcsTop];
    end;
  end;

begin
  r0 := Edit.Row0 - Shape.Base;
  if Edit.SpanRows > 1 then
  begin
    partRows := Edit.SpanRows div Edit.Rows;
    add := 0;
  end
  else
  begin
    partRows := 1;
    add := Edit.Rows - 1;
  end;
  k := Length(Edit.SplitEdges) + 1;
  src := Shape.Rows[r0];
  oldEdges := src.Row.CellEdges;
  if Edit.Index = 0 then l := src.Row.Format.Row.LeftTwips else l := oldEdges[Edit.Index - 1];
  rt := oldEdges[Edit.Index];
  SetLength(Plan, Shape.RowCount + add);
  pr := 0;
  firstFmt := nil;
  for r := 0 to Shape.RowCount - 1 do
  begin
    src := Shape.Rows[r];
    n := Length(src.Cells);
    oldEdges := src.Row.CellEdges;
    q := r - r0;
    if (q >= 0) and (q < Edit.SpanRows) then j := CellAtExtent(src.Row, l, rt) else j := -1;
    with Plan[pr] do
    begin
      Shape := r;
      Nested := src.Row.FHoldsNestedTable;
      if j < 0 then
      begin
        Same := True;
        Edges := Copy(oldEdges);
        SetLength(CellFrom, n);
        SetLength(NewFormat, n);
        for i := 0 to n - 1 do
        begin
          CellFrom[i] := i;
          NewFormat[i] := FormatOf(src.First);
        end;
        Raw := src.Row.FRawFormat;
        Inc(pr);
        Continue;
      end;
      Same := False;
      d := k - 1;
      SetLength(newEdges, n + d);
      SetLength(CellFrom, n + d);
      SetLength(NewFormat, n + d);
      isNew := nil;
      SetLength(isNew, n + d);
      for i := 0 to n + d - 1 do
      begin
        Inc(Doc.FTableEditSteps);
        if i < j then
        begin
          CellFrom[i] := i;
          newEdges[i] := oldEdges[i];
        end
        else if i <= j + d then
        begin
          if i = j then CellFrom[i] := j else CellFrom[i] := -1;
          isNew[i] := i > j;
          if i < j + d then newEdges[i] := Edit.SplitEdges[i - j] else newEdges[i] := oldEdges[j];
        end
        else
        begin
          CellFrom[i] := i - d;
          newEdges[i] := oldEdges[i - d];
        end;
        if (i >= j) and (i <= j + d) and (src.Cells[j].First >= 0) then
          NewFormat[i] := FormatOf(src.Cells[j].First)
        else
          NewFormat[i] := FormatOf(src.First);
      end;
      Edges := newEdges;
      Raw := '';
      joined := False;
      if SameBytes(src.Row.FRawFormat, TyRtfGridRowFormat(oldEdges)) then
        Raw := TyRtfGridRowFormat(newEdges)
      else if src.Row.FRawFormat <> '' then
      begin
        if TyRtfSplitRowFormat(src.Row.FRawFormat, n, rowWords, cells, tail) then
        begin
          newCells := nil;
          SetLength(newCells, Length(CellFrom));
          for i := 0 to High(CellFrom) do
            if CellFrom[i] >= 0 then newCells[i] := cells[CellFrom[i]] else newCells[i] := cells[j];
          FitPreferredWidths(newCells, newEdges, src.Row.Format.Row.LeftTwips);
          Raw := TyRtfJoinRowFormat(rowWords, newCells, newEdges, tail);
          joined := True;
        end
        else
          Raw := TyRtfGridRowFormat(newEdges);
      end;
      perm := nil;
      SetLength(perm, Length(CellFrom));
      for i := 0 to High(CellFrom) do
        if CellFrom[i] >= 0 then perm[i] := CellFrom[i] else perm[i] := j;
      p := src.Row.Format.Permuted(perm);
      c := p.Clone;
      p.Release;
      cf := src.Row.Format.Cells[j];
      // (the span's look is its first row's)
      if q > 0 then cf.Props := Self.Shape.Rows[r0].Row.Format.Cells[Edit.Index].Props;
      for m := 0 to d do c.Cells[j + m] := Part(cf, m, q);
      // one row split down: its other cells reach over the rows that come
      if add > 0 then
        for i := 0 to High(c.Cells) do
          if ((i < j) or (i > j + d)) and (c.Cells[i].VMerge = rcmNone) then
            c.Cells[i].VMerge := rcmFirst;
      Format := Hold(TyRichInternRowFormat(c));
      if joined then Base := Hold(src.Row.BaseFormat.Permuted(perm))
      else Base := Hold(TyRichDecodeRowFormat(Raw, Length(CellFrom), []));
      if (add > 0) and (q = 0) then
      begin
        firstEdges := Edges;
        firstRaw := Raw;
        firstNew := Copy(NewFormat);
        firstFmt := Format;
      end;
    end;
    Inc(pr);
    // the rows that come below a row split down
    if (add > 0) and (q = 0) then
      for a := 1 to add do
      begin
        with Plan[pr] do
        begin
          Shape := -1;
          Same := False;
          Nested := False;
          Edges := Copy(firstEdges);
          Raw := firstRaw;
          SetLength(CellFrom, Length(firstEdges));
          for i := 0 to High(CellFrom) do CellFrom[i] := -1;
          NewFormat := Copy(firstNew);
          c := firstFmt.Clone;
          for i := 0 to High(c.Cells) do
            if (i >= j) and (i <= j + k - 1) then
            begin
              nf := Part(firstFmt.Cells[i], i - j, a);
              // (the split cell's own rows: no merge down)
              nf.VMerge := rcmNone;
              nf.Props.Borders[rcsTop] := firstFmt.Cells[i].Props.Borders[rcsTop];
              c.Cells[i] := nf;
            end
            else
              c.Cells[i].VMerge := rcmContinue;
          Format := Hold(TyRichInternRowFormat(c));
          Base := Hold(TyRichDecodeRowFormat(Raw, Length(CellFrom), []));
        end;
        Inc(pr);
      end;
  end;
  SetLength(Plan, pr);
end;

{ The rows of a column by the grid (TTyRichTableEdit says what each does). The words of a cell
  go with it (a new one takes those of the cell beside it), Word's preferred widths follow the
  new edges; a merge across that loses its first cell begins at the next. }
procedure TTyRichTableEditor.PlanGridColumns;
var
  r, n, i, j, k, b, left, w, x, a, bb, d, nn: Integer;
  src: TTyRichShapeRow;
  oldEdges, newEdges: TTyIntArray;
  rowWords, tail: RawByteString;
  cells, newCells: TTyRtfCellWords;
  joined: Boolean;
  perm: array of Integer;
  p, c: TTyRichRowFormat;
  changed, isNew: Boolean;
  newAt: Integer;

  function Map(AX: Integer): Integer;
  begin
    if AX <= a then Result := AX
    else if AX >= bb then Result := AX - d
    else Result := a;
  end;

begin
  SetLength(Plan, Shape.RowCount);
  x := Edit.X0;
  w := Edit.Width;
  a := Edit.X0;
  bb := Edit.X1;
  d := bb - a;
  for r := 0 to Shape.RowCount - 1 do
  begin
    src := Shape.Rows[r];
    n := Length(src.Cells);
    oldEdges := src.Row.CellEdges;
    left := src.Row.Format.Row.LeftTwips;
    newEdges := nil;
    changed := False;
    newAt := -1;
    b := 0;
    with Plan[r] do
    begin
      Shape := r;
      Nested := src.Row.FHoldsNestedTable;
      CellFrom := nil;
      if Edit.Kind = rtkInsertGridColumn then
      begin
        // where X0 falls: the row's left, an edge (after cell k), or inside cell k
        k := -2;
        if Abs(x - left) <= CRichSharedEdgeTwips then k := -1
        else
          for i := 0 to n - 1 do
          begin
            if i = 0 then j := left else j := oldEdges[i - 1];
            if Abs(oldEdges[i] - x) <= CRichSharedEdgeTwips then
            begin
              k := i;
              // (between the cells of a merge across: inside it)
              if (i + 1 < n) and (TyRichCellHMergeOf(src.Row, i + 1) = Ord(rcmContinue)) then k := -3 - i;
              Break;
            end;
            if (j < x) and (x < oldEdges[i]) then
            begin
              k := -3 - i;
              Break;
            end;
          end;
        if k = -2 then
        begin
          // (past the row's end: the row as it is)
          SetLength(newEdges, n);
          SetLength(CellFrom, n);
          for i := 0 to n - 1 do
          begin
            newEdges[i] := oldEdges[i];
            CellFrom[i] := i;
          end;
        end
        else if k <= -3 then
        begin
          // inside cell -3 - k: it grows, the edges after it move
          j := -3 - k;
          SetLength(newEdges, n);
          SetLength(CellFrom, n);
          for i := 0 to n - 1 do
          begin
            CellFrom[i] := i;
            if i >= j then newEdges[i] := oldEdges[i] + w else newEdges[i] := oldEdges[i];
          end;
          changed := True;
        end
        else
        begin
          // a new cell after cell k (-1: before the first)
          newAt := k + 1;
          if k >= 0 then b := k else b := 0;
          SetLength(newEdges, n + 1);
          SetLength(CellFrom, n + 1);
          for i := 0 to n do
          begin
            if i < newAt then
            begin
              CellFrom[i] := i;
              newEdges[i] := oldEdges[i];
            end
            else if i = newAt then
            begin
              CellFrom[i] := -1;
              if newAt > 0 then newEdges[i] := oldEdges[newAt - 1] + w else newEdges[i] := left + w;
            end
            else
            begin
              CellFrom[i] := i - 1;
              newEdges[i] := oldEdges[i - 1] + w;
            end;
          end;
          changed := True;
        end;
      end
      else
      begin
        // the columns X0 .. X1 out: a cell wholly inside goes, the others shrink or move
        nn := 0;
        SetLength(newEdges, n);
        SetLength(CellFrom, n);
        for i := 0 to n - 1 do
        begin
          if i = 0 then j := left else j := oldEdges[i - 1];
          if (j >= a - CRichSharedEdgeTwips) and (oldEdges[i] <= bb + CRichSharedEdgeTwips) and
             (oldEdges[i] > j) then
          begin
            changed := True;
            Continue;
          end;
          CellFrom[nn] := i;
          newEdges[nn] := Map(oldEdges[i]);
          if newEdges[nn] <> oldEdges[i] then changed := True;
          Inc(nn);
        end;
        SetLength(newEdges, nn);
        SetLength(CellFrom, nn);
      end;
      Edges := newEdges;
      SetLength(NewFormat, Length(CellFrom));
      for i := 0 to High(CellFrom) do
      begin
        Inc(Doc.FTableEditSteps);
        if (CellFrom[i] < 0) and (src.Cells[b].First >= 0) then NewFormat[i] := FormatOf(src.Cells[b].First)
        else NewFormat[i] := FormatOf(src.First);
      end;
      if not changed then
      begin
        Same := True;
        Raw := src.Row.FRawFormat;
        Continue;
      end;
      Same := False;
      Raw := '';
      joined := False;
      if SameBytes(src.Row.FRawFormat, TyRtfGridRowFormat(oldEdges)) then
        Raw := TyRtfGridRowFormat(newEdges)
      else if src.Row.FRawFormat <> '' then
      begin
        if TyRtfSplitRowFormat(src.Row.FRawFormat, n, rowWords, cells, tail) then
        begin
          newCells := nil;
          SetLength(newCells, Length(CellFrom));
          for i := 0 to High(CellFrom) do
            if CellFrom[i] >= 0 then newCells[i] := cells[CellFrom[i]] else newCells[i] := cells[b];
          FitPreferredWidths(newCells, newEdges, left);
          if Length(newEdges) > 0 then
            rowWords := TyRichRowWordsWidth(rowWords, newEdges[High(newEdges)] - left);
          Raw := TyRtfJoinRowFormat(rowWords, newCells, newEdges, tail);
          joined := True;
        end
        else
          Raw := TyRtfGridRowFormat(newEdges);
      end;
      perm := nil;
      SetLength(perm, Length(CellFrom));
      for i := 0 to High(CellFrom) do
        if CellFrom[i] >= 0 then perm[i] := CellFrom[i] else perm[i] := b;
      p := src.Row.Format.Permuted(perm);
      c := p.Clone;
      p.Release;
      // a new cell merges with nothing; a merge across keeps a first cell
      for i := 0 to High(CellFrom) do
        if CellFrom[i] < 0 then
        begin
          c.Cells[i].HMerge := rcmNone;
          c.Cells[i].VMerge := rcmNone;
        end;
      for i := 0 to c.CellCount - 1 do
        if c.Cells[i].HMerge = rcmContinue then
          if (i = 0) or (c.Cells[i - 1].HMerge = rcmNone) then
          begin
            if (i + 1 < c.CellCount) and (c.Cells[i + 1].HMerge = rcmContinue) then
              c.Cells[i].HMerge := rcmFirst
            else
              c.Cells[i].HMerge := rcmNone;
          end;
      for i := 0 to c.CellCount - 1 do
        if (c.Cells[i].HMerge = rcmFirst) and
           ((i + 1 >= c.CellCount) or (c.Cells[i + 1].HMerge <> rcmContinue)) then
          c.Cells[i].HMerge := rcmNone;
      Format := Hold(TyRichInternRowFormat(c));
      if joined then Base := Hold(src.Row.BaseFormat.Permuted(perm))
      else Base := Hold(TyRichDecodeRowFormat(Raw, Length(CellFrom), []));
    end;
  end;
end;

procedure TTyRichTableEditor.InsertTable(U: TTyRichUndoData);
var
  pos: TTyRichPos;
  k, anchor, r, ci, n, w, i: Integer;
  cellFormat: TTyRichNewPara;
  edges: TTyIntArray;
  raw: RawByteString;
  t: TTyRichTable;
  paras: TTyRichNewParas;
  apart: Boolean;
begin
  pos := Edit.Pos;
  k := Doc.FText.ParaOfPos(pos);
  // the cells' formats: those in effect at the place, the paragraph's without a list or indents
  cellFormat.ParaFormat := Unlisted(Doc.ParaFormatOf(k));
  cellFormat.CharFormat := Doc.TypingFormatAt(pos);
  cellFormat.Cell := nil;
  if pos > Doc.FText.ParaStart(k) then
  begin
    // inside a paragraph, or after the text at its end: split, the table between the parts
    U.AddPart(Doc.InsertText(pos, #13#10));
    anchor := k + 1;
  end
  else
    anchor := k;
  // right after another table: a paragraph in no table first, so that the two stay apart
  apart := (anchor > 0) and (Doc.CellAt(anchor - 1) <> nil);
  w := Edit.Width;
  if w <= 0 then w := Doc.TextWidthTwips;
  edges := nil;
  SetLength(edges, Edit.Cols);
  for i := 0 to Edit.Cols - 1 do edges[i] := Integer(Int64(w) * (i + 1) div Edit.Cols);
  raw := TyRtfGridRowFormat(edges);
  Plan := nil;
  SetLength(Plan, Edit.Rows);
  for r := 0 to Edit.Rows - 1 do
  begin
    Plan[r].Shape := -1;
    Plan[r].Raw := raw;
    Plan[r].Edges := edges;
    Plan[r].Nested := False;
    SetLength(Plan[r].CellFrom, Edit.Cols);
    for ci := 0 to Edit.Cols - 1 do Plan[r].CellFrom[ci] := -1;
  end;
  t := TableFor(edges);
  n := Edit.Rows * Edit.Cols;
  paras := nil;
  SetLength(paras, n + Ord(apart));
  i := 0;
  if apart then
  begin
    // (like the cells: no list item, no indents)
    paras[0] := FormatOf(anchor);
    paras[0].ParaFormat := Unlisted(paras[0].ParaFormat);
    i := 1;
  end;
  for r := 0 to Edit.Rows - 1 do
    for ci := 0 to Edit.Cols - 1 do
    begin
      paras[i] := cellFormat;
      paras[i].Cell := t.FRows[r].FCells[ci];
      Inc(i);
    end;
  U.AddPart(InsertParas(anchor, paras));
end;

procedure TTyRichTableEditor.EditShape(U: TTyRichUndoData);
var
  t: TTyRichTable;
  cells: array of TTyRichCell;
  rowOf: array of Integer;
  // per plan row: the new cell each old cell of its shape row is (-1: it goes)
  newOf: array of TTyIntArray;
  r, pr, ci, j, k, i, dels: Integer;
  colBounds: TTyIntArray;
  kinds: TTyRichChangeKinds;
  // per plan row: the row object it is
  rows: array of TTyRichRow;
  changed: Boolean;
  sp: TTyRichUndoData;
begin
  // (Shape: read by the refusal check, in this read scope)
  // a paragraph in no table after the table, so that whole paragraphs can go and come
  // before it (a table that ends the text is made only by code)
  if Shape.Last = Doc.FText.ParaCount - 1 then
  begin
    U.AddPart(Doc.InsertText(Doc.FText.Length, #13#10));
    U.AddPart(SetCells(Doc.FText.ParaCount - 1, [nil], [rckStructure]));
  end;
  { A table whose rows are not known (a plain delete took a row's last paragraph; the shape
    was read whole): its rows are put right first, as a step of this edit, and it is edited
    as one whose rows are known - the table read whole being the window. A part a loader cut
    is not: its parts become one table below. }
  if not Shape.Window and (Shape.RowCount > 0) then
  begin
    t := Shape.Rows[0].Row.FTable;
    changed := not t.FCut;
    for r := 0 to Shape.RowCount - 1 do
      if (Shape.Rows[r].Row.FTable <> t) or
         ((r > 0) and (Shape.Rows[r].Row.FIndex <= Shape.Rows[r - 1].Row.FIndex)) then
        changed := False;
    if changed then
    begin
      rows := nil;
      SetLength(rows, Shape.RowCount);
      for r := 0 to Shape.RowCount - 1 do rows[r] := Shape.Rows[r].Row;
      U.AddPart(Doc.SpliceRows(t, 0, Length(t.FRows), rows, True));
      Shape.Window := True;
      Shape.Base := 0;
      Shape.Table := t;
      Shape.RowIndex := Edit.Index;
    end;
  end;
  if Edit.Kind in [rtkInsertRow, rtkDeleteRow] then PlanRows
  else if Edit.Kind = rtkMergeCells then PlanMerge
  else if Edit.Kind = rtkSplitCell then PlanSplit
  else if Edit.Kind in [rtkInsertGridColumn, rtkDeleteGridColumns] then PlanGridColumns
  else PlanColumns;
  // the shape row each plan row is, and the new cell of each old one
  rowOf := nil;
  SetLength(rowOf, Shape.RowCount);
  for r := 0 to Shape.RowCount - 1 do rowOf[r] := -1;
  newOf := nil;
  SetLength(newOf, Length(Plan));
  for pr := 0 to High(Plan) do
  begin
    if Plan[pr].Shape < 0 then Continue;
    rowOf[Plan[pr].Shape] := pr;
    SetLength(newOf[pr], Length(Shape.Rows[Plan[pr].Shape].Cells));
    for ci := 0 to High(newOf[pr]) do newOf[pr][ci] := -1;
    for j := 0 to High(Plan[pr].CellFrom) do
    begin
      Inc(Doc.FTableEditSteps);
      if Plan[pr].CellFrom[j] >= 0 then newOf[pr][Plan[pr].CellFrom[j]] := j;
    end;
  end;
  t := nil;
  rows := nil;
  SetLength(rows, Length(Plan));
  if Shape.Window then
  begin
    { A table whose rows are known stays the object it is: a row the edit leaves as it is
      stays, a new or changed one is a row of its own in it (the shape's rows are all
      there is to read). }
    t := Shape.Table;
    for pr := 0 to High(Plan) do
      if Plan[pr].Same then
        rows[pr] := Shape.Rows[Plan[pr].Shape].Row
      else
      begin
        Inc(Doc.FTableEditSteps);
        rows[pr] := NewRowIn(t, Length(Plan[pr].CellFrom), Plan[pr].Raw, Plan[pr].Edges,
          Plan[pr].Nested, Plan[pr].Base, Plan[pr].Format);
      end;
  end
  else if Length(Plan) > 0 then
  begin
    // the parts a loader gave of a table: one table made of them
    if Edit.Kind in [rtkInsertRow, rtkDeleteRow, rtkMergeCells, rtkSplitCell,
      rtkInsertGridColumn, rtkDeleteGridColumns] then
      colBounds := Copy(Shape.Rows[0].Row.FTable.FColBoundaries)
    else
      colBounds := Plan[0].Edges;
    t := TableFor(colBounds);
    for pr := 0 to High(Plan) do rows[pr] := t.FRows[pr];
  end;
  if Length(Plan) > 0 then
  begin
    // every paragraph that stays: its cell in its new row, where its row is new (an edit of
    // rows changes nothing a view shows of them, and tells nobody)
    cells := nil;
    SetLength(cells, Shape.Last - Shape.First + 1);
    changed := False;
    for r := 0 to Shape.RowCount - 1 do
      for k := Shape.Rows[r].First to Shape.Rows[r].Last do
      begin
        Inc(Doc.FTableEditSteps);
        cells[k - Shape.First] := Shape.Cells[k - Shape.First];
        pr := rowOf[r];
        if pr < 0 then Continue;
        if rows[pr] = Shape.Rows[r].Row then Continue;
        j := newOf[pr][cells[k - Shape.First].FIndex];
        if j >= 0 then
        begin
          cells[k - Shape.First] := rows[pr].FCells[j];
          changed := True;
        end;
      end;
    if Edit.Kind in [rtkInsertRow, rtkDeleteRow] then kinds := [] else kinds := [rckStructure];
    if changed then U.AddPart(SetCells(Shape.First, cells, kinds));
  end;
  // what goes, from the first place to the last
  for r := 0 to Shape.RowCount - 1 do
  begin
    pr := rowOf[r];
    if pr < 0 then
    begin
      AddOp(Shape.Rows[r].First, Shape.Rows[r].Last, False, nil);
      Continue;
    end;
    for ci := 0 to High(Shape.Rows[r].Cells) do
    begin
      Inc(Doc.FTableEditSteps);
      if (Shape.Rows[r].Cells[ci].First >= 0) and (newOf[pr][ci] < 0) then
        AddOp(Shape.Rows[r].Cells[ci].First, Shape.Rows[r].Cells[ci].Last, False, nil);
    end;
  end;
  dels := OpCount;
  // what comes, from the first place to the last: each new cell's paragraph (and a cell's that
  // had none) goes in before the next paragraph that stays, in the new table's order
  PendingCount := 0;
  for pr := 0 to High(Plan) do
    for j := 0 to High(Plan[pr].CellFrom) do
    begin
      Inc(Doc.FTableEditSteps);
      ci := Plan[pr].CellFrom[j];
      if (ci >= 0) and (Shape.Rows[Plan[pr].Shape].Cells[ci].First >= 0) then
        Flush(Shape.Rows[Plan[pr].Shape].Cells[ci].First)
      else
      begin
        Pend(Plan[pr].NewFormat[j]);
        Pending[PendingCount - 1].Cell := rows[pr].FCells[j];
      end;
    end;
  Flush(Shape.Last + 1);
  { Both lists rise; they are applied from the last place to the first, so that each op's
    paragraphs are where they were: the two merged from their ends. (No two ops have one
    place: an insert goes before a paragraph that stays, a delete starts at one that goes.) }
  i := dels - 1;
  k := OpCount - 1;
  while (i >= 0) or (k >= dels) do
  begin
    Inc(Doc.FTableEditSteps);
    if (k >= dels) and ((i < 0) or (Ops[k].Anchor > Ops[i].Anchor)) then
    begin
      U.AddPart(InsertParas(Ops[k].Anchor, Ops[k].Paras));
      Dec(k);
    end
    else
    begin
      U.AddPart(DeleteParas(Ops[i].Anchor, Ops[i].Last));
      Dec(i);
    end;
  end;
  { The table's rows as the document has them now - after the text, whose deletes of whole
    rows take the rows as unknown (an undo puts the rows back before the text, and with them
    the rows known, as a window needs them). }
  if Shape.Window then
  begin
    sp := Doc.SpliceRows(t, Shape.Base, Shape.RowCount, rows, True);
    sp.FRowsOldValid := True;
    U.AddPart(sp);
  end;
end;

function TTyRichTableEditor.Run: TTyRichUndoData;
begin
  Result := Doc.NewUndo(Default(TTyRichChange));
  Doc.BeginRead;
  try
    try
      if Edit.Kind = rtkInsertTable then InsertTable(Result) else EditShape(Result);
      Result.SealParts;
    except
      // what was done goes back before the error travels on
      Doc.Revert(Result);
      raise;
    end;
  finally
    Doc.EndRead;
  end;
end;

function TTyRichDocument.TextWidthTwips: Integer;
var
  w: Int64;
begin
  w := Int64(FPaperWidth) - FMarginLeft - FMarginRight;
  if w > High(Integer) then w := High(Integer);
  if w < 0 then w := 0;
  Result := Integer(w);
end;

function TTyRichDocument.ValueSource(AData: Pointer): Pointer;
begin
  if AData = nil then Exit(nil);
  Result := TTyRichParaData(AData).FSource;
end;

{ The cells of row ARow (a shape's) that meet AX0 .. AX1: AFirst .. ALast (False: none). }
function MergeRun(ARow: TTyRichRow; AX0, AX1: Integer; out AFirst, ALast: Integer): Boolean;
var
  e: TTyRichEdges;
  i, l: Integer;
begin
  AFirst := -1;
  ALast := -1;
  e := ARow.CellEdges;
  for i := 0 to High(e) do
  begin
    if i = 0 then l := ARow.Format.Row.LeftTwips else l := e[i - 1];
    if (e[i] > l) and (l < AX1) and (e[i] > AX0) then
    begin
      if AFirst < 0 then AFirst := i;
      ALast := i;
    end;
  end;
  Result := AFirst >= 0;
end;

{ A row whose cell begins a merge down that goes on past it (into the next row of S) and holds
  something: rtrNotEmpty - its content would go with the row (the control's DeleteRow moves it
  to the row below first, in the same step); else rtrNone. ARow counts as S.Base does. }
function DeleteRowRefusal(ADoc: TTyRichDocument; const S: TTyRichShape; ARow: Integer): TTyRichTableRefusal;
var
  d, i, o: Integer;
  rd, rb: TTyRichRow;
  c: TTyRichShapeCell;
begin
  Result := rtrNone;
  d := ARow - S.Base;
  if (d < 0) or (d + 1 >= S.RowCount) then Exit;
  rd := S.Rows[d].Row;
  rb := S.Rows[d + 1].Row;
  for i := 0 to High(S.Rows[d].Cells) do
  begin
    if (i >= rd.Format.CellCount) or (rd.Format.Cells[i].VMerge <> rcmFirst) then Continue;
    o := TyRichFacingCell(rd.CellEdges, rd.Format.Row.LeftTwips, i, rb.CellEdges, rb.Format.Row.LeftTwips);
    if (o < 0) or (o >= rb.Format.CellCount) or (rb.Format.Cells[o].VMerge <> rcmContinue) then Continue;
    c := S.Rows[d].Cells[i];
    if (c.First >= 0) and ((c.First <> c.Last) or (ADoc.FText.ParaLength(c.First) > 0)) then
      Exit(rtrNotEmpty);
  end;
end;

{ A column by the grid against S (every row): a width of a twip at least, an edge inside the
  rows' extent, no row with more cells than a table may have, no row left without a cell -
  rtrOutOfRange; else rtrNone. }
function GridColumnsRefusal(const S: TTyRichShape; const AEdit: TTyRichTableEdit): TTyRichTableRefusal;
var
  r, i, l, kept: Integer;
  e: TTyRichEdges;
  row: TTyRichRow;
begin
  Result := rtrOutOfRange;
  if AEdit.Kind = rtkInsertGridColumn then
  begin
    if AEdit.Width < 1 then Exit;
    for r := 0 to S.RowCount - 1 do
      if Length(S.Rows[r].Row.FCells) + 1 > CRichMaxTableCols then Exit;
  end
  else
  begin
    if AEdit.X1 <= AEdit.X0 then Exit;
    for r := 0 to S.RowCount - 1 do
    begin
      row := S.Rows[r].Row;
      e := row.CellEdges;
      kept := 0;
      for i := 0 to High(e) do
      begin
        if i = 0 then l := row.Format.Row.LeftTwips else l := e[i - 1];
        if not ((l >= AEdit.X0 - CRichSharedEdgeTwips) and (e[i] <= AEdit.X1 + CRichSharedEdgeTwips)) then
          Inc(kept);
      end;
      // (a row that would lose every cell: the whole table goes, not this edit)
      if kept = 0 then Exit;
    end;
  end;
  Result := rtrNone;
end;

{ A split's numbers against a table of ARowCount rows: rtrOutOfRange or rtrNone. }
function SplitArgsRefusal(const AEdit: TTyRichTableEdit; ARowCount: Integer): TTyRichTableRefusal;
var
  i: Integer;
begin
  Result := rtrOutOfRange;
  if (AEdit.Row0 < 0) or (AEdit.SpanRows < 1) or (AEdit.Row0 + AEdit.SpanRows > ARowCount) then Exit;
  if (AEdit.Cols < 1) or (AEdit.Cols > CRichMaxTableCols) or (AEdit.Rows < 1) then Exit;
  if (AEdit.Cols = 1) and (AEdit.Rows = 1) then Exit;
  if Length(AEdit.SplitEdges) <> AEdit.Cols - 1 then Exit;
  for i := 1 to High(AEdit.SplitEdges) do
    if AEdit.SplitEdges[i] <= AEdit.SplitEdges[i - 1] then Exit;
  if AEdit.SpanRows > 1 then
  begin
    if (AEdit.SpanRows mod AEdit.Rows) <> 0 then Exit;
  end
  else if ARowCount + AEdit.Rows - 1 > CRichMaxTableRows then
    Exit;
  Result := rtrNone;
end;

{ The cell of row ARow at the extent ALeft .. ARight (its edges within the slack), else -1. }
function CellAtExtent(ARow: TTyRichRow; ALeft, ARight: Integer): Integer;
var
  e: TTyRichEdges;
  i, l: Integer;
begin
  Result := -1;
  e := ARow.CellEdges;
  for i := 0 to High(e) do
  begin
    if i = 0 then l := ARow.Format.Row.LeftTwips else l := e[i - 1];
    if (Abs(l - ALeft) <= CRichSharedEdgeTwips) and (Abs(e[i] - ARight) <= CRichSharedEdgeTwips) then
      Exit(i);
  end;
end;

{ A split of S's rows (from Base on): the cell there, the edges inside it, the cells a row
  may have - rtrOutOfRange; else rtrNone. }
function SplitRefusal(const S: TTyRichShape; const AEdit: TTyRichTableEdit): TTyRichTableRefusal;
var
  r, i, l, rt, k: Integer;
  e: TTyRichEdges;
  row: TTyRichRow;
begin
  Result := rtrOutOfRange;
  r := AEdit.Row0 - S.Base;
  if (r < 0) or (r + AEdit.SpanRows > S.RowCount) then Exit;
  row := S.Rows[r].Row;
  e := row.CellEdges;
  i := AEdit.Index;
  if (i < 0) or (i > High(e)) then Exit;
  if i = 0 then l := row.Format.Row.LeftTwips else l := e[i - 1];
  rt := e[i];
  for k := 0 to High(AEdit.SplitEdges) do
    if (AEdit.SplitEdges[k] <= l) or (AEdit.SplitEdges[k] >= rt) then Exit;
  for k := r to r + AEdit.SpanRows - 1 do
  begin
    if CellAtExtent(S.Rows[k].Row, l, rt) < 0 then Exit;
    if Length(S.Rows[k].Row.FCells) - 1 + AEdit.Cols > CRichMaxTableCols then Exit;
  end;
  Result := rtrNone;
end;

{ A merge of S's rows (S holds them, from Base on): fewer than two cells - rtrOutOfRange; a cell
  that goes, or one that the merged cell comes to cover (the first of a row below the first),
  holding more than one empty paragraph - rtrNotEmpty; else rtrNone. }
function MergeRefusal(ADoc: TTyRichDocument; const S: TTyRichShape;
  const AEdit: TTyRichTableEdit): TTyRichTableRefusal;
var
  r, a, b, j, n, from: Integer;

  function Empty(const C: TTyRichShapeCell): Boolean;
  begin
    Result := (C.First < 0) or ((C.First = C.Last) and (ADoc.FText.ParaLength(C.First) = 0));
  end;

begin
  n := 0;
  Result := rtrNone;
  for r := 0 to S.RowCount - 1 do
    if (S.Base + r >= AEdit.Row0) and (S.Base + r <= AEdit.Row1) and
       MergeRun(S.Rows[r].Row, AEdit.X0, AEdit.X1, a, b) then
    begin
      Inc(n, b - a + 1);
      if S.Base + r = AEdit.Row0 then from := a + 1 else from := a;
      for j := from to b do
        if (j <= High(S.Rows[r].Cells)) and not Empty(S.Rows[r].Cells[j]) then
          Result := rtrNotEmpty;
    end;
  if n < 2 then Result := rtrOutOfRange;
end;

{ TableRefusal for a table whose rows are known (TTyRichTable.FRowsValid, no part a loader
  cut): only the rows the edit touches are read (S a window: the row an edit of rows puts
  one beside or takes, every row for a column). S.Window False and rtrNone: not such a
  table - the caller reads it whole. }
function WindowRefusal(ADoc: TTyRichDocument; const AEdit: TTyRichTableEdit; APara: Integer;
  out S: TTyRichShape): TTyRichTableRefusal;
var
  c: TTyRichCell;
  t: TTyRichTable;
  n, ik, idx, w0, w1, cells: Integer;
begin
  S := Default(TTyRichShape);
  Result := rtrNone;
  c := ADoc.CellAt(APara);
  if (c = nil) or c.FRow.FTable.FCut or not c.FRow.FTable.FRowsValid then Exit;
  t := c.FRow.FTable;
  n := Length(t.FRows);
  ik := c.FRow.FIndex;
  if (ik < 0) or (ik >= n) or (t.FRows[ik] <> c.FRow) then Exit;
  Result := TableLock(t);
  if Result <> rtrNone then
  begin
    // (refused: no row is read, but the answer is the window's)
    S.Window := True;
    Exit;
  end;
  case AEdit.Kind of
    rtkSplitCell:
      begin
        idx := AEdit.Row0;
        S.Window := True;
        Result := SplitArgsRefusal(AEdit, n);
        if Result <> rtrNone then Exit;
        w0 := AEdit.Row0;
        w1 := AEdit.Row0 + AEdit.SpanRows - 1;
      end;
    rtkMergeCells:
      begin
        idx := AEdit.Row0;
        S.Window := True;
        if (AEdit.Row0 < 0) or (AEdit.Row1 >= n) or (AEdit.Row1 < AEdit.Row0) or
           (AEdit.X1 <= AEdit.X0) then
          Exit(rtrOutOfRange);
        w0 := AEdit.Row0;
        w1 := AEdit.Row1;
      end;
    rtkInsertRow:
      begin
        if AEdit.Index = CRichRowAbove then idx := ik
        else if AEdit.Index = CRichRowBelow then idx := ik + 1
        else idx := AEdit.Index;
        S.Window := True;
        if (idx < 0) or (idx > n) then Exit(rtrOutOfRange);
        if idx > 0 then w0 := idx - 1 else w0 := 0;
        w1 := w0;
        // (the row below too, when a merge down goes on into it: past the new row, it takes it)
        if (idx < n) and RowMergedDown(t.FRows[idx]) then w1 := idx;
      end;
    rtkDeleteRow:
      begin
        idx := AEdit.Index;
        S.Window := True;
        if (idx < 0) or (idx >= n) then Exit(rtrOutOfRange);
        w0 := idx;
        w1 := idx;
        { (a merge down in it or beside it: the row above and two below - the merge the row is
          part of starts or ends again) }
        if RowMergedDown(t.FRows[idx]) or ((idx > 0) and RowMergedDown(t.FRows[idx - 1])) or
           ((idx + 1 < n) and RowMergedDown(t.FRows[idx + 1])) then
        begin
          if idx > 0 then w0 := idx - 1;
          if idx + 2 < n then w1 := idx + 2 else w1 := n - 1;
        end;
      end;
  else
    begin
      idx := AEdit.Index;
      w0 := 0;
      w1 := n - 1;
    end;
  end;
  if not ReadRowWindow(ADoc, APara, t, w0, w1, S) then
  begin
    // the paragraphs are not where its rows say: as if they were not known
    t.FRowsValid := False;
    S := Default(TTyRichShape);
    Exit(rtrNone);
  end;
  S.RowIndex := idx;
  if AEdit.Kind = rtkMergeCells then
  begin
    Result := MergeRefusal(ADoc, S, AEdit);
    if Result <> rtrNone then Exit;
  end;
  if AEdit.Kind = rtkDeleteRow then
  begin
    Result := DeleteRowRefusal(ADoc, S, idx);
    if Result <> rtrNone then Exit;
  end;
  if AEdit.Kind = rtkSplitCell then
  begin
    Result := SplitRefusal(S, AEdit);
    if Result <> rtrNone then Exit;
  end;
  if AEdit.Kind in [rtkInsertGridColumn, rtkDeleteGridColumns] then
  begin
    Result := GridColumnsRefusal(S, AEdit);
    if Result <> rtrNone then Exit;
  end;
  if AEdit.Kind in [rtkInsertColumn, rtkDeleteColumn] then
  begin
    if not S.Regular or not S.Ordered then Exit(rtrIrregularRows);
    cells := Length(S.Rows[0].Cells);
    if (idx < 0) or (idx > cells) or ((AEdit.Kind = rtkDeleteColumn) and (idx = cells)) then
      Exit(rtrOutOfRange);
    if (AEdit.Kind = rtkInsertColumn) and (cells >= CRichMaxTableCols) then Exit(rtrOutOfRange);
  end;
  if not S.Ordered then Exit(rtrIrregularRows);
end;

{ TTyRichDocument.TableEditRefusal, and for an edit of a table its shape in S (read once: the
  edit goes by it). Call it inside a read scope. }
function TableRefusal(ADoc: TTyRichDocument; const AEdit: TTyRichTableEdit;
  out S: TTyRichShape): TTyRichTableRefusal;
var
  k, n, w: Integer;
begin
  S := Default(TTyRichShape);
  if ADoc.FLoadingContent or ADoc.FIncomplete or (ADoc.FSaving > 0) then Exit(rtrReadOnly);
  if (AEdit.Pos < 0) or (AEdit.Pos > ADoc.FText.Length) then Exit(rtrOutOfRange);
  k := ADoc.FText.ParaOfPos(AEdit.Pos);
  if AEdit.Kind = rtkInsertTable then
  begin
    if (AEdit.Rows < 1) or (AEdit.Cols < 1) or (AEdit.Rows > CRichMaxTableRows) or
       (AEdit.Cols > CRichMaxTableCols) or (AEdit.Width < 0) then
      Exit(rtrOutOfRange);
    w := AEdit.Width;
    if w = 0 then w := ADoc.TextWidthTwips;
    // every column at least a twip wide
    if w < AEdit.Cols then Exit(rtrOutOfRange);
    if ADoc.CellAt(k) <> nil then Exit(rtrInTable);
    { A table never goes into a field's result. (A field in a cell is one paragraph, whole in
      it - a reader keeps any other as one object -, so the other edits take whole fields or
      none.) }
    if ADoc.FieldRefused(AEdit.Pos, 0) then Exit(rtrInField);
    Exit(rtrNone);
  end;
  Result := WindowRefusal(ADoc, AEdit, k, S);
  if S.Window or (Result <> rtrNone) then Exit;
  Result := ReadTableShape(ADoc, k, S);
  if Result <> rtrNone then Exit;
  if S.Locked <> rtrNone then Exit(S.Locked);
  case AEdit.Kind of
    rtkInsertGridColumn, rtkDeleteGridColumns:
      begin
        Result := GridColumnsRefusal(S, AEdit);
        if Result <> rtrNone then Exit;
      end;
    rtkSplitCell:
      begin
        Result := SplitArgsRefusal(AEdit, S.RowCount);
        if Result <> rtrNone then Exit;
        Result := SplitRefusal(S, AEdit);
        if Result <> rtrNone then Exit;
      end;
    rtkMergeCells:
      begin
        if (AEdit.Row0 < 0) or (AEdit.Row1 >= S.RowCount) or (AEdit.Row1 < AEdit.Row0) or
           (AEdit.X1 <= AEdit.X0) then
          Exit(rtrOutOfRange);
        Result := MergeRefusal(ADoc, S, AEdit);
        if Result <> rtrNone then Exit;
      end;
    rtkInsertRow:
      if (AEdit.Index <> CRichRowAbove) and (AEdit.Index <> CRichRowBelow) and
         ((AEdit.Index < 0) or (AEdit.Index > S.RowCount)) then
        Exit(rtrOutOfRange);
    rtkDeleteRow:
      begin
        if (AEdit.Index < 0) or (AEdit.Index >= S.RowCount) then Exit(rtrOutOfRange);
        Result := DeleteRowRefusal(ADoc, S, AEdit.Index);
        if Result <> rtrNone then Exit;
      end;
  else
    begin
      if not S.Regular or not S.Ordered then Exit(rtrIrregularRows);
      n := Length(S.Rows[0].Cells);
      if (AEdit.Index < 0) or (AEdit.Index > n) or
         ((AEdit.Kind = rtkDeleteColumn) and (AEdit.Index = n)) then
        Exit(rtrOutOfRange);
      // a new column beyond what a table may have
      if (AEdit.Kind = rtkInsertColumn) and (n >= CRichMaxTableCols) then Exit(rtrOutOfRange);
    end;
  end;
  // (a row edit needs the rows' cells in order too: a cell's paragraphs are found by it)
  if not S.Ordered then Exit(rtrIrregularRows);
  Result := rtrNone;
end;

{ AEdit with a row named by its position (CRichRowAbove, CRichRowBelow) given its index in S:
  the row of the paragraph at AEdit.Pos, or the one after it. }
function ResolvedEdit(ADoc: TTyRichDocument; const AEdit: TTyRichTableEdit;
  const S: TTyRichShape): TTyRichTableEdit;
var
  k, r: Integer;
begin
  Result := AEdit;
  // (a split names its cell by Index: only a row edit's row is resolved here)
  if AEdit.Kind in [rtkMergeCells, rtkSplitCell] then Exit;
  if S.Window then
  begin
    // (the window's refusal resolved it)
    Result.Index := S.RowIndex;
    Exit;
  end;
  if (AEdit.Kind <> rtkInsertRow) or
     ((AEdit.Index <> CRichRowAbove) and (AEdit.Index <> CRichRowBelow)) then
    Exit;
  k := ADoc.FText.ParaOfPos(AEdit.Pos);
  for r := 0 to S.RowCount - 1 do
    if (k >= S.Rows[r].First) and (k <= S.Rows[r].Last) then
    begin
      Result.Index := r + Ord(AEdit.Index = CRichRowBelow);
      Exit;
    end;
  Result.Index := S.RowCount;
end;

function TTyRichDocument.TableEditRefusal(const AEdit: TTyRichTableEdit): TTyRichTableRefusal;
var
  s: TTyRichShape;
begin
  BeginRead;
  try
    Result := TableRefusal(Self, AEdit, s);
  finally
    EndRead;
  end;
end;

function TTyRichDocument.TableInfoAt(APara: Integer; out AInfo: TTyRichTableInfo): Boolean;
var
  s: TTyRichShape;
  r: Integer;
  c: TTyRichCell;
begin
  AInfo := Default(TTyRichTableInfo);
  AInfo.First := -1;
  AInfo.Last := -1;
  AInfo.Row := -1;
  AInfo.Cell := -1;
  if (APara < 0) or (APara >= FText.ParaCount) then Exit(False);
  BeginRead;
  try
    if ReadTableShape(Self, APara, s) = rtrNoTable then Exit(False);
    AInfo.First := s.First;
    AInfo.Last := s.Last;
    AInfo.RowCount := s.RowCount;
    for r := 0 to s.RowCount - 1 do
      if (APara >= s.Rows[r].First) and (APara <= s.Rows[r].Last) then
      begin
        c := CellAt(APara);
        AInfo.Row := r;
        AInfo.RowFirst := s.Rows[r].First;
        AInfo.RowLast := s.Rows[r].Last;
        AInfo.Cell := c.FIndex;
        AInfo.CellCount := Length(s.Rows[r].Cells);
        AInfo.CellFirst := s.Rows[r].Cells[c.FIndex].First;
        AInfo.CellLast := s.Rows[r].Cells[c.FIndex].Last;
        Exit(True);
      end;
    Result := False;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.TableCellParas(ATablePara, ARow, ACell: Integer;
  out AFirst, ALast: Integer): Boolean;
var
  s: TTyRichShape;
begin
  AFirst := -1;
  ALast := -1;
  if (ATablePara < 0) or (ATablePara >= FText.ParaCount) then Exit(False);
  BeginRead;
  try
    if ReadTableShape(Self, ATablePara, s) = rtrNoTable then Exit(False);
    if (ARow < 0) or (ARow >= s.RowCount) or (ACell < 0) or
       (ACell > High(s.Rows[ARow].Cells)) then
      Exit(False);
    AFirst := s.Rows[ARow].Cells[ACell].First;
    ALast := s.Rows[ARow].Cells[ACell].Last;
    Result := AFirst >= 0;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.EditTable(const AEdit: TTyRichTableEdit;
  var ATables: TTyRichTables): TTyRichUndoData;
var
  r: TTyRichTableRefusal;
  ed: TTyRichTableEditor;
begin
  // (the table read for the check is the one the edit goes by: one read scope for both)
  BeginRead;
  try
    ed := TTyRichTableEditor.Create;
    try
      r := TableRefusal(Self, AEdit, ed.Shape);
      if r <> rtrNone then
        raise ETyRichRefused.CreateFmt('The table edit is refused (%s)', [RefusalName(r)]);
      ed.Doc := Self;
      ed.Edit := ResolvedEdit(Self, AEdit, ed.Shape);
      ed.RowAt := ed.Edit.Index - ed.Shape.Base;
      ed.Kept := @ATables;
      Result := ed.Run;
    finally
      ed.Free;
    end;
  finally
    EndRead;
  end;
end;

{ ---- a table's rows, and its properties ---- }

// the bytes a row object takes
function RowBytes(R: TTyRichRow): Int64;
begin
  Result := R.InstanceSize + Length(R.FRawFormat) + Length(R.FBoundaries) * SizeOf(Integer) +
    Length(R.FCells) * (TTyRichCell.InstanceSize + SizeOf(Pointer));
end;

function TTyRichDocument.SpliceRows(ATable: TTyRichTable; AAt, AOldCount: Integer;
  const ANew: array of TTyRichRow; ANewValid: Boolean): TTyRichUndoData;
var
  i: Integer;
begin
  Result := NewUndo(Default(TTyRichChange));
  ATable.AddRef;
  Result.FRowTable := ATable;
  Result.FRowAt := AAt;
  Result.FRowsOldValid := ATable.FRowsValid;
  Result.FRowsNewValid := ANewValid;
  SetLength(Result.FRowsOld, AOldCount);
  SetLength(Result.FRowsOldIdx, AOldCount);
  for i := 0 to AOldCount - 1 do
  begin
    Result.FRowsOld[i] := ATable.FRows[AAt + i];
    RowAddRef(Result.FRowsOld[i]);
    Result.FRowsOldIdx[i] := ATable.FRows[AAt + i].FIndex;
    // (a row the step keeps alive: its bytes are the step's)
    if Result.FRowsOld[i].FFreeable then
      Inc(Result.FExtraBytes, RowBytes(Result.FRowsOld[i]));
  end;
  SetLength(Result.FRowsNew, Length(ANew));
  for i := 0 to High(ANew) do
  begin
    Result.FRowsNew[i] := ANew[i];
    RowAddRef(ANew[i]);
    // a row made for the edit: what the step makes the table keep
    if ANew[i].FIndex < 0 then
      Inc(Result.FExtraBytes, ANew[i].InstanceSize + Length(ANew[i].FBoundaries) * SizeOf(Integer) +
        Length(ANew[i].FCells) * (TTyRichCell.InstanceSize + SizeOf(Pointer)));
  end;
  ReplaceRowRange(ATable, AAt, AOldCount, ANew);
  ATable.FRowsValid := ANewValid;
end;

procedure TTyRichDocument.RevertRows(AUndo: TTyRichUndoData);
var
  i: Integer;
  t: TTyRichTable;
begin
  t := AUndo.FRowTable;
  ReplaceRowRange(t, AUndo.FRowAt, Length(AUndo.FRowsNew), AUndo.FRowsOld);
  for i := 0 to High(AUndo.FRowsOld) do AUndo.FRowsOld[i].FIndex := AUndo.FRowsOldIdx[i];
  // a row the edit made is in no place again
  for i := 0 to High(AUndo.FRowsNew) do
    if (AUndo.FRowsNew[i].FIndex >= Length(t.FRows)) or
       (t.FRows[AUndo.FRowsNew[i].FIndex] <> AUndo.FRowsNew[i]) then
      AUndo.FRowsNew[i].FIndex := -1;
  t.FRowsValid := AUndo.FRowsOldValid;
end;

{ A delete joined paragraph AFirst (whose value was AOld) with the one after the range, and
  took ARemoved away: a row none of whose paragraphs is left - the rows of the paragraphs
  beside the place are the only ones that can still have one - leaves its table's rows
  unknown (TTyRichTable.FRowsValid). Inside the delete's read scope. }
procedure TTyRichDocument.RowsLost(AFirst: Integer; AOld: TTyRichParaData;
  const ARemoved: TTyRichPieces);
var
  i: Integer;
  r0, r1, r2: TTyRichRow;
  d: TTyRichParaData;
  any: Boolean;

  function RowOfPara(AIndex: Integer): TTyRichRow;
  var
    c: TTyRichCell;
  begin
    Result := nil;
    if (AIndex < 0) or (AIndex >= FText.ParaCount) then Exit;
    c := CellAt(AIndex);
    if c <> nil then Result := c.FRow;
  end;

  procedure Check(D: TTyRichParaData);
  var
    r: TTyRichRow;
  begin
    if (D = nil) or (D.FCell = nil) then Exit;
    r := D.FCell.FRow;
    if (r <> r0) and (r <> r1) and (r <> r2) then r.FTable.FRowsValid := False;
  end;

begin
  any := (AOld <> nil) and (AOld.FCell <> nil);
  for i := 0 to High(ARemoved.Pieces) do
    if (ARemoved.Pieces[i].Separator <> rsNone) and (ARemoved.Pieces[i].Data <> nil) and
       (TTyRichParaData(ARemoved.Pieces[i].Data).FCell <> nil) then
      any := True;
  if not any then Exit;
  r0 := RowOfPara(AFirst - 1);
  r1 := RowOfPara(AFirst);
  r2 := RowOfPara(AFirst + 1);
  Check(AOld);
  for i := 0 to High(ARemoved.Pieces) do
    if ARemoved.Pieces[i].Separator <> rsNone then
    begin
      d := TTyRichParaData(ARemoved.Pieces[i].Data);
      Check(d);
    end;
end;

function HasNestedRow(T: TTyRichTable): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(T.FRows) do
    if T.FRows[i].FHoldsNestedTable then Exit(True);
  Result := False;
end;

{ TTyRichDocument.TablePropsRefusal, and the rows the edit goes by in S: a window of the
  table's rows when they are known, else the table read whole (or the part a loader cut it
  into). Call it inside a read scope. }
function PropsRefusal(ADoc: TTyRichDocument; const AEdit: TTyRichPropEdit;
  out S: TTyRichShape): TTyRichTableRefusal;
const
  BorderProp: array[TTyRichCellSide] of TTyRichCellProp = (rcpBorderLeft, rcpBorderTop,
    rcpBorderRight, rcpBorderBottom);
  PadProp: array[TTyRichCellSide] of TTyRichCellProp = (rcpPadLeft, rcpPadTop, rcpPadRight,
    rcpPadBottom);
var
  k, r, most, nested: Integer;
  c: TTyRichCell;
  t: TTyRichTable;
  row: TTyRichRow;
  side: TTyRichCellSide;
begin
  S := Default(TTyRichShape);
  if ADoc.FLoadingContent or ADoc.FIncomplete or (ADoc.FSaving > 0) then Exit(rtrReadOnly);
  if (AEdit.Pos < 0) or (AEdit.Pos > ADoc.FText.Length) then Exit(rtrOutOfRange);
  k := ADoc.FText.ParaOfPos(AEdit.Pos);
  Inc(ADoc.FTableParaVisits);
  c := ADoc.CellAt(k);
  if c = nil then Exit(rtrNoTable);
  if (AEdit.Row0 < 0) or (AEdit.Row1 < AEdit.Row0) then Exit(rtrOutOfRange);
  // values no row or cell can have
  if AEdit.OfRows then
  begin
    if rrpPad in AEdit.Row.Valid then
      for side := Low(TTyRichCellSide) to High(TTyRichCellSide) do
        if AEdit.Row.DefaultPad[side] < -1 then Exit(rtrOutOfRange);
  end
  else
  begin
    if (AEdit.Col0 < 0) or (AEdit.Col1 < AEdit.Col0) then Exit(rtrOutOfRange);
    if (rcpWidth in AEdit.Cell.Valid) and (AEdit.Cell.WidthTwips < 1) then Exit(rtrOutOfRange);
    for side := Low(TTyRichCellSide) to High(TTyRichCellSide) do
    begin
      if (BorderProp[side] in AEdit.Cell.Valid) and (AEdit.Cell.Borders[side].WidthTwips < 0) then
        Exit(rtrOutOfRange);
      if (PadProp[side] in AEdit.Cell.Valid) and (AEdit.Cell.Pad[side] < -1) then
        Exit(rtrOutOfRange);
    end;
  end;
  t := c.FRow.FTable;
  if not t.FCut and t.FRowsValid then
  begin
    if AEdit.Row1 >= Length(t.FRows) then Exit(rtrOutOfRange);
    if not ReadRowWindow(ADoc, k, t, AEdit.Row0, AEdit.Row1, S) then
    begin
      // the paragraphs are not where its rows say: as if they were not known
      t.FRowsValid := False;
      S := Default(TTyRichShape);
    end;
  end;
  if not S.Window then
  begin
    // (a part a loader cannot give whole: the part's rows - rtrNotWhole leaves S the part)
    if ReadTableShape(ADoc, k, S) = rtrNoTable then Exit(rtrNoTable);
    if AEdit.Row1 >= S.RowCount then Exit(rtrOutOfRange);
  end;
  most := 0;
  nested := 0;
  for r := AEdit.Row0 - S.Base to AEdit.Row1 - S.Base do
  begin
    row := S.Rows[r].Row;
    { A row that holds a nested table is only the file's bytes: it cannot be made again - it
      is left as it is (EditTableProps skips it, PropsSkipped counts it); refused only when
      every row named is one. }
    if row.FHoldsNestedTable then Inc(nested);
    if Length(row.FCells) > most then most := Length(row.FCells);
    if row.FTable.FRows[row.FIndex] <> row then
      raise ETyRichModel.Create('A table''s row is not in its place');
  end;
  if nested = AEdit.Row1 - AEdit.Row0 + 1 then Exit(rtrNestedTable);
  if not AEdit.OfRows and (AEdit.Col0 >= most) then Exit(rtrOutOfRange);
  { The edges moved where rows share them (an edge drag, a fit to a width): merged cells keep
    their place among the edges, so a table with them takes it - not one with a nested table,
    which is the file's bytes. Every cell made as wide as its row's others would part a merged
    cell from the cells it lines up with. }
  if AEdit.OfRows and (AEdit.EdgeKind <> rekNone) then
  begin
    if (AEdit.EdgeKind = rekFit) and (AEdit.FitWidth < 1) then Exit(rtrOutOfRange);
    if (AEdit.EdgeKind = rekDistribute) and t.FContentLocked then Exit(rtrMergedCells);
    Exit(rtrNone);
  end;
  // what moves edges: a table with merged cells keeps them where they are
  if ((not AEdit.OfRows and (rcpWidth in AEdit.Cell.Valid)) or
      (AEdit.OfRows and (rrpLeft in AEdit.Row.Valid))) and t.FContentLocked then
  begin
    if HasNestedRow(t) then Exit(rtrNestedTable);
    Exit(rtrMergedCells);
  end;
  Result := rtrNone;
end;

type
  PTyRichShape = ^TTyRichShape;

procedure DropPropShape(ADoc: TTyRichDocument);
begin
  if ADoc.FPropShape = nil then Exit;
  Dispose(PTyRichShape(ADoc.FPropShape));
  ADoc.FPropShape := nil;
end;

function SamePropEdit(const A, B: TTyRichPropEdit): Boolean;
begin
  Result := CompareByte(A, B, SizeOf(TTyRichPropEdit)) = 0;
end;

function TTyRichDocument.TablePropsRefusal(const AEdit: TTyRichPropEdit): TTyRichTableRefusal;
var
  s: TTyRichShape;
begin
  DropPropShape(Self);
  BeginRead;
  try
    Result := PropsRefusal(Self, AEdit, s);
  finally
    EndRead;
  end;
  // (kept for the edit that may follow at once: a window of rows only, never a loader's part)
  if (Result = rtrNone) and s.Window then
  begin
    New(PTyRichShape(FPropShape));
    PTyRichShape(FPropShape)^ := s;
    FPropShapeState := FState;
    FPropShapeEdit := AEdit;
  end;
end;

function TTyRichDocument.TableRowsAt(APos: TTyRichPos; ARow0, ARow1: Integer;
  out ARows: TTyRichRowList; out AFirstRow, ARowCount: Integer): Boolean;
var
  k, r: Integer;
  c: TTyRichCell;
  t: TTyRichTable;
  s: TTyRichShape;
begin
  ARows := nil;
  AFirstRow := 0;
  ARowCount := 0;
  Result := False;
  if (APos < 0) or (APos > FText.Length) then Exit;
  BeginRead;
  try
    k := FText.ParaOfPos(APos);
    c := CellAt(k);
    if c = nil then Exit;
    t := c.FRow.FTable;
    s := Default(TTyRichShape);
    if not t.FCut and t.FRowsValid then
    begin
      ARowCount := Length(t.FRows);
      if ARow0 < 0 then ARow0 := 0;
      if ARow1 > ARowCount - 1 then ARow1 := ARowCount - 1;
      if ARow1 < ARow0 then
      begin
        AFirstRow := ARow0;
        Exit(True);
      end;
      if not ReadRowWindow(Self, k, t, ARow0, ARow1, s) then
      begin
        // the paragraphs are not where its rows say: as if they were not known
        t.FRowsValid := False;
        s := Default(TTyRichShape);
      end;
    end;
    if not s.Window then
    begin
      if ReadTableShape(Self, k, s) = rtrNoTable then Exit;
      ARowCount := s.RowCount;
      if ARow0 < 0 then ARow0 := 0;
      if ARow1 > ARowCount - 1 then ARow1 := ARowCount - 1;
    end;
    AFirstRow := ARow0;
    if ARow1 >= ARow0 then
    begin
      SetLength(ARows, ARow1 - ARow0 + 1);
      for r := ARow0 to ARow1 do ARows[r - ARow0] := s.Rows[r - s.Base].Row;
    end;
    Result := True;
  finally
    EndRead;
  end;
end;

function EMin(A, B: Integer): Integer; inline;
begin
  if A < B then Result := A else Result := B;
end;

function EMax(A, B: Integer): Integer; inline;
begin
  if A > B then Result := A else Result := B;
end;

{ ARow's edges and left after an edge change (AEdit.EdgeKind, which says what each does). }
procedure EdgesMoved(ARow: TTyRichRow; const AEdit: TTyRichPropEdit; out AEdges: TTyRichEdges;
  out ALeft: Integer);
var
  i, k, n, left, d, best, dist, lo, hi, w: Integer;
  old: TTyRichEdges;
begin
  old := ARow.CellEdges;
  AEdges := Copy(old);
  left := ARow.Format.Row.LeftTwips;
  ALeft := left;
  n := Length(old);
  if n = 0 then Exit;
  case AEdit.EdgeKind of
    rekMove:
      begin
        d := AEdit.EdgeTo - AEdit.EdgeFrom;
        // the row's edge nearest EdgeFrom, within the shared distance (-1: its left)
        best := -2;
        dist := CRichSharedEdgeTwips + 1;
        if Abs(left - AEdit.EdgeFrom) < dist then
        begin
          best := -1;
          dist := Abs(left - AEdit.EdgeFrom);
        end;
        for i := 0 to n - 1 do
          if Abs(old[i] - AEdit.EdgeFrom) < dist then
          begin
            best := i;
            dist := Abs(old[i] - AEdit.EdgeFrom);
          end;
        if (best = -2) or (d = 0) then Exit;
        if best = -1 then
        begin
          if AEdit.EdgeShift then
          begin
            ALeft := left + d;
            for i := 0 to n - 1 do Inc(AEdges[i], d);
          end
          else
            // its first cell's width follows: never narrower than a twip
            ALeft := EMin(left + d, old[0] - 1);
          Exit;
        end;
        if best = 0 then lo := left + 1 else lo := old[best - 1] + 1;
        if AEdit.EdgeShift or (best = n - 1) then
        begin
          k := EMax(old[best] + d, lo);
          d := k - old[best];
          for i := best to n - 1 do Inc(AEdges[i], d);
        end
        else
        begin
          hi := old[best + 1] - 1;
          AEdges[best] := EMin(EMax(old[best] + d, lo), hi);
        end;
      end;
    rekDistribute:
      begin
        w := old[n - 1] - left;
        for i := 0 to n - 2 do AEdges[i] := left + Int64(w) * (i + 1) div n;
      end;
    rekFit:
      begin
        w := old[n - 1] - left;
        if w <= 0 then Exit;
        for i := 0 to n - 1 do
          AEdges[i] := left + Int64(old[i] - left) * AEdit.FitWidth div w;
        // (never two edges at one place)
        for i := 0 to n - 1 do
          if i = 0 then AEdges[0] := EMax(AEdges[0], left + 1)
          else AEdges[i] := EMax(AEdges[i], AEdges[i - 1] + 1);
      end;
  end;
end;

{ ARow's edges after AEdit: a cell's width moves its right edge and every one after it; a
  row's left moves them all. }
function EdgesAfter(ARow: TTyRichRow; const AEdit: TTyRichPropEdit): TTyRichEdges;
var
  i, left, prev, w, d: Integer;
  old: TTyRichEdges;
begin
  old := ARow.CellEdges;
  Result := Copy(old);
  left := ARow.Format.Row.LeftTwips;
  if AEdit.OfRows and (AEdit.EdgeKind <> rekNone) then
  begin
    EdgesMoved(ARow, AEdit, Result, d);
    Exit;
  end;
  if AEdit.OfRows then
  begin
    if not (rrpLeft in AEdit.Row.Valid) then Exit;
    d := AEdit.Row.LeftTwips - left;
    for i := 0 to High(Result) do Inc(Result[i], d);
    Exit;
  end;
  if not (rcpWidth in AEdit.Cell.Valid) then Exit;
  prev := left;
  for i := 0 to High(old) do
  begin
    if i = 0 then w := old[0] - left else w := old[i] - old[i - 1];
    if (i >= AEdit.Col0) and (i <= AEdit.Col1) then w := AEdit.Cell.WidthTwips;
    Result[i] := prev + w;
    prev := Result[i];
  end;
end;

function TTyRichDocument.EditTableProps(const AEdit: TTyRichPropEdit): TTyRichUndoData;
var
  s: TTyRichShape;
  why: TTyRichTableRefusal;
  ed: TTyRichTableEditor;
  rr, k: Integer;
  row, nr: TTyRichRow;
  f: TTyRichRowFormat;
  edges, old: TTyRichEdges;
  cells: array of TTyRichCell;
  moved: Boolean;
  i, newLeft: Integer;
  rp: TTyRichRowProps;
  // a run of changed rows next to each other, whose paragraphs and places are set at once
  runRows: array of TTyRichRow;
  runCells: array of TTyRichCell;
  runFirst, runAt, nRows, nCells: Integer;
  runTable: TTyRichTable;

  procedure FlushRun;
  begin
    if nRows = 0 then Exit;
    Result.AddPart(ed.SetCells(runFirst, Copy(runCells, 0, nCells), [rckFormat]));
    Result.AddPart(SpliceRows(runTable, runAt, nRows, Copy(runRows, 0, nRows), runTable.FRowsValid));
    nRows := 0;
    nCells := 0;
  end;

begin
  nRows := 0;
  nCells := 0;
  runFirst := 0;
  runAt := 0;
  runTable := nil;
  runRows := nil;
  runCells := nil;
  BeginRead;
  try
    // the rows the refusal just read, when nothing changed since (see FPropShape)
    if (FPropShape <> nil) and (FPropShapeState = FState) and SamePropEdit(FPropShapeEdit, AEdit) then
    begin
      s := PTyRichShape(FPropShape)^;
      why := rtrNone;
    end
    else
      why := PropsRefusal(Self, AEdit, s);
    DropPropShape(Self);
    if why <> rtrNone then
      raise ETyRichRefused.CreateFmt('The table edit is refused (%s)', [RefusalName(why)]);
    Result := NewUndo(Default(TTyRichChange));
    ed := TTyRichTableEditor.Create;
    try
      ed.Doc := Self;
      try
        for rr := AEdit.Row0 - s.Base to AEdit.Row1 - s.Base do
        begin
          row := s.Rows[rr].Row;
          // a row that holds a nested table: left as it is, counted (see PropsRefusal)
          if row.FHoldsNestedTable then
          begin
            Inc(FPropsSkipped);
            FlushRun;
            Continue;
          end;
          if AEdit.OfRows and (AEdit.EdgeKind <> rekNone) then
          begin
            // the edges, and the left when it moved (in the row's format)
            EdgesMoved(row, AEdit, edges, newLeft);
            if newLeft <> row.Format.Row.LeftTwips then
            begin
              rp := Default(TTyRichRowProps);
              rp.Valid := [rrpLeft];
              rp.LeftTwips := newLeft;
              f := TyRichWithRowProps(row.Format, rp);
            end
            else
            begin
              f := row.Format;
              f.AddRef;
            end;
          end
          else
          begin
            if AEdit.OfRows then f := TyRichWithRowProps(row.Format, AEdit.Row)
            else f := TyRichWithCellProps(row.Format, AEdit.Col0, AEdit.Col1, AEdit.Cell);
            edges := EdgesAfter(row, AEdit);
          end;
          old := row.CellEdges;
          moved := False;
          for i := 0 to High(edges) do
            if edges[i] <> old[i] then moved := True;
          if (f = row.Format) and not moved then
          begin
            // nothing of this row changes
            f.Release;
            FlushRun;
            Continue;
          end;
          try
            Inc(FTableEditSteps);
            if moved then
              nr := NewRowIn(row.FTable, Length(row.FCells), row.FRawFormat, edges,
                row.FHoldsNestedTable, row.BaseFormat, f)
            else
              nr := NewRowIn(row.FTable, Length(row.FCells), row.FRawFormat, row.FBoundaries,
                row.FHoldsNestedTable, row.BaseFormat, f);
            // (its bytes' \cellx no longer its edges: the row is written from the model)
            nr.FEdgesMoved := moved or row.FEdgesMoved;
          finally
            f.Release;
          end;
          { Its paragraphs: the same cells of the new row. Rows next to each other - their
            paragraphs and their places in the table - are set as one run: one change told,
            one splice (a column's edge in ten thousand rows is two parts, not twenty
            thousand). }
          if (nRows > 0) and ((row.FTable <> runTable) or (row.FIndex <> runAt + nRows) or
             (s.Rows[rr].First <> runFirst + nCells)) then
            FlushRun;
          if nRows = 0 then
          begin
            runTable := row.FTable;
            runAt := row.FIndex;
            runFirst := s.Rows[rr].First;
          end;
          if nRows >= Length(runRows) then SetLength(runRows, 2 * nRows + 16);
          runRows[nRows] := nr;
          Inc(nRows);
          for k := s.Rows[rr].First to s.Rows[rr].Last do
          begin
            Inc(FTableEditSteps);
            if nCells >= Length(runCells) then SetLength(runCells, 2 * nCells + 16);
            runCells[nCells] := nr.FCells[s.Cells[k - s.First].FIndex];
            Inc(nCells);
          end;
        end;
        FlushRun;
        Result.SealParts;
      except
        Revert(Result);
        raise;
      end;
    finally
      ed.Free;
    end;
  finally
    EndRead;
  end;
end;

{ The row ARow of the table ATablePos is in (counted as the table edits count them), nil for
  none. Inside a read scope. }
function PropRow(ADoc: TTyRichDocument; ATablePos: TTyRichPos; ARow: Integer): TTyRichRow;
var
  k: Integer;
  c: TTyRichCell;
  t: TTyRichTable;
  s: TTyRichShape;
begin
  Result := nil;
  if (ATablePos < 0) or (ATablePos > ADoc.FText.Length) or (ARow < 0) then Exit;
  k := ADoc.FText.ParaOfPos(ATablePos);
  Inc(ADoc.FTableParaVisits);
  c := ADoc.CellAt(k);
  if c = nil then Exit;
  t := c.FRow.FTable;
  if not t.FCut and t.FRowsValid then
  begin
    if ARow < Length(t.FRows) then Result := t.FRows[ARow];
    Exit;
  end;
  if (ReadTableShape(ADoc, k, s) <> rtrNoTable) and (ARow < s.RowCount) then
    Result := s.Rows[ARow].Row;
end;

function TTyRichDocument.CellProps(ATablePos: TTyRichPos; ARow, ACol: Integer): TTyRichCellProps;
var
  row: TTyRichRow;
  edges: TTyRichEdges;
  w: Integer;
begin
  Result := Default(TTyRichCellProps);
  BeginRead;
  try
    row := PropRow(Self, ATablePos, ARow);
    if (row = nil) or (ACol < 0) or (ACol >= Length(row.FCells)) then Exit;
    edges := row.CellEdges;
    if ACol = 0 then w := edges[0] - row.Format.Row.LeftTwips
    else w := edges[ACol] - edges[ACol - 1];
    Result := TyRichEffectiveCellProps(row.Format, ACol, w);
  finally
    EndRead;
  end;
end;

function TTyRichDocument.RowProps(ATablePos: TTyRichPos; ARow: Integer): TTyRichRowProps;
var
  row: TTyRichRow;
begin
  Result := Default(TTyRichRowProps);
  BeginRead;
  try
    row := PropRow(Self, ATablePos, ARow);
    if row <> nil then Result := row.Format.Row;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.TableRowIndex(APara: Integer; out ARow, ARowCount: Integer): Boolean;
var
  c: TTyRichCell;
  t: TTyRichTable;
  info: TTyRichTableInfo;
begin
  ARow := -1;
  ARowCount := 0;
  if (APara < 0) or (APara >= FText.ParaCount) then Exit(False);
  BeginRead;
  try
    c := CellAt(APara);
    if c = nil then Exit(False);
    t := c.FRow.FTable;
    if not t.FCut and t.FRowsValid and (c.FRow.FIndex >= 0) and
       (c.FRow.FIndex < Length(t.FRows)) and (t.FRows[c.FRow.FIndex] = c.FRow) then
    begin
      ARow := c.FRow.FIndex;
      ARowCount := Length(t.FRows);
      Exit(True);
    end;
  finally
    EndRead;
  end;
  Result := TableInfoAt(APara, info);
  if Result then
  begin
    ARow := info.Row;
    ARowCount := info.RowCount;
  end;
end;

{ ---- a fragment of another document ---- }

function TTyRichFragmentFilter.RowLook(const ARaw: RawByteString;
  ACellCount: Integer): TTyRichRowFormat;
begin
  Result := TyRichDecodeRowFormat(ARaw, ACellCount, []);
end;

constructor TTyRichFragment.Create(ATarget: TTyRichDocument; APos: TTyRichPos;
  ASource: TTyRichDocument; AEndsWithParagraph: Boolean; AFlatten: Boolean;
  AFilter: TTyRichFragmentFilter);
var
  t: TTyRichText;
  k, n, i: Integer;
  o: Int64;
  cell: TTyRichCell;
begin
  inherited Create;
  if (ATarget = nil) or (ASource = nil) or (ATarget = ASource) then
    raise ETyRichModel.Create('A fragment needs a target and a source of its own');
  FDoc := ATarget;
  FSrc := ASource;
  FFilter := AFilter;
  t := ATarget.FText;
  k := t.ParaOfPos(APos);   // range check
  o := APos - t.ParaStart(k);
  { The target's cell at APos is used to the end (the values made here hold it): in a document
    that parses on demand it stays as read only inside a read scope - one for all of this. }
  ATarget.BeginRead;
  try
  cell := ATarget.CellOfData(ATarget.DataOf(k));
  // a table goes into a table only as its text: there are no nested tables
  FFlat := AFlatten or (cell <> nil);
  FFlatCell := cell;
  FSrcDefault := ASource.DefaultCharFormat;
  n := ASource.FText.ParaCount;
  try
    if (ASource.FText.Length = 0) and not AEndsWithParagraph then Exit;
    SetLength(FCharMap, ASource.FFormats.CharCount);
    for i := 0 to High(FCharMap) do FCharMap[i] := -1;
    SetLength(FParaMap, ASource.FFormats.ParaCount);
    for i := 0 to High(FParaMap) do FParaMap[i] := -1;
    SetLength(FParts, n + 3);
    SetLength(FLens, n + 3);
    SetLength(FOwn, n + 3);
    // tables, cells and objects of a document that parses on demand stay as read meanwhile
    ASource.BeginRead;
    try
      ASource.FText.WalkParaTexts(0, n - 1, @TakePara, True);
    finally
      ASource.EndRead;
    end;
    if AEndsWithParagraph then
    begin
      AddText(nil, 0);
      AddPart(nil, 0, True);
    end;
    if not FFlat then
    begin
      // rows stay rows: the text before APos keeps its own paragraph, and a last row is
      // never joined with the text after APos
      if (o > 0) and (PartCell(0) <> nil) then InsertOwnFirst;
      if PartCell(FCount - 1) <> nil then
      begin
        AddText(nil, 0);
        AddPart(nil, 0, True);
      end;
    end;
    SetLength(FText, FTextLen);
    if FFlatCell <> nil then UnfieldOverParagraphs;
  finally
    FSrc := nil;
    FFilter := nil;
    FCharMap := nil;
    FParaMap := nil;
    // a table made again was held while it was made: the values that use it hold theirs
    for i := 0 to FTabCount - 1 do
      if (FTabNew[i] <> nil) and (FTabNew[i] <> FTabSrc[i]) then FTabNew[i].Release;
    FTabSrc := nil;
    FTabNew := nil;
    FTabCount := 0;
  end;
  finally
    ATarget.EndRead;
  end;
end;

destructor TTyRichFragment.Destroy;
var
  i: Integer;
begin
  if FDoc <> nil then
  begin
    for i := 0 to FCount - 1 do FDoc.ReleaseData(FParts[i]);
    DropBody;
  end;
  inherited Destroy;
end;

procedure TTyRichFragment.DropBody;
var
  i: Integer;
begin
  for i := 0 to High(FBodyPieces.Pieces) do
    if (FBodyPieces.Pieces[i].Separator <> rsNone) and (FBodyPieces.Pieces[i].Data <> nil) then
      FDoc.ReleaseData(TTyRichParaData(FBodyPieces.Pieces[i].Data));
  FBodyPieces := Default(TTyRichPieces);
end;

{ A paragraph mark after the parts so far: in the text, or one more to put after the body. }
procedure TTyRichFragment.AddMark;
begin
  if FBody then Inc(FTrail) else AddText(nil, 0);
end;

function TTyRichFragment.CharCount: Int64;
var
  i: Integer;
begin
  Result := 0;
  if FCount = 0 then Exit;
  Result := FCount - 1;
  for i := 0 to FCount - 1 do Inc(Result, FLens[i]);
end;

function TTyRichFragment.MemSize: Int64;
var
  i: Integer;
begin
  // the text: as it is, or what its first insert keeps alive in the add buffer
  Result := InstanceSize + Length(FText) + FTextBytes +
    (Length(FPieces.Pieces) + Length(FBodyPieces.Pieces) + Length(FLeadPieces.Pieces) +
    Length(FTrailPieces.Pieces)) * SizeOf(TTyRichPiece) +
    Length(FParts) * (SizeOf(Pointer) + SizeOf(Int64) + 1);
  // the values are this fragment's own (made for it), with their runs (the objects they
  // bring: GatherObjects)
  for i := 0 to FCount - 1 do
    if FParts[i] <> nil then
      Inc(Result, FParts[i].InstanceSize + Length(FParts[i].FRuns) * SizeOf(TTyRichRun));
end;

procedure TTyRichFragment.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
var
  i, j: Integer;
begin
  for i := 0 to FCount - 1 do
    if FParts[i] <> nil then
      for j := 0 to High(FParts[i].FRuns) do
        if FParts[i].FRuns[j].Obj <> nil then
        begin
          Inc(FDoc.FHistoryObjectVisits);
          AddObject(AList, ACount, FParts[i].FRuns[j].Obj);
        end;
end;

function TTyRichFragment.PartCell(AIndex: Integer): TTyRichCell;
begin
  if (AIndex < 0) or (AIndex >= FCount) or FOwn[AIndex] or (FParts[AIndex] = nil) then
    Result := nil
  else
    Result := FParts[AIndex].FCell;
end;

procedure TTyRichFragment.AddPart(AValue: TTyRichParaData; ALen: Int64; AOwn: Boolean);
begin
  if FCount = Length(FParts) then
  begin
    SetLength(FParts, FCount * 2 + 4);
    SetLength(FLens, FCount * 2 + 4);
    SetLength(FOwn, FCount * 2 + 4);
  end;
  FDoc.AcquireData(AValue);
  FParts[FCount] := AValue;
  FLens[FCount] := ALen;
  FOwn[FCount] := AOwn;
  Inc(FCount);
end;

procedure TTyRichFragment.InsertOwnFirst;
var
  i: Integer;
  s: UTF8String;
begin
  AddPart(nil, 0, True);
  for i := FCount - 1 downto 1 do
  begin
    FParts[i] := FParts[i - 1];
    FLens[i] := FLens[i - 1];
    FOwn[i] := FOwn[i - 1];
  end;
  FParts[0] := nil;
  FLens[0] := 0;
  FOwn[0] := True;
  if FBody then
  begin
    FLead := True;
    Exit;
  end;
  s := #10;
  SetLength(FText, FTextLen);
  FText := s + FText;
  Inc(FTextLen);
end;

{ ALen bytes at P, after a separator when a part came before. }
procedure TTyRichFragment.AddText(P: PByte; ALen: PtrInt);
var
  need, i: PtrInt;
  q: PAnsiChar;
begin
  need := FTextLen + ALen + 1;
  if need > Length(FText) then
  begin
    if need < 2 * Length(FText) then need := 2 * Length(FText);
    SetLength(FText, need + 16);
  end;
  if FCount > 0 then
  begin
    FText[FTextLen + 1] := #10;
    Inc(FTextLen);
  end;
  if ALen > 0 then
  begin
    Move(P^, FText[FTextLen + 1], ALen);
    { A paragraph's text holds no separator; one a source should never give (a CR inside a
      paragraph) is a space here, so that the insert makes the parts it was counted to make. }
    q := @FText[FTextLen + 1];
    for i := 0 to ALen - 1 do
      if q[i] in [#10, #13] then q[i] := ' ';
    Inc(FTextLen, ALen);
  end;
end;

function TTyRichFragment.MapChar(AId: TTyCharFormatId): TTyCharFormatId;
var
  f: TTyCharFormat;
begin
  if (AId >= 0) and (AId < Length(FCharMap)) and (FCharMap[AId] >= 0) then Exit(FCharMap[AId]);
  f := FSrc.FFormats.CharFormat(AId);
  { What the source showed in its default font (no font of its own) keeps that font here,
    named: the target's defaults are not the source's. }
  if (f.FontName = '') and (FSrcDefault.FontName <> '') then
  begin
    f.FontName := FSrcDefault.FontName;
    f.Charset := FSrcDefault.Charset;
  end;
  if (f.SizeHalfPt = 0) and (FSrcDefault.SizeHalfPt <> 0) then f.SizeHalfPt := FSrcDefault.SizeHalfPt;
  if FFilter <> nil then f.Extra := MapExtra(f.Extra, False);
  Result := FDoc.FFormats.InternChar(f);
  if (AId >= 0) and (AId < Length(FCharMap)) then FCharMap[AId] := Result;
end;

function TTyRichFragment.MapPara(AId: TTyParaFormatId): TTyParaFormatId;
var
  f: TTyParaFormat;
begin
  if (AId >= 0) and (AId < Length(FParaMap)) and (FParaMap[AId] >= 0) then Exit(FParaMap[AId]);
  f := FSrc.FFormats.ParaFormat(AId);
  if FFilter <> nil then f.Extra := MapExtra(f.Extra, True);
  Result := FDoc.FFormats.InternPara(f);
  if (AId >= 0) and (AId < Length(FParaMap)) then FParaMap[AId] := Result;
end;

function TTyRichFragment.MapExtra(const AExtra: TTyOpaqueAttrs; APara: Boolean): TTyOpaqueAttrs;
var
  i: Integer;
begin
  Result.FItems := nil;
  for i := 0 to AExtra.Count - 1 do
    if FFilter.KeepFragment(AExtra.Item(i), APara) then Result.Add(AExtra.Item(i));
end;

{ The cell a paragraph of the source's ACell goes into: the very one, or with a filter the
  same cell of the table made again for the target - made at its first paragraph, whole (a
  table's rows are fixed once a paragraph uses it). }
function TTyRichFragment.MapCell(ACell: TTyRichCell): TTyRichCell;
var
  src, nt: TTyRichTable;
  r: TTyRichRow;
  i: Integer;
  fmt: TTyRichRowFormat;
begin
  Result := ACell;
  if ACell = nil then Exit;
  src := ACell.Table;
  i := FTabCount - 1;
  while (i >= 0) and (FTabSrc[i] <> src) do Dec(i);
  if i < 0 then
  begin
    nt := src;
    { A table with a row that holds a nested table goes in as its paragraphs: what
      made the inner table one is only in the bytes of the source's file, and in this
      document such a row could neither be saved nor edited. }
    for i := 0 to High(src.FRows) do
      if src.FRows[i].FHoldsNestedTable then nt := nil;
    if FTabCount = Length(FTabSrc) then
    begin
      SetLength(FTabSrc, FTabCount * 2 + 4);
      SetLength(FTabNew, FTabCount * 2 + 4);
    end;
    { Made again with a filter and without one: two runs of paragraphs never share a table
      object (a table edit changes its rows in place - a source pasted twice would be two
      tables of one object). }
    if nt <> nil then
    begin
      // (a part of a table cut by a loader is a table of its own in the target)
      nt := TTyRichTable.Create(src.FColBoundaries, src.FContentLocked);
      { held while the fragment is made (Create lets go of it at its end) - entered first, so
        that a failure while its rows are made (out of memory, the filter's) lets go of it too }
      nt.AddRef;
      FTabSrc[FTabCount] := src;
      FTabNew[FTabCount] := nt;
      Inc(FTabCount);
      for i := 0 to High(src.FRows) do
      begin
        r := src.FRows[i];
        if FFilter = nil then
        begin
          nt.AddRow(Length(r.FCells), r.FRawFormat, r.FBoundaries, r.FHoldsNestedTable);
          nt.FRows[i].SetFormats(r.BaseFormat, r.Format);
          nt.FRows[i].FEdgesMoved := r.FEdgesMoved;
        end
        else
        begin
          nt.AddRow(Length(r.FCells), FFilter.RowFormat(r.FRawFormat), r.FBoundaries,
            r.FHoldsNestedTable);
          { What the bytes say of the row, as the filter left them. A look a property edit set
            goes as the source has it, its colours real ones: a writer makes the definition
            again from it, in the target's numbers. }
          fmt := FFilter.RowLook(nt.FRows[i].FRawFormat, Length(r.FCells));
          try
            if r.Edited then nt.FRows[i].SetFormats(fmt, r.Format)
            else nt.FRows[i].SetFormats(fmt, fmt);
            nt.FRows[i].FEdgesMoved := r.FEdgesMoved;
          finally
            fmt.Release;
          end;
        end;
      end;
      nt.FRowsValid := src.FRowsValid;
    end
    else
    begin
      FTabSrc[FTabCount] := src;
      FTabNew[FTabCount] := nt;
      Inc(FTabCount);
    end;
    i := FTabCount - 1;
  end
  else if i < FTabCount - 1 then
  begin
    // the table met last first: a table's paragraphs follow each other
    src := FTabSrc[i];
    nt := FTabNew[i];
    FTabSrc[i] := FTabSrc[FTabCount - 1];
    FTabNew[i] := FTabNew[FTabCount - 1];
    FTabSrc[FTabCount - 1] := src;
    FTabNew[FTabCount - 1] := nt;
    i := FTabCount - 1;
  end;
  nt := FTabNew[i];
  if nt = nil then Exit(nil);
  if nt = ACell.Table then Exit;
  Result := nt.FRows[ACell.FRow.FIndex].FCells[ACell.FIndex];
end;

function Utf8SeqLen(B: Byte): Integer; inline;
begin
  if B < $C0 then Result := 1
  else if B < $E0 then Result := 2
  else if B < $F0 then Result := 3
  else Result := 4;
end;

{ The paragraph's objects through the filter: one kept or made again stays its character; one
  left out gives its character's place to the text the filter has for it (or to nothing). }
procedure TTyRichFragment.MapObjects(var AText: RawByteString; var ARuns: TTyRunArray;
  var AChars: Int64);
var
  j, n: Integer;
  p, q: PtrInt;
  ch, runEnd, outCh: Int64;
  got: TTyRichObject;
  s: UTF8String;
  o: RawByteString;
  runs: TTyRunArray;
begin
  o := '';
  runs := nil;
  SetLength(runs, Length(ARuns));
  n := 0;
  p := 1;
  ch := 0;
  outCh := 0;
  for j := 0 to High(ARuns) do
  begin
    if j < High(ARuns) then runEnd := ARuns[j + 1].Start else runEnd := AChars;
    if ARuns[j].Obj = nil then
    begin
      AppendRun(runs, n, outCh, ARuns[j].Format, nil);
      q := p;
      while (ch < runEnd) and (q <= Length(AText)) do
      begin
        Inc(q, Utf8SeqLen(Byte(AText[q])));
        Inc(ch);
        Inc(outCh);
      end;
      if q > Length(AText) + 1 then q := Length(AText) + 1;
      o := o + Copy(AText, p, q - p);
      p := q;
      Continue;
    end;
    // an object run is its one character
    q := p;
    if (ch < runEnd) and (q <= Length(AText)) then
    begin
      Inc(q, Utf8SeqLen(Byte(AText[q])));
      if q > Length(AText) + 1 then q := Length(AText) + 1;
      Inc(ch);
    end;
    got := FFilter.MapObject(ARuns[j].Obj, s);
    if got <> nil then
    begin
      AppendRun(runs, n, outCh, ARuns[j].Format, got);
      o := o + Copy(AText, p, q - p);
      Inc(outCh);
    end
    else if s <> '' then
    begin
      AppendRun(runs, n, outCh, ARuns[j].Format, nil);
      o := o + s;
      q := 1;
      while q <= Length(s) do
      begin
        Inc(q, Utf8SeqLen(Byte(s[q])));
        Inc(outCh);
      end;
    end;
    p := q;
    // (a run that held more than its one character: the rest as text)
    if (ch < runEnd) and (p <= Length(AText)) then
      AppendRun(runs, n, outCh, ARuns[j].Format, nil);
    while (ch < runEnd) and (p <= Length(AText)) do
    begin
      q := p + Utf8SeqLen(Byte(AText[p]));
      if q > Length(AText) + 1 then q := Length(AText) + 1;
      o := o + Copy(AText, p, q - p);
      p := q;
      Inc(ch);
      Inc(outCh);
    end;
  end;
  if n = 0 then AppendRun(runs, n, 0, ARuns[0].Format, nil);
  SetLength(runs, n);
  AText := o;
  ARuns := runs;
  AChars := outCh;
end;

{ Going into a cell: a field whose result holds a paragraph's end goes as its content without
  its own marks - in a cell a reader keeps such a field as one object, so the document saved
  would not read back as shown. The fields inside it that fit in a cell (no paragraph end of
  their own) stay fields. The parts are one to one with the text's runs between its #10s
  (into a cell nothing goes before the first part). }
procedure TTyRichFragment.UnfieldOverParagraphs;
type
  TMarkAt = record
    Part, Run: Integer;
  end;
var
  stack: array of TMarkAt;
  drop: array of array of Boolean;
  sp, i, j, n: Integer;
  any: Boolean;
  runs, nr: TTyRunArray;
  o: UTF8String;
  p, q, w, segEnd, k: PtrInt;
  ch, stop, outCh: Int64;
  v: TTyRichParaData;

  procedure Mark(APart, ARun: Integer);
  begin
    if drop[APart] = nil then SetLength(drop[APart], Length(FParts[APart].FRuns));
    drop[APart][ARun] := True;
  end;

begin
  stack := nil;
  sp := 0;
  any := False;
  drop := nil;
  SetLength(drop, FCount);
  for i := 0 to FCount - 1 do
    if FParts[i] <> nil then
      for j := 0 to High(FParts[i].FRuns) do
        if FParts[i].FRuns[j].Obj is TTyRichFieldMark then
          if TTyRichFieldMark(FParts[i].FRuns[j].Obj).Kind = rfmOpen then
          begin
            if sp = Length(stack) then SetLength(stack, sp * 2 + 8);
            stack[sp].Part := i;
            stack[sp].Run := j;
            Inc(sp);
          end
          // (a close with no open: InsertFragment refuses the fragment)
          else if sp > 0 then
          begin
            Dec(sp);
            if stack[sp].Part <> i then
            begin
              Mark(stack[sp].Part, stack[sp].Run);
              Mark(i, j);
              any := True;
            end;
          end;
  if not any then Exit;
  if FBody then
    raise ETyRichModel.Create('A field over a paragraph''s end goes into a cell only from ' +
      'content read as text (TTyRichRangeContent''s AIntoCell)');
  o := '';
  SetLength(o, FTextLen);
  w := 0;
  p := 1;
  for i := 0 to FCount - 1 do
  begin
    segEnd := p;
    while (segEnd <= FTextLen) and (FText[segEnd] <> #10) do Inc(segEnd);
    if i > 0 then
    begin
      Inc(w);
      o[w] := #10;
    end;
    if drop[i] = nil then
    begin
      if segEnd > p then Move(FText[p], o[w + 1], segEnd - p);
      Inc(w, segEnd - p);
    end
    else
    begin
      runs := FParts[i].FRuns;
      nr := nil;
      SetLength(nr, Length(runs));
      n := 0;
      q := p;
      ch := 0;
      outCh := 0;
      for j := 0 to High(runs) do
      begin
        stop := RunEnd(runs, j, FLens[i]);
        if drop[i][j] then
        begin
          // the mark's one character goes; (anything more of its run stays as text)
          if (ch < stop) and (q < segEnd) then
          begin
            Inc(q, Utf8SeqLen(Byte(FText[q])));
            Inc(ch);
          end;
          if ch < stop then AppendRun(nr, n, outCh, runs[j].Format, nil);
        end
        else
          AppendRun(nr, n, outCh, runs[j].Format, runs[j].Obj);
        while (ch < stop) and (q < segEnd) do
        begin
          k := Utf8SeqLen(Byte(FText[q]));
          if q + k > segEnd then k := segEnd - q;
          Move(FText[q], o[w + 1], k);
          Inc(w, k);
          Inc(q, k);
          Inc(ch);
          Inc(outCh);
        end;
      end;
      if n = 0 then AppendRun(nr, n, 0, runs[0].Format, nil);
      SetLength(nr, n);
      v := FDoc.MakeData(FDoc.FormatOfData(FParts[i]), nr, FDoc.CellOfData(FParts[i]));
      FDoc.AcquireData(v);
      FDoc.ReleaseData(FParts[i]);
      FParts[i] := v;
      FLens[i] := outCh;
    end;
    p := segEnd + 1;
  end;
  SetLength(o, w);
  FText := o;
  FTextLen := w;
end;

procedure TTyRichFragment.TakePara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  fmt: TTyParaFormatId;
  runs, mapped: TTyRunArray;
  cell: TTyRichCell;
  n, j: Integer;
  chars: Int64;
  txt: RawByteString;
  objs: Boolean;
begin
  // a paragraph of a reader that parses on demand with no value of the moment: parse it
  if not FSrc.ReadValue(AData, fmt, runs, cell) then
    FSrc.ReadValue(FSrc.DataOf(AIndex), fmt, runs, cell);
  chars := FSrc.FText.ParaLength(AIndex);
  objs := False;
  if FFilter <> nil then
    for j := 0 to High(runs) do
      if runs[j].Obj <> nil then
      begin
        objs := True;
        Break;
      end;
  if objs then
  begin
    txt := '';
    SetLength(txt, ALen);
    if ALen > 0 then Move(AText^, txt[1], ALen);
    MapObjects(txt, runs, chars);
  end;
  mapped := nil;
  n := 0;
  SetLength(mapped, Length(runs));
  for j := 0 to High(runs) do
    AppendRun(mapped, n, runs[j].Start, MapChar(runs[j].Format), runs[j].Obj);
  SetLength(mapped, n);
  if FFlat then cell := FFlatCell else cell := MapCell(cell);
  if objs then AddText(PByte(PAnsiChar(txt)), Length(txt))
  else AddText(AText, ALen);
  AddPart(FDoc.MakeData(MapPara(fmt), mapped, cell), chars, False);
end;

{ ---- a stretch of a document's own content ---- }

constructor TTyRichRangeContent.Create(ADoc: TTyRichDocument; AFrom, ALen: TTyRichPos;
  AWiden: Boolean; AIntoCell: Boolean);
var
  t: TTyRichText;
  stop, tFrom, tTo: TTyRichPos;
  first, last, i, k: Integer;
  fromCh, toCh, acc: Int64;
  lastSep, lastWhole: Boolean;
  c0, c1, c: TTyRichCell;
begin
  inherited Create;
  if ADoc = nil then raise ETyRichModel.Create('A range of a document needs the document');
  FDoc := ADoc;
  t := ADoc.FText;
  if (AFrom < 0) or (ALen <= 0) or (AFrom + ALen > t.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [AFrom, ALen, t.Length]);
  // the paragraphs a copy takes: RtfWrite's TyRichCopyRange, whose rules these are
  stop := AFrom + ALen;
  first := t.ParaOfPos(AFrom);
  last := t.ParaOfPos(stop - 1);
  fromCh := AFrom - t.ParaStart(first);
  lastSep := stop - 1 >= t.ParaStart(last) + t.ParaLength(last);
  if lastSep then toCh := t.ParaLength(last) else toCh := stop - t.ParaStart(last);
  lastWhole := lastSep or ((last = t.ParaCount - 1) and (toCh = t.ParaLength(last)) and
    ((first < last) or ((fromCh = 0) and (t.ParaCount = 1))));
  // an empty last paragraph is taken whole by a range that reaches it through its separator
  if lastSep and (stop = t.Length) and (last = t.ParaCount - 2) and
    (t.ParaLength(t.ParaCount - 1) = 0) then
  begin
    last := t.ParaCount - 1;
    toCh := 0;
    lastSep := False;
    lastWhole := True;
  end;
  ADoc.BeginRead;
  try
    c0 := ADoc.CellAt(first);
    c1 := ADoc.CellAt(last);
    FInOneCell := (c0 <> nil) and (c0 = c1);
    if AWiden and not FInOneCell then
    begin
      // more than one cell, or across a row's edge: every row met whole
      if c0 <> nil then
      begin
        while first > 0 do
        begin
          c := ADoc.CellAt(first - 1);
          if (c = nil) or (c.Row <> c0.Row) then Break;
          Dec(first);
        end;
        fromCh := 0;
      end;
      if c1 <> nil then
      begin
        while last < t.ParaCount - 1 do
        begin
          c := ADoc.CellAt(last + 1);
          if (c = nil) or (c.Row <> c1.Row) then Break;
          Inc(last);
        end;
        toCh := t.ParaLength(last);
        lastSep := last < t.ParaCount - 1;
        lastWhole := True;
      end;
    end;
    FFirst := first;
    FLast := last;
    FFirstFrom := fromCh;
    FLastTo := toCh;
    FFirstLen := t.ParaLength(first);
    FLastLen := t.ParaLength(last);
    FEnds := lastWhole;
    FEndsInText := lastSep;
    tFrom := t.ParaStart(first) + fromCh;
    tTo := t.ParaStart(last) + toCh;
    if lastSep then Inc(tTo);
    FCharCount := tTo - tFrom;
    // the text as its pieces - unless a lazy one is among them: then as text
    if FCharCount > 0 then FPieces := t.PieceSnapshot(tFrom, FCharCount);
    for i := 0 to High(FPieces.Pieces) do
      if FPieces.Pieces[i].Kind = rpkLazy then
      begin
        FUseText := True;
        Break;
      end;
    if FUseText then
      FPieces := Default(TTyRichPieces)
    else
      for i := 0 to High(FPieces.Pieces) do
        if (FPieces.Pieces[i].Separator <> rsNone) and (FPieces.Pieces[i].Data <> nil) then
          ADoc.AcquireData(TTyRichParaData(FPieces.Pieces[i].Data));
    FCount := last - first + 1;
    SetLength(FValues, FCount);
    SetLength(FLens, FCount);
    for i := 0 to FCount - 1 do FValues[i] := nil;
    { The characters taken of each paragraph, from the pieces: a separator ends one (not a
      lookup a paragraph). }
    if not FUseText then
    begin
      k := 0;
      acc := 0;
      for i := 0 to High(FPieces.Pieces) do
      begin
        Inc(acc, FPieces.Pieces[i].CharCount);
        if FPieces.Pieces[i].Separator <> rsNone then
        begin
          FLens[k] := acc - 1;
          Inc(k);
          acc := 0;
        end;
      end;
      if k < FCount then FLens[k] := acc;
    end;
    t.WalkParaTexts(first, last, @TakePara, False);
    if AIntoCell and not FUseText and FieldOverParagraphs then
    begin
      // as text after all: its pieces cannot lose a field's marks
      for i := 0 to FCount - 1 do
      begin
        ADoc.ReleaseData(FValues[i]);
        FValues[i] := nil;
      end;
      for i := 0 to High(FPieces.Pieces) do
        if (FPieces.Pieces[i].Separator <> rsNone) and (FPieces.Pieces[i].Data <> nil) then
          ADoc.ReleaseData(TTyRichParaData(FPieces.Pieces[i].Data));
      FPieces := Default(TTyRichPieces);
      FUseText := True;
      t.WalkParaTexts(first, last, @TakePara, False);
    end;
    if FUseText then SetLength(FText, FTextLen);
  finally
    ADoc.EndRead;
  end;
end;

// a field opened in one paragraph taken and closed in another
function TTyRichRangeContent.FieldOverParagraphs: Boolean;
var
  opens: array of Integer;
  sp, i, j: Integer;
  runs: TTyRunArray;
  a, e: Int64;
begin
  opens := nil;
  sp := 0;
  for i := 0 to FCount - 1 do
  begin
    if FValues[i] = nil then Continue;
    runs := FDoc.RunsOfData(FValues[i]);
    if i = 0 then a := FFirstFrom else a := 0;
    e := a + FLens[i];
    for j := 0 to High(runs) do
      if (runs[j].Start >= a) and (runs[j].Start < e) and (runs[j].Obj is TTyRichFieldMark) then
        if TTyRichFieldMark(runs[j].Obj).Kind = rfmOpen then
        begin
          if sp = Length(opens) then SetLength(opens, sp * 2 + 8);
          opens[sp] := i;
          Inc(sp);
        end
        else if sp > 0 then
        begin
          Dec(sp);
          if opens[sp] <> i then Exit(True);
        end;
  end;
  Result := False;
end;

destructor TTyRichRangeContent.Destroy;
var
  i: Integer;
begin
  if FDoc <> nil then
  begin
    for i := 0 to High(FValues) do FDoc.ReleaseData(FValues[i]);
    for i := 0 to High(FPieces.Pieces) do
      if (FPieces.Pieces[i].Separator <> rsNone) and (FPieces.Pieces[i].Data <> nil) then
        FDoc.ReleaseData(TTyRichParaData(FPieces.Pieces[i].Data));
  end;
  inherited Destroy;
end;

procedure TTyRichRangeContent.TakePara(AIndex: Integer; AData: Pointer; AText: PByte;
  ALen: PtrInt; var AContinue: Boolean);
var
  v: TTyRichParaData;
  i: Integer;
  a, b, ch: Int64;
  p, q, n, j, need: PtrInt;
  dst: PAnsiChar;
begin
  v := TTyRichParaData(AData);
  // a paragraph a reader that parses on demand has not read yet: read now, and kept
  if (v = nil) and (FDoc.FLoader <> nil) then v := FDoc.DataOf(AIndex);
  i := AIndex - FFirst;
  FDoc.AcquireData(v);
  FValues[i] := v;
  // (taken from the pieces already)
  if not FUseText then Exit;
  if i = 0 then a := FFirstFrom else a := 0;
  if AIndex = FLast then b := FLastTo
  else if i = 0 then b := FFirstLen
  else b := FDoc.FText.ParaLength(AIndex);
  FLens[i] := b - a;
  // the characters [a, b) of the paragraph's bytes
  p := 0;
  ch := 0;
  while (ch < a) and (p < ALen) do
  begin
    Inc(p, Utf8SeqLen(AText[p]));
    Inc(ch);
  end;
  q := p;
  while (ch < b) and (q < ALen) do
  begin
    Inc(q, Utf8SeqLen(AText[q]));
    Inc(ch);
  end;
  if q > ALen then q := ALen;
  if p > q then p := q;
  need := FTextLen + (q - p) + 1;
  if need > Length(FText) then
  begin
    if need < 2 * Length(FText) then need := 2 * Length(FText);
    SetLength(FText, need + 16);
  end;
  if i > 0 then
  begin
    FText[FTextLen + 1] := #10;
    Inc(FTextLen);
  end;
  n := q - p;
  if n > 0 then
  begin
    Move(AText[p], FText[FTextLen + 1], n);
    // (a separator a paragraph's text should never hold: a space, as a fragment's text has it)
    dst := @FText[FTextLen + 1];
    for j := 0 to n - 1 do
      if dst[j] in [#10, #13] then dst[j] := ' ';
    Inc(FTextLen, n);
  end;
end;

constructor TTyRichFragment.CreateOfContent(ATarget: TTyRichDocument; APos: TTyRichPos;
  AContent: TTyRichRangeContent; AKeepObjects: Boolean);
var
  t: TTyRichText;
  k, i, j, n, made: Integer;
  o, a, full: Int64;
  cell, c: TTyRichCell;
  v: TTyRichParaData;
  runs, src: TTyRunArray;
begin
  inherited Create;
  if (ATarget = nil) or (AContent = nil) or (AContent.FDoc <> ATarget) then
    raise ETyRichModel.Create('A fragment of a document''s own content goes into that document');
  FDoc := ATarget;
  t := ATarget.FText;
  k := t.ParaOfPos(APos);   // range check
  o := APos - t.ParaStart(k);
  ATarget.BeginRead;
  try
    cell := ATarget.CellOfData(ATarget.DataOf(k));
    // a table goes into a table only as its text: there are no nested tables
    FFlat := cell <> nil;
    FFlatCell := cell;
    if AContent.FCount = 0 then Exit;
    FBody := not AContent.FUseText;
    if FBody then
    begin
      FBodyPieces := AContent.FPieces;
      for i := 0 to High(FBodyPieces.Pieces) do
        if (FBodyPieces.Pieces[i].Separator <> rsNone) and (FBodyPieces.Pieces[i].Data <> nil) then
          ATarget.AcquireData(TTyRichParaData(FBodyPieces.Pieces[i].Data));
    end
    else
    begin
      FText := AContent.FText;
      FTextLen := Length(FText);
    end;
    SetLength(FParts, AContent.FCount + 3);
    SetLength(FLens, AContent.FCount + 3);
    SetLength(FOwn, AContent.FCount + 3);
    try
      if not FFlat and not AContent.FInOneCell then OwnTables(AContent);
      for i := 0 to AContent.FCount - 1 do
      begin
        v := AContent.FValues[i];
        if FFlat then c := FFlatCell
        else if AContent.FInOneCell then c := nil
        else c := MapOwnCell(ATarget.CellOfData(v));
        // a plain paragraph (no format, run or object of its own) outside a table: the plain value
        if ((v = nil) or (v = ATarget.FPlainParsed)) and (c = nil) then
        begin
          AddPart(ATarget.PlainValue, AContent.FLens[i], False);
          Continue;
        end;
        src := ATarget.RunsOfData(v);
        if i = 0 then a := AContent.FFirstFrom else a := 0;
        if i = 0 then full := AContent.FFirstLen
        else if i = AContent.FCount - 1 then full := AContent.FLastLen
        else full := AContent.FLens[i];
        runs := nil;
        n := 0;
        AppendSlice(runs, n, src, full, a, a + AContent.FLens[i], -a);
        // (nothing of it taken - its end only: the format there)
        if n = 0 then AppendRun(runs, n, 0, src[RunIndexAt(src, a)].Format, nil);
        SetLength(runs, n);
        if not AKeepObjects then
        begin
          made := 0;
          try
            for j := 0 to n - 1 do
              if runs[j].Obj <> nil then
              begin
                runs[j].Obj := runs[j].Obj.Clone;
                made := j + 1;
              end;
          except
            // the clones made for this paragraph so far are no value's yet: they go
            for j := 0 to made - 1 do
              if runs[j].Obj <> nil then
              begin
                runs[j].Obj.AddRef;
                runs[j].Obj.Release;
              end;
            raise;
          end;
        end;
        AddPart(ATarget.MakeData(ATarget.FormatOfData(v), runs, c), AContent.FLens[i], False);
      end;
      if AContent.FEnds then
      begin
        // (a separator the range took is among its pieces already; its text has none)
        if not FBody or not AContent.FEndsInText then AddMark;
        AddPart(nil, 0, True);
      end;
      if not FFlat then
      begin
        // rows stay rows: the text before APos keeps its own paragraph, and a last row is
        // never joined with the text after APos
        if (o > 0) and (PartCell(0) <> nil) then InsertOwnFirst;
        if PartCell(FCount - 1) <> nil then
        begin
          AddMark;
          AddPart(nil, 0, True);
        end;
      end;
      if not FBody then SetLength(FText, FTextLen);
      if FFlatCell <> nil then UnfieldOverParagraphs;
    finally
      // a table made again was held while it was made: the values that use it hold theirs
      for i := 0 to FTabCount - 1 do
        if FTabNew[i] <> nil then FTabNew[i].Release;
      FTabSrc := nil;
      FTabNew := nil;
      FTabMin := nil;
      FTabCount := 0;
    end;
  finally
    ATarget.EndRead;
  end;
end;

{ The tables the content's paragraphs are in, each made again with the rows taken of it only
  (their cells, RawFormat and edges): a run of paragraphs of its own. A table one of whose
  rows taken holds a nested table goes in as paragraphs, as a fragment's does (nil). }
procedure TTyRichFragment.OwnTables(AContent: TTyRichRangeContent);
var
  i, j, lo, hi: Integer;
  c: TTyRichCell;
  src, nt: TTyRichTable;
  r: TTyRichRow;
  found: Boolean;
  maxs: array of Integer;
begin
  maxs := nil;
  for i := 0 to AContent.FCount - 1 do
  begin
    c := FDoc.CellOfData(AContent.FValues[i]);
    if c = nil then Continue;
    src := c.Table;
    found := False;
    for j := FTabCount - 1 downto 0 do
      if FTabSrc[j] = src then
      begin
        if c.FRow.FIndex < FTabMin[j] then FTabMin[j] := c.FRow.FIndex;
        if c.FRow.FIndex > maxs[j] then maxs[j] := c.FRow.FIndex;
        found := True;
        Break;
      end;
    if found then Continue;
    if FTabCount = Length(FTabSrc) then
    begin
      SetLength(FTabSrc, FTabCount * 2 + 4);
      SetLength(FTabNew, FTabCount * 2 + 4);
      SetLength(FTabMin, FTabCount * 2 + 4);
      SetLength(maxs, FTabCount * 2 + 4);
    end;
    FTabSrc[FTabCount] := src;
    FTabNew[FTabCount] := nil;
    FTabMin[FTabCount] := c.FRow.FIndex;
    maxs[FTabCount] := c.FRow.FIndex;
    Inc(FTabCount);
  end;
  for i := 0 to FTabCount - 1 do
  begin
    src := FTabSrc[i];
    lo := FTabMin[i];
    hi := maxs[i];
    found := False;
    for j := lo to hi do
      if src.FRows[j].FHoldsNestedTable then found := True;
    if found then Continue;
    nt := TTyRichTable.Create(src.FColBoundaries, src.FContentLocked);
    // held while the fragment is made (entered first: a failure while its rows are made lets
    // go of it too)
    nt.AddRef;
    FTabNew[i] := nt;
    for j := lo to hi do
    begin
      r := src.FRows[j];
      nt.AddRow(Length(r.FCells), r.FRawFormat, r.FBoundaries, False);
      nt.FRows[j - lo].SetFormats(r.BaseFormat, r.Format);
      nt.FRows[j - lo].FEdgesMoved := r.FEdgesMoved;
    end;
    nt.FRowsValid := src.FRowsValid;
  end;
end;

function TTyRichFragment.MapOwnCell(ACell: TTyRichCell): TTyRichCell;
var
  i: Integer;
begin
  Result := nil;
  if ACell = nil then Exit;
  for i := FTabCount - 1 downto 0 do
    if FTabSrc[i] = ACell.Table then
    begin
      if FTabNew[i] = nil then Exit;
      Exit(FTabNew[i].FRows[ACell.FRow.FIndex - FTabMin[i]].FCells[ACell.FIndex]);
    end;
end;

type
  // the fragment's parts between its first and last into the paragraphs the insert made
  TTyRichFragmentWalk = class
  public
    Doc: TTyRichDocument;
    Fragment: TTyRichFragment;
    First: Integer;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

function TTyRichFragment.MarksPaired: Boolean;
var
  i, j, depth: Integer;
begin
  depth := 0;
  for i := 0 to FCount - 1 do
    if FParts[i] <> nil then
      for j := 0 to High(FParts[i].FRuns) do
        if FParts[i].FRuns[j].Obj is TTyRichFieldMark then
          if TTyRichFieldMark(FParts[i].FRuns[j].Obj).Kind = rfmOpen then
            Inc(depth)
          else
          begin
            Dec(depth);
            if depth < 0 then Exit(False);
          end;
  Result := depth = 0;
end;

function TTyRichFragment.HoldsFields: Boolean;
var
  i, j: Integer;
begin
  for i := 0 to FCount - 1 do
    if FParts[i] <> nil then
    begin
      if FParts[i].FFieldDepth <> 0 then Exit(True);
      for j := 0 to High(FParts[i].FRuns) do
        if FParts[i].FRuns[j].Obj is TTyRichFieldMark then Exit(True);
    end;
  Result := False;
end;

function TTyRichFragmentWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  v: TTyRichParaData;
begin
  v := Fragment.FParts[AIndex - First];
  if Pointer(v) <> AData then
  begin
    Doc.AcquireData(v);
    Doc.ReleaseData(TTyRichParaData(AData));
  end;
  Result := v;
end;

function TTyRichDocument.InsertFragment(APos: TTyRichPos;
  AFragment: TTyRichFragment): TTyRichUndoData;
var
  c: TTyRichChange;
  k, s, n1, n2, last, kb, sb, i: Integer;
  d, part: TTyRichParaData;
  r, pr, runs1, runs2: TTyRunArray;
  ps, o, len, plen, added, oldChars, p: Int64;
  lb: UTF8String;
  f: TTyCharFormatId;
  fmt: TTyParaFormatId;
  cell: TTyRichCell;
  oldCount: Integer;
  txt: UTF8String;
  w: TTyRichFragmentWalk;
  e: ETyRichRefused;
begin
  if AFragment = nil then
    raise ETyRichModel.Create('InsertFragment needs a fragment');
  if AFragment.FDoc <> Self then
    raise ETyRichModel.Create('The fragment was made for another document');
  c := Default(TTyRichChange);
  c.Pos := APos;
  FText.ParaOfPos(APos);   // range check before anything changes
  if AFragment.FCount = 0 then Exit(NewUndo(c));
  RaiseRefused(APos, 0);
  if not AFragment.MarksPaired then
  begin
    // a mark whose partner the fragment lacks would leave a field with one edge
    e := ETyRichRefused.Create(rsRichEditRefusedField);
    e.Field := True;
    raise e;
  end;
  if AFragment.FHavePieces then txt := '' else txt := WithBreaks(AFragment.FText, FDominantLineBreak);
  k := FText.ParaOfPos(APos);
  d := DataOf(k);
  r := RunsOfData(d);
  ps := FText.ParaStart(k);
  o := APos - ps;
  len := FText.ParaLength(k);
  f := InheritedFormat(r, o);
  fmt := FormatOfData(d);
  cell := CellOfData(d);
  last := AFragment.FCount - 1;
  oldChars := FText.Length;
  oldCount := FText.ParaCount;
  Result := NewUndo(c);
  try
    Result.FFirstPara := k;
    Result.AddOld(d);
    Result.SealOld;
    Result.FSpan := FText.PieceSpan(APos, APos);
    if AFragment.FHavePieces then
    begin
      // again (a redo): the very bytes of the first insert, still in the add buffer
      Inc(FEditing);
      try
        FText.RestorePieces(APos, AFragment.FPieces);
      finally
        Dec(FEditing);
      end;
    end
    else if AFragment.FBody then
    begin
      { A document's own content: its pieces go in where it goes - the text is not copied -,
        with this document's paragraph marks around them; the paragraphs they make get
        their values below (the separators came with the values of the paragraphs they
        ended: none is counted for them, the slots are emptied first). }
      lb := WithBreaks(#10, FDominantLineBreak);
      Inc(FEditing);
      try
        p := APos;
        if AFragment.FLead then
        begin
          if AFragment.FBodyRan then
            FText.RestorePieces(p, AFragment.FLeadPieces)
          else
          begin
            FText.Insert(p, lb);
            AFragment.FLeadPieces := FText.PieceSnapshot(p, 1);
          end;
          Inc(p);
        end;
        if AFragment.FBodyPieces.CharCount > 0 then
        begin
          sb := 0;
          for i := 0 to High(AFragment.FBodyPieces.Pieces) do
            if AFragment.FBodyPieces.Pieces[i].Separator <> rsNone then Inc(sb);
          kb := FText.ParaOfPos(p);
          FText.RestorePieces(p, AFragment.FBodyPieces);
          if sb > 0 then FText.MapParaData(kb + 1, kb + sb, @NoDataMap);
          Inc(p, AFragment.FBodyPieces.CharCount);
        end;
        if AFragment.FTrail > 0 then
        begin
          if AFragment.FBodyRan then
            FText.RestorePieces(p, AFragment.FTrailPieces)
          else
          begin
            for i := 1 to AFragment.FTrail do FText.Insert(p + i - 1, lb);
            AFragment.FTrailPieces := FText.PieceSnapshot(p, AFragment.FTrail);
          end;
        end;
        { The body stays the fragment's: a redo puts the same pieces in again (no snapshot of
          what went in - the pieces are the body's, a move's delete keeps that very array). }
        AFragment.FBodyRan := True;
      finally
        Dec(FEditing);
      end;
    end
    else if txt <> '' then
    begin
      Inc(FEditing);
      try
        FText.Insert(APos, txt);
        // (taken before any paragraph value is put: the separators hand out no data)
        AFragment.FPieces := FText.PieceSnapshot(APos, FText.Length - oldChars);
        AFragment.FHavePieces := True;
        // the text itself is no longer needed (its bytes are counted still: MemSize)
        AFragment.FTextBytes := Length(AFragment.FText);
        AFragment.FText := '';
      finally
        Dec(FEditing);
      end;
    end;
    added := FText.Length - oldChars;
    s := FText.ParaCount - oldCount;
    if s <> last then
      raise ETyRichModel.CreateFmt('A fragment of %d parts made %d paragraphs', [last + 1, s + 1]);
    runs1 := nil;
    n1 := 0;
    // the text before APos keeps its runs
    AppendSlice(runs1, n1, r, len, 0, o, 0);
    part := AFragment.FParts[0];
    plen := AFragment.FLens[0];
    if not AFragment.FOwn[0] then
    begin
      pr := RunsOfData(part);
      AppendSlice(runs1, n1, pr, plen, 0, plen, o);
      if n1 = 0 then AppendRun(runs1, n1, 0, pr[0].Format, nil);
    end;
    if last = 0 then
    begin
      // inline: one paragraph, its own format and cell, the text after APos follows
      AppendSlice(runs1, n1, r, len, o, len, plen);
      if n1 = 0 then AppendRun(runs1, n1, 0, f, nil);
      SetLength(runs1, n1);
      PutData(k, d, MakeDataLike(fmt, runs1, cell, d));
    end
    else
    begin
      if n1 = 0 then AppendRun(runs1, n1, 0, f, nil);
      SetLength(runs1, n1);
      // the paragraph that ends with the fragment's first mark has that paragraph's format
      if AFragment.FOwn[0] then PutData(k, d, MakeDataLike(fmt, runs1, cell, d))
      // (a format of the fragment: not the file's list marker of the paragraph it was)
      else PutData(k, d, MakeData(FormatOfData(part), runs1, CellOfData(part)));
      if last > 1 then
      begin
        w := TTyRichFragmentWalk.Create;
        try
          w.Doc := Self;
          w.Fragment := AFragment;
          w.First := k;
          FText.MapParaData(k + 1, k + last - 1, @w.Map);
        finally
          w.Free;
        end;
      end;
      // the last part and the text after APos: this document's mark, its format and cell
      runs2 := nil;
      n2 := 0;
      part := AFragment.FParts[last];
      plen := AFragment.FLens[last];
      if not AFragment.FOwn[last] then
        AppendSlice(runs2, n2, RunsOfData(part), plen, 0, plen, 0);
      AppendSlice(runs2, n2, r, len, o, len, plen - o);
      if n2 = 0 then
      begin
        if AFragment.FOwn[last] then AppendRun(runs2, n2, 0, f, nil)
        else AppendRun(runs2, n2, 0, RunsOfData(part)[0].Format, nil);
      end;
      SetLength(runs2, n2);
      PutData(k + last, SlotData(k + last), MakeData(fmt, runs2, cell));
    end;
    { The paragraphs it made start as deep in fields as the text before them leaves (the
      fragment's fields are whole and it goes in outside every field: the paragraph after
      it is as deep as before); the first one where k did. With no field in it every
      paragraph after the first starts outside every field already: only the first. }
    if AFragment.HoldsFields then FixDepths(k, k + last, DepthOfData(d))
    else FixDepths(k, k, DepthOfData(d));
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckText];
  if s > 0 then c.Kinds := c.Kinds + [rckStructure, rckFormat];
  c.NewLen := added;
  Result.FInserted := added;
  c.FirstPara := k;
  c.OldParaCount := 1;
  c.NewParaCount := 1 + s;
  Result.FChange := c;
  Notify(c);
end;

procedure TTyRichDocument.Revert(var AUndo: TTyRichUndoData);
var
  u: TTyRichUndoData;
  c: TTyRichChange;
  i, total: Integer;
  w: TTyRichRevertWalk;
begin
  u := AUndo;
  if u = nil then Exit;
  if u.FDoc <> Self then
    raise ETyRichModel.Create('Undo data of another document');
  AUndo := nil;
  if Length(u.FParts) > 0 then
  begin
    // the edits it is made of, newest first; each reports what it puts back
    try
      for i := High(u.FParts) downto 0 do Revert(u.FParts[i]);
    finally
      u.Free;
    end;
    Exit;
  end;
  try
    Inc(FEditing);
    try
      if u.FHasSettings then
      begin
        PutSettings(u.FSettings);
        // the shared plain value follows the defaults again, as before the change froze it
        if u.FFroze then
        begin
          FPlainFrozen := False;
          if FPlainParsed <> nil then
          begin
            FPlainParsed.FRuns := nil;
            FPlainParsed.FParaFormat := FDefaultParaId;
          end;
        end;
      end;
      if u.FRowTable <> nil then RevertRows(u);
      if u.FSwapCount > 0 then RevertSwaps(u);
      if u.FInserted > 0 then
        FText.Delete(u.FChange.Pos, u.FInserted);
      if u.FRemoved.CharCount > 0 then
      begin
        // the restored separators put these values back in slots: the slots' references
        for i := 0 to High(u.FRemoved.Pieces) do
          if (u.FRemoved.Pieces[i].Separator <> rsNone) and (u.FRemoved.Pieces[i].Data <> nil) then
            AcquireData(TTyRichParaData(u.FRemoved.Pieces[i].Data));
        FText.RestorePieces(u.FChange.Pos, u.FRemoved);
      end;
      { The text is what it was where the change split it: its pieces too (a decoded lazy
        paragraph lazy again). }
      if (Length(u.FSpan2.Pieces.Pieces) > 0) or u.FSpan2.LazyTail then FText.RestoreSpan(u.FSpan2);
      if (Length(u.FSpan.Pieces.Pieces) > 0) or u.FSpan.LazyTail then FText.RestoreSpan(u.FSpan);
      if u.FOldCount > 0 then
      begin
        total := 0;
        for i := 0 to u.FOldCount - 1 do Inc(total, u.FOldData[i].Count);
        w := TTyRichRevertWalk.Create;
        try
          w.Doc := Self;
          w.Undo := u;
          w.Run := 0;
          w.Left := u.FOldData[0].Count;
          FText.MapParaData(u.FFirstPara, u.FFirstPara + total - 1, @w.Map);
        finally
          w.Free;
        end;
      end;
    finally
      Dec(FEditing);
    end;
    if u.FChange.Kinds <> [] then
    begin
      c := u.FChange;
      c.OldLen := u.FChange.NewLen;
      c.NewLen := u.FChange.OldLen;
      c.OldParaCount := u.FChange.NewParaCount;
      c.NewParaCount := u.FChange.OldParaCount;
      Notify(c);
    end;
  finally
    u.Free;
  end;
end;

{ ---- TTyRichCommand ---- }

procedure TTyRichCommand.BeforeDestruction;
var
  h: TNotifyEvent;
begin
  // (before any destructor's body: the command is still whole for who hears of it)
  h := FOnFreed;
  FOnFreed := nil;
  if Assigned(h) then h(Self);
  inherited BeforeDestruction;
end;

destructor TTyRichCommand.Destroy;
begin
  FreeRecords;
  inherited Destroy;
end;

procedure TTyRichCommand.Covered;
begin
end;

procedure TTyRichCommand.FreeRecords;
begin
  while FRecordCount > 0 do
  begin
    Dec(FRecordCount);
    FRecords[FRecordCount].Free;
    FRecords[FRecordCount] := nil;
  end;
  FRecords := nil;
end;

procedure TTyRichCommand.CheckRunning(ADoc: TTyRichDocument);
begin
  // the guarantee that every change is in the history: a command changes a document only
  // while that document runs it
  if (ADoc = nil) or (FDoc <> ADoc) then
    raise ETyRichModel.CreateFmt('%s changes a document only while the document runs it',
      [ClassName]);
end;

procedure TTyRichCommand.AddSummary(const AChange: TTyRichChange);
begin
  ComposeChange(FSummary, FChanged, AChange);
end;

procedure TTyRichCommand.ResetSummary;
begin
  FSummary := Default(TTyRichChange);
  FChanged := False;
end;

function TTyRichCommand.Keep(AUndo: TTyRichUndoData): TTyRichChange;
begin
  Result := AUndo.Change;
  if Result.Kinds = [] then
  begin
    // a no-op: nothing to put back
    AUndo.Free;
    Exit;
  end;
  if FRecordCount = Length(FRecords) then SetLength(FRecords, FRecordCount * 2 + 2);
  FRecords[FRecordCount] := AUndo;
  Inc(FRecordCount);
  AddSummary(Result);
end;

procedure TTyRichCommand.DoUndo(ADoc: TTyRichDocument);
begin
  // newest first: each record was made on the document the later ones changed again
  while FRecordCount > 0 do
  begin
    Dec(FRecordCount);
    ADoc.Revert(FRecords[FRecordCount]);
  end;
end;

procedure TTyRichCommand.DoRedo(ADoc: TTyRichDocument);
begin
  DoExecute(ADoc);
end;

function TTyRichCommand.InsertText(ADoc: TTyRichDocument; APos: TTyRichPos;
  const AText: UTF8String; AFormat: TTyCharFormatId): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.InsertText(APos, AText, AFormat));
end;

function TTyRichCommand.InsertObject(ADoc: TTyRichDocument; APos: TTyRichPos;
  AObject: TTyRichObject; AFormat: TTyCharFormatId): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.InsertObject(APos, AObject, AFormat));
end;

type
  { A bookmark's end in a deletion's range that its other end is not in. Keep: it stays where
    it is (the range's stretches around it go); else (in a field's result or a table cell,
    where the stretches cannot be cut) it goes with the range and comes back at the range's
    place - Obj, held. }
  TTyRichLoneEnd = record
    Pos: TTyRichPos;
    Keep: Boolean;
    Obj: TTyRichBookmarkMark;
  end;
  TTyRichLoneEnds = array of TTyRichLoneEnd;

  { A mark the range holds, as its pairing needs it: from a paragraph's value (Pos and Obj
    known) or from the load's index (Entry: its paragraph Para is not parsed). }
  TTyRichRangeMark = record
    Kind: TTyRichBookmarkKind;
    Hash: Cardinal;
    Pos: TTyRichPos;
    Obj: TTyRichBookmarkMark;
    Entry, Para: Integer;
  end;

  { The paragraphs of a deletion: the marks of those that have a value, and the file offsets
    of the unparsed ones (the index tells of their marks). }
  TTyRichBkmWalk = class
  public
    Doc: TTyRichDocument;
    Last: Integer;
    From, Stop: TTyRichPos;
    Marks: array of TTyRichRangeMark;
    MarkN: Integer;
    LazySrc: array of Int64;
    LazyPara: array of Integer;
    LazyN: Integer;
    procedure Visit(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    procedure AddMark(const M: TTyRichRangeMark);
  end;

procedure TTyRichBkmWalk.AddMark(const M: TTyRichRangeMark);
begin
  if MarkN = Length(Marks) then SetLength(Marks, MarkN * 2 + 8);
  Marks[MarkN] := M;
  Inc(MarkN);
end;

procedure TTyRichBkmWalk.Visit(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
  var AContinue: Boolean);
var
  d: TTyRichParaData;
  i: Integer;
  ps, p: TTyRichPos;
  m: TTyRichRangeMark;
begin
  if AIndex > Last then
  begin
    AContinue := False;
    Exit;
  end;
  d := TTyRichParaData(AData);
  if d <> nil then
  begin
    ps := -1;
    for i := 0 to High(d.FRuns) do
      if d.FRuns[i].Obj is TTyRichBookmarkMark then
      begin
        if ps < 0 then ps := Doc.FText.ParaStart(AIndex);
        p := ps + d.FRuns[i].Start;
        if (p < From) or (p >= Stop) then Continue;
        m.Obj := TTyRichBookmarkMark(d.FRuns[i].Obj);
        m.Kind := m.Obj.Kind;
        m.Hash := TyRichBookmarkHash(m.Obj.Name);
        m.Pos := p;
        m.Entry := -1;
        m.Para := AIndex;
        AddMark(m);
      end;
  end
  else if ASrcOffset >= 0 then
  begin
    // (in order: lazy paragraphs keep the file's order)
    if LazyN = Length(LazySrc) then
    begin
      SetLength(LazySrc, LazyN * 2 + 64);
      SetLength(LazyPara, LazyN * 2 + 64);
    end;
    LazySrc[LazyN] := ASrcOffset;
    LazyPara[LazyN] := AIndex;
    Inc(LazyN);
  end;
end;

{ The bookmark ends in [APos, APos + ALen) whose other end is not in it, rising. Decided from
  the paragraphs' values and, for the unparsed paragraphs of a file read on demand, from the
  load's index alone (kind and name's hash), counted by hash in a table (TTyRichHashCounts);
  only a paragraph that holds an end of a hash left unpaired is parsed (its places and objects
  are needed), and an edge the range cuts when the index has a mark in it. A hash is no name:
  the ends found are paired again by their names. }
function LoneBookmarkEnds(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): TTyRichLoneEnds;
var
  w: TTyRichBkmWalk;
  i, j, k, m, n, lo, hi, mid, para: Integer;
  ld: TTyRichParaLoader;
  kind: TTyRichBookmarkKind;
  h: Cardinal;
  psrc, gsrc: Int64;
  pairs: TTyRichHashCounts;
  v: Int64;
  mk: TTyRichRangeMark;
  lone: array of TTyRichRangeMark;
  loneN: Integer;
  parsed: specialize TDictionary<Integer, Boolean>;
  names: specialize TDictionary<UTF8String, Int64>;
  key: UTF8String;
  kPart, mPart, kNeed, mNeed: Boolean;
  stop: TTyRichPos;
  oddN: Integer;

  // one end more of hash AHash: oddN counts the hashes whose starts and ends differ
  procedure Count(AHash: Cardinal; AKind: TTyRichBookmarkKind);
  var
    now, was: Int64;
    d: Int64;
  begin
    if AKind = rbmStart then d := Int64(1) shl 32 else d := 1;
    now := pairs.Add(AHash, d);
    was := now - d;
    if ((was shr 32) = (was and $FFFFFFFF)) <> ((now shr 32) = (now and $FFFFFFFF)) then
      if (now shr 32) = (now and $FFFFFFFF) then Dec(oddN) else Inc(oddN);
  end;

  // the marks of paragraph APara in the range, from its value (parsed if it is not)
  procedure AddValueMarks(APara: Integer);
  var
    rr: TTyRunArray;
    q, s0: TTyRichPos;
    t: Integer;
    one: TTyRichRangeMark;
  begin
    rr := ADoc.RunsOf(APara);
    s0 := ADoc.FText.ParaStart(APara);
    for t := 0 to High(rr) do
      if rr[t].Obj is TTyRichBookmarkMark then
      begin
        q := s0 + rr[t].Start;
        if (q < APos) or (q >= APos + ALen) then Continue;
        one.Obj := TTyRichBookmarkMark(rr[t].Obj);
        one.Kind := one.Obj.Kind;
        one.Hash := TyRichBookmarkHash(one.Obj.Name);
        one.Pos := q;
        one.Entry := -1;
        one.Para := APara;
        w.AddMark(one);
      end;
  end;

  procedure AddLone(const AMark: TTyRichRangeMark);
  begin
    if loneN = Length(lone) then SetLength(lone, loneN * 2 + 4);
    lone[loneN] := AMark;
    Inc(loneN);
  end;

  function Unpaired(AHash: Cardinal): Boolean;
  var
    c: Int64;
  begin
    Result := pairs.TryGet(AHash, c) and ((c shr 32) <> (c and $FFFFFFFF));
  end;

  { The index's marks of the range's unparsed paragraphs (the edges the range cuts left to
    their values): APass 1 counts them; 2 parses, once, each paragraph that holds one of an
    unpaired hash and takes its unpaired ends. }
  procedure IndexMarks(APass: Integer);
  var
    t, x, y: Integer;
    rr: TTyRunArray;
    s0, q: TTyRichPos;
    bm: TTyRichBookmarkMark;
    one: TTyRichRangeMark;
    hh: Cardinal;
  begin
    x := 0;
    for t := lo to n - 1 do
    begin
      ld.BookmarkIndexEntry(t, kind, h, psrc, gsrc);
      while (x < w.LazyN) and (w.LazySrc[x] < psrc) do Inc(x);
      if (x >= w.LazyN) or (w.LazySrc[x] <> psrc) then Continue;
      para := w.LazyPara[x];
      if ((para = k) and kPart) or ((para = m) and mPart) then
      begin
        if para = k then kNeed := True else mNeed := True;
        Continue;
      end;
      if APass = 1 then
      begin
        Count(h, kind);
        Continue;
      end;
      if not Unpaired(h) or parsed.ContainsKey(para) then Continue;
      parsed.Add(para, True);
      rr := ADoc.RunsOf(para);
      s0 := ADoc.FText.ParaStart(para);
      for y := 0 to High(rr) do
        if rr[y].Obj is TTyRichBookmarkMark then
        begin
          bm := TTyRichBookmarkMark(rr[y].Obj);
          q := s0 + rr[y].Start;
          if (q < APos) or (q >= APos + ALen) then Continue;
          hh := TyRichBookmarkHash(bm.Name);
          if not Unpaired(hh) then Continue;
          one.Kind := bm.Kind;
          one.Hash := hh;
          one.Pos := q;
          one.Obj := bm;
          one.Entry := t;
          one.Para := para;
          AddLone(one);
        end;
    end;
  end;

begin
  Result := nil;
  if (ALen <= 0) or (APos < 0) or (APos + ALen > ADoc.FText.Length) then Exit;
  k := ADoc.FText.ParaOfPos(APos);
  m := ADoc.FText.ParaOfPos(APos + ALen - 1);
  ld := ADoc.FLoader;
  if (ld <> nil) and (ld.BookmarkIndexCount < 0) then ld := nil;
  w := TTyRichBkmWalk.Create;
  pairs := nil;
  parsed := nil;
  names := nil;
  lone := nil;
  loneN := 0;
  ADoc.BeginRead;
  try
    { The edges: one the range holds a part of only, when it is unparsed and holds a mark (the
      index says), is parsed - its marks' places tell which are in the range }
    kPart := APos > ADoc.FText.ParaStart(k);
    // (its separator is no mark: up to its text's end, it is whole)
    stop := ADoc.FText.ParaStart(m) + ADoc.FText.ParaLength(m);
    mPart := APos + ALen < stop;
    kNeed := False;
    mNeed := False;
    w.Doc := ADoc;
    w.Last := m;
    w.From := APos;
    w.Stop := APos + ALen;
    ADoc.FText.WalkParas(k, @w.Visit);
    n := 0;
    lo := 0;
    oddN := 0;
    if (ld <> nil) and (w.LazyN > 0) then
    begin
      { the index's entries of the range's unparsed paragraphs (rising by offset): from the
        first one's first [lo, n) }
      hi := ld.BookmarkIndexCount;
      while lo < hi do
      begin
        mid := (lo + hi) shr 1;
        ld.BookmarkIndexEntry(mid, kind, h, psrc, gsrc);
        if psrc < w.LazySrc[0] then lo := mid + 1 else hi := mid;
      end;
      n := lo;
      hi := ld.BookmarkIndexCount;
      while n < hi do
      begin
        mid := (n + hi) shr 1;
        ld.BookmarkIndexEntry(mid, kind, h, psrc, gsrc);
        if psrc <= w.LazySrc[w.LazyN - 1] then n := mid + 1 else hi := mid;
      end;
    end
    else if w.LazyN > 0 then
      // (no index: each unparsed paragraph's own marks)
      for i := 0 to w.LazyN - 1 do AddValueMarks(w.LazyPara[i]);
    // (about two ends a name)
    pairs := TTyRichHashCounts.Create(w.MarkN + (n - lo) div 2 + 16);
    if n > lo then IndexMarks(1);
    if kNeed then AddValueMarks(k);
    if mNeed and (m <> k) then AddValueMarks(m);
    // paired by name's hash: starts in the high half, ends in the low
    for i := 0 to w.MarkN - 1 do Count(w.Marks[i].Hash, w.Marks[i].Kind);
    // every hash paired (a range that holds whole bookmarks): nothing more to look at
    if oddN = 0 then Exit;
    // the ends of an unpaired hash: the values' as they are, the index's from their paragraph
    for i := 0 to w.MarkN - 1 do
      if Unpaired(w.Marks[i].Hash) then AddLone(w.Marks[i]);
    parsed := specialize TDictionary<Integer, Boolean>.Create;
    if n > lo then IndexMarks(2);
    if loneN = 0 then Exit;
    { Paired again by the names themselves: two names of one hash that are both whole in the
      range are no lone ends }
    names := specialize TDictionary<UTF8String, Int64>.Create;
    for i := 0 to loneN - 1 do
    begin
      key := UTF8UpperCase(lone[i].Obj.Name);
      if not names.TryGetValue(key, v) then v := 0;
      if lone[i].Kind = rbmStart then Inc(v, Int64(1) shl 32) else Inc(v);
      names.AddOrSetValue(key, v);
    end;
    j := 0;
    for i := 0 to loneN - 1 do
    begin
      v := names[UTF8UpperCase(lone[i].Obj.Name)];
      if (v shr 32) = (v and $FFFFFFFF) then Continue;
      lone[j] := lone[i];
      Inc(j);
    end;
    loneN := j;
    // rising by place (the values' and the index's come in two lists)
    for i := 1 to loneN - 1 do
    begin
      mk := lone[i];
      j := i - 1;
      while (j >= 0) and (lone[j].Pos > mk.Pos) do
      begin
        lone[j + 1] := lone[j];
        Dec(j);
      end;
      lone[j + 1] := mk;
    end;
    SetLength(Result, loneN);
    for i := 0 to loneN - 1 do
    begin
      Result[i].Pos := lone[i].Pos;
      Result[i].Obj := lone[i].Obj;
      para := ADoc.FText.ParaOfPos(lone[i].Pos);
      Result[i].Keep := (ADoc.DepthAt(lone[i].Pos) = 0) and (ADoc.CellAt(para) = nil);
      // (held: it may go with the range and come back)
      Result[i].Obj.AddRef;
    end;
  finally
    ADoc.EndRead;
    names.Free;
    parsed.Free;
    pairs.Free;
    w.Free;
  end;
end;

function TTyRichCommand.DeleteRange(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): TTyRichChange;
var
  ends: TTyRichLoneEnds;
  e: TTyRichPos;
  i: Integer;
begin
  CheckRunning(ADoc);
  ends := LoneBookmarkEnds(ADoc, APos, ALen);
  if Length(ends) = 0 then
  begin
    Result := Keep(ADoc.DeleteRange(APos, ALen));
    Exit;
  end;
  try
    { A bookmark one of whose ends is in the range and the other not keeps both: it collapses
      to the place where the text was, as in Word. The stretches between such ends go, the
      last first (the places before them stay where they are); an end that cannot stay where
      it is (in a field's result, in a table cell) goes with them and comes back at the
      range's place - no deletion leaves a lone end. }
    Result := Default(TTyRichChange);
    e := APos + ALen;
    for i := High(ends) downto 0 do
    begin
      if not ends[i].Keep then Continue;
      if e > ends[i].Pos + 1 then
        Result := Keep(ADoc.DeleteRange(ends[i].Pos + 1, e - ends[i].Pos - 1));
      e := ends[i].Pos;
    end;
    if e > APos then Result := Keep(ADoc.DeleteRange(APos, e - APos));
    // the ones that went: at the range's place, in their order
    for i := High(ends) downto 0 do
      if not ends[i].Keep and ADoc.CanChange(APos, 0) then
        Result := Keep(ADoc.InsertCore(APos, TyRichObjectChar, TyRichInheritFormat, ends[i].Obj));
  finally
    for i := 0 to High(ends) do ends[i].Obj.Release;
  end;
end;

function TTyRichCommand.DeleteRange(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
  const APieces: TTyRichPieces): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.DeleteKnownRange(APos, ALen, APieces));
end;

function TTyRichCommand.ApplyCharFormat(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
  AMask: TTyCharFormatMask; const AValue: TTyCharFormat;
  AKeepNone: TTyCharFormatMask): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ApplyCharFormat(APos, ALen, AMask, AValue, AKeepNone));
end;

function TTyRichCommand.ApplyParaFormat(ADoc: TTyRichDocument; AFirstPara, ALastPara: Integer;
  AMask: TTyParaFormatMask; const AValue: TTyParaFormat): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ApplyParaFormat(AFirstPara, ALastPara, AMask, AValue));
end;

function TTyRichCommand.MarkTable(ADoc: TTyRichDocument; AFirstPara: Integer;
  ATable: TTyRichTable; const ACellParas: array of Integer): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.MarkTable(AFirstPara, ATable, ACellParas));
end;

function TTyRichCommand.InsertFragment(ADoc: TTyRichDocument; APos: TTyRichPos;
  AFragment: TTyRichFragment): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.InsertFragment(APos, AFragment));
end;

function TTyRichCommand.ReplaceInParas(ADoc: TTyRichDocument; const APos: array of TTyRichPos;
  AFrom, ACount: Integer; ALen: TTyRichPos; const AText: UTF8String;
  out ASkipped: Integer): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ReplaceInParas(APos, AFrom, ACount, ALen, AText, ASkipped));
end;

function TTyRichCommand.EditTable(ADoc: TTyRichDocument; const AEdit: TTyRichTableEdit;
  var ATables: TTyRichTables): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.EditTable(AEdit, ATables));
end;

function TTyRichCommand.EditTableProps(ADoc: TTyRichDocument;
  const AEdit: TTyRichPropEdit): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.EditTableProps(AEdit));
end;

function TTyRichCommand.ReplaceObject(ADoc: TTyRichDocument; APos: TTyRichPos;
  AObject: TTyRichObject): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ReplaceObject(APos, AObject));
end;

function TTyRichCommand.ChangeSettings(ADoc: TTyRichDocument;
  const ASettings: TTyRichDocSettings): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ChangeSettings(ASettings));
end;

procedure TTyRichCommand.DoContinue(ADoc: TTyRichDocument);
begin
  raise ETyRichModel.CreateFmt('%s does not go on in parts', [ClassName]);
end;

function TTyRichCommand.RecordsSize(AFrom: Integer): Int64;
var
  i: Integer;
begin
  Result := 0;
  if AFrom < 0 then AFrom := 0;
  for i := AFrom to FRecordCount - 1 do Inc(Result, FRecords[i].MemSize);
end;

procedure TTyRichCommand.AdoptChange(AChild: TTyRichCommand);
begin
  if AChild.FChanged then AddSummary(AChild.FSummary);
end;

procedure TTyRichCommand.ExecuteChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
begin
  CheckRunning(ADoc);
  AChild.FreeRecords;
  AChild.ResetSummary;
  AChild.FDoc := ADoc;
  try
    try
      AChild.DoExecute(ADoc);
    except
      // what the child did so far goes back before the error travels on
      try
        AChild.DoUndo(ADoc);
      except
      end;
      raise;
    end;
  finally
    AChild.FDoc := nil;
  end;
  AdoptChange(AChild);
end;

procedure TTyRichCommand.UndoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
begin
  CheckRunning(ADoc);
  AChild.FDoc := ADoc;
  try
    AChild.DoUndo(ADoc);
  finally
    AChild.FDoc := nil;
  end;
  // records a DoUndo override left are stale: redo runs the child again
  AChild.FreeRecords;
end;

procedure TTyRichCommand.RedoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
begin
  CheckRunning(ADoc);
  AChild.FreeRecords;
  AChild.ResetSummary;
  AChild.FDoc := ADoc;
  try
    try
      AChild.DoRedo(ADoc);
    except
      try
        AChild.DoUndo(ADoc);
      except
      end;
      raise;
    end;
  finally
    AChild.FDoc := nil;
  end;
  AdoptChange(AChild);
end;

procedure TTyRichCommand.TakeOver(ANext: TTyRichCommand);
var
  i: Integer;
begin
  for i := 0 to ANext.FRecordCount - 1 do
  begin
    if FRecordCount = Length(FRecords) then SetLength(FRecords, FRecordCount * 2 + 2);
    FRecords[FRecordCount] := ANext.FRecords[i];
    Inc(FRecordCount);
    ANext.FRecords[i] := nil;
  end;
  ANext.FRecordCount := 0;
  AdoptChange(ANext);
  // the merged step ends where ANext left the view (it begins where this one began)
  FMarks.HasAfter := ANext.FMarks.HasAfter;
  FMarks.After := ANext.FMarks.After;
end;

function TTyRichCommand.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := True;
end;

function TTyRichCommand.TryMerge(ANext: TTyRichCommand): Boolean;
begin
  Result := False;
end;

function TTyRichCommand.Description: string;
begin
  Result := rsRichUndoEdit;
end;

function TTyRichCommand.ChangedRange: TTyRichRange;
begin
  Result.Pos := FSummary.Pos;
  Result.Len := FSummary.NewLen;
end;

function TTyRichCommand.MemSize: Int64;
var
  i: Integer;
begin
  Result := InstanceSize + Length(FRecords) * SizeOf(Pointer);
  for i := 0 to FRecordCount - 1 do Inc(Result, FRecords[i].MemSize);
end;

procedure TTyRichCommand.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
var
  i: Integer;
begin
  for i := 0 to FRecordCount - 1 do FRecords[i].GatherObjects(AList, ACount);
end;

{ ---- the history's objects ---- }

{ AEntry's command's objects, each distinct one held once by this step; an object no other
  step held yet adds its bytes to the history's. Sorted by address to find the distinct ones:
  no walk of the other steps. }
{ AList[0..ACount) sorted by address and its duplicates gone: the distinct count. }
function SortDistinct(var AList: TTyRichObjectList; ACount: Integer): Integer;
var
  i, j: Integer;
  t: TTyRichObject;
begin
  // insertion sort of the few, merge-free: steps hold few objects as a rule
  if ACount > 1 then
    if ACount <= 32 then
    begin
      for i := 1 to ACount - 1 do
      begin
        t := AList[i];
        j := i;
        while (j > 0) and (PtrUInt(AList[j - 1]) > PtrUInt(t)) do
        begin
          AList[j] := AList[j - 1];
          Dec(j);
        end;
        AList[j] := t;
      end;
    end
    else
      SortObjects(AList, 0, ACount - 1);
  Result := 0;
  for i := 0 to ACount - 1 do
    if (Result = 0) or (AList[Result - 1] <> AList[i]) then
    begin
      AList[Result] := AList[i];
      Inc(Result);
    end;
end;

procedure TTyRichDocument.BeginGather(const ASkip: array of Int64);
var
  i: Integer;
begin
  if FKeyMet = nil then FKeyMet := TTyRichKeySet.Create else FKeyMet.Clear;
  for i := 0 to High(ASkip) do FKeyMet.AddOrSetValue(ASkip[i], True);
  FGatherKeys := nil;
  FGatherKeyCount := 0;
  FGathering := True;
end;

function TTyRichDocument.EndGather: TTyRichKeyList;
begin
  FGathering := False;
  Result := FGatherKeys;
  SetLength(Result, FGatherKeyCount);
  FGatherKeys := nil;
  FGatherKeyCount := 0;
end;

function TTyRichDocument.MeetKey(AKey: Int64): Boolean;
begin
  Result := not FKeyMet.ContainsKey(AKey);
  if not Result then Exit;
  FKeyMet.Add(AKey, True);
  if FGatherKeyCount = Length(FGatherKeys) then SetLength(FGatherKeys, FGatherKeyCount * 2 + 4);
  FGatherKeys[FGatherKeyCount] := AKey;
  Inc(FGatherKeyCount);
end;

procedure TTyRichDocument.HoldObjects(var AEntry: TTyRichHistoryEntry);
var
  list: TTyRichObjectList;
  n, i, k, c: Integer;
begin
  list := nil;
  n := 0;
  // (values that share a key - a merged run of typing's - are walked once)
  BeginGather([]);
  try
    AEntry.Cmd.GatherObjects(list, n);
  finally
    AEntry.Keys := EndGather;
  end;
  k := SortDistinct(list, n);
  SetLength(list, k);
  AEntry.Objs := list;
  if FObjHolds = nil then FObjHolds := TTyRichObjHolds.Create;
  for i := 0 to k - 1 do
  begin
    if FObjHolds.TryGetValue(list[i], c) then
      FObjHolds[list[i]] := c + 1
    else
    begin
      FObjHolds.Add(list[i], 1);
      CountHeld(list[i], True);
    end;
  end;
end;

procedure TTyRichDocument.CountHeld(AObj: TTyRichObject; AHold: Boolean);
var
  b, sb: Int64;
  p: Pointer;
  c: Integer;
begin
  b := AObj.DataBytes;
  p := AObj.SharedData(sb);
  if p <> nil then
  begin
    // its own part always; the block only for the first object that shares it, or the last
    Dec(b, sb);
    if FDataHolds = nil then FDataHolds := TTyRichObjHolds.Create;
    if FDataHolds.TryGetValue(p, c) then
    begin
      if AHold then
        FDataHolds[p] := c + 1
      else if c > 1 then
        FDataHolds[p] := c - 1
      else
      begin
        FDataHolds.Remove(p);
        Inc(b, sb);
      end;
    end
    else if AHold then
    begin
      FDataHolds.Add(p, 1);
      Inc(b, sb);
    end;
  end;
  if AHold then Inc(FHistoryBytes, b) else Dec(FHistoryBytes, b);
end;

procedure TTyRichDocument.HoldMore(var AEntry: TTyRichHistoryEntry;
  var AList: TTyRichObjectList; ACount: Integer; const AKeys: TTyRichKeyList);
var
  k, i, j, m, c: Integer;
  merged: TTyRichObjectList;
begin
  if Length(AKeys) > 0 then
  begin
    m := Length(AEntry.Keys);
    SetLength(AEntry.Keys, m + Length(AKeys));
    for i := 0 to High(AKeys) do AEntry.Keys[m + i] := AKeys[i];
  end;
  if ACount = 0 then Exit;
  k := SortDistinct(AList, ACount);
  if FObjHolds = nil then FObjHolds := TTyRichObjHolds.Create;
  // both sorted: one pass merges the new ones in, each held by this step once
  merged := nil;
  SetLength(merged, Length(AEntry.Objs) + k);
  i := 0;
  j := 0;
  m := 0;
  while (i < Length(AEntry.Objs)) or (j < k) do
    if (j >= k) or ((i < Length(AEntry.Objs)) and
      (PtrUInt(AEntry.Objs[i]) <= PtrUInt(AList[j]))) then
    begin
      // (one the step holds already: once)
      if (j < k) and (AEntry.Objs[i] = AList[j]) then Inc(j);
      merged[m] := AEntry.Objs[i];
      Inc(m);
      Inc(i);
    end
    else
    begin
      merged[m] := AList[j];
      Inc(m);
      if FObjHolds.TryGetValue(AList[j], c) then
        FObjHolds[AList[j]] := c + 1
      else
      begin
        FObjHolds.Add(AList[j], 1);
        CountHeld(AList[j], True);
      end;
      Inc(j);
    end;
  SetLength(merged, m);
  AEntry.Objs := merged;
end;

{ The step lets go of its objects: one no step holds any more leaves the history's bytes.
  Before the step's command is freed (the address must still be that object). }
procedure TTyRichDocument.LetGoObjects(var AEntry: TTyRichHistoryEntry);
var
  i, c: Integer;
begin
  for i := 0 to High(AEntry.Objs) do
    if (FObjHolds <> nil) and FObjHolds.TryGetValue(AEntry.Objs[i], c) then
      if c > 1 then
        FObjHolds[AEntry.Objs[i]] := c - 1
      else
      begin
        FObjHolds.Remove(AEntry.Objs[i]);
        CountHeld(AEntry.Objs[i], False);
      end;
  AEntry.Objs := nil;
  AEntry.Keys := nil;
end;

{ ---- TTyRichDocument: commands and the history ---- }

function TTyRichDocument.NewState: Int64;
begin
  Result := FNextState;
  Inc(FNextState);
end;

function TTyRichDocument.GetModified: Boolean;
begin
  Result := FState <> FSavedState;
end;

procedure TTyRichDocument.SetModified(AValue: Boolean);
begin
  if AValue then
    FSavedState := -1
  else
  begin
    FSavedState := FState;
    { Typing merged into the step that led here would carry the step's "after" past this
      content: an undo could not come back to it. }
    FMergeBroken := True;
  end;
  NoteModified;
end;

procedure TTyRichDocument.LeftHistory;
begin
  FState := NewState;
  FSavedState := -1;
end;

procedure TTyRichDocument.NoteModified;
var
  m: Boolean;
begin
  m := GetModified;
  if m = FModifiedSeen then Exit;
  FModifiedSeen := m;
  if Assigned(FOnModifiedChange) then FOnModifiedChange(Self);
end;

procedure TTyRichDocument.CheckIdle(const AWhat: string);
begin
  if FRunning <> nil then
    raise ETyRichModel.CreateFmt('%s while a command runs', [AWhat]);
end;

{ The end of a stretch the changes were held in (a command's run, an update block): what is
  pending is reported, then the edge (OnUpdatingEnd) - also after a report that raised. }
procedure TTyRichDocument.Flush;
var
  c: TTyRichChange;
begin
  if (FHold > 0) or (FUpdateCount > 0) then Exit;
  try
    if FHasPending then
    begin
      c := FPending;
      FHasPending := False;
      FPending := Default(TTyRichChange);
      if Assigned(FOnChange) then FOnChange(Self, c);
    end;
  finally
    // (a handler of the report may have begun an update)
    if Assigned(FOnUpdatingEnd) and not Updating then FOnUpdatingEnd(Self);
  end;
end;

{ Runs one step of ACmd with the notifications held; a failed execute or redo is reverted
  before the error travels on. }
procedure TTyRichDocument.RunStep(ACmd: TTyRichCommand; AStep: Integer);
begin
  Inc(FHold);
  FRunning := ACmd;
  ACmd.FDoc := Self;
  try
    if AStep = StepUndo then
    begin
      ACmd.DoUndo(Self);
      ACmd.FreeRecords;
    end
    else
    begin
      ACmd.FreeRecords;
      ACmd.ResetSummary;
      try
        if AStep = StepExecute then ACmd.DoExecute(Self) else ACmd.DoRedo(Self);
      except
        try
          ACmd.DoUndo(Self);
        except
        end;
        raise;
      end;
    end;
  finally
    ACmd.FDoc := nil;
    FRunning := nil;
    Dec(FHold);
  end;
end;

procedure TTyRichDocument.PushUndo(ACmd: TTyRichCommand);
var
  e: TTyRichHistoryEntry;
begin
  if FUndoCount > 0 then FUndo[FUndoCount - 1].Cmd.Covered;
  e := Default(TTyRichHistoryEntry);
  e.Cmd := ACmd;
  e.Bytes := ACmd.MemSize;
  HoldObjects(e);
  if FUndoCount = Length(FUndo) then SetLength(FUndo, FUndoCount * 2 + 8);
  FUndo[FUndoCount] := e;
  Inc(FUndoCount);
  Inc(FHistoryBytes, e.Bytes);
end;

procedure TTyRichDocument.DropOldestUndo;
var
  i: Integer;
begin
  Dec(FHistoryBytes, FUndo[0].Bytes);
  LetGoObjects(FUndo[0]);
  FUndo[0].Cmd.Free;
  for i := 1 to FUndoCount - 1 do FUndo[i - 1] := FUndo[i];
  Dec(FUndoCount);
end;

procedure TTyRichDocument.ClearRedo;
begin
  while FRedoCount > 0 do
  begin
    Dec(FRedoCount);
    Dec(FHistoryBytes, FRedo[FRedoCount].Bytes);
    LetGoObjects(FRedo[FRedoCount]);
    FRedo[FRedoCount].Cmd.Free;
  end;
end;

procedure TTyRichDocument.ClearHistory;
begin
  ClearRedo;
  while FUndoCount > 0 do
  begin
    Dec(FUndoCount);
    Dec(FHistoryBytes, FUndo[FUndoCount].Bytes);
    LetGoObjects(FUndo[FUndoCount]);
    FUndo[FUndoCount].Cmd.Free;
  end;
  while FBlockCount > 0 do
  begin
    Dec(FBlockCount);
    FBlock[FBlockCount].Free;
  end;
  FUndo := nil;
  FRedo := nil;
  FBlock := nil;
  FHistoryBytes := 0;
  if FObjHolds <> nil then FObjHolds.Clear;
  if FDataHolds <> nil then FDataHolds.Clear;
end;

procedure TTyRichDocument.TrimHistory;
begin
  // the newest step always stays, however big
  while (FMaxUndoBytes > 0) and (FHistoryBytes > FMaxUndoBytes) and (FUndoCount > 1) do
    DropOldestUndo;
end;

procedure TTyRichDocument.SetMaxUndoBytes(AValue: Int64);
begin
  FMaxUndoBytes := AValue;
  TrimHistory;
end;

function TTyRichDocument.Execute(ACmd: TTyRichCommand): Boolean;
var
  ok: Boolean;
  top: TTyRichCommand;
  list: TTyRichObjectList;
  n: Integer;
  keys: TTyRichKeyList;
begin
  if ACmd = nil then
    raise ETyRichModel.Create('Execute needs a command');
  try
    CheckIdle('Execute');
    // a document still loading (or cut short) is read-only, and so is one being saved: the
    // save's plan holds paragraph indices
    ok := not FLoadingContent and not FIncomplete and (FSaving = 0) and ACmd.CanExecute(Self);
  except
    ACmd.Free;
    raise;
  end;
  if not ok then
  begin
    ACmd.Free;
    Exit(False);
  end;
  Result := True;
  try
    RunStep(ACmd, StepExecute);
  except
    ACmd.Free;
    Flush;
    raise;
  end;
  if not ACmd.Changed then
  begin
    ACmd.Free;
    // nothing to report; the run's hold ended all the same
    Flush;
    Exit;
  end;
  // a content of its own; a merged step takes the new "after" (below)
  ACmd.FStateBefore := FState;
  FState := NewState;
  ACmd.FStateAfter := FState;
  if FUpdateCount > 0 then
  begin
    if FBlockCount = Length(FBlock) then SetLength(FBlock, FBlockCount * 2 + 4);
    FBlock[FBlockCount] := ACmd;
    Inc(FBlockCount);
    Exit;
  end;
  ClearRedo;
  // typing merges as the Memo's undo stack does: not across BreakMerge, Undo or Redo
  if (not FMergeBroken) and (FUndoCount > 0) then
  begin
    top := FUndo[FUndoCount - 1].Cmd;
    if top.ClassType = ACmd.ClassType then
    begin
      { The kinds that merge (typing, a replace's batches): what ACmd brings is gathered
        while its records are its own, past the values the step holds already (their keys) -
        a merged keystroke beside a paragraph's pictures walks none of them. }
      list := nil;
      n := 0;
      BeginGather(FUndo[FUndoCount - 1].Keys);
      try
        ACmd.GatherObjects(list, n);
      finally
        keys := EndGather;
      end;
      if top.TryMerge(ACmd) then
      begin
        top.FStateAfter := ACmd.FStateAfter;
        ACmd.Free;
        Dec(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        FUndo[FUndoCount - 1].Bytes := top.MemSize;
        Inc(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        ACmd := nil;
        HoldMore(FUndo[FUndoCount - 1], list, n, keys);
      end;
    end
    else
    begin
      // (another merge: the step's objects let go first, held again with ANext's)
      LetGoObjects(FUndo[FUndoCount - 1]);
      if top.TryMerge(ACmd) then
      begin
        top.FStateAfter := ACmd.FStateAfter;
        ACmd.Free;
        Dec(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        FUndo[FUndoCount - 1].Bytes := top.MemSize;
        Inc(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        ACmd := nil;
      end;
      HoldObjects(FUndo[FUndoCount - 1]);
    end;
  end;
  if ACmd <> nil then PushUndo(ACmd);
  FMergeBroken := False;
  TrimHistory;
  Flush;
  NoteModified;
end;

function TTyRichDocument.ExecutePart(ACmd: TTyRichCommand): Boolean;
var
  top, n0, cnt, i: Integer;
  list: TTyRichObjectList;
  keys: TTyRichKeyList;
  ok, lost: Boolean;
begin
  Result := False;
  if ACmd = nil then raise ETyRichModel.Create('ExecutePart needs a command');
  CheckIdle('ExecutePart');
  if (FUpdateCount > 0) or FLoadingContent or FIncomplete or (FSaving > 0) then Exit;
  if (FUndoCount = 0) or (FUndo[FUndoCount - 1].Cmd <> ACmd) or (FRedoCount > 0) then Exit;
  // the content it left, and no saved point set on it since
  if (FState <> ACmd.FStateAfter) or (FSavedState = FState) then Exit;
  top := FUndoCount - 1;
  n0 := ACmd.FRecordCount;
  ok := False;
  lost := False;
  Inc(FHold);
  FRunning := ACmd;
  ACmd.FDoc := Self;
  try
    ACmd.DoContinue(Self);
    ok := True;
  finally
    if not ok then
      // what the part did goes back, newest first: the step is as it was
      try
        while ACmd.FRecordCount > n0 do
        begin
          Dec(ACmd.FRecordCount);
          Revert(ACmd.FRecords[ACmd.FRecordCount]);
        end;
      except
        lost := True;
      end;
    ACmd.FDoc := nil;
    FRunning := nil;
    Dec(FHold);
    if not ok then
    begin
      if lost then
      begin
        // the document no longer matches the history: drop it all
        ClearHistory;
        LeftHistory;
      end;
      Flush;
      NoteModified;
    end;
  end;
  Result := True;
  if ACmd.FRecordCount > n0 then
  begin
    FState := NewState;
    ACmd.FStateAfter := FState;
    // what the part brought joins the step: its bytes, the objects its records hold
    Dec(FHistoryBytes, FUndo[top].Bytes);
    FUndo[top].Bytes := ACmd.MemSize;
    Inc(FHistoryBytes, FUndo[top].Bytes);
    list := nil;
    cnt := 0;
    BeginGather(FUndo[top].Keys);
    try
      for i := n0 to ACmd.FRecordCount - 1 do ACmd.FRecords[i].GatherObjects(list, cnt);
    finally
      keys := EndGather;
    end;
    HoldMore(FUndo[top], list, cnt, keys);
    TrimHistory;
  end;
  Flush;
  NoteModified;
end;

procedure TTyRichDocument.Undo;
var
  cmd: TTyRichCommand;
  e: TTyRichHistoryEntry;
begin
  CheckIdle('Undo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('Undo inside BeginUpdate .. EndUpdate');
  if (FUndoCount = 0) or (FSaving > 0) then Exit;
  Dec(FUndoCount);
  cmd := FUndo[FUndoCount].Cmd;
  Dec(FHistoryBytes, FUndo[FUndoCount].Bytes);
  // (before the undo frees its records: the objects' addresses are still theirs)
  LetGoObjects(FUndo[FUndoCount]);
  FMergeBroken := True;
  try
    RunStep(cmd, StepUndo);
  except
    // the document no longer matches the history: drop it all
    cmd.Free;
    ClearHistory;
    LeftHistory;
    Flush;
    NoteModified;
    raise;
  end;
  FState := cmd.FStateBefore;
  e := Default(TTyRichHistoryEntry);
  e.Cmd := cmd;
  e.Bytes := cmd.MemSize;
  HoldObjects(e);
  if FRedoCount = Length(FRedo) then SetLength(FRedo, FRedoCount * 2 + 8);
  FRedo[FRedoCount] := e;
  Inc(FRedoCount);
  Inc(FHistoryBytes, e.Bytes);
  Flush;
  NoteModified;
end;

procedure TTyRichDocument.Redo;
var
  cmd: TTyRichCommand;
begin
  CheckIdle('Redo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('Redo inside BeginUpdate .. EndUpdate');
  if (FRedoCount = 0) or (FSaving > 0) then Exit;
  Dec(FRedoCount);
  cmd := FRedo[FRedoCount].Cmd;
  Dec(FHistoryBytes, FRedo[FRedoCount].Bytes);
  LetGoObjects(FRedo[FRedoCount]);
  FMergeBroken := True;
  try
    RunStep(cmd, StepRedo);
  except
    // reverted; the steps after it were made on top of it
    cmd.Free;
    ClearRedo;
    Flush;
    raise;
  end;
  FState := cmd.FStateAfter;
  PushUndo(cmd);
  TrimHistory;
  Flush;
  NoteModified;
end;

function TTyRichDocument.CanUndo: Boolean;
begin
  Result := (FUndoCount > 0) and (FUpdateCount = 0) and (FRunning = nil) and (FSaving = 0);
end;

function TTyRichDocument.CanRedo: Boolean;
begin
  Result := (FRedoCount > 0) and (FUpdateCount = 0) and (FRunning = nil) and (FSaving = 0);
end;

procedure TTyRichDocument.ClearUndo;
begin
  CheckIdle('ClearUndo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('ClearUndo inside BeginUpdate .. EndUpdate');
  ClearHistory;
  FMergeBroken := False;
end;

function TTyRichDocument.UndoDescription: string;
begin
  if FUndoCount = 0 then Result := '' else Result := FUndo[FUndoCount - 1].Cmd.Description;
end;

function TTyRichDocument.RedoDescription: string;
begin
  if FRedoCount = 0 then Result := '' else Result := FRedo[FRedoCount - 1].Cmd.Description;
end;

function TTyRichDocument.UndoStep: TTyRichCommand;
begin
  if FUndoCount = 0 then Result := nil else Result := FUndo[FUndoCount - 1].Cmd;
end;

function TTyRichDocument.RedoStep: TTyRichCommand;
begin
  if FRedoCount = 0 then Result := nil else Result := FRedo[FRedoCount - 1].Cmd;
end;

procedure TTyRichDocument.BeginUpdate(const ADescription: string);
begin
  CheckIdle('BeginUpdate');
  Inc(FUpdateCount);
  if FUpdateCount = 1 then FBlockDescription := ADescription;
end;

procedure TTyRichDocument.EndUpdate;
var
  cmds: array of TTyRichCommand;
  comp: TTyRichCompositeCommand;
  i: Integer;
begin
  CheckIdle('EndUpdate');
  if FUpdateCount = 0 then
    raise ETyRichModel.Create('EndUpdate without BeginUpdate');
  Dec(FUpdateCount);
  if FUpdateCount > 0 then Exit;
  if FBlockCount > 0 then
  begin
    cmds := nil;
    SetLength(cmds, FBlockCount);
    for i := 0 to FBlockCount - 1 do cmds[i] := FBlock[i];
    FBlockCount := 0;
    FBlock := nil;
    comp := TTyRichCompositeCommand.CreateExecuted(FBlockDescription, cmds);
    comp.FStateBefore := cmds[0].FStateBefore;
    comp.FStateAfter := cmds[High(cmds)].FStateAfter;
    ClearRedo;
    PushUndo(comp);
    FMergeBroken := False;
    TrimHistory;
  end;
  FBlockDescription := '';
  Flush;
  NoteModified;
end;

function TTyRichDocument.GetUpdating: Boolean;
begin
  Result := (FUpdateCount > 0) or (FHold > 0);
end;

procedure TTyRichDocument.BreakMerge;
begin
  FMergeBroken := True;
end;

{ ---- a field's marks as a pair ---- }

type
  { The paragraphs of ShiftFieldDepths, each given its depth plus Delta (paragraphs that
    share a value share the new one). }
  TTyRichDepthWalk = class
  public
    Doc: TTyRichDocument;
    Undo: TTyRichUndoData;
    Delta: Integer;
    PrevD, PrevNew: TTyRichParaData;
    Changed: Boolean;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

function TTyRichDepthWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  d, nd: TTyRichParaData;
  depth: Integer;
begin
  d := TTyRichParaData(AData);
  if (d = nil) and (Doc.FLoader <> nil) then d := Doc.DataOf(AIndex);
  Undo.AddOld(d);
  if (d <> nil) and (d = PrevD) then
    nd := PrevNew
  else
  begin
    depth := Doc.DepthOfData(d) + Delta;
    if depth < 0 then depth := 0;
    nd := Doc.WithDepth(d, depth);
    PrevD := d;
    PrevNew := nd;
  end;
  if nd <> d then
  begin
    Doc.AcquireData(nd);
    Doc.ReleaseData(d);
    Changed := True;
  end;
  Result := nd;
end;

function TTyRichDocument.ShiftFieldDepths(AFirst, ALast, ADelta: Integer): TTyRichUndoData;
var
  c: TTyRichChange;
  w: TTyRichDepthWalk;
begin
  c := Default(TTyRichChange);
  if (AFirst < 0) or (ALast < AFirst) or (ALast >= FText.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraphs %d..%d out of 0..%d',
      [AFirst, ALast, FText.ParaCount - 1]);
  c.Pos := FText.ParaStart(AFirst);
  Result := NewUndo(c);
  w := TTyRichDepthWalk.Create;
  try
    try
      w.Doc := Self;
      w.Undo := Result;
      w.Delta := ADelta;
      Result.FFirstPara := AFirst;
      FText.MapParaData(AFirst, ALast, @w.Map);
      Result.SealOld;
      if not w.Changed then
      begin
        Result.FChange := c;
        Exit;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    w.Free;
  end;
  // (nothing a reader sees changed: told as a format change, so a view lays them out again)
  c.Kinds := [rckFormat];
  c.OldLen := FText.ParaStart(ALast) + FText.ParaLength(ALast) - c.Pos;
  c.NewLen := c.OldLen;
  c.FirstPara := AFirst;
  c.OldParaCount := ALast - AFirst + 1;
  c.NewParaCount := c.OldParaCount;
  Result.FChange := c;
  Notify(c);
end;

{ The field whose open mark is at AOpenPos, for UnwrapField and ReplaceFieldMarks: its close
  mark's position, and the field may be changed as a whole there (it lies in no other
  field's result, nor in a row that holds a nested table). Raises otherwise. }
function WholeFieldAt(ADoc: TTyRichDocument; AOpenPos: TTyRichPos): TTyRichPos;
var
  o: TTyRichObject;
begin
  ADoc.BeginRead;
  try
    o := ADoc.ObjectAt(AOpenPos);
    if not (o is TTyRichFieldMark) or (TTyRichFieldMark(o).Kind <> rfmOpen) then
      raise ETyRichModel.CreateFmt('No field''s open mark at %d', [AOpenPos]);
    Result := ADoc.FieldPartner(AOpenPos);
    if Result < 0 then
      raise ETyRichModel.CreateFmt('The field at %d has no close mark', [AOpenPos]);
    // both ends outside every field: it is in no result
    ADoc.RaiseRefused(AOpenPos, Result + 1 - AOpenPos);
  finally
    ADoc.EndRead;
  end;
end;

function TTyRichCommand.DeleteObjectAt(ADoc: TTyRichDocument; APos: TTyRichPos): TTyRichChange;
begin
  CheckRunning(ADoc);
  ADoc.BeginRead;
  try
    if ADoc.ObjectAt(APos) = nil then
      raise ETyRichModel.CreateFmt('No object at %d', [APos]);
  finally
    ADoc.EndRead;
  end;
  Result := Keep(ADoc.DeleteRange(APos, 1));
end;

procedure TTyRichCommand.WrapInField(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
  AOpen, AClose: TTyRichFieldMark; AFormat: TTyCharFormatId);
var
  t: TTyRichText;
  k, i: Integer;
  ps: Int64;
  runs: TTyRunArray;
begin
  CheckRunning(ADoc);
  if (AOpen = nil) or (AClose = nil) or (AOpen.Kind <> rfmOpen) or (AClose.Kind <> rfmClose) then
    raise ETyRichModel.Create('A field is made of an open and a close mark');
  t := ADoc.FText;
  if (APos < 0) or (ALen < 0) or (APos + ALen > t.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, t.Length]);
  k := t.ParaOfPos(APos);
  ps := t.ParaStart(k);
  if APos + ALen > ps + t.ParaLength(k) then
    raise ETyRichModel.Create('A field is made around text of one paragraph');
  if AFormat <> TyRichInheritFormat then ADoc.CheckCharId(AFormat);
  // the field rule, asked here: the primitives below do not ask it for the marks
  ADoc.RaiseRefused(APos, 0);
  if ALen > 0 then ADoc.RaiseRefused(APos, ALen);
  runs := ADoc.RunsOf(k);
  for i := 0 to High(runs) do
    if (runs[i].Obj is TTyRichFieldMark) and (ps + runs[i].Start >= APos) and
      (ps + runs[i].Start < APos + ALen) then
      raise ETyRichModel.Create('A field is not made around another field');
  Inc(ADoc.FMarkEdit);
  try
    // the close mark first: the open one after it would put its place in the field
    Keep(ADoc.InsertCore(APos + ALen, TyRichObjectChar, AFormat, AClose));
    Keep(ADoc.InsertCore(APos, TyRichObjectChar, AFormat, AOpen));
  finally
    Dec(ADoc.FMarkEdit);
  end;
end;

procedure TTyRichCommand.UnwrapField(ADoc: TTyRichDocument; AOpenPos: TTyRichPos);
var
  c: TTyRichPos;
  k, m: Integer;
begin
  CheckRunning(ADoc);
  c := WholeFieldAt(ADoc, AOpenPos);
  k := ADoc.FText.ParaOfPos(AOpenPos);
  m := ADoc.FText.ParaOfPos(c);
  Inc(ADoc.FMarkEdit);
  try
    Keep(ADoc.DeleteRange(c, 1));
    Keep(ADoc.DeleteRange(AOpenPos, 1));
    // the paragraphs that began inside the field begin one field less deep
    if m > k then Keep(ADoc.ShiftFieldDepths(k + 1, m, -1));
  finally
    Dec(ADoc.FMarkEdit);
  end;
end;

procedure TTyRichCommand.ReplaceFieldMarks(ADoc: TTyRichDocument; AOpenPos: TTyRichPos;
  AOpen, AClose: TTyRichFieldMark);
var
  c: TTyRichPos;
begin
  CheckRunning(ADoc);
  if (AOpen = nil) or (AClose = nil) or (AOpen.Kind <> rfmOpen) or (AClose.Kind <> rfmClose) then
    raise ETyRichModel.Create('A field is made of an open and a close mark');
  c := WholeFieldAt(ADoc, AOpenPos);
  Inc(ADoc.FMarkEdit);
  try
    Keep(ADoc.ReplaceObject(AOpenPos, AOpen));
    Keep(ADoc.ReplaceObject(c, AClose));
  finally
    Dec(ADoc.FMarkEdit);
  end;
end;

{ ---- bookmarks ---- }

function TyRichSameBookmarkName(const A, B: UTF8String): Boolean;
begin
  Result := UTF8UpperCase(A) = UTF8UpperCase(B);
end;

{ ---- TTyRichHashCounts ---- }

constructor TTyRichHashCounts.Create(ACapacity: Integer);
var
  n: Integer;
begin
  inherited Create;
  n := 16;
  while n < 2 * ACapacity do n := n * 2;
  SetLength(FKeys, n);
  SetLength(FVals, n);
  SetLength(FUsed, n);
  FMask := n - 1;
end;

function TTyRichHashCounts.Slot(AKey: Cardinal): Integer;
begin
  Result := Integer((AKey xor (AKey shr 15)) and Cardinal(FMask));
  while FUsed[Result] and (FKeys[Result] <> AKey) do Result := (Result + 1) and FMask;
end;

procedure TTyRichHashCounts.Grow;
var
  keys: array of Cardinal;
  vals: array of Int64;
  used: array of Boolean;
  i, j, n: Integer;
begin
  keys := FKeys;
  vals := FVals;
  used := FUsed;
  n := Length(keys) * 2;
  FKeys := nil;
  FVals := nil;
  FUsed := nil;
  SetLength(FKeys, n);
  SetLength(FVals, n);
  SetLength(FUsed, n);
  FMask := n - 1;
  for i := 0 to High(keys) do
    if used[i] then
    begin
      j := Slot(keys[i]);
      FUsed[j] := True;
      FKeys[j] := keys[i];
      FVals[j] := vals[i];
    end;
end;

function TTyRichHashCounts.Add(AKey: Cardinal; AValue: Int64): Int64;
var
  i: Integer;
begin
  Result := AValue;
  i := Slot(AKey);
  if FUsed[i] then
  begin
    Inc(FVals[i], AValue);
    Result := FVals[i];
    Exit;
  end;
  if 2 * (FCount + 1) > Length(FKeys) then
  begin
    Grow;
    i := Slot(AKey);
  end;
  FUsed[i] := True;
  FKeys[i] := AKey;
  FVals[i] := AValue;
  Inc(FCount);
end;

function TTyRichHashCounts.TryGet(AKey: Cardinal; out AValue: Int64): Boolean;
var
  i: Integer;
begin
  i := Slot(AKey);
  Result := FUsed[i];
  if Result then AValue := FVals[i] else AValue := 0;
end;

function TyRichBookmarkHash(const AName: UTF8String): Cardinal;
var
  s: UTF8String;
  i: Integer;
begin
  // FNV-1a of the name's folded bytes
  s := UTF8UpperCase(AName);
  Result := 2166136261;
  for i := 1 to Length(s) do
    Result := (Result xor Byte(s[i])) * 16777619;
end;

function TyRichBookmarkBytes(AKind: TTyRichBookmarkKind; const AName: UTF8String): RawByteString;
var
  i, n: Integer;
  c: Cardinal;
  b: Byte;

  procedure PutU(ACode: Cardinal);
  begin
    if ACode > 32767 then Result := Result + '\u' + IntToStr(Integer(ACode) - 65536) + '?'
    else Result := Result + '\u' + IntToStr(ACode) + '?';
  end;

begin
  if AKind = rbmStart then Result := '{\*\bkmkstart ' else Result := '{\*\bkmkend ';
  i := 1;
  n := Length(AName);
  while i <= n do
  begin
    b := Byte(AName[i]);
    if b < $80 then
    begin
      if AnsiChar(b) in ['\', '{', '}'] then Result := Result + '\';
      Result := Result + AnsiChar(b);
      Inc(i);
      Continue;
    end;
    // a UTF-8 sequence (a stray byte: U+FFFD)
    if (b >= $F0) and (i + 3 <= n) then
    begin
      c := ((b and 7) shl 18) or ((Byte(AName[i + 1]) and $3F) shl 12) or
        ((Byte(AName[i + 2]) and $3F) shl 6) or (Byte(AName[i + 3]) and $3F);
      Inc(i, 4);
    end
    else if (b >= $E0) and (i + 2 <= n) then
    begin
      c := ((b and $F) shl 12) or ((Byte(AName[i + 1]) and $3F) shl 6) or
        (Byte(AName[i + 2]) and $3F);
      Inc(i, 3);
    end
    else if (b >= $C0) and (i + 1 <= n) then
    begin
      c := ((b and $1F) shl 6) or (Byte(AName[i + 1]) and $3F);
      Inc(i, 2);
    end
    else
    begin
      c := $FFFD;
      Inc(i);
    end;
    if c > $FFFF then
    begin
      Dec(c, $10000);
      PutU($D800 + (c shr 10));
      PutU($DC00 + (c and $3FF));
    end
    else
      PutU(c);
  end;
  Result := Result + '}';
  SetCodePage(Result, CP_NONE, False);
end;

constructor TTyRichBookmarkMark.Create(AKind: TTyRichBookmarkKind; const AName: UTF8String;
  const ABytes: RawByteString; ARawUc: Integer);
begin
  inherited Create(ABytes, '', ARawUc);
  FKind := AKind;
  FName := AName;
end;

constructor TTyRichBookmarkMark.CreateNew(AKind: TTyRichBookmarkKind; const AName: UTF8String);
begin
  Create(AKind, AName, TyRichBookmarkBytes(AKind, AName), 1);
  FMade := True;
end;

function TTyRichBookmarkMark.Clone: TTyRichObject;
begin
  if FMade then Result := TTyRichBookmarkMark.CreateNew(FKind, FName)
  else Result := TTyRichBookmarkMark.Create(FKind, FName, Bytes, RawUc);
end;

function TTyRichBookmarkMark.DataBytes: Int64;
begin
  Result := inherited DataBytes + Length(FName);
end;

function TTyRichParaLoader.BookmarkIndexCount: Integer;
begin
  Result := -1;
end;

procedure TTyRichParaLoader.BookmarkIndexEntry(AIndex: Integer; out AKind: TTyRichBookmarkKind;
  out AHash: Cardinal; out AParaSrc, AGroupSrc: Int64);
begin
  AKind := rbmStart;
  AHash := 0;
  AParaSrc := -1;
  AGroupSrc := -1;
end;

function TTyRichParaLoader.BookmarkIndexName(AIndex: Integer): UTF8String;
begin
  Result := '';
end;

function TTyRichParaLoader.BookmarkIndexHidden(AIndex: Integer): Boolean;
begin
  Result := False;
end;

{ ---- a picture handed over ---- }

function PicLE16(const B: TBytes; AAt: Integer): Cardinal;
begin
  if (AAt < 0) or (AAt + 2 > Length(B)) then Exit(0);
  Result := Cardinal(B[AAt]) or (Cardinal(B[AAt + 1]) shl 8);
end;

function PicLE32(const B: TBytes; AAt: Integer): Cardinal;
begin
  if (AAt < 0) or (AAt + 4 > Length(B)) then Exit(0);
  Result := PicLE16(B, AAt) or (PicLE16(B, AAt + 2) shl 16);
end;

function TyRichPictureImageStream(APicture: TTyRichPicture;
  out AFormat: TTyRichPictureFormat): TMemoryStream;
var
  start, count: Integer;
  data: TBytes;
  hs, bits, comp, used, entry, pal, off: Cardinal;
  h: array[0..13] of Byte;

  procedure Put32(AAt: Integer; AValue: Cardinal);
  begin
    h[AAt] := AValue and $FF;
    h[AAt + 1] := (AValue shr 8) and $FF;
    h[AAt + 2] := (AValue shr 16) and $FF;
    h[AAt + 3] := (AValue shr 24) and $FF;
  end;

begin
  Result := nil;
  AFormat := rpfUnknown;
  if (APicture = nil) or not APicture.DisplayBytes(AFormat, start, count, data) then Exit;
  if (start < 0) or (count <= 0) or (Int64(start) + count > Length(data)) then Exit;
  Result := TMemoryStream.Create;
  try
    if AFormat = rpfDib then
    begin
      // a .bmp file's header: where the bits start - after the header, the colours, the masks
      hs := PicLE32(data, start);
      if hs = 12 then
      begin
        bits := PicLE16(data, start + 10);
        comp := 0;
        used := 0;
        entry := 3;
      end
      else
      begin
        bits := PicLE16(data, start + 14);
        comp := PicLE32(data, start + 16);
        if hs >= 36 then used := PicLE32(data, start + 32) else used := 0;
        entry := 4;
      end;
      if (used = 0) and (bits >= 1) and (bits <= 8) then used := Cardinal(1) shl bits;
      if used > 65536 then used := 0;
      pal := used * entry;
      if (hs = 40) and (comp = 3) then Inc(pal, 12)
      else if (hs = 40) and (comp = 6) then Inc(pal, 16);
      off := 14 + hs + pal;
      FillChar(h, SizeOf(h), 0);
      h[0] := Ord('B');
      h[1] := Ord('M');
      Put32(2, 14 + Cardinal(count));
      Put32(10, off);
      Result.WriteBuffer(h, SizeOf(h));
    end;
    Result.WriteBuffer(data[start], count);
    Result.Position := 0;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

procedure TTyRichPicture.AssignTo(Dest: TPersistent);
var
  s: TMemoryStream;
  fmt: TTyRichPictureFormat;
  g: TGraphic;
begin
  if not ((Dest is TPicture) or (Dest is TBitmap)) then
  begin
    inherited AssignTo(Dest);
    Exit;
  end;
  s := TyRichPictureImageStream(Self, fmt);
  if s = nil then raise EInvalidGraphic.Create(rsRichPictureNotShown);
  try
    case fmt of
      rpfPng: g := TPortableNetworkGraphic.Create;
      rpfJpeg: g := TJPEGImage.Create;
    else
      g := TBitmap.Create;
    end;
    try
      g.LoadFromStream(s);
      if Dest is TPicture then TPicture(Dest).Assign(g) else TBitmap(Dest).Assign(g);
    finally
      g.Free;
    end;
  finally
    s.Free;
  end;
end;

procedure TTyRichPicture.SaveImageToStream(AStream: TStream);
var
  data: TBytes;
begin
  data := MakeImageData;
  if Length(data) > 0 then AStream.WriteBuffer(data[0], Length(data));
end;

procedure TTyRichOpaque.AssignTo(Dest: TPersistent);
var
  p: TTyRichKeptPicture;
begin
  p := DisplayPicture;
  if p <> nil then p.AssignTo(Dest) else inherited AssignTo(Dest);
end;

end.
