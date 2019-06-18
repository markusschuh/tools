#!/usr/bin/perl
#------------------------------------------
#  Author:  Jan Huschauer (EDV-Dienstleistungen)
#  Kontakt: huschi @ http://www.serversupportforum.de
#           http://www.huschi.net
#  Version: 0.2
#  Datum:   25.03.11
#  aktuall.:15.09.11
#  Danke an User dotme aus dem SSF fuer Wilcard Includes
#------------------------------------------

use strict;
use File::Spec::Functions qw(file_name_is_absolute rel2abs);
use File::Basename;

use vars qw(%config $Usage $searchHost $searchState @searchBuf); #config

#init:
$Usage = qq(usage:
  $0 [-v virtualhost] [-c|-C] [-n|-N] [/etc/httpd/httpd.conf]
Options:
  -v virtualhost  print only the VirtualHost of this host
  -c|-C           print comments  (-C) or not (-c) (default not)
  -n|-N           print filenames (-N) or not (-n) (default not)
  -help           print this usage-screen
);
%config = (	'debug'      => 0,
			'config'     => '',
			'hostonly'   => '',
			'comments'   => 0,
			'filenames'  => 0,
			'ServerRoot' => '',
);

# main
parse_Commandline();
do_run();

#------------------------------------------

#
# error
#
sub error {
	my ($error, $halt) = @_;
	print STDERR $error;
	print STDERR "\n" if ($error !~ /\n$/);
	exit if ($halt);
}

#
# findfile
#
sub findfile {
	my $cnf = '';
	foreach my $file (@_) {
		if (-f $file && -s $file) {
			$cnf = $file;
			last;
		}
	}
	return $cnf;
}

#
# parse_Commandline
#
sub parse_Commandline {
	while (@ARGV) {
		my $command = shift @ARGV;
		if ($command =~ /^-(\w+)/o) {
			my $char = $1;
			if ($char eq 'd') {
				$config{debug} = 1;
			} elsif ($char eq 'v') {
				$config{'hostonly'} = shift @ARGV;
			} elsif ($char eq 'c') {
				$config{'comments'} = 0;
			} elsif ($char eq 'C') {
				$config{'comments'} = 1;
			} elsif ($char eq 'n') {
				$config{'filenames'} = 0;
			} elsif ($char eq 'N') {
				$config{'filenames'} = 1;
			} elsif (($char eq '?') || ($char eq 'h') || ($char eq 'help')) {
				error($Usage, 1);
			} else {
				error("unknown parameter: $command\n".$Usage, 1);
			}
		} else {
			$config{'config'} = $command;
		}
	}
	if (!$config{'config'}) {
		$config{'config'} = findfile('/etc/apache2/apache2.conf', '/etc/apache2/httpd.conf', '/etc/apache/apache.conf', '/etc/httpd/httpd.conf');
	}
}

#------------------------------------------

#
# clearComment
#
sub clearComment {
	my ($line) = @_;
	my $pos = index($line, '#');
	$line = substr($line, 0, $pos) if ($pos >= 0);
	return $line;
}

#
# out
#
sub out {
	my ($line) = @_;
	if (!$config{debug}) {
		$line = clearComment($line) if (!$config{comments});
		print $line."\n" if ($line && ($line !~ /^[\s\t]+$/o));
	}
}

#
# read_dir
#
sub read_dir {
	my ($dir) = @_;
	$dir =~ s/\/$//g;
	return if (! -d $dir);
	if (opendir(my $hDIR, $dir)) {
		my $name;
		while ($name = readdir($hDIR)) {
			next if (($name =~ /^\./o) || ($name =~ /~$/o));
			my $path = $dir.'/'.$name;
			if (-f $path) {
				read_file($path);
			} elsif (-d $path) {
				read_dir($path);
			}
		}
		close($hDIR);
	} else {
		error("cannot open directory $dir\n");
	}
}

#
# read_file
#
sub read_file {
	my ($file) = @_;
	$file = rel2abs($file) if (!file_name_is_absolute($file));
	print "read file $file\n" if ($config{debug});
	my $printedName = 0;
	if ($config{filenames} && ($searchState != 1)) {
		print "### reading $file\n";
		$printedName = 1;
	}
	if (open(my $hIN, $file)) {
		my $line;
		while ($line = <$hIN>) {
			chomp($line);
			my $linec = clearComment($line);
			if ($linec =~ /^[\s\t]*(Include|AccessConfig|ResourceConfig)[\s\t]+"?([^"]+)"?/i) {
				my $inc = $2;
				print "found include $inc\n" if ($config{debug});
				if (!file_name_is_absolute($inc)) {
					$inc = $config{ServerRoot}.$inc;
				}
				if ($inc =~ /[*?]/) {
					if ($inc =~ /\s/) {
						print "WARN: skipping ambiguous include '$inc'\n";
						next;
					}
					foreach my $include (glob($inc)) {
						read_file($include) if (-f $include);
					}
				} else {
					if (-d $inc) {
						read_dir($inc);
					} else {
						read_file($inc);
					}
				}
			} else {
				if ($line =~ /^[}s\t]*ServerRoot[\s\t]+"?([^"]+)"?/i) {
					$config{ServerRoot} = $1;
					$config{ServerRoot} .= '/' if ($config{ServerRoot} !~ /\/$/o);
				}
				if ($searchState == 0) {
					out $line;
				} elsif ($searchState == 1) {
					if ($linec =~ /<VirtualHost/io) {
						$searchState = 2;
					}
				}
				if ($searchState > 1) {
					push @searchBuf, $line;
					if ($linec =~ /(ServerName|ServerAlias)[\s\t].*?$searchHost/g) {
						if ($config{filenames} && !$printedName) {
							print "### reading $file\n";
							$printedName = 1;
						}
						$searchState = 3;
					}
					if ($linec =~ /<\/VirtualHost>/io) {
						if ($searchState == 3) {
							foreach (@searchBuf) { out $_; }
						}
						$searchState = 1;
						@searchBuf   = ();
					}
				}
			}
		}
		close $hIN;
	} else {
		error("cannot open file $file\n");
	}
}

#
# do_run
#
sub do_run {
	if ($config{'config'}) {
		$searchHost  = $config{hostonly} || '';
		$searchState = ($searchHost) ? 1 : 0;
		@searchBuf   = ();
		read_file($config{'config'});
	} else {
		error('no config found!', 1);
	}
}
