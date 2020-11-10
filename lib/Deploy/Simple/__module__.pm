package Deploy::Simple;

use Rex -feature => ['1.4'];
use Rex::Commands::PkgConf;
use Data::Dumper;


desc "Deploy Debian/Ubuntu server";
task "deploy_srv", sub {
  my $hostname = shift->{hostname};
  say "Simple server deployment.";
  say "! Enable internet on the destination server.";
  my %i = get_system_information();
  say "Started on: $i{hostname}, $i{operating_system} system (arch: $i{architecture}), version: $i{operating_system_release}.";
  if (operating_system_is('Debian')) {
    #say operating_system_version();
    die "Unsupported DEBIAN version\n" if operating_system_version() < 10;
  } elsif (operating_system_is('Ubuntu')) {
    #say operating_system_version();
    die "Unsupported UBUNTU version\n" if operating_system_version() < 1804;
  } else {
    die "Unsupported operating system.\n";
  }

  if (is_installed('lvm2')) {
    # print lvm structure jfyi
    say "LVM configuration is:";
    my $v = run "pvs";
    say "*** PV-s:"; say $v;
    $v = run "vgs";
    say "*** VG-s:"; say $v;
    $v = run "lvs";
    say "*** LV-s:"; say $v;
  } else {
    say "LVM2 is not installed.";
  }


  # install packages
  my $packages = case operating_system, {
    qr{debian}i => ['debconf', 'debconf-utils', 'sudo', 'nftables', 'ulogd2', 'aptitude', 'unattended-upgrades', 'mc', 'nagios-nrpe-server'],
    qr{ubuntu}i => ['debconf', 'debconf-utils', 'sudo', 'nftables', 'ulogd2', 'aptitude', 'unattended-upgrades', 'mc', 'nagios-nrpe-server'],
  };
  my $packages_rm = case operating_system, {
    qr{debian}i => ['ufw', 'mlocate'],
    qr{ubuntu}i => ['ufw', 'mlocate'],
  };
  say "Updating package database... Wait...";
  update_package_db;
  say "Updating system... Wait patiently (it depends on internet speed)...";
  update_system
    on_change => sub {
      my (@modified_packages) = @_;
      for my $pkg (@modified_packages) {
        say "$pkg->{action} package $pkg->{name} $pkg->{version}";
      }
    };
  say "Installing packages...";
  pkg $packages, ensure => 'present';
  pkg $packages_rm, ensure => 'absent';

  my $open_vm_tools_installed = is_installed('open-vm-tools');

  # set hostname
  if ($hostname) {
    say "Changing hostname to $hostname...";
    file '/etc/hostname',
      owner => 'root',
      group => 'root',
      mode => 644,
      content => "$hostname\n",
      on_change => sub {
        say "/etc/hostname is updated.";
      };
    my $domain = get(cmdb('deploy_domain'));
    my $l = ($domain) ? "$hostname.$domain	$hostname" : $hostname;
    append_or_amend_line '/etc/hosts',
      line => "127.0.1.1	$l",
      regexp => qr/^\s*127.0.1.1/;
  }


  # switch to textmode
  my $grub_cfg = '/etc/default/grub';
  my $f = 0;
  append_or_amend_line $grub_cfg,
    line => "GRUB_CMDLINE_LINUX_DEFAULT=\"nomodeset\"",
    regexp => qr/^\s*GRUB_CMDLINE_LINUX_DEFAULT/,
    on_change => sub { $f = 1 };
  append_or_amend_line $grub_cfg,
    line => "GRUB_TERMINAL=console",
    regexp => qr/^\s*GRUB_TERMINAL/,
    on_change => sub { $f = 1 };
  append_or_amend_line $grub_cfg,
    line => "GRUB_DISABLE_OS_PROBER=true",
    regexp => qr/^\s*GRUB_DISABLE_OS_PROBER/,
    on_change => sub { $f = 1 };
  append_or_amend_line $grub_cfg,
    line => "GRUB_GFXPAYLOAD_LINUX=text",
    regexp => qr/^\s*GRUB_GFXPAYLOAD_LINUX/,
    on_change => sub { $f = 1 };
    
  if ($f) { 
    say "Updating grub...";
    run "update-grub";
    say "Textmode: grub configuration updated."
  };

  # configure timezone
  if (is_installed('tzdata')) {
    say "Configuring timezone...";
    set_pkgconf('tzdata', [
      {question=>'tzdata/Zones/Etc', type=>'select', value=>'UTC'},
      {question=>'tzdata/Zones/Asia', type=>'select', value=>'Yekaterinburg'},
      {question=>'tzdata/Areas', type=>'select', value=>'Asia'},
    ]);
    #my %opt = get_pkgconf('tzdata'); say Dumper \%opt;
    file '/etc/localtime', ensure=>'absent';
    file '/etc/timezone', ensure=>'absent';
    run 'dpkg-reconfigure -f noninteractive tzdata';

  } else {
    say "WARNING: tzdata is not installed! No timezone set.";
  }

  # time sync
  append_or_amend_line "/etc/systemd/timesyncd.conf",
    line => "NTP=10.15.0.1",
    regexp => qr/^\s*NTP/,
    on_change => sub {
      say "Time syncronization: /etc/systemd/timesyncd.conf updated."
    };

  # locale
  if (is_installed('locales')) {
    say "Configuring locale...";
    set_pkgconf('locales', [
      {question=>'locales/locales_to_be_generated', type=>'miltiselect', value=>'en_US.UTF-8 UTF-8, ru_RU.UTF-8 UTF-8'},
      {question=>'locales/default_environment_locale', type=>'select', value=>'ru_RU.UTF-8'},
    ]);
    #my %opt = get_pkgconf('locales'); say Dumper \%opt;
    run 'dpkg-reconfigure -f noninteractive locales';

  } else {
    say "WARNING: locales is not installed! No locale is configured.";
  }

  # keyboard
  if (is_installed('keyboard-configuration')) {
    say "Configuring keyboard...";
    my $xkboptions = 'grp:caps_toggle,grp_led:scroll';
    #my $xkboptions = 'grp:alt_shift_toggle,grp_led:scroll';
    set_pkgconf('keyboard-configuration', [
      {question=>'keyboard-configuration/model', type=>'select', value=>'Обычный ПК с 105-клавишной (межд.)'},
      {question=>'keyboard-configuration/modelcode', type=>'string', value=>'pc105'},
      {question=>'keyboard-configuration/layout', type=>'select', value=>'Русская'},
      {question=>'keyboard-configuration/layoutcode', type=>'string', value=>'us,ru'},
      {question=>'keyboard-configuration/variant', type=>'select', value=>'Русская'},
      {question=>'keyboard-configuration/variantcode', type=>'string', value=>','},
      {question=>'keyboard-configuration/toggle', type=>'select', value=>'Caps Lock'},
      #{question=>'keyboard-configuration/toggle', type=>'select', value=>'Alt+Shift'},
      {question=>'keyboard-configuration/switch', type=>'select', value=>'No temporary switch'},
      {question=>'keyboard-configuration/compose', type=>'select', value=>'No compose key'},
      {question=>'keyboard-configuration/altgr', type=>'select', value=>'The default for the keyboard layout'},
      {question=>'keyboard-configuration/optionscode', type=>'string', value=>$xkboptions},
      {question=>'keyboard-configuration/ctrl_alt_bksp', type=>'boolean', value=>'false'},
      {question=>'console-setup/ask_detect', type=>'boolean', value=>'false'},
      #{question=>'keyboard-configuration/unsupported_layout', type=>'boolean', value=>'false'},
      #{question=>'keyboard-configuration/unsupported_config_layout', type=>'boolean', value=>'false'},
      #{question=>'keyboard-configuration/unsupported_options', type=>'boolean', value=>'false'},
      #{question=>'keyboard-configuration/unsupported_config_options', type=>'boolean', value=>'false'},
    ]);
    #my %opt = get_pkgconf('keyboard-configuration'); say Dumper \%opt;
    file '/etc/default/keyboard', ensure=>'absent';
    run 'dpkg-reconfigure -f noninteractive keyboard-configuration';
    # fix improper XKBOPTIONS
    append_or_amend_line '/etc/default/keyboard',
      line => "XKBOPTIONS=\"$xkboptions\"",
      regexp => qr/^\s*XKBOPTIONS/;
    # setupcon is run on console-setup part
  } else {
    say "WARNING: keyboard-configuration is not installed! No keyboard is configured.";
  }

  # fonts
  if (is_installed('console-setup')) {
    say "Configuring console...";
    my $fontface = 'Terminus';
    my $charmap = 'UTF-8';
    my $consetup_version = 47; # valid for ubuntu1804,2004, debian10
    set_pkgconf('console-setup', [
      {question=>"console-setup/charmap$consetup_version", type=>'select', value=>$charmap},
      {question=>"console-setup/codeset$consetup_version", type=>'select', value=>'Guess optimal character set'},
      {question=>'console-setup/codesetcode', type=>'string', value=>'guess'},
      {question=>"console-setup/fontface$consetup_version", type=>'select', value=>$fontface},
      {question=>"console-setup/fontsize-fb$consetup_version", type=>'select', value=>'8x16'},
      {question=>"console-setup/fontsize-text$consetup_version", type=>'select', value=>'8x16'},
      {question=>'console-setup/fontsize', type=>'string', value=>'8x16'},
    ]);
    #my %opt = get_pkgconf('console-setup'); say Dumper \%opt;
    file '/etc/default/console-setup', ensure=>'absent';
    run 'dpkg-reconfigure -f noninteractive console-setup';
    # fix improper CHARMAP in Debian
    append_or_amend_line '/etc/default/console-setup',
      line => "CHARMAP=\"$charmap\"",
      regexp => qr/^\s*CHARMAP/;
    # fix improper FONTFACE
    append_or_amend_line '/etc/default/console-setup',
      line => "FONTFACE=\"$fontface\"",
      regexp => qr/^\s*FONTFACE/;
    # activate
    run 'setupcon';

  } else {
    say "WARNING: console-setup is not installed! No console is configured.";
  }


  # unattended-upgrades
  if (is_installed('unattended-upgrades')) {
    say "Disabling unattended-upgrades...";
    #set_pkgconf('unattended-upgrades', [
    #  {question=>"unattended-upgrades/enable_auto_updates", type=>'boolean', value=>'false'},
    #]);
    #my %opt = get_pkgconf('unattended-upgrades'); say Dumper \%opt;
    #run 'dpkg-reconfigure -f noninteractive unattended-upgrades';
    file '/etc/apt/apt.conf.d/20auto-upgrades',
      owner => 'root',
      group => 'root',
      mode => 644,
      source => 'files/20auto-upgrades-disabled';
  } else {
    say "WARNING: unattended-upgrades is not installed!";
  }


  # user configuration
  for ('ural', 'av') {
    say "Configuring user: $_. Use passwd for the new user to assign password and enable it.";
    Deploy::Simple::add_admin_user( {user => $_} );
  }

  # sudo for me
  append_or_amend_line '/etc/sudoers',
    line => "ural	ALL=(ALL:ALL) NOPASSWD: ALL",
    regexp => qr/^ural\s+ALL=/;

  # rundeck key for root
  my %u = get_user('root');
  my $home = $u{home};
  unless (is_dir("$home")) {
    die "$home directory is not found. Something get wrong.";
  }
  file "$home/.ssh/authorized_keys",
    source => get(cmdb('public_key')),
    mode => 600,
    owner => 'root',
    on_change => sub { 
      say "Rundeck key is installed to $home/.ssh/authorized_keys.";
    };


  # setup network
  my $net = $i{Network};
  #say Dumper $net;
  my $conf_iface = {
      #dev => '',
      ip => get(cmdb('deploy_ip')),
      ip6 => get(cmdb('deploy_ip6')),
      gateway => get(cmdb('deploy_gateway')),
      gateway6 => get(cmdb('deploy_gateway6')),
      domain => get(cmdb('deploy_domain')),
      dns_servers => get(cmdb('deploy_dns_servers')),
  };
  foreach my $dev (sort @{$net->{networkdevices}}) {
    $dev eq 'lo' && next;
    my $net_c = $net->{networkconfiguration};
    my $net_c_dev = $net_c->{$dev};
    $net_c_dev->{is_bridge} && next;
    if ($dev =~ m/^en/ && $net_c_dev->{ip}) {
      say "selected iface $dev, ip:$net_c_dev->{ip}, netmask:$net_c_dev->{netmask}";
      $conf_iface->{dev} = $dev;
      last;
    }
  }
  if ($conf_iface->{dev}) {
    if (operating_system_is('Ubuntu')) {
      say "Creating network template for $conf_iface->{dev}.";
      file '/etc/netplan/99-config.yaml',
	owner => 'root',
	group => 'root',
	mode => 644,
	content => template('files/netplan.yaml.tpl', iface => $conf_iface),
	on_change => sub {
	  say "/etc/netplan/99-config.yaml template is updated.";
	};
      say "Network template /etc/netplan/99-config.yaml is created with IP address: $conf_iface->{ip}.";
      say "Review template manually, uncomment, comment settings in other files.";

    } elsif(operating_system_is('Debian')) {
      say "Adding configuration to /etc/network/interfaces.new.";
      file '/etc/network/interfaces.new',
	owner => 'root',
	group => 'root',
	mode => 644,
	content => template('files/interfaces.tpl', iface => $conf_iface),
	on_change => sub {
	  say "/etc/network/interfaces.new template is updated.";
	};
      file '/etc/resolv.conf.new',
	owner => 'root',
	group => 'root',
	mode => 644,
	content => template('files/resolv.conf.tpl', iface => $conf_iface),
	on_change => sub {
	  say "/etc/resolv.conf.new template is updated.";
	};
      say "Network settings are added to the /etc/network/interfaces.new. IP address is: $conf_iface->{ip}.";
      say "Review interfaces.new/resolv.conf.new files manually.";

    } else {
      die "Unsupported operating system!\n";
    }
  } else {
    say "Network physical interface wasn't found! No network configuration is performed."
  }


  # nftables config
  file "/etc/nftables.conf",
    owner => 'root',
    group => 'root',
    mode => 755,
    source => 'files/nftables.conf',
    on_change => sub {
      say "/etc/nftables.conf is updated. Firewall will be active after reboot.";
    };
  # switch to iptables-nft on ubuntu 20
  if (operating_system_is('Ubuntu') && operating_system_version() > 1904) {
    run 'update-alternatives --set iptables /usr/sbin/iptables-nft; update-alternatives --set ip6tables /usr/sbin/ip6tables-nft';
  }
  run "systemctl enable nftables";

  # bacula client
  %u = get_user('ural');
  $home = $u{home};
  unless (is_dir("$home")) {
    die "$home directory is not found. Something get wrong.";
  }
  file "$home/bacula-client-uwc.deb",
    owner => 'ural',
    source => 'files/bacula-client-uwc.deb';
  run "dpkg -i $home/bacula-client-uwc.deb";

  # keep a copy nftables.conf
  file "$home/nftables.conf",
    mode => 755,
    owner => 'ural',
    source => 'files/nftables.conf';

  # nrpe
  file '/etc/nagios/nrpe.cfg',
    owner => 'root',
    group => 'root',
    mode => 644,
    source => 'files/nrpe.cfg';
  file '/etc/nagios/nrpe_local.cfg',
    owner => 'root',
    group => 'root',
    mode => 644,
    source => 'files/nrpe_local.cfg';
  # https://github.com/kiranos/check_vg_size
  file '/usr/lib/nagios/plugins/check_vg_size',
    owner => 'root',
    group => 'root',
    mode => 755,
    source => 'files/check_vg_size';


  # cleaning
  file '/etc/cron.d/popularity-contest', ensure=>'absent';
  file '/etc/cron.daily/popularity-contest', ensure=>'absent';
  say "Cleaning apt cache...";
  run "apt clean";

  # recreate openssh host keys
  run 'rm /etc/ssh/ssh_host_*;dpkg-reconfigure -f noninteractive openssh-server';
  say "OpenSSH host keys recreated. May require cleaning known_hosts files!";
  delete_lines_according_to qr/^\s*PermitRootLogin\s+yes/i, '/etc/ssh/sshd_config';

  # done
  say "\nBasic server is configured.";
  say "Things to check:";
  say "- Change root password (passwd root)." if operating_system_is('Debian');
  say "- Expand root filesystem partition if needed.";
  say "- Set hostname in /etc/hostname and /etc/hosts." unless $hostname;
  say "- Install open-vm-tools if necessary." unless $open_vm_tools_installed;
  say "- Review and activate network configuration in the /etc/netplan/99-config.yaml." if operating_system_is('Ubuntu');
  say "- Review and activate network configuration in the /etc/network/interfaces.new and /etc/resolv.conf.new." if operating_system_is('Debian');
  say '';

  return 0;
};


desc "Add administrative user account (hidden)";
# --user=testuser parameter required
task "add_admin_user", sub {
  my $login = shift->{user};
  die 'User login parameter is required!' unless $login;

  my $user_exists = 1;
  $user_exists = 0 unless (grep { $_ eq $login } user_list);

  my %opts = (
    ensure => 'present',
    comment => "$login (local admin)",
    home => "/home/$login",
    create_home => TRUE,
    groups => ['users'],
    shell => '/bin/bash'
  );

  # groups
  $opts{groups} = case operating_system, {
    qr{debian}i => ['users', 'adm', 'sudo', 'cdrom', 'floppy', 'audio', 'video', 'dip', 'plugdev', 'netdev'],
    qr{ubuntu}i => ['users', 'adm', 'sudo', 'cdrom', 'dip', 'plugdev'],
  };

  # new users are disabled
  $opts{crypt_password} = '!' unless $user_exists;

  $opts{ssh_key} = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDb+Mda8fgl4HZof1s4AZUFDsw2m72Z+/W3ix3djxClw2v6+WBdwFjQ+ZwLObWX9drVPn/QNPbEJkZ5qo5kA2NGA8xBhInvCnfZ++23+c+4Weoyx9wAVTVadQpNMl15hXbe+x0AdhB4HAFGc909OFiuF6aokZdVu/ICcadcNVRTn0syH14//sizbg1WLHCMR8XK9A3sWJDlz2mxOi5FEB7kaAeWo3YTEbk+ZL1QDC4i2czNGmQkMD22geeAPgh6Aiw8tXG8IlfliK2Csf2zSTVPhxz4Z086X6JYUJPN8/RwOGgXVapqwsPb5rJ+n/QlyIA0d4kITVvX1UoEBGfDBT+P sv@wispa' if $login eq 'ural';

  account $login, %opts;

  return 0;
}, {dont_register => TRUE};


1;

=pod

=encoding utf-8

=head1 NAME

$::Deploy::Simple - deploy simple Debian/Ubuntu server.

=head1 DESCRIPTION

Настройка самого общего Debian/Ubuntu сервера.

=head1 USAGE

Устанавливаем сервер 10.14.73.27.
  rex -u root -H 10.14.73.27 Deploy:Simple:deploy_srv
Устанавливаем сервер 10.14.73.27 с именем testserver.
  rex -u root -H 10.14.73.27 Deploy:Simple:deploy_srv --hostname=testserver

На сервере должен быть интернет!

=head1 TASKS

=over 4

=item deploy_srv [--hostname=testserver]

Simple server deployment. Sets hostname if supplied.

=item add_admin_user --user=testuser (hidden task)

Add administrative user account. If account exists, modify it as appropriate.
New users are disabled. Use passwd to enable it.

=back

=cut
