#!/bin/bash

# 1. Muokataan Nginx-konfiguraatiota
NGINX_CONF="/etc/nginx/sites-enabled/munin"

if [ -f "$NGINX_CONF" ]; then
    sed -i 's/8089/4049/g' "$NGINX_CONF"
    echo "Nginx: Portti vaihdettu 8089 -> 4049."
else
    echo "Virhe: Tiedostoa $NGINX_CONF ei löytynyt."
fi

# 2. Luodaan joustava Munin-plugin
PLUGIN_DEST="/etc/munin/plugins/abitti_students"

cat << 'EOF' > "$PLUGIN_DEST"
#!/bin/bash

if [ "$1" = "config" ]; then
    echo "graph_title Abitti 2 Aktiivisuus"
    echo "graph_vlabel kpl"
    echo "graph_category abitti"
    echo "students.label Aktiiviset opiskelijat"
    echo "students.draw LINE2"
    echo "students.type GAUGE"
    echo "exams.label Kaynnissa olevat kokeet"
    echo "exams.draw LINE2"
    echo "exams.type GAUGE"
    echo "papers.label Luodut vastaukset"
    echo "papers.draw LINE2"
    echo "papers.type GAUGE"
    exit 0
fi

export HOME=/tmp
NOW=$(date -u +%s)

# Haetaan koko status-data
RAW_DATA=$(cd /opt/ktp-controller && ./ktp-controller cli status 2>/dev/null)

# Lasketaan arvot AWK:lla
RESULT=$(echo "$RAW_DATA" | awk -v now="$NOW" '
    BEGIN { 
        RS="  - studentUuid"; 
        student_count=0;
        paper_count=0;
        ENVIRON["TZ"] = "UTC"
    }
    # Yleinen answerPaperCount NR=1 lohkosta
    NR == 1 {
        if (match($0, /answerPaperCount: ([0-9]+)/, ap)) {
            paper_count = ap[1]
        }
    }
    # Opiskelijakohtaiset lohkot
    NR > 1 {
        if (match($0, /updateTime: .([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})/, t)) {
            
            timestr = t[1] " " t[2] " " t[3] " " t[4] " " t[5] " " t[6]
            utctime = mktime(timestr)
            diff = now - utctime
            
            # DYNAAMINEN YHTEYSTARKISTUS:
            # Jos "isConnected" löytyy datasta, sen on oltava true.
            # Jos sitä ei löydy, ehto on aina tosi (pass).
            conn_ok = 1
            if ($0 ~ /isConnected:/) {
                if ($0 !~ /isConnected: true/) {
                    conn_ok = 0
                }
            }
            
            # EHDOT:
            # 1. Koe ei ole päättynyt (examFinishedAt: null) [cite: 1, 4]
            # 2. Yhteystila on OK (jos muuttuja olemassa)
            # 3. Status on jokin aktiivisista 
            # 4. Päivitys on tuore (alle 10min) [cite: 3, 4]
            if ($0 ~ /examFinishedAt: null/ && \
                conn_ok == 1 && \
                ($0 ~ /studentStatus: in-exam/ || $0 ~ /studentStatus: surveillance-not-on/) && \
                diff < 600 && diff >= -60) {
                
                student_count++
                
                # Kerätään uniikit kokeiden nimet
                if (match($0, /examTitle: ([^\n]+)/, title)) {
                    exams[title[1]] = 1
                }
            }
        }
    }
    END { 
        exam_count = 0
        for (i in exams) exam_count++
        print student_count " " exam_count " " paper_count
    }
')

# Puretaan tulokset
STUDENTS=$(echo $RESULT | cut -d' ' -f1)
EXAMS=$(echo $RESULT | cut -d' ' -f2)
PAPERS=$(echo $RESULT | cut -d' ' -f3)

echo "students.value ${STUDENTS:-0}"
echo "exams.value ${EXAMS:-0}"
echo "papers.value ${PAPERS:-0}"
EOF

# Oikeudet ja restart
chmod +x "$PLUGIN_DEST"
systemctl restart nginx
systemctl restart munin-node

echo "Valmis! Joustava isConnected-tarkistus otettu käyttöön."
