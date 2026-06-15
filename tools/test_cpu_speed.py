"""Probe CPU base vs current MHz (mirrors CpuInfoNative.pas paths)."""
from __future__ import annotations

import ctypes
import sys
import time
from ctypes import wintypes

SystemProcessorPowerInformation = 11
SystemProcessorPerformanceDistribution = 100
CLogProcHitCountSize = 16


class PROCESSOR_POWER_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("Number", wintypes.DWORD),
        ("MaxMhz", wintypes.ULONG),
        ("CurrentMhz", wintypes.ULONG),
        ("MhzLimit", wintypes.ULONG),
        ("MaxIdleState", wintypes.ULONG),
        ("CurrentIdleState", wintypes.ULONG),
    ]


class SYSTEM_INFO(ctypes.Structure):
    _fields_ = [
        ("wProcessorArchitecture", wintypes.WORD),
        ("wReserved", wintypes.WORD),
        ("dwPageSize", wintypes.DWORD),
        ("lpMinimumApplicationAddress", wintypes.LPVOID),
        ("lpMaximumApplicationAddress", wintypes.LPVOID),
        ("dwActiveProcessorMask", ctypes.c_size_t),
        ("dwNumberOfProcessors", wintypes.DWORD),
        ("dwProcessorType", wintypes.DWORD),
        ("dwAllocationGranularity", wintypes.DWORD),
        ("wProcessorLevel", wintypes.WORD),
        ("wProcessorRevision", wintypes.WORD),
    ]


def nt_success(status: int) -> bool:
    return status >= 0


def load_nt_power():
    for dll_name in ("powrprof.dll", "ntdll.dll"):
        try:
            dll = ctypes.WinDLL(dll_name)
        except OSError:
            continue
        fn = getattr(dll, "CallNtPowerInformation", None)
        if fn is None and dll_name == "ntdll.dll":
            fn = getattr(dll, "NtPowerInformation", None)
        if fn is not None:
            fn.argtypes = [
                wintypes.DWORD,
                wintypes.LPVOID,
                wintypes.ULONG,
                wintypes.LPVOID,
                wintypes.ULONG,
            ]
            fn.restype = wintypes.LONG
            return fn
    raise RuntimeError("NtPowerInformation not found")


def query_power_info(fn) -> list[PROCESSOR_POWER_INFORMATION]:
    si = SYSTEM_INFO()
    ctypes.windll.kernel32.GetSystemInfo(ctypes.byref(si))
    n = si.dwNumberOfProcessors
    buf = (PROCESSOR_POWER_INFORMATION * n)()
    status = fn(
        SystemProcessorPowerInformation,
        None,
        0,
        ctypes.byref(buf),
        ctypes.sizeof(buf),
    )
    if not nt_success(status):
        raise RuntimeError(f"NtPowerInformation failed: 0x{status & 0xFFFFFFFF:08X}")
    return list(buf)


def legacy_avg(entries: list[PROCESSOR_POWER_INFORMATION]) -> int:
    max_cur = 0
    total = 0
    cnt = 0
    for e in entries:
        if e.CurrentMhz > 0:
            total += e.CurrentMhz
            cnt += 1
        if e.CurrentMhz > max_cur:
            max_cur = e.CurrentMhz
    if max_cur > 0:
        return int(max_cur)
    if cnt > 0:
        return int(total // cnt)
    return 0


def load_nt_query():
    ntdll = ctypes.WinDLL("ntdll.dll")
    fn = ntdll.NtQuerySystemInformation
    fn.argtypes = [wintypes.DWORD, wintypes.LPVOID, wintypes.ULONG, ctypes.POINTER(wintypes.ULONG)]
    fn.restype = wintypes.LONG
    return fn


def fetch_perf_distribution(fn) -> bytes | None:
    ret_len = wintypes.ULONG(0)
    fn(SystemProcessorPerformanceDistribution, None, 0, ctypes.byref(ret_len))
    if ret_len.value == 0:
        return None
    buf = (ctypes.c_byte * ret_len.value)()
    status = fn(SystemProcessorPerformanceDistribution, buf, ret_len.value, ctypes.byref(ret_len))
    if not nt_success(status):
        return None
    return bytes(buf)


def calc_speed_from_distribution(cur: bytes, saved: bytes, power: list[PROCESSOR_POWER_INFORMATION]) -> int:
    proc_count = int.from_bytes(cur[0:4], "little")
    if proc_count == 0 or proc_count > len(power):
        return 0
    total_hits = 0
    total_freq = 0
    for proc_idx in range(proc_count):
        cur_off = int.from_bytes(cur[4 + proc_idx * 4 : 8 + proc_idx * 4], "little")
        saved_off = int.from_bytes(saved[4 + proc_idx * 4 : 8 + proc_idx * 4], "little")
        cur_state_count = int.from_bytes(cur[cur_off + 4 : cur_off + 8], "little")
        saved_state_count = int.from_bytes(saved[saved_off + 4 : saved_off + 8], "little")
        if cur_state_count != saved_state_count:
            continue
        max_mhz = power[proc_idx].MaxMhz or power[0].MaxMhz
        base = cur_off + 8
        saved_base = saved_off + 8
        for state_idx in range(cur_state_count):
            off = base + state_idx * CLogProcHitCountSize
            saved_off2 = saved_base + state_idx * CLogProcHitCountSize
            cur_hits = int.from_bytes(cur[off : off + 8], "little")
            saved_hits = int.from_bytes(saved[saved_off2 : saved_off2 + 8], "little")
            hits_delta = cur_hits - saved_hits
            if hits_delta <= 0:
                continue
            pct = cur[off + 8]
            total_hits += hits_delta
            total_freq += hits_delta * pct * max_mhz
    if total_hits <= 0:
        return 0
    return int(total_freq // total_hits // 100)


def burn_cpu(seconds: float = 0.5) -> None:
    end = time.time() + seconds
    x = 1.0
    while time.time() < end:
        x = (x * 1.000001 + 0.000003) % 997.0


def main() -> int:
    power_fn = load_nt_power()
    entries = query_power_info(power_fn)
    print(f"processors={len(entries)}")
    for i, e in enumerate(entries[:4]):
        print(
            f"  core[{i}] MaxMhz={e.MaxMhz} CurrentMhz={e.CurrentMhz} "
            f"MhzLimit={e.MhzLimit}"
        )
    if len(entries) > 4:
        print(f"  ... ({len(entries) - 4} more cores omitted)")

    legacy_idle = legacy_avg(entries)
    print(f"legacy_avg_idle={legacy_idle} MHz")

    nt_query = load_nt_query()
    saved = fetch_perf_distribution(nt_query)
    if saved is None:
        print("perf_distribution=unsupported")
        return 1

    print(f"perf_distribution_bytes={len(saved)}")
    time.sleep(1.0)
    burn_cpu(0.5)
    cur = fetch_perf_distribution(nt_query)
    entries2 = query_power_info(power_fn)
    legacy_load = legacy_avg(entries2)
    dist_speed = calc_speed_from_distribution(cur, saved, entries2) if cur else 0
    print(f"legacy_avg_load={legacy_load} MHz")
    print(f"perf_distribution_speed={dist_speed} MHz")
    if dist_speed > legacy_load:
        print(f"OK dynamic ({dist_speed} > legacy {legacy_load})")
    elif dist_speed > 0:
        print("OK distribution speed available")
    else:
        print("FAIL distribution speed unavailable")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
