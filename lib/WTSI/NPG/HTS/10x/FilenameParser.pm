package WTSI::NPG::HTS::10x::FilenameParser;

use File::Basename;
use Moose::Role;

our $VERSION = '';

=head2 parse_file_name

  Arg [1]      Full path or file name of a file named using
               the 10x convention for fastq files

  Example    : my @pg_records = $obj->parse_file_name($path);
  Description: Return an array containing read, tag, position
               and format. The file must be named using the 10x
               convention for fastq files which differs
               dending on how the fastq files were generated

               ..ranger mkfastq
    
                  21870_1_AACCGTAA_S4_L001_I1_001.fastq.gz
                  21870_1_AACCGTAA_S4_L001_R1_001.fastq.gz

               ..ranger undetermined mkfastq
    
                  Undetermined_S0_L007_I1_001.fastq.gz
    
               ..ranger demux

                  read-RA_si-TTTCATGA_lane-005-chunk-000.fastq.gz
                  read-I1_si-TTTCATGA_lane-005-chunk-000.fastq.gz

  Returntype : Array[Str]

=cut

sub parse_file_name {
  my ($self, $path) = @_;

  my ($file_name, $directories, $suffix) = fileparse($path);

  ## no critic (RegularExpressions::ProhibitComplexRegexes)

  my ($id_run,$read,$tag,$position,$format);

  # first ..ranger mkfastq format
  ($id_run,$position,$tag,$read,$format) =
            $file_name =~ m{
                         ^(\d+)            # run id
                         _                 # Separator
                         (\d)              # Position
                         _                 # Separator
                         ([ACGTNX]+)       # Tag sequence
                         _S\d+_            # Separator
                         L00\2             # Position again
                         _                 # Separator
                         (I\d|R\d)         # Read
                         _\d+              # chunk
                         [.](fastq)[.]gz+$ # File format
                     }mxs;
  if ( defined $id_run && defined $read && defined $tag and defined $position && defined $format ) {
    return ($id_run, $read, $tag, $position, $format);
  }

  # next ..ranger mkfastq undetermined format
  ($tag,$position,$read,$format) =
            $file_name =~ m{
                         ^(Undetermined)   # Tag sequence
                         _S\d+_            # Separator
                         L00(\d)           # Position
                         _                 # Separator
                         (I\d|R\d)         # Read
                         _\d+              # chunk
                         [.](fastq)[.]gz+$ # File format
                     }mxs;
  if ( defined $read && defined $tag and defined $position && defined $format ) {
    return ($id_run, $read, $tag, $position, $format);
  }

  # and finally ..ranger demux format
  ($read,$tag,$position,$format) =
        $file_name =~ m{
                         ^read\-           # Separator
                         (I1|I2|RA)        # Read
                         _si\-             # Separator
                         ([ACGTNX]+)       # Tag sequence
                         _lane\-           # Separator
                         00(\d)            # Position
                         \-chunk\-         # Separator
                         \d+               # chunk
                         [.](fastq)[.]gz+$ # File format
                     }mxs;
  
  return ($id_run, $read, $tag, $position, $format);
}

no Moose::Role;

1;

__END__

=head1 NAME

WTSI::NPG::HTS::10x::FilenameParser

=head1 DESCRIPTION

This role is to be used where it is necessary to parse the names of
10x fastq file. The file names are structured such that their
read type, lane position, tag may be determined.

This should be considered a legacy or last resort method of
determining this information. Future work should use the
npg_tracking::glossary::composition package to determine the
provenance of data in sequencing results.


=head1 AUTHOR

Keith James <kdj@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2015, 2016 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
