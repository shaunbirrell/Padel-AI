# MongoDB Setup Options:

## Option 1: Install MongoDB locally
# Ubuntu/Debian:
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod

# macOS with Homebrew:
brew tap mongodb/brew
brew install mongodb-community
brew services start mongodb/brew/mongodb-community

# Windows: Download from https://www.mongodb.com/try/download/community

## Option 2: Use Docker (Recommended)
docker run -d --name padel-mongodb -p 27017:27017 mongo:latest

## Option 3: Use MongoDB Atlas (Cloud)
# Go to https://www.mongodb.com/atlas
# Create free cluster
# Get connection string
