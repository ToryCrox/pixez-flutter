#include "window_placement.h"

// 从注册表加载保存的窗口位置信息
bool WindowPlacementHelper::LoadPlacement(WINDOWPLACEMENT& placement) {
  HKEY hKey;
  LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, kRegKey, 0, KEY_READ, &hKey);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  DWORD dataSize = sizeof(WINDOWPLACEMENT);
  DWORD dataType = 0;
  result = RegQueryValueExW(hKey, kRegValueName, nullptr, &dataType,
                            reinterpret_cast<BYTE*>(&placement), &dataSize);
  RegCloseKey(hKey);

  // 验证数据有效性
  if (result != ERROR_SUCCESS || dataType != REG_BINARY ||
      dataSize != sizeof(WINDOWPLACEMENT) ||
      placement.length != sizeof(WINDOWPLACEMENT)) {
    return false;
  }

  // 验证还原位置是否合理（窗口大小至少 100x100）
  RECT& rc = placement.rcNormalPosition;
  if ((rc.right - rc.left) < 100 || (rc.bottom - rc.top) < 100) {
    return false;
  }

  // 验证窗口位置是否在某个显示器上可见
  // 使用还原位置的中心点检查
  POINT center;
  center.x = (rc.left + rc.right) / 2;
  center.y = (rc.top + rc.bottom) / 2;
  HMONITOR monitor = MonitorFromPoint(center, MONITOR_DEFAULTTONULL);
  if (monitor == nullptr) {
    // 窗口中心不在任何显示器上，检查是否有任何交叉
    HMONITOR monitor2 = MonitorFromRect(&rc, MONITOR_DEFAULTTONULL);
    if (monitor2 == nullptr) {
      return false;  // 窗口完全在屏幕外
    }
  }

  return true;
}

// 将当前窗口位置信息保存到注册表
bool WindowPlacementHelper::SavePlacement(HWND hwnd) {
  WINDOWPLACEMENT placement;
  placement.length = sizeof(WINDOWPLACEMENT);

  if (!GetWindowPlacement(hwnd, &placement)) {
    return false;
  }

  HKEY hKey;
  LONG result = RegCreateKeyExW(HKEY_CURRENT_USER, kRegKey, 0, nullptr,
                                REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                                &hKey, nullptr);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  result = RegSetValueExW(hKey, kRegValueName, 0, REG_BINARY,
                          reinterpret_cast<const BYTE*>(&placement),
                          sizeof(WINDOWPLACEMENT));
  RegCloseKey(hKey);

  return result == ERROR_SUCCESS;
}
