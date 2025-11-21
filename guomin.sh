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
UPDATE_LOG_FILE="./guomin_update.log"  # Git update log file
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"  # 脚本绝对路径

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

# Update code from git
update_code() {
    log_info "Updating code from git repository..."
    
    # Check if git is installed
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git is not installed"
        return 1
    fi
    
    # Check if current directory is a git repository
    if [ ! -d ".git" ]; then
        log_error "Current directory is not a git repository"
        return 1
    fi
    
    # Save current branch
    local current_branch=$(git branch --show-current 2>/dev/null)
    if [ -z "$current_branch" ]; then
        log_error "Failed to get current branch"
        return 1
    fi
    
    log_info "Current branch: $current_branch"
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        log_warning "You have uncommitted changes"
        read -p "Do you want to stash changes and continue? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git stash save "Auto-stash before update $(date '+%Y-%m-%d %H:%M:%S')" >> "$UPDATE_LOG_FILE" 2>&1
            log_info "Changes stashed"
        else
            log_info "Update cancelled"
            return 1
        fi
    fi
    
    # Fetch latest changes
    log_info "Fetching latest changes..."
    if ! git fetch origin >> "$UPDATE_LOG_FILE" 2>&1; then
        log_error "Failed to fetch from remote"
        return 1
    fi
    
    # Check if there are updates
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse origin/$current_branch 2>/dev/null)
    
    if [ "$local_commit" = "$remote_commit" ]; then
        log_success "Code is already up to date"
        return 0
    fi
    
    # Pull latest changes
    log_info "Pulling latest changes..."
    if git pull origin "$current_branch" >> "$UPDATE_LOG_FILE" 2>&1; then
        log_success "Code updated successfully"
        log_info "Update log: $UPDATE_LOG_FILE"
        
        # Ask if user wants to restart service
        if check_pid_file > /dev/null; then
            read -p "Service is running. Do you want to restart it? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                restart_service
            fi
        fi
        return 0
    else
        log_error "Failed to pull changes"
        log_error "Please check update log: $UPDATE_LOG_FILE"
        return 1
    fi
}

# Setup auto-update with cron
setup_auto_update() {
    local interval=${1:-60}  # Default: every 60 minutes
    
    log_info "Setting up auto-update (every $interval minutes)..."
    
    # Validate interval
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 1 ]; then
        log_error "Invalid interval. Please specify a positive number (minutes)"
        return 1
    fi
    
    # Check if cron is available
    if ! command -v crontab >/dev/null 2>&1; then
        log_error "Crontab is not available on this system"
        return 1
    fi
    
    # Create cron job entry
    local cron_comment="# Guomin website auto-update"
    local cron_job="*/$interval * * * * cd $(pwd) && $SCRIPT_PATH update-silent >> $UPDATE_LOG_FILE 2>&1"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH update-silent"; then
        log_warning "Auto-update cron job already exists"
        read -p "Do you want to update it? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled"
            return 1
        fi
        # Remove old cron job
        crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH update-silent" | crontab -
    fi
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_comment"; echo "$cron_job") | crontab -
    
    if [ $? -eq 0 ]; then
        log_success "Auto-update enabled (every $interval minutes)"
        log_info "Update log will be saved to: $UPDATE_LOG_FILE"
        log_info "To view cron jobs: crontab -l"
        log_info "To stop auto-update: $0 stop-auto-update"
        return 0
    else
        log_error "Failed to setup auto-update"
        return 1
    fi
}

# Stop auto-update
stop_auto_update() {
    log_info "Stopping auto-update..."
    
    if ! command -v crontab >/dev/null 2>&1; then
        log_error "Crontab is not available on this system"
        return 1
    fi
    
    # Check if cron job exists
    if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH update-silent"; then
        log_warning "Auto-update is not enabled"
        return 1
    fi
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "Guomin website auto-update" | grep -v "$SCRIPT_PATH update-silent" | crontab -
    
    if [ $? -eq 0 ]; then
        log_success "Auto-update stopped"
        return 0
    else
        log_error "Failed to stop auto-update"
        return 1
    fi
}

# Silent update (for cron job)
update_code_silent() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting auto-update..." >> "$UPDATE_LOG_FILE"
    
    if ! command -v git >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Git is not installed" >> "$UPDATE_LOG_FILE"
        return 1
    fi
    
    if [ ! -d ".git" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Not a git repository" >> "$UPDATE_LOG_FILE"
        return 1
    fi
    
    local current_branch=$(git branch --show-current 2>/dev/null)
    
    # Fetch and check for updates
    git fetch origin >> "$UPDATE_LOG_FILE" 2>&1
    
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse origin/$current_branch 2>/dev/null)
    
    if [ "$local_commit" = "$remote_commit" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Code is up to date" >> "$UPDATE_LOG_FILE"
        return 0
    fi
    
    # Pull changes
    if git pull origin "$current_branch" >> "$UPDATE_LOG_FILE" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Code updated successfully" >> "$UPDATE_LOG_FILE"
        
        # Auto restart service if running
        if check_pid_file > /dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restarting service..." >> "$UPDATE_LOG_FILE"
            stop_service >> "$UPDATE_LOG_FILE" 2>&1
            sleep 2
            start_service >> "$UPDATE_LOG_FILE" 2>&1
        fi
        return 0
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to pull changes" >> "$UPDATE_LOG_FILE"
        return 1
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
    echo -e "  ${GREEN}start${NC}            Start Guomin website service"
    echo -e "  ${GREEN}stop${NC}             Stop Guomin website service"
    echo -e "  ${GREEN}restart${NC}          Restart Guomin website service"
    echo -e "  ${GREEN}status${NC}           Check service status"
    echo -e "  ${GREEN}logs${NC}             View recent logs (default 50 lines, specify: logs 100)"
    echo -e "  ${GREEN}follow${NC}           Follow logs in real-time"
    echo -e "  ${GREEN}clean${NC}            Clean log file"
    echo -e "  ${GREEN}update${NC}           Update code from git repository"
    echo -e "  ${GREEN}auto-update${NC}      Enable auto-update (specify interval: auto-update 30)"
    echo -e "  ${GREEN}stop-auto-update${NC} Stop auto-update"
    echo -e "  ${GREEN}help${NC}             Show this help information"
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
    echo "  $0 start              # Start service"
    echo "  $0 status             # Check status"
    echo "  $0 logs 100           # View last 100 lines of logs"
    echo "  $0 follow             # Follow logs in real-time"
    echo "  $0 restart            # Restart service"
    echo "  $0 update             # Update code from git"
    echo "  $0 auto-update 30     # Enable auto-update every 30 minutes"
    echo "  $0 stop-auto-update   # Stop auto-update"
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
        update)
            update_code
            ;;
        update-silent)
            update_code_silent
            ;;
        auto-update)
            setup_auto_update "${2:-60}"
            ;;
        stop-auto-update)
            stop_auto_update
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