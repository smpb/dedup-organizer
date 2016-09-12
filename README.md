# Image Deduplication Organizer

Simple image file deduplication (and organizer) tool, through MD5 and Perceptual Hashes for images.


## Non-Core Perl Dependencies

  - DBI
  - DBD::SQLite
  - Image::Hash
  - Image::ExifTool
  - File::Copy::Recursive


## How-to

  1. `perl dedup-organizer.pl --setup    [--verbose]`
  2. `perl dedup-organizer.pl --analize  [--verbose]`
  3. `perl dedup-organizer.pl --organize [--verbose]`

or just...

  - `perl dedup-organizer.pl --setup --analyze --organize [--verbose]`

