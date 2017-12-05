# Image Deduplicator & Organizer

Simple image file deduplication (and organizer) tool, through MD5 and Perceptual Hashes for images.


## How-to

First,

  1. `cpanm Carton`
  2. `carton install`

Then,

  1. `perl dedup-organizer.pl --setup    [--verbose]`
  2. `perl dedup-organizer.pl --analize  [--verbose]`
  3. `perl dedup-organizer.pl --organize [--verbose] [--move] [--dry-run]`

or just...

  - `perl dedup-organizer.pl --setup --analyze --organize [--verbose] [--move] [--dry-run]`


## Non-Core Perl Dependencies

  - DBI
  - DBD::SQLite
  - Image::Hash
  - Image::ExifTool
  - File::Copy::Recursive

