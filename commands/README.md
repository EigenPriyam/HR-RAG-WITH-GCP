# Commands

Copy-paste runbooks, in the order you need them. Shell: Git Bash (macOS/Linux work too).

| File | Stage | Covers |
|---|---|---|
| [01-basic-rag.md](01-basic-rag.md) | Basic RAG (`src/`) | GCP project, bucket, venv, `.env`, ingest, run |
| [02-security.md](02-security.md) | Advanced RAG (`src_security_layer/`) | Model Armor guardrail, LiteLLM fallback, red-team, evaluation |
| [03-deployment.md](03-deployment.md) | Deployment | Docker, Google OAuth + allow-list, Cloud Run |

Every file starts with a **Values** block. Set those variables in your shell first,
using your own values — nothing here is specific to anyone's account.
API keys never go into a command; they live in `.env` (local) or `deploy.env.yaml`
(Cloud Run), both gitignored.
