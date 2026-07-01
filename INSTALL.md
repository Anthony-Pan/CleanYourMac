# 🧹 CleanMac 全局命令安装指南

## 快速安装

在CleanYourMac项目目录下运行：

```bash
./install.sh
```

## 安装说明

### 自动安装位置优先级：

1. **🍺 Homebrew目录** `/opt/homebrew/bin/cleanmac` (推荐)
   - ✅ 无需配置PATH
   - ✅ 立即可用
   - ✅ 系统级安装

2. **🏠 系统目录** `/usr/local/bin/cleanmac`
   - ✅ 无需配置PATH
   - ✅ 立即可用
   - ⚠️ 可能需要管理员权限

3. **👤 用户目录** `~/.local/bin/cleanmac`
   - ⚠️ 需要配置PATH
   - ⚠️ 需要重启终端
   - ✅ 不需要管理员权限

## 使用方法

安装完成后，在任何目录下都可以使用：

### 基本命令：
```bash
cleanmac              # 启动交互式界面
cleanmac --auto       # 快速自动清理
cleanmac --help       # 显示帮助信息
```

### 高级选项：
```bash
cleanmac --lang=cn    # 中文界面
cleanmac --lang=en    # 英文界面  
cleanmac --dry-run    # 预览模式（不删除文件）
cleanmac 30           # 保留30天内的文件
```

## 功能菜单

运行 `cleanmac` 后会看到：

```
选择功能：

[1] 🧹 自动清理
[2] 📱 卸载应用程序  
[3] 🛡️ 病毒扫描
[4] 📊 磁盘分析
[5] 🌐 语言 / Language
```

## 故障排除

### 命令找不到？

1. **检查安装位置**：
   ```bash
   which cleanmac
   ```

2. **重新运行安装**：
   ```bash
   ./install.sh
   ```

3. **手动检查PATH**：
   ```bash
   echo $PATH | tr ':' '\n' | grep -E "(homebrew|local)"
   ```

### 权限问题？

如果安装到系统目录失败，会自动回退到用户目录，然后：
```bash
source ~/.zshrc    # 或 ~/.bashrc
```

## 卸载

删除对应目录下的文件：
```bash
# Homebrew安装
rm /opt/homebrew/bin/cleanmac

# 系统安装  
rm /usr/local/bin/cleanmac

# 用户安装
rm ~/.local/bin/cleanmac
```

## 更新

重新运行安装脚本即可：
```bash
./install.sh
```

---

🎉 **安装成功后，无论在哪个目录，输入 `cleanmac` 就可以使用了！**