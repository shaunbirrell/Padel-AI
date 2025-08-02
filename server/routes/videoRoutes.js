const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs').promises;
const { v4: uuidv4 } = require('uuid');
const router = express.Router();

// Configure multer for video uploads
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = path.join(__dirname, '../../uploads');
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error);
    }
  },
  filename: (req, file, cb) => {
    const uniqueName = `${uuidv4()}-${Date.now()}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  }
});

const fileFilter = (req, file, cb) => {
  // Accept video files only
  const allowedTypes = ['video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm'];
  
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only video files are allowed.'), false);
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: 500 * 1024 * 1024, // 500MB limit
  }
});

// Upload video
router.post('/upload', upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No video file provided' });
    }

    const videoData = {
      id: uuidv4(),
      originalName: req.file.originalname,
      filename: req.file.filename,
      path: req.file.path,
      size: req.file.size,
      mimetype: req.file.mimetype,
      uploadDate: new Date(),
      status: 'uploaded',
      analysisStatus: 'pending'
    };

    // In a real application, you would save this to a database
    // For now, we'll store it in memory (not recommended for production)
    if (!global.videos) global.videos = new Map();
    global.videos.set(videoData.id, videoData);

    res.status(201).json({
      message: 'Video uploaded successfully',
      video: {
        id: videoData.id,
        originalName: videoData.originalName,
        size: videoData.size,
        uploadDate: videoData.uploadDate,
        status: videoData.status
      }
    });
  } catch (error) {
    console.error('Upload error:', error);
    res.status(500).json({ error: 'Failed to upload video' });
  }
});

// Get all videos
router.get('/', async (req, res) => {
  try {
    if (!global.videos) global.videos = new Map();
    
    const videos = Array.from(global.videos.values()).map(video => ({
      id: video.id,
      originalName: video.originalName,
      size: video.size,
      uploadDate: video.uploadDate,
      status: video.status,
      analysisStatus: video.analysisStatus
    }));

    res.json({ videos });
  } catch (error) {
    console.error('Error fetching videos:', error);
    res.status(500).json({ error: 'Failed to fetch videos' });
  }
});

// Get specific video
router.get('/:id', async (req, res) => {
  try {
    if (!global.videos) global.videos = new Map();
    
    const video = global.videos.get(req.params.id);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    res.json({
      id: video.id,
      originalName: video.originalName,
      size: video.size,
      uploadDate: video.uploadDate,
      status: video.status,
      analysisStatus: video.analysisStatus,
      url: `/uploads/${video.filename}`
    });
  } catch (error) {
    console.error('Error fetching video:', error);
    res.status(500).json({ error: 'Failed to fetch video' });
  }
});

// Delete video
router.delete('/:id', async (req, res) => {
  try {
    if (!global.videos) global.videos = new Map();
    
    const video = global.videos.get(req.params.id);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Delete file from filesystem
    try {
      await fs.unlink(video.path);
    } catch (fileError) {
      console.warn('Could not delete file:', fileError.message);
    }

    // Remove from memory
    global.videos.delete(req.params.id);

    res.json({ message: 'Video deleted successfully' });
  } catch (error) {
    console.error('Error deleting video:', error);
    res.status(500).json({ error: 'Failed to delete video' });
  }
});

module.exports = router;