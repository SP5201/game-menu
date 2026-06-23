program QDesktop;


{$IF CompilerVersion >= 21.0}
{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$IFEND}

{$R *.dres}

uses
  ActiveX,
  Windows,
  SysUtils,
  AppPaths,
  AppConfig,
  XCGUI,
  SafeLog,
  PawnIoClient,
  UI_MainWindow;

const
  APP_MUTEX_NAME = 'QDesktop_SingleInstance_Mutex';

var
  FormUI: TMainFormUI;
  hMutex: THandle;
  hFoundWindow: HWND;
  configExisted: Boolean;

begin
  ConfigureNativeDllSearchPath;
  // 检查是否已有实例运行
  hMutex := CreateMutex(nil, False, APP_MUTEX_NAME);
  if (hMutex = 0) or (GetLastError = DWORD(ERROR_ALREADY_EXISTS)) then
  begin
    // 已存在实例，查找并激活旧窗口（通过窗口标题查找）
    hFoundWindow := FindWindow(nil, 'QDesktop');
    if hFoundWindow = HWND(0) then
      hFoundWindow := FindWindow('XCGUI_WINDOW', nil);
    if hFoundWindow <> HWND(0) then
    begin
      ShowWindow(hFoundWindow, SW_RESTORE);
      SetForegroundWindow(hFoundWindow);
    end;
    Exit;
  end;

  CoInitialize(nil);
  try
{$IFDEF DEBUG}
    XC_EnableResMonitor(True);
    XC_EnableDebugFile(True);
{$ELSE}
    XC_EnableResMonitor(False);
{$ENDIF}
    SafeLogStartupBegin;
    configExisted := FileExists(TAppConfig.ConfigFilePath);
    TAppConfig.Load;
    if configExisted then
      SafeLogStartupAppendStep('配置', '加载配置文件', True)
    else
      SafeLogStartupAppendStep('配置', '已创建默认配置 QDesktop.ini', True);
    TAppSettings.SyncRunWithWindowsRegistry(TAppConfig.IsRunWithWindows);
    if not TAppSettings.InitXCGUI then
    begin
      SafeLogStartupAppendStep('资源', 'XCGUI 初始化失败', False);
      SafeLogStartupCommit;
      Exit;
    end;
    if XC_IsEnableD2D then
      SafeLogStartupAppendStep('资源', '加载程序界面引擎 D2D模式', True)
    else
      SafeLogStartupAppendStep('资源', '加载程序界面引擎 GDI模式', True);
    TAppSettings.ApplyPaintFrequency;
    XC_LoadResource('Resource\Resource.res');
    XC_SetDefaultFont(XRes_GetFont('YaHei_10'));
    try
      XC_EnableDPI(True);
      XC_EnableAutoDPI(True);
      FormUI := TMainFormUI.LoadLayout('Resource\Layout\MainWindow.xml');
      FormUI.Show;
      XRunXCGUI();
    finally
      PawnIoClientShutdown;
      XExitXCGUI();
      if hMutex <> THandle(0) then
        CloseHandle(hMutex);
    end;
  finally
    CoUninitialize;
  end;
end.

