# Padel Match Video Analyzer

An AI-powered platform for analyzing Padel match videos using Google Cloud Video Intelligence API. Upload your match recordings and get detailed insights on shots, volleys, rallies, and technique to improve your game.

![Padel Analyzer Demo](docs/demo-screenshot.png)

## Features

### 📊 Comprehensive Shot Analysis
- Detailed breakdown of all shot types (forehand, backhand, volley, smash, lob, bandeja, víbora, etc.)
- Shot accuracy and power estimation
- Technique scoring with personalized recommendations

### 🎾 Rally Intelligence
- Automatic rally detection and grouping
- Rally intensity and type classification (offensive/defensive/neutral)
- Tactical insights for each rally
- Shot sequence analysis

### 📈 Performance Metrics
- Player movement and court coverage analysis
- Shot distribution visualization
- Accuracy rates and error tracking
- Technical scoring (footwork, body rotation, racket preparation, follow-through)

### 🎯 Personalized Recommendations
- AI-generated improvement plans
- Training focus areas prioritization
- Technique-specific recommendations
- Progress tracking over multiple sessions

### 🎥 Video Features
- Match highlights automatic detection
- Rally-by-rally video navigation
- Timestamp-based shot viewing
- Support for multiple video formats (MP4, AVI, MOV, MKV)

## Tech Stack

### Backend
- **FastAPI** - Modern Python web framework
- **Google Cloud Video Intelligence API** - AI-powered video analysis
- **OpenCV** - Video processing and metadata extraction
- **Pydantic** - Data validation and serialization

### Frontend
- **React** with TypeScript - UI framework
- **Vite** - Fast development build tool
- **Recharts** - Data visualization
- **React Player** - Video playback
- **Tailwind CSS** - Utility-first styling
- **Lucide React** - Modern icon library

## Prerequisites

- Python 3.8+
- Node.js 16+
- Google Cloud Platform account with Video Intelligence API enabled
- Service account credentials for GCP

## Installation

### 1. Clone the repository
```bash
git clone https://github.com/yourusername/padel-analyzer.git
cd padel-analyzer
```

### 2. Backend Setup

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp .env.example .env
# Edit .env with your Google Cloud credentials
```

### 3. Configure Google Cloud

1. Create a new project in Google Cloud Console
2. Enable the Video Intelligence API
3. Create a service account and download the JSON credentials
4. Set the path to your credentials in `.env`:
   ```
   GOOGLE_APPLICATION_CREDENTIALS=path/to/your/credentials.json
   GOOGLE_CLOUD_PROJECT=your-project-id
   ```

### 4. Frontend Setup

```bash
cd ../frontend

# Install dependencies
npm install

# Create environment file
echo "VITE_API_URL=http://localhost:8000" > .env
```

## Running the Application

### Start the Backend

```bash
cd backend
python main.py
```

The API will be available at `http://localhost:8000`

### Start the Frontend

```bash
cd frontend
npm run dev
```

The application will be available at `http://localhost:5173`

## Usage

1. **Upload Video**: Navigate to the Upload page and drag & drop your Padel match video
2. **Wait for Analysis**: The AI will process your video (this may take several minutes)
3. **View Results**: Once complete, explore the comprehensive analysis with:
   - Match overview and statistics
   - Rally-by-rally breakdown
   - Technical analysis scores
   - Personalized recommendations

## API Documentation

Once the backend is running, visit `http://localhost:8000/docs` for interactive API documentation.

### Key Endpoints

- `POST /api/upload` - Upload a video for analysis
- `GET /api/videos` - List all uploaded videos
- `GET /api/analysis/{video_id}` - Get analysis results
- `POST /api/analyze` - Trigger analysis for specific types

## Development

### Backend Development

```bash
cd backend
uvicorn main:app --reload
```

### Frontend Development

```bash
cd frontend
npm run dev
```

### Running Tests

```bash
# Backend tests
cd backend
pytest

# Frontend tests
cd frontend
npm test
```

## Deployment

### Docker Deployment

```bash
# Build and run with Docker Compose
docker-compose up --build
```

### Cloud Deployment

See [deployment guide](docs/deployment.md) for instructions on deploying to:
- Google Cloud Platform
- AWS
- Azure
- Heroku

## Video Recording Tips

For best analysis results:

1. **Camera Position**: Place camera to capture the entire court
2. **Stability**: Use a tripod or stable surface
3. **Quality**: Record in HD (720p or higher)
4. **Lighting**: Ensure good lighting conditions
5. **Duration**: Include complete rallies

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Google Cloud Video Intelligence API for powering the video analysis
- The Padel community for inspiration and feedback
- OpenCV community for video processing capabilities

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Contact: support@padelanalyzer.com

---

Made with ❤️ for the Padel community