-- Simplified NUQ schema for Supabase
-- Run this SQL in your Supabase SQL Editor

-- Create the extensions (pgcrypto should be available)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create the nuq schema
CREATE SCHEMA IF NOT EXISTS nuq;

-- Create the job_status enum type
DO $$ BEGIN
  CREATE TYPE nuq.job_status AS ENUM ('queued', 'active', 'completed', 'failed');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Create the main queue table
CREATE TABLE IF NOT EXISTS nuq.queue_scrape (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  status nuq.job_status NOT NULL DEFAULT 'queued'::nuq.job_status,
  data jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  priority int NOT NULL DEFAULT 0,
  lock uuid,
  locked_at timestamp with time zone,
  stalls integer,
  finished_at timestamp with time zone,
  returnvalue jsonb, -- only for selfhost
  failedreason text, -- only for selfhost
  CONSTRAINT queue_scrape_pkey PRIMARY KEY (id)
);

-- Optimize the table for frequent updates
ALTER TABLE nuq.queue_scrape
SET (autovacuum_vacuum_scale_factor = 0.01,
     autovacuum_analyze_scale_factor = 0.01,
     autovacuum_vacuum_cost_limit = 2000,
     autovacuum_vacuum_cost_delay = 2);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS queue_scrape_active_locked_at_idx 
ON nuq.queue_scrape USING btree (locked_at) 
WHERE (status = 'active'::nuq.job_status);

CREATE INDEX IF NOT EXISTS nuq_queue_scrape_queued_optimal_2_idx 
ON nuq.queue_scrape (priority ASC, created_at ASC, id) 
WHERE (status = 'queued'::nuq.job_status);

CREATE INDEX IF NOT EXISTS nuq_queue_scrape_failed_created_at_idx 
ON nuq.queue_scrape USING btree (created_at) 
WHERE (status = 'failed'::nuq.job_status);

CREATE INDEX IF NOT EXISTS nuq_queue_scrape_completed_created_at_idx 
ON nuq.queue_scrape USING btree (created_at) 
WHERE (status = 'completed'::nuq.job_status);

-- Note: Cron jobs are commented out as they may not be available in Supabase
-- You can set up these cleanup jobs using Supabase Edge Functions or Database Webhooks if needed:

-- Clean up completed jobs older than 1 hour:
-- DELETE FROM nuq.queue_scrape WHERE status = 'completed' AND created_at < now() - interval '1 hour';

-- Clean up failed jobs older than 6 hours:
-- DELETE FROM nuq.queue_scrape WHERE status = 'failed' AND created_at < now() - interval '6 hours';

-- Handle stalled jobs (jobs locked for more than 1 minute):
-- UPDATE nuq.queue_scrape SET status = 'queued', lock = null, locked_at = null, stalls = COALESCE(stalls, 0) + 1 
-- WHERE locked_at <= now() - interval '1 minute' AND status = 'active' AND COALESCE(stalls, 0) < 9;
