#!/bin/bash

echo "🔧 修复find命令兼容性问题"
echo "========================="
echo ""

echo "问题：您的系统将find别名为fd，导致清理功能无法正常工作"
echo "解决：使用/usr/bin/find替换所有find命令"
echo ""

# Backup the original file
cp clean_mac.sh clean_mac.sh.backup

echo "正在修复find命令..."

# Replace all standalone find commands with /usr/bin/find
sed -i.tmp 's/\bfind /\/usr\/bin\/find /g' clean_mac.sh

# Also fix sudo find commands
sed -i.tmp 's/sudo find/sudo \/usr\/bin\/find/g' clean_mac.sh

# Clean up temporary files
rm -f clean_mac.sh.tmp

echo "✅ 已将所有find命令替换为/usr/bin/find"
echo ""

echo "📊 替换统计："
grep -c "/usr/bin/find" clean_mac.sh | xargs -I {} echo "  找到 {} 个/usr/bin/find命令"

echo ""
echo "🎯 现在清理功能应该能正常工作了！"
echo "备份文件已保存为: clean_mac.sh.backup"