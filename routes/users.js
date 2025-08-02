const express = require('express');
const User = require('../models/User');
const Video = require('../models/Video');
const { protect, authorize } = require('../middleware/auth');

const router = express.Router();

// @desc    Get user dashboard stats
// @route   GET /api/users/dashboard
// @access  Private
router.get('/dashboard', protect, async (req, res) => {
  try {
    const userId = req.user._id;
    
    // Get user stats
    const user = await User.findById(userId).select('stats subscription profile');
    
    // Get video analytics
    const videoStats = await Video.aggregate([
      { $match: { user: userId } },
      {
        $group: {
          _id: null,
          totalVideos: { $sum: 1 },
          completedAnalyses: { 
            $sum: { $cond: [{ $eq: ['$analysis.status', 'completed'] }, 1, 0] } 
          },
          averageRating: { $avg: '$analysis.performance.overallRating' },
          totalShots: { $sum: '$analysis.shots.total' },
          averageAccuracy: { $avg: '$analysis.performance.accuracy' },
          averageRallyLength: { $avg: '$analysis.rallies.averageLength' }
        }
      }
    ]);

    // Get recent activity
    const recentVideos = await Video.find({ user: userId })
      .sort({ createdAt: -1 })
      .limit(5)
      .select('originalName analysis.status analysis.performance.overallRating createdAt');

    // Calculate improvement trend
    const improvementData = await Video.find({ 
      user: userId, 
      'analysis.status': 'completed' 
    })
      .sort({ createdAt: 1 })
      .limit(10)
      .select('analysis.performance.overallRating createdAt');

    const improvement = calculateImprovementTrend(improvementData);

    res.json({
      user: {
        stats: user.stats,
        subscription: user.subscription,
        profile: user.profile
      },
      analytics: videoStats[0] || {
        totalVideos: 0,
        completedAnalyses: 0,
        averageRating: 0,
        totalShots: 0,
        averageAccuracy: 0,
        averageRallyLength: 0
      },
      recentActivity: recentVideos,
      improvement
    });

  } catch (error) {
    console.error('Dashboard error:', error);
    res.status(500).json({ 
      error: 'Failed to load dashboard',
      message: error.message 
    });
  }
});

// @desc    Update subscription plan
// @route   PUT /api/users/subscription
// @access  Private
router.put('/subscription', protect, async (req, res) => {
  try {
    const { plan } = req.body;
    
    if (!['free', 'pro', 'premium'].includes(plan)) {
      return res.status(400).json({ error: 'Invalid subscription plan' });
    }

    const user = await User.findById(req.user._id);
    
    // Update subscription
    user.subscription.plan = plan;
    
    // Reset videos based on new plan
    const videosPerMonth = {
      free: 3,
      pro: 20,
      premium: 100
    };
    
    user.subscription.videosRemaining = videosPerMonth[plan];
    user.subscription.resetDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days
    
    await user.save();

    res.json({
      message: `Subscription updated to ${plan}`,
      subscription: user.subscription
    });

  } catch (error) {
    console.error('Subscription update error:', error);
    res.status(500).json({ 
      error: 'Failed to update subscription',
      message: error.message 
    });
  }
});

// @desc    Get user progress analytics
// @route   GET /api/users/progress
// @access  Private
router.get('/progress', protect, async (req, res) => {
  try {
    const userId = req.user._id;
    const timeframe = req.query.timeframe || '30'; // days
    
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - parseInt(timeframe));
    
    // Get videos from timeframe
    const videos = await Video.find({
      user: userId,
      'analysis.status': 'completed',
      createdAt: { $gte: startDate }
    }).sort({ createdAt: 1 })
      .select('analysis.performance analysis.shots analysis.rallies createdAt originalName');

    if (videos.length === 0) {
      return res.json({
        message: 'No completed analyses in the selected timeframe',
        progress: null
      });
    }

    // Calculate progress metrics
    const progressData = videos.map((video, index) => ({
      date: video.createdAt,
      videoName: video.originalName,
      overallRating: video.analysis.performance.overallRating,
      accuracy: video.analysis.performance.accuracy,
      consistency: video.analysis.performance.consistency,
      totalShots: video.analysis.shots.total,
      averageRallyLength: video.analysis.rallies.averageLength
    }));

    // Calculate trends
    const trends = calculateProgressTrends(progressData);
    
    // Identify areas of improvement and decline
    const insights = generateProgressInsights(progressData);

    res.json({
      timeframe: parseInt(timeframe),
      totalAnalyses: videos.length,
      progress: progressData,
      trends,
      insights
    });

  } catch (error) {
    console.error('Progress analytics error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve progress analytics',
      message: error.message 
    });
  }
});

// @desc    Get user achievements
// @route   GET /api/users/achievements
// @access  Private
router.get('/achievements', protect, async (req, res) => {
  try {
    const userId = req.user._id;
    
    const user = await User.findById(userId);
    const videos = await Video.find({ 
      user: userId, 
      'analysis.status': 'completed' 
    });

    const achievements = calculateAchievements(user, videos);

    res.json({
      achievements,
      totalUnlocked: achievements.filter(a => a.unlocked).length,
      totalAvailable: achievements.length
    });

  } catch (error) {
    console.error('Achievements error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve achievements',
      message: error.message 
    });
  }
});

// @desc    Update user goals
// @route   PUT /api/users/goals
// @access  Private
router.put('/goals', protect, async (req, res) => {
  try {
    const { goals } = req.body;
    
    if (!Array.isArray(goals)) {
      return res.status(400).json({ error: 'Goals must be an array' });
    }

    const user = await User.findById(req.user._id);
    user.profile.goals = goals.slice(0, 5); // Limit to 5 goals
    
    await user.save();

    res.json({
      message: 'Goals updated successfully',
      goals: user.profile.goals
    });

  } catch (error) {
    console.error('Goals update error:', error);
    res.status(500).json({ 
      error: 'Failed to update goals',
      message: error.message 
    });
  }
});

// @desc    Get all users (Admin only)
// @route   GET /api/users
// @access  Private/Admin
router.get('/', protect, authorize('admin'), async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const skip = (page - 1) * limit;

    const users = await User.find({})
      .select('-password')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit);

    const total = await User.countDocuments({});

    res.json({
      users,
      pagination: {
        current: page,
        pages: Math.ceil(total / limit),
        total
      }
    });

  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve users',
      message: error.message 
    });
  }
});

// @desc    Delete user account
// @route   DELETE /api/users/account
// @access  Private
router.delete('/account', protect, async (req, res) => {
  try {
    const userId = req.user._id;
    
    // Delete all user's videos from database
    await Video.deleteMany({ user: userId });
    
    // Delete user account
    await User.findByIdAndDelete(userId);

    res.json({ message: 'Account deleted successfully' });

  } catch (error) {
    console.error('Account deletion error:', error);
    res.status(500).json({ 
      error: 'Failed to delete account',
      message: error.message 
    });
  }
});

// Helper functions
function calculateImprovementTrend(videos) {
  if (videos.length < 2) return { trend: 'insufficient_data', change: 0 };

  const ratings = videos.map(v => v.analysis.performance.overallRating);
  const firstHalf = ratings.slice(0, Math.ceil(ratings.length / 2));
  const secondHalf = ratings.slice(Math.floor(ratings.length / 2));

  const firstAvg = firstHalf.reduce((a, b) => a + b, 0) / firstHalf.length;
  const secondAvg = secondHalf.reduce((a, b) => a + b, 0) / secondHalf.length;

  const change = secondAvg - firstAvg;
  
  return {
    trend: change > 5 ? 'improving' : change < -5 ? 'declining' : 'stable',
    change: Math.round(change),
    firstPeriodAvg: Math.round(firstAvg),
    secondPeriodAvg: Math.round(secondAvg)
  };
}

function calculateProgressTrends(data) {
  if (data.length < 2) return {};

  const first = data[0];
  const last = data[data.length - 1];

  return {
    overallRating: last.overallRating - first.overallRating,
    accuracy: last.accuracy - first.accuracy,
    consistency: last.consistency - first.consistency,
    totalShots: last.totalShots - first.totalShots,
    averageRallyLength: last.averageRallyLength - first.averageRallyLength
  };
}

function generateProgressInsights(data) {
  if (data.length < 3) return [];

  const insights = [];
  const recent = data.slice(-3); // Last 3 videos
  const earlier = data.slice(0, -3); // Earlier videos

  if (earlier.length === 0) return [];

  const recentAvg = {
    overallRating: recent.reduce((sum, v) => sum + v.overallRating, 0) / recent.length,
    accuracy: recent.reduce((sum, v) => sum + v.accuracy, 0) / recent.length
  };

  const earlierAvg = {
    overallRating: earlier.reduce((sum, v) => sum + v.overallRating, 0) / earlier.length,
    accuracy: earlier.reduce((sum, v) => sum + v.accuracy, 0) / earlier.length
  };

  if (recentAvg.overallRating > earlierAvg.overallRating + 5) {
    insights.push('Your overall performance has improved significantly in recent matches');
  }

  if (recentAvg.accuracy > earlierAvg.accuracy + 10) {
    insights.push('Your shot accuracy has shown marked improvement');
  }

  if (recentAvg.overallRating < earlierAvg.overallRating - 5) {
    insights.push('Consider reviewing recent matches to identify areas for improvement');
  }

  return insights;
}

function calculateAchievements(user, videos) {
  const achievements = [
    {
      id: 'first_upload',
      name: 'First Steps',
      description: 'Upload your first video',
      unlocked: videos.length > 0,
      icon: '🎥'
    },
    {
      id: 'five_uploads',
      name: 'Getting Started',
      description: 'Upload 5 videos',
      unlocked: videos.length >= 5,
      icon: '📹'
    },
    {
      id: 'ten_uploads',
      name: 'Dedicated Player',
      description: 'Upload 10 videos',
      unlocked: videos.length >= 10,
      icon: '🏆'
    },
    {
      id: 'accuracy_master',
      name: 'Accuracy Master',
      description: 'Achieve 85% accuracy in a match',
      unlocked: videos.some(v => v.analysis.performance.accuracy >= 85),
      icon: '🎯'
    },
    {
      id: 'consistency_king',
      name: 'Consistency King',
      description: 'Achieve 80% consistency in a match',
      unlocked: videos.some(v => v.analysis.performance.consistency >= 80),
      icon: '👑'
    },
    {
      id: 'rally_master',
      name: 'Rally Master',
      description: 'Maintain average rally length of 10+ shots',
      unlocked: videos.some(v => v.analysis.rallies.averageLength >= 10),
      icon: '🔄'
    },
    {
      id: 'improvement_streak',
      name: 'Improvement Streak',
      description: 'Show improvement across 3 consecutive matches',
      unlocked: checkImprovementStreak(videos),
      icon: '📈'
    },
    {
      id: 'net_player',
      name: 'Net Player',
      description: 'Achieve 40%+ net play in a match',
      unlocked: videos.some(v => v.analysis.performance.netPlay >= 40),
      icon: '🏐'
    }
  ];

  return achievements;
}

function checkImprovementStreak(videos) {
  if (videos.length < 3) return false;

  const sorted = videos
    .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt))
    .slice(-3);

  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].analysis.performance.overallRating <= sorted[i-1].analysis.performance.overallRating) {
      return false;
    }
  }

  return true;
}

module.exports = router;