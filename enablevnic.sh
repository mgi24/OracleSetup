#!/bin/bash

echo "=== OCI 2nd VNIC Setup ==="

# 1. input local IP
read -p "INPUT LOCAL IP FROM ORACLE (contoh 10.0.0.48): " LOCAL_IP

if [ -z "$LOCAL_IP" ]; then
  echo "IP tidak boleh kosong!"
  exit 1
fi

# ambil subnet otomatis (contoh 10.0.0.0/24)
SUBNET=$(echo $LOCAL_IP | awk -F. '{print $1"."$2"."$3".0/24"}')
GATEWAY=$(echo $LOCAL_IP | awk -F. '{print $1"."$2"."$3".1"}')

# 2. show ip a
echo ""
echo "=== AVAILABLE ADAPTERS ==="
ip a
echo ""

# 3. pilih adapter
read -p "SELECT NEW ADAPTER (contoh enp1s0): " IFACE

if [ -z "$IFACE" ]; then
  echo "Adapter tidak boleh kosong!"
  exit 1
fi

# 4. up adapter + set ip
sudo ip link set $IFACE up
sudo ip addr add ${LOCAL_IP}/24 dev $IFACE

echo "Adapter $IFACE UP dengan IP $LOCAL_IP"

# 5. edit rt_tables (add kalau belum ada)
if ! grep -q "100 vnic1" /etc/iproute2/rt_tables; then
    echo "100 vnic1" | sudo tee -a /etc/iproute2/rt_tables
fi

# 6. tambah route & rule (hindari duplicate)
sudo ip route add $SUBNET dev $IFACE src $LOCAL_IP table vnic1 2>/dev/null
sudo ip route add default via $GATEWAY dev $IFACE table vnic1 2>/dev/null

sudo ip rule add from $LOCAL_IP table vnic1 2>/dev/null
sudo ip rule add to $LOCAL_IP table vnic1 2>/dev/null

sudo ip route flush cache

echo "Policy routing applied."

# 7. buat systemd service supaya auto start saat boot
SERVICE_FILE="/etc/systemd/system/vnic1-routing.service"

sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=OCI VNIC1 Routing
After=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set $IFACE up
ExecStart=/sbin/ip addr add ${LOCAL_IP}/24 dev $IFACE
ExecStart=/sbin/ip route add $SUBNET dev $IFACE src $LOCAL_IP table vnic1
ExecStart=/sbin/ip route add default via $GATEWAY dev $IFACE table vnic1
ExecStart=/sbin/ip rule add from $LOCAL_IP table vnic1
ExecStart=/sbin/ip rule add to $LOCAL_IP table vnic1
ExecStart=/sbin/ip route flush cache
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vnic1-routing.service

echo ""
echo "DONE ✅"
echo "Routing akan otomatis aktif setelah reboot."