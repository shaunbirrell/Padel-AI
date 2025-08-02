import asyncio
from typing import Dict, List, Any, Optional
from datetime import datetime
import cv2
import numpy as np
from google.cloud import videointelligence
from google.cloud.videointelligence import types
import json
from pathlib import Path

from models import (
    ShotAnalysis, RallyAnalysis, PlayerPerformance, 
    TechnicalAnalysis, VideoAnalysis, ShotType
)
from config import settings

class PadelVideoAnalyzer:
    def __init__(self):
        self.video_client = videointelligence.VideoIntelligenceServiceClient()
        self.shot_classifier = PadelShotClassifier()
        
    async def analyze_padel_video(self, video_path: str) -> Dict[str, Any]:
        """Main analysis function that coordinates all analysis types"""
        
        # Get video metadata
        video_metadata = self._get_video_metadata(video_path)
        
        # Run Google Cloud Video Intelligence analysis
        gcp_analysis = await self._run_gcp_analysis(video_path)
        
        # Analyze shots and rallies
        shot_analysis = await self._analyze_shots(gcp_analysis, video_path)
        rally_analysis = self._group_shots_into_rallies(shot_analysis)
        
        # Analyze player performance
        player_performance = self._analyze_player_performance(shot_analysis, rally_analysis)
        
        # Technical analysis
        technical_analysis = self._analyze_technique(shot_analysis)
        
        # Generate insights and recommendations
        match_highlights = self._identify_highlights(rally_analysis)
        improvement_plan = self._generate_improvement_plan(player_performance, technical_analysis)
        
        return {
            "video_metadata": video_metadata,
            "match_duration": video_metadata["duration"],
            "total_rallies": len(rally_analysis),
            "total_shots": len(shot_analysis),
            "rallies": [rally.dict() for rally in rally_analysis],
            "player_performances": [perf.dict() for perf in player_performance],
            "technical_analysis": technical_analysis.dict(),
            "match_intensity": self._calculate_match_intensity(rally_analysis),
            "match_highlights": match_highlights,
            "improvement_plan": improvement_plan,
            "analysis_timestamp": datetime.now().isoformat()
        }
    
    def _get_video_metadata(self, video_path: str) -> Dict[str, Any]:
        """Extract video metadata using OpenCV"""
        cap = cv2.VideoCapture(video_path)
        
        metadata = {
            "duration": cap.get(cv2.CAP_PROP_FRAME_COUNT) / cap.get(cv2.CAP_PROP_FPS),
            "fps": cap.get(cv2.CAP_PROP_FPS),
            "resolution": f"{int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}x{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))}",
            "total_frames": int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        }
        
        cap.release()
        return metadata
    
    async def _run_gcp_analysis(self, video_path: str) -> Dict[str, Any]:
        """Run Google Cloud Video Intelligence API analysis"""
        
        with open(video_path, 'rb') as file:
            input_content = file.read()
        
        # Configure features
        features = [
            videointelligence.Feature.OBJECT_TRACKING,
            videointelligence.Feature.PERSON_DETECTION,
            videointelligence.Feature.SHOT_CHANGE_DETECTION,
            videointelligence.Feature.LABEL_DETECTION
        ]
        
        # Configure video context for sports analysis
        video_context = videointelligence.VideoContext(
            segments=[],
            label_detection_config=videointelligence.LabelDetectionConfig(
                label_detection_mode=videointelligence.LabelDetectionMode.SHOT_AND_FRAME_MODE,
                model="builtin/latest"
            ),
            object_tracking_config=videointelligence.ObjectTrackingConfig(
                model="builtin/latest"
            )
        )
        
        # Start the operation
        operation = self.video_client.annotate_video(
            request={
                "features": features,
                "input_content": input_content,
                "video_context": video_context
            }
        )
        
        # Wait for the operation to complete
        result = operation.result(timeout=600)
        
        return self._parse_gcp_results(result)
    
    def _parse_gcp_results(self, result) -> Dict[str, Any]:
        """Parse Google Cloud Video Intelligence results"""
        
        parsed_results = {
            "shot_changes": [],
            "objects": [],
            "persons": [],
            "labels": []
        }
        
        # Process shot changes
        for shot in result.annotation_results[0].shot_annotations:
            parsed_results["shot_changes"].append({
                "start_time": shot.start_time_offset.total_seconds(),
                "end_time": shot.end_time_offset.total_seconds()
            })
        
        # Process object tracking (including ball tracking)
        for obj in result.annotation_results[0].object_annotations:
            if obj.entity.description.lower() in ["ball", "tennis ball", "sports ball"]:
                parsed_results["objects"].append({
                    "type": "ball",
                    "tracks": [{
                        "timestamp": frame.time_offset.total_seconds(),
                        "bbox": {
                            "x": frame.normalized_bounding_box.left,
                            "y": frame.normalized_bounding_box.top,
                            "width": frame.normalized_bounding_box.right - frame.normalized_bounding_box.left,
                            "height": frame.normalized_bounding_box.bottom - frame.normalized_bounding_box.top
                        }
                    } for frame in obj.frames]
                })
        
        # Process person detection
        for person in result.annotation_results[0].person_detection_annotations:
            parsed_results["persons"].append({
                "tracks": [{
                    "timestamp": track.timestamp_offset.total_seconds(),
                    "landmarks": self._extract_pose_landmarks(track.landmarks) if hasattr(track, 'landmarks') else []
                } for track in person.tracks]
            })
        
        # Process labels for context
        for label in result.annotation_results[0].segment_label_annotations:
            if label.entity.description.lower() in ["tennis", "padel", "racket sport", "sports"]:
                parsed_results["labels"].append({
                    "label": label.entity.description,
                    "segments": [{
                        "start": seg.segment.start_time_offset.total_seconds(),
                        "end": seg.segment.end_time_offset.total_seconds(),
                        "confidence": seg.confidence
                    } for seg in label.segments]
                })
        
        return parsed_results
    
    def _extract_pose_landmarks(self, landmarks) -> List[Dict[str, float]]:
        """Extract pose landmarks for technique analysis"""
        pose_points = []
        for landmark in landmarks:
            pose_points.append({
                "type": landmark.name,
                "x": landmark.point.x,
                "y": landmark.point.y,
                "confidence": landmark.confidence
            })
        return pose_points
    
    async def _analyze_shots(self, gcp_analysis: Dict[str, Any], video_path: str) -> List[ShotAnalysis]:
        """Analyze individual shots using computer vision and GCP data"""
        
        shots = []
        ball_tracks = gcp_analysis.get("objects", [])
        person_tracks = gcp_analysis.get("persons", [])
        
        # Detect shots based on ball trajectory changes and player movements
        shot_events = self._detect_shot_events(ball_tracks, person_tracks)
        
        for event in shot_events:
            shot_type = self.shot_classifier.classify_shot(event, video_path)
            
            shot = ShotAnalysis(
                timestamp=event["timestamp"],
                duration=event["duration"],
                shot_type=shot_type,
                player_position=event["player_position"],
                ball_trajectory=event["ball_trajectory"],
                technique_score=self._calculate_technique_score(event),
                power_estimate=self._estimate_shot_power(event),
                accuracy=self._calculate_accuracy(event),
                recommendations=self._generate_shot_recommendations(shot_type, event)
            )
            shots.append(shot)
        
        return shots
    
    def _detect_shot_events(self, ball_tracks: List[Dict], person_tracks: List[Dict]) -> List[Dict]:
        """Detect shot events from ball and player tracking data"""
        
        shot_events = []
        
        if not ball_tracks or not ball_tracks[0]["tracks"]:
            return shot_events
        
        ball_positions = ball_tracks[0]["tracks"]
        
        # Analyze ball trajectory for direction changes
        for i in range(2, len(ball_positions)):
            prev_pos = ball_positions[i-2]["bbox"]
            curr_pos = ball_positions[i-1]["bbox"]
            next_pos = ball_positions[i]["bbox"]
            
            # Calculate velocity changes
            velocity_change = self._calculate_velocity_change(prev_pos, curr_pos, next_pos)
            
            if velocity_change > 0.3:  # Threshold for shot detection
                # Find closest player
                timestamp = ball_positions[i-1]["timestamp"]
                player_pos = self._find_closest_player(timestamp, person_tracks)
                
                shot_events.append({
                    "timestamp": timestamp,
                    "duration": 0.5,  # Approximate shot duration
                    "player_position": player_pos,
                    "ball_trajectory": self._extract_trajectory(ball_positions, i-5, i+10),
                    "velocity_change": velocity_change
                })
        
        return shot_events
    
    def _calculate_velocity_change(self, prev: Dict, curr: Dict, next: Dict) -> float:
        """Calculate velocity change to detect shots"""
        
        # Calculate velocities
        v1_x = curr["x"] - prev["x"]
        v1_y = curr["y"] - prev["y"]
        v2_x = next["x"] - curr["x"]
        v2_y = next["y"] - curr["y"]
        
        # Calculate angle change
        angle_change = np.arccos(np.clip(
            (v1_x * v2_x + v1_y * v2_y) / 
            (np.sqrt(v1_x**2 + v1_y**2) * np.sqrt(v2_x**2 + v2_y**2) + 1e-6),
            -1, 1
        ))
        
        return angle_change / np.pi
    
    def _find_closest_player(self, timestamp: float, person_tracks: List[Dict]) -> Dict[str, float]:
        """Find the closest player to the ball at a given timestamp"""
        
        # Simple implementation - in real scenario would use more sophisticated tracking
        return {"x": 0.5, "y": 0.8}  # Mock position
    
    def _extract_trajectory(self, positions: List[Dict], start_idx: int, end_idx: int) -> List[Dict[str, float]]:
        """Extract ball trajectory for a shot"""
        
        trajectory = []
        start_idx = max(0, start_idx)
        end_idx = min(len(positions), end_idx)
        
        for i in range(start_idx, end_idx):
            trajectory.append({
                "timestamp": positions[i]["timestamp"],
                "x": positions[i]["bbox"]["x"],
                "y": positions[i]["bbox"]["y"]
            })
        
        return trajectory
    
    def _group_shots_into_rallies(self, shots: List[ShotAnalysis]) -> List[RallyAnalysis]:
        """Group consecutive shots into rallies"""
        
        rallies = []
        current_rally_shots = []
        rally_number = 1
        
        for i, shot in enumerate(shots):
            if i == 0:
                current_rally_shots.append(shot)
                continue
            
            # Check if this shot is part of the same rally
            time_diff = shot.timestamp - shots[i-1].timestamp
            
            if time_diff < 5.0:  # Max 5 seconds between shots in a rally
                current_rally_shots.append(shot)
            else:
                # End current rally and start new one
                if current_rally_shots:
                    rally = self._create_rally_analysis(rally_number, current_rally_shots)
                    rallies.append(rally)
                    rally_number += 1
                
                current_rally_shots = [shot]
        
        # Add last rally
        if current_rally_shots:
            rally = self._create_rally_analysis(rally_number, current_rally_shots)
            rallies.append(rally)
        
        return rallies
    
    def _create_rally_analysis(self, rally_number: int, shots: List[ShotAnalysis]) -> RallyAnalysis:
        """Create rally analysis from grouped shots"""
        
        return RallyAnalysis(
            rally_number=rally_number,
            start_time=shots[0].timestamp,
            end_time=shots[-1].timestamp + shots[-1].duration,
            duration=shots[-1].timestamp + shots[-1].duration - shots[0].timestamp,
            total_shots=len(shots),
            winner=self._determine_rally_winner(shots),
            shot_sequence=shots,
            rally_type=self._classify_rally_type(shots),
            intensity_level=self._calculate_rally_intensity(shots),
            tactical_insights=self._generate_tactical_insights(shots)
        )
    
    def _determine_rally_winner(self, shots: List[ShotAnalysis]) -> Optional[str]:
        """Determine who won the rally based on the last shot"""
        
        # Simplified logic - in real implementation would analyze errors
        last_shot = shots[-1]
        if last_shot.accuracy < 0.5:
            return "opponent"
        return "player"
    
    def _classify_rally_type(self, shots: List[ShotAnalysis]) -> str:
        """Classify rally as offensive, defensive, or neutral"""
        
        offensive_shots = sum(1 for s in shots if s.shot_type in [ShotType.SMASH, ShotType.VIBORA])
        defensive_shots = sum(1 for s in shots if s.shot_type in [ShotType.LOB, ShotType.CHIQUITA])
        
        if offensive_shots > defensive_shots * 1.5:
            return "offensive"
        elif defensive_shots > offensive_shots * 1.5:
            return "defensive"
        else:
            return "neutral"
    
    def _calculate_rally_intensity(self, shots: List[ShotAnalysis]) -> float:
        """Calculate rally intensity based on shot frequency and power"""
        
        if not shots:
            return 0.0
        
        duration = shots[-1].timestamp - shots[0].timestamp
        shot_frequency = len(shots) / (duration + 1)
        avg_power = sum(s.power_estimate for s in shots) / len(shots)
        
        return min(1.0, (shot_frequency * 0.5 + avg_power * 0.5))
    
    def _generate_tactical_insights(self, shots: List[ShotAnalysis]) -> List[str]:
        """Generate tactical insights for a rally"""
        
        insights = []
        
        # Analyze shot patterns
        shot_types = [s.shot_type for s in shots]
        
        if shot_types.count(ShotType.LOB) >= 2:
            insights.append("Multiple lobs used - consider mixing with offensive shots")
        
        if shot_types.count(ShotType.VOLLEY) >= 3:
            insights.append("Good net play demonstrated in this rally")
        
        # Analyze positioning
        avg_position_y = sum(s.player_position["y"] for s in shots) / len(shots)
        if avg_position_y < 0.4:
            insights.append("Strong net position maintained throughout rally")
        
        return insights
    
    def _analyze_player_performance(self, shots: List[ShotAnalysis], rallies: List[RallyAnalysis]) -> List[PlayerPerformance]:
        """Analyze overall player performance"""
        
        # For single player analysis
        shot_distribution = {}
        for shot in shots:
            shot_type = shot.shot_type.value
            shot_distribution[shot_type] = shot_distribution.get(shot_type, 0) + 1
        
        winner_shots = sum(1 for r in rallies if r.winner == "player")
        unforced_errors = sum(1 for s in shots if s.accuracy < 0.3)
        
        performance = PlayerPerformance(
            player_id="player1",
            total_shots=len(shots),
            shot_distribution=shot_distribution,
            accuracy_rate=sum(s.accuracy for s in shots) / len(shots) if shots else 0,
            winner_shots=winner_shots,
            unforced_errors=unforced_errors,
            court_coverage=self._calculate_court_coverage(shots),
            movement_efficiency=self._calculate_movement_efficiency(shots),
            strengths=self._identify_strengths(shots, rallies),
            areas_for_improvement=self._identify_improvements(shots, rallies)
        )
        
        return [performance]
    
    def _calculate_court_coverage(self, shots: List[ShotAnalysis]) -> float:
        """Calculate how well the player covers the court"""
        
        if not shots:
            return 0.0
        
        positions = [s.player_position for s in shots]
        x_range = max(p["x"] for p in positions) - min(p["x"] for p in positions)
        y_range = max(p["y"] for p in positions) - min(p["y"] for p in positions)
        
        return min(1.0, (x_range + y_range) / 2)
    
    def _calculate_movement_efficiency(self, shots: List[ShotAnalysis]) -> float:
        """Calculate movement efficiency between shots"""
        
        # Simplified - would analyze actual movement patterns
        return 0.75
    
    def _identify_strengths(self, shots: List[ShotAnalysis], rallies: List[RallyAnalysis]) -> List[str]:
        """Identify player strengths"""
        
        strengths = []
        
        # Analyze shot accuracy
        high_accuracy_shots = [s for s in shots if s.accuracy > 0.8]
        if len(high_accuracy_shots) / len(shots) > 0.6:
            strengths.append("Excellent shot accuracy")
        
        # Analyze volleys
        volleys = [s for s in shots if s.shot_type == ShotType.VOLLEY]
        if volleys and sum(v.technique_score for v in volleys) / len(volleys) > 0.7:
            strengths.append("Strong volley technique")
        
        # Analyze rally wins
        won_rallies = [r for r in rallies if r.winner == "player"]
        if len(won_rallies) / len(rallies) > 0.6:
            strengths.append("Good rally construction and finishing")
        
        return strengths
    
    def _identify_improvements(self, shots: List[ShotAnalysis], rallies: List[RallyAnalysis]) -> List[str]:
        """Identify areas for improvement"""
        
        improvements = []
        
        # Check backhand performance
        backhands = [s for s in shots if s.shot_type == ShotType.BACKHAND]
        if backhands and sum(b.technique_score for b in backhands) / len(backhands) < 0.6:
            improvements.append("Work on backhand technique and consistency")
        
        # Check defensive play
        defensive_rallies = [r for r in rallies if r.rally_type == "defensive"]
        if defensive_rallies:
            lost_defensive = [r for r in defensive_rallies if r.winner != "player"]
            if len(lost_defensive) / len(defensive_rallies) > 0.7:
                improvements.append("Improve defensive play and counter-attacking")
        
        return improvements
    
    def _analyze_technique(self, shots: List[ShotAnalysis]) -> TechnicalAnalysis:
        """Analyze technical aspects of the player's game"""
        
        # Calculate average scores
        technique_scores = [s.technique_score for s in shots]
        
        return TechnicalAnalysis(
            footwork_score=0.7,  # Would be calculated from pose analysis
            body_rotation_score=0.75,
            racket_preparation_score=0.8,
            follow_through_score=0.7,
            timing_consistency=np.std(technique_scores) if technique_scores else 0,
            technical_recommendations=[
                "Focus on early racket preparation for better shot quality",
                "Improve footwork positioning for wall shots",
                "Work on follow-through consistency for better control"
            ]
        )
    
    def _calculate_match_intensity(self, rallies: List[RallyAnalysis]) -> float:
        """Calculate overall match intensity"""
        
        if not rallies:
            return 0.0
        
        return sum(r.intensity_level for r in rallies) / len(rallies)
    
    def _identify_highlights(self, rallies: List[RallyAnalysis]) -> List[Dict[str, Any]]:
        """Identify match highlights"""
        
        highlights = []
        
        # Long rallies
        for rally in rallies:
            if rally.total_shots >= 10:
                highlights.append({
                    "timestamp": rally.start_time,
                    "duration": rally.duration,
                    "type": "long_rally",
                    "description": f"Impressive {rally.total_shots}-shot rally"
                })
        
        # High intensity rallies
        intense_rallies = [r for r in rallies if r.intensity_level > 0.8]
        for rally in intense_rallies[:3]:  # Top 3
            highlights.append({
                "timestamp": rally.start_time,
                "duration": rally.duration,
                "type": "high_intensity",
                "description": "High-intensity rally with aggressive play"
            })
        
        return highlights
    
    def _generate_improvement_plan(self, performances: List[PlayerPerformance], technical: TechnicalAnalysis) -> List[str]:
        """Generate personalized improvement plan"""
        
        plan = []
        
        # Based on performance analysis
        if performances[0].accuracy_rate < 0.6:
            plan.append("Practice shot placement drills to improve accuracy")
        
        if performances[0].movement_efficiency < 0.7:
            plan.append("Work on court movement and positioning exercises")
        
        # Based on technical analysis
        if technical.footwork_score < 0.7:
            plan.append("Focus on footwork drills, especially split-step timing")
        
        if technical.follow_through_score < 0.7:
            plan.append("Practice follow-through consistency for better shot control")
        
        # Add specific drill recommendations
        plan.append("Recommended drills: Wall practice for consistency, Volley reflex training")
        
        return plan
    
    def _calculate_technique_score(self, event: Dict) -> float:
        """Calculate technique score for a shot"""
        # Simplified implementation
        return np.random.uniform(0.6, 0.9)
    
    def _estimate_shot_power(self, event: Dict) -> float:
        """Estimate shot power based on ball velocity"""
        # Simplified implementation
        return np.random.uniform(0.5, 0.9)
    
    def _calculate_accuracy(self, event: Dict) -> float:
        """Calculate shot accuracy"""
        # Simplified implementation
        return np.random.uniform(0.6, 0.95)
    
    def _generate_shot_recommendations(self, shot_type: ShotType, event: Dict) -> List[str]:
        """Generate specific recommendations for a shot"""
        
        recommendations = []
        
        if shot_type == ShotType.VOLLEY:
            recommendations.append("Keep racket head up for better control")
        elif shot_type == ShotType.SMASH:
            recommendations.append("Focus on timing and contact point")
        elif shot_type == ShotType.LOB:
            recommendations.append("Add more height for defensive lobs")
        
        return recommendations


class PadelShotClassifier:
    """Classifier for different types of Padel shots"""
    
    def classify_shot(self, event: Dict, video_path: str) -> ShotType:
        """Classify the type of shot based on trajectory and player position"""
        
        # Simplified classification logic
        # In a real implementation, this would use ML models or more sophisticated heuristics
        
        player_y = event["player_position"]["y"]
        trajectory = event["ball_trajectory"]
        
        if len(trajectory) < 3:
            return ShotType.FOREHAND
        
        # Check if near net
        if player_y < 0.3:
            return ShotType.VOLLEY
        
        # Check trajectory for lob
        y_positions = [t["y"] for t in trajectory]
        if max(y_positions) - min(y_positions) > 0.4:
            return ShotType.LOB
        
        # Random selection for demo purposes
        import random
        return random.choice([
            ShotType.FOREHAND,
            ShotType.BACKHAND,
            ShotType.SMASH,
            ShotType.BANDEJA,
            ShotType.VIBORA
        ])