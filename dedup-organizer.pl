#!perl

use v5.10;
use strict;
use warnings;

use DBI;
use Storable qw/nfreeze thaw/;

use File::Find;
use File::Slurp;
use File::Basename;
use File::Copy::Recursive 'fcopy';
use Getopt::Long;

use Image::Hash;
use Digest::MD5;
use Image::ExifTool 'ImageInfo';

use Data::Dumper;

# global

my $dbh;
my $opt_verbose;
my $opt_config;
my $opt_analyze;
my $opt_organize;
my $config = {
  db   => 'photos.db',
  dirs => {
    src => [ './imgs' ],
    dst => './sorted',
  }
};

# functions

sub load_cfg {
  my $file_cfg = shift;

  open (my $fh, '<', $file_cfg) or die "Can't open '$file_cfg': $!";
  my $contents = do { local $/; <$fh> };
  close $fh;

  my $loaded_cfg = eval $contents;
  foreach my $key (keys %{$loaded_cfg}) {
    $config->{$key} = $loaded_cfg->{$key};
  }
}

sub image_info {
  my $file = shift;

  my $exif = ImageInfo($file);
  return unless $exif->{FileType};

  delete $exif->{ThumbnailImage}; # binary data I don't need

  #print "$file : " . Dumper $exif;

  my $image = read_file($file, binmode => ':raw' ) ;

  # file hash
  my $md5 = Digest::MD5->new->add($image)->hexdigest;

  # image hash
  my $hash = '';
  if (lc $exif->{FileType} ne 'mov') {
    my $iHash = Image::Hash->new($image);
    $hash = $iHash->phash();
  } else {
    $hash = $md5;
  }

  # date the image
  my $date;

  my $f_md = $exif->{FileModifyDate} || '';
  my $md   = $exif->{ModifyDate}     || '';
  for my $string (($f_md, $file, $md)) {
    if ($string =~ /(\d+)[-:_\.]+(\d+)[-:_\.]+(\d+)[-:_\.\s]+(\d+)[-:_\.]+(\d+)[-:_\.]*(\d*)/i) {
      $date = {
        year => $1,
        mon  => $2,
        day  => $3,
        hour => $4,
        min  => $5,
        sec  => $6,
      };
    }
  }

  # camera used
  my $camera = '';
  if ($exif->{Make} || $exif->{Model}) {
    $camera = "$exif->{Make} $exif->{Model}";
    $camera =~ s/^\s//g;
    $camera =~ s/\s$//g;
    $camera =~ s/\s/-/g;
  }

  return {
    exif   => $exif,
    hash   => $hash,
    md5    => $md5,
    date   => $date,
    camera => $camera,
  };
}

sub db {
  state $dbh;

  unless ( $dbh ) {
    $dbh = DBI->connect("DBI:SQLite:dbname=".$config->{db}, "", "", {RaiseError => 1}) or die $DBI::errstr;
    print Dumper $dbh;
  }

  return $dbh;
}

sub filter {
  my $file = $_;
  my $dir  = $File::Find::dir;
  my $src  = $File::Find::name;

  state $current_dir = '';

  return if ($file eq '.' or $file eq '..');

  if ($current_dir ne $dir) {
    $current_dir = $dir;
    say "Analysing directory '$current_dir' ...";
  }

  my $info = image_info( $file );

  if ($info) {
    my($filename, $dirs, $suffix) = fileparse( $file, qr/\.[^.]*/ );

    my $name   .= join('-', ($info->{date}{year}, $info->{date}{mon}, $info->{date}{day})) . '_';
    $name      .= join('.', ($info->{date}{hour}, $info->{date}{min}, $info->{date}{sec}));
    $name      .= $info->{camera} ? '_' . $info->{camera} : '';
    $name      .= $suffix;

    my $dst = join('/',
      ($info->{date}{year}, $info->{date}{mon}, $info->{date}{day}, $name)
    );

    my $data_exif = nfreeze($info->{exif});
    my $data_date = nfreeze($info->{date});

    if ($opt_verbose) {
      say "Storing : MD5 '$info->{md5}' | HASH '$info->{hash}' | EXIF '". length($data_exif)  ."' | '$src' -> '$dst'";
    } else {
      say "Storing info about '$src'...";
    }

    my $stmt = "INSERT INTO photos (md5, hash, exif, date, camera, source, destination) VALUES (?,?,?,?,?,?,?)";
    my $sth  = $dbh->prepare($stmt);
    my $res  = $sth->execute(
      $info->{md5},
      $info->{hash},
      $data_exif,
      $data_date,
      $info->{camera},
      $src,
      $dst,
    );
  }

}

sub organize {
    my $sth  = $dbh->prepare('SELECT * FROM photos;');
    my $res  = $sth->execute();

    my $photos = {};

    if ($res) {
      say "Organizing stored information ...";

      while(my $photo = $sth->fetchrow_hashref()) {
        #print Dumper $photo;

        my $key = $photo->{hash};
        say "Using key '$key' to identify the item '$photo->{source}'." if $opt_verbose;

        my $use_it = 1;
        if (exists $photos->{$key}) {
          if ($photos->{$key}{md5} eq $photo->{md5}) {
            say "Found an exact duplicate, ignoring it..." if $opt_verbose;
            $use_it = 0;
          } else {
            $use_it = length($photo->{exif}) > length($photos->{$key}{exif});
            my $name = $use_it ? $photo->{source} : $photos->{$key}{source};
            say "Found a partial duplicate, using '$name' for its larger EXIF." if $opt_verbose;
          }
        }

        if ( $use_it ) { $photos->{$key} = $photo; }
      }

      my $total = scalar(keys %$photos);
      say "Found '$total' unique items ...";

      if ($total) {
        for my $photo (values %$photos) {
          my $src = $photo->{source};
          my $dst = join('/', ($config->{dirs}{dst}, $photo->{destination}));
          say "Creating a copy of '$src' in '$dst'";
          fcopy($src, $dst);
        }
      }
    }
}

# main

# sudo port install gd2;sudo port install libvpx

GetOptions (
  "config=s"  => \$opt_config,
  "verbose"     => \$opt_verbose,
  "analyze"   => \$opt_analyze,
  "organize"  => \$opt_organize
);

&load_cfg($opt_config) if $opt_config;

$dbh = DBI->connect("dbi:SQLite:dbname=$config->{db}", "", "", {RaiseError => 1}) or die $DBI::errstr;
if ($opt_analyze)  { find( \&filter, @{$config->{dirs}{src}} ); }
if ($opt_organize) { organize();  }

unless ($opt_analyze || $opt_organize) { say "Nothing to do ..."; } else { say "All done!"; }




