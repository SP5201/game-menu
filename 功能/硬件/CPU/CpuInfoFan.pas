unit CpuInfoFan;

{
  CPU 风扇转速：参考 LibreHardwareMonitor LpcIO，经 PawnIO LpcIO 模块扫描 Super I/O。
  支持 Nuvoton NCT67xx（含 679x 13 位 tach）、NCT668x（Intel 600+ 新板常用）与 ITE IT87xx。
}

interface

uses
  CpuInfo;

function CpuFanQueryRpm(out ARpm: Integer): Boolean;
function CpuFanLastDiag: string;

implementation

uses
  Windows, SysUtils, PawnIoClient;

const
  cIsaBusMutex = 'Global\Access_ISABUS.HTP.Method';
  cFanTachDivisor = 1350000;
  cNct679MinFanCount = $15;
  cNct679MaxFanCount = $1FFF;
  cIt87MinTach = $3F;

  cSioRegDevice = $07;
  cSioRegChipId = $20;
  cSioRegChipRev = $21;
  cSioRegBaseAddr = $60;
  cSioRegIt87Version = $22;
  cSioLdnHwMonitorNuvoton = $0B;
  cSioLdnHwMonitorIt87 = $04;
  cNctBankSelectReg = $4E;
  cNuvotonIoSpaceLockReg = $28;
  cIt87CfgCtrlReg = $02;

  cNct679FanCountRegs: array[0..5] of Word = ($4B0, $4B2, $4B4, $4B6, $4B8, $4BA);
  cNct6687FanRpmRegs: array[0..16] of Word = (
    $140, $142, $144, $146, $148, $14A, $14C, $14E,
    $150, $152, $154, $156, $158, $15A, $15C, $15E, $852);
  cNct6687InitReg = $180;
  cIt87FanTachRegs: array[0..2] of Byte = ($0D, $0E, $0F);
  cIt87FanTachExtRegs: array[0..2] of Byte = ($18, $19, $1A);

type
  TCpuFanSioKind = (fskNone, fskNct679x, fskNct677x, fskNct6687, fskIt87);

  TCpuFanSioContext = record
    Kind: TCpuFanSioKind;
    BarBase: Word;
    ChipId: Word;
    Revision: Byte;
    It87Version: Byte;
  end;

var
  GIsaBusMutex: THandle = 0;
  GLastDiag: string = '';

procedure CpuFanDiag(const AText: string);
begin
  if GLastDiag <> '' then
    GLastDiag := GLastDiag + '; ';
  GLastDiag := GLastDiag + AText;
end;

function CpuFanLastDiag: string;
begin
  Result := GLastDiag;
end;

procedure CpuFanReleaseIsaBus;
begin
  if GIsaBusMutex <> 0 then
  begin
    ReleaseMutex(GIsaBusMutex);
    GIsaBusMutex := 0;
  end;
end;

function CpuFanAcquireIsaBus: Boolean;
begin
  if GIsaBusMutex <> 0 then
  begin
    Result := True;
    Exit;
  end;
  GIsaBusMutex := CreateMutexW(nil, False, PWideChar(cIsaBusMutex));
  if GIsaBusMutex = 0 then
  begin
    Result := True;
    Exit;
  end;
  case WaitForSingleObject(GIsaBusMutex, 500) of
    WAIT_OBJECT_0, WAIT_ABANDONED:
      Result := True;
  else
    begin
      CloseHandle(GIsaBusMutex);
      GIsaBusMutex := 0;
      Result := True;
    end;
  end;
end;

function CpuFanLpcSelectSlot(ASlot: Integer): Boolean;
begin
  Result := PawnIoLpcRun('ioctl_select_slot', [UInt64(ASlot)]);
end;

function CpuFanLpcPioOut(APort: Word; AValue: Byte): Boolean;
begin
  Result := PawnIoLpcExecute2('ioctl_pio_outb', UInt64(APort), AValue);
end;

function CpuFanLpcSuperInB(AReg: Byte; out AValue: Byte): Boolean;
var
  raw: UInt64;
begin
  AValue := 0;
  Result := PawnIoLpcExecute1('ioctl_superio_inb', AReg, raw);
  if Result then
    AValue := Byte(raw and $FF);
end;

function CpuFanLpcSuperInW(AReg: Byte; out AValue: Word): Boolean;
var
  raw: UInt64;
begin
  AValue := 0;
  Result := PawnIoLpcExecute1('ioctl_superio_inw', AReg, raw);
  if Result then
    AValue := Word(raw and $FFFF);
end;

procedure CpuFanLpcSuperOutB(AReg, AValue: Byte);
begin
  PawnIoLpcExecute2('ioctl_superio_outb', AReg, AValue);
end;

function CpuFanLpcPioInB(APort: Word; out AValue: Byte): Boolean;
begin
  Result := PawnIoLpcPioInB(APort, AValue);
end;

function CpuFanNormalizeBar(ABar: Word): Word;
begin
  Result := ABar;
  if (Result and $07) = $05 then
    Result := Result and $FFF8;
end;

function CpuFanIsValidBar(ABar: Word): Boolean;
begin
  ABar := CpuFanNormalizeBar(ABar);
  Result := (ABar >= $100) and ((ABar and $F007) = 0);
end;

function CpuFanNuvotonEnter(ASlot: Integer): Boolean;
var
  enterPort: Word;
begin
  enterPort := Word($2E + (ASlot shl 5));
  Result := CpuFanLpcPioOut(enterPort, $87) and
    CpuFanLpcPioOut(enterPort, $87);
end;

procedure CpuFanNuvotonExit(ASlot: Integer);
begin
  CpuFanLpcPioOut(Word($2E + (ASlot shl 5)), $AA);
end;

function CpuFanIt87Enter(ASlot: Integer): Boolean;
var
  regPort: Word;
  tail: Byte;
begin
  regPort := Word($2E + (ASlot shl 5));
  if regPort = $4E then
    tail := $AA
  else
    tail := $55;
  Result := CpuFanLpcPioOut(regPort, $87) and
    CpuFanLpcPioOut(regPort, $01) and
    CpuFanLpcPioOut(regPort, $55) and
    CpuFanLpcPioOut(regPort, tail);
end;

procedure CpuFanIt87Exit(ASlot: Integer);
var
  regPort, valPort: Word;
begin
  regPort := Word($2E + (ASlot shl 5));
  if regPort = $4E then
    Exit;
  valPort := regPort + 1;
  CpuFanLpcPioOut(regPort, cIt87CfgCtrlReg);
  CpuFanLpcPioOut(valPort, cIt87CfgCtrlReg);
end;

function CpuFanClassifyNuvoton(AChipId, ARev: Byte): TCpuFanSioKind;
begin
  case AChipId of
    $C7:
      if ARev = $32 then
        Result := fskNct6687
      else
        Result := fskNct679x;
    $D4, $D5:
      Result := fskNct6687;
    $C8, $C9, $D1, $D3, $D8, $C5, $C4, $C3:
      Result := fskNct679x;
    $B4, $B0, $A0, $A5, $88, $82, $52:
      Result := fskNct677x;
  else
    if (AChipId >= $C2) and (AChipId <= $D8) then
      Result := fskNct679x
    else if (AChipId >= $50) and (AChipId <= $B4) then
      Result := fskNct677x
    else
      Result := fskNone;
  end;
end;

function CpuFanIsIt87ChipId(AChipId: Word): Boolean;
begin
  Result := (AChipId <> 0) and (AChipId <> $FFFF);
  if not Result then
    Exit;
  case AChipId of
    $8613, $8620, $8625, $8628, $8631, $8638, $8665, $8655,
    $8686, $8688, $8689, $8696, $8705, $8712, $8716, $8718,
    $8720, $8721, $8726, $8728, $8771, $8772, $8790, $8733, $8695:
      Result := True;
  else
    Result := ((AChipId shr 12) = $868) or ((AChipId shr 12) = $869) or
      ((AChipId shr 12) = $870) or ((AChipId shr 12) = $871) or
      ((AChipId shr 12) = $872) or ((AChipId shr 12) = $877) or
      ((AChipId shr 12) = $879);
  end;
end;

function CpuFanNctBarReadByte(ABar: Word; AAddress: Word; out AValue: Byte): Boolean;
var
  bank, reg: Byte;
begin
  AValue := 0;
  Result := False;
  bank := Byte(AAddress shr 8);
  reg := Byte(AAddress and $FF);
  if not CpuFanLpcPioOut(ABar + 5, cNctBankSelectReg) then
    Exit;
  if not CpuFanLpcPioOut(ABar + 6, bank) then
    Exit;
  if not CpuFanLpcPioOut(ABar + 5, reg) then
    Exit;
  Result := CpuFanLpcPioInB(ABar + 6, AValue);
end;

function CpuFanIt87BarReadByte(ABar: Word; ARegister: Byte; out AValue: Byte): Boolean;
begin
  AValue := 0;
  Result := False;
  if not CpuFanLpcPioOut(ABar + 5, ARegister) then
    Exit;
  Result := CpuFanLpcPioInB(ABar + 6, AValue);
end;

function CpuFanRpmFrom13BitCount(ACount: Integer): Integer;
begin
  Result := 0;
  if (ACount >= cNct679MinFanCount) and (ACount < cNct679MaxFanCount) then
    Result := cFanTachDivisor div ACount;
end;

function CpuFanRpmFrom16BitTach(ATach: Integer): Integer;
begin
  Result := 0;
  if (ATach > cIt87MinTach) and (ATach < $FFFF) then
    Result := cFanTachDivisor div (ATach * 2);
end;

function CpuFanNctBarWriteByte(ABar: Word; AAddress: Word; AValue: Byte): Boolean;
var
  bank, reg: Byte;
begin
  Result := False;
  bank := Byte(AAddress shr 8);
  reg := Byte(AAddress and $FF);
  if not CpuFanLpcPioOut(ABar + 5, cNctBankSelectReg) then
    Exit;
  if not CpuFanLpcPioOut(ABar + 6, bank) then
    Exit;
  if not CpuFanLpcPioOut(ABar + 5, reg) then
    Exit;
  Result := CpuFanLpcPioOut(ABar + 6, AValue);
end;

procedure CpuFanInitNct6687(ABar: Word);
var
  data: Byte;
begin
  if not CpuFanNctBarReadByte(ABar, cNct6687InitReg, data) then
    Exit;
  if (data and $80) = 0 then
    CpuFanNctBarWriteByte(ABar, cNct6687InitReg, data or $80);
end;

function CpuFanReadNct6687Fans(const ACtx: TCpuFanSioContext; out AMaxRpm: Integer): Boolean;
var
  i: Integer;
  hi, lo: Byte;
  count, rpm: Integer;
begin
  Result := False;
  AMaxRpm := 0;
  CpuFanInitNct6687(ACtx.BarBase);
  for i := Low(cNct6687FanRpmRegs) to High(cNct6687FanRpmRegs) do
  begin
    if not CpuFanNctBarReadByte(ACtx.BarBase, cNct6687FanRpmRegs[i], hi) then
      Continue;
    if not CpuFanNctBarReadByte(ACtx.BarBase, cNct6687FanRpmRegs[i] + 1, lo) then
      Continue;
    if (hi = $FF) and (lo = $F8) then
      Continue;
    count := (Integer(hi) shl 5) or (Integer(lo) and $1F);
    rpm := CpuFanRpmFrom13BitCount(count);
    if rpm > AMaxRpm then
    begin
      AMaxRpm := rpm;
      Result := True;
    end;
  end;
end;

function CpuFanReadNct679xFans(const ACtx: TCpuFanSioContext; out AMaxRpm: Integer): Boolean;
var
  i: Integer;
  hi, lo: Byte;
  count, rpm: Integer;
begin
  Result := False;
  AMaxRpm := 0;
  for i := Low(cNct679FanCountRegs) to High(cNct679FanCountRegs) do
  begin
    if not CpuFanNctBarReadByte(ACtx.BarBase, cNct679FanCountRegs[i], hi) then
      Continue;
    if not CpuFanNctBarReadByte(ACtx.BarBase, cNct679FanCountRegs[i] + 1, lo) then
      Continue;
    count := (Integer(hi) shl 5) or (Integer(lo) and $1F);
    rpm := CpuFanRpmFrom13BitCount(count);
    if rpm > AMaxRpm then
    begin
      AMaxRpm := rpm;
      Result := True;
    end;
  end;
end;

function CpuFanReadNct677xFans(const ACtx: TCpuFanSioContext; out AMaxRpm: Integer): Boolean;
var
  i: Integer;
  addr: Word;
  hi, lo: Byte;
  value, rpm, count: Integer;
begin
  Result := False;
  AMaxRpm := 0;
  for i := 0 to 4 do
  begin
    addr := Word($656 + (i shl 1));
    if not CpuFanNctBarReadByte(ACtx.BarBase, addr, hi) then
      Continue;
    if not CpuFanNctBarReadByte(ACtx.BarBase, addr + 1, lo) then
      Continue;
    value := (Integer(hi) shl 8) or lo;
    if value <= 0 then
      Continue;
    if value > cFanTachDivisor div $FFFF then
      rpm := value
    else
    begin
      count := (Integer(hi) shl 5) or (Integer(lo) and $1F);
      rpm := CpuFanRpmFrom13BitCount(count);
    end;
    if rpm > AMaxRpm then
    begin
      AMaxRpm := rpm;
      Result := True;
    end;
  end;
end;

function CpuFanReadIt87Fans(const ACtx: TCpuFanSioContext; out AMaxRpm: Integer): Boolean;
var
  i: Integer;
  lo, hi: Byte;
  tach, rpm: Integer;
  use16Bit: Boolean;
begin
  Result := False;
  AMaxRpm := 0;
  use16Bit := (ACtx.ChipId <> $8705) or (ACtx.It87Version >= 3);
  if not use16Bit then
    Exit;
  for i := Low(cIt87FanTachRegs) to High(cIt87FanTachRegs) do
  begin
    if not CpuFanIt87BarReadByte(ACtx.BarBase, cIt87FanTachRegs[i], lo) then
      Continue;
    if not CpuFanIt87BarReadByte(ACtx.BarBase, cIt87FanTachExtRegs[i], hi) then
      Continue;
    tach := Integer(lo) or (Integer(hi) shl 8);
    rpm := CpuFanRpmFrom16BitTach(tach);
    if rpm > AMaxRpm then
    begin
      AMaxRpm := rpm;
      Result := True;
    end;
  end;
  if Result then
    Exit;
  for i := 0 to 2 do
  begin
    if not CpuFanIt87BarReadByte(ACtx.BarBase, Byte($80 + i * 2), lo) then
      Continue;
    if not CpuFanIt87BarReadByte(ACtx.BarBase, Byte($81 + i * 2), hi) then
      Continue;
    tach := Integer(lo) or (Integer(hi) shl 8);
    rpm := CpuFanRpmFrom16BitTach(tach);
    if rpm > AMaxRpm then
    begin
      AMaxRpm := rpm;
      Result := True;
    end;
  end;
end;

procedure CpuFanNuvotonDisableIoLock;
var
  options: Byte;
begin
  if CpuFanLpcSuperInB(cNuvotonIoSpaceLockReg, options) then
  begin
    if (options and $10) <> 0 then
      CpuFanLpcSuperOutB(cNuvotonIoSpaceLockReg, options and not $10);
  end;
end;

function CpuFanDetectNuvoton(ASlot: Integer; out ACtx: TCpuFanSioContext): Boolean;
var
  chipId, rev: Byte;
  bar, verify: Word;
begin
  FillChar(ACtx, SizeOf(ACtx), 0);
  Result := False;
  if not CpuFanLpcSelectSlot(ASlot) then
    Exit;
  if not CpuFanNuvotonEnter(ASlot) then
    Exit;
  try
    if not CpuFanLpcSuperInB(cSioRegChipId, chipId) then
      Exit;
    if not CpuFanLpcSuperInB(cSioRegChipRev, rev) then
      Exit;
    if (chipId = 0) or (chipId = $FF) then
      Exit;
    ACtx.Kind := CpuFanClassifyNuvoton(chipId, rev);
    if ACtx.Kind = fskNone then
      Exit;
    if not PawnIoLpcExecute0('ioctl_find_bars') then
      Exit;
    CpuFanLpcSuperOutB(cSioRegDevice, cSioLdnHwMonitorNuvoton);
    if not CpuFanLpcSuperInW(cSioRegBaseAddr, bar) then
      Exit;
    if not CpuFanLpcSuperInW(cSioRegBaseAddr, verify) then
      Exit;
    if (bar <> verify) or not CpuFanIsValidBar(bar) then
      Exit;
    bar := CpuFanNormalizeBar(bar);
    if ACtx.Kind = fskNct679x then
      CpuFanNuvotonDisableIoLock;
    ACtx.BarBase := bar;
    ACtx.ChipId := Word(chipId shl 8) or rev;
    ACtx.Revision := rev;
    Result := True;
    CpuFanDiag(Format('Nuvoton slot%d bar=$%x id=$%x', [ASlot, bar, chipId]));
  finally
    CpuFanNuvotonExit(ASlot);
  end;
end;

function CpuFanDetectIt87(ASlot: Integer; out ACtx: TCpuFanSioContext): Boolean;
var
  chipId: Word;
  bar, barVerify: Word;
  version: Byte;
begin
  FillChar(ACtx, SizeOf(ACtx), 0);
  Result := False;
  if not CpuFanLpcSelectSlot(ASlot) then
    Exit;
  if not CpuFanIt87Enter(ASlot) then
    Exit;
  try
    if not CpuFanLpcSuperInW(cSioRegChipId, chipId) then
      Exit;
    if not CpuFanIsIt87ChipId(chipId) then
      Exit;
    if not PawnIoLpcExecute0('ioctl_find_bars') then
      Exit;
    CpuFanLpcSuperOutB(cSioRegDevice, cSioLdnHwMonitorIt87);
    if not CpuFanLpcSuperInW(cSioRegBaseAddr, bar) then
      Exit;
    if not CpuFanLpcSuperInW(cSioRegBaseAddr, barVerify) then
      Exit;
    if (bar <> barVerify) or not CpuFanIsValidBar(bar) then
      Exit;
    bar := CpuFanNormalizeBar(bar);
    if not CpuFanLpcSuperInB(cSioRegIt87Version, version) then
      version := 0;
    ACtx.Kind := fskIt87;
    ACtx.BarBase := bar;
    ACtx.ChipId := chipId;
    ACtx.It87Version := version and $0F;
    Result := True;
    CpuFanDiag(Format('ITE slot%d bar=$%x id=$%x', [ASlot, bar, chipId]));
  finally
    CpuFanIt87Exit(ASlot);
  end;
end;

function CpuFanTrySlot(ASlot: Integer; out ARpm: Integer): Boolean;
var
  ctx: TCpuFanSioContext;
  rpm: Integer;
  maxRpm: Integer;
begin
  Result := False;
  ARpm := 0;
  maxRpm := 0;
  if CpuFanDetectIt87(ASlot, ctx) then
  begin
    if CpuFanReadIt87Fans(ctx, rpm) and (rpm > maxRpm) then
      maxRpm := rpm;
  end;
  if CpuFanDetectNuvoton(ASlot, ctx) then
  begin
    case ctx.Kind of
      fskNct6687:
        begin
          if CpuFanReadNct6687Fans(ctx, rpm) and (rpm > maxRpm) then
            maxRpm := rpm;
        end;
      fskNct679x:
        begin
          if CpuFanReadNct679xFans(ctx, rpm) and (rpm > maxRpm) then
            maxRpm := rpm;
        end;
      fskNct677x:
        begin
          if CpuFanReadNct677xFans(ctx, rpm) and (rpm > maxRpm) then
            maxRpm := rpm;
        end;
    end;
  end;
  if maxRpm > 0 then
  begin
    ARpm := maxRpm;
    Result := True;
    CpuFanDiag(Format('slot%d=%dRPM', [ASlot, maxRpm]));
  end;
end;

function CpuFanQueryRpm(out ARpm: Integer): Boolean;
var
  slot: Integer;
  slotRpm, maxRpm: Integer;
begin
  ARpm := 0;
  maxRpm := 0;
  Result := False;
  GLastDiag := '';
  if not PawnIoLpcAvailable then
  begin
    CpuFanDiag('LPC不可用:' + PawnIoLoadFailureDetail);
    Exit;
  end;
  if not CpuFanAcquireIsaBus then
  begin
    CpuFanDiag('ISA互斥量超时');
    Exit;
  end;
  try
    for slot := 0 to 1 do
    begin
      if CpuFanTrySlot(slot, slotRpm) and (slotRpm > maxRpm) then
        maxRpm := slotRpm;
    end;
    if maxRpm > 0 then
    begin
      ARpm := maxRpm;
      Result := True;
    end;
  finally
    CpuFanReleaseIsaBus;
  end;
end;

end.
