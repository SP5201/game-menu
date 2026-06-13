unit NetInfo;

{
  网卡悬停提示：GetAdaptersAddresses + GetIfEntry2（发送/接收字节数每次刷新）。
}

interface

uses
  SysUtils, Windows;

const
  cNetDash = '--';

type
  TNetAdapterInfo = record
    IfIndex: DWORD;
    Name: string;
    TypeText: string;
    Mac: string;
    LinkSpeedText: string;
    OperStatusText: string;
    Ipv4Text: string;
    Ipv6Text: string;
    GatewayText: string;
    DnsText: string;
    SentOctetsText: string;
    ReceivedOctetsText: string;
  end;

function NetFormatAdapterTooltip: string;
procedure NetPreloadHintData;

implementation

{$WARN IMPLICIT_STRING_CAST OFF}

uses
  Winapi.Winsock2, Classes, NetIfTable2;

var
  GStaticLoaded: Boolean;
  GStaticInfo: TNetAdapterInfo;
  GStaticLoadLock: TRTLCriticalSection;
  GStaticLoading: Boolean;
  GWsaStarted: Boolean;

const
  IF_TYPE_ETHERNET_CSMACD = 6;
  IF_TYPE_IEEE80211 = 71;
  MAX_ADAPTER_ADDRESS_LENGTH = 8;
  GAA_FLAG_INCLUDE_GATEWAYS = $40;
  cGaaBufferSize = 15000;
  cGaaMaxTries = 3;
  IpDadStateDeprecated = 3;
  IpDadStatePreferred = 4;
  AF_INET = 2;
  AF_INET6 = 23;
  cMaxTooltipDnsServers = 2;

type
  PIP_ADAPTER_ADDRESSES = ^IP_ADAPTER_ADDRESSES;
  PIP_ADAPTER_UNICAST_ADDRESS = ^IP_ADAPTER_UNICAST_ADDRESS;
  PIP_ADAPTER_DNS_SERVER_ADDRESS = ^IP_ADAPTER_DNS_SERVER_ADDRESS;
  PIP_ADAPTER_GATEWAY_ADDRESS = ^IP_ADAPTER_GATEWAY_ADDRESS;
  TSocketAddress = record
    lpSockaddr: Pointer;
    iSockaddrLength: Integer;
  end;
  IP_ADAPTER_UNICAST_ADDRESS = record
    Alignment: Int64;
    Next: PIP_ADAPTER_UNICAST_ADDRESS;
    Address: TSocketAddress;
    PrefixOrigin: Integer;
    SuffixOrigin: Integer;
    DadState: Integer;
    ValidLifetime: ULONG;
    PreferredLifetime: ULONG;
    LeaseLifetime: ULONG;
    OnLinkPrefixLength: Byte;
  end;
  IP_ADAPTER_DNS_SERVER_ADDRESS = record
    Alignment: Int64;
    Next: PIP_ADAPTER_DNS_SERVER_ADDRESS;
    Address: TSocketAddress;
  end;
  IP_ADAPTER_GATEWAY_ADDRESS = record
    Alignment: Int64;
    Next: PIP_ADAPTER_GATEWAY_ADDRESS;
    Address: TSocketAddress;
  end;
  IP_ADAPTER_ADDRESSES = record
    Length: ULONG;
    IfIndex: DWORD;
    Next: PIP_ADAPTER_ADDRESSES;
    AdapterName: PAnsiChar;
    FirstUnicastAddress: PIP_ADAPTER_UNICAST_ADDRESS;
    FirstAnycastAddress: Pointer;
    FirstMulticastAddress: Pointer;
    FirstDnsServerAddress: PIP_ADAPTER_DNS_SERVER_ADDRESS;
    DnsSuffix: PWideChar;
    Description: PWideChar;
    FriendlyName: PWideChar;
    PhysicalAddress: array[0..MAX_ADAPTER_ADDRESS_LENGTH - 1] of Byte;
    PhysicalAddressLength: ULONG;
    Flags: ULONG;
    Mtu: ULONG;
    IfType: ULONG;
    OperStatus: ULONG;
    Ipv6IfIndex: DWORD;
    ZoneIndices: array[0..15] of ULONG;
    FirstPrefix: Pointer;
    TransmitLinkSpeed: UInt64;
    ReceiveLinkSpeed: UInt64;
    FirstWinsServerAddress: Pointer;
    FirstGatewayAddress: PIP_ADAPTER_GATEWAY_ADDRESS;
  end;

  TNetNwAdapter = record
    AdapterKey: string;
    Description: string;
    IfIndex: DWORD;
    IfType: DWORD;
    OperStatus: DWORD;
    Mac: string;
    LinkSpeedBps: UInt64;
  end;

  TNetNwAdapterArray = array of TNetNwAdapter;

  PMIB_IPFORWARDTABLE = ^MIB_IPFORWARDTABLE;
  PMIB_IPFORWARDROW = ^MIB_IPFORWARDROW;
  MIB_IPFORWARDROW = record
    dwForwardDest: DWORD;
    dwForwardMask: DWORD;
    dwForwardPolicy: DWORD;
    dwForwardNextHop: DWORD;
    dwForwardIfIndex: DWORD;
    dwForwardType: DWORD;
    dwForwardProto: DWORD;
    dwForwardAge: DWORD;
    dwForwardNextHopAS: DWORD;
    dwForwardMetric1: DWORD;
    dwForwardMetric2: DWORD;
    dwForwardMetric3: DWORD;
    dwForwardMetric4: DWORD;
    dwForwardMetric5: DWORD;
  end;
  MIB_IPFORWARDTABLE = record
    dwNumEntries: DWORD;
    table: array[0..0] of MIB_IPFORWARDROW;
  end;

function GetAdaptersAddresses(Family: ULONG; Flags: ULONG; Reserved: Pointer;
  AdapterAddresses: PIP_ADAPTER_ADDRESSES; var SizePointer: ULONG): ULONG; stdcall;
  external 'iphlpapi.dll' name 'GetAdaptersAddresses';
function GetIpForwardTable(pIpForwardTable: PMIB_IPFORWARDTABLE; var pdwSize: DWORD;
  bOrder: BOOL): DWORD; stdcall; external 'iphlpapi.dll' name 'GetIpForwardTable';

procedure NetEnsureWsaStarted;
var
  wsaData: TWSAData;
begin
  if GWsaStarted then
    Exit;
  if WSAStartup(MAKEWORD(2, 2), wsaData) = 0 then
    GWsaStarted := True;
end;

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

function NetFormatLinkSpeedMbpsText(const ALinkSpeedBps: UInt64): string;
var
  mbps: UInt64;
begin
  if ALinkSpeedBps = 0 then
    Exit(cNetDash);
  mbps := ALinkSpeedBps div 1000000;
  Result := IntToStr(mbps) + ' (Mbps)';
end;

function NetFormatOperStatusText(const AOperStatus: DWORD): string;
begin
  case AOperStatus of
    IfOperStatusUp:
      Result := '已连接';
    IfOperStatusDown:
      Result := '已断开';
    IfOperStatusTesting:
      Result := '测试中';
    IfOperStatusDormant:
      Result := '休眠';
    IfOperStatusNotPresent:
      Result := '未就绪';
    IfOperStatusLowerLayerDown:
      Result := '下层断开';
  else
    Result := cNetDash;
  end;
end;

function NetAppendCsvText(const ABase, AItem: string): string;
begin
  if AItem = '' then
    Result := ABase
  else if ABase = '' then
    Result := AItem
  else
    Result := ABase + ', ' + AItem;
end;

function NetIsLinkLocalIpv6Text(const AAddr: string): Boolean;
var
  s: string;
  zonePos: Integer;
begin
  s := LowerCase(Trim(AAddr));
  zonePos := Pos('%', s);
  if zonePos > 0 then
    s := Copy(s, 1, zonePos - 1);
  Result := Copy(s, 1, 4) = 'fe80';
end;

function NetIsIpv4Text(const AAddr: string): Boolean;
begin
  Result := (Pos(':', AAddr) = 0) and (Pos('.', AAddr) > 0);
end;

function NetShouldSkipTooltipAddr(const AAddr: string): Boolean;
var
  s: string;
begin
  if Trim(AAddr) = '' then
    Exit(True);
  if NetIsLinkLocalIpv6Text(AAddr) then
    Exit(True);
  s := LowerCase(Trim(AAddr));
  if (Copy(s, 1, 5) = 'fe80:') and (Pos('::', s) = 0) then
    Exit(True);
  Result := False;
end;

function NetCsvContainsAddr(const ABase, AItem: string): Boolean;
var
  parts: TStringList;
  i: Integer;
begin
  Result := False;
  if SameText(Trim(ABase), Trim(AItem)) then
    Exit(True);
  if Trim(ABase) = '' then
    Exit;
  parts := TStringList.Create;
  try
    parts.StrictDelimiter := True;
    parts.Delimiter := ',';
    parts.DelimitedText := ABase;
    for i := 0 to parts.Count - 1 do
      if SameText(Trim(parts[i]), Trim(AItem)) then
        Exit(True);
  finally
    parts.Free;
  end;
end;

function NetTryAppendUniqueAddr(const ABase, AItem: string; AMaxItems: Integer): string;
var
  count: Integer;
  parts: TStringList;
begin
  Result := ABase;
  if NetShouldSkipTooltipAddr(AItem) then
    Exit;
  if NetCsvContainsAddr(ABase, AItem) then
    Exit;
  if AMaxItems > 0 then
  begin
    count := 0;
    if Trim(ABase) <> '' then
    begin
      parts := TStringList.Create;
      try
        parts.StrictDelimiter := True;
        parts.Delimiter := ',';
        parts.DelimitedText := ABase;
        count := parts.Count;
      finally
        parts.Free;
      end;
    end;
    if count >= AMaxItems then
      Exit;
  end;
  Result := NetAppendCsvText(ABase, AItem);
end;

function NetIpv6CandidateScore(const AAddr: string; const AEntry: IP_ADAPTER_UNICAST_ADDRESS): Integer;
begin
  Result := -1;
  if NetIsLinkLocalIpv6Text(AAddr) then
    Exit;
  if AEntry.DadState = IpDadStateDeprecated then
    Exit;
  Result := 1;
  if AEntry.PreferredLifetime > 0 then
    Inc(Result);
  if AEntry.DadState = IpDadStatePreferred then
    Inc(Result, 2);
end;

procedure NetTryPickBestIpv6(const AAddr: string; const AEntry: IP_ADAPTER_UNICAST_ADDRESS;
  var ABest: string; var ABestScore: Integer);
var
  score: Integer;
begin
  score := NetIpv6CandidateScore(AAddr, AEntry);
  if score < 0 then
    Exit;
  if (ABest = '') or (score > ABestScore) then
  begin
    ABest := AAddr;
    ABestScore := score;
  end;
end;

function WSAAddressToStringA(lpsaAddress: Pointer; dwAddressLength: DWORD;
  lpProtocolInfo: Pointer; lpszAddressString: PAnsiChar;
  var lpdwAddressStringLength: DWORD): Integer; stdcall; external 'ws2_32.dll';

function NetFormatIpv4Addr(const AAddr: in_addr): string;
var
  dw: LongWord;
begin
  dw := LongWord(AAddr.S_addr);
  Result := IntToStr(dw and $FF) + '.' +
    IntToStr((dw shr 8) and $FF) + '.' +
    IntToStr((dw shr 16) and $FF) + '.' +
    IntToStr((dw shr 24) and $FF);
end;

function NetFormatSockaddrText(const AAddr: TSocketAddress): string;
type
  PSockAddrIn = ^TSockAddrIn;
  PSockAddrIn6 = ^TSockAddrIn6;
  TSockAddrIn = record
    sin_family: Word;
    sin_port: Word;
    sin_addr: in_addr;
    sin_zero: array[0..7] of Byte;
  end;
  TSockAddrIn6 = record
    sin6_family: Word;
    sin6_port: Word;
    sin6_flowinfo: ULONG;
    sin6_addr: array[0..15] of Byte;
    sin6_scope_id: ULONG;
  end;
var
  sa4: PSockAddrIn;
  addrBuf: array[0..255] of AnsiChar;
  addrLen: DWORD;
  family: Word;
begin
  Result := '';
  if (AAddr.lpSockaddr = nil) or (AAddr.iSockaddrLength <= 0) then
    Exit;
  family := PWord(AAddr.lpSockaddr)^;
  if family = AF_INET then
  begin
    sa4 := PSockAddrIn(AAddr.lpSockaddr);
    if AAddr.iSockaddrLength >= SizeOf(TSockAddrIn) then
      Exit(NetFormatIpv4Addr(sa4^.sin_addr));
    Exit;
  end;
  if family <> AF_INET6 then
    Exit;
  if AAddr.iSockaddrLength < SizeOf(TSockAddrIn6) then
    Exit;
  NetEnsureWsaStarted;
  addrLen := SizeOf(addrBuf);
  FillChar(addrBuf, SizeOf(addrBuf), 0);
  if WSAAddressToStringA(AAddr.lpSockaddr, AAddr.iSockaddrLength, nil, @addrBuf[0], addrLen) = 0 then
    Result := Trim(string(AnsiString(Copy(string(AnsiString(addrBuf)), 1, 64))));
end;

function NetQueryIpv4DefaultGateway(const AIfIndex: DWORD): string;
var
  buf: PMIB_IPFORWARDTABLE;
  bufSize: DWORD;
  err: DWORD;
  i: Integer;
  row: PMIB_IPFORWARDROW;
  rowPtr: PByte;
  bestMetric: DWORD;
  bestHop: DWORD;
  hop: DWORD;
  hopAddr: in_addr;
begin
  Result := '';
  bestMetric := High(DWORD);
  bestHop := 0;
  bufSize := 0;
  err := GetIpForwardTable(nil, bufSize, True);
  if (err <> ERROR_INSUFFICIENT_BUFFER) and (err <> ERROR_BUFFER_OVERFLOW) then
    Exit;
  if bufSize = 0 then
    Exit;
  GetMem(buf, bufSize);
  try
    FillChar(buf^, bufSize, 0);
    if GetIpForwardTable(buf, bufSize, True) <> NO_ERROR then
      Exit;
    rowPtr := PByte(@buf.table[0]);
    for i := 0 to Integer(buf.dwNumEntries) - 1 do
    begin
      row := PMIB_IPFORWARDROW(rowPtr);
      if row^.dwForwardDest <> 0 then
      begin
        Inc(rowPtr, SizeOf(MIB_IPFORWARDROW));
        Continue;
      end;
      if (AIfIndex <> 0) and (row^.dwForwardIfIndex <> AIfIndex) then
      begin
        Inc(rowPtr, SizeOf(MIB_IPFORWARDROW));
        Continue;
      end;
      hop := row^.dwForwardNextHop;
      if hop = 0 then
      begin
        Inc(rowPtr, SizeOf(MIB_IPFORWARDROW));
        Continue;
      end;
      if row^.dwForwardMetric1 < bestMetric then
      begin
        bestMetric := row^.dwForwardMetric1;
        bestHop := hop;
      end;
      Inc(rowPtr, SizeOf(MIB_IPFORWARDROW));
    end;
  finally
    FreeMem(buf);
  end;
  if bestHop <> 0 then
  begin
    hopAddr.S_addr := bestHop;
    Result := NetFormatIpv4Addr(hopAddr);
  end;
end;

function WideAdapterDesc(P: PWideChar): string;
begin
  if P = nil then
    Result := ''
  else
    Result := Trim(P);
end;

procedure NetCollectUnicastAddresses(AFirst: PIP_ADAPTER_UNICAST_ADDRESS;
  var AIpv4, AIpv6: string);
var
  cur: PIP_ADAPTER_UNICAST_ADDRESS;
  addrText: string;
  bestIpv6: string;
  bestIpv6Score: Integer;
begin
  bestIpv6 := '';
  bestIpv6Score := -1;
  cur := AFirst;
  while cur <> nil do
  begin
    addrText := NetFormatSockaddrText(cur^.Address);
    if addrText <> '' then
    begin
      if Pos(':', addrText) > 0 then
        NetTryPickBestIpv6(addrText, cur^, bestIpv6, bestIpv6Score)
      else
        AIpv4 := NetAppendCsvText(AIpv4, addrText);
    end;
    cur := cur^.Next;
  end;
  AIpv6 := bestIpv6;
end;

procedure NetCollectGatewayAddresses(AFirst: PIP_ADAPTER_GATEWAY_ADDRESS;
  var AGateway: string);
var
  cur: PIP_ADAPTER_GATEWAY_ADDRESS;
  addrText: string;
begin
  cur := AFirst;
  while cur <> nil do
  begin
    addrText := NetFormatSockaddrText(cur^.Address);
    if NetIsIpv4Text(addrText) then
    begin
      AGateway := addrText;
      Exit;
    end;
    if (AGateway = '') and (addrText <> '') and not NetShouldSkipTooltipAddr(addrText) then
      AGateway := addrText;
    cur := cur^.Next;
  end;
end;

procedure NetCollectDnsAddresses(AFirst: PIP_ADAPTER_DNS_SERVER_ADDRESS;
  var ADns: string);
var
  cur: PIP_ADAPTER_DNS_SERVER_ADDRESS;
  addrText: string;
  ipv4Dns, ipv6Dns: string;
begin
  cur := AFirst;
  while cur <> nil do
  begin
    addrText := NetFormatSockaddrText(cur^.Address);
    if addrText = '' then
    begin
      cur := cur^.Next;
      Continue;
    end;
    if NetIsIpv4Text(addrText) then
      ipv4Dns := NetTryAppendUniqueAddr(ipv4Dns, addrText, cMaxTooltipDnsServers)
    else if not NetShouldSkipTooltipAddr(addrText) then
      ipv6Dns := NetTryAppendUniqueAddr(ipv6Dns, addrText, 1);
    cur := cur^.Next;
  end;
  ADns := ipv4Dns;
  if ADns = '' then
    ADns := ipv6Dns;
end;

procedure NetFillAddressFields(const AIfIndex: DWORD; const ACur: PIP_ADAPTER_ADDRESSES;
  var AInfo: TNetAdapterInfo);
begin
  if ACur = nil then
    Exit;
  NetCollectUnicastAddresses(ACur^.FirstUnicastAddress, AInfo.Ipv4Text, AInfo.Ipv6Text);
  NetCollectGatewayAddresses(ACur^.FirstGatewayAddress, AInfo.GatewayText);
  if AInfo.GatewayText = '' then
    AInfo.GatewayText := NetQueryIpv4DefaultGateway(AIfIndex);
  NetCollectDnsAddresses(ACur^.FirstDnsServerAddress, AInfo.DnsText);
end;

function FormatMacAddressBytes(const AAddr: array of Byte; ALen: DWORD): string;
var
  i, lim: Integer;
  part: string;
begin
  Result := '';
  if ALen = 0 then
    Exit;
  lim := Integer(ALen);
  if lim > Length(AAddr) then
    lim := Length(AAddr);
  for i := 0 to lim - 1 do
  begin
    part := IntToHex(AAddr[i], 2);
    if Result <> '' then
      Result := Result + '-';
    Result := Result + part;
  end;
end;

function MatchesPhysFilter(const A: TNetNwAdapter): Boolean;
begin
  Result := NetIfMatchesPhysFilter(A.IfType, A.Description);
end;

function MatchesActiveFilter(const A: TNetNwAdapter): Boolean;
begin
  Result := A.OperStatus = IfOperStatusUp;
end;

function ReadIfLinkSpeedBps(const AIfIndex: DWORD; out ALinkSpeedBps: UInt64): Boolean;
var
  ifRow: MIB_IF_ROW2;
  recvSpd, xmitSpd: UInt64;
begin
  ALinkSpeedBps := 0;
  Result := False;
  if not NetIfReadEntry2Row(AIfIndex, ifRow) then
    Exit;
  recvSpd := NetIfNormalizeLinkSpeedBps(ifRow.ReceiveLinkSpeed);
  xmitSpd := NetIfNormalizeLinkSpeedBps(ifRow.TransmitLinkSpeed);
  if recvSpd > 0 then
    ALinkSpeedBps := recvSpd
  else
    ALinkSpeedBps := xmitSpd;
  Result := ALinkSpeedBps > 0;
end;

function ReadIfTrafficOctets(const AIfIndex: DWORD; out AInOctets, AOutOctets: UInt64): Boolean;
var
  ifRow: MIB_IF_ROW2;
begin
  AInOctets := 0;
  AOutOctets := 0;
  Result := False;
  if not NetIfReadEntry2Row(AIfIndex, ifRow) then
    Exit;
  AInOctets := ifRow.InOctets;
  AOutOctets := ifRow.OutOctets;
  Result := True;
end;

function LoadAdaptersAddresses(out Addrs: PIP_ADAPTER_ADDRESSES): DWORD;
var
  bufLen: ULONG;
  iter: Integer;
begin
  Addrs := nil;
  bufLen := cGaaBufferSize;
  for iter := 1 to cGaaMaxTries do
  begin
    Addrs := PIP_ADAPTER_ADDRESSES(AllocMem(bufLen));
    if Addrs = nil then
      Exit(ERROR_NOT_ENOUGH_MEMORY);
    FillChar(Addrs^, bufLen, 0);
    Result := GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_GATEWAYS, nil, Addrs, bufLen);
    if Result = ERROR_BUFFER_OVERFLOW then
    begin
      FreeMem(Pointer(Addrs));
      Addrs := nil;
      Continue;
    end;
    Exit;
  end;
  Result := ERROR_GEN_FAILURE;
end;

function BuildAdapterListFromGaa: TNetNwAdapterArray;
var
  addrs, cur: PIP_ADAPTER_ADDRESSES;
  err: DWORD;
  adapterKey: string;
  adapter: TNetNwAdapter;
  n: Integer;
begin
  SetLength(Result, 0);
  addrs := nil;
  err := LoadAdaptersAddresses(addrs);
  if (err <> NO_ERROR) or (addrs = nil) then
  begin
    if addrs <> nil then
      FreeMem(Pointer(addrs));
    Exit;
  end;
  try
    cur := addrs;
    while cur <> nil do
    begin
      if cur.AdapterName = nil then
      begin
        cur := cur.Next;
        Continue;
      end;
      adapterKey := string(cur.AdapterName);
      FillChar(adapter, SizeOf(adapter), 0);
      adapter.AdapterKey := adapterKey;
      adapter.Description := WideAdapterDesc(cur.Description);
      adapter.IfIndex := cur.IfIndex;
      adapter.IfType := cur.IfType;
      adapter.OperStatus := cur.OperStatus;
      adapter.Mac := FormatMacAddressBytes(cur.PhysicalAddress, cur.PhysicalAddressLength);
      if not ReadIfLinkSpeedBps(cur.IfIndex, adapter.LinkSpeedBps) then
        adapter.LinkSpeedBps := 0;
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := adapter;
      cur := cur.Next;
    end;
  finally
    FreeMem(Pointer(addrs));
  end;
end;

function PickTooltipAdapterFromGaa(const AList: TNetNwAdapterArray; out AAdapter: TNetNwAdapter): Boolean;
var
  i: Integer;
  score, bestScore: UInt64;
  pickedIdx: Integer;
  defIfIdx: DWORD;
begin
  Result := False;
  FillChar(AAdapter, SizeOf(AAdapter), 0);
  defIfIdx := NetIfGetDefaultRouteIfIndex;
  if defIfIdx <> 0 then
  begin
    for i := 0 to High(AList) do
      if AList[i].IfIndex = defIfIdx then
      begin
        AAdapter := AList[i];
        Exit(True);
      end;
  end;
  pickedIdx := -1;
  bestScore := 0;
  for i := 0 to High(AList) do
  begin
    if not MatchesActiveFilter(AList[i]) then
      Continue;
    if not MatchesPhysFilter(AList[i]) then
      Continue;
    score := 0;
    if AList[i].IfType = IF_TYPE_ETHERNET_CSMACD then
      Inc(score, 4)
    else if AList[i].IfType = IF_TYPE_IEEE80211 then
      Inc(score, 2);
    if (pickedIdx < 0) or (score > bestScore) then
    begin
      bestScore := score;
      pickedIdx := i;
    end;
  end;
  if pickedIdx >= 0 then
  begin
    AAdapter := AList[pickedIdx];
    Result := True;
  end;
end;

procedure NetFillAdapterInfoFromNative(const AAdapter: TNetNwAdapter; var AInfo: TNetAdapterInfo);
var
  inOct, outOct: UInt64;
begin
  NetInitAdapterInfo(AInfo);
  AInfo.IfIndex := AAdapter.IfIndex;
  if AAdapter.Description <> '' then
    AInfo.Name := AAdapter.Description
  else if AAdapter.AdapterKey <> '' then
    AInfo.Name := AAdapter.AdapterKey
  else
    AInfo.Name := cNetDash;
  AInfo.TypeText := NetFormatAdapterTypeFromIfType(AAdapter.IfType);
  AInfo.OperStatusText := NetFormatOperStatusText(AAdapter.OperStatus);
  if AAdapter.Mac <> '' then
    AInfo.Mac := AAdapter.Mac
  else
    AInfo.Mac := cNetDash;
  AInfo.LinkSpeedText := NetFormatLinkSpeedMbpsText(AAdapter.LinkSpeedBps);
  if ReadIfTrafficOctets(AAdapter.IfIndex, inOct, outOct) then
  begin
    AInfo.SentOctetsText := NetFormatUInt64Comma(outOct);
    AInfo.ReceivedOctetsText := NetFormatUInt64Comma(inOct);
  end
  else
  begin
    AInfo.SentOctetsText := cNetDash;
    AInfo.ReceivedOctetsText := cNetDash;
  end;
end;

function NetNativeQueryAdapterInfo: TNetAdapterInfo;
var
  list: TNetNwAdapterArray;
  adapter: TNetNwAdapter;
  addrs, cur: PIP_ADAPTER_ADDRESSES;
  err: DWORD;
begin
  NetInitAdapterInfo(Result);
  list := BuildAdapterListFromGaa;
  if not PickTooltipAdapterFromGaa(list, adapter) then
    Exit;
  NetFillAdapterInfoFromNative(adapter, Result);
  addrs := nil;
  err := LoadAdaptersAddresses(addrs);
  if err <> NO_ERROR then
    Exit;
  try
    cur := addrs;
    while cur <> nil do
    begin
      if cur^.IfIndex = adapter.IfIndex then
      begin
        NetFillAddressFields(adapter.IfIndex, cur, Result);
        Break;
      end;
      cur := cur^.Next;
    end;
  finally
    if addrs <> nil then
      FreeMem(Pointer(addrs));
  end;
end;

procedure NetNativeRefreshTrafficOctets(AIfIndex: DWORD; var AInfo: TNetAdapterInfo);
var
  inOct, outOct: UInt64;
  ifIdx: DWORD;
begin
  ifIdx := AIfIndex;
  if ifIdx = 0 then
    ifIdx := AInfo.IfIndex;
  if ReadIfTrafficOctets(ifIdx, inOct, outOct) then
  begin
    AInfo.SentOctetsText := NetFormatUInt64Comma(outOct);
    AInfo.ReceivedOctetsText := NetFormatUInt64Comma(inOct);
  end;
end;

procedure NetLoadStaticInfo;
begin
  if GStaticLoaded then
    Exit;
  EnterCriticalSection(GStaticLoadLock);
  try
    if GStaticLoaded then
      Exit;
    if GStaticLoading then
      Exit;
    GStaticLoading := True;
    try
      GStaticInfo := NetNativeQueryAdapterInfo;
      GStaticLoaded := True;
    finally
      GStaticLoading := False;
    end;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

procedure NetPreloadHintData;
begin
  NetLoadStaticInfo;
end;

function NetFormatAdapterTooltip: string;
var
  info: TNetAdapterInfo;
begin
  NetLoadStaticInfo;
  if not GStaticLoaded then
    Exit('（网卡信息加载中…）');
  EnterCriticalSection(GStaticLoadLock);
  try
    info := GStaticInfo;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
  NetNativeRefreshTrafficOctets(info.IfIndex, info);

  if info.Name = '' then
    info.Name := cNetDash;
  if info.TypeText = '' then
    info.TypeText := cNetDash;
  if info.Mac = '' then
    info.Mac := cNetDash;
  if info.LinkSpeedText = '' then
    info.LinkSpeedText := cNetDash;
  if info.OperStatusText = '' then
    info.OperStatusText := cNetDash;
  if info.Ipv4Text = '' then
    info.Ipv4Text := cNetDash;
  if info.Ipv6Text = '' then
    info.Ipv6Text := cNetDash;
  if info.GatewayText = '' then
    info.GatewayText := cNetDash;
  if info.DnsText = '' then
    info.DnsText := cNetDash;
  if info.SentOctetsText = '' then
    info.SentOctetsText := cNetDash;
  if info.ReceivedOctetsText = '' then
    info.ReceivedOctetsText := cNetDash;

  Result := '网卡名：' + info.Name + sLineBreak +
    '网卡类型：' + info.TypeText + sLineBreak +
    '连接状态：' + info.OperStatusText + sLineBreak +
    'IPv4：' + info.Ipv4Text + sLineBreak +
    'IPv6：' + info.Ipv6Text + sLineBreak +
    '网关：' + info.GatewayText + sLineBreak +
    'DNS：' + info.DnsText + sLineBreak +
    '网卡MAC：' + info.Mac + sLineBreak +
    '链接速度：' + info.LinkSpeedText + sLineBreak +
    '发送的字节数：' + info.SentOctetsText + sLineBreak +
    '接收的字节数：' + info.ReceivedOctetsText;
end;

initialization
  InitializeCriticalSection(GStaticLoadLock);
  NetInitAdapterInfo(GStaticInfo);
  GWsaStarted := False;

finalization
  DeleteCriticalSection(GStaticLoadLock);
  if GWsaStarted then
    WSACleanup;

end.
