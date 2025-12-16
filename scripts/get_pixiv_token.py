#!/usr/bin/env python3
"""
PixEz - Pixiv Refresh Token 获取/刷新工具

用法:
    python get_pixiv_token.py                    # 刷新现有 token
    python get_pixiv_token.py --token YOUR_TOKEN # 使用指定 token 刷新
"""

import sys
import requests
import argparse
from datetime import datetime, timedelta

# Pixiv OAuth 客户端信息（与 PixEz 相同）
CLIENT_ID = "MOBrBDS8blbauoSck0ZfDbtuzpyT"
CLIENT_SECRET = "lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj"

def print_separator(char="=", length=60):
    """打印分隔线"""
    print(char * length)

def print_header():
    """打印标题"""
    print_separator()
    print("  PixEz - Pixiv Token 工具")
    print_separator()
    print()

def refresh_token(old_refresh_token):
    """
    使用旧的 refresh_token 获取新的 token
    
    Args:
        old_refresh_token: 现有的 refresh token
        
    Returns:
        dict: 包含新 token 的字典，如果失败则返回 None
    """
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
    
    try:
        print("正在连接 Pixiv 服务器...")
        response = requests.post(url, data=data, headers=headers, timeout=30)
        
        if response.status_code == 200:
            result = response.json()
            
            # 计算过期时间
            expires_in = result.get('expires_in', 3600)
            expire_time = datetime.now() + timedelta(seconds=expires_in)
            
            print()
            print_separator("=")
            print("✓ 成功获取新 Token!")
            print_separator("=")
            print()
            
            print("【Access Token】(用于 API 请求，1小时有效)")
            print(result['access_token'])
            print()
            
            print("【Refresh Token】(用于刷新，长期有效)")
            print(result['refresh_token'])
            print()
            
            print(f"有效期: {expires_in} 秒 (~{expires_in//60} 分钟)")
            print(f"过期时间: {expire_time.strftime('%Y-%m-%d %H:%M:%S')}")
            print()
            
            print_separator("-")
            print("使用说明:")
            print("1. 复制上面的 Refresh Token")
            print("2. 在 PixEz Windows 版登录页面点击 'Token' 按钮")
            print("3. 粘贴 Refresh Token 并登录")
            print_separator("-")
            print()
            
            return result
            
        elif response.status_code == 400:
            error_data = response.json()
            error_msg = error_data.get('errors', {}).get('system', {}).get('message', '未知错误')
            
            print()
            print_separator("=")
            print("✗ Token 刷新失败")
            print_separator("=")
            print()
            print(f"错误信息: {error_msg}")
            print()
            print("可能的原因:")
            print("  • Token 已过期或被撤销")
            print("  • 已修改过 Pixiv 密码")
            print("  • Token 格式不正确")
            print()
            print("解决方法:")
            print("  • 重新获取 Token（使用移动端 PixEz 导出）")
            print("  • 或使用浏览器登录（需先配置 URL Scheme）")
            print()
            
        else:
            print()
            print(f"✗ HTTP 错误: {response.status_code}")
            print(f"响应内容: {response.text[:200]}")
            print()
            
        return None
        
    except requests.exceptions.Timeout:
        print()
        print("✗ 连接超时，请检查网络连接")
        print()
        return None
        
    except requests.exceptions.ConnectionError:
        print()
        print("✗ 无法连接到服务器，请检查:")
        print("  • 网络是否正常")
        print("  • 是否需要代理")
        print()
        return None
        
    except Exception as e:
        print()
        print(f"✗ 发生错误: {str(e)}")
        print()
        return None

def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description='PixEz - Pixiv Token 获取/刷新工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
示例用法:
  python get_pixiv_token.py
  python get_pixiv_token.py --token YOUR_REFRESH_TOKEN
  
获取 Token 的其他方法:
  1. 移动端导出: 更多 → 账户信息 → Token export
  2. 抓包获取: 使用 Charles/Fiddler 抓取登录请求
  3. Python 脚本: 使用完整 OAuth 流程（见文档）
        '''
    )
    
    parser.add_argument(
        '--token', '-t',
        type=str,
        help='要刷新的 Refresh Token'
    )
    
    args = parser.parse_args()
    
    print_header()
    
    # 获取 refresh token
    if args.token:
        old_token = args.token.strip()
    else:
        print("请输入你的 Refresh Token:")
        print("(提示: 可以从移动端 PixEz 导出)")
        print()
        old_token = input("Token: ").strip()
    
    if not old_token:
        print()
        print("✗ 未提供 Token")
        return 1
    
    print()
    
    # 刷新 token
    result = refresh_token(old_token)
    
    return 0 if result else 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        print()
        print("用户取消操作")
        sys.exit(1)
