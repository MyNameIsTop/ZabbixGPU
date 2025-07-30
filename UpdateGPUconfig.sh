#!/bin/bash

# === Configuration ===
ZABBIX_CONF="/etc/zabbix/zabbix_agentd.conf"
GPU_SCRIPT_DIR="/etc/zabbix/scripts"
GPU_SCRIPT_URL="https://raw.githubusercontent.com/plambe/zabbix-nvidia-smi-multi-gpu/refs/heads/master/get_gpus_info.sh"
GPU_SCRIPT_PATH="$GPU_SCRIPT_DIR/get_gpus_info.sh"
BACKUP_CONF="${ZABBIX_CONF}.bak.$(date +%Y%m%d_%H%M%S)"

# === GPU UserParameters ===
read -r -d '' GPU_PARAMS <<'EOF'
# GPU Monitoring - Linux
UserParameter=gpu.number,nvidia-smi -L | /usr/bin/wc -l
UserParameter=gpu.discovery,/etc/zabbix/scripts/get_gpus_info.sh
UserParameter=gpu.fanspeed[*],nvidia-smi --query-gpu=fan.speed --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.power[*],nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.temp[*],nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.utilization[*],nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.memutilization[*],nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.memfree[*],nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.memused[*],nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.memtotal[*],nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits -i $1 | tr -d "\n"
UserParameter=gpu.utilization.dec.min[*],nvidia-smi -q -d UTILIZATION -i $1 | grep -A 5 DEC | grep Min | tr -s ' ' | cut -d ' ' -f 4
UserParameter=gpu.utilization.dec.max[*],nvidia-smi -q -d UTILIZATION -i $1 | grep -A 5 DEC | grep Max | tr -s ' ' | cut -d ' ' -f 4
UserParameter=gpu.utilization.enc.min[*],nvidia-smi -q -d UTILIZATION -i $1 | grep -A 5 ENC | grep Min | tr -s ' ' | cut -d ' ' -f 4
UserParameter=gpu.utilization.enc.max[*],nvidia-smi -q -d UTILIZATION -i $1 | grep -A 5 ENC | grep Max | tr -s ' ' | cut -d ' ' -f 4
EOF

# === Step 1: Backup current config ===
echo "📁 Backup config to: $BACKUP_CONF"
cp "$ZABBIX_CONF" "$BACKUP_CONF"

# === Step 2: Remove existing GPU UserParameters ===
echo "🔍 Removing existing GPU UserParameters..."
while IFS= read -r line; do
    # Extract key name from UserParameter
    param_key=$(echo "$line" | cut -d= -f2 | cut -d, -f1)

    # Escape [ and ] for safe grep/sed
    escaped_key=$(echo "$param_key" | sed 's/\[/\\[/g; s/\]/\\]/g')

    # Remove any lines that match the full key (at line beginning)
    sed -i "/^UserParameter=${escaped_key},/d" "$ZABBIX_CONF" && \
      echo "🗑️  Removed existing: UserParameter=${param_key},..."
done <<< "$(echo "$GPU_PARAMS" | grep ^UserParameter=)"

# === Step 3: Append new GPU UserParameters ===
{
  echo ""
  echo "# === BEGIN GPU CONFIG ==="
  echo "$GPU_PARAMS"
  echo "# === END GPU CONFIG ==="
  echo ""
} >> "$ZABBIX_CONF"

echo "✅ GPU UserParameters added to: $ZABBIX_CONF"

# === Step 4: Download GPU discovery script ===
echo "📥 Installing GPU discovery script..."
mkdir -p "$GPU_SCRIPT_DIR"
curl -s -o "$GPU_SCRIPT_PATH" "$GPU_SCRIPT_URL"
chmod +x "$GPU_SCRIPT_PATH"
echo "✅ Script saved to: $GPU_SCRIPT_PATH"

# === Step 5: Test the discovery script ===
echo "🧪 Running test: get_gpus_info.sh"
if bash "$GPU_SCRIPT_PATH"; then
    echo "✅ GPU discovery script ran successfully."
else
    echo "❌ Failed to run GPU discovery script. Please check nvidia-smi and GPU drivers."
fi

# === Step 6: Restart zabbix-agent ===
echo "🔄 Restarting zabbix-agent..."
systemctl restart zabbix-agent && echo "✅ zabbix-agent restarted." || echo "❌ Failed to restart zabbix-agent."

echo "🎉 All done."
