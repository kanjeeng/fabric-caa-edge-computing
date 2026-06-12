FROM python:3.11-slim

WORKDIR /app

COPY mqtt-bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY mqtt-bridge/bridge.py .

CMD ["python", "-u", "bridge.py"]