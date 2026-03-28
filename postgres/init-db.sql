-- This script runs once on first container start (empty data directory).
-- It creates the bifrost_logs database alongside the bifrost_config database
-- that was already created by the POSTGRES_DB environment variable.
--
-- Both databases use UTF8 encoding via template0 as required by Bifrost.
-- See: https://docs.getbifrost.ai/quickstart/gateway/setting-up#postgresql-utf8-requirement

CREATE DATABASE bifrost_logs
  WITH TEMPLATE template0
       ENCODING 'UTF8'
       LC_COLLATE 'C.UTF-8'
       LC_CTYPE 'C.UTF-8';
