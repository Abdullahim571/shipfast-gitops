from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/status")
def status():
    return jsonify(status="ok"), 200


if __name__ == "__main__":
    # Local development only; the container runs under gunicorn.
    app.run(host="0.0.0.0", port=5000)
