# Perforce to Discord Automation (p4bot)

A small set of tools to bridge a Perforce server with Discord.  
This repository is designed to be **self-hosted**, meaning each user or team runs the scripts on their own machine with their own Discord webhooks and bot token.

---

## Features

### 1. Submit Poller (`p4_poller/`)
Watches submitted Perforce changelists and posts embed messages to a Discord channel.

### 2. Opened Watcher (`opened_watcher/`)
Periodically runs `p4 opened` and reports who is currently holding which files.

### 3. `/canwork` Bot (`canwork_bot/`)
A Discord slash command that checks whether a specific file is currently opened in Perforce.

---

## Folder Structure

```
p4bot/
 ├─ p4_poller/
 │   ├─ p4-poller.ps1
 │   └─ run_poller.cmd
 ├─ opened_watcher/
 │   ├─ opened_watcher_min.ps1
 │   └─ run_opened_watcher.cmd
 ├─ canwork_bot/
 │   ├─ p4_canwork_bot.py
 │   ├─ canwork_task.ps1
 │   └─ run_canwork_bot.cmd
 ├─ runtime/
 │   ├─ last_change.txt
 │   ├─ opened_snapshot.json
 │   └─ logs...
 ├─ config.example.json
 └─ README.md
```

---

## Requirements

- Windows
- Perforce CLI (`p4`)
- Python 3.10+ (for `/canwork`)
- Discord bot token (for `/canwork`)
- Windows Task Scheduler

---

## Installation

### 1. Clone or place the repository

Example:
```
C:\p4bot
```

### 2. Create your own config

```
config.example.json -> config.json
```

Fill in:
- Perforce server info  
- Discord webhook URLs  
- Bot token  
- Optional trim prefixes

### 3. Runtime files

Runtime files (logs, snapshots) will be created automatically under ```runtime/```.

---

## Config Reference

### `p4`
- `port`: P4PORT  
- `user`: P4USER  
- `client`: P4CLIENT  

### `poller`
- `depotFilter`: Path to watch for submitted changes  
- `intervalSeconds`: Poll interval  
- `webhook`: Discord webhook  
- `userRouting`: Optional per-user extra webhooks  
- `trimPrefixes`: Remove long path prefixes  

### `openedWatcher`
- `depotPath`: Path for `p4 opened`  
- `snapshotFile`: JSON state saved locally  
- `webhook`: Discord webhook  
- `trimPrefixes`: Output cleanup  

### `canworkBot`
- `botToken`: Discord bot token  
- `pythonwPath`: Path to pythonw.exe  
- `taskName`: Scheduled task name  
- `scriptName`: Bot Python file  

---

## Running Scripts Manually

### Submit Poller
```
powershell -ExecutionPolicy Bypass -File .\p4_poller\p4-poller.ps1
```

### Opened Watcher
```
powershell -ExecutionPolicy Bypass -File .\opened_watcher\opened_watcher_min.ps1
```

### CanWork Bot
```
python p4_canwork_bot.py
```

---

## Register Scheduled Tasks (Auto-Start)

### Submit Poller
Runs at logon.

### Opened Watcher
Runs at logon and loops internally.

### CanWork Bot
Uses pythonw.exe (no console window).

Register:
```
powershell -ExecutionPolicy Bypass -File .\canwork_bot\canwork_task.ps1
```

---

## Discord Slash Command Setup

1. Create a bot in Discord Developer Portal  
2. Enable:  
   - MESSAGE CONTENT INTENT  
   - APPLICATION COMMANDS  
3. Put your bot token in:  
   `config.json -> canworkBot.botToken`  
4. First run will auto-sync `/canwork`

Usage:
```
/canwork filename: Content/Maps/MyMap.umap
```

---

## Troubleshooting

| Issue | Fix |
|------|-----|
| Bot not starting | Token missing in config.json |
| Snapshot missing | Run opened_watcher first |
| No changelist messages | Wrong poller webhook |
| Wrong path matching | Update trimPrefixes |

Logs:
```
runtime/*.log
```

---

## Security

- Never commit `config.json`
- Do not upload real webhooks or tokens
- Use `config.example.json` for sharing

---

## License
MIT
