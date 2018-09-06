# Image Deduplicator & Organizer

Simple image file deduplication (and organizer) tool, through MD5 and image hashing.


## How-to

First,

  1. `cpanm Carton`
  2. `carton install`
  3. `./install-imagemagick-perl` (this is optional: see below)

Then,

  1. `perl dedup-organizer.pl --setup    [--verbose]`
  2. `perl dedup-organizer.pl --analize  [--verbose]`
  3. `perl dedup-organizer.pl --organize [--verbose] [--move] [--dry-run]`

or just...

  - `perl dedup-organizer.pl --setup --analyze --organize [--verbose] [--move] [--dry-run]`


## Image Hashing Options

This tool uses the `Image::Hash` package naively for the purposes of image hashing. The module supports a number of image processing backends, and by default the tool will depend on `GD` out of the box. It has proven to be the easiest to add and the fastest, but it is the least compatible with diverse image formats.

The ideal choice is `Image::Magick`, however this package seems to be mostly abandoned on CPAN making its installation a considerable hassle these days. Thanks to [an article](http://perltricks.com/article/57/2014/1/1/Shazam-Use-Image-Magick-with-Perlbrew-in-minutes) addressing this issue, a [shell script is available](https://gist.github.com/zmughal/8264712) to automate that task.

I have incorporated it (with attribution) in this repository, and modified it to the tool's needs:

 - `./install-imagemagick-perl`


## Non-Core Perl Dependencies

  - [DBI](https://metacpan.org/pod/DBI)
  - [DBD::SQLite](https://metacpan.org/pod/DBD::SQLite)
  - [Image::Hash](https://metacpan.org/pod/Image::Hash)
  - [Image::ExifTool](https://metacpan.org/pod/Image::ExifTool)
  - [File::Copy::Recursive](https://metacpan.org/pod/File::Copy::Recursive)

