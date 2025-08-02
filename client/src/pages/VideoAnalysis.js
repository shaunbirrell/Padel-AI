import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { 
  Play, 
  Clock, 
  TrendingUp, 
  Target, 
  BarChart3,
  Eye,
  Calendar,
  ArrowLeft
} from 'lucide-react';
import { Link } from 'react-router-dom';
import ReactPlayer from 'react-player';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  LineChart,
  Line
} from 'recharts';
import axios from 'axios';
import toast from 'react-hot-toast';

const VideoAnalysis = () => {
  const { videoId } = useParams();
  const [video, setVideo] = useState(null);
  const [analysis, setAnalysis] = useState(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('overview');

  useEffect(() => {
    fetchVideoAndAnalysis();
  }, [videoId]);

  const fetchVideoAndAnalysis = async () => {
    try {
      // Fetch video details
      const videoResponse = await axios.get(`/api/videos/${videoId}`);
      setVideo(videoResponse.data);

      // Fetch analysis results
      const analysisResponse = await axios.get(`/api/analysis/${videoId}`);
      setAnalysis(analysisResponse.data.analysis);
    } catch (error) {
      console.error('Error fetching data:', error);
      toast.error('Failed to load analysis data');
    } finally {
      setLoading(false);
    }
  };

  const formatDuration = (seconds) => {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);
    
    if (hours > 0) {
      return `${hours}h ${minutes}m ${secs}s`;
    } else if (minutes > 0) {
      return `${minutes}m ${secs}s`;
    } else {
      return `${secs}s`;
    }
  };

  const formatTime = (seconds) => {
    const minutes = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
  };

  const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6'];

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-96">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-600"></div>
      </div>
    );
  }

  if (!video || !analysis) {
    return (
      <div className="text-center py-12">
        <h2 className="text-2xl font-bold text-gray-900 mb-4">Analysis Not Found</h2>
        <p className="text-gray-600 mb-6">The requested analysis could not be found.</p>
        <Link to="/" className="btn-primary">
          <ArrowLeft className="h-4 w-4 mr-2" />
          Back to Dashboard
        </Link>
      </div>
    );
  }

  const shotTypeData = [
    { name: 'Volleys', value: analysis.summary.volleyCount, color: '#3b82f6' },
    { name: 'Serves', value: analysis.summary.serveCount, color: '#10b981' },
    { name: 'Rallies', value: analysis.summary.rallyCount, color: '#f59e0b' },
  ].filter(item => item.value > 0);

  const shotTimelineData = analysis.shots.map((shot, index) => ({
    shot: index + 1,
    duration: shot.duration,
    time: parseFloat(shot.startTime)
  }));

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <Link to="/" className="flex items-center text-gray-600 hover:text-gray-900 mb-2">
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back to Dashboard
          </Link>
          <h1 className="text-3xl font-bold text-gray-900">{video.originalName}</h1>
          <p className="text-gray-600">
            Analyzed on {new Date(video.analysisDate).toLocaleDateString()}
          </p>
        </div>
        <div className="text-right">
          <div className="text-2xl font-bold text-primary-600">
            {formatDuration(analysis.summary.totalDuration)}
          </div>
          <div className="text-sm text-gray-500">Total Duration</div>
        </div>
      </div>

      {/* Video Player */}
      <div className="card">
        <h2 className="text-xl font-bold text-gray-900 mb-4">Match Video</h2>
        <div className="aspect-video bg-black rounded-lg overflow-hidden">
          <ReactPlayer
            url={video.url}
            width="100%"
            height="100%"
            controls
            playing={false}
            className="react-player"
          />
        </div>
      </div>

      {/* Analysis Tabs */}
      <div className="card">
        <div className="border-b border-gray-200 mb-6">
          <nav className="flex space-x-8">
            {[
              { id: 'overview', label: 'Overview', icon: BarChart3 },
              { id: 'shots', label: 'Shot Analysis', icon: Target },
              { id: 'timeline', label: 'Timeline', icon: Clock },
              { id: 'insights', label: 'Insights', icon: TrendingUp }
            ].map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
                    activeTab === tab.id
                      ? 'border-primary-500 text-primary-600'
                      : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                  }`}
                >
                  <Icon className="h-4 w-4" />
                  <span>{tab.label}</span>
                </button>
              );
            })}
          </nav>
        </div>

        {/* Tab Content */}
        {activeTab === 'overview' && (
          <div className="space-y-6">
            {/* Summary Stats */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <div className="stat-card">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium text-primary-600">Total Shots</p>
                    <p className="text-3xl font-bold text-primary-900">{analysis.summary.shotCount}</p>
                  </div>
                  <Target className="h-8 w-8 text-primary-600" />
                </div>
              </div>

              <div className="stat-card">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium text-primary-600">Volleys</p>
                    <p className="text-3xl font-bold text-primary-900">{analysis.summary.volleyCount}</p>
                  </div>
                  <TrendingUp className="h-8 w-8 text-primary-600" />
                </div>
              </div>

              <div className="stat-card">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium text-primary-600">Serves</p>
                    <p className="text-3xl font-bold text-primary-900">{analysis.summary.serveCount}</p>
                  </div>
                  <Play className="h-8 w-8 text-primary-600" />
                </div>
              </div>

              <div className="stat-card">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium text-primary-600">Rallies</p>
                    <p className="text-3xl font-bold text-primary-900">{analysis.summary.rallyCount}</p>
                  </div>
                  <BarChart3 className="h-8 w-8 text-primary-600" />
                </div>
              </div>
            </div>

            {/* Shot Type Distribution */}
            {shotTypeData.length > 0 && (
              <div>
                <h3 className="text-lg font-semibold text-gray-900 mb-4">Shot Type Distribution</h3>
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  <ResponsiveContainer width="100%" height={300}>
                    <PieChart>
                      <Pie
                        data={shotTypeData}
                        cx="50%"
                        cy="50%"
                        labelLine={false}
                        label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                        outerRadius={80}
                        fill="#8884d8"
                        dataKey="value"
                      >
                        {shotTypeData.map((entry, index) => (
                          <Cell key={`cell-${index}`} fill={entry.color} />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>

                  <div className="space-y-3">
                    {shotTypeData.map((item, index) => (
                      <div key={item.name} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                        <div className="flex items-center space-x-3">
                          <div 
                            className="w-4 h-4 rounded-full" 
                            style={{ backgroundColor: item.color }}
                          ></div>
                          <span className="font-medium">{item.name}</span>
                        </div>
                        <span className="text-lg font-bold">{item.value}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {activeTab === 'shots' && (
          <div className="space-y-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Detailed Shot Analysis</h3>
            
            {/* Shot Timeline Chart */}
            <div>
              <h4 className="text-md font-medium text-gray-700 mb-3">Shot Duration Timeline</h4>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={shotTimelineData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="shot" />
                  <YAxis />
                  <Tooltip 
                    formatter={(value) => [`${value}s`, 'Duration']}
                    labelFormatter={(label) => `Shot ${label}`}
                  />
                  <Line 
                    type="monotone" 
                    dataKey="duration" 
                    stroke="#3b82f6" 
                    strokeWidth={2}
                    dot={{ fill: '#3b82f6', strokeWidth: 2, r: 4 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>

            {/* Shot Details Table */}
            <div>
              <h4 className="text-md font-medium text-gray-700 mb-3">Shot Details</h4>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Shot #
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Start Time
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Duration
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Type
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {analysis.shots.slice(0, 10).map((shot, index) => (
                      <tr key={shot.id} className="hover:bg-gray-50">
                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                          {shot.id}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                          {formatTime(shot.startTime)}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                          {shot.duration}s
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-blue-100 text-blue-800">
                            Shot
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'timeline' && (
          <div className="space-y-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Match Timeline</h3>
            
            <div className="space-y-4">
              {analysis.shots.map((shot, index) => (
                <div key={shot.id} className="flex items-center space-x-4 p-4 bg-gray-50 rounded-lg">
                  <div className="flex-shrink-0 w-12 h-12 bg-primary-100 rounded-full flex items-center justify-center">
                    <span className="text-sm font-bold text-primary-600">{shot.id}</span>
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <span className="font-medium text-gray-900">Shot {shot.id}</span>
                      <span className="text-sm text-gray-500">{shot.duration}s</span>
                    </div>
                    <div className="text-sm text-gray-600">
                      {formatTime(shot.startTime)} - {formatTime(shot.endTime)}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {activeTab === 'insights' && (
          <div className="space-y-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Performance Insights</h3>
            
            {/* Key Insights */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="card bg-green-50 border-green-200">
                <h4 className="text-lg font-semibold text-green-900 mb-3">🎯 Strengths</h4>
                <ul className="space-y-2 text-green-800">
                  <li>• Consistent shot placement</li>
                  <li>• Good volley technique</li>
                  <li>• Effective serve strategy</li>
                </ul>
              </div>

              <div className="card bg-blue-50 border-blue-200">
                <h4 className="text-lg font-semibold text-blue-900 mb-3">📈 Areas for Improvement</h4>
                <ul className="space-y-2 text-blue-800">
                  <li>• Work on backhand consistency</li>
                  <li>• Improve court positioning</li>
                  <li>• Enhance shot variety</li>
                </ul>
              </div>
            </div>

            {/* Recommendations */}
            <div className="card bg-purple-50 border-purple-200">
              <h4 className="text-lg font-semibold text-purple-900 mb-3">💡 Training Recommendations</h4>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="p-4 bg-white rounded-lg">
                  <h5 className="font-semibold text-purple-800 mb-2">Volley Practice</h5>
                  <p className="text-sm text-purple-700">Focus on net play and quick reactions</p>
                </div>
                <div className="p-4 bg-white rounded-lg">
                  <h5 className="font-semibold text-purple-800 mb-2">Serve Technique</h5>
                  <p className="text-sm text-purple-700">Improve serve accuracy and power</p>
                </div>
                <div className="p-4 bg-white rounded-lg">
                  <h5 className="font-semibold text-purple-800 mb-2">Rally Consistency</h5>
                  <p className="text-sm text-purple-700">Work on maintaining long rallies</p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default VideoAnalysis;