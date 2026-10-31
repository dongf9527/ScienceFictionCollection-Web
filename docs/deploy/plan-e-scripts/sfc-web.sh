#!/usr/bin/env bash
# sfc-web.sh —— 方案 E 服务管理脚本（nginx 后台服务的启动/关闭/状态/部署/日志）
# 用法: sfc-web.sh {start|stop|restart|reload|enable|disable|status|deploy|logs}
#   start/stop/restart  启动、停止、重启 nginx（站点本身是纯静态文件，nginx 即服务本体）
#   enable/disable      设置/取消 WSL 启动时自动运行（systemd 自启）
#   status              查看运行状态
#   deploy              拉取代码并重新构建发布（调用同目录 sfc-web-deploy.sh）
#   logs                跟踪访问/错误/部署日志
set -euo pipefail

ACTION="${1:-status}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SFC_ROOT="${SFC_ROOT:-/opt/sfc}"

case "$ACTION" in
  start)   sudo systemctl start nginx ;;
  stop)    sudo systemctl stop nginx ;;
  restart) sudo systemctl restart nginx ;;
  reload)  sudo systemctl reload nginx ;;
  enable)  sudo systemctl enable nginx ;;      # WSL 启动时自动拉起
  disable) sudo systemctl disable nginx ;;
  status)  systemctl status nginx --no-pager -l ;;
  deploy)  exec "$SCRIPT_DIR/sfc-web-deploy.sh" ;;
  logs)    sudo tail -n 50 -f /var/log/nginx/access.log \
                    /var/log/nginx/error.log \
                    "$SFC_ROOT/deploy.log" ;;
  *) echo "用法: $0 {start|stop|restart|reload|enable|disable|status|deploy|logs}"; exit 1 ;;
esac
