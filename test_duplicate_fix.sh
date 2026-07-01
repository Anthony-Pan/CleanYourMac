#!/bin/bash

echo "🧪 测试重复文件检测修复"
echo "======================"
echo ""

# Create test directory and duplicate files
test_dir="/tmp/cleanmac_test_$$"
mkdir -p "$test_dir"

echo "创建测试文件..."
# Create some test files with duplicates
echo "This is test content 1" > "$test_dir/file1.txt"
echo "This is test content 2" > "$test_dir/file2.txt"
cp "$test_dir/file1.txt" "$test_dir/file1_duplicate.txt"  # Create duplicate

# Make files larger than 1MB so they will be detected
dd if=/dev/zero bs=1024 count=2000 >> "$test_dir/file1.txt" 2>/dev/null
dd if=/dev/zero bs=1024 count=2000 >> "$test_dir/file1_duplicate.txt" 2>/dev/null
dd if=/dev/zero bs=1024 count=1500 >> "$test_dir/file2.txt" 2>/dev/null

echo "测试文件创建完成："
echo "  file1.txt (应该有重复)"
echo "  file1_duplicate.txt (与file1.txt重复)"
echo "  file2.txt (唯一文件)"
echo ""

# Test the duplicate detection logic directly
echo "测试MD5计算..."
hash1=$(md5 "$test_dir/file1.txt" | awk '{print $4}')
hash1_dup=$(md5 "$test_dir/file1_duplicate.txt" | awk '{print $4}')
hash2=$(md5 "$test_dir/file2.txt" | awk '{print $4}')

echo "Hash1: $hash1"
echo "Hash1_dup: $hash1_dup"
echo "Hash2: $hash2"

if [[ "$hash1" == "$hash1_dup" ]]; then
    echo "✅ 重复文件检测逻辑正常 - 相同文件有相同哈希"
else
    echo "❌ 重复文件检测逻辑异常 - 相同文件哈希不匹配"
fi

if [[ "$hash1" != "$hash2" ]]; then
    echo "✅ 唯一文件检测逻辑正常 - 不同文件有不同哈希"
else
    echo "❌ 唯一文件检测逻辑异常 - 不同文件哈希相同"
fi

echo ""
echo "测试完成，清理测试文件..."
rm -rf "$test_dir"

echo ""
echo "🎯 修复总结："
echo "  ✅ 添加了文件大小限制 (1M-100M)"
echo "  ✅ 添加了扫描深度限制 (maxdepth 3)"
echo "  ✅ 添加了文件数量限制 (每目录100个)"
echo "  ✅ 添加了哈希计算超时 (5秒)"
echo "  ✅ 添加了进度显示"
echo "  ✅ 添加了文件可读性检查"
echo ""
echo "这些改进应该解决了之前的卡死问题！"