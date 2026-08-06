unit test.imagecollection.streaming;
{$mode objfpc}{$H+}

{ 设计期像素流式化 + 多分辨率母版 —— TTyImageCollection 的 .lfm 往返。

  这个单元钉的是两件事:

  1. **像素能进 .lfm,也能回来。** 之前 master 只活在一个私有 TStringList 里,
     组件根本不流式化任何东西 —— 设计期加载的图,保存后一张都不剩。现在
     Images 是一个 published 集合,每项把像素存成 base64 PNG。

  2. **多分辨率母版。** 一个名字可以挂多张母版(每张一个分辨率);渲染时挑
     "仍然覆盖请求尺寸的最小那张",挑不到就用最大的。

  §断言打在**边缘**,不打中心 —— 中心像素对本库真正发生过的每一种漂移都免疫。
  每张测试位图四角各一个不同颜色,其中一角是半透明,这样"丢 alpha"和"整张变黑"
  都会当场被抓住(见 memory/bgra-makebitmapcopy-black:BGRA 经 TPicture 往返
  会整张变黑,所以流式化路径一步都不许碰 TPicture)。

  §往返的判据是**像素相等**,不是"读出来了个东西"。文本那一半走
  ObjectBinaryToText / ObjectTextToBinary —— .lfm 真正的样子是文本,只验二进制
  等于没验设计器会写出去的东西。 }

interface

uses
  Classes, SysUtils, Forms, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes, tyControls.ImageCollection;

type
  { 编解码器本身。不碰集合,所以它红了就是 PNG/base64 那一层的问题,
    与流式化、与多分辨率都无关 —— 失败可归因。 }
  TImagePngCodecTest = class(TTestCase)
  published
    procedure EmptyTextDecodesToNil;
    procedure GarbageTextDecodesToNilAndDoesNotRaise;
    procedure NilBitmapEncodesToEmpty;
    procedure RoundTripKeepsSizeAndCornerPixels;
    procedure RoundTripKeepsSemiTransparentAlpha;
    procedure RoundTripDoesNotBlackenTheBitmap;
  end;

  { 集合的 .lfm 往返。 }
  TImageCollectionStreamingTest = class(TTestCase)
  published
    procedure WriterEmitsTheImagesBlock;
    procedure WriterEmitsReadablePayloadNotABinaryBlob;
    procedure BinaryRoundTripRestoresCornerPixels;
    procedure TextRoundTripRestoresCornerPixels;
    procedure RoundTripKeepsNamesAndCount;
    procedure AddBitmapFillsTheStreamedCollection;
    procedure ItemPayloadIsTheSourceOfTruth;
    procedure CorruptPayloadIsNotDecodableAndDoesNotRaise;
    procedure EmptyItemIsNotDecodable;
    procedure EditingAnItemBumpsChangeStampAndDropsCache;
    procedure ClearEmptiesTheStreamedCollection;
    procedure AssignCopiesPayloadNotTheBitmapInstance;
  end;

  { 多分辨率母版。 }
  TImageMultiResolutionTest = class(TTestCase)
  published
    procedure AddMasterKeepsTheExistingResolution;
    procedure AddBitmapReplacesEveryResolution;
    procedure CountCountsNamesNotMasters;
    procedure PicksSmallestMasterThatCoversTheRequest;
    procedure PicksExactMasterWhenOneMatches;
    procedure FallsBackToLargestWhenNoneCovers;
    procedure SameSizeMasterReplacesRatherThanDuplicates;
    procedure MultiResolutionSurvivesRoundTrip;
    procedure MasterPickIgnoresOtherNames;
  end;

implementation

type
  { .lfm 的替身:一个宿主窗体带一个图像集合子组件,和设计器保存出来的形状一样。 }
  TImgHostForm = class(TForm)
  end;

{ 四角的哨兵色。互不相同,且都不是黑 —— "整张变黑"必须让至少三个断言同时红。
  用 BGRA() 现算而不写成 typed const:TBGRAPixel 的字段顺序随 BGRABitmap 的
  BGRABITMAP_RGBAPIXEL 编译开关在 (b,g,r,a) 和 (r,g,b,a) 之间翻转,写死顺序的
  记录常量会跟着翻。 }
function CornerTL: TBGRAPixel;   // 左上 红
begin Result := BGRA(200, 40,  20,  255); end;
function CornerTR: TBGRAPixel;   // 右上 绿
begin Result := BGRA(50,  190, 30,  255); end;
function CornerBL: TBGRAPixel;   // 左下 蓝
begin Result := BGRA(70,  60,  210, 255); end;
function CornerBR: TBGRAPixel;   // 右下 半透明黄
begin Result := BGRA(220, 180, 15,  128); end;

{ 一张 AW x AH 的位图:底色中性,四角各钉一个哨兵像素。 }
function MakeCornerBmp(AW, AH: Integer): TBGRABitmap;
begin
  Result := TBGRABitmap.Create(AW, AH, BGRA(90, 90, 90, 255));
  Result.SetPixel(0,      0,      CornerTL);
  Result.SetPixel(AW - 1, 0,      CornerTR);
  Result.SetPixel(0,      AH - 1, CornerBL);
  Result.SetPixel(AW - 1, AH - 1, CornerBR);
end;

{ 断言 ABmp 的四角就是哨兵色。AWhere 进消息,好知道是哪一步掉的。 }
procedure AssertCorners(ATest: TTestCase; const AWhere: string; ABmp: TBGRABitmap);
var
  w, h: Integer;

  procedure Chk(const AName: string; AX, AY: Integer; const AWant: TBGRAPixel);
  var
    got: TBGRAPixel;
  begin
    got := ABmp.GetPixel(AX, AY);
    ATest.AssertEquals(AWhere + ' ' + AName + '.red',   Integer(AWant.red),   Integer(got.red));
    ATest.AssertEquals(AWhere + ' ' + AName + '.green', Integer(AWant.green), Integer(got.green));
    ATest.AssertEquals(AWhere + ' ' + AName + '.blue',  Integer(AWant.blue),  Integer(got.blue));
    ATest.AssertEquals(AWhere + ' ' + AName + '.alpha', Integer(AWant.alpha), Integer(got.alpha));
  end;

begin
  ATest.AssertNotNull(AWhere + ' 位图存在', ABmp);
  w := ABmp.Width;
  h := ABmp.Height;
  Chk('左上', 0,     0,     CornerTL);
  Chk('右上', w - 1, 0,     CornerTR);
  Chk('左下', 0,     h - 1, CornerBL);
  Chk('右下', w - 1, h - 1, CornerBR);
end;

{ ---- TImagePngCodecTest ---- }

procedure TImagePngCodecTest.EmptyTextDecodesToNil;
var
  it: TTyImageItem;
  c: TTyImageCollection;
begin
  c := TTyImageCollection.Create(nil);
  try
    it := c.Images.Add;
    it.PngBase64 := '';
    AssertNull('空载荷没有母版', it.Master);
  finally
    c.Free;
  end;
end;

procedure TImagePngCodecTest.GarbageTextDecodesToNilAndDoesNotRaise;
var
  it: TTyImageItem;
  c: TTyImageCollection;
begin
  c := TTyImageCollection.Create(nil);
  try
    it := c.Images.Add;
    // 手改坏了的 .lfm:合法 base64,但解出来不是 PNG。
    it.PngBase64 := 'bm90IGEgcG5nIGF0IGFsbA==';
    AssertNull('坏载荷解不出母版', it.Master);
    // 再来一次:失败也只解一次,而且第二次同样不抛。
    AssertNull('坏载荷第二次仍然是 nil', it.Master);
    AssertFalse('IsDecodable 说得出"坏"', it.IsDecodable);
  finally
    c.Free;
  end;
end;

procedure TImagePngCodecTest.NilBitmapEncodesToEmpty;
var
  it: TTyImageItem;
  c: TTyImageCollection;
begin
  c := TTyImageCollection.Create(nil);
  try
    it := c.Images.Add;
    it.SetBitmap(nil);
    AssertEquals('nil 位图编码成空串', '', it.PngBase64);
    AssertNull('因而没有母版', it.Master);
  finally
    c.Free;
  end;
end;

procedure TImagePngCodecTest.RoundTripKeepsSizeAndCornerPixels;
var
  c: TTyImageCollection;
  it: TTyImageItem;
  src: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  src := MakeCornerBmp(16, 16);
  try
    it := c.Images.Add;
    it.SetBitmap(src);
    AssertTrue('编码出了东西', it.PngBase64 <> '');
    AssertNotNull('解得回来', it.Master);
    AssertEquals('宽', 16, it.Master.Width);
    AssertEquals('高', 16, it.Master.Height);
    AssertCorners(Self, '编解码后', it.Master);
  finally
    src.Free;
    c.Free;
  end;
end;

procedure TImagePngCodecTest.RoundTripKeepsSemiTransparentAlpha;
var
  c: TTyImageCollection;
  it: TTyImageItem;
  src: TBGRABitmap;
begin
  { 右下角 alpha=128。单独一条,因为"PNG 把 alpha 拍平成 255"是最容易悄悄发生的
    那种损失 —— 图标看着还对,只有边缘的抗锯齿没了。 }
  c := TTyImageCollection.Create(nil);
  src := MakeCornerBmp(12, 12);
  try
    it := c.Images.Add;
    it.SetBitmap(src);
    AssertEquals('半透明角的 alpha 活下来了', 128,
      Integer(it.Master.GetPixel(11, 11).alpha));
    AssertTrue('而且没被拍成全不透明',
      it.Master.GetPixel(11, 11).alpha <> 255);
  finally
    src.Free;
    c.Free;
  end;
end;

procedure TImagePngCodecTest.RoundTripDoesNotBlackenTheBitmap;
var
  c: TTyImageCollection;
  it: TTyImageItem;
  src: TBGRABitmap;
  x, y, nonBlack: Integer;
  p: TBGRAPixel;
begin
  { memory/bgra-makebitmapcopy-black:BGRA 经 MakeBitmapCopy -> TPicture 往返会
    整张变黑。本路径走 SaveToStreamAsPng / LoadFromStream,一步不碰 TPicture,
    这条断言就是那个保证的守卫。 }
  c := TTyImageCollection.Create(nil);
  src := MakeCornerBmp(10, 10);
  try
    it := c.Images.Add;
    it.SetBitmap(src);
    nonBlack := 0;
    for y := 0 to it.Master.Height - 1 do
      for x := 0 to it.Master.Width - 1 do
      begin
        p := it.Master.GetPixel(x, y);
        if (p.red <> 0) or (p.green <> 0) or (p.blue <> 0) then Inc(nonBlack);
      end;
    AssertEquals('每个像素都还有颜色(全黑 = 走了 TPicture)', 100, nonBlack);
  finally
    src.Free;
    c.Free;
  end;
end;

{ ---- TImageCollectionStreamingTest ---- }

{ 建一个宿主窗体,挂一个装了 ANames 各一张母版的集合。 }
function BuildHost(const AName: string; ASize: Integer): TImgHostForm;
var
  coll: TTyImageCollection;
  b: TBGRABitmap;
begin
  Result := TImgHostForm.CreateNew(nil);
  Result.Name := 'ImgHost';
  coll := TTyImageCollection.Create(Result);
  coll.Name := 'Coll';
  b := MakeCornerBmp(ASize, ASize);
  try
    coll.AddBitmap(AName, b);
  finally
    b.Free;
  end;
end;

{ 把 ASrc 写成二进制再读进一个新窗体,返回其中的集合(窗体由 ADst 带出去释放)。 }
function BinaryRoundTrip(ASrc: TImgHostForm; out ADst: TImgHostForm): TTyImageCollection;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(ASrc);
    ms.Position := 0;
    ADst := TImgHostForm.CreateNew(nil);
    ms.ReadComponent(ADst);
  finally
    ms.Free;
  end;
  Result := ADst.FindComponent('Coll') as TTyImageCollection;
end;

procedure TImageCollectionStreamingTest.WriterEmitsTheImagesBlock;
var
  src: TImgHostForm;
  ms: TMemoryStream;
  txt: TStringStream;
begin
  { writer 那一半。published 属性少了 setter 就会被 TWriter.WriteProperty 静静
    跳过 —— 设计器每次保存都丢图,还不报错(commit 7d2c03d 就是这个 bug)。
    所以要验的是"文本里真的有",不是"内存里有"。 }
  src := BuildHost('save', 16);
  ms := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    AssertTrue('写出了 Images 块(跳过 = 保存即丢图)',
      Pos('Images', txt.DataString) > 0);
    AssertTrue('写出了图像名', Pos('ImageName', txt.DataString) > 0);
    AssertTrue('名字的值也在', Pos('save', txt.DataString) > 0);
    AssertTrue('写出了像素载荷', Pos('PngBase64', txt.DataString) > 0);
  finally
    txt.Free;
    ms.Free;
    src.Free;
  end;
end;

procedure TImageCollectionStreamingTest.WriterEmitsReadablePayloadNotABinaryBlob;
var
  src: TImgHostForm;
  ms: TMemoryStream;
  txt: TStringStream;
begin
  { 格式决策的守卫。LCL 用 DefineProperties 写一坨不可读的 Data;本库不用,
    因为伪属性没有 RTTI,IDE 的 LFM 检查器会把整个窗体拒掉
    (examples/demo/mainform.pas 里就写着这件事)。所以:.lfm 里既不许出现
    LCL 那个 Data 伪属性,载荷也必须是能读的文本。 }
  src := BuildHost('save', 16);
  ms := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    AssertTrue('没有 LCL 那种 Bitmap 二进制伪属性',
      Pos('Bitmap = {', txt.DataString) = 0);
    AssertTrue('也没有 Data 伪属性(IDE 会拒开整个窗体)',
      Pos('Data = {', txt.DataString) = 0);
    // base64 只有 A-Za-z0-9+/= ——载荷是文本,不是 {} 包起来的十六进制。
    AssertTrue('载荷是带引号的文本', Pos('PngBase64 = ', txt.DataString) > 0);
  finally
    txt.Free;
    ms.Free;
    src.Free;
  end;
end;

procedure TImageCollectionStreamingTest.BinaryRoundTripRestoresCornerPixels;
var
  src, dst: TImgHostForm;
  coll: TTyImageCollection;
begin
  src := BuildHost('save', 16);
  dst := nil;
  try
    coll := BinaryRoundTrip(src, dst);
    AssertNotNull('集合活下来了', coll);
    AssertEquals('一张图', 1, coll.Count);
    AssertTrue('名字回来了', coll.Contains('save'));
    // 母版本身(未缩放),这才是流式化路径的真正判据。
    AssertCorners(Self, '二进制往返后', coll.Images[0].Master);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TImageCollectionStreamingTest.TextRoundTripRestoresCornerPixels;
var
  src, dst: TImgHostForm;
  coll: TTyImageCollection;
  bin, bin2: TMemoryStream;
  txt: TStringStream;
begin
  { .lfm 真正的样子是**文本**。只验二进制往返,验的不是设计器写到盘上的东西。 }
  src := BuildHost('logo', 24);
  dst := nil;
  bin := TMemoryStream.Create;
  bin2 := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bin.WriteComponent(src);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);      // -> .lfm 文本
    txt.Position := 0;
    ObjectTextToBinary(txt, bin2);     // <- 再读回来
    bin2.Position := 0;
    dst := TImgHostForm.CreateNew(nil);
    bin2.ReadComponent(dst);
    coll := dst.FindComponent('Coll') as TTyImageCollection;
    AssertNotNull('集合活过了文本形式', coll);
    AssertEquals('一张图', 1, coll.Count);
    AssertEquals('母版尺寸', 24, coll.Images[0].Master.Width);
    AssertCorners(Self, '文本往返后', coll.Images[0].Master);
  finally
    txt.Free;
    bin2.Free;
    bin.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TImageCollectionStreamingTest.RoundTripKeepsNamesAndCount;
var
  src, dst: TImgHostForm;
  coll, srcColl: TTyImageCollection;
  b: TBGRABitmap;
begin
  src := BuildHost('one', 16);
  dst := nil;
  b := MakeCornerBmp(16, 16);
  try
    srcColl := src.FindComponent('Coll') as TTyImageCollection;
    srcColl.AddBitmap('two', b);
    srcColl.AddBitmap('three', b);
    coll := BinaryRoundTrip(src, dst);
    AssertEquals('三个名字', 3, coll.Count);
    AssertEquals('顺序是写入顺序', 'one',   coll.NameOf(0));
    AssertEquals('顺序是写入顺序', 'two',   coll.NameOf(1));
    AssertEquals('顺序是写入顺序', 'three', coll.NameOf(2));
    AssertEquals('IndexOf 跟着走', 1, coll.IndexOf('two'));
    AssertFalse('大小写仍然敏感', coll.Contains('One'));
  finally
    b.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TImageCollectionStreamingTest.AddBitmapFillsTheStreamedCollection;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  { 老 API 必须把东西放进**会被流式化的**那个store里 —— 否则运行期看着好好的,
    保存出来还是空的,正是这次要修的那个 bug。 }
  c := TTyImageCollection.Create(nil);
  b := MakeCornerBmp(8, 8);
  try
    AssertEquals('一开始没有母版', 0, c.Images.Count);
    c.AddBitmap('x', b);
    AssertEquals('AddBitmap 进了 Images', 1, c.Images.Count);
    AssertEquals('带着名字', 'x', c.Images[0].ImageName);
    AssertTrue('带着像素', c.Images[0].PngBase64 <> '');
    AssertTrue('而且解得开', c.Images[0].IsDecodable);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionStreamingTest.ItemPayloadIsTheSourceOfTruth;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
  before: string;
begin
  { 直接改载荷(OI 里粘一段 base64 就是这条路),母版必须跟着换,
    而不是继续拿旧的缓存位图。 }
  c := TTyImageCollection.Create(nil);
  b := MakeCornerBmp(8, 8);
  try
    c.AddBitmap('x', b);
    AssertEquals('母版是 8', 8, c.Images[0].Master.Width);
    before := c.Images[0].PngBase64;

    b.Free;
    b := MakeCornerBmp(20, 20);
    c.Images[0].SetBitmap(b);
    AssertTrue('载荷换了', c.Images[0].PngBase64 <> before);
    AssertEquals('母版跟着换成 20', 20, c.Images[0].Master.Width);
    AssertCorners(Self, '换载荷后', c.Images[0].Master);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionStreamingTest.CorruptPayloadIsNotDecodableAndDoesNotRaise;
var
  c: TTyImageCollection;
  got: TBGRABitmap;
begin
  { 手改坏的 .lfm 必须让图标变空白,而不是让窗体打不开。 }
  c := TTyImageCollection.Create(nil);
  try
    c.Images.Add.ImageName := 'broken';
    c.Images[0].PngBase64 := '!!!! not base64 !!!!';
    AssertFalse('解不开', c.Images[0].IsDecodable);
    AssertEquals('名字仍在(所以还算一张图)', 1, c.Count);
    got := c.GetBitmap('broken', 16);
    try
      AssertNotNull('照样给得出一张图,不抛异常', got);
      AssertEquals('是请求的尺寸', 16, got.Width);
    finally
      got.Free;
    end;
  finally
    c.Free;
  end;
end;

procedure TImageCollectionStreamingTest.EmptyItemIsNotDecodable;
var
  c: TTyImageCollection;
begin
  c := TTyImageCollection.Create(nil);
  try
    c.Images.Add;   // OI 里刚点出来、还没填的那一行
    AssertFalse('空项解不开', c.Images[0].IsDecodable);
    AssertEquals('没有尺寸', 0, c.Images[0].MasterSize);
    AssertEquals('没名字就不算一张图', 0, c.Count);
  finally
    c.Free;
  end;
end;

procedure TImageCollectionStreamingTest.EditingAnItemBumpsChangeStampAndDropsCache;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
  v0: Cardinal;
begin
  { OI 里改一项,渲染缓存必须失效 —— 否则设计器里换了图,画面还是旧的。 }
  c := TTyImageCollection.Create(nil);
  b := MakeCornerBmp(8, 8);
  try
    c.AddBitmap('x', b);
    c.GetCachedBitmap('x', 16);
    AssertEquals('缓存里有一张', 1, c.CacheCount);
    v0 := c.ChangeStamp;

    c.Images[0].ImageName := 'y';        // 只改名字,也算变更
    AssertTrue('改名字也要 bump', c.ChangeStamp > v0);
    AssertFalse('旧名字的缓存不作数', c.IsCached('x', 16));
    AssertEquals('缓存已清', 0, c.CacheCount);
    AssertTrue('新名字生效', c.Contains('y'));
    AssertFalse('旧名字没了', c.Contains('x'));
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionStreamingTest.ClearEmptiesTheStreamedCollection;
var
  c: TTyImageCollection;
  b: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b := MakeCornerBmp(8, 8);
  try
    c.AddBitmap('x', b);
    c.AddBitmap('y', b);
    AssertEquals('两张母版', 2, c.Images.Count);
    c.Clear;
    AssertEquals('Images 也空了', 0, c.Images.Count);
    AssertEquals('名字也空了', 0, c.Count);
  finally
    b.Free;
    c.Free;
  end;
end;

procedure TImageCollectionStreamingTest.AssignCopiesPayloadNotTheBitmapInstance;
var
  c1, c2: TTyImageCollection;
  b: TBGRABitmap;
begin
  { 集合 Assign(SetImages 走的就是这条)必须复制载荷,而且两边的解码位图
    不能是同一个实例 —— 共享一张 TBGRABitmap 会导致一边释放另一边野指针。 }
  c1 := TTyImageCollection.Create(nil);
  c2 := TTyImageCollection.Create(nil);
  b := MakeCornerBmp(16, 16);
  try
    c1.AddBitmap('x', b);
    c2.Images := c1.Images;
    AssertEquals('复制了一张母版', 1, c2.Images.Count);
    AssertEquals('名字也复制了', 'x', c2.Images[0].ImageName);
    AssertEquals('载荷相同', c1.Images[0].PngBase64, c2.Images[0].PngBase64);
    AssertCorners(Self, 'Assign 后', c2.Images[0].Master);
    AssertTrue('但解码位图不是同一个实例',
      c1.Images[0].Master <> c2.Images[0].Master);
  finally
    b.Free;
    c2.Free;
    c1.Free;
  end;
end;

{ ---- TImageMultiResolutionTest ---- }

procedure TImageMultiResolutionTest.AddMasterKeepsTheExistingResolution;
var
  c: TTyImageCollection;
  b16, b48: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b16 := MakeCornerBmp(16, 16);
  b48 := MakeCornerBmp(48, 48);
  try
    c.AddBitmap('save', b16);
    c.AddMasterBitmap('save', b48);
    AssertEquals('两张母版', 2, c.MasterCount('save'));
    AssertEquals('但还是一张图', 1, c.Count);
  finally
    b48.Free;
    b16.Free;
    c.Free;
  end;
end;

procedure TImageMultiResolutionTest.AddBitmapReplacesEveryResolution;
var
  c: TTyImageCollection;
  b16, b48, b32: TBGRABitmap;
begin
  { AddBitmap 是"换掉这个名字",不是"再加一个分辨率" —— 老契约必须保住,
    否则每调用一次就悄悄多留一张旧母版在 .lfm 里。 }
  c := TTyImageCollection.Create(nil);
  b16 := MakeCornerBmp(16, 16);
  b48 := MakeCornerBmp(48, 48);
  b32 := MakeCornerBmp(32, 32);
  try
    c.AddBitmap('save', b16);
    c.AddMasterBitmap('save', b48);
    AssertEquals('先有两张', 2, c.MasterCount('save'));
    c.AddBitmap('save', b32);
    AssertEquals('AddBitmap 把两张都换掉了', 1, c.MasterCount('save'));
    AssertEquals('剩下的就是新的那张', 32, c.PickedMasterSize('save', 32));
  finally
    b32.Free;
    b48.Free;
    b16.Free;
    c.Free;
  end;
end;

procedure TImageMultiResolutionTest.CountCountsNamesNotMasters;
var
  c: TTyImageCollection;
  b16, b48: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b16 := MakeCornerBmp(16, 16);
  b48 := MakeCornerBmp(48, 48);
  try
    c.AddBitmap('save', b16);
    c.AddMasterBitmap('save', b48);
    c.AddBitmap('open', b16);
    AssertEquals('三张母版', 3, c.Images.Count);
    AssertEquals('两个名字', 2, c.Count);
    AssertEquals('名字不重复出现', 'save', c.NameOf(0));
    AssertEquals('名字不重复出现', 'open', c.NameOf(1));
    AssertEquals('越界还是空', '', c.NameOf(2));
  finally
    b48.Free;
    b16.Free;
    c.Free;
  end;
end;

procedure TImageMultiResolutionTest.PicksSmallestMasterThatCoversTheRequest;
var
  c: TTyImageCollection;
  b16, b32, b64: TBGRABitmap;
begin
  { 这条就是这半个缺口本身:请求 24px,有 16/32/64 三张母版时必须挑 32
    ——挑 16 是把小图放大(糊),挑 64 是多余的降采样。 }
  c := TTyImageCollection.Create(nil);
  b16 := MakeCornerBmp(16, 16);
  b32 := MakeCornerBmp(32, 32);
  b64 := MakeCornerBmp(64, 64);
  try
    c.AddBitmap('ico', b16);
    c.AddMasterBitmap('ico', b64);
    c.AddMasterBitmap('ico', b32);   // 故意乱序加,挑选看尺寸不看顺序
    AssertEquals('三张母版', 3, c.MasterCount('ico'));
    AssertEquals('请求 24 -> 挑 32', 32, c.PickedMasterSize('ico', 24));
    AssertEquals('请求 17 -> 挑 32', 32, c.PickedMasterSize('ico', 17));
    AssertEquals('请求 16 -> 挑 16(正好覆盖)', 16, c.PickedMasterSize('ico', 16));
    AssertEquals('请求 33 -> 挑 64', 64, c.PickedMasterSize('ico', 33));
  finally
    b64.Free;
    b32.Free;
    b16.Free;
    c.Free;
  end;
end;

procedure TImageMultiResolutionTest.PicksExactMasterWhenOneMatches;
var
  c: TTyImageCollection;
  b16, b32: TBGRABitmap;
  got: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b16 := MakeCornerBmp(16, 16);
  b32 := MakeCornerBmp(32, 32);
  try
    c.AddBitmap('ico', b16);
    c.AddMasterBitmap('ico', b32);
    AssertEquals('正好有 32 就用 32', 32, c.PickedMasterSize('ico', 32));
    // 而且渲染确实是那张:32 的母版铺满 32 的方块,四角就是哨兵色本身
    // (缩放是恒等,所以边缘像素不会被重采样搅浑)。
    got := c.GetBitmap('ico', 32);
    try
      AssertEquals('渲染尺寸', 32, got.Width);
      AssertCorners(Self, '按母版尺寸渲染', got);
    finally
      got.Free;
    end;
  finally
    b32.Free;
    b16.Free;
    c.Free;
  end;
end;

procedure TImageMultiResolutionTest.FallsBackToLargestWhenNoneCovers;
var
  c: TTyImageCollection;
  b16, b32: TBGRABitmap;
begin
  c := TTyImageCollection.Create(nil);
  b16 := MakeCornerBmp(16, 16);
  b32 := MakeCornerBmp(32, 32);
  try
    c.AddBitmap('ico', b16);
    c.AddMasterBitmap('ico', b32);
    AssertEquals('请求 128,没有够大的 -> 用最大的 32', 32,
      c.PickedMasterSize('ico', 128));
  finally
    b32.Free;
    b16.Free;
    c.Free;
  end;
end;

procedure TImageMultiResolutionTest.SameSizeMasterReplacesRatherThanDuplicates;
var
  c: TTyImageCollection;
  b32a, b32b: TBGRABitmap;
begin
  { 同尺寸的第二张母版永远挑不中(挑选只比尺寸),留着只是白占 .lfm。 }
  c := TTyImageCollection.Create(nil);
  b32a := MakeCornerBmp(32, 32);
  b32b := MakeCornerBmp(32, 32);
  try
    c.AddBitmap('ico', b32a);
    c.AddMasterBitmap('ico', b32b);
    AssertEquals('同尺寸是替换,不是追加', 1, c.MasterCount('ico'));
  finally
    b32b.Free;
    b32a.Free;
    c.Free;
  end;
end;

procedure TImageMultiResolutionTest.MultiResolutionSurvivesRoundTrip;
var
  src, dst: TImgHostForm;
  srcColl, coll: TTyImageCollection;
  b16, b48: TBGRABitmap;
  ms: TMemoryStream;
begin
  src := TImgHostForm.CreateNew(nil);
  src.Name := 'ImgHost';
  dst := nil;
  b16 := MakeCornerBmp(16, 16);
  b48 := MakeCornerBmp(48, 48);
  ms := TMemoryStream.Create;
  try
    srcColl := TTyImageCollection.Create(src);
    srcColl.Name := 'Coll';
    srcColl.AddBitmap('ico', b16);
    srcColl.AddMasterBitmap('ico', b48);

    ms.WriteComponent(src);
    ms.Position := 0;
    dst := TImgHostForm.CreateNew(nil);
    ms.ReadComponent(dst);
    coll := dst.FindComponent('Coll') as TTyImageCollection;

    AssertNotNull('集合活下来了', coll);
    AssertEquals('两张母版都回来了', 2, coll.MasterCount('ico'));
    AssertEquals('还是一张图', 1, coll.Count);
    AssertEquals('挑选逻辑在载入后照样成立', 48, coll.PickedMasterSize('ico', 20));
    AssertEquals('小的那张也还在', 16, coll.PickedMasterSize('ico', 8));
    AssertCorners(Self, '多分辨率往返后', coll.Images[0].Master);
    AssertCorners(Self, '多分辨率往返后', coll.Images[1].Master);
  finally
    ms.Free;
    b48.Free;
    b16.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TImageMultiResolutionTest.MasterPickIgnoresOtherNames;
var
  c: TTyImageCollection;
  b16, b64: TBGRABitmap;
begin
  { 挑选必须只在同名母版里进行 —— 否则另一个图标的大母版会被当成本图标的。 }
  c := TTyImageCollection.Create(nil);
  b16 := MakeCornerBmp(16, 16);
  b64 := MakeCornerBmp(64, 64);
  try
    c.AddBitmap('small', b16);
    c.AddBitmap('big', b64);
    AssertEquals('small 请求 32 只能拿到自己的 16', 16,
      c.PickedMasterSize('small', 32));
    AssertEquals('big 请求 32 拿自己的 64', 64, c.PickedMasterSize('big', 32));
    AssertEquals('不存在的名字没有母版', 0, c.PickedMasterSize('nope', 32));
  finally
    b64.Free;
    b16.Free;
    c.Free;
  end;
end;

initialization
  RegisterTest(TImagePngCodecTest);
  RegisterTest(TImageCollectionStreamingTest);
  RegisterTest(TImageMultiResolutionTest);

end.
