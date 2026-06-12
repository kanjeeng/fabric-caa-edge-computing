FROM python:3.11-slim
WORKDIR /app
COPY caa-controller/requirements.txt .
RUN pip install --default-timeout=1000 --no-cache-dir -r requirements.txt
COPY caa-controller/ .
COPY fabric-network /app/fabric-network
RUN mkdir -p /var/log
CMD ["python", "-u", "controller.py"]