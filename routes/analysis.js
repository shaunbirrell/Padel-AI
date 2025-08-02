const express = require('express');
const Video = require('../models/Video');
const { protect } = require('../middleware/auth');

const router = express.Router();

// @desc    Get detailed analysis for a video
// @route   GET /api/analysis/:videoId
// @access  Private
router.get('/:videoId', protect, async (req, res) => {
  try {
    const video = await Video.findOne({
      _id: req.params.videoId,
      user: req.user._id
    });

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    if (video.analysis.status !== 'completed') {
      return res.status(400).json({ 
        error: 'Analysis not completed',
        status: video.analysis.status 
      });
    }

    res.json({
      videoId: video._id,
      analysis: video.analysis,
      matchDetails: video.matchDetails,
      duration: video.duration,
      analysisSummary: video.getAnalysisSummary(),
      analysisScore: video.calculateAnalysisScore()
    });

  } catch (error) {
    console.error('Get analysis error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve analysis',
      message: error.message 
    });
  }
});

// @desc    Get shot analysis breakdown
// @route   GET /api/analysis/:videoId/shots
// @access  Private
router.get('/:videoId/shots', protect, async (req, res) => {
  try {
    const video = await Video.findOne({
      _id: req.params.videoId,
      user: req.user._id
    }).select('analysis.shots analysis.errors analysis.timeline');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Filter timeline for shot events
    const shotEvents = video.analysis.timeline.filter(event => 
      event.event.type === 'shot'
    );

    res.json({
      shots: video.analysis.shots,
      errors: video.analysis.errors,
      shotEvents,
      insights: {
        mostCommonShot: getMostCommonShot(video.analysis.shots.breakdown),
        successRate: video.analysis.shots.total > 0 ? 
          Math.round((video.analysis.shots.successful / video.analysis.shots.total) * 100) : 0,
        winnerRate: video.analysis.shots.successful > 0 ?
          Math.round((video.analysis.shots.winners / video.analysis.shots.successful) * 100) : 0
      }
    });

  } catch (error) {
    console.error('Get shot analysis error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve shot analysis',
      message: error.message 
    });
  }
});

// @desc    Get rally analysis
// @route   GET /api/analysis/:videoId/rallies
// @access  Private
router.get('/:videoId/rallies', protect, async (req, res) => {
  try {
    const video = await Video.findOne({
      _id: req.params.videoId,
      user: req.user._id
    }).select('analysis.rallies analysis.timeline');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Filter timeline for rally events
    const rallyEvents = video.analysis.timeline.filter(event => 
      event.event.type === 'rally_start' || event.event.type === 'rally_end'
    );

    // Calculate rally statistics
    const rallyLengths = [];
    for (let i = 0; i < rallyEvents.length - 1; i += 2) {
      if (rallyEvents[i].event.type === 'rally_start' && rallyEvents[i + 1]?.event.type === 'rally_end') {
        rallyLengths.push(rallyEvents[i + 1].timestamp - rallyEvents[i].timestamp);
      }
    }

    res.json({
      rallies: video.analysis.rallies,
      rallyEvents,
      insights: {
        averageRallyDuration: rallyLengths.length > 0 ? 
          (rallyLengths.reduce((a, b) => a + b, 0) / rallyLengths.length).toFixed(1) : 0,
        longestRallyDuration: rallyLengths.length > 0 ? Math.max(...rallyLengths).toFixed(1) : 0,
        shortRallyPercentage: video.analysis.rallies.total > 0 ?
          Math.round((video.analysis.rallies.shortRallies / video.analysis.rallies.total) * 100) : 0
      }
    });

  } catch (error) {
    console.error('Get rally analysis error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve rally analysis',
      message: error.message 
    });
  }
});

// @desc    Get movement analysis
// @route   GET /api/analysis/:videoId/movement
// @access  Private
router.get('/:videoId/movement', protect, async (req, res) => {
  try {
    const video = await Video.findOne({
      _id: req.params.videoId,
      user: req.user._id
    }).select('analysis.movement analysis.heatMap');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    res.json({
      movement: video.analysis.movement,
      heatMap: video.analysis.heatMap,
      insights: {
        mobility: calculateMobilityScore(video.analysis.movement),
        courtCoverage: calculateCourtCoverage(video.analysis.movement.timeInEachZone),
        efficiency: calculateMovementEfficiency(video.analysis.movement)
      }
    });

  } catch (error) {
    console.error('Get movement analysis error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve movement analysis',
      message: error.message 
    });
  }
});

// @desc    Get performance metrics
// @route   GET /api/analysis/:videoId/performance
// @access  Private
router.get('/:videoId/performance', protect, async (req, res) => {
  try {
    const video = await Video.findOne({
      _id: req.params.videoId,
      user: req.user._id
    }).select('analysis.performance analysis.insights');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    res.json({
      performance: video.analysis.performance,
      insights: video.analysis.insights,
      recommendations: generatePerformanceRecommendations(video.analysis.performance),
      strengths: video.analysis.insights.strengths,
      weaknesses: video.analysis.insights.weaknesses
    });

  } catch (error) {
    console.error('Get performance analysis error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve performance analysis',
      message: error.message 
    });
  }
});

// @desc    Compare multiple videos
// @route   POST /api/analysis/compare
// @access  Private
router.post('/compare', protect, async (req, res) => {
  try {
    const { videoIds } = req.body;

    if (!videoIds || videoIds.length < 2) {
      return res.status(400).json({ error: 'At least 2 video IDs required for comparison' });
    }

    const videos = await Video.find({
      _id: { $in: videoIds },
      user: req.user._id,
      'analysis.status': 'completed'
    }).select('originalName analysis.shots analysis.rallies analysis.performance analysis.movement createdAt');

    if (videos.length < 2) {
      return res.status(400).json({ error: 'Not enough completed analyses found' });
    }

    const comparison = {
      videos: videos.map(video => ({
        id: video._id,
        name: video.originalName,
        date: video.createdAt,
        metrics: {
          overallRating: video.analysis.performance.overallRating,
          accuracy: video.analysis.performance.accuracy,
          totalShots: video.analysis.shots.total,
          averageRallyLength: video.analysis.rallies.averageLength,
          distanceCovered: video.analysis.movement.distanceCovered
        }
      })),
      trends: calculateTrends(videos),
      improvement: calculateImprovement(videos)
    };

    res.json(comparison);

  } catch (error) {
    console.error('Video comparison error:', error);
    res.status(500).json({ 
      error: 'Failed to compare videos',
      message: error.message 
    });
  }
});

// @desc    Get AI coaching insights
// @route   GET /api/analysis/:videoId/coaching
// @access  Private
router.get('/:videoId/coaching', protect, async (req, res) => {
  try {
    const video = await Video.findOne({
      _id: req.params.videoId,
      user: req.user._id
    }).select('analysis.insights analysis.performance analysis.shots analysis.movement');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    const coaching = {
      personalizedTips: generatePersonalizedTips(video.analysis, req.user.profile),
      drillRecommendations: video.analysis.insights.drillSuggestions,
      technicalAdvice: video.analysis.insights.technicalAdvice,
      nextSteps: generateNextSteps(video.analysis.performance),
      focusAreas: identifyFocusAreas(video.analysis)
    };

    res.json(coaching);

  } catch (error) {
    console.error('Get coaching insights error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve coaching insights',
      message: error.message 
    });
  }
});

// Helper functions
function getMostCommonShot(breakdown) {
  const shots = Object.entries(breakdown);
  return shots.reduce((a, b) => a[1] > b[1] ? a : b)[0];
}

function calculateMobilityScore(movement) {
  const { averageSpeed, maxSpeed, distanceCovered } = movement;
  return Math.min(100, Math.round((averageSpeed * 2) + (maxSpeed * 0.5) + (distanceCovered * 0.1)));
}

function calculateCourtCoverage(timeInEachZone) {
  const total = Object.values(timeInEachZone).reduce((a, b) => a + b, 0);
  const balance = 100 - Math.abs(25 - (timeInEachZone.forehand + timeInEachZone.backhand) / 2);
  return Math.round(balance);
}

function calculateMovementEfficiency(movement) {
  if (movement.distanceCovered === 0) return 0;
  return Math.min(100, Math.round((movement.averageSpeed / movement.distanceCovered) * 1000));
}

function generatePerformanceRecommendations(performance) {
  const recommendations = [];
  
  if (performance.accuracy < 70) {
    recommendations.push('Focus on shot placement accuracy through target practice');
  }
  if (performance.consistency < 60) {
    recommendations.push('Work on consistency with repetitive rally drills');
  }
  if (performance.netPlay < 30) {
    recommendations.push('Improve net play with volley practice sessions');
  }
  if (performance.aggressiveness < 3) {
    recommendations.push('Consider being more aggressive in favorable positions');
  }
  
  return recommendations;
}

function calculateTrends(videos) {
  const sortedVideos = videos.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
  
  if (sortedVideos.length < 2) return {};
  
  const first = sortedVideos[0].analysis.performance;
  const last = sortedVideos[sortedVideos.length - 1].analysis.performance;
  
  return {
    accuracy: last.accuracy - first.accuracy,
    overallRating: last.overallRating - first.overallRating,
    consistency: last.consistency - first.consistency
  };
}

function calculateImprovement(videos) {
  if (videos.length < 2) return 0;
  
  const ratings = videos
    .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt))
    .map(v => v.analysis.performance.overallRating);
  
  const improvement = ratings[ratings.length - 1] - ratings[0];
  return Math.round(improvement);
}

function generatePersonalizedTips(analysis, userProfile) {
  const tips = [];
  
  if (userProfile.playingLevel === 'beginner') {
    tips.push('Focus on getting the ball over the net consistently');
    tips.push('Work on basic positioning and court awareness');
  } else if (userProfile.playingLevel === 'intermediate') {
    tips.push('Develop shot variety and tactical awareness');
    tips.push('Improve movement patterns and court coverage');
  } else {
    tips.push('Refine advanced techniques and strategic play');
    tips.push('Focus on mental toughness and match situations');
  }
  
  if (analysis.performance.netPlay < 20) {
    tips.push('Spend more time practicing volleys and net approaches');
  }
  
  return tips;
}

function generateNextSteps(performance) {
  const steps = [];
  
  if (performance.overallRating < 50) {
    steps.push('Book lessons with a qualified Padel coach');
    steps.push('Practice basic strokes daily for 30 minutes');
  } else if (performance.overallRating < 75) {
    steps.push('Focus on tactical awareness and positioning');
    steps.push('Play practice matches to apply learned skills');
  } else {
    steps.push('Compete in tournaments to test skills');
    steps.push('Analyze opponent weaknesses and adapt strategy');
  }
  
  return steps;
}

function identifyFocusAreas(analysis) {
  const areas = [];
  
  if (analysis.performance.accuracy < 60) areas.push('Shot Accuracy');
  if (analysis.performance.consistency < 50) areas.push('Consistency');
  if (analysis.performance.netPlay < 25) areas.push('Net Play');
  if (analysis.movement.averageSpeed < 3) areas.push('Court Movement');
  if (analysis.shots.breakdown.volleys < analysis.shots.total * 0.1) areas.push('Volley Technique');
  
  return areas.length > 0 ? areas : ['Overall Game Development'];
}

module.exports = router;