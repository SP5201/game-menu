unit ShellExecuteHelper;

interface

uses
  SysUtils,
  Windows,
  ShellAPI,
  ShellPathHelper;

function ShellExecuteDefaultVerb(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;

function ShellExecuteRunAs(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;

function ShellOpenFolderAndSelectPath(hwnd: Windows.HWND; const FilePath: UnicodeString): Boolean;

implementation

function ShellExecuteDefaultVerb(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;
var
  sei: TShellExecuteInfo;
  execPath: UnicodeString;
begin
  Result := False;
  if FilePath = '' then
    Exit;
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
  sei.nShow := SW_SHOWNORMAL;
  Result := ShellExecuteEx(@sei);
end;

function ShellExecuteRunAs(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;
var
  execPath: UnicodeString;
begin
  Result := False;
  if FilePath = '' then
    Exit;
  execPath := NormalizeSystem32PathForExecute(FilePath);
  Result := ShellExecuteW(hwnd, 'runas', PWideChar(execPath), PWideChar(Parameters), PWideChar(WorkingDir), SW_SHOWNORMAL) > 32;
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

end.
