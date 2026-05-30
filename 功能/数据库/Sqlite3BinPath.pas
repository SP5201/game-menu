unit Sqlite3BinPath;

interface

implementation

uses
  Windows, SysUtils;

initialization
  SetDllDirectoryW(PWideChar(
    WideString(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'Bin')));

finalization
  SetDllDirectoryW(nil);

end.
