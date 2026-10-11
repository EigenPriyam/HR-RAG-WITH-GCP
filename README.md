# HR Policy Assistant — RAG on Google Cloud

An HR policy question-answering assistant built in two stages: a **basic RAG**
pipeline, then a **production-style version** with safety guardrails, caching,
conversation memory, evaluation, a Google login gate, and Cloud Run deployment.

Ask about leave, WFH, notice period, reimbursement, and more — answers are
grounded in the company policy documents and cited.

## Two stages in one repo

| | `src/` — basic RAG | `src_security_layer/` — advanced RAG |
|---|---|---|
| Retrieval | Hybrid search (dense + BM25) in Qdrant, Jina re-rank | Same, plus scope filter (category + relevance threshold) |
| Agent | LangChain agent with a search tool | Same agent, guarded search tool |
| Safety | — | Vertex AI Model Armor on input **and** output (or Gemini-lite fallback) |
| LLM | Gemini on Vertex AI | Gemini primary + Groq fallback via LiteLLM |
| Extras | — | Semantic cache, thread memory, LangSmith tracing, evaluation, red-team tests |
| UI / entry | `main.py` (CLI) | `app_final.py` (Streamlit + Google OAuth), `app_security_layer.py` (no login) |

## Architecture (advanced)

```
user ─▶ Google OAuth gate ─▶ input guardrail (Model Armor)
                                   │ blocked ─▶ refusal message
                                   ▼
                        semantic cache ─ hit ─▶ answer
                                   │ miss
                                   ▼
              agent (Gemini ⇄ Groq fallback) + thread memory
                                   │
                    scoped hybrid search tool ─▶ Qdrant + Jina re-rank
                                   ▼
                       output guardrail (Model Armor) ─▶ answer + citations
```

### Guardrail failure behaviour

If the guardrail provider raises (missing IAM role, API disabled, wrong template):

- **Input check fails closed** — the request is refused (`GUARDRAIL_FAIL_OPEN_INPUT=true` overrides).
- **Output check fails open** — the answer is returned and the error is logged (`GUARDRAIL_FAIL_OPEN_OUTPUT=false` overrides).

If every message, even "Hello", is reported as "flagged by the input safety
guardrail", check the logs for `Guardrail provider error` — it is usually the
Cloud Run service account lacking `roles/modelarmor.user`.

## Project layout

```
src/                     basic RAG pipeline
src_security_layer/      advanced RAG: guardrails, cache, memory, evaluation
ingest.py                build the Qdrant collections from the policy documents
main.py                  CLI demo (basic RAG)
main_src_security_layer*.py   CLI demos (advanced / reliability walkthrough)
app_final.py             Streamlit app with Google login (deployed to Cloud Run)
app_security_layer.py    Streamlit app without login
evaluate.py              LangSmith evaluation (dataset: hr-policy-qa)
readteam_test.py         7 adversarial attacks: plain vs guarded pipeline
Dockerfile, docker-compose.yml   container build and local run
langgraph.json           LangGraph Studio config
```

## Setup

Step-by-step copy-paste runbooks (GCP setup, guardrail, Cloud Run) are in [`commands/`](commands/README.md). A condensed version follows.

Requirements: Python 3.11, a GCP project with Vertex AI enabled, and free-tier
accounts for [Qdrant Cloud](https://cloud.qdrant.io), [Jina AI](https://jina.ai),
[Groq](https://groq.com) and [LangSmith](https://smith.langchain.com).

```bash
python -m venv .venv && source .venv/Scripts/activate   # Windows Git Bash
pip install -r requirements.txt
cp .env.example .env                                     # then fill in values
gcloud auth application-default login
```

Put your HR policy documents (`.txt`, `.pdf`, `.docx`, `.pptx`) in `data/`
(not included in the repo) or upload them to your `GCS_BUCKET_NAME`, then:

```bash
python ingest.py            # build the vector collections (--force to rebuild)
python main.py              # basic RAG, CLI
streamlit run app_security_layer.py   # advanced RAG, local UI
```

### Safety guardrail

Enable the Model Armor API and create a template, then set
`MODEL_ARMOR_TEMPLATE_ID` and `MODEL_ARMOR_LOCATION`:

```bash
gcloud services enable modelarmor.googleapis.com
```

For local development without any extra GCP setup use `GUARDRAIL_PROVIDER=gemini_lite`.

## Deploy to Cloud Run

1. Enable APIs: Cloud Run, Cloud Build, Artifact Registry, Secret Manager, Vertex AI, Model Armor.
2. Grant the Cloud Run runtime service account: `roles/aiplatform.user`,
   `roles/storage.objectViewer` on the bucket, `roles/modelarmor.user`, and
   `roles/secretmanager.secretAccessor` on the OAuth secret.
3. Create a Google OAuth client; store its `[auth]` config (`.streamlit/secrets.toml`)
   in Secret Manager and mount it on the service.
4. Put non-secret config and API keys in a `deploy.env.yaml` (gitignored) and deploy:

```bash
gcloud run deploy hr-assistant --source . --region <REGION> \
  --env-vars-file=deploy.env.yaml
```

5. Add the service URL as the OAuth redirect URI, and restrict access with `ALLOWED_EMPLOYEE_EMAILS`.

The image copies `data/` at build time, so make sure it exists before building.

## Evaluation and red-teaming

```bash
python evaluate.py        # LangSmith experiment on the hr-policy-qa dataset
python readteam_test.py   # persona override, jailbreak, scope escape, etc.
```

## Tech stack

LangChain 1.x · LangGraph · Gemini (Vertex AI) · Groq · LiteLLM · Qdrant (hybrid
dense + BM25) · Jina embeddings and reranker · Vertex AI Model Armor · Streamlit ·
LangSmith · Docker · Cloud Run · Secret Manager
