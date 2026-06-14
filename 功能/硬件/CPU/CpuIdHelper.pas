unit CpuIdHelper;

{
  CPUID 封装：Win32 / Win64 统一接口。
}

interface

type
  TCpuIdRegs = record
    Eax, Ebx, Ecx, Edx: Cardinal;
  end;

procedure CpuIdLeaf(const AFunc: Cardinal; out ARegs: TCpuIdRegs);
procedure CpuIdLeafEx(const AFunc, ASubFunc: Cardinal; out ARegs: TCpuIdRegs);

implementation

{$IFDEF WIN64}
procedure CpuIdLeafEx(const AFunc, ASubFunc: Cardinal; out ARegs: TCpuIdRegs); assembler;
asm
        push    rbx
        mov     eax, ecx
        mov     ecx, edx
        cpuid
        mov     [r8], eax
        mov     [r8 + 4], ebx
        mov     [r8 + 8], ecx
        mov     [r8 + 12], edx
        pop     rbx
end;
{$ELSE}
procedure CpuIdLeafEx(const AFunc, ASubFunc: Cardinal; out ARegs: TCpuIdRegs); assembler;
asm
  push ebx
  push edi
  mov edi, ARegs
  mov eax, AFunc
  mov ecx, ASubFunc
  cpuid
  mov dword ptr [edi], eax
  mov dword ptr [edi + 4], ebx
  mov dword ptr [edi + 8], ecx
  mov dword ptr [edi + 12], edx
  pop edi
  pop ebx
end;
{$ENDIF}

procedure CpuIdLeaf(const AFunc: Cardinal; out ARegs: TCpuIdRegs);
begin
  CpuIdLeafEx(AFunc, 0, ARegs);
end;

end.
