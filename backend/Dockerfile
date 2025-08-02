# Use official Python image
FROM python:3.11-slim

# Install system deps
RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*

# Set workdir
WORKDIR /app

# Copy requirements & install
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY app ./app

# Expose port
EXPOSE 8000

# Default command
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]