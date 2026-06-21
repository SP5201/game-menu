unit UI_MainWindowGeometry;

{ 主窗口几何与布局辅助：窗口尺寸约束、位置保存/恢复、默认滚动条样式、
  列表布局应用、搜索区/过滤工具栏重排。从 UI_MainWindow 拆出，纯文本搬运。 }

interface

uses
  Windows, XCGUI, UI_ListView;

procedure ApplyDefaultStyles(hXCGUI: hXCGUI);
procedure ClampWindowBoundsToWorkArea(var ALeft, ATop, AWidth, AHeight: Integer);
procedure RestoreMainWindowBounds(AWnd: HWINDOW);
procedure SaveMainWindowBounds(AWnd: HWINDOW);
procedure ApplyListViewLayoutFromConfig(AListView: TListViewUI);
procedure AdjustMainSearchAreaLayout;

implementation

uses
  Math, AppConfig, UI_ScrollBar;

procedure ApplyDefaultStyles(hXCGUI: hXCGUI);
var
  i, n: Integer;
  hChild: XCGUI.HXCGUI;
begin
  if XC_IsSViewExtend(hXCGUI) then
    TScrollBarUI.ApplyDefault(hXCGUI);
  if XC_IsHWINDOW(hXCGUI) then
  begin
    n := XWnd_GetChildCount(hXCGUI);
    for i := 0 to n - 1 do
    begin
      hChild := XWnd_GetChildByIndex(hXCGUI, i);
      ApplyDefaultStyles(hChild);
    end;
  end
  else if XC_IsHELE(hXCGUI) then
  begin
    n := XEle_GetChildCount(hXCGUI);
    for i := 0 to n - 1 do
    begin
      hChild := XEle_GetChildByIndex(hXCGUI, i);
      ApplyDefaultStyles(hChild);
    end;
  end;
end;

procedure ClampWindowBoundsToWorkArea(var ALeft, ATop, AWidth, AHeight: Integer);
var
  workRect: TRect;
begin
  AWidth := Max(AWidth, 640);
  AHeight := Max(AHeight, 420);

  workRect := TRect.Create(GetSystemMetrics(SM_XVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN), GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN));
  if workRect.IsEmpty then
    workRect := TRect.Create(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));

  AWidth := Min(AWidth, workRect.Width);
  AHeight := Min(AHeight, workRect.Height);
  ALeft := EnsureRange(ALeft, workRect.Left, workRect.Right - AWidth);
  ATop := EnsureRange(ATop, workRect.Top, workRect.Bottom - AHeight);
end;

procedure RestoreMainWindowBounds(AWnd: HWINDOW);
var
  L, T, W, H: Integer;
begin
  if TAppConfig.TryGetMainWindowBounds(L, T, W, H) then
  begin
    ClampWindowBoundsToWorkArea(L, T, W, H);
    XWnd_SetWindowPos(AWnd, 0, L, T, W, H, SWP_NOZORDER or SWP_NOACTIVATE);
  end;
  if TAppConfig.IsMainWindowMaximized then
    XWnd_MaxWindow(AWnd, True);
end;

procedure SaveMainWindowBounds(AWnd: HWINDOW);
var
  rc: TRect;
  hWndReal: Windows.HWND;
  wp: TWindowPlacement;
  isMaximized: Boolean;
begin
  if not XC_IsHWINDOW(AWnd) then
    Exit;
  hWndReal := XWnd_GetHWND(AWnd);
  wp.length := SizeOf(TWindowPlacement);
  if GetWindowPlacement(hWndReal, wp) then
  begin
    rc := wp.rcNormalPosition;
    isMaximized := (wp.showCmd = SW_SHOWMAXIMIZED)
      or ((wp.showCmd = SW_SHOWMINIMIZED) and ((wp.flags and WPF_RESTORETOMAXIMIZED) <> 0));
  end
  else
  begin
    if IsIconic(hWndReal) then
      Exit;
    isMaximized := IsZoomed(hWndReal);
    XWnd_GetRect(AWnd, rc);
  end;

  TAppConfig.SetMainWindowBounds(rc.Left, rc.Top, rc.Right - rc.Left, rc.Bottom - rc.Top);
  TAppConfig.SetMainWindowMaximized(isMaximized);
  TAppConfig.Save;
end;

procedure ApplyListViewLayoutFromConfig(AListView: TListViewUI);
begin
  if AListView = nil then
    Exit;
  AListView.ApplyLayoutSettings(TAppConfig.GetListColumnSpace, TAppConfig.GetListRowSpace,
    TAppConfig.GetListItemCornerRadius, TAppConfig.GetListScrollBarSize,
    TAppConfig.GetListScrollSliderMinLen, TAppConfig.GetListScrollThumbRadius);
end;

procedure AdjustMainSearchAreaLayout;
var
  hSearchRow, hHeaderBar: HELE;
begin
  hSearchRow := XC_GetObjectByName('layout_main_search_row');
  if XC_GetObjectType(hSearchRow) <> XC_ERROR then
  begin
    XEle_AdjustLayoutEx(hSearchRow, adjustLayout_all);
    XEle_Redraw(hSearchRow);
  end;
  hHeaderBar := XC_GetObjectByName('layout_main_header_bar');
  if XC_GetObjectType(hHeaderBar) <> XC_ERROR then
    XEle_AdjustLayoutEx(hHeaderBar, adjustLayout_all);
end;

end.
