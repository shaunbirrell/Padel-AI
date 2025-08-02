from fastapi import FastAPI, UploadFile, File, HTTPException, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from typing import List, Optional
import os
import uuid
from datetime import datetime
import aiofiles
from google.cloud import videointelligence
from google.cloud import storage
from pydantic import BaseModel
from pathlib import Path
import json

from config import settings
from video_analyzer import PadelVideoAnalyzer
from models import VideoAnalysis, AnalysisStatus, VideoMetadata

app = FastAPI(title="Padel Video Analyzer", version="1.0.0")

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize services
video_analyzer = PadelVideoAnalyzer()

# Create necessary directories
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)
ANALYSIS_DIR = Path("analysis_results")
ANALYSIS_DIR.mkdir(exist_ok=True)

class VideoUploadResponse(BaseModel):
    video_id: str
    filename: str
    message: str

class AnalysisRequest(BaseModel):
    video_id: str
    analysis_types: List[str] = ["shot_detection", "rally_analysis", "player_tracking"]

@app.get("/")
async def root():
    return {"message": "Padel Video Analyzer API", "version": "1.0.0"}

@app.post("/api/upload", response_model=VideoUploadResponse)
async def upload_video(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...)
):
    """Upload a video for analysis"""
    if not file.filename.endswith(('.mp4', '.avi', '.mov', '.mkv')):
        raise HTTPException(status_code=400, detail="Invalid video format")
    
    # Generate unique video ID
    video_id = str(uuid.uuid4())
    file_extension = Path(file.filename).suffix
    saved_filename = f"{video_id}{file_extension}"
    file_path = UPLOAD_DIR / saved_filename
    
    # Save uploaded file
    try:
        async with aiofiles.open(file_path, 'wb') as f:
            content = await file.read()
            await f.write(content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save file: {str(e)}")
    
    # Create metadata
    metadata = VideoMetadata(
        video_id=video_id,
        filename=file.filename,
        upload_time=datetime.now(),
        file_path=str(file_path),
        status=AnalysisStatus.UPLOADED
    )
    
    # Save metadata
    metadata_path = ANALYSIS_DIR / f"{video_id}_metadata.json"
    with open(metadata_path, 'w') as f:
        json.dump(metadata.dict(), f, default=str)
    
    # Start background analysis
    background_tasks.add_task(analyze_video_background, video_id, str(file_path))
    
    return VideoUploadResponse(
        video_id=video_id,
        filename=file.filename,
        message="Video uploaded successfully. Analysis started in background."
    )

@app.post("/api/analyze")
async def analyze_video(request: AnalysisRequest):
    """Trigger video analysis for specific types"""
    metadata_path = ANALYSIS_DIR / f"{request.video_id}_metadata.json"
    
    if not metadata_path.exists():
        raise HTTPException(status_code=404, detail="Video not found")
    
    with open(metadata_path, 'r') as f:
        metadata = json.load(f)
    
    if metadata['status'] == AnalysisStatus.ANALYZING.value:
        return {"message": "Analysis already in progress", "status": metadata['status']}
    
    # Update status
    metadata['status'] = AnalysisStatus.ANALYZING.value
    metadata['analysis_types'] = request.analysis_types
    
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, default=str)
    
    return {"message": "Analysis started", "video_id": request.video_id}

@app.get("/api/analysis/{video_id}")
async def get_analysis(video_id: str):
    """Get analysis results for a video"""
    analysis_path = ANALYSIS_DIR / f"{video_id}_analysis.json"
    metadata_path = ANALYSIS_DIR / f"{video_id}_metadata.json"
    
    if not metadata_path.exists():
        raise HTTPException(status_code=404, detail="Video not found")
    
    with open(metadata_path, 'r') as f:
        metadata = json.load(f)
    
    if metadata['status'] != AnalysisStatus.COMPLETED.value:
        return {
            "video_id": video_id,
            "status": metadata['status'],
            "message": "Analysis not completed yet"
        }
    
    if not analysis_path.exists():
        raise HTTPException(status_code=404, detail="Analysis results not found")
    
    with open(analysis_path, 'r') as f:
        analysis = json.load(f)
    
    return {
        "video_id": video_id,
        "status": metadata['status'],
        "analysis": analysis
    }

@app.get("/api/videos")
async def list_videos():
    """List all uploaded videos with their status"""
    videos = []
    
    for metadata_file in ANALYSIS_DIR.glob("*_metadata.json"):
        with open(metadata_file, 'r') as f:
            metadata = json.load(f)
            videos.append({
                "video_id": metadata['video_id'],
                "filename": metadata['filename'],
                "upload_time": metadata['upload_time'],
                "status": metadata['status']
            })
    
    return {"videos": sorted(videos, key=lambda x: x['upload_time'], reverse=True)}

async def analyze_video_background(video_id: str, file_path: str):
    """Background task to analyze video"""
    try:
        # Update status to analyzing
        metadata_path = ANALYSIS_DIR / f"{video_id}_metadata.json"
        with open(metadata_path, 'r') as f:
            metadata = json.load(f)
        
        metadata['status'] = AnalysisStatus.ANALYZING.value
        metadata['analysis_start_time'] = str(datetime.now())
        
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, default=str)
        
        # Perform analysis
        analysis_results = await video_analyzer.analyze_padel_video(file_path)
        
        # Save analysis results
        analysis_path = ANALYSIS_DIR / f"{video_id}_analysis.json"
        with open(analysis_path, 'w') as f:
            json.dump(analysis_results, f, default=str)
        
        # Update status to completed
        metadata['status'] = AnalysisStatus.COMPLETED.value
        metadata['analysis_end_time'] = str(datetime.now())
        
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, default=str)
        
    except Exception as e:
        # Update status to failed
        metadata['status'] = AnalysisStatus.FAILED.value
        metadata['error'] = str(e)
        
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, default=str)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)