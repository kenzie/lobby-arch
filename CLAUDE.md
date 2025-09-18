- run sudo lobby help to identify what commands are available
- We don't edit live files. We edit the repo and run the appropriate lobby setup command to implement.

## Health Monitoring System
- Health monitor checks connectivity + browser + app every 5 minutes (appropriate for offline-first kiosk system)
- Shows persistent critical notifications when offline or browser/app issues detected
- Automatically dismisses health-monitor notifications when issues resolve
- Monitors 3 reliable DNS servers: 8.8.8.8, 1.1.1.1, 9.9.9.9
- Monitors browser process health and automatically restarts if missing
- Monitors app availability (localhost:8080) and restarts if unresponsive
- Service is automatically started by `lobby start` command
- Mako notifications work properly with correct service dependencies and permissions

## Browser Reliability
- Browser wrapper script treats any Chromium exit as failure (kiosk should never exit voluntarily)
- Wrapper handles systemd SIGTERM properly for maintenance operations
- Enhanced service dependencies with BindsTo=lobby-compositor.service for coordinated restarts
- Prevents 1.5+ hour blank screen issues through immediate crash detection