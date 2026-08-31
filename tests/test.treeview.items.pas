unit test.treeview.items;
{ TTyTreeView 的条目模型(TTyTreeNodes / TTyTreeNodeItem)。

  这一组守卫分四类,每一类都对应一个具体的、能静默发生的坏结果:

  ① **移植面**:Tree.Items.AddChild(nil,'Root') 这一行现在编得过、并且真的建出树。
  ② **模式互斥**:两个数据源同时出现时必须**报错**,不能静默择一 ——
     静默偏向 Items 就是"我的 OnGetText 不触发了",静默偏向事件就是
     "设计器里填的节点运行时不见了"。
  ③ **虚拟路径不变**:Items 空时,分配步长、标题解析、结构 API 与条目模型
     进来之前逐字节相同。本仓库满是像素测试,这条不成立会全线变红。
  ④ **流式化**:published 集合没有 setter 时,FPC 的 writer 直接跳过该属性
     (设计器静默不保存)、reader 在看属性种类之前就抛 EReadError。本库两天前
     刚在 TTyHeader.Columns 上栽过一次(7d2c03d),所以这里用**写成文本再读回来**
     的往返来验,而不是断言 SetProc <> nil —— 后者对一个把数据丢在地上的
     空 setter 一样是绿的。 }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.TreeView, tyControls.Columns;

type
  TTreeViewItemsTest = class(TTestCase)
  private
    FTree: TTyTreeView;
    FGetTextCalls: Integer;
    FFreeNodeCalls: Integer;
    procedure FreeNode(Sender: TTyTreeView; Node: PTyTreeNode);
    procedure GetText(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string);
    procedure GetTextWithType(Sender: TTyTreeView; Node: PTyTreeNode;
      Column: Integer; TextType: TTyVSTTextType; var CellText: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { ① 移植面 }
    procedure TestAddChildBuildsARealTree;
    procedure TestItemsOrderIsPreOrderLikeLcl;
    procedure TestAddFamilyPlacesItemsWhereLclDoes;
    procedure TestDeleteItemTakesTheWholeSubtree;
    procedure TestNodeTextIsTheItemText;
    { ② 模式互斥 }
    procedure TestOnGetTextAfterItemsRaises;
    procedure TestItemsAfterOnGetTextRaises;
    procedure TestOnGetTextWithTypeAfterItemsRaises;
    procedure TestNodeDataSizeAndItemsRaise;
    procedure TestVirtualStructureApiRaisesInItemMode;
    procedure TestLfmConflictRaisesAtLoadedWhateverTheOrder;
    procedure TestDescendantThatOwnsItsDataRefusesItems;
    { ③ 虚拟路径不变 }
    procedure TestVirtualModeIsUntouchedWhenItemsEmpty;
    procedure TestNodeAllocStrideUnchangedInVirtualMode;
    procedure TestEmptyingItemsReturnsToVirtualMode;
    procedure TestCaptionEditDoesNotRebuildTheTree;
    procedure TestBeginUpdateMaterialisesOnceAtEndUpdate;
    procedure TestClearAlsoEmptiesItems;
    { ④ 流式化 }
    procedure TestItemsSurviveATextRoundTrip;
    procedure TestItemsAssignmentReplacesTheCollection;
    procedure TestLevelIsClampedToALegalShape;
    { ⑤ 子树块移动(节点编辑器的 Up/Down 原语) }
    procedure TestMoveSubTreeBeforeASibling;
    procedure TestMoveSubTreeAfterASibling;
    procedure TestMoveSubTreeCarriesTheChildren;
  end;

implementation

type
  TItemsHostForm = class(TForm)
  published
    Tree: TTyTreeView;
  end;

  { 站在 TTyShellTreeView 的位置上:自己拥有数据源(覆写 DoGetText、自己建树)。
    这个替身钉的是闸门本身 —— 任何后代声明 SupportsItemModel=False 都会被当场拒绝,
    与它在哪个单元无关。真的那个后代(TTyShellTreeView)由
    test.shelltreeview 的 TestItemsAreRefusedBecauseThisTreeOwnsItsData 钉住。 }
  TDataOwningTree = class(TTyTreeView)
  public
    function SupportsItemModel: Boolean; override;
  end;

function TDataOwningTree.SupportsItemModel: Boolean;
begin
  Result := False;
end;

procedure TTreeViewItemsTest.SetUp;
begin
  FTree := TTyTreeView.Create(nil);
  FTree.Name := 'ItemTree';
  FGetTextCalls := 0;
  FFreeNodeCalls := 0;
end;

procedure TTreeViewItemsTest.FreeNode(Sender: TTyTreeView; Node: PTyTreeNode);
begin
  Inc(FFreeNodeCalls);
end;

procedure TTreeViewItemsTest.TearDown;
begin
  FreeAndNil(FTree);
end;

procedure TTreeViewItemsTest.GetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var Text: string);
begin
  Inc(FGetTextCalls);
  Text := 'virtual';
end;

procedure TTreeViewItemsTest.GetTextWithType(Sender: TTyTreeView; Node: PTyTreeNode;
  Column: Integer; TextType: TTyVSTTextType; var CellText: string);
begin
  Inc(FGetTextCalls);
  CellText := 'virtual-typed';
end;

{ ===================== ① 移植面 ===================== }

{ 审计里点名的那一行。它不只要编得过 —— 编得过而建不出树是更坏的结果,
  因为报错会推迟到用户看着一棵空树发呆的时候。 }
procedure TTreeViewItemsTest.TestAddChildBuildsARealTree;
var
  root, childA, leaf: TTyTreeNodeItem;
begin
  root   := FTree.Items.AddChild(nil, 'Root');
  childA := FTree.Items.AddChild(root, 'Child A');
  FTree.Items.AddChild(root, 'Child B');
  leaf   := FTree.Items.AddChild(childA, 'Leaf');

  AssertTrue('Items 非空 = 条目模式', FTree.IsItemMode);
  AssertEquals('4 个条目', 4, FTree.Items.Count);
  AssertEquals('一个顶层节点', 1, Integer(FTree.RootNodeCount));

  { 条目层的形状 }
  AssertEquals('Root 有 2 个直接子条目', 2, root.Count);
  AssertEquals('Child A 有 1 个', 1, childA.Count);
  AssertEquals('Leaf 的层级', 2, leaf.Level);
  AssertSame('Leaf 的父亲是 Child A', childA, leaf.Parent);
  { 集合顺序是**前序**,所以 Leaf(Child A 的孩子)排在 Child B 前面 ——
    Child B 是 [3] 不是 [2]。这一条一开始就写错了,断言把它抓了出来。 }
  AssertEquals('前序:Root, Child A, Leaf, Child B', 'Leaf', FTree.Items[2].Text);
  AssertSame('Root 的第 2 个直接子条目是 Child B', FTree.Items[3], root.Items(1));

  { 记录树的形状 —— 条目建出来的必须是真的节点,不是影子 }
  AssertNotNull('Root 已物化', root.Node);
  AssertNotNull('Leaf 已物化', leaf.Node);
  AssertEquals('Root 记录节点有 2 个孩子', 2, Integer(root.Node^.ChildCount));
  AssertSame('Leaf 的父节点就是 Child A 的记录节点',
    TObject(childA.Node), TObject(leaf.Node^.Parent));
  AssertSame('记录节点反查回同一个条目', leaf, FTree.NodeItem[leaf.Node]);
end;

{ LCL 的 TTreeNodes.Item[i] 是**前序绝对下标**。我们的集合顺序就是前序,
  所以这条语义是白拿的 —— 但必须钉住,否则以后谁在 Add 里改了落点算术,
  移植过来的 Items[3] 会静默指向另一个节点。 }
procedure TTreeViewItemsTest.TestItemsOrderIsPreOrderLikeLcl;
var
  a, b: TTyTreeNodeItem;
begin
  a := FTree.Items.AddChild(nil, 'A');
  FTree.Items.AddChild(a, 'A1');
  FTree.Items.AddChild(a, 'A2');
  b := FTree.Items.AddChild(nil, 'B');
  FTree.Items.AddChild(b, 'B1');

  AssertEquals('前序 0', 'A',  FTree.Items[0].Text);
  AssertEquals('前序 1', 'A1', FTree.Items[1].Text);
  AssertEquals('前序 2', 'A2', FTree.Items[2].Text);
  AssertEquals('前序 3', 'B',  FTree.Items[3].Text);
  AssertEquals('前序 4', 'B1', FTree.Items[4].Text);
  AssertEquals('两个顶层', 2, FTree.Items.TopLvlCount);
  AssertSame('TopLvlItems[1] 是 B', b, FTree.Items.TopLvlItems[1]);
  AssertSame('GetFirstNode 是 A', a, FTree.Items.GetFirstNode);
end;

{ 五个 LCL 形状的建节点方法落点各不相同。全部走同一处插入算术,所以
  一条错了通常是全错 —— 但"全错"里最贵的是 Insert/AddFirst 这种少用的,
  没有断言就没人会发现。 }
procedure TTreeViewItemsTest.TestAddFamilyPlacesItemsWhereLclDoes;
var
  a, a1: TTyTreeNodeItem;
begin
  a  := FTree.Items.AddChild(nil, 'A');
  a1 := FTree.Items.AddChild(a, 'A1');
  FTree.Items.AddChild(a, 'A2');

  { AddChildFirst:插在 A 的孩子最前 }
  FTree.Items.AddChildFirst(a, 'A0');
  AssertEquals('AddChildFirst 落在最前', 'A0', FTree.Items[1].Text);
  AssertEquals('且是 A 的孩子', 1, FTree.Items[1].Level);

  { Insert:插在 A1 之前、同层 }
  FTree.Items.Insert(a1, 'before-A1');
  AssertEquals('Insert 落在 A1 之前', 'before-A1', FTree.Items[2].Text);
  AssertEquals('同层', 1, FTree.Items[2].Level);

  { Add(sibling):加成同层最后一个 }
  FTree.Items.Add(a1, 'last-sibling');
  AssertEquals('Add 落在 A 子树末尾', 'last-sibling',
    FTree.Items[FTree.Items.Count - 1].Text);
  AssertEquals('同层', 1, FTree.Items[FTree.Items.Count - 1].Level);

  { AddFirst(sibling):同层最前 }
  FTree.Items.AddFirst(a1, 'first-sibling');
  AssertEquals('AddFirst 落在 A 的孩子最前', 'first-sibling', FTree.Items[1].Text);
end;

{ 只 Delete(i) 会把子条目留成孤儿:它们的 Level 突然比前一项深 2 层,
  下一次物化时被夹紧成**别人**的孩子 —— 树默默换了形状,没有任何报错。 }
procedure TTreeViewItemsTest.TestDeleteItemTakesTheWholeSubtree;
var
  a, b: TTyTreeNodeItem;
begin
  a := FTree.Items.AddChild(nil, 'A');
  FTree.Items.AddChild(a, 'A1');
  FTree.Items.AddChild(a, 'A2');
  b := FTree.Items.AddChild(nil, 'B');
  AssertEquals('删之前 4 个', 4, FTree.Items.Count);

  FTree.Items.DeleteItem(a);
  AssertEquals('A 连子树一起走', 1, FTree.Items.Count);
  AssertSame('剩下的是 B', b, FTree.Items[0]);
  AssertEquals('B 还在顶层', 0, FTree.Items[0].Level);
  AssertEquals('记录树也只剩一个顶层节点', 1, Integer(FTree.RootNodeCount));
end;

{ 条目模式下屏幕上那一行显示的字必须是 Item.Text。NodeText[] 走的是
  GetNodeSearchText —— 也就是绘制/类型搜索/就地编辑共用的那条解析路径,
  所以这条断言同时钉住了"显示的"和"搜到的"是同一个字符串。 }
procedure TTreeViewItemsTest.TestNodeTextIsTheItemText;
var
  root: TTyTreeNodeItem;
begin
  root := FTree.Items.AddChild(nil, 'Documents');
  AssertEquals('标题来自条目', 'Documents', FTree.NodeText[root.Node]);

  root.Text := 'Pictures';
  AssertEquals('改了条目标题,树上跟着变', 'Pictures', FTree.NodeText[root.Node]);
  AssertEquals('OnGetText 一次都没被叫到(条目模式下它必须是 nil)',
    0, FGetTextCalls);
end;

{ ===================== ② 模式互斥 ===================== }

procedure TTreeViewItemsTest.TestOnGetTextAfterItemsRaises;
var
  raised: Boolean;
begin
  FTree.Items.AddChild(nil, 'Root');
  raised := False;
  try
    FTree.OnGetText := @GetText;
  except
    on E: ETyTreeItemMode do
    begin
      raised := True;
      AssertTrue('消息里必须同时点名两边(Items)', Pos('Items', E.Message) > 0);
      AssertTrue('消息里必须同时点名两边(OnGetText)',
        Pos('OnGetText', E.Message) > 0);
    end;
  end;
  AssertTrue('Items 非空之后再挂 OnGetText 必须报错,不能静默择一', raised);
end;

{ 反方向:先挂事件,再往 Items 里加条目。两边都要挡,否则赋值顺序就成了
  一个能绕过闸门的后门。 }
procedure TTreeViewItemsTest.TestItemsAfterOnGetTextRaises;
var
  raised: Boolean;
begin
  FTree.OnGetText := @GetText;
  raised := False;
  try
    FTree.Items.AddChild(nil, 'Root');
  except
    on E: ETyTreeItemMode do raised := True;
  end;
  AssertTrue('挂了 OnGetText 之后再往 Items 里加节点必须报错', raised);
  AssertFalse('报错之后不能半路切进条目模式', FTree.IsItemMode);
end;

procedure TTreeViewItemsTest.TestOnGetTextWithTypeAfterItemsRaises;
var
  raised: Boolean;
begin
  FTree.Items.AddChild(nil, 'Root');
  raised := False;
  try
    FTree.OnGetTextWithType := @GetTextWithType;
  except
    on E: ETyTreeItemMode do raised := True;
  end;
  AssertTrue('OnGetTextWithType 与 Items 同样互斥 —— 绘制侧优先走它,'
    + '放过去的话条目标题会被静默盖掉', raised);
end;

{ 条目模式征用了节点数据块的头 4 字节存条目下标。放过去 = 同一段内存
  两个主人 = 数据损坏,而且是那种在别处才显形的损坏。 }
procedure TTreeViewItemsTest.TestNodeDataSizeAndItemsRaise;
var
  raised: Boolean;
  t2: TTyTreeView;
begin
  FTree.Items.AddChild(nil, 'Root');
  raised := False;
  try
    FTree.NodeDataSize := 32;
  except
    on E: ETyTreeItemMode do raised := True;
  end;
  AssertTrue('Items 非空时设 NodeDataSize 必须报错', raised);

  { 反方向 }
  t2 := TTyTreeView.Create(nil);
  try
    t2.NodeDataSize := 32;
    raised := False;
    try
      t2.Items.AddChild(nil, 'Root');
    except
      on E: ETyTreeItemMode do raised := True;
    end;
    AssertTrue('设了 NodeDataSize 之后再用 Items 必须报错', raised);
  finally
    t2.Free;
  end;
end;

{ 条目模式下树形归 Items。虚拟结构 API 放行 = 两边同时改结构,
  条目下标槽立刻错行,而错行只会表现为"标题串了" —— 查起来极贵。 }
procedure TTreeViewItemsTest.TestVirtualStructureApiRaisesInItemMode;
var
  root: TTyTreeNodeItem;
  raised: Boolean;
begin
  root := FTree.Items.AddChild(nil, 'Root');

  raised := False;
  try FTree.RootNodeCount := 5; except on ETyTreeItemMode do raised := True; end;
  AssertTrue('条目模式下 RootNodeCount := 必须报错', raised);

  raised := False;
  try FTree.AddChild(nil); except on ETyTreeItemMode do raised := True; end;
  AssertTrue('条目模式下 AddChild(PTyTreeNode) 必须报错', raised);

  raised := False;
  try FTree.SetChildCount(root.Node, 3); except on ETyTreeItemMode do raised := True; end;
  AssertTrue('条目模式下 SetChildCount 必须报错', raised);

  raised := False;
  try FTree.DeleteNode(root.Node); except on ETyTreeItemMode do raised := True; end;
  AssertTrue('条目模式下 DeleteNode 必须报错', raised);

  AssertEquals('四次报错之后树没被动过', 1, Integer(FTree.RootNodeCount));
end;

{ .lfm 里 Items 与 OnGetText 谁先流进来是 IDE 决定的,不是用户写的。
  在读期间抛,就等于"报不报错取决于属性顺序"。所以冲突只在 csLoading
  期间记账,到 Loaded 一次性抛 —— 两种顺序都必须抛。 }
procedure TTreeViewItemsTest.TestLfmConflictRaisesAtLoadedWhateverTheOrder;
var
  Src, Dst: TItemsHostForm;
  MS: TMemoryStream;
  raised: Boolean;
begin
  Src := TItemsHostForm.CreateNew(nil);
  Dst := TItemsHostForm.CreateNew(nil);
  MS  := TMemoryStream.Create;
  try
    Src.Name := 'ItemsConflictHost';
    Src.Tree := TTyTreeView.Create(Src);
    Src.Tree.Name := 'Tree';
    Src.Tree.Parent := Src;
    Src.Tree.Items.AddChild(nil, 'Root');
    MS.WriteComponent(Src);

    { 读回来之后再挂事件 —— 这一半是"运行时冲突",立即抛。 }
    MS.Position := 0;
    MS.ReadComponent(Dst);
    raised := False;
    try
      (Dst.FindComponent('Tree') as TTyTreeView).OnGetText := @GetText;
    except
      on ETyTreeItemMode do raised := True;
    end;
    AssertTrue('从 .lfm 载入的 Items 一样把闸门关上', raised);
    AssertTrue('并且它确实进了条目模式',
      (Dst.FindComponent('Tree') as TTyTreeView).IsItemMode);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ 自己拥有数据源的后代(shell 树)必须当场拒绝条目模型,而不是先按条目重建一棵树、
  再让它自己的填充代码撞上虚拟结构闸门 —— 那样报的是 AddChild,指不到真正的原因。 }
procedure TTreeViewItemsTest.TestDescendantThatOwnsItsDataRefusesItems;
var
  t: TDataOwningTree;
  raised: Boolean;
begin
  t := TDataOwningTree.Create(nil);
  try
    t.Name := 'ShellLike';
    AssertFalse('这个后代声明了不支持条目模型', t.SupportsItemModel);
    AssertTrue('基类默认是支持的', FTree.SupportsItemModel);

    raised := False;
    try
      t.Items.AddChild(nil, 'Root');
    except
      on E: ETyTreeItemMode do
      begin
        raised := True;
        AssertTrue('报错要指向真正的原因(数据源归它自己),不是 AddChild',
          Pos('DoGetText', E.Message) > 0);
      end;
    end;
    AssertTrue('不支持条目模型的后代必须当场拒绝', raised);
    AssertFalse('并且没有半路切进条目模式', t.IsItemMode);
  finally
    t.Free;
  end;
end;

{ ===================== ③ 虚拟路径不变 ===================== }

{ 条目模型没被用到时,虚拟树必须与从前完全一样 —— 本仓库满是像素测试,
  这条不成立会全线变红,但"全线变红"是最好的情况;坏的情况是只有某一
  条路径变了而没有测试覆盖到。 }
procedure TTreeViewItemsTest.TestVirtualModeIsUntouchedWhenItemsEmpty;
var
  n: PTyTreeNode;
begin
  FTree.OnGetText := @GetText;
  FTree.RootNodeCount := 3;

  AssertFalse('Items 空 = 虚拟模式', FTree.IsItemMode);
  AssertEquals('三个根节点', 3, Integer(FTree.RootNodeCount));
  n := FTree.GetFirst;
  AssertNotNull('拿得到第一个节点', n);
  AssertEquals('标题仍然由 OnGetText 现算', 'virtual', FTree.NodeText[n]);
  AssertTrue('OnGetText 确实被调用了', FGetTextCalls > 0);
  AssertNull('虚拟模式下没有条目对象', TObject(FTree.NodeItem[n]));
end;

{ 分配步长 = 每个节点占多少字节。条目模式要在块首征用 4 字节存条目下标,
  所以这里钉死"虚拟模式下一个字节都没多占" —— 百万节点是这个控件存在的
  理由,11% 的内存回归不能靠人眼发现。 }
procedure TTreeViewItemsTest.TestNodeAllocStrideUnchangedInVirtualMode;
var
  a: PTyTreeNode;
  t2: TTyTreeView;
begin
  { 步长要**直接**断言,不能靠 GetNodeData 的偏移推:那个偏移恒为 TreeNodeSize,
    与分配步长无关,所以拿它来验步长的测试对"每个节点偷偷多占 4 字节"是全绿的
    —— 第一版就是这么写的,变异测试把它抓了出来。 }
  AssertEquals('虚拟模式、未设 NodeDataSize:一个字节都不多占',
    Int64(TreeNodeSize), Int64(FTree.NodeMemSize));

  FTree.RootNodeCount := 2;
  a := FTree.GetFirst;
  AssertNotNull('第一个节点', a);
  AssertNull('没设 NodeDataSize 时数据块为 nil(与从前一致)',
    FTree.GetNodeData(a));

  t2 := TTyTreeView.Create(nil);
  try
    t2.NodeDataSize := 16;
    AssertEquals('虚拟模式 + 16 字节数据块:正好多 16,中间没有条目槽',
      Int64(TreeNodeSize) + 16, Int64(t2.NodeMemSize));
    t2.RootNodeCount := 1;
    AssertEquals('app 的数据块紧跟在节点记录之后',
      Int64(TreeNodeSize),
      Int64(PtrUInt(t2.GetNodeData(t2.GetFirst)) - PtrUInt(t2.GetFirst)));
  finally
    t2.Free;
  end;

  { 反面:条目模式**确实**要那 4 字节 —— 否则上面那条断言可以靠
    "谁都不占槽位"来假绿,而条目反查就没地方存了。 }
  FTree.Items.AddChild(nil, 'Root');
  AssertEquals('条目模式:块首正好多一个条目下标槽',
    Int64(TreeNodeSize) + SizeOf(Cardinal), Int64(FTree.NodeMemSize));
  FTree.Items.Clear;
  AssertEquals('退回虚拟模式,步长复原',
    Int64(TreeNodeSize), Int64(FTree.NodeMemSize));
end;

{ 清空 Items 必须真的退回虚拟模式:步长复原、树清空、事件重新可挂。
  不退回的话,一个"先用设计器建、运行时再清掉改用虚拟"的宿主会卡死在
  一个永远报错的控件上。 }
procedure TTreeViewItemsTest.TestEmptyingItemsReturnsToVirtualMode;
begin
  FTree.Items.AddChild(nil, 'Root');
  AssertTrue('先进条目模式', FTree.IsItemMode);

  FTree.Items.Clear;
  AssertFalse('清空 Items 之后退回虚拟模式', FTree.IsItemMode);
  AssertEquals('记录树也空了', 0, Integer(FTree.RootNodeCount));

  { 闸门跟着放开 —— 否则"退回虚拟模式"只是个说法 }
  FTree.OnGetText := @GetText;
  FTree.RootNodeCount := 2;
  AssertEquals('虚拟 API 重新可用', 2, Integer(FTree.RootNodeCount));
end;

{ 改一个标题不能重建整棵树。重建会让所有记录指针失效、展开态与选中态全丢 ——
  运行时改标题是常事(重命名、翻译、状态变化),那样的树没法用。 }
procedure TTreeViewItemsTest.TestCaptionEditDoesNotRebuildTheTree;
var
  root, child: TTyTreeNodeItem;
begin
  root  := FTree.Items.AddChild(nil, 'Root');
  child := FTree.Items.AddChild(root, 'Child');
  root.Expanded := True;
  FTree.Selected := child.Node;
  AssertEquals('先选中', 1, FTree.SelectionCount);

  { 计数从这里开始:重建会把每个节点都释放掉,而释放是**直接可观测**的。
    注意不能用 "改完之后 child.Node 还是同一个指针" 来验 —— 释放之后紧接着
    重新分配,地址会被立刻复用,那条断言在重建发生时照样是绿的
    (库里已经栽过一次:见 memory/assertsame-freed-pointer-trap)。 }
  FFreeNodeCalls := 0;
  FTree.OnFreeNode := @FreeNode;

  child.Text := 'Renamed';

  AssertEquals('改一个标题不能释放任何节点(= 没有重建整棵树)',
    0, FFreeNodeCalls);
  AssertEquals('新标题生效', 'Renamed', FTree.NodeText[child.Node]);
  AssertTrue('展开态还在', nsExpanded in root.Node^.States);
  AssertEquals('选中态没有被冲掉 —— 重命名一个节点不该取消用户的选择',
    1, FTree.SelectionCount);
  AssertSame('而且选中的还是那个节点',
    TObject(child.Node), TObject(FTree.Selected));
end;

{ 每次结构变更都要重物化整棵树,所以批量建树必须能被 BeginUpdate 合并成一次
  —— 文档里就是这么写的,这条断言是那句话的凭据。用 OnFreeNode 计数来观测:
  每一次重物化都会先 Clear,也就是把已有节点全部释放一遍。 }
procedure TTreeViewItemsTest.TestBeginUpdateMaterialisesOnceAtEndUpdate;
var
  i: Integer;
  root: TTyTreeNodeItem;
begin
  root := FTree.Items.AddChild(nil, 'Root');
  FTree.OnFreeNode := @FreeNode;
  FFreeNodeCalls := 0;

  FTree.Items.BeginUpdate;
  try
    for i := 1 to 8 do
      FTree.Items.AddChild(root, 'Child ' + IntToStr(i));
    AssertEquals('批处理期间不物化:一个节点都没被释放过', 0, FFreeNodeCalls);
  finally
    FTree.Items.EndUpdate;
  end;

  AssertEquals('9 个条目', 9, FTree.Items.Count);
  AssertEquals('EndUpdate 之后树建好了', 1, Integer(FTree.RootNodeCount));
  AssertEquals('Root 有 8 个孩子', 8, Integer(root.Node^.ChildCount));
  AssertEquals('最后一个孩子的标题', 'Child 8',
    FTree.NodeText[FTree.Items[8].Node]);
  { 只重物化了一次 = 只释放了批处理开始时就存在的那 1 个节点。
    每加一个就重建一次的话,这个数会是 1+2+...+8 = 36。 }
  AssertEquals('整批只物化了一次', 1, FFreeNodeCalls);
end;

{ 条目模式下 Items 是树形的唯一真相,所以 Clear 必须连它一起清。
  只清记录会留下一集合对不上任何节点的条目 —— 之后每一次 NodeItem 反查
  都指向不存在的节点。 }
procedure TTreeViewItemsTest.TestClearAlsoEmptiesItems;
begin
  FTree.Items.AddChild(nil, 'Root');
  FTree.Items.AddChild(FTree.Items[0], 'Child');
  AssertEquals('两个条目', 2, FTree.Items.Count);

  FTree.Clear;

  AssertEquals('Clear 连条目一起清', 0, FTree.Items.Count);
  AssertEquals('记录树也空了', 0, Integer(FTree.RootNodeCount));
  AssertFalse('并且退回虚拟模式', FTree.IsItemMode);
end;

{ ===================== ④ 流式化 ===================== }

{ 这一条是本文件里最重要的守卫,原因见单元头:published 集合少一个 setter,
  设计器会**静默**不保存,而且没有任何报错。所以验的是"写成文本再读回来",
  不是 RTTI 形状 —— 一个把数据丢在地上的空 setter 对 SetProc <> nil 一样是绿的,
  对下面这条往返则不是。 }
procedure TTreeViewItemsTest.TestItemsSurviveATextRoundTrip;
var
  Src, Dst: TItemsHostForm;
  MS: TMemoryStream;
  Txt: TStringStream;
  root, a: TTyTreeNodeItem;
  DstTree: TTyTreeView;
begin
  Src := TItemsHostForm.CreateNew(nil);
  Dst := TItemsHostForm.CreateNew(nil);
  MS  := TMemoryStream.Create;
  Txt := TStringStream.Create('');
  try
    Src.Name := 'ItemsRoundTripHost';
    Src.Tree := TTyTreeView.Create(Src);
    Src.Tree.Name := 'Tree';
    Src.Tree.Parent := Src;

    root := Src.Tree.Items.AddChild(nil, 'Root');
    root.ImageIndex := 4;
    root.Expanded := True;
    a := Src.Tree.Items.AddChild(root, 'Alpha');
    a.CheckType := ctCheckBox;
    a.CheckState := csChecked;
    a.SelectedIndex := 7;
    Src.Tree.Items.AddChild(root, 'Beta');
    Src.Tree.Items.AddChild(nil, 'Second root');
    AssertEquals('写之前 4 个条目', 4, Src.Tree.Items.Count);

    { writer 那一半:被跳过的属性在文本里不留痕迹,而那正是设计器会保存的东西。 }
    MS.WriteComponent(Src);
    MS.Position := 0;
    ObjectBinaryToText(MS, Txt);
    AssertTrue('writer 必须写出 Items(跳过 = 设计器每次保存都丢节点)',
      Pos('Items', Txt.DataString) > 0);
    AssertTrue('节点标题也要在里面', Pos('Alpha', Txt.DataString) > 0);
    AssertTrue('层级也要在里面(树形就是 Level)',
      Pos('Level', Txt.DataString) > 0);

    { reader 那一半。 }
    MS.Position := 0;
    MS.ReadComponent(Dst);
    DstTree := Dst.FindComponent('Tree') as TTyTreeView;
    AssertNotNull('树活下来了', DstTree);
    AssertEquals('4 个条目回来了', 4, DstTree.Items.Count);
    AssertEquals('条目 0 标题', 'Root',        DstTree.Items[0].Text);
    AssertEquals('条目 1 标题', 'Alpha',       DstTree.Items[1].Text);
    AssertEquals('条目 3 标题', 'Second root', DstTree.Items[3].Text);
    AssertEquals('条目 1 的层级', 1, DstTree.Items[1].Level);
    AssertEquals('条目 3 回到顶层', 0, DstTree.Items[3].Level);
    AssertEquals('ImageIndex 活下来', 4, DstTree.Items[0].ImageIndex);
    AssertEquals('SelectedIndex 活下来', 7, DstTree.Items[1].SelectedIndex);
    AssertTrue('CheckType 活下来',  ctCheckBox = DstTree.Items[1].CheckType);
    AssertTrue('CheckState 活下来', csChecked  = DstTree.Items[1].CheckState);

    { 读进来的条目必须真的物化成树 —— 不然 .lfm 里有节点、跑起来是空的。 }
    AssertTrue('载入后是条目模式', DstTree.IsItemMode);
    AssertEquals('两个顶层节点', 2, Integer(DstTree.RootNodeCount));
    AssertNotNull('条目 1 已物化', DstTree.Items[1].Node);
    AssertEquals('并且树上显示的就是它的标题', 'Alpha',
      DstTree.NodeText[DstTree.Items[1].Node]);
    AssertTrue('Expanded 也施加到了记录节点上',
      nsExpanded in DstTree.Items[0].Node^.States);
  finally
    Txt.Free;
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ setter 的直接赋值路径。reader 其实从不调用它(vaCollection 走 ReadCollection),
  但它必须存在**且正确** —— 一个空 setter 能通过上面那条往返,通不过这条。 }
procedure TTreeViewItemsTest.TestItemsAssignmentReplacesTheCollection;
var
  t2: TTyTreeView;
begin
  FTree.Items.AddChild(nil, 'Keep me');
  FTree.Items.AddChild(FTree.Items[0], 'And me');

  t2 := TTyTreeView.Create(nil);
  try
    t2.Items.AddChild(nil, 'Replaced');
    AssertEquals('赋值前 1 个', 1, t2.Items.Count);

    t2.Items := FTree.Items;

    AssertEquals('赋值后 2 个', 2, t2.Items.Count);
    AssertEquals('内容来自源', 'Keep me', t2.Items[0].Text);
    AssertEquals('层级也搬过来了', 1, t2.Items[1].Level);
    AssertTrue('目标进了条目模式', t2.IsItemMode);
    AssertEquals('并且真的物化了', 1, Integer(t2.RootNodeCount));
    AssertEquals('树上显示的是搬过来的标题', 'Keep me',
      t2.NodeText[t2.Items[0].Node]);

    { 自赋值必须挡:TCollection.Assign 会先 Clear,然后把空集合还给你。 }
    t2.Items := t2.Items;
    AssertEquals('自赋值没有把集合清空', 2, t2.Items.Count);
  finally
    t2.Free;
  end;
end;

{ .lfm 是文本,可以手写出任何一串 Level(包括从 0 直接跳到 5)。夹紧规则
  ——「至多比前一项深 1 层,首项必须是 0」—— 保证任何一串都对应唯一一棵合法树,
  于是物化那一段不需要再防一次,手写的 .lfm 也不会把树建成一团乱麻。 }
procedure TTreeViewItemsTest.TestLevelIsClampedToALegalShape;
var
  a, b: TTyTreeNodeItem;
begin
  a := FTree.Items.AddChild(nil, 'A');
  a.Level := 5;
  AssertEquals('首项永远被夹到 0', 0, a.Level);

  b := FTree.Items.AddChild(a, 'B');
  b.Level := 9;
  AssertEquals('第二项至多比前一项深 1 层', 1, b.Level);

  b.Level := -3;
  AssertEquals('负数夹到 0', 0, b.Level);
  AssertEquals('两个顶层节点', 2, Integer(FTree.RootNodeCount));
end;

{ ⑤ 子树块移动:节点编辑器的 Up/Down 只能靠它 —— 扁平序 + Level 的模型里,
  "把 A 挪到同层 B 前面" = 把 A 的整个子树块(SubTreeCount 条)搬走,
  逐条 Index 赋值会互相踩(前面的移动改写后面的下标)。 }

procedure TTreeViewItemsTest.TestMoveSubTreeBeforeASibling;
begin
  FTree.Items.AddChild(nil, 'A');
  FTree.Items.AddChild(nil, 'B');
  FTree.Items.AddChild(nil, 'C');
  FTree.Items.MoveSubTreeBefore(FTree.Items[2], FTree.Items[0]);   // C before A
  AssertEquals('C first', 'C', FTree.Items[0].Text);
  AssertEquals('then A', 'A', FTree.Items[1].Text);
  AssertEquals('then B', 'B', FTree.Items[2].Text);
end;

procedure TTreeViewItemsTest.TestMoveSubTreeAfterASibling;
begin
  FTree.Items.AddChild(nil, 'A');
  FTree.Items.AddChild(nil, 'B');
  FTree.Items.AddChild(nil, 'C');
  FTree.Items.MoveSubTreeAfter(FTree.Items[0], FTree.Items[1]);    // A after B
  AssertEquals('B first', 'B', FTree.Items[0].Text);
  AssertEquals('then A', 'A', FTree.Items[1].Text);
  AssertEquals('C untouched', 'C', FTree.Items[2].Text);
end;

procedure TTreeViewItemsTest.TestMoveSubTreeCarriesTheChildren;
var
  a, b: TTyTreeNodeItem;
begin
  a := FTree.Items.AddChild(nil, 'A');
  FTree.Items.AddChild(a, 'a1');
  FTree.Items.AddChild(a, 'a2');
  b := FTree.Items.AddChild(nil, 'B');
  FTree.Items.AddChild(b, 'b1');
  { flat: A a1 a2 B b1.  Move B (with b1) before A: B b1 A a1 a2. }
  FTree.Items.MoveSubTreeBefore(b, a);
  AssertEquals('B leads', 'B', FTree.Items[0].Text);
  AssertEquals('with its child', 'b1', FTree.Items[1].Text);
  AssertEquals('child kept its depth', 1, FTree.Items[1].Level);
  AssertEquals('A follows whole', 'A', FTree.Items[2].Text);
  AssertEquals('a1 rides', 'a1', FTree.Items[3].Text);
  AssertEquals('a2 rides', 'a2', FTree.Items[4].Text);
  AssertEquals('a2 depth kept', 1, FTree.Items[4].Level);
  { and back down: A (subtree) after B's subtree is a no-op shape check via move up again }
  FTree.Items.MoveSubTreeAfter(b, FTree.Items[2]);   // B after A -> A a1 a2 B b1
  AssertEquals('A leads again', 'A', FTree.Items[0].Text);
  AssertEquals('B back behind', 'B', FTree.Items[3].Text);
  AssertEquals('b1 rides back', 'b1', FTree.Items[4].Text);
end;

initialization
  RegisterTest(TTreeViewItemsTest);
end.
