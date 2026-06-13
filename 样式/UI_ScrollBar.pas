unit UI_ScrollBar;

interface

uses
  Windows, XCGUI, UI_Theme;

type
  /// <summary>
  ///  滚动条封装类，负责为指定滚动视图应用统一的样式。
  /// </summary>
  TScrollBarUI = class
  private
    FHost: Integer;       // 宿主滚动视图句柄
    FScrollBar: Integer;  // 垂直滚动条句柄
    FSlider: Integer;     // 滚动条滑块句柄
    FIsVertical: Boolean; // 是否为垂直滚动条
  public
    constructor Create(AHost: Integer);
    /// <summary>针对横向滚动条的构造函数。</summary>
    constructor CreateH(AHost: Integer);
    /// <summary>为当前宿主应用默认滚动条样式。</summary>
    procedure ApplyDefaultStyle(MinLength: Integer = 36; AScrollBarSize: Integer = 7; AThumbRadius: Integer = 3);
    /// <summary>快捷方法：一次性为指定宿主应用默认样式。</summary>
    class procedure ApplyDefault(Hele: Integer; MinLength: Integer = 36; AScrollBarSize: Integer = 7;
      AThumbRadius: Integer = 3); static;
    /// <summary>快捷方法：一次性为指定宿主应用横向滚动条默认样式。</summary>
    class procedure ApplyDefaultH(Hele: Integer; MinLength: Integer = 36; AScrollBarSize: Integer = 7;
      AThumbRadius: Integer = 3); static;
    /// <summary>递归为窗口/元素树内所有滚动视图应用默认滚动条样式。</summary>
    class procedure ApplyDefaultRecursive(hRoot: Integer); static;
    property Host: Integer read FHost;
    property ScrollBar: Integer read FScrollBar;
    property Slider: Integer read FSlider;
  end;

implementation

function OnSliderPAINT(hSlider, hDraw: Integer; pbHandle: PBoolean): Integer; stdcall;
var
  RC: TRect;
  thumbRadius: Integer;
begin
  Result := 0;
  pbHandle^ := True;

  // 获取滑块自身区域，收缩四周形成“漂浮”的细条效果
  XEle_GetClientRect(hSlider, RC);
  if XBtn_GetState(hSlider) = button_state_leave then
    // 离开状态更透明，类似轻微浮在内容上的效果
    XDraw_SetBrushColor(hDraw, UITheme_ScrollThumbIdle)
  else
    // 悬停/按下时提高不透明度，凸显可拖动
    XDraw_SetBrushColor(hDraw, UITheme_ScrollThumbActive);

  thumbRadius := XEle_GetUserData(hSlider);
  if thumbRadius <= 0 then
    thumbRadius := 3;
  XDraw_FillRoundRectEx(hDraw, RC, thumbRadius, thumbRadius, thumbRadius, thumbRadius);
end;

{ TScrollBarUI }

constructor TScrollBarUI.Create(AHost: Integer);
begin
  inherited Create;
  FHost := AHost;
  FScrollBar := XSView_GetScrollBarV(FHost);
  FIsVertical := True;
  FSlider := XSBar_GetButtonSlider(FScrollBar);
end;

constructor TScrollBarUI.CreateH(AHost: Integer);
begin
  inherited Create;
  FHost := AHost;
  FScrollBar := XSView_GetScrollBarH(FHost);
  FIsVertical := False;
  FSlider := XSBar_GetButtonSlider(FScrollBar);
end;

procedure TScrollBarUI.ApplyDefaultStyle(MinLength: Integer; AScrollBarSize: Integer; AThumbRadius: Integer);
begin
  if FHost = 0 then
    Exit;

  XSView_SetScrollBarSize(FHost, AScrollBarSize);
  XEle_EnableBkTransparent(FScrollBar, True);
  XSView_EnableAutoShowScrollBar(FHost, True);
  XSBar_ShowButton(FScrollBar, False);
  XEle_EnableBkTransparent(FSlider, True);
  XSBar_SetSliderMinLength(FScrollBar, MinLength);
  XEle_SetCursor(FSlider, LoadCursor(0, IDC_HAND));
  XEle_SetUserData(FSlider, AThumbRadius);
  XEle_RegEventC1(FSlider, XE_PAINT, Integer(@OnSliderPAINT));
end;

class procedure TScrollBarUI.ApplyDefault(Hele: Integer; MinLength: Integer; AScrollBarSize: Integer;
  AThumbRadius: Integer);
var
  SB: TScrollBarUI;
begin
  SB := TScrollBarUI.Create(Hele);
  try
    SB.ApplyDefaultStyle(MinLength, AScrollBarSize, AThumbRadius);
  finally
    SB.Free;
  end;
end;

class procedure TScrollBarUI.ApplyDefaultH(Hele: Integer; MinLength: Integer; AScrollBarSize: Integer;
  AThumbRadius: Integer);
var
  SB: TScrollBarUI;
begin
  SB := TScrollBarUI.CreateH(Hele);
  try
    SB.ApplyDefaultStyle(MinLength, AScrollBarSize, AThumbRadius);
  finally
    SB.Free;
  end;
end;

class procedure TScrollBarUI.ApplyDefaultRecursive(hRoot: Integer);
var
  i, n: Integer;
  hChild: Integer;
begin
  if XC_IsSViewExtend(hRoot) then
    ApplyDefault(hRoot);
  if XC_IsHWINDOW(hRoot) then
  begin
    n := XWnd_GetChildCount(hRoot);
    for i := 0 to n - 1 do
    begin
      hChild := XWnd_GetChildByIndex(hRoot, i);
      ApplyDefaultRecursive(hChild);
    end;
  end
  else if XC_IsHELE(hRoot) then
  begin
    n := XEle_GetChildCount(hRoot);
    for i := 0 to n - 1 do
    begin
      hChild := XEle_GetChildByIndex(hRoot, i);
      ApplyDefaultRecursive(hChild);
    end;
  end;
end;

end.

