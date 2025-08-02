const express = require('express');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const Video = require('../models/Video');
const User = require('../models/User');
const { protect, checkSubscription } = require('../middleware/auth');
const googleCloudService = require('../services/googleCloudService');

const router = express.Router();

// Configure multer for video uploads
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: {
    fileSize: (process.env.MAX_VIDEO_SIZE_MB || 500) * 1024 * 1024, // Convert MB to bytes
  },
  fileFilter: (req, file, cb) => {
    const allowedFormats = (process.env.SUPPORTED_FORMATS || 'mp4,avi,mov,mkv').split(',');
    const fileExtension = file.originalname.split('.').pop().toLowerCase();
    
    if (allowedFormats.includes(fileExtension)) {
      cb(null, true);
    } else {
      cb(new Error(`File format .${fileExtension} is not supported. Allowed formats: ${allowedFormats.join(', ')}`), false);
    }
  }
});

// @desc    Upload video for analysis
// @route   POST /api/videos/upload
// @access  Private
router.post('/upload', protect, checkSubscription, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No video file provided' });
    }

    const { matchDetails, tags } = req.body;
    const videoId = uuidv4();
    
    console.log(`📤 Starting upload for user ${req.user._id}, video ${videoId}`);

    // Upload to Google Cloud Storage
    const uploadResult = await googleCloudService.uploadVideo(req.file, req.user._id, videoId);
    
    // Create video record in database
    const video = await Video.create({
      user: req.user._id,
      filename: uploadResult.fileName,
      originalName: req.file.originalname,
      cloudStorageUrl: uploadResult.publicUrl,
      cloudStoragePath: uploadResult.fileName,
      size: req.file.size,
      format: req.file.originalname.split('.').pop().toLowerCase(),
      matchDetails: matchDetails ? JSON.parse(matchDetails) : {},
      tags: tags ? JSON.parse(tags) : [],
      analysis: {
        status: 'pending'
      }
    });

    // Update user stats
    req.user.stats.totalVideosUploaded += 1;
    req.user.subscription.videosRemaining -= 1;
    await req.user.save();

    // Start video analysis asynchronously
    processVideoAnalysis(video._id, uploadResult.publicUrl);

    res.status(201).json({
      message: 'Video uploaded successfully',
      video: {
        _id: video._id,
        originalName: video.originalName,
        size: video.size,
        format: video.format,
        status: video.analysis.status,
        createdAt: video.createdAt
      }
    });

  } catch (error) {
    console.error('Video upload error:', error);
    res.status(500).json({ 
      error: 'Upload failed',
      message: error.message 
    });
  }
});

// Async function to process video analysis
async function processVideoAnalysis(videoId, videoUri) {
  try {
    console.log(`🔄 Starting analysis for video ${videoId}`);
    
    const video = await Video.findById(videoId);
    video.analysis.status = 'processing';
    await video.save();

    // Start Google Cloud Video Intelligence analysis
    const operationName = await googleCloudService.analyzeVideo(videoUri);
    video.analysis.videoIntelligenceJobId = operationName;
    await video.save();

    // Poll for results (in production, you'd use webhooks)
    pollAnalysisResults(videoId, operationName);

  } catch (error) {
    console.error(`❌ Analysis failed for video ${videoId}:`, error);
    await Video.findByIdAndUpdate(videoId, {
      'analysis.status': 'failed',
      $push: { processingLogs: `Analysis failed: ${error.message}` }
    });
  }
}

// Poll for analysis results
async function pollAnalysisResults(videoId, operationName, attempts = 0) {
  const MAX_ATTEMPTS = 60; // 30 minutes max (30 seconds * 60)
  
  try {
    const results = await googleCloudService.getAnalysisResults(operationName);
    
    if (results.status === 'processing') {
      if (attempts < MAX_ATTEMPTS) {
        setTimeout(() => pollAnalysisResults(videoId, operationName, attempts + 1), 30000); // Check every 30 seconds
      } else {
        throw new Error('Analysis timeout after 30 minutes');
      }
      return;
    }

    // Update video with analysis results
    await Video.findByIdAndUpdate(videoId, {
      analysis: results,
      $push: { processingLogs: `Analysis completed successfully` }
    });

    console.log(`✅ Analysis completed for video ${videoId}`);

  } catch (error) {
    console.error(`❌ Analysis polling failed for video ${videoId}:`, error);
    await Video.findByIdAndUpdate(videoId, {
      'analysis.status': 'failed',
      $push: { processingLogs: `Analysis polling failed: ${error.message}` }
    });
  }
}

// @desc    Get user's videos
// @route   GET /api/videos
// @access  Private
router.get('/', protect, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;
    const status = req.query.status;

    let filter = { user: req.user._id };
    if (status) {
      filter['analysis.status'] = status;
    }

    const videos = await Video.find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .select('-analysis.timeline -analysis.heatMap'); // Exclude large data for list view

    const total = await Video.countDocuments(filter);

    res.json({
      videos: videos.map(video => ({
        ...video.toObject(),
        analysisSummary: video.getAnalysisSummary(),
        analysisScore: video.calculateAnalysisScore()
      })),
      pagination: {
        current: page,
        pages: Math.ceil(total / limit),
        total
      }
    });

  } catch (error) {
    console.error('Get videos error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve videos',
      message: error.message 
    });
  }
});

// @desc    Get single video with full analysis
// @route   GET /api/videos/:id
// @access  Private
router.get('/:id', protect, async (req, res) => {
  try {
    const video = await Video.findOne({ 
      _id: req.params.id, 
      user: req.user._id 
    });

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Generate signed URL for video access
    let signedUrl = null;
    try {
      signedUrl = await googleCloudService.getSignedUrl(video.cloudStoragePath);
    } catch (error) {
      console.warn('Failed to generate signed URL:', error.message);
    }

    res.json({
      ...video.toObject(),
      signedUrl,
      analysisSummary: video.getAnalysisSummary(),
      analysisScore: video.calculateAnalysisScore()
    });

  } catch (error) {
    console.error('Get video error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve video',
      message: error.message 
    });
  }
});

// @desc    Update video metadata
// @route   PUT /api/videos/:id
// @access  Private
router.put('/:id', protect, async (req, res) => {
  try {
    const { matchDetails, tags, isPublic } = req.body;
    
    const video = await Video.findOne({ 
      _id: req.params.id, 
      user: req.user._id 
    });

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    if (matchDetails) video.matchDetails = { ...video.matchDetails, ...matchDetails };
    if (tags !== undefined) video.tags = tags;
    if (isPublic !== undefined) video.isPublic = isPublic;

    await video.save();

    res.json({
      message: 'Video updated successfully',
      video: video.toObject()
    });

  } catch (error) {
    console.error('Update video error:', error);
    res.status(500).json({ 
      error: 'Failed to update video',
      message: error.message 
    });
  }
});

// @desc    Delete video
// @route   DELETE /api/videos/:id
// @access  Private
router.delete('/:id', protect, async (req, res) => {
  try {
    const video = await Video.findOne({ 
      _id: req.params.id, 
      user: req.user._id 
    });

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Delete from Google Cloud Storage
    try {
      await googleCloudService.deleteVideo(video.cloudStoragePath);
    } catch (error) {
      console.warn('Failed to delete video from storage:', error.message);
    }

    // Delete from database
    await Video.findByIdAndDelete(req.params.id);

    // Update user stats
    if (req.user.stats.totalVideosUploaded > 0) {
      req.user.stats.totalVideosUploaded -= 1;
      await req.user.save();
    }

    res.json({ message: 'Video deleted successfully' });

  } catch (error) {
    console.error('Delete video error:', error);
    res.status(500).json({ 
      error: 'Failed to delete video',
      message: error.message 
    });
  }
});

// @desc    Get analysis progress
// @route   GET /api/videos/:id/progress
// @access  Private
router.get('/:id/progress', protect, async (req, res) => {
  try {
    const video = await Video.findOne({ 
      _id: req.params.id, 
      user: req.user._id 
    }).select('analysis.status analysis.videoIntelligenceJobId processingLogs');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    let progress = 0;
    if (video.analysis.status === 'processing' && video.analysis.videoIntelligenceJobId) {
      try {
        const results = await googleCloudService.getAnalysisResults(video.analysis.videoIntelligenceJobId);
        progress = results.progress || 0;
      } catch (error) {
        console.warn('Failed to get progress:', error.message);
      }
    } else if (video.analysis.status === 'completed') {
      progress = 100;
    }

    res.json({
      status: video.analysis.status,
      progress,
      logs: video.processingLogs
    });

  } catch (error) {
    console.error('Get progress error:', error);
    res.status(500).json({ 
      error: 'Failed to get analysis progress',
      message: error.message 
    });
  }
});

// @desc    Get video statistics
// @route   GET /api/videos/stats
// @access  Private
router.get('/stats/overview', protect, async (req, res) => {
  try {
    const userId = req.user._id;
    
    const stats = await Video.aggregate([
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
          averageAccuracy: { $avg: '$analysis.performance.accuracy' }
        }
      }
    ]);

    const recentVideos = await Video.find({ user: userId })
      .sort({ createdAt: -1 })
      .limit(5)
      .select('originalName analysis.status analysis.performance.overallRating createdAt');

    res.json({
      overview: stats[0] || {
        totalVideos: 0,
        completedAnalyses: 0,
        averageRating: 0,
        totalShots: 0,
        averageAccuracy: 0
      },
      recentVideos
    });

  } catch (error) {
    console.error('Get stats error:', error);
    res.status(500).json({ 
      error: 'Failed to retrieve statistics',
      message: error.message 
    });
  }
});

module.exports = router;