#!/bin/bash

# minta input nama user
read -p "Masukkan nama user baru: " USERNAME

# cek kalau kosong
if [ -z "$USERNAME" ]; then
  echo "Nama user tidak boleh kosong!"
  exit 1
fi

# tambah user baru
sudo adduser "$USERNAME"

# masukkan ke grup sudo
sudo usermod -aG sudo "$USERNAME"

# edit ssh config utama
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication no/' /etc/ssh/sshd_config

# edit cloudimg config jika ada
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
else
    echo "PasswordAuthentication yes" | sudo tee /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi

# restart ssh
sudo systemctl restart sshd

echo "DONE ✅"
echo "User $USERNAME sudah dibuat."
echo "Silakan test login SSH pakai password di terminal baru sebelum logout."