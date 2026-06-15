unit UI_MainWindowStat;

interface

uses
  Windows, Messages, SysUtils, Classes, SyncObjs, XCGUI, UI_Button, UI_Theme,
  UI_ProgressBar, UI_InfoListPopup, NetTrafficMonitor, HardwareMonitor,
  ExternalIpFetcher, WeatherFetcher, WeatherParser,
  CpuInfo, MemInfo, GpuInfo, NetInfo, AppConfig;

type
  TMainWindowStat = class
  private
    class var
      CShapeStatNetDown: HXCGUI;
      CShapeStatNetUp: HXCGUI;
      CShapeStatCpu: HXCGUI;
      CProgStatCpu: HXCGUI;
      CShapeStatMem: HXCGUI;
      CProgStatRam: HXCGUI;
      CShapeStatGpu: HXCGUI;
      CProgStatGpu: HXCGUI;
      CShapePicNetDown: HXCGUI;
      CShapePicNetUp: HXCGUI;
      CShapeStatExtIp: HXCGUI;
      CLayoutStatExtIp: HELE;
      CLayoutStatNet: HELE;
      CLayoutStatCpu: HELE;
      CLayoutStatRam: HELE;
      CLayoutStatGpu: HELE;
      CLastCpuUsageText: string;
      CLastMemUsageText: string;
      CLastGpuUsageText: string;
      CLastStatNetDown: string;
      CLastStatNetUp: string;
      CShapeStatWeather: HXCGUI;
      CBtnStatWeather: HELE;
      CLastExtIpInfo: TExternalIpInfo;
      CLastWeatherInfo: TWeatherInfo;
      FNetTrafficThread: TNetTrafficSamplerThread;
      FHardwareThread: THardwareSamplerThread;
      FExternalIpThread: TExternalIpFetcherThread;
      FWeatherThread: TWeatherFetcherThread;
      FHintPreloadThread: TThread;
      FMainFormHWINDOW: HWINDOW;
      FMainUiThreadId: DWORD;
      FCacheLock: TCriticalSection;
    class function IsMainUiThread: Boolean;
    class function TryPostStatMessage(AMsg: UINT; ALParam: LPARAM): Boolean;
    class procedure SetMainStatNet(const sDown, sUp: string);
    class procedure SetMainStatHardware(const ACpuText, AMemText, AGpuText: string);
    class procedure SetMainStatExtIp(const AInfo: TExternalIpInfo);
    class procedure SetMainStatWeather(const AInfo: TWeatherInfo);
    class procedure SetMainStatWeatherLoading;
    class function BuildStatIpWeatherHintText: string;
    class function BuildStatNetHintText: string;
    class function BuildStatCpuHintText: string;
    class function BuildStatMemHintText: string;
    class function BuildStatGpuHintText: string;
    class procedure RefreshStatIpWeatherHoverHint;
    class procedure RefreshStatCpuHoverHint;
    class procedure RefreshStatGpuHoverHint;
    class procedure DrainPendingStatMessages;
  public
    class procedure Init(const AMainWindow: HWINDOW; AUiThreadId: DWORD; const ABtnStatWeather: HELE);
    class procedure StopWorkers;
    class function TryHandleWinProc(Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Boolean;
    class procedure SyncNetTrafficSamplerWithConfig;
    class procedure PostStatNet(const sDown, sUp: string);
    class procedure PostStatHardware(const ACpuText, AMemText, AGpuText: string);
    class procedure PostStatExtIp(const AInfo: TExternalIpInfo);
    class procedure PostStatWeather(const AInfo: TWeatherInfo);
    class procedure PostStatWeatherLoading;
    class procedure PostStatHintReady;
  end;

const
  WM_QD_STAT_NET = WM_APP + 100;
  WM_QD_STAT_HARDWARE = WM_APP + 101;
  WM_QD_STAT_EXTIP = WM_APP + 102;
  WM_QD_STAT_WEATHER = WM_APP + 103;
  WM_QD_STAT_WEATHER_LOADING = WM_APP + 104;
  WM_QD_STAT_HINT_READY = WM_APP + 105;

implementation

uses
  Math, NetHttpWorker, UI_SafeLogWindow;

type
  PStatNetMsg = ^TStatNetMsg;
  TStatNetMsg = record
    DownText: string;
    UpText: string;
  end;

  PStatHardwareMsg = ^TStatHardwareMsg;
  TStatHardwareMsg = record
    CpuText: string;
    MemText: string;
    GpuText: string;
  end;

  PStatExtIpMsg = ^TStatExtIpMsg;
  TStatExtIpMsg = record
    Info: TExternalIpInfo;
  end;

  PStatWeatherMsg = ^TStatWeatherMsg;
  TStatWeatherMsg = record
    Info: TWeatherInfo;
  end;

function ResolveStatLayoutEle(const ALayoutName: string; const hFallbackShape: HXCGUI): HELE;
begin
  Result := XC_GetObjectByName(PWideChar(ALayoutName));
  if XC_GetObjectType(Result) <> XC_ELE_LAYOUT then
  begin
    if XC_GetObjectType(hFallbackShape) <> XC_ERROR then
      Result := XWidget_GetParentEle(hFallbackShape);
  end;
  if XC_GetObjectType(Result) <> XC_ELE_LAYOUT then
    Result := XC_ERROR;
end;

procedure BindStatHoverBlock(const ALayoutName: string; const hFallbackShape: HXCGUI;
  var ALayoutOut: HELE; const AHint: TInfoListGetTextFunc);
begin
  ALayoutOut := ResolveStatLayoutEle(ALayoutName, hFallbackShape);
  if XC_GetObjectType(ALayoutOut) <> XC_ELE_LAYOUT then
    Exit;
  XEle_EnableMouseThrough(ALayoutOut, False);
  TInfoListPopupUI.BindHover(ALayoutOut, AHint, True, -2);
end;

procedure StatNetBridge(const sDown, sUp: string);
begin
  TMainWindowStat.PostStatNet(sDown, sUp);
end;

procedure StatHardwareBridge(const ACpuText, AMemText, AGpuText: string);
begin
  TMainWindowStat.PostStatHardware(ACpuText, AMemText, AGpuText);
end;

procedure StatExtIpBridge(const AInfo: TExternalIpInfo);
begin
  TMainWindowStat.PostStatExtIp(AInfo);
end;

procedure StatWeatherBridge(const AInfo: TWeatherInfo);
begin
  TMainWindowStat.PostStatWeather(AInfo);
end;

procedure StatWeatherLoadingBridge;
begin
  TMainWindowStat.PostStatWeatherLoading;
end;

type
  THardwareHintPreloadThread = class(TThread)
  public
    constructor Create;
  protected
    procedure Execute; override;
  end;

constructor THardwareHintPreloadThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
end;

procedure THardwareHintPreloadThread.Execute;
begin
  CpuPreloadHintData;
  MemPreloadHintData;
  GpuPreloadHintData;
  NetPreloadHintData;
  TMainWindowStat.PostStatHintReady;
  MemEnrichStaticInfo;
  CpuPreloadSensors;
  GpuPreloadSensors;
  TMainWindowStat.PostStatHintReady;
end;

function StatIpWeatherHintBridge: string;
begin
  Result := TMainWindowStat.BuildStatIpWeatherHintText;
end;

function StatNetHintBridge: string;
begin
  Result := TMainWindowStat.BuildStatNetHintText;
end;

function StatCpuHintBridge: string;
begin
  Result := TMainWindowStat.BuildStatCpuHintText;
end;

function StatMemHintBridge: string;
begin
  Result := TMainWindowStat.BuildStatMemHintText;
end;

function StatGpuHintBridge: string;
begin
  Result := TMainWindowStat.BuildStatGpuHintText;
end;

class function TMainWindowStat.IsMainUiThread: Boolean;
begin
  Result := (FMainUiThreadId = 0) or (GetCurrentThreadId = FMainUiThreadId);
end;

class function TMainWindowStat.TryPostStatMessage(AMsg: UINT; ALParam: LPARAM): Boolean;
begin
  Result := (XC_GetObjectType(FMainFormHWINDOW) = XC_WINDOW) and
    XC_PostMessage(FMainFormHWINDOW, AMsg, 0, ALParam);
end;

class procedure TMainWindowStat.PostStatNet(const sDown, sUp: string);
var
  payload: PStatNetMsg;
begin
  if not IsMainUiThread then
  begin
    New(payload);
    payload.DownText := sDown;
    payload.UpText := sUp;
    if not TryPostStatMessage(WM_QD_STAT_NET, LPARAM(payload)) then
      Dispose(payload);
    Exit;
  end;
  SetMainStatNet(sDown, sUp);
end;

class procedure TMainWindowStat.PostStatHardware(const ACpuText, AMemText, AGpuText: string);
var
  payload: PStatHardwareMsg;
begin
  if not IsMainUiThread then
  begin
    New(payload);
    payload.CpuText := ACpuText;
    payload.MemText := AMemText;
    payload.GpuText := AGpuText;
    if not TryPostStatMessage(WM_QD_STAT_HARDWARE, LPARAM(payload)) then
      Dispose(payload);
    Exit;
  end;
  SetMainStatHardware(ACpuText, AMemText, AGpuText);
end;

class procedure TMainWindowStat.PostStatExtIp(const AInfo: TExternalIpInfo);
var
  payload: PStatExtIpMsg;
begin
  if not IsMainUiThread then
  begin
    New(payload);
    payload.Info := AInfo;
    if not TryPostStatMessage(WM_QD_STAT_EXTIP, LPARAM(payload)) then
      Dispose(payload);
    Exit;
  end;
  SetMainStatExtIp(AInfo);
end;

class procedure TMainWindowStat.PostStatWeather(const AInfo: TWeatherInfo);
var
  payload: PStatWeatherMsg;
begin
  if not IsMainUiThread then
  begin
    New(payload);
    payload.Info := AInfo;
    if not TryPostStatMessage(WM_QD_STAT_WEATHER, LPARAM(payload)) then
      Dispose(payload);
    Exit;
  end;
  SetMainStatWeather(AInfo);
end;

class procedure TMainWindowStat.PostStatWeatherLoading;
begin
  if not IsMainUiThread then
  begin
    TryPostStatMessage(WM_QD_STAT_WEATHER_LOADING, 0);
    Exit;
  end;
  SetMainStatWeatherLoading;
end;

class procedure TMainWindowStat.PostStatHintReady;
begin
  if not IsMainUiThread then
  begin
    TryPostStatMessage(WM_QD_STAT_HINT_READY, 0);
    Exit;
  end;
  TInfoListPopupUI.NotifyContentChanged;
end;

class procedure TMainWindowStat.Init(const AMainWindow: HWINDOW; AUiThreadId: DWORD; const ABtnStatWeather: HELE);
var
  hLabelExtIp: HXCGUI;
  hLabelCpu: HXCGUI;
  hLabelRam: HXCGUI;
  hLabelGpu: HXCGUI;
  hSepWeatherNet: HXCGUI;
  hSepStatusTop: HXCGUI;
  hSvgNetDown: HSVG;
  hSvgNetUp: HSVG;
begin
  FMainFormHWINDOW := AMainWindow;
  FMainUiThreadId := AUiThreadId;
  CBtnStatWeather := ABtnStatWeather;
  CShapeStatNetDown := XC_GetObjectByName('txt_main_stat_net_down');
  CShapeStatNetUp := XC_GetObjectByName('txt_main_stat_net_up');
  CShapeStatCpu := XC_GetObjectByName('txt_main_stat_cpu');
  CProgStatCpu := XC_GetObjectByName('prog_main_stat_cpu');
  TProgressBarUI.ApplyDefault(CProgStatCpu);
  CShapeStatMem := XC_GetObjectByName('txt_main_stat_mem');
  CProgStatRam := XC_GetObjectByName('prog_main_stat_ram');
  TProgressBarUI.ApplyDefault(CProgStatRam, UITheme_StatRamFill);
  CShapeStatGpu := XC_GetObjectByName('txt_main_stat_gpu');
  CProgStatGpu := XC_GetObjectByName('prog_main_stat_gpu');
  TProgressBarUI.ApplyDefault(CProgStatGpu, UITheme_StatGpuFill);
  CShapePicNetDown := XC_GetObjectByName('pic_main_stat_net_down');
  CShapePicNetUp := XC_GetObjectByName('pic_main_stat_net_up');
  CLastCpuUsageText := '--';
  CLastMemUsageText := '--';
  CLastGpuUsageText := '--';
  CShapeStatExtIp := XC_GetObjectByName('txt_main_stat_ext_ip');
  CShapeStatWeather := XC_GetObjectByName('txt_main_stat_weather');
  CLastExtIpInfo := EmptyExternalIpInfo;
  CLastWeatherInfo := EmptyWeatherInfo;
  hLabelExtIp := XC_GetObjectByName('txt_main_stat_label_ext_ip');
  hLabelCpu := XC_GetObjectByName('txt_main_stat_label_cpu');
  hLabelRam := XC_GetObjectByName('txt_main_stat_label_ram');
  hLabelGpu := XC_GetObjectByName('txt_main_stat_label_gpu');
  hSepWeatherNet := XC_GetObjectByName('sep_main_stat_weather_net_up');
  hSepStatusTop := XC_GetObjectByName('sep_main_status_bar_top');
  XShapeText_SetTextColor(hLabelExtIp, UITheme_StatLabel);
  XShapeText_SetTextColor(CShapeStatExtIp, UITheme_TextPrimary);
  XShapeText_SetTextColor(CShapeStatWeather, UITheme_TextPrimary);
  XShapeRect_SetFillColor(hSepWeatherNet, UITheme_StatBarTopLine);
  XShapeText_SetTextColor(hLabelCpu, UITheme_StatLabel);
  XShapeText_SetTextColor(hLabelRam, UITheme_StatLabel);
  XShapeText_SetTextColor(hLabelGpu, UITheme_StatLabel);
  XShapeRect_SetFillColor(hSepStatusTop, UITheme_StatBarTopLine);
  XShapeText_SetTextColor(CShapeStatNetDown, UITheme_TextPrimary);
  XShapeText_SetTextColor(CShapeStatNetUp, UITheme_TextPrimary);
  XShapeText_SetTextColor(CShapeStatCpu, UITheme_ProgressBarFill);
  XShapeText_SetTextColor(CShapeStatMem, UITheme_StatRamFill);
  XShapeText_SetTextColor(CShapeStatGpu, UITheme_StatGpuFill);
  hSvgNetDown := XSvg_LoadFile('Resource\NetDown.svg');
  XSvg_SetSize(hSvgNetDown, 15, 15);
  XSvg_SetUserFillColor(hSvgNetDown, UITheme_StatNetDownFill, True);
  { XImage_LoadSvg 接管 hSvgNetDown，勿再 XSvg_Destroy }
  XShapePic_SetImage(CShapePicNetDown, XImage_LoadSvg(hSvgNetDown));
  hSvgNetUp := XSvg_LoadFile('Resource\NetUp.svg');
  XSvg_SetSize(hSvgNetUp, 15, 15);
  XSvg_SetUserFillColor(hSvgNetUp, UITheme_StatNetUpFill, True);
  XShapePic_SetImage(CShapePicNetUp, XImage_LoadSvg(hSvgNetUp));
  BindStatHoverBlock('layout_main_stat_ext_ip', XC_ERROR, CLayoutStatExtIp, @StatIpWeatherHintBridge);
  BindStatHoverBlock('layout_main_stat_net', CShapeStatNetUp, CLayoutStatNet, @StatNetHintBridge);
  BindStatHoverBlock('layout_main_stat_cpu', CShapeStatCpu, CLayoutStatCpu, @StatCpuHintBridge);
  BindStatHoverBlock('layout_main_stat_ram', CShapeStatMem, CLayoutStatRam, @StatMemHintBridge);
  BindStatHoverBlock('layout_main_stat_gpu', CShapeStatGpu, CLayoutStatGpu, @StatGpuHintBridge);
  FNetTrafficThread := TNetTrafficSamplerThread.Create;
  FNetTrafficThread.OnUpdate := StatNetBridge;
  FNetTrafficThread.Start;
  SyncNetTrafficSamplerWithConfig;
  FHardwareThread := THardwareSamplerThread.Create;
  FHardwareThread.OnUpdate := StatHardwareBridge;
  FHardwareThread.Start;
  FExternalIpThread := TExternalIpFetcherThread.Create;
  FExternalIpThread.OnUpdate := StatExtIpBridge;
  FExternalIpThread.Start;
  FWeatherThread := TWeatherFetcherThread.Create;
  FWeatherThread.OnUpdate := StatWeatherBridge;
  FWeatherThread.OnLoading := StatWeatherLoadingBridge;
  FWeatherThread.Start;
  FHintPreloadThread := THardwareHintPreloadThread.Create;
  FHintPreloadThread.Start;
end;

class procedure TMainWindowStat.DrainPendingStatMessages;
var
  hRealWnd: Windows.HWND;
  msg: TMsg;
  handled: BOOL;
begin
  if XC_GetObjectType(FMainFormHWINDOW) <> XC_WINDOW then
    Exit;
  hRealWnd := XWnd_GetHWND(FMainFormHWINDOW);
  if hRealWnd = 0 then
    Exit;
  handled := False;
  while PeekMessageW(msg, hRealWnd, WM_QD_STAT_NET, WM_QD_STAT_HINT_READY, PM_REMOVE) do
  begin
    if not TryHandleWinProc(msg.message, msg.wParam, msg.lParam, @handled) then
    begin
      TranslateMessage(msg);
      DispatchMessageW(msg);
    end;
  end;
end;

class procedure TMainWindowStat.StopWorkers;
begin
  if (FNetTrafficThread = nil) and (FHardwareThread = nil) and
     (FExternalIpThread = nil) and (FWeatherThread = nil) and (FHintPreloadThread = nil) then
    Exit;
  NetHttpAbortAllPending;
  if FNetTrafficThread <> nil then
  begin
    FNetTrafficThread.OnUpdate := nil;
    FNetTrafficThread.RequestStop;
  end;
  if FHardwareThread <> nil then
  begin
    FHardwareThread.OnUpdate := nil;
    FHardwareThread.RequestStop;
  end;
  if FExternalIpThread <> nil then
  begin
    FExternalIpThread.OnUpdate := nil;
    FExternalIpThread.RequestStop;
  end;
  if FWeatherThread <> nil then
  begin
    FWeatherThread.OnUpdate := nil;
    FWeatherThread.OnLoading := nil;
    FWeatherThread.RequestStop;
  end;
  TSafeLogWindow.CloseIfOpen;
  DrainPendingStatMessages;
  if FHintPreloadThread <> nil then
  begin
    FHintPreloadThread.Terminate;
    FHintPreloadThread.WaitFor;
  end;
  FreeAndNil(FHintPreloadThread);
  FreeAndNil(FNetTrafficThread);
  FreeAndNil(FHardwareThread);
  FreeAndNil(FExternalIpThread);
  FreeAndNil(FWeatherThread);
  FMainFormHWINDOW := 0;
end;

class function TMainWindowStat.TryHandleWinProc(Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Boolean;
var
  netMsg: PStatNetMsg;
  hwMsg: PStatHardwareMsg;
  ipMsg: PStatExtIpMsg;
  weatherMsg: PStatWeatherMsg;
begin
  Result := False;
  case Msg of
    WM_QD_STAT_NET:
      begin
        netMsg := PStatNetMsg(lParam);
        if netMsg <> nil then
        try
          SetMainStatNet(netMsg.DownText, netMsg.UpText);
        finally
          Dispose(netMsg);
        end;
        pbHandled^ := True;
        Result := True;
      end;
    WM_QD_STAT_HARDWARE:
      begin
        hwMsg := PStatHardwareMsg(lParam);
        if hwMsg <> nil then
        try
          SetMainStatHardware(hwMsg.CpuText, hwMsg.MemText, hwMsg.GpuText);
        finally
          Dispose(hwMsg);
        end;
        pbHandled^ := True;
        Result := True;
      end;
    WM_QD_STAT_EXTIP:
      begin
        ipMsg := PStatExtIpMsg(lParam);
        if ipMsg <> nil then
        try
          SetMainStatExtIp(ipMsg.Info);
        finally
          Dispose(ipMsg);
        end;
        pbHandled^ := True;
        Result := True;
      end;
    WM_QD_STAT_WEATHER:
      begin
        weatherMsg := PStatWeatherMsg(lParam);
        if weatherMsg <> nil then
        try
          SetMainStatWeather(weatherMsg.Info);
        finally
          Dispose(weatherMsg);
        end;
        pbHandled^ := True;
        Result := True;
      end;
    WM_QD_STAT_WEATHER_LOADING:
      begin
        SetMainStatWeatherLoading;
        pbHandled^ := True;
        Result := True;
      end;
    WM_QD_STAT_HINT_READY:
      begin
        TInfoListPopupUI.NotifyContentChanged;
        pbHandled^ := True;
        Result := True;
      end;
  end;
end;

class procedure TMainWindowStat.SetMainStatNet(const sDown, sUp: string);
var
  hBar: hXCGUI;
begin
  if XC_GetObjectType(CShapeStatNetDown) <> XC_SHAPE_TEXT then
    Exit;
  if (sDown = CLastStatNetDown) and (sUp = CLastStatNetUp) then
    Exit;
  CLastStatNetDown := sDown;
  CLastStatNetUp := sUp;
  XShapeText_SetText(CShapeStatNetDown, PWideChar(sDown));
  XShapeText_SetText(CShapeStatNetUp, PWideChar(sUp));
  XShape_Redraw(CShapeStatNetDown);
  XShape_Redraw(CShapeStatNetUp);
  hBar := XC_GetObjectByID(XWidget_GetHWINDOW(CShapeStatNetDown), 1001);
  if XC_GetObjectType(hBar) <> XC_ERROR then
    XEle_Redraw(hBar);
end;

class function TMainWindowStat.BuildStatIpWeatherHintText: string;
var
  extIp: TExternalIpInfo;
  weather: TWeatherInfo;
begin
  if FCacheLock = nil then
    Exit('');
  FCacheLock.Enter;
  try
    extIp := CLastExtIpInfo;
    weather := CLastWeatherInfo;
  finally
    FCacheLock.Leave;
  end;
  Result := ExternalIpFormatTooltip(extIp) + sLineBreak + WeatherFormatTooltip(weather, False);
end;

class function TMainWindowStat.BuildStatNetHintText: string;
begin
  Result := NetFormatAdapterTooltip;
end;

class function TMainWindowStat.BuildStatCpuHintText: string;
var
  usageText: string;
begin
  if FCacheLock = nil then
    Exit('');
  FCacheLock.Enter;
  try
    usageText := CLastCpuUsageText;
  finally
    FCacheLock.Leave;
  end;
  Result := CpuFormatTooltip(usageText);
end;

class function TMainWindowStat.BuildStatMemHintText: string;
var
  usageText: string;
begin
  if FCacheLock = nil then
    Exit('');
  FCacheLock.Enter;
  try
    usageText := CLastMemUsageText;
  finally
    FCacheLock.Leave;
  end;
  Result := MemFormatTooltip(usageText);
end;

class function TMainWindowStat.BuildStatGpuHintText: string;
var
  usageText: string;
begin
  if FCacheLock = nil then
    Exit('');
  FCacheLock.Enter;
  try
    usageText := CLastGpuUsageText;
  finally
    FCacheLock.Leave;
  end;
  Result := GpuFormatTooltip(usageText);
end;

class procedure TMainWindowStat.RefreshStatIpWeatherHoverHint;
begin
  TInfoListPopupUI.NotifyContentChanged;
end;

class procedure TMainWindowStat.RefreshStatCpuHoverHint;
begin
  if TInfoListPopupUI.IsHoverBoundTo(CLayoutStatCpu) then
    TInfoListPopupUI.NotifyContentChanged;
end;

class procedure TMainWindowStat.RefreshStatGpuHoverHint;
begin
  if TInfoListPopupUI.IsHoverBoundTo(CLayoutStatGpu) then
    TInfoListPopupUI.NotifyContentChanged;
end;

class procedure TMainWindowStat.SetMainStatExtIp(const AInfo: TExternalIpInfo);
var
  hBar: hXCGUI;
  displayText: string;
begin
  if XC_GetObjectType(CShapeStatExtIp) <> XC_SHAPE_TEXT then
    Exit;
  FCacheLock.Enter;
  try
    CLastExtIpInfo := AInfo;
  finally
    FCacheLock.Leave;
  end;
  displayText := ExternalIpFormatDisplay(AInfo);
  XShapeText_SetText(CShapeStatExtIp, PWideChar(displayText));
  RefreshStatIpWeatherHoverHint;
  TWeatherFetcherThread.SetLocationFromIp(AInfo.City, AInfo.Latitude, AInfo.Longitude);
  hBar := XC_GetObjectByID(XWidget_GetHWINDOW(CShapeStatExtIp), 1001);
  if XC_GetObjectType(hBar) <> XC_ERROR then
  begin
    XEle_AdjustLayout(hBar);
    XEle_Redraw(hBar);
  end;
end;

class procedure TMainWindowStat.SetMainStatWeatherLoading;
var
  hBar: hXCGUI;
begin
  if XC_GetObjectType(CShapeStatWeather) <> XC_SHAPE_TEXT then
    Exit;
  XShapeText_SetText(CShapeStatWeather, PWideChar(cWeatherLoadingText));
  RefreshStatIpWeatherHoverHint;
  hBar := XC_GetObjectByID(XWidget_GetHWINDOW(CShapeStatWeather), 1001);
  if XC_GetObjectType(hBar) <> XC_ERROR then
  begin
    XEle_AdjustLayout(hBar);
    XEle_Redraw(hBar);
  end;
end;

class procedure TMainWindowStat.SetMainStatWeather(const AInfo: TWeatherInfo);
var
  hBar: hXCGUI;
  displayText, svgPath: string;
  iconCode: Integer;
begin
  if XC_GetObjectType(CShapeStatWeather) <> XC_SHAPE_TEXT then
    Exit;
  FCacheLock.Enter;
  try
    CLastWeatherInfo := AInfo;
  finally
    FCacheLock.Leave;
  end;
  displayText := WeatherFormatDisplay(AInfo);
  XShapeText_SetText(CShapeStatWeather, PWideChar(displayText));
  if XC_GetObjectType(CBtnStatWeather) = XC_BUTTON then
  begin
    iconCode := AInfo.IconCode;
    if iconCode <= 0 then
      iconCode := 999;
    svgPath := WeatherIconSvgPath(iconCode);
    if not FileExists(svgPath) then
      svgPath := WeatherIconSvgPath(999);
    TButtonUI(TButtonUI.FromHandle(CBtnStatWeather)).SetSvgFile(PWideChar(svgPath));
  end;
  RefreshStatIpWeatherHoverHint;
  hBar := XC_GetObjectByID(XWidget_GetHWINDOW(CShapeStatWeather), 1001);
  if XC_GetObjectType(hBar) <> XC_ERROR then
  begin
    XEle_AdjustLayout(hBar);
    XEle_Redraw(hBar);
  end;
end;

class procedure TMainWindowStat.SyncNetTrafficSamplerWithConfig;
var
  dash: string;
begin
  if FNetTrafficThread = nil then
    Exit;
  if TAppConfig.IsShowTrafficMonitor then
    FNetTrafficThread.ResumeSampler
  else
  begin
    FNetTrafficThread.PauseSampler;
    dash := Char($2014);
    CLastStatNetDown := '';
    CLastStatNetUp := '';
    SetMainStatNet(dash, dash);
  end;
end;

class procedure TMainWindowStat.SetMainStatHardware(const ACpuText, AMemText, AGpuText: string);
var
  hEle: hXCGUI;
  cpuPct, memPct, gpuPct: Integer;
begin
  if (ACpuText = CLastCpuUsageText) and (AMemText = CLastMemUsageText) and
    (AGpuText = CLastGpuUsageText) then
    Exit;
  hEle := XC_ERROR;
  cpuPct := ParseHardwarePercent(ACpuText);
  memPct := ParseHardwarePercent(AMemText);
  gpuPct := ParseHardwarePercent(AGpuText);
  FCacheLock.Enter;
  try
    CLastCpuUsageText := ACpuText;
    CLastMemUsageText := AMemText;
    CLastGpuUsageText := AGpuText;
  finally
    FCacheLock.Leave;
  end;
  if XC_GetObjectType(CShapeStatCpu) = XC_SHAPE_TEXT then
  begin
    XShapeText_SetText(CShapeStatCpu, PWideChar(ACpuText));
    hEle := XWidget_GetParent(XWidget_GetParent(CShapeStatCpu));
  end;
  if XC_GetObjectType(CProgStatCpu) = XC_PROGRESSBAR then
  begin
    XProgBar_SetPos(CProgStatCpu, cpuPct);
    XEle_Redraw(CProgStatCpu);
    if XC_GetObjectType(hEle) = XC_ERROR then
      hEle := XWidget_GetParent(XWidget_GetParent(CProgStatCpu));
  end;
  if XC_GetObjectType(CShapeStatMem) = XC_SHAPE_TEXT then
  begin
    XShapeText_SetText(CShapeStatMem, PWideChar(AMemText));
    if XC_GetObjectType(hEle) = XC_ERROR then
      hEle := XWidget_GetParent(XWidget_GetParent(CShapeStatMem));
  end;
  if XC_GetObjectType(CProgStatRam) = XC_PROGRESSBAR then
  begin
    XProgBar_SetPos(CProgStatRam, memPct);
    XEle_Redraw(CProgStatRam);
    if XC_GetObjectType(hEle) = XC_ERROR then
      hEle := XWidget_GetParent(XWidget_GetParent(CProgStatRam));
  end;
  if XC_GetObjectType(CShapeStatGpu) = XC_SHAPE_TEXT then
  begin
    XShapeText_SetText(CShapeStatGpu, PWideChar(AGpuText));
    if XC_GetObjectType(hEle) = XC_ERROR then
      hEle := XWidget_GetParent(XWidget_GetParent(CShapeStatGpu));
  end;
  if XC_GetObjectType(CProgStatGpu) = XC_PROGRESSBAR then
  begin
    XProgBar_SetPos(CProgStatGpu, gpuPct);
    XEle_Redraw(CProgStatGpu);
    if XC_GetObjectType(hEle) = XC_ERROR then
      hEle := XWidget_GetParent(XWidget_GetParent(CProgStatGpu));
  end;
  RefreshStatCpuHoverHint;
  RefreshStatGpuHoverHint;
  if XC_GetObjectType(hEle) <> XC_ERROR then
  begin
    XEle_AdjustLayout(hEle);
    XEle_Redraw(hEle);
  end;
end;

initialization
  TMainWindowStat.FCacheLock := TCriticalSection.Create;

finalization
  FreeAndNil(TMainWindowStat.FCacheLock);

end.
