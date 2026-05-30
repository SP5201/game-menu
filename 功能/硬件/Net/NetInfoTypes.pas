unit NetInfoTypes;

interface

uses
  Windows, SysUtils;

const
  cNetDash = '--';

type
  TNetAdapterInfo = record
    IfIndex: DWORD;
    Name: string;
    TypeText: string;
    Mac: string;
    LinkSpeedText: string;
    SentOctetsText: string;
    ReceivedOctetsText: string;
  end;

procedure NetInitAdapterInfo(out AInfo: TNetAdapterInfo);
function NetFormatUInt64Comma(const AValue: UInt64): string;
function NetFormatAdapterTypeFromIfType(const AIfType: DWORD): string;
function NetFormatAdapterTypeFromNwType(const ANwType: string): string;
function NetFormatLinkSpeedMbpsText(const ALinkSpeedBps: UInt64): string;

implementation

const
  IF_TYPE_ETHERNET_CSMACD = 6;
  IF_TYPE_IEEE80211 = 71;

function NetFormatUInt64Comma(const AValue: UInt64): string;
var
  s: string;
  i, digitIndex: Integer;
begin
  s := IntToStr(AValue);
  Result := '';
  digitIndex := 0;
  for i := Length(s) downto 1 do
  begin
    if (digitIndex > 0) and (digitIndex mod 3 = 0) then
      Result := ',' + Result;
    Result := s[i] + Result;
    Inc(digitIndex);
  end;
end;

procedure NetInitAdapterInfo(out AInfo: TNetAdapterInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

function NetFormatAdapterTypeFromIfType(const AIfType: DWORD): string;
begin
  case AIfType of
    IF_TYPE_ETHERNET_CSMACD:
      Result := '有线';
    IF_TYPE_IEEE80211:
      Result := 'WIFI';
  else
    Result := cNetDash;
  end;
end;

function NetFormatAdapterTypeFromNwType(const ANwType: string): string;
var
  s: string;
begin
  s := Trim(ANwType);
  if SameText(s, 'Ethernet') then
    Result := '有线'
  else if (Pos('802.11', s) > 0) or SameText(s, 'IEEE 802.11 Wireless') then
    Result := 'WIFI'
  else if s <> '' then
    Result := s
  else
    Result := cNetDash;
end;

function NetFormatLinkSpeedMbpsText(const ALinkSpeedBps: UInt64): string;
var
  mbps: UInt64;
begin
  if ALinkSpeedBps = 0 then
    Exit(cNetDash);
  mbps := ALinkSpeedBps div 1000000;
  Result := IntToStr(mbps) + ' (Mbps)';
end;

end.
