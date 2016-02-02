package WTSI::NPG::HTS::AlMapFileDataObjectTest;

use utf8;

use strict;
use warnings;

use Carp;
use English qw(-no_match_vars);
use File::Spec::Functions;
use File::Temp;
use Log::Log4perl;
use Test::More;

use base qw(WTSI::NPG::HTS::Test);

Log::Log4perl::init('./etc/log4perl_tests.conf');

use WTSI::DNAP::Warehouse::Schema;
use WTSI::NPG::HTS::AlMapFileDataObject;
use WTSI::NPG::HTS::LIMSFactory;
use WTSI::NPG::HTS::Samtools;
use WTSI::NPG::iRODS::Metadata;
use WTSI::NPG::iRODS;

{
  package TestDB;
  use Moose;

  with 'npg_testing::db';
}

my $test_counter = 0;
my $data_path = './t/data/almap_file_data_object';
my $fixture_path = "./t/fixtures";

my $utf8_extra = '[UTF-8 test: Τὴ γλῶσσα μοῦ ἔδωσαν ἑλληνικὴ το σπίτι φτωχικό στις αμμουδιές του Ομήρου.]';

my $db_dir = File::Temp->newdir;
my $wh_schema;
my $lims_factory;

my $run7915_lane5_tag0 = '7915_5#0';
my $run7915_lane5_tag1 = '7915_5#1';

my $run15440_lane1_tag0  = '15440_1#0';
my $run15440_lane1_tag81 = '15440_1#81';

my $reference_file = 'test_ref.fa';
my $irods_tmp_coll;
my $samtools = `which samtools`;

my $have_admin_rights =
  system(qq{$WTSI::NPG::iRODS::IADMIN lu >/dev/null 2>&1}) == 0;

# The public group
my $public_group = 'public';
# Prefix for test iRODS data access groups
my $group_prefix = 'ss_';

# Filter for recognising test groups
my $group_filter = sub {
  my ($group) = @_;
  if ($group eq $public_group or $group =~ m{^$group_prefix}) {
    return 1
  }
  else {
    return 0;
  }
};

# Groups to be added to the test iRODS
my @irods_groups = map { $group_prefix . $_ } (10, 100, 198, 619, 2967, 3720);
push @irods_groups, $public_group;
# Groups added to the test iRODS in fixture setup
my @groups_added;
# Enable group tests
my $group_tests_enabled = 0;

# Reference filter for recognising the test reference
my $ref_regex = qr{\./t\/data\/almap_file_data_object\/test_ref.fa}msx;
my $ref_filter = sub {
  my ($line) = @_;
  return $line =~ m{$ref_regex}msx;
};

my $pid = $PID;

sub setup_databases : Test(startup) {
  my $wh_db_file = catfile($db_dir, 'ml_wh.db');
  $wh_schema = TestDB->new(verbose => 0)->create_test_db
    ('WTSI::DNAP::Warehouse::Schema', "$fixture_path/ml_warehouse",
     $wh_db_file);

  $lims_factory = WTSI::NPG::HTS::LIMSFactory->new(mlwh_schema => $wh_schema);
}

sub teardown_databases : Test(shutdown) {
  $wh_schema->storage->disconnect;
}

sub setup_test : Test(setup) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  $irods_tmp_coll =
    $irods->add_collection("AlMapFileDataObjectTest.$pid.$test_counter");
  $test_counter++;

  my $group_count = 0;
  foreach my $group (@irods_groups) {
    if ($irods->group_exists($group)) {
      $group_count++;
    }
    else {
      if ($have_admin_rights) {
        push @groups_added, $irods->add_group($group);
        $group_count++;
      }
    }
  }

  if ($group_count == scalar @irods_groups) {
    $group_tests_enabled = 1;
  }

  if ($samtools) {
    foreach my $data_file ($run7915_lane5_tag0, $run7915_lane5_tag1,
                           $run15440_lane1_tag0, $run15440_lane1_tag81) {
      WTSI::NPG::HTS::Samtools->new
          (arguments => ['view', '-C',
                         '-T', qq[$data_path/$reference_file],
                         '-o', qq[irods:$irods_tmp_coll/$data_file.cram]],
           path      => "$data_path/$data_file.sam")->run;

      WTSI::NPG::HTS::Samtools->new
          (arguments => ['view', '-b',
                         '-T', qq[$data_path/$reference_file],
                         '-o', qq[irods:$irods_tmp_coll/$data_file.bam]],
           path      => "$data_path/$data_file.sam")->run;

        foreach my $format (qw(bam cram)) {
          my $obj = WTSI::NPG::HTS::AlMapFileDataObject->new
            ($irods, "$irods_tmp_coll/$data_file.$format");

          my $num_reads = 10000;
          my @avus;
          push @avus, $obj->make_primary_metadata
            ($obj->id_run, $obj->position, $num_reads,
             tag_index      => $obj->tag_index,
             is_paired_read => 1,
             is_aligned     => $obj->is_aligned,
             reference      => $obj->reference);

          foreach my $avu (@avus) {
            my $attribute = $avu->{attribute};
            my $value     = $avu->{value};
            my $units     = $avu->{units};
            $obj->supersede_avus($attribute, $value, $units);
          }

          # Add some test group permissions
          if ($group_tests_enabled) {
            $obj->set_permissions($WTSI::NPG::iRODS::READ_PERMISSION,
                                  $public_group);

          foreach my $group (map { $group_prefix . $_ } (10, 100)) {
            $obj->set_permissions($WTSI::NPG::iRODS::READ_PERMISSION,
                                  $group);
          }
        }
      }
    }
  }
}

sub teardown_test : Test(teardown) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);
  $irods->remove_collection($irods_tmp_coll);

  if ($have_admin_rights) {
    foreach my $group (@groups_added) {
      if ($irods->group_exists($group)) {
        $irods->remove_group($group);
      }
    }
  }
}

sub require : Test(1) {
  require_ok('WTSI::NPG::HTS::AlMapFileDataObject');
}

my @tagged_paths   = ('/seq/17550/17550_3#1',
                      '/seq/17550/17550_3#1_human',
                      '/seq/17550/17550_3#1_nonhuman',
                      '/seq/17550/17550_3#1_xahuman',
                      '/seq/17550/17550_3#1_yhuman',
                      '/seq/17550/17550_3#1_phix');
my @untagged_paths = ('/seq/17550/17550_3',
                      '/seq/17550/17550_3_human',
                      '/seq/17550/17550_3_nonhuman',
                      '/seq/17550/17550_3_xahuman',
                      '/seq/17550/17550_3_yhuman',
                      '/seq/17550/17550_3_phix');

sub id_run : Test(24) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  foreach my $format (qw(bam cram)) {
    foreach my $path (@tagged_paths, @untagged_paths) {
      my $full_path = $path . ".$format";
      cmp_ok(WTSI::NPG::HTS::AlMapFileDataObject->new
             ($irods, $full_path)->id_run,
             '==', 17550, "$full_path id_run is correct");
    }
  }
}

sub position : Test(24) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  foreach my $format (qw(bam cram)) {
    foreach my $path (@tagged_paths, @untagged_paths) {
      my $full_path = $path . ".$format";
      cmp_ok(WTSI::NPG::HTS::AlMapFileDataObject->new
             ($irods, $full_path)->position,
             '==', 3, "$full_path position is correct");
    }
  }
}

sub contains_nonconsented_human : Test(24) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  foreach my $format (qw(bam cram)) {
    foreach my $path (@tagged_paths, @untagged_paths) {
      my $full_path = "$path.$format";
      my $obj = WTSI::NPG::HTS::AlMapFileDataObject->new($irods, $full_path);
      my $af = $obj->alignment_filter;

      if (not $af) {
        ok(!$obj->contains_nonconsented_human,
           "$full_path is not nonconsented human");
      }
      elsif ($af eq 'nonhuman' or
             $af eq 'yhuman'   or
             $af eq 'phix') {
        ok(!$obj->contains_nonconsented_human,
           "$full_path is not nonconsented human ($af)");
      }
      elsif ($af eq 'human' or
             $af eq 'xahuman') {
        ok($obj->contains_nonconsented_human,
           "$full_path is nonconsented human ($af)");
      }
      else {
        fail "Unexpected alignment_filter '$af'";
      }
    }
  }
}

sub is_restricted_access : Test(24) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  # Without any study metadata information
  foreach my $format (qw(bam cram)) {
    foreach my $path (@tagged_paths, @untagged_paths) {
      my $full_path = "$path.$format";
      my $obj = WTSI::NPG::HTS::AlMapFileDataObject->new($irods, $full_path);
      my $af = $obj->alignment_filter;

      if ($af and ($af eq 'human' or
                   $af eq 'xahuman')) {
        ok($obj->is_restricted_access, "$full_path is restricted_access");
      }
      else {
        ok(!$obj->is_restricted_access, "$full_path is not restricted_access");
      }
    }
  }
}

sub tag_index : Test(24) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  foreach my $format (qw(bam cram)) {
    foreach my $path (@tagged_paths) {
      my $full_path = $path . ".$format";
      cmp_ok(WTSI::NPG::HTS::AlMapFileDataObject->new
             ($irods, $full_path)->tag_index,
             '==', 1, "$full_path tag_index is correct");
    }
  }

  foreach my $format (qw(bam cram)) {
    foreach my $path (@untagged_paths) {
      my $full_path = $path . ".$format";
      isnt(defined WTSI::NPG::HTS::AlMapFileDataObject->new
           ($irods, $full_path)->tag_index,
           "$full_path tag_index is correct");
    }
  }
}

sub alignment_filter : Test(24) {
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

  foreach my $format (qw(bam cram)) {
    foreach my $path (@tagged_paths, @untagged_paths) {
      my $full_path = $path . ".$format";
      # FIXME -- use controlled vocbulary
      my ($expected) = $path =~ m{_((human|nonhuman|xahuman|yhuman|phix))};

      my $alignment_filter = WTSI::NPG::HTS::AlMapFileDataObject->new
        ($irods, $full_path)->alignment_filter;

      is($alignment_filter, $expected,
         "$full_path alignment_filter is correct");
    }
  }
}

sub header : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      strict_baton_version => 0);

    foreach my $data_file ($run7915_lane5_tag0, $run7915_lane5_tag1) {
      foreach my $format (qw(bam cram)) {
        my $obj = WTSI::NPG::HTS::AlMapFileDataObject->new
          (collection  => $irods_tmp_coll,
           data_object => "$data_file.$format",
           file_format => $format,
           id_run      => 1,
           irods       => $irods,
           position    => 1);

        # 2 * 2 * 1 tests
        ok($obj->header, "$format header can be read");

        # 2 * 2 * 1 tests
        cmp_ok(scalar @{$obj->header}, '==', 11,
               "Correct number of $format header lines") or
                 diag explain $obj->header;
      }
    }
  } # SKIP samtools
}

sub is_aligned : Test(4) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 4;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      strict_baton_version => 0);

    foreach my $data_file ($run7915_lane5_tag0, $run7915_lane5_tag1) {
      foreach my $format (qw(bam cram)) {
        my $obj = WTSI::NPG::HTS::AlMapFileDataObject->new
          (collection  => $irods_tmp_coll,
           data_object => "$data_file.$format",
           file_format => $format,
           id_run      => 1,
           irods       => $irods,
           position    => 1);

        # 2 * 2 * 1 tests
        ok($obj->is_aligned, "$format data are aligned");
      }
    }
  } # SKIP samtools
}

sub reference : Test(4) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 4;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      strict_baton_version => 0);

    foreach my $data_file ($run7915_lane5_tag0, $run7915_lane5_tag1) {
      foreach my $format (qw(bam cram)) {
        my $obj = WTSI::NPG::HTS::AlMapFileDataObject->new
          (collection  => $irods_tmp_coll,
           data_object => "$data_file.$format",
           file_format => $format,
           id_run      => 1,
           irods       => $irods,
           position    => 1);

        # 2 * 2 * 1 tests
        is($obj->reference($ref_filter), "$data_path/test_ref.fa",
           "$format reference is correct");
      }
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag0_no_spike_bact : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0,);

    my $tag0_expected_meta =
      [{attribute => $ALIGNMENT,                value => '1'},
       {attribute => $ID_RUN,                   value => '7915'},
       {attribute => $IS_PAIRED_READ,           value => '1'},
       {attribute => $POSITION,                 value => '5'},
       {attribute => $LIBRARY_ID,               value => '4957423'},
       {attribute => $LIBRARY_ID,               value => '4957424'},
       {attribute => $LIBRARY_ID,               value => '4957425'},
       {attribute => $LIBRARY_ID,               value => '4957426'},
       {attribute => $LIBRARY_ID,               value => '4957427'},
       {attribute => $LIBRARY_ID,               value => '4957428'},
       {attribute => $LIBRARY_ID,               value => '4957429'},
       {attribute => $LIBRARY_ID,               value => '4957430'},
       {attribute => $LIBRARY_ID,               value => '4957431'},
       {attribute => $LIBRARY_ID,               value => '4957432'},
       {attribute => $LIBRARY_ID,               value => '4957433'},
       {attribute => $LIBRARY_ID,               value => '4957434'},
       {attribute => $LIBRARY_ID,               value => '4957435'},
       {attribute => $LIBRARY_ID,               value => '4957436'},
       {attribute => $LIBRARY_ID,               value => '4957437'},
       {attribute => $LIBRARY_ID,               value => '4957438'},
       {attribute => $LIBRARY_ID,               value => '4957439'},
       {attribute => $LIBRARY_ID,               value => '4957440'},
       {attribute => $LIBRARY_ID,               value => '4957441'},
       {attribute => $LIBRARY_ID,               value => '4957442'},
       {attribute => $LIBRARY_ID,               value => '4957443'},
       {attribute => $LIBRARY_ID,               value => '4957444'},
       {attribute => $LIBRARY_ID,               value => '4957445'},
       {attribute => $LIBRARY_ID,               value => '4957446'},
       {attribute => $LIBRARY_ID,               value => '4957447'},
       {attribute => $LIBRARY_ID,               value => '4957448'},
       {attribute => $LIBRARY_ID,               value => '4957449'},
       {attribute => $LIBRARY_ID,               value => '4957450'},
       {attribute => $LIBRARY_ID,               value => '4957451'},
       {attribute => $LIBRARY_ID,               value => '4957452'},
       {attribute => $LIBRARY_ID,               value => '4957453'},
       {attribute => $LIBRARY_ID,               value => '4957454'},
       {attribute => $LIBRARY_ID,               value => '4957455'},
       {attribute => $QC_STATE,                 value => '1'},
       {attribute => $SAMPLE_NAME,              value => '619s040'},
       {attribute => $SAMPLE_NAME,              value => '619s041'},
       {attribute => $SAMPLE_NAME,              value => '619s042'},
       {attribute => $SAMPLE_NAME,              value => '619s043'},
       {attribute => $SAMPLE_NAME,              value => '619s044'},
       {attribute => $SAMPLE_NAME,              value => '619s045'},
       {attribute => $SAMPLE_NAME,              value => '619s046'},
       {attribute => $SAMPLE_NAME,              value => '619s047'},
       {attribute => $SAMPLE_NAME,              value => '619s048'},
       {attribute => $SAMPLE_NAME,              value => '619s049'},
       {attribute => $SAMPLE_NAME,              value => '619s050'},
       {attribute => $SAMPLE_NAME,              value => '619s051'},
       {attribute => $SAMPLE_NAME,              value => '619s052'},
       {attribute => $SAMPLE_NAME,              value => '619s053'},
       {attribute => $SAMPLE_NAME,              value => '619s054'},
       {attribute => $SAMPLE_NAME,              value => '619s055'},
       {attribute => $SAMPLE_NAME,              value => '619s056'},
       {attribute => $SAMPLE_NAME,              value => '619s057'},
       {attribute => $SAMPLE_NAME,              value => '619s058'},
       {attribute => $SAMPLE_NAME,              value => '619s059'},
       {attribute => $SAMPLE_NAME,              value => '619s060'},
       {attribute => $SAMPLE_NAME,              value => '619s061'},
       {attribute => $SAMPLE_NAME,              value => '619s062'},
       {attribute => $SAMPLE_NAME,              value => '619s063'},
       {attribute => $SAMPLE_NAME,              value => '619s064'},
       {attribute => $SAMPLE_NAME,              value => '619s065'},
       {attribute => $SAMPLE_NAME,              value => '619s066'},
       {attribute => $SAMPLE_NAME,              value => '619s067'},
       {attribute => $SAMPLE_NAME,              value => '619s068'},
       {attribute => $SAMPLE_NAME,              value => '619s069'},
       {attribute => $SAMPLE_NAME,              value => '619s070'},
       {attribute => $SAMPLE_NAME,              value => '619s071'},
       {attribute => $SAMPLE_NAME,              value => '619s072'},
       {attribute => $SAMPLE_COMMON_NAME,
        value     => 'Burkholderia pseudomallei'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '10/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '109/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '15/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '153.0'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '17/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '21/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '23/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '35/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '4009-19'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '4033-10'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '457/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '488.0'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '490.0'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '497/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '504/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '6/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '77/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '78/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '79/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'D107310-3154'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'D68346-3058'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'DB'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'DB30729/00'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'DB61091/00'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'DC'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'DR08726/01'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'DR13450/01'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'EM10266/01'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'EM2107'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'I64043-3096'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'K11277244-293'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'P73230-3018'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => 'SOIL'},
       {attribute => $STUDY_NAME,
        value     => 'Burkholderia pseudomallei diversity'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value => 'ERP000251'},
       {attribute => $STUDY_ID,                 value => '619'},
       {attribute => $STUDY_TITLE,
        value     => 'Burkholderia pseudomallei diversity' . $utf8_extra},
       {attribute => $TAG_INDEX,                value => '0'},
       {attribute => $TARGET,                   value => '0'}, # target 0
       {attribute => $TOTAL_READS,              value => '10000'}];

    my $spiked_control = 0;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run7915_lane5_tag0,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag0_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_619']});
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag0_spike_bact : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0,);

    my $tag0_expected_meta =
      [{attribute => $ALIGNMENT,                value     => '1'},
       {attribute => $ID_RUN,                   value     => '7915'},
       {attribute => $IS_PAIRED_READ,           value     => '1'},
       {attribute => $POSITION,                 value     => '5'},
       {attribute => $LIBRARY_ID,               value     => '3691209'}, # spike
       {attribute => $LIBRARY_ID,               value     => '4957423'},
       {attribute => $LIBRARY_ID,               value     => '4957424'},
       {attribute => $LIBRARY_ID,               value     => '4957425'},
       {attribute => $LIBRARY_ID,               value     => '4957426'},
       {attribute => $LIBRARY_ID,               value     => '4957427'},
       {attribute => $LIBRARY_ID,               value     => '4957428'},
       {attribute => $LIBRARY_ID,               value     => '4957429'},
       {attribute => $LIBRARY_ID,               value     => '4957430'},
       {attribute => $LIBRARY_ID,               value     => '4957431'},
       {attribute => $LIBRARY_ID,               value     => '4957432'},
       {attribute => $LIBRARY_ID,               value     => '4957433'},
       {attribute => $LIBRARY_ID,               value     => '4957434'},
       {attribute => $LIBRARY_ID,               value     => '4957435'},
       {attribute => $LIBRARY_ID,               value     => '4957436'},
       {attribute => $LIBRARY_ID,               value     => '4957437'},
       {attribute => $LIBRARY_ID,               value     => '4957438'},
       {attribute => $LIBRARY_ID,               value     => '4957439'},
       {attribute => $LIBRARY_ID,               value     => '4957440'},
       {attribute => $LIBRARY_ID,               value     => '4957441'},
       {attribute => $LIBRARY_ID,               value     => '4957442'},
       {attribute => $LIBRARY_ID,               value     => '4957443'},
       {attribute => $LIBRARY_ID,               value     => '4957444'},
       {attribute => $LIBRARY_ID,               value     => '4957445'},
       {attribute => $LIBRARY_ID,               value     => '4957446'},
       {attribute => $LIBRARY_ID,               value     => '4957447'},
       {attribute => $LIBRARY_ID,               value     => '4957448'},
       {attribute => $LIBRARY_ID,               value     => '4957449'},
       {attribute => $LIBRARY_ID,               value     => '4957450'},
       {attribute => $LIBRARY_ID,               value     => '4957451'},
       {attribute => $LIBRARY_ID,               value     => '4957452'},
       {attribute => $LIBRARY_ID,               value     => '4957453'},
       {attribute => $LIBRARY_ID,               value     => '4957454'},
       {attribute => $LIBRARY_ID,               value     => '4957455'},
       {attribute => $QC_STATE,                 value     => '1'},
       {attribute => $SAMPLE_NAME,              value     => '619s040'},
       {attribute => $SAMPLE_NAME,              value     => '619s041'},
       {attribute => $SAMPLE_NAME,              value     => '619s042'},
       {attribute => $SAMPLE_NAME,              value     => '619s043'},
       {attribute => $SAMPLE_NAME,              value     => '619s044'},
       {attribute => $SAMPLE_NAME,              value     => '619s045'},
       {attribute => $SAMPLE_NAME,              value     => '619s046'},
       {attribute => $SAMPLE_NAME,              value     => '619s047'},
       {attribute => $SAMPLE_NAME,              value     => '619s048'},
       {attribute => $SAMPLE_NAME,              value     => '619s049'},
       {attribute => $SAMPLE_NAME,              value     => '619s050'},
       {attribute => $SAMPLE_NAME,              value     => '619s051'},
       {attribute => $SAMPLE_NAME,              value     => '619s052'},
       {attribute => $SAMPLE_NAME,              value     => '619s053'},
       {attribute => $SAMPLE_NAME,              value     => '619s054'},
       {attribute => $SAMPLE_NAME,              value     => '619s055'},
       {attribute => $SAMPLE_NAME,              value     => '619s056'},
       {attribute => $SAMPLE_NAME,              value     => '619s057'},
       {attribute => $SAMPLE_NAME,              value     => '619s058'},
       {attribute => $SAMPLE_NAME,              value     => '619s059'},
       {attribute => $SAMPLE_NAME,              value     => '619s060'},
       {attribute => $SAMPLE_NAME,              value     => '619s061'},
       {attribute => $SAMPLE_NAME,              value     => '619s062'},
       {attribute => $SAMPLE_NAME,              value     => '619s063'},
       {attribute => $SAMPLE_NAME,              value     => '619s064'},
       {attribute => $SAMPLE_NAME,              value     => '619s065'},
       {attribute => $SAMPLE_NAME,              value     => '619s066'},
       {attribute => $SAMPLE_NAME,              value     => '619s067'},
       {attribute => $SAMPLE_NAME,              value     => '619s068'},
       {attribute => $SAMPLE_NAME,              value     => '619s069'},
       {attribute => $SAMPLE_NAME,              value     => '619s070'},
       {attribute => $SAMPLE_NAME,              value     => '619s071'},
       {attribute => $SAMPLE_NAME,              value     => '619s072'},
       {attribute => $SAMPLE_NAME,
        value     => "phiX_for_spiked_buffers"},
       {attribute => $SAMPLE_COMMON_NAME,
        value     => 'Burkholderia pseudomallei'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '10/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '109/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '15/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '153.0'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '17/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '21/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '23/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '35/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '4009-19'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '4033-10'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '457/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '488.0'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '490.0'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '497/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '504/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '6/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '77/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '78/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => '79/96'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'D107310-3154'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'D68346-3058'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'DB'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'DB30729/00'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'DB61091/00'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'DC'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'DR08726/01'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'DR13450/01'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'EM10266/01'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'EM2107'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'I64043-3096'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'K11277244-293'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'P73230-3018'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value     => 'SOIL'},
       {attribute => $STUDY_NAME,
        value     => 'Burkholderia pseudomallei diversity'},
       {attribute => $STUDY_NAME,
        value     => 'Illumina Controls'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value     => 'ERP000251'},
       {attribute => $STUDY_ID,                 value     => '198'},
       {attribute => $STUDY_ID,                 value     => '619'},
       {attribute => $STUDY_TITLE,
        value     => 'Burkholderia pseudomallei diversity' . $utf8_extra},
       {attribute => $TAG_INDEX,                value     => '0'},
       {attribute => $TARGET,                   value     => '0'}, # target 0
       {attribute => $TOTAL_READS,              value     => '10000'}];

    my $spiked_control = 1;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run7915_lane5_tag0,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag0_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_198',
                                                       'ss_619']});
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag1_no_spike_bact : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0);

    my $tag1_expected_meta =
      [{attribute => $ALIGNMENT,                value => '1'},
       {attribute => $ID_RUN,                   value => '7915'},
       {attribute => $IS_PAIRED_READ,           value => '1'},
       {attribute => $POSITION,                 value => '5'},
       {attribute => $LIBRARY_ID,               value => '4957423'},
       {attribute => $QC_STATE,                 value => '1'},
       {attribute => $SAMPLE_NAME,              value => '619s040'},
       {attribute => $SAMPLE_COMMON_NAME,
        value     => 'Burkholderia pseudomallei'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '153.0'},
       {attribute => $STUDY_NAME,
        value     => 'Burkholderia pseudomallei diversity'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value => 'ERP000251'},
       {attribute => $STUDY_ID,                 value => '619'},
       {attribute => $STUDY_TITLE,
        value     => 'Burkholderia pseudomallei diversity' . $utf8_extra},
       {attribute => $TAG_INDEX,                value => '1'},
       {attribute => $TARGET,                   value => '1'},
       {attribute => $TOTAL_READS,              value => '10000'}];

    my $spiked_control = 0;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run7915_lane5_tag1,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag1_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_619']});
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag1_spike_bact : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0);

    my $tag1_expected_meta =
      [{attribute => $ALIGNMENT,                value => '1'},
       {attribute => $ID_RUN,                   value => '7915'},
       {attribute => $IS_PAIRED_READ,           value => '1'},
       {attribute => $POSITION,                 value => '5'},
       {attribute => $LIBRARY_ID,               value => '4957423'},
       {attribute => $QC_STATE,                 value => '1'},
       {attribute => $SAMPLE_NAME,              value => '619s040'},
       {attribute => $SAMPLE_COMMON_NAME,
        value     => 'Burkholderia pseudomallei'},
       {attribute => $SAMPLE_PUBLIC_NAME,       value => '153.0'},
       {attribute => $STUDY_NAME,
        value     => 'Burkholderia pseudomallei diversity'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value => 'ERP000251'},
       {attribute => $STUDY_ID,                 value => '619'},
       {attribute => $STUDY_TITLE,
        value     => 'Burkholderia pseudomallei diversity' . $utf8_extra},
       {attribute => $TAG_INDEX,                value => '1'},
       {attribute => $TARGET,                   value => '1'},
       {attribute => $TOTAL_READS,              value => '10000'}];

    my $spiked_control = 1;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run7915_lane5_tag1,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag1_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_619']});
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag0_no_spike_human : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0);

    my $tag0_expected_meta =
      [{attribute => $ALIGNMENT,                value => '1'},
       {attribute => $ID_RUN,                   value => '15440'},
       {attribute => $IS_PAIRED_READ,           value => '1'},
       {attribute => $POSITION,                 value => '1'},
       {attribute => $LIBRARY_ID,               value => '12789790'},
       {attribute => $LIBRARY_ID,               value => '12789802'},
       {attribute => $LIBRARY_ID,               value => '12789814'},
       {attribute => $LIBRARY_ID,               value => '12789826'},
       {attribute => $QC_STATE,                 value => '1'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759041'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759045'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759048'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759062'},
       {attribute => $SAMPLE_COMMON_NAME,       value => 'Homo Sapien'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759041'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759045'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759048'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759062'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '6AJ182'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '7R5'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '8AJ1'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '8R163'},
       {attribute => $STUDY_NAME,
        value     => 'SEQCAP_Lebanon_LowCov-seq'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value => 'ERP005180'},
       {attribute => $STUDY_ID,                 value => '2967'},
       {attribute => $STUDY_TITLE,
        value     => 'Lebanon_LowCov-seq' . $utf8_extra},
       {attribute => $TAG_INDEX,                value => '0'},
       {attribute => $TARGET,                   value => '0'}, # target 0
       {attribute => $TOTAL_READS,              value => '10000'}];

    my $spiked_control = 0;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run15440_lane1_tag0,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag0_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_2967']});
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag0_spike_human : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0);

    my $tag0_expected_meta =
      [{attribute => $ALIGNMENT,                value => '1'},
       {attribute => $ID_RUN,                   value => '15440'},
       {attribute => $IS_PAIRED_READ,           value => '1'},
       {attribute => $POSITION,                 value => '1'},
       {attribute => $LIBRARY_ID,               value => '12789790'},
       {attribute => $LIBRARY_ID,               value => '12789802'},
       {attribute => $LIBRARY_ID,               value => '12789814'},
       {attribute => $LIBRARY_ID,               value => '12789826'},
       {attribute => $LIBRARY_ID,               value => '6759268'},
       {attribute => $QC_STATE,                 value => '1'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759041'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759045'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759048'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759062'},
       {attribute => $SAMPLE_NAME,
        value     => 'phiX_for_spiked_buffers'},
       {attribute => $SAMPLE_COMMON_NAME,       value => 'Homo Sapien'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759041'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759045'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759048'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759062'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '6AJ182'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '7R5'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '8AJ1'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '8R163'},
       {attribute => $STUDY_NAME,               value => 'Illumina Controls'},
       {attribute => $STUDY_NAME,
        value     => 'SEQCAP_Lebanon_LowCov-seq'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value => 'ERP005180'},
       {attribute => $STUDY_ID,                 value => '198'},
       {attribute => $STUDY_ID,                 value => '2967'},
       {attribute => $STUDY_TITLE,
        value     => 'Lebanon_LowCov-seq' . $utf8_extra},
       {attribute => $TAG_INDEX,                value => '0'},
       {attribute => $TARGET,                   value => '0'}, # target 0
       {attribute => $TOTAL_READS,              value => '10000'}];

    my $spiked_control = 1;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run15440_lane1_tag0,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag0_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_198',
                                                       'ss_2967']});
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag81_no_spike_human : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0);

    my $tag81_expected_meta =
      [{attribute => $ALIGNMENT,                value => '1'},
       {attribute => $ID_RUN,                   value => '15440'},
       {attribute => $IS_PAIRED_READ,           value => '1'},
       {attribute => $POSITION,                 value => '1'},
       {attribute => $LIBRARY_ID,               value => '12789790'},
       {attribute => $QC_STATE,                 value => '1'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759041'},
       {attribute => $SAMPLE_COMMON_NAME,       value => 'Homo Sapien'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759041'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '7R5'},
       {attribute => $STUDY_NAME,
        value     => 'SEQCAP_Lebanon_LowCov-seq'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value => 'ERP005180'},
       {attribute => $STUDY_ID,                 value => '2967'},
       {attribute => $STUDY_TITLE,
        value     => 'Lebanon_LowCov-seq' . $utf8_extra},
       {attribute => $TAG_INDEX,                value => '81'},
       {attribute => $TARGET,                   value => '1'},
       {attribute => $TOTAL_READS,              value => '10000'}];

    my $spiked_control = 0;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run15440_lane1_tag81,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag81_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_2967']});
    }
  } # SKIP samtools
}

sub update_secondary_metadata_tag81_spike_human : Test(8) {
 SKIP: {
    if (not $samtools) {
      skip 'samtools executable not on the PATH', 8;
    }

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      group_prefix         => $group_prefix,
                                      group_filter         => $group_filter,
                                      strict_baton_version => 0);

    my $tag81_expected_meta =
      [{attribute => $ALIGNMENT,                value => '1'},
       {attribute => $ID_RUN,                   value => '15440'},
       {attribute => $IS_PAIRED_READ,           value => '1'},
       {attribute => $POSITION,                 value => '1'},
       {attribute => $LIBRARY_ID,               value => '12789790'},
       {attribute => $QC_STATE,                 value => '1'},
       {attribute => $SAMPLE_NAME,              value => 'T19PG5759041'},
       {attribute => $SAMPLE_COMMON_NAME,       value => 'Homo Sapien'},
       {attribute => $SAMPLE_DONOR_ID,          value => 'T19PG5759041'},
       {attribute => $SAMPLE_SUPPLIER_NAME,     value => '7R5'},
       {attribute => $STUDY_NAME,
        value     => 'SEQCAP_Lebanon_LowCov-seq'},
       {attribute => $STUDY_ACCESSION_NUMBER,   value => 'ERP005180'},
       {attribute => $STUDY_ID,                 value => '2967'},
       {attribute => $STUDY_TITLE,
        value     => 'Lebanon_LowCov-seq' . $utf8_extra},
       {attribute => $TAG_INDEX,                value => '81'},
       {attribute => $TARGET,                   value => '1'},
       {attribute => $TOTAL_READS,              value => '10000'}];

    my $spiked_control = 1;

    foreach my $format (qw(bam cram)) {
      # 2 * 4 tests
      test_metadata_update($irods, $irods_tmp_coll, $ref_filter,
                           {data_file              => $run15440_lane1_tag81,
                            format                 => $format,
                            spiked_control         => $spiked_control,
                            expected_metadata      => $tag81_expected_meta,
                            expected_groups_before => [$public_group,
                                                       'ss_10',
                                                       'ss_100'],
                            expected_groups_after  => ['ss_2967']});
    }
  } # SKIP samtools
}

sub test_metadata_update {
  my ($irods, $working_coll, $ref_filter, $args) = @_;

  ref $args eq 'HASH' or croak "The arguments must be a HashRef";

  my $data_file      = $args->{data_file};
  my $format         = $args->{format};
  my $spiked         = $args->{spiked_control};
  my $exp_metadata   = $args->{expected_metadata};
  my $exp_grp_before = $args->{expected_groups_before};
  my $exp_grp_after  = $args->{expected_groups_after};

  my $obj = WTSI::NPG::HTS::AlMapFileDataObject->new
    (collection  => $working_coll,
     data_object => "$data_file.$format",
     irods       => $irods);
  my $tag = $obj->tag_index;

  my @groups_before = $obj->get_groups;
  ok($obj->update_secondary_metadata($lims_factory, $spiked, $ref_filter),
     "Secondary metadata ran; format: $format, tag: $tag, spiked: $spiked");
  my @groups_after = $obj->get_groups;

  my $metadata = $obj->metadata;
  is_deeply($metadata, $exp_metadata,
            "Secondary metadata was updated; format: $format, " .
            "tag: $tag, spiked: $spiked")
    or diag explain $metadata;

 SKIP: {
    if (not $group_tests_enabled) {
      skip 'iRODS test groups were not present', 2;
    }
    else {
      is_deeply(\@groups_before, $exp_grp_before,
                'Groups before update') or diag explain \@groups_before;

      is_deeply(\@groups_after, $exp_grp_after,
                'Groups after update') or diag explain \@groups_after;
    }
  } # SKIP groups_added
}

1;
