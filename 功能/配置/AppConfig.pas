unit AppConfig;

interface

uses
  SysUtils;

const
  cIniFileName = 'QDesktop.ini';
  cDefaultSQLFileName = 'games.db';
  cDefaultIconCacheDirName = 'IconCache';
  /// <summary>Shell 通用「默认文档」类型图标落盘/内存缓存统一文件名。</summary>
  cDefaultFileTypeIconFileName = 'default.png';
  cRenderModeGDI = 'GDI';
  cRenderModeD2D = 'D2D';
  /// <summary>UI 绘制间隔（毫秒），传给 XC_SetPaintFrequency</summary>
  cDefaultPaintFrequencyMs = 30;
  cMaxPaintFrequencyMs = 120;
  cDefaultCityCoordsUrl = 'https://raw.githubusercontent.com/zhongzx8080/CityCoordinate/refs/heads/master/city.json';
  cProxyModeOff = 0;
  cProxyModeHttp = 1;
  cProxyModeHttps = 2;
  cProxyModeSocks5 = 3;
  cDefaultUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36';
  /// <summary>主列表图标项宽度（像素），全部分组共用。</summary>
  cListItemWidthMin = 60;
  cListItemWidthMax = 256;
  cDefaultListItemWidth = 130;
  cListColumnSpaceMin = 0;
  cListColumnSpaceMax = 24;
  cDefaultListColumnSpace = 8;
  cListRowSpaceMin = 0;
  cListRowSpaceMax = 24;
  cDefaultListRowSpace = 8;
  cListItemCornerRadiusMin = 0;
  cListItemCornerRadiusMax = 12;
  cDefaultListItemCornerRadius = 6;
  cListScrollBarSizeMin = 4;
  cListScrollBarSizeMax = 14;
  cDefaultListScrollBarSize = 7;
  cListScrollSliderMinLenMin = 24;
  cListScrollSliderMinLenMax = 64;
  cDefaultListScrollSliderMinLen = 36;
  cListScrollThumbRadiusMin = 0;
  cListScrollThumbRadiusMax = 8;
  cDefaultListScrollThumbRadius = 3;

type
  TAppConfig = class
  private
    class var
      FSQLFileName: string;
      FIconCacheDirName: string;
      FShowCommonTools: Integer;
      FShowTrafficMonitor: Integer;
      FMainWindowLeft: Integer;
      FMainWindowTop: Integer;
      FMainWindowWidth: Integer;
      FMainWindowHeight: Integer;
      FMainWindowMaximized: Integer;
      FRunWithWindows: Integer;
      FMinimizeToTray: Integer;
      FRenderMode: string;
      FPaintFrequencyMs: Integer;
      FCityCoordsUrl: string;
      FCityCoordsUpdateEnabled: Integer;
      FProxyMode: Integer;
      FProxyUrl: string;
      FUserAgent: string;
      FHostsResolve: string;
      FListItemWidth: Integer;
      FListColumnSpace: Integer;
      FListRowSpace: Integer;
      FListItemCornerRadius: Integer;
      FListScrollBarSize: Integer;
      FListScrollSliderMinLen: Integer;
      FListScrollThumbRadius: Integer;
    class procedure ApplyDefaults;
    class function ClampPaintFrequencyMs(const AValue: Integer): Integer;
    class function ClampInt(const AValue, AMin, AMax: Integer): Integer;
    class function NormalizeHostsResolveText(const AValue: string): string;
    class function EncodeHostsResolveForIni(const AValue: string): string;
    class function DecodeHostsResolveFromIni(const AValue: string): string;
  public
    class function ClampListItemWidth(const AValue: Integer): Integer;
    class function ClampListColumnSpace(const AValue: Integer): Integer;
    class function ClampListRowSpace(const AValue: Integer): Integer;
    class function ClampListItemCornerRadius(const AValue: Integer): Integer;
    class function ClampListScrollBarSize(const AValue: Integer): Integer;
    class function ClampListScrollSliderMinLen(const AValue: Integer): Integer;
    class function ClampListScrollThumbRadius(const AValue: Integer): Integer;
    class function ClampProxyMode(const AValue: Integer): Integer;
    class function DataDirectory: string;
    class function ConfigFilePath: string;
    class procedure Load;
    class procedure Save;
    class function DatabaseFilePath: string;
    class function IconCacheDirectory: string;
    class function BuildIconCachePathFromFileName(const AFileName: string): string;
    { 分组项图标：入库存储可为完整路径、相对路径或仅文件名，此处解析为可加载的现有文件 }
    class function ResolveGroupIconFile(const AIconFile: string): string;
    class function IsShowCommonTools: Boolean;
    class function IsShowTrafficMonitor: Boolean;
    class procedure SetShowCommonTools(AEnabled: Boolean);
    class procedure SetShowTrafficMonitor(AEnabled: Boolean);
    class function TryGetMainWindowBounds(out ALeft, ATop, AWidth, AHeight: Integer): Boolean;
    class procedure SetMainWindowBounds(ALeft, ATop, AWidth, AHeight: Integer);
    class function IsMainWindowMaximized: Boolean;
    class procedure SetMainWindowMaximized(AValue: Boolean);
    class function IsRunWithWindows: Boolean;
    class function IsMinimizeToTray: Boolean;
    class procedure SetRunWithWindows(AEnabled: Boolean);
    class procedure SetMinimizeToTray(AEnabled: Boolean);
    class function GetRenderMode: string;
    class procedure SetRenderMode(const AValue: string);
    class function IsRenderModeD2D: Boolean;
    class function GetPaintFrequencyMs: Integer;
    class procedure SetPaintFrequencyMs(const AValue: Integer);
    class function GetCityCoordsUrl: string;
    class procedure SetCityCoordsUrl(const AValue: string);
    class function IsCityCoordsUpdateEnabled: Boolean;
    class procedure SetCityCoordsUpdateEnabled(AEnabled: Boolean);
    class function GetProxyMode: Integer;
    class procedure SetProxyMode(const AValue: Integer);
    class function GetProxyUrl: string;
    class procedure SetProxyUrl(const AValue: string);
    class function BuildCurlProxyUrl: AnsiString;
    class function GetUserAgent: string;
    class procedure SetUserAgent(const AValue: string);
    class function GetHostsResolve: string;
    class procedure SetHostsResolve(const AValue: string);
    class function GetListItemWidth: Integer;
    class procedure SetListItemWidth(const AValue: Integer);
    class function GetListColumnSpace: Integer;
    class procedure SetListColumnSpace(const AValue: Integer);
    class function GetListRowSpace: Integer;
    class procedure SetListRowSpace(const AValue: Integer);
    class function GetListItemCornerRadius: Integer;
    class procedure SetListItemCornerRadius(const AValue: Integer);
    class function GetListScrollBarSize: Integer;
    class procedure SetListScrollBarSize(const AValue: Integer);
    class function GetListScrollSliderMinLen: Integer;
    class procedure SetListScrollSliderMinLen(const AValue: Integer);
    class function GetListScrollThumbRadius: Integer;
    class procedure SetListScrollThumbRadius(const AValue: Integer);
    class procedure ApplyListViewLayoutDefaults;
  end;

type
  TAppGeneralSettings = record
    RunWithWindows: Boolean;
    MinimizeToTray: Boolean;
    RenderModeD2D: Boolean;
    PaintFrequencyMs: Integer;
  end;

  TAppSettings = class
  public
    class procedure ApplyDefaults(out ASettings: TAppGeneralSettings);
    class procedure Load(out ASettings: TAppGeneralSettings);
    class procedure Save(const ASettings: TAppGeneralSettings);
    class procedure SyncRunWithWindowsRegistry(const AEnabled: Boolean);
    class function InitXCGUI: Boolean;
    class procedure ApplyPaintFrequency;
  end;


implementation


uses
  IniFiles, Windows, Registry, XCGUI, AppPaths;

class function TAppConfig.ClampInt(const AValue, AMin, AMax: Integer): Integer;
begin
  if AValue < AMin then
    Result := AMin
  else if AValue > AMax then
    Result := AMax
  else
    Result := AValue;
end;







class procedure TAppConfig.ApplyDefaults;
begin
  FSQLFileName := cDefaultSQLFileName;
  FIconCacheDirName := cDefaultIconCacheDirName;
  FShowCommonTools := 0;
  FShowTrafficMonitor := 1;
  FMainWindowLeft := -1;
  FMainWindowTop := -1;
  FMainWindowWidth := 0;
  FMainWindowHeight := 0;
  FMainWindowMaximized := 0;
  FRunWithWindows := 0;
  FMinimizeToTray := 0;
  FRenderMode := cRenderModeD2D;
  FPaintFrequencyMs := cDefaultPaintFrequencyMs;
  FCityCoordsUrl := cDefaultCityCoordsUrl;
  FCityCoordsUpdateEnabled := 1;
  FProxyMode := cProxyModeOff;
  FProxyUrl := '';
  FUserAgent := cDefaultUserAgent;
  FHostsResolve := '';
  FListItemWidth := cDefaultListItemWidth;
  ApplyListViewLayoutDefaults;
end;

class procedure TAppConfig.ApplyListViewLayoutDefaults;
begin
  FListColumnSpace := cDefaultListColumnSpace;
  FListRowSpace := cDefaultListRowSpace;
  FListItemCornerRadius := cDefaultListItemCornerRadius;
  FListScrollBarSize := cDefaultListScrollBarSize;
  FListScrollSliderMinLen := cDefaultListScrollSliderMinLen;
  FListScrollThumbRadius := cDefaultListScrollThumbRadius;
end;

class function TAppConfig.ClampListColumnSpace(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cListColumnSpaceMin, cListColumnSpaceMax);
end;

class function TAppConfig.ClampListRowSpace(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cListRowSpaceMin, cListRowSpaceMax);
end;

class function TAppConfig.ClampListItemCornerRadius(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cListItemCornerRadiusMin, cListItemCornerRadiusMax);
end;

class function TAppConfig.ClampListScrollBarSize(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cListScrollBarSizeMin, cListScrollBarSizeMax);
end;

class function TAppConfig.ClampListScrollSliderMinLen(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cListScrollSliderMinLenMin, cListScrollSliderMinLenMax);
end;

class function TAppConfig.ClampListScrollThumbRadius(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cListScrollThumbRadiusMin, cListScrollThumbRadiusMax);
end;

class function TAppConfig.ClampProxyMode(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cProxyModeOff, cProxyModeSocks5);
end;

class function TAppConfig.ClampListItemWidth(const AValue: Integer): Integer;
begin
  Result := ClampInt(AValue, cListItemWidthMin, cListItemWidthMax);
end;

class function TAppConfig.ClampPaintFrequencyMs(const AValue: Integer): Integer;
begin
  if AValue < 0 then
    Result := 0
  else if AValue > cMaxPaintFrequencyMs then
    Result := cMaxPaintFrequencyMs
  else
    Result := AValue;
end;

class function TAppConfig.DataDirectory: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'Data';
end;

class function TAppConfig.ConfigFilePath: string;
begin
  Result := IncludeTrailingPathDelimiter(DataDirectory) + cIniFileName;
end;

class procedure TAppConfig.Load;
var
  ini: TIniFile;
begin
  ForceDirectories(DataDirectory);
  if not FileExists(ConfigFilePath) then
  begin
    ApplyDefaults;
    Save;
    Exit;
  end;
  ini := TIniFile.Create(ConfigFilePath);
  try
    FSQLFileName := ini.ReadString('Database', 'SQLFileName', '');
    if Trim(FSQLFileName) = '' then
      FSQLFileName := ini.ReadString('Database', 'FileName', cDefaultSQLFileName);
    FIconCacheDirName := ini.ReadString('Paths', 'IconCacheDir', cDefaultIconCacheDirName);
    FShowCommonTools := ini.ReadInteger('Features', 'ShowCommonTools', 0);
    FShowTrafficMonitor := ini.ReadInteger('Features', 'ShowTrafficMonitor', 1);
    FMainWindowLeft := ini.ReadInteger('Window', 'MainLeft', -1);
    FMainWindowTop := ini.ReadInteger('Window', 'MainTop', -1);
    FMainWindowWidth := ini.ReadInteger('Window', 'MainWidth', 0);
    FMainWindowHeight := ini.ReadInteger('Window', 'MainHeight', 0);
    FMainWindowMaximized := ini.ReadInteger('Window', 'MainMaximized', 0);
    FRunWithWindows := ini.ReadInteger('General', 'RunWithWindows', 0);
    FMinimizeToTray := ini.ReadInteger('General', 'MinimizeToTray', 0);
    FRenderMode := ini.ReadString('General', 'RenderMode', cRenderModeD2D);
    FPaintFrequencyMs := ini.ReadInteger('General', 'PaintFrequency', cDefaultPaintFrequencyMs);
    FCityCoordsUrl := ini.ReadString('Data', 'CityCoordsUrl', cDefaultCityCoordsUrl);
    FCityCoordsUpdateEnabled := ini.ReadInteger('Data', 'CityCoordsUpdate', 1);
    FProxyMode := ini.ReadInteger('Proxy', 'Mode', -1);
    if FProxyMode < 0 then
    begin
      if ini.ReadInteger('Proxy', 'Enabled', 0) <> 0 then
        FProxyMode := cProxyModeHttp
      else
        FProxyMode := cProxyModeOff;
    end;
    FProxyUrl := ini.ReadString('Proxy', 'Url', '');
    FUserAgent := ini.ReadString('Network', 'UserAgent', cDefaultUserAgent);
    FHostsResolve := DecodeHostsResolveFromIni(ini.ReadString('Network', 'HostsResolve', ''));
    FListItemWidth := ini.ReadInteger('UI', 'ListItemWidth', cDefaultListItemWidth);
    FListColumnSpace := ini.ReadInteger('UI', 'ListColumnSpace', cDefaultListColumnSpace);
    FListRowSpace := ini.ReadInteger('UI', 'ListRowSpace', cDefaultListRowSpace);
    FListItemCornerRadius := ini.ReadInteger('UI', 'ListItemCornerRadius', cDefaultListItemCornerRadius);
    FListScrollBarSize := ini.ReadInteger('UI', 'ListScrollBarSize', cDefaultListScrollBarSize);
    FListScrollSliderMinLen := ini.ReadInteger('UI', 'ListScrollSliderMinLen', cDefaultListScrollSliderMinLen);
    FListScrollThumbRadius := ini.ReadInteger('UI', 'ListScrollThumbRadius', cDefaultListScrollThumbRadius);
  finally
    ini.Free;
  end;
  if Trim(FSQLFileName) = '' then
    FSQLFileName := cDefaultSQLFileName;
  if Trim(FIconCacheDirName) = '' then
    FIconCacheDirName := cDefaultIconCacheDirName;
  FShowCommonTools := Ord(FShowCommonTools <> 0);
  FShowTrafficMonitor := Ord(FShowTrafficMonitor <> 0);
  FRunWithWindows := Ord(FRunWithWindows <> 0);
  FMinimizeToTray := Ord(FMinimizeToTray <> 0);
  if not SameText(FRenderMode, cRenderModeGDI) then
    FRenderMode := cRenderModeD2D
  else
    FRenderMode := cRenderModeGDI;
  FPaintFrequencyMs := ClampPaintFrequencyMs(FPaintFrequencyMs);
  FListItemWidth := ClampListItemWidth(FListItemWidth);
  FListColumnSpace := ClampListColumnSpace(FListColumnSpace);
  FListRowSpace := ClampListRowSpace(FListRowSpace);
  FListItemCornerRadius := ClampListItemCornerRadius(FListItemCornerRadius);
  FListScrollBarSize := ClampListScrollBarSize(FListScrollBarSize);
  FListScrollSliderMinLen := ClampListScrollSliderMinLen(FListScrollSliderMinLen);
  FListScrollThumbRadius := ClampListScrollThumbRadius(FListScrollThumbRadius);
  if Trim(FCityCoordsUrl) = '' then
    FCityCoordsUrl := cDefaultCityCoordsUrl;
  FCityCoordsUpdateEnabled := Ord(FCityCoordsUpdateEnabled <> 0);
  FProxyMode := ClampProxyMode(FProxyMode);
  FMainWindowMaximized := Ord(FMainWindowMaximized <> 0);
  if Trim(FUserAgent) = '' then
    FUserAgent := cDefaultUserAgent;
  if FMainWindowWidth < 0 then
    FMainWindowWidth := 0;
  if FMainWindowHeight < 0 then
    FMainWindowHeight := 0;
end;

class procedure TAppConfig.Save;
var
  ini: TIniFile;
begin
  ForceDirectories(DataDirectory);
  ini := TIniFile.Create(ConfigFilePath);
  try
    ini.WriteString('Database', 'SQLFileName', FSQLFileName);
    ini.WriteString('Paths', 'IconCacheDir', FIconCacheDirName);
    ini.WriteInteger('Features', 'ShowCommonTools', FShowCommonTools);
    ini.WriteInteger('Features', 'ShowTrafficMonitor', FShowTrafficMonitor);
    ini.WriteInteger('Window', 'MainLeft', FMainWindowLeft);
    ini.WriteInteger('Window', 'MainTop', FMainWindowTop);
    ini.WriteInteger('Window', 'MainWidth', FMainWindowWidth);
    ini.WriteInteger('Window', 'MainHeight', FMainWindowHeight);
    ini.WriteInteger('Window', 'MainMaximized', FMainWindowMaximized);
    ini.WriteInteger('General', 'RunWithWindows', FRunWithWindows);
    ini.WriteInteger('General', 'MinimizeToTray', FMinimizeToTray);
    ini.WriteString('General', 'RenderMode', FRenderMode);
    ini.WriteInteger('General', 'PaintFrequency', FPaintFrequencyMs);
    ini.WriteString('Data', 'CityCoordsUrl', FCityCoordsUrl);
    ini.WriteInteger('Data', 'CityCoordsUpdate', FCityCoordsUpdateEnabled);
    ini.WriteInteger('Proxy', 'Mode', FProxyMode);
    ini.WriteString('Proxy', 'Url', FProxyUrl);
    ini.WriteString('Network', 'UserAgent', FUserAgent);
    ini.WriteString('Network', 'HostsResolve', EncodeHostsResolveForIni(FHostsResolve));
    ini.WriteInteger('UI', 'ListItemWidth', FListItemWidth);
    ini.WriteInteger('UI', 'ListColumnSpace', FListColumnSpace);
    ini.WriteInteger('UI', 'ListRowSpace', FListRowSpace);
    ini.WriteInteger('UI', 'ListItemCornerRadius', FListItemCornerRadius);
    ini.WriteInteger('UI', 'ListScrollBarSize', FListScrollBarSize);
    ini.WriteInteger('UI', 'ListScrollSliderMinLen', FListScrollSliderMinLen);
    ini.WriteInteger('UI', 'ListScrollThumbRadius', FListScrollThumbRadius);
  finally
    ini.Free;
  end;
end;

class function TAppConfig.DatabaseFilePath: string;
var
  rel, dir: string;
begin
  rel := Trim(FSQLFileName);
  if rel = '' then
    rel := cDefaultSQLFileName;
  rel := StringReplace(rel, '/', '\', [rfReplaceAll]);
  if (Length(rel) > 0) and (rel[1] = '\') then
    Delete(rel, 1, 1);
  Result := IncludeTrailingPathDelimiter(DataDirectory) + rel;
  dir := ExtractFilePath(Result);
  if dir <> '' then
    ForceDirectories(ExcludeTrailingPathDelimiter(dir));
end;

class function TAppConfig.IconCacheDirectory: string;
var
  rel: string;
begin
  rel := Trim(FIconCacheDirName);
  if rel = '' then
    rel := cDefaultIconCacheDirName;
  rel := StringReplace(rel, '/', '\', [rfReplaceAll]);
  if (Length(rel) > 0) and (rel[1] = '\') then
    Delete(rel, 1, 1);
  Result := IncludeTrailingPathDelimiter(DataDirectory) + rel;
  ForceDirectories(Result);
end;

class function TAppConfig.BuildIconCachePathFromFileName(const AFileName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IconCacheDirectory) + AFileName;
end;

class function TAppConfig.ResolveGroupIconFile(const AIconFile: string): string;
var
  s, nameOnly: string;
begin
  s := Trim(AIconFile);
  if s = '' then
  begin
    s := 'Resource\category\default.svg';
    if FileExists(s) then
      Result := s
    else
      Result := 'default.svg';
    Exit;
  end;
  if FileExists(s) then
  begin
    Result := s;
    Exit;
  end;
  s := ExpandFileName(Trim(AIconFile));
  if FileExists(s) then
  begin
    Result := s;
    Exit;
  end;
  nameOnly := ExtractFileName(Trim(AIconFile));
  Result := IncludeTrailingPathDelimiter(AppExeDirectory) + 'Resource\CategoryIcons\' + nameOnly;
  if FileExists(Result) then
    Exit;
  Result := 'Resource\category\default.svg';
  if not FileExists(Result) and (nameOnly <> '') then
    Result := nameOnly;
end;

class function TAppConfig.IsShowCommonTools: Boolean;
begin
  Result := FShowCommonTools <> 0;
end;

class function TAppConfig.IsShowTrafficMonitor: Boolean;
begin
  Result := FShowTrafficMonitor <> 0;
end;

class procedure TAppConfig.SetShowCommonTools(AEnabled: Boolean);
begin
  FShowCommonTools := Ord(AEnabled);
end;

class procedure TAppConfig.SetShowTrafficMonitor(AEnabled: Boolean);
begin
  FShowTrafficMonitor := Ord(AEnabled);
end;

class function TAppConfig.TryGetMainWindowBounds(out ALeft, ATop, AWidth, AHeight: Integer): Boolean;
begin
  ALeft := FMainWindowLeft;
  ATop := FMainWindowTop;
  AWidth := FMainWindowWidth;
  AHeight := FMainWindowHeight;
  Result := (AWidth > 0) and (AHeight > 0);
end;

class procedure TAppConfig.SetMainWindowBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  FMainWindowLeft := ALeft;
  FMainWindowTop := ATop;
  FMainWindowWidth := AWidth;
  FMainWindowHeight := AHeight;
end;

class function TAppConfig.IsMainWindowMaximized: Boolean;
begin
  Result := FMainWindowMaximized <> 0;
end;

class procedure TAppConfig.SetMainWindowMaximized(AValue: Boolean);
begin
  FMainWindowMaximized := Ord(AValue);
end;

class function TAppConfig.IsRunWithWindows: Boolean;
begin
  Result := FRunWithWindows <> 0;
end;

class function TAppConfig.IsMinimizeToTray: Boolean;
begin
  Result := FMinimizeToTray <> 0;
end;

class procedure TAppConfig.SetRunWithWindows(AEnabled: Boolean);
begin
  FRunWithWindows := Ord(AEnabled);
end;

class procedure TAppConfig.SetMinimizeToTray(AEnabled: Boolean);
begin
  FMinimizeToTray := Ord(AEnabled);
end;

class function TAppConfig.GetRenderMode: string;
begin
  Result := FRenderMode;
end;

class procedure TAppConfig.SetRenderMode(const AValue: string);
begin
  if SameText(Trim(AValue), cRenderModeGDI) then
    FRenderMode := cRenderModeGDI
  else
    FRenderMode := cRenderModeD2D;
end;

class function TAppConfig.IsRenderModeD2D: Boolean;
begin
  Result := SameText(FRenderMode, cRenderModeD2D);
end;

class function TAppConfig.GetPaintFrequencyMs: Integer;
begin
  Result := ClampPaintFrequencyMs(FPaintFrequencyMs);
end;

class procedure TAppConfig.SetPaintFrequencyMs(const AValue: Integer);
begin
  FPaintFrequencyMs := ClampPaintFrequencyMs(AValue);
end;

class function TAppConfig.GetCityCoordsUrl: string;
begin
  Result := FCityCoordsUrl;
end;

class procedure TAppConfig.SetCityCoordsUrl(const AValue: string);
begin
  if Trim(AValue) = '' then
    FCityCoordsUrl := cDefaultCityCoordsUrl
  else
    FCityCoordsUrl := AValue;
end;

class function TAppConfig.IsCityCoordsUpdateEnabled: Boolean;
begin
  Result := FCityCoordsUpdateEnabled <> 0;
end;

class procedure TAppConfig.SetCityCoordsUpdateEnabled(AEnabled: Boolean);
begin
  FCityCoordsUpdateEnabled := Ord(AEnabled);
end;

class function TAppConfig.GetProxyMode: Integer;
begin
  Result := ClampProxyMode(FProxyMode);
end;

class procedure TAppConfig.SetProxyMode(const AValue: Integer);
begin
  FProxyMode := ClampProxyMode(AValue);
end;

class function TAppConfig.GetProxyUrl: string;
begin
  Result := FProxyUrl;
end;

class procedure TAppConfig.SetProxyUrl(const AValue: string);
begin
  FProxyUrl := Trim(AValue);
end;

class function TAppConfig.BuildCurlProxyUrl: AnsiString;
var
  addr: string;
begin
  Result := '';
  if FProxyMode = cProxyModeOff then
    Exit;
  addr := Trim(FProxyUrl);
  if addr = '' then
    Exit;
  if Pos('://', LowerCase(addr)) > 0 then
    Exit(AnsiString(UTF8Encode(addr)));
  case FProxyMode of
    cProxyModeHttp:
      Result := AnsiString(UTF8Encode('http://' + addr));
    cProxyModeHttps:
      Result := AnsiString(UTF8Encode('https://' + addr));
    cProxyModeSocks5:
      Result := AnsiString(UTF8Encode('socks5://' + addr));
  end;
end;

class function TAppConfig.GetUserAgent: string;
begin
  Result := FUserAgent;
  if Trim(Result) = '' then
    Result := cDefaultUserAgent;
end;

class procedure TAppConfig.SetUserAgent(const AValue: string);
begin
  if Trim(AValue) = '' then
    FUserAgent := cDefaultUserAgent
  else
    FUserAgent := AValue;
end;

class function TAppConfig.NormalizeHostsResolveText(const AValue: string): string;
begin
  Result := StringReplace(AValue, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, sLineBreak, [rfReplaceAll]);
end;

class function TAppConfig.EncodeHostsResolveForIni(const AValue: string): string;
begin
  Result := StringReplace(NormalizeHostsResolveText(AValue), sLineBreak, '|', [rfReplaceAll]);
end;

class function TAppConfig.DecodeHostsResolveFromIni(const AValue: string): string;
begin
  Result := StringReplace(AValue, '|', sLineBreak, [rfReplaceAll]);
end;

class function TAppConfig.GetHostsResolve: string;
begin
  Result := FHostsResolve;
end;

class procedure TAppConfig.SetHostsResolve(const AValue: string);
begin
  FHostsResolve := NormalizeHostsResolveText(Trim(AValue));
end;

class function TAppConfig.GetListItemWidth: Integer;
begin
  Result := ClampListItemWidth(FListItemWidth);
end;

class procedure TAppConfig.SetListItemWidth(const AValue: Integer);
begin
  FListItemWidth := ClampListItemWidth(AValue);
end;

class function TAppConfig.GetListColumnSpace: Integer;
begin
  Result := ClampListColumnSpace(FListColumnSpace);
end;

class procedure TAppConfig.SetListColumnSpace(const AValue: Integer);
begin
  FListColumnSpace := ClampListColumnSpace(AValue);
end;

class function TAppConfig.GetListRowSpace: Integer;
begin
  Result := ClampListRowSpace(FListRowSpace);
end;

class procedure TAppConfig.SetListRowSpace(const AValue: Integer);
begin
  FListRowSpace := ClampListRowSpace(AValue);
end;

class function TAppConfig.GetListItemCornerRadius: Integer;
begin
  Result := ClampListItemCornerRadius(FListItemCornerRadius);
end;

class procedure TAppConfig.SetListItemCornerRadius(const AValue: Integer);
begin
  FListItemCornerRadius := ClampListItemCornerRadius(AValue);
end;

class function TAppConfig.GetListScrollBarSize: Integer;
begin
  Result := ClampListScrollBarSize(FListScrollBarSize);
end;

class procedure TAppConfig.SetListScrollBarSize(const AValue: Integer);
begin
  FListScrollBarSize := ClampListScrollBarSize(AValue);
end;

class function TAppConfig.GetListScrollSliderMinLen: Integer;
begin
  Result := ClampListScrollSliderMinLen(FListScrollSliderMinLen);
end;

class procedure TAppConfig.SetListScrollSliderMinLen(const AValue: Integer);
begin
  FListScrollSliderMinLen := ClampListScrollSliderMinLen(AValue);
end;

class function TAppConfig.GetListScrollThumbRadius: Integer;
begin
  Result := ClampListScrollThumbRadius(FListScrollThumbRadius);
end;

class procedure TAppConfig.SetListScrollThumbRadius(const AValue: Integer);
begin
  FListScrollThumbRadius := ClampListScrollThumbRadius(AValue);
end;


const
  cRunValueName = 'QDesktop';
  cRegRunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';

class procedure TAppSettings.ApplyDefaults(out ASettings: TAppGeneralSettings);
begin
  ASettings.RunWithWindows := False;
  ASettings.MinimizeToTray := False;
  ASettings.RenderModeD2D := True;
  ASettings.PaintFrequencyMs := cDefaultPaintFrequencyMs;
end;

class procedure TAppSettings.Load(out ASettings: TAppGeneralSettings);
begin
  ASettings.RunWithWindows := TAppConfig.IsRunWithWindows;
  ASettings.MinimizeToTray := TAppConfig.IsMinimizeToTray;
  ASettings.RenderModeD2D := TAppConfig.IsRenderModeD2D;
  ASettings.PaintFrequencyMs := TAppConfig.GetPaintFrequencyMs;
end;

class procedure TAppSettings.Save(const ASettings: TAppGeneralSettings);
begin
  TAppConfig.SetRunWithWindows(ASettings.RunWithWindows);
  TAppConfig.SetMinimizeToTray(ASettings.MinimizeToTray);
  if ASettings.RenderModeD2D then
    TAppConfig.SetRenderMode(cRenderModeD2D)
  else
    TAppConfig.SetRenderMode(cRenderModeGDI);
  TAppConfig.SetPaintFrequencyMs(ASettings.PaintFrequencyMs);
  TAppConfig.Save;
  SyncRunWithWindowsRegistry(ASettings.RunWithWindows);
  ApplyPaintFrequency;
end;

class function TAppSettings.InitXCGUI: Boolean;
begin
  if TAppConfig.IsRenderModeD2D then
  begin
    Result := XInitXCGUI(True);
    if Result then
      Exit;
    TAppConfig.SetRenderMode(cRenderModeGDI);
    TAppConfig.Save;
    Result := XInitXCGUI(False);
  end
  else
    Result := XInitXCGUI(False);
end;

class procedure TAppSettings.ApplyPaintFrequency;
begin
  XC_SetPaintFrequency(TAppConfig.GetPaintFrequencyMs);
end;

class procedure TAppSettings.SyncRunWithWindowsRegistry(const AEnabled: Boolean);
var
  reg: TRegistry;
  exePath, cmdLine: string;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if not reg.OpenKey(cRegRunKey, False) then
      Exit;
    if AEnabled then
    begin
      exePath := ParamStr(0);
      if exePath = '' then
        Exit;
      cmdLine := '"' + exePath + '"';
      reg.WriteString(cRunValueName, cmdLine);
    end
    else if reg.ValueExists(cRunValueName) then
      reg.DeleteValue(cRunValueName);
  finally
    reg.Free;
  end;
end;

end.