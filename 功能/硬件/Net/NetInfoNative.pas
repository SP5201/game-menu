unit NetInfoNative;

{
  网卡信息 Native 回退：GetAdaptersAddresses + GetIfEntry2（与 nwinfo network.c 一致）。
}

interface

uses
  Windows, SysUtils, NetInfoTypes;

function NetNativeQueryAdapterInfo: TNetAdapterInfo;
procedure NetNativeRefreshTrafficOctets(AIfIndex: DWORD; var AInfo: TNetAdapterInfo);

implementation

uses
  Winsock2, NetIfTable2;

const
  MAX_ADAPTER_ADDRESS_LENGTH = 8;
  GAA_FLAG_INCLUDE_GATEWAYS = $40;
  cGaaBufferSize = 15000;
  cGaaMaxTries = 3;

type
  PIP_ADAPTER_ADDRESSES = ^IP_ADAPTER_ADDRESSES;
  IP_ADAPTER_ADDRESSES = record
    Length: ULONG;
    IfIndex: DWORD;
    Next: PIP_ADAPTER_ADDRESSES;
    AdapterName: PAnsiChar;
    FirstUnicastAddress: Pointer;
    FirstAnycastAddress: Pointer;
    FirstMulticastAddress: Pointer;
    FirstDnsServerAddress: Pointer;
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

function GetAdaptersAddresses(Family: ULONG; Flags: ULONG; Reserved: Pointer;
  AdapterAddresses: PIP_ADAPTER_ADDRESSES; var SizePointer: ULONG): ULONG; stdcall;
  external 'iphlpapi.dll' name 'GetAdaptersAddresses';

function WideAdapterDesc(P: PWideChar): string;
begin
  if P = nil then
    Result := ''
  else
    Result := Trim(P);
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

function MatchesNwinfoPhysFilter(const A: TNetNwAdapter): Boolean;
begin
  Result := NetIfMatchesPhysFilter(A.IfType, A.Description);
end;

function MatchesNwinfoActiveFilter(const A: TNetNwAdapter): Boolean;
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
    if not MatchesNwinfoActiveFilter(AList[i]) then
      Continue;
    if not MatchesNwinfoPhysFilter(AList[i]) then
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
begin
  NetInitAdapterInfo(Result);
  list := BuildAdapterListFromGaa;
  if PickTooltipAdapterFromGaa(list, adapter) then
    NetFillAdapterInfoFromNative(adapter, Result);
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

end.
