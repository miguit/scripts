#!/bin/bash
set -e

# 1. Muokataan Nginx-konfiguraatiota
NGINX_CONF="/etc/nginx/sites-enabled/munin"

if [ -f "$NGINX_CONF" ]; then
    sed -i 's/:8089/:4049/g' "$NGINX_CONF"
    echo "Nginx: Portti vaihdettu 8089 -> 4049."
else
    echo "Virhe: Tiedostoa $NGINX_CONF ei löytynyt."
fi

# 2. Luodaan Munin-plugin
PLUGIN_DEST="/etc/munin/plugins/abitti_students"

cat << 'EOF' > "$PLUGIN_DEST"
#!/bin/bash

if [ "$1" = "config" ]; then
    echo "graph_title Abitti 2 Aktiivisuus"
    echo "graph_vlabel kpl"
    echo "graph_category abitti"
    echo "students.label Aktiiviset opiskelijat"
    echo "students.draw LINE2"
    echo "exams.label Kaynnissa olevat kokeet"
    echo "exams.draw LINE2"
    exit 0
fi

export HOME=/tmp

if [ ! -x /opt/ktp-controller/ktp-controller ]; then
    echo "students.value 0"
    echo "exams.value 0"
    exit 0
fi

RAW_DATA=$(cd /opt/ktp-controller && ./ktp-controller cli status 2>/dev/null)

if [ -z "$RAW_DATA" ]; then
    echo "students.value 0"
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

echo "students.value ${STUDENTS:-0}"
echo "exams.value ${EXAMS:-0}"
EOF

# Oikeudet kuntoon
chmod +x "$PLUGIN_DEST"

# 3. Tarkistetaan Nginx-konfiguraatio ja käynnistetään palvelut
nginx -t
systemctl restart nginx
systemctl restart munin-node

echo "Valmis! Abitti Munin -plugin päivitetty käyttämään is_active-statusta ja exams-listaa."
