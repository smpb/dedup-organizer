--
-- Table structure for photo information
--
DROP TABLE IF EXISTS photos;
CREATE TABLE photos (
    id           INTEGER       PRIMARY KEY  AUTOINCREMENT,
    md5          VARCHAR(50)   NOT NULL     DEFAULT '',
    hash         VARCHAR(50)   NOT NULL     DEFAULT '',
    exif         BLOB          NOT NULL     DEFAULT '',
    date         BLOB          NOT NULL     DEFAULT '',
    camera       VARCHAR(50)   NOT NULL     DEFAULT '',
    source       VARCHAR(255)  NOT NULL     DEFAULT '',
    destination  VARCHAR(255)  NOT NULL     DEFAULT ''
);
CREATE INDEX IDX_MD5  ON photos (md5);
CREATE INDEX IDX_HASH ON photos (hash);
