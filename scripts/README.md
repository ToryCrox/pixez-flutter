# PixEz 脚本工具集

本目录包含用于 PixEz Windows 版本的辅助脚本工具。

## 文件说明

### 📄 register_pixiv_protocol.reg
**Windows 注册表文件**

用于注册 `pixiv://` URL Scheme，使浏览器能够回调到 PixEz 应用。

**使用方法**:
1. 用文本编辑器打开此文件
2. 将两处 `E:\Program Files\PixEz\pixez.exe` 修改为你的实际安装路径
3. 保存后双击导入注册表
4. 在浏览器地址栏输入 `pixiv://test` 测试

**注意事项**:
- 路径中的反斜杠需要双写（如 `E:\\Program Files\\`）
- 建议使用下面的 PowerShell 脚本，更加安全和自动化

---

### 🔧 register_pixiv_protocol.ps1
**PowerShell 自动注册脚本**（推荐）

交互式脚本，自动注册 `pixiv://` 协议。

**使用方法**:

**方式 1 - 交互式**（推荐新手）:
```powershell
.\register_pixiv_protocol.ps1
```
然后按提示输入 pixez.exe 的完整路径。

**方式 2 - 命令行参数**:
```powershell
.\register_pixiv_protocol.ps1 -ExePath "E:\Program Files\PixEz\pixez.exe"
```

**特性**:
- ✅ 自动检测文件是否存在
- ✅ 友好的错误提示
- ✅ 提供测试功能
- ✅ 彩色输出，易于阅读

**可能遇到的问题**:

如果提示"无法加载脚本"，执行以下命令允许运行脚本：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

### 🐍 get_pixiv_token.py
**Python Token 获取/刷新工具**

用于刷新 Pixiv Refresh Token。

**前置要求**:
```bash
pip install requests
```

**使用方法**:

**方式 1 - 交互式**:
```bash
python get_pixiv_token.py
```
然后根据提示输入你的 Refresh Token。

**方式 2 - 命令行参数**:
```bash
python get_pixiv_token.py --token YOUR_REFRESH_TOKEN_HERE
```

**输出示例**:
```
============================================================
  PixEz - Pixiv Token 工具
============================================================

请输入你的 Refresh Token:
(提示: 可以从移动端 PixEz 导出)

Token: xxxxxxxxxxxxx...

正在连接 Pixiv 服务器...

============================================================
✓ 成功获取新 Token!
============================================================

【Access Token】(用于 API 请求，1小时有效)
aXXXXXXXXXXXXXXXXXXXX...

【Refresh Token】(用于刷新，长期有效)
rYYYYYYYYYYYYYYYYYYYY...

有效期: 3600 秒 (~60 分钟)
过期时间: 2025-12-16 23:30:00
```

---

## 快速开始指南

### 🎯 场景 1: 首次在 Windows 上使用 PixEz

**如果你有手机（Android/iOS）**:
1. 在手机上安装并登录 PixEz
2. 进入: 更多 → 账户信息 → Token export
3. 复制 Token 到电脑
4. 在 Windows 版 PixEz 登录页点击 "Token" 按钮
5. 粘贴并登录

**如果没有手机**:
1. 运行 `register_pixiv_protocol.ps1` 配置 URL Scheme
2. 在 PixEz 中使用浏览器登录

---

### 🎯 场景 2: 已有 Token 需要刷新

```bash
python get_pixiv_token.py
```

---

### 🎯 场景 3: 浏览器登录不work

1. 检查注册表是否正确配置：
   ```powershell
   Get-ItemProperty -Path "HKCU:\Software\Classes\pixiv\shell\open\command"
   ```

2. 测试 URL Scheme:
   ```cmd
   start pixiv://test
   ```

3. 如果都不行，使用 Token 登录方式

---

## 常见问题

### Q: PowerShell 脚本无法运行？
**A**: 执行策略限制，运行：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Q: Python 脚本提示 "No module named 'requests'"？
**A**: 安装依赖：
```bash
pip install requests
```

### Q: Token 刷新失败？
**A**: 可能原因：
- Token 已过期（修改过密码会使旧 token 失效）
- 网络问题（尝试使用代理）
- Token 格式错误（确保完整复制）

### Q: 注册表导入后浏览器还是不能跳转？
**A**: 
1. 重启浏览器
2. 检查路径是否正确（注意双反斜杠）
3. 尝试手动打开注册表编辑器检查

---

## 安全提示

⚠️ **重要**: 
- Refresh Token 相当于你的账号永久密码
- 不要分享给任何人
- 不要上传到公开的地方（如 GitHub）
- 定期修改密码会使旧 token 失效

---

## 相关文档

详细说明请参考：
- [完整登录与鉴权文档](../docs/LOGIN_AND_AUTHENTICATION.md)
- [FAQ 常见问题](./.github/FAQ.md)

---

## 脚本版本历史

- **v1.0** (2025-12-16)
  - 初始版本
  - 包含注册表文件、PowerShell 脚本和 Python 工具

---

**维护者**: PixEz Community  
**问题反馈**: https://github.com/Notsfsssf/pixez-flutter/issues
