#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/local/lib/perl5";
use Getopt::Long qw/:config posix_default no_ignore_case bundling/;
use Pod::Usage qw/pod2usage/;
use HTTP::Tiny;
use JSON::PP;

GetOptions(
    'h|help'       => \my $help,
    'gf-uri=s'     => \my $gfbase,
    'gf-service=s' => \my $gfservice,
    'gf-section=s' => \my $gfsection,
    'gf-name-prefix=s' => \my $gfprefix,
    'jvm-pid=i'    => \my $jvmpid,
) or pod2usage(1);

pod2usage(-verbose=>2,-exitval=>0) if $help;
pod2usage(-verbose=>1,-exitval=>1) if !$gfbase || !$gfservice || !$gfsection || !$jvmpid;

my $_json = JSON::PP->new->utf8;
if ( $gfprefix ) {
    $gfprefix .= '_';
}
else {
    $gfprefix = '';
}

my %st;
my %ids;
my %colors = (
    perm_max => '#1111cc',
    perm_commit => '#11cc11',
    perm_used => '#cccc77',
    old_max => '#1111cc',
    old_commit => '#11cc11',
    old_used => '#cccc77',
    new_max => '#1111cc',
    new_commit => '#11cc11',
    sv0_used => '#952d57',
    sv1_used => '#f9d475',
    eden_used => '#dd923c',
    fgc_times => '#7020AF',
    fgc_sec => '#F0B300',
);

my $gccapacities = cap_jstat('gccapacity',$jvmpid);
die "fetch gccapacity failed" unless $gccapacities;
($st{new_max},$st{new_commit},$st{old_max},$st{old_commit},$st{perm_max},$st{perm_commit}) = @$gccapacities[1,2,7,8,11,12];

my $gcolds = cap_jstat('gcold',$jvmpid);
die "fetch gcold failed" unless $gcolds;
($st{perm_used}, $st{old_used}) = @$gcolds[1,3];

my $gcnews = cap_jstat('gcnew',$jvmpid);
die "fetch gcnew failed" unless $gcnews;
($st{sv0_used}, $st{sv1_used}, $st{eden_used}) = @$gcnews[2,3,8];

my $fgcs = cap_jstat('gc',$jvmpid);
die "fetch gc failed" unless $fgcs;
($st{fgc_times},$st{fgc_sec}) = ($fgcs->[12], $fgcs->[13]*1000);

my $ua = HTTP::Tiny->new(
    agent => 'jstat2gf',
    timeout => 30,
);

foreach my $key ( keys %st ) {
    my $res = $ua->post_form(
        $gfbase . 'api/' . $gfservice . '/' . $gfsection . '/' . $gfprefix. $key, [
            number => int($st{$key}),
            mode   => 'gauge',
            color  => $colors{$key},
        ]
    );
    if ( !$res->{success} ) {
        die 'failed update:'.$res->{status}.' '.$res->{reason};
    }
    my $json = $_json->decode($res->{content});
    $ids{$key} = $json->{data}->{id};
}

# fgc_times, fgc_sec
{
    my $key = 'fgc_times';
    my $json = get_json($ua, $gfbase . 'json/graph/' . $gfservice . '/' . $gfsection . '/' . $gfprefix.$key);
    if ( $json && $json->{gmode} ne 'subtract' ) {
        $json->{gmode} = 'subtract';
        $json->{stype} = 'LINE1';
        $json->{sort} = 16;
        $json->{adjust} = '/';
        $json->{adjustval} = '60';
        $json->{description} = 'gc/sec';
        post_json($ua, $gfbase . 'json/edit/graph/' . $ids{$key}, $json);
    }
}
{
    my $key = 'fgc_sec';
    my $json = get_json($ua, $gfbase . 'json/graph/' . $gfservice . '/' . $gfsection . '/' . $gfprefix.$key);
    if ( $json && $json->{gmode} ne 'subtract' ) {
        $json->{gmode} = 'subtract';
        $json->{stype} = 'AREA';
        $json->{sort} = 15;
        $json->{adjust} = '/';
        $json->{adjustval} = '60000';
        $json->{description} = 'time spent for gc/sec';
        post_json($ua, $gfbase . 'json/edit/graph/' . $ids{$key}, $json);
    }
}


#complex perm
{
    my $key = 'permanent';
    my $json = get_json($ua, $gfbase . 'json/complex/' . $gfservice . '/' . $gfsection . '/' . $gfprefix.$key);
    if ( !$json ) {
        $json = {
            service_name => $gfservice,
            section_name => $gfsection,
            graph_name => $gfprefix.$key,
            description => 'JVM memory KB (permanent)',
            sort => 17,
            data => [
                { graph_id => $ids{perm_commit}, type => 'AREA', gmode => 'gauge' ,stack => 0  },
                { graph_id => $ids{perm_max}, type => 'LINE1', gmode => 'gauge' ,stack => 0  },
                { graph_id => $ids{perm_used}, type => 'AREA', gmode => 'gauge' ,stack => 0  }
            ],
        };
        post_json($ua, $gfbase . 'json/create/complex', $json);
    }
}

#complex new
{
    my $key = 'new';
    my $json = get_json($ua, $gfbase . 'json/complex/' . $gfservice . '/' . $gfsection . '/' . $gfprefix.$key);
    if ( !$json ) {
        $json = {
            service_name => $gfservice,
            section_name => $gfsection,
            graph_name => $gfprefix.$key,
            description => 'JVM memory KB (new)',
            sort => 19,
            data => [
                { graph_id => $ids{new_commit}, type => 'AREA', gmode => 'gauge' ,stack => 0  },
                { graph_id => $ids{new_max}, type => 'LINE1', gmode => 'gauge' ,stack => 0  },
                { graph_id => $ids{sv0_used}, type => 'AREA', gmode => 'gauge' ,stack => 0  },
                { graph_id => $ids{sv1_used}, type => 'AREA', gmode => 'gauge' ,stack => 1  },
                { graph_id => $ids{eden_used}, type => 'AREA', gmode => 'gauge' ,stack => 1  }
            ],
        };
        post_json($ua, $gfbase . 'json/create/complex', $json);
    }
}

#complex old
{
    my $key = 'old';
    my $json = get_json($ua, $gfbase . 'json/complex/' . $gfservice . '/' . $gfsection . '/' . $gfprefix.$key);
    if ( !$json ) {
        $json = {
            service_name => $gfservice,
            section_name => $gfsection,
            graph_name => $gfprefix.$key,
            description => 'JVM memory KB (old)',
            sort => 18,
            data => [
                { graph_id => $ids{old_commit}, type => 'AREA', gmode => 'gauge' ,stack => 0  },
                { graph_id => $ids{old_max}, type => 'LINE1', gmode => 'gauge' ,stack => 0  },
                { graph_id => $ids{old_used}, type => 'AREA', gmode => 'gauge' ,stack => 0  }
            ],
        };
        post_json($ua, $gfbase . 'json/create/complex', $json);
    }
}


sub get_json {
    my ($ua, $uri) = @_;
    my $res = $ua->get($uri);
    if ( !$res->{success} ) {
        return;
    }
    $_json->decode($res->{content});
}

sub post_json {
    my ($ua, $uri, $json) = @_;
    my $data = $_json->encode($json);    
    $ua->post($uri, {
        headers => {
            'Content-Length'=>length($data)
        },
        content => $data
    });
}

sub cap_jstat {
    my ($option, $jvmpid) = @_;
    pipe my $logrh, my $logwh
        or die "Died: failed to create pipe:$!";
    my $pid = fork;
    if ( ! defined $pid ) {
        die "Died: fork failed: $!";
    } 

    elsif ( $pid == 0 ) {
        #child
        close $logrh;
        open STDOUT, '>&', $logwh
            or die "Died: failed to redirect STDOUT";
        close $logwh;
        exec 'jstat','-'.$option, $jvmpid;
        die "Died: exec failed: $!";
    }
    close $logwh;
    my @result;
    while(<$logrh>){
        chomp;chomp;
        push @result,$_;
    }
    close $logrh;
    while (wait == -1) {}
    my $exit_code = $?;
    $exit_code = $exit_code >> 8;
    if ( $exit_code != 0 ) {
        warn "Error: command exited with code: $exit_code";
        return;
    }
    if ( @result != 2 ) {
        warn "Error: does not contain stats";
        return;
    }
    $result[1] =~ s/^\s+//g;
    my @ret = split /\s+/, $result[1];
    return \@ret;
}

=encoding utf8

=head1 NAME

jstat2gf.pl - Visualize jstat with GrowthForecast

=head1 SYNOPSIS

  $ crontab -l
  PATH=/path/to/java/bin:/usr/bin
  * * * * * perl /path/to/jstat2gf.pl --gf-uri=http://gf/ --gf-service=example --gf-section=jvm --gf-name-prefix=app001 --jvm-pid=$(pgrep -of 'process name')

=head1 DESCRIPTION

jstat2gf.pl retieve jvm's metrics from jstat command, and push them to GrowthForecast. 
Also jstat2gf.pl adds some stacked graphs.


=head1 ARGUMENTS

=over 4

=item -h, --help

Display help message

=item --gf-uri

URI of GrowthForecast

=item --gf-service

service_name to push metrics

=item --gf-section

section_name to push metrics

=item --gf-name-prefix

prefix of graph_name (Optional)

=item --jvm-pid

pid of a jvm process

=back

=head1 SEE ALSO

<jstat>

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo@gmail.comE<gt>

=head1 LICENSE

Copyright (C) Masahiro Nagano

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


