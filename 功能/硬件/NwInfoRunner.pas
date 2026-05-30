unit NwInfoRunner;

{
  nwinfox86.exe 子进程封装：解析路径、拼装 CLI 参数、运行并捕获 stdout/stderr。
  libnw 未单独导出 API，故通过子进程调用（与 gnwinfo 一致）。

  CLI 完整说明见官方文档：
  https://a1ive.github.io/nwinfo/docs/#cli-nwinfo

  常用示例（文档原文）：
    nwinfox86.exe --format=json --output=report.json --cp=UTF8 --sys --disk
    nwinfox86.exe --pci=03
    nwinfox86.exe --format=html --output=report.html --net=active,phys,ipv4
}

interface

uses
  SysUtils;

const
  { 通用选项 }
  cNwInfoCpUtf8       = '--cp=UTF8';
  cNwInfoCpAnsi       = '--cp=ANSI';
  cNwInfoHuman        = '--human';
  cNwInfoHideSensitive = '--hide-sensitive';
  cNwInfoDebug        = '--debug';

  { 系统 / 硬件开关（无参） }
  cNwInfoOptSys       = '--sys';
  cNwInfoOptCpu       = '--cpu';
  cNwInfoOptBoard     = '--board';
  cNwInfoOptGpu       = '--gpu';
  cNwInfoOptUsb       = '--usb';
  cNwInfoOptBattery   = '--battery';
  cNwInfoOptAudio     = '--audio';
  cNwInfoOptPublicIp  = '--public-ip';

  { 输出段标记（用于 ARequiredMarker 校验） }
  cNwInfoMarkerSmbios = 'SMBIOS:';
  cNwInfoMarkerCpu    = 'CPUID:';
  cNwInfoMarkerNet    = 'Network:';
  cNwInfoMarkerSensors = 'Sensors:';

  { 本项目预设 }
  cNwInfoArgsMem = '--cp=UTF8 --sys --smbios=16,17';
  cNwInfoArgsCpu = '--cp=UTF8 --cpu';
  cNwInfoArgsCpuSensors = '--cp=UTF8 --temp-unit=C --sensors=CPU';
  cNwInfoArgsGpu = '--cp=UTF8 --gpu';
  cNwInfoArgsGpuSensors = '--cp=UTF8 --temp-unit=C --sensors=GPU';
  cNwInfoArgsNet = '--cp=UTF8 --net=active,phys';

function NwInfoJoinArgs(const AArgs: array of string): string;
function NwInfoOptFormat(const AFormat: string): string;
function NwInfoOptOutput(const AFile: string): string;
function NwInfoOptDriver(const AName: string): string;
function NwInfoOptSmbios(const ATypes: string): string;
function NwInfoOptNet(const AFlags: string): string;
function NwInfoOptDisk(const AFlags: string): string;
function NwInfoOptPci(const AClasses: string): string;
function NwInfoOptSensors(const ASources: string): string;

function NwInfoResolveExe(out AExePath, AWorkDir: string): Boolean;
function NwInfoRunCapture(const AArgs: string; out AOutput: string;
  const ARequiredMarker: string = ''): Boolean;

implementation

uses
  Windows, Classes, SyncObjs;

var
  GNwInfoRunLock: TCriticalSection;
  GResolvedExePath: string;
  GResolvedWorkDir: string;
  GResolvedExeValid: Boolean;

function NwInfoJoinArgs(const AArgs: array of string): string;
var
  i: Integer;
  s: string;
begin
  Result := '';
  for i := Low(AArgs) to High(AArgs) do
  begin
    s := Trim(AArgs[i]);
    if s = '' then
      Continue;
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + s;
  end;
end;

function NwInfoOptFormat(const AFormat: string): string;
begin
  Result := '--format=' + AFormat;
end;

function NwInfoOptOutput(const AFile: string): string;
begin
  Result := '--output=' + AFile;
end;

function NwInfoOptDriver(const AName: string): string;
begin
  Result := '--driver=' + AName;
end;

function NwInfoOptSmbios(const ATypes: string): string;
begin
  if Trim(ATypes) = '' then
    Result := '--smbios'
  else
    Result := '--smbios=' + ATypes;
end;

function NwInfoOptNet(const AFlags: string): string;
begin
  if Trim(AFlags) = '' then
    Result := '--net'
  else
    Result := '--net=' + AFlags;
end;

function NwInfoOptDisk(const AFlags: string): string;
begin
  if Trim(AFlags) = '' then
    Result := '--disk'
  else
    Result := '--disk=' + AFlags;
end;

function NwInfoOptPci(const AClasses: string): string;
begin
  if Trim(AClasses) = '' then
    Result := '--pci'
  else
    Result := '--pci=' + AClasses;
end;

function NwInfoOptSensors(const ASources: string): string;
begin
  if Trim(ASources) = '' then
    Result := '--sensors'
  else
    Result := '--sensors=' + ASources;
end;

function NwInfoAppendPipeChunk(const AOutput: string; const AChunk: AnsiString): string;
begin
  if Length(AChunk) = 0 then
    Result := AOutput
  else
    Result := AOutput + UTF8ToString(UTF8String(AChunk));
end;

function NwInfoAppExeDir: string;
var
  n: DWORD;
begin
  SetLength(Result, MAX_PATH);
  n := GetModuleFileName(0, PChar(Result), MAX_PATH);
  SetLength(Result, n);
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(Result));
end;

function NwInfoResolveExe(out AExePath, AWorkDir: string): Boolean;
const
  REL_PATHS: array[0..2] of string = (
    'NwInfo\nwinfox86.exe',
    '..\Resource\NwInfo\nwinfox86.exe',
    'Resource\NwInfo\nwinfox86.exe'
  );
var
  i: Integer;
  p: string;
begin
  if GResolvedExeValid then
  begin
    AExePath := GResolvedExePath;
    AWorkDir := GResolvedWorkDir;
    Exit(True);
  end;
  Result := False;
  AExePath := '';
  AWorkDir := '';
  for i := Low(REL_PATHS) to High(REL_PATHS) do
  begin
    p := NwInfoAppExeDir + REL_PATHS[i];
    if FileExists(p) then
    begin
      AExePath := p;
      AWorkDir := IncludeTrailingPathDelimiter(ExtractFilePath(p));
      GResolvedExePath := AExePath;
      GResolvedWorkDir := AWorkDir;
      GResolvedExeValid := True;
      Result := True;
      Exit;
    end;
  end;
end;

function NwInfoRunCapture(const AArgs: string; out AOutput: string;
  const ARequiredMarker: string): Boolean;
var
  exePath, workDir, cmdLine: string;
  sa: TSecurityAttributes;
  hReadPipe, hWritePipe, hNulIn: THandle;
  si: TStartupInfo;
  pi: TProcessInformation;
  startupDir: array[0..MAX_PATH] of Char;
  buf: array[0..8191] of AnsiChar;
  bytesRead: DWORD;
  chunk: AnsiString;
  exitCode, waitRc: DWORD;
  markerPos: Integer;
begin
  Result := False;
  AOutput := '';
  hReadPipe := 0;
  hWritePipe := 0;
  if not NwInfoResolveExe(exePath, workDir) then
    Exit;
  GNwInfoRunLock.Enter;
  try
  sa.nLength := SizeOf(sa);
  sa.bInheritHandle := True;
  sa.lpSecurityDescriptor := nil;
  if not CreatePipe(hReadPipe, hWritePipe, @sa, 0) then
    Exit;
  hNulIn := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ, @sa, OPEN_EXISTING, 0, 0);
  if hNulIn = INVALID_HANDLE_VALUE then
    hNulIn := 0;
  try
    FillChar(si, SizeOf(si), 0);
    si.cb := SizeOf(si);
    si.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    si.wShowWindow := SW_HIDE;
    si.hStdOutput := hWritePipe;
    si.hStdError := hWritePipe;
    if hNulIn <> 0 then
      si.hStdInput := hNulIn
    else
      si.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(pi, SizeOf(pi), 0);
    cmdLine := Format('"%s" %s', [exePath, AArgs]);
    FillChar(startupDir, SizeOf(startupDir), 0);
    StrLCopy(startupDir, PChar(workDir), MAX_PATH - 1);
    if not CreateProcess(nil, PChar(cmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, startupDir,
      si, pi) then
    begin
      Exit;
    end;
    CloseHandle(hWritePipe);
    hWritePipe := 0;
    while True do
    begin
      bytesRead := 0;
      if ReadFile(hReadPipe, buf, SizeOf(buf), bytesRead, nil) and (bytesRead > 0) then
      begin
        SetLength(chunk, bytesRead);
        Move(buf[0], chunk[1], bytesRead);
        AOutput := NwInfoAppendPipeChunk(AOutput, chunk);
      end
      else
      begin
        waitRc := WaitForSingleObject(pi.hProcess, 50);
        if waitRc = WAIT_OBJECT_0 then
          Break;
      end;
    end;
    while ReadFile(hReadPipe, buf, SizeOf(buf), bytesRead, nil) and (bytesRead > 0) do
    begin
      SetLength(chunk, bytesRead);
      Move(buf[0], chunk[1], bytesRead);
      AOutput := NwInfoAppendPipeChunk(AOutput, chunk);
    end;
    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, exitCode);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    if ARequiredMarker <> '' then
    begin
      markerPos := Pos(ARequiredMarker, AOutput);
      Result := markerPos > 0;
    end
    else
      Result := AOutput <> '';
  finally
    if hWritePipe <> 0 then
      CloseHandle(hWritePipe);
    if hReadPipe <> 0 then
      CloseHandle(hReadPipe);
    if hNulIn <> 0 then
      CloseHandle(hNulIn);
  end;
  finally
    GNwInfoRunLock.Leave;
  end;
end;

initialization
  GNwInfoRunLock := TCriticalSection.Create;

finalization
  FreeAndNil(GNwInfoRunLock);

end.
