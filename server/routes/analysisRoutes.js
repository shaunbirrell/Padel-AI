const express = require('express');
const router = express.Router();
const videoIntelligence = require('@google-cloud/video-intelligence');
const fs = require('fs').promises;
const path = require('path');

// Initialize Google Cloud Video Intelligence client
const client = new videoIntelligence.VideoIntelligenceServiceClient();

// Analyze video for padel-specific features
router.post('/analyze/:videoId', async (req, res) => {
  try {
    if (!global.videos) global.videos = new Map();
    
    const video = global.videos.get(req.params.videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Update video status
    video.analysisStatus = 'processing';
    global.videos.set(video.id, video);

    // Read video file
    const videoBytes = await fs.readFile(video.path);

    // Configure the request for multiple analysis features
    const request = {
      inputContent: videoBytes.toString('base64'),
      features: [
        'LABEL_DETECTION',
        'SHOT_CHANGE_DETECTION',
        'OBJECT_TRACKING',
        'EXPLICIT_CONTENT_DETECTION',
        'TEXT_DETECTION'
      ],
      videoContext: {
        segments: [{
          startTimeOffset: {
            seconds: '0',
            nanos: 0
          },
          endTimeOffset: {
            seconds: '0',
            nanos: 0
          }
        }]
      }
    };

    // Perform video analysis
    const [operation] = await client.annotateVideo(request);
    
    // Wait for operation to complete
    const [operationResult] = await operation.promise();

    // Process results for padel-specific analysis
    const analysis = processPadelAnalysis(operationResult, video);

    // Update video with analysis results
    video.analysis = analysis;
    video.analysisStatus = 'completed';
    video.analysisDate = new Date();
    global.videos.set(video.id, video);

    res.json({
      message: 'Analysis completed successfully',
      analysis: analysis
    });

  } catch (error) {
    console.error('Analysis error:', error);
    
    // Update video status on error
    if (global.videos && global.videos.has(req.params.videoId)) {
      const video = global.videos.get(req.params.videoId);
      video.analysisStatus = 'failed';
      global.videos.set(video.id, video);
    }

    res.status(500).json({ 
      error: 'Failed to analyze video',
      details: process.env.NODE_ENV === 'development' ? error.message : 'Analysis failed'
    });
  }
});

// Get analysis results for a video
router.get('/:videoId', async (req, res) => {
  try {
    if (!global.videos) global.videos = new Map();
    
    const video = global.videos.get(req.params.videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    if (!video.analysis) {
      return res.status(404).json({ error: 'Analysis not found for this video' });
    }

    res.json({
      videoId: video.id,
      analysis: video.analysis,
      analysisDate: video.analysisDate,
      analysisStatus: video.analysisStatus
    });

  } catch (error) {
    console.error('Error fetching analysis:', error);
    res.status(500).json({ error: 'Failed to fetch analysis' });
  }
});

// Process Google Cloud Video Intelligence results for padel analysis
function processPadelAnalysis(operationResult, video) {
  const analysis = {
    summary: {
      totalDuration: 0,
      shotCount: 0,
      rallyCount: 0,
      volleyCount: 0,
      serveCount: 0
    },
    shots: [],
    rallies: [],
    volleys: [],
    serves: [],
    objects: [],
    labels: [],
    textDetected: [],
    explicitContent: null
  };

  // Process shot changes
  if (operationResult.annotationResults[0].shotAnnotations) {
    analysis.summary.shotCount = operationResult.annotationResults[0].shotAnnotations.length;
    analysis.shots = operationResult.annotationResults[0].shotAnnotations.map((shot, index) => ({
      id: index + 1,
      startTime: shot.startTimeOffset.seconds,
      endTime: shot.endTimeOffset.seconds,
      duration: shot.endTimeOffset.seconds - shot.startTimeOffset.seconds
    }));
  }

  // Process labels (detect padel-related objects and actions)
  if (operationResult.annotationResults[0].shotLabelAnnotations) {
    operationResult.annotationResults[0].shotLabelAnnotations.forEach(shotLabel => {
      shotLabel.entries.forEach(entry => {
        const label = {
          description: entry.segmentLabelAnnotations[0].entity.description,
          confidence: entry.segmentLabelAnnotations[0].segments[0].confidence,
          startTime: entry.segmentLabelAnnotations[0].segments[0].segment.startTimeOffset.seconds,
          endTime: entry.segmentLabelAnnotations[0].segments[0].segment.endTimeOffset.seconds
        };

        // Categorize based on padel-specific labels
        if (isPadelRelated(label.description)) {
          analysis.labels.push(label);
          
          // Categorize specific shot types
          if (isVolley(label.description)) {
            analysis.volleys.push(label);
            analysis.summary.volleyCount++;
          } else if (isServe(label.description)) {
            analysis.serves.push(label);
            analysis.summary.serveCount++;
          } else if (isRally(label.description)) {
            analysis.rallies.push(label);
            analysis.summary.rallyCount++;
          }
        }
      });
    });
  }

  // Process object tracking (rackets, balls, players)
  if (operationResult.annotationResults[0].objectAnnotations) {
    analysis.objects = operationResult.annotationResults[0].objectAnnotations.map(obj => ({
      description: obj.entity.description,
      confidence: obj.frames[0]?.confidence || 0,
      boundingBox: obj.frames[0]?.normalizedBoundingBox || null
    }));
  }

  // Process text detection (score, player names, etc.)
  if (operationResult.annotationResults[0].textAnnotations) {
    analysis.textDetected = operationResult.annotationResults[0].textAnnotations.map(text => ({
      text: text.text,
      confidence: text.segments[0]?.confidence || 0
    }));
  }

  // Process explicit content detection
  if (operationResult.annotationResults[0].explicitAnnotation) {
    analysis.explicitContent = {
      pornography: operationResult.annotationResults[0].explicitAnnotation.pornographyLikelihood,
      violence: operationResult.annotationResults[0].explicitAnnotation.violenceLikelihood
    };
  }

  // Calculate total duration
  if (analysis.shots.length > 0) {
    const lastShot = analysis.shots[analysis.shots.length - 1];
    analysis.summary.totalDuration = parseFloat(lastShot.endTime);
  }

  return analysis;
}

// Helper functions to categorize padel-specific actions
function isPadelRelated(description) {
  const padelKeywords = [
    'racket', 'paddle', 'ball', 'tennis', 'padel', 'sport', 'game', 'player',
    'serve', 'volley', 'rally', 'shot', 'hit', 'swing', 'court', 'net'
  ];
  
  return padelKeywords.some(keyword => 
    description.toLowerCase().includes(keyword.toLowerCase())
  );
}

function isVolley(description) {
  const volleyKeywords = ['volley', 'net', 'close', 'quick'];
  return volleyKeywords.some(keyword => 
    description.toLowerCase().includes(keyword.toLowerCase())
  );
}

function isServe(description) {
  const serveKeywords = ['serve', 'service', 'start', 'beginning'];
  return serveKeywords.some(keyword => 
    description.toLowerCase().includes(keyword.toLowerCase())
  );
}

function isRally(description) {
  const rallyKeywords = ['rally', 'exchange', 'back', 'forth', 'continuous'];
  return rallyKeywords.some(keyword => 
    description.toLowerCase().includes(keyword.toLowerCase())
  );
}

module.exports = router;