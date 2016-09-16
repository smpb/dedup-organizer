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
use Time::Local;
use List::Util 'max';

use Image::Hash;
use Digest::MD5;
use Image::ExifTool 'ImageInfo';

# global

my $opt_setup;
my $opt_config;
my $opt_verbose;
my $opt_analyze;
my $opt_organize;

my $dbh;
my $config = {
  db   => 'photos.db',
  dirs => {
    src => [ './imgs' ],
    dst => './sorted',
  },
  apps   => [ qw/Android Instagram Snapseed Moldiv Hellolab Camera+ Photosynth Squaready VSCOcam FxCam/ ],
  binary => [ qw/PreviewImage PhotoshopThumbnail ThumbnailImage RedTRC BlueTRC GreenTRC/ ],
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

sub setup_db {
  say "Setting up database file ...";

  while (my $sql = <DATA>) {
    print $sql if $opt_verbose;
    $dbh->do($sql);
  }
}

sub image_info {
  my $file = shift;

  my $exif = ImageInfo($file);
  return unless $exif->{FileType};

  # binary data we don't need
  for my $tag (@{$config->{binary}}) {
    delete $exif->{$tag};
  }

  my $image = read_file($file, binmode => ':raw' );

  # camera used
  $exif->{Camera} = '';
  if ($exif->{Model}) {
    $exif->{Camera} = $exif->{Model};
    if ($exif->{Make}) {
      my @make = split m{[\/\\\-:_\.\s]}, $exif->{Make};
      my $m_pat = join('|', map { quotemeta $_ } @make);

      if ($exif->{Model} !~ /$m_pat/i) {
        $exif->{Camera} = "$exif->{Make} $exif->{Model}";
      }
    }
    $exif->{Camera} =~ s/^\s//g;
    $exif->{Camera} =~ s/\s$//g;
    $exif->{Camera} =~ s/\s/-/g;
  }

  # file hash
  my $md5 = Digest::MD5->new->add($image)->hexdigest;

  my $hash = '';
  if ($exif->{MIMEType} =~ /image/i) { # mostly ignore videos

    # image hash
    eval {
      my $iHash = Image::Hash->new($image);
      $hash = $iHash->phash();
    }; say "ERROR: $@" if $@;

    # custom rendering options for iPhone:
    #  4 : original image
    #  3 : HDR image
    #  6 : panorama image
    if (($exif->{Camera} =~ /Apple/i) && $exif->{CustomRendered} && ($exif->{CustomRendered} =~ /(\d+)/)) {
      my $render_v = $1;
      $exif->{HDR}      = 1 if ($render_v == 3);
      $exif->{Panorama} = 1 if ($render_v == 6);
    }

    # panorama double check
    my $min_pano_ratio = 16 / 9;
    if (($exif->{ImageWidth}) && ($exif->{ImageHeight})) {
      my $ratio = max(
        ($exif->{ImageWidth}  / $exif->{ImageHeight}),
        ($exif->{ImageHeight} / $exif->{ImageWidth}),
      );
      $exif->{Panorama} = 1 if ($ratio > $min_pano_ratio);
    }

    # custom fields (subject to change...)
    my $app;
    my $s_pat = join('|', map { quotemeta $_ } @{$config->{apps}});

    if ($file =~ /($s_pat)/) { $exif->{App} = $1; }

    if ($exif->{Software}) {
      $app = $exif->{Software};
      $app =~ s/[\(\)\[\]\-\d\.]+//g;
      $app =~ s/\s+/ /g;
      $app =~ s/^\s//g;
      $app =~ s/\s$//g;
      $app =~ s/\s/-/g;

      if ($app && $app =~ /$s_pat/i) {
        $exif->{App} = $app;
      }
    }
    if (($exif->{FileName}    && $exif->{FileName}    =~ /captura\s*de\s*ecr/i) ||
        ($exif->{FileName}    && $exif->{FileName}    =~ /screen\s*shot/i)      ||
        ($exif->{UserComment} && $exif->{UserComment} =~ /screen\s*shot/i)) {
      $exif->{App} = 'Screenshot';
    }
  }

  $hash = $md5 unless $hash;

  # date the image
  my $date;

  my $f_md = $exif->{FileModifyDate} || '';
  my $md   = $exif->{ModifyDate}     || '';
  for my $string (($f_md, $file, $md)) {
    if ($string =~ /(\d+)[-:_\.]+(\d+)[-:_\.]+(\d+)[-:_\.\s]+(\d+)[-:_\.]+(\d+)[-:_\.]*(\d*)/i) {
      eval { my $sec = $6 || 0; timelocal( $sec+0, $5+0, $4+0, $3+0, $2-1, $1+0 ) };

      if ($@ && $opt_verbose) { say "NOTICE: Found invalid date '$string' on '$file' ..."; }

      unless ( $@ ) {
        $date = {
          year => $1,
          mon  => $2,
          day  => $3,
          hour => $4,
          min  => $5,
          sec  => $6,
        };
        $date->{sec} = '00' unless $date->{sec};
      }
    }
  }

  return {
    exif => $exif,
    hash => $hash,
    md5  => $md5,
    date => $date,
  };
}

sub analyze {
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

    my $name .= join('-', ($info->{date}{year}, $info->{date}{mon}, $info->{date}{day})) . '_';
       $name .= join('.', ($info->{date}{hour}, $info->{date}{min}, $info->{date}{sec}));
       $name .= $info->{exif}{App}      ? '_' . $info->{exif}{App}    : '';
       $name .= $info->{exif}{Camera}   ? '_' . $info->{exif}{Camera} : '';
       $name .= $info->{exif}{HDR}      ? '_HDR'        : '';
       $name .= $info->{exif}{Panorama} ? '_Panorama'   : '';
       $name .= lc $suffix;

    # final name sanitization, just to be safe
    my $cleaner = qr{\<|\>|\:|\"|\'|\/|\\|\||\?|\*};
    $name =~ s/$cleaner/-/g;

    my $dst = join('/',
      ($info->{date}{year}, $info->{date}{mon}, $info->{date}{day}, $name)
    );

    my $data_exif = nfreeze($info->{exif});
    my $data_date = nfreeze($info->{date});

    my $stmt = "INSERT OR REPLACE INTO photos (md5, hash, exif, date, source, destination) VALUES (?,?,?,?,?,?)";
    my $sth  = $dbh->prepare($stmt);
    my $res  = $sth->execute(
      $info->{md5},
      $info->{hash},
      $data_exif,
      $data_date,
      $src,
      $dst,
    );

    if ( $res ) {
      if ($opt_verbose) {
        say "Stored : MD5 '$info->{md5}' | HASH '$info->{hash}' | EXIF '". length($data_exif)  ."' | '$src' -> '$dst'";
      } else {
        say "Stored info about '$src' ...";
      }
    } else {
      say "ERROR: Unable to store info about '$src'; $DBI::errstr"
    }
  }

}

sub organize {
    my $sth  = $dbh->prepare('SELECT * FROM photos;');
    my $res  = $sth->execute();

    my $photos = {};

    if ($res) {
      say "Organizing stored information ...";

      while(my $photo = $sth->fetchrow_hashref()) {
        my $key = $photo->{hash};
        say "Using key '$key' to identify the item '$photo->{source}'." if $opt_verbose;

        my $use_it = 1;
        if (exists $photos->{$key}) {
          $use_it = length($photo->{exif}) > length($photos->{$key}{exif});
          my $name = $use_it ? $photo->{source} : $photos->{$key}{source};
          say "NOTICE: Found a partial duplicate, using '$name' for its larger EXIF." if $opt_verbose;
        }

        unless (-e $photo->{source}) {
          say "WARNING: Item '$photo->{source}' no longer exists, ignoring it!";
          $use_it = 0;
        }

        if ( $use_it ) { $photos->{$key} = $photo; }
      }

      my $total = scalar(keys %$photos);
      say "Organizing '$total' unique items ...";

      if ($total) {
        for my $photo (values %$photos) {
          my $src = $photo->{source};
          my $dst = join('/', ($config->{dirs}{dst}, $photo->{destination}));
          if (-e $dst) {
            my $count = 0;
            my $new_dst = $dst;

            do {
              my($filename, $dirs, $suffix) = fileparse( $dst, qr/\.[^.]*/ );
              $count++; $new_dst = $dirs . $filename . "_$count" . $suffix;
            } while (-e $new_dst);

            $dst = $new_dst;
          }
          fcopy($src, $dst);
          say "Created a copy of '$src' in '$dst'";
        }
      }
    }
}

# main

GetOptions (
  "setup"     => \$opt_setup,
  "config=s"  => \$opt_config,
  "verbose"   => \$opt_verbose,
  "analyze"   => \$opt_analyze,
  "organize"  => \$opt_organize
);

load_cfg($opt_config) if $opt_config;

$dbh = DBI->connect("dbi:SQLite:dbname=$config->{db}", "", "", {PrintError => 0}) or die $DBI::errstr;

if ($opt_setup)    { setup_db(); }
if ($opt_analyze)  { find( \&analyze, @{$config->{dirs}{src}} ); }
if ($opt_organize) { organize(); }

unless ($opt_setup || $opt_analyze || $opt_organize) { say "Nothing to do ..."; } else { say "All done!"; }

__DATA__
DROP TABLE IF EXISTS photos;
CREATE TABLE photos (md5 VARCHAR(50) PRIMARY KEY, hash VARCHAR(50), exif BLOB, date BLOB, source VARCHAR(255), destination VARCHAR(255));
CREATE INDEX IDX_MD5  ON photos (md5);
CREATE INDEX IDX_HASH ON photos (hash);
