# Use Node.js 16 Alpine as base image
FROM node:16-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install server dependencies
RUN npm install

# Copy client package files
COPY client/package*.json ./client/

# Install client dependencies
RUN cd client && npm install

# Copy source code
COPY . .

# Build React app
RUN cd client && npm run build

# Create uploads directory
RUN mkdir -p uploads

# Expose port
EXPOSE 5000

# Set environment variables
ENV NODE_ENV=production
ENV PORT=5000

# Start the application
CMD ["npm", "start"]