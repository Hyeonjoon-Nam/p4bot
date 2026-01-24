#!/bin/bash
set -e

echo "----------------------------------------"
echo "[Docker] p4bot Container Started"
echo "----------------------------------------"

# 1. Create runtime directory for logs and state files
mkdir -p runtime

echo "[Docker] Checking Perforce connection..."
# Check P4 connection and print version (ensure env vars are set)
p4 -V | head -n 1

echo "[Docker] Starting Opened Watcher (Interval: 60s)..."
# Run PowerShell script in background
pwsh -File ./opened_watcher/opened_watcher_min.ps1 -LoopSeconds 60 &

echo "[Docker] Starting P4 Poller (Interval: 30s)..."
# Run PowerShell script in background
pwsh -File ./p4_poller/p4-poller.ps1 -IntervalSeconds 30 &

echo "[Docker] Starting Discord Bot..."
# Run Python bot in foreground (Main process)
python ./canwork_bot/p4_canwork_bot.py