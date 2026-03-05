#!/bin/bash

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

    # Graafi 3: Vastauspaperit
    echo "multigraph abitti_papers"
    echo "graph_title Abitti 2 Vastaukset"
    echo "graph_vlabel kpl"
    echo "graph_category abitti"
    echo "papers.label Vastauspapereita"
    echo "papers.draw LINE2"
    exit 0
fi

# --- DATA-OSA ---
export HOME=/tmp
NOW=$(date -u +%s)
RAW_DATA=$(cd /opt/ktp-controller && ./ktp-controller cli status 2>/dev/null)

RESULT=$(echo "$RAW_DATA" | awk -v now="$NOW" '
    BEGIN { 
        RS="  - studentUuid"; 
        s_count=0; p_count=0;
        ENVIRON["TZ"] = "UTC"
    }
    NR == 1 {
        if (match($0, /answerPaperCount: ([0-9]+)/, ap)) p_count = ap[1]
    }
    NR > 1 {
        if (match($0, /updateTime: .([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})/, t)) {
            timestr = t[1] " " t[2] " " t[3] " " t[4] " " t[5] " " t[6]
            utctime = mktime(timestr)
            conn_ok = 1
            if ($0 ~ /isConnected:/ && $0 !~ /isConnected: true/) conn_ok = 0
            
            if ($0 ~ /examFinishedAt: null/ && conn_ok == 1 && \
                ($0 ~ /studentStatus: in-exam/ || $0 ~ /studentStatus: surveillance-not-on/) && \
                now - utctime < 600) {
                s_count++
                if (match($0, /examTitle: ([^\n]+)/, title)) exams[title[1]] = 1
            }
        }
    }
    END { 
        e_count = 0; for (i in exams) e_count++
        print s_count " " e_count " " p_count
    }
')

# Puretaan ja tulostetaan multigraph-muodossa
STUDENTS=$(echo $RESULT | cut -d' ' -f1)
EXAMS=$(echo $RESULT | cut -d' ' -f2)
PAPERS=$(echo $RESULT | cut -d' ' -f3)

echo "multigraph abitti_students"
echo "students.value ${STUDENTS:-0}"

echo "multigraph abitti_exams"
echo "exams.value ${EXAMS:-0}"

echo "multigraph abitti_papers"
echo "papers.value ${PAPERS:-0}"
EOF

# 3. Oikeudet ja konfiguraatio
chmod +x "$PLUGIN_DEST"

# Lisätään oikeudet ajaa rootina, jotta ktp-controller toimii
CONF_FILE="/etc/munin/plugin-conf.d/abitti"
echo "[abitti_status]" > "$CONF_FILE"
echo "user root" >> "$CONF_FILE"

systemctl restart munin-node
echo "Valmis! Graafit on nyt erotettu toisistaan multigraph-tekniikalla."
