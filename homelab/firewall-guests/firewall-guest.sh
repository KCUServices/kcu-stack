#!/bin/bash
# Firewall do Proxmox num container (LXC) ou numa VM: SSH só para quem administra,
# o resto da rede local entra como antes e o que vem de fora da rede local fica bloqueado.
# Descobre sozinho se o ID é de um container ou de uma VM.
#
# Uso (no Proxmox, como root):
#   firewall-guest.sh <id> --ensaio        mostra o .fw que ia escrever, sem mexer em nada
#   firewall-guest.sh <id> [--tailscale]   liga a firewall no guest (--tailscale abre a UDP 41641)
#   firewall-guest.sh <id> --desfazer      desliga a firewall do guest (enable: 0), sem apagar as regras
#
# Os teus valores (ADMINS, REDE4, REDE6) vêm de firewall-guests.conf, ao lado deste script,
# ou do ficheiro indicado na variável CONF. Copia o firewall-guests.conf.exemplo.
# Antes de mudar o .fw, guarda o anterior em /root/firewall-<id>.fw.antes-<data>.
set -euo pipefail

uso="Uso: $0 <id> [--tailscale] [--ensaio] | $0 <id> --desfazer"
id=${1:-}
case "$id" in ''|*[!0-9]*) echo "$uso" >&2; exit 1 ;; esac
shift
ts=""; ensaio=""; desfazer=""
for a in "$@"; do
  case "$a" in
    --tailscale) ts=1 ;;
    --ensaio) ensaio=1 ;;
    --desfazer) desfazer=1 ;;
    *) echo "Opção desconhecida: $a" >&2; echo "$uso" >&2; exit 1 ;;
  esac
done

# Container ou VM?
if pct config "$id" >/dev/null 2>&1; then tipo=CT; cmd=pct
elif qm config "$id" >/dev/null 2>&1; then tipo=VM; cmd=qm
else echo "Não há nenhum container nem VM com o ID $id." >&2; exit 1; fi

f=/etc/pve/firewall/$id.fw
copia=/root/firewall-$id.fw.antes-$(date +%Y%m%d-%H%M%S)

if [ -n "$desfazer" ]; then
  [ -f "$f" ] || { echo "$tipo $id não tem $f: nada a desfazer."; exit 0; }
  cp "$f" "$copia"
  sed -i 's/^enable: 1/enable: 0/' "$f"
  echo "$tipo $id: firewall desligada (enable: 0). Cópia do anterior: $copia"
  exit 0
fi

CONF=${CONF:-$(dirname "$(readlink -f "$0")")/firewall-guests.conf}
[ -r "$CONF" ] || { echo "Falta $CONF (copia o firewall-guests.conf.exemplo e põe os teus IPs)." >&2; exit 1; }
# shellcheck source=/dev/null
. "$CONF"
if [ -z "${ADMINS:-}" ] || [ -z "${REDE4:-}" ]; then
  echo "ADMINS e REDE4 têm de estar preenchidos em $CONF." >&2; exit 1
fi

gerar() {
  cat <<EOF
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT
dhcp: 1
ndp: 1

[IPSET admin] # quem pode entrar por SSH
EOF
  for ip in $ADMINS; do echo "$ip"; done
  cat <<EOF

[RULES]
IN ACCEPT -source +admin -p tcp -dport 22 # SSH só para quem administra
IN DROP -p tcp -dport 22
IN ACCEPT -source $REDE4 # rede local: o resto entra como antes
EOF
  for r in ${REDE6:-}; do echo "IN ACCEPT -source $r # rede local (IPv6)"; done
  echo "IN ACCEPT -source fe80::/10 # IPv6 link-local"
  if [ -n "$ts" ]; then echo "IN ACCEPT -p udp -dport 41641 # Tailscale: ligações diretas"; fi
}

if [ -n "$ensaio" ]; then
  echo "== $tipo $id: $f ficaria assim"
  gerar
  exit 0
fi

if ! grep -qs '^enable: 1' /etc/pve/firewall/cluster.fw; then
  echo "Aviso: a firewall do Datacenter está desligada. Sem ela, as regras dos guests não se aplicam (lê o README antes de a ligar)."
fi

if [ -f "$f" ]; then cp "$f" "$copia"; echo "Cópia do anterior: $copia"; fi
gerar > "$f"

# Liga firewall=1 em todas as placas de rede do guest (sem isso o .fw não tem efeito).
$cmd config "$id" | awk -F': ' '/^net[0-9]+:/{print $1, $2}' | while read -r nic val; do
  case "$val" in
    *firewall=1*) continue ;;
    *firewall=0*) novo=${val/firewall=0/firewall=1} ;;
    *) novo="$val,firewall=1" ;;
  esac
  $cmd set "$id" "-$nic" "$novo"
  echo "$nic: firewall=1"
done

sleep 4
echo "$tipo $id: firewall ligada. Testa já o SSH a partir de um PC admin e de um que não é (ver testar-portas.sh)."
