package WTSI::NPG::HTS::TarStream;

use namespace::autoclean;

use English qw[-no_match_vars];
use File::Basename;
use File::Spec::Functions qw[abs2rel];
use Moose;
use MooseX::StrictConstructor;

our $VERSION = '';

our $PUT_STREAM = 'npg_irods_putstream.sh';

with qw[
         WTSI::DNAP::Utilities::Loggable
       ];

has 'tar' =>
  (isa           => 'FileHandle',
   is            => 'rw',
   required      => 0,
   init_arg      => undef,
   documentation => 'The tar file handle for writing');

has 'tar_cwd' =>
  (isa           => 'Str',
   is            => 'ro',
   required      => 1,
   documentation => 'The local working directory of the tar operation');

has 'tar_file' =>
  (isa           => 'Str',
   is            => 'ro',
   required      => 1,
   documentation => 'The tar file name');

has 'tar_content' =>
  (isa           => 'HashRef',
   is            => 'ro',
   required      => 1,
   default       => sub { return {} },
   init_arg      => undef,
   documentation => 'The file names added the current tar archive, by path');

has 'remove_files' =>
  (isa           => 'Str',
   is            => 'ro',
   required      => 1,
   default       => 0,
   documentation => 'Enable GNU tar --remove-files option to remove the ' .
                    'original file once archived');

sub BUILD {
  my ($self) = @_;

  $self->_check_absolute($self->tar_cwd);
  $self->_check_absolute($self->tar_file);

  return;
}

sub open_stream {
  my ($self) = @_;

  my $tar_path = $self->tar_file;

  my ($obj_name, $collections, $suffix) =
    fileparse($tar_path, qr{[.][^.]*}msx);
  $suffix =~ s/^[.]//msx; # Strip leading dot from suffix

  if (not $suffix) {
    $self->logconfess("Invalid data object path '$tar_path'");
  }

  my $tar_cwd     = $self->tar_cwd;
  my $tar_options = $self->remove_files ? '--remove-files ' : q[];
  $tar_options .= "-C '$tar_cwd' -c -T ";

  my $tar_cmd = "tar $tar_options - | " .
                "$PUT_STREAM -t $suffix '$tar_path' >/dev/null";
  $self->info("Opening pipe to '$tar_cmd' in '$tar_cwd'");

  open my $fh, q[|-], $tar_cmd
    or $self->logcroak("Failed to open pipe to '$tar_cmd': $ERRNO");

  $self->tar($fh);

  return $self->tar;
}

sub close_stream {
  my ($self) = @_;

  my $filename = $self->tar_file;
  if (defined $self->tar) {
    close $self->tar or
      $self->logcroak("Failed to close '$filename': $ERRNO");

    $self->debug("Closed '$filename'");
  }

  return;
}

sub add_file {
  my ($self, $path) = @_;

  $self->_check_absolute($path);

  my $rel_path = abs2rel($path, $self->tar_cwd);

  my $filename = $self->tar_file;
  $self->debug("Adding '$rel_path' to '$filename'");

  print {$self->tar} "$rel_path\n" or
    $self->logcroak("Failed write to filehandle of '$filename'");

  $self->tar_content->{$rel_path} = 1;

  return $rel_path;
}

sub file_count {
  my ($self) = @_;

  return scalar keys %{$self->tar_content};
}

sub _check_absolute {
  my ($self, $path) = @_;

  defined $path or $self->logconfess('A defined path argument is required');
  $path =~ m{^/}msx or
    $self->logconfess("An absolute path argument is required: '$path'");

  return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=head1 NAME

WTSI::NPG::HTS::TarStream

=head1 DESCRIPTION


=head1 AUTHOR

Keith James E<lt>kdj@sanger.ac.ukE<gt>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2017 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
