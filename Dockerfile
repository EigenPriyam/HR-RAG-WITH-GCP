FROM python:3.11-slim
WORKDIR /app

# uv, copied straight from its own image — no pip/curl install step needed.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# Pre-download the BM25 model at BUILD time (see docs/12) so the container
# never has to fetch it from HuggingFace on a cold start.
RUN python -c "from fastembed import SparseTextEmbedding; SparseTextEmbedding(model_name='Qdrant/bm25')"

COPY src_security_layer/ ./src_security_layer/
COPY data/ ./data/
COPY app_final.py app_security_layer.py ingest.py evaluate.py main_src_security_layer_reliable.py main_src_security_layer.py readteam_test.py ./

ENV PORT=8080
EXPOSE 8080

# Default command: the Streamlit app. docker-compose / `docker compose run`
# override this to run evaluate.py etc.
CMD ["sh", "-c", "streamlit run app_final.py --server.port=${PORT} --server.address=0.0.0.0 --server.headless=true --server.enableCORS=false --server.enableXsrfProtection=false"]
