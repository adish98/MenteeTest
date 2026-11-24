FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY hello_world.py .

ARG APP_VERSION=0.0.0
ENV APP_VERSION=${APP_VERSION}

USER 10001:10001
EXPOSE 8080

CMD ["python", "hello_world.py"]
