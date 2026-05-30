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

function MainWindowTools_OnButtonClick(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
function MainWindowTools_OnMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
function MainWindowCommonTools_OnButtonClick(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
function MainWindowCommonTools_OnMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
function MainWindowSettings_OnButtonClick(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
function MainWindowSettings_OnMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;

implementation

uses
   SysUtils, ShellAPI, UI_PopupMenu, ShellHelper, UI_QrCodeDialog,
   UI_SettingsDialog, UI_MainWindowHelpers;

/// <summary>同步执行并等待进程退出（用于 taskkill 等），避免与后续启动 explorer 竞态。</summary>
function ShellExecuteHiddenWait(hwnd: HWND; const FileName, Parameters: UnicodeString; TimeoutMs: DWORD): Boolean;
var
  sei: TShellExecuteInfo;
  fn, par: UnicodeString;
begin
  Result := False;
  fn := FileName;
  par := Parameters;
  ZeroMemory(@sei, SizeOf(sei));
  sei.cbSize := SizeOf(sei);
  sei.fMask := SEE_MASK_NOCLOSEPROCESS;
  sei.Wnd := hwnd;
  sei.lpFile := PWideChar(fn);
  if par <> '' then
    sei.lpParameters := PWideChar(par);
  sei.nShow := SW_HIDE;
  if not ShellExecuteEx(@sei) then
    Exit;
  if sei.hProcess <> 0 then
  begin
    WaitForSingleObject(sei.hProcess, TimeoutMs);
    CloseHandle(sei.hProcess);
  end;
  Result := True;
end;

function MainWindowTools_OnButtonClick(hEle: HELE; pbHandled: PBOOL): Integer;
var
  Menu: TPopupMenuUI;
  pt: TPoint;
  rc: TRect;
  AIcon: HICON;
  hMscImg: HIMAGE;
  mscIconDummy: string;
  cachePaths: TShellIconCachePaths;
begin
  Result := 0;
  pbHandled^ := True;
  cachePaths := GetShellIconCachePaths;
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
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('devmgmt.msc'), mscIconDummy, cachePaths);
    Menu.AddItemIconImage(ID_SYS_DEVMGMT, '设备管理器', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('eventvwr.msc'), mscIconDummy, cachePaths);
    Menu.AddItemIconImage(ID_SYS_EVENTVWR, '事件查看器', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('gpedit.msc'), mscIconDummy, cachePaths);
    Menu.AddItemIconImage(ID_SYS_GPEDIT, '组策略', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('services.msc'), mscIconDummy, cachePaths);
    Menu.AddItemIconImage(ID_SYS_SERVICES, '服务', 0, hMscImg, 0);
    hMscImg := GetItemImageFromParsingPath(ResolveSystem32MscDocumentPath('diskmgmt.msc'), mscIconDummy, cachePaths);
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
    pt.Y := rc.Bottom - XEle_GetHeight(hEle) - 5;
    Menu.Popup(hEle, pt, menu_popup_position_right_bottom);
  finally
    Menu.Free;
  end;
end;

function MainWindowTools_OnMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer;
var
  WinDir: array[0..MAX_PATH - 1] of Char;
  ExplorerExe: UnicodeString;
  WinDirOnly: UnicodeString;
  hwnd: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  hwnd := XWidget_GetHWND(hEle);
  case nItem of
    ID_SYS_RESTART_EXPLORER:
      begin
        ShellExecuteHiddenWait(hwnd, ResolveSystemBinaryPathForOsArchitecture('taskkill.exe'),
          '/f /im explorer.exe', 30000);
        Sleep(800);
        ShellExecuteHiddenWait(hwnd, ResolveSystemBinaryPathForOsArchitecture('taskkill.exe'),
          '/f /im explorer.exe', 30000);
        Sleep(500);
        if GetWindowsDirectory(WinDir, MAX_PATH) <> 0 then
        begin
          WinDirOnly := UnicodeString(WinDir);
          ExplorerExe := IncludeTrailingPathDelimiter(WinDirOnly) + 'explorer.exe';
          ShellExecuteW(hwnd, 'open', PWideChar(ExplorerExe), nil, PWideChar(WinDirOnly), SW_SHOWNORMAL);
        end
        else
          ShellExecuteW(hwnd, 'open', 'explorer.exe', nil, nil, SW_SHOWNORMAL);
      end;
    ID_SYS_REGISTRY:
      ShellExecuteDefaultVerb(hwnd, 'regedit.exe', '', '');
    ID_SYS_MSCONFIG:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('msconfig.exe'), '', '');
    ID_SYS_NETWORK:
      ShellExecuteW(hwnd, 'open', 'explorer.exe', 'shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}', nil, SW_SHOWNORMAL);
    ID_SYS_DEVMGMT:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('devmgmt.msc'), '');
    ID_SYS_EVENTVWR:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('eventvwr.msc'), '');
    ID_SYS_GPEDIT:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('gpedit.msc'), '');
    ID_SYS_SERVICES:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('services.msc'), '');
    ID_SYS_DISKMGMT:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('mmc.exe'), ResolveSystem32MscDocumentPath('diskmgmt.msc'), '');
    ID_SYS_RESMON:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('resmon.exe'), '', '');
    ID_SYS_DXDIAG:
      ShellExecuteDefaultVerb(hwnd, ResolveSystemBinaryPathForOsArchitecture('dxdiag.exe'), '', '');
    ID_SYS_PRINTERS:
      ShellExecuteW(hwnd, 'open', 'explorer.exe', 'shell:::{2227A280-3AEA-1069-A2DE-08002B30309D}', nil, SW_SHOWNORMAL);
    ID_SYS_MOUSE:
      ShellExecuteW(hwnd, 'open', 'control.exe', 'main.cpl', nil, SW_SHOWNORMAL);
  end;
end;

function MainWindowSettings_OnButtonClick(hEle: HELE; pbHandled: PBOOL): Integer;
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
    Menu.AddItemIcon(ID_SETTINGS_ABOUT, '关于', 0, '', 0);
    XEle_GetRect(hEle, rc);
    pt.X := (rc.Left + rc.Right) div 2;
    pt.Y := rc.Bottom;
    Menu.Popup(hEle, pt, menu_popup_position_center_top);
  finally
    Menu.Free;
  end;
end;

function MainWindowSettings_OnMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer;
var
  hParentWnd: HWND;
begin
  Result := 0;
  pbHandled^ := True;
  hParentWnd := XWidget_GetHWND(hEle);
  case nItem of
    ID_SETTINGS_CONFIG:
      TSettingsDialogUI.ShowDialog(hParentWnd);
    ID_SETTINGS_ABOUT:
      MessageBoxW(hParentWnd, 'QDesktop 游戏菜单', '关于', MB_OK or MB_ICONINFORMATION);
    ID_SETTINGS_DONATE:
      ShellExecuteW(hParentWnd, 'open', 'https://github.com/sponsors', nil, nil, SW_SHOWNORMAL);
    ID_SETTINGS_SHORTCUT:
      MessageBoxW(hParentWnd, '快捷键功能待实现', '快捷键', MB_OK or MB_ICONINFORMATION);
  end;
end;

function MainWindowCommonTools_OnButtonClick(hEle: HELE; pbHandled: PBOOL): Integer;
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
    pt.Y := rc.Bottom - XEle_GetHeight(hEle) - 5;
    Menu.Popup(hEle, pt, menu_popup_position_right_bottom);
  finally
    Menu.Free;
  end;
end;

function MainWindowCommonTools_OnMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer;
var
  hParentWnd: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  hParentWnd := XWidget_GetHWINDOW(hEle);
  case nItem of
    ID_COMMON_SHUTDOWN:
      MessageBoxW(XWidget_GetHWND(hEle), '定时关机功能待实现', '定时关机', MB_OK or MB_ICONINFORMATION);
    ID_COMMON_IMAGE_CONV:
      MessageBoxW(XWidget_GetHWND(hEle), '图片转换功能待实现', '图片转换', MB_OK or MB_ICONINFORMATION);
    ID_COMMON_QR_CODE:
      TQrCodeDialogUI.ShowDialog(hParentWnd);
  end;
end;

end.
