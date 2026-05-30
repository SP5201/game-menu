unit AppConfig;

interface

uses
  SysUtils;

const
  cIniFileName = 'QDesktop.ini';
  cDefaultSQLFileName = 'games.db';
  cDefaultIconCacheDirName = 'IconCache';
  cDefaultFileTypeIconDirName = 'FileTypeIcons';
  /// <summary>Shell 通用「默认文档」类型图标落盘/内存缓存统一文件名。</summary>
  cDefaultFileTypeIconFileName = 'default.png';
  cRenderModeGDI = 'GDI';
  cRenderModeD2D = 'D2D';
  /// <summary>UI 绘制间隔（毫秒），传给 XC_SetPaintFrequency</summary>
  cDefaultPaintFrequencyMs = 30;
  cMaxPaintFrequencyMs = 120;
  cDefaultCityCoordsUrl = 'https://raw.githubusercontent.com/zhongzx8080/CityCoordinate/refs/heads/master/city.json';

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
    class procedure ApplyDefaults;
    class function ClampPaintFrequencyMs(const AValue: Integer): Integer;
  public
    class function DataDirectory: string;
    class function ConfigFilePath: string;
    class procedure Load;
    class procedure Save;
    class function DatabaseFilePath: string;
    class function IconCacheDirectory: string;
    class function BuildIconCachePathFromFileName(const AFileName: string): string;
    class function FileTypeIconDirectory: string;
    class function BuildFileTypeIconPathFromFileName(const AFileName: string): string;
    { 分组项图标：入库存储可为完整路径、相对路径或仅文件名，此处解析为可加载的现有文件 }
    class function ResolveGroupIconFile(const AIconFile: string): string;
    class function GetSQLFileName: string;
    class procedure SetSQLFileName(const AValue: string);
    class function GetIconCacheDirName: string;
    class procedure SetIconCacheDirName(const AValue: string);
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
  end;

implementation

uses
  IniFiles;

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
  if Trim(FCityCoordsUrl) = '' then
    FCityCoordsUrl := cDefaultCityCoordsUrl;
  FCityCoordsUpdateEnabled := Ord(FCityCoordsUpdateEnabled <> 0);
  FMainWindowMaximized := Ord(FMainWindowMaximized <> 0);
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

class function TAppConfig.FileTypeIconDirectory: string;
begin
  Result := IncludeTrailingPathDelimiter(DataDirectory) + cDefaultFileTypeIconDirName;
  ForceDirectories(Result);
end;

class function TAppConfig.BuildFileTypeIconPathFromFileName(const AFileName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FileTypeIconDirectory) + AFileName;
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
  Result := ExpandFileName('Data\CategoryIcons\' + nameOnly);
  if FileExists(Result) then
    Exit;
  Result := ExpandFileName('Debug\Data\CategoryIcons\' + nameOnly);
  if FileExists(Result) then
    Exit;
  Result := 'Resource\category\default.svg';
  if not FileExists(Result) and (nameOnly <> '') then
    Result := nameOnly;
end;

class function TAppConfig.GetSQLFileName: string;
begin
  Result := FSQLFileName;
end;

class procedure TAppConfig.SetSQLFileName(const AValue: string);
begin
  FSQLFileName := AValue;
end;

class function TAppConfig.GetIconCacheDirName: string;
begin
  Result := FIconCacheDirName;
end;

class procedure TAppConfig.SetIconCacheDirName(const AValue: string);
begin
  FIconCacheDirName := AValue;
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

end.
