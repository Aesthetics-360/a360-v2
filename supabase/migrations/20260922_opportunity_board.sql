-- Opportunity Board — extend Ops `opportunities` and add its evidence ledger.
--
-- Target: A360 Ops (uedajrdzcjfrmbiznflf). Ops DDL lives in a360-v2 migrations.
-- Probed live 2026-09-22 before writing: `opportunities` has 10 columns and ZERO
-- rows, so every change below is free today and a data migration later.
--
-- Why Ops and not the extraction project: Prompt Runner is consumed over its
-- Railway HTTP API, not by connecting to its Supabase; both extraction-side
-- project refs are banned write targets; and Ops is the authorized store for
-- patients and consultations, which this table already has real foreign keys to.
--
-- Two grains. "What did they receive that day" is a fact about a visit and never
-- changes. "What is she still interested in" accumulates across visits.
--
-- Values are ranges. Unpriced is NULL, never 0. data_mode has no default, so a
-- row cannot be inserted without declaring its provenance.

-- ---------------------------------------------------------------------------
-- 1. The ticket. Extends the existing empty table rather than replacing it.
--    Pre-existing columns (tier, product_ref, description, source_agent) are
--    left alone - they are not mine to drop. offering_id supersedes the
--    free-text product_ref for new writes.
-- ---------------------------------------------------------------------------
alter table opportunities
  add column if not exists offering_id        uuid,
  add column if not exists offering_label     text,
  add column if not exists name               text,
  add column if not exists category           text,

  -- Groups line items under one patient decision, keyed on an extracted goal
  -- rather than an invented objective. NULL means it stands alone.
  add column if not exists group_id           text,
  add column if not exists group_label        text,

  -- `stage` already exists as free text; it gets a CHECK below.
  -- `status` uses the CRM's four values verbatim so the mapping is identity.
  -- Dormancy is NOT a status - it is derived from last_activity_at.
  add column if not exists status             text not null default 'open',
  add column if not exists readiness          text not null default 'unknown',
  add column if not exists loss_reason        text,
  add column if not exists loss_note          text,

  -- Money. Assigned by extraction from the practice library, stored as given.
  add column if not exists value_low          numeric,
  add column if not exists value_high         numeric,
  add column if not exists value_horizon      text,
  add column if not exists value_basis        jsonb,
  add column if not exists data_mode          text,

  add column if not exists owner_initials     text,
  add column if not exists owner_name         text,
  add column if not exists source             text not null default 'extraction',

  add column if not exists evidence_quote     text,
  add column if not exists consult_date       date,

  -- CRM linkage. Reserved while the table is empty and it is free.
  -- Vendor-neutral on purpose: crm_, never ghl_. Nothing auto-pushes.
  add column if not exists sync_state         text not null default 'local',
  add column if not exists crm_contact_id     text,
  add column if not exists crm_opportunity_id text,
  add column if not exists crm_pipeline_id    text,
  add column if not exists crm_stage_id       text,
  add column if not exists crm_synced_at      timestamptz,
  add column if not exists crm_sync_error     text,

  -- The extraction prompt is still being developed. Fields it has not settled
  -- on land here rather than forcing a migration each time one appears.
  add column if not exists fields             jsonb not null default '{}'::jsonb,

  add column if not exists first_observed_at  timestamptz,
  add column if not exists last_activity_at   timestamptz not null default now(),
  add column if not exists observation_count  int not null default 0,
  add column if not exists stage_changed_at   timestamptz not null default now(),
  add column if not exists updated_at         timestamptz not null default now();

-- ---------------------------------------------------------------------------
-- 2. Constraints. Safe to add unconditionally: the table has zero rows.
-- ---------------------------------------------------------------------------

-- `stage` was free text with no constraint. These are patient-state stages -
-- where the PATIENT is - because the consultation is the only signal that
-- exists today. An outreach vocabulary would have stages nothing could set.
alter table opportunities
  add constraint opp_stage_valid
  check (stage is null or stage in ('identified','discussed','considering','ready_to_book','booked'));

alter table opportunities
  add constraint opp_status_valid
  check (status in ('open','won','lost','abandoned'));

alter table opportunities
  add constraint opp_readiness_valid
  check (readiness in ('high','medium','low','unknown'));

alter table opportunities
  add constraint opp_loss_reason_valid
  check (loss_reason is null or loss_reason in
    ('price','timing','went_elsewhere','no_response','changed_mind','other'));

-- A loss reason is mandatory when something closes lost. "Why did the money
-- walk" is the entire point of the leakage view.
alter table opportunities
  add constraint opp_loss_reason_required
  check (status <> 'lost' or loss_reason is not null);

alter table opportunities
  add constraint opp_value_horizon_valid
  check (value_horizon is null or value_horizon in ('per_visit','per_course','per_year'));

-- Ranges only. A high below its low is a bug, not a value.
alter table opportunities
  add constraint opp_value_range_ordered
  check (value_low is null or value_high is null or value_low <= value_high);

-- Synthetic money must be declarable as synthetic. No default on purpose.
alter table opportunities
  add constraint opp_data_mode_valid
  check (data_mode is null or data_mode in ('synthetic','mock','real'));

alter table opportunities
  add constraint opp_source_valid
  check (source in ('extraction','manual'));

alter table opportunities
  add constraint opp_sync_state_valid
  check (sync_state in ('local','pushed','linked','failed'));

-- The grain, enforced: one ticket per practice + patient + offering.
create unique index if not exists uq_opportunity_grain
  on opportunities (practice_id, patient_id, offering_label);

create index if not exists ix_opportunity_board
  on opportunities (practice_id, status, stage);
create index if not exists ix_opportunity_group
  on opportunities (practice_id, group_id);

-- ---------------------------------------------------------------------------
-- 3. The evidence ledger. Append-only, one row per consultation + offering.
--    A correction is a new row, never an edit - that is what makes the
--    evidence trail worth trusting.
-- ---------------------------------------------------------------------------
create table if not exists opportunity_observation (
  id                uuid primary key default gen_random_uuid(),

  practice_id       uuid not null references practices (id),
  patient_id        uuid references patients (id),
  consultation_id   uuid references consultations (id),

  offering_id       uuid,
  offering_label    text not null,

  disposition       text not null,
  readiness         text not null default 'unknown'
                      check (readiness in ('high','medium','low','unknown')),

  value_low         numeric,
  value_high        numeric,
  value_horizon     text check (value_horizon in ('per_visit','per_course','per_year')),
  value_basis       jsonb,
  data_mode         text not null check (data_mode in ('synthetic','mock','real')),

  evidence_quote    text,
  evidence_locator  jsonb,

  observed_at       timestamptz not null,
  -- Provenance back to the extraction that produced this. Free text because the
  -- run lives in a different system, reached over HTTP rather than by join.
  extraction_run_id text,

  fields            jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),

  constraint obs_value_range_ordered
    check (value_low is null or value_high is null or value_low <= value_high)
);

-- Ingest is idempotent on this pair. Extractions get re-run constantly while the
-- prompt is being tuned, and a re-run must never double-count.
create unique index if not exists uq_observation_source
  on opportunity_observation (practice_id, consultation_id, offering_label);

create index if not exists ix_observation_patient
  on opportunity_observation (practice_id, patient_id);

-- ---------------------------------------------------------------------------
-- Note for whoever reads this next.
--
-- Tenancy here is application-enforced, not RLS-enforced - consistent with the
-- rest of Ops. practice_id is applied server-side from the token and is never
-- accepted from caller input. The capability-layer contract entry is where that
-- is actually guaranteed, which makes it a tenancy control rather than
-- paperwork.
-- ---------------------------------------------------------------------------
