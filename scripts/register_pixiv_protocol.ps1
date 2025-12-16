# PixEz - Pixiv URL Scheme 自动注册脚本
# 用法: .\register_pixiv_protocol.ps1 [-ExePath "完整路径"]

param(
    [Parameter(Mandatory=$false)]
    [string]$ExePath = ""
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PixEz - Pixiv URL Scheme 注册工具  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 如果未提供路径，提示用户输入
if ($ExePath -eq "") {
    Write-Host "请输入 pixez.exe 的完整路径（含文件名）" -ForegroundColor Yellow
    Write-Host "例如: E:\Program Files\PixEz\pixez.exe" -ForegroundColor Gray
    Write-Host ""
    $ExePath = Read-Host "路径"
}

# 移除路径两端的引号（如果有）
$ExePath = $ExePath.Trim('"')

# 检查文件是否存在
if (-not (Test-Path $ExePath)) {
    Write-Host ""
    Write-Host "✗ 错误: 文件不存在!" -ForegroundColor Red
    Write-Host "  路径: $ExePath" -ForegroundColor Red
    Write-Host ""
    Read-Host "按 Enter 键退出"
    exit 1
}

Write-Host ""
Write-Host "找到文件: $ExePath" -ForegroundColor Green
Write-Host ""
Write-Host "正在注册 pixiv:// 协议..." -ForegroundColor Yellow

try {
    # 创建主键
    $regPath = "HKCU:\Software\Classes\pixiv"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Pixiv Protocol" -Force
    Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value "" -Force
    Write-Host "  ✓ 创建主键" -ForegroundColor Green

    # 创建图标键
    $iconPath = "$regPath\DefaultIcon"
    if (-not (Test-Path $iconPath)) {
        New-Item -Path $iconPath -Force | Out-Null
    }
    Set-ItemProperty -Path $iconPath -Name "(Default)" -Value "`"$ExePath`",0" -Force
    Write-Host "  ✓ 设置图标" -ForegroundColor Green

    # 创建命令键
    $commandPath = "$regPath\shell\open\command"
    if (-not (Test-Path $commandPath)) {
        New-Item -Path $commandPath -Force | Out-Null
    }
    Set-ItemProperty -Path $commandPath -Name "(Default)" -Value "`"$ExePath`" `"%1`"" -Force
    Write-Host "  ✓ 设置命令" -ForegroundColor Green

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "✓ 注册成功！" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "现在可以使用浏览器登录 PixEz 了！" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "测试方法:" -ForegroundColor Yellow
    Write-Host "  1. 在浏览器地址栏输入: pixiv://test" -ForegroundColor Gray
    Write-Host "  2. 或在命令行执行: start pixiv://test" -ForegroundColor Gray
    Write-Host "  3. 如果 PixEz 启动，说明配置成功" -ForegroundColor Gray
    Write-Host ""
    
    # 询问是否立即测试
    $test = Read-Host "是否立即测试? (Y/N)"
    if ($test -eq "Y" -or $test -eq "y") {
        Write-Host ""
        Write-Host "正在启动 PixEz..." -ForegroundColor Yellow
        Start-Process "pixiv://test"
        Start-Sleep -Seconds 2
    }
    
} catch {
    Write-Host ""
    Write-Host "✗ 注册失败!" -ForegroundColor Red
    Write-Host "错误信息: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "可能的原因:" -ForegroundColor Yellow
    Write-Host "  1. 权限不足（请以管理员身份运行）" -ForegroundColor Gray
    Write-Host "  2. 注册表被锁定或保护" -ForegroundColor Gray
    Write-Host ""
    Read-Host "按 Enter 键退出"
    exit 1
}

Write-Host ""
Read-Host "按 Enter 键退出"
