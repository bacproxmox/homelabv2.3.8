# Homelab v2.3.8

Proxmox tabanlı homelab otomasyon seti.

## İlk komut

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.3.8/main/bootstrap.sh)
```

## Ana hedefler

- Proxmox subscription/no-subscription bootstrap
- Merkezi secrets yapısı: `/root/homelab-secrets`
- Log yapısı: `/root/homelab-logs`
- State tracking: `/root/homelab-state`
- VM + service + config ayrımı
- Menü tabanlı kurulum
- Maintenance / repair / health check sistemi

## Ana menüler

```bash
bash menu/install-menu.sh
bash menu/config-menu.sh
bash menu/maintenance-menu.sh
```

## Fresh install runbook

Detaylı sıra için:

```bash
cat docs/RUNBOOK-FRESH-INSTALL.md
```

## Önemli mimari kararlar

- Docker network: `homelab`
- Stack root: `/opt/homelab`
- Container prefix: `hb-`
- VM106 docker-media: `32GB RAM / 512GB disk`
- VM107 chia-farmer: `16GB RAM / 320GB disk`
- Cloudflared-only reverse access
- Nextcloud domain: `cloud.bacmastercloud.com`, ama local IP redirect yapmayacak şekilde configlenecek
- Immich upload: `/mnt/photos/immich-upload` -> TrueNAS `/mnt/tank/photos/immich-upload`
