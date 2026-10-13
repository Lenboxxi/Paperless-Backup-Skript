#!/bin/bash
set -euo pipefail

EXPORT_DIR="$HOME/paperless/export"
BACKUP_ROOT="$HOME/nextcloud/PaperlessBackup"
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="$BACKUP_ROOT/$DATE"

RETENTION_DAYS=5
KEEP_MIN=3

DISCORD_WEBHOOK=
NEXTCLOUD_USER=
NEXTCLOUD_PASSWORD=
NEXTCLOUD_URL=

send_discord () {
    curl -fsS -H "Content-Type: application/json" \
         -d "{\"content\": \"$1\"}" \
         "$DISCORD_WEBHOOK" >/dev/null || true
}

nextcloud_sync () {
    nextcloudcmd --user "$NEXTCLOUD_USER" --password "$NEXTCLOUD_PASSWORD" \
        "$HOME/nextcloud" "$NEXTCLOUD_URL"
}

STEP="Start"
trap 'send_discord "❌ Paperless Backup fehlgeschlagen: $STEP ($DATE)"' ERR

echo "=== Backup gestartet ==="

STEP="Nextcloud-Sync vorher"
nextcloud_sync

STEP="Export"
docker exec paperless-webserver-1 document_exporter ../export

STEP="Export prüfen"
if [ -z "$(ls -A "$EXPORT_DIR")" ]; then
    echo "Export-Verzeichnis ist leer, Abbruch." >&2
    false
fi

STEP="Kopieren"
mkdir -p "$BACKUP_DIR"
cp -a "$EXPORT_DIR"/. "$BACKUP_DIR"/
touch "$BACKUP_DIR"

STEP="Aufräumen"
CUTOFF=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)

mapfile -t BACKUPS < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -regextype posix-extended -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    -printf '%f\n' | sort)

COUNT=${#BACKUPS[@]}
for name in "${BACKUPS[@]}"; do
    (( COUNT <= KEEP_MIN )) && break
    if [[ "$name" < "$CUTOFF" ]]; then
        echo "Lösche altes Backup: $name"
        rm -rf -- "${BACKUP_ROOT:?}/$name"
        COUNT=$((COUNT - 1))
    fi
done

STEP="Nextcloud-Sync nachher"
nextcloud_sync

echo "=== Backup erfolgreich ==="
send_discord "✅ Paperless Backup erfolgreich ($DATE)"
