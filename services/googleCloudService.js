const { VideoIntelligenceServiceClient } = require('@google-cloud/video-intelligence');
const { Storage } = require('@google-cloud/storage');
const path = require('path');

class GoogleCloudService {
  constructor() {
    // Initialize Video Intelligence client
    this.videoClient = new VideoIntelligenceServiceClient({
      keyFilename: process.env.GOOGLE_CLOUD_KEY_FILE,
      projectId: process.env.GOOGLE_CLOUD_PROJECT_ID,
    });

    // Initialize Storage client
    this.storage = new Storage({
      keyFilename: process.env.GOOGLE_CLOUD_KEY_FILE,
      projectId: process.env.GOOGLE_CLOUD_PROJECT_ID,
    });

    this.bucket = this.storage.bucket(process.env.GOOGLE_CLOUD_STORAGE_BUCKET);
  }

  /**
   * Upload video to Google Cloud Storage
   */
  async uploadVideo(file, userId, videoId) {
    try {
      const fileName = `videos/${userId}/${videoId}/${file.originalname}`;
      const fileUpload = this.bucket.file(fileName);

      const stream = fileUpload.createWriteStream({
        metadata: {
          contentType: file.mimetype,
          metadata: {
            uploadedBy: userId,
            videoId: videoId,
            originalName: file.originalname
          }
        },
        resumable: false
      });

      return new Promise((resolve, reject) => {
        stream.on('error', (error) => {
          reject(error);
        });

        stream.on('finish', () => {
          resolve({
            fileName,
            publicUrl: `gs://${process.env.GOOGLE_CLOUD_STORAGE_BUCKET}/${fileName}`,
            downloadUrl: `https://storage.googleapis.com/${process.env.GOOGLE_CLOUD_STORAGE_BUCKET}/${fileName}`
          });
        });

        stream.end(file.buffer);
      });
    } catch (error) {
      throw new Error(`Upload failed: ${error.message}`);
    }
  }

  /**
   * Analyze video using Google Cloud Video Intelligence API
   */
  async analyzeVideo(videoUri) {
    try {
      const request = {
        inputUri: videoUri,
        features: [
          'LABEL_DETECTION',
          'SHOT_CHANGE_DETECTION',
          'OBJECT_TRACKING',
          'PERSON_DETECTION',
          'FACE_DETECTION'
        ],
        videoContext: {
          labelDetectionConfig: {
            mode: 'SHOT_AND_FRAME_MODE',
            stationaryCamera: false
          },
          shotChangeDetectionConfig: {
            model: 'builtin/latest'
          },
          objectTrackingConfig: {
            model: 'builtin/latest'
          },
          personDetectionConfig: {
            includeBoundingBoxes: true,
            includePoseLandmarks: true,
            includeAttributes: true
          }
        }
      };

      console.log('🎥 Starting video analysis...');
      const [operation] = await this.videoClient.annotateVideo(request);
      console.log('📊 Video analysis job created:', operation.name);

      return operation.name;
    } catch (error) {
      throw new Error(`Video analysis failed: ${error.message}`);
    }
  }

  /**
   * Get analysis results from operation
   */
  async getAnalysisResults(operationName) {
    try {
      const [operation] = await this.videoClient.checkAnnotateVideoProgress(operationName);
      
      if (!operation.done) {
        return { status: 'processing', progress: operation.metadata?.progressPercent || 0 };
      }

      if (operation.error) {
        throw new Error(`Analysis failed: ${operation.error.message}`);
      }

      const results = operation.result;
      return this.processAnalysisResults(results);
    } catch (error) {
      throw new Error(`Failed to get analysis results: ${error.message}`);
    }
  }

  /**
   * Process and interpret Video Intelligence API results for Padel analysis
   */
  processAnalysisResults(results) {
    const analysis = {
      status: 'completed',
      processedAt: new Date(),
      shots: { total: 0, successful: 0, errors: 0, winners: 0, breakdown: {} },
      rallies: { total: 0, averageLength: 0, longestRally: 0 },
      movement: { distanceCovered: 0, averageSpeed: 0, maxSpeed: 0 },
      performance: { accuracy: 0, consistency: 0, aggressiveness: 5 },
      timeline: [],
      insights: { strengths: [], weaknesses: [], recommendations: [] },
      errors: { unforced: 0, forced: 0, netErrors: 0 },
      heatMap: { shotPositions: [], movementPath: [] }
    };

    try {
      // Process shot changes to identify rallies
      if (results.shotAnnotations) {
        analysis.rallies.total = results.shotAnnotations.length;
        const shotDurations = results.shotAnnotations.map(shot => 
          this.timeToSeconds(shot.endTimeOffset) - this.timeToSeconds(shot.startTimeOffset)
        );
        analysis.rallies.averageLength = shotDurations.reduce((a, b) => a + b, 0) / shotDurations.length;
        analysis.rallies.longestRally = Math.max(...shotDurations);
      }

      // Process person detection for movement analysis
      if (results.personDetectionAnnotations) {
        const personTracks = results.personDetectionAnnotations.flatMap(annotation => annotation.tracks || []);
        
        if (personTracks.length > 0) {
          analysis.movement = this.analyzeMovement(personTracks);
          analysis.heatMap.movementPath = this.generateMovementPath(personTracks);
        }
      }

      // Process object tracking for ball and racket detection
      if (results.objectAnnotations) {
        const ballTracks = results.objectAnnotations.filter(obj => 
          obj.entity?.description?.toLowerCase().includes('ball') ||
          obj.entity?.description?.toLowerCase().includes('sport')
        );
        
        const racketTracks = results.objectAnnotations.filter(obj =>
          obj.entity?.description?.toLowerCase().includes('racket') ||
          obj.entity?.description?.toLowerCase().includes('tennis') ||
          obj.entity?.description?.toLowerCase().includes('paddle')
        );

        analysis.shots = this.analyzeShotData(ballTracks, racketTracks);
        analysis.heatMap.shotPositions = this.generateShotHeatMap(ballTracks);
      }

      // Process labels for context and insights
      if (results.segmentLabelAnnotations) {
        analysis.insights = this.generateInsights(results.segmentLabelAnnotations);
      }

      // Calculate performance metrics
      analysis.performance = this.calculatePerformanceMetrics(analysis);

      // Generate timeline
      analysis.timeline = this.generateTimeline(results);

      return analysis;
    } catch (error) {
      console.error('Error processing analysis results:', error);
      return { 
        ...analysis, 
        status: 'completed_with_errors',
        processingError: error.message 
      };
    }
  }

  /**
   * Analyze movement patterns from person tracking data
   */
  analyzeMovement(personTracks) {
    if (!personTracks.length) return { distanceCovered: 0, averageSpeed: 0, maxSpeed: 0 };

    let totalDistance = 0;
    let maxSpeed = 0;
    const speeds = [];

    personTracks.forEach(track => {
      const timestampedObjects = track.timestampedObjects || [];
      
      for (let i = 1; i < timestampedObjects.length; i++) {
        const prev = timestampedObjects[i - 1];
        const curr = timestampedObjects[i];
        
        if (prev.normalizedBoundingBox && curr.normalizedBoundingBox) {
          const distance = this.calculateDistance(
            prev.normalizedBoundingBox,
            curr.normalizedBoundingBox
          );
          
          const timeDiff = this.timeToSeconds(curr.timeOffset) - this.timeToSeconds(prev.timeOffset);
          const speed = timeDiff > 0 ? distance / timeDiff : 0;
          
          totalDistance += distance;
          speeds.push(speed);
          maxSpeed = Math.max(maxSpeed, speed);
        }
      }
    });

    return {
      distanceCovered: Math.round(totalDistance * 10), // Rough conversion to meters
      averageSpeed: speeds.length > 0 ? Math.round(speeds.reduce((a, b) => a + b, 0) / speeds.length * 3.6) : 0, // km/h
      maxSpeed: Math.round(maxSpeed * 3.6), // km/h
      timeInEachZone: this.calculateCourtZones(personTracks)
    };
  }

  /**
   * Analyze shot data from ball and racket tracking
   */
  analyzeShotData(ballTracks, racketTracks) {
    const shots = {
      total: 0,
      successful: 0,
      errors: 0,
      winners: 0,
      breakdown: {
        forehands: 0,
        backhands: 0,
        volleys: 0,
        smashes: 0,
        serves: 0
      }
    };

    // Estimate shots based on ball movement patterns
    ballTracks.forEach(track => {
      const timestampedObjects = track.timestampedObjects || [];
      let shotCount = 0;
      
      for (let i = 1; i < timestampedObjects.length; i++) {
        const prev = timestampedObjects[i - 1];
        const curr = timestampedObjects[i];
        
        // Detect rapid direction changes as potential shots
        if (prev.normalizedBoundingBox && curr.normalizedBoundingBox) {
          const movement = this.calculateMovementVector(prev.normalizedBoundingBox, curr.normalizedBoundingBox);
          if (this.isSignificantMovementChange(movement)) {
            shotCount++;
          }
        }
      }
      
      shots.total += shotCount;
    });

    // Estimate shot types and success rates based on movement patterns
    shots.successful = Math.round(shots.total * 0.7); // Assume 70% success rate
    shots.errors = shots.total - shots.successful;
    shots.winners = Math.round(shots.successful * 0.15); // 15% winners

    // Distribute shot types
    shots.breakdown.forehands = Math.round(shots.total * 0.4);
    shots.breakdown.backhands = Math.round(shots.total * 0.35);
    shots.breakdown.volleys = Math.round(shots.total * 0.15);
    shots.breakdown.smashes = Math.round(shots.total * 0.05);
    shots.breakdown.serves = Math.round(shots.total * 0.05);

    return shots;
  }

  /**
   * Generate AI insights based on analysis data
   */
  generateInsights(labelAnnotations) {
    const insights = {
      strengths: [],
      weaknesses: [],
      recommendations: [],
      drillSuggestions: [],
      technicalAdvice: []
    };

    // Extract relevant labels
    const relevantLabels = labelAnnotations.filter(label => 
      label.entity?.description && this.isPadelRelevant(label.entity.description)
    );

    // Generate insights based on detected activities
    relevantLabels.forEach(label => {
      const confidence = label.segments?.[0]?.confidence || 0;
      const description = label.entity.description.toLowerCase();

      if (confidence > 0.7) {
        if (description.includes('running') || description.includes('moving')) {
          insights.strengths.push('Good court movement and positioning');
        }
        if (description.includes('hitting') || description.includes('striking')) {
          insights.strengths.push('Active shot-making during rallies');
        }
      }
    });

    // Default recommendations
    insights.recommendations = [
      'Focus on consistent ball placement',
      'Work on court positioning during rallies',
      'Practice volley technique at the net',
      'Improve movement between shots'
    ];

    insights.drillSuggestions = [
      'Wall practice for consistency',
      'Cross-court rally drills',
      'Net approach exercises',
      'Serve and volley practice'
    ];

    insights.technicalAdvice = [
      'Keep your eye on the ball throughout the shot',
      'Maintain balanced stance during rallies',
      'Use continental grip for volleys',
      'Follow through on groundstrokes'
    ];

    return insights;
  }

  /**
   * Calculate performance metrics
   */
  calculatePerformanceMetrics(analysis) {
    const { shots, rallies, movement } = analysis;
    
    const accuracy = shots.total > 0 ? Math.round((shots.successful / shots.total) * 100) : 0;
    const consistency = rallies.averageLength > 3 ? Math.min(rallies.averageLength * 10, 100) : 50;
    const aggressiveness = shots.winners > 0 ? Math.min((shots.winners / shots.total) * 100, 10) : 5;
    const defensivePlay = shots.total > 0 ? Math.max(100 - aggressiveness * 10, 20) : 70;
    const netPlay = shots.breakdown?.volleys > 0 ? (shots.breakdown.volleys / shots.total) * 100 : 10;
    
    const overallRating = Math.round((accuracy * 0.3) + (consistency * 0.3) + (aggressiveness * 2) + (movement.averageSpeed * 0.5));

    return {
      accuracy,
      consistency,
      aggressiveness: Math.round(aggressiveness),
      defensivePlay: Math.round(defensivePlay),
      netPlay: Math.round(netPlay),
      overallRating: Math.min(overallRating, 100)
    };
  }

  /**
   * Generate timeline of events
   */
  generateTimeline(results) {
    const timeline = [];
    
    if (results.shotAnnotations) {
      results.shotAnnotations.forEach((shot, index) => {
        timeline.push({
          timestamp: this.timeToSeconds(shot.startTimeOffset),
          event: { type: 'rally_start' },
          details: { rallyNumber: index + 1 }
        });
        
        timeline.push({
          timestamp: this.timeToSeconds(shot.endTimeOffset),
          event: { type: 'rally_end' },
          details: { rallyNumber: index + 1 }
        });
      });
    }

    return timeline.sort((a, b) => a.timestamp - b.timestamp);
  }

  // Helper methods
  timeToSeconds(timeOffset) {
    if (!timeOffset) return 0;
    return (timeOffset.seconds || 0) + ((timeOffset.nanos || 0) / 1e9);
  }

  calculateDistance(box1, box2) {
    const dx = (box1.left + box1.width / 2) - (box2.left + box2.width / 2);
    const dy = (box1.top + box1.height / 2) - (box2.top + box2.height / 2);
    return Math.sqrt(dx * dx + dy * dy);
  }

  calculateMovementVector(box1, box2) {
    return {
      dx: (box2.left + box2.width / 2) - (box1.left + box1.width / 2),
      dy: (box2.top + box2.height / 2) - (box1.top + box1.height / 2)
    };
  }

  isSignificantMovementChange(movement) {
    return Math.abs(movement.dx) > 0.1 || Math.abs(movement.dy) > 0.1;
  }

  isPadelRelevant(description) {
    const keywords = ['sport', 'tennis', 'ball', 'racket', 'court', 'player', 'running', 'hitting', 'serving'];
    return keywords.some(keyword => description.toLowerCase().includes(keyword));
  }

  calculateCourtZones(personTracks) {
    // Simplified court zone calculation
    return {
      forehand: 30,
      backhand: 35,
      net: 20,
      back: 15
    };
  }

  generateMovementPath(personTracks) {
    const path = [];
    personTracks.forEach(track => {
      (track.timestampedObjects || []).forEach(obj => {
        if (obj.normalizedBoundingBox) {
          path.push({
            x: obj.normalizedBoundingBox.left + obj.normalizedBoundingBox.width / 2,
            y: obj.normalizedBoundingBox.top + obj.normalizedBoundingBox.height / 2,
            timestamp: this.timeToSeconds(obj.timeOffset)
          });
        }
      });
    });
    return path;
  }

  generateShotHeatMap(ballTracks) {
    const positions = [];
    ballTracks.forEach(track => {
      (track.timestampedObjects || []).forEach(obj => {
        if (obj.normalizedBoundingBox) {
          positions.push({
            x: obj.normalizedBoundingBox.left + obj.normalizedBoundingBox.width / 2,
            y: obj.normalizedBoundingBox.top + obj.normalizedBoundingBox.height / 2,
            frequency: 1
          });
        }
      });
    });
    return positions;
  }

  /**
   * Delete video from storage
   */
  async deleteVideo(filePath) {
    try {
      await this.bucket.file(filePath).delete();
      console.log(`🗑️  Deleted video: ${filePath}`);
    } catch (error) {
      console.error(`❌ Failed to delete video: ${error.message}`);
      throw error;
    }
  }

  /**
   * Generate signed URL for video access
   */
  async getSignedUrl(filePath, expirationMinutes = 60) {
    try {
      const [url] = await this.bucket.file(filePath).getSignedUrl({
        action: 'read',
        expires: Date.now() + expirationMinutes * 60 * 1000,
      });
      return url;
    } catch (error) {
      throw new Error(`Failed to generate signed URL: ${error.message}`);
    }
  }
}

module.exports = new GoogleCloudService();