#! /usr/bin/perl -w

use warnings;
use strict;
use Mail::POP3Client;
use Mail::IMAPClient;
use IO::Socket::SSL;
use Net::SMTP::SSL;
require Conf;

our $VERSION = 0.42;

my $conf = 'Conf.pm';
my %cfg;
my $pop;
my $imap;
my @msg_ids;

if ( -e $conf ) {
    if ( -e $conf ) { %cfg = Conf::get_conf(); }
}
else {
    exit;
}

my %hash_func = (
    'list'   => \&get_mail,
    'read'   => \&read_mail,
    'delete' => \&delete_mail,
    'move'   => \&move_mail,
    'cd'     => \&change_folder,
    'lf'     => \&list_folders,
    'send'   => \&send_mail,
);

if ( $cfg{'base_info'}{'prot'} eq 'POP3' ) {
    $pop = Mail::POP3Client->new(
        USER     => $cfg{'base_info'}{'username'},
        PASSWORD => $cfg{'base_info'}{'password'},
        HOST     => $cfg{'base_info'}{'mailhost'},
        PORT     => $cfg{'base_info'}{'port'},
        USESSL   => 'true',
        TIMEOUT  => 5
    ) || die "Could not connect to server, terminating...\n";
}
elsif ( $cfg{'base_info'}{'prot'} eq 'IMAP' ) {
    $imap = Mail::IMAPClient->new(
        Server   => $cfg{'base_info'}{'mailhost'},
        User     => $cfg{'base_info'}{'username'},
        Password => $cfg{'base_info'}{'password'},
        Port     => $cfg{'base_info'}{'port'},
        Ssl      => 1,
        Uid      => 1,
        Timeout  => 5
    ) || die "Could not connect to server, terminating...\n";
    $imap->select('INBOX')
      || die "Could not select INBOX folder, terminating...\n";
}

print <<"EOT" or die $!;
Hello and welcome to perlOmail !
        Usage : list [number of mail]  	=> will fetch [number of mail] from INBOX and list there subject and writer, with an id
        read [id]			=> Obvious
        delete [id]			=> Obvious
        move [id new_folder]		=> Will move [id] from current folder (INBOX by default) to [new_folder]
        cd [new_folder]	       		=> Will change from current folder to [new_folder]
	lf				=> List folders
	send [to] [subject] [file]	=> Will send an email to the specidied address
        exit				=> Obvious
You\'re now in the perlOmail loop, enjoy your stay :)
EOT

sub get_mail {
    my ( $nbr, $prot ) = @_;

    if ( $prot eq 'POP3' ) {
        if ( $pop->Count() < 1 ) { print "no messages INBOX\n" || die $!; }
        for my $i ( $pop->Count() - $nbr .. $pop->Count() ) {
            print "id $i:\n" || die $!;
            foreach ( $pop->Head($i) ) {
                /^(From|Subject):\s+/xmsi && print $_, "\n" || die $!;
            }
        }
    }
    elsif ( $prot eq 'IMAP' ) {
        @msg_ids = $imap->messages;
        print $#msg_ids . " message found\n" || die $!;
        for my $i ( $#msg_ids - $nbr .. $#msg_ids ) {
            print "id $i:\n" || die $!;
            print 'from: '
              . $imap->get_header( $msg_ids[$i], 'from' ) . "\n"
              . 'subject: '
              . $imap->get_header( $msg_ids[$i], 'subject' )
              . "\n" || die $!;
        }
    }
    return;
}

sub read_mail {
    my ( $id, $prot ) = @_;

    if ( $prot eq 'POP3' ) {
        return 1 if $id < 0 || $id > $pop->Count();
        my $body = $pop->Body($id);
        $body =~ s/<[^>]*>//gxms;
        print $body. "\n" || die $!;

    }
    elsif ( $prot eq 'IMAP' ) {
        return 1 if $id < 0 || $id > $#msg_ids;
        my $body = $imap->body_string( $msg_ids[$id] );
        $body =~ s/<[^>]*>//gxms;
        print $body. "\n" || die $!;
    }
    return;
}

sub delete_mail {
    my ( $id, $prot ) = @_;

    print "Deleting message with id $id, will be effective on next session\n"
      || die $!;
    if ( $prot eq 'POP3' ) {
        return 1 if $id < 0 || $id > $pop->Count();
        $pop->Delete($id)
          || warn 'Delete failed';
    }
    elsif ( $prot eq 'IMAP' ) {
        return 1 if $id < 0 || $id > $#msg_ids;
        $imap->delete_message( $msg_ids[$id] )
          || warn 'delete_message failed"';
    }
    return;
}

sub clean_exit {
    my ($prot) = @_;

    if ( $prot eq 'POP3' ) {
        $pop->Close();
    }
    elsif ( $prot eq 'IMAP' ) {
        $imap->close();
    }
    print "We hope you enjoyed perlOmail, see you soon o/\n" || die $!;
    exit;
}

sub move_mail {
    my ( $id, $folder, $prot ) = @_;

    if ( $prot ne 'IMAP' ) {
        print "Moving mails requires IMAP\n" || die $!;
        return;
    }
    print "Moving mail with id $id from INBOX to $folder\n" || die $!;
    $imap->move( $folder, $msg_ids[$id] )
      || warn "Could not move mail\n";
    return;
}

sub change_folder {
    my ( $folder, $prot ) = @_;

    if ( $prot ne 'IMAP' ) {
        print "Changing folder requires IMAP\n" || die $!;
        return;
    }
    print "Changing folder, switching to $folder\n" || die $!;
    $imap->select($folder)
      || warn 'Could not change folder';
    return;
}

sub list_folders {
    my ($prot) = @_;

    if ( $prot ne 'IMAP' ) {
        print "list folders requires IMAP\n" || die $!;
        return;
    }
    my $folders = $imap->folders
      || warn "List folders error\n";
    print "Folders: @$folders\n" || die $!;
    return;
}

sub send_mail {
    my ( $from, $to, $subject, $file ) = @_;
    open FILE, '<', $file
      || die $!;
    close(FILE) || die $!;
    my $body = do { local $/; <FILE> };
    my $smtp = Net::SMTP::SSL->new( $cfg{'base_info'}{'smtphost'},
        Port => $cfg{'base_info'}{'smtpport'}, )
      || die 'Could not open connection';
    $smtp->auth( $cfg{'base_info'}{'username'}, $cfg{'base_info'}{'password'} )
      || warn 'Could not connect to server';
    $smtp->mail( $from . "\n" );
    my @recepients = split /,/xms, $to;

    foreach my $recp (@recepients) {
        $smtp->to( $recp . "\n" );
    }
    print "sending email !\n" || die $!;
    $smtp->data();
    $smtp->datasend( 'From: ' . $from . "\n" );
    $smtp->datasend( 'To: ' . $to . "\n" );
    $smtp->datasend( 'Subject: ' . $subject . "\n" );
    $smtp->datasend("\n");
    $smtp->datasend( $body . "\n" );
    $smtp->datasend( 'Signé ' . $cfg{'base_info'}{'username'} . "\n" );
    $smtp->dataend();
    $smtp->quit;
    return;
}

while (42) {
    print 'perlOmail =>' || die $!;
    my $cmd = <>;
    if ( $cmd =~ /(?<cmd>list)\s(?<nbr>[0-9]+)/xms ) {
        $hash_func{ $+{cmd} }->( $+{nbr}, $cfg{'base_info'}{'prot'} );
    }
    if ( $cmd =~ /(?<cmd>read)\s(?<id>[0-9]+)/xms ) {
        $hash_func{ $+{cmd} }->( $+{id}, $cfg{'base_info'}{'prot'} );
    }
    if ( $cmd =~ /(?<cmd>delete)\s(?<id>[0-9]+)/xms ) {
        $hash_func{ $+{cmd} }->( $+{id}, $cfg{'base_info'}{'prot'} );
    }
    if ( $cmd =~ /(?<cmd>move)\s(?<id>[0-9]+)\s(?<new_folder>[a-zA-Z]+)/xms ) {
        $hash_func{ $+{cmd} }->( $+{id}, $+{new_folder}, $cfg{'base_info'}{'prot'} );
    }
    if ( $cmd =~ /(?<cmd>cd)\s(?<nf>[a-zA-Z]+)/xms ) {
        $hash_func{ $+{cmd} }->( $+{nf}, $cfg{'base_info'}{'prot'} );
    }
    if ( $cmd =~ /(?<cmd>lf)/xms ) {
        $hash_func{ $+{cmd} }->( $cfg{'base_info'}{'prot'} );
    }
    if ( $cmd =~ /(?<cmd>send)\sto\s(?<to>[a-z0-9-_.]+@[a-z0-9-_]+.[a-z]{2,3})\ssubject\s(?<subj>[a-z0-9]+)\sfile\s(?<file>[a-z0-9]+.[a-z0-9]+)/ixms ) {
        $hash_func{ $+{cmd} }->( $cfg{'base_info'}{'username'}, $+{to}, $+{subj}, $+{file} );
    }
    if ( $cmd =~ /exit/xms ) { clean_exit( $cfg{'base_info'}{'prot'} ); }
}
