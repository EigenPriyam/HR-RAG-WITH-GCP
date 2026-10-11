# 01 · Basic RAG

The plain pipeline in `src/`: retrieval → hybrid search → re-rank → agent → cited
answer. No guardrails, no login, no Cloud Run.

## Values

Set these in your shell (replace with your own):

```bash
PROJECT_ID=your-project-id
REGION=us-central1
LOCATION=us-central1
GCS_BUCKET_NAME=your-project-id-hr-policies
BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX
QDRANT_COLLECTION_NAME=hr_policies
QDRANT_NOISY_COLLECTION_NAME=hr_policies_noisy_demo
```

`JINA_API_KEY`, `QDRANT_URL` and `QDRANT_API_KEY` are secrets — get free-tier keys
from [jina.ai](https://jina.ai) and [cloud.qdrant.io](https://cloud.qdrant.io) and put
them in `.env`.

## 1. GCP project + billing (skip if it exists)

```bash
gcloud auth login
gcloud billing accounts list                     # find your billing account ID
gcloud projects create $PROJECT_ID --name="RAG HR Assistant"
gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT_ID
gcloud config set project $PROJECT_ID
```

## 2. Local credentials

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project $PROJECT_ID
```

## 3. Enable the APIs

```bash
gcloud services enable aiplatform.googleapis.com storage.googleapis.com --project=$PROJECT_ID
```

- `aiplatform` — Vertex AI (Gemini)
- `storage` — Cloud Storage (raw HR documents)

## 4. Create the bucket

```bash
gcloud storage buckets create gs://$GCS_BUCKET_NAME --project=$PROJECT_ID --location=$REGION
```

`ingest.py` uploads `data/` into it — no manual upload.

## 5. Python environment

```bash
uv venv .venv                        # or: python -m venv .venv
source .venv/Scripts/activate        # Git Bash. macOS/Linux: source .venv/bin/activate
uv pip install -r requirements.txt   # or: pip install -r requirements.txt
```

## 6. `.env`

```bash
cp .env.example .env
```

Fill in `PROJECT_ID`, `LOCATION`, `GCS_BUCKET_NAME`, `JINA_API_KEY`, `QDRANT_URL`,
`QDRANT_API_KEY`. Put your HR policy files in `data/` first.

## 7. Ingest into Qdrant

```bash
python ingest.py              # local data/ -> GCS -> chunk -> embed -> Qdrant (idempotent)
python ingest.py --force      # rebuild from scratch
python ingest.py --hr-only    # skip the noisy/mixed collection
python ingest.py --noisy-only # skip the clean collection
```

## 8. Run

```bash
python main.py                # CLI demo (basic RAG)
langgraph dev                 # LangGraph Studio
```

## Troubleshooting

- *Collection not found* → run `python ingest.py`.
- *Jina / Qdrant auth error* → check the keys in `.env`.
- *`DefaultCredentialsError`* → rerun `gcloud auth application-default login`.
