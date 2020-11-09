package Deploy::Virt;

use Rex -feature=>['1.3'];
use Data::Dumper;
#use Rex::Commands::LVM;


desc "Deploy LXC virtualization host server";
task "deploy_hostsrv", sub {
  say "LXC virtualization host server deployment.";
  say "! Enable internet on the destination server.";
  my %i = get_system_information();
  say "Started on: $i{hostname}, $i{operating_system} system (arch: $i{architecture}), version: $i{operating_system_release}.";
  die "Unsupported operating system.\n" unless operating_system_is('Debian');
  die "Unsupported OS version\n" if operating_system_version() < 90;

  # print lvm structure jfyi
  say "LVM configuration is:";
  my $v = run "pvs";
  say "*** PV-s:"; say $v;
  $v = run "vgs";
  say "*** VG-s:"; say $v;
  $v = run "lvs";
  say "*** LV-s:"; say $v;

  # install packages
  my $packages = case operating_system, {
    Debian => ['sudo','aptitude','mc','lxc'],
    Ubuntu => ['sudo','aptitude','mc','lxc'], #FIXME
  };
  say "Updating package database...";
  update_package_db;
  pkg $packages, ensure => "present";

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

  # time sync
  append_or_amend_line "/etc/systemd/timesyncd.conf",
    line => "NTP=10.15.0.1",
    regexp => qr/^\s*NTP/,
    on_change => sub {
      say "Time syncronization: /etc/systemd/timesyncd.conf updated."
    };

  # setup network bridges
  my $net = $i{Network};
  #say Dumper $net;
  # check that interface br0 not exist
  my $br0_exists = 0;
  foreach (@{$net->{networkdevices}}) {
    if (/br0/) { $br0_exists = 1; last;}
  }
  if ($br0_exists) {
    say "Interface br0 exists! No network configuration is performed."
  } else {
    my $conf_iface = {
      #dev => '',
      ip => '10.14.73.11',
      netmask => '255.192.0.0',
      gateway => '10.15.0.1',
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
      say 'Configuring network.';
      file '/etc/network/interfaces',
        owner => 'root',
	group => 'root',
	mode => 644,
        content => template("files/interfaces.tpl", iface => $conf_iface),
	on_change => sub {
	  say "/etc/network/interfaces is updated.";
	};
      file '/etc/resolv.conf',
        owner => 'root',
	group => 'root',
	mode => 644,
        source => "files/resolv.conf",
	on_change => sub {
	  say "/etc/resolv.conf is updated.";
	};
      say "Network is configured to IP address: $conf_iface->{ip}.";
      say "Review and set the IP manually. Settings will be applied on next reboot!"
    } else {
      say "Network physical interface wasn't found! No network configuration is performed."
    }
  }

};


desc "Display LVM configuration for host server";
task "show_lvm", sub {
  die "Unsupported operating system.\n" unless operating_system_is('Debian');
  die "Unsupported OS version\n" if operating_system_version() < 90;
  say "LVM configuration:";
  my $v = run "pvs";
  say "*** PV-s:"; say $v;
  $v = run "vgs";
  say "*** VG-s:"; say $v;
  $v = run "lvs";
  say "*** LV-s:"; say $v."\n";
};

1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Virt/;

 task yourtask => sub {
    Deploy::Virt::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
