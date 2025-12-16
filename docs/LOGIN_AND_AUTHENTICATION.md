# PixEz 登录与鉴权完整指南

本文档详细说明了 PixEz Flutter 应用在各平台（特别是 Windows）上的登录机制、鉴权流程、以及如何获取和使用 Refresh Token。

---

## 目录

- [一、登录机制概述](#一登录机制概述)
- [二、OAuth 2.0 认证流程](#二oauth-20-认证流程)
- [三、Windows 平台特殊配置](#三windows-平台特殊配置)
- [四、Refresh Token 获取方法](#四refresh-token-获取方法)
- [五、鉴权与自动刷新](#五鉴权与自动刷新)
- [六、数据存储机制](#六数据存储机制)
- [七、故障排查](#七故障排查)

---

## 一、登录机制概述

PixEz 支持三种登录方式：

### 1.1 标准 OAuth 登录（推荐）

- **Android/iOS**: 使用 WebView 或 Custom Tab
- **Windows/macOS**: 使用系统默认浏览器
- **优点**: 安全、官方支持
- **缺点**: Windows 需要配置 URL Scheme

### 1.2 Token 登录

- 直接输入 Refresh Token
- 适用于所有平台
- 无需浏览器交互

### 1.3 快速注册

- 通过 OAuth 流程快速创建新账号
- 注册后需记录用户名和密码

---

## 二、OAuth 2.0 认证流程

### 2.1 认证流程图

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 用户点击登录                                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 生成 code_verifier 和 code_challenge (PKCE)              │
│    - code_verifier: 随机字符串                               │
│    - code_challenge: SHA256(code_verifier)                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. 打开浏览器访问 Pixiv OAuth 页面                           │
│    URL: https://app-api.pixiv.net/web/v1/login?            │
│         code_challenge={challenge}&                         │
│         code_challenge_method=S256&                         │
│         client=pixiv-android                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. 用户在浏览器中输入账号密码                                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Pixiv 服务器重定向                                        │
│    pixiv://account/login?code={authorization_code}          │
└──────────────────────┬──────────────────────────────────────┘
                       │
          ┌────────────┴────────────┐
          │                         │
          ▼                         ▼
┌──────────────────┐    ┌──────────────────────┐
│ Android/iOS      │    │ Windows/macOS        │
│ Intent Filter    │    │ URL Scheme Registry  │
│ 拦截 URI         │    │ + 命名管道转发        │
└─────────┬────────┘    └──────────┬───────────┘
          │                        │
          └────────────┬───────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. 使用 code + code_verifier 换取 token                      │
│    POST https://oauth.secure.pixiv.net/auth/token           │
│    {                                                        │
│      "code": "{authorization_code}",                        │
│      "code_verifier": "{code_verifier}",                    │
│      "grant_type": "authorization_code"                     │
│    }                                                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. 获取 Token 响应                                           │
│    {                                                        │
│      "access_token": "...",                                 │
│      "refresh_token": "...",                                │
│      "expires_in": 3600,                                    │
│      "user": {...}                                          │
│    }                                                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. 保存到 SQLite 数据库                                      │
│    - access_token (1小时有效)                                │
│    - refresh_token (长期有效)                                │
│    - 用户信息                                                │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 关键参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `client_id` | OAuth 客户端 ID | `MOBrBDS8blbauoSck0ZfDbtuzpyT` |
| `client_secret` | OAuth 客户端密钥 | `lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj` |
| `code_verifier` | PKCE 验证码（随机） | `dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` |
| `code_challenge` | PKCE 挑战码（SHA256） | Base64Url(SHA256(code_verifier)) |

### 2.3 代码实现

**生成 WebView URL** (`lib/network/oauth_client.dart`):
```dart
static Future<String> generateWebviewUrl({bool create = false}) async {
  await generateCodeVerify();
  String codeChallenge = await CryptoPlugin.getCodeChallenge();
  String url = !create
      ? "https://app-api.pixiv.net/web/v1/login?code_challenge=${codeChallenge}&code_challenge_method=S256&client=pixiv-android"
      : "https://app-api.pixiv.net/web/v1/provisional-accounts/create?code_challenge=${codeChallenge}&code_challenge_method=S256&client=pixiv-android";
  return url;
}
```

**Code 换 Token** (`lib/network/oauth_client.dart`):
```dart
Future<Response> code2Token(String code) {
  return httpClient.post("/auth/token",
      data: {
        "code": code,
        "redirect_uri": "https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback",
        "grant_type": "authorization_code",
        "include_policy": true,
        "client_id": CLIENT_ID,
        "code_verifier": Constants.code_verifier,
        "client_secret": CLIENT_SECRET
      },
      options: Options(contentType: Headers.formUrlEncodedContentType));
}
```

---

## 三、Windows 平台特殊配置

### 3.1 为什么 Windows 需要特殊配置？

Windows 平台使用**系统默认浏览器**进行 OAuth 登录，而不是内嵌 WebView。当浏览器收到 `pixiv://` 协议的回调 URL 时，需要通过注册表找到对应的应用程序。

### 3.2 URL Scheme 注册方法

#### 方法 1: 使用注册表文件（推荐）

1. **创建文件** `register_pixiv_protocol.reg`：

```reg
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Classes\pixiv]
@="URL:Pixiv Protocol"
"URL Protocol"=""

[HKEY_CURRENT_USER\Software\Classes\pixiv\DefaultIcon]
@="\"E:\\Program Files\\PixEz\\pixez.exe\",0"

[HKEY_CURRENT_USER\Software\Classes\pixiv\shell\open\command]
@="\"E:\\Program Files\\PixEz\\pixez.exe\" \"%1\""
```

2. **修改路径**：将 `E:\Program Files\PixEz\pixez.exe` 替换为你的实际安装路径

3. **双击导入**：运行 `.reg` 文件导入注册表

#### 方法 2: 使用 PowerShell 脚本

创建 `register_pixiv_protocol.ps1`：

```powershell
# 需要管理员权限运行
param(
    [string]$ExePath = ""
)

if ($ExePath -eq "") {
    $ExePath = Read-Host "请输入 pixez.exe 的完整路径"
}

if (-not (Test-Path $ExePath)) {
    Write-Host "错误: 文件不存在: $ExePath" -ForegroundColor Red
    Read-Host "按 Enter 键退出"
    exit 1
}

Write-Host "正在注册 pixiv:// 协议..." -ForegroundColor Yellow

# 创建主键
New-Item -Path "HKCU:\Software\Classes\pixiv" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\pixiv" -Name "(Default)" -Value "URL:Pixiv Protocol"
Set-ItemProperty -Path "HKCU:\Software\Classes\pixiv" -Name "URL Protocol" -Value ""

# 创建图标键
New-Item -Path "HKCU:\Software\Classes\pixiv\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\pixiv\DefaultIcon" -Name "(Default)" -Value "`"$ExePath`",0"

# 创建命令键
New-Item -Path "HKCU:\Software\Classes\pixiv\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\pixiv\shell\open\command" -Name "(Default)" -Value "`"$ExePath`" `"%1`""

Write-Host "✓ 注册成功！" -ForegroundColor Green
Write-Host "现在可以使用浏览器登录了。" -ForegroundColor Green
Read-Host "按 Enter 键退出"
```

**运行方式**：
```powershell
# 自动填写路径
.\register_pixiv_protocol.ps1 -ExePath "E:\Program Files\PixEz\pixez.exe"

# 或手动输入
.\register_pixiv_protocol.ps1
```

#### 方法 3: 手动添加注册表

1. 按 `Win + R`，输入 `regedit` 打开注册表编辑器
2. 导航到 `HKEY_CURRENT_USER\Software\Classes`
3. 右键新建项，命名为 `pixiv`
4. 在右侧创建字符串值：
   - `(默认)` = `URL:Pixiv Protocol`
   - `URL Protocol` = (空值)
5. 在 `pixiv` 下创建路径：`shell\open\command`
6. 修改 `command` 的默认值为：`"你的路径\pixez.exe" "%1"`

### 3.3 单实例管理机制

Windows 使用**命名管道**实现单实例和深链接转发：

```
第一次启动 pixez.exe
    ↓
创建 Mutex (名称: "pixez")
    ↓
创建命名管道 \\.\pipe\pixez
    ↓
等待接收参数...
```

```
第二次启动 pixez.exe "pixiv://account/login?code=xxx"
    ↓
检测到 Mutex 已存在
    ↓
连接到命名管道 \\.\pipe\pixez
    ↓
发送命令行参数
    ↓
关闭自身进程
    ↓
首实例接收参数并处理登录
```

**代码位置**: `windows/runner/plugins/single_instance_plugin.cpp`

### 3.4 验证配置

配置完成后，可以通过以下方式验证：

1. **命令行测试**：
```cmd
start pixiv://account/login?code=test123
```

2. **浏览器测试**：
在浏览器地址栏输入：
```
pixiv://account/login?code=test123
```

如果配置正确，应该会启动 PixEz 应用。

---

## 四、Refresh Token 获取方法

### 4.1 方法对比

| 方法 | 难度 | 安全性 | 适用场景 | 推荐度 |
|------|------|--------|---------|--------|
| 移动端导出 | ⭐ | ⭐⭐⭐⭐⭐ | 有手机设备 | ⭐⭐⭐⭐⭐ |
| 配置 URL Scheme | ⭐⭐ | ⭐⭐⭐⭐⭐ | Windows PC | ⭐⭐⭐⭐⭐ |
| Python 脚本 | ⭐⭐⭐ | ⭐⭐⭐⭐ | 懂编程 | ⭐⭐⭐⭐ |
| 手动抓包 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 会抓包 | ⭐⭐⭐ |
| 在线工具 | ⭐⭐ | ⭐⭐⭐ | 快速获取 | ⭐⭐ |

### 4.2 方法一：移动端导出（最简单）

如果你有 Android 或 iOS 设备：

1. 在手机上安装 PixEz
   - Android: [Google Play](https://play.google.com/store/apps/details?id=com.perol.play.pixez) 或 [GitHub Release](https://github.com/Notsfsssf/pixez-flutter/releases)
   - iOS: [App Store](https://apps.apple.com/us/app/pixez/id1494435126)

2. 使用正常方式登录（手机上可以直接使用 WebView）

3. 登录成功后，导航到：
   ```
   更多 → 账户信息 → Token export
   ```

4. 点击后会自动复制 Refresh Token 到剪贴板

5. 通过云同步、聊天软件等方式发送到电脑

6. 在 Windows 版 PixEz 登录页面点击 "Token" 按钮粘贴

### 4.3 方法二：Python 脚本获取

#### 安装依赖

```bash
pip install requests
```

#### 脚本方式 1：使用已有 Refresh Token

如果你已经有一个 Refresh Token 但想获取新的：

```python
#!/usr/bin/env python3
"""Pixiv Token Refresher"""

import requests

CLIENT_ID = "MOBrBDS8blbauoSck0ZfDbtuzpyT"
CLIENT_SECRET = "lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj"

def refresh_token(old_refresh_token):
    """使用旧的 refresh_token 获取新的 token"""
    url = "https://oauth.secure.pixiv.net/auth/token"
    
    data = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "refresh_token",
        "refresh_token": old_refresh_token,
        "include_policy": "true"
    }
    
    headers = {
        "User-Agent": "PixivAndroidApp/5.0.166 (Android 6.0; Pixel C)",
        "Content-Type": "application/x-www-form-urlencoded"
    }
    
    response = requests.post(url, data=data, headers=headers)
    
    if response.status_code == 200:
        result = response.json()
        print("✓ 成功获取新 Token!")
        print(f"\nAccess Token: {result['access_token']}")
        print(f"\nRefresh Token: {result['refresh_token']}")
        print(f"\n有效期: {result['expires_in']} 秒")
        return result
    else:
        print(f"✗ 错误: {response.status_code}")
        print(response.text)
        return None

if __name__ == "__main__":
    old_token = input("请输入你的 Refresh Token: ").strip()
    refresh_token(old_token)
```

#### 脚本方式 2：完整 OAuth 流程

使用 GitHub Gist 中的完整脚本：

**参考**: https://gist.github.com/ZipFile/c9ebedb224406f4f11845ab700124362

这个脚本会：
1. 生成 code_verifier 和 code_challenge
2. 打开浏览器到 Pixiv 登录页
3. 你在浏览器中登录
4. 脚本自动捕获回调 URL 中的 code
5. 使用 code 交换 token

### 4.4 方法三：手动抓包（进阶）

#### 所需工具
- **Android 手机** + **Pixiv 官方 App** 或 **PixEz**
- **Charles Proxy** 或 **Fiddler**（抓包工具）

#### 步骤

1. **安装 Charles 或 Fiddler**

2. **配置手机代理**：
   - 打开手机 WiFi 设置
   - 设置 HTTP 代理为你的电脑 IP 和端口（如 `192.168.1.100:8888`）

3. **安装 CA 证书**（用于抓取 HTTPS）：
   - Charles: 手机访问 `chls.pro/ssl`
   - Fiddler: 手机访问 `http://你的电脑IP:8888`

4. **开始抓包并登录**：
   - 在抓包工具中开始监控
   - 打开 Pixiv App 或 PixEz 并登录

5. **查找 Token**：
   - 搜索 URL: `oauth.secure.pixiv.net/auth/token`
   - 找到 POST 请求的响应
   - 在 JSON 响应中找到 `refresh_token` 字段

**响应示例**:
```json
{
  "response": {
    "access_token": "aXXXXXXXXXX...",
    "refresh_token": "rXXXXXXXXXX...",  // ← 这个就是你需要的
    "expires_in": 3600,
    "token_type": "bearer",
    "scope": "",
    "user": {
      "id": "12345678",
      "name": "YourUsername",
      ...
    }
  }
}
```

### 4.5 方法四：在线工具

#### pixiv.pictures

1. 访问 https://pixiv.pictures
2. 使用提供的用户脚本（需要 Tampermonkey 等扩展）
3. 登录后在设置页面导出 RefreshToken

⚠️ **安全警告**: 使用第三方工具时要谨慎，Refresh Token 相当于你的账号永久密码！

### 4.6 Token 使用方法

获取到 Refresh Token 后：

1. 打开 PixEz Windows 版
2. 在登录页面点击 **"Token"** 按钮
3. 粘贴你的 Refresh Token（一长串字符）
4. 点击 "Next"

应用会自动：
- 使用 Refresh Token 获取 Access Token
- 获取用户信息
- 保存到本地数据库
- 跳转到主页

**代码位置**: `lib/page/login/token_page.dart`

---

## 五、鉴权与自动刷新

### 5.1 Token 类型

| Token 类型 | 有效期 | 用途 | 存储位置 |
|-----------|--------|------|---------|
| Access Token | 1 小时 | API 请求鉴权 | SQLite + 内存 |
| Refresh Token | 长期有效 | 刷新 Access Token | SQLite |

### 5.2 自动刷新机制

应用使用 Dio Interceptor 自动刷新过期的 Token：

```dart
// lib/network/refresh_token_interceptor.dart

@override
void onError(DioException err, handler) async {
  // 检测到 400 错误且包含 OAuth 信息
  if (err.response != null && err.response!.statusCode == 400) {
    ErrorMessage errorMessage = ErrorMessage.fromJson(err.response!.data);
    
    if (errorMessage.error.message!.contains("OAuth")) {
      // 1. 使用 Refresh Token 获取新的 Access Token
      final client = OAuthClient();
      await client.createDioClient();
      Response response = await client.postRefreshAuthToken(
          refreshToken: accountStore.now!.refreshToken);
      
      // 2. 更新数据库中的 Token
      AccountResponse accountResponse = Account.fromJson(response.data).response;
      await accountStore.updateSingle(newAccountPersist);
      
      // 3. 使用新 Token 重试失败的请求
      option.headers[OAuthClient.AUTHORIZATION] = newToken;
      var response = await apiClient.httpClient.request(...);
      return handler.resolve(response);
    }
  }
  
  return handler.reject(err);
}
```

### 5.3 请求流程

```
API 请求
    ↓
添加 Authorization Header: "Bearer {access_token}"
    ↓
发送请求
    ↓
┌─────────────┐
│ 返回 200 OK  │ → 成功
└─────────────┘
    ↓
┌──────────────────┐
│ 返回 400 OAuth错误│
└────────┬─────────┘
         │
         ▼
使用 Refresh Token 获取新 Access Token
         │
         ▼
更新数据库
         │
         ▼
使用新 Token 重试请求
         │
         ▼
      成功
```

### 5.4 防重复刷新

使用时间戳防止短时间内重复刷新：

```dart
int lastRefreshTime = 0;

if ((currentTime - lastRefreshTime) > 200000) {  // 200秒
  // 执行刷新操作
  lastRefreshTime = currentTime;
}
```

---

## 六、数据存储机制

### 6.1 SQLite 数据库结构

**表名**: `account`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | INTEGER | 主键（自增） |
| `user_id` | TEXT | Pixiv 用户 ID |
| `access_token` | TEXT | 访问令牌 |
| `refresh_token` | TEXT | 刷新令牌 |
| `device_token` | TEXT | 设备令牌（已废弃） |
| `user_image` | TEXT | 用户头像 URL |
| `name` | TEXT | 用户昵称 |
| `password` | TEXT | 密码（新版填 "no more"） |
| `account` | TEXT | Pixiv 账号名 |
| `mail_address` | TEXT | 邮箱地址 |
| `is_premium` | INTEGER | 是否会员（0/1） |
| `x_restrict` | INTEGER | 年龄限制等级 |
| `is_mail_authorized` | INTEGER | 邮箱是否验证（0/1） |

**代码位置**: `lib/models/account.dart`

### 6.2 SharedPreferences 配置

使用 SharedPreferences 存储：
- 当前选中的账户索引: `account_select_num`
- 用户偏好设置
- 窗口位置信息

**代码位置**: `lib/er/prefer.dart`

### 6.3 数据库位置

各平台数据库文件路径：

| 平台 | 路径 |
|------|------|
| Windows | `%APPDATA%\Roaming\pixez\databases\account.db` |
| Android | `/data/data/com.perol.pixez/databases/account.db` |
| iOS | `Library/Application Support/account.db` |
| macOS | `~/Library/Application Support/pixez/databases/account.db` |

### 6.4 多账户支持

应用支持同时存储多个账户：

```dart
// 切换账户
await accountStore.select(index);

// 获取所有账户
List<AccountPersist> accounts = await accountProvider.getAllAccount();

// 删除指定账户
await accountStore.deleteSingle(id);
```

---

## 七、故障排查

### 7.1 常见问题

#### Q1: Windows 浏览器登录后没有反应

**原因**: 未配置 URL Scheme 注册表

**解决方案**:
1. 按照 [三、Windows 平台特殊配置](#三windows-平台特殊配置) 配置注册表
2. 测试命令: `start pixiv://test`
3. 确认 PixEz 是否启动

#### Q2: Token 登录提示错误

**可能原因**:
- Token 格式错误（多余空格、换行）
- Token 已过期
- Token 被撤销（修改过密码）

**解决方案**:
1. 确保复制完整的 Refresh Token
2. 重新获取新的 Token
3. 检查网络连接

#### Q3: 登录后立即提示 OAuth 错误

**原因**: Access Token 立即过期

**解决方案**:
- 通常会自动刷新，等待几秒
- 如持续失败，清除数据重新登录

#### Q4: 无法打开浏览器登录页面

**Windows 特有问题**:
- 检查是否安装了默认浏览器
- 尝试手动复制 URL 到浏览器
- 使用 Token 登录方式

### 7.2 调试技巧

#### 启用日志

在 `lib/network/oauth_client.dart` 中已启用 Debug 日志：

```dart
if (kDebugMode) {
  httpClient.interceptors.add(LogInterceptor(
      responseBody: true, 
      responseHeader: true, 
      requestBody: true));
}
```

#### 查看数据库内容

使用 SQLite 工具查看：
```bash
# Windows
sqlite3 "%APPDATA%\Roaming\pixez\databases\account.db"

# 查询账户
SELECT user_id, name, account FROM account;
```

#### 检查注册表

```powershell
# 检查 pixiv:// 协议是否注册
Get-ItemProperty -Path "HKCU:\Software\Classes\pixiv\shell\open\command"
```

### 7.3 重置应用

如果遇到无法解决的问题：

1. **清除数据库**:
   - 删除 `account.db` 文件
   - 重启应用

2. **清除所有数据**:
   ```
   设置 → 登出 → 删除所有账户
   ```

3. **重新安装**:
   - 完全卸载应用
   - 删除应用数据目录
   - 重新安装

---

## 八、安全建议

### 8.1 Token 安全

- ✅ **不要分享** Refresh Token 给任何人
- ✅ **定期更换密码** 会使旧 Token 失效
- ✅ **不要在公共场合** 展示包含 Token 的截图
- ✅ **使用强密码** 保护你的 Pixiv 账户

### 8.2 第三方工具

使用第三方工具获取 Token 时：
- ⚠️ 仔细检查工具来源
- ⚠️ 优先使用开源脚本
- ⚠️ 获取后立即修改密码使旧 Token 失效

### 8.3 数据备份

建议定期备份：
- 收藏列表
- 下载记录
- 自定义设置

可以使用应用内的导出功能。

---

## 九、参考资源

### 官方文档
- [Pixiv API 文档](https://pixiv.net/api) (非公开)
- [OAuth 2.0 PKCE](https://tools.ietf.org/html/rfc7636)

### 相关工具
- [pixiv_auth.py](https://gist.github.com/ZipFile/c9ebedb224406f4f11845ab700124362) - Python Token 获取脚本
- [Charles Proxy](https://www.charlesproxy.com/) - HTTP 抓包工具
- [Fiddler](https://www.telerik.com/fiddler) - HTTP 调试代理

### 社区支持
- [GitHub Issues](https://github.com/Notsfsssf/pixez-flutter/issues)
- [Telegram 群组](https://t.me/PixEzChannel)
- Discord: [@PixEz](https://discord.gg/Em9AeJbg)
- QQ 群: 815791942

---

**文档版本**: 1.0  
**最后更新**: 2025-12-16  
**维护者**: PixEz Community
