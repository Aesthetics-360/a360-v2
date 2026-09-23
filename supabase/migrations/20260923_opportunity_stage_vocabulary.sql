-- Opportunity Board — drop `booked`, rename `ready_to_book` to `wants_to_book`.
--
-- Chris, 2026-09-23: "We're not going to know if they're booked or not. We're
-- just trying to identify opportunities here."
--
-- A360 observes the consultation, not the schedule. A `booked` stage was a
-- claim the system has no way to substantiate - nothing in the pipeline can
-- ever set it truthfully, so it could only ever be a human guess dressed as
-- extracted fact. `ready_to_book` had the same problem in weaker form: it reads
-- as a practice-side readiness judgement. `wants_to_book` states only what a
-- consultation can actually evidence - the patient asked to schedule.
--
-- The status vocabulary (open/won/lost/abandoned) is unchanged and stays
-- CRM-shaped. `won` simply becomes unreachable from this board, which is
-- correct: winning is a booking, and the board cannot see bookings.

begin;

alter table opportunities drop constraint if exists opp_stage_valid;

update opportunities
   set stage = 'wants_to_book'
 where stage in ('ready_to_book', 'booked');

alter table opportunities
  add constraint opp_stage_valid
  check (stage is null or stage in ('identified', 'discussed', 'considering', 'wants_to_book'));

commit;
