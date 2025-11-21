#!/bin/bash

# 过敏网站服务管理脚本
# 支持start、stop、restart、status功能

# 配置参数
JEKYLL_ENV="production"
CONFIG_FILE="./local/_config.yml"
PORT="4001"
PID_FILE="./guomin.pid"
LOG_FILE="./guomin.log"
HOST="0.0.0.0"  # 服务监听地址

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取本机IP地址
get_local_ip() {
    # 尝试多种方式获取本机IP
    local ip=""
    
    # macOS方式
    if command -v ipconfig >/dev/null 2>&1; then
        ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
    fi
    
    # Linux方式
    if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # 通用方式
    if [ -z "$ip" ]; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1 | sed 's/addr://')
    fi
    
    echo "${ip:-127.0.0.1}"
}

# Display access URLs
show_urls() {
    local ip=$(get_local_ip)
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📡 Service Access URLs:${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  🌐 Local:   ${BLUE}http://localhost:$PORT${NC}"
    echo -e "  🌐 Network: ${BLUE}http://127.0.0.1:$PORT${NC}"
    if [ "$ip" != "127.0.0.1" ]; then
        echo -e "  🌐 LAN:     ${BLUE}http://$ip:$PORT${NC}"
    fi
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 检查PID文件是否存在
check_pid_file() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
            echo "$pid"
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# 检查端口是否被占用
check_port() {
    if lsof -i :$PORT >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep ":$PORT " > /dev/null; then
        return 0
    fi
    return 1
}

# Start service
start_service() {
    log_info "Starting Guomin website service..."
    
    if check_pid_file > /dev/null; then
        log_warning "Service is already running (PID: $(check_pid_file))"
        return 1
    fi
    
    # Check if port is in use
    if check_port; then
        log_error "Port $PORT is already in use, please check or change port"
        lsof -i :$PORT 2>/dev/null || netstat -tuln 2>/dev/null | grep ":$PORT"
        return 1
    fi
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        return 1
    fi
    
    export JEKYLL_ENV="$JEKYLL_ENV"
    nohup bundle exec jekyll server --config "$CONFIG_FILE" --port "$PORT" --host "$HOST" >> "$LOG_FILE" 2>&1 &
    local jekyll_pid=$!
    
    echo "$jekyll_pid" > "$PID_FILE"
    
    # Wait for service to start
    log_info "Waiting for service to start..."
    local count=0
    while [ $count -lt 10 ]; do
        sleep 1
        if check_port; then
            break
        fi
        count=$((count + 1))
    done
    
    if ps -p "$jekyll_pid" > /dev/null 2>&1; then
        log_success "Guomin website service started successfully (PID: $jekyll_pid)"
        log_info "Service running on port: $PORT"
        log_info "Log file: $LOG_FILE"
        show_urls
        return 0
    else
        log_error "Failed to start Guomin website service"
        log_error "Please check log file: $LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Stop service
stop_service() {
    log_info "Stopping Guomin website service..."
    
    local pid=$(check_pid_file)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        sleep 2
        
        if ps -p "$pid" > /dev/null 2>&1; then
            log_warning "Service did not stop gracefully, forcing termination..."
            kill -9 "$pid" 2>/dev/null
        fi
        
        rm -f "$PID_FILE"
        log_success "Guomin website service stopped"
        return 0
    else
        log_warning "Service is not running"
        return 1
    fi
}

# Restart service
restart_service() {
    log_info "Restarting Guomin website service..."
    
    stop_service
    sleep 2
    start_service
}

# Check service status
status_service() {
    local pid=$(check_pid_file)
    if [ -n "$pid" ]; then
        log_success "Guomin website service is running (PID: $pid)"
        echo ""
        echo "📋 Service Information:"
        echo "  Process ID: $pid"
        echo "  Port: $PORT"
        echo "  Config File: $CONFIG_FILE"
        echo "  Environment: $JEKYLL_ENV"
        echo "  Log File: $LOG_FILE"
        
        # Check if port is listening
        if check_port; then
            echo -e "  Port Status: ${GREEN}✓ Listening${NC}"
            
            # Show process info
            if command -v ps >/dev/null 2>&1; then
                local cpu_mem=$(ps -p "$pid" -o %cpu,%mem | tail -n 1)
                echo "  Resource Usage: CPU${cpu_mem}"
            fi
            
            # Show log file size
            if [ -f "$LOG_FILE" ]; then
                local log_size=$(du -h "$LOG_FILE" | awk '{print $1}')
                echo "  Log Size: $log_size"
            fi
            
            show_urls
        else
            echo -e "  Port Status: ${RED}✗ Not Listening${NC}"
            log_warning "Service process exists but port is not listening, may have failed to start"
        fi
        return 0
    else
        log_error "Guomin website service is not running"
        return 1
    fi
}

# View logs
view_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        log_error "Log file not found: $LOG_FILE"
        return 1
    fi
    
    local lines=${1:-50}
    log_info "Showing last $lines lines of log:"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    tail -n "$lines" "$LOG_FILE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Follow logs in real-time
follow_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        log_error "Log file not found: $LOG_FILE"
        return 1
    fi
    
    log_info "Following logs in real-time (Ctrl+C to exit):"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    tail -f "$LOG_FILE"
}

# Clean logs
clean_logs() {
    if [ -f "$LOG_FILE" ]; then
        local size=$(du -h "$LOG_FILE" | awk '{print $1}')
        read -p "Are you sure you want to clean the log file ($size)? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            > "$LOG_FILE"
            log_success "Log file cleaned"
        else
            log_info "Cleaning cancelled"
        fi
    else
        log_warning "Log file not found"
    fi
}

# Show help information
show_help() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📚 Guomin Website Service Management Script${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 {start|stop|restart|status|logs|follow|clean|help}"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo -e "  ${GREEN}start${NC}     Start Guomin website service"
    echo -e "  ${GREEN}stop${NC}      Stop Guomin website service"
    echo -e "  ${GREEN}restart${NC}   Restart Guomin website service"
    echo -e "  ${GREEN}status${NC}    Check service status"
    echo -e "  ${GREEN}logs${NC}      View recent logs (default 50 lines, specify: logs 100)"
    echo -e "  ${GREEN}follow${NC}    Follow logs in real-time"
    echo -e "  ${GREEN}clean${NC}     Clean log file"
    echo -e "  ${GREEN}help${NC}      Show this help information"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo -e "  Environment: ${YELLOW}$JEKYLL_ENV${NC}"
    echo -e "  Config File: ${YELLOW}$CONFIG_FILE${NC}"
    echo -e "  Listen Host: ${YELLOW}$HOST${NC}"
    echo -e "  Port:        ${YELLOW}$PORT${NC}"
    echo -e "  PID File:    ${YELLOW}$PID_FILE${NC}"
    echo -e "  Log File:    ${YELLOW}$LOG_FILE${NC}"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 start          # Start service"
    echo "  $0 status         # Check status"
    echo "  $0 logs 100       # View last 100 lines of logs"
    echo "  $0 follow         # Follow logs in real-time"
    echo "  $0 restart        # Restart service"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 主函数
main() {
    case "$1" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            status_service
            ;;
        logs)
            view_logs "${2:-50}"
            ;;
        follow|tail)
            follow_logs
            ;;
        clean)
            clean_logs
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: '$1'"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 脚本入口
if [ $# -eq 0 ]; then
    show_help
    exit 1
else
    main "$1"
fi