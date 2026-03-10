#!/bin/bash
set -e

# 1. Nginx-muokkaus
NGINX_CONF="/etc/nginx/sites-enabled/munin"
if [ -f "$NGINX_CONF" ]; then
    sed -i 's/8089/4049/g' "$NGINX_CONF"
fi

# 2. Luodaan Multigraph Munin-plugin
PLUGIN_DEST="/etc/munin/plugins/abitti_status"

cat << 'EOF' > "$PLUGIN_DEST"
#!/bin/bash

# --- CONFIG-OSA ---
if [ "$1" = "config" ]; then
    # Graafi 1: Opiskelijat
    echo "multigraph abitti_students"
    echo "graph_title Abitti 2 Aktiiviset Opiskelijat"
    echo "graph_vlabel kpl"
    echo "graph_category abitti"
    echo "students.label Aktiiviset"
    echo "students.draw LINE2"

    # Graafi 2: Kokeet
    echo "multigraph abitti_exams"
    echo "graph_title Abitti 2 Kaynnissa olevat kokeet"
    echo "graph_vlabel kpl"
    echo "graph_category abitti"
    echo "exams.label Kokeita"
    echo "exams.draw LINE2"
    exit 0
fi

# --- DATA-OSA ---
export HOME=/tmp
RAW_DATA=$(cd /opt/ktp-controller && ./ktp-controller cli status 2>/dev/null)

if [ -z "$RAW_DATA" ]; then
    echo "multigraph abitti_students"
    echo "students.value 0"
    echo "multigraph abitti_exams"
    echo "exams.value 0"
    exit 0
fi

STUDENTS=$(printf '%s\n' "$RAW_DATA" | awk '
BEGIN {
    in_students=0
    count=0
}
{
    if ($0 ~ /^students:$/) {
        in_students=1
        next
    }
    if ($0 ~ /^exams:$/) {
        in_students=0
    }
    if (in_students && $0 ~ /is_active: true/) {
        count++
    }
}
END {
    print count+0
}')

EXAMS=$(printf '%s\n' "$RAW_DATA" | awk '
BEGIN {
    in_exams=0
    count=0
}
{
    if ($0 ~ /^exams:$/) {
        in_exams=1
        next
    }
    if (in_exams && $0 ~ /^  - uuid:/) {
        count++
    }
}
END {
    print count+0
}')

# Tulostetaan multigraph-muodossa
echo "multigraph abitti_students"
echo "students.value ${STUDENTS:-0}"

echo "multigraph abitti_exams"
echo "exams.value ${EXAMS:-0}"
EOF

# 3. Oikeudet ja konfiguraatio
chmod +x "$PLUGIN_DEST"

# Lisätään oikeudet ajaa rootina, jotta ktp-controller toimii
CONF_FILE="/etc/munin/plugin-conf.d/abitti"
echo "[abitti_status]" > "$CONF_FILE"
echo "user root" >> "$CONF_FILE"

systemctl restart munin-node
echo "Valmis! Graafit on nyt erotettu toisistaan multigraph-tekniikalla."
