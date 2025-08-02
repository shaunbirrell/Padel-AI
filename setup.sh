#!/bin/bash

echo "🏓 Setting up Padel Analysis Platform..."
echo "========================================"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js v16 or higher."
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 16 ]; then
    echo "❌ Node.js version 16 or higher is required. Current version: $(node -v)"
    exit 1
fi

echo "✅ Node.js version: $(node -v)"

# Install server dependencies
echo "📦 Installing server dependencies..."
npm install

# Install client dependencies
echo "📦 Installing client dependencies..."
cd client
npm install
cd ..

# Create uploads directory if it doesn't exist
echo "📁 Creating uploads directory..."
mkdir -p uploads

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "⚙️ Creating .env file..."
    cp .env.example .env
    echo "📝 Please edit .env file with your configuration"
    echo "   - Set GOOGLE_APPLICATION_CREDENTIALS path"
    echo "   - Set GOOGLE_CLOUD_PROJECT_ID"
else
    echo "✅ .env file already exists"
fi

# Check if Google Cloud credentials are set
if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "⚠️  GOOGLE_APPLICATION_CREDENTIALS environment variable is not set"
    echo "   Please set it to the path of your service account key file"
    echo "   Example: export GOOGLE_APPLICATION_CREDENTIALS=\"./service-account-key.json\""
fi

echo ""
echo "🎉 Setup completed!"
echo ""
echo "Next steps:"
echo "1. Configure your .env file with Google Cloud credentials"
echo "2. Start the development servers: npm run dev"
echo "3. Open http://localhost:3000 in your browser"
echo ""
echo "For production deployment:"
echo "1. Build the app: npm run build"
echo "2. Start production server: npm start"
echo ""
echo "Happy Padel Playing! 🏓"