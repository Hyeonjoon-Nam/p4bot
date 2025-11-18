# C:\p4bot\canwork_bot\p4_canwork_bot.py
# Discord slash command /canwork
# - Reads opened_snapshot.json written by opened_watcher_min.ps1
# - Tells you who currently has a file opened in Perforce

import os
import json
from pathlib import Path

import discord
from discord import app_commands

# --- Config / paths ---------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parents[1]  # ...\p4bot
CONFIG_PATH = BASE_DIR / "config.json"


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise RuntimeError(f"config.json not found at {CONFIG_PATH}")
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


CONFIG = load_config()

opened_cfg = CONFIG.get("openedWatcher") or {}
canwork_cfg = CONFIG.get("canworkBot") or {}
poller_cfg = CONFIG.get("poller") or {}

snapshot_rel = opened_cfg.get("snapshotFile", "runtime/opened_snapshot.json")
SNAPSHOT_PATH = (BASE_DIR / snapshot_rel).resolve()

# Trim prefixes: prefer openedWatcher.trimPrefixes, fall back to poller.trimPrefixes
if opened_cfg.get("trimPrefixes"):
    DEPOT_PREFIXES = [str(p) for p in opened_cfg["trimPrefixes"]]
elif poller_cfg.get("trimPrefixes"):
    DEPOT_PREFIXES = [str(p) for p in poller_cfg["trimPrefixes"]]
else:
    DEPOT_PREFIXES = [
        "//f25_kimbap_games/UnrealEngine/KimbapGame/KimbapGame/",
        "//f25_kimbap_games/UnrealEngine/KimbapGame/",
        "//f25_kimbap_games/",
    ]


def read_token() -> str:
    """Read Discord bot token from config.json (canworkBot.botToken)."""
    token = str(canwork_cfg.get("botToken", "")).strip()
    if not token:
        raise RuntimeError("canworkBot.botToken is missing or empty in config.json")
    return token


# --- Path helpers -----------------------------------------------------------

def normalize_path(p: str) -> str:
    """Normalize path: forward slashes, trimmed, lower-cased."""
    if not p:
        return ""
    return p.replace("\\", "/").strip().lower()


def depot_to_short(depot: str) -> str:
    """Convert full depot path to the same short form used by opened_watcher."""
    if not depot:
        return depot
    s = str(depot)
    for pref in DEPOT_PREFIXES:
        if s.startswith(pref):
            s = s[len(pref):]
            break
    if s.startswith("//"):
        s = s[2:]
    if s.startswith("/"):
        s = s[1:]
    return s


# --- Snapshot loading / search ----------------------------------------------

def load_snapshot() -> dict:
    """Load opened_snapshot.json into a Python dict."""
    if not SNAPSHOT_PATH.exists():
        print(f"[canwork] snapshot not found: {SNAPSHOT_PATH}")
        return {}

    try:
        # PowerShell writes UTF-8 (sometimes with BOM), so be tolerant.
        with SNAPSHOT_PATH.open("r", encoding="utf-8-sig") as f:
            raw = f.read()

        raw = raw.lstrip("\ufeff")  # extra safety
        data = json.loads(raw)

        if isinstance(data, dict):
            print(f"[canwork] snapshot loaded: {len(data)} entries from {SNAPSHOT_PATH}")
            return data

        print("[canwork] snapshot is not a dict")
        return {}

    except json.JSONDecodeError as e:
        print(f"[canwork] JSON decode error after BOM-strip: {e}")
        return {}
    except Exception as e:
        print(f"[canwork] unexpected error reading snapshot: {e}")
        return {}


def find_openers(target: str):
    """
    Find users currently opening a file that matches the given target.

    Matching rules:
      - depotFile normalized equals target, or ends with target
      - short path normalized equals target, or ends with target
      - if still no match, short path contains target as substring

    Returns:
      dict[user] = set(short_paths)
    """
    import os as _os

    q = normalize_path(target)
    if not q:
        return {}

    snapshot = load_snapshot()
    if not snapshot:
        return {}

    openers = {}
    match_count = 0

    for _, entry in snapshot.items():
        depot = entry.get("depotFile", "") or ""
        user = entry.get("user", "unknown") or "unknown"

        short = depot_to_short(depot) or depot

        depot_norm = normalize_path(depot)
        short_norm = normalize_path(short)
        filename_norm = _os.path.basename(short_norm)

        candidates = [depot_norm, short_norm, filename_norm]

        matched = False
        for c in candidates:
            if not c:
                continue
            if q == c or c.endswith(q):
                matched = True
                break

        # Loose match (e.g. partial directory name)
        if not matched and q in short_norm:
            matched = True

        if matched:
            match_count += 1
            if user not in openers:
                openers[user] = set()
            openers[user].add(short or depot)

    print(f"[canwork] target='{q}', matches={match_count}")
    return openers


# --- Discord client setup ---------------------------------------------------

class P4Client(discord.Client):
    def __init__(self):
        intents = discord.Intents.none()
        super().__init__(intents=intents)
        self.tree = app_commands.CommandTree(self)

    async def setup_hook(self) -> None:
        cmds = await self.tree.sync()
        print(f"[P4CanWorkBot] Synced {len(cmds)} command(s).")


client = P4Client()


@client.event
async def on_ready():
    print(f"[P4CanWorkBot] Logged in as {client.user} (id={client.user.id})")
    print("------")


@client.tree.command(
    name="canwork",
    description="Check if a file is safe to work on (not opened in Perforce).",
)
@app_commands.describe(
    filename="Example: Assets/real_test.txt or Content/Level/.../L_LobbyMap.umap"
)
async def canwork(interaction: discord.Interaction, filename: str):
    filename_norm = filename.replace("\\", "/").strip()

    print(f"[canwork] command from {interaction.user} : '{filename_norm}'")

    snapshot_exists = SNAPSHOT_PATH.exists()
    openers = find_openers(filename_norm)

    lines = []
    lines.append(f"🔍 Checking: `{filename_norm}`")

    if not snapshot_exists:
        lines.append("")
        lines.append("⚠ Snapshot file does not exist yet.")
        lines.append(f"Expected path: `{SNAPSHOT_PATH}`")
        lines.append("Make sure opened_watcher_min.ps1 has run at least once.")
        await interaction.response.send_message("\n".join(lines))
        return

    if not openers:
        lines.append("")
        lines.append(
            "✅ **Can work:** no matching opened files found in `opened_snapshot.json`."
        )
        await interaction.response.send_message("\n".join(lines))
        return

    lines.append("")
    lines.append("❌ **Cannot work safely:** file is currently opened by:")
    for user, paths in openers.items():
        sorted_paths = sorted(paths)
        path_list = ", ".join(f"`{p}`" for p in sorted_paths)
        lines.append(f"- **{user}** → {path_list}")

    await interaction.response.send_message("\n".join(lines))


if __name__ == "__main__":
    token = read_token()
    client.run(token)
