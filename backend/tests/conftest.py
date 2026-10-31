import os, sys
os.environ["SAFECIRCLE_NO_AUTOAPP"] = "1"
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import pytest
from fastapi.testclient import TestClient
from app.main import create_app


@pytest.fixture()
def app(tmp_path):
    return create_app(f"sqlite:///{tmp_path}/t.db", seed=True)


@pytest.fixture()
def client(app):
    return TestClient(app)


@pytest.fixture()
def db(app):
    with app.state.SessionLocal() as s:
        yield s
