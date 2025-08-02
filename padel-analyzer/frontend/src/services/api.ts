import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Types
export interface VideoUploadResponse {
  video_id: string;
  filename: string;
  message: string;
}

export interface VideoMetadata {
  video_id: string;
  filename: string;
  upload_time: string;
  status: 'uploaded' | 'analyzing' | 'completed' | 'failed';
}

export interface VideoAnalysis {
  video_id: string;
  status: string;
  analysis?: {
    video_metadata: any;
    match_duration: number;
    total_rallies: number;
    total_shots: number;
    rallies: Rally[];
    player_performances: PlayerPerformance[];
    technical_analysis: TechnicalAnalysis;
    match_intensity: number;
    match_highlights: MatchHighlight[];
    improvement_plan: string[];
    analysis_timestamp: string;
  };
}

export interface Rally {
  rally_number: number;
  start_time: number;
  end_time: number;
  duration: number;
  total_shots: number;
  winner: string | null;
  shot_sequence: Shot[];
  rally_type: string;
  intensity_level: number;
  tactical_insights: string[];
}

export interface Shot {
  timestamp: number;
  duration: number;
  shot_type: string;
  player_position: { x: number; y: number };
  ball_trajectory: { timestamp: number; x: number; y: number }[];
  technique_score: number;
  power_estimate: number;
  accuracy: number;
  recommendations: string[];
}

export interface PlayerPerformance {
  player_id: string;
  total_shots: number;
  shot_distribution: Record<string, number>;
  accuracy_rate: number;
  winner_shots: number;
  unforced_errors: number;
  court_coverage: number;
  movement_efficiency: number;
  strengths: string[];
  areas_for_improvement: string[];
}

export interface TechnicalAnalysis {
  footwork_score: number;
  body_rotation_score: number;
  racket_preparation_score: number;
  follow_through_score: number;
  timing_consistency: number;
  technical_recommendations: string[];
}

export interface MatchHighlight {
  timestamp: number;
  duration: number;
  type: string;
  description: string;
}

// API Methods
export const uploadVideo = async (file: File): Promise<VideoUploadResponse> => {
  const formData = new FormData();
  formData.append('file', file);

  const response = await api.post<VideoUploadResponse>('/api/upload', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
  });

  return response.data;
};

export const getVideos = async (): Promise<{ videos: VideoMetadata[] }> => {
  const response = await api.get('/api/videos');
  return response.data;
};

export const getAnalysis = async (videoId: string): Promise<VideoAnalysis> => {
  const response = await api.get<VideoAnalysis>(`/api/analysis/${videoId}`);
  return response.data;
};

export const triggerAnalysis = async (videoId: string, analysisTypes: string[]): Promise<any> => {
  const response = await api.post('/api/analyze', {
    video_id: videoId,
    analysis_types: analysisTypes,
  });
  return response.data;
};

export default api;