#!/bin/bash
# Testa portas TCP de um guest a partir de OUTRO container que NÃO está na lista de admins.
# Corre no Proxmox, como root. O container de teste precisa de bash (Debian e Ubuntu têm).
#
# Uso:  testar-portas.sh <ct-de-teste> <ip-do-alvo> <porta> [porta...]
# Ex.:  testar-portas.sh 200 192.168.1.50 22 80 443
#
# Depois da firewall, o esperado é: 22=fechada (o CT de teste não é admin) e as outras como antes.
# "fechada" quer dizer que não respondeu em 3 s (recusada ou bloqueada).
set -u
[ $# -ge 3 ] || { echo "Uso: $0 <ct-de-teste> <ip-do-alvo> <porta> [porta...]" >&2; exit 1; }
ct=$1; ip=$2; shift 2
case "$ct" in *[!0-9]*) echo "ID do container inválido: $ct" >&2; exit 1 ;; esac
case "$ip" in *[!0-9a-fA-F.:]*) echo "IP inválido: $ip" >&2; exit 1 ;; esac

linha="$ip:"
for p in "$@"; do
  case "$p" in ''|*[!0-9]*) echo "Porta inválida: $p" >&2; exit 1 ;; esac
  if pct exec "$ct" -- timeout 3 bash -c "echo > /dev/tcp/$ip/$p" >/dev/null 2>&1; then r=aberta; else r=fechada; fi
  linha="$linha $p=$r"
done
echo "$linha"
