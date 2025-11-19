# Perforce to Discord Automation (p4bot)

A small set of tools to bridge a Perforce server with Discord.  
This repository is designed to be **self-hosted**, meaning each user or team runs the scripts on their own machine with their own Discord webhooks and bot token.

---

## Who is this for?

This toolkit was originally built for a small team working with Perforce in an exclusive-lock environment, but it works equally well for individuals or any collaborative workflow.

By pointing the webhooks to your own private Discord channel (and optionally using `userRouting`), you can:

- Track your own submitted changelists across any project (past or current)
- Keep a lightweight “activity log” of your work without opening Perforce
- Check whether a file is safe to work on without navigating Perforce’s UI

Everything runs locally on the user’s machine — no server access or shared infrastructure required.

---

## Background
This project originally started as a solution to a real workflow problem my team faced while using Perforce in an exclusive-lock environment.

During previous projects, team members often had to manually check Perforce to see who submitted what, or who was holding which files. We even used to copy-paste changelist messages into a Discord channel so everyone could stay updated — a process that was easy to forget and impossible to scale.

Checking who had a file opened was even worse: you either had to ask in chat or dig through Perforce’s UI to find the right folder, which slowed everyone down during busy development periods.

Initially, I explored using Perforce server-side triggers to automate these tasks properly. However, our Perforce server was managed by the school’s IT department, and for security reasons they couldn't allow custom trigger scripts to be installed.

So I designed a fully self-hosted alternative — a client-side automation pipeline that polls Perforce, formats the results, and posts them to Discord, all running locally on a user’s machine with no server modifications required.

The project grew organically from there:
- Submit Poller → automated changelist notifications
- Opened Watcher → real-time visibility into who is holding which files
- `/canwork` slash command → created to solve the Discord message length limit when many files are opened, and to make single-file checks instant and convenient

What started as a patch to a recurring inconvenience has become a flexible toolset that supports both team workflows and solo developers who want better visibility into their Perforce activity.

---

## Features

### 1. Submit Poller (`p4_poller/`)
Watches submitted Perforce changelists and posts embed messages to a Discord channel.

### 2. Opened Watcher (`opened_watcher/`)
Periodically runs `p4 opened` and reports who is currently holding which files.

### 3. `/canwork` Bot (`canwork_bot/`)
A Discord slash command that checks whether a specific file is currently opened in Perforce.

---

> Note: While the examples use common game-development file patterns, p4bot is not engine-specific and works with any Perforce-based workflow (Unity, DCC tools, custom engines, or general depot usage).

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

## Roadmap

These are realistic, planned improvements for future versions of **p4bot** — all aligned with the current architecture and fully achievable.

### **1. Extended `/canwork` Features**
- **`/notify_when_free`**  
  Allow users to “subscribe” to a file. If someone is holding the file, the bot monitors it and automatically sends a DM or channel message when the file becomes free.
- Automatic path correction (guessing correct paths even when partial names are given)
- Improved matching logic for better accuracy

### **2. Swarm Integration**
If the user sets:
```
"swarmBase": "https://your-swarm-server"
```
the submit poller will attach a **“Open in Swarm”** link directly inside the Discord embed.

### **3. Path Normalization Enhancements**
- Automatic detection of depot prefixes for trimming  
- Better normalization across Windows / Linux / hybrid environments  
- Cleaner, more consistent path output in Discord messages

### **4. Opened Watcher Filters**
Optional filters so teams can reduce noise:
- Monitor only specific extensions (e.g., `.uasset`, `.umap`)
- Monitor only certain folders  
- Ideal for large projects with heavy check-out activity


---

## Security

- Never commit `config.json`
- Do not upload real webhooks or tokens
- Use `config.example.json` for sharing

---

## License
MIT
