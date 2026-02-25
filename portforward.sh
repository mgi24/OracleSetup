#this is only example!
sudo iptables -t nat -A PREROUTING -i enp0s6 -p tcp --dport 80 -j DNAT --to-destination 10.8.0.4:80
sudo netfilter-persistent save