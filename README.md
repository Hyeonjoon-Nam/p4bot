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

> Note: While the examples use common game-development file patterns, p4bot is not engine-specific and works with any Perforce-based workflow (Unity, DCC tools, custom engines, or general depot usage).

---

## Folder Structure

```text
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
- Perforce CLI (`p4`) available in `PATH`
- Python 3.10+ (only required for `/canwork`)
- Discord bot token (only required for `/canwork`)
- Windows Task Scheduler

---

## Installation

This section walks through the **exact steps** to get p4bot running on your own machine.

### 1. Clone or place the repository

1. Choose a folder on your machine, for example:

   ```text
   C:\p4bot
   ```

2. Either:
   - Clone from GitHub:

     ```powershell
     git clone https://github.com/Hyeonjoon-Nam/p4bot.git C:\p4bot
     ```

   - Or download as ZIP from GitHub and extract it into `C:\p4bot`.

All paths in this README assume `C:\p4bot` as the root, but any folder is fine.

---

### 2. Create your own `config.json` (step-by-step)

All configuration happens in a single file.

#### 2.1 Copy the example file

1. In the repo root, find:

   ```text
   config.example.json
   ```

2. Make a copy and rename it to:

   ```text
   config.json
   ```

3. Open `config.json` in a text editor (VS Code, Notepad++, etc.).

You will see sections like `p4`, `poller`, `openedWatcher`, and `canworkBot`.

---

#### 2.2 Fill in Perforce server info (`p4` section)

This section tells p4bot how to talk to your Perforce server:

```jsonc
"p4": {
  "port":   "ssl:your-perforce-server:xxxx",
  "user":   "your_p4_user",
  "client": "your_p4_client"
}
```

- **`port` (P4PORT)**  
  - This is the address of your Perforce server.  
  - If you already use Perforce on this machine:
    - In a command prompt, run:

      ```powershell
      p4 set P4PORT
      ```

      and copy the value into `"port"`.  
    - Or open P4V → **Connection → Edit Current Workspace** and copy the *Server* field.
  - Example: `"ssl:perforce.mycompany.com:xxxx"`

- **`user` (P4USER)**  
  - Your Perforce username.  
  - Check with:

    ```powershell
    p4 set P4USER
    ```

    or from P4V under **Connection → Edit Current Workspace → User**.

- **`client` (P4CLIENT / workspace name)**  
  - The name of the workspace/client you use on this machine.  
  - Check with:

    ```powershell
    p4 set P4CLIENT
    ```

    or from P4V under **Connection → Edit Current Workspace → Workspace**.

If you are unsure about any of these values, ask whoever manages your Perforce server — they will usually know your P4PORT and help confirm your user/workspace.

---

#### 2.3 Create Discord webhooks for `poller` and `openedWatcher`

You need **at least one** Discord webhook for the submit poller, and **optionally another** for the opened-file watcher.

##### 2.3.1 Create a webhook in Discord

Repeat these steps for each channel you want:

1. Open Discord and go to the server where you want messages.
2. Create or choose a text channel, for example `#perforce-commits`.
3. Click the **⚙️ Settings** icon next to the channel name.
4. In the left sidebar, select **Integrations**.
5. Under **Webhooks**, click **New Webhook**.
6. Give it a name (e.g., `P4 Submit Poller`) and select the target channel.
7. Click **Copy Webhook URL**.
8. Click **Save Changes**.

Keep that URL handy — you will paste it into `config.json`.

##### 2.3.2 Configure the submit poller webhook

In `config.json`, find the `poller` section:

```jsonc
"poller": {
  "depotFilter": "//your_depot/...",
  "intervalSeconds": 30,
  "webhook": "https://discord.com/api/webhooks/XXXXX/XXXXX",
  "swarmBase": "",
  "userRouting": {},
  "trimPrefixes": [
    "//your_depot/Project/..."
  ],
  "stateFile": "runtime/last_change.txt",
  "logFile":   "runtime/p4_poller.log"
}
```

Set:

- **`webhook`**  
  - Paste the webhook URL you copied from Discord (e.g., from the `#perforce-commits` channel).

- **`depotFilter`**  
  - Restricts which submitted changelists are reported.  
  - Example: only your project depot:

    ```json
    "depotFilter": "//MyProject/..."
    ```

- **`intervalSeconds`**  
  - How often the script checks Perforce for new submissions (in seconds).  
  - 30–60 seconds is usually fine.

- **`userRouting` (optional)**  
  - Lets you send *extra* notifications for specific Perforce users to their own private channels.  
  - Example:

    ```json
    "userRouting": {
      "alice": "https://discord.com/api/webhooks/ALICE_WEBHOOK",
      "bob":   "https://discord.com/api/webhooks/BOB_WEBHOOK"
    }
    ```

  - To set this up:
    1. Repeat the webhook-creation steps above for each user’s private channel.
    2. Paste each user’s webhook URL here, keyed by their Perforce username.

##### 2.3.3 Configure the opened watcher webhook

In `config.json`, find the `openedWatcher` section:

```jsonc
"openedWatcher": {
  "depotPath":   "//your_depot/...",
  "webhook":     "https://discord.com/api/webhooks/XXXXX/XXXXX",
  "snapshotFile": "runtime/opened_snapshot.json",
  "logFile":      "runtime/opened_watcher.log",
  "trimPrefixes": [
    "//your_depot/Project/",
    "//your_depot/",
    "//"
  ]
}
```

Set:

- **`depotPath`**  
  - The depot scope for `p4 opened`.  
  - Example: `"//MyProject/..."` to only track files from one project.

- **`webhook`**  
  - Webhook URL for the **“opened files”** channel, e.g., `#perforce-opened`.  
  - Create this webhook the same way as above.

---

#### 2.4 Create a Discord bot and token for `/canwork`

This part is **only required** if you want to use the `/canwork` slash command.  
The poller and opened watcher only need webhooks and work without a bot.

##### 2.4.1 Create a Discord application + bot

1. Go to the Discord Developer Portal:  
   <https://discord.com/developers/applications>
2. Log in with your Discord account.
3. Click **New Application** (top-right).
4. Enter a name (e.g., `P4CanWorkBot`) and click **Create**.
5. Click your new application in the list, and in the left sidebar click **Bot**.  
   (You’ll configure its token and intents in the next steps.)

Now you have a bot user.

##### 2.4.2 Enable required intents

Still under **Bot** in the sidebar:

1. Scroll down to **Privileged Gateway Intents**.
2. Turn on:
   - **MESSAGE CONTENT INTENT**
3. Click **Save Changes** at the bottom.

(The bot primarily uses slash commands, but enabling message content intent is safe for future extensions.)

##### 2.4.3 Copy the bot token

1. Under **Bot**, in the **Token** section, click **Reset Token** (if needed), then **Copy**.
2. Open your `config.json`.
3. In the `canworkBot` section, set:

   ```jsonc
   "canworkBot": {
     "pythonwPath": "C:\\Path\\To\\pythonw.exe",
     "taskName":    "P4CanWorkBot",
     "scriptName":  "p4_canwork_bot.py",
     "botToken":    "YOUR_DISCORD_BOT_TOKEN_HERE"
   }
   ```

   - Replace `"YOUR_DISCORD_BOT_TOKEN_HERE"` with the token you copied.

> **Important:** Treat this token like a password.  
> Never commit your real token to Git, and never share it publicly.

##### 2.4.4 Invite the bot to your server

1. In the Developer Portal, go to your application.
2. Click **OAuth2 → URL Generator** (left sidebar).
3. Under **Scopes**, check:
   - `bot`
   - `applications.commands`
4. Under **Bot Permissions**, check at minimum:
   - **Send Messages**
   - **Use Slash Commands**
5. Copy the generated URL at the bottom.
6. Paste the URL into your browser, choose the target server, and click **Authorize**.

The bot should now appear in your server’s member list.

---

#### 2.5 Configure `pythonwPath` (for `/canwork`)

In the `canworkBot` section:

```jsonc
"pythonwPath": "C:\\Path\\To\\pythonw.exe"
```

- This should point to your `pythonw.exe` (the GUI-less Python executable).  
- Typical locations:

  ```text
  C:\Users\<you>\AppData\Local\Programs\Python\Python312\pythonw.exe
  ```

- You can find it by:
  1. Opening your Python installation directory.
  2. Copying the full path to `pythonw.exe`.

---

#### 2.6 Optional: Trim prefixes for cleaner paths

Both `poller` and `openedWatcher` support `trimPrefixes`, which are strings that will be removed from file paths before sending them to Discord.

Example:

```jsonc
"trimPrefixes": [
  "//MyProject/Main/",
  "//MyProject/",
  "//"
]
```

If the raw depot path is:

```text
//MyProject/Main/Content/Maps/MyMap.umap
```

The displayed path after trimming becomes:

```text
Content/Maps/MyMap.umap
```

You can add as many prefixes as you like; the script will strip the first matching one.

---

### 3. Runtime files

You do **not** need to edit any runtime files manually.

- By default, the scripts store state and logs under:

  ```text
  runtime/
    last_change.txt
    opened_snapshot.json
    *.log
  ```

- If the `runtime/` folder does not exist, create an empty `runtime` folder at the repo root before running the scripts for the first time.

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

```powershell
powershell -ExecutionPolicy Bypass -File .\p4_poller\p4-poller.ps1
```

### Opened Watcher

```powershell
powershell -ExecutionPolicy Bypass -File .\opened_watcher\opened_watcher_min.ps1
```

### CanWork Bot

```powershell
python p4_canwork_bot.py
```

---

## Register Scheduled Tasks (Auto-Start)

The recommended way to run everything in the background is via Windows Task Scheduler.

### Submit Poller

Runs at logon and loops internally.

### Opened Watcher

Runs at logon and loops internally.

### CanWork Bot

Uses `pythonw.exe` (no console window).

To register the `/canwork` bot task:

```powershell
powershell -ExecutionPolicy Bypass -File .\canwork_bot\canwork_task.ps1
```

You can verify the tasks in **Task Scheduler → Task Scheduler Library**.

---

## Discord Slash Command Setup

Once the bot is configured and invited to your server:

1. Ensure your bot token is correctly set in `config.json → canworkBot.botToken`.
2. Start the bot once (manually or via Task Scheduler):

   ```powershell
   python .\canwork_bot\p4_canwork_bot.py
   ```

3. On first startup, the bot will auto-register the `/canwork` command with Discord.

Usage in any channel where the bot has access:

```text
/canwork filename: Content/Maps/MyMap.umap
```

The bot looks up currently opened files (based on your `openedWatcher` scope) and replies whether the file is free or held by someone.

---

## Troubleshooting

| Issue                   | Fix                                     |
|-------------------------|------------------------------------------|
| Bot not starting        | Token missing or wrong in `config.json` |
| Snapshot missing        | Run `opened_watcher` first               |
| No changelist messages  | Wrong poller webhook or depot filter    |
| Wrong path matching     | Update `trimPrefixes`                   |

Logs:

```text
runtime/*.log
```

---

## Roadmap

These are realistic, planned improvements for future versions of **p4bot** — all aligned with the current architecture and fully achievable.

### 1. Extended `/canwork` Features

- `/notify_when_free` — allow users to “subscribe” to a file. If someone is holding the file, the bot monitors it and automatically sends a DM or channel message when the file becomes free.
- Automatic path correction (guessing correct paths even when partial names are given).
- Improved matching logic for better accuracy.

### 2. Swarm Integration

If the user sets:

```json
"swarmBase": "https://your-swarm-server"
```

the submit poller will attach an **“Open in Swarm”** link directly inside the Discord embed.

### 3. Path Normalization Enhancements

- Automatic detection of depot prefixes for trimming.  
- Better normalization across Windows / Linux / hybrid environments.  
- Cleaner, more consistent path output in Discord messages.

### 4. Opened Watcher Filters

Optional filters so teams can reduce noise:

- Monitor only specific extensions (e.g., `.uasset`, `.umap`).  
- Monitor only certain folders.  
- Ideal for large projects with heavy check-out activity.

---

## Security

- Never commit `config.json`.  
- Do not upload real webhooks or tokens.  
- Use `config.example.json` for sharing.

---

## License

MIT
