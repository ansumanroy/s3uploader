FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies (includes awscurl)
RUN pip install --no-cache-dir -r requirements.txt

# Copy Python scripts into container
COPY generate-presigned-url.py .
COPY generate-multipart-presigned-url.py .

# awscurl will be available as a command in PATH
# No default entrypoint - allow direct command execution

