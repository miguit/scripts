#!/bin/bash

# 1. Muokataan Nginx-konfiguraatiota
NGINX_CONF="/etc/nginx/sites-enabled/munin"

if [ -f "$NGINX_CONF" ]; then
    sed -i 's/8089/4049/g' "$NGINX_CONF"
    echo "Nginx: Portti vaihdettu 8089 -> 4049."
else
    echo "Virhe: Tiedostoa $NGINX_CONF ei löytynyt."
fi

# 2. Luodaan Munin-plugin (sisältää in-exam -tuen)
PLUGIN_DEST="/etc/munin/plugins/abitti_students"

cat << 'EOF' > "$PLUGIN_DEST"
#!/bin/bash

if [ "$1" = "config" ]; then
    echo "graph_title Abitti 2 Aktiiviset Opiskelijat"
    echo "graph_vlabel kpl"
    echo "graph_category abitti"
    echo "students.label Aktiiviset (viim. 10min)"
    echo "students.draw LINE2"
    echo "students.type GAUGE"
    exit 0
fi

export HOME=/tmp
NOW=$(date -u +%s)

COUNT=$(cd /opt/ktp-controller && ./ktp-controller cli status 2>/dev/null | awk -v now="$NOW" '
    BEGIN { 
        RS="  - studentUuid"; 
        count=0;
        ENVIRON["TZ"] = "UTC"
    }
    NR > 1 {
        if (match($0, /updateTime: .([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})/, t)) {
            
            timestr = t[1] " " t[2] " " t[3] " " t[4] " " t[5] " " t[6]
            utctime = mktime(timestr)
            diff = now - utctime
            
            if ($0 ~ /examFinishedAt: null/ && $0 ~ /studentStatus: in-exam/ && diff < 600 && diff >= -60) {
                count++
            }
        }
    }
    END { print count }
')

echo "students.value $COUNT"
EOF

# Oikeudet kuntoon
chmod +x "$PLUGIN_DEST"

# 3. Käynnistetään palvelut uudelleen
systemctl restart nginx
systemctl restart munin-node

echo "Valmis! Skripti suoritettu puhtaasti."
