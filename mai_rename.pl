#!/usr/bin/env perl
# Rename zip files in current dir if they contain a psvita param.sfo
# http://www.vitadevwiki.com/index.php?title=System_File_Object_(SFO)_(PSF)

use strict;
use warnings;
use Archive::Zip;
use Archive::Zip::MemberRead;
use File::Copy;

# Some region_code/country relations.
my $regions = { 'PCSB' => 'EUR'  , 'VCES' => 'EUR'  , 'VLES' => 'EUR' , 'PCSF' => 'EUR'
              , 'PCSE' => 'USA'  , 'PCSA' => 'USA'  , 'PCSD' => 'USA' , 'VCUS' => 'USA' , 'VLUS' => 'USA'
              , 'PCSG' => 'JAP'  , 'PCSC' => 'JAP'  , 'VCJS' => 'JAP' , 'VLJM' => 'JAP' , 'VLJS' => 'JAP'
              , 'PCSH' => 'ASIA' , 'VCAS' => 'ASIA' , 'VLAS' => 'ASIA'
              };

# Return the contents of param.sfo as a hash
sub parse_sfo {
  my $slurp = shift;
  # Get the magic and position of the keys and data tables
  my ($magic, $key_offset, $data_offset) = unpack("H8 x4 I I", $slurp);
  return 0 unless $magic eq '00505346'; # Not a sfo file
  # Get a slice with the keys table
  my $key_bytes = substr($slurp, $key_offset, $data_offset-$key_offset);
  # The table is made of strings separated for the null character
  my @keys = split("\000", $key_bytes);
  print "SFO: key_offset:$key_offset data_offset:$data_offset keys:".scalar @keys."\n" if $ARGV[0];

  my $href;
  # Get a slice of the params table for each key
  foreach my $key (@keys) {
    # First slice beginst at 20 bytes and each one is 16 bytes long
    my $param_bytes = substr($slurp, 20+(16*$href->{COUNT}++), 16);
    # Get the length and position of the current param
    my ($param_length, $param_offset) = unpack("x4 I x4 I", $param_bytes);
    # Get a slice with the current param, clean it and assign it as our value
    my $value = substr($slurp, $data_offset+$param_offset, $param_length);
    $value =~ s/[\000\n\r\/]//g;
    $href->{$key} = $value;
  }

  my $regcode = substr($href->{TITLE_ID}, 0, 4);
  $href->{REGION} = $regions->{$regcode} || 'UNK';
  return $href;
}

# Get all the zip files on current dir
opendir(DIR, ".");
my @files = grep(/\.zip$/i, readdir(DIR));
closedir(DIR);

# Process every zip file
foreach my $file (@files) {
  my $zip = Archive::Zip->new();
  die "Can't read zip file '$file'\n" unless $zip->read($file) == 0;
  my $new_name;
  my $app_ver = '0.00';
  # Look for param.sfo files
  foreach my $member ($zip->membersMatching('.*param\.sfo$')) {
    my $buffer;
    my $bytes = $member->readFileHandle()->read($buffer);
    print "Readed $bytes bytes from '".$member->fileName()."'$file''\n" if $ARGV[0];
    # Get the info from the param.sfo file
    my $info = parse_sfo $buffer;
    map { print "$_ -> '$info->{$_}'\n" } sort keys %{ $info } if $ARGV[0];
    # We are only interested in the 'gp' and 'gd' categories
    if ($info->{CATEGORY} && $info->{CATEGORY} eq "gp" || $info->{CATEGORY} eq "gd") {
      # We will keep the highest app_ver from all valid sfos
      $app_ver = $info->{APP_VER} if $info->{APP_VER} gt $app_ver;
      $new_name = "$info->{TITLE} [$info->{TITLE_ID}] ($info->{APP_VER}) ($info->{REGION}).zip";
    }
  }
  # Print and move the file if we got a valid name
  next unless $new_name;
  print "'$file' -> '$new_name'\n";
  move($file, $new_name) or die "File could not be moved!\n";
}
