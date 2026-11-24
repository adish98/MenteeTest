import re

import pytest

from hello_world import app

SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"
)


@pytest.fixture
def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_root_returns_hello_world(client, monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    response = client.get("/")
    assert response.status_code == 200
    assert response.is_json
    assert response.get_json()["message"] == "Hello World"


def test_root_defaults_to_version_0_0_0(client, monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    assert client.get("/").get_json()["version"] == "0.0.0"


@pytest.mark.parametrize("version", ["1.2.3", "10.0.1", "2.0.0-rc.1"])
def test_root_reports_configured_version(client, monkeypatch, version):
    monkeypatch.setenv("APP_VERSION", version)
    assert client.get("/").get_json() == {"message": "Hello World", "version": version}


def test_default_version_is_semver(client, monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    assert SEMVER.match(client.get("/").get_json()["version"])


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_unknown_route_returns_404(client):
    assert client.get("/does-not-exist").status_code == 404


@pytest.mark.parametrize("path", ["/", "/health"])
def test_only_get_is_allowed(client, path):
    assert client.post(path).status_code == 405


def test_requests_are_logged(client, caplog):
    with caplog.at_level("INFO", logger="hello_world"):
        client.get("/health")
    assert any("GET /health 200" in message for message in caplog.messages)


def test_unhandled_errors_are_logged_and_return_500(client, caplog, monkeypatch):
    def boom():
        raise RuntimeError("boom")

    monkeypatch.setitem(app.view_functions, "health", boom)
    # Let the error handler run instead of re-raising into the test.
    monkeypatch.setitem(app.config, "PROPAGATE_EXCEPTIONS", False)
    with caplog.at_level("ERROR", logger="hello_world"):
        response = client.get("/health")
    assert response.status_code == 500
    assert response.get_json() == {"error": "Internal Server Error"}
    assert any("Unhandled error on GET /health" in m for m in caplog.messages)
