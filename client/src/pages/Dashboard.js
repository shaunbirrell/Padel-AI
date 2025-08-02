import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { 
  Play, 
  Clock, 
  TrendingUp, 
  BarChart3, 
  Upload, 
  Eye,
  Calendar,
  FileVideo
} from 'lucide-react';
import axios from 'axios';
import toast from 'react-hot-toast';

const Dashboard = () => {
  const [videos, setVideos] = useState([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    totalVideos: 0,
    analyzedVideos: 0,
    totalDuration: 0,
    averageRallyLength: 0
  });

  useEffect(() => {
    fetchVideos();
  }, []);

  const fetchVideos = async () => {
    try {
      const response = await axios.get('/api/videos');
      const videoList = response.data.videos || [];
      setVideos(videoList);

      // Calculate stats
      const analyzedVideos = videoList.filter(v => v.analysisStatus === 'completed').length;
      const totalDuration = videoList.reduce((sum, v) => sum + (v.duration || 0), 0);
      
      setStats({
        totalVideos: videoList.length,
        analyzedVideos,
        totalDuration,
        averageRallyLength: analyzedVideos > 0 ? Math.round(totalDuration / analyzedVideos) : 0
      });
    } catch (error) {
      console.error('Error fetching videos:', error);
      toast.error('Failed to load videos');
    } finally {
      setLoading(false);
    }
  };

  const formatDuration = (seconds) => {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    
    if (hours > 0) {
      return `${hours}h ${minutes}m ${secs}s`;
    } else if (minutes > 0) {
      return `${minutes}m ${secs}s`;
    } else {
      return `${secs}s`;
    }
  };

  const formatFileSize = (bytes) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'completed':
        return 'bg-green-100 text-green-800';
      case 'processing':
        return 'bg-yellow-100 text-yellow-800';
      case 'failed':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-96">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-600"></div>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="text-center">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          Welcome to Padel Analysis
        </h1>
        <p className="text-xl text-gray-600 max-w-2xl mx-auto">
          Upload your padel match videos and get AI-powered insights to improve your game
        </p>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="stat-card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-primary-600">Total Videos</p>
              <p className="text-3xl font-bold text-primary-900">{stats.totalVideos}</p>
            </div>
            <FileVideo className="h-8 w-8 text-primary-600" />
          </div>
        </div>

        <div className="stat-card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-primary-600">Analyzed Videos</p>
              <p className="text-3xl font-bold text-primary-900">{stats.analyzedVideos}</p>
            </div>
            <BarChart3 className="h-8 w-8 text-primary-600" />
          </div>
        </div>

        <div className="stat-card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-primary-600">Total Duration</p>
              <p className="text-3xl font-bold text-primary-900">
                {formatDuration(stats.totalDuration)}
              </p>
            </div>
            <Clock className="h-8 w-8 text-primary-600" />
          </div>
        </div>

        <div className="stat-card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-primary-600">Avg Rally Length</p>
              <p className="text-3xl font-bold text-primary-900">
                {stats.averageRallyLength}s
              </p>
            </div>
            <TrendingUp className="h-8 w-8 text-primary-600" />
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="card">
        <h2 className="text-2xl font-bold text-gray-900 mb-6">Quick Actions</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <Link
            to="/upload"
            className="flex items-center justify-center space-x-3 p-6 border-2 border-dashed border-primary-300 rounded-xl hover:border-primary-500 hover:bg-primary-50 transition-colors duration-200"
          >
            <Upload className="h-8 w-8 text-primary-600" />
            <span className="text-lg font-medium text-primary-600">Upload New Video</span>
          </Link>
          
          <div className="flex items-center justify-center space-x-3 p-6 bg-gray-50 rounded-xl">
            <BarChart3 className="h-8 w-8 text-gray-400" />
            <span className="text-lg font-medium text-gray-500">View Analytics</span>
          </div>
        </div>
      </div>

      {/* Recent Videos */}
      <div className="card">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-2xl font-bold text-gray-900">Recent Videos</h2>
          {videos.length > 0 && (
            <Link
              to="/upload"
              className="btn-primary"
            >
              Upload More
            </Link>
          )}
        </div>

        {videos.length === 0 ? (
          <div className="text-center py-12">
            <FileVideo className="h-16 w-16 text-gray-400 mx-auto mb-4" />
            <h3 className="text-lg font-medium text-gray-900 mb-2">No videos yet</h3>
            <p className="text-gray-600 mb-6">Upload your first padel match video to get started</p>
            <Link to="/upload" className="btn-primary">
              Upload Your First Video
            </Link>
          </div>
        ) : (
          <div className="space-y-4">
            {videos.slice(0, 5).map((video) => (
              <div
                key={video.id}
                className="flex items-center justify-between p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors duration-200"
              >
                <div className="flex items-center space-x-4">
                  <div className="bg-primary-100 p-2 rounded-lg">
                    <Play className="h-5 w-5 text-primary-600" />
                  </div>
                  <div>
                    <h3 className="font-medium text-gray-900">{video.originalName}</h3>
                    <div className="flex items-center space-x-4 text-sm text-gray-500">
                      <span>{formatFileSize(video.size)}</span>
                      <span>•</span>
                      <span>
                        <Calendar className="h-4 w-4 inline mr-1" />
                        {new Date(video.uploadDate).toLocaleDateString()}
                      </span>
                    </div>
                  </div>
                </div>
                
                <div className="flex items-center space-x-3">
                  <span className={`px-3 py-1 rounded-full text-xs font-medium ${getStatusColor(video.analysisStatus)}`}>
                    {video.analysisStatus}
                  </span>
                  
                  {video.analysisStatus === 'completed' && (
                    <Link
                      to={`/analysis/${video.id}`}
                      className="btn-secondary text-sm"
                    >
                      <Eye className="h-4 w-4 mr-1" />
                      View Analysis
                    </Link>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default Dashboard;