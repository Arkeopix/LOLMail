#!/usr/bin/perl
# Simple gmail config:
# IMAP port = 993; host = imap.gmail.com
# POP3 port = 995; host = pop.gmail.com

package Conf;
{
    my %CFG = (
        'base_info' => {
            'username' => 'mendiej750@gmail.com',
            'password' => '*****',
            'mailhost' => 'pop.gmail.com',
            'smtphost' => 'smtp.gmail.com',
            'smtpport' => 465,
            'port'     => 995,
            'prot'     => 'POP3',
        },
    );
    sub get_conf { return %CFG; }
}
1;
