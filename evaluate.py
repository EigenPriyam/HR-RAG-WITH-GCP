"""26 · evaluate.py — entry point: run the LangSmith evaluation (20).

Needs LANGSMITH_API_KEY and GROQ_API_KEY in .env. Results land in your
LangSmith project as an Experiment on the 'hr-policy-qa' dataset.

Run with:  python evaluate.py
"""

from src_security_layer.evaluation import run_evaluation
from src_security_layer.evaluation_dataset import DATASET_NAME
from src_security_layer.logging_config import configure_logging


def main():
    configure_logging()
    print("Running HR Policy Assistant evaluation (uploads to LangSmith)...")
    results = run_evaluation()
    print(f"\nDone. Open the '{DATASET_NAME}' dataset in LangSmith to see the experiment.")
    try:
        print(results)
    except Exception:
        pass


if __name__ == "__main__":
    main()
