---
name: pre_edit_backup
description: 修改代码前自动备份文件到项目根目录的lightning-bak文件夹，直接通过命令行复制实现，自动过滤构建缓存/依赖目录/临时文件，无需外部脚本。
---

# pre_edit_backup
## 目标
在修改、删除、重命名项目中的任意代码文件之前，先通过命令行复制文件到项目根目录的`lightning-bak`文件夹，自动过滤构建缓存、依赖目录和临时文件，无需外部脚本，确保修改前的版本被安全备份。

## 触发条件
当你准备对项目中的任意文件执行编辑、删除、重命名操作时，必须先触发本技能，执行备份后再执行修改。

## 执行步骤
1.  **过滤判断**：
    先检查要修改的文件路径，若路径包含以下内容，直接跳过备份：
    - 构建缓存目录：`build/`、`.gradle/`、`.dart_tool/`、`ios/Pods/`、`ios/build/`、`linux/flutter/`、`macos/Flutter/`、`windows/flutter/`
    - 依赖/临时文件：`.pub-cache/`、`.git/`、`.metadata`、`.log`结尾、`.tmp`结尾
    若属于以上情况，直接执行用户的修改指令，不备份。

2.  **构建备份路径**：
    若文件需要备份，执行以下操作：
    - 获取当前文件的**相对项目根目录路径**（例如文件路径为`D:/project/lib/main.dart`，则相对路径为`lib/main.dart`）
    - 生成带时间戳的备份文件名，格式：`原文件名_YYYYMMDD_HHMMSS.后缀`（例如`main.dart`变为`main_20260518_153000.dart`）
    - 目标备份路径为：`项目根目录/lightning-bak/[相对路径的目录]/[带时间戳的文件名]`

3.  **执行复制命令**：
    根据当前操作系统，执行对应的复制命令：
    - Windows 系统：
      ```cmd
      mkdir "项目根目录\lightning-bak\相对路径的目录" 2>nul
      copy /Y "原文件完整路径" "项目根目录\lightning-bak\相对路径的目录\带时间戳的文件名"