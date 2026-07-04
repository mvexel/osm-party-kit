FROM python:3.13-slim

WORKDIR /app

COPY serve.py region.json ./
COPY baked ./baked
COPY web ./web

EXPOSE 8765
VOLUME ["/app/party"]

CMD ["python3", "serve.py", "8765"]
