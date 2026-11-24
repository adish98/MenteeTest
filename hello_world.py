from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.get("/")
def hello():
    return jsonify(
        message="Hello World",
        version=os.environ.get("APP_VERSION", "0.0.0"),
    )


@app.get("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)