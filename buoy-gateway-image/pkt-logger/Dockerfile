FROM python:3.11-slim

WORKDIR /app
COPY pkt_logger.py .

EXPOSE 1702/udp

CMD ["python", "-u", "pkt_logger.py"]
