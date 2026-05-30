unit CpuInfoNwInfo;

{
  通过 NwInfoRunner 调用 nwinfox86.exe --cpu 获取 CPU 信息并解析。
  字段名参考 libnw/cpuid.c PrintCpuInfo / PrintCpuidMachine。
}

interface

uses
  SysUtils, CpuInfoTypes;

function CpuTryQueryFromNwInfo(out AInfo: TCpuStaticInfo): Boolean;
function CpuTryQuerySensorsFromNwInfo(out AInfo: TCpuSensorInfo): Boolean;

implementation

uses
  Windows, Classes, NwInfoRunner, NwInfoParse;

function CpuNwIsCpuDetailLine(const ALine: string): Boolean;
begin
  Result := (Pos('CPU0:', ALine) > 0) or
    ((Length(ALine) >= 4) and (Copy(ALine, 1, 3) = 'CPU') and (Pos(':', ALine) > 0));
end;

procedure CpuParseNwInfoOutput(const AText: string; out AInfo: TCpuStaticInfo);
var
  sl: TStringList;
  i: Integer;
  line, key, val: string;
  inCpuDetail: Boolean;
  cores, threads: Integer;
  speedMhz: DWORD;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  sl := TStringList.Create;
  try
    sl.Text := AText;
    inCpuDetail := False;
    for i := 0 to sl.Count - 1 do
    begin
      line := Trim(sl[i]);
      if line = '' then
        Continue;
      if CpuNwIsCpuDetailLine(line) then
      begin
        inCpuDetail := True;
        Continue;
      end;
      key := NwInfoParseLineKey(line);
      if key = '' then
        Continue;
      val := NwInfoParseLineValue(line);

      if SameText(key, 'CPU Clock (MHz)') then
      begin
        if NwInfoTryParseDword(val, speedMhz) then
          AInfo.CurrentSpeedMhz := speedMhz;
      end
      else if inCpuDetail then
      begin
        if SameText(key, 'Brand') then
        begin
          if AInfo.Brand = '' then
            AInfo.Brand := val;
        end
        else if SameText(key, 'Vendor Name') or SameText(key, 'Vendor') then
        begin
          if AInfo.Vendor = '' then
            AInfo.Vendor := val;
        end
        else if SameText(key, 'Cores') then
        begin
          if NwInfoTryParseInt(val, cores) and (cores > 0) then
            AInfo.PhysicalCores := cores;
        end
        else if SameText(key, 'Logical CPUs') then
        begin
          if NwInfoTryParseInt(val, threads) and (threads > 0) then
            AInfo.LogicalProcessors := threads;
        end
        else if SameText(key, 'Base Clock (MHz)') then
        begin
          if NwInfoTryParseDword(val, speedMhz) then
            AInfo.BaseSpeedMhz := speedMhz;
        end
        else if SameText(key, 'L1 Cache Size') then
        begin
          if AInfo.L1CacheBytes = 0 then
            AInfo.L1CacheBytes := NwInfoParseHumanSizeBytes(val);
        end
        else if SameText(key, 'L2 Cache Size') then
        begin
          if AInfo.L2CacheBytes = 0 then
            AInfo.L2CacheBytes := NwInfoParseHumanSizeBytes(val);
        end
        else if SameText(key, 'L3 Cache Size') then
        begin
          if AInfo.L3CacheBytes = 0 then
            AInfo.L3CacheBytes := NwInfoParseHumanSizeBytes(val);
        end;
      end;
    end;
  finally
    sl.Free;
  end;
end;

function CpuNwInfoHasStaticData(const AInfo: TCpuStaticInfo): Boolean;
begin
  Result := (AInfo.Brand <> '') or (AInfo.PhysicalCores > 0) or (AInfo.LogicalProcessors > 0);
end;

procedure CpuParseSensorOutput(const AText: string; out AInfo: TCpuSensorInfo);
var
  sl: TStringList;
  i: Integer;
  line, key, val: string;
  tempVal, voltVal: Double;
begin
  CpuInitSensorInfo(AInfo);
  sl := TStringList.Create;
  try
    sl.Text := AText;
    for i := 0 to sl.Count - 1 do
    begin
      line := Trim(sl[i]);
      if line = '' then
        Continue;
      key := NwInfoParseLineKey(line);
      if key = '' then
        Continue;
      val := NwInfoParseLineValue(line);
      if SameText(key, 'Core Temperature') then
      begin
        if NwInfoTryParseDouble(val, tempVal) then
          NwInfoUpdateMaxDouble(True, tempVal, AInfo.HasCoreTemp, AInfo.CoreTempC);
      end
      else if SameText(key, 'Package Temperature') then
      begin
        if NwInfoTryParseDouble(val, tempVal) then
          NwInfoUpdateMaxDouble(True, tempVal, AInfo.HasPackageTemp, AInfo.PackageTempC);
      end
      else if SameText(key, 'Core Voltage') then
      begin
        if NwInfoTryParseDouble(val, voltVal) then
          NwInfoUpdateFirstDouble(True, voltVal, AInfo.HasVoltage, AInfo.VoltageV);
      end;
    end;
  finally
    sl.Free;
  end;
end;

function CpuNwInfoHasSensorData(const AInfo: TCpuSensorInfo): Boolean;
begin
  Result := AInfo.HasCoreTemp or AInfo.HasPackageTemp or AInfo.HasVoltage;
end;

function CpuTryQueryFromNwInfo(out AInfo: TCpuStaticInfo): Boolean;
var
  output: string;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  if not NwInfoRunCapture(cNwInfoArgsCpu, output, cNwInfoMarkerCpu) then
    Exit(False);
  CpuParseNwInfoOutput(output, AInfo);
  Result := CpuNwInfoHasStaticData(AInfo);
end;

function CpuTryQuerySensorsFromNwInfo(out AInfo: TCpuSensorInfo): Boolean;
var
  output: string;
begin
  CpuInitSensorInfo(AInfo);
  if not NwInfoRunCapture(cNwInfoArgsCpuSensors, output, cNwInfoMarkerSensors) then
    Exit(False);
  CpuParseSensorOutput(output, AInfo);
  Result := CpuNwInfoHasSensorData(AInfo);
end;

end.
