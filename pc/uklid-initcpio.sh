#!/usr/bin/env bash
# Jednorázový úklid: smaže obsah initramfs, který `lsinitcpio -x` omylem rozbalil do kořene repozitáře
# (2026-10-11 18.38, vše vlastní root). Maže jen tyhle položky a jen když patří rootovi.
set -euo pipefail
cd "$(dirname "$0")/.."
for f in VERSION bin buildconfig config dev early_cpio etc init init_functions kernel lib lib64 new_root proc run sbin sys sysroot tmp usr var; do
  [[ -e $f || -L $f ]] || continue
  [[ $(stat -c %U "$f") == root ]] || { echo "přeskakuji $f (nepatří rootovi)"; continue; }
  rm -rf -- "$f" && echo "smazáno $f"
done
