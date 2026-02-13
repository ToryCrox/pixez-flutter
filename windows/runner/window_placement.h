#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>
#include <string>

// 使用 Win32 原生 API 管理窗口位置和状态的保存/恢复
// 通过注册表持久化 WINDOWPLACEMENT 结构体，完美处理最大化/还原状态
class WindowPlacementHelper {
 public:
  // 从注册表加载保存的窗口位置信息
  // 如果没有保存的数据或加载失败，返回 false
  static bool LoadPlacement(WINDOWPLACEMENT& placement);

  // 将当前窗口位置信息保存到注册表
  static bool SavePlacement(HWND hwnd);

 private:
  // 注册表路径和键名
  static constexpr const wchar_t* kRegKey = L"Software\\PixEz";
  static constexpr const wchar_t* kRegValueName = L"WindowPlacement";
};

#endif  // RUNNER_WINDOW_PLACEMENT_H_
