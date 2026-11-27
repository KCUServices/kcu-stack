# O que mudou

Cada versão fica ligada ao episódio em que foi mostrada.

## [Por lançar]: 2026-11-27

- **Firewall nos guests** (`homelab/firewall-guests`): um script para containers e VMs que liga a firewall do Proxmox com SSH só para quem administra, o resto da rede local como antes e o que vem de fora bloqueado. Guarda o `.fw` anterior, tem `--ensaio` e `--desfazer`, e um script para testar portas a partir de um container que não é admin.
- **Atualizar para o Debian 13** (`homelab/atualizar-debian13`): passa um container de bookworm para trixie com backup antes (e confirma que o Proxmox é 8.4 ou mais recente), repositórios externos incluídos, reinício e verificação no fim. O README tem o que verificar depois (SSH, Docker, pacotes retirados) e como desfazer.

## [ep00] Primeira versão pública: 2026-11-24

- Máquinas, Proxmox, IA local, apps do dia a dia e automáticos, tal como estão hoje.
- Pasta `homelab/` com dois modelos: a ponte Tailscale (nginx) e o backup semanal do Proxmox com aviso no Discord. No Proxmox entram a VM do Stremio, o MeTube e o RomM, com uma nota de uso legal.
