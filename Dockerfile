FROM python:3.13-slim

# Install uv
RUN pip install --no-cache-dir uv

# Set Workdir
WORKDIR /app  

# Copy only dependency files first (better caching)
COPY pyproject.toml uv.lock /

# Install all dependencies system-wide
RUN uv export --no-dev | uv pip install --system -r -

# Copy application code
COPY src ./src