-- LOCAL DISPOSABLE RESTORE ONLY. Never apply to DIGIY CORE production.
-- Exact upstream migration scripts pinned to supabase/storage v1.80.2.
-- This Docker image's migration runner skips both s3_multipart_uploads tables.
-- Their original definitions are restored using the official SQL unchanged,
-- plus verified type contract below. No COPY rows are discarded.
-- BEGIN official supabase/storage v1.80.2: migrations/tenant/0021-s3-multipart-uploads.sql
CREATE TABLE IF NOT EXISTS storage.s3_multipart_uploads (
    id text PRIMARY KEY,
    in_progress_size int NOT NULL default 0,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL references storage.buckets(id),
    key text COLLATE "C" NOT NULL ,
    version text NOT NULL,
    owner_id text NULL,
    created_at timestamptz NOT NULL default now()
);

CREATE TABLE IF NOT EXISTS storage.s3_multipart_uploads_parts (
     id uuid PRIMARY KEY default gen_random_uuid(),
     upload_id text NOT NULL references storage.s3_multipart_uploads(id) ON DELETE CASCADE,
     size int NOT NULL default 0,
     part_number int NOT NULL,
     bucket_id text NOT NULL references storage.buckets(id),
     key text COLLATE "C" NOT NULL,
     etag text NOT NULL,
     owner_id text NULL,
     version text NOT NULL,
     created_at timestamptz NOT NULL default now()
);

CREATE INDEX IF NOT EXISTS idx_multipart_uploads_list
    ON storage.s3_multipart_uploads (bucket_id, (key COLLATE "C"), created_at ASC);

CREATE OR REPLACE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer default 100, next_key_token text DEFAULT '', next_upload_token text default '')
    RETURNS TABLE (key text, id text, created_at timestamptz) AS
$$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    anon_role text = COALESCE(current_setting('storage.anon_role', true), 'anon');
    authenticated_role text = COALESCE(current_setting('storage.authenticated_role', true), 'authenticated');
    service_role text = COALESCE(current_setting('storage.service_role', true), 'service_role');
BEGIN
    EXECUTE 'revoke all on storage.s3_multipart_uploads from ' || anon_role || ', ' || authenticated_role;
    EXECUTE 'revoke all on storage.s3_multipart_uploads_parts from ' || anon_role || ', ' || authenticated_role;
    EXECUTE 'GRANT ALL ON TABLE storage.s3_multipart_uploads TO ' || service_role;
    EXECUTE 'GRANT ALL ON TABLE storage.s3_multipart_uploads_parts TO ' || service_role;
    EXECUTE 'GRANT SELECT ON TABLE storage.s3_multipart_uploads TO ' || authenticated_role || ', ' || anon_role;
    EXECUTE 'GRANT SELECT ON TABLE storage.s3_multipart_uploads_parts TO ' || authenticated_role || ', ' || anon_role;
END$$;
-- END migrations/tenant/0021-s3-multipart-uploads.sql

-- BEGIN official supabase/storage v1.80.2: migrations/tenant/0022-s3-multipart-uploads-big-ints.sql
ALTER TABLE storage.s3_multipart_uploads ALTER COLUMN in_progress_size TYPE bigint;
ALTER TABLE storage.s3_multipart_uploads_parts ALTER COLUMN size TYPE bigint;
-- END migrations/tenant/0022-s3-multipart-uploads-big-ints.sql

-- BEGIN official supabase/storage v1.80.2: migrations/tenant/0025-custom-metadata.sql
ALTER TABLE storage.objects ADD COLUMN IF NOT EXISTS user_metadata jsonb NULL;
ALTER TABLE storage.s3_multipart_uploads ADD COLUMN IF NOT EXISTS user_metadata jsonb NULL;
-- END migrations/tenant/0025-custom-metadata.sql

-- BEGIN official supabase/storage v1.80.2: migrations/tenant/0057-s3-multipart-uploads-metadata.sql
ALTER TABLE storage.s3_multipart_uploads ADD COLUMN IF NOT EXISTS metadata jsonb NULL;
-- END migrations/tenant/0057-s3-multipart-uploads-metadata.sql

-- Assert required compatible s3 tables exist and match real catalog types.
DO $digiy_storage_contract$
BEGIN
  IF to_regclass('storage.s3_multipart_uploads') IS NULL
     OR to_regclass('storage.s3_multipart_uploads_parts') IS NULL
     OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'storage.s3_multipart_uploads'::regclass
          AND attname='in_progress_size' AND atttypid='pg_catalog.int8'::regtype
          AND NOT attisdropped
     )
     OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'storage.s3_multipart_uploads_parts'::regclass
          AND attname='size' AND atttypid='pg_catalog.int8'::regtype
          AND NOT attisdropped
     )
     OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'storage.s3_multipart_uploads'::regclass
          AND attname='user_metadata' AND atttypid='pg_catalog.jsonb'::regtype
          AND NOT attisdropped
     )
     OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'storage.s3_multipart_uploads'::regclass
          AND attname='metadata' AND atttypid='pg_catalog.jsonb'::regtype
          AND NOT attisdropped
     )
  THEN
    RAISE EXCEPTION 'DIGIY_LOCAL_STORAGE_MULTIPART_CONTRACT_MISMATCH';
  END IF;
END;
$digiy_storage_contract$;
