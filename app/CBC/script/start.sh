HOST_IP="$HOST_IP"

sed -i "s/10.71.33.161/$HOST_IP/" /app/ILM_CBC/settings.py
