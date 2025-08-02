from pydantic import BaseModel
from datetime import datetime
from typing import List, Dict, Optional, Any
from enum import Enum

class AnalysisStatus(str, Enum):
    UPLOADED = "uploaded"
    ANALYZING = "analyzing"
    COMPLETED = "completed"
    FAILED = "failed"

class ShotType(str, Enum):
    FOREHAND = "forehand"
    BACKHAND = "backhand"
    VOLLEY = "volley"
    SMASH = "smash"
    LOB = "lob"
    SERVE = "serve"
    BANDEJA = "bandeja"
    VIBORA = "vibora"
    CHIQUITA = "chiquita"
    WALL_SHOT = "wall_shot"

class ShotAnalysis(BaseModel):
    timestamp: float
    duration: float
    shot_type: ShotType
    player_position: Dict[str, float]
    ball_trajectory: List[Dict[str, float]]
    technique_score: float
    power_estimate: float
    accuracy: float
    recommendations: List[str]

class RallyAnalysis(BaseModel):
    rally_number: int
    start_time: float
    end_time: float
    duration: float
    total_shots: int
    winner: Optional[str]
    shot_sequence: List[ShotAnalysis]
    rally_type: str  # offensive, defensive, neutral
    intensity_level: float
    tactical_insights: List[str]

class PlayerPerformance(BaseModel):
    player_id: str
    total_shots: int
    shot_distribution: Dict[str, int]
    accuracy_rate: float
    winner_shots: int
    unforced_errors: int
    court_coverage: float
    movement_efficiency: float
    strengths: List[str]
    areas_for_improvement: List[str]

class TechnicalAnalysis(BaseModel):
    footwork_score: float
    body_rotation_score: float
    racket_preparation_score: float
    follow_through_score: float
    timing_consistency: float
    technical_recommendations: List[str]

class VideoMetadata(BaseModel):
    video_id: str
    filename: str
    upload_time: datetime
    file_path: str
    status: AnalysisStatus
    duration: Optional[float] = None
    resolution: Optional[str] = None
    fps: Optional[float] = None

class VideoAnalysis(BaseModel):
    video_id: str
    analysis_timestamp: datetime
    match_duration: float
    total_rallies: int
    total_shots: int
    rallies: List[RallyAnalysis]
    player_performances: List[PlayerPerformance]
    technical_analysis: TechnicalAnalysis
    match_intensity: float
    match_highlights: List[Dict[str, Any]]
    improvement_plan: List[str]
    
class AnalysisHighlight(BaseModel):
    timestamp: float
    duration: float
    type: str  # "great_shot", "long_rally", "tactical_play"
    description: str
    thumbnail_url: Optional[str] = None

class MatchStatistics(BaseModel):
    total_points: int
    longest_rally: RallyAnalysis
    average_rally_duration: float
    shot_type_distribution: Dict[str, int]
    court_zone_usage: Dict[str, float]
    momentum_shifts: List[Dict[str, Any]]