##
## copy-windows-links.pl -- Copies symbolic "links" on windows
##

use File::Copy;
use strict;

my $sourceDir = $ARGV[0];
my $targetDir = $ARGV[1];

# Force forward slashes in paths
$sourceDir =~ s/\\/\//g;
$targetDir =~ s/\\/\//g;

# Remove trailing slashes
$sourceDir =~ s/\/$//;
$targetDir =~ s/\/$//;

print "\nCopying linked files from '$sourceDir' to '$targetDir'\n\n";

printUsage() unless (-d $sourceDir);
printUsage() unless (-d $targetDir);

sub printUsage
{
    die "Usage:\n\tcopy-windows-links.pl <source-dir> <target-dir>\n";
}

while (<$sourceDir/*.h>)  #*/
{
	my $header = $_;

	open(HEADER, "< $header");
	my $relativePath = <HEADER>;
	close(HEADER);

	if (substr($relativePath, length($relativePath) - 1) eq "\n")
	{
		print "Copying '$header'... (NOT A LINK)\n";
		copy ($header, $targetDir);
	}
	else
	{
		my $linkedFile = "$sourceDir/$relativePath";
		print "Copying '$linkedFile'... (LINK from '$header')\n";

		if (-s $linkedFile > 0)
		{
			copy ($linkedFile, $targetDir);
		}
		else
		{
			print "ERROR: '$linkedFile' does not exist!\n";
		}
	}
}


print "\nFinished copying links!\n";
