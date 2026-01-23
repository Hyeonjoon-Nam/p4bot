# Perforce to Discord Automation (p4bot)

A small set of tools to bridge a Perforce server with Discord.
This repository is designed to be **self-hosted**, meaning each user or team runs the scripts on their own machine (via Docker) with their own Discord webhooks and bot token.

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

> **Note:** This project is now **Dockerized**. It runs inside a container, making it compatible with Windows, Linux, and macOS without complex environment setup.

---

## Folder Structure

```text
p4bot/
 ├─ p4_poller/
 │   └─ p4-poller.ps1
 ├─ opened_watcher/
 │   └─ opened_watcher_min.ps1
 ├─ canwork_bot/
 │   └─ p4_canwork_bot.py
 ├─ runtime/                 # Mapped to container volume
 │   ├─ last_change.txt
 │   ├─ opened_snapshot.json
 │   └─ logs...
 ├─ config.example.json
 ├─ Dockerfile               # Docker build definition
 ├─ start.sh                 # Container entrypoint
 └─ README.md
```

---

## Requirements

- **Docker Desktop** (Windows, Linux, or Mac)
- **Git**
- Perforce Account (P4USER, Password)
- Discord Bot Token & Webhook URLs

---

## Installation

This section walks through the **exact steps** to get p4bot running on your own machine using Docker.

### 1. Clone the repository

1. Choose a folder on your machine, for example `C:\p4bot`.
2. Clone from GitHub:

   ```bash
   git clone [https://github.com/Hyeonjoon-Nam/p4bot.git](https://github.com/Hyeonjoon-Nam/p4bot.git) C:\p4bot
   ```

### 2. Create your own `config.json`

All configuration happens in a single file.

1. Copy `config.example.json` to `config.json`.
2. Open `config.json` and fill in the details below.

#### 2.1 Perforce Info (`p4`)

```jsonc
"p4": {
  "port":   "ssl:your-perforce-server:1666",
  "user":   "your_p4_user",
  "client": "your_p4_workspace_name"
}
```

#### 2.2 Webhooks (`poller` & `openedWatcher`)

```jsonc
"poller": {
  "webhook": "[https://discord.com/api/webhooks/](https://discord.com/api/webhooks/)...",
  "depotFilter": "//your_depot/...",
  "intervalSeconds": 30
}
```
* **webhook**: Create a webhook in your Discord channel settings and paste the URL here.

#### 2.3 Bot Token (`canworkBot`)

```jsonc
"canworkBot": {
  "botToken": "YOUR_DISCORD_BOT_TOKEN_HERE"
}
```
* Create a bot in the [Discord Developer Portal](https://discord.com/developers/applications).
* Enable **MESSAGE CONTENT INTENT** in the Bot settings.
* Copy the token and paste it here.

---

## Docker Build & Run (The New Way)

Instead of using Windows Task Scheduler, we now use Docker to run everything in the background.

### 1. Build the Image

Run this command in the repository root. (Add `--no-cache` if you modified scripts).

```powershell
docker build --no-cache --network=host -t p4bot:v1 .
```

### 2. Run the Container

This runs the bot in the background (`-d`) and ensures it restarts automatically (`--restart unless-stopped`).
We mount the `config.json` and `runtime/` folder so logs and state are saved on your host machine.

```powershell
docker run -d --name p4bot --restart unless-stopped `
  -v ${PWD}/config.json:/app/config.json `
  -v ${PWD}/runtime:/app/runtime `
  p4bot:v1
```

### 3. Verify Execution

Check the logs to see if everything started correctly.

```powershell
docker logs -f p4bot
```

---

## Maintenance (Important)

### Daily Login (Manual for now)
Since Perforce tickets typically expire every 12 hours, and the bot runs inside a container, **you must refresh the login session manually once a day**.

(Automated login via Jenkins is planned for the next update).

```powershell
# 1. Enter the container and run p4 login
docker exec -it p4bot p4 login

# 2. (Type your password and press Enter)
```

---

## Discord Slash Command Setup

1. Invite the bot to your server using the OAuth2 URL Generator in the Discord Developer Portal (Scopes: `bot`, `applications.commands`).
2. Once the container is running, the `/canwork` command will sync automatically.

**Usage:**
```
/canwork filename: Content/Maps/MyMap.umap
```

---

## Troubleshooting

| Issue | Fix |
|------|-----|
| **`p4 trust` error** | Run `docker exec -it p4bot p4 trust -y` manually. |
| **Session expired** | Run `docker exec -it p4bot p4 login`. |
| **Bot not responding** | Check logs with `docker logs --tail 50 p4bot`. |
| **Call depth overflow** | Ensure `.ps1` scripts use absolute paths (fixed in v1). |

Logs are available at:
```text
runtime/*.log
```

---

## Roadmap

The focus of p4bot is shifting towards **infrastructure stability** and **cross-platform support** before expanding feature sets.

### 1. DevOps & Infrastructure (Current Focus)
* **Docker Support (Done):** Containerizing the toolkit (Python bot + P4 CLI) to ensure it runs consistently on any environment (Linux/Windows/Server).
* **Jenkins CI/CD (Next):** Implementing an automated pipeline for build verification and testing to streamline deployment.

### 2. Cross-Platform Compatibility
* **Path Normalization:** Refactoring path handling to support both Windows (`\`) and Linux (`/`) separators.
* **Environment Agnostic:** Removing hardcoded system paths to allow flexible configuration across different operating systems.

---

## Security

- Never commit `config.json`.
- Do not upload real webhooks or tokens.
- Use `config.example.json` for sharing.

---

## License

MIT