FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

RUN groupadd -r agrosynchro && \
    useradd -r -g agrosynchro -d /app -s /bin/bash agrosynchro && \
    chown -R agrosynchro:agrosynchro /app

USER agrosynchro

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8081/ping || exit 1

CMD ["python", "src/main.py"]