- run sudo lobby help to identify what commands are available
- We don't edit live files. We edit the repo and run the appropriate lobby setup command to implement.

## Network Monitoring
- Network monitor checks connectivity every 5 minutes (appropriate for offline-first kiosk system)
- Shows persistent critical notifications when offline
- Automatically dismisses only network-monitor notifications when connectivity returns
- Monitors 3 reliable DNS servers: 8.8.8.8, 1.1.1.1, 9.9.9.9
- Service is automatically started by `lobby start` command
- Mako notifications work properly with correct service dependencies and permissions