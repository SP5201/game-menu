unit GpuInfoNwInfo;

{
  通过 NwInfoRunner 调用 nwinfox86.exe --gpu / --sensors=GPU 获取 GPU 信息并解析。
}

interface

uses
  SysUtils, GpuInfoTypes;

function GpuTryQueryStaticFromNwInfo(out AInfo: TGpuStaticInfo; out ASensors: TGpuSensorInfo): Boolean; overload;
function GpuTryQueryStaticFromNwInfo(out AInfo: TGpuStaticInfo): Boolean; overload;
function GpuTryQuerySensorsFromNwInfo(out AInfo: TGpuSensorInfo): Boolean;

implementation

uses
  Windows, Classes, Math, NwInfoRunner, NwInfoParse;

procedure GpuNwApplyStaticField(const AKey, AVal: string; var AInfo: TGpuStaticInfo);
var
  boolVal: Boolean;
begin
  if SameText(AKey, 'Device') then
  begin
    if AInfo.Device = '' then
      AInfo.Device := AVal;
  end
  else if SameText(AKey, 'Location') then
  begin
    if AInfo.Location = '' then
      AInfo.Location := AVal;
  end
  else if SameText(AKey, 'PnP ID') then
  begin
    if AInfo.PnpId = '' then
      AInfo.PnpId := AVal;
  end
  else if SameText(AKey, 'Integrated GPU') then
  begin
    if NwInfoTryParseBool(AVal, boolVal) then
    begin
      AInfo.HasIntegrated := True;
      AInfo.Integrated := boolVal;
    end;
  end
  else if SameText(AKey, 'PCIe Current Link') then
  begin
    if AInfo.PcieLink = '' then
      AInfo.PcieLink := AVal;
  end;
end;

procedure GpuNwApplySensorField(const AKey, AVal: string; var AInfo: TGpuSensorInfo);
var
  dVal: Double;
  iVal: Integer;
  u64: UInt64;
begin
  if SameText(AKey, 'GPU Utilization') or SameText(AKey, 'Utilization') then
  begin
    if NwInfoTryParsePercent(AVal, dVal) then
    begin
      AInfo.HasUtilization := True;
      AInfo.UtilizationPct := dVal;
    end;
  end
  else if SameText(AKey, 'Temperature (C)') or SameText(AKey, 'Temperature') then
  begin
    if NwInfoTryParseDouble(AVal, dVal) then
    begin
      AInfo.HasTemperature := True;
      AInfo.TemperatureC := dVal;
    end;
  end
  else if SameText(AKey, 'Total Memory') or SameText(AKey, 'Total Dedicated Memory') then
  begin
    if NwInfoTryParseUInt64(AVal, u64) then
    begin
      AInfo.HasTotalMem := True;
      AInfo.TotalMemBytes := u64;
    end;
  end
  else if SameText(AKey, 'Free Memory') or SameText(AKey, 'Free Dedicated Memory') then
  begin
    if NwInfoTryParseUInt64(AVal, u64) then
    begin
      AInfo.HasFreeMem := True;
      AInfo.FreeMemBytes := u64;
    end;
  end
  else if SameText(AKey, 'Memory Usage') then
  begin
    if NwInfoTryParsePercent(AVal, dVal) then
    begin
      AInfo.HasMemUsage := True;
      AInfo.MemUsagePct := EnsureRange(Round(dVal), 0, 100);
    end
    else if NwInfoTryParseInt(AVal, iVal) then
    begin
      AInfo.HasMemUsage := True;
      AInfo.MemUsagePct := EnsureRange(iVal, 0, 100);
    end;
  end
  else if SameText(AKey, 'Power (W)') or SameText(AKey, 'Power') then
  begin
    if NwInfoTryParseDouble(AVal, dVal) then
    begin
      AInfo.HasPower := True;
      AInfo.PowerW := dVal;
    end;
  end
  else if SameText(AKey, 'Frequency (MHz)') or SameText(AKey, 'Frequency') then
  begin
    if NwInfoTryParseDouble(AVal, dVal) then
    begin
      AInfo.HasFrequency := True;
      AInfo.FrequencyMhz := dVal;
    end;
  end
  else if SameText(AKey, 'Memory Frequency (MHz)') or SameText(AKey, 'Memory Frequency') then
  begin
    if NwInfoTryParseDouble(AVal, dVal) then
    begin
      AInfo.HasMemFrequency := True;
      AInfo.MemFrequencyMhz := dVal;
    end;
  end
  else if SameText(AKey, 'Voltage (V)') or SameText(AKey, 'Voltage') then
  begin
    if NwInfoTryParseDouble(AVal, dVal) then
    begin
      AInfo.HasVoltage := True;
      AInfo.VoltageV := dVal;
    end;
  end
  else if SameText(AKey, 'Fan Speed (RPM)') or SameText(AKey, 'Fan Speed') then
  begin
    if NwInfoTryParseInt(AVal, iVal) then
    begin
      AInfo.HasFanSpeed := True;
      AInfo.FanSpeedRpm := iVal;
    end;
  end;
end;

function GpuNwIsDeviceBlockLine(const ALine: string): Boolean;
begin
  Result := Pos('- Device:', ALine) > 0;
end;

function GpuNwIsGpuSensorBlockLine(const ALine: string): Boolean;
var
  key: string;
begin
  key := NwInfoParseLineKey(ALine);
  Result := (Length(key) >= 2) and (key[1] = '''') and (key[Length(key)] = '''');
end;

procedure GpuParseStaticOutput(const AText: string; out AInfo: TGpuStaticInfo; out ASensors: TGpuSensorInfo);
var
  sl: TStringList;
  i: Integer;
  line, key, val: string;
  inGpuSection, inDevice: Boolean;
begin
  GpuInitStaticInfo(AInfo);
  GpuInitSensorInfo(ASensors);
  sl := TStringList.Create;
  try
    sl.Text := AText;
    inGpuSection := False;
    inDevice := False;
    for i := 0 to sl.Count - 1 do
    begin
      line := sl[i];
      if Trim(line) = '' then
        Continue;
      if SameText(Trim(line), 'GPU:') then
      begin
        inGpuSection := True;
        inDevice := False;
        Continue;
      end;
      if not inGpuSection then
        Continue;
      if GpuNwIsDeviceBlockLine(line) then
      begin
        if inDevice and (AInfo.Device <> '') then
          Break;
        inDevice := True;
        Continue;
      end;
      if not inDevice then
        Continue;
      key := NwInfoParseLineKey(line);
      if key = '' then
        Continue;
      val := NwInfoParseLineValue(line);
      GpuNwApplyStaticField(key, val, AInfo);
      GpuNwApplySensorField(key, val, ASensors);
    end;
  finally
    sl.Free;
  end;
end;

procedure GpuParseSensorOutput(const AText: string; out AInfo: TGpuSensorInfo);
var
  sl: TStringList;
  i: Integer;
  line, key, val: string;
  inSensors, inGpuSensors, inDevice: Boolean;
begin
  GpuInitSensorInfo(AInfo);
  sl := TStringList.Create;
  try
    sl.Text := AText;
    inSensors := False;
    inGpuSensors := False;
    inDevice := False;
    for i := 0 to sl.Count - 1 do
    begin
      line := sl[i];
      if Trim(line) = '' then
        Continue;
      if SameText(Trim(line), 'Sensors:') then
      begin
        inSensors := True;
        inGpuSensors := False;
        inDevice := False;
        Continue;
      end;
      if not inSensors then
        Continue;
      if SameText(Trim(line), 'GPU:') then
      begin
        inGpuSensors := True;
        inDevice := False;
        Continue;
      end;
      if not inGpuSensors then
        Continue;
      if GpuNwIsGpuSensorBlockLine(line) then
      begin
        if inDevice then
          Break;
        inDevice := True;
        Continue;
      end;
      if not inDevice then
        Continue;
      key := NwInfoParseLineKey(line);
      if key = '' then
        Continue;
      val := NwInfoParseLineValue(line);
      GpuNwApplySensorField(key, val, AInfo);
    end;
  finally
    sl.Free;
  end;
end;

function GpuNwInfoHasStaticData(const AInfo: TGpuStaticInfo): Boolean;
begin
  Result := AInfo.Device <> '';
end;

function GpuNwInfoHasSensorData(const AInfo: TGpuSensorInfo): Boolean;
begin
  Result := AInfo.HasUtilization or AInfo.HasTemperature or AInfo.HasTotalMem or
    AInfo.HasMemUsage or AInfo.HasPower or AInfo.HasFrequency;
end;

function GpuTryQueryStaticFromNwInfo(out AInfo: TGpuStaticInfo; out ASensors: TGpuSensorInfo): Boolean;
var
  output: string;
begin
  GpuInitStaticInfo(AInfo);
  GpuInitSensorInfo(ASensors);
  if not NwInfoRunCapture(cNwInfoArgsGpu, output, 'GPU:') then
    Exit(False);
  GpuParseStaticOutput(output, AInfo, ASensors);
  Result := GpuNwInfoHasStaticData(AInfo);
end;

function GpuTryQueryStaticFromNwInfo(out AInfo: TGpuStaticInfo): Boolean;
var
  sensors: TGpuSensorInfo;
begin
  Result := GpuTryQueryStaticFromNwInfo(AInfo, sensors);
end;

function GpuTryQuerySensorsFromNwInfo(out AInfo: TGpuSensorInfo): Boolean;
var
  output: string;
begin
  GpuInitSensorInfo(AInfo);
  if not NwInfoRunCapture(cNwInfoArgsGpuSensors, output, cNwInfoMarkerSensors) then
    Exit(False);
  GpuParseSensorOutput(output, AInfo);
  Result := GpuNwInfoHasSensorData(AInfo);
end;

end.
