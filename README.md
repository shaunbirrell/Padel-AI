# 🎾 Padel Match Analyzer

An AI-powered video analysis platform for Padel players to improve their game through detailed match analysis using Google Cloud Video Intelligence API.

![Padel Analyzer](https://img.shields.io/badge/Padel-Analyzer-blue) ![Node.js](https://img.shields.io/badge/Node.js-18+-green) ![React](https://img.shields.io/badge/React-18+-blue) ![TypeScript](https://img.shields.io/badge/TypeScript-5+-blue) ![MongoDB](https://img.shields.io/badge/MongoDB-6+-green)

## ✨ Features

### 🎥 Video Analysis
- **Upload Match Videos**: Support for MP4, AVI, MOV, MKV formats up to 500MB
- **AI-Powered Analysis**: Google Cloud Video Intelligence API for object detection and movement tracking
- **Real-time Processing**: Track analysis progress with live updates

### 📊 Comprehensive Analytics
- **Shot Analysis**: Detailed breakdown of forehands, backhands, volleys, smashes, and serves
- **Rally Statistics**: Average rally length, longest rallies, and rally distribution
- **Movement Analysis**: Court coverage, speed metrics, and positioning insights
- **Performance Metrics**: Accuracy, consistency, aggressiveness, and overall ratings

### 🏆 Performance Tracking
- **Progress Visualization**: Charts showing improvement over time
- **Video Comparison**: Compare multiple matches to track development
- **Achievement System**: Unlock badges for reaching milestones
- **Personal Goals**: Set and track custom improvement goals

### 🎯 AI Coaching
- **Personalized Insights**: AI-generated strengths and weaknesses analysis
- **Drill Recommendations**: Specific exercises based on your playing style
- **Technical Advice**: Professional tips for technique improvement
- **Strategic Guidance**: Tactical recommendations for better gameplay

### 📱 Modern UI/UX
- **Responsive Design**: Works seamlessly on desktop, tablet, and mobile
- **Material-UI**: Beautiful, accessible interface with dark/light themes
- **Real-time Notifications**: Stay updated on analysis progress
- **Interactive Charts**: Detailed visualizations using Recharts

## 🚀 Quick Start

### Prerequisites
- Node.js 18+ and npm
- MongoDB 6+
- Google Cloud account with Video Intelligence API enabled
- Google Cloud Storage bucket

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd padel-match-analyzer
   ```

2. **Install backend dependencies**
   ```bash
   npm install
   ```

3. **Install frontend dependencies**
   ```bash
   cd client
   npm install
   cd ..
   ```

4. **Set up environment variables**
   ```bash
   cp .env.example .env
   ```
   
   Configure your `.env` file:
   ```env
   # Google Cloud Configuration
   GOOGLE_CLOUD_PROJECT_ID=your-project-id
   GOOGLE_CLOUD_KEY_FILE=path/to/service-account-key.json
   GOOGLE_CLOUD_STORAGE_BUCKET=padel-videos-bucket

   # Database Configuration
   MONGODB_URI=mongodb://localhost:27017/padel-analyzer

   # JWT Configuration
   JWT_SECRET=your-super-secret-jwt-key
   JWT_EXPIRE=7d

   # Server Configuration
   PORT=5000
   NODE_ENV=development
   CLIENT_URL=http://localhost:3000
   ```

5. **Set up Google Cloud**
   - Enable Video Intelligence API in Google Cloud Console
   - Create a service account and download the JSON key file
   - Create a Cloud Storage bucket for video storage
   - Update the environment variables with your Google Cloud details

6. **Start MongoDB**
   ```bash
   # Using MongoDB service
   sudo systemctl start mongod
   
   # Or using Docker
   docker run -d -p 27017:27017 mongo:latest
   ```

7. **Start the application**
   
   **Development mode (both backend and frontend):**
   ```bash
   # Terminal 1 - Backend
   npm run dev
   
   # Terminal 2 - Frontend
   cd client
   npm start
   ```
   
   **Production mode:**
   ```bash
   npm run build
   npm start
   ```

8. **Access the application**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:5000
   - API Documentation: http://localhost:5000/api/health

## 📋 Usage Guide

### 1. Account Setup
1. Register with your email and create a playing profile
2. Set your playing level, dominant hand, and preferred position
3. Choose a subscription plan (Free: 3 videos/month, Pro: 20 videos/month, Premium: 100 videos/month)

### 2. Upload Your First Video
1. Navigate to "Upload Video" from the sidebar
2. Drag and drop your match video or click to browse
3. Add match details (date, opponents, court conditions)
4. Click upload and wait for AI analysis to complete (usually 5-15 minutes)

### 3. View Analysis Results
1. Go to "Video Library" to see all your uploaded videos
2. Click on a completed analysis to view detailed insights
3. Explore different tabs: Overview, Shots, Rallies, Movement, Performance
4. Read AI coaching recommendations and improvement suggestions

### 4. Track Your Progress
1. Visit the Dashboard for an overview of your improvement
2. Use the Progress tab to see trends over time
3. Compare multiple videos to track specific metrics
4. Set personal goals and track achievements

## 🏗️ Architecture

### Backend Stack
- **Node.js & Express**: RESTful API server
- **MongoDB & Mongoose**: Database and ODM
- **Google Cloud Video Intelligence**: AI video analysis
- **Google Cloud Storage**: Video file storage
- **JWT**: Authentication and authorization
- **Multer**: File upload handling

### Frontend Stack
- **React 18 & TypeScript**: Modern UI library with type safety
- **Material-UI**: Component library and design system
- **React Router**: Client-side routing
- **Recharts**: Data visualization
- **Axios**: HTTP client
- **React Dropzone**: File upload interface

### Key Directories
```
├── server.js                 # Main server entry point
├── config/                   # Database and app configuration
├── models/                   # MongoDB schemas (User, Video)
├── routes/                   # API endpoints (auth, videos, analysis, users)
├── services/                 # Google Cloud and external services
├── middleware/               # Authentication and validation
├── client/                   # React frontend application
│   ├── src/
│   │   ├── components/       # Reusable UI components
│   │   ├── pages/            # Route components
│   │   ├── contexts/         # React contexts (Auth, Notifications)
│   │   └── services/         # API client
└── README.md
```

## 🔧 API Endpoints

### Authentication
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `GET /api/auth/me` - Get current user
- `PUT /api/auth/profile` - Update profile

### Videos
- `POST /api/videos/upload` - Upload video for analysis
- `GET /api/videos` - Get user's videos with pagination
- `GET /api/videos/:id` - Get specific video with analysis
- `DELETE /api/videos/:id` - Delete video
- `GET /api/videos/:id/progress` - Get analysis progress

### Analysis
- `GET /api/analysis/:videoId` - Get complete analysis
- `GET /api/analysis/:videoId/shots` - Get shot analysis
- `GET /api/analysis/:videoId/rallies` - Get rally analysis
- `GET /api/analysis/:videoId/movement` - Get movement analysis
- `GET /api/analysis/:videoId/performance` - Get performance metrics
- `GET /api/analysis/:videoId/coaching` - Get AI coaching insights
- `POST /api/analysis/compare` - Compare multiple videos

### Users
- `GET /api/users/dashboard` - Get dashboard data
- `GET /api/users/progress` - Get progress analytics
- `GET /api/users/achievements` - Get user achievements
- `PUT /api/users/goals` - Update personal goals

## 🔒 Security Features

- **JWT Authentication**: Secure token-based authentication
- **Rate Limiting**: API rate limiting to prevent abuse
- **Input Validation**: Comprehensive input validation and sanitization
- **File Type Validation**: Restricted file uploads to supported video formats
- **CORS Protection**: Configured CORS for secure cross-origin requests
- **Helmet Security**: Security headers for Express application

## 📊 Video Analysis Details

### Google Cloud Video Intelligence Features Used
- **Object Tracking**: Detect and track padel balls and rackets
- **Person Detection**: Track player movement and positioning
- **Shot Change Detection**: Identify rallies and game segments
- **Label Detection**: Understand game context and activities

### Custom Analysis Logic
- **Shot Classification**: Categorize shots into types (forehand, backhand, volley, etc.)
- **Rally Analysis**: Calculate rally lengths and patterns
- **Movement Metrics**: Analyze court coverage and player speed
- **Performance Scoring**: Generate accuracy and consistency ratings
- **AI Insights**: Provide personalized coaching recommendations

## 🎯 Subscription Plans

| Feature | Free | Pro | Premium |
|---------|------|-----|---------|
| Videos per month | 3 | 20 | 100 |
| Analysis depth | Basic | Full | Full + Advanced |
| Video comparison | ❌ | ✅ | ✅ |
| Progress tracking | Limited | Full | Full |
| AI coaching | Basic | Advanced | Premium |
| Export reports | ❌ | ✅ | ✅ |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙋‍♂️ Support

For support, email support@padelanalyzer.com or join our Discord server.

## 🎖️ Acknowledgments

- Google Cloud Video Intelligence API for powerful AI analysis
- Material-UI team for the beautiful component library
- The Padel community for inspiration and feedback
- All contributors who helped make this project possible

---

**Made with ❤️ for the Padel community**