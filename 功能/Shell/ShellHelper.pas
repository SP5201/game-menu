unit ShellHelper;

interface

uses
  Classes,
  SysUtils,
  Windows,
  CommDlg,
  ShlObj,
  ShellAPI;

function ResolveSystem32ExePath(const AExeName: string): string;
function ResolveSystemBinaryPathForOsArchitecture(const AExeName: string): string;
function ResolveSystem32MscDocumentPath(const AMscFileName: string): string;
function OpenFileDialogSingle(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; out AFilePath: string): Boolean;
function OpenFileDialogMulti(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; AFiles: TStrings): Boolean;
function SaveFileDialog(const AOwnerWnd: Windows.HWND; const ATitle, AFilter, ADefaultFileName,
  AInitialDir, ADefaultExt: string; out AFilePath: string): Boolean;
function ShellExecuteDefaultVerb(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString;
  const AShowCmd: Integer): Boolean;
function ShellExecuteRunAs(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString;
  const AShowCmd: Integer): Boolean;
function ShellOpenFolderAndSelectPath(hwnd: Windows.HWND; const FilePath: UnicodeString): Boolean;
function ShellCopyPathToClipboard(const APath: UnicodeString): Boolean;
function ShellDeletePath(hwnd: Windows.HWND; const FilePath: UnicodeString): Boolean;
procedure RestartWindowsExplorer;
procedure RestartWindowsExplorerAsync;

function IsRunningUnderWow64: Boolean;

/// <summary>WOW64 下 System32 路径在仅 64 位文件存在时改用 Sysnative（供 ExtractIcon 等）。</summary>
function NormalizeSystem32PathForIcon(const APath: string): string;

/// <summary>WOW64 下执行路径的 Sysnative 纠正（目录不误判为缺失）。</summary>
function NormalizeSystem32PathForExecute(const APath: UnicodeString): UnicodeString;

/// <summary>%WinDir%\explorer.exe；32 位进程 CreateProcess 时需 Wow64DisableWow64FsRedirection。</summary>
function ResolveWindowsExplorerPath: UnicodeString;

/// <summary>32 位进程在 WOW64 下纠正 Program Files(x86) → ProgramW6432（目标存在时）。</summary>
function NormalizeProgramFilesPathForWow64(const APath: string): string;

function ResolveItemIconPath(const AIconPath: string): string;

function BrowseForFolderPath(const ATitle: string; const AOwnerWnd: Windows.HWND; out AFolderPath: string): Boolean;

implementation

uses
  ActiveX, ComObj, CommCtrl, AppConfig, TlHelp32;

function OpenFileDialogSingle(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; out AFilePath: string): Boolean;
var
  ofn: TOpenFilenameW;
  fileBuf: array[0..MAX_PATH * 4] of WideChar;
begin
  Result := False;
  AFilePath := '';
  FillChar(ofn, SizeOf(ofn), 0);
  FillChar(fileBuf, SizeOf(fileBuf), 0);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := AOwnerWnd;
  ofn.lpstrTitle := PWideChar(ATitle);
  ofn.lpstrFilter := PWideChar(StringReplace(AFilter, '|', #0, [rfReplaceAll]) + #0#0);
  ofn.lpstrFile := @fileBuf[0];
  ofn.nMaxFile := Length(fileBuf);
  ofn.Flags := OFN_EXPLORER or OFN_FILEMUSTEXIST or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY or OFN_ENABLESIZING;
  if not GetOpenFileNameW(ofn) then
    Exit;
  AFilePath := fileBuf;
  Result := AFilePath <> '';
end;

function OpenFileDialogMulti(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; AFiles: TStrings): Boolean;
var
  ofn: TOpenFilenameW;
  fileBuf: array[0..65535] of WideChar;
  baseDir: string;
  p: PWideChar;
  item: string;
begin
  Result := False;
  if AFiles = nil then
    Exit;
  AFiles.Clear;
  FillChar(ofn, SizeOf(ofn), 0);
  FillChar(fileBuf, SizeOf(fileBuf), 0);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := AOwnerWnd;
  ofn.lpstrTitle := PWideChar(ATitle);
  ofn.lpstrFilter := PWideChar(StringReplace(AFilter, '|', #0, [rfReplaceAll]) + #0#0);
  ofn.lpstrFile := @fileBuf[0];
  ofn.nMaxFile := Length(fileBuf);
  ofn.Flags := OFN_EXPLORER or OFN_ALLOWMULTISELECT or OFN_FILEMUSTEXIST or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY or OFN_ENABLESIZING;
  if not GetOpenFileNameW(ofn) then
    Exit;

  baseDir := fileBuf;
  p := @fileBuf[Length(baseDir) + 1];
  if p^ = #0 then
    AFiles.Add(baseDir)
  else
  begin
    while p^ <> #0 do
    begin
      item := p;
      AFiles.Add(IncludeTrailingPathDelimiter(baseDir) + item);
      Inc(p, Length(item) + 1);
    end;
  end;
  Result := AFiles.Count > 0;
end;

function SaveFileDialog(const AOwnerWnd: Windows.HWND; const ATitle, AFilter, ADefaultFileName,
  AInitialDir, ADefaultExt: string; out AFilePath: string): Boolean;
var
  ofn: TOpenFilenameW;
  fileBuf: array[0..MAX_PATH * 4] of WideChar;
begin
  Result := False;
  AFilePath := '';
  FillChar(ofn, SizeOf(ofn), 0);
  FillChar(fileBuf, SizeOf(fileBuf), 0);
  if ADefaultFileName <> '' then
    StrPLCopy(fileBuf, ADefaultFileName, Length(fileBuf) - 1);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := AOwnerWnd;
  ofn.lpstrTitle := PWideChar(ATitle);
  ofn.lpstrFilter := PWideChar(StringReplace(AFilter, '|', #0, [rfReplaceAll]) + #0#0);
  ofn.lpstrFile := @fileBuf[0];
  ofn.nMaxFile := Length(fileBuf);
  if AInitialDir <> '' then
    ofn.lpstrInitialDir := PWideChar(AInitialDir);
  if ADefaultExt <> '' then
    ofn.lpstrDefExt := PWideChar(ADefaultExt);
  ofn.Flags := OFN_EXPLORER or OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST or
    OFN_HIDEREADONLY or OFN_ENABLESIZING;
  if not GetSaveFileNameW(ofn) then
    Exit;
  AFilePath := fileBuf;
  Result := AFilePath <> '';
end;


const
  cShellTaskbarGoneTimeoutMs = 3000;
  cShellTaskbarReadyTimeoutMs = 15000; // 正常情况下 1-2 秒内即可就绪
  cShellTaskbarPollIntervalMs = 50;
  cShellTaskbarStablePollCount = 2;

function GetTickCount64: UInt64; stdcall;
  external 'kernel32.dll' name 'GetTickCount64';

// 获取当前任务栏句柄
function GetShellTaskbarHwnd: Windows.HWND;
begin
  Result := FindWindow('Shell_TrayWnd', nil);
end;

function NormalizeShellShowCmd(const AShowCmd: Integer): Integer;
begin
  case AShowCmd of
    SW_SHOWNORMAL, SW_SHOWMINIMIZED, SW_SHOWMAXIMIZED:
      Result := AShowCmd;
  else
    Result := SW_SHOWNORMAL;
  end;
end;

function EnumExplorerProcessExists: Boolean;
var
  Snapshot: THandle;
  Entry: TProcessEntry32W;
begin
  Result := False;
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snapshot = INVALID_HANDLE_VALUE then
    Exit;
  try
    FillChar(Entry, SizeOf(Entry), 0);
    Entry.dwSize := SizeOf(Entry);
    if Process32FirstW(Snapshot, Entry) then
    repeat
      if SameText(UnicodeString(Entry.szExeFile), 'explorer.exe') then
        Exit(True);
    until not Process32NextW(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

function TerminateAllExplorerProcesses: Boolean;
var
  Snapshot: THandle;
  Entry: TProcessEntry32W;
  hProcess: THandle;
  foundAny: Boolean;
begin
  Result := True;
  foundAny := False;
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snapshot = INVALID_HANDLE_VALUE then
    Exit(False);
  try
    FillChar(Entry, SizeOf(Entry), 0);
    Entry.dwSize := SizeOf(Entry);
    if Process32FirstW(Snapshot, Entry) then
    repeat
      if SameText(UnicodeString(Entry.szExeFile), 'explorer.exe') then
      begin
        foundAny := True;
        hProcess := OpenProcess(PROCESS_TERMINATE, False, Entry.th32ProcessID);
        if hProcess <> 0 then
        try
          if not TerminateProcess(hProcess, 1) then
            Result := False;
        finally
          CloseHandle(hProcess);
        end
        else
          Result := False;
      end;
    until not Process32NextW(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
  if not foundAny then
    Result := True;
end;

{ 1. 毫秒级强杀函数 }
function KillExplorerProcesses: Boolean;
const
  WM_USER_EXITEXPLORER = $0400 + 24; // 微软官方外壳优雅退出消息 (比老旧的 500 命令更兼容 Win10/Win11)
  cExplorerGracefulExitWaitMs = 50;  // 仅给一次轮询机会，不等待优雅退出
  cExplorerProcessGoneTimeoutMs = 1000;
var
  hTaskbar: Windows.HWND;
  t0: UInt64;
begin
  hTaskbar := GetShellTaskbarHwnd;

  // 第一步：尝试发送优雅退出消息
  if hTaskbar <> Windows.HWND(0) then
  begin
    PostMessage(hTaskbar, WM_USER_EXITEXPLORER, 0, 0);

    t0 := GetTickCount64;
    while GetTickCount64 - t0 < cExplorerGracefulExitWaitMs do
    begin
      if GetShellTaskbarHwnd = Windows.HWND(0) then
        Break;
      Sleep(cShellTaskbarPollIntervalMs);
    end;
  end;

  // 第二步：Win10/11 每个文件夹窗口可能是独立 explorer 进程，须全部清掉
  Result := TerminateAllExplorerProcesses;

  t0 := GetTickCount64;
  while EnumExplorerProcessExists and (GetTickCount64 - t0 < cExplorerProcessGoneTimeoutMs) do
    Sleep(cShellTaskbarPollIntervalMs);
  Result := Result and not EnumExplorerProcessExists;
end;

{ 2. 瞬间唤醒全新外壳 }
function StartWindowsExplorerShell: Boolean;
type
  TWow64DisableWow64FsRedirection = function(var OldValue: Pointer): BOOL; stdcall;
var
  Kernel: HMODULE;
  DisableWow64: TWow64DisableWow64FsRedirection;
  RevertWow64: TWow64DisableWow64FsRedirection;
  OldRedir: Pointer;
  RedirDisabled: Boolean;
begin
  // 初始化变量以消除 W1036 编译器警告
  Kernel := 0;
  RedirDisabled := False;
  OldRedir := nil;

  // 如果是 32 位程序拉起 64 位系统外壳，必须临时关闭文件系统重定向，防止产生空间污染导致任务栏加载慢
  if IsRunningUnderWow64 then
  begin
    Kernel := GetModuleHandle('kernel32.dll');
    if Kernel <> 0 then
    begin
      @DisableWow64 := GetProcAddress(Kernel, 'Wow64DisableWow64FsRedirection');
      if Assigned(DisableWow64) then
        RedirDisabled := DisableWow64(OldRedir);
    end;
  end;

  try
    // 严禁通过 CreateProcess 传绝对路径拉起，否则会被 Windows 当作普通文件夹拉起并在后台挂起 30 秒！
    // 纯净的 WinExec('explorer.exe') 会被内核直接识别为“当前无桌面外壳，使其作为 Shell 启动”
    Result := WinExec('explorer.exe', SW_SHOWNORMAL) > 31;
  finally
    if RedirDisabled and (Kernel <> 0) then
    begin
      @RevertWow64 := GetProcAddress(Kernel, 'Wow64RevertWow64FsRedirection');
      if Assigned(RevertWow64) then
        RevertWow64(OldRedir);
    end;
  end;
end;

function IsTaskbarWindowReady(hTaskbar: Windows.HWND): Boolean;
var
  rc: TRect;
begin
  Result := False;
  if (hTaskbar = Windows.HWND(0)) or (not IsWindow(hTaskbar)) or (not IsWindowVisible(hTaskbar)) then
    Exit;
  if not GetWindowRect(hTaskbar, rc) then
    Exit;
  Result := (rc.Right > rc.Left) and (rc.Bottom > rc.Top);
end;

function WaitForShellTaskbarGone(ATimeoutMs: Cardinal): Boolean;
var
  t0: UInt64;
begin
  t0 := GetTickCount64;
  while GetTickCount64 - t0 < ATimeoutMs do
  begin
    if GetShellTaskbarHwnd = Windows.HWND(0) then
      Exit(True);
    Sleep(cShellTaskbarPollIntervalMs);
  end;
  Result := (GetShellTaskbarHwnd = Windows.HWND(0));
end;

function WaitForNewShellTaskbarReady(AOldHwnd: Windows.HWND; ATimeoutMs: Cardinal): Boolean;
var
  t0: UInt64;
  hTaskbar: Windows.HWND;
  stableCount: Integer;
begin
  Result := False;
  stableCount := 0;
  t0 := GetTickCount64;
  while GetTickCount64 - t0 < ATimeoutMs do
  begin
    hTaskbar := GetShellTaskbarHwnd;
    if (hTaskbar <> Windows.HWND(0)) and (hTaskbar <> AOldHwnd) and IsTaskbarWindowReady(hTaskbar) then
    begin
      Inc(stableCount);
      if stableCount >= cShellTaskbarStablePollCount then
        Exit(True);
    end
    else
      stableCount := 0;
    Sleep(cShellTaskbarPollIntervalMs);
  end;
end;

procedure RestartWindowsExplorer;
var
  oldTaskbar: Windows.HWND;
begin
  oldTaskbar := GetShellTaskbarHwnd;
  KillExplorerProcesses;
  WaitForShellTaskbarGone(cShellTaskbarGoneTimeoutMs);
  StartWindowsExplorerShell;
  WaitForNewShellTaskbarReady(oldTaskbar, cShellTaskbarReadyTimeoutMs);
end;

procedure RestartWindowsExplorerAsync;
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      RestartWindowsExplorer;
    end
  ).Start;
end;

{ 3. 标准 Shell 函数 保持实现不变 }

function ShellExecuteDefaultVerb(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString;
  const AShowCmd: Integer): Boolean;
var
  sei: TShellExecuteInfo;
  execPath: UnicodeString;
  showCmd: Integer;
begin
  Result := False;
  if FilePath = '' then
    Exit;
  showCmd := NormalizeShellShowCmd(AShowCmd);
  execPath := NormalizeSystem32PathForExecute(FilePath);
  ZeroMemory(@sei, SizeOf(sei));
  sei.cbSize := SizeOf(sei);
  sei.fMask := SEE_MASK_DEFAULT;
  sei.Wnd := hwnd;
  sei.lpVerb := nil;
  sei.lpFile := PWideChar(execPath);
  if Parameters <> '' then
    sei.lpParameters := PWideChar(Parameters);
  if WorkingDir <> '' then
    sei.lpDirectory := PWideChar(WorkingDir);
  sei.nShow := showCmd;
  Result := ShellExecuteEx(@sei);
end;

function ShellExecuteRunAs(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString;
  const AShowCmd: Integer): Boolean;
var
  execPath: UnicodeString;
  showCmd: Integer;
begin
  Result := False;
  if FilePath = '' then
    Exit;
  showCmd := NormalizeShellShowCmd(AShowCmd);
  execPath := NormalizeSystem32PathForExecute(FilePath);
  Result := ShellExecuteW(hwnd, 'runas', PWideChar(execPath), PWideChar(Parameters), PWideChar(WorkingDir), showCmd) > 32;
end;

function ShellOpenFolderAndSelectPath(hwnd: Windows.HWND; const FilePath: UnicodeString): Boolean;
var
  Params: UnicodeString;
begin
  Result := False;
  if (FilePath = '') or not FileExists(FilePath) or DirectoryExists(FilePath) then
    Exit;
  Params := '/select,' + FilePath;
  Result := ShellExecuteW(hwnd, nil, 'explorer.exe', PWideChar(Params), nil, SW_SHOWNORMAL) > 32;
end;

function ShellCopyPathToClipboard(const APath: UnicodeString): Boolean;
var
  Drop: ^TDropFiles;
  buf: Pointer;
  bufSize, offset, pathLen: Integer;
  hDrop, hEffect: HGLOBAL;
  dropEffect: Cardinal;
  dropEffectFmt: UINT;
begin
  Result := False;
  if APath = '' then
    Exit;
  pathLen := Length(APath);
  bufSize := SizeOf(TDropFiles) + (pathLen + 2) * SizeOf(WideChar);
  hDrop := GlobalAlloc(GHND, bufSize);
  if hDrop = 0 then
    Exit;
  buf := GlobalLock(hDrop);
  if buf = nil then
  begin
    GlobalFree(hDrop);
    Exit;
  end;
  try
    Drop := buf;
    Drop^.pFiles := SizeOf(TDropFiles);
    Drop^.fWide := True;
    offset := SizeOf(TDropFiles);
    Move(PWideChar(APath)^, PByte(buf)[offset], (pathLen + 1) * SizeOf(WideChar));
  finally
    GlobalUnlock(hDrop);
  end;
  if not OpenClipboard(0) then
  begin
    GlobalFree(hDrop);
    Exit;
  end;
  try
    EmptyClipboard;
    if SetClipboardData(CF_HDROP, hDrop) = 0 then
    begin
      GlobalFree(hDrop);
      Exit;
    end;
    dropEffectFmt := RegisterClipboardFormat('Preferred DropEffect');
    if dropEffectFmt <> 0 then
    begin
      dropEffect := DROPEFFECT_COPY;
      hEffect := GlobalAlloc(GHND, SizeOf(dropEffect));
      if hEffect <> 0 then
      begin
        buf := GlobalLock(hEffect);
        if buf <> nil then
        try
          Move(dropEffect, buf^, SizeOf(dropEffect));
        finally
          GlobalUnlock(hEffect);
        end;
        SetClipboardData(dropEffectFmt, hEffect);
      end;
    end;
    Result := True;
  finally
    CloseClipboard;
  end;
end;

function ShellDeletePath(hwnd: Windows.HWND; const FilePath: UnicodeString): Boolean;
var
  fo: TSHFileOpStruct;
  fromBuf: UnicodeString;
begin
  Result := False;
  if FilePath = '' then
    Exit;
  fromBuf := FilePath + #0#0;
  FillChar(fo, SizeOf(fo), 0);
  fo.Wnd := hwnd;
  fo.wFunc := FO_DELETE;
  fo.pFrom := PWideChar(fromBuf);
  fo.fFlags := FOF_ALLOWUNDO;
  Result := (SHFileOperation(fo) = 0) and (not fo.fAnyOperationsAborted);
end;

function IsRunningUnderWow64: Boolean;
type
  TIsWow64Process = function(hProcess: THandle; var Wow64Process: BOOL): BOOL; stdcall;
var
  Kernel: HMODULE;
  Proc: TIsWow64Process;
  b: BOOL;
begin
  Result := False;
  b := False;
  Kernel := GetModuleHandle('kernel32.dll');
  if Kernel = 0 then
    Exit;
  @Proc := GetProcAddress(Kernel, 'IsWow64Process');
  if not Assigned(Proc) then
    Exit;
  if Proc(GetCurrentProcess, b) then
    Result := b;
end;

function NormalizeSystem32PathForIcon(const APath: string): string;
var
  WinDir: array[0..MAX_PATH - 1] of Char;
  Prefix: string;
begin
  Result := APath;
  if not IsRunningUnderWow64 then
    Exit;
  if GetWindowsDirectory(WinDir, MAX_PATH) = 0 then
    Exit;
  Prefix := IncludeTrailingPathDelimiter(string(WinDir)) + 'System32\';
  if (Length(Result) > Length(Prefix)) and SameText(Copy(Result, 1, Length(Prefix)), Prefix) then
  begin
    if not FileExists(Result) then
      Result := IncludeTrailingPathDelimiter(string(WinDir)) + 'Sysnative\' + Copy(Result, Length(Prefix) + 1, MaxInt);
  end;
end;

function ResolveSystem32ExePath(const AExeName: string): string;
var
  WinDir: array[0..MAX_PATH - 1] of Char;
begin
  if GetWindowsDirectory(WinDir, MAX_PATH) = 0 then
    Exit(AExeName);
  Result := IncludeTrailingPathDelimiter(string(WinDir)) + 'System32\' + AExeName;
  Result := NormalizeSystem32PathForIcon(Result);
end;

function ResolveSystemBinaryPathForOsArchitecture(const AExeName: string): string;
var
  WinDir: array[0..MAX_PATH - 1] of Char;
begin
  if GetWindowsDirectory(WinDir, MAX_PATH) = 0 then
    Exit(AExeName);
  if IsRunningUnderWow64 then
    Result := IncludeTrailingPathDelimiter(string(WinDir)) + 'Sysnative\' + AExeName
  else
    Result := IncludeTrailingPathDelimiter(string(WinDir)) + 'System32\' + AExeName;
end;

function ResolveSystem32MscDocumentPath(const AMscFileName: string): string;
var
  WinDir: array[0..MAX_PATH - 1] of Char;
begin
  if GetWindowsDirectory(WinDir, MAX_PATH) = 0 then
    Exit(AMscFileName);
  Result := IncludeTrailingPathDelimiter(string(WinDir)) + 'System32\' + AMscFileName;
end;

function ResolveWindowsExplorerPath: UnicodeString;
var
  WinDir: array[0..MAX_PATH - 1] of Char;
begin
  if GetWindowsDirectory(WinDir, MAX_PATH) = 0 then
    Exit('explorer.exe');
  Result := IncludeTrailingPathDelimiter(UnicodeString(WinDir)) + 'explorer.exe';
end;

function NormalizeSystem32PathForExecute(const APath: UnicodeString): UnicodeString;
var
  WinDir: array[0..MAX_PATH - 1] of Char;
  Prefix: UnicodeString;
  Tail: UnicodeString;
begin
  Result := Trim(APath);
  if Result = '' then
    Exit;
  if not IsRunningUnderWow64 then
    Exit;
  if GetWindowsDirectory(WinDir, MAX_PATH) = 0 then
    Exit;
  Prefix := IncludeTrailingPathDelimiter(UnicodeString(WinDir)) + 'System32\';
  if (Length(Result) > Length(Prefix)) and SameText(Copy(Result, 1, Length(Prefix)), Prefix) then
  begin
    if not FileExists(Result) and not DirectoryExists(Result) then
    begin
      Tail := Copy(Result, Length(Prefix) + 1, MaxInt);
      Result := IncludeTrailingPathDelimiter(UnicodeString(WinDir)) + 'Sysnative\' + Tail;
    end;
  end;
end;

function NormalizeProgramFilesPathForWow64(const APath: string): string;
var
  pf86: string;
  pf64: string;
  prefix86: string;
  prefix64: string;
  tail: string;
begin
  Result := Trim(APath);
  if Result = '' then
    Exit;
  if not IsRunningUnderWow64 then
    Exit;
  pf86 := Trim(GetEnvironmentVariable('ProgramFiles(x86)'));
  pf64 := Trim(GetEnvironmentVariable('ProgramW6432'));
  if (pf86 = '') or (pf64 = '') then
    Exit;
  prefix86 := IncludeTrailingPathDelimiter(pf86);
  prefix64 := IncludeTrailingPathDelimiter(pf64);
  if (Length(Result) > Length(prefix86)) and SameText(Copy(Result, 1, Length(prefix86)), prefix86) then
  begin
    tail := Copy(Result, Length(prefix86) + 1, MaxInt);
    if FileExists(prefix64 + tail) then
      Result := prefix64 + tail;
  end;
end;


function ResolveItemIconPath(const AIconPath: string): string;
begin
  Result := Trim(AIconPath);
  if (Result <> '') and (not FileExists(Result)) then
    Result := '';
end;

function BrowseForFolderPath(const ATitle: string; const AOwnerWnd: Windows.HWND; out AFolderPath: string): Boolean;
var
  browseInfo: TBrowseInfoW;
  pidl: PItemIDList;
  pathBuffer: array[0..MAX_PATH] of WideChar;
begin
  Result := False;
  AFolderPath := '';
  FillChar(browseInfo, SizeOf(browseInfo), 0);
  browseInfo.hwndOwner := AOwnerWnd;
  browseInfo.lpszTitle := PWideChar(ATitle);
  browseInfo.ulFlags := BIF_RETURNONLYFSDIRS or BIF_NEWDIALOGSTYLE;
  pidl := SHBrowseForFolderW(browseInfo);
  if pidl = nil then
    Exit;
  try
    if SHGetPathFromIDListW(pidl, pathBuffer) then
    begin
      AFolderPath := pathBuffer;
      Result := AFolderPath <> '';
    end;
  finally
    CoTaskMemFree(pidl);
  end;
end;

end.