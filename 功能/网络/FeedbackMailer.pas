unit FeedbackMailer;

interface

uses
  Windows;

function SendFeedbackMessage(const AMessage: string; const AOwnerWnd: Windows.HWND;
  out AError: string): Boolean;

implementation

uses
  Classes, SysUtils, ShellHelper;

const
  cGithubRepo = 'SP5201/game-menu';
  cGithubIssueBodyMaxLen = 1800;
  cGithubUserMessageMaxLen = 900;

function UrlEncodeUtf8(const S: string): string;
var
  utf8: UTF8String;
  i: Integer;
  b: Byte;
begin
  utf8 := UTF8Encode(S);
  Result := '';
  for i := 1 to Length(utf8) do
  begin
    b := Ord(utf8[i]);
    if (b in [$41..$5A, $61..$7A, $30..$39, Ord('-'), Ord('_'), Ord('.'), Ord('~')]) then
      Result := Result + WideChar(b)
    else if b = Ord(' ') then
      Result := Result + '+'
    else
      Result := Result + Format('%%%.2x', [b]);
  end;
end;

function GetAppVersionText: string;
var
  handle: DWORD;
  infoSize: DWORD;
  infoBuf: Pointer;
  fixedInfo: PVSFixedFileInfo;
  len: UINT;
  exePath: string;
begin
  Result := '未知';
  exePath := ParamStr(0);
  infoSize := GetFileVersionInfoSizeW(PWideChar(exePath), handle);
  if infoSize = 0 then
    Exit;
  GetMem(infoBuf, infoSize);
  try
    if not GetFileVersionInfoW(PWideChar(exePath), 0, infoSize, infoBuf) then
      Exit;
    if VerQueryValueW(infoBuf, '\', Pointer(fixedInfo), len) then
      Result := Format('%d.%d.%d.%d', [
        HiWord(fixedInfo^.dwFileVersionMS),
        LoWord(fixedInfo^.dwFileVersionMS),
        HiWord(fixedInfo^.dwFileVersionLS),
        LoWord(fixedInfo^.dwFileVersionLS)]);
  finally
    FreeMem(infoBuf);
  end;
end;

function GetOsArchBitText: string;
var
  sysInfo: TSystemInfo;
begin
  GetNativeSystemInfo(sysInfo);
  case sysInfo.wProcessorArchitecture of
    PROCESSOR_ARCHITECTURE_AMD64:
      Result := '64 位';
    PROCESSOR_ARCHITECTURE_INTEL:
      Result := '32 位';
  else
    Result := '未知';
  end;
end;

function GetOsVersionArchText: string;
type
  TRtlGetVersion = function(var AInfo: TOSVersionInfoEx): LongInt; stdcall;
var
  fn: TRtlGetVersion;
  info: TOSVersionInfoEx;
  h: THandle;
begin
  Result := '未知';
  h := GetModuleHandle('ntdll.dll');
  if h = 0 then
    Exit;
  fn := TRtlGetVersion(GetProcAddress(h, 'RtlGetVersion'));
  if not Assigned(fn) then
    Exit;
  FillChar(info, SizeOf(info), 0);
  info.dwOSVersionInfoSize := SizeOf(info);
  if fn(info) <> 0 then
    Exit;
  Result := Format('Windows %d.%d.%d %s', [
    info.dwMajorVersion, info.dwMinorVersion, info.dwBuildNumber, GetOsArchBitText]);
end;

function MarkdownQuoteBlock(const AText: string): string;
var
  lines: TStringList;
  i: Integer;
  line: string;
begin
  Result := '';
  lines := TStringList.Create;
  try
    lines.Text := AText;
    for i := 0 to lines.Count - 1 do
    begin
      line := TrimRight(lines[i]);
      if Result <> '' then
        Result := Result + sLineBreak;
      if line = '' then
        Result := Result + '>'
      else
        Result := Result + '> ' + line;
    end;
    if Result = '' then
      Result := '> （未填写详细描述）';
  finally
    lines.Free;
  end;
end;

function TruncateWithHint(const S: string; AMaxLen: Integer): string;
begin
  if Length(S) <= AMaxLen then
    Result := S
  else
    Result := Copy(S, 1, AMaxLen) + sLineBreak + sLineBreak +
      '_（内容过长已截断，请在此 Issue 中继续补充）_';
end;

function BuildFeedbackBody(const AMessage: string): string;
var
  userText, appVersion, osText: string;
begin
  userText := TruncateWithHint(Trim(AMessage), cGithubUserMessageMaxLen);
  appVersion := GetAppVersionText;
  osText := GetOsVersionArchText;

  Result :=
    '## 问题描述' + sLineBreak + sLineBreak +
    MarkdownQuoteBlock(userText) + sLineBreak + sLineBreak +
    '## 环境信息' + sLineBreak + sLineBreak +
    '| 项目 | 内容 |' + sLineBreak +
    '|:---|:---|' + sLineBreak +
    '| **应用版本** | ' + appVersion + ' |' + sLineBreak +
    '| **系统** | ' + osText + ' |';

  if Length(Result) > cGithubIssueBodyMaxLen then
    Result := Copy(Result, 1, cGithubIssueBodyMaxLen) + sLineBreak + sLineBreak +
      '_（正文过长已截断，请补充完整信息）_';
end;

function BuildIssueTitle(const AMessage: string): string;
var
  line: string;
  p: Integer;
begin
  line := Trim(AMessage);
  p := Pos(#13#10, line);
  if p > 0 then
    line := Copy(line, 1, p - 1);
  p := Pos(#10, line);
  if p > 0 then
    line := Copy(line, 1, p - 1);
  line := Trim(line);
  if line = '' then
    line := '用户反馈';
  if Length(line) > 48 then
    SetLength(line, 48);
  Result := '[反馈] ' + line;
end;

function BuildGithubNewIssueUrl(const AMessage: string): string;
var
  title, body: string;
begin
  title := BuildIssueTitle(AMessage);
  body := BuildFeedbackBody(AMessage);
  Result := 'https://github.com/' + cGithubRepo + '/issues/new' +
    '?title=' + UrlEncodeUtf8(title) +
    '&body=' + UrlEncodeUtf8(body);
end;

function SendFeedbackMessage(const AMessage: string; const AOwnerWnd: Windows.HWND;
  out AError: string): Boolean;
var
  issueUrl: string;
begin
  Result := False;
  AError := '';
  if Trim(AMessage) = '' then
  begin
    AError := '反馈内容为空';
    Exit;
  end;
  if Trim(cGithubRepo) = '' then
  begin
    AError := '未配置 GitHub 仓库地址';
    Exit;
  end;

  issueUrl := BuildGithubNewIssueUrl(AMessage);
  Result := ShellExecuteDefaultVerb(AOwnerWnd, issueUrl, '', '', SW_SHOWNORMAL);
  if not Result then
    AError := '无法打开浏览器，请检查系统默认浏览器设置。';
end;

end.
