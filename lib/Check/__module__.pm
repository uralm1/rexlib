package Check;

use Rex -feature => ['1.3'];
use Data::Dumper;

use DBI;
use Check::ResultProcessor;

sub nd {
  my $v = shift;
  return ($v) ? $v : 'н/д';
}

sub ppres {
  return (shift)?'*ИСПРАВНО*':'*НЕТ СВЯЗИ*';
}

# rex Check:diagnose --host=gwsouth2 [--email=ural@uwc.ufanet.ru] [--ticket] [--ticket_from=ural@uwc.ufanet.ru]
desc "Network link diagnostics";
task diagnose => sub {
  my $params = shift;
  my $host = $params->{host};
  die "Router name is required!" unless $host;
  my $email= $params->{email};
  #say "DEBUG: email=$email";
  unless ($email && $email =~ /^.+\@uwc\.ufanet\.ru$/) {
    say("Ошибка! Указан неверный адрес электронной почты. Отправка результата по электронной почте производиться не будет.\n") if ($email);
    $email = '';
  }
  my $ticket = $params->{ticket} || '';
  my $ticket_from = $params->{ticket_from};
  $ticket = (lc($ticket) =~ /^(|no|false|Нет|нет)$/) ? 0:1;
  if ($ticket) {
    unless ($ticket_from && $ticket_from =~ /^.+\@uwc\.ufanet\.ru$/) {
      say("Ошибка! Не указан или неверный адрес создателя заявки. Заявка создана не будет.\n");
      $ticket = 0;
    }
  }
  #say "DEBUG: ticket=$ticket, ticket_from=$ticket_from";
 
  my $rp = Check::ResultProcessor->new();

  my $dbh = DBI->connect("DBI:mysql:database=".get('dbname').';host='.get('dbhost'), get('dbuser'), get('dbpass')) or 
    die "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");

  my $hr = $dbh->selectrow_hashref("SELECT \
r.host_name AS host_name, \
router_equipment.eq_name AS eq_name, \
router_equipment.manufacturer AS eq_manufacturer, \
departments.dept_name AS dept_name, \
departments.address AS dept_address, \
departments.contacts AS dept_contacts, \
departments.notes AS dept_notes, \
wans.name AS wan_name, \
wans.ip AS wan_ip, \
wans.gw AS wan_gw, \
providers.prov_name AS prov_name, \
providers.support AS prov_support, \
dogovors.prov_code AS prov_dog, \
dogovors.date AS prov_dog_date, \
dop_sogl.code AS prov_dog_dop_sogl, \
dop_sogl.date AS prov_dog_dop_sogl_date, \
lans.name AS lan_name, \
lans.ip AS lan_ip \
FROM routers r \
INNER JOIN wans ON wans.router_id = r.id \
INNER JOIN lans ON lans.router_id = r.id \
LEFT OUTER JOIN router_equipment ON router_equipment.id = r.equipment_id \
LEFT OUTER JOIN departments ON departments.id = r.placement_dept_id \
LEFT OUTER JOIN dogovors ON dogovors.id = wans.dogovor_id \
LEFT OUTER JOIN dop_sogl ON dop_sogl.id = wans.dop_sogl_id AND dop_sogl.dogovor_id = dogovors.id \
LEFT OUTER JOIN providers ON providers.id = dogovors.prov_id \
WHERE r.host_name = ?", {}, $host);
  unless ($hr) {
    $rp->say("Узел $host или его адреса WAN/LAN не найдены в базе данных. Будет произведена только проверка сетевой доступности.\n");
    $rp->say("Проверка доступности узла $host...\n");

    my $r = run_task 'UtilRex:ping', params => {host=>$host};
    $rp->say(ppres($r), ' - узел ', $host, '.');

    $rp->say("\nДиагностика узла $host завершена.");
    $rp->email($email, $host) if $email;
    $rp->make_ticket($ticket_from, $host) if $ticket and not $r;
    $dbh->disconnect;
    return 0;
  }
  #say Dumper $hr;

  my $ar1 = $dbh->selectall_arrayref("SELECT d.dept_name, d.address \
FROM departments d \
INNER JOIN routers r ON d.router_id = r.id \
WHERE r.host_name = ?", { Slice=>{} }, $host);

  $rp->say("Автодиагностика узла $hr->{host_name} корпоративной сети...\n");
  $rp->say("Маршрутизатор $hr->{host_name}, тип ".nd($hr->{eq_name}).' ('.nd($hr->{eq_manufacturer}).').');
  $rp->say('Место размещения маршрутизатора: '.nd($hr->{dept_name}).'.');
  $rp->say('Посмотреть на карте: https://net.uwc.ufanet.ru/mapv?c='.$hr->{host_name});
  $rp->say('Маршрутизатор обслуживает следующие подразделения: ');
  $rp->say('- ', nd($_->{dept_name}), ' (', nd($_->{address}), ')') foreach (@$ar1);

  $rp->say("\nПроверка связи по локальной сети (туннелированый канал):");
  my $success = 0;
  my $r = run_task 'UtilRex:ping', params => {host=>$hr->{lan_ip}};
  $rp->say(ppres($r), ' - ', $hr->{lan_name}, '.');
  if ($r) {
    $rp->say('1. Канал связи по локальной сети от ПЛК до маршрутизатора исправен.');
    $rp->say('2. Внешний канал связи провайдера '.nd($hr->{prov_name}).' до '.nd($hr->{dept_name}).' исправен (проверка не требуется).');
    # TODO проверка по подразделениям
    #
    $rp->say("\nПроблем не обнаружено.");
    $success = 1;
  } else {
    $rp->say("\nПроверка внешнего канала связи:");
    #$r = run_task 'UtilRex:ping', params => {host=>$hr->{wan_ip}}, on => 'erebus';
    my $task = Rex::TaskList->create()->get_task('UtilRex:ping');
    #say "DEBUG: ping on erebus user: ".$task->user;
    $task->set_user('ural');
    $r = $task->run('erebus', params=>{host=>$hr->{wan_ip}});

    $rp->say(ppres($r), ' - ', $hr->{wan_name}, '.');
    if ($r) {
      # tunnel error
      $rp->say("\n*** Диагноз ***");
      $rp->say("Обнаружено нарушение работы туннелированного канала связи.");
      $rp->say("Рекомендации по устранению неисправности:");
      $rp->say("- Перезагрузите маршрутизатор $hr->{host_name} через центр управления сетью.");
      $rp->say("- Проверьте работоспособность маршрутизатора в ПЛК.");
    } else {
      # link error
      $rp->say("Попытка проверки шлюза провайдера объекта (для диагностики):");
      # correct user is already set for this task
      $r = run_task 'UtilRex:ping', params => {host=>$hr->{wan_gw}}, on => 'erebus';
      $rp->say(ppres($r), ' - шлюз провайдера для '.$hr->{wan_name}.' (некритично).');
      $rp->say("\n*** Диагноз ***");
      $rp->say("Связь до обслуживаемых $hr->{host_name} подразделений отсутствует.\nЭто может быть вызвано следующими причинами:");
      $rp->say("1. Отключение или сбой маршрутизатора в ".nd($hr->{dept_name}).".");
      $rp->say("Рекомендации:");
      $rp->print("- Выполните звонок контактному персоналу: ".nd($hr->{dept_contacts}));
      $rp->say(" и попросите перезагрузить сетевое оборудование.");
      $rp->print("- Если неисправность устранить не удалось, выполните выезд на ".nd($hr->{dept_name}));
      $rp->print(' по адресу: '.nd($hr->{dept_address})) if $hr->{dept_address};
      $rp->say('.');
      $rp->say('Замечания по объекту: '.nd($hr->{dept_notes}).'.') if $hr->{dept_notes};

      $rp->say("\n2. Проблемы со связью на стороне провайдера ".nd($hr->{prov_name})." до ".nd($hr->{dept_name}).".");
      $rp->say("Рекомендации:");
      $rp->say("- Выполните звонок службе поддержки провайдера ".nd($hr->{prov_name}).', контакты:');
      $rp->say(nd($hr->{prov_support}));
      $rp->say("узнайте о наличии проблем с объектом ".nd($hr->{dept_name}));
      $rp->print("ip-адрес: ".$hr->{wan_ip});
      $rp->print(", договор: ".nd($hr->{prov_dog})." от ".nd($hr->{prov_dog_date})) if ($hr->{prov_dog});
      $rp->print(", доп.соглашение: ".nd($hr->{prov_dog_dop_sogl})." от ".nd($hr->{prov_dog_dop_sogl_date})) if ($hr->{prov_dog_dop_sogl});
      $rp->say("\nи сроки устранения проблем.");
    }
  }

  $rp->say("\nДиагностика узла $hr->{host_name} завершена.");
  $rp->email($email, $hr->{host_name}) if $email;
  $rp->make_ticket($ticket_from, $host, $hr->{dept_name}) if $ticket and not $success;
  $dbh->disconnect;
  return 0;
};

1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Check/;

 task yourtask => sub {
    Check::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
