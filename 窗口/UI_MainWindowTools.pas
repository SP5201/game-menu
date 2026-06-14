unit UI_MainWindowTools;

interface

uses
  Windows, XCGUI;

const
  /// <summary>系统工具菜单项ID</summary>
  ID_SYS_RESTART_EXPLORER = 301;
  ID_SYS_REGISTRY = 302;
  ID_SYS_MSCONFIG = 303;
  ID_SYS_NETWORK = 304;
  ID_SYS_DEVMGMT = 305;
  ID_SYS_EVENTVWR = 306;
  ID_SYS_GPEDIT = 308;
  ID_SYS_SERVICES = 310;
  ID_SYS_DISKMGMT = 311;
  ID_SYS_DXDIAG = 312;
  ID_SYS_PRINTERS = 313;
  ID_SYS_MOUSE = 314;
  ID_SYS_RESMON = 315;
  /// <summary>常用工具菜单项ID</summary>
  ID_COMMON_SHUTDOWN = 501;
  ID_COMMON_IMAGE_CONV = 502;
  ID_COMMON_QR_CODE = 503;
  /// <summary>设置菜单项ID</summary>
  ID_SETTINGS_CONFIG = 401;
  ID_SETTINGS_ABOUT = 402;
  ID_SETTINGS_DONATE = 403;
  ID_SETTINGS_SHORTCUT = 404;
  ID_SETTINGS_FEEDBACK = 405;

function MainWindowTools_OnButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
function MainWindowTools_OnMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
function MainWindowCommonTools_OnButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
function MainWindowCommonTools_OnMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
function MainWindowSettings_OnButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
function MainWindowSettings_OnMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;

implementation

uses
   SysUtils, ShellAPI, UI_PopupMenu, ShellHelper, UI_QrCodeDialog,
   UI_SettingsDialog, UI_FeedbackDialog;

function MainWindowTools_OnButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  Menu: TPopupMenuUI;
  pt: TPoint;
  rc: TRect;
  AIcon: HICON;
  hMscImg: HIMAGE;
  mscIconDummy: string;
begin
  Result := 0;
  pbHandled^ := True;
  Menu := TPopupMenuUI.Create(hEle);
  try
    AIcon := ExtractIconW(HInstance, PChar('explorer.exe'), 0);
    Menu.AddItemIconData(ID_SYS_RESTART_EXPLORER, '重启资源管理器', 0, AIcon, 0);
    AIcon := ExtractIconW(HInstance, PChar('regedit.exe'), 0);
    Menu.AddItemIconData(ID_SYS_REGISTRY, '注册表编辑', 0, AIcon, 0);
    AIcon := ExtractIconW(HInstance, PChar(ResolveSystemBinaryPathForOsArchitecture('msconfig.exe')), 0);
    Menu.AddItemIconData(ID_SYS_MSCONFIG, '系统配置', 0, AIcon, 0);
    AIcon := ExtractIconW(HInstance, PChar(ResolveSystemBinaryPathForOsArchitecture('shell32.dll')), 17);
    Menu.AddItemIconData(ID_SYS_NETWORK, '网络连接', 0, AIcon, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('devmgmt.msc'), mscIconDummy);
    Menu.AddItemIconImage(ID_SYS_DEVMGMT, '设备管理器', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('eventvwr.msc'), mscIconDummy);
    Menu.AddItemIconImage(ID_SYS_EVENTVWR, '事件查看器', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('gpedit.msc'), mscIconDummy);
    Menu.AddItemIconImage(ID_SYS_GPEDIT, '组策略', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('services.msc'), mscIconDummy);
    Menu.AddItemIconImage(ID_SYS_SERVICES, '服务', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('diskmgmt.msc'), mscIconDummy);
    Menu.AddItemIconImage(ID_SYS_DISKMGMT, '磁盘管理', 0, hMscImg, 0);
    AIcon := ExtractIconW(HInstance, PChar(ResolveSystemBinaryPathForOsArchitecture('resmon.exe')), 0);
    Menu.AddItemIconData(ID_SYS_RESMON, '资源监视器', 0, AIcon, 0);
    AIcon := ExtractIconW(HInstance, PChar(ResolveSystemBinaryPathForOsArchitecture('dxdiag.exe')), 0);
    Menu.AddItemIconData(ID_SYS_DXDIAG, 'DirectX 诊断工具', 0, AIcon, 0);
    AIcon := ExtractIconW(HInstance, PChar(ResolveSystemBinaryPathForOsArchitecture('shell32.dll')), 16);
    Menu.AddItemIconData(ID_SYS_PRINTERS, '查看打印机', 0, AIcon, 0);
    AIcon := ExtractIconW(HInstance, PWideChar(ResolveSystem32ExePath('main.cpl')), 0);
    Menu.AddItemIconData(ID_SYS_MOUSE, '鼠标属性', 0, AIcon, 0);
    XEle_GetRect(hEle, rc);
    pt.X := rc.Right;
    pt.Y := rc.Bottom - XEle_GetHeight(hEle) - 12;
    Menu.Popup(hEle, pt, menu_popup_position_right_bottom);
  finally
    Menu.Free;
  end;
end;

function MainWindowTools_OnMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  hwnd: Windows.HWND;
begin
  Result := 0;
  pbHandled^ := True;
  hwnd := XWidget_GetHWND(hEle);
  case nItem of
    ID_SYS_RESTART_EXPLORER:
      RestartWindowsExplorerAsync;
    ID_SYS_REGISTRY:
      ShellExecuteDefaultVerb(hwnd, 'regedit.exe', '', '', SW_SHOWNORMAL);
    ID_SYS_MSCONFIG:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('msconfig.exe'), '', '', SW_SHOWNORMAL);
    ID_SYS_NETWORK:
      ShellExecuteDefaultVerb(hwnd, 'explorer.exe', 'shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}', '', SW_SHOWNORMAL);
    ID_SYS_DEVMGMT:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('devmgmt.msc'), '', SW_SHOWNORMAL);
    ID_SYS_EVENTVWR:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('eventvwr.msc'), '', SW_SHOWNORMAL);
    ID_SYS_GPEDIT:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('gpedit.msc'), '', SW_SHOWNORMAL);
    ID_SYS_SERVICES:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('services.msc'), '', SW_SHOWNORMAL);
    ID_SYS_DISKMGMT:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('diskmgmt.msc'), '', SW_SHOWNORMAL);
    ID_SYS_RESMON:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('resmon.exe'), '', '', SW_SHOWNORMAL);
    ID_SYS_DXDIAG:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('dxdiag.exe'), '', '', SW_SHOWNORMAL);
    ID_SYS_PRINTERS:
      ShellExecuteDefaultVerb(hwnd, 'explorer.exe', 'shell:::{2227A280-3AEA-1069-A2DE-08002B30309D}', '', SW_SHOWNORMAL);
    ID_SYS_MOUSE:
      ShellExecuteDefaultVerb(hwnd, 'control.exe', 'main.cpl', '', SW_SHOWNORMAL);
  end;
end;

function MainWindowSettings_OnButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  Menu: TPopupMenuUI;
  pt: TPoint;
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;
  Menu := TPopupMenuUI.Create(hEle);
  try
    Menu.AddItemIcon(ID_SETTINGS_CONFIG, '设置', 0, '', 0);
    Menu.AddItemIcon(ID_SETTINGS_DONATE, '赞助作者', 0, '', 0);
    Menu.AddItemIcon(ID_SETTINGS_SHORTCUT, '快捷键', 0, '', 0);
    Menu.AddItemIcon(ID_SETTINGS_FEEDBACK, '反馈', 0, '', 0);
    Menu.AddItemIcon(ID_SETTINGS_ABOUT, '关于', 0, '', 0);
    XEle_GetRect(hEle, rc);
    pt.X := (rc.Left + rc.Right) div 2;
    pt.Y := rc.Bottom;
    Menu.Popup(hEle, pt, menu_popup_position_center_top);
  finally
    Menu.Free;
  end;
end;

function MainWindowSettings_OnMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  hParentWnd: XCGUI.HWINDOW;
  hwndOwner: Windows.HWND;
begin
  Result := 0;
  pbHandled^ := True;
  hParentWnd := XWidget_GetHWINDOW(hEle);
  hwndOwner := XWidget_GetHWND(hEle);
  case nItem of
    ID_SETTINGS_CONFIG:
      TSettingsDialogUI.ShowDialog(hParentWnd);
    ID_SETTINGS_ABOUT:
      MessageBoxW(hwndOwner, 'QDesktop 游戏菜单', '关于', MB_OK or MB_ICONINFORMATION);
    ID_SETTINGS_DONATE:
      ShellExecuteDefaultVerb(hwndOwner, 'https://github.com/sponsors', '', '', SW_SHOWNORMAL);
    ID_SETTINGS_SHORTCUT:
      MessageBoxW(hwndOwner, '快捷键功能待实现', '快捷键', MB_OK or MB_ICONINFORMATION);
    ID_SETTINGS_FEEDBACK:
      TFeedbackDialogUI.ShowDialog(hParentWnd);
  end;
end;

function MainWindowCommonTools_OnButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  Menu: TPopupMenuUI;
  pt: TPoint;
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;
  Menu := TPopupMenuUI.Create(hEle);
  try
    Menu.AddItemIcon(ID_COMMON_SHUTDOWN, '定时关机', 0,'', 0);
    Menu.AddItemIcon(ID_COMMON_IMAGE_CONV, '图片转换', 0, '', 0);
    Menu.AddItemIcon(ID_COMMON_QR_CODE, '二维码生成', 0, '', 0);
    XEle_GetRect(hEle, rc);
    pt.X := rc.Right;
    pt.Y := rc.Bottom - XEle_GetHeight(hEle) - 12;
    Menu.Popup(hEle, pt, menu_popup_position_right_bottom);
  finally
    Menu.Free;
  end;
end;

function MainWindowCommonTools_OnMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  hParentWnd: XCGUI.HWINDOW;
  hwndOwner: Windows.HWND;
begin
  Result := 0;
  pbHandled^ := True;
  hParentWnd := XWidget_GetHWINDOW(hEle);
  hwndOwner := XWidget_GetHWND(hEle);
  case nItem of
    ID_COMMON_SHUTDOWN:
      MessageBoxW(hwndOwner, '定时关机功能待实现', '定时关机', MB_OK or MB_ICONINFORMATION);
    ID_COMMON_IMAGE_CONV:
      MessageBoxW(hwndOwner, '图片转换功能待实现', '图片转换', MB_OK or MB_ICONINFORMATION);
    ID_COMMON_QR_CODE:
      TQrCodeDialogUI.ShowDialog(hParentWnd);
  end;
end;

end.
