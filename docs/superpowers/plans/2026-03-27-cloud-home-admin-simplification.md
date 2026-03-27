# Cloud Home Admin Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the public cloud homepage from the internal admin console so `/` becomes a clean status entry page and `/admin` becomes a minimal account-admin surface.

**Architecture:** Keep the existing runtime data sources for database, ASR, LLM, and admin session state. Refactor the App Router pages so the homepage renders a dedicated status layout while `/admin` renders the trimmed admin console directly. Remove invite-code and legacy-management UI from the admin component instead of hiding it behind conditionals.

**Tech Stack:** Next.js App Router, React Server Components, TypeScript/TSX, CSS, node:test

---

### Task 1: Lock in the homepage/admin split with a failing route-level test

**Files:**
- Create: `cloud/api/app/page.test.mts`
- Modify: `cloud/api/app/page.tsx`
- Modify: `cloud/api/app/admin/page.tsx`

- [ ] **Step 1: Write a failing test that asserts the homepage no longer references invite-code/admin bulk UI and `/admin` is no longer a redirect shell**
- [ ] **Step 2: Run the route-level test and verify it fails for the current implementation**
  Run: `cd cloud/api && node --test app/page.test.mts`
- [ ] **Step 3: Implement the minimal page split**
- [ ] **Step 4: Re-run the route-level test**
  Run: `cd cloud/api && node --test app/page.test.mts`

### Task 2: Trim `AdminConsole` down to the minimum viable account admin

**Files:**
- Modify: `cloud/api/app/admin/AdminConsole.tsx`
- Test: `cloud/api/app/page.test.mts`

- [ ] **Step 1: Extend the failing test to assert invite-code and legacy-management content are removed while login/password-reset remains**
- [ ] **Step 2: Run the route/component test and verify it fails for the current admin console**
  Run: `cd cloud/api && node --test app/page.test.mts`
- [ ] **Step 3: Remove invite-code, legacy takeover, managed-user creation, and deployment instruction sections**
- [ ] **Step 4: Keep only admin login, summary, account list, reset password, and logout**
- [ ] **Step 5: Re-run the route/component test**
  Run: `cd cloud/api && node --test app/page.test.mts`

### Task 3: Restyle the homepage and admin page to match the approved A1 direction

**Files:**
- Modify: `cloud/api/app/page.tsx`
- Modify: `cloud/api/app/globals.css`
- Modify: `cloud/api/app/admin/AdminConsole.tsx`

- [ ] **Step 1: Write a failing assertion for the new homepage copy and admin entry CTA if the existing test coverage is not enough**
- [ ] **Step 2: Run the focused test to verify the expected text is not present yet**
  Run: `cd cloud/api && node --test app/page.test.mts`
- [ ] **Step 3: Implement the A1 homepage copy, status cards, endpoint links, and `/admin` CTA**
- [ ] **Step 4: Simplify shared styles so the homepage is calm and the admin page remains readable without the current clutter**
- [ ] **Step 5: Re-run the focused test**
  Run: `cd cloud/api && node --test app/page.test.mts`

### Task 4: Final verification

**Files:**
- Verify only

- [ ] **Step 1: Run the focused cloud-page test**
  Run: `cd cloud/api && node --test app/page.test.mts`
- [ ] **Step 2: Build the cloud app**
  Run: `cd cloud/api && npm run build`
- [ ] **Step 3: Spot-check the running UI in a browser or with route fetches**
  Verify: `/` shows the clean status page and `/admin` shows the minimal admin surface
- [ ] **Step 4: Summarize residual risks**
  Focus: copy drift, missing admin status details, and any CSS regressions between homepage and admin page
