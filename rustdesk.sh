#!/bin/bash
read -p "ENTER MACHINE PASSWORD"
sudo apt update 
sudo apt purge rustdesk -y
sudo apt autoclean -y
wget https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/main/rustdesk-1.2.1-aarch64.deb
sudo dpkg -i rustdesk-1.2.1-aarch64.deb
sudo apt --fix-broken install -y
sudo reboot  