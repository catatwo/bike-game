FROM python:3.13-slim
WORKDIR /app
COPY bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bridge/*.py ./
# The image is only built if the tests pass.
RUN python -m unittest -q
ENV XDG_STATE_HOME=/state PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "bikebridge.py"]
