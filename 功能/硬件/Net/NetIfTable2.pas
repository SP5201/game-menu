unit NetIfTable2;

{
  GetIfTable2 / GetIfEntry2 / GetBestInterface 共用类型与网卡过滤。
  网速采样用 NetIfCollectDefaultRouteBytes（默认路由单网卡）。
}

interface

uses
  Windows, SysUtils;

const
  IF_TYPE_SOFTWARE_LOOPBACK = 24;
  IF_TYPE_PPP = 23;
  IF_TYPE_PROP_VIRTUAL = 53;
  IF_TYPE_TUNNEL = 131;
  IF_TYPE_ETHERNET_CSMACD = 6;
  IF_TYPE_IEEE80211 = 71;
  IfOperStatusUp = 1;
  IfOperStatusDown = 2;
  IfOperStatusTesting = 3;
  IfOperStatusDormant = 5;
  IfOperStatusNotPresent = 6;
  IfOperStatusLowerLayerDown = 7;
  cLinkSpeedUnknown = UInt64($FFFFFFFFFFFFFFFF);
  { 8.8.8.8 / 1.1.1.1，网络字节序，供 GetBestInterface 选取默认路由网卡 }
  cInetDestPublicDnsA: ULONG = $08080808;
  cInetDestPublicDnsB: ULONG = $01010101;

type
  MIB_IF_ROW2 = record
    InterfaceLuid: UInt64;
    InterfaceIndex: DWORD;
    InterfaceGuid: TGUID;
    Alias: array[0..255] of WideChar;
    Description: array[0..255] of WideChar;
    PhysicalAddressLength: DWORD;
    PhysicalAddress: array[0..31] of Byte;
    PermanentPhysicalAddressLength: DWORD;
    PermanentPhysicalAddress: array[0..31] of Byte;
    Mtu: DWORD;
    IfType: DWORD;
    TunnelType: DWORD;
    MediaType: DWORD;
    PhysicalMediumType: DWORD;
    AccessType: DWORD;
    DirectionType: DWORD;
    InterfaceAndOperStatusFlags: Byte;
    OperStatus: DWORD;
    AdminStatus: DWORD;
    MediaConnectState: DWORD;
    NetworkGuid: TGUID;
    ConnectionType: DWORD;
    TransmitLinkSpeed: UInt64;
    ReceiveLinkSpeed: UInt64;
    InOctets: UInt64;
    InUcastPkts: UInt64;
    InNUcastPkts: UInt64;
    InDiscards: UInt64;
    InErrors: UInt64;
    InUnknownProtos: UInt64;
    InUcastOctets: UInt64;
    InMulticastOctets: UInt64;
    InBroadcastOctets: UInt64;
    OutOctets: UInt64;
    OutUcastPkts: UInt64;
    OutNUcastPkts: UInt64;
    OutDiscards: UInt64;
    OutErrors: UInt64;
    OutUcastOctets: UInt64;
    OutMulticastOctets: UInt64;
    OutBroadcastOctets: UInt64;
    OutQLen: UInt64;
  end;

  PMIB_IF_ROW2 = ^MIB_IF_ROW2;
  PMIB_IF_TABLE2 = ^MIB_IF_TABLE2;
  MIB_IF_TABLE2 = record
    NumEntries: DWORD;
    Table: array[0..0] of MIB_IF_ROW2;
  end;

function GetIfTable2(out Table: PMIB_IF_TABLE2): DWORD; stdcall;
  external 'iphlpapi.dll' name 'GetIfTable2';
procedure FreeMibTable(Memory: Pointer); stdcall;
  external 'iphlpapi.dll' name 'FreeMibTable';
function GetIfEntry2(pIfRow: PMIB_IF_ROW2): DWORD; stdcall;
  external 'iphlpapi.dll' name 'GetIfEntry2';
function GetBestInterface(dwDestAddr: ULONG; var pdwBestIfIndex: ULONG): DWORD; stdcall;
  external 'iphlpapi.dll' name 'GetBestInterface';

function NetIfRowDisplayName(const ARow: MIB_IF_ROW2): string;
function NetIfIsExcludedIfType(const AIfType: DWORD): Boolean;
function NetIfIsVirtualAdapterDesc(const ADesc: string): Boolean;
function NetIfMatchesPhysFilter(const AIfType: DWORD; const ADescription: string): Boolean;
function NetIfShouldSumTrafficRow(const ARow: MIB_IF_ROW2): Boolean;
function NetIfNormalizeLinkSpeedBps(const ASpeed: UInt64): UInt64;
function NetIfReadEntry2Row(const AIfIndex: DWORD; out AIfRow: MIB_IF_ROW2): Boolean;
function NetIfGetDefaultRouteIfIndex: DWORD;
function NetIfPickFallbackActiveIfIndex: DWORD;
function NetIfCollectDefaultRouteBytes(out AIfIndex: DWORD; out AInOctets, AOutOctets: UInt64): Boolean;
function NetIfHasPhysActiveAdapter: Boolean;

implementation

function NetIfRowDisplayName(const ARow: MIB_IF_ROW2): string;
begin
  Result := Trim(string(ARow.Description));
  if Result = '' then
    Result := Trim(string(ARow.Alias));
end;

function NetIfIsExcludedIfType(const AIfType: DWORD): Boolean;
begin
  Result := (AIfType = IF_TYPE_SOFTWARE_LOOPBACK) or
    (AIfType = IF_TYPE_PPP) or
    (AIfType = IF_TYPE_PROP_VIRTUAL) or
    (AIfType = IF_TYPE_TUNNEL);
end;

function NetIfIsVirtualAdapterDesc(const ADesc: string): Boolean;
var
  uDesc: string;
begin
  Result := False;
  if ADesc = '' then
    Exit;
  if Copy(ADesc, 1, 38) = 'Microsoft Wi-Fi Direct Virtual Adapter' then
    Exit(True);
  if Copy(ADesc, 1, 16) = 'Bluetooth Device' then
    Exit(True);
  if Copy(ADesc, 1, 31) = 'VMware Virtual Ethernet Adapter' then
    Exit(True);
  if Copy(ADesc, 1, 37) = 'VirtualBox Host-Only Ethernet Adapter' then
    Exit(True);
  if Copy(ADesc, 1, 32) = 'Hyper-V Virtual Ethernet Adapter' then
    Exit(True);
  uDesc := UpperCase(ADesc);
  if Pos('WAN MINIPORT', uDesc) > 0 then
    Exit(True);
  if Pos('TAP-', uDesc) = 1 then
    Exit(True);
  if Pos('TUN ', uDesc) = 1 then
    Exit(True);
  if Pos('WIREGUARD', uDesc) > 0 then
    Exit(True);
  if Pos('TAILSCALE', uDesc) > 0 then
    Exit(True);
  if Pos('ZEROTIER', uDesc) > 0 then
    Exit(True);
  if Pos('ZERO TIER', uDesc) > 0 then
    Exit(True);
  if Pos('OPENVPN', uDesc) > 0 then
    Exit(True);
  if Pos('SOFTETHER', uDesc) > 0 then
    Exit(True);
  if Pos('NPCAP', uDesc) > 0 then
    Exit(True);
end;

function NetIfMatchesPhysFilter(const AIfType: DWORD; const ADescription: string): Boolean;
begin
  Result := False;
  if NetIfIsExcludedIfType(AIfType) then
    Exit;
  if NetIfIsVirtualAdapterDesc(ADescription) then
    Exit;
  Result := True;
end;

function NetIfShouldSumTrafficRow(const ARow: MIB_IF_ROW2): Boolean;
begin
  Result := (ARow.OperStatus = IfOperStatusUp) and
    NetIfMatchesPhysFilter(ARow.IfType, NetIfRowDisplayName(ARow));
end;

function NetIfNormalizeLinkSpeedBps(const ASpeed: UInt64): UInt64;
begin
  if (ASpeed = 0) or (ASpeed = cLinkSpeedUnknown) then
    Result := 0
  else
    Result := ASpeed;
end;

function NetIfReadEntry2Row(const AIfIndex: DWORD; out AIfRow: MIB_IF_ROW2): Boolean;
begin
  FillChar(AIfRow, SizeOf(AIfRow), 0);
  if AIfIndex = 0 then
    Exit(False);
  AIfRow.InterfaceIndex := AIfIndex;
  Result := GetIfEntry2(@AIfRow) = NO_ERROR;
end;

function NetIfPickFallbackActiveIfIndex: DWORD;
var
  buf: PMIB_IF_TABLE2;
  err: DWORD;
  i: DWORD;
  row: PMIB_IF_ROW2;
  p: PByte;
  bestScore: Integer;
  score: Integer;
begin
  Result := 0;
  bestScore := -1;
  buf := nil;
  err := GetIfTable2(buf);
  if err <> NO_ERROR then
    Exit;
  try
    p := PByte(@buf.Table[0]);
    for i := 0 to buf.NumEntries - 1 do
    begin
      row := PMIB_IF_ROW2(p);
      if NetIfShouldSumTrafficRow(row^) then
      begin
        score := 0;
        if row.IfType = IF_TYPE_ETHERNET_CSMACD then
          Inc(score, 4)
        else if row.IfType = IF_TYPE_IEEE80211 then
          Inc(score, 2);
        if score > bestScore then
        begin
          bestScore := score;
          Result := row.InterfaceIndex;
        end;
      end;
      Inc(p, SizeOf(MIB_IF_ROW2));
    end;
  finally
    FreeMibTable(buf);
  end;
end;

function NetIfGetDefaultRouteIfIndex: DWORD;
var
  err: DWORD;
  idx: ULONG;
begin
  idx := 0;
  err := GetBestInterface(cInetDestPublicDnsA, idx);
  if (err = NO_ERROR) and (idx <> 0) then
  begin
    Result := idx;
    Exit;
  end;
  idx := 0;
  err := GetBestInterface(cInetDestPublicDnsB, idx);
  if (err = NO_ERROR) and (idx <> 0) then
    Result := idx
  else
    Result := NetIfPickFallbackActiveIfIndex;
end;

function NetIfCollectDefaultRouteBytes(out AIfIndex: DWORD; out AInOctets, AOutOctets: UInt64): Boolean;
var
  ifRow: MIB_IF_ROW2;
begin
  AIfIndex := 0;
  AInOctets := 0;
  AOutOctets := 0;
  AIfIndex := NetIfGetDefaultRouteIfIndex;
  if AIfIndex = 0 then
    Exit(False);
  if not NetIfReadEntry2Row(AIfIndex, ifRow) then
    Exit(False);
  AInOctets := ifRow.InOctets;
  AOutOctets := ifRow.OutOctets;
  Result := True;
end;

function NetIfHasPhysActiveAdapter: Boolean;
var
  buf: PMIB_IF_TABLE2;
  err: DWORD;
  i: DWORD;
  row: PMIB_IF_ROW2;
  p: PByte;
begin
  Result := False;
  buf := nil;
  err := GetIfTable2(buf);
  if err <> NO_ERROR then
    Exit;
  try
    p := PByte(@buf.Table[0]);
    for i := 0 to buf.NumEntries - 1 do
    begin
      row := PMIB_IF_ROW2(p);
      if NetIfShouldSumTrafficRow(row^) then
        Exit(True);
      Inc(p, SizeOf(MIB_IF_ROW2));
    end;
  finally
    FreeMibTable(buf);
  end;
end;

end.
