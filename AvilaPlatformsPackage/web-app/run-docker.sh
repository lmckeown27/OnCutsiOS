#!/bin/bash

# AvilaPlatforms Frontend - Docker Run Script
# Runs the Docker container with proper configuration

set -e  # Exit on error

echo "🚀 Starting AvilaPlatforms Frontend Container..."
echo ""

# Stop and remove existing container if running
if [ "$(docker ps -aq -f name=avilaplatforms-frontend)" ]; then
    echo "🛑 Stopping existing container..."
    docker stop avilaplatforms-frontend || true
    docker rm avilaplatforms-frontend || true
fi

# Run the container
docker run -d \
  --name avilaplatforms-frontend \
  --restart unless-stopped \
  -p 80:80 \
  avilaplatforms-frontend:latest

echo ""
echo "✅ Container started successfully!"
echo ""
echo "📊 Container Status:"
docker ps | grep avilaplatforms-frontend

echo ""
echo "🌐 Access the application at:"
echo "   http://localhost"
echo ""
echo "📝 View logs with:"
echo "   docker logs -f avilaplatforms-frontend"
echo ""
echo "🛑 Stop the container with:"
echo "   docker stop avilaplatforms-frontend"

