#!/bin/bash

echo "🧹 CleanMac 全局命令安装程序"
echo "=================================="
echo ""

# 检查脚本文件是否存在
if [[ ! -f "clean_mac.sh" ]]; then
    echo "❌ 找不到 clean_mac.sh 文件"
    echo "请确保在 CleanYourMac 项目目录下运行此安装程序"
    exit 1
fi

echo "📁 创建用户bin目录..."
mkdir -p "$HOME/.local/bin"

echo "📋 复制脚本文件..."

# 优先使用homebrew目录（更可靠）
if [[ -d "/opt/homebrew/bin" && -w "/opt/homebrew/bin" ]]; then
    cp clean_mac.sh "/opt/homebrew/bin/cleanmac"
    chmod +x "/opt/homebrew/bin/cleanmac"
    echo "✅ 脚本已复制到: /opt/homebrew/bin/cleanmac"
    INSTALL_PATH="/opt/homebrew/bin/cleanmac"
    NEED_PATH_SETUP=false
elif [[ -d "/usr/local/bin" && -w "/usr/local/bin" ]]; then
    cp clean_mac.sh "/usr/local/bin/cleanmac"
    chmod +x "/usr/local/bin/cleanmac"
    echo "✅ 脚本已复制到: /usr/local/bin/cleanmac"
    INSTALL_PATH="/usr/local/bin/cleanmac"
    NEED_PATH_SETUP=false
else
    # 回退到用户目录
    mkdir -p "$HOME/.local/bin"
    cp clean_mac.sh "$HOME/.local/bin/cleanmac"
    chmod +x "$HOME/.local/bin/cleanmac"
    echo "✅ 脚本已复制到: $HOME/.local/bin/cleanmac"
    INSTALL_PATH="$HOME/.local/bin/cleanmac"
    NEED_PATH_SETUP=true
fi
echo ""

# 只在需要时配置PATH
if [[ "$NEED_PATH_SETUP" == "true" ]]; then
    SHELL_TYPE=$(basename "$SHELL")
    case "$SHELL_TYPE" in
        "zsh")
            CONFIG_FILE="$HOME/.zshrc"
            ;;
        "bash")
            CONFIG_FILE="$HOME/.bashrc"
            if [[ ! -f "$CONFIG_FILE" ]]; then
                CONFIG_FILE="$HOME/.bash_profile"
            fi
            ;;
        *)
            CONFIG_FILE="$HOME/.profile"
            ;;
    esac

    echo "🔧 配置PATH设置..."
    echo "检测到shell: $SHELL_TYPE"
    echo "配置文件: $CONFIG_FILE"

    # 检查是否已经添加了PATH设置
    if grep -q ".local/bin" "$CONFIG_FILE" 2>/dev/null; then
        echo "✅ PATH设置已存在"
    else
        echo "➕ 添加PATH设置..."
        echo "" >> "$CONFIG_FILE"
        echo "# CleanMac全局命令" >> "$CONFIG_FILE"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$CONFIG_FILE"
        echo "✅ PATH设置已添加到 $CONFIG_FILE"
        echo ""
        echo "⚠️  重要: 请运行以下命令使设置生效:"
        echo "   source $CONFIG_FILE"
        echo "或者重新打开终端"
    fi
else
    echo "✅ 已安装到系统PATH目录，无需额外配置"
fi

echo ""
echo "🎉 安装完成！"
echo ""
echo "使用方法:"
echo "  cleanmac              # 交互模式"
echo "  cleanmac --auto       # 自动清理"
echo "  cleanmac --help       # 显示帮助"
echo "  cleanmac --lang=cn    # 中文界面"
echo ""
if [[ "$NEED_PATH_SETUP" == "true" ]]; then
    echo "如果命令不可用，请运行:"
    echo "  source $CONFIG_FILE"
    echo "或重新打开终端窗口"
else
    echo "✅ 命令已可用，无需重启终端！"
    echo ""
    echo "立即测试:"
    echo "  cleanmac --help"
fi