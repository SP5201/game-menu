unit PawnIoDriver;

{
  PawnIO 内核驱动服务生命周期：注册/启动/探测设备；仅在本进程新建服务时退出卸载（策略 A）。
}

interface

uses
  Windows;

const
  cPawnIoSysFileName = 'PawnIO.sys';
  cPawnIoServiceName = 'PawnIO';

function PawnIoDriverTryOpenDevice(out ADevicePath: string): THandle;
function PawnIoDriverEnsureRunning: Boolean;
function PawnIoDriverInstalledByUs: Boolean;
procedure PawnIoDriverUnloadIfOwned;
function PawnIoDriverLastError: DWORD;
function PawnIoDriverLastStage: string;
function PawnIoDriverServiceIsRunning: Boolean;
function PawnIoDriverDeviceZombieSuspected: Boolean;
function PawnIoDriverNeedsReboot: Boolean;

implementation

uses
  SysUtils, AppPaths;

const
  ERROR_SERVICE_EXISTS = 1073;
  ERROR_SERVICE_ALREADY_RUNNING = 1056;
  ERROR_SERVICE_MARKED_FOR_DELETE = 1072;
  ERROR_SERVICE_CANNOT_ACCEPT_CTRL = 1052;
  SERVICE_KERNEL_DRIVER = $00000001;
  SERVICE_DEMAND_START = 3;
  SERVICE_ERROR_NORMAL = 1;
  SERVICE_CONTROL_STOP = 1;
  SERVICE_RUNNING = 4;
  SERVICE_STOPPED = 1;
  SC_MANAGER_ALL_ACCESS = $F003F;
  SC_MANAGER_CONNECT = $0001;
  SERVICE_ALL_ACCESS = $F01FF;
  SERVICE_QUERY_STATUS = $0004;
  SERVICE_STOP = $0020;
  SERVICE_START = $0010;
  cDeviceOpenRetries = 10;
  cDeviceOpenRetryMs = 200;
  HKEY_LOCAL_MACHINE = NativeUInt($80000002);
  KEY_READ = $20019;
  ERROR_SUCCESS = 0;

type
  TPawnRegKeyHandle = NativeUInt;
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
function CreateService(hSCManager: SC_HANDLE; lpServiceName, lpDisplayName: PChar;
  dwDesiredAccess, dwServiceType, dwStartType, dwErrorControl: DWORD;
  lpBinaryPathName, lpLoadOrderGroup: PChar; lpdwTagId: PDWORD;
  lpDependencies, lpServiceStartName, lpPassword: PChar): SC_HANDLE; stdcall;
  external advapi32 name 'CreateServiceW';
function OpenService(hSCManager: SC_HANDLE; lpServiceName: PChar;
  dwDesiredAccess: DWORD): SC_HANDLE; stdcall; external advapi32 name 'OpenServiceW';
function StartService(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
  lpServiceArgVectors: PChar): BOOL; stdcall; external advapi32 name 'StartServiceW';
function ControlService(hService: SC_HANDLE; dwControl: DWORD;
  var lpServiceStatus: SERVICE_STATUS): BOOL; stdcall; external advapi32 name 'ControlService';
function DeleteService(hService: SC_HANDLE): BOOL; stdcall; external advapi32 name 'DeleteService';
function QueryServiceStatus(hService: SC_HANDLE; var lpServiceStatus: SERVICE_STATUS): BOOL; stdcall;
  external advapi32 name 'QueryServiceStatus';
function CloseServiceHandle(hSCObject: SC_HANDLE): BOOL; stdcall;
  external advapi32 name 'CloseServiceHandle';
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

function PawnIoDriverTryStopService: Boolean;
var
  scm, svc: SC_HANDLE;
  status: SERVICE_STATUS;
  err: DWORD;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if scm = 0 then
    Exit;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName),
      SERVICE_STOP or SERVICE_QUERY_STATUS);
    if svc = 0 then
      Exit;
    try
      if QueryServiceStatus(svc, status) and
        (status.dwCurrentState = SERVICE_STOPPED) then
        Exit(True);
      if ControlService(svc, SERVICE_CONTROL_STOP, status) then
        Exit(True);
      err := GetLastError;
      Result := (err = ERROR_SERVICE_CANNOT_ACCEPT_CTRL) or
        (err = ERROR_SERVICE_MARKED_FOR_DELETE);
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverWaitServiceStopped(svc: SC_HANDLE): Boolean;
var
  status: SERVICE_STATUS;
  i: Integer;
begin
  Result := False;
  for i := 0 to 49 do
  begin
    if not QueryServiceStatus(svc, status) then
      Exit;
    if status.dwCurrentState = SERVICE_STOPPED then
      Exit(True);
    Sleep(100);
  end;
end;

function PawnIoDriverRemoveService: Boolean;
var
  scm, svc: SC_HANDLE;
  status: SERVICE_STATUS;
  err: DWORD;
begin
  Result := False;
  if PawnIoDriverServiceDeletePending then
  begin
    PawnIoDriverSetError(ERROR_SERVICE_MARKED_FOR_DELETE);
    Exit;
  end;
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
      err := GetLastError;
      if err = ERROR_SERVICE_MARKED_FOR_DELETE then
      begin
        GNeedsReboot := True;
        PawnIoDriverSetError(err);
      end;
      Exit(True);
    end;
    try
      if not ControlService(svc, SERVICE_CONTROL_STOP, status) then
      begin
        err := GetLastError;
        if (err = ERROR_SERVICE_CANNOT_ACCEPT_CTRL) or
          (err = ERROR_SERVICE_MARKED_FOR_DELETE) then
          GNeedsReboot := True;
      end;
      if not PawnIoDriverWaitServiceStopped(svc) then
        Exit;
      if DeleteService(svc) then
        Exit(True);
      err := GetLastError;
      if err = ERROR_SERVICE_MARKED_FOR_DELETE then
        GNeedsReboot := True;
      PawnIoDriverSetError(err);
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverLastStage: string;
begin
  Result := GLastStage;
end;

function PawnIoDriverFileExists(const APath: string): Boolean;
var
  attrs: DWORD;
begin
  attrs := GetFileAttributesW(PWideChar(APath));
  Result := (attrs <> INVALID_FILE_ATTRIBUTES) and
    ((attrs and FILE_ATTRIBUTE_DIRECTORY) = 0);
end;

function PawnIoDriverResolveSysPath(out AResolvedPath: string): Boolean;
const
  cCandidates: array[0..1] of string = ('PawnIO.sys', 'PawnIO64.sys');
var
  i: Integer;
  path: string;
begin
  Result := False;
  AResolvedPath := '';
  GSysPathTried := AppBinDirectory + 'PawnIO.sys';
  for i := Low(cCandidates) to High(cCandidates) do
  begin
    path := AppBinDllPath(cCandidates[i]);
    if PawnIoDriverFileExists(path) then
    begin
      AResolvedPath := path;
      GSysPathTried := path;
      Exit(True);
    end;
  end;
end;

function PawnIoDriverLastError: DWORD;
begin
  Result := GLastError;
end;

function PawnIoDriverInstalledByUs: Boolean;
begin
  Result := GDriverOwnedByUs;
end;

function PawnIoDriverTryOpenDevice(out ADevicePath: string): THandle;
const
  cPaths: array[0..1] of PChar = (
    '\\.\PawnIO',
    '\\?\GLOBALROOT\Device\PawnIO');
var
  i: Integer;
  h: THandle;
begin
  Result := INVALID_HANDLE_VALUE;
  ADevicePath := '';
  for i := Low(cPaths) to High(cPaths) do
  begin
    h := CreateFile(
      cPaths[i],
      GENERIC_READ or GENERIC_WRITE,
      FILE_SHARE_READ or FILE_SHARE_WRITE,
      nil,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      0);
    if h <> INVALID_HANDLE_VALUE then
    begin
      ADevicePath := string(cPaths[i]);
      Result := h;
      Exit;
    end;
    PawnIoDriverSetError(0);
    ADevicePath := string(cPaths[i]);
  end;
end;

function PawnIoDriverInstall(const ADriverPath: string): Boolean;
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
    svc := CreateService(
      scm,
      PChar(cPawnIoServiceName),
      PChar(cPawnIoServiceName),
      SERVICE_ALL_ACCESS,
      SERVICE_KERNEL_DRIVER,
      SERVICE_DEMAND_START,
      SERVICE_ERROR_NORMAL,
      PChar(ADriverPath),
      nil, nil, nil, nil, nil);
    if svc <> 0 then
    begin
      CloseServiceHandle(svc);
      GDriverOwnedByUs := True;
      Result := True;
      Exit;
    end;
    err := GetLastError;
    if err = ERROR_SERVICE_EXISTS then
    begin
      svc := OpenService(scm, PChar(cPawnIoServiceName), SERVICE_ALL_ACCESS);
      if svc <> 0 then
      begin
        CloseServiceHandle(svc);
        Result := True;
      end
      else
        PawnIoDriverSetError(0);
    end
    else if err = ERROR_SERVICE_MARKED_FOR_DELETE then
    begin
      GNeedsReboot := True;
      PawnIoDriverSetError(err);
    end
    else
      PawnIoDriverSetError(err);
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverStart: Boolean;
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
        else if err = ERROR_SERVICE_MARKED_FOR_DELETE then
        begin
          GNeedsReboot := True;
          PawnIoDriverSetError(err);
        end
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

function PawnIoDriverHandleDeletePending: Boolean;
var
  h: THandle;
  devPath: string;
begin
  Result := False;
  GNeedsReboot := True;
  GLastError := ERROR_SERVICE_MARKED_FOR_DELETE;
  PawnIoDriverTryStopService;
  Sleep(cDeviceOpenRetryMs);
  h := PawnIoDriverTryOpenDeviceWait(devPath);
  if h <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(h);
    GNeedsReboot := False;
    GLastError := 0;
    Exit(True);
  end;
  GDeviceZombieSuspected := PawnIoDriverServiceIsRunning;
  GLastStage := '恢复驱动';
end;

function PawnIoDriverRestartService: Boolean;
var
  scm, svc: SC_HANDLE;
  status: SERVICE_STATUS;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if scm = 0 then
    Exit;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName),
      SERVICE_STOP or SERVICE_START or SERVICE_QUERY_STATUS);
    if svc = 0 then
      Exit;
    try
      if not QueryServiceStatus(svc, status) then
        Exit;
      if status.dwCurrentState = SERVICE_RUNNING then
      begin
        ControlService(svc, SERVICE_CONTROL_STOP, status);
        PawnIoDriverWaitServiceStopped(svc);
        if not QueryServiceStatus(svc, status) then
          Exit;
        if status.dwCurrentState <> SERVICE_STOPPED then
          Exit;
      end;
      if StartService(svc, 0, nil) then
        Result := True;
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoDriverEnsureRunning: Boolean;
var
  sysPath: string;
  h: THandle;
  devPath: string;
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

  if not PawnIoDriverResolveSysPath(sysPath) then
  begin
    GLastStage := '检查驱动';
    GLastError := ERROR_FILE_NOT_FOUND;
    Exit;
  end;

  if PawnIoDriverServiceDeletePending then
    Exit(PawnIoDriverHandleDeletePending);

  if PawnIoDriverServiceExists then
  begin
    if PawnIoDriverServiceIsRunning then
    begin
      Sleep(cDeviceOpenRetryMs);
      h := PawnIoDriverTryOpenDevice(devPath);
      if h <> INVALID_HANDLE_VALUE then
      begin
        CloseHandle(h);
        Exit(True);
      end;
    end;

    if PawnIoDriverRestartService then
    begin
      h := PawnIoDriverTryOpenDeviceWait(devPath);
      if h <> INVALID_HANDLE_VALUE then
      begin
        CloseHandle(h);
        Exit(True);
      end;
    end;

    if not PawnIoDriverRemoveService then
    begin
      if PawnIoDriverNeedsReboot then
        GLastStage := '恢复驱动'
      else
      begin
        GDeviceZombieSuspected := PawnIoDriverServiceIsRunning;
        GLastStage := '打开设备';
      end;
      Exit;
    end;
    Sleep(200);
  end;

  if not PawnIoDriverInstall(sysPath) then
  begin
    if PawnIoDriverNeedsReboot then
      GLastStage := '恢复驱动'
    else
      GLastStage := '注册服务';
    Exit;
  end;
  if not PawnIoDriverStart then
  begin
    if PawnIoDriverNeedsReboot then
      GLastStage := '恢复驱动'
    else
      GLastStage := '启动驱动';
    Exit;
  end;

  h := PawnIoDriverTryOpenDeviceWait(devPath);
  if h <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(h);
    Exit(True);
  end;
  GDeviceZombieSuspected := PawnIoDriverServiceIsRunning;
  GLastStage := '打开设备';
end;

procedure PawnIoDriverUnloadIfOwned;
var
  scm, svc: SC_HANDLE;
  status: SERVICE_STATUS;
begin
  if not GDriverOwnedByUs then
    Exit;
  scm := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
  if scm = 0 then
    Exit;
  try
    svc := OpenService(scm, PChar(cPawnIoServiceName), SERVICE_ALL_ACCESS);
    if svc = 0 then
      Exit;
    try
      if QueryServiceStatus(svc, status) and
        (status.dwCurrentState <> SERVICE_STOPPED) then
        ControlService(svc, SERVICE_CONTROL_STOP, status);
      if PawnIoDriverWaitServiceStopped(svc) then
        DeleteService(svc);
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
  GDriverOwnedByUs := False;
end;

end.
