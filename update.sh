#!/bin/bash

echo "🔄 更新全局 cleanmac 命令"
echo "========================="
echo ""

# Find where cleanmac is installed
CLEANMAC_PATH=$(which cleanmac 2>/dev/null)

if [[ -n "$CLEANMAC_PATH" ]]; then
    echo "发现现有安装: $CLEANMAC_PATH"
    
    # Update the file
    cp clean_mac.sh "$CLEANMAC_PATH"
    chmod +x "$CLEANMAC_PATH"
    
    echo "✅ 已更新全局命令"
    echo ""
    echo "验证更新:"
    cleanmac --help | head -3
else
    echo "⚠️ 未找到全局 cleanmac 命令"
    echo "请运行 ./install.sh 重新安装"
fi