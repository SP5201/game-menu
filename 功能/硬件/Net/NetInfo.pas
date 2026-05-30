unit NetInfo;

{
  网卡悬停提示：优先 NwInfoRunner（--net=active,phys），失败或缺字段时回退 NetInfoNative。
  发送/接收字节数每次由 Native GetIfEntry2 刷新。
}

interface

uses
  SysUtils;

function NetFormatAdapterTooltip: string;

implementation

{$WARN IMPLICIT_STRING_CAST OFF}

uses
  NetInfoTypes, NetInfoNative, NetInfoNwInfo, NwInfoRunner;

var
  GStaticLoaded: Boolean;
  GStaticInfo: TNetAdapterInfo;

procedure NetMergeMissingFields(var ATarget, ANative: TNetAdapterInfo);
begin
  if ATarget.IfIndex = 0 then
    ATarget.IfIndex := ANative.IfIndex;
  if (ATarget.Name = '') or (ATarget.Name = cNetDash) then
    ATarget.Name := ANative.Name;
  if (ATarget.TypeText = '') or (ATarget.TypeText = cNetDash) then
    ATarget.TypeText := ANative.TypeText;
  if (ATarget.Mac = '') or (ATarget.Mac = cNetDash) then
    ATarget.Mac := ANative.Mac;
  if (ATarget.LinkSpeedText = '') or (ATarget.LinkSpeedText = cNetDash) then
    ATarget.LinkSpeedText := ANative.LinkSpeedText;
end;

procedure NetEnsureAdapterInfo;
var
  nwInfo, nativeInfo: TNetAdapterInfo;
begin
  if GStaticLoaded then
    Exit;
  nativeInfo := NetNativeQueryAdapterInfo;
  if NetTryQueryFromNwInfo(nwInfo) then
  begin
    NetMergeMissingFields(nwInfo, nativeInfo);
    GStaticInfo := nwInfo;
    GStaticLoaded := True;
    Exit;
  end;
  if (nativeInfo.Name <> '') and (nativeInfo.Name <> cNetDash) then
  begin
    GStaticInfo := nativeInfo;
    GStaticLoaded := True;
    Exit;
  end;
  GStaticInfo := nativeInfo;
end;

function NetFormatAdapterTooltip: string;
var
  info: TNetAdapterInfo;
  nwExe, nwDir: string;
begin
  NetEnsureAdapterInfo;
  info := GStaticInfo;
  NetNativeRefreshTrafficOctets(info.IfIndex, info);

  if info.Name = '' then
    info.Name := cNetDash;
  if info.TypeText = '' then
    info.TypeText := cNetDash;
  if info.Mac = '' then
    info.Mac := cNetDash;
  if info.LinkSpeedText = '' then
    info.LinkSpeedText := cNetDash;
  if info.SentOctetsText = '' then
    info.SentOctetsText := cNetDash;
  if info.ReceivedOctetsText = '' then
    info.ReceivedOctetsText := cNetDash;

  Result := '网卡名：' + info.Name + sLineBreak +
    '网卡类型：' + info.TypeText + sLineBreak +
    '网卡MAC：' + info.Mac + sLineBreak +
    '链接速度：' + info.LinkSpeedText + sLineBreak +
    '发送的字节数：' + info.SentOctetsText + sLineBreak +
    '接收的字节数：' + info.ReceivedOctetsText;

  if (info.Name = cNetDash) and not NwInfoResolveExe(nwExe, nwDir) then
    Result := Result + sLineBreak +
      '（未找到 NwInfo\nwinfox86.exe，请运行 scripts\copy_nwinfo_runtime.ps1）';
end;

initialization
  NetInitAdapterInfo(GStaticInfo);

end.
