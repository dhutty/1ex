#!/usr/bin/env perl

use strict;
use warnings;

use Time::HiRes qw(gettimeofday tv_interval);
use IO::Socket;


my $t0 = [gettimeofday];
my $c = new IO::Socket::INET(PeerHost => '127.0.0.1',
                             PeerPort => '2003',
                             Proto    => 'tcp',
                             Reuse    => 0) or die ("$@\n");
my $elapsed = tv_interval($t0);
$c->send("agb.ops.infra.test.0 ".$elapsed." ".time()."\n");
$c->close();
