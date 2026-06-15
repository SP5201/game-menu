"""Test AMD GPU fan RPM via ADL (mirrors GpuInfoVendor.pas)."""
from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes

ADL_OK = 0
AMD_VENDOR_ID = 1002
ADL_MAX_PATH = 256
ADL_PMLOG_MAX_SENSORS = 256
ADL_PMLOG_FAN_RPM = 14
ADL_DL_FANCTRL_SPEED_TYPE_RPM = 2
ADL_DL_FANCTRL_SPEED_TYPE_PERCENT = 1


class ADLFanSpeedValue(ctypes.Structure):
    _fields_ = [
        ("iSize", ctypes.c_int),
        ("iSpeedType", ctypes.c_int),
        ("iFanSpeed", ctypes.c_int),
        ("iFlags", ctypes.c_int),
    ]


class ADLSingleSensorData(ctypes.Structure):
    _fields_ = [("supported", ctypes.c_int), ("value", ctypes.c_int)]


class ADLPMLogDataOutput(ctypes.Structure):
    _fields_ = [
        ("size", ctypes.c_int),
        ("sensors", ADLSingleSensorData * ADL_PMLOG_MAX_SENSORS),
    ]


class ADLAdapterInfo(ctypes.Structure):
    _fields_ = [
        ("iSize", ctypes.c_int),
        ("iAdapterIndex", ctypes.c_int),
        ("strUDID", ctypes.c_char * ADL_MAX_PATH),
        ("iBusNumber", ctypes.c_int),
        ("iDeviceNumber", ctypes.c_int),
        ("iFunctionNumber", ctypes.c_int),
        ("iVendorID", ctypes.c_int),
        ("strAdapterName", ctypes.c_char * ADL_MAX_PATH),
        ("strDisplayName", ctypes.c_char * ADL_MAX_PATH),
        ("iPresent", ctypes.c_int),
        ("iExist", ctypes.c_int),
        ("strDriverPath", ctypes.c_char * ADL_MAX_PATH),
        ("strDriverPathExt", ctypes.c_char * ADL_MAX_PATH),
        ("strPNPString", ctypes.c_char * ADL_MAX_PATH),
        ("iOSDisplayIndex", ctypes.c_int),
    ]


ADL_MAIN_MEMORY_ALLOC = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_int)


def adl_alloc(size: int):
    return ctypes.create_string_buffer(size)


def load_adl():
    for name in ("atiadlxx.dll", "atiadlxy.dll"):
        try:
            return ctypes.WinDLL(name)
        except OSError:
            pass
    raise RuntimeError("ADL DLL not found")


def main() -> int:
    adl = load_adl()
    context = ctypes.c_void_p()

    create = adl.ADL2_Main_Control_Create
    create.argtypes = [ADL_MAIN_MEMORY_ALLOC, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p)]
    create.restype = ctypes.c_int
    if create(ADL_MAIN_MEMORY_ALLOC(adl_alloc), 1, ctypes.byref(context)) != ADL_OK:
        print("FAIL: ADL2_Main_Control_Create")
        return 1

    num = ctypes.c_int(0)
    adl.ADL2_Adapter_NumberOfAdapters_Get(context, ctypes.byref(num))
    print(f"adapters={num.value}")
    if num.value <= 0:
        return 1

    adapters = (ADLAdapterInfo * num.value)()
    for i in range(num.value):
        adapters[i].iSize = ctypes.sizeof(ADLAdapterInfo)
    buf_size = ctypes.sizeof(ADLAdapterInfo) * num.value
    adl.ADL2_Adapter_AdapterInfo_Get(context, ctypes.byref(adapters), buf_size)

    adapter_index = -1
    for i in range(num.value):
        info = adapters[i]
        name = info.strDisplayName.decode("ascii", "ignore").strip()
        print(
            f"  [{info.iAdapterIndex}] vendor=0x{info.iVendorID:04X} "
            f"present={info.iPresent} name={name!r}"
        )
        if info.iPresent and info.iVendorID == AMD_VENDOR_ID and adapter_index < 0:
            adapter_index = info.iAdapterIndex
    if adapter_index < 0:
        for i in range(num.value):
            if adapters[i].iVendorID == AMD_VENDOR_ID:
                adapter_index = adapters[i].iAdapterIndex
                break
    if adapter_index < 0:
        print("FAIL: no AMD adapter")
        return 1
    print(f"selected adapter={adapter_index}")

    pm = ADLPMLogDataOutput()
    pm.size = ctypes.sizeof(ADLPMLogDataOutput)
    pm_get = adl.ADL2_New_QueryPMLogData_Get
    pm_get.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ADLPMLogDataOutput)]
    pm_get.restype = ctypes.c_int
    st = pm_get(context, adapter_index, ctypes.byref(pm))
    print(f"PMLog status={st}")
    if st == ADL_OK:
        fan = pm.sensors[ADL_PMLOG_FAN_RPM]
        print(f"  FAN_RPM supported={fan.supported} value={fan.value}")
        if fan.supported:
            print(f"OK {fan.value}")
        else:
            print("FAIL FAN_RPM not supported")
        for sid in (8, 14, 21, 23, 73):
            s = pm.sensors[sid]
            if s.supported:
                print(f"  sensor[{sid}] value={s.value}")

    od5 = adl.ADL2_Overdrive5_FanSpeed_Get
    od5.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.POINTER(ADLFanSpeedValue),
    ]
    od5.restype = ctypes.c_int
    for thermal in range(4):
        for speed_type, label in (
            (ADL_DL_FANCTRL_SPEED_TYPE_RPM, "RPM"),
            (ADL_DL_FANCTRL_SPEED_TYPE_PERCENT, "PCT"),
        ):
            fan = ADLFanSpeedValue()
            fan.iSize = ctypes.sizeof(ADLFanSpeedValue)
            fan.iSpeedType = speed_type
            st = od5(context, adapter_index, thermal, ctypes.byref(fan))
            if st == ADL_OK and fan.iFanSpeed > 0:
                print(f"OD5 thermal={thermal} {label}={fan.iFanSpeed} flags={fan.iFlags}")

    destroy = adl.ADL2_Main_Control_Destroy
    destroy.argtypes = [ctypes.c_void_p]
    destroy.restype = ctypes.c_int
    destroy(context)
    return 0


if __name__ == "__main__":
    sys.exit(main())
