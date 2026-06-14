unit AppPaths;

{
  应用程序目录与原生 DLL 搜索路径。
  默认 Bin 目录为 exe 同级的 Bin\（如 Debug\Win32\Bin\），存放 XCGUI、sqlite3、libcurl 等第三方 DLL。
}

interface

uses
  SysUtils;

const
  cDefaultBinDirName = 'Bin';

function AppExeDirectory: string;
function AppBinDirectory: string;
function AppDataDirectory: string;
function AppBinDllFileName(const AFileName: string): string;
function AppBinDllPath(const AFileName: string): string;
function AppBinRelativeDllPath(const AFileName: string): string;
procedure SetAppBinDirectory(const ADirectory: string);
procedure ConfigureNativeDllSearchPath;

implementation

uses
  Windows;

var
  GExeDirectory: string;
  GBinDirectory: string;
  GDllSearchConfigured: Boolean;

function AppExeDirectory: string;
begin
  if GExeDirectory = '' then
    GExeDirectory := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Result := GExeDirectory;
end;

function AppBinDirectory: string;
begin
  if GBinDirectory = '' then
    GBinDirectory := AppExeDirectory + cDefaultBinDirName + PathDelim;
  Result := GBinDirectory;
end;

function AppDataDirectory: string;
begin
  Result := AppExeDirectory + 'Data' + PathDelim;
end;

procedure SetAppBinDirectory(const ADirectory: string);
var
  normalized: string;
begin
  if ADirectory = '' then
    GBinDirectory := AppExeDirectory + cDefaultBinDirName + PathDelim
  else
  begin
    normalized := ADirectory;
    if (Length(normalized) >= 2) and (normalized[2] = ':') then
      normalized := IncludeTrailingPathDelimiter(normalized)
    else
      normalized := IncludeTrailingPathDelimiter(AppExeDirectory + normalized);
    GBinDirectory := normalized;
  end;
  GDllSearchConfigured := False;
  ConfigureNativeDllSearchPath;
end;

function AppBinDllFileName(const AFileName: string): string;
{$IFDEF WIN64}
var
  baseName, ext: string;
{$ENDIF}
begin
  Result := ExtractFileName(AFileName);
{$IFDEF WIN64}
  ext := ExtractFileExt(Result);
  if SameText(ext, '.dll') then
  begin
    baseName := ChangeFileExt(Result, '');
    if (Length(baseName) < 4) or not SameText(Copy(baseName, Length(baseName) - 3, 4), '_x64') then
      Result := baseName + '_x64' + ext;
  end;
{$ENDIF}
end;

function AppBinDllPath(const AFileName: string): string;
begin
  Result := AppBinDirectory + AppBinDllFileName(AFileName);
end;

function AppBinRelativeDllPath(const AFileName: string): string;
begin
  Result := cDefaultBinDirName + PathDelim + AppBinDllFileName(AFileName);
end;

procedure ConfigureNativeDllSearchPath;
begin
  if GDllSearchConfigured then
    Exit;
  SetDllDirectoryW(PWideChar(AppBinDirectory));
  GDllSearchConfigured := True;
end;

initialization
  ConfigureNativeDllSearchPath;

finalization
  SetDllDirectoryW(nil);

end.
