unit PawnIoClient;

{
  PawnIO IOCTL 客户端：DeviceIoControl 加载 *.bin 模块并执行 MSR/LpcIO 函数。
  32 位进程直连 x64 内核驱动，不依赖 PawnIOLib.dll。
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
function PawnIoLpcAvailable: Boolean;
function PawnIoLpcExecute0(const AName: AnsiString): Boolean;
function PawnIoLpcExecute1(const AName: AnsiString; AInput: UInt64;
  out AOutput: UInt64): Boolean;
function PawnIoLpcExecute2(const AName: AnsiString; AInput0, AInput1: UInt64): Boolean;
function PawnIoLpcRun(const AName: AnsiString; const AInputs: array of UInt64): Boolean;
function PawnIoLpcPioInB(APort: Word): Boolean; overload;
function PawnIoLpcPioInB(APort: Word; out AValue: Byte): Boolean; overload;
procedure PawnIoClientShutdown;

implementation

uses
  SysUtils, Classes, Math, AppPaths, PawnIoDriver, CpuIdHelper, SyncObjs;

const
  cPawnIoFnNameLen = 32;
  cPawnIoDeviceType = DWORD(41394) shl 16;
  IOCTL_PIO_LOAD_BINARY = cPawnIoDeviceType or (DWORD($821) shl 2);
  IOCTL_PIO_EXECUTE_FN = cPawnIoDeviceType or (DWORD($841) shl 2);
  ERROR_FILE_NOT_FOUND = 2;
  ERROR_NOT_SUPPORTED = 50;
  ERROR_ACCESS_DENIED = 5;
  ERROR_SERVICE_EXISTS = 1073;
  ERROR_SERVICE_ALREADY_RUNNING = 1056;
  ERROR_SERVICE_MARKED_FOR_DELETE = 1072;

var
  GMsrHandle: THandle;
  GLpcHandle: THandle;
  GBackend: TPawnIoBackend;
  GMsrInitialized: Boolean;
  GMsrInitFailed: Boolean;
  GLpcInitialized: Boolean;
  GLpcInitFailed: Boolean;
  GMsrSupported: Boolean;
  GMsrChecked: Boolean;
  GLastLoadError: DWORD;
  GLastLoadStage: string;
  GLastModuleName: string;
  GLastDevicePath: string;
  GPawnIoLock: TCriticalSection;

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

function PawnIoWin32ErrorName(AError: DWORD): string;
begin
  case AError of
    ERROR_FILE_NOT_FOUND: Result := 'ERROR_FILE_NOT_FOUND';
    ERROR_ACCESS_DENIED: Result := 'ERROR_ACCESS_DENIED';
    ERROR_NOT_SUPPORTED: Result := 'ERROR_NOT_SUPPORTED';
    ERROR_SERVICE_EXISTS: Result := 'ERROR_SERVICE_EXISTS';
    ERROR_SERVICE_ALREADY_RUNNING: Result := 'ERROR_SERVICE_ALREADY_RUNNING';
    ERROR_SERVICE_MARKED_FOR_DELETE: Result := 'ERROR_SERVICE_MARKED_FOR_DELETE';
  else
    Result := '';
  end;
end;

function PawnIoFormatWin32Error(AError: DWORD): string;
var
  sysMsg, codeName: string;
begin
  if AError = 0 then
    Exit('未知错误（错误码 0）');
  sysMsg := SysErrorMessage(AError);
  if sysMsg = '' then
    sysMsg := '未知系统错误';
  codeName := PawnIoWin32ErrorName(AError);
  if codeName <> '' then
    Result := Format('%s（%s，%d）', [sysMsg, codeName, AError])
  else
    Result := Format('%s（Win32 错误 %d）', [sysMsg, AError]);
end;

function PawnIoLoadErrorHint(AError: DWORD): string;
var
  devPath: string;
begin
  if (GLastLoadStage = '恢复驱动') or (GLastLoadStage = '等待服务删除') or
    (AError = ERROR_SERVICE_MARKED_FOR_DELETE) or PawnIoDriverNeedsReboot then
    Exit(
      'PawnIO 服务处于「待删除」僵死状态（多为旧版退出时强删驱动所致）。' +
      '请以管理员打开 CMD 执行 sc delete PawnIO 后重启一次；重启后由 QDesktop 自动重装，之后不会再僵死');

  case AError of
    ERROR_FILE_NOT_FOUND:
      begin
        if GLastLoadStage = '检查驱动' then
          Result := Format('Bin\PawnIO.sys 未找到（查找目录：%s）', [AppBinDirectory])
        else if (GLastLoadStage = '打开设备') or (GLastLoadStage = '安装驱动') then
        begin
          if GLastDevicePath <> '' then
            devPath := GLastDevicePath
          else
            devPath := '\\.\PawnIO';
          if PawnIoDriverNeedsReboot or PawnIoDriverServiceDeletePending then
            Result :=
              'PawnIO 服务处于僵死/待删除状态（旧版 CreateService 直挂 .sys 所致）。' +
              '请以管理员执行 sc delete PawnIO 后重启一次，重启后由 QDesktop 经 INF 自动安装'
          else if PawnIoDriverDeviceZombieSuspected then
            Result :=
              'PawnIO 服务显示 RUNNING 但设备节点不存在；' +
              '可能原因：1) 内核隔离（HVCI）拦截；2) 驱动签名被拒绝；3) 僵死服务未清除。' +
              '请关闭内核隔离，或以管理员执行 sc delete PawnIO 后重启一次'
          else
            Result := Format(
              'CreateFile("%s") 失败：内核设备对象不存在，PawnIO 驱动未加载或未成功创建设备节点；' +
              '若首次使用请用管理员权限运行一次，若已安装请检查服务 PawnIO 是否正在运行、驱动是否被安全软件或内核隔离拦截',
              [devPath]);
        end
        else
          Result := GLastModuleName + ' 未找到';
      end;
    ERROR_NOT_SUPPORTED:
      if GLastModuleName = 'IntelMSR.bin' then
        Result := '当前 PawnIO 驱动禁用了通用 MSR 模块'
      else
        Result := GLastModuleName + ' 与当前 PawnIO 驱动不兼容';
    ERROR_ACCESS_DENIED:
      if (GLastLoadStage = '打开设备') or (GLastLoadStage = '安装驱动') then
      begin
        if GLastDevicePath <> '' then
          devPath := GLastDevicePath
        else
          devPath := cPawnIoDevicePath;
        Result := Format('CreateFile("%s") 失败：当前进程无权打开 PawnIO 设备', [devPath]);
      end
      else
        Result := '需要管理员权限安装或启动 PawnIO 驱动服务';
  else
    if GLastLoadStage = '打开设备' then
    begin
      if GLastDevicePath <> '' then
        devPath := GLastDevicePath
      else
        devPath := '\\.\PawnIO';
      Result := Format('CreateFile("%s") 失败', [devPath]);
    end
    else
      Result := GLastLoadStage + ' 失败';
  end;
end;

function PawnIoLoadFailureDetail: string;
var
  hint, win32: string;
begin
  if (GLastLoadStage = '') and (GLastLoadError = 0) then
    Exit('PawnIO 不可用');

  hint := PawnIoLoadErrorHint(GLastLoadError);
  win32 := PawnIoFormatWin32Error(GLastLoadError);

  if GLastLoadStage <> '' then
    Result := Format('PawnIO 不可用（%s）：%s；%s',
      [GLastLoadStage, hint, win32])
  else
    Result := Format('PawnIO 不可用：%s；%s', [hint, win32]);
end;

function PawnIoBackend: TPawnIoBackend;
begin
  Result := GBackend;
end;

procedure PawnIoCloseMsrHandle;
begin
  if GMsrHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(GMsrHandle);
    GMsrHandle := INVALID_HANDLE_VALUE;
  end;
end;

procedure PawnIoCloseLpcHandle;
begin
  if GLpcHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(GLpcHandle);
    GLpcHandle := INVALID_HANDLE_VALUE;
  end;
  GLpcInitialized := False;
end;

function PawnIoOpenDevice: THandle;
begin
  Result := PawnIoDriverTryOpenDevice(GLastDevicePath);
  if Result = INVALID_HANDLE_VALUE then
    GLastLoadError := PawnIoDriverLastError;
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

  GPawnIoLock.Enter;
  try
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
  finally
    GPawnIoLock.Leave;
  end;
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

  GPawnIoLock.Enter;
  try
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
  finally
    GPawnIoLock.Leave;
  end;
end;

function PawnIoExecuteOne(const AName: AnsiString; AInput: UInt64;
  out AOutput: UInt64): Boolean;
begin
  Result := PawnIoHandleExecute(GMsrHandle, AName, [AInput], 1, AOutput);
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
  GPawnIoLock.Enter;
  try
    Result := DeviceIoControl(
      AHandle,
      IOCTL_PIO_LOAD_BINARY,
      @blob[0],
      Length(blob),
      nil,
      0,
      returned,
      nil);
  finally
    GPawnIoLock.Leave;
  end;
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

function PawnIoEnsureDriver: Boolean;
var
  h: THandle;
begin
  if (GMsrHandle <> INVALID_HANDLE_VALUE) or (GLpcHandle <> INVALID_HANDLE_VALUE) then
    Exit(True);
  if GMsrInitFailed and GLpcInitFailed then
    Exit(False);

  h := PawnIoOpenDevice;
  if h <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(h);
    Exit(True);
  end;

  if not PawnIoDriverEnsureRunning then
  begin
    PawnIoSetLoadFailure(PawnIoDriverLastStage, PawnIoDriverLastError);
    Exit(False);
  end;

  h := PawnIoOpenDevice;
  Result := h <> INVALID_HANDLE_VALUE;
  if Result then
    CloseHandle(h)
  else
    PawnIoSetLoadFailure('打开设备', GLastLoadError);
end;

function PawnIoEnsureMsrLoaded: Boolean;
var
  moduleName, modulePath: string;
begin
  if GMsrInitialized then
    Exit(True);
  if GMsrInitFailed then
    Exit(False);
  if not PawnIoEnsureDriver then
  begin
    GMsrInitFailed := True;
    Exit(False);
  end;

  GMsrHandle := PawnIoOpenDevice;
  if GMsrHandle = INVALID_HANDLE_VALUE then
  begin
    PawnIoSetLoadFailure('打开设备', GLastLoadError);
    GMsrInitFailed := True;
    Exit(False);
  end;

  moduleName := PawnIoSelectModuleName(GBackend);
  modulePath := AppBinDllPath(moduleName);
  if not PawnIoLoadModuleOnHandle(GMsrHandle, modulePath, moduleName) then
  begin
    PawnIoCloseMsrHandle;
    GBackend := pbNone;
    GMsrInitFailed := True;
    Exit(False);
  end;

  GLastLoadError := 0;
  GLastLoadStage := '';
  GLastDevicePath := '';
  GMsrInitialized := True;
  Result := True;
end;

function PawnIoAvailable: Boolean;
begin
  Result := PawnIoEnsureMsrLoaded;
end;

function PawnIoIsMsrSupported: Boolean;
begin
  Result := PawnIoEnsureMsrLoaded and PawnIoQueryMsrSupported and
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
  Result := PawnIoEnsureMsrLoaded and PawnIoDeviceReadMsr(AIndex, AEax, AEdx);
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
  if not PawnIoEnsureMsrLoaded then
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

  GLpcHandle := PawnIoOpenDevice;
  if GLpcHandle = INVALID_HANDLE_VALUE then
  begin
    GLpcInitFailed := True;
    Exit(False);
  end;

  modulePath := AppBinDllPath('LpcIO.bin');
  if not PawnIoLoadModuleOnHandle(GLpcHandle, modulePath, 'LpcIO.bin') then
  begin
    PawnIoCloseLpcHandle;
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
  if not PawnIoEnsureMsrLoaded or (GBackend <> pbAmdFamily17) then
    Exit;
  if not PawnIoExecuteOne('ioctl_read_smn', AOffset, value) then
    Exit;
  AValue := DWORD(value);
  Result := True;
end;

procedure PawnIoClientShutdown;
begin
  PawnIoCloseLpcHandle;
  PawnIoCloseMsrHandle;
  GBackend := pbNone;
  GMsrInitialized := False;
  GMsrInitFailed := False;
  GLpcInitFailed := False;
  GLastLoadError := 0;
  GLastLoadStage := '';
  GLastModuleName := '';
  GLastDevicePath := '';
  PawnIoDriverUnloadIfOwned;
end;

initialization
  GMsrHandle := INVALID_HANDLE_VALUE;
  GLpcHandle := INVALID_HANDLE_VALUE;
  GPawnIoLock := TCriticalSection.Create;

finalization
  PawnIoClientShutdown;
  FreeAndNil(GPawnIoLock);

end.
