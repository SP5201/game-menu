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
    FHost: XCGUI.HELE;       // 宿主滚动视图句柄
    FScrollBar: XCGUI.HELE;  // 垂直滚动条句柄
    FSlider: XCGUI.HELE;     // 滚动条滑块句柄
    FIsVertical: Boolean; // 是否为垂直滚动条
  public
    constructor Create(AHost: XCGUI.HELE; AIsVertical: Boolean = True);
    /// <summary>为当前宿主应用默认滚动条样式。</summary>
    procedure ApplyDefaultStyle(MinLength: Integer = 36; AScrollBarSize: Integer = 7; AThumbRadius: Integer = 3);
    /// <summary>快捷方法：一次性为指定宿主应用默认样式。</summary>
    class procedure ApplyDefault(Hele: XCGUI.HELE; MinLength: Integer = 36; AScrollBarSize: Integer = 7;
      AThumbRadius: Integer = 3); static;
    /// <summary>快捷方法：一次性为指定宿主应用横向滚动条默认样式。</summary>
    class procedure ApplyDefaultH(Hele: XCGUI.HELE; MinLength: Integer = 36; AScrollBarSize: Integer = 7;
      AThumbRadius: Integer = 3); static;
    /// <summary>递归为窗口/元素树内所有滚动视图应用默认滚动条样式。</summary>
    class procedure ApplyDefaultRecursive(hRoot: XCGUI.HXCGUI); static;
    property Host: XCGUI.HELE read FHost;
    property ScrollBar: XCGUI.HELE read FScrollBar;
    property Slider: XCGUI.HELE read FSlider;
  end;

implementation

function OnSliderPAINT(hSlider: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandle: PBOOL): Integer; stdcall;
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

constructor TScrollBarUI.Create(AHost: XCGUI.HELE; AIsVertical: Boolean);
begin
  inherited Create;
  FHost := AHost;
  FIsVertical := AIsVertical;
  if FIsVertical then
    FScrollBar := XSView_GetScrollBarV(FHost)
  else
    FScrollBar := XSView_GetScrollBarH(FHost);
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
  XEle_RegEventC1(FSlider, XE_PAINT, NativeInt(@OnSliderPAINT));
end;

class procedure TScrollBarUI.ApplyDefault(Hele: XCGUI.HELE; MinLength: Integer; AScrollBarSize: Integer;
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

class procedure TScrollBarUI.ApplyDefaultH(Hele: XCGUI.HELE; MinLength: Integer; AScrollBarSize: Integer;
  AThumbRadius: Integer);
var
  SB: TScrollBarUI;
begin
  SB := TScrollBarUI.Create(Hele, False);
  try
    SB.ApplyDefaultStyle(MinLength, AScrollBarSize, AThumbRadius);
  finally
    SB.Free;
  end;
end;

class procedure TScrollBarUI.ApplyDefaultRecursive(hRoot: XCGUI.HXCGUI);
var
  i, n: Integer;
  hChild: XCGUI.HXCGUI;
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

