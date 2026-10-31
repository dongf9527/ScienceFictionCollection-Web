# sfc-windows-setup.ps1 —— 方案 E Windows 侧一次性配置（在"管理员 PowerShell"中运行）
# 前提: 已按文档 E1 安装 WSL2 + Ubuntu-24.04，并在 WSL 内完成 nginx enable。

# 1) 局域网防火墙放行 8080（镜像网络与 NAT + portproxy 两种模式都需要）
New-NetFirewallRule -DisplayName "SFC-Web 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow

# 2) 仅 NAT 模式需要：把 Windows 主机 8080 转发到 WSL IP（镜像网络模式请跳过本步）
#    注意: WSL 重启后 IP 可能变化，需重跑本段刷新。
$wslIp = (wsl -d Ubuntu-24.04 -- hostname -I).Trim().Split(' ')[0]
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=$wslIp
netsh interface portproxy show v4tov4

# 3) 登录时自动启动 WSL 发行版（systemd 随之拉起已 enable 的 nginx）
schtasks /Create /TN "SFC-WSL-Boot" /TR "wsl.exe -d Ubuntu-24.04 --exec true" /SC ONLOGON /RL HIGHEST /F

Write-Host "完成。WSL 内验证: curl http://127.0.0.1:8080/ ；局域网访问: http://<本机IP>:8080/"
