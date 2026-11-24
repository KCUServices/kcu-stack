#!/bin/bash
# Hook do vzdump: avisa no Discord quando um backup do Proxmox falha.
# O vzdump chama este script em cada fase do backup, com a fase no 1.º argumento.
#
# Instalar:
#   cp vzdump-hook.sh /root/vzdump-hook.sh && chmod 700 /root/vzdump-hook.sh
#   e na tarefa de backup: script /root/vzdump-hook.sh
#
# O webhook NUNCA fica escrito aqui. Vem de:
#   1. a variável DISCORD_WEBHOOK_URL, ou
#   2. o ficheiro indicado em WEBHOOK_FILE (por defeito /root/.discord-webhook),
#      criado com:  install -m 600 /dev/null /root/.discord-webhook  e depois colas o URL lá dentro.

phase="$1"
WEBHOOK_FILE="${WEBHOOK_FILE:-/root/.discord-webhook}"

case "$phase" in
  backup-abort|job-abort)
    url="${DISCORD_WEBHOOK_URL:-}"
    if [ -z "$url" ] && [ -r "$WEBHOOK_FILE" ]; then
      url=$(head -n 1 "$WEBHOOK_FILE" | tr -d '[:space:]')
    fi
    # Sem webhook configurado, não faz nada (o backup nunca fica parado por causa do aviso).
    [ -z "$url" ] && exit 0

    msg="🚨 Proxmox: um backup FALHOU (fase ${phase}${VMID:+, guest $VMID}) em $(hostname) às $(date '+%H:%M de %d/%m'). Vê Datacenter > Backup e o log da tarefa."
    # Escapa aspas e barras para o JSON ficar válido.
    msg_json=$(printf '%s' "$msg" | sed -e 's/[\\]/&&/g' -e 's/"/\\"/g')

    curl -s -m 15 -H "Content-Type: application/json" \
      -d "{\"content\":\"${msg_json}\"}" "$url" >/dev/null 2>&1
    ;;
esac

# Sair sempre com 0: um erro aqui não deve fazer falhar o backup.
exit 0
