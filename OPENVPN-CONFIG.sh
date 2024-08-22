# OPEN VPN CONFIG 
sudo mkdir -p /etc/openvpn/client/
sudo cp /path/to/your/file.ovpn /etc/openvpn/client/
sudo mv /etc/openvpn/client/yourfile.ovpn /etc/openvpn/client/myvpn.ovpn
sudo nano /etc/systemd/system/openvpn-client@myvpn.service



[Unit]
Description=OpenVPN connection to %i
After=network.target

[Service]
ExecStart=/usr/sbin/openvpn --config /etc/openvpn/client/%i.ovpn
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target



sudo systemctl enable openvpn-client@myvpn.service
sudo systemctl start openvpn-client@myvpn.service
sudo systemctl status openvpn-client@myvpn.service
