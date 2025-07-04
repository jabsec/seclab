#!/bin/bash

SECLAB_PATH="$HOME/seclab"
VSCODE_URL='https://update.code.visualstudio.com/latest/linux-deb-x64/stable'
VIVALDI_URL='https://downloads.vivaldi.com/stable/vivaldi-stable_7.4.3684.46-1_amd64.deb'
KPXC_DB_PATH="$SECLAB_PATH/seclab.kdbx"
PKI_PATH="$SECLAB_PATH/pki"
PKI_DOMAIN="sec.lab"
PKI_ISO_DOMAIN="iso.sec.lab"
PW_LENGTH=32

install_tools() {
	echo "[+] Installing baseline tools"
	sudo apt update
	sudo apt install -y \
		expect \
		tmux \
		vim-gtk3 \
		terminator \
		krdc \
		fish \
		openssh-server \
		sshpass \
		wireshark \
		fonts-liberation \
		xrdp \
		genisoimage \
		keepassxc \
		python3-pip \
		python3-pykeepass \
		pipx \
		easy-rsa \
		caddy
}

install_vscode() {
	echo "[?] Install Visual Studio Code [y/N]? "
	read vscode_confirm
	if [[ $vscode_confirm == "y" ]] || [[ $vscode_confirm == "Y" ]]; then
		echo "[+] Installing Visual Studio Code"
		wget -O code.deb $VSCODE_URL
		sudo dpkg -i code.deb
		rm code.deb
	fi
}

install_vivaldi() {
	echo "[?] Install Vivaldi Browser [y/N]? "
	read vivaldi_confirm
	if [[ $vivaldi_confirm == "y" ]] || [[ $vivaldi_confirm == "Y" ]]; then
		echo "[+] Installing Vivaldi"
		wget -O vivaldi.deb $VIVALDI_URL
		sudo dpkg -i vivaldi.deb
		sudo apt --fix-broken install -y
		rm vivaldi.deb
	fi
}

install_hashicorp() {
	echo "[+] Setting up Hashicorp Repository"
	wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
	sudo apt update
	echo "[+] Installing Hashicorp Tools"
	sudo apt install -y packer terraform
	echo "[+] Installing/Fixing Keepass plugin"
	packer plugin install github.com/chunqi/keepass
	pushd ~/.config/packer/plugins/github.com/chunqi/keepass
	for f in $(ls); do
		mv $f $(echo $f | sed "s/_5/_x5/")
	done
	popd
}

install_ansible() {
	echo "[+] Installing Ansible"
	pipx install --include-deps ansible
	pipx runpip ansible install pykeepass
	echo "[+] Installing Ansible Galaxy Plugins"
  ansible-galaxy collection install \
  	community.docker \
  	viczem.keepass \
  	community.windows \
  	community.general \
  	microsoft.ad
	ansible-galaxy role install geerlingguy.mysql
}

install_nerdfont() {
	echo "[+] Installing NerdFont"
	wget -O /tmp/scp.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/SourceCodePro.zip
	unzip /tmp/scp.zip -d /tmp/scp '*.ttf'
	sudo mkdir /usr/share/fonts/saucecode-pro
	sudo mv /tmp/scp/*.ttf /usr/share/fonts/saucecode-pro
	rm -rf /tmp/scp
	sudo fc-cache -s -f
}

install_fish() {
	printf "[?] Do you want to configure fish as your default shell [Y/n]? "
	read fish_confirm
	if [[ $fish_confirm == "" ]] || [[ $fish_confirm == "Y" ]] || [[ $fish_confirm == "y" ]]; then
		echo "[!] This is going to kick you into a fish shell. Type 'exit' to close it and continue installation. The final step will mess up this terminal session. Once it's finished, close it and open a new one."
		echo "[!] To enter Fish automatically, log out and back in."
		chsh -s /usr/bin/fish
		install_nerdfont
		echo "[+] Configuring Terminator"
		cp ./terminatorconfig ~/.config/terminator/config
		echo "[+] Configuring Fish"
		# Starship
		curl -sS https://starship.rs/install.sh | sh
		mkdir ~/.config/fish
		echo "starship init fish | source" >~/.config/fish/config.fish
		cp ./fish_variables/.config/fish
		echo "[+] Configuring Starship"
		cp ./starship.toml ~/.config/starship.toml
		# OMF
		# curl -kL https://get.oh-my.fish | fish
		# fish -c "omf install bobthefish && exit"
	fi
}

initialize_keepassxc() {
	echo "[+] Setting Up KeePassXC Database"
	echo "[+] You will be asked to set your database password."
	echo "[!] DO NOT LOSE THIS; it will not be stored for you."
	echo "[+] Database will be stored at $KPXC_DB_PATH"
	keepassxc-cli db-create -p $KPXC_DB_PATH
	echo "[+] Creating Seclab group to Database; password required"
	keepassxc-cli mkdir $KPXC_DB_PATH Seclab
}

create_creds() {

	create_ssh_key() {
		echo "[+] Creating Lab Credentials"
		if [ ! -f ~/.ssh/id_ed25519.pub ]; then
			echo "[+] Generating SSH Key"
			ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
		else
			echo "[!] SSH Key exists!"
		fi
	}
	get_proxmox_api_id() {
		printf "[?] Enter the Proxmox API Token ID: "
		read proxmox_api_id
	}
	get_seclab_user() {
		printf "[?] Enter the default lab username: "
		read seclab_user
	}

	create_ssh_key
	get_seclab_user

	echo "[+] Setting secrets in KPXC database"
	echo "[!] You will be asked for your database password several times"
 	USER_HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
 	echo "[+] Setting Proxmox API Credentials"
	get_proxmox_api_id
	echo "[+] When asked for the new entry password, enter your Proxmox API Token Secret"
 	keepassxc-cli add -p -u $proxmox_api_id $KPXC_DB_PATH Seclab/proxmox_api
 	echo "[+] Setting Seclab user"
 	keepassxc-cli add -g -L $PW_LENGTH -lUns -u $seclab_user $KPXC_DB_PATH Seclab/seclab_user
 	echo "[+] Setting Seclab Windows user"
 	keepassxc-cli add -g -L $PW_LENGTH -lUns -u $seclab_user $KPXC_DB_PATH Seclab/seclab_windows
 	echo "[+] Setting Seclab Windows domain admin"
 	keepassxc-cli add -g -L $PW_LENGTH -lUns -u $seclab_user $KPXC_DB_PATH Seclab/seclab_windows_da
 	# SSH Key add
	ssh_privkey=$(cat ~/.ssh/id_ed25519 | base64 -w 0)
	ssh_pubkey=$(cat ~/.ssh/id_ed25519.pub | base64 -w 0)
	echo -n "Enter password to unlock $KPXC_DB_PATH: "
	read -s kpxc_pass
	expect << EOF
spawn keepassxc-cli add -u $ssh_pubkey -p "$KPXC_DB_PATH" Seclab/seclab_ssh_key
expect "Enter password to unlock $KPXC_DB_PATH:"
send {$kpxc_pass}
send "\n"
expect "Enter password for new entry:"
send "$ssh_privkey\n"
expect eof
EOF
 	
 	echo "[+] Secrets generated. You can change them using KeePassXC and your database password."
 	echo "[!] Make sure you change secrets BEFORE running init-cloud-init.sh!"

}

initialize_pki() {
	echo "[+] Initializing PKI"
	echo "[+] Linking easyrsa"
	sudo ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin/easyrsa
	echo "[+] Setting up PKI"
	pushd $SECLAB_PATH
	easyrsa init-pki
	cat <<EOF > pki/vars
set_var EASYRSA_DN "cn_only"
EOF
	easyrsa build-ca
	popd
}

initialize_caddy() {
	echo "[+] Initializing PKI Server"
	cat <<EOF | sudo tee /etc/caddy/Caddyfile 1>/dev/null
{
	pki {
		ca seclab {
			intermediate_cn "Seclab Caddy Intermediate"
			root {
				format pem_file
				cert /etc/caddy/ca.crt
				key /etc/caddy/ca.key
			}
		}
	}

  log default {
	  output file /var/log/caddy/caddy.json
    format json
  }
}

https://ca.$PKI_DOMAIN {

	tls {
		issuer internal {
			ca seclab
		}
	}

	acme_server {
		ca seclab
	}

}

https://ca.$PKI_ISO_DOMAIN {

	tls {
		issuer internal {
			ca seclab
		}
	}

	acme_server {
		ca seclab
	}

}
EOF
  echo "[+] Installing CA certificate for Caddy"
  sudo cp $PKI_PATH/ca.crt /etc/caddy/ca.crt
  openssl rsa -in $PKI_PATH/private/ca.key | sudo tee /etc/caddy/ca.key
  sudo chown caddy: /etc/caddy/ca.*
  echo "[+] Enabling/Starting Caddy Server"
  sudo mkdir /var/log/caddy
  sudo chown caddy: /var/log/caddy
  sudo systemctl enable caddy.service
  sudo systemctl restart caddy.service
		
}

append_rcs() {
	echo "export PATH=$PATH:~/.local/bin:$SECLAB_PATH/Scripts" >>~/.bashrc
	echo "export KEEPASS_DATABASE=$KPXC_DB_PATH" >>~/.bashrc
	if [[ $fish_confirm == "" ]] || [[ $fish_confirm == "Y" ]] || [[ $fish_confirm == "y" ]]; then
		mkdir ~/.config/fish
		echo "set -x PATH $PATH ~/.local/bin $SECLAB_PATH/Scripts" >> ~/.config/fish/config.fish
		echo "set -x KEEPASS_DATABASE $KPXC_DB_PATH" >> ~/.config/fish/config.fish
	fi
	source ~/.bashrc
}

echo "                                                                                          
     █████████████ ████████████   ████████████ █████            ███████    █████████████  
    ██████████████ ████████████ ██████████████ ████            ████████    ██████████████ 
                                                                                          
    ████████████  ████████████  ████          █████          █████ ████   █████████████   
           ██████ █████        █████          ████          █████  █████ █████    █████   
   █████████████ █████████████ █████████████  ████████████ █████████████ ██████████████   
  █████████████  ████████████  █████████████ █████████████ ████    █████ █████████████    
                                                                                          "

echo "This script will install dependencies for Seclab Jumpbox."
printf "Continue [Y/n]? "
read confirm

if [[ $confirm == "" ]] || [[ $confirm == "Y" ]]; then
	echo "[+] Beginning installation"
	install_tools
	install_vscode
	install_vivaldi
	install_hashicorp
	install_ansible
	initialize_keepassxc
	create_creds
	install_fish
	initialize_pki
	initialize_caddy
	append_rcs
	echo "[+] Setup finished!"
else
	exit 0
fi
