FROM python:3.11-slim

RUN pip install --no-cache-dir paho-mqtt==2.1.0 docker==7.1.0 psutil==6.1.0

WORKDIR /app
COPY buoy_agent.py .

CMD ["python", "-u", "buoy_agent.py"]
