#!/bin/bash
#
# Uncrash agent install
#
# @version		1.0.0.0013
# @date			2018-07-30
# @copyright	(c) 2018 TimeInn
# @support		https://uncrash.net/
# 
# @inspired NodeQuery https://nodequery.com/

# Banner
echo -e "|\n|   Uncrash Installer\n|   ===================\n|"


# Install package
function packageInstall ()
{

	if [ -n "$(command -v apt-get)" ]
	then
		echo -e "|\n|   Notice: Installing required package '$1' via 'apt-get'"
		apt-get -y update
		apt-get -y install $1
	elif [ -n "$(command -v yum)" ]
	then
		echo -e "|\n|   Notice: Installing required package '$1' via 'yum'"
		yum -y install $1
	elif [ -n "$(command -v pacman)" ]
	then
		echo -e "|\n|   Notice: Installing required package '$1' via 'pacman'"
		pacman -S --noconfirm $1
	fi
}

function runService ()
{
	if [ -n "$(command -v systemctl)" ]
	then
		systemctl start $1
		systemctl enable $1
	elif [ -n "$(command -v service)"]
	then
		service $1 start
		if [ -n "$(command -v yum)" ]
		then
			chkconfig $1 on
		fi
	fi
}

packageInstall("wget")

# Required root
if [ $(id -u) != "0" ];
then
	echo -e "|   Error: You need to be root to install the Uncrash agent\n|"
	echo -e "|          The agent itself will NOT be running as root but instead under its own non-privileged user\n|"
	exit 1
fi

if [ $# -lt 1 ]
then
	echo -e "|   Usage: bash $0 'token'\n|"
	exit 1
fi

# Check if wget is installed
if [ ! -n "$(command -v crontab)" ]
then
	echo "|" && read -p "|   wget is required and could not be found. Do you want to install it? [Y/n] " input_variable_install

	# Attempt to install crontab
	if [ -z $input_variable_install ] || [ $input_variable_install == "Y" ] || [ $input_variable_install == "y" ]
	then
		packageInstall "wget"
	fi
fi

# Check if crontab is installed
if [ ! -n "$(command -v crontab)" ]
then

	# Confirm crontab installation
	echo "|" && read -p "|   Crontab is required and could not be found. Do you want to install it? [Y/n] " input_variable_install

	# Attempt to install crontab
	if [ -z $input_variable_install ] || [ $input_variable_install == "Y" ] || [ $input_variable_install == "y" ]
	then
		if [ -n "$(command -v apt-get)" ]
		then
			echo -e "|\n|   Notice: Installing required package 'cron' via 'apt-get'"
		    apt-get -y update
		    apt-get -y install cron
		elif [ -n "$(command -v yum)" ]
		then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'yum'"
		    yum -y install cronie
		    
		    if [ ! -n "$(command -v crontab)" ]
		    then
		    	echo -e "|\n|   Notice: Installing required package 'vixie-cron' via 'yum'"
		    	yum -y install vixie-cron
		    fi
		elif [ -n "$(command -v pacman)" ]
		then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'pacman'"
		    pacman -S --noconfirm cronie
		fi
	fi
	
	if [ ! -n "$(command -v crontab)" ]
	then
	    # Show error
	    echo -e "|\n|   Error: Crontab is required and could not be installed\n|"
	    exit 1
	fi	
fi

# Check if cron is running
if [ -z "$(ps -Al | grep cron | grep -v grep)" ]
then
	
	# Confirm cron service
	echo "|" && read -p "|   Cron is available but not running. Do you want to start it? [Y/n] " input_variable_service

	# Attempt to start cron
	if [ -z $input_variable_service ] || [ $input_variable_service == "Y" ] || [ $input_variable_service == "y" ]
	then
		if [ -n "$(command -v apt-get)" ]
		then
			echo -e "|\n|   Notice: Starting 'cron' via 'service'"
			service cron start
		elif [ -n "$(command -v yum)" ]
		then
			if [ -n "$(command -v systemctl)" ]
			then
				systemctl start crond
				systemctl enable crond
			else
				echo -e "|\n|   Notice: Starting 'crond' via 'service'"
				chkconfig crond on
				service crond start
			fi
		elif [ -n "$(command -v pacman)" ]
		then
			echo -e "|\n|   Notice: Starting 'cronie' via 'systemctl'"
		    systemctl start cronie
		    systemctl enable cronie
		fi
	fi
	
	# Check if cron was started
	if [ -z "$(ps -Al | grep cron | grep -v grep)" ]
	then
		# Show error
		echo -e "|\n|   Error: Cron is available but could not be started\n|"
		exit 1
	fi
fi

# Attempt to delete previous agent
if [ -f /etc/uncrash/agent.sh ]
then
	# Remove agent dir
	rm -Rf /etc/uncrash

	# Remove cron entry and user
	if id -u uncrash >/dev/null 2>&1
	then
		(crontab -u uncrash -l | grep -v "/etc/uncrash/agent.sh") | crontab -u uncrash - && userdel uncrash
	else
		(crontab -u root -l | grep -v "/etc/uncrash/agent.sh") | crontab -u root -
	fi
fi

# Create agent dir
mkdir -p /etc/uncrash
mkdir -p /var/uncrash

# Download agent
# curl -o cnmp.sh  && bash cnmp.sh
echo -e "|   Downloading agent.sh to /etc/uncrash\n|\n|   + $(wget -nv -o /dev/stdout -O /etc/uncrash/agent.sh --no-check-certificate https://raw.github.com/TimeInn/Uncrash-Agent/master/uncrash-agent.sh)"

if [ -f /etc/uncrash/agent.sh ]
then
	# Create auth file
	echo "$1" > /var/uncrash/auth.token
	
	# Create user
	useradd uncrash -r -d /etc/uncrash -s /bin/false
	
	# Modify user permissions
	chown -R uncrash:uncrash /etc/uncrash && chmod -R 700 /etc/uncrash
    chown -R uncrash:uncrash /var/uncrash && chmod -R 700 /var/uncrash
	
	# Modify ping permissions
	chmod +s `type -p ping`

	# Configure cron
	crontab -u uncrash -l 2>/dev/null | { cat; echo "*/3 * * * * bash /etc/uncrash/agent.sh > /var/uncrash/cron.log 2>&1"; } | crontab -u uncrash -
	
	# Show success
	echo -e "|\n|   Success: The Uncrash Agent has been installed\n|"
	
	# Attempt to delete installation script
	if [ -f $0 ]
	then
		rm -f $0
	fi
else
	# Show error
	echo -e "|\n|   Error: The Uncrash agent could not be installed\n|"
fi
