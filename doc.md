sudo apt install -y build-essential dkms linux-headers-$(uname -r)

sudo nano /etc/gdm3/custom.conf
https://us.download.nvidia.com/XFree86/Linux-x86_64/580.119.02/NVIDIA-Linux-x86_64-580.119.02.run
Docker Permission

sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
