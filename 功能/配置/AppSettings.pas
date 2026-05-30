unit AppSettings;

interface

uses
  SysUtils;

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
    class function GeneralSettingsEqual(const A, B: TAppGeneralSettings): Boolean;
    class procedure SyncRunWithWindowsRegistry(const AEnabled: Boolean);
    class function QueryRunWithWindowsRegistry: Boolean;
    { XInitXCGUI(True)=D2D；配置为 GDI 或 D2D 初始化失败时 XInitXCGUI(False)=GDI }
    class function InitXCGUI: Boolean;
    class procedure ApplyPaintFrequency;
  end;

implementation

uses
  Windows, Registry, XCGUI, AppConfig;

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

class function TAppSettings.GeneralSettingsEqual(const A, B: TAppGeneralSettings): Boolean;
begin
  Result := (A.RunWithWindows = B.RunWithWindows)
    and (A.MinimizeToTray = B.MinimizeToTray)
    and (A.RenderModeD2D = B.RenderModeD2D)
    and (A.PaintFrequencyMs = B.PaintFrequencyMs);
end;

class function TAppSettings.QueryRunWithWindowsRegistry: Boolean;
var
  reg: TRegistry;
begin
  Result := False;
  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly(cRegRunKey) then
      Result := reg.ValueExists(cRunValueName);
  finally
    reg.Free;
  end;
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
