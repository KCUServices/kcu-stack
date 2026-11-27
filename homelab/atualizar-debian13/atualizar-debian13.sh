#!/bin/bash
# Atualiza um container (LXC) do Proxmox de Debian 12 (bookworm) para Debian 13 (trixie).
# Ordem: backup (vzdump, snapshot) > cópia de /etc/apt > bookworm -> trixie em todos os repositórios
# > upgrade sem pacotes novos > full-upgrade > autoremove > reinício > verificação.
#
# Uso (no Proxmox, como root). Corre-o com systemd-run, para não morrer se o SSH cair a meio:
#   systemd-run --collect --unit=debian13-200 /root/atualizar-debian13.sh 200 [storage-do-backup]
#   journalctl -fu debian13-200          # acompanhar
# O storage do backup é "local" se não disseres outro. O registo fica também em /root/atualizar-debian13-<id>.log
set -euo pipefail

id=${1:-}; storage=${2:-local}
case "$id" in ''|*[!0-9]*) echo "Uso: $0 <ctid> [storage-do-backup]" >&2; exit 1 ;; esac
pct config "$id" >/dev/null 2>&1 || { echo "Não há nenhum container com o ID $id (este script é só para LXC)." >&2; exit 1; }

log=/root/atualizar-debian13-$id.log
exec > >(tee -a "$log") 2>&1

[ "$(pct status "$id")" = "status: running" ] || { echo "O CT $id tem de estar ligado."; exit 1; }
versao=$(pct exec "$id" -- cat /etc/debian_version)
case "$versao" in 12*) ;; *) echo "O CT $id tem Debian $versao, não 12. Nada a fazer."; exit 1 ;; esac
# Proxmox antigo recusa arrancar containers com Debian 13: o CT ficava parado depois do reinício.
grep -qE 'pve-manager/(8\.[4-9]|9|[1-9][0-9])' <<<"$(pveversion)" || { echo "Precisas do Proxmox VE 8.4 ou mais recente para correr Debian 13 em containers."; exit 1; }
cfg=$(pct config "$id")
if grep -q '^unprivileged: 1' <<<"$cfg" && ! grep -q 'nesting=1' <<<"$cfg"; then
  echo "Aviso: o CT $id não tem nesting=1; o systemd do Debian 13 precisa dele em containers sem privilégios (Options > Features > Nesting)."
fi

echo "== $(date +%T) CT $id: backup para o storage $storage"
vzdump "$id" --storage "$storage" --mode snapshot --compress zstd --notes-template "antes do Debian 13" 2>&1 | tail -3

echo "== $(date +%T) repositórios: bookworm -> trixie (cópia em /root/apt.antes-debian13 dentro do CT)"
pct exec "$id" -- sh -c '
  [ -e /root/apt.antes-debian13 ] || cp -a /etc/apt /root/apt.antes-debian13
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] && sed -i "s/bookworm/trixie/g" "$f"
  done
  grep -rhE "^(deb |Suites:)" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true'

echo "== $(date +%T) atualizar (pode demorar)"
# --force-confold: um ficheiro de configuração que TU alteraste fica como está.
pct exec "$id" -- env DEBIAN_FRONTEND=noninteractive sh -c '
  set -e
  O="-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef"
  apt-get update -q
  apt-get -y -q $O upgrade --without-new-pkgs
  apt-get -y -q $O full-upgrade
  apt-get -y -q autoremove --purge' 2>&1 \
  | { grep -v -E "^(Get|Hit|Ign|Preparing|Unpacking|Selecting|Setting up|Processing|\(Reading)" || true; }

echo "== $(date +%T) reiniciar"
pct reboot "$id"
ok=; for _ in $(seq 30); do pct exec "$id" -- true >/dev/null 2>&1 && { ok=1; break; }; sleep 2; done
[ -n "$ok" ] || { echo "O CT $id não voltou em 60 s: vê a consola e 'pct status $id'."; exit 1; }
sleep 10

echo "== $(date +%T) verificar"
pct exec "$id" -- sh -c '
  echo "Debian $(cat /etc/debian_version)"
  systemctl --failed --no-legend --plain | sed "s/^/FALHOU: /"
  echo "estado: $(systemctl is-system-running 2>/dev/null)"
  if [ -x /usr/sbin/sshd ]; then /usr/sbin/sshd -T 2>/dev/null | grep -Ei "^(passwordauthentication|permitrootlogin) " | sed "s/^/ssh: /"; fi
  if command -v docker >/dev/null 2>&1; then docker ps -a --format "docker: {{.Names}} {{.Status}}"; fi' || true
echo "== $(date +%T) FIM. Lê o README: confirma o SSH, o Docker e os pacotes que o autoremove tirou."
