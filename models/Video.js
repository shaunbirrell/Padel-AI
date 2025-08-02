const mongoose = require('mongoose');

const videoSchema = new mongoose.Schema({
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  filename: {
    type: String,
    required: true
  },
  originalName: {
    type: String,
    required: true
  },
  cloudStorageUrl: {
    type: String,
    required: true
  },
  cloudStoragePath: {
    type: String,
    required: true
  },
  size: {
    type: Number,
    required: true
  },
  duration: {
    type: Number, // in seconds
    default: 0
  },
  format: {
    type: String,
    required: true
  },
  resolution: {
    width: Number,
    height: Number
  },
  thumbnailUrl: {
    type: String
  },
  matchDetails: {
    date: {
      type: Date,
      default: Date.now
    },
    opponents: [{
      name: String,
      level: String
    }],
    score: {
      sets: [{
        player: Number,
        opponent: Number
      }]
    },
    court: {
      type: String,
      enum: ['indoor', 'outdoor'],
      default: 'outdoor'
    },
    surface: {
      type: String,
      enum: ['glass', 'concrete', 'artificial_grass'],
      default: 'glass'
    },
    weather: {
      type: String,
      enum: ['sunny', 'cloudy', 'windy', 'humid'],
      default: 'sunny'
    }
  },
  analysis: {
    status: {
      type: String,
      enum: ['pending', 'processing', 'completed', 'failed'],
      default: 'pending'
    },
    processedAt: Date,
    videoIntelligenceJobId: String,
    
    // Shot Analysis
    shots: {
      total: { type: Number, default: 0 },
      successful: { type: Number, default: 0 },
      errors: { type: Number, default: 0 },
      winners: { type: Number, default: 0 },
      breakdown: {
        forehands: { type: Number, default: 0 },
        backhands: { type: Number, default: 0 },
        volleys: { type: Number, default: 0 },
        smashes: { type: Number, default: 0 },
        serves: { type: Number, default: 0 }
      }
    },
    
    // Rally Analysis
    rallies: {
      total: { type: Number, default: 0 },
      averageLength: { type: Number, default: 0 },
      longestRally: { type: Number, default: 0 },
      shortRallies: { type: Number, default: 0 }, // < 4 shots
      mediumRallies: { type: Number, default: 0 }, // 4-8 shots
      longRallies: { type: Number, default: 0 } // > 8 shots
    },
    
    // Movement Analysis
    movement: {
      distanceCovered: { type: Number, default: 0 }, // in meters
      averageSpeed: { type: Number, default: 0 }, // km/h
      maxSpeed: { type: Number, default: 0 },
      timeInEachZone: {
        forehand: { type: Number, default: 0 }, // percentage
        backhand: { type: Number, default: 0 },
        net: { type: Number, default: 0 },
        back: { type: Number, default: 0 }
      }
    },
    
    // Performance Metrics
    performance: {
      accuracy: { type: Number, default: 0 }, // percentage
      consistency: { type: Number, default: 0 }, // percentage
      aggressiveness: { type: Number, default: 0 }, // 1-10 scale
      defensivePlay: { type: Number, default: 0 }, // percentage
      netPlay: { type: Number, default: 0 }, // percentage
      overallRating: { type: Number, default: 0 } // 1-100 scale
    },
    
    // Detailed Timeline
    timeline: [{
      timestamp: Number, // seconds from start
      event: {
        type: String,
        enum: ['shot', 'rally_start', 'rally_end', 'point_won', 'point_lost', 'error']
      },
      details: {
        shotType: String,
        location: {
          x: Number, // court coordinates
          y: Number
        },
        speed: Number,
        direction: String,
        success: Boolean
      }
    }],
    
    // AI Insights and Recommendations
    insights: {
      strengths: [String],
      weaknesses: [String],
      recommendations: [String],
      drillSuggestions: [String],
      technicalAdvice: [String]
    },
    
    // Error Analysis
    errors: {
      unforced: { type: Number, default: 0 },
      forced: { type: Number, default: 0 },
      netErrors: { type: Number, default: 0 },
      longErrors: { type: Number, default: 0 },
      wideErrors: { type: Number, default: 0 }
    },
    
    // Heat Map Data
    heatMap: {
      shotPositions: [{
        x: Number,
        y: Number,
        frequency: Number
      }],
      movementPath: [{
        x: Number,
        y: Number,
        timestamp: Number
      }]
    }
  },
  
  tags: [String],
  isPublic: {
    type: Boolean,
    default: false
  },
  processingLogs: [String]
}, {
  timestamps: true
});

// Index for efficient queries
videoSchema.index({ user: 1, createdAt: -1 });
videoSchema.index({ 'analysis.status': 1 });
videoSchema.index({ 'matchDetails.date': -1 });

// Calculate analysis score
videoSchema.methods.calculateAnalysisScore = function() {
  const { shots, rallies, performance } = this.analysis;
  
  if (!shots.total || shots.total === 0) return 0;
  
  const accuracyScore = (shots.successful / shots.total) * 30;
  const consistencyScore = performance.consistency * 0.25;
  const rallyScore = rallies.averageLength > 0 ? Math.min(rallies.averageLength * 2, 20) : 0;
  const performanceScore = performance.overallRating * 0.25;
  
  return Math.round(accuracyScore + consistencyScore + rallyScore + performanceScore);
};

// Get analysis summary
videoSchema.methods.getAnalysisSummary = function() {
  return {
    totalShots: this.analysis.shots.total,
    successRate: this.analysis.shots.total > 0 ? 
      Math.round((this.analysis.shots.successful / this.analysis.shots.total) * 100) : 0,
    averageRallyLength: this.analysis.rallies.averageLength,
    overallRating: this.analysis.performance.overallRating,
    topStrengths: this.analysis.insights.strengths.slice(0, 3),
    topWeaknesses: this.analysis.insights.weaknesses.slice(0, 3)
  };
};

module.exports = mongoose.model('Video', videoSchema);