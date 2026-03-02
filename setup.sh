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
# Pakotetaan järjestelmän kello antamaan UTC-sekunnit
NOW=$(date -u +%s) [cite: 1]

COUNT=$(cd /opt/ktp-controller && ./ktp-controller cli status 2>/dev/null | awk -v now="$NOW" '
    BEGIN { 
        RS="  - studentUuid"; 
        count=0; [cite: 1]
        # Pakotetaan AWK käsittelemään ajat UTC-muodossa
        ENVIRON["TZ"] = "UTC" [cite: 2]
    }
    NR > 1 {
        if (match($0, /updateTime: .([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})/, t)) { [cite: 2]
            
            # Luodaan aikamerkkijono AWK:n mktime-muodossa
            timestr = t[1] " " t[2] " " t[3] " " t[4] " " t[5] " " t[6] [cite: 2, 3]
            utctime = mktime(timestr) [cite: 3]
            
            diff = now - utctime [cite: 3]
            
            # TARKISTETTU EHTO:
            # 1. Koe ei ole päättynyt (examFinishedAt: null)
            # 2. Status on joko virallinen "in-exam" tai erikoistapaus "in-exam-browser"
            # 3. Päivitys on tuore (alle 10min) ja kello ei ole liikaa edellä
            if ($0 ~ /examFinishedAt: null/ && \
                ($0 ~ /studentStatus: in-exam/ || $0 ~ /studentStatus: in-exam-browser/) && \
                diff < 600 && diff >= -60) { 
                count++
            }
        }
    }
    END { print count }
')

echo "students.value $COUNT"
