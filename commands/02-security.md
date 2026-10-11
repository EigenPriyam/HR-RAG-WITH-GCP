# 02 · Security layer (advanced RAG)

Everything in `01-basic-rag.md`, plus `src_security_layer/`: Model Armor input/output
guardrail, LiteLLM Gemini→Groq fallback, scope guardrail, semantic cache, thread
memory, LangSmith evaluation and a red-team suite.

## Values

```bash
PROJECT_ID=your-project-id
REGION=us-central1
MODEL_ARMOR_LOCATION=us
MODEL_ARMOR_TEMPLATE_ID=hr-assistant-guardrail
```

Optional extra keys (only for `evaluate.py` and the Groq fallback), in `.env`:
`GROQ_API_KEY` ([console.groq.com](https://console.groq.com)),
`LANGSMITH_API_KEY` ([smith.langchain.com](https://smith.langchain.com)).

## 1. Enable Model Armor

```bash
gcloud services enable modelarmor.googleapis.com --project=$PROJECT_ID
```

## 2. Create the guardrail template (one-time)

Screens every input and output for prompt injection, jailbreaks and unsafe content.

```bash
gcloud model-armor templates create $MODEL_ARMOR_TEMPLATE_ID \
  --location=$MODEL_ARMOR_LOCATION \
  --project=$PROJECT_ID \
  --pi-and-jailbreak-filter-settings-enforcement=enabled \
  --pi-and-jailbreak-filter-settings-confidence-level=high \
  --basic-config-filter-enforcement=enabled \
  --rai-settings-filters=confidenceLevel=high,filterType=HATE_SPEECH \
  --rai-settings-filters=confidenceLevel=high,filterType=HARASSMENT \
  --rai-settings-filters=confidenceLevel=high,filterType=DANGEROUS \
  --rai-settings-filters=confidenceLevel=high,filterType=SEXUALLY_EXPLICIT \
  --malicious-uri-filter-settings-enforcement=enabled

gcloud model-armor templates describe $MODEL_ARMOR_TEMPLATE_ID \
  --location=$MODEL_ARMOR_LOCATION --project=$PROJECT_ID
```

**No template? Run without it:** set `GUARDRAIL_PROVIDER=gemini_lite` in `.env`
(one cheap Gemini classify call) or `none` (guardrail off).

## 3. `.env` additions

```bash
GUARDRAIL_PROVIDER=model_armor          # model_armor | gemini_lite | none
MODEL_ARMOR_LOCATION=us
MODEL_ARMOR_TEMPLATE_ID=hr-assistant-guardrail   # must match the template name exactly
QDRANT_NOISY_COLLECTION_NAME=hr_policies_noisy_demo
GROQ_API_KEY=...
LANGSMITH_API_KEY=...
LANGSMITH_TRACING=true
```

Optional tuning (defaults are fine): `GUARDRAIL_FAIL_OPEN_INPUT`,
`GUARDRAIL_FAIL_OPEN_OUTPUT`, `GUARDRAIL_HISTORY_TURNS`,
`SEMANTIC_CACHE_MAX_ENTRIES`, `SEMANTIC_CACHE_TTL_SECONDS`.

## 4. Ingest (skip if already done)

```bash
python ingest.py
```

## 5. Run

```bash
python main_src_security_layer.py            # CLI, full secure pipeline
python main_src_security_layer_reliable.py   # guarded walkthrough on the noisy corpus
streamlit run app_security_layer.py          # chat UI, no login (http://localhost:8501)
langgraph dev                                # LangGraph Studio
```

## 6. Red-team pass

```bash
python readteam_test.py   # 7 attacks vs a plain baseline AND the guarded pipeline
                          # -> results/redteam_results.json
```

## 7. Answer-quality evaluation

Needs `LANGSMITH_API_KEY` and `GROQ_API_KEY`.

```bash
python evaluate.py        # correctness + groundedness, judged by Groq; creates a LangSmith experiment
```

## Delete the template (reference)

```bash
gcloud model-armor templates delete $MODEL_ARMOR_TEMPLATE_ID \
  --location=$MODEL_ARMOR_LOCATION --project=$PROJECT_ID
```

## Troubleshooting

- **Every message, even "Hello", is "flagged by the input safety guardrail".** The
  guardrail call is *erroring* and the input check fails closed. Check logs for
  `Guardrail provider error`. Usual causes: missing `roles/modelarmor.user` on the
  runtime service account, Model Armor API not enabled, or a template-ID typo.
  Quick local workaround: `GUARDRAIL_PROVIDER=gemini_lite`.
- *404 on the template* → `MODEL_ARMOR_TEMPLATE_ID` / `MODEL_ARMOR_LOCATION` don't
  match the template you created.
