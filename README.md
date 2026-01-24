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

> **Note:** This project is fully **Dockerized**. It runs inside a container, making it compatible with Windows, Linux, and macOS without complex environment setup.

---

## Folder Structure

```text
p4bot/
 ├─ p4_poller/
 ├─ opened_watcher/
 ├─ canwork_bot/
 ├─ runtime/                 # Mapped to container volume (Logs & State)
 ├─ config.example.json
 ├─ Dockerfile               # Docker build definition
 ├─ Jenkinsfile              # CI/CD Pipeline (Deployment)
 ├─ docker-compose.yml       # Service definition
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

### 1. Clone the repository

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

**How to get a Webhook URL:**
1. Go to your Discord Channel Settings (Gear icon).
2. Click **Integrations** → **Webhooks** → **New Webhook**.
3. Copy the **Webhook URL** and paste it below.

```jsonc
"poller": {
  "webhook": "[https://discord.com/api/webhooks/](https://discord.com/api/webhooks/)...",
  "depotFilter": "//your_depot/...",
  "intervalSeconds": 30
}
```

#### 2.3 Bot Token (`canworkBot`)

```jsonc
"canworkBot": {
  "botToken": "YOUR_DISCORD_BOT_TOKEN_HERE"
}
```

---

## How to Run

### Option A: Using Jenkins (Recommended)
This repository includes a full **CI/CD pipeline** that handles **auto-deployment** and **session maintenance**.

#### 1. Start Services
Run Jenkins and the Bot using Docker Compose:
```bash
docker-compose up -d --build
```

#### 2. Unlock Jenkins
1. Open `http://localhost:8080` in your browser.
2. To get the initial admin password, run:
   ```bash
   docker exec p4bot-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
   ```
3. Complete the "Install Suggested Plugins" steps and create your admin account.

#### 3. Configure Credentials (Important!)
You need to save your Perforce password in Jenkins so it can run `p4 login` securely.

1. Go to **Manage Jenkins** → **Credentials** → **System** → **Global credentials**.
2. Click **Add Credentials**.
   - **Kind:** Secret text
   - **ID:** `p4-password`  *(Must match this exact ID)*
   - **Secret:** (Type your Perforce Password)
3. Click **Create**.

#### 4. Create Job 1: Auto-Deploy (`P4Bot-Deploy`)
This job builds and runs the container whenever code changes.

1. Click **New Item** → Name: `P4Bot-Deploy` → Select **Pipeline** → OK.
2. Scroll to **Triggers**: Check **Poll SCM** and enter `* * * * *` (checks every minute).
3. Scroll to **Pipeline**:
   - **Definition:** Pipeline script from SCM
   - **SCM:** Git
   - **Repository URL:** (Enter your local path or GitHub URL)
     - *Local Example:* `/var/jenkins_home/workspace/p4bot`
     - *GitHub Example:* `https://github.com/Hyeonjoon-Nam/p4bot.git`
   - **Branch Specifier:** `*/main`
   - **Script Path:** `Jenkinsfile`
4. Click **Save**.

#### 5. Create Job 2: Auto-Login (`P4-Auto-Login`)
This job refreshes the Perforce ticket every 12 hours.

1. Click **New Item** → Name: `P4-Auto-Login` → Select **Pipeline** → OK.
2. Scroll to **Triggers**: Check **Build periodically** and enter `H */12 * * *`.
3. Scroll to **Pipeline**:
   - **Definition:** Pipeline script
   - **Script:** Copy and paste the code below (Update `P4_PORT` and `P4_USER`).

```groovy
pipeline {
    agent any
    environment {
        // Must match the Credential ID you created in Step 3
        P4_PASS = credentials('p4-password')
        
        // UPDATE THESE VALUES
        P4_PORT = 'ssl:your-perforce-server:1666' 
        P4_USER = 'your_username'
    }
    stages {
        stage('Perforce Login') {
            steps {
                script {
                    // 1. Trust the fingerprint
                    sh 'docker exec p4bot p4 -p $P4_PORT trust -y'
                    
                    // 2. Login using the password credential
                    sh '''
                        set +x
                        echo $P4_PASS | docker exec -i p4bot p4 -p $P4_PORT -u $P4_USER login
                    '''
                    
                    // 3. Verify status
                    sh 'docker exec p4bot p4 -p $P4_PORT -u $P4_USER login -s'
                }
            }
        }
    }
}
```
4. Click **Save**.

#### 6. Run
Click **Build Now** on `P4Bot-Deploy` first to start the container.
Then click **Build Now** on `P4-Auto-Login` to verify the login session.

---

### Option B: Standalone (Docker only)
If you don't need Jenkins, you can run the bot directly:

```bash
docker run -d --name p4bot --restart unless-stopped \
  -v ${PWD}/config.json:/app/config.json \
  -v ${PWD}/runtime:/app/runtime \
  p4bot:v1
```

---

## Maintenance

**Session Management:**
Perforce security tickets typically expire every 12 hours.

### 1. Automated (Jenkins)
The `P4-Auto-Login` pipeline configured above automatically renews the ticket every 12 hours. No manual action is required.

### 2. Manual (Standalone)
If you are running the bot without Jenkins, you must refresh the login session manually once a day:

```bash
# Enter the container and run p4 login
docker exec -it p4bot p4 login
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
| **`p4 trust` error** | Run `docker exec -it p4bot p4 trust -y` manually (or use Jenkins Auto-Login). |
| **Session expired** | Run `docker exec -it p4bot p4 login`. |
| **Bot not responding** | Check logs with `docker logs --tail 50 p4bot`. |
| **Call depth overflow** | Ensure `.ps1` scripts use absolute paths (fixed in v1). |

Logs are available at:
```text
runtime/*.log
```

---

## Roadmap & Status

### ✅ Completed
- **Docker Support:** Containerized the toolkit to ensure it runs consistently on any environment (Linux/Windows).
- **Jenkins CI/CD:** Implemented automated pipelines for `Auto-Login` (Session Management) and `Auto-Deploy` (CD).
- **Cross-Platform Compatibility:** Refactored path handling to be environment-agnostic via Docker.

### 🔜 Future Improvements
- Notification feature when a locked file becomes available.

---

## Security

- Never commit `config.json`.
- Do not upload real webhooks or tokens.
- Use `config.example.json` for sharing.

---

## License

MIT
