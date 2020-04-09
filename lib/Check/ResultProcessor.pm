package Check::ResultProcessor;

use strict;
use warnings;
#use utf8;
use feature ':5.10';

use Mail::Sender;
use Encode;

sub new {
  my $class = shift;
  my $self = {};
  $self->{buffer} = '';

  return bless $self, $class;
}

sub reset {
  shift->{buffer} = '';
}

sub say {
  my $self = shift;
  $self->{buffer} .= join '', @_, "\n";
  say @_;
}

sub print {
  my $self = shift;
  $self->{buffer} .= join '', @_, "\n";
  print @_;
}

# $obj->email('ural@uwc.ufanet.ru', 'gwsouth3');
sub email {
  my $self = shift;
  my $rep_to = shift; 
  die "Email parameter missing" unless $rep_to;
  my $host = shift; $host = '' unless defined $host;

  my $f1 = 'ural@uwc.ufanet.ru';
  # Группа сетевого администрирования
  my $f2 = << "EOF";
"=?UTF-8?Q?=D0=93=D1=80=D1=83=D0=BF=D0=BF=D0=B0_?=
=?UTF-8?Q?=D1=81=D0=B5=D1=82=D0=B5=D0=B2=D0=BE=D0=B3=D0=BE_?=
=?UTF-8?Q?=D0=B0=D0=B4=D0=BC=D0=B8=D0=BD=D0=B8=D1=81=D1=82=D1=80=D0=B8?=
=?UTF-8?Q?=D1=80=D0=BE=D0=B2=D0=B0=D0=BD=D0=B8=D1=8F?=" <$f1>
EOF
  my $subj = "Результат проверки узла $host корпоративной сети";
  $subj = encode('MIME-Header', decode_utf8($subj));

  say "\nОтправка отчёта по электронной почте на $rep_to...";

  my $s = new Mail::Sender {
    smtp => 'mail.uwc.ufanet.ru',
    from => $f1,
    fake_from => $f2,
    to => $rep_to,
    on_errors => undef,
  } or die "Error: can't create mail sender object.\n";

  $s->MailMsg({ subject => $subj,
    charset => 'UTF-8',
    encoding => 'quoted-printable',
    msg => decode_utf8($self->{buffer}),
  }) or die "Error: can't mail report: $s->{'error_msg'}\n";
}

# $obj->make_ticket('hatypov@uwc.ufanet.ru', 'gwsouth3');
# $obj->make_ticket('hatypov@uwc.ufanet.ru', 'gwsouth3', 'СКВС');
sub make_ticket {
  my $self = shift;
  my $ticket_from = shift; 
  die "ticket_from parameter missing" unless $ticket_from;
  my $host = shift || 'н/д';
  my $dept = shift || '';
  #say "DEBUG: Host: $host, Dept: $dept";
  
  my $subj = ($dept) ? "Нарушение связи с объектом $dept, узел $host корпоративной сети" : "Нарушение связи с узлом $host сети";
  my $subj1 = encode('MIME-Header', decode_utf8($subj));

  say "\nСоздание заявки от $ticket_from...";

  my $s = new Mail::Sender {
    smtp => 'mail.uwc.ufanet.ru',
    from => $ticket_from,
    fake_from => $ticket_from,
    to => 'otrs@uwc.ufanet.ru',
    on_errors => undef,
  } or die "Error: can't create mail sender object.\n";

  $s->MailMsg({ subject => $subj1,
    charset => 'UTF-8',
    encoding => 'quoted-printable',
    msg => decode_utf8('Неисправность: '.$subj."\n\nПо заявке проведена автоматическая диагностика неисправности. Результаты.\n".$self->{buffer}),
  }) or die "Error: can't mail report: $s->{'error_msg'}\n";
  say "Заявка будет создана в системе техподдержки в течение 10 минут.";
}


#sub buf_debug {
#  say "Buffer: ".shift->{buffer}."Buffer end.";
#}

1;
__END__
