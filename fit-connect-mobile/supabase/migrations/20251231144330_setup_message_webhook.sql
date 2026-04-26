-- Enable the pg_net extension to allow making HTTP requests from database triggers
create extension if not exists "pg_net" with schema "extensions";

