unit PawnIo;

{
  PawnIO 封装：直接 DeviceIoControl 访问内核驱动，不依赖 PawnIOLib.dll（32 位程序无法加载 64 位库）。
  Bin\PawnIO.sys 随程序分发，首次以管理员权限自动注册；模块按 CPU 选择（AMD Zen → AMDFamily17）。
}

interface

uses
  Windows;

type
  TPawnIoBackend = (pbNone, pbIntelMsr, pbAmdFamily17, pbAmdFamily10, pbAmdFamily0F);

function PawnIoAvailable: Boolean;
function PawnIoLoadFailureDetail: string;
function PawnIoBackend: TPawnIoBackend;
function PawnIoIsMsrSupported: Boolean;
function PawnIoReadMsr(AIndex: DWORD; out AEax, AEdx: DWORD): Boolean;
function PawnIoReadMsrTx(AIndex: DWORD; AThreadAffinityMask: ULONG_PTR;
  out AEax, AEdx: DWORD): Boolean;
function PawnIoReadSmn(AOffset: DWORD; out AValue: DWORD): Boolean;
function PawnIoEnsureDriver: Boolean;
function PawnIoLpcAvailable: Boolean;
function PawnIoLpcExecute0(const AName: AnsiString): Boolean;
function PawnIoLpcExecute1(const AName: AnsiString; AInput: UInt64;
  out AOutput: UInt64): Boolean;
function PawnIoLpcExecute2(const AName: AnsiString; AInput0, AInput1: UInt64): Boolean;
function PawnIoLpcRun(const AName: AnsiString; const AInputs: array of UInt64): Boolean;
function PawnIoLpcPioInB(APort: Word): Boolean; overload;
function PawnIoLpcPioInB(APort: Word; out AValue: Byte): Boolean; overload;
procedure PawnIoShutdown;

implementation

uses
  SysUtils, Classes, Math, AppPaths;

const
  cPawnIoSysName = 'PawnIO.sys';
  cPawnIoDriverId = 'PawnIO';
  cPawnIoFnNameLen = 32;
  cPawnIoDeviceType = DWORD(41394) shl 16;
  IOCTL_PIO_LOAD_BINARY = cPawnIoDeviceType or (DWORD($821) shl 2);
  IOCTL_PIO_EXECUTE_FN = cPawnIoDeviceType or (DWORD($841) shl 2);
  ERROR_FILE_NOT_FOUND = 2;
  ERROR_NOT_SUPPORTED = 50;
  ERROR_ACCESS_DENIED = 5;
  SERVICE_KERNEL_DRIVER = $00000001;
  SERVICE_DEMAND_START = 3;
  SERVICE_ERROR_NORMAL = 1;
  SERVICE_CONTROL_STOP = 1;
  SC_MANAGER_ALL_ACCESS = $F003F;
  SERVICE_ALL_ACCESS = $F01FF;
  ERROR_SERVICE_EXISTS = 1073;
  ERROR_SERVICE_ALREADY_RUNNING = 1056;

type
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

  TCpuIdRegs = record
    Eax, Ebx, Ecx, Edx: Cardinal;
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
function CloseServiceHandle(hSCObject: SC_HANDLE): BOOL; stdcall;
  external advapi32 name 'CloseServiceHandle';

var
  GDeviceHandle: THandle;
  GLpcHandle: THandle;
  GBackend: TPawnIoBackend;
  GInitialized: Boolean;
  GInitFailed: Boolean;
  GLpcInitialized: Boolean;
  GLpcInitFailed: Boolean;
  GMsrSupported: Boolean;
  GMsrChecked: Boolean;
  GLastLoadError: DWORD;
  GLastLoadStage: string;
  GLastModuleName: string;

procedure CpuIdLeaf(const AFunc: Cardinal; out ARegs: TCpuIdRegs); assembler;
asm
  push ebx
  push edi
  mov edi, edx
  cpuid
  mov dword ptr [edi], eax
  mov dword ptr [edi + 4], ebx
  mov dword ptr [edi + 8], ecx
  mov dword ptr [edi + 12], edx
  pop edi
  pop ebx
end;

function PawnIoVendorId: string;
var
  regs: TCpuIdRegs;
  raw: array[0..12] of AnsiChar;
begin
  Result := '';
  CpuIdLeaf(0, regs);
  FillChar(raw, SizeOf(raw), 0);
  Move(regs.Ebx, raw[0], 4);
  Move(regs.Edx, raw[4], 4);
  Move(regs.Ecx, raw[8], 4);
  Result := string(raw);
end;

function PawnIoFamilyModel: Cardinal;
var
  regs: TCpuIdRegs;
begin
  CpuIdLeaf(1, regs);
  Result := (regs.Eax shr 8) and $FF0F;
end;

function PawnIoSelectModuleName(out ABackend: TPawnIoBackend): string;
var
  family: Cardinal;
begin
  ABackend := pbIntelMsr;
  Result := 'IntelMSR.bin';
  if SameText(PawnIoVendorId, 'AuthenticAMD') then
  begin
    family := PawnIoFamilyModel shr 4;
    if family >= $17 then
    begin
      ABackend := pbAmdFamily17;
      Result := 'AMDFamily17.bin';
    end
    else if family >= $10 then
    begin
      ABackend := pbAmdFamily10;
      Result := 'AMDFamily10.bin';
    end
    else
    begin
      ABackend := pbAmdFamily0F;
      Result := 'AMDFamily0F.bin';
    end;
  end;
end;

procedure PawnIoSetLoadFailure(const AStage: string; AError: DWORD = 0);
begin
  GLastLoadStage := AStage;
  if AError <> 0 then
    GLastLoadError := AError
  else
    GLastLoadError := GetLastError;
end;

function PawnIoLoadErrorHint(AError: DWORD): string;
begin
  case AError of
    ERROR_FILE_NOT_FOUND:
      begin
        if GLastLoadStage = '检查驱动' then
          Result := 'Bin\PawnIO.sys 未找到'
        else if GLastLoadStage = '打开设备' then
          Result := 'PawnIO 驱动未运行，请以管理员权限启动一次'
        else
          Result := GLastModuleName + ' 未找到';
      end;
    ERROR_NOT_SUPPORTED:
      if GLastModuleName = 'IntelMSR.bin' then
        Result := '当前 PawnIO 驱动禁用了通用 MSR 模块'
      else
        Result := GLastModuleName + ' 与当前 PawnIO 驱动不兼容';
    ERROR_ACCESS_DENIED:
      Result := '需要管理员权限安装 PawnIO 驱动';
  else
    Result := SysErrorMessage(AError);
    if Result = '' then
      Result := '未知错误';
  end;
end;

function PawnIoLoadFailureDetail: string;
begin
  if GLastLoadStage <> '' then
    Result := Format('PawnIO 不可用（%s）：%s（错误 %d）',
      [GLastLoadStage, PawnIoLoadErrorHint(GLastLoadError), GLastLoadError])
  else if GLastLoadError <> 0 then
    Result := Format('PawnIO 不可用：%s（错误 %d）',
      [PawnIoLoadErrorHint(GLastLoadError), GLastLoadError])
  else
    Result := 'PawnIO 不可用';
end;

function PawnIoBackend: TPawnIoBackend;
begin
  Result := GBackend;
end;

procedure PawnIoCloseDevice;
begin
  if GDeviceHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(GDeviceHandle);
    GDeviceHandle := INVALID_HANDLE_VALUE;
  end;
end;

function PawnIoTryOpenDevice: THandle;
const
  cPaths: array[0..1] of PChar = (
    '\\.\PawnIO',
    '\\?\GLOBALROOT\Device\PawnIO');
var
  i: Integer;
  h: THandle;
begin
  Result := INVALID_HANDLE_VALUE;
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
      Result := h;
      Exit;
    end;
  end;
end;

function PawnIoInstallDriver(const ADriverPath: string): Boolean;
var
  scm, svc: SC_HANDLE;
  err: DWORD;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
  if scm = 0 then
  begin
    PawnIoSetLoadFailure('注册服务', 0);
    Exit;
  end;
  try
    svc := CreateService(
      scm,
      PChar(cPawnIoDriverId),
      PChar(cPawnIoDriverId),
      SERVICE_ALL_ACCESS,
      SERVICE_KERNEL_DRIVER,
      SERVICE_DEMAND_START,
      SERVICE_ERROR_NORMAL,
      PChar(ADriverPath),
      nil, nil, nil, nil, nil);
    if svc <> 0 then
    begin
      CloseServiceHandle(svc);
      Result := True;
      Exit;
    end;
    err := GetLastError;
    if err = ERROR_SERVICE_EXISTS then
    begin
      svc := OpenService(scm, PChar(cPawnIoDriverId), SERVICE_ALL_ACCESS);
      if svc <> 0 then
      begin
        CloseServiceHandle(svc);
        Result := True;
      end
      else
        PawnIoSetLoadFailure('打开已有服务', 0);
    end
    else
      PawnIoSetLoadFailure('注册服务', err);
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoStartDriver: Boolean;
var
  scm, svc: SC_HANDLE;
  err: DWORD;
begin
  Result := False;
  scm := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
  if scm = 0 then
  begin
    PawnIoSetLoadFailure('启动驱动', 0);
    Exit;
  end;
  try
    svc := OpenService(scm, PChar(cPawnIoDriverId), SERVICE_ALL_ACCESS);
    if svc = 0 then
    begin
      PawnIoSetLoadFailure('启动驱动', 0);
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
          PawnIoSetLoadFailure('启动驱动', err);
      end;
    finally
      CloseServiceHandle(svc);
    end;
  finally
    CloseServiceHandle(scm);
  end;
end;

function PawnIoHandleExecute(AHandle: THandle; const AName: AnsiString;
  const AInputs: array of UInt64; AOutCount: Integer; out AOutput: UInt64): Boolean;
var
  fnName: array[0..cPawnIoFnNameLen - 1] of AnsiChar;
  inBuf, outBuf: TBytes;
  inSize, outSize, returned: DWORD;
  i: Integer;
begin
  Result := False;
  AOutput := 0;
  if (AHandle = INVALID_HANDLE_VALUE) or (AOutCount <= 0) then
    Exit;

  FillChar(fnName, SizeOf(fnName), 0);
  if Length(AName) > 0 then
    Move(PAnsiChar(AName)^, fnName[0], Min(Length(AName), cPawnIoFnNameLen - 1));

  inSize := cPawnIoFnNameLen + Length(AInputs) * SizeOf(UInt64);
  SetLength(inBuf, inSize);
  Move(fnName[0], inBuf[0], cPawnIoFnNameLen);
  for i := 0 to Length(AInputs) - 1 do
    Move(AInputs[i], inBuf[cPawnIoFnNameLen + i * SizeOf(UInt64)], SizeOf(UInt64));

  outSize := AOutCount * SizeOf(UInt64);
  SetLength(outBuf, outSize);
  FillChar(outBuf[0], outSize, 0);

  Result := DeviceIoControl(
    AHandle,
    IOCTL_PIO_EXECUTE_FN,
    @inBuf[0],
    inSize,
    @outBuf[0],
    outSize,
    returned,
    nil);
  if Result and (returned >= SizeOf(UInt64)) then
    Move(outBuf[0], AOutput, SizeOf(UInt64))
  else
    Result := False;
end;

function PawnIoHandleExecuteNoOut(AHandle: THandle; const AName: AnsiString;
  const AInputs: array of UInt64): Boolean;
var
  fnName: array[0..cPawnIoFnNameLen - 1] of AnsiChar;
  inBuf: TBytes;
  inSize, returned: DWORD;
  i: Integer;
begin
  Result := False;
  if AHandle = INVALID_HANDLE_VALUE then
    Exit;

  FillChar(fnName, SizeOf(fnName), 0);
  if Length(AName) > 0 then
    Move(PAnsiChar(AName)^, fnName[0], Min(Length(AName), cPawnIoFnNameLen - 1));

  inSize := cPawnIoFnNameLen + Length(AInputs) * SizeOf(UInt64);
  SetLength(inBuf, inSize);
  Move(fnName[0], inBuf[0], cPawnIoFnNameLen);
  for i := 0 to Length(AInputs) - 1 do
    Move(AInputs[i], inBuf[cPawnIoFnNameLen + i * SizeOf(UInt64)], SizeOf(UInt64));

  Result := DeviceIoControl(
    AHandle,
    IOCTL_PIO_EXECUTE_FN,
    @inBuf[0],
    inSize,
    nil,
    0,
    returned,
    nil);
end;

function PawnIoExecuteOne(const AName: AnsiString; AInput: UInt64;
  out AOutput: UInt64): Boolean;
begin
  Result := PawnIoHandleExecute(GDeviceHandle, AName, [AInput], 1, AOutput);
end;

function PawnIoLoadModuleOnHandle(AHandle: THandle; const AModulePath,
  AModuleName: string): Boolean;
var
  stream: TFileStream;
  blob: TBytes;
  returned: DWORD;
begin
  Result := False;
  GLastModuleName := AModuleName;
  if not FileExists(AModulePath) then
  begin
    PawnIoSetLoadFailure('检查模块', ERROR_FILE_NOT_FOUND);
    Exit;
  end;
  stream := TFileStream.Create(AModulePath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(blob, stream.Size);
    if stream.Size > 0 then
      stream.ReadBuffer(blob[0], stream.Size);
  finally
    stream.Free;
  end;
  Result := DeviceIoControl(
    AHandle,
    IOCTL_PIO_LOAD_BINARY,
    @blob[0],
    Length(blob),
    nil,
    0,
    returned,
    nil);
  if not Result then
    PawnIoSetLoadFailure('加载模块', 0);
end;

function PawnIoQueryMsrSupported: Boolean;
var
  regs: TCpuIdRegs;
begin
  if GMsrChecked then
    Exit(GMsrSupported);
  GMsrChecked := True;
  GMsrSupported := False;
  try
    CpuIdLeaf(1, regs);
    GMsrSupported := ((regs.Edx shr 5) and 1) <> 0;
  except
    GMsrSupported := False;
  end;
  Result := GMsrSupported;
end;

function PawnIoLoadModule(const AModulePath, AModuleName: string): Boolean;
begin
  Result := PawnIoLoadModuleOnHandle(GDeviceHandle, AModulePath, AModuleName);
end;

function PawnIoEnsureDriver: Boolean;
var
  sysPath: string;
  h: THandle;
begin
  if (GDeviceHandle <> INVALID_HANDLE_VALUE) or (GLpcHandle <> INVALID_HANDLE_VALUE) then
    Exit(True);
  if GInitFailed and GLpcInitFailed then
    Exit(False);

  h := PawnIoTryOpenDevice;
  if h <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(h);
    Exit(True);
  end;

  sysPath := AppBinDllPath(cPawnIoSysName);
  if not FileExists(sysPath) then
  begin
    PawnIoSetLoadFailure('检查驱动', ERROR_FILE_NOT_FOUND);
    Exit(False);
  end;
  if not PawnIoInstallDriver(sysPath) then
    Exit(False);
  if not PawnIoStartDriver then
    Exit(False);
  Result := PawnIoTryOpenDevice <> INVALID_HANDLE_VALUE;
  if not Result then
    PawnIoSetLoadFailure('打开设备', 0);
end;

function PawnIoEnsureLoaded: Boolean;
var
  moduleName, modulePath: string;
begin
  if GInitialized then
    Exit(True);
  if GInitFailed then
    Exit(False);
  if not PawnIoEnsureDriver then
  begin
    GInitFailed := True;
    Exit(False);
  end;

  GDeviceHandle := PawnIoTryOpenDevice;
  if GDeviceHandle = INVALID_HANDLE_VALUE then
  begin
    PawnIoSetLoadFailure('打开设备', 0);
    GInitFailed := True;
    Exit(False);
  end;

  moduleName := PawnIoSelectModuleName(GBackend);
  modulePath := AppBinDllPath(moduleName);
  if not PawnIoLoadModule(modulePath, moduleName) then
  begin
    PawnIoCloseDevice;
    GBackend := pbNone;
    GInitFailed := True;
    Exit(False);
  end;

  GLastLoadError := 0;
  GLastLoadStage := '';
  GInitialized := True;
  Result := True;
end;

function PawnIoAvailable: Boolean;
begin
  Result := PawnIoEnsureLoaded;
end;

function PawnIoIsMsrSupported: Boolean;
begin
  Result := PawnIoEnsureLoaded and PawnIoQueryMsrSupported and
    (GBackend in [pbIntelMsr, pbAmdFamily17, pbAmdFamily10, pbAmdFamily0F]);
end;

function PawnIoDeviceReadMsr(AIndex: DWORD; out AEax, AEdx: DWORD): Boolean;
var
  value: UInt64;
begin
  AEax := 0;
  AEdx := 0;
  Result := False;
  if not PawnIoExecuteOne('ioctl_read_msr', AIndex, value) then
    Exit;
  AEax := DWORD(value and $FFFFFFFF);
  AEdx := DWORD((value shr 32) and $FFFFFFFF);
  Result := True;
end;

function PawnIoReadMsr(AIndex: DWORD; out AEax, AEdx: DWORD): Boolean;
begin
  AEax := 0;
  AEdx := 0;
  Result := PawnIoEnsureLoaded and PawnIoDeviceReadMsr(AIndex, AEax, AEdx);
end;

function PawnIoReadMsrTx(AIndex: DWORD; AThreadAffinityMask: ULONG_PTR;
  out AEax, AEdx: DWORD): Boolean;
var
  hThread: THandle;
  oldMask: DWORD_PTR;
begin
  AEax := 0;
  AEdx := 0;
  Result := False;
  if not PawnIoEnsureLoaded then
    Exit;
  hThread := GetCurrentThread;
  oldMask := SetThreadAffinityMask(hThread, AThreadAffinityMask);
  if oldMask = 0 then
    Exit;
  try
    Result := PawnIoDeviceReadMsr(AIndex, AEax, AEdx);
  finally
    SetThreadAffinityMask(hThread, oldMask);
  end;
end;

procedure PawnIoCloseLpc;
begin
  if GLpcHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(GLpcHandle);
    GLpcHandle := INVALID_HANDLE_VALUE;
  end;
  GLpcInitialized := False;
end;

function PawnIoEnsureLpc: Boolean;
var
  modulePath: string;
begin
  if GLpcInitialized then
    Exit(True);
  if GLpcInitFailed then
    Exit(False);
  if not PawnIoEnsureDriver then
  begin
    GLpcInitFailed := True;
    Exit(False);
  end;

  GLpcHandle := PawnIoTryOpenDevice;
  if GLpcHandle = INVALID_HANDLE_VALUE then
  begin
    GLpcInitFailed := True;
    Exit(False);
  end;

  modulePath := AppBinDllPath('LpcIO.bin');
  if not PawnIoLoadModuleOnHandle(GLpcHandle, modulePath, 'LpcIO.bin') then
  begin
    PawnIoCloseLpc;
    GLpcInitFailed := True;
    Exit(False);
  end;
  GLpcInitialized := True;
  Result := True;
end;

function PawnIoLpcAvailable: Boolean;
begin
  Result := PawnIoEnsureLpc;
end;

function PawnIoLpcExecute0(const AName: AnsiString): Boolean;
begin
  Result := False;
  if not PawnIoEnsureLpc then
    Exit;
  Result := PawnIoHandleExecuteNoOut(GLpcHandle, AName, []);
end;

function PawnIoLpcExecute1(const AName: AnsiString; AInput: UInt64;
  out AOutput: UInt64): Boolean;
begin
  Result := False;
  AOutput := 0;
  if not PawnIoEnsureLpc then
    Exit;
  Result := PawnIoHandleExecute(GLpcHandle, AName, [AInput], 1, AOutput);
end;

function PawnIoLpcExecute2(const AName: AnsiString; AInput0, AInput1: UInt64): Boolean;
begin
  Result := False;
  if not PawnIoEnsureLpc then
    Exit;
  Result := PawnIoHandleExecuteNoOut(GLpcHandle, AName, [AInput0, AInput1]);
end;

function PawnIoLpcRun(const AName: AnsiString; const AInputs: array of UInt64): Boolean;
begin
  Result := False;
  if not PawnIoEnsureLpc then
    Exit;
  Result := PawnIoHandleExecuteNoOut(GLpcHandle, AName, AInputs);
end;

function PawnIoLpcPioInB(APort: Word; out AValue: Byte): Boolean;
var
  raw: UInt64;
begin
  AValue := 0;
  Result := False;
  if not PawnIoEnsureLpc then
    Exit;
  Result := PawnIoHandleExecute(GLpcHandle, 'ioctl_pio_inb', [UInt64(APort)], 1, raw);
  if Result then
    AValue := Byte(raw and $FF);
end;

function PawnIoLpcPioInB(APort: Word): Boolean;
var
  dummy: Byte;
begin
  Result := PawnIoLpcPioInB(APort, dummy);
end;

function PawnIoReadSmn(AOffset: DWORD; out AValue: DWORD): Boolean;
var
  value: UInt64;
begin
  AValue := 0;
  Result := False;
  if not PawnIoEnsureLoaded or (GBackend <> pbAmdFamily17) then
    Exit;
  if not PawnIoExecuteOne('ioctl_read_smn', AOffset, value) then
    Exit;
  AValue := DWORD(value);
  Result := True;
end;

procedure PawnIoShutdown;
begin
  PawnIoCloseLpc;
  PawnIoCloseDevice;
  GBackend := pbNone;
  GInitialized := False;
  GInitFailed := False;
  GLpcInitFailed := False;
  GLastLoadError := 0;
  GLastLoadStage := '';
  GLastModuleName := '';
end;

initialization
  GDeviceHandle := INVALID_HANDLE_VALUE;
  GLpcHandle := INVALID_HANDLE_VALUE;

finalization
  PawnIoShutdown;

end.
