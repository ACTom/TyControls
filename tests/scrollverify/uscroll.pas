unit uscroll;

{ scrollverify 的 .lfm 面 —— 用户最普通的用法:在设计器里摆一个 TTyScrollBox,
  往里丢几个比视口大的子控件,运行。代码里**一行都不写**。
  单元测试里每个用例都手动调了 UpdateScrollRange,这一层正是它们跳过的。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.ScrollBox, tyControls.Button, tyControls.Panel;

type
  TScrollForm = class(TForm)
    Box: TTyScrollBox;
    SbBtn1: TTyButton;
    SbBtn2: TTyButton;
    SbBtn3: TTyButton;
    SbBtn4: TTyButton;
    SbBtn5: TTyButton;
    SbBtn6: TTyButton;
    SbBtn7: TTyButton;
    SbBtn8: TTyButton;
    Host: TTyPanel;
    ClientBox: TTyScrollBox;
    CbBtn1: TTyButton;
    CbBtn2: TTyButton;
    AlignBox: TTyScrollBox;
    AlTop1: TTyButton;
    AlTop2: TTyButton;
    AlTop3: TTyButton;
    AlTop4: TTyButton;
    AlTop5: TTyButton;
    AlTop6: TTyButton;
    AlTop7: TTyButton;
    AlTop8: TTyButton;
  end;

implementation

{$R *.lfm}

end.
