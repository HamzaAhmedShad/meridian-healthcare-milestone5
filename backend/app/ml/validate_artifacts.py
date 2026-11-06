"""Validate packaged inference artifacts without database or training data."""
from importlib.metadata import version
from pathlib import Path
import warnings

from sklearn.exceptions import InconsistentVersionWarning

EXPECTED_VERSIONS = {
    "scikit-learn": "1.9.0",
    "joblib": "1.4.2",
    "numpy": "2.4.6",
    "scipy": "1.17.1",
    "pandas": "3.0.6",
}

def main():
    directory = Path(__file__).resolve().parent / "artifacts"

    for name in ("model.joblib", "scaler.joblib", "metrics.json"):
        path = directory / name
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"Required inference artifact missing: {name}")

    for package, expected in EXPECTED_VERSIONS.items():
        actual = version(package)
        if actual != expected:
            raise RuntimeError(
                f"{package}: expected {expected}, installed {actual}"
            )

    warnings.simplefilter("error", InconsistentVersionWarning)

    from .predictor import get_predictor
    get_predictor()

    print("Packaged model loaded successfully without training data.")

if __name__ == "__main__":
    main()
