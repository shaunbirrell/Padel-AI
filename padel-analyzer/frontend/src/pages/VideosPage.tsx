import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { getVideos, VideoMetadata } from '../services/api';
import { Film, Clock, CheckCircle, AlertCircle, Loader, Play } from 'lucide-react';

const VideosPage: React.FC = () => {
  const [videos, setVideos] = useState<VideoMetadata[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchVideos();
  }, []);

  const fetchVideos = async () => {
    try {
      setLoading(true);
      const response = await getVideos();
      setVideos(response.videos);
    } catch (err) {
      setError('Failed to load videos');
    } finally {
      setLoading(false);
    }
  };

  const getStatusBadge = (status: VideoMetadata['status']) => {
    const statusConfig = {
      uploaded: { className: 'badge-info', icon: Clock, text: 'Uploaded' },
      analyzing: { className: 'badge-warning', icon: Loader, text: 'Analyzing' },
      completed: { className: 'badge-success', icon: CheckCircle, text: 'Completed' },
      failed: { className: 'badge-danger', icon: AlertCircle, text: 'Failed' },
    };

    const config = statusConfig[status];
    const Icon = config.icon;

    return (
      <span className={`badge ${config.className}`}>
        <Icon className="w-3 h-3" />
        {config.text}
      </span>
    );
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  if (loading) {
    return (
      <div className="loading-container">
        <div className="loading-spinner" />
        <p className="text-secondary">Loading your videos...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="card border-red-200 bg-red-50">
        <div className="flex items-center gap-2 text-red-700">
          <AlertCircle className="w-5 h-5" />
          <p className="font-semibold">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="fade-in">
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-3xl font-bold">My Videos</h1>
        <Link to="/upload" className="btn btn-primary">
          <Film className="w-5 h-5" />
          Upload New Video
        </Link>
      </div>

      {videos.length === 0 ? (
        <div className="card text-center py-12">
          <Film className="w-16 h-16 mx-auto mb-4 text-gray-400" />
          <h2 className="text-xl font-semibold mb-2">No videos uploaded yet</h2>
          <p className="text-secondary mb-6">
            Upload your first Padel match video to get started with analysis
          </p>
          <Link to="/upload" className="btn btn-primary">
            Upload Your First Video
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-6">
          {videos.map((video) => (
            <div key={video.video_id} className="card hover:shadow-lg transition-shadow">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <div 
                    className="w-16 h-16 rounded-lg flex items-center justify-center"
                    style={{ backgroundColor: '#f0fdf4' }}
                  >
                    <Film className="w-8 h-8" style={{ color: 'var(--primary-color)' }} />
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold mb-1">{video.filename}</h3>
                    <p className="text-sm text-secondary">
                      Uploaded on {formatDate(video.upload_time)}
                    </p>
                  </div>
                </div>
                
                <div className="flex items-center gap-4">
                  {getStatusBadge(video.status)}
                  
                  {video.status === 'completed' && (
                    <Link 
                      to={`/analysis/${video.video_id}`} 
                      className="btn btn-primary"
                    >
                      <Play className="w-4 h-4" />
                      View Analysis
                    </Link>
                  )}
                  
                  {video.status === 'analyzing' && (
                    <button className="btn btn-outline" disabled>
                      <Loader className="w-4 h-4 spinner" />
                      Processing...
                    </button>
                  )}
                  
                  {video.status === 'uploaded' && (
                    <button className="btn btn-secondary">
                      Start Analysis
                    </button>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default VideosPage;