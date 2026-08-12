#!/usr/bin/env bash
set -u

echo "=== OBS Flatpak installations ==="
flatpak list --app --columns=application,name,branch,installation | grep -E '^com\.obsproject\.Studio' || true

echo
echo "=== LocalVocal Flatpak installations ==="
flatpak list --columns=application,branch,installation | grep -Ei 'LocalVocal|obsproject' || true

echo
echo "=== OBS matching extensions ==="
flatpak info -e com.obsproject.Studio 2>&1 || true

echo
echo "=== Is LocalVocal visible inside the OBS sandbox? ==="
flatpak run --command=sh com.obsproject.Studio -c '
echo "--- /.flatpak-info extensions ---"
grep -i "extensions\|localvocal\|obsproject" /.flatpak-info || true
echo
echo "--- /app/plugins content ---"
find /app/plugins -maxdepth 6 \( -iname "*local*" -o -iname "*vocal*" -o -iname "*obs-localvocal*" \) -print 2>/dev/null || true
'

echo
echo "=== Latest OBS log plugin errors ==="
latest_log="$(ls -t ~/.var/app/com.obsproject.Studio/config/obs-studio/logs/*.txt 2>/dev/null | head -n1 || true)"
if [[ -n "$latest_log" ]]; then
  echo "Log: $latest_log"
  grep -iE 'localvocal|vocal|obs-localvocal|plugin|dlopen|failed|error|undefined|symbol' "$latest_log" || true
else
  echo "No Flatpak OBS log found."
fi
