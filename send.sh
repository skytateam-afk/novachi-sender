#!/bin/bash
# Public runner: prints counts only, never names or addresses.
# Runs one sending round: send.sh <list name> <cap per inbox>. Needs BYPASS, PASSWORD, BASE in the environment.
set -u
if [ -z "$BYPASS" ] || [ -z "$PASSWORD" ]; then echo "The VERCEL_BYPASS and ADMIN_PASSWORD secrets are not set."; exit 1; fi
C=(-s -m 75 -b jar -c jar -H "x-vercel-protection-bypass: $BYPASS" -H "x-novachi-runner: 1")
login=$(curl "${C[@]}" -H 'content-type: application/json' -d "$(jq -n --arg p "$PASSWORD" '{password:$p}')" "$BASE/api/login")
echo "Login: $(echo "$login" | jq -c '{ok,error}' 2>/dev/null || echo "$login" | head -c 200)"
[ "$(echo "$login" | jq -r .ok 2>/dev/null)" = "true" ] || exit 1
BATCH="$1"
CAPMSG="$2"
echo "List: ${BATCH:-default}"
status=$(curl "${C[@]}" "$BASE/api/gmail/batch?batch=$BATCH")
END=$(echo "$status" | jq -r '.window.end // 15' 2>/dev/null || echo 15)
START=$(echo "$status" | jq -r '.window.start // 10' 2>/dev/null || echo 10)
echo "Engine: $(echo "$status" | jq -c '{ok,open:.now.open,queued:[.plan[]?|.today]}' 2>/dev/null || echo "no answer")"
if [ "${PROBE:-}" = "1" ]; then
  PD="${PREVIEW_DATE:-$(TZ=America/New_York date -d tomorrow +%F)}"
  pv=$(curl "${C[@]}" "$BASE/api/gmail/batch?batch=$BATCH&date=$PD")
  echo "Plan for $PD, emails queued per inbox: $(echo "$pv" | jq -c '[.plan[]?|.today]' 2>/dev/null)"
  for pg in truvasse skyta qivo loopups; do echo "Booking page $pg: $(curl -s -o /dev/null -w '%{http_code}' -m 30 "https://qivo.tregox.com/api/qivo/meet/$pg")"; done
  echo "Probe only, nothing sent."; exit 0
fi
SENDERS="princess@gettruvasse.com mitchel@gettruvasse.com jennifer@gettruvasse.com"
declare -A CUR; declare -A DONE; for s in $SENDERS; do CUR[$s]=0; DONE[$s]=0; done
CAP=${CAPMSG:-100}
echo "Window $START:00 to $END:00 New York, up to $CAP per inbox"
sent=0; skipped=0
while :; do
  hour=$(TZ=America/New_York date +%-H)
  all=1; for s in $SENDERS; do [ "${DONE[$s]}" -lt "$CAP" ] && all=0; done
  if [ "$all" = 1 ]; then echo "All three inboxes reached $CAP today. Sent $sent."; break; fi
  if [ "$hour" -ge "$END" ]; then echo "$END:00 New York: done. Sent $sent, skipped $skipped."; break; fi
  for s in $SENDERS; do
    [ "${DONE[$s]}" -ge "$CAP" ] && continue
    r=$(curl "${C[@]}" -H 'content-type: application/json' -d "{\"sender\":\"$s\",\"batch\":\"$BATCH\",\"cursor\":${CUR[$s]}}" "$BASE/api/gmail/batch")
    st=$(echo "$r" | jq -r '.status // .error // "no answer"' 2>/dev/null || echo "bad answer")
    c=$(echo "$r" | jq -r '.cursor // empty' 2>/dev/null); [ -n "$c" ] && CUR[$s]=$c
    n=$(echo "$r" | jq -r '(.skipped // []) | length' 2>/dev/null || echo 0); skipped=$((skipped + n))
    case "$st" in
      sent) sent=$((sent + 1)); DONE[$s]=$((DONE[$s] + 1)); [ $((sent % 10)) = 0 ] && echo "$(TZ=America/New_York date +%H:%M) sent $sent so far, skipped $skipped";;
      waiting|closed|skipped|finished) ;;
      *) echo "$(TZ=America/New_York date +%H:%M) inbox ${s%%@*}: $(echo "$st" | head -c 80 | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/[address]/g')";;
    esac
  done
  if [ "$hour" -lt "$START" ]; then sleep 60; else sleep 20; fi
done
