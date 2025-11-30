Name:           ssh-ip-blocker
Version:        1.0
Release:        1%{?dist}
Summary:        Automatic SSH IP blocker for failed login attempts

License:        MIT
URL:            https://github.com/ATan0728/user-12-49.git
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  systemd
BuildRequires:  bash

# РАБОЧИЕ ЗАВИСИМОСТИ - будут требоваться при установке
Requires:       firewalld
Requires:       systemd
Requires:       bash
Requires:       grep
Requires:       awk
Requires:       coreutils
Requires:       iproute  # для работы с IP

# Рекомендуемые зависимости (не обязательные, но полезные)
Recommends:     logrotate
Recommends:     fail2ban  # дополнительная защита

%description
This tool automatically blocks IP addresses that have multiple failed
SSH login attempts to a specific user within a short time period.
It monitors /var/log/secure for failed authentication attempts and
automatically blocks suspicious IPs using firewalld.

%prep
%setup -q

%build
# No compilation needed for bash script

%install
# Create directories
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_unitdir}
mkdir -p %{buildroot}%{_sysconfdir}
mkdir -p %{buildroot}%{_datarootdir}/%{name}

# Install main script
install -m 755 ssh-ip-blocker.sh %{buildroot}%{_bindir}/ssh-ip-blocker

# Install systemd units
install -m 644 ssh-ip-blocker.service %{buildroot}%{_unitdir}/
install -m 644 ssh-ip-blocker.timer %{buildroot}%{_unitdir}/

# Install documentation
install -m 644 README.md %{buildroot}%{_datarootdir}/%{name}/

# Create config file
cat > %{buildroot}%{_sysconfdir}/ssh-ip-blocker.conf << 'CONFIGEOF'
# SSH IP Blocker Configuration
# Target user to monitor
USER="user-12-49"
# Number of failed attempts before blocking
ATTEMPTS_THRESHOLD=5
# Time window in minutes
TIME_WINDOW=10
# How long to block IP addresses (for temporary rules)
BAN_DURATION="24h"
# Log file to monitor
LOG_FILE="/var/log/secure"
CONFIGEOF

%pre
getent group ssh-blocker >/dev/null 2>&1 || groupadd -r ssh-blocker

%post
# Create log directory
mkdir -p /var/log/ssh-ip-blocker
chmod 755 /var/log/ssh-ip-blocker

# Reload systemd
systemctl daemon-reload >/dev/null 2>&1 || :

# Enable the timer
systemctl enable ssh-ip-blocker.timer >/dev/null 2>&1 || :

echo "===================================================================="
echo "SSH IP Blocker successfully installed!"
echo ""
echo "To start automatic blocking:"
echo "  systemctl start ssh-ip-blocker.timer"
echo ""
echo "Configuration file: /etc/ssh-ip-blocker.conf"
echo "Manual execution: ssh-ip-blocker"
echo "===================================================================="

%preun
if [ $1 -eq 0 ]; then
    # Package removal (not upgrade)
    systemctl stop ssh-ip-blocker.timer >/dev/null 2>&1 || :
    systemctl disable ssh-ip-blocker.timer >/dev/null 2>&1 || :
    systemctl stop ssh-ip-blocker.service >/dev/null 2>&1 || :
fi

%postun
if [ $1 -ge 1 ]; then
    # Package upgrade
    systemctl daemon-reload >/dev/null 2>&1 || :
    systemctl try-restart ssh-ip-blocker.timer >/dev/null 2>&1 || :
fi

%files
%doc %{_datarootdir}/%{name}/README.md
%{_bindir}/ssh-ip-blocker
%{_unitdir}/ssh-ip-blocker.service
%{_unitdir}/ssh-ip-blocker.timer
%config(noreplace) %{_sysconfdir}/ssh-ip-blocker.conf

%changelog
* Sat Nov 15 2025 ATan <> - 1.0-1
- Initial package build with firewalld dependency
- Added systemd timer for automatic execution
- Configurable thresholds and time windows
