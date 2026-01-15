#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CSV_FILE="/tmp/user_permissions_report_$(date +%Y%m%d_%H%M%S).csv"

# 显示标题
echo -e "${YELLOW}==================================${NC}"
echo -e "${YELLOW}群晖NAS LDAP用户权限查询工具${NC}"
echo -e "${YELLOW}==================================${NC}"
echo ""

# 输入用户名
read -p "请输入要查询的用户名，无需输入域名（例如: zhangsan）: " USERNAME

# 检查用户名是否为空
if [ -z "$USERNAME" ]; then
    echo -e "${RED}错误: 用户名不能为空！${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}请选择查询范围:${NC}"
echo "  1) 查询所有共享文件夹的权限"
echo "  2) 查询指定共享文件夹下的一级子文件夹权限"
echo ""
read -p "请输入选项 (1 或 2): " QUERY_MODE

# 验证输入
if [[ ! "$QUERY_MODE" =~ ^[12]$ ]]; then
    echo -e "${RED}错误: 无效的选项！${NC}"
    exit 1
fi

# 定义要扫描的路径数组
declare -a SCAN_PATHS=()

if [ "$QUERY_MODE" == "1" ]; then
    # 模式1: 扫描所有共享文件夹
    echo ""
    echo -e "${CYAN}正在获取所有共享文件夹列表...${NC}"
    
    # 获取所有共享文件夹（排除系统文件夹）
    for share in /volume*/*/ ; do
        if [ -d "$share" ]; then
            share_name=$(basename "$share")
            # 排除系统文件夹
            if [[ ! "$share_name" =~ ^(@|#|homes|homes$) ]]; then
                SCAN_PATHS+=("$share")
            fi
        fi
    done
    
    echo -e "${GREEN}找到 ${#SCAN_PATHS[@]} 个共享文件夹${NC}"
    SCAN_MODE="共享文件夹"
    
else
    # 模式2: 扫描指定共享文件夹的一级子文件夹
    echo ""
    echo -e "${CYAN}请输入要查询的共享文件夹名称（支持多个）${NC}"
    echo "  - 多个文件夹用空格分隔，例如: A B C"
    echo "  - 共享文件夹路径格式: /volume1/共享文件夹名称"
    echo ""
    read -p "请输入共享文件夹名称: " SHARE_NAMES
    
    # 检查输入是否为空
    if [ -z "$SHARE_NAMES" ]; then
        echo -e "${RED}错误: 共享文件夹名称不能为空！${NC}"
        exit 1
    fi
    
    # 将输入的共享文件夹名称转换为路径，并获取其一级子文件夹
    for share_name in $SHARE_NAMES; do
        share_path="/volume1/$share_name"
        
        if [ ! -d "$share_path" ]; then
            echo -e "${RED}警告: 共享文件夹不存在: $share_path${NC}"
            continue
        fi
        
        # 获取该共享文件夹下的所有一级子文件夹
        for subfolder in "$share_path"/*/ ; do
            if [ -d "$subfolder" ]; then
                SCAN_PATHS+=("$subfolder")
            fi
        done
    done
    
    if [ ${#SCAN_PATHS[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未找到任何有效的文件夹！${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}找到 ${#SCAN_PATHS[@]} 个子文件夹${NC}"
    SCAN_MODE="一级子文件夹"
fi

# 询问是否在CSV中包含无权限的文件夹
echo ""
read -p "是否在CSV中包含无权限的文件夹？(y/n，默认n): " INCLUDE_NO_PERM
INCLUDE_NO_PERM=${INCLUDE_NO_PERM:-n}

echo ""
echo -e "${YELLOW}==================================${NC}"
echo -e "${YELLOW}开始扫描...${NC}"
echo -e "${YELLOW}==================================${NC}"
echo "用户: $USERNAME"
echo "查询模式: $SCAN_MODE"
echo "扫描数量: ${#SCAN_PATHS[@]} 个文件夹"
echo "========================================"

# 创建CSV文件，使用UTF-8 BOM确保Excel正确识别中文
echo -ne '\xEF\xBB\xBF' > "$CSV_FILE"
echo "序号,文件夹名称,完整路径,是否有权限,权限类型,权限详情" >> "$CSV_FILE"

count_with_perm=0
count_without_perm=0
csv_row_number=1
current_folder_num=0
total_folders=${#SCAN_PATHS[@]}

# 遍历所有要扫描的路径
for folder in "${SCAN_PATHS[@]}"; do
    ((current_folder_num++))
    
    # 显示进度
    if [ $((current_folder_num % 10)) -eq 0 ]; then
        echo -e "${CYAN}进度: $current_folder_num / $total_folders${NC}"
    fi
    
    folder_name=$(basename "$folder")
    parent_folder=$(dirname "$folder")
    parent_name=$(basename "$parent_folder")
    
    # 获取包含用户名的ACL行
    acl_line=$(synoacltool -get "$folder" 2>/dev/null | grep "$USERNAME")
    
    if [ -n "$acl_line" ]; then
        # 提取权限类型
        perm_type=$(echo "$acl_line" | sed 's/.*allow:\([^:]*\).*/\1/')
        
        # 屏幕输出（带颜色）
        if [ "$QUERY_MODE" == "1" ]; then
            echo -e "${GREEN}✓${NC} ${BLUE}$folder_name${NC} (共享文件夹)"
        else
            echo -e "${GREEN}✓${NC} ${BLUE}$parent_name/$folder_name${NC}"
        fi
        echo -e "  权限: ${GREEN}$perm_type${NC}"
        
        # CSV输出（转义特殊字符）
        acl_line_escaped=$(echo "$acl_line" | sed 's/"/""/g' | tr -d '\n' | tr -d '\r')
        
        if [ "$QUERY_MODE" == "1" ]; then
            display_name="$folder_name"
        else
            display_name="$parent_name/$folder_name"
        fi
        
        echo "\"$csv_row_number\",\"$display_name\",\"$folder\",\"是\",\"$perm_type\",\"$acl_line_escaped\"" >> "$CSV_FILE"
        
        ((count_with_perm++))
        ((csv_row_number++))
    else
        # 根据用户选择决定是否在CSV中记录无权限的文件夹
        if [[ "$INCLUDE_NO_PERM" =~ ^[Yy]$ ]]; then
            if [ "$QUERY_MODE" == "1" ]; then
                display_name="$folder_name"
            else
                display_name="$parent_name/$folder_name"
            fi
            
            echo "\"$csv_row_number\",\"$display_name\",\"$folder\",\"否\",\"-\",\"-\"" >> "$CSV_FILE"
            ((csv_row_number++))
        fi
        ((count_without_perm++))
    fi
done

echo ""
echo "========================================"
echo -e "${YELLOW}扫描完成！${NC}"
echo "========================================"
echo -e "统计结果:"
echo -e "  ${GREEN}有权限: $count_with_perm 个${NC}"
echo -e "  ${RED}无权限: $count_without_perm 个${NC}"
echo -e "  总计: $((count_with_perm + count_without_perm)) 个"
echo ""
echo -e "${YELLOW}CSV报告已生成:${NC}"
echo -e "  文件路径: ${BLUE}$CSV_FILE${NC}"
echo -e "  文件编码: UTF-8 (带BOM)"
echo -e "  记录条数: $((csv_row_number - 1)) 条"
echo "========================================"
echo ""
echo -e "${YELLOW}提示:${NC}"
echo "  - CSV文件可直接用Excel或WPS打开，中文显示正常"
if [ "$QUERY_MODE" == "2" ]; then
    echo "  - 查询的共享文件夹: $SHARE_NAMES"
fi
echo ""