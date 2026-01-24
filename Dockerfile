# 1. Base Image: Python 3.11 on Debian 12 (Bookworm)
FROM python:3.11-slim-bookworm

# 2. Install essential system utilities
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    git \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# 3. Install PowerShell Core (pwsh)
RUN wget -q "https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb" && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y powershell

# 4. Install Perforce CLI (helix-cli)
# STRATEGY: Use 'ubuntu/jammy' repository instead of debian.
# This works perfectly on Debian and bypasses the 404 error on the debian path.
RUN wget -qO - https://package.perforce.com/perforce.pubkey | gpg --dearmor -o /usr/share/keyrings/perforce.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/perforce.gpg] https://package.perforce.com/apt/ubuntu jammy release" > /etc/apt/sources.list.d/perforce.list && \
    apt-get update && \
    apt-get install -y helix-cli

# 5. Set working directory
WORKDIR /app

# 6. Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 7. Copy source code
COPY . .

# 8. Permissions
RUN chmod +x start.sh

# 9. Environment variables
ENV PYTHONUNBUFFERED=1
ENV IO_ENCODING=UTF-8
ENV LANG=C.UTF-8

# 10. Start command
CMD ["./start.sh"]