package UtilSSH;

use Rex -feature => ['1.3'];
#use Rex::Commands::User;

desc "Install public key to authorized_keys, for OpenWrt (Dropbear/OpenSSH supported)";
task "install_owrt_sshkey", sub {
  if (operating_system_is("OpenWrt")) {
    if (is_dir("/etc/dropbear")) {
      say "Installing for Dropbear...";
      UtilSSH::install_dropbear_sshkey();
    }

    if (is_dir("/etc/ssh")) {
      say "Installing for OpenSSH (global key)...";
      UtilSSH::install_openssh_sshkey();
    }

  } else {
    die "Unsupported operating system";
  }
};


desc "Install public key to Dropbear authorized_keys, for OpenWrt";
task "install_dropbear_sshkey", sub {
  unless (is_dir("/etc/dropbear")) {
    die "/etc/dropbear directory is not found. Probably this is not Dropbear system";
  }
  if (operating_system_is("OpenWrt")) {
    file "/etc/dropbear/authorized_keys",
      source => get(cmdb('public_key')),
      mode => 600;
    say "Keyfile is installed to dropbear.";
  } else {
    die "Unsupported operating system";
  }
};


desc "Install public key to OpenSSH *global* authorized_keys";
task "install_openssh_sshkey", sub {
  unless (is_dir("/etc/ssh")) {
    die "/etc/ssh directory is not found. Probably this is not OpenSSH system";
  }
  # openssh complains on bad permissions /etc/ssh
  file "/etc/ssh",
    ensure => "directory",
    mode => 755;
  file "/etc",
    ensure => "directory",
    mode => 755;

  file "/etc/ssh/authorized_keys",
    source => get(cmdb('public_key')),
    mode => 600,
    on_change => sub {
      say "Keyfile installed to /etc/ssh/authorized_keys.";
    };

  my $f = '/etc/ssh/sshd_config';
  delete_lines_according_to qr/^PermitEmptyPasswords yes/, $f;
  append_or_amend_line $f,
    line => "PubkeyAuthentication yes",
    regexp => qr/^#?PubkeyAuthentication/;
  append_or_amend_line $f,
    line => "AuthorizedKeysFile /etc/ssh/authorized_keys",
    regexp => qr/^#?AuthorizedKeysFile/,
    on_change => sub {
      run "kill -HUP `cat /var/run/sshd.pid`";
    };
  say "sshd is configured to use /etc/ssh/authorized_keys file.";
};


desc "Install public key to OpenSSH *user* authorized_keys
  rex install_openssh_user_sshkey --user=ural";
task "install_openssh_user_sshkey", sub {
  my $_user = shift->{user};
  unless ($_user) {
    die "Invalid task parameters";
  }
  unless (is_dir("/etc/ssh")) {
    die "/etc/ssh directory is not found. Probably this is not OpenSSH system";
  }
  my %u = get_user($_user);
  my $home = $u{home};
  unless (is_dir("$home")) {
    die "$home directory is not found. Something get wrong.";
  }
  say "Installing sshkey to user: $_user, $home/.ssh/authorized_keys file...";
  file "$home/.ssh/authorized_keys",
    source => get(cmdb('public_key')),
    mode => 600,
    owner => "$_user",
    on_change => sub { 
      say "Keyfile is installed to $home/.ssh/authorized_keys.";
    };
  
  my $f = '/etc/ssh/sshd_config';
  delete_lines_according_to qr/^PermitEmptyPasswords yes/, $f;
  append_or_amend_line $f,
    line => "PubkeyAuthentication yes",
    regexp => qr/^#?PubkeyAuthentication/;
  append_or_amend_line $f,
    line => "AuthorizedKeysFile .ssh/authorized_keys",
    regexp => qr/^#?AuthorizedKeysFile/,
    on_change => sub {
      run "kill -HUP `cat /var/run/sshd.pid`";
    };
  say "sshd is configured to use .ssh/authorized_keys file.";
};


desc "Delete one IP address from openssh known_hosts file on rundeck server
  rex cleanup_known_hosts_ip --ip=192.168.0.1";
task "cleanup_known_hosts_ip", sub {
  my $_ip = shift->{ip};
  unless ($_ip) {
    die "Invalid task parameter, specify ip address.";
  }
  my $file_skh = '/opt/rundeck/var/lib/rundeck/.ssh/known_hosts';
  #
  say "Trying to delete stored key for $_ip...";

  my $ip_pat = $_ip; $ip_pat =~ s/\./\\./g;
  delete_lines_according_to qr/$ip_pat/, $file_skh, on_change => sub {
    say "Key for $_ip has been deleted from known_hosts file.";
  };
};


desc "Delete deploy hosts (10.0.1.1, 10.0.1.2) from known_hosts file on rundeck server";
task "cleanup_known_hosts_deploy", sub {
  my $file_skh = '/opt/rundeck/var/lib/rundeck/.ssh/known_hosts';
  #
  say "Trying to delete stored keys for 10.0.1.1 and 10.0.1.2...";
  delete_lines_according_to qr/10\.0\.1\.1/, $file_skh, on_change => sub {
    say "Key for 10.0.1.1 has been deleted from known_hosts file.";
  };
  delete_lines_according_to qr/10\.0\.1\.2/, $file_skh, on_change => sub {
    say "Key for 10.0.1.2 has been deleted from known_hosts file.";
  };
};


desc "Delete one IP address from local root openssh known_hosts file
  rex root_cleanup_known_hosts_ip --ip=192.168.0.1";
task "root_cleanup_known_hosts_ip", sub {
  my $_ip = shift->{ip};
  unless ($_ip) {
    die "Invalid task parameter, specify ip address.";
  }
  my $file_skh = '/root/.ssh/known_hosts';
  #
  say "Trying to delete stored key for $_ip...";

  my $ip_pat = $_ip; $ip_pat =~ s/\./\\./g;
  delete_lines_according_to qr/$ip_pat/, $file_skh, on_change => sub {
    say "Key for $_ip has been deleted from local root known_hosts file.";
  };
};


1;

=pod

=encoding utf-8

=head1 NAME

$::UtilSSH - SSH configuration tasks

=head1 DESCRIPTION

Установка ключей SSH, очистка known_hosts.

=head1 USAGE

Путь к устанавливаемому публичному ключу берется из cmdb public_key.

Для OpenWrt:
  rex -H 10.0.1.1 UtilSSH:install_owrt_sshkey

  rex -H 10.0.1.1 UtilSSH:install_dropbear_sshkey
  rex -H 10.0.1.1 UtilSSH:install_openssh_sshkey

В Slackware, для юзера ttt:
  rex -u root -H 10.15.0.3 UtilSSH:install_openssh_user_sshkey --user=ttt

Для Debian, просто заходим под существующим пользователем root, устанавливаем ключ для root:
  rex -u ural -s -S sudo_password -H 10.14.73.27 UtilSSH:install_openssh_user_sshkey --user=root

Для Ubuntu, используем существующего пользователя ural и делаем sudo, устанавливаем ключ для root.
Затем команды rex можно будет запускать от пользователя root (rex -u root):
  rex -u ural -s -S sudo_password -H 10.14.73.27 UtilSSH:install_openssh_user_sshkey --user=root

=head1 TASKS

=over 4

=item install_owrt_sshkey

Installs public key for OpenWrt. Dropbear/OpenSSH are detected automatically.

=item install_dropbear_sshkey

Installs public key to Dropbear /etc/dropbear/authorized_keys, for OpenWrt.

=item install_openssh_sshkey

Installs public key to OpenSSH B<*global*> /etc/ssh/authorized_keys.

=item install_openssh_user_sshkey --user=username

Installs public key to OpenSSH B<*user*> ~/.ssh/authorized_keys.

=item cleanup_known_hosts_ip

Delete one IP address from openssh I<known_hosts> file for rundeck server.
  rex cleanup_known_hosts_ip --ip=192.168.0.1";

=item cleanup_known_hosts_deploy

Delete deploy hosts (10.0.1.1, 10.0.1.2) from I<known_hosts> file for rundeck server.

=item root_cleanup_known_hosts_ip

Delete one IP address from B<local root> openssh I<known_hosts> file.
  rex root_cleanup_known_hosts_ip --ip=10.14.73.27";

=back

=cut
