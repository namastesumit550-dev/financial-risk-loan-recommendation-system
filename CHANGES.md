# Changelog

This project went through two rounds of fixes. Round 1 got the frontend built and the app
runnable end-to-end. Round 2 (this one) closed the remaining gaps: a data/code mismatch, missing
business logic, an unused persistence layer, missing tests, and repo hygiene.

## Round 2 — this pass

**Bug fixes**
- `calculation_service.get_loan_products()` hardcoded only 3 of the 5 products in
  `data/bank_products/sample_bank_products.csv` (Bank D and E were invisible to the whole app).
  Now loads all 5 from the CSV at runtime (cached after first read), with a 3-product hardcoded
  fallback only if the CSV can't be read at all.
- `loan_type` was collected in every request but never used to filter products — a borrower asking
  for an "Education Loan" was scored against personal/home loan products too. Both
  `eligibility_service.py` and `recommendation_service.py` now filter to the requested loan type
  first, falling back to the full catalog if no product of that type exists (e.g. "Auto Loan" isn't
  in the sample catalog yet).
- `LoanProductResponse` schema was missing `product_id` even though the route always returned it;
  the products route now properly declares `response_model=List[LoanProductResponse]`.

**New: persistence layer**
- `database/schema.sql` + `backend/models/db_models.py` existed but nothing ever wrote to Postgres.
  `db_models.py` was also missing 5 of the 7 tables the schema defines. Added:
  - The missing `User`, `FinancialProfile`, `RiskPrediction`, `Recommendation`,
    `UserPreferenceRecord` models (now matches `schema.sql` exactly).
  - `backend/database.py` — engine/session setup that degrades to a no-op `NullSession` if
    Postgres/psycopg2 aren't available, so the API never crashes because of the database.
  - `backend/services/persistence_service.py` — best-effort logging called from every analysis
    route. Any failure (DB down, driver missing, connection refused) is caught and logged, never
    raised.
  - `database/seed.sql` — seeds `banks`/`loan_products` to match the CSV catalog, so persisted
    `recommendations` rows (which have a foreign key to `loan_products.product_id`) don't violate
    the constraint.
  - Known limitation (documented in README): each endpoint persists its own profile row rather
    than sharing one row per "Analyze profile" click.

**Testing**
- `tests/conftest.py` — shared `sample_profile` fixture.
- `tests/test_eligibility_service.py`, `tests/test_recommendation_service.py` — previously zero
  coverage on the two most business-logic-heavy services.
- `tests/test_api.py` — HTTP-level tests via FastAPI's `TestClient` against all 5 endpoints,
  including a CORS check and two validation-error (422) cases.
- `frontend/src/utils/format.test.js`, `validation.test.js` — pure-logic tests; every expected
  value was verified by actually running the formatting/validation code in Node, not hand-computed.
- `frontend/src/components/BorrowerForm.test.jsx` — render, valid-submit, validation-blocks-submit,
  and disabled-while-submitting cases.
- Added `@testing-library/react`, `@testing-library/jest-dom`, `@testing-library/user-event` to
  `frontend/package.json` devDependencies (previously absent, so `npm test` had nothing to run
  against even if test files existed).
- Not covered: `HomePage`/`ExplainabilityChart` (react-plotly.js needs Jest transform config CRA
  doesn't expose without ejecting) and true browser/e2e tests.

**Docker / infra**
- `docker/Dockerfile.backend` now also `COPY data ./data` — `calculation_service.py` reads the CSV
  at runtime, and the image wasn't shipping that file.
- `docker-compose.yml` — added healthchecks for `db` (`pg_isready`) and `backend`; `backend` now
  waits for `condition: service_healthy` on `db` instead of just "container started."
- Root `Dockerfile` — added a comment clarifying it's a separate, standalone single-container image
  for PaaS deploys, distinct from `docker/Dockerfile.backend` used by docker-compose.
- Added `.dockerignore` (`.venv`, `node_modules`, `.git`, `data/raw`, `data/processed`, etc.) so
  builds don't upload gigabytes of irrelevant context to the Docker daemon.

**Repo hygiene**
- Removed `.venv/` (a full Windows virtualenv, ~14MB) and `.pytest_cache/` — both had been
  committed by accident.
- Deleted `Untitled-1.py` (a one-line `print("heyy")` scratch file).
- Added root `.gitignore`.
- Added `backend/routes/__init__.py`, `schemas/__init__.py`, `services/__init__.py`,
  `models/__init__.py` — these subpackages relied on Python's implicit namespace packages, which
  works but was inconsistent with `backend/__init__.py` existing.
- Trimmed `requirements.txt`: removed `xgboost`, `catboost`, `shap` (confirmed unused anywhere in
  the codebase via grep — they were pulled in for a model that's never trained/loaded); added
  `httpx` (required by FastAPI's `TestClient`, used in the new `test_api.py`).
- Rewrote `README.md` to describe what's actually implemented, including the heuristic-vs-ML
  decision, the best-effort persistence design, and how to run the tests.

## Round 1 — earlier pass

- Built out the entire frontend from an empty skeleton: `services/api.js`, `utils/`, all
  components, `HomePage.jsx`/`App.jsx`.
- Added CORS middleware to `backend/main.py` (was completely missing — every browser request from
  the frontend was being blocked regardless of frontend code).
- Fixed `docker/Dockerfile.backend` and `Dockerfile.frontend`, which used `COPY ../...` — Docker
  forbids copying from outside the build context, so `docker-compose up` couldn't build at all.
  Also fixed a `WORKDIR` change in the backend Dockerfile that broke `backend.main`'s absolute
  imports.
- Fixed `docker-compose.yml`: added the missing `dockerfile:` fields, corrected the frontend volume
  mount path, and added an anonymous `node_modules` volume so the host's (empty) copy doesn't
  shadow the one installed in the image.
- Deleted a stray, empty `frontend/node_modules` that had shipped in the original zip.

## What's still open

See the "Known gaps / next steps" section in README.md — mainly: the `ml/` pipeline is unwired
(intentional heuristic-vs-trained-model decision, not a bug), no CI, and no production frontend
build path in Docker.
