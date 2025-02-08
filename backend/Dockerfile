FROM python:3.12-slim

WORKDIR /

COPY /src /app
COPY pyproject.toml .
COPY poetry.lock .

RUN pip install --upgrade pip
RUN pip install poetry==1.8.5

RUN poetry config virtualenvs.create false
RUN poetry install --no-dev

EXPOSE 8080
ENTRYPOINT ["fastapi", "run", "app/main.py", "--port", "8080", "--host", "0.0.0.0"]