#!/usr/bin/env bash
# Automatická oprava UKI po obnově snapshotu Timeshiftu.
#
# Snapshot obsahuje jen podsvazek @ (s /boot/vmlinuz-* a /usr/lib/modules), UKI na ESP ne.
# Když se obnoví snapshot s jinou verzí jádra, nabootuje UKI z ESP jádro, ke kterému
# obnovený systém nemá moduly. Služba to při startu pozná (chybí /usr/lib/modules/$(uname -r)),
# přestaví UKI z obnoveného /boot (mkinitcpio -P) a restartuje. Za normálního startu se přeskočí.
# Pojistka proti smyčce: pro každou verzi jádra jen jeden pokus (/var/lib/uki-match-kernel/<verze>).
#
# Instalace: sudo bash pc/setup-uki-match-kernel.sh
# Log:       journalctl -u uki-match-kernel
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Spusť přes sudo."; exit 1; }

cat >/usr/local/bin/uki-match-kernel <<'EOF'
#!/usr/bin/env bash
# Přestaví UKI, když běžící jádro (z ESP) nemá moduly v systému — typicky po obnově snapshotu.
# Instaluje pc/setup-uki-match-kernel.sh (repozitář manjaro-setup-script), spouští uki-match-kernel.service.
set -euo pipefail
kver=$(uname -r)
marker=/var/lib/uki-match-kernel/$kver

[[ -d /usr/lib/modules/$kver ]] && { echo "Moduly pro $kver jsou, UKI sedí."; exit 0; }
[[ -e $marker ]] && { echo "Pro $kver už se přestavění zkoušelo ($marker), znovu ne."; exit 1; }

echo "Běžící jádro $kver nemá moduly → UKI na ESP nesedí k systému (obnovený snapshot?)."
echo "Jádra v systému: $(ls /usr/lib/modules | tr '\n' ' ')"
mkdir -p "${marker%/*}"
touch "$marker"
mkinitcpio -P
echo "UKI přestavěné, restartuju."
systemctl --no-block reboot
EOF
chmod 755 /usr/local/bin/uki-match-kernel

cat >/etc/systemd/system/uki-match-kernel.service <<'EOF'
[Unit]
Description=Přestavění UKI, když jádro na ESP nesedí k systému (po obnově snapshotu)
ConditionPathExists=!/usr/lib/modules/%v
RequiresMountsFor=/boot /boot/efi /var/lib
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/uki-match-kernel

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable uki-match-kernel.service
echo "-- ověření jednotky:"; systemd-analyze verify uki-match-kernel.service && echo "   OK"
echo "-- zkušební spuštění (má se přeskočit, moduly běžícího jádra existují):"
systemctl start uki-match-kernel.service
systemctl status uki-match-kernel.service --no-pager | sed -n "1,6p" || true
