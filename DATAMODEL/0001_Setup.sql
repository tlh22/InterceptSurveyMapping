-- Create post code sectors

-- load codepoint into db
/***
UPDATE public.codepoint
SET postcode_sector = left(postcode, -2);

ALTER TABLE IF EXISTS public.codepoint
    ADD COLUMN postcode_sector character varying;
***/

DROP TABLE IF EXISTS public.postcode_sectors CASCADE;

CREATE TABLE public.postcode_sectors
(
  gid SERIAL,
  postcode_sector character varying,
  geom geometry(Point,27700),
  CONSTRAINT "RC_Sections_merged_pkey" PRIMARY KEY (gid)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE public.postcode_sectors
  OWNER TO postgres;

-- Index: public."sidx_RC_Sections_merged_geom"

-- DROP INDEX public."sidx_RC_Sections_merged_geom";

CREATE INDEX "sidx_postcode_sectors_geom"
  ON public.postcode_sectors
  USING gist
  (geom);

INSERT INTO public.postcode_sectors (postcode_sector, geom)
SELECT postcode_sector, st_centroid(st_union(geom)) as geom
FROM public.codepoint
GROUP BY postcode_sector;

-- sort out postcode formats, etc

UPDATE mhtc_operations."InterviewPostcodes"
SET "Postcode"=UPPER("Postcode")
;

-- replace full postcodes with postcode sectors

SELECT "Postcode", REGEXP_MATCHES("Postcode", '^([A-Za-z]{1,2})([0-9]{1,2})\s([0-9]{1,2})([A-Za-z]{2})', 'g')
FROM mhtc_operations."InterviewPostcodes"
;

SELECT "Postcode", REGEXP_REPLACE("Postcode", '^([A-Za-z]{1,2})([0-9]{1,2})\s([0-9]{1,2})([A-Za-z]{2})', '\1\2 \3', 'g')
FROM mhtc_operations."InterviewPostcodes"
ORDER BY "Postcode"

-- *** not sure what to do with postcode areas ??



---***** Set up link to OS_ONS_Bids db

--On foreign db:
CREATE USER fdwUser WITH PASSWORD 'secret';
GRANT toms_public TO fdwUser;
GRANT SELECT,USAGE ON ALL SEQUENCES IN SCHEMA public TO toms_public;
GRANT USAGE ON SCHEMA public TO toms_public;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO toms_public;

--check
--psql -U fdwUser -d 'OS_ONS_Bids'

--On local db
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SERVER ons_os_fdw FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', port '5436', dbname 'OS_ONS_Bids');

CREATE USER localUser WITH PASSWORD 'secret';
GRANT USAGE ON SCHEMA PUBLIC TO localUser;

CREATE USER MAPPING FOR postgres SERVER ons_os_fdw OPTIONS (user 'fdwuser', password 'secret');
GRANT USAGE ON FOREIGN SERVER ons_os_fdw TO postgres;
IMPORT FOREIGN SCHEMA public FROM SERVER ons_os_fdw INTO public;

--- Now create local table(s)


DROP TABLE IF EXISTS mhtc_operations."InterviewResults";

CREATE TABLE mhtc_operations."InterviewResults"
(
  gid SERIAL,
  "Postcode_Sector" character varying COLLATE pg_catalog."default",
  "Count" integer,
  geom geometry(Point,27700),
  CONSTRAINT "InterviewResults_pkey" PRIMARY KEY (gid)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE mhtc_operations."InterviewResults"
  OWNER TO postgres;

CREATE INDEX "sidx_InterviewResults_geom"
  ON mhtc_operations."InterviewResults"
  USING gist
  (geom);

INSERT INTO mhtc_operations."InterviewResults" ("Postcode_Sector", "Count", geom)
    SELECT "Postcode_Sector", "Count", s.geom
	FROM
	( SELECT "Postcode" As "Postcode_Sector", COUNT("Postcode") AS "Count"
	  FROM mhtc_operations."InterviewPostcodes" 
	  GROUP BY "Postcode" ) i, public.postcode_sectors s
	WHERE i."Postcode_Sector" = s."postcode_sector";

ALTER TABLE mhtc_operations."InterviewResults"
    OWNER TO postgres;

CREATE INDEX interview_results_postcode_sectors ON mhtc_operations."InterviewResults"
(
    "Postcode_Sector"
);

CREATE TABLE mhtc_operations."InterviewResultsByTown"
(
  gid SERIAL,
  "Town" character varying COLLATE pg_catalog."default",
  "Postcode_Sector" character varying COLLATE pg_catalog."default",
  "Count" integer,
  geom geometry(Point,27700),
  CONSTRAINT "InterviewResultsByTown_pkey" PRIMARY KEY (gid)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE mhtc_operations."InterviewResultsByTown"
  OWNER TO postgres;

CREATE INDEX "sidx_InterviewResultsByTown_geom"
  ON mhtc_operations."InterviewResultsByTown"
  USING gist
  (geom);

INSERT INTO mhtc_operations."InterviewResults" ("Town", "Postcode_Sector", "Count", geom)
    SELECT i."Town", "Postcode_Sector", "Count", s.geom
	FROM
	( SELECT "Town", "Postcode" As "Postcode_Sector", COUNT("Postcode") AS "Count"
	  FROM mhtc_operations."InterviewPostcodes" 
	  GROUP BY "Town", "Postcode" ) i, public.postcode_sectors s
	WHERE i."Postcode_Sector" = s."postcode_sector";

ALTER TABLE mhtc_operations."InterviewResultsByTown"
    OWNER TO postgres;

CREATE INDEX interview_results_by_town_postcode_sectors ON mhtc_operations."InterviewResultsByTown"
(
    "Postcode_Sector"
);