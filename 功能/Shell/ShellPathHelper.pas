unit ShellPathHelper;

interface

uses
  SysUtils,
  Windows;

function IsRunningUnderWow64: Boolean;

/// <summary>WOW64 下 System32 路径在仅 64 位文件存在时改用 Sysnative（供 ExtractIcon 等）。</summary>
function NormalizeSystem32PathForIcon(const APath: string): string;

/// <summary>WOW64 下执行路径的 Sysnative 纠正（目录不误判为缺失）。</summary>
function NormalizeSystem32PathForExecute(const APath: UnicodeString): UnicodeString;

function ResolveSystem32ExePath(const AExeName: string): string;

function ResolveSystemBinaryPathForOsArchitecture(const AExeName: string): string;

function ResolveSystem32MscDocumentPath(const AMscFileName: string): string;

/// <summary>32 位进程在 WOW64 下纠正 Program Files(x86) → ProgramW6432（目标存在时）。</summary>
function NormalizeProgramFilesPathForWow64(const APath: string): string;

implementation

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

end.
