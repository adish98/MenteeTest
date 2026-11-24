import logging
import os
import sys
import time

from flask import Flask, g, jsonify, request

# Log to stdout so `docker logs` and ECS pick it up. LOG_LEVEL defaults to INFO.
logging.basicConfig(
    stream=sys.stdout,
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
# Our request log below replaces Werkzeug's per-request lines.
logging.getLogger("werkzeug").setLevel(logging.WARNING)

logger = logging.getLogger("hello_world")

app = Flask(__name__)


def app_version():
    return os.environ.get("APP_VERSION", "0.0.0")


@app.before_request
def start_timer():
    g.start = time.perf_counter()


@app.after_request
def log_request(response):
    duration_ms = (time.perf_counter() - g.get("start", time.perf_counter())) * 1000
    logger.info(
        "%s %s %s %.1fms from %s",
        request.method,
        request.path,
        response.status_code,
        duration_ms,
        request.headers.get("X-Forwarded-For", request.remote_addr),
    )
    return response


@app.errorhandler(Exception)
def log_unhandled_error(error):
    # Keep Flask's normal responses for HTTP errors such as 404 and 405.
    if hasattr(error, "code") and hasattr(error, "get_response"):
        return error
    logger.exception("Unhandled error on %s %s", request.method, request.path)
    return jsonify(error="Internal Server Error"), 500


@app.get("/")
def hello():
    return jsonify(message="Hello World", version=app_version())


@app.get("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    logger.info("Starting Hello World %s on 0.0.0.0:8080", app_version())
    app.run(host="0.0.0.0", port=8080)
