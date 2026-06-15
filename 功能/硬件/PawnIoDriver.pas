unit PawnIoDriver;

{
  PawnIO 内核驱动：经 INF（Root\PawnIO）安装，不用 CreateService 直挂 .sys（无设备节点、易僵死）。
  不调用 PawnIOSetup 等安装 exe；包文件暂存到 %LOCALAPPDATA%\QDesktop\Bin\。
  若系统已存在官方 PawnIO（Program Files），仅打开设备。
  退出不 stop/delete（NOT_STOPPABLE，强删会僵死）。
}

interface

uses
  Windows;

const
  cPawnIoSysFileName = 'PawnIO.sys';
  cPawnIoInfFileName = 'PawnIO.inf';
  cPawnIoCatFileName = 'PawnIO.cat';
  cPawnIoServiceName = 'PawnIO';
  cPawnIoDevicePath = '\\?\GLOBALROOT\Device\PawnIO';
  cPawnIoDevicePathAlt = '\\.\PawnIO';
  cPawnIoHardwareId = 'Root\PawnIO';

function PawnIoDriverTryOpenDevice(out ADevicePath: string): THandle;
function PawnIoDriverEnsureRunning: Boolean;
function PawnIoDriverInstalledByUs: Boolean;
procedure PawnIoDriverUnloadIfOwned;
function PawnIoDriverLastError: DWORD;
function PawnIoDriverLastStage: string;
function PawnIoDriverServiceIsRunning: Boolean;
function PawnIoDriverServiceExists: Boolean;
function PawnIoDriverServiceDeletePending: Boolean;
function PawnIoDriverDeviceZombieSuspected: Boolean;
function PawnIoDriverNeedsReboot: Boolean;

implementation

uses
  SysUtils, AppPaths;

const
  ERROR_SERVICE_EXISTS = 1073;
  ERROR_SERVICE_ALREADY_RUNNING = 1056;
  ERROR_SERVICE_MARKED_FOR_DELETE = 1072;
  SERVICE_KERNEL_DRIVER = $00000001;
  SERVICE_DEMAND_START = 3;
  SERVICE_ERROR_NORMAL = 1;
  SERVICE_RUNNING = 4;
  SERVICE_STOPPED = 1;
  SC_MANAGER_ALL_ACCESS = $F003F;
  SC_MANAGER_CONNECT = $0001;
  SERVICE_ALL_ACCESS = $F01FF;
  SERVICE_QUERY_STATUS = $0004;
  SERVICE_START = $0010;
  cDeviceOpenRetries = 20;
  cDeviceOpenRetryMs = 250;
  cDeletePendingWaitLoops = 5;
  cDeletePendingWaitMs = 1000;
  cStableBinSubDir = 'QDesktop\Bin\';
  cExternalPawnIoLib = 'PawnIO\PawnIOLib.dll';
  cOurManualImageMarker = 'qdesktop\bin\';
  cOfficialImageMarker = 'system32\drivers\pawnio.sys';
  HKEY_LOCAL_MACHINE = NativeUInt($80000002);
  KEY_READ = $20019;
  ERROR_SUCCESS = 0;
  ERROR_DEVINST_ALREADY_EXISTS = DWORD($E0000209);
  INSTALLFLAG_FORCE = $00000001;
  INSTALLFLAG_NONINTERACTIVE = $00000004;
  DICD_GENERATE_ID = $00000001;
  DIF_REGISTERDEVICE = $00000019;
  SPDRP_HARDWAREID = $00000001;
  cPawnIoClassGuid: TGUID = '{62f9c741-b25a-46ce-b54c-9bccce08b6f2}';

type
  TPawnRegKeyHandle = NativeUInt;
  HDEVINFO = NativeUInt;
  SP_DEVINFO_DATA = record
    cbSize: DWORD;
    ClassGuid: TGUID;
    DevInst: DWORD;
    Reserved: NativeUInt;
  end;
  PSPDevInfoData = ^SP_DEVINFO_DATA;
  SC_HANDLE = THandle;
  SERVICE_STATUS = record
    dwServiceType: DWORD;
    dwCurrentState: DWORD;
    dwControlsAccepted: DWORD;
    dwWin32ExitCode: DWORD;
    dwServiceSpecificExitCode: DWORD;
    dwCheckPoint: DWORD;
    dwWaitHint: DWORD;
  end;

function OpenSCManager(lpMachineName, lpDatabaseName: PChar;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall; external advapi32 name 'OpenSCManagerW';
function OpenService(hSCManager: SC_HANDLE; lpServiceName: PChar;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall; external advapi32 name 'OpenServiceW';
function StartService(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  lpServiceArgVectors: PChar): BOOL; stdcall; external advapi32 name 'StartServiceW';
function DeleteService(hService: SC_HANDLE): BOOL; stdcall; external advapi32 name 'DeleteService';
function QueryServiceStatus(hService: SC_HANDLE; var lpServiceStatus: SERVICE_STATUS): BOOL; stdcall;
  external advapi32 name 'QueryServiceStatus';
function CloseServiceHandle(hSCObject: SC_HANDLE): BOOL; stdcall;
  external advapi32 name 'CloseServiceHandle';
function UpdateDriverForPlugAndPlayDevicesW(hwndParent: HWND; HardwareId, FullInfPath: PWideChar;
  InstallFlags: DWORD; bRebootRequired: PBOOL): BOOL; stdcall;
  external 'newdev.dll' name 'UpdateDriverForPlugAndPlayDevicesW';
function SetupDiCreateDeviceInfoList(ClassGuid: PGUID; hwndParent: HWND): HDEVINFO; stdcall;
  external 'setupapi.dll' name 'SetupDiCreateDeviceInfoList';
function SetupDiCreateDeviceInfoW(DeviceInfoSet: HDEVINFO; DeviceName: PWideChar;
  ClassGuid: PGUID; DeviceDescription: PWideChar; hwndParent: HWND; CreationFlags: DWORD;
  DeviceInfoData: PSPDevInfoData): BOOL; stdcall; external 'setupapi.dll' name 'SetupDiCreateDeviceInfoW';
function SetupDiSetDeviceRegistryPropertyW(DeviceInfoSet: HDEVINFO; DeviceInfoData: PSPDevInfoData;
  Property_: DWORD; PropertyBuffer: PByte; PropertyBufferSize: DWORD): BOOL; stdcall;
  external 'setupapi.dll' name 'SetupDiSetDeviceRegistryPropertyW';
function SetupDiCallClassInstaller(InstallFunction: DWORD; DeviceInfoSet: HDEVINFO;
  DeviceInfoData: PSPDevInfoData): BOOL; stdcall; external 'setupapi.dll' name 'SetupDiCallClassInstaller';
function SetupDiDestroyDeviceInfoList(DeviceInfoSet: HDEVINFO): BOOL; stdcall;
  external 'setupapi.dll' name 'SetupDiDestroyDeviceInfoList';
function PawnRegOpenKeyExW(AKey: TPawnRegKeyHandle; ASubKey: PWideChar; AOptions: DWORD;
  ASamDesired: LongWord; var AResultKey: TPawnRegKeyHandle): Longint; stdcall;
  external advapi32 name 'RegOpenKeyExW';
function PawnRegCloseKey(AKey: TPawnRegKeyHandle): Longint; stdcall; external advapi32 name 'RegCloseKey';
function PawnRegQueryValueExW(AKey: TPawnRegKeyHandle; AValueName: PWideChar; AReserved: Pointer;
  var AType: DWORD; AData: PByte; var ADataSize: DWORD): Longint; stdcall;
  external advapi32 name 'RegQueryValueExW';

var
  GDriverOwnedByUs: Boolean;
  GLastError: DWORD;
  GLastStage: string;
  GSysPathTried: string;
  GDeviceZombieSuspected: Boolean;
  GNeedsReboot: Boolean;

procedure PawnIoDriverSetError(AError: DWORD);
begin
  if AError <> 0 then
    GLastError := AError
  else
    GLastError := GetLastError;
end;

function PawnIoDriverDeviceZombieSuspected: Boolean;
begin
  Result := GDeviceZombieSuspected;
end;

function PawnIoDriverNeedsReboot: Boolean;
begin
  Result := GNeedsReboot;
end;

function PawnIoDriverLastStage: string;
begin
  Result := GLastStage;
end;

function PawnIoDriverLastError: DWORD;
begin
  Result := GLastError;
end;

function PawnIoDriverInstalledByUs: Boolean;
begin
  Result := GDriverOwnedByUs;
end;

function PawnIoDriverFileExists(const APath: string): Boolean;
var
  attrs: DWORD;
begin
  attrs := GetFileAttributesW(PWideChar(APath));
  Result := (attrs <> INVALID_FILE_ATTRIBUTES) and
    ((attrs and FILE_ATTRIBUTE_DIRECTORY) = 0);
end;

function PawnIoDriverNormalizePath(const APath: string): string;
var
  path: string;
begin
  path := APath;
  if (Length(path) >= 4) and SameText(Copy(path, 1, 4), '\??\') then
    path := Copy(path, 5, MaxInt);
  Result := AnsiLowerCase(ExcludeTrailingPathDelimiter(ExpandFileName(path)));
end;

function PawnIoDriverProgramFilesPath: string;
var
  buf: array[0..MAX_PATH] of WideChar;
  len: DWORD;
begin
  len := GetEnvironmentVariableW('ProgramFiles', buf, MAX_PATH);
  if len > 0 then
    Result := IncludeTrailingPathDelimiter(string(buf))
  else
    Result := 'C:\Program Files\';
end;

function PawnIoDriverExternalInstalled: Boolean;
begin
  Result := PawnIoDriverFileExists(PawnIoDriverProgramFilesPath + cExternalPawnIoLib);
end;

function PawnIoDriverStableBinDir: string;
var
  localApp: string;
  len: DWORD;
  buf: array[0..MAX_PATH] of WideChar;
begin
  len := GetEnvironmentVariableW('LOCALAPPDATA', buf, MAX_PATH);
  if len = 0 then
    localApp := IncludeTrailingPathDelimiter(GetEnvironmentVariable('USERPROFILE')) + 'AppData\Local'
  else
    SetString(localApp, buf, len);
  Result := IncludeTrailingPathDelimiter(localApp) + cStableBinSubDir;
end;

function PawnIoDriverResolvePackageFile(const AFileName: string; out AResolvedPath: string): Boolean;
const
  cSysCandidates: array[0..1] of string = ('PawnIO.sys', 'PawnIO64.sys');
var
  i: Integer;
  path: string;
begin
  Result := False;
  AResolvedPath := '';
  if SameText(AFileName, cPawnIoSysFileName) or SameText(AFileName, 'PawnIO64.sys') then
  begin
    for i := Low(cSysCandidates) to High(cSysCandidates) do
    begin
      path := AppBinDllPath(cSysCandidates[i]);
      if PawnIoDriverFileExists(path) then
      begin
        AResolvedPath := path;
        GSysPathTried := path;
        Exit(True);
      end;
    end;
    GSysPathTried := AppBinDirectory + cPawnIoSysFileName;
    Exit;
  end;
  path := AppBinDllPath(AFileName);
  if PawnIoDriverFileExists(path) then
  begin
    AResolvedPath := path;
    Exit(True);
  end;
end;

function PawnIoDriverStagePackage(out AStagedInfPath: string): Boolean;
var
  srcSys, srcInf, srcCat, destDir, destSys, destInf, destCat: string;
begin
  Result := False;
  AStagedInfPath := '';
  if not PawnIoDriverResolvePackageFile(cPawnIoSysFileName, srcSys) then
    Exit;
  if not PawnIoDriverResolvePackageFile(cPawnIoInfFileName, srcInf) then
    Exit;
  if not PawnIoDriverResolvePackageFile(cPawnIoCatFileName, srcCat) then
    Exit;
  destDir := PawnIoDriverStableBinDir;
  destSys := destDir + cPawnIoSysFileName;
  destInf := destDir + cPawnIoInfFileName;
  destCat := destDir + cPawnIoCatFileName;
  if not ForceDirectories(destDir) then
    Exit;
  if PawnIoDriverFileExists(destSys) and PawnIoDriverFileExists(destInf) and
    PawnIoDriverFileExists(destCat) then
  begin
    AStagedInfPath := destInf;
    Exit(True);
  end;
  if not CopyFileW(PWideChar(srcSys), PWideChar(destSys), False) and
    not PawnIoDriverFileExists(destSys) then
    Exit;
  if not CopyFileW(PWideChar(srcInf), PWideChar(destInf), False) and
    not PawnIoDriverFileExists(destInf) then
    Exit;
  if not CopyFileW(PWideChar(srcCat), PWideChar(destCat), False) and
    not PawnIoDriverFileExists(destCat) then
    Exit;
  AStagedInfPath := destInf;
  Result := True;
end;

function PawnIoDriverServiceExists: Boolean;
var
  scm, svc: SC_HANDLE;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if scm = 0 then
    Exit;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName), SERVICE_QUERY_STATUS);
    if svc <> 0 then
    begin
      CloseServiceHandle(svc);
      Result := True;
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverServiceDeletePending: Boolean;
const
  cServiceKey = 'SYSTEM\CurrentControlSet\Services\' + cPawnIoServiceName;
var
  hKey: TPawnRegKeyHandle;
  deleteFlag: DWORD;
  dataType, cb: DWORD;
begin
  Result := False;
  if PawnRegOpenKeyExW(HKEY_LOCAL_MACHINE, PChar(cServiceKey), 0, KEY_READ, hKey) <> ERROR_SUCCESS then
    Exit;
  try
    cb := SizeOf(deleteFlag);
    if PawnRegQueryValueExW(hKey, 'DeleteFlag', nil, dataType, PByte(@deleteFlag), cb) = ERROR_SUCCESS then
      Result := deleteFlag <> 0;
  finally
    PawnRegCloseKey(hKey);
  end;
end;

function PawnIoDriverGetServiceImagePath(out AImagePath: string): Boolean;
const
  cServiceKey = 'SYSTEM\CurrentControlSet\Services\' + cPawnIoServiceName;
var
  hKey: TPawnRegKeyHandle;
  dataType, cb: DWORD;
  buf: array[0..1023] of WideChar;
begin
  Result := False;
  AImagePath := '';
  if PawnRegOpenKeyExW(HKEY_LOCAL_MACHINE, PChar(cServiceKey), 0, KEY_READ, hKey) <> ERROR_SUCCESS then
    Exit;
  try
    cb := SizeOf(buf) - SizeOf(WideChar);
    if PawnRegQueryValueExW(hKey, 'ImagePath', nil, dataType, PByte(@buf[0]), cb) <> ERROR_SUCCESS then
      Exit;
    buf[cb div SizeOf(WideChar)] := #0;
    AImagePath := string(buf);
    Result := AImagePath <> '';
  finally
    PawnRegCloseKey(hKey);
  end;
end;

function PawnIoDriverServiceIsRunning: Boolean;
var
  scm, svc: SC_HANDLE;
  status: SERVICE_STATUS;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if scm = 0 then
    Exit;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName), SERVICE_QUERY_STATUS);
    if svc = 0 then
      Exit;
    try
      if QueryServiceStatus(svc, status) then
        Result := status.dwCurrentState = SERVICE_RUNNING;
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverServiceIsStopped: Boolean;
var
  scm, svc: SC_HANDLE;
  status: SERVICE_STATUS;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if scm = 0 then
    Exit;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName), SERVICE_QUERY_STATUS);
    if svc = 0 then
      Exit(True);
    try
      if QueryServiceStatus(svc, status) then
        Result := status.dwCurrentState = SERVICE_STOPPED;
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverIsManualServiceImage(const AImagePath: string): Boolean;
begin
  Result := Pos(cOurManualImageMarker, PawnIoDriverNormalizePath(AImagePath)) > 0;
end;

function PawnIoDriverIsOfficialServiceImage(const AImagePath: string): Boolean;
begin
  Result := Pos(cOfficialImageMarker, PawnIoDriverNormalizePath(AImagePath)) > 0;
end;

function PawnIoDriverTryOpenDevicePath(const APath: string): THandle;
begin
  Result := CreateFile(
    PChar(APath),
    GENERIC_READ or GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    0);
end;

function PawnIoDriverTryOpenDevice(out ADevicePath: string): THandle;
const
  cPaths: array[0..1] of string = (cPawnIoDevicePath, cPawnIoDevicePathAlt);
var
  i: Integer;
begin
  ADevicePath := cPawnIoDevicePath;
  for i := Low(cPaths) to High(cPaths) do
  begin
    Result := PawnIoDriverTryOpenDevicePath(cPaths[i]);
    if Result <> INVALID_HANDLE_VALUE then
    begin
      ADevicePath := cPaths[i];
      Exit;
    end;
  end;
  PawnIoDriverSetError(0);
end;

function PawnIoDriverTryOpenDeviceWait(out ADevicePath: string): THandle;
var
  i: Integer;
begin
  for i := 0 to cDeviceOpenRetries - 1 do
  begin
    Result := PawnIoDriverTryOpenDevice(ADevicePath);
    if Result <> INVALID_HANDLE_VALUE then
      Exit;
    if i < cDeviceOpenRetries - 1 then
      Sleep(cDeviceOpenRetryMs);
  end;
end;

function PawnIoDriverStartService: Boolean;
var
  scm, svc: SC_HANDLE;
  err: DWORD;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
  if scm = 0 then
  begin
    PawnIoDriverSetError(0);
    Exit;
  end;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName), SERVICE_ALL_ACCESS);
    if svc = 0 then
    begin
      PawnIoDriverSetError(0);
      Exit;
    end;
    try
      if StartService(svc, 0, nil) then
        Result := True
      else
      begin
        err := GetLastError;
        if err = ERROR_SERVICE_ALREADY_RUNNING then
          Result := True
        else
          PawnIoDriverSetError(err);
      end;
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverDeleteStoppedService: Boolean;
var
  scm, svc: SC_HANDLE;
begin
  Result := False;
  if PawnIoDriverServiceDeletePending or not PawnIoDriverServiceIsStopped then
    Exit;
  scm := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
  if scm = 0 then
    Exit;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName), SERVICE_ALL_ACCESS);
    if svc = 0 then
      Exit;
    try
      Result := DeleteService(svc);
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverWaitDeletePendingClear: Boolean;
var
  i: Integer;
  h: THandle;
  devPath: string;
begin
  Result := False;
  GLastStage := '等待服务删除';
  for i := 0 to cDeletePendingWaitLoops - 1 do
  begin
    h := PawnIoDriverTryOpenDevice(devPath);
    if h <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(h);
      Exit(True);
    end;
    if not PawnIoDriverServiceDeletePending then
      Exit(not PawnIoDriverServiceExists);
    Sleep(cDeletePendingWaitMs);
  end;
  if PawnIoDriverServiceDeletePending then
  begin
    GNeedsReboot := True;
    PawnIoDriverSetError(ERROR_SERVICE_MARKED_FOR_DELETE);
  end;
end;

function PawnIoDriverRegisterRootDevice: Boolean;
var
  devInfo: SP_DEVINFO_DATA;
  devInfoSet: HDEVINFO;
  hwId: array[0..11] of WideChar;
  err: DWORD;
begin
  Result := False;
  devInfoSet := SetupDiCreateDeviceInfoList(@cPawnIoClassGuid, 0);
  if devInfoSet = HDEVINFO(NativeInt(-1)) then
  begin
    PawnIoDriverSetError(0);
    Exit;
  end;
  try
    FillChar(devInfo, SizeOf(devInfo), 0);
    devInfo.cbSize := SizeOf(devInfo);
    if not SetupDiCreateDeviceInfoW(devInfoSet, 'PawnIO', @cPawnIoClassGuid, 'PawnIO', 0,
      DICD_GENERATE_ID, @devInfo) then
    begin
      err := GetLastError;
      if err = ERROR_DEVINST_ALREADY_EXISTS then
        Exit(True);
      PawnIoDriverSetError(err);
      Exit;
    end;
    StrPCopy(hwId, 'Root\PawnIO');
    hwId[10] := #0;
    hwId[11] := #0;
    if not SetupDiSetDeviceRegistryPropertyW(devInfoSet, @devInfo, SPDRP_HARDWAREID,
      PByte(@hwId[0]), SizeOf(hwId)) then
    begin
      PawnIoDriverSetError(0);
      Exit;
    end;
    if not SetupDiCallClassInstaller(DIF_REGISTERDEVICE, devInfoSet, @devInfo) then
    begin
      PawnIoDriverSetError(0);
      Exit;
    end;
    Result := True;
  finally
    SetupDiDestroyDeviceInfoList(devInfoSet);
  end;
end;

function PawnIoDriverInstallViaInf(const AInfPath: string): Boolean;
var
  rebootRequired: BOOL;
begin
  Result := False;
  rebootRequired := False;
  if UpdateDriverForPlugAndPlayDevicesW(
    0,
    PChar(cPawnIoHardwareId),
    PChar(AInfPath),
    INSTALLFLAG_FORCE or INSTALLFLAG_NONINTERACTIVE,
    @rebootRequired) then
  begin
    GDriverOwnedByUs := True;
    if rebootRequired then
      GNeedsReboot := True;
    Exit(True);
  end;
  PawnIoDriverSetError(0);
end;

function PawnIoDriverDetectZombieState: Boolean;
var
  imagePath: string;
begin
  Result := False;
  if not PawnIoDriverServiceIsRunning then
    Exit;
  if PawnIoDriverTryOpenDevicePath(cPawnIoDevicePath) <> INVALID_HANDLE_VALUE then
    Exit;
  if PawnIoDriverTryOpenDevicePath(cPawnIoDevicePathAlt) <> INVALID_HANDLE_VALUE then
    Exit;
  Result := True;
  GDeviceZombieSuspected := True;
  if PawnIoDriverServiceDeletePending then
  begin
    GNeedsReboot := True;
    Exit;
  end;
  if PawnIoDriverGetServiceImagePath(imagePath) and
    PawnIoDriverIsManualServiceImage(imagePath) then
    GNeedsReboot := True;
end;

function PawnIoDriverTryStartAndOpen(out ADevPath: string): Boolean;
var
  h: THandle;
begin
  Result := False;
  if PawnIoDriverServiceExists and not PawnIoDriverServiceIsRunning then
  begin
    if not PawnIoDriverStartService then
      Exit;
  end;
  h := PawnIoDriverTryOpenDeviceWait(ADevPath);
  if h <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(h);
    Exit(True);
  end;
  if PawnIoDriverDetectZombieState then
    GLastStage := '打开设备';
end;

function PawnIoDriverEnsureOurService(const AStagedInfPath: string): Boolean;
var
  imagePath: string;
begin
  Result := False;

  if PawnIoDriverExternalInstalled then
  begin
    Result := PawnIoDriverTryStartAndOpen(GSysPathTried);
    if not Result then
      GLastStage := '打开设备';
    Exit;
  end;

  if PawnIoDriverServiceDeletePending then
  begin
    GNeedsReboot := True;
    GLastStage := '恢复驱动';
    PawnIoDriverSetError(ERROR_SERVICE_MARKED_FOR_DELETE);
    Exit;
  end;

  if PawnIoDriverDetectZombieState then
  begin
    GLastStage := '打开设备';
    PawnIoDriverSetError(ERROR_FILE_NOT_FOUND);
    Exit;
  end;

  if PawnIoDriverServiceExists then
  begin
    if PawnIoDriverGetServiceImagePath(imagePath) and
      PawnIoDriverIsManualServiceImage(imagePath) and
      PawnIoDriverServiceIsStopped then
      PawnIoDriverDeleteStoppedService;

    if PawnIoDriverServiceExists then
    begin
      if PawnIoDriverTryStartAndOpen(GSysPathTried) then
        Exit(True);
      if PawnIoDriverDetectZombieState then
      begin
        GLastStage := '打开设备';
        Exit;
      end;
    end;
  end;

  if AStagedInfPath = '' then
  begin
    GLastStage := '检查驱动';
    GLastError := ERROR_FILE_NOT_FOUND;
    Exit;
  end;

  if not PawnIoDriverRegisterRootDevice then
  begin
    GLastStage := '安装驱动';
    Exit;
  end;

  if not PawnIoDriverInstallViaInf(AStagedInfPath) then
  begin
    GLastStage := '安装驱动';
    Exit;
  end;

  if GNeedsReboot then
  begin
    GLastStage := '安装驱动';
    Exit;
  end;

  if not PawnIoDriverStartService then
  begin
    GLastStage := '启动驱动';
    Exit;
  end;

  Result := PawnIoDriverTryStartAndOpen(GSysPathTried);
  if not Result then
    GLastStage := '打开设备';
end;

function PawnIoDriverEnsureRunning: Boolean;
var
  stagedInf, devPath: string;
  h: THandle;
begin
  Result := False;
  GLastError := 0;
  GLastStage := '';
  GDeviceZombieSuspected := False;
  GNeedsReboot := False;

  h := PawnIoDriverTryOpenDevice(devPath);
  if h <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(h);
    Exit(True);
  end;

  if PawnIoDriverExternalInstalled then
    Exit(PawnIoDriverEnsureOurService(''));

  if PawnIoDriverServiceDeletePending then
  begin
    GNeedsReboot := True;
    GLastStage := '恢复驱动';
    GLastError := ERROR_SERVICE_MARKED_FOR_DELETE;
    Exit;
  end;

  if PawnIoDriverDetectZombieState then
  begin
    GLastStage := '打开设备';
    GLastError := ERROR_FILE_NOT_FOUND;
    Exit;
  end;

  if not PawnIoDriverStagePackage(stagedInf) then
  begin
    GLastStage := '检查驱动';
    GLastError := ERROR_FILE_NOT_FOUND;
    Exit;
  end;

  Result := PawnIoDriverEnsureOurService(stagedInf);
end;

procedure PawnIoDriverUnloadIfOwned;
begin
  GDriverOwnedByUs := False;
end;

end.
