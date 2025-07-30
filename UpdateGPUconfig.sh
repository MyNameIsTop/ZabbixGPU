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

# === Step 0: Install dos2unix if needed ===
if ! command -v dos2unix >/dev/null 2>&1; then
    echo "📦 Installing dos2unix..."
    apt update && apt install -y dos2unix
fi

# === Step 1: Backup config ===
echo "📁 Backup config to: $BACKUP_CONF"
cp "$ZABBIX_CONF" "$BACKUP_CONF"

# === Step 2: Convert CRLF to LF ===
dos2unix "$ZABBIX_CONF" 2>/dev/null

# === Step 3: Comment existing UserParameters ===
echo "🔍 Commenting existing GPU UserParameters..."
while IFS= read -r line; do
    param_key=$(echo "$line" | cut -d= -f2 | cut -d, -f1)
    escaped_key=$(echo "$param_key" | sed 's/\[/\\[/g; s/\]/\\]/g')
    match_line=$(grep -E "^UserParameter=${escaped_key}," "$ZABBIX_CONF" || true)

    if [[ -n "$match_line" ]]; then
        echo "➡️  Commenting: $param_key"
        escaped_line=$(printf '%s\n' "$match_line" | sed 's/[]\/$*.^[]/\\&/g')
        sed -i "s|^$escaped_line|# $match_line|" "$ZABBIX_CONF"
    fi
done <<< "$(echo "$GPU_PARAMS" | grep ^UserParameter=)"

# === Step 4: Insert new GPU UserParameters below "# UserParameter=" ===
echo "📌 Inserting new GPU UserParameters under '# UserParameter='..."
insert_line=$(grep -n "^# UserParameter=" "$ZABBIX_CONF" | cut -d: -f1 | head -n1)

if [[ -n "$insert_line" ]]; then
    insert_at=$((insert_line + 1))
    tmp_file=$(mktemp)
    head -n "$insert_line" "$ZABBIX_CONF" > "$tmp_file"
    echo "# === BEGIN GPU CONFIG ===" >> "$tmp_file"
    echo "$GPU_PARAMS" >> "$tmp_file"
    echo "# === END GPU CONFIG ===" >> "$tmp_file"
    tail -n +"$insert_at" "$ZABBIX_CONF" >> "$tmp_file"
    mv "$tmp_file" "$ZABBIX_CONF"
    echo "✅ Inserted GPU UserParameters at line $insert_at"
else
    echo "⚠️  '# UserParameter=' not found, appending to end of file..."
    {
        echo ""
        echo "# === BEGIN GPU CONFIG ==="
        echo "$GPU_PARAMS"
        echo "# === END GPU CONFIG ==="
        echo ""
    } >> "$ZABBIX_CONF"
fi

# === Step 5: Install GPU discovery script ===
echo "📥 Installing GPU discovery script..."
mkdir -p "$GPU_SCRIPT_DIR"
curl -s -o "$GPU_SCRIPT_PATH" "$GPU_SCRIPT_URL"
chmod +x "$GPU_SCRIPT_PATH"
echo "✅ Script saved to: $GPU_SCRIPT_PATH"

# === Step 6: Test discovery script ===
echo "🧪 Running test: get_gpus_info.sh"
if bash "$GPU_SCRIPT_PATH"; then
    echo "✅ GPU discovery script ran successfully."
else
    echo "❌ Failed to run GPU discovery script. Please check nvidia-smi and GPU drivers."
fi

# === Step 7: Restart Zabbix agent ===
echo "🔄 Restarting zabbix-agent..."
systemctl restart zabbix-agent && echo "✅ zabbix-agent restarted." || echo "❌ Failed to restart zabbix-agent."

echo "🎉 All done."
