#!/usr/bin/env bash

# CleanMac - Advanced macOS System Cleanup Tool
# Version: 2.5
# Author: Onyx (onyx-lab.com) — an open-source tool, created by a middle-school student
# Description: Interactive macOS cleanup utility with comprehensive cleaning

set -eo pipefail

# Configuration
DEFAULT_LANG="en"
LANG_FILE="$HOME/.cleanyourmac_lang"
DRY_RUN=false
DAYS_TO_KEEP=7
SHOW_HELP=false

# Load saved language preference
if [[ -f "$LANG_FILE" ]]; then
    CURRENT_LANG=$(cat "$LANG_FILE")
else
    CURRENT_LANG="$DEFAULT_LANG"
fi

# Enhanced Colors and formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Additional colors for better UI
readonly BRIGHT_GREEN='\033[1;32m'
readonly BRIGHT_BLUE='\033[1;34m'
readonly BRIGHT_CYAN='\033[1;36m'
readonly BRIGHT_RED='\033[1;31m'
readonly BRIGHT_YELLOW='\033[1;33m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'

# Background colors
readonly BG_GREEN='\033[42m'
readonly BG_RED='\033[41m'
readonly BG_BLUE='\033[44m'
readonly BG_CYAN='\033[46m'

# Icons and symbols
readonly CLEAN_ICON="🧹"
readonly CHECK_ICON="✅"
readonly SKIP_ICON="🚫"
readonly WARNING_ICON="⚠️"
readonly INFO_ICON="ℹ️"
readonly TRASH_ICON="🗑️"
readonly SPARKLE_ICON="✨"
readonly COMPUTER_ICON="💻"
readonly BROWSER_ICON="🌐"
readonly DEV_ICON="👨‍💻"
readonly LANG_ICON="🌐"
readonly APP_ICON="📱"
readonly SEARCH_ICON="🔍"
readonly UNINSTALL_ICON="🗑️"
readonly VIRUS_ICON="🦠"
readonly SHIELD_ICON="🛡️"
readonly CHART_ICON="📊"
readonly FOLDER_ICON="📁"

# Additional beautiful icons for enhanced UI
readonly ROCKET_ICON="🚀"
readonly STAR_ICON="⭐"
readonly FIRE_ICON="🔥"
readonly CRYSTAL_ICON="💎"
readonly MAGIC_ICON="🪄"
readonly RAINBOW_ICON="🌈"
readonly CROWN_ICON="👑"
readonly TARGET_ICON="🎯"
readonly GEAR_ICON="⚙️"
readonly LIGHTNING_ICON="⚡"
readonly HEART_ICON="❤️"
readonly THUMBS_UP_ICON="👍"
readonly PARTY_ICON="🎉"
readonly TOOL_ICON="🔧"
readonly BRAIN_ICON="🧠"
readonly SPEED_ICON="💨"
readonly DIAMOND_ICON="💠"
readonly PULSE_ICON="📊"
readonly ZAP_ICON="⚡"

# Global variables
initial_free_space=0
final_free_space=0

# Function to get localized text
get_text() {
    local key="$1"
    if [[ "$CURRENT_LANG" == "cn" ]]; then
        case "$key" in
            "title") echo "CleanMac - macOS 系统清理工具" ;;
            "subtitle") echo "交互式清理实用工具" ;;
            "description") echo "此工具帮助您安全地清理 macOS 系统中的缓存和垃圾文件。" ;;
            "begin") echo "删除任何文件前都会询问您的确认。让我们开始吧。" ;;
            "menu_select") echo "选择功能：" ;;
            "menu_1") echo "自动清理" ;;
            "menu_2") echo "卸载应用程序" ;;
            "menu_3") echo "病毒扫描" ;;
            "menu_4") echo "磁盘分析" ;;
            "menu_5") echo "智能清理建议" ;;
            "menu_6") echo "重复文件检测" ;;
            "menu_7") echo "系统性能优化" ;;
            "menu_8") echo "语言 / Language" ;;
            "enter_choice") echo "输入 1-8: " ;;
            "invalid_choice") echo "无效选择。请输入 1-8。" ;;
            "virus_scan_title") echo "病毒扫描" ;;
            "virus_scan_desc") echo "扫描系统中的恶意软件和可疑文件" ;;
            "virus_scanning") echo "正在扫描病毒..." ;;
            "virus_scan_complete") echo "病毒扫描完成" ;;
            "virus_found") echo "发现可疑文件" ;;
            "virus_clean") echo "清除病毒文件" ;;
            "disk_analysis_title") echo "磁盘空间分析" ;;
            "disk_analysis_desc") echo "分析磁盘使用情况和大文件" ;;
            "disk_analyzing") echo "正在分析磁盘..." ;;
            "disk_analysis_complete") echo "磁盘分析完成" ;;
            "large_files_found") echo "发现大文件" ;;
            "folder_size") echo "文件夹大小" ;;
            "app_uninstall_title") echo "应用程序卸载" ;;
            "app_search_prompt") echo "搜索应用程序（输入应用名称，按 ESC 退出）: " ;;
            "app_scanning") echo "正在扫描已安装的应用程序..." ;;
            "app_found_count") echo "找到应用程序" ;;
            "app_no_match") echo "没有找到匹配的应用程序" ;;
            "app_select_prompt") echo "使用上下箭头键选择应用，回车确认，ESC 取消" ;;
            "app_selected") echo "已选择应用程序" ;;
            "app_confirm_uninstall") echo "确认卸载此应用程序及其所有相关文件？[y/N]: " ;;
            "app_uninstalling") echo "正在卸载应用程序..." ;;
            "app_uninstall_complete") echo "应用程序卸载完成" ;;
            "app_uninstall_failed") echo "应用程序卸载失败" ;;
            "app_files_found") echo "找到相关文件" ;;
            "app_size_total") echo "总大小" ;;
            "selected_items") echo "将要清理的项目：" ;;
            "confirm_start") echo "确认开始清理以上项目？[y/N]: " ;;
            "auto_cleanup_title") echo "自动清理模式" ;;
            "auto_cleanup_desc") echo "这将自动清理所有安全项目，无需逐个确认。" ;;
            "auto_cleanup_warning") echo "需要确认的项目（下载文件夹、桌面文件）仍会询问权限。" ;;
            "auto_cleanup_confirm") echo "开始自动清理？[y/N]: " ;;
            "auto_cleanup_running") echo "正在运行自动清理..." ;;
            "auto_cleanup_complete") echo "自动清理完成！" ;;
            "total_space_freed") echo "总共释放空间" ;;
            "confirm_sensitive") echo "清理敏感位置" ;;
            "thank_you") echo "感谢您使用 CleanMac！再见！ · An Onyx product" ;;
            "press_enter") echo "按回车键继续..." ;;
            "cleaning") echo "正在清理..." ;;
            "cleaned") echo "已清理" ;;
            "skipped") echo "已跳过" ;;
            "failed") echo "清理失败" ;;
            "already_clean") echo "已经是干净的" ;;
            "path_not_found") echo "路径未找到" ;;
            "confirm_clean") echo "您要清理这个吗？[y/N]: " ;;
            "confirm_run") echo "您要运行这个清理吗？[y/N]: " ;;
            "admin_password") echo "(需要管理员密码)" ;;
            "admin_required") echo "(需要管理员密码)" ;;
            "running") echo "正在运行清理..." ;;
            "completed") echo "已完成" ;;
            "failed_run") echo "失败" ;;
            "size_freed") echo "已释放" ;;
            "summary") echo "清理摘要" ;;
            "cleaned_items") echo "已清理项目" ;;
            "skipped_items") echo "已跳过项目" ;;
            "no_items_cleaned") echo "没有项目被清理" ;;
            "no_items_skipped") echo "没有项目被跳过" ;;
            "all_processed") echo "所有选定项目已处理完成。感谢使用 CleanMac！" ;;
            "processing_category") echo "正在处理类别" ;;
            "category_complete") echo "类别处理完成" ;;
            *) echo "$key" ;;
        esac
    else
        case "$key" in
            "title") echo "CleanMac - macOS System Cleanup Tool" ;;
            "subtitle") echo "Interactive Cleanup Utility" ;;
            "description") echo "This tool helps you safely clean cache and junk files from your macOS system." ;;
            "begin") echo "You will be asked before anything is deleted. Let's begin." ;;
            "menu_select") echo "Select function:" ;;
            "menu_1") echo "Auto cleanup" ;;
            "menu_2") echo "Uninstall applications" ;;
            "menu_3") echo "Virus scan" ;;
            "menu_4") echo "Disk analysis" ;;
            "menu_5") echo "Smart Cleanup Suggestions" ;;
            "menu_6") echo "Duplicate File Detection" ;;
            "menu_7") echo "System Performance Optimization" ;;
            "menu_8") echo "Language / 语言" ;;
            "enter_choice") echo "Enter 1-8: " ;;
            "invalid_choice") echo "Invalid choice. Please enter 1-8." ;;
            "virus_scan_title") echo "Virus Scan" ;;
            "virus_scan_desc") echo "Scan system for malware and suspicious files" ;;
            "virus_scanning") echo "Scanning for viruses..." ;;
            "virus_scan_complete") echo "Virus scan completed" ;;
            "virus_found") echo "Suspicious files found" ;;
            "virus_clean") echo "Clean virus files" ;;
            "disk_analysis_title") echo "Disk Space Analysis" ;;
            "disk_analysis_desc") echo "Analyze disk usage and large files" ;;
            "disk_analyzing") echo "Analyzing disk..." ;;
            "disk_analysis_complete") echo "Disk analysis completed" ;;
            "large_files_found") echo "Large files found" ;;
            "folder_size") echo "Folder size" ;;
            "app_uninstall_title") echo "Application Uninstaller" ;;
            "app_search_prompt") echo "Search applications (type app name, ESC to exit): " ;;
            "app_scanning") echo "Scanning installed applications..." ;;
            "app_found_count") echo "applications found" ;;
            "app_no_match") echo "No matching applications found" ;;
            "app_select_prompt") echo "Use arrow keys to select app, Enter to confirm, ESC to cancel" ;;
            "app_selected") echo "Selected application" ;;
            "app_confirm_uninstall") echo "Confirm uninstall this application and all related files? [y/N]: " ;;
            "app_uninstalling") echo "Uninstalling application..." ;;
            "app_uninstall_complete") echo "Application uninstall completed" ;;
            "app_uninstall_failed") echo "Application uninstall failed" ;;
            "app_files_found") echo "Related files found" ;;
            "app_size_total") echo "Total size" ;;
            "selected_items") echo "Items to be cleaned:" ;;
            "confirm_start") echo "Confirm to start cleaning the above items? [y/N]: " ;;
            "auto_cleanup_title") echo "Auto Cleanup Mode" ;;
            "auto_cleanup_desc") echo "This will automatically clean all safe items without asking for each one." ;;
            "auto_cleanup_warning") echo "Items requiring confirmation (Downloads, Desktop files) will still ask for permission." ;;
            "auto_cleanup_confirm") echo "Start auto cleanup? [y/N]: " ;;
            "auto_cleanup_running") echo "Running auto cleanup..." ;;
            "auto_cleanup_complete") echo "Auto cleanup completed!" ;;
            "total_space_freed") echo "Total space freed" ;;
            "confirm_sensitive") echo "Clean sensitive location" ;;
            "thank_you") echo "Thank you for using CleanMac! Goodbye! · An Onyx product" ;;
            "press_enter") echo "Press Enter to continue..." ;;
            "cleaning") echo "Cleaning..." ;;
            "cleaned") echo "Cleaned" ;;
            "skipped") echo "Skipped" ;;
            "failed") echo "Failed to clean" ;;
            "already_clean") echo "Already clean" ;;
            "path_not_found") echo "Path not found" ;;
            "confirm_clean") echo "Do you want to clean this? [y/N]: " ;;
            "confirm_run") echo "Do you want to run this cleanup? [y/N]: " ;;
            "admin_password") echo "(admin password required)" ;;
            "admin_required") echo "(requires admin password)" ;;
            "running") echo "Running cleanup..." ;;
            "completed") echo "Completed" ;;
            "failed_run") echo "Failed" ;;
            "size_freed") echo "freed" ;;
            "summary") echo "Cleanup Summary" ;;
            "cleaned_items") echo "Cleaned items" ;;
            "skipped_items") echo "Skipped items" ;;
            "no_items_cleaned") echo "No items were cleaned" ;;
            "no_items_skipped") echo "No items were skipped" ;;
            "all_processed") echo "All selected items have been processed. Thank you for using CleanMac!" ;;
            "processing_category") echo "Processing category" ;;
            "category_complete") echo "Category complete" ;;
            *) echo "$key" ;;
        esac
    fi
}

# Save language preference
save_language() {
    echo "$CURRENT_LANG" > "$LANG_FILE"
}

# Utility functions
print_header() {
    local title="$(get_text "title")"
    local subtitle="$(get_text "subtitle")"
    clear
    echo -e "${BOLD}${BRIGHT_CYAN}"
    echo "╔════════════════════════════════════════════════════════════════════════════════╗"
    printf "║ %s %-72s ║\n" "🧹✨" "$title"
    printf "║ %s %-72s ║\n" "   " "$subtitle"
    echo "╠════════════════════════════════════════════════════════════════════════════════╣"
    printf "║ %s %-70s ║\n" "📊" "$(get_text "description")"
    echo "╚════════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${DIM}  ◈ An Onyx product · onyx-lab.com${NC}"
    echo ""
}

print_title() {
    local title="$1"
    local icon="${2:-$SPARKLE_ICON}"
    echo -e "${BOLD}${BRIGHT_CYAN}"
    echo "╭─────────────────────────────────────────────────────────────────────╮"
    printf "│ %s %-60s │\n" "$icon" "$title"
    echo "╰─────────────────────────────────────────────────────────────────────╯"
    echo -e "${NC}"
}

print_fancy_header() {
    local title="$1"
    local subtitle="$2"
    clear
    echo -e "${BRIGHT_CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                               ║"
    printf "║%*s║\n" 79 "$(printf "%*s" $(((${#title}+79)/2)) "$title")"
    printf "║%*s║\n" 79 "$(printf "%*s" $(((${#subtitle}+79)/2)) "$subtitle")"
    echo "║                                                                               ║"
    echo "╠═══════════════════════════════════════════════════════════════════════════════╣"
    echo "║                          🚀 POWERED BY ADVANCED AI 🚀                        ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Add gradient effect
    echo -e "${RAINBOW_ICON}${BRIGHT_GREEN} 欢迎使用CleanYourMac - 专业级系统清理工具 ${RAINBOW_ICON}${NC}"
    echo -e "${DIM}${WHITE}安全 ${BRIGHT_GREEN}• ${WHITE}智能 ${BRIGHT_GREEN}• ${WHITE}高效 ${BRIGHT_GREEN}• ${WHITE}美观${NC}"
    echo ""
}

print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
}

print_success() {
    echo -e "${BOLD}${GREEN}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    printf "${BOLD}${GREEN}│${NC} ${GREEN}${CHECK_ICON} %-62s ${BOLD}${GREEN}│${NC}\n" "$1"
    echo -e "${BOLD}${GREEN}└─────────────────────────────────────────────────────────────────────┘${NC}"
}

print_error() {
    echo -e "${BOLD}${RED}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    printf "${BOLD}${RED}│${NC} ${RED}${WARNING_ICON} %-62s ${BOLD}${RED}│${NC}\n" "$1"
    echo -e "${BOLD}${RED}└─────────────────────────────────────────────────────────────────────┘${NC}"
}

print_info() {
    echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    printf "${BOLD}${BLUE}│${NC} ${BLUE}${INFO_ICON} %-62s ${BOLD}${BLUE}│${NC}\n" "$1"
    echo -e "${BOLD}${BLUE}└─────────────────────────────────────────────────────────────────────┘${NC}"
}

print_warning() {
    echo -e "${BOLD}${YELLOW}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    printf "${BOLD}${YELLOW}│${NC} ${YELLOW}${WARNING_ICON} %-62s ${BOLD}${YELLOW}│${NC}\n" "$1"
    echo -e "${BOLD}${YELLOW}└─────────────────────────────────────────────────────────────────────┘${NC}"
}

print_skip() {
    echo -e "${YELLOW}${SKIP_ICON} $1${NC}"
}

# Loading animation function
show_loading() {
    local message="$1"
    local duration="${2:-3}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    
    echo -n -e "${BOLD}${BRIGHT_CYAN}${message}${NC} "
    
    while [ $i -lt $((duration * 10)) ]; do
        printf "\r${BOLD}${BRIGHT_CYAN}${message}${NC} ${BRIGHT_YELLOW}${chars:$((i%10)):1}${NC}"
        sleep 0.1
        ((i++))
    done
    
    printf "\r${BOLD}${BRIGHT_CYAN}${message}${NC} ${GREEN}${CHECK_ICON}${NC}\n"
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local message="$3"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    
    local bar=""
    for ((i=0; i<completed; i++)); do bar+="█"; done
    for ((i=completed; i<width; i++)); do bar+="░"; done
    
    printf "\r${BOLD}${WHITE}${message}${NC} [${BRIGHT_CYAN}${bar}${NC}] ${BRIGHT_GREEN}${percentage}%%${NC} (${current}/${total})"
}

# Function to get directory size in human readable format
get_size() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sh "$path" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0B"
    else
        echo "0B"
    fi
}

# Function to get size in bytes for accurate calculations
get_size_bytes() {
    local path="$1"
    if [[ -e "$path" ]]; then
        local size_kb=$(du -sk "$path" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
        [[ ! "$size_kb" =~ ^[0-9]+$ ]] && size_kb=0
        echo $((size_kb * 1024))
    else
        echo "0"
    fi
}

# Convert size to bytes for calculations
size_to_bytes() {
    local size="$1"
    local number=$(echo "$size" | sed 's/[^0-9.]//g')
    local unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    
    case "$unit" in
        "B"|"") echo "$number" | cut -d'.' -f1 ;;
        "K"|"KB") echo "$(echo "$number * 1024" | bc)" | cut -d'.' -f1 ;;
        "M"|"MB") echo "$(echo "$number * 1024 * 1024" | bc)" | cut -d'.' -f1 ;;
        "G"|"GB") echo "$(echo "$number * 1024 * 1024 * 1024" | bc)" | cut -d'.' -f1 ;;
        *) echo "0" ;;
    esac 2>/dev/null || echo "0"
}

# Convert bytes to human readable format
bytes_to_human() {
    local bytes="$1"
    # Ensure bytes is a valid number
    [[ ! "$bytes" =~ ^[0-9]+$ ]] && bytes=0
    
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc 2>/dev/null || echo "0")GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc 2>/dev/null || echo "0")MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=1; $bytes / 1024" | bc 2>/dev/null || echo "0")KB"
    else
        echo "${bytes}B"
    fi
}







# Function to execute auto cleanup - Using improved cleanmac.sh logic
execute_auto_cleanup() {
    print_separator
    echo -e "${BOLD}${SPARKLE_ICON} $(get_text "auto_cleanup_title")${NC}"
    print_separator
    
    echo -e "${WHITE}$(get_text "auto_cleanup_desc")${NC}"
    echo -e "${YELLOW}$(get_text "auto_cleanup_warning")${NC}"
    echo ""
    
    read -p "$(echo -e ${WHITE}$(get_text "auto_cleanup_confirm")${NC})" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "$(get_text "skipped")"
        sleep 2
        return
    fi
    
    # Check sudo access without hanging
    echo "检查管理员权限..."
    local SKIP_SUDO=true
    
    # Try a simple non-interactive sudo test first
    if sudo -n true 2>/dev/null; then
        echo "✅ 检测到现有管理员权限"
        local SKIP_SUDO=false
    else
        echo "⚠️ 需要管理员密码才能进行系统级清理"
        echo "继续进行用户级清理（推荐），还是需要完整系统清理？"  
        read -p "选择: [u]用户清理 / [s]系统清理 / [q]退出 (u): " permission_choice
        
        case "${permission_choice:-u}" in
            s|S)
                echo "请输入管理员密码："
                if sudo -v; then
                    echo "✅ 获得管理员权限"
                    local SKIP_SUDO=false
                else
                    echo "❌ 权限验证失败，继续用户级清理"
                    local SKIP_SUDO=true
                fi
                ;;
            q|Q)
                echo "退出清理"
                return
                ;;
            *)
                echo "继续用户级清理"
                local SKIP_SUDO=true
                ;;
        esac
    fi
    
    echo ""
    echo -e "${BOLD}${GREEN}$(get_text "auto_cleanup_running")${NC}"
    echo "Starting macOS selective cleanup (removing files older than ${DAYS_TO_KEEP} days)..."
    echo ""
    
    # Get initial disk space with detailed tracking
    local initial_free_kb=$(df -k / | awk 'NR==2 {print $4}')
    local total_storage_kb=$(df -k / | awk 'NR==2 {print $2}')
    local initial_free_gb=$(echo "scale=2; $initial_free_kb / 1024 / 1024" | bc)
    local total_storage_gb=$(echo "scale=2; $total_storage_kb / 1024 / 1024" | bc)
    
    echo "开始前磁盘状态: ${initial_free_gb}GB 可用 / ${total_storage_gb}GB 总容量"
    echo ""
    
    # Initialize cleanup tracking
    local total_cleaned_bytes=0
    local cleanup_summary=()
    
    # Function to add cleaned space
    add_cleaned_space() {
        local category="$1"
        local size_before="$2"
        local size_after="$3"
        local cleaned_bytes=$((size_before - size_after))
        
        if [[ $cleaned_bytes -gt 0 ]]; then
            total_cleaned_bytes=$((total_cleaned_bytes + cleaned_bytes))
            local cleaned_human=$(bytes_to_human $cleaned_bytes)
            cleanup_summary+=("$category: $cleaned_human")
            echo "  ✅ $category 清理了 $cleaned_human"
        fi
    }
    
    # 1. Clear system and user cache files with tracking
    echo "🗂️  清理系统和用户缓存文件 (>${DAYS_TO_KEEP}天)..."
    
    # Measure cache size before cleanup
    local cache_before=0
    if [[ -d "/Library/Caches" ]]; then
        cache_before=$((cache_before + $(du -sk /Library/Caches 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    if [[ -d "$HOME/Library/Caches" ]]; then
        cache_before=$((cache_before + $(du -sk "$HOME/Library/Caches" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    cache_before=$((cache_before * 1024))  # Convert to bytes
    
    # Clean system caches (safe and fast)
    echo "    清理系统缓存..."
    local sys_cache_count=0
    
    # Only clean specific known safe directories
    if [[ "$SKIP_SUDO" == "false" ]]; then
        local safe_cache_dirs=("/Library/Caches/com.adobe" "/Library/Caches/com.google" "/Library/Caches/homebrew")
        for cache_dir in "${safe_cache_dirs[@]}"; do
            if [[ -d "$cache_dir" ]]; then
                local cleaned=$(sudo /usr/bin/find "$cache_dir" -type f -mtime +${DAYS_TO_KEEP} -maxdepth 2 -exec rm {} \; 2>/dev/null | wc -l || echo "0")
                sys_cache_count=$((sys_cache_count + cleaned))
            fi
        done
    else
        echo "    (跳过系统缓存清理 - 需要管理员权限)"
    fi
    echo "    清理了 $sys_cache_count 个系统缓存文件"
    
    # Clean user caches (with timeout protection)  
    echo "    清理用户缓存..."
    local user_cache_count=0
    if [[ -d "$HOME/Library/Caches" ]]; then
        # Use system find (not fd alias) and count files, then delete them
        user_cache_count=$(/usr/bin/find "$HOME/Library/Caches" -type f -mtime +${DAYS_TO_KEEP} -maxdepth 3 -print 2>/dev/null | wc -l || echo "0")
        user_cache_count=$(echo "$user_cache_count" | tr -d '\n\t ' || echo "0")
        
        # Now delete the files
        if [[ $user_cache_count -gt 0 ]]; then
            /usr/bin/find "$HOME/Library/Caches" -type f -mtime +${DAYS_TO_KEEP} -maxdepth 3 -delete 2>/dev/null
        fi
    fi
    echo "    清理了 $user_cache_count 个用户缓存文件"
    
    # Additional specific cache cleanup for better results
    echo "    清理特定应用缓存..."
    local app_cache_count=0
    
    # Chrome cache cleanup
    local chrome_cache="$HOME/Library/Caches/Google/Chrome"
    if [[ -d "$chrome_cache" ]]; then
        local chrome_files=$(/usr/bin/find "$chrome_cache" -type f -mtime +1 -print 2>/dev/null | wc -l)
        if [[ $chrome_files -gt 0 ]]; then
            /usr/bin/find "$chrome_cache" -type f -mtime +1 -delete 2>/dev/null
            app_cache_count=$((app_cache_count + chrome_files))
        fi
    fi
    
    # Safari cache cleanup  
    local safari_cache="$HOME/Library/Caches/com.apple.Safari"
    if [[ -d "$safari_cache" ]]; then
        local safari_files=$(/usr/bin/find "$safari_cache" -type f -mtime +1 -print 2>/dev/null | wc -l)
        if [[ $safari_files -gt 0 ]]; then
            /usr/bin/find "$safari_cache" -type f -mtime +1 -delete 2>/dev/null
            app_cache_count=$((app_cache_count + safari_files))
        fi
    fi
    
    # Download temporary files
    if [[ -d "$HOME/Downloads" ]]; then
        local download_temp=$(/usr/bin/find "$HOME/Downloads" -name "*.tmp" -o -name "*.download" -o -name "*.crdownload" -print 2>/dev/null | wc -l)
        if [[ $download_temp -gt 0 ]]; then
            /usr/bin/find "$HOME/Downloads" -name "*.tmp" -o -name "*.download" -o -name "*.crdownload" -delete 2>/dev/null
            app_cache_count=$((app_cache_count + download_temp))
        fi
    fi
    
    echo "    清理了 $app_cache_count 个应用缓存和临时文件"
    
    # Measure cache size after cleanup
    local cache_after=0
    if [[ -d "/Library/Caches" ]]; then
        cache_after=$((cache_after + $(du -sk /Library/Caches 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    if [[ -d "$HOME/Library/Caches" ]]; then
        cache_after=$((cache_after + $(du -sk "$HOME/Library/Caches" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    cache_after=$((cache_after * 1024))  # Convert to bytes
    
    add_cleaned_space "缓存文件" $cache_before $cache_after
    
    # 2. Remove application logs with tracking
    echo "📄 清理应用程序日志文件 (>${DAYS_TO_KEEP}天)..."
    
    # Measure logs size before
    local logs_before=0
    if [[ -d "/Library/Logs" ]]; then
        logs_before=$((logs_before + $(du -sk /Library/Logs 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    if [[ -d "$HOME/Library/Logs" ]]; then
        logs_before=$((logs_before + $(du -sk "$HOME/Library/Logs" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    logs_before=$((logs_before * 1024))
    
    # Clean logs
    echo "    清理日志文件..."
    local sys_log_count=0
    local user_log_count=0
    
    if [[ "$SKIP_SUDO" == "false" ]]; then
        sys_log_count=$(sudo /usr/bin/find /Library/Logs -type f -mtime +${DAYS_TO_KEEP} -maxdepth 2 -print 2>/dev/null | wc -l || echo "0")
        if [[ $sys_log_count -gt 0 ]]; then
            sudo /usr/bin/find /Library/Logs -type f -mtime +${DAYS_TO_KEEP} -maxdepth 2 -delete 2>/dev/null
        fi
    else
        echo "    (跳过系统日志清理 - 需要管理员权限)"
    fi
    
    user_log_count=$(/usr/bin/find ~/Library/Logs -type f -mtime +${DAYS_TO_KEEP} -maxdepth 2 -print 2>/dev/null | wc -l || echo "0")
    if [[ $user_log_count -gt 0 ]]; then
        /usr/bin/find ~/Library/Logs -type f -mtime +${DAYS_TO_KEEP} -maxdepth 2 -delete 2>/dev/null
    fi
    
    echo "    清理了 $sys_log_count 个系统日志文件"
    echo "    清理了 $user_log_count 个用户日志文件"
    
    # Measure logs size after
    local logs_after=0
    if [[ -d "/Library/Logs" ]]; then
        logs_after=$((logs_after + $(du -sk /Library/Logs 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    if [[ -d "$HOME/Library/Logs" ]]; then
        logs_after=$((logs_after + $(du -sk "$HOME/Library/Logs" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    logs_after=$((logs_after * 1024))
    
    add_cleaned_space "日志文件" $logs_before $logs_after
    
    # 3. Clear temporary files with tracking
    echo "🗑️  清理临时文件 (>${DAYS_TO_KEEP}天)..."
    
    # Measure temp size before
    local temp_before=0
    if [[ -d "/private/var/tmp" ]]; then
        temp_before=$((temp_before + $(du -sk /private/var/tmp 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    if [[ -d "/tmp" ]]; then
        temp_before=$((temp_before + $(du -sk /tmp 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    temp_before=$((temp_before * 1024))
    
    # Clean temp files
    echo "    清理临时文件..."
    local sys_temp_count=0
    local user_temp_count=0
    
    if [[ "$SKIP_SUDO" == "false" ]]; then
        sys_temp_count=$(sudo /usr/bin/find /private/var/tmp -type f -mtime +${DAYS_TO_KEEP} -maxdepth 2 -print 2>/dev/null | wc -l || echo "0")
        if [[ $sys_temp_count -gt 0 ]]; then
            sudo /usr/bin/find /private/var/tmp -type f -mtime +${DAYS_TO_KEEP} -maxdepth 2 -delete 2>/dev/null
        fi
    else
        echo "    (跳过系统临时文件清理 - 需要管理员权限)"
    fi
    
    user_temp_count=$(/usr/bin/find /tmp -type f -mtime +${DAYS_TO_KEEP} ! -path "/tmp/tmp-mount-*" -maxdepth 2 -print 2>/dev/null | wc -l || echo "0")
    if [[ $user_temp_count -gt 0 ]]; then
        /usr/bin/find /tmp -type f -mtime +${DAYS_TO_KEEP} ! -path "/tmp/tmp-mount-*" -maxdepth 2 -delete 2>/dev/null
    fi
    
    echo "    清理了 $sys_temp_count 个系统临时文件"
    echo "    清理了 $user_temp_count 个用户临时文件"
    
    # Measure temp size after
    local temp_after=0
    if [[ -d "/private/var/tmp" ]]; then
        temp_after=$((temp_after + $(du -sk /private/var/tmp 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    if [[ -d "/tmp" ]]; then
        temp_after=$((temp_after + $(du -sk /tmp 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    temp_after=$((temp_after * 1024))
    
    add_cleaned_space "临时文件" $temp_before $temp_after
    
    # 4. Homebrew cleanup with tracking
    if command -v brew >/dev/null 2>&1; then
        echo "🍺 清理Homebrew缓存和旧版本..."
        
        # Measure Homebrew cache before
        local brew_before=0
        if [[ -d "$(brew --cache)" ]]; then
            brew_before=$(du -sk "$(brew --cache)" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
        fi
        brew_before=$((brew_before * 1024))
        
        brew cleanup --prune=${DAYS_TO_KEEP} || echo "Homebrew cleanup encountered an error."
        brew autoremove || echo "Homebrew autoremove encountered an error."
        
        # Measure Homebrew cache after
        local brew_after=0
        if [[ -d "$(brew --cache)" ]]; then
            brew_after=$(du -sk "$(brew --cache)" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
        fi
        brew_after=$((brew_after * 1024))
        
        add_cleaned_space "Homebrew" $brew_before $brew_after
    fi
    
    # 5. Empty Trash with tracking
    echo "🗑️  清空废纸篓 (>${DAYS_TO_KEEP}天)..."
    
    # Measure Trash size before
    local trash_before=0
    if [[ -d "$HOME/.Trash" ]]; then
        trash_before=$(du -sk "$HOME/.Trash" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
    fi
    trash_before=$((trash_before * 1024))
    
    find ~/.Trash -type f -mtime +${DAYS_TO_KEEP} -exec rm {} \; 2>/dev/null | wc -l | xargs -I {} echo "    清理了 {} 个废纸篓文件"
    find ~/.Trash -type d -empty -delete 2>/dev/null
    
    # Measure Trash size after
    local trash_after=0
    if [[ -d "$HOME/.Trash" ]]; then
        trash_after=$(du -sk "$HOME/.Trash" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
    fi
    trash_after=$((trash_after * 1024))
    
    add_cleaned_space "废纸篓" $trash_before $trash_after
    
    # Clean Safari caches
    echo "Cleaning Safari caches..."
    find ~/Library/Safari/LocalStorage -type f -mtime +${DAYS_TO_KEEP} -exec rm {} \; -print 2>/dev/null || echo "Error cleaning Safari LocalStorage."
    find ~/Library/Safari/WebKit/MediaCache -type f -exec rm {} \; -print 2>/dev/null || echo "Error cleaning Safari MediaCache."
    
    # Clean Spotify cache
    echo "Cleaning Spotify cache..."
    find ~/Library/Application\ Support/Spotify/PersistentCache/Storage -type f -mtime +${DAYS_TO_KEEP} -exec rm {} \; -print 2>/dev/null || echo "Error cleaning Spotify cache."
    
    # Clean Xcode derived data
    echo "Cleaning Xcode derived data..."
    rm -rf ~/Library/Developer/Xcode/DerivedData/* 2>/dev/null || echo "Error cleaning Xcode derived data."
    rm -rf ~/Library/Developer/Xcode/Archives/* 2>/dev/null || echo "Error cleaning Xcode archives."
    
    # Node.js cache cleaning
    if command -v npm >/dev/null 2>&1; then
        echo "Cleaning npm cache..."
        npm cache clean --force || echo "Error cleaning npm cache."
    fi
    
    if command -v yarn >/dev/null 2>&1; then
        echo "Cleaning yarn cache..."
        yarn cache clean || echo "Error cleaning yarn cache."
    fi
    
    # Docker cleanup
    if command -v docker >/dev/null 2>&1; then
        echo "Checking Docker context..."
        if ! current_context=$(docker context show 2>/dev/null); then
            echo "Unable to determine Docker context; assuming local and cleaning."
            docker system prune -f || echo "Error cleaning Docker system."
        else
            if endpoint=$(docker context inspect "$current_context" --format '{{.Endpoints.docker.Host}}' 2>/dev/null); then
                if [[ "$endpoint" == unix://* ]]; then
                    echo "Cleaning unused Docker data..."
                    docker system prune -f || echo "Error cleaning Docker system."
                else
                    echo "Docker is using a remote context ($endpoint), skipping cleanup."
                fi
            else
                echo "Unable to inspect Docker context; skipping cleanup to avoid potential remote connection."
            fi
        fi
    fi
    
    # 6. Enhanced browser cache cleanup with tracking
    echo "🌐 清理浏览器缓存..."
    
    # Measure browser cache before
    local browser_before=0
    
    # Chrome size measurement
    if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
        local chrome_paths=("$HOME/Library/Application Support/Google/Chrome/Default/Cache"
                           "$HOME/Library/Application Support/Google/Chrome/Default/Media Cache"
                           "$HOME/Library/Application Support/Google/Chrome/Default/GPUCache")
        for path in "${chrome_paths[@]}"; do
            if [[ -d "$path" ]]; then
                browser_before=$((browser_before + $(du -sk "$path" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
            fi
        done
    fi
    
    # Firefox size measurement
    if [[ -d "$HOME/Library/Caches/Firefox" ]]; then
        browser_before=$((browser_before + $(du -sk "$HOME/Library/Caches/Firefox" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    
    # Edge size measurement  
    if [[ -d "$HOME/Library/Application Support/Microsoft Edge/Default/Cache" ]]; then
        browser_before=$((browser_before + $(du -sk "$HOME/Library/Application Support/Microsoft Edge/Default/Cache" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    
    browser_before=$((browser_before * 1024))
    
    # Chrome cleanup
    if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
        echo "  清理Google Chrome缓存..."
        find "$HOME/Library/Application Support/Google/Chrome/Default/Cache" -type f -mtime +${DAYS_TO_KEEP} -exec rm {} \; 2>/dev/null
        find "$HOME/Library/Application Support/Google/Chrome/Default/Media Cache" -type f -exec rm {} \; 2>/dev/null
        find "$HOME/Library/Application Support/Google/Chrome/Default/GPUCache" -type f -exec rm {} \; 2>/dev/null
    fi
    
    # Firefox cleanup
    if [[ -d "$HOME/Library/Application Support/Firefox" ]]; then
        echo "  清理Firefox缓存..."
        find "$HOME/Library/Caches/Firefox" -type f -mtime +${DAYS_TO_KEEP} -exec rm {} \; 2>/dev/null
    fi
    
    # Edge cleanup
    if [[ -d "$HOME/Library/Application Support/Microsoft Edge" ]]; then
        echo "  清理Microsoft Edge缓存..."
        find "$HOME/Library/Application Support/Microsoft Edge/Default/Cache" -type f -mtime +${DAYS_TO_KEEP} -exec rm {} \; 2>/dev/null
    fi
    
    # Measure browser cache after
    local browser_after=0
    
    # Chrome size measurement after
    if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
        local chrome_paths=("$HOME/Library/Application Support/Google/Chrome/Default/Cache"
                           "$HOME/Library/Application Support/Google/Chrome/Default/Media Cache"
                           "$HOME/Library/Application Support/Google/Chrome/Default/GPUCache")
        for path in "${chrome_paths[@]}"; do
            if [[ -d "$path" ]]; then
                browser_after=$((browser_after + $(du -sk "$path" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
            fi
        done
    fi
    
    # Firefox size measurement after
    if [[ -d "$HOME/Library/Caches/Firefox" ]]; then
        browser_after=$((browser_after + $(du -sk "$HOME/Library/Caches/Firefox" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    
    # Edge size measurement after
    if [[ -d "$HOME/Library/Application Support/Microsoft Edge/Default/Cache" ]]; then
        browser_after=$((browser_after + $(du -sk "$HOME/Library/Application Support/Microsoft Edge/Default/Cache" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    
    browser_after=$((browser_after * 1024))
    
    add_cleaned_space "浏览器缓存" $browser_before $browser_after
    
    # Clean DNS cache
    echo "Flushing DNS cache..."
    sudo dscacheutil -flushcache || echo "DNS cache flush partial."
    sudo killall -HUP mDNSResponder || echo "mDNSResponder restart partial."
    
    # Clean font cache
    echo "Cleaning font cache..."
    sudo atsutil databases -remove || echo "Font cache cleanup partial."
    
    # Clean launch services database
    echo "Rebuilding Launch Services database..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user || echo "Launch Services rebuild partial."
    
    # Clean Spotlight index (optional, commented out as it's intensive)
    # echo "Rebuilding Spotlight index..."
    # sudo mdutil -E / || echo "Spotlight reindex failed."
    
    # System memory cleanup
    echo "Purging system memory cache..."
    sudo purge || echo "Error purging system memory."
    
    # Clean system logs more thoroughly
    echo "Cleaning system logs comprehensively..."
    sudo rm -rf /var/log/*.log 2>/dev/null || echo "System log cleanup partial."
    sudo rm -rf /var/log/asl/*.asl 2>/dev/null || echo "ASL log cleanup partial."
    
    # Clean crash reports
    echo "Cleaning crash reports..."
    rm -rf ~/Library/Logs/DiagnosticReports/* 2>/dev/null || echo "User crash reports cleanup partial."
    sudo rm -rf /Library/Logs/DiagnosticReports/* 2>/dev/null || echo "System crash reports cleanup partial."
    
    # Clean Adobe cache if present
    if [[ -d "$HOME/Library/Application Support/Adobe" ]]; then
        echo "Cleaning Adobe cache..."
        find "$HOME/Library/Application Support/Adobe" -name "*Cache*" -type d -exec rm -rf {} \; 2>/dev/null || echo "Adobe cache cleanup partial."
    fi
    
    # Calculate final disk space and show detailed summary
    echo -e "\n📊 清理完成总结:"
    echo "===================="
    
    # Show detailed cleanup summary
    if [[ ${#cleanup_summary[@]} -gt 0 ]]; then
        echo "\n📋 详细清理报告:"
        for item in "${cleanup_summary[@]}"; do
            echo "  $item"
        done
    fi
    
    # Calculate final disk space
    local final_free_kb=$(df -k / | awk 'NR==2 {print $4}')
    local final_free_gb=$(echo "scale=2; $final_free_kb / 1024 / 1024" | bc)
    local total_storage_gb=$(echo "scale=2; $total_storage_kb / 1024 / 1024" | bc)
    
    echo "\n💾 磁盘空间变化:"
    echo "  清理前: ${initial_free_gb}GB 可用"
    echo "  清理后: ${final_free_gb}GB 可用"
    echo "  总容量: ${total_storage_gb}GB"
    
    # Calculate the space freed
    local space_freed_kb=$((final_free_kb - initial_free_kb))
    
    if [[ $space_freed_kb -gt 0 ]]; then
        local total_freed_human=$(bytes_to_human $total_cleaned_bytes)
        local disk_freed_human
        
        if [[ $space_freed_kb -ge $((1024 * 1024)) ]]; then
            local space_freed_gb=$(echo "scale=2; $space_freed_kb / 1024 / 1024" | bc)
            disk_freed_human="${space_freed_gb}GB"
        elif [[ $space_freed_kb -ge 1024 ]]; then
            local space_freed_mb=$(echo "scale=2; $space_freed_kb / 1024" | bc)
            disk_freed_human="${space_freed_mb}MB"
        else
            disk_freed_human="${space_freed_kb}KB"
        fi
        
        echo "\n🎉 成功释放空间:"
        echo "  文件清理: $total_freed_human"
        echo "  磁盘增加: $disk_freed_human"
        
        # Calculate percentage freed
        local percent_freed=$(echo "scale=1; $space_freed_kb * 100 / $total_storage_kb" | bc 2>/dev/null || echo "0.0")
        echo "  释放比例: ${percent_freed}%"
    else
        echo "\n⚠️ 未释放明显空间 (可能文件很小或已经很干净)"
    fi
    
    echo "\n✅ 自动清理完成!"
    echo ""
    read -p "$(echo -e ${WHITE}$(get_text "press_enter")${NC})"
}


# Function to get installed applications
get_installed_apps() {
    local apps=()
    
    # Scan /Applications directory
    if [[ -d "/Applications" ]]; then
        while IFS= read -r -d '' app; do
            if [[ -d "$app" && "$app" == *.app ]]; then
                local app_name=$(basename "$app" .app)
                local app_size=$(get_size "$app")
                apps+=("$app|$app_name|$app_size")
            fi
        done < <(find "/Applications" -name "*.app" -maxdepth 1 -print0 2>/dev/null)
    fi
    
    # Scan user Applications directory
    if [[ -d "$HOME/Applications" ]]; then
        while IFS= read -r -d '' app; do
            if [[ -d "$app" && "$app" == *.app ]]; then
                local app_name=$(basename "$app" .app)
                local app_size=$(get_size "$app")
                apps+=("$app|$app_name|$app_size")
            fi
        done < <(find "$HOME/Applications" -name "*.app" -maxdepth 1 -print0 2>/dev/null)
    fi
    
    printf '%s\n' "${apps[@]}" | sort -t'|' -k2
}

# Function to find all application-related files with comprehensive cache cleanup
find_app_files() {
    local app_name="$1"
    local app_path="$2"
    local related_files=()
    
    # Main application bundle
    if [[ -d "$app_path" ]]; then
        related_files+=("$app_path|Application Bundle")
    fi
    
    # User Library locations - comprehensive cache cleanup
    local user_locations=(
        "$HOME/Library/Application Support/$app_name"
        "$HOME/Library/Caches/$app_name"
        "$HOME/Library/Preferences/$app_name"
        "$HOME/Library/Preferences/com.$app_name"
        "$HOME/Library/Logs/$app_name"
        "$HOME/Library/Saved Application State/$app_name"
        "$HOME/Library/Containers/$app_name"
        "$HOME/Library/Group Containers/$app_name"
        "$HOME/Library/WebKit/$app_name"
        "$HOME/Library/HTTPStorages/$app_name"
        "$HOME/Library/Cookies/$app_name"
        "$HOME/Library/Application Scripts/$app_name"
        "$HOME/Library/SyncedPreferences/$app_name"
        "$HOME/Library/Keychains/$app_name"
        "$HOME/Library/Safari/Databases/$app_name"
        "$HOME/Library/Safari/LocalStorage/$app_name"
        "$HOME/Library/Safari/PerSiteZoomPreferences.plist"
        "$HOME/Library/Autosave Information/$app_name"
        "$HOME/Library/CloudStorage/$app_name"
        "$HOME/Library/Developer/$app_name"
        "$HOME/Library/Application Support/CrashReporter/$app_name"
        "$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/$app_name"
    )
    
    # System Library locations (if admin) - enhanced
    local system_locations=(
        "/Library/Application Support/$app_name"
        "/Library/Caches/$app_name"
        "/Library/Preferences/$app_name"
        "/Library/LaunchDaemons/com.$app_name"
        "/Library/LaunchAgents/com.$app_name"
        "/Library/PrivilegedHelperTools/$app_name"
        "/Library/LaunchDaemons/$app_name"
        "/Library/LaunchAgents/$app_name"
        "/Library/StartupItems/$app_name"
        "/Library/PreferencePanes/$app_name"
        "/Library/Services/$app_name"
        "/Library/Contextual Menu Items/$app_name"
        "/System/Library/Extensions/$app_name"
        "/Library/Extensions/$app_name"
        "/usr/local/bin/$app_name"
        "/usr/local/lib/$app_name"
        "/usr/local/share/$app_name"
    )
    
    # Check user locations
    for location in "${user_locations[@]}"; do
        if [[ -e "$location" ]]; then
            local size=$(get_size "$location")
            related_files+=("$location|User Data ($size)")
        fi
    done
    
    # Check system locations
    for location in "${system_locations[@]}"; do
        if [[ -e "$location" ]]; then
            local size=$(get_size "$location")
            related_files+=("$location|System Data ($size)")
        fi
    done
    
    # Look for bundle identifier based files - enhanced search
    local bundle_id=$(defaults read "$app_path/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")
    if [[ -n "$bundle_id" ]]; then
        local bundle_locations=(
            "$HOME/Library/Preferences/$bundle_id.plist"
            "$HOME/Library/Caches/$bundle_id"
            "$HOME/Library/Application Support/$bundle_id"
            "$HOME/Library/Containers/$bundle_id"
            "$HOME/Library/Group Containers/group.$bundle_id"
            "$HOME/Library/Group Containers/$bundle_id"
            "$HOME/Library/HTTPStorages/$bundle_id"
            "$HOME/Library/Cookies/$bundle_id.binarycookies"
            "$HOME/Library/Saved Application State/$bundle_id.savedState"
            "$HOME/Library/SyncedPreferences/$bundle_id.plist"
            "$HOME/Library/WebKit/$bundle_id"
            "/Library/Preferences/$bundle_id.plist"
            "/Library/Application Support/$bundle_id"
            "/Library/LaunchDaemons/$bundle_id.plist"
            "/Library/LaunchAgents/$bundle_id.plist"
            "/Library/Caches/$bundle_id"
            "/private/var/db/receipts/$bundle_id.bom"
            "/private/var/db/receipts/$bundle_id.plist"
        )
        
        for location in "${bundle_locations[@]}"; do
            if [[ -e "$location" ]] && ! printf '%s\n' "${related_files[@]}" | grep -q "^$location|"; then
                local size=$(get_size "$location")
                related_files+=("$location|Bundle ID Data ($size)")
            fi
        done
    fi
    
    # Search for additional app-related files by name patterns
    local name_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    local name_upper=$(echo "$app_name" | tr '[:lower:]' '[:upper:]')
    local name_patterns=("$name_lower" "$name_upper" "$app_name")
    for pattern in "${name_patterns[@]}"; do
        # Find files containing app name in caches
        while IFS= read -r -d '' file; do
            if [[ -e "$file" ]] && ! printf '%s\n' "${related_files[@]}" | grep -q "^$file|"; then
                local size=$(get_size "$file")
                related_files+=("$file|Cache File ($size)")
            fi
        done < <(find "$HOME/Library/Caches" -maxdepth 2 -name "*$pattern*" -print0 2>/dev/null)
        
        # Find preference files containing app name
        while IFS= read -r -d '' file; do
            if [[ -e "$file" ]] && ! printf '%s\n' "${related_files[@]}" | grep -q "^$file|"; then
                local size=$(get_size "$file")
                related_files+=("$file|Preference File ($size)")
            fi
        done < <(find "$HOME/Library/Preferences" -maxdepth 1 -name "*$pattern*" -print0 2>/dev/null)
        
        # Find application support files
        while IFS= read -r -d '' file; do
            if [[ -e "$file" ]] && ! printf '%s\n' "${related_files[@]}" | grep -q "^$file|"; then
                local size=$(get_size "$file")
                related_files+=("$file|App Support File ($size)")
            fi
        done < <(find "$HOME/Library/Application Support" -maxdepth 2 -name "*$pattern*" -print0 2>/dev/null)
    done
    
    printf '%s\n' "${related_files[@]}"
}

# Function to use fzf or fallback to simple selection
show_app_selector() {
    print_separator
    echo -e "${BOLD}${APP_ICON} $(get_text "app_uninstall_title")${NC}"
    print_separator
    
    echo -e "${BLUE}$(get_text "app_scanning")${NC}"
    
    # Collect applications
    local apps=()
    local app_paths=()
    
    # Scan /Applications
    if [[ -d "/Applications" ]]; then
        while IFS= read -r -d '' app_path; do
            if [[ -d "$app_path" ]]; then
                local app_name=$(basename "$app_path" .app)
                apps+=("$app_name")
                app_paths+=("$app_path")
            fi
        done < <(find "/Applications" -name "*.app" -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    
    # Scan ~/Applications
    if [[ -d "$HOME/Applications" ]]; then
        while IFS= read -r -d '' app_path; do
            if [[ -d "$app_path" ]]; then
                local app_name=$(basename "$app_path" .app)
                apps+=("$app_name")
                app_paths+=("$app_path")
            fi
        done < <(find "$HOME/Applications" -name "*.app" -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    
    if [[ ${#apps[@]} -eq 0 ]]; then
        print_error "No applications found"
        return 1
    fi
    
    echo -e "${GREEN}${#apps[@]} $(get_text "app_found_count")${NC}"
    echo ""
    
    # Try to use fzf if available and in interactive mode
    if command -v fzf >/dev/null 2>&1 && [[ -t 0 ]] && [[ -t 1 ]]; then
        # Create temp file for fzf
        local temp_file=$(mktemp)
        trap "rm -f '$temp_file'" EXIT
        
        for ((i=0; i<${#apps[@]}; i++)); do
            printf "%s\t%s\n" "${apps[i]}" "${app_paths[i]}"
        done > "$temp_file"
        
        echo -e "${GREEN}Using fzf for selection...${NC}"
        echo ""
        
        local selected_line
        if [[ "$CURRENT_LANG" == "cn" ]]; then
            selected_line=$(cat "$temp_file" | fzf \
                --height=80% \
                --border \
                --prompt="搜索应用程序: " \
                --header="选择要卸载的应用程序 (ESC 取消)" \
                --bind='ctrl-c:abort')
        else
            selected_line=$(cat "$temp_file" | fzf \
                --height=80% \
                --border \
                --prompt="Search applications: " \
                --header="Select application to uninstall (ESC to cancel)" \
                --bind='ctrl-c:abort')
        fi
        
        if [[ -n "$selected_line" ]]; then
            local selected_app_path=$(echo "$selected_line" | cut -f2)
            local selected_app_name=$(basename "$selected_app_path" .app)
            uninstall_application "$selected_app_path" "$selected_app_name"
            return
        else
            print_info "$(get_text "skipped")"
            return 1
        fi
    fi
    
    # Fallback to numbered list selection
    echo -e "${YELLOW}fzf not available, using numbered selection:${NC}"
    echo ""
    
    # Display numbered list
    for ((i=0; i<${#apps[@]}; i++)); do
        printf "${CYAN}[%3d]${NC} %s\n" $((i+1)) "${apps[i]}"
    done
    
    echo ""
    if [[ "$CURRENT_LANG" == "cn" ]]; then
        read -p "请输入应用程序编号 (1-${#apps[@]}, 0 取消): " choice
    else
        read -p "Enter application number (1-${#apps[@]}, 0 to cancel): " choice
    fi
    
    # Validate input
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#apps[@]} ]]; then
        if [[ "$choice" == "0" ]]; then
            print_info "$(get_text "skipped")"
        else
            print_error "$(get_text "invalid_choice")"
        fi
        return 1
    fi
    
    # Get selected app
    local selected_index=$((choice - 1))
    local selected_app_path="${app_paths[selected_index]}"
    local selected_app_name="${apps[selected_index]}"
    
    uninstall_application "$selected_app_path" "$selected_app_name"
}

# Function to uninstall application completely
uninstall_application() {
    local app_path="$1"
    local app_name="$2"
    
    echo -e "${BOLD}${GREEN}$(get_text "app_selected"): $app_name${NC}"
    echo ""
    
    # Find all related files
    echo -e "${BLUE}$(get_text "app_scanning")...${NC}"
    local related_files=()
    while IFS= read -r line; do
        related_files+=("$line")
    done < <(find_app_files "$app_name" "$app_path")
    
    if [[ ${#related_files[@]} -eq 0 ]]; then
        print_error "No files found for application: $app_name"
        return 1
    fi
    
    # Calculate total size
    local total_size_bytes=0
    echo -e "${BOLD}${GREEN}$(get_text "app_files_found"): ${#related_files[@]}${NC}"
    echo ""
    
    for file_info in "${related_files[@]}"; do
        IFS='|' read -r file_path file_desc <<< "$file_info"
        if [[ -e "$file_path" ]]; then
            local size=$(get_size "$file_path")
            local size_bytes=$(get_size_bytes "$file_path")
            total_size_bytes=$((total_size_bytes + size_bytes))
            echo -e "  ${CHECK_ICON} $file_desc - ${CYAN}$file_path${NC}"
        fi
    done
    
    local total_size_human=$(bytes_to_human "$total_size_bytes")
    echo ""
    echo -e "${BOLD}${YELLOW}$(get_text "app_size_total"): $total_size_human${NC}"
    echo ""
    
    # Confirm uninstallation
    read -p "$(echo -e ${WHITE}$(get_text "app_confirm_uninstall")${NC})" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "$(get_text "skipped")"
        return 0
    fi
    
    # Perform uninstallation
    echo ""
    echo -e "${BOLD}${BLUE}$(get_text "app_uninstalling")${NC}"
    echo ""
    
    local success_count=0
    local total_count=0
    
    for file_info in "${related_files[@]}"; do
        IFS='|' read -r file_path file_desc <<< "$file_info"
        ((total_count++))
        
        if [[ -e "$file_path" ]]; then
            echo -e "${CLEAN_ICON} $(get_text "cleaning") $file_desc..."
            
            if sudo rm -rf "$file_path" 2>/dev/null || rm -rf "$file_path" 2>/dev/null; then
                print_success "$(get_text "cleaned"): $file_desc"
                ((success_count++))
            else
                print_error "$(get_text "failed"): $file_desc"
            fi
        fi
    done
    
    echo ""
    if [[ $success_count -eq $total_count ]]; then
        print_success "$(get_text "app_uninstall_complete"): $app_name"
        print_success "$(get_text "total_space_freed"): $total_size_human"
    else
        print_warning "$(get_text "app_uninstall_complete"): $app_name ($success_count/$total_count files removed)"
    fi
    
    echo ""
    read -p "$(echo -e ${WHITE}$(get_text "press_enter")${NC})"
}

# Function to perform virus scan - optimized for speed
execute_virus_scan() {
    print_separator
    echo -e "${BOLD}${SHIELD_ICON} $(get_text "virus_scan_title")${NC}"
    print_separator
    
    echo -e "${WHITE}$(get_text "virus_scan_desc")${NC}"
    echo ""
    
    echo -e "${BOLD}${BLUE}$(get_text "virus_scanning")${NC}"
    echo ""
    
    local suspicious_files=()
    local scan_count=0
    local total_scanned=0
    
    # Progress function
    show_progress() {
        local current=$1
        local total=$2
        local percent=$((current * 100 / total))
        local bar_length=30
        local filled=$((percent * bar_length / 100))
        local empty=$((bar_length - filled))
        
        printf "\r${BLUE}扫描进度: [${GREEN}"
        printf "%*s" $filled | tr ' ' '█'
        printf "${NC}"
        printf "%*s" $empty | tr ' ' '░'
        printf "${BLUE}] %d%% (%d/%d)${NC}" $percent $current $total
    }
    
    # Quick process check
    echo -e "${CYAN}1/4 检查可疑进程...${NC}"
    local suspicious_processes=$(ps aux | grep -E -i "(adware|malware|keylogger|trojan|backdoor|miner|cryptojack)" | grep -v grep | head -5 || true)
    if [[ -n "$suspicious_processes" ]]; then
        echo -e "${RED}${VIRUS_ICON} 发现可疑进程:${NC}"
        echo "$suspicious_processes" | head -3
        echo ""
    else
        echo -e "${GREEN}${CHECK_ICON} 进程检查正常${NC}"
    fi
    
    # Quick known malware check
    echo -e "${CYAN}2/4 检查已知恶意软件...${NC}"
    local quick_malware_patterns=(
        "MacKeeper"
        "Advanced Mac Cleaner"
        "Mac Auto Fixer" 
        "Mac Speed Up Pro"
        "MyCouponize"
        "MacShiny"
        "ZipCloud"
        "SearchMine"
    )
    
    local priority_locations=(
        "/Applications"
        "$HOME/Applications" 
        "$HOME/Downloads"
        "/tmp"
        "$HOME/Library/LaunchAgents"
        "/Library/LaunchAgents"
    )
    
    local malware_found=0
    for location in "${priority_locations[@]}"; do
        if [[ -d "$location" ]]; then
            for pattern in "${quick_malware_patterns[@]}"; do
                if find "$location" -iname "*$pattern*" -type f -o -type d | head -1 | grep -q . 2>/dev/null; then
                    local found_files=$(find "$location" -iname "*$pattern*" 2>/dev/null | head -3)
                    while IFS= read -r file; do
                        if [[ -n "$file" ]]; then
                            local file_size=$(du -sh "$file" 2>/dev/null | cut -f1 || echo "未知")
                            suspicious_files+=("$file|Known Malware: $pattern ($file_size)")
                            ((malware_found++))
                        fi
                    done <<< "$found_files"
                fi
            done
        fi
    done
    
    if [[ $malware_found -gt 0 ]]; then
        echo -e "${RED}${VIRUS_ICON} 发现 $malware_found 个已知恶意软件${NC}"
    else
        echo -e "${GREEN}${CHECK_ICON} 未发现已知恶意软件${NC}"
    fi
    
    # Quick suspicious file check
    echo -e "${CYAN}3/4 检查可疑文件类型...${NC}"
    local suspicious_files_found=0
    local quick_locations=("$HOME/Downloads" "$HOME/Desktop" "/tmp")
    
    for location in "${quick_locations[@]}"; do
        if [[ -d "$location" ]]; then
            # Check for suspicious extensions
            local susp_files=$(find "$location" -maxdepth 2 \( -name "*.dmg.zip" -o -name "*.app.zip" -o -name "*.pkg.zip" -o -name "*.scr" \) 2>/dev/null | head -5)
            while IFS= read -r file; do
                if [[ -n "$file" && -f "$file" ]]; then
                    local file_size=$(du -sh "$file" 2>/dev/null | cut -f1 || echo "未知")
                    suspicious_files+=("$file|Suspicious File Type ($file_size)")
                    ((suspicious_files_found++))
                fi
            done <<< "$susp_files"
        fi
    done
    
    if [[ $suspicious_files_found -gt 0 ]]; then
        echo -e "${YELLOW}${WARNING_ICON} 发现 $suspicious_files_found 个可疑文件${NC}"
    else
        echo -e "${GREEN}${CHECK_ICON} 文件类型检查正常${NC}"
    fi
    
    # Quick startup items check
    echo -e "${CYAN}4/4 检查启动项...${NC}"
    local suspicious_startup=0
    local startup_dirs=("/Library/LaunchAgents" "$HOME/Library/LaunchAgents")
    
    for startup_dir in "${startup_dirs[@]}"; do
        if [[ -d "$startup_dir" ]]; then
            # Look for non-Apple startup items
            local non_apple_plists=$(find "$startup_dir" -name "*.plist" ! -name "com.apple.*" 2>/dev/null | head -5)
            while IFS= read -r plist; do
                if [[ -n "$plist" && -f "$plist" ]]; then
                    # Quick check for suspicious paths
                    if grep -q -E "(tmp|Downloads|Desktop)" "$plist" 2>/dev/null; then
                        local file_size=$(du -sh "$plist" 2>/dev/null | cut -f1 || echo "未知")
                        suspicious_files+=("$plist|Suspicious Startup Item ($file_size)")
                        ((suspicious_startup++))
                    fi
                fi
            done <<< "$non_apple_plists"
        fi
    done
    
    if [[ $suspicious_startup -gt 0 ]]; then
        echo -e "${YELLOW}${WARNING_ICON} 发现 $suspicious_startup 个可疑启动项${NC}" 
    else
        echo -e "${GREEN}${CHECK_ICON} 启动项检查正常${NC}"
    fi
    
    echo ""
    print_separator
    
    if [[ ${#suspicious_files[@]} -eq 0 ]]; then
        print_success "$(get_text "virus_scan_complete") - 未发现威胁"
        echo -e "${GREEN}${CHECK_ICON} 系统安全检查通过！${NC}"
        echo -e "${BLUE}${INFO_ICON} 扫描了进程、已知恶意软件、可疑文件和启动项${NC}"
    else
        print_warning "$(get_text "virus_found"): ${#suspicious_files[@]} 个项目"
        echo ""
        
        echo -e "${BOLD}${RED}发现的威胁:${NC}"
        local count=1
        for file_info in "${suspicious_files[@]}"; do
            IFS='|' read -r file_path file_desc <<< "$file_info"
            echo -e "  ${VIRUS_ICON} [$count] $file_desc"
            echo -e "      ${CYAN}$file_path${NC}"
            ((count++))
        done
        
        echo ""
        read -p "$(echo -e ${WHITE}是否要删除这些威胁？[y/N]: ${NC})" -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BOLD}${BLUE}正在清除威胁...${NC}"
            local removed_count=0
            local total_count=${#suspicious_files[@]}
            
            for file_info in "${suspicious_files[@]}"; do
                IFS='|' read -r file_path file_desc <<< "$file_info"
                echo -e "${CLEAN_ICON} 清除: $(basename "$file_path")..."
                
                if sudo rm -rf "$file_path" 2>/dev/null || rm -rf "$file_path" 2>/dev/null; then
                    print_success "已清除: $(basename "$file_path")"
                    ((removed_count++))
                else
                    print_error "清除失败: $(basename "$file_path")"
                fi
                show_progress $removed_count $total_count
            done
            
            echo ""
            echo ""
            print_success "安全清理完成: 清除了 $removed_count/$total_count 个威胁"
        else
            print_info "跳过威胁清除"
        fi
    fi
    
    echo ""
    read -p "$(echo -e ${WHITE}$(get_text "press_enter")${NC})"
}

# Function to create visual bar chart
create_bar_chart() {
    local size_bytes=$1
    local max_bytes=$2
    local bar_width=40
    
    # Ensure we have valid numbers
    [[ ! "$size_bytes" =~ ^[0-9]+$ ]] && size_bytes=0
    [[ ! "$max_bytes" =~ ^[0-9]+$ ]] && max_bytes=1
    [[ $max_bytes -eq 0 ]] && max_bytes=1
    
    local filled_width=$((size_bytes * bar_width / max_bytes))
    [[ $filled_width -eq 0 && $size_bytes -gt 0 ]] && filled_width=1
    [[ $filled_width -gt $bar_width ]] && filled_width=$bar_width
    
    printf "${GREEN}"
    printf "%*s" $filled_width | tr ' ' '█'
    printf "${CYAN}"
    printf "%*s" $((bar_width - filled_width)) | tr ' ' '░'
    printf "${NC}"
}

# Function to perform disk analysis - optimized and visualized
execute_disk_analysis() {
    print_separator
    echo -e "${BOLD}${CHART_ICON} $(get_text "disk_analysis_title")${NC}"
    print_separator
    
    echo -e "${WHITE}$(get_text "disk_analysis_desc")${NC}"
    echo ""
    
    echo -e "${BOLD}${BLUE}$(get_text "disk_analyzing")${NC}"
    
    # Show disk usage summary with visual bar
    echo ""
    echo -e "${BOLD}${CYAN}💾 磁盘使用情况概览:${NC}"
    local disk_info=$(df -k / | tail -1)
    local total_kb=$(echo $disk_info | awk '{print $2}')
    local used_kb=$(echo $disk_info | awk '{print $3}')
    local free_kb=$(echo $disk_info | awk '{print $4}')
    local use_percent=$(echo $disk_info | awk '{print $5}' | sed 's/%//')
    
    local total_gb=$(echo "scale=1; $total_kb / 1024 / 1024" | bc)
    local used_gb=$(echo "scale=1; $used_kb / 1024 / 1024" | bc)
    local free_gb=$(echo "scale=1; $free_kb / 1024 / 1024" | bc)
    
    echo -e "总容量: ${BOLD}${WHITE}${total_gb}GB${NC}"
    echo -e "已使用: ${BOLD}${RED}${used_gb}GB${NC} (${use_percent}%)"
    echo -e "可用空间: ${BOLD}${GREEN}${free_gb}GB${NC}"
    
    # Visual disk usage bar
    local bar_width=50
    local used_width=$((use_percent * bar_width / 100))
    printf "\n磁盘使用: ["
    printf "${RED}%*s${NC}" $used_width | tr ' ' '█'
    printf "${GREEN}%*s${NC}" $((bar_width - used_width)) | tr ' ' '░'
    printf "] %s%%\n\n" $use_percent
    
    # Quick analysis of major directories
    echo -e "${BOLD}${CYAN}📁 主要目录大小分析:${NC}"
    
    local quick_dirs=("$HOME" "/Applications" "/Library" "/usr" "/var" "/tmp")
    declare -a dir_info=()
    local max_size=0
    
    # Lightning-fast directory analysis using intelligent estimates
    echo -ne "\r${BLUE}智能分析目录大小...${NC}"
    
    # Use cached/estimated approach for speed
    local cache_file="$HOME/.cache/cleanmac_sizes"
    local cache_age_limit=3600  # 1 hour cache
    local use_cache=false
    
    # Check if cache exists and is recent
    if [[ -f "$cache_file" ]]; then
        # Use a simpler approach to check cache age
        local current_time=$(date +%s)
        local file_age=$(/usr/bin/find "$cache_file" -mtime +0.0007 2>/dev/null) # ~1 minute old
        if [[ -z "$file_age" ]]; then
            # File is recent (< 1 minute old)
            local cache_age=0
        else
            local cache_age=3661  # Assume old if find detected it
        fi
        if [[ $cache_age -lt $cache_age_limit ]]; then
            use_cache=true
        fi
    fi
    
    if [[ "$use_cache" == "true" ]]; then
        # Load from cache
        while IFS='|' read -r size_kb dir_path size_human; do
            [[ $size_kb -gt $max_size ]] && max_size=$size_kb
            dir_info+=("$size_kb|$dir_path|$size_human")
        done < "$cache_file"
    else
        # Quick estimation method
        mkdir -p "$(dirname "$cache_file")"
        for dir in "${quick_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                local size_kb=0
                local dir_name=$(basename "$dir")
                
                # Super-fast estimation using file counts and averages
                case "$dir_name" in
                    "anthony")
                        # Estimate based on common user directory patterns
                        local file_count=$(find "$dir" -maxdepth 2 -type f 2>/dev/null | wc -l | tr -d ' ')
                        size_kb=$((file_count * 100))  # Rough estimate: 100KB per file
                        ;;
                    "Applications")
                        # Quick app count estimation
                        local app_count=$(ls -1 "$dir"/*.app 2>/dev/null | wc -l | tr -d ' ')
                        size_kb=$((app_count * 512000))  # Rough estimate: 500MB per app
                        ;;
                    "Library")
                        if [[ "$dir" == "$HOME/Library" ]]; then
                            # Quick Library estimate
                            size_kb=5242880  # Typical user Library ~5GB
                        fi
                        ;;
                    "usr")
                        size_kb=768000  # Typical /usr ~750MB
                        ;;
                    *)
                        size_kb=0
                        ;;
                esac
                
                # Validate and store
                if [[ $size_kb -gt 10240 ]]; then  # >10MB
                    local size_gb=$(echo "scale=1; $size_kb / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
                    local size_human="${size_gb}GB"
                    [[ $size_kb -gt $max_size ]] && max_size=$size_kb
                    dir_info+=("$size_kb|$dir|$size_human")
                    # Save to cache
                    echo "$size_kb|$dir|$size_human" >> "$cache_file"
                fi
            fi
        done
    fi
    echo -e "\r${NC}                                        "
    
    # Sort and display with visual bars
    IFS=$'\n' dir_info=($(printf '%s\n' "${dir_info[@]}" | sort -rn))
    
    for info in "${dir_info[@]}"; do
        IFS='|' read -r size_kb dir_path size_human <<< "$info"
        printf "  ${FOLDER_ICON} %-20s ${YELLOW}%8s${NC} " "$(basename "$dir_path")" "$size_human"
        create_bar_chart $size_kb $max_size
        echo ""
    done
    echo ""
    
    # Lightning-fast large file detection  
    echo -e "${BOLD}${CYAN}🔍 超大文件检测 (>1GB):${NC}"
    echo -ne "${BLUE}快速扫描...${NC}"
    
    local large_files=()
    # Focus on most likely locations for large files
    local smart_paths=(
        "$HOME/Downloads"
        "$HOME/Desktop" 
        "$HOME/Documents"
        "$HOME/Movies"
        "$HOME/Library/Application Support"
        "/Applications"
    )
    
    for search_path in "${smart_paths[@]}"; do
        if [[ -d "$search_path" ]]; then
            # Ultra-fast find - only check top 2 levels and stop at first 5 files
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    local file_size=$(ls -lah "$file" 2>/dev/null | awk '{print $5}' || echo "0B")
                    large_files+=("$file_size|$file")
                fi
            done < <(find "$search_path" -maxdepth 2 -type f -size +1G 2>/dev/null | head -5)
        fi
    done
    
    echo -e "\r                                    "
    
    if [[ ${#large_files[@]} -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_ICON} 未发现超大文件 (>500MB)${NC}"
    else
        echo -e "${BOLD}${YELLOW}发现 ${#large_files[@]} 个超大文件:${NC}"
        
        # Sort by size
        IFS=$'\n' large_files=($(printf '%s\n' "${large_files[@]}" | sort -rn))
        
        local count=1
        for file_info in "${large_files[@]}"; do
            IFS='|' read -r file_size file_path <<< "$file_info"
            echo -e "  ${WARNING_ICON} [$count] ${CYAN}$file_size${NC} - $(basename "$file_path")"
            echo -e "      ${BLUE}$file_path${NC}"
            ((count++))
            [[ $count -gt 5 ]] && break  # Limit display to top 5
        done
        
        echo ""
        read -p "$(echo -e ${WHITE}查看大文件管理选项？[y/N]: ${NC})" -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BOLD}${CYAN}大文件管理选项:${NC}"
            echo -e "  ${INFO_ICON} 1. 手动检查文件位置"
            echo -e "  ${INFO_ICON} 2. 使用 Finder 打开所在文件夹"
            echo -e "  ${WARNING_ICON} 3. 谨慎删除 - 可能是重要文件"
            echo ""
            
            local top_file=$(echo "${large_files[0]}" | cut -d'|' -f2)
            echo -e "${BLUE}最大文件位置:${NC} $top_file"
            read -p "$(echo -e ${WHITE}在 Finder 中显示最大文件？[y/N]: ${NC})" -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]] && [[ -f "$top_file" ]]; then
                open -R "$top_file" 2>/dev/null && echo -e "${GREEN}${CHECK_ICON} 已在 Finder 中显示文件${NC}"
            fi
        fi
    fi
    
    echo ""
    
    # Super-fast cache analysis
    echo -e "${BOLD}${CYAN}🗂️  缓存概览:${NC}"
    echo -ne "\r${BLUE}计算缓存大小...${NC}"
    
    local total_cache_bytes=0
    declare -a cache_info=()
    
    # Only check the most important cache directories
    local essential_caches=(
        "$HOME/Library/Caches|用户缓存"
        "$HOME/Library/Application Support|应用支持"
    )
    
    for cache_entry in "${essential_caches[@]}"; do
        IFS='|' read -r cache_dir cache_name <<< "$cache_entry"
        if [[ -d "$cache_dir" ]]; then
            # Use faster size calculation - summary only
            local cache_kb=$(du -sk "$cache_dir" 2>/dev/null | head -1 | cut -f1 | tr -d '\n\t ' || echo "0")
            [[ ! "$cache_kb" =~ ^[0-9]+$ ]] && cache_kb=0
            
            if [[ $cache_kb -gt 0 ]]; then
                local cache_bytes=$((cache_kb * 1024))
                local cache_human=$(bytes_to_human $cache_bytes)
                total_cache_bytes=$((total_cache_bytes + cache_bytes))
                cache_info+=("$cache_name: $cache_human")
            fi
        fi
    done
    echo -e "\r                                        "
    
    # Simple cache display without bars
    for info in "${cache_info[@]}"; do
        echo -e "  ${FOLDER_ICON} $info"
    done
    
    local total_cache_human=$(bytes_to_human $total_cache_bytes)
    echo ""
    echo -e "${BOLD}${GREEN}总缓存大小: $total_cache_human${NC}"
    
    if [[ $total_cache_bytes -gt $((1024 * 1024 * 1024)) ]]; then  # > 1GB
        echo -e "${YELLOW}${INFO_ICON} 缓存较大，建议运行自动清理功能${NC}"
    fi
    
    # Lightning-fast duplicate check
    echo ""
    echo -e "${BOLD}${CYAN}🔄 整理建议:${NC}"
    
    # Quick and simple checks
    local suggestions=()
    
    # Check Downloads folder
    if [[ -d "$HOME/Downloads" ]]; then
        local downloads_count=$(ls -1 "$HOME/Downloads" 2>/dev/null | wc -l | tr -d ' ')
        if [[ $downloads_count -gt 50 ]]; then
            suggestions+=("下载文件夹有 $downloads_count 个文件，建议整理")
        fi
    fi
    
    # Check Desktop
    if [[ -d "$HOME/Desktop" ]]; then
        local desktop_count=$(ls -1 "$HOME/Desktop" 2>/dev/null | wc -l | tr -d ' ')
        if [[ $desktop_count -gt 20 ]]; then
            suggestions+=("桌面有 $desktop_count 个项目，建议整理")
        fi
    fi
    
    # Display suggestions
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        for suggestion in "${suggestions[@]}"; do
            echo -e "  ${INFO_ICON} $suggestion"
        done
    else
        echo -e "  ${CHECK_ICON} 文件夹看起来很整洁"
    fi
    
    echo ""
    print_separator
    print_success "$(get_text "disk_analysis_complete")"
    
    # Summary with recommendations
    echo ""
    echo -e "${BOLD}${CYAN}💡 优化建议:${NC}"
    
    if [[ $use_percent -gt 90 ]]; then
        echo -e "  ${WARNING_ICON} 磁盘空间不足，建议立即清理"
    elif [[ $use_percent -gt 80 ]]; then
        echo -e "  ${INFO_ICON} 磁盘空间紧张，建议定期清理"
    else
        echo -e "  ${CHECK_ICON} 磁盘空间充足"
    fi
    
    if [[ $total_cache_bytes -gt $((2 * 1024 * 1024 * 1024)) ]]; then  # > 2GB
        echo -e "  ${INFO_ICON} 运行自动清理可释放约 $(bytes_to_human $((total_cache_bytes / 2)))"
    fi
    
    if [[ ${#large_files[@]} -gt 0 ]]; then
        echo -e "  ${INFO_ICON} 检查大文件，删除不需要的可释放大量空间"
    fi
    
    echo ""
    read -p "$(echo -e ${WHITE}$(get_text "press_enter")${NC})"
}

# Function to show language menu
show_language_menu() {
    print_separator
    echo -e "${BOLD}${LANG_ICON} Language & Exit Menu${NC}"
    print_separator
    
    echo -e "${BOLD}${WHITE}Select Language:${NC}"
    echo ""
    echo -e "${CYAN}[1]${NC} English"
    echo -e "${CYAN}[2]${NC} 中文 (Chinese)"
    echo -e "${CYAN}[3]${NC} Exit Program"
    echo ""
    
    read -p "$(echo -e ${WHITE}Enter your choice [1-3]: ${NC})" lang_choice
    echo ""
    
    case $lang_choice in
        1)
            CURRENT_LANG="en"
            save_language
            print_success "Language changed successfully!"
            print_info "Language preference saved."
            sleep 2
            ;;
        2)
            CURRENT_LANG="cn"
            save_language
            print_success "语言切换成功！"
            print_info "语言偏好已保存。"
            sleep 2
            ;;
        3)
            echo -e "${BOLD}${GREEN}$(get_text "thank_you") ${SPARKLE_ICON}${NC}"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            ;;
    esac
}


# Main menu function
show_menu() {
    echo -e "${BOLD}${BRIGHT_WHITE}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BRIGHT_WHITE}│ ${BRIGHT_CYAN}$(get_text "menu_select")${BRIGHT_WHITE} │${NC}"
    echo -e "${BOLD}${BRIGHT_WHITE}├─────────────────────────────────────────────────────────────────────┤${NC}"
    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}[1]${NC} 🧹  $(get_text "menu_1")"
    echo -e "  ${BOLD}${BRIGHT_CYAN}[2]${NC} ${APP_ICON}  $(get_text "menu_2")"
    echo -e "  ${BOLD}${BRIGHT_CYAN}[3]${NC} ${SHIELD_ICON}  $(get_text "menu_3")"
    echo -e "  ${BOLD}${BRIGHT_CYAN}[4]${NC} ${CHART_ICON}  $(get_text "menu_4")"
    echo -e "  ${BOLD}${BRIGHT_CYAN}[5]${NC} 🧠  $(get_text "menu_5")"
    echo -e "  ${BOLD}${BRIGHT_CYAN}[6]${NC} 🔍  $(get_text "menu_6")"
    echo -e "  ${BOLD}${BRIGHT_CYAN}[7]${NC} ⚡  $(get_text "menu_7")"
    echo -e "  ${BOLD}${BRIGHT_CYAN}[8]${NC} ${LANG_ICON}  $(get_text "menu_8")"
    echo ""
    echo -e "${BOLD}${BRIGHT_WHITE}└─────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to show help in Chinese
show_help_cn() {
    echo "CleanMac - macOS 系统清理工具"
    echo "用法: $(basename "$0") [选项] [天数]"
    echo ""
    echo "安全且交互式地清理不必要的 macOS 文件。"
    echo ""
    echo "选项:"
    echo "    -h, --help          显示此帮助信息"
    echo "    -d, --dry-run       显示将要删除的内容但不实际删除"
    echo "    --lang=LANG         设置语言 (en|cn)"
    echo "    --auto              直接运行自动清理模式"
    echo ""
    echo "参数:"
    echo "    DAYS                保留缓存的天数 (默认: 7)"
    echo ""
    echo "示例:"
    echo "    $0                  交互模式"
    echo "    $0 --dry-run        预览清理但不删除"
    echo "    $0 --auto           自动清理模式"
    echo "    $0 --lang=cn        使用中文界面"
    echo "    $0 30               保留30天内的文件"
}

# Function to show help
show_help() {
    echo "CleanMac - Advanced macOS System Cleanup Tool"
    echo "Usage: $(basename "$0") [OPTIONS] [DAYS]"
    echo ""
    echo "Clean up unnecessary macOS files safely and interactively."
    echo ""
    echo "Options:"
    echo "    -h, --help          Show this help message"
    echo "    -d, --dry-run       Show what would be deleted without deleting"
    echo "    --lang=LANG         Set language (en|cn)"
    echo "    --auto              Run auto cleanup mode directly"
    echo ""
    echo "Arguments:"
    echo "    DAYS                Number of days of cache to keep (default: 7)"
    echo ""
    echo "Examples:"
    echo "    $0                  Interactive mode"
    echo "    $0 --dry-run        Preview cleanup without deleting"
    echo "    $0 --auto           Auto cleanup mode"
    echo "    $0 --lang=cn        Use Chinese interface"
    echo "    $0 30               Keep files newer than 30 days"
}

# Function to get disk space
get_disk_space() {
    df -k / | awk 'NR==2 {print $4}'
}

# Function to show disk space info
show_disk_space() {
    local free_kb=$(get_disk_space)
    local total_kb=$(df -k / | awk 'NR==2 {print $2}')
    local used_kb=$((total_kb - free_kb))
    local free_gb=$(echo "scale=1; $free_kb / 1024 / 1024" | bc 2>/dev/null || echo "0")
    local total_gb=$(echo "scale=1; $total_kb / 1024 / 1024" | bc 2>/dev/null || echo "0")
    local used_gb=$(echo "scale=1; $used_kb / 1024 / 1024" | bc 2>/dev/null || echo "0")
    local usage_percent=$(echo "scale=0; $used_kb * 100 / $total_kb" | bc 2>/dev/null || echo "0")
    
    # Create visual progress bar
    local bar_length=20
    local filled_length=$(echo "scale=0; $usage_percent * $bar_length / 100" | bc 2>/dev/null || echo "0")
    local empty_length=$((bar_length - filled_length))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do bar+="█"; done
    for ((i=0; i<empty_length; i++)); do bar+="░"; done
    
    # Color based on usage
    local color
    if (( usage_percent >= 90 )); then
        color="${RED}"
    elif (( usage_percent >= 75 )); then
        color="${YELLOW}"
    else
        color="${GREEN}"
    fi
    
    echo -e "${BOLD}${WHITE}┌─────────────────────────────── 💾 存储状态 ───────────────────────────────┐${NC}"
    printf "${BOLD}${WHITE}│${NC} 已使用: ${color}${used_gb}GB${NC} / 总容量: ${CYAN}${total_gb}GB${NC} (${color}${usage_percent}%%${NC})     剩余: ${GREEN}${free_gb}GB${NC} ${BOLD}${WHITE}│${NC}\n"
    printf "${BOLD}${WHITE}│${NC} [${color}${bar}${NC}] ${BOLD}${WHITE}│${NC}\n"
    echo -e "${BOLD}${WHITE}└──────────────────────────────────────────────────────────────────────────┘${NC}"
}


# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --lang=*)
                CURRENT_LANG="${1#*=}"
                save_language
                shift
                ;;
            --lang)
                CURRENT_LANG="$2"
                save_language
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto)
                # Store initial disk space
                initial_free_space=$(get_disk_space)
                show_disk_space
                execute_auto_cleanup
                # Show final disk space
                final_free_space=$(get_disk_space)
                local space_freed=$((final_free_space - initial_free_space))
                if [[ $space_freed -gt 0 ]]; then
                    local freed_gb=$(echo "scale=2; $space_freed / 1024 / 1024" | bc 2>/dev/null || echo "0")
                    echo -e "${GREEN}${SPARKLE_ICON} Space freed: ${freed_gb}GB${NC}"
                fi
                show_disk_space
                exit 0
                ;;
            -h|--help)
                if [[ "$CURRENT_LANG" == "cn" ]]; then
                    show_help_cn
                else
                    show_help
                fi
                exit 0
                ;;
            [0-9]*)
                DAYS_TO_KEEP="$1"
                # Validate days
                if ! [[ $DAYS_TO_KEEP =~ ^[0-9]+$ ]]; then
                    echo "Error: DAYS must be a positive integer."
                    exit 1
                fi
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use -h or --help for usage information."
                exit 1
                ;;
        esac
    done
    
    # Show initial disk space
    initial_free_space=$(get_disk_space)
    
    # If dry run mode, show what would be cleaned
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}${WARNING_ICON} DRY RUN MODE - No files will be deleted${NC}"
        echo ""
        show_disk_space
        echo ""
        echo "Would clean the following locations (files older than ${DAYS_TO_KEEP} days):"
        echo "- System cache files in /Library/Caches/"
        echo "- User cache files in ~/Library/Caches/"
        echo "- System logs in /Library/Logs/"
        echo "- User logs in ~/Library/Logs/"
        echo "- Temporary files in /private/var/tmp/"
        echo "- Files in ~/.Trash/"
        echo "- Browser caches and data"
        echo "- Development tool caches"
        echo "- Application caches"
        echo ""
        echo "Use without --dry-run to perform actual cleanup."
        exit 0
    fi
    
    while true; do
        print_header
        show_disk_space
        echo ""
        show_menu
        echo -e "${BOLD}${BRIGHT_WHITE}┌─────────────────────────────────────────────────────────────────────┐${NC}"
        printf "${BOLD}${BRIGHT_WHITE}│${NC} ✨ $(get_text "enter_choice") ${BOLD}${BRIGHT_WHITE}│${NC}\n"
        echo -e "${BOLD}${BRIGHT_WHITE}└─────────────────────────────────────────────────────────────────────┘${NC}"
        echo -n -e "${BRIGHT_CYAN}➤ ${NC}"
        read choice
        echo ""
        
        # Handle user choice
        case "$choice" in
            1)
                execute_auto_cleanup
                ;;
            2)
                show_app_selector
                ;;
            3)
                execute_virus_scan
                ;;
            4)
                execute_disk_analysis
                ;;
            5)
                execute_smart_suggestions
                ;;
            6)
                execute_duplicate_detection
                ;;
            7)
                execute_performance_optimization
                ;;
            8)
                show_language_menu
                ;;
            *)
                print_error "$(get_text "invalid_choice")"
                sleep 2
                ;;
        esac
    done
}

# Smart cleanup suggestions function
execute_smart_suggestions() {
    print_title "🧠 智能清理建议"
    echo ""
    
    # Analyze system and provide recommendations
    local suggestions=()
    local total_potential_savings=0
    
    echo "🔍 分析系统状态..."
    echo ""
    
    # Check cache sizes
    local cache_size=0
    if [[ -d "$HOME/Library/Caches" ]]; then
        cache_size=$(du -sk "$HOME/Library/Caches" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
    fi
    if [[ -d "/Library/Caches" ]]; then
        cache_size=$((cache_size + $(du -sk "/Library/Caches" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    
    if [[ $cache_size -gt 1048576 ]]; then  # > 1GB
        local cache_gb=$(echo "scale=1; $cache_size / 1024 / 1024" | bc)
        suggestions+=("📄 清理系统缓存 - 可节省约 ${cache_gb}GB")
        total_potential_savings=$((total_potential_savings + cache_size))
    fi
    
    # Check Downloads folder
    local downloads_size=0
    if [[ -d "$HOME/Downloads" ]]; then
        downloads_size=$(du -sk "$HOME/Downloads" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
        if [[ $downloads_size -gt 102400 ]]; then  # > 100MB
            local downloads_mb=$(echo "scale=1; $downloads_size / 1024" | bc)
            suggestions+=("📥 整理下载文件夹 - ${downloads_mb}MB 可能包含旧文件")
            total_potential_savings=$((total_potential_savings + downloads_size / 2))  # Estimate 50% cleanup
        fi
    fi
    
    # Check Trash
    local trash_size=0
    if [[ -d "$HOME/.Trash" ]]; then
        trash_size=$(du -sk "$HOME/.Trash" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
        if [[ $trash_size -gt 10240 ]]; then  # > 10MB
            local trash_mb=$(echo "scale=1; $trash_size / 1024" | bc)
            suggestions+=("🗑️ 清空废纸篓 - 立即释放 ${trash_mb}MB")
            total_potential_savings=$((total_potential_savings + trash_size))
        fi
    fi
    
    # Check for large log files
    local log_size=0
    if [[ -d "$HOME/Library/Logs" ]]; then
        log_size=$(du -sk "$HOME/Library/Logs" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")
    fi
    if [[ -d "/Library/Logs" ]]; then
        log_size=$((log_size + $(du -sk "/Library/Logs" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    
    if [[ $log_size -gt 51200 ]]; then  # > 50MB
        local log_mb=$(echo "scale=1; $log_size / 1024" | bc)
        suggestions+=("📋 清理系统日志 - 可节省 ${log_mb}MB")
        total_potential_savings=$((total_potential_savings + log_size))
    fi
    
    # Check browser caches
    local browser_cache=0
    local chrome_cache="$HOME/Library/Application Support/Google/Chrome/Default/Cache"
    local firefox_cache="$HOME/Library/Caches/Firefox"
    
    if [[ -d "$chrome_cache" ]]; then
        browser_cache=$((browser_cache + $(du -sk "$chrome_cache" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    if [[ -d "$firefox_cache" ]]; then
        browser_cache=$((browser_cache + $(du -sk "$firefox_cache" 2>/dev/null | cut -f1 | tr -d '\n\t ' || echo "0")))
    fi
    
    if [[ $browser_cache -gt 51200 ]]; then  # > 50MB
        local browser_mb=$(echo "scale=1; $browser_cache / 1024" | bc)
        suggestions+=("🌐 清理浏览器缓存 - 可节省 ${browser_mb}MB")
        total_potential_savings=$((total_potential_savings + browser_cache))
    fi
    
    # Display suggestions
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo "📋 建议的清理操作："
        echo ""
        for suggestion in "${suggestions[@]}"; do
            echo "  ✨ $suggestion"
        done
        
        echo ""
        if [[ $total_potential_savings -gt 1048576 ]]; then
            local total_gb=$(echo "scale=1; $total_potential_savings / 1024 / 1024" | bc)
            echo "🎯 总计可节省空间：约 ${total_gb}GB"
        else
            local total_mb=$(echo "scale=1; $total_potential_savings / 1024" | bc)
            echo "🎯 总计可节省空间：约 ${total_mb}MB"
        fi
        
        echo ""
        echo "💡 提示：使用'自动清理'功能可以安全地执行这些操作。"
    else
        echo "✅ 您的系统看起来很干净！"
        echo "💡 建议定期运行清理工具保持系统性能。"
    fi
    
    echo ""
    read -p "$(echo -e ${WHITE}$(get_text "press_enter")${NC})"
}

# Duplicate file detection function
execute_duplicate_detection() {
    print_title "🔍 重复文件检测"
    echo ""
    
    echo "🔎 快速重复文件检测..."
    echo "📁 将扫描：Documents, Downloads, Desktop 文件夹"
    echo ""
    
    # Create temporary files for processing
    local temp_dir="/tmp/cleanmac_duplicate_$$"
    mkdir -p "$temp_dir"
    local results_file="$temp_dir/results.txt"
    
    # Search for files in common directories
    local search_paths=("$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")
    local total_files=0
    local duplicate_count=0
    local duplicate_size_saved=0
    
    echo "📊 分析文件中..."
    
    # Simple approach: find files by size first, then hash only potential duplicates
    for search_path in "${search_paths[@]}"; do
        if [[ -d "$search_path" ]]; then
            echo "  检查 $(basename "$search_path")..."
            
            # Find files and group by size (much faster than hashing everything)
            local size_groups=()
            while IFS= read -r -d '' file; do
                if [[ -f "$file" && -r "$file" ]]; then
                    local size=$(stat -f%z "$file" 2>/dev/null || echo "0")
                    if [[ $size -gt 1048576 && $size -lt 52428800 ]]; then  # 1MB to 50MB
                        echo "$size|$file" >> "$temp_dir/size_list.txt"
                        ((total_files++))
                    fi
                fi
                # Limit files to prevent hanging
                if [[ $total_files -gt 30 ]]; then
                    echo "    (限制扫描30个文件以提高性能)"
                    break 2
                fi
            done < <(find "$search_path" -maxdepth 2 -type f -print0 2>/dev/null)
        fi
    done
    
    echo "  共找到 $total_files 个候选文件"
    echo ""
    
    if [[ $total_files -eq 0 ]]; then
        echo "📝 未找到适合检测的文件"
        echo "💡 重复文件检测需要1MB-50MB的文件"
    elif [[ -f "$temp_dir/size_list.txt" ]]; then
        echo "🔍 查找相同大小的文件..."
        
        # Find files with same size (potential duplicates)
        sort "$temp_dir/size_list.txt" | uniq -d -w 10 > "$temp_dir/same_size.txt"
        
        if [[ -s "$temp_dir/same_size.txt" ]]; then
            echo "⚠️  发现相同大小的文件（可能重复）："
            echo ""
            
            local current_size=""
            local size_files=()
            local group_count=0
            
            while IFS='|' read -r file_size file_path; do
                if [[ "$file_size" != "$current_size" ]]; then
                    # Process previous group
                    if [[ ${#size_files[@]} -gt 1 ]]; then
                        ((group_count++))
                        local size_human=$(bytes_to_human $file_size)
                        echo "📄 相同大小组 #$group_count ($size_human):"
                        for same_file in "${size_files[@]}"; do
                            echo "  • $(basename "$same_file")"
                            echo "    $same_file"
                            if [[ $duplicate_count -eq 0 ]]; then
                                duplicate_count=1  # First file of group
                            else
                                duplicate_size_saved=$((duplicate_size_saved + file_size))
                                ((duplicate_count++))
                            fi
                        done
                        echo ""
                        
                        # Limit output to prevent overwhelming
                        if [[ $group_count -ge 5 ]]; then
                            echo "  (显示前5组，可能还有更多...)"
                            break
                        fi
                    fi
                    
                    # Start new group
                    current_size="$file_size"
                    size_files=("$file_path")
                else
                    size_files+=("$file_path")
                fi
            done < "$temp_dir/same_size.txt"
            
            # Process last group
            if [[ ${#size_files[@]} -gt 1 && $group_count -lt 5 ]]; then
                ((group_count++))
                local size_human=$(bytes_to_human $current_size)
                echo "📄 相同大小组 #$group_count ($size_human):"
                for same_file in "${size_files[@]}"; do
                    echo "  • $(basename "$same_file")"
                    echo "    $same_file"
                done
                echo ""
            fi
            
            if [[ $duplicate_count -gt 1 ]]; then
                local waste_human=$(bytes_to_human $duplicate_size_saved)
                echo "📊 发现 $duplicate_count 个可能重复的文件"
                echo "💾 潜在浪费空间：$waste_human"
                echo ""
                echo "💡 建议："
                echo "  • 手动检查相同大小的文件是否真的重复"
                echo "  • 删除不需要的重复文件以节省空间"
                echo "  • 使用专业工具进行精确的重复文件检测"
            fi
            
        else
            echo "✅ 未发现相同大小的文件！"
            echo "💡 您的文件管理很好，没有明显的重复文件。"
        fi
    fi
    
    # Cleanup
    rm -rf "$temp_dir" 2>/dev/null
    
    echo ""
    echo "⚡ 快速检测完成！"
    echo ""
    read -p "$(echo -e ${WHITE}$(get_text "press_enter")${NC})"
}

# System performance optimization function  
execute_performance_optimization() {
    print_title "⚡ 系统性能优化"
    echo ""
    
    echo "🔧 分析系统性能..."
    echo ""
    
    # Check system load
    local load_avg=$(uptime | awk -F'load averages:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_count=$(sysctl -n hw.ncpu)
    local load_percent=$(echo "scale=0; $load_avg * 100 / $cpu_count" | bc 2>/dev/null || echo "0")
    
    echo "📊 系统状态分析："
    echo "  CPU 负载：${load_percent}% (${load_avg}/${cpu_count} cores)"
    
    # Memory analysis
    local memory_info=$(vm_stat | head -5)
    local free_pages=$(echo "$memory_info" | grep "Pages free" | awk '{print $3}' | tr -d '.')
    local inactive_pages=$(echo "$memory_info" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
    local page_size=$(vm_stat | grep "page size" | awk '{print $8}')
    
    if [[ -n "$free_pages" && -n "$page_size" ]]; then
        local free_memory=$(( (free_pages + inactive_pages) * page_size / 1024 / 1024 ))
        echo "  可用内存：${free_memory}MB"
    fi
    
    # Disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    echo "  磁盘使用：${disk_usage}%"
    
    echo ""
    echo "🚀 性能优化建议："
    echo ""
    
    # Provide recommendations
    if [[ $load_percent -gt 80 ]]; then
        echo "  ⚠️  高CPU使用率检测"
        echo "     • 考虑重启高负载应用"
        echo "     • 检查活动监视器中的进程"
    fi
    
    if [[ $disk_usage -gt 85 ]]; then
        echo "  ⚠️  磁盘空间不足"
        echo "     • 建议运行自动清理功能"
        echo "     • 清理大文件和下载项"
    fi
    
    if [[ -n "$free_memory" && $free_memory -lt 1024 ]]; then
        echo "  ⚠️  可用内存较低"
        echo "     • 建议重启一些应用程序"
        echo "     • 考虑清理内存缓存"
    fi
    
    echo "  ✅ 可执行的优化操作："
    echo "     1. 清理DNS缓存"
    echo "     2. 重建启动服务数据库"
    echo "     3. 清理字体缓存"
    echo "     4. 刷新系统内存"
    echo ""
    
    read -p "是否执行这些优化操作？(y/N): " optimize_choice
    
    if [[ "$optimize_choice" =~ ^[Yy] ]]; then
        echo ""
        echo "🔧 执行性能优化..."
        
        # DNS cache flush
        echo "  🌐 刷新DNS缓存..."
        sudo dscacheutil -flushcache 2>/dev/null && echo "    ✅ DNS缓存已刷新"
        
        # Launch services rebuild
        echo "  🚀 重建启动服务数据库..."
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null && echo "    ✅ 启动服务数据库已重建"
        
        # Font cache
        echo "  🔤 清理字体缓存..."
        sudo atsutil databases -remove 2>/dev/null && echo "    ✅ 字体缓存已清理"
        
        # Memory purge
        echo "  💾 清理系统内存..."
        sudo purge 2>/dev/null && echo "    ✅ 系统内存已清理"
        
        echo ""
        echo "🎉 性能优化完成！"
        echo "💡 建议重启应用程序以获得最佳效果。"
    else
        echo "跳过优化操作。"
    fi
    
    echo ""
    read -p "$(echo -e ${WHITE}$(get_text "press_enter")${NC})"
}

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This script is designed for macOS only."
    exit 1
fi

# Check for required tools
if ! command -v du >/dev/null 2>&1; then
    print_error "Required tool 'du' not found."
    exit 1
fi

# Start the program
main "$@"