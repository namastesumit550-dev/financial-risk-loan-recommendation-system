# AI-Powered Financial Risk Prediction and Personalized Loan Recommendation System

A final-year BE Artificial Intelligence & Data Science project combining a risk-assessment API, a
personalized loan-recommendation engine, and a bank product comparison dashboard.

## What it does

Given a borrower's financial and credit profile, the system:

- predicts a risk score (0–100) and category (Low/Medium/High)
- explains what's driving that score (a SHAP-style feature breakdown)
- checks eligibility against every loan product of the requested type
- computes EMI, total interest, total repayment, and processing fee per product
- ranks products by the borrower's stated preferences (lower EMI vs. lower total cost vs.
  shorter tenure, etc.) and highlights the best match

## Architecture

- **`backend/`** — FastAPI app. `main.py` wires up routes + CORS; `routes/` are thin HTTP
  handlers; `services/` hold the actual business logic (EMI math, risk scoring, eligibility,
  ranking); `schemas/` are the pydantic request/response contracts; `models/db_models.py` are the
  SQLAlchemy ORM models.
- **`frontend/`** — React (Create React App) dashboard: a borrower-profile form plus panels for
  risk, explainability, eligibility, and ranked recommendations. `src/services/api.js` is the only
  file that talks to the backend.
- **`database/`** — `schema.sql` (table definitions) + `seed.sql` (the 5-bank product catalog,
  seeded so it matches what the API serves). Both run automatically on first Postgres start via
  `docker-entrypoint-initdb.d`.
- **`data/bank_products/sample_bank_products.csv`** — the single source of truth for the loan
  product catalog. `calculation_service.py` reads this file at runtime; `database/seed.sql` mirrors
  it for the Postgres side. If you add/change a product, update both.
- **`ml/`, `notebooks/`, `data/raw/`, `data/processed/`** — the data-science groundwork (a real
  preprocessing pipeline built on the UCI German Credit dataset, with a synthetic
  `risk_target`-labeled dataset already prepared). **Not currently wired into the live API** — see
  "Design decisions" below.
- **`docker/`** — `Dockerfile.backend` / `Dockerfile.frontend`, used by `docker-compose.yml` for
  local multi-container development. The root-level `Dockerfile` is a separate, standalone
  single-container backend image for PaaS platforms that deploy from a root Dockerfile directly.

## Design decisions worth knowing

- **The risk model is a deterministic heuristic, not a trained ML model.** `ml_service.py` scores
  risk from weighted borrower features (credit score, previous defaults, late payments, debt
  burden, credit utilization, employment stability, savings). This is intentional — no `joblib`,
  no model artifacts to ship — but it means `xgboost`/`catboost`/`shap`/a trained `scikit-learn`
  model are **not** part of the live request path, even though the data-prep pipeline for training
  one already exists in `ml/`. If you want real ML predictions, `ml/prepare_data.py` +
  `ml/preprocessing.py` are a working starting point; you'd still need to write a training script
  and load the serialized model in `ml_service.py`.
- **Products are filtered by the borrower's requested loan type**, falling back to the full
  catalog if no product of that type exists yet (e.g. "Auto Loan" isn't in the sample catalog).
  See `filter_products_by_loan_type()` in `calculation_service.py`.
- **Persistence is best-effort.** Every analysis endpoint tries to log the request to Postgres
  (`financial_profiles` + `risk_predictions`/`recommendations`/`user_preferences`), but a database
  outage never breaks the response — see `backend/database.py` and
  `backend/services/persistence_service.py`. This also means: if you run the backend with plain
  `uvicorn` and no Postgres, everything still works, it just isn't logged anywhere. One known
  simplification: each endpoint call persists its own `financial_profiles` row rather than sharing
  one row across a single "Analyze profile" click (which fires all four endpoints), so one borrower
  submission currently produces multiple profile rows.

## Running it

**Docker (recommended — starts Postgres too):**
```bash
docker-compose up --build
```
Frontend: http://localhost:3000 · Backend: http://localhost:8000

**Locally, without Docker:**
```bash
# terminal 1 — backend (Postgres is optional; persistence just no-ops without it)
pip install -r requirements.txt
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000

# terminal 2 — frontend
cd frontend
cp .env.example .env
npm install
npm start
```

## Testing

```bash
# backend — unit tests for calculations/risk/eligibility/recommendation logic,
# plus HTTP-level tests against every endpoint via FastAPI's TestClient
pytest

# frontend — pure-logic tests (utils/format.js, utils/validation.js) and a
# BorrowerForm component test
cd frontend && npm test
```
Not covered yet: `HomePage`/`ExplainabilityChart` component tests (react-plotly.js needs extra
Jest transform config that CRA doesn't expose without ejecting), and true end-to-end/browser tests.

## API endpoints

| Method | Path                  | Purpose                                              |
|--------|-----------------------|-------------------------------------------------------|
| GET    | `/`                    | Health check                                          |
| GET    | `/loan-products/`      | Full product catalog                                  |
| POST   | `/predict-risk/`       | Risk score + category + probabilities                 |
| POST   | `/risk-explanation/`   | Risk score + SHAP-style feature contributions          |
| POST   | `/check-eligibility/`  | Per-product eligibility + reasons                      |
| POST   | `/recommend-loans/`    | Ranked recommendations + best pick                     |

All POST endpoints take a `BaseProfile`-shaped JSON body (see `backend/schemas/requests.py`);
`/recommend-loans/` additionally accepts an optional `preferences` object.

## Known gaps / next steps

- `ml/` pipeline is unwired (see "Design decisions" above) — decide whether to finish it or trim it.
- No CI (`.github/workflows`) running `pytest`/`npm test` automatically.
- No production frontend build path in Docker (the frontend container runs the CRA dev server, not
  a built + nginx-served bundle).
- No auth/rate limiting — fine for a project/demo, not for a public deployment.
