#!/usr/bin/perl

use strict;

my $warn;
my $crit;
my $out;

my @out;
my $drives;
my $pci;
my $scsi;
my $type;
my $mdadm;
my $fullcommand;
my $message;

my $pci = `lspci | /bin/grep -i raid | /bin/grep -v PATA | /usr/bin/head -1`;
my $scsi = `lspci | /bin/grep -i scsi | /bin/grep -v PATA | /usr/bin/head -1`;



my $smartcheck = `whereis smartctl`;
my $exist = length($smartcheck);

if ( $exist < 15 )
{
	system("sudo apt-get update");
	system("sudo apt-get -y install smartmontools > /dev/null 2>&1 ");
	system("sudo dpkg --configure -a");
}


sub smartctl
{
	my $command=$_[0];
	my $raidtype=$_[1];
	my $drive=$_[2];
	my $scsidev=$_[3];

	if ( $raidtype =~ /areca/i )
	{
		$fullcommand = "sudo $command -a -d areca,$drive $scsidev |";
	}
        if ( $raidtype =~ /mdadm/i )
        {
                $fullcommand = "sudo $command -a -d ata /dev/$drive|";
        }
	if ( $raidtype =~ /none/i )
	{
		$fullcommand = "sudo $command -a -d sat /dev/$drive|";
	}

	open(SMART,$fullcommand);
	while (<SMART>)
	{
		if ( $_ =~ /FAILING_NOW/ )
		{
			my @fail = split;
			$message = "Drive $drive is S.M.A.R.T. failing for $fail[1]";
			$crit = 1;
			push(@out,$message);
		}
	        if ( $_ =~ /_sector/i )
	        {
	                my @sector = split;
	                if ( $sector[1] =~ /reallocated/i  )
	                {
	                        $type = "reallocated";
	                }
	                if ( $sector[1] =~ /pending/i  )
	                {
	                        $type = "pending";
	                }
	                foreach ( $sector[9] )
	                {
	                        my $count = $_;
	                        $message = "Drive $drive has $count $type sectors";
	                        if ( ( $type =~ /reallocated/i && $count > 50 ) && ( $type =~ /pending/i && $count > 5 ) )
	                        {
					$crit = 1;
					push(@out,$message);
	                        }
	                        else
	                        {
					if ( $type =~ /reallocated/i && $count > 50 )
					{
	        				$crit = 1;
	        				push(@out,$message);
					}
					if ( $type =~ /pending/i && $count > 5 )
					{
	        				$crit = 1;
	        				push(@out,$message);
					}
	                	}
			}
		}
	}
}

#1068 IT controller
if ( $scsi =~ /SAS1068E/i )
{
	open(BLOCK,"cat /proc/partitions | grep -w sd[a-z] |");
	while (<BLOCK>)
	{
		my @output = split;
		my $blockdevice = $output[3];
		foreach ( $blockdevice )
		{
			$drives++;
			smartctl("smartctl","none",$blockdevice,"none");
		}
	}
}


# software raid!
if (-e "/proc/mdstat") 
{
	open(R,"/proc/mdstat");
	while (<R>)
	{
		if (/^(md\d+) : (\w+)/)
		{
			$mdadm = $mdadm + 1;
		}
	}
	if ( $mdadm gt 0 )
	{
	 open(BLOCK,"cat /proc/partitions | grep -w sd[a-z] |");
		while (<BLOCK>)
		{
			my @output = split;
			my $blockdevice = $output[3];
			foreach ( $blockdevice )
			{
				$drives++;
				smartctl("smartctl","mdadm",$blockdevice,"none");
			}
		}
	}
}

#areca hardware raid
if ( $pci =~ /areca/i)
{
	open(CLI,"sudo cli64 disk info | grep -vi Modelname | grep -v ====== | grep -vi GuiErr | grep -vi Free | grep -vi Failed |");
	while (<CLI>)
	{
		$drives++;
		if ( $_ =~ /^\ \ [0-9]+/ )
		{
			my @info = split(/\s+/,$_);
			foreach ($info[1])
			{
				my $drive = $_;
				my $vsf= `cli64 vsf info  | grep -v Capacity | grep -v ======== | grep -v ErrMsg | wc -l`;
				chomp $vsf;
				my $scsidev = "/dev/sg$vsf";
				smartctl("smartctl","areca",$drive,$scsidev);
			}
		}
	}
}

# show results
my $result = 0;
$result = 1 if $warn;
$result = 2 if $crit;
# print "warn = $warn crit = $crit\n";

my $out = "No real disks found on machine";
$out = "All $drives drives happy as clams" if $drives;

if (@out)
{
    $out = join(';     ', @out);  
}

print "$out\n";
exit $result;
