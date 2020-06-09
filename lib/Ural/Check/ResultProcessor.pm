package Ural::Check::ResultProcessor;

use strict;
use warnings;
use v5.12;
#use utf8;

use Email::Sender::Simple qw(try_to_sendmail);
use Email::Sender::Transport::SMTP qw();
use Email::Simple;
use Encode;

# $rp = Check::ResultProcessor->new(
#   mail_smtp => 'mail.uwc.ufanet.ru',
#   mail_from => 'ural@uwc.ufanet.ru',
#   mail_ticket_to => 'otrs@uwc.ufanet.ru',
# );
sub new {
  my ($class, %args) = @_;
  my $self = {};
  $self->{buffer} = '';

  $self->{mail_smtp} = 'mail.uwc.ufanet.ru';
  $self->{mail_from} = 'ural@uwc.ufanet.ru';
  $self->{mail_ticket_to} = 'otrs@uwc.ufanet.ru';
  for (qw/mail_smtp mail_from mail_ticket_to/) {
    $self->{$_} = $args{$_} if defined $args{$_};
  }

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

  # Группа сетевого администрирования
  my $f2 = '"'.encode('MIME-Header', decode_utf8('Группа сетевого администрирования'))."\" <$self->{mail_from}>";
  my $subj = "Результат проверки узла $host корпоративной сети";
  $subj = encode('MIME-Header', decode_utf8($subj));

  my $email = Email::Simple->create(
    header => [
      To => $rep_to,
      #From => $f2,
      #Subject => $subj,
      'MIME-Version' => '1.0',
      'Content-Type' => 'text/plain; charset=UTF-8',
      'Content-Transfer-Encoding' => '8bit',
    ],
    body => decode_utf8($self->{buffer}),
  );
  $email->header_set('From', $f2);
  $email->header_set('Subject', $subj);

  say "\nОтправка отчёта по электронной почте на $rep_to...";

  try_to_sendmail(
    $email,
    { from => $self->{mail_from},
      to => $rep_to,
      transport => Email::Sender::Transport::SMTP->new({
	host => $self->{mail_smtp},
	port => 25,
      })
    }
  ) or die "Error: can't mail report\n";
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

  my $email = Email::Simple->create(
    header => [
      To => $self->{mail_ticket_to},
      #From => $ticket_from,
      #Subject => $subj1,
      'MIME-Version' => '1.0',
      'Content-Type' => 'text/plain; charset=UTF-8',
      'Content-Transfer-Encoding' => '8bit',
    ],
    body => decode_utf8('Неисправность: '.$subj."\n\nПо заявке проведена автоматическая диагностика неисправности. Результаты.\n".$self->{buffer}),
  );
  $email->header_set('From', $ticket_from);
  $email->header_set('Subject', $subj1);

  try_to_sendmail(
    $email,
    { from => $ticket_from,
      to => $self->{mail_ticket_to},
      transport => Email::Sender::Transport::SMTP->new({
	host => $self->{mail_smtp},
	port => 25,
      })
    }
  ) or die "Error: can't mail report\n";

  say "Заявка будет создана в системе техподдержки в течение 10 минут.";
}


#sub buf_debug {
#  say "Buffer: ".shift->{buffer}."Buffer end.";
#}

1;
__END__
