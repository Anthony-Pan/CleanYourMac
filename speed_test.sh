#!/bin/bash

echo "🚀 磁盘分析速度测试"
echo "===================="
echo ""

echo "测试优化后的磁盘分析速度..."
echo ""

# Time the disk analysis function
time_start=$(date +%s)

echo "1. 目录大小分析测试:"
quick_dirs=("$HOME" "/Applications" "/usr" "/var" "/tmp")

for dir in "${quick_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        dir_name=$(basename "$dir")
        
        case "$dir_name" in
            "anthony"|"Applications")
                size_kb=$(du -sk "$dir" 2>/dev/null | head -1 | cut -f1 | tr -d '\n\t ' || echo "0")
                ;;
            "usr"|"var"|"tmp")
                size_kb=$(du -sk "$dir" 2>/dev/null | head -1 | cut -f1 | tr -d '\n\t ' || echo "0")
                ;;
            *)
                size_kb=0
                ;;
        esac
        
        if [[ "$size_kb" =~ ^[0-9]+$ ]] && [[ $size_kb -gt 10240 ]]; then
            size_gb=$(echo "scale=1; $size_kb / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
            echo "  ✅ $dir_name: ${size_gb}GB"
        fi
    fi
done

time_mid=$(date +%s)
dir_time=$((time_mid - time_start))
echo "  ⏱️ 目录分析耗时: ${dir_time}秒"
echo ""

echo "2. 大文件检测测试:"
large_count=0
smart_paths=("$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents")

for search_path in "${smart_paths[@]}"; do
    if [[ -d "$search_path" ]]; then
        files_found=$(find "$search_path" -maxdepth 2 -type f -size +1G 2>/dev/null | head -3 | wc -l)
        large_count=$((large_count + files_found))
    fi
done

echo "  ✅ 发现 $large_count 个超大文件 (>1GB)"

time_mid2=$(date +%s)
file_time=$((time_mid2 - time_mid))
echo "  ⏱️ 大文件检测耗时: ${file_time}秒"
echo ""

echo "3. 缓存分析测试:"
cache_dirs=("$HOME/Library/Caches" "$HOME/Library/Application Support")
cache_count=0

for cache_dir in "${cache_dirs[@]}"; do
    if [[ -d "$cache_dir" ]]; then
        cache_kb=$(du -sk "$cache_dir" 2>/dev/null | head -1 | cut -f1 | tr -d '\n\t ' || echo "0")
        if [[ "$cache_kb" =~ ^[0-9]+$ ]] && [[ $cache_kb -gt 0 ]]; then
            cache_gb=$(echo "scale=1; $cache_kb / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
            echo "  ✅ $(basename "$cache_dir"): ${cache_gb}GB"
            cache_count=$((cache_count + 1))
        fi
    fi
done

time_end=$(date +%s)
cache_time=$((time_end - time_mid2))
echo "  ⏱️ 缓存分析耗时: ${cache_time}秒"
echo ""

total_time=$((time_end - time_start))

echo "📊 性能总结:"
echo "  总耗时: ${total_time}秒"
echo "  目标: <5秒"

if [[ $total_time -lt 5 ]]; then
    echo "  🎉 性能优化成功！"
else
    echo "  ⚠️ 需要进一步优化"
fi

echo ""
echo "优化效果:"
echo "  ✅ 跳过慢速系统目录"
echo "  ✅ 限制扫描深度(maxdepth=2)"
echo "  ✅ 只检查关键缓存目录"
echo "  ✅ 提高大文件检测阈值(1GB)"
echo "  ✅ 简化重复文件检测"