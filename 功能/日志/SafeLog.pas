unit SafeLog;

{
  线程安全运行日志：写入后由安全日志窗口展示（列表 + 详情）。
}

interface

uses
  SysUtils, Classes, SyncObjs, Windows, XCGUI;

const
  { 与 Messages.WM_APP($8000) 一致，避免 interface 依赖 Messages }
  WM_SAFELOG_APPEND = $8000 + 200;
  WM_SAFELOG_REMOVE_OLDEST = $8000 + 201;

type
  TSafeLogEntry = record
    Id: Integer;
    TimeText: string;
    TypeText: string;
    FeatureText: string;
    SummaryText: string;
    Success: Boolean;
    FetchTimeText: string;
    ElapsedText: string;
    ParsedLine: string;
  end;

  TSafeLogEntryArray = array of TSafeLogEntry;

procedure SafeLogFetch(const ATypeText, AFeature, ASummary: string;
  AStart: TDateTime; AElapsedMs: Cardinal; ASuccess: Boolean;
  const AParsedSingleLine: string);
procedure SafeLogRecord(const ATypeText, AFeature, ASummary: string; ASuccess: Boolean);
function SafeLogFindById(AId: Integer; out AEntry: TSafeLogEntry): Boolean;
procedure SafeLogCopyAll(out AEntries: TSafeLogEntryArray);
function SafeLogBuildDetail(const AEntry: TSafeLogEntry): string;
function SafeLogFormatStatusText(ASuccess: Boolean): string;
function SafeLogFormatElapsed(AElapsedMs: Cardinal): string;
procedure SafeLogClearAll;
function SafeLogFormatExportText: string;
function SafeLogSaveToFile(const AFileName: string): Boolean;
procedure SafeLogBindWindow(AWindow: HWINDOW);
procedure SafeLogClearWindow;
procedure SafeLogStartupBegin;
procedure SafeLogStartupAppendRuntimeEnv;
procedure SafeLogStartupAppendStep(const AFeature, ADetail: string; ASuccess: Boolean);
procedure SafeLogStartupCommit;
function SafeLogStartupPending: Boolean;

implementation

uses
  SQLite3;

const
  cMaxEntries = 500;

var
  GLogLock: TCriticalSection;
  GEntries: array of TSafeLogEntry;
  GNextId: Integer;
  GSafeLogWindow: HWINDOW;
  GStartupLines: TStringList;
  GStartupActive: Boolean;
  GStartupHasFailure: Boolean;

procedure SafeLogBindWindow(AWindow: HWINDOW);
begin
  GSafeLogWindow := AWindow;
end;

procedure SafeLogClearWindow;
begin
  GSafeLogWindow := 0;
end;

function GetPeVersionString(const AFilePath: string; const AValueName: string): string;
var
  handle: DWORD;
  infoSize: DWORD;
  infoBuf: Pointer;
  transBuf: Pointer;
  transLen: UINT;
  trans: DWORD;
  query: string;
  valueBuf: Pointer;
  valueLen: UINT;
begin
  Result := '';
  infoSize := GetFileVersionInfoSizeW(PWideChar(AFilePath), handle);
  if infoSize = 0 then
    Exit;
  GetMem(infoBuf, infoSize);
  try
    if not GetFileVersionInfoW(PWideChar(AFilePath), 0, infoSize, infoBuf) then
      Exit;
    if VerQueryValueW(infoBuf, '\VarFileInfo\Translation', transBuf, transLen) and
      (transLen >= SizeOf(DWORD)) then
      trans := PDWORD(transBuf)^
    else
      trans := $04B00409;
    query := Format('\StringFileInfo\%.4x%.4x\%s', [LOWORD(trans), HIWORD(trans), AValueName]);
    if VerQueryValueW(infoBuf, PWideChar(query), valueBuf, valueLen) and (valueLen > 0) then
      Result := Trim(WideString(PWideChar(valueBuf)));
  finally
    FreeMem(infoBuf);
  end;
end;

function GetDllFileVersionText(const AFilePath: string): string;
begin
  if not FileExists(AFilePath) then
    Exit('(未找到)');
  Result := GetPeVersionString(AFilePath, 'ProductVersion');
  if Result = '' then
    Result := GetPeVersionString(AFilePath, 'FileVersion');
  if Result = '' then
    Result := '(无版本信息)';
end;

function GetSqlite3VersionText: string;
var
  ver: PAnsiChar;
begin
  ver := sqlite3_libversion;
  if ver <> nil then
    Result := string(AnsiString(ver))
  else
    Result := '';
end;

function RtlGetVersionSucceeded(AStatus: LongInt): Boolean;
begin
  Result := AStatus >= 0;
end;

function GetNativeOsArchText: string;
var
  sysInfo: TSystemInfo;
begin
  GetNativeSystemInfo(sysInfo);
  case sysInfo.wProcessorArchitecture of
    PROCESSOR_ARCHITECTURE_AMD64:
      Result := 'x64';
    PROCESSOR_ARCHITECTURE_INTEL:
      Result := 'x86';
  else
    Result := Format('Arch%d', [sysInfo.wProcessorArchitecture]);
  end;
end;

function GetWindowsVersionText: string;
type
  TRtlGetVersion = function(var AInfo: TOSVersionInfoEx): LongInt; stdcall;
var
  modNtdll: HMODULE;
  fnRtlGetVersion: TRtlGetVersion;
  osInfo: TOSVersionInfoEx;
  verText: string;
begin
  Result := '(未知)';
  modNtdll := GetModuleHandle('ntdll.dll');
  if modNtdll = 0 then
    Exit;
  @fnRtlGetVersion := GetProcAddress(modNtdll, PAnsiChar('RtlGetVersion'));
  if not Assigned(fnRtlGetVersion) then
    Exit;
  FillChar(osInfo, SizeOf(osInfo), 0);
  osInfo.dwOSVersionInfoSize := SizeOf(osInfo);
  if not RtlGetVersionSucceeded(fnRtlGetVersion(osInfo)) then
    Exit;
  verText := Format('%d.%d.%d', [osInfo.dwMajorVersion, osInfo.dwMinorVersion,
    osInfo.dwBuildNumber]);
  Result := verText + ' ' + GetNativeOsArchText;
end;

function BuildRuntimeDllVersionLines: string;
var
  binDir: string;
  sl: TStringList;
  sqliteVer: string;
begin
  binDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'Bin\';
  sl := TStringList.Create;
  try
    sl.Add('系统版本: ' + GetWindowsVersionText);
    sl.Add('界面库版本: ' + GetDllFileVersionText(binDir + 'XCGUI.dll'));
    sqliteVer := GetSqlite3VersionText;
    if sqliteVer <> '' then
      sl.Add('数据库版本: ' + sqliteVer)
    else
      sl.Add('数据库版本: ' + GetDllFileVersionText(binDir + 'Sqlite3.dll'));
    Result := Trim(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure SafeLogPostAppend(AEntryId: Integer); 
begin
  if GSafeLogWindow <> 0 then
    XC_PostMessage(GSafeLogWindow, WM_SAFELOG_APPEND, WPARAM(AEntryId), 0);
end;

procedure SafeLogPostRemoveOldest;
begin
  if GSafeLogWindow <> 0 then
    XC_PostMessage(GSafeLogWindow, WM_SAFELOG_REMOVE_OLDEST, 0, 0);
end;

function FormatLogTime(const ATime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy/mm/dd hh:nn', ATime);
end;

function FormatLogFetchTime(const ATime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy/mm/dd hh:nn:ss', ATime);
end;

function ToSingleLine(const AText: string): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, sLineBreak, ' ', [rfReplaceAll]),
    #13#10, ' ', [rfReplaceAll]));
end;

function ResolveSummaryText(const ASummary, AParsedSingleLine: string; ASuccess: Boolean): string;
var
  parsed: string;
begin
  if Trim(ASummary) <> '' then
    Exit(Trim(ASummary));
  parsed := ToSingleLine(AParsedSingleLine);
  if parsed <> '' then
    Exit(parsed);
  if ASuccess then
    Result := '成功'
  else
    Result := '失败';
end;

procedure SafeLogAppendEntry(const entry: TSafeLogEntry);
var
  idx: Integer;
  copyEntry: TSafeLogEntry;
begin
  copyEntry := entry;
  GLogLock.Enter;
  try
    Inc(GNextId);
    copyEntry.Id := GNextId;
    idx := Length(GEntries);
    SetLength(GEntries, idx + 1);
    GEntries[idx] := copyEntry;
    while Length(GEntries) > cMaxEntries do
    begin
      SafeLogPostRemoveOldest;
      if Length(GEntries) <= 1 then
      begin
        SetLength(GEntries, 0);
        Break;
      end;
      GEntries[0] := GEntries[1];
      SetLength(GEntries, Length(GEntries) - 1);
    end;
  finally
    GLogLock.Leave;
  end;
  SafeLogPostAppend(copyEntry.Id);
end;

procedure SafeLogFetch(const ATypeText, AFeature, ASummary: string;
  AStart: TDateTime; AElapsedMs: Cardinal; ASuccess: Boolean;
  const AParsedSingleLine: string);
var
  entry: TSafeLogEntry;
begin
  entry.Id := 0;
  entry.TimeText := FormatLogTime(AStart);
  entry.TypeText := Trim(ATypeText);
  if entry.TypeText = '' then
    entry.TypeText := 'get';
  entry.FeatureText := Trim(AFeature);
  entry.Success := ASuccess;
  entry.FetchTimeText := FormatLogFetchTime(AStart);
  entry.ElapsedText := SafeLogFormatElapsed(AElapsedMs);
  entry.ParsedLine := ToSingleLine(AParsedSingleLine);
  entry.SummaryText := ResolveSummaryText(ASummary, AParsedSingleLine, ASuccess);
  SafeLogAppendEntry(entry);
end;

procedure SafeLogRecord(const ATypeText, AFeature, ASummary: string; ASuccess: Boolean);
var
  entry: TSafeLogEntry;
  nowTime: TDateTime;
begin
  nowTime := Now;
  entry.Id := 0;
  entry.TimeText := FormatLogTime(nowTime);
  entry.TypeText := Trim(ATypeText);
  if entry.TypeText = '' then
    entry.TypeText := 'local';
  entry.FeatureText := Trim(AFeature);
  entry.Success := ASuccess;
  entry.FetchTimeText := FormatLogFetchTime(nowTime);
  entry.ElapsedText := '-';
  entry.ParsedLine := '';
  entry.SummaryText := ResolveSummaryText(ASummary, '', ASuccess);
  SafeLogAppendEntry(entry);
end;

procedure SafeLogStartupBegin;
begin
  if GStartupLines = nil then
    GStartupLines := TStringList.Create;
  GStartupLines.Clear;
  GStartupActive := True;
  GStartupHasFailure := False;
end;

procedure SafeLogStartupAppendRuntimeEnv;
var
  sl: TStringList;
begin
  if not GStartupActive then
    Exit;
  sl := TStringList.Create;
  try
    sl.Text := BuildRuntimeDllVersionLines;
    GStartupLines.AddStrings(sl);
  finally
    sl.Free;
  end;
end;

procedure SafeLogStartupAppendStep(const AFeature, ADetail: string; ASuccess: Boolean);
var
  line: string;
begin
  if not GStartupActive then
    Exit;
  line := Trim(AFeature) + string('：') + Trim(ADetail);
  if not ASuccess then
  begin
    line := line + string(' [失败]');
    GStartupHasFailure := True;
  end;
  GStartupLines.Add(line);
end;

procedure SafeLogStartupCommit;
var
  entry: TSafeLogEntry;
  nowTime: TDateTime;
begin
  if not GStartupActive then
    Exit;
  GStartupActive := False;
  if (GStartupLines = nil) or (GStartupLines.Count = 0) then
    Exit;
  nowTime := Now;
  entry.Id := 0;
  entry.TimeText := FormatLogTime(nowTime);
  entry.TypeText := 'local';
  entry.FeatureText := string('初始化');
  entry.Success := not GStartupHasFailure;
  entry.FetchTimeText := FormatLogFetchTime(nowTime);
  entry.ElapsedText := '-';
  entry.ParsedLine := Trim(GStartupLines.Text);
  if entry.Success then
    entry.SummaryText := string('应用初始化完成')
  else
    entry.SummaryText := string('应用初始化失败');
  GStartupLines.Clear;
  SafeLogAppendEntry(entry);
end;

function SafeLogStartupPending: Boolean;
begin
  Result := GStartupActive;
end;

function SafeLogFindById(AId: Integer; out AEntry: TSafeLogEntry): Boolean;
var
  i: Integer;
begin
  Result := False;
  GLogLock.Enter;
  try
    for i := 0 to High(GEntries) do
      if GEntries[i].Id = AId then
      begin
        AEntry := GEntries[i];
        Exit(True);
      end;
  finally
    GLogLock.Leave;
  end;
end;

procedure SafeLogCopyAll(out AEntries: TSafeLogEntryArray);
var
  i: Integer;
begin
  GLogLock.Enter;
  try
    SetLength(AEntries, Length(GEntries));
    for i := 0 to High(GEntries) do
      AEntries[i] := GEntries[i];
  finally
    GLogLock.Leave;
  end;
end;

function SafeLogBuildDetail(const AEntry: TSafeLogEntry): string;
begin
  if SameText(AEntry.TypeText, 'local') then
  begin
    if AEntry.Success then
      Result := '结果：成功'
    else
      Result := '结果：失败';
    Result := Result + sLineBreak + '时间：' + AEntry.FetchTimeText;
    if Trim(AEntry.ParsedLine) <> '' then
      Result := Result + sLineBreak + AEntry.ParsedLine
    else
      Result := Result + sLineBreak + '说明：' + AEntry.SummaryText;
    Exit;
  end;
  if AEntry.Success then
    Result := '获取结果：成功'
  else
    Result := '获取结果：失败';
  Result := Result + sLineBreak + '获取时间：' + AEntry.FetchTimeText;
  if (AEntry.ElapsedText <> '') and (AEntry.ElapsedText <> '-') then
    Result := Result + sLineBreak + '耗时：' + AEntry.ElapsedText;
  Result := Result + sLineBreak + '解析后的数据：' + AEntry.ParsedLine;
end;

function SafeLogFormatStatusText(ASuccess: Boolean): string;
begin
  if ASuccess then
    Result := '成功'
  else
    Result := '失败';
end;

function SafeLogFormatElapsed(AElapsedMs: Cardinal): string;
begin
  if AElapsedMs < 1000 then
    Result := IntToStr(AElapsedMs) + 'ms'
  else
    Result := Format('%.2fs', [AElapsedMs / 1000]);
end;

procedure SafeLogClearAll;
begin
  GLogLock.Enter;
  try
    SetLength(GEntries, 0);
  finally
    GLogLock.Leave;
  end;
end;

function SafeLogFormatExportText: string;
var
  entries: TSafeLogEntryArray;
  sl: TStringList;
  i: Integer;
begin
  SafeLogCopyAll(entries);
  sl := TStringList.Create;
  try
    for i := 0 to High(entries) do
    begin
      sl.Add(Format('[%s] %s  %s  %s  %s  %s', [
        SafeLogFormatStatusText(entries[i].Success),
        entries[i].TimeText,
        entries[i].ElapsedText,
        entries[i].TypeText,
        entries[i].FeatureText,
        entries[i].SummaryText]));
      sl.Add(SafeLogBuildDetail(entries[i]));
      sl.Add('---');
    end;
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function SafeLogSaveToFile(const AFileName: string): Boolean;
var
  sl: TStringList;
begin
  Result := False;
  if Trim(AFileName) = '' then
    Exit;
  sl := TStringList.Create;
  try
    try
      sl.Text := SafeLogFormatExportText;
      sl.SaveToFile(AFileName, TEncoding.UTF8);
      Result := True;
    except
      Result := False;
    end;
  finally
    sl.Free;
  end;
end;

initialization
  GLogLock := TCriticalSection.Create;

finalization
  FreeAndNil(GStartupLines);
  FreeAndNil(GLogLock);

end.
