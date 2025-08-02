# 🏓 Padel Analysis Platform

A comprehensive web application for analyzing padel match videos using Google Cloud Video Intelligence API. Upload your padel match videos and get AI-powered insights to improve your game.

## ✨ Features

### 🎥 Video Analysis
- **Drag & Drop Upload**: Easy video upload with drag-and-drop interface
- **Multiple Format Support**: MP4, AVI, MOV, WMV, FLV, WEBM
- **Large File Support**: Up to 500MB per video
- **Progress Tracking**: Real-time upload and analysis progress

### 🤖 AI-Powered Analysis
- **Shot Detection**: Automatic detection of shots, volleys, and rallies
- **Object Tracking**: Track rackets, balls, and players
- **Text Recognition**: Detect scores and player information
- **Content Analysis**: Analyze video content for sports-related activities

### 📊 Comprehensive Analytics
- **Shot Statistics**: Detailed breakdown of shot types and frequencies
- **Timeline Analysis**: Visual timeline of all shots and events
- **Performance Insights**: AI-generated recommendations for improvement
- **Interactive Charts**: Beautiful visualizations using Recharts

### 🎨 Modern UI/UX
- **Responsive Design**: Works perfectly on desktop, tablet, and mobile
- **Dark/Light Theme**: Clean, modern interface with Tailwind CSS
- **Real-time Updates**: Live progress tracking and status updates
- **Intuitive Navigation**: Easy-to-use interface with clear navigation

## 🚀 Quick Start

### Prerequisites

- Node.js (v16 or higher)
- npm or yarn
- Google Cloud Platform account
- Google Cloud Video Intelligence API enabled

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd padel-analysis-platform
   ```

2. **Install dependencies**
   ```bash
   # Install server dependencies
   npm install
   
   # Install client dependencies
   cd client
   npm install
   cd ..
   ```

3. **Set up Google Cloud**
   - Create a Google Cloud Project
   - Enable the Video Intelligence API
   - Create a service account and download the JSON key
   - Set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable

4. **Configure environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

5. **Start the development servers**
   ```bash
   # Start both server and client
   npm run dev
   
   # Or start them separately
   npm run server  # Backend on port 5000
   npm run client  # Frontend on port 3000
   ```

6. **Open your browser**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:5000

## 📁 Project Structure

```
padel-analysis-platform/
├── server/                 # Backend server
│   ├── index.js           # Main server file
│   ├── routes/            # API routes
│   │   ├── videoRoutes.js # Video upload/management
│   │   └── analysisRoutes.js # Video analysis
│   └── middleware/        # Custom middleware
├── client/                # React frontend
│   ├── src/
│   │   ├── components/    # Reusable components
│   │   ├── pages/         # Page components
│   │   ├── App.js         # Main app component
│   │   └── index.js       # React entry point
│   ├── public/            # Static files
│   └── package.json       # Frontend dependencies
├── uploads/               # Video storage
├── package.json           # Backend dependencies
└── README.md             # This file
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file in the root directory:

```env
# Server Configuration
PORT=5000
NODE_ENV=development

# Google Cloud Configuration
GOOGLE_APPLICATION_CREDENTIALS=path/to/your/service-account-key.json
GOOGLE_CLOUD_PROJECT_ID=your-project-id

# Frontend URL
FRONTEND_URL=http://localhost:3000

# File Upload Configuration
MAX_FILE_SIZE=500000000
UPLOAD_DIR=./uploads
```

### Google Cloud Setup

1. **Create a Google Cloud Project**
   ```bash
   gcloud projects create padel-analysis-platform
   gcloud config set project padel-analysis-platform
   ```

2. **Enable Video Intelligence API**
   ```bash
   gcloud services enable videointelligence.googleapis.com
   ```

3. **Create Service Account**
   ```bash
   gcloud iam service-accounts create padel-analysis-sa \
     --display-name="Padel Analysis Service Account"
   ```

4. **Download Service Account Key**
   ```bash
   gcloud iam service-accounts keys create service-account-key.json \
     --iam-account=padel-analysis-sa@padel-analysis-platform.iam.gserviceaccount.com
   ```

5. **Set Environment Variable**
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/service-account-key.json"
   ```

## 📖 Usage

### 1. Upload Video
- Navigate to the Upload page
- Drag and drop your padel match video or click to browse
- Wait for upload to complete

### 2. Analysis Processing
- The system automatically starts analysis after upload
- Monitor progress in real-time
- Analysis typically takes 2-5 minutes depending on video length

### 3. View Results
- Once analysis is complete, you'll be redirected to the results page
- Explore different tabs:
  - **Overview**: Summary statistics and charts
  - **Shot Analysis**: Detailed shot breakdown
  - **Timeline**: Chronological view of all shots
  - **Insights**: AI-generated recommendations

### 4. Improve Your Game
- Review shot statistics and patterns
- Identify strengths and areas for improvement
- Follow training recommendations
- Track progress over time

## 🛠️ API Endpoints

### Video Management
- `POST /api/videos/upload` - Upload a new video
- `GET /api/videos` - Get all videos
- `GET /api/videos/:id` - Get specific video
- `DELETE /api/videos/:id` - Delete video

### Analysis
- `POST /api/analysis/analyze/:videoId` - Start video analysis
- `GET /api/analysis/:videoId` - Get analysis results

### Health Check
- `GET /api/health` - Server health status

## 🎯 Analysis Features

### Shot Detection
- **Volleys**: Quick shots near the net
- **Serves**: Opening shots of each point
- **Rallies**: Extended exchanges between players
- **Shot Duration**: Timing analysis for each shot

### Object Tracking
- **Rackets**: Track racket movement and positioning
- **Balls**: Follow ball trajectory and speed
- **Players**: Monitor player movement and positioning

### Performance Metrics
- **Shot Frequency**: How often different shots are used
- **Rally Length**: Average duration of rallies
- **Court Coverage**: Player movement patterns
- **Shot Accuracy**: Based on ball placement

## 🚀 Deployment

### Production Build
```bash
# Build the React app
cd client
npm run build
cd ..

# Start production server
npm start
```

### Docker Deployment
```dockerfile
# Dockerfile example
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN cd client && npm install && npm run build
EXPOSE 5000
CMD ["npm", "start"]
```

### Environment Variables for Production
```env
NODE_ENV=production
PORT=5000
FRONTEND_URL=https://your-domain.com
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Google Cloud Video Intelligence API](https://cloud.google.com/video-intelligence)
- [React](https://reactjs.org/) for the frontend framework
- [Tailwind CSS](https://tailwindcss.com/) for styling
- [Recharts](https://recharts.org/) for data visualization
- [Express.js](https://expressjs.com/) for the backend framework

## 📞 Support

If you have any questions or need help, please:

1. Check the [Issues](https://github.com/your-repo/issues) page
2. Create a new issue with detailed information
3. Contact the development team

---

**Happy Padel Playing! 🏓**